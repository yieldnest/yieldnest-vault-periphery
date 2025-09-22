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

    function test_getConfig_emptyHooks() public view {
        // Test getConfig when no hooks are set
        IHooks.Config memory config = metaHooks.getConfig();

        assertFalse(config.beforeDeposit, "beforeDeposit should be false when no hooks are set");
        assertFalse(config.afterDeposit, "afterDeposit should be false when no hooks are set");
        assertFalse(config.beforeMint, "beforeMint should be false when no hooks are set");
        assertFalse(config.afterMint, "afterMint should be false when no hooks are set");
        assertFalse(config.beforeRedeem, "beforeRedeem should be false when no hooks are set");
        assertFalse(config.afterRedeem, "afterRedeem should be false when no hooks are set");
        assertFalse(config.beforeWithdraw, "beforeWithdraw should be false when no hooks are set");
        assertFalse(config.afterWithdraw, "afterWithdraw should be false when no hooks are set");
        assertFalse(config.beforeProcessAccounting, "beforeProcessAccounting should be false when no hooks are set");
        assertFalse(config.afterProcessAccounting, "afterProcessAccounting should be false when no hooks are set");
    }

    function test_getConfig_withHooks() public {
        vm.startPrank(hookManager);

        // Create hooks with different configurations
        IHooks[] memory hooks = new IHooks[](3);

        // Hook 1: only beforeDeposit and afterMint
        hooks[0] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: true,
                        afterDeposit: false,
                        beforeMint: false,
                        afterMint: true,
                        beforeRedeem: false,
                        afterRedeem: false,
                        beforeWithdraw: false,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: false
                    })
                )
            )
        );

        // Hook 2: only afterDeposit and beforeRedeem
        hooks[1] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: false,
                        afterDeposit: true,
                        beforeMint: false,
                        afterMint: false,
                        beforeRedeem: true,
                        afterRedeem: false,
                        beforeWithdraw: false,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: false
                    })
                )
            )
        );

        // Hook 3: only beforeWithdraw and afterProcessAccounting
        hooks[2] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: false,
                        afterDeposit: false,
                        beforeMint: false,
                        afterMint: false,
                        beforeRedeem: false,
                        afterRedeem: false,
                        beforeWithdraw: true,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: true
                    })
                )
            )
        );

        metaHooks.setHooks(hooks);

        // Test that getConfig returns the OR of all hook configurations
        IHooks.Config memory config = metaHooks.getConfig();

        assertTrue(config.beforeDeposit, "beforeDeposit should be true (from hook 1)");
        assertTrue(config.afterDeposit, "afterDeposit should be true (from hook 2)");
        assertFalse(config.beforeMint, "beforeMint should be false (none have this)");
        assertTrue(config.afterMint, "afterMint should be true (from hook 1)");
        assertTrue(config.beforeRedeem, "beforeRedeem should be true (from hook 2)");
        assertFalse(config.afterRedeem, "afterRedeem should be false (none have this)");
        assertTrue(config.beforeWithdraw, "beforeWithdraw should be true (from hook 3)");
        assertFalse(config.afterWithdraw, "afterWithdraw should be false (none have this)");
        assertFalse(config.beforeProcessAccounting, "beforeProcessAccounting should be false (none have this)");
        assertTrue(config.afterProcessAccounting, "afterProcessAccounting should be true (from hook 3)");

        vm.stopPrank();
    }

    function test_getHooks_empty() public view {
        // Test getHooks when no hooks are set
        IHooks[] memory hooks = metaHooks.getHooks();
        assertEq(hooks.length, 0, "hooks should be empty when no hooks are set");
    }

    function test_getHooksLength_empty() public view {
        // Test getHooksLength when no hooks are set
        assertEq(metaHooks.hooksLength(), 0, "hooksLength should be 0 when no hooks are set");
    }

    function test_getHooks_withHooks() public {
        // Test getHooks when hooks are set
        vm.startPrank(hookManager);

        IHooks[] memory hooks = new IHooks[](3);
        hooks[0] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: true,
                        afterDeposit: false,
                        beforeMint: false,
                        afterMint: true,
                        beforeRedeem: false,
                        afterRedeem: false,
                        beforeWithdraw: false,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: false
                    })
                )
            )
        );
        hooks[1] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: false,
                        afterDeposit: true,
                        beforeMint: false,
                        afterMint: false,
                        beforeRedeem: true,
                        afterRedeem: false,
                        beforeWithdraw: false,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: false
                    })
                )
            )
        );
        hooks[2] = IHooks(
            address(
                new HooksMock(
                    IHooks.Config({
                        beforeDeposit: false,
                        afterDeposit: false,
                        beforeMint: false,
                        afterMint: false,
                        beforeRedeem: false,
                        afterRedeem: false,
                        beforeWithdraw: true,
                        afterWithdraw: false,
                        beforeProcessAccounting: false,
                        afterProcessAccounting: true
                    })
                )
            )
        );

        metaHooks.setHooks(hooks);

        IHooks[] memory retrievedHooks = metaHooks.getHooks();
        assertEq(retrievedHooks.length, 3, "hooks should be 3 when hooks are set");
        assertEq(metaHooks.hooksLength(), 3, "hooksLength should be 3 when hooks are set");
        for (uint256 i = 0; i < retrievedHooks.length; i++) {
            assertEq(address(retrievedHooks[i]), address(hooks[i]), "retrieved hook should match set hook");
        }

        vm.stopPrank();
    }

    function test_vault_view() public view {
        // Test that vault() returns the correct vault address
        assertEq(address(metaHooks.VAULT()), address(vault), "VAULT() should return the correct vault address");
    }

    function test_convertToShares(uint256 assets) public view {
        // Test convertToShares view function
        uint256 shares = metaHooks.convertToShares(assets);
        uint256 expectedShares = vault.convertToShares(assets);
        assertEq(shares, expectedShares, "convertToShares should match vault's convertToShares");
    }

    function test_asset() public view {
        // Test asset view function
        address assetAddress = metaHooks.asset();
        address expectedAsset = vault.asset();
        assertEq(assetAddress, expectedAsset, "asset() should return the same asset as vault");
    }

    function test_feeOnRaw(uint256 amount, address caller) public view {
        // Test _feeOnRaw view function
        uint256 fee = metaHooks._feeOnRaw(amount, caller);
        uint256 expectedFee = vault._feeOnRaw(amount, caller);
        assertEq(fee, expectedFee, "_feeOnRaw should match vault's _feeOnRaw");
    }

    function test_feeOnTotal(uint256 amount, address caller) public view {
        // Test _feeOnTotal view function
        uint256 fee = metaHooks._feeOnTotal(amount, caller);
        uint256 expectedFee = vault._feeOnTotal(amount, caller);
        assertEq(fee, expectedFee, "_feeOnTotal should match vault's _feeOnTotal");
    }

    function test_previewDepositAsset(uint256 assets) public view {
        // Test previewDepositAsset view function
        address assetAddress = vault.asset();
        uint256 shares = metaHooks.previewDepositAsset(assetAddress, assets);
        uint256 expectedShares = vault.previewDepositAsset(assetAddress, assets);
        assertEq(shares, expectedShares, "previewDepositAsset should match vault's previewDepositAsset");
    }

    function test_convertToAssets(uint256 shares) public view {
        // Test convertToAssets view function
        uint256 assets = metaHooks.convertToAssets(shares);
        uint256 expectedAssets = vault.convertToAssets(shares);
        assertEq(assets, expectedAssets, "convertToAssets should match vault's convertToAssets");
    }
}
