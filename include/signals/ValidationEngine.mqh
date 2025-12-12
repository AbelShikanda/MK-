//+------------------------------------------------------------------+
//| ValidationEngine.mqh                                             |
//| Signal and Trade Validation Module                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/inputs.mqh"
#include "../config/enums.mqh"
#include "../config/structures.mqh"
#include "../config/GlobalVariables.mqh"
#include "../market/confluence/POIManager.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../market/News/NewsFilter.mqh"
#include "../risk/PositionSizer.mqh"
#include "../risk/ExposureController.mqh"
#include "../market/trend/MultiTimeframe.mqh"
#include "../signals/SignalScorer.mqh"

// //+------------------------------------------------------------------+
// //| Check Ultra-Sensitive Entry                                     |
// //| Entry validation for sensitive trading conditions              |
// //+------------------------------------------------------------------+
// bool CheckUltraSensitiveEntry(const string symbol, const bool isBuy)
// {
//     // Get comprehensive signal score
//     const int signalScore = GetUltraSensitiveSignalScore(symbol, isBuy);
    
//     // Check for aggressive pullback entry
//     const bool isPullback = CheckAggressivePullback(symbol, isBuy);
    
//     if(isPullback)
//     {
//         // For pullbacks, accept slightly lower scores
//         return (signalScore >= 30);
//     }
//     else
//     {
//         // For regular entries, need stronger signals
//         return (signalScore >= SignalScoreThreshold);
//     }
// }

//+------------------------------------------------------------------+
//| Check Ultra-Sensitive Entry                                     |
//| Entry validation for sensitive trading conditions              |
//+------------------------------------------------------------------+
bool CheckUltraSensitiveEntry(const string symbol, const bool isBuy)
{
    // Get comprehensive signal score
    const int signalScore = GetUltraSensitiveSignalScore(symbol, isBuy);
    
    // Check for aggressive pullback entry
    const bool isPullback = CheckAggressivePullback(symbol, isBuy);
    
    if(isPullback)
    {
        // For pullbacks, accept slightly lower scores
        // 30 for BUY, 50 for SELL (SELL needs stronger signal)
        int pullbackThreshold = isBuy ? 50 : 60;
        
        bool passed = (signalScore >= pullbackThreshold);
        
        PrintFormat("PULLBACK %s: Score=%d, Threshold=%d, Passed=%s",
                   isBuy ? "BUY" : "SELL", 
                   signalScore, 
                   pullbackThreshold,
                   passed ? "YES" : "NO");
        
        return passed;
    }
    else
    {
        // For regular entries, need stronger signals
        // 60 for BUY, 80 for SELL (SELL needs much stronger signal)
        int regularThreshold = isBuy ? 57 : 73;
        
        bool passed = (signalScore >= regularThreshold);
        
        PrintFormat("REGULAR %s: Score=%d, Threshold=%d, Passed=%s",
                   isBuy ? "BUY" : "SELL", 
                   signalScore, 
                   regularThreshold,
                   passed ? "YES" : "NO");
        
        return passed;
    }
}

//+------------------------------------------------------------------+
//| Get Ultra-Sensitive Trend Status                                |
//| Returns trend status based on signal scores                    |
//+------------------------------------------------------------------+
string GetUltraSensitiveTrendStatus(const string symbol)
{
    const double buyScore = GetUltraSensitiveSignalScore(symbol, true);
    const double sellScore = GetUltraSensitiveSignalScore(symbol, false);
    
    if(buyScore >= 70 && sellScore < 50)
        return "STRONG UPTREND ⬆️⬆️";
    else if(sellScore >= 70 && buyScore < 50)
        return "STRONG DOWNTREND ⬇️⬇️";
    else if(buyScore >= 60 && sellScore < 60)
        return "UPTREND ⬆️";
    else if(sellScore >= 60 && buyScore < 60)
        return "DOWNTREND ⬇️";
    else if(buyScore > 50 && sellScore > 50)
        return "CONFLICTING ⚡";
    else if(buyScore < 40 && sellScore < 40)
        return "RANGING ↔️";
    else
        return "NEUTRAL •";
}

//+------------------------------------------------------------------+
//| Validated - Primary Trade Validation                            |
//| Main validation entry point                                    |
//+------------------------------------------------------------------+
bool Validated(const string symbol)
{
    return PrimaryValidation(symbol);
}

//+------------------------------------------------------------------+
//| Main Validation Function                                         |
//| Now includes bar trading limits                                 |
//+------------------------------------------------------------------+

