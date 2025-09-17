package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/Layr-Labs/hourglass-monorepo/ponos/pkg/performer/server"
	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"go.uber.org/zap"
)

// TaskType represents the different types of Oracle tasks
type TaskType string

const (
	TaskTypePriceAttestation       TaskType = "price_attestation"
	TaskTypeConsensusValidation    TaskType = "consensus_validation"
	TaskTypeManipulationChallenge  TaskType = "manipulation_challenge"
	TaskTypeOperatorSlashing       TaskType = "operator_slashing"
)

// TaskPayload represents the structure of task payload data
type TaskPayload struct {
	Type       TaskType               `json:"type"`
	Parameters map[string]interface{} `json:"parameters"`
}

// parseTaskPayload extracts and parses the task payload from TaskRequest
func parseTaskPayload(t *performerV1.TaskRequest) (*TaskPayload, error) {
	var payload TaskPayload
	if err := json.Unmarshal(t.Payload, &payload); err != nil {
		return nil, fmt.Errorf("failed to parse task payload: %w", err)
	}
	return &payload, nil
}

// OraclePerformer implements the Hourglass Performer interface for Oracle tasks.
// This offchain binary is run by Operators running the Hourglass Executor. It contains
// the business logic of the Oracle AVS and performs work based on tasks sent to it.
//
// The Hourglass Aggregator ingests tasks from the TaskMailbox and distributes work
// to Executors configured to run the Oracle Performer. Performers execute the work and
// return the result to the Executor where the result is signed and returned to the
// Aggregator to place in the outbox once the signing threshold is met.
type OraclePerformer struct {
	logger *zap.Logger
}

func NewOraclePerformer(logger *zap.Logger) *OraclePerformer {
	return &OraclePerformer{
		logger: logger,
	}
}

func (op *OraclePerformer) ValidateTask(t *performerV1.TaskRequest) error {
	op.logger.Sugar().Infow("Validating Oracle task",
		zap.Any("task", t),
	)

	// ------------------------------------------------------------------------
	// Oracle Task Validation Logic
	// ------------------------------------------------------------------------
	// Validate that the task request data is well-formed for Oracle operations
	
	if len(t.TaskId) == 0 {
		return fmt.Errorf("task ID cannot be empty")
	}

	if len(t.Payload) == 0 {
		return fmt.Errorf("task payload cannot be empty")
	}

	// Parse and validate task payload
	payload, err := parseTaskPayload(t)
	if err != nil {
		return fmt.Errorf("failed to parse task payload: %w", err)
	}

	// Validate task type specific requirements
	switch payload.Type {
	case TaskTypePriceAttestation:
		if err := op.validatePriceAttestationTask(payload); err != nil {
			return fmt.Errorf("price attestation validation failed: %w", err)
		}
	case TaskTypeConsensusValidation:
		if err := op.validateConsensusValidationTask(payload); err != nil {
			return fmt.Errorf("consensus validation failed: %w", err)
		}
	case TaskTypeManipulationChallenge:
		if err := op.validateManipulationChallengeTask(payload); err != nil {
			return fmt.Errorf("manipulation challenge validation failed: %w", err)
		}
	case TaskTypeOperatorSlashing:
		if err := op.validateOperatorSlashingTask(payload); err != nil {
			return fmt.Errorf("operator slashing validation failed: %w", err)
		}
	default:
		return fmt.Errorf("unknown task type: %s", payload.Type)
	}

	op.logger.Sugar().Infow("Task validation successful", "taskId", string(t.TaskId))
	return nil
}

func (op *OraclePerformer) HandleTask(t *performerV1.TaskRequest) (*performerV1.TaskResponse, error) {
	op.logger.Sugar().Infow("Handling Oracle task",
		zap.Any("task", t),
	)

	// ------------------------------------------------------------------------
	// Oracle Task Processing Logic
	// ------------------------------------------------------------------------
	// This is where the Performer will execute Oracle-specific work
	
	var resultBytes []byte
	var err error

	// Parse task payload to determine task type
	payload, err := parseTaskPayload(t)
	if err != nil {
		return nil, fmt.Errorf("failed to parse task payload: %w", err)
	}
	
	// Route to appropriate handler based on task type
	switch payload.Type {
	case TaskTypePriceAttestation:
		resultBytes, err = op.handlePriceAttestation(t, payload)
	case TaskTypeConsensusValidation:
		resultBytes, err = op.handleConsensusValidation(t, payload)
	case TaskTypeManipulationChallenge:
		resultBytes, err = op.handleManipulationChallenge(t, payload)
	case TaskTypeOperatorSlashing:
		resultBytes, err = op.handleOperatorSlashing(t, payload)
	default:
		return nil, fmt.Errorf("unknown task type '%s' for task %s", payload.Type, string(t.TaskId))
	}

	if err != nil {
		op.logger.Sugar().Errorw("Task processing failed", 
			"taskId", string(t.TaskId), 
			"error", err,
		)
		return nil, err
	}

	op.logger.Sugar().Infow("Task processing completed successfully", 
		"taskId", string(t.TaskId),
		"resultSize", len(resultBytes),
	)

	return &performerV1.TaskResponse{
		TaskId: t.TaskId,
		Result: resultBytes,
	}, nil
}

