// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFV2PlusWrapperConsumerBase} from "src/libraries/chainlink/vrf/VRFV2PlusWrapperConsumerBase.sol";
import {ConfirmedOwner} from "src/libraries/chainlink/access/ConfirmedOwner.sol";
import {VRFV2PlusClient} from "src/libraries/chainlink/vrf/libraries/VRFV2PlusClient.sol";
import {AccessControl} from "src/libraries/access/AccessControl.sol";
import {ERC1155Holder} from "src/libraries/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";

import {Egg} from "src/tokens/Egg.sol";
import {Mememon} from "src/tokens/Mememon.sol";

import {IOpenEgg} from "./interfaces/IOpenEgg.sol";

contract OpenEggV3 is
    IOpenEgg,
    AccessControl,
    VRFV2PlusWrapperConsumerBase,
    ConfirmedOwner,
    ERC1155Holder,
    ReentrancyGuard
{
    // ========== Chainlink VRF
    uint16 private s_requestConfirmations;
    uint32 private s_callbackGasLimit = 1000000;
    uint32 private s_numWords;
    uint256 private s_calculateFeeRate = 100;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    uint256[] private s_mememonIds = [201, 301, 401, 501, 601];
    mapping(uint256 eggId => uint256[] ratios) private s_openEggRatios;

    struct ReqInfor {
        address user;
        uint256 requestedFee;
        uint256 prepaidFee;
        uint256 eggId;
        uint256 requestTime;
        uint256 fulfilledTime;
        bool isEmergencyWithdraw;
        bool isFulfilled;
    }

    mapping(uint256 reqId => ReqInfor) private s_requestInfor;

    Mememon private immutable i_mememonContract;
    Egg private immutable i_eggContract;

    constructor(address eggContract, address mememonContract, address defaultAdmin, address wrapperAddress)
        ConfirmedOwner(defaultAdmin)
        VRFV2PlusWrapperConsumerBase(wrapperAddress)
    {
        i_eggContract = Egg(eggContract);
        i_mememonContract = Mememon(mememonContract);
        s_numWords = 1;
        s_requestConfirmations = 3;

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MODERATOR_ROLE, defaultAdmin);
    }

    // ========== Moderator Functions
    function setRatios(uint256 eggId, uint256[] memory ratios) public onlyRole(MODERATOR_ROLE) {
        if (s_mememonIds.length != ratios.length) {
            revert IOpenEgg__InvalidRatiosLength();
        }
        s_openEggRatios[eggId] = ratios;
    }

    function setMememonIds(uint256[] memory mememonIds) public onlyRole(MODERATOR_ROLE) {
        s_mememonIds = mememonIds;
    }

    function setRequestConfirmations(uint16 requestConfirmations) public onlyRole(MODERATOR_ROLE) {
        s_requestConfirmations = requestConfirmations;
    }

    function setCallbackGasLimit(uint32 callbackGasLimit) public onlyRole(MODERATOR_ROLE) {
        s_callbackGasLimit = callbackGasLimit;
    }

    function setNumWords(uint32 numWords) public onlyRole(MODERATOR_ROLE) {
        s_numWords = numWords;
    }

    function setCalculateFeeRate(uint256 calculateFeeRate) public onlyRole(MODERATOR_ROLE) {
        s_calculateFeeRate = calculateFeeRate;
    }

    // ========== User Functions
    function openEgg(uint256 eggId) external payable nonReentrant returns (uint256 requestId) {
        uint256[] memory ratios = getRatios(eggId);
        if (ratios.length == 0) {
            revert IOpenEgg__InvalidEggId();
        }

        uint256 requestPrice = i_vrfV2PlusWrapper.calculateRequestPriceNative(s_callbackGasLimit, 1);
        if (msg.value < requestPrice) {
            revert IOpenEgg__FailedToOpenEgg();
        }

        uint256 eggBalance = i_eggContract.balanceOf(msg.sender, eggId);
        if (eggBalance < 1) {
            revert IOpenEgg__InsufficientEggBalance();
        }

        i_eggContract.safeTransferFrom(msg.sender, address(this), eggId, 1, "");

        requestId = _requestRandomWords(eggId, msg.value);

        emit OpenEggRequested(msg.sender, eggId, requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        if (s_requestInfor[requestId].isFulfilled) {
            revert IOpenEgg__InvalidRequest(requestId);
        }
        ReqInfor memory reqInfor = s_requestInfor[requestId];
        uint256[] memory ratios = s_openEggRatios[reqInfor.eggId];

        uint256 scaledRandom = (randomWords[0] % 100) + 1;

        uint256 sum = 0;
        uint256 tokenIdPicked;

        for (uint256 i = 0; i < ratios.length; i++) {
            sum += ratios[i];
            if (scaledRandom <= sum) {
                tokenIdPicked = s_mememonIds[i];
                break;
            }
        }

        require(tokenIdPicked != 0, "No tokenId could be picked");

        i_eggContract.burn(address(this), reqInfor.eggId, 1);
        i_mememonContract.mint(reqInfor.user, tokenIdPicked, 1, "");

        uint256 feeToGiveBack = reqInfor.prepaidFee - reqInfor.requestedFee;

        if (feeToGiveBack > 0) {
            (bool success,) = payable(reqInfor.user).call{value: feeToGiveBack}("");
            if (!success) {
                revert IOpenEgg__FailedToGiveBackFee(requestId, feeToGiveBack);
            }
        }

        s_requestInfor[requestId].isFulfilled = true;
        s_requestInfor[requestId].fulfilledTime = block.timestamp;

        emit OpenEggFulfilled(
            reqInfor.user, reqInfor.eggId, tokenIdPicked, requestId, reqInfor.requestTime, reqInfor.requestedFee
        );
    }

    // ========== Emergency Functions
    function emergencyWithdraw(uint256 reqId) public nonReentrant {
        ReqInfor memory reqInfor = s_requestInfor[reqId];
        if (reqInfor.user != msg.sender) {
            revert IOpenEgg__OnlyRequester(reqInfor.user, msg.sender);
        }

        if (reqInfor.isFulfilled) {
            revert IOpenEgg__RequestAlreadyFulfilled(reqId);
        }

        if (reqInfor.requestTime + 1 days > block.timestamp) {
            revert IOpenEgg__FailedEmergencyWithdraw(reqId);
        }

        if (reqInfor.isEmergencyWithdraw) {
            revert IOpenEgg__FailedEmergencyWithdraw(reqId);
        }

        if (reqInfor.prepaidFee > 0) {
            (bool success,) = payable(reqInfor.user).call{value: reqInfor.prepaidFee}("");
            if (!success) {
                revert IOpenEgg__FailedToGiveBackFee(reqId, reqInfor.prepaidFee);
            }

            i_eggContract.safeTransferFrom(address(this), reqInfor.user, reqInfor.eggId, 1, "");
        }

        s_requestInfor[reqId].isEmergencyWithdraw = true;

        emit EmergencyWithdrawal(msg.sender, reqId);
    }

    // ========== Internal Functions
    function _requestRandomWords(uint256 eggId, uint256 prepaidFee) internal returns (uint256) {
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));
        (uint256 requestId, uint256 reqPrice) =
            requestRandomnessPayInNative(s_callbackGasLimit, s_requestConfirmations, s_numWords, extraArgs);

        s_requestInfor[requestId] = ReqInfor({
            user: msg.sender,
            requestedFee: reqPrice,
            prepaidFee: prepaidFee,
            eggId: eggId,
            requestTime: block.timestamp,
            fulfilledTime: 0,
            isFulfilled: false,
            isEmergencyWithdraw: false
        });

        return requestId;
    }

    // ========== ERC1155Holder Functions
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ========== Getter Functions
    function getCalculateRequestPrice() public view returns (uint256) {
        uint256 fee = i_vrfV2PlusWrapper.calculateRequestPriceNative(s_callbackGasLimit, 1);
        return fee * s_calculateFeeRate;
    }

    function getRequestInfor(uint256 requestId) public view returns (ReqInfor memory) {
        return s_requestInfor[requestId];
    }

    function getRatios(uint256 eggId) public view returns (uint256[] memory) {
        return s_openEggRatios[eggId];
    }
}
