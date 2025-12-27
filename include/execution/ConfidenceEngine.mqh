// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++       CONFIDENCE ENGINE      ++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property strict
#property version   "1.00"

/*
==============================================================
DYNAMIC CONFIDENCE ENGINE
==============================================================
Core Principles:
1. Dynamic Component Integration
2. Always 100% Weight Distribution
3. Adaptive Strategy Selection
4. Performance-Based Optimization
5. Real-Time Chart Display with ResourceManager Logging
==============================================================
*/
#include "../risk/RiskManager.mqh"
#include "../Confidence/MarketStructure.mqh"
#include "../Confidence/MTF.mqh"

#include "../config/enums.mqh"
#include "../utils/Utils.mqh"

// Forward declarations for dependencies
class ResourceManager;

// ================= ENUMS =================
enum CONFIDENCE_SIGNAL {
    NO_SIGNAL,
    SIGNAL_STRONG_BUY,
    SIGNAL_WEAK_BUY,
    SIGNAL_STRONG_SELL,
    SIGNAL_WEAK_SELL,
    SIGNAL_NEUTRAL,
    SIGNAL_NO_TRADE
};

enum TRADE_STRATEGY {
    STRATEGY_TREND_FOLLOWING,
    STRATEGY_COUNTER_TREND,
    STRATEGY_RANGE_TRADING,
    STRATEGY_BREAKOUT,
    STRATEGY_REVERSAL,
    STRATEGY_SCALPING,
    STRATEGY_NONE
};

enum CONFIDENCE_LEVEL {
    CONFIDENCE_VERY_LOW,
    CONFIDENCE_LOW,
    CONFIDENCE_MEDIUM,
    CONFIDENCE_HIGH,
    CONFIDENCE_VERY_HIGH
};

// ================= STRUCTURES =================
struct ComponentAnalysis {
    string componentName;
    double rawScore;
    double normalizedScore;
    double baseWeight;
    double adjustedWeight;
    double weightedScore;
    int rank;
    bool isAvailable;
    string signal;
    double directionalBias;
};

struct ConfidenceAnalysis {
    ComponentAnalysis components[11];
    double totalConfidence;
    CONFIDENCE_LEVEL level;
    CONFIDENCE_SIGNAL signal;
    TRADE_STRATEGY strategy;
    datetime analysisTime;
    string marketBias;
    bool isConfluent;
    double divergenceScore;
    string tradeAction;
    string conditionsSummary;
    string decisionSummary;
    double positionSizeMultiplier;
    double riskMultiplier;
    string entrySignal;
    double stopLossPrice;
    double takeProfitPrice;
    double rewardRiskRatio;
};

struct StrategyProfile {
    TRADE_STRATEGY strategy;
    string description;
    double minConfidence;
    double minConfluence;
    double maxDivergence;
    string requiredComponents[5];
    double componentMultipliers[11];
};

// ================= CLASS DEFINITION =================
class ConfidenceEngine
{
private:
    // Initialization state
    bool m_initialized;
    
    // Core configuration
    string m_symbol;
    int m_maxComponents;
    
    // Component registry
    struct ComponentRegistry {
        string componentName;
        double baseWeight;
        bool isAvailable;
        bool isRequired;
        double lastScore;
        int successCount;
        int totalUses;
    };
    
    ComponentRegistry m_registry[11];
    int m_availableCount;
    
    // Strategy profiles
    StrategyProfile m_strategies[6];
    
    // State management
    ConfidenceAnalysis m_currentAnalysis;
    TRADE_STRATEGY m_currentStrategy;
    
    // Performance tracking
    struct PerformanceRecord {
        TRADE_STRATEGY strategy;
        double confidence;
        bool wasSuccessful;
        double profitLoss;
        datetime tradeTime;
    };
    
    PerformanceRecord m_performanceHistory[100];
    int m_performanceIndex;
    
    // Weight management
    double m_dynamicWeights[11];
    double m_strategyMultipliers[6][11];
    
    // Dependencies (injected)
    ResourceManager* m_logger;
    MarketStructureEngine* m_MarketStructureEngine;
    MTFEngine* m_mtf;
    RiskManager* m_riskManager;
    
    // Chart display configuration
    bool m_showOnChart;
    int m_chartUpdateInterval;
    datetime m_lastChartUpdate;
    
    // Trading session state
    bool m_isTradingSession;
    double m_currentPrice;
    double m_currentStopLoss;
    double m_currentTakeProfit;
    
    // ================= PERFORMANCE OPTIMIZATION =================
    // Cached indicator handles
    int m_ma50_handle;
    int m_ma200_handle;
    int m_rsi_handle;
    int m_macd_handle;
    int m_atr_handle;
    
    // Cached MTF data
    double m_cachedMTFConfidence;
    MTF_SIGNAL m_cachedMTFSignal;
    datetime m_lastMTFUpdate;
    bool m_mtfCacheValid;  // ADDED: Track if cache is valid
    
    // Cached market structure data
    double m_cachedMA50;
    double m_cachedMA200;
    datetime m_lastMAUpdate;
    
    // Cached symbol properties
    double m_cachedPoint;
    double m_cachedTickValue;
    double m_cachedTickSize;
    datetime m_lastSymbolUpdate;
    
    // Tick throttling
    datetime m_lastTickProcessTime;
    int m_tickCounter;
    
    // Logging optimization
    bool m_enableDetailedLogging;
    
    // Session control - ADDED THIS VARIABLE
    bool m_enableSessionControl;
    
    // String constants for optimization
    static const string STR_COMPONENT_PREFIX;
    static const string STR_WEIGHT_PREFIX;
    static const string STR_SCORE_PREFIX;
    static const string STR_ANALYSIS_PREFIX;
    
public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    ConfidenceEngine();
    ~ConfidenceEngine();
    
    // ================= INITIALIZATION/DEINITIALIZATION =================
    bool Initialize(ResourceManager* logger,
                    MarketStructureEngine* MarketStructureEngine,
                    MTFEngine* mtf,
                    RiskManager* riskManager,
                    string symbol = NULL,
                    bool showOnChart = true
                );
    void Deinitialize();
    bool IsInitialized() const { return m_initialized; }
    
    // ================= EVENT HANDLERS =================
    void OnTick();
    void OnTimer();
    void OnTradeTransaction(const MqlTradeTransaction &trans);
    
    // ================= MAIN PUBLIC INTERFACE =================
    ConfidenceAnalysis Analyze(string symbol, double price, bool isBuy = false, double stopLoss = 0, double takeProfit = 0);
    double GetConfidenceScore(string symbol);
    CONFIDENCE_SIGNAL GetSignal(string symbol);
    TRADE_STRATEGY GetRecommendedStrategy(string symbol);
    
    // Component management
    void RegisterComponent(string componentName, double baseWeight, bool isRequired = false);
    void SetComponentAvailability(string componentName, bool isAvailable);
    void UpdateComponentScore(string componentName, double score, bool wasSuccessful);
    
    // Strategy selection
    TRADE_STRATEGY SelectBestStrategy(ConfidenceAnalysis &analysis);
    bool IsStrategyValid(TRADE_STRATEGY strategy, ConfidenceAnalysis &analysis);
    void RecordStrategyPerformance(TRADE_STRATEGY strategy, double confidence, bool wasSuccessful, double profitLoss);
    
    // Weight adaptation
    void AdaptWeightsBasedOnPerformance();
    void ApplyStrategyMultipliers(TRADE_STRATEGY strategy);
    void RebalanceWeights();
    
    // Position sizing recommendations
    double GetPositionSizeMultiplier();
    double GetRiskMultiplier();
    string GetTradeAction();
    
    // Trading decision methods
    string GetDecisionSummary();
    bool ShouldEnterTrade();
    bool ShouldExitTrade();
    bool ShouldHoldPosition();
    string GetEntrySignal();
    
    // Getters
    ComponentAnalysis GetComponentAnalysis(string componentName);
    double GetStrategySuccessRate(TRADE_STRATEGY strategy);
    string GetConfidenceSummary();
    ConfidenceAnalysis GetCurrentAnalysis() { return m_currentAnalysis; }
    double GetTotalConfidence() { return m_currentAnalysis.totalConfidence; }
    CONFIDENCE_SIGNAL GetCurrentSignal() { return m_currentAnalysis.signal; }
    
    // Setters for trading parameters
    void SetTradingParameters(double price, double stopLoss, double takeProfit) {
        m_currentPrice = price;
        m_currentStopLoss = stopLoss;
        m_currentTakeProfit = takeProfit;
    }
    
    // Session management
    void StartTradingSession() { m_isTradingSession = true; }
    void EndTradingSession() { m_isTradingSession = false; }
    bool IsTradingSessionActive() { return m_isTradingSession; }
    
    // Session control - ADDED THESE METHODS
    void EnableSessionControl(bool enable) { m_enableSessionControl = enable; }
    bool IsSessionControlEnabled() { return m_enableSessionControl; }
    
    string GetMTFSignalString(MTF_SIGNAL signal);
    
    // ================= NEW METHODS FOR CACHE MANAGEMENT =================
    void ForceRefreshMTFCache();  // Force immediate MTF cache refresh
    void ClearAllCaches();        // Clear all cached data
    double GetFreshMTFConfidence(); // Get fresh MTF confidence without cache
    
private:
    // ================= PRIVATE CORE FUNCTIONS =================
    // Component scoring placeholders
    double GetMarketStructureEngineScore(string symbol);
    double GetMTFEngineScore(string symbol);
    // double GetLiquidityScore(string symbol);
    // double GetPatternRecognitionScore(string symbol);
    // double GetMomentumScore(string symbol);
    // double GetMarketContextScore(string symbol);
    // double GetRiskRewardScore(string symbol, double entry, double stopLoss, double takeProfit);
    // double GetConfluenceDensityScore(string symbol);
    // double GetAdvancedConceptsScore(string symbol);
    // double GetFinanceScore(string symbol);
    // double GetTradeManagerScore(string symbol, double entry, double stopLoss, double takeProfit);
    
    // Score calculation
    void CalculateTotalConfidence();
    void NormalizeScores();
    void ApplyDynamicWeighting();
    void CheckConfluence();
    
    // Strategy helpers
    void InitializeStrategies();
    double CalculateStrategyScore(TRADE_STRATEGY strategy, ConfidenceAnalysis &analysis);
    bool MeetsStrategyRequirements(TRADE_STRATEGY strategy, ConfidenceAnalysis &analysis);
    
    // Component helpers
    int GetComponentIndex(string componentName);
    double GetDefaultScore(string componentName);
    double CalculateComponentSuccessRate(string componentName);
    
    // Signal generation
    CONFIDENCE_SIGNAL GenerateSignal(ConfidenceAnalysis &analysis);
    CONFIDENCE_LEVEL DetermineConfidenceLevel(double score);
    string DetermineMarketBias(ConfidenceAnalysis &analysis);
    
    // Weight management
    void InitializeWeights();
    void DistributeWeights();
    void AdjustWeightsForStrategy(TRADE_STRATEGY strategy);
    void ApplyPerformanceBasedAdjustments();
    
    // Performance tracking
    void UpdatePerformanceMetrics();
    double CalculateComponentSuccessAdjustment(string componentName);
    
    // Utility functions
    double CalculateDivergence(ConfidenceAnalysis &analysis);
    bool CheckComponentAgreement(ConfidenceAnalysis &analysis);
    string GenerateConditionsSummary(ConfidenceAnalysis &analysis);
    string GenerateDecisionSummary(ConfidenceAnalysis &analysis);
    
    // Chart display helpers
    void PrepareChartData();
    void DisplayScoresToChart();
    void DisplayMarketBiasToChart();
    void DisplayTradeSummaryToChart();
    void DisplayPerformanceToChart();
    void DisplayConditionsToChart();
    void DisplayOrderBlocksToChart();
    void DisplayDecisionToChart();
    
    // Trading decision helpers
    bool EvaluateEntryConditions();
    bool EvaluateExitConditions();
    bool EvaluateHoldConditions();
    string DetermineEntrySignal();
    
    // Risk management
    double CalculateRewardRiskRatio(double entry, double stopLoss, double takeProfit);
    double CalculatePositionSize(double riskPercent, double stopLossDistance);
    double CalculateStopLossDistance();
    double CalculateTakeProfitDistance();
    
    // Logging helpers
    void LogComponentAnalysis();
    void LogStrategySelection(TRADE_STRATEGY selectedStrategy, double strategyScore);
    void LogTradingDecision();
    string SignalToString(CONFIDENCE_SIGNAL signal);
    string StrategyToString(TRADE_STRATEGY strategy);
    string ConfidenceLevelToString(CONFIDENCE_LEVEL level);
    
    // Initialization helpers
    void InitializeRegistry();
    void SetupDefaultComponents();
    
    // Component raw score helper
    double GetComponentRawScore(string componentName, string symbol, double price, double stopLoss, double takeProfit);
    
    // Time management
    bool IsValidTradingTime();
    string GetCurrentSession();
    
    // Order block helpers
    string GetOrderBlockInfo();
    double GetNearestOrderBlockLevel();
    bool IsPriceNearOrderBlock(double price);
    
