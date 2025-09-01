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

    function test_mintShares_wrong_caller() public {
        // Set up a hook
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
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        // Should revert if not called by a hook
        address badCaller = address(0xBEEF);
        vm.startPrank(badCaller);
        vm.expectRevert(abi.encodeWithSelector(MetaHooks.CallerNotHook.selector, badCaller));
        metaHooks.mintShares(address(0x1234), 10);
        vm.stopPrank();
    }

    function test_mintShares_success() public {
        // Set up a hook
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
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        address recipient = address(0x5678);
        uint256 shares = 100;

        // Call mintShares as hook
        vm.startPrank(address(hook));
        metaHooks.mintShares(recipient, shares);
        vm.stopPrank();

        // Verify vault was called with correct parameters
        assertEq(vault.mintedShares(recipient), shares, "vault should receive correct shares amount for recipient");
    }
}
