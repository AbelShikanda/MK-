//+------------------------------------------------------------------+
//|                      PortfolioManager.mqh                        |
//|               Complete Portfolio Management System               |
//|                Capital Allocation & Distribution                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict
#property version   "2.0"

#include "../config/structures.mqh"
#include "../utils/ResourceManager.mqh"
#include "../risk/RiskManager.mqh"
#include "../risk/AccountManager.mqh"
#include "../symbols/SymbolManager.mqh"

/*
==============================================================
                            USECASE
==============================================================

==============================================================
*/

// ============ ENUMERATIONS ============
enum ENUM_CAPITAL_ALLOCATION_METHOD
{
    ALLOC_EQUAL,            // Equal capital allocation
    ALLOC_VOLATILITY,       // Volatility-adjusted allocation
    ALLOC_SHARPE,           // Sharpe ratio-based allocation
    ALLOC_KELLY,            // Kelly criterion allocation
    ALLOC_CUSTOM            // Custom weight allocation
};

enum ENUM_PORTFOLIO_ACTION
{
    ACTION_ALLOCATE,        // Allocate capital
    ACTION_REBALANCE,       // Rebalance positions
    ACTION_SECURE_PROFIT,   // Secure profits
    ACTION_SHIFT_CAPITAL,   // Shift capital between symbols
    ACTION_ADJUST_RISK,     // Adjust risk parameters
    ACTION_ENABLE_SYMBOL,   // Enable symbol
    ACTION_DISABLE_SYMBOL,  // Disable symbol
    ACTION_EMERGENCY_STOP   // Emergency action
};

// ============ PORTFOLIO MANAGER CLASS ============
class PortfolioManager
{
private:
    // Core Components
    ResourceManager* rm_logger;
    RiskManager* m_riskManager;
    SymbolManager* m_symbolManager;
    AccountManager* m_accountManager;
    CTrade m_trade;
    
    // Portfolio Configuration
    SymbolAllocation m_allocations[];     // Symbol allocations
    PortfolioMetrics m_metrics;           // Portfolio metrics
    double m_maxPortfolioRisk;            // Maximum portfolio risk %
    double m_maxSymbolRisk;               // Maximum risk per symbol %
    double m_correlationLimit;            // Maximum correlation allowed
    ENUM_CAPITAL_ALLOCATION_METHOD m_allocationMethod;
    
    // State Tracking
    double m_totalCapital;                // Total available capital
    double m_initialCapital;              // Initial capital
    datetime m_lastRebalance;             // Last rebalance time
    int m_rebalanceFrequency;             // Rebalance frequency in hours
    bool m_autoRebalance;                 // Auto-rebalance enabled
    
    // Performance Tracking
    double m_dailyReturns[];              // Daily returns for Sharpe calculation
    double m_symbolPerformance[];         // Symbol performance tracking
    int m_totalTrades;                    // Total trades executed
    double m_totalProfit;                 // Total profit
    double m_totalLoss;                   // Total loss
    
    // Risk Controls
    bool m_dynamicRiskAdjustment;         // Dynamic risk adjustment enabled
    double m_drawdownReductionFactor;     // Reduce risk when in drawdown
    double m_profitIncreaseFactor;        // Increase risk when profitable
    int m_maxConcurrentPositions;
    bool m_canOpenNewTrades;
    
public:
    // ============ SECTION 1: INITIALIZATION ============
    
    PortfolioManager()
    {
        rm_logger = NULL;
        m_riskManager = NULL;
        m_symbolManager = NULL;
        m_accountManager = NULL;
        
        // Default configuration
        m_maxPortfolioRisk = 30.0;
        m_maxSymbolRisk = 10.0;
        m_correlationLimit = 0.7;
        m_allocationMethod = ALLOC_VOLATILITY;
        m_totalCapital = 0.0;
        m_initialCapital = 0.0;
        m_lastRebalance = 0;
        m_rebalanceFrequency = 24; // Daily rebalance
        m_autoRebalance = true;
        m_dynamicRiskAdjustment = true;
        m_drawdownReductionFactor = 0.7;
        m_profitIncreaseFactor = 1.2;
        
        m_totalTrades = 0;
        m_totalProfit = 0.0;
        m_totalLoss = 0.0;
        m_canOpenNewTrades = true;
    }
    
    ~PortfolioManager()
    {
        ArrayFree(m_allocations);
        ArrayFree(m_dailyReturns);
        ArrayFree(m_symbolPerformance);
    }
    
