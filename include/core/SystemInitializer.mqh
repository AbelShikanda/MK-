//+------------------------------------------------------------------+
//|                   SystemInitializer.mqh                          |
//|                  Complete EA Setup & Management                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// ============================================================
// INCLUDES (MODULAR - Add modules as needed)
// ============================================================
#include "../utils/ResourceManager.mqh"

#include "../risk/AccountManager.mqh"
#include "../risk/RiskManager.mqh"
#include "../execution/PositionManager.mqh"
#include "../execution/DecisionEngine.mqh"  // <-- This gives us DecisionParams definition

#include "../MTF/MtfDetector.mqh"
#include "../MarketStructure/OrderBlock.mqh"

#include "../Confidence/MarketStructure.mqh"
#include "../Confidence/MTF.mqh"
#include "../execution/ConfidenceEngine.mqh"

// ============================================================
//               CONFIDENCE ENGINE BRIDGE FUNCTIONS
// ============================================================

// Global ConfidenceEngine instance
ConfidenceEngine* g_confidenceEngine = NULL;

// 1. Bridge function to get confidence score WITH SYMBOL
double GetConfidenceFromEngine(string symbol)
{
    if(g_confidenceEngine != NULL && g_confidenceEngine.IsInitialized()) 
    {
        // USE THE SYMBOL PARAMETER!
        double confidence = g_confidenceEngine.GetConfidenceScore(symbol);  // Changed!
        
        if(confidence < 10.0 || confidence > 90.0) // Log only extreme values
            PrintFormat("Bridge: Confidence for %s = %.1f%%", symbol, confidence);
        return confidence;
    }
    PrintFormat("ERROR: ConfidenceEngine not available for %s", symbol);
    return 50.0; // Default neutral confidence
}

// 2. Bridge function to get market direction WITH SYMBOL
MARKET_DIRECTION GetMarketDirectionFromEngine(string symbol)
{
    if(g_confidenceEngine != NULL && g_confidenceEngine.IsInitialized()) 
    {
        // USE THE SYMBOL PARAMETER!
        CONFIDENCE_SIGNAL signal = g_confidenceEngine.GetSignal(symbol);  // Changed!
        
        // Convert CONFIDENCE_SIGNAL to MARKET_DIRECTION
        if(signal == SIGNAL_STRONG_BUY || signal == SIGNAL_WEAK_BUY) 
        {
            return DIRECTION_BULLISH;
        }
        else if(signal == SIGNAL_STRONG_SELL || signal == SIGNAL_WEAK_SELL) 
        {
            return DIRECTION_BEARISH;
        }
        else if(signal == SIGNAL_NEUTRAL) 
        {
            return DIRECTION_RANGING;
        }
        else 
        {
            PrintFormat("WARN: %s direction = UNCLEAR (signal: %d)", symbol, signal);
            return DIRECTION_UNCLEAR;
        }
    }
    PrintFormat("ERROR: ConfidenceEngine not available for %s", symbol);
    return DIRECTION_UNCLEAR;
}

// 3. Bridge function to check if market is ranging WITH SYMBOL
bool IsMarketRangingFromEngine(string symbol)
{
    if(g_confidenceEngine != NULL && g_confidenceEngine.IsInitialized()) 
    {
        CONFIDENCE_SIGNAL signal = g_confidenceEngine.GetSignal(symbol);
        bool isRanging = (signal == SIGNAL_NEUTRAL);
        return isRanging;
    }
    PrintFormat("ERROR: ConfidenceEngine not available for %s", symbol);
    return false;
}

// ============================================================
//               SYSTEM INITIALIZER
// ============================================================
class SystemInitializer
{
private:
    // Components in dependency order
    ResourceManager* m_logger;

    AccountManager* m_accountMgr;
    RiskManager* m_riskMgr;
    PositionManager* m_posMgr;
    DecisionEngine* m_decisionEngine;
    
    MTFScorer* m_mtfScorer;

    COrderBlock* m_orderBlock;
    
    MTFEngine* m_mtfEngine;
    MarketStructureEngine* m_marketStructure;
    
