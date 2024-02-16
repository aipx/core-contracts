// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAIPXStake} from "../interfaces/IAIPXStake.sol";
import {IBurnableERC20} from "../interfaces/IBurnableERC20.sol";

/**
 * @notice Contract to stake AIPX token and earn AGO reward.
 */
contract AIPXStake is Initializable, OwnableUpgradeable, IAIPXStake {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    uint8 constant VERSION = 3;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 cooldowns;
    }

    uint256 private constant ACC_REWARD_PRECISION = 1e12;
    uint256 private constant MAX_REWARD_PER_SECOND = 1 ether;
    uint256 private constant MAX_BOOSTED_REWARD_PER_SECOND = 1 ether;

    //== UNUSED: keep for frontend
    uint256 public constant COOLDOWN_SECONDS = 0;
    uint256 public constant UNSTAKE_WINDOWN = 0;
    //===============================

    uint256 public constant STAKING_TAX_PRECISION = 1000;

    IBurnableERC20 public AIPX;
    IERC20 public AGO;

    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;

    mapping(address => UserInfo) public userInfo;

    address public booster;
    uint256 public boostedRewardPerSecond;
    uint256 public boostedRewardEndTime;

    address public auctionTreasury;

    uint256 public stakingTax;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Called by the proxy contract
     */
    function initialize(address _aipx, address _ago, uint256 _rewardPerSecond) external initializer {
        __Ownable_init();
        require(_rewardPerSecond <= MAX_REWARD_PER_SECOND, "> MAX_REWARD_PER_SECOND");
        require(_aipx != address(0), "Invalid AIPX address");
        require(_ago != address(0), "Invalid AGO address");
        AIPX = IBurnableERC20(_aipx);
        AGO = IERC20(_ago);
        rewardPerSecond = _rewardPerSecond;
    }


    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @dev Return the total rewards pending to claim by an staker
     * @param _to The user address
     * @return The rewards
     */
    function pendingReward(address _to) external view returns (uint256) {
        UserInfo storage user = userInfo[_to];
        uint256 aipxSupply = AIPX.balanceOf(address(this));
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && aipxSupply != 0) {
            uint256 time = block.timestamp - lastRewardTime;
            uint256 reward = time * rewardPerSecond;
            uint256 boostedReward = getBoostedReward();
            _accRewardPerShare += (((reward + boostedReward) * ACC_REWARD_PRECISION) / aipxSupply);
        }
        return ((user.amount * _accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt;
    }


    /* ========== PUBLIC FUNCTIONS ========== */

    /**
     * @dev Staked AIPX tokens, and start earning rewards
     * @param _to Address to stake to
     * @param _amount Amount to stake
     */
    function stake(address _to, uint256 _amount) external override {
        require(_amount != 0, "INVALID_AMOUNT");
        UserInfo storage user = userInfo[_to];
        update();

        if (user.amount != 0) {
            uint256 pending = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION - user.rewardDebt;
            if (pending != 0) {
                _safeTransferAGO(_to, pending);
                emit RewardsClaimed(msg.sender, _to, pending);
            }
        }

        uint256 _taxAmount = _amount * stakingTax / STAKING_TAX_PRECISION;
        uint256 _stakedAmount = _amount - _taxAmount;

        user.amount += _stakedAmount;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;

        AIPX.safeTransferFrom(msg.sender, address(this), _amount);
        AIPX.burn(_taxAmount);

        emit Staked(msg.sender, _to, _amount);
    }

    /**
     * @dev Unstake tokens, and stop earning rewards
     * @param _to Address to unstake to
     * @param _amount Amount to unstake
     */
    function unstake(address _to, uint256 _amount) external override {
        update();
        require(_amount != 0, "INVALID_AMOUNT");
        UserInfo storage user = userInfo[msg.sender];

        uint256 amountToUnstake = (_amount > user.amount) ? user.amount : _amount;
        uint256 pending = ((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION) - user.rewardDebt;

        user.amount -= amountToUnstake;
        user.rewardDebt = (user.amount * accRewardPerShare) / ACC_REWARD_PRECISION;

        if (pending != 0) {
            _safeTransferAGO(_to, pending);
            emit RewardsClaimed(msg.sender, _to, pending);
        }

        IERC20(AIPX).safeTransfer(_to, amountToUnstake);

        emit Unstaked(msg.sender, _to, amountToUnstake);
    }

    /**
     * @dev Activates the cooldown period to unstake
     * - It can't be called if the user is not staking
     */
    function cooldown() external override {
        // doing nothing
    }

    /**
     * @dev Deactivates the cooldown period
     * - It can't be called if the user not on cooldown time
     */
    function deactivateCooldown() external override {
        // doing nothing
    }

    /**
     * @dev Claims AGO rewards to the address `to`
     * @param _to Address to stake for
     */
    function claimRewards(address _to) external {
        update();
        UserInfo storage user = userInfo[msg.sender];

        uint256 accumulatedReward = uint256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        user.rewardDebt = accumulatedReward;

        if (_pendingReward != 0) {
            _safeTransferAGO(_to, _pendingReward);
            emit RewardsClaimed(msg.sender, _to, _pendingReward);
        }
    }


    /* ========== RESTRICTIVE FUNCTIONS ========== */

    /// @notice Sets boosted reward manager. Can only be called by the owner.
    /// @param _booster Address of booster.
    function setBooster(address _booster) public onlyOwner {
        require(_booster != address(0), "INVALID_ADDRESS");
        booster = _booster;
        emit BoosterSet(_booster);
    }

    /// @notice Sets the reward per second to be distributed. Only be called by the owner.
    /// @param _rewardPerSecond The amount of AGO to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        require(_rewardPerSecond <= MAX_REWARD_PER_SECOND, "> MAX_REWARD_PER_SECOND");
        update();
        rewardPerSecond = _rewardPerSecond;
        emit RewardPerSecondUpdated(_rewardPerSecond);
    }

    /// @notice Sets the boosted reward to be distributed. Can only be called by the booster.
    /// @param _boostedRewardPerSecond The boosted amount of AGO to be distributed per second.
    /// @param _duration  Distribute duration of boosted reward.
    function setBoostedReward(uint256 _boostedRewardPerSecond, uint256 _duration) public {
        require(msg.sender == booster, "CALLER_IS_NOT_BOOSTER");
        require(_boostedRewardPerSecond <= MAX_BOOSTED_REWARD_PER_SECOND, "> MAX_BOOSTED_REWARD_PER_SECOND");
        require(_duration > 0, "INVALID_DURATION");
        update();
        boostedRewardPerSecond = _boostedRewardPerSecond;
        boostedRewardEndTime = block.timestamp + _duration;

        emit BoostedRewardUpdated(boostedRewardPerSecond, block.timestamp, boostedRewardEndTime);
    }

    /// @notice Reserve an amount of AGO by sending it to auction treasury.
    function reserveAuctionFund(uint256 amount) external onlyOwner {
        AGO.safeTransfer(auctionTreasury, amount);
        emit AuctionFundReserved(amount);
    }

    /// @notice Sets the staking tax. Can only be called by the owner.
    function setStakingTax(uint256 tax) external onlyOwner {
        stakingTax = tax;
        emit StakingTaxSet(tax);
    }

    /// @notice Sets the auction treasury address. Can only be called by the owner.
    function setAuctionTreasury(address treasury) external onlyOwner {
        auctionTreasury = treasury;
        emit AuctionTreasurySet(treasury);
    }


    /* ========== INTERNAL FUNCTIONS ========== */

    function getBoostedReward() internal view returns (uint256) {
        uint256 boostedTime = block.timestamp <= boostedRewardEndTime ? block.timestamp : boostedRewardEndTime;
        uint256 duration = boostedTime > lastRewardTime ? boostedTime - lastRewardTime : 0;
        return duration * boostedRewardPerSecond;
    }

    function update() public {
        if (block.timestamp > lastRewardTime) {
            uint256 aipxSupply = AIPX.balanceOf(address(this));
            if (aipxSupply != 0) {
                uint256 time = block.timestamp - lastRewardTime;
                uint256 reward = time * rewardPerSecond;
                uint256 boostedReward = getBoostedReward();
                accRewardPerShare = accRewardPerShare + (((reward + boostedReward) * ACC_REWARD_PRECISION) / aipxSupply);
            }
            lastRewardTime = block.timestamp;
        }
    }

    // Safe AGO transfer function, just in case if rounding error causes pool to not have enough AGOs.
    function _safeTransferAGO(address _to, uint256 _amount) internal {
        require(AGO != IERC20(address(0)), "AGO not set");
        uint256 agoBalance = AGO.balanceOf(address(this));
        if (_amount > agoBalance) {
            AGO.safeTransfer(_to, agoBalance);
        } else {
            AGO.safeTransfer(_to, _amount);
        }
    }

    /* ========== EVENT ========== */

    event Staked(address indexed from, address indexed to, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);
    event BoosterSet(address booster);
    event RewardPerSecondUpdated(uint256 rewardPerSecond);
    event BoostedRewardUpdated(uint256 boostedRewardPerSecond, uint256 startTime, uint256 endTime);
    event AuctionFundReserved(uint256 amount);
    event StakingTaxSet(uint256 tax);
    event AuctionTreasurySet(address treasury);
}
