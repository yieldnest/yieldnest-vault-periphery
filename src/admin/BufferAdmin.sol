// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title BufferAdmin
/// @notice Contract for managing buffer addresses for a Vault, with role-based access control.
/// @dev Only addresses with BUFFER_ADMIN_ROLE can add, remove, or reorder buffers.
contract BufferAdmin is AccessControl {
    /// @notice Thrown when trying to add a buffer that already exists.
    error BufferAlreadyAdded(address buffer);
    /// @notice Thrown when the buffer is not a valid asset in the vault.
    error NotVaultAsset(address buffer);
    /// @notice Thrown when the buffer does not match the ERC4626 asset.
    error ERC4626AssetMismatch(address buffer);
    /// @notice Thrown when a buffer is not found in the mapping.
    error BufferNotFound(address buffer);
    /// @notice Thrown when a buffer is not found in the array.
    error BufferNotFoundInArray(address buffer);
    /// @notice Thrown when the input length does not match the expected length.
    error LengthMismatch(uint256 expected, uint256 actual);
    /// @notice Thrown when a duplicate buffer is detected.
    error DuplicateBuffer(address buffer);
    /// @notice Thrown when a buffer is not in the list.
    error BufferNotInList(address buffer);
    /// @notice Thrown when setting the buffer fails.
    error SetBufferFailed();

    IVault public vault;
    address[] public buffers;
    mapping(address => bool) public isBuffer;

    /// @notice Role identifier for buffer admins.
    bytes32 public constant BUFFER_ADMIN_ROLE = keccak256("BUFFER_ADMIN_ROLE");

    /// @notice Initializes the BufferAdmin contract.
    /// @param _vault The address of the vault contract.
    /// @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
    /// @param bufferAdmin The address to be granted BUFFER_ADMIN_ROLE.
    constructor(address _vault, address defaultAdmin, address bufferAdmin) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_ADMIN_ROLE, bufferAdmin);
    }

    /// @notice Add new buffer addresses to the list.
    /// @dev Only callable by BUFFER_ADMIN_ROLE. Checks for duplicates and asset validity.
    /// @param _buffers Array of buffer addresses to add.
    function addBuffers(address[] memory _buffers) public onlyRole(BUFFER_ADMIN_ROLE) {
        // Check for duplicates in the input array
        for (uint256 i = 0; i < _buffers.length; i++) {
            for (uint256 j = i + 1; j < _buffers.length; j++) {
                if (_buffers[i] == _buffers[j]) revert DuplicateBuffer(_buffers[i]);
            }
        }
        for (uint256 i = 0; i < _buffers.length; i++) {
            address buf = _buffers[i];
            if (_isInBuffers(buf)) revert BufferAlreadyAdded(buf);
            if (!_isVaultAsset(buf)) revert NotVaultAsset(buf);
            if (!_isERC4626Asset(buf)) revert ERC4626AssetMismatch(buf);
            buffers.push(buf);
            isBuffer[buf] = true;
        }
    }

    /// @notice Remove buffer addresses from the list.
    /// @dev Only callable by BUFFER_ADMIN_ROLE.
    /// @param _buffers Array of buffer addresses to remove.
    function removeBuffers(address[] memory _buffers) public onlyRole(BUFFER_ADMIN_ROLE) {
        for (uint256 i = 0; i < _buffers.length; i++) {
            _removeBuffer(_buffers[i]);
        }
    }

    /// @notice Internal function to remove a buffer address.
    /// @dev Reverts if the buffer is not found.
    /// @param _buffer The buffer address to remove.
    function _removeBuffer(address _buffer) internal {
        if (!isBuffer[_buffer]) revert BufferNotFound(_buffer);
        uint256 len = buffers.length;
        for (uint256 i = 0; i < len; i++) {
            if (buffers[i] == _buffer) {
                buffers[i] = buffers[len - 1];
                buffers.pop();
                isBuffer[_buffer] = false;
                return;
            }
        }
        revert BufferNotFoundInArray(_buffer);
    }

    /// @notice Update the order of buffer addresses.
    /// @dev Only callable by BUFFER_ADMIN_ROLE. Checks for set equality and duplicates.
    /// @param _buffers The new ordered array of buffer addresses.
    function updateBufferOrder(address[] memory _buffers) public onlyRole(BUFFER_ADMIN_ROLE) {
        if (_buffers.length != buffers.length) revert LengthMismatch(buffers.length, _buffers.length);
        // Check that the set is the same
        for (uint256 i = 0; i < _buffers.length; i++) {
            if (!isBuffer[_buffers[i]]) revert BufferNotFound(_buffers[i]);
        }
        // Check for duplicates
        for (uint256 i = 0; i < _buffers.length; i++) {
            for (uint256 j = i + 1; j < _buffers.length; j++) {
                if (_buffers[i] == _buffers[j]) revert DuplicateBuffer(_buffers[i]);
            }
        }
        buffers = _buffers;
    }

    /// @notice Set the current buffer in the vault.
    /// @dev Only callable by BUFFER_ADMIN_ROLE. Checks buffer validity.
    /// @param _buffer The buffer address to set as current.
    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_ADMIN_ROLE) {
        if (!isBuffer[_buffer]) revert BufferNotInList(_buffer);

        // Check again; buffer may be removed as an asset in the meantime.
        if (!_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);
        vault.setBuffer(_buffer);
    }

    // --- Internal helpers ---

    /// @notice Checks if an address is in the buffer list.
    /// @param _buffer The address to check.
    /// @return True if the address is a buffer, false otherwise.
    function _isInBuffers(address _buffer) public view returns (bool) {
        return isBuffer[_buffer];
    }

    /// @notice Checks if an address is a valid vault asset.
    /// @param _buffer The address to check.
    /// @return True if the address is a valid asset, false otherwise.
    function _isVaultAsset(address _buffer) public view returns (bool) {
        return vault.getAsset(_buffer).decimals > 0;
    }

    /// @notice Checks if an address is a valid ERC4626 asset for the vault.
    /// @param _buffer The address to check.
    /// @return True if the address is a valid ERC4626 asset, false otherwise.
    function _isERC4626Asset(address _buffer) public view returns (bool) {
        // Use IVault and IERC4626 interfaces
        try IERC4626(_buffer).asset() returns (address bufferAsset) {
            return bufferAsset == vault.asset();
        } catch {
            return false;
        }
    }
}
