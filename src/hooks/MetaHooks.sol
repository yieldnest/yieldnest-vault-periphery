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
    error EmptyHooksArray();
    error TooManyHooks();

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
        // Check if the array is empty
        if (hooks_.length == 0) revert EmptyHooksArray();
        // uint16 can only hold 16 hooks
        if (hooks_.length > 16) revert TooManyHooks();

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
            if (config.beforeDeposit) newConfigBitmap.beforeDeposit = setHook(i, newConfigBitmap.beforeDeposit);
            if (config.afterDeposit) newConfigBitmap.afterDeposit = setHook(i, newConfigBitmap.afterDeposit);
            if (config.beforeMint) newConfigBitmap.beforeMint = setHook(i, newConfigBitmap.beforeMint);
            if (config.afterMint) newConfigBitmap.afterMint = setHook(i, newConfigBitmap.afterMint);
            if (config.beforeRedeem) newConfigBitmap.beforeRedeem = setHook(i, newConfigBitmap.beforeRedeem);
            if (config.afterRedeem) newConfigBitmap.afterRedeem = setHook(i, newConfigBitmap.afterRedeem);
            if (config.beforeWithdraw) newConfigBitmap.beforeWithdraw = setHook(i, newConfigBitmap.beforeWithdraw);
            if (config.afterWithdraw) newConfigBitmap.afterWithdraw = setHook(i, newConfigBitmap.afterWithdraw);
            if (config.beforeProcessAccounting) {
                newConfigBitmap.beforeProcessAccounting = setHook(i, newConfigBitmap.beforeProcessAccounting);
            }
            if (config.afterProcessAccounting) {
                newConfigBitmap.afterProcessAccounting = setHook(i, newConfigBitmap.afterProcessAccounting);
            }
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

    // CONFIG ///

    function setConfig(Config memory) public pure override {
        revert NotSupported();
    }

    function getConfig() public view override returns (Config memory) {
        ConfigBitmap memory bitmap = configBitmap;
        return Config({
            beforeDeposit: bitmap.beforeDeposit != 0,
            afterDeposit: bitmap.afterDeposit != 0,
            beforeMint: bitmap.beforeMint != 0,
            afterMint: bitmap.afterMint != 0,
            beforeRedeem: bitmap.beforeRedeem != 0,
            afterRedeem: bitmap.afterRedeem != 0,
            beforeWithdraw: bitmap.beforeWithdraw != 0,
            afterWithdraw: bitmap.afterWithdraw != 0,
            beforeProcessAccounting: bitmap.beforeProcessAccounting != 0,
            afterProcessAccounting: bitmap.afterProcessAccounting != 0
        });
    }

    function supportsHook(uint256 index, uint16 bitmap) internal pure returns (bool) {
        return (bitmap & (1 << index)) != 0;
    }

    function setHook(uint256 index, uint16 bitmap) internal pure returns (uint16) {
        return bitmap | uint16(1 << index);
    }
    /// HOOKS FUNCTIONS ///

    function beforeDeposit(
        address _asset,
        uint256 assets,
        address caller,
        address receiver,
        uint256 shares,
        uint256 baseAssets
    ) external override onlyVault {
        uint16 bitmap = configBitmap.beforeDeposit;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.afterDeposit;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.beforeMint;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.afterMint;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.beforeRedeem;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.afterRedeem;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.beforeWithdraw;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.afterWithdraw;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterWithdraw(_asset, assets, caller, receiver, owner, shares);
            }
        }
    }

    function beforeProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalSupplyBeforeAccounting,
        uint256 totalBaseBalanceBeforeAccounting
    ) external override onlyVault {
        uint16 bitmap = configBitmap.beforeProcessAccounting;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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
        uint16 bitmap = configBitmap.afterProcessAccounting;
        if (bitmap == 0) return;

        uint256 hooksLength = hooks.length;
        for (uint256 i = 0; i < hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
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

    function previewDepositAsset(address assetAddress, uint256 assets) external view override returns (uint256) {
        return VAULT.previewDepositAsset(assetAddress, assets);
    }
}
