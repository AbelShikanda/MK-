// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++       DECISION ENGINE           ++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property strict
#property version   "1.00"

/*
==============================================================
DECISION ENGINE - EXECUTION MANAGER
==============================================================
Core Decision Logic:
1. No Position → Evaluate Confidence → OPEN
2. Position → Evaluate Confidence → ADD/HOLD/CLOSE
3. Market Context → Adjust Decisions
4. Cooldown Management → Prevent Rapid Flipping
==============================================================
*/

// ================= INCLUDES =================
#include "PositionManager.mqh"  
#include "ConfidenceEngine.mqh"
#include "../utils/Utils.mqh"

// ================= LOGGING SYSTEM =================
#include "../utils/ResourceManager.mqh"

// Global instances
ConfidenceEngine* d_confidenceEngine = NULL;

// ================= ENUMS =================

enum MARKET_DIRECTION {
    DIRECTION_BULLISH,
    DIRECTION_BEARISH,
    DIRECTION_RANGING,
    DIRECTION_UNCLEAR
};

// ================= STRUCTURES =================
struct DecisionParams {
    double buyConfidenceThreshold;
    double sellConfidenceThreshold;
    double addPositionThreshold;
    double closePositionThreshold;
    double closeAllThreshold;
    int cooldownMinutes;
    double maxPositionsPerSymbol;
    double riskPercent;
};

struct CooldownRecord {
    string symbol;
    bool isBuy;
    datetime lastTime;
    int actionCount;
};

struct SymbolParams {
    string symbol;
    DecisionParams params;
    PositionManager* positionManager;
    datetime lastDecisionTime;
    CooldownRecord cooldown;
    DECISION_ACTION lastDecision;
};

struct PositionAnalysis {
    // Hot data (frequently accessed) first
    POSITION_STATE state;
    int buyCount;
    int sellCount;
    double totalProfit;
    
    // Warm data (less frequently accessed)
    double totalBuyVolume;
    double totalSellVolume;
    double averageBuyPrice;
    double averageSellPrice;
    
    // Cold data (rarely accessed)
    double totalLoss;
    datetime newestPositionTime;
    datetime oldestPositionTime;
};

struct MarketAnalysis {
    MARKET_DIRECTION direction;
    double trendStrength;
    bool isRanging;
    double volatility;
    string bias;
};

struct TradeConditions {
    bool confidenceThresholdMet;
    bool marketDirectionAligned;
    bool positionLimitNotExceeded;
    bool notInCooldown;
    bool withinTradingHours;
    bool riskManagementOk;
    bool overallConditionsMet;
    
    TradeConditions() {
        confidenceThresholdMet = false;
        marketDirectionAligned = false;
        positionLimitNotExceeded = false;
        notInCooldown = false;
        withinTradingHours = false;
        riskManagementOk = false;
        overallConditionsMet = false;
    }
};

// ================= PROFILING STRUCTURES =================
struct PerformanceMetrics {
    ulong lastProfileTime;
    int totalTicksProcessed;
    int ticksSkipped;
    int decisionsMade;
    int tradesExecuted;
    double avgProcessingTimeMs;
    double maxProcessingTimeMs;
    double totalProcessingTimeMs;
    
    PerformanceMetrics() {
        lastProfileTime = TimeCurrent();
        totalTicksProcessed = 0;
        ticksSkipped = 0;
        decisionsMade = 0;
        tradesExecuted = 0;
        avgProcessingTimeMs = 0;
        maxProcessingTimeMs = 0;
        totalProcessingTimeMs = 0;
    }
};

struct SymbolCache {
    string symbol;
    datetime lastMarketAnalysisTime;
    MarketAnalysis cachedMarketAnalysis;
    double lastConfidence;
    MARKET_DIRECTION lastDirection;
    bool isRangingCached;
    PositionAnalysis lastPositionAnalysis;
    
    SymbolCache() {
        symbol = "";
        lastMarketAnalysisTime = 0;
        lastConfidence = 0;
        lastDirection = DIRECTION_UNCLEAR;
        isRangingCached = false;
    }
};

// ================= TYPEDEFS (OUTSIDE CLASS) =================
typedef double (*ConfidenceFunction)(string symbol);
typedef MARKET_DIRECTION (*DirectionFunction)(string symbol);
typedef bool (*RangingFunction)(string symbol);

// ================= CLASS DEFINITION =================
class DecisionEngine
{
private:
    // Configuration
    string m_engineComment;
    int m_engineMagicBase;
    int m_slippage;
    
    // Symbol-specific management
    SymbolParams m_symbolParams[];
    int m_totalSymbols;
    
    // External module interfaces
    ConfidenceFunction m_getConfidence;     
    DirectionFunction m_getMarketDirection; 
    RangingFunction m_isMarketRanging; 
    
    // Dependencies (passed in Initialize)
    ResourceManager* m_logger;
    RiskManager* m_riskManager;
    
    // Performance tracking
    int m_totalDecisions;
    int m_correctDecisions;
    double m_decisionAccuracy;

    bool m_initialized;
    datetime m_lastTickTime;
    datetime m_lastTimerTime;
    int m_timerIntervalSeconds;
    
    // Comment throttling
    datetime m_lastCommentUpdate[];
    int m_commentThrottleSeconds;
    
    // Performance optimization
    datetime m_lastTickProcessTime[];
    bool m_isTesterMode;
    
    // ================= MINIMAL CACHING FIELDS =================
    PerformanceMetrics m_performance;
    SymbolCache m_symbolCache[];
    datetime m_lastBatchProcessTime;
    int m_batchProcessingInterval;
    bool m_skipUnchangedConditions;  // Set to FALSE for testing
    
    // Decision caching - Minimal
    struct CachedDecision {
        DECISION_ACTION action;
        double confidence;
        MARKET_DIRECTION direction;
        datetime timestamp;
    };
    CachedDecision m_decisionCache[];
    
    // Timeframe data caching - Kept for performance
    struct TimeframeCache {
        double ema9;
        double ema21;
        double atr;
        datetime lastUpdate;
        int ema9Handle;
        int ema21Handle;
        int atrHandle;
        int adxHandle;
        
        TimeframeCache() {
            ema9 = 0;
            ema21 = 0;
            atr = 0;
            lastUpdate = 0;
            ema9Handle = INVALID_HANDLE;
            ema21Handle = INVALID_HANDLE;
            atrHandle = INVALID_HANDLE;
            adxHandle = INVALID_HANDLE;
        }
    };
    TimeframeCache m_timeframeCache[];
    
    // Trade decision tracking
    struct TradeDecision {
        // Hot data (accessed every decision)
        string symbol;
        DECISION_ACTION action;
        double confidence;
        MARKET_DIRECTION direction;
        datetime timestamp;
        
        // Warm data (accessed during evaluation)
        string reason;
        TradeConditions conditions;
        
        // Cold data (accessed occasionally)
        PositionAnalysis positions;
        MarketAnalysis market;
        
        TradeDecision() {
            symbol = "";
            action = ACTION_NONE;
            confidence = 0.0;
            direction = DIRECTION_UNCLEAR;
            timestamp = 0;
            reason = "";
        }
    };
    
    TradeDecision m_lastDecision[];
    
    // DEBUG FLAG
    bool m_debugMode;
    
    // String constants for optimization
    const string STR_DECISION_ENGINE;
    const string STR_SYSTEM;
    
    // Position data caching - Kept but with shorter TTL
    struct PositionCache {
        string symbol;
        int buyCount;
        int sellCount;
        double totalBuyVolume;
        double totalSellVolume;
        datetime lastUpdate;
    };
    PositionCache m_positionCache[];
    
    // Symbol data caching - Kept but with shorter TTL
    struct SymbolData {
        string symbol;
        double point;
        double tickSize;
        double bid;
        double ask;
        datetime lastUpdate;
    };
    SymbolData m_symbolDataCache[];
    
    // New: Testing mode flag
    bool m_testingMode;
    
    // ================= ENHANCED LOGGING FIELDS =================
    struct TradeLog {
        datetime timestamp;
        string symbol;
        DECISION_ACTION action;
        double confidence;
        bool executed;
        double profit;
        int positionsBefore;
        int positionsAfter;
        string details;
        
        TradeLog() {
            timestamp = 0;
            symbol = "";
            action = ACTION_NONE;
            confidence = 0.0;
            executed = false;
            profit = 0.0;
            positionsBefore = 0;
            positionsAfter = 0;
            details = "";
        }
    };
    
    TradeLog m_tradeLogs[];  // Circular buffer for trade logs
    int m_tradeLogIndex;
    int m_maxTradeLogs;
    
    struct DailyStats {
        datetime date;
        int totalTrades;
        int winningTrades;
        int losingTrades;
        double totalProfit;
        double largestWin;
        double largestLoss;
        int buyTrades;
        int sellTrades;
        
        DailyStats() {
            date = 0;
            totalTrades = 0;
            winningTrades = 0;
            losingTrades = 0;
            totalProfit = 0.0;
            largestWin = 0.0;
            largestLoss = 0.0;
            buyTrades = 0;
            sellTrades = 0;
        }
    };
    
    DailyStats m_dailyStats;
    
public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    DecisionEngine();  // ONLY sets default values
    ~DecisionEngine();
    
    // ================= INITIALIZATION/DEINITIALIZATION =================
    bool Initialize(
        ResourceManager* logger,
        PositionManager* pm,
        RiskManager* riskManager = NULL,
        string engineComment = "DecisionEngine", 
        int engineMagicBase = 12345, 
        int slippage = 5
    );
    void Deinitialize();
    
    // ================= EVENT HANDLERS =================
    void OnTick();
    void OnTimer();
    void OnTradeTransaction();
    void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
    
    // ================= SYMBOL MANAGEMENT =================
    bool AddSymbol(string symbol, DecisionParams &params);
    bool AddSymbolAuto(string symbol, DecisionParams &params);
    bool RemoveSymbol(string symbol);
    
    // ================= MAIN PUBLIC INTERFACE =================
    DECISION_ACTION MakeDecision(string symbol, double confidence, double marketDirectionScore);
    DECISION_ACTION MakeDecision(string symbol, double confidence, MARKET_DIRECTION direction);
    void ExecuteDecision(string symbol, DECISION_ACTION decision, double confidence, double lots = 0);
    DECISION_ACTION GetCurrentDecision(string symbol);
    
    // ================= ANALYSIS FUNCTIONS =================
    PositionAnalysis AnalyzePositions(string symbol) const;
    PositionAnalysis AnalyzePositionsOriginal(string symbol) const;
    MarketAnalysis AnalyzeMarket(string symbol);
    bool IsInCooldown(string symbol, bool isBuy);
    void UpdateCooldown(string symbol, bool isBuy);
    
    // ================= SETTERS =================
    void SetSymbolParameters(string symbol, DecisionParams &params);
    void SetConfidenceFunction(ConfidenceFunction func);
    void SetMarketDirectionFunction(DirectionFunction func);
    void SetRangingFunction(RangingFunction func);
    void SetTimerInterval(int seconds);
    void SetCommentThrottle(int seconds) { m_commentThrottleSeconds = MathMax(seconds, 1); }
    void SetSkipUnchangedConditions(bool skip) { m_skipUnchangedConditions = skip; }
    void SetBatchProcessingInterval(int seconds) { m_batchProcessingInterval = MathMax(seconds, 5); }
    void SetTestingMode(bool testing) { 
        m_testingMode = testing; 
        if(testing) {
            m_skipUnchangedConditions = false;  // Disable caching in testing mode
            m_batchProcessingInterval = 1;      // Process every second
            Print("DecisionEngine: TESTING MODE ENABLED (caching disabled)");
        }
    }
    
    // ================= DEBUG SETTER =================
    void SetDebugMode(bool debug) { m_debugMode = debug; if(debug) Print("DecisionEngine Debug Mode: ENABLED"); }
    
    // ================= GETTERS =================
    PositionAnalysis GetPositionAnalysis(string symbol) const;
    MarketAnalysis GetMarketAnalysis(string symbol) const;
    double GetDecisionAccuracy() const;
    DecisionParams GetSymbolParameters(string symbol) const;
    bool IsDecisionValid(string symbol, DECISION_ACTION decision, double confidence);
    int GetSymbolCount() const { return m_totalSymbols; }
    string GetSymbolByIndex(int index) const;
    bool HasSymbol(string symbol) const;
    bool IsInitialized() const { return m_initialized; }
    string GetQuickStatus();
    PerformanceMetrics GetPerformanceMetrics() const { return m_performance; }
    
    // ================= UTILITY FUNCTIONS =================
    string DecisionToString(DECISION_ACTION decision);
    void ResetStatistics();
    void PrintDecisionLog(string symbol, DECISION_ACTION decision, double confidence, string reason);
    void PrintAllSymbolsStatus();
    bool QuickInitialize(string symbol, double buyThreshold = 25.0, 
                         double sellThreshold = 25.0, double riskPercent = 1.0,
                         int cooldownMinutes = 5);
    
    // ================= CACHE CONTROL =================
    void InvalidateDecisionCache(string symbol);
    void InvalidateAllCaches();
    void ForceRefresh(string symbol);
    
    // ================= ENHANCED LOGGING METHODS =================
    void LogTrade(string symbol, DECISION_ACTION action, bool executed, double confidence, 
                  double profit = 0.0, string details = "");
    void LogTradeSummary();
    string GetTradeHistory(int count = 10);
    DailyStats GetDailyStats() const { return m_dailyStats; }
    void UpdateDailyStats(DECISION_ACTION action, bool executed, double profit);

private:
    // ================= PRIVATE CORE FUNCTIONS =================
    // Symbol management
    int FindSymbolIndex(string symbol) const;
    PositionManager* GetPositionManager(string symbol) const;
    DecisionParams GetSymbolDecisionParams(string symbol);
    SymbolParams GetSymbolParams(string symbol);
    
    // Position management
    double CalculatePositionSize(string symbol, double confidence);
    double CalculateAddPositionSize(string symbol, double existingVolume, double confidence);
    
    // Decision logic
    DECISION_ACTION DecideNoPosition(string symbol, double confidence, MARKET_DIRECTION direction);
    DECISION_ACTION DecideWithPosition(string symbol, double confidence, MARKET_DIRECTION direction, PositionAnalysis &positions);
    DECISION_ACTION DecideAdding(string symbol, double confidence, POSITION_STATE state, MARKET_DIRECTION direction);
    DECISION_ACTION DecideHolding(string symbol, double confidence, POSITION_STATE state, MARKET_DIRECTION direction);
    DECISION_ACTION DecideFolding(string symbol, double confidence, POSITION_STATE state);
    DECISION_ACTION DecideClosing(string symbol, double confidence, POSITION_STATE state);
    
    // Market analysis
    MARKET_DIRECTION DetermineMarketDirection(string symbol);
    bool IsMarketRanging(string symbol);
    double CalculateTrendStrength(string symbol);
    
    // Risk management
    bool CheckMaxPositions(string symbol, bool isBuy);
    bool CheckTimeSinceLastTrade(string symbol);
    
    // Validation
    bool ValidateDecision(string symbol, DECISION_ACTION decision, double confidence);
    bool CheckConfidenceThresholds(string symbol, double confidence, bool isBuy);
    bool IsWithinTradingHours(string symbol);
    
    // Utility
    void UpdateDecisionStatistics(bool wasSuccessful);
    datetime GetLastTradeTime(string symbol, bool isBuy);
    
    // Default implementations
    double DefaultGetConfidence(string symbol);
    MARKET_DIRECTION DefaultGetMarketDirection(string symbol);
    bool DefaultIsMarketRanging(string symbol);
    
    // Helper functions
    bool ShouldMakeDecision(string symbol);
    void CheckEmergencyConditions(string symbol);
    
    // PositionManager helpers
    int CountPositions(string symbol, bool isBuy) const;
    double GetTotalPositionVolume(string symbol, bool isBuy) const;
    bool HasOpenPosition(string symbol, bool isBuy);
    
    // Magic number generation
    int GenerateMagicNumber(string symbol);
    
    // Default implementations - make them static
    static double StaticDefaultGetConfidence(string symbol);
    static MARKET_DIRECTION StaticDefaultGetMarketDirection(string symbol);
    static bool StaticDefaultIsMarketRanging(string symbol);
    
    // Instance versions that call static versions with context
    double InstanceDefaultGetConfidence(string symbol);
    MARKET_DIRECTION InstanceDefaultGetMarketDirection(string symbol);
    bool InstanceDefaultIsMarketRanging(string symbol);
    
    // Cleanup helper
    void Cleanup();
    
    // Trade conditions evaluation
    TradeConditions EvaluateTradeConditions(string symbol, double confidence, 
                                          MARKET_DIRECTION direction, DECISION_ACTION action);
    string ConditionsToString(TradeConditions &conditions);
    
    // Decision tracking
    void StoreDecision(string symbol, DECISION_ACTION action, double confidence, 
                      MARKET_DIRECTION direction, TradeConditions &conditions, 
                      PositionAnalysis &positions, MarketAnalysis &market, string reason);
    
    // ================= MINIMAL CACHING METHODS =================
    // Performance profiling
    void StartProfiling();
    void StopProfiling();
    void LogPerformanceMetrics();
    
    // Caching methods - MINIMAL VERSION
    bool ShouldUseCachedMarketAnalysis(string symbol);
    MarketAnalysis GetCachedMarketAnalysis(string symbol);
    void UpdateMarketAnalysisCache(string symbol, MarketAnalysis &analysis);
    
    bool ShouldUseCachedDecision(string symbol, double confidence, MARKET_DIRECTION direction);
    DECISION_ACTION GetCachedDecision(string symbol);
    void UpdateDecisionCache(string symbol, DECISION_ACTION decision, double confidence, MARKET_DIRECTION direction);
    
    // Batch processing methods - Simplified
    bool ShouldProcessBatch();
    void ProcessSymbolBatch();
    
    // Timeframe data caching - Kept for performance
    void UpdateTimeframeCache(string symbol);
    double GetCachedEMA9(string symbol);
    double GetCachedEMA21(string symbol);
    double GetCachedATR(string symbol);
    
    // Performance optimization methods - MINIMAL
    bool ShouldProcessSymbol(string symbol);
    bool ShouldUpdateComments(string symbol);
    void InitializePerformanceArrays();
    
    // Minimal logging helper (only when trade happens or conditions change)
    void LogDecisionContext(string symbol, DECISION_ACTION decision, double confidence, 
                           MARKET_DIRECTION direction, PositionAnalysis &positions, string reason);
    
    // Efficient comment updates
    void UpdateDecisionComments(string symbol, TradeDecision &decision);
    string BuildDecisionExplanation(TradeDecision &decision);
    void UpdatePerformanceComments(string symbol);

