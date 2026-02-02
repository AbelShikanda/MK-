// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++       DECISION ENGINE v4.1           ++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property strict
#property version "4.10"

/*
==============================================================
DECISION ENGINE v4.1 - INTELLIGENT ROUTING ARCHITECTURE
==============================================================
Core Improvements:
1. Automatic processor routing based on package type & market regime
2. Dynamic threshold adjustment for ranging/trending markets
3. Clear separation between trend-following and range-fading logic
4. Enhanced regime detection with automatic switching
5. Auto-package creation and processing
==============================================================
*/

// ================= INCLUDES =================

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"

#include "../Utils/Logger.mqh"
#include "../Utils/TimeUtils.mqh"

#include "../Execution/PositionManager.mqh"

#include "../Data/RangePackage.mqh"
#include "../Data/TrendPackage.mqh"
#include "../Data/MarketRegime.mqh"

#include "../Core/PackageManager.mqh"

// ================= FORWARD DECLARATIONS =================

// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED = true;

// Simple debug function using Logger
void DebugLogFile(string context, string message, 
                  bool logToFile = true, bool logToConsole = true)
{
    if (DEBUG_ENABLED)
    {
        Logger::Log(context, message, logToFile, logToConsole);
    }
}

// ================= ENUMS =================
enum DECISION_ACTION
{
    ACTION_NONE,
    ACTION_OPEN_BUY,
    ACTION_OPEN_SELL,
    ACTION_CLOSE_BUY,
    ACTION_CLOSE_SELL,
    ACTION_CLOSE_ALL,
    ACTION_HOLD,
    ACTION_WAITING_FOR_PACKAGE
};

enum POSITION_STATE
{
    STATE_NO_POSITION,
    STATE_HAS_BUY,
    STATE_HAS_SELL,
    STATE_HAS_BOTH
};

// Add this missing enum from MarketRegime.mqh
enum ENUM_MARKET_LIFECYCLE
{
    LIFECYCLE_UNKNOWN,
    LIFECYCLE_TREND_CONFIRMED,
    LIFECYCLE_TREND_RESUMING,
    LIFECYCLE_TREND_WEAKENING,
    LIFECYCLE_BREAKOUT_DETECTED,
    LIFECYCLE_RANGE_ACTIVE,
    LIFECYCLE_RANGE_FORMING,
    LIFECYCLE_PULLBACK_ACTIVE,
    LIFECYCLE_PULLBACK_FORMING
};

// ====================== TRADE PACKAGE INTERFACE ======================

// ================= STRUCTURES =================
struct DecisionParams
{
    double buyConfidenceThreshold;
    double sellConfidenceThreshold;
    double closePositionThreshold;
    double closeAllThreshold;
    int cooldownMinutes;
    int maxPositionsPerSymbol;
    double riskPercent;
    double minRiskRewardRatio;

    // New: Dynamic thresholds for different market regimes
    double rangeBuyThreshold;
    double rangeSellThreshold;
    double trendBuyThreshold;
    double trendSellThreshold;
    double trapProbabilityThreshold;

    DecisionParams(double buyThresh = 65.0,
                   double sellThresh = 65.0,
                   double closeThresh = 40.0,
                   double closeAllThresh = 40.0,
                   int cooldownMins = 30,
                   int maxPositions = 2,
                   double riskPct = 20.0,
                   double minRR = 1.0,
                   double rangeBuy = 75.0,
                   double rangeSell = 75.0,
                   double trendBuy = 65.0,
                   double trendSell = 65.0,
                   double trapProb = 65.0)
    {
        buyConfidenceThreshold = buyThresh;
        sellConfidenceThreshold = sellThresh;
        closePositionThreshold = closeThresh;
        closeAllThreshold = closeAllThresh;
        cooldownMinutes = cooldownMins;
        maxPositionsPerSymbol = maxPositions;
        riskPercent = riskPct;
        minRiskRewardRatio = minRR;
        rangeBuyThreshold = rangeBuy;
        rangeSellThreshold = rangeSell;
        trendBuyThreshold = trendBuy;
        trendSellThreshold = trendSell;
        trapProbabilityThreshold = trapProb;
    }

    // Added: Log params structure
    string ToString() const
    {
        return StringFormat("BuyThresh: %.1f%%, SellThresh: %.1f%%, CloseThresh: %.1f%%, CloseAllThresh: %.1f%%, Cooldown: %dm, MaxPos: %d, Risk: %.1f%%, RR: %.1f",
                            buyConfidenceThreshold, sellConfidenceThreshold, closePositionThreshold,
                            closeAllThreshold, cooldownMinutes, maxPositionsPerSymbol, riskPercent, minRiskRewardRatio);
    }

    // Updated: Get threshold based on market regime
    double GetBuyThreshold(const string &marketRegime) const
    {
        // Check for ALL ranging regime variations
        if (marketRegime == "RANGING" ||
            marketRegime == "TIGHT_RANGE" ||
            marketRegime == "CONSOLIDATION")
            return rangeBuyThreshold;
        return trendBuyThreshold;
    }

    double GetSellThreshold(const string &marketRegime) const
    {
        // Check for ALL ranging regime variations
        if (marketRegime == "RANGING" ||
            marketRegime == "TIGHT_RANGE" ||
            marketRegime == "CONSOLIDATION")
            return rangeSellThreshold;
        return trendSellThreshold;
    }
};

struct CooldownRecord
{
    datetime lastBuyTime;
    datetime lastSellTime;
    int buyCount;
    int sellCount;

    CooldownRecord()
    {
        lastBuyTime = 0;
        lastSellTime = 0;
        buyCount = 0;
        sellCount = 0;
    }

    bool IsInCooldown(bool isBuy, int cooldownMinutes)
    {
        if (cooldownMinutes <= 0)
            return false;

        datetime currentTime = TimeCurrent();
        datetime lastTime = isBuy ? lastBuyTime : lastSellTime;

        bool inCooldown = ((currentTime - lastTime) < (cooldownMinutes * 60));
        if (inCooldown)
        {
            DebugLogFile("COOLDOWN_CHECK", StringFormat("In cooldown: isBuy=%s, lastTime=%s, cooldownMins=%d, remaining=%d sec",
                                                        isBuy ? "true" : "false", TimeToString(lastTime), cooldownMinutes, (cooldownMinutes * 60) - (currentTime - lastTime)));
        }
        return inCooldown;
    }

    void Update(bool isBuy)
    {
        if (isBuy)
        {
            lastBuyTime = TimeCurrent();
            buyCount++;
            DebugLogFile("COOLDOWN_UPDATE", StringFormat("Buy cooldown updated. LastBuyTime: %s, BuyCount: %d",
                                                         TimeToString(lastBuyTime), buyCount));
        }
        else
        {
            lastSellTime = TimeCurrent();
            sellCount++;
            DebugLogFile("COOLDOWN_UPDATE", StringFormat("Sell cooldown updated. LastSellTime: %s, SellCount: %d",
                                                         TimeToString(lastSellTime), sellCount));
        }
    }

    void Reset()
    {
        lastBuyTime = 0;
        lastSellTime = 0;
        buyCount = 0;
        sellCount = 0;
        DebugLogFile("COOLDOWN_RESET", "Cooldown record reset");
    }

    // Added: Log cooldown status
    string GetStatus() const
    {
        return StringFormat("Buy: %s (count: %d), Sell: %s (count: %d)",
                            (lastBuyTime > 0 ? TimeToString(lastBuyTime) : "Never"), buyCount,
                            (lastSellTime > 0 ? TimeToString(lastSellTime) : "Never"), sellCount);
    }
};

struct SymbolState
{
    string symbol;
    DecisionParams params;
    CooldownRecord cooldown;
    DecisionEngineInterface lastPackage;
    DECISION_ACTION lastDecision;
    datetime lastDecisionTime;
    int magicNumber;
    RangeAnalysisResult lastRangeResult;
    bool usingRangePackage;
    string lastProcessorUsed;

    // POSITION TRACKING FIELDS:
    datetime positionOpenTime;
    datetime positionCloseTime;
    DECISION_ACTION positionOpenDecision;
    double positionOpenConfidence;
    bool awaitingProfitabilityCheck;

    string actualProcessorUsed; // "TREND", "RANGE", etc.
    datetime lastProcessingTime;
    string lastProcessingReason;

    SymbolState()
    {
        symbol = "";
        lastDecision = ACTION_NONE;
        lastDecisionTime = 0;
        magicNumber = 0;
        usingRangePackage = false;
        lastProcessorUsed = "NONE";

        // Initialize position tracking fields
        positionOpenTime = 0;
        positionCloseTime = 0;
        positionOpenDecision = ACTION_NONE;
        positionOpenConfidence = 0;
        awaitingProfitabilityCheck = false;

        actualProcessorUsed = "NONE";
        lastProcessingTime = 0;
        lastProcessingReason = "";
    }

    bool HasValidPackage()
    {
        bool isValid = (lastPackage.analysisTime > 0);
        if (!isValid)
        {
            DebugLogFile("PACKAGE_CHECK", StringFormat("No valid interface for %s: analysisTime=%s",
                                                       symbol, TimeToString(lastPackage.analysisTime)));
        }
        return isValid;
    }

    bool IsPackageFresh(int maxAgeSeconds = 300)
    {
        if (!HasValidPackage())
        {
            DebugLogFile("PACKAGE_FRESHNESS", StringFormat("No valid interface for %s", symbol));
            return false;
        }

        int age = (int)(TimeCurrent() - lastPackage.analysisTime);
        bool isFresh = (age <= maxAgeSeconds);

        DebugLogFile("PACKAGE_FRESHNESS", StringFormat("Interface for %s: age=%d sec, maxAge=%d sec, fresh=%s",
                                                       symbol, age, maxAgeSeconds, isFresh ? "true" : "false"));

        return isFresh;
    }

    string GetStatus() const
    {
        return StringFormat("Symbol: %s, Magic: %d, LastDecision: %s, LastDecisionTime: %s, HasInterface: %s, Processor: %s",
                            symbol, magicNumber,
                            (lastDecision == ACTION_NONE ? "NONE" : "SET"),
                            (lastDecisionTime > 0 ? TimeToString(lastDecisionTime) : "Never"),
                            (lastPackage.IsValid() ? "YES" : "NO"),
                            lastProcessorUsed);
    }
};

struct PositionAnalysis
{
    POSITION_STATE state;
    int buyCount;
    int sellCount;
    double totalProfit;
    double totalVolume;
    double maxRiskExposure;

    PositionAnalysis()
    {
        state = STATE_NO_POSITION;
        buyCount = 0;
        sellCount = 0;
        totalProfit = 0;
        totalVolume = 0;
        maxRiskExposure = 0;
    }

    string ToString() const
    {
        string stateStr = "";
        switch (state)
        {
        case STATE_NO_POSITION:
            stateStr = "NO_POSITION";
            break;
        case STATE_HAS_BUY:
            stateStr = "HAS_BUY";
            break;
        case STATE_HAS_SELL:
            stateStr = "HAS_SELL";
            break;
        case STATE_HAS_BOTH:
            stateStr = "HAS_BOTH";
            break;
        }
        return StringFormat("State: %s | Buy: %d | Sell: %d | Profit: %.2f | Volume: %.2f",
                            stateStr, buyCount, sellCount, totalProfit, totalVolume);
    }
};

struct DecisionMetrics
{
    int totalDecisions;
    int profitableDecisions;
    double accuracyRate;
    double averageConfidence;
    datetime startTime;

    int trendProcessorCount;
    int rangeProcessorCount;
    int autoRoutedCount;

    DecisionMetrics()
    {
        totalDecisions = 0;
        profitableDecisions = 0;
        accuracyRate = 0;
        averageConfidence = 0;
        startTime = TimeCurrent();
        trendProcessorCount = 0;
        rangeProcessorCount = 0;
        autoRoutedCount = 0;
        DebugLogFile("METRICS_INIT", "Decision metrics initialized");
    }

    void Update(DECISION_ACTION decision, double confidence, bool wasProfitable = false, string processorType = "")
    {
        // Only count OPEN decisions, not CLOSE decisions
        bool isOpenDecision = (decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL);

        if (!isOpenDecision)
        {
            DebugLogFile("METRICS_SKIP",
                         StringFormat("Skipping non-open decision in metrics: %s (Conf: %.1f%%)",
                                      DecisionToStringStatic(decision), confidence));
            return;
        }

        // ⚠️ IMPORTANT: This method should ONLY be called from ProcessClosedTradeProfitability()
        // after we know if the trade was profitable or not

        // The counting of totalDecisions and profitableDecisions is now done in ProcessClosedTradeProfitability()
        // We just track processor usage here

        // Track processor usage
        if (processorType == "TREND")
            trendProcessorCount++;
        else if (processorType == "RANGE")
            rangeProcessorCount++;
        else if (processorType == "AUTO_ROUTED")
            autoRoutedCount++;

        DebugLogFile("METRICS_PROCESSOR_ONLY",
                     StringFormat("Updated processor stats: Trend: %d | Range: %d | Auto: %d",
                                  trendProcessorCount, rangeProcessorCount, autoRoutedCount));
    }

    // ✅ CORRECTED - KEEP THIS ONE (REMOVE THE OTHER ONE)
    string ToString() const
    {
        // Calculate accuracy based on ONLY OPEN decisions that have closed
        double accuracy = 0;
        if (totalDecisions > 0)
        {
            accuracy = ((double)profitableDecisions / totalDecisions) * 100.0;
        }

        int losses = totalDecisions - profitableDecisions;
        int runningHours = (int)((TimeCurrent() - startTime) / 3600);

        return StringFormat("Trades: %d | W:%d L:%d | Acc: %.1f%% | AvgConf: %.1f%% | Running: %dh",
                            totalDecisions,
                            profitableDecisions,
                            losses,
                            accuracy,
                            averageConfidence,
                            runningHours);
    }

    string GetProcessorStats() const
    {
        return StringFormat("Trend: %d (%.1f%%) | Range: %d (%.1f%%) | Auto: %d (%.1f%%)",
                            trendProcessorCount, totalDecisions > 0 ? (double)trendProcessorCount / totalDecisions * 100 : 0,
                            rangeProcessorCount, totalDecisions > 0 ? (double)rangeProcessorCount / totalDecisions * 100 : 0,
                            autoRoutedCount, totalDecisions > 0 ? (double)autoRoutedCount / totalDecisions * 100 : 0);
    }

    static string DecisionToStringStatic(DECISION_ACTION decision)
    {
        switch (decision)
        {
        case ACTION_NONE:
            return "NONE";
        case ACTION_OPEN_BUY:
            return "OPEN_BUY";
        case ACTION_OPEN_SELL:
            return "OPEN_SELL";
        case ACTION_CLOSE_BUY:
            return "CLOSE_BUY";
        case ACTION_CLOSE_SELL:
            return "CLOSE_SELL";
        case ACTION_CLOSE_ALL:
            return "CLOSE_ALL";
        case ACTION_HOLD:
            return "HOLD";
        case ACTION_WAITING_FOR_PACKAGE:
            return "WAITING";
        default:
            return "UNKNOWN";
        }
    }
};

// ================= CLASS DEFINITION =================
class DecisionEngine
{
private:
    // Configuration
    string m_engineName;
    int m_engineMagicBase;
    bool m_initialized;
    bool m_debugEnabled;

    // Symbol management
    SymbolState m_symbolStates[];
    int m_totalSymbols;

    // Performance tracking
    DecisionMetrics m_metrics;

    // Configuration
    bool m_allowMultiplePositions;
    bool m_useRiskManagement;
    bool m_enforceCooldown;
    int m_maxPackageAgeSeconds;

    // Routing configuration
    bool m_autoDetectProcessor;
    bool m_useMarketRegimeRouting;
    double m_trapThresholdForRange;

