// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title BaseBeaconMaker
/// @notice Shared beacon proxy factory and implementation upgrade manager.
contract BaseBeaconMaker is Initializable, AccessControlUpgradeable {
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    /// @custom:storage-location erc7201:yieldnest.storage.base_beacon_maker
    struct BaseBeaconMakerStorage {
        UpgradeableBeacon beacon;
    }

    error ZeroAddress();

    event ProxyCreated(address indexed proxy);
    event ImplementationUpgraded(address indexed previousImplementation, address indexed newImplementation);

    // keccak256(abi.encode(uint256(keccak256("yieldnest.storage.base_beacon_maker")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseBeaconMakerStorageLocation =
        0xe4e9b5977ec8c1e8a7f1ef970796fa212a6082e4e0e770d85816b6d74cca3a00;

    function _getBaseBeaconMakerStorage() private pure returns (BaseBeaconMakerStorage storage $) {
        assembly {
            $.slot := BaseBeaconMakerStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address implementation_, address defaultAdmin, address creator, address implementationManager)
        external
        initializer
    {
        if (
            implementation_ == address(0) || defaultAdmin == address(0) || creator == address(0)
                || implementationManager == address(0)
        ) {
            revert ZeroAddress();
        }

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(CREATOR_ROLE, creator);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, implementationManager);

        _getBaseBeaconMakerStorage().beacon = new UpgradeableBeacon(implementation_, address(this));
    }

    /// @notice Creates a new beacon proxy initialized with arbitrary call data.
    /// @param initData Initialization call data for the implementation.
    /// @return proxy New proxy address.
    function create(bytes calldata initData) external onlyRole(CREATOR_ROLE) returns (address proxy) {
        proxy = address(new BeaconProxy(address(_getBaseBeaconMakerStorage().beacon), initData));

        emit ProxyCreated(proxy);
    }

    /// @notice Upgrades the implementation used by all proxies created by this maker.
    /// @param newImplementation New implementation address.
    function upgradeImplementation(address newImplementation) external onlyRole(IMPLEMENTATION_MANAGER_ROLE) {
        if (newImplementation == address(0)) revert ZeroAddress();

        UpgradeableBeacon beacon_ = _getBaseBeaconMakerStorage().beacon;
        address previousImplementation = beacon_.implementation();
        beacon_.upgradeTo(newImplementation);

        emit ImplementationUpgraded(previousImplementation, newImplementation);
    }

    /// @notice Returns the beacon used by created proxies.
    /// @return The beacon address.
    function beacon() public view returns (address) {
        return address(_getBaseBeaconMakerStorage().beacon);
    }

    /// @notice Returns the current implementation.
    /// @return The current implementation address.
    function implementation() public view returns (address) {
        return _getBaseBeaconMakerStorage().beacon.implementation();
    }
}
