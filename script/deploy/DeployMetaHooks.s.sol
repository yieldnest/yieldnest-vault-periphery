// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {FeeHooks, IHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployMetaHooks is Script {
    uint256 public performanceFee = 0.001 ether;
    address public performanceFeeRecipient = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183;

    uint256 public maxDecreaseRatio = 0.0005 ether; // 0.05%
    uint256 public maxIncreaseRatio = 0.002 ether; // 0.2%
    uint256 public maxTotalSupplyIncreaseRatio = 0.0005 ether; // 0.05%

    address public deployer;

    address public vault;
    MetaHooks public metaHooks;
    FeeHooks public feeHooks;
    ProcessAccountingGuardHook public processAccountingGuardHook;
    MainnetActors public L1Actors;

    function run() public virtual {
        L1Actors = new MainnetActors();

        deployer = msg.sender;

        vm.startBroadcast();

        vault = MC.YNETHX;

        // address vault_, address defaultAdmin, address hookManager)
        metaHooks = new MetaHooks(address(vault), L1Actors.ADMIN(), L1Actors.HOOKS_MANAGER());

        feeHooks = new FeeHooks(
            address(metaHooks),
            L1Actors.ADMIN(), // owner
            performanceFee, // performanceFee (0.1%)
            performanceFeeRecipient,
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: true // only afterProcessAccounting is true
            })
        );

        processAccountingGuardHook = new ProcessAccountingGuardHook(
            address(metaHooks),
            L1Actors.ADMIN(),
            maxDecreaseRatio, // maxDecreaseRatio (0.05%)
            maxIncreaseRatio, // maxIncreaseRatio (0.2%)
            maxTotalSupplyIncreaseRatio, // maxTotalSupplyIncreaseRatio (0.05%)
            performanceFee
        );

        vm.stopBroadcast();

        // Store vault implementation in JSON file
        saveDeployment();
    }

    function label() public view returns (string memory) {
        return string.concat("metaHooks-ynETHx-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "metaHooks", address(metaHooks));
        vm.serializeAddress(label(), "feeHooks", address(feeHooks));
        vm.serializeAddress(label(), "processAccountingGuardHook", address(processAccountingGuardHook));
        vm.serializeAddress(label(), "vault", address(vault));
        vm.serializeAddress(label(), "admin", L1Actors.ADMIN());
        vm.serializeAddress(label(), "hooksManager", L1Actors.HOOKS_MANAGER());
        vm.serializeAddress(label(), "performanceFeeRecipient", performanceFeeRecipient);

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }
}
