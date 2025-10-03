// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {VaultMock} from "test/local/unit/mocks/VaultMock.sol";

contract ProcessAccountingGuardHookTest is Test {
    ProcessAccountingGuardHook public processAccountingGuardHook;

    address vaultMock = address(0x123321);
    address owner = address(0x123322222222);

    address mockAsset = address(0x123323);

    function setUp() public {
        VaultMock vaultMockContract = new VaultMock(mockAsset);
        bytes memory vaultMockBytecode = address(vaultMockContract).code;
        vm.etch(vaultMock, vaultMockBytecode);
        processAccountingGuardHook =
            new ProcessAccountingGuardHook(vaultMock, owner, 0.001 ether, 0.002 ether, 0.0015 ether, 0 ether);
    }

    function testFuzz_afterProcessAccounting_ratioIncrease(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting
    ) public {
        // Bound inputs to reasonable ranges to avoid overflow and ensure meaningful tests
        totalAssetsBeforeAccounting = bound(totalAssetsBeforeAccounting, 1e18, 100_000 ether); // 1 to 1e12 tokens

        // Bound totalAssetsAfterAccounting to ensure increase scenario
        totalAssetsAfterAccounting = bound(totalAssetsAfterAccounting, totalAssetsBeforeAccounting, 200_000 ether);

        uint256 increase = totalAssetsAfterAccounting - totalAssetsBeforeAccounting;
        uint256 increaseRatio =
            (increase * processAccountingGuardHook.RATIO_DENOMINATOR()) / totalAssetsBeforeAccounting;

        vm.startPrank(vaultMock);

        //
        VaultMock(vaultMock).setTotalAssets(totalAssetsAfterAccounting);

        // supply excess is not tested here therefore make it stay constant.
        uint256 totalSupplyAfterAccounting = totalAssetsBeforeAccounting;
        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);

        if (increaseRatio > processAccountingGuardHook.maxTotalAssetsIncreaseRatio()) {
            // Should revert if increase ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalAssetsIncreasedTooMuch.selector,
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    processAccountingGuardHook.maxTotalAssetsIncreaseRatio()
                )
            );
        }

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting: totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting: totalAssetsBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyAfterAccounting,
                totalBaseAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalBaseAssetsAfterAccounting: totalAssetsAfterAccounting
            })
        );
        vm.stopPrank();
    }

    function testFuzz_afterProcessAccounting_ratioDecrease(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting
    ) public {
        // Bound inputs to reasonable ranges to avoid overflow and ensure meaningful tests
        totalAssetsBeforeAccounting = bound(totalAssetsBeforeAccounting, 1e18, 100_000 ether); // 1 to 1e12 tokens

        // Bound totalAssetsAfterAccounting to ensure decrease scenario
        totalAssetsAfterAccounting = bound(totalAssetsAfterAccounting, 0, totalAssetsBeforeAccounting);

        uint256 decrease = totalAssetsBeforeAccounting - totalAssetsAfterAccounting;
        uint256 decreaseRatio =
            (decrease * processAccountingGuardHook.RATIO_DENOMINATOR()) / totalAssetsBeforeAccounting;

        vm.startPrank(vaultMock);

        VaultMock(vaultMock).setTotalAssets(totalAssetsAfterAccounting);

        // supply excess is not tested here therefore make it stay constant.
        uint256 totalSupplyAfterAccounting = totalAssetsBeforeAccounting;
        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);

        if (decreaseRatio > processAccountingGuardHook.maxTotalAssetsDecreaseRatio()) {
            // Should revert if decrease ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalAssetsDecreasedTooMuch.selector,
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    processAccountingGuardHook.maxTotalAssetsDecreaseRatio()
                )
            );
        }

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting: totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting: totalAssetsBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyAfterAccounting,
                totalBaseAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalBaseAssetsAfterAccounting: totalAssetsAfterAccounting
            })
        );
        vm.stopPrank();
    }

    function testFuzz_afterProcessAccounting_supplyDecrease(
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting
    ) public {
        // Bound inputs to reasonable ranges to avoid overflow and ensure meaningful tests
        totalSupplyBeforeAccounting = bound(totalSupplyBeforeAccounting, 1e18, 100_000 ether); // 1 to 100k tokens

        // Bound totalSupplyAfterAccounting to ensure decrease scenario
        totalSupplyAfterAccounting = bound(totalSupplyAfterAccounting, 0, totalSupplyBeforeAccounting - 1);

        VaultMock(vaultMock).setTotalSupply(totalSupplyBeforeAccounting);

        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);

        vm.startPrank(vaultMock);

        // Should revert when supply decreases
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.TotalSupplyDecreased.selector));

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1e18,
                totalAssetsAfterAccounting: 1e18,
                totalSupplyBeforeAccounting: totalSupplyBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyBeforeAccounting, // this parameter is ignored
                totalBaseAssetsBeforeAccounting: 1e18,
                totalBaseAssetsAfterAccounting: 1e18
            })
        );
        vm.stopPrank();
    }

    function testFuzz_afterProcessAccounting_supplyIncrease_totalAssetsDecrease(
        uint256 totalSupplyBeforeAccounting,
        uint256 totalSupplyAfterAccounting
    ) public {
        // Bound inputs to reasonable ranges to avoid overflow and ensure meaningful tests
        totalSupplyBeforeAccounting = bound(totalSupplyBeforeAccounting, 1e18, 100_000 ether); // 1 to 100k tokens

        totalSupplyAfterAccounting = bound(totalSupplyAfterAccounting, totalSupplyBeforeAccounting + 1, 200_000 ether);

        vm.startPrank(owner);
        processAccountingGuardHook.setMaxTotalSupplyIncreaseRatio(100_000_000 ether); // 100 million % so it never reverts for this reason
        vm.stopPrank();

        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);
        vm.startPrank(vaultMock);

        // Should revert when supply increases
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.TotalSupplyIncreasedForLoss.selector));
        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1e18,
                totalAssetsAfterAccounting: 1e18 - 1,
                totalSupplyBeforeAccounting: totalSupplyBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyAfterAccounting,
                totalBaseAssetsBeforeAccounting: 1e18,
                totalBaseAssetsAfterAccounting: 1e18 - 1
            })
        );
        vm.stopPrank();
    }

    function test_afterProcessAccounting_supplyIncrease_totalAssetsIncrease_success() public {
        uint256 totalSupplyBeforeAccounting = 1e18;
        uint256 totalSupplyAfterAccounting = 1.05 ether;

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(1 ether);
        processAccountingGuardHook.setMaxTotalSupplyIncreaseRatio(1 ether);
        processAccountingGuardHook.setExpectedPerformanceFee(0.1 ether);
        vm.stopPrank();

        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);
        vm.startPrank(vaultMock);

        // Should succeed when supply increases and total assets increase
        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1e18,
                totalAssetsAfterAccounting: 2e18,
                totalSupplyBeforeAccounting: totalSupplyBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyAfterAccounting,
                totalBaseAssetsBeforeAccounting: 1e18,
                totalBaseAssetsAfterAccounting: 2e18
            })
        );
        vm.stopPrank();
    }

    function test_setConfig_reverts() public {
        // Test that setConfig reverts with NotSupported error
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: true,
            afterDeposit: true,
            beforeMint: true,
            afterMint: true,
            beforeRedeem: true,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: true,
            beforeProcessAccounting: true,
            afterProcessAccounting: true
        });

        vm.expectRevert(ProcessAccountingGuardHook.NotSupported.selector);
        processAccountingGuardHook.setConfig(config);
    }

    function test_setMaxTotalAssetsDecreaseRatio_success() public {
        uint256 newMaxTotalAssetsDecreaseRatio = 0.2e18; // 20%

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxTotalAssetsDecreaseRatio(newMaxTotalAssetsDecreaseRatio);
        vm.stopPrank();

        assertEq(processAccountingGuardHook.maxTotalAssetsDecreaseRatio(), newMaxTotalAssetsDecreaseRatio);
    }

    function test_setMaxTotalAssetsDecreaseRatio_onlyOwner() public {
        uint256 newMaxTotalAssetsDecreaseRatio = 0.2e18; // 20%

        address wrongCaller = address(0x123323);
        // Test that non-owner cannot call setMaxTotalAssetsDecreaseRatio
        vm.startPrank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.OnlyOwner.selector));
        processAccountingGuardHook.setMaxTotalAssetsDecreaseRatio(newMaxTotalAssetsDecreaseRatio);
        vm.stopPrank();
    }

    function test_setMaxTotalAssetsIncreaseRatio_success() public {
        uint256 newMaxTotalAssetsIncreaseRatio = 0.3e18; // 30%

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(newMaxTotalAssetsIncreaseRatio);
        vm.stopPrank();

        assertEq(processAccountingGuardHook.maxTotalAssetsIncreaseRatio(), newMaxTotalAssetsIncreaseRatio);
    }

    function test_setMaxTotalAssetsIncreaseRatio_onlyOwner() public {
        uint256 newMaxTotalAssetsIncreaseRatio = 0.3e18; // 30%

        address wrongCaller = address(0x123323);

        // Test that non-owner cannot call setMaxTotalAssetsIncreaseRatio
        vm.startPrank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.OnlyOwner.selector));
        processAccountingGuardHook.setMaxTotalAssetsIncreaseRatio(newMaxTotalAssetsIncreaseRatio);
        vm.stopPrank();
    }

    function test_setExpectedPerformanceFee_success() public {
        uint256 newExpectedPerformanceFee = 0.4e18; // 40%

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setExpectedPerformanceFee(newExpectedPerformanceFee);
        vm.stopPrank();
    }

    function test_setExpectedPerformanceFee_onlyOwner() public {
        uint256 newExpectedPerformanceFee = 0.4e18; // 40%

        vm.startPrank(address(0x123323));
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.OnlyOwner.selector));
        processAccountingGuardHook.setExpectedPerformanceFee(newExpectedPerformanceFee);
        vm.stopPrank();
    }

    function test_alwaysComputeTotalAssets_true_reverts() public {
        // Set a fake totalAssets in the vaultMock contract storage
        uint256 fakeTotalAssets = 12345 ether;
        VaultMock(vaultMock).setTotalAssets(fakeTotalAssets);

        // Set alwaysComputeTotalAssets to true
        VaultMock(vaultMock).setAlwaysComputeTotalAssets(true);

        // Try to call afterProcessAccounting and expect revert due to alwaysComputeTotalAssets = true
        IHooks.AfterProcessAccountingParams memory params = IHooks.AfterProcessAccountingParams({
            totalAssetsBeforeAccounting: 1e18,
            totalAssetsAfterAccounting: 2e18,
            totalSupplyBeforeAccounting: 1e18,
            totalSupplyAfterAccounting: 2e18,
            totalBaseAssetsBeforeAccounting: 1e18,
            totalBaseAssetsAfterAccounting: 2e18
        });

        vm.startPrank(vaultMock);
        vm.expectRevert(ProcessAccountingGuardHook.AlwaysComputeTotalAssetsIsEnabled.selector);
        processAccountingGuardHook.afterProcessAccounting(params);
        vm.stopPrank();
    }

    function testFuzz_afterProcessAccounting_ratioIncrease_excessShares_reverts(
        uint256 totalAssetsBeforeAccounting,
        uint256 totalAssetsAfterAccounting,
        uint256 totalSupplyAfterAccounting
    ) public {
        // Bound inputs to reasonable ranges to avoid overflow and ensure meaningful tests
        totalAssetsBeforeAccounting = bound(totalAssetsBeforeAccounting, 1e18, 100_000 ether); // 1 to 1e12 tokens

        // Bound totalAssetsAfterAccounting to ensure increase scenario
        totalAssetsAfterAccounting = bound(totalAssetsAfterAccounting, totalAssetsBeforeAccounting, 200_000 ether);

        uint256 totalSupplyBeforeAccounting = totalAssetsBeforeAccounting;
        // cap the supply increase to 2x the before supply, so that the excess fee error does not trigger.
        totalSupplyAfterAccounting =
            bound(totalSupplyAfterAccounting, totalSupplyBeforeAccounting, totalAssetsAfterAccounting);

        vm.startPrank(processAccountingGuardHook.owner());
        // set fee to 100% max
        processAccountingGuardHook.setExpectedPerformanceFee(1 ether);
        vm.stopPrank();

        uint256 increase = totalAssetsAfterAccounting - totalAssetsBeforeAccounting;
        uint256 increaseRatio =
            (increase * processAccountingGuardHook.RATIO_DENOMINATOR()) / totalAssetsBeforeAccounting;

        vm.startPrank(vaultMock);

        //
        VaultMock(vaultMock).setTotalAssets(totalAssetsAfterAccounting);

        VaultMock(vaultMock).setTotalSupply(totalSupplyAfterAccounting);

        uint256 totalSupplyIncreaseRatio = (totalSupplyAfterAccounting - totalSupplyBeforeAccounting)
            * processAccountingGuardHook.RATIO_DENOMINATOR() / totalSupplyBeforeAccounting;

        if (increaseRatio > processAccountingGuardHook.maxTotalAssetsIncreaseRatio()) {
            // Should revert if increase ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalAssetsIncreasedTooMuch.selector,
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    processAccountingGuardHook.maxTotalAssetsIncreaseRatio()
                )
            );
        } else if (totalSupplyIncreaseRatio >= processAccountingGuardHook.maxTotalSupplyIncreaseRatio()) {
            // Should revert if increase ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalSupplyIncreasedTooMuch.selector,
                    totalSupplyBeforeAccounting,
                    totalSupplyAfterAccounting
                )
            );
        } else if (
            totalAssetsBeforeAccounting == totalAssetsAfterAccounting
                && totalSupplyBeforeAccounting < totalSupplyAfterAccounting
        ) {
            // Should revert if total assets and supply increase but total supply increase is greater than total assets increase
            vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.TotalSupplyIncreasedForLoss.selector));
        }

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting: totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting: totalSupplyBeforeAccounting,
                totalSupplyAfterAccounting: totalSupplyAfterAccounting,
                totalBaseAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalBaseAssetsAfterAccounting: totalAssetsAfterAccounting
            })
        );
        vm.stopPrank();
    }
}
