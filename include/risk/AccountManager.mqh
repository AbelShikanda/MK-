//+------------------------------------------------------------------+
//|                     AccountManager.mqh                          |
//|                Specialized Account Risk Management              |
//|                  Optimized Performance Version                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include <Trade/Trade.mqh>
#include "../utils/ResourceManager.mqh"
#include "../utils/Utils.mqh"

// ============ ENUMERATIONS ============
enum ENUM_TRADING_MODE
{
    MODE_CONSERVATIVE,
    MODE_NORMAL,
    MODE_AGGRESSIVE
};

// ============ ACCOUNT MANAGER CLASS ============
class AccountManager
{
private:
    // Configuration
    double          m_maxDailyLossPercent;
    double          m_maxPositionRiskPercent;
    double          m_maxPortfolioExposure;
    int             m_maxConcurrentPositions;
    ENUM_TRADING_MODE m_tradingMode;
    int             m_accountTier;
    
    // State tracking
    double          m_startingBalance;
    double          m_dailyPnL;
    double          m_peakEquity;
    double          m_currentDrawdown;
    datetime        m_sessionStartTime;
    int             m_tradesToday;
    
    // Risk metrics
    double          m_totalExposure;
    double          m_riskPerTrade;
    
    // Trade limits
    bool            m_canOpenNewPositions;
    bool            m_canAddToPositions;
    bool            m_canUseAggressiveLogic;
    
    // Logger instance
    ResourceManager* rm_logger;
    
    // Performance tracking (no position caching)
    datetime        m_lastTickTime;
    datetime        m_lastHourlyCheck;
    datetime        m_lastDailyReset;
    datetime        m_lastStatusPrint;
    datetime        m_lastRiskCheck;
    int             m_tickCount;
    
    // Initialization flag
    bool            m_initialized;
    
public:
    // ============ CONSTRUCTOR ============
    AccountManager() : rm_logger(NULL), m_initialized(false)
    {
        ResetState();
    }
    
    ~AccountManager()
    {
        if(m_initialized)
            Deinitialize();
    }
    
    // ============ INITIALIZATION METHOD ============
    bool Initialize(ResourceManager* logger)
    {
        if(m_initialized)
            return true;
        
        if(logger == NULL)
        {
            Print("AccountManager: Error - Logger is NULL");
            return false;
        }
        
        rm_logger = logger;
        
        // Set default conservative settings
        m_maxDailyLossPercent = 5.0;
        m_maxPositionRiskPercent = 2.0;
        m_maxPortfolioExposure = 30.0;
        m_maxConcurrentPositions = 5;
        m_tradingMode = MODE_NORMAL;
        
        // Initialize tracking
        m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_dailyPnL = 0.0;
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_currentDrawdown = 0.0;
        m_sessionStartTime = TimeCurrent();
        m_tradesToday = 0;
        
        m_totalExposure = 0.0;
        m_riskPerTrade = 0.0;
        
        m_canOpenNewPositions = true;
        m_canAddToPositions = true;
        m_canUseAggressiveLogic = false;
        
        // Initialize performance tracking
        m_lastTickTime = TimeCurrent();
        m_lastHourlyCheck = TimeCurrent();
        m_lastDailyReset = TimeCurrent();
        m_lastStatusPrint = TimeCurrent();
        m_lastRiskCheck = TimeCurrent();
        m_tickCount = 0;
        
        // Determine account tier
        m_accountTier = DetermineAccountTier();
        
        // Mark as initialized
        m_initialized = true;
        
        // Essential initialization log
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", 
            StringFormat("Initialized | Tier %d | Balance: $%.2f", 
            m_accountTier, m_startingBalance));
            
