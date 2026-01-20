

#include "../Headers/Enums.mqh"

// ====================== DECISION ENGINE INTERFACE ======================
struct DecisionEngineInterface
{
    // Basic fields
    string symbol;
    datetime analysisTime;
    string dominantDirection; // "BULLISH", "BEARISH", "NEUTRAL", "CONFLICTED"
    double overallConfidence; // 0-100

    // Core signal data needed for decision making
    bool isValid;
    double weightedScore;

    // Signal info (minimal)
    ENUM_ORDER_TYPE orderType;
    double signalConfidence;
    string signalReason;

    // Basic setup info (if available)
    double entryPrice;
    double stopLoss;
    double takeProfit1;
    double takeProfit2; // Added for multi-target strategies
    double positionSize;

    // MTF data (basic)
    // int mtfBullishCount;
    // int mtfBearishCount;
    // double mtfWeight;

    string extraInfo1;
    string extraInfo2;
    string extraInfo3;

    // ============== ENHANCED FIELDS FOR RANGE/TREND PACKAGES ==============
    string marketRegime;      // "TRENDING", "RANGING", "TIGHT_RANGE", "BREAKOUT", "VOLATILE", "UNKNOWN"
    string recommendedAction; // "TRADE", "AVOID", "FADE", "WAIT", "CLOSE"
    double trapProbability;   // 0-100
    bool isTrapZone;          // true if likely institutional trap
    bool isAvoidSignal;       // true if package says to avoid trading
    string trapReason;        // Explanation from trap detector

    // Additional range-specific fields
    double entryQualityScore;   // 0-100% (timing for range trade)
    double riskRewardScore;     // 0-100% (RR for range trade)
    string rangeBiasDirection;  // "BULLISH", "BEARISH", "NEUTRAL"
    double rangeBiasConfidence; // 0-100% confidence in bias
    string rangeAction;         // "FADE_EDGE", "WAIT_IN_MIDDLE", "AVOID_HIGH_TRAP", "NO_RANGE"

    // Range boundaries for reference
    double supportLevel;
    double resistanceLevel;
    int supportTouches;
    int resistanceTouches;

    // Component analysis flags
    bool hasComponentAnalysis; // true if component breakdown is available
    // ===========================================================

    ENUM_TIMEFRAMES timeframe; // Timeframe of analysis

    string packageType; // "TREND" or "RANGE"

    // Constructor
    DecisionEngineInterface()
    {
        symbol = "";
        analysisTime = 0;
        dominantDirection = "NEUTRAL";
        overallConfidence = 0;

        // Initialize new fields
        marketRegime = "UNKNOWN";
        recommendedAction = "TRADE";
        trapProbability = 0;
        isTrapZone = false;
        isAvoidSignal = false;
        trapReason = "";
        entryQualityScore = 0;
        riskRewardScore = 0;
        rangeBiasDirection = "NEUTRAL";
        rangeBiasConfidence = 0;
        rangeAction = "NO_RANGE";
        supportLevel = 0;
        resistanceLevel = 0;
        supportTouches = 0;
        resistanceTouches = 0;
        hasComponentAnalysis = false;
        timeframe = PERIOD_CURRENT;
        packageType = "NONE";   // "TREND" or "RANGE"

        isValid = false;
        weightedScore = 0;
        orderType = ORDER_TYPE_BUY_LIMIT;
        signalConfidence = 0;
        signalReason = "";
        entryPrice = 0;
        stopLoss = 0;
        takeProfit1 = 0;
        takeProfit2 = 0;
        positionSize = 0;
        extraInfo1 = "";
        extraInfo2 = "";
        extraInfo3 = "";
    }

    // Check if valid
    bool IsValid() const
    {
        return (analysisTime > 0 && symbol != "" && overallConfidence >= 0);
    }

    // Check if this is a range package
    bool IsRangePackage() const
    {
        return (marketRegime == "RANGING" ||
                marketRegime == "TIGHT_RANGE" ||
                marketRegime == "CONSOLIDATION");
    }

    // Check if this is a trend package
    bool IsTrendPackage() const
    {
        return (marketRegime == "TRENDING" ||
                marketRegime == "TREND_RESUMING" ||
                marketRegime == "TREND_CONFIRMED" ||
                marketRegime == "BREAKOUT");
    }

