// Flow of data organization (High-level to Low-level):
// 1. Configuration/Setup → 2. Market Analysis → 3. Signal Generation → 4. Risk Management → 5. Trade Execution → 6. Monitoring

#include "enums.mqh"

// ============ 1. CONFIGURATION & SETUP STRUCTURES ============
// Configuration objects that define system behavior and parameters

struct BaseConfig
{
    string configName;
    string version;
    datetime lastModified;
    bool isDefault;
    
    // Constructor
    BaseConfig(string name = "") : configName(name), version("1.0"),
                                 lastModified(0), isDefault(true) {}
    
    void SetDefaults() {}
    bool Validate() const { return true; }
    string ToJSON() const { return ""; }
    bool FromJSON(string json) { return false; }
};

struct TradingConfig : public BaseConfig
{
    // General trading
    string symbol;
    ENUM_TIMEFRAMES tradeTimeframe;
    bool allowMultiplePairs;
    bool allowHedging;
    int maxConcurrentTrades;
    int tradingStartHour;
    int tradingEndHour;
    bool useSessionFilter;
    
    // Risk management
    double maximumRiskPercent;
    double maximumDailyRisk;
    double maximumPositionRisk;
    double maximumPortfolioExposure;
    double stopLossATRMultiplier;
    double takeProfitRRRatio;
    double breakevenTriggerRR;
    
    // Signal filters
    double minimumConfidence;
    double minimumTrendStrength;
    double maximumReversalRisk;
    bool requireVolumeConfirmation;
    bool requireDivergence;
    double minimumMomentumThreshold;
    
    // Constructor
    TradingConfig() : BaseConfig("TradingConfig")
    {
        SetDefaults();
    }
    
    void SetDefaults()
    {
        symbol = "EURUSD";
        tradeTimeframe = PERIOD_H1;
        allowMultiplePairs = true;
        allowHedging = false;
        maxConcurrentTrades = 3;
        tradingStartHour = 0;
        tradingEndHour = 24;
        useSessionFilter = false;
        
        maximumRiskPercent = 2.0;
        maximumDailyRisk = 5.0;
        maximumPositionRisk = 5.0;
        maximumPortfolioExposure = 30.0;
        stopLossATRMultiplier = 2.0;
        takeProfitRRRatio = 2.0;
        breakevenTriggerRR = 1.0;
        
        minimumConfidence = 60.0;
        minimumTrendStrength = 50.0;
        maximumReversalRisk = 70.0;
        requireVolumeConfirmation = true;
        requireDivergence = false;
        minimumMomentumThreshold = 0.0;
        
        lastModified = TimeCurrent();
    }
    
    bool Validate() const
    {
        if(maximumRiskPercent <= 0 || maximumRiskPercent > 10)
            return false;
        if(maximumDailyRisk <= 0 || maximumDailyRisk > 20)
            return false;
        if(maxConcurrentTrades <= 0 || maxConcurrentTrades > 20)
            return false;
        if(takeProfitRRRatio < 1.0)
            return false;
            
        return true;
    }
    
    string ToJSON() const
    {
        string json = "{";
        json += StringFormat("\"configName\":\"%s\",", configName);
        json += StringFormat("\"version\":\"%s\",", version);
        json += StringFormat("\"symbol\":\"%s\",", symbol);
        json += StringFormat("\"tradeTimeframe\":%d,", tradeTimeframe);
        json += StringFormat("\"maxConcurrentTrades\":%d,", maxConcurrentTrades);
        json += StringFormat("\"maximumRiskPercent\":%.2f,", maximumRiskPercent);
        json += StringFormat("\"maximumDailyRisk\":%.2f,", maximumDailyRisk);
        json += StringFormat("\"stopLossATRMultiplier\":%.2f,", stopLossATRMultiplier);
        json += StringFormat("\"takeProfitRRRatio\":%.2f", takeProfitRRRatio);
        json += "}";
        return json;
    }
};

struct RiskConfig : public BaseConfig
{
    // Drawdown limits
    double maxDailyDrawdownPercent;
    double maxTotalDrawdownPercent;
    double warningDrawdownPercent;
    double criticalDrawdownPercent;
    
    // Position sizing
    ENUM_POSITION_SIZING_METHOD sizingMethod;
    double fixedFractionalPercent;
    double kellyFractionPercent;
    double minimumPositionSize;
    double maximumPositionSize;
    
    // Exposure limits
    double maxSymbolExposurePercent;
    double maxAssetClassExposurePercent;
    double maxDirectionalExposurePercent;
    double maxCorrelatedExposurePercent;
    
    // Cooldown rules
    int cooldownAfterLossMinutes;
    int cooldownAfterBigWinMinutes;
    int cooldownAfterConsecutiveLosses;
    int maxTradesPerDay;
    
    // Constructor
    RiskConfig() : BaseConfig("RiskConfig")
    {
        SetDefaults();
    }
    
    void SetDefaults()
    {
        maxDailyDrawdownPercent = 5.0;
        maxTotalDrawdownPercent = 20.0;
        warningDrawdownPercent = 10.0;
        criticalDrawdownPercent = 15.0;
        
        sizingMethod = PS_FIXED_FRACTIONAL;
        fixedFractionalPercent = 2.0;
        kellyFractionPercent = 25.0;
        minimumPositionSize = 0.01;
        maximumPositionSize = 10.0;
        
        maxSymbolExposurePercent = 10.0;
        maxAssetClassExposurePercent = 40.0;
        maxDirectionalExposurePercent = 50.0;
        maxCorrelatedExposurePercent = 20.0;
        
        cooldownAfterLossMinutes = 30;
        cooldownAfterBigWinMinutes = 15;
        cooldownAfterConsecutiveLosses = 3;
        maxTradesPerDay = 20;
        
        lastModified = TimeCurrent();
    }
    
