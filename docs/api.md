# API Reference

## Smart Contract APIs

### AVSOracleHook

#### Constructor
```solidity
constructor(IPoolManager _poolManager, address _oracleAVS)
```
Initializes the Oracle Hook with pool manager and AVS addresses.

**Parameters:**
- `_poolManager`: Uniswap V4 pool manager address
- `_oracleAVS`: Oracle AVS service manager address

#### Hook Functions

##### getHookPermissions()
```solidity
function getHookPermissions() public pure returns (Hooks.Permissions memory)
```
Returns the hook permissions required by this contract.

**Returns:**
- `Hooks.Permissions`: Permission struct with enabled hooks

##### beforeInitialize()
```solidity
function beforeInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96,
    bytes calldata hookData
) external returns (bytes4)
```
Called before pool initialization to set up oracle configuration.

**Parameters:**
- `sender`: Address initiating pool creation
- `key`: Pool key containing token addresses and fee
- `sqrtPriceX96`: Initial price of the pool
- `hookData`: Additional hook data

**Returns:**
- `bytes4`: Function selector for success

##### beforeSwap()
```solidity
function beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
) external returns (bytes4, BeforeSwapDelta, uint24)
```
Validates swap prices against AVS consensus before execution.

**Parameters:**
- `sender`: Address initiating the swap
- `key`: Pool key
- `params`: Swap parameters (amount, direction, etc.)
- `hookData`: Additional hook data

**Returns:**
- `bytes4`: Function selector
- `BeforeSwapDelta`: Delta modifications (typically zero)
- `uint24`: LP fee override (typically zero)

**Reverts:**
- `"Oracle validation failed"`: When consensus validation fails

##### afterSwap()
```solidity
function afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external returns (bytes4, int128)
```
Post-swap processing and operator reliability updates.

**Parameters:**
- `sender`: Address that initiated the swap
- `key`: Pool key
- `params`: Swap parameters
- `delta`: Swap result deltas
- `hookData`: Additional hook data

**Returns:**
- `bytes4`: Function selector
- `int128`: Hook delta (typically zero)

#### Oracle Management

##### getConsensusData()
```solidity
function getConsensusData(PoolId poolId) external view returns (
    uint256 consensusPrice,
    uint256 totalStake,
    uint256 confidenceLevel,
    bool isValid
)
```
Retrieves current consensus data for a pool.

**Parameters:**
- `poolId`: Pool identifier

**Returns:**
- `consensusPrice`: Current consensus price
- `totalStake`: Total stake backing consensus
- `confidenceLevel`: Confidence level (0-10000 BPS)
- `isValid`: Whether consensus is valid for trading

##### enableOracleForPool()
```solidity
function enableOracleForPool(PoolId poolId, bool enabled) external
```
Enables or disables oracle validation for a specific pool.

**Parameters:**
- `poolId`: Pool identifier
- `enabled`: Whether to enable oracle validation

##### updateOracleConfig()
```solidity
function updateOracleConfig(
    PoolId poolId,
    uint256 maxPriceDeviation,
    uint256 minStakeRequired,
    uint256 consensusThreshold
) external
```
Updates oracle configuration parameters for a pool.

**Parameters:**
- `poolId`: Pool identifier
- `maxPriceDeviation`: Maximum allowed price deviation (BPS)
- `minStakeRequired`: Minimum stake required for consensus
- `consensusThreshold`: Consensus threshold percentage

#### Events

##### PriceValidationRequested
```solidity
event PriceValidationRequested(
    PoolId indexed poolId,
    address indexed trader,
    uint256 swapAmount,
    uint256 expectedPrice
)
```
Emitted when price validation is requested for a swap.

##### ConsensusReached
```solidity
event ConsensusReached(
    PoolId indexed poolId,
    uint256 consensusPrice,
    uint256 totalStake,
    uint256 attestationCount,
    uint256 confidenceLevel
)
```
Emitted when consensus is successfully reached.

##### SwapBlocked
```solidity
event SwapBlocked(
    PoolId indexed poolId,
    address indexed trader,
    uint256 requestedPrice,
    uint256 consensusPrice,
    string reason
)
```
Emitted when a swap is blocked due to validation failure.