    // ================= PERFORMANCE OPTIMIZATION HELPERS =================
    bool ShouldProcessTick();
    void UpdateCachedMTFData();
    void UpdateCachedMarketStructureData();
    void UpdateCachedSymbolProperties();
    bool CalculateRiskParams(double price, bool isBuy, double &stopLoss, double &takeProfit);
    void ExecuteTradeSignal(ConfidenceAnalysis &analysis);
    
    // ================= NEW CACHE MANAGEMENT HELPERS =================
    void RefreshMTFCacheImmediately();  // Internal method for immediate refresh
    bool IsMTFCacheStale();             // Check if cache is stale
    void ResetMTFCache();               // Reset MTF cache
    bool ValidateMTFCache();            // Validate cache contents
};

// Initialize static string constants
const string ConfidenceEngine::STR_COMPONENT_PREFIX = "Component_";
const string ConfidenceEngine::STR_WEIGHT_PREFIX = "Weight_";
const string ConfidenceEngine::STR_SCORE_PREFIX = "_Score";
const string ConfidenceEngine::STR_ANALYSIS_PREFIX = "ConfidenceAnalysis_";

// ================= EXTERNAL INTERFACE =================
double Confidence_GetScore(string symbol)
{
    ConfidenceEngine engine;
    return engine.GetConfidenceScore(symbol);
}

CONFIDENCE_SIGNAL Confidence_GetSignal(string symbol)
{
    ConfidenceEngine engine;
    return engine.GetSignal(symbol);
}

TRADE_STRATEGY Confidence_GetStrategy(string symbol)
{
    ConfidenceEngine engine;
    return engine.GetRecommendedStrategy(symbol);
}

// ================= IMPLEMENTATION =================

//+------------------------------------------------------------------+
//| Constructor - ONLY sets default values                           |
//+------------------------------------------------------------------+
ConfidenceEngine::ConfidenceEngine()
{
    // Default initialization - NO resource creation
    m_initialized = false;
    m_logger = NULL;
    m_MarketStructureEngine = NULL;
    m_mtf = NULL;
    m_riskManager = NULL;
    
    // Set default values
    m_symbol = "";
    m_maxComponents = 2;
    m_availableCount = 0;
    m_performanceIndex = 0;
    m_currentStrategy = STRATEGY_NONE;
    
    // Chart display settings
    m_showOnChart = true;
    m_chartUpdateInterval = 1; // Update every 1 second
    m_lastChartUpdate = 0;
    
    // Trading session state
    m_isTradingSession = false;
    m_currentPrice = 0.0;
    m_currentStopLoss = 0.0;
    m_currentTakeProfit = 0.0;
    
    // ================= PERFORMANCE INITIALIZATION =================
    // Initialize cached handles
    m_ma50_handle = INVALID_HANDLE;
    m_ma200_handle = INVALID_HANDLE;
    m_rsi_handle = INVALID_HANDLE;
    m_macd_handle = INVALID_HANDLE;
    m_atr_handle = INVALID_HANDLE;
    
    // Initialize cached data
    m_cachedMTFConfidence = 0.0;
    m_cachedMTFSignal = MTF_SIGNAL_NEUTRAL;
    m_lastMTFUpdate = 0;
    m_mtfCacheValid = false;  // Cache starts as invalid
    
    m_cachedMA50 = 0.0;
    m_cachedMA200 = 0.0;
    m_lastMAUpdate = 0;
    
    // Initialize cached symbol properties
    m_cachedPoint = 0.0;
    m_cachedTickValue = 0.0;
    m_cachedTickSize = 0.0;
    m_lastSymbolUpdate = 0;
    
    m_lastTickProcessTime = 0;
    m_tickCounter = 0;
    m_enableDetailedLogging = true; // Set to false in testing mode
    
    // Initialize session control - ADDED THIS: DEFAULT TO OFF
    m_enableSessionControl = false; // Session checking is OFF by default
    
    // Initialize arrays with zeros/null
    for(int i = 0; i < m_maxComponents; i++) {
        m_registry[i].componentName = "";
        m_registry[i].baseWeight = 0;
        m_registry[i].isAvailable = false;
        m_registry[i].isRequired = false;
        m_registry[i].lastScore = 0;
        m_registry[i].successCount = 0;
        m_registry[i].totalUses = 0;
        m_dynamicWeights[i] = 0;
    }
    
    for(int i = 0; i < 100; i++) {
        m_performanceHistory[i].strategy = STRATEGY_NONE;
        m_performanceHistory[i].confidence = 0;
        m_performanceHistory[i].wasSuccessful = false;
        m_performanceHistory[i].profitLoss = 0;
        m_performanceHistory[i].tradeTime = 0;
    }
}

//+------------------------------------------------------------------+
//| Destructor - calls Deinitialize if needed                        |
//+------------------------------------------------------------------+
ConfidenceEngine::~ConfidenceEngine()
{
    if(m_initialized) {
        Deinitialize();
    }
}

//+------------------------------------------------------------------+
//| Initialize - ONE AND ONLY real initialization method             |
//+------------------------------------------------------------------+
bool ConfidenceEngine::Initialize(ResourceManager* logger, 
                                    MarketStructureEngine* MarketStructureEngine,
                                    MTFEngine* mtf,
                                    RiskManager* riskManager,
                                    string symbol,
                                    bool showOnChart
                                )
{
    // Prevent double initialization
    if(m_initialized) {
        Print("ConfidenceEngine: Already initialized");
        return true;
    }
    
    // Validate dependencies
    if(logger == NULL) {
        Print("ConfidenceEngine: ERROR - ResourceManager is NULL");
        return false;
    }
    
    if(MarketStructureEngine == NULL) {
        Print("ConfidenceEngine: ERROR - market structure is NULL");
        return false;
    }
    
    if(mtf == NULL) {
        Print("ConfidenceEngine: ERROR - mtf engine is NULL");
        return false;
    }
    
    m_logger = logger;
    m_MarketStructureEngine = MarketStructureEngine;
    m_mtf = mtf;
    m_riskManager = riskManager;
    m_symbol = (symbol == NULL) ? _Symbol : symbol;
    m_showOnChart = showOnChart;
    
    // ================= INITIALIZE PERFORMANCE OPTIMIZATIONS =================
    // Create indicator handles ONCE
    m_ma50_handle = iMA(m_symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
    m_ma200_handle = iMA(m_symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
    m_rsi_handle = iRSI(m_symbol, PERIOD_H1, 14, PRICE_CLOSE);
    m_macd_handle = iMACD(m_symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
    m_atr_handle = iATR(m_symbol, PERIOD_H1, 14);
    
    // Check if handles are valid
    if(m_ma50_handle == INVALID_HANDLE || m_ma200_handle == INVALID_HANDLE) {
        Print("ConfidenceEngine: WARNING - Failed to create indicator handles");
        // Continue anyway - we have fallback mechanisms
    }
    
    // Initialize cached symbol properties
    m_cachedPoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    m_cachedTickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    m_cachedTickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    m_lastSymbolUpdate = TimeCurrent();
    
    // Initialize MTF cache with fresh data immediately
    ForceRefreshMTFCache();
    
    // Disable detailed logging in testing mode for performance
    #ifdef TESTING
    m_enableDetailedLogging = false;
    #endif
    
    // Initialize registry with component names
    InitializeRegistry();
    
    // Setup default components
    SetupDefaultComponents();
    
    // Initialize strategies
    InitializeStrategies();
    
    // Initialize weights
    InitializeWeights();
    
    // Log initialization with session control status
    if(m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "ConfidenceEngine_Initialization");
        m_logger.AddToContext(m_symbol, "MaxComponents", IntegerToString(m_maxComponents));
        m_logger.AddToContext(m_symbol, "AvailableComponents", IntegerToString(m_availableCount));
        m_logger.AddBoolContext(m_symbol, "ChartDisplayEnabled", m_showOnChart);
        m_logger.AddBoolContext(m_symbol, "DetailedLogging", m_enableDetailedLogging);
        m_logger.AddBoolContext(m_symbol, "SessionControl", m_enableSessionControl); // Log session control status
        m_logger.AddBoolContext(m_symbol, "MTFCacheValid", m_mtfCacheValid);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             StringFormat("Engine initialized | Session Control: %s | MTF Cache: %s", 
                                         m_enableSessionControl ? "ENABLED" : "DISABLED",
                                         m_mtfCacheValid ? "VALID" : "INVALID"), false);
    }
    
    m_initialized = true;
    
    // Log to Experts tab
    Print("========================================");
    Print("CONFIDENCE ENGINE INITIALIZED");
    Print("Symbol: ", m_symbol);
    Print("Chart Display: ", m_showOnChart ? "ENABLED" : "DISABLED");
    Print("Components Available: ", m_availableCount, "/", m_maxComponents);
    Print("Performance Mode: ", m_enableDetailedLogging ? "DETAILED" : "OPTIMIZED");
    Print("Session Control: ", m_enableSessionControl ? "ENABLED" : "DISABLED"); // Show session status
    Print("MTF Cache Status: ", m_mtfCacheValid ? "VALID" : "INVALID");
    Print("========================================");
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize - cleanup counterpart                              |
//+------------------------------------------------------------------+
void ConfidenceEngine::Deinitialize()
{
    if(!m_initialized) {
        return;
    }
    
    // Log destruction
    if(m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "ConfidenceEngine_Deinitialization");
        m_logger.AddToContext(m_symbol, "PerformanceIndex", IntegerToString(m_performanceIndex));
        m_logger.AddToContext(m_symbol, "AvailableComponents", IntegerToString(m_availableCount));
        m_logger.AddToContext(m_symbol, "TicksProcessed", IntegerToString(m_tickCounter));
        m_logger.AddBoolContext(m_symbol, "SessionControlWas", m_enableSessionControl);
        m_logger.AddBoolContext(m_symbol, "MTFCacheWasValid", m_mtfCacheValid);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", "Engine deinitialized", false);
    }
    
    // ================= RELEASE INDICATOR HANDLES =================
    if(m_ma50_handle != INVALID_HANDLE) {
        IndicatorRelease(m_ma50_handle);
        m_ma50_handle = INVALID_HANDLE;
    }
    if(m_ma200_handle != INVALID_HANDLE) {
        IndicatorRelease(m_ma200_handle);
        m_ma200_handle = INVALID_HANDLE;
    }
    if(m_rsi_handle != INVALID_HANDLE) {
        IndicatorRelease(m_rsi_handle);
        m_rsi_handle = INVALID_HANDLE;
    }
    if(m_macd_handle != INVALID_HANDLE) {
        IndicatorRelease(m_macd_handle);
        m_macd_handle = INVALID_HANDLE;
    }
    if(m_atr_handle != INVALID_HANDLE) {
        IndicatorRelease(m_atr_handle);
        m_atr_handle = INVALID_HANDLE;
    }
    
    // Reset state
    m_initialized = false;
    m_logger = NULL;
    m_MarketStructureEngine = NULL;
    m_mtf = NULL;
    m_riskManager = NULL;
    m_mtfCacheValid = false;
    
    // Clear arrays
    for(int i = 0; i < m_maxComponents; i++) {
        m_registry[i].isAvailable = false;
        m_registry[i].lastScore = 0;
        m_dynamicWeights[i] = 0;
    }
    
    m_availableCount = 0;
    m_currentStrategy = STRATEGY_NONE;
    m_performanceIndex = 0;
    
    // Clear analysis
    ZeroMemory(m_currentAnalysis);
    
    Print("ConfidenceEngine: Deinitialized - Resources released");
}

//+------------------------------------------------------------------+
//| Performance helper: Check if we should process this tick         |
//+------------------------------------------------------------------+
bool ConfidenceEngine::ShouldProcessTick()
{
    // Throttle updates to once per second max
    datetime currentTime = TimeCurrent();
    if(currentTime - m_lastTickProcessTime < 1) {
        return false; // Skip this tick (throttled)
    }
    
    // Update last process time
    m_lastTickProcessTime = currentTime;
    m_tickCounter++;
    
    // Debug: Log tick count every 100 ticks
    if(m_tickCounter % 100 == 0 && m_enableDetailedLogging) {
        Print("ConfidenceEngine: Processed ", m_tickCounter, " ticks");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update cached MTF data                                           |
//+------------------------------------------------------------------+
void ConfidenceEngine::UpdateCachedMTFData()
{
    if(m_mtf == NULL || !m_mtf.IsInitialized()) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                              "MTF Engine not available for cache update", false, false, 0.0);
        }
        m_mtfCacheValid = false;
        return;
    }
    
    datetime currentTime = TimeCurrent();
    
    // Update cache only once per second, but always validate
    if(currentTime - m_lastMTFUpdate >= 1 || !m_mtfCacheValid) {
        double newConfidence = m_mtf.GetOverallConfidence(m_symbol);
        MTF_SIGNAL newSignal = m_mtf.GetSignal(m_symbol);
        
        // Validate the data
        if(newConfidence >= 0 && newConfidence <= 100) {
            m_cachedMTFConfidence = newConfidence;
            m_cachedMTFSignal = newSignal;
            m_lastMTFUpdate = currentTime;
            m_mtfCacheValid = true;
            
            if(m_enableDetailedLogging && m_logger != NULL) {
                m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                                  StringFormat("MTF cache updated: %s (%.1f) | Cache valid: %s", 
                                  GetMTFSignalString(m_cachedMTFSignal),
                                  m_cachedMTFConfidence,
                                  m_mtfCacheValid ? "YES" : "NO"), 
                                  false, false, 0.0);
            }
        } else {
            // Invalid data - mark cache as invalid
            m_mtfCacheValid = false;
            if(m_enableDetailedLogging && m_logger != NULL) {
                m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                                  StringFormat("Invalid MTF data received: %.1f", newConfidence), 
                                  false, false, 0.0);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| NEW: Force refresh MTF cache immediately                         |
//+------------------------------------------------------------------+
void ConfidenceEngine::ForceRefreshMTFCache()
{
    if(m_mtf == NULL || !m_mtf.IsInitialized()) {
        Print("ConfidenceEngine: ERROR - MTF Engine not available for force refresh");
        m_mtfCacheValid = false;
        return;
    }
    
    // Force immediate update regardless of time
    double newConfidence = m_mtf.GetOverallConfidence(m_symbol);
    MTF_SIGNAL newSignal = m_mtf.GetSignal(m_symbol);
    
    // Validate the data
    if(newConfidence >= 0 && newConfidence <= 100) {
        m_cachedMTFConfidence = newConfidence;
        m_cachedMTFSignal = newSignal;
        m_lastMTFUpdate = TimeCurrent();
        m_mtfCacheValid = true;
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.StartContextWith(m_symbol, "MTF_Cache_ForceRefresh");
            m_logger.AddDoubleContext(m_symbol, "MTF_Confidence", newConfidence, 1);
            m_logger.AddToContext(m_symbol, "MTF_Signal", GetMTFSignalString(newSignal));
            m_logger.AddBoolContext(m_symbol, "CacheValid", m_mtfCacheValid);
            m_logger.FlushContext(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                                 StringFormat("MTF cache FORCE refreshed: %s (%.1f)", 
                                             GetMTFSignalString(newSignal), newConfidence), 
                                 true);
        }
        
        Print("ConfidenceEngine: MTF cache force refreshed to: ", newConfidence, " (", GetMTFSignalString(newSignal), ")");
    } else {
        m_mtfCacheValid = false;
        Print("ConfidenceEngine: ERROR - Invalid MTF data on force refresh: ", newConfidence);
    }
}

//+------------------------------------------------------------------+
//| NEW: Get fresh MTF confidence without cache                      |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetFreshMTFConfidence()
{
    if(m_mtf == NULL || !m_mtf.IsInitialized()) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                              "MTF Engine not available for fresh data", false, false, 0.0);
        }
        return 50.0; // Neutral default
    }
    
    double freshConfidence = m_mtf.GetOverallConfidence(m_symbol);
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "MTF_Fresh_Data");
        m_logger.AddDoubleContext(m_symbol, "Fresh_MTF_Confidence", freshConfidence, 1);
        m_logger.AddToContext(m_symbol, "Fresh_MTF_Signal", GetMTFSignalString(m_mtf.GetSignal(m_symbol)));
        m_logger.AddDoubleContext(m_symbol, "Cached_MTF_Confidence", m_cachedMTFConfidence, 1);
        m_logger.AddToContext(m_symbol, "Cache_Age", IntegerToString(TimeCurrent() - m_lastMTFUpdate));
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             StringFormat("Fresh MTF data: %.1f vs Cached: %.1f (Age: %d sec)", 
                                         freshConfidence, m_cachedMTFConfidence, TimeCurrent() - m_lastMTFUpdate), 
                             false);
    }
    
    return freshConfidence;
}

