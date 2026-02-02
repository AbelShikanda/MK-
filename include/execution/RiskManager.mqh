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
bool RISK_DEBUG_ENABLED = false;

// Simple debug function using Logger
void RiskDebugLog(string context, string message)
{
    if (RISK_DEBUG_ENABLED)
    {
        Logger::Log(context, message, true, true);
    }
}

// ==================== ENUMERATIONS ====================
enum ENUM_RISK_LEVEL
{
    RISK_CRITICAL, // Stop all trading
    RISK_HIGH,     // Reduce position sizes
    RISK_MODERATE, // Normal trading
    RISK_LOW,      // Conservative
    RISK_OPTIMAL   // Ideal conditions
};

enum ENUM_TRAIL_METHOD
{
    TRAIL_STRUCTURE, // Structural trailing (swing highs/lows)
    TRAIL_FIXED,     // Fixed distance
    TRAIL_ATR,       // ATR-based
    TRAIL_BOLLINGER  // Bollinger Bands
};

// ==================== STRUCTURES ====================
struct PriceStructure
{
    double swingHigh;
    double swingLow;
    datetime timeHigh;
    datetime timeLow;
};

// ==================== HELPER FUNCTIONS ====================
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
    default:
        return "TF-" + IntegerToString(tf);
    }
}

double NormalizePrice(const string symbol, double price)
{
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    if (tickSize > 0)
    {
        double normalized = NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
        RiskDebugLog("RISK-NORMALIZE", StringFormat("Normalized %.5f -> %.5f (tick size: %.5f, digits: %d)",
                                                    price, normalized, tickSize, digits));
        return normalized;
    }

    double normalized = NormalizeDouble(price, digits);
    RiskDebugLog("RISK-NORMALIZE", StringFormat("Normalized %.5f -> %.5f (digits: %d)", price, normalized, digits));
    return normalized;
}

double GetPipValue(string symbol, double lotSize)
{
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

    if (tickSize > 0 && point > 0)
        return (tickValue * lotSize * point) / tickSize;

    return 0;
}

// ==================== STRUCTURE FUNCTIONS ====================
PriceStructure GetRecentStructure(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15, int lookback = 50)
{
    PriceStructure structure;
    structure.swingHigh = 0;
    structure.swingLow = DBL_MAX;
    structure.timeHigh = 0;
    structure.timeLow = D'3000.01.01';

    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    int barsNeeded = MathMin(lookback, iBars(symbol, timeframe));
    if (CopyHigh(symbol, timeframe, 0, barsNeeded, highs) < barsNeeded ||
        CopyLow(symbol, timeframe, 0, barsNeeded, lows) < barsNeeded)
    {
        return structure;
    }

    for (int i = 2; i < barsNeeded - 2; i++)
    {
        // Check for swing high (high > left and right)
        if (highs[i] > highs[i + 1] && highs[i] > highs[i + 2] &&
            highs[i] > highs[i - 1] && highs[i] > highs[i - 2])
        {
            if (highs[i] > structure.swingHigh)
            {
                structure.swingHigh = highs[i];
                structure.timeHigh = iTime(symbol, timeframe, i);
            }
        }

        // Check for swing low (low < left and right)
        if (lows[i] < lows[i + 1] && lows[i] < lows[i + 2] &&
            lows[i] < lows[i - 1] && lows[i] < lows[i - 2])
        {
            if (lows[i] < structure.swingLow)
            {
                structure.swingLow = lows[i];
                structure.timeLow = iTime(symbol, timeframe, i);
            }
        }
    }

    return structure;
}

