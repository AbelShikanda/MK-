//+------------------------------------------------------------------+
//|                     OrderManager.mqh                             |
//|                  Complete Order Management System                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/TradeUtils.mqh"
#include "../risk/RiskManager.mqh"
#include "../utils/ResourceManager.mqh"  // Logging system
#include "../utils/System/sys.mqh"

// ============================================================
//                      ENUMS
// ============================================================
enum ENUM_CLOSE_PRIORITY 
{
    CLOSE_SMALLEST_PROFIT,    // Default for folding - minimize impact
    CLOSE_BIGGEST_LOSS,       // For damage control
    CLOSE_SMALLEST_LOSS,      // For gradual recovery
    CLOSE_OLDEST,             // Based on opening time
    CLOSE_NEWEST              // Based on opening time
};

// ============================================================
//                     ORDER MANAGER CLASS
// ============================================================
class OrderManager
{
private:
    // ================= PRIVATE VARIABLES =================
    CTrade trade;
    ResourceManager* logger;
    RiskManager* m_riskManager;
    TradeDecision tradeDecision;
    bool loggerEnabled;
    
    string lastDecision;
    int dailyTradesCount;
    double marginSafetyBuffer;
    
public:
    // ================= CONSTRUCTOR =================
    OrderManager()
    {
        logger = NULL;
        m_riskManager = NULL;
        loggerEnabled = false;
        lastDecision = "";
        dailyTradesCount = 0;
        marginSafetyBuffer = 0.8;
        
        // trade.SetExpertMagicNumber(ExpertMagicNumber);
        trade.SetDeviationInPoints(10);
        trade.SetTypeFilling(ORDER_FILLING_FOK);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", OBSERVE, "OrderManager", 
                           "Constructor called - OrderManager instance created", 
                           false, false, 0);
        }
    }
    
    // ================= PUBLIC METHODS =================
    
    // ============ INITIALIZATION ============
    void Initialize(double buffer = 0.8, RiskManager* g_riskManager = NULL)
    {
        marginSafetyBuffer = MathMax(0.1, MathMin(buffer, 1.0));
        m_riskManager = g_riskManager;
        
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "ORDERMANAGER_INIT");
            logger.AddDoubleContext("SYSTEM", "MarginBuffer", marginSafetyBuffer * 100, 0);
            logger.AddToContext("SYSTEM", "RiskManagerAttached", (m_riskManager != NULL) ? "YES" : "NO");
            logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                              "Initialized with margin safety buffer", false);
        }
        
        Print("OrderManager: Initialized with margin safety buffer: ", 
              DoubleToString(marginSafetyBuffer * 100, 0), "%",
              " | RiskManager: ", (m_riskManager != NULL ? "Attached" : "Not attached"));
    }
    
    void SetLogger(ResourceManager &log)
    {
        logger = &log;
        loggerEnabled = true;
        
        if(logger != NULL)
        {
            logger.KeepNotes("SYSTEM", AUTHORIZE, "OrderManager", 
                           "Logger attached successfully to OrderManager", false, false, 0);
        }
    }
    
    void SetRiskManager(RiskManager &f_riskManager)
    {
        m_riskManager = &f_riskManager;
        
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", OBSERVE, "OrderManager", 
                           "RiskManager attached to OrderManager", false, false, 0);
        }
    }
    
    // ============ GETTERS & SETTERS ============
    string GetLastDecision() { return lastDecision; }
    int GetDailyTradesCount() { return dailyTradesCount; }
    void ResetDailyTrades() { 
        dailyTradesCount = 0;
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", OBSERVE, "OrderManager", 
                           "Daily trades counter reset to 0", false, false, 0);
        }
    }
    void SetMarginSafetyBuffer(double buffer) { 
        marginSafetyBuffer = buffer;
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", OBSERVE, "OrderManager", 
                           StringFormat("Margin safety buffer set to %.1f%%", buffer * 100), 
                           false, false, 0);
        }
    }
    RiskManager* GetRiskManager() { return m_riskManager; }
    bool IsLoggerEnabled() const { return loggerEnabled; }
    ResourceManager* GetLogger() const { return logger; }
    
    // ============ TRADE EXECUTION ============
    //+------------------------------------------------------------------+
    //| Enhanced TryOpenTrade with Reason Tag                           |
    //+------------------------------------------------------------------+
    bool TryOpenTradeWithReason(string symbol, bool isBuy, double lot, double sl, double tp, string reason = "")
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "TRY_OPEN_TRADE");
            logger.AddToContext(symbol, "Direction", isBuy ? "BUY" : "SELL", true);
            logger.AddDoubleContext(symbol, "LotSize", lot, 3);
            logger.AddDoubleContext(symbol, "StopLoss", sl, 5);
            logger.AddDoubleContext(symbol, "TakeProfit", tp, 5);
            logger.AddToContext(symbol, "Reason", reason);
        }
        
        // 1. Get CURRENT market price for execution
        double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double executionPrice = isBuy ? currentAsk : currentBid;
        
        // 2. Track whether we're using signal price or fallback
        bool usingSignalPrice = false;
        bool usingSignalSLTP = false;
        string priceSource = "MARKET";
        string sltpSource = "PARAMETER";
        double finalSL = sl;
        double finalTP = tp;
        
        // 3. Validate signal if we have one
        if(tradeDecision.signal.isValid && !tradeDecision.signal.isExpired)
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "SignalAvailable", "YES");
                logger.AddDoubleContext(symbol, "SignalPrice", tradeDecision.signal.entryPrice, 5);
            }
            
            // Check if signal price is still relevant
            double signalPrice = tradeDecision.signal.entryPrice;
            double priceDiff = MathAbs(executionPrice - signalPrice);
            double maxSlippage = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            
            if(priceDiff <= maxSlippage)
            {
                // Signal price is still good - use it
                executionPrice = signalPrice;
                usingSignalPrice = true;
                priceSource = "SIGNAL";
                
                // Check if we should use signal's SL/TP
                if(tradeDecision.signal.stopLoss > 0)
                {
                    finalSL = tradeDecision.signal.stopLoss;
                    usingSignalSLTP = true;
                    sltpSource = "SIGNAL";
                }
                
                if(tradeDecision.signal.takeProfit > 0 && tradeDecision.signal.takeProfit != tp)
                {
                    finalTP = tradeDecision.signal.takeProfit;
                    usingSignalSLTP = true;
                    sltpSource = "SIGNAL";
                }
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "UsingSignalPrice", "YES");
                    logger.AddToContext(symbol, "SLTPSource", sltpSource);
                }
            }
            else
            {
                // Signal price outdated - fallback to current price
                string slippageMsg = StringFormat("Signal price outdated: Signal=%.5f, Market=%.5f, Diff=%.5f",
                                                signalPrice, executionPrice, priceDiff);
                Print("FALLBACK: ", slippageMsg);
                
                executionPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "SignalOutdated", "YES");
                    logger.KeepNotes(symbol, WARN, "OrderManager", 
                                    "Using market price fallback: " + slippageMsg, 
                                    false, false, 0);
                }
            }
        }
        else
        {
            Print("FALLBACK: No valid signal available, using market price");
            executionPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "SignalAvailable", "NO");
                logger.AddToContext(symbol, "PriceSource", "MARKET_FALLBACK");
            }
        }
        
        // 4. Validate with RiskManager if available
        if(m_riskManager != NULL)
        {
            // Check if RiskManager allows this trade
            if(!m_riskManager.AllowNewTrade(symbol, lot, reason))
            {
                string blockMsg = StringFormat("Trade blocked by RiskManager: %s", reason);
                Print("RISKMANAGER_BLOCKED: ", blockMsg);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "RiskManagerBlocked", "YES");
                    logger.AddToContext(symbol, "BlockReason", reason);
                    logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                      "Trade blocked by RiskManager", false);
                }
                return false;
            }
            
            // Check exposure limits
            if(!m_riskManager.CheckExposureLimits(symbol, lot))
            {
                string exposureMsg = StringFormat("Exposure limit exceeded: Lot=%.3f", lot);
                Print("EXPOSURE_LIMIT_EXCEEDED: ", exposureMsg);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "ExposureLimitExceeded", "YES");
                    logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                      "Exposure limit exceeded", false);
                }
                return false;
            }
            
            // Check margin sufficiency using RiskManager
            if(!m_riskManager.IsMarginSufficient(symbol, lot))
            {
                Print("INSUFFICIENT_MARGIN_RM: RiskManager blocked trade for ", symbol);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "MarginInsufficientRM", "YES");
                    logger.FlushContext(symbol, WARN, "OrderManager", 
                                      "Insufficient margin (RiskManager)", false);
                }
                return false;
            }
            
            // Validate stop loss placement using execution price
            if(finalSL > 0)
            {
                m_riskManager.ValidateStopLossPlacement(symbol, finalSL, executionPrice, isBuy);
            }
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "RiskManagerValidation", "PASSED");
            }
        }
        
        // 5. Validate lot size
        double maxSafeLot = CalculateMaxSafeLotSize(symbol);
        if(lot > maxSafeLot)
        {
            string lotAdjustMsg = StringFormat("Lot reduced from %.3f to %.3f", lot, maxSafeLot);
            Print("LOT_TOO_LARGE: ", lotAdjustMsg);
            lot = maxSafeLot;
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "LotAdjusted", "YES");
                logger.AddDoubleContext(symbol, "OriginalLot", lot, 3);
                logger.AddDoubleContext(symbol, "AdjustedLot", maxSafeLot, 3);
            }
        }
        
        // 6. Check margin
        if(!CheckMarginRequirement(symbol, lot))
        {
            Print("INSUFFICIENT_MARGIN: Cannot open ", lot, " lots for ", symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "MarginCheckFailed", "YES");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Insufficient margin", false);
            }
            return false;
        }
        
        // 7. Round lot to step size
        double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        if(stepLot > 0)
        {
            double originalLot = lot;
            lot = MathRound(lot / stepLot) * stepLot;
            
            if(loggerEnabled && logger != NULL && MathAbs(originalLot - lot) > 0.0001)
            {
                logger.AddToContext(symbol, "LotRounded", "YES");
                logger.AddDoubleContext(symbol, "RoundedLot", lot, 3);
            }
        }
        
        // 8. Prepare execution details for logging
        string executionDetails = StringFormat("Price: %s (%.5f), SL: %s (%.5f), TP: %s (%.5f)",
                                            priceSource, executionPrice,
                                            sltpSource, finalSL, 
                                            sltpSource, finalTP);
        
        bool result;
        string direction = isBuy ? "BUY" : "SELL";
        
        // 9. Execute the trade
        if(isBuy)
            result = trade.Buy(lot, symbol, 0, finalSL, finalTP, reason);
        else
            result = trade.Sell(lot, symbol, 0, finalSL, finalTP, reason);
        
        if(result)
        {
            lastDecision = StringFormat("%s %s opened: Lot=%.3f, Price=%.5f, Reason=%s", 
                                    direction, symbol, lot, executionPrice, reason);
            
            // 10. Log the trade with execution details
            if(loggerEnabled && logger != NULL)
            {
                string logMessage = direction + " opened: ";
                logMessage += StringFormat("Lot=%.3f, ", lot);
                logMessage += executionDetails;
                logMessage += ", Reason=" + reason;
                
                // Add signal usage info
                if(usingSignalPrice)
                {
                    logMessage += " [USING SIGNAL PRICE]";
                    if(!usingSignalSLTP)
                        logMessage += " [PARAMETER SL/TP]";
                }
                else
                {
                    logMessage += " [MARKET PRICE FALLBACK]";
                }
                
                logger.AddToContext(symbol, "ExecutionPrice", DoubleToString(executionPrice, 5));
                logger.AddToContext(symbol, "TradeResult", "SUCCESS");
                logger.AddToContext(symbol, "Ticket", IntegerToString(trade.ResultOrder()));
                logger.FlushContext(symbol, AUTHORIZE, "OrderManager", 
                                  logMessage, true);
            }
            
            // 11. Update RiskManager metrics if available
            if(m_riskManager != NULL)
            {
                // Use actual execution price for risk calculation
                double riskAmount = MathAbs(executionPrice - finalSL) * lot * SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
                m_riskManager.UpdatePerformanceMetrics(true, 0, riskAmount);
                
                // Record execution vs signal comparison
                if(tradeDecision.signal.isValid)
                {
                    double signalRisk = MathAbs(tradeDecision.signal.entryPrice - tradeDecision.signal.stopLoss) * 
                                    lot * SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
                    double executionDiff = riskAmount - signalRisk;
                    
                    if(MathAbs(executionDiff) > 0.01)
                    {
                        Print("EXECUTION_ADJUSTMENT: Risk changed from $", signalRisk, 
                            " to $", riskAmount, " due to price adjustment");
                    }
                }
            }
            
            dailyTradesCount++;
            
            if(loggerEnabled && logger != NULL)
            {
                logger.KeepNotes(symbol, OBSERVE, "OrderManager", 
                               StringFormat("Daily trades count incremented to %d", dailyTradesCount), 
                               false, false, 0);
            }
            
            return true;
        }
        else
        {
            int error = GetLastError();
            string errorMsg = StringFormat("Failed to open %s for %s | Lot: %.3f | Price: %.5f | Error: %d - %s", 
                                        direction, symbol, lot, executionPrice, error, GetOrderErrorDescription(error));
            Print("TRADE_FAILED: ", errorMsg);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "TradeResult", "FAILED");
                logger.AddToContext(symbol, "ErrorCode", IntegerToString(error));
                logger.AddToContext(symbol, "ErrorDescription", GetOrderErrorDescription(error));
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Trade execution failed", false);
            }
            
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| ExecuteTrade - Main trade execution method                       |
    //+------------------------------------------------------------------+
    bool ExecuteTrade(string symbol, bool isBuy, double lotSize, 
                     double stopLoss, double takeProfit, string reason = "")
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "EXECUTE_TRADE");
            logger.AddToContext(symbol, "Method", "ExecuteTrade", true);
            logger.AddToContext(symbol, "Direction", isBuy ? "BUY" : "SELL");
            logger.AddDoubleContext(symbol, "LotSize", lotSize, 3);
            logger.AddToContext(symbol, "Reason", reason);
        }
        
        // Use RiskManager for optimal stop loss and take profit if available
        if(m_riskManager != NULL && (stopLoss == 0 || takeProfit == 0))
        {
            double entryPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
            
            if(stopLoss == 0)
            {
                stopLoss = m_riskManager.GetOptimalStopLoss(symbol, entryPrice, isBuy);
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "SLFromRiskManager", "YES");
                    logger.AddDoubleContext(symbol, "RiskManagerSL", stopLoss, 5);
                }
            }
            
            if(takeProfit == 0)
            {
                takeProfit = m_riskManager.GetOptimalTakeProfit(symbol, PERIOD_H1, entryPrice, stopLoss, isBuy);
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "TPFromRiskManager", "YES");
                    logger.AddDoubleContext(symbol, "RiskManagerTP", takeProfit, 5);
                }
            }
        }
        
        bool result = TryOpenTradeWithReason(symbol, isBuy, lotSize, stopLoss, takeProfit, reason);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "FinalResult", result ? "SUCCESS" : "FAILED");
            logger.FlushContext(symbol, result ? AUTHORIZE : WARN, "OrderManager", 
                              StringFormat("ExecuteTrade %s", result ? "successful" : "failed"), 
                              result);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| ExecuteTradeWithLog - Trade execution with logging              |
    //+------------------------------------------------------------------+
    bool ExecuteTradeWithLog(string symbol, bool isBuy, double lotSize,
                            string reason = "", double stopLoss = 0, 
                            double takeProfit = 0)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "TRADE_ATTEMPT");
            logger.AddToContext(symbol, "Direction", isBuy ? "BUY" : "SELL", true);
            logger.AddDoubleContext(symbol, "LotSize", lotSize, 2);
            logger.AddToContext(symbol, "Reason", reason, true);
            
            // Add RiskManager context if available
            if(m_riskManager != NULL)
            {
                string riskLevel = RiskLevelToString(m_riskManager.GetRiskLevel());
                logger.AddToContext(symbol, "RiskLevel", riskLevel);
                logger.AddDoubleContext(symbol, "DailyPnL", m_riskManager.GetDailyPnL(), 2);
            }
            
            if(stopLoss > 0) logger.AddDoubleContext(symbol, "StopLoss", stopLoss, 5);
            if(takeProfit > 0) logger.AddDoubleContext(symbol, "TakeProfit", takeProfit, 5);
        }
        
        bool result = ExecuteTrade(symbol, isBuy, lotSize, stopLoss, takeProfit, reason);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.FlushContext(symbol, result ? AUTHORIZE : WARN, "OrderManager", 
                              "Trade " + string(result ? "executed" : "failed"), result);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| ValidateTrade - Check if trade can be executed                   |
    //+------------------------------------------------------------------+
    bool ValidateTrade(string symbol, double lotSize, 
                      double stopLoss, double takeProfit)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "TRADE_VALIDATION");
            logger.AddDoubleContext(symbol, "LotSize", lotSize, 3);
            logger.AddDoubleContext(symbol, "StopLoss", stopLoss, 5);
            logger.AddDoubleContext(symbol, "TakeProfit", takeProfit, 5);
        }
        
        // Check if symbol is tradeable
        if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
        {
            Print("ERROR: Symbol ", symbol, " not tradeable");
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "SymbolTradeable", "NO");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Symbol not tradeable", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "SymbolTradeable", "YES");
        }
        
        // Check lot size
        if(lotSize <= 0)
        {
            Print("ERROR: Invalid lot size: ", lotSize);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "LotSizeValid", "NO");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Invalid lot size", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "LotSizeValid", "YES");
        }
        
        // Check stops
        if(stopLoss <= 0 || takeProfit <= 0)
        {
            Print("WARNING: Invalid stop loss or take profit values");
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "StopsValid", "WARNING");
                logger.KeepNotes(symbol, WARN, "OrderManager", 
                               "Invalid stop loss or take profit values", 
                               false, false, 0);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "StopsValid", "YES");
            }
        }
        
        // Check RiskManager conditions if available
        if(m_riskManager != NULL)
        {
            // Check volatility
            if(!m_riskManager.IsVolatilityAcceptable(symbol))
            {
                Print("VOLATILITY_CHECK_FAILED: Market too volatile for ", symbol);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "VolatilityAcceptable", "NO");
                    logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                      "Market too volatile", false);
                }
                return false;
            }
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "VolatilityAcceptable", "YES");
            }
            
            // Check spread
            if(!m_riskManager.IsSpreadAcceptable(symbol))
            {
                Print("SPREAD_CHECK_FAILED: Spread too high for ", symbol);
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext(symbol, "SpreadAcceptable", "NO");
                    logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                      "Spread too high", false);
                }
                return false;
            }
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "SpreadAcceptable", "YES");
            }
        }
        
        // Check margin
        if(!CheckMarginRequirement(symbol, lotSize))
        {
            Print("MARGIN_CHECK_FAILED for ", symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "MarginSufficient", "NO");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Insufficient margin", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "MarginSufficient", "YES");
            logger.AddToContext(symbol, "ValidationResult", "PASSED");
            logger.FlushContext(symbol, AUTHORIZE, "OrderManager", 
                              "Trade validation passed", false);
        }
        
        return true;
    }
    
    // ============ POSITION CLOSING ============
    
    //+------------------------------------------------------------------+
    //| CloseAllTradesForSymbol - Close all positions for a symbol      |
    //+------------------------------------------------------------------+
    void CloseAllTradesForSymbol(string symbol, string reason = "Manual close")
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "CLOSE_ALL_TRADES");
            logger.AddToContext(symbol, "Reason", reason, true);
        }
        
        int closedCount = 0;
        double totalProfit = 0;
        string closedTickets = "";
        
        // ============ 1. COLLECT AND CLOSE POSITIONS ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                
                if(positionSymbol == symbol)
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    if(trade.PositionClose(ticket))
                    {
                        closedCount++;
                        totalProfit += profit;
                        closedTickets += (closedTickets == "" ? "" : ", ") + IntegerToString(ticket);
                        Print("CLOSED: Position ", ticket, " for ", symbol);
                        
                        // Log individual closure
                        if(loggerEnabled && logger != NULL)
                        {
                            logger.AddToContext(symbol, "ClosedTicket" + IntegerToString(closedCount), IntegerToString(ticket));
                            logger.AddDoubleContext(symbol, "TicketProfit" + IntegerToString(closedCount), profit, 2);
                        }
                        
                        // Update RiskManager metrics if available
                        if(m_riskManager != NULL)
                        {
                            m_riskManager.UpdatePerformanceMetrics((profit > 0), profit, 0);
                        }
                    }
                    else
                    {
                        Print("FAILED to close position ", ticket, 
                              " for ", symbol, " - Error: ", GetLastError());
                        
                        if(loggerEnabled && logger != NULL)
                        {
                            logger.AddToContext(symbol, "FailedTicket", IntegerToString(ticket));
                            logger.AddToContext(symbol, "Error", IntegerToString(GetLastError()));
                        }
                    }
                }
            }
        }
        
        // ============ 2. POST-CLOSURE PROCESSING ============
        if(closedCount > 0)
        {
            Print("SUMMARY: Closed ", closedCount, " position(s) for ", symbol, 
                  " | Tickets: ", closedTickets, " | Total Profit: $", DoubleToString(totalProfit, 2));
            
            // Log the closure
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "TotalClosed", IntegerToString(closedCount));
                logger.AddDoubleContext(symbol, "TotalProfit", totalProfit, 2);
                logger.AddToContext(symbol, "ClosedTickets", closedTickets);
                logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                  StringFormat("Closed %d positions: %s", closedCount, reason), 
                                  true);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                                  "No positions found to close", false);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| ClosePositionType - Close specific type of positions            |
    //+------------------------------------------------------------------+
    void ClosePositionType(string symbol, int positionType = -1, string reason = "Type close")
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "CLOSE_POSITION_TYPE");
            string directionText = positionType == -1 ? "ALL" : 
                                  (positionType == POSITION_TYPE_BUY ? "BUY" : "SELL");
            logger.AddToContext(symbol, "CloseType", directionText, true);
            logger.AddToContext(symbol, "Reason", reason);
        }
        
        int closedCount = 0;
        double totalProfit = 0;
        string directionText = positionType == -1 ? "ALL" : 
                              (positionType == POSITION_TYPE_BUY ? "BUY" : "SELL");
        
        // ============ 1. CLOSE SPECIFIED POSITION TYPE ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string positionSymbol = PositionGetString(POSITION_SYMBOL);
                int currentType = (int)PositionGetInteger(POSITION_TYPE);
                
                if(positionSymbol == symbol && 
                   (positionType == -1 || currentType == positionType))
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    if(trade.PositionClose(ticket))
                    {
                        closedCount++;
                        totalProfit += profit;
                        Print("CLOSED: ", GetDirectionText(currentType), 
                              " position ", ticket, " for ", symbol);
                        
                        if(loggerEnabled && logger != NULL)
                        {
                            logger.AddToContext(symbol, "ClosedTicket" + IntegerToString(closedCount), 
                                              GetDirectionText(currentType) + ":" + IntegerToString(ticket));
                            logger.AddDoubleContext(symbol, "TicketProfit" + IntegerToString(closedCount), profit, 2);
                        }
                        
                        // Update RiskManager metrics if available
                        if(m_riskManager != NULL)
                        {
                            m_riskManager.UpdatePerformanceMetrics((profit > 0), profit, 0);
                        }
                    }
                    else
                    {
                        Print("FAILED to close ", GetDirectionText(currentType), 
                              " position ", ticket, " - Error: ", GetLastError());
                        
                        if(loggerEnabled && logger != NULL)
                        {
                            logger.AddToContext(symbol, "FailedTicket", 
                                              GetDirectionText(currentType) + ":" + IntegerToString(ticket));
                        }
                    }
                }
            }
        }
        
        // ============ 2. POST-CLOSURE PROCESSING ============
        if(closedCount > 0)
        {
            Print("SUMMARY: Closed ", closedCount, " ", directionText, 
                  " position(s) for ", symbol, " | Total Profit: $", DoubleToString(totalProfit, 2));
            
            // Log the closure
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "TotalClosed", IntegerToString(closedCount));
                logger.AddDoubleContext(symbol, "TotalProfit", totalProfit, 2);
                logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                  StringFormat("Closed %d %s positions: %s", closedCount, directionText, reason), 
                                  true);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                                  StringFormat("No %s positions found to close", directionText), 
                                  false);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| CloseBiggestLosingPosition - Close position with biggest loss   |
    //+------------------------------------------------------------------+
    bool CloseBiggestLosingPosition(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_BIGGEST_LOSER");
        }
        
        Print("=== CLOSE BIGGEST LOSING POSITION START ===");
        
        double biggestLoss = DBL_MAX;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        bool foundLoss = false;
        
        // ============ 1. FIND BIGGEST LOSING POSITION ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                
                // ONLY consider LOSING positions (profit < 0)
                if(profit < 0)
                {
                    foundLoss = true;
                    
                    // Compare losses: -50 is WORSE than -10 (more negative)
                    if(profit < biggestLoss)
                    {
                        biggestLoss = profit;
                        ticketToClose = ticket;
                        symbolToClose = symbol;
                    }
                }
            }
        }
        
        // ============ 2. CHECK IF WE SHOULD CLOSE ============
        if(!foundLoss)
        {
            Print("No losing positions found. Nothing to close.");
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "FoundLosingPosition", "NO");
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                  "No losing positions found", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "FoundLosingPosition", "YES");
            logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
            logger.AddDoubleContext("SYSTEM", "BiggestLoss", biggestLoss, 2);
            logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticketToClose));
        }
        
        // ============ 3. CLOSE THE POSITION ============
        Print("Attempting to close biggest losing position: ", symbolToClose);
        
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("SUCCESS: Closed biggest losing position");
            Print("  Symbol: ", symbolToClose);
            Print("  Loss: $", DoubleToString(biggestLoss, 2));
            
            // Log the closure
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "SUCCESS");
                logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                  StringFormat("Closed biggest losing position: %s, Loss $%.2f", 
                                              symbolToClose, biggestLoss), 
                                  true);
            }
            
            // Update RiskManager metrics if available
            if(m_riskManager != NULL)
            {
                m_riskManager.UpdatePerformanceMetrics(false, biggestLoss, 0);
            }
            
            // Optional: Add delay to prevent immediate re-entry
            Sleep(100);
        }
        else
        {
            Print("FAILED: Could not close position ", ticketToClose);
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "FAILED");
                logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "Failed to close biggest losing position", false);
            }
        }
        
        Print("=== CLOSE BIGGEST LOSING POSITION END ===");
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| CloseSmallestProfitPosition - Close position with smallest gain |
    //+------------------------------------------------------------------+
    bool CloseSmallestProfitPosition(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_SMALLEST_PROFIT");
        }
        
        Print("=== CLOSE SMALLEST PROFIT POSITION START ===");
        
        double smallestProfit = DBL_MAX;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        bool foundPosition = false;
        
        // ============ 1. FIND POSITION WITH SMALLEST PROFIT ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                
                // Consider ALL positions (profit or loss)
                foundPosition = true;
                
                // Compare absolute profit value (smallest = closest to zero)
                if(MathAbs(profit) < MathAbs(smallestProfit))
                {
                    smallestProfit = profit;
                    ticketToClose = ticket;
                    symbolToClose = symbol;
                }
            }
        }
        
        // ============ 2. CHECK IF WE SHOULD CLOSE ============
        if(!foundPosition)
        {
            Print("No positions found. Nothing to close.");
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "FoundPosition", "NO");
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                  "No positions found", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "FoundPosition", "YES");
            logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
            logger.AddDoubleContext("SYSTEM", "SmallestProfit", smallestProfit, 2);
            logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticketToClose));
        }
        
        // ============ 3. CLOSE THE POSITION ============
        Print("Closing smallest profit position: ", symbolToClose);
        
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("SUCCESS: Closed smallest profit position");
            Print("  Symbol: ", symbolToClose);
            Print("  Profit: $", DoubleToString(smallestProfit, 2));
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "SUCCESS");
                string msg = "Closed smallest ";
                msg += (smallestProfit >= 0 ? "winning" : "losing");
                msg += " position";
                
                logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                  msg, true);
                
                // Detailed log
                logger.KeepNotes(symbolToClose, ENFORCE, "OrderManager",
                                StringFormat("Closed smallest %s position: $%.2f",
                                           (smallestProfit >= 0 ? "winning" : "losing"), 
                                           smallestProfit),
                                true, smallestProfit >= 0, smallestProfit);
            }
            
            // Update RiskManager metrics if available
            if(m_riskManager != NULL)
            {
                m_riskManager.UpdatePerformanceMetrics((smallestProfit >= 0), smallestProfit, 0);
            }
        }
        else
        {
            Print("FAILED: Could not close position ", ticketToClose);
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "FAILED");
                logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "Failed to close smallest profit position", false);
            }
        }
        
        Print("=== CLOSE SMALLEST PROFIT POSITION END ===");
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| CloseSmallestWinFirst - Complete version                         |
    //| Closes the smallest WINNING position first                       |
    //+------------------------------------------------------------------+
    bool CloseSmallestWinFirst(string &outClosedSymbol, double minProfit = 0.01)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_SMALLEST_WIN");
            logger.AddDoubleContext("SYSTEM", "MinProfit", minProfit, 2);
        }
        
        Print("=== CLOSE SMALLEST WIN FIRST ===");
        
        double smallestWin = DBL_MAX;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        bool foundWin = false;
        
        // ============ 1. FIND SMALLEST WINNING POSITION ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                
                // Only consider WINNING positions above minimum
                if(profit >= minProfit)
                {
                    foundWin = true;
                    
                    // Find smallest winning position
                    if(profit < smallestWin)
                    {
                        smallestWin = profit;
                        ticketToClose = ticket;
                        symbolToClose = symbol;
                    }
                }
            }
        }
        
        // ============ 2. FALLBACK TO SMALLEST LOSS IF NO WINS ============
        if(!foundWin)
        {
            Print("No winning positions found. Checking losses...");
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "WinningPositionsFound", "NO");
                logger.AddToContext("SYSTEM", "FallbackToLoss", "YES");
            }
            
            return CloseSmallestLossFirst(outClosedSymbol);
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "WinningPositionsFound", "YES");
            logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
            logger.AddDoubleContext("SYSTEM", "SmallestWin", smallestWin, 2);
            logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticketToClose));
        }
        
        // ============ 3. CLOSE THE POSITION ============
        Print("Closing smallest win: ", symbolToClose);
        
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("SUCCESS: Closed smallest winning position");
            Print("  Symbol: ", symbolToClose);
            Print("  Profit: $", DoubleToString(smallestWin, 2));
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "SUCCESS");
                logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                  StringFormat("Closed smallest win: %s, $%.2f", 
                                              symbolToClose, smallestWin), 
                                  true);
            }
            
            // Update RiskManager metrics if available
            if(m_riskManager != NULL)
            {
                m_riskManager.UpdatePerformanceMetrics(true, smallestWin, 0);
            }
        }
        else
        {
            Print("FAILED: Could not close position ", ticketToClose);
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "FAILED");
                logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "Failed to close smallest win", false);
            }
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| CloseSmallestLossFirst - Complete version                        |
    //| Closes the smallest LOSS first (least negative)                  |
    //+------------------------------------------------------------------+
    bool CloseSmallestLossFirst(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_SMALLEST_LOSS");
        }
        
        Print("=== CLOSE SMALLEST LOSS FIRST ===");
        
        double smallestLoss = 0;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        bool foundLoss = false;
        
        // ============ 1. FIND SMALLEST LOSS ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                
                // Only consider LOSING positions
                if(profit < 0)
                {
                    foundLoss = true;
                    
                    // Find least negative loss (closest to zero)
                    if(profit > smallestLoss)
                    {
                        smallestLoss = profit;
                        ticketToClose = ticket;
                        symbolToClose = symbol;
                    }
                }
            }
        }
        
        // ============ 2. CHECK IF WE SHOULD CLOSE ============
        if(!foundLoss)
        {
            Print("No losing positions found.");
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "LosingPositionsFound", "NO");
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                  "No losing positions found", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "LosingPositionsFound", "YES");
            logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
            logger.AddDoubleContext("SYSTEM", "SmallestLoss", smallestLoss, 2);
            logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticketToClose));
        }
        
        // ============ 3. CLOSE THE POSITION ============
        Print("Closing smallest loss: ", symbolToClose);
        
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("SUCCESS: Closed smallest losing position");
            Print("  Symbol: ", symbolToClose);
            Print("  Loss: $", DoubleToString(smallestLoss, 2));
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "SUCCESS");
                logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                  StringFormat("Closed smallest loss: %s, $%.2f", 
                                              symbolToClose, smallestLoss), 
                                  true);
            }
            
            // Update RiskManager metrics if available
            if(m_riskManager != NULL)
            {
                m_riskManager.UpdatePerformanceMetrics(false, smallestLoss, 0);
            }
        }
        else
        {
            Print("FAILED: Could not close position ", ticketToClose);
            outClosedSymbol = "";
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "CloseResult", "FAILED");
                logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "Failed to close smallest loss", false);
            }
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| Smart Close Position - Decision based on strategy                |
    //+------------------------------------------------------------------+
    bool SmartClosePosition(string &outClosedSymbol, ENUM_CLOSE_PRIORITY priority = CLOSE_SMALLEST_PROFIT)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "SMART_CLOSE");
            string priorityStr;
            switch(priority)
            {
                case CLOSE_SMALLEST_PROFIT: priorityStr = "SMALLEST_PROFIT"; break;
                case CLOSE_BIGGEST_LOSS: priorityStr = "BIGGEST_LOSS"; break;
                case CLOSE_SMALLEST_LOSS: priorityStr = "SMALLEST_LOSS"; break;
                case CLOSE_OLDEST: priorityStr = "OLDEST"; break;
                case CLOSE_NEWEST: priorityStr = "NEWEST"; break;
            }
            logger.AddToContext("SYSTEM", "Priority", priorityStr, true);
        }
        
        bool result = false;
        
        switch(priority)
        {
            case CLOSE_SMALLEST_PROFIT:
                result = CloseSmallestProfitPosition(outClosedSymbol);
                break;
            
            case CLOSE_BIGGEST_LOSS:
                result = CloseBiggestLosingPosition(outClosedSymbol);
                break;
            
            case CLOSE_SMALLEST_LOSS:
                result = CloseSmallestLossFirst(outClosedSymbol);
                break;
            
            case CLOSE_OLDEST:
                result = CloseOldestPosition(outClosedSymbol);
                break;
            
            case CLOSE_NEWEST:
                result = CloseNewestPosition(outClosedSymbol);
                break;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "Result", result ? "SUCCESS" : "FAILED");
            if(result)
                logger.AddToContext("SYSTEM", "ClosedSymbol", outClosedSymbol);
            logger.FlushContext("SYSTEM", result ? ENFORCE : WARN, "OrderManager", 
                              StringFormat("Smart close %s", result ? "successful" : "failed"), 
                              result);
        }
        
        if(!result) outClosedSymbol = "";
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| Get Folding Recommendation - Which position to close for folding |
    //+------------------------------------------------------------------+
    ENUM_CLOSE_PRIORITY GetFoldingRecommendation()
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "FOLDING_RECOMMENDATION");
        }
        
        int totalPositions = PositionsTotal();
        int winningPositions = 0;
        int losingPositions = 0;
        double totalProfit = 0;
        
        // Analyze current positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                totalProfit += profit;
                
                if(profit >= 0)
                    winningPositions++;
                else
                    losingPositions++;
            }
        }
        
        Print("Folding Analysis: Total=", totalPositions, 
              " | Wins=", winningPositions, 
              " | Losses=", losingPositions,
              " | Total Profit=$", DoubleToString(totalProfit, 2));
        
        // Check RiskManager's risk level for guidance
        string riskLevel = "MODERATE";
        if(m_riskManager != NULL)
        {
            riskLevel = RiskLevelToString(m_riskManager.GetRiskLevel());
            Print("Current Risk Level: ", riskLevel);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "RiskLevel", riskLevel);
            }
        }
        
        ENUM_CLOSE_PRIORITY recommendation;
        
        // Decision logic with RiskManager consideration
        if(riskLevel == "CRITICAL" || riskLevel == "HIGH")
        {
            // High risk level - close biggest loss to reduce exposure
            Print("Recommendation: CLOSE_BIGGEST_LOSS (high risk level: ", riskLevel, ")");
            recommendation = CLOSE_BIGGEST_LOSS;
        }
        else if(totalProfit >= 0)
        {
            // Overall profitable - close smallest win to preserve capital
            Print("Recommendation: CLOSE_SMALLEST_PROFIT (portfolio is green)");
            recommendation = CLOSE_SMALLEST_PROFIT;
        }
        else if(losingPositions)
        {
            // Mostly losing - close smallest loss to reduce damage
            Print("Recommendation: CLOSE_SMALLEST_LOSS (mostly losing positions)");
            recommendation = CLOSE_SMALLEST_LOSS;
        }
        else
        {
            // Mixed or mostly winning but overall loss - close biggest loss
            Print("Recommendation: CLOSE_BIGGEST_LOSS (mixed but overall loss)");
            recommendation = CLOSE_BIGGEST_LOSS;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "TotalPositions", IntegerToString(totalPositions));
            logger.AddToContext("SYSTEM", "WinningPositions", IntegerToString(winningPositions));
            logger.AddToContext("SYSTEM", "LosingPositions", IntegerToString(losingPositions));
            logger.AddDoubleContext("SYSTEM", "TotalProfit", totalProfit, 2);
            
            string recStr;
            switch(recommendation)
            {
                case CLOSE_SMALLEST_PROFIT: recStr = "CLOSE_SMALLEST_PROFIT"; break;
                case CLOSE_BIGGEST_LOSS: recStr = "CLOSE_BIGGEST_LOSS"; break;
                case CLOSE_SMALLEST_LOSS: recStr = "CLOSE_SMALLEST_LOSS"; break;
                case CLOSE_OLDEST: recStr = "CLOSE_OLDEST"; break;
                case CLOSE_NEWEST: recStr = "CLOSE_NEWEST"; break;
            }
            logger.AddToContext("SYSTEM", "Recommendation", recStr);
            logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                              "Folding recommendation generated", false);
        }
        
        return recommendation;
    }
    
    //+------------------------------------------------------------------+
    //| CloseSmallestPosition - Close position with smallest volume     |
    //+------------------------------------------------------------------+
    bool CloseSmallestPosition(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_SMALLEST_POSITION");
        }
        
        double smallestVolume = DBL_MAX;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        
        // ============ 1. FIND SMALLEST POSITION ============
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                if(volume < smallestVolume)
                {
                    smallestVolume = volume;
                    ticketToClose = ticket;
                    symbolToClose = PositionGetString(POSITION_SYMBOL);
                }
            }
        }
        
        // ============ 2. CLOSE THE POSITION ============
        if(ticketToClose > 0)
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            bool result = trade.PositionClose(ticketToClose);
            
            if(result)
            {
                outClosedSymbol = symbolToClose;
                
                Print("CLOSED: Smallest position for ", symbolToClose,
                      " | Volume: ", DoubleToString(smallestVolume, 2),
                      " | Ticket: ", ticketToClose,
                      " | Profit: $", DoubleToString(profit, 2));
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
                    logger.AddDoubleContext("SYSTEM", "Volume", smallestVolume, 2);
                    logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticketToClose));
                    logger.AddDoubleContext("SYSTEM", "Profit", profit, 2);
                    logger.AddToContext("SYSTEM", "Result", "SUCCESS");
                    logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                      "Closed smallest position", true);
                }
                
                // Update RiskManager metrics if available
                if(m_riskManager != NULL)
                {
                    m_riskManager.UpdatePerformanceMetrics((profit > 0), profit, 0);
                }
            }
            else
            {
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Result", "FAILED");
                    logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                    logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                      "Failed to close smallest position", false);
                }
            }
            
            return result;
        }
        
        outClosedSymbol = "";
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "Result", "NO_POSITIONS");
            logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                              "No positions found to close", false);
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| CloseOldestPosition - Close position opened earliest            |
    //+------------------------------------------------------------------+
    bool CloseOldestPosition(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_OLDEST");
        }
        
        datetime oldestTime = D'3000.01.01';
        ulong ticketToClose = 0;
        string symbolToClose = "";
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                
                if(openTime < oldestTime)
                {
                    oldestTime = openTime;
                    ticketToClose = ticket;
                    symbolToClose = PositionGetString(POSITION_SYMBOL);
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            bool result = trade.PositionClose(ticketToClose);
            
            if(result)
            {
                outClosedSymbol = symbolToClose;
                Print("Closed oldest position: ", symbolToClose, 
                      " | Opened: ", TimeToString(oldestTime),
                      " | Profit: $", DoubleToString(profit, 2));
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
                    logger.AddToContext("SYSTEM", "OpenTime", TimeToString(oldestTime));
                    logger.AddDoubleContext("SYSTEM", "Profit", profit, 2);
                    logger.AddToContext("SYSTEM", "Result", "SUCCESS");
                    logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                      "Closed oldest position", true);
                }
                
                // Update RiskManager metrics if available
                if(m_riskManager != NULL)
                {
                    m_riskManager.UpdatePerformanceMetrics((profit > 0), profit, 0);
                }
            }
            else
            {
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Result", "FAILED");
                    logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                    logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                      "Failed to close oldest position", false);
                }
            }
            
            return result;
        }
        
        outClosedSymbol = "";
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "Result", "NO_POSITIONS");
            logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                              "No positions found to close", false);
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| CloseNewestPosition - Close position opened most recently       |
    //+------------------------------------------------------------------+
    bool CloseNewestPosition(string &outClosedSymbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "CLOSE_NEWEST");
        }
        
        datetime newestTime = 0;
        ulong ticketToClose = 0;
        string symbolToClose = "";
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                
                if(openTime > newestTime)
                {
                    newestTime = openTime;
                    ticketToClose = ticket;
                    symbolToClose = PositionGetString(POSITION_SYMBOL);
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            bool result = trade.PositionClose(ticketToClose);
            
            if(result)
            {
                outClosedSymbol = symbolToClose;
                Print("Closed newest position: ", symbolToClose, 
                      " | Opened: ", TimeToString(newestTime),
                      " | Profit: $", DoubleToString(profit, 2));
                
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Symbol", symbolToClose);
                    logger.AddToContext("SYSTEM", "OpenTime", TimeToString(newestTime));
                    logger.AddDoubleContext("SYSTEM", "Profit", profit, 2);
                    logger.AddToContext("SYSTEM", "Result", "SUCCESS");
                    logger.FlushContext("SYSTEM", ENFORCE, "OrderManager", 
                                      "Closed newest position", true);
                }
                
                // Update RiskManager metrics if available
                if(m_riskManager != NULL)
                {
                    m_riskManager.UpdatePerformanceMetrics((profit > 0), profit, 0);
                }
            }
            else
            {
                if(loggerEnabled && logger != NULL)
                {
                    logger.AddToContext("SYSTEM", "Result", "FAILED");
                    logger.AddToContext("SYSTEM", "Error", IntegerToString(GetLastError()));
                    logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                      "Failed to close newest position", false);
                }
            }
            
            return result;
        }
        
        outClosedSymbol = "";
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext("SYSTEM", "Result", "NO_POSITIONS");
            logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                              "No positions found to close", false);
        }
        
        return false;
    }
    
    // ============ RISK MANAGER INTEGRATION FUNCTIONS ============
    
    //+------------------------------------------------------------------+
    //| SecureProfits - Use RiskManager's profit securing logic         |
    //+------------------------------------------------------------------+
    void SecureProfits()
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "SECURE_PROFITS");
        }
        
        if(m_riskManager != NULL)
        {
            int securedCount = 0;
            double totalSecuredProfit = 0;
            
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(PositionSelectByTicket(ticket))
                {
                    string symbol = PositionGetString(POSITION_SYMBOL);
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    
                    // Use RiskManager's profit securing logic for profitable positions
                    if(profit > 0)
                    {
                        // If SecureProfit returns void, we can't check its return value
                        m_riskManager.SecureProfit(ticket);
                        
                        // You'll need alternative logic to determine if profit was secured
                        // For example, check if position still exists or profit changed
                        securedCount++;
                        totalSecuredProfit += profit;
                        
                        if(loggerEnabled && logger != NULL)
                        {
                            logger.AddToContext("SYSTEM", "SecuredTicket" + IntegerToString(securedCount), 
                                            symbol + ":" + IntegerToString(ticket));
                            logger.AddDoubleContext("SYSTEM", "SecuredProfit" + IntegerToString(securedCount), 
                                                profit, 2);
                        }
                    }
                }
            }
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "TotalSecured", IntegerToString(securedCount));
                logger.AddDoubleContext("SYSTEM", "TotalSecuredProfit", totalSecuredProfit, 2);
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                  StringFormat("Secured profits on %d positions", securedCount), 
                                  false);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "RiskManager not available for profit securing", 
                                  false);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| ApplyTrailingStops - Use RiskManager's trailing stop logic      |
    //+------------------------------------------------------------------+
    void ApplyTrailingStops()
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "APPLY_TRAILING_STOPS");
        }
        
        if(m_riskManager != NULL)
        {
            // Just call it, don't store the return value
            m_riskManager.UpdateTrailingStops();
            
            if(loggerEnabled && logger != NULL)
            {
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                "Trailing stops updated", 
                                false);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                "RiskManager not available for trailing stops", 
                                false);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| MoveToBreakeven - Use RiskManager's breakeven logic             |
    //+------------------------------------------------------------------+
    bool MoveToBreakeven(ulong ticket, double minProfitPips = 10.0)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "MOVE_TO_BREAKEVEN");
            logger.AddToContext("SYSTEM", "Ticket", IntegerToString(ticket));
            logger.AddDoubleContext("SYSTEM", "MinProfitPips", minProfitPips, 1);
        }
        
        bool result = false;
        
        if(m_riskManager != NULL)
        {
            result = m_riskManager.MoveToBreakevenWithProfitCheck(ticket, minProfitPips);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "Result", result ? "SUCCESS" : "FAILED");
                logger.FlushContext("SYSTEM", result ? AUTHORIZE : WARN, "OrderManager", 
                                  StringFormat("Move to breakeven %s", result ? "successful" : "failed"), 
                                  false);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "Result", "NO_RISKMANAGER");
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "RiskManager not available for breakeven move", 
                                  false);
            }
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| GetRiskAdjustedPositionSize - Use RiskManager for sizing        |
    //+------------------------------------------------------------------+
    double GetRiskAdjustedPositionSize(string symbol, double baseLots, 
                                       double stopLoss, ENUM_POSITION_TYPE direction)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "RISK_ADJUSTED_SIZE");
            logger.AddDoubleContext(symbol, "BaseLots", baseLots, 3);
            logger.AddDoubleContext(symbol, "StopLoss", stopLoss, 5);
            logger.AddToContext(symbol, "Direction", direction == POSITION_TYPE_BUY ? "BUY" : "SELL");
        }
        
        double result = baseLots;
        
        if(m_riskManager != NULL)
        {
            result = m_riskManager.CalculateRiskAdjustedSize(symbol, baseLots, stopLoss, direction);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddDoubleContext(symbol, "AdjustedLots", result, 3);
                logger.AddToContext(symbol, "AdjustmentApplied", "YES");
                logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                                  "Risk-adjusted position size calculated", 
                                  false);
            }
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "AdjustmentApplied", "NO");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "RiskManager not available for size adjustment", 
                                  false);
            }
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| CalculatePositionSizeWithRiskManager - Advanced sizing          |
    //+------------------------------------------------------------------+
    double CalculatePositionSizeWithRiskManager(string symbol, double stopLossPips)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "ADVANCED_SIZE_CALC");
            logger.AddDoubleContext(symbol, "StopLossPips", stopLossPips, 1);
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            logger.AddDoubleContext(symbol, "AccountBalance", balance, 2);
        }
        
        double result = 0;
        
        if(m_riskManager != NULL)
        {
            result = m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                symbol, AccountInfoDouble(ACCOUNT_BALANCE), stopLossPips);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddDoubleContext(symbol, "CalculatedLots", result, 3);
                logger.AddToContext(symbol, "CalculationMethod", "RISKMANAGER");
                logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                                  "Advanced position size calculated", 
                                  false);
            }
        }
        else
        {
            result = CalculateMaxSafeLotSize(symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddDoubleContext(symbol, "CalculatedLots", result, 3);
                logger.AddToContext(symbol, "CalculationMethod", "MAX_SAFE_LOT");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Using max safe lot (RiskManager not available)", 
                                  false);
            }
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| GetCurrentRiskLevel - Get risk level from RiskManager           |
    //+------------------------------------------------------------------+
    string GetCurrentRiskLevel()
    {
        string riskLevel = "UNKNOWN";
        
        if(m_riskManager != NULL)
        {
            riskLevel = RiskLevelToString(m_riskManager.GetRiskLevel());
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", OBSERVE, "OrderManager", 
                           "Current risk level: " + riskLevel, 
                           false, false, 0);
        }
        
        return riskLevel;
    }
    
    //+------------------------------------------------------------------+
    //| CheckTradingPermission - Check if trading is allowed            |
    //+------------------------------------------------------------------+
    bool CheckTradingPermission()
    {
        bool result = true;
        
        if(m_riskManager != NULL)
        {
            result = m_riskManager.CanOpenNewTrades();
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.KeepNotes("SYSTEM", result ? AUTHORIZE : ENFORCE, "OrderManager", 
                           StringFormat("Trading permission: %s", result ? "GRANTED" : "DENIED"), 
                           false, false, 0);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| PrintRiskStatus - Display RiskManager status                    |
    //+------------------------------------------------------------------+
    void PrintRiskStatus()
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith("SYSTEM", "RISK_STATUS");
        }
        
        if(m_riskManager != NULL)
        {
            m_riskManager.PrintRiskStatus();
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "RiskManagerStatus", "AVAILABLE");
                logger.FlushContext("SYSTEM", OBSERVE, "OrderManager", 
                                  "RiskManager status printed", false);
            }
        }
        else
        {
            Print("RiskManager not attached to OrderManager");
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext("SYSTEM", "RiskManagerStatus", "NOT_ATTACHED");
                logger.FlushContext("SYSTEM", WARN, "OrderManager", 
                                  "RiskManager not attached", false);
            }
        }
    }
    
    // ============ UTILITY FUNCTIONS ============
    
    //+------------------------------------------------------------------+
    //| CheckMarginRequirement - Validate margin                         |
    //+------------------------------------------------------------------+
    bool CheckMarginRequirement(string symbol, double lotSize)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "MARGIN_CHECK");
            logger.AddDoubleContext(symbol, "LotSize", lotSize, 3);
        }
        
        double marginRequired = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL) * lotSize;
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddDoubleContext(symbol, "MarginRequired", marginRequired, 2);
            logger.AddDoubleContext(symbol, "FreeMargin", freeMargin, 2);
            logger.AddDoubleContext(symbol, "SafetyBuffer", marginSafetyBuffer * 100, 0);
        }
        
        // Safety buffer: use max 80% of free margin
        if(marginRequired > freeMargin * marginSafetyBuffer)
        {
            Print("MARGIN_INSUFFICIENT: Required $", DoubleToString(marginRequired, 2), 
                  ", Available $", DoubleToString(freeMargin, 2));
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "CheckResult", "FAILED");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Insufficient margin", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "CheckResult", "PASSED");
            logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                              "Margin check passed", false);
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| CalculateMaxSafeLotSize - Calculate maximum safe lot size        |
    //+------------------------------------------------------------------+
    double CalculateMaxSafeLotSize(string symbol)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "MAX_SAFE_LOT");
        }
        
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double marginPerLot = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        
        if(marginPerLot <= 0) 
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "Calculation", "FAILED");
                logger.AddToContext(symbol, "Reason", "Invalid margin per lot");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Failed to calculate max safe lot", false);
            }
            return 0;
        }
        
        double maxLotsByMargin = (freeMargin * marginSafetyBuffer) / marginPerLot;
        
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        maxLotsByMargin = MathMax(minLot, MathMin(maxLotsByMargin, maxLot));
        
        if(lotStep > 0)
            maxLotsByMargin = MathRound(maxLotsByMargin / lotStep) * lotStep;
        
        double result = NormalizeDouble(maxLotsByMargin, 2);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddDoubleContext(symbol, "FreeMargin", freeMargin, 2);
            logger.AddDoubleContext(symbol, "MarginPerLot", marginPerLot, 2);
            logger.AddDoubleContext(symbol, "MinLot", minLot, 2);
            logger.AddDoubleContext(symbol, "MaxLot", maxLot, 2);
            logger.AddDoubleContext(symbol, "LotStep", lotStep, 2);
            logger.AddDoubleContext(symbol, "MaxSafeLot", result, 3);
            logger.AddToContext(symbol, "Calculation", "SUCCESS");
            logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                              "Max safe lot calculated", false);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| ApplySafetyLimits - Apply safety limits to trade                 |
    //+------------------------------------------------------------------+
    bool ApplySafetyLimits(string symbol, double &lotSize)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "APPLY_SAFETY_LIMITS");
            logger.AddDoubleContext(symbol, "OriginalLotSize", lotSize, 3);
        }
        
        // ============ 1. CHECK MARGIN ============
        if(!CheckMarginRequirement(symbol, lotSize))
        {
            Print("MARGIN CHECK FAILED for ", symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "MarginCheck", "FAILED");
                logger.FlushContext(symbol, WARN, "OrderManager", 
                                  "Margin check failed", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "MarginCheck", "PASSED");
        }
        
        // ============ 2. ADJUST LOT SIZE TO SAFE LIMIT ============
        double maxSafeLot = CalculateMaxSafeLotSize(symbol);
        
        if(lotSize > maxSafeLot)
        {
            Print("LOT_SIZE_ADJUSTED: Reduced from ", lotSize, 
                  " to ", maxSafeLot, " for ", symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "LotSizeAdjusted", "YES");
                logger.AddDoubleContext(symbol, "MaxSafeLot", maxSafeLot, 3);
            }
            lotSize = maxSafeLot;
        }
        else
        {
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "LotSizeAdjusted", "NO");
            }
        }
        
        // ============ 3. CHECK MAX TRADES PER SYMBOL ============
        int openTrades = CountOpenTrades(symbol);
        if(openTrades >= MaxTradesPerSymbol)
        {
            Print("MAX_TRADES_REACHED: ", openTrades, 
                  " trades already open for ", symbol);
            
            if(loggerEnabled && logger != NULL)
            {
                logger.AddToContext(symbol, "MaxTradesCheck", "FAILED");
                logger.AddToContext(symbol, "OpenTrades", IntegerToString(openTrades));
                logger.AddToContext(symbol, "MaxTrades", IntegerToString(MaxTradesPerSymbol));
                logger.FlushContext(symbol, ENFORCE, "OrderManager", 
                                  "Max trades per symbol reached", false);
            }
            return false;
        }
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddToContext(symbol, "MaxTradesCheck", "PASSED");
            logger.AddToContext(symbol, "OpenTrades", IntegerToString(openTrades));
            logger.AddDoubleContext(symbol, "FinalLotSize", lotSize, 3);
            logger.AddToContext(symbol, "SafetyLimitsResult", "PASSED");
            logger.FlushContext(symbol, AUTHORIZE, "OrderManager", 
                              "Safety limits applied successfully", false);
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| AdjustLotSizeToConstraints - Adjust lot size to symbol limits   |
    //+------------------------------------------------------------------+
    double AdjustLotSizeToConstraints(string symbol, double lotSize)
    {
        if(loggerEnabled && logger != NULL)
        {
            logger.StartContextWith(symbol, "ADJUST_LOT_CONSTRAINTS");
            logger.AddDoubleContext(symbol, "InputLotSize", lotSize, 3);
        }
        
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddDoubleContext(symbol, "MinLot", minLot, 3);
            logger.AddDoubleContext(symbol, "MaxLot", maxLot, 3);
            logger.AddDoubleContext(symbol, "LotStep", lotStep, 3);
        }
        
        // Apply minimum and maximum
        double originalLot = lotSize;
        lotSize = MathMax(lotSize, minLot);
        lotSize = MathMin(lotSize, maxLot);
        
        // Adjust to lot step
        if(lotStep > 0)
        {
            lotSize = MathRound(lotSize / lotStep) * lotStep;
        }
        
        double result = NormalizeDouble(lotSize, 2);
        
        if(loggerEnabled && logger != NULL)
        {
            logger.AddDoubleContext(symbol, "OutputLotSize", result, 3);
            
            if(MathAbs(originalLot - result) > 0.0001)
            {
                logger.AddToContext(symbol, "AdjustmentMade", "YES");
                logger.AddDoubleContext(symbol, "AdjustmentDelta", result - originalLot, 3);
            }
            else
            {
                logger.AddToContext(symbol, "AdjustmentMade", "NO");
            }
            
            logger.FlushContext(symbol, OBSERVE, "OrderManager", 
                              "Lot size adjusted to constraints", false);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| CountOpenTrades - Count open trades for symbol                  |
    //+------------------------------------------------------------------+
    int CountOpenTrades(string symbol = "")
    {
        int count = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                if(symbol == "" || PositionGetString(POSITION_SYMBOL) == symbol)
                    count++;
            }
        }
        
        if(loggerEnabled && logger != NULL && symbol != "")
        {
            logger.KeepNotes(symbol, OBSERVE, "OrderManager", 
                           StringFormat("Open trades count: %d", count), 
                           false, false, 0);
        }
        
        return count;
    }
    
    //+------------------------------------------------------------------+
    //| GetOrderErrorDescription - Get error description                |
    //+------------------------------------------------------------------+
    string GetOrderErrorDescription(int errorCode)
    {
        // Common MQL5 error codes
        switch(errorCode)
        {
            case 0:   return "No error";
            case 1:   return "No error, but result unknown";
            case 2:   return "Common error";
            case 3:   return "Invalid trade parameters";
            case 4:   return "Trade server is busy";
            case 5:   return "Old version";
            case 6:   return "No connection with trade server";
            case 7:   return "Not enough rights";
            case 8:   return "Too frequent requests";
            case 64:  return "Account disabled";
            case 65:  return "Invalid account";
            case 128: return "Trade timeout";
            case 129: return "Invalid price";
            case 130: return "Invalid stops";
            case 131: return "Invalid trade volume";
            case 132: return "Market is closed";
            case 133: return "Trade is disabled";
            case 134: return "Not enough money";
            case 135: return "Price changed";
            case 136: return "Off quotes";
            case 137: return "Broker is busy";
            case 138: return "Requote";
            case 139: return "Order is locked";
            case 140: return "Long positions only allowed";
            case 141: return "Too many requests";
            case 145: return "Modification denied (order too close to market)";
            case 146: return "Trade context is busy";
            case 147: return "Expirations denied by broker";
            case 148: return "Too many open and pending orders";
            default:  return StringFormat("Unknown error code: %d", errorCode);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Helper function to convert position type to text                |
    //+------------------------------------------------------------------+
    string GetDirectionText(int positionType)
    {
        switch(positionType)
        {
            case POSITION_TYPE_BUY: return "BUY";
            case POSITION_TYPE_SELL: return "SELL";
            default: return "UNKNOWN";
        }
    }
    
    //+------------------------------------------------------------------+
    //| Helper function to convert risk level to string                 |
    //+------------------------------------------------------------------+
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
};

// ============================================================
//                  INITIALIZATION FUNCTION
// ============================================================
OrderManager g_orderManager;  // Global instance

bool InitializeOrderManager(ResourceManager &p_logger, RiskManager &h_riskManager, double marginBuffer = 0.8)
{
    // Configure order manager
    g_orderManager.SetLogger(p_logger);
    g_orderManager.SetRiskManager(h_riskManager);
    g_orderManager.Initialize(marginBuffer, &h_riskManager);
    g_orderManager.ResetDailyTrades();
    
    // Log initialization
    if(g_orderManager.IsLoggerEnabled() && g_orderManager.GetLogger() != NULL)
    {
        g_orderManager.GetLogger().StartContextWith("SYSTEM", "ORDERMANAGER_INIT_FULL");
        g_orderManager.GetLogger().AddDoubleContext("SYSTEM", "MarginBuffer", marginBuffer * 100, 0);
        g_orderManager.GetLogger().AddToContext("SYSTEM", "LoggerAttached", "YES");
        g_orderManager.GetLogger().AddToContext("SYSTEM", "RiskManagerAttached", "YES");
        g_orderManager.GetLogger().FlushContext("SYSTEM", AUTHORIZE, "OrderManager", 
                                         "OrderManager fully initialized", false);
    }
    
    Print("========================================");
    Print("ORDER MANAGER INITIALIZED SUCCESSFULLY");
    Print("========================================");
    Print("  - Logger: Attached");
    Print("  - RiskManager: Attached");
    Print("  - Margin buffer: ", DoubleToString(marginBuffer * 100, 0), "%");
    Print("  - Daily trades counter: Reset");
    Print("========================================");
    
    return true;
}

//+------------------------------------------------------------------+