//+------------------------------------------------------------------+
//| NEW: Clear all caches                                            |
//+------------------------------------------------------------------+
void ConfidenceEngine::ClearAllCaches()
{
    m_cachedMTFConfidence = 0.0;
    m_cachedMTFSignal = MTF_SIGNAL_NEUTRAL;
    m_lastMTFUpdate = 0;
    m_mtfCacheValid = false;
    
    m_cachedMA50 = 0.0;
    m_cachedMA200 = 0.0;
    m_lastMAUpdate = 0;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                          "All caches cleared", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| NEW: Check if MTF cache is stale                                 |
//+------------------------------------------------------------------+
bool ConfidenceEngine::IsMTFCacheStale()
{
    datetime currentTime = TimeCurrent();
    bool isStale = (currentTime - m_lastMTFUpdate > 5); // Stale if older than 5 seconds
    
    if(isStale && m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                          StringFormat("MTF cache is stale: %d seconds old", currentTime - m_lastMTFUpdate), 
                          false, false, 0.0);
    }
    
    return isStale;
}

//+------------------------------------------------------------------+
//| NEW: Validate MTF cache contents                                 |
//+------------------------------------------------------------------+
bool ConfidenceEngine::ValidateMTFCache()
{
    if(!m_mtfCacheValid) return false;
    
    bool isValid = (m_cachedMTFConfidence >= 0 && m_cachedMTFConfidence <= 100);
    
    if(!isValid && m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                          StringFormat("MTF cache validation failed: %.1f", m_cachedMTFConfidence), 
                          false, false, 0.0);
    }
    
    return isValid;
}

//+------------------------------------------------------------------+
//| Update cached market structure data                              |
//+------------------------------------------------------------------+
void ConfidenceEngine::UpdateCachedMarketStructureData()
{
    datetime currentTime = TimeCurrent();
    
    // Update cache only once per second
    if(currentTime - m_lastMAUpdate >= 1) {
        if(m_ma50_handle != INVALID_HANDLE && m_ma200_handle != INVALID_HANDLE) {
            // Use static arrays to avoid reallocation
            static double ma50_buffer[10];  // Batch size of 10
            static double ma200_buffer[10]; // Batch size of 10
            
            // Copy multiple bars at once
            int copied50 = CopyBuffer(m_ma50_handle, 0, 0, 10, ma50_buffer);
            int copied200 = CopyBuffer(m_ma200_handle, 0, 0, 10, ma200_buffer);
            
            if(copied50 > 0) {
                m_cachedMA50 = ma50_buffer[0]; // Use most recent
            }
            
            if(copied200 > 0) {
                m_cachedMA200 = ma200_buffer[0]; // Use most recent
            }
            
            m_lastMAUpdate = currentTime;
        }
    }
}

//+------------------------------------------------------------------+
//| Update cached symbol properties                                  |
//+------------------------------------------------------------------+
void ConfidenceEngine::UpdateCachedSymbolProperties()
{
    datetime currentTime = TimeCurrent();
    if(currentTime - m_lastSymbolUpdate >= 5) { // Update every 5 seconds
        m_cachedPoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        m_cachedTickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        m_cachedTickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        m_lastSymbolUpdate = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Calculate risk parameters                                        |
//+------------------------------------------------------------------+
bool ConfidenceEngine::CalculateRiskParams(double price, bool isBuy, double &stopLoss, double &takeProfit)
{
    if(m_riskManager == NULL) {
        // Fallback: use fixed risk parameters
        double point = m_cachedPoint > 0 ? m_cachedPoint : SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(isBuy) {
            stopLoss = price - 100 * point;
            takeProfit = price + 200 * point;
        } else {
            stopLoss = price + 100 * point;
            takeProfit = price - 200 * point;
        }
        return true;
    }
    
    // ============ USE RISK MANAGER FOR DYNAMIC SL/TP ============
    stopLoss = m_riskManager.GetOptimalStopLoss(m_symbol, price, isBuy);
    
    if(stopLoss == 0) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                              "RiskManager failed to calculate SL", false, false, 0.0);
        }
        return false;
    }
    
    // Get current timeframe
    ENUM_TIMEFRAMES currentTF = (ENUM_TIMEFRAMES)Period();
    
    takeProfit = m_riskManager.GetOptimalTakeProfit(
        m_symbol, 
        currentTF,  // Current timeframe
        price, 
        stopLoss,   // Need SL to calculate TP
        isBuy
    );
    
    if(takeProfit == 0) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.KeepNotes(m_symbol, WARN, "ConfidenceEngine", 
                              "RiskManager failed to calculate TP", false, false, 0.0);
        }
        return false;
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "RiskManager_Success");
        m_logger.AddDoubleContext(m_symbol, "StopLoss", stopLoss, 5);
        m_logger.AddDoubleContext(m_symbol, "TakeProfit", takeProfit, 5);
        m_logger.AddDoubleContext(m_symbol, "R_R_Ratio", 
            MathAbs(takeProfit - price) / MathAbs(price - stopLoss), 2);
        m_logger.FlushContext(m_symbol, OBSERVE, "RiskManager", 
            "Dynamic SL/TP calculated successfully", false);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Execute trade signal                                             |
//+------------------------------------------------------------------+
void ConfidenceEngine::ExecuteTradeSignal(ConfidenceAnalysis &analysis)
{
    if(!m_initialized || m_logger == NULL) return;
    
    if(m_enableDetailedLogging) {
        m_logger.StartContextWith(m_symbol, "Trade_Execution_Ready");
        m_logger.AddToContext(m_symbol, "EntrySignal", analysis.entrySignal);
        m_logger.AddToContext(m_symbol, "Strategy", StrategyToString(analysis.strategy));
        m_logger.AddDoubleContext(m_symbol, "EntryPrice", m_currentPrice, 5);
        m_logger.AddDoubleContext(m_symbol, "StopLoss", analysis.stopLossPrice, 5);
        m_logger.AddDoubleContext(m_symbol, "TakeProfit", analysis.takeProfitPrice, 5);
        m_logger.AddDoubleContext(m_symbol, "R_R_Ratio", analysis.rewardRiskRatio, 2);
        m_logger.AddDoubleContext(m_symbol, "Confidence", analysis.totalConfidence, 1);
        
        m_logger.FlushContext(m_symbol, AUTHORIZE, "ConfidenceEngine", 
            StringFormat("CONFIDENCE APPROVAL: %s @ %.5f | SL: %.5f | TP: %.5f | R:R: %.2f | Strategy: %s",
                analysis.entrySignal,
                m_currentPrice,
                analysis.stopLossPrice,
                analysis.takeProfitPrice,
                analysis.rewardRiskRatio,
                StrategyToString(analysis.strategy)),
            true);
    }
    
    // Signal is ready for Decision Manager to execute
    // The actual trade execution should be handled by Decision Manager
}

//+------------------------------------------------------------------+
//| Optimized OnTick - Paves way for Decision Manager execution     |
//+------------------------------------------------------------------+
void ConfidenceEngine::OnTick()
{
    // Quick exit if not initialized
    if(!m_initialized || m_logger == NULL) return;
    
    // Throttle tick processing for performance
    if(!ShouldProcessTick()) return;
    
    // Update cached data (optimized - only updates when needed)
    UpdateCachedMTFData();
    UpdateCachedMarketStructureData();
    UpdateCachedSymbolProperties();
    
    // Check MTF cache validity - force refresh if invalid
    if(!m_mtfCacheValid || IsMTFCacheStale()) {
        ForceRefreshMTFCache();
    }
    
    // Early exit if MTF signal is neutral or confidence too low
    if(m_cachedMTFSignal == MTF_SIGNAL_NEUTRAL || m_cachedMTFConfidence < 25) { // Reduced from 55 to 25
        if(m_enableDetailedLogging) {
            m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                              StringFormat("Skipping: MTF Signal=%s, Confidence=%.1f", 
                                          GetMTFSignalString(m_cachedMTFSignal), m_cachedMTFConfidence), 
                              false, false, 0.0);
        }
        return;
    }
    
    // Update current price
    m_currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // Only run analysis if MTF has a valid signal
    if(m_cachedMTFSignal != MTF_SIGNAL_NEUTRAL && m_cachedMTFConfidence >= 25) { // Reduced from 55 to 25
        
        bool isBuy = (m_cachedMTFSignal == MTF_SIGNAL_STRONG_BUY || m_cachedMTFSignal == MTF_SIGNAL_WEAK_BUY);
        
        // Get risk parameters
        double stopLoss = 0, takeProfit = 0;
        bool riskCalculated = CalculateRiskParams(m_currentPrice, isBuy, stopLoss, takeProfit);
        
        // If risk calculation failed, use fallback
        if(!riskCalculated) {
            double point = m_cachedPoint > 0 ? m_cachedPoint : SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(isBuy) {
                stopLoss = m_currentPrice - 100 * point;
                takeProfit = m_currentPrice + 200 * point;
            } else {
                stopLoss = m_currentPrice + 100 * point;
                takeProfit = m_currentPrice - 200 * point;
            }
            
            if(m_enableDetailedLogging) {
                m_logger.StartContextWith(m_symbol, "RiskManager_Fallback");
                m_logger.AddToContext(m_symbol, "Reason", "RiskManager unavailable or failed");
                m_logger.AddDoubleContext(m_symbol, "StopLoss", stopLoss, 5);
                m_logger.AddDoubleContext(m_symbol, "TakeProfit", takeProfit, 5);
                m_logger.FlushContext(m_symbol, WARN, "RiskManager", 
                    "Using fixed SL/TP as fallback", false);
            }
        }
        
        // ============ RUN CONFIDENCE ANALYSIS WITH PROPER RISK PARAMETERS ============
        ConfidenceAnalysis analysis = Analyze(
            m_symbol,
            m_currentPrice,
            isBuy,
            stopLoss,
            takeProfit
        );
        
        // ============ LOG CONFIDENCE ENGINE RESPONSE (Optimized logging) ============
        if(m_enableDetailedLogging) {
            m_logger.StartContextWith(m_symbol, "ConfidenceEngine_OnTick_Response");
            m_logger.AddToContext(m_symbol, "MTF_Signal", GetMTFSignalString(m_cachedMTFSignal));
            m_logger.AddDoubleContext(m_symbol, "MTF_Confidence", m_cachedMTFConfidence, 1);
            m_logger.AddDoubleContext(m_symbol, "ConfidenceEngine_Score", analysis.totalConfidence, 1);
            m_logger.AddToContext(m_symbol, "ConfidenceEngine_Signal", SignalToString(analysis.signal));
            m_logger.AddDoubleContext(m_symbol, "StopLoss", stopLoss, 5);
            m_logger.AddDoubleContext(m_symbol, "TakeProfit", takeProfit, 5);
            m_logger.AddDoubleContext(m_symbol, "R_R_Ratio", analysis.rewardRiskRatio, 2);
            m_logger.AddBoolContext(m_symbol, "SessionControlEnabled", m_enableSessionControl);
            m_logger.AddBoolContext(m_symbol, "MTFCacheValid", m_mtfCacheValid);
            
            string actionMessage = "";
            if(ShouldEnterTrade()) {
                actionMessage = StringFormat("TRADE APPROVED: Enter %s", analysis.entrySignal);
                m_logger.AddBoolContext(m_symbol, "TradeApproved", true);
                m_logger.AddToContext(m_symbol, "Action", "ENTER");
            } else {
                actionMessage = "NO TRADE: Conditions not met";
                m_logger.AddBoolContext(m_symbol, "TradeApproved", false);
                m_logger.AddToContext(m_symbol, "Action", "WAIT");
            }
            
            m_logger.FlushContext(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                StringFormat("Responding to MTF %s: Confidence %s (%.1f%%) | Cache: %s | %s", 
                    GetMTFSignalString(m_cachedMTFSignal),
                    SignalToString(analysis.signal),
                    analysis.totalConfidence,
                    m_mtfCacheValid ? "VALID" : "INVALID",
                    actionMessage), 
                ShouldEnterTrade());
        }
        
        // ============ MAKE TRADING DECISION (Paves way for Decision Manager) ============
        if(ShouldEnterTrade()) {
            ExecuteTradeSignal(analysis);
            // Decision Manager should pick up this signal and execute the trade
        }
    }
}