    // Bridge functions that connect DecisionEngine to ConfidenceEngine
    double GetConfidenceFromEngine(string symbol);
    MARKET_DIRECTION GetMarketDirectionFromEngine(string symbol);
    bool IsMarketRangingFromEngine(string symbol);
    
    // Enhanced execution logging
    void LogExecutionResult(string symbol, DECISION_ACTION decision, bool executed, 
                           string actionResult, double confidence);
    
    // DEBUG HELPER METHODS
    void DebugLog(string symbol, string message);
    void DebugLogConditionCheck(string symbol, string condition, bool result, string details = "");
    
    // New optimization methods - MINIMAL
    void UpdateSymbolData(string symbol);
    void UpdatePositionCache(string symbol);
    
    // ================= ENHANCED LOGGING METHODS =================
    void InitializeTradeLogging();
    void LogTradeExecution(string symbol, DECISION_ACTION action, bool executed, 
                          double confidence, double profit, int positionsBefore, 
                          int positionsAfter, string details);
    void LogPositionChange(string symbol, string changeType, int countBefore, 
                          int countAfter, double volumeChange);
    void LogMarketConditions(string symbol, double confidence, MARKET_DIRECTION direction,
                            double trendStrength, double volatility);
};

// ================= IMPLEMENTATION =================

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
DecisionEngine::DecisionEngine() : STR_DECISION_ENGINE("DecisionEngine"), STR_SYSTEM("SYSTEM")
{
    // ONLY SET DEFAULT VALUES - NO INITIALIZATION
    m_engineComment = "";
    m_engineMagicBase = 0;
    m_slippage = 0;
    m_totalDecisions = 0;
    m_correctDecisions = 0;
    m_decisionAccuracy = 0.0;
    m_totalSymbols = 0;
    
    // Initialize external function pointers
    m_getConfidence = NULL;
    m_getMarketDirection = NULL;
    m_isMarketRanging = NULL;
    
    // Initialize dependencies to NULL
    m_logger = NULL;
    m_riskManager = NULL;
    
    // Initialize tracking variables
    m_initialized = false;
    m_lastTickTime = 0;
    m_lastTimerTime = 0;
    m_timerIntervalSeconds = 60;
    
    // Initialize performance optimization
    m_commentThrottleSeconds = 2; // Default: update comments every 2 seconds
    m_isTesterMode = MQLInfoInteger(MQL_TESTER);
    
    // Initialize caching - MINIMAL for testing
    m_lastBatchProcessTime = 0;
    m_batchProcessingInterval = 1; // Process every second for testing
    m_skipUnchangedConditions = false; // DISABLE decision caching for testing
    
    // Initialize debug mode
    m_debugMode = false;
    
    // Initialize testing mode
    m_testingMode = false;
    
    // Initialize trade logging
    m_tradeLogIndex = 0;
    m_maxTradeLogs = 100; // Keep last 100 trades in memory
    ArrayResize(m_tradeLogs, m_maxTradeLogs);
    
    // Initialize arrays with pre-allocation
    InitializePerformanceArrays();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
DecisionEngine::~DecisionEngine()
{
    // Cleanup indicator handles
    for(int i = 0; i < ArraySize(m_timeframeCache); i++) {
        if(m_timeframeCache[i].ema9Handle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[i].ema9Handle);
        }
        if(m_timeframeCache[i].ema21Handle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[i].ema21Handle);
        }
        if(m_timeframeCache[i].atrHandle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[i].atrHandle);
        }
        if(m_timeframeCache[i].adxHandle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[i].adxHandle);
        }
    }
    
    // Call Deinitialize if needed
    if(m_initialized) {
        Deinitialize();
    }
}

//+------------------------------------------------------------------+
//| Initialize performance arrays                                    |
//+------------------------------------------------------------------+
void DecisionEngine::InitializePerformanceArrays()
{
    // Pre-allocate arrays with initial size (optimized for typical usage)
    int initialSize = 10;
    ArrayResize(m_symbolParams, initialSize);
    ArrayResize(m_lastDecision, initialSize);
    ArrayResize(m_lastCommentUpdate, initialSize);
    ArrayResize(m_lastTickProcessTime, initialSize);
    ArrayResize(m_symbolCache, initialSize);
    ArrayResize(m_decisionCache, initialSize);
    ArrayResize(m_timeframeCache, initialSize);
    ArrayResize(m_positionCache, initialSize);
    ArrayResize(m_symbolDataCache, initialSize);
    
    // Initialize position cache timestamps
    for(int i = 0; i < initialSize; i++) {
        m_positionCache[i].lastUpdate = 0;
        m_symbolDataCache[i].lastUpdate = 0;
        m_decisionCache[i].timestamp = 0; // Invalidate all caches
    }
}

//+------------------------------------------------------------------+
//| Initialize trade logging system                                  |
//+------------------------------------------------------------------+
void DecisionEngine::InitializeTradeLogging()
{
    m_tradeLogIndex = 0;
    m_maxTradeLogs = 100;
    ArrayResize(m_tradeLogs, m_maxTradeLogs);
    
    // Initialize daily stats
    m_dailyStats.date = TimeCurrent();
    m_dailyStats.totalTrades = 0;
    m_dailyStats.winningTrades = 0;
    m_dailyStats.losingTrades = 0;
    m_dailyStats.totalProfit = 0.0;
    m_dailyStats.largestWin = 0.0;
    m_dailyStats.largestLoss = 0.0;
    m_dailyStats.buyTrades = 0;
    m_dailyStats.sellTrades = 0;
    
    if(m_logger != NULL) {
        m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                         "Trade logging system initialized", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Log trade execution with enhanced details                        |
//+------------------------------------------------------------------+
void DecisionEngine::LogTradeExecution(string symbol, DECISION_ACTION action, bool executed, 
                                      double confidence, double profit, int positionsBefore, 
                                      int positionsAfter, string details)
{
    // Create trade log entry
    TradeLog logEntry;
    logEntry.timestamp = TimeCurrent();
    logEntry.symbol = symbol;
    logEntry.action = action;
    logEntry.confidence = confidence;
    logEntry.executed = executed;
    logEntry.profit = profit;
    logEntry.positionsBefore = positionsBefore;
    logEntry.positionsAfter = positionsAfter;
    logEntry.details = details;
    
    // Store in circular buffer
    m_tradeLogs[m_tradeLogIndex] = logEntry;
    m_tradeLogIndex = (m_tradeLogIndex + 1) % m_maxTradeLogs;
    
    // Update daily statistics
    UpdateDailyStats(action, executed, profit);
    
    // Log to ResourceManager
    if(m_logger != NULL) {
        string actionStr = DecisionToString(action);
        string status = executed ? "EXECUTED" : "FAILED";
        
        m_logger.StartContextWith(symbol, "TradeExecution");
        m_logger.AddToContext(symbol, "Action", actionStr, true);
        m_logger.AddToContext(symbol, "Status", status);
        m_logger.AddDoubleContext(symbol, "Confidence", confidence, 1);
        m_logger.AddDoubleContext(symbol, "Profit", profit, 2);
        m_logger.AddDoubleContext(symbol, "PositionsBefore", positionsBefore, 0);
        m_logger.AddDoubleContext(symbol, "PositionsAfter", positionsAfter, 0);
        m_logger.AddDoubleContext(symbol, "PositionChange", positionsAfter - positionsBefore, 0);
        
        if(details != "") {
            m_logger.AddToContext(symbol, "Details", details);
        }
        
        // Log level based on execution result
        int logLevel = executed ? AUTHORIZE : ENFORCE;
        string message = StringFormat("%s %s | Confidence: %.1f%% | Profit: $%.2f | Positions: %d→%d", 
                                     actionStr, status, confidence, profit, positionsBefore, positionsAfter);
        
        m_logger.FlushContext(symbol, OBSERVE, "DecisionEngine_Trade", message, true);
    }
}

//+------------------------------------------------------------------+
//| Log position change                                              |
//+------------------------------------------------------------------+
void DecisionEngine::LogPositionChange(string symbol, string changeType, int countBefore, 
                                      int countAfter, double volumeChange)
{
    if(m_logger != NULL) {
        m_logger.StartContextWith(symbol, "PositionChange");
        m_logger.AddToContext(symbol, "ChangeType", changeType);
        m_logger.AddDoubleContext(symbol, "CountBefore", countBefore, 0);
        m_logger.AddDoubleContext(symbol, "CountAfter", countAfter, 0);
        m_logger.AddDoubleContext(symbol, "VolumeChange", volumeChange, 2);
        m_logger.AddDoubleContext(symbol, "NetChange", countAfter - countBefore, 0);
        
        string message = StringFormat("Position %s: %d → %d (Δ: %d) | Volume Δ: %.2f", 
                                     changeType, countBefore, countAfter, 
                                     countAfter - countBefore, volumeChange);
        
        m_logger.FlushContext(symbol, OBSERVE, "DecisionEngine_PositionChange", message, false);
    }
}

//+------------------------------------------------------------------+
//| Log market conditions                                            |
//+------------------------------------------------------------------+
void DecisionEngine::LogMarketConditions(string symbol, double confidence, MARKET_DIRECTION direction,
                                        double trendStrength, double volatility)
{
    if(m_logger != NULL) {
        string directionStr = "UNKNOWN";
        switch(direction) {
            case DIRECTION_BULLISH: directionStr = "BULLISH"; break;
            case DIRECTION_BEARISH: directionStr = "BEARISH"; break;
            case DIRECTION_RANGING: directionStr = "RANGING"; break;
            case DIRECTION_UNCLEAR: directionStr = "UNCLEAR"; break;
        }
        
        m_logger.StartContextWith(symbol, "MarketConditions");
        m_logger.AddDoubleContext(symbol, "Confidence", confidence, 1);
        m_logger.AddToContext(symbol, "Direction", directionStr);
        m_logger.AddDoubleContext(symbol, "TrendStrength", trendStrength, 1);
        m_logger.AddDoubleContext(symbol, "Volatility", volatility, 2);
        
        string message = StringFormat("Market: %s | Confidence: %.1f%% | Trend: %.1f | Volatility: %.2f%%", 
                                     directionStr, confidence, trendStrength, volatility);
        
        m_logger.FlushContext(symbol, OBSERVE, "DecisionEngine_Market", message, false);
    }
}

//+------------------------------------------------------------------+
//| Log trade summary                                                |
//+------------------------------------------------------------------+
void DecisionEngine::LogTrade(string symbol, DECISION_ACTION action, bool executed, double confidence, 
                             double profit, string details)
{
    PositionAnalysis positions = AnalyzePositions(symbol);
    int totalPositions = positions.buyCount + positions.sellCount;
    
    LogTradeExecution(symbol, action, executed, confidence, profit, totalPositions, 
                     totalPositions, details);
}

void DecisionEngine::UpdateDailyStats(DECISION_ACTION action, bool executed, double profit)
{
    if(!executed) return;
    
    datetime currentTime = TimeCurrent();
    datetime statsDate = m_dailyStats.date;
    
    // Reset stats if new day
    MqlDateTime currentStruct, statsStruct;
    TimeToStruct(currentTime, currentStruct);
    TimeToStruct(statsDate, statsStruct);
    
    if(currentStruct.day != statsStruct.day || 
       currentStruct.mon != statsStruct.mon ||
       currentStruct.year != statsStruct.year) {
        m_dailyStats.date = currentTime;
        m_dailyStats.totalTrades = 0;
        m_dailyStats.winningTrades = 0;
        m_dailyStats.losingTrades = 0;
        m_dailyStats.totalProfit = 0.0;
        m_dailyStats.largestWin = 0.0;
        m_dailyStats.largestLoss = 0.0;
        m_dailyStats.buyTrades = 0;
        m_dailyStats.sellTrades = 0;
        
        if(m_logger != NULL) {
            m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                             "Daily stats reset for new day", false, false, 0.0);
        }
    }
    
    // Update stats
    m_dailyStats.totalTrades++;
    
    if(profit > 0) {
        m_dailyStats.winningTrades++;
        m_dailyStats.largestWin = MathMax(m_dailyStats.largestWin, profit);
    } else if(profit < 0) {
        m_dailyStats.losingTrades++;
        m_dailyStats.largestLoss = MathMin(m_dailyStats.largestLoss, profit);
    }
    
    m_dailyStats.totalProfit += profit;
    
    // Track buy/sell trades
    if(action == ACTION_OPEN_BUY || action == ACTION_ADD_BUY) {
        m_dailyStats.buyTrades++;
    } else if(action == ACTION_OPEN_SELL || action == ACTION_ADD_SELL) {
        m_dailyStats.sellTrades++;
    }
    
    // Log daily summary every 10 trades or once an hour
    static int lastTradeCount = 0;
    static datetime lastLogTime = 0;
    
    if(m_dailyStats.totalTrades % 10 == 0 || 
       (currentTime - lastLogTime) >= 3600) {
        
        double winRate = (m_dailyStats.totalTrades > 0) ? 
                        ((double)m_dailyStats.winningTrades / m_dailyStats.totalTrades * 100.0) : 0.0;
        
        if(m_logger != NULL) {
            m_logger.StartContextWith(STR_SYSTEM, "DailySummary");
            m_logger.AddDoubleContext(STR_SYSTEM, "TotalTrades", m_dailyStats.totalTrades, 0);
            m_logger.AddDoubleContext(STR_SYSTEM, "WinningTrades", m_dailyStats.winningTrades, 0);
            m_logger.AddDoubleContext(STR_SYSTEM, "LosingTrades", m_dailyStats.losingTrades, 0);
            m_logger.AddDoubleContext(STR_SYSTEM, "WinRate", winRate, 1);
            m_logger.AddDoubleContext(STR_SYSTEM, "TotalProfit", m_dailyStats.totalProfit, 2);
            m_logger.AddDoubleContext(STR_SYSTEM, "LargestWin", m_dailyStats.largestWin, 2);
            m_logger.AddDoubleContext(STR_SYSTEM, "LargestLoss", m_dailyStats.largestLoss, 2);
            m_logger.AddDoubleContext(STR_SYSTEM, "BuyTrades", m_dailyStats.buyTrades, 0);
            m_logger.AddDoubleContext(STR_SYSTEM, "SellTrades", m_dailyStats.sellTrades, 0);
            
            string message = StringFormat("Daily Summary: %d trades | Win Rate: %.1f%% | P&L: $%.2f", 
                                         m_dailyStats.totalTrades, winRate, m_dailyStats.totalProfit);
            
            m_logger.FlushContext(STR_SYSTEM, AUDIT, "DecisionEngine_DailySummary", message, true);
        }
        
        lastTradeCount = m_dailyStats.totalTrades;
        lastLogTime = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Get trade history                                                |
//+------------------------------------------------------------------+
string DecisionEngine::GetTradeHistory(int count = 10)
{
    string history = "Recent Trades:\n";
    history += "═══════════════════════════════════════════\n";
    
    int actualCount = MathMin(count, m_maxTradeLogs);
    int startIndex = (m_tradeLogIndex - actualCount + m_maxTradeLogs) % m_maxTradeLogs;
    
    for(int i = 0; i < actualCount; i++) {
        int index = (startIndex + i) % m_maxTradeLogs;
        TradeLog log = m_tradeLogs[index];
        
        if(log.timestamp > 0) {
            string timeStr = TimeToString(log.timestamp, TIME_MINUTES);
            string actionStr = DecisionToString(log.action);
            string status = log.executed ? "✓" : "✗";
            
            history += StringFormat("%s | %s %s | %.1f%% | $%.2f | %s\n",
                                  timeStr, actionStr, status, log.confidence, 
                                  log.profit, log.details);
        }
    }
    
    history += "═══════════════════════════════════════════\n";
    return history;
}

//+------------------------------------------------------------------+
//| Log trade summary                                                |
//+------------------------------------------------------------------+
void DecisionEngine::LogTradeSummary()
{
    string summary = GetTradeHistory(20);
    
    if(m_logger != NULL) {
        m_logger.KeepNotes(STR_SYSTEM, AUDIT, STR_DECISION_ENGINE, summary, true, false, 0.0);
    }
    
    Print(summary);
}

//+------------------------------------------------------------------+
//| Debug logging helper                                             |
//+------------------------------------------------------------------+
void DecisionEngine::DebugLog(string symbol, string message)
{
    if(m_debugMode && m_logger != NULL) {
        m_logger.KeepNotes(symbol, OBSERVE, STR_DECISION_ENGINE, message, false, false, 0.0);
    }
    if(m_debugMode) {
        Print(StringFormat("[%s] %s", symbol, message));
    }
}

//+------------------------------------------------------------------+
//| Debug condition check                                            |
//+------------------------------------------------------------------+
void DecisionEngine::DebugLogConditionCheck(string symbol, string condition, bool result, string details)
{
    if(m_debugMode) {
        string message = StringFormat("%s: %s", condition, result ? "PASS" : "FAIL");
        if(details != "") {
            message += " | " + details;
        }
        DebugLog(symbol, message);
    }
}

//+------------------------------------------------------------------+
//| Initialize - THE ONE AND ONLY initialization method              |
//+------------------------------------------------------------------+
bool DecisionEngine::Initialize(
    ResourceManager* logger,
    PositionManager* pm,
    RiskManager* riskManager,
    string engineComment,
    int engineMagicBase,
    int slippage)
{
    // EARLY EXIT: Already initialized
    if(m_initialized) {
        Print("DecisionEngine: Already initialized");
        return true;
    }
    
    // EARLY EXIT: Validate required dependencies
    if(logger == NULL) {
        Print("DecisionEngine::Initialize - Error: Logger is NULL");
        return false;
    }
    
    // Start profiling
    StartProfiling();
    
    // Store dependencies
    m_logger = logger;
    m_riskManager = riskManager;
    
    // Start initialization context
    m_logger.StartContextWith(STR_SYSTEM, "DECISION_ENGINE_INIT");
    
    // 1. Set configuration parameters
    m_engineComment = (engineComment == "") ? "AutoDecisionEngine" : engineComment;
    m_engineMagicBase = (engineMagicBase == 0) ? 12345 : engineMagicBase;
    m_slippage = (slippage == 0) ? 5 : slippage;
    
    // 2. Initialize tracking variables
    m_totalDecisions = 0;
    m_correctDecisions = 0;
    m_decisionAccuracy = 0.0;
    m_totalSymbols = 0;
    m_lastTickTime = 0;
    m_lastTimerTime = TimeCurrent();
    m_timerIntervalSeconds = 60;
    
    // 3. Set default external functions if none provided
    if(m_getConfidence == NULL) {
        m_getConfidence = StaticDefaultGetConfidence;
        m_logger.AddToContext(STR_SYSTEM, "ConfidenceFunction", "DEFAULT");
    }
    
    if(m_getMarketDirection == NULL) {
        m_getMarketDirection = StaticDefaultGetMarketDirection;
        m_logger.AddToContext(STR_SYSTEM, "DirectionFunction", "DEFAULT");
    }
    
    if(m_isMarketRanging == NULL) {
        m_isMarketRanging = StaticDefaultIsMarketRanging;
        m_logger.AddToContext(STR_SYSTEM, "RangingFunction", "DEFAULT");
    }
    
    // 4. Initialize arrays
    InitializePerformanceArrays();
    
    // 5. Initialize trade logging
    InitializeTradeLogging();
    
    // 6. Mark as initialized
    m_initialized = true;
    
    // 7. Log successful initialization
    m_logger.AddToContext(STR_SYSTEM, "Status", "INITIALIZED");
    m_logger.AddToContext(STR_SYSTEM, "EngineName", m_engineComment);
    m_logger.AddDoubleContext(STR_SYSTEM, "MagicBase", m_engineMagicBase, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "Slippage", m_slippage, 0);
    m_logger.AddToContext(STR_SYSTEM, "SymbolCount", (string)m_totalSymbols);
    m_logger.FlushContext(STR_SYSTEM, AUTHORIZE, "DecisionEngine_Initialize", 
                       StringFormat("Decision Engine initialized successfully: %s", m_engineComment), 
                       true);
    
    // 8. Print to console (only once during initialization)
    Print("========================================");
    Print("DECISION ENGINE INITIALIZED");
    Print("========================================");
    Print("Engine Name: ", m_engineComment);
    Print("Magic Base: ", m_engineMagicBase);
    Print("Slippage: ", m_slippage);
    Print("Logger: ", (m_logger != NULL ? "SET" : "NULL"));
    Print("RiskManager: ", (m_riskManager != NULL ? "SET" : "NULL"));
    Print("Symbols: ", m_totalSymbols);
    Print("Timer Interval: ", m_timerIntervalSeconds, " seconds");
    Print("Comment Throttle: ", m_commentThrottleSeconds, " seconds");
    Print("Performance Mode: ", m_isTesterMode ? "TESTER" : "LIVE");
    Print("Debug Mode: ", m_debugMode ? "ENABLED" : "DISABLED");
    Print("Decision Caching: ", m_skipUnchangedConditions ? "ENABLED" : "DISABLED");
    Print("Batch Processing: Every ", m_batchProcessingInterval, " seconds");
    Print("Testing Mode: ", m_testingMode ? "ENABLED" : "DISABLED");
    Print("Trade Logging: ENABLED (100 trades memory)");
    Print("========================================");
    
    StopProfiling();
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize - Cleanup counterpart                               |
//+------------------------------------------------------------------+
void DecisionEngine::Deinitialize()
{
    if(!m_initialized) {
        Print("DecisionEngine: Not initialized, skipping deinitialization");
        return;
    }
    
    StartProfiling();
    m_logger.StartContextWith(STR_SYSTEM, "DECISION_ENGINE_DEINIT");
    
    // 1. Close all positions safely
    int positionsClosed = 0;
    for(int i = 0; i < m_totalSymbols; i++) {
        string symbol = m_symbolParams[i].symbol;
        PositionManager* pm = m_symbolParams[i].positionManager;
        
        if(pm != NULL) {
            if(pm.CloseAllPositions(symbol)) {
                positionsClosed++;
                m_logger.AddToContext(STR_SYSTEM, StringFormat("%s_Positions", symbol), "CLOSED");
            }
        }
    }
    
    // 2. Cleanup resources
    Cleanup();
    
    // 3. Reset dependencies
    m_logger = NULL;
    m_riskManager = NULL;
    
    // 4. Reset flags
    m_initialized = false;
    
    // 5. Log performance metrics before deinitialization
    LogPerformanceMetrics();
    
    // 6. Log final trade summary
    LogTradeSummary();
    
    // 7. Log deinitialization
    m_logger.AddDoubleContext(STR_SYSTEM, "PositionsClosed", positionsClosed, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "TotalDecisions", m_totalDecisions, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "FinalAccuracy", m_decisionAccuracy, 1);
    m_logger.FlushContext(STR_SYSTEM, AUDIT, "DecisionEngine_Deinitialize", 
                       StringFormat("Decision Engine deinitialized: %d positions closed", 
                                  positionsClosed), 
                       true);
    
    StopProfiling();
    
    // 8. Print summary to console (only once during deinitialization)
    Print("========================================");
    Print("DECISION ENGINE DEINITIALIZED");
    Print("========================================");
    Print("Positions Closed: ", positionsClosed);
    Print("Total Decisions Made: ", m_totalDecisions);
    Print("Final Decision Accuracy: ", m_decisionAccuracy, "%");
    Print("Total Trades Executed: ", m_performance.tradesExecuted);
    Print("Engine Name: ", m_engineComment);
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Cache invalidation methods                                       |
//+------------------------------------------------------------------+
void DecisionEngine::InvalidateDecisionCache(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_decisionCache)) {
        m_decisionCache[index].timestamp = 0; // Invalidate cache
        DebugLog(symbol, "Decision cache invalidated");
    }
}

void DecisionEngine::InvalidateAllCaches()
{
    for(int i = 0; i < ArraySize(m_decisionCache); i++) {
        m_decisionCache[i].timestamp = 0;
    }
    for(int i = 0; i < ArraySize(m_symbolCache); i++) {
        m_symbolCache[i].lastMarketAnalysisTime = 0;
    }
    for(int i = 0; i < ArraySize(m_positionCache); i++) {
        m_positionCache[i].lastUpdate = 0;
    }
    for(int i = 0; i < ArraySize(m_symbolDataCache); i++) {
        m_symbolDataCache[i].lastUpdate = 0;
    }
    DebugLog(STR_SYSTEM, "All caches invalidated");
}

void DecisionEngine::ForceRefresh(string symbol)
{
    InvalidateDecisionCache(symbol);
    DebugLog(symbol, "Forced refresh - caches cleared");
}

//+------------------------------------------------------------------+
//| Start profiling                                                  |
//+------------------------------------------------------------------+
void DecisionEngine::StartProfiling()
{
    m_performance.lastProfileTime = GetMicrosecondCount();
}

//+------------------------------------------------------------------+
//| Stop profiling                                                   |
//+------------------------------------------------------------------+
void DecisionEngine::StopProfiling()
{
    ulong endTime = GetMicrosecondCount();
    ulong elapsed = endTime - m_performance.lastProfileTime;
    double elapsedMs = elapsed / 1000.0;
    
    m_performance.totalProcessingTimeMs += elapsedMs;
    m_performance.maxProcessingTimeMs = MathMax(m_performance.maxProcessingTimeMs, elapsedMs);
    
    if(m_performance.totalTicksProcessed > 0) {
        m_performance.avgProcessingTimeMs = m_performance.totalProcessingTimeMs / m_performance.totalTicksProcessed;
    }
}

//+------------------------------------------------------------------+
//| Log performance metrics                                          |
//+------------------------------------------------------------------+
void DecisionEngine::LogPerformanceMetrics()
{
    if(m_performance.totalTicksProcessed == 0) return;
    
    datetime now = TimeCurrent();
    if(now - m_performance.lastProfileTime < 300) return; // Log every 5 minutes
    
    m_logger.StartContextWith(STR_SYSTEM, "PERFORMANCE_METRICS");
    m_logger.AddDoubleContext(STR_SYSTEM, "TotalTicks", m_performance.totalTicksProcessed, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "TicksSkipped", m_performance.ticksSkipped, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "DecisionsMade", m_performance.decisionsMade, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "TradesExecuted", m_performance.tradesExecuted, 0);
    m_logger.AddDoubleContext(STR_SYSTEM, "AvgProcessingTimeMs", m_performance.avgProcessingTimeMs, 2);
    m_logger.AddDoubleContext(STR_SYSTEM, "MaxProcessingTimeMs", m_performance.maxProcessingTimeMs, 2);
    m_logger.AddDoubleContext(STR_SYSTEM, "SkipRate", 
                            (double)m_performance.ticksSkipped / m_performance.totalTicksProcessed * 100.0, 1);
    m_logger.FlushContext(STR_SYSTEM, AUDIT, "DecisionEngine_Performance", 
                       "Performance metrics report", 
                       false);
    
    m_performance.lastProfileTime = now;
}

//+------------------------------------------------------------------+
//| Should use cached market analysis? - MINIMAL CACHING            |
//+------------------------------------------------------------------+
bool DecisionEngine::ShouldUseCachedMarketAnalysis(string symbol)
{
    // In testing mode, never use cache
    if(m_testingMode) return false;
    
    // Minimal cache: only 5 seconds TTL
    int index = FindSymbolIndex(symbol);
    if(index < 0 || index >= ArraySize(m_symbolCache)) return false;
    
    datetime currentTime = TimeCurrent();
    datetime cacheTime = m_symbolCache[index].lastMarketAnalysisTime;
    
    // Use cache if less than 5 seconds old (was 60 seconds)
    return (currentTime - cacheTime < 5);
}

//+------------------------------------------------------------------+
//| Get cached market analysis                                       |
//+------------------------------------------------------------------+
MarketAnalysis DecisionEngine::GetCachedMarketAnalysis(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_symbolCache)) {
        return m_symbolCache[index].cachedMarketAnalysis;
    }
    
    MarketAnalysis empty;
    ZeroMemory(empty);
    return empty;
}

//+------------------------------------------------------------------+
//| Update market analysis cache                                     |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateMarketAnalysisCache(string symbol, MarketAnalysis &analysis)
{
    // In testing mode, don't update cache
    if(m_testingMode) return;
    
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        if(ArraySize(m_symbolCache) <= index) {
            ArrayResize(m_symbolCache, m_totalSymbols);
        }
        m_symbolCache[index].symbol = symbol;
        m_symbolCache[index].cachedMarketAnalysis = analysis;
        m_symbolCache[index].lastMarketAnalysisTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Should use cached decision? - MINIMAL CACHING                   |
//+------------------------------------------------------------------+
bool DecisionEngine::ShouldUseCachedDecision(string symbol, double confidence, MARKET_DIRECTION direction)
{
    // In testing mode, never use cache
    if(m_testingMode || !m_skipUnchangedConditions) return false;
    
    int index = FindSymbolIndex(symbol);
    if(index < 0 || index >= ArraySize(m_symbolCache)) return false;
    
    // Check if confidence and direction haven't changed significantly
    bool confidenceSimilar = MathAbs(confidence - m_symbolCache[index].lastConfidence) < 1.0; // Was 5.0
    bool directionSame = (direction == m_symbolCache[index].lastDirection);
    
    // Only cache for 5 seconds max (was 30 seconds)
    datetime currentTime = TimeCurrent();
    bool cacheFresh = (currentTime - m_decisionCache[index].timestamp < 5);
    
    return (confidenceSimilar && directionSame && cacheFresh);
}

//+------------------------------------------------------------------+
//| Get cached decision                                              |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::GetCachedDecision(string symbol)
{
    // In testing mode, never return cached decision
    if(m_testingMode) return ACTION_NONE;
    
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_decisionCache)) {
        if(m_decisionCache[index].timestamp > 0 && 
           (TimeCurrent() - m_decisionCache[index].timestamp) < 5) { // Was 30 seconds
            return m_decisionCache[index].action;
        }
    }
    return ACTION_NONE;
}

