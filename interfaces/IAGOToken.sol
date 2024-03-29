// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAGOToken is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}
