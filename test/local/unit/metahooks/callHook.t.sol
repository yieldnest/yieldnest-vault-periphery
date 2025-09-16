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
    MetaHooks public metaHooks;
    VaultMock public vault;
    address public admin = address(0xA1);
    address public hookManager = address(0xB1);

    function setUp() public {
        vault = new VaultMock(address(0xDEAD));
        metaHooks = new MetaHooks(address(vault), admin, hookManager);
    }

    function testOnlyVaultCanCallHooks() public {
        // Set up a hook that enables all hook functions
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
        HooksMock hook = new HooksMock(config);
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        // Test beforeDeposit
        IHooks.DepositParams memory depositParams = IHooks.DepositParams({
            asset: address(0xDEAD),
            assets: 1,
            caller: address(this),
            receiver: address(this),
            shares: 1,
            baseAssets: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeDeposit(depositParams);

        vm.startPrank(address(vault));
        metaHooks.beforeDeposit(depositParams);
        assertTrue(hook.beforeDepositCalled(), "beforeDeposit should be called on hook");
        vm.stopPrank();

        // Test afterDeposit
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterDeposit(depositParams);

        vm.startPrank(address(vault));
        metaHooks.afterDeposit(depositParams);
        assertTrue(hook.afterDepositCalled(), "afterDeposit should be called on hook");
        vm.stopPrank();

        // Test beforeMint
        IHooks.MintParams memory mintParams = IHooks.MintParams({
            asset: address(0xDEAD),
            shares: 1,
            caller: address(this),
            receiver: address(this),
            assets: 1,
            baseAssets: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeMint(mintParams);

        vm.startPrank(address(vault));
        metaHooks.beforeMint(mintParams);
        assertTrue(hook.beforeMintCalled(), "beforeMint should be called on hook");
        vm.stopPrank();

        // Test afterMint
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterMint(mintParams);

        vm.startPrank(address(vault));
        metaHooks.afterMint(mintParams);
        assertTrue(hook.afterMintCalled(), "afterMint should be called on hook");
        vm.stopPrank();

        // Test beforeRedeem
        IHooks.RedeemParams memory redeemParams = IHooks.RedeemParams({
            asset: address(0xDEAD),
            shares: 1,
            caller: address(this),
            receiver: address(this),
            owner: address(0xBEEF),
            assets: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeRedeem(redeemParams);

        vm.startPrank(address(vault));
        metaHooks.beforeRedeem(redeemParams);
        assertTrue(hook.beforeRedeemCalled(), "beforeRedeem should be called on hook");
        vm.stopPrank();

        // Test afterRedeem
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterRedeem(redeemParams);

        vm.startPrank(address(vault));
        metaHooks.afterRedeem(redeemParams);
        assertTrue(hook.afterRedeemCalled(), "afterRedeem should be called on hook");
        vm.stopPrank();

        // Test beforeWithdraw
        IHooks.WithdrawParams memory withdrawParams = IHooks.WithdrawParams({
            asset: address(0xDEAD),
            assets: 1,
            caller: address(this),
            receiver: address(this),
            owner: address(0xBEEF),
            shares: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeWithdraw(withdrawParams);

        vm.startPrank(address(vault));
        metaHooks.beforeWithdraw(withdrawParams);
        assertTrue(hook.beforeWithdrawCalled(), "beforeWithdraw should be called on hook");
        vm.stopPrank();

        // Test afterWithdraw
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterWithdraw(withdrawParams);

        vm.startPrank(address(vault));
        metaHooks.afterWithdraw(withdrawParams);
        assertTrue(hook.afterWithdrawCalled(), "afterWithdraw should be called on hook");
        vm.stopPrank();

        // Test beforeProcessAccounting
        IHooks.BeforeProcessAccountingParams memory beforeAccountingParams = IHooks.BeforeProcessAccountingParams({
            totalAssetsBeforeAccounting: 1,
            totalSupplyBeforeAccounting: 1,
            totalBaseAssetsBeforeAccounting: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeProcessAccounting(beforeAccountingParams);

        vm.startPrank(address(vault));
        metaHooks.beforeProcessAccounting(beforeAccountingParams);
        assertTrue(hook.beforeProcessAccountingCalled(), "beforeProcessAccounting should be called on hook");
        vm.stopPrank();

        // Test afterProcessAccounting
        IHooks.AfterProcessAccountingParams memory afterAccountingParams = IHooks.AfterProcessAccountingParams({
            totalAssetsBeforeAccounting: 1,
            totalAssetsAfterAccounting: 1,
            totalSupplyBeforeAccounting: 1,
            totalSupplyAfterAccounting: 1,
            totalBaseAssetsBeforeAccounting: 1,
            totalBaseAssetsAfterAccounting: 1
        });
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterProcessAccounting(afterAccountingParams);

        vm.startPrank(address(vault));
        metaHooks.afterProcessAccounting(afterAccountingParams);
        assertTrue(hook.afterProcessAccountingCalled(), "afterProcessAccounting should be called on hook");
        vm.stopPrank();
    }

    function testFuzzMetaHooksCallsAllHooksWithDifferentConfigs(
        bool beforeDeposit,
        bool afterDeposit,
        bool beforeMint,
        bool afterMint,
        bool beforeRedeem,
        bool afterRedeem,
        bool beforeWithdraw,
        bool afterWithdraw,
        bool beforeProcessAccounting,
        bool afterProcessAccounting
    ) public {
        // Create hook with fuzzed config
        HooksMock hook = new HooksMock(
            IHooks.Config({
                beforeDeposit: beforeDeposit,
                afterDeposit: afterDeposit,
                beforeMint: beforeMint,
                afterMint: afterMint,
                beforeRedeem: beforeRedeem,
                afterRedeem: afterRedeem,
                beforeWithdraw: beforeWithdraw,
                afterWithdraw: afterWithdraw,
                beforeProcessAccounting: beforeProcessAccounting,
                afterProcessAccounting: afterProcessAccounting
            })
        );
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        // Set hooks
        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        // Test all hook calls with the single hook
        HooksMock[] memory hooks = new HooksMock[](1);
        hooks[0] = hook;

        _testAllHookCalls(
            hooks,
            _castBoolToDynamic(beforeDeposit),
            _castBoolToDynamic(afterDeposit),
            _castBoolToDynamic(beforeMint),
            _castBoolToDynamic(afterMint),
            _castBoolToDynamic(beforeRedeem),
            _castBoolToDynamic(afterRedeem),
            _castBoolToDynamic(beforeWithdraw),
            _castBoolToDynamic(afterWithdraw),
            _castBoolToDynamic(beforeProcessAccounting),
            _castBoolToDynamic(afterProcessAccounting)
        );
    }

    function testMetaHooksWithMultipleHooks(
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
        // Create arrays of 5 hooks with fuzzed configurations
        HooksMock[] memory hooks = new HooksMock[](5);

        // Initialize hooks with fuzzed configurations
        for (uint256 i = 0; i < 5; i++) {
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

        // Convert to IHooks array
        IHooks[] memory ihooks = new IHooks[](5);
        for (uint256 i = 0; i < 5; i++) {
            ihooks[i] = IHooks(address(hooks[i]));
        }

        vm.startPrank(hookManager);
        metaHooks.setHooks(ihooks);
        vm.stopPrank();

        _testAllHookCalls(
            hooks,
            _castBoolArrToDynamic(beforeDeposits),
            _castBoolArrToDynamic(afterDeposits),
            _castBoolArrToDynamic(beforeMints),
            _castBoolArrToDynamic(afterMints),
            _castBoolArrToDynamic(beforeRedeems),
            _castBoolArrToDynamic(afterRedeems),
            _castBoolArrToDynamic(beforeWithdraws),
            _castBoolArrToDynamic(afterWithdraws),
            _castBoolArrToDynamic(beforeProcessAccountings),
            _castBoolArrToDynamic(afterProcessAccountings)
        );
    }

    function _castBoolArrToDynamic(bool[5] memory fixedArray) internal pure returns (bool[] memory) {
        bool[] memory dynamicArray = new bool[](5);
        for (uint256 i = 0; i < 5; i++) {
            dynamicArray[i] = fixedArray[i];
        }
        return dynamicArray;
    }

    function _castBoolToDynamic(bool value) internal pure returns (bool[] memory) {
        bool[] memory dynamicArray = new bool[](1);
        dynamicArray[0] = value;
        return dynamicArray;
    }

    function _testAllHookCalls(
        HooksMock[] memory hooks,
        bool[] memory beforeDeposits,
        bool[] memory afterDeposits,
        bool[] memory beforeMints,
        bool[] memory afterMints,
        bool[] memory beforeRedeems,
        bool[] memory afterRedeems,
        bool[] memory beforeWithdraws,
        bool[] memory afterWithdraws,
        bool[] memory beforeProcessAccountings,
        bool[] memory afterProcessAccountings
    ) internal {
        uint256 count = hooks.length;

        {
            // Test beforeDeposit
            vm.startPrank(address(vault));
            IHooks.DepositParams memory depositParams = IHooks.DepositParams({
                asset: address(0xDEAD),
                assets: 100,
                caller: address(this),
                receiver: address(this),
                shares: 50,
                baseAssets: 100
            });
            metaHooks.beforeDeposit(depositParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].beforeDepositCalled(), beforeDeposits[i], "beforeDeposit call mismatch");
            }

            // Test afterDeposit
            vm.startPrank(address(vault));
            metaHooks.afterDeposit(depositParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].afterDepositCalled(), afterDeposits[i], "afterDeposit call mismatch");
            }
        }

        {
            // Test beforeMint
            vm.startPrank(address(vault));
            IHooks.MintParams memory mintParams = IHooks.MintParams({
                asset: address(0xDEAD),
                shares: 50,
                caller: address(this),
                receiver: address(this),
                assets: 100,
                baseAssets: 100
            });
            metaHooks.beforeMint(mintParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].beforeMintCalled(), beforeMints[i], "beforeMint call mismatch");
            }

            // Test afterMint
            vm.startPrank(address(vault));
            metaHooks.afterMint(mintParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].afterMintCalled(), afterMints[i], "afterMint call mismatch");
            }
        }

        {
            // Test beforeRedeem
            vm.startPrank(address(vault));
            IHooks.RedeemParams memory redeemParams = IHooks.RedeemParams({
                asset: address(0xDEAD),
                shares: 50,
                caller: address(this),
                receiver: address(this),
                owner: address(this),
                assets: 100
            });
            metaHooks.beforeRedeem(redeemParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].beforeRedeemCalled(), beforeRedeems[i], "beforeRedeem call mismatch");
            }

            // Test afterRedeem
            vm.startPrank(address(vault));
            metaHooks.afterRedeem(redeemParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].afterRedeemCalled(), afterRedeems[i], "afterRedeem call mismatch");
            }
        }

        {
            // Test beforeWithdraw
            vm.startPrank(address(vault));
            IHooks.WithdrawParams memory withdrawParams = IHooks.WithdrawParams({
                asset: address(0xDEAD),
                assets: 100,
                caller: address(this),
                receiver: address(this),
                owner: address(this),
                shares: 50
            });
            metaHooks.beforeWithdraw(withdrawParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].beforeWithdrawCalled(), beforeWithdraws[i], "beforeWithdraw call mismatch");
            }

            // Test afterWithdraw
            vm.startPrank(address(vault));
            metaHooks.afterWithdraw(withdrawParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(hooks[i].afterWithdrawCalled(), afterWithdraws[i], "afterWithdraw call mismatch");
            }
        }

        {
            // Test beforeProcessAccounting
            vm.startPrank(address(vault));
            IHooks.BeforeProcessAccountingParams memory beforeAccountingParams = IHooks.BeforeProcessAccountingParams({
                totalAssetsBeforeAccounting: 1000,
                totalSupplyBeforeAccounting: 500,
                totalBaseAssetsBeforeAccounting: 800
            });
            metaHooks.beforeProcessAccounting(beforeAccountingParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(
                    hooks[i].beforeProcessAccountingCalled(),
                    beforeProcessAccountings[i],
                    "beforeProcessAccounting call mismatch"
                );
            }
        }

        {
            // Test afterProcessAccounting
            vm.startPrank(address(vault));
            IHooks.AfterProcessAccountingParams memory afterAccountingParams = IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1000,
                totalAssetsAfterAccounting: 1100,
                totalSupplyBeforeAccounting: 500,
                totalSupplyAfterAccounting: 550,
                totalBaseAssetsBeforeAccounting: 850,
                totalBaseAssetsAfterAccounting: 800
            });
            metaHooks.afterProcessAccounting(afterAccountingParams);
            vm.stopPrank();
            for (uint256 i = 0; i < count; i++) {
                assertEq(
                    hooks[i].afterProcessAccountingCalled(),
                    afterProcessAccountings[i],
                    "afterProcessAccounting call mismatch"
                );
            }
        }
    }
}