//+------------------------------------------------------------------+
//| Update decision cache                                            |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateDecisionCache(string symbol, DECISION_ACTION decision, double confidence, MARKET_DIRECTION direction)
{
    // In testing mode, don't update cache
    if(m_testingMode) return;
    
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        if(ArraySize(m_decisionCache) <= index) {
            ArrayResize(m_decisionCache, m_totalSymbols);
        }
        m_decisionCache[index].action = decision;
        m_decisionCache[index].confidence = confidence;
        m_decisionCache[index].direction = direction;
        m_decisionCache[index].timestamp = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Should process batch?                                            |
//+------------------------------------------------------------------+
bool DecisionEngine::ShouldProcessBatch()
{
    // In testing mode, always process
    if(m_testingMode) return true;
    
    datetime currentTime = TimeCurrent();
    return (currentTime - m_lastBatchProcessTime >= m_batchProcessingInterval);
}

//+------------------------------------------------------------------+
//| Process symbol batch                                             |
//+------------------------------------------------------------------+
void DecisionEngine::ProcessSymbolBatch()
{
    if(!ShouldProcessBatch()) return;
    
    StartProfiling();
    
    // Update timeframe cache for all symbols in batch
    for(int i = 0; i < m_totalSymbols; i++) {
        UpdateTimeframeCache(m_symbolParams[i].symbol);
    }
    
    m_lastBatchProcessTime = TimeCurrent();
    
    StopProfiling();
    
    // Log batch processing (throttled)
    static datetime lastBatchLog = 0;
    if(TimeCurrent() - lastBatchLog > 300) { // Log every 5 minutes
        m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                        "Batch processing completed", false, false, 0.0);
        lastBatchLog = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Update timeframe cache with indicator handle caching             |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateTimeframeCache(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index < 0) return;
    
    if(ArraySize(m_timeframeCache) <= index) {
        ArrayResize(m_timeframeCache, m_totalSymbols);
    }
    
    // Update cache only if stale (older than 30 seconds in testing mode, 60 in production)
    int cacheTTL = m_testingMode ? 30 : 60;
    if(TimeCurrent() - m_timeframeCache[index].lastUpdate > cacheTTL) {
        // Create handles if not already created
        if(m_timeframeCache[index].ema9Handle == 0 || m_timeframeCache[index].ema9Handle == INVALID_HANDLE) {
            m_timeframeCache[index].ema9Handle = iMA(symbol, PERIOD_H1, 9, 0, MODE_EMA, PRICE_CLOSE);
        }
        if(m_timeframeCache[index].ema21Handle == 0 || m_timeframeCache[index].ema21Handle == INVALID_HANDLE) {
            m_timeframeCache[index].ema21Handle = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
        }
        if(m_timeframeCache[index].atrHandle == 0 || m_timeframeCache[index].atrHandle == INVALID_HANDLE) {
            m_timeframeCache[index].atrHandle = iATR(symbol, PERIOD_H1, 14);
        }
        if(m_timeframeCache[index].adxHandle == 0 || m_timeframeCache[index].adxHandle == INVALID_HANDLE) {
            m_timeframeCache[index].adxHandle = iADX(symbol, PERIOD_H1, 14);
        }
        
        // Use handles to get values with batch copying
        double ema9Buffer[1], ema21Buffer[1], atrBuffer[1];
        
        if(m_timeframeCache[index].ema9Handle != INVALID_HANDLE) {
            if(CopyBuffer(m_timeframeCache[index].ema9Handle, 0, 0, 1, ema9Buffer) == 1) {
                m_timeframeCache[index].ema9 = ema9Buffer[0];
            }
        }
        
        if(m_timeframeCache[index].ema21Handle != INVALID_HANDLE) {
            if(CopyBuffer(m_timeframeCache[index].ema21Handle, 0, 0, 1, ema21Buffer) == 1) {
                m_timeframeCache[index].ema21 = ema21Buffer[0];
            }
        }
        
        if(m_timeframeCache[index].atrHandle != INVALID_HANDLE) {
            if(CopyBuffer(m_timeframeCache[index].atrHandle, 0, 0, 1, atrBuffer) == 1) {
                m_timeframeCache[index].atr = atrBuffer[0];
            }
        }
        
        m_timeframeCache[index].lastUpdate = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Get cached EMA9 with handle caching                              |
//+------------------------------------------------------------------+
double DecisionEngine::GetCachedEMA9(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_timeframeCache)) {
        // Ensure cache is updated
        UpdateTimeframeCache(symbol);
        return m_timeframeCache[index].ema9;
    }
    return iMA(symbol, PERIOD_H1, 9, 0, MODE_EMA, PRICE_CLOSE);
}

//+------------------------------------------------------------------+
//| Get cached EMA21 with handle caching                             |
//+------------------------------------------------------------------+
double DecisionEngine::GetCachedEMA21(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_timeframeCache)) {
        UpdateTimeframeCache(symbol);
        return m_timeframeCache[index].ema21;
    }
    return iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
}

//+------------------------------------------------------------------+
//| Get cached ATR with handle caching                               |
//+------------------------------------------------------------------+
double DecisionEngine::GetCachedATR(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_timeframeCache)) {
        UpdateTimeframeCache(symbol);
        return m_timeframeCache[index].atr;
    }
    return iATR(symbol, PERIOD_H1, 14);
}

//+------------------------------------------------------------------+
//| Update symbol data cache                                         |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateSymbolData(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index < 0) return;
    
    if(ArraySize(m_symbolDataCache) <= index) {
        ArrayResize(m_symbolDataCache, m_totalSymbols);
    }
    
    datetime currentTime = TimeCurrent();
    // Update only if cache is stale (100ms in testing, 500ms in production)
    int cacheTTL = m_testingMode ? 100 : 500;
    if(currentTime - m_symbolDataCache[index].lastUpdate > (cacheTTL / 1000.0)) {
        m_symbolDataCache[index].symbol = symbol;
        m_symbolDataCache[index].point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        m_symbolDataCache[index].tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        m_symbolDataCache[index].bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        m_symbolDataCache[index].ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        m_symbolDataCache[index].lastUpdate = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Update position cache                                            |
//+------------------------------------------------------------------+
void DecisionEngine::UpdatePositionCache(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index < 0) return;
    
    if(ArraySize(m_positionCache) <= index) {
        ArrayResize(m_positionCache, m_totalSymbols);
    }
    
    // Update cache only if stale (500ms in testing, 1 second in production)
    int cacheTTL = m_testingMode ? 500 : 1000;
    if(TimeCurrent() - m_positionCache[index].lastUpdate > (cacheTTL / 1000.0)) {
        m_positionCache[index].symbol = symbol;
        m_positionCache[index].buyCount = 0;
        m_positionCache[index].sellCount = 0;
        m_positionCache[index].totalBuyVolume = 0;
        m_positionCache[index].totalSellVolume = 0;
        
        int positionsTotal = PositionsTotal();
        // Use backward iteration for efficiency
        for(int i = positionsTotal - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket)) {
                if(PositionGetString(POSITION_SYMBOL) == symbol) {
                    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    double volume = PositionGetDouble(POSITION_VOLUME);
                    
                    if(type == POSITION_TYPE_BUY) {
                        m_positionCache[index].buyCount++;
                        m_positionCache[index].totalBuyVolume += volume;
                    } else if(type == POSITION_TYPE_SELL) {
                        m_positionCache[index].sellCount++;
                        m_positionCache[index].totalSellVolume += volume;
                    }
                }
            }
        }
        m_positionCache[index].lastUpdate = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Should process symbol? (Performance optimization)                |
