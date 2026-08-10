// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IStrategy} from "lib/yieldnest-vault/src/interface/IStrategy.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

interface IAlwaysComputeTotalAssetsVault {
    function setAlwaysComputeTotalAssets(bool alwaysComputeTotalAssets_) external;
}

interface IHooksManagedVault {
    function setHooks(address hooks_) external;
}

interface IAssetWithdrawableManagedVault {
    function setAssetWithdrawable(address asset_, bool withdrawable_) external;
}

interface IStrategyVersioned {
    function STRATEGY_VERSION() external view returns (string memory);
}

/// @title VaultManager
/// @notice Contract for managing Admin functions for a Vault, with role-based access control.
/// @notice Each wrapper function performs additional checks to ensure vault state is consistent.
contract VaultManager is Initializable, AccessControlUpgradeable {
    //// CONSTANTS ////

    /// @custom:storage-location erc7201:yieldnest.storage.VaultManager
    struct VaultManagerStorage {
        IVault vault;
        bool isStrategyManaged;
    }

    //// ERRORS ////

    /// @notice Thrown when the buffer is not a valid asset in the vault.
    error NotVaultAsset(address buffer);
    /// @notice Thrown when an asset deletion request includes the current buffer.
    error CannotDeleteBufferAsset(address asset);
    /// @notice Thrown when the buffer does not match the ERC4626 asset.
    error ERC4626AssetMismatch(address buffer);
    /// @notice Thrown when the buffer cannot satisfy a maxWithdraw probe.
    error BufferMaxWithdrawCheckFailed(address buffer);
    /// @notice Thrown when a provider rate is not defined for an asset.
    error ProviderRateNotDefined(address asset);
    /// @notice Thrown when an asset rate changes across a provider update.
    error AssetRateChanged(address asset, uint256 beforeRate, uint256 afterRate);
    /// @notice Thrown when the total base assets mismatch after changing provider.
    error TotalBaseAssetsMismatch(uint256 beforeBaseAssets, uint256 afterBaseAssets);
    /// @notice Thrown when the total supply mismatch after a configuration change.
    error TotalSupplyMismatch(uint256 beforeTotalSupply, uint256 afterTotalSupply);
    /// @notice Thrown when arrays have mismatched lengths.
    error LengthMismatch();
    /// @notice Thrown when an asset appears more than once in a batch.
    error DuplicateAsset(address asset);
    /// @notice Thrown when hooks must be disabled for the requested operation.
    error HooksMustBeDisabled();
    /// @notice Thrown when alwaysComputeTotalAssets must be disabled for the requested operation.
    error AlwaysComputeTotalAssetsMustBeDisabled();
    /// @notice Thrown when a requested configuration change would not modify state.
    error NoOp();
    /// @notice Thrown when a strategy-only operation is attempted on a non-strategy managed contract.
    error ManagedContractNotStrategy(address managedContract);

    //// ROLES ////

    /// @notice Role identifier for buffer managers.
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    /// @notice Role identifier for provider managers.
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    /// @notice Role identifier for asset addition managers.
    bytes32 public constant ASSET_ADDER_ROLE = keccak256("ASSET_ADDER_ROLE");
    /// @notice Role identifier for asset deletion managers.
    bytes32 public constant ASSET_DELETER_ROLE = keccak256("ASSET_DELETER_ROLE");
    /// @notice Role identifier for asset withdrawal managers.
    bytes32 public constant ASSET_WITHDRAWER_ROLE = keccak256("ASSET_WITHDRAWER_ROLE");
    /// @notice Role identifier for accounting mode managers.
    bytes32 public constant TOTAL_ASSETS_MODE_MANAGER_ROLE = keccak256("TOTAL_ASSETS_MODE_MANAGER_ROLE");
    /// @notice Role identifier for hooks managers.
    bytes32 public constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");

    //// INITIALIZER ////

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    function _getVaultManagerStorage() internal pure returns (VaultManagerStorage storage $) {
        assembly {
            // keccak256(abi.encode(uint256(keccak256("yieldnest.storage.VaultManager")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0x4ee6fd4281980a6f17143263df94113ac1b3537a4cb7994a4310a0a99380a400
        }
    }

    function vault() public view returns (IVault) {
        return _getVaultManagerStorage().vault;
    }

    function isStrategyManaged() public view returns (bool) {
        return _getVaultManagerStorage().isStrategyManaged;
    }

    /**
     * @notice Initializes the VaultManager contract.
     * @param _vault The address of the vault contract.
     * @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param bufferManager The address to be granted BUFFER_MANAGER_ROLE.
     * @param providerManager The address to be granted PROVIDER_MANAGER_ROLE.
     * @param assetAdder The address to be granted ASSET_ADDER_ROLE.
     * @param assetDeleter The address to be granted ASSET_DELETER_ROLE.
     * @param assetWithdrawer The address to be granted ASSET_WITHDRAWER_ROLE.
     * @param totalAssetsModeManager The address to be granted TOTAL_ASSETS_MODE_MANAGER_ROLE.
     * @param hooksManager The address to be granted HOOKS_MANAGER_ROLE.
     */
    function initialize(
        address _vault,
        address defaultAdmin,
        address bufferManager,
        address providerManager,
        address assetAdder,
        address assetDeleter,
        address assetWithdrawer,
        address totalAssetsModeManager,
        address hooksManager
    ) external initializer {
        __AccessControl_init();

        _setManagedVault(_vault);
        _grantManagerRoles(
            defaultAdmin,
            bufferManager,
            providerManager,
            assetAdder,
            assetDeleter,
            assetWithdrawer,
            totalAssetsModeManager,
            hooksManager
        );
    }

    //// BUFFER ////

    modifier onlyManagedStrategy() {
        if (!isStrategyManaged()) revert ManagedContractNotStrategy(address(vault()));
        _;
    }

    function _setManagedVault(address managedVault) internal {
        VaultManagerStorage storage $ = _getVaultManagerStorage();
        $.vault = IVault(managedVault);
        $.isStrategyManaged = _supportsStrategyVersion(managedVault);
    }

    function _grantManagerRoles(
        address defaultAdmin,
        address bufferManager,
        address providerManager,
        address assetAdder,
        address assetDeleter,
        address assetWithdrawer,
        address totalAssetsModeManager,
        address hooksManager
    ) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_MANAGER_ROLE, bufferManager);
        _grantRole(PROVIDER_MANAGER_ROLE, providerManager);
        _grantRole(ASSET_ADDER_ROLE, assetAdder);
        _grantRole(ASSET_DELETER_ROLE, assetDeleter);
        _grantRole(ASSET_WITHDRAWER_ROLE, assetWithdrawer);
        _grantRole(TOTAL_ASSETS_MODE_MANAGER_ROLE, totalAssetsModeManager);
        _grantRole(HOOKS_MANAGER_ROLE, hooksManager);
    }

    /**
     * @notice Set the current buffer in the vault.
     * @dev Only callable by BUFFER_MANAGER_ROLE. Performs all validation here.
     * @param _buffer The buffer address to set as current.
     */
    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_MANAGER_ROLE) {
        setCurrentBuffer(_buffer, false);
    }

    /**
     * @notice Set the current buffer in the vault.
     * @dev Only callable by BUFFER_MANAGER_ROLE. Performs all validation here.
     * @param _buffer The buffer address to set as current.
     * @param skipIsAssetCheck Whether to skip the vault asset membership check.
     */
    function setCurrentBuffer(address _buffer, bool skipIsAssetCheck) public onlyRole(BUFFER_MANAGER_ROLE) {
        // Check that _buffer is a valid vault asset
        if (!skipIsAssetCheck && !_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);

        // Check that _buffer is a valid ERC4626 asset for the vault
        if (!_erc4626AssetMatchesVaultAsset(_buffer)) revert ERC4626AssetMismatch(_buffer);

        try IStrategy(_buffer).maxWithdraw(address(vault())) returns (uint256) {}
        catch {
            revert BufferMaxWithdrawCheckFailed(_buffer);
        }

        vault().setBuffer(_buffer);
    }

    /**
     * @notice Checks if an address is a valid vault asset.
     * @param asset The address to check.
     * @return True if the address is a valid asset, false otherwise.
     */
    function _isVaultAsset(address asset) public view returns (bool) {
        return vault().hasAsset(asset);
    }

    /**
     * @notice Checks if an address is a valid ERC4626 asset for the vault.
     * @param _buffer The address to check.
     * @return True if the address is a valid ERC4626 asset, false otherwise.
     */
    function _erc4626AssetMatchesVaultAsset(address _buffer) public view returns (bool) {
        try IERC4626(_buffer).asset() returns (address bufferAsset) {
            return bufferAsset == vault().asset();
        } catch {
            return false;
        }
    }

    //// PROVIDER ////

    /**
     * @notice Set the provider for the vault.
     * @dev Validates that the new provider can provide rates for all active vault assets
     *      and that changing the provider doesn't affect the total base assets calculation.
     *      This ensures consistency in asset valuation before and after the provider change.
     * @param _provider The provider address to set.
     */
    function setProvider(address _provider) public onlyRole(PROVIDER_MANAGER_ROLE) {
        address[] memory assets = vault().getAssets();
        address currentProvider = vault().provider();

        // Check that all assets have a defined rate as defined by provider using getAssets
        for (uint256 i = 0; i < assets.length; ++i) {
            address assetAddr = assets[i];
            if (vault().getAsset(assetAddr).active) {
                // Assume provider has a getRate(address) function that reverts or returns 0 if not defined
                try IProvider(_provider).getRate(assetAddr) returns (uint256 rate) {
                    if (rate == 0) revert ProviderRateNotDefined(assetAddr);
                } catch {
                    revert ProviderRateNotDefined(assetAddr);
                }
            }
        }

        // Check that the rates of the base asset and default asset have not changed
        {
            address baseAsset = assets[0];
            address defaultAsset = vault().asset();

            uint256 beforeBaseAssetRate = IProvider(currentProvider).getRate(baseAsset);
            uint256 beforeDefaultAssetRate = IProvider(currentProvider).getRate(defaultAsset);
            uint256 afterBaseAssetRate = IProvider(_provider).getRate(baseAsset);
            uint256 afterDefaultAssetRate = IProvider(_provider).getRate(defaultAsset);

            if (beforeBaseAssetRate != afterBaseAssetRate) {
                revert AssetRateChanged(baseAsset, beforeBaseAssetRate, afterBaseAssetRate);
            }

            if (beforeDefaultAssetRate != afterDefaultAssetRate) {
                revert AssetRateChanged(defaultAsset, beforeDefaultAssetRate, afterDefaultAssetRate);
            }
        }

        // Process accounting to ensure totalBaseAssets is updated
        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }

        // Get totalBaseAssets before changing provider from a fresh accounting snapshot
        uint256 beforeBaseAssets = vault().totalBaseAssets();

        vault().setProvider(_provider);

        // Get totalBaseAssets after changing provider, using computeTotalAssets (virtual recompute)
        // This is an optimization to avoid calling processAccounting again.
        // If the virtual result is different, the call must revert.
        uint256 afterBaseAssets = vault().computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }

        // processAccounting is not called again, since storage value doesn't actually change,
        // assuming there was no revert condition.
    }

    //// ADD ASSET ////

    /**
     * @notice Add assets to the vault.
     * @param _assets The addresses of the assets to add.
     * @param _active Whether the assets are active.
     */
    function addAssets(address[] memory _assets, bool[] memory _active) public onlyRole(ASSET_ADDER_ROLE) {
        if (_assets.length != _active.length) revert LengthMismatch();

        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }

        // Get totalBaseAssets before changing provider
        uint256 beforeBaseAssets = vault().totalBaseAssets();

        for (uint256 i = 0; i < _assets.length; ++i) {
            // Check that the provider returns a rate > 0 for the asset before adding
            try IProvider(vault().provider()).getRate(_assets[i]) returns (uint256 rate) {
                if (rate == 0) revert ProviderRateNotDefined(_assets[i]);
            } catch {
                revert ProviderRateNotDefined(_assets[i]);
            }
            vault().addAsset(_assets[i], _active[i]);
        }

        // Get totalBaseAssets after changing provider, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault().computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }

        // No need to call processAccounting again since storage value doesn't actually change,
        // assuming there was no revert condition.
    }

    //// DELETE ASSET ////

    /**
     * @notice Delete an asset from the vault.
     * @dev Assumes that vault.processAccounting() is called before this function is called.
     * @param _asset The asset to delete.
     */
    function deleteAsset(address _asset) public onlyRole(ASSET_DELETER_ROLE) {
        address[] memory assets = new address[](1);
        assets[0] = _asset;
        deleteAssets(assets);
    }

    /**
     * @notice Delete assets from the vault.
     * @dev Assumes that vault.processAccounting() is called before this function is called.
     * @param _assets The assets to delete.
     */
    function deleteAssets(address[] memory _assets) public onlyRole(ASSET_DELETER_ROLE) {
        uint256[] memory indexes = new uint256[](_assets.length);
        address currentBuffer = vault().buffer();

        for (uint256 i = 0; i < _assets.length; ++i) {
            address asset = _assets[i];

            if (!_isVaultAsset(asset)) revert NotVaultAsset(asset);
            if (asset == currentBuffer) revert CannotDeleteBufferAsset(asset);

            for (uint256 j = i + 1; j < _assets.length; ++j) {
                if (asset == _assets[j]) revert DuplicateAsset(asset);
            }

            indexes[i] = vault().getAsset(asset).index;
        }

        _sortDescending(indexes);

        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }

        // Get totalBaseAssets before deleting asset
        uint256 beforeBaseAssets = vault().totalBaseAssets();

        for (uint256 i = 0; i < indexes.length; ++i) {
            vault().deleteAsset(indexes[i]);
        }

        // Get totalBaseAssets after deleting asset, using computeTotalAssets (forces virtual recompute)
        uint256 afterBaseAssets = vault().computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }

        // No need to call processAccounting again since storage value doesn't actually change,
        // assuming there was no revert condition.
    }

    //// ALWAYS COMPUTE TOTAL ASSETS ////

    /**
     * @notice Toggle the vault's always-compute accounting mode.
     * @dev Enabling always-compute requires hooks to be disabled.
     * @param _alwaysComputeTotalAssets The desired accounting mode.
     */
    function setAlwaysComputeTotalAssets(bool _alwaysComputeTotalAssets)
        external
        onlyRole(TOTAL_ASSETS_MODE_MANAGER_ROLE)
    {
        bool wasAlwaysComputeTotalAssets = vault().alwaysComputeTotalAssets();
        if (wasAlwaysComputeTotalAssets == _alwaysComputeTotalAssets) {
            revert NoOp();
        }

        if (_alwaysComputeTotalAssets && address(vault().hooks()) != address(0)) revert HooksMustBeDisabled();

        if (!wasAlwaysComputeTotalAssets && _alwaysComputeTotalAssets) {
            vault().processAccounting();
        }

        uint256 beforeTotalBaseAssets = vault().totalBaseAssets();

        IAlwaysComputeTotalAssetsVault(address(vault())).setAlwaysComputeTotalAssets(_alwaysComputeTotalAssets);

        uint256 afterTotalBaseAssets = vault().totalBaseAssets();

        if (beforeTotalBaseAssets != afterTotalBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeTotalBaseAssets, afterTotalBaseAssets);
        }
    }

    //// HOOKS ////

    /**
     * @notice Set the hooks contract on the vault.
     * @dev Requires cached-accounting mode so pre/post accounting invariants are meaningful.
     * @param _hooks The hooks contract to install, or `address(0)` to clear hooks.
     */
    function setHooks(address _hooks) external onlyRole(HOOKS_MANAGER_ROLE) {
        if (vault().alwaysComputeTotalAssets()) revert AlwaysComputeTotalAssetsMustBeDisabled();

        // alwaysComputeTotalAssets is false, so processAccounting is called.
        vault().processAccounting();
        uint256 beforeTotalBaseAssets = vault().totalBaseAssets();
        uint256 beforeTotalSupply = vault().totalSupply();

        IHooksManagedVault(address(vault())).setHooks(_hooks);

        // alwaysComputeTotalAssets is false, so processAccounting is called.
        vault().processAccounting();
        uint256 afterTotalBaseAssets = vault().totalBaseAssets();
        uint256 afterTotalSupply = vault().totalSupply();

        if (beforeTotalBaseAssets != afterTotalBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeTotalBaseAssets, afterTotalBaseAssets);
        }

        if (beforeTotalSupply != afterTotalSupply) {
            revert TotalSupplyMismatch(beforeTotalSupply, afterTotalSupply);
        }
    }

    /**
     * @notice Sort an array of unsigned integers in descending order in place.
     * @param values The array to sort.
     */
    function _sortDescending(uint256[] memory values) internal pure {
        for (uint256 i = 1; i < values.length; ++i) {
            uint256 current = values[i];
            uint256 j = i;

            while (j > 0 && values[j - 1] < current) {
                values[j] = values[j - 1];
                unchecked {
                    --j;
                }
            }

            values[j] = current;
        }
    }

    //// WITHDRAW ASSET ////

    /**
     * @notice Set whether an existing managed asset is withdrawable.
     * @dev Only callable by ASSET_ADDER_ROLE. Intended for strategy instances that expose per-asset
     *      withdrawability controls. The asset must already exist on the managed contract.
     * @param asset_ The managed asset whose withdrawability flag will be updated.
     * @param withdrawable_ The new withdrawability value.
     */
    function setAssetWithdrawable(address asset_, bool withdrawable_)
        external
        onlyRole(ASSET_ADDER_ROLE)
        onlyManagedStrategy
    {
        if (!_isVaultAsset(asset_)) revert NotVaultAsset(asset_);
        IAssetWithdrawableManagedVault(address(vault())).setAssetWithdrawable(asset_, withdrawable_);
    }

    /**
     * @notice Withdraw a vault asset using the receiver as the share owner.
     * @param asset_ The asset to withdraw.
     * @param assets The amount of the asset to withdraw.
     * @param receiver The asset recipient and share owner.
     * @return shares The number of shares burned by the vault.
     */
    function withdrawAsset(address asset_, uint256 assets, address receiver)
        external
        onlyRole(ASSET_WITHDRAWER_ROLE)
        returns (uint256 shares)
    {
        return _withdrawAsset(asset_, assets, receiver, receiver);
    }

    /**
     * @notice Withdraw a vault asset on behalf of a specific share owner.
     * @param asset_ The asset to withdraw.
     * @param assets The amount of the asset to withdraw.
     * @param receiver The asset recipient.
     * @param owner The share owner whose shares are burned.
     * @return shares The number of shares burned by the vault.
     */
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        onlyRole(ASSET_WITHDRAWER_ROLE)
        returns (uint256 shares)
    {
        return _withdrawAsset(asset_, assets, receiver, owner);
    }

    /// @notice Internal withdraw helper that forwards to the vault and conditionally syncs accounting.
    /// @param asset_ The asset to withdraw.
    /// @param assets The amount of the asset to withdraw.
    /// @param receiver The asset recipient.
    /// @param owner The share owner whose shares are burned.
    /// @return shares The number of shares burned by the vault.
    function _withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        internal
        returns (uint256 shares)
    {
        shares = vault().withdrawAsset(asset_, assets, receiver, owner);
        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }
    }

    function _supportsStrategyVersion(address managedContract) internal view returns (bool) {
        try IStrategyVersioned(managedContract).STRATEGY_VERSION() returns (string memory version) {
            return bytes(version).length != 0;
        } catch {
            return false;
        }
    }
}