    // Check if we should avoid trading
    bool ShouldAvoid() const
    {
        return (isAvoidSignal ||
                recommendedAction == "AVOID" ||
                rangeAction == "AVOID_HIGH_TRAP" ||
                (IsRangePackage() && trapProbability > 70) ||
                (IsRangePackage() && recommendedAction == "AVOID"));
    }

    // Check if this is a fade (counter-trend) signal
    bool IsFadeSignal() const
    {
        return (recommendedAction == "FADE" ||
                (IsRangePackage() && rangeAction == "FADE_EDGE"));
    }

    // Check if we should wait
    bool ShouldWait() const
    {
        return (recommendedAction == "WAIT" ||
                rangeAction == "WAIT_IN_MIDDLE" ||
                overallConfidence < 40);
    }

    // Get detailed signal string
    string GetDetailedSignal() const
    {
        if (ShouldAvoid())
            return "AVOID";
        if (ShouldWait())
            return "WAIT";

        if (IsRangePackage())
        {
            if (IsFadeSignal())
            {
                if (rangeBiasDirection == "BULLISH")
                    return "RANGE-FADE-BUY";
                else if (rangeBiasDirection == "BEARISH")
                    return "RANGE-FADE-SELL";
            }
            return "RANGE-TRADE";
        }
        else if (IsTrendPackage())
        {
            if (dominantDirection == "BULLISH")
                return "TREND-BUY";
            else if (dominantDirection == "BEARISH")
                return "TREND-SELL";
        }

        return "UNKNOWN";
    }

    // Get simple signal string
    string GetSimpleSignal() const
    {
        if (ShouldAvoid())
            return "AVOID";
        if (ShouldWait())
            return "WAIT";

        if (dominantDirection == "BULLISH")
            return "BUY";
        else if (dominantDirection == "BEARISH")
            return "SELL";
        else
            return "NEUTRAL";
    }

    // Check if confidence meets minimum threshold
    bool MeetsConfidenceThreshold(double threshold) const
    {
        return (overallConfidence >= threshold);
    }

    // Get position size multiplier based on regime
    double GetPositionSizeMultiplier() const
    {
        if (ShouldAvoid() || trapProbability > 80)
            return 0.0;

        if (IsRangePackage())
        {
            if (trapProbability > 75)
                return 0.5;
            if (entryQualityScore > 60)
                return 1.0;
            return 0.75;
        }
        else if (IsTrendPackage())
        {
            if (overallConfidence > 70)
                return 1.2;
            if (overallConfidence > 70)
                return 1.0;
            return 0.8;
        }

        return 0.5;
    }

    // Get stop loss multiplier based on regime
    double GetStopLossMultiplier() const
    {
        if (IsRangePackage())
        {
            if (trapProbability > 75)
                return 2.0; // Wider stops for high trap zones
            if (rangeAction == "FADE_EDGE")
                return 1.5; // Wider for fade trades
            return 1.0;
        }
        else if (IsTrendPackage())
        {
            return 1.0; // Normal stops for trends
        }

        return 1.5; // Default wider for unknown
    }

    // Get range width if available
    double GetRangeWidth() const
    {
        if (supportLevel > 0 && resistanceLevel > supportLevel)
        {
            return (resistanceLevel - supportLevel) / supportLevel * 100.0;
        }
        return 0.0;
    }

    // Check if price is near support
    bool IsNearSupport(double currentPrice, double atr = 0.0) const
    {
        if (supportLevel <= 0 || currentPrice <= 0)
            return false;

        double distance = MathAbs(currentPrice - supportLevel);
        if (atr > 0)
            return (distance <= atr * 1.5);
        return (distance / currentPrice * 100.0 <= 0.2); // Within 0.2%
    }

    // Check if price is near resistance
    bool IsNearResistance(double currentPrice, double atr = 0.0) const
    {
        if (resistanceLevel <= 0 || currentPrice <= 0)
            return false;

        double distance = MathAbs(currentPrice - resistanceLevel);
        if (atr > 0)
            return (distance <= atr * 1.5);
        return (distance / currentPrice * 100.0 <= 0.2); // Within 0.2%
    }

