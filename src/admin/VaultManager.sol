// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IStrategy} from "lib/yieldnest-vault/src/interface/IStrategy.sol";

interface IAlwaysComputeTotalAssetsVault {
    function setAlwaysComputeTotalAssets(bool alwaysComputeTotalAssets_) external;
}

interface IHooksManagedVault {
    function setHooks(address hooks_) external;
}

/// @title VaultManager
/// @notice Contract for managing Admin functions for a Vault, with role-based access control.
/// @notice Each wrapper function performs additional checks to ensure vault state is consistent.
contract VaultManager is AccessControl {
    uint256 public constant RATIO_DENOMINATOR = 1e18;

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
    /// @notice Thrown when the total base assets mismatch after changing provider.
    error TotalBaseAssetsMismatch(uint256 beforeBaseAssets, uint256 afterBaseAssets);
    /// @notice Thrown when the total assets mismatch after a configuration change.
    error TotalAssetsMismatch(uint256 beforeTotalAssets, uint256 afterTotalAssets);
    /// @notice Thrown when the total supply mismatch after a configuration change.
    error TotalSupplyMismatch(uint256 beforeTotalSupply, uint256 afterTotalSupply);
    /// @notice Thrown when arrays have mismatched lengths.
    error LengthMismatch();
    /// @notice Thrown when an asset appears more than once in a batch.
    error DuplicateAsset(address asset);
    /// @notice Thrown when the processor changes total assets by more than the configured ratio.
    error TotalAssetsDeltaExceeded(uint256 beforeTotalAssets, uint256 afterTotalAssets);
    /// @notice Thrown when the processor changes total supply by more than the configured ratio.
    error TotalSupplyDeltaExceeded(uint256 beforeTotalSupply, uint256 afterTotalSupply);
    /// @notice Thrown when a configured ratio exceeds the allowed denominator.
    error RatioTooHigh(uint256 ratio);
    /// @notice Thrown when hooks must be disabled for the requested operation.
    error HooksMustBeDisabled();
    /// @notice Thrown when alwaysComputeTotalAssets must be disabled for the requested operation.
    error AlwaysComputeTotalAssetsMustBeDisabled();

    event ProcessorMaxDeltaRatioSet(uint256 oldRatio, uint256 newRatio);

    IVault public immutable vault;
    uint256 public maxProcessorDeltaRatio;

    /// @notice Role identifier for buffer managers.
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    /// @notice Role identifier for provider managers.
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    /// @notice Role identifier for asset addition managers.
    bytes32 public constant ASSET_ADDER_ROLE = keccak256("ASSET_ADDER_ROLE");
    /// @notice Role identifier for asset deletion managers.
    bytes32 public constant ASSET_DELETER_ROLE = keccak256("ASSET_DELETER_ROLE");
    /// @notice Role identifier for accounting mode managers.
    bytes32 public constant TOTAL_ASSETS_MODE_MANAGER_ROLE = keccak256("TOTAL_ASSETS_MODE_MANAGER_ROLE");
    /// @notice Role identifier for hooks managers.
    bytes32 public constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");

    /// @notice Initializes the VaultManager contract.
    /// @param _vault The address of the vault contract.
    /// @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
    /// @param bufferManager The address to be granted BUFFER_MANAGER_ROLE.
    /// @param providerManager The address to be granted PROVIDER_MANAGER_ROLE.
    /// @param assetAdder The address to be granted ASSET_ADDER_ROLE.
    /// @param assetDeleter The address to be granted ASSET_DELETER_ROLE.
    /// @param totalAssetsModeManager The address to be granted TOTAL_ASSETS_MODE_MANAGER_ROLE.
    /// @param hooksManager The address to be granted HOOKS_MANAGER_ROLE.
    /// @param processorManager The address to be granted PROCESSOR_ROLE.
    constructor(
        address _vault,
        address defaultAdmin,
        address bufferManager,
        address providerManager,
        address assetAdder,
        address assetDeleter,
        address totalAssetsModeManager,
        address hooksManager,
        address processorManager
    ) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_MANAGER_ROLE, bufferManager);
        _grantRole(PROVIDER_MANAGER_ROLE, providerManager);
        _grantRole(ASSET_ADDER_ROLE, assetAdder);
        _grantRole(ASSET_DELETER_ROLE, assetDeleter);
        _grantRole(TOTAL_ASSETS_MODE_MANAGER_ROLE, totalAssetsModeManager);
        _grantRole(HOOKS_MANAGER_ROLE, hooksManager);
        _grantRole(PROCESSOR_ROLE, processorManager);
        maxProcessorDeltaRatio = RATIO_DENOMINATOR;
    }

    /// @notice Set the current buffer in the vault.
    /// @dev Only callable by BUFFER_MANAGER_ROLE. Performs all validation here.
    /// @param _buffer The buffer address to set as current.
    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_MANAGER_ROLE) {
        setCurrentBuffer(_buffer, false);
    }

    /// @notice Set the current buffer in the vault.
    /// @dev Only callable by BUFFER_MANAGER_ROLE. Performs all validation here.
    /// @param _buffer The buffer address to set as current.
    /// @param skipIsAssetCheck Whether to skip the vault asset membership check.
    function setCurrentBuffer(address _buffer, bool skipIsAssetCheck) public onlyRole(BUFFER_MANAGER_ROLE) {
        // Check that _buffer is a valid vault asset
        if (!skipIsAssetCheck && !_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);

        // Check that _buffer is a valid ERC4626 asset for the vault
        if (!_erc4626AssetMatchesVaultAsset(_buffer)) revert ERC4626AssetMismatch(_buffer);

        try IStrategy(_buffer).maxWithdraw(address(vault)) returns (uint256) {} catch {
            revert BufferMaxWithdrawCheckFailed(_buffer);
        }

        vault.setBuffer(_buffer);
    }

    /// @notice Checks if an address is a valid vault asset.
    /// @param asset The address to check.
    /// @return True if the address is a valid asset, false otherwise.
    function _isVaultAsset(address asset) public view returns (bool) {
        return vault.hasAsset(asset);
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
            if (vault.getAsset(assetAddr).active) {
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
        if (_assets.length != _active.length) revert LengthMismatch();

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
        address currentBuffer = vault.buffer();

        for (uint256 i = 0; i < _assets.length; ++i) {
            address asset = _assets[i];

            if (!_isVaultAsset(asset)) revert NotVaultAsset(asset);
            if (asset == currentBuffer) revert CannotDeleteBufferAsset(asset);

            for (uint256 j = i + 1; j < _assets.length; ++j) {
                if (asset == _assets[j]) revert DuplicateAsset(asset);
            }

            indexes[i] = vault.getAsset(asset).index;
        }

        _sortDescending(indexes);

        // Get totalBaseAssets before deleting asset
        uint256 beforeBaseAssets = vault.totalBaseAssets();

        for (uint256 i = 0; i < indexes.length; ++i) {
            vault.deleteAsset(indexes[i]);
        }

        // Get totalBaseAssets after deleting asset, using computeTotalAssets (forces recompute)
        uint256 afterBaseAssets = vault.computeTotalAssets();

        if (beforeBaseAssets != afterBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
        }
    }

    function processor(address[] memory _targets, uint256[] memory _values, bytes[] memory _data)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (bytes[] memory results)
    {
        if (_targets.length != _values.length || _targets.length != _data.length) revert LengthMismatch();

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalSupply = vault.totalSupply();

        results = vault.processor(_targets, _values, _data);
        vault.processAccounting();

        uint256 afterTotalAssets = vault.totalAssets();
        uint256 afterTotalSupply = vault.totalSupply();

        if (_ratioDelta(beforeTotalAssets, afterTotalAssets) > maxProcessorDeltaRatio) {
            revert TotalAssetsDeltaExceeded(beforeTotalAssets, afterTotalAssets);
        }

        if (_ratioDelta(beforeTotalSupply, afterTotalSupply) > maxProcessorDeltaRatio) {
            revert TotalSupplyDeltaExceeded(beforeTotalSupply, afterTotalSupply);
        }
    }

    function setAlwaysComputeTotalAssets(bool _alwaysComputeTotalAssets)
        external
        onlyRole(TOTAL_ASSETS_MODE_MANAGER_ROLE)
    {
        bool wasAlwaysComputeTotalAssets = vault.alwaysComputeTotalAssets();
        if (wasAlwaysComputeTotalAssets == _alwaysComputeTotalAssets) {
            return;
        }

        if (_alwaysComputeTotalAssets && address(vault.hooks()) != address(0)) revert HooksMustBeDisabled();

        if (!wasAlwaysComputeTotalAssets && _alwaysComputeTotalAssets) {
            vault.processAccounting();
        }

        uint256 beforeTotalBaseAssets = vault.totalBaseAssets();
        uint256 beforeTotalAssets = vault.totalAssets();

        IAlwaysComputeTotalAssetsVault(address(vault)).setAlwaysComputeTotalAssets(_alwaysComputeTotalAssets);

        uint256 afterTotalBaseAssets = vault.totalBaseAssets();
        uint256 afterTotalAssets = vault.totalAssets();

        if (beforeTotalBaseAssets != afterTotalBaseAssets) {
            revert TotalBaseAssetsMismatch(beforeTotalBaseAssets, afterTotalBaseAssets);
        }

        if (beforeTotalAssets != afterTotalAssets) {
            revert TotalAssetsMismatch(beforeTotalAssets, afterTotalAssets);
        }
    }

    function setHooks(address _hooks) external onlyRole(HOOKS_MANAGER_ROLE) {
        if (vault.alwaysComputeTotalAssets()) revert AlwaysComputeTotalAssetsMustBeDisabled();

        vault.processAccounting();
        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalSupply = vault.totalSupply();

        IHooksManagedVault(address(vault)).setHooks(_hooks);

        vault.processAccounting();
        uint256 afterTotalAssets = vault.totalAssets();
        uint256 afterTotalSupply = vault.totalSupply();

        if (beforeTotalAssets != afterTotalAssets) {
            revert TotalAssetsMismatch(beforeTotalAssets, afterTotalAssets);
        }

        if (beforeTotalSupply != afterTotalSupply) {
            revert TotalSupplyMismatch(beforeTotalSupply, afterTotalSupply);
        }
    }

    function setMaxProcessorDeltaRatio(uint256 _maxProcessorDeltaRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxProcessorDeltaRatio > RATIO_DENOMINATOR) revert RatioTooHigh(_maxProcessorDeltaRatio);

        emit ProcessorMaxDeltaRatioSet(maxProcessorDeltaRatio, _maxProcessorDeltaRatio);
        maxProcessorDeltaRatio = _maxProcessorDeltaRatio;
    }

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

    function _ratioDelta(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256) {
        if (beforeValue == afterValue) return 0;

        uint256 delta = beforeValue > afterValue ? beforeValue - afterValue : afterValue - beforeValue;
        uint256 baseline = beforeValue == 0 ? 1 : beforeValue;

        return (delta * RATIO_DENOMINATOR) / baseline;
    }
}
