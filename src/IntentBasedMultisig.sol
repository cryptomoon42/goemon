pragma solidity ^0.8.25;

/// @title Intent-Based Multisig Wallet
/// @notice A multisignature wallet that operates based on intents
contract IntentBasedMultisig {
    struct Intent {
        // address to call
        address to;
        // amount of ether to send
        uint256 value;
        // data to send
        bytes data;
        // number of approvals for the intent
        uint256 approvals;
        // whether the intent has been executed
        bool executed;
    }

    // mapping of intent id to intent
    mapping(uint256 intentId => Intent) public intents;
    // mapping of intent id to mapping of address to boolean indicating whether the address has approved the intent
    mapping(uint256 intentId => mapping(address approver => bool approved)) public hasApproved;
    // number of approvals required for an intent to be executed
    uint256 public requiredApprovals;
    // id of the next intent
    uint256 public nextIntentId;
    // mapping of address to boolean indicating whether the address is an owner
    mapping(address owner => bool isOwner) public isOwner;
    // number of owners
    uint256 public ownerCount;

    /// @notice Initializes the multisig wallet with owners and required approvals
    /// @dev Sets up the initial state of the contract
    /// @param _owners An array of addresses that will be the initial owners of the multisig
    /// @param _requiredApprovals The number of approvals required to execute an intent
    constructor(address[] memory _owners, uint256 _requiredApprovals) {
        // check if the owners array is not empty
        require(_owners.length > 0, "Owners required");
        // check if the required approvals is greater than 0 and less than or equal to the number of owners
        require(_requiredApprovals > 0 && _requiredApprovals <= _owners.length, "Invalid required approvals");
        // set the required approvals
        requiredApprovals = _requiredApprovals;
        // set the owner count
        ownerCount = _owners.length;
        // set the owner status as true for each owner
        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
    }

    /// @notice Updates the number of required approvals for executing an intent
    /// @dev This function can only be called by the multisig itself through an executed intent
    /// @param _requiredApprovals The new number of required approvals
    function updateRequiredApprovals(uint256 _requiredApprovals) public {
        // check if the new number of approvals is valid
        require(_requiredApprovals > 0 && _requiredApprovals <= ownerCount, "Invalid required approvals");
        // check if the caller is the contract itself
        // this function is only callable by the contract itself because it updates the contract's state
        require(msg.sender == address(this), "Only callable by contract");
        // update the number of approvals required
        requiredApprovals = _requiredApprovals;
    }

    /// @notice Removes an owner from the multisig wallet
    /// @dev This function can only be called by the multisig itself through an executed intent
    /// @param _owner The address of the owner to be removed
    function removeOwner(address _owner) public {
        // check if the caller is the contract itself
        // this function is only callable by the contract itself because it updates the contract's state
        require(msg.sender == address(this), "Only callable by contract");
        // check if the owner is already an owner or not
        require(isOwner[_owner], "Not an owner");
        // update the owner's status
        isOwner[_owner] = false;
        // decrement the owner count
        ownerCount--;
        // assert that the owner count is greater than or equal to the required approvals
        require(ownerCount >= requiredApprovals, "Required approvals cannot be greater than owner count");
    }

    /// @notice Adds a new owner to the multisig wallet
    /// @dev This function can only be called by the multisig itself through an executed intent
    /// @param _owner The address of the new owner to be added
    function addOwner(address _owner) public {
        // check if the caller is the contract itself
        // this function is only callable by the contract itself because it updates the contract's state
        require(msg.sender == address(this), "Only callable by contract");
        // check if the owner is already an owner or not
        require(!isOwner[_owner], "Already an owner");
        // update the owner's status
        isOwner[_owner] = true;
        // increment the owner count
        ownerCount++;
    }
    /// @notice Creates a new intent for the multisig to execute
    /// @dev This function generally proposes the intent but can execute it if requiredApprovals is 1
    /// @param _to The address that will receive the transaction
    /// @param _value The amount of Ether to send with the transaction
    /// @param _data The data payload of the transaction
    /// @return intentId The ID of the newly created intent

    function createIntent(address _to, uint256 _value, bytes memory _data) public returns (uint256 intentId) {
        // check if the caller is an owner
        require(isOwner[msg.sender], "Not an owner");
        // increment the intent id
        uint256 intentId = ++nextIntentId;
        // create the intent
        // approvals is initialized to 1 because the creator of the intent will approve it
        // executed is initialized to false
        intents[intentId] = Intent(_to, _value, _data, 1, false);
        // set the approval status for the intent and caller
        hasApproved[intentId][msg.sender] = true;
        // if the intent has enough approvals, execute the intent
        if (requiredApprovals == 1) {
            executeIntent(intentId);
        }
        // return the intent id
        return intentId;
    }

    /// @notice Approves an intent for execution
    /// @dev Can only be called by authorized signers of the multisig
    /// @param intentId The unique identifier of the intent to be approved
    function approveIntent(uint256 intentId) public {
        // check if the caller is an owner
        require(isOwner[msg.sender], "Not an owner");
        // check if the intent exists
        require(intentId <= nextIntentId, "Intent does not exist");
        // get the intent
        Intent storage intent = intents[intentId];
        // check if the intent has been executed
        require(!intent.executed, "Intent already executed");
        // check if the caller has already approved the intent
        require(!hasApproved[intentId][msg.sender], "Already approved");
        // update the approval status for the intent and caller
        hasApproved[intentId][msg.sender] = true;
        // increment the intent approvals
        uint256 intentApprovals = ++intent.approvals;

        // if the intent has enough approvals, execute the intent
        if (intentApprovals >= requiredApprovals) {
            executeIntent(intentId);
        }
    }

    /// @notice Executes a previously created intent with enough approvals
    /// @dev This function can only be called by anyone once the intent has enough approvals
    /// @param intentId The ID of the intent to be executed
    /// @return success A boolean indicating whether the execution was successful
    /// @return result The data returned by the executed transaction, if any
    function executeIntent(uint256 intentId) public returns (bool success, bytes memory result) {
        // get the intent
        Intent storage intent = intents[intentId];
        // check if the intent has been executed
        require(!intent.executed, "Intent already executed");
        // check if the intent has enough approvals
        require(intent.approvals >= requiredApprovals, "Not enough approvals");
        // following checks-effects-interaction pattern
        intent.executed = true;
        // execute the intent
        (success, result) = intent.to.call{ value: intent.value }(intent.data);
        // if the external call fails, mark the intent as not executed
        if (!success) {
            intent.executed = false;
        }
    }

    /// @notice Allows the contract to receive Ether
    /// @dev This function is automatically called when Ether is sent to the contract without data
    receive() external payable {
        // Function implementation (empty in this case)
    }
}
