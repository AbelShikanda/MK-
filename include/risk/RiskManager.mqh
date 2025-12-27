//+------------------------------------------------------------------+
//|                         RiskManager.mqh                          |
//|                   Comprehensive Risk Management System           |
//|                     DRY Version - Uses External Modules          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include <Trade/Trade.mqh>
#include <Arrays/ArrayObj.mqh>

// Include specialized modules
#include "TrailingSL.mqh"
#include "TakeProfit.mqh"
#include "StopLoss.mqh"
#include "AccountManager.mqh"  // Added AccountManager include

#include "../config/enums.mqh"
#include "../config/structures.mqh"
#include "../utils/Utils.mqh"
#include "../utils/ResourceManager.mqh"

/*
==============================================================
                            USECASE
==============================================================
This RiskManager now leverages specialized modules for:
1. Stop Loss calculation (StopLossManager.mqh)
2. Take Profit calculation (TakeProfit.mqh)
3. Trailing Stop management (TrailingSL.mqh)
4. Account management (AccountManager.mqh)

All position sizing, stop loss, take profit, and trailing logic
should delegate to these specialized modules.
==============================================================
*/

// ============ STRUCTURES ============

struct SymbolRisk
{
    string symbol;
    int positionCount;
    double totalExposure;
    double maxExposure;
    int maxPositions;
    double correlationFactor;
    
    int consecutiveWins;
    int consecutiveLosses;
    double symbolWinRate;
    bool inCooldown;
    datetime cooldownUntil;
};

// Forward declaration instead of include
class CStopLossManager;
class AccountManager;

// ============ CONSTANTS ============
const string STR_EMERGENCY_STOP_ACTIVE = "Emergency stop active";
const string STR_SYMBOL_COOLDOWN = "Symbol in cooldown period";
const string STR_TRADE_BLOCKED = "Trade blocked";
const string STR_TRADE_AUTHORIZED = "Trade authorized";

// ============ RISK MANAGER CLASS ============
class RiskManager
{
private:
    // Core Components
    CTrade m_trade;
    ResourceManager* m_logger;
    AccountManager* m_accountManager;  // Added AccountManager instance
    
    // CStopLossManagerodules
    CStopLossManager m_stopManager;
    CTakeProfit m_takeProfit;
    TrailingStopManager m_trailingManager;
    string m_currentSymbol;
    
    // Configuration
    double m_maxDailyLossPercent;
    double m_maxPositionRiskPercent;
    double m_maxPortfolioExposure;
    int m_maxConcurrentPositions;
    
    // Risk Levels
    double m_dailyLossThresholds[5];     // CRITICAL, HIGH, MODERATE, LOW, OPTIMAL
    double m_drawdownThresholds[5];
    double m_volatilityThresholds[5];
    
    // State Tracking
    double m_startingBalance;
    double m_weeklyPnL;
    double m_monthlyPnL;
    double m_peakEquity;
    
    datetime m_sessionStart;
    datetime m_lastTradeTime;
    
    // Risk Metrics
    RiskMetrics m_metrics;
    SymbolRisk m_symbolRisks[];
    PositionData m_openPositions[];
    
    // OPTIMIZED: Hot data grouped together
    struct HotData {
        bool m_initialized;
        bool m_emergencyStopActive;
        bool m_canOpenNewTrades;
        bool m_canAddToPositions;
        ENUM_RISK_LEVEL m_currentRiskLevel;
        double m_currentDrawdown;
        double m_dailyPnL;
    };
    HotData m_hotData;
    
    // OPTIMIZED: Performance metrics grouped
    struct PerformanceData {
        int m_totalTrades;
        int m_totalWins;
        int m_totalLosses;
        double m_totalProfit;
        double m_totalLoss;
        double m_winRate;
        double m_expectancy;
        double m_profitFactor;
        double m_avgRiskReward;
    };
    PerformanceData m_perfData;
    
    // Tier 1: Indicator & Data Caching
    struct SymbolDataCache {
        string symbol;
        double point;
        double tickValue;
        double contractSize;
        datetime lastUpdated;
    };
    SymbolDataCache m_symbolCache[];
    
    // Cache for expensive calculations
    struct VolatilityCache {
        string symbol;
        double volatility;
        double avgVolatility;
        datetime lastUpdated;
    };
    VolatilityCache m_volCache[];
    
    struct CalculationCache {
        string symbol;
        double value;
        datetime timestamp;
        int calculationType; // 1=volatility, 2=avgVolatility, 3=spread, etc.
    };
    CalculationCache m_calculationCache[50];
    int m_cacheIndex;
    
    // Position caching
    struct PositionCache {
        ulong tickets[100];
        int count;
        datetime lastUpdated;
    };
    PositionCache m_posCache;
    
    // Static caches
    static double s_cachedPoints[];
    static datetime s_lastPointUpdate;
    
    // Log frequency control - ADDED MISSING DECLARATIONS
    static datetime s_lastStatusPrint;
    static datetime s_lastErrorPrint[10];
    static int s_errorPrintIndex;
    
public:
    // ============ SECTION 1: INITIALIZATION & CONFIGURATION ============
    
    // CONSTRUCTOR - Sets default values only, NO initialization
    RiskManager()
    {
        // Initialize hot data
        m_hotData.m_initialized = false;
        m_hotData.m_emergencyStopActive = false;
        m_hotData.m_canOpenNewTrades = true;
        m_hotData.m_canAddToPositions = true;
        m_hotData.m_currentRiskLevel = RISK_MODERATE;
        m_hotData.m_currentDrawdown = 0.0;
        m_hotData.m_dailyPnL = 0.0;
        
        // Initialize performance data
        m_perfData.m_totalTrades = 0;
        m_perfData.m_totalWins = 0;
        m_perfData.m_totalLosses = 0;
        m_perfData.m_totalProfit = 0.0;
        m_perfData.m_totalLoss = 0.0;
        m_perfData.m_winRate = 0.0;
        m_perfData.m_expectancy = 0.0;
        m_perfData.m_profitFactor = 0.0;
        m_perfData.m_avgRiskReward = 0.0;
        
        // Initialize other int components
        m_maxConcurrentPositions = 0;
        m_cacheIndex = 0;
        m_posCache.count = 0;
        m_posCache.lastUpdated = 0;
        
        // Initialize all double components
        m_maxDailyLossPercent = 0.0;
        m_maxPositionRiskPercent = 0.0;
        m_maxPortfolioExposure = 0.0;
        m_startingBalance = 0.0;
        m_weeklyPnL = 0.0;
        m_monthlyPnL = 0.0;
        m_peakEquity = 0.0;
        
        // Initialize arrays
        ArrayInitialize(m_dailyLossThresholds, 0.0);
        ArrayInitialize(m_drawdownThresholds, 0.0);
        ArrayInitialize(m_volatilityThresholds, 0.0);
        
        // Set default configuration
        SetDefaultConfig();
        m_logger = NULL;
    }
    
    ~RiskManager()
    {
        Deinitialize();
    }
    
