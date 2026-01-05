//+------------------------------------------------------------------+
//|                     RiskCalculator.mqh                           |
//|              Pure Functions for Risk Calculations                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include <Trade/Trade.mqh>
#include "../Headers/Enums.mqh"
#include "../Utils/MathUtils.mqh"
#include "../Data/IndicatorManager.mqh"

// ==================== DEBUG SETTINGS ====================
bool RISK_DEBUG_ENABLED = true;

// Simple debug function using Logger
void RiskDebugLog(string context, string message) {
   if(RISK_DEBUG_ENABLED) {
      Logger::Log(context, message, true, true);
   }
}

// ==================== ENUMERATIONS ====================
enum ENUM_RISK_LEVEL {
    RISK_CRITICAL,   // Stop all trading
    RISK_HIGH,       // Reduce position sizes
    RISK_MODERATE,   // Normal trading
    RISK_LOW,        // Conservative
    RISK_OPTIMAL     // Ideal conditions
};

enum ENUM_TRAIL_METHOD {
    TRAIL_STRUCTURE,    // Structural trailing (swing highs/lows)
    TRAIL_FIXED,        // Fixed distance
    TRAIL_ATR,          // ATR-based
    TRAIL_BOLLINGER     // Bollinger Bands
};

// ==================== STRUCTURES ====================
struct PriceStructure {
    double swingHigh;
    double swingLow;
    datetime timeHigh;
    datetime timeLow;
};

// ==================== GLOBAL INSTANCES ====================
   IndicatorManager *globalIndManager = NULL;

// ==================== INITIALIZATION FUNCTIONS ====================
void InitializeRiskCalculator(string symbol = NULL) {
    if(globalIndManager == NULL) {
        globalIndManager = new IndicatorManager(symbol);
        if(globalIndManager.Initialize()) {
            RiskDebugLog("RISK-INIT", "✅ IndicatorManager initialized successfully");
        } else {
            RiskDebugLog("RISK-INIT", "❌ Failed to initialize IndicatorManager");
            delete globalIndManager;
            globalIndManager = NULL;
        }
    }
}

void DeinitializeRiskCalculator() {
    if(globalIndManager != NULL) {
        globalIndManager.Deinitialize();
        delete globalIndManager;
        globalIndManager = NULL;
        RiskDebugLog("RISK-INIT", "✅ IndicatorManager deinitialized");
    }
}

