//+------------------------------------------------------------------+
//|                                           RangePackage.mqh       |
//|              PURE Institutional Trap Detection (No Regime)      |
//|          ENHANCED WITH COMPONENT & OVERALL DIRECTION/CONFIDENCE |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "2.10"
#property strict

#include <Arrays\ArrayDouble.mqh>
#include <Trade\SymbolInfo.mqh>

#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"  // Added for MathUtils
#include "../Data/IndicatorManager.mqh"  // INCLUDE THE ACTUAL INDICATOR MANAGER

// ====================== DEBUG SETTINGS ======================
bool DEBUG_TRAP_ENABLED = true;

// Simple debug function using Logger
void DebugTrapLogs(string context, string message)
{
    if (DEBUG_TRAP_ENABLED)
    {
        Logger::Log(context, message, true, true);
    }
}

//+------------------------------------------------------------------+
//| Enhanced Trap Weights Structure                                 |
//+------------------------------------------------------------------+
struct TrapWeights 
{
    // CORE RANGE COMPONENTS
    double tightnessWeight;           // Range compression
    double symmetryWeight;            // Balanced touches both sides
    double consolidationTimeWeight;   // Time spent in range
    
    // PRICE ACTION COMPONENTS
    double touchQualityWeight;        // Wick vs. body touches
    double rejectionWeight;           // Strong rejection candles
    double failedBreakoutWeight;      // Failed break attempts
    double liquidityWeight;           // Volume at boundaries
    
    // MARKET STRUCTURE
    double higherTimeframeWeight;     // HTF alignment
    double roundNumberWeight;         // Psychological levels
    double sessionWeight;             // London/NY session overlaps
    
    // Constructor with optimal defaults
    TrapWeights()
    {
        // CORE (Total: 40%)
        tightnessWeight = 0.25;       // 25%
        symmetryWeight = 0.10;        // 10%
        consolidationTimeWeight = 0.05; // 5%
        
        // PRICE ACTION (Total: 45%)
        touchQualityWeight = 0.15;    // 15%
        rejectionWeight = 0.15;       // 15%
        failedBreakoutWeight = 0.10;  // 10%
        liquidityWeight = 0.05;       // 5%
        
        // MARKET STRUCTURE (Total: 25%)
        higherTimeframeWeight = 0.10; // 10%
        roundNumberWeight = 0.10;     // 10%
        sessionWeight = 0.05;         // 5%
    }
    
    // Normalize weights to 100%
    void Normalize()
    {
        double total = tightnessWeight + symmetryWeight + consolidationTimeWeight +
                      touchQualityWeight + rejectionWeight + failedBreakoutWeight + liquidityWeight +
                      higherTimeframeWeight + roundNumberWeight + sessionWeight;
        
        if(total > 0)
        {
            double factor = 1.0 / total;
            tightnessWeight *= factor;
            symmetryWeight *= factor;
            consolidationTimeWeight *= factor;
            touchQualityWeight *= factor;
            rejectionWeight *= factor;
            failedBreakoutWeight *= factor;
            liquidityWeight *= factor;
            higherTimeframeWeight *= factor;
            roundNumberWeight *= factor;
            sessionWeight *= factor;
        }
    }
};

//+------------------------------------------------------------------+
//| Component Direction & Strength Structure                        |
//+------------------------------------------------------------------+
struct ComponentAnalysis
{
    string name;                     // Component name
    string direction;                // "BULLISH", "BEARISH", "NEUTRAL", "CONFLICTED"
    double strength;                 // 0-100% (how strong is this signal)
    double confidence;               // 0-100% (confidence in this assessment)
    string reasoning;                // Why this direction/strength
    
    ComponentAnalysis()
    {
        name = "";
        direction = "NEUTRAL";
        strength = 0;
        confidence = 0;
        reasoning = "";
    }
    
    string ToString() const
    {
        return StringFormat("%s: %s (%.0f%% strength, %.0f%% confidence) - %s",
                           name, direction, strength, confidence, reasoning);
    }
};

//+------------------------------------------------------------------+
//| Enhanced Range Analysis Result                                  |
//+------------------------------------------------------------------+
struct RangeAnalysisResult
{
    // RANGE IDENTIFICATION
    string marketRegime;              // "RANGING", "TIGHT_RANGE", "TRENDING", "UNKNOWN"
    double rangeWidthPercent;         // Actual range width
    bool isValidRange;                // Is there a detectable range?
    
    // TRAP DETECTION (Range-specific)
    double trapProbability;           // 0-100% probability of trap
    bool isTrapZone;                  // Is this a likely trap?
    
    // OVERALL DIRECTION & CONFIDENCE (NEW)
    string overallDirection;          // "BULLISH", "BEARISH", "NEUTRAL", "CONFLICTED"
    double overallConfidence;         // 0-100% confidence in overall direction
    string overallReasoning;          // Why this overall direction
    
    // RANGE-BASED DIRECTIONAL BIAS
    string rangeBiasDirection;        // "BULLISH", "BEARISH", "NEUTRAL"
    double rangeBiasConfidence;       // 0-100% confidence in bias
    string rangeBiasReason;           // Why this bias exists
    
    // EXECUTION GUIDANCE
    string rangeAction;               // "FADE_EDGE", "WAIT_IN_MIDDLE", "AVOID_HIGH_TRAP", "NO_RANGE"
    double entryQualityScore;         // 0-100% (timing for range trade)
    double riskRewardScore;           // 0-100% (RR for range trade)
    
    // RANGE BOUNDARIES
    double supportLevel;
    double resistanceLevel;
    int supportTouches;
    int resistanceTouches;
    int totalTouches;
    
    // COMPONENT BREAKDOWN WITH DIRECTION (ENHANCED)
    struct ComponentScores
    {
        // Strength scores (0-100%)
        double tightnessScore;
        double symmetryScore;
        double consolidationTimeScore;
        double touchQualityScore;
        double rejectionScore;
        double failedBreakoutScore;
        double liquidityScore;
        double higherTimeframeScore;
        double roundNumberScore;
        double sessionScore;
        
        // Direction assessments
        ComponentAnalysis tightnessAnalysis;
        ComponentAnalysis symmetryAnalysis;
        ComponentAnalysis consolidationTimeAnalysis;
        ComponentAnalysis touchQualityAnalysis;
        ComponentAnalysis rejectionAnalysis;
        ComponentAnalysis failedBreakoutAnalysis;
        ComponentAnalysis liquidityAnalysis;
        ComponentAnalysis higherTimeframeAnalysis;
        ComponentAnalysis roundNumberAnalysis;
        ComponentAnalysis sessionAnalysis;
        
        // All components array for easy iteration
        ComponentAnalysis components[9];
        
        ComponentScores()
        {
            tightnessScore = 0;
            symmetryScore = 0;
            consolidationTimeScore = 0;
            touchQualityScore = 0;
            rejectionScore = 0;
            failedBreakoutScore = 0;
            liquidityScore = 0;
            higherTimeframeScore = 0;
            roundNumberScore = 0;
            sessionScore = 0;
            
            // Initialize component names
            tightnessAnalysis.name = "Tightness";
            symmetryAnalysis.name = "Symmetry";
            consolidationTimeAnalysis.name = "Consolidation Time";
            touchQualityAnalysis.name = "Touch Quality";
            rejectionAnalysis.name = "Rejection";
            failedBreakoutAnalysis.name = "Failed Breakouts";
            liquidityAnalysis.name = "Liquidity";
            higherTimeframeAnalysis.name = "HTF Alignment";
            roundNumberAnalysis.name = "Round Numbers";
            sessionAnalysis.name = "Session";
            
            // Initialize array
            components[0] = tightnessAnalysis;
            components[1] = symmetryAnalysis;
            components[2] = consolidationTimeAnalysis;
            components[3] = touchQualityAnalysis;
            components[4] = rejectionAnalysis;
            components[5] = failedBreakoutAnalysis;
            components[6] = liquidityAnalysis;
            components[7] = higherTimeframeAnalysis;
            components[8] = roundNumberAnalysis;
        }
        
