// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";

/// @title VaultAdmin
/// @notice Contract for managing buffer addresses for a Vault, with role-based access control.
/// @dev Only addresses with BUFFER_ADMIN_ROLE can set the current buffer.
contract VaultAdmin is AccessControl {
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

    IVault public vault;

    /// @notice Role identifier for buffer admins.
    bytes32 public constant BUFFER_ADMIN_ROLE = keccak256("BUFFER_ADMIN_ROLE");

    bytes32 public constant MODULE_MANAGER_ROLE = keccak256("MODULE_MANAGER_ROLE");

    /// @notice Initializes the BufferAdmin contract.
    /// @param _vault The address of the vault contract.
    /// @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
    /// @param bufferAdmin The address to be granted BUFFER_ADMIN_ROLE.
    constructor(address _vault, address defaultAdmin, address bufferAdmin) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_ADMIN_ROLE, bufferAdmin);
    }

    /// @notice Set the current buffer in the vault.
    /// @dev Only callable by BUFFER_ADMIN_ROLE. Performs all validation here.
    /// @param _buffer The buffer address to set as current.
    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_ADMIN_ROLE) {
        // Check that _buffer is a valid vault asset
        if (!_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);

        // Check that _buffer is a valid ERC4626 asset for the vault
        if (!_isERC4626Asset(_buffer)) revert ERC4626AssetMismatch(_buffer);

        vault.setBuffer(_buffer);
    }

    /// @notice Checks if an address is a valid vault asset.
    /// @param _buffer The address to check.
    /// @return True if the address is a valid asset, false otherwise.
    function _isVaultAsset(address _buffer) public view returns (bool) {
        return vault.getAsset(_buffer).decimals > 0;
    }

    /// @notice Checks if an address is a valid ERC4626 asset for the vault.
    /// @param _buffer The address to check.
    /// @return True if the address is a valid ERC4626 asset, false otherwise.
    function _isERC4626Asset(address _buffer) public view returns (bool) {
        // Use IVault and IERC4626 interfaces
        try IERC4626(_buffer).asset() returns (address bufferAsset) {
            return bufferAsset == vault.asset();
        } catch {
            return false;
        }
    }

    function setProvider(address _provider) public onlyRole(MODULE_MANAGER_ROLE) {
        // Check that all assets have a defined rate as defined by provider using getAssets
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; ++i) {
            address assetAddr = assets[i];
            // Only check active assets
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

    function addAssets(address[] memory _assets, bool[] memory _active) public onlyRole(MODULE_MANAGER_ROLE) {
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

    function deleteAsset(uint256 _index) public onlyRole(MODULE_MANAGER_ROLE) {
        // Get totalBaseAssets before deleting asset
        uint256 beforeBaseAssets = vault.totalBaseAssets();

        // Get totalBaseAssets after deleting asset, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault.computeTotalAssets();

        vault.deleteAsset(_index);

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }
    }
}
