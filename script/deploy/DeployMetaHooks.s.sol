// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {FeeHooks, IHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetContracts as MC} from "lib/yieldnest-vault/script/Contracts.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {BaseScript} from "script/deploy/BaseScript.sol";

contract DeployMetaHooks is BaseScript {
    uint256 public performanceFee = 0.1 ether; // 10%

    uint256 public maxDecreaseRatio = 0.0005 ether; // 0.05%
    uint256 public maxIncreaseRatio = 0.002 ether; // 0.2%
    uint256 public maxTotalSupplyIncreaseRatio = 0.0005 ether; // 0.05%, 25% of maxIncreaseRatio

    function run() public virtual {
        actors = new MainnetActors();

        performanceFeeRecipient = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183;

        deployer = msg.sender;

        vm.startBroadcast();

        vault = MC.YNETHX;

        // Deploy MetaHooks with deployer as the initial owner (defaultAdmin and hookManager)
        metaHooks = new MetaHooks(address(vault), deployer, deployer);

        // Deploy hooks with ADMIN as the owner (feeHooks does not need deployer as owner)
        feeHooks = new FeeHooks(
            address(metaHooks),
            actors.ADMIN(), // owner is ADMIN
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
            actors.ADMIN(), // owner is ADMIN
            maxDecreaseRatio,
            maxIncreaseRatio,
            maxTotalSupplyIncreaseRatio,
            performanceFee
        );

        // Set up hooks array for MetaHooks
        IHooks[] memory hooks = new IHooks[](2);
        hooks[0] = IHooks(address(feeHooks));
        hooks[1] = IHooks(address(processAccountingGuardHook));

        // Set hooks as deployer
        metaHooks.setHooks(hooks);

        // Give ADMIN the roles and renounce from deployer
        bytes32 DEFAULT_ADMIN_ROLE = metaHooks.DEFAULT_ADMIN_ROLE();
        bytes32 HOOK_MANAGER_ROLE = metaHooks.HOOK_MANAGER_ROLE();

        // Grant roles to ADMIN
        metaHooks.grantRole(DEFAULT_ADMIN_ROLE, actors.ADMIN());
        metaHooks.grantRole(HOOK_MANAGER_ROLE, actors.HOOKS_MANAGER());

        // Renounce roles from deployer
        metaHooks.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
        metaHooks.renounceRole(HOOK_MANAGER_ROLE, deployer);

        vm.stopBroadcast();

        // Store vault implementation in JSON file
        saveDeployment();
    }

    function label() public view override returns (string memory) {
        return string.concat("metaHooks-ynETHx-", Strings.toString(block.chainid));
    }
}