bool Validated(const string symbol, const bool isBuy)
{
    // === 1. BAR ALREADY TRADED CHECK ===
    if(BarAlreadyTraded(symbol, isBuy, TradeLimitTimeframe))
    {
        PrintFormat("VALIDATION_FAILED: Bar already traded limit reached for %s", 
                   isBuy ? "BUY" : "SELL");
        return false;
    }
    
    // === 2. PRIMARY VALIDATION CHECK ===
    if(!PrimaryValidation(symbol))
    {
        PrintFormat("Primary Validation failed for %s", symbol);
        return false;
    }
    
    // === 3. RANGE AVOIDANCE CHECK ===
    if(IsMarketRanging(symbol, isBuy))
    {
        PrintFormat("Range Validation Failed for %s", symbol);
        return false;
    }
    
    // === 4. ALL VALIDATIONS PASSED ===
    PrintFormat("VALIDATION_PASSED: All conditions met for %s %s", 
               isBuy ? "BUY" : "SELL", symbol);
    return true;
}

//+------------------------------------------------------------------+
//| Primary Validation - Core Trade Conditions                     |
//+------------------------------------------------------------------+
bool PrimaryValidation(const string symbol)
{
    // Balance check: Under minimum balance, only trade XAUUSD
    if(accountBalance < BalanceForSecondSymbol && symbol != "XAUUSD")
    {
        PrintFormat("FAILED_VALIDATION: Balance below $%.2f - only XAUUSD allowed", 
                   BalanceForSecondSymbol);
        return false;
    }

    // Daily limit check: Maximum trades per day reached
    if(dailyLimitReached)
    {
        Print("FAILED_VALIDATION: Daily limit reached");
        return false;
    }
    
    // News blackout check
    if(IsNewsBlackoutPeriod(symbol))
    {
        PrintFormat("FAILED_VALIDATION: News blackout period for %s", symbol);
        return false;
    }
    
    // Symbol validity check
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1)
    {
        PrintFormat("FAILED_VALIDATION: Symbol %s not in active symbols list", symbol);
        return false;
    }
    
    // Candle time check: Prevent multiple trades per candle
    const datetime currentCandle = iTime(symbol, TradeTF, 0);
    if(lastTradeCandle[symbolIndex] == currentCandle)
    {
        PrintFormat("FAILED_VALIDATION: Already traded on this candle for %s", symbol);
        return false;
    }
    
    // Spread check
    const double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    const double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double spread = (ask - bid) / point;
    
    if(spread > MaxSpreadPips)
    {
        PrintFormat("VALIDATION_FAILED: Spread too high (%.1f > %.1f)", 
                   spread, MaxSpreadPips);
        return false;
    }
    
    // Maximum trades per symbol check
    const int openTrades = CountOpenTrades(symbol);
    if(openTrades >= MaxTradesPerSymbol)
    {
        PrintFormat("VALIDATION_FAILED: Max trades (%d) reached for %s", 
                   MaxTradesPerSymbol, symbol);
        return false;
    }
    
    PrintFormat("Primary Validation Passed for %s", symbol);
    return true;
}

//+------------------------------------------------------------------+
//| Update Trade Candle                                             |
//| Call this AFTER successful trade                               |
//+------------------------------------------------------------------+
void UpdateTradeCandle(const string symbol)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex != -1)
    {
        lastTradeCandle[symbolIndex] = iTime(symbol, TradeTF, 0);
        PrintFormat("UPDATED: Trade candle for %s set to %s", 
                   symbol, TimeToString(lastTradeCandle[symbolIndex]));
    }
}

