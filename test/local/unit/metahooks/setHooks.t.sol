// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
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

    function assertHookToggle(bool configValue, bool[5] memory hookIsActive) internal {
        bool expected = false;
        for (uint256 i = 0; i < 5; i++) {
            expected = expected || hookIsActive[i];
        }
        assertEq(configValue, expected, "configValue should match OR of all hooks");
    }
}