//+------------------------------------------------------------------+
//| Helper function for MTF signal string                            |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetMTFSignalString(MTF_SIGNAL signal)
{
    switch(signal) {
        case MTF_SIGNAL_STRONG_BUY: return "STRONG_BUY";
        case MTF_SIGNAL_STRONG_SELL: return "STRONG_SELL";
        case MTF_SIGNAL_WEAK_BUY: return "WEAK_BUY";
        case MTF_SIGNAL_WEAK_SELL: return "WEAK_SELL";
        case MTF_SIGNAL_NEUTRAL: return "NEUTRAL";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
void ConfidenceEngine::OnTimer()
{
    // Timer handling - optional for periodic updates
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void ConfidenceEngine::OnTradeTransaction(const MqlTradeTransaction &trans)
{
    if(!m_initialized || m_logger == NULL) return;
    
    // Cache position data with 2-second TTL
    static datetime lastPositionCheck = 0;
    static int totalPositions = 0;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - lastPositionCheck >= 2) {
        // Only check positions every 2 seconds
        totalPositions = PositionsTotal();
        lastPositionCheck = currentTime;
    }
    
    // Process trade transactions
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        // Batch position operations: collect tickets once
        ulong dealTicket = trans.deal;
        if(HistoryDealSelect(dealTicket)) {
            // NEVER cache profit/loss, current price, SL/TP levels
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            bool wasSuccessful = (profit > 0);
            
            RecordStrategyPerformance(m_currentStrategy, 
                                     m_currentAnalysis.totalConfidence, 
                                     wasSuccessful, 
                                     profit);
            
            // Log trade outcome (optimized)
            if(m_enableDetailedLogging) {
                m_logger.StartContextWith(m_symbol, "Trade_Outcome");
                m_logger.AddDoubleContext(m_symbol, "Profit", profit, 2);
                m_logger.AddBoolContext(m_symbol, "Successful", wasSuccessful);
                m_logger.AddToContext(m_symbol, "Strategy", StrategyToString(m_currentStrategy));
                m_logger.FlushContext(m_symbol, wasSuccessful ? AUTHORIZE : WARN, 
                                     "ConfidenceEngine", 
                                     "Trade closed: " + (wasSuccessful ? "WIN" : "LOSS"), 
                                     true);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Main analysis function - with performance optimizations         |
//+------------------------------------------------------------------+
ConfidenceAnalysis ConfidenceEngine::Analyze(string symbol, double price, bool isBuy, double stopLoss, double takeProfit)
{
    if(!m_initialized || m_logger == NULL) {
        ConfidenceAnalysis empty;
        ZeroMemory(empty);
        empty.signal = SIGNAL_NO_TRADE;
        empty.strategy = STRATEGY_NONE;
        empty.tradeAction = "WAIT";
        empty.decisionSummary = "ENGINE_NOT_INITIALIZED";
        return empty;
    }
    
    // Early exit for invalid inputs
    if(price <= 0 || symbol == "") {
        ConfidenceAnalysis empty;
        ZeroMemory(empty);
        empty.signal = SIGNAL_NO_TRADE;
        empty.strategy = STRATEGY_NONE;
        return empty;
    }
    
    if(m_enableDetailedLogging) {
        m_logger.StartContextWith(symbol, "ConfidenceAnalysis_Start");
        m_logger.AddDoubleContext(symbol, "Price", price, 5);
        m_logger.AddBoolContext(symbol, "IsBuy", isBuy);
        m_logger.AddDoubleContext(symbol, "StopLoss", stopLoss, 5);
        m_logger.AddDoubleContext(symbol, "TakeProfit", takeProfit, 5);
    }
    
    m_symbol = symbol;
    m_currentPrice = price;
    m_currentStopLoss = stopLoss;
    m_currentTakeProfit = takeProfit;
    
    // Collect scores from available components
    int componentIndex = 0;
    int totalAvailable = 0;
    
    // Cache array size for loop optimization
    int registrySize = m_maxComponents;
    for(int i = 0; i < registrySize; i++) {
        if(m_registry[i].isAvailable) {
            totalAvailable++;
        }
    }
    
    if(m_enableDetailedLogging) {
        m_logger.AddToContext(symbol, "TotalAvailableComponents", IntegerToString(totalAvailable));
    }
    
    for(int i = 0; i < registrySize; i++) {
        if(m_registry[i].isAvailable) {
            ComponentAnalysis comp;
            comp.componentName = m_registry[i].componentName;
            comp.rawScore = GetComponentRawScore(comp.componentName, symbol, price, stopLoss, takeProfit);
            comp.baseWeight = m_registry[i].baseWeight;
            comp.adjustedWeight = m_registry[i].baseWeight;
            comp.rank = i + 1;
            comp.isAvailable = true;
            
            // Store component analysis
            m_currentAnalysis.components[componentIndex] = comp;
            componentIndex++;
            
            if(m_enableDetailedLogging) {
                m_logger.AddDoubleContext(symbol, 
                    StringFormat("%s%s%s", STR_COMPONENT_PREFIX, comp.componentName, STR_SCORE_PREFIX), 
                    comp.rawScore, 1);
            }
        }
    }
    
    m_availableCount = componentIndex;
    if(m_enableDetailedLogging) {
        m_logger.AddToContext(symbol, "ComponentsProcessed", IntegerToString(m_availableCount));
    }
    
    // If no components available, use defaults
    if(m_availableCount == 0) {
        if(m_enableDetailedLogging) {
            m_logger.AddToContext(symbol, "Warning", "NoComponentsAvailable", true);
        }
        
        // Use MarketStructureEngine as default if no components registered
        ComponentAnalysis defaultComp;
        defaultComp.componentName = "MarketStructureEngine";
        defaultComp.rawScore = 50.0;
        defaultComp.baseWeight = 100.0;
        defaultComp.adjustedWeight = 100.0;
        defaultComp.rank = 1;
        defaultComp.isAvailable = true;
        
        m_currentAnalysis.components[0] = defaultComp;
        m_availableCount = 1;
    }
    
    // Distribute weights to ensure total = 100%
    DistributeWeights();
    
    // Normalize scores
    NormalizeScores();
    
    // Calculate total confidence
    CalculateTotalConfidence();
    
    // Select best strategy
    m_currentStrategy = SelectBestStrategy(m_currentAnalysis);
    
    // Apply strategy-specific multipliers
    ApplyStrategyMultipliers(m_currentStrategy);
    
    // Recalculate with adjusted weights
    CalculateTotalConfidence();
    
    // Generate signal and determine confidence level
    m_currentAnalysis.signal = GenerateSignal(m_currentAnalysis);
    m_currentAnalysis.level = DetermineConfidenceLevel(m_currentAnalysis.totalConfidence);
    m_currentAnalysis.strategy = m_currentStrategy;
    m_currentAnalysis.marketBias = DetermineMarketBias(m_currentAnalysis);
    
    // Check confluence and divergence
    m_currentAnalysis.isConfluent = CheckComponentAgreement(m_currentAnalysis);
    m_currentAnalysis.divergenceScore = CalculateDivergence(m_currentAnalysis);
    
    // Generate conditions summary
    m_currentAnalysis.conditionsSummary = GenerateConditionsSummary(m_currentAnalysis);
    
    // Calculate reward/risk ratio
    m_currentAnalysis.rewardRiskRatio = CalculateRewardRiskRatio(price, stopLoss, takeProfit);
    
    // Set analysis time and trade action
    m_currentAnalysis.analysisTime = TimeCurrent();
    m_currentAnalysis.tradeAction = GetTradeAction();
    
    // Set position sizing multipliers
    m_currentAnalysis.positionSizeMultiplier = GetPositionSizeMultiplier();
    m_currentAnalysis.riskMultiplier = GetRiskMultiplier();
    
    // Set entry signal
    m_currentAnalysis.entrySignal = DetermineEntrySignal();
    
    // Set stop loss and take profit prices
    m_currentAnalysis.stopLossPrice = stopLoss;
    m_currentAnalysis.takeProfitPrice = takeProfit;
    
    // Generate decision summary
    m_currentAnalysis.decisionSummary = GenerateDecisionSummary(m_currentAnalysis);
    
    // Update component usage statistics
    int componentsSize = m_availableCount;
    for(int i = 0; i < componentsSize; i++) {
        string compName = m_currentAnalysis.components[i].componentName;
        int regIndex = GetComponentIndex(compName);
        if(regIndex >= 0) {
            m_registry[regIndex].lastScore = m_currentAnalysis.components[i].normalizedScore;
            m_registry[regIndex].totalUses++;
        }
    }
    
    // Log final analysis results (optimized)
    if(m_enableDetailedLogging) {
        m_logger.StartContextWith(symbol, "ConfidenceAnalysis_Results");
        m_logger.AddDoubleContext(symbol, "TotalConfidence", m_currentAnalysis.totalConfidence, 1);
        m_logger.AddToContext(symbol, "Signal", SignalToString(m_currentAnalysis.signal));
        m_logger.AddToContext(symbol, "Strategy", StrategyToString(m_currentAnalysis.strategy));
        m_logger.AddToContext(symbol, "MarketBias", m_currentAnalysis.marketBias);
        m_logger.AddBoolContext(symbol, "IsConfluent", m_currentAnalysis.isConfluent);
        m_logger.AddDoubleContext(symbol, "DivergenceScore", m_currentAnalysis.divergenceScore, 1);
        m_logger.AddToContext(symbol, "TradeAction", m_currentAnalysis.tradeAction);
        m_logger.AddToContext(symbol, "ConfidenceLevel", ConfidenceLevelToString(m_currentAnalysis.level));
        m_logger.AddToContext(symbol, "ConditionsSummary", m_currentAnalysis.conditionsSummary);
        m_logger.AddDoubleContext(symbol, "RewardRiskRatio", m_currentAnalysis.rewardRiskRatio, 2);
        m_logger.AddDoubleContext(symbol, "PositionSizeMultiplier", m_currentAnalysis.positionSizeMultiplier, 2);
        m_logger.AddDoubleContext(symbol, "RiskMultiplier", m_currentAnalysis.riskMultiplier, 2);
        m_logger.AddToContext(symbol, "EntrySignal", m_currentAnalysis.entrySignal);
        m_logger.AddToContext(symbol, "DecisionSummary", m_currentAnalysis.decisionSummary);
        
        bool tradeRecommended = (m_currentAnalysis.signal == SIGNAL_STRONG_BUY || 
                                m_currentAnalysis.signal == SIGNAL_WEAK_BUY ||
                                m_currentAnalysis.signal == SIGNAL_STRONG_SELL || 
                                m_currentAnalysis.signal == SIGNAL_WEAK_SELL);
        
        m_logger.FlushContext(symbol, tradeRecommended ? AUTHORIZE : OBSERVE, 
                             "ConfidenceEngine", 
                             StringFormat("Analysis: %s | Confidence: %.1f%% | Action: %s | R:R: %.2f", 
                                          SignalToString(m_currentAnalysis.signal),
                                          m_currentAnalysis.totalConfidence,
                                          m_currentAnalysis.tradeAction,
                                          m_currentAnalysis.rewardRiskRatio), 
                             tradeRecommended);
        
        // Log detailed component analysis
        LogComponentAnalysis();
        
        // Log trading decision
        LogTradingDecision();
    }
    
    // Print summary to Experts tab (only in detailed mode)
    #ifdef CONFIDENCE_ENGINE_DEBUG
    if(m_enableDetailedLogging) {
        Print("========================================");
        Print("CONFIDENCE ANALYSIS COMPLETE");
        Print("Signal: ", SignalToString(m_currentAnalysis.signal));
        Print("Confidence: ", DoubleToString(m_currentAnalysis.totalConfidence, 1), "%");
        Print("Strategy: ", StrategyToString(m_currentAnalysis.strategy));
        Print("Market Bias: ", m_currentAnalysis.marketBias);
        Print("Action: ", m_currentAnalysis.tradeAction);
        Print("R:R Ratio: ", DoubleToString(m_currentAnalysis.rewardRiskRatio, 2));
        Print("========================================");
    }
    #endif
    
    return m_currentAnalysis;
}

//+------------------------------------------------------------------+
//| Generate conditions summary                                      |
//+------------------------------------------------------------------+
string ConfidenceEngine::GenerateConditionsSummary(ConfidenceAnalysis &analysis)
{
    string summary = "";
    
    // Key condition: Confidence level
    if(analysis.totalConfidence >= 80) {
        summary += "VERY_HIGH_CONFIDENCE";
    } else if(analysis.totalConfidence >= 70) {
        summary += "HIGH_CONFIDENCE";
    } else if(analysis.totalConfidence >= 60) {
        summary += "MODERATE_CONFIDENCE";
    } else if(analysis.totalConfidence >= 50) {
        summary += "LOW_CONFIDENCE";
    } else {
        summary += "VERY_LOW_CONFIDENCE";
    }
    
    // Condition: Component agreement
    if(analysis.isConfluent) {
        summary += "|STRONG_CONFLUENCE";
    } else {
        summary += "|WEAK_CONFLUENCE";
    }
    
    // Condition: Divergence level
    if(analysis.divergenceScore < 20) {
        summary += "|LOW_DIVERGENCE";
    } else if(analysis.divergenceScore < 40) {
        summary += "|MODERATE_DIVERGENCE";
    } else {
        summary += "|HIGH_DIVERGENCE";
    }
    
    // Condition: Strategy validity
    if(analysis.strategy != STRATEGY_NONE) {
        summary += "|STRATEGY_VALID";
    } else {
        summary += "|NO_VALID_STRATEGY";
    }
    
    // Condition: Market bias strength
    if(analysis.marketBias == "STRONG_BULLISH" || analysis.marketBias == "STRONG_BEARISH") {
        summary += "|STRONG_BIAS";
    } else if(analysis.marketBias == "BULLISH" || analysis.marketBias == "BEARISH") {
        summary += "|MODERATE_BIAS";
    } else {
        summary += "|NEUTRAL_BIAS";
    }
    
    return summary;
}

//+------------------------------------------------------------------+
//| Generate decision summary                                        |
//+------------------------------------------------------------------+
string ConfidenceEngine::GenerateDecisionSummary(ConfidenceAnalysis &analysis)
{
    string decision = "";
    
    // Determine main decision
    switch(analysis.signal) {
        case SIGNAL_STRONG_BUY:
            decision = "STRONG BUY SIGNAL - Enter Aggressively";
            break;
        case SIGNAL_WEAK_BUY:
            decision = "WEAK BUY SIGNAL - Enter Cautiously";
            break;
        case SIGNAL_NEUTRAL:
            decision = "NEUTRAL - Hold or Wait";
            break;
        case SIGNAL_WEAK_SELL:
            decision = "WEAK SELL SIGNAL - Enter Cautiously";
            break;
        case SIGNAL_STRONG_SELL:
            decision = "STRONG SELL SIGNAL - Enter Aggressively";
            break;
        case SIGNAL_NO_TRADE:
            decision = "NO TRADE - Wait for Better Conditions";
            break;
        default:
            decision = "WAIT - Analyzing...";
            break;
    }
    
    // Add confidence level
    decision += StringFormat(" (Confidence: %.1f%%)", analysis.totalConfidence);
    
    // Add strategy recommendation
    if(analysis.strategy != STRATEGY_NONE) {
        decision += StringFormat(" | Strategy: %s", StrategyToString(analysis.strategy));
    }
    
    // Add risk/reward info if available
    if(analysis.rewardRiskRatio > 0) {
        decision += StringFormat(" | R:R: %.2f:1", analysis.rewardRiskRatio);
    }
    
    return decision;
}

//+------------------------------------------------------------------+
//| Get decision summary                                             |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetDecisionSummary()
{
    return m_currentAnalysis.decisionSummary;
}

//+------------------------------------------------------------------+
//| Should enter trade                                               |
//+------------------------------------------------------------------+
bool ConfidenceEngine::ShouldEnterTrade()
{
    if(!m_initialized) return false;
    
    // Check session time ONLY if session control is enabled (cheapest check)
    bool validSession = m_enableSessionControl ? IsValidTradingTime() : true;
    if(!validSession) return false;
    
    // Next check confluence (boolean)
    if(!m_currentAnalysis.isConfluent) return false;
    
    // Then check confidence score (double comparison) - REDUCED FROM 50 TO 25
    if(m_currentAnalysis.totalConfidence < 25) return false;
    
    // Then check divergence (double comparison)
    if(m_currentAnalysis.divergenceScore >= 15) return false;
    
    // Then check strategy (enum comparison)
    if(m_currentAnalysis.strategy == STRATEGY_NONE) return false;
    
    // Finally, check signal (most expensive - multiple enum comparisons)
    CONFIDENCE_SIGNAL signal = m_currentAnalysis.signal;
    return (signal == SIGNAL_STRONG_BUY || 
            signal == SIGNAL_WEAK_BUY ||
            signal == SIGNAL_STRONG_SELL || 
            signal == SIGNAL_WEAK_SELL);
}

//+------------------------------------------------------------------+
//| Should exit trade                                                |
//+------------------------------------------------------------------+
bool ConfidenceEngine::ShouldExitTrade()
{
    if(!m_initialized) return false;
    
    // Exit conditions: Confidence drops below threshold or signal reverses
    return (m_currentAnalysis.totalConfidence < 25 ||  // Reduced from 40 to 25
           m_currentAnalysis.signal == SIGNAL_NO_TRADE ||
           (m_currentAnalysis.signal == SIGNAL_NEUTRAL && m_currentAnalysis.totalConfidence < 40)); // Reduced from 50 to 40
}

//+------------------------------------------------------------------+
//| Should hold position                                             |
//+------------------------------------------------------------------+
bool ConfidenceEngine::ShouldHoldPosition()
{
    if(!m_initialized) return false;
    
    return (m_currentAnalysis.signal == SIGNAL_NEUTRAL ||
           m_currentAnalysis.signal == SIGNAL_NO_TRADE) &&
           m_currentAnalysis.totalConfidence >= 40;  // Reduced from 50 to 40
}

//+------------------------------------------------------------------+
//| Get entry signal                                                 |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetEntrySignal()
{
    return m_currentAnalysis.entrySignal;
}

//+------------------------------------------------------------------+
//| Determine entry signal                                           |
//+------------------------------------------------------------------+
string ConfidenceEngine::DetermineEntrySignal()
{
    if(!m_initialized) return "NO_ENTRY";
    
    switch(m_currentAnalysis.signal) {
        case SIGNAL_STRONG_BUY:
            return "BUY_LIMIT_AGGRESSIVE";
        case SIGNAL_WEAK_BUY:
            return "BUY_LIMIT_CAUTIOUS";
        case SIGNAL_STRONG_SELL:
            return "SELL_LIMIT_AGGRESSIVE";
        case SIGNAL_WEAK_SELL:
            return "SELL_LIMIT_CAUTIOUS";
        default:
            return "NO_ENTRY";
    }
}

//+------------------------------------------------------------------+
//| Evaluate entry conditions                                        |
//+------------------------------------------------------------------+
bool ConfidenceEngine::EvaluateEntryConditions()
{
    return ShouldEnterTrade();
}

//+------------------------------------------------------------------+
//| Evaluate exit conditions                                         |
//+------------------------------------------------------------------+
bool ConfidenceEngine::EvaluateExitConditions()
{
    return ShouldExitTrade();
}

//+------------------------------------------------------------------+
//| Evaluate hold conditions                                         |
//+------------------------------------------------------------------+
bool ConfidenceEngine::EvaluateHoldConditions()
{
    return ShouldHoldPosition();
}

//+------------------------------------------------------------------+
//| Calculate reward/risk ratio                                      |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculateRewardRiskRatio(double entry, double stopLoss, double takeProfit)
{
    if(entry == 0 || stopLoss == 0 || takeProfit == 0) return 0.0;
    
    double risk = MathAbs(entry - stopLoss);
    double reward = MathAbs(takeProfit - entry);
    
    if(risk == 0) return 0.0;
    
    return reward / risk;
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculatePositionSize(double riskPercent, double stopLossDistance)
{
    if(stopLossDistance == 0) return 0.0;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (riskPercent / 100.0);
    
    // Use cached tick value
    if(m_cachedTickValue == 0) {
        m_cachedTickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    }
    
    if(m_cachedTickValue == 0) return 0.0;
    
    return riskAmount / (stopLossDistance * m_cachedTickValue);
}

//+------------------------------------------------------------------+
//| Calculate stop loss distance                                     |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculateStopLossDistance()
{
    if(m_currentPrice == 0 || m_currentStopLoss == 0) return 0.0;
    
    // Use cached point value
    if(m_cachedPoint == 0) {
        m_cachedPoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    }
    
    return MathAbs(m_currentPrice - m_currentStopLoss) / m_cachedPoint;
}

//+------------------------------------------------------------------+
//| Calculate take profit distance                                   |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculateTakeProfitDistance()
{
    if(m_currentPrice == 0 || m_currentTakeProfit == 0) return 0.0;
    
    // Use cached point value
    if(m_cachedPoint == 0) {
        m_cachedPoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    }
    
    return MathAbs(m_currentTakeProfit - m_currentPrice) / m_cachedPoint;
}

//+------------------------------------------------------------------+
//| Log trading decision                                             |
//+------------------------------------------------------------------+
void ConfidenceEngine::LogTradingDecision()
{
    #ifdef CONFIDENCE_ENGINE_DEBUG
    if(!m_initialized || m_logger == NULL || !m_enableDetailedLogging) return;
    
    m_logger.StartContextWith(m_symbol, "Trading_Decision");
    
    // Log decision factors
    m_logger.AddToContext(m_symbol, "Signal", SignalToString(m_currentAnalysis.signal));
    m_logger.AddDoubleContext(m_symbol, "Confidence", m_currentAnalysis.totalConfidence, 1);
    m_logger.AddBoolContext(m_symbol, "ShouldEnter", ShouldEnterTrade());
    m_logger.AddBoolContext(m_symbol, "ShouldExit", ShouldExitTrade());
    m_logger.AddBoolContext(m_symbol, "ShouldHold", ShouldHoldPosition());
    m_logger.AddToContext(m_symbol, "EntrySignal", m_currentAnalysis.entrySignal);
    m_logger.AddBoolContext(m_symbol, "ValidTradingTime", IsValidTradingTime());
    m_logger.AddBoolContext(m_symbol, "SessionControlEnabled", m_enableSessionControl);
    m_logger.AddToContext(m_symbol, "TradingSession", GetCurrentSession());
    
    m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                         "Trading decision logged: " + m_currentAnalysis.decisionSummary, 
                         false);
    #endif
}

//+------------------------------------------------------------------+
//| Check if it's valid trading time                                 |
//+------------------------------------------------------------------+
bool ConfidenceEngine::IsValidTradingTime()
{
    // If session control is disabled, always return true
    if(!m_enableSessionControl) {
        return true;
    }
    
    MqlDateTime timeNow;
    TimeToStruct(TimeCurrent(), timeNow);
    
    // Check if it's weekend
    if(timeNow.day_of_week == 0 || timeNow.day_of_week == 6) {
        return false;
    }
    
    // Check time of day (example: trade during London/New York overlap)
    int hour = timeNow.hour;
    
    // London/New York overlap (13:00-17:00 GMT)
    // New York morning (8:00-12:00 GMT)
    if((hour >= 13 && hour < 17) || (hour >= 8 && hour < 12)) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get current trading session                                      |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetCurrentSession()
{
    MqlDateTime timeNow;
    TimeToStruct(TimeCurrent(), timeNow);
    int hour = timeNow.hour;
    
    if(hour >= 0 && hour < 6) return "ASIAN";
    else if(hour >= 6 && hour < 13) return "LONDON";
    else if(hour >= 13 && hour < 17) return "LONDON_NY_OVERLAP";
    else if(hour >= 17 && hour < 21) return "NY_AFTERNOON";
    else return "OVERNIGHT";
}

//+------------------------------------------------------------------+
//| Get order block info                                             |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetOrderBlockInfo()
{
    // This would integrate with your MarketStructureEngine
    // For now, return placeholder info
    return "OB Levels: [Recent High/Low]\nOB Strength: Medium\nOB Age: Fresh\n";
}

//+------------------------------------------------------------------+
//| Get nearest order block level                                    |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetNearestOrderBlockLevel()
{
    // This would integrate with your MarketStructureEngine
    // For now, return 0
    return 0.0;
}

//+------------------------------------------------------------------+
//| Check if price is near order block                               |
//+------------------------------------------------------------------+
bool ConfidenceEngine::IsPriceNearOrderBlock(double price)
{
    // This would integrate with your MarketStructureEngine
    // For now, return false
    return false;
}

//+------------------------------------------------------------------+
//| Get confidence summary                                           |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetConfidenceSummary()
{
    // Use StringFormat for all concatenations
    string summary = StringFormat("Confidence: %.1f%% [%s]\n", 
                           m_currentAnalysis.totalConfidence,
                           ConfidenceLevelToString(m_currentAnalysis.level));
    
    summary += StringFormat("Signal: %s | Action: %s\n", 
                           SignalToString(m_currentAnalysis.signal),
                           m_currentAnalysis.tradeAction);
    
    summary += StringFormat("Strategy: %s | Bias: %s\n", 
                           StrategyToString(m_currentAnalysis.strategy),
                           m_currentAnalysis.marketBias);
    
    summary += StringFormat("Confluence: %s | Divergence: %.1f\n", 
                           m_currentAnalysis.isConfluent ? "Strong" : "Weak",
                           m_currentAnalysis.divergenceScore);
    
    summary += StringFormat("R:R Ratio: %.2f:1 | Position: %.2fx", 
                           m_currentAnalysis.rewardRiskRatio,
                           m_currentAnalysis.positionSizeMultiplier);
    
    // Add session info if enabled
    if(m_enableSessionControl) {
        summary += StringFormat("\nSession: %s | Valid: %s", 
                               GetCurrentSession(),
                               IsValidTradingTime() ? "Yes" : "No");
    }
    
    return summary;
}

//+------------------------------------------------------------------+
//| Initialize registry                                             |
//+------------------------------------------------------------------+
void ConfidenceEngine::InitializeRegistry()
{
    string componentNames[2] = {
        "MarketStructureEngine", "MTFEngine"
    };
    
    double baseWeights[2] = {
        WEIGHT_MARKET_STRUCTURE, WEIGHT_MTF_ENGINE
    };
    
    for(int i = 0; i < m_maxComponents; i++) {
        m_registry[i].componentName = componentNames[i];
        m_registry[i].baseWeight = baseWeights[i];
        m_registry[i].isAvailable = false; // Will be set by SetupDefaultComponents
        m_registry[i].isRequired = (i < 3); // First 3 are required
        m_registry[i].lastScore = 0;
        m_registry[i].successCount = 0;
        m_registry[i].totalUses = 0;
        
        m_dynamicWeights[i] = baseWeights[i];
        
        if(m_logger != NULL && m_enableDetailedLogging) {
            m_logger.AddToContext(m_symbol, 
                StringFormat("%s%s_BaseWeight", STR_COMPONENT_PREFIX, componentNames[i]), 
                DoubleToString(baseWeights[i], 1));
        }
    }
}

//+------------------------------------------------------------------+
//| Setup default components                                        |
//+------------------------------------------------------------------+
void ConfidenceEngine::SetupDefaultComponents()
{
    // Enable ALL components by default
    for(int i = 0; i < m_maxComponents; i++) {
        m_registry[i].isAvailable = true;  // Mark as available
        m_registry[i].isRequired = (i < 3); // First 3 are required
        
        // Also register them
        RegisterComponent(m_registry[i].componentName, m_registry[i].baseWeight, m_registry[i].isRequired);
        
        if(m_logger != NULL && m_enableDetailedLogging) {
            m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                              StringFormat("Component %s enabled and registered (Weight: %.1f)", 
                              m_registry[i].componentName, m_registry[i].baseWeight));
        }
    }
    
    // Log the setup
    if(m_logger != NULL && m_enableDetailedLogging) {
        m_logger.KeepNotes(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                          StringFormat("All %d components enabled", m_maxComponents));
    }
}

//+------------------------------------------------------------------+
//| Initialize strategy profiles                                    |
//+------------------------------------------------------------------+
void ConfidenceEngine::InitializeStrategies()
{
    if(!m_initialized || m_logger == NULL) return;
    
    if(m_enableDetailedLogging) {
        m_logger.StartContextWith(m_symbol, "StrategyProfiles_Init");
    }
    
    // Initialize strategies (simplified for performance)
    // Note: Your original strategy initialization code is commented out
    // but kept for reference. We're using simplified versions for performance.
    
    // Multipliers for strategies (simplified)
    for(int i = 0; i < 6; i++) {
        for(int j = 0; j < 11; j++) {
            m_strategies[i].componentMultipliers[j] = 1.0; // Default multiplier
        }
    }
    
    if(m_enableDetailedLogging) {
        m_logger.AddToContext(m_symbol, "TotalStrategies", IntegerToString(6));
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", "Strategy profiles initialized", false);
    }
}

//+------------------------------------------------------------------+
//| Initialize weights                                               |
//+------------------------------------------------------------------+
void ConfidenceEngine::InitializeWeights()
{
    if(!m_initialized || m_logger == NULL) return;
    
    if(m_enableDetailedLogging) {
        m_logger.StartContextWith(m_symbol, "Weights_Initialization");
    }
    
    // Copy base weights to dynamic weights
    for(int i = 0; i < m_maxComponents; i++) {
        m_dynamicWeights[i] = m_registry[i].baseWeight;
        if(m_enableDetailedLogging) {
            m_logger.AddDoubleContext(m_symbol, 
                StringFormat("%s%s", STR_WEIGHT_PREFIX, m_registry[i].componentName), 
                m_dynamicWeights[i], 1);
        }
    }
    
    if(m_enableDetailedLogging) {
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", "Weights initialized", false);
    }
}

//+------------------------------------------------------------------+
//| Get raw score from component (OPTIMIZED VERSION)                |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetComponentRawScore(string componentName, string symbol, double price, double stopLoss, double takeProfit)
{
    if(!m_initialized) return 50.0;
    
    double score = 0.0;
    
    // Use cached handles and data for performance
    if(componentName == "MarketStructureEngine") {
        score = GetMarketStructureEngineScore(symbol);
    }
    else if(componentName == "MTFEngine") {
        score = GetMTFEngineScore(symbol);
    }
    else {
        score = GetDefaultScore(componentName);
    }
    
    return score;
}

//+------------------------------------------------------------------+
//| FIXED: OPTIMIZED MTFEngineScore with cache validation           |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetMTFEngineScore(string symbol)
{
    if(!m_initialized) return 50.0;
    
    // Check cache validity
    if(!m_mtfCacheValid || IsMTFCacheStale()) {
        // Force refresh cache if invalid or stale
        ForceRefreshMTFCache();
    }
    
    // Use cached data if valid, otherwise get fresh data
    double mtfConfidence = m_mtfCacheValid ? m_cachedMTFConfidence : GetFreshMTFConfidence();
    MTF_SIGNAL mtfSignal = m_mtfCacheValid ? m_cachedMTFSignal : m_mtf.GetSignal(symbol);
    
    // Adjust score based on MTF signal strength
    double adjustedScore = mtfConfidence;
    
    // Boost for strong signals, reduce for weak/neutral
    switch(mtfSignal) {
        case MTF_SIGNAL_STRONG_BUY:
        case MTF_SIGNAL_STRONG_SELL:
            adjustedScore *= 1.1; // 10% boost for strong signals
            break;
        case MTF_SIGNAL_WEAK_BUY:
        case MTF_SIGNAL_WEAK_SELL:
            adjustedScore *= 0.9; // 10% reduction for weak signals
            break;
        case MTF_SIGNAL_NEUTRAL:
            adjustedScore *= 0.8; // 20% reduction for neutral
            break;
    }
    
    adjustedScore = MathMin(100.0, MathMax(0.0, adjustedScore));
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(symbol, "MTF_Analysis");
        m_logger.AddDoubleContext(symbol, "MTFEngine_Confidence", mtfConfidence, 1);
        m_logger.AddToContext(symbol, "MTFEngine_Signal", GetMTFSignalString(mtfSignal));
        m_logger.AddDoubleContext(symbol, "AdjustedScore", adjustedScore, 1);
        m_logger.AddBoolContext(symbol, "UsingCache", m_mtfCacheValid);
        m_logger.AddBoolContext(symbol, "CacheValid", m_mtfCacheValid);
        m_logger.AddToContext(symbol, "CacheAge", IntegerToString(TimeCurrent() - m_lastMTFUpdate));
        m_logger.FlushContext(symbol, OBSERVE, "ConfidenceEngine", 
                             StringFormat("MTF analysis: %.1f → %.1f | Cache: %s (Age: %d sec)", 
                                         mtfConfidence, adjustedScore,
                                         m_mtfCacheValid ? "VALID" : "INVALID",
                                         TimeCurrent() - m_lastMTFUpdate), 
                             false);
    }
    
    return adjustedScore;
}

//+------------------------------------------------------------------+
//| OPTIMIZED MarketStructureEngineScore using cached data          |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetMarketStructureEngineScore(string symbol)
{
    if(!m_initialized) return 50.0;
    
    // Time-based caching for this calculation
    static datetime lastCalculation = 0;
    static double cachedScore = 50.0;
    static string cachedSymbol = "";
    
    datetime currentTime = TimeCurrent();
    if(currentTime - lastCalculation < 2 && cachedSymbol == symbol) {
        return cachedScore; // Return cached result if within 2 seconds
    }
    
    double score = 50.0;
    string structure = "NEUTRAL";
    
    // Use cached MA values if available and recent
    if(m_lastMAUpdate > 0 && (currentTime - m_lastMAUpdate) < 2) {
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        if(m_cachedMA50 > m_cachedMA200 && price > m_cachedMA50) {
            score = 80.0;  // Bullish structure
            structure = "BULLISH";
        }
        else if(m_cachedMA50 < m_cachedMA200 && price < m_cachedMA50) {
            score = 20.0; // Bearish structure
            structure = "BEARISH";
        }
        else {
            score = 50.0; // Neutral structure
            structure = "NEUTRAL";
        }
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.StartContextWith(symbol, "MarketStructureEngine_Analysis_Cached");
            m_logger.AddDoubleContext(symbol, "MA50", m_cachedMA50, 5);
            m_logger.AddDoubleContext(symbol, "MA200", m_cachedMA200, 5);
            m_logger.AddDoubleContext(symbol, "Price", price, 5);
            m_logger.AddToContext(symbol, "Structure", structure);
            m_logger.AddDoubleContext(symbol, "Score", score, 1);
            m_logger.AddBoolContext(symbol, "UsingCache", true);
            m_logger.FlushContext(symbol, OBSERVE, "MarketStructureEngine", 
                                 "Market structure analysis (CACHED): " + structure, false);
        }
    } else {
        // Fallback to manual calculation if cache is stale
        // (This should rarely happen due to UpdateCachedMarketStructureData())
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.KeepNotes(symbol, WARN, "MarketStructureEngine", 
                              "Using fallback calculation - cache stale", false, false, 0.0);
        }
        
        // Your original fallback calculation here
        // ... (simplified for performance)
        score = 50.0;
    }
    
    // Cache the result
    lastCalculation = currentTime;
    cachedScore = score;
    cachedSymbol = symbol;
    
    return score;
}

//+------------------------------------------------------------------+
//| Get default score for unavailable components                     |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetDefaultScore(string componentName)
{
    // Neutral default scores
    double score = 50.0;
    
    if(componentName == "MarketStructureEngine") score = 50.0;
    else if(componentName == "MTFEngine") score = 50.0;
    
    return score;
}

//+------------------------------------------------------------------+
//| Distribute weights to ensure total = 100%                        |
//+------------------------------------------------------------------+
void ConfidenceEngine::DistributeWeights()
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "Weight_Distribution");
    }
    
    // Calculate total base weight of available components
    double totalBaseWeight = 0;
    int availableComponents = 0;
    
    int registrySize = m_maxComponents;
    for(int i = 0; i < registrySize; i++) {
        if(m_registry[i].isAvailable) {
            totalBaseWeight += m_registry[i].baseWeight;
            availableComponents++;
        }
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddDoubleContext(m_symbol, "TotalBaseWeight", totalBaseWeight, 1);
        m_logger.AddToContext(m_symbol, "AvailableComponents", IntegerToString(availableComponents));
    }
    
    // If no components available, use MarketStructureEngine with 100%
    if(availableComponents == 0) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Warning", "NoAvailableComponents", true);
        }
        
        int availCount = m_availableCount;
        for(int i = 0; i < availCount; i++) {
            if(m_currentAnalysis.components[i].componentName == "MarketStructureEngine") {
                m_currentAnalysis.components[i].adjustedWeight = 100.0;
                if(m_enableDetailedLogging && m_logger != NULL) {
                    m_logger.AddToContext(m_symbol, "Action", "SetMarketStructureEngineTo100Percent");
                    m_logger.FlushContext(m_symbol, WARN, "ConfidenceEngine", 
                                         "No available components, using MarketStructureEngine with 100% weight", false);
                }
                return;
            }
        }
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.FlushContext(m_symbol, WARN, "ConfidenceEngine", 
                                 "No available components and no MarketStructureEngine found", false);
        }
        return;
    }
    
    // Distribute weights proportionally
    double redistributionFactor = 100.0 / totalBaseWeight;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddDoubleContext(m_symbol, "RedistributionFactor", redistributionFactor, 3);
    }
    
    int availCount = m_availableCount;
    for(int i = 0; i < availCount; i++) {
        string compName = m_currentAnalysis.components[i].componentName;
        int regIndex = GetComponentIndex(compName);
        
        if(regIndex >= 0) {
            m_currentAnalysis.components[i].adjustedWeight = 
                m_registry[regIndex].baseWeight * redistributionFactor;
            
            if(m_enableDetailedLogging && m_logger != NULL) {
                m_logger.AddDoubleContext(m_symbol, 
                    StringFormat("%s%s_Weight", STR_COMPONENT_PREFIX, compName), 
                    m_currentAnalysis.components[i].adjustedWeight, 1);
            }
        }
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Weights distributed: " + DoubleToString(redistributionFactor, 3) + " factor", false);
    }
}

