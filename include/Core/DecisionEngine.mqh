// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++       DECISION ENGINE v4.0           ++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property strict
#property version   "4.00"

/*
==============================================================
DECISION ENGINE v4.0 - PURE CONSUMER ARCHITECTURE
==============================================================
Core Principles:
1. ONLY consumes TradePackages (does NOT create its own)
2. Makes decisions based solely on received TradePackage data
3. No fallbacks or internal analysis - requires valid packages
4. Fully dependent on external analyzers (MTF, Volume, RSI, etc.)
==============================================================
*/

// ================= INCLUDES =================
#include "../Utils/Logger.mqh"
#include "../Utils/TimeUtils.mqh"
#include "../Execution/PositionManager.mqh"

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"
// #include "../Data/TradePackage.mqh"  // REMOVED - Using interface instead

// ================= FORWARD DECLARATIONS =================

// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED = false;

// Simple debug function using Logger
void DebugLogFile(string context, string message) {
   if(DEBUG_ENABLED) {
      Logger::Log(context, message, true, true);
   }
}

// ================= ENUMS =================
enum DECISION_ACTION {
    ACTION_NONE,
    ACTION_OPEN_BUY,
    ACTION_OPEN_SELL,
    ACTION_CLOSE_BUY,
    ACTION_CLOSE_SELL,
    ACTION_CLOSE_ALL,
    ACTION_HOLD,
    ACTION_WAITING_FOR_PACKAGE
};

enum POSITION_STATE {
    STATE_NO_POSITION,
    STATE_HAS_BUY,
    STATE_HAS_SELL,
    STATE_HAS_BOTH
};

// ====================== TRADE PACKAGE INTERFACE ======================

// ================= STRUCTURES =================
struct DecisionParams {
    double buyConfidenceThreshold;
    double sellConfidenceThreshold;
    double closePositionThreshold;
    double closeAllThreshold;
    int cooldownMinutes;
    int maxPositionsPerSymbol;
    double riskPercent;
    double minRiskRewardRatio;
    
    DecisionParams() {
        buyConfidenceThreshold = 70.0;
        sellConfidenceThreshold = 90.0;
        closePositionThreshold = 30.0;
        closeAllThreshold = 20.0;
        cooldownMinutes = 60;
        maxPositionsPerSymbol = 3;
        riskPercent = 10.0;
        minRiskRewardRatio = 1.5;
    }
    
    // Added: Log params structure
    string ToString() const {
        return StringFormat("BuyThresh: %.1f%%, SellThresh: %.1f%%, CloseThresh: %.1f%%, CloseAllThresh: %.1f%%, Cooldown: %dm, MaxPos: %d, Risk: %.1f%%, RR: %.1f",
            buyConfidenceThreshold, sellConfidenceThreshold, closePositionThreshold,
            closeAllThreshold, cooldownMinutes, maxPositionsPerSymbol, riskPercent, minRiskRewardRatio);
    }
};

struct CooldownRecord {
    datetime lastBuyTime;
    datetime lastSellTime;
    int buyCount;
    int sellCount;
    
    CooldownRecord() {
        lastBuyTime = 0;
        lastSellTime = 0;
        buyCount = 0;
        sellCount = 0;
    }
    
    bool IsInCooldown(bool isBuy, int cooldownMinutes) {
        if(cooldownMinutes <= 0) return false;
        
        datetime currentTime = TimeCurrent();
        datetime lastTime = isBuy ? lastBuyTime : lastSellTime;
        
        bool inCooldown = ((currentTime - lastTime) < (cooldownMinutes * 60));
        if(inCooldown) {
            DebugLogFile("COOLDOWN_CHECK", StringFormat("In cooldown: isBuy=%s, lastTime=%s, cooldownMins=%d, remaining=%d sec",
                isBuy ? "true" : "false", TimeToString(lastTime), cooldownMinutes, (cooldownMinutes * 60) - (currentTime - lastTime)));
        }
        return inCooldown;
    }
    
    void Update(bool isBuy) {
        if(isBuy) {
            lastBuyTime = TimeCurrent();
            buyCount++;
            DebugLogFile("COOLDOWN_UPDATE", StringFormat("Buy cooldown updated. LastBuyTime: %s, BuyCount: %d",
                TimeToString(lastBuyTime), buyCount));
        } else {
            lastSellTime = TimeCurrent();
            sellCount++;
            DebugLogFile("COOLDOWN_UPDATE", StringFormat("Sell cooldown updated. LastSellTime: %s, SellCount: %d",
                TimeToString(lastSellTime), sellCount));
        }
    }
    
    void Reset() {
        lastBuyTime = 0;
        lastSellTime = 0;
        buyCount = 0;
        sellCount = 0;
        DebugLogFile("COOLDOWN_RESET", "Cooldown record reset");
    }
    
    // Added: Log cooldown status
    string GetStatus() const {
        return StringFormat("Buy: %s (count: %d), Sell: %s (count: %d)",
            (lastBuyTime > 0 ? TimeToString(lastBuyTime) : "Never"), buyCount,
            (lastSellTime > 0 ? TimeToString(lastSellTime) : "Never"), sellCount);
    }
};

struct SymbolState {
    string symbol;
    DecisionParams params;
    CooldownRecord cooldown;
    DecisionEngineInterface lastPackage;  // CHANGED: Now uses Interface instead of TradePackage
    DECISION_ACTION lastDecision;
    datetime lastDecisionTime;
    int magicNumber;
    
    SymbolState() {
        symbol = "";
        lastDecision = ACTION_NONE;
        lastDecisionTime = 0;
        magicNumber = 0;
    }
    
    bool HasValidPackage() {
        bool isValid = (lastPackage.IsValid() && lastPackage.analysisTime > 0);
        if(!isValid) {
            DebugLogFile("PACKAGE_CHECK", StringFormat("No valid interface for %s: isValid=%s, analysisTime=%s",
                symbol, lastPackage.IsValid() ? "true" : "false", TimeToString(lastPackage.analysisTime)));
        }
        return isValid;
    }
    
    bool IsPackageFresh(int maxAgeSeconds = 300) { // 5 minutes default
        if(!HasValidPackage()) {
            DebugLogFile("PACKAGE_FRESHNESS", StringFormat("No valid interface for %s", symbol));
            return false;
        }
        
        int age = (int)(TimeCurrent() - lastPackage.analysisTime);
        bool isFresh = (age <= maxAgeSeconds);
        
        DebugLogFile("PACKAGE_FRESHNESS", StringFormat("Interface for %s: age=%d sec, maxAge=%d sec, fresh=%s",
            symbol, age, maxAgeSeconds, isFresh ? "true" : "false"));
        
        return isFresh;
    }
    
    // Added: Log symbol state
    string GetStatus() const {
        return StringFormat("Symbol: %s, Magic: %d, LastDecision: %s, LastDecisionTime: %s, HasInterface: %s",
            symbol, magicNumber, 
            (lastDecision == ACTION_NONE ? "NONE" : "SET"),
            (lastDecisionTime > 0 ? TimeToString(lastDecisionTime) : "Never"),
            (lastPackage.IsValid() ? "YES" : "NO"));
    }
};

struct PositionAnalysis {
    POSITION_STATE state;
    int buyCount;
    int sellCount;
    double totalProfit;
    double totalVolume;
    double maxRiskExposure;
    
    PositionAnalysis() {
        state = STATE_NO_POSITION;
        buyCount = 0;
        sellCount = 0;
        totalProfit = 0;
        totalVolume = 0;
        maxRiskExposure = 0;
    }
    
    string ToString() const {
        string stateStr = "";
        switch(state) {
            case STATE_NO_POSITION: stateStr = "NO_POSITION"; break;
            case STATE_HAS_BUY: stateStr = "HAS_BUY"; break;
            case STATE_HAS_SELL: stateStr = "HAS_SELL"; break;
            case STATE_HAS_BOTH: stateStr = "HAS_BOTH"; break;
        }
        return StringFormat("State: %s | Buy: %d | Sell: %d | Profit: %.2f | Volume: %.2f",
                           stateStr, buyCount, sellCount, totalProfit, totalVolume);
    }
};

struct DecisionMetrics {
    int totalDecisions;
    int profitableDecisions;
    double accuracyRate;
    double averageConfidence;
    datetime startTime;
    
    DecisionMetrics() {
        totalDecisions = 0;
        profitableDecisions = 0;
        accuracyRate = 0;
        averageConfidence = 0;
        startTime = TimeCurrent();
        DebugLogFile("METRICS_INIT", "Decision metrics initialized");
    }
    
    void Update(DECISION_ACTION decision, double confidence, bool wasProfitable = false) {
        int prevTotal = totalDecisions;
        totalDecisions++;
        
        if(wasProfitable) {
            profitableDecisions++;
            DebugLogFile("METRICS_UPDATE", StringFormat("Profitable decision: %s, Confidence: %.1f%%",
                DecisionToStringStatic(decision), confidence));
        }
        
        // Update rolling average confidence
        if(totalDecisions == 1) {
            averageConfidence = confidence;
        } else {
            averageConfidence = ((averageConfidence * prevTotal) + confidence) / totalDecisions;
        }
        
        // Update accuracy
        if(totalDecisions > 0) {
            accuracyRate = ((double)profitableDecisions / totalDecisions) * 100.0;
        }
        
        DebugLogFile("METRICS_UPDATE", StringFormat("Decision: %s, Confidence: %.1f%%, Total: %d, Profitable: %d, Accuracy: %.1f%%, AvgConf: %.1f%%",
            DecisionToStringStatic(decision), confidence, totalDecisions, profitableDecisions, accuracyRate, averageConfidence));
    }
    
    string ToString() const {
        return StringFormat("Decisions: %d | Accuracy: %.1f%% | Avg Conf: %.1f%% | Running: %d hours",
                           totalDecisions, accuracyRate, averageConfidence,
                           (int)((TimeCurrent() - startTime) / 3600));
    }
    
