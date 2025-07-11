// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

interface IAIPredictionOracle {
    function getLatestPrediction() external view returns (
        uint256 predictedPrice,
        uint256 confidence,
        uint256 timestamp,
        string memory analysisHash
    );
    
    function getCurrentBTCPrice() external view returns (uint256);
}

contract AIBTCPrediction is ReentrancyGuard, Ownable, Pausable, AutomationCompatibleInterface {
    
    struct PredictionRound {
        uint256 roundId;
        uint256 aiPredictedPrice;
        uint256 actualStartPrice;
        uint256 actualEndPrice;
        uint256 confidence;
        uint256 startTime;
        uint256 endTime;
        bool resolved;
        bool aiWon;
        uint256 totalBullish;
        uint256 totalBearish;
        string analysisHash;
    }
    
    struct UserBet {
        uint256 amount;
        bool betOnAI;
        bool claimed;
    }
    
    IAIPredictionOracle public aiOracle;
    
    mapping(uint256 => PredictionRound) public predictionRounds;
    mapping(uint256 => mapping(address => UserBet)) public userBets;
    
    uint256 public currentRoundId;
    uint256 public constant ROUND_DURATION = 24 hours;
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant MAX_BET = 50 ether;
    uint256 public houseFee = 3;
    uint256 public accuracyThreshold = 5;
    bool public autoDistribution = true;
    
    mapping(uint256 => bool) public rewardsDistributed;
    
    event NewPredictionRound(
        uint256 indexed roundId,
        uint256 aiPredictedPrice,
        uint256 currentPrice,
        uint256 confidence,
        string analysisHash
    );
    
    event BetPlaced(
        uint256 indexed roundId,
        address indexed user,
        uint256 amount,
        bool betOnAI
    );
    
    event RoundResolved(
        uint256 indexed roundId,
        uint256 actualPrice,
        bool aiWon,
        uint256 totalPayout
    );
    
    event RewardClaimed(
        uint256 indexed roundId,
        address indexed user,
        uint256 amount
    );
    
    event RewardDistributed(
        uint256 indexed roundId,
        uint256 totalPayout,
        uint256 winningPool
    );
    
    event HouseFeeUpdated(uint256 newFee);
    event AccuracyThresholdUpdated(uint256 newThreshold);
    event AutoDistributionToggled(bool enabled);
    
    constructor(address _aiOracle) {
        aiOracle = IAIPredictionOracle(_aiOracle);
        currentRoundId = 1;
    }
    
    function startNewRound() external onlyOwner {
        require(
            currentRoundId == 1 || 
            (predictionRounds[currentRoundId - 1].resolved && 
             block.timestamp >= predictionRounds[currentRoundId - 1].endTime),
            "Previous round not finished"
        );
        
        (uint256 predictedPrice, uint256 confidence, uint256 timestamp, string memory analysisHash) = 
            aiOracle.getLatestPrediction();
        
        require(block.timestamp - timestamp <= 1 hours, "AI prediction too old");
        require(confidence >= 60, "AI confidence too low");
        
        uint256 currentPrice = aiOracle.getCurrentBTCPrice();
        
        PredictionRound storage round = predictionRounds[currentRoundId];
        round.roundId = currentRoundId;
        round.aiPredictedPrice = predictedPrice;
        round.actualStartPrice = currentPrice;
        round.confidence = confidence;
        round.startTime = block.timestamp;
        round.endTime = block.timestamp + ROUND_DURATION;
        round.resolved = false;
        round.analysisHash = analysisHash;
        
        emit NewPredictionRound(
            currentRoundId,
            predictedPrice,
            currentPrice,
            confidence,
            analysisHash
        );
        
        currentRoundId++;
    }
    
    function placeBet(uint256 roundId, bool betOnAI) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        require(msg.value >= MIN_BET && msg.value <= MAX_BET, "Invalid bet amount");
        require(roundId < currentRoundId, "Round not started");
        require(block.timestamp < predictionRounds[roundId].endTime, "Betting period ended");
        require(userBets[roundId][msg.sender].amount == 0, "Already placed bet");
        
        PredictionRound storage round = predictionRounds[roundId];
        require(!round.resolved, "Round already resolved");
        
        userBets[roundId][msg.sender] = UserBet({
            amount: msg.value,
            betOnAI: betOnAI,
            claimed: false
        });
        
        if (betOnAI) {
            round.totalBullish += msg.value;
        } else {
            round.totalBearish += msg.value;
        }
        
        emit BetPlaced(roundId, msg.sender, msg.value, betOnAI);
    }
    
    function resolveRound(uint256 roundId) external onlyOwner {
        PredictionRound storage round = predictionRounds[roundId];
        require(block.timestamp >= round.endTime, "Round not finished");
        require(!round.resolved, "Round already resolved");
        
        uint256 actualPrice = aiOracle.getCurrentBTCPrice();
        round.actualEndPrice = actualPrice;
        
        uint256 priceDifference;
        if (round.aiPredictedPrice > actualPrice) {
            priceDifference = round.aiPredictedPrice - actualPrice;
        } else {
            priceDifference = actualPrice - round.aiPredictedPrice;
        }
        
        uint256 accuracyPercentage = (priceDifference * 100) / round.actualStartPrice;
        round.aiWon = accuracyPercentage <= accuracyThreshold;
        round.resolved = true;
        
        uint256 totalPool = round.totalBullish + round.totalBearish;
        uint256 totalPayout = (totalPool * (100 - houseFee)) / 100;
        
        emit RoundResolved(roundId, actualPrice, round.aiWon, totalPayout);
    }
    
    function checkUpkeep(bytes calldata) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory performData) 
    {
        uint256[] memory roundsToProcess = new uint256[](50);
        uint256 count = 0;
        
        for (uint256 i = 1; i < currentRoundId && count < 50; i++) {
            PredictionRound storage round = predictionRounds[i];
            
            if (round.resolved && 
                !rewardsDistributed[i] && 
                (round.totalBullish > 0 || round.totalBearish > 0)) {
                roundsToProcess[count] = i;
                count++;
            }
        }
        
        if (count > 0) {
            uint256[] memory roundsToReturn = new uint256[](count);
            for (uint256 i = 0; i < count; i++) {
                roundsToReturn[i] = roundsToProcess[i];
            }
            
            upkeepNeeded = true;
            performData = abi.encode(roundsToReturn);
        }
    }
    
    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory roundsToProcess = abi.decode(performData, (uint256[]));
        
        for (uint256 i = 0; i < roundsToProcess.length; i++) {
            uint256 roundId = roundsToProcess[i];
            if (!rewardsDistributed[roundId] && autoDistribution) {
                _distributeRewards(roundId);
            }
        }
    }
    
    function _distributeRewards(uint256 roundId) internal {
        PredictionRound storage round = predictionRounds[roundId];
        
        if (!round.resolved || rewardsDistributed[roundId]) {
            return;
        }
        
        uint256 totalPool = round.totalBullish + round.totalBearish;
        if (totalPool == 0) {
            rewardsDistributed[roundId] = true;
            return;
        }
        
        uint256 totalPayout = (totalPool * (100 - houseFee)) / 100;
        uint256 winningPool = round.aiWon ? round.totalBullish : round.totalBearish;
        
        rewardsDistributed[roundId] = true;
        
        emit RewardDistributed(roundId, totalPayout, winningPool);
    }
    
    function claimReward(uint256 roundId) external nonReentrant {
        PredictionRound storage round = predictionRounds[roundId];
        UserBet storage userBet = userBets[roundId][msg.sender];
        
        require(round.resolved, "Round not resolved");
        require(userBet.amount > 0, "No bet placed");
        require(!userBet.claimed, "Already claimed");
        require(userBet.betOnAI == round.aiWon, "Bet lost");
        
        if (autoDistribution && rewardsDistributed[roundId]) {
            revert("Rewards already auto-distributed");
        }
        
        uint256 totalPool = round.totalBullish + round.totalBearish;
        uint256 totalPayout = (totalPool * (100 - houseFee)) / 100;
        
        uint256 winningPool = round.aiWon ? round.totalBullish : round.totalBearish;
        uint256 userReward = (totalPayout * userBet.amount) / winningPool;
        
        userBet.claimed = true;
        
        (bool success, ) = payable(msg.sender).call{value: userReward}("");
        require(success, "Transfer failed");
        
        emit RewardClaimed(roundId, msg.sender, userReward);
    }
    
    function setHouseFee(uint256 _houseFee) external onlyOwner {
        require(_houseFee <= 30, "House fee cannot exceed 30%");
        houseFee = _houseFee;
        emit HouseFeeUpdated(_houseFee);
    }
    
    function setAccuracyThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold <= 20, "Threshold cannot exceed 20%");
        accuracyThreshold = _threshold;
        emit AccuracyThresholdUpdated(_threshold);
    }
    
    function setAutoDistribution(bool _enabled) external onlyOwner {
        autoDistribution = _enabled;
        emit AutoDistributionToggled(_enabled);
    }
    
    function getPredictionRound(uint256 roundId) external view returns (
        uint256 aiPredictedPrice,
        uint256 actualStartPrice,
        uint256 actualEndPrice,
        uint256 confidence,
        uint256 startTime,
        uint256 endTime,
        bool resolved,
        bool aiWon,
        uint256 totalBullish,
        uint256 totalBearish,
        string memory analysisHash
    ) {
        PredictionRound storage round = predictionRounds[roundId];
        return (
            round.aiPredictedPrice,
            round.actualStartPrice,
            round.actualEndPrice,
            round.confidence,
            round.startTime,
            round.endTime,
            round.resolved,
            round.aiWon,
            round.totalBullish,
            round.totalBearish,
            round.analysisHash
        );
    }
    
    function getUserBet(uint256 roundId, address user) external view returns (
        uint256 amount,
        bool betOnAI,
        bool claimed
    ) {
        UserBet storage bet = userBets[roundId][user];
        return (bet.amount, bet.betOnAI, bet.claimed);
    }
    
    function getContractSettings() external view returns (
        uint256 currentHouseFee,
        uint256 currentAccuracyThreshold,
        bool autoDistributionEnabled,
        uint256 minBet,
        uint256 maxBet,
        uint256 roundDuration
    ) {
        return (
            houseFee,
            accuracyThreshold,
            autoDistribution,
            MIN_BET,
            MAX_BET,
            ROUND_DURATION
        );
    }
    
    function updateAIOracle(address _aiOracle) external onlyOwner {
        aiOracle = IAIPredictionOracle(_aiOracle);
    }
    
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        
        uint256 lockedAmount = 0;
        for (uint256 i = 1; i < currentRoundId; i++) {
            if (!predictionRounds[i].resolved) {
                lockedAmount += predictionRounds[i].totalBullish + predictionRounds[i].totalBearish;
            }
        }
        
        uint256 availableAmount = balance - lockedAmount;
        require(availableAmount > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: availableAmount}("");
        require(success, "Transfer failed");
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    receive() external payable {}
}