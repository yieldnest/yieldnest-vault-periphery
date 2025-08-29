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
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
// Minimal mock for IHooks

contract ProcessAccountingHooksIntegrationTest is BaseIntegrationTest {
    MockERC4626 public slashableAsset;

    function setUp() public override {
        super.setUp();

        // Create a slashable asset (MockERC4626)
        slashableAsset = new MockERC4626(ERC20(vault.asset()), "Slashable Asset", "SLASH");

        // Add the slashable asset to the vault
        vm.startPrank(ADMIN);
        vault.addAsset(address(slashableAsset), true);
        vm.stopPrank();

        // Add the slashable asset to the rate provider
        vm.startPrank(PROVIDER_MANAGER);
        MockProvider(address(vault.provider())).addERC4626(address(slashableAsset));
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

    function test_deposit_donate_and_processAccounting_revert(uint256 depositAmount, uint256 donationAmount) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        donationAmount = bound(donationAmount, 1, depositAmount * 10); // Cap donation to 10x the deposit amount

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();
        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), depositAmount);
        uint256 totalAssetsBefore = vault.totalAssets();
        assertEq(totalAssetsBefore, depositAmount);

        // Donate a large amount to trigger the increase ratio guard
        // This will cause totalAssets to increase significantly without corresponding shares
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalAssetsAfter = totalAssetsBefore + donationAmount;
        uint256 maxIncreaseRatio = processAccountingGuardHook.maxIncreaseRatio();

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
            vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        }
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_deposit_slash_and_processAccounting_revert(uint256 depositAmount, uint256 slashAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        slashAmount = bound(slashAmount, 1, depositAmount / 2); // Cap slash to the deposit amount

        // First deposit asset() to get slashableAsset
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(slashableAsset), depositAmount);
        IERC4626(slashableAsset).deposit(depositAmount, depositor);
        vm.stopPrank();

        // Now deposit the slashableAsset into the vault
        uint256 slashableAssetBalance = IERC20(slashableAsset).balanceOf(depositor);
        vm.startPrank(depositor);
        IERC20(slashableAsset).approve(address(vault), slashableAssetBalance);
        vault.depositAsset(address(slashableAsset), slashableAssetBalance, depositor);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), slashableAssetBalance);
        uint256 totalAssetsBefore = vault.totalAssets();
        assertEq(totalAssetsBefore, slashableAssetBalance);

        // Slash assets by transferring them out of the slashableAsset contract
        // This simulates a slashing event where underlying assets are lost
        vm.startPrank(address(slashableAsset));
        IERC20(vault.asset()).transfer(address(0xdead), slashAmount);
        vm.stopPrank();

        uint256 totalAssetsAfter = vault.computeTotalAssets();
        uint256 maxDecreaseRatio = processAccountingGuardHook.maxDecreaseRatio();

        // Process accounting should revert due to exceeding maxDecreaseRatio
        // The slashing decreased assets significantly which should be above the maxDecreaseRatio limit
        vm.startPrank(PROCESSOR);
        // Calculate the actual decrease ratio
        uint256 actualDecreaseRatio = ((totalAssetsBefore - totalAssetsAfter) * 1e18) / totalAssetsBefore;

        // Only expect revert if the decrease ratio exceeds the maximum allowed
        if (actualDecreaseRatio > maxDecreaseRatio) {
            bytes memory revertData = abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalAssetsDecreasedTooMuch.selector,
                totalAssetsBefore,
                totalAssetsAfter,
                maxDecreaseRatio
            );
            vm.expectRevert(abi.encodeWithSelector(HookCallFailed.selector, revertData));
        }
        vault.processAccounting();
        vm.stopPrank();
    }
}
