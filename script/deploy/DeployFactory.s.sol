// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {HooksFactory} from "script/factory/HooksFactory.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployFactory is Script {
    function run() public virtual {
        vm.startBroadcast();

        HooksFactory factory = new HooksFactory();

        vm.stopBroadcast();

        // Save factory deployment info to JSON
        string memory version = factory.FACTORY_VERSION();
        vm.serializeAddress("HooksFactory", "address", address(factory));
        string memory json = vm.serializeString("HooksFactory", "version", version);
        string memory filename =
            string.concat(vm.projectRoot(), "/deployments/hooks_factory-", Strings.toString(block.chainid), ".json");
        vm.writeJson(json, filename);
    }
}
