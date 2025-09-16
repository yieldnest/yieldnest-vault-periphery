// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

library TStore {
    function store(bytes32 key, uint256 value) internal {
        assembly {
            tstore(key, value)
        }
    }

    function store(bytes32 key, bool value) internal {
        assembly {
            tstore(key, value)
        }
    }

    function loadUint256(bytes32 key) internal view returns (uint256 value) {
        assembly {
            value := tload(key)
        }
    }

    function loadBool(bytes32 key) internal view returns (bool value) {
        assembly {
            value := tload(key)
        }
    }

    function clear(bytes32 key) internal {
        assembly {
            tstore(key, 0)
        }
    }
}