        return true;
    }
    
    // ============ DEINITIALIZATION METHOD ============
    void Deinitialize()
    {
        if(!m_initialized)
            return;
        
        // Log deinitialization
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", "Deinitializing");
        
        ResetState();
        rm_logger = NULL;
        m_initialized = false;
        
        Print("AccountManager: Deinitialize() completed");
    }
    
    // ============ TICK HANDLER METHOD ============
    void OnTick()
    {
        if(!m_initialized)
            return;
            
        datetime currentTime = TimeCurrent();
        m_tickCount++;
        
        // Update risk metrics every 10 ticks instead of every tick
        if(m_tickCount % 10 == 0)
        {
            UpdateTotalExposure();
            CheckRiskLimits();
            UpdatePermissions();
        }
        
        // Update P&L and drawdown - simplified, no logging
        UpdateDailyPnL();
        
        m_lastTickTime = currentTime;
        
        // Call OnTimer periodically (every 100 ticks)
        if(m_tickCount % 100 == 0)
            OnTimer();
    }
    
    // ============ TIME-BASED HANDLER METHOD ============
    void OnTimer()
    {
        if(!m_initialized)
            return;
            
        datetime currentTime = TimeCurrent();
        
        // Hourly tasks
        if(currentTime - m_lastHourlyCheck >= 3600)
        {
            PerformHourlyTasks();
            m_lastHourlyCheck = currentTime;
        }
        
        // Daily reset check
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        
        if(dt.hour == 0 && dt.min == 0)
        {
            if(currentTime - m_lastDailyReset >= 86400)
            {
                PerformDailyReset();
                m_lastDailyReset = currentTime;
            }
        }
        
        // Print status every 5 minutes instead of every hour
        if(currentTime - m_lastStatusPrint >= 300)
        {
            PrintAccountStatus();
            m_lastStatusPrint = currentTime;
        }
    }
    
    // ============ TRADE TRANSACTION HANDLER ============
    void OnTradeTransaction(const MqlTradeTransaction &trans)
    {
        if(!m_initialized || rm_logger == NULL)
            return;
            
        rm_logger.AutoLogTradeTransaction(trans);
        
        // Update trade count only for opening trades
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
            if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
            {
                m_tradesToday++;
            }
        }
    }
    
    // ============ PUBLIC INTERFACE ============
    
    string GetAccountInterpretation()
    {
        if(!m_initialized || rm_logger == NULL) 
            return "AccountManager not initialized";
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        
        string interpretation = "";
        
        // Check equity vs balance
        if(equity > balance * 1.05)
            interpretation = "🔥 PROFITABLE SESSION";
        else if(equity < balance * 0.95)
            interpretation = "⚠️ LOSS SESSION";
        else
            interpretation = "⚖️ BREAKEVEN SESSION";
        
        // Check margin usage
        if(marginLevel > 500)
            interpretation += " | VERY SAFE MARGIN";
        else if(marginLevel > 200)
            interpretation += " | SAFE MARGIN";
        else if(marginLevel > 100)
            interpretation += " | MODERATE MARGIN";
        else if(marginLevel > 50)
            interpretation += " | RISKY MARGIN";
        else
            interpretation += " | CRITICAL MARGIN";
        
        // Daily performance summary only (no tick-by-tick logging)
        static datetime lastInterpretationLog = 0;
        if(TimeCurrent() - lastInterpretationLog >= 300) // Log every 5 minutes
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", interpretation);
            lastInterpretationLog = TimeCurrent();
        }
        
        return interpretation;
    }
    
    ENUM_ACCOUNT_HEALTH CheckRiskLimits()
    {
        if(!m_initialized || rm_logger == NULL) 
            return HEALTH_GOOD;
        
        datetime currentTime = TimeCurrent();
        static datetime lastDetailedLog = 0;
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double dailyLoss = m_startingBalance - equity;
        double dailyLossPercent = (dailyLoss / m_startingBalance) * 100;
        
        // Update peak equity and drawdown
        if(equity > m_peakEquity)
            m_peakEquity = equity;
        
        if(m_peakEquity > 0)
            m_currentDrawdown = ((m_peakEquity - equity) / m_peakEquity) * 100;
        
        ENUM_ACCOUNT_HEALTH health = HEALTH_GOOD;
        string healthStatus = "GOOD";
        RESOURCE_MANAGER logLevel = OBSERVE;
        
        // Check daily loss limit - CRITICAL
        if(dailyLossPercent >= m_maxDailyLossPercent)
        {
            health = HEALTH_CRITICAL;
            healthStatus = "CRITICAL";
            logLevel = ENFORCE;
        }
        // Check drawdown levels - WARNING
        else if(m_currentDrawdown >= 15.0)
        {
            health = HEALTH_WARNING;
            healthStatus = "WARNING";
            logLevel = WARN;
        }
        else if(m_currentDrawdown >= 10.0)
        {
            health = HEALTH_WARNING;
            healthStatus = "WARNING";
            logLevel = WARN;
        }
        
        // Check margin level - CRITICAL
        double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if(marginLevel > 0 && marginLevel < 100.0)
        {
            health = HEALTH_CRITICAL;
            healthStatus = "CRITICAL";
            logLevel = ENFORCE;
        }
        // Check margin level - WARNING
        else if(marginLevel > 0 && marginLevel < 150.0)
        {
            health = HEALTH_WARNING;
            healthStatus = "WARNING";
            logLevel = WARN;
        }
        
        // Log only on state changes or periodically
        if(health != HEALTH_GOOD || currentTime - lastDetailedLog >= 300)
        {
            rm_logger.KeepNotes("SYSTEM", logLevel, "AccountManager",
                StringFormat("Risk Check: %s | Loss: %.1f%% | Drawdown: %.1f%% | Margin: %.1f%%",
                healthStatus, dailyLossPercent, m_currentDrawdown, marginLevel));
            lastDetailedLog = currentTime;
        }
        
        return health;
    }
    
    double CalculatePositionSize(string symbol, double stopLossPoints)
    {
        if(!m_initialized || rm_logger == NULL) 
            return 0.0;
        
        if(stopLossPoints <= 0)
        {
            rm_logger.KeepNotes(symbol, ENFORCE, "AccountManager",
                StringFormat("Invalid stop loss points: %.1f", stopLossPoints));
            return 0.0;
        }
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
        double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if(tickValue == 0 || pointValue == 0)
        {
            rm_logger.KeepNotes(symbol, ENFORCE, "AccountManager",
                "Cannot calculate position size (invalid tick/point value)");
            return 0.0;
        }
        
        // Base risk amount (2% of equity)
        double baseRiskAmount = equity * (m_maxPositionRiskPercent / 100.0);
        
        // Adjust based on trading mode
        double modeMultiplier = 1.0;
        switch(m_tradingMode)
        {
            case MODE_CONSERVATIVE: 
                modeMultiplier = 0.5;
                break;
            case MODE_NORMAL: 
                modeMultiplier = 1.0;
                break;
            case MODE_AGGRESSIVE: 
                modeMultiplier = 1.5;
                break;
        }
        
        // Adjust based on account tier
        double tierMultiplier = 1.0 + ((m_accountTier - 1) * 0.2);
        
        // Adjust based on account health
        double healthMultiplier = 1.0;
        ENUM_ACCOUNT_HEALTH health = CheckRiskLimits();
        if(health == HEALTH_WARNING)
            healthMultiplier = 0.5;
        else if(health == HEALTH_CRITICAL)
            healthMultiplier = 0.0;
        
        // Calculate position size
        double riskAmount = baseRiskAmount * modeMultiplier * tierMultiplier * healthMultiplier;
        double positionSize = riskAmount / (stopLossPoints * tickValue * pointValue);
        
        // Apply broker limits
        positionSize = ApplyBrokerLimits(symbol, positionSize);
        
        // Log only significant position calculations
        static datetime lastPositionLog = 0;
        if(positionSize > 0 && TimeCurrent() - lastPositionLog >= 60)
        {
            rm_logger.KeepNotes(symbol, OBSERVE, "AccountManager",
                StringFormat("Position Size: %.3f lots | Risk: $%.2f | Mode: %s",
                positionSize, riskAmount, TradingModeToString(m_tradingMode)));
            lastPositionLog = TimeCurrent();
        }
        
        return positionSize;
    }
    
    bool CheckExposureLimits(string symbol, double proposedLotSize)
    {
        if(!m_initialized) 
            return false;
        
        // Calculate current total exposure (no caching)
        UpdateTotalExposure();
        
        // Calculate proposed exposure
        double proposedExposure = CalculateSymbolExposure(symbol, proposedLotSize);
        double totalAfter = m_totalExposure + proposedExposure;
        
        bool passed = true;
        string failureReason = "";
        
        // Check if we'd exceed max exposure
        if(totalAfter > m_maxPortfolioExposure)
        {
            passed = false;
            failureReason = StringFormat("Exposure limit: %.1f%% > %.1f%%", 
                totalAfter, m_maxPortfolioExposure);
        }
        // Check position count limit
        else if(PositionsTotal() >= m_maxConcurrentPositions)
        {
            passed = false;
            failureReason = StringFormat("Position count: %d >= %d", 
                PositionsTotal(), m_maxConcurrentPositions);
        }
        // Check if symbol already has too many positions
        else if(CountSymbolPositions(symbol) >= GetMaxPositionsPerSymbol())
        {
            passed = false;
            failureReason = StringFormat("Symbol positions: %d >= %d", 
                CountSymbolPositions(symbol), GetMaxPositionsPerSymbol());
        }
        
        // Log only failures or periodically
        static datetime lastExposureLog = 0;
        if(!passed || TimeCurrent() - lastExposureLog >= 300)
        {
            RESOURCE_MANAGER logLevel = passed ? OBSERVE : WARN;
            rm_logger.KeepNotes(symbol, logLevel, "AccountManager",
                StringFormat("Exposure %s: %.1f%% (Max: %.1f%%) | Positions: %d/%d",
                passed ? "OK" : "FAILED", totalAfter, m_maxPortfolioExposure,
                PositionsTotal(), m_maxConcurrentPositions));
            lastExposureLog = TimeCurrent();
        }
        
        return passed;
    }
    
    bool CanOpenPosition(string symbol, double lotSize, string reason = "")
    {
        if(!m_initialized) 
            return false;
        
        // Check risk limits first
        ENUM_ACCOUNT_HEALTH health = CheckRiskLimits();
        if(health == HEALTH_CRITICAL)
        {
            rm_logger.KeepNotes(symbol, ENFORCE, "AccountManager", 
                "Cannot open position: Account health CRITICAL");
            m_canOpenNewPositions = false;
            return false;
        }
        
        // Check exposure limits
        if(!CheckExposureLimits(symbol, lotSize))
            return false;
        
        // Check if trading mode allows this
        if(!IsTradingModeAllowed(reason))
            return false;
        
        // All checks passed
        m_canOpenNewPositions = true;
        
        // Log permission grant
        rm_logger.KeepNotes(symbol, AUTHORIZE, "AccountManager",
            StringFormat("Permission GRANTED for %s | Lots: %.3f", reason, lotSize));
        
        return true;
    }
    
    void SetTradingMode(ENUM_TRADING_MODE mode)
    {
        if(!m_initialized || rm_logger == NULL) 
            return;
        
        // Can't set aggressive mode if conditions don't allow
        if(mode == MODE_AGGRESSIVE && !m_canUseAggressiveLogic)
        {
            rm_logger.KeepNotes("SYSTEM", WARN, "AccountManager", 
                "Cannot set AGGRESSIVE mode - conditions not met");
            return;
        }
        
        ENUM_TRADING_MODE oldMode = m_tradingMode;
        m_tradingMode = mode;
        
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", 
            StringFormat("Trading mode changed: %s → %s", 
            TradingModeToString(oldMode), TradingModeToString(mode)));
    }
    
    ENUM_TRADING_MODE GetTradingMode() { return m_tradingMode; }
    
    void UpdatePermissions()
    {
        if(!m_initialized) 
            return;
        
        ENUM_ACCOUNT_HEALTH health = CheckRiskLimits();
        ENUM_TRADING_MODE oldMode = m_tradingMode;
        
        switch(health)
        {
            case HEALTH_CRITICAL:
                m_canOpenNewPositions = false;
                m_canAddToPositions = false;
                m_canUseAggressiveLogic = false;
                m_tradingMode = MODE_CONSERVATIVE;
                break;
                
            case HEALTH_WARNING:
                m_canOpenNewPositions = true;
                m_canAddToPositions = false;
                m_canUseAggressiveLogic = false;
                if(m_tradingMode != MODE_CONSERVATIVE)
                    m_tradingMode = MODE_NORMAL;
                break;
                
            case HEALTH_GOOD:
                m_canOpenNewPositions = true;
                m_canAddToPositions = true;
                m_canUseAggressiveLogic = (m_accountTier >= 3);
                break;
                
            case HEALTH_EXCELLENT:
                m_canOpenNewPositions = true;
                m_canAddToPositions = true;
                m_canUseAggressiveLogic = true;
                break;
        }
        
        // Log only on permission changes
        static bool lastCanOpen = true;
        static bool lastCanAdd = true;
        static bool lastCanAggressive = false;
        
        if(lastCanOpen != m_canOpenNewPositions || 
           lastCanAdd != m_canAddToPositions || 
           lastCanAggressive != m_canUseAggressiveLogic ||
           oldMode != m_tradingMode)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager",
                StringFormat("Permissions Updated | Open: %s | Add: %s | Aggressive: %s | Mode: %s",
                BoolToString(m_canOpenNewPositions),
                BoolToString(m_canAddToPositions),
                BoolToString(m_canUseAggressiveLogic),
                TradingModeToString(m_tradingMode)));
            
            lastCanOpen = m_canOpenNewPositions;
            lastCanAdd = m_canAddToPositions;
            lastCanAggressive = m_canUseAggressiveLogic;
        }
    }
    
    // ============ OPTIMIZED GETTERS ============
    bool CanOpenNewPositions() { 
        return m_initialized && m_canOpenNewPositions; 
    }
    
    bool CanAddToPositions() { 
        return m_initialized && m_canAddToPositions; 
    }
    
    bool CanUseAggressiveLogic() { 
        return m_initialized && m_canUseAggressiveLogic; 
    }
    
    int GetAccountTier() { 
        return m_initialized ? m_accountTier : 1; 
    }
    
    double GetCurrentDrawdown() { 
        return m_initialized ? m_currentDrawdown : 0.0; 
    }
    
    double GetDailyPnL() { 
        return m_initialized ? m_dailyPnL : 0.0; 
    }
    
    double GetTotalExposure() { 
        return m_initialized ? m_totalExposure : 0.0; 
    }
    
    bool IsInitialized() const { return m_initialized; }
    
    // ============ SETTERS ============
    void SetMaxDailyLossPercent(double percent) 
    { 
        if(!m_initialized) return;
        double oldValue = m_maxDailyLossPercent;
        m_maxDailyLossPercent = MathMax(percent, 1.0);
        LogConfigChange("MaxDailyLossPercent", oldValue, m_maxDailyLossPercent);
    }
    
    void SetMaxPositionRiskPercent(double percent) 
    { 
        if(!m_initialized) return;
        double oldValue = m_maxPositionRiskPercent;
        m_maxPositionRiskPercent = MathMax(percent, 0.5);
        LogConfigChange("MaxPositionRiskPercent", oldValue, m_maxPositionRiskPercent);
    }
    
    void SetMaxPortfolioExposure(double percent) 
    { 
        if(!m_initialized) return;
        double oldValue = m_maxPortfolioExposure;
        m_maxPortfolioExposure = MathMax(percent, 10.0);
        LogConfigChange("MaxPortfolioExposure", oldValue, m_maxPortfolioExposure);
    }
    
    void SetMaxConcurrentPositions(int count) 
    { 
        if(!m_initialized) return;
        int oldValue = m_maxConcurrentPositions;
        m_maxConcurrentPositions = MathMax(count, 1);
        LogConfigChange("MaxConcurrentPositions", oldValue, m_maxConcurrentPositions);
    }
    
    // ============ UTILITY FUNCTIONS ============
    void PrintAccountStatus()
    {
        if(!m_initialized) return;
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        
        string status = StringFormat(
            "Account Status | Tier: %d | Mode: %s | P&L: $%.2f (%.1f%%) | Drawdown: %.1f%% | Margin: %.1f%%",
            m_accountTier, TradingModeToString(m_tradingMode), m_dailyPnL, 
            (m_dailyPnL/m_startingBalance)*100, m_currentDrawdown, marginLevel);
        
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", status);
    }
    
    ResourceManager* GetLogger() { 
        return m_initialized ? rm_logger : NULL; 
    }
    
    void LogTradeExecution(string symbol, double lotSize, string direction, double price, double sl, double tp)
    {
        if(!m_initialized || rm_logger == NULL) return;
        
        m_tradesToday++;
        
        rm_logger.KeepNotes(symbol, AUTHORIZE, "AccountManager", 
            StringFormat("Trade executed: %s %.3f lots at %.5f", direction, lotSize, price));
    }
    
    void LogTradeClosure(string symbol, double profit, double balanceAfter)
    {
        if(!m_initialized || rm_logger == NULL) return;
        
        RESOURCE_MANAGER logLevel = profit > 0 ? AUTHORIZE : WARN;
        rm_logger.KeepNotes(symbol, logLevel, "AccountManager",
            StringFormat("Trade closed: %s $%.2f", profit > 0 ? "Profit" : "Loss", profit));
    }
    
