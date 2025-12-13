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

// For EURUSD, GBPUSD:
// double RANGING_THRESHOLD_PERCENT = 0.15;    // Below 0.15% = RANGING
// double TRENDING_THRESHOLD_PERCENT = 0.25;   // Above 0.25% = CLEAR TREND

// For XAUUSD (Gold):
// double RANGING_THRESHOLD_PERCENT = 0.25;    // Below 0.25% = RANGING  
// double TRENDING_THRESHOLD_PERCENT = 0.40;   // Above 0.40% = CLEAR TREND

// For JPY pairs:
// double RANGING_THRESHOLD_PERCENT = 0.12;    // Below 0.12% = RANGING
// double TRENDING_THRESHOLD_PERCENT = 0.20;   // Above 0.20% = CLEAR TREND

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
        int pullbackThreshold = isBuy ? 37 : 45;
        
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
        int regularThreshold = isBuy ? 45 : 56;
        
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
    const double minProfitDollars = 7.0;
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
    return IsMarketRangingByMADistance(symbol, isBuy);
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
//| GetM15TrendStrength - COMPLETE DEBUG VERSION                    |
//+------------------------------------------------------------------+
ENUM_TREND_STRENGTH GetM15TrendStrength(const string symbol)
{
    Print("\n=== GetM15TrendStrength DEBUG START ===");
    Print("Analyzing symbol: ", symbol);
    
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) 
    {
        Print("ERROR: Symbol not found in active symbols array");
        Print("Active symbols count: ", totalSymbols);
        for(int i = 0; i < totalSymbols; i++) {
            Print("  ", i, ": ", activeSymbols[i]);
        }
        Print("=== GetM15TrendStrength DEBUG END ===\n");
        return TREND_NEUTRAL;
    }
    
    Print("Symbol index: ", symbolIndex);
    Print("fastMA_M15 handle: ", fastMA_M15[symbolIndex]);
    Print("mediumMA_M15 handle: ", mediumMA_M15[symbolIndex]);
    Print("slowMA_M15 handle: ", slowMA_M15[symbolIndex]);
    
    // Get MA values
    const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    const double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
    const double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
    
    PrintFormat("\nMA Values:");
    PrintFormat("  Fast MA (Period %d): %.5f", FastMA_Period, fast);
    PrintFormat("  Med MA (Period %d):  %.5f", MediumMA_Period, med);
    PrintFormat("  Slow MA (Period %d): %.5f", SlowMA_Period, slow);
    
    // Calculate point and pip size
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double pipSize = (digits == 5 || digits == 3) ? (point * 10) : point;
    
    PrintFormat("\nMarket Info:");
    PrintFormat("  Point: %.5f", point);
    PrintFormat("  Digits: %d", digits);
    PrintFormat("  Pip Size: %.5f", pipSize);
    
    // Calculate distances
    double fastMedDist = MathAbs(fast - med) / pipSize;
    double medSlowDist = MathAbs(med - slow) / pipSize;
    double fastSlowDist = MathAbs(fast - slow) / pipSize;
    double totalSpreadPoints = MathAbs(fast - slow) / point;
    
    PrintFormat("\nDistances:");
    PrintFormat("  Fast-Med:   %.1f pips (%.0f points)", fastMedDist, fastMedDist * 10);
    PrintFormat("  Med-Slow:   %.1f pips (%.0f points)", medSlowDist, medSlowDist * 10);
    PrintFormat("  Fast-Slow:  %.1f pips (%.0f points)", fastSlowDist, fastSlowDist * 10);
    PrintFormat("  Total Spread: %.0f points", totalSpreadPoints);
    
    // Check MA stack conditions
    bool bullStack = (fast > med) && (med > slow);
    bool bearStack = (fast < med) && (med < slow);
    bool mixed1 = (fast > med && med < slow);
    bool mixed2 = (fast < med && med > slow);
    
    PrintFormat("\nMA Stack Analysis:");
    PrintFormat("  Bull Stack (fast>med>slow): %s", bullStack ? "YES ✅" : "NO ❌");
    PrintFormat("  Bear Stack (fast<med<slow): %s", bearStack ? "YES ✅" : "NO ❌");
    PrintFormat("  Mixed 1 (fast>med<slow):    %s", mixed1 ? "YES ⚠️" : "NO");
    PrintFormat("  Mixed 2 (fast<med>slow):    %s", mixed2 ? "YES ⚠️" : "NO");
    
    // ORIGINAL LOGIC CHECKS (from your code)
    PrintFormat("\n=== ORIGINAL LOGIC CHECKS ===");
    
    // Check 1: Perfect stack conditions
    if(bullStack)
    {
        if(fastMedDist > 40.0 && medSlowDist > 40.0) 
        {
            PrintFormat("✅ Bull Stack: STRONG_BULLISH (both gaps > 40 pips)");
            Print("=== GetM15TrendStrength DEBUG END ===\n");
            return TREND_STRONG_BULLISH;
        }
        if(fastMedDist > 20.0 && medSlowDist > 20.0) 
        {
            PrintFormat("✅ Bull Stack: MODERATE_BULLISH (both gaps > 20 pips)");
            Print("=== GetM15TrendStrength DEBUG END ===\n");
            return TREND_MODERATE_BULLISH;
        }
        PrintFormat("⚠️ Bull Stack: WEAK_BULLISH (gaps too small: %.1f, %.1f pips)", fastMedDist, medSlowDist);
        Print("=== GetM15TrendStrength DEBUG END ===\n");
        return TREND_WEAK_BULLISH;
    }
    else if(bearStack)
    {
        if(fastMedDist > 40.0 && medSlowDist > 40.0) 
        {
            PrintFormat("✅ Bear Stack: STRONG_BEARISH (both gaps > 40 pips)");
            Print("=== GetM15TrendStrength DEBUG END ===\n");
            return TREND_STRONG_BEARISH;
        }
        if(fastMedDist > 20.0 && medSlowDist > 20.0) 
        {
            PrintFormat("✅ Bear Stack: MODERATE_BEARISH (both gaps > 20 pips)");
            Print("=== GetM15TrendStrength DEBUG END ===\n");
            return TREND_MODERATE_BEARISH;
        }
        PrintFormat("⚠️ Bear Stack: WEAK_BEARISH (gaps too small: %.1f, %.1f pips)", fastMedDist, medSlowDist);
        Print("=== GetM15TrendStrength DEBUG END ===\n");
        return TREND_WEAK_BEARISH;
    }
    
    // Check 2: Original total spread check (line 403 in your code)
    PrintFormat("\nChecking total spread: %.0f points < 100.0 points?", totalSpreadPoints);
    if(totalSpreadPoints < 100.0) 
    {
        PrintFormat("❌ NEUTRAL: Total spread too small (%.0f points < 100 points)", totalSpreadPoints);
        Print("=== GetM15TrendStrength DEBUG END ===\n");
        return TREND_NEUTRAL;
    }
    else
    {
        PrintFormat("✅ Total spread OK: %.0f points ≥ 100 points", totalSpreadPoints);
    }
    
    // Check 3: Mixed signal check (lines 405-408 in your code)
    PrintFormat("\nChecking mixed signals:");
    if(mixed1 || mixed2)
    {
        PrintFormat("❌ NEUTRAL: Mixed MA signals detected");
        Print("=== GetM15TrendStrength DEBUG END ===\n");
        return TREND_NEUTRAL;
    }
    else
    {
        PrintFormat("✅ No mixed signals detected");
    }
    
    // If we get here, something is wrong with the logic
    PrintFormat("\n⚠️ UNEXPECTED: Logic fell through all checks!");
    PrintFormat("  fastSlowDist: %.1f pips", fastSlowDist);
    PrintFormat("  bullStack: %s, bearStack: %s", bullStack ? "YES" : "NO", bearStack ? "YES" : "NO");
    PrintFormat("  mixed1: %s, mixed2: %s", mixed1 ? "YES" : "NO", mixed2 ? "YES" : "NO");
    
    Print("=== GetM15TrendStrength DEBUG END ===\n");
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
    // if(BarAlreadyTraded(...)) return false;
    // is not sufficient unless your BarAlreadyTraded() does ALL of the following:
    // Tracks trades per direction (buy and sell separately)
    // Tracks trade state per timeframe correctly
    // Resets when the new candle opens
    // Survives EA restart or reconnection
    // Correctly maps bars across timeframes

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