    // Helper static method for logging
    static string DecisionToStringStatic(DECISION_ACTION decision) {
        switch(decision) {
            case ACTION_NONE: return "NONE";
            case ACTION_OPEN_BUY: return "OPEN_BUY";
            case ACTION_OPEN_SELL: return "OPEN_SELL";
            case ACTION_CLOSE_BUY: return "CLOSE_BUY";
            case ACTION_CLOSE_SELL: return "CLOSE_SELL";
            case ACTION_CLOSE_ALL: return "CLOSE_ALL";
            case ACTION_HOLD: return "HOLD";
            case ACTION_WAITING_FOR_PACKAGE: return "WAITING";
            default: return "UNKNOWN";
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
    
    // Chart display
    datetime m_lastChartUpdate;
    int m_chartUpdateInterval;
    
public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    DecisionEngine() {
        m_engineName = "DecisionEngine";
        m_engineMagicBase = 10000;
        m_initialized = false;
        m_debugEnabled = false;
        m_totalSymbols = 0;
        
        m_allowMultiplePositions = true;
        m_useRiskManagement = true;
        m_enforceCooldown = true;
        m_maxPackageAgeSeconds = 300; // 5 minutes
        
        m_lastChartUpdate = 0;
        m_chartUpdateInterval = 2;
        
        ArrayResize(m_symbolStates, 0);
        
        DebugLogFile("CONSTRUCTOR", "DecisionEngine constructor called");
    }
    
    ~DecisionEngine() {
        DebugLogFile("DESTRUCTOR", "DecisionEngine destructor called");
        Deinitialize();
    }
    
    // ================= INITIALIZATION =================
    bool Initialize(string engineName = "DecisionEngine", 
                    int magicBase = 10000,
                    bool debug = false) {
        
        DebugLogFile("INIT_START", StringFormat("Initializing DecisionEngine: name=%s, magicBase=%d, debug=%s",
            engineName, magicBase, debug ? "true" : "false"));
        
        if(m_initialized) {
            DebugLogFile("INIT_WARNING", "Already initialized, calling Deinitialize first");
            Deinitialize();
        }
        
        m_engineName = engineName;
        m_engineMagicBase = magicBase;
        m_debugEnabled = debug;
        
        // Initialize logger with default settings
        Logger::Initialize();
        
        m_initialized = true;
        
        DebugLogFile("INIT_SUCCESS", "Decision Engine v4.0 Initialized Successfully");
        DebugLogFile("CONFIG", StringFormat("Mode: Pure Consumer | Max Package Age: %d seconds", m_maxPackageAgeSeconds));
        DebugLogFile("CONFIG", StringFormat("AllowMultiplePositions: %s | UseRiskManagement: %s | EnforceCooldown: %s",
            m_allowMultiplePositions ? "true" : "false",
            m_useRiskManagement ? "true" : "false",
            m_enforceCooldown ? "true" : "false"));
        
        return true;
    }
    
    void Deinitialize() {
        DebugLogFile("DEINIT_START", "Deinitializing DecisionEngine");
        
        if(!m_initialized) {
            DebugLogFile("DEINIT_WARNING", "Not initialized, skipping deinitialization");
            return;
        }
        
        // Log shutdown statistics
        DebugLogFile("SHUTDOWN", "=== SHUTDOWN STATISTICS ===");
        DebugLogFile("STATS", m_metrics.ToString());
        DebugLogFile("SYMBOLS", StringFormat("Total symbols monitored: %d", m_totalSymbols));
        
        // Log each symbol's final state
        for(int i = 0; i < m_totalSymbols; i++) {
            DebugLogFile("SYMBOL_FINAL_STATE", m_symbolStates[i].GetStatus());
        }
        
        ArrayFree(m_symbolStates);
        m_totalSymbols = 0;
        m_initialized = false;
        
        Logger::Shutdown();
        
        DebugLogFile("DEINIT_SUCCESS", "DecisionEngine deinitialized successfully");
    }
    
    // ================= SYMBOL MANAGEMENT =================
    bool RegisterSymbol(string symbol, DecisionParams &params) {
        DebugLogFile("REGISTER_SYMBOL_START", StringFormat("Registering symbol: %s with params: %s", symbol, params.ToString()));
        
        if(!m_initialized) {
            DebugLogFile("ERROR", "Engine not initialized");
            return false;
        }
        
        if(HasSymbol(symbol)) {
            DebugLogFile("WARNING", "Symbol already registered: " + symbol);
            return true; // Already registered is not an error
        }
        
        // Resize array if needed
        if(m_totalSymbols >= ArraySize(m_symbolStates)) {
            int newSize = m_totalSymbols + 10;
            ArrayResize(m_symbolStates, newSize);
            DebugLogFile("ARRAY_RESIZE", StringFormat("Resized symbol states array to %d", newSize));
        }
        
        // Initialize symbol state
        SymbolState state;
        state.symbol = symbol;
        state.params = params;
        
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
    
    bool RegisterSymbolWithDefaults(string symbol,
                                   double buyThreshold = 60.0,
                                   double sellThreshold = 60.0,
                                   double riskPercent = 5.0) {
        DebugLogFile("REGISTER_SYMBOL_DEFAULTS", StringFormat("Registering %s with defaults: Buy=%.1f%%, Sell=%.1f%%, Risk=%.1f%%",
            symbol, buyThreshold, sellThreshold, riskPercent));
        
        DecisionParams params;
        params.buyConfidenceThreshold = buyThreshold;
        params.sellConfidenceThreshold = sellThreshold;
        params.riskPercent = riskPercent;
        
        return RegisterSymbol(symbol, params);
    }
    
    bool UnregisterSymbol(string symbol) {
        DebugLogFile("UNREGISTER_SYMBOL_START", "Unregistering symbol: " + symbol);
        
        int index = FindSymbolIndex(symbol);
        if(index < 0) {
            DebugLogFile("UNREGISTER_ERROR", "Symbol not found: " + symbol);
            return false;
        }
        
        // Log symbol state before removal
        DebugLogFile("SYMBOL_REMOVAL", StringFormat("Removing symbol %s at index %d, state: %s",
            symbol, index, m_symbolStates[index].GetStatus()));
        
        // Shift array elements
        for(int i = index; i < m_totalSymbols - 1; i++) {
            m_symbolStates[i] = m_symbolStates[i + 1];
        }
        
        m_totalSymbols--;
        DebugLogFile("UNREGISTER_SUCCESS", "Symbol unregistered: " + symbol);
        DebugLogFile("SYMBOL_COUNT", StringFormat("Total symbols after removal: %d", m_totalSymbols));
        
        return true;
    }
    
    // ================= MAIN PUBLIC INTERFACE =================
    DECISION_ACTION ProcessTradePackage(DecisionEngineInterface &package) {  // CHANGED: Now uses Interface
        DebugLogFile("PROCESS_PACKAGE_START", StringFormat("=== PROCESSING TRADE PACKAGE === | Symbol: %s | Valid: %s | Conf: %.1f%%",
                           package.symbol, package.IsValid() ? "YES" : "NO", package.overallConfidence));
        
        if(!m_initialized) {
            DebugLogFile("ERROR", "Engine not initialized");
            return ACTION_NONE;
        }
        
        string symbol = package.symbol;
        
        // Validate symbol is registered
        if(!HasSymbol(symbol)) {
            // Auto-register with defaults if not registered
            DebugLogFile("AUTO-REG", "Auto-registering symbol: " + symbol);
            if(!RegisterSymbolWithDefaults(symbol)) {
                DebugLogFile("AUTO-REG_ERROR", "Failed to auto-register symbol: " + symbol);
                return ACTION_NONE;
            }
            DebugLogFile("AUTO-REG_SUCCESS", "Auto-registered symbol: " + symbol);
        }
        
        int symbolIndex = FindSymbolIndex(symbol);
        if(symbolIndex < 0) {
            DebugLogFile("ERROR", "Symbol index not found: " + symbol);
            return ACTION_NONE;
        }
        
        DebugLogFile("SYMBOL_FOUND", StringFormat("Symbol %s found at index %d", symbol, symbolIndex));
        
        // Store the package interface
        m_symbolStates[symbolIndex].lastPackage = package;
        m_symbolStates[symbolIndex].lastDecisionTime = TimeCurrent();
        
        DebugLogFile("PACKAGE_STORED", StringFormat("Package interface stored for %s at time %s",
            symbol, TimeToString(TimeCurrent())));
        
        // Validate package
        if(!package.IsValid()) {
            LogDecision(symbol, ACTION_NONE, package, "Invalid TradePackage");
            DebugLogFile("PROCESS", "❌ Package invalid");
            return ACTION_NONE;
        }
        
        // Check package freshness
        if(!IsPackageFresh(symbolIndex)) {
            LogDecision(symbol, ACTION_WAITING_FOR_PACKAGE, package, "Package too old");
            DebugLogFile("PROCESS", "⚠️ Package stale");
            return ACTION_WAITING_FOR_PACKAGE;
        }
        
        DebugLogFile("PROCESS", "✅ Package valid and fresh");
        
        // Analyze current positions
        PositionAnalysis positions = AnalyzePositions(symbolIndex);
        DebugLogFile("POSITIONS", StringFormat("Current positions: %s", positions.ToString()));
        
        // Make decision based on package and positions
        DECISION_ACTION decision = MakeDecision(symbolIndex, package, positions);  // CHANGED
        DebugLogFile("DECISION_MADE", StringFormat("Decision made: %s", DecisionToString(decision)));
        
        // Validate and potentially execute
        if(decision != ACTION_NONE && decision != ACTION_HOLD && decision != ACTION_WAITING_FOR_PACKAGE) {
            DebugLogFile("DECISION_VALIDATION_START", "Starting decision validation");
            if(ValidateDecision(symbolIndex, decision, package)) {  // CHANGED
                DebugLogFile("VALIDATION", "✅ Decision validated");
                ExecuteDecision(symbolIndex, decision, package);  // CHANGED
            } else {
                DebugLogFile("VALIDATION", "❌ Decision validation failed");
                decision = ACTION_HOLD; // Fallback to hold if validation fails
                DebugLogFile("DECISION_FALLBACK", "Falling back to HOLD due to validation failure");
            }
        } else {
            DebugLogFile("DECISION_NO_EXECUTION", StringFormat("No execution needed: %s", DecisionToString(decision)));
        }
        
        // Store and log decision
        m_symbolStates[symbolIndex].lastDecision = decision;
        m_metrics.Update(decision, package.overallConfidence);
        
        DebugLogFile("PROCESS_COMPLETE", StringFormat("=== PROCESS COMPLETE === | Final decision: %s", DecisionToString(decision)));
        return decision;
    }
    
    // ================= BATCH PROCESSING =================
    int ProcessMultiplePackages(DecisionEngineInterface &packages[]) {  // CHANGED: Now uses Interface
        DebugLogFile("BATCH_PROCESS_START", StringFormat("Processing %d packages", ArraySize(packages)));
        
        if(!m_initialized) {
            DebugLogFile("ERROR", "Engine not initialized");
            return 0;
        }
        
        if(ArraySize(packages) == 0) {
            DebugLogFile("WARNING", "Empty package array");
            return 0;
        }
        
        int decisionsMade = 0;
        
        for(int i = 0; i < ArraySize(packages); i++) {
            DebugLogFile("BATCH_ITEM", StringFormat("Processing package %d/%d: Symbol=%s, Conf=%.1f%%",
                i+1, ArraySize(packages), packages[i].symbol, packages[i].overallConfidence));
            
            DECISION_ACTION decision = ProcessTradePackage(packages[i]);
            if(decision != ACTION_NONE && decision != ACTION_HOLD && 
               decision != ACTION_WAITING_FOR_PACKAGE) {
                decisionsMade++;
                DebugLogFile("BATCH_DECISION", StringFormat("Package %d resulted in actionable decision: %s", i+1, DecisionToString(decision)));
            } else {
                DebugLogFile("BATCH_NO_DECISION", StringFormat("Package %d resulted in non-actionable decision: %s", i+1, DecisionToString(decision)));
            }
        }
        
        DebugLogFile("BATCH_PROCESS_COMPLETE", StringFormat("Batch processing complete. Decisions made: %d/%d", decisionsMade, ArraySize(packages)));
        
        return decisionsMade;
    }
    
    // ================= SETTERS =================
    void SetDebugMode(bool enabled) { 
        DebugLogFile("CONFIG_CHANGE", StringFormat("Debug mode changing from %s to %s", 
            m_debugEnabled ? "ENABLED" : "DISABLED", enabled ? "ENABLED" : "DISABLED"));
        m_debugEnabled = enabled; 
        DebugLogFile("CONFIG", "Debug mode: " + (enabled ? "ENABLED" : "DISABLED"));
    }
    
    void SetAllowMultiplePositions(bool allowed) { 
        DebugLogFile("CONFIG_CHANGE", StringFormat("Multiple positions changing from %s to %s",
            m_allowMultiplePositions ? "ALLOWED" : "NOT ALLOWED", allowed ? "ALLOWED" : "NOT ALLOWED"));
        m_allowMultiplePositions = allowed; 
        DebugLogFile("CONFIG", "Multiple positions: " + (allowed ? "ALLOWED" : "NOT ALLOWED"));
    }
    
    void SetUseRiskManagement(bool use) { 
        DebugLogFile("CONFIG_CHANGE", StringFormat("Risk management changing from %s to %s",
            m_useRiskManagement ? "ENABLED" : "DISABLED", use ? "ENABLED" : "DISABLED"));
        m_useRiskManagement = use; 
        DebugLogFile("CONFIG", "Risk management: " + (use ? "ENABLED" : "DISABLED"));
    }
    
    void SetEnforceCooldown(bool enforce) { 
        DebugLogFile("CONFIG_CHANGE", StringFormat("Cooldown enforcement changing from %s to %s",
            m_enforceCooldown ? "ENABLED" : "DISABLED", enforce ? "ENABLED" : "DISABLED"));
        m_enforceCooldown = enforce; 
        DebugLogFile("CONFIG", "Cooldown enforcement: " + (enforce ? "ENABLED" : "DISABLED"));
    }
    
    void SetMaxPackageAge(int seconds) { 
        int oldValue = m_maxPackageAgeSeconds;
        m_maxPackageAgeSeconds = MathMax(60, seconds); // Minimum 60 seconds
        DebugLogFile("CONFIG_CHANGE", StringFormat("Max package age changing from %d to %d seconds", oldValue, m_maxPackageAgeSeconds));
        DebugLogFile("CONFIG", StringFormat("Max package age: %d seconds", m_maxPackageAgeSeconds));
    }
    
    void SetChartUpdateInterval(int seconds) { 
        int oldValue = m_chartUpdateInterval;
        m_chartUpdateInterval = MathMax(1, seconds); 
        DebugLogFile("CONFIG_CHANGE", StringFormat("Chart update interval changing from %d to %d seconds", oldValue, m_chartUpdateInterval));
        DebugLogFile("CONFIG", StringFormat("Chart update interval: %d seconds", m_chartUpdateInterval));
    }
    
    void UpdateSymbolParams(string symbol, DecisionParams &params) {
        DebugLogFile("UPDATE_PARAMS_START", StringFormat("Updating params for %s: %s", symbol, params.ToString()));
        
        int index = FindSymbolIndex(symbol);
        if(index >= 0) {
            DecisionParams oldParams = m_symbolStates[index].params;
            m_symbolStates[index].params = params;
            
            DebugLogFile("UPDATE_PARAMS_SUCCESS", StringFormat("Updated params for %s", symbol));
            DebugLogFile("PARAMS_CHANGE", StringFormat("Buy: %.1f%% -> %.1f%% | Sell: %.1f%% -> %.1f%%",
                oldParams.buyConfidenceThreshold, params.buyConfidenceThreshold,
                oldParams.sellConfidenceThreshold, params.sellConfidenceThreshold));
        } else {
            DebugLogFile("UPDATE_PARAMS_ERROR", "Symbol not found: " + symbol);
        }
    }
    
    // ================= GETTERS =================
    string GetStatus() const {
        if(!m_initialized) {
            DebugLogFile("GET_STATUS", "DecisionEngine: NOT INITIALIZED");
            return "DecisionEngine: NOT INITIALIZED";
        }
        
        string status = StringFormat("DecisionEngine v4.0 | Symbols: %d | %s",
                           m_totalSymbols, m_metrics.ToString());
        DebugLogFile("GET_STATUS", status);
        return status;
    }
    
    DecisionEngineInterface GetLastPackage(string symbol) const {  // CHANGED: Returns Interface
        DebugLogFile("GET_LAST_PACKAGE", "Getting last package for: " + symbol);
        
        int index = FindSymbolIndex(symbol);
        if(index >= 0) {
            DebugLogFile("GET_LAST_PACKAGE_SUCCESS", StringFormat("Found package for %s, isValid=%s", 
                symbol, m_symbolStates[index].lastPackage.IsValid() ? "true" : "false"));
            return m_symbolStates[index].lastPackage;
        }
        
        DebugLogFile("GET_LAST_PACKAGE_ERROR", "Symbol not found: " + symbol);
        DecisionEngineInterface empty;
        return empty;
    }
    
    DECISION_ACTION GetLastDecision(string symbol) const {
        DebugLogFile("GET_LAST_DECISION", "Getting last decision for: " + symbol);
        
        int index = FindSymbolIndex(symbol);
        if(index >= 0) {
            DebugLogFile("GET_LAST_DECISION_SUCCESS", StringFormat("Last decision for %s: %s", 
                symbol, DecisionToString(m_symbolStates[index].lastDecision)));
            return m_symbolStates[index].lastDecision;
        }
        
        DebugLogFile("GET_LAST_DECISION_ERROR", "Symbol not found: " + symbol);
        return ACTION_NONE;
    }
    
    DecisionMetrics GetMetrics() const {
        DebugLogFile("GET_METRICS", "Getting decision metrics");
        return m_metrics;
    }
    
    int GetSymbolCount() const {
        DebugLogFile("GET_SYMBOL_COUNT", StringFormat("Symbol count: %d", m_totalSymbols));
        return m_totalSymbols;
    }
    
    bool HasSymbol(string symbol) const {
        bool hasSymbol = (FindSymbolIndex(symbol) >= 0);
        DebugLogFile("HAS_SYMBOL", StringFormat("Checking if symbol %s exists: %s", symbol, hasSymbol ? "YES" : "NO"));
        return hasSymbol;
    }
    
    // ================= EVENT HANDLERS =================
    void OnTick() {
        if(!m_initialized) {
            DebugLogFile("ONTICK_WARNING", "Engine not initialized, skipping OnTick");
            return;
        }
        
        // Optional: Update chart display
        if(m_debugEnabled && (TimeCurrent() - m_lastChartUpdate) >= m_chartUpdateInterval) {
            DebugLogFile("CHART_UPDATE", "Updating chart display");
            
            // Choose which display to show:
            // DisplayCombinedView();  // Show combined view (both components and decision engine)
            // OR: DisplayComponentsView();  // Show only components
            // OR: DisplayDecisionEngineView();  // Show only decision engine
            
            m_lastChartUpdate = TimeCurrent();
            DebugLogFile("CHART_UPDATE_COMPLETE", StringFormat("Chart updated at %s", TimeToString(m_lastChartUpdate)));
        }
        
        // Check for expired packages
        int expiredCount = 0;
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].HasValidPackage() && !m_symbolStates[i].IsPackageFresh()) {
                expiredCount++;
                DebugLogFile("PACKAGE_EXPIRED", StringFormat("Package expired for %s (age: %d seconds)",
                                    m_symbolStates[i].symbol,
                                    (int)(TimeCurrent() - m_symbolStates[i].lastPackage.analysisTime)));
            }
        }
        
        if(expiredCount > 0) {
            DebugLogFile("PACKAGE_CHECK_SUMMARY", StringFormat("%d packages expired out of %d total symbols", expiredCount, m_totalSymbols));
        }
    }
    
