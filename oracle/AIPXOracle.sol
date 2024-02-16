// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

contract AIPXOracle {
    uint256 private constant PRECISION = 1e6;

    address public updater;
    uint256 public lastTWAP;

    IPriceFeed public priceFeed;

    constructor(address _priceFeed, address _updater) {
        require(_priceFeed != address(0), "AIPXOracle::initialize: invalid address");
        require(_updater != address(0), "AIPXOracle::initialize: invalid address");
        
        priceFeed = IPriceFeed(_priceFeed);
        updater = _updater;
        lastTWAP = priceFeed.currentTWAP();
    }


    // =============== VIEW FUNCTIONS ===============

    function getCurrentTWAP() public view returns (uint256) {
        return priceFeed.currentTWAP();
    }


    // =============== USER FUNCTIONS ===============

    function update() external {
        require(msg.sender == updater, "AIPXOracle::updatePrice: !updater");
        priceFeed.update();
        lastTWAP = priceFeed.currentTWAP();
        emit PriceUpdated(block.timestamp, lastTWAP);
    }


    // ===============  EVENTS ===============
    event PriceUpdated(uint256 timestamp, uint256 price);
}

