// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBag} from "src/interface/IBag.sol";
import {Bag} from "src/withdrawal/Bag.sol";
import {BeaconProxyFactory} from "src/withdrawal/BeaconProxyFactory.sol";

interface IBagV2 {
    function version2() external pure returns (string memory);
}

contract BagV2 is Bag {
    function version2() external pure returns (string memory) {
        return "v2";
    }
}

contract BeaconProxyFactoryTest is Test {
    BeaconProxyFactory implementation;
    BeaconProxyFactory maker;
    Bag bagImplementation;

    address admin = address(0xA11CE);
    address creator = address(0xC0FFEE);
    address implementationManager = address(0x1F);
    address owner = address(0xB0B);
    address other = address(0xCAFE);

    function setUp() public {
        implementation = new BeaconProxyFactory();
        bagImplementation = new Bag();
        maker = BeaconProxyFactory(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        BeaconProxyFactory.initialize,
                        (address(bagImplementation), admin, creator, implementationManager)
                    )
                )
            )
        );
    }

    function testInitializeSetsRolesBeaconAndImplementation() public {
        assertTrue(maker.hasRole(maker.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(maker.hasRole(maker.CREATOR_ROLE(), creator));
        assertTrue(maker.hasRole(maker.IMPLEMENTATION_MANAGER_ROLE(), implementationManager));
        assertFalse(maker.hasRole(maker.DEFAULT_ADMIN_ROLE(), creator));
        assertFalse(maker.hasRole(maker.CREATOR_ROLE(), admin));
        assertFalse(maker.hasRole(maker.IMPLEMENTATION_MANAGER_ROLE(), admin));
        assertTrue(maker.beacon() != address(0));
        assertEq(maker.implementation(), address(bagImplementation));
    }

    function testInitializeRevertsForZeroImplementation() public {
        vm.expectRevert(BeaconProxyFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(BeaconProxyFactory.initialize, (address(0), admin, creator, implementationManager))
        );
    }

    function testInitializeRevertsForZeroAdmin() public {
        vm.expectRevert(BeaconProxyFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                BeaconProxyFactory.initialize, (address(bagImplementation), address(0), creator, implementationManager)
            )
        );
    }

    function testInitializeRevertsForZeroCreator() public {
        vm.expectRevert(BeaconProxyFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                BeaconProxyFactory.initialize, (address(bagImplementation), admin, address(0), implementationManager)
            )
        );
    }

    function testInitializeRevertsForZeroImplementationManager() public {
        vm.expectRevert(BeaconProxyFactory.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(BeaconProxyFactory.initialize, (address(bagImplementation), admin, creator, address(0)))
        );
    }

    function testImplementationCannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(bagImplementation), admin, creator, implementationManager);
    }

    function testProxyCannotBeInitializedTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        maker.initialize(address(bagImplementation), admin, creator, implementationManager);
    }

    function testCreateDeploysBeaconProxyAndInitializesIt() public {
        vm.expectEmit(false, false, false, false, address(maker));
        emit BeaconProxyFactory.ProxyCreated(address(0));

        vm.prank(creator);
        address proxy = maker.create(abi.encodeCall(IBag.initialize, (owner, 9)));

        assertTrue(proxy != address(0));
        assertEq(IBag(proxy).ownerOf(IBag(proxy).TOKEN_ID()), owner);
        assertEq(IBag(proxy).name(), "YieldNest Withdrawal Bag #9");
        assertEq(IBag(proxy).symbol(), "ynBAG-9");
        assertEq(IBag(proxy).id(), 9);
        assertEq(IBag(proxy).VERSION(), "0.1.0");
    }

    function testCreateCanDeployUninitializedProxyWithEmptyData() public {
        vm.prank(creator);
        address proxy = maker.create("");

        vm.expectRevert();
        IBag(proxy).ownerOf(1);

        IBag(proxy).initialize(owner, 10);

        assertEq(IBag(proxy).ownerOf(IBag(proxy).TOKEN_ID()), owner);
        assertEq(IBag(proxy).name(), "YieldNest Withdrawal Bag #10");
        assertEq(IBag(proxy).id(), 10);
    }

    function testCreateRevertsForUnauthorizedCreator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, other, maker.CREATOR_ROLE()
            )
        );
        vm.prank(other);
        maker.create(abi.encodeCall(IBag.initialize, (owner, 9)));
    }

    function testCreateBubblesInitializationRevert() public {
        vm.expectRevert(IBag.ZeroAddress.selector);
        vm.prank(creator);
        maker.create(abi.encodeCall(IBag.initialize, (address(0), 9)));
    }

    function testUpgradeImplementationUpdatesBeaconAndEmitsPreviousImplementation() public {
        BagV2 newImplementation = new BagV2();

        vm.expectEmit(true, true, true, true, address(maker));
        emit BeaconProxyFactory.ImplementationUpgraded(address(bagImplementation), address(newImplementation));

        vm.prank(implementationManager);
        maker.upgradeImplementation(address(newImplementation));

        assertEq(maker.implementation(), address(newImplementation));
    }

    function testUpgradeImplementationAffectsExistingAndNewProxies() public {
        vm.prank(creator);
        address existingProxy = maker.create(abi.encodeCall(IBag.initialize, (owner, 9)));

        BagV2 newImplementation = new BagV2();

        vm.prank(implementationManager);
        maker.upgradeImplementation(address(newImplementation));

        assertEq(IBagV2(existingProxy).version2(), "v2");
        assertEq(IBag(existingProxy).ownerOf(IBag(existingProxy).TOKEN_ID()), owner);

        vm.prank(creator);
        address newProxy = maker.create(abi.encodeCall(IBag.initialize, (other, 10)));

        assertEq(IBagV2(newProxy).version2(), "v2");
        assertEq(IBag(newProxy).ownerOf(IBag(newProxy).TOKEN_ID()), other);
    }

    function testUpgradeImplementationRevertsForUnauthorizedManager() public {
        BagV2 newImplementation = new BagV2();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, other, maker.IMPLEMENTATION_MANAGER_ROLE()
            )
        );
        vm.prank(other);
        maker.upgradeImplementation(address(newImplementation));
    }

    function testUpgradeImplementationRevertsForZeroImplementation() public {
        vm.expectRevert(BeaconProxyFactory.ZeroAddress.selector);
        vm.prank(implementationManager);
        maker.upgradeImplementation(address(0));
    }

    function testAdminCanGrantCreatorRole() public {
        address newCreator = address(0xD00D);
        bytes32 creatorRole = maker.CREATOR_ROLE();

        vm.prank(admin);
        maker.grantRole(creatorRole, newCreator);

        vm.prank(newCreator);
        address proxy = maker.create(abi.encodeCall(IBag.initialize, (owner, 11)));

        assertEq(IBag(proxy).ownerOf(IBag(proxy).TOKEN_ID()), owner);
    }

    function testNonAdminCannotGrantRoles() public {
        address newCreator = address(0xD00D);
        bytes32 creatorRole = maker.CREATOR_ROLE();
        bytes32 defaultAdminRole = maker.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        vm.prank(other);
        maker.grantRole(creatorRole, newCreator);
    }
}