    // INITIALIZE() - The ONE AND ONLY real initialization method
    bool Initialize(ResourceManager* logger = NULL, 
                   AccountManager* accountManager = NULL)
    {
        if(m_hotData.m_initialized) 
        {
            return true;
        }
        
        // 1. Set dependencies
        m_logger = logger;
        
        // 2. Set configuration
        // SetMaxDailyLossPercent(maxDailyLoss);
        // SetMaxPositionRiskPercent(maxTradeRisk);
        // SetMaxPortfolioExposure(maxExposure);
        // SetMaxConcurrentPositions(maxPositions);
        
        // 3. Get starting balance
        m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_sessionStart = TimeCurrent();
        
        // 4. Initialize risk metrics
        InitializeRiskMetrics();
        
        // 5. Initialize specialized modules
        if(!InitializeSpecializedModules())
        {
            Print("RiskManager::Initialize() - Failed to initialize specialized modules");
            return false;
        }
        
        // 6. Log initialization - CRITICAL
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", OBSERVE, "RiskManager",
                StringFormat("Initialized | Balance: $%.2f | Risk Level: %s",
                m_startingBalance, RiskLevelToString(m_hotData.m_currentRiskLevel)));
        }
        
        m_hotData.m_initialized = true;
        return true;
    }
    
    // DEINITIALIZE() - Cleanup counterpart
    void Deinitialize()
    {
        if(!m_hotData.m_initialized) return;
        
        // 1. Cleanup specialized modules
        m_takeProfit.Cleanup();
        
        // 2. Reset state variables
        m_hotData.m_emergencyStopActive = false;
        m_hotData.m_canOpenNewTrades = false;
        m_hotData.m_canAddToPositions = false;
        
        // 3. Free arrays
        ArrayFree(m_symbolRisks);
        ArrayFree(m_openPositions);
        ArrayFree(m_symbolCache);
        ArrayFree(m_volCache);
        
        // 4. Reset initialization flag
        m_hotData.m_initialized = false;
        
        // 5. Log cleanup - CRITICAL
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", OBSERVE, "RiskManager", "Deinitialized");
        }
    }
    
    // Check if initialized
    bool IsInitialized() const { return m_hotData.m_initialized; }
    
    double GetMinimumStopLoss(string symbol)
    {
        // Symbol-specific minimum stops
        if(symbol == "XAUUSD" || symbol == "XAGUSD")
            return 80.0;
        else if(symbol == "EURUSD" || symbol == "GBPUSD")
            return 30.0;
        else
            return 20.0;
    }
    
    // ============ EVENT HANDLERS ============
    
    void OnTick()
    {
        // OPTIMIZED: Early exit
        if(!m_hotData.m_initialized) return;
        
        // 1. Update trailing stops on open positions
        UpdateTrailingStops();
        
        // OPTIMIZED: Cache position tickets with 2-second TTL
        if(TimeCurrent() > m_posCache.lastUpdated + 2)
        {
            m_posCache.count = PositionsTotal();
            for(int i = 0; i < m_posCache.count && i < 100; i++)
            {
                m_posCache.tickets[i] = PositionGetTicket(i);
            }
            m_posCache.lastUpdated = TimeCurrent();
        }
        
        // 2. Secure profits on profitable positions
        // OPTIMIZED: Use cached tickets and backward iteration
        for(int i = m_posCache.count - 1; i >= 0; i--)
        {
            ulong ticket = m_posCache.tickets[i];
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                if(profit > 0)
                {
                    SecureProfit(ticket);
                }
            }
        }
    }

    void OnTimer()
    {
        // OPTIMIZED: Early exit
        if(!m_hotData.m_initialized) return;
        
        // 1. Enforce drawdown limits
        EnforceDrawdownLimits();
        
        // 2. Close expired positions
        CloseExpiredPositions();
        
        // 3. Print status every hour - PERIODIC LOGGING
        static datetime lastPrint = 0;
        if(TimeCurrent() - lastPrint >= 3600)
        {
            PrintRiskStatus();
            lastPrint = TimeCurrent();
        }
    }
    
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                          const MqlTradeRequest& request,
                          const MqlTradeResult& result)
    {
        // OPTIMIZED: Early exit
        if(!m_hotData.m_initialized) return;
        
        // Only process order placement and position changes
        if(trans.type == TRADE_TRANSACTION_ORDER_ADD || 
           trans.type == TRADE_TRANSACTION_ORDER_UPDATE ||
           trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
            ProcessTradeTransaction(trans, request, result);
        }
    }
    
    // ============ SIMPLE INTEGRATION FUNCTIONS ============

    // Legacy wrapper for backward compatibility
    bool Initialize(double maxDailyLoss = 5.0, double maxTradeRisk = 2.0, 
                double maxExposure = 30.0, int maxPositions = 5)
    {
        // 1. Initialize with default dependencies
        if(!Initialize(NULL, NULL))
        {
            return false;
        }
        
        // 2. Set configuration
        SetMaxDailyLossPercent(maxDailyLoss);
        SetMaxPositionRiskPercent(maxTradeRisk);
        SetMaxPortfolioExposure(maxExposure);
        SetMaxConcurrentPositions(maxPositions);
        
        return m_hotData.m_initialized;
    }
    
    // ============ SECTION 2: CAPITAL PROTECTION ============
    
    bool AllowNewTrade(string symbol, double lots, string reason = "")
    {
        // OPTIMIZED: Check initialization FIRST (cheapest check)
        if(!m_hotData.m_initialized) 
        {
            return false;
        }
        
        // OPTIMIZED: Order checks from cheapest to most expensive
        // 1. Emergency stop check (very cheap)
        if(m_hotData.m_emergencyStopActive)
        {
            if(m_logger != NULL) {
                m_logger.KeepNotes(symbol, ENFORCE, "RiskManager", 
                    STR_EMERGENCY_STOP_ACTIVE, false, false, 0.0);
            }
            return false;
        }
        
        // 2. Symbol cooldown check (cheap)
        if(InCooldown(symbol))
        {
            if(m_logger != NULL) {
                m_logger.KeepNotes(symbol, WARN, "RiskManager", 
                    STR_SYMBOL_COOLDOWN, false, false, 0.0);
            }
            return false;
        }
        
        // 3. Position size validation (more expensive)
        double maxRisk = GetMaxRiskPerTrade(symbol);
        double proposedRisk = CalculateTradeRisk(symbol, lots);
        
        if(proposedRisk > maxRisk)
        {
            if(m_logger != NULL) {
                m_logger.KeepNotes(symbol, ENFORCE, "RiskManager", 
                    StringFormat("Trade blocked: Risk %.2f%% > Max %.2f%%",
                    proposedRisk, maxRisk), false, false, 0.0);
            }
            return false;
        }
        
        // All checks passed - TRADE EXECUTION LOG
        if(m_logger != NULL) {
            m_logger.KeepNotes(symbol, AUTHORIZE, "RiskManager", 
                StringFormat("%s: %s | Lots: %.3f | Risk: %.2f%%",
                STR_TRADE_AUTHORIZED, reason, lots, proposedRisk), false, false, 0.0);
        }
        
        return true;
    }
    
    void EnforceDrawdownLimits()
    {
        if(!m_hotData.m_initialized) return;
        
        // Use AccountManager's risk limits check
        ENUM_ACCOUNT_HEALTH accountHealth = m_accountManager.CheckRiskLimits();
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Update peak equity
        if(equity > m_peakEquity)
            m_peakEquity = equity;
        
        // Check drawdown thresholds using AccountManager's health
        ENUM_RISK_LEVEL newRiskLevel = m_hotData.m_currentRiskLevel;
        
        if(accountHealth == HEALTH_CRITICAL)
        {
            newRiskLevel = RISK_CRITICAL;
            ActivateEmergencyStop("Critical drawdown exceeded");
        }
        else if(accountHealth == HEALTH_WARNING)
        {
            newRiskLevel = RISK_HIGH;
            ReduceExposure();
        }
        else if(accountHealth == HEALTH_GOOD)
        {
            newRiskLevel = RISK_MODERATE;
            // Maintain current exposure
        }
        else if(accountHealth == HEALTH_EXCELLENT)
        {
            newRiskLevel = RISK_OPTIMAL;
            // Can increase exposure
        }
        
        // Update AccountManager permissions based on risk level
        UpdateAccountManagerPermissions(newRiskLevel);
        
        // Update risk level if changed - MAJOR STATE CHANGE
        if(newRiskLevel != m_hotData.m_currentRiskLevel)
        {
            m_hotData.m_currentRiskLevel = newRiskLevel;
            
            // Log risk level change - MAJOR STATE CHANGE
            if(m_logger != NULL)
            {
                m_logger.KeepNotes("SYSTEM", OBSERVE, "RiskManager",
                    StringFormat("Risk level changed to: %s", RiskLevelToString(newRiskLevel)));
            }
        }
    }
    
    void ActivateEmergencyStop(string reason)
    {
        m_hotData.m_emergencyStopActive = true;
        m_hotData.m_canOpenNewTrades = false;
        m_hotData.m_canAddToPositions = false;
        
        // Also update AccountManager permissions
        // m_accountManager.SetTradingMode(MODE_CONSERVATIVE);
        
        // EMERGENCY STOP LOG - CRITICAL
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", ENFORCE, "RiskManager",
                StringFormat("EMERGENCY STOP ACTIVATED: %s", reason), false, false, 0.0);
        }
        
        // Force close all positions
        ForceCloseAllPositions(reason);
    }
    
    // ============ SECTION 3: POSITION SIZING & PLACEMENT ============
    
    double GetOptimalStopLoss(string symbol, double entryPrice, bool isBuy)
    {
        // OPTIMIZED: Early exit for invalid input
        if(!m_hotData.m_initialized || entryPrice <= 0) return 0.0;
        
        // Auto-select method based on symbol
        ENUM_STOP_METHOD method = SelectStopMethod(symbol);
        
        // Create stop info
        SStopLevel stopInfo;
        
        // Calculate
        return m_stopManager.Calculate(symbol, entryPrice, isBuy, method, stopInfo);
    }

    ENUM_STOP_METHOD SelectStopMethod(string symbol)
    {
        // Example: Choose method based on symbol characteristics
        if(StringFind(symbol, "XAU") >= 0) return STOP_STRUCTURE;      // Gold - use ATR
        if(StringFind(symbol, "BTC") >= 0) return STOP_ATR;      // Crypto - use ATR
        if(StringFind(symbol, "JPY") >= 0) return STOP_STRUCTURE; // JPY pairs - use structure
        
        // Default to structure-based
        return STOP_STRUCTURE;
    }
    
    double GetOptimalTakeProfit(string symbol, ENUM_TIMEFRAMES timeframe,
                               double entryPrice, double stopLoss, bool isBuy)
    {
        if(!m_hotData.m_initialized) return 0.0;
        
        // Delegate to TakeProfit module
        return m_takeProfit.CalculateTP(symbol, timeframe, entryPrice, stopLoss, isBuy);
    }
    
    void ValidateStopLossPlacement(string symbol, double stopLoss, double entryPrice, bool isBuy)
    {
        if(!m_hotData.m_initialized) return;
        
        // OPTIMIZED: Cache point value
        double point = GetCachedPoint(symbol);
        double distancePips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
        
        // Check minimum stop distance
        double minStop = GetMinimumStopLoss(symbol);
        if(distancePips < minStop)
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, ENFORCE, "RiskManager",
                    StringFormat("Stop loss too close: %.1f pips < %.1f pips minimum",
                    distancePips, minStop), false, false, 0.0);
            }
            return;
        }
        
        // Check volatility-adjusted stop using ATR
        double atrStop = m_stopManager.Calculate(symbol, isBuy, entryPrice, STOP_ATR);
        double atrDistance = MathAbs(entryPrice - atrStop) / (point * 10.0);
        
        if(distancePips < atrDistance * 0.5) // Too tight relative to volatility
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, WARN, "RiskManager",
                    StringFormat("Stop loss may be too tight for volatility: %.1f vs %.1f pips",
                    distancePips, atrDistance), false, false, 0.0);
            }
        }
    }
    
    double CalculatePositionSize(string symbol, double stopLossPoints)
    {
        if(!m_hotData.m_initialized) return 0.01;
        
        // Use AccountManager's position sizing function
        return m_accountManager.CalculatePositionSize(symbol, stopLossPoints);
    }
    
    double CalculatePositionSizeFromCapital(string symbol, double capital)
    {
        // OPTIMIZED: Early exit for invalid input
        if(!m_hotData.m_initialized || capital <= 0) return 0.01;
        
        // OPTIMIZED: Cache symbol info
        static double cachedPrice = 0;
        static double cachedContractSize = 0;
        static string cachedSymbol = "";
        static datetime lastCacheUpdate = 0;
        
        if(cachedSymbol != symbol || TimeCurrent() > lastCacheUpdate + 60)
        {
            cachedPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            cachedContractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            cachedSymbol = symbol;
            lastCacheUpdate = TimeCurrent();
        }
        
        if(cachedPrice > 0 && cachedContractSize > 0)
        {
            double lots = capital / (cachedPrice * cachedContractSize);
            lots = ApplyBrokerLimits(symbol, lots);
            return lots;
        }
        
        return 0.01; // Default 0.01 lots
    }
    
    double CalculateRiskAdjustedPositionSizeFromCapital(string symbol, double capital, double stopLossPips)
    {
        if(!m_hotData.m_initialized) return 0.01;
    
        // TEMPORARY BYPASS - Use simple calculation
        if(m_accountManager == NULL)
        {
            // ERROR CONDITION - Keep logging
            Print("WARNING: AccountManager is NULL, using fallback position size");
            return 0.01; // Return minimum lot size
        }
        
        // Use AccountManager's position size calculation with stop loss points
        return m_accountManager.CalculatePositionSize(symbol, stopLossPips);
    }
    
    double CalculateRiskAdjustedSize(string symbol, double baseLots, 
                                    double stopLossPrice, ENUM_POSITION_TYPE direction)
    {
        if(!m_hotData.m_initialized) return baseLots;
        
        // Calculate current price
        double currentPrice = (direction == POSITION_TYPE_BUY) ?
            SymbolInfoDouble(symbol, SYMBOL_ASK) :
            SymbolInfoDouble(symbol, SYMBOL_BID);
        
        double stopDistance = MathAbs(currentPrice - stopLossPrice);
        double point = GetCachedPoint(symbol);
        double stopDistancePips = stopDistance / (point * 10.0);
        
        // Use AccountManager's position sizing with the calculated stop distance
        double adjustedLots = m_accountManager.CalculatePositionSize(symbol, stopDistancePips);
        
        return adjustedLots;
    }
    
    // ============ SECTION 4: PROFIT PROTECTION & TRAILING ============
    
    void SecureProfit(ulong ticket)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        
        // 1. NEW: Move to breakeven after $25 profit
        if(!IsBreakevenSet(ticket))
        {
            MoveToBreakevenAtDollarProfit(ticket, 25.0);  // $25 threshold
        }
    }
    
    void UpdateTrailingStops()
    {
        if(!m_hotData.m_initialized) return;
        
        // Delegate to TrailingStopManager
        m_trailingManager.UpdateAllTrails();
    }
    
    void UpdateTrailingStop(ulong ticket)
    {
        if(!m_hotData.m_initialized) return;
        
        // Delegate to TrailingStopManager
        m_trailingManager.UpdateTrail(ticket);
    }
    
    // ============ SECTION 5: EXPOSURE CONTROL ============
    
    bool CheckExposureLimits(string symbol, double proposedLots)
    {
        if(!m_hotData.m_initialized) return false;
    
        // TEMPORARY BYPASS
        if(m_accountManager == NULL)
        {
            // ERROR CONDITION - Keep logging
            Print("WARNING: AccountManager NULL in CheckExposureLimits, bypassing");
            return true; // Allow trade
        }
        
        // Use AccountManager's exposure check
        return m_accountManager.CheckExposureLimits(symbol, proposedLots);
    }
    
    // ============ SECTION 6: RISK QUALIFICATION ============
    
    bool IsSpreadAcceptable(string symbol, double maxSpreadMultiplier = 2.0)
    {
        if(!m_hotData.m_initialized) return false;
        
        double currentSpread = GetCurrentSpread(symbol);
        double avgSpread = GetAverageSpread(symbol);
        
        bool acceptable = currentSpread <= (avgSpread * maxSpreadMultiplier);
        
        if(!acceptable && m_logger != NULL)
        {
            m_logger.KeepNotes(symbol, WARN, "RiskManager",
                StringFormat("Spread too high: %.1f vs avg %.1f (%.1fx limit)",
                currentSpread, avgSpread, maxSpreadMultiplier), false, false, 0.0);
        }
        
        return acceptable;
    }
    
    bool IsMarginSufficient(string symbol, double lots)
    {
        if(!m_hotData.m_initialized) return false;
        
        double requiredMargin = CalculateMarginRequired(symbol, lots);
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        
        bool sufficient = freeMargin >= (requiredMargin * 1.5); // 50% buffer
        
        if(!sufficient && m_logger != NULL)
        {
            m_logger.KeepNotes(symbol, ENFORCE, "RiskManager",
                StringFormat("Insufficient margin: Required $%.2f, Free $%.2f",
                requiredMargin, freeMargin), false, false, 0.0);
        }
        
        return sufficient;
    }
    
    bool IsVolatilityAcceptable(string symbol)
    {
        return true;
    }
    
    // ============ SECTION 7: ACCOUNT-LEVEL SAFEGUARDS ============
    
    bool IsDailyLossLimitExceeded()
    {
        if(!m_hotData.m_initialized) return false;
        
        // Use AccountManager's daily PnL calculation
        double dailyPnL = m_accountManager.GetDailyPnL();
        double dailyLossPercent = (dailyPnL < 0 ? MathAbs(dailyPnL) / m_startingBalance : 0) * 100.0;
        
        return dailyLossPercent >= m_maxDailyLossPercent;
    }
    
    void ApplyCooldown(string symbol, int minutes = 60)
    {
        if(!m_hotData.m_initialized) return;
        
        int index = GetSymbolRiskIndex(symbol);
        if(index >= 0)
        {
            m_symbolRisks[index].inCooldown = true;
            m_symbolRisks[index].cooldownUntil = TimeCurrent() + (minutes * 60);
        }
    }
    
    bool InCooldown(string symbol)
    {
        if(!m_hotData.m_initialized) return false;
        
        int index = GetSymbolRiskIndex(symbol);
        if(index >= 0)
        {
            if(m_symbolRisks[index].inCooldown)
            {
                if(TimeCurrent() >= m_symbolRisks[index].cooldownUntil)
                {
                    m_symbolRisks[index].inCooldown = false;
                    return false;
                }
                return true;
            }
        }
        return false;
    }
    
    // ============ SECTION 8: PERFORMANCE FEEDBACK ============
    
    void UpdatePerformanceMetrics(bool win, double profit, double riskAmount)
    {
        if(!m_hotData.m_initialized) return;
        
        m_perfData.m_totalTrades++;
        
        if(profit > 0)
        {
            m_perfData.m_totalWins++;
            m_perfData.m_totalProfit += profit;
        }
        else
        {
            m_perfData.m_totalLosses++;
            m_perfData.m_totalLoss += MathAbs(profit);
        }
        
        // Update win rate
        if(m_perfData.m_totalTrades > 0)
            m_perfData.m_winRate = (double)m_perfData.m_totalWins / m_perfData.m_totalTrades * 100.0;
        
        // Update expectancy
        if(m_perfData.m_totalTrades > 0)
        {
            double avgWin = (m_perfData.m_totalWins > 0) ? m_perfData.m_totalProfit / m_perfData.m_totalWins : 0;
            double avgLoss = (m_perfData.m_totalLosses > 0) ? m_perfData.m_totalLoss / m_perfData.m_totalLosses : 0;
            double winProbability = m_perfData.m_winRate / 100.0;
            
            m_perfData.m_expectancy = (winProbability * avgWin) - ((1 - winProbability) * avgLoss);
        }
        
        // Update profit factor
        if(m_perfData.m_totalLoss > 0)
            m_perfData.m_profitFactor = m_perfData.m_totalProfit / m_perfData.m_totalLoss;
        
        // Check for deteriorating performance
        CheckPerformanceDeterioration();
    }
    
    // ============ SECTION 9: COMPLIANCE & ENFORCEMENT ============
    
    void ForceClose(ulong ticket, string reason)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);  // Get profit BEFORE closing
        
        if(m_trade.PositionClose(ticket))
        {
            // TRADE EXECUTION LOG - CRITICAL
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, ENFORCE, "RiskManager",
                    StringFormat("Position forced closed: %s | P&L: $%.2f",
                    reason, profit), true, (profit > 0), profit);
            }
            
            // Update metrics
            UpdatePerformanceMetrics((profit > 0), profit, 0);
        }
        else
        {
            // ERROR CONDITION - Keep logging
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, WARN, "RiskManager",
                    StringFormat("Failed to force close position: %s", reason), false, false, 0.0);
            }
        }
    }
    
    void ForceCloseAllPositions(string reason)
    {
        if(!m_hotData.m_initialized) return;
        
        // OPTIMIZED: Cache PositionsTotal() before loop
        int totalPositions = PositionsTotal();
        for(int i = totalPositions - 1; i >= 0; i--)  // OPTIMIZED: backward iteration
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                ForceClose(ticket, reason);
            }
        }
    }
    
    void CloseExpiredPositions()
    {
        if(!m_hotData.m_initialized) return;
        
        // OPTIMIZED: Cache PositionsTotal() before loop
        int totalPositions = PositionsTotal();
        for(int i = totalPositions - 1; i >= 0; i--)  // OPTIMIZED: backward iteration
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                int hoursOpen = int((TimeCurrent() - openTime) / 3600);
                int barsOpen = hoursOpen; // Since H1 = 1 hour
                
                if(barsOpen > GetMaxBarsInTrade(PositionGetString(POSITION_SYMBOL)))
                {
                    ForceClose(ticket, "Max time in trade exceeded");
                }
            }
        }
    }
    
    // ============ SECTION 10: GETTERS ============
    
    ENUM_RISK_LEVEL GetRiskLevel() { return m_hotData.m_currentRiskLevel; }
    bool CanOpenNewTrades() 
    { 
        return m_hotData.m_initialized && 
            m_hotData.m_canOpenNewTrades && 
            !m_hotData.m_emergencyStopActive && 
            (m_accountManager != NULL ? m_accountManager.CanOpenNewPositions() : true);
    }
    bool CanAddToPositions() { return m_hotData.m_initialized && m_hotData.m_canAddToPositions && m_accountManager.CanAddToPositions(); }
    double GetCurrentDrawdown() { return m_hotData.m_currentDrawdown; }
    double GetDailyPnL() { return m_hotData.m_initialized ? m_accountManager.GetDailyPnL() : 0.0; }
    double GetWinRate() { return m_perfData.m_winRate; }
    double GetExpectancy() { return m_perfData.m_expectancy; }
    double GetAverageRiskReward() { return m_perfData.m_avgRiskReward; }
    double GetProfitFactor() { return m_perfData.m_profitFactor; }
    
    double GetMaxRiskPerTrade(string symbol)
    {
        if(!m_hotData.m_initialized) return 0.0;
        
        // Adjust max risk based on current risk level
        double baseRisk = m_maxPositionRiskPercent;
        
        switch(m_hotData.m_currentRiskLevel)
        {
            case RISK_CRITICAL: return 0.0;
            case RISK_HIGH: return baseRisk * 0.5;
            case RISK_MODERATE: return baseRisk;
            case RISK_LOW: return baseRisk * 1.2;
            case RISK_OPTIMAL: return baseRisk * 1.5;
        }
        
        return baseRisk;
    }
    
    // ============ SECTION 11: SETTERS ============
    
    void SetMaxDailyLossPercent(double percent)
    {
        m_maxDailyLossPercent = MathMax(1.0, percent);
        // m_accountManager.SetMaxDailyLossPercent(percent); // Sync with AccountManager
        LogConfigChange("MaxDailyLossPercent", DoubleToString(percent, 1));
    }
    
    void SetMaxPositionRiskPercent(double percent)
    {
        m_maxPositionRiskPercent = MathMax(0.5, percent);
        // m_accountManager.SetMaxPositionRiskPercent(percent); // Sync with AccountManager
        LogConfigChange("MaxPositionRiskPercent", DoubleToString(percent, 1));
    }
    
    void SetMaxPortfolioExposure(double percent)
    {
        m_maxPortfolioExposure = MathMax(10.0, percent);
        // m_accountManager.SetMaxPortfolioExposure(percent); // Sync with AccountManager
        LogConfigChange("MaxPortfolioExposure", DoubleToString(percent, 1));
    }
    
    void SetMaxConcurrentPositions(int count)
    {
        m_maxConcurrentPositions = MathMax(1, count);
        // m_accountManager.SetMaxConcurrentPositions(count); // Sync with AccountManager
        LogConfigChange("MaxConcurrentPositions", IntegerToString(count));
    }
    
    // Module-specific setters
    void SetStopMethod(ENUM_STOP_METHOD method)
    {
        m_stopManager.SetDefaultMethod(method);
    }
    
    void SetTakeProfitMethod(ENUM_TP_TYPE method)
    {
        m_takeProfit.SetTPType(method);
    }
    
    void SetTrailingMethod(ENUM_TRAIL_METHOD method, double distance, double activation)
    {
        // Get symbol-appropriate base configuration
        TrailConfig config = GetTrailingConfigForSymbol(_Symbol);
        
        // Override with user-specified parameters
        config.method = method;
        config.distance = distance;
        config.activation = activation;
        
        // Apply symbol-specific validation rules
        // ApplySymbolSpecificValidation(_Symbol, config);
        
        m_trailingManager.Initialize(config);
        
        // Log the configuration - CONFIGURATION CHANGE
        if(m_logger != NULL)
        {
            m_logger.KeepNotes(_Symbol, OBSERVE, "RiskManager",
                StringFormat("Trailing set: Method=%s, Distance=%.1f, Activation=%.1f pips",
                EnumToString(config.method), config.distance, config.activation));
        }
    }
    
    // ============ SECTION 12: UTILITIES ============
    
    void PrintRiskStatus()
    {
        if(!m_hotData.m_initialized) return;
        
        // Get account interpretation from AccountManager
        string accountStatus = m_accountManager.GetAccountInterpretation();
        
        // OPTIMIZED: Pre-allocate string buffer
        string status;
        StringInit(status, 1024);
        
        status = "\n═══════════════════════════════════════════\n" +
                 "              RISK MANAGER STATUS\n" +
                 "═══════════════════════════════════════════\n";
        
        // OPTIMIZED: Use StringFormat for formatted strings
        status += StringFormat("Account Status: %s\n", accountStatus);
        status += StringFormat("Risk Level: %s\n", RiskLevelToString(m_hotData.m_currentRiskLevel));
        
        double dailyPnL = GetDailyPnL();
        status += StringFormat("Daily P&L: $%.2f (%.1f%%)\n", 
                              dailyPnL, (dailyPnL/m_startingBalance)*100);
        status += StringFormat("Drawdown: %.1f%% (Peak: $%.2f)\n", 
                              m_hotData.m_currentDrawdown, m_peakEquity);
        
        int positions = PositionsTotal();
        status += StringFormat("Positions: %d/%d\n", positions, m_maxConcurrentPositions);
        status += StringFormat("Emergency Stop: %s\n", 
                              m_hotData.m_emergencyStopActive ? "ACTIVE" : "INACTIVE");
        status += StringFormat("Can Open New: %s | Can Add: %s\n",
                              CanOpenNewTrades() ? "YES" : "NO",
                              CanAddToPositions() ? "YES" : "NO");
        
        status += "═══════════════════════════════════════════\n" +
                  "PERFORMANCE METRICS:\n" +
                  StringFormat("  Win Rate: %.1f%%\n", m_perfData.m_winRate) +
                  StringFormat("  Expectancy: $%.2f\n", m_perfData.m_expectancy) +
                  StringFormat("  Profit Factor: %.2f\n", m_perfData.m_profitFactor) +
                  StringFormat("  Total Trades: %d (W:%d L:%d)\n",
                              m_perfData.m_totalTrades, m_perfData.m_totalWins, m_perfData.m_totalLosses) +
                  "═══════════════════════════════════════════\n";
        
        Print(status);
    }
    
    void PrintAccountStatus()
    {
        if(!m_hotData.m_initialized) return;
        
        // Delegate to AccountManager
        // m_accountManager.PrintAccountStatus();
    }
    
    // ============ POSITION MANAGEMENT HELPERS ============
    
    bool MoveStopToBreakeven(ulong ticket)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
        
        // Add small buffer (configurable)
        double point = GetCachedPoint(symbol);
        double bufferPips = GetBreakevenBuffer(symbol);
        double buffer = bufferPips * point * 10.0;
        
        double breakevenSL = isBuy ? openPrice - buffer : openPrice + buffer;
        
        bool success = m_trade.PositionModify(ticket, breakevenSL, 0);
        
        return success;
    }
    
    bool MoveToBreakevenWithProfitCheck(ulong ticket, double minProfitPips = 10.0)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        
        // Calculate profit in pips
        double pipValue = GetPipValue(symbol);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double profitPips = (pipValue > 0 && volume > 0) ? 
            MathAbs(profit) / (pipValue * volume) : 0.0;
        
        // Only move to breakeven if we have sufficient profit
        if(profitPips >= minProfitPips)
        {
            bool success = MoveStopToBreakeven(ticket);
            return success;
        }
        
        return false;
    }
    
    bool MoveToBreakevenAtRiskReward(ulong ticket, double riskRewardRatio = 1.0)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        // Calculate original risk (stop distance)
        double point = GetCachedPoint(symbol);
        double originalRiskPips = MathAbs(openPrice - currentSL) / (point * 10.0);
        
        // Calculate current profit in pips
        double pipValue = GetPipValue(symbol);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double profitPips = (pipValue > 0 && volume > 0) ? 
            MathAbs(profit) / (pipValue * volume) : 0.0;
        
        // Check if profit reached risk-reward target
        if(originalRiskPips > 0 && profitPips >= (originalRiskPips * riskRewardRatio))
        {
            bool success = MoveStopToBreakeven(ticket);
            return success;
        }
        
        return false;
    }
    
    bool MoveStopToProfit(ulong ticket, double profitPips)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
        
        double point = GetCachedPoint(symbol);
        double profitDistance = profitPips * point * 10.0;
        
        double profitSL;
        if(isBuy)
        {
            profitSL = openPrice + profitDistance; // For buys, profit stop is above entry
        }
        else
        {
            profitSL = openPrice - profitDistance; // For sells, profit stop is below entry
        }
        
        // Ensure profit stop is better than current stop
        double currentSL = PositionGetDouble(POSITION_SL);
        bool shouldUpdate = (isBuy && profitSL > currentSL) || (!isBuy && profitSL < currentSL);
        
        if(shouldUpdate)
        {
            bool success = m_trade.PositionModify(ticket, profitSL, 0);
            return success;
        }
        
        return false;
    }
    
