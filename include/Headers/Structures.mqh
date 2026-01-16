// DecisionEngineInterface.mqh

// #ifndef DECISION_ENGINE_INTERFACE_MQH
// #define DECISION_ENGINE_INTERFACE_MQH

// ====================== TRADE PACKAGE INTERFACE ======================
// Minimal interface that contains ONLY what DecisionEngine needs
// struct DecisionEngineInterface
// {

//     DecisionEngineInterface() {
//     }
// };

// #endif

// ====================== DECISION ENGINE INTERFACE ======================
struct DecisionEngineInterface
{
    // Basic fields
    string symbol;
    datetime analysisTime;
    string dominantDirection; // "BULLISH", "BEARISH", "NEUTRAL"
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
    double positionSize;

    // MTF data (basic)
    // int mtfBullishCount;
    // int mtfBearishCount;
    // double mtfWeight;

    string extraInfo1;
    string extraInfo2;
    string extraInfo3;

    // ============== NEW FIELDS FOR RANGE PACKAGES ==============
    string marketRegime;      // "TRENDING", "RANGING", "TIGHT_RANGE", "BREAKOUT", "VOLATILE", "UNKNOWN"
    string recommendedAction; // "TRADE", "AVOID", "FADE", "WAIT", "CLOSE"
    double trapProbability;   // 0-100
    bool isTrapZone;          // true if likely institutional trap
    bool isAvoidSignal;       // true if package says to avoid trading
    string trapReason;        // Explanation from trap detector
    // ===========================================================

    ENUM_TIMEFRAMES timeframe; // Timeframe of analysis

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
        timeframe = PERIOD_CURRENT;

        isValid = false;
        weightedScore = 0;
        orderType = ORDER_TYPE_BUY_LIMIT;
        signalConfidence = 0;
        signalReason = "";
        entryPrice = 0;
        stopLoss = 0;
        takeProfit1 = 0;
        positionSize = 0;
        // mtfBullishCount = 0;
        // mtfBearishCount = 0;
        // mtfWeight = 0;
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
        return (marketRegime == "RANGING" || marketRegime == "TIGHT_RANGE");
    }

    // Check if we should avoid trading
    bool ShouldAvoid() const
    {
        return (isAvoidSignal || recommendedAction == "AVOID" ||
                (IsRangePackage() && recommendedAction == "AVOID"));
    }

    // Get simple signal string
    string GetSimpleSignal() const
    {
        if (IsRangePackage())
        {
            if (recommendedAction == "AVOID")
                return "RANGE-AVOID";
            else if (recommendedAction == "FADE")
                return "RANGE-FADE";
            else if (recommendedAction == "WAIT")
                return "RANGE-WAIT";
        }

        if (dominantDirection == "BULLISH")
            return "BUY";
        else if (dominantDirection == "BEARISH")
            return "SELL";
        else
            return "NEUTRAL";
    }

    // Convert to string for logging
    string ToString() const
    {
        return StringFormat("%s | Dir: %s | Conf: %.1f%% | Regime: %s | Action: %s | Trap: %.1f%% | Avoid: %s",
                            symbol, dominantDirection, overallConfidence,
                            marketRegime, recommendedAction, trapProbability,
                            ShouldAvoid() ? "YES" : "NO");
    }
};



//+------------------------------------------------------------------+
//| Market Analysis Structure                                        |
//+------------------------------------------------------------------+
struct MarketAnalysis
  {
   ENUM_ROOT_REGIME     rootState;
   ENUM_MARKET_STATE   state;
   ENUM_MARKET_STATE   nextLikelyState;
   string              action;
   ENUM_POSITION_SIZE  positionSize;
   double              stopDistance;
   double              takeProfitDistance;
   double              riskRewardRatio;
   string              direction;
   double              confidence;
   string              description;
   
   // Quick helper methods
   bool IsTrending() const { return rootState == REGIME_TRENDING; }
   bool IsRanging() const { return rootState == REGIME_RANGING; }
   bool IsContraction() const { return state == STATE_CONTRACTION; }
   bool IsExpansion() const { return state == STATE_EXPANSION; }
   
   // String representation
   string ToString() const
     {
      string posSizeStr;
      switch(positionSize)
        {
         case SIZE_ZERO: posSizeStr = "ZERO"; break;
         case SIZE_VERY_SMALL: posSizeStr = "VERY SMALL"; break;
         case SIZE_SMALL: posSizeStr = "SMALL"; break;
         case SIZE_MEDIUM: posSizeStr = "MEDIUM"; break;
         case SIZE_LARGE: posSizeStr = "LARGE"; break;
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
      switch(regime)
        {
         case REGIME_TRENDING: return "TRENDING";
         case REGIME_RANGING: return "RANGING";
         default: return "UNKNOWN";
        }
     }
   
   static string GetStateString(ENUM_MARKET_STATE state)
     {
      switch(state)
        {
         case STATE_RANGING_LOW_VOL: return "Ranging Low Vol";
         case STATE_RANGING_HIGH_VOL: return "Ranging High Vol";
         case STATE_TRENDING_LOW_VOL: return "Trending Low Vol";
         case STATE_TRENDING_HIGH_VOL: return "Trending High Vol";
         case STATE_CONTRACTION: return "Contraction";
         case STATE_EXPANSION: return "Expansion";
         case STATE_CHURN: return "Churn";
         default: return "Unknown";
        }
     }
  };