//+------------------------------------------------------------------+
//|                                           RangePackage.mqh       |
//|              PURE Institutional Trap Detection (No Regime)      |
//|                   ALREADY INTEGRATED WITH LOGGER FUNCTIONS       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.00"
#property strict

#include <Arrays\ArrayDouble.mqh>
#include <Trade\SymbolInfo.mqh>

#include "../Utils/Logger.mqh"
#include "../Data/IndicatorManager.mqh" // Include IndicatorManager

// Note: Logger functions are available as static calls: Logger::Log(...)

// ====================== DEBUG SETTINGS ======================
bool DEBUG_TRAP_ENABLED = true;

// Simple debug function using Logger
void DebugTrapLogs(string context, string message)
{
    if (DEBUG_TRAP_ENABLED)
    {
        Logger::Log(context, message, true, true); // logToFile: true, logToConsole: true
    }
}

//+------------------------------------------------------------------+
//| Trap Detection Results                                          |
//+------------------------------------------------------------------+
struct TrapAnalysisResult
{
    double trapProbability;    // 0-100% probability it's a trap
    bool isTrapZone;           // True if likely institutional trap
    string recommendedAction;  // "FOLLOW", "FADE", "AVOID", "WAIT"
    string reason;             // Explanation of the analysis
    string marketRegime;       // Added: "RANGING", "TIGHT_RANGE", "TRENDING", "UNKNOWN"
    string overrideDirection;  // Added: "BULLISH", "BEARISH", "NEUTRAL"
    double overrideConfidence; // Added: Confidence for the override direction (0-100%)

    TrapAnalysisResult()
    {
        trapProbability = 0;
        isTrapZone = false;
        recommendedAction = "FOLLOW";
        reason = "No analysis performed";
        marketRegime = "UNKNOWN";
        overrideDirection = "NEUTRAL";
        overrideConfidence = 0;
    }

    string ToString() const
    {
        return StringFormat("TrapProb: %.1f%% | Action: %s | TrapZone: %s | Regime: %s | Dir: %s | Conf: %.1f%%",
                            trapProbability, recommendedAction,
                            isTrapZone ? "YES" : "NO",
                            marketRegime, overrideDirection, overrideConfidence);
    }
};

//+------------------------------------------------------------------+
//| Main Trap Detector Namespace                                    |
//+------------------------------------------------------------------+
namespace RangePackage
{
    // Configuration
    input int TRAP_LOOKBACK_CANDLES = 15;     // Candles to analyze for traps
    input double TIGHT_RANGE_THRESHOLD = 1.5; // % width for tight range
    input double VERY_TIGHT_RANGE = 0.8;      // % width for very tight range
    input int MIN_TOUCHES_FOR_TRAP = 2;       // Min touches to consider level valid

    // Static IndicatorManager instance
    static IndicatorManager *m_indicatorManager = NULL;

    //+------------------------------------------------------------------+
    //| Set the IndicatorManager instance (call from your EA)           |
    //+------------------------------------------------------------------+
    void SetIndicatorManager(IndicatorManager *manager)
    {
        m_indicatorManager = manager;
        if (DEBUG_TRAP_ENABLED && m_indicatorManager != NULL)
        {
            DebugTrapLogs("INDICATOR_MANAGER_SET",
                          StringFormat("IndicatorManager set for symbol: %s", m_indicatorManager.GetSymbol()));
        }
    }