    bool Validate() const
    {
        if(maxDailyDrawdownPercent <= 0 || maxDailyDrawdownPercent > 20)
            return false;
        if(maxTotalDrawdownPercent <= maxDailyDrawdownPercent)
            return false;
        if(fixedFractionalPercent <= 0 || fixedFractionalPercent > 10)
            return false;
        if(maxTradesPerDay <= 0 || maxTradesPerDay > 100)
            return false;
            
        return true;
    }
};

struct AnalysisConfig : public BaseConfig
{
    // Timeframe settings
    ENUM_TIMEFRAMES primaryTimeframe;
    ENUM_TIMEFRAMES confirmationTimeframe;
    bool useMultiTimeframeAnalysis;
    int multiTimeframeCount;
    ENUM_TIMEFRAMES multiTimeframes[5];
    
    // Indicator settings
    int rsiPeriod;
    int stochasticPeriod;
    int macdFast;
    int macdSlow;
    int macdSignal;
    int atrPeriod;
    int maFastPeriod;
    int maSlowPeriod;
    int maTrendPeriod;
    
    // Divergence settings
    bool enableDivergenceDetection;
    int divergenceLookbackBars;
    double divergenceMinimumStrength;
    bool requireHiddenDivergence;
    
    // POI settings
    bool enablePOIDetection;
    double poiSwingStrength;
    int poiLookbackBars;
    bool markMajorPOIOnly;
    
    // Constructor
    AnalysisConfig() : BaseConfig("AnalysisConfig")
    {
        SetDefaults();
    }
    
    void SetDefaults()
    {
        primaryTimeframe = PERIOD_H1;
        confirmationTimeframe = PERIOD_H4;
        useMultiTimeframeAnalysis = true;
        multiTimeframeCount = 3;
        multiTimeframes[0] = PERIOD_M15;
        multiTimeframes[1] = PERIOD_H1;
        multiTimeframes[2] = PERIOD_H4;
        
        rsiPeriod = 14;
        stochasticPeriod = 14;
        macdFast = 12;
        macdSlow = 26;
        macdSignal = 9;
        atrPeriod = 14;
        maFastPeriod = 9;
        maSlowPeriod = 21;
        maTrendPeriod = 50;
        
        enableDivergenceDetection = true;
        divergenceLookbackBars = 50;
        divergenceMinimumStrength = 0.6;
        requireHiddenDivergence = false;
        
        enablePOIDetection = true;
        poiSwingStrength = 1.5;
        poiLookbackBars = 100;
        markMajorPOIOnly = false;
        
        lastModified = TimeCurrent();
    }
    
    bool Validate() const
    {
        if(rsiPeriod <= 0 || rsiPeriod > 100)
            return false;
        if(atrPeriod <= 0 || atrPeriod > 100)
            return false;
        if(divergenceLookbackBars <= 0 || divergenceLookbackBars > 200)
            return false;
            
        return true;
    }
};

struct SystemConfig : public BaseConfig
{
    // Logging
    bool enableLogging;
    int logLevel;  // 0=Error, 1=Warning, 2=Info, 3=Debug
    string logFilePath;
    bool logToFile;
    bool logToTerminal;
    
    // Alerts
    bool enableEmailAlerts;
    string emailRecipient;
    bool enablePushNotifications;
    string pushToken;
    
    // Performance
    int healthCheckInterval;      // Seconds
    int metricsUpdateInterval;    // Seconds
    int positionUpdateInterval;   // Seconds
    bool enablePerformanceMetrics;
    
    // Safety
    bool enableEmergencyStop;
    double emergencyStopDrawdown;
    int maxRuntimeHours;
    bool autoRestartOnError;
    
    // Constructor
    SystemConfig() : BaseConfig("SystemConfig")
    {
        SetDefaults();
    }
    
    void SetDefaults()
    {
        enableLogging = true;
        logLevel = 2;
        logFilePath = "Logs/";
        logToFile = true;
        logToTerminal = true;
        
        enableEmailAlerts = false;
        emailRecipient = "";
        enablePushNotifications = false;
        pushToken = "";
        
        healthCheckInterval = 60;
        metricsUpdateInterval = 5;
        positionUpdateInterval = 1;
        enablePerformanceMetrics = true;
        
        enableEmergencyStop = true;
        emergencyStopDrawdown = 25.0;
        maxRuntimeHours = 24;
        autoRestartOnError = false;
        
        lastModified = TimeCurrent();
    }
    
    bool Validate() const
    {
        if(logLevel < 0 || logLevel > 3)
            return false;
        if(healthCheckInterval <= 0 || healthCheckInterval > 3600)
            return false;
        if(emergencyStopDrawdown <= 0 || emergencyStopDrawdown > 50)
            return false;
            
        return true;
    }
};

// ============ 2. MARKET DATA & SYMBOL STRUCTURES ============
// Market information and symbol data collection

// ============ SYMBOL INFO STRUCTURE ============
struct SymbolInfo
{
    // Basic identification
    string symbol;
    string name;
    ENUM_ASSET_CLASS assetClass;
    ENUM_SYMBOL_STATUS status;
    