    ConfidenceEngine* m_confidenceEngine;
    
    bool m_initialized;
    string m_errorMessage;
    
    // Logging control
    static datetime s_lastDebugTime;
    static int s_tickCounter;
    
    // ============================================================
    //               DEBUG METHODS
    // ============================================================
    void DebugEngineStatus()
    {
        static datetime lastDebugTime = 0;
        datetime currentTime = TimeCurrent();
        
        // Limit debug logging to once per minute
        if(currentTime - lastDebugTime < 60) 
            return;
        
        lastDebugTime = currentTime;
        
        if(!m_initialized) 
        {
            Print("DEBUG: System not initialized");
            return;
        }
        
        // 1. Check ConfidenceEngine
        if(m_confidenceEngine != NULL) 
        {
            if(m_confidenceEngine.IsInitialized()) 
            {
                double conf = m_confidenceEngine.GetTotalConfidence();
                PrintFormat("Status: Confidence=%.1f, Session=%s", 
                          conf, 
                          m_confidenceEngine.IsTradingSessionActive() ? "ACTIVE" : "INACTIVE");
            }
        } 
        
        // 2. Check DecisionEngine
        if(m_decisionEngine != NULL) 
        {
            PrintFormat("DecisionEngine: %d symbols", m_decisionEngine.GetSymbolCount());
        }
    }
    
    // Add this emergency fix method
    bool EmergencyAddSymbolToDecisionEngine(string symbol)
    {
        if(m_decisionEngine == NULL) 
        {
            Print("ERROR: DecisionEngine is NULL!");
            return false;
        }
        
        Print("EMERGENCY: Adding symbol ", symbol, " to DecisionEngine...");
        
        // Use the global DecisionParams from DecisionEngine.mqh
        DecisionParams params;
        params.buyConfidenceThreshold = 25.0;
        params.sellConfidenceThreshold = 25.0;
        params.addPositionThreshold = 30.0;
        params.closePositionThreshold = 10.0;
        params.closeAllThreshold = 5.0;
        params.cooldownMinutes = 5;
        params.maxPositionsPerSymbol = 3;
        params.riskPercent = 1.0;
        
        if(m_decisionEngine.AddSymbol(symbol, params)) 
        {
            Print("SUCCESS: Added ", symbol, " to DecisionEngine");
            
            // Connect bridge functions
            if(g_confidenceEngine != NULL) 
            {
                m_decisionEngine.SetConfidenceFunction(GetConfidenceFromEngine);
                m_decisionEngine.SetMarketDirectionFunction(GetMarketDirectionFromEngine);
                m_decisionEngine.SetRangingFunction(IsMarketRangingFromEngine);
            }
            
            return true;
        } 
        
        Print("ERROR: Could not add symbol");
        return false;
    }
    
    // ============================================================
    //               PRIMARY DEPENDANCY
    // ============================================================
    bool Initialize_Primary_Dep()
    {
        // Phase 1: ResourceManager (no dependencies)
        m_logger = new ResourceManager();
        if(m_logger == NULL)
        {
            m_errorMessage = "Failed to create ResourceManager";
            return false;
        }
        
        if(!m_logger.Initialize("SystemLog.csv", true, true, true))
        {
            m_errorMessage = "Failed to initialize ResourceManager";
            delete m_logger;
            m_logger = NULL;
            return false;
        }
        
        return true;
    }
    
    // ============================================================
    //               ACCOUNTS INITIALIZATION
    // ============================================================
    bool Initialize_Acocunts()
    {
        // Phase 2: AccountManager (needs ResourceManager)
        m_accountMgr = new AccountManager();
        if(m_accountMgr == NULL)
        {
            m_errorMessage = "Failed to create AccountManager";
            return false;
        }
        
        if(!m_accountMgr.Initialize(m_logger))
        {
            m_errorMessage = "Failed to initialize AccountManager";
            delete m_accountMgr;
            m_accountMgr = NULL;
            return false;
        }
        
        return true;
    }
    
