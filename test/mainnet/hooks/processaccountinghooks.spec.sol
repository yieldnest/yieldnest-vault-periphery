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

        // Assert that convertToAssets increased after processAccounting
        uint256 assetsPerShareBefore = vault.convertToAssets(1 ether);

        uint256 feeReceiverBalanceBefore = vault.balanceOf(feeReceiver);

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        assertGt(
            vault.convertToAssets(1 ether),
            assetsPerShareBefore,
            "convertToAssets should increase after processAccounting"
        );

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 totalAssetsAfter = vault.totalAssets();

        assertGt(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");
        uint256 supplyIncrease = totalSupplyAfter - totalSupplyBefore;
        uint256 assetsIncrease = totalAssetsAfter - totalAssetsBefore;

        // Calculate expected supply increase after performance fee (0.1%)
        uint256 expectedSupplyIncrease = vault.convertToShares(assetsIncrease * feeHooks.performanceFee() / 1 ether);

        // Allow for rounding error of 1 wei
        assertApproxEqAbs(
            supplyIncrease, expectedSupplyIncrease, 1, "Supply increase should match assets increase minus fee"
        );

        assertEq(
            vault.balanceOf(feeReceiver) - feeReceiverBalanceBefore,
            supplyIncrease,
            "Fee receiver balance should equal supply increase"
        );
    }

    function test_deposit_donate_and_processAccounting_revert(uint256 depositAmount, uint256 donationAmount) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        donationAmount = bound(donationAmount, 1, depositAmount * 10); // Cap donation to 10x the deposit amount

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, depositor);
        vm.stopPrank();
        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), shares, "Depositor balance should match deposit shares");
        uint256 totalAssetsBefore = vault.totalAssets();

        // Donate a large amount to trigger the increase ratio guard
        // This will cause totalAssets to increase significantly without corresponding shares
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalAssetsAfter = totalAssetsBefore + donationAmount;
        uint256 maxIncreaseRatio = processAccountingGuardHook.maxTotalAssetsIncreaseRatio();

        // Process accounting should revert due to exceeding maxIncreaseRatio
        // The donation increased assets significantly which should be above the maxIncreaseRatio limit
        vm.startPrank(PROCESSOR);
        // Calculate the actual increase ratio
        uint256 actualIncreaseRatio = ((totalAssetsAfter - totalAssetsBefore) * 1e18) / totalAssetsBefore;

        // Only expect revert if the increase ratio exceeds the maximum allowed
        if (actualIncreaseRatio > maxIncreaseRatio) {
            bytes memory revertData = abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalAssetsIncreasedTooMuch.selector,
                totalAssetsBefore,
                totalAssetsAfter,
                maxIncreaseRatio
            );
            vm.expectRevert(abi.encodeWithSelector(HooksLib.HookCallFailed.selector, revertData));
        }
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_deposit_donate_and_processAccounting_when_fee_doubles_reverts() public {
        // Bound inputs
        uint256 depositAmount = 100 ether;
        uint256 donationAmount = 0.001 ether; // low amount

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Donate a large amount to trigger the increase ratio guard
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        // Double the performance fee in feeHooks
        vm.startPrank(owner);
        uint256 oldFee = feeHooks.performanceFee();
        uint256 newFee = oldFee + oldFee / 10;
        feeHooks.setPerformanceFee(newFee);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        vm.expectRevert();
        vault.processAccounting();
        vm.stopPrank();
    }
}