    // Trading properties
    double tickSize;
    double lotSize;
    double contractSize;
    double pointValue;
    double pipValue;
    
    // Limits
    double minVolume;
    double maxVolume;
    double volumeStep;
    double marginRequired;
    double marginMaintenance;
    double maxSpreadAllowed;
    
    // Current market data
    double bid;
    double ask;
    double lastPrice;
    double spread;
    double dailyHigh;
    double dailyLow;
    double dailyRange;
    double avgSpread;
    double volatility;
    datetime lastUpdate;
    
    // Risk parameters
    int positionCount;
    double totalExposure;
    double maxExposure;
    int maxPositions;
    double correlationFactor;
    
    // Performance tracking
    int totalTrades;
    int profitableTrades;
    double totalProfit;
    double winRate;
    int consecutiveWins;
    int consecutiveLosses;
    datetime lastTradeTime;
    
    // Behavior profile
    string behavior;           // "TRENDY", "RANGY", "VOLATILE"
    int tradesTaken;
    int tradesSkipped;
    bool lastTradeTaken;
    bool lastTradeProfitable;
    string lastTradeSummary;
    
    // Cooldown/blocking
    bool inCooldown;
    datetime cooldownUntil;
    string cooldownReason;
    
    // Allocation
    double targetWeight;
    double currentWeight;
    double allocatedCapital;
    double riskBudget;
    int priority;              // 1-10
    
    // Constructor
    SymbolInfo() : symbol(""), name(""), assetClass(ASSET_FOREX),
                  status(SYMBOL_DISABLED), tickSize(0.0), lotSize(0.0),
                  contractSize(0.0), pointValue(0.0), pipValue(0.0),
                  minVolume(0.0), maxVolume(0.0), volumeStep(0.0),
                  marginRequired(0.0), marginMaintenance(0.0),
                  maxSpreadAllowed(0.0), bid(0.0), ask(0.0),
                  lastPrice(0.0), spread(0.0), dailyHigh(0.0),
                  dailyLow(0.0), dailyRange(0.0), avgSpread(0.0),
                  volatility(0.0), lastUpdate(0), positionCount(0),
                  totalExposure(0.0), maxExposure(10.0), maxPositions(3),
                  correlationFactor(1.0), totalTrades(0), profitableTrades(0),
                  totalProfit(0.0), winRate(0.0), consecutiveWins(0),
                  consecutiveLosses(0), lastTradeTime(0), behavior(""),
                  tradesTaken(0), tradesSkipped(0), lastTradeTaken(false),
                  lastTradeProfitable(false), lastTradeSummary(""),
                  inCooldown(false), cooldownUntil(0), cooldownReason(""),
                  targetWeight(0.0), currentWeight(0.0), allocatedCapital(0.0),
                  riskBudget(0.0), priority(5) {}
    
    bool Initialize(string sym)
    {
        symbol = sym;
        
        if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
        {
            status = SYMBOL_ERROR;
            return false;
        }
        
        name = SymbolInfoString(sym, SYMBOL_DESCRIPTION);
        tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
        lotSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
        contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
        
        minVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
        maxVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
        volumeStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
        
        marginRequired = SymbolInfoDouble(sym, SYMBOL_MARGIN_INITIAL);
        marginMaintenance = SymbolInfoDouble(sym, SYMBOL_MARGIN_MAINTENANCE);
        
        double point = SymbolInfoDouble(sym, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
        pointValue = tickValue * point;
        pipValue = pointValue * 10.0;
        
        string symLower = sym;
        StringToLower(symLower);
        if(StringFind(symLower, "xau") >= 0 || StringFind(symLower, "xag") >= 0)
            assetClass = ASSET_METALS;
        else if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0)
            assetClass = ASSET_CRYPTO;
        else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "SPX") >= 0)
            assetClass = ASSET_INDICES;
        else
            assetClass = ASSET_FOREX;
        
        status = SYMBOL_ENABLED;
        lastUpdate = TimeCurrent();
        return true;
    }
    
    void UpdateMarketData()
    {
        if(symbol == "") return;
        
        bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        lastPrice = (bid + ask) / 2.0;
        spread = (ask - bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, PERIOD_D1, 0, 1, rates) == 1)
        {
            dailyHigh = rates[0].high;
            dailyLow = rates[0].low;
            dailyRange = dailyHigh - dailyLow;
        }
        
        lastUpdate = TimeCurrent();
    }
    
    bool CanTrade() const
    {
        if(status != SYMBOL_ENABLED) return false;
        if(inCooldown && TimeCurrent() < cooldownUntil) return false;
        if(spread > maxSpreadAllowed && maxSpreadAllowed > 0) return false;
        if(positionCount >= maxPositions) return false;
        
        return true;
    }
    
    bool CanAddPosition(double newExposure = 0.0) const
    {
        if(!CanTrade()) return false;
        if((totalExposure + newExposure) > maxExposure) return false;
        
        return true;
    }
    
    void AddExposure(double exposure)
    {
        positionCount++;
        totalExposure += exposure;
        currentWeight = (totalExposure / maxExposure) * 100.0;
    }
    
    void RemoveExposure(double exposure)
    {
        positionCount = MathMax(0, positionCount - 1);
        totalExposure = MathMax(0.0, totalExposure - exposure);
        currentWeight = (totalExposure / maxExposure) * 100.0;
    }
    
    void UpdateTradeResult(bool isWin, double profit)
    {
        totalTrades++;
        
        if(isWin)
        {
            profitableTrades++;
            consecutiveWins++;
            consecutiveLosses = 0;
            totalProfit += profit;
        }
        else
        {
            consecutiveLosses++;
            consecutiveWins = 0;
        }
        
        winRate = (totalTrades > 0) ? (double)profitableTrades / totalTrades * 100.0 : 0.0;
        lastTradeTime = TimeCurrent();
        lastTradeTaken = true;
        lastTradeProfitable = isWin;
        
        if(consecutiveLosses >= 3)
        {
            ApplyCooldown(60, "3 consecutive losses");
        }
    }
    
    void ApplyCooldown(int minutes, string reason = "")
    {
        inCooldown = true;
        cooldownUntil = TimeCurrent() + (minutes * 60);
        cooldownReason = reason;
    }
    
    string GetCooldownStatus() const
    {
        if(!inCooldown) return "ACTIVE";
        
        if(TimeCurrent() >= cooldownUntil)
        {
            return "COOLDOWN_EXPIRED";
        }
        
        int remaining = int((cooldownUntil - TimeCurrent()) / 60);
        return StringFormat("COOLDOWN (%d min): %s", remaining, cooldownReason);
    }
    
    bool ClearExpiredCooldown()
    {
        if(inCooldown && TimeCurrent() >= cooldownUntil)
        {
            inCooldown = false;
            cooldownReason = "";
            return true;
        }
        return false;
    }
    
    double GetExposurePercent() const
    {
        return maxExposure > 0 ? (totalExposure / maxExposure) * 100.0 : 0.0;
    }
    
    string GetSummary() const
    {
        string summary = StringFormat("%s [%s]", symbol, name);
        summary += StringFormat("\nStatus: %s | Exposure: %.1f%%/%0.f%%", 
                              GetCooldownStatus(), GetExposurePercent(), maxExposure);
        summary += StringFormat("\nPrice: %.5f | Spread: %.1f pips", lastPrice, spread);
        summary += StringFormat("\nTrades: %d | Win Rate: %.1f%% | Profit: $%.2f",
                              totalTrades, winRate, totalProfit);
        
        return summary;
    }
};

