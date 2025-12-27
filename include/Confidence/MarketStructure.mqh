// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++      MARKET STRUCTURE ENGINE     ++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict
#property version   "1.00"

/*
==============================================================
HIERARCHICAL MARKET STRUCTURE DECISION SYSTEM
==============================================================
Core Principles:
1. Primitive Strength Hierarchy
2. Weighted Confidence Scoring (Always totals 100%)
3. Strategy Selection Based on Scores
==============================================================
*/

// ================= INCLUDES =================
#include <Arrays/List.mqh>
#include "../utils/Utils.mqh"
#include "../utils/ResourceManager.mqh"               // Logging System

#include "..\marketStructure\OrderBlock.mqh"    // Order Blocks

// ================= PRIMITIVE STRENGTH RANKING =================
// 1 = Strongest, 7 = Weakest
enum PRIMITIVE_RANK {
    RANK_ORDERFLOW_CLUSTER = 1,   // Volume accumulation
    RANK_SSDD_ZONE = 2,           // Supply/Demand imbalance
    RANK_ORDER_BLOCK = 3,         // Institutional order accumulation
    RANK_BOS = 4,                 // Break of Structure
    RANK_MSS = 5,                 // Market Structure Shift
    RANK_LIQUIDITY_GRAB = 6,      // Stop hunts
    RANK_CHOCH = 7                // Momentum shift
};

// ================= BASE WEIGHTS (Total = 100%) =================
enum PRIMITIVE_WEIGHT {
    WEIGHT_ORDERFLOW   = 25,    // Institutional volume footprint
    WEIGHT_SSDD        = 20,    // Supply/Demand imbalance
    WEIGHT_ORDERBLOCK  = 15,    // Institutional order accumulation
    WEIGHT_BOS         = 15,    // Clean structure break
    WEIGHT_MSS         = 10,    // Swing point break
    WEIGHT_LIQUIDITY   = 10,    // Stop hunt risk assessment
    WEIGHT_CHOCH       = 5      // Momentum shift confirmation
};

// ================= ENUMS =================
enum MARKET_STRUCTURE_TYPE {
    MS_TREND_UP,
    MS_TREND_DOWN,
    MS_RANGE,
    MS_BREAKOUT,
    MS_REVERSAL,
    MS_CHOPPY
};

enum STRUCTURE_CONFIRMATION {
    CONFIRMATION_NONE,
    CONFIRMATION_WEAK,
    CONFIRMATION_MODERATE,
    CONFIRMATION_STRONG,
    CONFIRMATION_VERY_STRONG
};

enum ZONE_TYPE {
    ZONE_SUPPLY,
    ZONE_DEMAND,
    ZONE_ORDER_BLOCK,
    ZONE_BREAKER,
    ZONE_FAIR_VALUE_GAP,
    ZONE_LIQUIDITY_POOL
};

enum STRUCTURE_SIGNAL {
    SIGNAL_NONE,
    SIGNAL_BOS_BUY,
    SIGNAL_BOS_SELL,
    SIGNAL_CHOCH_BUY,
    SIGNAL_CHOCH_SELL,
    SIGNAL_MS_SHIFT_BUY,
    SIGNAL_MS_SHIFT_SELL,
    SIGNAL_LIQUIDITY_GRAB_BUY,
    SIGNAL_LIQUIDITY_GRAB_SELL
};

enum MARKET_REGIME {
    REGIME_TRENDING_BULLISH,
    REGIME_TRENDING_BEARISH,
    REGIME_RANGING,
    REGIME_BREAKOUT,
    REGIME_HIGH_VOLATILITY,
    REGIME_LOW_VOLATILITY
};

// ================= STRUCTURES =================
struct PrimitiveScore {
    string primitiveName;
    double rawScore;           // 0-100 from primitive module
    double normalizedScore;    // Normalized 0-100
    double weight;            // Base weight %
    double adjustedWeight;    // Market-adjusted weight %
    double weightedScore;     // (normalizedScore * adjustedWeight)
    int rank;                 // Strength ranking
    bool isAvailable;         // Is this primitive module loaded?
    
    // Constructor for easy initialization
    PrimitiveScore() : 
        primitiveName(""),
        rawScore(0.0),
        normalizedScore(0.0),
        weight(0.0),
        adjustedWeight(0.0),
        weightedScore(0.0),
        rank(0),
        isAvailable(false)
    {}
};

struct MarketStructureScore {
    PrimitiveScore scores[7];    // All 7 primitives
    double totalConfidence;      // Overall confidence 0-100
    MARKET_REGIME currentRegime;
    datetime analysisTime;
    string bias;                 // "BULLISH", "BEARISH", "NEUTRAL"
    STRUCTURE_SIGNAL signal;
    bool isStrategyValid;
    string recommendedStrategy;
    
    // Constructor for easy initialization
    MarketStructureScore() : 
        totalConfidence(0.0),
        currentRegime(REGIME_RANGING),
        analysisTime(0),
        bias("NEUTRAL"),
        signal(SIGNAL_NONE),
        isStrategyValid(false),
        recommendedStrategy("")
    {
        // Initialize scores array
        for(int i = 0; i < 7; i++) {
            scores[i] = PrimitiveScore();
        }
    }
};

struct StrategyRequirements {
    string strategyName;
    double minOverallScore;
    double minOrderFlow;
    double minSSDD;
    double minOrderBlock;
    double minBOS;
    double minMSS;
    double maxLiquidityRisk;
    bool requireConfluence;
};

// ================= CLASS DEFINITION =================
class MarketStructureEngine
{
private:
    // Core components
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Configuration
    double m_baseWeights[7];
    bool m_primitiveAvailability[7];
    
    // State management
    MarketStructureScore m_currentScore;
    MARKET_REGIME m_currentRegime;
    
    // Performance tracking
    int m_totalAnalyses;
    double m_accuracyRate;
    
    // Dynamic weight adjustment
    double m_trendingMultiplier;
    double m_rangingMultiplier;
    double m_breakoutMultiplier;
    double m_highVolMultiplier;
    
    // Logging and display systems
    ResourceManager *m_logger;
    COrderBlock *m_orderBlock;
    
    // Initialization flag
    bool m_initialized;
    
    // Chart display settings
    bool m_onlyShowImportant;
    
    // ================= PERFORMANCE OPTIMIZATION FIELDS =================
    // Indicator handles
    int m_atrHandle;
    
    // Caching
    double m_lastAtrValue;
    datetime m_lastAtrUpdate;
    double m_pointCache;
    datetime m_lastSymbolInfoUpdate;
    
    // Analysis caching
    string m_cachedAnalysisSymbol;
    ENUM_TIMEFRAMES m_cachedAnalysisTF;
    datetime m_cachedAnalysisTime;
    MarketStructureScore m_cachedScore;
    
    // Order block score caching
    datetime m_lastOrderBlockCalc;
    double m_cachedOrderBlockScore;
    
    // Regime detection caching
    datetime m_lastRegimeCalc;
    MARKET_REGIME m_cachedRegime;
    
    // String constants
    static const string STR_NEUTRAL;
    static const string STR_NONE;
    
public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    MarketStructureEngine();
    ~MarketStructureEngine();
    
    // ================= INITIALIZATION METHODS =================
    bool Initialize(ResourceManager *logger, COrderBlock *ob);
    void Deinitialize();
    