        // Update array after individual assignments
        void UpdateArray()
        {
            components[0] = tightnessAnalysis;
            components[1] = symmetryAnalysis;
            components[2] = consolidationTimeAnalysis;
            components[3] = touchQualityAnalysis;
            components[4] = rejectionAnalysis;
            components[5] = failedBreakoutAnalysis;
            components[6] = liquidityAnalysis;
            components[7] = higherTimeframeAnalysis;
            components[8] = roundNumberAnalysis;
        }
        
        // Get component by index
        ComponentAnalysis GetComponent(int index) const
        {
            if(index >= 0 && index < 9)
                return components[index];
            ComponentAnalysis empty;
            return empty;
        }
        
        // Get all components as string
        string ToString() const
        {
            string result = "=== COMPONENT ANALYSIS ===\n";
            for(int i = 0; i < 9; i++)
            {
                result += components[i].ToString() + "\n";
            }
            result += sessionAnalysis.ToString() + "\n";
            return result;
        }
    };
    
    ComponentScores scores;
    string scoreBreakdown;            // Human-readable breakdown
    
    // Constructor
    RangeAnalysisResult()
    {
        marketRegime = "UNKNOWN";
        rangeWidthPercent = 0;
        isValidRange = false;
        trapProbability = 0;
        isTrapZone = false;
        overallDirection = "NEUTRAL";
        overallConfidence = 0;
        overallReasoning = "No analysis performed";
        rangeBiasDirection = "NEUTRAL";
        rangeBiasConfidence = 0;
        rangeAction = "NO_RANGE";
        entryQualityScore = 0;
        riskRewardScore = 0;
        supportLevel = 0;
        resistanceLevel = 0;
        supportTouches = 0;
        resistanceTouches = 0;
        totalTouches = 0;
        scoreBreakdown = "";
        rangeBiasReason = "No range detected";
    }
    
    // Simple output
    string ToString() const
    {
        if(!isValidRange) {
            return StringFormat("No valid range | Regime: %s", marketRegime);
        }
        
        return StringFormat(
            "Overall: %s (%.0f%% confidence) | Range: %.1f%% width | Trap: %.0f%% | Bias: %s (%.0f%%) | Action: %s",
            overallDirection, overallConfidence, rangeWidthPercent, trapProbability,
            rangeBiasDirection, rangeBiasConfidence, rangeAction
        );
    }
    
    // Detailed output
    string ToDetailedString() const
    {
        if(!isValidRange) {
            return "=== NO VALID RANGE DETECTED ===\n" +
                   StringFormat("Market Regime: %s", marketRegime);
        }
        
        string details = "=== RANGE ANALYSIS RESULTS ===\n";
        details += StringFormat("Support: %.5f (%d touches)\n", supportLevel, supportTouches);
        details += StringFormat("Resistance: %.5f (%d touches)\n", resistanceLevel, resistanceTouches);
        details += StringFormat("Range Width: %.2f%% | Regime: %s\n", rangeWidthPercent, marketRegime);
        details += StringFormat("Trap Probability: %.1f%% | Trap Zone: %s\n", 
                               trapProbability, isTrapZone ? "YES" : "NO");
        details += StringFormat("Overall Direction: %s (%.1f%% confidence)\n", 
                               overallDirection, overallConfidence);
        details += StringFormat("Overall Reasoning: %s\n", overallReasoning);
        details += StringFormat("Range Bias: %s (%.1f%% confidence)\n", 
                               rangeBiasDirection, rangeBiasConfidence);
        details += StringFormat("Action: %s | Entry Quality: %.1f%% | R/R Score: %.1f%%\n",
                               rangeAction, entryQualityScore, riskRewardScore);
        details += StringFormat("Range Reason: %s\n", rangeBiasReason);
        
        details += scores.ToString();
        
        return details;
    }
    
    // Get specific component analysis
    ComponentAnalysis GetComponentAnalysis(string componentName) const
    {
        if(componentName == "Tightness") return scores.tightnessAnalysis;
        if(componentName == "Symmetry") return scores.symmetryAnalysis;
        if(componentName == "Consolidation Time") return scores.consolidationTimeAnalysis;
        if(componentName == "Touch Quality") return scores.touchQualityAnalysis;
        if(componentName == "Rejection") return scores.rejectionAnalysis;
        if(componentName == "Failed Breakouts") return scores.failedBreakoutAnalysis;
        if(componentName == "Liquidity") return scores.liquidityAnalysis;
        if(componentName == "HTF Alignment") return scores.higherTimeframeAnalysis;
        if(componentName == "Round Numbers") return scores.roundNumberAnalysis;
        if(componentName == "Session") return scores.sessionAnalysis;
        
        ComponentAnalysis empty;
        return empty;
    }
};

//+------------------------------------------------------------------+
//| Main Range Intelligence Namespace                               |
//+------------------------------------------------------------------+
namespace RangeIntelligence
{
    // Configuration
    input int TRAP_LOOKBACK_CANDLES = 8;     // Candles to analyze for traps
    input double TIGHT_RANGE_THRESHOLD = 1.5; // % width for tight range
    input double VERY_TIGHT_RANGE = 0.8;      // % width for very tight range
    input int MIN_TOUCHES_FOR_TRAP = 2;       // Min touches to consider level valid
    
    // Weights (can be configured via input if desired)
    static TrapWeights m_weights;
    
    // Static IndicatorManager instance - will be set from outside
    static IndicatorManager *m_indicatorManager = NULL;