//+------------------------------------------------------------------+
//| Add Position Validated                                          |
//| Comprehensive validation for position additions                |
//+------------------------------------------------------------------+
bool AddPositionValidated(const string symbol, const bool isBuy, const string reason = "ADDITION")
{
    PrintFormat("=== SMART POSITION ADDITION START: %s (%s) | Reason: %s ===",
               symbol, isBuy ? "BUY" : "SELL", reason);
    
    // Get current positions statistics
    const int positions = CountOpenTrades(symbol);
    if(positions == 0)
    {
        Print("FAILED: No existing positions to add to");
        return false;
    }

    // Initialize position statistics
    double totalProfit = 0.0;
    double totalVolume = 0.0;
    double averageEntry = 0.0;
    double totalCommission = 0.0;
    double totalSwap = 0.0;
    
    const double currentPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Loop through all open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                totalProfit += PositionGetDouble(POSITION_PROFIT);
                totalSwap += PositionGetDouble(POSITION_SWAP);
                
                const double positionVolume = PositionGetDouble(POSITION_VOLUME);
                totalVolume += positionVolume;
                averageEntry += PositionGetDouble(POSITION_PRICE_OPEN) * positionVolume;
            }
        }
    }
    
    // Calculate net profit
    const double netProfitDollars = totalProfit + totalSwap + totalCommission;
    
    if(totalVolume <= 0)
    {
        Print("FAILED: No valid positions found or volume calculation error");
        return false;
    }
    
    averageEntry /= totalVolume;
    
    // Profitability checks
    if(netProfitDollars <= 0)
    {
        PrintFormat("FAILED: Positions are not profitable: $%.2f", netProfitDollars);
        PrintFormat("  Floating: $%.2f | Swap: $%.2f | Commission: $%.2f", 
                   totalProfit, totalSwap, totalCommission);
        return false;
    }
    
    const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double profitInPips = 0.0;
    
    if(isBuy)
    {
        profitInPips = (currentPrice - averageEntry) / pointValue;
    }
    else
    {
        profitInPips = (averageEntry - currentPrice) / pointValue;
    }
    
    // Minimum profit requirement
    const double minProfitDollars = 3.0;
    const double profitMultiplier = 1.5;
    const double requiredProfit = minProfitDollars * MathPow(profitMultiplier, positions - 1);
    
    if(netProfitDollars < requiredProfit)
    {
        PrintFormat("FAILED: Insufficient NET profit: $%.2f (Required: $%.2f for position %d)",
                   netProfitDollars, requiredProfit, positions + 1);
        return false;
    }
    
    // Price movement check
    double priceMovementDollars = MathAbs(currentPrice - averageEntry) * totalVolume;
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
        priceMovementDollars *= 100;
    
    const double minMovementDollars = 5.0;
    if(priceMovementDollars < minMovementDollars)
    {
        PrintFormat("FAILED: Insufficient price movement: $%.2f (minimum: $%.2f)", 
                   priceMovementDollars, minMovementDollars);
        return false;
    }
    
    // Position sizing
    const double normalLotSize = CalculateProgressivePositionSize(symbol);
    if(normalLotSize <= 0)
    {
        Print("FAILED: Could not calculate position size");
        return false;
    }
    
    const double addLotMultiplier = 0.5;
    double addLotSize = normalLotSize * addLotMultiplier;
    
    const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(addLotSize < minLot)
    {
        addLotSize = minLot;
    }
    
    // Maximum positions check
    if(positions >= MaxTradesPerSymbol)
    {
        PrintFormat("FAILED: Maximum positions reached: %d/%d", 
                   positions, MaxTradesPerSymbol);
        return false;
    }
    
    // Calculate new average entry
    const double newTotalVolume = totalVolume + addLotSize;
    const double newAverageEntry = (averageEntry * totalVolume + currentPrice * addLotSize) / newTotalVolume;
    
    // Safety margin check
    double safetyDistanceDollars = MathAbs(currentPrice - newAverageEntry) * newTotalVolume;
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
        safetyDistanceDollars *= 100;
    
    const double minSafetyDistanceDollars = 5.0;
    if(safetyDistanceDollars < minSafetyDistanceDollars)
    {
        PrintFormat("FAILED: New average too close to current price: $%.2f (minimum safety: $%.2f)", 
                   safetyDistanceDollars, minSafetyDistanceDollars);
        return false;
    }

    // Exposure validation
    const ENUM_POSITION_TYPE positionType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
    bool exposureValid = ValidateExposure(
        symbol,
        positionType,
        newTotalVolume,
        newAverageEntry,
        0,
        EXPOSURE_MARGIN_BASED
    );

    if(!exposureValid)
    {
        Print("FAILED: Account exposure limit would be exceeded");
        return false;
    }
    
    // POI validation
    static bool poiInitialized = false;
    if(!poiInitialized)
    {
        InitializePOISystem(symbol);
        poiInitialized = true;
    }
    
    double confidenceScore;
    bool poiValid = ValidatePOI(symbol, currentPrice, isBuy, profitInPips, confidenceScore);
    
    if(!poiValid)
    {
        PrintFormat("FAILED: POI validation failed - Confidence: %.1f%%", confidenceScore);
        return false;
    }
    
    Print("PASSED: All validation checks successful");
    PrintFormat("STATS: Net Profit=$%.2f, Movement=$%.2f, Positions=%d",
               netProfitDollars, priceMovementDollars, positions);
    PrintFormat("ADDITION: Adding %.3f lots (%.0f%% of normal %.3f lots)",
               addLotSize, addLotMultiplier * 100, normalLotSize);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get MA Alignment Score                                          |
