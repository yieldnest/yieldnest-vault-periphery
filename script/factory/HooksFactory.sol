// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";

contract HooksFactory {
    event MetaHooksCreated(address indexed metaHooks, address indexed vault, address owner, address hookManager);

    function createMetaHooks(address vault, address owner, address hookManager, IHooks[] memory hooks)
        public
        returns (MetaHooks)
    {
        address deployer = address(this);
        MetaHooks metaHooks = new MetaHooks(vault, deployer, deployer);
        // Set hooks as deployer
        metaHooks.setHooks(hooks);

        // Give ADMIN the roles and renounce from deployer
        bytes32 DEFAULT_ADMIN_ROLE = metaHooks.DEFAULT_ADMIN_ROLE();
        bytes32 HOOK_MANAGER_ROLE = metaHooks.HOOK_MANAGER_ROLE();

        // Grant roles to ADMIN
        metaHooks.grantRole(DEFAULT_ADMIN_ROLE, owner);
        metaHooks.grantRole(HOOK_MANAGER_ROLE, hookManager);
        // Renounce roles from deployer
        metaHooks.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
        metaHooks.renounceRole(HOOK_MANAGER_ROLE, deployer);

        emit MetaHooksCreated(address(metaHooks), vault, owner, hookManager);

        return metaHooks;
    }

    function createProcessAccountingGuardHook(
        address vault,
        address owner,
        uint256 maxDecreaseRatio,
        uint256 maxIncreaseRatio,
        uint256 maxTotalSupplyIncreaseRatio,
        uint256 performanceFee
    ) public returns (ProcessAccountingGuardHook) {
        return new ProcessAccountingGuardHook(
            vault, owner, maxDecreaseRatio, maxIncreaseRatio, maxTotalSupplyIncreaseRatio, performanceFee
        );
    }
}
