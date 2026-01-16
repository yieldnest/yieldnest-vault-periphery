// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {MetaHooks} from "src/hooks/MetaHooks.sol";
import {ProcessAccountingGuardHook} from "src/hooks/ProcessAccountingGuardHook.sol";
import {FeeHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";

contract HooksFactory {
    string public constant FACTORY_VERSION = "0.1.0";

    event MetaHooksCreated(address indexed metaHooks, address indexed vault, address owner, address hookManager);

    event ProcessAccountingGuardHookCreated(
        address indexed hook,
        address indexed vault,
        address indexed owner,
        uint256 maxDecreaseRatio,
        uint256 maxIncreaseRatio,
        uint256 maxTotalSupplyIncreaseRatio,
        uint256 performanceFee
    );

    event FeeHooksCreated(
        address indexed feeHooks,
        address indexed vault,
        address owner,
        uint256 performanceFee,
        address performanceFeeRecipient
    );

    function createMetaHooks(address vault, address owner, address hookManager, IHooks[] memory hooks)
        public
        returns (MetaHooks)
    {
        address deployer = address(this);
        MetaHooks metaHooks = new MetaHooks(vault, deployer, deployer);

        if (hooks.length > 0) {
            // Set hooks as deployer
            metaHooks.setHooks(hooks);
        }

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
        ProcessAccountingGuardHook hook = new ProcessAccountingGuardHook(
            vault, owner, maxDecreaseRatio, maxIncreaseRatio, maxTotalSupplyIncreaseRatio, performanceFee
        );
        emit ProcessAccountingGuardHookCreated(
            address(hook), vault, owner, maxDecreaseRatio, maxIncreaseRatio, maxTotalSupplyIncreaseRatio, performanceFee
        );
        return hook;
    }

    function createFeeHooks(address vault, address owner, uint256 performanceFee, address performanceFeeRecipient)
        public
        returns (FeeHooks)
    {
        FeeHooks feeHooks = new FeeHooks(
            vault,
            owner,
            performanceFee,
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
                afterProcessAccounting: true
            })
        );
        emit FeeHooksCreated(address(feeHooks), vault, owner, performanceFee, performanceFeeRecipient);
        return feeHooks;
    }
}