//| Returns 0-100% alignment quality                               |
//+------------------------------------------------------------------+
double GetMAAlignmentScore(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    const double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
    const double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double fastMedDist = MathAbs(fast - med) / point;
    const double medSlowDist = MathAbs(med - slow) / point;
    
    double totalScore = 0.0;
    string scoreBreakdown = "";
    
    // Rule 1: Medium-Slow Separation (40% weight)
    double medSlowScore = 0.0;
    if(medSlowDist > 20.0)
    {
        medSlowScore = 100.0;
        scoreBreakdown += "Med-Slow: Excellent (>20 pips), ";
    }
    else if(medSlowDist > 15.0)
    {
        medSlowScore = 85.0;
        scoreBreakdown += "Med-Slow: Very Good (15-20 pips), ";
    }
    else if(medSlowDist > 10.0)
    {
        medSlowScore = 70.0;
        scoreBreakdown += "Med-Slow: Good (10-15 pips), ";
    }
    else if(medSlowDist > 5.0)
    {
        medSlowScore = 40.0;
        scoreBreakdown += "Med-Slow: Weak (5-10 pips), ";
    }
    else
    {
        medSlowScore = 0.0;
        scoreBreakdown += "Med-Slow: Poor (<5 pips), ";
    }
    
    totalScore += medSlowScore * 0.40;
    
    // Rule 2: Medium-Slow Direction (30% weight)
    double medSlowDirScore = 0.0;
    if(isBuy)
    {
        if(med > slow)
        {
            medSlowDirScore = 100.0;
            scoreBreakdown += "Dir: Perfect (Med>Slow), ";
        }
        else if(med >= slow - (5.0 * point))
        {
            medSlowDirScore = 60.0;
            scoreBreakdown += "Dir: Close (Med≈Slow), ";
        }
        else
        {
            medSlowDirScore = 0.0;
            scoreBreakdown += "Dir: Wrong, ";
        }
    }
    else
    {
        if(med < slow)
        {
            medSlowDirScore = 100.0;
            scoreBreakdown += "Dir: Perfect (Med<Slow), ";
        }
        else if(med <= slow + (5.0 * point))
        {
            medSlowDirScore = 60.0;
            scoreBreakdown += "Dir: Close (Med≈Slow), ";
        }
        else
        {
            medSlowDirScore = 0.0;
            scoreBreakdown += "Dir: Wrong, ";
        }
    }
    
    totalScore += medSlowDirScore * 0.30;
    
    // Rule 3: Fast-Medium Momentum (20% weight)
    double fastMedScore = 0.0;
    if(isBuy)
    {
        if(fast > med)
        {
            if(fastMedDist > 10.0)
            {
                fastMedScore = 100.0;
                scoreBreakdown += "Fast-Med: Strong (>10), ";
            }
            else if(fastMedDist > 5.0)
            {
                fastMedScore = 80.0;
                scoreBreakdown += "Fast-Med: Good (5-10), ";
            }
            else if(fastMedDist > 2.0)
            {
                fastMedScore = 60.0;
                scoreBreakdown += "Fast-Med: Moderate (2-5), ";
            }
            else
            {
                fastMedScore = 40.0;
                scoreBreakdown += "Fast-Med: Weak (<2), ";
            }
        }
        else if(fast >= med - (3.0 * point))
        {
            fastMedScore = 30.0;
            scoreBreakdown += "Fast-Med: Pullback (Close), ";
        }
        else
        {
            fastMedScore = 0.0;
            scoreBreakdown += "Fast-Med: Wrong Dir, ";
        }
    }
    else
    {
        if(fast < med)
        {
            if(fastMedDist > 10.0)
            {
                fastMedScore = 100.0;
                scoreBreakdown += "Fast-Med: Strong (>10), ";
            }
            else if(fastMedDist > 5.0)
            {
                fastMedScore = 80.0;
                scoreBreakdown += "Fast-Med: Good (5-10), ";
            }
            else if(fastMedDist > 2.0)
            {
                fastMedScore = 60.0;
                scoreBreakdown += "Fast-Med: Moderate (2-5), ";
            }
            else
            {
                fastMedScore = 40.0;
                scoreBreakdown += "Fast-Med: Weak (<2), ";
            }
        }
        else if(fast <= med + (3.0 * point))
        {
            fastMedScore = 30.0;
            scoreBreakdown += "Fast-Med: Bounce (Close), ";
        }
        else
        {
            fastMedScore = 0.0;
            scoreBreakdown += "Fast-Med: Wrong Dir, ";
        }
    }
    
    totalScore += fastMedScore * 0.20;
    
    // Rule 4: Overall Stack Consistency (10% weight)
    double stackScore = 0.0;
    if(isBuy)
    {
        if(fast > med && med > slow)
        {
            stackScore = 100.0;
            scoreBreakdown += "Stack: Perfect";
        }
        else if(fast > slow && med > slow)
        {
            stackScore = 70.0;
            scoreBreakdown += "Stack: Good";
        }
        else if(med > slow)
        {
            stackScore = 50.0;
            scoreBreakdown += "Stack: OK";
        }
        else
        {
            stackScore = 0.0;
            scoreBreakdown += "Stack: Poor";
        }
    }
    else
    {
        if(fast < med && med < slow)
        {
            stackScore = 100.0;
            scoreBreakdown += "Stack: Perfect";
        }
        else if(fast < slow && med < slow)
        {
            stackScore = 70.0;
            scoreBreakdown += "Stack: Good";
        }
        else if(med < slow)
        {
            stackScore = 50.0;
            scoreBreakdown += "Stack: OK";
        }
        else
        {
            stackScore = 0.0;
            scoreBreakdown += "Stack: Poor";
        }
    }
    
    totalScore += stackScore * 0.10;
    
    // Clean up breakdown string
    if(StringLen(scoreBreakdown) > 0)
    {
        scoreBreakdown = StringSubstr(scoreBreakdown, 0, StringLen(scoreBreakdown) - 2);
    }
    
    PrintFormat("MA Alignment: %.1f%% - %s", totalScore, scoreBreakdown);
    
    return totalScore;
}