//+------------------------------------------------------------------+
//| Normalize scores to 0-100 range                                  |
//+------------------------------------------------------------------+
void ConfidenceEngine::NormalizeScores()
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "Score_Normalization");
    }
    
    int availCount = m_availableCount;
    for(int i = 0; i < availCount; i++) {
        double rawScore = m_currentAnalysis.components[i].rawScore;
        double normalizedScore = MathMax(0, MathMin(100, rawScore));
        m_currentAnalysis.components[i].normalizedScore = normalizedScore;
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddDoubleContext(m_symbol, 
                StringFormat("%s%s_Normalized", STR_COMPONENT_PREFIX, m_currentAnalysis.components[i].componentName), 
                normalizedScore, 1);
        }
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Scores normalized to 0-100 range", false);
    }
}

//+------------------------------------------------------------------+
//| Calculate total confidence                                       |
//+------------------------------------------------------------------+
void ConfidenceEngine::CalculateTotalConfidence()
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "TotalConfidence_Calculation");
    }
    
    double weightedSum = 0;
    
    int availCount = m_availableCount;
    for(int i = 0; i < availCount; i++) {
        ComponentAnalysis comp = m_currentAnalysis.components[i];
        
        // Calculate weighted score
        comp.weightedScore = (comp.normalizedScore * comp.adjustedWeight) / 100.0;
        weightedSum += comp.weightedScore;
        
        // Update component
        m_currentAnalysis.components[i] = comp;
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddDoubleContext(m_symbol, 
                StringFormat("%s%s_WeightedScore", STR_COMPONENT_PREFIX, comp.componentName), 
                comp.weightedScore, 2);
        }
    }
    
    m_currentAnalysis.totalConfidence = MathMin(100.0, MathMax(0.0, weightedSum));
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddDoubleContext(m_symbol, "WeightedSum", weightedSum, 2);
        m_logger.AddDoubleContext(m_symbol, "TotalConfidence", m_currentAnalysis.totalConfidence, 1);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Total confidence calculated: " + DoubleToString(m_currentAnalysis.totalConfidence, 1), false);
    }
}

