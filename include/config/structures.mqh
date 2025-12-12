#include "enums.mqh"

// Trend health tracking - EXPANDED
struct TrendHealth
{
    string symbol;
    double trendStrength;
    double reversalRisk;
    string protectionLevel;
    string trendStatus;
    double multiTFSync;     // NEW: Multi-timeframe synchronization score
    double momentumScore;   // NEW: Momentum strength
    double volumeConf;      // NEW: Volume confirmation
};
TrendHealth trendHealth[];

// Position tracking
struct PositionData
{
    ulong ticket;
    datetime openTime;
    double openPrice;
    double initialSL;
    double currentATR;      // NEW: Store ATR at entry
};
PositionData positionTracker[];

// NEW: Trend momentum tracking
struct TrendMomentum
{
    string symbol;
    double acceleration;    // Rate of trend acceleration
    double consistency;     // How consistent is the trend
    datetime lastUpdate;
};
TrendMomentum trendMomentum[];


//+---------------------------------------------------+
//| POI                                               |
//+--------------------------------------------------+
struct POILevel {
    double price;
    string type;        // "RESISTANCE", "SUPPORT", "SWING_HIGH", "SWING_LOW", "LIQUIDITY_HIGH", "LIQUIDITY_LOW"
    string timeframe;   // "H1", "H4", "D1"
    datetime timestamp;
    bool isMajor;
    bool isBroken;
    int brokenSinceBar;
};
POILevel poiLevels[];



//+------------------------------------------------------------------+
//| 4. COMPLETE TRADE VALIDATION SYSTEM                             |
//+------------------------------------------------------------------+
struct TradeSignal {
    bool isValid;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    string reason;
    ENUM_TREND_STRENGTH trendStrength;
    double confidence;
};

//+------------------------------------------------------------------+
//| 5. Structure to store swing points                            |
//+------------------------------------------------------------------+

struct SwingPoint {
    datetime time;
    double price;
    double rsi;
    int type;           // 1 = High, -1 = Low
    int barIndex;       // Bar index from current
    int strength;       // Strength rating (1-3)
};

// Divergence structure
struct DivergenceSignal {
    bool exists;
    bool bullish;       // true = bullish divergence, false = bearish
    datetime latestTime;
    double priceLevel;
    double rsiLevel;
    int strength;       // 1-3 scale
    int confirmations;  // How many times confirmed
    double score;       // Divergence score (0-100)
    datetime firstDetected; // When first detected
    string type;        // "Regular" or "Hidden"
};

// Global arrays to store swing points
SwingPoint highSwingPoints[];
SwingPoint lowSwingPoints[];
DivergenceSignal currentDivergence;


//+------------------------------------------------------------------+
//| Divergence Execution Result Structure                           |
//+------------------------------------------------------------------+
struct DivExecResult {
    bool shouldReverse;     // Reverse trade direction
    bool shouldWarn;        // Warn but proceed
    bool shouldProceed;     // Divergence supports trade
    double divergenceScore; // Score of relevant divergence
    string divergenceType;  // "Regular" or "Hidden"
    int divergenceAge;      // Bars since divergence
    string message;         // Explanation
};

//+------------------------------------------------------------------+
//| Global variables for divergence override persistence            |
//+------------------------------------------------------------------+
struct DivergenceOverride
{
    bool    active;            // Is override active?
    bool    forceBuy;          // Force buy direction?
    bool    forceSell;         // Force sell direction?
    string  reason;            // Reason for override
    datetime activatedTime;    // When override started
    int      tradeCount;       // How many trades under this override
};

// ============ STRUCTURES ============

struct SymbolScore {
    string symbol;
    double score;
    int ranking;
    double liquidity;
    double volatility;
    long spread;
};

struct SymbolStatus {
    string symbol;
    bool isTradable;
    string reason;
    int errorCode;
    double score;
};

// ============ SYMBOL IDENTIFICATION ============

struct SignalScore
{
    int total;              // Total score out of 100
    double mtfAlignment;    // Multi-timeframe alignment score
    double momentum;        // Trend momentum score
    double rsiFilter;       // RSI filter score
    double stochastic;      // Stochastic filter score
    double macdConfirmation; // MACD confirmation score
    double volumeConfirmation; // Volume confirmation score
    double reversalPenalty; // Reversal penalty score
};

// ============ MARKET DATA STRUCTURE ============
// In structures.mqh, find the MarketData structure and add:
struct MarketData
{
    double sentiment;           // Raw sentiment (0-100)
    double buyScore;           // Pure buy score (0-100)
    double sellScore;          // Pure sell score (0-100)
    double trend;              // For logging only
    double pressure;           // For logging only
    int openTrades;            // Current open trades
    string currentDirection;   // Current trade direction
    string divergenceType;     // NEW: "BULLISH", "BEARISH", or "NONE"
    double divergenceScore;    // NEW: Divergence impact score
    double divergenceConfidence; // NEW: Confidence level (0-1)
};

// ============ STRUCTURES ============

struct BlockedStatus {
    bool isBlocked;
    string decision;
    string botThoughts;
};

struct TradingDecision {
    string decision;
    string botThoughts;
    string actionType;
    double confidence;
};

// ============ STRUCTURES ============

struct EngineMetrics {
    int totalAdjustments;
    int divergenceSignals;
    double avgDivergenceImpact;
    datetime lastCalculation;
};

// In your structures.mqh file (or wherever AdjustedMarketData is defined)
struct AdjustedMarketData
{
    // Existing members:
    double rawSentiment;
    double rawTrend;
    double rawPressure;
    double adjustedSentiment;
    double adjustedTrend;
    double adjustedPressure;
    double buyScore;
    double sellScore;
    string divergenceType;
    double divergenceFactor;
    string marketPhase;
    
    // ADD THIS NEW MEMBER:
    double divergenceScore;  // Raw divergence impact score (+/- points)
    
    // Constructor (if you have one):
    AdjustedMarketData()
    {
        rawSentiment = 0;
        rawTrend = 0;
        rawPressure = 0;
        adjustedSentiment = 0;
        adjustedTrend = 0;
        adjustedPressure = 0;
        buyScore = 0;
        sellScore = 0;
        divergenceType = "NONE";
        divergenceFactor = 0;
        marketPhase = "CONTINUATION";
        divergenceScore = 0;  // Initialize new member
    }
};

// NEW: Structure to hold MA alignment results
struct MAAlignmentScore
{
    double buyConfidence;    // 0-100: Confidence for BUY (based on bullish alignment)
    double sellConfidence;   // 0-100: Confidence for SELL (based on bearish alignment)
    double netBias;          // -100 to +100: Negative = bearish, Positive = bullish
    string alignment;        // "BULLISH", "BEARISH", "NEUTRAL", "MIXED"
    string warning;          // Warning message if any
    bool isCritical;         // True if critical condition detected
};


struct SignalRecord
{
    string symbol;
    string type;
    double strength;
    datetime timestamp;
};

SignalRecord signalHistory[100];  // Array of structs