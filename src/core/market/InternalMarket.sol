// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Vault} from "src/core/Vault.sol";
import {ERC20} from "src/libraries/token/ERC20/ERC20.sol";
import {IERC20} from "src/libraries/token/ERC20/IERC20.sol";
import {SafeERC20} from "src/libraries/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "src/libraries/access/AccessControl.sol";
import {IInternalMarket} from "./interfaces/IInternalMarket.sol";
import {GameAssets} from "src/core/nfts/GameAssets.sol";
import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";

contract InternalMarket is IInternalMarket, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    Vault private immutable s_vault;
    GameAssets private immutable s_mememon;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    struct MememonPrice {
        uint256 mememonId;
        uint256 price;
    }

    MememonPrice[] private s_mememonPrices;
    mapping(uint256 mememonId => uint256 price) public s_mememonToPrice;
    mapping(uint256 mememmonId => bool isOnSale) public s_mememonOnSale;

    constructor(address vault, address mememonContract) {
        s_mememon = GameAssets(mememonContract);
        s_vault = Vault(vault);
        _grantRole(MODERATOR_ROLE, msg.sender);
    }

    // ========= Owner Functions
    function setMememonPrice(uint256 mememonId, uint256 price) public onlyRole(MODERATOR_ROLE) {
        _validateMememonId(mememonId);
        s_mememonPrices.push(MememonPrice(mememonId, price));
        s_mememonToPrice[mememonId] = price;
        s_mememonOnSale[mememonId] = true;
    }

    function setMememonPrices(uint256[] memory mememonIds, uint256[] memory prices) public onlyRole(MODERATOR_ROLE) {
        if (mememonIds.length != prices.length) {
            revert IInternalMarket__InvalidInputLength();
        }

        for (uint256 i; i < mememonIds.length; i++) {
            setMememonPrice(mememonIds[i], prices[i]);
        }
    }

    function changeMememonSaleStatus(uint256 mememonId, bool onSale) public onlyRole(MODERATOR_ROLE) {
        s_mememonOnSale[mememonId] = onSale;
    }

    function removeMememonPrice(uint256 mememonId) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i; i < s_mememonPrices.length; i++) {
            if (s_mememonPrices[i].mememonId == mememonId) {
                s_mememonPrices[i] = s_mememonPrices[s_mememonPrices.length - 1];
                s_mememonPrices.pop();
                break;
            }
        }
        s_mememonToPrice[mememonId] = 0;
        s_mememonOnSale[mememonId] = false;
    }

    function removeMememonPrices() public onlyRole(MODERATOR_ROLE) {
        for (uint256 i; i < s_mememonPrices.length; i++) {
            s_mememonToPrice[s_mememonPrices[i].mememonId] = 0;
            s_mememonOnSale[s_mememonPrices[i].mememonId] = false;
        }
        delete s_mememonPrices;
    }

    function sellMememon(uint256 mememonId, uint256 amount, address token) public nonReentrant {
        _validateMememonId(mememonId);

        address sender = msg.sender;
        uint256 userMememonBalance = s_mememon.balanceOf(sender, mememonId);
        if (userMememonBalance < amount) {
            revert IInternalMarket__InvalidMememonAmount(mememonId, userMememonBalance);
        }

        uint256 price = _validatePrice(mememonId);

        uint256 totalPrice = _getTokenPriceWithDecimals(token, price) * amount;

        _validateVaultBalance(totalPrice, token);

        s_mememon.burn(sender, mememonId, amount);
        s_vault.withdraw(token, totalPrice);
        IERC20(token).safeTransfer(sender, totalPrice);

        emit MememonSold(mememonId, amount, token, totalPrice);
    }

    // ========== Internal functions
    function _getTokenPriceWithDecimals(address token, uint256 priceWithNoDecimals) internal view returns (uint256) {
        uint8 decimals = ERC20(token).decimals();
        return priceWithNoDecimals * 10 ** decimals;
    }

    function _validateMememonId(uint256 mememonId) internal view {
        bool isMememonIdExist = s_mememon.getIsTokenIdExists(mememonId);
        if (!isMememonIdExist) {
            revert IInternalMarket__InvalidTokenId(mememonId);
        }
    }

    function _validatePrice(uint256 mememonId) internal view returns (uint256) {
        uint256 price = s_mememonToPrice[mememonId];
        if (price == 0) {
            revert IInternalMarket__InvalidPrice(mememonId);
        }

        bool isOnSale = s_mememonOnSale[mememonId];
        if (!isOnSale) {
            revert IInternalMarket__MememonNotOnSale(mememonId);
        }

        return price;
    }

    function _validateVaultBalance(uint256 amount, address token) internal view {
        uint256 availableBalance = getAvailableBalance(token);
        if (availableBalance < amount) {
            revert IInternalMarket__InvalidVaultBalance(token, availableBalance);
        }
    }

    // ========== Getter functions
    function getAvailableBalance(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(s_vault));
    }

    function getMememonPrices() public view returns (MememonPrice[] memory) {
        return s_mememonPrices;
    }
}
