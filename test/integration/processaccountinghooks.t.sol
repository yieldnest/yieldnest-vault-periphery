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
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";

// Minimal mock for IHooks
contract ProcessAccountingHooksIntegrationTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
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

    function test_deposit_donate_and_processAccounting_revert() public {
        // Deposit as whitelisted user
        deal(vault.asset(), depositor, 100 ether);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 100 ether);
        vault.deposit(100 ether, depositor);
        vm.stopPrank();
        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), 100 ether);
        uint256 totalAssetsBefore = vault.totalAssets();
        assertEq(totalAssetsBefore, 100 ether);

        // Donate a large amount to trigger the increase ratio guard
        // This will cause totalAssets to increase significantly without corresponding shares
        uint256 donationAmount = 10 ether;
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalAssetsAfter = totalAssetsBefore + donationAmount;
        uint256 maxIncreaseRatio = processAccountingGuardHook.maxIncreaseRatio();

        // Process accounting should revert due to exceeding maxIncreaseRatio (0.2%)
        // The donation increased assets by 10% which is way above the 0.2% limit
        vm.startPrank(PROCESSOR);
        bytes memory revertData = abi.encodeWithSelector(
            ProcessAccountingGuardHook.TotalAssetsIncreasedTooMuch.selector,
            totalAssetsBefore,
            totalAssetsAfter,
            maxIncreaseRatio
        );
        vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        vault.processAccounting();
        vm.stopPrank();
    }
}
