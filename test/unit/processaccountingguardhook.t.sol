// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ProcessAccountingGuardHook} from "../../src/hooks/ProcessAccountingGuardHook.sol";

contract ProcessAccountingGuardHookTest is Test {
    ProcessAccountingGuardHook public processAccountingGuardHook;

    address vaultMock = address(0x123321);
    address owner = address(0x123322222222);

    function setUp() public {
        processAccountingGuardHook = new ProcessAccountingGuardHook(vaultMock, owner, 0.001 ether, 0.002 ether);
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
            totalAssetsBeforeAccounting,
            totalAssetsAfterAccounting,
            0, // unused parameter
            0, // unused parameter
            0, // unused parameter
            0 // unused parameter
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
            totalAssetsBeforeAccounting,
            totalAssetsAfterAccounting,
            0, // unused parameter
            0, // unused parameter
            0, // unused parameter
            0 // unused parameter
        );
        vm.stopPrank();
    }
}
