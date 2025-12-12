//+------------------------------------------------------------------+
//| Enhanced MA Relationship Analyzer                               |
//| Comprehensive multi-MA analysis on single timeframe             |
//+------------------------------------------------------------------+

#include "../../config/structures.mqh"

// Input parameters for the analyzer
input group "=== Enhanced MA Relationship Settings ==="
input ENUM_TIMEFRAMES MA_Analysis_Timeframe = PERIOD_M15;  // DECREASE (shorter timeframe) for faster signals, INCREASE (longer timeframe) for more reliable signals
input int VeryFastMA_Period_Enhanced = 5;                   // DECREASE for faster response, INCREASE for smoother MA
input int FastMA_Period_Enhanced = 9;                       // DECREASE for faster response, INCREASE for smoother MA
input int MediumMA_Period_Enhanced = 21;                    // DECREASE for more sensitive medium trend, INCREASE for more stable medium trend
input int SlowMA_Period_Enhanced = 89;                      // DECREASE for more responsive long trend, INCREASE for more stable long trend

// Gap thresholds (in pips)
input double Gap_5_9_Min = 5.0;         // DECREASE to allow MAs to be closer together before signaling weakness
input double Gap_5_9_Max = 5.0;         // INCREASE to allow MAs to spread further apart before signaling over-extension
input double Gap_9_21_Min = 20.0;        // DECREASE to allow MAs to be closer together before signaling weakness
input double Gap_9_21_Max = 20.0;       // INCREASE to allow MAs to spread further apart before signaling over-extension
input double Gap_21_89_Min = 200.0;       // DECREASE to allow MAs to be closer together before signaling weakness
input double Gap_21_89_Max = 400.0;      // INCREASE to allow MAs to spread further apart before signaling over-extension

// Buffer zones (pips) - to avoid whipsaws
input double Buffer_5_9 = 20.0;          // INCREASE to reduce false signals but miss earlier entries
input double Buffer_9_21 = 20.0;         // INCREASE to reduce false signals but miss earlier entries
input double Buffer_21_89 = 20.0;        // INCREASE to reduce false signals but miss earlier entries

// Score weights - UPDATED TO YOUR PREFERENCES
input double Weight_5_9 = 0.15;         // 15% weight (YOU WANTED THIS)
input double Weight_9_21 = 0.60;        // 60% weight (YOU WANTED THIS)
input double Weight_21_89 = 0.25;       // 25% weight (YOU WANTED THIS)

// Warning thresholds
input double Critical_Cross_Score = 20.0;  // DECREASE to trigger critical warnings earlier (more sensitive)
input double Severe_Cross_Score = 15.0;    // DECREASE to trigger severe warnings earlier (more sensitive)

// Keep old structure for backward compatibility
struct MARelationshipScore
{
    double score_5_9;          // 5-9 relationship score (0-100)
    double score_9_21;         // 9-21 relationship score (0-100)
    double score_21_89;        // 21-89 relationship score (0-100)
    double totalScore;         // Weighted total score (0-100)
    string warning;           // Warning message if any
    string tradeAdvice;       // Trade advice based on analysis
    bool isCritical;          // True if critical condition detected
};

