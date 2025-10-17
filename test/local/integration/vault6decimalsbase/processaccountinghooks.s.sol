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
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "lib/yieldnest-vault/test/unit/mocks/MockProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ShareInflationFeeHooks} from "test/local/integration/mocks/ShareInflationFeeHooks.sol";
import {Math} from "lib/yieldnest-vault/src/Common.sol";

// Minimal mock for IHooks

contract ProcessAccountingHooksIntegrationTest_base_6decimals is BaseIntegrationTest_base_6decimals {
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

    function test_assertSlashableAsset() public view {
        assertEq(slashableAsset.decimals(), 6, "Slashable asset should have 6 decimals");
        assertEq(slashableAsset.totalAssets(), 0, "Slashable asset should have 0 total assets");
        assertEq(slashableAsset.totalSupply(), 0, "Slashable asset should have 0 total supply");
    }

    function test_deposit_and_processAccounting_multiple_times_success() public {
        uint256 depositAmount = 1_000_000 * 1e6; // 1,000,000 units of an asset with 6 decimals (large USDC amount)
        uint256 expectedTotalShares = 0;
        for (uint256 i = 0; i < 5; i++) {
            // Deposit as whitelisted user
            deal(vault.asset(), depositor, depositAmount);
            vm.startPrank(depositor);
            IERC20(vault.asset()).approve(address(vault), depositAmount);
            vault.deposit(depositAmount, depositor);
            vm.stopPrank();

            expectedTotalShares += depositAmount * 1e12;

            // Verify deposit was successful (using shares, not just depositAmount)
            assertEq(
                vault.balanceOf(depositor),
                expectedTotalShares,
                "deposit_and_processAccounting_multiple_times: Depositor share balance mismatch after deposit"
            );

            // Process accounting should succeed (within allowed ratio bounds)
            vm.startPrank(PROCESSOR);
            vault.processAccounting();
            vm.stopPrank();
        }
    }

    function test_deposit_and_processAccounting_with_fees_success() public {
        uint256 depositAmount = 100 * 1e6; // 100 USDC with 6 decimals
        uint256 expectedShares = depositAmount * 1e12; // shares use 18 decimals

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "deposit_and_processAccounting_with_fees: Depositor share balance mismatch"
        );
        assertEq(vault.totalAssets(), depositAmount, "deposit_and_processAccounting_with_fees: totalAssets mismatch");

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 0.1% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(
            totalSupplyAfter,
            totalSupplyBefore,
            "deposit_and_processAccounting_with_fees: Total supply should have increased"
        );
    }

    function test_deposit_and_processAccounting_doubleAsset_increase_success() public {
        uint256 depositAmount = 1_000_000 * 1e6; // 1,000,000 USDC (6 decimals)
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

        // Since the vault uses 18 decimals for shares, but USDC depositAmount is 6 decimals,
        // shares are calculated according to the vault's ERC4626 logic.
        // So the expected shares to receive is depositAmount * 1e12 (from 6 decimals USDC to 18 decimals shares).
        uint256 expectedShares = depositAmount * 1e12;

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "deposit_and_processAccounting_doubleAsset_increase_usdc: Depositor shares mismatch"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "deposit_and_processAccounting_doubleAsset_increase_usdc: totalAssets mismatch"
        );

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount; // match the deposit, 1,000,000 USDC donation
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(
            totalSupplyAfter,
            totalSupplyBefore,
            "deposit_and_processAccounting_doubleAsset_increase_usdc: Total supply should have increased"
        );
    }

    function test_deposit_and_processAccounting_with_100_percent_fees_success() public {
        uint256 depositAmount = 1_000_000 * 1e6; // 1,000,000 USDC (6 decimals)
        // Set 100% performance fee
        vm.startPrank(owner);
        feeHooks.setPerformanceFee(1 ether);
        processAccountingGuardHook.setExpectedPerformanceFee(1 ether);
        vm.stopPrank();

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Shares should be scaled up from 6 decimals USDC to 18 decimals shares: 1_000_000 * 1e12
        uint256 expectedShares = depositAmount * 1e12;

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "deposit_and_processAccounting_with_100_percent_fees_usdc: Depositor shares mismatch"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "deposit_and_processAccounting_with_100_percent_fees_usdc: totalAssets mismatch"
        );

        // Donate to vault to trigger fee calculation (10% donation)
        uint256 donationAmount = depositAmount / 1000;
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGt(
            totalSupplyAfter,
            totalSupplyBefore,
            "deposit_and_processAccounting_with_100_percent_fees_usdc: Total supply should have increased"
        );

        // Check that with 100% fee, all profit goes to fee receiver as new shares
        // All profit shares should go to fee receiver, not depositor
        uint256 profitAssets = donationAmount;
        uint256 expectedFeeShares = profitAssets * 1e12; // Since 100% fee, and shares logic multiplies by 1e12
        uint256 feeReceiverBalance = vault.balanceOf(feeHooks.performanceFeeRecipient());

        // Allow for dust due to rounding
        assertApproxEqAbs(
            feeReceiverBalance, expectedFeeShares, 1e6, "Fee receiver should get all new shares from 100% fee"
        );
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
        // Use 6 decimals for USDC asset
        depositAmount = bound(depositAmount, 1_000_000, 10_000_000e6); // 1 USDC to 1,000 USDC (in 6 decimals)
        performanceFee = bound(performanceFee, 0, 1e18); // from 0 to 100%
        donationAmount = bound(donationAmount, 1, depositAmount / 100); // Bound donation to reasonable range

        // Set the performance fee first
        vm.startPrank(owner);
        feeHooks.setPerformanceFee(performanceFee);
        processAccountingGuardHook.setExpectedPerformanceFee(performanceFee);
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(0.1 ether);
        processAccountingGuardHook.setMaxTotalSupplyIncreaseRatio(0.1 ether);
        vm.stopPrank();
        uint256 expectedTotalShares = 0;

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Shares are always 18 decimals. Deposit is in 6 decimals, so multiply by 1e12 for expected shares.
        expectedTotalShares += depositAmount * 1e12;

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedTotalShares,
            "fuzz_deposit_and_processAccounting_with_fees_usdc: Depositor balance mismatch"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "fuzz_deposit_and_processAccounting_with_fees_usdc: totalAssets mismatch"
        );

        // Donate to vault to trigger fee calculation
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        uint256 totalSupplyBefore = vault.totalSupply();

        // Process accounting should succeed (within allowed ratio bounds)
        vm.startPrank(PROCESSOR);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertGe(
            totalSupplyAfter,
            totalSupplyBefore,
            "fuzz_deposit_and_processAccounting_with_fees_usdc: Total supply should have increased"
        );

        // Fee is in base assets (6 decimals), but shares are 18 decimals. First calculate fee in base assets.
        // Base asset is WUSDC with 18 decimals.FEE_MANAGER_ROLE
        uint256 feeInBaseAssets = (donationAmount * 1e12).mulDiv(performanceFee, 1e18, Math.Rounding.Floor);

        uint256 feeShares =
            convertToShares(feeInBaseAssets, vault.totalSupply(), vault.totalSupply(), Math.Rounding.Floor);

        assertGe(
            feeShares,
            totalSupplyAfter - totalSupplyBefore,
            "fuzz_deposit_and_processAccounting_with_fees: Fee shares should be greater than or equal to total supply increase"
        );
    }

    function test_deposit_and_processAccounting_revert_fee_increase() public {
        // Use a large USDC amount (6 decimals), mirrored after test_deposit_and_processAccounting_multiple_times_success
        uint256 depositAmount = 1_000_000 * 1e6; // 1,000,000 USDC units
        uint256 expectedTotalShares = 0;

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedTotalShares += depositAmount * 1e12; // 6 decimal asset -> 18 decimal shares

        // Verify deposit was successful, using shares
        assertEq(
            vault.balanceOf(depositor),
            expectedTotalShares,
            "revert_fee_increase: Depositor share balance mismatch after deposit"
        );

        // Sanity: check vault's totalAssets (in USDC, 6 decimals)
        assertEq(vault.totalAssets(), depositAmount, "revert_fee_increase: totalAssets mismatch");

        // Set a performance fee higher than what the processAccountingGuardHook expects
        vm.startPrank(owner);
        feeHooks.setPerformanceFee(feeHooks.performanceFee() * 2);
        vm.stopPrank();

        // Donate to vault to trigger fee calculation (large USDC amount)
        uint256 donationAmount = depositAmount / 1000;
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        // Process accounting should revert due to unexpectedly high fee
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
        assertEq(
            vault.balanceOf(depositor),
            depositAmount * 1e12,
            "deposit_donate_and_processAccounting_revert: Depositor balance mismatch after deposit"
        );
        uint256 totalAssetsBefore = vault.totalAssets();
        assertEq(
            totalAssetsBefore,
            depositAmount,
            "deposit_donate_and_processAccounting_revert: totalAssets mismatch after deposit"
        );

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
        // Use 6 decimal asset units for deposit
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6); // 1 USDC to 10,000,000 USDC for 6 decimals
        slashAmount = bound(slashAmount, 1, depositAmount / 2); // Cap slash to half the deposit amount

        // First deposit asset (asset token: 6 decimals) to get slashableAsset
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

        // The deposited asset is a 6 decimals ERC4626, but shares in the vault will use 18 decimals.
        // For correct assertion, vault shares should equal slashableAssetBalance * 1e12 (6 -> 18 decimals).
        uint256 expectedShares = slashableAssetBalance * 1e12;

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "deposit_slash_and_processAccounting_revert: Depositor balance mismatch after asset deposit"
        );
        uint256 totalAssetsBefore = vault.totalAssets();
        assertEq(
            totalAssetsBefore,
            slashableAssetBalance,
            "deposit_slash_and_processAccounting_revert: totalAssets mismatch after asset deposit"
        );

        // Slash assets by transferring them out of the slashableAsset contract
        // This simulates a slashing event where underlying assets are lost
        vm.startPrank(address(slashableAsset));
        IERC20(vault.asset()).transfer(address(0xdead), slashAmount);
        vm.stopPrank();

        uint256 totalAssetsAfter = vault.computeTotalAssets() / 1e12; // convert to 6 decimals
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

        uint256 depositAmount = 10_000_000e6;
        uint256 expectedShares = 0;
        // Deposit as whitelisted user

        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedShares += depositAmount * 1e12;

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "deposit_and_processAccounting_with_excessive_mintShares_reverts: Depositor balance mismatch"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "deposit_and_processAccounting_with_excessive_mintShares_reverts: totalAssets mismatch"
        );

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10% donation to create profit
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        bytes memory revertData = abi.encodeWithSelector(
            HooksLib.HookCallFailed.selector,
            abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalSupplyIncreasedTooMuch.selector,
                10000000000000000000000000, // totalSupplyBefore; 1e7 * 1e18
                10001998201618543311020080 // totalSupplyAfter; excessive mint amount
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

        uint256 fixedMintAmount = 10_000_000 ether; // 10,000,000 shares (18 decimals)

        shareInflationFeeHook.setFixedMintAmount(fixedMintAmount);

        setNewFeeHook(shareInflationFeeHook);

        // USDC amount, 6 decimals
        uint256 depositAmount = 10_000_000e6;
        uint256 expectedShares = 0;

        // Deposit as whitelisted user
        deal(vault.asset(), depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, depositor);
        vm.stopPrank();

        expectedShares += depositAmount * 1e12; // Convert asset (6dec) to shares (18dec)

        // Verify deposit was successful
        assertEq(
            vault.balanceOf(depositor),
            expectedShares,
            "processAccounting_with_excessive_mintShares_usdc: Depositor balance mismatch"
        );
        assertEq(
            vault.totalAssets(), depositAmount, "processAccounting_with_excessive_mintShares_usdc: totalAssets mismatch"
        );

        // Donate to vault to trigger fee calculation
        uint256 donationAmount = depositAmount / 1000; // 10_000 USDC
        deal(vault.asset(), address(this), donationAmount);
        IERC20(vault.asset()).transfer(address(vault), donationAmount);

        // The revert expects totalSupply to increase by too much.
        // Let's ensure max allowed increase is less than what will happen. Example: 15% (using 0.15e18)
        // Starting totalSupply: 10_000_000e18
        // Minting additional 10_000_000e12 shares (enormous; should easily revert)
        bytes memory revertData = abi.encodeWithSelector(
            HooksLib.HookCallFailed.selector,
            abi.encodeWithSelector(
                ProcessAccountingGuardHook.TotalSupplyIncreasedTooMuch.selector,
                10_000_000e18, // totalSupplyBefore (shares, 18 dec)
                20_000_000e18 // totalSupplyAfter (shares, 18 dec)
            )
        );
        vm.expectRevert(revertData);
        vault.processAccounting();
    }
}
