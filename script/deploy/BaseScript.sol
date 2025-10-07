// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {FeeHooks, IHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {IActors} from "lib/yieldnest-vault/script/Actors.sol";

abstract contract BaseScript is Script {
    address public deployer;

    address public vault;
    MetaHooks public metaHooks;
    FeeHooks public feeHooks;
    ProcessAccountingGuardHook public processAccountingGuardHook;
    IActors public actors;
    address public performanceFeeRecipient;

    function label() public view virtual returns (string memory);

    function deploymentFilePath() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal virtual {
        vm.serializeAddress(label(), "metaHooks", address(metaHooks));
        vm.serializeAddress(label(), "feeHooks", address(feeHooks));
        vm.serializeAddress(label(), "processAccountingGuardHook", address(processAccountingGuardHook));
        vm.serializeAddress(label(), "vault", address(vault));
        vm.serializeAddress(label(), "admin", actors.ADMIN());
        vm.serializeAddress(label(), "hooksManager", actors.HOOKS_MANAGER());
        vm.serializeAddress(label(), "performanceFeeRecipient", performanceFeeRecipient);

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function loadDeployment() internal virtual {
        if (!vm.isFile(deploymentFilePath())) {
            return;
        }
        string memory jsonInput = vm.readFile(deploymentFilePath());

        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        vault = address(vm.parseJsonAddress(jsonInput, ".vault"));
        metaHooks = MetaHooks(address(vm.parseJsonAddress(jsonInput, ".metaHooks")));
        feeHooks = FeeHooks(address(vm.parseJsonAddress(jsonInput, ".feeHooks")));
        processAccountingGuardHook =
            ProcessAccountingGuardHook(address(vm.parseJsonAddress(jsonInput, ".processAccountingGuardHook")));
        performanceFeeRecipient = address(vm.parseJsonAddress(jsonInput, ".performanceFeeRecipient"));
    }
}
