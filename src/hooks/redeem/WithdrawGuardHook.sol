// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {BaseRedemptionGuardHook} from "src/hooks/redeem/BaseRedemptionGuardHook.sol";

contract WithdrawGuardHook is BaseRedemptionGuardHook {
    constructor(address _vault) BaseRedemptionGuardHook(_vault) {}

    function getConfig() external pure override returns (Config memory) {
        return Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: true,
            afterWithdraw: true,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });
    }

    /// WITHDRAW RATE CHECKS ///

    function beforeWithdraw(address, uint256, address, address, address, uint256) external override onlyVault {
        storeConvertToAssets();
    }

    function afterWithdraw(address, uint256, address, address, address, uint256) external override onlyVault {
        // Compare the convertToAssets(1e18) value in transient storage with the current value
        // and check that the rate did not change
        compareConvertToAssets();
    }
}
