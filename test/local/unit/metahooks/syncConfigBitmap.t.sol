// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {HooksMock} from "./HooksMock.sol";
import {VaultMock} from "../mocks/VaultMock.sol";

contract SyncConfigBitmapMetaHooksTest is Test {
    MetaHooks metaHooks;
    VaultMock vault;
    address admin = address(0xA1);
    address hookManager = address(0xB1);

    function setUp() public {
        vault = new VaultMock(address(0xDEAD));
        metaHooks = new MetaHooks(address(vault), admin, hookManager);
    }

    struct HookConfigSet {
        bool[5] beforeDeposits;
        bool[5] afterDeposits;
        bool[5] beforeMints;
        bool[5] afterMints;
        bool[5] beforeRedeems;
        bool[5] afterRedeems;
        bool[5] beforeWithdraws;
        bool[5] afterWithdraws;
        bool[5] beforeProcessAccountings;
        bool[5] afterProcessAccountings;
    }

    function test_syncConfigBitmap_success(HookConfigSet memory initialConfig, HookConfigSet memory updatedConfig)
        public
    {
        vm.startPrank(hookManager);
        uint256 numHooks = 5;

        // Create arrays of 5 hooks with fuzzed configurations
        HooksMock[] memory hooks = new HooksMock[](numHooks);

        // Initialize hooks with initialConfig
        for (uint256 i = 0; i < numHooks; i++) {
            hooks[i] = new HooksMock(
                IHooks.Config({
                    beforeDeposit: initialConfig.beforeDeposits[i],
                    afterDeposit: initialConfig.afterDeposits[i],
                    beforeMint: initialConfig.beforeMints[i],
                    afterMint: initialConfig.afterMints[i],
                    beforeRedeem: initialConfig.beforeRedeems[i],
                    afterRedeem: initialConfig.afterRedeems[i],
                    beforeWithdraw: initialConfig.beforeWithdraws[i],
                    afterWithdraw: initialConfig.afterWithdraws[i],
                    beforeProcessAccounting: initialConfig.beforeProcessAccountings[i],
                    afterProcessAccounting: initialConfig.afterProcessAccountings[i]
                })
            );
        }

        IHooks[] memory hooksArr = new IHooks[](numHooks);
        for (uint256 i = 0; i < numHooks; i++) {
            hooksArr[i] = IHooks(address(hooks[i]));
        }

        metaHooks.setHooks(hooksArr);

        // Call setConfig on each hook with the updatedConfig
        for (uint256 i = 0; i < numHooks; i++) {
            hooks[i].setConfig(
                IHooks.Config({
                    beforeDeposit: updatedConfig.beforeDeposits[i],
                    afterDeposit: updatedConfig.afterDeposits[i],
                    beforeMint: updatedConfig.beforeMints[i],
                    afterMint: updatedConfig.afterMints[i],
                    beforeRedeem: updatedConfig.beforeRedeems[i],
                    afterRedeem: updatedConfig.afterRedeems[i],
                    beforeWithdraw: updatedConfig.beforeWithdraws[i],
                    afterWithdraw: updatedConfig.afterWithdraws[i],
                    beforeProcessAccounting: updatedConfig.beforeProcessAccountings[i],
                    afterProcessAccounting: updatedConfig.afterProcessAccountings[i]
                })
            );
        }

        metaHooks.syncConfigBitmap();

        // Config should be the OR of all hooks
        IHooks.Config memory config = metaHooks.getConfig();

        assertHookToggle(config.beforeDeposit, updatedConfig.beforeDeposits);
        assertHookToggle(config.afterDeposit, updatedConfig.afterDeposits);
        assertHookToggle(config.beforeMint, updatedConfig.beforeMints);
        assertHookToggle(config.afterMint, updatedConfig.afterMints);
        assertHookToggle(config.beforeRedeem, updatedConfig.beforeRedeems);
        assertHookToggle(config.afterRedeem, updatedConfig.afterRedeems);
        assertHookToggle(config.beforeWithdraw, updatedConfig.beforeWithdraws);
        assertHookToggle(config.afterWithdraw, updatedConfig.afterWithdraws);
        assertHookToggle(config.beforeProcessAccounting, updatedConfig.beforeProcessAccountings);
        assertHookToggle(config.afterProcessAccounting, updatedConfig.afterProcessAccountings);

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

    function test_syncConfigBitmap_revertsForNonOwner() public {
        address nonOwner = address(0xBEEF);

        vm.startPrank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonOwner, metaHooks.HOOK_MANAGER_ROLE()
            )
        );
        metaHooks.syncConfigBitmap();
        vm.stopPrank();
    }
}
