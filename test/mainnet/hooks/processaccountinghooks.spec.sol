// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {BaseMainnetIntegrationTest} from "./BaseMainnetIntegrationTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PermissionedVaultHook} from "test/testhooks/PermissionedVaultHook.sol";
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "lib/yieldnest-vault/src/Common.sol";
// Minimal mock for IHooks

contract ProcessAccountingHooksIntegrationTest is BaseMainnetIntegrationTest {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_deposit_and_processAccounting_multiple_times_success() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalShares = 0;
        uint256 prevFeeReceiverBalance = vault.balanceOf(feeReceiver);
        for (uint256 i = 0; i < 5; i++) {
            // Deposit as whitelisted user
            deal(vault.asset(), depositor, depositAmount);
            vm.startPrank(depositor);
            IERC20(vault.asset()).approve(address(vault), depositAmount);
            uint256 shares = vault.deposit(depositAmount, depositor);
            vm.stopPrank();

            expectedTotalShares += shares;

            // Verify deposit was successful
            assertEq(vault.balanceOf(depositor), expectedTotalShares);

            // Process accounting should succeed (within allowed ratio bounds)
            vm.startPrank(PROCESSOR);
            vault.processAccounting();
            vm.stopPrank();

            // Assert performance fee recipient balance does not increase
            uint256 currentFeeReceiverBalance = vault.balanceOf(feeReceiver);
            assertEq(currentFeeReceiverBalance, prevFeeReceiverBalance, "Fee receiver balance should not increase");
            prevFeeReceiverBalance = currentFeeReceiverBalance;
        }
    }

    function test_deposit_and_processAccounting_with_fees_success() public {
        uint256 depositAmount = 100 ether;
        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), shares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 totalAssetsAfter = vault.totalAssets();

        assertGt(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");
        uint256 supplyIncrease = totalSupplyAfter - totalSupplyBefore;
        uint256 assetsIncrease = totalAssetsAfter - totalAssetsBefore;

        // Calculate expected supply increase after performance fee (0.1%)
        uint256 expectedSupplyIncrease = vault.convertToShares(assetsIncrease  * feeHooks.performanceFee() / 1 ether);

        // Allow for rounding error of 1 wei
        assertApproxEqAbs(supplyIncrease, expectedSupplyIncrease, 1, "Supply increase should match assets increase minus fee");

        
    }
}