// ============ MARKET DATA STRUCTURE ============
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

// ============ SYMBOL IDENTIFICATION ============
struct SymbolScore {
    string symbol;
    double score;
    int ranking;
    double liquidity;
    double volatility;
    long spread;
};

// ============ SYMBOL IDENTIFICATION ============
struct SymbolStatus {
    string symbol;
    bool isTradable;
    string reason;
    int errorCode;
    double score;
};

// ============ 3. TECHNICAL ANALYSIS STRUCTURES ============
// Structures for market analysis, pattern detection, and technical indicators

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

// Trend momentum tracking
struct TrendMomentum
{
    string symbol;
    double acceleration;    // Rate of trend acceleration
    double consistency;     // How consistent is the trend
    datetime lastUpdate;
};

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

// Market structure analysis
struct MarketStructure
{
    string symbol;
    ENUM_MARKET_PHASE phase;
    double rangeHigh;
    double rangeLow;
    bool isRanging;
    double rangeWidth;      // Percentage
    int rangeBars;          // Bars in current range
    string bias;            // "BULLISH", "BEARISH", "NEUTRAL"
    datetime phaseStart;
    
    void Initialize(string sym = "")
    {
        if(sym != "") symbol = sym;
        phase = PHASE_RANGE;
        rangeHigh = 0.0;
        rangeLow = 0.0;
        isRanging = true;
        rangeWidth = 0.0;
        rangeBars = 0;
        bias = "NEUTRAL";
        phaseStart = TimeCurrent();
    }
    
    bool IsBreakout(double price) const
    {
        if(!isRanging) return false;
        return price > rangeHigh * 1.001 || price < rangeLow * 0.999;
    }
    
    void UpdateRange(double high, double low, int bars)
    {
        rangeHigh = high;
        rangeLow = low;
        rangeBars = bars;
        rangeWidth = ((high - low) / low) * 100.0;
        
        isRanging = rangeWidth < 1.0 && bars > 10;
        
        bias = "NEUTRAL";
    }
    
    double GetRangeMidpoint() const { return (rangeHigh + rangeLow) / 2; }
    
    string GetDescription() const
    {
        string phaseStr;
        switch(phase)
        {
            case PHASE_ACCUMULATION: phaseStr = "ACCUMULATION"; break;
            case PHASE_MARKUP: phaseStr = "MARKUP"; break;
            case PHASE_DISTRIBUTION: phaseStr = "DISTRIBUTION"; break;
            case PHASE_MARKDOWN: phaseStr = "MARKDOWN"; break;
            case PHASE_RANGE: phaseStr = "RANGE"; break;
        }
        
        return StringFormat("%s: %s | Range: %.5f-%.5f (%.2f%%) | Bars: %d",
                          symbol, phaseStr, rangeLow, rangeHigh, rangeWidth, rangeBars);
    }
};

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
DivergenceOverride divergenceOverride;

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

// ============ 4. SIGNAL GENERATION STRUCTURES ============
// Trade signals, scoring, and decision-making structures

//+------------------------------------------------------------------+
//| 4. COMPLETE TRADE VALIDATION SYSTEM                             |
//+------------------------------------------------------------------+
struct TradeSignal {
    bool isValid;
    bool isExpired;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    string reason;
    ENUM_TREND_STRENGTH trendStrength;
    double confidence;
};

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

