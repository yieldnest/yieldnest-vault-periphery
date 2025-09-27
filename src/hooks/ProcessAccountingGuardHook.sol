// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title ProcessAccountingGuardHook
 * @notice This hook is used to check for excessive totalAssets changes
 *         when calling the processAccounting function for the vault.
 * It checks if the total assets decreased too much or increased too much.
 * It is used to prevent the vault from being exposed to anomalous totalAssets fluctuations.
 * which can be a result of oracle manipulation or 3rd party protocol failures.
 * the processAccounting call reverts if the totalAssets changed too much.
 */
contract ProcessAccountingGuardHook is IHooks {
    using Math for uint256;

    error TotalAssetsDecreasedTooMuch(uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxDecreaseRatio);
    error TotalAssetsIncreasedTooMuch(uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxIncreaseRatio);
    error OnlyOwner();
    error NotSupported();
    error OnlyVault();
    error ConvertToAssetsChangedDuringDeposit(uint256 valueBefore, uint256 valueAfter);
    error TotalSupplyDecreased();
    error TotalSupplyIncreasedForLoss();
    error TotalSupplyIncreasedTooMuch(uint256 totalSupplyBefore, uint256 totalSupplyAfter, uint256 maxShares);
    error AlwaysComputeTotalAssetsIsEnabled();

    event MaxDecreaseRatioSet(uint256 oldRatio, uint256 newRatio);
    event MaxIncreaseRatioSet(uint256 oldRatio, uint256 newRatio);
    event ExpectedPerformanceFeeSet(uint256 oldFee, uint256 newFee);

    uint256 public constant RATIO_DENOMINATOR = 1e18;
    uint256 public constant FEE_DENOMINATOR = 1e18;

    IVault public immutable VAULT;
    address public immutable owner;
    uint256 public maxDecreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)
    uint256 public maxIncreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)

    uint256 public expectedPerformanceFee;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    constructor(
        address _vault,
        address _owner,
        uint256 _maxDecreaseRatio,
        uint256 _maxIncreaseRatio,
        uint256 _expectedPerformanceFee
    ) {
        VAULT = IVault(_vault);
        owner = _owner;
        maxDecreaseRatio = _maxDecreaseRatio;
        maxIncreaseRatio = _maxIncreaseRatio;
        expectedPerformanceFee = _expectedPerformanceFee;
    }

    function name() external pure returns (string memory) {
        return "ProcessAccountingGuardHook";
    }

    /**
     * @notice Set the maximum decrease ratio
     * @param _maxDecreaseRatio The maximum decrease ratio
     */
    function setMaxDecreaseRatio(uint256 _maxDecreaseRatio) external onlyOwner {
        uint256 old = maxDecreaseRatio;
        maxDecreaseRatio = _maxDecreaseRatio;
        emit MaxDecreaseRatioSet(old, _maxDecreaseRatio);
    }

    /**
     * @notice Set the maximum increase ratio
     * @param _maxIncreaseRatio The maximum increase ratio
     */
    function setMaxIncreaseRatio(uint256 _maxIncreaseRatio) external onlyOwner {
        uint256 old = maxIncreaseRatio;
        maxIncreaseRatio = _maxIncreaseRatio;
        emit MaxIncreaseRatioSet(old, _maxIncreaseRatio);
    }

    /**
     * @notice Set the expected performance fee
     * @param _expectedPerformanceFee The expected performance fee
     */
    function setExpectedPerformanceFee(uint256 _expectedPerformanceFee) external onlyOwner {
        uint256 old = expectedPerformanceFee;
        expectedPerformanceFee = _expectedPerformanceFee;
        emit ExpectedPerformanceFeeSet(old, _expectedPerformanceFee);
    }

    function getConfig() external pure override returns (Config memory) {
        return Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
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
    function afterProcessAccounting(AfterProcessAccountingParams memory params) external view override onlyVault {
        if (VAULT.alwaysComputeTotalAssets()) {
            revert AlwaysComputeTotalAssetsIsEnabled();
        }

        if (params.totalAssetsBeforeAccounting == 0) return; // Skip check if starting from zero

        checkTotalAssetsChange(params);
        checkTotalSupplyChange(params);
    }

    function checkTotalAssetsChange(AfterProcessAccountingParams memory params) internal view {
        if (params.totalAssetsAfterAccounting < params.totalAssetsBeforeAccounting) {
            // Check for excessive decrease
            uint256 decrease = params.totalAssetsBeforeAccounting - params.totalAssetsAfterAccounting;
            uint256 decreaseRatio = (decrease * RATIO_DENOMINATOR) / params.totalAssetsBeforeAccounting;
            if (decreaseRatio > maxDecreaseRatio) {
                revert TotalAssetsDecreasedTooMuch(
                    params.totalAssetsBeforeAccounting, params.totalAssetsAfterAccounting, maxDecreaseRatio
                );
            }
        } else if (params.totalAssetsAfterAccounting > params.totalAssetsBeforeAccounting) {
            // Check for excessive increase
            uint256 increase = params.totalAssetsAfterAccounting - params.totalAssetsBeforeAccounting;
            uint256 increaseRatio = (increase * RATIO_DENOMINATOR) / params.totalAssetsBeforeAccounting;
            if (increaseRatio > maxIncreaseRatio) {
                revert TotalAssetsIncreasedTooMuch(
                    params.totalAssetsBeforeAccounting, params.totalAssetsAfterAccounting, maxIncreaseRatio
                );
            }
        }
    }

    function checkTotalSupplyChange(AfterProcessAccountingParams memory params) internal view {
        uint256 totalSupplyAfterAccounting = VAULT.totalSupply();

        if (totalSupplyAfterAccounting < params.totalSupplyBeforeAccounting) {
            // total supply must not decrease
            revert TotalSupplyDecreased();
        }

        uint256 totalSupplyIncrease = totalSupplyAfterAccounting - params.totalSupplyBeforeAccounting;

        if (totalSupplyIncrease > 0) {
            if (params.totalBaseAssetsAfterAccounting <= params.totalBaseAssetsBeforeAccounting) {
                // no shares should be minted for loss
                revert TotalSupplyIncreasedForLoss();
            }

            uint256 totalBaseAssetsIncrease =
                params.totalBaseAssetsAfterAccounting - params.totalBaseAssetsBeforeAccounting;

            uint256 maxFeeInBaseAssets =
                totalBaseAssetsIncrease.mulDiv(expectedPerformanceFee, FEE_DENOMINATOR, Math.Rounding.Floor);

            // maxShares is a looser bound that ensures the fee asset amount converted to vault shares at rate post mint
            // is less than or equal to the total supply increase
            uint256 maxShares = convertToShares(
                maxFeeInBaseAssets, totalSupplyAfterAccounting, params.totalAssetsAfterAccounting, Math.Rounding.Floor
            );

            if (totalSupplyIncrease > maxShares) {
                revert TotalSupplyIncreasedTooMuch(
                    params.totalSupplyBeforeAccounting, totalSupplyAfterAccounting, maxShares
                );
            }
        }
    }

    function convertToShares(uint256 assets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return assets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
    }

    /// UNUSED HOOKS ///

    function beforeDeposit(DepositParams memory) external pure override {
        // Not implemented
    }

    function afterDeposit(DepositParams memory) external pure override {
        // Not implemented
    }

    function beforeMint(MintParams memory) external pure override {
        // Not implemented
    }

    function afterMint(MintParams memory) external pure override {
        // Not implemented
    }

    function beforeRedeem(RedeemParams memory) external pure override {
        // Not implemented
    }

    function afterRedeem(RedeemParams memory) external pure override {
        // Not implemented
    }

    function beforeWithdraw(WithdrawParams memory) external pure override {
        // Not implemented
    }

    function afterWithdraw(WithdrawParams memory) external pure override {
        // Not implemented
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external pure override {
        // Not implemented
    }
}