    void Init(string &symbols[], int &priorities[], ResourceManager* logger = NULL,
              RiskManager* riskMgr = NULL, SymbolManager* symbolMgr = NULL,
              AccountManager* accountMgr = NULL)
    {
        rm_logger = logger;
        m_riskManager = riskMgr;
        m_symbolManager = symbolMgr;
        m_accountManager = accountMgr;
        m_maxConcurrentPositions = 5;
        
        // Initialize with symbols and priorities
        int count = MathMin(ArraySize(symbols), ArraySize(priorities));
        ArrayResize(m_allocations, count);
        
        m_totalCapital = AccountInfoDouble(ACCOUNT_BALANCE);
        m_initialCapital = m_totalCapital;
        
        for(int i = 0; i < count; i++)
        {
            m_allocations[i].symbol = symbols[i];
            m_allocations[i].priority = priorities[i];
            m_allocations[i].enabled = true;
            m_allocations[i].riskBudget = m_maxSymbolRisk;
            m_allocations[i].assetClass = DetermineAssetClass(symbols[i]);
            
            // Initialize with equal weights (will be adjusted)
            m_allocations[i].targetWeight = 100.0 / count;
            m_allocations[i].currentWeight = 0.0;
            m_allocations[i].capital = 0.0;
            m_allocations[i].performance = 0.0;
            m_allocations[i].volatility = CalculateVolatility(symbols[i], 30);
            m_allocations[i].sharpeRatio = 0.0;
            m_allocations[i].lastTradeTime = 0;
            m_allocations[i].totalProfit = 0.0;
            m_allocations[i].winRate = 0.0;
        }
        
        // Initialize portfolio metrics
        InitializeMetrics();
        
        // Calculate initial allocation
        CalculateCapitalAllocation();
        
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("Portfolio initialized with %d symbols | Capital: $%.2f",
                count, m_totalCapital));
        }
    }
    
    // ============ SECTION 2: CAPITAL ALLOCATION DECISIONS ============
    
    // Function 1: Decide where capital is allocated
    void CalculateCapitalAllocation()
    {
        rm_logger.StartContextWith("SYSTEM", "CAPITAL_ALLOCATION");
        
        double totalWeight = 0.0;
        int enabledCount = 0;
        
        // Count enabled symbols
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                enabledCount++;
                totalWeight += m_allocations[i].priority;
            }
        }
        
        if(enabledCount == 0 || totalWeight == 0)
        {
            rm_logger.FlushContext("SYSTEM", WARN, "PortfolioManager",
                "No enabled symbols for capital allocation", false);
            return;
        }
        
        // Allocate capital based on selected method
        switch(m_allocationMethod)
        {
            case ALLOC_EQUAL:
                AllocateEqualCapital(enabledCount);
                break;
                
            case ALLOC_VOLATILITY:
                AllocateVolatilityAdjusted();
                break;
                
            case ALLOC_SHARPE:
                AllocateSharpeBased();
                break;
                
            case ALLOC_KELLY:
                AllocateKellyCriterion();
                break;
                
            case ALLOC_CUSTOM:
                // Use custom weights already set
                break;
        }
        
        // Apply risk budgets
        ApplyRiskBudgets();
        
        // Log allocation
        string allocationLog = "Capital Allocation:\n";
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                allocationLog += StringFormat("  %s: $%.2f (%.1f%%) | Risk: %.1f%%\n",
                    m_allocations[i].symbol, m_allocations[i].capital,
                    m_allocations[i].targetWeight, m_allocations[i].riskBudget);
                
                rm_logger.AddDoubleContext("SYSTEM", 
                    StringFormat("%s_Capital", m_allocations[i].symbol),
                    m_allocations[i].capital, 2);
                rm_logger.AddDoubleContext("SYSTEM",
                    StringFormat("%s_Weight", m_allocations[i].symbol),
                    m_allocations[i].targetWeight, 1);
            }
        }
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            allocationLog, false);
    }
    
    // Function 2: Decide how capital is distributed across opportunities
    TradeDecision GetTradingDecision(string symbol)
    {
        rm_logger.StartContextWith(symbol, "TRADING_DECISION");
        TradeDecision decision;
        ZeroMemory(decision);
        decision.symbol = symbol;
        
        // 1. Check if symbol is enabled
        int index = GetSymbolIndex(symbol);
        if(index < 0 || !m_allocations[index].enabled)
        {
            decision.approved = false;
            decision.reason = "Symbol not enabled";
            rm_logger.FlushContext(symbol, OBSERVE, "PortfolioManager",
                "Trade not approved: Symbol not enabled", false);
            return decision;
        }
        
        // 2. Use RiskManager to check ALL risk limits
        if(m_riskManager != NULL)
        {
            // First check if RiskManager allows the trade at all
            if(!m_riskManager.AllowNewTrade(symbol, 0.01, "Portfolio allocation check"))
            {
                decision.approved = false;
                decision.reason = m_riskManager.GetRiskLevel() == RISK_CRITICAL ? 
                                "Emergency stop active" : "Risk limits exceeded";
                rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                    StringFormat("Trade not approved: %s", decision.reason), false);
                return decision;
            }
            
            // Check volatility and spread
            if(!m_riskManager.IsVolatilityAcceptable(symbol) || 
               !m_riskManager.IsSpreadAcceptable(symbol))
            {
                decision.approved = false;
                decision.reason = "Market conditions not favorable";
                rm_logger.FlushContext(symbol, OBSERVE, "PortfolioManager",
                    "Trade not approved: Market conditions", false);
                return decision;
            }
        }
        
        // 3. Check if we have capital allocated
        if(m_allocations[index].capital <= 0)
        {
            decision.approved = false;
            decision.reason = "No capital allocated";
            rm_logger.FlushContext(symbol, OBSERVE, "PortfolioManager",
                "Trade not approved: No capital allocated", false);
            return decision;
        }
        
        // 4. Calculate position details using RiskManager
        double riskPercent = m_allocations[index].riskBudget;
        double capital = m_allocations[index].capital;
        
        // Use RiskManager for stop loss calculation
        double stopLossPips = 0;
        if(m_riskManager != NULL)
        {
            // Get optimal stop loss using RiskManager's StopLossManager
            double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            stopLossPips = MathAbs(currentPrice - 
                m_riskManager.GetOptimalStopLoss(symbol, currentPrice, true)) / 
                (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0);
        }
        else
        {
            stopLossPips = CalculateOptimalStopLoss(symbol);
        }
        
        // Calculate position size using RiskManager
        double lotSize = 0;
        if(m_riskManager != NULL && stopLossPips > 0)
        {
            lotSize = m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                symbol, capital, stopLossPips);
        }
        else
        {
            lotSize = CalculatePositionSizeFromCapital(symbol, capital);
        }
        
        decision.capital = capital;
        decision.lotSize = lotSize;
        decision.riskPercent = riskPercent;
        decision.direction = DetermineTradeDirection(symbol);
        decision.reason = GenerateTradeReason(symbol);
        
        // 5. Final check with specific position size using RiskManager
        if(m_riskManager != NULL && !m_riskManager.CheckExposureLimits(symbol, lotSize))
        {
            decision.approved = false;
            decision.reason = "Exposure limits exceeded";
            rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                "Trade not approved: Exposure limits exceeded", false);
            return decision;
        }
        
        // Check margin requirements
        if(m_riskManager != NULL && !m_riskManager.IsMarginSufficient(symbol, lotSize))
        {
            decision.approved = false;
            decision.reason = "Insufficient margin";
            rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                "Trade not approved: Insufficient margin", false);
            return decision;
        }
        
        decision.approved = true;
        
        rm_logger.AddDoubleContext(symbol, "AllocatedCapital", capital, 2);
        rm_logger.AddDoubleContext(symbol, "LotSize", lotSize, 3);
        rm_logger.AddDoubleContext(symbol, "RiskPercent", riskPercent, 1);
        rm_logger.AddDoubleContext(symbol, "StopLossPips", stopLossPips, 1);
        rm_logger.AddToContext(symbol, "Direction", EnumToString(decision.direction));
        rm_logger.AddToContext(symbol, "Reason", decision.reason);
        
        // Add RiskManager context
        if(m_riskManager != NULL)
        {
            rm_logger.AddToContext(symbol, "RiskLevel", 
                RiskLevelToString(m_riskManager.GetRiskLevel()));
            rm_logger.AddDoubleContext(symbol, "DailyPnL", 
                m_riskManager.GetDailyPnL(), 2);
        }
        
        rm_logger.FlushContext(symbol, AUTHORIZE, "PortfolioManager",
            StringFormat("Trade approved: %s lots | Risk: %.1f%% | Capital: $%.2f",
            DoubleToString(lotSize, 3), riskPercent, capital), false);
        
        return decision;
    }
    
     void HandleTradeTransaction(const MqlTradeTransaction &trans)
    {
        // Log transaction type
        Print("Transaction type: ", trans.type);
        
        switch(trans.type)
        {
            case TRADE_TRANSACTION_DEAL_ADD:
                ProcessNewDeal(trans);
                break;
                
            case TRADE_TRANSACTION_HISTORY_ADD:
                ProcessHistoryUpdate(trans);
                break;
                
            case TRADE_TRANSACTION_POSITION:
                ProcessPositionUpdate(trans);
                break;
                
            default:
                // Handle other transaction types if needed
                Print("Unhandled transaction type: ", trans.type);
                break;
        }
    }
    
    // ============ SECTION 3: PROFITABILITY ASSESSMENT ============
    
    // Function 3: What looks profitable?
    TradingOpportunity GetNextTradingOpportunity()
    {
        rm_logger.StartContextWith("SYSTEM", "PROFITABILITY_ASSESSMENT");
        
        TradingOpportunity bestOpportunity;
        ZeroMemory(bestOpportunity);
        double bestScore = -9999.0;
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(!m_allocations[i].enabled) continue;
            
            double score = CalculateProfitabilityScore(m_allocations[i].symbol);
            
            rm_logger.AddDoubleContext("SYSTEM",
                StringFormat("%s_Score", m_allocations[i].symbol),
                score, 2);
            
            if(score > bestScore)
            {
                bestScore = score;
                bestOpportunity.symbol = m_allocations[i].symbol;
                
                // Use RiskManager for trade parameters if available
                if(m_riskManager != NULL)
                {
                    double currentPrice = SymbolInfoDouble(m_allocations[i].symbol, SYMBOL_BID);
                    bool isBuy = CalculateDirection(m_allocations[i].symbol) == POSITION_TYPE_BUY;
                    
                    // Get optimal stop loss from RiskManager
                    double stopLoss = m_riskManager.GetOptimalStopLoss(
                        m_allocations[i].symbol, currentPrice, isBuy);
                    
                    // Get optimal take profit from RiskManager
                    double takeProfit = m_riskManager.GetOptimalTakeProfit(
                        m_allocations[i].symbol, PERIOD_H1, currentPrice, stopLoss, isBuy);
                    
                    bestOpportunity.direction = CalculateDirection(m_allocations[i].symbol);
                    bestOpportunity.lotSize = CalculateOptimalLotSize(m_allocations[i].symbol);
                    bestOpportunity.stopLoss = stopLoss;
                    bestOpportunity.takeProfit = takeProfit;
                }
                else
                {
                    // Fallback to basic calculations
                    bestOpportunity.direction = CalculateDirection(m_allocations[i].symbol);
                    bestOpportunity.lotSize = CalculateOptimalLotSize(m_allocations[i].symbol);
                    bestOpportunity.stopLoss = CalculateStopLoss(m_allocations[i].symbol, bestOpportunity.direction);
                    bestOpportunity.takeProfit = CalculateTakeProfit(m_allocations[i].symbol, bestOpportunity.direction);
                }
                
                bestOpportunity.reason = StringFormat("High profitability score: %.2f", score);
                bestOpportunity.approved = true;
                bestOpportunity.confidence = MathMin(score / 100.0, 1.0);
            }
        }
        
        if(bestOpportunity.symbol != "")
        {
            rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("Best opportunity: %s (Score: %.2f)", bestOpportunity.symbol, bestScore), false);
        }
        else
        {
            rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
                "No profitable opportunities found", false);
        }
        
        return bestOpportunity;
    }
    
    // Function 4: How to place the trade?
    bool ExecuteTradeWithAllocation(string symbol, ENUM_POSITION_TYPE direction,
                                double stopLoss, double takeProfit)
    {
        rm_logger.StartContextWith(symbol, "TRADE_EXECUTION");
        
        // Get trading decision
        TradeDecision decision = GetTradingDecision(symbol);
        if(!decision.approved)
        {
            rm_logger.FlushContext(symbol, OBSERVE, "PortfolioManager",
                "Trade execution cancelled: Not approved", false);
            return false;
        }
        
        // Use RiskManager for stop loss validation
        if(m_riskManager != NULL)
        {
            double currentPrice = (direction == POSITION_TYPE_BUY) ? 
                SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                SymbolInfoDouble(symbol, SYMBOL_BID);
            
            m_riskManager.ValidateStopLossPlacement(symbol, stopLoss, currentPrice, 
                direction == POSITION_TYPE_BUY);
            
            // Get optimal take profit from RiskManager if not provided
            if(takeProfit == 0)
            {
                takeProfit = m_riskManager.GetOptimalTakeProfit(symbol, PERIOD_H1,
                    currentPrice, stopLoss, direction == POSITION_TYPE_BUY);
            }
        }
        
        // Calculate precise position size using RiskManager
        double riskAdjustedSize = decision.lotSize;
        if(m_riskManager != NULL && stopLoss > 0)
        {
            riskAdjustedSize = m_riskManager.CalculateRiskAdjustedSize(
                symbol, decision.lotSize, stopLoss, direction);
        }
        
        // Calculate entry price and order type
        double price = (direction == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : 
            SymbolInfoDouble(symbol, SYMBOL_BID);
        
        ENUM_ORDER_TYPE orderType = (direction == POSITION_TYPE_BUY) ? 
                                ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        
        string tradeComment = StringFormat("PM:%s|Lots:%.3f|Risk:%.1f%%", 
                                        EnumToString(direction), riskAdjustedSize,
                                        decision.riskPercent);
        
        // Execute the trade
        if(m_trade.PositionOpen(symbol, 
                            orderType,          // ORDER_TYPE_BUY or ORDER_TYPE_SELL
                            riskAdjustedSize,   // Volume
                            price,              // Entry price
                            stopLoss,           // Stop loss price
                            takeProfit,         // Take profit price
                            tradeComment))      // Comment
        {
            // Update allocation tracking
            UpdateAllocationAfterTrade(symbol, riskAdjustedSize);
            
            // Update performance tracking
            m_totalTrades++;
            
            // Update RiskManager metrics
            if(m_riskManager != NULL)
            {
                double profit = 0; // Will be updated when position closes
                double riskAmount = MathAbs(price - stopLoss) * riskAdjustedSize * 
                    SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
                m_riskManager.UpdatePerformanceMetrics(true, profit, riskAmount);
            }
            
            rm_logger.AddDoubleContext(symbol, "ExecutedLotSize", riskAdjustedSize, 3);
            rm_logger.AddDoubleContext(symbol, "Price", price, 5);
            rm_logger.AddDoubleContext(symbol, "StopLoss", stopLoss, 5);
            rm_logger.AddDoubleContext(symbol, "TakeProfit", takeProfit, 5);
            
            rm_logger.FlushContext(symbol, AUTHORIZE, "PortfolioManager",
                StringFormat("Trade executed: %s %.3f lots at %.5f",
                EnumToString(direction), riskAdjustedSize, price), true);
            
            return true;
        }
        else
        {
            rm_logger.FlushContext(symbol, WARN, "PortfolioManager",
                StringFormat("Trade execution failed: %s",
                m_trade.ResultRetcodeDescription()), false);
            return false;
        }
    }
    
    // ============ SECTION 4: CAPITAL DISTRIBUTION ============
    
    // Function 5: Where should capital be allocated?
    void DistributeCapital()
    {
        rm_logger.StartContextWith("SYSTEM", "CAPITAL_DISTRIBUTION");
        
        // Update total capital
        m_totalCapital = AccountInfoDouble(ACCOUNT_EQUITY);
        m_metrics.totalCapital = m_totalCapital;
        
        // Calculate available capital (not in use)
        m_metrics.allocatedCapital = CalculateAllocatedCapital();
        m_metrics.availableCapital = m_totalCapital - m_metrics.allocatedCapital;
        
        // Update symbol weights based on performance
        UpdateWeightsBasedOnPerformance();
        
        // Recalculate allocations
        CalculateCapitalAllocation();
        
        // Check for rebalancing needs
        if(ShouldRebalance())
        {
            RebalancePortfolio();
        }
        
        rm_logger.AddDoubleContext("SYSTEM", "TotalCapital", m_totalCapital, 2);
        rm_logger.AddDoubleContext("SYSTEM", "AllocatedCapital", m_metrics.allocatedCapital, 2);
        rm_logger.AddDoubleContext("SYSTEM", "AvailableCapital", m_metrics.availableCapital, 2);
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            StringFormat("Capital distributed | Total: $%.2f | Allocated: $%.2f | Available: $%.2f",
            m_totalCapital, m_metrics.allocatedCapital, m_metrics.availableCapital), false);
    }
    
    // Function 6: Allocate capital across symbols
    double GetCapitalAllocation(string symbol)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0 && m_allocations[index].enabled)
        {
            // Use RiskManager to calculate risk-adjusted capital
            if(m_riskManager != NULL)
            {
                double baseCapital = m_allocations[index].capital;
                double riskPercent = m_allocations[index].riskBudget;
                
                // Get risk-adjusted capital allocation
                return m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                    symbol, baseCapital, 0) * SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            }
            return m_allocations[index].capital;
        }
        return 0.0;
    }
    
    void SetSymbolCapital(string symbol, double capital)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].capital = capital;
            m_allocations[index].targetWeight = (capital / m_totalCapital) * 100.0;
            
            if(rm_logger != NULL)
            {
                rm_logger.KeepNotes(symbol, OBSERVE, "PortfolioManager",
                    StringFormat("Capital set to $%.2f (%.1f%%)",
                    capital, m_allocations[index].targetWeight));
            }
        }
    }

    void RecordTradeExecution(string symbol, double lotSize, ENUM_POSITION_TYPE direction,
                              double entryPrice = 0.0, double stopLoss = 0.0, 
                              double takeProfit = 0.0)
    {
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes(symbol, AUTHORIZE, "PortfolioManager",
                StringFormat("Trade executed: %s %s %.3f lots @ %.5f",
                symbol, EnumToString(direction), lotSize, entryPrice));
        }
        
        // Update symbol tracking
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].lastTradeTime = TimeCurrent();
            
            // Calculate position value
            double positionValue = CalculatePositionValue(symbol, lotSize, entryPrice);
            m_allocations[index].currentWeight = (positionValue / m_totalCapital) * 100.0;
            
            // Update trade count
            m_totalTrades++;
        }
        
        // Update portfolio metrics
        UpdatePortfolioMetrics();
        
        Print("PortfolioManager: Trade recorded for ", symbol);
    }
    
    // Helper method to calculate position value
    double CalculatePositionValue(string symbol, double lotSize, double price)
    {
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        double positionValue = lotSize * contractSize * price;
        
        // Adjust for Forex (1 standard lot = 100,000 units)
        if(SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE) == SYMBOL_CALC_MODE_FOREX)
        {
            positionValue = lotSize * 100000;
        }
        
        return positionValue;
    }
    
    // Calculate allocated capital
    double CalculateAllocatedCapital()
    {
        double totalAllocated = 0.0;
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].positionSize > 0)
            {
                double positionValue = CalculatePositionValue(
                    m_allocations[i].symbol,
                    m_allocations[i].positionSize,
                    SymbolInfoDouble(m_allocations[i].symbol, SYMBOL_BID)
                );
                totalAllocated += positionValue;
            }
        }
        return totalAllocated;
    }
    
    // Other calculation methods (simplified examples)
    double CalculateDailyPnL()
    {
        // Use RiskManager if available
        if(m_riskManager != NULL)
        {
            return m_riskManager.GetDailyPnL();
        }
        
        // Implement daily PnL calculation
        return 0.0;
    }
    
    double CalculateMaxDrawdown()
    {
        // Use RiskManager if available
        if(m_riskManager != NULL)
        {
            return m_riskManager.GetCurrentDrawdown();
        }
        
        // Implement max drawdown calculation
        return 0.0;
    }
    
    // Setter for logger
    void SetLogger(ResourceManager* logger)
    {
        rm_logger = logger;
    }
    
    // ============ SECTION 5: RISK MANAGEMENT ============
    
    // Function 7: Balance exposure between asset classes
    void BalanceAssetClasses()
    {
        rm_logger.StartContextWith("SYSTEM", "ASSET_CLASS_BALANCING");
        
        // Calculate current exposure per asset class
        double classExposure[7] = {0, 0, 0, 0, 0, 0, 0};
        int classCount[7] = {0, 0, 0, 0, 0, 0, 0};
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].currentWeight > 0)
            {
                int classIndex = (int)m_allocations[i].assetClass;
                classExposure[classIndex] += m_allocations[i].currentWeight;
                classCount[classIndex]++;
            }
        }
        
        // Calculate target exposure (equal weighting for now)
        double targetPerClass = 100.0 / 7; // ~14.3% per class
        
        // Adjust allocations to balance classes
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                int classIndex = (int)m_allocations[i].assetClass;
                double currentClassWeight = classExposure[classIndex];
                
                if(currentClassWeight > targetPerClass * 1.5) // 50% over target
                {
                    // Reduce weight for this symbol
                    double reduction = m_allocations[i].targetWeight * 0.8;
                    m_allocations[i].targetWeight = reduction;
                    
                    rm_logger.AddDoubleContext("SYSTEM",
                        StringFormat("%s_AdjWeight", m_allocations[i].symbol),
                        reduction, 1);
                    rm_logger.AddToContext("SYSTEM",
                        StringFormat("%s_AdjReason", m_allocations[i].symbol),
                        "Asset class overexposure");
                }
            }
        }
        
        // Store metrics
        for(int i = 0; i < 7; i++)
        {
            m_metrics.assetClassExposure[i] = classExposure[i];
        }
        
        string balanceLog = "Asset Class Exposure:\n";
        for(int i = 0; i < 7; i++)
        {
            balanceLog += StringFormat("  %s: %.1f%%\n",
                AssetClassToString((ENUM_ASSET_CLASS)i), classExposure[i]);
        }
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager", balanceLog, false);
    }
    
    // Function 8: Control correlation risk
    void ControlCorrelationRisk()
    {
        rm_logger.StartContextWith("SYSTEM", "CORRELATION_CONTROL");
        
        if(m_symbolManager != NULL)
        {
            // Update correlation matrix
            m_symbolManager.CalculateCorrelationMatrix(PERIOD_H1, 100);
            
            // Find highly correlated pairs
            string correlatedPairs[][2];
            double correlationValues[];
            
            int pairCount = m_symbolManager.FindHighlyCorrelatedPairs(
                correlatedPairs, correlationValues, m_correlationLimit);
            
            if(pairCount > 0)
            {
                // Reduce exposure to correlated pairs
                for(int i = 0; i < pairCount; i++)
                {
                    string symbol1 = correlatedPairs[i][0];
                    string symbol2 = correlatedPairs[i][1];
                    double correlation = correlationValues[i];
                    
                    if(correlation > m_correlationLimit)
                    {
                        ReduceCorrelatedExposure(symbol1, symbol2, correlation);
                    }
                }
                
                rm_logger.FlushContext("SYSTEM", WARN, "PortfolioManager",
                    StringFormat("Correlation risk controlled: %d pairs adjusted", pairCount), false);
            }
            else
            {
                rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
                    "No excessive correlation found", false);
            }
            
            // Store average correlation in metrics
            m_metrics.correlationMatrixAverage = m_symbolManager.GetPortfolioAverageCorrelation();
        }
        else
        {
            rm_logger.FlushContext("SYSTEM", WARN, "PortfolioManager",
                "SymbolManager not available for correlation analysis", false);
        }
    }

    // Enhanced version with position size consideration
    bool CheckRiskLimitsWithSize(string symbol, double lotSize)
    {
        rm_logger.StartContextWith(symbol, "PORTFOLIO_RISK_LIMITS_WITH_SIZE");
        
        // First, check basic limits
        if(!CheckRiskLimits(symbol))
        {
            rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                "Basic risk limits failed", false);
            return false;
        }
        
        // Check RiskManager for position-specific risk
        if(m_riskManager != NULL)
        {
            if(!m_riskManager.AllowNewTrade(symbol, lotSize, "Portfolio allocation"))
            {
                rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                    "RiskManager blocked the trade", false);
                return false;
            }
            
            // Check exposure limits with specific lot size
            if(!m_riskManager.CheckExposureLimits(symbol, lotSize))
            {
                rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                    "Exposure limits exceeded with proposed lot size", false);
                return false;
            }
        }
        
        // Calculate proposed exposure increase
        double proposedExposure = CalculateProposedExposure(symbol, lotSize);
        double currentExposure = m_metrics.allocatedCapital;
        double totalAfter = currentExposure + proposedExposure;
        
        // Check if total would exceed portfolio limits
        if(totalAfter > m_totalCapital * (m_maxPortfolioRisk / 100.0))
        {
            rm_logger.AddDoubleContext(symbol, "CurrentExposure", currentExposure, 2);
            rm_logger.AddDoubleContext(symbol, "ProposedExposure", proposedExposure, 2);
            rm_logger.AddDoubleContext(symbol, "TotalAfter", totalAfter, 2);
            rm_logger.AddDoubleContext(symbol, "MaxAllowed", 
                m_totalCapital * (m_maxPortfolioRisk / 100.0), 2);
            
            rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                StringFormat("Portfolio exposure limit would be exceeded: $%.2f > $%.2f",
                totalAfter, m_totalCapital * (m_maxPortfolioRisk / 100.0)), false);
            
            return false;
        }
        
        rm_logger.AddDoubleContext(symbol, "LotSize", lotSize, 3);
        rm_logger.AddDoubleContext(symbol, "ProposedExposure", proposedExposure, 2);
        rm_logger.FlushContext(symbol, AUTHORIZE, "PortfolioManager",
            "All risk limits passed with position size", false);
        
        return true;
    }
    
    // Helper function that uses SymbolManager
    double GetSymbolCorrelation(string symbol)
    {
        if(m_symbolManager != NULL)
        {
            return m_symbolManager.GetAverageCorrelation(symbol);
        }
        return true;
    }
    
    // Check correlation before opening a position
    bool CheckCorrelationBeforeTrade(string symbol, double lots)
    {
        if(m_symbolManager != NULL)
        {
            return m_symbolManager.CheckCorrelationLimit(symbol, m_correlationLimit);
        }
        return true;
    }
    
    // Reduce exposure for correlated symbols
    void ReduceCorrelatedExposure(string symbol1, string symbol2, double correlation)
    {
        rm_logger.StartContextWith("SYSTEM", "REDUCE_CORRELATED_EXPOSURE");
        
        // Determine which symbol to reduce (lower performing or higher correlation)
        double perf1 = GetSymbolPerformance(symbol1);
        double perf2 = GetSymbolPerformance(symbol2);
        
        string reduceSymbol = (perf1 < perf2) ? symbol1 : symbol2;
        double reductionPercent = 30.0; // Reduce by 30%
        
        // Reduce exposure
        ReduceSymbolExposure(reduceSymbol, reductionPercent);
        
        rm_logger.AddToContext("SYSTEM", "Symbol1", symbol1);
        rm_logger.AddToContext("SYSTEM", "Symbol2", symbol2);
        rm_logger.AddDoubleContext("SYSTEM", "Correlation", correlation, 2);
        rm_logger.AddToContext("SYSTEM", "ReduceSymbol", reduceSymbol);
        rm_logger.AddDoubleContext("SYSTEM", "ReductionPercent", reductionPercent, 1);
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            StringFormat("Reduced %s exposure by %.1f%% due to correlation (%.2f) with %s",
            reduceSymbol, reductionPercent, correlation, 
            (reduceSymbol == symbol1) ? symbol2 : symbol1), false);
    }
    
    // ============ SECTION 6: PERFORMANCE ADJUSTMENT ============
    
    // Function 9: Shift capital away from underperforming symbols
    void ShiftCapitalFromUnderperformers(int lookbackDays = 7)
    {
        rm_logger.StartContextWith("SYSTEM", "CAPITAL_SHIFT_FROM_LOSERS");
        
        string underperformers[];
        GetUnderperformingSymbols(underperformers, lookbackDays);
        
        for(int i = 0; i < ArraySize(underperformers); i++)
        {
            string symbol = underperformers[i];
            int index = GetSymbolIndex(symbol);
            
            if(index >= 0 && m_allocations[index].enabled)
            {
                // Reduce capital allocation
                double currentCapital = m_allocations[index].capital;
                double newCapital = currentCapital * 0.7; // Reduce by 30%
                
                m_allocations[index].capital = newCapital;
                m_allocations[index].targetWeight = (newCapital / m_totalCapital) * 100.0;
                
                rm_logger.AddDoubleContext("SYSTEM",
                    StringFormat("%s_NewCapital", symbol),
                    newCapital, 2);
                rm_logger.AddToContext("SYSTEM",
                    StringFormat("%s_ShiftReason", symbol),
                    "Underperforming");
                
                if(rm_logger != NULL)
                {
                    rm_logger.KeepNotes(symbol, OBSERVE, "PortfolioManager",
                        StringFormat("Capital reduced by 30%%: $%.2f -> $%.2f",
                        currentCapital, newCapital));
                }
            }
        }
        
        // Reallocate freed capital
        CalculateCapitalAllocation();
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            StringFormat("Shifted capital from %d underperformers",
            ArraySize(underperformers)), false);
    }
    
    // Function 10: Scale capital toward outperforming strategies
    void ScaleCapitalToOutperformers(int lookbackDays = 7)
    {
        rm_logger.StartContextWith("SYSTEM", "CAPITAL_SCALE_TO_WINNERS");
        
        string outperformers[];
        GetOutperformingSymbols(outperformers, lookbackDays);
        
        double totalReduced = 0.0;
        
        // First, calculate total capital from underperformers
        string underperformers[];
        GetUnderperformingSymbols(underperformers, lookbackDays);
        
        for(int i = 0; i < ArraySize(underperformers); i++)
        {
            int index = GetSymbolIndex(underperformers[i]);
            if(index >= 0)
            {
                double reduction = m_allocations[index].capital * 0.3; // 30% reduction
                totalReduced += reduction;
            }
        }
        
        // Distribute to outperformers
        double capitalPerOutperformer = totalReduced / ArraySize(outperformers);
        
        for(int i = 0; i < ArraySize(outperformers); i++)
        {
            string symbol = outperformers[i];
            int index = GetSymbolIndex(symbol);
            
            if(index >= 0 && m_allocations[index].enabled)
            {
                // Increase capital allocation
                double currentCapital = m_allocations[index].capital;
                double newCapital = currentCapital + capitalPerOutperformer;
                
                m_allocations[index].capital = newCapital;
                m_allocations[index].targetWeight = (newCapital / m_totalCapital) * 100.0;
                
                rm_logger.AddDoubleContext("SYSTEM",
                    StringFormat("%s_NewCapital", symbol),
                    newCapital, 2);
                rm_logger.AddToContext("SYSTEM",
                    StringFormat("%s_ScaleReason", symbol),
                    "Outperforming");
                
                if(rm_logger != NULL)
                {
                    rm_logger.KeepNotes(symbol, AUTHORIZE, "PortfolioManager",
                        StringFormat("Capital increased: $%.2f -> $%.2f (+$%.2f)",
                        currentCapital, newCapital, capitalPerOutperformer));
                }
            }
        }
        
        rm_logger.FlushContext("SYSTEM", AUTHORIZE, "PortfolioManager",
            StringFormat("Scaled capital to %d outperformers (+$%.2f each)",
            ArraySize(outperformers), capitalPerOutperformer), false);
    }
    
    // ============ SECTION 7: DYNAMIC SYMBOL MANAGEMENT ============
    
    // Function 11: Enable / disable symbols dynamically
    void EnableSymbol(string symbol, string reason = "")
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].enabled = true;
            
            if(rm_logger != NULL)
            {
                rm_logger.KeepNotes(symbol, AUTHORIZE, "PortfolioManager",
                    StringFormat("Symbol enabled: %s", reason));
            }
            
            // Recalculate allocations
            CalculateCapitalAllocation();
        }
    }
    
    void DisableSymbol(string symbol, string reason = "")
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].enabled = false;
            m_allocations[index].capital = 0.0;
            m_allocations[index].currentWeight = 0.0;
            
            if(rm_logger != NULL)
            {
                rm_logger.KeepNotes(symbol, WARN, "PortfolioManager",
                    StringFormat("Symbol disabled: %s", reason));
            }
            
            // Close any open positions for this symbol
            CloseSymbolPositions(symbol, reason);
            
            // Recalculate allocations
            CalculateCapitalAllocation();
        }
    }
    
    // Function 12: Set per-symbol risk budgets
    void SetSymbolRiskBudget(string symbol, double riskPercent)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].riskBudget = MathMin(riskPercent, m_maxSymbolRisk);
            
            if(rm_logger != NULL)
            {
                rm_logger.KeepNotes(symbol, OBSERVE, "PortfolioManager",
                    StringFormat("Risk budget set to %.1f%%", riskPercent));
            }
        }
    }
    
    double GetSymbolRiskBudget(string symbol)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_allocations[index].riskBudget;
        }
        return 0.0;
    }
    
    // ============ SECTION 8: PORTFOLIO REBALANCING ============
    
    bool ShouldRebalance()
    {
        if(!m_autoRebalance) return false;
        
        // Check time-based rebalancing
        datetime now = TimeCurrent();
        int hoursSinceRebalance = (int)((now - m_lastRebalance) / 3600);
        
        if(hoursSinceRebalance >= m_rebalanceFrequency)
        {
            return true;
        }
        
        // Check weight drift rebalancing
        double maxDrift = 0.0;
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                double drift = MathAbs(m_allocations[i].currentWeight - m_allocations[i].targetWeight);
                if(drift > maxDrift)
                {
                    maxDrift = drift;
                }
            }
        }
        
        // Rebalance if drift exceeds 5%
        if(maxDrift > 5.0)
        {
            return true;
        }
        
        return false;
    }
    
    void RebalancePortfolio()
    {
        rm_logger.StartContextWith("SYSTEM", "PORTFOLIO_REBALANCING");
        
        // Close positions that are over-allocated
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].currentWeight > 0)
            {
                double targetWeight = m_allocations[i].targetWeight;
                double currentWeight = m_allocations[i].currentWeight;
                
                if(currentWeight > targetWeight * 1.1) // 10% over target
                {
                    // Calculate how much to reduce
                    double reductionPercent = ((currentWeight - targetWeight) / currentWeight) * 100.0;
                    ReduceSymbolExposure(m_allocations[i].symbol, reductionPercent);
                }
            }
        }
        
        // Update last rebalance time
        m_lastRebalance = TimeCurrent();
        
        // Recalculate allocations
        CalculateCapitalAllocation();
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            "Portfolio rebalanced", false);
    }
    
    // Add method to integrate with RiskManager's profit protection
    void ApplyRiskBasedStopManagement()
    {
        if(m_riskManager != NULL)
        {
            // Update trailing stops using RiskManager
            m_riskManager.UpdateTrailingStops();
            
            // Check for profit securing
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(PositionSelectByTicket(ticket))
                {
                    string symbol = PositionGetString(POSITION_SYMBOL);
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    
                    // Use RiskManager's profit securing logic
                    if(profit > 0)
                    {
                        m_riskManager.SecureProfit(ticket);
                    }
                }
            }
        }
    }
    
    // ============ SECTION 9: PROFIT SECURING ============
    
    void SecureProfits()
    {
        rm_logger.StartContextWith("SYSTEM", "PROFIT_SECURING");
        
        int positionsSecured = 0;
        double totalProfitSecured = 0.0;
        
        // Use RiskManager for profit securing
        if(m_riskManager != NULL)
        {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(PositionSelectByTicket(ticket))
                {
                    string symbol = PositionGetString(POSITION_SYMBOL);
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    
                    // Use RiskManager to secure profits
                    m_riskManager.SecureProfit(ticket);
                    positionsSecured++;
                    
                    rm_logger.AddDoubleContext("SYSTEM",
                        StringFormat("%s_Secured", symbol),
                        profit, 2);
                }
            }
        }
        
        rm_logger.FlushContext("SYSTEM", AUTHORIZE, "PortfolioManager",
            StringFormat("Profits secured for %d positions", positionsSecured), false);
    }
    
    // ============ SECTION 10: GETTERS ============
    
    double GetTotalCapital() { return m_totalCapital; }
    double GetAllocatedCapital() { return m_metrics.allocatedCapital; }
    double GetAvailableCapital() { return m_metrics.availableCapital; }
    double GetPortfolioReturn() { return m_metrics.portfolioReturn; }
    double GetPortfolioVolatility() { return m_metrics.portfolioVolatility; }
    double GetSharpeRatio(int period = 30) { return CalculateSharpeRatio(period); }
    double GetSortinoRatio(int period = 30) { return CalculateSortinoRatio(period); }
    double GetMaxDrawdown() { return m_metrics.maxDrawdown; }
    double GetCurrentDrawdown() { return m_metrics.currentDrawdown; }
    double GetProfitFactor() { return m_metrics.profitFactor; }
    
    ENUM_CAPITAL_ALLOCATION_METHOD GetAllocationMethod() { return m_allocationMethod; }
    double GetPortfolioCorrelation() { return CalculateAverageCorrelation(); }
    
    // Add method to get RiskManager's risk level
    ENUM_RISK_LEVEL GetPortfolioRiskLevel()
    {
        if(m_riskManager != NULL)
        {
            return m_riskManager.GetRiskLevel();
        }
        return RISK_MODERATE; // Default
    }
    
    // Add method to check if new trades are allowed
    bool CanOpenNewTrades()
    {
        if(m_riskManager != NULL)
        {
            return m_riskManager.CanOpenNewTrades();
        }
        return m_canOpenNewTrades;
    }
    
    void GetUnderperformingSymbols(string &symbols[], int lookbackDays = 7)
    {
        ArrayResize(symbols, 0);
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].performance < 0)
            {
                int size = ArraySize(symbols);
                ArrayResize(symbols, size + 1);
                symbols[size] = m_allocations[i].symbol;
            }
        }
    }
    
    void GetOutperformingSymbols(string &symbols[], int lookbackDays = 7)
    {
        ArrayResize(symbols, 0);
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].performance > 1.0) // > 1% return
            {
                int size = ArraySize(symbols);
                ArrayResize(symbols, size + 1);
                symbols[size] = m_allocations[i].symbol;
            }
        }
    }
    
    // Get maximum concurrent positions
    int GetMaxConcurrentPositions() const { return m_maxConcurrentPositions; }
    
    // ============ SECTION 11: SETTERS ============
    
    void SetMaxPortfolioRisk(double percent)
    {
        m_maxPortfolioRisk = MathMax(10.0, MathMin(percent, 100.0));
        LogConfigChange("MaxPortfolioRisk", DoubleToString(percent, 1));
    }
    
    void SetMaxSymbolRisk(double percent)
    {
        m_maxSymbolRisk = MathMax(1.0, MathMin(percent, 50.0));
        LogConfigChange("MaxSymbolRisk", DoubleToString(percent, 1));
    }
    
    void SetCorrelationLimit(double limit)
    {
        m_correlationLimit = MathMax(0.3, MathMin(limit, 0.95));
        LogConfigChange("CorrelationLimit", DoubleToString(limit, 2));
    }
    
    void SetAllocationMethod(ENUM_CAPITAL_ALLOCATION_METHOD method)
    {
        m_allocationMethod = method;
        LogConfigChange("AllocationMethod", EnumToString(method));
    }
    
    void SetRebalanceFrequency(int hours)
    {
        m_rebalanceFrequency = MathMax(1, hours);
        LogConfigChange("RebalanceFrequency", IntegerToString(hours));
    }
    
    void SetAutoRebalance(bool enable)
    {
        m_autoRebalance = enable;
        LogConfigChange("AutoRebalance", enable ? "TRUE" : "FALSE");
    }
    
    // Set maximum concurrent positions
    void SetMaxConcurrentPositions(int maxPositions)
    {
        m_maxConcurrentPositions = MathMax(1, maxPositions);
        
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("Max concurrent positions set to %d", m_maxConcurrentPositions));
        }
    }
    
    // ============ SECTION 12: PORTFOLIO MONITORING ============
    
    void MonitorPerformance()
    {
        // Update daily returns
        UpdateDailyReturns();
        
        // Update portfolio metrics
        UpdatePortfolioMetrics();
        
        // Update symbol performance
        UpdateSymbolPerformance();
        
        // Check for dynamic risk adjustment
        if(m_dynamicRiskAdjustment)
        {
            AdjustRiskBasedOnPerformance();
        }
        
        // Integrate with RiskManager's monitoring
        if(m_riskManager != NULL)
        {
            // Enforce drawdown limits
            m_riskManager.EnforceDrawdownLimits();
            
            // Close expired positions
            m_riskManager.CloseExpiredPositions();
            
            // Update trailing stops
            m_riskManager.UpdateTrailingStops();
            
            // Get updated risk metrics
            m_metrics.currentDrawdown = m_riskManager.GetCurrentDrawdown();
            m_metrics.winRate = m_riskManager.GetWinRate();
            m_metrics.expectancy = m_riskManager.GetExpectancy();
            m_metrics.profitFactor = m_riskManager.GetProfitFactor();
        }
    }
    
    void PrintPortfolioStatus()
    {
        rm_logger.StartContextWith("SYSTEM", "PORTFOLIO_STATUS");
        
        string status = "\n═══════════════════════════════════════════\n" +
                      "           PORTFOLIO MANAGER STATUS\n" +
                      "═══════════════════════════════════════════\n" +
                      StringFormat("Total Capital: $%.2f\n", m_totalCapital) +
                      StringFormat("Allocated: $%.2f (%.1f%%) | Available: $%.2f\n",
                                 m_metrics.allocatedCapital,
                                 (m_metrics.allocatedCapital/m_totalCapital)*100,
                                 m_metrics.availableCapital) +
                      StringFormat("Portfolio Return: %.2f%% | Volatility: %.2f%%\n",
                                 m_metrics.portfolioReturn, m_metrics.portfolioVolatility) +
                      StringFormat("Sharpe Ratio: %.2f | Sortino Ratio: %.2f\n",
                                 m_metrics.sharpeRatio, m_metrics.sortinoRatio);
        
        // Add RiskManager info if available
        if(m_riskManager != NULL)
        {
            status += StringFormat("Risk Level: %s | Daily P&L: $%.2f\n",
                RiskLevelToString(m_riskManager.GetRiskLevel()),
                m_riskManager.GetDailyPnL());
        }
        
        status += StringFormat("Max Drawdown: %.1f%% | Current: %.1f%%\n",
                             m_metrics.maxDrawdown, m_metrics.currentDrawdown) +
                StringFormat("Profit Factor: %.2f | Recovery Factor: %.2f\n",
                             m_metrics.profitFactor, m_metrics.recoveryFactor) +
                StringFormat("Total Trades: %d | Active Symbols: %d/%d\n",
                             m_totalTrades, CountEnabledSymbols(), ArraySize(m_allocations)) +
                "═══════════════════════════════════════════\n" +
                "SYMBOL ALLOCATIONS:\n";
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                status += StringFormat("  %-8s: $%-8.2f (%-5.1f%%) | Risk: %-4.1f%% | Perf: %-5.1f%%\n",
                    m_allocations[i].symbol,
                    m_allocations[i].capital,
                    m_allocations[i].currentWeight,
                    m_allocations[i].riskBudget,
                    m_allocations[i].performance);
                
                rm_logger.AddDoubleContext("SYSTEM",
                    StringFormat("%s_CurrentWeight", m_allocations[i].symbol),
                    m_allocations[i].currentWeight, 1);
                rm_logger.AddDoubleContext("SYSTEM",
                    StringFormat("%s_Performance", m_allocations[i].symbol),
                    m_allocations[i].performance, 1);
            }
        }
        
        status += "═══════════════════════════════════════════\n";
        
        rm_logger.AddDoubleContext("SYSTEM", "TotalCapital", m_totalCapital, 2);
        rm_logger.AddDoubleContext("SYSTEM", "SharpeRatio", m_metrics.sharpeRatio, 2);
        rm_logger.AddDoubleContext("SYSTEM", "CurrentDrawdown", m_metrics.currentDrawdown, 1);
        
        rm_logger.FlushContext("SYSTEM", OBSERVE, "PortfolioManager",
            "Portfolio status printed", false);
        
        Print(status);
    }
    
