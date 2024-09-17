// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
// import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
// import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// import {AccessControl} from "src/libraries/access/AccessControl.sol";
// import {Arrays} from "src/libraries/utils/Arrays.sol";
// import {ERC1155Holder} from "src/libraries/token/ERC1155/utils/ERC1155Holder.sol";
// import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";

// import {Egg} from "src/tokens/Egg.sol";
// import {Mememon} from "src/tokens/Mememon.sol";

// import {IOpenEgg} from "./interfaces/IOpenEgg.sol";

// /// @dev Cannot use AccessControlDefaultAdminRules because VRFConsumerBaseV2Plus already uses owner() function
// contract OpenEggV2 is
//     IOpenEgg,
//     AccessControl,
//     VRFV2PlusWrapperConsumerBase,
//     ConfirmedOwner,
//     ERC1155Holder,
//     ReentrancyGuard
// {
//     using Arrays for uint256[];

//     // ========== Chainlink VRF
//     uint16 private s_requestConfirmations;
//     uint32 private s_callbackGasLimit = 1000000;
//     uint32 private s_numWords;

//     bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

//     uint256[] private s_mememonIds = [201, 301, 401, 501, 601];
//     mapping(uint256 eggId => uint256[] ratios) private s_openEggRatios;

//     struct ReqInfor {
//         address user;
//         uint256 fee;
//         uint256 eggId;
//         uint256 mememonId;
//         bool isFulfilled;
//         bool isClaimed;
//     }

//     mapping(uint256 reqId => ReqInfor) private s_requestInfor;
//     mapping(address user => uint256 eggBalance) private s_eggBal;
//     mapping(address user => uint256[] reqIds) private s_requestUnclaim;

//     Mememon private immutable i_mememonContract;
//     Egg private immutable i_eggContract;

//     constructor(address eggContract, address mememonContract, address defaultAdmin, address wrapperAddress)
//         ConfirmedOwner(defaultAdmin)
//         VRFV2PlusWrapperConsumerBase(wrapperAddress)
//     {
//         i_eggContract = Egg(eggContract);
//         i_mememonContract = Mememon(mememonContract);
//         s_numWords = 1;
//         s_requestConfirmations = 3;

//         _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
//     }

//     receive() external payable {
//         emit ReceivedNativeToken(msg.sender, msg.value);
//     }

//     // ========== Moderator Functions
//     function setRatios(uint256 eggId, uint256[] memory ratios) public onlyRole(MODERATOR_ROLE) {
//         if (s_mememonIds.length != ratios.length) {
//             revert IOpenEgg__InvalidRatiosLength();
//         }
//         s_openEggRatios[eggId] = ratios;
//     }

//     function setMememonIds(uint256[] memory mememonIds) public onlyRole(MODERATOR_ROLE) {
//         s_mememonIds = mememonIds;
//     }

//     function setRequestConfirmations(uint16 requestConfirmations) public onlyRole(MODERATOR_ROLE) {
//         s_requestConfirmations = requestConfirmations;
//     }

//     function setCallbackGasLimit(uint32 callbackGasLimit) public onlyRole(MODERATOR_ROLE) {
//         s_callbackGasLimit = callbackGasLimit;
//     }

//     function setNumWords(uint32 numWords) public onlyRole(MODERATOR_ROLE) {
//         s_numWords = numWords;
//     }

//     function withdrawNative() external onlyRole(MODERATOR_ROLE) {
//         uint256 amount = address(this).balance;
//         (bool success,) = payable(owner()).call{value: amount}("");

//         if (!success) {
//             revert IOpenEgg__FailedWithdrawNativeToken();
//         }
//     }

//     // ========== User Functions
//     function openEgg(uint256 eggId) external nonReentrant returns (uint256 requestId) {
//         uint256[] memory ratios = getRatios(eggId);
//         if (ratios.length == 0) {
//             revert IOpenEgg__InvalidEggId();
//         }