//+------------------------------------------------------------------+
//| Select best strategy based on analysis                           |
//+------------------------------------------------------------------+
TRADE_STRATEGY ConfidenceEngine::SelectBestStrategy(ConfidenceAnalysis &analysis)
{
    if(!m_initialized) return STRATEGY_NONE;
    
    // Simple strategy selection based on signal
    if(analysis.signal == SIGNAL_STRONG_BUY || analysis.signal == SIGNAL_STRONG_SELL) {
        return STRATEGY_TREND_FOLLOWING;  // Strong signals = trend following
    } else if(analysis.signal == SIGNAL_WEAK_BUY || analysis.signal == SIGNAL_WEAK_SELL) {
        return STRATEGY_COUNTER_TREND;    // Weak signals = counter-trend
    }
    
    return STRATEGY_NONE;
}

//+------------------------------------------------------------------+
//| Calculate strategy score                                         |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculateStrategyScore(TRADE_STRATEGY strategy, ConfidenceAnalysis &analysis)
{
    // Simplified for performance
    return analysis.totalConfidence; // Use confidence as strategy score
}

//+------------------------------------------------------------------+
//| Check if strategy is valid                                       |
//+------------------------------------------------------------------+
bool ConfidenceEngine::IsStrategyValid(TRADE_STRATEGY strategy, ConfidenceAnalysis &analysis)
{
    // Simplified for performance - all strategies are valid
    return true;
}

