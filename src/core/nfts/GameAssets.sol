// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC1155} from "src/libraries/token/ERC1155/ERC1155.sol";
import {ERC1155Pausable} from "src/libraries/token/ERC1155/extensions/ERC1155Pausable.sol";
import {ERC1155Burnable} from "src/libraries/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Supply} from "src/libraries/token/ERC1155/extensions/ERC1155Supply.sol";
import {AccessControlDefaultAdminRules} from "src/libraries/access/extensions/AccessControlDefaultAdminRules.sol";
import {Strings} from "src/libraries/utils/Strings.sol";
import {Arrays} from "src/libraries/utils/Arrays.sol";
import {IGameAssets} from "./interfaces/IGameAssets.sol";

contract GameAssets is
    IGameAssets,
    ERC1155,
    AccessControlDefaultAdminRules,
    ERC1155Pausable,
    ERC1155Burnable,
    ERC1155Supply
{
    using Arrays for uint256[];

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(uint256 tokenId => bool isAccept) private s_isAcceptTokenId;
    uint256[] private s_tokenIds;
    string private s_uri;
    bool private s_includeJsonExtension = true;

    constructor(address defaultAdmin) ERC1155("") AccessControlDefaultAdminRules(1 days, defaultAdmin) {
        _grantRole(MODERATOR_ROLE, defaultAdmin);
    }

    // ========== Token ID Management
    function setTokenId(uint256 tokenId) public onlyRole(MODERATOR_ROLE) {
        _checkTokenIdAlreadyExists(tokenId);

        uint256 pos = s_tokenIds.findUpperBound(tokenId);

        s_tokenIds.push(tokenId);

        for (uint256 i = s_tokenIds.length - 1; i > pos;) {
            s_tokenIds[i] = s_tokenIds[i - 1];

            unchecked {
                i--;
            }
        }

        s_tokenIds[pos] = tokenId;
        s_isAcceptTokenId[tokenId] = true;
    }

    function setTokenIds(uint256[] memory tokenIds) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];
            _checkTokenIdAlreadyExists(tokenId);
            s_isAcceptTokenId[tokenId] = true;

            uint256 pos = s_tokenIds.findUpperBound(tokenId);

            s_tokenIds.push(tokenId);
            for (uint256 j = s_tokenIds.length - 1; j > pos;) {
                s_tokenIds[j] = s_tokenIds[j - 1];

                unchecked {
                    j--;
                }
            }
            s_tokenIds[pos] = tokenId;

            unchecked {
                i++;
            }
        }
    }

    function disableTokenId(uint256 tokenId) public onlyRole(MODERATOR_ROLE) {
        _checkTokenIdExists(tokenId);
        s_isAcceptTokenId[tokenId] = false;
    }

    function enableTokenId(uint256 tokenId) public onlyRole(MODERATOR_ROLE) {
        _checkTokenIdExists(tokenId);
        s_isAcceptTokenId[tokenId] = true;
    }

    function disableTokenIds(uint256[] memory tokenIds) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _checkTokenIdExists(tokenIds[i]);
            s_isAcceptTokenId[tokenIds[i]] = false;
        }
    }

    function enableTokenIds(uint256[] memory tokenIds) public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _checkTokenIdExists(tokenIds[i]);

            s_isAcceptTokenId[tokenIds[i]] = true;
        }
    }

    function removeTokenId(uint256 tokenIdToRemove) public onlyRole(MODERATOR_ROLE) {
        _checkTokenIdExists(tokenIdToRemove);

        uint256 pos = s_tokenIds.findUpperBound(tokenIdToRemove);

        if (pos < s_tokenIds.length && s_tokenIds[pos] == tokenIdToRemove) {
            for (uint256 i = pos; i < s_tokenIds.length - 1;) {
                s_tokenIds[i] = s_tokenIds[i + 1];
                unchecked {
                    i++;
                }
            }
            s_tokenIds.pop();
        }

        s_isAcceptTokenId[tokenIdToRemove] = false;
    }

    function removeAllTokenIds() public onlyRole(MODERATOR_ROLE) {
        for (uint256 i = 0; i < s_tokenIds.length; i++) {
            s_isAcceptTokenId[s_tokenIds[i]] = false;
        }

        delete s_tokenIds;
    }

    function setIncludeJsonExtension(bool status) public onlyRole(MODERATOR_ROLE) {
        s_includeJsonExtension = status;
    }

    // ========== Internal Functions
    function _checkTokenIdExists(uint256 tokenId) internal view {
        if (!getIsTokenIdExists(tokenId)) {
            revert TokenIdDoesNotExist(tokenId);
        }
    }

    function _checkTokenIdAlreadyExists(uint256 tokenId) internal view {
        if (getIsTokenIdExists(tokenId)) {
            revert TokenIdAlreadyExists(tokenId);
        }
    }

    // ========== URI Management
    function setURI(string memory newuri) public onlyRole(MODERATOR_ROLE) {
        _setURI(newuri);
    }

    function _setURI(string memory newuri) internal override {
        s_uri = newuri;
    }

    function contractURI() public view returns (string memory) {
        return s_uri;
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory _uri = string(abi.encodePacked(s_uri, "/", Strings.toString(tokenId)));
        if (s_includeJsonExtension) {
            return string(abi.encodePacked(_uri, ".json"));
        } else {
            return _uri;
        }
    }

    // ========== External Functions
    function mint(address account, uint256 id, uint256 amount, bytes memory data) external onlyRole(MINTER_ROLE) {
        _checkTokenIdExists(id);
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        external
        onlyRole(MINTER_ROLE)
    {
        for (uint256 i = 0; i < ids.length; i++) {
            _checkTokenIdExists(ids[i]);
        }
        _mintBatch(to, ids, amounts, data);
    }

    // ========== Getter Functions
    function getIsTokenIdExists(uint256 tokenId) public view returns (bool) {
        return s_isAcceptTokenId[tokenId];
    }

    function getTokenIds() external view returns (uint256[] memory) {
        return s_tokenIds;
    }

    // ========== ERC1155Pausable
    function pause() public onlyRole(MODERATOR_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(MODERATOR_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Pausable, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
