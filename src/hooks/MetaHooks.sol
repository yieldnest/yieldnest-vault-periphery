// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";

contract MetaHooks is IHooks, IVaultForHooks, AccessControl {
    error ZeroVaultAddress();
    error DuplicateInInput(IHooks hook);
    error CallerNotHook(address caller);

    IVault public immutable override VAULT;
    IHooks[] public hooks;
    Config private _config;

    /// @notice Role identifier for hook managers.
    bytes32 public constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");

    constructor(address vault_, address defaultAdmin, address hookManager) {
        if (vault_ == address(0)) revert ZeroVaultAddress();
        VAULT = IVault(vault_);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(HOOK_MANAGER_ROLE, hookManager);
    }

    function setHooks(IHooks[] memory hooks_) external onlyRole(HOOK_MANAGER_ROLE) {
        Config memory newConfig;
        // Check for duplicates in hooks_
        for (uint256 i = 0; i < hooks_.length; i++) {
            for (uint256 j = i + 1; j < hooks_.length; j++) {
                if (hooks_[i] == hooks_[j]) revert DuplicateInInput(hooks_[i]);
            }
        }

        // Clear the hooks array before setting new hooks
        delete hooks;

        for (uint256 i = 0; i < hooks_.length; i++) {
            hooks.push(hooks_[i]);

            IHooks.Config memory config = hooks_[i].getConfig();

            newConfig.beforeDeposit = newConfig.beforeDeposit || config.beforeDeposit;
            newConfig.afterDeposit = newConfig.afterDeposit || config.afterDeposit;
            newConfig.beforeMint = newConfig.beforeMint || config.beforeMint;
            newConfig.afterMint = newConfig.afterMint || config.afterMint;
            newConfig.beforeRedeem = newConfig.beforeRedeem || config.beforeRedeem;
            newConfig.afterRedeem = newConfig.afterRedeem || config.afterRedeem;
            newConfig.beforeWithdraw = newConfig.beforeWithdraw || config.beforeWithdraw;
        }

        setConfig(newConfig);
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    modifier onlyHook() {
        bool isHook = false;
        for (uint256 i = 0; i < hooks.length; i++) {
            if (msg.sender == address(hooks[i])) {
                isHook = true;
                break;
            }
        }
        if (!isHook) revert CallerNotHook(msg.sender);
        _;
    }

    // HOOKS FUNCTIONS

    function setConfig(Config memory config_) public override {
        _config = config_;
    }

    function getConfig() public view override returns (Config memory) {
        return _config;
    }

    function beforeDeposit(uint256 assets, address caller, address receiver, uint256 shares, uint256 baseAssets)
        external
        override
        onlyVault
    {
        if (!_config.beforeDeposit) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.beforeDeposit(hooks[i], assets, caller, receiver, shares, baseAssets);
        }
    }

    function afterDeposit(uint256 assets, address caller, address receiver, uint256 shares, uint256 baseAssets)
        external
        override
        onlyVault
    {
        if (!_config.afterDeposit) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.afterDeposit(hooks[i], assets, caller, receiver, shares, baseAssets);
        }
    }

    function beforeMint(uint256 shares, address caller, address receiver, uint256 assets, uint256 baseAssets)
        external
        override
        onlyVault
    {
        if (!_config.beforeMint) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.beforeMint(hooks[i], shares, caller, receiver, assets, baseAssets);
        }
    }

    function afterMint(uint256 shares, address caller, address receiver, uint256 assets, uint256 baseAssets)
        external
        override
        onlyVault
    {
        if (!_config.afterMint) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.afterMint(hooks[i], shares, caller, receiver, assets, baseAssets);
        }
    }

    function beforeRedeem(uint256 shares, address caller, address receiver, address owner, uint256 assets)
        external
        override
        onlyVault
    {
        if (!_config.beforeRedeem) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.beforeRedeem(hooks[i], shares, caller, receiver, owner, assets);
        }
    }

    function afterRedeem(uint256 shares, address caller, address receiver, address owner, uint256 assets)
        external
        override
        onlyVault
    {
        if (!_config.afterRedeem) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.afterRedeem(hooks[i], shares, caller, receiver, owner, assets);
        }
    }

    function beforeWithdraw(uint256 assets, address caller, address receiver, address owner, uint256 shares)
        external
        override
        onlyVault
    {
        if (!_config.beforeWithdraw) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.beforeWithdraw(hooks[i], assets, caller, receiver, owner, shares);
        }
    }

    function afterWithdraw(uint256 assets, address caller, address receiver, address owner, uint256 shares)
        external
        override
        onlyVault
    {
        if (!_config.afterWithdraw) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.afterWithdraw(hooks[i], assets, caller, receiver, owner, shares);
        }
    }

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        if (!_config.beforeProcessAccounting) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.beforeProcessAccounting(
                hooks[i], totalAssetsBeforeAccounting, totalSupplyBeforeAccounting, totalBaseBalanceBeforeAccounting
            );
        }
    }

    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseBalanceAfterAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        if (!_config.afterProcessAccounting) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            HooksLib.afterProcessAccounting(
                hooks[i],
                totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting,
                totalSupplyAfterAccounting,
                totalBaseBalanceAfterAccounting,
                totalBaseBalanceBeforeAccounting
            );
        }
    }

    // VAULT FUNCTIONS

    function mintShares(address to, uint256 shares) external override onlyHook {
        VAULT.mintShares(to, shares);
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return VAULT.convertToShares(assets);
    }

    function asset() external view override returns (address) {
        return VAULT.asset();
    }

    function _feeOnRaw(uint256 assets, address caller) external view override returns (uint256) {
        return VAULT._feeOnRaw(assets, caller);
    }

    function _feeOnTotal(uint256 shares, address caller) external view override returns (uint256) {
        return VAULT._feeOnTotal(shares, caller);
    }

    // TODO: remove when interface is simplified

    function performanceFee() external pure returns (uint256) {
        // stub
        return 0;
    }

    function performanceFeeRecipient() external pure returns (address) {
        // stub
        return address(0);
    }

    function setPerformanceFee(uint256 /*performanceFee_*/ ) external pure {
        // stub
    }
    function setPerformanceFeeRecipient(address /*performanceFeeRecipient_*/ ) external pure {
        // stub
    }
}