    //+------------------------------------------------------------------+
    //| Get ATR using IndicatorManager (RELIABLE)                       |
    //+------------------------------------------------------------------+
    double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period = 14)
    {
        if (m_indicatorManager != NULL)
        {
            // Use IndicatorManager's reliable ATR
            double atr = m_indicatorManager.GetATR(timeframe, 0);

            if (DEBUG_TRAP_ENABLED && atr > 0)
            {
                DebugTrapLogs("ATR_FROM_MANAGER",
                              StringFormat("%s: ATR=%.5f from IndicatorManager", symbol, atr));
            }

            if (atr > 0)
                return atr;
        }

        // Fallback to direct calculation
        int handle = iATR(symbol, timeframe, period);
        if (handle == INVALID_HANDLE)
        {
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("ATR_FAILED",
                              StringFormat("Failed to create ATR handle for %s", symbol));
            }
            return 0;
        }

        double atr[];
        if (CopyBuffer(handle, 0, 0, 1, atr) > 0)
        {
            return atr[0];
        }
        return 0;
    }

    //+------------------------------------------------------------------+
    //| Detect price range (FOR TRAP ANALYSIS ONLY)                     |
    //+------------------------------------------------------------------+
    bool DetectRange(string symbol, ENUM_TIMEFRAMES timeframe, double &support, double &resistance,
                     int &touchCountResistance, int &touchCountSupport)
    {
        support = 0;
        resistance = 0;
        touchCountResistance = 0;
        touchCountSupport = 0;

        int candles = TRAP_LOOKBACK_CANDLES;

        // Additional price trend check
        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        double price15CandlesAgo = iClose(symbol, timeframe, candles - 1);
        double priceChangePercent = ((currentPrice - price15CandlesAgo) / price15CandlesAgo) * 100.0;

        // Get ATR for volatility measurement
        double atr = GetATR(symbol, timeframe, 14);
        double atrPercent = (atr / currentPrice) * 100.0;

        // Trend detection - if price moved significantly more than ATR
        bool isPriceTrending = MathAbs(priceChangePercent) > (atrPercent * 3.0);

        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("PRICE_TREND_CHECK",
                          StringFormat("%s: Price change=%.2f%%, ATR=%.2f%%, TrendScore=%.1f",
                                       symbol, priceChangePercent, atrPercent, MathAbs(priceChangePercent) / atrPercent));
        }

        // If trending strongly, return false
        if (isPriceTrending && MathAbs(priceChangePercent) > 1.0)
        {
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("STRONG_PRICE_TREND",
                              StringFormat("%s: Strong price trend (%.2f%% move) - No valid range",
                                           symbol, priceChangePercent));
            }
            return false;
        }

        // Only proceed if market appears to be ranging
        double highs[], lows[];
        ArrayResize(highs, candles);
        ArrayResize(lows, candles);

        // Collect price data
        for (int i = 0; i < candles; i++)
        {
            highs[i] = iHigh(symbol, timeframe, i);
            lows[i] = iLow(symbol, timeframe, i);
        }

        // Find range boundaries
        support = lows[ArrayMinimum(lows)];
        resistance = highs[ArrayMaximum(highs)];

        // Validate range
        if (support <= 0 || resistance <= support)
        {
            return false;
        }

        double rangeWidthPercent = ((resistance - support) / support) * 100.0;

        // Check if range is too small (just noise)
        if (rangeWidthPercent < (atrPercent * 1.5))
        {
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("RANGE_TOO_SMALL",
                              StringFormat("%s: Range width %.2f%% < %.2f%% (ATR*1.5) - too small",
                                           symbol, rangeWidthPercent, atrPercent * 1.5));
            }
            return false;
        }

        // Check if price is mostly contained within range
        int candlesInsideRange = 0;
        for (int i = 0; i < candles; i++)
        {
            double close = iClose(symbol, timeframe, i);
            if (close >= support && close <= resistance)
                candlesInsideRange++;
        }

        double percentInside = (double)candlesInsideRange / candles * 100.0;
        if (percentInside < 70.0)
        {
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("PRICE_OUTSIDE_RANGE",
                              StringFormat("%s: Only %.1f%% candles inside range - invalid",
                                           symbol, percentInside));
            }
            return false;
        }

        // Count touches
        touchCountResistance = CountTouches(symbol, timeframe, resistance, true);
        touchCountSupport = CountTouches(symbol, timeframe, support, false);

        // Range needs multiple touches to be valid
        if (touchCountResistance < 2 && touchCountSupport < 2)
        {
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("RANGE_WEAK_TOUCHES",
                              StringFormat("%s: Range has insufficient touches (Res: %d, Sup: %d)",
                                           symbol, touchCountResistance, touchCountSupport));
            }
            return false;
        }

        // FINAL VALIDATION
        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("VALID_RANGE_DETECTED",
                          StringFormat("%s: SUCCESS - Support=%.5f (%d touches), Resistance=%.5f (%d touches), Width=%.2f%%, Inside=%.1f%%",
                                       symbol, support, touchCountSupport, resistance, touchCountResistance, rangeWidthPercent, percentInside));
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Detect institutional traps                                      |
    //+------------------------------------------------------------------+
    TrapAnalysisResult AnalyzeForTraps(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        TrapAnalysisResult result;

        // Debug logging with your logger
        if (DEBUG_TRAP_ENABLED)
        {
            string logMsg = StringFormat("Analyzing %s on %s for traps",
                                         symbol, TimeframeToString(timeframe));
            DebugTrapLogs("TRAP_DETECTOR", logMsg);
        }

        // 1. Detect range
        double support, resistance;
        int touchCountResistance, touchCountSupport;

        bool hasValidRange = DetectRange(symbol, timeframe, support, resistance,
                                         touchCountResistance, touchCountSupport);

        // 2. Calculate trap probability
        result.trapProbability = CalculateTrapProbability(symbol, timeframe, hasValidRange,
                                                          support, resistance,
                                                          touchCountResistance, touchCountSupport);
        result.isTrapZone = (result.trapProbability > 70);

        // 3. Generate recommendations based on trap analysis (WITH NEW FIELDS)
        GenerateTrapRecommendations(symbol, timeframe, hasValidRange, support, resistance,
                                    touchCountResistance, touchCountSupport, result);

        // Debug logging with your logger
        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("TRAP_RESULT", "Analysis complete: " + result.ToString());
        }

        return result;
    }

    //+------------------------------------------------------------------+
    //| Generate trap recommendations based on trap analysis            |
    //+------------------------------------------------------------------+
    void GenerateTrapRecommendations(string symbol, ENUM_TIMEFRAMES timeframe,
                                     bool hasValidRange, double support, double resistance,
                                     int touchCountResistance, int touchCountSupport,
                                     TrapAnalysisResult &result)
    {
        if (!hasValidRange)
        {
            result.recommendedAction = "FOLLOW";
            result.reason = "No valid range detected - follow trend";
            result.marketRegime = "TRENDING"; // Default to trending if no range
            result.overrideDirection = "NEUTRAL";
            result.overrideConfidence = 0;
            return;
        }

        result.marketRegime = "RANGING"; // Set the market regime to RANGING

        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        double atr = GetATR(symbol, timeframe, 14);
        double distanceToResistance = MathAbs(resistance - currentPrice);
        double distanceToSupport = MathAbs(support - currentPrice);

        // Determine proximity to range edges
        bool nearResistance = (distanceToResistance < atr * 1.5);
        bool nearSupport = (distanceToSupport < atr * 1.5);
        bool inMiddleRange = !nearResistance && !nearSupport;

        // Check for round number traps
        bool resistanceIsRound = IsNearRoundNumber(resistance);
        bool supportIsRound = IsNearRoundNumber(support);

        // Determine override direction and confidence based on trap analysis
        if (nearResistance)
        {
            result.recommendedAction = "FADE";
            result.reason = StringFormat("Near resistance (%.4f) with %d touches - likely trap.",
                                         resistance, touchCountResistance);

            // For resistance fade, suggest BEARISH direction
            result.overrideDirection = "BEARISH";
            result.overrideConfidence = MathMin(100, result.trapProbability * 0.8); // 80% of trap probability

            if (resistanceIsRound)
            {
                result.reason += " Resistance is at round number - STRONG TRAP SIGNAL.";
                result.overrideConfidence = MathMin(100, result.trapProbability * 0.9); // Higher confidence for round numbers
            }
        }
        else if (nearSupport)
        {
            result.recommendedAction = "FADE";
            result.reason = StringFormat("Near support (%.4f) with %d touches - likely trap.",
                                         support, touchCountSupport);

            // For support fade, suggest BULLISH direction
            result.overrideDirection = "BULLISH";
            result.overrideConfidence = MathMin(100, result.trapProbability * 0.8); // 80% of trap probability

            if (supportIsRound)
            {
                result.reason += " Support is at round number - STRONG TRAP SIGNAL.";
                result.overrideConfidence = MathMin(100, result.trapProbability * 0.9); // Higher confidence for round numbers
            }
        }
        else if (inMiddleRange)
        {
            result.recommendedAction = "WAIT";
            result.reason = "In middle of range - waiting for better edge opportunity.";
            result.overrideDirection = "NEUTRAL";
            result.overrideConfidence = 0;
        }

        // If trap probability is very high, force avoidance
        if (result.trapProbability > 85)
        {
            result.recommendedAction = "AVOID";
            result.reason = "Extremely high trap probability - avoid trading.";
            result.overrideDirection = "NEUTRAL";
            result.overrideConfidence = 0;
        }

        // Check for TIGHT_RANGE condition
        double rangeWidthPercent = ((resistance - support) / currentPrice) * 100.0;
        if (rangeWidthPercent < VERY_TIGHT_RANGE)
        {
            result.marketRegime = "TIGHT_RANGE";
            if (DEBUG_TRAP_ENABLED)
            {
                DebugTrapLogs("TIGHT_RANGE_DETECTED",
                              StringFormat("%s: Very tight range detected (%.2f%% < %.2f%%)",
                                           symbol, rangeWidthPercent, VERY_TIGHT_RANGE));
            }
        }

        // Debug logging with your logger
        if (DEBUG_TRAP_ENABLED)
        {
            string logMsg = StringFormat("%s: %s with %.1f%% trap probability. Regime: %s, Dir: %s, Conf: %.1f%%. Reason: %s",
                                         symbol, result.recommendedAction, result.trapProbability,
                                         result.marketRegime, result.overrideDirection,
                                         result.overrideConfidence, result.reason);
            DebugTrapLogs("TRAP_RECOMMENDATION", logMsg);
        }
    }

    //+------------------------------------------------------------------+
    //| Calculate trap probability                                      |
    //+------------------------------------------------------------------+
    double CalculateTrapProbability(string symbol, ENUM_TIMEFRAMES timeframe, bool hasValidRange,
                                    double support, double resistance,
                                    int touchCountResistance, int touchCountSupport)
    {
        if (!hasValidRange)
            return 0;

        double probability = 0;

        // Calculate range width percentage
        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        double rangeWidthPercent = ((resistance - support) / support) * 100.0;

        // 1. Range tightness (tighter = more trap likely)
        if (rangeWidthPercent < VERY_TIGHT_RANGE)
            probability += 40;
        else if (rangeWidthPercent < TIGHT_RANGE_THRESHOLD)
            probability += 20;

        // 2. Multiple touches (more touches = more stops accumulated)
        int totalTouches = touchCountSupport + touchCountResistance;
        probability += MathMin(totalTouches * 5, 30); // Max 30% for touches

        // 3. Round number proximity
        if (IsNearRoundNumber(currentPrice))
            probability += 15;
        if (IsNearRoundNumber(resistance))
            probability += 10;
        if (IsNearRoundNumber(support))
            probability += 10;

        // 4. Recent failed breakouts
        int failedBreakouts = CountFailedBreakouts(symbol, timeframe, support, resistance);
        probability += failedBreakouts * 10;

        return MathMin(probability, 100);
    }

    //+------------------------------------------------------------------+
    //| Check if price is near round number                             |
    //+------------------------------------------------------------------+
    bool IsNearRoundNumber(double price)
    {
        // This is simplified - you should customize based on your symbols
        double base = MathFloor(price);

        // Check if close to .0000, .2500, .5000, .7500 for forex
        double fractional = price - base;
        if (MathAbs(fractional) < 0.0001 ||
            MathAbs(fractional - 0.25) < 0.0001 ||
            MathAbs(fractional - 0.50) < 0.0001 ||
            MathAbs(fractional - 0.75) < 0.0001)
        {
            return true;
        }

        // Check round base numbers
        if (MathMod(base, 100) == 0 || MathMod(base, 50) == 0 || MathMod(base, 20) == 0)
        {
            return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Count failed breakouts in recent history                        |
    //+------------------------------------------------------------------+
    int CountFailedBreakouts(string symbol, ENUM_TIMEFRAMES timeframe, double support, double resistance)
    {
        int failedCount = 0;
        int lookback = MathMin(100, TRAP_LOOKBACK_CANDLES * 3);

        for (int i = 1; i < lookback; i++)
        {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);

            // Check for breakout above resistance that failed
            if (high > resistance * 1.001)
            { // 0.1% break
                // If closed back in range, it's a failed breakout
                if (close < resistance)
                {
                    failedCount++;
                }
            }

            // Check for breakout below support that failed
            if (low < support * 0.999)
            { // 0.1% break
                // If closed back in range, it's a failed breakdown
                if (close > support)
                {
                    failedCount++;
                }
            }
        }

        // Debug logging with your logger
        if (DEBUG_TRAP_ENABLED)
        {
            string logMsg = StringFormat("%s: %d failed breakouts in last %d candles",
                                         symbol, failedCount, lookback);
            DebugTrapLogs("FAILED_BREAKOUTS", logMsg);
        }

        return failedCount;
    }

    //+------------------------------------------------------------------+
    //| Utility Functions                                               |
    //+------------------------------------------------------------------+
    double GetPipValue(string symbol)
    {
        // MQL5: Use TICKSIZE instead of POINT for more accuracy
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double lotSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

        if (tickSize > 0 && tickValue > 0 && lotSize > 0)
        {
            // Calculate pip value for standard lots (0.01 for micro, 0.1 for mini, 1.0 for standard)
            return (tickValue * tickSize * 10000); // Approximate pip value
        }

        // Fallback for older method
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        if (digits == 5 || digits == 3 || digits == 2)
        {
            return point * 10;
        }
        return point;
    }

    int CountTouches(string symbol, ENUM_TIMEFRAMES timeframe, double level, bool isResistance)
    {
        int touches = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;

        for (int i = 0; i < lookback; i++)
        {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);

            if (isResistance)
            {
                if (MathAbs(high - level) < tolerance)
                    touches++;
            }
            else
            {
                if (MathAbs(low - level) < tolerance)
                    touches++;
            }
        }

        return touches;
    }

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
        case PERIOD_W1:
            return "W1";
        case PERIOD_MN1:
            return "MN1";
        default:
            return "UNKNOWN";
        }
    }

    //+------------------------------------------------------------------+
    //| Quick check if price is in trap zone                            |
    //+------------------------------------------------------------------+
    bool IsInTrapZone(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        TrapAnalysisResult result = AnalyzeForTraps(symbol, timeframe);
        return result.isTrapZone && result.trapProbability > 70;
    }

    //+------------------------------------------------------------------+
    //| Get recommended action based on trap analysis                   |
    //+------------------------------------------------------------------+
    string GetRecommendedAction(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        TrapAnalysisResult result = AnalyzeForTraps(symbol, timeframe);
        return result.recommendedAction;
    }

    //+------------------------------------------------------------------+
    //| Get trap probability                                            |
    //+------------------------------------------------------------------+
    double GetTrapProbability(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        TrapAnalysisResult result = AnalyzeForTraps(symbol, timeframe);
        return result.trapProbability;
    }

    //+------------------------------------------------------------------+
    //| Display trap analysis results on chart                          |
    //+------------------------------------------------------------------+
    void DisplayTrapAnalysis(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        if (!DEBUG_TRAP_ENABLED)
            return;

        TrapAnalysisResult result = AnalyzeForTraps(symbol, timeframe);

        // Create visual display on chart
        string displayText =
            "=== INSTITUTIONAL TRAP DETECTOR ===\n" +
            StringFormat("Symbol: %s | Timeframe: %s\n", symbol, TimeframeToString(timeframe)) +
            StringFormat("Trap Probability: %.1f%%\n", result.trapProbability) +
            StringFormat("Trap Zone: %s\n", result.isTrapZone ? "YES ⚠️" : "NO ✅") +
            StringFormat("Recommended: %s\n", result.recommendedAction) +
            StringFormat("Reason: %s", result.reason);

        // Use Logger for chart display
        Logger::Log("TRAP_ANALYSIS", displayText, true, false);

        // Also log fast version for quick viewing
        string fastMsg = StringFormat("%s: %s (%.0f%% trap)", symbol, result.recommendedAction, result.trapProbability);
        if (result.isTrapZone)
        {
            Logger::LogError("TRAP_WARNING", fastMsg);
        }
    }
}