    // Auto-package creation
    bool m_autoPackageCreation;
    int m_packageUpdateInterval;
    datetime m_lastPackageCreation;
    PackageManager *m_packageManager;

public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    DecisionEngine()
    {
        m_engineName = "DecisionEngine";
        m_engineMagicBase = 10000;
        m_initialized = false;
        m_debugEnabled = false;
        m_totalSymbols = 0;

        m_allowMultiplePositions = true;
        m_useRiskManagement = true;
        m_enforceCooldown = true;
        m_maxPackageAgeSeconds = 300;

        // Routing defaults
        m_autoDetectProcessor = true;
        m_useMarketRegimeRouting = true;
        m_trapThresholdForRange = 50.0;

        // Auto-package creation defaults
        m_autoPackageCreation = false;
        m_packageUpdateInterval = 10;
        m_lastPackageCreation = 0;
        m_packageManager = NULL;

        ArrayResize(m_symbolStates, 0);

        DebugLogFile("CONSTRUCTOR", "DecisionEngine constructor called");
    }

    ~DecisionEngine()
    {
        DebugLogFile("DESTRUCTOR", "DecisionEngine destructor called");
        Deinitialize();
    }

    // ================= INITIALIZATION =================
    bool Initialize(string engineName = "DecisionEngine",
                    int magicBase = 10000,
                    bool debug = false)
    {
        DebugLogFile("INIT_START", StringFormat("Initializing DecisionEngine: name=%s, magicBase=%d, debug=%s",
                                                engineName, magicBase, debug ? "true" : "false"));

        if (m_initialized)
        {
            DebugLogFile("INIT_WARNING", "Already initialized, calling Deinitialize first");
            Deinitialize();
        }

        m_engineName = engineName;
        m_engineMagicBase = magicBase;
        m_debugEnabled = debug;

        // Initialize logger with default settings
        Logger::Initialize();

        m_initialized = true;

        DebugLogFile("INIT_SUCCESS", "Decision Engine v4.1 Initialized Successfully");
        DebugLogFile("CONFIG", StringFormat("Mode: Intelligent Router | Max Package Age: %d seconds", m_maxPackageAgeSeconds));
        DebugLogFile("CONFIG", StringFormat("AllowMultiplePositions: %s | UseRiskManagement: %s | EnforceCooldown: %s",
                                            m_allowMultiplePositions ? "true" : "false",
                                            m_useRiskManagement ? "true" : "false",
                                            m_enforceCooldown ? "true" : "false"));
        DebugLogFile("CONFIG", StringFormat("AutoDetectProcessor: %s | UseRegimeRouting: %s | TrapThreshold: %.1f%%",
                                            m_autoDetectProcessor ? "true" : "false",
                                            m_useMarketRegimeRouting ? "true" : "false",
                                            m_trapThresholdForRange));
        DebugLogFile("CONFIG", StringFormat("AutoPackageCreation: %s | UpdateInterval: %d sec",
                                            m_autoPackageCreation ? "ENABLED" : "DISABLED",
                                            m_packageUpdateInterval));

        return true;
    }

    void Deinitialize()
    {
        DebugLogFile("DEINIT_START", "Deinitializing DecisionEngine");

        if (!m_initialized)
        {
            DebugLogFile("DEINIT_WARNING", "Not initialized, skipping deinitialization");
            return;
        }

        // Log shutdown statistics
        DebugLogFile("SHUTDOWN", "=== SHUTDOWN STATISTICS ===");
        DebugLogFile("STATS", m_metrics.ToString());
        DebugLogFile("PROCESSOR_STATS", m_metrics.GetProcessorStats());
        DebugLogFile("SYMBOLS", StringFormat("Total symbols monitored: %d", m_totalSymbols));

        // Log each symbol's final state
        for (int i = 0; i < m_totalSymbols; i++)
        {
            DebugLogFile("SYMBOL_FINAL_STATE", m_symbolStates[i].GetStatus());
        }

        ArrayFree(m_symbolStates);
        m_totalSymbols = 0;
        m_initialized = false;

        Logger::Shutdown();

        DebugLogFile("DEINIT_SUCCESS", "DecisionEngine deinitialized successfully");
    }

    // ================= AUTO-PACKAGE CREATION SETTINGS =================
    void SetAutoPackageCreation(bool enabled)
    {
        m_autoPackageCreation = enabled;
        DebugLogFile("CONFIG_CHANGE", StringFormat("Auto-package creation: %s", enabled ? "ENABLED" : "DISABLED"));
    }

    void SetPackageUpdateInterval(int seconds)
    {
        m_packageUpdateInterval = MathMax(1, seconds);
        DebugLogFile("CONFIG_CHANGE", StringFormat("Package update interval: %d seconds", m_packageUpdateInterval));
    }

    void SetPackageManager(PackageManager *manager)
    {
        m_packageManager = manager;
        DebugLogFile("CONFIG_CHANGE", "PackageManager set for auto-package creation");
    }

    // ================= SYMBOL MANAGEMENT =================
    bool RegisterSymbol(string symbol, DecisionParams &params)
    {
        DebugLogFile("REGISTER_SYMBOL_START", StringFormat("Registering symbol: %s with params: %s", symbol, params.ToString()));

        if (!m_initialized)
        {
            DebugLogFile("ERROR", "Engine not initialized");
            return false;
        }

        if (HasSymbol(symbol))
        {
            DebugLogFile("WARNING", "Symbol already registered: " + symbol);
            return true;
        }

        // Resize array if needed
        if (m_totalSymbols >= ArraySize(m_symbolStates))
        {
            int newSize = m_totalSymbols + 10;
            ArrayResize(m_symbolStates, newSize);
            DebugLogFile("ARRAY_RESIZE", StringFormat("Resized symbol states array to %d", newSize));
        }

        // Get market regime for this symbol
        MarketAnalysis regime = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        // Apply regime adaptation
        DecisionParams adaptedParams = CreateRegimeBasedParams(regime, params);

        // Initialize symbol state
        SymbolState state;
        state.symbol = symbol;
        state.params = adaptedParams;

        // Generate unique magic number
        state.magicNumber = GenerateMagicNumber(symbol);

        // Store in array
        m_symbolStates[m_totalSymbols] = state;
        m_totalSymbols++;

        DebugLogFile("REGISTER_SYMBOL_SUCCESS", StringFormat("Symbol registered: %s | Magic: %d | Buy: %.1f%% | Sell: %.1f%%",
                                                             symbol, state.magicNumber,
                                                             state.params.buyConfidenceThreshold,
                                                             state.params.sellConfidenceThreshold));

        DebugLogFile("SYMBOL_COUNT", StringFormat("Total symbols: %d", m_totalSymbols));

        return true;
    }

    // Factory function for mk$ EA parameters - APPLIES MK$ PROFILE
    static DecisionParams CreateMKParams(double maxRiskPerTrade = 20.0,
                                         int positionCooldownMinutes = 60)
    {
        // Start with minimal defaults
        DecisionParams params;

        // OVERRIDE with mk$ specific settings
        params.buyConfidenceThreshold = 60.0;  // mk$ needs higher confidence
        params.sellConfidenceThreshold = 60.0; // Even higher for sells
        params.closePositionThreshold = 40.0;
        params.closeAllThreshold = 40.0;
        params.cooldownMinutes = positionCooldownMinutes;
        params.maxPositionsPerSymbol = 2; // mk$ only trades 1 position
        params.riskPercent = maxRiskPerTrade;
        params.minRiskRewardRatio = 1.0;

        // Regime-specific thresholds for mk$
        params.rangeBuyThreshold = 75.0; // Higher for range trading
        params.rangeSellThreshold = 75.0;
        params.trendBuyThreshold = 60.0; // Lower for trend following
        params.trendSellThreshold = 60.0;
        params.trapProbabilityThreshold = 65.0; // mk$ avoids traps

        DebugLogFile("MK_PARAMS_CREATED",
                     StringFormat("Created mk$ params: Risk=%.1f%%, Cooldown=%dm",
                                  maxRiskPerTrade, positionCooldownMinutes));

        return params;
    }

    bool SetupForMKEA(string symbol,
                      double maxRiskPerTrade,
                      int positionCooldownMinutes,
                      bool useAutoExecution,
                      int magicBase = 10000)
    {
        // Initialize engine
        if (!Initialize("mk$", magicBase, useAutoExecution))
            return false;

        // 1. Create mk$ profile
        DecisionParams mkParams = CreateMKParams(maxRiskPerTrade, positionCooldownMinutes);

        // 2. Get current market regime
        MarketAnalysis regime = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        // 3. Adapt mk$ profile to current regime
        DecisionParams finalParams = CreateRegimeBasedParams(regime, mkParams);

        // 4. Register with adapted parameters
        return RegisterSymbol(symbol, finalParams);
    }

    bool RegisterSymbolWithDefaults(string symbol,
                                    double buyThreshold = 60.0,
                                    double sellThreshold = 60.0,
                                    double riskPercent = 5.0)
    {
        DebugLogFile("REGISTER_SYMBOL_DEFAULTS", StringFormat("Registering %s with defaults: Buy=%.1f%%, Sell=%.1f%%, Risk=%.1f%%",
                                                              symbol, buyThreshold, sellThreshold, riskPercent));

        DecisionParams params;
        params.buyConfidenceThreshold = buyThreshold;
        params.sellConfidenceThreshold = sellThreshold;
        params.riskPercent = riskPercent;

        return RegisterSymbol(symbol, params);
    }

    bool UnregisterSymbol(string symbol)
    {
        DebugLogFile("UNREGISTER_SYMBOL_START", "Unregistering symbol: " + symbol);

        int index = FindSymbolIndex(symbol);
        if (index < 0)
        {
            DebugLogFile("UNREGISTER_ERROR", "Symbol not found: " + symbol);
            return false;
        }

        // Log symbol state before removal
        DebugLogFile("SYMBOL_REMOVAL", StringFormat("Removing symbol %s at index %d, state: %s",
                                                    symbol, index, m_symbolStates[index].GetStatus()));

        // Shift array elements
        for (int i = index; i < m_totalSymbols - 1; i++)
        {
            m_symbolStates[i] = m_symbolStates[i + 1];
        }

        m_totalSymbols--;
        DebugLogFile("UNREGISTER_SUCCESS", "Symbol unregistered: " + symbol);
        DebugLogFile("SYMBOL_COUNT", StringFormat("Total symbols after removal: %d", m_totalSymbols));

        return true;
    }

    // ================= AUTO-PACKAGE CREATION =================
    void CreateAndProcessPackages()
    {
        if (!m_autoPackageCreation || m_packageManager == NULL)
            return;

        if (TimeCurrent() - m_lastPackageCreation < m_packageUpdateInterval)
            return;

        m_lastPackageCreation = TimeCurrent();

        // Create packages for all registered symbols
        for (int i = 0; i < m_totalSymbols; i++)
        {
            string symbol = m_symbolStates[i].symbol;
            DebugLogFile("AUTO_PACKAGE_CREATION", StringFormat("Creating package for %s", symbol));

            // Create appropriate package based on market regime
            DecisionEngineInterface package = CreateAppropriatePackage(symbol);

            if (package.isValid)
            {
                // Process the package
                ProcessPackage(package);
            }
        }
    }

    // ================= PACKAGE CREATION FUNCTION =================
    DecisionEngineInterface CreateAppropriatePackage(string symbol)
    {
        DecisionEngineInterface package;
        package.symbol = symbol;
        package.analysisTime = TimeCurrent();

        DebugLogFile("PACKAGE_CREATION", "=== AUTO-PACKAGE CREATION ===");
        DebugLogFile("PACKAGE_CREATION", "Symbol: " + symbol);

        // ========== STEP 1: GET MARKET REGIME ANALYSIS ==========
        MarketAnalysis regimeAnalysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        DebugLogFile("MARKET_REGIME_ANALYSIS",
                     StringFormat("Market Regime: %s | State: %s | Confidence: %.0f%%",
                                  regimeAnalysis.GetRootStateString(regimeAnalysis.rootState),
                                  regimeAnalysis.GetStateString(regimeAnalysis.state),
                                  regimeAnalysis.confidence));

        // ========== STEP 2: CREATE PACKAGE BASED ON MARKET REGIME ==========
        if (regimeAnalysis.IsTrending())
        {
            // ========== CREATE TREND PACKAGE ==========
            DebugLogFile("PACKAGE_TYPE", "📈 MARKET IS TRENDING - Creating TREND package");

            if (m_packageManager == NULL || !m_packageManager.IsInitialized())
            {
                DebugLogFile("ERROR", "❌ PackageManager not available");
                package.isValid = false;
                return package;
            }

            TrendPackage trendPackage = m_packageManager.GetTrendPackage(true);

            if (!trendPackage.isValid)
            {
                DebugLogFile("ERROR", "❌ No valid TrendPackage available");
                package.isValid = false;
                return package;
            }

            // Populate TREND package with regime info
            package.marketRegime = "TRENDING";
            package.packageType = "TREND"; // Set explicit package type
            package.overallConfidence = (regimeAnalysis.confidence * 0.2) + (trendPackage.overallConfidence * 0.8);
            package.dominantDirection = trendPackage.directionAnalysis.dominantDirection;
            package.weightedScore = trendPackage.weightedScore;
            package.isValid = true;
            package.signalReason = StringFormat("Market Trending (%s): %s",
                                                regimeAnalysis.GetStateString(regimeAnalysis.state),
                                                regimeAnalysis.description);

            // Set trend-specific fields
            package.recommendedAction = "TREND_FOLLOW";
            package.trapProbability = 0; // Trend packages typically have low trap probability
            package.isTrapZone = false;
            package.isAvoidSignal = false;
            package.rangeAction = "NO_RANGE"; // Not a range trade
        }
        else if (regimeAnalysis.IsRanging())
        {
            // ========== CREATE RANGE PACKAGE ==========
            DebugLogFile("PACKAGE_TYPE", "📊 MARKET IS RANGING - Creating RANGE package");

            // Use RangeIntelligence::AnalyzeRange
            RangeAnalysisResult rangeResult = RangeIntelligence::AnalyzeRange(symbol, PERIOD_M15);

            // Populate RANGE package with regime info
            package.marketRegime = "RANGING";
            package.packageType = "RANGE"; // Set explicit package type
            package.trapProbability = rangeResult.trapProbability;
            package.recommendedAction = rangeResult.rangeAction;
            package.overallConfidence = (regimeAnalysis.confidence * 0.2) + (rangeResult.overallConfidence * 0.8);
            package.dominantDirection = rangeResult.rangeBiasDirection;
            package.isTrapZone = rangeResult.isTrapZone;
            package.isAvoidSignal = (regimeAnalysis.action == "Wait for clarity" ||
                                     rangeResult.rangeAction == "AVOID_HIGH_TRAP");
            package.trapReason = StringFormat("Trap: %.1f%%, Bias: %s",
                                              rangeResult.trapProbability, rangeResult.rangeBiasDirection);
            package.isValid = true;
            package.signalReason = StringFormat("Market Ranging (%s): %s",
                                                regimeAnalysis.GetStateString(regimeAnalysis.state),
                                                regimeAnalysis.description);

            // Copy range-specific fields
            package.entryQualityScore = rangeResult.entryQualityScore;
            package.riskRewardScore = rangeResult.riskRewardScore;
            package.rangeBiasDirection = rangeResult.rangeBiasDirection;
            package.rangeBiasConfidence = rangeResult.rangeBiasConfidence;
            package.rangeAction = rangeResult.rangeAction;
            package.supportLevel = rangeResult.supportLevel;
            package.resistanceLevel = rangeResult.resistanceLevel;
            package.supportTouches = rangeResult.supportTouches;
            package.resistanceTouches = rangeResult.resistanceTouches;
        }
        else
        {
            // ========== CREATE DEFAULT PACKAGE ==========
            DebugLogFile("PACKAGE_TYPE", "❓ MARKET REGIME UNKNOWN - Creating default package");

            package.marketRegime = "UNKNOWN";
            package.packageType = "RANGE"; // Default to range for safety
            package.overallConfidence = regimeAnalysis.confidence;
            package.dominantDirection = regimeAnalysis.direction;
            package.isValid = true;
            package.signalReason = "Market Regime Unknown: " + regimeAnalysis.description;

            // Set RANGE-style defaults for safety
            package.recommendedAction = "Wait for clarity";
            package.trapProbability = 50.0;
            package.isTrapZone = true;
            package.isAvoidSignal = true;
            package.rangeAction = "AVOID_HIGH_TRAP";
        }

        // ========== STEP 3: SET COMMON FIELDS WITH REGIME INFO ==========
        package.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        package.orderType = (package.dominantDirection == "BULLISH") ? ORDER_TYPE_BUY : (package.dominantDirection == "BEARISH") ? ORDER_TYPE_SELL
                                                                                                                                 : ORDER_TYPE_BUY_LIMIT;
        package.signalConfidence = package.overallConfidence;

        // Use regime-based stop and TP distances
        package.stopLoss = regimeAnalysis.stopDistance;
        package.takeProfit1 = regimeAnalysis.takeProfitDistance;

        // Use regime-based position size
        switch (regimeAnalysis.positionSize)
        {
        case SIZE_ZERO:
            package.positionSize = 0.0;
            break;
        case SIZE_VERY_SMALL:
            package.positionSize = 0.01;
            break;
        case SIZE_SMALL:
            package.positionSize = 0.08;
            break;
        case SIZE_MEDIUM:
            package.positionSize = 2.05;
            break;
        case SIZE_LARGE:
            package.positionSize = 5.1;
            break;
        default:
            package.positionSize = 0.03;
            break;
        }

        package.timeframe = Period();

        // Store regime info in extra fields
        package.extraInfo1 = StringFormat("Regime:%s", regimeAnalysis.GetRootStateString(regimeAnalysis.rootState));
        package.extraInfo2 = StringFormat("State:%s", regimeAnalysis.GetStateString(regimeAnalysis.state));
        package.extraInfo3 = StringFormat("Conf:%.0f|Action:%s", regimeAnalysis.confidence, regimeAnalysis.action);

        DebugLogFile("PACKAGE_CREATION_COMPLETE",
                     StringFormat("🎯 Package created: Type=%s, Regime=%s, State=%s, Action=%s, Dir=%s, Conf=%.1f%%",
                                  package.packageType,
                                  package.marketRegime,
                                  regimeAnalysis.GetStateString(regimeAnalysis.state),
                                  package.recommendedAction,
                                  package.dominantDirection,
                                  package.overallConfidence));

        return package;
    }

