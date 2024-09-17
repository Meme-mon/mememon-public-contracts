// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITraining {
    error Training__OnlyTrainer(address trainer, address caller);
    error Training__AlreadyTraining(address trainer, uint256 trainingId);
    error Training__NotTraining(address user);
    error Training__NotTrainThisMememon(uint256 mememonId);
    error Training__InsufficientMememonBalance(address trainer, uint256 mememonId);
    error Training__MememonMaxTrainingNotSet();
    error Training__MememonMaxTraining(uint256 mememonId);
    error Training__TxAlreadyExecute(bytes32 txHash);
    error Training__InvalidModeratorSignature();

    event TrainingStarted(address indexed trainer, uint256 indexed mememonId, uint256 trainingId, uint256 startTime);
    event TrainingCanceled(address indexed trainer, uint256 indexed mememonId, uint256 trainingId, uint256 cancelTime);
    event Evolutioned(address indexed trainer, uint256 trainingId, uint256 oldMememonId, uint256 newMememonId);
}
