// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract BufferAdmin is AccessControl {
    error BufferAlreadyAdded(address buffer);
    error NotVaultAsset(address buffer);
    error ERC4626AssetMismatch(address buffer);
    error BufferNotFound(address buffer);
    error BufferNotFoundInArray(address buffer);
    error LengthMismatch(uint256 expected, uint256 actual);
    error DuplicateBuffer(address buffer);
    error BufferNotInList(address buffer);
    error SetBufferFailed();

    IVault public vault;
    address[] public buffers;
    mapping(address => bool) public isBuffer;

    bytes32 public constant BUFFER_ADMIN_ROLE = keccak256("BUFFER_ADMIN_ROLE");

    constructor(address _vault, address defaultAdmin, address bufferAdmin) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BUFFER_ADMIN_ROLE, bufferAdmin);
    }

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

    function removeBuffers(address[] memory _buffers) public onlyRole(BUFFER_ADMIN_ROLE) {
        for (uint256 i = 0; i < _buffers.length; i++) {
            _removeBuffer(_buffers[i]);
        }
    }

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

    function setCurrentBuffer(address _buffer) public onlyRole(BUFFER_ADMIN_ROLE) {
        if (!isBuffer[_buffer]) revert BufferNotInList(_buffer);

        // check again; buffer may be removed as an asset in the meantime.
        if (!_isVaultAsset(_buffer)) revert NotVaultAsset(_buffer);
        vault.setBuffer(_buffer);
    }

    // --- Internal helpers ---

    function _isInBuffers(address _buffer) public view returns (bool) {
        return isBuffer[_buffer];
    }

    function _isVaultAsset(address _buffer) public view returns (bool) {
        return vault.getAsset(_buffer).decimals > 0;
    }

    function _isERC4626Asset(address _buffer) public view returns (bool) {
        // Use IVault and IERC4626 interfaces
        try IERC4626(_buffer).asset() returns (address bufferAsset) {
            return bufferAsset == vault.asset();
        } catch {
            return false;
        }
    }
}