    //+------------------------------------------------------------------+
    //| Set the IndicatorManager instance                               |
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
    //| Get ATR using IndicatorManager                                  |
    //+------------------------------------------------------------------+
    double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period = 14)
    {
        if (m_indicatorManager != NULL)
        {
            // FIXED: Use 'tf' parameter name instead of 'timeframe'
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
    //| Detect price range                                              |
    //+------------------------------------------------------------------+
    bool DetectRange(string symbol, ENUM_TIMEFRAMES timeframe, double &support, double &resistance,
                     int &touchCountResistance, int &touchCountSupport, double &rangeWidthPercent)
    {
        support = 0;
        resistance = 0;
        touchCountResistance = 0;
        touchCountSupport = 0;
        rangeWidthPercent = 0;

        int candles = TRAP_LOOKBACK_CANDLES;
        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

        // Additional price trend check
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

        rangeWidthPercent = ((resistance - support) / support) * 100.0;

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
        if (touchCountResistance < MIN_TOUCHES_FOR_TRAP && touchCountSupport < MIN_TOUCHES_FOR_TRAP)
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
    //| Calculate component directions and strengths                     |
    //+------------------------------------------------------------------+
    void CalculateComponentAnalysis(string symbol, ENUM_TIMEFRAMES timeframe,
                                  double support, double resistance,
                                  int touchesSupport, int touchesResistance,
                                  double rangeWidthPercent, double currentPrice,
                                  RangeAnalysisResult &result)
    {
        double atr = GetATR(symbol, timeframe, 14);
        
        // 1. TIGHTNESS ANALYSIS
        result.scores.tightnessScore = CalculateTightnessScore(rangeWidthPercent);
        result.scores.tightnessAnalysis.strength = result.scores.tightnessScore;
        result.scores.tightnessAnalysis.confidence = 80; // High confidence in measurement
        if(rangeWidthPercent < VERY_TIGHT_RANGE) {
            result.scores.tightnessAnalysis.direction = "BEARISH"; // Very tight ranges favor bears (traps)
            result.scores.tightnessAnalysis.reasoning = "Extremely tight range favors institutional traps";
        } else if(rangeWidthPercent < TIGHT_RANGE_THRESHOLD) {
            result.scores.tightnessAnalysis.direction = "BEARISH"; // Tight ranges favor bears
            result.scores.tightnessAnalysis.reasoning = "Tight range suggests compression before breakout";
        } else {
            result.scores.tightnessAnalysis.direction = "NEUTRAL";
            result.scores.tightnessAnalysis.reasoning = "Normal range width, no directional bias";
        }
        
        // 2. SYMMETRY ANALYSIS
        result.scores.symmetryScore = CalculateSymmetryScore(touchesSupport, touchesResistance);
        result.scores.symmetryAnalysis.strength = result.scores.symmetryScore;
        result.scores.symmetryAnalysis.confidence = 70;
        if(touchesSupport > touchesResistance * 1.5) {
            result.scores.symmetryAnalysis.direction = "BULLISH"; // More support touches = bullish pressure
            result.scores.symmetryAnalysis.reasoning = StringFormat("More support touches (%d vs %d) suggests buying pressure",
                                                                   touchesSupport, touchesResistance);
        } else if(touchesResistance > touchesSupport * 1.5) {
            result.scores.symmetryAnalysis.direction = "BEARISH"; // More resistance touches = bearish pressure
            result.scores.symmetryAnalysis.reasoning = StringFormat("More resistance touches (%d vs %d) suggests selling pressure",
                                                                   touchesResistance, touchesSupport);
        } else {
            result.scores.symmetryAnalysis.direction = "NEUTRAL";
            result.scores.symmetryAnalysis.reasoning = "Balanced touches on both sides";
        }
        
        // 3. CONSOLIDATION TIME ANALYSIS
        result.scores.consolidationTimeScore = CalculateConsolidationTime(symbol, timeframe);
        result.scores.consolidationTimeAnalysis.strength = result.scores.consolidationTimeScore;
        result.scores.consolidationTimeAnalysis.confidence = 75;
        if(result.scores.consolidationTimeScore > 70) {
            result.scores.consolidationTimeAnalysis.direction = "BEARISH"; // Longer consolidation favors bears
            result.scores.consolidationTimeAnalysis.reasoning = "Extended consolidation increases trap probability";
        } else if(result.scores.consolidationTimeScore > 40) {
            result.scores.consolidationTimeAnalysis.direction = "NEUTRAL";
            result.scores.consolidationTimeAnalysis.reasoning = "Moderate consolidation time";
        } else {
            result.scores.consolidationTimeAnalysis.direction = "NEUTRAL";
            result.scores.consolidationTimeAnalysis.reasoning = "Short consolidation period";
        }
        
        // 4. TOUCH QUALITY ANALYSIS
        result.scores.touchQualityScore = CalculateTouchQuality(symbol, timeframe, support, resistance);
        result.scores.touchQualityAnalysis.strength = result.scores.touchQualityScore;
        result.scores.touchQualityAnalysis.confidence = 75;
        if(result.scores.touchQualityScore > 70) {
            // High touch quality (wick touches) suggests strong institutional activity
            double supportQuality = CalculateSupportTouchQuality(symbol, timeframe, support);
            double resistanceQuality = CalculateResistanceTouchQuality(symbol, timeframe, resistance);
            
            if(supportQuality > resistanceQuality * 1.2) {
                result.scores.touchQualityAnalysis.direction = "BULLISH";
                result.scores.touchQualityAnalysis.reasoning = "Higher quality wick touches at support";
            } else if(resistanceQuality > supportQuality * 1.2) {
                result.scores.touchQualityAnalysis.direction = "BEARISH";
                result.scores.touchQualityAnalysis.reasoning = "Higher quality wick touches at resistance";
            } else {
                result.scores.touchQualityAnalysis.direction = "NEUTRAL";
                result.scores.touchQualityAnalysis.reasoning = "Similar touch quality on both sides";
            }
        } else {
            result.scores.touchQualityAnalysis.direction = "NEUTRAL";
            result.scores.touchQualityAnalysis.reasoning = "Mixed or body touches, unclear direction";
        }
        
        // 5. REJECTION STRENGTH ANALYSIS
        result.scores.rejectionScore = CalculateRejectionStrength(symbol, timeframe, support, resistance);
        result.scores.rejectionAnalysis.strength = result.scores.rejectionScore;
        result.scores.rejectionAnalysis.confidence = 85; // Rejections are clear signals
        if(result.scores.rejectionScore > 60) {
            // Strong rejections - check which side is stronger
            double supportRejections = CountStrongRejections(symbol, timeframe, support, true);
            double resistanceRejections = CountStrongRejections(symbol, timeframe, resistance, false);
            
            if(supportRejections > resistanceRejections) {
                result.scores.rejectionAnalysis.direction = "BULLISH";
                result.scores.rejectionAnalysis.reasoning = "Stronger rejections at support suggest buying interest";
            } else if(resistanceRejections > supportRejections) {
                result.scores.rejectionAnalysis.direction = "BEARISH";
                result.scores.rejectionAnalysis.reasoning = "Stronger rejections at resistance suggest selling pressure";
            } else {
                result.scores.rejectionAnalysis.direction = "CONFLICTED";
                result.scores.rejectionAnalysis.reasoning = "Strong rejections on both sides, conflict";
            }
        } else {
            result.scores.rejectionAnalysis.direction = "NEUTRAL";
            result.scores.rejectionAnalysis.reasoning = "Weak or no clear rejection patterns";
        }
        
        // 6. FAILED BREAKOUT ANALYSIS
        int failedBreakouts = CountFailedBreakouts(symbol, timeframe, support, resistance);
        result.scores.failedBreakoutScore = MathMin(failedBreakouts * 10, 100);
        result.scores.failedBreakoutAnalysis.strength = result.scores.failedBreakoutScore;
        result.scores.failedBreakoutAnalysis.confidence = 90; // Failed breakouts are clear
        if(failedBreakouts > 0) {
            // Failed breakouts suggest trap - direction is opposite of failed breakout
            int failedUpBreakouts = CountFailedUpBreakouts(symbol, timeframe, resistance);
            int failedDownBreakouts = CountFailedDownBreakouts(symbol, timeframe, support);
            
            if(failedUpBreakouts > failedDownBreakouts) {
                result.scores.failedBreakoutAnalysis.direction = "BEARISH"; // Failed up = bearish
                result.scores.failedBreakoutAnalysis.reasoning = StringFormat("%d failed upside breakouts suggest traps", failedUpBreakouts);
            } else if(failedDownBreakouts > failedUpBreakouts) {
                result.scores.failedBreakoutAnalysis.direction = "BULLISH"; // Failed down = bullish
                result.scores.failedBreakoutAnalysis.reasoning = StringFormat("%d failed downside breakouts suggest traps", failedDownBreakouts);
            } else {
                result.scores.failedBreakoutAnalysis.direction = "CONFLICTED";
                result.scores.failedBreakoutAnalysis.reasoning = "Mixed failed breakouts on both sides";
            }
        } else {
            result.scores.failedBreakoutAnalysis.direction = "NEUTRAL";
            result.scores.failedBreakoutAnalysis.reasoning = "No failed breakouts detected";
        }
        
        // 7. LIQUIDITY ANALYSIS
        result.scores.liquidityScore = CalculateLiquidityScore(symbol, timeframe, support, resistance);
        result.scores.liquidityAnalysis.strength = result.scores.liquidityScore;
        result.scores.liquidityAnalysis.confidence = 60; // Proxy measurement
        if(result.scores.liquidityScore > 60) {
            // High liquidity suggests institutional activity
            double supportLiquidity = CalculateSupportLiquidity(symbol, timeframe, support);
            double resistanceLiquidity = CalculateResistanceLiquidity(symbol, timeframe, resistance);
            
            if(resistanceLiquidity > supportLiquidity * 1.3) {
                result.scores.liquidityAnalysis.direction = "BEARISH";
                result.scores.liquidityAnalysis.reasoning = "Higher liquidity/volume at resistance";
            } else if(supportLiquidity > resistanceLiquidity * 1.3) {
                result.scores.liquidityAnalysis.direction = "BULLISH";
                result.scores.liquidityAnalysis.reasoning = "Higher liquidity/volume at support";
            } else {
                result.scores.liquidityAnalysis.direction = "NEUTRAL";
                result.scores.liquidityAnalysis.reasoning = "Balanced liquidity on both sides";
            }
        } else {
            result.scores.liquidityAnalysis.direction = "NEUTRAL";
            result.scores.liquidityAnalysis.reasoning = "Low liquidity, unclear institutional activity";
        }
        
        // 8. HIGHER TIMEFRAME ALIGNMENT
        result.scores.higherTimeframeScore = CalculateHTFAlignment(symbol, timeframe, support, resistance);
        result.scores.higherTimeframeAnalysis.strength = result.scores.higherTimeframeScore;
        result.scores.higherTimeframeAnalysis.confidence = 70;
        // Direction depends on HTF trend if aligned
        string htfTrend = GetHTFTrend(symbol, timeframe);
        if(htfTrend == "BULLISH") {
            result.scores.higherTimeframeAnalysis.direction = "BULLISH";
            result.scores.higherTimeframeAnalysis.reasoning = "HTF trend is bullish";
        } else if(htfTrend == "BEARISH") {
            result.scores.higherTimeframeAnalysis.direction = "BEARISH";
            result.scores.higherTimeframeAnalysis.reasoning = "HTF trend is bearish";
        } else {
            result.scores.higherTimeframeAnalysis.direction = "NEUTRAL";
            result.scores.higherTimeframeAnalysis.reasoning = "HTF shows no clear trend";
        }
        
        // 9. ROUND NUMBER ANALYSIS
        result.scores.roundNumberScore = CalculateRoundNumberScore(support, resistance, currentPrice);
        result.scores.roundNumberAnalysis.strength = result.scores.roundNumberScore;
        result.scores.roundNumberAnalysis.confidence = 85; // Round numbers are clear
        bool supportRound = IsNearRoundNumber(support);
        bool resistanceRound = IsNearRoundNumber(resistance);
        bool priceRound = IsNearRoundNumber(currentPrice);
        
        if(priceRound && MathAbs(currentPrice - support) < MathAbs(currentPrice - resistance)) {
            result.scores.roundNumberAnalysis.direction = "BULLISH";
            result.scores.roundNumberAnalysis.reasoning = "Price at round number near support";
        } else if(priceRound && MathAbs(currentPrice - resistance) < MathAbs(currentPrice - support)) {
            result.scores.roundNumberAnalysis.direction = "BEARISH";
            result.scores.roundNumberAnalysis.reasoning = "Price at round number near resistance";
        } else if(supportRound && !resistanceRound) {
            result.scores.roundNumberAnalysis.direction = "BULLISH";
            result.scores.roundNumberAnalysis.reasoning = "Support at round number, resistance not";
        } else if(resistanceRound && !supportRound) {
            result.scores.roundNumberAnalysis.direction = "BEARISH";
            result.scores.roundNumberAnalysis.reasoning = "Resistance at round number, support not";
        } else {
            result.scores.roundNumberAnalysis.direction = "NEUTRAL";
            result.scores.roundNumberAnalysis.reasoning = "No clear round number bias";
        }
        
        // 10. SESSION ANALYSIS
        result.scores.sessionScore = CalculateSessionScore();
        result.scores.sessionAnalysis.strength = result.scores.sessionScore;
        result.scores.sessionAnalysis.confidence = 90; // Session times are certain
        MqlDateTime timeNow;
        TimeCurrent(timeNow);
        int hour = timeNow.hour;
        
        // London/NY overlap (13:00-17:00 GMT) is most volatile, often favors breakouts
        if(hour >= 13 && hour <= 17) {
            result.scores.sessionAnalysis.direction = "BEARISH"; // Overlap often sees selling in ranges
            result.scores.sessionAnalysis.reasoning = "London/NY overlap - high volatility favors traps";
        }
        // Asian session (22:00-08:00 GMT) is ranging, favors mean reversion
        else if(hour >= 22 || hour <= 8) {
            result.scores.sessionAnalysis.direction = "BULLISH"; // Asian often sees buying in ranges
            result.scores.sessionAnalysis.reasoning = "Asian session - ranging favors mean reversion";
        }
        else {
            result.scores.sessionAnalysis.direction = "NEUTRAL";
            result.scores.sessionAnalysis.reasoning = "Standard trading session";
        }
        
        // Update the components array
        result.scores.UpdateArray();
    }

    //+------------------------------------------------------------------+
    //| Calculate overall direction from components                      |
    //+------------------------------------------------------------------+
    void CalculateOverallDirection(RangeAnalysisResult &result)
    {
        if(!result.isValidRange) {
            result.overallDirection = "NEUTRAL";
            result.overallConfidence = 0;
            result.overallReasoning = "No valid range detected";
            return;
        }
        
        // Count directional votes (10 components total)
        int bullishVotes = 0;
        int bearishVotes = 0;
        int neutralVotes = 0;
        int conflictedVotes = 0;
        
        double totalBullishStrength = 0;
        double totalBearishStrength = 0;
        double totalConfidence = 0;
        
        // Analyze each component (9 in array + session)
        ComponentAnalysis allComponents[10];
        for(int i = 0; i < 9; i++) {
            allComponents[i] = result.scores.GetComponent(i);
        }
        allComponents[9] = result.scores.sessionAnalysis;
        
        for(int i = 0; i < 10; i++)
        {
            ComponentAnalysis comp = allComponents[i];
            
            if(comp.direction == "BULLISH") {
                bullishVotes++;
                totalBullishStrength += comp.strength * (comp.confidence / 100.0);
            }
            else if(comp.direction == "BEARISH") {
                bearishVotes++;
                totalBearishStrength += comp.strength * (comp.confidence / 100.0);
            }
            else if(comp.direction == "NEUTRAL") {
                neutralVotes++;
            }
            else if(comp.direction == "CONFLICTED") {
                conflictedVotes++;
            }
            
            totalConfidence += comp.confidence;
        }
        
        // Calculate weighted strengths
        double bullishWeighted = totalBullishStrength / 10.0;
        double bearishWeighted = totalBearishStrength / 10.0;
        double avgConfidence = totalConfidence / 10.0;
        
        // Determine overall direction
        if(bullishVotes == 0 && bearishVotes == 0) {
            result.overallDirection = "NEUTRAL";
            result.overallConfidence = MathMin(avgConfidence, 30); // Low confidence if all neutral
            result.overallReasoning = "All components neutral - no clear direction";
        }
        else if(bullishVotes > bearishVotes * 1.5) {
            result.overallDirection = "BULLISH";
            result.overallConfidence = MathMin(avgConfidence * (bullishWeighted / 100.0) * 100, 100);
            result.overallReasoning = StringFormat("%d bullish vs %d bearish components, weighted strength: %.1f%%",
                                                  bullishVotes, bearishVotes, bullishWeighted);
        }
        else if(bearishVotes > bullishVotes * 1.5) {
            result.overallDirection = "BEARISH";
            result.overallConfidence = MathMin(avgConfidence * (bearishWeighted / 100.0) * 100, 100);
            result.overallReasoning = StringFormat("%d bearish vs %d bullish components, weighted strength: %.1f%%",
                                                  bearishVotes, bullishVotes, bearishWeighted);
        }
        else if(bullishVotes > bearishVotes) {
            result.overallDirection = "BULLISH";
            result.overallConfidence = MathMin(avgConfidence * 0.7, 70); // Lower confidence for close call
            result.overallReasoning = StringFormat("Slight bullish edge: %d vs %d components",
                                                  bullishVotes, bearishVotes);
        }
        else if(bearishVotes > bullishVotes) {
            result.overallDirection = "BEARISH";
            result.overallConfidence = MathMin(avgConfidence * 0.7, 70);
            result.overallReasoning = StringFormat("Slight bearish edge: %d vs %d components",
                                                  bearishVotes, bullishVotes);
        }
        else if(conflictedVotes > 0) {
            result.overallDirection = "CONFLICTED";
            result.overallConfidence = MathMin(avgConfidence * 0.5, 50);
            result.overallReasoning = StringFormat("Mixed signals with %d conflicted components", conflictedVotes);
        }
        else {
            result.overallDirection = "NEUTRAL";
            result.overallConfidence = MathMin(avgConfidence * 0.6, 60);
            result.overallReasoning = "Balanced components with no clear majority";
        }
        
        // Adjust confidence based on trap probability
        if(result.trapProbability > 70) {
            // High trap probability reduces confidence in overall direction
            result.overallConfidence *= (1.0 - (result.trapProbability - 70) / 100.0);
            result.overallReasoning += " | High trap probability reduces confidence";
        }
    }

    //+------------------------------------------------------------------+
    //| Calculate enhanced trap probability                              |
    //+------------------------------------------------------------------+
    double CalculateEnhancedTrapProbability(string symbol, ENUM_TIMEFRAMES timeframe,
                                          double support, double resistance,
                                          int touchesSupport, int touchesResistance,
                                          double rangeWidthPercent, RangeAnalysisResult &result)
    {
        double totalScore = 0;
        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        // First calculate component analysis (directions and strengths)
        CalculateComponentAnalysis(symbol, timeframe, support, resistance,
                                 touchesSupport, touchesResistance,
                                 rangeWidthPercent, currentPrice, result);
        
        // Calculate trap probability from component strengths (weighted)
        totalScore += result.scores.tightnessScore * m_weights.tightnessWeight;
        totalScore += result.scores.symmetryScore * m_weights.symmetryWeight;
        totalScore += result.scores.consolidationTimeScore * m_weights.consolidationTimeWeight;
        totalScore += result.scores.touchQualityScore * m_weights.touchQualityWeight;
        totalScore += result.scores.rejectionScore * m_weights.rejectionWeight;
        totalScore += result.scores.failedBreakoutScore * m_weights.failedBreakoutWeight;
        totalScore += result.scores.liquidityScore * m_weights.liquidityWeight;
        totalScore += result.scores.higherTimeframeScore * m_weights.higherTimeframeWeight;
        totalScore += result.scores.roundNumberScore * m_weights.roundNumberWeight;
        totalScore += result.scores.sessionScore * m_weights.sessionWeight;
        
        // Create score breakdown string
        result.scoreBreakdown = result.scores.ToString();
        
        // Normalize to 0-100%
        result.trapProbability = MathMin(100, totalScore);
        result.isTrapZone = (result.trapProbability > 65);
        
        return result.trapProbability;
    }

    //+------------------------------------------------------------------+
    //| Calculate range-based directional bias                          |
    //+------------------------------------------------------------------+
    void CalculateRangeBias(RangeAnalysisResult &result, string symbol, 
                          ENUM_TIMEFRAMES timeframe, double currentPrice)
    {
        if(!result.isValidRange) {
            result.rangeBiasDirection = "NEUTRAL";
            result.rangeBiasConfidence = 0;
            result.rangeBiasReason = "No valid range detected";
            result.rangeAction = "NO_RANGE";
            return;
        }
        
        double atr = GetATR(symbol, timeframe, 14);
        double distanceToSupport = MathAbs(currentPrice - result.supportLevel);
        double distanceToResistance = MathAbs(currentPrice - result.resistanceLevel);
        
        // Determine proximity to edges
        bool nearSupport = distanceToSupport < (atr * 1.5);
        bool nearResistance = distanceToResistance < (atr * 1.5);
        bool inMiddleRange = !nearSupport && !nearResistance;
        
        // NEAR SUPPORT EDGE
        if(nearSupport && distanceToSupport < distanceToResistance) {
            result.rangeBiasDirection = "BULLISH";
            result.rangeBiasReason = StringFormat(
                "Price near support (%.5f) with %d touches - expecting bounce",
                result.supportLevel, result.supportTouches
            );
            
            // Calculate bias confidence
            result.rangeBiasConfidence = CalculateBiasConfidence(
                result.trapProbability,
                result.supportTouches,
                true,  // isSupport
                result.scores
            );
            
            result.rangeAction = "FADE_EDGE";
        }
        // NEAR RESISTANCE EDGE
        else if(nearResistance && distanceToResistance < distanceToSupport) {
            result.rangeBiasDirection = "BEARISH";
            result.rangeBiasReason = StringFormat(
                "Price near resistance (%.5f) with %d touches - expecting rejection",
                result.resistanceLevel, result.resistanceTouches
            );
            
            result.rangeBiasConfidence = CalculateBiasConfidence(
                result.trapProbability,
                result.resistanceTouches,
                false,  // isSupport
                result.scores
            );
            
            result.rangeAction = "FADE_EDGE";
        }
        // IN MIDDLE OF RANGE
        else if(inMiddleRange) {
            result.rangeBiasDirection = "NEUTRAL";
            result.rangeBiasReason = "Price in middle of range - no clear edge bias";
            result.rangeBiasConfidence = 0;
            result.rangeAction = "WAIT_IN_MIDDLE";
        }
        // EQUIDISTANT (rare case)
        else {
            result.rangeBiasDirection = "NEUTRAL";
            result.rangeBiasReason = "Equidistant from both range edges";
            result.rangeBiasConfidence = 0;
            result.rangeAction = "WAIT_IN_MIDDLE";
        }
        
        // High trap probability suggests caution
        if(result.trapProbability > 85) {
            result.rangeAction = "AVOID_HIGH_TRAP";
            result.rangeBiasReason += " | EXTREME TRAP PROBABILITY - HIGH CAUTION";
            result.rangeBiasConfidence *= 0.8;  // Reduce confidence for extreme traps
        }
        
        // Calculate execution scores
        result.entryQualityScore = CalculateEntryQualityScore(symbol, timeframe, currentPrice,
                                                            result.supportLevel, result.resistanceLevel,
                                                            result.rangeBiasDirection);
        
        result.riskRewardScore = CalculateRiskRewardScore(currentPrice, result.supportLevel,
                                                         result.resistanceLevel, atr,
                                                         result.rangeBiasDirection);
    }

    //+------------------------------------------------------------------+
    //| Main analysis function                                          |
    //+------------------------------------------------------------------+
    RangeAnalysisResult AnalyzeRange(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
    {
        RangeAnalysisResult result;
        
        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("RANGE_ANALYSIS_START",
                          StringFormat("Analyzing %s on %s", symbol, TimeframeToString(timeframe)));
        }
        
        // 1. Detect range
        double support, resistance;
        int touchCountResistance, touchCountSupport;
        double rangeWidthPercent;
        
        bool hasValidRange = DetectRange(symbol, timeframe, support, resistance,
                                        touchCountResistance, touchCountSupport,
                                        rangeWidthPercent);
        
        result.isValidRange = hasValidRange;
        
        if(!hasValidRange) {
            result.marketRegime = "TRENDING";
            result.rangeAction = "NO_RANGE";
            result.rangeBiasReason = "No valid range detected - market appears trending";
            result.overallDirection = "NEUTRAL";
            result.overallConfidence = 0;
            result.overallReasoning = "No range detected for analysis";
            return result;
        }
        
        // Set range properties
        result.supportLevel = support;
        result.resistanceLevel = resistance;
        result.supportTouches = touchCountSupport;
        result.resistanceTouches = touchCountResistance;
        result.totalTouches = touchCountSupport + touchCountResistance;
        result.rangeWidthPercent = rangeWidthPercent;
        
        // Determine market regime based on range width
        if(rangeWidthPercent < VERY_TIGHT_RANGE) {
            result.marketRegime = "TIGHT_RANGE";
        } else {
            result.marketRegime = "RANGING";
        }
        
        // 2. Calculate trap probability and component analysis
        CalculateEnhancedTrapProbability(symbol, timeframe, support, resistance,
                                       touchCountSupport, touchCountResistance,
                                       rangeWidthPercent, result);
        
        // 3. Calculate overall direction from components
        CalculateOverallDirection(result);
        
        // 4. Calculate range bias and execution scores
        double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        CalculateRangeBias(result, symbol, timeframe, currentPrice);
        
        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("RANGE_ANALYSIS_COMPLETE", result.ToString());
        }
        
        return result;
    }

    //+------------------------------------------------------------------+
    //| COMPONENT CALCULATION FUNCTIONS                                 |
    //+------------------------------------------------------------------+
    
    // Tightness score (0-100%)
    double CalculateTightnessScore(double rangeWidthPercent)
    {
        if(rangeWidthPercent < VERY_TIGHT_RANGE)
            return 100;
        else if(rangeWidthPercent < TIGHT_RANGE_THRESHOLD)
            return 80;
        else if(rangeWidthPercent < 2.5)
            return 50;
        else if(rangeWidthPercent < 4.0)
            return 20;
        else
            return 0;
    }
    
    // Symmetry score (0-100%)
    double CalculateSymmetryScore(int touchesSupport, int touchesResistance)
    {
        if(touchesSupport == 0 || touchesResistance == 0)
            return 0;
            
        double ratio = (double)MathMin(touchesSupport, touchesResistance) / 
                      (double)MathMax(touchesSupport, touchesResistance);
        return ratio * 100;
    }
    
    // Consolidation time score (0-100%)
    double CalculateConsolidationTime(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        // Simple implementation: more candles in lookback = higher score
        int candles = TRAP_LOOKBACK_CANDLES;
        return MathMin((candles / 20.0) * 100, 100);  // 20 candles = 100%
    }
    
    // Touch quality score (0-100%)
    double CalculateTouchQuality(string symbol, ENUM_TIMEFRAMES timeframe,
                               double support, double resistance)
    {
        // Simplified: count wick touches vs body touches
        int wickTouches = 0;
        int totalTouches = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double open = iOpen(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);
            
            // Check support touches
            if(MathAbs(low - support) < tolerance) {
                totalTouches++;
                // If candle closed above support, it's a wick touch
                if(close > support && open > support)
                    wickTouches++;
            }
            
            // Check resistance touches
            if(MathAbs(high - resistance) < tolerance) {
                totalTouches++;
                // If candle closed below resistance, it's a wick touch
                if(close < resistance && open < resistance)
                    wickTouches++;
            }
        }
        
        if(totalTouches == 0) return 0;
        return (double)wickTouches / totalTouches * 100;
    }
    
    // Support touch quality
    double CalculateSupportTouchQuality(string symbol, ENUM_TIMEFRAMES timeframe, double support)
    {
        int wickTouches = 0;
        int totalTouches = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double low = iLow(symbol, timeframe, i);
            double open = iOpen(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);
            
            if(MathAbs(low - support) < tolerance) {
                totalTouches++;
                if(close > support && open > support)
                    wickTouches++;
            }
        }
        
        if(totalTouches == 0) return 0;
        return (double)wickTouches / totalTouches * 100;
    }
    
    // Resistance touch quality
    double CalculateResistanceTouchQuality(string symbol, ENUM_TIMEFRAMES timeframe, double resistance)
    {
        int wickTouches = 0;
        int totalTouches = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double open = iOpen(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);
            
            if(MathAbs(high - resistance) < tolerance) {
                totalTouches++;
                if(close < resistance && open < resistance)
                    wickTouches++;
            }
        }
        
        if(totalTouches == 0) return 0;
        return (double)wickTouches / totalTouches * 100;
    }
    
    // Rejection strength score (0-100%)
    double CalculateRejectionStrength(string symbol, ENUM_TIMEFRAMES timeframe,
                                    double support, double resistance)
    {
        int strongRejections = 0;
        int totalTouches = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double range = high - low;
            double atr = GetATR(symbol, timeframe, 14);
            
            // Check support rejections
            if(MathAbs(low - support) < tolerance) {
                totalTouches++;
                // Strong rejection if candle has long lower wick
                double bodyBottom = MathMin(iOpen(symbol, timeframe, i), iClose(symbol, timeframe, i));
                double lowerWick = bodyBottom - low;
                if(lowerWick > range * 0.3 && lowerWick > atr * 0.5)
                    strongRejections++;
            }
            
            // Check resistance rejections
            if(MathAbs(high - resistance) < tolerance) {
                totalTouches++;
                // Strong rejection if candle has long upper wick
                double bodyTop = MathMax(iOpen(symbol, timeframe, i), iClose(symbol, timeframe, i));
                double upperWick = high - bodyTop;
                if(upperWick > range * 0.3 && upperWick > atr * 0.5)
                    strongRejections++;
            }
        }
        
        if(totalTouches == 0) return 0;
        return (double)strongRejections / totalTouches * 100;
    }
    
    // Count strong rejections at level
    int CountStrongRejections(string symbol, ENUM_TIMEFRAMES timeframe, double level, bool isSupport)
    {
        int strongRejections = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double range = high - low;
            double atr = GetATR(symbol, timeframe, 14);
            
            if(isSupport && MathAbs(low - level) < tolerance) {
                double bodyBottom = MathMin(iOpen(symbol, timeframe, i), iClose(symbol, timeframe, i));
                double lowerWick = bodyBottom - low;
                if(lowerWick > range * 0.3 && lowerWick > atr * 0.5)
                    strongRejections++;
            }
            else if(!isSupport && MathAbs(high - level) < tolerance) {
                double bodyTop = MathMax(iOpen(symbol, timeframe, i), iClose(symbol, timeframe, i));
                double upperWick = high - bodyTop;
                if(upperWick > range * 0.3 && upperWick > atr * 0.5)
                    strongRejections++;
            }
        }
        
        return strongRejections;
    }
    
    // Count failed breakouts
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
            {
                if (close < resistance)
                {
                    failedCount++;
                }
            }

            // Check for breakout below support that failed
            if (low < support * 0.999)
            {
                if (close > support)
                {
                    failedCount++;
                }
            }
        }

        if (DEBUG_TRAP_ENABLED)
        {
            DebugTrapLogs("FAILED_BREAKOUTS",
                          StringFormat("%s: %d failed breakouts", symbol, failedCount));
        }

        return failedCount;
    }
    
    // Count failed up breakouts
    int CountFailedUpBreakouts(string symbol, ENUM_TIMEFRAMES timeframe, double resistance)
    {
        int failedCount = 0;
        int lookback = MathMin(100, TRAP_LOOKBACK_CANDLES * 3);

        for (int i = 1; i < lookback; i++)
        {
            double high = iHigh(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);

            if (high > resistance * 1.001 && close < resistance)
            {
                failedCount++;
            }
        }

        return failedCount;
    }
    
    // Count failed down breakouts
    int CountFailedDownBreakouts(string symbol, ENUM_TIMEFRAMES timeframe, double support)
    {
        int failedCount = 0;
        int lookback = MathMin(100, TRAP_LOOKBACK_CANDLES * 3);

        for (int i = 1; i < lookback; i++)
        {
            double low = iLow(symbol, timeframe, i);
            double close = iClose(symbol, timeframe, i);

            if (low < support * 0.999 && close > support)
            {
                failedCount++;
            }
        }

        return failedCount;
    }
    
    // Liquidity score (0-100%) - proxy using candle ranges
    double CalculateLiquidityScore(string symbol, ENUM_TIMEFRAMES timeframe,
                                 double support, double resistance)
    {
        double totalRangeAtTouches = 0;
        int touchCount = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double range = high - low;
            
            if(MathAbs(low - support) < tolerance || MathAbs(high - resistance) < tolerance) {
                totalRangeAtTouches += range;
                touchCount++;
            }
        }
        
        if(touchCount == 0) return 0;
        
        double avgRangeAtTouch = totalRangeAtTouches / touchCount;
        double avgATR = GetATR(symbol, timeframe, 14);
        
        // Score based on range size relative to ATR
        if(avgRangeAtTouch > avgATR * 1.5) return 80;
        else if(avgRangeAtTouch > avgATR) return 60;
        else if(avgRangeAtTouch > avgATR * 0.7) return 40;
        else return 20;
    }
    
    // Support liquidity
    double CalculateSupportLiquidity(string symbol, ENUM_TIMEFRAMES timeframe, double support)
    {
        double totalRange = 0;
        int touchCount = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double range = high - low;
            
            if(MathAbs(low - support) < tolerance) {
                totalRange += range;
                touchCount++;
            }
        }
        
        if(touchCount == 0) return 0;
        return totalRange / touchCount;
    }
    
    // Resistance liquidity
    double CalculateResistanceLiquidity(string symbol, ENUM_TIMEFRAMES timeframe, double resistance)
    {
        double totalRange = 0;
        int touchCount = 0;
        int lookback = TRAP_LOOKBACK_CANDLES;
        double tolerance = GetATR(symbol, timeframe, 14) * 0.5;
        
        for(int i = 0; i < lookback; i++) {
            double high = iHigh(symbol, timeframe, i);
            double low = iLow(symbol, timeframe, i);
            double range = high - low;
            
            if(MathAbs(high - resistance) < tolerance) {
                totalRange += range;
                touchCount++;
            }
        }
        
        if(touchCount == 0) return 0;
        return totalRange / touchCount;
    }
    
    // Get HTF trend
    string GetHTFTrend(string symbol, ENUM_TIMEFRAMES currentTF)
    {
        ENUM_TIMEFRAMES higherTF = GetHigherTimeframe(currentTF);
        if(higherTF == currentTF) return "NEUTRAL";
        
        // Simple trend detection using MA crossover
        int maFastHandle = iMA(symbol, higherTF, 20, 0, MODE_SMA, PRICE_CLOSE);
        int maSlowHandle = iMA(symbol, higherTF, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        if(maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE)
            return "NEUTRAL";
            
        double maFast[], maSlow[];
        if(CopyBuffer(maFastHandle, 0, 0, 1, maFast) > 0 && 
           CopyBuffer(maSlowHandle, 0, 0, 1, maSlow) > 0)
        {
            if(maFast[0] > maSlow[0])
                return "BULLISH";
            else if(maFast[0] < maSlow[0])
                return "BEARISH";
        }
        
        return "NEUTRAL";
    }
    
    // Higher timeframe alignment score (0-100%)
    double CalculateHTFAlignment(string symbol, ENUM_TIMEFRAMES currentTF,
                               double support, double resistance)
    {
        ENUM_TIMEFRAMES higherTF = GetHigherTimeframe(currentTF);
        if(higherTF == currentTF) return 50;  // No higher TF available
        
        // Check if range aligns with HTF levels
        // For now, return neutral score (can be enhanced with actual HTF S/R detection)
        return 50;
    }
    
    // Round number score (0-100%)
    double CalculateRoundNumberScore(double support, double resistance, double currentPrice)
    {
        int roundNumberCount = 0;
        
        if(IsNearRoundNumber(support)) roundNumberCount++;
        if(IsNearRoundNumber(resistance)) roundNumberCount++;
        if(IsNearRoundNumber(currentPrice)) roundNumberCount++;
        
        return (roundNumberCount / 3.0) * 100;
    }
    
    // Session overlap score (0-100%)
    double CalculateSessionScore()
    {
        // Simplified: check if current time is in London/NY overlap
        MqlDateTime timeNow;
        TimeCurrent(timeNow);
        int hour = timeNow.hour;
        
        // London/NY overlap: 13:00-17:00 GMT
        if(hour >= 13 && hour <= 17) {
            return 80;
        }
        // London session: 08:00-17:00 GMT
        else if(hour >= 8 && hour <= 17) {
            return 60;
        }
        // NY session: 13:00-22:00 GMT
        else if(hour >= 13 && hour <= 22) {
            return 70;
        }
        // Asian session
        else if(hour >= 22 || hour <= 8) {
            return 30;
        }
        
        return 50;
    }
    
    // Bias confidence calculation (0-100%)
    double CalculateBiasConfidence(double trapProbability, int touches,
                                 bool isSupport, const RangeAnalysisResult::ComponentScores &scores)
    {
        // Base confidence from trap probability
        double confidence = trapProbability * 0.6;  // 60% of trap prob
        
        // Touch count boost
        confidence += MathMin(touches * 4, 20);  // Max +20% for touches
        
        // Component boosts
        confidence += scores.rejectionScore * 0.15;
        confidence += scores.touchQualityScore * 0.10;
        confidence += scores.symmetryScore * 0.05;
        
        // Round number boost
        confidence += scores.roundNumberScore * 0.10;
        
        // Session boost
        confidence += (scores.sessionScore - 50) * 0.2;  // Positive if >50
        
        return MathMin(confidence, 100);
    }
    
    // Entry quality score (0-100%)
    double CalculateEntryQualityScore(string symbol, ENUM_TIMEFRAMES timeframe,
                                    double currentPrice, double support, double resistance,
                                    string biasDirection)
    {
        double atr = GetATR(symbol, timeframe, 14);
        double distanceToSupport = MathAbs(currentPrice - support);
        double distanceToResistance = MathAbs(currentPrice - resistance);
        
        // Proximity score (closer to edge = better)
        double proximityScore = 0;
        if(biasDirection == "BULLISH") {
            proximityScore = 100 * (1 - distanceToSupport / (atr * 2));
        } else if(biasDirection == "BEARISH") {
            proximityScore = 100 * (1 - distanceToResistance / (atr * 2));
        } else {
            proximityScore = 0;
        }
        
        // Momentum score (divergence at edge)
        double momentumScore = CalculateMomentumDivergence(symbol, timeframe, biasDirection);
        
        // Candle pattern score
        double patternScore = CalculateReversalCandleScore(symbol, timeframe, biasDirection);
        
        // Weighted combination
        return (proximityScore * 0.5 + momentumScore * 0.3 + patternScore * 0.2);
    }
    
    // Risk-reward score (0-100%)
    double CalculateRiskRewardScore(double currentPrice, double support, double resistance,
                                  double atr, string biasDirection)
    {
        if(biasDirection == "NEUTRAL") return 0;
        
        double potentialGain = 0;
        double potentialLoss = atr * 2;  // 2 ATR stop loss
        
        if(biasDirection == "BULLISH") {
            potentialGain = resistance - currentPrice;
        } else if(biasDirection == "BEARISH") {
            potentialGain = currentPrice - support;
        }
        
        if(potentialGain <= 0) return 0;
        
        double rawRR = potentialGain / potentialLoss;
        
        // Scale to 0-100% (RR of 3 = 100%)
        double score = MathMin(100, rawRR * 33.33);
        
        // Adjust for range width (wider ranges have better RR)
        double rangeWidth = resistance - support;
        if(rangeWidth > atr * 10) score *= 1.2;
        else if(rangeWidth > atr * 5) score *= 1.1;
        
        return MathMin(score, 100);
    }

    //+------------------------------------------------------------------+
    //| UTILITY FUNCTIONS                                                |
    //+------------------------------------------------------------------+
    
    // Count touches
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
    
    // Check if near round number
    bool IsNearRoundNumber(double price)
    {
        double base = MathFloor(price);
        double fractional = price - base;
        
        if (MathAbs(fractional) < 0.0001 ||
            MathAbs(fractional - 0.25) < 0.0001 ||
            MathAbs(fractional - 0.50) < 0.0001 ||
            MathAbs(fractional - 0.75) < 0.0001)
        {
            return true;
        }

        if (MathMod(base, 100) == 0 || MathMod(base, 50) == 0 || MathMod(base, 20) == 0)
        {
            return true;
        }

        return false;
    }
    
    // Get higher timeframe
    ENUM_TIMEFRAMES GetHigherTimeframe(ENUM_TIMEFRAMES tf)
    {
        switch(tf)
        {
            case PERIOD_M1: return PERIOD_M5;
            case PERIOD_M5: return PERIOD_M15;
            case PERIOD_M15: return PERIOD_M30;
            case PERIOD_M30: return PERIOD_H1;
            case PERIOD_H1: return PERIOD_H4;
            case PERIOD_H4: return PERIOD_D1;
            case PERIOD_D1: return PERIOD_W1;
            case PERIOD_W1: return PERIOD_MN1;
            default: return tf;
        }
    }
    
    // Calculate momentum divergence
    double CalculateMomentumDivergence(string symbol, ENUM_TIMEFRAMES timeframe, string biasDirection)
    {
        // Use the IndicatorManager's RSI if available
        if (m_indicatorManager != NULL)
        {
            // FIXED: Use 'tf' instead of 'timeframe'
            double rsi = m_indicatorManager.GetRSI(timeframe);
            
            if(biasDirection == "BULLISH" && rsi < 30) {
                return 80; // Bullish divergence
            } else if(biasDirection == "BEARISH" && rsi > 70) {
                return 80; // Bearish divergence
            }
            
            return 50;  // Neutral
        }
        
        // Fallback to original calculation
        int rsiHandle = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE) return 50;
        
        double rsi[];
        if(CopyBuffer(rsiHandle, 0, 0, 5, rsi) < 5) return 50;
        
        // Check for oversold/overbought conditions
        if(biasDirection == "BULLISH" && rsi[0] < 30 && rsi[0] > rsi[4]) {
            return 80; // Bullish divergence
        } else if(biasDirection == "BEARISH" && rsi[0] > 70 && rsi[0] < rsi[4]) {
            return 80; // Bearish divergence
        }
        
        return 50;  // Neutral
    }
    
    // Calculate reversal candle score
    double CalculateReversalCandleScore(string symbol, ENUM_TIMEFRAMES timeframe, string biasDirection)
    {
        // Check last 3 candles for reversal patterns
        int reversalPatterns = 0;
        
        if(biasDirection == "BULLISH") {
            // Look for hammer, bullish engulfing, etc.
            for(int i = 0; i < 3; i++) {
                double open = iOpen(symbol, timeframe, i);
                double close = iClose(symbol, timeframe, i);
                double high = iHigh(symbol, timeframe, i);
                double low = iLow(symbol, timeframe, i);
                double range = high - low;
                
                // Hammer pattern
                if(close > open && (close - low) > range * 0.6 && (high - close) < range * 0.1) {
                    reversalPatterns++;
                }
                // Bullish engulfing
                if(i > 0 && close > open && close > iOpen(symbol, timeframe, i-1) && 
                   open < iClose(symbol, timeframe, i-1) && close - open > range * 0.7) {
                    reversalPatterns++;
                }
            }
        }
        else if(biasDirection == "BEARISH") {
            // Look for shooting star, bearish engulfing, etc.
            for(int i = 0; i < 3; i++) {
                double open = iOpen(symbol, timeframe, i);
                double close = iClose(symbol, timeframe, i);
                double high = iHigh(symbol, timeframe, i);
                double low = iLow(symbol, timeframe, i);
                double range = high - low;
                
                // Shooting star pattern
                if(close < open && (high - open) > range * 0.6 && (open - low) < range * 0.1) {
                    reversalPatterns++;
                }
                // Bearish engulfing
                if(i > 0 && close < open && close < iOpen(symbol, timeframe, i-1) && 
                   open > iClose(symbol, timeframe, i-1) && open - close > range * 0.7) {
                    reversalPatterns++;
                }
            }
        }
        
        return MathMin(reversalPatterns * 33.33, 100);
    }
    
    string TimeframeToString(ENUM_TIMEFRAMES tf)
    {
        switch (tf)
        {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "UNKNOWN";
        }
    }

    //+------------------------------------------------------------------+
    //| NEW: Get specific component analysis                            |
    //+------------------------------------------------------------------+
    ComponentAnalysis GetComponentAnalysis(string symbol, ENUM_TIMEFRAMES timeframe, string componentName)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, timeframe);
        return result.GetComponentAnalysis(componentName);
    }
    
    //+------------------------------------------------------------------+
    //| NEW: Get all components as array                                |
    //+------------------------------------------------------------------+
    ComponentAnalysis GetAllComponents(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, timeframe);
        ComponentAnalysis summary;
        summary.name = "ALL_COMPONENTS_SUMMARY";
        
        // Create weighted summary from 10 components
        int totalComponents = 10;
        double bullishScore = 0;
        double bearishScore = 0;
        double neutralScore = 0;
        double totalStrength = 0;
        
        // Get array of all components
        ComponentAnalysis allComponents[10];
        for(int i = 0; i < 9; i++) {
            allComponents[i] = result.scores.GetComponent(i);
        }
        allComponents[9] = result.scores.sessionAnalysis;
        
        for(int i = 0; i < totalComponents; i++)
        {
            ComponentAnalysis comp = allComponents[i];
            double weight = 1.0 / totalComponents;
            
            if(comp.direction == "BULLISH") {
                bullishScore += comp.strength * weight * (comp.confidence / 100.0);
            }
            else if(comp.direction == "BEARISH") {
                bearishScore += comp.strength * weight * (comp.confidence / 100.0);
            }
            else {
                neutralScore += weight;
            }
            
            totalStrength += comp.strength * weight;
        }
        
        double totalWeighted = bullishScore + bearishScore + neutralScore;
        
        if(bullishScore > bearishScore && bullishScore > 0.3)
        {
            summary.direction = "BULLISH";
            summary.strength = (bullishScore / totalWeighted) * 100;
            summary.confidence = (bullishScore / totalWeighted) * 100;
        }
        else if(bearishScore > bullishScore && bearishScore > 0.3)
        {
            summary.direction = "BEARISH";
            summary.strength = (bearishScore / totalWeighted) * 100;
            summary.confidence = (bearishScore / totalWeighted) * 100;
        }
        else
        {
            summary.direction = "NEUTRAL";
            summary.strength = (neutralScore / totalWeighted) * 100;
            summary.confidence = 50;
        }
        
        summary.reasoning = StringFormat("Weighted component analysis: Bullish=%.1f%%, Bearish=%.1f%%, Neutral=%.1f%%",
                                        (bullishScore / totalWeighted) * 100, 
                                        (bearishScore / totalWeighted) * 100, 
                                        (neutralScore / totalWeighted) * 100);
        
        return summary;
    }

    //+------------------------------------------------------------------+
    //| Quick Access Functions                                          |
    //+------------------------------------------------------------------+
    
    bool IsInRange(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.isValidRange;
    }
    
    bool IsNearRangeEdge(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.isValidRange && 
               (result.rangeAction == "FADE_EDGE");
    }
    
    string GetRangeBias(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.rangeBiasDirection;
    }
    
    double GetRangeBiasConfidence(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.rangeBiasConfidence;
    }
    
    string GetOverallDirection(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.overallDirection;
    }
    
    double GetOverallConfidence(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.overallConfidence;
    }
    
    double GetTrapRiskMultiplier(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        if(!result.isValidRange) return 1.0;
        
        // Higher trap probability = smaller position size
        if(result.trapProbability > 85) return 0.5;
        else if(result.trapProbability > 70) return 0.7;
        else if(result.trapProbability > 50) return 0.8;
        else return 1.0;
    }
    
    double GetEntryQualityScore(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        RangeAnalysisResult result = AnalyzeRange(symbol, tf);
        return result.entryQualityScore;
    }
}

//+------------------------------------------------------------------+
//| Initialization function                                         |
//+------------------------------------------------------------------+
void InitializeRangePackage(bool enableDebug = true)
{
    DEBUG_TRAP_ENABLED = enableDebug;
    
    // Normalize weights
    RangeIntelligence::m_weights.Normalize();
    
    if (DEBUG_TRAP_ENABLED)
    {
        DebugTrapLogs("RANGE_PACKAGE_INIT", 
                     "Enhanced Range Package with component analysis initialized");
    }
}
//+------------------------------------------------------------------+