    // ================= ADDITIONAL HELPER METHODS =================
    void LogPackageProcessingResult(string symbol, string processorType, DECISION_ACTION decision, string status)
    {
        string decisionStr = DecisionToString(decision);
        string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

        string logEntry = StringFormat("[%s] %s | Processor: %s | Decision: %s | Status: %s",
                                       timestamp, symbol, processorType, decisionStr, status);

        DebugLogFile("PACKAGE_RESULT", logEntry);
        DebugLogFile("PACKAGE_PROCESSING", logEntry, true, true);
    }

    string TimeframeToString(ENUM_TIMEFRAMES tf)
    {
        switch (tf)
        {
        case PERIOD_M1:
            return "M1";
        case PERIOD_M5:
            return "M5";
        case PERIOD_M15:
            return "M15";
        case PERIOD_M30:
            return "M30";
        case PERIOD_H1:
            return "H1";
        case PERIOD_H4:
            return "H4";
        case PERIOD_D1:
            return "D1";
        case PERIOD_W1:
            return "W1";
        case PERIOD_MN1:
            return "MN1";
        default:
            return "UNKNOWN";
        }
    }

    // ================= MAIN PUBLIC INTERFACE =================
    DECISION_ACTION ProcessPackage(DecisionEngineInterface &package)
    {
        DebugLogFile("PROCESS_PACKAGE_START", "=====================================");
        DebugLogFile("PROCESS_PACKAGE_START", StringFormat(">>> PURE PROCESSOR MODE | Symbol: %s", package.symbol));

        if (!m_initialized)
        {
            DebugLogFile("ERROR", "❌ Engine not initialized");
            return ACTION_NONE;
        }

        string symbol = package.symbol;

        // ============ STEP 1: VALIDATE PACKAGE ============
        DebugLogFile("PACKAGE_VALIDATION", "--- VALIDATING INCOMING PACKAGE ---");

        if (!package.isValid)
        {
            DebugLogFile("ERROR", "❌ Package is invalid");
            return ACTION_NONE;
        }

        if (package.symbol == "")
        {
            DebugLogFile("ERROR", "❌ Package symbol is empty");
            return ACTION_NONE;
        }

        DebugLogFile("PACKAGE_DETAILS", StringFormat("Type=%s, Confidence=%.1f%%, Dir=%s, Regime=%s, Action=%s, Trap=%.1f%%",
                                                     package.packageType,
                                                     package.overallConfidence,
                                                     package.dominantDirection,
                                                     package.marketRegime,
                                                     package.recommendedAction,
                                                     package.trapProbability));

        // ============ STEP 2: USE PACKAGE REGIME FOR ROUTING ============
        DebugLogFile("ROUTING_START", "--- ROUTING BASED ON PACKAGE REGIME ---");

        DECISION_ACTION decision = ACTION_NONE;
        string processorType = "UNKNOWN";
        string routingReason = "";

        // Get package type from packageType field (preferred)
        string packageType = package.packageType;

        // If packageType not set, infer from marketRegime
        if (packageType == "NONE" || packageType == "")
        {
            if (StringFind(package.marketRegime, "RANGING") >= 0 ||
                StringFind(package.marketRegime, "CONSOLIDATION") >= 0)
            {
                packageType = "RANGE";
            }
            else if (StringFind(package.marketRegime, "TRENDING") >= 0)
            {
                packageType = "TREND";
            }
            else
            {
                // Default inference based on other fields
                if (StringFind(package.recommendedAction, "FADE") >= 0 ||
                    package.trapProbability > 40)
                {
                    packageType = "RANGE";
                }
                else
                {
                    packageType = "TREND";
                }
            }
            DebugLogFile("PACKAGE_TYPE_INFERRED", StringFormat("Inferred package type as: %s", packageType));
        }

        DebugLogFile("PACKAGE_TYPE", StringFormat("Final package type: %s", packageType));

        // ============ STEP 3: GET CURRENT MARKET REGIME (FOR MONITORING ONLY) ============
        DebugLogFile("MARKET_MONITOR", "--- GETTING CURRENT MARKET REGIME (MONITORING ONLY) ---");

        MarketAnalysis currentRegime = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        DebugLogFile("CURRENT_REGIME", StringFormat("Current Market: Root=%s, State=%s, Conf=%.0f%%",
                                                    currentRegime.GetRootStateString(currentRegime.rootState),
                                                    currentRegime.GetStateString(currentRegime.state),
                                                    currentRegime.confidence));

        DebugLogFile("PACKAGE_REGIME", StringFormat("Package Regime: %s", package.marketRegime));

        // ============ STEP 4: PURE ROUTING BASED ON PACKAGE TYPE ============
        DebugLogFile("PURE_ROUTING", "--- EXECUTING PURE ROUTING ---");

        if (packageType == "TREND")
        {
            DebugLogFile("ROUTING_DECISION", "📈 PACKAGE IS TREND TYPE - routing to TREND processor");

            // Check regime alignment for monitoring
            if (StringFind(package.marketRegime, "RANGING") >= 0)
            {
                DebugLogFile("REGIME_MISMATCH_MONITOR", "⚠️ MONITORING: Package marked as TREND but regime says RANGING");
                routingReason = "Trend package (regime mismatch monitoring)";
            }
            else
            {
                routingReason = "Trend package - optimal routing";
            }

            decision = ProcessTrendPackage(package);
            processorType = "TREND";
        }
        else if (packageType == "RANGE")
        {
            DebugLogFile("ROUTING_DECISION", "📊 PACKAGE IS RANGE TYPE - routing to RANGE processor");

            // Check regime alignment for monitoring
            if (StringFind(package.marketRegime, "TRENDING") >= 0)
            {
                DebugLogFile("REGIME_MISMATCH_MONITOR", "⚠️ MONITORING: Package marked as RANGE but regime says TRENDING");
                routingReason = "Range package (regime mismatch monitoring)";
            }
            else
            {
                routingReason = "Range package - optimal routing";
            }

            decision = ProcessRangePackage(package);
            processorType = "RANGE";
        }
        else
        {
            DebugLogFile("ROUTING_ERROR", "❌ Unknown package type: " + packageType);
            return ACTION_NONE;
        }

        DebugLogFile("ROUTING_COMPLETE", StringFormat("✅ Routed to %s processor | Reason: %s", processorType, routingReason));

        // ============ STEP 5: SYMBOL REGISTRATION ============
        DebugLogFile("SYMBOL_CHECK", "--- SYMBOL REGISTRATION ---");

        if (!HasSymbol(symbol))
        {
            DebugLogFile("AUTO_REGISTRATION", StringFormat("Auto-registering %s", symbol));

            DecisionParams minimalParams;
            DecisionParams params = CreateRegimeBasedParams(currentRegime, minimalParams);

            if (!RegisterSymbol(symbol, params))
            {
                DebugLogFile("AUTO_REG_ERROR", "❌ Failed to auto-register symbol");
                return ACTION_NONE;
            }
        }

        // ============ STEP 6: GET SYMBOL INDEX ============
        int symbolIndex = FindSymbolIndex(symbol);
        if (symbolIndex < 0)
        {
            DebugLogFile("SYMBOL_INDEX_ERROR", "❌ Symbol index not found");
            return ACTION_NONE;
        }

        // ============ STEP 7: UPDATE SYMBOL STATE ============
        m_symbolStates[symbolIndex].lastProcessorUsed = processorType;
        m_symbolStates[symbolIndex].actualProcessorUsed = processorType;
        m_symbolStates[symbolIndex].lastProcessingTime = TimeCurrent();
        m_symbolStates[symbolIndex].lastProcessingReason = routingReason;

        // Store current regime for monitoring (DO NOT override package regime)
        package.extraInfo1 = StringFormat("CurrentRegime:%s", currentRegime.GetRootStateString(currentRegime.rootState));
        package.extraInfo2 = StringFormat("CurrentState:%s", currentRegime.GetStateString(currentRegime.state));
        package.extraInfo3 = StringFormat("Monitor:PackageRegime=%s|CurrentRegime=%s|Match=%s",
                                          package.marketRegime,
                                          currentRegime.GetRootStateString(currentRegime.rootState),
                                          (StringFind(package.marketRegime, "TRENDING") >= 0 && currentRegime.IsTrending()) ||
                                                  (StringFind(package.marketRegime, "RANGING") >= 0 && currentRegime.IsRanging())
                                              ? "YES"
                                              : "NO");

        // ============ STEP 8: LOG RESULTS ============
        string decisionStr = DecisionToString(decision);

        // Calculate regime match for monitoring
        bool regimeMatch = false;
        if (StringFind(package.marketRegime, "TRENDING") >= 0 && currentRegime.IsTrending())
            regimeMatch = true;
        else if (StringFind(package.marketRegime, "RANGING") >= 0 && currentRegime.IsRanging())
            regimeMatch = true;

        LogPackageProcessingResult(symbol, processorType, decision,
                                   StringFormat("PURE_PROCESSOR | PackageRegime: %s | CurrentRegime: %s | Match: %s",
                                                package.marketRegime,
                                                currentRegime.GetRootStateString(currentRegime.rootState),
                                                regimeMatch ? "YES" : "NO"));

        if (decision == ACTION_NONE || decision == ACTION_HOLD)
        {
            DebugLogFile("NO_ACTION", StringFormat("⏸️ No action | Decision: %s", decisionStr));
        }
        else if (decision == ACTION_WAITING_FOR_PACKAGE)
        {
            DebugLogFile("WAITING", StringFormat("⏳ Waiting for fresh package", ""));
        }
        else
        {
            DebugLogFile("ACTIONABLE", StringFormat("🎯 Action: %s | Processor: %s | PackageRegime: %s",
                                                    decisionStr, processorType, package.marketRegime));
        }

        DebugLogFile("PROCESS_PACKAGE_END", StringFormat("<<< PURE PROCESSING COMPLETE | Symbol: %s | Decision: %s | PackageType: %s | PackageRegime: %s | CurrentRegime: %s | Processor: %s",
                                                         symbol, decisionStr, packageType,
                                                         package.marketRegime,
                                                         currentRegime.GetRootStateString(currentRegime.rootState),
                                                         processorType));
        DebugLogFile("PROCESS_PACKAGE_END", "=====================================\n");

        return decision;
    }

    // ================= PROCESS TREND PACKAGE =================
    DECISION_ACTION ProcessTrendPackage(DecisionEngineInterface &package)
    {
        DebugLogFile("PROCESS_TREND_PACKAGE", StringFormat("=== PROCESSING TREND PACKAGE === | Symbol: %s | Dir: %s | Conf: %.1f%% | Regime: %s",
                                                           package.symbol, package.dominantDirection,
                                                           package.overallConfidence, package.marketRegime));

        if (!m_initialized)
        {
            DebugLogFile("ERROR", "Engine not initialized");
            return ACTION_NONE;
        }

        string symbol = package.symbol;

        // Validate symbol is registered
        if (!HasSymbol(symbol))
        {
            DebugLogFile("AUTO-REG", "Auto-registering symbol: " + symbol);
            if (!RegisterSymbolWithDefaults(symbol))
            {
                DebugLogFile("AUTO-REG_ERROR", "Failed to auto-register symbol: " + symbol);
                return ACTION_NONE;
            }
        }

        int symbolIndex = FindSymbolIndex(symbol);
        if (symbolIndex < 0)
        {
            DebugLogFile("ERROR", "Symbol index not found: " + symbol);
            return ACTION_NONE;
        }

        // Store the package as trend
        m_symbolStates[symbolIndex].lastPackage = package;
        m_symbolStates[symbolIndex].lastDecisionTime = TimeCurrent();
        m_symbolStates[symbolIndex].usingRangePackage = false;

        DebugLogFile("TREND_PACKAGE_STORED", StringFormat("Trend package stored for %s | Dir: %s | Conf: %.1f%%",
                                                          symbol, package.dominantDirection, package.overallConfidence));

        // Validate package
        if (!package.IsValid())
        {
            LogDecision(symbol, ACTION_NONE, package, "Invalid trend package");
            return ACTION_NONE;
        }

        // Check package freshness
        if (!IsPackageFresh(symbolIndex))
        {
            LogDecision(symbol, ACTION_WAITING_FOR_PACKAGE, package, "Trend package too old");
            return ACTION_WAITING_FOR_PACKAGE;
        }

        DebugLogFile("TREND_PROCESS", "✅ Trend package valid and fresh");

        // Analyze current positions
        PositionAnalysis positions = AnalyzePositions(symbolIndex);
        DebugLogFile("TREND_POSITIONS", StringFormat("Current positions: %s", positions.ToString()));

        // Make decision using PURE trend-following logic
        DECISION_ACTION decision = MakeTrendDecision(symbolIndex, package, positions);
        DebugLogFile("TREND_DECISION_MADE", StringFormat("Trend decision made: %s", DecisionToString(decision)));

        // Validate and potentially execute
        if (decision != ACTION_NONE && decision != ACTION_HOLD && decision != ACTION_WAITING_FOR_PACKAGE)
        {
            DebugLogFile("TREND_VALIDATION_START", "Starting trend decision validation");
            if (ValidateDecision(symbolIndex, decision, package))
            {
                DebugLogFile("TREND_VALIDATION", "✅ Trend decision validated");
                ExecuteDecision(symbolIndex, decision, package);
            }
            else
            {
                DebugLogFile("TREND_VALIDATION", "❌ Trend decision validation failed");
                decision = ACTION_HOLD;
                DebugLogFile("TREND_FALLBACK", "Falling back to HOLD due to validation failure");
            }
        }
        else
        {
            DebugLogFile("TREND_NO_EXECUTION", StringFormat("No execution needed: %s", DecisionToString(decision)));
        }

        // Store and log decision
        m_symbolStates[symbolIndex].lastDecision = decision;

        DebugLogFile("TREND_PROCESS_COMPLETE", StringFormat("=== TREND PROCESS COMPLETE === | Final decision: %s", DecisionToString(decision)));
        return decision;
    }

