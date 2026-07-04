// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Bag} from "src/withdrawal/Bag.sol";
import {BaseBeaconMaker} from "src/withdrawal/BaseBeaconMaker.sol";

/// @title BagMaker
/// @notice Creates upgradeable per-request Bag proxies and manages their beacon implementation.
contract BagMaker is BaseBeaconMaker {
    bytes32 public constant BAG_CREATOR_ROLE = CREATOR_ROLE;
    bytes32 public constant BAG_IMPLEMENTATION_MANAGER_ROLE = IMPLEMENTATION_MANAGER_ROLE;

    event BagCreated(address indexed owner, address indexed bag);

    constructor(address bagImplementation_, address defaultAdmin, address bagCreator, address bagImplementationManager)
        BaseBeaconMaker(bagImplementation_, defaultAdmin, bagCreator, bagImplementationManager)
    {}

    /// @notice Creates a new Bag proxy initialized for an owner.
    /// @param owner Initial owner of the Bag NFT.
    /// @return bag New Bag proxy address.
    function createBag(address owner) external onlyRole(BAG_CREATOR_ROLE) returns (address bag) {
        if (owner == address(0)) revert ZeroAddress();

        bag = _create(abi.encodeCall(Bag.initialize, (owner)));

        emit BagCreated(owner, bag);
    }
}
