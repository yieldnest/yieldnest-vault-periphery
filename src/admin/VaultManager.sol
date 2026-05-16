// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

/// @title VaultManager
/// @notice Contract for managing Admin functions for a Vault, with role-based access control.
/// @notice Each wrapper function performs additional checks to ensure vault state is consistent.
contract VaultManager is AccessControl {
    /// @notice Thrown when the buffer is not a valid asset in the vault.
    error NotVaultAsset(address buffer);
    /// @notice Thrown when the buffer does not match the ERC4626 asset.
    error ERC4626AssetMismatch(address buffer);
    /// @notice Thrown when setting the buffer fails.
    error SetBufferFailed();
    /// @notice Thrown when a provider rate is not defined for an asset.
    error ProviderRateNotDefined(address asset);
    /// @notice Thrown when the total base assets mismatch after changing provider.
    error TotalBaseAssetsMismatch(uint256 beforeBaseAssets, uint256 afterBaseAssets);

    IVault public immutable vault;

    /// @notice Role identifier for buffer managers.
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    /// @notice Role identifier for provider managers.
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    /// @notice Role identifier for asset addition managers.
    bytes32 public constant ASSET_ADDER_ROLE = keccak256("ASSET_ADDER_ROLE");
    /// @notice Role identifier for asset deletion managers.
    bytes32 public constant ASSET_DELETER_ROLE = keccak256("ASSET_DELETER_ROLE");
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");

    /// @notice Initializes the VaultManager contract.
    /// @param _vault The address of the vault contract.
    /// @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
    /// @param bufferManager The address to be granted BUFFER_MANAGER_ROLE.
    /// @param providerManager The address to be granted PROVIDER_MANAGER_ROLE.
    /// @param assetAdder The address to be granted ASSET_ADDER_ROLE.
    /// @param assetDeleter The address to be granted ASSET_DELETER_ROLE.
    /// @param processorManager The address to be granted PROCESSOR_ROLE.
    constructor(
        address _vault,
        address defaultAdmin,
        address bufferManager,
        address providerManager,
        address assetAdder,
        address assetDeleter,
        address processorManager
    ) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_MANAGER_ROLE, bufferManager);
        _grantRole(PROVIDER_MANAGER_ROLE, providerManager);
        _grantRole(ASSET_ADDER_ROLE, assetAdder);
        _grantRole(ASSET_DELETER_ROLE, assetDeleter);
        _grantRole(PROCESSOR_ROLE, processorManager);
    }

    /// @notice Set the current buffer in the vault.
    /// @dev Only callable by BUFFER_MANAGER_ROLE. Performs all validation here.
    /// @param _buffer The buffer address to set as current.
    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_MANAGER_ROLE) {
        // Check that _buffer is a valid vault asset
        if (!_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);

        // Check that _buffer is a valid ERC4626 asset for the vault
        if (!_erc4626AssetMatchesVaultAsset(_buffer)) revert ERC4626AssetMismatch(_buffer);

        vault.setBuffer(_buffer);
    }

    /// @notice Checks if an address is a valid vault asset.
    /// @param asset The address to check.
    /// @return True if the address is a valid asset, false otherwise.
    function _isVaultAsset(address asset) public view returns (bool) {
        // TODO: optimizse using vault.hasAsset() post upgrade
        uint256 vaultIndex = vault.getAsset(asset).index;
        address[] memory allAssets = vault.getAssets();
        return vaultIndex < allAssets.length && allAssets[vaultIndex] == asset;
    }

    /// @notice Checks if an address is a valid ERC4626 asset for the vault.
    /// @param _buffer The address to check.
    /// @return True if the address is a valid ERC4626 asset, false otherwise.
    function _erc4626AssetMatchesVaultAsset(address _buffer) public view returns (bool) {
        // Use IVault and IERC4626 interfaces
        try IERC4626(_buffer).asset() returns (address bufferAsset) {
            return bufferAsset == vault.asset();
        } catch {
            return false;
        }
    }

    /**
     * @notice Set the provider for the vault.
     * @dev Validates that the new provider can provide rates for all active vault assets
     *      and that changing the provider doesn't affect the total base assets calculation.
     *      This ensures consistency in asset valuation before and after the provider change.
     * @dev Assumes that vault.processAccounting() is called before this function is called.
     * @param _provider The provider address to set.
     */
    function setProvider(address _provider) public onlyRole(PROVIDER_MANAGER_ROLE) {
        // Check that all assets have a defined rate as defined by provider using getAssets
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; ++i) {
            address assetAddr = assets[i];
            // Only check active assets

            // use the hasAsset boolean
            if (vault.getAsset(assetAddr).decimals > 0) {
                // Assume provider has a getRate(address) function that reverts or returns 0 if not defined
                try IProvider(_provider).getRate(assetAddr) returns (uint256 rate) {
                    if (rate == 0) revert ProviderRateNotDefined(assetAddr);
                } catch {
                    revert ProviderRateNotDefined(assetAddr);
                }
            }
        }

        // Get totalBaseAssets before changing provider
        uint256 beforeBaseAssets = vault.totalBaseAssets();

        vault.setProvider(_provider);

        // Get totalBaseAssets after changing provider, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault.computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }
    }

    /**
     * @notice Add assets to the vault.
     * @dev Assumes that vault.processAccounting() is called before this function is called.
     * @param _assets The addresses of the assets to add.
     * @param _active Whether the assets are active.
     */
    function addAssets(address[] memory _assets, bool[] memory _active) public onlyRole(ASSET_ADDER_ROLE) {
        // Get totalBaseAssets before changing provider
        uint256 beforeBaseAssets = vault.totalBaseAssets();

        for (uint256 i = 0; i < _assets.length; ++i) {
            // Check that the provider returns a rate > 0 for the asset before adding
            try IProvider(vault.provider()).getRate(_assets[i]) returns (uint256 rate) {
                if (rate == 0) revert ProviderRateNotDefined(_assets[i]);
            } catch {
                revert ProviderRateNotDefined(_assets[i]);
            }
            vault.addAsset(_assets[i], _active[i]);
        }

        // Get totalBaseAssets after changing provider, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault.computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }
    }

    /**
     * @notice Delete an asset from the vault.
     * @dev Assumes that vault.processAccounting() is called before this function is called.
     * @param _index The index of the asset to delete.
     */
    function deleteAsset(uint256 _index) public onlyRole(ASSET_DELETER_ROLE) {

        /*
          Improvements:
          Check asset is not the buffer.

          Make this function work for an array.

          Make it handle addresses and not indexes.

          Check for duplicates.
          
          it then sorts them so that it
          deletes starting with the last and finishes with the first to account for changing indexes.

          Bonus harder to build: check or unwind all related rules. Hard because rules associated with this
          are in a mapping so there's no way to iterate over them without hints.


        */

        // Get totalBaseAssets before deleting asset
        uint256 beforeBaseAssets = vault.totalBaseAssets();

        vault.deleteAsset(_index);

        // Get totalBaseAssets after deleting asset, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault.computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }
    }

    function processor(address[] memory _targets, uint256[] memory _values, bytes[] memory _data) public onlyRole(PROCESSOR_ROLE) {
        /*
        Improvements:
        ALWAYS execute processAccounting after.

        Bonus harder to build: actions have enumerated side-effects.
        each transaction can only alter the balances of a defined set of assets and not others.
        if anything other than the define side effects happens, revert.

        
        */
        vault.processor(_targets, _values, _data);
    }
}
