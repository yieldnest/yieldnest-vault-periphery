// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";

contract MetaHooks is IHooks, IVaultForHooks, AccessControl {
    error ZeroVaultAddress();
    error DuplicateInInput(IHooks hook);
    error CallerNotHook(address caller);
    error NotSupported();

    struct HookData {
        uint8 index;
        bool active;
    }

    struct ConfigBitmap {
        uint16 beforeDeposit;
        uint16 afterDeposit;
        uint16 beforeMint;
        uint16 afterMint;
        uint16 beforeRedeem;
        uint16 afterRedeem;
        uint16 beforeWithdraw;
        uint16 afterWithdraw;
        uint16 beforeProcessAccounting;
        uint16 afterProcessAccounting;
    }

    IVault public immutable override VAULT;
    IHooks[] public hooks;
    mapping(IHooks => HookData) public hookData;
    ConfigBitmap private configBitmap;

    /// @notice Role identifier for hook managers.
    bytes32 public constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");

    constructor(address vault_, address defaultAdmin, address hookManager) {
        if (vault_ == address(0)) revert ZeroVaultAddress();
        VAULT = IVault(vault_);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(HOOK_MANAGER_ROLE, hookManager);
    }

    /// @notice Sets the array of hooks to be executed by this MetaHooks contract
    /// @dev This function replaces all existing hooks with the provided array. Clears existing hook data.
    /// @param hooks_ Array of hook contracts to be set. Each hook must implement the IHooks interface.
    function setHooks(IHooks[] memory hooks_) external onlyRole(HOOK_MANAGER_ROLE) {
        Config memory newConfig;
        // Check for duplicates in hooks_
        for (uint256 i = 0; i < hooks_.length; i++) {
            for (uint256 j = i + 1; j < hooks_.length; j++) {
                if (hooks_[i] == hooks_[j]) revert DuplicateInInput(hooks_[i]);
            }
        }
        // Clear existing hook data mappings
        for (uint256 i = 0; i < hooks.length; i++) {
            delete hookData[hooks[i]];
        }
        // Clear the hooks array before setting new hooks
        delete hooks;

        ConfigBitmap memory newConfigBitmap;

        for (uint256 i = 0; i < hooks_.length; i++) {
            hooks.push(hooks_[i]);
            hookData[hooks_[i]] = HookData({index: uint8(i), active: true});

            IHooks.Config memory config = hooks_[i].getConfig();

            if (config.beforeDeposit) newConfigBitmap.beforeDeposit |= uint16(1 << i);
            if (config.afterDeposit) newConfigBitmap.afterDeposit |= uint16(1 << i);
            if (config.beforeMint) newConfigBitmap.beforeMint |= uint16(1 << i);
            if (config.afterMint) newConfigBitmap.afterMint |= uint16(1 << i);
            if (config.beforeRedeem) newConfigBitmap.beforeRedeem |= uint16(1 << i);
            if (config.afterRedeem) newConfigBitmap.afterRedeem |= uint16(1 << i);
            if (config.beforeWithdraw) newConfigBitmap.beforeWithdraw |= uint16(1 << i);
            if (config.afterWithdraw) newConfigBitmap.afterWithdraw |= uint16(1 << i);
            if (config.beforeProcessAccounting) newConfigBitmap.beforeProcessAccounting |= uint16(1 << i);
            if (config.afterProcessAccounting) newConfigBitmap.afterProcessAccounting |= uint16(1 << i);
        }

        configBitmap = newConfigBitmap;
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    modifier onlyHook() {
        if (!hookData[IHooks(msg.sender)].active) revert CallerNotHook(msg.sender);
        _;
    }

    // HOOKS FUNCTIONS

    function setConfig(Config memory config_) public override {
        revert NotSupported();
    }

    function getConfig() public view override returns (Config memory) {
        return Config({
            beforeDeposit: configBitmap.beforeDeposit != 0,
            afterDeposit: configBitmap.afterDeposit != 0,
            beforeMint: configBitmap.beforeMint != 0,
            afterMint: configBitmap.afterMint != 0,
            beforeRedeem: configBitmap.beforeRedeem != 0,
            afterRedeem: configBitmap.afterRedeem != 0,
            beforeWithdraw: configBitmap.beforeWithdraw != 0,
            afterWithdraw: configBitmap.afterWithdraw != 0,
            beforeProcessAccounting: configBitmap.beforeProcessAccounting != 0,
            afterProcessAccounting: configBitmap.afterProcessAccounting != 0
        });
    }

    function beforeDeposit(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyVault {
        if (!getConfig().beforeDeposit) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().beforeDeposit) {
                hooks[i].beforeDeposit(_asset, assets, caller, receiver, shares, baseAssets);
            }
        }
    }

    function afterDeposit(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyVault {
        if (!getConfig().afterDeposit) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().afterDeposit) {
                hooks[i].afterDeposit(_asset, assets, caller, receiver, shares, baseAssets);
            }
        }
    }

    function beforeMint(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override onlyVault {
        if (!getConfig().beforeMint) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().beforeMint) {
                hooks[i].beforeMint(_asset, shares, caller, receiver, assets, baseAssets);
            }
        }
    }

    function afterMint(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        uint256 assets,
        uint256 baseAssets
    ) external override onlyVault {
        if (!getConfig().afterMint) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().afterMint) {
                hooks[i].afterMint(_asset, shares, caller, receiver, assets, baseAssets);
            }
        }
    }

    function beforeRedeem(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external override onlyVault {
        if (!getConfig().beforeRedeem) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().beforeRedeem) {
                hooks[i].beforeRedeem(_asset, shares, caller, receiver, owner, assets);
            }
        }
    }

    function afterRedeem(
        address _asset,
        uint256 shares,
        address caller,
        address receiver,
        address owner,
        uint256 assets
    ) external override onlyVault {
        if (!getConfig().afterRedeem) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().afterRedeem) {
                hooks[i].afterRedeem(_asset, shares, caller, receiver, owner, assets);
            }
        }
    }

    function beforeWithdraw(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external override onlyVault {
        if (!getConfig().beforeWithdraw) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().beforeWithdraw) {
                hooks[i].beforeWithdraw(_asset, assets, caller, receiver, owner, shares);
            }
        }
    }

    function afterWithdraw(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        address owner,
        uint256 shares
    ) external override onlyVault {
        if (!getConfig().afterWithdraw) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().afterWithdraw) {
                hooks[i].afterWithdraw(_asset, assets, caller, receiver, owner, shares);
            }
        }
    }

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        if (!getConfig().beforeProcessAccounting) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().beforeProcessAccounting) {
                hooks[i].beforeProcessAccounting(
                    totalAssetsBeforeAccounting, totalSupplyBeforeAccounting, totalBaseBalanceBeforeAccounting
                );
            }
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
        if (!getConfig().afterProcessAccounting) return;

        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i].getConfig().afterProcessAccounting) {
                hooks[i].afterProcessAccounting(
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    totalSupplyBeforeAccounting,
                    totalSupplyAfterAccounting,
                    totalBaseBalanceAfterAccounting,
                    totalBaseBalanceBeforeAccounting
                );
            }
        }
    }

    // VAULT FUNCTIONS

    /// @notice Allows authorized hooks to mint shares directly to a specified address
    /// @dev This function acts as a proxy to the vault's mintShares function, restricted to registered hooks
    /// @param to The address that will receive the newly minted shares
    /// @param shares The number of shares to mint
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
}
