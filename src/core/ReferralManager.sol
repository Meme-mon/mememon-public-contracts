// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlDefaultAdminRules} from "src/libraries/access/extensions/AccessControlDefaultAdminRules.sol";
import {Strings} from "src/libraries/utils/Strings.sol";
import {ERC20} from "src/libraries/token/ERC20/ERC20.sol";
import {SafeERC20} from "src/libraries/token/ERC20/utils/SafeERC20.sol";

contract ReferralManager is AccessControlDefaultAdminRules {
    using SafeERC20 for ERC20;

    error ReferralManager_UserAlreadyHaveReferralCode();
    error ReferralManager_NoBalanceToClaim();
    error ReferralManager_InvalidReferralCode();
    error ReferralManager_ReferralUserInvalid();
    error ReferralManager_InvalidReferralInfor();

    struct ReferralInfo {
        address owner;
        uint256 referralPercentage;
        bool isActive;
        bool isLimitedTime;
        uint256 endTime;
    }

    mapping(string => ReferralInfo) private s_referralInfo;
    mapping(address => mapping(address => uint256)) private s_balances;
    mapping(address => string) private s_referralCode;
    mapping(address => bool) private s_haveReferralCode;

    uint256 private s_currentReferralId;

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant DEPOSITER_ROLE = keccak256("DEPOSITER_ROLE");

    constructor(address defaultAdmin) AccessControlDefaultAdminRules(1 days, defaultAdmin) {}

    event ReferralCodeCreated(address indexed owner, string referralCode);
    event ReferralClaimed(address indexed user, address indexed token, uint256 amount);
    event SpecialReferralCodeCreated(
        address indexed owner, string referralCode, uint256 endTime, uint256 refPercentage
    );

    function disableReferralCode(string memory referralCode) public onlyRole(MODERATOR_ROLE) {
        s_referralInfo[referralCode].isActive = false;
    }

    function enableReferralCode(string memory referralCode) public onlyRole(MODERATOR_ROLE) {
        s_referralInfo[referralCode].isActive = true;
    }

    function createSpecialReferralCode(
        string memory referralCode,
        address owner,
        uint256 refPercentage,
        uint256 endTime
    ) public onlyRole(MODERATOR_ROLE) returns (string memory) {
        if (s_referralInfo[referralCode].isActive) {
            revert ReferralManager_InvalidReferralInfor();
        }
        if (endTime <= block.timestamp || endTime > (block.timestamp + 180 days)) {
            revert ReferralManager_InvalidReferralInfor();
        }
        if (refPercentage > 10) {
            revert ReferralManager_InvalidReferralInfor();
        }

        s_referralInfo[referralCode] = ReferralInfo({
            owner: owner,
            referralPercentage: refPercentage,
            isActive: true,
            isLimitedTime: true,
            endTime: endTime
        });

        s_referralCode[owner] = referralCode;

        emit SpecialReferralCodeCreated(owner, referralCode, endTime, refPercentage);

        return referralCode;
    }

    function addBalance(address token, string memory refCode, uint256 amount, address refCodeUser)
        public
        onlyRole(DEPOSITER_ROLE)
    {
        _checkRefCodeExists(refCode);
        _checkReferralEndTime(refCode);
        _checkOwnerAndRefUser(refCode, refCodeUser);
        s_balances[s_referralInfo[refCode].owner][token] += amount / 2;
        s_balances[refCodeUser][token] += amount / 2;
    }

    function claim(address token) public {
        uint256 amount = s_balances[msg.sender][token];
        if (amount == 0) revert ReferralManager_NoBalanceToClaim();

        ERC20(token).safeTransfer(msg.sender, amount);

        s_balances[msg.sender][token] = 0;

        emit ReferralClaimed(msg.sender, token, amount);
    }

    function createReferralCode() public returns (string memory referralCode) {
        _checkHaveReferralCode(msg.sender);
        referralCode = string(abi.encodePacked("MEMEMON", Strings.toString(s_currentReferralId)));
        s_referralInfo[referralCode] =
            ReferralInfo({owner: msg.sender, isActive: true, referralPercentage: 5, isLimitedTime: false, endTime: 0});
        s_referralCode[msg.sender] = referralCode;
        s_haveReferralCode[msg.sender] = true;
        s_currentReferralId++;

        emit ReferralCodeCreated(msg.sender, referralCode);
    }

    function _checkHaveReferralCode(address user) internal view {
        if (s_haveReferralCode[user]) revert ReferralManager_UserAlreadyHaveReferralCode();
    }

    function _checkRefCodeExists(string memory refCode) internal view {
        if (!s_referralInfo[refCode].isActive) revert ReferralManager_InvalidReferralCode();
    }

    function _checkOwnerAndRefUser(string memory refCode, address refCodeUser) internal view {
        address owner = s_referralInfo[refCode].owner;
        if (owner == refCodeUser) revert ReferralManager_ReferralUserInvalid();
    }

    function _checkReferralEndTime(string memory refCode) internal view {
        if (s_referralInfo[refCode].isLimitedTime && s_referralInfo[refCode].endTime < block.timestamp) {
            revert ReferralManager_InvalidReferralCode();
        }
    }

    function getReferralCode(address user) public view returns (string memory) {
        return s_referralCode[user];
    }

    function isReferralCodeActive(string memory referralCode) public view returns (bool) {
        return s_referralInfo[referralCode].isActive;
    }

    function getReferralOwner(string memory referralCode) public view returns (address) {
        return s_referralInfo[referralCode].owner;
    }

    function getReferralPercentage(string memory referralCode) public view returns (uint256) {
        return s_referralInfo[referralCode].referralPercentage;
    }

    function getReferralCodeInfor(string memory referralCode)
        public
        view
        returns (address owner, uint256 referralPercentage, bool isActive, bool isLimitedTime, uint256 endTime)
    {
        ReferralInfo memory info = s_referralInfo[referralCode];
        return (info.owner, info.referralPercentage, info.isActive, info.isLimitedTime, info.endTime);
    }

    function getReferralBalance(address user, address token) public view returns (uint256) {
        return s_balances[user][token];
    }
}
