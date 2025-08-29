// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {BaseIntegrationTest} from "test/integration/BaseIntegrationTest.sol";
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

    function test_mint_permissionedVaultHook() public {
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.mint(100 ether, depositor);
        vm.stopPrank();

        assertEq(vault.balanceOf(depositor), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);
    }

    function test_mint_permissionedVaultHook_revert() public {
        address notWhitelisted = address(0xbeefee);
        deal(vault.asset(), notWhitelisted, 100 ether);

        vm.startPrank(notWhitelisted);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        vault.mint(100 ether, notWhitelisted);
        vm.stopPrank();
    }
}