    // ============================================================
    //               RISK INITIALIZATION
    // ============================================================
    bool Initialize_Risk(double maxDailyLoss, double maxPositionRisk, 
                         double maxExposure, int maxPositions)
    {
        // Phase 3: RiskManager (needs AccountManager + ResourceManager)
        m_riskMgr = new RiskManager();
        if(m_riskMgr == NULL)
        {
            m_errorMessage = "Failed to create RiskManager";
            return false;
        }
        
        // CRITICAL: Verify AccountManager is initialized
        if(m_accountMgr == NULL) 
        {
            m_errorMessage = "AccountManager not initialized before RiskManager";
            delete m_riskMgr;
            m_riskMgr = NULL;
            return false;
        }
        
        // Verify logger
        if(m_logger == NULL) 
        {
            m_errorMessage = "Logger not initialized before RiskManager";
            delete m_riskMgr;
            m_riskMgr = NULL;
            return false;
        }
        
        if(!m_riskMgr.Initialize(m_logger, m_accountMgr))
        {
            m_errorMessage = "Failed to initialize RiskManager";
            delete m_riskMgr;
            m_riskMgr = NULL;
            return false;
        }
        
        // Set risk parameters
        m_riskMgr.SetMaxDailyLossPercent(maxDailyLoss);
        m_riskMgr.SetMaxPositionRiskPercent(maxPositionRisk);
        m_riskMgr.SetMaxPortfolioExposure(maxExposure);
        m_riskMgr.SetMaxConcurrentPositions(maxPositions);
        
        return true;
    }
    
    // ============================================================
    //               DATA ANALYSIS COMPONENTS
    // ============================================================
    bool Initialize_MTF_Components(string m_symbol)
    {
        // Phase 1: MTFEngine (needs ResourceManager)
        m_mtfScorer = new MTFScorer();
        if(m_mtfScorer == NULL)
        {
            m_errorMessage = "Failed to create MTFEngine";
            return false;
        }
        
        if(!m_mtfScorer.Initialize(m_logger, m_symbol))
        {
            m_errorMessage = "Failed to initialize MTFEngine";
            delete m_mtfScorer;
            m_mtfScorer = NULL;
            return false;
        }

        return true;
    }
    
    bool Initialize_MarketStructure_Components(string m_symbol)
    {
        // Phase 1: OrderBlock (needs ResourceManager)
        m_orderBlock = new COrderBlock();
        if(m_orderBlock == NULL)
        {
            m_errorMessage = "Failed to create OrderBlock";
            return false;
        }
        
        if(!m_orderBlock.Initialize(m_logger, m_symbol))
        {
            m_errorMessage = "Failed to initialize OrderBlock";
            delete m_orderBlock;
            m_orderBlock = NULL;
            return false;
        }

        return true;
    }
    
    // ============================================================
    //               CONFIDENCE COMPONENTS
    // ============================================================
    bool Initialize_MTF(string m_symbol)
    {
        // Phase 1: MTFEngine (needs ResourceManager)
        m_mtfEngine = new MTFEngine();
        if(m_mtfEngine == NULL)
        {
            m_errorMessage = "Failed to create MTFEngine";
            return false;
        }
        
        if(!m_mtfEngine.Initialize(m_logger, m_mtfScorer, m_symbol))
        {
            m_errorMessage = "Failed to initialize MTFEngine";
            delete m_mtfEngine;
            m_mtfEngine = NULL;
            return false;
        }

        return true;
    }
    
    bool Initialize_MarketStructure()
    {
        // Phase 1: MarketStructure (needs ResourceManager)
        m_marketStructure = new MarketStructureEngine();
        if(m_marketStructure == NULL)
        {
            m_errorMessage = "Failed to create MarketStructure";
            return false;
        }
        
        if(!m_marketStructure.Initialize(m_logger, m_orderBlock))
        {
            m_errorMessage = "Failed to initialize MarketStructure";
            delete m_marketStructure;
            m_marketStructure = NULL;
            return false;
        }

        return true;
    }

    // ============================================================
    //               EXECUTION COMPONENTS
    // ============================================================
    