struct SignalRecord
{
    string symbol;
    string type;
    double strength;
    datetime timestamp;
};

// ============ 5. TRADE EXECUTION STRUCTURES ============
// Structures related to order placement, position management, and execution

//+---------------------------------------------------+
//| TRADE DECISION STRUCTURE                           |
//+--------------------------------------------------+
// struct TradeDecision
// {
//     string symbol;
//     double capital;
//     double lotSize;
//     ENUM_POSITION_TYPE direction;
//     double riskPercent;
//     string reason;
//     bool approved;
//     double confidence;
// };

//+---------------------------------------------------+
//| Position tracking                               |
//+--------------------------------------------------+
struct PositionData
{
    ulong ticket;
    string symbol;
    double openPrice;
    double initialSL;
    double stopLoss;
    double takeProfit;
    double volume;
    datetime openTime;
    ENUM_POSITION_TYPE type;
    double currentProfit;
    double peakProfit;
    bool breakevenSet;
    bool partialClosed;
    double currentATR;
};

//+------------------------------------------------------------------+
// Structure for trading opportunity                                 |
//+------------------------------------------------------------------+
struct TradingOpportunity
{
    string symbol;
    double lotSize;
    ENUM_POSITION_TYPE direction;
    double stopLoss;
    double takeProfit;
    string reason;
    bool approved;
    double confidence;
};

//+---------------------------------------------------+
// MQL5 Trade Data                                   |
//+--------------------------------------------------+
struct MyTradeData
{
    long ticket;
    string symbol;
    double entryPrice;
    double exitPrice;
    double profit;
    datetime entryTime;
    datetime exitTime;
    ENUM_POSITION_TYPE direction;
    double volume;
    string comment;
    double riskAmount;
    double rewardAmount;
    double riskRewardRatio;
};

struct MyTradeTransaction
{
    // Copy MQL fields
    long deal;
    long order;
    string symbol;
    double price;
    double volume;
    
    // Your custom fields
    double profit;                    // MQL doesn't provide this
    double calculatedRisk;            // Your risk calculation
    string strategyName;              // Which strategy made this trade
    double confidenceScore;           // Your confidence metric
    bool isManualTrade;               // Manual vs automated
    string tradePlanId;               // Link to trade plan
    double positionSizePercent;       // % of portfolio
};

// ============ 6. RISK & PORTFOLIO MANAGEMENT STRUCTURES ============
// Risk metrics, portfolio allocation, and position sizing

// ============ RISK METRICS STRUCTURE ============
struct RiskMetrics
{
    // Daily Performance
    double dailyPnL;
    double dailyMaxLoss;
    int tradesToday;
    int winsToday;
    int lossesToday;
    
    // Period Performance
    double weeklyPnL;
    double monthlyPnL;
    double quarterlyPnL;
    double yearlyPnL;
    
    // Core Metrics
    double winRate;
    double expectancy;
    double avgRiskReward;
    double profitFactor;
    
    // Drawdown
    double maxDrawdown;
    double currentDrawdown;
    double recoveryFactor;
    
    // Totals
    int totalTrades;
    int totalWins;
    int totalLosses;
    double totalProfit;
    double totalLoss;
    
    // Portfolio Metrics
    double totalCapital;
    double allocatedCapital;
    double availableCapital;
    double portfolioReturn;
    double portfolioVolatility;
    double sharpeRatio;
    double sortinoRatio;
    
    // Account Health
    double accountEquity;
    double accountBalance;
    double accountMargin;
    double freeMarginPercent;
    string accountStatus;
    
    // System Metrics
    int totalAdjustments;
    int divergenceSignals;
    double avgDivergenceImpact;
    datetime lastCalculation;
    
    // Timestamps
    datetime sessionStart;
    datetime lastTradeTime;
    datetime metricsTime;
    
    RiskMetrics() : dailyPnL(0.0), dailyMaxLoss(0.0), tradesToday(0),
                   winsToday(0), lossesToday(0), weeklyPnL(0.0),
                   monthlyPnL(0.0), quarterlyPnL(0.0), yearlyPnL(0.0),
                   winRate(0.0), expectancy(0.0), avgRiskReward(0.0),
                   profitFactor(0.0), maxDrawdown(0.0), currentDrawdown(0.0),
                   recoveryFactor(0.0), totalTrades(0), totalWins(0),
                   totalLosses(0), totalProfit(0.0), totalLoss(0.0),
                   totalCapital(0.0), allocatedCapital(0.0),
                   availableCapital(0.0), portfolioReturn(0.0),
                   portfolioVolatility(0.0), sharpeRatio(0.0),
                   sortinoRatio(0.0), accountEquity(0.0),
                   accountBalance(0.0), accountMargin(0.0),
                   freeMarginPercent(0.0), accountStatus(""),
                   totalAdjustments(0), divergenceSignals(0),
                   avgDivergenceImpact(0.0), lastCalculation(0),
                   sessionStart(0), lastTradeTime(0), metricsTime(0) {}
    
    void Initialize(double startingBalance = 0.0)
    {
        if(startingBalance == 0.0)
            startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            
        totalCapital = startingBalance;
        accountBalance = startingBalance;
        accountEquity = startingBalance;
        sessionStart = TimeCurrent();
        metricsTime = TimeCurrent();
        
        ResetDaily();
        ResetPeriodic();
    }
    