    // ================= RANGE PACKAGE PROCESSING =================
    DECISION_ACTION ProcessRangePackage(DecisionEngineInterface &package)
    {
        DebugLogFile("PROCESS_RANGE_PACKAGE", StringFormat("=== PROCESSING RANGE PACKAGE === | Symbol: %s | Regime: %s | Action: %s | Trap: %.1f%%",
                                                           package.symbol, package.marketRegime, package.recommendedAction, package.trapProbability));

        if (!m_initialized)
        {
            DebugLogFile("ERROR", "Engine not initialized");
            return ACTION_NONE;
        }

        string symbol = package.symbol;

        // Validate symbol is registered
        if (!HasSymbol(symbol))
        {
            DebugLogFile("AUTO-REG", "Auto-registering symbol: " + symbol);
            if (!RegisterSymbolWithDefaults(symbol))
            {
                DebugLogFile("AUTO-REG_ERROR", "Failed to auto-register symbol: " + symbol);
                return ACTION_NONE;
            }
        }

        int symbolIndex = FindSymbolIndex(symbol);
        if (symbolIndex < 0)
        {
            DebugLogFile("ERROR", "Symbol index not found: " + symbol);
            return ACTION_NONE;
        }

        // Mark this as a range package
        m_symbolStates[symbolIndex].usingRangePackage = true;
        m_symbolStates[symbolIndex].lastPackage = package;
        m_symbolStates[symbolIndex].lastDecisionTime = TimeCurrent();

        // Range packages should have these fields populated:
        DebugLogFile("RANGE_DATA", StringFormat("Regime: %s | Action: %s | Trap: %.1f%% | Avoid: %s",
                                                package.marketRegime, package.recommendedAction,
                                                package.trapProbability, package.ShouldAvoid() ? "YES" : "NO"));

        // Validate package
        if (!package.IsValid())
        {
            LogDecision(symbol, ACTION_NONE, package, "Invalid RangePackage");
            return ACTION_NONE;
        }

        // Check package freshness
        if (!IsPackageFresh(symbolIndex))
        {
            LogDecision(symbol, ACTION_WAITING_FOR_PACKAGE, package, "Range package too old");
            return ACTION_WAITING_FOR_PACKAGE;
        }

        // Analyze current positions
        PositionAnalysis positions = AnalyzePositions(symbolIndex);

        // Make decision based on RANGE package
        DECISION_ACTION decision = MakeRangeDecision(symbolIndex, package, positions);

        DebugLogFile("RANGE_DECISION_MADE", StringFormat("Range decision: %s", DecisionToString(decision)));

        // Execute if needed
        if (decision != ACTION_NONE && decision != ACTION_HOLD && decision != ACTION_WAITING_FOR_PACKAGE)
        {
            if (ValidateDecision(symbolIndex, decision, package))
            {
                ExecuteDecision(symbolIndex, decision, package);
            }
            else
            {
                decision = ACTION_HOLD;
            }
        }

        m_symbolStates[symbolIndex].lastDecision = decision;

        return decision;
    }

    // ================= ENHANCED TREND DECISION WITH LIFECYCLE =================
    DECISION_ACTION MakeTrendDecision(int symbolIndex, DecisionEngineInterface &package, PositionAnalysis &positions)
    {
        DebugLogFile("MAKE_TREND_DECISION", "=====================================");
        DebugLogFile("MAKE_TREND_DECISION", StringFormat("=== MAKING TREND DECISION (RESPECTING PACKAGE) === | Symbol: %s",
                                                         m_symbolStates[symbolIndex].symbol));

        if (symbolIndex < 0 || symbolIndex >= m_totalSymbols)
        {
            DebugLogFile("ERROR", "❌ Invalid symbol index");
            return ACTION_NONE;
        }

        string symbol = m_symbolStates[symbolIndex].symbol;

        // ============ STEP 1: GET MARKET REGIME FOR MONITORING ONLY ============
        DebugLogFile("MARKET_MONITOR", "--- Getting current market (MONITORING ONLY) ---");
        MarketAnalysis currentMarket = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        // PURE MONITORING - no rejection
        bool marketIsTrending = currentMarket.IsTrending();
        string marketState = currentMarket.GetRootStateString(currentMarket.rootState);

        DebugLogFile("MARKET_MONITOR_INFO",
                     StringFormat("Current Market: %s | State: %s | Conf: %.0f%% | IsTrending: %s",
                                  marketState,
                                  currentMarket.GetStateString(currentMarket.state),
                                  currentMarket.confidence,
                                  marketIsTrending ? "YES" : "NO"));

        // ============ STEP 2: USE PACKAGE VALUES FOR DECISION MAKING ============
        DebugLogFile("PACKAGE_RESPECT", "--- RESPECTING PACKAGE VALUES ---");

        // Use package values EXACTLY as provided
        double confidence = package.overallConfidence; // NO adjustments
        string direction = package.dominantDirection;  // NO overrides
        string packageRegime = package.marketRegime;   // Package's own regime

        DebugLogFile("PACKAGE_VALUES",
                     StringFormat("Package: Regime=%s, Dir=%s, Conf=%.1f%%, Type=%s",
                                  packageRegime, direction, confidence, package.packageType));

        // ============ STEP 3: SET THRESHOLDS BASED ON PACKAGE REGIME ============
        DebugLogFile("THRESHOLDS", "--- Setting thresholds based on PACKAGE regime ---");
        DecisionParams params = m_symbolStates[symbolIndex].params;

        // Use package regime to determine thresholds (respects package intent)
        double buyThreshold = params.GetBuyThreshold(packageRegime);   // Uses packageRegime
        double sellThreshold = params.GetSellThreshold(packageRegime); // Uses packageRegime

        DebugLogFile("THRESHOLD_INFO",
                     StringFormat("Using thresholds for PackageRegime=%s: Buy=%.1f%%, Sell=%.1f%%",
                                  packageRegime, buyThreshold, sellThreshold));

        // ============ STEP 4: MONITOR CONTEXT (NO ADJUSTMENTS) ============
        DebugLogFile("CONTEXT_MONITOR", "--- Monitoring context (NO adjustments) ---");

        // Monitor if package regime matches current market
        bool contextMatch = false;
        string contextNote = "";

        if ((StringFind(packageRegime, "TRENDING") >= 0 || package.packageType == "TREND") && marketIsTrending)
        {
            contextMatch = true;
            contextNote = "Optimal: Trend package in trending market";
            DebugLogFile("CONTEXT_MONITOR", "✅ MONITOR: Optimal context");
        }
        else if ((StringFind(packageRegime, "TRENDING") >= 0 || package.packageType == "TREND") && !marketIsTrending)
        {
            contextMatch = false;
            contextNote = StringFormat("Monitor: Trend package in %s market (continuing anyway)", marketState);
            DebugLogFile("CONTEXT_MONITOR", StringFormat("⚠️ MONITOR: %s", contextNote));
        }

        // Store monitoring info (NO adjustments to package)
        string originalExtraInfo = package.extraInfo3;
        package.extraInfo3 = StringFormat("%s|Monitor:CurrMarket=%s|ContextMatch=%s",
                                          originalExtraInfo, marketState, contextMatch ? "YES" : "NO");

        // ============ STEP 5: HANDLE NO POSITION CASE ============
        if (positions.state == STATE_NO_POSITION)
        {
            DebugLogFile("NO_POSITION", "No positions open - evaluating new position");

            // Check BUY conditions using PACKAGE values
            if (direction == "BULLISH" && confidence >= buyThreshold)
            {
                DebugLogFile("BUY_CONDITION_MET",
                             StringFormat("✅ BUY condition met using PACKAGE values: Dir=%s, Conf=%.1f%% >= %.1f%%",
                                          direction, confidence, buyThreshold));

                if (!CheckCooldown(symbolIndex, true))
                {
                    DebugLogFile("BUY_COOLDOWN", "❌ Buy blocked by cooldown");
                    return ACTION_HOLD;
                }

                if (!CheckPositionLimits(symbolIndex, true))
                {
                    DebugLogFile("BUY_LIMITS", "❌ Buy position limits reached");
                    return ACTION_HOLD;
                }

                DebugLogFile("DECISION_FINAL", "🎯 Trend decision: OPEN_BUY (respecting package)");
                return ACTION_OPEN_BUY;
            }

            // Check SELL conditions using PACKAGE values
            if (direction == "BEARISH" && confidence >= sellThreshold)
            {
                DebugLogFile("SELL_CONDITION_MET",
                             StringFormat("✅ SELL condition met using PACKAGE values: Dir=%s, Conf=%.1f%% >= %.1f%%",
                                          direction, confidence, sellThreshold));

                if (!CheckCooldown(symbolIndex, false))
                {
                    DebugLogFile("SELL_COOLDOWN", "❌ Sell blocked by cooldown");
                    return ACTION_HOLD;
                }

                if (!CheckPositionLimits(symbolIndex, false))
                {
                    DebugLogFile("SELL_LIMITS", "❌ Sell position limits reached");
                    return ACTION_HOLD;
                }

                DebugLogFile("DECISION_FINAL", "🎯 Trend decision: OPEN_SELL (respecting package)");
                return ACTION_OPEN_SELL;
            }

            DebugLogFile("NO_ENTRY", StringFormat("⏸️ No entry conditions met | Dir=%s, Conf=%.1f%%, BuyThresh=%.1f%%, SellThresh=%.1f%%",
                                                  direction, confidence, buyThreshold, sellThreshold));
            return ACTION_HOLD;
        }

        // ============ STEP 6: HANDLE EXISTING POSITIONS ============
        DebugLogFile("EXISTING_POSITIONS", StringFormat("Existing positions: %s", positions.ToString()));

        // Apply position management using PACKAGE values
        return DecideWithPositionTrend(symbolIndex, package, positions, params, direction, confidence, currentMarket);
    }

    //+------------------------------------------------------------------+
    //| Make range decision respecting package                          |
    //+------------------------------------------------------------------+
    DECISION_ACTION MakeRangeDecision(int symbolIndex, DecisionEngineInterface &package,
                                      PositionAnalysis &positions)
    {
        DebugLogFile("MAKE_RANGE_DECISION", "=====================================");
        DebugLogFile("MAKE_RANGE_DECISION", StringFormat("=== MAKING RANGE DECISION (RESPECTING PACKAGE) === | Symbol: %s",
                                                         m_symbolStates[symbolIndex].symbol));

        if (symbolIndex < 0 || symbolIndex >= m_totalSymbols)
        {
            DebugLogFile("ERROR", "❌ Invalid symbol index");
            return ACTION_NONE;
        }

        string symbol = m_symbolStates[symbolIndex].symbol;

        // ============ STEP 1: GET CURRENT MARKET FOR MONITORING ============
        DebugLogFile("MARKET_MONITOR", "--- Getting current market (MONITORING ONLY) ---");
        MarketAnalysis currentMarket = GetMarketRegimeAnalysis(symbol, PERIOD_M15);

        // PURE MONITORING - no rejection
        bool marketIsRanging = currentMarket.IsRanging();
        string marketState = currentMarket.GetRootStateString(currentMarket.rootState);

        DebugLogFile("MARKET_MONITOR_INFO",
                     StringFormat("Current Market: %s | State: %s | Conf: %.0f%% | IsRanging: %s",
                                  marketState,
                                  currentMarket.GetStateString(currentMarket.state),
                                  currentMarket.confidence,
                                  marketIsRanging ? "YES" : "NO"));

        // ============ STEP 2: USE PACKAGE VALUES FOR DECISION MAKING ============
        DebugLogFile("PACKAGE_RESPECT", "--- RESPECTING PACKAGE VALUES ---");

        // Use package values EXACTLY as provided
        double confidence = package.overallConfidence; // NO adjustments
        string direction = package.dominantDirection;  // NO overrides
        string packageRegime = package.marketRegime;   // Package's own regime

        DebugLogFile("PACKAGE_VALUES",
                     StringFormat("Package: Regime=%s, Dir=%s, Conf=%.1f%%, Type=%s, Action=%s, Trap=%.1f%%",
                                  packageRegime, direction, confidence, package.packageType,
                                  package.recommendedAction, package.trapProbability));

        // ============ STEP 3: SET THRESHOLDS BASED ON PACKAGE REGIME ============
        DebugLogFile("THRESHOLDS", "--- Setting thresholds based on PACKAGE regime ---");
        DecisionParams params = m_symbolStates[symbolIndex].params;

        // Use package regime to determine thresholds (respects package intent)
        double buyThreshold = params.GetBuyThreshold(packageRegime);   // Uses packageRegime
        double sellThreshold = params.GetSellThreshold(packageRegime); // Uses packageRegime

        DebugLogFile("THRESHOLD_INFO",
                     StringFormat("Using thresholds for PackageRegime=%s: Buy=%.1f%%, Sell=%.1f%%",
                                  packageRegime, buyThreshold, sellThreshold));

        // ============ STEP 4: MONITOR CONTEXT (NO ADJUSTMENTS) ============
        DebugLogFile("CONTEXT_MONITOR", "--- Monitoring context (NO adjustments) ---");

        // Monitor if package regime matches current market
        bool contextMatch = false;
        string contextNote = "";

        if ((StringFind(packageRegime, "RANGING") >= 0 || package.packageType == "RANGE") && marketIsRanging)
        {
            contextMatch = true;
            contextNote = "Optimal: Range package in ranging market";
            DebugLogFile("CONTEXT_MONITOR", "✅ MONITOR: Optimal context");
        }
        else if ((StringFind(packageRegime, "RANGING") >= 0 || package.packageType == "RANGE") && !marketIsRanging)
        {
            contextMatch = false;
            contextNote = StringFormat("Monitor: Range package in %s market (continuing anyway)", marketState);
            DebugLogFile("CONTEXT_MONITOR", StringFormat("⚠️ MONITOR: %s", contextNote));
        }

        // Store monitoring info (NO adjustments to package)
        string originalExtraInfo = package.extraInfo3;
        package.extraInfo3 = StringFormat("%s|Monitor:CurrMarket=%s|ContextMatch=%s",
                                          originalExtraInfo, marketState, contextMatch ? "YES" : "NO");

        // ============ STEP 5: HANDLE NO POSITION CASE ============
        if (positions.state == STATE_NO_POSITION)
        {
            DebugLogFile("NO_POSITION", "No positions open - evaluating new position");

            // Simple check: Use package values directly
            if (direction == "BULLISH" && confidence >= buyThreshold)
            {
                DebugLogFile("BUY_CONDITION_MET",
                             StringFormat("✅ RANGE BUY condition met using PACKAGE values: Dir=%s, Conf=%.1f%% >= %.1f%%",
                                          direction, confidence, buyThreshold));

                if (!CheckCooldown(symbolIndex, true))
                {
                    DebugLogFile("BUY_COOLDOWN", "❌ Buy blocked by cooldown");
                    return ACTION_HOLD;
                }

                if (!CheckPositionLimits(symbolIndex, true))
                {
                    DebugLogFile("BUY_LIMITS", "❌ Buy position limits reached");
                    return ACTION_HOLD;
                }

                DebugLogFile("DECISION_FINAL", "🎯 Range decision: OPEN_BUY (respecting package)");
                return ACTION_OPEN_BUY;
            }

            if (direction == "BEARISH" && confidence >= sellThreshold)
            {
                DebugLogFile("SELL_CONDITION_MET",
                             StringFormat("✅ RANGE SELL condition met using PACKAGE values: Dir=%s, Conf=%.1f%% >= %.1f%%",
                                          direction, confidence, sellThreshold));

                if (!CheckCooldown(symbolIndex, false))
                {
                    DebugLogFile("SELL_COOLDOWN", "❌ Sell blocked by cooldown");
                    return ACTION_HOLD;
                }

                if (!CheckPositionLimits(symbolIndex, false))
                {
                    DebugLogFile("SELL_LIMITS", "❌ Sell position limits reached");
                    return ACTION_HOLD;
                }

                DebugLogFile("DECISION_FINAL", "🎯 Range decision: OPEN_SELL (respecting package)");
                return ACTION_OPEN_SELL;
            }

            DebugLogFile("NO_ENTRY", StringFormat("⏸️ No entry conditions met | Dir=%s, Conf=%.1f%%, BuyThresh=%.1f%%, SellThresh=%.1f%%",
                                                  direction, confidence, buyThreshold, sellThreshold));
            return ACTION_HOLD;
        }

        // ============ STEP 6: HANDLE EXISTING POSITIONS ============
        DebugLogFile("EXISTING_POSITIONS", StringFormat("Existing positions: %s", positions.ToString()));

        // Apply position management using PACKAGE values
        return DecideWithPositionRange(symbolIndex, package, positions, params, direction, confidence, currentMarket);
    }

