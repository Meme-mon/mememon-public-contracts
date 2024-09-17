// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IOpenEgg {
    error IOpenEgg__InsufficientEggBalance();
    error IOpenEgg__InvalidRatiosLength();
    error IOpenEgg__InvalidEggId();
    error IOpenEgg__FailedToOpenEgg();
    error IOpenEgg__FailedEmergencyWithdraw(uint256 requestId);
    error IOpenEgg__InvalidRequest(uint256 requestId);
    error IOpenEgg__FeeIsNotCorrect(uint256 fee, uint256 requestId);
    error IOpenEgg__FailedToGiveBackFee(uint256 requestId, uint256 feeToGiveBack);
    error IOpenEgg__OnlyRequester(address requester, address sender);
    error IOpenEgg__RequestAlreadyFulfilled(uint256 requestId);
    error IOpenEgg__FailedWithdrawNativeToken();

    event OpenEggRequested(address indexed user, uint256 indexed eggId, uint256 requestId);
    event OpenEggFulfilled(
        address indexed user,
        uint256 indexed eggId,
        uint256 indexed mememonId,
        uint256 requestId,
        uint256 reqTime,
        uint256 requestedFee
    );
    event ReceivedNativeToken(address from, uint256 amount);
    event MememonClaimed(address indexed user, uint256 indexed eggId, uint256 mememonId, uint256 requestId);
    event EmergencyWithdrawal(address indexed user, uint256 indexed requestId);
}
