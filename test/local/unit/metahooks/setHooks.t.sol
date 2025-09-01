// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {HooksMock} from "./HooksMock.sol";
import {VaultMock} from "../mocks/VaultMock.sol";

contract MetaHooksTest is Test {
    MetaHooks metaHooks;
    VaultMock vault;
    address admin = address(0xA1);
    address hookManager = address(0xB1);

    function setUp() public {
        vault = new VaultMock(address(0xDEAD));
        metaHooks = new MetaHooks(address(vault), admin, hookManager);
    }

    function test_setHooks_success(
        bool[5] memory beforeDeposits,
        bool[5] memory afterDeposits,
        bool[5] memory beforeMints,
        bool[5] memory afterMints,
        bool[5] memory beforeRedeems,
        bool[5] memory afterRedeems,
        bool[5] memory beforeWithdraws,
        bool[5] memory afterWithdraws,
        bool[5] memory beforeProcessAccountings,
        bool[5] memory afterProcessAccountings
    ) public {
        vm.startPrank(hookManager);
        uint256 numHooks = 5;

        // Create arrays of 5 hooks with fuzzed configurations
        HooksMock[] memory hooks = new HooksMock[](numHooks);

        // Initialize hooks with fuzzed configurations
        for (uint256 i = 0; i < numHooks; i++) {
            hooks[i] = new HooksMock(
                IHooks.Config({
                    beforeDeposit: beforeDeposits[i],
                    afterDeposit: afterDeposits[i],
                    beforeMint: beforeMints[i],
                    afterMint: afterMints[i],
                    beforeRedeem: beforeRedeems[i],
                    afterRedeem: afterRedeems[i],
                    beforeWithdraw: beforeWithdraws[i],
                    afterWithdraw: afterWithdraws[i],
                    beforeProcessAccounting: beforeProcessAccountings[i],
                    afterProcessAccounting: afterProcessAccountings[i]
                })
            );
        }

        IHooks[] memory hooksArr = new IHooks[](numHooks);
        for (uint256 i = 0; i < numHooks; i++) {
            hooksArr[i] = IHooks(address(hooks[i]));
        }

        metaHooks.setHooks(hooksArr);

        // Config should be the OR of all hooks
        IHooks.Config memory config = metaHooks.getConfig();

        assertHookToggle(config.beforeDeposit, beforeDeposits);
        assertHookToggle(config.afterDeposit, afterDeposits);
        assertHookToggle(config.beforeMint, beforeMints);
        assertHookToggle(config.afterMint, afterMints);
        assertHookToggle(config.beforeRedeem, beforeRedeems);
        assertHookToggle(config.afterRedeem, afterRedeems);
        assertHookToggle(config.beforeWithdraw, beforeWithdraws);
        assertHookToggle(config.afterWithdraw, afterWithdraws);
        assertHookToggle(config.beforeProcessAccounting, beforeProcessAccountings);
        assertHookToggle(config.afterProcessAccounting, afterProcessAccountings);

        // Should revert on duplicate hooks
        IHooks[] memory dupArr = new IHooks[](2);
        dupArr[0] = IHooks(address(hooks[0]));
        dupArr[1] = IHooks(address(hooks[0]));
        vm.expectRevert(abi.encodeWithSelector(MetaHooks.DuplicateInInput.selector, address(hooks[0])));
        metaHooks.setHooks(dupArr);

        vm.stopPrank();
    }

    function assertHookToggle(bool configValue, bool[5] memory hookIsActive) internal pure {
        bool expected = false;
        for (uint256 i = 0; i < 5; i++) {
            expected = expected || hookIsActive[i];
        }
        assertEq(configValue, expected, "configValue should match OR of all hooks");
    }

    function test_setHooks_duplicates() public {
        // Create two hooks
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });
        HooksMock hook1 = new HooksMock(config);
        HooksMock hook2 = new HooksMock(config);

        vm.startPrank(hookManager);

        // Test duplicate hooks in array should revert
        IHooks[] memory dupArr = new IHooks[](3);
        dupArr[0] = IHooks(address(hook1));
        dupArr[1] = IHooks(address(hook2));
        dupArr[2] = IHooks(address(hook1)); // Duplicate

        vm.expectRevert(abi.encodeWithSelector(MetaHooks.DuplicateInInput.selector, address(hook1)));
        metaHooks.setHooks(dupArr);

        vm.stopPrank();
    }

    function test_setHooks_empty() public {
        vm.startPrank(hookManager);

        // Test empty hooks array should revert
        IHooks[] memory emptyArr = new IHooks[](0);
        vm.expectRevert(abi.encodeWithSelector(MetaHooks.EmptyHooksArray.selector));
        metaHooks.setHooks(emptyArr);

        vm.stopPrank();
    }

    function test_setHooks_tooMany() public {
        vm.startPrank(hookManager);

        // Test too many hooks (more than 16) should revert
        IHooks[] memory tooManyArr = new IHooks[](17);

        // Create 17 hooks
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });

        for (uint256 i = 0; i < 17; i++) {
            HooksMock hook = new HooksMock(config);
            tooManyArr[i] = IHooks(address(hook));
        }

        vm.expectRevert(abi.encodeWithSelector(MetaHooks.TooManyHooks.selector));
        metaHooks.setHooks(tooManyArr);

        vm.stopPrank();
    }

    function test_setHooks_notAllowed() public {
        // Test that non-hook manager cannot call setHooks
        address unauthorizedUser = address(0xC1);
        vm.startPrank(unauthorizedUser);

        IHooks[] memory hooksArr = new IHooks[](1);
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });
        HooksMock hook = new HooksMock(config);
        hooksArr[0] = IHooks(address(hook));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                metaHooks.HOOK_MANAGER_ROLE()
            )
        );
        metaHooks.setHooks(hooksArr);

        vm.stopPrank();
    }

    function test_setHooks_clearsPreExistingData() public {
        vm.startPrank(hookManager);

        // First, set up initial hooks with all configurations set to true
        uint256 initialNumHooks = 3;
        IHooks[] memory initialHooks = new IHooks[](initialNumHooks);

        for (uint256 i = 0; i < initialNumHooks; i++) {
            HooksMock hook = new HooksMock(
                IHooks.Config({
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
                })
            );
            initialHooks[i] = IHooks(address(hook));
        }

        // Set the initial hooks
        metaHooks.setHooks(initialHooks);

        // Verify initial state - all config flags should be true
        IHooks.Config memory initialConfig = metaHooks.getConfig();
        assertTrue(initialConfig.beforeDeposit);
        assertTrue(initialConfig.afterDeposit);
        assertTrue(initialConfig.beforeMint);
        assertTrue(initialConfig.afterMint);
        assertTrue(initialConfig.beforeRedeem);
        assertTrue(initialConfig.afterRedeem);
        assertTrue(initialConfig.beforeWithdraw);
        assertTrue(initialConfig.afterWithdraw);
        assertTrue(initialConfig.beforeProcessAccounting);
        assertTrue(initialConfig.afterProcessAccounting);

        // Verify hooks array length
        assertEq(metaHooks.hooksLength(), initialNumHooks);

        // Now set new hooks with different configuration (all false)
        uint256 newNumHooks = 2;
        IHooks[] memory newHooks = new IHooks[](newNumHooks);

        for (uint256 i = 0; i < newNumHooks; i++) {
            HooksMock hook = new HooksMock(
                IHooks.Config({
                    beforeDeposit: false,
                    afterDeposit: false,
                    beforeMint: false,
                    afterMint: false,
                    beforeRedeem: false,
                    afterRedeem: false,
                    beforeWithdraw: false,
                    afterWithdraw: false,
                    beforeProcessAccounting: false,
                    afterProcessAccounting: false
                })
            );
            newHooks[i] = IHooks(address(hook));
        }

        // Set the new hooks - this should clear all pre-existing data
        metaHooks.setHooks(newHooks);

        // Verify that all previous configuration is cleared
        IHooks.Config memory newConfig = metaHooks.getConfig();
        assertFalse(newConfig.beforeDeposit);
        assertFalse(newConfig.afterDeposit);
        assertFalse(newConfig.beforeMint);
        assertFalse(newConfig.afterMint);
        assertFalse(newConfig.beforeRedeem);
        assertFalse(newConfig.afterRedeem);
        assertFalse(newConfig.beforeWithdraw);
        assertFalse(newConfig.afterWithdraw);
        assertFalse(newConfig.beforeProcessAccounting);
        assertFalse(newConfig.afterProcessAccounting);

        // Verify hooks array is updated with new length
        assertEq(metaHooks.hooksLength(), newNumHooks);

        // Verify the new hooks are correctly set
        for (uint256 i = 0; i < newNumHooks; i++) {
            assertEq(address(metaHooks.hooks(i)), address(newHooks[i]));
        }

        vm.stopPrank();
    }

    function test_setConfig_reverts() public {
        vm.startPrank(hookManager);

        // setConfig should revert with NotSupported error
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

        vm.expectRevert(MetaHooks.NotSupported.selector);
        metaHooks.setConfig(config);

        vm.stopPrank();
    }

    function test_supportsHook_fuzz(uint8 hookIndex, uint16 bitmap) public view {
        // Bound hookIndex to valid range (0-15 since we support max 16 hooks)
        hookIndex = uint8(bound(hookIndex, 0, 15));

        // Test supportsHook function with alternative implementation
        bool expectedResult = (bitmap & (2 ** hookIndex)) != 0;
        bool actualResult = metaHooks.supportsHook(hookIndex, bitmap);

        assertEq(actualResult, expectedResult, "supportsHook should return correct result based on bitmap");
    }

    function test_setHook_fuzz(uint8 hookIndex, uint16 bitmap) public view {
        // Bound hookIndex to valid range (0-15 since we support max 16 hooks)
        hookIndex = uint8(bound(hookIndex, 0, 15));

        uint16 expectedResult = uint16(2 ** hookIndex | bitmap);

        uint256 updatedBitmap = metaHooks.setHook(hookIndex, bitmap);
        assertEq(updatedBitmap, expectedResult, "setHook should return correct result based on bitmap");
    }
}