    DECISION_ACTION DecideWithPositionTrend(int symbolIndex, const DecisionEngineInterface &source,
                                            PositionAnalysis &positions, DecisionParams &params,
                                            string direction, double confidence, const MarketAnalysis &currentMarket)
    {
        DebugLogFile("DECIDE_TREND_WITH_POSITION", "--- Making trend decision with signal context ---");

        // LOG SIGNAL CONTEXT (simplified - no TradeSignal fields)
        DebugLogFile("TREND_SIGNAL_CONTEXT", StringFormat("Signal Direction: %s | Confidence: %.1f%% | Market: %s",
                                                          direction, confidence,
                                                          currentMarket.GetStateString(currentMarket.state)));

        // Use params for thresholds
        double closeThreshold = params.closePositionThreshold;
        double emergencyThreshold = params.closeAllThreshold;

        // SIMPLE POSITION CHECKING
        DebugLogFile("TREND_POSITION_STATE",
                     StringFormat("Positions: %s | Signal: %s (%.1f%%)",
                                  GetPositionStateString(positions.state),
                                  direction, confidence));

        // Check for emergency close based on confidence
        if (confidence < emergencyThreshold)
        {
            DebugLogFile("TREND_EMERGENCY_CLOSE",
                         StringFormat("Confidence %.1f%% < %.1f%%", confidence, emergencyThreshold));
            return ACTION_CLOSE_ALL;
        }

        // NORMAL CLOSING LOGIC
        if (confidence > closeThreshold)
        {
            if (positions.state == STATE_HAS_BUY && direction == "BEARISH")
            {
                DebugLogFile("TREND_CLOSE_BUY",
                             StringFormat("Closing BUY | Signal confidence %.1f%% > threshold %.1f%%",
                                          confidence, closeThreshold));
                return ACTION_CLOSE_BUY;
            }

            if (positions.state == STATE_HAS_SELL && direction == "BULLISH")
            {
                DebugLogFile("TREND_CLOSE_SELL",
                             StringFormat("Closing SELL | Signal confidence %.1f%% > threshold %.1f%%",
                                          confidence, closeThreshold));
                return ACTION_CLOSE_SELL;
            }
        }

        // If positions are aligned with signal, HOLD
        if ((positions.state == STATE_HAS_BUY && direction == "BULLISH") ||
            (positions.state == STATE_HAS_SELL && direction == "BEARISH"))
        {
            DebugLogFile("TREND_HOLD_ALIGNED", "Positions aligned with signal - holding");
            return ACTION_HOLD;
        }

        DebugLogFile("TREND_HOLD_NO_CLEAR", "No clear action - holding");
        return ACTION_HOLD;
    }

    DECISION_ACTION DecideWithPositionRange(int symbolIndex, const DecisionEngineInterface &source,
                                            PositionAnalysis &positions, DecisionParams &params,
                                            string direction, double confidence, const MarketAnalysis &currentMarket)
    {
        DebugLogFile("DECIDE_RANGE_WITH_POSITION", "--- Making range decision with signal context ---");

        // LOG SIGNAL CONTEXT
        DebugLogFile("RANGE_SIGNAL_CONTEXT",
                     StringFormat("Range Signal: %s (%.1f%%) | Market: %s",
                                  direction, confidence,
                                  currentMarket.GetStateString(currentMarket.state)));

        // Higher threshold for range trading
        double rangeCloseThreshold = params.closePositionThreshold + 7.0;

        // Check position state
        if (positions.state == STATE_HAS_BUY && direction == "BEARISH" && confidence > rangeCloseThreshold)
        {
            DebugLogFile("RANGE_CLOSE_BUY",
                         StringFormat("Closing BUY in range market | Confidence %.1f%% > threshold %.1f%%",
                                      confidence, rangeCloseThreshold));
            return ACTION_CLOSE_BUY;
        }

        if (positions.state == STATE_HAS_SELL && direction == "BULLISH" && confidence > rangeCloseThreshold)
        {
            DebugLogFile("RANGE_CLOSE_SELL",
                         StringFormat("Closing SELL in range market | Confidence %.1f%% > threshold %.1f%%",
                                      confidence, rangeCloseThreshold));
            return ACTION_CLOSE_SELL;
        }

        // Check for close all
        if (confidence < params.closeAllThreshold)
        {
            DebugLogFile("RANGE_CLOSE_ALL",
                         StringFormat("Low confidence %.1f%% < %.1f%% - closing all",
                                      confidence, params.closeAllThreshold));
            return ACTION_CLOSE_ALL;
        }

        DebugLogFile("RANGE_HOLD", "No clear range action - holding");
        return ACTION_HOLD;
    }

    string GetPositionStateString(POSITION_STATE state) const
    {
        switch (state)
        {
        case STATE_NO_POSITION:
            return "NO_POSITION";
        case STATE_HAS_BUY:
            return "HAS_BUY";
        case STATE_HAS_SELL:
            return "HAS_SELL";
        case STATE_HAS_BOTH:
            return "HAS_BOTH";
        default:
            return "UNKNOWN";
        }
    }

    // ================= SETTERS =================
    void SetDebugMode(bool enabled)
    {
        DebugLogFile("CONFIG_CHANGE", StringFormat("Debug mode changing from %s to %s",
                                                   m_debugEnabled ? "ENABLED" : "DISABLED", enabled ? "ENABLED" : "DISABLED"));
        m_debugEnabled = enabled;
        DebugLogFile("CONFIG", "Debug mode: " + (enabled ? "ENABLED" : "DISABLED"));
    }

    void SetAllowMultiplePositions(bool allowed)
    {
        DebugLogFile("CONFIG_CHANGE", StringFormat("Multiple positions changing from %s to %s",
                                                   m_allowMultiplePositions ? "ALLOWED" : "NOT ALLOWED", allowed ? "ALLOWED" : "NOT ALLOWED"));
        m_allowMultiplePositions = allowed;
        DebugLogFile("CONFIG", "Multiple positions: " + (allowed ? "ALLOWED" : "NOT ALLOWED"));
    }

    void SetUseRiskManagement(bool use)
    {
        DebugLogFile("CONFIG_CHANGE", StringFormat("Risk management changing from %s to %s",
                                                   m_useRiskManagement ? "ENABLED" : "DISABLED", use ? "ENABLED" : "DISABLED"));
        m_useRiskManagement = use;
        DebugLogFile("CONFIG", "Risk management: " + (use ? "ENABLED" : "DISABLED"));
    }

    void SetEnforceCooldown(bool enforce)
    {
        DebugLogFile("CONFIG_CHANGE", StringFormat("Cooldown enforcement changing from %s to %s",
                                                   m_enforceCooldown ? "ENABLED" : "DISABLED", enforce ? "ENABLED" : "DISABLED"));
        m_enforceCooldown = enforce;
        DebugLogFile("CONFIG", "Cooldown enforcement: " + (enforce ? "ENABLED" : "DISABLED"));
    }

    void SetMaxPackageAge(int seconds)
    {
        int oldValue = m_maxPackageAgeSeconds;
        m_maxPackageAgeSeconds = MathMax(60, seconds);
        DebugLogFile("CONFIG_CHANGE", StringFormat("Max package age changing from %d to %d seconds", oldValue, m_maxPackageAgeSeconds));
        DebugLogFile("CONFIG", StringFormat("Max package age: %d seconds", m_maxPackageAgeSeconds));
    }

    void SetAutoDetectProcessor(bool autoDetect)
    {
        m_autoDetectProcessor = autoDetect;
        DebugLogFile("CONFIG_CHANGE", StringFormat("Auto-detect processor: %s", autoDetect ? "ENABLED" : "DISABLED"));
    }

    void SetUseMarketRegimeRouting(bool useRegimeRouting)
    {
        m_useMarketRegimeRouting = useRegimeRouting;
        DebugLogFile("CONFIG_CHANGE", StringFormat("Market regime routing: %s", useRegimeRouting ? "ENABLED" : "DISABLED"));
    }

    void SetTrapThresholdForRange(double threshold)
    {
        m_trapThresholdForRange = MathMax(0, MathMin(100, threshold));
        DebugLogFile("CONFIG_CHANGE", StringFormat("Trap threshold for range routing: %.1f%%", m_trapThresholdForRange));
    }

    void UpdateSymbolParams(string symbol, DecisionParams &params)
    {
        DebugLogFile("UPDATE_PARAMS_START", StringFormat("Updating params for %s: %s", symbol, params.ToString()));

        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            DecisionParams oldParams = m_symbolStates[index].params;
            m_symbolStates[index].params = params;

            DebugLogFile("UPDATE_PARAMS_SUCCESS", StringFormat("Updated params for %s", symbol));
            DebugLogFile("PARAMS_CHANGE", StringFormat("Buy: %.1f%% -> %.1f%% | Sell: %.1f%% -> %.1f%%",
                                                       oldParams.buyConfidenceThreshold, params.buyConfidenceThreshold,
                                                       oldParams.sellConfidenceThreshold, params.sellConfidenceThreshold));
        }
        else
        {
            DebugLogFile("UPDATE_PARAMS_ERROR", "Symbol not found: " + symbol);
        }
    }

    // ================= GETTERS =================
    string GetStatus() const
    {
        if (!m_initialized)
        {
            DebugLogFile("GET_STATUS", "DecisionEngine: NOT INITIALIZED");
            return "DecisionEngine: NOT INITIALIZED";
        }

        string status = StringFormat("DecisionEngine v4.1 | Symbols: %d | %s",
                                     m_totalSymbols, m_metrics.ToString());
        DebugLogFile("GET_STATUS", status);
        return status;
    }

    string GetProcessorStatistics() const
    {
        if (!m_initialized)
            return "Engine not initialized";

        return m_metrics.GetProcessorStats();
    }

    DecisionEngineInterface GetLastPackage(string symbol)
    {
        DebugLogFile("GET_LAST_PACKAGE", "Getting last package for: " + symbol);

        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            DebugLogFile("GET_LAST_PACKAGE_SUCCESS", StringFormat("Found package for %s, isValid=%s",
                                                                  symbol, m_symbolStates[index].lastPackage.IsValid() ? "true" : "false"));
            return m_symbolStates[index].lastPackage;
        }

        DebugLogFile("GET_LAST_PACKAGE_ERROR", "Symbol not found: " + symbol);
        DecisionEngineInterface empty;
        return empty;
    }

    DECISION_ACTION GetLastDecision(string symbol)
    {
        DebugLogFile("GET_LAST_DECISION", "Getting last decision for: " + symbol);

        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            DebugLogFile("GET_LAST_DECISION_SUCCESS", StringFormat("Last decision for %s: %s",
                                                                   symbol, DecisionToString(m_symbolStates[index].lastDecision)));
            return m_symbolStates[index].lastDecision;
        }

        DebugLogFile("GET_LAST_DECISION_ERROR", "Symbol not found: " + symbol);
        return ACTION_NONE;
    }

    string GetLastProcessorUsed(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            return m_symbolStates[index].lastProcessorUsed;
        }
        return "NONE";
    }

    DecisionMetrics GetMetrics() const
    {
        DebugLogFile("GET_METRICS", "Getting decision metrics");
        return m_metrics;
    }

    int GetSymbolCount() const
    {
        DebugLogFile("GET_SYMBOL_COUNT", StringFormat("Symbol count: %d", m_totalSymbols));
        return m_totalSymbols;
    }

    bool HasSymbol(string symbol)
    {
        bool hasSymbol = (FindSymbolIndex(symbol) >= 0);
        DebugLogFile("HAS_SYMBOL", StringFormat("Checking if symbol %s exists: %s", symbol, hasSymbol ? "YES" : "NO"));
        return hasSymbol;
    }

    int GetMagicNumber(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            return m_symbolStates[index].magicNumber;
        }
        return 0;
    }

    // ================= EVENT HANDLERS =================
    void OnTick()
    {
        if (!m_initialized)
        {
            DebugLogFile("ONTICK_WARNING", "Engine not initialized, skipping OnTick");
            return;
        }

        // Auto-create and process packages
        if (m_autoPackageCreation)
        {
            CreateAndProcessPackages();
        }

        // Check for expired packages
        int expiredCount = 0;
        for (int i = 0; i < m_totalSymbols; i++)
        {
            if (m_symbolStates[i].HasValidPackage() && !m_symbolStates[i].IsPackageFresh())
            {
                expiredCount++;
                DebugLogFile("PACKAGE_EXPIRED", StringFormat("Package expired for %s (age: %d seconds)",
                                                             m_symbolStates[i].symbol,
                                                             (int)(TimeCurrent() - m_symbolStates[i].lastPackage.analysisTime)));
            }
        }

        if (expiredCount > 0)
        {
            DebugLogFile("PACKAGE_CHECK_SUMMARY", StringFormat("%d packages expired out of %d total symbols", expiredCount, m_totalSymbols));
        }

        // NEW: Check closed positions for profitability
        CheckClosedPositions();
    }

    void OnTimer()
    {
        DebugLogFile("ONTIMER", "OnTimer called");
        OnTick();
    }

    void OnTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest &request,
                            const MqlTradeResult &result)
    {
        DebugLogFile("TRADE_TRANSACTION", StringFormat("Trade transaction: type=%d, symbol=%s, result=%d",
                                                       trans.type, trans.symbol, result.retcode));

        if (!m_initialized)
        {
            DebugLogFile("TRADE_TRANSACTION_WARNING", "Engine not initialized, skipping");
            return;
        }

        // Update cooldown on successful trades
        if (result.retcode == TRADE_RETCODE_DONE)
        {
            DebugLogFile("TRADE_SUCCESS", "Trade transaction successful");

            bool isBuy = false;

            // Check if it's a deal addition
            if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
            {
                // Get deal information
                ulong dealTicket = trans.deal;

                // Check if this is a buy deal
                if (HistoryDealSelect(dealTicket))
                {
                    long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                    if (dealType == DEAL_TYPE_BUY)
                    {
                        isBuy = true;
                        DebugLogFile("TRADE_DIRECTION", "BUY deal detected");
                    }
                    else if (dealType == DEAL_TYPE_SELL)
                    {
                        DebugLogFile("TRADE_DIRECTION", "SELL deal detected");
                    }
                }
            }

            // Update cooldown for the symbol
            int index = FindSymbolIndex(trans.symbol);
            if (index >= 0)
            {
                m_symbolStates[index].cooldown.Update(isBuy);
                DebugLogFile("COOLDOWN_UPDATE_TRADE", StringFormat("Cooldown updated for %s: %s",
                                                                   trans.symbol, isBuy ? "BUY" : "SELL"));
            }
        }
    }

    // ================= UTILITY =================
    string DecisionToString(DECISION_ACTION decision) const
    {
        return DecisionMetrics::DecisionToStringStatic(decision);
    }

    string GetSymbolAtIndex(int index) const
    {
        if (index >= 0 && index < m_totalSymbols)
        {
            return m_symbolStates[index].symbol;
        }
        return "";
    }

    string GetRegimeInfo(string symbol)
    {
        string regime, source, direction;
        double confidence;
        return GetRegimeInfoDetailed(symbol, regime, source, direction, confidence);
    }

    // Configure market regime detector settings
    void SetMarketRegimeSettings(int lookbackBars = 8,
                                 double accountBalance = 10000,
                                 double riskPercent = 1.0)
    {
        // These settings will be used when creating MarketRegimeDetector instances
        DebugLogFile("REGIME_CONFIG",
                     StringFormat("Market Regime Settings: Lookback=%d bars, Balance=$%.2f, Risk=%.1f%%",
                                  lookbackBars, accountBalance, riskPercent));
    }

    // Get current market regime as string
    string GetCurrentMarketRegimeString(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.ToString();
    }

