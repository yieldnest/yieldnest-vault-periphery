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
        processAccountingGuardHook = new ProcessAccountingGuardHook(vaultMock, owner, 0.001 ether, 0.002 ether, 0);
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

        if (increaseRatio > processAccountingGuardHook.maxIncreaseRatio()) {
            // Should revert if increase ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalAssetsIncreasedTooMuch.selector,
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    processAccountingGuardHook.maxIncreaseRatio()
                )
            );
        }

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting: totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting: 0,
                totalSupplyAfterAccounting: 0,
                totalBaseAssetsBeforeAccounting: 0,
                totalBaseAssetsAfterAccounting: 0
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

        if (decreaseRatio > processAccountingGuardHook.maxDecreaseRatio()) {
            // Should revert if decrease ratio exceeds maximum
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProcessAccountingGuardHook.TotalAssetsDecreasedTooMuch.selector,
                    totalAssetsBeforeAccounting,
                    totalAssetsAfterAccounting,
                    processAccountingGuardHook.maxDecreaseRatio()
                )
            );
        }

        processAccountingGuardHook.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: totalAssetsBeforeAccounting,
                totalAssetsAfterAccounting: totalAssetsAfterAccounting,
                totalSupplyBeforeAccounting: 0,
                totalSupplyAfterAccounting: 0,
                totalBaseAssetsBeforeAccounting: 0,
                totalBaseAssetsAfterAccounting: 0
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

    function test_setMaxDecreaseRatio_success() public {
        uint256 newMaxDecreaseRatio = 0.2e18; // 20%

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxDecreaseRatio(newMaxDecreaseRatio);
        vm.stopPrank();

        assertEq(processAccountingGuardHook.maxDecreaseRatio(), newMaxDecreaseRatio);
    }

    function test_setMaxDecreaseRatio_onlyOwner() public {
        uint256 newMaxDecreaseRatio = 0.2e18; // 20%

        address wrongCaller = address(0x123323);
        // Test that non-owner cannot call setMaxDecreaseRatio
        vm.startPrank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.OnlyOwner.selector));
        processAccountingGuardHook.setMaxDecreaseRatio(newMaxDecreaseRatio);
        vm.stopPrank();
    }

    function test_setMaxIncreaseRatio_success() public {
        uint256 newMaxIncreaseRatio = 0.3e18; // 30%

        vm.startPrank(processAccountingGuardHook.owner());
        processAccountingGuardHook.setMaxIncreaseRatio(newMaxIncreaseRatio);
        vm.stopPrank();

        assertEq(processAccountingGuardHook.maxIncreaseRatio(), newMaxIncreaseRatio);
    }

    function test_setMaxIncreaseRatio_onlyOwner() public {
        uint256 newMaxIncreaseRatio = 0.3e18; // 30%

        address wrongCaller = address(0x123323);

        // Test that non-owner cannot call setMaxIncreaseRatio
        vm.startPrank(wrongCaller);
        vm.expectRevert(abi.encodeWithSelector(ProcessAccountingGuardHook.OnlyOwner.selector));
        processAccountingGuardHook.setMaxIncreaseRatio(newMaxIncreaseRatio);
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
}