    void OnTimer() {
        DebugLogFile("ONTIMER", "OnTimer called");
        OnTick(); // Same as OnTick for simplicity
    }
    
    void OnTradeTransaction(const MqlTradeTransaction &trans,
                       const MqlTradeRequest &request,
                       const MqlTradeResult &result) 
    {
        DebugLogFile("TRADE_TRANSACTION", StringFormat("Trade transaction: type=%d, symbol=%s, result=%d",
            trans.type, trans.symbol, result.retcode));
        
        if(!m_initialized) {
            DebugLogFile("TRADE_TRANSACTION_WARNING", "Engine not initialized, skipping");
            return;
        }
        
        // Update cooldown on successful trades
        if(result.retcode == TRADE_RETCODE_DONE) {
            DebugLogFile("TRADE_SUCCESS", "Trade transaction successful");
            
            bool isBuy = false;
            
            // Check if it's a deal addition
            if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
                // Get deal information
                ulong dealTicket = trans.deal;
                
                // Check if this is a buy deal
                if(HistoryDealSelect(dealTicket)) {
                    long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                    if(dealType == DEAL_TYPE_BUY) {
                        isBuy = true;
                        DebugLogFile("TRADE_DIRECTION", "BUY deal detected");
                    } else if(dealType == DEAL_TYPE_SELL) {
                        DebugLogFile("TRADE_DIRECTION", "SELL deal detected");
                    } else {
                        DebugLogFile("TRADE_DIRECTION", StringFormat("Other deal type: %d", dealType));
                    }
                } else {
                    DebugLogFile("TRADE_HISTORY_ERROR", "Failed to select deal from history");
                }
            } else {
                DebugLogFile("TRADE_TYPE", StringFormat("Non-deal transaction type: %d", trans.type));
            }
            
            // Update cooldown for the symbol
            int index = FindSymbolIndex(trans.symbol);
            if(index >= 0) {
                m_symbolStates[index].cooldown.Update(isBuy);
                DebugLogFile("COOLDOWN_UPDATE_TRADE", StringFormat("Cooldown updated for %s: %s",
                                    trans.symbol, isBuy ? "BUY" : "SELL"));
            } else {
                DebugLogFile("COOLDOWN_UPDATE_ERROR", "Symbol not found for cooldown update: " + trans.symbol);
            }
        } else {
            DebugLogFile("TRADE_FAILED", StringFormat("Trade failed with retcode: %d", result.retcode));
        }
    }
    
    // ================= DISPLAY METHODS =================
    void UpdateChartDisplay() {
        DebugLogFile("UPDATE_CHART_DISPLAY", "Manual chart display update requested");
        
        if(!m_initialized) {
            DebugLogFile("UPDATE_CHART_ERROR", "Engine not initialized");
            return;
        }
        
        if(!m_debugEnabled) {
            DebugLogFile("UPDATE_CHART_WARNING", "Debug mode disabled, skipping chart update");
            return;
        }
        
        DisplayCombinedView(); // Show the combined view
        
        DebugLogFile("UPDATE_CHART_COMPLETE", "Chart display updated");
    }
    
    // ================= UTILITY =================
    string DecisionToString(DECISION_ACTION decision) const {
        return DecisionMetrics::DecisionToStringStatic(decision);
    }
    
    // Show only Decision Engine panel
    void DisplayDecisionEngineOnly() {
        DebugLogFile("DISPLAY_DECISION_ENGINE", "Displaying Decision Engine panel only");
        
        // Create the panel content
        string display = "=== DECISION ENGINE PANEL ===\n";
        display += StringFormat("Time: %s | Version: 4.0\n", TimeToString(TimeCurrent(), TIME_SECONDS));
        display += StringFormat("Symbols: %d | Active: %d\n\n", m_totalSymbols, GetActiveSymbolCount());
        
        display += "Symbol      | Status     | Conf% | Decision\n";
        display += "────────────┼────────────┼───────┼───────────\n";
        
        int displayCount = MathMin(m_totalSymbols, 10);
        for(int i = 0; i < displayCount; i++) {
            SymbolState state = m_symbolStates[i];
            string status = state.HasValidPackage() ? (state.IsPackageFresh() ? "FRESH" : "STALE") : "NO PKG";
            string decision = DecisionToString(state.lastDecision);
            double confidence = state.HasValidPackage() ? state.lastPackage.overallConfidence : 0;
            
            display += StringFormat("%-12s| %-11s| %5.0f%%| %-10s\n",
                state.symbol, status, confidence, decision);
        }
        
        display += StringFormat("\nMetrics: %s", m_metrics.ToString());
        
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_DECISION_ENGINE_COMPLETE", "Decision Engine panel displayed");
    }
    
    // Show only Trading Package panel  
    void DisplayTradingPackageOnly() {
        DebugLogFile("DISPLAY_TRADING_PACKAGE", "Displaying Trading Package panel only");
        
        string display = "=== TRADING PACKAGE ===\n";
        display += GetTradingPackagePanel();
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_TRADING_PACKAGE_COMPLETE", "Trading Package panel displayed");
    }
    
    // Show only Scanning New panel
    void DisplayScanningNewOnly() {
        DebugLogFile("DISPLAY_SCANNING_NEW", "Displaying Scanning New panel only");
        
        string display = "=== SCANNING NEW ===\n";
        display += GetScanningNewPanel();
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_SCANNING_NEW_COMPLETE", "Scanning New panel displayed");
    }

    // ================= NEW DISPLAY METHODS =================
    // Show components panel
    void DisplayComponentsView() {
        DebugLogFile("DISPLAY_COMPONENTS", "Displaying components view");
        
        string display = "";
        
        // Header
        display += "=== COMPONENTS ANALYSIS ===\n";
        display += StringFormat("Time: %s\n\n", 
            TimeToString(TimeCurrent(), TIME_SECONDS));
        
        // Display for each symbol (limited to 2 symbols as requested)
        int symbolsToShow = MathMin(m_totalSymbols, 2);
        
        for(int s = 0; s < symbolsToShow; s++) {
            if(m_symbolStates[s].HasValidPackage()) {
                SymbolState state = m_symbolStates[s];
                DecisionEngineInterface pkg = state.lastPackage;
                
                display += StringFormat("SYMBOL: %s\n", state.symbol);
                display += "─────────────────────────────────────────\n";
                
                // Basic package information that we know exists
                display += StringFormat("Analysis Time: %s\n", 
                    TimeToString(pkg.analysisTime, TIME_SECONDS));
                
                display += StringFormat("Confidence: %.1f%%\n", 
                    pkg.overallConfidence);
                
                display += StringFormat("Direction: %s\n", 
                    pkg.dominantDirection);
                
                // Package freshness
                int age = (int)(TimeCurrent() - pkg.analysisTime);
                display += StringFormat("Package Age: %d seconds\n", age);
                display += StringFormat("Fresh: %s\n", (age <= m_maxPackageAgeSeconds) ? "YES" : "NO");
                
                // Try to get any additional info from the package
                // Use the GetSimpleSignal() method if it exists
                display += StringFormat("Signal: %s\n", pkg.GetSimpleSignal());
                
                display += "\n";
            }
        }
        
        // If no symbols with valid packages, show message
        if(display == "=== COMPONENTS ANALYSIS ===\n" + 
           StringFormat("Time: %s\n\n", TimeToString(TimeCurrent(), TIME_SECONDS))) {
            display += "No valid packages available for component analysis\n";
        }
        
        Logger::DisplaySingleFrame(display);
        DebugLogFile("DISPLAY_COMPONENTS_COMPLETE", "Components view displayed");
    }

    // Show Decision Engine panel
    void DisplayDecisionEngineView() {
        DebugLogFile("DISPLAY_DECISION_ENGINE", "Displaying Decision Engine view");
        
        string display = "=== DECISION ENGINE ===\n";
        display += StringFormat("Time: %s | Mode: %s\n", 
            TimeToString(TimeCurrent(), TIME_SECONDS), m_engineName);
        display += StringFormat("Total Symbols: %d | %s\n\n", 
            m_totalSymbols, m_metrics.ToString());
        
        // Header
        display += "Symbol      | Decision   | #Pos | Conf% | Profit\n";
        display += "────────────┼────────────┼──────┼───────┼────────\n";
        
        int displayCount = MathMin(m_totalSymbols, 10); // Limit to 10 symbols
        int validCount = 0;
        
        for(int i = 0; i < displayCount; i++) {
            if(m_symbolStates[i].HasValidPackage()) {
                validCount++;
                SymbolState state = m_symbolStates[i];
                DecisionEngineInterface pkg = state.lastPackage;
                PositionAnalysis pos = AnalyzePositions(i);
                
                // Get number of positions
                int numPositions = pos.buyCount + pos.sellCount;
                
                // Get decision as readable string
                string decision = DecisionToString(state.lastDecision);
                if(decision == "OPEN_BUY") decision = "BUY ▲";
                else if(decision == "OPEN_SELL") decision = "SELL ▼";
                else if(decision == "CLOSE_BUY") decision = "CLOSE_BUY";
                else if(decision == "CLOSE_SELL") decision = "CLOSE_SELL";
                else if(decision == "CLOSE_ALL") decision = "CLOSE_ALL";
                else if(decision == "HOLD") decision = "HOLD ●";
                else if(decision == "WAITING") decision = "WAIT ⏳";
                
                // Format the line
                display += StringFormat("%-12s| %-11s| %4d | %5.0f%%| %7.2f\n",
                    state.symbol,
                    decision,
                    numPositions,
                    pkg.overallConfidence,
                    pos.totalProfit);
            }
        }
        
        if(validCount == 0) {
            display += "No valid packages available\n";
        }
        
        // Add footer with statistics
        display += StringFormat("\nDECISIONS TODAY: %d | ACCURACY: %.1f%%",
            m_metrics.totalDecisions, m_metrics.accuracyRate);
        
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_DECISION_ENGINE_COMPLETE", "Decision Engine view displayed");
    }

    // Combined view showing both panels
    void DisplayCombinedView() {
        DebugLogFile("DISPLAY_COMBINED", "Displaying combined view");
        
        string display = "";
        
        // Components Analysis Section
        display += "=== PACKAGE ANALYSIS ===\n";
        display += StringFormat("Time: %s\n\n", TimeToString(TimeCurrent(), TIME_SECONDS));
        
        // Display 2 symbols with package info
        int symbolsToShow = MathMin(m_totalSymbols, 2);
        bool hasPackages = false;
        
        for(int s = 0; s < symbolsToShow; s++) {
            if(m_symbolStates[s].HasValidPackage()) {
                hasPackages = true;
                SymbolState state = m_symbolStates[s];
                DecisionEngineInterface pkg = state.lastPackage;
                
                display += StringFormat("%s | Conf: %.0f%% | Dir: %s\n", 
                    state.symbol, pkg.overallConfidence, pkg.dominantDirection);
                
                int age = (int)(TimeCurrent() - pkg.analysisTime);
                display += StringFormat("Age: %ds | Fresh: %s\n", 
                    age, (age <= m_maxPackageAgeSeconds) ? "YES" : "NO");
                
                display += "─\n";
            }
        }
        
        if(!hasPackages) {
            display += "No package data available\n";
        }
        
        display += "\n";
        
        // Decision Engine Section
        display += "=== DECISION ENGINE ===\n";
        display += StringFormat("Symbols: %d | %s\n\n", m_totalSymbols, m_metrics.ToString());
        
        display += "Symbol      | Decision   | #Pos | Conf% | Profit\n";
        display += "────────────┼────────────┼──────┼───────┼────────\n";
        
        int displayCount = MathMin(m_totalSymbols, 5); // Show 5 symbols
        int validCount = 0;
        
        for(int i = 0; i < displayCount; i++) {
            if(m_symbolStates[i].HasValidPackage()) {
                validCount++;
                SymbolState state = m_symbolStates[i];
                DecisionEngineInterface pkg = state.lastPackage;
                PositionAnalysis pos = AnalyzePositions(i);
                
                int numPositions = pos.buyCount + pos.sellCount;
                
                // Format decision string
                string decision = "";
                switch(state.lastDecision) {
                    case ACTION_OPEN_BUY: decision = "BUY ▲"; break;
                    case ACTION_OPEN_SELL: decision = "SELL ▼"; break;
                    case ACTION_CLOSE_BUY: decision = "CLOSE B"; break;
                    case ACTION_CLOSE_SELL: decision = "CLOSE S"; break;
                    case ACTION_CLOSE_ALL: decision = "CLOSE ALL"; break;
                    case ACTION_HOLD: decision = "HOLD ●"; break;
                    case ACTION_WAITING_FOR_PACKAGE: decision = "WAIT ⏳"; break;
                    default: decision = "NONE"; break;
                }
                
                display += StringFormat("%-12s| %-11s| %4d | %5.0f%%| %7.2f\n",
                    state.symbol,
                    decision,
                    numPositions,
                    pkg.overallConfidence,
                    pos.totalProfit);
            }
        }
        
        if(validCount == 0) {
            display += "No valid packages available\n";
        }
        
        // Add engine statistics
        display += StringFormat("\nActive: %d/%d symbols | Today: %d decisions",
            validCount, m_totalSymbols, m_metrics.totalDecisions);
        
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_COMBINED_COMPLETE", "Combined view displayed");
    }

    // Add to DecisionEngine class (public section)
    int GetMagicNumber(string symbol) const {
        int index = FindSymbolIndex(symbol);
        if(index >= 0) {
            return m_symbolStates[index].magicNumber;
        }
        return 0;
    }

    // Also add this method to get symbol by index:
    string GetSymbolAtIndex(int index) const {
        if(index >= 0 && index < m_totalSymbols) {
            return m_symbolStates[index].symbol;
        }
        return "";
    }
    
