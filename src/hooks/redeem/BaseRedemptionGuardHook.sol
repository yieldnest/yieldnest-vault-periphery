// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {console} from "forge-std/console.sol";
import {TStore} from "src/lib/TStore.sol";

abstract contract BaseRedemptionGuardHook is IHooks {
    error NotSupported();
    error OnlyVault();
    error ConvertToAssetsDecreasedDuringRedemption(uint256 valueBefore, uint256 valueAfter);
    error ConvertToAssetsChangedDuringRedemption(uint256 valueBefore, uint256 valueAfter);
    error CheckInProgress();
    error CheckNotInProgress();

    bytes32 public constant CONVERT_TO_ASSETS_SLOT = bytes32(uint256(0x01));
    bytes32 public constant CHECK_IN_PROGRESS_SLOT = bytes32(uint256(0x02));

    IVault public immutable VAULT;
    uint256 public immutable maxDelta;

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    constructor(address _vault, uint256 _maxDelta) {
        VAULT = IVault(_vault);
        maxDelta = _maxDelta;
    }

    function setConfig(Config memory) external pure virtual override {
        revert NotSupported();
    }

    /**
     * @notice Store the convertToAssets(1e18) value in transient storage
     */
    function storeConvertToAssets() internal {
        if (TStore.loadBool(CHECK_IN_PROGRESS_SLOT)) revert CheckInProgress();

        uint256 convertToAssetsValue = VAULT.convertToAssets(1e18);
        TStore.store(CONVERT_TO_ASSETS_SLOT, convertToAssetsValue);
        TStore.store(CHECK_IN_PROGRESS_SLOT, true);
    }

    /**
     * @notice Compare the convertToAssets(1e18) value in transient storage with the current value
     */
    function compareConvertToAssets() internal {
        if (!TStore.loadBool(CHECK_IN_PROGRESS_SLOT)) revert CheckNotInProgress();

        uint256 currentValue = VAULT.convertToAssets(1e18);
        uint256 storedValue = TStore.loadUint256(CONVERT_TO_ASSETS_SLOT);

        if (currentValue < storedValue) {
            revert ConvertToAssetsDecreasedDuringRedemption(storedValue, currentValue);
        }

        uint256 delta = currentValue - storedValue;
        // Rate should not change by more than 10 wei
        if (delta >= maxDelta) {
            revert ConvertToAssetsChangedDuringRedemption(storedValue, currentValue);
        }

        TStore.store(CHECK_IN_PROGRESS_SLOT, false);
        TStore.clear(CONVERT_TO_ASSETS_SLOT);
    }

    /// UNUSED HOOKS ///

    function beforeWithdraw(address, uint256, address, address, address, uint256) external virtual override {
        // Not implemented
    }

    function afterWithdraw(address, uint256, address, address, address, uint256) external virtual override {
        // Not implemented
    }

    function beforeRedeem(address, uint256, address, address, address, uint256) external virtual override {
        // Not implemented
    }

    function afterRedeem(address, uint256, address, address, address, uint256) external virtual override {
        // Not implemented
    }

    function beforeDeposit(address, uint256, address, address, uint256, uint256) external virtual override {
        // Not implemented
    }

    function afterDeposit(address, uint256, address, address, uint256, uint256) external virtual override {
        // Not implemented
    }

    function beforeMint(address, uint256, address, address, uint256, uint256) external virtual override {
        // Not implemented
    }

    function afterMint(address, uint256, address, address, uint256, uint256) external pure virtual override {
        // Not implemented
    }

    function beforeProcessAccounting(uint256, uint256, uint256) external pure virtual override {
        // Not implemented
    }

    function afterProcessAccounting(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256,
        uint256,
        uint256,
        uint256
    ) external view virtual {
        // Not implemented
    }
}