    // Convert to string for logging
    string ToString() const
    {
        string result = StringFormat("%s | Dir: %s | Conf: %.1f%% | Regime: %s | Action: %s",
                                     symbol, dominantDirection, overallConfidence,
                                     marketRegime, GetDetailedSignal());

        if (IsRangePackage())
        {
            result += StringFormat(" | Trap: %.1f%% | Bias: %s (%.1f%%) | EntryQ: %.1f%% | R/R: %.1f%%",
                                   trapProbability, rangeBiasDirection, rangeBiasConfidence,
                                   entryQualityScore, riskRewardScore);

            if (supportLevel > 0 && resistanceLevel > supportLevel)
            {
                double rangeWidth = GetRangeWidth();
                result += StringFormat(" | Range: %.5f-%.5f (%.2f%%) | Touches: %d/%d",
                                       supportLevel, resistanceLevel, rangeWidth,
                                       supportTouches, resistanceTouches);
            }
        }

        if (ShouldAvoid())
            result += " | AVOID";
        if (ShouldWait())
            result += " | WAIT";

        return result;
    }

    // Get compact string for display
    string ToCompactString() const
    {
        return StringFormat("%s: %s %.0f%% (%s)",
                            symbol,
                            GetSimpleSignal(),
                            overallConfidence,
                            marketRegime);
    }
    // Add this function somewhere before the DecisionEngineInterface struct or inside it
    string TimeframeToString(ENUM_TIMEFRAMES tf) const
    {
        switch (tf)
        {
        case PERIOD_M1:
            return "M1";
        case PERIOD_M2:
            return "M2";
        case PERIOD_M3:
            return "M3";
        case PERIOD_M4:
            return "M4";
        case PERIOD_M5:
            return "M5";
        case PERIOD_M6:
            return "M6";
        case PERIOD_M10:
            return "M10";
        case PERIOD_M12:
            return "M12";
        case PERIOD_M15:
            return "M15";
        case PERIOD_M20:
            return "M20";
        case PERIOD_M30:
            return "M30";
        case PERIOD_H1:
            return "H1";
        case PERIOD_H2:
            return "H2";
        case PERIOD_H3:
            return "H3";
        case PERIOD_H4:
            return "H4";
        case PERIOD_H6:
            return "H6";
        case PERIOD_H8:
            return "H8";
        case PERIOD_H12:
            return "H12";
        case PERIOD_D1:
            return "D1";
        case PERIOD_W1:
            return "W1";
        case PERIOD_MN1:
            return "MN1";
        default:
            return IntegerToString(tf);
        }
    }

    // Get debug info string
    string GetDebugInfo() const
    {
        string debug = "=== DECISION ENGINE INTERFACE DEBUG ===\n";
        debug += StringFormat("Symbol: %s | Time: %s\n", symbol, TimeToString(analysisTime));
        debug += StringFormat("Valid: %s | Timeframe: %s\n", isValid ? "YES" : "NO", TimeframeToString(timeframe));
        debug += StringFormat("Signal: %s | Confidence: %.1f%% | Weighted: %.1f\n",
                              dominantDirection, overallConfidence, weightedScore);
        debug += StringFormat("Regime: %s | Package Type: %s\n",
                              marketRegime, IsRangePackage() ? "RANGE" : (IsTrendPackage() ? "TREND" : "UNKNOWN"));
        debug += StringFormat("Action: %s | Avoid: %s | Wait: %s\n",
                              recommendedAction, ShouldAvoid() ? "YES" : "NO", ShouldWait() ? "YES" : "NO");

        if (IsRangePackage())
        {
            debug += "--- RANGE SPECIFIC ---\n";
            debug += StringFormat("Trap: %.1f%% | TrapZone: %s | Reason: %s\n",
                                  trapProbability, isTrapZone ? "YES" : "NO", trapReason);
            debug += StringFormat("Range Bias: %s (%.1f%%) | Range Action: %s\n",
                                  rangeBiasDirection, rangeBiasConfidence, rangeAction);
            debug += StringFormat("Entry Quality: %.1f%% | R/R Score: %.1f%%\n",
                                  entryQualityScore, riskRewardScore);

            if (supportLevel > 0 && resistanceLevel > supportLevel)
            {
                double rangeWidth = GetRangeWidth();
                debug += StringFormat("Support: %.5f (%d touches) | Resistance: %.5f (%d touches)\n",
                                      supportLevel, supportTouches, resistanceLevel, resistanceTouches);
                debug += StringFormat("Range Width: %.2f%% | Current Price: %.5f\n",
                                      rangeWidth, entryPrice);
            }
        }

        debug += "--- TRADE SETUP ---\n";
        debug += StringFormat("Order Type: %d | Entry: %.5f | Stop: %.5f | TP1: %.5f | TP2: %.5f\n",
                              orderType, entryPrice, stopLoss, takeProfit1, takeProfit2);
        debug += StringFormat("Position Size: %.2f | Multiplier: %.2f\n",
                              positionSize, GetPositionSizeMultiplier());

        if (extraInfo1 != "")
            debug += StringFormat("Extra1: %s\n", extraInfo1);
        if (extraInfo2 != "")
            debug += StringFormat("Extra2: %s\n", extraInfo2);
        if (extraInfo3 != "")
            debug += StringFormat("Extra3: %s\n", extraInfo3);

        return debug;
    }
};

