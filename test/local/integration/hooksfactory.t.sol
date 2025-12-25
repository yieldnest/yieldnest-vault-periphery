// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "script/factory/HooksFactory.sol";
import "src/hooks/MetaHooks.sol";
import "src/hooks/ProcessAccountingGuardHook.sol";
import "lib/yieldnest-vault/src/interface/IHooks.sol";
import {MockNoOpHooks} from "lib/yieldnest-vault/test/unit/mocks/MockNoOpHooks.sol";
import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";

contract HooksFactoryIntegrationTest is BaseIntegrationTest {
    address public constant hookManager = address(0xF00D);
    HooksFactory public factory;

    function setUp() public override {
        super.setUp();
        factory = new HooksFactory();
    }

    function testCreateMetaHooks() public {
        // Use the proper mocks: MockNoOpHooks with vault address
        MockNoOpHooks mock1 = new MockNoOpHooks(vault);
        MockNoOpHooks mock2 = new MockNoOpHooks(vault);

        IHooks[] memory hooks = new IHooks[](2);
        hooks[0] = IHooks(address(mock1));
        hooks[1] = IHooks(address(mock2));

        MetaHooks metaHooks = factory.createMetaHooks(address(vault), owner, hookManager, hooks);

        assertEq(address(metaHooks.VAULT()), address(vault));
        // check roles
        assertTrue(metaHooks.hasRole(metaHooks.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(metaHooks.hasRole(metaHooks.HOOK_MANAGER_ROLE(), hookManager));

        // metaHooks renounced admin/manager from deployer (factory)
        assertFalse(metaHooks.hasRole(metaHooks.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(metaHooks.hasRole(metaHooks.HOOK_MANAGER_ROLE(), address(factory)));

        // hooks should be set
        assertEq(address(metaHooks.hooks(0)), address(mock1));
        assertEq(address(metaHooks.hooks(1)), address(mock2));
    }

    function testCreateProcessAccountingGuardHook() public {
        uint256 maxDecreaseRatio = 0.05e18;
        uint256 maxIncreaseRatio = 0.2e18;
        uint256 maxTotalSupplyIncreaseRatio = 0.01e18;
        uint256 performanceFee = 0.1e18;

        ProcessAccountingGuardHook hook = factory.createProcessAccountingGuardHook(
            address(vault), owner, maxDecreaseRatio, maxIncreaseRatio, maxTotalSupplyIncreaseRatio, performanceFee
        );

        assertEq(address(hook.VAULT()), address(vault));
        assertEq(hook.owner(), owner);
        assertEq(hook.maxTotalAssetsDecreaseRatio(), maxDecreaseRatio);
        assertEq(hook.maxTotalAssetsIncreaseRatio(), maxIncreaseRatio);
        assertEq(hook.maxTotalSupplyIncreaseRatio(), maxTotalSupplyIncreaseRatio);
        assertEq(hook.expectedPerformanceFee(), performanceFee);
    }
}
