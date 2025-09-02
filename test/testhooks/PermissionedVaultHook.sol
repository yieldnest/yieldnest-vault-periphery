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

    function beforeDeposit(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyWhitelisted(caller) {
        // Allow deposit if caller is whitelisted
    }

    function afterDeposit(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override {
        // Not implemented
    }

    function beforeMint(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override onlyWhitelisted(caller) {
        // Allow mint if caller is whitelisted
    }

    function afterMint(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override {
        // Not implemented
    }

    function beforeRedeem(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner_,
        uint256 assets
    ) external override onlyWhitelisted(caller) {
        // Allow redeem if caller is whitelisted
    }

    function afterRedeem(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner_,
        uint256 assets
    ) external override {
        // Not implemented
    }

    function beforeWithdraw(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner_,
        uint256 shares
    ) external override onlyWhitelisted(caller) {
        // Allow withdraw if caller is whitelisted
    }

    function afterWithdraw(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner_,
        uint256 shares
    ) external override {
        // Not implemented
    }

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override {
        // Not implemented
    }

    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseBalanceAfterAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override {
        // Not implemented
    }
}