// ==================== HELPER FUNCTIONS ====================
string TimeframeToString(ENUM_TIMEFRAMES tf) {
    switch(tf) {
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

double NormalizePrice(const string symbol, double price) {
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    if(tickSize > 0) {
        double normalized = NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
        RiskDebugLog("RISK-NORMALIZE", StringFormat("Normalized %.5f -> %.5f (tick size: %.5f, digits: %d)",
                               price, normalized, tickSize, digits));
        return normalized;
    }
    
    double normalized = NormalizeDouble(price, digits);
    RiskDebugLog("RISK-NORMALIZE", StringFormat("Normalized %.5f -> %.5f (digits: %d)", price, normalized, digits));
    return normalized;
}

double GetPipValue(string symbol, double lotSize) {
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(tickSize > 0 && point > 0)
        return (tickValue * lotSize * point) / tickSize;
    
    return 0;
}

// ==================== STRUCTURE FUNCTIONS ====================
PriceStructure GetRecentStructure(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1, int lookback = 50) {
    PriceStructure structure;
    structure.swingHigh = 0;
    structure.swingLow = DBL_MAX;
    structure.timeHigh = 0;
    structure.timeLow = D'3000.01.01';
    
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    
    int barsNeeded = MathMin(lookback, iBars(symbol, timeframe));
    if(CopyHigh(symbol, timeframe, 0, barsNeeded, highs) < barsNeeded ||
       CopyLow(symbol, timeframe, 0, barsNeeded, lows) < barsNeeded) {
        return structure;
    }
    
    for(int i = 2; i < barsNeeded - 2; i++) {
        // Check for swing high (high > left and right)
        if(highs[i] > highs[i+1] && highs[i] > highs[i+2] &&
           highs[i] > highs[i-1] && highs[i] > highs[i-2]) {
            if(highs[i] > structure.swingHigh) {
                structure.swingHigh = highs[i];
                structure.timeHigh = iTime(symbol, timeframe, i);
            }
        }
        
        // Check for swing low (low < left and right)
        if(lows[i] < lows[i+1] && lows[i] < lows[i+2] &&
           lows[i] < lows[i-1] && lows[i] < lows[i-2]) {
            if(lows[i] < structure.swingLow) {
                structure.swingLow = lows[i];
                structure.timeLow = iTime(symbol, timeframe, i);
            }
        }
    }
    
    return structure;
}

double FindRecentSwingLow(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50) {
    double lows[];
    ArraySetAsSeries(lows, true);
    
    int barsNeeded = lookback * 3;
    if(CopyLow(symbol, timeframe, 0, barsNeeded, lows) < barsNeeded)
        return 0;
    
    for(int i = 2; i < lookback; i++) {
        if(lows[i] < lows[i-1] && lows[i] < lows[i-2] && 
           lows[i] < lows[i+1] && lows[i] < lows[i+2]) {
            return lows[i];
        }
    }
    
    return 0;
}

double FindRecentSwingHigh(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50) {
    double highs[];
    ArraySetAsSeries(highs, true);
    
    int barsNeeded = lookback * 3;
    if(CopyHigh(symbol, timeframe, 0, barsNeeded, highs) < barsNeeded)
        return 0;
    
    for(int i = 2; i < lookback; i++) {
        if(highs[i] > highs[i-1] && highs[i] > highs[i-2] && 
           highs[i] > highs[i+1] && highs[i] > highs[i+2]) {
            return highs[i];
        }
    }
    
    return 0;
}

// ==================== RISK CALCULATOR NAMESPACE ====================
namespace RiskCalculator {

    // ==================== RISK VALIDATION ====================
    bool CanOpenTrade(double maxDailyLossPercent = 5.0, double maxDrawdownPercent = 20.0) {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        RiskDebugLog("RISK-VALIDATION", StringFormat("Account: Balance=$%.2f, Equity=$%.2f", accountBalance, equity));
        
        if(accountBalance > 0) {
            double drawdownPercent = ((accountBalance - equity) / accountBalance) * 100;
            RiskDebugLog("RISK-VALIDATION", StringFormat("Drawdown: %.1f%% (Max: %.1f%%)", drawdownPercent, maxDrawdownPercent));
            
            if(drawdownPercent > maxDrawdownPercent) {
                RiskDebugLog("RISK-VALIDATION", "❌ Max drawdown exceeded");
                return false;
            }
        }
        
        RiskDebugLog("RISK-VALIDATION", "✅ Risk validation passed");
        return true;
    }
    
    // ==================== POSITION SIZE CALCULATION ====================
    double CalculatePositionSize(string symbol, double entryPrice, double stopLoss, 
                                double riskPercent = 2.0) {
        RiskDebugLog("RISK-SIZE", StringFormat("=== CALCULATING POSITION SIZE === | Symbol: %s | Entry: %.5f | SL: %.5f | Risk: %.1f%%",
                              symbol, entryPrice, stopLoss, riskPercent));
        
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (riskPercent / 100.0);
        double riskPerLot = MathAbs(entryPrice - stopLoss) * 
                           SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        RiskDebugLog("RISK-SIZE", StringFormat("Account: $%.2f | Risk amount: $%.2f | Risk per lot: $%.2f",
                              accountBalance, riskAmount, riskPerLot));
        
        if(riskPerLot <= 0) {
            RiskDebugLog("RISK-SIZE", "❌ Invalid risk per lot");
            return 0.0;
        }
        
        double lots = riskAmount / riskPerLot;
        RiskDebugLog("RISK-SIZE", StringFormat("Raw lot size: %.3f", lots));
        
        // Apply symbol constraints
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        RiskDebugLog("RISK-SIZE", StringFormat("Constraints: Min=%.3f, Max=%.3f, Step=%.3f", minLot, maxLot, lotStep));
        
        lots = MathMax(lots, minLot);
        lots = MathMin(lots, maxLot);
        
        if(lotStep > 0) {
            double beforeNormalization = lots;
            lots = MathRound(lots / lotStep) * lotStep;
            RiskDebugLog("RISK-SIZE", StringFormat("Normalized: %.3f -> %.3f", beforeNormalization, lots));
        }
        
        RiskDebugLog("RISK-SIZE", StringFormat("✅ Final lot size: %.3f", lots));
        return NormalizeDouble(lots, 2);
    }
    
    // ==================== STOP LOSS CALCULATIONS ====================
    double CalculateStopLoss(string symbol, bool isBuy, double entryPrice,
                         double atrMultiplier = 2.0,
                         ENUM_TIMEFRAMES timeframe = PERIOD_H1) {
        static IndicatorManager indManager(symbol);
        
        Logger::Log("Risk", StringFormat("Calculating stop for %s (%s)...", 
            symbol, isBuy ? "BUY" : "SELL"));
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        Logger::Log("Risk", StringFormat("%s: Entry=%.5f, Point=%.5f, Digits=%d", 
            symbol, entryPrice, point, digits));
        
        ENUM_TIMEFRAMES atrTimeframe = timeframe;
        
        // Adjust timeframe for volatile symbols
        if(symbol == "XAUUSD" || symbol == "GOLD" || 
           symbol == "XAGUSD" || symbol == "SILVER" ||
           symbol == "BTCUSD" || symbol == "ETHUSD" ||
           StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0) {
            if(timeframe < PERIOD_M15) {
                atrTimeframe = PERIOD_M15;
            }
        } else {
            if(timeframe == PERIOD_M1 || timeframe == PERIOD_M5) {
                atrTimeframe = PERIOD_M15;
            }
        }
        
        double atrValue = indManager.GetATR(atrTimeframe, 0);
        
        if(isBuy) {
            double swingLow = FindRecentSwingLow(symbol, atrTimeframe);
            if(swingLow <= 0) {
                double atrStop = entryPrice - (atrValue * atrMultiplier);
                atrStop = NormalizeStopPrice(symbol, atrStop, isBuy, entryPrice);
                return atrStop;
            }
            
            double buffer = CalculateStopBuffer(symbol, atrValue, point, isBuy);
            double stop = swingLow - buffer;
            stop = ValidateAndAdjustStop(symbol, isBuy, entryPrice, stop, atrTimeframe);
            
            return stop;
        } else {
            double swingHigh = FindRecentSwingHigh(symbol, atrTimeframe);
            if(swingHigh <= 0) {
                double atrStop = entryPrice + (atrValue * atrMultiplier);
                atrStop = NormalizeStopPrice(symbol, atrStop, isBuy, entryPrice);
                return atrStop;
            }
            
            double buffer = CalculateStopBuffer(symbol, atrValue, point, isBuy);
            double stop = swingHigh + buffer;
            stop = ValidateAndAdjustStop(symbol, isBuy, entryPrice, stop, atrTimeframe);
            
            return stop;
        }
    }
    
    double CalculateStopBuffer(string symbol, double atrValue, double point, bool isBuy) {
        double buffer = atrValue * 0.5;
        double minBuffer = GetMinBuffer(symbol, point, isBuy);
        
        if(buffer < minBuffer) {
            buffer = minBuffer;
        }
        
        return buffer;
    }
    
    double GetMinBuffer(string symbol, double point, bool isBuy) {
        if(symbol == "XAUUSD" || symbol == "GOLD")
            return 1.00;
        else if(symbol == "XAGUSD" || symbol == "SILVER")
            return 0.20;
        else if(symbol == "BTCUSD" || symbol == "ETHUSD" || 
                StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0)
            return 50.0;
        else
            return 10 * point;
    }
    
    double ValidateAndAdjustStop(string symbol, bool isBuy, double entryPrice, double stop, ENUM_TIMEFRAMES tf) {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        double minDistancePips = 0;
        double maxDistancePips = 0;
        
        if(symbol == "XAUUSD" || symbol == "GOLD") {
            minDistancePips = 150;
            maxDistancePips = 2000;
        } else if(symbol == "XAGUSD" || symbol == "SILVER") {
            minDistancePips = 30;
            maxDistancePips = 300;
        } else if(symbol == "BTCUSD" || symbol == "ETHUSD" ||
                StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0) {
            minDistancePips = 50;
            maxDistancePips = 500;
        } else {
            minDistancePips = 15;
            maxDistancePips = 200;
        }
        
        if(tf >= PERIOD_H1) {
            minDistancePips *= 1.5;
            maxDistancePips *= 1.5;
        }
        
        double minDistance = minDistancePips * point;
        double maxDistance = maxDistancePips * point;
        double currentDistance = isBuy ? (entryPrice - stop) : (stop - entryPrice);
        
        if(currentDistance < minDistance) {
            if(isBuy)
                stop = entryPrice - minDistance;
            else
                stop = entryPrice + minDistance;
        }
        
        if(currentDistance > maxDistance) {
            if(isBuy)
                stop = entryPrice - maxDistance;
            else
                stop = entryPrice + maxDistance;
        }
        
        stop = NormalizeDouble(stop, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
        return stop;
    }
    
    double NormalizeStopPrice(string symbol, double price, bool isBuy, double entryPrice) {
        if((isBuy && price >= entryPrice) || (!isBuy && price <= entryPrice)) {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double minDistance = GetMinBuffer(symbol, point, isBuy);
            
            if(isBuy)
                price = entryPrice - minDistance;
            else
                price = entryPrice + minDistance;
        }
        
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        price = NormalizeDouble(price, digits);
        return price;
    }
    
    // ==================== TAKE PROFIT CALCULATIONS ====================
    double CalculateTakeProfit(string symbol, bool isBuy, double entryPrice,
                          double stopLoss, double rrRatio = 2.0) {
        RiskDebugLog("RISK-TP", StringFormat("=== CALCULATING TAKE PROFIT === | Symbol: %s | %s @ %.5f | SL: %.5f | RR: %.1f",
                            symbol, isBuy ? "BUY" : "SELL", entryPrice, stopLoss, rrRatio));
        
        if(rrRatio <= 0) {
            RiskDebugLog("RISK-TP-ERROR", StringFormat("❌ Invalid RR Ratio: %.1f. Using default 1.5", rrRatio));
            rrRatio = 1.5;
        }
        
        double risk = MathAbs(entryPrice - stopLoss);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double riskPips = risk / point;
        
        if(riskPips < 1.0) {
            risk = 200 * point;
        }
        
        double reward = risk * rrRatio;
        double tpPrice = isBuy ? entryPrice + reward : entryPrice - reward;
        double normalizedPrice = NormalizePrice(symbol, tpPrice);
        
        return normalizedPrice;
    }
    
    // ==================== STRUCTURAL TRAILING STOP CALCULATION ====================
    // REPLACING THE OLD CalculateTrailingStop FUNCTION
    double CalculateTrailingStop(string symbol, bool isBuy, double entryPrice,
                                double currentPrice, double currentSL, 
                                ENUM_TRAIL_METHOD method = TRAIL_STRUCTURE,
                                ENUM_TIMEFRAMES timeframe = PERIOD_H1) {
        
        RiskDebugLog("RISK-TRAIL", StringFormat("=== STRUCTURAL TRAILING STOP === | Symbol: %s | %s | Entry: %.5f | Current: %.5f | Current SL: %.5f | TF: %s",
                               symbol, isBuy ? "BUY" : "SELL", entryPrice, currentPrice, currentSL, TimeframeToString(timeframe)));
        
        // Only use structural trailing method
        if(method != TRAIL_STRUCTURE) {
            RiskDebugLog("RISK-TRAIL", "⚠️ Only structural trailing supported, using structure method");
        }
        
        double newSL = currentSL;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // Get recent price structure
        PriceStructure structure = GetRecentStructure(symbol, timeframe, 100);
        
        RiskDebugLog("RISK-TRAIL-STRUCTURE", 
            StringFormat("Recent structure - High: %.5f (Time: %s), Low: %.5f (Time: %s)",
            structure.swingHigh, TimeToString(structure.timeHigh),
            structure.swingLow, TimeToString(structure.timeLow)));
        
        if(isBuy) {
            // For BUY positions: Move SL to last swing LOW + buffer
            if(structure.swingLow > 0 && structure.swingLow < DBL_MAX) {
                // Calculate buffer based on ATR or fixed distance
                double atrValue = GetATR(symbol, timeframe, 0);
                double buffer = MathMax(atrValue * 0.5, 10 * point); // Half ATR or 10 pips, whichever is larger
                
                newSL = structure.swingLow - buffer;
                
                RiskDebugLog("RISK-TRAIL-BUY", 
                    StringFormat("BUY: Swing low at %.5f - buffer %.5f = new SL %.5f", 
                    structure.swingLow, buffer, newSL));
                
                // Check if price has moved significantly from entry
                double distanceFromEntry = currentPrice - entryPrice;
                if(distanceFromEntry > atrValue * 1.5) { // Only trail if we have good profit
                    RiskDebugLog("RISK-TRAIL-BUY", 
                        StringFormat("Good profit: %.5f from entry (ATR: %.5f)", 
                        distanceFromEntry, atrValue));
                } else {
                    RiskDebugLog("RISK-TRAIL-BUY", 
                        "Not enough profit to trail yet, keeping current SL");
                    return currentSL;
                }
            }
        } else {
            // For SELL positions: Move SL to last swing HIGH + buffer
            if(structure.swingHigh > 0) {
                double atrValue = GetATR(symbol, timeframe, 0);
                double buffer = MathMax(atrValue * 0.5, 10 * point);
                
                newSL = structure.swingHigh + buffer;
                
                RiskDebugLog("RISK-TRAIL-SELL", 
                    StringFormat("SELL: Swing high at %.5f + buffer %.5f = new SL %.5f", 
                    structure.swingHigh, buffer, newSL));
                
                // Check if price has moved significantly from entry
                double distanceFromEntry = entryPrice - currentPrice;
                if(distanceFromEntry > atrValue * 1.5) {
                    RiskDebugLog("RISK-TRAIL-SELL", 
                        StringFormat("Good profit: %.5f from entry (ATR: %.5f)", 
                        distanceFromEntry, atrValue));
                } else {
                    RiskDebugLog("RISK-TRAIL-SELL", 
                        "Not enough profit to trail yet, keeping current SL");
                    return currentSL;
                }
            }
        }
        
        // Normalize the new SL
        newSL = NormalizePrice(symbol, newSL);
        
        // Validate the new SL makes sense
        if(isBuy) {
            if(newSL > currentSL && newSL < currentPrice && newSL < entryPrice) {
                RiskDebugLog("RISK-TRAIL", StringFormat("✅ BUY: Moving SL up from %.5f to %.5f", currentSL, newSL));
                return newSL;
            }
        } else {
            if(newSL < currentSL && newSL > currentPrice && newSL > entryPrice) {
                RiskDebugLog("RISK-TRAIL", StringFormat("✅ SELL: Moving SL down from %.5f to %.5f", currentSL, newSL));
                return newSL;
            }
        }
        
        RiskDebugLog("RISK-TRAIL", "⚠️ No valid structural trailing improvement found");
        return currentSL;
    }
    
    // ==================== RISK ANALYSIS ====================
    double CalculateRiskRewardRatio(double entry, double stop, double target) {
        double risk = MathAbs(entry - stop);
        double reward = MathAbs(target - entry);
        
        if(risk <= 0) return 0.0;
        
        double rr = reward / risk;
        RiskDebugLog("RISK-RR", StringFormat("RR Ratio: Entry=%.5f, SL=%.5f, TP=%.5f -> Risk=%.5f, Reward=%.5f, RR=%.2f",
                            entry, stop, target, risk, reward, rr));
        return rr;
    }
    
    double CalculateRiskAmount(string symbol, double entry, double stop, double lots) {
        double riskPerLot = MathAbs(entry - stop) * 
                           SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        double totalRisk = riskPerLot * lots;
        
        RiskDebugLog("RISK-AMOUNT", StringFormat("Risk amount: %.3f lots * $%.2f per lot = $%.2f",
                                lots, riskPerLot, totalRisk));
        return totalRisk;
    }
    
    ENUM_RISK_LEVEL GetCurrentRiskLevel(double maxDrawdownPercent = 20.0) {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        if(accountBalance <= 0) return RISK_CRITICAL;
        
        double drawdownPercent = ((accountBalance - equity) / accountBalance) * 100;
        
        RiskDebugLog("RISK-LEVEL", StringFormat("Drawdown: %.1f%% | Max: %.1f%%", drawdownPercent, maxDrawdownPercent));
        
        if(drawdownPercent >= maxDrawdownPercent) return RISK_CRITICAL;
        if(drawdownPercent >= maxDrawdownPercent * 0.75) return RISK_HIGH;
        if(drawdownPercent >= maxDrawdownPercent * 0.5) return RISK_MODERATE;
        if(drawdownPercent >= maxDrawdownPercent * 0.25) return RISK_LOW;
        
        return RISK_OPTIMAL;
    }
    
    ENUM_RISK_LEVEL GetMarketRiskLevel(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) {
        RiskDebugLog("RISK-MARKET-LEVEL", StringFormat("Getting market risk level for %s (TF: %d)...", symbol, timeframe));
        
        IndicatorManager indManager(symbol);
        if(!indManager.Initialize()) {
            RiskDebugLog("RISK-MARKET-LEVEL", "❌ Failed to initialize IndicatorManager");
            return RISK_MODERATE;
        }
        
        double atr = indManager.GetATR(timeframe, 0);
        double adx, plus_di, minus_di;
        indManager.GetADXValues(timeframe, adx, plus_di, minus_di, 0);
        double rsi = indManager.GetRSI(timeframe, 0);
        
        int riskScore = 0;
        
        if(atr > 0.002) riskScore += 2;
        else if(atr < 0.0005) riskScore -= 1;
        
        if(adx > 25) riskScore += 1;
        else if(adx < 20) riskScore += 2;
        
        if(rsi > 70 || rsi < 30) riskScore += 1;
        
        RiskDebugLog("RISK-MARKET-LEVEL", StringFormat("Market risk score: %d (ATR=%.5f, ADX=%.1f, RSI=%.1f)", 
                          riskScore, atr, adx, rsi));
        
        if(riskScore >= 4) return RISK_HIGH;
        if(riskScore >= 2) return RISK_MODERATE;
        if(riskScore >= 0) return RISK_LOW;
        
        return RISK_OPTIMAL;
    }
    
    double GetATR(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0) {
        RiskDebugLog("RISK-ATR", StringFormat("Getting ATR for %s on TF %d shift %d...", 
                                              symbol, timeframe, shift));
        
        if(globalIndManager != NULL) {
            double atrValue = globalIndManager.GetATR(timeframe, shift);
            if(atrValue > 0) {
                RiskDebugLog("RISK-ATR", StringFormat("ATR from global instance: %.5f", atrValue));
                return atrValue;
            }
        }
        
        IndicatorManager indManager(symbol);
        if(!indManager.Initialize()) {
            RiskDebugLog("RISK-ATR", "❌ Failed to initialize IndicatorManager");
            return 0.0;
        }
        
        double atrValue = indManager.GetATR(timeframe, shift);
        RiskDebugLog("RISK-ATR", StringFormat("ATR value: %.5f", atrValue));
        return atrValue;
    }
    
    double GetMarketConfidence(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1) {
        RiskDebugLog("RISK-CONFIDENCE", StringFormat("Getting market confidence for %s (TF: %d)...", symbol, timeframe));
        
        IndicatorManager indManager(symbol);
        if(!indManager.Initialize()) {
            RiskDebugLog("RISK-CONFIDENCE", "❌ Failed to initialize IndicatorManager");
            return 50.0;
        }
        
        double confidence = 50.0;
        
        double adx, plus_di, minus_di;
        indManager.GetADXValues(timeframe, adx, plus_di, minus_di, 0);
        if(adx > 25) confidence += 20;
        else if(adx < 20) confidence -= 10;
        
        double rsi = indManager.GetRSI(timeframe, 0);
        if((rsi > 30 && rsi < 70)) confidence += 10;
        else confidence -= 10;
        
        int bullish_tf_count, bearish_tf_count;
        indManager.GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
        if(bullish_tf_count > bearish_tf_count + 1 || bearish_tf_count > bullish_tf_count + 1)
            confidence += 15;
        
        confidence = MathMax(0, MathMin(100, confidence));
        
        RiskDebugLog("RISK-CONFIDENCE", StringFormat("Market confidence: %.1f%% (ADX=%.1f, RSI=%.1f)", 
                          confidence, adx, rsi));
        
        return confidence;
    }
    
    // ==================== POSITION LIMIT CHECKS ====================
    bool CanAddNewPosition(string symbol, int magic, int maxTotalPositions = 5, int maxPositionsPerSymbol = 2) {
        RiskDebugLog("RISK-POSITION-LIMIT", StringFormat("Checking position limits for %s (Magic: %d)...", symbol, magic));
        
        int totalPositions = 0;
        int symbolPositions = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket)) {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
                
                if(posMagic == magic) {
                    totalPositions++;
                    if(posSymbol == symbol)
                        symbolPositions++;
                }
            }
        }
        
        RiskDebugLog("RISK-POSITION-LIMIT", 
            StringFormat("Current positions: Total=%d/%d, %s=%d/%d", 
                        totalPositions, maxTotalPositions, 
                        symbol, symbolPositions, maxPositionsPerSymbol));
        
        if(totalPositions >= maxTotalPositions) {
            RiskDebugLog("RISK-POSITION-LIMIT", 
                StringFormat("❌ Maximum total positions reached: %d/%d", 
                            totalPositions, maxTotalPositions));
            return false;
        }
        
        if(symbolPositions >= maxPositionsPerSymbol) {
            RiskDebugLog("RISK-POSITION-LIMIT", 
                StringFormat("❌ Maximum positions for %s reached: %d/%d", 
                            symbol, symbolPositions, maxPositionsPerSymbol));
            return false;
        }
        
        RiskDebugLog("RISK-POSITION-LIMIT", "✅ Position limits OK");
        return true;
    }
    
    void GetRecommendedPositionLimits(double accountBalance, int &outMaxTotal, int &outMaxPerSymbol) {
        if(accountBalance < 100) {
            outMaxTotal = 2;
            outMaxPerSymbol = 1;
        } else if(accountBalance < 500) {
            outMaxTotal = 4;
            outMaxPerSymbol = 2;
        } else if(accountBalance < 2000) {
            outMaxTotal = 8;
            outMaxPerSymbol = 2;
        } else if(accountBalance < 5000) {
            outMaxTotal = 10;
            outMaxPerSymbol = 3;
        } else if(accountBalance < 10000) {
            outMaxTotal = 10;
            outMaxPerSymbol = 4;
        } else {
            outMaxTotal = 20;
            outMaxPerSymbol = 4;
        }
        
        RiskDebugLog("RISK-POSITION-LIMIT", 
            StringFormat("Recommended limits for $%.2f account: MaxTotal=%d, MaxPerSymbol=%d", 
                        accountBalance, outMaxTotal, outMaxPerSymbol));
    }
}