//+------------------------------------------------------------------+
bool DecisionEngine::ShouldProcessSymbol(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index < 0) return false;
    
    // Performance tracking
    m_performance.totalTicksProcessed++;
    
    // In testing mode, process more frequently
    if(m_testingMode) {
        // Process every tick in testing mode
        return true;
    }
    
    // In tester mode during fast-forward, reduce processing frequency
    if(m_isTesterMode) {
        // Only process every 3rd tick during fast-forward
        static int tickCounter = 0;
        tickCounter++;
        if(tickCounter % 3 != 0) {
            m_performance.ticksSkipped++;
            return false;
        }
    }
    
    // Don't process if recently processed (min 1 second between for same symbol in production)
    datetime currentTime = TimeCurrent();
    
    if(ArraySize(m_lastTickProcessTime) <= index) {
        // Initialize array if needed
        ArrayResize(m_lastTickProcessTime, m_totalSymbols);
        for(int i = 0; i < m_totalSymbols; i++) {
            m_lastTickProcessTime[i] = 0;
        }
    }
    
    int minProcessInterval = m_testingMode ? 1 : 2; // 1 second in testing, 2 in production
    bool shouldProcess = (currentTime - m_lastTickProcessTime[index] >= minProcessInterval);
    if(!shouldProcess) {
        m_performance.ticksSkipped++;
    }
    
    return shouldProcess;
}

//+------------------------------------------------------------------+
//| TICK FUNCTION - Optimized for minimal caching                   |
//+------------------------------------------------------------------+
void DecisionEngine::OnTick()
{
    StartProfiling();
    
    // EARLY EXIT: ONLY process if initialized
    if(!m_initialized) {
        StopProfiling();
        return;
    }
    
    // EARLY EXIT: Skip if no symbols
    if(m_totalSymbols <= 0) {
        StopProfiling();
        return;
    }
    
    // DEBUG: Log when called
    if(m_logger != NULL && m_debugMode) {
        static int tickCounter = 0;
        tickCounter++;
        if(tickCounter % 50 == 0) { // Log every 50 ticks (was 100)
            m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                            StringFormat("OnTick called (#%d) - Processing %d symbols", 
                                        tickCounter, m_totalSymbols), 
                            false, false, 0.0);
        }
    }
    
    // Process batch updates if needed
    ProcessSymbolBatch();
    
    // Process all configured symbols with early exits
    int decisionsMade = 0;
    int symbolsProcessed = 0;
    
    for(int i = 0; i < m_totalSymbols; i++) {
        string symbol = m_symbolParams[i].symbol;
        
        // Performance check: should we process this symbol now?
        if(!ShouldProcessSymbol(symbol)) {
            continue;
        }
        
        symbolsProcessed++;
        
        // Track processing time
        if(ArraySize(m_lastTickProcessTime) <= i) {
            ArrayResize(m_lastTickProcessTime, m_totalSymbols);
        }
        m_lastTickProcessTime[i] = TimeCurrent();
        
        // Update symbol data cache
        UpdateSymbolData(symbol);
        
        // 1. Get confidence from external function or default (NO CACHING in testing)
        double confidence = (m_getConfidence != NULL) ? m_getConfidence(symbol) : 50.0;
        
        // EARLY EXIT: Check confidence validity
        if(confidence < 0 || confidence > 100) {
            DebugLog(symbol, StringFormat("Invalid confidence: %.1f", confidence));
            continue;
        }
        
        // Update cache (only if not in testing mode)
        if(!m_testingMode) {
            int cacheIndex = FindSymbolIndex(symbol);
            if(cacheIndex >= 0 && cacheIndex < ArraySize(m_symbolCache)) {
                m_symbolCache[cacheIndex].lastConfidence = confidence;
            }
        }
        
        // 2. Get market direction (NO CACHING in testing mode)
        MARKET_DIRECTION direction;
        if(ShouldUseCachedMarketAnalysis(symbol)) {
            MarketAnalysis cached = GetCachedMarketAnalysis(symbol);
            direction = cached.direction;
            if(m_debugMode) DebugLog(symbol, "Using cached market analysis");
        } else {
            direction = DetermineMarketDirection(symbol);
            if(m_debugMode) DebugLog(symbol, "Fresh market analysis");
        }
        
        // Update cache (only if not in testing mode)
        if(!m_testingMode) {
            int cacheIndex = FindSymbolIndex(symbol);
            if(cacheIndex >= 0 && cacheIndex < ArraySize(m_symbolCache)) {
                m_symbolCache[cacheIndex].lastDirection = direction;
            }
        }
        
        // 3. Check if we can use cached decision (MINIMAL in testing)
        DECISION_ACTION cachedDecision = ACTION_NONE;
        if(ShouldUseCachedDecision(symbol, confidence, direction)) {
            cachedDecision = GetCachedDecision(symbol);
            if(m_debugMode && cachedDecision != ACTION_NONE) {
                DebugLog(symbol, StringFormat("Using cached decision: %s", DecisionToString(cachedDecision)));
            }
        }
        
        DECISION_ACTION decision;
        if(cachedDecision != ACTION_NONE) {
            decision = cachedDecision;
        } else {
            // 4. Make decision (with minimal logging)
            if(m_debugMode) DebugLog(symbol, "Making fresh decision...");
            decision = MakeDecision(symbol, confidence, direction);
            m_performance.decisionsMade++;
            
            // Update decision cache (only if not in testing mode)
            if(!m_testingMode) {
                UpdateDecisionCache(symbol, decision, confidence, direction);
            }
        }
        
        // 5. Execute decision if actionable
        if(decision != ACTION_NONE && decision != ACTION_HOLD && decision != ACTION_THINKING) {
            if(m_debugMode) DebugLog(symbol, StringFormat("Executing decision: %s", DecisionToString(decision)));
            
            // Get position count before execution
            PositionAnalysis positionsBefore = AnalyzePositions(symbol);
            int totalPositionsBefore = positionsBefore.buyCount + positionsBefore.sellCount;
            
            ExecuteDecision(symbol, decision, confidence);
            decisionsMade++;
            m_performance.tradesExecuted++;
            
            // Get position count after execution
            PositionAnalysis positionsAfter = AnalyzePositions(symbol);
            int totalPositionsAfter = positionsAfter.buyCount + positionsAfter.sellCount;
            
            // Log position change
            if(totalPositionsBefore != totalPositionsAfter) {
                LogPositionChange(symbol, "Trade Execution", totalPositionsBefore, 
                                totalPositionsAfter, positionsAfter.totalProfit - positionsBefore.totalProfit);
            }
            
            // Update decision statistics
            UpdateDecisionStatistics(true);
        }
        
        // 6. Log market conditions periodically
        static datetime lastMarketLog[100] = {0};
        int symbolIndex = FindSymbolIndex(symbol);
        if(symbolIndex >= 0 && (TimeCurrent() - lastMarketLog[symbolIndex]) > 300) { // Every 5 minutes
            MarketAnalysis market = AnalyzeMarket(symbol);
            LogMarketConditions(symbol, confidence, market.direction, 
                              market.trendStrength, market.volatility);
            lastMarketLog[symbolIndex] = TimeCurrent();
        }
        
        // 7. Update last decision time for this symbol
        m_symbolParams[i].lastDecisionTime = TimeCurrent();
        m_symbolParams[i].lastDecision = decision;
    }
    
    // Log overall tick summary (throttled)
    static datetime lastTickLog = 0;
    if(TimeCurrent() - lastTickLog > (m_testingMode ? 1 : 2)) { // Throttle to every 1 second in testing
        if(m_logger != NULL && m_debugMode) {
            m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                            StringFormat("OnTick complete: Processed %d/%d symbols, Made %d decisions", 
                                        symbolsProcessed, m_totalSymbols, decisionsMade), 
                            false, false, 0.0);
        }
        lastTickLog = TimeCurrent();
    }
    
    // Update performance metrics periodically
    LogPerformanceMetrics();
    
    StopProfiling();
}

//+------------------------------------------------------------------+
//| TIMER FUNCTION - Optimized for minimal caching                  |
//+------------------------------------------------------------------+
void DecisionEngine::OnTimer()
{
    StartProfiling();
    
    // EARLY EXIT: ONLY process if initialized
    if(!m_initialized) {
        StopProfiling();
        return;
    }
    
    datetime currentTime = TimeCurrent();
    
    // Check timer interval
    if(currentTime - m_lastTimerTime < m_timerIntervalSeconds) {
        m_performance.ticksSkipped++;
        StopProfiling();
        return; // Too soon for next timer check
    }
    m_lastTimerTime = currentTime;
    
    // EARLY EXIT: Skip if no symbols
    if(m_totalSymbols <= 0) {
        StopProfiling();
        return;
    }
    
    // Only minimal logging in timer
    int emergencyActions = 0;
    
    // 1. Emergency checks for all symbols (only critical checks)
    for(int i = 0; i < m_totalSymbols; i++) {
        string symbol = m_symbolParams[i].symbol;
        CheckEmergencyConditions(symbol);
        
        // Count if any emergency action was taken
        PositionAnalysis analysis = AnalyzePositions(symbol);
        if(analysis.buyCount == 0 && analysis.sellCount == 0) {
            emergencyActions++;
        }
    }
    
    // 2. In testing mode, force cache refresh periodically
    if(m_testingMode) {
        // Force cache refresh every 30 seconds in testing mode
        static datetime lastCacheRefresh = 0;
        if(currentTime - lastCacheRefresh > 30) {
            InvalidateAllCaches();
            if(m_debugMode) DebugLog(STR_SYSTEM, "Testing mode: Forced cache refresh");
            lastCacheRefresh = currentTime;
        }
    }
    
    // 3. Log trade summary every hour
    static datetime lastTradeSummary = 0;
    if(currentTime - lastTradeSummary >= 3600) { // Every hour
        LogTradeSummary();
        lastTradeSummary = currentTime;
    }
    
    // 4. Log only if emergency actions occurred
    if(emergencyActions > 0) {
        m_logger.KeepNotes(STR_SYSTEM, ENFORCE, STR_DECISION_ENGINE, 
                        StringFormat("Emergency: %d actions taken", emergencyActions), 
                        false, false, 0.0);
    }
    
    StopProfiling();
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION FUNCTION                                       |
//+------------------------------------------------------------------+
void DecisionEngine::OnTradeTransaction()
{
    StartProfiling();
    
    // EARLY EXIT: ONLY process if initialized
    if(!m_initialized) {
        StopProfiling();
        return;
    }
    
    // Clear decision cache on trade transaction
    for(int i = 0; i < ArraySize(m_decisionCache); i++) {
        m_decisionCache[i].timestamp = 0; // Invalidate cache
    }
    
    // Invalidate position cache
    for(int i = 0; i < ArraySize(m_positionCache); i++) {
        m_positionCache[i].lastUpdate = 0;
    }
    
    if(m_debugMode) {
        DebugLog(STR_SYSTEM, "Trade transaction: Caches invalidated");
    }
    
    // Log trade transaction
    if(m_logger != NULL) {
        m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                         "Trade transaction detected", false, false, 0.0);
    }
    
    StopProfiling();
}

//+------------------------------------------------------------------+
//| Cleanup helper                                                   |
//+------------------------------------------------------------------+
void DecisionEngine::Cleanup()
{
    // Clean up all PositionManagers
    for(int i = 0; i < m_totalSymbols; i++) {
        if(m_symbolParams[i].positionManager != NULL) {
            delete m_symbolParams[i].positionManager;
            m_symbolParams[i].positionManager = NULL;
        }
    }
    
    // Reset arrays
    ArrayFree(m_symbolParams);
    ArrayFree(m_lastDecision);
    ArrayFree(m_lastCommentUpdate);
    ArrayFree(m_lastTickProcessTime);
    ArrayFree(m_symbolCache);
    ArrayFree(m_decisionCache);
    ArrayFree(m_timeframeCache);
    ArrayFree(m_positionCache);
    ArrayFree(m_symbolDataCache);
    ArrayFree(m_tradeLogs);
    m_totalSymbols = 0;
}

//+------------------------------------------------------------------+
//| Generate unique magic number for symbol                          |
//+------------------------------------------------------------------+
int DecisionEngine::GenerateMagicNumber(string symbol)
{
    // Create unique magic number based on base + symbol hash
    int symbolHash = 0;
    int strLen = StringLen(symbol); // Cache string length
    for(int i = 0; i < strLen; i++) {
        symbolHash += StringGetCharacter(symbol, i);
    }
    return m_engineMagicBase + (symbolHash % 10000);
}