private:
    // ============ PRIVATE HELPER FUNCTIONS ============
    
    void ResetState()
    {
        m_maxConcurrentPositions = 0;
        m_accountTier = 0;
        m_tradesToday = 0;
        m_tickCount = 0;
        
        m_lastTickTime = 0;
        m_lastHourlyCheck = 0;
        m_lastDailyReset = 0;
        m_lastStatusPrint = 0;
        m_lastRiskCheck = 0;
        
        m_maxDailyLossPercent = 5.0;
        m_maxPositionRiskPercent = 2.0;
        m_maxPortfolioExposure = 30.0;
        m_startingBalance = 0.0;
        m_dailyPnL = 0.0;
        m_peakEquity = 0.0;
        m_currentDrawdown = 0.0;
        m_totalExposure = 0.0;
        m_riskPerTrade = 0.0;
        
        m_canOpenNewPositions = true;
        m_canAddToPositions = true;
        m_canUseAggressiveLogic = false;
        
        m_tradingMode = MODE_NORMAL;
    }
    
    int DetermineAccountTier()
    {
        if(!m_initialized) return 1;
        
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        int tier;
        
        if(balance < 500.0) tier = 1;
        else if(balance < 5000.0) tier = 2;
        else if(balance < 20000.0) tier = 3;
        else if(balance < 100000.0) tier = 4;
        else tier = 5;
        
        return tier;
    }
    
    // ORIGINAL METHOD - NO CACHING
    void UpdateTotalExposure()
    {
        if(!m_initialized) return;
        
        m_totalExposure = 0.0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                // Calculate exposure for this position
                double exposure = CalculateSymbolExposure(symbol, volume);
                m_totalExposure += exposure;
            }
        }
    }
    
    double CalculateSymbolExposure(string symbol, double lotSize)
    {
        return lotSize * 1.0; // Simplified: 1% exposure per lot
    }
    
    double ApplyBrokerLimits(string symbol, double lots)
    {
        if(!m_initialized) return lots;
        
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        double originalLots = lots;
        
        lots = MathMax(lots, minLot);
        lots = MathMin(lots, maxLot);
        
        if(lotStep > 0)
            lots = MathRound(lots / lotStep) * lotStep;
        
        return lots;
    }
    
    int CountSymbolPositions(string symbol)
    {
        if(!m_initialized) return 0;
        
        int count = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                    count++;
            }
        }
        
        return count;
    }
    
    int GetMaxPositionsPerSymbol()
    {
        if(!m_initialized) return 1;
        
        switch(m_accountTier)
        {
            case 1: return 1;
            case 2: return 2;
            case 3: return 3;
            case 4: return 4;
            case 5: return 5;
            default: return 1;
        }
    }
    
    bool IsTradingModeAllowed(string reason)
    {
        if(!m_initialized) return true;
        
        // Aggressive actions only allowed in aggressive mode
        string aggressiveActions[] = {"BREAKOUT", "REVERSAL", "MARTINGALE", "SCALPING"};
        
        for(int i = 0; i < ArraySize(aggressiveActions); i++)
        {
            if(StringFind(reason, aggressiveActions[i]) >= 0 && m_tradingMode != MODE_AGGRESSIVE)
            {
                rm_logger.KeepNotes("SYSTEM", WARN, "AccountManager",
                    StringFormat("Trading mode restriction: %s requires AGGRESSIVE mode", aggressiveActions[i]));
                return false;
            }
        }
        
        return true;
    }
    
    string TradingModeToString(ENUM_TRADING_MODE mode)
    {
        switch(mode)
        {
            case MODE_CONSERVATIVE: return "CONSERVATIVE";
            case MODE_NORMAL: return "NORMAL";
            case MODE_AGGRESSIVE: return "AGGRESSIVE";
            default: return "UNKNOWN";
        }
    }
    
    string BoolToString(bool value)
    {
        return value ? "YES" : "NO";
    }
    
    void LogConfigChange(string parameter, double oldValue, double newValue)
    {
        if(!m_initialized || rm_logger == NULL) return;
        
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", 
            StringFormat("Config changed: %s = %.1f → %.1f", parameter, oldValue, newValue));
    }
    
    void LogConfigChange(string parameter, int oldValue, int newValue)
    {
        if(!m_initialized || rm_logger == NULL) return;
        
        rm_logger.KeepNotes("SYSTEM", OBSERVE, "AccountManager", 
            StringFormat("Config changed: %s = %d → %d", parameter, oldValue, newValue));
    }
    
    void UpdateDailyPnL()
    {
        if(!m_initialized) return;
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_dailyPnL = equity - m_startingBalance;
    }
    
    void PerformHourlyTasks()
    {
        if(!m_initialized) return;
        
        // Auto flush logs
        if(rm_logger != NULL)
            rm_logger.AutoFlushAllSymbols();
    }
    
    void PerformDailyReset()
    {
        if(!m_initialized) return;
        
        rm_logger.KeepNotes("SYSTEM", AUTHORIZE, "AccountManager", 
            "Performing daily reset - starting new trading day");
        
        // Reset daily tracking
        m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_dailyPnL = 0.0;
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_currentDrawdown = 0.0;
        m_tradesToday = 0;
        m_sessionStartTime = TimeCurrent();
        
        // Reset permissions to default
        m_canOpenNewPositions = true;
        m_canAddToPositions = true;
        m_canUseAggressiveLogic = false;
        
        // Reset to normal trading mode
        m_tradingMode = MODE_NORMAL;
        
        // Update account tier
        m_accountTier = DetermineAccountTier();
        
        rm_logger.KeepNotes("SYSTEM", AUTHORIZE, "AccountManager",
            StringFormat("Daily reset complete | Balance: $%.2f | Tier: %d", 
            m_startingBalance, m_accountTier));
    }
};