// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {WithdrawalRequestManager} from "src/withdrawal/WithdrawalRequestManager.sol";

contract DeployWithdrawalRequestManager is Script {
    uint256 public constant MINIMUM_AMOUNT_TO_LOCK = 10 ether;

    MainnetActors public actors;
    WithdrawalRequestManager public implementation;
    WithdrawalRequestManager public withdrawalRequestManager;
    ERC1967Proxy public proxy;

    address public deployer;
    address public token;
    address public defaultAdmin;
    address public fulfiller;
    address public configurationManager;
    address public pauser;

    function run() public {
        actors = new MainnetActors();

        deployer = msg.sender;
        token = MC.YNETHX;
        defaultAdmin = actors.ADMIN();
        fulfiller = actors.ADMIN();
        configurationManager = actors.ADMIN();
        pauser = actors.PAUSER();

        vm.startBroadcast();

        implementation = new WithdrawalRequestManager();
        proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                WithdrawalRequestManager.initialize,
                (token, defaultAdmin, fulfiller, configurationManager, pauser, MINIMUM_AMOUNT_TO_LOCK)
            )
        );
        withdrawalRequestManager = WithdrawalRequestManager(address(proxy));

        vm.stopBroadcast();

        saveDeployment();
    }

    function label() public view returns (string memory) {
        return string.concat("withdrawalRequestManager-ynETHx-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "implementation", address(implementation));
        vm.serializeAddress(label(), "proxy", address(proxy));
        vm.serializeAddress(label(), "withdrawalRequestManager", address(withdrawalRequestManager));
        vm.serializeAddress(label(), "token", token);
        vm.serializeUint(label(), "minimumAmountToLock", MINIMUM_AMOUNT_TO_LOCK);
        vm.serializeAddress(label(), "defaultAdmin", defaultAdmin);
        vm.serializeAddress(label(), "fulfiller", fulfiller);
        vm.serializeAddress(label(), "configurationManager", configurationManager);
        vm.serializeAddress(label(), "pauser", pauser);

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }
}