//+------------------------------------------------------------------+
//| Add symbol to monitor                                            |
//+------------------------------------------------------------------+
bool DecisionEngine::AddSymbol(string symbol, DecisionParams &params)
{
    // Check if initialized
    if(!m_initialized) {
        Print("DecisionEngine::AddSymbol - Error: Not initialized");
        return false;
    }
    
    // Check if symbol already exists
    if(HasSymbol(symbol)) {
        if(m_logger != NULL) {
            m_logger.KeepNotes(symbol, WARN, STR_DECISION_ENGINE, 
                            "Symbol already exists in DecisionEngine", false, false, 0.0);
        }
        return false;
    }
    
    // Pre-allocate arrays if needed
    if(ArraySize(m_symbolParams) <= m_totalSymbols) {
        // Grow by 50% or at least 5 slots
        int newSize = MathMax(m_totalSymbols + 5, (int)(m_totalSymbols * 1.5));
        ArrayResize(m_symbolParams, newSize);
        ArrayResize(m_lastDecision, newSize);
        ArrayResize(m_symbolCache, newSize);
        ArrayResize(m_decisionCache, newSize);
        ArrayResize(m_timeframeCache, newSize);
        ArrayResize(m_lastTickProcessTime, newSize);
        ArrayResize(m_lastCommentUpdate, newSize);
        ArrayResize(m_positionCache, newSize);
        ArrayResize(m_symbolDataCache, newSize);
    }
    
    int index = m_totalSymbols;
    m_totalSymbols++;
    
    // Initialize symbol parameters
    m_symbolParams[index].symbol = symbol;
    m_symbolParams[index].params = params;
    
    // Generate unique magic number for this symbol
    int dm_magicNumber = GenerateMagicNumber(symbol);
    
    // Create PositionManager for this symbol
    m_symbolParams[index].positionManager = new PositionManager();
    
    // Initialize PositionManager with dependencies
    if(!m_symbolParams[index].positionManager.Initialize(
        m_engineComment + "_" + symbol, 
        dm_magicNumber,
        m_slippage,
        m_logger,           // Use stored logger
        m_riskManager)) {   // Use stored risk manager
        
        if(m_logger != NULL) {
            m_logger.KeepNotes(symbol, ENFORCE, STR_DECISION_ENGINE, 
                            "Failed to initialize PositionManager", false, false, 0.0);
        }
        
        delete m_symbolParams[index].positionManager;
        m_symbolParams[index].positionManager = NULL;
        m_totalSymbols--;
        // Resize arrays back
        ArrayResize(m_symbolParams, m_totalSymbols);
        ArrayResize(m_lastDecision, m_totalSymbols);
        ArrayResize(m_symbolCache, m_totalSymbols);
        ArrayResize(m_decisionCache, m_totalSymbols);
        ArrayResize(m_timeframeCache, m_totalSymbols);
        ArrayResize(m_positionCache, m_totalSymbols);
        ArrayResize(m_symbolDataCache, m_totalSymbols);
        return false;
    }
    
    // Initialize cooldown
    m_symbolParams[index].cooldown.symbol = symbol;
    m_symbolParams[index].cooldown.isBuy = false;
    m_symbolParams[index].cooldown.lastTime = 0;
    m_symbolParams[index].cooldown.actionCount = 0;
    
    m_symbolParams[index].lastDecisionTime = 0;
    m_symbolParams[index].lastDecision = ACTION_NONE;
    
    // Initialize cache
    m_symbolCache[index].symbol = symbol;
    m_symbolCache[index].lastMarketAnalysisTime = 0;
    m_symbolCache[index].lastConfidence = 0;
    m_symbolCache[index].lastDirection = DIRECTION_UNCLEAR;
    
    if(m_logger != NULL) {
        m_logger.StartContextWith(symbol, "SymbolAdded");
        m_logger.AddDoubleContext(symbol, "MagicNumber", dm_magicNumber, 0);
        m_logger.AddDoubleContext(symbol, "BuyConfidenceThreshold", params.buyConfidenceThreshold, 1);
        m_logger.AddDoubleContext(symbol, "SellConfidenceThreshold", params.sellConfidenceThreshold, 1);
        m_logger.AddDoubleContext(symbol, "AddPositionThreshold", params.addPositionThreshold, 1);
        m_logger.AddDoubleContext(symbol, "CooldownMinutes", params.cooldownMinutes, 0);
        m_logger.FlushContext(symbol, AUTHORIZE, STR_DECISION_ENGINE, 
                           StringFormat("Symbol added to DecisionEngine: %s Magic: %d", 
                                       symbol, dm_magicNumber), 
                           true);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if symbol exists                                           |
//+------------------------------------------------------------------+
bool DecisionEngine::HasSymbol(string symbol) const
{
    // Early exit: empty symbol
    if(symbol == "") return false;
    
    for(int i = 0; i < m_totalSymbols; i++) {
        if(m_symbolParams[i].symbol == symbol) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Remove symbol from monitoring                                    |
//+------------------------------------------------------------------+
bool DecisionEngine::RemoveSymbol(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index < 0) {
        if(m_logger != NULL) {
            m_logger.KeepNotes(symbol, WARN, STR_DECISION_ENGINE, 
                            "Symbol not found in DecisionEngine", false, false, 0.0);
        }
        return false;
    }
    
    // Clean up PositionManager
    if(m_symbolParams[index].positionManager != NULL) {
        delete m_symbolParams[index].positionManager;
        m_symbolParams[index].positionManager = NULL;
    }
    
    // Clean up indicator handles
    if(index < ArraySize(m_timeframeCache)) {
        if(m_timeframeCache[index].ema9Handle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[index].ema9Handle);
        }
        if(m_timeframeCache[index].ema21Handle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[index].ema21Handle);
        }
        if(m_timeframeCache[index].atrHandle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[index].atrHandle);
        }
        if(m_timeframeCache[index].adxHandle != INVALID_HANDLE) {
            IndicatorRelease(m_timeframeCache[index].adxHandle);
        }
    }
    
    // Remove from arrays
    for(int i = index; i < m_totalSymbols - 1; i++) {
        m_symbolParams[i] = m_symbolParams[i + 1];
        m_lastDecision[i] = m_lastDecision[i + 1];
        m_symbolCache[i] = m_symbolCache[i + 1];
        m_decisionCache[i] = m_decisionCache[i + 1];
        m_timeframeCache[i] = m_timeframeCache[i + 1];
        m_positionCache[i] = m_positionCache[i + 1];
        m_symbolDataCache[i] = m_symbolDataCache[i + 1];
    }
    
    m_totalSymbols--;
    
    if(m_logger != NULL) {
        m_logger.KeepNotes(symbol, OBSERVE, STR_DECISION_ENGINE, 
                        "Symbol removed from DecisionEngine", false, false, 0.0);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Find symbol index in array                                       |
//+------------------------------------------------------------------+
int DecisionEngine::FindSymbolIndex(string symbol) const
{
    // Early exit: empty symbol
    if(symbol == "") return -1;
    
    for(int i = 0; i < m_totalSymbols; i++) {
        if(m_symbolParams[i].symbol == symbol) {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Get PositionManager for symbol                                   |
//+------------------------------------------------------------------+
PositionManager* DecisionEngine::GetPositionManager(string symbol) const
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        return m_symbolParams[index].positionManager;
    }
    return NULL;
}

//+------------------------------------------------------------------+
//| Get DecisionParams for symbol                                    |
//+------------------------------------------------------------------+
DecisionParams DecisionEngine::GetSymbolDecisionParams(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        return m_symbolParams[index].params;  // Return value, not pointer
    }
    
    // Return empty params if not found
    DecisionParams empty;
    ZeroMemory(empty);
    return empty;
}

//+------------------------------------------------------------------+
//| Get SymbolParams for symbol                                      |
//+------------------------------------------------------------------+
SymbolParams DecisionEngine::GetSymbolParams(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        return m_symbolParams[index];  // Return value, not pointer
    }
    
    // Return empty SymbolParams if not found
    SymbolParams empty;
    ZeroMemory(empty);
    empty.symbol = "";  // Mark as empty
    return empty;
}

//+------------------------------------------------------------------+
//| Get symbol by index                                              |
//+------------------------------------------------------------------+
string DecisionEngine::GetSymbolByIndex(int index) const
{
    if(index >= 0 && index < m_totalSymbols) {
        return m_symbolParams[index].symbol;
    }
    return "";
}

//+------------------------------------------------------------------+
//| Main decision function                                           |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::MakeDecision(string symbol, double confidence, double marketDirectionScore)
{
    MARKET_DIRECTION direction = (MARKET_DIRECTION)marketDirectionScore;
    return MakeDecision(symbol, confidence, direction);
}

//+------------------------------------------------------------------+
//| Main decision function with optimized logging                    |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::MakeDecision(string symbol, double confidence, MARKET_DIRECTION direction)
{
    StartProfiling();
    
    // EARLY EXIT: Check if initialized
    if(!m_initialized) {
        StopProfiling();
        return ACTION_NONE;
    }
    
    // EARLY EXIT: Check if symbol exists
    if(!HasSymbol(symbol)) {
        StopProfiling();
        return ACTION_NONE;
    }
    
    // EARLY EXIT: Check basic confidence validity
    if(confidence < 0 || confidence > 100) {
        DebugLog(symbol, StringFormat("Invalid confidence: %.1f", confidence));
        StopProfiling();
        return ACTION_NONE;
    }
    
    // Update position cache
    UpdatePositionCache(symbol);
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== MAKE DECISION START for %s ===", symbol));
        DebugLog(symbol, StringFormat("Confidence: %.1f%%, Direction: %d", confidence, direction));
    }
    
    // Get symbol-specific parameters
    DecisionParams params = GetSymbolDecisionParams(symbol);
    if(params.buyConfidenceThreshold == 0) {
        DebugLog(symbol, "ERROR: Invalid parameters - buyConfidenceThreshold is 0");
        StopProfiling();
        return ACTION_NONE;
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Thresholds - Buy: %.1f%%, Sell: %.1f%%, Add: %.1f%%, Close: %.1f%%, CloseAll: %.1f%%",
                                      params.buyConfidenceThreshold, params.sellConfidenceThreshold,
                                      params.addPositionThreshold, params.closePositionThreshold,
                                      params.closeAllThreshold));
    }
    
    // Check cooldown
    bool isBuyAction = (direction == DIRECTION_BULLISH);
    if(IsInCooldown(symbol, isBuyAction)) {
        DebugLog(symbol, "Skipping - In cooldown period");
        StopProfiling();
        return ACTION_THINKING;
    } else if(m_debugMode) {
        DebugLog(symbol, "Not in cooldown - proceeding");
    }
    
    // Use cached position analysis if available
    PositionAnalysis positions;
    int cacheIndex = FindSymbolIndex(symbol);
    if(cacheIndex >= 0 && cacheIndex < ArraySize(m_positionCache) && 
       m_positionCache[cacheIndex].symbol == symbol &&
       TimeCurrent() - m_positionCache[cacheIndex].lastUpdate < (m_testingMode ? 0.5 : 2)) {
        // Use cached position counts
        positions.buyCount = m_positionCache[cacheIndex].buyCount;
        positions.sellCount = m_positionCache[cacheIndex].sellCount;
        positions.totalBuyVolume = m_positionCache[cacheIndex].totalBuyVolume;
        positions.totalSellVolume = m_positionCache[cacheIndex].totalSellVolume;
        
        // Determine state from cached counts
        if(positions.buyCount > 0 && positions.sellCount > 0) {
            positions.state = STATE_HAS_BOTH;
        } else if(positions.buyCount > 0) {
            positions.state = STATE_HAS_BUY;
        } else if(positions.sellCount > 0) {
            positions.state = STATE_HAS_SELL;
        } else {
            positions.state = STATE_NO_POSITION;
        }
        
        // Get dynamic data (not cached)
        PositionManager* pm = GetPositionManager(symbol);
        if(pm != NULL) {
            positions.averageBuyPrice = pm.GetAveragePrice(symbol, true);
            positions.averageSellPrice = pm.GetAveragePrice(symbol, false);
            positions.totalProfit = pm.GetTotalProfit(symbol);
        }
    } else {
        // Fall back to original calculation
        positions = AnalyzePositionsOriginal(symbol);
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Position state: %d (Buy: %d, Sell: %d)", positions.state, positions.buyCount, positions.sellCount));
    }
    
    // Get market analysis (NO CACHING in testing mode)
    MarketAnalysis market;
    if(ShouldUseCachedMarketAnalysis(symbol)) {
        market = GetCachedMarketAnalysis(symbol);
        if(m_debugMode) DebugLog(symbol, "Using cached market analysis");
    } else {
        market = AnalyzeMarket(symbol);
        UpdateMarketAnalysisCache(symbol, market);
        if(m_debugMode) DebugLog(symbol, "Created new market analysis");
    }
    
    // Check if market is ranging
    bool isRanging = IsMarketRanging(symbol);
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Market Ranging Check", isRanging);
    }
    
    DECISION_ACTION decision = ACTION_NONE;
    
    // Core decision logic with debug
    if(m_debugMode) DebugLog(symbol, "=== CORE DECISION LOGIC ===");
    
    if(positions.state == STATE_NO_POSITION) {
        if(m_debugMode) DebugLog(symbol, "State: NO POSITION - Calling DecideNoPosition");
        decision = DecideNoPosition(symbol, confidence, direction);
    } else {
        if(m_debugMode) DebugLog(symbol, StringFormat("State: HAS POSITION (state=%d) - Confidence=%.1f, isRanging=%s", 
                                      positions.state, confidence, isRanging ? "YES" : "NO"));
        
        if(isRanging) {
            if(m_debugMode) DebugLog(symbol, "Market is ranging - Calling DecideHolding");
            decision = DecideHolding(symbol, confidence, positions.state, direction);
        } else if(confidence < params.closeAllThreshold) {
            if(m_debugMode) DebugLog(symbol, StringFormat("Confidence (%.1f) < CloseAll (%.1f) - ACTION_CLOSE_ALL", 
                                         confidence, params.closeAllThreshold));
            decision = ACTION_CLOSE_ALL;
        } else if(confidence < params.closePositionThreshold) {
            if(m_debugMode) DebugLog(symbol, StringFormat("Confidence (%.1f) < ClosePos (%.1f) - Calling DecideFolding", 
                                         confidence, params.closePositionThreshold));
            decision = DecideFolding(symbol, confidence, positions.state);
        } else if(confidence >= params.addPositionThreshold) {
            if(m_debugMode) DebugLog(symbol, StringFormat("Confidence (%.1f) >= AddPos (%.1f) - Calling DecideAdding", 
                                         confidence, params.addPositionThreshold));
            decision = DecideAdding(symbol, confidence, positions.state, direction);
        } else {
            if(m_debugMode) DebugLog(symbol, StringFormat("Confidence (%.1f) between thresholds - Calling DecideHolding", confidence));
            decision = DecideHolding(symbol, confidence, positions.state, direction);
        }
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Preliminary decision: %s", DecisionToString(decision)));
    }
    
    // Evaluate trade conditions
    TradeConditions conditions = EvaluateTradeConditions(symbol, confidence, direction, decision);
    
    // Log condition results
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Confidence Threshold", conditions.confidenceThresholdMet);
        DebugLogConditionCheck(symbol, "Market Direction", conditions.marketDirectionAligned);
        DebugLogConditionCheck(symbol, "Position Limit", conditions.positionLimitNotExceeded);
        DebugLogConditionCheck(symbol, "Not in Cooldown", conditions.notInCooldown);
        DebugLogConditionCheck(symbol, "Within Trading Hours", conditions.withinTradingHours);
        DebugLogConditionCheck(symbol, "Risk Management OK", conditions.riskManagementOk);
        DebugLogConditionCheck(symbol, "OVERALL CONDITIONS", conditions.overallConditionsMet);
    }
    
    // Store decision with all context
    string reason = StringFormat("Confidence: %.1f, Direction: %d", confidence, direction);
    StoreDecision(symbol, decision, confidence, direction, conditions, positions, market, reason);
    
    // Validate decision
    if(!ValidateDecision(symbol, decision, confidence)) {
        if(m_debugMode) DebugLog(symbol, "Decision validation FAILED - Changing to HOLD");
        decision = ACTION_HOLD;
    } else if(m_debugMode) {
        DebugLog(symbol, "Decision validation PASSED");
    }
    
    m_totalDecisions++;
    
    // Only log when conditions change significantly or trade is about to happen
    if(decision != ACTION_NONE && decision != ACTION_HOLD && decision != ACTION_THINKING) {
        LogDecisionContext(symbol, decision, confidence, direction, positions, reason);
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== FINAL DECISION: %s ===", DecisionToString(decision)));
    }
    
    StopProfiling();
    return decision;
}

//+------------------------------------------------------------------+
//| Analyze positions using cached data                              |
//+------------------------------------------------------------------+
PositionAnalysis DecisionEngine::AnalyzePositions(string symbol) const
{
    PositionAnalysis analysis;
    ZeroMemory(analysis);
    
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_positionCache)) {
        // Use cached data if available and fresh (< 1 second in testing, 2 in production)
        int cacheTTL = m_testingMode ? 1 : 2;
        if(TimeCurrent() - m_positionCache[index].lastUpdate < cacheTTL && 
           m_positionCache[index].symbol == symbol) {
            analysis.buyCount = m_positionCache[index].buyCount;
            analysis.sellCount = m_positionCache[index].sellCount;
            analysis.totalBuyVolume = m_positionCache[index].totalBuyVolume;
            analysis.totalSellVolume = m_positionCache[index].totalSellVolume;
            
            // Determine state from cached counts
            if(analysis.buyCount > 0 && analysis.sellCount > 0) {
                analysis.state = STATE_HAS_BOTH;
            } else if(analysis.buyCount > 0) {
                analysis.state = STATE_HAS_BUY;
            } else if(analysis.sellCount > 0) {
                analysis.state = STATE_HAS_SELL;
            } else {
                analysis.state = STATE_NO_POSITION;
            }
            
            // Get dynamic data (not cached)
            PositionManager* pm = GetPositionManager(symbol);
            if(pm != NULL) {
                analysis.averageBuyPrice = pm.GetAveragePrice(symbol, true);
                analysis.averageSellPrice = pm.GetAveragePrice(symbol, false);
                analysis.totalProfit = pm.GetTotalProfit(symbol);
            }
            
            return analysis;
        }
    }
    
    // Fall back to original calculation if cache is stale
    return AnalyzePositionsOriginal(symbol);
}

//+------------------------------------------------------------------+
//| Original positions analysis (fallback)                           |
//+------------------------------------------------------------------+
PositionAnalysis DecisionEngine::AnalyzePositionsOriginal(string symbol) const
{
    PositionAnalysis analysis;
    ZeroMemory(analysis);
    
    PositionManager* pm = GetPositionManager(symbol);
    if(pm == NULL) {
        return analysis;
    }
    
    // Cache positions total once
    int positionsTotal = PositionsTotal();
    if(positionsTotal <= 0) {
        analysis.state = STATE_NO_POSITION;
        return analysis;
    }
    
    // Use backward iteration and cached total
    for(int i = positionsTotal - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == symbol) {
                ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                if(type == POSITION_TYPE_BUY) {
                    analysis.buyCount++;
                    analysis.totalBuyVolume += volume;
                } else if(type == POSITION_TYPE_SELL) {
                    analysis.sellCount++;
                    analysis.totalSellVolume += volume;
                }
            }
        }
    }
    
    analysis.averageBuyPrice = pm.GetAveragePrice(symbol, true);    
    analysis.averageSellPrice = pm.GetAveragePrice(symbol, false);  
    analysis.totalProfit = pm.GetTotalProfit(symbol);               
    
    // Determine state
    if(analysis.buyCount > 0 && analysis.sellCount > 0) {
        analysis.state = STATE_HAS_BOTH;
    } else if(analysis.buyCount > 0) {
        analysis.state = STATE_HAS_BUY;
    } else if(analysis.sellCount > 0) {
        analysis.state = STATE_HAS_SELL;
    } else {
        analysis.state = STATE_NO_POSITION;
    }
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Get total position volume for symbol                             |
//+------------------------------------------------------------------+
double DecisionEngine::GetTotalPositionVolume(string symbol, bool isBuy) const
{
    double totalVolume = 0;
    
    int positionsTotal = PositionsTotal(); // Cache once
    for(int i = positionsTotal - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == symbol) {
                ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                bool positionIsBuy = (type == POSITION_TYPE_BUY);
                
                if(positionIsBuy == isBuy) {
                    totalVolume += PositionGetDouble(POSITION_VOLUME);
                }
            }
        }
    }
    
    return totalVolume;
}

//+------------------------------------------------------------------+
//| Count positions for symbol                                       |
//+------------------------------------------------------------------+
int DecisionEngine::CountPositions(string symbol, bool isBuy) const
{
    PositionManager* pm = GetPositionManager(symbol);
    if(pm != NULL) {
        return pm.GetPositionCount(symbol, isBuy);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Check if has open position for symbol                            |
//+------------------------------------------------------------------+
bool DecisionEngine::HasOpenPosition(string symbol, bool isBuy)
{
    PositionManager* pm = GetPositionManager(symbol);
    if(pm != NULL) {
        return (pm.GetPositionCount(symbol, isBuy) > 0);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check max positions for symbol                                   |
//+------------------------------------------------------------------+
bool DecisionEngine::CheckMaxPositions(string symbol, bool isBuy)
{
    if(m_debugMode) DebugLog(symbol, StringFormat("=== CHECK MAX POSITIONS for %s ===", isBuy ? "BUY" : "SELL"));
    
    DecisionParams params = GetSymbolDecisionParams(symbol);
    
    // Check if params are valid
    if(params.buyConfidenceThreshold == 0) {
        if(m_debugMode) DebugLog(symbol, "ERROR: Invalid params");
        if(m_debugMode) DebugLog(symbol, "=== END CHECK MAX POSITIONS ===");
        return false;
    }
    
    int currentPositions = CountPositions(symbol, isBuy);
    bool canAddMore = (currentPositions < params.maxPositionsPerSymbol);
    
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Max Positions Check", 
                               canAddMore,
                               StringFormat("Current: %d, Max: %.0f", 
                                           currentPositions, params.maxPositionsPerSymbol));
    }
    
    if(m_debugMode) DebugLog(symbol, "=== END CHECK MAX POSITIONS ===");
    
    return canAddMore;
}

//+------------------------------------------------------------------+
//| Check cooldown for symbol                                        |
//+------------------------------------------------------------------+
bool DecisionEngine::IsInCooldown(string symbol, bool isBuy)
{
    if(m_debugMode) DebugLog(symbol, StringFormat("=== CHECK COOLDOWN for %s ===", isBuy ? "BUY" : "SELL"));
    
    // Get symbol params - returns SymbolParams, not bool
    // SymbolParams symbolParams = GetSymbolParams(symbol);
    
    // // Check if symbol was found
    // if(symbolParams.symbol != symbol) {
    //     if(m_debugMode) DebugLog(symbol, "ERROR: Symbol not found");
    //     if(m_debugMode) DebugLog(symbol, "=== END CHECK COOLDOWN ===");
    //     return false;
    // }
    
    // if(symbolParams.cooldown.symbol == symbol && symbolParams.cooldown.isBuy == isBuy) {
    //     datetime currentTime = TimeCurrent();
        
    //     // Get decision params - assign to variable
    //     DecisionParams params = GetSymbolDecisionParams(symbol);
        
    //     int cooldownMinutes = 5; // default value
    //     if(params.buyConfidenceThreshold != 0) {
    //         cooldownMinutes = params.cooldownMinutes;
    //     }
        
    //     int minutesSinceLast = (int)((currentTime - symbolParams.cooldown.lastTime) / 60);
    //     bool inCooldown = (minutesSinceLast < cooldownMinutes);
        
    //     if(m_debugMode) {
    //         DebugLogConditionCheck(symbol, "Cooldown Check", 
    //                                inCooldown,
    //                                StringFormat("Minutes since last: %d, Cooldown: %d minutes", 
    //                                            minutesSinceLast, cooldownMinutes));
    //     }
        
    //     if(m_debugMode) DebugLog(symbol, "=== END CHECK COOLDOWN ===");
    //     return inCooldown;
    // }
    
    if(m_debugMode) DebugLog(symbol, "No cooldown record found");
    if(m_debugMode) DebugLog(symbol, "=== END CHECK COOLDOWN ===");
    return false;
}

//+------------------------------------------------------------------+
//| Update cooldown for symbol                                       |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateCooldown(string symbol, bool isBuy)
{
    // Get symbol params by value
    SymbolParams symbolParams = GetSymbolParams(symbol);
    
    // Check if symbol was found
    if(symbolParams.symbol == symbol) {
        // Update the local copy
        symbolParams.cooldown.symbol = symbol;
        symbolParams.cooldown.isBuy = isBuy;
        symbolParams.cooldown.lastTime = TimeCurrent();
        symbolParams.cooldown.actionCount++;
        
        // Update the original in array
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolParams[i].symbol == symbol) {
                m_symbolParams[i].cooldown = symbolParams.cooldown;
                if(m_debugMode) {
                    DebugLog(symbol, StringFormat("Cooldown updated for %s (last time: %s)", 
                                                isBuy ? "BUY" : "SELL", 
                                                TimeToString(symbolParams.cooldown.lastTime)));
                }
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Decide when no position for symbol                               |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideNoPosition(string symbol, double confidence, MARKET_DIRECTION direction)
{
    if(m_debugMode) {
        DebugLog(symbol, "=== DECIDE NO POSITION ===");
        DebugLog(symbol, StringFormat("Confidence: %.1f, Direction: %d", confidence, direction));
    }
    
    DecisionParams params = GetSymbolDecisionParams(symbol);
    PositionManager* pm = GetPositionManager(symbol);
    
    // Check if params are valid (not NULL check)
    if(params.buyConfidenceThreshold == 0 || pm == NULL) {
        if(m_debugMode) {
            DebugLog(symbol, "ERROR: Invalid params or PositionManager");
            DebugLog(symbol, "=== END DECIDE NO POSITION ===");
        }
        return ACTION_THINKING;
    }
    
    bool canOpenBuy = false;
    bool canOpenSell = false;
    DECISION_ACTION decision = ACTION_THINKING;
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Checking BUY: Confidence (%.1f) >= BuyThreshold (%.1f) = %s, Direction (%d) == BULLISH/UNCLEAR = %s",
                                      confidence, params.buyConfidenceThreshold,
                                      confidence >= params.buyConfidenceThreshold ? "YES" : "NO",
                                      direction, 
                                      (direction == DIRECTION_BULLISH || direction == DIRECTION_UNCLEAR) ? "YES" : "NO"));
    }
    
    if(confidence >= params.buyConfidenceThreshold && 
       (direction == DIRECTION_BULLISH || direction == DIRECTION_UNCLEAR)) {
        
        canOpenBuy = pm.CanOpenNewPosition(symbol, true);
        if(m_debugMode) DebugLogConditionCheck(symbol, "CanOpenNewPosition (BUY)", canOpenBuy);
        if(canOpenBuy) {
            decision = ACTION_OPEN_BUY;
            if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_OPEN_BUY");
        } else {
            if(m_debugMode) DebugLog(symbol, "Cannot open BUY - PositionManager blocked");
        }
    } 
    else if(m_debugMode) {
        DebugLog(symbol, "BUY conditions not met - checking SELL");
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Checking SELL: Confidence (%.1f) >= SellThreshold (%.1f) = %s, Direction (%d) == BEARISH/UNCLEAR = %s",
                                      confidence, params.sellConfidenceThreshold,
                                      confidence >= params.sellConfidenceThreshold ? "YES" : "NO",
                                      direction,
                                      (direction == DIRECTION_BEARISH || direction == DIRECTION_UNCLEAR) ? "YES" : "NO"));
    }
    
    if(confidence >= params.sellConfidenceThreshold && 
       (direction == DIRECTION_BEARISH || direction == DIRECTION_UNCLEAR)) {
        
        canOpenSell = pm.CanOpenNewPosition(symbol, false);
        if(m_debugMode) DebugLogConditionCheck(symbol, "CanOpenNewPosition (SELL)", canOpenSell);
        if(canOpenSell) {
            decision = ACTION_OPEN_SELL;
            if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_OPEN_SELL");
        } else {
            if(m_debugMode) DebugLog(symbol, "Cannot open SELL - PositionManager blocked");
        }
    }
    else if(m_debugMode) {
        DebugLog(symbol, "SELL conditions not met");
    }
    
    if(decision == ACTION_THINKING && m_debugMode) {
        DebugLog(symbol, "No conditions met - returning ACTION_THINKING");
    }
    
    if(m_debugMode) DebugLog(symbol, "=== END DECIDE NO POSITION ===");
    
    return decision;
}

