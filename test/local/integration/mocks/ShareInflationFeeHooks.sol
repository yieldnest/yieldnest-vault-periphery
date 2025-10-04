// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FeeHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

contract ShareInflationFeeHooks is FeeHooks {
    using Math for uint256;

    uint256 public fixedMintAmount;

    constructor(
        address _vault,
        address _owner,
        uint256 _performanceFee,
        address _performanceFeeRecipient,
        Config memory _config
    ) FeeHooks(_vault, _owner, _performanceFee, _performanceFeeRecipient, _config) {}

    function setFixedMintAmount(uint256 _fixedMintAmount) external {
        fixedMintAmount = _fixedMintAmount;
    }

    function afterProcessAccounting(AfterProcessAccountingParams calldata params) external override onlyVault {
        if (fixedMintAmount > 0) {
            VAULT.mintShares(performanceFeeRecipient, fixedMintAmount);
            return;
        }

        uint256 totalSupplyBeforeAccounting = VAULT.totalSupply();
        {
            if (VAULT.alwaysComputeTotalAssets()) {
                revert AlwaysComputeTotalAssetsIsEnabled();
            }

            // if there is increase in total base assets, then there is yield earned
            if (params.totalBaseAssetsAfterAccounting > params.totalBaseAssetsBeforeAccounting) {
                // calculate the yield earned and fees accrued
                uint256 yieldEarnedInBaseAsset =
                    params.totalBaseAssetsAfterAccounting - params.totalBaseAssetsBeforeAccounting;
                uint256 feesAccruedInBaseAsset = (yieldEarnedInBaseAsset * performanceFee) / FEE_DENOMINATOR;

                if (feesAccruedInBaseAsset > 0) {
                    // totalBaseAssetsAfterAccounting already includes the fees accrued
                    uint256 sharesToMint = feesAccruedInBaseAsset.mulDiv(
                        params.totalSupplyBeforeAccounting,
                        params.totalBaseAssetsAfterAccounting - feesAccruedInBaseAsset,
                        Math.Rounding.Floor
                    );
                    if (sharesToMint > 0) {
                        VAULT.mintShares(performanceFeeRecipient, sharesToMint);
                        emit PerformanceFeeCharged(
                            performanceFeeRecipient,
                            sharesToMint,
                            feesAccruedInBaseAsset,
                            params.totalBaseAssetsBeforeAccounting,
                            params.totalBaseAssetsAfterAccounting,
                            params.totalSupplyBeforeAccounting
                        );
                    }
                }
            }
        }

        uint256 totalSupplyAfterAccounting = VAULT.totalSupply();

        // double mint
        VAULT.mintShares(address(this), totalSupplyAfterAccounting - totalSupplyBeforeAccounting);
    }
}