    // ================= MAIN PUBLIC INTERFACE =================
    MarketStructureScore AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES tf);
    double GetOverallConfidence(string symbol);
    string GetMarketBias(string symbol);
    STRUCTURE_SIGNAL GetStructureSignal(string symbol);
    
    // Strategy selection
    string SelectBestStrategy(string symbol);
    bool IsStrategyValid(string strategy, string symbol);
    double CalculateStrategyScore(string strategy, string symbol);
    
    // Primitive integration
    void UpdatePrimitiveAvailability();
    double GetPrimitiveScore(string primitive, string symbol);
    double GetNormalizedScore(double rawScore, string primitive);
    
    // Weight management
    void AdjustWeightsForMarketRegime(MARKET_REGIME regime);
    void AdjustWeight(string primitive, double multiplier);
    void RebalanceWeights();
    double GetAdjustedWeight(string primitive);
    
    // Regime detection
    MARKET_REGIME DetectMarketRegime(string symbol);
    double CalculateRegimeStrength(string symbol);
    
    // Chart display control
    void SetChartDisplay(bool showComments, bool onlyImportant = true);
    void UpdateChartDisplay(string symbol, MarketStructureScore &score);
    
    // Event handlers
    void OnTick();
    void OnTimer();
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                           const MqlTradeRequest& request,
                           const MqlTradeResult& result);
    
    // State check
    bool IsInitialized() const { return m_initialized; }
    
private:
    // ================= PRIVATE CORE FUNCTIONS =================
    // Primitive scoring
    double GetOrderBlockScore(string symbol);
    double GetSSDDScore(string symbol);
    double GetBOSScore(string symbol);
    double GetMSSScore(string symbol);
    double GetCHOCHScore(string symbol);
    double GetLiquidityScore(string symbol);
    double GetOrderFlowScore(string symbol);
    
    // Score calculation
    void CalculateTotalConfidence();
    void NormalizePrimitiveScores();
    void ApplyMarketRegimeAdjustments();
    
    // Strategy evaluation
    StrategyRequirements GetStrategyRequirements(string strategy);
    bool CheckStrategyConfluence(string strategy, MarketStructureScore &score);
    
    // Signal generation
    STRUCTURE_SIGNAL GenerateSignalFromScores(MarketStructureScore &score);
    
    // Helper functions
    bool IsPrimitiveAvailable(int index);
    void InitializeBaseWeights();
    void EnsureTotalWeight100();
    double CalculateWeightedAverage();
    
    // Default scores for unavailable primitives
    double GetDefaultScore(string primitive);
    
    // Logging and display helpers
    void LogPrimitiveScores(MarketStructureScore &score);
    void DisplayImportantResults(string symbol, MarketStructureScore &score);
    string RegimeToString(MARKET_REGIME regime);
    string SignalToString(STRUCTURE_SIGNAL signal);
    
    // Decision helper
    string GenerateTradeDecision(MarketStructureScore &score);
    
    // ================= PERFORMANCE OPTIMIZATION METHODS =================
    double GetCachedATR(string symbol);
    double GetCachedPoint(string symbol);
};

// ================= EXTERNAL INTERFACE =================
// Quick access functions
double MarketStructure_GetConfidence(string symbol)
{
    MarketStructureEngine engine;
    return engine.GetOverallConfidence(symbol);
}

string MarketStructure_GetStrategy(string symbol)
{
    MarketStructureEngine engine;
    return engine.SelectBestStrategy(symbol);
}

bool MarketStructure_IsSignalValid(string symbol, STRUCTURE_SIGNAL signal)
{
    MarketStructureEngine engine;
    MarketStructureScore score = engine.AnalyzeMarketStructure(symbol, _Period);
    return (score.signal == signal && score.totalConfidence >= 70);
}

// Initialize string constants
const string MarketStructureEngine::STR_NEUTRAL = "NEUTRAL";
const string MarketStructureEngine::STR_NONE = "None";

// ================= IMPLEMENTATION =================

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
MarketStructureEngine::MarketStructureEngine()
{
    // Only set default values, NO initialization
    m_symbol = "";
    m_timeframe = PERIOD_CURRENT;
    m_orderBlock = NULL;
    m_logger = NULL;
    m_initialized = false;
    m_onlyShowImportant = true;
    
    // Initialize base weights array with zeros
    ArrayInitialize(m_baseWeights, 0.0);
    ArrayInitialize(m_primitiveAvailability, false);
    
    m_totalAnalyses = 0;
    m_accuracyRate = 0.0;
    
    // Initialize regime multipliers
    m_trendingMultiplier = 1.2;
    m_rangingMultiplier = 0.8;
    m_breakoutMultiplier = 1.5;
    m_highVolMultiplier = 0.7;
    
    // Initialize score structure using constructor
    m_currentScore = MarketStructureScore();
    m_currentScore.bias = STR_NEUTRAL;
    m_currentScore.recommendedStrategy = STR_NONE;
    
    // ================= PERFORMANCE OPTIMIZATION INIT =================
    // Initialize indicator handles
    m_atrHandle = INVALID_HANDLE;
    m_lastAtrValue = 0.0;
    m_lastAtrUpdate = 0;
    m_pointCache = 0.0;
    m_lastSymbolInfoUpdate = 0;
    
    // Initialize caching
    m_cachedAnalysisSymbol = "";
    m_cachedAnalysisTF = PERIOD_CURRENT;
    m_cachedAnalysisTime = 0;
    m_cachedScore = MarketStructureScore();
    
    m_lastOrderBlockCalc = 0;
    m_cachedOrderBlockScore = 50.0;
    
    m_lastRegimeCalc = 0;
    m_cachedRegime = REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
MarketStructureEngine::~MarketStructureEngine()
{
    // If initialized, call Deinitialize
    if(m_initialized) {
        Deinitialize();
    }
}

//+------------------------------------------------------------------+
//| Initialize - The ONE AND ONLY real initialization method         |
//+------------------------------------------------------------------+
bool MarketStructureEngine::Initialize(ResourceManager *logger, COrderBlock *ob)
{
    // Prevent re-initialization
    if(m_initialized) {
        if(logger) {
            logger.KeepNotes(_Symbol, WARN, "MarketStructureEngine_Initialize", 
                "Already initialized, skipping", false, false, 0.0);
        }
        return true;
    }
    
    // Validate dependencies
    if(logger == NULL) {
        Print("MarketStructureEngine::Initialize() - WARN: ResourceManager is NULL");
        return false;
    }
    if(ob == NULL) {
        Print("MarketStructureEngine::Initialize() - WARN: COrderBlock is NULL");
        return false;
    }
    
    m_logger = logger;
    m_orderBlock = ob;
    m_symbol = _Symbol;
    m_timeframe = _Period;
    
    // Initialize logger context
    m_logger.StartContextWith(m_symbol, "MarketStructureEngine_Init");
    m_logger.AddToContext(m_symbol, "Component", "MarketStructureEngine", true);
    m_logger.AddToContext(m_symbol, "Version", "1.00", true);
    m_logger.AddBoolContext(m_symbol, "OnlyShowImportant", m_onlyShowImportant);
    
    // Initialize base weights
    InitializeBaseWeights();
    
    // Check primitive availability
    UpdatePrimitiveAvailability();
    
    // ================= PERFORMANCE OPTIMIZATION: Create indicator handles =================
    m_atrHandle = iATR(m_symbol, m_timeframe, 14);
    if(m_atrHandle == INVALID_HANDLE) {
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, WARN, "MarketStructureEngine_Initialize", 
                "Failed to create ATR indicator", false, false, 0.0);
        }
    }
    
    // Log initialization
    m_logger.AddToContext(m_symbol, "BaseWeightsSet", "TRUE", true);
    m_logger.AddDoubleContext(m_symbol, "TrendingMultiplier", m_trendingMultiplier, 2);
    m_logger.AddDoubleContext(m_symbol, "RangingMultiplier", m_rangingMultiplier, 2);
    m_logger.AddDoubleContext(m_symbol, "BreakoutMultiplier", m_breakoutMultiplier, 2);
    m_logger.AddDoubleContext(m_symbol, "HighVolMultiplier", m_highVolMultiplier, 2);
    
    m_initialized = true;
    
    m_logger.KeepNotes(m_symbol, OBSERVE, "MarketStructureEngine", 
        "Engine initialized successfully", false, false, 0.0);
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize - Cleanup counterpart                               |
//+------------------------------------------------------------------+
void MarketStructureEngine::Deinitialize()
{
    if(!m_initialized) {
        return;
    }
    
    // Log shutdown start
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "MarketStructureEngine_Shutdown");
    }
    
    // ================= PERFORMANCE OPTIMIZATION: Release indicator handles =================
    if(m_atrHandle != INVALID_HANDLE) {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
    
    // Clean up primitive modules
    if(m_orderBlock != NULL) {
        delete m_orderBlock;
        m_orderBlock = NULL;
    }
    
    // Log performance summary
    if(m_logger) {
        m_logger.AddToContext(m_symbol, "TotalAnalyses", IntegerToString(m_totalAnalyses), true);
        m_logger.AddDoubleContext(m_symbol, "AccuracyRate", m_accuracyRate, 2);
        m_logger.KeepNotes(m_symbol, AUDIT, "MarketStructureEngine", 
            "Engine shutdown complete", false, false, 0.0);
        
        // Clear references
        m_logger = NULL;
    }
    
    // Reset state
    m_initialized = false;
    m_symbol = "";
    m_timeframe = PERIOD_CURRENT;
    m_totalAnalyses = 0;
    m_accuracyRate = 0.0;
    
    // Reset score structure
    m_currentScore = MarketStructureScore();
    m_currentScore.bias = STR_NEUTRAL;
    m_currentScore.recommendedStrategy = STR_NONE;
}