//+------------------------------------------------------------------+
//| Decide when adding to position for symbol                        |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideAdding(string symbol, double confidence, POSITION_STATE state, MARKET_DIRECTION direction)
{
    DecisionParams params = GetSymbolDecisionParams(symbol);
    PositionManager* pm = GetPositionManager(symbol);
    
    // Check if params are valid
    if(params.buyConfidenceThreshold == 0 || pm == NULL) {
        return ACTION_HOLD;
    }
    
    DECISION_ACTION decision = ACTION_HOLD;
    
    if(state == STATE_HAS_BUY) {
        if(!CheckMaxPositions(symbol, true)) {
            if(m_debugMode) DebugLog(symbol, "Max BUY positions reached");
        } else if(direction == DIRECTION_BULLISH && confidence >= params.addPositionThreshold) {
            if(pm.CanAddToPosition(symbol, true)) {
                decision = ACTION_ADD_BUY;
                if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_ADD_BUY");
            } else {
                if(m_debugMode) DebugLog(symbol, "Cannot add to BUY - PositionManager blocked");
            }
        }
    }
    else if(state == STATE_HAS_SELL) {
        if(!CheckMaxPositions(symbol, false)) {
            if(m_debugMode) DebugLog(symbol, "Max SELL positions reached");
        } else if(direction == DIRECTION_BEARISH && confidence >= params.addPositionThreshold) {
            if(pm.CanAddToPosition(symbol, false)) {
                decision = ACTION_ADD_SELL;
                if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_ADD_SELL");
            } else {
                if(m_debugMode) DebugLog(symbol, "Cannot add to SELL - PositionManager blocked");
            }
        }
    }
    
    return decision;
}

//+------------------------------------------------------------------+
//| Decide when holding for symbol                                   |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideHolding(string symbol, double confidence, POSITION_STATE state, MARKET_DIRECTION direction)
{
    DecisionParams params = GetSymbolDecisionParams(symbol);
    
    // Check if params are valid
    if(params.buyConfidenceThreshold == 0) {
        return ACTION_HOLD;
    }
    
    // Hold existing positions, don't open new ones
    if(state == STATE_NO_POSITION) {
        return ACTION_THINKING;
    }
    
    DECISION_ACTION decision = ACTION_HOLD;
    
    // Check if we should close opposing positions
    if(state == STATE_HAS_BUY && direction == DIRECTION_BEARISH && 
       confidence < params.closePositionThreshold) {
        decision = ACTION_CLOSE_BUY;
        if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_CLOSE_BUY (opposing direction)");
    }
    else if(state == STATE_HAS_SELL && direction == DIRECTION_BULLISH && 
            confidence < params.closePositionThreshold) {
        decision = ACTION_CLOSE_SELL;
        if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_CLOSE_SELL (opposing direction)");
    }
    
    return decision;
}

//+------------------------------------------------------------------+
//| Decide when folding for symbol                                   |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideFolding(string symbol, double confidence, POSITION_STATE state)
{
    DECISION_ACTION decision = ACTION_HOLD;
    
    if(state == STATE_HAS_BUY || state == STATE_HAS_BOTH) {
        decision = ACTION_CLOSE_BUY;
        if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_CLOSE_BUY (folding)");
    }
    else if(state == STATE_HAS_SELL || state == STATE_HAS_BOTH) {
        decision = ACTION_CLOSE_SELL;
        if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_CLOSE_SELL (folding)");
    }
    
    return decision;
}

//+------------------------------------------------------------------+
//| Decide when closing for symbol                                   |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideClosing(string symbol, double confidence, POSITION_STATE state)
{
    // This is called when confidence is critically low
    DECISION_ACTION decision = ACTION_THINKING;
    
    if(state != STATE_NO_POSITION) {
        decision = ACTION_CLOSE_ALL;
        if(m_debugMode) DebugLog(symbol, "DECISION: ACTION_CLOSE_ALL (critical confidence)");
    }
    
    return decision;
}

//+------------------------------------------------------------------+
//| Validate decision for symbol                                     |
//+------------------------------------------------------------------+
bool DecisionEngine::ValidateDecision(string symbol, DECISION_ACTION decision, double confidence)
{
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== VALIDATE DECISION: %s, Confidence: %.1f ===", 
                                     DecisionToString(decision), confidence));
    }
    
    DecisionParams params = GetSymbolDecisionParams(symbol);
    PositionManager* pm = GetPositionManager(symbol);
    
    // Check if params are valid
    if(params.buyConfidenceThreshold == 0 || pm == NULL) {
        if(m_debugMode) DebugLog(symbol, "ERROR: Invalid params or PositionManager");
        return false;
    }
    
    bool isValid = true;
    string reason = "";
    
    // Check confidence thresholds
    switch(decision) {
        case ACTION_OPEN_BUY:
        case ACTION_ADD_BUY:
            if(confidence < params.buyConfidenceThreshold) {
                isValid = false;
                reason = StringFormat("Confidence %.1f < BuyThreshold %.1f", 
                                     confidence, params.buyConfidenceThreshold);
            }
            break;
        case ACTION_OPEN_SELL:
        case ACTION_ADD_SELL:
            if(confidence < params.sellConfidenceThreshold) {
                isValid = false;
                reason = StringFormat("Confidence %.1f < SellThreshold %.1f", 
                                     confidence, params.sellConfidenceThreshold);
            }
            break;
        case ACTION_CLOSE_BUY:
        case ACTION_CLOSE_SELL:
            if(confidence > params.closePositionThreshold) {
                isValid = false;
                reason = StringFormat("Confidence %.1f > CloseThreshold %.1f", 
                                     confidence, params.closePositionThreshold);
            }
            break;
        case ACTION_CLOSE_ALL:
            if(confidence > params.closeAllThreshold) {
                isValid = false;
                reason = StringFormat("Confidence %.1f > CloseAllThreshold %.1f", 
                                     confidence, params.closeAllThreshold);
            }
            break;
    }
    
    if(!isValid && m_debugMode) {
        DebugLog(symbol, StringFormat("Validation FAILED: %s", reason));
    }
    
    // Check if PositionManager allows trading
    if(isValid && !pm.IsTradingAllowed()) {
        isValid = false;
        if(m_debugMode) DebugLog(symbol, "Validation FAILED: PositionManager not allowing trading");
    } else if(isValid && m_debugMode) {
        DebugLog(symbol, "PositionManager allows trading");
    }
    
    if(isValid && m_debugMode) {
        DebugLog(symbol, "Validation PASSED");
    }
    
    if(m_debugMode) DebugLog(symbol, "=== END VALIDATE DECISION ===");
    
    return isValid;
}

//+------------------------------------------------------------------+
//| Evaluate trade conditions                                        |
//+------------------------------------------------------------------+
TradeConditions DecisionEngine::EvaluateTradeConditions(string symbol, double confidence, 
                                                       MARKET_DIRECTION direction, DECISION_ACTION action)
{
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== EVALUATE TRADE CONDITIONS for action: %s ===", DecisionToString(action)));
    }
    
    TradeConditions conditions;
    
    DecisionParams params = GetSymbolDecisionParams(symbol);
    PositionAnalysis positions = AnalyzePositions(symbol);
    
    // 1. Check confidence thresholds
    switch(action) {
        case ACTION_OPEN_BUY:
        case ACTION_ADD_BUY:
            conditions.confidenceThresholdMet = (confidence >= params.buyConfidenceThreshold);
            if(m_debugMode) {
                DebugLogConditionCheck(symbol, "Confidence for BUY", 
                                       conditions.confidenceThresholdMet,
                                       StringFormat("%.1f >= %.1f", confidence, params.buyConfidenceThreshold));
            }
            break;
        case ACTION_OPEN_SELL:
        case ACTION_ADD_SELL:
            conditions.confidenceThresholdMet = (confidence >= params.sellConfidenceThreshold);
            if(m_debugMode) {
                DebugLogConditionCheck(symbol, "Confidence for SELL", 
                                       conditions.confidenceThresholdMet,
                                       StringFormat("%.1f >= %.1f", confidence, params.sellConfidenceThreshold));
            }
            break;
        case ACTION_CLOSE_BUY:
        case ACTION_CLOSE_SELL:
            conditions.confidenceThresholdMet = (confidence < params.closePositionThreshold);
            if(m_debugMode) {
                DebugLogConditionCheck(symbol, "Confidence for CLOSE", 
                                       conditions.confidenceThresholdMet,
                                       StringFormat("%.1f < %.1f", confidence, params.closePositionThreshold));
            }
            break;
        case ACTION_CLOSE_ALL:
            conditions.confidenceThresholdMet = (confidence < params.closeAllThreshold);
            if(m_debugMode) {
                DebugLogConditionCheck(symbol, "Confidence for CLOSE_ALL", 
                                       conditions.confidenceThresholdMet,
                                       StringFormat("%.1f < %.1f", confidence, params.closeAllThreshold));
            }
            break;
        default:
            conditions.confidenceThresholdMet = true;
            if(m_debugMode) DebugLog(symbol, "Confidence check: N/A for this action");
    }
    
    // 2. Check market direction alignment
    if(action == ACTION_OPEN_BUY || action == ACTION_ADD_BUY) {
        conditions.marketDirectionAligned = (direction == DIRECTION_BULLISH || direction == DIRECTION_UNCLEAR);
        if(m_debugMode) {
            DebugLogConditionCheck(symbol, "Direction for BUY", 
                                   conditions.marketDirectionAligned,
                                   StringFormat("Direction: %d, Expected: BULLISH(0) or UNCLEAR(3)", direction));
        }
    } else if(action == ACTION_OPEN_SELL || action == ACTION_ADD_SELL) {
        conditions.marketDirectionAligned = (direction == DIRECTION_BEARISH || direction == DIRECTION_UNCLEAR);
        if(m_debugMode) {
            DebugLogConditionCheck(symbol, "Direction for SELL", 
                                   conditions.marketDirectionAligned,
                                   StringFormat("Direction: %d, Expected: BEARISH(1) or UNCLEAR(3)", direction));
        }
    } else {
        conditions.marketDirectionAligned = true;
        if(m_debugMode) DebugLog(symbol, "Direction check: N/A for this action");
    }
    
    // 3. Check position limits
    bool isBuyAction = (action == ACTION_OPEN_BUY || action == ACTION_ADD_BUY);
    conditions.positionLimitNotExceeded = CheckMaxPositions(symbol, isBuyAction);
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Position Limit", 
                               conditions.positionLimitNotExceeded,
                               StringFormat("Action is %s", isBuyAction ? "BUY" : "SELL"));
    }
    
    // 4. Check cooldown
    conditions.notInCooldown = !IsInCooldown(symbol, isBuyAction);
    if(m_debugMode) DebugLogConditionCheck(symbol, "Not in Cooldown", conditions.notInCooldown);
    
    // 5. Check trading hours (always true for now, can be extended)
    conditions.withinTradingHours = IsWithinTradingHours(symbol);
    if(m_debugMode) DebugLogConditionCheck(symbol, "Within Trading Hours", conditions.withinTradingHours);
    
    // 6. Check risk management (placeholder for future implementation)
    conditions.riskManagementOk = (m_riskManager != NULL);
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Risk Manager", conditions.riskManagementOk,
                              m_riskManager != NULL ? "Available" : "NULL");
    }
    
    // 7. Overall conditions
    conditions.overallConditionsMet = 
        conditions.confidenceThresholdMet &&
        conditions.marketDirectionAligned &&
        conditions.positionLimitNotExceeded &&
        conditions.notInCooldown &&
        conditions.withinTradingHours &&
        conditions.riskManagementOk;
    
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "OVERALL CONDITIONS", conditions.overallConditionsMet);
        DebugLog(symbol, "=== END EVALUATE TRADE CONDITIONS ===");
    }
    
    return conditions;
}

//+------------------------------------------------------------------+
//| Store decision for tracking                                      |
//+------------------------------------------------------------------+
void DecisionEngine::StoreDecision(string symbol, DECISION_ACTION action, double confidence, 
                                  MARKET_DIRECTION direction, TradeConditions &conditions, 
                                  PositionAnalysis &positions, MarketAnalysis &market, string reason)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        m_lastDecision[index].symbol = symbol;
        m_lastDecision[index].action = action;
        m_lastDecision[index].confidence = confidence;
        m_lastDecision[index].direction = direction;
        m_lastDecision[index].timestamp = TimeCurrent();
        m_lastDecision[index].reason = reason;
        m_lastDecision[index].conditions = conditions;
        m_lastDecision[index].positions = positions;
        m_lastDecision[index].market = market;
    }
}

//+------------------------------------------------------------------+
//| Log decision context ONLY when necessary                         |
//+------------------------------------------------------------------+
void DecisionEngine::LogDecisionContext(string symbol, DECISION_ACTION decision, double confidence, 
                                       MARKET_DIRECTION direction, PositionAnalysis &positions, string reason)
{
    // Only log when trade is about to happen
    if(decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL || 
       decision == ACTION_CLOSE_ALL || decision == ACTION_ADD_BUY || decision == ACTION_ADD_SELL) {
        
        if(m_logger != NULL) {
            m_logger.StartContextWith(symbol, "DecisionMaking");
            m_logger.AddToContext(symbol, "Action", DecisionToString(decision), true);
            m_logger.AddDoubleContext(symbol, "Confidence", confidence, 1);
            m_logger.AddToContext(symbol, "Direction", EnumToString(direction));
            m_logger.AddDoubleContext(symbol, "BuyPositions", positions.buyCount, 0);
            m_logger.AddDoubleContext(symbol, "SellPositions", positions.sellCount, 0);
            m_logger.AddDoubleContext(symbol, "TotalPL", positions.totalProfit, 2);
            m_logger.FlushContext(symbol, AUTHORIZE, "DecisionEngine_MakeDecision", 
                               StringFormat("%s | %s", DecisionToString(decision), reason), 
                               true);
        }
    }
}