// handlePriceAttestation processes price attestation tasks
func (op *OraclePerformer) handlePriceAttestation(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	op.logger.Sugar().Infow("Processing price attestation task", "taskId", string(t.TaskId))
	
	// TODO: Implement price attestation logic
	// Example parameter access:
	// poolId := payload.Parameters["pool_id"].(string)
	// price := payload.Parameters["price"].(float64)
	
	// - Fetch prices from multiple sources (Binance, Coinbase, Kraken, etc.)
	// - Calculate weighted average price
	// - Sign price attestation with BLS signature
	// - Submit to Oracle AVS Service Manager
	// - Return attestation result
	
	return []byte("Price attestation completed"), nil
}

// handleConsensusValidation processes consensus validation tasks
func (op *OraclePerformer) handleConsensusValidation(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	op.logger.Sugar().Infow("Processing consensus validation task", "taskId", string(t.TaskId))
	
	// TODO: Implement consensus validation logic
	// - Validate incoming price attestations
	// - Check for outliers and manipulation attempts
	// - Calculate stake-weighted consensus
	// - Return consensus result
	
	return []byte("Consensus validation completed"), nil
}

// handleManipulationChallenge processes manipulation challenge tasks
func (op *OraclePerformer) handleManipulationChallenge(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	op.logger.Sugar().Infow("Processing manipulation challenge task", "taskId", string(t.TaskId))
	
	// TODO: Implement manipulation challenge logic
	// - Analyze suspected price manipulation
	// - Gather evidence from multiple price sources
	// - Calculate deviation from consensus
	// - Submit challenge proof
	// - Return challenge result
	
	return []byte("Manipulation challenge completed"), nil
}

// handleOperatorSlashing processes operator slashing tasks
func (op *OraclePerformer) handleOperatorSlashing(t *performerV1.TaskRequest, payload *TaskPayload) ([]byte, error) {
	op.logger.Sugar().Infow("Processing operator slashing task", "taskId", string(t.TaskId))
	
	// TODO: Implement operator slashing logic
	// - Validate slashing evidence
	// - Calculate slashing amount based on deviation
	// - Execute slashing through EigenLayer
	// - Update operator reliability scores
	// - Return slashing result
	
	return []byte("Operator slashing completed"), nil
}

// Oracle task validation functions
func (op *OraclePerformer) validatePriceAttestationTask(payload *TaskPayload) error {
	// Validate required parameters for price attestation
	if poolId, ok := payload.Parameters["pool_id"].(string); !ok || poolId == "" {
		return fmt.Errorf("missing or invalid pool_id")
	}
	
	if price, ok := payload.Parameters["price"].(float64); !ok || price <= 0 {
		return fmt.Errorf("missing or invalid price")
	}
	
	if sourceHash, ok := payload.Parameters["source_hash"].(string); !ok || sourceHash == "" {
		return fmt.Errorf("missing or invalid source_hash")
	}
	
	return nil
}

func (op *OraclePerformer) validateConsensusValidationTask(payload *TaskPayload) error {
	// Validate required parameters for consensus validation
	if poolId, ok := payload.Parameters["pool_id"].(string); !ok || poolId == "" {
		return fmt.Errorf("missing or invalid pool_id")
	}
	
	return nil
}

func (op *OraclePerformer) validateManipulationChallengeTask(payload *TaskPayload) error {
	// Validate required parameters for manipulation challenge
	if operator, ok := payload.Parameters["operator"].(string); !ok || operator == "" {
		return fmt.Errorf("missing or invalid operator")
	}
	
	if evidence, ok := payload.Parameters["evidence"].(string); !ok || evidence == "" {
		return fmt.Errorf("missing or invalid evidence")
	}
	
	return nil
}

func (op *OraclePerformer) validateOperatorSlashingTask(payload *TaskPayload) error {
	// Validate required parameters for operator slashing
	if operator, ok := payload.Parameters["operator"].(string); !ok || operator == "" {
		return fmt.Errorf("missing or invalid operator")
	}
	
	if slashAmount, ok := payload.Parameters["slash_amount"].(float64); !ok || slashAmount <= 0 {
		return fmt.Errorf("missing or invalid slash_amount")
	}
	
	return nil
}

func main() {
	ctx := context.Background()
	l, _ := zap.NewProduction()

	performer := NewOraclePerformer(l)

	pp, err := server.NewPonosPerformerWithRpcServer(&server.PonosPerformerConfig{
		Port:    8080,
		Timeout: 5 * time.Second,
	}, performer, l)
	if err != nil {
		panic(fmt.Errorf("failed to create Oracle performer: %w", err))
	}

	l.Info("Starting Oracle Performer on port 8080...")
	if err := pp.Start(ctx); err != nil {
		panic(err)
	}
}