//+------------------------------------------------------------------+
//| Event handler: OnTick                                            |
//+------------------------------------------------------------------+
void MarketStructureEngine::OnTick()
{
    // Only process if initialized
    if(!m_initialized) {
        return;
    }
}

//+------------------------------------------------------------------+
//| Event handler: OnTimer                                           |
//+------------------------------------------------------------------+
void MarketStructureEngine::OnTimer()
{
    // Only process if initialized
    if(!m_initialized) {
        return;
    }
    
    // Update primitive availability periodically
    if(TimeCurrent() % 300 == 0) { // Every 5 minutes
        UpdatePrimitiveAvailability();
    }
}

//+------------------------------------------------------------------+
//| Event handler: OnTradeTransaction                                |
//+------------------------------------------------------------------+
void MarketStructureEngine::OnTradeTransaction(const MqlTradeTransaction& trans,
                                             const MqlTradeRequest& request,
                                             const MqlTradeResult& result)
{
    // Only process if initialized
    if(!m_initialized) {
        return;
    }
    
    // Log trade transactions
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        if(m_logger) {
            m_logger.AutoLogTradeTransaction(trans);
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize base weights                                          |
//+------------------------------------------------------------------+
void MarketStructureEngine::InitializeBaseWeights()
{
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "InitializeBaseWeights");
    }
    
    m_baseWeights[0] = WEIGHT_ORDERFLOW;    // OrderFlow Cluster
    m_baseWeights[1] = WEIGHT_SSDD;         // SSDD Zone
    m_baseWeights[2] = WEIGHT_ORDERBLOCK;   // Order Block
    m_baseWeights[3] = WEIGHT_BOS;          // BOS
    m_baseWeights[4] = WEIGHT_MSS;          // MSS
    m_baseWeights[5] = WEIGHT_LIQUIDITY;    // Liquidity Grab
    m_baseWeights[6] = WEIGHT_CHOCH;        // CHOCH
    
    EnsureTotalWeight100();
    
    // Log the base weights
    if(m_logger) {
        const int totalWeights = 7;
        for(int i = 0; i < totalWeights; i++) {
            m_logger.AddDoubleContext(m_symbol, 
                StringFormat("Weight_%d", i), 
                m_baseWeights[i], 
                2);
        }
        
        m_logger.KeepNotes(m_symbol, OBSERVE, "InitializeBaseWeights", 
            "Base weights initialized", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Ensure weights total 100%                                        |
//+------------------------------------------------------------------+
void MarketStructureEngine::EnsureTotalWeight100()
{
    double total = 0;
    const int totalWeights = 7;
    
    // Cache array size before loop
    for(int i = 0; i < totalWeights; i++) {
        total += m_baseWeights[i];
    }
    
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "EnsureTotalWeight100");
        m_logger.AddDoubleContext(m_symbol, "InitialTotal", total, 2);
    }
    
    if(total != 100.0) {
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "RequiresRebalancing", "TRUE", true);
            m_logger.AddDoubleContext(m_symbol, "RebalanceFactor", 100.0 / total, 4);
        }
        
        double factor = 100.0 / total;
        for(int i = 0; i < totalWeights; i++) {
            m_baseWeights[i] *= factor;
        }
        
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, WARN, "EnsureTotalWeight100", 
                "Weights rebalanced to 100%", false, false, 0.0);
        }
    } else if(m_logger) {
        m_logger.KeepNotes(m_symbol, OBSERVE, "EnsureTotalWeight100", 
            "Weights already total 100%", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Update primitive availability                                    |
//+------------------------------------------------------------------+
void MarketStructureEngine::UpdatePrimitiveAvailability()
{
    if(!m_initialized) {
        return;
    }
    
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "UpdatePrimitiveAvailability");
    }
    
    // Check OrderBlock availability
    if(m_orderBlock == NULL) {
        m_orderBlock = new COrderBlock(m_symbol, m_timeframe);
    }
    
    if(CheckPointer(m_orderBlock) != POINTER_INVALID) {
        m_primitiveAvailability[2] = true;
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "OrderBlock", "AVAILABLE", true);
        }
    } else {
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "OrderBlock", "UNAVAILABLE", true);
        }
    }
    
    // Note: Other primitives will be checked as they become available
    m_primitiveAvailability[0] = false;  // OrderFlow Cluster
    m_primitiveAvailability[1] = false;  // SSDD Zone
    m_primitiveAvailability[3] = false;  // BOS
    m_primitiveAvailability[4] = false;  // MSS
    m_primitiveAvailability[5] = false;  // Liquidity Grab
    m_primitiveAvailability[6] = false;  // CHOCH
    
    // Log availability status
    if(m_logger) {
        string availablePrimitives = "";
        const int totalPrimitives = 7;
        for(int i = 0; i < totalPrimitives; i++) {
            if(m_primitiveAvailability[i]) {
                availablePrimitives += StringFormat("%d,", i);
            }
        }
        m_logger.AddToContext(m_symbol, "AvailablePrimitives", availablePrimitives, true);
        m_logger.KeepNotes(m_symbol, OBSERVE, "UpdatePrimitiveAvailability", 
            "Primitive availability updated", false, false, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Main analysis function                                           |
//+------------------------------------------------------------------+
MarketStructureScore MarketStructureEngine::AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES tf)
{
    // ================= PERFORMANCE OPTIMIZATION: Early exit for invalid state =================
    if(!m_initialized) {
        MarketStructureScore emptyScore;
        emptyScore.bias = STR_NEUTRAL;
        emptyScore.recommendedStrategy = STR_NONE;
        return emptyScore;
    }
    
    // ================= PERFORMANCE OPTIMIZATION: Cache analysis results for 2 seconds =================
    bool useCache = (symbol == m_cachedAnalysisSymbol && 
                     tf == m_cachedAnalysisTF && 
                     TimeCurrent() <= m_cachedAnalysisTime + 2);
    
    if(useCache && m_cachedAnalysisTime > 0) {
        return m_cachedScore;
    }
    
    if(m_logger) {
        m_logger.StartContextWith(symbol, "AnalyzeMarketStructure");
        m_logger.AddToContext(symbol, "Timeframe", EnumToString(tf), true);
    }
    
    m_symbol = symbol;
    m_timeframe = tf;
    
    // ================= PERFORMANCE OPTIMIZATION: Use cached regime detection =================
    m_currentRegime = DetectMarketRegime(symbol);
    if(m_logger) {
        m_logger.AddToContext(symbol, "MarketRegime", RegimeToString(m_currentRegime), true);
    }
    
    // Get scores from all primitives
    PrimitiveScore primitiveScores[7];
    const int totalPrimitives = 7;
    
    // Initialize primitive scores
    for(int i = 0; i < totalPrimitives; i++) {
        primitiveScores[i] = PrimitiveScore();
    }
    
    // ================= PERFORMANCE OPTIMIZATION: Batch primitive score calculations =================
    // OrderFlow Cluster
    primitiveScores[0].primitiveName = "OrderFlow";
    primitiveScores[0].rawScore = GetOrderFlowScore(symbol);
    primitiveScores[0].rank = RANK_ORDERFLOW_CLUSTER;
    primitiveScores[0].isAvailable = m_primitiveAvailability[0];
    
    // SSDD Zone
    primitiveScores[1].primitiveName = "SSDD";
    primitiveScores[1].rawScore = GetSSDDScore(symbol);
    primitiveScores[1].rank = RANK_SSDD_ZONE;
    primitiveScores[1].isAvailable = m_primitiveAvailability[1];
    
    // Order Block
    primitiveScores[2].primitiveName = "OrderBlock";
    primitiveScores[2].rawScore = GetOrderBlockScore(symbol);
    primitiveScores[2].rank = RANK_ORDER_BLOCK;
    primitiveScores[2].isAvailable = m_primitiveAvailability[2];
    
    // BOS
    primitiveScores[3].primitiveName = "BOS";
    primitiveScores[3].rawScore = GetBOSScore(symbol);
    primitiveScores[3].rank = RANK_BOS;
    primitiveScores[3].isAvailable = m_primitiveAvailability[3];
    
    // MSS
    primitiveScores[4].primitiveName = "MSS";
    primitiveScores[4].rawScore = GetMSSScore(symbol);
    primitiveScores[4].rank = RANK_MSS;
    primitiveScores[4].isAvailable = m_primitiveAvailability[4];
    
    // Liquidity Grab
    primitiveScores[5].primitiveName = "Liquidity";
    primitiveScores[5].rawScore = GetLiquidityScore(symbol);
    primitiveScores[5].rank = RANK_LIQUIDITY_GRAB;
    primitiveScores[5].isAvailable = m_primitiveAvailability[5];
    
    // CHOCH
    primitiveScores[6].primitiveName = "CHOCH";
    primitiveScores[6].rawScore = GetCHOCHScore(symbol);
    primitiveScores[6].rank = RANK_CHOCH;
    primitiveScores[6].isAvailable = m_primitiveAvailability[6];
    
    // Log raw scores if needed
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        for(int i = 0; i < totalPrimitives; i++) {
            m_logger.AddDoubleContext(symbol, 
                StringFormat("%s_RawScore", primitiveScores[i].primitiveName), 
                primitiveScores[i].rawScore, 
                2);
        }
    }
    #endif
    
    // Apply base weights
    for(int i = 0; i < totalPrimitives; i++) {
        primitiveScores[i].weight = m_baseWeights[i];
        primitiveScores[i].adjustedWeight = m_baseWeights[i];
    }
    
    // Adjust weights for current regime
    AdjustWeightsForMarketRegime(m_currentRegime);
    
    // Normalize scores (handle unavailable primitives)
    for(int i = 0; i < totalPrimitives; i++) {
        if(!primitiveScores[i].isAvailable) {
            primitiveScores[i].rawScore = GetDefaultScore(primitiveScores[i].primitiveName);
            #ifdef MARKET_STRUCTURE_DEBUG
            if(m_logger) {
                m_logger.AddToContext(symbol, 
                    StringFormat("%s_UsingDefault", primitiveScores[i].primitiveName), 
                    "TRUE", 
                    true);
            }
            #endif
        }
        primitiveScores[i].normalizedScore = GetNormalizedScore(primitiveScores[i].rawScore, 
                                                               primitiveScores[i].primitiveName);
    }
    
    // Calculate weighted scores
    double totalWeight = 0;
    double weightedSum = 0;
    
    for(int i = 0; i < totalPrimitives; i++) {
        if(primitiveScores[i].isAvailable) {
            primitiveScores[i].adjustedWeight = GetAdjustedWeight(primitiveScores[i].primitiveName);
            primitiveScores[i].weightedScore = primitiveScores[i].normalizedScore * 
                                              primitiveScores[i].adjustedWeight / 100.0;
            weightedSum += primitiveScores[i].weightedScore;
            totalWeight += primitiveScores[i].adjustedWeight;
        }
    }
    
    // Rebalance if some primitives are unavailable
    if(totalWeight < 100.0) {
        if(totalWeight <= 0.001) {
            weightedSum = 50.0;
            
            if(m_logger) {
                m_logger.KeepNotes(symbol, WARN, "AnalyzeMarketStructure", 
                    StringFormat("Cannot redistribute: totalWeight=%.4f (too low). Using neutral score.", 
                        totalWeight), 
                    false, false, 0.0);
            }
        }
        else {
            double redistributionFactor = 100.0 / totalWeight;
            weightedSum *= redistributionFactor;
            
            #ifdef MARKET_STRUCTURE_DEBUG
            if(m_logger) {
                m_logger.AddDoubleContext(symbol, "RedistributionFactor", redistributionFactor, 4);
                m_logger.KeepNotes(symbol, WARN, "AnalyzeMarketStructure", 
                    StringFormat("Weights redistributed. totalWeight=%.2f, factor=%.2f", 
                        totalWeight, redistributionFactor), 
                    false, false, 0.0);
            }
            #endif
        }
    }
    
    // Populate the result structure
    m_currentScore.currentRegime = m_currentRegime;
    m_currentScore.analysisTime = TimeCurrent();
    m_currentScore.totalConfidence = weightedSum;
    
    // Copy primitive scores
    for(int i = 0; i < totalPrimitives; i++) {
        m_currentScore.scores[i] = primitiveScores[i];
    }
    
    // Generate signal
    m_currentScore.signal = GenerateSignalFromScores(m_currentScore);
    
    // Determine bias
    if(m_currentScore.totalConfidence >= 60) {
        // Determine direction based on strongest primitive signals
        m_currentScore.bias = STR_NEUTRAL;
    } else {
        m_currentScore.bias = STR_NEUTRAL;
    }
    
    if(m_logger) {
        m_logger.AddToContext(symbol, "MarketBias", m_currentScore.bias, true);
        m_logger.AddDoubleContext(symbol, "TotalConfidence", m_currentScore.totalConfidence, 2);
    }
    
    m_totalAnalyses++;
    
    // ================= PERFORMANCE OPTIMIZATION: Store in cache =================
    m_cachedAnalysisSymbol = symbol;
    m_cachedAnalysisTF = tf;
    m_cachedAnalysisTime = TimeCurrent();
    m_cachedScore = m_currentScore;
    
    // Log detailed primitive scores
    LogPrimitiveScores(m_currentScore);
    
    if(m_logger) {
        m_logger.KeepNotes(symbol, AUTHORIZE, "AnalyzeMarketStructure", 
            StringFormat("Analysis complete: Confidence=%.2f, Regime=%s, Signal=%s", 
                m_currentScore.totalConfidence, 
                RegimeToString(m_currentRegime),
                SignalToString(m_currentScore.signal)), 
            false, false, 0.0);
    }
    
    return m_currentScore;
}