    bool Initialize_PositionManager(string expertName, int baseMagic, int slippage)
    {
        // Phase 4: PositionManager (needs RiskManager + ResourceManager)
        m_posMgr = new PositionManager();
        if(m_posMgr == NULL)
        {
            m_errorMessage = "Failed to create PositionManager";
            return false;
        }
        
        if(!m_posMgr.Initialize(expertName + "_Positions", baseMagic, 
                                 slippage, m_logger, m_riskMgr))
        {
            m_errorMessage = "Failed to initialize PositionManager";
            
            // Try alternative initialization
            delete m_posMgr;
            m_posMgr = new PositionManager();
            
            // Try without RiskManager first
            if(!m_posMgr.Initialize(
                expertName + "_Positions", 
                baseMagic, 
                slippage, 
                m_logger, 
                NULL))  // NULL RiskManager
            {
                delete m_posMgr;
                m_posMgr = NULL;
                return false;
            } 
        } 
        
        return true;
    }
    
    bool Initialize_DecisionEngine(string expertName, int baseMagic, int slippage)
    {
        // Phase 5: DecisionEngine (needs PositionManager + ResourceManager)
        m_decisionEngine = new DecisionEngine();
        if(m_decisionEngine == NULL)
        {
            m_errorMessage = "Failed to create DecisionEngine";
            return false;
        }
        
        if(!m_decisionEngine.Initialize(m_logger, m_posMgr, m_riskMgr, 
                                         expertName + "_Decisions", baseMagic, slippage))
        {
            m_errorMessage = "Failed to initialize DecisionEngine";
            
            // Try alternative initialization without PositionManager
            delete m_decisionEngine;
            m_decisionEngine = new DecisionEngine();
            
            if(!m_decisionEngine.Initialize(m_logger, NULL, m_riskMgr,
                                             expertName + "_Decisions", baseMagic, slippage))
            {
                delete m_decisionEngine;
                m_decisionEngine = NULL;
                return false;
            } 
        } 
        
        return true;
    }
    
    bool Initialize_Confidence(string m_symbol)
    {
        // Phase 5: ConfidenceEngine (needs MTFEngine + ResourceManager)
        m_confidenceEngine = new ConfidenceEngine();
        if(m_confidenceEngine == NULL)
        {
            m_errorMessage = "Failed to create ConfidenceEngine";
            return false;
        }
        
        if(!m_confidenceEngine.Initialize(m_logger, 
                                            m_marketStructure,
                                            m_mtfEngine, 
                                            m_riskMgr,
                                            m_symbol))
        {
            m_errorMessage = "Failed to initialize ConfidenceEngine";
            delete m_confidenceEngine;
            m_confidenceEngine = NULL;
            return false;
        }
        
        return true;
    }
    
