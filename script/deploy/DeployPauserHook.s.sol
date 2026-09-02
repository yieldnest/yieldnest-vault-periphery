// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {PauserHook} from "src/hooks/PauserHook.sol";

contract DeployPauserHook is Script {
    MainnetActors public actors;
    PauserHook public pauserHook;

    function run() public virtual {
        actors = new MainnetActors();
        address vault_ = vm.promptAddress("Vault");

        vm.startBroadcast();

        pauserHook = new PauserHook(vault_, actors.ADMIN(), actors.PAUSER(), actors.UNPAUSER());

        vm.stopBroadcast();

        saveDeployment(vault_);
    }

    function saveDeployment(address vault_) internal {
        string memory label = deploymentLabel(vault_);

        vm.serializeAddress(label, "pauserHook", address(pauserHook));
        vm.serializeAddress(label, "vault", vault_);
        vm.serializeAddress(label, "admin", actors.ADMIN());
        vm.serializeAddress(label, "pauser", actors.PAUSER());
        vm.serializeAddress(label, "unpauser", actors.UNPAUSER());
        vm.serializeUint(label, "chainId", block.chainid);
        string memory jsonOutput = vm.serializeAddress(label, "deployer", msg.sender);

        vm.writeJson(jsonOutput, deploymentFilePath(vault_));
    }

    function deploymentLabel(address vault_) internal view returns (string memory) {
        return string.concat("pauserHook-", Strings.toHexString(vault_), "-", Strings.toString(block.chainid));
    }

    function deploymentFilePath(address vault_) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", deploymentLabel(vault_), ".json");
    }
}