//+------------------------------------------------------------------+
//| Market Analysis Structure                                        |
//+------------------------------------------------------------------+
struct MarketAnalysis
{
    ENUM_ROOT_REGIME rootState;
    ENUM_MARKET_STATE state;
    ENUM_MARKET_STATE nextLikelyState;
    string action;
    ENUM_POSITION_SIZE positionSize;
    double stopDistance;
    double takeProfitDistance;
    double riskRewardRatio;
    string direction;
    double confidence;
    string description;

    // Quick helper methods
    bool IsTrending() const { return rootState == REGIME_TRENDING; }
    bool IsRanging() const { return rootState == REGIME_RANGING; }
    bool IsContraction() const { return state == STATE_CONTRACTION; }
    bool IsExpansion() const { return state == STATE_EXPANSION; }

    // String representation
    string ToString() const
    {
        string posSizeStr;
        switch (positionSize)
        {
        case SIZE_ZERO:
            posSizeStr = "ZERO";
            break;
        case SIZE_VERY_SMALL:
            posSizeStr = "VERY SMALL";
            break;
        case SIZE_SMALL:
            posSizeStr = "SMALL";
            break;
        case SIZE_MEDIUM:
            posSizeStr = "MEDIUM";
            break;
        case SIZE_LARGE:
            posSizeStr = "LARGE";
            break;
        }

        return StringFormat(
            "Root: %s | State: %s (%.0f%%) | Next: %s\n" +
                "Action: %s | Position: %s | Dir: %s\n" +
                "Stop: %.1f pips | TP: %.1f pips | R/R: %.1f\n" +
                "Description: %s",
            GetRootStateString(rootState),
            GetStateString(state),
            confidence,
            GetStateString(nextLikelyState),
            action,
            posSizeStr,
            direction,
            stopDistance * 10000, // Convert to pips for Forex
            takeProfitDistance * 10000,
            riskRewardRatio,
            description);
    }

    static string GetRootStateString(ENUM_ROOT_REGIME regime)
    {
        switch (regime)
        {
        case REGIME_TRENDING:
            return "TRENDING";
        case REGIME_RANGING:
            return "RANGING";
        default:
            return "UNKNOWN";
        }
    }

    static string GetStateString(ENUM_MARKET_STATE state)
    {
        switch (state)
        {
        case STATE_RANGING_LOW_VOL:
            return "Ranging Low Vol";
        case STATE_RANGING_HIGH_VOL:
            return "Ranging High Vol";
        case STATE_TRENDING_LOW_VOL:
            return "Trending Low Vol";
        case STATE_TRENDING_HIGH_VOL:
            return "Trending High Vol";
        case STATE_CONTRACTION:
            return "Contraction";
        case STATE_EXPANSION:
            return "Expansion";
        case STATE_CHURN:
            return "Churn";
        default:
            return "Unknown";
        }
    }
};