//+------------------------------------------------------------------+
//| Get OrderBlock score                                             |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetOrderBlockScore(string symbol)
{
    // Early exit checks from cheapest to most expensive
    if(!m_initialized) {
        return GetDefaultScore("OrderBlock");
    }
    
    if(!m_primitiveAvailability[2]) {
        return GetDefaultScore("OrderBlock");
    }
    
    // Early exit if order block is null
    if(m_orderBlock == NULL) {
        return GetDefaultScore("OrderBlock");
    }
    
    // ================= PERFORMANCE OPTIMIZATION: Cache order block scores for 3 seconds =================
    if(TimeCurrent() <= m_lastOrderBlockCalc + 3 && m_lastOrderBlockCalc > 0) {
        return m_cachedOrderBlockScore;
    }
    
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    double score = m_orderBlock.GetScoreAtPrice(currentPrice);
    
    // Clamp score to 0-100 range
    m_cachedOrderBlockScore = MathMax(0, MathMin(100, score));
    m_lastOrderBlockCalc = TimeCurrent();
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(symbol, "GetOrderBlockScore");
        m_logger.AddDoubleContext(symbol, "CurrentPrice", currentPrice, 5);
        m_logger.AddDoubleContext(symbol, "OrderBlockScore", m_cachedOrderBlockScore, 2);
        m_logger.FlushContext(symbol, OBSERVE, "GetOrderBlockScore", 
            "OrderBlock score calculated and cached", false);
    }
    #endif
    
    return m_cachedOrderBlockScore;
}

