// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract PermissionedVaultHook is IHooks {
    error UserNotWhitelisted(address user);
    error NotSupported();

    mapping(address => bool) public whitelist;
    address public owner;
    IVault public immutable VAULT;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyWhitelisted(address user) {
        if (!whitelist[user]) revert UserNotWhitelisted(user);
        _;
    }

    constructor(address _vault, address _owner, address[] memory _whitelistedUsers) {
        VAULT = IVault(_vault);
        owner = _owner;
        for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
            whitelist[_whitelistedUsers[i]] = true;
        }
    }

    function name() external pure returns (string memory) {
        return "PermissionedVaultHook";
    }

    function addToWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
    }

    function removeFromWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
    }

    function getConfig() external pure override returns (Config memory) {
        return Config({
            beforeDeposit: true,
            afterDeposit: false,
            beforeMint: true,
            afterMint: false,
            beforeRedeem: true,
            afterRedeem: false,
            beforeWithdraw: true,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });
    }

    function setConfig(Config memory) external pure {
        revert NotSupported();
    }

    function beforeDeposit(DepositParams memory params) external override onlyWhitelisted(params.caller) {
        // Allow deposit if caller is whitelisted
    }

    function afterDeposit(DepositParams memory params) external override {
        // Not implemented
    }

    function beforeMint(MintParams memory params) external override onlyWhitelisted(params.caller) {
        // Allow mint if caller is whitelisted
    }

    function afterMint(MintParams memory params) external override {
        // Not implemented
    }

    function beforeRedeem(RedeemParams memory params) external override onlyWhitelisted(params.caller) {
        // Allow redeem if caller is whitelisted
    }

    function afterRedeem(RedeemParams memory params) external override {
        // Not implemented
    }

    function beforeWithdraw(WithdrawParams memory params) external override onlyWhitelisted(params.caller) {
        // Allow withdraw if caller is whitelisted
    }

    function afterWithdraw(WithdrawParams memory params) external override {
        // Not implemented
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams memory params) external override {
        // Not implemented
    }

    function afterProcessAccounting(AfterProcessAccountingParams memory params) external override {
        // Not implemented
    }
}
