// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IInternalMarket {
    event MememonSold(uint256 mememonId, uint256 amount, address tokenReceive, uint256 totalPrice);

    error IInternalMarket__InvalidTokenId(uint256 tokenId);
    error IInternalMarket__InvalidInputLength();
    error IInternalMarket__InvalidPrice(uint256 tokenId);
    error IInternalMarket__MememonNotOnSale(uint256 tokenId);
    error IInternalMarket__InvalidVaultBalance(address tokenReceive, uint256 availableBalance);
    error IInternalMarket__InvalidMememonAmount(uint256 tokenId, uint256 userAmount);

    function setMememonPrice(uint256 mememonId, uint256 price) external;
    function sellMememon(uint256 mememonId, uint256 amount, address token) external;
    function getAvailableBalance(address token) external view returns (uint256);
}