//+------------------------------------------------------------------+
//| Get SSDD score (placeholder until module is available)          |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetSSDDScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetSSDDScore", 
            "SSDD primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("SSDD");
}

//+------------------------------------------------------------------+
//| Get BOS score (placeholder)                                      |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetBOSScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetBOSScore", 
            "BOS primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("BOS");
}

//+------------------------------------------------------------------+
//| Get MSS score (placeholder)                                      |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetMSSScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetMSSScore", 
            "MSS primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("MSS");
}

//+------------------------------------------------------------------+
//| Get CHOCH score (placeholder)                                    |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetCHOCHScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetCHOCHScore", 
            "CHOCH primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("CHOCH");
}

//+------------------------------------------------------------------+
//| Get Liquidity score (placeholder)                                |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetLiquidityScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetLiquidityScore", 
            "Liquidity primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("Liquidity");
}

//+------------------------------------------------------------------+
//| Get OrderFlow score (placeholder)                                |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetOrderFlowScore(string symbol)
{
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized) {
        m_logger.KeepNotes(symbol, WARN, "GetOrderFlowScore", 
            "OrderFlow primitive not yet implemented, using default", false, false, 0.0);
    }
    #endif
    return GetDefaultScore("OrderFlow");
}

//+------------------------------------------------------------------+
//| Get default score for unavailable primitives                     |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetDefaultScore(string primitive)
{
    // ================= PERFORMANCE OPTIMIZATION: Use static arrays for default scores =================
    static const string primitives[7] = {"OrderFlow", "SSDD", "OrderBlock", "BOS", "MSS", "Liquidity", "CHOCH"};
    static const double defaults[7] = {50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0};
    
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        if(primitives[i] == primitive) {
            return defaults[i];
        }
    }
    
    return 50.0;
}

//+------------------------------------------------------------------+
//| Normalize primitive scores                                       |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetNormalizedScore(double rawScore, string primitive)
{
    // Apply primitive-specific normalization if needed
    // For now, just ensure score is between 0-100
    double normalized = MathMax(0, MathMin(100, rawScore));
    
    // ================= PERFORMANCE OPTIMIZATION: Reduced logging =================
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger && m_initialized && MathAbs(rawScore - normalized) > 0.1) {
        m_logger.StartContextWith(m_symbol, "GetNormalizedScore");
        m_logger.AddToContext(m_symbol, "Primitive", primitive, true);
        m_logger.AddDoubleContext(m_symbol, "RawScore", rawScore, 2);
        m_logger.AddDoubleContext(m_symbol, "NormalizedScore", normalized, 2);
        m_logger.FlushContext(m_symbol, AUDIT, "GetNormalizedScore", 
            StringFormat("Normalized %s score: %.2f . %.2f", primitive, rawScore, normalized), 
            false);
    }
    #endif
    
    return normalized;
}

//+------------------------------------------------------------------+
//| Get cached ATR value                                             |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetCachedATR(string symbol)
{
    // Cache ATR for 2 seconds
    if(TimeCurrent() <= m_lastAtrUpdate + 2 && m_lastAtrUpdate > 0) {
        return m_lastAtrValue;
    }
    
    if(m_atrHandle != INVALID_HANDLE) {
        double atrValues[1];
        int copied = CopyBuffer(m_atrHandle, 0, 0, 1, atrValues);
        if(copied > 0) {
            m_lastAtrValue = atrValues[0];
            m_lastAtrUpdate = TimeCurrent();
            return m_lastAtrValue;
        }
    }
    
    // Fallback to direct call
    m_lastAtrValue = iATR(symbol, m_timeframe, 14);
    m_lastAtrUpdate = TimeCurrent();
    return m_lastAtrValue;
}

//+------------------------------------------------------------------+
//| Get cached point value                                           |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetCachedPoint(string symbol)
{
    // Cache point value for 5 seconds
    if(TimeCurrent() <= m_lastSymbolInfoUpdate + 5 && m_lastSymbolInfoUpdate > 0) {
        return m_pointCache;
    }
    
    m_pointCache = SymbolInfoDouble(symbol, SYMBOL_POINT);
    m_lastSymbolInfoUpdate = TimeCurrent();
    return m_pointCache;
}

//+------------------------------------------------------------------+
//| Detect market regime                                             |
//+------------------------------------------------------------------+
MARKET_REGIME MarketStructureEngine::DetectMarketRegime(string symbol)
{
    // Early exit if not initialized
    if(!m_initialized) {
        return REGIME_RANGING;
    }
    
    // ================= PERFORMANCE OPTIMIZATION: Cache regime for 5 seconds =================
    if(TimeCurrent() <= m_lastRegimeCalc + 5 && m_lastRegimeCalc > 0) {
        return m_cachedRegime;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(symbol, "DetectMarketRegime");
    }
    #endif
    
    // Get ATR using cached value
    double atr = GetCachedATR(symbol);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    double atrPercent = (atr / currentPrice) * 100;
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.AddDoubleContext(symbol, "ATR", atr, 5);
        m_logger.AddDoubleContext(symbol, "CurrentPrice", currentPrice, 5);
        m_logger.AddDoubleContext(symbol, "ATRPercent", atrPercent, 2);
    }
    #endif
    
    if(atrPercent > 0.5) {
        m_cachedRegime = REGIME_HIGH_VOLATILITY;
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(symbol, "RegimeDecision", "HIGH_VOLATILITY", true);
            m_logger.KeepNotes(symbol, OBSERVE, "DetectMarketRegime", 
                StringFormat("High volatility detected: ATR=%.5f (%.2f%%)", atr, atrPercent), 
                false, false, 0.0);
        }
        #endif
    } else {
        // Placeholder - would use actual trend detection
        m_cachedRegime = REGIME_RANGING;
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(symbol, "RegimeDecision", "RANGING", true);
            m_logger.KeepNotes(symbol, OBSERVE, "DetectMarketRegime", 
                StringFormat("Ranging market detected: ATR=%.5f (%.2f%%)", atr, atrPercent), 
                false, false, 0.0);
        }
        #endif
    }
    
    m_lastRegimeCalc = TimeCurrent();
    return m_cachedRegime;
}

//+------------------------------------------------------------------+
//| Calculate regime strength                                        |
//+------------------------------------------------------------------+
double MarketStructureEngine::CalculateRegimeStrength(string symbol)
{
    // Cache for 10 seconds since this doesn't change rapidly
    static datetime lastStrengthCalc = 0;
    static double cachedStrength = 0.5;
    
    if(TimeCurrent() <= lastStrengthCalc + 10 && lastStrengthCalc > 0) {
        return cachedStrength;
    }
    
    // Simple strength calculation based on ATR percentage
    double atr = GetCachedATR(symbol);
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    cachedStrength = MathMin(1.0, (atr / price) * 100 / 0.5);
    lastStrengthCalc = TimeCurrent();
    
    return cachedStrength;
}