// //+------------------------------------------------------------------+
// //| COMPLETE DebugRangeDetection Function                          |
// //+------------------------------------------------------------------+
// void DebugRangeDetection(const string symbol)
// {
//     Print("\n" + StringRepeat("=", 60));
//     Print("🎯 RANGE DETECTION DEBUG - COMPLETE ANALYSIS");
//     Print(StringRepeat("=", 60));
    
//     // 1. BASIC SYMBOL INFO
//     Print("\n📊 1. SYMBOL INFORMATION:");
//     Print("   Symbol: ", symbol);
//     Print("   Current Time: ", TimeToString(TimeCurrent(), TIME_SECONDS));
    
//     double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
//     double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
//     double spread = (ask - bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);
//     PrintFormat("   Bid: %.5f, Ask: %.5f, Spread: %.0f points", bid, ask, spread);
    
//     // 2. CHECK SYMBOL POSITION
//     Print("\n📊 2. SYMBOL POSITION CHECK:");
//     const int symbolIndex = ArrayPosition(symbol);
//     if(symbolIndex == -1)
//     {
//         Print("   ❌ ERROR: Symbol not found in active symbols!");
//         Print("   Total active symbols: ", totalSymbols);
//         for(int i = 0; i < totalSymbols; i++) {
//             PrintFormat("     [%d] %s", i, activeSymbols[i]);
//         }
//         Print(StringRepeat("=", 60));
//         return;
//     }
//     PrintFormat("   ✅ Symbol found at index: %d", symbolIndex);
    
