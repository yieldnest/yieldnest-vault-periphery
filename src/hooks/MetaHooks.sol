// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";

/**
 * @title MetaHooks
 * @notice MetaHooks is a contract that manages a set of hooks for a vault.
 * @dev It is used to manage the hooks for a vault and to call the hooks in the order set by the setHooks call.
 * @dev Important: Order in which hoos run is of utmost importance. Eg. if a hook verifies the effect of
 * @dev afterProcessAccounting minting fee shares as performed by another hook, it needs to be set *after*
 * @dev the other hook in order to make the check useful.
 * @dev It supports the IHooks interface, in order to be used as a hook for the vault.
 */
contract MetaHooks is IHooks, IVaultForHooks, AccessControl {
    string public constant VERSION = "0.1.0";

    error ZeroVaultAddress();
    error DuplicateInInput(IHooks hook);
    error CallerNotHook(address caller);
    error NotSupported();
    error EmptyHooksArray();
    error TooManyHooks();
    error IndexOutOfBounds();

    event ConfigBitmapUpdated(ConfigBitmap configBitmap, ConfigBitmap newConfigBitmap);
    event SharesMinted(address to, uint256 shares, address caller);
    event HookAdded(IHooks hook);
    event HookRemoved(IHooks hook);

    /**
     * @notice The data of a hook
     * @dev The index of the hook in the hooks array;
     * @dev The active boolean is used to check if the hook is registered, when calling the onlyHook modifier
     */
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

    /**
     * @notice The vault that the MetaHooks contract is attached to
     */
    IVault public immutable override VAULT;

    /**
     * @notice The array of hooks that are active for this MetaHooks contract
     * @dev The array is used to call the hooks in the correct order
     */
    IHooks[] public hooks;

    /**
     * @notice The mapping of the hooks that are active for each operation
     * @dev The mapping is used to store the index and active status of the hooks
     * @dev The index is used to call the hooks in the correct order
     * @dev The active status is used to check if the hook is active for the operation
     */
    mapping(IHooks => HookData) public hookData;

    /**
     * @notice The bitmap of the hooks that are active for each operation
     * @dev The bitmap is a uint16 where each bit represents a hook
     * @dev The bit is set to 1 if the hook is active for the operation
     * @dev The bit is set to 0 if the hook is not active for the operation
     * @dev The bitmap is used to optimize the check for what hooks to call (single slot read)
     */
    ConfigBitmap private configBitmap;

    /// @notice Role identifier for hook managers.
    bytes32 public constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert CallerNotVault();
        _;
    }

    modifier onlyHook() {
        if (!hookData[IHooks(msg.sender)].active) revert CallerNotHook(msg.sender);
        _;
    }

    /**
     * @notice Constructor for the MetaHooks contract
     * @param vault_ The address of the vault to be managed by the MetaHooks contract
     * @param defaultAdmin The address of the default admin
     * @param hookManager The address of the hook manager
     */
    constructor(address vault_, address defaultAdmin, address hookManager) {
        if (vault_ == address(0)) revert ZeroVaultAddress();
        VAULT = IVault(vault_);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(HOOK_MANAGER_ROLE, hookManager);
    }

    /// @inheritdoc IHooks
    function name() external pure override returns (string memory) {
        return "MetaHooks";
    }

    /**
     * @notice Sets the array of hooks to be executed by this MetaHooks contract
     * @dev This function replaces all existing hooks with the provided array. Clears existing hook data.
     * @dev Hooks are called IN THE ORDER they are added to the array.
     * @param hooks_ Array of hook contracts to be set. Each hook must implement the IHooks interface.
     */
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
            emit HookRemoved(hooks[i]);
        }

        // Clear the hooks array before setting new hooks
        delete hooks;

        // add the hooks to the hookData array
        for (uint256 i = 0; i < hooks_.length; i++) {
            hooks.push(hooks_[i]);
            hookData[hooks_[i]] = HookData({index: uint8(i), active: true});
            emit HookAdded(hooks_[i]);
        }

        _syncConfigBitmap();
    }

    /**
     * @notice Syncs the config bitmap for all the hooks
     * @dev This function is used to sync the config bitmap for the hooks, based on the config of each hook
     * @dev Must be called if the getConfig() output of any of the hooks changes.
     * @dev This function is called when the hooks are set
     */
    function syncConfigBitmap() external onlyRole(HOOK_MANAGER_ROLE) {
        _syncConfigBitmap();
    }

    function _syncConfigBitmap() internal {
        ConfigBitmap memory newConfigBitmap;

        IHooks[] memory _hooks = hooks;

        for (uint256 i = 0; i < _hooks.length; i++) {
            IHooks.Config memory config = _hooks[i].getConfig();

            // encode the config of hook at index i into the bitmap of each Hook Type flag
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

        emit ConfigBitmapUpdated(configBitmap, newConfigBitmap);

        configBitmap = newConfigBitmap;
    }

    /// CONFIG ///

    /// @inheritdoc IHooks
    function setConfig(Config memory) public pure override {
        revert NotSupported();
    }

    /// @inheritdoc IHooks
    function getConfig() public view override returns (Config memory) {
        ConfigBitmap memory bitmap = configBitmap;
        // Convert bitmap values to boolean flags for each hook type
        // Each bitmap field is a uint16 where bits represent which hooks support that operation
        // If any bit is set (bitmap != 0), then at least one hook supports that operation
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

    /**
     * @notice Check if a hook is supported in the bitmap
     * @param index The index of the hook to check
     * @param bitmap The bitmap to check the hook in
     * @return True if the hook is supported, false otherwise
     */
    function supportsHook(uint256 index, uint16 bitmap) public pure returns (bool) {
        if (index >= 16) revert IndexOutOfBounds();
        return (bitmap & (1 << index)) != 0;
    }

    /**
     * @notice Toggle a hook in the bitmap
     * @param index The index of the hook to set
     * @param bitmap The bitmap to set the hook in
     * @return The new bitmap
     */
    function setHook(uint256 index, uint16 bitmap) public pure returns (uint16) {
        if (index >= 16) revert IndexOutOfBounds();
        return bitmap | uint16(1 << index);
    }

    /**
     * @notice Returns the hooks array
     * @return The hooks array
     */
    function getHooks() public view returns (IHooks[] memory) {
        return hooks;
    }

    /**
     * @notice Returns the length of the hooks array
     * @return The length of the hooks array
     */
    function hooksLength() public view returns (uint256) {
        return hooks.length;
    }

    /// HOOKS FUNCTIONS ///

    /// @inheritdoc IHooks
    function beforeDeposit(DepositParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.beforeDeposit;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].beforeDeposit(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function afterDeposit(DepositParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.afterDeposit;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterDeposit(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function beforeMint(MintParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.beforeMint;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].beforeMint(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function afterMint(MintParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.afterMint;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterMint(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function beforeRedeem(RedeemParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.beforeRedeem;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].beforeRedeem(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function afterRedeem(RedeemParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.afterRedeem;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterRedeem(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function beforeWithdraw(WithdrawParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.beforeWithdraw;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].beforeWithdraw(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function afterWithdraw(WithdrawParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.afterWithdraw;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterWithdraw(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function beforeProcessAccounting(BeforeProcessAccountingParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.beforeProcessAccounting;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].beforeProcessAccounting(params);
            }
        }
    }

    /// @inheritdoc IHooks
    function afterProcessAccounting(AfterProcessAccountingParams memory params) external override onlyVault {
        uint16 bitmap = configBitmap.afterProcessAccounting;
        if (bitmap == 0) return;

        uint256 _hooksLength = hooks.length;
        for (uint256 i = 0; i < _hooksLength; i++) {
            if (supportsHook(i, bitmap)) {
                hooks[i].afterProcessAccounting(params);
            }
        }
    }

    /// VAULT FUNCTIONS ///

    /**
     * @notice Allows authorized hooks to mint shares directly to a specified address
     * @dev This function acts as a proxy to the vault's mintShares function, restricted to registered hooks
     * @param to The address that will receive the newly minted shares
     * @param shares The number of shares to mint
     */
    function mintShares(address to, uint256 shares) external override onlyHook {
        VAULT.mintShares(to, shares);
        emit SharesMinted(to, shares, msg.sender);
    }

    /**
     * @notice Converts a given amount of assets to the equivalent amount of shares
     * @dev This function acts as a proxy to the vault's convertToShares function
     * @param assets The amount of assets to convert
     * @return The equivalent amount of shares
     */
    function convertToShares(uint256 assets) external view override returns (uint256) {
        return VAULT.convertToShares(assets);
    }

    /**
     * @notice Returns the address of the underlying asset
     * @dev This function acts as a proxy to the vault's asset function
     * @return The address of the underlying asset
     */
    function asset() external view override returns (address) {
        return VAULT.asset();
    }

    /**
     * @notice Calculates the fee on raw assets
     * @dev This function acts as a proxy to the vault's _feeOnRaw function
     * @param amount The amount of assets to calculate the fee for
     * @param caller The address of the caller
     * @return The calculated fee amount
     */
    function _feeOnRaw(uint256 amount, address caller) external view override returns (uint256) {
        return VAULT._feeOnRaw(amount, caller);
    }

    /**
     * @notice Calculates the fee on total shares
     * @dev This function acts as a proxy to the vault's _feeOnTotal function
     * @param amount The amount of shares to calculate the fee for
     * @param caller The address of the caller
     * @return The calculated fee amount
     */
    function _feeOnTotal(uint256 amount, address caller) external view override returns (uint256) {
        return VAULT._feeOnTotal(amount, caller);
    }

    /**
     * @notice Previews the amount of shares that would be received for depositing a specific asset
     * @dev This function acts as a proxy to the vault's previewDepositAsset function
     * @param assetAddress The address of the asset to deposit
     * @param assets The amount of assets to deposit
     * @return The amount of shares that would be received
     */
    function previewDepositAsset(address assetAddress, uint256 assets) external view override returns (uint256) {
        return VAULT.previewDepositAsset(assetAddress, assets);
    }

    /**
     * @notice Converts a given amount of shares to the equivalent amount of assets
     * @dev This function acts as a proxy to the vault's convertToAssets function
     * @param shares The amount of shares to convert
     * @return The equivalent amount of assets
     */
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return VAULT.convertToAssets(shares);
    }

    /**
     * @notice Returns the total supply of shares
     * @dev This function acts as a proxy to the vault's totalSupply function
     * @return The total supply of shares
     */
    function totalSupply() external view override returns (uint256) {
        return VAULT.totalSupply();
    }

    /**
     * @notice Returns the total amount of assets held by the vault
     * @dev This function acts as a proxy to the vault's totalAssets function
     * @return The total amount of assets
     */
    function totalAssets() external view override returns (uint256) {
        return VAULT.totalAssets();
    }

    /**
     * @notice Returns whether the vault always computes total assets
     * @dev This function acts as a proxy to the vault's alwaysComputeTotalAssets function
     * @return True if the vault always computes total assets, false otherwise
     */
    function alwaysComputeTotalAssets() external view override returns (bool) {
        return VAULT.alwaysComputeTotalAssets();
    }
}