//+------------------------------------------------------------------+
//| Is Market Ranging                                               |
//| Returns true if market is ranging (no clear trend)             |
//+------------------------------------------------------------------+
bool IsMarketRanging(const string symbol, const bool isBuy)
{
    // Get current market status
    PrintM15MarketStatus(symbol);
    
    // Check trend strength
    const ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
    
    if(trend == TREND_NEUTRAL)
    {
        Print("❌ Market RANGING: MAs tangled/compressed (TREND_NEUTRAL)");
        return true;
    }
    
    if((isBuy && trend == TREND_WEAK_BULLISH) || 
       (!isBuy && trend == TREND_WEAK_BEARISH))
    {
        PrintFormat("❌ Market RANGING: Weak trend (%s)", EnumToString(trend));
        return true;
    }
    
    // Check MA alignment
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return true;
    
    const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    const double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
    const double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
    const double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double maScore = GetMAAlignmentScore(symbol, isBuy);
    
    // Dynamic threshold based on trend strength
    double minScore = 45.0;
    
    if(trend == TREND_STRONG_BULLISH || trend == TREND_STRONG_BEARISH)
    {
        minScore = 60.0;
        Print("Strong trend detected - lowering MA score requirement to 55%");
    }
    else if(trend == TREND_MODERATE_BULLISH || trend == TREND_MODERATE_BEARISH)
    {
        minScore = 55.0;
    }
    else
    {
        minScore = 65.0;
    }
    
    if(maScore < minScore)
    {
        PrintFormat("❌ Market RANGING: MA alignment too weak (%.1f%% < %.1f%%)", 
                   maScore, minScore);
        
        if(maScore < 30.0)
        {
            Print("   Major alignment issues - MAs are tangled");
        }
        else if(maScore < 40.0)
        {
            Print("   Poor alignment - Wait for better MA structure");
        }
        
        return true;
    }
    
    PrintFormat("✅ MA Alignment Score: %.1f%% (≥ %.1f%%)", maScore, minScore);
    
    // Check price position
    if(isBuy && price < med)
    {
        PrintFormat("❌ Market RANGING: Price (%.5f) below medium MA (%.5f)", price, med);
        return true;
    }
    
    if(!isBuy && price > med)
    {
        PrintFormat("❌ Market RANGING: Price (%.5f) above medium MA (%.5f)", price, med);
        return true;
    }
    
    // Check timing
    // const double priceFastDistance = MathAbs(price - fast) / point;
    // if(priceFastDistance > 30.0)
    // {
    //     PrintFormat("⚠️ Timing Warning: Price far from Fast MA (%.1f pips)", priceFastDistance);
    //     Print("   Consider waiting for pullback/bounce for better entry");
    // }
    
    // Final trend validation
    const TradeSignal signal = ValidateM15Trade(symbol, isBuy);
    
    if(!signal.isValid)
    {
        PrintFormat("❌ Market RANGING: %s", signal.reason);
        return true;
    }
    
    PrintFormat("✅ Market NOT ranging - Good for %s trades", isBuy ? "BUY" : "SELL");
    PrintFormat("   Trend: %s", EnumToString(trend));
    PrintFormat("   MA Alignment Score: %.1f%%", maScore);
    PrintFormat("   Signal Confidence: %.1f%%", signal.confidence);
    
    return false;
}

