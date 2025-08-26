// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetaHooks} from "../../src/hooks/MetaHooks.sol";
import {IHooks, IVault} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IVaultForHooks} from "../../src/interface/IVaultForHooks.sol";

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

// Minimal mock for IVault
contract VaultMock is IVaultForHooks {
    address public asset_;
    uint256 public mintedShares;
    uint256 public assetsToShares;
    uint256 public feeOnRaw;
    uint256 public feeOnTotal;

    constructor(address _asset) {
        asset_ = _asset;
    }

    function asset() external view override returns (address) {
        return asset_;
    }

    function mintShares(address to, uint256 shares) external override {
        mintedShares += shares;
        // silence warning
        to;
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return assetsToShares + assets;
    }

    function _feeOnRaw(uint256 assets, address) external view override returns (uint256) {
        return feeOnRaw + assets;
    }

    function _feeOnTotal(uint256 shares, address) external view override returns (uint256) {
        return feeOnTotal + shares;
    }
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
        // Set up a hook that sets beforeDepositCalled
        IHooks.Config memory config = IHooks.Config({
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
        HooksMock hook = new HooksMock(config);
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        // Should revert if not called by vault
        vm.expectRevert(IHooks.CallerNotVault.selector);
        metaHooks.beforeDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);

        // Call as vault
        vm.startPrank(address(vault));
        metaHooks.beforeDeposit(address(0xDEAD), 1, address(this), address(this), 1, 1);
        vm.stopPrank();

        assertTrue(hook.beforeDepositCalled(), "beforeDeposit should be called on hook");
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
        // Create config with fuzzed boolean values
        IHooks.Config memory config = IHooks.Config({
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
        });

        // Create hook with fuzzed config
        HooksMock hook = new HooksMock(config);
        IHooks[] memory hooksArr = new IHooks[](1);
        hooksArr[0] = IHooks(address(hook));

        // Set hooks
        vm.startPrank(hookManager);
        metaHooks.setHooks(hooksArr);
        vm.stopPrank();

        // Test beforeDeposit
        vm.startPrank(address(vault));
        metaHooks.beforeDeposit(address(0xDEAD), 100, address(this), address(this), 50, 100);
        vm.stopPrank();
        assertEq(hook.beforeDepositCalled(), beforeDeposit, "beforeDeposit call mismatch");

        // Test afterDeposit
        vm.startPrank(address(vault));
        metaHooks.afterDeposit(address(0xDEAD), 100, address(this), address(this), 50, 100);
        vm.stopPrank();
        assertEq(hook.afterDepositCalled(), afterDeposit, "afterDeposit call mismatch");

        // Test beforeMint
        vm.startPrank(address(vault));
        metaHooks.beforeMint(address(0xDEAD), 50, address(this), address(this), 100, 100);
        vm.stopPrank();
        assertEq(hook.beforeMintCalled(), beforeMint, "beforeMint call mismatch");

        // Test afterMint
        vm.startPrank(address(vault));
        metaHooks.afterMint(address(0xDEAD), 50, address(this), address(this), 100, 100);
        vm.stopPrank();
        assertEq(hook.afterMintCalled(), afterMint, "afterMint call mismatch");

        // Test beforeRedeem
        vm.startPrank(address(vault));
        metaHooks.beforeRedeem(address(0xDEAD), 50, address(this), address(this), address(this), 100);
        vm.stopPrank();
        assertEq(hook.beforeRedeemCalled(), beforeRedeem, "beforeRedeem call mismatch");

        // Test afterRedeem
        vm.startPrank(address(vault));
        metaHooks.afterRedeem(address(0xDEAD), 50, address(this), address(this), address(this), 100);
        vm.stopPrank();
        assertEq(hook.afterRedeemCalled(), afterRedeem, "afterRedeem call mismatch");

        // Test beforeWithdraw
        vm.startPrank(address(vault));
        metaHooks.beforeWithdraw(address(0xDEAD), 100, address(this), address(this), address(this), 50);
        vm.stopPrank();
        assertEq(hook.beforeWithdrawCalled(), beforeWithdraw, "beforeWithdraw call mismatch");

        // Test afterWithdraw
        vm.startPrank(address(vault));
        metaHooks.afterWithdraw(address(0xDEAD), 100, address(this), address(this), address(this), 50);
        vm.stopPrank();
        assertEq(hook.afterWithdrawCalled(), afterWithdraw, "afterWithdraw call mismatch");

        // Test beforeProcessAccounting
        vm.startPrank(address(vault));
        metaHooks.beforeProcessAccounting(1000, 500, 800);
        vm.stopPrank();
        assertEq(hook.beforeProcessAccountingCalled(), beforeProcessAccounting, "beforeProcessAccounting call mismatch");

        // Test afterProcessAccounting
        vm.startPrank(address(vault));
        metaHooks.afterProcessAccounting(1000, 1100, 500, 550, 850, 800);
        vm.stopPrank();
        assertEq(hook.afterProcessAccountingCalled(), afterProcessAccounting, "afterProcessAccounting call mismatch");
    }
}
