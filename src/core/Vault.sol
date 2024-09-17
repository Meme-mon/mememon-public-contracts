// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from "src/libraries/access/extensions/AccessControlDefaultAdminRules.sol";
import {ERC20} from "src/libraries/token/ERC20/ERC20.sol";
import {SafeERC20} from "src/libraries/token/ERC20/utils/SafeERC20.sol";

contract Vault is AccessControlDefaultAdminRules {
    using SafeERC20 for ERC20;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    constructor(address defaultAdmin) AccessControlDefaultAdminRules(1 days, defaultAdmin) {}

    function withdraw(address token, uint256 amount) external onlyRole(MODERATOR_ROLE) {
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    function withdrawAll(address token) external onlyRole(MODERATOR_ROLE) {
        ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }
}