//     // 3. MA HANDLES CHECK
//     Print("\n📊 3. MA HANDLE STATUS:");
//     PrintFormat("   fastMA_M15[%d]: %d", symbolIndex, fastMA_M15[symbolIndex]);
//     PrintFormat("   mediumMA_M15[%d]: %d", symbolIndex, mediumMA_M15[symbolIndex]);
//     PrintFormat("   slowMA_M15[%d]: %d", symbolIndex, slowMA_M15[symbolIndex]);
    
//     if(fastMA_M15[symbolIndex] == INVALID_HANDLE || 
//        mediumMA_M15[symbolIndex] == INVALID_HANDLE || 
//        slowMA_M15[symbolIndex] == INVALID_HANDLE)
//     {
//         Print("   ❌ ERROR: One or more MA handles are INVALID!");
//         Print(StringRepeat("=", 60));
//         return;
//     }
//     Print("   ✅ All MA handles are valid");
    
//     // 4. GET MA VALUES
//     Print("\n📊 4. MOVING AVERAGE VALUES:");
//     const double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
//     const double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
//     const double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
    
//     PrintFormat("   Fast MA (Period %d):  %.5f", FastMA_Period, fast);
//     PrintFormat("   Medium MA (Period %d): %.5f", MediumMA_Period, med);
//     PrintFormat("   Slow MA (Period %d):   %.5f", SlowMA_Period, slow);
    
//     // 5. CALCULATE DISTANCES
//     Print("\n📊 5. DISTANCE CALCULATIONS:");
//     double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
//     int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
//     double pipSize = (digits == 5 || digits == 3) ? (point * 10) : point;
    
//     double fastMedDist = MathAbs(fast - med) / pipSize;
//     double medSlowDist = MathAbs(med - slow) / pipSize;
//     double fastSlowDist = MathAbs(fast - slow) / pipSize;
//     double totalSpreadPoints = MathAbs(fast - slow) / point;
    
