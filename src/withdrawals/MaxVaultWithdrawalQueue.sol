// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract WithdrawalQueue is AccessControlUpgradeable {

    struct WithdrawalRequest {
        address requester;
        uint256 amount;
        uint256 timestamp;
        bool fulfilled;
    }

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bool) public whitelist;
    uint256 public nextRequestId;
    uint256 public lastFulfilledId;
    uint256 public partiallyFulfilledAmount;
    IVault public immutable vault;

    /// @notice Role identifier for processors who can call vault withdraw
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    event WithdrawalRequested(uint256 indexed requestId, address indexed requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed requester, uint256 amount);

    error RequesterNotWhitelisted(address requester);

    constructor(IVault _vault) {
        vault = _vault;
    }

    function setWhitelist(address requester, bool whitelisted) external onlyRole(WHITELIST_MANAGER_ROLE) {
        whitelist[requester] = whitelisted;
    }

    function requestWithdrawal(uint256 amount) external returns (uint256 requestId) {
        if (!whitelist[msg.sender]) {
            revert RequesterNotWhitelisted(msg.sender);
        }
        
        requestId = nextRequestId++;
        
        withdrawalRequests[requestId] = WithdrawalRequest({
            requester: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            fulfilled: false
        });

        emit WithdrawalRequested(requestId, msg.sender, amount);
    }

    function claimWithdrawal(uint256 requestId) external {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        
        require(request.requester == msg.sender, "Not your request");
        require(!request.fulfilled, "Already fulfilled");
        
        request.fulfilled = true;
        
        // Transfer the underlying token (assumes underlying is available)
        IERC20(vault.asset()).transfer(msg.sender, request.amount);
        
        emit WithdrawalClaimed(requestId, msg.sender, request.amount);
    }

    /// @notice Admin function to withdraw from vault when withdrawal queue has balance
    /// @param amount The amount to withdraw
    function processVaultWithdrawal(uint256 amount) external onlyRole(PROCESSOR_ROLE) {
        uint256 balanceBefore = IERC20(vault.asset()).balanceOf(address(this));
        vault.withdraw(amount, address(this), address(this));
        uint256 actualWithdrawn = IERC20(vault.asset()).balanceOf(address(this)) - balanceBefore;
        
        uint256 remainingToProcess = actualWithdrawn;
        uint256 currentRequestId = lastFulfilledId + 1;
        
        // Process requests starting from the next unfulfilled request
        while (remainingToProcess > 0 && currentRequestId < nextRequestId) {
            WithdrawalRequest storage request = withdrawalRequests[currentRequestId];
            
            if (!request.fulfilled) {
                uint256 neededForCurrentRequest = request.amount - partiallyFulfilledAmount;
                
                if (remainingToProcess >= neededForCurrentRequest) {
                    // Can fully fulfill this request
                    remainingToProcess -= neededForCurrentRequest;
                    request.fulfilled = true;
                    lastFulfilledId = currentRequestId;
                    partiallyFulfilledAmount = 0;
                } else {
                    // Partially fulfill this request
                    partiallyFulfilledAmount += remainingToProcess;
                    remainingToProcess = 0;
                }
            }
            
            currentRequestId++;
        }
    }
}