private:
    // ============ SECTION 13: PRIVATE HELPER FUNCTIONS ============
    
    // Helper function to calculate trade direction
    ENUM_POSITION_TYPE CalculateDirection(string symbol)
    {
        // Simple example: Use moving average crossover
        double fastMA = iMA(symbol, PERIOD_H1, 10, 0, MODE_SMA, PRICE_CLOSE);
        double slowMA = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        if(fastMA > slowMA)
            return POSITION_TYPE_BUY;
        else
            return POSITION_TYPE_SELL;
    }
    
    // Calculate optimal lot size
    double CalculateOptimalLotSize(string symbol)
    {
        if(m_riskManager != NULL)
        {
            // Use RiskManager to calculate lot size
            double capital = GetCapitalAllocation(symbol);
            if(capital > 0)
            {
                return m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                    symbol, capital, 0);
            }
        }
        
        // Default: 0.1 lots
        return 0.1;
    }
    
    // Calculate stop loss
    double CalculateStopLoss(string symbol, ENUM_POSITION_TYPE direction)
    {
        double currentPrice = (direction == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(symbol, SYMBOL_BID) :
                             SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        // Use RiskManager if available
        if(m_riskManager != NULL)
        {
            return m_riskManager.GetOptimalStopLoss(
                symbol, currentPrice, direction == POSITION_TYPE_BUY);
        }
        
        // Simple ATR-based stop loss
        double atr = iATR(symbol, PERIOD_H1, 14);
        
        if(direction == POSITION_TYPE_BUY)
            return currentPrice - (atr * 2.0);
        else
            return currentPrice + (atr * 2.0);
    }
    
    // Calculate take profit
    double CalculateTakeProfit(string symbol, ENUM_POSITION_TYPE direction)
    {
        double currentPrice = (direction == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(symbol, SYMBOL_BID) :
                             SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        // Use RiskManager if available
        if(m_riskManager != NULL)
        {
            double stopLoss = CalculateStopLoss(symbol, direction);
            return m_riskManager.GetOptimalTakeProfit(
                symbol, PERIOD_H1, currentPrice, stopLoss, direction == POSITION_TYPE_BUY);
        }
        
        // 2:1 risk-reward ratio
        double atr = iATR(symbol, PERIOD_H1, 14);
        
        if(direction == POSITION_TYPE_BUY)
            return currentPrice + (atr * 4.0); // 2x the stop distance
        else
            return currentPrice - (atr * 4.0);
    }
    
    // Calculate average correlation for the portfolio
    double CalculateAverageCorrelation()
    {
        if(m_symbolManager != NULL)
        {
            return m_symbolManager.GetPortfolioAverageCorrelation();
        }
        
        // Fallback: calculate from correlation matrix if available
        if(ArraySize(m_metrics.correlationMatrix) > 0)
        {
            double sum = 0.0;
            int count = 0;
            int symbolCount = (int)MathSqrt(ArraySize(m_metrics.correlationMatrix));
            
            for(int i = 0; i < symbolCount; i++)
            {
                for(int j = i + 1; j < symbolCount; j++)
                {
                    sum += MathAbs(m_metrics.correlationMatrix[i * symbolCount + j]);
                    count++;
                }
            }
            
            return count > 0 ? sum / count : 0.0;
        }
        
        return 0.0; // Default if no data
    }

    // Helper function to get symbol performance
    double GetSymbolPerformance(string symbol)
    {
        // Search in allocations
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].symbol == symbol)
            {
                return m_allocations[i].performance;
            }
        }
        
        // Search in symbol manager if available
        if(m_symbolManager != NULL)
        {
            // You might need to implement a GetSymbolPerformance method in SymbolManager
            // or use existing methods
            return 0.0; // Placeholder
        }
        
        return 0.0; // Default if not found
    }
    
    // Initialization helpers
    void InitializeMetrics()
    {
        ZeroMemory(m_metrics);
        m_metrics.totalCapital = m_totalCapital;
        m_metrics.allocatedCapital = 0.0;
        m_metrics.availableCapital = m_totalCapital;
        
        // Initialize asset class exposure array
        ArrayInitialize(m_metrics.assetClassExposure, 0.0);

        // Or if you want to be explicit:
        for(int i = 0; i < 7; i++)
        {
            m_metrics.assetClassExposure[i] = 0.0;
        }
        for(int i = 0; i < 7; i++)
        {
            m_metrics.assetClassExposure[i] = 0.0;
        }
    }
    
    ENUM_ASSET_CLASS DetermineAssetClass(string symbol)
    {
        // Major forex pairs
        string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD"};
        for(int i = 0; i < ArraySize(majors); i++)
        {
            if(symbol == majors[i]) return ASSET_FOREX_MAJOR;
        }
        
        // Metals
        if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "XAG") >= 0)
            return ASSET_METAL;
        
        // Energy
        if(StringFind(symbol, "OIL") >= 0 || StringFind(symbol, "GAS") >= 0)
            return ASSET_ENERGY;
        
        // Default to forex minor
        return ASSET_FOREX_MINOR;
    }
    
    // Allocation methods
    void AllocateEqualCapital(int enabledCount)
    {
        double weightPerSymbol = 100.0 / enabledCount;
        
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                m_allocations[i].targetWeight = weightPerSymbol;
                m_allocations[i].capital = (m_totalCapital * weightPerSymbol) / 100.0;
            }
        }
    }
    
    void AllocateVolatilityAdjusted()
    {
        double totalInverseVol = 0.0;
        
        // Calculate total inverse volatility
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].volatility > 0)
            {
                totalInverseVol += 1.0 / m_allocations[i].volatility;
            }
        }
        
        // Allocate weights inversely proportional to volatility
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].volatility > 0)
            {
                double weight = (1.0 / m_allocations[i].volatility) / totalInverseVol * 100.0;
                m_allocations[i].targetWeight = weight;
                m_allocations[i].capital = (m_totalCapital * weight) / 100.0;
            }
        }
    }
    
    void AllocateSharpeBased()
    {
        double totalSharpe = 0.0;
        
        // Calculate total Sharpe (positive only)
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled && m_allocations[i].sharpeRatio > 0)
            {
                totalSharpe += m_allocations[i].sharpeRatio;
            }
        }
        
        if(totalSharpe > 0)
        {
            for(int i = 0; i < ArraySize(m_allocations); i++)
            {
                if(m_allocations[i].enabled && m_allocations[i].sharpeRatio > 0)
                {
                    double weight = (m_allocations[i].sharpeRatio / totalSharpe) * 100.0;
                    m_allocations[i].targetWeight = weight;
                    m_allocations[i].capital = (m_totalCapital * weight) / 100.0;
                }
            }
        }
    }
    
    void AllocateKellyCriterion()
    {
        // Simplified Kelly criterion
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                double winRate = m_allocations[i].winRate / 100.0;
                double avgWin = 1.0; // Simplified
                double avgLoss = 1.0; // Simplified
                
                if(avgLoss > 0)
                {
                    double kelly = winRate - ((1 - winRate) / (avgWin / avgLoss));
                    kelly = MathMax(0.0, MathMin(kelly, 0.25)); // Cap at 25%
                    
                    m_allocations[i].targetWeight = kelly * 100.0;
                    m_allocations[i].capital = m_totalCapital * kelly;
                }
            }
        }
    }
    
    void ApplyRiskBudgets()
    {
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                // Adjust capital based on risk budget
                double riskAdjustedCapital = m_allocations[i].capital * 
                    (m_allocations[i].riskBudget / m_maxSymbolRisk);
                
                m_allocations[i].capital = riskAdjustedCapital;
                m_allocations[i].targetWeight = (riskAdjustedCapital / m_totalCapital) * 100.0;
            }
        }
    }
    
    // Enhanced risk limits check that integrates RiskManager
    bool CheckRiskLimits(string symbol)
    {
        rm_logger.StartContextWith(symbol, "PORTFOLIO_RISK_LIMITS_CHECK");
        
        bool allChecksPassed = true;
        string failureReasons = "";
        
        // 1. Check RiskManager risk limits
        if(m_riskManager != NULL)
        {
            ENUM_RISK_LEVEL riskLevel = m_riskManager.GetRiskLevel();
            
            rm_logger.AddToContext(symbol, "RiskLevel", RiskLevelToString(riskLevel));
            
            switch(riskLevel)
            {
                case RISK_CRITICAL:
                    allChecksPassed = false;
                    failureReasons += "Risk level CRITICAL. ";
                    rm_logger.AddToContext(symbol, "BlockReason", "RiskCritical", true);
                    break;
                    
                case RISK_HIGH:
                    // Allow trades but log warning
                    rm_logger.AddToContext(symbol, "Warning", "RiskLevelHigh");
                    // Continue with other checks
                    break;
                    
                case RISK_MODERATE:
                case RISK_LOW:
                case RISK_OPTIMAL:
                    // All good, continue checks
                    break;
            }
            
            // Check if RiskManager allows new trades
            if(allChecksPassed && !m_riskManager.CanOpenNewTrades())
            {
                allChecksPassed = false;
                failureReasons += "RiskManager blocking new trades. ";
                rm_logger.AddToContext(symbol, "BlockReason", "RiskManagerBlock", true);
            }
        }
        
        // 2. Check Portfolio-level risk limits
        if(allChecksPassed)
        {
            // A. Check maximum portfolio exposure
            if(m_metrics.allocatedCapital > m_totalCapital * (m_maxPortfolioRisk / 100.0))
            {
                allChecksPassed = false;
                failureReasons += StringFormat("Portfolio exposure (%.1f%%) exceeds limit (%.1f%%). ",
                    (m_metrics.allocatedCapital / m_totalCapital) * 100.0,
                    m_maxPortfolioRisk);
                rm_logger.AddToContext(symbol, "BlockReason", "PortfolioExposureLimit", true);
            }
            
            // B. Check symbol-specific risk budget
            int index = GetSymbolIndex(symbol);
            if(index >= 0)
            {
                if(m_allocations[index].riskBudget <= 0)
                {
                    allChecksPassed = false;
                    failureReasons += "Symbol risk budget exhausted. ";
                    rm_logger.AddToContext(symbol, "BlockReason", "SymbolRiskBudget", true);
                }
                
                // C. Check if symbol already at max exposure
                double maxSymbolExposure = GetSymbolMaxExposure(symbol);
                double currentSymbolWeight = m_allocations[index].currentWeight;
                
                if(currentSymbolWeight >= maxSymbolExposure)
                {
                    allChecksPassed = false;
                    failureReasons += StringFormat("Symbol exposure (%.1f%%) at maximum (%.1f%%). ",
                        currentSymbolWeight, maxSymbolExposure);
                    rm_logger.AddToContext(symbol, "BlockReason", "SymbolExposureLimit", true);
                }
            }
            
            // D. Check correlation risk (if SymbolManager available)
            if(m_symbolManager != NULL)
            {
                if(!m_symbolManager.CheckCorrelationLimit(symbol, m_correlationLimit))
                {
                    allChecksPassed = false;
                    failureReasons += "Correlation limit would be exceeded. ";
                    rm_logger.AddToContext(symbol, "BlockReason", "CorrelationLimit", true);
                }
            }
            
            // E. Check concurrent positions limit
            if(PositionsTotal() >= m_maxConcurrentPositions)
            {
                allChecksPassed = false;
                failureReasons += StringFormat("Max positions (%d) reached. ",
                    m_maxConcurrentPositions);
                rm_logger.AddToContext(symbol, "BlockReason", "MaxPositions", true);
            }
            
            // F. Check if trading is allowed (AccountManager permission)
            if(m_accountManager != NULL && !m_accountManager.CanOpenNewPositions())
            {
                allChecksPassed = false;
                failureReasons += "Account not allowing new positions. ";
                rm_logger.AddToContext(symbol, "BlockReason", "AccountNoNewPositions", true);
            }
        }
        
        // Log the result
        if(allChecksPassed)
        {
            if(m_riskManager != NULL)
            {
                rm_logger.AddDoubleContext(symbol, "DailyPnL", m_riskManager.GetDailyPnL(), 2);
                rm_logger.AddDoubleContext(symbol, "CurrentDrawdown", m_riskManager.GetCurrentDrawdown(), 2);
            }
            
            rm_logger.AddDoubleContext(symbol, "PortfolioExposure", 
                (m_metrics.allocatedCapital / m_totalCapital) * 100.0, 1);
            rm_logger.AddDoubleContext(symbol, "MaxPortfolioExposure", m_maxPortfolioRisk, 1);
            
            int index = GetSymbolIndex(symbol);
            if(index >= 0)
            {
                rm_logger.AddDoubleContext(symbol, "SymbolWeight", 
                    m_allocations[index].currentWeight, 1);
                rm_logger.AddDoubleContext(symbol, "SymbolRiskBudget", 
                    m_allocations[index].riskBudget, 1);
            }
            
            rm_logger.FlushContext(symbol, AUTHORIZE, "PortfolioManager",
                "All risk limits passed", false);
        }
        else
        {
            rm_logger.AddToContext(symbol, "FailureReasons", failureReasons, true);
            rm_logger.FlushContext(symbol, ENFORCE, "PortfolioManager",
                StringFormat("Risk limits failed: %s", failureReasons), false);
        }
        
        return allChecksPassed;
    }
    
    double CalculateVolatility(string symbol, int period)
    {
        // Calculate ATR-based volatility
        int handle = iATR(symbol, PERIOD_D1, period);
        if(handle != INVALID_HANDLE)
        {
            double atr[1];
            if(CopyBuffer(handle, 0, 0, 1, atr) > 0)
            {
                IndicatorRelease(handle);
                double price = SymbolInfoDouble(symbol, SYMBOL_BID);
                return price > 0 ? (atr[0] / price) * 100.0 : 1.0;
            }
            IndicatorRelease(handle);
        }
        
        return 1.0; // Default 1% volatility
    }
    
    double CalculateProfitabilityScore(string symbol)
    {
        int index = GetSymbolIndex(symbol);
        if(index < 0) return -9999.0;
        
        double score = 0.0;
        
        // 1. Performance (40% weight)
        score += m_allocations[index].performance * 0.4;
        
        // 2. Sharpe ratio (30% weight)
        score += m_allocations[index].sharpeRatio * 3.0 * 0.3;
        
        // 3. Priority (20% weight)
        score += (m_allocations[index].priority / 10.0) * 0.2;
        
        // 4. Recent activity (10% weight, penalize if traded recently)
        datetime now = TimeCurrent();
        int hoursSinceLastTrade = (int)((now - m_allocations[index].lastTradeTime) / 3600);
        if(hoursSinceLastTrade < 1) score -= 0.1; // Penalize if traded in last hour
        
        return score;
    }

    double CalculateOptimalStopLoss(string symbol)
    {
        if(m_riskManager != NULL)
        {
            // Use RiskManager to calculate optimal stop loss
            double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            return m_riskManager.GetOptimalStopLoss(symbol, currentPrice, true);
        }
        
        // Fallback to ATR-based stop
        double atr = iATR(symbol, PERIOD_H1, 14);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        return price - (atr * 2.0);
    }
    
    double CalculatePositionSizeFromCapital(string symbol, double capital)
    {
        if(m_riskManager != NULL)
        {
            return m_riskManager.CalculatePositionSizeFromCapital(symbol, capital);
        }
        
        // Fallback calculation
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        if(price > 0 && contractSize > 0)
        {
            return capital / (price * contractSize);
        }
        
        return 0.01; // Default
    }
    
    double CalculateRiskAdjustedSize(string symbol, double baseLots, 
                                     double stopLoss, ENUM_POSITION_TYPE direction)
    {
        if(m_riskManager != NULL)
        {
            return m_riskManager.CalculateRiskAdjustedSize(
                symbol, baseLots, stopLoss, direction);
        }
        
        return baseLots;
    }
    
    ENUM_POSITION_TYPE DetermineTradeDirection(string symbol)
    {
        // Simplified direction determination
        // TODO: In real implementation, use your trading logic
        double maFast = iMA(symbol, PERIOD_H1, 10, 0, MODE_SMA, PRICE_CLOSE);
        double maSlow = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        if(maFast > maSlow)
            return POSITION_TYPE_BUY;
        else
            return POSITION_TYPE_SELL;
    }
    
    string GenerateTradeReason(string symbol)
    {
        // Generate trade reason based on analysis
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            return StringFormat("Portfolio allocation | Weight: %.1f%% | Risk: %.1f%%",
                m_allocations[index].targetWeight,
                m_allocations[index].riskBudget);
        }
        
        return "Portfolio allocation";
    }
    
    // Position tracking helpers
    void UpdateAllocationAfterTrade(string symbol, double lots)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            // Update last trade time
            m_allocations[index].lastTradeTime = TimeCurrent();
            
            // Update current weight (simplified)
            double positionValue = CalculatePositionValue(symbol, lots);
            m_allocations[index].currentWeight = (positionValue / m_totalCapital) * 100.0;
        }
    }
    
    double CalculatePositionValue(string symbol, double lots)
    {
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        return lots * contractSize * price;
    }
    
    // Performance tracking helpers
    void UpdateDailyReturns()
    {
        // Add today's return to array
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        static double lastEquity = m_initialCapital;
        
        if(lastEquity > 0)
        {
            double dailyReturn = ((equity - lastEquity) / lastEquity) * 100.0;
            
            int size = ArraySize(m_dailyReturns);
            ArrayResize(m_dailyReturns, size + 1);
            m_dailyReturns[size] = dailyReturn;
            
            // Keep only last 100 days
            if(size >= 100)
            {
                for(int i = 0; i < 99; i++)
                {
                    m_dailyReturns[i] = m_dailyReturns[i + 1];
                }
                ArrayResize(m_dailyReturns, 99);
            }
        }
        
        lastEquity = equity;
    }
    
    void UpdatePortfolioMetrics()
    {
        // Update return
        m_metrics.portfolioReturn = ((m_totalCapital - m_initialCapital) / m_initialCapital) * 100.0;
        
        // Update volatility (standard deviation of daily returns)
        m_metrics.portfolioVolatility = CalculateStandardDeviation(m_dailyReturns);
        
        // Update Sharpe ratio
        m_metrics.sharpeRatio = CalculateSharpeRatio(30);
        
        // Update Sortino ratio
        m_metrics.sortinoRatio = CalculateSortinoRatio(30);
        
        // Update drawdown
        UpdateDrawdownMetrics();
        
        // Update profit factor
        if(m_totalLoss > 0)
            m_metrics.profitFactor = m_totalProfit / m_totalLoss;
        else
            m_metrics.profitFactor = 999.0;
    }
    
    void UpdateSymbolPerformance()
    {
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                // Simplified performance calculation
                // In real implementation, calculate actual returns for each symbol
                m_allocations[i].performance = CalculateSymbolReturn(m_allocations[i].symbol, 30);
                m_allocations[i].volatility = CalculateVolatility(m_allocations[i].symbol, 30);
                m_allocations[i].sharpeRatio = m_allocations[i].performance / 
                    MathMax(m_allocations[i].volatility, 0.01);
            }
        }
    }
    
    double CalculateSymbolReturn(string symbol, int period)
    {
        // Simplified return calculation
        // In real implementation, calculate actual returns from trades
        return MathRand() % 200 / 100.0 - 1.0; // Random between -1% and +1%
    }
    
    double CalculateSharpeRatio(int period)
    {
        if(ArraySize(m_dailyReturns) < 2) return 0.0;
        
        double avgReturn = CalculateAverageReturn();
        double stdDev = m_metrics.portfolioVolatility;
        
        if(stdDev > 0)
            return (avgReturn / stdDev) * MathSqrt(252); // Annualized
        else
            return 0.0;
    }
    
    double CalculateSortinoRatio(int period)
    {
        if(ArraySize(m_dailyReturns) < 2) return 0.0;
        
        double avgReturn = CalculateAverageReturn();
        double downsideDev = CalculateDownsideDeviation();
        
        if(downsideDev > 0)
            return (avgReturn / downsideDev) * MathSqrt(252); // Annualized
        else
            return 999.0;
    }
    
    double CalculateAverageReturn()
    {
        double sum = 0.0;
        for(int i = 0; i < ArraySize(m_dailyReturns); i++)
        {
            sum += m_dailyReturns[i];
        }
        
        return ArraySize(m_dailyReturns) > 0 ? sum / ArraySize(m_dailyReturns) : 0.0;
    }
    
    double CalculateStandardDeviation(double &array[])
    {
        if(ArraySize(array) < 2) return 0.0;
        
        double mean = 0.0;
        for(int i = 0; i < ArraySize(array); i++)
        {
            mean += array[i];
        }
        mean /= ArraySize(array);
        
        double variance = 0.0;
        for(int i = 0; i < ArraySize(array); i++)
        {
            variance += MathPow(array[i] - mean, 2);
        }
        variance /= (ArraySize(array) - 1);
        
        return MathSqrt(variance);
    }
    
    double CalculateDownsideDeviation()
    {
        if(ArraySize(m_dailyReturns) < 2) return 0.0;
        
        double mean = CalculateAverageReturn();
        double sumSquares = 0.0;
        int count = 0;
        
        for(int i = 0; i < ArraySize(m_dailyReturns); i++)
        {
            if(m_dailyReturns[i] < mean)
            {
                sumSquares += MathPow(m_dailyReturns[i] - mean, 2);
                count++;
            }
        }
        
        if(count > 1)
            return MathSqrt(sumSquares / count);
        else
            return 0.0;
    }
    
    void UpdateDrawdownMetrics()
    {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Update peak equity
        if(equity > m_metrics.maxDrawdown)
        {
            m_metrics.maxDrawdown = equity;
        }
        
        // Calculate current drawdown
        if(m_metrics.maxDrawdown > 0)
        {
            m_metrics.currentDrawdown = ((m_metrics.maxDrawdown - equity) / m_metrics.maxDrawdown) * 100.0;
        }
        
        // Update max drawdown
        if(m_metrics.currentDrawdown > m_metrics.maxDrawdown)
        {
            m_metrics.maxDrawdown = m_metrics.currentDrawdown;
        }
    }
    
    // Portfolio adjustment helpers
    void UpdateWeightsBasedOnPerformance()
    {
        double totalPerformance = 0.0;
        
        // Calculate total performance
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled)
            {
                totalPerformance += MathMax(m_allocations[i].performance, 0.0);
            }
        }
        
        // Adjust weights based on performance
        if(totalPerformance > 0)
        {
            for(int i = 0; i < ArraySize(m_allocations); i++)
            {
                if(m_allocations[i].enabled)
                {
                    double performanceWeight = MathMax(m_allocations[i].performance, 0.0) / totalPerformance;
                    
                    // Blend with original weight (50/50 mix)
                    m_allocations[i].targetWeight = 
                        (m_allocations[i].targetWeight * 0.5) + (performanceWeight * 100.0 * 0.5);
                }
            }
        }
    }
    
    void AdjustRiskBasedOnPerformance()
    {
        // Reduce risk when in drawdown
        if(m_metrics.currentDrawdown > 10.0)
        {
            for(int i = 0; i < ArraySize(m_allocations); i++)
            {
                m_allocations[i].riskBudget *= m_drawdownReductionFactor;
            }
        }
        
        // Increase risk when profitable
        else if(m_metrics.portfolioReturn > 5.0)
        {
            for(int i = 0; i < ArraySize(m_allocations); i++)
            {
                m_allocations[i].riskBudget *= m_profitIncreaseFactor;
                m_allocations[i].riskBudget = MathMin(m_allocations[i].riskBudget, m_maxSymbolRisk);
            }
        }
    }
    
    void ReduceSymbolExposure(string symbol, double percent)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            // Close portion of positions
            double closePercent = percent / 100.0;
            ClosePartialPositions(symbol, closePercent);
            
            // Reduce allocation
            m_allocations[index].capital *= (1.0 - closePercent);
            m_allocations[index].targetWeight = (m_allocations[index].capital / m_totalCapital) * 100.0;
            
            if(rm_logger != NULL)
            {
                rm_logger.KeepNotes(symbol, OBSERVE, "PortfolioManager",
                    StringFormat("Exposure reduced by %.1f%%", percent));
            }
        }
    }
    
    // Utility helpers
    int GetSymbolIndex(string symbol)
    {
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].symbol == symbol)
                return i;
        }
        return -1;
    }
    
    int CountEnabledSymbols()
    {
        int count = 0;
        for(int i = 0; i < ArraySize(m_allocations); i++)
        {
            if(m_allocations[i].enabled) count++;
        }
        return count;
    }
    
    string AssetClassToString(ENUM_ASSET_CLASS assetClass)
    {
        switch(assetClass)
        {
            case ASSET_FOREX_MAJOR: return "FOREX_MAJOR";
            case ASSET_FOREX_MINOR: return "FOREX_MINOR";
            case ASSET_FOREX_EXOTIC: return "FOREX_EXOTIC";
            case ASSET_METAL: return "METAL";
            case ASSET_ENERGY: return "ENERGY";
            case ASSET_INDEX: return "INDEX";
            case ASSET_CRYPTO: return "CRYPTO";
            default: return "UNKNOWN";
        }
    }
    
    // Helper to convert RiskLevel to string
    string RiskLevelToString(ENUM_RISK_LEVEL level)
    {
        switch(level)
        {
            case RISK_CRITICAL: return "CRITICAL";
            case RISK_HIGH: return "HIGH";
            case RISK_MODERATE: return "MODERATE";
            case RISK_LOW: return "LOW";
            case RISK_OPTIMAL: return "OPTIMAL";
            default: return "UNKNOWN";
        }
    }
    
    // Trade execution helpers
    bool MoveStopToBreakeven(ulong ticket)
    {
        if(!PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
        
        // Add small buffer
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double buffer = 10.0 * point; // 10 points buffer
        
        double breakevenSL = isBuy ? openPrice - buffer : openPrice + buffer;
        
        return m_trade.PositionModify(ticket, breakevenSL, 0);
    }
    
    bool TakePartialProfit(ulong ticket, double ratio)
    {
        if(!PositionSelectByTicket(ticket)) return false;
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double volume = PositionGetDouble(POSITION_VOLUME);
        
        // Close partial position
        double closeVolume = volume * ratio;
        
        // For MQL5, we need to close and reopen for partial closure
        // This is simplified - in real implementation use PositionClosePartial if available
        return m_trade.PositionClose(ticket);
    }
    
    void CloseSymbolPositions(string symbol, string reason)
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    m_trade.PositionClose(ticket);
                    
                    if(rm_logger != NULL)
                    {
                        rm_logger.KeepNotes(symbol, ENFORCE, "PortfolioManager",
                            StringFormat("Position closed: %s", reason));
                    }
                }
            }
        }
    }
    
    void ClosePartialPositions(string symbol, double ratio)
    {
        double totalVolume = 0.0;
        
        // First, calculate total volume
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    totalVolume += PositionGetDouble(POSITION_VOLUME);
                }
            }
        }
        
        // Close positions until ratio is met
        double targetVolume = totalVolume * ratio;
        double closedVolume = 0.0;
        
        for(int i = PositionsTotal() - 1; i >= 0 && closedVolume < targetVolume; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    double volume = PositionGetDouble(POSITION_VOLUME);
                    if(closedVolume + volume <= targetVolume)
                    {
                        m_trade.PositionClose(ticket);
                        closedVolume += volume;
                    }
                }
            }
        }
    }
    
    void LogConfigChange(string parameter, string newValue)
    {
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("Configuration changed: %s = %s", parameter, newValue));
        }
    }
    
    // Convert account health enum to string
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
    
    // Calculate proposed exposure for a position
    double CalculateProposedExposure(string symbol, double lotSize)
    {
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        if(price > 0 && contractSize > 0)
        {
            return lotSize * contractSize * price;
        }
        
        return lotSize * 100000.0; // Simplified: 1 lot = 100,000 units
    }
    
    // Get maximum exposure for a symbol
    double GetSymbolMaxExposure(string symbol)
    {
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            // Base on performance and risk budget
            double baseMax = 15.0; // Default 15%
            
            // Adjust based on performance
            if(m_allocations[index].performance > 10.0)
                baseMax = MathMin(baseMax * 1.3, 25.0); // Increase for winners
            else if(m_allocations[index].performance < -5.0)
                baseMax = MathMax(baseMax * 0.7, 5.0); // Decrease for losers
            
            return baseMax;
        }
        
        return 10.0; // Default
    }
    
    // You might also need these helper methods:
    void UpdateTradePerformance(string symbol, double profit)
    {
        // Update symbol performance
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_totalTrades++;
            if(profit > 0)
            {
                m_totalProfit += profit;
                m_allocations[index].totalProfit += profit;
                m_allocations[index].winRate = CalculateWinRate(index);
            }
            else
            {
                m_totalLoss += MathAbs(profit);
            }
        }
    }
    
    void UpdateTradeHistory(string symbol)
    {
        // Update trade history for the symbol
        // Could track number of trades, last trade time, etc.
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            m_allocations[index].lastTradeTime = TimeCurrent();
        }
    }
    
    void UpdatePositionTracking(string symbol, double volume)
    {
        // Update current position tracking
        int index = GetSymbolIndex(symbol);
        if(index >= 0)
        {
            // Calculate current weight based on position
            double positionValue = CalculatePositionValue(symbol, volume);
            m_allocations[index].currentWeight = (positionValue / m_totalCapital) * 100.0;
        }
    }
    
    double CalculateWinRate(int allocationIndex)
    {
        if(m_totalTrades > 0 && m_totalProfit >= 0)
        {
            return (double)m_totalProfit / m_totalTrades * 100.0;
        }
        return 0.0;
    }

    // Helper to get symbol from deal
    string GetSymbolFromDeal(long dealTicket)
    {
        if(HistoryDealSelect(dealTicket))
        {
            return HistoryDealGetString(dealTicket, DEAL_SYMBOL);
        }
        return "";
    }
    
    // Helper to get symbol from position
    string GetSymbolFromPosition(long positionTicket)
    {
        if(PositionSelectByTicket(positionTicket))
        {
            return PositionGetString(POSITION_SYMBOL);
        }
        return "";
    }
    
    // Your existing helper functions
    void ProcessNewDeal(const MqlTradeTransaction &trans)
    {
        string symbol = GetSymbolFromDeal(trans.deal);
        if(symbol == "") symbol = trans.symbol; // Fallback to trans.symbol
        
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("New deal added: %s (Deal: %d, Price: %.5f, Volume: %.3f)",
                symbol, trans.deal, trans.price, trans.volume));
        }
    }
    
    void ProcessHistoryUpdate(const MqlTradeTransaction &trans)
    {
        string symbol = GetSymbolFromDeal(trans.deal);
        if(symbol == "") symbol = trans.symbol; // Fallback
        
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("History updated: %s (Deal: %d)",
                symbol, trans.deal));
        }
    }
    
    void ProcessPositionUpdate(const MqlTradeTransaction &trans)
    {
        string symbol = GetSymbolFromPosition(trans.position);
        if(symbol == "") symbol = trans.symbol; // Fallback
        
        if(rm_logger != NULL)
        {
            rm_logger.KeepNotes("SYSTEM", OBSERVE, "PortfolioManager",
                StringFormat("Position updated: %s (Position: %d, Volume: %.3f)",
                symbol, trans.position, trans.volume));
        }
    }
};

// Global instance
PortfolioManager portfolioManager;