//+------------------------------------------------------------------+
//| Get MA Distance for Previous Bar                                |
//+------------------------------------------------------------------+
double GetMADistance(const string symbol, const bool isBuy, const int barsBack)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    const double fastPrev = GetMAValueAtBar(fastMA_M15[symbolIndex], barsBack);
    const double medPrev = GetMAValueAtBar(mediumMA_M15[symbolIndex], barsBack);
    
    if(fastPrev == 0.0 || medPrev == 0.0) return 0.0;
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    return MathAbs(fastPrev - medPrev) / point;
}

//+------------------------------------------------------------------+
//| Get MA Value at Specific Bar                                    |
//+------------------------------------------------------------------+
double GetMAValueAtBar(const int maHandle, const int shift)
{
    double values[1];
    if(CopyBuffer(maHandle, 0, shift, 1, values) > 0)
    {
        return values[0];
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Validate M15 Trade                                              |
//| Validates trade signals based on MA structure only             |
//+------------------------------------------------------------------+
TradeSignal ValidateM15Trade(const string symbol, const bool isBuy)
{
    TradeSignal signal;
    signal.isValid = false;
    signal.trendStrength = GetM15TrendStrength(symbol);
    signal.confidence = 0.0;
    
    // MA trend strength condition
    bool maCondition = false;
    if(isBuy)
    {
        maCondition = (signal.trendStrength == TREND_STRONG_BULLISH || 
                      signal.trendStrength == TREND_MODERATE_BULLISH);
        if(!maCondition)
        {
            signal.reason = "MA trend not bullish enough";
            return signal;
        }
    }
    else
    {
        maCondition = (signal.trendStrength == TREND_STRONG_BEARISH || 
                      signal.trendStrength == TREND_MODERATE_BEARISH);
        if(!maCondition)
        {
            signal.reason = "MA trend not bearish enough";
            return signal;
        }
    }
    
    // MA alignment quality
    const double maScore = GetMAAlignmentScore(symbol, isBuy);
    if(maScore < 50.0)
    {
        signal.reason = StringFormat("MA alignment too weak (%.1f%% < 50%%)", maScore);
        return signal;
    }
    
    // Adjust confidence based on MA score
    signal.confidence = (signal.confidence * 0.7 + maScore * 0.3);
    
    // All conditions passed
    signal.isValid = true;
    signal.reason = StringFormat("Valid %s signal - Confidence: %.1f%%", 
                                isBuy ? "BUY" : "SELL", signal.confidence);
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get M15 Trend Strength                                          |
//+------------------------------------------------------------------+
ENUM_TREND_STRENGTH GetM15TrendStrength(const string symbol)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return TREND_NEUTRAL;
    
    const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    const double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
    const double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double fastMedDist = MathAbs(fast - med) / point;
    const double medSlowDist = MathAbs(med - slow) / point;
    
    const bool bullStack = (fast > med) && (med > slow);
    const bool bearStack = (fast < med) && (med < slow);
    
    if(bullStack)
    {
        if(fastMedDist > 40.0 && medSlowDist > 40.0) return TREND_STRONG_BULLISH;
        if(fastMedDist > 20.0 && medSlowDist > 20.0) return TREND_MODERATE_BULLISH;
        return TREND_WEAK_BULLISH;
    }
    else if(bearStack)
    {
        if(fastMedDist > 40.0 && medSlowDist > 40.0) return TREND_STRONG_BEARISH;
        if(fastMedDist > 20.0 && medSlowDist > 20.0) return TREND_MODERATE_BEARISH;
        return TREND_WEAK_BEARISH;
    }
    
    const double totalSpread = MathAbs(fast - slow) / point;
    if(totalSpread < 100.0) return TREND_NEUTRAL;
    
    if((fast > med && med < slow) || (fast < med && med > slow))
    {
        return TREND_NEUTRAL;
    }
    
    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Is RSI Valid for Trade                                          |
//+------------------------------------------------------------------+
bool IsRSIValidForTrade(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return false;
    
    const double rsi = GetCurrentRSIValue(rsi_M15[symbolIndex]);
    if(rsi == 0.0) return false;
    
    if(isBuy)
    {
        if(rsi < RSI_Oversold) return true;
        
        const double rsiPrev = GetPreviousRSIValue(rsi_M15[symbolIndex], 1);
        if(rsi > RSI_Oversold && rsi < 50.0 && rsiPrev <= RSI_Oversold)
        {
            return true;
        }
        return false;
    }
    else
    {
        if(rsi > RSI_Overbought) return true;
        
        const double rsiPrev = GetPreviousRSIValue(rsi_M15[symbolIndex], 1);
        if(rsi < RSI_Overbought && rsi > 50.0 && rsiPrev >= RSI_Overbought)
        {
            return true;
        }
        return false;
    }
}

//+------------------------------------------------------------------+
//| Get Previous RSI Value                                          |
//+------------------------------------------------------------------+
double GetPreviousRSIValue(const int rsiHandle, const int barsBack)
{
    double value[1];
    if(CopyBuffer(rsiHandle, 0, barsBack, 1, value) > 0)
    {
        return value[0];
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Print M15 Market Status                                         |
//+------------------------------------------------------------------+
void PrintM15MarketStatus(const string symbol)
{
    const ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
    
    double rsi = 0.0;
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex != -1)
    {
        rsi = GetCurrentRSIValue(rsi_M15[symbolIndex]);
    }
    
    const double atr = GetATRValue(symbol, PERIOD_M15, ATR_Period);
    
    Print("=== M15 MARKET STATUS ===");
    PrintFormat("Symbol: %s", symbol);
    PrintFormat("Trend: %s", EnumToString(trend));
    PrintFormat("RSI: %.1f", rsi);
    PrintFormat("ATR: %.5f", atr);
    
    const bool buyValid = ValidateM15Trade(symbol, true).isValid;
    const bool sellValid = ValidateM15Trade(symbol, false).isValid;
    
    PrintFormat("BUY Signal: %s", buyValid ? "✅ VALID" : "❌ INVALID");
    PrintFormat("SELL Signal: %s", sellValid ? "✅ VALID" : "❌ INVALID");
    Print("========================");
}

//+------------------------------------------------------------------+
//| Get Enhanced Validation Score                                   |
//| Comprehensive validation score for trade decisions             |
//+------------------------------------------------------------------+
double GetEnhancedValidationScore(const string symbol, const bool isBuy)
{
    double totalScore = 0.0;
    
    // Primary validation (20%)
    if(PrimaryValidation(symbol))
        totalScore += 20.0;
    
    // MA alignment (25%)
    const double maScore = GetMAAlignmentScore(symbol, isBuy);
    totalScore += maScore * 0.25;
    
    // Trend strength (15%)
    const ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
    double trendScore = 0.0;
    switch(trend)
    {
        case TREND_STRONG_BULLISH:
        case TREND_STRONG_BEARISH:
            trendScore = 100.0;
            break;
        case TREND_MODERATE_BULLISH:
        case TREND_MODERATE_BEARISH:
            trendScore = 80.0;
            break;
        case TREND_WEAK_BULLISH:
        case TREND_WEAK_BEARISH:
            trendScore = 50.0;
            break;
        default:
            trendScore = 20.0;
    }
    totalScore += trendScore * 0.15;
    
    // Ultra-sensitive entry (20%)
    if(CheckUltraSensitiveEntry(symbol, isBuy))
        totalScore += 20.0;
    
    // RSI validation (10%)
    if(IsRSIValidForTrade(symbol, isBuy))
        totalScore += 10.0;
    
    // Market ranging penalty (deduct up to 10%)
    if(IsMarketRanging(symbol, isBuy))
        totalScore -= 10.0;
    
    return MathMax(0.0, MathMin(100.0, totalScore));
}

//+------------------------------------------------------------------+
//| Check Trade Timing Quality                                      |
//| Returns timing quality for entry decisions                     |
//+------------------------------------------------------------------+
string CheckTradeTimingQuality(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return "POOR";
    
    const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    const double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double distance = MathAbs(price - fast) / point;
    
    if(distance < 5.0) return "EXCELLENT";    // Very close to fast MA
    if(distance < 10.0) return "GOOD";        // Good proximity
    if(distance < 20.0) return "FAIR";        // Acceptable distance
    if(distance < 30.0) return "WEAK";        // Far from fast MA
    return "POOR";                            // Too far for optimal entry
}

//+------------------------------------------------------------------+
//| Validate Complete Trade Setup                                   |
//| Comprehensive validation for complete trade setups             |
//+------------------------------------------------------------------+
bool ValidateCompleteTradeSetup(const string symbol, const bool isBuy)
{
    PrintFormat("=== COMPLETE TRADE SETUP VALIDATION for %s (%s) ===",
               symbol, isBuy ? "BUY" : "SELL");
    
    // 1. Primary validation
    if(!PrimaryValidation(symbol))
        return false;
    
    // 2. Ultra-sensitive entry
    if(!CheckUltraSensitiveEntry(symbol, isBuy))
        return false;
    
    // 3. Market ranging check
    if(IsMarketRanging(symbol, isBuy))
        return false;
    
    // 4. MA alignment score
    if(GetMAAlignmentScore(symbol, isBuy) < 60.0)
        return false;
    
    // 5. Trend strength
    const ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
    if(trend == TREND_NEUTRAL || trend == TREND_WEAK_BULLISH || trend == TREND_WEAK_BEARISH)
        return false;
    
    // 6. Trade timing quality
    if(CheckTradeTimingQuality(symbol, isBuy) == "POOR")
        return false;
    
    Print("✅ COMPLETE TRADE SETUP VALIDATION PASSED");
    return true;
}

//+------------------------------------------------------------------+
//| Get Validation Summary                                          |
//+------------------------------------------------------------------+
string GetValidationSummary(const string symbol, const bool isBuy)
{
    const double validationScore = GetEnhancedValidationScore(symbol, isBuy);
    const ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
    const double maScore = GetMAAlignmentScore(symbol, isBuy);
    const string timing = CheckTradeTimingQuality(symbol, isBuy);
    
    return StringFormat("Validation Summary for %s (%s):\n" +
                       "  Overall Score: %.1f%%\n" +
                       "  Trend: %s\n" +
                       "  MA Alignment: %.1f%%\n" +
                       "  Timing Quality: %s\n" +
                       "  Market Ranging: %s",
                       symbol, isBuy ? "BUY" : "SELL",
                       validationScore,
                       EnumToString(trend),
                       maScore,
                       timing,
                       IsMarketRanging(symbol, isBuy) ? "YES" : "NO");
}

bool BarAlreadyTraded(const string symbol, const bool isBuy, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    // === GET CURRENT BAR TIME ===
    datetime currentBarTime = iTime(symbol, tf, 0);
    
    // === CHECK IF NEW BAR ===
    if(currentBarTime != g_LastTradedBarTime)
    {
        // New bar - reset all counters
        g_TradesCountThisBar = 0;
        g_BuyTradedThisBar = false;
        g_SellTradedThisBar = false;
        g_LastTradedBarTime = currentBarTime;
        
        PrintFormat("BAR_TRACKER: New %s bar started at %s - Counters reset", 
                   EnumToString(tf),
                   TimeToString(currentBarTime, TIME_MINUTES));
    }
    
    // === CHECK MAX TRADES LIMIT ===
    if(g_TradesCountThisBar >= MaxTradesPerBar)
    {
        PrintFormat("BAR_TRACKER: Max trades per bar reached (%d/%d) - Blocking %s", 
                   g_TradesCountThisBar, MaxTradesPerBar, isBuy ? "BUY" : "SELL");
        return true; // Already traded too many times this bar
    }
    
    // === OPTIONAL: CHECK BUY/SELL SPECIFIC LIMITS ===
    if(isBuy && g_BuyTradedThisBar)
    {
        PrintFormat("BAR_TRACKER: BUY already traded this bar - Blocking");
        return true; // Already traded BUY this bar
    }
    
    if(!isBuy && g_SellTradedThisBar)
    {
        PrintFormat("BAR_TRACKER: SELL already traded this bar - Blocking");
        return true; // Already traded SELL this bar
    }
    
    // === BAR IS AVAILABLE FOR TRADING ===
    PrintFormat("BAR_TRACKER: Bar available (%d/%d trades used, %s allowed)", 
               g_TradesCountThisBar, MaxTradesPerBar, isBuy ? "BUY" : "SELL");
    return false; // NOT already traded - proceed
}

//+------------------------------------------------------------------+
//| Mark Bar as Traded                                              |
//| Call this AFTER successful trade execution                      |
//+------------------------------------------------------------------+
void MarkBarAsTraded(const bool isBuy)
{
    g_TradesCountThisBar++;
    
    if(isBuy)
        g_BuyTradedThisBar = true;
    else
        g_SellTradedThisBar = true;
    
    PrintFormat("BAR_TRACKER: Marked %s as traded. Total trades this bar: %d/%d", 
               isBuy ? "BUY" : "SELL", g_TradesCountThisBar, MaxTradesPerBar);
}

//+------------------------------------------------------------------+
//| Reset Bar Tracking (optional - for manual reset)                |
//+------------------------------------------------------------------+
void ResetBarTracking()
{
    g_LastTradedBarTime = 0;
    g_TradesCountThisBar = 0;
    g_BuyTradedThisBar = false;
    g_SellTradedThisBar = false;
    Print("BAR_TRACKER: Tracking completely reset");
}