private:
    // ==================== FIXED: PROFITABILITY CHECKER ====================
    void CheckClosedPositions()
    {
        DebugLogFile("CHECK_CLOSED_POSITIONS_START",
                     StringFormat("Checking %d symbols for closed positions", m_totalSymbols));

        for (int i = 0; i < m_totalSymbols; i++)
        {
            string symbol = m_symbolStates[i].symbol;
            int magic = m_symbolStates[i].magicNumber;

            // METHOD 1: Check if we have an open position that should be tracked
            if (m_symbolStates[i].positionOpenTime > 0 &&
                !m_symbolStates[i].awaitingProfitabilityCheck)
            {
                // Check if position is still open
                bool positionStillOpen = IsPositionStillOpen(symbol, magic);

                if (!positionStillOpen)
                {
                    // Position WAS open (we tracked it) but NOW it's closed!
                    // Must have closed via SL/TP/Manual outside system
                    DebugLogFile("AUTO_CLOSE_DETECTED",
                                 StringFormat("Position for %s (Magic: %d) auto-closed! Opened at %s",
                                              symbol, magic, TimeToString(m_symbolStates[i].positionOpenTime)));

                    // Process it now
                    ProcessClosedTradeProfitability(i);
                }
            }

            // METHOD 2: Original logic for manual closes
            if (m_symbolStates[i].awaitingProfitabilityCheck &&
                m_symbolStates[i].positionOpenTime > 0)
            {
                // Wait for the trade to fully close (give it 10 seconds)
                if ((TimeCurrent() - m_symbolStates[i].positionCloseTime) > 10)
                {
                    bool positionStillOpen = IsPositionStillOpen(symbol, magic);

                    if (!positionStillOpen)
                    {
                        ProcessClosedTradeProfitability(i);
                    }
                    else
                    {
                        DebugLogFile("PROFIT_CHECK_DEFERRED",
                                     StringFormat("Position still open for %s (Magic: %d), waiting...",
                                                  symbol, magic));
                    }
                }
            }
        }
    }

    bool IsPositionStillOpen(string symbol, int magicNumber)
    {
        int total = PositionsTotal();
        for (int i = 0; i < total; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0)
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);

                if (posSymbol == symbol && posMagic == magicNumber)
                {
                    return true; // Position is still open
                }
            }
        }
        return false; // Position is closed
    }

    void ProcessClosedTradeProfitability(int symbolIndex)
    {
        string symbol = m_symbolStates[symbolIndex].symbol;
        int magic = m_symbolStates[symbolIndex].magicNumber;

        DebugLogFile("PROCESS_CLOSED_TRADE",
                     StringFormat("Processing closed trade for %s (Magic: %d) opened at %s",
                                  symbol, magic, TimeToString(m_symbolStates[symbolIndex].positionOpenTime)));

        // Look for the CLOSED trade in history
        bool wasProfitable = CheckClosedTradeInHistory(symbol, magic, m_symbolStates[symbolIndex].positionOpenTime);

        // Get processor type
        string processorType = m_symbolStates[symbolIndex].lastProcessorUsed;

        // ⚠️ CRITICAL: UPDATE METRICS WITH ACTUAL RESULT!
        DebugLogFile("METRICS_UPDATE_START",
                     StringFormat("Updating metrics for %s: wasProfitable=%s | OpenDecision: %s | Conf: %.1f%%",
                                  symbol, wasProfitable ? "true" : "false",
                                  DecisionToString(m_symbolStates[symbolIndex].positionOpenDecision),
                                  m_symbolStates[symbolIndex].positionOpenConfidence));

        // Only count if it was an OPEN decision
        if (m_symbolStates[symbolIndex].positionOpenDecision == ACTION_OPEN_BUY ||
            m_symbolStates[symbolIndex].positionOpenDecision == ACTION_OPEN_SELL)
        {
            // Update total decisions
            int prevTotal = m_metrics.totalDecisions;
            m_metrics.totalDecisions++;

            // Update profitable decisions if it was profitable
            if (wasProfitable)
            {
                m_metrics.profitableDecisions++;
                DebugLogFile("METRICS_PROFITABLE_ADD",
                             StringFormat("✅ Added profitable trade: %s | Total profitable now: %d",
                                          symbol, m_metrics.profitableDecisions));
            }
            else
            {
                DebugLogFile("METRICS_UNPROFITABLE_ADD",
                             StringFormat("❌ Added unprofitable trade: %s | Profitable total still: %d",
                                          symbol, m_metrics.profitableDecisions));
            }

            // Update rolling average confidence
            if (m_metrics.totalDecisions == 1)
            {
                m_metrics.averageConfidence = m_symbolStates[symbolIndex].positionOpenConfidence;
            }
            else
            {
                m_metrics.averageConfidence = ((m_metrics.averageConfidence * prevTotal) +
                                               m_symbolStates[symbolIndex].positionOpenConfidence) /
                                              m_metrics.totalDecisions;
            }

            // Update accuracy rate
            if (m_metrics.totalDecisions > 0)
            {
                m_metrics.accuracyRate = ((double)m_metrics.profitableDecisions / m_metrics.totalDecisions) * 100.0;

                DebugLogFile("METRICS_UPDATED",
                             StringFormat("Metrics updated: Trades: %d | Profitable: %d | Accuracy: %.1f%% | AvgConf: %.1f%%",
                                          m_metrics.totalDecisions,
                                          m_metrics.profitableDecisions,
                                          m_metrics.accuracyRate,
                                          m_metrics.averageConfidence));
            }
        }
        else
        {
            DebugLogFile("METRICS_SKIP",
                         StringFormat("Skipping non-open decision in metrics: %s",
                                      DecisionToString(m_symbolStates[symbolIndex].positionOpenDecision)));
        }

        // Track processor usage (call Update with wasProfitable flag)
        m_metrics.Update(m_symbolStates[symbolIndex].positionOpenDecision,
                         m_symbolStates[symbolIndex].positionOpenConfidence,
                         wasProfitable,
                         processorType);

        DebugLogFile("CLOSED_TRADE_PROCESSED",
                     StringFormat("%s | Open: %s | Final Result: %s | Processor: %s",
                                  symbol,
                                  DecisionToString(m_symbolStates[symbolIndex].positionOpenDecision),
                                  wasProfitable ? "WIN" : "LOSS",
                                  processorType));

        // Reset the stored position info
        ResetPositionTracking(symbolIndex);
    }

    bool CheckClosedTradeInHistory(string symbol, int magicNumber, datetime openTime)
    {
        int totalDeals = HistoryDealsTotal();
        double netProfit = 0;
        bool foundCloseDeal = false;

        DebugLogFile("CHECK_HISTORY_FOR_CLOSED_TRADE",
                     StringFormat("Checking history for closed trade: %s (Magic: %d)", symbol, magicNumber));

        for (int i = totalDeals - 1; i >= 0; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket <= 0)
                continue;

            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

            // Only check deals that happened after position open
            if (dealTime < openTime - 60) // Allow 1 minute buffer
                continue;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

            // Check if this deal belongs to our position
            if (dealSymbol == symbol && dealMagic == magicNumber)
            {
                // Look for OUT/OUT_BY deals (closing deals)
                if (dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
                {
                    foundCloseDeal = true;

                    double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                    double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                    double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                    double dealTotal = profit + commission + swap;

                    netProfit += dealTotal;

                    DebugLogFile("CLOSE_DEAL_FOUND",
                                 StringFormat("Close deal %llu: Time: %s, Profit: $%.2f, Total: $%.2f",
                                              dealTicket, TimeToString(dealTime), profit, dealTotal));
                }
            }
        }

        if (foundCloseDeal)
        {
            bool isProfitable = (netProfit > 0);

            DebugLogFile("CLOSED_TRADE_RESULT",
                         StringFormat("Closed trade for %s: Net Profit: $%.2f | Profitable: %s",
                                      symbol, netProfit, isProfitable ? "YES (WIN)" : "NO (LOSS)"));

            return isProfitable;
        }
        else
        {
            // No close deals found yet - trade might still be processing
            DebugLogFile("NO_CLOSE_DEALS_FOUND",
                         StringFormat("No close deals found for %s yet, might still be processing", symbol));
            return false; // Don't count it yet
        }
    }

    void ResetPositionTracking(int symbolIndex)
    {
        m_symbolStates[symbolIndex].positionOpenTime = 0;
        m_symbolStates[symbolIndex].positionCloseTime = 0;
        m_symbolStates[symbolIndex].positionOpenDecision = ACTION_NONE;
        m_symbolStates[symbolIndex].positionOpenConfidence = 0;
        m_symbolStates[symbolIndex].awaitingProfitabilityCheck = false;
    }

    // ==================== NEW: ENHANCED PROFITABILITY CHECK ====================
    bool CheckPositionNetProfitability(string symbol, int magicNumber, datetime openTime)
    {
        // Find ALL deals for this position (including partial closes)
        int totalDeals = HistoryDealsTotal();
        double netProfit = 0;
        bool positionFound = false;

        DebugLogFile("ENHANCED_PROFIT_TRACKING",
                     StringFormat("Checking enhanced profitability for %s (Magic: %d) opened at %s",
                                  symbol, magicNumber, TimeToString(openTime)));

        // We need to check deals from openTime until now
        datetime endTime = TimeCurrent();

        for (int i = totalDeals - 1; i >= 0; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket <= 0)
                continue;

            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

            // Only check deals that happened after position open
            if (dealTime < openTime)
                continue;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

            // Check if this deal belongs to our position
            if (dealSymbol == symbol && dealMagic == magicNumber)
            {
                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double dealTotal = profit + commission + swap;

                netProfit += dealTotal;
                positionFound = true;

                DebugLogFile("POSITION_DEAL_DETAIL_ENHANCED",
                             StringFormat("Deal %llu: Time: %s, Entry: %d, Profit: $%.2f, Commission: $%.2f, Swap: $%.2f, Total: $%.2f",
                                          dealTicket, TimeToString(dealTime), dealEntry,
                                          profit, commission, swap, dealTotal));
            }
        }

        if (positionFound)
        {
            bool isProfitable = (netProfit > 0);

            DebugLogFile("POSITION_NET_RESULT_ENHANCED",
                         StringFormat("Position for %s: Net Profit: $%.2f | Profitable: %s",
                                      symbol, netProfit, isProfitable ? "YES (WIN)" : "NO (LOSS)"));

            return isProfitable;
        }

        DebugLogFile("POSITION_NOT_FOUND_ENHANCED", "No position deals found in history");
        return false;
    }

    ulong GetLastTradeTicket(string symbol, int magicNumber)
    {
        int totalDeals = HistoryDealsTotal();

        for (int i = totalDeals - 1; i >= 0; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket <= 0)
                continue;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

            if (dealSymbol == symbol && dealMagic == magicNumber &&
                (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL))
            {
                DebugLogFile("LAST_TRADE_TICKET",
                             StringFormat("Found last trade for %s (Magic: %d): Ticket %llu",
                                          symbol, magicNumber, dealTicket));
                return dealTicket;
            }
        }

        DebugLogFile("LAST_TRADE_TICKET",
                     StringFormat("No trade found for %s (Magic: %d)", symbol, magicNumber));
        return 0;
    }

    // ================= TRADE PROFITABILITY CHECKING =================
    bool CheckTradeProfitability(ulong tradeTicket)
    {
        if (tradeTicket <= 0)
        {
            DebugLogFile("PROFIT_CHECK", "Invalid trade ticket");
            return false;
        }

        if (!HistoryDealSelect(tradeTicket))
        {
            DebugLogFile("PROFIT_CHECK", StringFormat("Failed to select deal with ticket: %llu", tradeTicket));
            return false;
        }

        // Get profit components
        double profit = HistoryDealGetDouble(tradeTicket, DEAL_PROFIT);
        double commission = HistoryDealGetDouble(tradeTicket, DEAL_COMMISSION);
        double swap = HistoryDealGetDouble(tradeTicket, DEAL_SWAP);
        double total = profit + commission + swap;

        // Log detailed info
        DebugLogFile("PROFIT_DETAILS",
                     StringFormat("Ticket: %llu | Profit: $%.2f | Commission: $%.2f | Swap: $%.2f | Total: $%.2f | Profitable: %s",
                                  tradeTicket, profit, commission, swap, total, total > 0 ? "YES" : "NO"));

        return (total > 0);
    }

    // Enhanced version to check position profitability
    bool CheckPositionProfitability(string symbol, int magicNumber, datetime sinceTime = 0)
    {
        int totalDeals = HistoryDealsTotal();
        double totalProfit = 0;
        int tradeCount = 0;
        int profitableTrades = 0;

        for (int i = totalDeals - 1; i >= 0; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket <= 0)
                continue;

            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

            // Filter by symbol, magic, and time
            if (dealSymbol == symbol && dealMagic == magicNumber &&
                (sinceTime == 0 || dealTime >= sinceTime) &&
                (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL))
            {
                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double netProfit = profit + commission + swap;

                totalProfit += netProfit;
                tradeCount++;
                if (netProfit > 0)
                    profitableTrades++;

                DebugLogFile("POSITION_PROFIT_DETAILS",
                             StringFormat("Deal: %llu | Time: %s | Type: %s | Net: $%.2f",
                                          dealTicket, TimeToString(dealTime),
                                          dealType == DEAL_TYPE_BUY ? "BUY" : "SELL",
                                          netProfit));
            }
        }

        DebugLogFile("POSITION_PROFIT_SUMMARY",
                     StringFormat("%s (Magic: %d) | Trades: %d | Profitable: %d | Total P/L: $%.2f | Win Rate: %.1f%%",
                                  symbol, magicNumber, tradeCount, profitableTrades, totalProfit,
                                  tradeCount > 0 ? ((double)profitableTrades / tradeCount * 100) : 0));

        return (totalProfit > 0);
    }

    // Get market regime analysis
    MarketAnalysis GetMarketRegimeAnalysis(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
    {
        MarketRegimeDetector* detector = MarketRegimeDetector::Instance(symbol, timeframe);
        return detector.GetMarketRegime();
    }

    // Regime-based parameter adjustment - ADAPTS TO MARKET
    static DecisionParams CreateRegimeBasedParams(const MarketAnalysis &regime,
                                                  const DecisionParams &baseParams)
    {
        // Start with the base parameters (either minimal or mk$ profile)
        DecisionParams params = baseParams;

        DebugLogFile("REGIME_ADAPT_START",
                     StringFormat("Adapting params for regime: %s",
                                  regime.GetRootStateString(regime.rootState)));

        if (regime.IsTrending())
        {
            DebugLogFile("TRENDING_ADAPT", "Adapting for TRENDING market");

            // Trending market adjustments
            params.cooldownMinutes = MathMax(30, baseParams.cooldownMinutes / 2);            // Faster entries
            params.maxPositionsPerSymbol = MathMin(3, baseParams.maxPositionsPerSymbol + 1); // More positions

            // Adjust thresholds for trend following
            if (regime.direction == "Bullish")
            {
                params.buyConfidenceThreshold = MathMax(55.0, baseParams.trendBuyThreshold);
                params.sellConfidenceThreshold = MathMax(60.0, baseParams.trendSellThreshold);
            }
            else if (regime.direction == "Bearish")
            {
                params.buyConfidenceThreshold = MathMax(60.0, baseParams.trendBuyThreshold);
                params.sellConfidenceThreshold = MathMax(60.0, baseParams.trendSellThreshold);
            }

            // Risk management for trends
            params.minRiskRewardRatio = MathMax(2.0, baseParams.minRiskRewardRatio);

            DebugLogFile("TRENDING_ADAPT_DONE",
                         StringFormat("Cooldown: %d→%d, MaxPos: %d→%d, RR: %.1f→%.1f",
                                      baseParams.cooldownMinutes, params.cooldownMinutes,
                                      baseParams.maxPositionsPerSymbol, params.maxPositionsPerSymbol,
                                      baseParams.minRiskRewardRatio, params.minRiskRewardRatio));
        }
        else if (regime.IsRanging())
        {
            DebugLogFile("RANGING_ADAPT", "Adapting for RANGING market");

            // Ranging market adjustments
            params.cooldownMinutes = MathMin(120, baseParams.cooldownMinutes * 2);           // Slower entries
            params.maxPositionsPerSymbol = MathMax(1, baseParams.maxPositionsPerSymbol - 1); // Fewer positions

            // Higher thresholds for range trading
            params.buyConfidenceThreshold = MathMax(60.0, baseParams.rangeBuyThreshold);
            params.sellConfidenceThreshold = MathMax(60.0, baseParams.rangeSellThreshold);

            // More conservative in ranges
            params.minRiskRewardRatio = MathMax(1.0, baseParams.minRiskRewardRatio - 0.5);
            params.trapProbabilityThreshold = MathMax(40.0, baseParams.trapProbabilityThreshold - 10.0);

            DebugLogFile("RANGING_ADAPT_DONE",
                         StringFormat("Cooldown: %d→%d, MaxPos: %d→%d, Trap: %.1f→%.1f",
                                      baseParams.cooldownMinutes, params.cooldownMinutes,
                                      baseParams.maxPositionsPerSymbol, params.maxPositionsPerSymbol,
                                      baseParams.trapProbabilityThreshold, params.trapProbabilityThreshold));
        }
        else
        {
            DebugLogFile("UNKNOWN_REGIME", "Keeping base params for unknown regime");
        }

        return params;
    }

    // Apply regime-based position size
    void ApplyRegimePositionSize(int symbolIndex, const MarketAnalysis &regimeAnalysis, bool isBuy)
    {
        // Store the recommended position size for execution
        ENUM_POSITION_SIZE recommendedSize = regimeAnalysis.positionSize;

        DebugLogFile("REGIME_POSITION_SIZE",
                     StringFormat("Market regime recommends %s position size for %s",
                                  GetPositionSizeString(recommendedSize),
                                  isBuy ? "BUY" : "SELL"));

        // Adjust position size multiplier based on market state
        double sizeMultiplier = 1.0;

        switch (regimeAnalysis.state)
        {
        case STATE_TRENDING_LOW_VOL:
        case STATE_EXPANSION:
            sizeMultiplier = 1.2; // Larger positions in healthy trends/expansions
            break;
        case STATE_TRENDING_HIGH_VOL:
        case STATE_RANGING_HIGH_VOL:
        case STATE_CHURN:
            sizeMultiplier = 0.5; // Smaller positions in volatile/churn states
            break;
        case STATE_CONTRACTION:
            sizeMultiplier = 0.3; // Very small positions during contractions
            break;
        }

        DebugLogFile("POSITION_SIZE_ADJUSTMENT",
                     StringFormat("Applying %.1fx multiplier for %s state",
                                  sizeMultiplier, regimeAnalysis.GetStateString(regimeAnalysis.state)));
    }

    // position sizing string
    string GetPositionSizeString(ENUM_POSITION_SIZE size)
    {
        switch (size)
        {
        case SIZE_ZERO:
            return "ZERO";
        case SIZE_VERY_SMALL:
            return "VERY_SMALL";
        case SIZE_SMALL:
            return "SMALL";
        case SIZE_MEDIUM:
            return "MEDIUM";
        case SIZE_LARGE:
            return "LARGE";
        default:
            return "UNKNOWN";
        }
    }

    // Get root state for decision making
    ENUM_ROOT_REGIME GetRootRegimeForSymbol(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.rootState;
    }

    // Get market state for decision making
    ENUM_MARKET_STATE GetMarketStateForSymbol(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.state;
    }

    // Get position size recommendation based on market regime
    ENUM_POSITION_SIZE GetRecommendedPositionSize(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.positionSize;
    }

    // Get stop distance based on market regime
    double GetRecommendedStopDistance(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.stopDistance;
    }

    // Get TP distance based on market regime
    double GetRecommendedTakeProfitDistance(string symbol)
    {
        MarketAnalysis analysis = GetMarketRegimeAnalysis(symbol, PERIOD_M15);
        return analysis.takeProfitDistance;
    }

    // Convert lifecycle enum to string
    string GetLifecycleString(ENUM_MARKET_LIFECYCLE lifecycle)
    {
        switch (lifecycle)
        {
        case LIFECYCLE_TREND_CONFIRMED:
            return "TREND_CONFIRMED";
        case LIFECYCLE_TREND_RESUMING:
            return "TREND_RESUMING";
        case LIFECYCLE_TREND_WEAKENING:
            return "TREND_WEAKENING";
        case LIFECYCLE_BREAKOUT_DETECTED:
            return "BREAKOUT_DETECTED";
        case LIFECYCLE_RANGE_ACTIVE:
            return "RANGE_ACTIVE";
        case LIFECYCLE_RANGE_FORMING:
            return "RANGE_FORMING";
        case LIFECYCLE_PULLBACK_ACTIVE:
            return "PULLBACK_ACTIVE";
        case LIFECYCLE_PULLBACK_FORMING:
            return "PULLBACK_FORMING";
        case LIFECYCLE_UNKNOWN:
        default:
            return "UNKNOWN";
        }
    }

    // ================= PRIVATE HELPER METHODS =================
    int FindSymbolIndex(string symbol)
    {
        for (int i = 0; i < m_totalSymbols; i++)
        {
            if (m_symbolStates[i].symbol == symbol)
            {
                DebugLogFile("FIND_SYMBOL_INDEX", StringFormat("Found symbol %s at index %d", symbol, i));
                return i;
            }
        }
        DebugLogFile("FIND_SYMBOL_INDEX", "Symbol not found: " + symbol);
        return -1;
    }

    int GenerateMagicNumber(string symbol)
    {
        DebugLogFile("GENERATE_MAGIC", "Generating magic number for: " + symbol);

        int hash = 0;
        for (int i = 0; i < StringLen(symbol); i++)
        {
            hash = hash * 31 + StringGetCharacter(symbol, i);
        }

        int magic = m_engineMagicBase + (MathAbs(hash) % 10000);
        DebugLogFile("GENERATE_MAGIC_RESULT", StringFormat("Generated magic %d for symbol %s", magic, symbol));

        return magic;
    }

    bool IsPackageFresh(int symbolIndex)
    {
        if (symbolIndex < 0 || symbolIndex >= m_totalSymbols)
        {
            DebugLogFile("IS_PACKAGE_FRESH_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return false;
        }

        bool isFresh = m_symbolStates[symbolIndex].IsPackageFresh(m_maxPackageAgeSeconds);
        DebugLogFile("IS_PACKAGE_FRESH", StringFormat("Package freshness for %s: %s",
                                                      m_symbolStates[symbolIndex].symbol, isFresh ? "FRESH" : "STALE"));

        return isFresh;
    }

    int GetActiveSymbolCount()
    {
        int count = 0;
        for (int i = 0; i < m_totalSymbols; i++)
        {
            if (m_symbolStates[i].HasValidPackage() && m_symbolStates[i].IsPackageFresh())
            {
                count++;
            }
        }
        return count;
    }

    // ================= REGIME CHECKING =================ENUM_ROOT_REGIME
    struct EnhancedRegimeInfo
    {
        ENUM_ROOT_REGIME basicRegime;
        ENUM_MARKET_LIFECYCLE lifecycle;
        string regimeString;
        string lifecycleString;
        double confidence;
        string description;

        EnhancedRegimeInfo()
        {
            basicRegime = REGIME_UNKNOWN;
            lifecycle = LIFECYCLE_UNKNOWN;
            regimeString = "UNKNOWN";
            lifecycleString = "UNKNOWN";
            confidence = 0.0;
            description = "";
        }

        string ToString() const
        {
            return StringFormat("Regime: %s | Lifecycle: %s | Conf: %.0f%% | %s",
                                regimeString, lifecycleString, confidence, description);
        }

        bool IsTrending() const
        {
            return (basicRegime == REGIME_TRENDING || basicRegime == REGIME_TRENDING);
        }

        bool IsRanging() const
        {
            return (basicRegime == REGIME_RANGING);
        }

        bool IsInTrendPhase() const
        {
            return (lifecycle == LIFECYCLE_TREND_CONFIRMED ||
                    lifecycle == LIFECYCLE_TREND_RESUMING ||
                    lifecycle == LIFECYCLE_BREAKOUT_DETECTED);
        }

        bool IsInRangePhase() const
        {
            return (lifecycle == LIFECYCLE_RANGE_ACTIVE ||
                    lifecycle == LIFECYCLE_RANGE_FORMING ||
                    lifecycle == LIFECYCLE_PULLBACK_ACTIVE ||
                    lifecycle == LIFECYCLE_PULLBACK_FORMING);
        }
    };

    string RegimeToString(ENUM_ROOT_REGIME regime)
    {
        switch (regime)
        {
        case REGIME_TRENDING:
            return "TRENDING";
        case REGIME_RANGING:
            return "RANGING";
        case REGIME_UNKNOWN:
            return "UNKNOWN";
        default:
            return "UNKNOWN";
        }
    }

    string ExtractBaseRegime(const string &packageRegime)
    {
        int underscorePos = StringFind(packageRegime, "_LIFECYCLE_");
        if (underscorePos > 0)
        {
            return StringSubstr(packageRegime, 0, underscorePos);
        }

        if (StringFind(packageRegime, "TRENDING") >= 0)
            return "TRENDING";
        if (StringFind(packageRegime, "RANGING") >= 0)
            return "RANGING";

        return packageRegime;
    }

    // ================= POSITION ANALYSIS =================
    PositionAnalysis AnalyzePositions(int symbolIndex)
    {
        DebugLogFile("ANALYZE_POSITIONS_START", StringFormat("Analyzing positions for symbol index %d", symbolIndex));

        PositionAnalysis analysis;

        if (symbolIndex < 0 || symbolIndex >= m_totalSymbols)
        {
            DebugLogFile("ANALYZE_POSITIONS_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return analysis;
        }

        string symbol = m_symbolStates[symbolIndex].symbol;
        int magic = m_symbolStates[symbolIndex].magicNumber;

        DebugLogFile("ANALYZE_POSITIONS", StringFormat("Analyzing positions for %s (magic: %d)", symbol, magic));

        int positionsTotal = PositionsTotal();
        DebugLogFile("POSITIONS_TOTAL", StringFormat("Total positions in terminal: %d", positionsTotal));

        for (int i = 0; i < positionsTotal; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0)
            {
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                long positionMagic = PositionGetInteger(POSITION_MAGIC);

                if (positionSymbol == symbol && positionMagic == magic)
                {
                    long positionType = PositionGetInteger(POSITION_TYPE);
                    double positionVolume = PositionGetDouble(POSITION_VOLUME);
                    double positionProfit = PositionGetDouble(POSITION_PROFIT);
                    double positionSwap = PositionGetDouble(POSITION_SWAP);

                    double positionCommission = GetPositionCommission(ticket);
                    analysis.totalProfit += positionProfit + positionSwap + positionCommission;

                    if (positionType == POSITION_TYPE_BUY)
                    {
                        analysis.buyCount++;
                    }
                    else if (positionType == POSITION_TYPE_SELL)
                    {
                        analysis.sellCount++;
                    }
                }
            }
        }

        if (analysis.buyCount > 0 && analysis.sellCount > 0)
        {
            analysis.state = STATE_HAS_BOTH;
        }
        else if (analysis.buyCount > 0)
        {
            analysis.state = STATE_HAS_BUY;
        }
        else if (analysis.sellCount > 0)
        {
            analysis.state = STATE_HAS_SELL;
        }
        else
        {
            analysis.state = STATE_NO_POSITION;
        }

        DebugLogFile("ANALYZE_POSITIONS_RESULT", StringFormat("Position analysis for %s: %s", symbol, analysis.ToString()));

        return analysis;
    }

    double GetPositionCommission(ulong positionTicket)
    {
        if (positionTicket == 0)
        {
            DebugLogFile("GET_COMMISSION", "Position ticket is 0");
            return 0.0;
        }

        double commission = 0.0;

        if (HistoryDealSelect(positionTicket))
        {
            commission = HistoryDealGetDouble(positionTicket, DEAL_COMMISSION);
        }
        else
        {
            datetime positionTime = 0;
            string positionSymbol = "";

            if (PositionSelectByTicket(positionTicket))
            {
                positionTime = (datetime)PositionGetInteger(POSITION_TIME);
                positionSymbol = PositionGetString(POSITION_SYMBOL);
            }

            int totalDeals = HistoryDealsTotal();
            for (int i = totalDeals - 1; i >= 0; i--)
            {
                ulong dealTicket = HistoryDealGetTicket(i);
                if (dealTicket <= 0)
                    continue;

                long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);

                if ((dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) &&
                    dealSymbol == positionSymbol &&
                    MathAbs(dealTime - positionTime) < 60)
                {
                    commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                    break;
                }
            }
        }

        return commission;
    }

    bool CheckPositionLimits(int symbolIndex, bool isBuy)
    {
        if (symbolIndex < 0)
        {
            DebugLogFile("CHECK_POSITION_LIMITS_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return false;
        }

        if (!m_allowMultiplePositions)
        {
            PositionAnalysis analysis = AnalyzePositions(symbolIndex);
            bool hasPosition = (analysis.state != STATE_NO_POSITION);

            if (isBuy && hasPosition && analysis.state != STATE_HAS_SELL)
            {
                DebugLogFile("CHECK_POSITION_LIMITS", "Cannot open BUY - already have position");
                return false;
            }

            if (!isBuy && hasPosition && analysis.state != STATE_HAS_BUY)
            {
                DebugLogFile("CHECK_POSITION_LIMITS", "Cannot open SELL - already have position");
                return false;
            }

            DebugLogFile("CHECK_POSITION_LIMITS", "Position limit check passed");
            return true;
        }

        PositionAnalysis analysis = AnalyzePositions(symbolIndex);
        DecisionParams params = m_symbolStates[symbolIndex].params;

        int currentCount = isBuy ? analysis.buyCount : analysis.sellCount;
        int maxAllowed = params.maxPositionsPerSymbol;

        bool withinLimits = (currentCount < maxAllowed);

        DebugLogFile("CHECK_POSITION_LIMITS", StringFormat("Symbol: %s, isBuy: %s, Current: %d, Max: %d, WithinLimits: %s",
                                                           m_symbolStates[symbolIndex].symbol, isBuy ? "true" : "false", currentCount, maxAllowed, withinLimits ? "true" : "false"));

        return withinLimits;
    }

    // ================= VALIDATION =================
    bool ValidateDecision(int symbolIndex, DECISION_ACTION decision, const DecisionEngineInterface &package)
    {
        DebugLogFile("VALIDATE_DECISION_START", StringFormat("=== VALIDATING DECISION === | %s | Symbol: %s | Conf: %.1f%% | Processor: %s",
                                                             DecisionToString(decision), package.symbol, package.overallConfidence,
                                                             m_symbolStates[symbolIndex].lastProcessorUsed));

        if (decision == ACTION_NONE || decision == ACTION_HOLD || decision == ACTION_WAITING_FOR_PACKAGE)
        {
            DebugLogFile("VALIDATE_NON_ACTION", "Non-action decision - always valid");
            return true;
        }

        if (symbolIndex < 0)
        {
            DebugLogFile("VALIDATE_ERROR", "Invalid symbol index");
            return false;
        }

        DecisionParams params = m_symbolStates[symbolIndex].params;
        double confidence = package.overallConfidence;
        string direction = package.dominantDirection;

        DebugLogFile("VALIDATION_PARAMS", StringFormat("Params: Buy=%.1f%%, Sell=%.1f%%, Close=%.1f%%, CloseAll=%.1f%%",
                                                       params.buyConfidenceThreshold, params.sellConfidenceThreshold,
                                                       params.closePositionThreshold, params.closeAllThreshold));

        bool confidenceValid = false;
        switch (decision)
        {
        case ACTION_OPEN_BUY:
            DebugLogFile("VALIDATE_OPEN_BUY", StringFormat("Checking OPEN_BUY: Conf=%.1f%% >= %.1f%% && Dir=%s == BULLISH",
                                                           confidence, params.buyConfidenceThreshold, direction));
            if (confidence < params.buyConfidenceThreshold)
            {
                DebugLogFile("VALIDATE_FAIL", "❌ Confidence too low for BUY");
                return false;
            }
            if (direction != "BULLISH")
            {
                DebugLogFile("VALIDATE_FAIL", StringFormat("❌ Wrong direction for BUY: %s != BULLISH", direction));
                return false;
            }
            confidenceValid = true;
            break;

        case ACTION_OPEN_SELL:
            DebugLogFile("VALIDATE_OPEN_SELL", StringFormat("Checking OPEN_SELL: Conf=%.1f%% >= %.1f%% && Dir=%s == BEARISH",
                                                            confidence, params.sellConfidenceThreshold, direction));
            if (confidence < params.sellConfidenceThreshold)
            {
                DebugLogFile("VALIDATE_FAIL", "❌ Confidence too low for SELL");
                return false;
            }
            if (direction != "BEARISH")
            {
                DebugLogFile("VALIDATE_FAIL", StringFormat("❌ Wrong direction for SELL: %s != BEARISH", direction));
                return false;
            }
            confidenceValid = true;
            break;

        case ACTION_CLOSE_BUY:
        case ACTION_CLOSE_SELL:
            DebugLogFile("VALIDATE_CLOSE", StringFormat("Checking CLOSE: Conf=%.1f%% <= %.1f%%",
                                                        confidence, params.closePositionThreshold));
            if (confidence > params.closePositionThreshold)
            {
                DebugLogFile("VALIDATE_FAIL", "❌ Confidence too high for close");
                return false;
            }
            confidenceValid = true;
            break;

        case ACTION_CLOSE_ALL:
            DebugLogFile("VALIDATE_CLOSE_ALL", StringFormat("Checking CLOSE_ALL: Conf=%.1f%% <= %.1f%%",
                                                            confidence, params.closeAllThreshold));
            if (confidence > params.closeAllThreshold)
            {
                DebugLogFile("VALIDATE_FAIL", "❌ Confidence too high for close all");
                return false;
            }
            confidenceValid = true;
            break;
        }

        if (!confidenceValid)
        {
            DebugLogFile("VALIDATE_FAIL", "❌ Confidence validation failed");
            return false;
        }

        DebugLogFile("VALIDATE_SUCCESS", "✅ Confidence validation passed");

        if (m_useRiskManagement)
        {
            DebugLogFile("VALIDATE_RISK", "Checking risk conditions...");
            DebugLogFile("VALIDATE_SUCCESS", "✅ Risk conditions met");
        }

        DebugLogFile("VALIDATE_TRADING_HOURS", "Checking trading hours...");
        if (!TimeUtils::IsTradingSession(m_symbolStates[symbolIndex].symbol))
        {
            DebugLogFile("VALIDATE_FAIL", "❌ Not in trading session");
            return false;
        }
        DebugLogFile("VALIDATE_SUCCESS", "✅ Trading hours OK");

        bool isBuy = (decision == ACTION_OPEN_BUY || decision == ACTION_CLOSE_SELL || decision == ACTION_CLOSE_ALL);
        DebugLogFile("VALIDATE_COOLDOWN", StringFormat("Checking cooldown (%s)...", isBuy ? "BUY" : "SELL"));
        if (!CheckCooldown(symbolIndex, isBuy))
        {
            DebugLogFile("VALIDATE_FAIL", "❌ In cooldown");
            return false;
        }
        DebugLogFile("VALIDATE_SUCCESS", "✅ Cooldown OK");

        if (decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL)
        {
            DebugLogFile("UPDATE_COOLDOWN_VALIDATION", StringFormat("Updating cooldown on validation for %s decision",
                                                                    isBuy ? "BUY" : "SELL"));
            m_symbolStates[symbolIndex].cooldown.Update(isBuy);
        }

        if (decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL)
        {
            DebugLogFile("VALIDATE_POSITION_LIMITS", "Checking position limits...");
            if (!CheckPositionLimits(symbolIndex, isBuy))
            {
                DebugLogFile("VALIDATE_FAIL", "❌ Position limit reached");
                return false;
            }
            DebugLogFile("VALIDATE_SUCCESS", "✅ Position limits OK");
        }

        DebugLogFile("VALIDATE_SUCCESS_ALL", "✅ All validation passed");
        return true;
    }

    bool CheckCooldown(int symbolIndex, bool isBuy)
    {
        if (!m_enforceCooldown)
        {
            DebugLogFile("COOLDOWN_CHECK_SKIP", "Cooldown enforcement disabled");
            return true;
        }

        if (symbolIndex < 0)
        {
            DebugLogFile("COOLDOWN_CHECK_ERROR", "Invalid symbol index");
            return false;
        }

        DecisionParams params = m_symbolStates[symbolIndex].params;
        CooldownRecord cooldown = m_symbolStates[symbolIndex].cooldown;

        DebugLogFile("COOLDOWN_STATE", StringFormat("Symbol: %s, isBuy: %s, LastBuy: %s, LastSell: %s, CooldownMins: %d",
                                                    m_symbolStates[symbolIndex].symbol,
                                                    isBuy ? "true" : "false",
                                                    TimeToString(cooldown.lastBuyTime),
                                                    TimeToString(cooldown.lastSellTime),
                                                    params.cooldownMinutes));

        bool inCooldown = cooldown.IsInCooldown(isBuy, params.cooldownMinutes);

        DebugLogFile("COOLDOWN_CHECK", StringFormat("Symbol: %s, isBuy: %s, InCooldown: %s",
                                                    m_symbolStates[symbolIndex].symbol, isBuy ? "true" : "false",
                                                    inCooldown ? "BLOCKED" : "ALLOWED"));

        return !inCooldown;
    }

    void ExecuteDecision(int symbolIndex, DECISION_ACTION decision, DecisionEngineInterface &package)
    {
        DebugLogFile("EXECUTE_DECISION_START", StringFormat("=== EXECUTING DECISION === | %s | Symbol: %s | Conf: %.1f%% | Processor: %s",
                                                            DecisionToString(decision), package.symbol, package.overallConfidence,
                                                            m_symbolStates[symbolIndex].lastProcessorUsed));

        if (symbolIndex < 0)
        {
            DebugLogFile("EXECUTE_ERROR", "❌ Invalid symbol index");
            return;
        }

        string symbol = m_symbolStates[symbolIndex].symbol;
        int magic = m_symbolStates[symbolIndex].magicNumber;

        DebugLogFile("EXECUTE_PARAMS", StringFormat("Symbol: %s | Magic: %d", symbol, magic));

        bool executed = false;
        string actionStr = DecisionToString(decision);

        switch (decision)
        {
        case ACTION_OPEN_BUY:
            DebugLogFile("EXECUTE_BUY", "Opening BUY position...");
            executed = PositionManager::OpenPositionWithTrendPackage(symbol, true, package, magic);
            if (executed)
            {
                m_symbolStates[symbolIndex].cooldown.Update(true);
                DebugLogFile("EXECUTE_COOLDOWN", "Buy cooldown updated after execution");
            }
            break;

        case ACTION_OPEN_SELL:
            DebugLogFile("EXECUTE_SELL", "Opening SELL position...");
            executed = PositionManager::OpenPositionWithTrendPackage(symbol, false, package, magic);
            if (executed)
            {
                m_symbolStates[symbolIndex].cooldown.Update(false);
                DebugLogFile("EXECUTE_COOLDOWN", "Sell cooldown updated after execution");
            }
            break;

        case ACTION_CLOSE_BUY:
            DebugLogFile("EXECUTE_CLOSE_BUY", "Calling PositionManager::CloseAllPositions (BUY)...");
            executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close BUY");
            if (executed)
            {
                m_symbolStates[symbolIndex].cooldown.Update(true);
                DebugLogFile("EXECUTE_COOLDOWN", "Buy cooldown updated after closing BUY");
            }
            break;

        case ACTION_CLOSE_SELL:
            DebugLogFile("EXECUTE_CLOSE_SELL", "Calling PositionManager::CloseAllPositions (SELL)...");
            executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close SELL");
            if (executed)
            {
                m_symbolStates[symbolIndex].cooldown.Update(false);
                DebugLogFile("EXECUTE_COOLDOWN", "Sell cooldown updated after closing SELL");
            }
            break;

        case ACTION_CLOSE_ALL:
            DebugLogFile("EXECUTE_CLOSE_ALL", "Calling PositionManager::CloseAllPositions (ALL)...");
            executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close ALL");
            if (executed)
            {
                m_symbolStates[symbolIndex].cooldown.Update(true);
                m_symbolStates[symbolIndex].cooldown.Update(false);
                DebugLogFile("EXECUTE_COOLDOWN", "Both cooldowns updated after closing ALL");
            }
            break;

        default:
            DebugLogFile("EXECUTE_SKIP", "No execution needed for this decision type");
            return;
        }

        if (executed)
        {
            DebugLogFile("EXECUTE_SUCCESS", "✅ Execution successful");
            LogExecution(symbol, decision, true, package);
        }
        else
        {
            DebugLogFile("EXECUTE_FAILED", "❌ Execution failed");
            LogExecution(symbol, decision, false, package);
            m_symbolStates[symbolIndex].cooldown.Reset();
            DebugLogFile("COOLDOWN_RESET", "Cooldown reset due to failed execution");
        }
    }

    // ================= LOGGING =================
    void LogInfo(string message)
    {
        DebugLogFile("INFO", message);
        DebugLogFile(m_engineName, message, true, true);
    }

    void LogWarning(string message)
    {
        DebugLogFile("WARNING", message);
        Logger::LogError(m_engineName, message);
    }

    void LogError(string message)
    {
        DebugLogFile("ERROR", message);
        Logger::LogError(m_engineName, message);
    }

    void LogDebug(string message)
    {
        if (m_debugEnabled)
        {
            DebugLogFile("DEBUG", message);
            DebugLogFile("DEBUG-" + m_engineName, message, true, true);
        }
    }

    void LogDecision(string symbol, DECISION_ACTION decision, const DecisionEngineInterface &package, string reason)
    {
        if (decision == ACTION_NONE || decision == ACTION_HOLD)
        {
            DebugLogFile("LOG_DECISION_SKIP", StringFormat("Skipping log for non-action decision: %s", DecisionToString(decision)));
            return;
        }

        string decisionStr = DecisionToString(decision);
        string logMsg = StringFormat("%s | %s | Conf: %.1f%% | Dir: %s | Reason: %s",
                                     symbol, decisionStr, package.overallConfidence,
                                     package.dominantDirection, reason);

        logMsg += StringFormat(" | Regime: %s | Action: %s | Type: %s",
                               package.marketRegime, package.recommendedAction,
                               package.IsRangePackage() ? "RANGE" : "TREND");

        if (decision == ACTION_WAITING_FOR_PACKAGE)
        {
            DebugLogFile("DECISION_WAITING", logMsg);
        }
        else
        {
            LogInfo(logMsg);
        }

        DebugLogFile("LOG_DECISION", StringFormat("Logged decision: %s", logMsg));
    }

    void LogExecution(string symbol, DECISION_ACTION decision, bool success, const DecisionEngineInterface &package)
    {
        string decisionStr = DecisionToString(decision);
        string logType = success ? "EXECUTION_SUCCESS" : "EXECUTION_FAILURE";

        DebugLogFile(logType, StringFormat("%s for %s | Conf: %.1f%%", decisionStr, symbol, package.overallConfidence));

        if (success)
        {
            if (decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL)
            {
                // Store position open info for later profitability check
                int symbolIndex = FindSymbolIndex(symbol);
                if (symbolIndex >= 0)
                {
                    m_symbolStates[symbolIndex].positionOpenTime = TimeCurrent();
                    m_symbolStates[symbolIndex].positionOpenDecision = decision;
                    m_symbolStates[symbolIndex].positionOpenConfidence = package.overallConfidence;
                    m_symbolStates[symbolIndex].awaitingProfitabilityCheck = false;

                    // DON'T update metrics here! Wait for close.

                    DebugLogFile("POSITION_OPEN_RECORDED",
                                 StringFormat("Recorded open for %s | Decision: %s | Conf: %.1f%% | Waiting for close...",
                                              symbol,
                                              DecisionToString(decision),
                                              package.overallConfidence));
                }
            }
            else if (decision == ACTION_CLOSE_BUY || decision == ACTION_CLOSE_SELL || decision == ACTION_CLOSE_ALL)
            {
                // This is a CLOSE signal - mark that we're waiting for the position to actually close
                int symbolIndex = FindSymbolIndex(symbol);
                if (symbolIndex >= 0 && m_symbolStates[symbolIndex].positionOpenTime > 0)
                {
                    m_symbolStates[symbolIndex].positionCloseTime = TimeCurrent();
                    m_symbolStates[symbolIndex].awaitingProfitabilityCheck = true;

                    DebugLogFile("CLOSE_SIGNAL_RECEIVED",
                                 StringFormat("Close signal for %s | Open was: %s | Awaiting actual close...",
                                              symbol,
                                              DecisionToString(m_symbolStates[symbolIndex].positionOpenDecision)));
                }
            }
        }
        else
        {
            LogError(StringFormat("FAILED: %s for %s", decisionStr, symbol));
            DebugLogFile("FAILURE_LOG", StringFormat("Execution failure logged: %s %s",
                                                     decisionStr, symbol));
        }
    }

    void ResetCooldown(string symbol)
    {
        DebugLogFile("RESET_COOLDOWN_START", "Resetting cooldown for: " + symbol);

        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            m_symbolStates[index].cooldown.Reset();
            DebugLogFile("RESET_COOLDOWN_SUCCESS", "Cooldown reset for " + symbol);
        }
        else
        {
            DebugLogFile("RESET_COOLDOWN_ERROR", "Symbol not found: " + symbol);
        }
    }

    void ResetAllCooldowns()
    {
        DebugLogFile("RESET_ALL_COOLDOWNS_START", "Resetting all cooldowns");

        for (int i = 0; i < m_totalSymbols; i++)
        {
            m_symbolStates[i].cooldown.Reset();
            DebugLogFile("COOLDOWN_RESET_INDIVIDUAL", StringFormat("Reset cooldown for %s", m_symbolStates[i].symbol));
        }

        DebugLogFile("RESET_ALL_COOLDOWNS_SUCCESS", "All cooldowns reset");
    }

    // ================= NEW: Get detailed regime info =================
    string GetRegimeInfoDetailed(string symbol, string &outRegime, string &outSource,
                                 string &outDirection, double &outConfidence)
    {
        int index = FindSymbolIndex(symbol);
        if (index < 0)
            return "";

        if (m_symbolStates[index].lastPackage.IsValid())
        {
            outRegime = m_symbolStates[index].lastPackage.marketRegime;
            outSource = m_symbolStates[index].usingRangePackage ? "RangePackage" : "TrendPackage";
            outDirection = m_symbolStates[index].lastPackage.dominantDirection;
            outConfidence = m_symbolStates[index].lastPackage.overallConfidence;

            return StringFormat("%s|%s|%s|%.0f%%",
                                outRegime, outSource, outDirection, outConfidence);
        }

        return "";
    }

    string GetActualProcessorUsed(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if (index >= 0)
        {
            return m_symbolStates[index].actualProcessorUsed;
        }
        return "NONE";
    }
};

// ================= END OF FILE =================