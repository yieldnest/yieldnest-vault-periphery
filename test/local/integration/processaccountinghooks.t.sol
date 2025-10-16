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
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "lib/yieldnest-vault/src/Common.sol";
import {ShareInflationFeeHooks} from "./mocks/ShareInflationFeeHooks.sol";
// Minimal mock for IHooks

contract ProcessAccountingHooksIntegrationTest is BaseIntegrationTest {
    using Math for uint256;

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

    function test_deposit_and_processAccounting_multiple_times_success() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        for (uint256 i = 0; i < 5; i++) {
            // Deposit as whitelisted user
            deal(vault.asset(), depositor, depositAmount);
            vm.startPrank(depositor);
            IERC20(vault.asset()).approve(address(vault), depositAmount);
            vault.deposit(depositAmount, depositor);
            vm.stopPrank();

            expectedTotalAssetsAndShares += depositAmount;

            // Verify deposit was successful
            assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
            assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

            // Process accounting should succeed (within allowed ratio bounds)
            vm.startPrank(PROCESSOR);
            vault.processAccounting();
            vm.stopPrank();
        }
    }

    function test_deposit_and_processAccounting_with_fees_success() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");
    }

    function test_deposit_and_processAccounting_doubleAsset_increase_success() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        vm.startPrank(owner);
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(1 ether);
        processAccountingGuardHook.setMaxTotalSupplyIncreaseRatio(0.1 ether);
        processAccountingGuardHook.setExpectedPerformanceFee(0.1 ether);
        vm.stopPrank();

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");
    }

    function test_deposit_and_processAccounting_with_100_percent_fees_success() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        vm.startPrank(owner);
        feeHooks.setPerformanceFee(1 ether);
        processAccountingGuardHook.setExpectedPerformanceFee(1 ether);
        vm.stopPrank();

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");
    }

    function convertToShares(uint256 assets, uint256 totalSupply, uint256 totalAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return assets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
    }

    function test_fuzz_deposit_and_processAccounting_with_fees_success(
        uint256 depositAmount,
        uint256 performanceFee,
        uint256 donationAmount
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 1000 ether);
        performanceFee = bound(performanceFee, 0, 1 ether); // from 0 to 100%
        donationAmount = bound(donationAmount, 1, depositAmount / 100); // Bound donation to reasonable range

        // Set the performance fee first
        vm.startPrank(owner);
        feeHooks.setPerformanceFee(performanceFee);
        processAccountingGuardHook.setExpectedPerformanceFee(performanceFee);
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(0.1 ether);
        processAccountingGuardHook.setMaxTotalSupplyIncreaseRatio(0.1 ether);
        vm.stopPrank();
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation

        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGe(totalSupplyAfter, totalSupplyBefore, "Total supply should have increased");

        uint256 feeInBaseAssets = donationAmount.mulDiv(performanceFee, 1e18, Math.Rounding.Floor);
        uint256 feeShares =
            convertToShares(feeInBaseAssets, vault.totalSupply(), vault.totalSupply(), Math.Rounding.Floor);

        assertGe(
            feeShares,
            totalSupplyAfter - totalSupplyBefore,
            "Fee shares should be greater than or equal to total supply increase"
        );
    }

    function test_deposit_and_processAccounting_revert_fee_increase() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // set a performance fee higher than what the processaccountingguardhook expects
        vm.startPrank(owner);
        feeHooks.setPerformanceFee(feeHooks.performanceFee() * 2);
        vm.stopPrank();

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vm.expectRevert();
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
        uint256 maxDecreaseRatio = processAccountingGuardHook.maxTotalAssetsDecreaseRatio();

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
            vm.expectRevert(abi.encodeWithSelector(HooksLib.HookCallFailed.selector, revertData));
        }
        vault.processAccounting();
        vm.stopPrank();
    }

    function setNewFeeHook(ShareInflationFeeHooks shareInflationFeeHook) public {
        // Get the current hooks array from metaHooks
        IHooks[] memory hooksArr = new IHooks[](metaHooks.hooksLength());
        {
            for (uint256 i = 0; i < hooksArr.length; i++) {
                hooksArr[i] = metaHooks.hooks(i);
            }
            // Find the index of the FeeHooks in the array by matching name()
            uint256 feeHooksIndex = type(uint256).max;
            for (uint256 i = 0; i < hooksArr.length; i++) {
                try hooksArr[i].name() returns (string memory hookName) {
                    if (keccak256(bytes(hookName)) == keccak256(bytes("PerformanceFeeHooks"))) {
                        feeHooksIndex = i;
                        break;
                    }
                } catch {}
            }
            require(feeHooksIndex != type(uint256).max, "FeeHooks not found in hooks array");
            // Replace FeeHooks with ShareInflationFeeHooks
            hooksArr[feeHooksIndex] = IHooks(address(shareInflationFeeHook));
        }

        // Set the hooks in MetaHooks to only ShareInflationFeeHooks
        vm.startPrank(HOOK_MANAGER);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();
    }

    function test_deposit_and_processAccounting_with_excessive_mintShares_reverts() public {
        // Use ShareInflationFeeHooks instead of MetaHooks for this test
        // Copy the configuration from MetaHooks and set it for ShareInflationFeeHooks

        // Deploy ShareInflationFeeHooks and set as the only hook in MetaHooks
        // (Assume ShareInflationFeeHooks is imported and available)
        ShareInflationFeeHooks shareInflationFeeHook = new ShareInflationFeeHooks(
            address(metaHooks),
            owner,
            feeHooks.performanceFee(),
            feeHooks.performanceFeeRecipient(),
            feeHooks.getConfig()
        );

        setNewFeeHook(shareInflationFeeHook);

        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        bytes memory revertData = abi.encodeWithSelector(
            HooksLib.HookCallFailed.selector,
            abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalSupplyIncreasedTooMuch.selector,
                100000000000000000000, // totalSupplyBefore
                100019982016185433110 // totalSupplyAfter
            )
        );
        vm.expectRevert(revertData);
        vault.processAccounting();
    }

    function test_processAccounting_with_excessive_mintShares_exceeds_max_increase_ratio_reverts() public {
        ShareInflationFeeHooks shareInflationFeeHook = new ShareInflationFeeHooks(
            address(metaHooks),
            owner,
            feeHooks.performanceFee(),
            feeHooks.performanceFeeRecipient(),
            feeHooks.getConfig()
        );

        uint256 fixedMintAmount = 100000000000000000000;

        shareInflationFeeHook.setFixedMintAmount(fixedMintAmount);

        setNewFeeHook(shareInflationFeeHook);

        uint256 depositAmount = 100 ether;
        uint256 expectedTotalAssetsAndShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalAssetsAndShares += depositAmount;

        // Verify deposit was successful
        assertEq(vault.balanceOf(depositor), expectedTotalAssetsAndShares);
        assertEq(vault.totalAssets(), expectedTotalAssetsAndShares);

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        abi.encodeWithSelector(
            HooksLib.HookCallFailed.selector,
            abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalSupplyIncreasedTooMuch.selector,
                100000000000000000000, // totalSupplyBefore
                200000000000000000000, // totalSupplyAfter
                150000000000000000 // maxShares
            )
        );
        vm.expectRevert();
        vault.processAccounting();
    }
}