//+------------------------------------------------------------------+
//| Adjust weights for market regime - FIXED VERSION                |
//+------------------------------------------------------------------+
void MarketStructureEngine::AdjustWeightsForMarketRegime(MARKET_REGIME regime)
{
    if(!m_initialized) {
        return;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "AdjustWeightsForMarketRegime");
        m_logger.AddToContext(m_symbol, "Regime", RegimeToString(regime), true);
    }
    #endif
    
    // ================= PERFORMANCE OPTIMIZATION: Use pre-calculated multiplier arrays =================
    // Define multiplier arrays for each regime
    double trendingMultipliers[7] = {1.0, 1.0, 0.8, 1.2, 1.2, 0.5, 1.2};
    double rangingMultipliers[7] = {1.0, 1.2, 1.2, 0.5, 0.8, 1.3, 0.8};
    double breakoutMultipliers[7] = {1.3, 0.8, 0.9, 1.5, 1.3, 1.2, 0.7};
    double highVolMultipliers[7] = {1.2, 0.8, 0.9, 0.7, 0.9, 2.0, 0.6};
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        switch(regime) {
            case REGIME_TRENDING_BULLISH:
            case REGIME_TRENDING_BEARISH:
                m_logger.AddToContext(m_symbol, "WeightAdjustment", "TRENDING_REGIME", true);
                break;
            case REGIME_RANGING:
                m_logger.AddToContext(m_symbol, "WeightAdjustment", "RANGING_REGIME", true);
                break;
            case REGIME_BREAKOUT:
                m_logger.AddToContext(m_symbol, "WeightAdjustment", "BREAKOUT_REGIME", true);
                break;
            case REGIME_HIGH_VOLATILITY:
                m_logger.AddToContext(m_symbol, "WeightAdjustment", "HIGH_VOL_REGIME", true);
                break;
            default:
                m_logger.AddToContext(m_symbol, "WeightAdjustment", "NO_ADJUSTMENT", true);
                break;
        }
    }
    #endif
    
    // Apply multipliers based on regime
    const int totalPrimitives = 7;
    
    switch(regime) {
        case REGIME_TRENDING_BULLISH:
        case REGIME_TRENDING_BEARISH:
            for(int i = 0; i < totalPrimitives; i++) {
                m_currentScore.scores[i].adjustedWeight = m_baseWeights[i] * trendingMultipliers[i];
            }
            break;
            
        case REGIME_RANGING:
            for(int i = 0; i < totalPrimitives; i++) {
                m_currentScore.scores[i].adjustedWeight = m_baseWeights[i] * rangingMultipliers[i];
            }
            break;
            
        case REGIME_BREAKOUT:
            for(int i = 0; i < totalPrimitives; i++) {
                m_currentScore.scores[i].adjustedWeight = m_baseWeights[i] * breakoutMultipliers[i];
            }
            break;
            
        case REGIME_HIGH_VOLATILITY:
            for(int i = 0; i < totalPrimitives; i++) {
                m_currentScore.scores[i].adjustedWeight = m_baseWeights[i] * highVolMultipliers[i];
            }
            break;
            
        default:
            // No adjustment for unknown regimes
            for(int i = 0; i < totalPrimitives; i++) {
                m_currentScore.scores[i].adjustedWeight = m_baseWeights[i];
            }
            return;
    }
    
    // Log adjusted weights in debug mode
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        for(int i = 0; i < totalPrimitives; i++) {
            m_logger.AddDoubleContext(m_symbol, 
                StringFormat("%s_AdjustedWeight", m_currentScore.scores[i].primitiveName), 
                m_currentScore.scores[i].adjustedWeight, 
                2);
        }
    }
    #endif
    
    // Rebalance to ensure total is 100%
    RebalanceWeights();
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.KeepNotes(m_symbol, OBSERVE, "AdjustWeightsForMarketRegime", 
            StringFormat("Weights adjusted for %s regime", RegimeToString(regime)), 
            false, false, 0.0);
    }
    #endif
}

//+------------------------------------------------------------------+
//| Adjust individual weight                                         |
//+------------------------------------------------------------------+
void MarketStructureEngine::AdjustWeight(string primitive, double multiplier)
{
    if(!m_initialized) {
        return;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "AdjustWeight");
        m_logger.AddToContext(m_symbol, "Primitive", primitive, true);
        m_logger.AddDoubleContext(m_symbol, "Multiplier", multiplier, 2);
    }
    #endif
    
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        if(m_currentScore.scores[i].primitiveName == primitive) {
            double oldWeight = m_currentScore.scores[i].adjustedWeight;
            m_currentScore.scores[i].adjustedWeight *= multiplier;
            #ifdef MARKET_STRUCTURE_DEBUG
            if(m_logger) {
                m_logger.AddDoubleContext(m_symbol, "OldWeight", oldWeight, 2);
                m_logger.AddDoubleContext(m_symbol, "NewWeight", m_currentScore.scores[i].adjustedWeight, 2);
            }
            #endif
            break;
        }
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.FlushContext(m_symbol, AUDIT, "AdjustWeight", 
            StringFormat("Adjusted %s weight by factor %.2f", primitive, multiplier), 
            false);
    }
    #endif
}

//+------------------------------------------------------------------+
//| Rebalance weights to total 100%                                  |
//+------------------------------------------------------------------+
void MarketStructureEngine::RebalanceWeights()
{
    if(!m_initialized) {
        return;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "RebalanceWeights");
    }
    #endif
    
    double total = 0;
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        total += m_currentScore.scores[i].adjustedWeight;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.AddDoubleContext(m_symbol, "PreRebalanceTotal", total, 2);
    }
    #endif
    
    if(MathAbs(total - 100.0) > 0.001) {
        double factor = 100.0 / total;
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddDoubleContext(m_symbol, "RebalanceFactor", factor, 4);
        }
        #endif
        
        for(int i = 0; i < totalPrimitives; i++) {
            m_currentScore.scores[i].adjustedWeight *= factor;
        }
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, ENFORCE, "RebalanceWeights", 
                StringFormat("Weights rebalanced from %.2f to 100%%", total), 
                false, false, 0.0);
        }
        #endif
    } else {
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, OBSERVE, "RebalanceWeights", 
                "Weights already total 100%", false, false, 0.0);
        }
        #endif
    }
}

//+------------------------------------------------------------------+
//| Select best strategy based on scores                             |
//+------------------------------------------------------------------+
string MarketStructureEngine::SelectBestStrategy(string symbol)
{
    if(!m_initialized) {
        return STR_NONE;
    }
    
    if(m_logger) {
        m_logger.StartContextWith(symbol, "SelectBestStrategy");
    }
    
    MarketStructureScore score = AnalyzeMarketStructure(symbol, m_timeframe);
    
    // Define strategy requirements
    StrategyRequirements institutional = GetStrategyRequirements("Institutional");
    StrategyRequirements breakout = GetStrategyRequirements("Breakout");
    StrategyRequirements zoneReversal = GetStrategyRequirements("ZoneReversal");
    StrategyRequirements scalping = GetStrategyRequirements("Scalping");
    
    // Calculate scores for each strategy
    double instScore = CalculateStrategyScore("Institutional", symbol);
    double breakScore = CalculateStrategyScore("Breakout", symbol);
    double zoneScore = CalculateStrategyScore("ZoneReversal", symbol);
    double scalpScore = CalculateStrategyScore("Scalping", symbol);
    
    if(m_logger) {
        m_logger.AddDoubleContext(symbol, "InstitutionalScore", instScore, 2);
        m_logger.AddDoubleContext(symbol, "BreakoutScore", breakScore, 2);
        m_logger.AddDoubleContext(symbol, "ZoneReversalScore", zoneScore, 2);
        m_logger.AddDoubleContext(symbol, "ScalpingScore", scalpScore, 2);
    }
    
    // Find best strategy
    double bestScore = 0;
    string bestStrategy = STR_NONE;
    
    if(instScore > bestScore && instScore >= institutional.minOverallScore) {
        bestScore = instScore;
        bestStrategy = "Institutional";
    }
    
    if(breakScore > bestScore && breakScore >= breakout.minOverallScore) {
        bestScore = breakScore;
        bestStrategy = "Breakout";
    }
    
    if(zoneScore > bestScore && zoneScore >= zoneReversal.minOverallScore) {
        bestScore = zoneScore;
        bestStrategy = "ZoneReversal";
    }
    
    if(scalpScore > bestScore && scalpScore >= scalping.minOverallScore) {
        bestScore = scalpScore;
        bestStrategy = "Scalping";
    }
    
    m_currentScore.recommendedStrategy = bestStrategy;
    m_currentScore.isStrategyValid = (bestStrategy != STR_NONE);
    
    if(m_logger) {
        m_logger.AddToContext(symbol, "BestStrategy", bestStrategy, true);
        m_logger.AddDoubleContext(symbol, "BestStrategyScore", bestScore, 2);
        m_logger.AddBoolContext(symbol, "StrategyValid", m_currentScore.isStrategyValid);
        
        m_logger.KeepNotes(symbol, AUTHORIZE, "SelectBestStrategy", 
            StringFormat("Selected strategy: %s (Score: %.2f)", bestStrategy, bestScore), 
            false, false, 0.0);
    }
    
    return bestStrategy;
}

