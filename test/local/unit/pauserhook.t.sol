// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {PauserHook} from "src/hooks/PauserHook.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";

contract PauserHookTest is Test {
    PauserHook internal hook;

    address internal vault = address(0xA11CE);
    address internal admin = address(0xA1);
    address internal pauser = address(0xB1);
    address internal unpauser = address(0xC1);
    address internal other = address(0xD1);

    function setUp() public {
        hook = new PauserHook(vault, admin, pauser, unpauser);
    }

    function testGetConfigEnablesEveryHookCall() public view {
        IHooks.Config memory config = hook.getConfig();

        assertTrue(config.beforeDeposit);
        assertTrue(config.afterDeposit);
        assertTrue(config.beforeMint);
        assertTrue(config.afterMint);
        assertTrue(config.beforeRedeem);
        assertTrue(config.afterRedeem);
        assertTrue(config.beforeWithdraw);
        assertTrue(config.afterWithdraw);
        assertTrue(config.beforeProcessAccounting);
        assertTrue(config.afterProcessAccounting);
    }

    function testPauseAndUnpause() public {
        vm.prank(pauser);
        hook.pause(PauserHook.HookCall.Deposit);

        assertTrue(hook.paused(PauserHook.HookCall.Deposit));

        vm.prank(unpauser);
        hook.unpause(PauserHook.HookCall.Deposit);

        assertFalse(hook.paused(PauserHook.HookCall.Deposit));
    }

    function testPauseRequiresPauserRole() public {
        vm.prank(other);
        vm.expectRevert();
        hook.pause(PauserHook.HookCall.Deposit);
    }

    function testUnpauseRequiresUnpauserRole() public {
        vm.prank(pauser);
        hook.pause(PauserHook.HookCall.Deposit);

        vm.prank(other);
        vm.expectRevert();
        hook.unpause(PauserHook.HookCall.Deposit);
    }

    function testBeforeAndAfterDepositRevertWhenDepositPaused() public {
        _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall.Deposit);
    }

    function testBeforeAndAfterMintRevertWhenMintPaused() public {
        _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall.Mint);
    }

    function testBeforeAndAfterRedeemRevertWhenRedeemPaused() public {
        _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall.Redeem);
    }

    function testBeforeAndAfterWithdrawRevertWhenWithdrawPaused() public {
        _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall.Withdraw);
    }

    function testBeforeAndAfterProcessAccountingRevertWhenProcessAccountingPaused() public {
        _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall.ProcessAccounting);
    }

    function testBeforeAndAfterDepositSkipWhenDifferentHookCallPaused() public {
        vm.prank(pauser);
        hook.pause(PauserHook.HookCall.Withdraw);

        vm.startPrank(vault);
        hook.beforeDeposit(_depositParams());
        hook.afterDeposit(_depositParams());
        vm.stopPrank();
    }

    function testOnlyVaultCanCallHooks() public {
        vm.expectRevert(PauserHook.OnlyVault.selector);
        hook.beforeDeposit(_depositParams());
    }

    function testNoOpPauseAndUnpauseRevert() public {
        vm.startPrank(pauser);
        hook.pause(PauserHook.HookCall.Deposit);
        vm.expectRevert(PauserHook.NoOp.selector);
        hook.pause(PauserHook.HookCall.Deposit);
        vm.stopPrank();

        vm.startPrank(unpauser);
        hook.unpause(PauserHook.HookCall.Deposit);
        vm.expectRevert(PauserHook.NoOp.selector);
        hook.unpause(PauserHook.HookCall.Deposit);
        vm.stopPrank();
    }

    function testSetConfigReverts() public {
        IHooks.Config memory config = hook.getConfig();

        vm.expectRevert(PauserHook.NotSupported.selector);
        hook.setConfig(config);
    }

    function _depositParams() internal pure returns (IHooks.DepositParams memory) {
        return IHooks.DepositParams({
            asset: address(0), assets: 0, caller: address(0), receiver: address(0), shares: 0, baseAssets: 0
        });
    }

    function _assertBeforeAndAfterRevertWhenPaused(PauserHook.HookCall hookCall) internal {
        vm.prank(pauser);
        hook.pause(hookCall);

        vm.startPrank(vault);
        _expectBeforeRevert(hookCall);
        _expectAfterRevert(hookCall);
        vm.stopPrank();
    }

    function _expectBeforeRevert(PauserHook.HookCall hookCall) internal {
        vm.expectRevert(abi.encodeWithSelector(PauserHook.Paused.selector, hookCall));

        if (hookCall == PauserHook.HookCall.Deposit) hook.beforeDeposit(_depositParams());
        else if (hookCall == PauserHook.HookCall.Mint) hook.beforeMint(_mintParams());
        else if (hookCall == PauserHook.HookCall.Redeem) hook.beforeRedeem(_redeemParams());
        else if (hookCall == PauserHook.HookCall.Withdraw) hook.beforeWithdraw(_withdrawParams());
        else hook.beforeProcessAccounting(_beforeProcessAccountingParams());
    }

    function _expectAfterRevert(PauserHook.HookCall hookCall) internal {
        vm.expectRevert(abi.encodeWithSelector(PauserHook.Paused.selector, hookCall));

        if (hookCall == PauserHook.HookCall.Deposit) hook.afterDeposit(_depositParams());
        else if (hookCall == PauserHook.HookCall.Mint) hook.afterMint(_mintParams());
        else if (hookCall == PauserHook.HookCall.Redeem) hook.afterRedeem(_redeemParams());
        else if (hookCall == PauserHook.HookCall.Withdraw) hook.afterWithdraw(_withdrawParams());
        else hook.afterProcessAccounting(_afterProcessAccountingParams());
    }

    function _mintParams() internal pure returns (IHooks.MintParams memory) {
        return IHooks.MintParams({
            asset: address(0), shares: 0, caller: address(0), receiver: address(0), assets: 0, baseAssets: 0
        });
    }

    function _redeemParams() internal pure returns (IHooks.RedeemParams memory) {
        return IHooks.RedeemParams({
            asset: address(0), shares: 0, caller: address(0), receiver: address(0), owner: address(0), assets: 0
        });
    }

    function _withdrawParams() internal pure returns (IHooks.WithdrawParams memory) {
        return IHooks.WithdrawParams({
            asset: address(0), assets: 0, caller: address(0), receiver: address(0), owner: address(0), shares: 0
        });
    }

    function _beforeProcessAccountingParams() internal pure returns (IHooks.BeforeProcessAccountingParams memory) {
        return IHooks.BeforeProcessAccountingParams({
            totalAssetsBeforeAccounting: 0, totalSupplyBeforeAccounting: 0, totalBaseAssetsBeforeAccounting: 0
        });
    }

    function _afterProcessAccountingParams() internal pure returns (IHooks.AfterProcessAccountingParams memory) {
        return IHooks.AfterProcessAccountingParams({
            totalAssetsBeforeAccounting: 0,
            totalAssetsAfterAccounting: 0,
            totalSupplyBeforeAccounting: 0,
            totalSupplyAfterAccounting: 0,
            totalBaseAssetsBeforeAccounting: 0,
            totalBaseAssetsAfterAccounting: 0
        });
    }
}
