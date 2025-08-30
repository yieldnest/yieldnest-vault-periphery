// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PermissionedVaultHook} from "test/testhooks/PermissionedVaultHook.sol";
import {HooksLib, HookCallFailed} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";

// Minimal mock for IHooks
contract WithdrawHooksIntegrationTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_withdraw_permissionedVaultHook() public {
        // First deposit to have shares to withdraw
        uint256 depositAmount = 100 ether;
        uint256 bufferAmount = 80 ether;
        uint256 withdrawAmount = 50 ether;
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        uint256 initialShares = vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, bufferAmount, PROCESSOR);

        // Calculate expected shares to be burned for withdrawal (including fee)
        uint256 withdrawFee = vault._feeOnRaw(withdrawAmount, depositor);
        uint256 totalAssetsNeeded = withdrawAmount + withdrawFee;
        uint256 sharesToBurn = vault.convertToShares(totalAssetsNeeded);
        uint256 expectedRemainingShares = initialShares - sharesToBurn;
        uint256 expectedRemainingAssets = depositAmount - withdrawAmount;

        // Now withdraw
        vm.startPrank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);
        vm.stopPrank();
        assertEq(
            vault.balanceOf(depositor), expectedRemainingShares, "Depositor should have less shares after withdrawal"
        );
        assertEq(vault.totalAssets(), expectedRemainingAssets, "Vault should have less total assets after withdrawal");

        // Check that fee recipient received shares from the withdrawal fee
        address feeRecipient = feeHooks.performanceFeeRecipient();
        uint256 feeRecipientShares = vault.balanceOf(feeRecipient);
        uint256 expectedFeeShares = vault.convertToShares(withdrawFee);
        assertEq(
            feeRecipientShares, expectedFeeShares, "Fee recipient should have received exact fee shares from withdrawal"
        );
    }

    function test_withdraw_permissionedVaultHook_revert() public {
        address notWhitelisted = address(0xbeefee);

        // First deposit as whitelisted user to create shares
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);

        // Transfer shares to non-whitelisted user
        vault.transfer(notWhitelisted, 50 ether);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);

        // Try to withdraw as non-whitelisted user
        vm.startPrank(notWhitelisted);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        vault.withdraw(25 ether, notWhitelisted, notWhitelisted);
        vm.stopPrank();
    }

    function test_withdraw_after_donation() public {
        // First deposit to have shares to withdraw from
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        uint256 initialShares = vault.deposit(100 ether, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxIncreaseRatio(100e18); // 10000% increase allowed

        {
            // Donate assets to the vault through bob to increase totalAssets without minting shares
            uint256 donationAmount = 100 ether;
            address bob = makeAddr("bob");
            deal(vault.asset(), bob, donationAmount);
            vm.startPrank(bob);
            IERC20(vault.asset()).transfer(address(vault), donationAmount);
            vm.stopPrank();

            vault.processAccounting();
        }

        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 amountToWithdraw = 75 ether;
        // Now withdraw - should get more assets due to donation
        uint256 balanceBefore = IERC20(vault.asset()).balanceOf(depositor);
        vm.startPrank(depositor);
        uint256 sharesBurned = vault.withdraw(amountToWithdraw, depositor, depositor);
        vm.stopPrank();
        uint256 balanceAfter = IERC20(vault.asset()).balanceOf(depositor);
        uint256 assetsWithdrawn = balanceAfter - balanceBefore;

        assertEq(assetsWithdrawn, amountToWithdraw, "Assets withdrawn should be equal to the requested amount");
        // After donation, shares should be worth more, so we should have withdrawn the requested amount
        assertEq(vault.balanceOf(depositor), initialShares - sharesBurned, "Should have exact remaining shares");
        assertEq(
            vault.totalAssets(),
            totalAssetsBefore - amountToWithdraw,
            "Total assets should be equal to the sum of the initial total assets and the amount withdrawn"
        );
    }

    function test_redeem_permissionedVaultHook() public {
        uint256 initialAssets = 100 ether;
        // First deposit to have shares to redeem
        deal(vault.asset(), depositor, initialAssets);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), initialAssets);
        vault.deposit(initialAssets, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);

        uint256 sharesToRedeem = 50 ether;
        // Now redeem
        uint256 balanceBefore = IERC20(vault.asset()).balanceOf(depositor);
        uint256 sharesBefore = vault.balanceOf(depositor);
        vm.startPrank(depositor);
        uint256 amountRedeemed = vault.redeem(sharesToRedeem, depositor, depositor);
        vm.stopPrank();
        uint256 balanceAfter = IERC20(vault.asset()).balanceOf(depositor);

        vault.processAccounting();

        assertEq(vault.convertToAssets(1e18), 1e18, "Vault should have a 1:1 ratio of shares to assets");

        assertEq(vault.totalAssets(), vault.totalSupply());

        assertEq(balanceAfter - balanceBefore, amountRedeemed, "Depositor balance should increase by 50 ether");
        assertEq(
            vault.balanceOf(depositor), sharesBefore - sharesToRedeem, "Depositor should have 50 ether shares remaining"
        );

        assertEq(
            vault.balanceOf(feeHooks.performanceFeeRecipient()) + amountRedeemed,
            sharesToRedeem,
            "fee + redeem should be equal to 50 ether"
        );

        assertEq(
            vault.totalAssets() + balanceAfter,
            initialAssets,
            "assets redeemed + remaining assets should be equal to initial assets"
        );
    }

    function test_redeem_permissionedVaultHook_revert() public {
        address notWhitelisted = address(0xbeefee);

        // First deposit as whitelisted user to create shares
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);

        // Transfer shares to non-whitelisted user
        vault.transfer(notWhitelisted, 50 ether);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);

        // Try to redeem as non-whitelisted user
        vm.startPrank(notWhitelisted);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        vault.redeem(25 ether, notWhitelisted, notWhitelisted);
        vm.stopPrank();
    }

    function test_redeem_after_donation() public {
        // First deposit to have shares to redeem
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        uint256 initialShares = vault.deposit(100 ether, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 100 ether, PROCESSOR);

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxIncreaseRatio(100e18); // 10000% increase allowed
        vm.stopPrank();

        {
            // Donate assets to the vault through bob to increase totalAssets without minting shares
            uint256 donationAmount = 100 ether;
            address bob = makeAddr("bob");
            deal(vault.asset(), bob, donationAmount);
            vm.startPrank(bob);
            IERC20(vault.asset()).transfer(address(vault), donationAmount);
            vm.stopPrank();

            vault.processAccounting();
        }
        // Now redeem
        uint256 redeemShares = 10 ether;
        vm.startPrank(depositor);
        vault.redeem(redeemShares, depositor, depositor);
        vm.stopPrank();

        assertEq(
            vault.balanceOf(depositor),
            initialShares - redeemShares,
            "Depositor should have 90 shares remaining after redeeming 10"
        );
    }
}