//+------------------------------------------------------------------+
//| Get strategy requirements                                        |
//+------------------------------------------------------------------+
StrategyRequirements MarketStructureEngine::GetStrategyRequirements(string strategy)
{
    StrategyRequirements req;
    req.strategyName = strategy;
    
    if(strategy == "Institutional") {
        req.minOverallScore = 85.0;
        req.minOrderFlow = 80.0;
        req.minSSDD = 75.0;
        req.minOrderBlock = 70.0;
        req.minBOS = 60.0;
        req.minMSS = 60.0;
        req.maxLiquidityRisk = 20.0;
        req.requireConfluence = true;
    }
    else if(strategy == "Breakout") {
        req.minOverallScore = 75.0;
        req.minOrderFlow = 60.0;
        req.minSSDD = 50.0;
        req.minOrderBlock = 55.0;
        req.minBOS = 70.0;
        req.minMSS = 65.0;
        req.maxLiquidityRisk = 35.0;
        req.requireConfluence = true;
    }
    else if(strategy == "ZoneReversal") {
        req.minOverallScore = 70.0;
        req.minOrderFlow = 50.0;
        req.minSSDD = 70.0;
        req.minOrderBlock = 65.0;
        req.minBOS = 50.0;
        req.minMSS = 50.0;
        req.maxLiquidityRisk = 30.0;
        req.requireConfluence = true;
    }
    else if(strategy == "Scalping") {
        req.minOverallScore = 65.0;
        req.minOrderFlow = 40.0;
        req.minSSDD = 60.0;
        req.minOrderBlock = 50.0;
        req.minBOS = 55.0;
        req.minMSS = 50.0;
        req.maxLiquidityRisk = 25.0;
        req.requireConfluence = false;
    }
    
    return req;
}

//+------------------------------------------------------------------+
//| Calculate strategy score                                         |
//+------------------------------------------------------------------+
double MarketStructureEngine::CalculateStrategyScore(string strategy, string symbol)
{
    if(!m_initialized) {
        return 0.0;
    }
    
    if(m_logger) {
        m_logger.StartContextWith(symbol, "CalculateStrategyScore");
        m_logger.AddToContext(symbol, "Strategy", strategy, true);
    }
    
    MarketStructureScore score = AnalyzeMarketStructure(symbol, m_timeframe);
    StrategyRequirements req = GetStrategyRequirements(strategy);
    
    double strategyScore = 0;
    
    // Check each requirement
    if(score.totalConfidence >= req.minOverallScore) {
        strategyScore += 20;
        if(m_logger) {
            m_logger.AddToContext(symbol, "OverallScoreMet", "TRUE", true);
        }
    } else {
        if(m_logger) {
            m_logger.AddToContext(symbol, "OverallScoreMet", "FALSE", true);
        }
    }
    
    // Check individual primitive scores
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        if(score.scores[i].primitiveName == "OrderFlow" && 
           score.scores[i].normalizedScore >= req.minOrderFlow) {
            strategyScore += 15;
            if(m_logger) {
                m_logger.AddToContext(symbol, "OrderFlowMet", "TRUE", true);
            }
        }
        else if(score.scores[i].primitiveName == "SSDD" && 
                score.scores[i].normalizedScore >= req.minSSDD) {
            strategyScore += 15;
            if(m_logger) {
                m_logger.AddToContext(symbol, "SSDDMet", "TRUE", true);
            }
        }
        else if(score.scores[i].primitiveName == "OrderBlock" && 
                score.scores[i].normalizedScore >= req.minOrderBlock) {
            strategyScore += 15;
            if(m_logger) {
                m_logger.AddToContext(symbol, "OrderBlockMet", "TRUE", true);
            }
        }
        else if(score.scores[i].primitiveName == "BOS" && 
                score.scores[i].normalizedScore >= req.minBOS) {
            strategyScore += 15;
            if(m_logger) {
                m_logger.AddToContext(symbol, "BOSMet", "TRUE", true);
            }
        }
        else if(score.scores[i].primitiveName == "MSS" && 
                score.scores[i].normalizedScore >= req.minMSS) {
            strategyScore += 15;
            if(m_logger) {
                m_logger.AddToContext(symbol, "MSSMet", "TRUE", true);
            }
        }
    }
    
    // Normalize to 0-100 scale
    double finalScore = (strategyScore / (20 + (15 * 5))) * 100;
    
    if(m_logger) {
        m_logger.AddDoubleContext(symbol, "RawStrategyScore", strategyScore, 2);
        m_logger.AddDoubleContext(symbol, "FinalStrategyScore", finalScore, 2);
        
        m_logger.KeepNotes(symbol, OBSERVE, "CalculateStrategyScore", 
            StringFormat("Strategy %s score: %.2f", strategy, finalScore), 
            false, false, 0.0);
    }
    
    return finalScore;
}

//+------------------------------------------------------------------+
//| Generate signal from scores                                      |
//+------------------------------------------------------------------+
STRUCTURE_SIGNAL MarketStructureEngine::GenerateSignalFromScores(MarketStructureScore &score)
{
    if(!m_initialized) {
        return SIGNAL_NONE;
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.StartContextWith(m_symbol, "GenerateSignalFromScores");
    }
    #endif
    
    // Check for low confidence
    if(score.totalConfidence < 60) {
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "SignalDecision", "NO_SIGNAL_LOW_CONFIDENCE", true);
            m_logger.KeepNotes(m_symbol, OBSERVE, "GenerateSignalFromScores", 
                StringFormat("No signal generated: Confidence too low (%.2f)", score.totalConfidence), 
                false, false, 0.0);
        }
        #endif
        return SIGNAL_NONE;
    }
    
    // Check for strongest primitive signals
    double strongestScore = 0;
    string strongestPrimitive = "";
    
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        if(score.scores[i].normalizedScore > strongestScore) {
            strongestScore = score.scores[i].normalizedScore;
            strongestPrimitive = score.scores[i].primitiveName;
        }
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.AddToContext(m_symbol, "StrongestPrimitive", strongestPrimitive, true);
        m_logger.AddDoubleContext(m_symbol, "StrongestScore", strongestScore, 2);
    }
    #endif
    
    // Generate signal based on strongest primitive
    STRUCTURE_SIGNAL signal = SIGNAL_NONE;
    
    if(strongestPrimitive == "BOS" && strongestScore > 70) {
        signal = SIGNAL_BOS_BUY; // Would need direction from BOS module
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "SignalType", "BOS_BUY", true);
        }
        #endif
    }
    else if(strongestPrimitive == "CHOCH" && strongestScore > 65) {
        signal = SIGNAL_CHOCH_BUY; // Would need direction from CHOCH module
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "SignalType", "CHOCH_BUY", true);
        }
        #endif
    }
    else if(strongestPrimitive == "MSS" && strongestScore > 70) {
        signal = SIGNAL_MS_SHIFT_BUY; // Would need direction from MSS module
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "SignalType", "MS_SHIFT_BUY", true);
        }
        #endif
    }
    else {
        #ifdef MARKET_STRUCTURE_DEBUG
        if(m_logger) {
            m_logger.AddToContext(m_symbol, "SignalType", "NONE", true);
        }
        #endif
    }
    
    #ifdef MARKET_STRUCTURE_DEBUG
    if(m_logger) {
        m_logger.KeepNotes(m_symbol, AUTHORIZE, "GenerateSignalFromScores", 
            StringFormat("Signal generated: %s from %s (score: %.2f)", 
                SignalToString(signal), strongestPrimitive, strongestScore), 
            false, false, 0.0);
    }
    #endif
    
    return signal;
}

