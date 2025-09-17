// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IOracleTaskHook
 * @notice Interface for Oracle Task Hook connector
 * @dev Defines the interface for the Oracle Task Hook that connects EigenLayer tasks with Oracle operations
 */
interface IOracleTaskHook {
    
    /*//////////////////////////////////////////////////////////////
                            TASK TYPES
    //////////////////////////////////////////////////////////////*/
    
    function TASK_TYPE_PRICE_ATTESTATION() external pure returns (bytes32);
    function TASK_TYPE_CONSENSUS_VALIDATION() external pure returns (bytes32);
    function TASK_TYPE_MANIPULATION_CHALLENGE() external pure returns (bytes32);
    function TASK_TYPE_OPERATOR_SLASHING() external pure returns (bytes32);
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the main Oracle Hook address
     * @return The address of the main Oracle logic contract
     */
    function getOracleHook() external view returns (address);
    
    /**
     * @notice Get fee for a specific task type
     * @param taskType The task type
     * @return The fee for that task type
     */
    function getTaskTypeFee(bytes32 taskType) external view returns (uint96);
    
    /**
     * @notice Get all supported task types
     * @return Array of supported task type hashes
     */
    function getSupportedTaskTypes() external pure returns (bytes32[] memory);
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update fee for a task type (only service manager)
     * @param taskType The task type to update
     * @param newFee The new fee amount
     */
    function updateTaskTypeFee(bytes32 taskType, uint96 newFee) external;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TaskValidated(bytes32 indexed taskHash, bytes32 taskType, address caller);
    event TaskCreated(bytes32 indexed taskHash, bytes32 taskType);
    event TaskResultSubmitted(bytes32 indexed taskHash, address caller);
    event TaskFeeCalculated(bytes32 indexed taskHash, bytes32 taskType, uint96 fee);
    event OracleHookUpdated(address indexed oldHook, address indexed newHook);
}