double FindRecentSwingLow(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50)
{
    RiskDebugLog("SWING-LOW", StringFormat("Looking for swing low on %s (%s), lookback=%d",
                                           symbol, TimeframeToString(timeframe), lookback));

    double lows[];
    ArraySetAsSeries(lows, true);

    int barsNeeded = lookback * 3;
    RiskDebugLog("SWING-LOW", StringFormat("Need %d bars", barsNeeded));

    int copied = CopyLow(symbol, timeframe, 0, barsNeeded, lows);
    RiskDebugLog("SWING-LOW", StringFormat("Copied %d/%d low values", copied, barsNeeded));

    if (copied < barsNeeded)
    {
        RiskDebugLog("SWING-LOW-ERROR", StringFormat("❌ Failed to copy enough low values: %d/%d", copied, barsNeeded));
        return 0;
    }

    RiskDebugLog("SWING-LOW-DATA", StringFormat("First few lows: [0]=%.5f, [1]=%.5f, [2]=%.5f, [3]=%.5f, [4]=%.5f",
                                                lows[0], lows[1], lows[2], lows[3], lows[4]));

    for (int i = 2; i < lookback; i++)
    {
        bool isSwingLow = lows[i] < lows[i - 1] && lows[i] < lows[i - 2] &&
                          lows[i] < lows[i + 1] && lows[i] < lows[i + 2];

        if (isSwingLow)
        {
            RiskDebugLog("SWING-LOW-FOUND",
                         StringFormat("✅ Found swing low at bar %d: %.5f (L[%d]=%.5f, L[%d]=%.5f, L[%d]=%.5f, L[%d]=%.5f)",
                                      i, lows[i],
                                      i - 2, lows[i - 2], i - 1, lows[i - 1],
                                      i + 1, lows[i + 1], i + 2, lows[i + 2]));
            return lows[i];
        }
    }

    RiskDebugLog("SWING-LOW", "❌ No swing low found in lookback period");
    return 0;
}

double FindRecentSwingHigh(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 50)
{
    double highs[];
    ArraySetAsSeries(highs, true);

    int barsNeeded = lookback * 3;
    if (CopyHigh(symbol, timeframe, 0, barsNeeded, highs) < barsNeeded)
        return 0;

    for (int i = 2; i < lookback; i++)
    {
        if (highs[i] > highs[i - 1] && highs[i] > highs[i - 2] &&
            highs[i] > highs[i + 1] && highs[i] > highs[i + 2])
        {
            return highs[i];
        }
    }

    return 0;
}

// ==================== RISK CALCULATOR NAMESPACE ====================
namespace RiskCalculator
{
    // ==================== RISK VALIDATION ====================
    bool CanOpenTrade(double maxDailyLossPercent = 5.0, double maxDrawdownPercent = 20.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);

        RiskDebugLog("RISK-VALIDATION", StringFormat("Account: Balance=$%.2f, Equity=$%.2f", accountBalance, equity));

        if (accountBalance > 0)
        {
            double drawdownPercent = ((accountBalance - equity) / accountBalance) * 100;
            RiskDebugLog("RISK-VALIDATION", StringFormat("Drawdown: %.1f%% (Max: %.1f%%)", drawdownPercent, maxDrawdownPercent));

            if (drawdownPercent > maxDrawdownPercent)
            {
                RiskDebugLog("RISK-VALIDATION", "❌ Max drawdown exceeded");
                return false;
            }
        }