##### ManipulationDetected
```solidity
event ManipulationDetected(
    PoolId indexed poolId,
    address indexed suspiciousOperator,
    uint256 reportedPrice,
    uint256 consensusPrice,
    uint256 deviation
)
```
Emitted when price manipulation is detected.

### PriceValidation Library

#### validatePrice()
```solidity
function validatePrice(ValidationParams memory params) 
    internal pure returns (ValidationResult memory)
```
Validates a price against consensus parameters.

**Parameters:**
```solidity
struct ValidationParams {
    uint256 currentPrice;
    uint256 consensusPrice;
    uint256 confidenceLevel;
    uint256 maxDeviationBps;
    uint256 minConfidence;
    uint256 timestamp;
    uint256 maxStaleness;
}
```

**Returns:**
```solidity
struct ValidationResult {
    bool isValid;
    uint256 deviation;
    string reason;
}
```

#### detectManipulation()
```solidity
function detectManipulation(
    uint256[] memory prices,
    uint256[] memory timestamps
) internal pure returns (bool isManipulation, uint256 suspicionLevel)
```
Detects potential price manipulation patterns.

**Parameters:**
- `prices`: Array of historical prices
- `timestamps`: Corresponding timestamps

**Returns:**
- `isManipulation`: Whether manipulation is detected
- `suspicionLevel`: Suspicion level (0-10000 BPS)

#### validateMultipleSources()
```solidity
function validateMultipleSources(
    uint256[] memory sources,
    uint256[] memory weights
) internal pure returns (uint256 weightedPrice, uint256 consistency)
```
Validates prices from multiple sources.

**Parameters:**
- `sources`: Array of price sources
- `weights`: Corresponding weights

**Returns:**
- `weightedPrice`: Weighted average price
- `consistency`: Consistency score (0-10000 BPS)

### ConsensusCalculation Library

#### calculateConsensus()
```solidity
function calculateConsensus(
    AttestationData[] memory attestations,
    uint256 consensusThreshold
) internal pure returns (ConsensusResult memory)
```
Calculates stake-weighted consensus from attestations.

**Parameters:**
```solidity
struct AttestationData {
    address operator;
    uint256 price;
    uint256 stake;
    uint256 timestamp;
    uint256 reliability;
}
```

**Returns:**
```solidity
struct ConsensusResult {
    uint256 consensusPrice;
    uint256 totalStake;
    uint256 participatingStake;
    uint256 confidenceLevel;
    uint256 convergenceScore;
    bool hasConsensus;
}
```

## Go Operator API

### Configuration

#### Config Structure
```go
type Config struct {
    Operator    OperatorConfig    `yaml:"operator"`
    Networks    NetworksConfig    `yaml:"networks"`
    PriceSources PriceSourcesConfig `yaml:"price_sources"`
    Consensus   ConsensusConfig   `yaml:"consensus"`
}

type OperatorConfig struct {
    Address     string `yaml:"address"`
    PrivateKey  string `yaml:"private_key"`
    StakeAmount string `yaml:"stake_amount"`
}
```

### Operator Commands

#### Register Operator
```bash
./operator register --config config.yaml
```
Registers the operator with the AVS service manager.

#### Start Operator
```bash
./operator start --config config.yaml [--daemon]
```
Starts the operator service for price attestations.

**Flags:**
- `--daemon`: Run in background mode
- `--log-level`: Set logging level (debug, info, warn, error)
- `--metrics-port`: Port for metrics endpoint

#### Operator Status
```bash
./operator status --config config.yaml
```
Shows current operator status and statistics.

#### Stop Operator
```bash
./operator stop
```
Gracefully stops the operator service.

### REST API Endpoints

#### Health Check
```
GET /health
```
Returns operator health status.

**Response:**
```json
{
  "status": "healthy",
  "uptime": "2h30m15s",
  "last_attestation": "2024-01-15T10:30:00Z",
  "consensus_participation": 95.5
}
```

#### Metrics
```
GET /metrics
```
Returns Prometheus-formatted metrics.

#### Price Data
```
GET /price/{symbol}
```
Returns current price data for a symbol.

**Response:**
```json
{
  "symbol": "ETH/USD",
  "price": "2105.50",
  "sources": {
    "binance": "2105.23",
    "coinbase": "2105.45",
    "kraken": "2105.67"
  },
  "timestamp": "2024-01-15T10:30:00Z",
  "confidence": 8500
}
```

### WebSocket API