//     PrintFormat("   Point Size: %.5f", point);
//     PrintFormat("   Digits: %d", digits);
//     PrintFormat("   Pip Size: %.5f", pipSize);
//     PrintFormat("\n   Fast-Med Distance:   %.1f pips", fastMedDist);
//     PrintFormat("   Med-Slow Distance:   %.1f pips", medSlowDist);
//     PrintFormat("   Fast-Slow Distance:  %.1f pips", fastSlowDist);
//     PrintFormat("   Total Spread:        %.0f points", totalSpreadPoints);
    
//     // 6. MA STACK ANALYSIS
//     Print("\n📊 6. MA STACK ANALYSIS:");
//     bool bullStack = (fast > med) && (med > slow);
//     bool bearStack = (fast < med) && (med < slow);
//     bool mixed1 = (fast > med && med < slow);
//     bool mixed2 = (fast < med && med > slow);
//     bool flatStack = (MathAbs(fast - med) < pipSize * 5) && 
//                      (MathAbs(med - slow) < pipSize * 5);
    
//     PrintFormat("   Bullish Stack:       %s", bullStack ? "✅ YES" : "❌ NO");
//     PrintFormat("   Bearish Stack:       %s", bearStack ? "✅ YES" : "❌ NO");
//     PrintFormat("   Mixed Signal 1:      %s", mixed1 ? "⚠️ YES" : "NO");
//     PrintFormat("   Mixed Signal 2:      %s", mixed2 ? "⚠️ YES" : "NO");
//     PrintFormat("   Flat/Ranging:        %s", flatStack ? "⚠️ YES" : "NO");
    
//     // 7. THRESHOLD CHECKS
//     Print("\n📊 7. THRESHOLD CHECKS:");
    
//     // Check 1: Original 100-point spread check
//     PrintFormat("   Check 1: Total Spread < 100 points?");
//     PrintFormat("     Value: %.0f points %s 100 points", 
//                 totalSpreadPoints, 
//                 totalSpreadPoints < 100.0 ? "< ❌" : ">= ✅");
    
//     // Check 2: Your hierarchical MA gaps (for reference)
//     PrintFormat("\n   Check 2: Hierarchical MA Gaps (for reference):");
//     PrintFormat("     5-9 MA gap:   ? pips (should be ~500+)");
//     PrintFormat("     9-21 MA gap:  ? pips (should be ~900+)");
//     PrintFormat("     21-89 MA gap: ? pips (should be ~2000+)");
//     Print("     Note: These are different from M15 MAs above!");
    
//     // Check 3: Trend strength based on distances
//     PrintFormat("\n   Check 3: Trend Strength Classification:");
//     if(fastSlowDist > 80.0) {
//         Print("     📈 STRONG TREND: >80 pips total separation");
//     } else if(fastSlowDist > 40.0) {
//         Print("     📊 MODERATE TREND: 40-80 pips separation");
//     } else if(fastSlowDist > 20.0) {
//         Print("     📉 WEAK TREND: 20-40 pips separation");
//     } else {
//         Print("     ↔️ RANGING: <20 pips separation");
//     }
    
//     // 8. FINAL TREND DETECTION
//     Print("\n📊 8. FINAL TREND DETECTION:");
//     ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
//     string trendString = EnumToString(trend);
    
//     // Color code the result
//     if(trend == TREND_NEUTRAL) {
//         trendString = "❌ " + trendString + " (RANGING)";
//     } else if(trend == TREND_STRONG_BULLISH || trend == TREND_STRONG_BEARISH) {
//         trendString = "✅ " + trendString + " (STRONG TREND)";
//     } else if(trend == TREND_MODERATE_BULLISH || trend == TREND_MODERATE_BEARISH) {
//         trendString = "⚠️ " + trendString + " (MODERATE TREND)";
//     } else {
//         trendString = "🔸 " + trendString + " (WEAK TREND)";
//     }
    
//     PrintFormat("   GetM15TrendStrength() returns: %s", trendString);
    