        RiskDebugLog("RISK-VALIDATION", "✅ Risk validation passed");
        return true;
    }

    // ==================== POSITION SIZE CALCULATION ====================
    double CalculatePositionSize(string symbol, double entryPrice, double stopLoss,
                                 double riskPercent = 20.0)
    {
        RiskDebugLog("RISK-SIZE", StringFormat("=== CALCULATING POSITION SIZE === | Symbol: %s | Entry: %.5f | SL: %.5f | Risk: %.1f%%",
                                               symbol, entryPrice, stopLoss, riskPercent));

        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (riskPercent / 100.0);
        double riskPerLot = MathAbs(entryPrice - stopLoss) *
                            SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

        RiskDebugLog("RISK-SIZE", StringFormat("Account: $%.2f | Risk amount: $%.2f | Risk per lot: $%.2f",
                                               accountBalance, riskAmount, riskPerLot));

        if (riskPerLot <= 0)
        {
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

        if (lotStep > 0)
        {
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
                             ENUM_TIMEFRAMES timeframe = PERIOD_M15)
    {
        RiskDebugLog("RISK-SL", StringFormat("===== CALCULATE STOP LOSS START =====", ""));
        RiskDebugLog("RISK-SL", StringFormat("Parameters: Symbol=%s, IsBuy=%s, Entry=%.5f, ATRMultiplier=%.1f, Timeframe=%s",
                                             symbol, isBuy ? "BUY" : "SELL", entryPrice, atrMultiplier, TimeframeToString(timeframe)));

        // ✅ USE SINGLETON
        IndicatorManager* indManager = IndicatorManager::Instance();
        if (indManager == NULL)
        {
            RiskDebugLog("RISK-SL", "❌ Failed to get IndicatorManager singleton");
            return 0.0;
        }

        // Ensure singleton is initialized
        if (!indManager.IsInitialized())
        {
            RiskDebugLog("RISK-SL", "⚠️ IndicatorManager not initialized, initializing now...");
            if (!indManager.Initialize())
            {
                RiskDebugLog("RISK-SL", "❌ Failed to initialize IndicatorManager singleton");
                return 0.0;
            }
        }

        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        RiskDebugLog("RISK-SL", StringFormat("Symbol info: Point=%.5f, Digits=%d", point, digits));

        ENUM_TIMEFRAMES atrTimeframe = timeframe;

        // Adjust timeframe for volatile symbols
        RiskDebugLog("RISK-SL", StringFormat("Original timeframe: %s", TimeframeToString(timeframe)));

        if (symbol == "XAUUSD" || symbol == "GOLD" ||
            symbol == "XAGUSD" || symbol == "SILVER" ||
            symbol == "BTCUSD" || symbol == "ETHUSD" ||
            StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0)
        {
            RiskDebugLog("RISK-SL", "Volatile symbol detected");
            if (timeframe < PERIOD_M15)
            {
                atrTimeframe = PERIOD_M15;
                RiskDebugLog("RISK-SL", StringFormat("Timeframe adjusted UP from %s to %s",
                                                     TimeframeToString(timeframe), TimeframeToString(atrTimeframe)));
            }
        }
        else
        {
            if (timeframe == PERIOD_M1 || timeframe == PERIOD_M5)
            {
                atrTimeframe = PERIOD_M15;
                RiskDebugLog("RISK-SL", StringFormat("Timeframe adjusted UP from %s to %s",
                                                     TimeframeToString(timeframe), TimeframeToString(atrTimeframe)));
            }
        }

        RiskDebugLog("RISK-SL", StringFormat("Final timeframe for calculations: %s",
                                             TimeframeToString(atrTimeframe)));

        // ✅ Get ATR from singleton
        double atrValue = indManager.GetATR(atrTimeframe, 0);
        RiskDebugLog("RISK-SL", StringFormat("ATR Value: %.5f (%.1f pips)", atrValue, atrValue / point));

        if (atrValue <= 0)
        {
            RiskDebugLog("RISK-SL-ERROR", "❌ ATR value is 0 or negative!");
        }

        if (isBuy)
        {
            RiskDebugLog("RISK-SL", "=== BUY POSITION ===");

            // Get swing low with debug
            double swingLow = FindRecentSwingLow(symbol, atrTimeframe);
            RiskDebugLog("RISK-SL-SWING", StringFormat("FindRecentSwingLow returned: %.5f", swingLow));

            if (swingLow <= 0)
            {
                RiskDebugLog("RISK-SL-SWING", "❌ Swing low not found or is 0. Using ATR fallback.");

                double atrStop = entryPrice - (atrValue * atrMultiplier);
                RiskDebugLog("RISK-SL-CALC", StringFormat("ATR Stop calculation: %.5f - (%.5f * %.1f) = %.5f",
                                                          entryPrice, atrValue, atrMultiplier, atrStop));

                double distancePoints = (entryPrice - atrStop) / point;
                RiskDebugLog("RISK-SL-CALC", StringFormat("Stop distance: %.1f points (%.1f pips)",
                                                          distancePoints, distancePoints / 10));

                atrStop = NormalizeStopPrice(symbol, atrStop, isBuy, entryPrice);

                RiskDebugLog("RISK-SL", StringFormat("✅ Final ATR-based stop: %.5f (%.1f points from entry)",
                                                     atrStop, (entryPrice - atrStop) / point));
                return atrStop;
            }
            else
            {
                RiskDebugLog("RISK-SL-SWING", StringFormat("✅ Swing low found at: %.5f", swingLow));
                RiskDebugLog("RISK-SL-SWING", StringFormat("Distance from entry: %.1f points",
                                                           (entryPrice - swingLow) / point));

                double buffer = CalculateStopBuffer(symbol, atrValue, point, isBuy);
                RiskDebugLog("RISK-SL-BUFFER", StringFormat("Stop buffer: %.5f (%.1f pips)", buffer, buffer / point));

                double stop = swingLow - buffer;
                RiskDebugLog("RISK-SL-CALC", StringFormat("Initial stop: %.5f - %.5f = %.5f",
                                                          swingLow, buffer, stop));

                stop = ValidateAndAdjustStop(symbol, isBuy, entryPrice, stop, atrTimeframe);

                RiskDebugLog("RISK-SL", StringFormat("✅ Final swing-based stop: %.5f", stop));
                return stop;
            }
        }
        else
        {
            RiskDebugLog("RISK-SL", "=== SELL POSITION ===");

            // Get swing high with debug
            double swingHigh = FindRecentSwingHigh(symbol, atrTimeframe);
            RiskDebugLog("RISK-SL-SWING", StringFormat("FindRecentSwingHigh returned: %.5f", swingHigh));

            if (swingHigh <= 0)
            {
                RiskDebugLog("RISK-SL-SWING", "❌ Swing high not found or is 0. Using ATR fallback.");

                double atrStop = entryPrice + (atrValue * atrMultiplier);
                RiskDebugLog("RISK-SL-CALC", StringFormat("ATR Stop calculation: %.5f + (%.5f * %.1f) = %.5f",
                                                          entryPrice, atrValue, atrMultiplier, atrStop));

                double distancePoints = (atrStop - entryPrice) / point;
                RiskDebugLog("RISK-SL-CALC", StringFormat("Stop distance: %.1f points (%.1f pips)",
                                                          distancePoints, distancePoints / 10));

                atrStop = NormalizeStopPrice(symbol, atrStop, isBuy, entryPrice);

                RiskDebugLog("RISK-SL", StringFormat("✅ Final ATR-based stop: %.5f (%.1f points from entry)",
                                                     atrStop, (atrStop - entryPrice) / point));
                return atrStop;
            }
            else
            {
                RiskDebugLog("RISK-SL-SWING", StringFormat("✅ Swing high found at: %.5f", swingHigh));
                RiskDebugLog("RISK-SL-SWING", StringFormat("Distance from entry: %.1f points",
                                                           (swingHigh - entryPrice) / point));

                double buffer = CalculateStopBuffer(symbol, atrValue, point, isBuy);
                RiskDebugLog("RISK-SL-BUFFER", StringFormat("Stop buffer: %.5f (%.1f pips)", buffer, buffer / point));

                double stop = swingHigh + buffer;
                RiskDebugLog("RISK-SL-CALC", StringFormat("Initial stop: %.5f + %.5f = %.5f",
                                                          swingHigh, buffer, stop));

                stop = ValidateAndAdjustStop(symbol, isBuy, entryPrice, stop, atrTimeframe);

                RiskDebugLog("RISK-SL", StringFormat("✅ Final swing-based stop: %.5f", stop));
                return stop;
            }
        }

        RiskDebugLog("RISK-SL", "===== CALCULATE STOP LOSS END =====");
        return 0.0;
    }

    double CalculateStopBuffer(string symbol, double atrValue, double point, bool isBuy)
    {
        double buffer = atrValue * 0.25;
        double minBuffer = GetMinBuffer(symbol, point, isBuy);

        // Cap the buffer for volatile symbols
        if (symbol == "XAUUSD" || symbol == "GOLD")
        {
            double maxBuffer = 1.50; // 150 pips max buffer for gold
            buffer = MathMin(buffer, maxBuffer);
        }

        if (buffer < minBuffer)
        {
            buffer = minBuffer;
        }

        return buffer;
    }

    double GetMinBuffer(string symbol, double point, bool isBuy)
    {
        if (symbol == "XAUUSD" || symbol == "GOLD")
            return 1.00;
        else if (symbol == "XAGUSD" || symbol == "SILVER")
            return 0.20;
        else if (symbol == "BTCUSD" || symbol == "ETHUSD" ||
                 StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0)
            return 50.0;
        else
            return 10 * point;
    }

    double ValidateAndAdjustStop(string symbol, bool isBuy, double entryPrice, double stop, ENUM_TIMEFRAMES tf)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

        double minDistancePips = 0;
        double maxDistancePips = 0;

        if (symbol == "XAUUSD" || symbol == "GOLD")
        {
            // For gold, use appropriate distances in PIPS
            // 50 pips min, 300 pips max
            minDistancePips = 50;  // 50 pips = 500 points
            maxDistancePips = 300; // 300 pips = 3000 points
        }
        else if (symbol == "XAGUSD" || symbol == "SILVER")
        {
            minDistancePips = 30;
            maxDistancePips = 300;
        }
        else if (symbol == "BTCUSD" || symbol == "ETHUSD" ||
                 StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0)
        {
            minDistancePips = 50;
            maxDistancePips = 500;
        }
        else
        {
            // For forex majors
            minDistancePips = 15;
            maxDistancePips = 200;
        }

        // Convert pips to points
        double pipSize = 10 * point; // Standard: 1 pip = 10 points

        double minDistance = minDistancePips * pipSize;
        double maxDistance = maxDistancePips * pipSize;

        RiskDebugLog("VALIDATE-STOP", StringFormat("Min: %.0f pips (%.1f points), Max: %.0f pips (%.1f points), Pip size: %.5f",
                                                   minDistancePips, minDistance, maxDistancePips, maxDistance, pipSize));

        double currentDistance = MathAbs(entryPrice - stop);

        RiskDebugLog("VALIDATE-STOP", StringFormat("Current distance: %.1f points (%.1f pips)",
                                                   currentDistance, currentDistance / pipSize));

        // Apply adjustments
        if (currentDistance < minDistance)
        {
            RiskDebugLog("VALIDATE-STOP", StringFormat("Distance too small (%.1f < %.1f pips). Adjusting...",
                                                       currentDistance / pipSize, minDistancePips));

            if (isBuy)
                stop = entryPrice - minDistance;
            else
                stop = entryPrice + minDistance;

            RiskDebugLog("VALIDATE-STOP", StringFormat("Adjusted stop to: %.5f", stop));
        }

        if (currentDistance > maxDistance)
        {
            RiskDebugLog("VALIDATE-STOP", StringFormat("Distance too large (%.1f > %.1f pips). Adjusting...",
                                                       currentDistance / pipSize, maxDistancePips));

            if (isBuy)
                stop = entryPrice - maxDistance;
            else
                stop = entryPrice + maxDistance;

            RiskDebugLog("VALIDATE-STOP", StringFormat("Adjusted stop to: %.5f", stop));
        }

        return NormalizeDouble(stop, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    }

    double NormalizeStopPrice(string symbol, double price, bool isBuy, double entryPrice)
    {
        if ((isBuy && price >= entryPrice) || (!isBuy && price <= entryPrice))
        {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double minDistance = GetMinBuffer(symbol, point, isBuy);

            if (isBuy)
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
                               double stopLoss, double rrRatio = 1.5)
    {
        RiskDebugLog("RISK-TP", StringFormat("=== CALCULATING TAKE PROFIT === | Symbol: %s | %s @ %.5f | SL: %.5f | RR: %.1f",
                                             symbol, isBuy ? "BUY" : "SELL", entryPrice, stopLoss, rrRatio));

        if (rrRatio <= 0)
        {
            RiskDebugLog("RISK-TP-ERROR", StringFormat("❌ Invalid RR Ratio: %.1f. Using default 1.5", rrRatio));
            rrRatio = 1.5;
        }

        double risk = MathAbs(entryPrice - stopLoss);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double riskPips = risk / point;

        if (riskPips < 1.0)
        {
            risk = 200 * point;
        }

        double reward = risk * rrRatio;
        double tpPrice = isBuy ? entryPrice + reward : entryPrice - reward;
        double normalizedPrice = NormalizePrice(symbol, tpPrice);
        RiskDebugLog("RISK-TP-DEBUG", StringFormat("=== PROFIT === | NormalizedPrice: %.5f | SL: %.5f | RR: %.1f", normalizedPrice, stopLoss, rrRatio));

        return normalizedPrice;
    }

    // ==================== STRUCTURAL TRAILING STOP CALCULATION ====================
    double CalculateTrailingStop(string symbol, bool isBuy, double entryPrice,
                                 double currentPrice, double currentSL,
                                 ENUM_TRAIL_METHOD method = TRAIL_STRUCTURE,
                                 ENUM_TIMEFRAMES timeframe = PERIOD_M15)
    {
        RiskDebugLog("RISK-TRAIL", StringFormat("=== STRUCTURAL TRAILING STOP === | Symbol: %s | %s | Entry: %.5f | Current: %.5f | Current SL: %.5f | TF: %s",
                                                symbol, isBuy ? "BUY" : "SELL", entryPrice, currentPrice, currentSL, TimeframeToString(timeframe)));

        // Only use structural trailing method
        if (method != TRAIL_STRUCTURE)
        {
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

        if (isBuy)
        {
            // For BUY positions: Move SL to last swing LOW + buffer
            if (structure.swingLow > 0 && structure.swingLow < DBL_MAX)
            {
                // Calculate buffer based on ATR or fixed distance
                double atrValue = GetATR(symbol, timeframe, 0);
                double buffer = MathMax(atrValue * 0.5, 10 * point); // Half ATR or 10 pips, whichever is larger

                newSL = structure.swingLow - buffer;

                RiskDebugLog("RISK-TRAIL-BUY",
                             StringFormat("BUY: Swing low at %.5f - buffer %.5f = new SL %.5f",
                                          structure.swingLow, buffer, newSL));

                // Check if price has moved significantly from entry
                double distanceFromEntry = currentPrice - entryPrice;
                if (distanceFromEntry > atrValue * 1.5)
                { // Only trail if we have good profit
                    RiskDebugLog("RISK-TRAIL-BUY",
                                 StringFormat("Good profit: %.5f from entry (ATR: %.5f)",
                                              distanceFromEntry, atrValue));
                }
                else
                {
                    RiskDebugLog("RISK-TRAIL-BUY",
                                 "Not enough profit to trail yet, keeping current SL");
                    return currentSL;
                }
            }
        }
        else
        {
            // For SELL positions: Move SL to last swing HIGH + buffer
            if (structure.swingHigh > 0)
            {
                double atrValue = GetATR(symbol, timeframe, 0);
                double buffer = MathMax(atrValue * 0.5, 10 * point);

                newSL = structure.swingHigh + buffer;

                RiskDebugLog("RISK-TRAIL-SELL",
                             StringFormat("SELL: Swing high at %.5f + buffer %.5f = new SL %.5f",
                                          structure.swingHigh, buffer, newSL));

                // Check if price has moved significantly from entry
                double distanceFromEntry = entryPrice - currentPrice;
                if (distanceFromEntry > atrValue * 1.5)
                {
                    RiskDebugLog("RISK-TRAIL-SELL",
                                 StringFormat("Good profit: %.5f from entry (ATR: %.5f)",
                                              distanceFromEntry, atrValue));
                }
                else
                {
                    RiskDebugLog("RISK-TRAIL-SELL",
                                 "Not enough profit to trail yet, keeping current SL");
                    return currentSL;
                }
            }
        }

        // Normalize the new SL
        newSL = NormalizePrice(symbol, newSL);

        // Validate the new SL makes sense
        if (isBuy)
        {
            if (newSL > currentSL && newSL < currentPrice && newSL < entryPrice)
            {
                RiskDebugLog("RISK-TRAIL", StringFormat("✅ BUY: Moving SL up from %.5f to %.5f", currentSL, newSL));
                return newSL;
            }
        }
        else
        {
            if (newSL < currentSL && newSL > currentPrice && newSL > entryPrice)
            {
                RiskDebugLog("RISK-TRAIL", StringFormat("✅ SELL: Moving SL down from %.5f to %.5f", currentSL, newSL));
                return newSL;
            }
        }

        RiskDebugLog("RISK-TRAIL", "⚠️ No valid structural trailing improvement found");
        return currentSL;
    }

    // ==================== RISK ANALYSIS ====================
    double CalculateRiskRewardRatio(double entry, double stop, double target)
    {
        double risk = MathAbs(entry - stop);
        double reward = MathAbs(target - entry);

        if (risk <= 0)
            return 0.0;

        double rr = reward / risk;
        RiskDebugLog("RISK-RR", StringFormat("RR Ratio: Entry=%.5f, SL=%.5f, TP=%.5f -> Risk=%.5f, Reward=%.5f, RR=%.2f",
                                             entry, stop, target, risk, reward, rr));
        return rr;
    }

    double CalculateRiskAmount(string symbol, double entry, double stop, double lots)
    {
        double riskPerLot = MathAbs(entry - stop) *
                            SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        double totalRisk = riskPerLot * lots;

        RiskDebugLog("RISK-AMOUNT", StringFormat("Risk amount: %.3f lots * $%.2f per lot = $%.2f",
                                                 lots, riskPerLot, totalRisk));
        return totalRisk;
    }

    ENUM_RISK_LEVEL GetCurrentRiskLevel(double maxDrawdownPercent = 20.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);

        if (accountBalance <= 0)
            return RISK_CRITICAL;

        double drawdownPercent = ((accountBalance - equity) / accountBalance) * 100;

        RiskDebugLog("RISK-LEVEL", StringFormat("Drawdown: %.1f%% | Max: %.1f%%", drawdownPercent, maxDrawdownPercent));

        if (drawdownPercent >= maxDrawdownPercent)
            return RISK_CRITICAL;
        if (drawdownPercent >= maxDrawdownPercent * 0.75)
            return RISK_HIGH;
        if (drawdownPercent >= maxDrawdownPercent * 0.5)
            return RISK_MODERATE;
        if (drawdownPercent >= maxDrawdownPercent * 0.25)
            return RISK_LOW;

        return RISK_OPTIMAL;
    }

    ENUM_RISK_LEVEL GetMarketRiskLevel(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
    {
        RiskDebugLog("RISK-MARKET-LEVEL", StringFormat("Getting market risk level for %s (TF: %d)...", symbol, timeframe));

        // ✅ USE SINGLETON
        IndicatorManager* indManager = IndicatorManager::Instance();
        if (indManager == NULL)
        {
            RiskDebugLog("RISK-MARKET-LEVEL", "❌ Failed to get IndicatorManager singleton");
            return RISK_MODERATE;
        }

        // Ensure singleton is initialized
        if (!indManager.IsInitialized())
        {
            RiskDebugLog("RISK-MARKET-LEVEL", "⚠️ IndicatorManager not initialized, initializing now...");
            if (!indManager.Initialize())
            {
                RiskDebugLog("RISK-MARKET-LEVEL", "❌ Failed to initialize IndicatorManager singleton");
                return RISK_MODERATE;
            }
        }

        // ✅ Get indicator values from singleton
        double atr = indManager.GetATR(timeframe, 0);
        double adx, plus_di, minus_di;
        indManager.GetADXValues(timeframe, adx, plus_di, minus_di, 0);
        double rsi = indManager.GetRSI(timeframe, 0);

        int riskScore = 0;

        if (atr > 0.002)
            riskScore += 2;
        else if (atr < 0.0005)
            riskScore -= 1;

        if (adx > 25)
            riskScore += 1;
        else if (adx < 20)
            riskScore += 2;

        if (rsi > 70 || rsi < 30)
            riskScore += 1;

        RiskDebugLog("RISK-MARKET-LEVEL", StringFormat("Market risk score: %d (ATR=%.5f, ADX=%.1f, RSI=%.1f)",
                                                       riskScore, atr, adx, rsi));

        if (riskScore >= 4)
            return RISK_HIGH;
        if (riskScore >= 2)
            return RISK_MODERATE;
        if (riskScore >= 0)
            return RISK_LOW;

        return RISK_OPTIMAL;
    }

    double GetATR(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
    {
        RiskDebugLog("RISK-ATR", StringFormat("Getting ATR for %s on TF %s shift %d...",
                                              symbol, TimeframeToString(timeframe), shift));

        // ✅ USE SINGLETON
        IndicatorManager* im = IndicatorManager::Instance();
        if (im == NULL)
        {
            RiskDebugLog("RISK-ATR", "❌ Failed to get IndicatorManager singleton");
            return 0.0;
        }

        // Ensure singleton is initialized
        if (!im.IsInitialized())
        {
            RiskDebugLog("RISK-ATR", "⚠️ IndicatorManager not initialized, initializing now...");
            if (!im.Initialize())
            {
                RiskDebugLog("RISK-ATR", "❌ Failed to initialize IndicatorManager singleton");
                return 0.0;
            }
        }

        double atrValue = im.GetATR(timeframe, shift);
        
        if (atrValue <= 0)
        {
            RiskDebugLog("RISK-ATR", "⚠️ ATR value is 0 or negative, using default calculation");
            
            // Fallback calculation
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            
            if (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
                atrValue = 10.0 * point; // Default Gold ATR
            else
                atrValue = 0.0005; // Default Forex ATR (5 pips)
        }

        RiskDebugLog("RISK-ATR", StringFormat("ATR value: %.5f (%.1f pips)",
                                              atrValue, atrValue / SymbolInfoDouble(symbol, SYMBOL_POINT)));
        return atrValue;
    }

    double GetMarketConfidence(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
    {
        RiskDebugLog("RISK-CONFIDENCE", StringFormat("Getting market confidence for %s (TF: %d)...", symbol, timeframe));

        // ✅ USE SINGLETON
        IndicatorManager* indManager = IndicatorManager::Instance();
        if (indManager == NULL)
        {
            RiskDebugLog("RISK-CONFIDENCE", "❌ Failed to get IndicatorManager singleton");
            return 50.0;
        }

        // Ensure singleton is initialized
        if (!indManager.IsInitialized())
        {
            RiskDebugLog("RISK-CONFIDENCE", "⚠️ IndicatorManager not initialized, initializing now...");
            if (!indManager.Initialize())
            {
                RiskDebugLog("RISK-CONFIDENCE", "❌ Failed to initialize IndicatorManager singleton");
                return 50.0;
            }
        }

        double confidence = 50.0;

        // ✅ Get indicator values from singleton
        double adx, plus_di, minus_di;
        indManager.GetADXValues(timeframe, adx, plus_di, minus_di, 0);
        if (adx > 25)
            confidence += 20;
        else if (adx < 20)
            confidence -= 10;

        double rsi = indManager.GetRSI(timeframe, 0);
        if ((rsi > 30 && rsi < 70))
            confidence += 10;
        else
            confidence -= 10;

        int bullish_tf_count, bearish_tf_count;
        indManager.GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
        if (bullish_tf_count > bearish_tf_count + 1 || bearish_tf_count > bullish_tf_count + 1)
            confidence += 15;

        confidence = MathMax(0, MathMin(100, confidence));

        RiskDebugLog("RISK-CONFIDENCE", StringFormat("Market confidence: %.1f%% (ADX=%.1f, RSI=%.1f)",
                                                     confidence, adx, rsi));

        return confidence;
    }

    // ==================== POSITION LIMIT CHECKS ====================
    bool CanAddNewPosition(string symbol, int magic, int maxTotalPositions = 5, int maxPositionsPerSymbol = 2)
    {
        RiskDebugLog("RISK-POSITION-LIMIT", StringFormat("Checking position limits for %s (Magic: %d)...", symbol, magic));

        int totalPositions = 0;
        int symbolPositions = 0;

        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket <= 0)
                continue;

            if (PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                int posMagic = (int)PositionGetInteger(POSITION_MAGIC);

                if (posMagic == magic)
                {
                    totalPositions++;
                    if (posSymbol == symbol)
                        symbolPositions++;
                }
            }
        }

        RiskDebugLog("RISK-POSITION-LIMIT",
                     StringFormat("Current positions: Total=%d/%d, %s=%d/%d",
                                  totalPositions, maxTotalPositions,
                                  symbol, symbolPositions, maxPositionsPerSymbol));

        if (totalPositions >= maxTotalPositions)
        {
            RiskDebugLog("RISK-POSITION-LIMIT",
                         StringFormat("❌ Maximum total positions reached: %d/%d",
                                      totalPositions, maxTotalPositions));
            return false;
        }

        if (symbolPositions >= maxPositionsPerSymbol)
        {
            RiskDebugLog("RISK-POSITION-LIMIT",
                         StringFormat("❌ Maximum positions for %s reached: %d/%d",
                                      symbol, symbolPositions, maxPositionsPerSymbol));
            return false;
        }
        
        // all other positions must be in profits.

        RiskDebugLog("RISK-POSITION-LIMIT", "✅ Position limits OK");
        return true;
    }

    void GetRecommendedPositionLimits(double accountBalance, int &outMaxTotal, int &outMaxPerSymbol)
    {
        if (accountBalance < 100)
        {
            outMaxTotal = 1;
            outMaxPerSymbol = 1;
        }
        else if (accountBalance < 500)
        {
            outMaxTotal = 1;
            outMaxPerSymbol = 1;
        }
        else if (accountBalance < 2000)
        {
            outMaxTotal = 1;
            outMaxPerSymbol = 1;
        }
        else if (accountBalance < 5000)
        {
            outMaxTotal = 10;
            outMaxPerSymbol = 3;
        }
        else if (accountBalance < 10000)
        {
            outMaxTotal = 10;
            outMaxPerSymbol = 4;
        }
        else
        {
            outMaxTotal = 20;
            outMaxPerSymbol = 4;
        }

        RiskDebugLog("RISK-POSITION-LIMIT",
                     StringFormat("Recommended limits for $%.2f account: MaxTotal=%d, MaxPerSymbol=%d",
                                  accountBalance, outMaxTotal, outMaxPerSymbol));
    }
}