//+------------------------------------------------------------------+
//| NEW: Calculate MA Alignment (Direction-Neutral)                 |
//| Returns both buy and sell confidence scores                     |
//+------------------------------------------------------------------+
MAAlignmentScore CalculateMAAlignment(const string symbol)
{
    MAAlignmentScore result;
    result.buyConfidence = 50.0;     // Start neutral
    result.sellConfidence = 50.0;    // Start neutral
    result.netBias = 0.0;
    result.alignment = "NEUTRAL";
    result.warning = "";
    result.isCritical = false;
    
    // Get MA handles
    int hVeryFast = iMA(symbol, MA_Analysis_Timeframe, VeryFastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hFast = iMA(symbol, MA_Analysis_Timeframe, FastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hMedium = iMA(symbol, MA_Analysis_Timeframe, MediumMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hSlow = iMA(symbol, MA_Analysis_Timeframe, SlowMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    
    // Get current values
    double vfCurrent[1], fCurrent[1], mCurrent[1], sCurrent[1];
    
    bool dataOk = true;
    dataOk = dataOk && (CopyBuffer(hVeryFast, 0, 0, 1, vfCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hFast, 0, 0, 1, fCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hMedium, 0, 0, 1, mCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hSlow, 0, 0, 1, sCurrent) >= 1);
    
    if(!dataOk)
    {
        result.warning = "Failed to get MA data";
        IndicatorRelease(hVeryFast);
        IndicatorRelease(hFast);
        IndicatorRelease(hMedium);
        IndicatorRelease(hSlow);
        return result;
    }
    
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // ============================================
    // 1. CALCULATE GAPS (SIGNED - Positive = Bullish)
    // ============================================
    double gap_5_9 = (vfCurrent[0] - fCurrent[0]) / point;   // Positive if 5 > 9 (bullish)
    double gap_9_21 = (fCurrent[0] - mCurrent[0]) / point;    // Positive if 9 > 21 (bullish)
    double gap_21_89 = (mCurrent[0] - sCurrent[0]) / point;   // Positive if 21 > 89 (bullish)
    
    // ============================================
    // 2. CALCULATE BUY CONFIDENCE (Bullish Alignment)
    // ============================================
    double buyScore = 50.0; // Start neutral
    
    // Bullish gap contributions (15%, 60%, 25% weights)
    if(gap_5_9 > 0) {
        double gapStrength_5_9 = MathMin(gap_5_9 / Gap_5_9_Max, 2.0); // Normalize
        buyScore += (gapStrength_5_9 * 30.0 * Weight_5_9); // 15% weight
    }
    
    if(gap_9_21 > 0) {
        double gapStrength_9_21 = MathMin(gap_9_21 / Gap_9_21_Max, 2.0); // Normalize
        buyScore += (gapStrength_9_21 * 50.0 * Weight_9_21); // 60% weight
    }
    
    if(gap_21_89 > 0) {
        double gapStrength_21_89 = MathMin(gap_21_89 / Gap_21_89_Max, 2.0); // Normalize
        buyScore += (gapStrength_21_89 * 40.0 * Weight_21_89); // 25% weight
    }
    
    // Perfect bullish alignment bonus (5 > 9 > 21 > 89)
    if(gap_5_9 > 0 && gap_9_21 > 0 && gap_21_89 > 0) {
        buyScore += 20.0;
    }
    
    // ============================================
    // 3. CALCULATE SELL CONFIDENCE (Bearish Alignment)
    // ============================================
    double sellScore = 50.0; // Start neutral
    
    // Bearish gap contributions (15%, 60%, 25% weights)
    if(gap_5_9 < 0) {
        double gapStrength_5_9 = MathMin(MathAbs(gap_5_9) / Gap_5_9_Max, 2.0); // Normalize
        sellScore += (gapStrength_5_9 * 30.0 * Weight_5_9); // 15% weight
    }
    
    if(gap_9_21 < 0) {
        double gapStrength_9_21 = MathMin(MathAbs(gap_9_21) / Gap_9_21_Max, 2.0); // Normalize
        sellScore += (gapStrength_9_21 * 50.0 * Weight_9_21); // 60% weight
    }
    
    if(gap_21_89 < 0) {
        double gapStrength_21_89 = MathMin(MathAbs(gap_21_89) / Gap_21_89_Max, 2.0); // Normalize
        sellScore += (gapStrength_21_89 * 40.0 * Weight_21_89); // 25% weight
    }
    
    // Perfect bearish alignment bonus (5 < 9 < 21 < 89)
    if(gap_5_9 < 0 && gap_9_21 < 0 && gap_21_89 < 0) {
        sellScore += 20.0;
    }
    
    // ============================================
    // 4. CHECK FOR CROSSINGS/WARNINGS (Critical Conditions)
    // ============================================
    
    // Check if MAs are too close (in buffer zone)
    if(MathAbs(gap_5_9) < Buffer_5_9) {
        result.warning += (result.warning == "" ? "" : " | ") + "5-9 in buffer zone";
        result.isCritical = true;
    }
    
    if(MathAbs(gap_9_21) < Buffer_9_21) {
        result.warning += (result.warning == "" ? "" : " | ") + "9-21 in buffer zone - HIGH ALERT";
        result.isCritical = true;
        buyScore *= 0.7;  // Reduce confidence
        sellScore *= 0.7; // Reduce confidence
    }
    
    if(MathAbs(gap_21_89) < Buffer_21_89) {
        result.warning += (result.warning == "" ? "" : " | ") + "21-89 in buffer zone - TREND WEAK";
        buyScore *= 0.8;
        sellScore *= 0.8;
    }
    
    // Check for recent crossings (need previous values)
    double vfPrevious[1], fPrevious[1], mPrevious[1], sPrevious[1];
    CopyBuffer(hVeryFast, 0, 1, 1, vfPrevious);
    CopyBuffer(hFast, 0, 1, 1, fPrevious);
    CopyBuffer(hMedium, 0, 1, 1, mPrevious);
    CopyBuffer(hSlow, 0, 1, 1, sPrevious);
    
    // Check 9-21 crossing (most critical)
    bool was9Above21 = (fPrevious[0] > mPrevious[0]);
    bool is9Above21 = (fCurrent[0] > mCurrent[0]);
    if(was9Above21 != is9Above21) {
        result.warning += (result.warning == "" ? "" : " | ") + "9-21 CROSSING DETECTED - DROP TRADES";
        result.isCritical = true;
        buyScore = MathMin(buyScore, 30.0);
        sellScore = MathMin(sellScore, 30.0);
    }
    
    // ============================================
    // 5. FINALIZE SCORES
    // ============================================
    result.buyConfidence = MathMax(0, MathMin(100, buyScore));
    result.sellConfidence = MathMax(0, MathMin(100, sellScore));
    result.netBias = result.buyConfidence - result.sellConfidence;
    
    // Determine alignment
    if(result.netBias > 25) result.alignment = "STRONGLY_BULLISH";
    else if(result.netBias > 10) result.alignment = "BULLISH";
    else if(result.netBias < -25) result.alignment = "STRONGLY_BEARISH";
    else if(result.netBias < -10) result.alignment = "BEARISH";
    else result.alignment = "NEUTRAL";
    
    // Clean up
    IndicatorRelease(hVeryFast);
    IndicatorRelease(hFast);
    IndicatorRelease(hMedium);
    IndicatorRelease(hSlow);
    
    return result;
}

//+------------------------------------------------------------------+
//| BACKWARD COMPATIBILITY: Original function (deprecated)          |
//+------------------------------------------------------------------+
MARelationshipScore CalculateMARelationshipScore(const string symbol, const bool isBuyTrade)
{
    MARelationshipScore result;
    
    // Use new alignment system but convert to old format
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    // Convert alignment to the old score format
    result.score_5_9 = 50.0;  // Default
    result.score_9_21 = 50.0; // Default
    result.score_21_89 = 50.0; // Default
    
    // For backward compatibility, use buyConfidence for buy trades, sellConfidence for sell trades
    if(isBuyTrade) {
        result.totalScore = alignment.buyConfidence;
    } else {
        result.totalScore = alignment.sellConfidence;
    }
    
    result.warning = alignment.warning;
    result.isCritical = alignment.isCritical;
    
    // Generate simple advice based on alignment
    if(alignment.isCritical) {
        result.tradeAdvice = "DROP_TRADES";
    } else if(alignment.netBias > 15) {
        result.tradeAdvice = isBuyTrade ? "STRONG_SIGNAL" : "WEAK_SIGNAL";
    } else if(alignment.netBias < -15) {
        result.tradeAdvice = isBuyTrade ? "WEAK_SIGNAL" : "STRONG_SIGNAL";
    } else {
        result.tradeAdvice = "NEUTRAL";
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Enhanced CheckSmartMACrossover (Updated)                        |
//+------------------------------------------------------------------+
bool CheckSmartMACrossover(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isUptrend)
{
    // Use the new alignment system
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    // Crossover detected if alignment is critical (MAs crossing/in buffer)
    return alignment.isCritical;
}

// [KEEP ALL OTHER FUNCTIONS AS-IS FOR BACKWARD COMPATIBILITY]
// The AnalyzeMA5_9Relationship, AnalyzeMA9_21Relationship, etc. can stay
// but they won't be used by the new system

//+------------------------------------------------------------------+
//| Get Detailed MA Analysis Report (Updated)                       |
//+------------------------------------------------------------------+
string GetMAAnalysisReport(const string symbol, const bool isBuyTrade)
{
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    string report = "\n=== ENHANCED MA ALIGNMENT ANALYSIS ===\n";
    report += StringFormat("Timeframe: %s\n", EnumToString(MA_Analysis_Timeframe));
    report += StringFormat("MAs: %d-%d-%d-%d (5-9-21-89)\n\n",
                          VeryFastMA_Period_Enhanced, FastMA_Period_Enhanced,
                          MediumMA_Period_Enhanced, SlowMA_Period_Enhanced);
    
    // report += "CONFIDENCE SCORES:\n";
    // report += StringFormat("  BUY Confidence:  %.1f/100 (Bullish alignment)\n", alignment.buyConfidence);
    // report += StringFormat("  SELL Confidence: %.1f/100 (Bearish alignment)\n", alignment.sellConfidence);
    // report += StringFormat("  Net Bias: %.1f (%s)\n\n", alignment.netBias, alignment.alignment);
    
    if(alignment.warning != "") {
        report += StringFormat("⚠️ WARNINGS: %s\n\n", alignment.warning);
    }
    
    report += StringFormat("CRITICAL: %s\n", alignment.isCritical ? "YES" : "NO");
    report += "=================================\n";
    
    return report;
}

// [KEEP ALL OTHER ORIGINAL FUNCTIONS - They can stay for backward compatibility]