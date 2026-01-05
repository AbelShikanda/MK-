//+------------------------------------------------------------------+
//|                     PositionManager.mqh                          |
//|           Pure Functions for Position Management                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include <Trade/Trade.mqh>

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"
#include "RiskManager.mqh"
#include "../Utils/Logger.mqh"
#include "../Data/TradePackage.mqh"

// ================= FORWARD DECLARATIONS =================

// ==================== DEBUG SETTINGS ====================
bool POSITION_DEBUG_ENABLED = true;

// Simple debug function using Logger
void PositionDebugLog(string context, string message) {
   if(POSITION_DEBUG_ENABLED) {
      Logger::Log(context, message, true, true);
   }
}

// ==================== ENUMERATIONS ====================
enum ENUM_CLOSE_PRIORITY 
{
    CLOSE_SMALLEST_PROFIT,
    CLOSE_BIGGEST_LOSS,
    CLOSE_SMALLEST_LOSS,
    CLOSE_OLDEST,
    CLOSE_NEWEST
};

// ==================== POSITION MANAGER NAMESPACE ====================
namespace PositionManager
{
    // ==================== VALIDATION FUNCTIONS ====================
    
    bool ValidateStops(string symbol, bool isBuy, double entryPrice, double &stopLoss, double &takeProfit)
    {
        PositionDebugLog("POSITION-VALIDATE-STOPS", "=== COMPREHENSIVE STOP VALIDATION (DOLLARS) ===");
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        PositionDebugLog("POSITION-VALIDATE-STOPS", 
                    StringFormat("%s: Bid=%.5f, Ask=%.5f, Entry=%.5f, Digits=%d, Point=%.5f, Tick=%.5f",
                                symbol, bid, ask, entryPrice, digits, point, tickSize));
        
        // Get current market prices for validation
        double currentPrice = isBuy ? ask : bid;
        
        // Check if entry price is reasonable compared to current market
        double priceDiffDollars = MathAbs(entryPrice - currentPrice);  // Dollar difference
        if(priceDiffDollars > 10.0)  // More than $10 from current market
        {
            PositionDebugLog("POSITION-VALIDATE-STOPS", 
                        StringFormat("⚠️ Entry price %.5f is $%.2f from market %.5f", 
                                    entryPrice, priceDiffDollars, currentPrice));
            // For pending orders, this might be OK, but for market orders, adjust
            if(entryPrice != currentPrice)
            {
                entryPrice = currentPrice;
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("✅ Using market price as entry: %.5f", entryPrice));
            }
        }
        
        // ==================== SYMBOL-SPECIFIC DISTANCE LIMITS IN DOLLARS ====================
        double maxDistanceDollars = 15.0;  // Default maximum: $15
        double minDistanceDollars = 7.0;    // Default minimum: $2.00
        
        if(symbol == "XAUUSD" || symbol == "GOLD")
        {
            maxDistanceDollars = 15.0;   // Maximum $15 for gold
            minDistanceDollars = 7.0;    // Minimum $7 for gold
            PositionDebugLog("POSITION-VALIDATE-STOPS", "✅ Gold detected - limits: $20-$100");
        }
        else if(symbol == "XAGUSD")
        {
            maxDistanceDollars = 30.0;    // Maximum $30.00 for silver
            minDistanceDollars = 10.30;   // Minimum $10.30 for silver
            PositionDebugLog("POSITION-VALIDATE-STOPS", "✅ Silver detected - limits: $10.30-$30.00");
        }
        else if(symbol == "BTCUSD" || symbol == "ETHUSD")
        {
            maxDistanceDollars = 200.0;  // Maximum $200 for crypto
            minDistanceDollars = 50.0;   // Minimum $50 for crypto
            PositionDebugLog("POSITION-VALIDATE-STOPS", "✅ Crypto detected - limits: $50-$200");
        }
        else
        {
            // Forex - convert pips to dollars (approx 1 pip = $10 per lot)
            // For 0.01 lots, 1 pip ≈ $0.10, so adjust accordingly
            maxDistanceDollars = 20.0;   // Maximum $20 for forex (approx 200 pips)
            minDistanceDollars = 1.5;    // Minimum $1.50 for forex (approx 15 pips)
            PositionDebugLog("POSITION-VALIDATE-STOPS", "✅ Forex detected - limits: $1.50-$20.00");
        }
        // ==================== END SYMBOL-SPECIFIC LIMITS ====================
        
        // Validate stop loss
        if(stopLoss > 0)
        {
            // Check direction
            if((isBuy && stopLoss >= entryPrice) || (!isBuy && stopLoss <= entryPrice))
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("❌ Stop loss wrong direction: %s SL=%.5f %s Entry=%.5f",
                                        isBuy ? "BUY" : "SELL", stopLoss, 
                                        isBuy ? ">=" : "<=", entryPrice));
                
