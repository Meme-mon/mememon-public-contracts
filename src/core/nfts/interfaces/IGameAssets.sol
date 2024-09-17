// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGameAssets {
    error TokenIdDoesNotExist(uint256 tokenId);
    error TokenIdAlreadyExists(uint256 tokenId);

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;

    function getTokenIds() external view returns (uint256[] memory);
}
