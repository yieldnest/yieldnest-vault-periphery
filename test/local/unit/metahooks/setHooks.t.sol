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

    function testSetHooksAndConfig() public {
        vm.startPrank(hookManager);

        // Set up two hooks with different configs
        IHooks.Config memory config1 = IHooks.Config({
            beforeDeposit: true,
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
        IHooks.Config memory config2 = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: true,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: false
        });

        HooksMock hook1 = new HooksMock(config1);
        HooksMock hook2 = new HooksMock(config2);

        IHooks[] memory hooksArr = new IHooks[](2);
        hooksArr[0] = IHooks(address(hook1));
        hooksArr[1] = IHooks(address(hook2));

        metaHooks.setHooks(hooksArr);

        // Config should be the OR of all hooks
        IHooks.Config memory config = metaHooks.getConfig();
        assertTrue(config.beforeDeposit, "beforeDeposit should be true");
        assertTrue(config.afterDeposit, "afterDeposit should be true");
        assertFalse(config.beforeMint, "beforeMint should be false");

        // Should revert on duplicate hooks
        IHooks[] memory dupArr = new IHooks[](2);
        dupArr[0] = IHooks(address(hook1));
        dupArr[1] = IHooks(address(hook1));
        vm.expectRevert(abi.encodeWithSelector(MetaHooks.DuplicateInInput.selector, address(hook1)));
        metaHooks.setHooks(dupArr);

        vm.stopPrank();
    }
}