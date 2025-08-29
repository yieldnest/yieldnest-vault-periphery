// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {console} from "forge-std/console.sol";

contract ProcessAccountingGuardHook is IHooks {
    error TotalAssetsDecreasedTooMuch(uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxDecreaseRatio);
    error TotalAssetsIncreasedTooMuch(uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxIncreaseRatio);
    error OnlyOwner();
    error NotSupported();
    error OnlyVault();
    error ConvertToAssetsChangedDuringDeposit(uint256 valueBefore, uint256 valueAfter);

    uint256 public constant RATIO_DENOMINATOR = 1e18;
    uint256 public constant CONVERT_TO_SHARES_TSTORE_SLOT = 0x01;

    IVault public immutable VAULT;
    address public owner;
    uint256 public maxDecreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)
    uint256 public maxIncreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    constructor(address _vault, address _owner, uint256 _maxDecreaseRatio, uint256 _maxIncreaseRatio) {
        VAULT = IVault(_vault);
        owner = _owner;
        maxDecreaseRatio = _maxDecreaseRatio;
        maxIncreaseRatio = _maxIncreaseRatio;
    }

    function setMaxDecreaseRatio(uint256 _maxDecreaseRatio) external onlyOwner {
        maxDecreaseRatio = _maxDecreaseRatio;
    }

    function setMaxIncreaseRatio(uint256 _maxIncreaseRatio) external onlyOwner {
        maxIncreaseRatio = _maxIncreaseRatio;
    }

    function getConfig() external pure override returns (Config memory) {
        return Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: true,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: true,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
    }

    function setConfig(Config memory) external pure override {
        revert NotSupported();
    }

    /**
     * @notice Check if the total assets decreased too much or increased too much
     */
    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256,
        uint256,
        uint256,
        uint256
    ) external view override onlyVault {
        if (totalAssetsBeforeAccounting == 0) return; // Skip check if starting from zero

        if (totalAssetsAfterAccounting < totalAssetsBeforeAccounting) {
            // Check for excessive decrease
            uint256 decrease = totalAssetsBeforeAccounting - totalAssetsAfterAccounting;
            uint256 decreaseRatio = (decrease * RATIO_DENOMINATOR) / totalAssetsBeforeAccounting;
            if (decreaseRatio > maxDecreaseRatio) {
                revert TotalAssetsDecreasedTooMuch(
                    totalAssetsBeforeAccounting, totalAssetsAfterAccounting, maxDecreaseRatio
                );
            }
        } else if (totalAssetsAfterAccounting > totalAssetsBeforeAccounting) {
            // Check for excessive increase
            uint256 increase = totalAssetsAfterAccounting - totalAssetsBeforeAccounting;
            uint256 increaseRatio = (increase * RATIO_DENOMINATOR) / totalAssetsBeforeAccounting;
            if (increaseRatio > maxIncreaseRatio) {
                revert TotalAssetsIncreasedTooMuch(
                    totalAssetsBeforeAccounting, totalAssetsAfterAccounting, maxIncreaseRatio
                );
            }
        }
    }

    /// REDEEM AND WITHDRAW RATE CHECKS ///

    function beforeRedeem(address, uint256, address, address, address, uint256) external override onlyVault {
        // Store the convertToAssets(1e18) value in transient storage
        storeConvertToAssets();
    }

    function afterRedeem(address, uint256, address, address, address, uint256) external view override onlyVault {
        // Compare the convertToAssets(1e18) value in transient storage with the current value
        // and check that the rate did not change
        compareConvertToAssets();
    }

    function beforeWithdraw(address, uint256, address, address, address, uint256) external override onlyVault {
        // Store the convertToAssets(1e18) value in transient storage
        storeConvertToAssets();
    }

    function afterWithdraw(address, uint256, address, address, address, uint256) external view override onlyVault {
        // Compare the convertToAssets(1e18) value in transient storage with the current value
        // and check that the rate did not change
        compareConvertToAssets();
    }

    /**
     * @notice Store the convertToAssets(1e18) value in transient storage
     */
    function storeConvertToAssets() internal {
        uint256 convertToAssetsValue = VAULT.convertToAssets(1e18);
        assembly {
            tstore(CONVERT_TO_SHARES_TSTORE_SLOT, convertToAssetsValue)
        }
    }

    /**
     * @notice Compare the convertToAssets(1e18) value in transient storage with the current value
     */
    function compareConvertToAssets() internal view {
        uint256 storedValue;
        assembly {
            storedValue := tload(CONVERT_TO_SHARES_TSTORE_SLOT)
        }
        uint256 currentValue = VAULT.convertToAssets(1e18);
        uint256 delta = currentValue > storedValue ? currentValue - storedValue : storedValue - currentValue;
        // Rate should not change by more than 10 wei
        if (delta >= 10 wei) {
            revert ConvertToAssetsChangedDuringDeposit(storedValue, currentValue);
        }
    }

    /// UNUSED HOOKS ///

    function beforeDeposit(address, uint256, address, address, uint256, uint256) external pure override {
        // Not implemented
    }

    function afterDeposit(address, uint256, address, address, uint256, uint256) external pure override {
        // Not implemented
    }

    function beforeMint(address, uint256, address, address, uint256, uint256) external pure override {
        // Not implemented
    }

    function afterMint(address, uint256, address, address, uint256, uint256) external pure override {
        // Not implemented
    }

    function beforeProcessAccounting(uint256, uint256, uint256) external pure override {
        // Not implemented
    }
}
