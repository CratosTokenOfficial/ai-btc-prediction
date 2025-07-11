// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AIBTCPredictionOracle is Ownable, ReentrancyGuard {
    
    struct PredictionData {
        uint256 predictedPrice;
        uint256 confidence;
        uint256 timestamp;
        string analysisHash;
        address aiProvider;
        bool isActive;
    }
    
    struct DataSource {
        string name;
        uint256 weight;
        bool isActive;
        uint256 lastUpdate;
    }
    
    AggregatorV3Interface internal btcPriceFeed;
    
    mapping(uint256 => PredictionData) public predictions;
    mapping(address => bool) public authorizedAIProviders;
    mapping(string => DataSource) public dataSources;
    
    uint256 public latestPredictionId;
    uint256 public constant PREDICTION_VALIDITY_PERIOD = 2 hours;
    
    string[] public dataSourceNames;
    
    event PredictionSubmitted(
        uint256 indexed predictionId,
        uint256 predictedPrice,
        uint256 confidence,
        string analysisHash,
        address aiProvider
    );
    
    event DataSourceAdded(string name, uint256 weight);
    event DataSourceUpdated(string name, uint256 weight, bool isActive);
    event AIProviderAuthorized(address provider, bool authorized);
    
    constructor(address _btcPriceFeed) {
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        
        _addDataSource("M2_MONEY_SUPPLY", 30);
        _addDataSource("CRYPTO_NEWS_SENTIMENT", 25);
        _addDataSource("TECHNICAL_ANALYSIS", 20);
        _addDataSource("ECONOMIC_INDICATORS", 15);
        _addDataSource("SOCIAL_MEDIA_SENTIMENT", 10);
    }
    
    function _addDataSource(string memory name, uint256 weight) internal {
        dataSources[name] = DataSource({
            name: name,
            weight: weight,
            isActive: true,
            lastUpdate: block.timestamp
        });
        dataSourceNames.push(name);
        emit DataSourceAdded(name, weight);
    }
    
    function submitPrediction(
        uint256 predictedPrice,
        uint256 confidence,
        string calldata analysisHash
    ) external {
        require(authorizedAIProviders[msg.sender], "Not authorized AI provider");
        require(predictedPrice > 0, "Invalid predicted price");
        require(confidence >= 50 && confidence <= 100, "Confidence must be 50-100");
        require(bytes(analysisHash).length > 0, "Analysis hash required");
        
        latestPredictionId++;
        
        predictions[latestPredictionId] = PredictionData({
            predictedPrice: predictedPrice,
            confidence: confidence,
            timestamp: block.timestamp,
            analysisHash: analysisHash,
            aiProvider: msg.sender,
            isActive: true
        });
        
        emit PredictionSubmitted(
            latestPredictionId,
            predictedPrice,
            confidence,
            analysisHash,
            msg.sender
        );
    }
    
    function getLatestPrediction() external view returns (
        uint256 predictedPrice,
        uint256 confidence,
        uint256 timestamp,
        string memory analysisHash
    ) {
        require(latestPredictionId > 0, "No predictions available");
        
        PredictionData storage prediction = predictions[latestPredictionId];
        require(prediction.isActive, "Latest prediction not active");
        require(
            block.timestamp - prediction.timestamp <= PREDICTION_VALIDITY_PERIOD,
            "Prediction too old"
        );
        
        return (
            prediction.predictedPrice,
            prediction.confidence,
            prediction.timestamp,
            prediction.analysisHash
        );
    }
    
    function getCurrentBTCPrice() external view returns (uint256) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = btcPriceFeed.latestRoundData();
        
        require(price > 0, "Invalid price");
        require(timeStamp > 0, "Invalid timestamp");
        require(block.timestamp - timeStamp <= 3600, "Price too old");
        
        return uint256(price);
    }
    
    function getPredictionById(uint256 predictionId) external view returns (
        uint256 predictedPrice,
        uint256 confidence,
        uint256 timestamp,
        string memory analysisHash,
        address aiProvider,
        bool isActive
    ) {
        PredictionData storage prediction = predictions[predictionId];
        return (
            prediction.predictedPrice,
            prediction.confidence,
            prediction.timestamp,
            prediction.analysisHash,
            prediction.aiProvider,
            prediction.isActive
        );
    }
    
    function getDataSourceInfo(string calldata sourceName) external view returns (
        uint256 weight,
        bool isActive,
        uint256 lastUpdate
    ) {
        DataSource storage source = dataSources[sourceName];
        return (source.weight, source.isActive, source.lastUpdate);
    }
    
    function getAllDataSources() external view returns (
        string[] memory names,
        uint256[] memory weights,
        bool[] memory activeStatus
    ) {
        uint256 length = dataSourceNames.length;
        names = new string[](length);
        weights = new uint256[](length);
        activeStatus = new bool[](length);
        
        for (uint256 i = 0; i < length; i++) {
            string memory name = dataSourceNames[i];
            names[i] = name;
            weights[i] = dataSources[name].weight;
            activeStatus[i] = dataSources[name].isActive;
        }
        
        return (names, weights, activeStatus);
    }
    
    function authorizeAIProvider(address provider, bool authorized) external onlyOwner {
        authorizedAIProviders[provider] = authorized;
        emit AIProviderAuthorized(provider, authorized);
    }
    
    function addDataSource(string calldata name, uint256 weight) external onlyOwner {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(weight > 0 && weight <= 100, "Weight must be 1-100");
        require(dataSources[name].weight == 0, "Data source already exists");
        
        _addDataSource(name, weight);
    }
    
    function updateDataSource(
        string calldata name,
        uint256 weight,
        bool isActive
    ) external onlyOwner {
        require(dataSources[name].weight > 0, "Data source does not exist");
        require(weight > 0 && weight <= 100, "Weight must be 1-100");
        
        dataSources[name].weight = weight;
        dataSources[name].isActive = isActive;
        dataSources[name].lastUpdate = block.timestamp;
        
        emit DataSourceUpdated(name, weight, isActive);
    }
    
    function deactivatePrediction(uint256 predictionId) external onlyOwner {
        require(predictionId <= latestPredictionId, "Invalid prediction ID");
        predictions[predictionId].isActive = false;
    }
    
    function updateBTCPriceFeed(address _btcPriceFeed) external onlyOwner {
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
    }
    
    function isPredictionValid(uint256 predictionId) external view returns (bool) {
        if (predictionId == 0 || predictionId > latestPredictionId) {
            return false;
        }
        
        PredictionData storage prediction = predictions[predictionId];
        return prediction.isActive && 
               (block.timestamp - prediction.timestamp <= PREDICTION_VALIDITY_PERIOD);
    }
    
    function getLatestValidPrediction() external view returns (
        uint256 predictionId,
        uint256 predictedPrice,
        uint256 confidence,
        uint256 timestamp,
        string memory analysisHash
    ) {
        for (uint256 i = latestPredictionId; i > 0; i--) {
            PredictionData storage prediction = predictions[i];
            if (prediction.isActive && 
                (block.timestamp - prediction.timestamp <= PREDICTION_VALIDITY_PERIOD)) {
                return (
                    i,
                    prediction.predictedPrice,
                    prediction.confidence,
                    prediction.timestamp,
                    prediction.analysisHash
                );
            }
        }
        
        revert("No valid prediction found");
    }
    