//     // 9. RECOMMENDATION
//     Print("\n📊 9. RECOMMENDATION:");
//     if(trend == TREND_NEUTRAL || trend == TREND_WEAK_BULLISH || trend == TREND_WEAK_BEARISH) {
//         Print("   ⚠️ CAUTION: Market may be ranging or trend is too weak");
//         Print("   Consider waiting for stronger trend confirmation");
//     } else {
//         Print("   ✅ Market appears to be trending");
//         Print("   Trading may be acceptable if other validations pass");
//     }
    
//     Print(StringRepeat("=", 60));
// }


























// Below is the **full upgraded, production-grade version** of your `BarAlreadyTraded` system.
// It includes:

// 1. Persistence across EA restart
// 2. Correct per-direction tracking
// 3. Correct per-bar trade counting
// 4. Terminal-level global variables
// 5. Clean, deterministic integration with your trade executor
// 6. Logging that will actually show you what is happening

// After the code, I will answer your second question about the *executor logic* and why yes — you should start there first.

// ---

// # 1. FULL UPGRADED VERSION (copy-paste ready)

// ## **A) Global State (put in GlobalVariables.mqh or top of EA)**

// ```cpp
// // Persistent keys (unique per symbol + timeframe)
// string KeyLastBarBuy(const string symbol, ENUM_TIMEFRAMES tf)
// {
//     return symbol + "_BUY_LAST_BAR_" + IntegerToString((int)tf);
// }

// string KeyLastBarSell(const string symbol, ENUM_TIMEFRAMES tf)
// {
//     return symbol + "_SELL_LAST_BAR_" + IntegerToString((int)tf);
// }

// string KeyTradesCount(const string symbol, ENUM_TIMEFRAMES tf)
// {
//     return symbol + "_TRADES_COUNT_" + IntegerToString((int)tf);
// }

// // In-memory trackers
// datetime g_LastBarTime = 0;
// int g_TradesCountThisBar = 0;
// bool g_BuyTradedThisBar = false;
// bool g_SellTradedThisBar = false;
// ```

// ---

// ## **B) INITIALIZATION (call on EA init or first tick)**

// ```cpp
// void InitBarTracker(const string symbol, ENUM_TIMEFRAMES tf)
// {
//     // Load persistent values or initialize
//     if(!GlobalVariableCheck(KeyTradesCount(symbol, tf)))
//         GlobalVariableSet(KeyTradesCount(symbol, tf), 0);
    
//     if(!GlobalVariableCheck(KeyLastBarBuy(symbol, tf)))
//         GlobalVariableSet(KeyLastBarBuy(symbol, tf), 0);
    
//     if(!GlobalVariableCheck(KeyLastBarSell(symbol, tf)))
//         GlobalVariableSet(KeyLastBarSell(symbol, tf), 0);

//     Print("BAR_TRACKER_INIT: Persistent keys ready.");
// }
// ```

// Call it once in `OnInit()`:

// ```cpp
// InitBarTracker(TradeSymbol, TradeLimitTimeframe);
// ```

// ---

// ## **C) THE NEW BarAlreadyTraded() — FINAL VERSION**

// ```cpp
// bool BarAlreadyTraded(const string symbol, const bool isBuy, ENUM_TIMEFRAMES tf)
// {
//     datetime barTime = iTime(symbol, tf, 0);

//     // Detect new bar
//     if(barTime != g_LastBarTime)
//     {
//         g_LastBarTime = barTime;

//         // Load persisted count for this bar if exists
//         g_TradesCountThisBar = (int)GlobalVariableGet(KeyTradesCount(symbol, tf));

//         // Load buy/sell last-bar timestamps
//         datetime lastBuyBar  = (datetime)GlobalVariableGet(KeyLastBarBuy(symbol, tf));
//         datetime lastSellBar = (datetime)GlobalVariableGet(KeyLastBarSell(symbol, tf));

//         g_BuyTradedThisBar  = (lastBuyBar  == barTime);
//         g_SellTradedThisBar = (lastSellBar == barTime);