#### Price Updates
```
ws://localhost:8080/ws/prices
```
Real-time price updates stream.

**Message Format:**
```json
{
  "type": "price_update",
  "symbol": "ETH/USD",
  "price": "2105.50",
  "timestamp": "2024-01-15T10:30:00Z",
  "sources": ["binance", "coinbase", "kraken"]
}
```

#### Consensus Events
```
ws://localhost:8080/ws/consensus
```
Real-time consensus events stream.

**Message Format:**
```json
{
  "type": "consensus_reached",
  "pool_id": "0x...",
  "consensus_price": "2105.50",
  "participants": 5,
  "confidence": 8500,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## HTTP API

### Price Oracle Service

#### Base URL
```
Production: https://api.avsoracle.com
Testnet: https://testnet-api.avsoracle.com
```

#### Authentication
```bash
# API Key in header
curl -H "X-API-Key: your-api-key" https://api.avsoracle.com/v1/price/ETH-USD
```

#### Get Current Price
```
GET /v1/price/{symbol}
```

**Parameters:**
- `symbol`: Trading pair symbol (e.g., ETH-USD, BTC-USD)

**Response:**
```json
{
  "symbol": "ETH-USD",
  "price": "2105.50",
  "confidence": 8500,
  "timestamp": "2024-01-15T10:30:00Z",
  "sources": {
    "binance": 2105.23,
    "coinbase": 2105.45,
    "kraken": 2105.67
  },
  "consensus": {
    "operators": 5,
    "total_stake": "500000000000000000000",
    "deviation": 25
  }
}
```

#### Get Historical Prices
```
GET /v1/price/{symbol}/history?from={timestamp}&to={timestamp}&interval={interval}
```

**Parameters:**
- `from`: Start timestamp (Unix)
- `to`: End timestamp (Unix)
- `interval`: Time interval (1m, 5m, 15m, 1h, 4h, 1d)

**Response:**
```json
{
  "symbol": "ETH-USD",
  "interval": "1h",
  "data": [
    {
      "timestamp": "2024-01-15T09:00:00Z",
      "price": "2100.00",
      "confidence": 8200
    },
    {
      "timestamp": "2024-01-15T10:00:00Z",
      "price": "2105.50",
      "confidence": 8500
    }
  ]
}
```

#### Get Consensus Status
```
GET /v1/consensus/{pool_id}
```

**Response:**
```json
{
  "pool_id": "0x...",
  "consensus_price": "2105.50",
  "total_stake": "500000000000000000000",
  "operator_count": 5,
  "confidence_level": 8500,
  "last_update": "2024-01-15T10:30:00Z",
  "is_valid": true
}
```

### Error Codes

#### HTTP Status Codes
- `200`: Success
- `400`: Bad Request
- `401`: Unauthorized
- `403`: Forbidden
- `404`: Not Found
- `429`: Rate Limited
- `500`: Internal Server Error
- `503`: Service Unavailable

#### Error Response Format
```json
{
  "error": {
    "code": "INVALID_SYMBOL",
    "message": "Symbol ETH-INVALID is not supported",
    "details": {
      "supported_symbols": ["ETH-USD", "BTC-USD", "USDC-USD"]
    }
  }
}
```

### Rate Limits

#### Public Endpoints
- **Requests**: 100 per minute per IP
- **WebSocket**: 10 connections per IP

#### Authenticated Endpoints
- **Basic Plan**: 1,000 requests per minute
- **Pro Plan**: 10,000 requests per minute
- **Enterprise**: Custom limits

### SDKs and Libraries

#### JavaScript/TypeScript
```bash
npm install @avsoracle/sdk
```

```typescript
import { AVSOracleClient } from '@avsoracle/sdk';

const client = new AVSOracleClient({
  apiKey: 'your-api-key',
  network: 'mainnet'
});

const price = await client.getPrice('ETH-USD');
```

#### Python
```bash
pip install avsoracle-python
```

```python
from avsoracle import AVSOracleClient

client = AVSOracleClient(api_key='your-api-key')
price = client.get_price('ETH-USD')
```

#### Go
```bash
go get github.com/avsoracle/go-sdk
```

```go
import "github.com/avsoracle/go-sdk"

client := avsoracle.NewClient("your-api-key")
price, err := client.GetPrice("ETH-USD")
```