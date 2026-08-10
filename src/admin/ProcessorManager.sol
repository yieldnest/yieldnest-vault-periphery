// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/// @title ProcessorManager
/// @notice Standalone manager for executing guarded processor calls on a vault.
contract ProcessorManager is Initializable, AccessControlUpgradeable {
    uint256 public constant RATIO_DENOMINATOR = 1e18;

    /// @custom:storage-location erc7201:yieldnest.storage.ProcessorManager
    struct ProcessorManagerStorage {
        IVault vault;
        uint256 maxProcessorBaseAssetsDeltaRatio;
        uint256 maxProcessorSupplyDeltaRatio;
    }

    /// @notice Thrown when arrays have mismatched lengths.
    error LengthMismatch();
    /// @notice Thrown when the processor changes total base assets by more than the configured ratio.
    error TotalBaseAssetsDeltaExceeded(uint256 beforeTotalBaseAssets, uint256 afterTotalBaseAssets);
    /// @notice Thrown when the processor changes total supply by more than the configured ratio.
    error TotalSupplyDeltaExceeded(uint256 beforeTotalSupply, uint256 afterTotalSupply);
    /// @notice Thrown when a configured ratio exceeds the allowed denominator.
    error RatioTooHigh(uint256 ratio);

    event ProcessorMaxBaseAssetsDeltaRatioSet(uint256 oldRatio, uint256 newRatio);
    event ProcessorMaxSupplyDeltaRatioSet(uint256 oldRatio, uint256 newRatio);

    /// @notice Role identifier for processor executors.
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    function initialize(address _vault, address defaultAdmin, address processorManager) external initializer {
        __AccessControl_init();

        ProcessorManagerStorage storage $ = _getProcessorManagerStorage();
        $.vault = IVault(_vault);
        $.maxProcessorBaseAssetsDeltaRatio = RATIO_DENOMINATOR;
        $.maxProcessorSupplyDeltaRatio = RATIO_DENOMINATOR;

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PROCESSOR_ROLE, processorManager);
    }

    function _getProcessorManagerStorage() internal pure returns (ProcessorManagerStorage storage $) {
        assembly {
            // keccak256(abi.encode(uint256(keccak256("yieldnest.storage.ProcessorManager")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0xf77153a4e589060b003b517c9d04418c011940e855a6a02891843866b9734d00
        }
    }

    function vault() public view returns (IVault) {
        return _getProcessorManagerStorage().vault;
    }

    function maxProcessorBaseAssetsDeltaRatio() public view returns (uint256) {
        return _getProcessorManagerStorage().maxProcessorBaseAssetsDeltaRatio;
    }

    function maxProcessorSupplyDeltaRatio() public view returns (uint256) {
        return _getProcessorManagerStorage().maxProcessorSupplyDeltaRatio;
    }

    /**
     * @notice Execute a batch of processor calls on the vault.
     * @dev In cached-accounting mode, syncs accounting before and after execution.
     * @param _targets The target addresses for each call.
     * @param _values The ETH values to send with each call.
     * @param _data The calldata payload for each call.
     * @return results The return data for each processor call.
     */
    function processor(address[] memory _targets, uint256[] memory _values, bytes[] memory _data)
        public
        onlyRole(PROCESSOR_ROLE)
        returns (bytes[] memory results)
    {
        if (_targets.length != _values.length || _targets.length != _data.length) revert LengthMismatch();

        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }

        uint256 beforeTotalBaseAssets = vault().totalBaseAssets();
        uint256 beforeTotalSupply = vault().totalSupply();

        results = vault().processor(_targets, _values, _data);

        // trigger recomputation since deltas are very likely
        if (!vault().alwaysComputeTotalAssets()) {
            vault().processAccounting();
        }

        uint256 afterTotalBaseAssets = vault().totalBaseAssets();
        uint256 afterTotalSupply = vault().totalSupply();

        if (_ratioDelta(beforeTotalBaseAssets, afterTotalBaseAssets) > maxProcessorBaseAssetsDeltaRatio()) {
            revert TotalBaseAssetsDeltaExceeded(beforeTotalBaseAssets, afterTotalBaseAssets);
        }

        if (_ratioDelta(beforeTotalSupply, afterTotalSupply) > maxProcessorSupplyDeltaRatio()) {
            revert TotalSupplyDeltaExceeded(beforeTotalSupply, afterTotalSupply);
        }

        // No need to call processAccounting again since storage value doesn't actually change,
        // assuming there was no revert condition.
    }

    /**
     * @notice Set the maximum allowed processor base-assets delta ratio.
     * @param _maxProcessorBaseAssetsDeltaRatio The new base-assets delta ratio scaled by `RATIO_DENOMINATOR`.
     */
    function setMaxProcessorBaseAssetsDeltaRatio(uint256 _maxProcessorBaseAssetsDeltaRatio)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_maxProcessorBaseAssetsDeltaRatio > RATIO_DENOMINATOR) {
            revert RatioTooHigh(_maxProcessorBaseAssetsDeltaRatio);
        }

        ProcessorManagerStorage storage $ = _getProcessorManagerStorage();
        emit ProcessorMaxBaseAssetsDeltaRatioSet($.maxProcessorBaseAssetsDeltaRatio, _maxProcessorBaseAssetsDeltaRatio);
        $.maxProcessorBaseAssetsDeltaRatio = _maxProcessorBaseAssetsDeltaRatio;
    }

    /**
     * @notice Set the maximum allowed processor supply delta ratio.
     * @param _maxProcessorSupplyDeltaRatio The new supply delta ratio scaled by `RATIO_DENOMINATOR`.
     */
    function setMaxProcessorSupplyDeltaRatio(uint256 _maxProcessorSupplyDeltaRatio)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_maxProcessorSupplyDeltaRatio > RATIO_DENOMINATOR) {
            revert RatioTooHigh(_maxProcessorSupplyDeltaRatio);
        }

        ProcessorManagerStorage storage $ = _getProcessorManagerStorage();
        emit ProcessorMaxSupplyDeltaRatioSet($.maxProcessorSupplyDeltaRatio, _maxProcessorSupplyDeltaRatio);
        $.maxProcessorSupplyDeltaRatio = _maxProcessorSupplyDeltaRatio;
    }

    /**
     * @notice Compute the absolute percentage delta between two values.
     * @param beforeValue The baseline value before a change.
     * @param afterValue The value after a change.
     * @return The absolute delta scaled by `RATIO_DENOMINATOR`.
     */
    function _ratioDelta(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256) {
        if (beforeValue == afterValue) return 0;

        uint256 delta = beforeValue > afterValue ? beforeValue - afterValue : afterValue - beforeValue;
        uint256 baseline = beforeValue == 0 ? 1 : beforeValue;

        return (delta * RATIO_DENOMINATOR) / baseline;
    }
}
