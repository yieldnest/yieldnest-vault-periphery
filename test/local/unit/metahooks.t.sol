// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "src/interface/IVaultForHooks.sol";
import {VaultMock} from "./mocks/VaultMock.sol";

// Minimal mock for IHooks
contract HooksMock is IHooks {
    Config public config;
    bool public beforeDepositCalled;
    bool public afterDepositCalled;
    bool public beforeMintCalled;
    bool public afterMintCalled;
    bool public beforeRedeemCalled;
    bool public afterRedeemCalled;
    bool public beforeWithdrawCalled;
    bool public afterWithdrawCalled;
    bool public beforeProcessAccountingCalled;
    bool public afterProcessAccountingCalled;

    constructor(Config memory _config) {
        config = _config;
    }

    function getConfig() external view override returns (Config memory) {
        return config;
    }

    function beforeDeposit(address, uint256, address, address, uint256, uint256) external override {
        beforeDepositCalled = true;
    }

    function afterDeposit(address, uint256, address, address, uint256, uint256) external override {
        afterDepositCalled = true;
    }

    function beforeMint(address, uint256, address, address, uint256, uint256) external override {
        beforeMintCalled = true;
    }

    function afterMint(address, uint256, address, address, uint256, uint256) external override {
        afterMintCalled = true;
    }

    function beforeRedeem(address, uint256, address, address, address, uint256) external override {
        beforeRedeemCalled = true;
    }

    function afterRedeem(address, uint256, address, address, address, uint256) external override {
        afterRedeemCalled = true;
    }

    function beforeWithdraw(address, uint256, address, address, address, uint256) external override {
        beforeWithdrawCalled = true;
    }

    function afterWithdraw(address, uint256, address, address, address, uint256) external override {
        afterWithdrawCalled = true;
    }

    function beforeProcessAccounting(uint256, uint256, uint256) external override {
        beforeProcessAccountingCalled = true;
    }

    function afterProcessAccounting(uint256, uint256, uint256, uint256, uint256, uint256) external override {
        afterProcessAccountingCalled = true;
    }

    function VAULT() external pure returns (IVault) {
        return IVault(address(0));
    }

    function setConfig(Config memory) external {}
}

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
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);

        vm.startPrank(address(vault));
        metaHooks.beforeDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);
        assertTrue(hook.beforeDepositCalled(), "beforeDeposit should be called on hook");
        vm.stopPrank();

        // Test afterDeposit
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);

        vm.startPrank(address(vault));
        metaHooks.afterDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);
        assertTrue(hook.afterDepositCalled(), "afterDeposit should be called on hook");
        vm.stopPrank();

        // Test beforeMint
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeMint(address(0xDEAD), 1, address(this), address(this), 1, 1);

        vm.startPrank(address(vault));
        metaHooks.beforeMint(address(0xDEAD), 1, address(this), address(this), 1, 1);
        assertTrue(hook.beforeMintCalled(), "beforeMint should be called on hook");
        vm.stopPrank();

        // Test afterMint
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterMint(address(0xDEAD), 1, address(this), address(this), 1, 1);

        vm.startPrank(address(vault));
        metaHooks.afterMint(address(0xDEAD), 1, address(this), address(this), 1, 1);
        assertTrue(hook.afterMintCalled(), "afterMint should be called on hook");
        vm.stopPrank();

        // Test beforeRedeem
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeRedeem(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);

        vm.startPrank(address(vault));
        metaHooks.beforeRedeem(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);
        assertTrue(hook.beforeRedeemCalled(), "beforeRedeem should be called on hook");
        vm.stopPrank();

        // Test afterRedeem
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterRedeem(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);

        vm.startPrank(address(vault));
        metaHooks.afterRedeem(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);
        assertTrue(hook.afterRedeemCalled(), "afterRedeem should be called on hook");
        vm.stopPrank();

        // Test beforeWithdraw
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeWithdraw(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);

        vm.startPrank(address(vault));
        metaHooks.beforeWithdraw(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);
        assertTrue(hook.beforeWithdrawCalled(), "beforeWithdraw should be called on hook");
        vm.stopPrank();

        // Test afterWithdraw
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterWithdraw(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);

        vm.startPrank(address(vault));
        metaHooks.afterWithdraw(address(0xDEAD), 1, address(this), address(this), address(0xBEEF), 1);
        assertTrue(hook.afterWithdrawCalled(), "afterWithdraw should be called on hook");
        vm.stopPrank();

        // Test beforeProcessAccounting
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeProcessAccounting(1, 1, 1);

        vm.startPrank(address(vault));
        metaHooks.beforeProcessAccounting(1, 1, 1);
        assertTrue(hook.beforeProcessAccountingCalled(), "beforeProcessAccounting should be called on hook");
        vm.stopPrank();

        // Test afterProcessAccounting
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.afterProcessAccounting(1, 1, 1, 1, 1, 1);

        vm.startPrank(address(vault));
        metaHooks.afterProcessAccounting(1, 1, 1, 1, 1, 1);
        assertTrue(hook.afterProcessAccountingCalled(), "afterProcessAccounting should be called on hook");
        vm.stopPrank();
    }

    function testOnlyHookCanCallVaultFunctions() public {
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

        // Call as hook
        vm.startPrank(address(hook));
        metaHooks.mintShares(address(0x1234), 10);
        vm.stopPrank();

        assertEq(vault.mintedShares(), 10, "mintedShares should be updated in vault");
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

        // Test beforeDeposit
        vm.startPrank(address(vault));
        metaHooks.beforeDeposit(address(0xDEAD), 100, address(this), address(this), 50, 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].beforeDepositCalled(), beforeDeposits[i], "beforeDeposit call mismatch");
        }

        // Test afterDeposit
        vm.startPrank(address(vault));
        metaHooks.afterDeposit(address(0xDEAD), 100, address(this), address(this), 50, 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].afterDepositCalled(), afterDeposits[i], "afterDeposit call mismatch");
        }

        // Test beforeMint
        vm.startPrank(address(vault));
        metaHooks.beforeMint(address(0xDEAD), 50, address(this), address(this), 100, 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].beforeMintCalled(), beforeMints[i], "beforeMint call mismatch");
        }

        // Test afterMint
        vm.startPrank(address(vault));
        metaHooks.afterMint(address(0xDEAD), 50, address(this), address(this), 100, 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].afterMintCalled(), afterMints[i], "afterMint call mismatch");
        }

        // Test beforeRedeem
        vm.startPrank(address(vault));
        metaHooks.beforeRedeem(address(0xDEAD), 50, address(this), address(this), address(this), 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].beforeRedeemCalled(), beforeRedeems[i], "beforeRedeem call mismatch");
        }

        // Test afterRedeem
        vm.startPrank(address(vault));
        metaHooks.afterRedeem(address(0xDEAD), 50, address(this), address(this), address(this), 100);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].afterRedeemCalled(), afterRedeems[i], "afterRedeem call mismatch");
        }

        // Test beforeWithdraw
        vm.startPrank(address(vault));
        metaHooks.beforeWithdraw(address(0xDEAD), 100, address(this), address(this), address(this), 50);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].beforeWithdrawCalled(), beforeWithdraws[i], "beforeWithdraw call mismatch");
        }

        // Test afterWithdraw
        vm.startPrank(address(vault));
        metaHooks.afterWithdraw(address(0xDEAD), 100, address(this), address(this), address(this), 50);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(hooks[i].afterWithdrawCalled(), afterWithdraws[i], "afterWithdraw call mismatch");
        }

        // Test beforeProcessAccounting
        vm.startPrank(address(vault));
        metaHooks.beforeProcessAccounting(1000, 500, 800);
        vm.stopPrank();
        for (uint256 i = 0; i < count; i++) {
            assertEq(
                hooks[i].beforeProcessAccountingCalled(),
                beforeProcessAccountings[i],
                "beforeProcessAccounting call mismatch"
            );
        }

        // Test afterProcessAccounting
        vm.startPrank(address(vault));
        metaHooks.afterProcessAccounting(1000, 1100, 500, 550, 850, 800);
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