                // Auto-correct with reasonable distance
                if(isBuy)
                {
                    stopLoss = entryPrice - minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Auto-corrected BUY SL to: %.5f ($%.2f below)", 
                                            stopLoss, minDistanceDollars));
                }
                else
                {
                    stopLoss = entryPrice + minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Auto-corrected SELL SL to: %.5f ($%.2f above)", 
                                            stopLoss, minDistanceDollars));
                }
            }
            
            // Check distance in dollars
            double slDistanceDollars = isBuy ? (entryPrice - stopLoss) : (stopLoss - entryPrice);
            
            PositionDebugLog("POSITION-VALIDATE-STOPS", 
                        StringFormat("SL distance: $%.2f (entry: %.5f, sl: %.5f)", 
                                    slDistanceDollars, entryPrice, stopLoss));
            
            // Check minimum distance
            if(slDistanceDollars < minDistanceDollars)
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("⚠️ Stop loss too close: $%.2f < $%.2f min", 
                                        slDistanceDollars, minDistanceDollars));
                
                if(isBuy)
                {
                    stopLoss = entryPrice - minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted BUY SL to min distance: %.5f ($%.2f)", 
                                            stopLoss, minDistanceDollars));
                }
                else
                {
                    stopLoss = entryPrice + minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted SELL SL to min distance: %.5f ($%.2f)", 
                                            stopLoss, minDistanceDollars));
                }
            }
            
            // Check maximum distance
            if(slDistanceDollars > maxDistanceDollars)
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("⚠️ Stop loss too far: $%.2f > $%.2f max", 
                                        slDistanceDollars, maxDistanceDollars));
                
                if(isBuy)
                {
                    stopLoss = entryPrice - maxDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted BUY SL to max distance: %.5f ($%.2f)", 
                                            stopLoss, maxDistanceDollars));
                }
                else
                {
                    stopLoss = entryPrice + maxDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted SELL SL to max distance: %.5f ($%.2f)", 
                                            stopLoss, maxDistanceDollars));
                }
            }
        }
        
        // Validate take profit
        if(takeProfit > 0)
        {
            // Check direction
            if((isBuy && takeProfit <= entryPrice) || (!isBuy && takeProfit >= entryPrice))
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("❌ Take profit wrong direction: %s TP=%.5f %s Entry=%.5f",
                                        isBuy ? "BUY" : "SELL", takeProfit,
                                        isBuy ? "<=" : ">=", entryPrice));
                
                // Auto-correct with reasonable distance
                if(isBuy)
                {
                    takeProfit = entryPrice + (minDistanceDollars * 1.5);  // 1.5x min distance above
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Auto-corrected BUY TP to: %.5f ($%.1.5f above)", 
                                            takeProfit, minDistanceDollars * 1.5));
                }
                else
                {
                    takeProfit = entryPrice - (minDistanceDollars * 1.5);  // 1.5x min distance below
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Auto-corrected SELL TP to: %.5f ($%.1.5f below)", 
                                            takeProfit, minDistanceDollars * 1.5));
                }
            }
            
            // Check distance in dollars
            double tpDistanceDollars = isBuy ? (takeProfit - entryPrice) : (entryPrice - takeProfit);
            
            PositionDebugLog("POSITION-VALIDATE-STOPS", 
                        StringFormat("TP distance: $%.2f (entry: %.5f, tp: %.5f)", 
                                    tpDistanceDollars, entryPrice, takeProfit));
            
            // Check minimum distance
            if(tpDistanceDollars < minDistanceDollars)
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("⚠️ Take profit too close: $%.2f < $%.2f min", 
                                        tpDistanceDollars, minDistanceDollars));
                
                if(isBuy)
                {
                    takeProfit = entryPrice + minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted BUY TP to min distance: %.5f ($%.2f)", 
                                            takeProfit, minDistanceDollars));
                }
                else
                {
                    takeProfit = entryPrice - minDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted SELL TP to min distance: %.5f ($%.2f)", 
                                            takeProfit, minDistanceDollars));
                }
            }
            
            // Optional: Check maximum TP distance
            double maxTpDistanceDollars = maxDistanceDollars * 3; // TP can be 3x further than SL
            if(tpDistanceDollars > maxTpDistanceDollars)
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", 
                            StringFormat("⚠️ Take profit too far: $%.2f > $%.2f max", 
                                        tpDistanceDollars, maxTpDistanceDollars));
                
                if(isBuy)
                {
                    takeProfit = entryPrice + maxTpDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted BUY TP to max distance: %.5f ($%.2f)", 
                                            takeProfit, maxTpDistanceDollars));
                }
                else
                {
                    takeProfit = entryPrice - maxTpDistanceDollars;
                    PositionDebugLog("POSITION-VALIDATE-STOPS", 
                                StringFormat("✅ Adjusted SELL TP to max distance: %.5f ($%.2f)", 
                                            takeProfit, maxTpDistanceDollars));
                }
            }
        }
        
        // Normalize prices to broker requirements
        stopLoss = NormalizePriceForBroker(symbol, stopLoss);
        takeProfit = NormalizePriceForBroker(symbol, takeProfit);
        
        // Final validation
        bool isValid = true;
        
        if(stopLoss > 0)
        {
            if((isBuy && stopLoss >= entryPrice) || (!isBuy && stopLoss <= entryPrice))
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", "❌ FINAL VALIDATION FAILED: Stop loss still invalid");
                isValid = false;
            }
        }
        
        if(takeProfit > 0)
        {
            if((isBuy && takeProfit <= entryPrice) || (!isBuy && takeProfit >= entryPrice))
            {
                PositionDebugLog("POSITION-VALIDATE-STOPS", "❌ FINAL VALIDATION FAILED: Take profit still invalid");
                isValid = false;
            }
        }
        
        PositionDebugLog("POSITION-VALIDATE-STOPS", 
                    StringFormat("%s Final: Entry=%.5f, SL=%.5f, TP=%.5f",
                                isValid ? "✅" : "❌", entryPrice, stopLoss, takeProfit));
        
        return isValid;
    }

    double NormalizePriceForBroker(string symbol, double price)
    {
        if(price <= 0) return price;
        
        PositionDebugLog("POSITION-NORMALIZE", StringFormat("Normalizing price %.5f for %s", price, symbol));
        
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        if(tickSize > 0)
        {
            // Ensure price is multiple of tick size
            double normalized = NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
            
            PositionDebugLog("POSITION-NORMALIZE", StringFormat("Normalized: %.5f -> %.5f (tick: %.5f, digits: %d)", 
                                        price, normalized, tickSize, digits));
            return normalized;
        }
        
        double normalized = NormalizeDouble(price, digits);
        PositionDebugLog("POSITION-NORMALIZE", StringFormat("Normalized: %.5f -> %.5f (digits: %d)", 
                                    price, normalized, digits));
        return normalized;
    }
    
    void LogStopErrorDetails(string symbol, bool isBuy, double entryPrice, double stopLoss, double takeProfit)
    {
        PositionDebugLog("POSITION-ERROR-4756", "=== ERROR 4756 DETAILS ===");
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        // Corrected: Use SymbolInfoInteger instead of SymbolInfoDouble
        double stopsLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double freezeLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        double minStopDistance = stopsLevel * point;
        
        PositionDebugLog("POSITION-ERROR-4756", StringFormat("Symbol: %s | Buy: %s", symbol, isBuy ? "YES" : "NO"));
        PositionDebugLog("POSITION-ERROR-4756", StringFormat("Entry: %.5f | SL: %.5f | TP: %.5f", 
                                entryPrice, stopLoss, takeProfit));
        PositionDebugLog("POSITION-ERROR-4756", StringFormat("Point: %.5f | StopsLevel: %.0f | FreezeLevel: %.0f", 
                                point, stopsLevel, freezeLevel));
        PositionDebugLog("POSITION-ERROR-4756", StringFormat("Min stop distance: %.5f (%.1f pips)", 
                                minStopDistance, minStopDistance/point));
        
        if(isBuy)
        {
            double slDistance = entryPrice - stopLoss;
            double tpDistance = (takeProfit > 0) ? (takeProfit - entryPrice) : 0;
            PositionDebugLog("POSITION-ERROR-4756", StringFormat("BUY: SL distance: %.5f (%.1f pips) | TP distance: %.5f (%.1f pips)", 
                                    slDistance, slDistance/point, tpDistance, tpDistance/point));
        }
        else
        {
            double slDistance = stopLoss - entryPrice;
            double tpDistance = (takeProfit > 0) ? (entryPrice - takeProfit) : 0;
            PositionDebugLog("POSITION-ERROR-4756", StringFormat("SELL: SL distance: %.5f (%.1f pips) | TP distance: %.5f (%.1f pips)", 
                                    slDistance, slDistance/point, tpDistance, tpDistance/point));
        }
        
        PositionDebugLog("POSITION-ERROR-4756", "=== END ERROR DETAILS ===");
    }
    
    // ==================== POSITION OPERATIONS ====================
    
    bool OpenPosition(string symbol, bool isBuy, string comment = "", int magic = 0, 
                 ENUM_STOP_METHOD stopMethod = STOP_ATR, double riskPercent = 2.0, 
                 double rrRatio = 2.0, string reason = "Signal",
                 double customEntry = 0, double customStopLoss = 0, double customTakeProfit = 0)
    {
        PositionDebugLog("POSITION-OPEN", StringFormat("=== OPENING POSITION === | Symbol: %s | Buy: %s | Magic: %d | Reason: %s | StopMethod: %d | Risk: %.2f%% | RR: %.2f",
                                        symbol, isBuy ? "YES" : "NO", magic, reason, stopMethod, riskPercent, rrRatio));
        
        PositionDebugLog("POSITION-OPEN", StringFormat("Custom params - Entry: %.5f (provided: %s) | SL: %.5f | TP: %.5f",
                                        customEntry, customEntry > 0 ? "YES" : "NO", customStopLoss, customTakeProfit));
        
        // ==================== POSITION LIMIT CHECK ====================
        PositionDebugLog("POSITION-OPEN", "Checking position limits...");
        
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        int maxTotalPositions, maxPositionsPerSymbol;
        
        // Get recommended limits based on account size
        RiskCalculator::GetRecommendedPositionLimits(accountBalance, maxTotalPositions, maxPositionsPerSymbol);
        
        // Check if we can open a new position
        if(!RiskCalculator::CanAddNewPosition(symbol, magic, maxTotalPositions, maxPositionsPerSymbol))
        {
            PositionDebugLog("POSITION-OPEN", "❌ Position limit check failed");
            return false;
        }
        // ==================== END POSITION LIMIT CHECK ====================
        
        // Validate risk first
        PositionDebugLog("POSITION-OPEN", "Validating risk constraints...");
        if(!RiskCalculator::CanOpenTrade(5.0, 20.0))
        {
            PositionDebugLog("POSITION-OPEN", "❌ Risk validation failed");
            return false;
        }
        
        // Calculate entry price (use custom if provided, otherwise get market price)
        PositionDebugLog("POSITION-OPEN", "Calculating entry price...");
        double entryPrice = (customEntry > 0) ? customEntry : GetEntryPrice(symbol, isBuy);
        PositionDebugLog("POSITION-OPEN", StringFormat("Entry price: %.5f (Custom: %s)", 
                                    entryPrice, customEntry > 0 ? "YES" : "NO"));
        
        // Calculate stop loss (use custom if provided, otherwise calculate)
        PositionDebugLog("POSITION-OPEN", "Calculating stop loss...");
        double stopLoss = 0;
        PositionDebugLog("POSITION-OPEN", StringFormat("Calculating stop loss using method: %d", stopMethod));
        stopLoss = RiskCalculator::CalculateStopLoss(symbol, isBuy, entryPrice, stopMethod);
        PositionDebugLog("POSITION-OPEN", StringFormat("Calculated stop loss: %.5f (Method: %d)", stopLoss, stopMethod));
        
        // Calculate position size using RiskCalculator
        PositionDebugLog("POSITION-OPEN", "Calculating position size...");
        double lotSize = RiskCalculator::CalculatePositionSize(symbol, entryPrice, stopLoss, riskPercent);
        PositionDebugLog("POSITION-OPEN", StringFormat("Calculated lot size: %.3f (Risk: %.1f%%)", lotSize, riskPercent));
        
        // Validate lot size
        if(lotSize <= 0)
        {
            PositionDebugLog("POSITION-OPEN", "❌ Invalid lot size");
            return false;
        }
        
        // ==================== SAFETY CHECK: LIMIT LOT SIZE FOR VOLATILE SYMBOLS ====================
        
        if(symbol == "XAUUSD" || symbol == "GOLD" || symbol == "XAGUSD")
        {
            // Precious metals need much smaller lot sizes
            double maxPreciousMetalLots = 0.5; // Maximum 0.5 lots for precious metals with $5000 account
            
            // Adjust based on account size
            if(accountBalance >= 100)
                maxPreciousMetalLots = 0.01;
            else if(accountBalance >= 500)
                maxPreciousMetalLots = 0.05;
            else if(accountBalance >= 5000)
                maxPreciousMetalLots = 5.0;
            
            if(lotSize > maxPreciousMetalLots)
            {
                PositionDebugLog("POSITION-OPEN", 
                            StringFormat("⚠️ Reducing %s lot size from %.3f to %.3f (precious metal safety limit | Account: $%.2f)", 
                                        symbol, lotSize, maxPreciousMetalLots, accountBalance));
                lotSize = maxPreciousMetalLots;
            }
        }
        
        // For major forex pairs, also apply reasonable limits
        string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD"};
        bool isMajor = false;
        for(int i = 0; i < ArraySize(majors); i++)
        {
            if(symbol == majors[i])
            {
                isMajor = true;
                break;
            }
        }

        if(isMajor && lotSize > 10.0) // Cap major forex at 10 lots
        {
            PositionDebugLog("POSITION-OPEN", 
                        StringFormat("⚠️ Capping %s lot size from %.3f to 50.0 (major forex safety limit)", 
                                    symbol, lotSize));
            lotSize = 50.0;
        }
        // ==================== END SAFETY CHECK ====================
        
        // Check margin
        PositionDebugLog("POSITION-OPEN", "Checking margin requirements...");
        if(!CheckMargin(symbol, lotSize))
        {
            PositionDebugLog("POSITION-OPEN", "❌ Insufficient margin");
            return false;
        }
        
        // Calculate take profit (use custom if provided, otherwise calculate)
        PositionDebugLog("POSITION-OPEN", "Calculating take profit...");
        double takeProfit = 0;
        PositionDebugLog("POSITION-OPEN", StringFormat("Calculating take profit with RR ratio: %.2f", rrRatio));
        takeProfit = RiskCalculator::CalculateTakeProfit(symbol, isBuy, entryPrice, stopLoss, rrRatio);
        PositionDebugLog("POSITION-OPEN", StringFormat("Calculated take profit: %.5f (RR: %.1f)", takeProfit, rrRatio));

        
        // VALIDATE STOPS BEFORE EXECUTION (CRITICAL FIX)
        PositionDebugLog("POSITION-OPEN", "Validating stop levels...");
        if(!ValidateStops(symbol, isBuy, entryPrice, stopLoss, takeProfit))
        {
            PositionDebugLog("POSITION-OPEN", "❌ Stop validation failed");
            return false;
        }
        
        // Normalize prices for broker requirements
        stopLoss = NormalizePriceForBroker(symbol, stopLoss);
        takeProfit = NormalizePriceForBroker(symbol, takeProfit);
        PositionDebugLog("POSITION-OPEN", StringFormat("Normalized prices - SL: %.5f | TP: %.5f", stopLoss, takeProfit));
        
        // Execute trade
        PositionDebugLog("POSITION-OPEN", "Preparing to execute trade...");
        CTrade trade;
        trade.SetExpertMagicNumber(magic);
        trade.SetDeviationInPoints(10);  // Default slippage
        
        string fullComment = comment != "" ? comment + "_" + reason : reason;
        
        PositionDebugLog("POSITION-OPEN", StringFormat("Executing %s: %.3f lots @ %.5f (SL: %.5f, TP: %.5f)",
                                    isBuy ? "BUY" : "SELL", lotSize, entryPrice, stopLoss, takeProfit));
        
        bool success = false;
        if(isBuy)
            success = trade.Buy(lotSize, symbol, entryPrice, stopLoss, takeProfit, fullComment);
        else
            success = trade.Sell(lotSize, symbol, entryPrice, stopLoss, takeProfit, fullComment);

        
        if(success)
        {
            PositionDebugLog("POSITION-OPEN", "✅ SUCCESS: Position opened");
            
            // Log trade
            Logger::LogTrade("PositionManager", symbol, isBuy ? "BUY" : "SELL", lotSize, entryPrice);
            Logger::ShowDecisionFast(symbol, isBuy ? 1 : -1, 0.9, 
                                StringFormat("Entry: %.5f, SL: %.5f, TP: %.5f", 
                                            entryPrice, stopLoss, takeProfit));
            
            Logger::Log("PositionManager", 
                    StringFormat("%s %s opened: %.3f lots @ %.5f (SL: %.5f, TP: %.5f, Risk: %.2f%%)",
                                symbol, isBuy ? "BUY" : "SELL", lotSize, entryPrice,
                                stopLoss, takeProfit, riskPercent));
            // ExpertRemove();
            return true;
        }
        else
        {
            int errorCode = GetLastError();
            string errorDesc = "";
            
            // Enhanced error handling with 4756
            switch(errorCode)
            {
                case 10004: errorDesc = "Requote"; break;
                case 10006: errorDesc = "Request rejected"; break;
                case 10007: errorDesc = "Request canceled by trader"; break;
                case 10010: errorDesc = "Only part of request executed"; break;
                case 10011: errorDesc = "Request processing error"; break;
                case 10012: errorDesc = "Request canceled by timeout"; break;
                case 10013: errorDesc = "Invalid request"; break;
                case 10014: errorDesc = "Invalid volume"; break;
                case 10015: errorDesc = "Invalid price"; break;
                case 10016: errorDesc = "Invalid stops (10016)"; break;
                case 4756: errorDesc = "Invalid stops (4756) - Stop loss/take profit levels invalid"; break;
                case 10017: errorDesc = "Trade disabled"; break;
                case 10018: errorDesc = "Market closed"; break;
                case 10019: errorDesc = "Insufficient funds"; break;
                case 10020: errorDesc = "Price changed"; break;
                case 10021: errorDesc = "Off quotes"; break;
                case 10022: errorDesc = "Broker busy"; break;
                case 10023: errorDesc = "Trade context busy"; break;
                case 10024: errorDesc = "Expiration denied"; break;
                case 10025: errorDesc = "Too many requests"; break;
                case 10026: errorDesc = "No changes"; break;
                case 10027: errorDesc = "Automated trading disabled"; break;
                default: errorDesc = "Unknown error"; break;
            }
            
            PositionDebugLog("POSITION-OPEN", StringFormat("❌ FAILED: Trade execution error %d: %s", errorCode, errorDesc));
            
            // Special handling for error 4756
            if(errorCode == 4756)
            {
                LogStopErrorDetails(symbol, isBuy, entryPrice, stopLoss, takeProfit);
            }
            
            return false;
        }
    }
    
    bool CloseAllPositions(string symbol = "", int magic = 0, string reason = "Close All")
    {
        PositionDebugLog("POSITION-CLOSE-ALL", StringFormat("=== CLOSING ALL POSITIONS === | Symbol: %s | Magic: %d | Reason: %s",
                                       symbol != "" ? symbol : "ALL", magic, reason));
        
        int closedCount = 0;
        int attemptedCount = 0;
        double totalProfit = 0;
        double totalLoss = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                if((symbol == "" || posSymbol == symbol) &&
                   (magic == 0 || posMagic == magic))
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    CTrade trade;
                    attemptedCount++;
                    
                    PositionDebugLog("POSITION-CLOSE-ALL", StringFormat("Attempting to close position %d: %s | Volume: %.3f | Ticket: %d | Profit: $%.2f",
                                                   i, posSymbol, volume, ticket, profit));
                    
                    if(trade.PositionClose(ticket))
                    {
                        closedCount++;
                        totalProfit += profit;
                        if(profit < 0) totalLoss += profit;
                        
                        PositionDebugLog("POSITION-CLOSE-ALL", "✅ Position closed successfully");
                        Logger::Log("PositionManager", 
                                   StringFormat("Closed %s: %.3f lots, P/L: $%.2f", 
                                               posSymbol, volume, profit),
                                   false, false);
                    }
                    else
                    {
                        int errorCode = GetLastError();
                        PositionDebugLog("POSITION-CLOSE-ALL", StringFormat("❌ Failed to close position: Error %d", errorCode));
                        Logger::Log("PositionManager", 
                                   StringFormat("Failed to close %s: Error %d", posSymbol, errorCode),
                                   true, true);
                    }
                }
            }
        }
        
        if(attemptedCount > 0)
        {
            if(closedCount == attemptedCount)
            {
                PositionDebugLog("POSITION-CLOSE-ALL", StringFormat("✅ SUCCESS: All %d positions closed | Total P/L: $%.2f | Losses: $%.2f", 
                                                   closedCount, totalProfit, totalLoss));
                Logger::Log("PositionManager", 
                           StringFormat("All %d positions closed: $%.2f total", 
                                       closedCount, totalProfit),
                           true, true);
            }
            else
            {
                PositionDebugLog("POSITION-CLOSE-ALL", StringFormat("⚠️ PARTIAL: Closed %d/%d positions | Total P/L: $%.2f", 
                                                   closedCount, attemptedCount, totalProfit));
                Logger::Log("PositionManager", 
                           StringFormat("Partial close: %d/%d positions closed: $%.2f", 
                                       closedCount, attemptedCount, totalProfit),
                           true, true);
            }
            return closedCount > 0;
        }
        
        PositionDebugLog("POSITION-CLOSE-ALL", "⚠️ No positions to close matching criteria");
        return false;
    }
    
    bool CloseSinglePosition(ulong ticket, string reason = "Manual")
    {
        PositionDebugLog("POSITION-CLOSE-SINGLE", StringFormat("=== CLOSING SINGLE POSITION === | Ticket: %d | Reason: %s", ticket, reason));
        
        if(!PositionSelectByTicket(ticket))
        {
            PositionDebugLog("POSITION-CLOSE-SINGLE", StringFormat("❌ Position not found: %d", ticket));
            return false;
        }
        
        string symbol = PositionGetString(POSITION_SYMBOL);
        double profit = PositionGetDouble(POSITION_PROFIT);
        double volume = PositionGetDouble(POSITION_VOLUME);
        
        PositionDebugLog("POSITION-CLOSE-SINGLE", StringFormat("Closing %s: %.3f lots | Current P/L: $%.2f", symbol, volume, profit));
        
        CTrade trade;
        if(trade.PositionClose(ticket))
        {
            PositionDebugLog("POSITION-CLOSE-SINGLE", "✅ Position closed successfully");
            Logger::Log("PositionManager", 
                       StringFormat("Closed %s (Ticket: %d): $%.2f", symbol, ticket, profit),
                       false, false);
            return true;
        }
        else
        {
            int errorCode = GetLastError();
            PositionDebugLog("POSITION-CLOSE-SINGLE", StringFormat("❌ Failed to close position: Error %d", errorCode));
            return false;
        }
    }
    
    // ==================== SMART CLOSE FUNCTIONS ====================
    
    bool SmartClosePositionEx(ENUM_CLOSE_PRIORITY priority, int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-SMART-CLOSE", StringFormat("=== SMART CLOSE EXECUTION === | Priority: %d | Magic: %d", priority, magic));
        
        int totalPositions = GetPositionCount("", magic);
        PositionDebugLog("POSITION-SMART-CLOSE", StringFormat("Found %d total positions for magic %d", totalPositions, magic));
        
        bool result = false;
        switch(priority)
        {
            case CLOSE_SMALLEST_PROFIT:
                PositionDebugLog("POSITION-SMART-CLOSE", "Strategy: Close smallest profit");
                result = CloseSmallestProfit(magic, outClosedSymbol);
                break;
            case CLOSE_BIGGEST_LOSS:
                PositionDebugLog("POSITION-SMART-CLOSE", "Strategy: Close biggest loss");
                result = CloseBiggestLoss(magic, outClosedSymbol);
                break;
            case CLOSE_SMALLEST_LOSS:
                PositionDebugLog("POSITION-SMART-CLOSE", "Strategy: Close smallest loss");
                result = CloseSmallestLoss(magic, outClosedSymbol);
                break;
            case CLOSE_OLDEST:
                PositionDebugLog("POSITION-SMART-CLOSE", "Strategy: Close oldest position");
                result = CloseOldest(magic, outClosedSymbol);
                break;
            case CLOSE_NEWEST:
                PositionDebugLog("POSITION-SMART-CLOSE", "Strategy: Close newest position");
                result = CloseNewest(magic, outClosedSymbol);
                break;
            default:
                PositionDebugLog("POSITION-SMART-CLOSE", "⚠️ Unknown priority, defaulting to smallest profit");
                result = CloseSmallestProfit(magic, outClosedSymbol);
                break;
        }
        
        PositionDebugLog("POSITION-SMART-CLOSE", StringFormat("Smart close result: %s | Symbol: %s", 
                                           result ? "✅ SUCCESS" : "❌ FAILED", outClosedSymbol));
        return result;
    }
    
    // ==================== POSITION ANALYSIS ====================
    
    int GetPositionCount(string symbol = "", int magic = 0)
    {
        PositionDebugLog("POSITION-ANALYSIS", StringFormat("Counting positions | Symbol: %s | Magic: %d", 
                                          symbol != "" ? symbol : "ALL", magic));
        
        int count = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                
                if((symbol == "" || posSymbol == symbol) &&
                   (magic == 0 || posMagic == magic))
                    count++;
            }
        }
        
        PositionDebugLog("POSITION-ANALYSIS", StringFormat("Found %d positions", count));
        return count;
    }
    
    double GetTotalProfit(string symbol = "", int magic = 0)
    {
        PositionDebugLog("POSITION-ANALYSIS", StringFormat("Calculating total profit | Symbol: %s | Magic: %d", 
                                          symbol != "" ? symbol : "ALL", magic));
        
        double total = 0;
        int positionCount = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                
                if((symbol == "" || posSymbol == symbol) &&
                   (magic == 0 || posMagic == magic))
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    total += profit;
                    positionCount++;
                    
                    PositionDebugLog("POSITION-ANALYSIS-DETAIL", StringFormat("Position %d: %s - $%.2f", 
                                                           i, posSymbol, profit));
                }
            }
        }
        
        PositionDebugLog("POSITION-ANALYSIS", StringFormat("Total profit: $%.2f from %d positions", total, positionCount));
        return total;
    }
    
    // ==================== TRAILING STOP MANAGEMENT ====================
    
    void UpdateAllTrailingStops(int magicNumber = 0, double minProfitToTrail = 10.0, 
                                ENUM_TIMEFRAMES structureTF = PERIOD_H1)
    {
        PositionDebugLog("TRAILING-SIMPLE", 
            StringFormat("=== AUTO-TRAILING ALL POSITIONS === | Magic: %d | Min Profit: $%.2f | TF: %s",
                       magicNumber, minProfitToTrail, TimeframeToString(structureTF)));
        
        int totalUpdated = 0;
        int totalPositions = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                totalPositions++;
                
                // Filter by magic number if specified
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magicNumber != 0 && posMagic != magicNumber) continue;
                
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                double entry = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSL = PositionGetDouble(POSITION_SL);
                double currentTP = PositionGetDouble(POSITION_TP);
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
                
                PositionDebugLog("TRAILING-POSITION", 
                    StringFormat("%s (%s): Entry=%.5f, Current SL=%.5f, Price=%.5f, P/L=$%.2f",
                               symbol, isBuy ? "BUY" : "SELL", entry, currentSL, currentPrice, profit));
                
                // Check minimum profit requirement
                if(profit < minProfitToTrail)
                {
                    PositionDebugLog("TRAILING-SKIP", 
                        StringFormat("Skipping - Profit $%.2f < Minimum $%.2f", profit, minProfitToTrail));
                    continue;
                }
                
                // Calculate new structural trailing stop
                double newSL = RiskCalculator::CalculateTrailingStop(
                    symbol, 
                    isBuy, 
                    entry, 
                    currentPrice, 
                    currentSL,
                    0,
                    structureTF
                );
                
                // Check if new SL is better
                bool shouldUpdate = false;
                
                if(isBuy)
                {
                    if(newSL > currentSL && newSL < currentPrice)
                    {
                        shouldUpdate = true;
                        PositionDebugLog("TRAILING-BUY", 
                            StringFormat("✅ BUY: New SL %.5f > Current SL %.5f", newSL, currentSL));
                    }
                }
                else
                {
                    if(newSL < currentSL && newSL > currentPrice)
                    {
                        shouldUpdate = true;
                        PositionDebugLog("TRAILING-SELL", 
                            StringFormat("✅ SELL: New SL %.5f < Current SL %.5f", newSL, currentSL));
                    }
                }
                
                // Update position if improved
                if(shouldUpdate)
                {
                    CTrade trade;
                    if(trade.PositionModify(ticket, newSL, currentTP))
                    {
                        totalUpdated++;
                        PositionDebugLog("TRAILING-UPDATED", 
                            StringFormat("✅ Position updated: SL %.5f -> %.5f (Locked profit: $%.2f)",
                                       currentSL, newSL, profit));
                    }
                    else
                    {
                        int errorCode = GetLastError();
                        PositionDebugLog("TRAILING-ERROR", 
                            StringFormat("❌ Failed to update: Error %d", errorCode));
                    }
                    ExpertRemove();
                }
                else
                {
                    PositionDebugLog("TRAILING-NOCHANGE", "No improvement in SL");
                }
            }
        }
        
        PositionDebugLog("TRAILING-COMPLETE", 
            StringFormat("Trailing complete: %d/%d positions updated", totalUpdated, totalPositions));
    }
    
    // Helper function for timeframe string
    string TimeframeToString(ENUM_TIMEFRAMES tf)
    {
        switch(tf)
        {
            case PERIOD_M1:  return "M1";
            case PERIOD_M5:  return "M5";
            case PERIOD_M15: return "M15";
            case PERIOD_M30: return "M30";
            case PERIOD_H1:  return "H1";
            case PERIOD_H4:  return "H4";
            case PERIOD_D1:  return "D1";
            default: return "TF-" + IntegerToString(tf);
        }
    }
    
    // ==================== UTILITY FUNCTIONS ====================
    
    bool CheckMargin(string symbol, double lotSize, double safetyBuffer = 0.8)
    {
        PositionDebugLog("POSITION-MARGIN", StringFormat("Checking margin for %s: %.3f lots | Safety buffer: %.0f%%", 
                                            symbol, lotSize, safetyBuffer * 100));
        
        // Get correct margin calculation
        double marginRequired = 0;
        double marginPerLot = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        PositionDebugLog("POSITION-MARGIN-DETAILS", 
                    StringFormat("%s: Margin per lot=%.2f, Contract size=%.0f, Lots=%.3f", 
                                symbol, marginPerLot, contractSize, lotSize));
        
        // Try different calculation methods
        if(marginPerLot > 0)
        {
            // Standard calculation
            marginRequired = marginPerLot * lotSize;
            PositionDebugLog("POSITION-MARGIN-DETAILS", 
                        StringFormat("Standard calculation: %.2f × %.3f = $%.2f", 
                                    marginPerLot, lotSize, marginRequired));
        }
        else
        {
            // Alternative calculation for symbols without direct margin info
            double price = SymbolInfoDouble(symbol, SYMBOL_BID);
            marginRequired = (price * lotSize * contractSize) / 50.0; // 2% margin estimate
            PositionDebugLog("POSITION-MARGIN-DETAILS", 
                        StringFormat("Alternative calculation: %.2f × %.3f × %.0f / 50 = $%.2f", 
                                    price, lotSize, contractSize, marginRequired));
        }
        
        // Special handling for XAUUSD/Gold
        if(symbol == "XAUUSD" || symbol == "GOLD")
        {
            PositionDebugLog("POSITION-MARGIN-GOLD", "⚠️ Gold detected - applying margin multiplier");
            double goldMultiplier = 5.0; // Gold typically requires 5x more margin
            marginRequired *= goldMultiplier;
            PositionDebugLog("POSITION-MARGIN-GOLD", 
                        StringFormat("Gold margin: $%.2f × %.1f = $%.2f", 
                                    marginRequired/goldMultiplier, goldMultiplier, marginRequired));
        }
        
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double marginLevel = (equity > 0) ? (freeMargin / equity) * 100 : 0;
        
        bool result = marginRequired <= freeMargin * safetyBuffer;
        
        PositionDebugLog("POSITION-MARGIN", StringFormat("Margin: Required: $%.2f | Free: $%.2f | Equity: $%.2f | Level: %.1f%%",
                                            marginRequired, freeMargin, equity, marginLevel));
        
        if(!result)
        {
            PositionDebugLog("POSITION-MARGIN", StringFormat("❌ Margin check failed: Required $%.2f > Available $%.2f (%.0f%%)",
                                                marginRequired, freeMargin * safetyBuffer, safetyBuffer * 100));
        }
        else
        {
            PositionDebugLog("POSITION-MARGIN", "✅ Margin check passed");
        }
        
        return result;
    }
    
    double GetEntryPrice(string symbol, bool isBuy)
    {
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double price = isBuy ? ask : bid;
        
        PositionDebugLog("POSITION-PRICE", StringFormat("Getting entry price for %s: %s | Bid: %.5f | Ask: %.5f | Price: %.5f",
                                       symbol, isBuy ? "BUY" : "SELL", bid, ask, price));
        
        return price;
    }
    
    // ==================== PRIVATE CLOSE HELPERS ====================
    
    bool CloseSmallestProfit(int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-CLOSE-HELPER", "Starting CloseSmallestProfit...");
        double smallestProfit = DBL_MAX;
        ulong ticketToClose = 0;
        double volumeToClose = 0;
        int positionType = -1;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magic != 0 && posMagic != magic) continue;
                
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Evaluating %s: %.3f lots | Profit: $%.2f | Ticket: %d",
                                                    symbol, volume, profit, ticket));
                
                if(MathAbs(profit) < MathAbs(smallestProfit))
                {
                    smallestProfit = profit;
                    ticketToClose = ticket;
                    outClosedSymbol = symbol;
                    volumeToClose = volume;
                    positionType = (int)PositionGetInteger(POSITION_TYPE);
                    PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("New smallest profit: %s $%.2f", symbol, profit));
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Closing %s: %.3f lots | Profit: $%.2f | Type: %s",
                                                 outClosedSymbol, volumeToClose, smallestProfit,
                                                 positionType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
            
            CTrade trade;
            if(trade.PositionClose(ticketToClose))
            {
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("✅ Closed smallest profit: %s $%.2f", 
                                                    outClosedSymbol, smallestProfit));
                Logger::Log("PositionManager", 
                           StringFormat("Closed smallest profit (%s): $%.2f", outClosedSymbol, smallestProfit),
                           false, false);
                return true;
            }
            else
            {
                int errorCode = GetLastError();
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("❌ Failed to close: Error %d", errorCode));
                outClosedSymbol = "";
                return false;
            }
        }
        
        outClosedSymbol = "";
        PositionDebugLog("POSITION-CLOSE-HELPER", "❌ No positions to close");
        return false;
    }
    
    bool CloseBiggestLoss(int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-CLOSE-HELPER", "Starting CloseBiggestLoss...");
        double biggestLoss = DBL_MAX;
        ulong ticketToClose = 0;
        double volumeToClose = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magic != 0 && posMagic != magic) continue;
                
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Evaluating %s: %.3f lots | Profit: $%.2f", symbol, volume, profit));
                
                if(profit < 0 && profit < biggestLoss)
                {
                    biggestLoss = profit;
                    ticketToClose = ticket;
                    outClosedSymbol = symbol;
                    volumeToClose = volume;
                    PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("New biggest loss: %s $%.2f", symbol, profit));
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Closing biggest loss: %s: %.3f lots | Loss: $%.2f",
                                                 outClosedSymbol, volumeToClose, biggestLoss));
            
            CTrade trade;
            if(trade.PositionClose(ticketToClose))
            {
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("✅ Closed biggest loss: %s $%.2f", 
                                                    outClosedSymbol, biggestLoss));
                Logger::Log("PositionManager", 
                           StringFormat("Closed biggest loss (%s): $%.2f", outClosedSymbol, biggestLoss),
                           true, true);
                return true;
            }
            else
            {
                int errorCode = GetLastError();
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("❌ Failed to close: Error %d", errorCode));
                outClosedSymbol = "";
                return false;
            }
        }
        
        outClosedSymbol = "";
        PositionDebugLog("POSITION-CLOSE-HELPER", "❌ No positions to close (no losses found)");
        return false;
    }
    
    bool CloseSmallestLoss(int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-CLOSE-HELPER", "Starting CloseSmallestLoss...");
        double smallestLoss = 0;
        ulong ticketToClose = 0;
        double volumeToClose = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magic != 0 && posMagic != magic) continue;
                
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Evaluating %s: %.3f lots | Profit: $%.2f", symbol, volume, profit));
                
                if(profit < 0 && profit > smallestLoss)
                {
                    smallestLoss = profit;
                    ticketToClose = ticket;
                    outClosedSymbol = symbol;
                    volumeToClose = volume;
                    PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("New smallest loss: %s $%.2f", symbol, profit));
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Closing smallest loss: %s: %.3f lots | Loss: $%.2f",
                                                 outClosedSymbol, volumeToClose, smallestLoss));
            
            CTrade trade;
            if(trade.PositionClose(ticketToClose))
            {
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("✅ Closed smallest loss: %s $%.2f", 
                                                    outClosedSymbol, smallestLoss));
                Logger::Log("PositionManager", 
                           StringFormat("Closed smallest loss (%s): $%.2f", outClosedSymbol, smallestLoss),
                           false, false);
                return true;
            }
            else
            {
                int errorCode = GetLastError();
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("❌ Failed to close: Error %d", errorCode));
                outClosedSymbol = "";
                return false;
            }
        }
        
        outClosedSymbol = "";
        PositionDebugLog("POSITION-CLOSE-HELPER", "❌ No positions to close (no losses found)");
        return false;
    }
    
    bool CloseOldest(int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-CLOSE-HELPER", "Starting CloseOldest...");
        datetime oldestTime = D'3000.01.01';
        ulong ticketToClose = 0;
        double volumeToClose = 0;
        double profitToClose = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magic != 0 && posMagic != magic) continue;
                
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Evaluating %s: Opened %s | Profit: $%.2f",
                                                    symbol, TimeToString(openTime), profit));
                
                if(openTime < oldestTime)
                {
                    oldestTime = openTime;
                    ticketToClose = ticket;
                    outClosedSymbol = symbol;
                    volumeToClose = volume;
                    profitToClose = profit;
                    PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("New oldest: %s opened %s", symbol, TimeToString(openTime)));
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Closing oldest: %s opened %s | Profit: $%.2f",
                                                 outClosedSymbol, TimeToString(oldestTime), profitToClose));
            
            CTrade trade;
            if(trade.PositionClose(ticketToClose))
            {
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("✅ Closed oldest: %s opened %s | P/L: $%.2f", 
                                                    outClosedSymbol, TimeToString(oldestTime), profitToClose));
                Logger::Log("PositionManager", 
                           StringFormat("Closed oldest position (%s): $%.2f", outClosedSymbol, profitToClose),
                           false, false);
                return true;
            }
            else
            {
                int errorCode = GetLastError();
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("❌ Failed to close: Error %d", errorCode));
                outClosedSymbol = "";
                return false;
            }
        }
        
        outClosedSymbol = "";
        PositionDebugLog("POSITION-CLOSE-HELPER", "❌ No positions to close");
        return false;
    }
    
    bool CloseNewest(int magic, string &outClosedSymbol)
    {
        PositionDebugLog("POSITION-CLOSE-HELPER", "Starting CloseNewest...");
        datetime newestTime = 0;
        ulong ticketToClose = 0;
        double volumeToClose = 0;
        double profitToClose = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                if(magic != 0 && posMagic != magic) continue;
                
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Evaluating %s: Opened %s | Profit: $%.2f",
                                                    symbol, TimeToString(openTime), profit));
                
                if(openTime > newestTime)
                {
                    newestTime = openTime;
                    ticketToClose = ticket;
                    outClosedSymbol = symbol;
                    volumeToClose = volume;
                    profitToClose = profit;
                    PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("New newest: %s opened %s", symbol, TimeToString(openTime)));
                }
            }
        }
        
        if(ticketToClose > 0)
        {
            PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("Closing newest: %s opened %s | Profit: $%.2f",
                                                 outClosedSymbol, TimeToString(newestTime), profitToClose));
            
            CTrade trade;
            if(trade.PositionClose(ticketToClose))
            {
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("✅ Closed newest: %s opened %s | P/L: $%.2f", 
                                                    outClosedSymbol, TimeToString(newestTime), profitToClose));
                Logger::Log("PositionManager", 
                           StringFormat("Closed newest position (%s): $%.2f", outClosedSymbol, profitToClose),
                           false, false);
                return true;
            }
            else
            {
                int errorCode = GetLastError();
                PositionDebugLog("POSITION-CLOSE-HELPER", StringFormat("❌ Failed to close: Error %d", errorCode));
                outClosedSymbol = "";
                return false;
            }
        }
        
        outClosedSymbol = "";
        PositionDebugLog("POSITION-CLOSE-HELPER", "❌ No positions to close");
        return false;
    }

    // ==================== TRADE PACKAGE POSITION OPENING ====================
    
    bool OpenPositionWithTradePackage(string symbol, bool isBuy, DecisionEngineInterface &package, int magic = 0)
    {
        PositionDebugLog("POSITION-PACKAGE", StringFormat("=== OPENING WITH TRADE PACKAGE INTERFACE === | Symbol: %s | Buy: %s | Magic: %d | Conf: %.1f%%",
                                            symbol, isBuy ? "YES" : "NO", magic, package.overallConfidence));
        
        // Extract values from Interface (mapped from TradePackage)
        string comment = package.signalReason;
        double riskPercent = 2.0; // Default, can be configured or passed
        double rrRatio = 1.5;    // Default, can be configured or passed
        
        PositionDebugLog("POSITION-PACKAGE", StringFormat("Interface details - Dir: %s | Entry: %.5f | SL: %.5f | TP1: %.5f",
                                            package.dominantDirection, package.entryPrice, 
                                            package.stopLoss, package.takeProfit1));
        
        PositionDebugLog("POSITION-PACKAGE", StringFormat("Signal - Reason: %s | Confidence: %.1f%% | MTF: B%d/S%d",
                                            package.signalReason, package.overallConfidence, 
                                            package.mtfBullishCount, package.mtfBearishCount));
        
        // Use default stop method
        ENUM_STOP_METHOD stopMethod = STOP_ATR;  // Default
        
        // If Interface has setup information, use it for more precise entry
        double entryPrice = 0;
        double stopLoss = 0;
        double takeProfit = 0;
        
        if(package.entryPrice > 0 && package.stopLoss > 0) {
            entryPrice = package.entryPrice;
            stopLoss = package.stopLoss;
            takeProfit = package.takeProfit1;
            PositionDebugLog("POSITION-PACKAGE", "✅ Using Interface setup values");
        } else {
            PositionDebugLog("POSITION-PACKAGE", "⚠️ Interface setup NOT fully specified - using market prices");
        }
        
        // Check if we should use the signal order type from the Interface
        ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        if(package.orderType == ORDER_TYPE_BUY && !isBuy) {
            PositionDebugLog("POSITION-PACKAGE", "⚠️ Signal conflict: Interface suggests BUY but decision is SELL");
        } else if(package.orderType == ORDER_TYPE_SELL && isBuy) {
            PositionDebugLog("POSITION-PACKAGE", "⚠️ Signal conflict: Interface suggests SELL but decision is BUY");
        }
        
        bool result = OpenPosition(
            symbol, 
            isBuy, 
            comment, 
            magic,                 // Required parameter
            stopMethod,            // Required parameter
            riskPercent,           // Required parameter
            rrRatio,               // Required parameter
            "TradePackageInterface", // Reason
            entryPrice,            // Optional: specific entry
            stopLoss,              // Optional: specific stop loss
            takeProfit             // Optional: specific take profit
        );
        
        PositionDebugLog("POSITION-PACKAGE", StringFormat("Interface execution result: %s", result ? "✅ SUCCESS" : "❌ FAILED"));
        
        if(result) {
            Logger::Log("PositionManager", 
                        StringFormat("Interface executed: %s %s (Confidence: %.1f%%, Dir: %s)",
                                    symbol, isBuy ? "BUY" : "SELL", 
                                    package.overallConfidence, package.dominantDirection),
                        true, true);
        } else {
            Logger::LogError("PositionManager", 
                        StringFormat("Failed to execute interface: %s %s (Confidence: %.1f%%)",
                                    symbol, isBuy ? "BUY" : "SELL", package.overallConfidence));
        }
        
        return result;
    }
}