//+------------------------------------------------------------------+
//| Helper functions for easy integration                            |
//+------------------------------------------------------------------+

// Initialize trap detector with specific settings
void InitializeRangePackage(bool enableDebug = true)
{
    DEBUG_TRAP_ENABLED = enableDebug;
    if (DEBUG_TRAP_ENABLED)
    {
        DebugTrapLogs("TRAP_DETECTOR_INIT", "Trap Detector initialized with debug enabled");
    }
}

// Example usage function
void ExampleRangePackageUsage()
{
    // Initialize
    InitializeRangePackage(true);

    // Analyze for traps
    string symbol = Symbol();
    TrapAnalysisResult result = RangePackage::AnalyzeForTraps(symbol, PERIOD_H1);

    // Display results
    if (DEBUG_TRAP_ENABLED)
    {
        Logger::Log("TRAP_EXAMPLE", result.ToString(), true, true);

        // Show decision based on analysis
        if (result.isTrapZone)
        {
            string message = "Trap zone detected - " + result.recommendedAction;

            // Convert to appropriate direction for ShowDecisionFast
            int direction = 0;
            if (StringFind(result.recommendedAction, "BUY") >= 0)
                direction = 1;
            else if (StringFind(result.recommendedAction, "SELL") >= 0)
                direction = -1;

            Logger::ShowDecisionFast(symbol, direction, result.trapProbability / 100, message);
        }
        else
        {
            Logger::ShowScoreFast(symbol, result.trapProbability / 100,
                                  result.recommendedAction, result.trapProbability);
        }
    }

    // Check specific conditions
    bool inTrapZone = RangePackage::IsInTrapZone(symbol, PERIOD_H1);
    string action = RangePackage::GetRecommendedAction(symbol, PERIOD_H1);
    double trapProb = RangePackage::GetTrapProbability(symbol, PERIOD_H1);

    if (DEBUG_TRAP_ENABLED)
    {
        string statusMsg = StringFormat("In Trap Zone: %s | Action: %s | Trap Prob: %.1f%%",
                                        inTrapZone ? "YES" : "NO", action, trapProb);
        DebugTrapLogs("TRAP_STATUS", statusMsg);
    }
}
//+------------------------------------------------------------------+