    void ResetDaily()
    {
        dailyPnL = 0.0;
        dailyMaxLoss = 0.0;
        tradesToday = 0;
        winsToday = 0;
        lossesToday = 0;
        currentDrawdown = 0.0;
    }
    
    void ResetPeriodic()
    {
        weeklyPnL = 0.0;
        monthlyPnL = 0.0;
    }
    
    void UpdateAfterTrade(bool win, double profit, double riskAmount, double equity)
    {
        totalTrades++;
        tradesToday++;
        
        if(win)
        {
            totalWins++;
            winsToday++;
            totalProfit += profit;
            dailyPnL += profit;
        }
        else
        {
            totalLosses++;
            lossesToday++;
            totalLoss += MathAbs(profit);
            dailyPnL -= MathAbs(profit);
            
            if(MathAbs(dailyPnL) > dailyMaxLoss)
                dailyMaxLoss = MathAbs(dailyPnL);
        }
        
        accountEquity = equity;
        
        UpdateDerivedMetrics();
        metricsTime = TimeCurrent();
        lastTradeTime = metricsTime;
    }
    
    void UpdateDrawdown(double equity, double peakEquity)
    {
        if(equity < peakEquity)
        {
            currentDrawdown = ((peakEquity - equity) / peakEquity) * 100.0;
            
            if(currentDrawdown > maxDrawdown)
                maxDrawdown = currentDrawdown;
        }
        else
        {
            currentDrawdown = 0.0;
        }
        
        if(maxDrawdown > 0)
            recoveryFactor = totalProfit / maxDrawdown;
    }
    
    void UpdateDerivedMetrics()
    {
        if(totalTrades > 0)
            winRate = (double)totalWins / totalTrades * 100.0;
        
        if(totalLoss > 0)
            profitFactor = totalProfit / totalLoss;
        
        if(totalTrades > 0)
        {
            double avgWin = (totalWins > 0) ? totalProfit / totalWins : 0;
            double avgLoss = (totalLosses > 0) ? totalLoss / totalLosses : 0;
            double winProbability = winRate / 100.0;
            
            expectancy = (winProbability * avgWin) - ((1 - winProbability) * avgLoss);
        }
    }
    
    ENUM_RISK_LEVEL GetRiskLevel() const
    {
        double dailyLossPercent = (dailyPnL < 0 ? MathAbs(dailyPnL) / totalCapital : 0) * 100.0;
        
        if(dailyLossPercent >= 5.0 || currentDrawdown >= 15.0)
            return RISK_CRITICAL;
        else if(dailyLossPercent >= 3.0 || currentDrawdown >= 10.0)
            return RISK_HIGH;
        else if(dailyLossPercent >= 1.5 || currentDrawdown >= 5.0)
            return RISK_MODERATE;
        else if(dailyLossPercent >= 0.5 || currentDrawdown >= 2.0)
            return RISK_LOW;
        else
            return RISK_OPTIMAL;
    }
    
    ENUM_ACCOUNT_HEALTH GetAccountHealth() const
    {
        if(freeMarginPercent < 10.0 || currentDrawdown >= 15.0)
            return HEALTH_CRITICAL;
        else if(freeMarginPercent < 20.0 || currentDrawdown >= 10.0)
            return HEALTH_WARNING;
        else if(freeMarginPercent < 40.0 || currentDrawdown >= 5.0)
            return HEALTH_GOOD;
        else
            return HEALTH_EXCELLENT;
    }
    
    bool IsDailyLossLimitExceeded(double limitPercent = 5.0) const
    {
        double dailyLossPercent = (dailyPnL < 0 ? MathAbs(dailyPnL) / totalCapital : 0) * 100.0;
        return dailyLossPercent >= limitPercent;
    }
    
    string GetDailySummary() const
    {
        return StringFormat("Daily P&L: $%.2f (%.2f%%) | Trades: %d | Win Rate: %.1f%%",
                          dailyPnL, (dailyPnL/totalCapital)*100, tradesToday, 
                          (tradesToday > 0 ? (double)winsToday/tradesToday*100 : 0));
    }
    
    string GetPerformanceSummary() const
    {
        return StringFormat("Total Trades: %d | Win Rate: %.1f%% | PF: %.2f | Expectancy: $%.2f",
                          totalTrades, winRate, profitFactor, expectancy);
    }
    
    string GetRiskSummary() const
    {
        ENUM_RISK_LEVEL riskLevel = GetRiskLevel();
        string riskStr;
        switch(riskLevel)
        {
            case RISK_CRITICAL: riskStr = "CRITICAL"; break;
            case RISK_HIGH: riskStr = "HIGH"; break;
            case RISK_MODERATE: riskStr = "MODERATE"; break;
            case RISK_LOW: riskStr = "LOW"; break;
            case RISK_OPTIMAL: riskStr = "OPTIMAL"; break;
        }
        
        return StringFormat("Risk Level: %s | Drawdown: %.2f%% (Max: %.2f%%) | Margin Free: %.1f%%",
                          riskStr, currentDrawdown, maxDrawdown, freeMarginPercent);
    }
    
    void PrintFullReport() const
    {
        Print("\n═══════════════════════════════════════");
        Print("          RISK METRICS REPORT");
        Print("═══════════════════════════════════════");
        Print("Daily Summary:");
        Print("  " + GetDailySummary());
        Print("\nPerformance Metrics:");
        Print("  " + GetPerformanceSummary());
        Print("\nRisk Assessment:");
        Print("  " + GetRiskSummary());
        Print("═══════════════════════════════════════\n");
    }
};