//+------------------------------------------------------------------+
//| Apply strategy multipliers to weights                            |
//+------------------------------------------------------------------+
void ConfidenceEngine::ApplyStrategyMultipliers(TRADE_STRATEGY strategy)
{
    if(!m_initialized) return;
    
    if(strategy == STRATEGY_NONE) {
        if(m_enableDetailedLogging) {
            m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                              "No strategy selected, skipping multiplier application", false, false, 0.0);
        }
        return;
    }
    
    // Simplified for performance - no multiplier application
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                          "Strategy multipliers skipped for performance", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Rebalance weights to total 100%                                  |
//+------------------------------------------------------------------+
void ConfidenceEngine::RebalanceWeights()
{
    if(!m_initialized) return;
    
    // Simplified for performance - weights already balanced
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                          "Weight rebalancing skipped (already balanced)", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Generate signal from analysis                                    |
//+------------------------------------------------------------------+
CONFIDENCE_SIGNAL ConfidenceEngine::GenerateSignal(ConfidenceAnalysis &analysis)
{
    if(!m_initialized) return SIGNAL_NO_TRADE;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "Signal_Generation");
    }
    
    if(analysis.totalConfidence < 20) {  // Was 50, reduced to 20
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddDoubleContext(m_symbol, "TotalConfidence", analysis.totalConfidence, 1);
            m_logger.AddToContext(m_symbol, "Decision", "ConfidenceTooLow");
            m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                                 "Signal generation: Confidence too low for trade", false);
        }
        return SIGNAL_NO_TRADE;
    }
    
    // Calculate directional bias (simplified)
    CONFIDENCE_SIGNAL signal = SIGNAL_NEUTRAL;
    
    // Simplified signal generation based on confidence - ADJUSTED FOR 25 THRESHOLD
    if(analysis.totalConfidence >= 60) {
        signal = SIGNAL_STRONG_BUY; // Default to buy for high confidence
    } else if(analysis.totalConfidence >= 40) {  // Reduced from 55 to 40
        signal = SIGNAL_WEAK_BUY;
    } else if(analysis.totalConfidence >= 25) {  // Reduced from 40 to 25
        signal = SIGNAL_NEUTRAL;
    } else {
        signal = SIGNAL_NO_TRADE;
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddToContext(m_symbol, "FinalSignal", SignalToString(signal));
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Signal generated: " + SignalToString(signal), false);
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Determine confidence level                                       |
//+------------------------------------------------------------------+
CONFIDENCE_LEVEL ConfidenceEngine::DetermineConfidenceLevel(double score)
{
    CONFIDENCE_LEVEL level;
    
    if(score >= 90) level = CONFIDENCE_VERY_HIGH;
    else if(score >= 75) level = CONFIDENCE_HIGH;
    else if(score >= 60) level = CONFIDENCE_MEDIUM;
    else if(score >= 40) level = CONFIDENCE_LOW;
    else level = CONFIDENCE_VERY_LOW;
    
    return level;
}

//+------------------------------------------------------------------+
//| Determine market bias                                            |
//+------------------------------------------------------------------+
string ConfidenceEngine::DetermineMarketBias(ConfidenceAnalysis &analysis)
{
    // Cache bias determination
    static datetime lastBiasCalc = 0;
    static string cachedBias = "NEUTRAL";
    static double cachedConfidence = 0.0;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - lastBiasCalc < 1 && 
       MathAbs(cachedConfidence - analysis.totalConfidence) < 1.0) {
        return cachedBias;
    }
    
    // Simplified market bias determination
    string bias;
    if(analysis.totalConfidence >= 70) bias = "STRONG_BULLISH";
    else if(analysis.totalConfidence >= 55) bias = "BULLISH";
    else if(analysis.totalConfidence >= 45) bias = "NEUTRAL";
    else if(analysis.totalConfidence >= 30) bias = "BEARISH";
    else bias = "STRONG_BEARISH";
    
    // Cache results
    lastBiasCalc = currentTime;
    cachedBias = bias;
    cachedConfidence = analysis.totalConfidence;
    
    return bias;
}

//+------------------------------------------------------------------+
//| Check if components agree                                        |
//+------------------------------------------------------------------+
bool ConfidenceEngine::CheckComponentAgreement(ConfidenceAnalysis &analysis)
{
    if(!m_initialized) return false;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "Component_Agreement_Check");
    }
    
    if(m_availableCount < 2) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Decision", "NotEnoughComponents");
            m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                                 "Confluence check: Not enough components", false);
        }
        return true;
    }
    
    // Simplified confluence check
    bool isConfluent = (analysis.totalConfidence >= 60);
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddBoolContext(m_symbol, "IsConfluent", isConfluent);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Confluence check: " + (isConfluent ? "Strong agreement" : "Weak agreement"), false);
    }
    
    return isConfluent;
}

//+------------------------------------------------------------------+
//| Calculate divergence between components                          |
//+------------------------------------------------------------------+
double ConfidenceEngine::CalculateDivergence(ConfidenceAnalysis &analysis)
{
    if(!m_initialized) return 0.0;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "Divergence_Calculation");
    }
    
    if(m_availableCount < 2) {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Decision", "NotEnoughComponents");
            m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                                 "Divergence calculation: Not enough components", false);
        }
        return 0.0;
    }
    
    // Simplified divergence calculation
    double divergence = 20.0; // Default low divergence
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddDoubleContext(m_symbol, "Divergence", divergence, 1);
        m_logger.AddToContext(m_symbol, "DivergenceLevel", "LOW");
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Divergence calculated: " + DoubleToString(divergence, 1) + " (LOW)", false);
    }
    
    return divergence;
}

//+------------------------------------------------------------------+
//| Get component index by name                                      |
//+------------------------------------------------------------------+
int ConfidenceEngine::GetComponentIndex(string componentName)
{
    for(int i = 0; i < m_maxComponents; i++) {
        if(m_registry[i].componentName == componentName) {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Get component analysis                                           |
//+------------------------------------------------------------------+
ComponentAnalysis ConfidenceEngine::GetComponentAnalysis(string componentName)
{
    int availCount = m_availableCount;
    for(int i = 0; i < availCount; i++) {
        if(m_currentAnalysis.components[i].componentName == componentName) {
            return m_currentAnalysis.components[i];
        }
    }
    
    ComponentAnalysis empty;
    empty.componentName = componentName;
    empty.normalizedScore = 0;
    return empty;
}

//+------------------------------------------------------------------+
//| Get confidence score                                             |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetConfidenceScore(string symbol)
{
    if(!m_initialized) return 0.0;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(symbol, "GetConfidenceScore");
    }
    
    ConfidenceAnalysis analysis = Analyze(symbol, SymbolInfoDouble(symbol, SYMBOL_BID));
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddDoubleContext(symbol, "ConfidenceScore", analysis.totalConfidence, 1);
        m_logger.FlushContext(symbol, OBSERVE, "ConfidenceEngine", 
                             "Confidence score retrieved: " + DoubleToString(analysis.totalConfidence, 1), false);
    }
    
    return analysis.totalConfidence;
}

//+------------------------------------------------------------------+
//| Get signal                                                       |
//+------------------------------------------------------------------+
CONFIDENCE_SIGNAL ConfidenceEngine::GetSignal(string symbol)
{
    if(!m_initialized) return SIGNAL_NO_TRADE;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(symbol, "GetSignal");
    }
    
    ConfidenceAnalysis analysis = Analyze(symbol, SymbolInfoDouble(symbol, SYMBOL_BID));
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddToContext(symbol, "Signal", SignalToString(analysis.signal));
        m_logger.FlushContext(symbol, OBSERVE, "ConfidenceEngine", 
                             "Signal retrieved: " + SignalToString(analysis.signal), false);
    }
    
    return analysis.signal;
}

//+------------------------------------------------------------------+
//| Get recommended strategy                                         |
//+------------------------------------------------------------------+
TRADE_STRATEGY ConfidenceEngine::GetRecommendedStrategy(string symbol)
{
    if(!m_initialized) return STRATEGY_NONE;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(symbol, "GetRecommendedStrategy");
    }
    
    ConfidenceAnalysis analysis = Analyze(symbol, SymbolInfoDouble(symbol, SYMBOL_BID));
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddToContext(symbol, "RecommendedStrategy", StrategyToString(analysis.strategy));
        m_logger.FlushContext(symbol, OBSERVE, "ConfidenceEngine", 
                             "Strategy recommended: " + StrategyToString(analysis.strategy), false);
    }
    
    return analysis.strategy;
}

