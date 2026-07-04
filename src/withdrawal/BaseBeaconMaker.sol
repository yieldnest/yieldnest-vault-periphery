// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title BaseBeaconMaker
/// @notice Shared beacon proxy factory and implementation upgrade manager.
contract BaseBeaconMaker is AccessControl {
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    UpgradeableBeacon private immutable _beacon;

    error ZeroAddress();

    event ProxyCreated(address indexed proxy);
    event ImplementationUpgraded(address indexed implementation);

    constructor(address implementation_, address defaultAdmin, address creator, address implementationManager) {
        if (
            implementation_ == address(0) || defaultAdmin == address(0) || creator == address(0)
                || implementationManager == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(CREATOR_ROLE, creator);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, implementationManager);

        _beacon = new UpgradeableBeacon(implementation_, address(this));
    }

    /// @notice Creates a new beacon proxy initialized with arbitrary call data.
    /// @param initData Initialization call data for the implementation.
    /// @return proxy New proxy address.
    function create(bytes calldata initData) external onlyRole(CREATOR_ROLE) returns (address proxy) {
        proxy = address(new BeaconProxy(address(_beacon), initData));

        emit ProxyCreated(proxy);
    }

    /// @notice Upgrades the implementation used by all proxies created by this maker.
    /// @param newImplementation New implementation address.
    function upgradeImplementation(address newImplementation) external onlyRole(IMPLEMENTATION_MANAGER_ROLE) {
        if (newImplementation == address(0)) revert ZeroAddress();

        _beacon.upgradeTo(newImplementation);

        emit ImplementationUpgraded(newImplementation);
    }

    /// @notice Returns the beacon used by created proxies.
    /// @return The beacon address.
    function beacon() public view returns (address) {
        return address(_beacon);
    }

    /// @notice Returns the current implementation.
    /// @return The current implementation address.
    function implementation() public view returns (address) {
        return _beacon.implementation();
    }
}
