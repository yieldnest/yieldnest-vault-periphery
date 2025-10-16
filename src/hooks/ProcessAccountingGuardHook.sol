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

    string public constant VERSION = "0.1.1";

    error TotalAssetsDecreasedTooMuch(
        uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxTotalAssetsDecreaseRatio
    );
    error TotalAssetsIncreasedTooMuch(
        uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 maxTotalAssetsIncreaseRatio
    );
    error OnlyOwner();
    error NotSupported();
    error OnlyVault();
    error TotalSupplyDecreased();
    error TotalSupplyIncreasedForLoss();
    error TotalSupplyIncreasedTooMuch(uint256 totalSupplyBefore, uint256 totalSupplyAfter);
    error AlwaysComputeTotalAssetsIsEnabled();

    event MaxTotalAssetsDecreaseRatioSet(uint256 oldRatio, uint256 newRatio);
    event MaxTotalAssetsIncreaseRatioSet(uint256 oldRatio, uint256 newRatio);
    event MaxTotalSupplyIncreaseRatioSet(uint256 oldRatio, uint256 newRatio);
    event ExpectedPerformanceFeeSet(uint256 oldFee, uint256 newFee);

    uint256 public constant RATIO_DENOMINATOR = 1e18;
    uint256 public constant FEE_DENOMINATOR = 1e18;

    IVault public immutable VAULT;

    /// @notice The owner controls configuration settings
    address public immutable owner;
    /// @notice The maximum total assets decrease ratio during processAccounting()
    uint256 public maxTotalAssetsDecreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)
    /// @notice The maximum total assets increase ratio during processAccounting()
    uint256 public maxTotalAssetsIncreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)
    /// @notice The maximum total supply increase ratio during processAccounting()
    uint256 public maxTotalSupplyIncreaseRatio; // as a ratio with RATIO_DENOMINATOR (1e18 = 100%)

    uint256 public expectedPerformanceFee;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) revert OnlyVault();
        _;
    }

    /**
     * @notice Constructor
     * @param _vault The address of the vault
     * @param _owner The address of the owner
     * @param _maxTotalAssetsDecreaseRatio The maximum total assets decrease ratio
     * @param _maxTotalAssetsIncreaseRatio The maximum total assets increase ratio
     * @param _maxTotalSupplyIncreaseRatio The maximum total supply increase ratio
     * @param _expectedPerformanceFee The expected performance fee
     */
    constructor(
        address _vault,
        address _owner,
        uint256 _maxTotalAssetsDecreaseRatio,
        uint256 _maxTotalAssetsIncreaseRatio,
        uint256 _maxTotalSupplyIncreaseRatio,
        uint256 _expectedPerformanceFee
    ) {
        VAULT = IVault(_vault);
        owner = _owner;
        maxTotalAssetsDecreaseRatio = _maxTotalAssetsDecreaseRatio;
        maxTotalAssetsIncreaseRatio = _maxTotalAssetsIncreaseRatio;
        maxTotalSupplyIncreaseRatio = _maxTotalSupplyIncreaseRatio;

        expectedPerformanceFee = _expectedPerformanceFee;
    }

    /// @inheritdoc IHooks
    function name() external pure returns (string memory) {
        return "ProcessAccountingGuardHook";
    }

    /**
     * @notice Set the maximum totalAssets decrease ratio
     * @param _maxTotalAssetsDecreaseRatio The maximum totalAssets decrease ratio
     */
    function setMaxTotalAssetsDecreaseRatio(uint256 _maxTotalAssetsDecreaseRatio) external onlyOwner {
        uint256 old = maxTotalAssetsDecreaseRatio;
        maxTotalAssetsDecreaseRatio = _maxTotalAssetsDecreaseRatio;
        emit MaxTotalAssetsDecreaseRatioSet(old, _maxTotalAssetsDecreaseRatio);
    }

    /**
     * @notice Set the maximum totalAssets increase ratio
     * @param _maxTotalAssetsIncreaseRatio The maximum totalAssets increase ratio
     */
    function setMaxTotalAssetsIncreaseRatio(uint256 _maxTotalAssetsIncreaseRatio) external onlyOwner {
        uint256 old = maxTotalAssetsIncreaseRatio;
        maxTotalAssetsIncreaseRatio = _maxTotalAssetsIncreaseRatio;
        emit MaxTotalAssetsIncreaseRatioSet(old, _maxTotalAssetsIncreaseRatio);
    }

    /**
     * @notice Set the maximum totalSupply increase ratio
     * @param _maxTotalSupplyIncreaseRatio The maximum totalSupply increase ratio
     */
    function setMaxTotalSupplyIncreaseRatio(uint256 _maxTotalSupplyIncreaseRatio) external onlyOwner {
        uint256 old = maxTotalSupplyIncreaseRatio;
        maxTotalSupplyIncreaseRatio = _maxTotalSupplyIncreaseRatio;
        emit MaxTotalSupplyIncreaseRatioSet(old, _maxTotalSupplyIncreaseRatio);
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

    /// @inheritdoc IHooks
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

    /**
     * @notice Check if the total assets changed too much to the downside or upside
     * @dev This check protects against anomalous rate changes for the vault.
     * @dev Prevents processAccounting from running if totalAssets change falls outside bounds.
     * @param params The parameters for the afterProcessAccounting function
     */
    function checkTotalAssetsChange(AfterProcessAccountingParams memory params) public view {
        if (params.totalAssetsAfterAccounting < params.totalAssetsBeforeAccounting) {
            // Check for excessive decrease
            uint256 decrease = params.totalAssetsBeforeAccounting - params.totalAssetsAfterAccounting;
            uint256 decreaseRatio = (decrease * RATIO_DENOMINATOR) / params.totalAssetsBeforeAccounting;
            if (decreaseRatio > maxTotalAssetsDecreaseRatio) {
                revert TotalAssetsDecreasedTooMuch(
                    params.totalAssetsBeforeAccounting, params.totalAssetsAfterAccounting, maxTotalAssetsDecreaseRatio
                );
            }
        } else if (params.totalAssetsAfterAccounting > params.totalAssetsBeforeAccounting) {
            // Check for excessive increase
            uint256 increase = params.totalAssetsAfterAccounting - params.totalAssetsBeforeAccounting;
            uint256 increaseRatio = (increase * RATIO_DENOMINATOR) / params.totalAssetsBeforeAccounting;

            if (increaseRatio > maxTotalAssetsIncreaseRatio) {
                revert TotalAssetsIncreasedTooMuch(
                    params.totalAssetsBeforeAccounting, params.totalAssetsAfterAccounting, maxTotalAssetsIncreaseRatio
                );
            }
        }
    }

    /**
     * @notice Check if the total supply changed too much to the upside (decrease not permitted.)
     * @dev This check protects against anomalous supply changes for the vault.
     * @dev Prevents processAccounting from running if totalSupply change falls outside bounds.
     * @param params The parameters for the afterProcessAccounting function
     */
    function checkTotalSupplyChange(AfterProcessAccountingParams memory params) public view {
        uint256 totalSupplyAfterAccounting = VAULT.totalSupply();

        if (totalSupplyAfterAccounting < params.totalSupplyBeforeAccounting) {
            // total supply must not decrease
            revert TotalSupplyDecreased();
        }

        checkTotalSupplyIncreaseRatio(params.totalSupplyBeforeAccounting, totalSupplyAfterAccounting);
        checkTotalSupplyIncreaseGivenPerformanceFee(
            params.totalSupplyBeforeAccounting,
            totalSupplyAfterAccounting,
            params.totalBaseAssetsBeforeAccounting,
            params.totalBaseAssetsAfterAccounting,
            params.totalAssetsAfterAccounting
        );
    }

    /**
     * @notice Check if the total supply increased too much with respect to a max ratio change
     * @dev This check protects against anomalous supply changes for the vault.
     * @dev Prevents processAccounting from running if totalSupply increase falls outside bounds.
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalSupplyAfterAccounting The total supply after accounting
     */
    function checkTotalSupplyIncreaseRatio(uint256 totalSupplyBeforeAccounting, uint256 totalSupplyAfterAccounting)
        public
        view
    {
        uint256 totalSupplyIncrease = totalSupplyAfterAccounting - totalSupplyBeforeAccounting;
        uint256 _maxTotalSupplyIncreaseRatio = maxTotalSupplyIncreaseRatio;
        uint256 totalSupplyIncreaseRatio = (totalSupplyIncrease * RATIO_DENOMINATOR) / totalSupplyBeforeAccounting;

        if (totalSupplyIncreaseRatio > _maxTotalSupplyIncreaseRatio) {
            revert TotalSupplyIncreasedTooMuch(totalSupplyBeforeAccounting, totalSupplyAfterAccounting);
        }
    }

    /**
     * @notice Check if the total supply increased too much with respect to the expected performance fee
     * @dev This check protects against anomalous supply changes for the vault.
     * @dev Prevents processAccounting from running if totalSupply increases more than what the fee predicts.
     * @param totalSupplyBeforeAccounting The total supply before accounting
     * @param totalSupplyAfterAccounting The total supply after accounting
     */
    function checkTotalSupplyIncreaseGivenPerformanceFee(
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting,
        uint256 totalBaseAssetsBeforeAccounting,
        uint256 totalBaseAssetsAfterAccounting,
        uint256 /* totalAssetsAfterAccounting */
    ) public view {
        uint256 totalSupplyIncrease = totalSupplyAfterAccounting - totalSupplyBeforeAccounting;
        if (totalSupplyIncrease > 0) {
            if (totalBaseAssetsAfterAccounting <= totalBaseAssetsBeforeAccounting) {
                // no shares should be minted for loss
                revert TotalSupplyIncreasedForLoss();
            }

            uint256 totalBaseAssetsIncrease = totalBaseAssetsAfterAccounting - totalBaseAssetsBeforeAccounting;

            uint256 maxFeeInBaseAssets =
                totalBaseAssetsIncrease.mulDiv(expectedPerformanceFee, FEE_DENOMINATOR, Math.Rounding.Floor);

            // maxShares is a looser bound that ensures the fee asset amount converted to vault shares at rate post mint
            // is less than or equal to the total supply increase
            uint256 maxShares = convertToShares(
                maxFeeInBaseAssets, totalSupplyAfterAccounting, totalBaseAssetsAfterAccounting, Math.Rounding.Floor
            );

            if (totalSupplyIncrease > maxShares) {
                revert TotalSupplyIncreasedTooMuch(totalSupplyBeforeAccounting, totalSupplyAfterAccounting);
            }
        }
    }

    /**
     * @notice Internal function to convert assets to shares
     * @dev This function replicates BaseVault functionality for internal use
     * @param assets The assets to convert
     * @param totalSupply The total supply
     * @param totalAssets The total assets
     * @param rounding The rounding mode
     * @return The shares
     */
    function convertToShares(uint256 assets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return assets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
    }

    /// UNUSED HOOKS ///

    /// @inheritdoc IHooks
    function beforeDeposit(DepositParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function afterDeposit(DepositParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function beforeMint(MintParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function afterMint(MintParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function beforeRedeem(RedeemParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function afterRedeem(RedeemParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function beforeWithdraw(WithdrawParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function afterWithdraw(WithdrawParams memory) external pure override {
        // Not implemented
    }

    /// @inheritdoc IHooks
    function beforeProcessAccounting(BeforeProcessAccountingParams memory) external pure override {
        // Not implemented
    }
}