    // ============================================================
    //               CONNECT CONFIDENCE TO DECISION ENGINE
    // ============================================================
    bool ConnectEngines(string symbol, double buyThreshold = 25.0, 
                       double sellThreshold = 25.0, double riskPercent = 1.0)
    {
        if(m_confidenceEngine == NULL || m_decisionEngine == NULL) 
        {
            m_errorMessage = "Engines not initialized for connection";
            return false;
        }
        
        // Set the global pointer so bridge functions can access it
        g_confidenceEngine = m_confidenceEngine;
        
        // Set up DecisionParams for the symbol - using global DecisionParams
        DecisionParams params;
        params.buyConfidenceThreshold = buyThreshold;
        params.sellConfidenceThreshold = sellThreshold;
        params.addPositionThreshold = buyThreshold + 10.0;
        params.closePositionThreshold = buyThreshold - 10.0;
        params.closeAllThreshold = buyThreshold - 15.0;
        params.cooldownMinutes = 5;
        params.maxPositionsPerSymbol = 3;
        params.riskPercent = riskPercent;
        
        // Add symbol to DecisionEngine
        if(!m_decisionEngine.AddSymbol(symbol, params)) 
        {
            m_errorMessage = "Failed to add symbol to DecisionEngine";
            
            // Try alternative method
            if(!m_decisionEngine.QuickInitialize(symbol, buyThreshold, sellThreshold, riskPercent)) 
            {
                return false;
            } 
        } 
        
        // ============ ADD THIS ONE LINE ============
        m_decisionEngine.SetDebugMode(true);
        
        // Connect ConfidenceEngine to DecisionEngine using bridge functions
        m_decisionEngine.SetConfidenceFunction(GetConfidenceFromEngine);
        m_decisionEngine.SetMarketDirectionFunction(GetMarketDirectionFromEngine);
        m_decisionEngine.SetRangingFunction(IsMarketRangingFromEngine);
        
        // Log the connection
        if(m_logger != NULL) 
        {
            m_logger.KeepNotes(symbol, AUTHORIZE, "SystemInitializer", 
                StringFormat("Engines connected: Confidence → Decision for %s (Thresholds: Buy=%.1f%%, Sell=%.1f%%)", 
                           symbol, buyThreshold, sellThreshold));
        }
        
        PrintFormat("SUCCESS: Engines connected for %s (Buy:%.1f%%, Sell:%.1f%%, Risk:%.1f%%)", 
                   symbol, buyThreshold, sellThreshold, riskPercent);
        
        return true;
    }
    
public:
    SystemInitializer() : 
        m_logger(NULL),
        m_accountMgr(NULL),
        m_riskMgr(NULL),
        m_posMgr(NULL),
        m_decisionEngine(NULL),
        m_mtfScorer(NULL),
        m_orderBlock(NULL),
        m_mtfEngine(NULL),
        m_marketStructure(NULL),
        m_confidenceEngine(NULL),
        m_initialized(false),
        m_errorMessage("")
    {
    }
    
    ~SystemInitializer()
    {
        CleanupAll();
    }
    