struct PortfolioMetrics
{
    double totalCapital;        // Total portfolio capital
    double allocatedCapital;    // Capital currently allocated
    double availableCapital;    // Available capital for new positions
    double portfolioReturn;     // Portfolio total return
    double portfolioVolatility; // Portfolio volatility
    double sharpeRatio;         // Portfolio Sharpe ratio
    double sortinoRatio;        // Portfolio Sortino ratio
    double maxDrawdown;         // Maximum drawdown
    double currentDrawdown;     // Current drawdown
    double profitFactor;        // Profit factor
    double recoveryFactor;      // Recovery factor
    double correlationMatrix[]; // Correlation matrix
    double assetClassExposure[7]; // Exposure per asset class
    double correlationMatrixAverage;
};

// ============ 7. ACCOUNT & MONITORING STRUCTURES ============
// Account health, system metrics, and performance tracking

struct HealthReport
{
    string status;
    int uptime;
    int ticks;
    int errors;
    int warnings;
    string lastError;
    double cpuUsage;
    double memoryUsage;
    double diskUsage;
    datetime timestamp;
    double accountEquity;
    double accountBalance;
    double accountMargin;
    double freeMarginPercent;
    double currentDrawdown;
    
    HealthReport() :
        status(""),
        uptime(0),
        ticks(0),
        errors(0),
        warnings(0),
        lastError(""),
        cpuUsage(0.0),
        memoryUsage(0.0),
        diskUsage(0.0),
        timestamp(0),
        accountEquity(0.0),
        accountBalance(0.0),
        accountMargin(0.0),
        freeMarginPercent(0.0),
        currentDrawdown(0.0)
    {
    }
};

struct EngineMetrics {
    int totalAdjustments;
    int divergenceSignals;
    double avgDivergenceImpact;
    datetime lastCalculation;
};

// ============ 8. COMPREHENSIVE STRUCTURES ============
// Integrated structures that combine multiple aspects of the trading system

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
        divergenceScore = 0;
    }
};

// ============ TRADE DECISION STRUCTURE ============
struct TradeDecision
{
    // Decision identification
    string decisionId;
    TradeSignal signal;
    datetime decisionTime;
    
    // Risk-adjusted parameters
    double approvedLotSize;
    double approvedRiskPercent;
    double maxLossAmount;
    double expectedProfit;
    
    // Account context at decision time
    double accountBalance;
    double accountEquity;
    double freeMargin;
    int openPositions;
    
    // Approval chain
    bool isApproved;
    string approver;           // "RISK_MANAGER", "STRATEGY", "MANUAL_OVERRIDE"
    string approvalNotes;
    datetime approvalTime;
    
    // Execution status
    bool isExecuted;
    ulong orderTicket;
    datetime executionTime;
    
    TradeDecision() : decisionId(""), decisionTime(0),
                     approvedLotSize(0.0), approvedRiskPercent(0.0),
                     maxLossAmount(0.0), expectedProfit(0.0),
                     accountBalance(0.0), accountEquity(0.0),
                     freeMargin(0.0), openPositions(0),
                     isApproved(false), approver(""), approvalNotes(""),
                     approvalTime(0), isExecuted(false),
                     orderTicket(0), executionTime(0) {}
    
    void Reject(string reason)
    {
        isApproved = false;
        approver = "RISK_MANAGER";
        approvalNotes = "REJECTED: " + reason;
        approvalTime = TimeCurrent();
    }
    
    double GetRiskAmount() const
    {
        return maxLossAmount;
    }
    
    double GetRewardAmount() const
    {
        return expectedProfit;
    }
    
    string GetStatus() const
    {
        if(!isApproved) return "REJECTED";
        if(isExecuted) return "EXECUTED";
        return "APPROVED_PENDING";
    }
    
    string GetDecisionSummary() const
    {
        string summary = StringFormat("Decision: %s", decisionId);
        summary += StringFormat("\nStatus: %s | Approved: %s", 
                              GetStatus(), isApproved ? "Yes" : "No");
        
        if(isApproved)
        {
            summary += StringFormat("\nLot Size: %.3f | Risk: %.2f%% ($%.2f)", 
                                  approvedLotSize, approvedRiskPercent, maxLossAmount);
            summary += StringFormat("\nExpected Profit: $%.2f", expectedProfit);
        }
        
        if(approvalNotes != "")
            summary += "\nNotes: " + approvalNotes;
            
        return summary;
    }
};

// ============ CORE ANALYSIS STRUCTURES ============
// Pure technical analysis, NO risk or account data
struct AnalysisContext
{
    // Basic identification
    string symbol;
    datetime analysisTime;
    ENUM_TIMEFRAMES timeframe;
    
    // Technical analysis data
    MarketStructure marketStructure;
    TrendHealth trendHealth;
    TrendMomentum trendMomentum;
    DivergenceSignal divergence;
    
    // POI and swing points
    POILevel poiLevels[20];
    int poiCount;
    SwingPoint swingHighs[10];
    SwingPoint swingLows[10];
    int swingCount;
    
    // Current price data
    double currentPrice;
    double currentBid;
    double currentAsk;
    double currentSpread;
    
    // Technical indicators (simplified)
    double rsiValue;
    double macdValue;
    double stochValue;
    double atrValue;
    
    // Analysis results
    string bias;                    // "BULLISH", "BEARISH", "NEUTRAL"
    double confidence;              // 0-100
    bool hasSignal;
    string signalType;              // "BREAKOUT", "REVERSAL", "CONTINUATION"
    