//         PrintFormat("BAR_TRACKER: New bar %s. BuyFlag=%s SellFlag=%s Count=%d",
//             TimeToString(barTime), 
//             g_BuyTradedThisBar?"TRUE":"FALSE",
//             g_SellTradedThisBar?"TRUE":"FALSE",
//             g_TradesCountThisBar);
//     }

//     // === CHECK LIMITS ===
//     if(g_TradesCountThisBar >= MaxTradesPerBar)
//     {
//         Print("BAR_TRACKER_BLOCK: Max trades per bar reached.");
//         return true;
//     }

//     if(isBuy && g_BuyTradedThisBar)
//     {
//         Print("BAR_TRACKER_BLOCK: BUY already traded this bar.");
//         return true;
//     }

//     if(!isBuy && g_SellTradedThisBar)
//     {
//         Print("BAR_TRACKER_BLOCK: SELL already traded this bar.");
//         return true;
//     }

//     return false;
// }
// ```

// ---

// ## **D) THE REQUIRED UPDATE FUNCTION (call AFTER successful trade open)**

// ```cpp
// void RegisterBarTrade(const string symbol, const bool isBuy, ENUM_TIMEFRAMES tf)
// {
//     datetime barTime = iTime(symbol, tf, 0);

//     g_TradesCountThisBar++;
//     GlobalVariableSet(KeyTradesCount(symbol, tf), g_TradesCountThisBar);

//     if(isBuy)
//     {
//         g_BuyTradedThisBar = true;
//         GlobalVariableSet(KeyLastBarBuy(symbol, tf), barTime);
//     }
//     else
//     {
//         g_SellTradedThisBar = true;
//         GlobalVariableSet(KeyLastBarSell(symbol, tf), barTime);
//     }

//     PrintFormat("BAR_TRACKER_UPDATE: Trade registered (%s). Count=%d Bar=%s",
//         isBuy?"BUY":"SELL",
//         g_TradesCountThisBar,
//         TimeToString(barTime));
// }
// ```

// ---

// ## **E) HOW TO USE IT IN YOUR EXECUTOR**

// This must be the pattern:

// ```cpp
// if(BarAlreadyTraded(symbol, isBuy, TradeLimitTimeframe))
//     return false;

// if(ExecuteOrder(symbol, isBuy, volume))
// {
//     RegisterBarTrade(symbol, isBuy, TradeLimitTimeframe);
//     return true;
// }
// ```

// Never update inside BarAlreadyTraded().
// Always update **after a confirmed execution**.

// ---

// # 2. Your second question:

// ## “Isn’t it better to start with what is causing the problem inside the executor? The logic?”

// Yes — 100%.

// **Bar restriction logic is only a symptom filter.
// The real cause is inside your executor logic.**

// ### The real reasons bots double-enter are:

// 1. **Signal triggers multiple times within the same candle**
// 2. **Executor logic checks conditions multiple times**
// 3. **Executor executes both instant and pending logic on same tick**
// 4. **Conditions flip true → false → true within the same bar**
// 5. **You evaluate MAs on live ticks, not candle close**
// 6. **Your “no uptrend” or “no trend confirmed” logic is too strict/too sensitive**

// If you patch the bar-limit first, you hide the bug.
// If you fix the executor logic first, you eliminate the bug.

// ### The correct order:

// 1. **Fix signal logic → stable trend detection → correct trigger conditions**
// 2. **Stabilize executor → ensure one valid signal = one execution**
// 3. **Apply bar-limit as a safety shield**

// This gives:

// * cleaner logs
// * consistent entries
// * less patchwork
// * far fewer duplicates
// * easier debugging

// ---

// # 3. If you want, I can now do:

// * A full audit of your **executor logic**
// * Rebuild your **trend detection**
// * Fix your **MA inversion / no-trend bug**
// * Reconstruct a robust entry trigger system
// * Show you exact points where your bot fails to detect uptrend/downtrend

// Just tell me which file you want reviewed first.