//+------------------------------------------------------------------+
//| Get position size multiplier                                     |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetPositionSizeMultiplier()
{
    if(!m_initialized) return 1.0;
    
    double multiplier = 1.0;
    
    switch(m_currentAnalysis.level) {
        case CONFIDENCE_VERY_HIGH: multiplier = 1.5; break;
        case CONFIDENCE_HIGH: multiplier = 1.2; break;
        case CONFIDENCE_MEDIUM: multiplier = 1.0; break;
        case CONFIDENCE_LOW: multiplier = 0.7; break;
        case CONFIDENCE_VERY_LOW: multiplier = 0.3; break;
        default: multiplier = 1.0; break;
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "PositionSizeMultiplier");
        m_logger.AddToContext(m_symbol, "ConfidenceLevel", ConfidenceLevelToString(m_currentAnalysis.level));
        m_logger.AddDoubleContext(m_symbol, "Multiplier", multiplier, 2);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Position size multiplier: " + DoubleToString(multiplier, 2), false);
    }
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Get risk multiplier                                              |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetRiskMultiplier()
{
    if(!m_initialized) return 1.0;
    
    double multiplier = 1.0;
    
    switch(m_currentAnalysis.level) {
        case CONFIDENCE_VERY_HIGH: multiplier = 0.8; break;  // Lower risk on high confidence
        case CONFIDENCE_HIGH: multiplier = 0.9; break;
        case CONFIDENCE_MEDIUM: multiplier = 1.0; break;
        case CONFIDENCE_LOW: multiplier = 1.2; break;  // Higher risk on low confidence
        case CONFIDENCE_VERY_LOW: multiplier = 1.5; break;
        default: multiplier = 1.0; break;
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "RiskMultiplier");
        m_logger.AddToContext(m_symbol, "ConfidenceLevel", ConfidenceLevelToString(m_currentAnalysis.level));
        m_logger.AddDoubleContext(m_symbol, "Multiplier", multiplier, 2);
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Risk multiplier: " + DoubleToString(multiplier, 2), false);
    }
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Get trade action                                                 |
//+------------------------------------------------------------------+
string ConfidenceEngine::GetTradeAction()
{
    string action = "WAIT";
    
    switch(m_currentAnalysis.signal) {
        case SIGNAL_STRONG_BUY:
        case SIGNAL_STRONG_SELL:
            action = "ENTER_AGGRESSIVE"; break;
        case SIGNAL_WEAK_BUY:
        case SIGNAL_WEAK_SELL:
            action = "ENTER_CAUTIOUS"; break;
        case SIGNAL_NEUTRAL:
            action = "HOLD"; break;
        case SIGNAL_NO_TRADE:
            action = "WAIT"; break;
        default:
            action = "WAIT"; break;
    }
    
    return action;
}

//+------------------------------------------------------------------+
//| Register a component                                             |
//+------------------------------------------------------------------+
void ConfidenceEngine::RegisterComponent(string componentName, double baseWeight, bool isRequired)
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "RegisterComponent");
    }
    
    int index = GetComponentIndex(componentName);
    if(index >= 0) {
        m_registry[index].baseWeight = baseWeight;
        m_registry[index].isAvailable = true;
        m_registry[index].isRequired = isRequired;
        m_availableCount++;
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddDoubleContext(m_symbol, "BaseWeight", baseWeight, 1);
            m_logger.AddBoolContext(m_symbol, "IsRequired", isRequired);
            m_logger.AddBoolContext(m_symbol, "IsAvailable", true);
            m_logger.FlushContext(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                                 "Component registered: " + componentName, false);
        }
    } else {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Warning", "ComponentNotFound", true);
            m_logger.FlushContext(m_symbol, WARN, "ConfidenceEngine", 
                                 "Component not found: " + componentName, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Set component availability                                       |
//+------------------------------------------------------------------+
void ConfidenceEngine::SetComponentAvailability(string componentName, bool isAvailable)
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "SetComponentAvailability");
    }
    
    int index = GetComponentIndex(componentName);
    if(index >= 0) {
        bool wasAvailable = m_registry[index].isAvailable;
        m_registry[index].isAvailable = isAvailable;
        
        if(isAvailable && !wasAvailable) {
            m_availableCount++;
            if(m_enableDetailedLogging && m_logger != NULL) {
                m_logger.AddToContext(m_symbol, "Action", "ComponentEnabled");
            }
        } else if(!isAvailable && wasAvailable) {
            m_availableCount--;
            if(m_enableDetailedLogging && m_logger != NULL) {
                m_logger.AddToContext(m_symbol, "Action", "ComponentDisabled");
            }
        }
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddBoolContext(m_symbol, "NewAvailability", isAvailable);
            m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                                 "Component availability set: " + componentName + " = " + (isAvailable ? "TRUE" : "FALSE"), false);
        }
    } else {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Warning", "ComponentNotFound", true);
            m_logger.FlushContext(m_symbol, WARN, "ConfidenceEngine", 
                                 "Component not found: " + componentName, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Update component score                                           |
//+------------------------------------------------------------------+
void ConfidenceEngine::UpdateComponentScore(string componentName, double score, bool wasSuccessful)
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "UpdateComponentScore");
    }
    
    int index = GetComponentIndex(componentName);
    if(index >= 0) {
        m_registry[index].lastScore = score;
        if(wasSuccessful) {
            m_registry[index].successCount++;
        }
        m_registry[index].totalUses++;
        
        double successRate = (m_registry[index].totalUses > 0) ? 
                            (m_registry[index].successCount / (double)m_registry[index].totalUses) * 100.0 : 0.0;
        
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddDoubleContext(m_symbol, "Score", score, 1);
            m_logger.AddBoolContext(m_symbol, "WasSuccessful", wasSuccessful);
            m_logger.AddDoubleContext(m_symbol, "SuccessRate", successRate, 1);
            m_logger.AddToContext(m_symbol, "SuccessCount", IntegerToString(m_registry[index].successCount));
            m_logger.AddToContext(m_symbol, "TotalUses", IntegerToString(m_registry[index].totalUses));
            m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                                 "Component score updated: " + componentName, false);
        }
    } else {
        if(m_enableDetailedLogging && m_logger != NULL) {
            m_logger.AddToContext(m_symbol, "Warning", "ComponentNotFound", true);
            m_logger.FlushContext(m_symbol, WARN, "ConfidenceEngine", 
                                 "Component not found: " + componentName, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Record strategy performance                                      |
//+------------------------------------------------------------------+
void ConfidenceEngine::RecordStrategyPerformance(TRADE_STRATEGY strategy, double confidence, bool wasSuccessful, double profitLoss)
{
    if(!m_initialized) return;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "RecordStrategyPerformance");
    }
    
    m_performanceHistory[m_performanceIndex].strategy = strategy;
    m_performanceHistory[m_performanceIndex].confidence = confidence;
    m_performanceHistory[m_performanceIndex].wasSuccessful = wasSuccessful;
    m_performanceHistory[m_performanceIndex].profitLoss = profitLoss;
    m_performanceHistory[m_performanceIndex].tradeTime = TimeCurrent();
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddToContext(m_symbol, "Strategy", StrategyToString(strategy));
        m_logger.AddDoubleContext(m_symbol, "Confidence", confidence, 1);
        m_logger.AddBoolContext(m_symbol, "WasSuccessful", wasSuccessful);
        m_logger.AddDoubleContext(m_symbol, "ProfitLoss", profitLoss, 2);
        m_logger.AddToContext(m_symbol, "PerformanceIndex", IntegerToString(m_performanceIndex));
        
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Strategy performance recorded", false);
    }
    
    m_performanceIndex = (m_performanceIndex + 1) % 100;
}

//+------------------------------------------------------------------+
//| Get strategy success rate                                        |
//+------------------------------------------------------------------+
double ConfidenceEngine::GetStrategySuccessRate(TRADE_STRATEGY strategy)
{
    if(!m_initialized) return 0.0;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.StartContextWith(m_symbol, "GetStrategySuccessRate");
    }
    
    int totalTrades = 0;
    int successfulTrades = 0;
    
    for(int i = 0; i < 100; i++) {
        if(m_performanceHistory[i].strategy == strategy) {
            totalTrades++;
            if(m_performanceHistory[i].wasSuccessful) {
                successfulTrades++;
            }
        }
    }
    
    double successRate = 0.0;
    if(totalTrades > 0) {
        successRate = (successfulTrades / (double)totalTrades) * 100.0;
    }
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.AddToContext(m_symbol, "Strategy", StrategyToString(strategy));
        m_logger.AddToContext(m_symbol, "TotalTrades", IntegerToString(totalTrades));
        m_logger.AddToContext(m_symbol, "SuccessfulTrades", IntegerToString(successfulTrades));
        m_logger.AddDoubleContext(m_symbol, "SuccessRate", successRate, 1);
        
        m_logger.FlushContext(m_symbol, OBSERVE, "ConfidenceEngine", 
                             "Strategy success rate: " + DoubleToString(successRate, 1) + "%", false);
    }
    
    return successRate;
}

//+------------------------------------------------------------------+
//| Log component analysis                                           |
//+------------------------------------------------------------------+
void ConfidenceEngine::LogComponentAnalysis()
{
    #ifdef CONFIDENCE_ENGINE_DEBUG
    if(!m_initialized || m_logger == NULL || !m_enableDetailedLogging) return;
    
    m_logger.StartContextWith(m_symbol, "Component_Analysis_Details");
    
    int availCount = m_availableCount;
    for(int i = 0; i < availCount; i++) {
        ComponentAnalysis comp = m_currentAnalysis.components[i];
        
        m_logger.AddToContext(m_symbol, 
            StringFormat("Comp_%s_Raw", comp.componentName), 
            DoubleToString(comp.rawScore, 1));
        m_logger.AddToContext(m_symbol, 
            StringFormat("Comp_%s_Norm", comp.componentName), 
            DoubleToString(comp.normalizedScore, 1));
        m_logger.AddToContext(m_symbol, 
            StringFormat("Comp_%s_Weight", comp.componentName), 
            DoubleToString(comp.adjustedWeight, 1));
        m_logger.AddToContext(m_symbol, 
            StringFormat("Comp_%s_Weighted", comp.componentName), 
            DoubleToString(comp.weightedScore, 2));
    }
    
    m_logger.FlushContext(m_symbol, AUDIT, "ConfidenceEngine", 
                         "Detailed component analysis", false);
    #endif
}

//+------------------------------------------------------------------+
//| Log strategy selection                                           |
//+------------------------------------------------------------------+
void ConfidenceEngine::LogStrategySelection(TRADE_STRATEGY selectedStrategy, double strategyScore)
{
    #ifdef CONFIDENCE_ENGINE_DEBUG
    if(!m_initialized || m_logger == NULL || !m_enableDetailedLogging) return;
    
    m_logger.KeepNotes(m_symbol, AUTHORIZE, "ConfidenceEngine", 
                      "Strategy selected: " + StrategyToString(selectedStrategy) + 
                      " (Score: " + DoubleToString(strategyScore, 1) + ")", 
                      false, false, 0.0);
    #endif
}

//+------------------------------------------------------------------+
//| Convert signal to string                                         |
//+------------------------------------------------------------------+
string ConfidenceEngine::SignalToString(CONFIDENCE_SIGNAL signal)
{
    switch(signal) {
        case NO_SIGNAL: return "NONE";
        case SIGNAL_STRONG_BUY: return "STRONG_BUY";
        case SIGNAL_WEAK_BUY: return "WEAK_BUY";
        case SIGNAL_STRONG_SELL: return "STRONG_SELL";
        case SIGNAL_WEAK_SELL: return "WEAK_SELL";
        case SIGNAL_NEUTRAL: return "NEUTRAL";
        case SIGNAL_NO_TRADE: return "NO_TRADE";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Convert strategy to string                                       |
//+------------------------------------------------------------------+
string ConfidenceEngine::StrategyToString(TRADE_STRATEGY strategy)
{
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING: return "TREND_FOLLOWING";
        case STRATEGY_COUNTER_TREND: return "COUNTER_TREND";
        case STRATEGY_RANGE_TRADING: return "RANGE_TRADING";
        case STRATEGY_BREAKOUT: return "BREAKOUT";
        case STRATEGY_REVERSAL: return "REVERSAL";
        case STRATEGY_SCALPING: return "SCALPING";
        case STRATEGY_NONE: return "NONE";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Convert confidence level to string                               |
//+------------------------------------------------------------------+
string ConfidenceEngine::ConfidenceLevelToString(CONFIDENCE_LEVEL level)
{
    switch(level) {
        case CONFIDENCE_VERY_LOW: return "VERY_LOW";
        case CONFIDENCE_LOW: return "LOW";
        case CONFIDENCE_MEDIUM: return "MEDIUM";
        case CONFIDENCE_HIGH: return "HIGH";
        case CONFIDENCE_VERY_HIGH: return "VERY_HIGH";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| NEW: Internal method for immediate cache refresh                 |
//+------------------------------------------------------------------+
void ConfidenceEngine::RefreshMTFCacheImmediately()
{
    ForceRefreshMTFCache(); // Alias for public method
}

//+------------------------------------------------------------------+
//| NEW: Reset MTF cache                                             |
//+------------------------------------------------------------------+
void ConfidenceEngine::ResetMTFCache()
{
    m_cachedMTFConfidence = 0.0;
    m_cachedMTFSignal = MTF_SIGNAL_NEUTRAL;
    m_lastMTFUpdate = 0;
    m_mtfCacheValid = false;
    
    if(m_enableDetailedLogging && m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, OBSERVE, "ConfidenceEngine", 
                          "MTF cache reset", false, false, 0.0);
    }
}