    AnalysisContext(string sym = "", ENUM_TIMEFRAMES tf = PERIOD_H1) : 
                  symbol(sym), analysisTime(0), timeframe(tf),
                  currentPrice(0.0), currentBid(0.0), currentAsk(0.0),
                  currentSpread(0.0), rsiValue(0.0), macdValue(0.0),
                  stochValue(0.0), atrValue(0.0), bias("NEUTRAL"),
                  confidence(0.0), hasSignal(false), signalType(""),
                  poiCount(0), swingCount(0) {}
    
    bool Initialize(string sym, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        symbol = sym;
        timeframe = tf;
        analysisTime = TimeCurrent();
        
        if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
            return false;
        
        currentBid = SymbolInfoDouble(sym, SYMBOL_BID);
        currentAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
        currentPrice = (currentBid + currentAsk) / 2.0;
        currentSpread = (currentAsk - currentBid) / SymbolInfoDouble(sym, SYMBOL_POINT);
        
        return true;
    }
    
    void UpdateMarketStructure()
    {
        marketStructure.UpdateRange(currentPrice * 1.01, currentPrice * 0.99, 10);
    }
    
    void FindDivergence()
    {
        divergence.exists = false;
    }
    
    void FindPOILevels()
    {
        poiCount = 0;
        AddPOI(currentPrice * 1.02, "RESISTANCE", "H1", true);
        AddPOI(currentPrice * 0.98, "SUPPORT", "H1", true);
    }
    
    void AddPOI(double price, string type, string tf, bool major)
    {
        if(poiCount < 20)
        {
            poiLevels[poiCount].price = price;
            poiLevels[poiCount].type = type;
            poiLevels[poiCount].timeframe = tf;
            poiLevels[poiCount].isMajor = major;
            poiLevels[poiCount].timestamp = analysisTime;
            poiCount++;
        }
    }
    
    bool GetNearestPOI(double price, POILevel &nearestPOI)
      {
          if(poiCount == 0) return false;
          
          int nearestIdx = 0;
          double minDistance = MathAbs(poiLevels[0].price - price);
          
          for(int i = 1; i < poiCount; i++)
          {
              double distance = MathAbs(poiLevels[i].price - price);
              if(distance < minDistance)
              {
                  minDistance = distance;
                  nearestIdx = i;
              }
          }
          
          nearestPOI = poiLevels[nearestIdx];
          return true;
      }
    
    string GetSummary() const
    {
        string summary = StringFormat("Analysis: %s | %s | %.5f", 
                                    symbol, EnumToString(timeframe), currentPrice);
        summary += StringFormat("\nBias: %s | Confidence: %.1f%%", bias, confidence);
        summary += "\nMarket: " + marketStructure.GetDescription();
            
        if(hasSignal)
            summary += StringFormat("\nSignal: %s detected", signalType);
            
        return summary;
    }
};

// ============ TRADING CONTEXT ============
// Adds risk and account data to analysis context
struct TradingContext
{
    // Analysis results
    AnalysisContext analysis;
    
    // Risk data
    RiskMetrics riskMetrics;
    SymbolInfo symbolInfo;
    
    // Account state
    double accountBalance;
    double accountEquity;
    double freeMargin;
    double usedMargin;
    int totalPositions;
    
    // Existing positions for this symbol
    int symbolPositions;
    double symbolExposure;
    double symbolPnL;
    
    // Decision parameters
    double maxRiskPercent;
    double maxPositionSize;
    bool canOpenNewTrades;
    bool canAddToPositions;
    
    // Generated decision
    TradeDecision decision;
    
    TradingContext() : accountBalance(0.0), accountEquity(0.0),
                      freeMargin(0.0), usedMargin(0.0), totalPositions(0),
                      symbolPositions(0), symbolExposure(0.0), symbolPnL(0.0),
                      maxRiskPercent(2.0), maxPositionSize(0.01),
                      canOpenNewTrades(true), canAddToPositions(true) {}
};

// ============ 9. GLOBAL ARRAYS & DATA STORAGE ============
// Global data containers used throughout the system

// Global arrays to store swing points
// SwingPoint highSwingPoints[];
// SwingPoint lowSwingPoints[];
// DivergenceSignal currentDivergence;

// TrendHealth trendHealth[];
// TrendMomentum trendMomentum[];

// POILevel poiLevels[];

SignalRecord signalHistory[100];  // Array of structs

// PositionData positionTracker[];

// ============ STRUCTURES ============
// struct SymbolAllocation
// {
//     string symbol;
//     ENUM_ASSET_CLASS assetClass;
//     double targetWeight;        // Target allocation percentage
//     double currentWeight;       // Current allocation percentage
//     double capital;             // Allocated capital in USD
//     double riskBudget;          // Maximum risk budget %
//     double performance;         // Performance metric (30-day return)
//     double volatility;          // 30-day volatility
//     double sharpeRatio;         // Risk-adjusted return
//     bool enabled;              // Whether symbol is enabled
//     int priority;              // Trading priority (1-10)
//     datetime lastTradeTime;    // Last trade timestamp
//     double totalProfit;        // Total profit from this symbol
//     double winRate;            // Win rate for this symbol
//     double positionSize;      // Current position size in lots
// };



//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SStopLevel
{
   double            price;
   ENUM_STOP_METHOD  method;
   string            reason;
   datetime          time;
};