//+------------------------------------------------------------------+
//| Generate trade decision                                          |
//+------------------------------------------------------------------+
string MarketStructureEngine::GenerateTradeDecision(MarketStructureScore &score)
{
    if(score.totalConfidence < 50) {
        return "HOLD - Low Confidence";
    }
    else if(score.totalConfidence >= 50 && score.totalConfidence < 70) {
        return (score.signal != SIGNAL_NONE) ? "CONSIDER ENTRY" : "HOLD - No Clear Signal";
    }
    else if(score.totalConfidence >= 70 && score.totalConfidence < 85) {
        return (score.signal != SIGNAL_NONE) ? "ENTRY VALID" : "HOLD - Wait for Signal";
    }
    else if(score.totalConfidence >= 85) {
        return (score.signal != SIGNAL_NONE) ? "STRONG ENTRY" : "HOLD - Excellent Conditions";
    }
    
    return "HOLD - Undefined";
}

//+------------------------------------------------------------------+
//| Update chart display with current score                          |
//+------------------------------------------------------------------+
void MarketStructureEngine::UpdateChartDisplay(string symbol, MarketStructureScore &score)
{
    DisplayImportantResults(symbol, score);
}

//+------------------------------------------------------------------+
//| Get overall confidence                                           |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetOverallConfidence(string symbol)
{
    if(!m_initialized) {
        return 0.0;
    }
    
    if(m_logger) {
        m_logger.StartContextWith(symbol, "GetOverallConfidence");
    }
    
    MarketStructureScore score = AnalyzeMarketStructure(symbol, m_timeframe);
    
    if(m_logger) {
        m_logger.AddDoubleContext(symbol, "OverallConfidence", score.totalConfidence, 2);
        m_logger.KeepNotes(symbol, OBSERVE, "GetOverallConfidence", 
            StringFormat("Overall confidence: %.2f", score.totalConfidence), 
            false, false, 0.0);
    }
    
    return score.totalConfidence;
}

//+------------------------------------------------------------------+
//| Get market bias                                                  |
//+------------------------------------------------------------------+
string MarketStructureEngine::GetMarketBias(string symbol)
{
    if(!m_initialized) {
        return STR_NEUTRAL;
    }
    
    MarketStructureScore score = AnalyzeMarketStructure(symbol, m_timeframe);
    
    // Log the bias
    if(m_logger) {
        m_logger.KeepNotes(symbol, OBSERVE, "GetMarketBias", 
            StringFormat("Market bias: %s", score.bias), 
            false, false, 0.0);
    }
    
    return score.bias;
}

//+------------------------------------------------------------------+
//| Get structure signal                                             |
//+------------------------------------------------------------------+
STRUCTURE_SIGNAL MarketStructureEngine::GetStructureSignal(string symbol)
{
    if(!m_initialized) {
        return SIGNAL_NONE;
    }
    
    MarketStructureScore score = AnalyzeMarketStructure(symbol, m_timeframe);
    
    // Log the signal
    if(m_logger) {
        m_logger.KeepNotes(symbol, OBSERVE, "GetStructureSignal", 
            StringFormat("Structure signal: %s", SignalToString(score.signal)), 
            false, false, 0.0);
    }
    
    return score.signal;
}

//+------------------------------------------------------------------+
//| Check if primitive is available                                  |
//+------------------------------------------------------------------+
bool MarketStructureEngine::IsPrimitiveAvailable(int index)
{
    return m_primitiveAvailability[index];
}

//+------------------------------------------------------------------+
//| Get adjusted weight for primitive                                |
//+------------------------------------------------------------------+
double MarketStructureEngine::GetAdjustedWeight(string primitive)
{
    const int totalPrimitives = 7;
    for(int i = 0; i < totalPrimitives; i++) {
        if(m_currentScore.scores[i].primitiveName == primitive) {
            return m_currentScore.scores[i].adjustedWeight;
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Log primitive scores in detail                                   |
//+------------------------------------------------------------------+
void MarketStructureEngine::LogPrimitiveScores(MarketStructureScore &score)
{
    if(!m_initialized || m_logger == NULL) {
        return;
    }
    
    m_logger.StartContextWith(m_symbol, "LogPrimitiveScores");
    
    // ================= PERFORMANCE OPTIMIZATION: Use StringFormat instead of concatenation =================
    string scoreSummary = StringFormat(
        "%s: %.2f (%.2f%%) | %s: %.2f (%.2f%%) | %s: %.2f (%.2f%%) | %s: %.2f (%.2f%%) | %s: %.2f (%.2f%%) | %s: %.2f (%.2f%%) | %s: %.2f (%.2f%%)",
        score.scores[0].primitiveName, score.scores[0].normalizedScore, score.scores[0].adjustedWeight,
        score.scores[1].primitiveName, score.scores[1].normalizedScore, score.scores[1].adjustedWeight,
        score.scores[2].primitiveName, score.scores[2].normalizedScore, score.scores[2].adjustedWeight,
        score.scores[3].primitiveName, score.scores[3].normalizedScore, score.scores[3].adjustedWeight,
        score.scores[4].primitiveName, score.scores[4].normalizedScore, score.scores[4].adjustedWeight,
        score.scores[5].primitiveName, score.scores[5].normalizedScore, score.scores[5].adjustedWeight,
        score.scores[6].primitiveName, score.scores[6].normalizedScore, score.scores[6].adjustedWeight
    );
    
    m_logger.AddToContext(m_symbol, "ScoreSummary", scoreSummary, true);
    m_logger.KeepNotes(m_symbol, AUDIT, "LogPrimitiveScores", 
        "Detailed primitive scores logged", 
        false, false, 0.0);
}

//+------------------------------------------------------------------+
//| Convert regime enum to string                                    |
//+------------------------------------------------------------------+
string MarketStructureEngine::RegimeToString(MARKET_REGIME regime)
{
    switch(regime) {
        case REGIME_TRENDING_BULLISH: return "TRENDING_BULLISH";
        case REGIME_TRENDING_BEARISH: return "TRENDING_BEARISH";
        case REGIME_RANGING: return "RANGING";
        case REGIME_BREAKOUT: return "BREAKOUT";
        case REGIME_HIGH_VOLATILITY: return "HIGH_VOLATILITY";
        case REGIME_LOW_VOLATILITY: return "LOW_VOLATILITY";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Convert signal enum to string                                    |
//+------------------------------------------------------------------+
string MarketStructureEngine::SignalToString(STRUCTURE_SIGNAL signal)
{
    switch(signal) {
        case SIGNAL_NONE: return "NONE";
        case SIGNAL_BOS_BUY: return "BOS_BUY";
        case SIGNAL_BOS_SELL: return "BOS_SELL";
        case SIGNAL_CHOCH_BUY: return "CHOCH_BUY";
        case SIGNAL_CHOCH_SELL: return "CHOCH_SELL";
        case SIGNAL_MS_SHIFT_BUY: return "MS_SHIFT_BUY";
        case SIGNAL_MS_SHIFT_SELL: return "MS_SHIFT_SELL";
        case SIGNAL_LIQUIDITY_GRAB_BUY: return "LIQUIDITY_GRAB_BUY";
        case SIGNAL_LIQUIDITY_GRAB_SELL: return "LIQUIDITY_GRAB_SELL";
        default: return "UNKNOWN_SIGNAL";
    }
}