    // Main initialization method
    bool InitializeAll(
        string expertName = "TradingSystem",
        int baseMagic = 12345,
        int slippage = 5,
        double maxDailyLoss = 5.0,
        double maxPositionRisk = 2.0,
        double maxExposure = 30.0,
        int maxPositions = 5,
        string m_symbol = "",
        double confidenceBuyThreshold = 25.0,
        double confidenceSellThreshold = 25.0,
        double riskPercent = 1.0
    )
    {
        if(m_initialized) return true;
        
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", OBSERVE, "Initializer", 
                "Starting system initialization...");
        }
        
        Print("========================================");
        Print("SYSTEM INITIALIZATION STARTED");
        Print("========================================");
        
        // =============== PHASE 1: CORE RESOURCES ===============
        if(!Initialize_Primary_Dep()) {
            Print("ERROR: ResourceManager initialization failed");
            return false;
        }
        
        // =============== PHASE 2: ACCOUNT & RISK ===============
        if(!Initialize_Acocunts()) {
            Print("ERROR: AccountManager initialization failed");
            return false;
        }
        
        if(!Initialize_Risk(maxDailyLoss, maxPositionRisk, maxExposure, maxPositions)) {
            Print("ERROR: RiskManager initialization failed");
            return false;
        }
        
        // =============== PHASE 3: EXECUTION COMPONENTS ===============
        if(!Initialize_PositionManager(expertName, baseMagic, slippage)) {
            Print("ERROR: PositionManager initialization failed");
            return false;
        }
        
        if(!Initialize_DecisionEngine(expertName, baseMagic, slippage)) {
            Print("ERROR: DecisionEngine initialization failed");
            return false;
        }
        
        // =============== PHASE 4: DATA ANALYSIS ===============
        if(!Initialize_MTF_Components(m_symbol)) {
            Print("ERROR: MTF components initialization failed");
            return false;
        }
        
        if(!Initialize_MarketStructure_Components(m_symbol)) {
            Print("ERROR: Market Structure components initialization failed");
            return false;
        }
        
        // =============== PHASE 5: CONFIDENCE ENGINES ===============
        if(!Initialize_MTF(m_symbol)) {
            Print("ERROR: MTFEngine initialization failed");
            return false;
        }
        
        if(!Initialize_MarketStructure()) {
            Print("ERROR: MarketStructureEngine initialization failed");
            return false;
        }
        
        if(!Initialize_Confidence(m_symbol)) {
            Print("ERROR: ConfidenceEngine initialization failed");
            return false;
        }
        
        // =============== PHASE 6: CONNECT ENGINES ===============
        if(!ConnectEngines(m_symbol, confidenceBuyThreshold, confidenceSellThreshold, riskPercent)) {
            Print("ERROR: Engine connection failed");
            return false;
        }
        
        m_initialized = true;
        
        // ============ VERIFY CONNECTION ============
        if(m_confidenceEngine != NULL && m_decisionEngine != NULL) 
        {
            // Check if symbol was added
            int symbolCount = m_decisionEngine.GetSymbolCount();
            
            if(symbolCount == 0) 
            {
                Print("WARN: No symbols in DecisionEngine - attempting emergency addition...");
                
                // Try to add manually as emergency fix
                DecisionParams emergencyParams;
                emergencyParams.buyConfidenceThreshold = confidenceBuyThreshold;
                emergencyParams.sellConfidenceThreshold = confidenceSellThreshold;
                emergencyParams.addPositionThreshold = confidenceBuyThreshold + 10.0;
                emergencyParams.closePositionThreshold = confidenceBuyThreshold - 10.0;
                emergencyParams.closeAllThreshold = confidenceBuyThreshold - 15.0;
                emergencyParams.cooldownMinutes = 5;
                emergencyParams.maxPositionsPerSymbol = 3;
                emergencyParams.riskPercent = riskPercent;
                
                if(!m_decisionEngine.AddSymbol(m_symbol, emergencyParams)) 
                {
                    Print("ERROR: Emergency symbol addition failed!");
                } 
            }
        }
        
        // ============ VERIFY ALL COMPONENTS ============
        bool allComponents = m_logger != NULL && m_accountMgr != NULL && 
                           m_riskMgr != NULL && m_posMgr != NULL && 
                           m_decisionEngine != NULL && m_mtfEngine != NULL && 
                           m_marketStructure != NULL && m_confidenceEngine != NULL;
        
        if(!allComponents) 
        {
            Print("WARN: Some components failed to initialize");
        }
        
        // Start ConfidenceEngine trading session
        if(m_confidenceEngine != NULL) 
        {
            m_confidenceEngine.StartTradingSession();
            if(m_logger != NULL) 
            {
                m_logger.KeepNotes("SYSTEM", AUTHORIZE, "SystemInitializer", 
                    "Trading session started for ConfidenceEngine");
            }
        } 
        
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", AUTHORIZE, "Initializer", "System initialized successfully");
        }
        
        Print("========================================");
        Print("SYSTEM INITIALIZATION COMPLETE");
        Print("========================================");
        
        return true;
    }
    
    // Event forwarding
    void OnTick()
    {
        if(!m_initialized) return;
        
        static int tickCounter = 0;
        static datetime lastStatusLog = 0;
        tickCounter++;
        
        // Log status only every 100 ticks or every minute
        datetime currentTime = TimeCurrent();
        if((tickCounter % 100 == 0 || (currentTime - lastStatusLog) >= 60) && m_logger != NULL) 
        {
            lastStatusLog = currentTime;
            m_logger.KeepNotes("SYSTEM", OBSERVE, "SystemInitializer_OnTick", 
                StringFormat("Tick #%d", tickCounter), 
                false, false, 0.0);
        }
        
        // Emergency fix: If DecisionEngine has no symbols after 3 ticks, add them
        if(tickCounter == 3 && m_decisionEngine != NULL) 
        {
            if(m_decisionEngine.GetSymbolCount() == 0) 
            {
                Print("EMERGENCY: DecisionEngine has no symbols after 3 ticks!");
                string currentSymbol = Symbol();
                EmergencyAddSymbolToDecisionEngine(currentSymbol);
            }
        }
        
        // Execute in logical order
        if(m_accountMgr != NULL) m_accountMgr.OnTick();
        if(m_riskMgr != NULL) m_riskMgr.OnTick();

        if(m_mtfScorer != NULL) m_mtfScorer.OnTick();

        if(m_orderBlock != NULL) m_orderBlock.OnTick();

        if(m_mtfEngine != NULL) m_mtfEngine.OnTick();

        if(m_marketStructure != NULL) m_marketStructure.OnTick();

        // ============ SAFETY CHECK - BEFORE ConfidenceEngine ============
        if(m_confidenceEngine != NULL && !m_confidenceEngine.IsTradingSessionActive()) 
        {
            m_confidenceEngine.StartTradingSession();
            if(m_logger != NULL) 
            {
                m_logger.KeepNotes("SYSTEM", WARN, "SystemInitializer", 
                    "ConfidenceEngine session was inactive - forcing start");
            }
        }
        // ================================================================
        
        // Now safe to run ConfidenceEngine
        if(m_confidenceEngine != NULL) m_confidenceEngine.OnTick();
        
        // ============ DECISION ENGINE PROCESSING ============
        if(m_decisionEngine != NULL) 
        {
            m_decisionEngine.OnTick();
        }
        
        // PositionManager should be last
        if(m_posMgr != NULL) m_posMgr.OnTick();
    }
    
    void OnTimer()
    {
        if(!m_initialized) return;
        
        if(m_accountMgr != NULL) m_accountMgr.OnTimer();
        if(m_riskMgr != NULL) m_riskMgr.OnTimer();

        if(m_mtfScorer != NULL) m_mtfScorer.OnTimer();

        if(m_marketStructure != NULL) m_marketStructure.OnTimer();

        if(m_posMgr != NULL) m_posMgr.OnTimer();
        if(m_decisionEngine != NULL) m_decisionEngine.OnTimer();
    }
    
    void OnTrade()
    {
        if(!m_initialized) return;
        
        if(m_decisionEngine != NULL) m_decisionEngine.OnTradeTransaction();
    }
    
    // Cleanup in reverse dependency order
    void CleanupAll()
    {
        Print("System cleanup started");
        
        // Reset global pointer first
        g_confidenceEngine = NULL;
        
        // Cleanup in reverse dependency order
        delete m_decisionEngine; 
        m_decisionEngine = NULL;
        
        delete m_posMgr; 
        m_posMgr = NULL;
        
        delete m_confidenceEngine; 
        m_confidenceEngine = NULL;
        
        delete m_marketStructure; 
        m_marketStructure = NULL;
        
        delete m_orderBlock; 
        m_orderBlock = NULL;
        
        delete m_mtfEngine; 
        m_mtfEngine = NULL;
        
        delete m_mtfScorer; 
        m_mtfScorer = NULL;
        
        delete m_riskMgr; 
        m_riskMgr = NULL;
        
        delete m_accountMgr; 
        m_accountMgr = NULL;
        
        // Logger last
        delete m_logger; 
        m_logger = NULL;
        
        Print("System cleanup complete");
    }
    
    // Getters (FIXED - these are class methods, not global functions)
    bool IsInitialized() const { return m_initialized; }
    string GetErrorMessage() const { return m_errorMessage; }
    
    ResourceManager* GetLogger() const { return m_logger; }
    AccountManager* GetAccountManager() const { return m_accountMgr; }
    RiskManager* GetRiskManager() const { return m_riskMgr; }
    MTFScorer* GetMTFScorer() const { return m_mtfScorer; }
    COrderBlock* GetOrderBlock() const { return m_orderBlock; }
    MTFEngine* GetMTFEngine() const { return m_mtfEngine; }
    MarketStructureEngine* GetMarketStructure() const { return m_marketStructure; }  // Fixed typo
    ConfidenceEngine* GetConfidenceEngine() const { return m_confidenceEngine; }
    PositionManager* GetPositionManager() const { return m_posMgr; }
    DecisionEngine* GetDecisionEngine() const { return m_decisionEngine; }
    
    // Add this public method to manually trigger debug
    void ForceDebug()
    {
        DebugEngineStatus();
    }
};