// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSTaskHook} from "@eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {IOracleTaskHook} from "../interfaces/IOracleTaskHook.sol";

/**
 * @title OracleTaskHook
 * @notice L2 task hook that interfaces between EigenLayer task system and main Oracle Hook
 * @dev This is a CONNECTOR contract that:
 * - Validates task parameters for Oracle operations (price attestations)
 * - Calculates fees for different task types
 * - Interfaces with the main Oracle Hook contract (deployed separately)
 * - Does NOT contain Oracle business logic itself
 */
contract OracleTaskHook is IAVSTaskHook, IOracleTaskHook {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the main Oracle Hook contract
    address public immutable oracleHook;
    
    /// @notice Address of the L1 service manager
    address public immutable serviceManager;
    
    /// @notice Task type constants for Oracle operations
    bytes32 public constant TASK_TYPE_PRICE_ATTESTATION = keccak256("PRICE_ATTESTATION");
    bytes32 public constant TASK_TYPE_CONSENSUS_VALIDATION = keccak256("CONSENSUS_VALIDATION");
    bytes32 public constant TASK_TYPE_MANIPULATION_CHALLENGE = keccak256("MANIPULATION_CHALLENGE");
    bytes32 public constant TASK_TYPE_OPERATOR_SLASHING = keccak256("OPERATOR_SLASHING");
    
    /// @notice Fee structure for different task types
    mapping(bytes32 => uint96) public taskTypeFees;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TaskValidated(bytes32 indexed taskHash, bytes32 taskType, address caller);
    event TaskCreated(bytes32 indexed taskHash, bytes32 taskType);
    event TaskResultSubmitted(bytes32 indexed taskHash, address caller);
    event TaskFeeCalculated(bytes32 indexed taskHash, bytes32 taskType, uint96 fee);
    event OracleHookUpdated(address indexed oldHook, address indexed newHook);
    
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyServiceManager() {
        require(msg.sender == serviceManager, "Only service manager can call");
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @param _oracleHook Address of the main Oracle Hook contract
     * @param _serviceManager Address of the L1 service manager
     */
    constructor(address _oracleHook, address _serviceManager) {
        require(_oracleHook != address(0), "Invalid Oracle hook");
        require(_serviceManager != address(0), "Invalid service manager");
        
        oracleHook = _oracleHook;
        serviceManager = _serviceManager;
        
        // Initialize default fees (in wei)
        taskTypeFees[TASK_TYPE_PRICE_ATTESTATION] = 0.001 ether;        // 0.001 ETH
        taskTypeFees[TASK_TYPE_CONSENSUS_VALIDATION] = 0.002 ether;     // 0.002 ETH
        taskTypeFees[TASK_TYPE_MANIPULATION_CHALLENGE] = 0.005 ether;   // 0.005 ETH
        taskTypeFees[TASK_TYPE_OPERATOR_SLASHING] = 0.01 ether;         // 0.01 ETH
    }
    
    /*//////////////////////////////////////////////////////////////
                            IAVSTaskHook IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate task parameters before task creation
     * @param caller The address creating the task
     * @param taskParams The task parameters
     */
    function validatePreTaskCreation(
        address caller,
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override {
        // Extract task type from payload
        bytes32 taskType = _extractTaskType(taskParams.payload);
        
        // Validate task type is supported
        require(_isValidTaskType(taskType), "Unsupported task type");
        
        // Validate caller permissions (could check with service manager)
        require(caller != address(0), "Invalid caller");
        
        // Additional Oracle-specific validations based on task type
        if (taskType == TASK_TYPE_PRICE_ATTESTATION) {
            _validatePriceAttestationTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_CONSENSUS_VALIDATION) {
            _validateConsensusValidationTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_MANIPULATION_CHALLENGE) {
            _validateManipulationChallengeTask(taskParams.payload);
        } else if (taskType == TASK_TYPE_OPERATOR_SLASHING) {
            _validateOperatorSlashingTask(taskParams.payload);
        }
        
        emit TaskValidated(keccak256(abi.encode(taskParams)), taskType, caller);
    }
    
    /**
     * @notice Handle post-task creation logic
     * @param taskHash The hash of the created task
     */
    function handlePostTaskCreation(bytes32 taskHash) external override {
        // Could notify the main Oracle Hook about new tasks
        // For now, just emit an event
        emit TaskCreated(taskHash, bytes32(0)); // Task type would need to be stored/retrieved
    }
    
    /**
     * @notice Validate task result before submission
     * @param caller The address submitting the result
     * @param taskHash The task hash
     * @param cert The certificate (if any)
     * @param result The task result
     */
    function validatePreTaskResultSubmission(
        address caller,
        bytes32 taskHash,
        bytes memory cert,
        bytes memory result
    ) external view override {
        // Validate caller is authorized (could check with service manager)
        require(caller != address(0), "Invalid caller");
        
        // Validate result format based on task type
        require(result.length > 0, "Empty result");
        
        // Additional validation logic could be added here
        // For example, validate result format matches expected structure
    }
    
    /**
     * @notice Handle post-task result submission
     * @param caller The address that submitted the result
     * @param taskHash The task hash
     */
    function handlePostTaskResultSubmission(
        address caller,
        bytes32 taskHash
    ) external override {
        // Could trigger actions in the main Oracle Hook
        // For now, just emit an event
        emit TaskResultSubmitted(taskHash, caller);
    }
    
    /**
     * @notice Calculate fee for a task
     * @param taskParams The task parameters
     * @return The calculated fee in wei
     */
    function calculateTaskFee(
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override returns (uint96) {
        bytes32 taskType = _extractTaskType(taskParams.payload);
        uint96 fee = taskTypeFees[taskType];
        
        // Could add dynamic fee calculation based on task complexity
        // For now, return fixed fee based on task type
        return fee;
    }
    
    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Extract task type from payload
     * @param payload The task payload
     * @return The task type hash
     */
    function _extractTaskType(bytes memory payload) internal pure returns (bytes32) {
        if (payload.length < 32) return bytes32(0);
        
        // Assume first 32 bytes contain task type
        bytes32 taskType;
        assembly {
            taskType := mload(add(payload, 32))
        }
        return taskType;
    }
    
    /**
     * @notice Check if task type is valid
     * @param taskType The task type to check
     * @return Whether the task type is supported
     */
    function _isValidTaskType(bytes32 taskType) internal view returns (bool) {
        return taskType == TASK_TYPE_PRICE_ATTESTATION ||
               taskType == TASK_TYPE_CONSENSUS_VALIDATION ||
               taskType == TASK_TYPE_MANIPULATION_CHALLENGE ||
               taskType == TASK_TYPE_OPERATOR_SLASHING;
    }
    
    /**
     * @notice Validate price attestation task parameters
     * @param payload The task payload
     */
    function _validatePriceAttestationTask(bytes memory payload) internal pure {
        // Validate that payload contains required price attestation parameters
        require(payload.length >= 128, "Invalid price attestation task payload"); // 32 + 32 + 32 + 32 minimum
        // Could add more specific validation for pool ID, price, operator signature, etc.
    }
    
    /**
     * @notice Validate consensus validation task parameters
     * @param payload The task payload
     */
    function _validateConsensusValidationTask(bytes memory payload) internal pure {
        // Validate that payload contains required consensus validation parameters
        require(payload.length >= 96, "Invalid consensus validation payload"); // Minimum required fields
        // Could add validation for pool ID, consensus data, etc.
    }
    
    /**
     * @notice Validate manipulation challenge task parameters
     * @param payload The task payload
     */
    function _validateManipulationChallengeTask(bytes memory payload) internal pure {
        // Validate that payload contains required manipulation challenge parameters
        require(payload.length >= 160, "Invalid manipulation challenge payload"); // Challenge data requirements
        // Could add validation for suspect operator, evidence, etc.
    }
    
    /**
     * @notice Validate operator slashing task parameters
     * @param payload The task payload
     */
    function _validateOperatorSlashingTask(bytes memory payload) internal pure {
        // Validate that payload contains required operator slashing parameters
        require(payload.length >= 128, "Invalid operator slashing payload"); // Slashing requirements
        // Could add validation for operator address, slashing amount, etc.
    }
    
    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the main Oracle Hook address
     * @return The address of the main Oracle logic contract
     */
    function getOracleHook() external view returns (address) {
        return oracleHook;
    }
    
    /**
     * @notice Get fee for a specific task type
     * @param taskType The task type
     * @return The fee for that task type
     */
    function getTaskTypeFee(bytes32 taskType) external view returns (uint96) {
        return taskTypeFees[taskType];
    }
    
    /**
     * @notice Get all supported task types
     * @return Array of supported task type hashes
     */
    function getSupportedTaskTypes() external pure returns (bytes32[] memory) {
        bytes32[] memory types = new bytes32[](4);
        types[0] = TASK_TYPE_PRICE_ATTESTATION;
        types[1] = TASK_TYPE_CONSENSUS_VALIDATION;
        types[2] = TASK_TYPE_MANIPULATION_CHALLENGE;
        types[3] = TASK_TYPE_OPERATOR_SLASHING;
        return types;
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update fee for a task type (only service manager)
     * @param taskType The task type to update
     * @param newFee The new fee amount
     */
    function updateTaskTypeFee(bytes32 taskType, uint96 newFee) external onlyServiceManager {
        require(_isValidTaskType(taskType), "Invalid task type");
        taskTypeFees[taskType] = newFee;
    }
}