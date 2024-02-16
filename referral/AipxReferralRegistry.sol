// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AipxReferralRegistry is Initializable, OwnableUpgradeable {
    mapping(address => address) public referredBy;
    mapping(address => uint256) public referredCount;

    address public controller;

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    // =============== USER FUNCTIONS ===============

    function setReferrer(address _trader, address _referrer) external {
        require(msg.sender == controller, "AipxReferralRegistry::setReferrer: !controller");
        require(_trader != address(0), "AipxReferralRegistry::setReferrer: invalid trader address");
        require(_referrer != address(0), "AipxReferralRegistry::setReferrer: invalid referrer address");
        require(_trader != _referrer, "AipxReferralRegistry::setReferrer: can not set yourself");

        require(referredBy[_trader] == address(0), "AipxReferralRegistry::setReferrer: referrer already exists");
        referredBy[_trader] = _referrer;
        referredCount[_referrer]++;

        emit ReferrerSet(_trader, _referrer);
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "AipxReferralRegistryController::setUpdater: invalid address");
        controller = _controller;
        emit ControllerSet(controller);
    }


    // ===============  EVENTS ===============

    event ReferrerSet(address indexed trader, address indexed referrer);
    event ControllerSet(address indexed updater);
}