private:
    // ============ SECTION 13: PRIVATE HELPERS ============
    
    void SetDefaultConfig()
    {
        m_maxDailyLossPercent = 5.0;
        m_maxPositionRiskPercent = 2.0;
        m_maxPortfolioExposure = 30.0;
        m_maxConcurrentPositions = 5;
        
        // Risk level thresholds
        m_dailyLossThresholds[RISK_CRITICAL] = 5.0;
        m_dailyLossThresholds[RISK_HIGH] = 3.0;
        m_dailyLossThresholds[RISK_MODERATE] = 1.5;
        m_dailyLossThresholds[RISK_LOW] = 0.5;
        m_dailyLossThresholds[RISK_OPTIMAL] = 0.0;
        
        m_drawdownThresholds[RISK_CRITICAL] = 15.0;
        m_drawdownThresholds[RISK_HIGH] = 10.0;
        m_drawdownThresholds[RISK_MODERATE] = 5.0;
        m_drawdownThresholds[RISK_LOW] = 2.0;
        m_drawdownThresholds[RISK_OPTIMAL] = 0.0;
    }
    
    void InitializeRiskMetrics()
    {
        ZeroMemory(m_metrics);
        m_perfData.m_totalTrades = 0;
        m_perfData.m_totalWins = 0;
        m_perfData.m_totalLosses = 0;
        m_perfData.m_totalProfit = 0.0;
        m_perfData.m_totalLoss = 0.0;
        m_perfData.m_winRate = 0.0;
        m_perfData.m_expectancy = 0.0;
        m_perfData.m_profitFactor = 0.0;
        m_perfData.m_avgRiskReward = 0.0;
    }
    
    bool InitializeSpecializedModules()
    {
        // Initialize TakeProfit module
        m_takeProfit.Initialize(
            TP_FIXED_RR,        // Default to fixed RR
            GetDefaultRRRatio(), // Get from risk level
            2.0,               // ATR multiplier
            50,                // Structure lookback
            20,                // MA period
            MODE_SMA,          // MA method
            1,                 // Single target
            "100"              // Close 100% at target
        );
        
        // Configure StopLossManager
        m_stopManager.SetDefaultMethod(STOP_ATR);
        m_stopManager.SetATRMultiplier(GetATRMultiplier());
        
        // Configure TrailingStopManager
        TrailConfig config = GetTrailingConfigForSymbol(_Symbol);
        m_trailingManager.Initialize(config);

        return true;
    }
    
    void UpdateAccountManagerPermissions(ENUM_RISK_LEVEL riskLevel)
    {
        if(!m_hotData.m_initialized) return;
        
        // Update AccountManager trading mode based on risk level
        ENUM_TRADING_MODE tradingMode;
        
        switch(riskLevel)
        {
            case RISK_CRITICAL:
            case RISK_HIGH:
                tradingMode = MODE_CONSERVATIVE;
                break;
            case RISK_MODERATE:
                tradingMode = MODE_NORMAL;
                break;
            case RISK_LOW:
            case RISK_OPTIMAL:
                tradingMode = MODE_AGGRESSIVE;
                break;
            default:
                tradingMode = MODE_NORMAL;
        }
        
        // Only set aggressive mode if AccountManager allows it
        if(tradingMode == MODE_AGGRESSIVE && m_accountManager.CanUseAggressiveLogic())
        {
            // m_accountManager.SetTradingMode(tradingMode);
        }
        else if(tradingMode != MODE_AGGRESSIVE)
        {
            // m_accountManager.SetTradingMode(tradingMode);
        }
        
        // Update AccountManager permissions
        // m_accountManager.UpdatePermissions();
    }
    
    double GetStartingBalance()
    {
        return AccountInfoDouble(ACCOUNT_BALANCE);
    }
    
    int GetSymbolRiskIndex(string symbol)
    {
        int size = ArraySize(m_symbolRisks);
        for(int i = 0; i < size; i++)  // OPTIMIZED: Cache array size
        {
            if(m_symbolRisks[i].symbol == symbol)
                return i;
        }
        
        // Create new entry
        int index = size;
        ArrayResize(m_symbolRisks, index + 1);
        
        SymbolRisk risk;
        ZeroMemory(risk);
        risk.symbol = symbol;
        risk.maxPositions = 3;
        risk.maxExposure = 10.0; // 10% max exposure per symbol
        risk.inCooldown = false;
        
        m_symbolRisks[index] = risk;
        return index;
    }
    
    double CalculateTradeRisk(string symbol, double lots)
    {
        if(!m_hotData.m_initialized) return 0.0;
        
        // OPTIMIZED: Batch symbol info calls
        static struct SymbolInfo {
            string symbol;
            double bid;
            double point;
            double tickValue;
            datetime lastUpdated;
        } cachedInfo;
        
        if(cachedInfo.symbol != symbol || TimeCurrent() > cachedInfo.lastUpdated + 1)
        {
            cachedInfo.bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            cachedInfo.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            cachedInfo.tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
            cachedInfo.symbol = symbol;
            cachedInfo.lastUpdated = TimeCurrent();
        }
        
        // Use StopLossManager with cached price
        double stopPips = MathAbs(cachedInfo.bid - m_stopManager.Calculate(symbol, true, cachedInfo.bid)) / 
                         (cachedInfo.point * 10.0);
        
        if(stopPips > 0 && cachedInfo.tickValue > 0 && cachedInfo.point > 0)
        {
            double riskAmount = stopPips * cachedInfo.tickValue * cachedInfo.point * 10.0 * lots;
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            
            if(balance > 0)
                return (riskAmount / balance) * 100.0;
        }
        
        return 0.0;
    }
    
    double CalculateSymbolExposure(string symbol)
    {
        if(!m_hotData.m_initialized) return 0.0;
        
        // Use AccountManager's total exposure calculation
        return m_accountManager.GetTotalExposure();
    }
    
    double CalculateLotsExposure(string symbol, double lots)
    {
        // Simplified exposure calculation
        // In real implementation, use margin requirements
        return lots * 1.0; // 1% exposure per lot
    }
    
    double GetMaxExposurePerSymbol(string symbol)
    {
        int index = GetSymbolRiskIndex(symbol);
        if(index >= 0)
            return m_symbolRisks[index].maxExposure;
        
        return 10.0; // Default 10%
    }
    
    bool IsBreakevenSet(ulong ticket)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        // Check if stop loss is at or beyond breakeven
        PositionSelectByTicket(ticket);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
        
        return (isBuy && currentSL >= openPrice) || (!isBuy && currentSL <= openPrice);
    }
    
    bool ShouldLockProfit(ulong ticket, double riskRewardRatio)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        // Calculate profit relative to risk
        double point = GetCachedPoint(symbol);
        double originalRiskPips = MathAbs(openPrice - currentSL) / (point * 10.0);
        
        double pipValue = GetPipValue(symbol);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double profitPips = (pipValue > 0 && volume > 0) ? 
            MathAbs(profit) / (pipValue * volume) : 0.0;
        
        return (profitPips >= originalRiskPips * riskRewardRatio);
    }
    
    double CalculatePipsForPercent(string symbol, double percent)
    {
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        double point = GetCachedPoint(symbol);
        
        if(price > 0 && point > 0)
        {
            double priceMove = price * (percent / 100.0);
            return priceMove / (point * 10.0);
        }
        
        return 50.0; // Default
    }
    
    bool WouldExceedCorrelationLimit(string symbol, double proposedLots)
    {
        if(!m_hotData.m_initialized) return false;
        
        string correlatedPairs[];
        GetCorrelatedPairs(symbol, correlatedPairs);
        
        double totalCorrelatedExposure = 0.0;
        int size = ArraySize(correlatedPairs);
        
        for(int i = 0; i < size; i++)  // OPTIMIZED: Cache array size
        {
            totalCorrelatedExposure += CalculateSymbolExposure(correlatedPairs[i]);
        }
        
        double newExposure = CalculateLotsExposure(symbol, proposedLots);
        double maxCorrelatedExposure = 20.0; // 20% max for correlated pairs
        
        return (totalCorrelatedExposure + newExposure) > maxCorrelatedExposure;
    }
    
    bool WouldExceedDirectionalLimit(string symbol, ENUM_POSITION_TYPE type, double proposedLots)
    {
        if(!m_hotData.m_initialized) return false;
        
        // Calculate net directional exposure
        double netLong = 0.0;
        double netShort = 0.0;
        
        int totalPositions = PositionsTotal();
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                if(posType == POSITION_TYPE_BUY)
                    netLong += CalculateLotsExposure(posSymbol, volume);
                else
                    netShort += CalculateLotsExposure(posSymbol, volume);
            }
        }
        
        // Add proposed position
        if(type == POSITION_TYPE_BUY)
            netLong += CalculateLotsExposure(symbol, proposedLots);
        else
            netShort += CalculateLotsExposure(symbol, proposedLots);
        
        // Max 40% exposure in one direction
        double maxDirectionalExposure = 40.0;
        
        return (netLong > maxDirectionalExposure) || (netShort > maxDirectionalExposure);
    }
    
    int GetMaxBarsInTrade(string symbol)
    {
        // Maximum bars to hold a position
        if(symbol == "XAUUSD" || symbol == "XAGUSD")
            return 48; // 2 days on H1
        else
            return 24; // 1 day on H1
    }
    
    double GetCurrentSpread(string symbol)
    {
        // OPTIMIZED: Group related SymbolInfoDouble calls
        static double cachedBid = 0;
        static double cachedAsk = 0;
        static double cachedPoint = 0;
        static string cachedSymbol = "";
        static datetime lastUpdate = 0;
        
        if(cachedSymbol != symbol || TimeCurrent() > lastUpdate + 1)
        {
            cachedBid = SymbolInfoDouble(symbol, SYMBOL_BID);
            cachedAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
            cachedPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
            cachedSymbol = symbol;
            lastUpdate = TimeCurrent();
        }
        
        return (cachedAsk - cachedBid) / (cachedPoint * 10.0);
    }
    
    double GetAverageSpread(string symbol)
    {
        // Calculate average spread over last 100 bars
        double totalSpread = 0.0;
        int count = 100;  // OPTIMIZED: Use constant
        
        // OPTIMIZED: Batch calculation with cached point
        double point = GetCachedPoint(symbol);
        
        for(int i = 0; i < count; i++)  // OPTIMIZED: Use cached count
        {
            double high = iHigh(symbol, PERIOD_M1, i);
            double low = iLow(symbol, PERIOD_M1, i);
            double spread = (high - low) / (point * 10.0);
            totalSpread += spread;
        }
        
        return count > 0 ? totalSpread / count : GetCurrentSpread(symbol);
    }
    
    double CalculateMarginRequired(string symbol, double lots)
    {
        double marginPerLot = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        return marginPerLot * lots;
    }
    
    double GetCurrentVolatility(string symbol)
    {
        if(!m_hotData.m_initialized) return 0.001;
        
        // OPTIMIZED: Time-based caching (5-second cache)
        static datetime lastCalc = 0;
        static double cachedValue = 0.001;
        static string cachedSymbol = "";
        
        if(cachedSymbol == symbol && TimeCurrent() < lastCalc + 5)
        {
            return cachedValue;
        }
        
        // Calculate current volatility using ATR
        double atr = m_stopManager.Calculate(symbol, true, SymbolInfoDouble(symbol, SYMBOL_BID), STOP_ATR);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        cachedValue = price > 0 ? MathAbs(atr - price) / price : 0.001;
        lastCalc = TimeCurrent();
        cachedSymbol = symbol;
        
        return cachedValue;
    }
    
    double GetAverageVolatility(string symbol)
    {
        // Average volatility over last 20 days
        double totalVolatility = 0.0;
        int count = 0;
        
        for(int i = 1; i <= 20; i++)
        {
            double high = iHigh(symbol, PERIOD_D1, i);
            double low = iLow(symbol, PERIOD_D1, i);
            
            if(high > 0 && low > 0)
            {
                double dailyRange = (high - low) / high;
                totalVolatility += dailyRange;
                count++;
            }
        }
        
        return count > 0 ? totalVolatility / count : 0.001;
    }
    
    double CalculateRecentWinRate(int lookbackTrades)
    {
        // Simplified - in real implementation, track recent trades in array
        if(m_perfData.m_totalTrades < lookbackTrades)
            return m_perfData.m_winRate;
        
        // Assume 50% win rate for recent trades (placeholder)
        return 50.0;
    }
    
    void CheckPerformanceDeterioration()
    {
        if(!m_hotData.m_initialized) return;
        
        // Check recent performance (last 10 trades)
        if(m_perfData.m_totalTrades >= 10)
        {
            double recentWinRate = CalculateRecentWinRate(10);
            
            if(recentWinRate < 30.0) // Less than 30% win rate in recent trades
            {
                // MAJOR STATE CHANGE - Keep logging
                if(m_logger != NULL)
                {
                    m_logger.KeepNotes("SYSTEM", WARN, "RiskManager",
                        StringFormat("Performance deteriorating: Recent win rate %.1f%%",
                        recentWinRate), false, false, 0.0);
                }
                
                // Trigger stricter thresholds
                ApplyStricterThresholds();
            }
        }
    }
    
    void ApplyStricterThresholds()
    {
        if(!m_hotData.m_initialized) return;
        
        // Reduce risk parameters when performance deteriorates
        m_maxPositionRiskPercent *= 0.7; // Reduce by 30%
        m_maxPortfolioExposure *= 0.8;   // Reduce by 20%
        
        // Also update AccountManager
        // m_accountManager.SetMaxPositionRiskPercent(m_maxPositionRiskPercent);
        // m_accountManager.SetMaxPortfolioExposure(m_maxPortfolioExposure);
        
        // MAJOR STATE CHANGE - Keep logging
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", WARN, "RiskManager",
                "Applying stricter risk thresholds due to performance deterioration",
                false, false, 0.0);
        }
    }
    
    double GetPipValue(string symbol)
    {
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
        double point = GetCachedPoint(symbol);
        
        if(tickValue > 0 && point > 0)
            return tickValue * 10.0 * point;
        
        return 0.0;
    }
    
    double GetStopDistance(string symbol, ulong ticket)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return 0.0;
        
        PositionSelectByTicket(ticket);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double point = GetCachedPoint(symbol);
        
        return MathAbs(openPrice - stopLoss) / (point * 10.0);
    }
    
    void GetCorrelatedPairs(string symbol, string &correlated[])
    {
        // OPTIMIZED: Use static arrays for common symbols
        static string eurCorrelated[] = {"GBPUSD", "AUDUSD"};
        static string goldCorrelated[] = {"XAGUSD"};
        
        ArrayResize(correlated, 0);
        
        if(symbol == "EURUSD")
        {
            // OPTIMIZED: Direct assignment instead of ArrayResize/assign
            int size = ArraySize(eurCorrelated);
            ArrayResize(correlated, size);
            for(int i = 0; i < size; i++)
                correlated[i] = eurCorrelated[i];
        }
        else if(symbol == "XAUUSD")
        {
            int size = ArraySize(goldCorrelated);
            ArrayResize(correlated, size);
            for(int i = 0; i < size; i++)
                correlated[i] = goldCorrelated[i];
        }
    }
    
    void ReduceExposure()
    {
        if(!m_hotData.m_initialized) return;
        
        // Reduce position sizes and limit new trades
        m_maxPositionRiskPercent *= 0.7;
        m_maxPortfolioExposure *= 0.8;
        m_hotData.m_canAddToPositions = false;
        
        // Update AccountManager
        // m_accountManager.SetMaxPositionRiskPercent(m_maxPositionRiskPercent);
        // m_accountManager.SetMaxPortfolioExposure(m_maxPortfolioExposure);
        
        // MAJOR STATE CHANGE - Keep logging
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", WARN, "RiskManager",
                "Exposure reduced due to high risk level", false, false, 0.0);
        }
    }
    
    bool IsDrawdownLimitExceeded()
    {
        return m_hotData.m_currentDrawdown >= m_drawdownThresholds[RISK_CRITICAL];
    }
    
    void LogConfigChange(string parameter, string newValue)
    {
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", OBSERVE, "RiskManager",
                StringFormat("Config changed: %s = %s", parameter, newValue),
                false, false, 0.0);
        }
    }
    
    string RiskLevelToString(ENUM_RISK_LEVEL level)
    {
        // OPTIMIZED: Use switch with return instead of variable assignment
        switch(level)
        {
            case RISK_CRITICAL: return "CRITICAL";
            case RISK_HIGH: return "HIGH";
            case RISK_MODERATE: return "MODERATE";
            case RISK_LOW: return "LOW";
            case RISK_OPTIMAL: return "OPTIMAL";
        }
        return "UNKNOWN";
    }
    
    string AccountHealthToString(ENUM_ACCOUNT_HEALTH health)
    {
        switch(health)
        {
            case HEALTH_CRITICAL: return "CRITICAL";
            case HEALTH_WARNING: return "WARNING";
            case HEALTH_GOOD: return "GOOD";
            case HEALTH_EXCELLENT: return "EXCELLENT";
            default: return "UNKNOWN";
        }
    }
    
    double ApplyBrokerLimits(string symbol, double lots)
    {
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        // Apply min/max limits
        lots = MathMax(lots, minLot);
        lots = MathMin(lots, maxLot);
        
        // Round to lot step
        if(lotStep > 0)
        {
            lots = MathRound(lots / lotStep) * lotStep;
        }
        
        // Ensure minimum precision
        lots = NormalizeDouble(lots, 2);
        
        return lots;
    }
    
    double GetBreakevenBuffer(string symbol)
    {
        // Symbol-specific buffer sizes
        if(symbol == "XAUUSD" || symbol == "XAGUSD")
            return 30.0; // Larger buffer for metals
        else if(symbol == "EURUSD" || symbol == "GBPUSD")
            return 15.0;  // Medium buffer for majors
        else
            return 20.0; // Default buffer
    }
    
    double GetDefaultRRRatio()
    {
        switch(m_hotData.m_currentRiskLevel)
        {
            case RISK_CRITICAL: return 1.0;
            case RISK_HIGH: return 1.5;
            case RISK_MODERATE: return 2.0;
            case RISK_LOW: return 2.5;
            case RISK_OPTIMAL: return 3.0;
            default: return 2.0;
        }
    }
    
    double GetATRMultiplier()
    {
        switch(m_hotData.m_currentRiskLevel)
        {
            case RISK_CRITICAL: return 1.0;
            case RISK_HIGH: return 1.2;
            case RISK_MODERATE: return 1.5;
            case RISK_LOW: return 1.8;
            case RISK_OPTIMAL: return 2.0;
            default: return 1.5;
        }
    }
    
    double GetTrailingATRMultiplier()
    {
        switch(m_hotData.m_currentRiskLevel)
        {
            case RISK_CRITICAL: return 1.0;
            case RISK_HIGH: return 1.2;
            case RISK_MODERATE: return 1.5;
            case RISK_LOW: return 1.8;
            case RISK_OPTIMAL: return 2.0;
            default: return 1.5;
        }
    }
    
    double GetTrailingActivationPips()
    {
        switch(m_hotData.m_currentRiskLevel)
        {
            case RISK_CRITICAL: return 15.0;
            case RISK_HIGH: return 12.0;
            case RISK_MODERATE: return 10.0;
            case RISK_LOW: return 8.0;
            case RISK_OPTIMAL: return 5.0;
            default: return 10.0;
        }
    }
    
    // Trade transaction processor
    void ProcessTradeTransaction(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result)
    {
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
            // Handle new deal
            // Get the deal ticket from the transaction
            ulong deal_ticket = trans.deal;  // Use trans.deal to get the deal ticket
            
            if(HistoryDealSelect(deal_ticket))
            {
                // Get deal type
                ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
                
                if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
                {
                    string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
                    double volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
                    double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                    double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                    
                    // TRADE EXECUTION LOG - CRITICAL
                    if(m_logger != NULL)
                    {
                        m_logger.KeepNotes(symbol, OBSERVE, "RiskManager",
                            StringFormat("New deal: %s %.3f lots @ %.5f | Profit: $%.2f", 
                            EnumToString(deal_type), volume, price, profit), false, false, 0.0);
                    }
                    
                    // Update performance metrics
                    if(profit != 0)
                    {
                        bool win = profit > 0;
                        UpdatePerformanceMetrics(win, profit, 0);
                    }
                }
            }
        }
        else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
        {
            // Handle new order - TRADE EXECUTION LOG
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(request.symbol, OBSERVE, "RiskManager",
                    StringFormat("New order: %s %.3f lots", 
                    EnumToString(request.type), request.volume), false, false, 0.0);
            }
        }
    }
    
    // OPTIMIZED: Helper method for cached point values
    double GetCachedPoint(string symbol)
    {
        // Simple cache implementation
        static datetime lastUpdate = 0;
        static string cachedSymbol = "";
        static double cachedPoint = 0;
        
        if(cachedSymbol != symbol || TimeCurrent() > lastUpdate + 60)
        {
            cachedPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
            cachedSymbol = symbol;
            lastUpdate = TimeCurrent();
        }
        
        return cachedPoint;
    }

    // New function: Move to breakeven after specific dollar profit
    bool MoveToBreakevenAtDollarProfit(ulong ticket, double minDollarProfit = 25.0)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        // Check if profit reaches minimum dollar amount
        if(profit >= minDollarProfit)
        {
            // Move to breakeven
            return MoveStopToBreakeven(ticket);
        }
        
        return false;
    }

    // Overload with symbol-specific buffers
    bool MoveToBreakevenAtDollarProfit(ulong ticket, double minDollarProfit, double bufferPips)
    {
        if(!m_hotData.m_initialized || !PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        if(profit >= minDollarProfit)
        {
            // Use custom buffer
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            double point = GetCachedPoint(symbol);
            double buffer = bufferPips * point * 10.0;
            
            double breakevenSL = isBuy ? openPrice - buffer : openPrice + buffer;
            
            return m_trade.PositionModify(ticket, breakevenSL, PositionGetDouble(POSITION_TP));
        }
        
        return false;
    }
};

// Initialize static variables outside the class
datetime RiskManager::s_lastStatusPrint = 0;
datetime RiskManager::s_lastErrorPrint[10];
int RiskManager::s_errorPrintIndex = 0;
double RiskManager::s_cachedPoints[] = {};
datetime RiskManager::s_lastPointUpdate = 0;