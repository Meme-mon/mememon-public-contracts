// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/core/nfts/GameAssets.sol";

contract Mememon is GameAssets {
    constructor(address defaultAdmin) GameAssets(defaultAdmin) {}
}
