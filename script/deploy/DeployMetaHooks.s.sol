// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {FeeHooks, IHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";

contract DeployVault is Script {
    uint256 public performanceFee = 0.001 ether;
    // Univeral fee receiver for all vaults
    address public performanceFeeRecipient = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183;

    uint256 public maxDecreaseRatio = 0.0005 ether; // 0.05%
    uint256 public maxIncreaseRatio = 0.002 ether; // 0.2%
    uint256 public maxTotalSupplyIncreaseRatio = 0.0005 ether; // 0.05%

    function run() public virtual {
        MainnetActors L1Actors = new MainnetActors();

        vm.startBroadcast();

        address vault = MC.YNETHX;

        // address vault_, address defaultAdmin, address hookManager)
        MetaHooks metaHooks = new MetaHooks(address(vault), L1Actors.ADMIN(), L1Actors.HOOKS_MANAGER());

        FeeHooks feeHooks = new FeeHooks(
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

        ProcessAccountingGuardHook processAccountingGuardHook = new ProcessAccountingGuardHook(
            address(metaHooks),
            L1Actors.ADMIN(),
            maxDecreaseRatio, // maxDecreaseRatio (0.05%)
            maxIncreaseRatio, // maxIncreaseRatio (0.2%)
            maxTotalSupplyIncreaseRatio, // maxTotalSupplyIncreaseRatio (0.05%)
            performanceFee
        );

        vm.stopBroadcast();

        // Store vault implementation in JSON file
        string memory json = string.concat("{\"Vault\": \"", vm.toString(vault), "\"}");
        vm.writeFile(string.concat("deployments/vault-", vm.toString(block.chainid), ".json"), json);
    }
}