//+------------------------------------------------------------------+
//| Execute decision for specific symbol                             |
//+------------------------------------------------------------------+
void DecisionEngine::ExecuteDecision(string symbol, DECISION_ACTION decision, double confidence, double lots)
{
    StartProfiling();
    
    // EARLY EXIT: Check if decision is actionable
    if(decision == ACTION_NONE || decision == ACTION_HOLD || decision == ACTION_THINKING) {
        if(m_debugMode) {
            DebugLog(symbol, StringFormat("Skipping execution - Non-actionable decision: %s", DecisionToString(decision)));
        }
        StopProfiling();
        return;
    }
    
    PositionManager* pm = GetPositionManager(symbol);
    if(pm == NULL) {
        if(m_debugMode) DebugLog(symbol, "ERROR: PositionManager is NULL");
        StopProfiling();
        return;
    }
    
    string reason = StringFormat("Confidence: %.1f%%", confidence);
    bool executed = false;
    string actionResult = "";
    double profit = 0.0;
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== EXECUTE DECISION: %s with confidence %.1f%% ===", DecisionToString(decision), confidence));
    }
    
    // Get position count before execution
    PositionAnalysis positionsBefore = AnalyzePositions(symbol);
    int totalPositionsBefore = positionsBefore.buyCount + positionsBefore.sellCount;
    
    // Minimal logging - only log the execution
    if(m_logger != NULL) {
        m_logger.StartContextWith(symbol, "ExecuteDecision");
        m_logger.AddToContext(symbol, "Action", DecisionToString(decision), true);
    }
    
    switch(decision) {
        case ACTION_OPEN_BUY: {
            if(pm.OpenPosition(symbol, true, reason)) {
                actionResult = "BUY opened successfully";
                executed = true;
                UpdateCooldown(symbol, true);
                if(m_debugMode) DebugLog(symbol, "SUCCESS: BUY position opened");
            } else {
                actionResult = "Failed to open BUY position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not open BUY position");
            }
            break;
        }
            
        case ACTION_OPEN_SELL: {
            if(pm.OpenPosition(symbol, false, reason)) {
                actionResult = "SELL opened successfully";
                executed = true;
                UpdateCooldown(symbol, false);
                if(m_debugMode) DebugLog(symbol, "SUCCESS: SELL position opened");
            } else {
                actionResult = "Failed to open SELL position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not open SELL position");
            }
            break;
        }
            
        case ACTION_ADD_BUY: {
            if(pm.AddToPosition(symbol, true, reason)) {
                actionResult = "BUY added successfully";
                executed = true;
                UpdateCooldown(symbol, true);
                if(m_debugMode) DebugLog(symbol, "SUCCESS: Added to BUY position");
            } else {
                actionResult = "Failed to add to BUY position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not add to BUY position");
            }
            break;
        }
            
        case ACTION_ADD_SELL: {
            if(pm.AddToPosition(symbol, false, reason)) {
                actionResult = "SELL added successfully";
                executed = true;
                UpdateCooldown(symbol, false);
                if(m_debugMode) DebugLog(symbol, "SUCCESS: Added to SELL position");
            } else {
                actionResult = "Failed to add to SELL position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not add to SELL position");
            }
            break;
        }
            
        case ACTION_CLOSE_BUY: {
            // Cache positions total once
            int positionsTotal = PositionsTotal();
            for(int i = positionsTotal - 1; i >= 0; i--) {
                ulong ticket = PositionGetTicket(i);
                if(ticket <= 0) continue;
                
                if(PositionSelectByTicket(ticket)) {
                    if(PositionGetString(POSITION_SYMBOL) == symbol && 
                       PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                        double positionProfit = PositionGetDouble(POSITION_PROFIT);
                        if(pm.ClosePosition(ticket)) {
                            actionResult = "BUY closed successfully";
                            executed = true;
                            profit += positionProfit;
                            if(m_debugMode) DebugLog(symbol, "SUCCESS: BUY position closed");
                            break;
                        }
                    }
                }
            }
            if(!executed) {
                actionResult = "Failed to close BUY position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not close BUY position");
            }
            UpdateCooldown(symbol, true);
            break;
        }
            
        case ACTION_CLOSE_SELL: {
            int positionsTotal = PositionsTotal();
            for(int i = positionsTotal - 1; i >= 0; i--) {
                ulong ticket = PositionGetTicket(i);
                if(ticket <= 0) continue;
                
                if(PositionSelectByTicket(ticket)) {
                    if(PositionGetString(POSITION_SYMBOL) == symbol && 
                       PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                        double positionProfit = PositionGetDouble(POSITION_PROFIT);
                        if(pm.ClosePosition(ticket)) {
                            actionResult = "SELL closed successfully";
                            executed = true;
                            profit += positionProfit;
                            if(m_debugMode) DebugLog(symbol, "SUCCESS: SELL position closed");
                            break;
                        }
                    }
                }
            }
            if(!executed) {
                actionResult = "Failed to close SELL position";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not close SELL position");
            }
            UpdateCooldown(symbol, false);
            break;
        }
            
        case ACTION_CLOSE_ALL: {
            // Close all positions and calculate total profit
            double totalProfit = 0;
            int positionsTotal = PositionsTotal();
            for(int i = positionsTotal - 1; i >= 0; i--) {
                ulong ticket = PositionGetTicket(i);
                if(ticket <= 0) continue;
                
                if(PositionSelectByTicket(ticket)) {
                    if(PositionGetString(POSITION_SYMBOL) == symbol) {
                        double positionProfit = PositionGetDouble(POSITION_PROFIT);
                        if(pm.ClosePosition(ticket)) {
                            totalProfit += positionProfit;
                        }
                    }
                }
            }
            
            if(totalProfit != 0) {
                actionResult = "ALL positions closed successfully";
                executed = true;
                profit = totalProfit;
                UpdateCooldown(symbol, true);
                UpdateCooldown(symbol, false);
                if(m_debugMode) DebugLog(symbol, "SUCCESS: All positions closed");
            } else {
                actionResult = "Failed to close ALL positions";
                if(m_debugMode) DebugLog(symbol, "FAILED: Could not close all positions");
            }
            break;
        }
    }
    
    // Get position count after execution
    PositionAnalysis positionsAfter = AnalyzePositions(symbol);
    int totalPositionsAfter = positionsAfter.buyCount + positionsAfter.sellCount;
    
    // Log execution result
    LogExecutionResult(symbol, decision, executed, actionResult, confidence);
    
    // Log trade execution with enhanced details
    LogTradeExecution(symbol, decision, executed, confidence, profit, 
                     totalPositionsBefore, totalPositionsAfter, actionResult);
    
    // Invalidate decision cache for this symbol
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_decisionCache)) {
        m_decisionCache[index].timestamp = 0;
    }
    
    // Invalidate position cache
    if(index >= 0 && index < ArraySize(m_positionCache)) {
        m_positionCache[index].lastUpdate = 0;
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("=== EXECUTION COMPLETE: %s ===", executed ? "SUCCESS" : "FAILED"));
    }
    
    StopProfiling();
}

//+------------------------------------------------------------------+
//| Log execution result with enhanced details                       |
//+------------------------------------------------------------------+
void DecisionEngine::LogExecutionResult(string symbol, DECISION_ACTION decision, bool executed, 
                                       string actionResult, double confidence)
{
    if(m_logger != NULL) {
        // Add execution result to context
        m_logger.AddToContext(symbol, "ExecutionResult", executed ? "SUCCESS" : "FAILED");
        m_logger.AddToContext(symbol, "ResultDetails", actionResult);
        m_logger.AddDoubleContext(symbol, "ConfidenceAtExecution", confidence, 1);
        
        // Get position analysis after execution
        if(executed) {
            PositionAnalysis postAnalysis = AnalyzePositions(symbol);
            m_logger.AddDoubleContext(symbol, "PostExec_BuyPositions", postAnalysis.buyCount, 0);
            m_logger.AddDoubleContext(symbol, "PostExec_SellPositions", postAnalysis.sellCount, 0);
            m_logger.AddDoubleContext(symbol, "PostExec_TotalPL", postAnalysis.totalProfit, 2);
        }
        
        // Flush the context with appropriate log level
        m_logger.FlushContext(symbol, 
                             executed ? AUTHORIZE : ENFORCE, 
                             "DecisionEngine_Execute", 
                             StringFormat("%s | %s | Confidence: %.1f%%", 
                                         DecisionToString(decision), 
                                         executed ? "EXECUTED" : "FAILED",
                                         confidence), 
                             true);
    }
}

//+------------------------------------------------------------------+
//| Check emergency conditions for symbol                            |
//+------------------------------------------------------------------+
void DecisionEngine::CheckEmergencyConditions(string symbol)
{
    PositionManager* pm = GetPositionManager(symbol);
    if(pm == NULL) return;
    
    // Check for large drawdown using PositionManager
    double drawdown = pm.GetCurrentDrawdown();
    
    if(drawdown > 10) { // 10% drawdown
        if(pm.CloseAllPositions(symbol)) {
            if(m_logger != NULL) {
                m_logger.KeepNotes(symbol, ENFORCE, STR_DECISION_ENGINE, 
                               "All positions closed due to emergency drawdown", true, false, 0.0);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Should make decision for symbol?                                 |
//+------------------------------------------------------------------+
bool DecisionEngine::ShouldMakeDecision(string symbol)
{
    SymbolParams symbolParams = GetSymbolParams(symbol);
    
    // Check if symbol was found (compare with requested symbol)
    if(symbolParams.symbol != symbol) {
        return false;
    }
    
    // Make decision every 5 minutes
    datetime currentTime = TimeCurrent();
    bool shouldDecide = (currentTime - symbolParams.lastDecisionTime >= 300); // 5 minutes
    
    return shouldDecide;
}

//+------------------------------------------------------------------+
//| Print decision log for symbol                                    |
//+------------------------------------------------------------------+
void DecisionEngine::PrintDecisionLog(string symbol, DECISION_ACTION decision, double confidence, string reason)
{
    string actionStr = DecisionToString(decision);
    string log = StringFormat("[%s] Decision: %s | Confidence: %.1f%% | %s", 
                              symbol, actionStr, confidence, reason);
    
    // Use logger instead of Print
    if(m_logger != NULL) {
        m_logger.KeepNotes(symbol, OBSERVE, STR_DECISION_ENGINE, log, false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Get current decision for symbol                                  |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::GetCurrentDecision(string symbol)
{
    SymbolParams symbolParams = GetSymbolParams(symbol);
    if(symbolParams.symbol == symbol) {
        return symbolParams.lastDecision;
    }
    return ACTION_NONE;
}

//+------------------------------------------------------------------+
//| Print all symbols status                                         |
//+------------------------------------------------------------------+
void DecisionEngine::PrintAllSymbolsStatus()
{
    if(m_totalSymbols == 0) {
        if(m_logger != NULL) {
            m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                            "No symbols configured", false, false, 0.0);
        }
        return;
    }
    
    string status = "\n═══════════════════════════════════════════\n" +
                   "          DECISION ENGINE STATUS\n" +
                   "═══════════════════════════════════════════\n" +
                   StringFormat("Engine: %s | Total Symbols: %d\n", m_engineComment, m_totalSymbols) +
                   StringFormat("Total Decisions: %d | Accuracy: %.1f%%\n", 
                               m_totalDecisions, m_decisionAccuracy) +
                   StringFormat("Trades Executed: %d | Daily P&L: $%.2f\n",
                               m_performance.tradesExecuted, m_dailyStats.totalProfit) +
                   "═══════════════════════════════════════════\n";
    
    for(int i = 0; i < m_totalSymbols; i++) {
        PositionAnalysis analysis = AnalyzePositions(m_symbolParams[i].symbol);
        string lastDecisionStr = DecisionToString(m_symbolParams[i].lastDecision);
        
        status += StringFormat("[%s] B%d/S%d | P&L: $%.2f | Last: %s\n", 
                              m_symbolParams[i].symbol, 
                              analysis.buyCount, analysis.sellCount,
                              analysis.totalProfit,
                              lastDecisionStr);
    }
    
    status += "═══════════════════════════════════════════\n";
    
    // Log status using logger
    if(m_logger != NULL) {
        m_logger.StartContextWith(STR_SYSTEM, "EngineStatus");
        m_logger.AddDoubleContext(STR_SYSTEM, "TotalSymbols", m_totalSymbols, 0);
        m_logger.AddDoubleContext(STR_SYSTEM, "TotalDecisions", m_totalDecisions, 0);
        m_logger.AddDoubleContext(STR_SYSTEM, "DecisionAccuracy", m_decisionAccuracy, 1);
        m_logger.AddDoubleContext(STR_SYSTEM, "TradesExecuted", m_performance.tradesExecuted, 0);
        m_logger.AddDoubleContext(STR_SYSTEM, "DailyProfit", m_dailyStats.totalProfit, 2);
        
        for(int i = 0; i < m_totalSymbols; i++) {
            PositionAnalysis analysis = AnalyzePositions(m_symbolParams[i].symbol);
            string symbol = m_symbolParams[i].symbol;
            
            m_logger.AddToContext(STR_SYSTEM, StringFormat("%s_BuyPos", symbol), (string)analysis.buyCount);
            m_logger.AddToContext(STR_SYSTEM, StringFormat("%s_SellPos", symbol), (string)analysis.sellCount);
            m_logger.AddDoubleContext(STR_SYSTEM, StringFormat("%s_PnL", symbol), analysis.totalProfit, 2);
        }
        
        m_logger.FlushContext(STR_SYSTEM, AUDIT, "DecisionEngine_Status", 
                           "Decision Engine Status Report", false);
    }
    
    // Still print to console for visibility
    Print(status);
}

//+------------------------------------------------------------------+
//| Set symbol parameters                                            |
//+------------------------------------------------------------------+
void DecisionEngine::SetSymbolParameters(string symbol, DecisionParams &params)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        m_symbolParams[index].params = params;
        if(m_debugMode) DebugLog(symbol, "Symbol parameters updated");
    }
}

//+------------------------------------------------------------------+
//| Get symbol parameters                                            |
//+------------------------------------------------------------------+
DecisionParams DecisionEngine::GetSymbolParameters(string symbol) const
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0) {
        return m_symbolParams[index].params;
    }
    
    // Return empty params if symbol not found
    DecisionParams emptyParams;
    ZeroMemory(emptyParams);
    return emptyParams;
}

//+------------------------------------------------------------------+
//| Decide with position                                             |
//+------------------------------------------------------------------+
DECISION_ACTION DecisionEngine::DecideWithPosition(string symbol, double confidence, MARKET_DIRECTION direction, PositionAnalysis &positions)
{
    return ACTION_HOLD;
}

//+------------------------------------------------------------------+
//| Determine market direction for symbol (simple version)           |
//+------------------------------------------------------------------+
MARKET_DIRECTION DecisionEngine::DetermineMarketDirection(string symbol)
{
    // Use external function if available
    if(m_getMarketDirection != NULL) {
        MARKET_DIRECTION dir = m_getMarketDirection(symbol);
        if(m_debugMode) DebugLog(symbol, StringFormat("External market direction: %d", dir));
        return dir;
    }
    
    // Use cached EMA values
    double ema9 = GetCachedEMA9(symbol);
    double ema21 = GetCachedEMA21(symbol);
    
    if(ema9 == 0 || ema21 == 0) {
        if(m_debugMode) DebugLog(symbol, "Cannot determine direction - EMA values are 0");
        return DIRECTION_UNCLEAR;
    }
    
    MARKET_DIRECTION direction;
    
    if(ema9 > ema21) {
        direction = DIRECTION_BULLISH;
    } 
    else if(ema9 < ema21) {
        direction = DIRECTION_BEARISH;
    }
    else {
        direction = DIRECTION_RANGING;
    }
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Market direction calculated: %d (EMA9=%.5f, EMA21=%.5f)", 
                                     direction, ema9, ema21));
    }
    
    return direction;
}

//+------------------------------------------------------------------+
//| Convert decision enum to string                                  |
//+------------------------------------------------------------------+
string DecisionEngine::DecisionToString(DECISION_ACTION decision)
{
    // Static array for quick lookup
    static const string decisionStrings[] = {
        "NONE",      // ACTION_NONE
        "OPEN_BUY",  // ACTION_OPEN_BUY
        "OPEN_SELL", // ACTION_OPEN_SELL
        "ADD_BUY",   // ACTION_ADD_BUY
        "ADD_SELL",  // ACTION_ADD_SELL
        "CLOSE_BUY", // ACTION_CLOSE_BUY
        "CLOSE_SELL",// ACTION_CLOSE_SELL
        "CLOSE_ALL", // ACTION_CLOSE_ALL
        "HOLD",      // ACTION_HOLD
        "THINKING"   // ACTION_THINKING
    };
    
    int index = (int)decision;
    if(index >= 0 && index < ArraySize(decisionStrings)) {
        return decisionStrings[index];
    }
    return "UNKNOWN";
}

// ================= MISSING IMPLEMENTATIONS =================

//+------------------------------------------------------------------+
//| Set confidence function                                          |
//+------------------------------------------------------------------+
void DecisionEngine::SetConfidenceFunction(ConfidenceFunction func)
{
    m_getConfidence = func;
    if(m_debugMode) DebugLog(STR_SYSTEM, "Confidence function set");
}

//+------------------------------------------------------------------+
//| Set market direction function                                    |
//+------------------------------------------------------------------+
void DecisionEngine::SetMarketDirectionFunction(DirectionFunction func)
{
    m_getMarketDirection = func;
    if(m_debugMode) DebugLog(STR_SYSTEM, "Market direction function set");
}

//+------------------------------------------------------------------+
//| Set ranging function                                             |
//+------------------------------------------------------------------+
void DecisionEngine::SetRangingFunction(RangingFunction func)
{
    m_isMarketRanging = func;
    if(m_debugMode) DebugLog(STR_SYSTEM, "Ranging function set");
}

//+------------------------------------------------------------------+
//| Get position analysis for symbol                                 |
//+------------------------------------------------------------------+
PositionAnalysis DecisionEngine::GetPositionAnalysis(string symbol) const
{
    return AnalyzePositions(symbol);
}

//+------------------------------------------------------------------+
//| Analyze market for symbol                                        |
//+------------------------------------------------------------------+
MarketAnalysis DecisionEngine::AnalyzeMarket(string symbol)
{
    MarketAnalysis analysis;
    ZeroMemory(analysis);
    
    // Check cache first (2-second TTL in testing, 5 in production)
    int cacheTTL = m_testingMode ? 2 : 5;
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_symbolCache)) {
        if(TimeCurrent() - m_symbolCache[index].lastMarketAnalysisTime < cacheTTL) {
            return m_symbolCache[index].cachedMarketAnalysis;
        }
    }
    
    analysis.direction = DetermineMarketDirection(symbol);
    analysis.trendStrength = CalculateTrendStrength(symbol);
    analysis.isRanging = IsMarketRanging(symbol);
    analysis.bias = (analysis.direction == DIRECTION_BULLISH) ? "BULLISH" : 
                   (analysis.direction == DIRECTION_BEARISH) ? "BEARISH" : 
                   (analysis.direction == DIRECTION_RANGING) ? "RANGING" : "UNCLEAR";
    
    // Calculate volatility (ATR) using cached value
    double atr = GetCachedATR(symbol);
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    analysis.volatility = (price > 0) ? (atr / price * 100) : 0;
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Market analysis: Direction=%d, Ranging=%s, Volatility=%.2f%%", 
                                     analysis.direction, analysis.isRanging ? "YES" : "NO", analysis.volatility));
    }
    
    // Update cache (only if not in testing mode)
    if(!m_testingMode && index >= 0) {
        m_symbolCache[index].cachedMarketAnalysis = analysis;
        m_symbolCache[index].lastMarketAnalysisTime = TimeCurrent();
    }
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Get market analysis for symbol                                   |
//+------------------------------------------------------------------+
MarketAnalysis DecisionEngine::GetMarketAnalysis(string symbol) const
{
    MarketAnalysis analysis;
    ZeroMemory(analysis);
    
    analysis.direction = DIRECTION_UNCLEAR;
    analysis.trendStrength = 50.0;
    analysis.isRanging = false;
    analysis.volatility = 0.0;
    analysis.bias = "UNKNOWN";
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Get decision accuracy                                            |
//+------------------------------------------------------------------+
double DecisionEngine::GetDecisionAccuracy() const
{
    return m_decisionAccuracy;
}

//+------------------------------------------------------------------+
//| Check if decision is valid                                       |
//+------------------------------------------------------------------+
bool DecisionEngine::IsDecisionValid(string symbol, DECISION_ACTION decision, double confidence)
{
    return ValidateDecision(symbol, decision, confidence);
}

//+------------------------------------------------------------------+
//| Calculate position size for symbol                               |
//+------------------------------------------------------------------+
double DecisionEngine::CalculatePositionSize(string symbol, double confidence)
{
    DecisionParams params = GetSymbolDecisionParams(symbol);
    if(params.buyConfidenceThreshold == 0) return 0.01;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (params.riskPercent / 100.0);
    
    // Calculate position size based on confidence
    double confidenceMultiplier = confidence / 100.0;
    double baseSize = 0.01 * (accountBalance / 1000.0);
    
    double positionSize = NormalizeDouble(baseSize * confidenceMultiplier, 2);
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Position size calculated: %.2f (Confidence: %.1f%%, Balance: %.2f)", 
                                     positionSize, confidence, accountBalance));
    }
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Calculate add position size                                      |
//+------------------------------------------------------------------+
double DecisionEngine::CalculateAddPositionSize(string symbol, double existingVolume, double confidence)
{
    // Add half of original position size
    double newSize = CalculatePositionSize(symbol, confidence);
    double addSize = MathMin(newSize * 0.5, existingVolume * 0.5); // Max 50% of existing
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Add position size: %.2f (Existing: %.2f)", addSize, existingVolume));
    }
    
    return addSize;
}

