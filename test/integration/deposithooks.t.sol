// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "../../src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "../../src/interface/IVaultForHooks.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PermissionedVaultHook} from "test/testhooks/PermissionedVaultHook.sol";
import {HooksLib, HookCallFailed} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";

// Minimal mock for IHooks
contract DepositHooksIntegrationTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit_permissionedVaultHook() public {
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);
        vm.stopPrank();

        assertEq(vault.balanceOf(depositor), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);
    }

    function test_deposit_permissionedVaultHook_revert() public {
        address notWhitelisted = address(0xbeefee);
        deal(vault.asset(), notWhitelisted, 100 ether);

        vm.startPrank(notWhitelisted);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        vault.deposit(100 ether, notWhitelisted);
        vm.stopPrank();
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

    function test_deposit_and_processAccounting_success() public {
        // Deposit as whitelisted user
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();
    }
}