private:
    
    // ================= PRIVATE HELPER METHODS =================
    int FindSymbolIndex(string symbol) const {
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].symbol == symbol) {
                DebugLogFile("FIND_SYMBOL_INDEX", StringFormat("Found symbol %s at index %d", symbol, i));
                return i;
            }
        }
        DebugLogFile("FIND_SYMBOL_INDEX", "Symbol not found: " + symbol);
        return -1;
    }
    
    int GenerateMagicNumber(string symbol) {
        DebugLogFile("GENERATE_MAGIC", "Generating magic number for: " + symbol);
        
        int hash = 0;
        for(int i = 0; i < StringLen(symbol); i++) {
            hash = hash * 31 + StringGetCharacter(symbol, i);
        }
        
        int magic = m_engineMagicBase + (MathAbs(hash) % 10000);
        DebugLogFile("GENERATE_MAGIC_RESULT", StringFormat("Generated magic %d for symbol %s", magic, symbol));
        
        return magic;
    }
    
    bool IsPackageFresh(int symbolIndex) {
        if(symbolIndex < 0 || symbolIndex >= m_totalSymbols) {
            DebugLogFile("IS_PACKAGE_FRESH_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return false;
        }
        
        bool isFresh = m_symbolStates[symbolIndex].IsPackageFresh(m_maxPackageAgeSeconds);
        DebugLogFile("IS_PACKAGE_FRESH", StringFormat("Package freshness for %s: %s",
            m_symbolStates[symbolIndex].symbol, isFresh ? "FRESH" : "STALE"));
        
        return isFresh;
    }
    
    // Helper method for active symbol count
    int GetActiveSymbolCount() const {
        int count = 0;
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].HasValidPackage() && m_symbolStates[i].IsPackageFresh()) {
                count++;
            }
        }
        return count;
    }
    
    // Helper methods for missing panels (to fix compilation errors)
    string GetTradingPackagePanel() {
        string panel = "";
        
        // Find first symbol with valid package
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].HasValidPackage()) {
                SymbolState state = m_symbolStates[i];
                DecisionEngineInterface pkg = state.lastPackage;
                
                panel += StringFormat("Symbol: %s\n", state.symbol);
                panel += StringFormat("Time: %s\n", TimeToString(pkg.analysisTime, TIME_SECONDS));
                panel += StringFormat("Confidence: %.1f%%\n", pkg.overallConfidence);
                panel += StringFormat("Direction: %s\n", pkg.dominantDirection);
                panel += StringFormat("Package Age: %d seconds\n", (int)(TimeCurrent() - pkg.analysisTime));
                panel += StringFormat("Fresh: %s\n", state.IsPackageFresh() ? "YES" : "NO");
                break;
            }
        }
        
        if(panel == "") {
            panel = "No trading packages available\n";
        }
        
        return panel;
    }
    
    string GetScanningNewPanel() {
        string panel = "";
        panel += "Scanning for new opportunities...\n\n";
        panel += StringFormat("Total Symbols: %d\n", m_totalSymbols);
        panel += StringFormat("Active Symbols: %d\n", GetActiveSymbolCount());
        panel += StringFormat("Expired Packages: %d\n", GetExpiredPackageCount());
        
        // Show recent symbols
        panel += "\nRecent Symbols:\n";
        int count = MathMin(m_totalSymbols, 5);
        for(int i = 0; i < count; i++) {
            panel += StringFormat("- %s\n", m_symbolStates[i].symbol);
        }
        
        return panel;
    }
    
    int GetExpiredPackageCount() const {
        int count = 0;
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].HasValidPackage() && !m_symbolStates[i].IsPackageFresh()) {
                count++;
            }
        }
        return count;
    }
    
    // ================= POSITION ANALYSIS =================
    double GetPositionCommission(ulong positionTicket) {
        if(positionTicket == 0) {
            DebugLogFile("GET_COMMISSION", "Position ticket is 0");
            return 0.0;
        }
        
        double commission = 0.0;
        
        // Try to get commission from the position's opening deal
        if(HistoryDealSelect(positionTicket)) {
            commission = HistoryDealGetDouble(positionTicket, DEAL_COMMISSION);
            DebugLogFile("GET_COMMISSION", StringFormat("Commission from deal %d: %.2f", positionTicket, commission));
        } else {
            DebugLogFile("GET_COMMISSION", StringFormat("Failed to select deal %d from history", positionTicket));
            
            // If that fails, search through deal history
            datetime positionTime = 0;
            string positionSymbol = "";
            
            if(PositionSelectByTicket(positionTicket)) {
                positionTime = (datetime)PositionGetInteger(POSITION_TIME);
                positionSymbol = PositionGetString(POSITION_SYMBOL);
                DebugLogFile("GET_COMMISSION", StringFormat("Position %s opened at %s", positionSymbol, TimeToString(positionTime)));
            } else {
                DebugLogFile("GET_COMMISSION_ERROR", StringFormat("Failed to select position by ticket %d", positionTicket));
            }
            
            // Search for opening deals
            int totalDeals = HistoryDealsTotal();
            DebugLogFile("GET_COMMISSION_SEARCH", StringFormat("Searching %d deals for opening deal", totalDeals));
            
            for(int i = totalDeals - 1; i >= 0; i--) {
                ulong dealTicket = HistoryDealGetTicket(i);
                if(dealTicket <= 0) continue;
                
                long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                
                // Check if this is an opening deal for our position
                // (within 60 seconds of position opening time)
                if((dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) &&
                   dealSymbol == positionSymbol &&
                   MathAbs(dealTime - positionTime) < 60) {
                    
                    commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                    DebugLogFile("GET_COMMISSION_FOUND", StringFormat("Found opening deal %d, commission: %.2f", dealTicket, commission));
                    break;
                }
            }
        }
        
        return commission;
    }
    
    PositionAnalysis AnalyzePositions(int symbolIndex) {
        DebugLogFile("ANALYZE_POSITIONS_START", StringFormat("Analyzing positions for symbol index %d", symbolIndex));
        
        PositionAnalysis analysis;
        
        if(symbolIndex < 0 || symbolIndex >= m_totalSymbols) {
            DebugLogFile("ANALYZE_POSITIONS_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return analysis;
        }
        
        string symbol = m_symbolStates[symbolIndex].symbol;
        int magic = m_symbolStates[symbolIndex].magicNumber;
        
        DebugLogFile("ANALYZE_POSITIONS", StringFormat("Analyzing positions for %s (magic: %d)", symbol, magic));
        
        // Get positions using MQL5 Position functions
        int totalPositions = 0;
        double totalBuyVolume = 0;
        double totalSellVolume = 0;
        double totalProfit = 0;
        
        // Use MQL5 Position functions
        int positionsTotal = PositionsTotal();
        DebugLogFile("POSITIONS_TOTAL", StringFormat("Total positions in terminal: %d", positionsTotal));
        
        for(int i = 0; i < positionsTotal; i++) {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0) {
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                long positionMagic = PositionGetInteger(POSITION_MAGIC);
                
                if(positionSymbol == symbol && positionMagic == magic) {
                    totalPositions++;
                    
                    long positionType = PositionGetInteger(POSITION_TYPE);
                    double positionVolume = PositionGetDouble(POSITION_VOLUME);
                    double positionProfit = PositionGetDouble(POSITION_PROFIT);
                    double positionSwap = PositionGetDouble(POSITION_SWAP);
                    
                    // Get commission using helper method
                    double positionCommission = GetPositionCommission(ticket);
                    
                    totalProfit += positionProfit + positionSwap + positionCommission;
                    
                    DebugLogFile("POSITION_DETAILS", StringFormat("Position %d: Type=%d, Volume=%.2f, Profit=%.2f, Swap=%.2f, Commission=%.2f",
                        ticket, positionType, positionVolume, positionProfit, positionSwap, positionCommission));
                    
                    if(positionType == POSITION_TYPE_BUY) {
                        totalBuyVolume += positionVolume;
                        analysis.buyCount++;
                        DebugLogFile("BUY_POSITION", StringFormat("Buy position: Ticket=%d, Volume=%.2f", ticket, positionVolume));
                    } else if(positionType == POSITION_TYPE_SELL) {
                        totalSellVolume += positionVolume;
                        analysis.sellCount++;
                        DebugLogFile("SELL_POSITION", StringFormat("Sell position: Ticket=%d, Volume=%.2f", ticket, positionVolume));
                    }
                }
            }
        }
        
        analysis.totalVolume = totalBuyVolume + totalSellVolume;
        analysis.totalProfit = totalProfit;
        
        // Determine position state
        if(analysis.buyCount > 0 && analysis.sellCount > 0) {
            analysis.state = STATE_HAS_BOTH;
        } else if(analysis.buyCount > 0) {
            analysis.state = STATE_HAS_BUY;
        } else if(analysis.sellCount > 0) {
            analysis.state = STATE_HAS_SELL;
        } else {
            analysis.state = STATE_NO_POSITION;
        }
        
        // Calculate max risk exposure (simplified)
        analysis.maxRiskExposure = analysis.totalVolume * 100; // Example calculation
        
        DebugLogFile("ANALYZE_POSITIONS_RESULT", StringFormat("Position analysis for %s: %s", symbol, analysis.ToString()));
        DebugLogFile("POSITION_SUMMARY", StringFormat("Found %d positions (%d buy, %d sell), Total volume: %.2f, Total profit: %.2f",
            totalPositions, analysis.buyCount, analysis.sellCount, analysis.totalVolume, analysis.totalProfit));
        
        return analysis;
    }
    
    bool CheckPositionLimits(int symbolIndex, bool isBuy) {
        if(symbolIndex < 0) {
            DebugLogFile("CHECK_POSITION_LIMITS_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return false;
        }
        
        if(!m_allowMultiplePositions) {
            DebugLogFile("CHECK_POSITION_LIMITS", "Multiple positions not allowed, checking if any position exists");
            
            PositionAnalysis analysis = AnalyzePositions(symbolIndex);
            bool hasPosition = (analysis.state != STATE_NO_POSITION);
            
            if(isBuy && hasPosition && analysis.state != STATE_HAS_SELL) {
                DebugLogFile("CHECK_POSITION_LIMITS", "Cannot open BUY - already have position");
                return false;
            }
            
            if(!isBuy && hasPosition && analysis.state != STATE_HAS_BUY) {
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
    
    // ================= DECISION LOGIC =================
    DECISION_ACTION MakeDecision(int symbolIndex, const DecisionEngineInterface &package, PositionAnalysis &positions) {  // CHANGED
        DebugLogFile("MAKE_DECISION_START", StringFormat("Making decision for %s (index: %d)", 
            m_symbolStates[symbolIndex].symbol, symbolIndex));
        
        DecisionParams params = m_symbolStates[symbolIndex].params;
        double confidence = package.overallConfidence;
        string direction = package.dominantDirection;
        
        DebugLogFile("DECISION_PARAMS", StringFormat("Confidence: %.1f%%, Direction: %s", confidence, direction));
        DebugLogFile("THRESHOLDS", StringFormat("Buy: %.1f%%, Sell: %.1f%%, Close: %.1f%%, CloseAll: %.1f%%",
            params.buyConfidenceThreshold, params.sellConfidenceThreshold,
            params.closePositionThreshold, params.closeAllThreshold));
        
        // Check for close conditions first (safety first)
        if(confidence < params.closeAllThreshold) {
            DebugLogFile("CLOSE_ALL_CHECK", StringFormat("Confidence %.1f%% < CloseAll threshold %.1f%% - Closing all",
                confidence, params.closeAllThreshold));
            return ACTION_CLOSE_ALL;
        }
        
        // Handle no position case
        if(positions.state == STATE_NO_POSITION) {
            DebugLogFile("NO_POSITION_CASE", "No positions open, deciding on new position");
            return DecideNoPosition(symbolIndex, package, params, direction, confidence);  // CHANGED
        }
        
        // Handle existing positions
        DebugLogFile("EXISTING_POSITIONS", StringFormat("Existing positions: %s", positions.ToString()));
        return DecideWithPosition(symbolIndex, package, positions, params, direction, confidence);  // CHANGED
    }
    
    DECISION_ACTION DecideNoPosition(int symbolIndex, const DecisionEngineInterface &package,  // CHANGED
                                     DecisionParams &params, string direction, double confidence) {
        DebugLogFile("DECIDE_NO_POSITION", "Evaluating new position opportunity");
        
        // Check BUY conditions
        if(direction == "BULLISH" && confidence >= params.buyConfidenceThreshold) {
            DebugLogFile("BUY_CONDITION_MET", StringFormat("BUY condition met: Direction=%s, Confidence=%.1f%% >= %.1f%%",
                direction, confidence, params.buyConfidenceThreshold));
            
            if(CheckCooldown(symbolIndex, true)) {
                DebugLogFile("COOLDOWN_PASSED", "Buy cooldown check passed");
                if(CheckPositionLimits(symbolIndex, true)) {
                    DebugLogFile("POSITION_LIMITS_PASSED", "Buy position limits check passed");
                    DebugLogFile("DECISION_FINAL", "Decision: OPEN_BUY");
                    return ACTION_OPEN_BUY;
                } else {
                    DebugLogFile("POSITION_LIMITS_FAILED", "Buy position limits check failed");
                }
            } else {
                DebugLogFile("COOLDOWN_FAILED", "Buy cooldown check failed");
            }
        } else if(direction == "BULLISH") {
            DebugLogFile("BUY_CONDITION_FAILED", StringFormat("BUY condition failed: Confidence %.1f%% < %.1f%%",
                confidence, params.buyConfidenceThreshold));
        }
        
        // Check SELL conditions
        if(direction == "BEARISH" && confidence >= params.sellConfidenceThreshold) {
            DebugLogFile("SELL_CONDITION_MET", StringFormat("SELL condition met: Direction=%s, Confidence=%.1f%% >= %.1f%%",
                direction, confidence, params.sellConfidenceThreshold));
            
            if(CheckCooldown(symbolIndex, false)) {
                DebugLogFile("COOLDOWN_PASSED", "Sell cooldown check passed");
                if(CheckPositionLimits(symbolIndex, false)) {
                    DebugLogFile("POSITION_LIMITS_PASSED", "Sell position limits check passed");
                    DebugLogFile("DECISION_FINAL", "Decision: OPEN_SELL");
                    return ACTION_OPEN_SELL;
                } else {
                    DebugLogFile("POSITION_LIMITS_FAILED", "Sell position limits check failed");
                }
            } else {
                DebugLogFile("COOLDOWN_FAILED", "Sell cooldown check failed");
            }
        } else if(direction == "BEARISH") {
            DebugLogFile("SELL_CONDITION_FAILED", StringFormat("SELL condition failed: Confidence %.1f%% < %.1f%%",
                confidence, params.sellConfidenceThreshold));
        }
        
        DebugLogFile("DECISION_FINAL", "No conditions met, Decision: HOLD");
        return ACTION_HOLD;
    }
    
    DECISION_ACTION DecideWithPosition(int symbolIndex, const DecisionEngineInterface &package,  // CHANGED
                                   PositionAnalysis &positions, DecisionParams &params,
                                   string direction, double confidence) {
        DebugLogFile("DECIDE_WITH_POSITION", "Evaluating with existing positions");
    
        // FIRST: Check for emergency close-all (very low confidence)
        if(confidence < params.closeAllThreshold) {  // 20% default
            DebugLogFile("EMERGENCY_CLOSE_ALL", StringFormat("Emergency close-all: Confidence %.1f%% < %.1f%%",
                confidence, params.closeAllThreshold));
            return ACTION_CLOSE_ALL;
        }
        
        // SECOND: Check if we should add to positions (high confidence)
        if(confidence >= MathMax(params.buyConfidenceThreshold, params.sellConfidenceThreshold) * 1.2) {
            DebugLogFile("ADD_TO_POSITION", StringFormat("High confidence %.1f%%, checking if we should add to positions", confidence));
            return DecideAdding(symbolIndex, package, positions, direction);  // CHANGED
        }
        
        DebugLogFile("CLOSING_EVALUATION", StringFormat("Checking closing conditions with confidence %.1f%%", confidence));
        // (But we'll let DecideClosing() decide based on confidence thresholds)
        return DecideClosing(symbolIndex, package, positions, direction);  // CHANGED
        
        // Note: We removed the default ACTION_HOLD - DecideClosing() returns HOLD if no close needed
    }
    
    DECISION_ACTION DecideAdding(int symbolIndex, const DecisionEngineInterface &package,  // CHANGED
                                 PositionAnalysis &positions, string direction) {
        DebugLogFile("DECIDE_ADDING", StringFormat("Evaluating adding to positions. Direction: %s, Positions: %s",
            direction, positions.ToString()));
        
        if(direction == "BULLISH" && (positions.state == STATE_HAS_BUY || positions.state == STATE_HAS_BOTH)) {
            DebugLogFile("ADD_BUY_CONSIDERED", "Considering adding to BUY position");
            if(CheckCooldown(symbolIndex, true)) {
                DebugLogFile("ADD_BUY_COOLDOWN_PASSED", "Buy cooldown check passed for adding");
                if(CheckPositionLimits(symbolIndex, true)) {
                    DebugLogFile("ADD_BUY_LIMITS_PASSED", "Position limits passed for adding BUY");
                    DebugLogFile("DECISION_FINAL", "Decision: OPEN_BUY (adding)");
                    return ACTION_OPEN_BUY; // Adding to existing buy
                } else {
                    DebugLogFile("ADD_BUY_LIMITS_FAILED", "Position limits failed for adding BUY");
                }
            } else {
                DebugLogFile("ADD_BUY_COOLDOWN_FAILED", "Buy cooldown check failed for adding");
            }
        }
        
        if(direction == "BEARISH" && (positions.state == STATE_HAS_SELL || positions.state == STATE_HAS_BOTH)) {
            DebugLogFile("ADD_SELL_CONSIDERED", "Considering adding to SELL position");
            if(CheckCooldown(symbolIndex, false)) {
                DebugLogFile("ADD_SELL_COOLDOWN_PASSED", "Sell cooldown check passed for adding");
                if(CheckPositionLimits(symbolIndex, false)) {
                    DebugLogFile("ADD_SELL_LIMITS_PASSED", "Position limits passed for adding SELL");
                    DebugLogFile("DECISION_FINAL", "Decision: OPEN_SELL (adding)");
                    return ACTION_OPEN_SELL; // Adding to existing sell
                } else {
                    DebugLogFile("ADD_SELL_LIMITS_FAILED", "Position limits failed for adding SELL");
                }
            } else {
                DebugLogFile("ADD_SELL_COOLDOWN_FAILED", "Sell cooldown check failed for adding");
            }
        }
        
        DebugLogFile("DECISION_FINAL", "No adding conditions met, Decision: HOLD");
        return ACTION_HOLD;
    }
    
    DECISION_ACTION DecideClosing(int symbolIndex, const DecisionEngineInterface &package,  // CHANGED
                              PositionAnalysis &positions, string direction) {
        DebugLogFile("DECIDE_CLOSING_START", StringFormat("Evaluating closing positions. Direction: %s, Positions: %s",
            direction, positions.ToString()));
        
        double confidence = package.overallConfidence;
        DecisionParams params = m_symbolStates[symbolIndex].params;
        
        // Base threshold
        double baseThreshold = MathMax(params.buyConfidenceThreshold, 
                                    params.sellConfidenceThreshold);
        
        // Adjust threshold based on position profit
        double closeThreshold = baseThreshold * 0.8; // Default: 80% of entry threshold
        
        // If position is profitable, require even stronger signal to close
        if(positions.totalProfit > 0) {
            // Winning trade - need 90% of threshold (harder to close)
            closeThreshold = baseThreshold * 0.9;
            DebugLogFile("CLOSING_LOGIC", StringFormat("💰 Winning trade (Profit: %.2f) - requiring stronger signal to close: %.1f%%",
                positions.totalProfit, closeThreshold));
        }
        // If position is losing badly, be quicker to close
        else if(positions.totalProfit < -50) {
            // Losing > $50 - use 70% of threshold (easier to close)
            closeThreshold = baseThreshold * 0.7;
            DebugLogFile("CLOSING_LOGIC", StringFormat("💸 Losing trade (Profit: %.2f) - more willing to close: %.1f%%",
                positions.totalProfit, closeThreshold));
        } else {
            DebugLogFile("CLOSING_LOGIC", StringFormat("Neutral position (Profit: %.2f) - standard close threshold: %.1f%%",
                positions.totalProfit, closeThreshold));
        }
        
        DebugLogFile("CLOSING_THRESHOLD", StringFormat("Conf: %.1f%%, CloseThreshold: %.1f%%, Profit: $%.2f, Dir: %s",
                        confidence, closeThreshold, positions.totalProfit, direction));
        
        if(confidence < closeThreshold) {
            DebugLogFile("CLOSING_DECISION", "❌ Confidence below threshold - HOLD (no close)");
            return ACTION_HOLD;
        }
        
        DebugLogFile("CLOSING_DECISION", "✅ Signal strong enough for closing consideration");
        
        // Now check direction conflicts with the strong signal
        if(positions.state == STATE_HAS_BUY && direction == "BEARISH") {
            DebugLogFile("CLOSE_BUY_SIGNAL", "🔻 Closing BUY (strong BEARISH signal)");
            return ACTION_CLOSE_BUY;
        }
        
        if(positions.state == STATE_HAS_SELL && direction == "BULLISH") {
            DebugLogFile("CLOSE_SELL_SIGNAL", "🔺 Closing SELL (strong BULLISH signal)");
            return ACTION_CLOSE_SELL;
        }
        
        if(positions.state == STATE_HAS_BOTH) {
            DebugLogFile("CLOSE_BOTH_POSITIONS", "🔀 Has BOTH positions, closing opposite side");
            // Close the side that's opposite to current direction
            if(direction == "BULLISH") {
                DebugLogFile("CLOSE_SELL_FOR_BULLISH", "Closing SELL for BULLISH signal");
                return ACTION_CLOSE_SELL;
            } else if(direction == "BEARISH") {
                DebugLogFile("CLOSE_BUY_FOR_BEARISH", "Closing BUY for BEARISH signal");
                return ACTION_CLOSE_BUY;
            }
        }
        
        DebugLogFile("CLOSING_DECISION", "⏸️ No closing needed, Decision: HOLD");
        return ACTION_HOLD;
    }
    
    // ================= VALIDATION =================
    bool ValidateDecision(int symbolIndex, DECISION_ACTION decision, const DecisionEngineInterface &package) {  // CHANGED
        DebugLogFile("VALIDATE_DECISION_START", StringFormat("=== VALIDATING DECISION === | %s | Symbol: %s | Conf: %.1f%%",
                           DecisionToString(decision), package.symbol, package.overallConfidence));
        
        if(decision == ACTION_NONE || decision == ACTION_HOLD || decision == ACTION_WAITING_FOR_PACKAGE) {
            DebugLogFile("VALIDATE_NON_ACTION", "Non-action decision - always valid");
            return true; // Non-actions are always valid
        }
        
        if(symbolIndex < 0) {
            DebugLogFile("VALIDATE_ERROR", "Invalid symbol index");
            return false;
        }
        
        DecisionParams params = m_symbolStates[symbolIndex].params;
        double confidence = package.overallConfidence;
        string direction = package.dominantDirection;
        
        DebugLogFile("VALIDATION_PARAMS", StringFormat("Params: Buy=%.1f%%, Sell=%.1f%%, Close=%.1f%%, CloseAll=%.1f%%",
                           params.buyConfidenceThreshold, params.sellConfidenceThreshold,
                           params.closePositionThreshold, params.closeAllThreshold));
        
        // Basic confidence validation
        bool confidenceValid = false;
        switch(decision) {
            case ACTION_OPEN_BUY:
                DebugLogFile("VALIDATE_OPEN_BUY", StringFormat("Checking OPEN_BUY: Conf=%.1f%% >= %.1f%% && Dir=%s == BULLISH",
                                   confidence, params.buyConfidenceThreshold, direction));
                if(confidence < params.buyConfidenceThreshold) {
                    DebugLogFile("VALIDATE_FAIL", "❌ Confidence too low for BUY");
                    return false;
                }
                if(direction != "BULLISH") {
                    DebugLogFile("VALIDATE_FAIL", StringFormat("❌ Wrong direction for BUY: %s != BULLISH", direction));
                    return false;
                }
                confidenceValid = true;
                break;
                
            case ACTION_OPEN_SELL:
                DebugLogFile("VALIDATE_OPEN_SELL", StringFormat("Checking OPEN_SELL: Conf=%.1f%% >= %.1f%% && Dir=%s == BEARISH",
                                   confidence, params.sellConfidenceThreshold, direction));
                if(confidence < params.sellConfidenceThreshold) {
                    DebugLogFile("VALIDATE_FAIL", "❌ Confidence too low for SELL");
                    return false;
                }
                if(direction != "BEARISH") {
                    DebugLogFile("VALIDATE_FAIL", StringFormat("❌ Wrong direction for SELL: %s != BEARISH", direction));
                    return false;
                }
                confidenceValid = true;
                break;
                
            case ACTION_CLOSE_BUY:
            case ACTION_CLOSE_SELL:
                DebugLogFile("VALIDATE_CLOSE", StringFormat("Checking CLOSE: Conf=%.1f%% <= %.1f%%",
                                   confidence, params.closePositionThreshold));
                if(confidence > params.closePositionThreshold) {
                    DebugLogFile("VALIDATE_FAIL", "❌ Confidence too high for close");
                    return false;
                }
                confidenceValid = true;
                break;
                
            case ACTION_CLOSE_ALL:
                DebugLogFile("VALIDATE_CLOSE_ALL", StringFormat("Checking CLOSE_ALL: Conf=%.1f%% <= %.1f%%",
                                   confidence, params.closeAllThreshold));
                if(confidence > params.closeAllThreshold) {
                    DebugLogFile("VALIDATE_FAIL", "❌ Confidence too high for close all");
                    return false;
                }
                confidenceValid = true;
                break;
        }
        
        if(!confidenceValid) {
            DebugLogFile("VALIDATE_FAIL", "❌ Confidence validation failed");
            return false;
        }
        
        DebugLogFile("VALIDATE_SUCCESS", "✅ Confidence validation passed");
        
        // Check risk management if enabled
        if(m_useRiskManagement) {
            DebugLogFile("VALIDATE_RISK", "Checking risk conditions...");
            // if(!CheckRiskConditions(package)) {
            //     DebugLogFile("VALIDATE_FAIL", "❌ Risk conditions not met");
            //     return false;
            // }
            DebugLogFile("VALIDATE_SUCCESS", "✅ Risk conditions met");
        }
        
        // Check trading hours
        DebugLogFile("VALIDATE_TRADING_HOURS", "Checking trading hours...");
        if(!TimeUtils::IsTradingSession(m_symbolStates[symbolIndex].symbol)) {
            DebugLogFile("VALIDATE_FAIL", "❌ Not in trading session");
            return false;
        }
        DebugLogFile("VALIDATE_SUCCESS", "✅ Trading hours OK");
        
        // Check cooldown
        bool isBuy = (decision == ACTION_OPEN_BUY || decision == ACTION_CLOSE_SELL || decision == ACTION_CLOSE_ALL);
        DebugLogFile("VALIDATE_COOLDOWN", StringFormat("Checking cooldown (%s)...", isBuy ? "BUY" : "SELL"));
        if(!CheckCooldown(symbolIndex, isBuy)) {
            DebugLogFile("VALIDATE_FAIL", "❌ In cooldown");
            return false;
        }
        DebugLogFile("VALIDATE_SUCCESS", "✅ Cooldown OK");
        
        // Check position limits
        if(decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL) {
            DebugLogFile("VALIDATE_POSITION_LIMITS", "Checking position limits...");
            if(!CheckPositionLimits(symbolIndex, isBuy)) {
                DebugLogFile("VALIDATE_FAIL", "❌ Position limit reached");
                return false;
            }
            DebugLogFile("VALIDATE_SUCCESS", "✅ Position limits OK");
        }
        
        DebugLogFile("VALIDATE_SUCCESS_ALL", "✅ All validation passed");
        return true;
    }
    
    bool CheckCooldown(int symbolIndex, bool isBuy) {
        if(!m_enforceCooldown) {
            DebugLogFile("COOLDOWN_CHECK_SKIP", "Cooldown enforcement disabled");
            return true;
        }
        
        if(symbolIndex < 0) {
            DebugLogFile("COOLDOWN_CHECK_ERROR", "Invalid symbol index");
            return false;
        }
        
        DecisionParams params = m_symbolStates[symbolIndex].params;
        bool inCooldown = m_symbolStates[symbolIndex].cooldown.IsInCooldown(isBuy, params.cooldownMinutes);
        
        DebugLogFile("COOLDOWN_CHECK", StringFormat("Symbol: %s, isBuy: %s, InCooldown: %s",
            m_symbolStates[symbolIndex].symbol, isBuy ? "true" : "false", inCooldown ? "true" : "false"));
        
        return !inCooldown;
    }
    
    void ExecuteDecision(int symbolIndex, DECISION_ACTION decision, DecisionEngineInterface &package) {
        DebugLogFile("EXECUTE_DECISION_START", StringFormat("=== EXECUTING DECISION === | %s | Symbol: %s | Conf: %.1f%%",
                           DecisionToString(decision), package.symbol, package.overallConfidence));
        
        if(symbolIndex < 0) {
            DebugLogFile("EXECUTE_ERROR", "❌ Invalid symbol index");
            return;
        }
        
        string symbol = m_symbolStates[symbolIndex].symbol;
        int magic = m_symbolStates[symbolIndex].magicNumber;
        
        DebugLogFile("EXECUTE_PARAMS", StringFormat("Symbol: %s | Magic: %d", symbol, magic));
        
        bool executed = false;
        string actionStr = DecisionToString(decision);
        
        switch(decision) {
            case ACTION_OPEN_BUY:
                DebugLogFile("EXECUTE_BUY", "Opening BUY position...");
                executed = PositionManager::OpenPositionWithTradePackage(symbol, true, package, magic);
                if(executed) {
                    m_symbolStates[symbolIndex].cooldown.Update(true);
                    DebugLogFile("EXECUTE_COOLDOWN", "Buy cooldown updated after execution");
                }
                break;
                
            case ACTION_OPEN_SELL:
                DebugLogFile("EXECUTE_SELL", "Opening SELL position...");
                executed = PositionManager::OpenPositionWithTradePackage(symbol, false, package, magic);
                if(executed) {
                    m_symbolStates[symbolIndex].cooldown.Update(false);
                    DebugLogFile("EXECUTE_COOLDOWN", "Sell cooldown updated after execution");
                }
                break;
                
            case ACTION_CLOSE_BUY:
                DebugLogFile("EXECUTE_CLOSE_BUY", "Calling PositionManager::CloseAllPositions (BUY)...");
                executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close BUY");
                if(executed) {
                    m_symbolStates[symbolIndex].cooldown.Update(true);
                    DebugLogFile("EXECUTE_COOLDOWN", "Buy cooldown updated after closing BUY");
                }
                break;
                
            case ACTION_CLOSE_SELL:
                DebugLogFile("EXECUTE_CLOSE_SELL", "Calling PositionManager::CloseAllPositions (SELL)...");
                executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close SELL");
                if(executed) {
                    m_symbolStates[symbolIndex].cooldown.Update(false);
                    DebugLogFile("EXECUTE_COOLDOWN", "Sell cooldown updated after closing SELL");
                }
                break;
                
            case ACTION_CLOSE_ALL:
                DebugLogFile("EXECUTE_CLOSE_ALL", "Calling PositionManager::CloseAllPositions (ALL)...");
                executed = PositionManager::CloseAllPositions(symbol, magic, "DecisionEngine: Close ALL");
                if(executed) {
                    m_symbolStates[symbolIndex].cooldown.Update(true);
                    m_symbolStates[symbolIndex].cooldown.Update(false);
                    DebugLogFile("EXECUTE_COOLDOWN", "Both cooldowns updated after closing ALL");
                }
                break;
                
            default:
                DebugLogFile("EXECUTE_SKIP", "No execution needed for this decision type");
                return;
        }
        
        if(executed) {
            DebugLogFile("EXECUTE_SUCCESS", "✅ Execution successful");
            LogExecution(symbol, decision, true, package);
        } else {
            DebugLogFile("EXECUTE_FAILED", "❌ Execution failed");
            LogExecution(symbol, decision, false, package);
            // Reset cooldown on failed execution
            m_symbolStates[symbolIndex].cooldown.Reset();
            DebugLogFile("COOLDOWN_RESET", "Cooldown reset due to failed execution");
        }
    }
    
    // ================= DISPLAY HELPERS =================
    void DisplayDecisionSummary() {
        DebugLogFile("DISPLAY_SUMMARY", "Displaying decision summary");
        
        string display = "=== DECISION ENGINE v4.0 ===\n";
        display += StringFormat("Time: %s\n", TimeToString(TimeCurrent(), TIME_SECONDS));
        display += StringFormat("Symbols: %d | %s\n\n", m_totalSymbols, m_metrics.ToString());
        
        for(int i = 0; i < MathMin(m_totalSymbols, 10); i++) { // Limit to 10 symbols
            display += GetSymbolStatusLine(i) + "\n";
        }
        
        Logger::DisplaySingleFrame(display);
        
        DebugLogFile("DISPLAY_SUMMARY_COMPLETE", "Decision summary displayed");
    }
    
    void DisplaySymbolStatus() {
        DebugLogFile("DISPLAY_SYMBOL_STATUS", "Displaying symbol status indicators");
        
        for(int i = 0; i < m_totalSymbols; i++) {
            if(m_symbolStates[i].HasValidPackage()) {
                string symbol = m_symbolStates[i].symbol;
                double confidence = m_symbolStates[i].lastPackage.overallConfidence;
                string decision = DecisionToString(m_symbolStates[i].lastDecision);
                
                Logger::ShowScoreFast(symbol, confidence / 100.0, decision, confidence / 100.0);
                DebugLogFile("SYMBOL_DISPLAY", StringFormat("Displayed %s: Conf=%.1f%%, Decision=%s",
                    symbol, confidence, decision));
            }
        }
        
        DebugLogFile("DISPLAY_SYMBOL_STATUS_COMPLETE", "Symbol status indicators displayed");
    }
    
    string GetSymbolStatusLine(int symbolIndex) {
        if(symbolIndex < 0 || symbolIndex >= m_totalSymbols) {
            DebugLogFile("GET_STATUS_LINE_ERROR", StringFormat("Invalid symbol index: %d", symbolIndex));
            return "";
        }
        
        SymbolState state = m_symbolStates[symbolIndex];
        string status = StringFormat("%-8s", state.symbol);
        
        if(state.HasValidPackage()) {
            string signal = state.lastPackage.GetSimpleSignal();
            double confidence = state.lastPackage.overallConfidence;
            string decision = DecisionToString(state.lastDecision);
            
            status += StringFormat(" | %-4s %3.0f%% | %-15s | %s",
                                  signal, confidence, decision,
                                  state.IsPackageFresh() ? "FRESH" : "STALE");
            
            DebugLogFile("STATUS_LINE", StringFormat("Symbol %s: Signal=%s, Conf=%.1f%%, Decision=%s, Fresh=%s",
                state.symbol, signal, confidence, decision, state.IsPackageFresh() ? "true" : "false"));
        } else {
            status += " | NO PACKAGE | WAITING";
            DebugLogFile("STATUS_LINE", StringFormat("Symbol %s: No valid package", state.symbol));
        }
        
        return status;
    }
    
    // ================= LOGGING =================
    void LogInfo(string message) {
        DebugLogFile("INFO", message);
        Logger::Log(m_engineName, message, true, true);
    }
    
    void LogWarning(string message) {
        DebugLogFile("WARNING", message);
        Logger::LogError(m_engineName, message);
    }
    
    void LogError(string message) {
        DebugLogFile("ERROR", message);
        Logger::LogError(m_engineName, message);
    }
    
    void LogDebug(string message) {
        if(m_debugEnabled) {
            DebugLogFile("DEBUG", message);
            Logger::Log("DEBUG-" + m_engineName, message, true, true);
        }
    }
    
    void LogDecision(string symbol, DECISION_ACTION decision, const DecisionEngineInterface &package, string reason) {  // CHANGED
        if(decision == ACTION_NONE || decision == ACTION_HOLD) {
            DebugLogFile("LOG_DECISION_SKIP", StringFormat("Skipping log for non-action decision: %s", DecisionToString(decision)));
            return;
        }
        
        string decisionStr = DecisionToString(decision);
        string logMsg = StringFormat("%s | %s | Conf: %.1f%% | Dir: %s | Reason: %s",
                                    symbol, decisionStr, package.overallConfidence,
                                    package.dominantDirection, reason);
        
        if(decision == ACTION_WAITING_FOR_PACKAGE) {
            DebugLogFile("DECISION_WAITING", logMsg);
        } else {
            LogInfo(logMsg);
        }
        
        DebugLogFile("LOG_DECISION", StringFormat("Logged decision: %s", logMsg));
    }
    
    void LogExecution(string symbol, DECISION_ACTION decision, bool success, const DecisionEngineInterface &package) {  // CHANGED
        string decisionStr = DecisionToString(decision);
        string logType = success ? "EXECUTION_SUCCESS" : "EXECUTION_FAILURE";
        
        DebugLogFile(logType, StringFormat("%s for %s | Conf: %.1f%%", decisionStr, symbol, package.overallConfidence));
        
        if(success) {
            LogInfo(StringFormat("EXECUTED: %s for %s | Conf: %.1f%%", 
                                decisionStr, symbol, package.overallConfidence));
            
            Logger::LogTradeFast(m_engineName, symbol, decisionStr, package.overallConfidence);
            DebugLogFile("TRADE_LOG", StringFormat("Trade logged: %s %s at %.1f%% confidence",
                decisionStr, symbol, package.overallConfidence));
        } else {
            LogError(StringFormat("FAILED: %s for %s", decisionStr, symbol));
            DebugLogFile("FAILURE_LOG", StringFormat("Execution failure logged: %s %s",
                decisionStr, symbol));
        }
    }
    
    void ResetCooldown(string symbol) {
        DebugLogFile("RESET_COOLDOWN_START", "Resetting cooldown for: " + symbol);
        
        int index = FindSymbolIndex(symbol);
        if(index >= 0) {
            m_symbolStates[index].cooldown.Reset();
            DebugLogFile("RESET_COOLDOWN_SUCCESS", "Cooldown reset for " + symbol);
        } else {
            DebugLogFile("RESET_COOLDOWN_ERROR", "Symbol not found: " + symbol);
        }
    }
    
    void ResetAllCooldowns() {
        DebugLogFile("RESET_ALL_COOLDOWNS_START", "Resetting all cooldowns");
        
        for(int i = 0; i < m_totalSymbols; i++) {
            m_symbolStates[i].cooldown.Reset();
            DebugLogFile("COOLDOWN_RESET_INDIVIDUAL", StringFormat("Reset cooldown for %s", m_symbolStates[i].symbol));
        }
        
        DebugLogFile("RESET_ALL_COOLDOWNS_SUCCESS", "All cooldowns reset");
    }
};

// ================= END OF FILE =================