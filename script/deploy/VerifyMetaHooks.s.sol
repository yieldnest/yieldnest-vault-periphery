// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {FeeHooks, IHooks, IVault} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {BaseScript} from "script/deploy/BaseScript.sol";
import {console} from "lib/forge-std/src/console.sol";

import {Test} from "lib/forge-std/src/Test.sol";

contract VerifyMetaHooks is BaseScript, Test {
    uint256 public performanceFee = 0.1 ether; // 10%

    uint256 public maxDecreaseRatio = 0.0005 ether; // 0.05%
    uint256 public maxIncreaseRatio = 0.002 ether; // 0.2%
    uint256 public maxTotalSupplyIncreaseRatio = 0.0005 ether; // 0.05%, 25% of maxIncreaseRatio

    function run() public virtual {
        actors = new MainnetActors();

        loadDeployment();
        verify();
        console.log("Verification successful!");
    }

    function label() public view override returns (string memory) {
        return string.concat("metaHooks-ynETHx-", Strings.toString(block.chainid));
    }

    function compareConfigsWithAsserts(IHooks.Config memory a, IHooks.Config memory b) internal pure {
        assertEq(a.beforeDeposit, b.beforeDeposit, "Config: beforeDeposit mismatch");
        assertEq(a.afterDeposit, b.afterDeposit, "Config: afterDeposit mismatch");
        assertEq(a.beforeMint, b.beforeMint, "Config: beforeMint mismatch");
        assertEq(a.afterMint, b.afterMint, "Config: afterMint mismatch");
        assertEq(a.beforeRedeem, b.beforeRedeem, "Config: beforeRedeem mismatch");
        assertEq(a.afterRedeem, b.afterRedeem, "Config: afterRedeem mismatch");
        assertEq(a.beforeWithdraw, b.beforeWithdraw, "Config: beforeWithdraw mismatch");
        assertEq(a.afterWithdraw, b.afterWithdraw, "Config: afterWithdraw mismatch");
        assertEq(a.beforeProcessAccounting, b.beforeProcessAccounting, "Config: beforeProcessAccounting mismatch");
        assertEq(a.afterProcessAccounting, b.afterProcessAccounting, "Config: afterProcessAccounting mismatch");
    }

    function verify() public virtual {
        assertNotEq(msg.sender, deployer, "msg.sender should not be deployer as this is a verifier script.");

        assertEq(
            processAccountingGuardHook.expectedPerformanceFee(),
            performanceFee,
            "processAccountingGuardHook: expectedPerformanceFee mismatch"
        );
        assertEq(
            processAccountingGuardHook.maxTotalAssetsDecreaseRatio(),
            maxDecreaseRatio,
            "processAccountingGuardHook: maxTotalAssetsDecreaseRatio mismatch"
        );
        assertEq(
            processAccountingGuardHook.maxTotalAssetsIncreaseRatio(),
            maxIncreaseRatio,
            "processAccountingGuardHook: maxTotalAssetsIncreaseRatio mismatch"
        );
        assertEq(
            processAccountingGuardHook.maxTotalSupplyIncreaseRatio(),
            maxTotalSupplyIncreaseRatio,
            "processAccountingGuardHook: maxTotalSupplyIncreaseRatio mismatch"
        );

        assertEq(feeHooks.performanceFee(), performanceFee, "feeHooks: performanceFee mismatch");
        assertEq(
            feeHooks.performanceFeeRecipient(), performanceFeeRecipient, "feeHooks: performanceFeeRecipient mismatch"
        );

        // MetaHooks checks
        assertEq(address(metaHooks.VAULT()), address(vault), "MetaHooks: vault address mismatch");
        assertEq(
            metaHooks.hasRole(metaHooks.DEFAULT_ADMIN_ROLE(), actors.ADMIN()),
            true,
            "MetaHooks: ADMIN should have DEFAULT_ADMIN_ROLE"
        );

        assertEq(
            metaHooks.hasRole(metaHooks.HOOK_MANAGER_ROLE(), actors.HOOKS_MANAGER()),
            true,
            "MetaHooks: HOOKS_MANAGER should have HOOK_MANAGER_ROLE"
        );
        assertEq(
            metaHooks.hasRole(metaHooks.DEFAULT_ADMIN_ROLE(), deployer),
            false,
            "MetaHooks: deployer should not have DEFAULT_ADMIN_ROLE"
        );
        assertEq(
            metaHooks.hasRole(metaHooks.HOOK_MANAGER_ROLE(), deployer),
            false,
            "MetaHooks: deployer should not have HOOK_MANAGER_ROLE"
        );

        // Hooks array check
        IHooks[] memory hooks = metaHooks.getHooks();
        assertEq(hooks.length, 2, "MetaHooks: hooks array length should be 2");
        assertEq(address(hooks[0]), address(feeHooks), "MetaHooks: hooks[0] should be feeHooks");
        assertEq(
            address(hooks[1]),
            address(processAccountingGuardHook),
            "MetaHooks: hooks[1] should be processAccountingGuardHook"
        );
        for (uint256 i = 0; i < hooks.length; i++) {
            assertEq(
                address(IHooks(hooks[i]).VAULT()),
                address(metaHooks),
                string(abi.encodePacked("Hook[", vm.toString(i), "]: VAULT address mismatch"))
            );
        }

        // Config to compare against
        IHooks.Config memory expectedConfig = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });

        // FeeHooks config check
        IHooks.Config memory feeHooksConfig = feeHooks.getConfig();
        compareConfigsWithAsserts(feeHooksConfig, expectedConfig);

        // ProcessAccountingGuardHook config check
        IHooks.Config memory processAccountingGuardHookConfig = processAccountingGuardHook.getConfig();
        compareConfigsWithAsserts(processAccountingGuardHookConfig, expectedConfig);

        // MetaHooks config check
        IHooks.Config memory metaHooksConfig = metaHooks.getConfig();
        compareConfigsWithAsserts(metaHooksConfig, expectedConfig);

        // FeeHooks owner check
        assertEq(feeHooks.owner(), actors.ADMIN(), "FeeHooks: owner should be ADMIN");

        // ProcessAccountingGuardHook owner check
        assertEq(
            processAccountingGuardHook.owner(), actors.ADMIN(), "ProcessAccountingGuardHook: owner should be ADMIN"
        );

        // Vault check
        assertEq(address(vault), address(MC.YNETHX), "Vault: address mismatch");

        // L1Actors check
    }
}
