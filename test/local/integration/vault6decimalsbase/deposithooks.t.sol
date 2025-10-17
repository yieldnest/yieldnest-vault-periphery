// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {BaseIntegrationTest_base_6decimals} from "./BaseIntegrationTest_base_6decimals.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PermissionedVaultHook} from "test/testhooks/PermissionedVaultHook.sol";
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";

// Minimal mock for IHooks
contract DepositHooksIntegrationTest_base_6decimals is BaseIntegrationTest_base_6decimals {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit_permissionedVaultHook(uint256 amount) public {
        amount = bound(amount, 1000 wei, 100_000_000e6);

        deal(vault.asset(), depositor, amount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), amount);
        vault.deposit(amount, depositor);
        vm.stopPrank();

        assertEq(
            vault.balanceOf(depositor),
            amount * 1e12,
            "balanceOf(depositor) does not match deposited amount (adjusted for decimals)"
        );
        assertEq(vault.totalAssets(), amount, "totalAssets does not match deposited amount");
    }

    function test_deposit_permissionedVaultHook_revert(uint256 amount) public {
        amount = bound(amount, 1000 wei, 100_000_000e6);

        address notWhitelisted = address(0xbeefee);
        deal(vault.asset(), notWhitelisted, amount);

        vm.startPrank(notWhitelisted);
        IERC20(vault.asset()).approve(address(vault), amount);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HooksLib.HookCallFailed.selector, revertData));
        vault.deposit(amount, notWhitelisted);
        vm.stopPrank();
    }

    function test_mint_permissionedVaultHook(uint256 shares) public {
        shares = bound(shares, 1000 wei, 100_000e18);

        deal(vault.asset(), depositor, shares / 1e12);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), shares / 1e12);
        vault.mint(shares, depositor);
        vm.stopPrank();

        assertEq(vault.balanceOf(depositor), shares, "balanceOf(depositor) does not match minted shares");
        assertEq(vault.totalAssets(), shares / 1e12, "totalAssets does not match deposited amount when minting shares");
    }

    function test_mint_permissionedVaultHook_revert(uint256 shares) public {
        shares = bound(shares, 1000 wei, 100_000e18);

        address notWhitelisted = address(0xbeefee);
        deal(vault.asset(), notWhitelisted, shares / 1e12);

        vm.startPrank(notWhitelisted);
        IERC20(vault.asset()).approve(address(vault), shares / 1e12);
        bytes memory revertData =
            abi.encodeWithSelector(PermissionedVaultHook.UserNotWhitelisted.selector, notWhitelisted);
        vm.expectRevert(abi.encodeWithSelector(HooksLib.HookCallFailed.selector, revertData));
        vault.mint(shares, notWhitelisted);
        vm.stopPrank();
    }
}