//         uint256 eggBalance = i_eggContract.balanceOf(msg.sender, eggId);
//         if (eggBalance < 1) {
//             revert IOpenEgg__InsufficientEggBalance();
//         }

//         i_eggContract.safeTransferFrom(msg.sender, address(this), eggId, 1, "");

//         requestId = _requestRandomWords(eggId);

//         s_eggBal[msg.sender] += 1;

//         emit OpenEggRequested(msg.sender, eggId, requestId);
//     }

//     function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
//         ReqInfor memory reqInfor = s_requestInfor[requestId];
//         uint256[] memory ratios = s_openEggRatios[reqInfor.eggId];

//         uint256 scaledRandom = (randomWords[0] % 100) + 1;

//         uint256 sum = 0;
//         uint256 tokenIdPicked;

//         for (uint256 i = 0; i < ratios.length; i++) {
//             sum += ratios[i];
//             if (scaledRandom <= sum) {
//                 tokenIdPicked = s_mememonIds[i];
//                 break;
//             }
//         }

//         require(tokenIdPicked != 0, "No tokenId could be picked");

//         s_eggBal[reqInfor.user] -= 1;
//         i_eggContract.burn(address(this), reqInfor.eggId, 1);
//         s_requestInfor[requestId].isFulfilled = true;
//         s_requestInfor[requestId].mememonId = tokenIdPicked;
//         s_requestUnclaim[reqInfor.user].push(requestId);

//         emit OpenEggFulfilled(reqInfor.user, reqInfor.eggId, tokenIdPicked, 0);
//     }

//     function claimMememon(uint256 requestId) public payable nonReentrant {
//         ReqInfor memory reqInfor = s_requestInfor[requestId];
//         if (reqInfor.user != msg.sender || !reqInfor.isFulfilled || reqInfor.isClaimed) {
//             revert IOpenEgg__InvalidRequest(requestId);
//         }

//         if (reqInfor.fee != msg.value) {
//             revert IOpenEgg__FeeIsNotCorrect(reqInfor.fee, requestId);
//         }

//         i_mememonContract.mint(msg.sender, reqInfor.mememonId, 1, "");
//         s_requestInfor[requestId].isClaimed = true;

//         uint256[] storage reqIds = s_requestUnclaim[msg.sender];
//         uint256 pos = reqIds.findUpperBound(requestId);

//         if (pos < reqIds.length && reqIds[pos] == requestId) {
//             for (uint256 i = pos; i < reqIds.length - 1;) {
//                 reqIds[i] = reqIds[i + 1];
//                 unchecked {
//                     i++;
//                 }
//             }
//             reqIds.pop();
//         }

//         emit MememonClaimed(msg.sender, reqInfor.eggId, reqInfor.mememonId, requestId);
//     }

//     // ========== Internal Functions
//     function _requestRandomWords(uint256 eggId) internal returns (uint256) {
//         bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));
//         (uint256 requestId, uint256 reqPrice) =
//             requestRandomnessPayInNative(s_callbackGasLimit, s_requestConfirmations, s_numWords, extraArgs);

//         s_requestInfor[requestId] = ReqInfor({
//             user: msg.sender,
//             fee: reqPrice,
//             eggId: eggId,
//             mememonId: 0,
//             isFulfilled: false,
//             isClaimed: false
//         });

//         return requestId;
//     }

//     // ========== ERC1155Holder Functions
//     function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
//         return super.supportsInterface(interfaceId);
//     }

//     // ========== Getter Functions
//     function getRequestInfor(uint256 requestId) public view returns (ReqInfor memory) {
//         return s_requestInfor[requestId];
//     }

//     function getRatios(uint256 eggId) public view returns (uint256[] memory) {
//         return s_openEggRatios[eggId];
//     }

//     function getEggBalance(address user) public view returns (uint256) {
//         return s_eggBal[user];
//     }

//     function getUnclaimedRequests(address user) public view returns (uint256[] memory) {
//         return s_requestUnclaim[user];
//     }
// }
