// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from "src/libraries/access/extensions/AccessControlDefaultAdminRules.sol";
import {ERC1155Holder} from "src/libraries/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";
import {ECDSA} from "src/libraries/cryptography/ECDSA.sol";
import {Mememon} from "src/tokens/Mememon.sol";
import {ITraining} from "./interfaces/ITraining.sol";

contract Training is ITraining, AccessControlDefaultAdminRules, ERC1155Holder, ReentrancyGuard {
    using ECDSA for bytes32;

    // ========== Roles
    bytes32 public constant MODERATOR_ROLE = keccak256("EVOLUTIONER_ROLE");

    struct TrainingInfor {
        address trainer;
        uint256 mememonId;
        uint256 startTime;
        uint256 endTime;
        bool isTraining;
    }

    mapping(uint256 trainingId => TrainingInfor) private s_trainings;
    uint256 private s_currentTrainingId;
    mapping(address user => uint256 trainingId) private s_userCurrentTrainingId;
    mapping(uint256 mememonId => bool isMax) private s_isMaxTrainingId;
    uint256[] private s_maxMememonIds;

    mapping(bytes32 => bool) private s_txEvolutionExecuted;

    Mememon private immutable i_mememon;

    address private s_moderator;

    constructor(address defaultAdmin, address mememon) AccessControlDefaultAdminRules(1 days, defaultAdmin) {
        i_mememon = Mememon(mememon);
        s_moderator = defaultAdmin;
        _grantRole(MODERATOR_ROLE, defaultAdmin);
    }

    function setMaxTrainingIds(uint256[] memory maxMememonIds) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < maxMememonIds.length;) {
            s_isMaxTrainingId[maxMememonIds[i]] = true;
            s_maxMememonIds.push(maxMememonIds[i]);
            unchecked {
                i++;
            }
        }
    }

    function removeMaxTrainingIds() public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < s_maxMememonIds.length;) {
            s_isMaxTrainingId[s_maxMememonIds[i]] = false;

            unchecked {
                i++;
            }
        }

        delete s_maxMememonIds;
    }

    function setModerator(address moderator) public onlyRole(MODERATOR_ROLE) {
        s_moderator = moderator;
    }

    function startTraining(uint256 mememonId) public nonReentrant {
        address user = msg.sender;

        if (s_maxMememonIds.length == 0) {
            revert Training__MememonMaxTrainingNotSet();
        }

        if (s_isMaxTrainingId[mememonId]) {
            revert Training__MememonMaxTraining(mememonId);
        }

        uint256 balanceMememon = i_mememon.balanceOf(user, mememonId);
        if (balanceMememon < 1) {
            revert Training__InsufficientMememonBalance(user, mememonId);
        }

        uint256 userTrainingId = s_userCurrentTrainingId[user];

        TrainingInfor memory training = s_trainings[userTrainingId];

        if (training.isTraining == true) {
            revert Training__AlreadyTraining(user, userTrainingId);
        }

        i_mememon.safeTransferFrom(user, address(this), mememonId, 1, "");

        s_currentTrainingId++;
        s_trainings[s_currentTrainingId] = TrainingInfor({
            trainer: user,
            mememonId: mememonId,
            startTime: block.timestamp,
            endTime: 0,
            isTraining: true
        });

        s_userCurrentTrainingId[user] = s_currentTrainingId;

        emit TrainingStarted(user, mememonId, s_currentTrainingId, block.timestamp);
    }

    function cancelTraining(uint256 mememonId) public nonReentrant {
        address user = msg.sender;
        uint256 userTrainingIdBeforeCancel = s_userCurrentTrainingId[user];

        TrainingInfor storage training = s_trainings[s_userCurrentTrainingId[user]];
        if (training.trainer != user) {
            revert Training__OnlyTrainer(training.trainer, user);
        }

        if (training.isTraining == false) {
            revert Training__NotTraining(user);
        }

        if (training.mememonId != mememonId) {
            revert Training__NotTrainThisMememon(mememonId);
        }

        i_mememon.safeTransferFrom(address(this), user, mememonId, 1, "");

        training.isTraining = false;
        training.endTime = block.timestamp;

        s_userCurrentTrainingId[user] = 0;

        emit TrainingCanceled(user, mememonId, userTrainingIdBeforeCancel, block.timestamp);
    }

    function evolution(address user, uint256 mememonId, bytes memory _sigs) public nonReentrant {
        uint256 trainingId = s_userCurrentTrainingId[user];
        bytes32 txHash = getEvolutionTxHash(s_moderator, user, mememonId, trainingId);

        if (s_txEvolutionExecuted[txHash]) {
            revert Training__TxAlreadyExecute(txHash);
        }

        if (!_checkSigs(_sigs, txHash)) {
            revert Training__InvalidModeratorSignature();
        }

        TrainingInfor storage training = s_trainings[trainingId];

        if (training.trainer != msg.sender) {
            revert Training__OnlyTrainer(training.trainer, user);
        }

        if (training.isTraining == false) {
            revert Training__NotTraining(user);
        }

        if (training.mememonId != mememonId) {
            revert Training__NotTrainThisMememon(mememonId);
        }

        if (s_isMaxTrainingId[mememonId]) {
            revert Training__MememonMaxTraining(mememonId);
        }

        i_mememon.burn(address(this), mememonId, 1);
        i_mememon.mint(training.trainer, mememonId + 1, 1, "");

        training.isTraining = false;
        training.endTime = block.timestamp;
        s_txEvolutionExecuted[txHash] = true;

        emit Evolutioned(user, trainingId, mememonId, mememonId + 1);
    }

    function _checkSigs(bytes memory _sigs, bytes32 _txHash) private view returns (bool) {
        bytes32 ethSignedHash = _txHash.toEthSignedMessageHash();

        address signer1 = ethSignedHash.recover(_sigs);

        if (signer1 != s_moderator) {
            return false;
        }

        return true;
    }

    // ========== ERC1155Holder
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlDefaultAdminRules, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ========== Getter functions
    function getEvolutionTxHash(address moderator, address trainer, uint256 mememonId, uint256 nonce)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(moderator, trainer, mememonId, nonce));
    }

    function getCurrentTrainingId() public view returns (uint256) {
        return s_currentTrainingId;
    }

    function getUserCurrentTrainingId(address user) public view returns (uint256) {
        return s_userCurrentTrainingId[user];
    }

    function getUserTrainingInfor(address user) public view returns (TrainingInfor memory) {
        return s_trainings[s_userCurrentTrainingId[user]];
    }

    function getTrainingInfor(uint256 trainingId) public view returns (TrainingInfor memory) {
        return s_trainings[trainingId];
    }

    function getMaxTrainingIds() public view returns (uint256[] memory) {
        return s_maxMememonIds;
    }

    function getIsMaxTrainingId(uint256 mememonId) public view returns (bool) {
        return s_isMaxTrainingId[mememonId];
    }
}
