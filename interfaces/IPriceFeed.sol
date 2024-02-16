// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

interface IPriceFeed {
    function update() external;
    function currentTWAP () external view returns (uint256);
}
