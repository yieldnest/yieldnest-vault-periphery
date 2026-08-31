// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {HooksLib} from "lib/yieldnest-vault/src/library/HooksLib.sol";
import {ProcessorUtils} from "lib/yieldnest-vault/test/utils/ProcessorUtils.sol";
import {PauserHook} from "src/hooks/PauserHook.sol";

contract PauserHookIntegrationTest is BaseIntegrationTest {
    PauserHook public pauserHook;

    function setUp() public override {
        super.setUp();

        pauserHook = new PauserHook(address(metaHooks), ADMIN, PAUSER, UNPAUSER);

        IHooks[] memory hooks = new IHooks[](1);
        hooks[0] = IHooks(address(pauserHook));

        vm.prank(HOOK_MANAGER);
        metaHooks.setHooks(hooks);
    }

    function test_deposit_reverts_when_paused() public {
        _pause(PauserHook.HookCall.Deposit);

        deal(vault.asset(), depositor, 1 ether);

        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 1 ether);

        _expectPaused(PauserHook.HookCall.Deposit);
        vault.deposit(1 ether, depositor);

        vm.stopPrank();
    }

    function test_mint_reverts_when_paused() public {
        _pause(PauserHook.HookCall.Mint);

        deal(vault.asset(), depositor, 1 ether);

        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), 1 ether);

        _expectPaused(PauserHook.HookCall.Mint);
        vault.mint(1 ether, depositor);

        vm.stopPrank();
    }

    function test_withdraw_reverts_when_paused() public {
        _deposit(depositor, 2 ether);
        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        _pause(PauserHook.HookCall.Withdraw);

        vm.startPrank(depositor);
        _expectPaused(PauserHook.HookCall.Withdraw);
        vault.withdraw(0.5 ether, depositor, depositor);
        vm.stopPrank();
    }

    function test_redeem_reverts_when_paused() public {
        uint256 shares = _deposit(depositor, 2 ether);
        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        _pause(PauserHook.HookCall.Redeem);

        vm.startPrank(depositor);
        _expectPaused(PauserHook.HookCall.Redeem);
        vault.redeem(shares / 4, depositor, depositor);
        vm.stopPrank();
    }

    function test_processAccounting_reverts_when_paused() public {
        _pause(PauserHook.HookCall.ProcessAccounting);

        _expectPaused(PauserHook.HookCall.ProcessAccounting);
        vault.processAccounting();
    }

    function test_deposit_succeeds_after_unpause() public {
        _pause(PauserHook.HookCall.Deposit);

        vm.prank(UNPAUSER);
        pauserHook.unpause(PauserHook.HookCall.Deposit);

        _deposit(depositor, 1 ether);

        assertEq(vault.balanceOf(depositor), 1 ether);
        assertEq(vault.totalAssets(), 1 ether);
    }

    function test_deposit_succeeds_when_withdraw_is_paused() public {
        _pause(PauserHook.HookCall.Withdraw);
        _deposit(depositor, 1 ether);

        assertEq(vault.balanceOf(depositor), 1 ether);
    }

    function _pause(PauserHook.HookCall hookCall) internal {
        vm.prank(PAUSER);
        pauserHook.pause(hookCall);
    }

    function _expectPaused(PauserHook.HookCall hookCall) internal {
        bytes memory revertData = abi.encodeWithSelector(PauserHook.Paused.selector, hookCall);
        vm.expectRevert(abi.encodeWithSelector(HooksLib.HookCallFailed.selector, revertData));
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        deal(vault.asset(), user, amount);

        vm.startPrank(user);
        IERC20(vault.asset()).approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }
}
