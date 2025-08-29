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
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);
        // Now withdraw
        vm.startPrank(depositor);
        vault.withdraw(50 ether, depositor, depositor);
        vm.stopPrank();

        assertEq(vault.balanceOf(depositor), 50 ether);
        assertEq(vault.totalAssets(), 50 ether);
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
        // First deposit to have shares to redeem
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 80 ether, PROCESSOR);
        // Now redeem
        vm.startPrank(depositor);
        vault.redeem(50 ether, depositor, depositor);
        vm.stopPrank();

        assertEq(vault.balanceOf(depositor), 50 ether);
        assertEq(vault.totalAssets(), 50 ether);
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
