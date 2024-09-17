// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from "src/libraries/access/extensions/AccessControlDefaultAdminRules.sol";
import {ERC20} from "src/libraries/token/ERC20/ERC20.sol";
import {SafeERC20} from "src/libraries/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";

import {IGameAssets} from "src/core/nfts/interfaces/IGameAssets.sol";
import {ReferralManager} from "src/core/ReferralManager.sol";

contract BuyEgg is AccessControlDefaultAdminRules, ReentrancyGuard {
    using SafeERC20 for ERC20;

    error BuyEgg_TokenNotAccepted(address token);
    error BuyEgg_InvalidAmount();
    error BuyEgg_InvalidReferralCode();
    error BuyEgg_InvalidEggPrice(uint256 eggId);

    mapping(uint256 eggId => uint256 eggPrice) private s_eggPrices;
    mapping(address token => bool) private s_isAcceptedToken;
    address[] private s_acceptedTokens;
    address private s_vault;
    address private s_treasury;
    address private s_referralManager;

    address private immutable i_egg;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    constructor(address defaultAdmin, address vault, address treasury, address egg, address referralManager)
        AccessControlDefaultAdminRules(1 days, defaultAdmin)
    {
        s_vault = vault;
        s_treasury = treasury;
        i_egg = egg;
        s_referralManager = referralManager;
    }

    event BoughtEgg(address indexed token, uint256 indexed eggId, uint256 eggAmount, uint256 tokenAmount);
    event BoughtEggWithRefCode(
        address indexed token, uint256 indexed eggId, string indexed refCode, uint256 eggAmount, uint256 tokenAmount
    );

    function setAcceptedToken(address token, bool isAccepted) external onlyRole(MODERATOR_ROLE) {
        s_isAcceptedToken[token] = isAccepted;
        s_acceptedTokens.push(token);
    }

    function removeAcceptedToken(address token) external onlyRole(MODERATOR_ROLE) {
        if (!s_isAcceptedToken[token]) {
            revert BuyEgg_TokenNotAccepted(token);
        }

        s_isAcceptedToken[token] = false;

        for (uint256 i = 0; i < s_acceptedTokens.length; i++) {
            if (s_acceptedTokens[i] == token) {
                s_acceptedTokens[i] = s_acceptedTokens[s_acceptedTokens.length - 1];
                s_acceptedTokens.pop();
                break;
            }
        }
    }

    function setEggPrice(uint256 eggId, uint256 price) external onlyRole(MODERATOR_ROLE) {
        s_eggPrices[eggId] = price;
    }

    function setVault(address vault) external onlyRole(MODERATOR_ROLE) {
        s_vault = vault;
    }

    function setTreasury(address treasury) external onlyRole(MODERATOR_ROLE) {
        s_treasury = treasury;
    }

    function setReferralManager(address referralManager) external onlyRole(MODERATOR_ROLE) {
        s_referralManager = referralManager;
    }

    function buyEgg(address token, uint256 eggId, uint256 eggAmount) external nonReentrant {
        _checkAcceptedToken(token);
        _checkEggPrice(eggId);
        _checkAmount(eggAmount);

        uint256 totalTokenAmount = _calculateTokenAmount(token, eggId, eggAmount);
        uint256 vaultAmount = (totalTokenAmount * 90) / 100; // 90%
        uint256 treasuryAmount = totalTokenAmount - vaultAmount; // 10%

        ERC20(token).safeTransferFrom(msg.sender, address(this), totalTokenAmount);

        ERC20(token).safeTransfer(s_vault, vaultAmount);
        ERC20(token).safeTransfer(s_treasury, treasuryAmount);

        IGameAssets(i_egg).mint(msg.sender, eggId, eggAmount, "");

        emit BoughtEgg(token, eggId, eggAmount, totalTokenAmount);
    }

    function buyEggWithRefCode(address token, uint256 eggId, uint256 eggAmount, string memory refCode)
        external
        nonReentrant
    {
        _checkAcceptedToken(token);
        _checkEggPrice(eggId);
        _checkAmount(eggAmount);

        uint256 totalTokenAmount = _calculateTokenAmount(token, eggId, eggAmount);
        uint256 vaultAmount = (totalTokenAmount * 90) / 100; // 90% - fixed

        uint256 referralPercentage = ReferralManager(s_referralManager).getReferralPercentage(refCode);

        uint256 treasuryAmount = (totalTokenAmount * (10 - referralPercentage)) / 100;
        uint256 refCodeAmount = (totalTokenAmount * referralPercentage) / 100;

        ERC20(token).safeTransferFrom(msg.sender, address(this), totalTokenAmount);

        ERC20(token).safeTransfer(s_vault, vaultAmount);

        if (treasuryAmount > 0) ERC20(token).safeTransfer(s_treasury, treasuryAmount);

        ERC20(token).safeTransfer(s_referralManager, refCodeAmount);

        ReferralManager(s_referralManager).addBalance(token, refCode, refCodeAmount, msg.sender);
        IGameAssets(i_egg).mint(msg.sender, eggId, eggAmount, "");

        emit BoughtEggWithRefCode(token, eggId, refCode, eggAmount, totalTokenAmount);
    }

    function _getTokenDecimal(address token) internal view returns (uint8) {
        return ERC20(token).decimals();
    }

    function _checkAcceptedToken(address token) internal view {
        if (!s_isAcceptedToken[token]) revert BuyEgg_TokenNotAccepted(token);
    }

    function _checkEggPrice(uint256 eggId) internal view {
        if (s_eggPrices[eggId] == 0) revert BuyEgg_InvalidEggPrice(eggId);
    }

    function _calculateTokenAmount(address token, uint256 eggId, uint256 eggAmount) internal view returns (uint256) {
        return eggAmount * (s_eggPrices[eggId] * 10 ** _getTokenDecimal(token));
    }

    function _checkAmount(uint256 eggAmount) internal pure {
        if (eggAmount <= 0) revert BuyEgg_InvalidAmount();
    }

    function getAcceptedToken(address token) external view returns (bool) {
        return s_isAcceptedToken[token];
    }

    function getAcceptedTokens() external view returns (address[] memory) {
        return s_acceptedTokens;
    }

    function getEggPrice(uint256 eggId) external view returns (uint256) {
        return s_eggPrices[eggId];
    }

    function getVault() external view returns (address) {
        return s_vault;
    }

    function getTreasury() external view returns (address) {
        return s_treasury;
    }

    function getReferralManager() external view returns (address) {
        return s_referralManager;
    }
}
