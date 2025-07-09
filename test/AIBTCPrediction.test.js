const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("AI BTC Prediction", function () {
  let prediction, oracle, mockPriceFeed;
  let owner, user1, user2, aiProvider;
  let mockBTCPrice = ethers.parseUnits("45000", 8);

  beforeEach(async function () {
    [owner, user1, user2, aiProvider] = await ethers.getSigners();

    // Deploy mock price feed
    const MockAggregator = await ethers.getContractFactory("MockV3Aggregator");
    mockPriceFeed = await MockAggregator.deploy(8, mockBTCPrice);
    await mockPriceFeed.waitForDeployment();

    // Deploy Oracle
    const AIBTCPredictionOracle = await ethers.getContractFactory("AIBTCPredictionOracle");
    oracle = await AIBTCPredictionOracle.deploy(await mockPriceFeed.getAddress());
    await oracle.waitForDeployment();

    // Deploy Prediction Contract
    const AIBTCPrediction = await ethers.getContractFactory("AIBTCPrediction");
    prediction = await AIBTCPrediction.deploy(await oracle.getAddress());
    await prediction.waitForDeployment();

    // Setup AI provider
    await oracle.authorizeAIProvider(aiProvider.address, true);
  });

  describe("Deployment", function () {
    it("Should set the right oracle address", async function () {
      expect(await prediction.aiOracle()).to.equal(await oracle.getAddress());
    });

    it("Should set the right owner", async function () {
      expect(await prediction.owner()).to.equal(owner.address);
    });

    it("Should have correct initial settings", async function () {
      const settings = await prediction.getContractSettings();
      expect(settings.currentHouseFee).to.equal(3);
      expect(settings.currentAccuracyThreshold).to.equal(5);
      expect(settings.autoDistributionEnabled).to.equal(true);
    });
  });

  describe("Configuration", function () {
    it("Should allow owner to set house fee", async function () {
      await prediction.setHouseFee(10);
      const settings = await prediction.getContractSettings();
      expect(settings.currentHouseFee).to.equal(10);
    });

    it("Should reject house fee above 30%", async function () {
      await expect(prediction.setHouseFee(31)).to.be.revertedWith("House fee cannot exceed 30%");
    });

    it("Should allow owner to set accuracy threshold", async function () {
      await prediction.setAccuracyThreshold(10);
      const settings = await prediction.getContractSettings();
      expect(settings.currentAccuracyThreshold).to.equal(10);
    });

    it("Should reject accuracy threshold above 20%", async function () {
      await expect(prediction.setAccuracyThreshold(21)).to.be.revertedWith("Threshold cannot exceed 20%");
    });
  });

  describe("AI Predictions", function () {
    it("Should allow authorized AI provider to submit prediction", async function () {
      const predictedPrice = ethers.parseUnits("46000", 8);
      const confidence = 75;
      const analysisHash = "QmTestHash123";

      await expect(
        oracle.connect(aiProvider).submitPrediction(predictedPrice, confidence, analysisHash)
      ).to.emit(oracle, "PredictionSubmitted");
    });

    it("Should reject prediction from unauthorized provider", async function () {
      const predictedPrice = ethers.parseUnits("46000", 8);
      const confidence = 75;
      const analysisHash = "QmTestHash123";

      await expect(
        oracle.connect(user1).submitPrediction(predictedPrice, confidence, analysisHash)
      ).to.be.revertedWith("Not authorized AI provider");
    });
  });

  describe("Betting Rounds", function () {
    beforeEach(async function () {
      // Submit AI prediction
      const predictedPrice = ethers.parseUnits("46000", 8);
      const confidence = 75;
      const analysisHash = "QmTestHash123";
      
      await oracle.connect(aiProvider).submitPrediction(predictedPrice, confidence, analysisHash);
      
      // Start new round
      await prediction.startNewRound();
    });

    it("Should start a new round with AI prediction", async function () {
      const roundInfo = await prediction.getPredictionRound(1);
      expect(roundInfo.aiPredictedPrice).to.equal(ethers.parseUnits("46000", 8));
      expect(roundInfo.confidence).to.equal(75);
      expect(roundInfo.resolved).to.equal(false);
    });

    it("Should allow users to place bets", async function () {
      const betAmount = ethers.parseEther("1.0");
      
      await expect(
        prediction.connect(user1).placeBet(1, true, { value: betAmount })
      ).to.emit(prediction, "BetPlaced");

      const userBet = await prediction.getUserBet(1, user1.address);
      expect(userBet.amount).to.equal(betAmount);
      expect(userBet.betOnAI).to.equal(true);
    });

    it("Should reject bets below minimum", async function () {
      const betAmount = ethers.parseEther("0.005");
      
      await expect(
        prediction.connect(user1).placeBet(1, true, { value: betAmount })
      ).to.be.revertedWith("Invalid bet amount");
    });

    it("Should prevent double betting", async function () {
      const betAmount = ethers.parseEther("1.0");
      
      await prediction.connect(user1).placeBet(1, true, { value: betAmount });
      
      await expect(
        prediction.connect(user1).placeBet(1, false, { value: betAmount })
      ).to.be.revertedWith("Already placed bet");
    });
  });

  describe("Round Resolution", function () {
    beforeEach(async function () {
      // Submit AI prediction for $46,000
      await oracle.connect(aiProvider).submitPrediction(
        ethers.parseUnits("46000", 8),
        75,
        "QmTestHash123"
      );
      
      // Start new round
      await prediction.startNewRound();
      
      // Place some bets
      await prediction.connect(user1).placeBet(1, true, { value: ethers.parseEther("1.0") });
      await prediction.connect(user2).placeBet(1, false, { value: ethers.parseEther("2.0") });
      
      // Fast forward to end of round
      await time.increase(24 * 60 * 60 + 1);
    });

    it("Should resolve round correctly when AI wins", async function () {
      // Set actual price to $46,100 (within 5% of predicted $46,000)
      const actualPrice = ethers.parseUnits("46100", 8);
      await mockPriceFeed.updateAnswer(actualPrice);
      
      await expect(prediction.resolveRound(1))
        .to.emit(prediction, "RoundResolved");
      
      const roundInfo = await prediction.getPredictionRound(1);
      expect(roundInfo.resolved).to.equal(true);
      expect(roundInfo.aiWon).to.equal(true);
    });

    it("Should resolve round correctly when AI loses", async function () {
      // Set actual price to $48,000 (more than 5% from predicted $46,000)
      const actualPrice = ethers.parseUnits("48000", 8);
      await mockPriceFeed.updateAnswer(actualPrice);
      
      await prediction.resolveRound(1);
      
      const roundInfo = await prediction.getPredictionRound(1);
      expect(roundInfo.resolved).to.equal(true);
      expect(roundInfo.aiWon).to.equal(false);
    });
  });

  describe("Reward Claims", function () {
    beforeEach(async function () {
      // Complete setup for resolved round
      await oracle.connect(aiProvider).submitPrediction(
        ethers.parseUnits("46000", 8),
        75,
        "QmTestHash123"
      );
      
      await prediction.startNewRound();
      
      // User1 bets 1 ETH on AI, User2 bets 2 ETH against AI
      await prediction.connect(user1).placeBet(1, true, { value: ethers.parseEther("1.0") });
      await prediction.connect(user2).placeBet(1, false, { value: ethers.parseEther("2.0") });
      
      await time.increase(24 * 60 * 60 + 1);
      
      // AI wins
      await mockPriceFeed.updateAnswer(ethers.parseUnits("46100", 8));
      await prediction.resolveRound(1);
    });

    it("Should allow winners to claim rewards", async function () {
      const userBalanceBefore = await ethers.provider.getBalance(user1.address);
      
      await prediction.connect(user1).claimReward(1);
      
      const userBalanceAfter = await ethers.provider.getBalance(user1.address);
      expect(userBalanceAfter).to.be.gt(userBalanceBefore);
    });

    it("Should prevent losers from claiming", async function () {
      await expect(prediction.connect(user2).claimReward(1))
        .to.be.revertedWith("Bet lost");
    });

    it("Should prevent double claiming", async function () {
      await prediction.connect(user1).claimReward(1);
      
      await expect(prediction.connect(user1).claimReward(1))
        .to.be.revertedWith("Already claimed");
    });
  });
});