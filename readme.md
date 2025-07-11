# AI BTC Price Prediction Platform

Blockchain-based Bitcoin price prediction platform powered by AI analysis

## Project Overview

This project combines AI and blockchain technology to create a decentralized platform where AI analyzes multiple data sources to predict Bitcoin prices, and users can bet on the AI's prediction results.

## Key Features

1. Multi-Source Data Analysis
   - M2 money supply, news sentiment, technical indicators
   - Comprehensive analysis beyond simple chart patterns

2. AI Confidence System
   - AI provides confidence scores (50-100%)
   - Rounds cannot start if confidence is below threshold

3. Fair Judgment Criteria
   - Configurable accuracy threshold (0-20%, default 5%)
   - Real-time Chainlink price feeds for objective judgment

4. Transparent Reward System
   - Configurable house fee (0-30%, default 3%)
   - Automatic reward distribution via Chainlink Automation

5. Complete Transparency
   - All AI analysis processes published on IPFS
   - All transaction history traceable on blockchain

## Architecture

```
AI Analysis Service → Oracle Contract → Main Contract
      ↓                    ↓              ↓
External APIs        Chainlink         Chainlink
• News APIs          Price Feeds       Automation
• Economic Data      • BTC/USD         (Auto Rewards)
• Social Media
```

## Project Structure

```
ai-btc-prediction/
├── contracts/
│   ├── AIBTCPrediction.sol
│   ├── AIBTCPredictionOracle.sol
│   └── test/
├── scripts/
│   └── deploy.js
├── ai-service/
│   └── requirements.txt
├── test/
└── docs/
```

## Quick Start

### Prerequisites
- Node.js v16+
- Python 3.8+
- Hardhat

### 1. Clone Repository
```bash
git clone https://github.com/CratosTokenOfficial/ai-btc-prediction.git
cd ai-btc-prediction
```

### 2. Install Dependencies
```bash
npm install
cd ai-service && pip install -r requirements.txt
```

### 3. Environment Setup
```bash
cp .env.example .env
# Edit .env with your configuration
```

### 4. Deploy Contracts
```bash
npx hardhat compile
npx hardhat run scripts/deploy.js --network bsc
```

### 5. Start AI Service
```bash
cd ai-service && python main.py
```

## Configuration

### Smart Contract Settings
- House Fee: 0-30% (default 3%)
- Accuracy Threshold: 0-20% (default 5%)
- Round Duration: 24 hours
- Min/Max Bet: 0.01 - 50 ETH/BNB

### AI Data Sources
- M2 Money Supply: Federal Reserve Economic Data
- News Sentiment: Multiple news APIs with NLP
- Technical Indicators: RSI, MACD, Bollinger Bands
- Fear & Greed Index: Alternative.me API
- Social Sentiment: Twitter/Reddit analysis

## Smart Contract Functions

### Main Contract
```solidity
// Admin functions
function setHouseFee(uint256 _houseFee) external onlyOwner
function setAccuracyThreshold(uint256 _threshold) external onlyOwner

// User functions
function placeBet(uint256 roundId, bool betOnAI) external payable
function claimReward(uint256 roundId) external

// Chainlink Automation
function checkUpkeep(bytes calldata) external view returns (bool, bytes memory)
function performUpkeep(bytes calldata) external
```

### Oracle Contract
```solidity
function submitPrediction(uint256 predictedPrice, uint256 confidence, string calldata analysisHash) external
function getLatestPrediction() external view returns (uint256, uint256, uint256, string memory)
function getCurrentBTCPrice() external view returns (uint256)
```

## Supported Networks

| Network | Chain ID | Currency | RPC URL |
|---------|----------|----------|---------|
| Ethereum Mainnet | 1 | ETH | infura.io |
| BSC Mainnet | 56 | BNB | bsc-dataseed.binance.org |
| BSC Testnet | 97 | tBNB | data-seed-prebsc.binance.org |

## Chainlink Price Feeds

| Network | BTC/USD Feed Address |
|---------|---------------------|
| Ethereum | 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c |
| BSC Mainnet | 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf |
| BSC Testnet | 0x5741306c21795FdCBb9b265Ea0255F946DaE2ad2 |

## How It Works

### 1. AI Analysis Phase
- Collect data from multiple sources
- Analyze M2 money supply, news sentiment, technical indicators
- Generate price prediction with confidence score
- Upload analysis to IPFS

### 2. Prediction Submission
- AI submits prediction to Oracle contract
- Oracle validates and stores data on-chain
- Main contract starts new betting round

### 3. Betting Phase (24 hours)
- Users bet FOR or AGAINST AI prediction
- Minimum 0.01, maximum 50 ETH/BNB per bet
- Bets locked after round ends

### 4. Resolution & Rewards
- Chainlink provides actual BTC price
- AI wins if within accuracy threshold
- Chainlink Automation distributes rewards
- Winners split prize pool proportionally

## Testing

```bash
npx hardhat test
npx hardhat coverage
cd ai-service && python -m pytest tests/
```

## Security Features

- ReentrancyGuard: Prevents reentrancy attacks
- Pausable: Emergency stop functionality
- Access Control: Owner-only admin functions
- Oracle Validation: Multiple data source verification

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Open Pull Request

## License

MIT License - see LICENSE file for details

## Contact

- GitHub: https://github.com/CratosTokenOfficial
- Email: contact@cratostoken.com

## Disclaimer

Educational and research purposes only. Cryptocurrency trading involves risk.