//+------------------------------------------------------------------+
//| Is market ranging                                                |
//+------------------------------------------------------------------+
bool DecisionEngine::IsMarketRanging(string symbol)
{
    // // Use external function if available
    // if(m_isMarketRanging != NULL) {
    //     bool ranging = m_isMarketRanging(symbol);
    //     if(m_debugMode) DebugLog(symbol, StringFormat("External ranging check: %s", ranging ? "YES" : "NO"));
    //     return ranging;
    // }
    
    // // Technical analysis for ranging market using cached ATR
    // double atr = GetCachedATR(symbol);
    // double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    // double volatility = (price > 0) ? (atr / price * 100) : 0;
    
    // bool isRanging = (volatility < 0.5); // Low volatility = ranging
    
    // if(m_debugMode) {
    //     DebugLog(symbol, StringFormat("Ranging check: %s (Volatility: %.2f%%, Threshold: 0.5%%)", 
    //                                  isRanging ? "YES" : "NO", volatility));
    // }
    
    // return isRanging;

    // TEMPORARY OVERRIDE: Always return false (market is NOT ranging)
    if(m_debugMode) {
        DebugLog(symbol, "OVERRIDE: Market ranging check disabled - always returning FALSE");
    }
    
    return false; // Market is NEVER ranging
}

//+------------------------------------------------------------------+
//| Calculate trend strength with handle caching                     |
//+------------------------------------------------------------------+
double DecisionEngine::CalculateTrendStrength(string symbol)
{
    int index = FindSymbolIndex(symbol);
    if(index >= 0 && index < ArraySize(m_timeframeCache)) {
        // Ensure cache is updated
        UpdateTimeframeCache(symbol);
        
        // Use cached ADX handle
        int adxHandle = m_timeframeCache[index].adxHandle;
        if(adxHandle == INVALID_HANDLE) {
            return 50.0;
        }
        
        // Get ADX value using cached handle
        double adxBuffer[1];
        if(CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) < 1) {
            return 50.0;
        }
        
        double adxValue = adxBuffer[0];
        
        // Normalize ADX to 0-100
        double trendStrength;
        if(adxValue > 60.0) trendStrength = 100.0;
        else if(adxValue < 10.0) trendStrength = 0.0;
        else trendStrength = ((adxValue - 10.0) / 50.0) * 100.0;
        
        if(m_debugMode) {
            DebugLog(symbol, StringFormat("Trend strength: %.1f (ADX: %.1f)", trendStrength, adxValue));
        }
        
        return trendStrength;
    }
    
    return 50.0;
}

//+------------------------------------------------------------------+
//| Check time since last trade                                      |
//+------------------------------------------------------------------+
bool DecisionEngine::CheckTimeSinceLastTrade(string symbol)
{
    SymbolParams symbolParams = GetSymbolParams(symbol);
    if(symbolParams.symbol != symbol) return true;
    
    datetime currentTime = TimeCurrent();
    datetime lastTime = symbolParams.cooldown.lastTime;
    
    // Minimum 1 minute between trades
    bool enoughTimePassed = ((currentTime - lastTime) >= 60);
    
    if(m_debugMode) {
        DebugLogConditionCheck(symbol, "Time since last trade", enoughTimePassed,
                              StringFormat("Current: %s, Last: %s", 
                                          TimeToString(currentTime), 
                                          TimeToString(lastTime)));
    }
    
    return enoughTimePassed;
}

//+------------------------------------------------------------------+
//| Check confidence thresholds                                      |
//+------------------------------------------------------------------+
bool DecisionEngine::CheckConfidenceThresholds(string symbol, double confidence, bool isBuy)
{
    DecisionParams params = GetSymbolDecisionParams(symbol);
    if(params.buyConfidenceThreshold == 0) return false;
    
    bool meetsThreshold;
    
    if(isBuy) {
        meetsThreshold = (confidence >= params.buyConfidenceThreshold);
        if(m_debugMode) {
            DebugLogConditionCheck(symbol, "Buy Confidence Threshold", 
                                   meetsThreshold,
                                   StringFormat("%.1f >= %.1f", confidence, params.buyConfidenceThreshold));
        }
    } else {
        meetsThreshold = (confidence >= params.sellConfidenceThreshold);
        if(m_debugMode) {
            DebugLogConditionCheck(symbol, "Sell Confidence Threshold", 
                                   meetsThreshold,
                                   StringFormat("%.1f >= %.1f", confidence, params.sellConfidenceThreshold));
        }
    }
    
    return meetsThreshold;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool DecisionEngine::IsWithinTradingHours(string symbol)
{
    // Always true for now
    return true;
}

//+------------------------------------------------------------------+
//| Update decision statistics                                       |
//+------------------------------------------------------------------+
void DecisionEngine::UpdateDecisionStatistics(bool wasSuccessful)
{
    m_correctDecisions += (wasSuccessful ? 1 : 0);
    
    if(m_totalDecisions > 0) {
        m_decisionAccuracy = (double)m_correctDecisions / m_totalDecisions * 100.0;
    }
    
    if(m_debugMode) {
        DebugLog(STR_SYSTEM, StringFormat("Decision statistics updated - Total: %d, Correct: %d, Accuracy: %.1f%%", 
                                       m_totalDecisions, m_correctDecisions, m_decisionAccuracy));
    }
}

//+------------------------------------------------------------------+
//| Get last trade time for symbol                                   |
//+------------------------------------------------------------------+
datetime DecisionEngine::GetLastTradeTime(string symbol, bool isBuy)
{
    SymbolParams symbolParams = GetSymbolParams(symbol);
    if(symbolParams.symbol != symbol) return 0;
    
    return symbolParams.cooldown.lastTime;
}

//+------------------------------------------------------------------+
//| Default confidence implementation                                |
//+------------------------------------------------------------------+
double DecisionEngine::DefaultGetConfidence(string symbol)
{
    // Simple confidence calculation based on trend using cached values
    double ema9 = GetCachedEMA9(symbol);
    double ema21 = GetCachedEMA21(symbol);
    double current = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    if(ema9 == 0 || ema21 == 0) return 50.0;
    
    double distance = MathAbs(ema9 - ema21) / current * 100;
    double baseConfidence = 50.0;
    
    // Stronger trend = higher confidence
    if(distance > 0.5) baseConfidence += 30.0;
    else if(distance > 0.2) baseConfidence += 15.0;
    
    double confidence = MathMin(baseConfidence, 95.0); // Cap at 95%
    
    if(m_debugMode) {
        DebugLog(symbol, StringFormat("Default confidence: %.1f%% (Distance: %.2f%%)", confidence, distance));
    }
    
    return confidence;
}

//+------------------------------------------------------------------+
//| Default market direction implementation                          |
//+------------------------------------------------------------------+
MARKET_DIRECTION DecisionEngine::DefaultGetMarketDirection(string symbol)
{
    return DetermineMarketDirection(symbol);
}

//+------------------------------------------------------------------+
//| Default market ranging implementation                            |
//+------------------------------------------------------------------+
bool DecisionEngine::DefaultIsMarketRanging(string symbol)
{
    return IsMarketRanging(symbol);
}

//+------------------------------------------------------------------+
//| Reset statistics                                                 |
//+------------------------------------------------------------------+
void DecisionEngine::ResetStatistics()
{
    m_totalDecisions = 0;
    m_correctDecisions = 0;
    m_decisionAccuracy = 0.0;
    
    // Reset trade logs
    for(int i = 0; i < ArraySize(m_tradeLogs); i++) {
        m_tradeLogs[i].timestamp = 0;
    }
    m_tradeLogIndex = 0;
    
    if(m_logger != NULL) {
        m_logger.KeepNotes(STR_SYSTEM, OBSERVE, STR_DECISION_ENGINE, 
                        "Decision statistics reset", false, false, 0.0);
    }
    Print("Decision statistics reset");
}

//+------------------------------------------------------------------+
//| Add symbol with auto-initialization                              |
//+------------------------------------------------------------------+
bool DecisionEngine::AddSymbolAuto(string symbol, DecisionParams &params)
{
    // Auto-initialize if not already done
    if(!m_initialized)
    {
        Print("DecisionEngine::AddSymbolAuto - Error: Not initialized");
        return false;
    }
    
    // Check if symbol already exists
    if(HasSymbol(symbol))
    {
        // Update existing symbol parameters
        SetSymbolParameters(symbol, params);
        if(m_debugMode) DebugLog(symbol, "Symbol parameters updated");
        return true;
    }
    
    // Add new symbol
    if(AddSymbol(symbol, params))
    {
        if(m_debugMode) DebugLog(symbol, "Symbol added successfully");
        return true;
    }
    
    if(m_debugMode) DebugLog(symbol, "Failed to add symbol");
    return false;
}

//+------------------------------------------------------------------+
//| Set timer interval for periodic checks                           |
//+------------------------------------------------------------------+
void DecisionEngine::SetTimerInterval(int seconds)
{
    if(seconds < 10) 
    {
        seconds = 10; // Minimum 10 seconds
    }
    
    if(seconds > 3600) 
    {
        seconds = 3600; // Maximum 1 hour
    }
    
    m_timerIntervalSeconds = seconds;
    if(m_debugMode) DebugLog(STR_SYSTEM, StringFormat("Timer interval set to %d seconds", seconds));
}

//+------------------------------------------------------------------+
//| Get quick status summary                                         |
//+------------------------------------------------------------------+
string DecisionEngine::GetQuickStatus()
{
    if(!m_initialized) 
    {
        return "Decision Engine: NOT INITIALIZED";
    }
    
    // Count active positions
    int totalPositions = 0;
    for(int i = 0; i < m_totalSymbols; i++)
    {
        PositionAnalysis analysis = AnalyzePositions(m_symbolParams[i].symbol);
        totalPositions += (analysis.buyCount + analysis.sellCount);
    }
    
    string status = StringFormat(
        "╔══════════════════════════════════════════╗\n" +
        "║          DECISION ENGINE STATUS          ║\n" +
        "╠══════════════════════════════════════════╣\n" +
        "║ Engine: %-32s ║\n" +
        "║ Symbols: %-2d  |  Positions: %-3d        ║\n" +
        "║ Decisions: %-5d  |  Accuracy: %-6.1f%%   ║\n" +
        "║ Timer Interval: %-4d seconds            ║\n" +
        "║ Processing: %-5.2f ms (avg)            ║\n" +
        "║ Caching: %-8s                     ║\n" +
        "║ Daily Trades: %-3d | P&L: $%-8.2f    ║\n" +
        "╚══════════════════════════════════════════╝",
        m_engineComment,
        m_totalSymbols,
        totalPositions,
        m_totalDecisions,
        m_decisionAccuracy,
        m_timerIntervalSeconds,
        m_performance.avgProcessingTimeMs,
        m_skipUnchangedConditions ? "ENABLED" : "DISABLED",
        m_dailyStats.totalTrades,
        m_dailyStats.totalProfit
    );
    
    return status;
}

//+------------------------------------------------------------------+
//| Quick initialization with defaults                               |
//+------------------------------------------------------------------+
bool DecisionEngine::QuickInitialize(string symbol, 
                                    double buyThreshold = 25.0, 
                                    double sellThreshold = 25.0,
                                    double riskPercent = 1.0,
                                    int cooldownMinutes = 5)
{
    // Setup default parameters with thresholds set to 25
    DecisionParams params;
    params.buyConfidenceThreshold = 25.0;        // Changed to 25
    params.sellConfidenceThreshold = 25.0;       // Changed to 25
    params.addPositionThreshold = 35.0;          // buyThreshold(25) + 10 = 35
    params.closePositionThreshold = 15.0;        // buyThreshold(25) - 10 = 15
    params.closeAllThreshold = 15.0;             // buyThreshold(25) - 10 = 15
    params.cooldownMinutes = cooldownMinutes;
    params.maxPositionsPerSymbol = 3;
    params.riskPercent = riskPercent;
    
    // Can't initialize without dependencies
    if(!m_initialized) {
        Print("DecisionEngine::QuickInitialize - Error: Not initialized.");
        return false;
    }
    
    if(m_debugMode) DebugLog(symbol, "QuickInitialize called");
    
    // Add symbol
    return AddSymbolAuto(symbol, params);
}

//+------------------------------------------------------------------+
//| Static default confidence implementation                        |
//+------------------------------------------------------------------+
double DecisionEngine::StaticDefaultGetConfidence(string symbol)
{
    // Simple confidence calculation based on trend
    double ema9 = iMA(symbol, PERIOD_H1, 9, 0, MODE_EMA, PRICE_CLOSE);
    double ema21 = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
    double current = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    if(ema9 == 0 || ema21 == 0) return 50.0;
    
    double distance = MathAbs(ema9 - ema21) / current * 100;
    double baseConfidence = 50.0;
    
    // Stronger trend = higher confidence
    if(distance > 0.5) baseConfidence += 30.0;
    else if(distance > 0.2) baseConfidence += 15.0;
    
    double confidence = MathMin(baseConfidence, 95.0);
    
    return confidence;
}

//+------------------------------------------------------------------+
//| Static default market direction implementation                   |
//+------------------------------------------------------------------+
MARKET_DIRECTION DecisionEngine::StaticDefaultGetMarketDirection(string symbol)
{
    // Simple moving average crossover
    double ema9 = iMA(symbol, PERIOD_H1, 9, 0, MODE_EMA, PRICE_CLOSE);
    double ema21 = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
    
    if(ema9 == 0 || ema21 == 0) {
        return DIRECTION_UNCLEAR;
    }
    
    if(ema9 > ema21) {
        return DIRECTION_BULLISH;
    } 
    else if(ema9 < ema21) {
        return DIRECTION_BEARISH;
    }
    else {
        return DIRECTION_RANGING;
    }
}

//+------------------------------------------------------------------+
//| Static default market ranging implementation                     |
//+------------------------------------------------------------------+
bool DecisionEngine::StaticDefaultIsMarketRanging(string symbol)
{
    // Technical analysis for ranging market
    double atr = iATR(symbol, PERIOD_H1, 14);
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    double volatility = (price > 0) ? (atr / price * 100) : 0;
    
    return (volatility < 0.5);
}

//+------------------------------------------------------------------+
//| Instance default confidence                                      |
//+------------------------------------------------------------------+
double DecisionEngine::InstanceDefaultGetConfidence(string symbol)
{
    return DefaultGetConfidence(symbol);
}

//+------------------------------------------------------------------+
//| Instance default market direction                                |
//+------------------------------------------------------------------+
MARKET_DIRECTION DecisionEngine::InstanceDefaultGetMarketDirection(string symbol)
{
    return DefaultGetMarketDirection(symbol);
}

//+------------------------------------------------------------------+
//| Instance default market ranging                                  |
//+------------------------------------------------------------------+
bool DecisionEngine::InstanceDefaultIsMarketRanging(string symbol)
{
    return DefaultIsMarketRanging(symbol);
}

//+------------------------------------------------------------------+
//| Build decision explanation                                       |
//+------------------------------------------------------------------+
string DecisionEngine::BuildDecisionExplanation(TradeDecision &decision)
{
    string explanation = "";
    
    // Essential information only
    explanation += "=== DECISION ENGINE ===\n";
    explanation += StringFormat("Decision: %s\n", DecisionToString(decision.action));
    explanation += StringFormat("Confidence: %.1f%%\n", decision.confidence);
    explanation += StringFormat("Market: %s\n", decision.market.bias);
    explanation += StringFormat("Positions: B%d/S%d\n", decision.positions.buyCount, decision.positions.sellCount);
    explanation += StringFormat("P&L: $%.2f\n", decision.positions.totalProfit);
    explanation += StringFormat("Conditions: %s", decision.conditions.overallConditionsMet ? "MET ✓" : "BLOCKED ✗");
    
    return explanation;
}

//+------------------------------------------------------------------+
//| Convert conditions to string                                     |
//+------------------------------------------------------------------+
string DecisionEngine::ConditionsToString(TradeConditions &conditions)
{
    string result = "CONDITIONS:\n";
    result += StringFormat("Confidence: %s\n", conditions.confidenceThresholdMet ? "✓" : "✗");
    result += StringFormat("Direction: %s\n", conditions.marketDirectionAligned ? "✓" : "✗");
    result += StringFormat("Positions: %s\n", conditions.positionLimitNotExceeded ? "✓" : "✗");
    result += StringFormat("Cooldown: %s\n", conditions.notInCooldown ? "✓" : "✗");
    result += StringFormat("Overall: %s", conditions.overallConditionsMet ? "✓ READY" : "✗ BLOCKED");
    
    return result;
}

// ================= EXTERNAL INTERFACE =================
DECISION_ACTION Decision_Make(DecisionEngine &d_engine, string symbol, double confidence, double marketDirectionScore)
{
    return d_engine.MakeDecision(symbol, confidence, marketDirectionScore);
}

bool Decision_IsValid(DecisionEngine &e_engine, string symbol, DECISION_ACTION decision, double confidence)
{
    return e_engine.IsDecisionValid(symbol, decision, confidence);
}

// ================= END OF FILE =================