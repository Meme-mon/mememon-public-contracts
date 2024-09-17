// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
// import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// import {AccessControl} from "src/libraries/access/AccessControl.sol";
// import {Arrays} from "src/libraries/utils/Arrays.sol";
// import {ERC1155Holder} from "src/libraries/token/ERC1155/utils/ERC1155Holder.sol";
// import {ReentrancyGuard} from "src/libraries/utils/ReentrancyGuard.sol";

// import {Egg} from "src/tokens/Egg.sol";
// import {Mememon} from "src/tokens/Mememon.sol";

// import {IOpenEgg} from "./interfaces/IOpenEgg.sol";

// /// @dev Cannot use AccessControlDefaultAdminRules because VRFConsumerBaseV2Plus already uses owner() function
// contract OpenEgg is IOpenEgg, AccessControl, VRFConsumerBaseV2Plus, ERC1155Holder, ReentrancyGuard {
//     using Arrays for uint256[];

//     // ========== Chainlink VRF

//     bytes32 private s_keyHash;
//     uint256 private s_subId;
//     uint16 private s_requestConfirmations;
//     uint32 private s_callbackGasLimit = 1000000;
//     uint32 private s_numWords;

//     bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

//     uint256[] private s_mememonIds = [201, 301, 401, 501, 601];
//     mapping(uint256 eggId => uint256[] ratios) private s_openEggRatios;

//     mapping(address user => mapping(uint256 reqId => bool)) private s_isRequesting;

//     struct ReqInfor {
//         address user;
//         uint256 eggId;
//     }

//     mapping(uint256 reqId => ReqInfor) private s_requestInfor;

//     mapping(address user => uint256 eggBalance) private s_eggBal;

//     Mememon private immutable i_mememonContract;
//     Egg private immutable i_eggContract;

//     constructor(
//         address eggContract,
//         address mememonContract,
//         address defaultAdmin,
//         address _vrfCoordinator,
//         uint256 _subId,
//         bytes32 _keyHash
//     ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
//         i_eggContract = Egg(eggContract);
//         i_mememonContract = Mememon(mememonContract);
//         s_numWords = 1;
//         s_keyHash = _keyHash;
//         s_requestConfirmations = 3;
//         s_subId = _subId;

//         _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
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

//     function setKeyHash(bytes32 keyHash) public onlyRole(MODERATOR_ROLE) {
//         s_keyHash = keyHash;
//     }

//     function setSubId(uint256 subId) public onlyRole(MODERATOR_ROLE) {
//         s_subId = subId;
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

//         requestId = _requestRandomWords();

//         s_isRequesting[msg.sender][requestId] = true;
//         s_eggBal[msg.sender] += 1;
//         s_requestInfor[requestId] = ReqInfor({user: msg.sender, eggId: eggId});

//         i_eggContract.setApprovalForAll(address(this), false);

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

//         s_isRequesting[reqInfor.user][requestId] = false;
//         s_eggBal[reqInfor.user] -= 1;

//         i_eggContract.burn(address(this), reqInfor.eggId, 1);
//         i_mememonContract.mint(reqInfor.user, tokenIdPicked, 1, "");

//         emit OpenEggFulfilled(reqInfor.user, reqInfor.eggId, tokenIdPicked, 0);
//     }

//     // ========== Internal Functions
//     function _requestRandomWords() internal returns (uint256) {
//         uint256 requestId = s_vrfCoordinator.requestRandomWords(
//             VRFV2PlusClient.RandomWordsRequest({
//                 keyHash: s_keyHash,
//                 subId: s_subId,
//                 requestConfirmations: s_requestConfirmations,
//                 callbackGasLimit: s_callbackGasLimit,
//                 numWords: s_numWords,
//                 extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
//             })
//         );
//         return requestId;
//     }

//     // ========== ERC1155Holder Functions
//     function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
//         return super.supportsInterface(interfaceId);
//     }

//     // ========== Getter Functions
//     function getReqStatus(address user, uint256 requestId) public view returns (bool) {
//         return s_isRequesting[user][requestId];
//     }

//     function getRequestInfor(uint256 requestId) public view returns (ReqInfor memory) {
//         return s_requestInfor[requestId];
//     }

//     function getRatios(uint256 eggId) public view returns (uint256[] memory) {
//         return s_openEggRatios[eggId];
//     }

//     function getEggBalance(address user) public view returns (uint256) {
//         return s_eggBal[user];
//     }
// }
