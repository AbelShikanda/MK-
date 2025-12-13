//+------------------------------------------------------------------+
//| Simplified DecisionEngine.mqh                                   |
//| Pure score addition/subtraction - NO value adjustments          |
//| UPDATED: Integrates new MA alignment + Pressure                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/structures.mqh"
#include "../../utils/IndicatorUtils.mqh"
#include "../../utils/TradeUtils.mqh"
#include "../../market/detectors/ReversalDetector.mqh"
#include "../../market/trend/TrendAnalyzer.mqh"

// ============ CONFIGURABLE WEIGHTS ============
#ifndef DECISION_ENGINE_WEIGHTS
#define DECISION_ENGINE_WEIGHTS

// Raw Score Weights (0-100 scale each) - UPDATED
input double Weight_Sentiment = 75.0;      // Sentiment score (0-100) - 70% weight
input double Weight_Trend = 15.0;          // Long-term trend score (0-100) - 20% weight
input double Weight_Pressure = 10.0;       // Market pressure score (0-100) - 10% weight
input double Weight_MA_Relationship = 30.0; // MA alignment score (0-100) - 30% of total

// Divergence Impact (symmetric for logical consistency)
input double Divergence_Impact_Strength = 15.0;  // Symmetric impact (±20 points)

// Thresholds
input double Divergence_Min_Threshold = 0.4;  // Minimum confidence to consider divergence
input double Signal_Conflict_Penalty = 10.0;  // Penalty when trend/sentiment conflict

#endif

// ============ GLOBAL VARIABLES ============
EngineMetrics g_engineMetrics;

//+------------------------------------------------------------------+
//| Initialize Decision Engine                                      |
//+------------------------------------------------------------------+
void InitDecisionEngine()
{
    g_engineMetrics.totalAdjustments = 0;
    g_engineMetrics.divergenceSignals = 0;
    g_engineMetrics.avgDivergenceImpact = 0.0;
    
    Print("=== PURE SCORE DECISION ENGINE INITIALIZED ===");
    PrintFormat("MTF Score Weights: Sentiment=%.0f, Trend=%.0f, Pressure=%.0f",
                Weight_Sentiment, Weight_Trend, Weight_Pressure);
    PrintFormat("MA Relationship Weight: %.0f", Weight_MA_Relationship);
    PrintFormat("Divergence Impact: ±%.0f points (symmetric)", Divergence_Impact_Strength);
}

//+------------------------------------------------------------------+
//| Check for Signal Conflicts                                      |
//+------------------------------------------------------------------+
double CheckSignalConsistency(double sentimentScore, bool isUptrend, string &outWarning)
{
    outWarning = "";
    double consistencyPenalty = 0.0;
    
    // Check if sentiment aligns with trend
    if(isUptrend && sentimentScore < 40) {
        outWarning = "UPTREND with BEARISH sentiment";
        consistencyPenalty = Signal_Conflict_Penalty;
    } else if(!isUptrend && sentimentScore > 60) {
        outWarning = "DOWNTREND with BULLISH sentiment";
        consistencyPenalty = Signal_Conflict_Penalty;
    } else if(isUptrend && sentimentScore < 50) {
        outWarning = "UPTREND with weak bullish sentiment";
        consistencyPenalty = Signal_Conflict_Penalty * 0.5;
    } else if(!isUptrend && sentimentScore > 50) {
        outWarning = "DOWNTREND with weak bearish sentiment";
        consistencyPenalty = Signal_Conflict_Penalty * 0.5;
    }
    
    return consistencyPenalty;
}

//+------------------------------------------------------------------+
//| Get Combined MTF Score (Sentiment + Trend + Pressure)           |
//| Uses weights: 70% sentiment, 20% trend, 10% pressure            |
//+------------------------------------------------------------------+
double GetCombinedMTFScore(double sentiment, double trend, double pressure)
{
    double combinedScore = (sentiment * (Weight_Sentiment/100.0)) +
                          (trend * (Weight_Trend/100.0)) +
                          (pressure * (Weight_Pressure/100.0));
    
    return MathMax(0, MathMin(100, combinedScore));
}

//+------------------------------------------------------------------+
//| Get MA Relationship Raw Score - UPDATED for new alignment system|
//+------------------------------------------------------------------+
double GetMARelationshipRawScore(string symbol, bool isUptrend)
{
    // Use the new MA alignment system
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    // Log the analysis
    PrintFormat("  === M15 MA ALIGNMENT ANALYSIS ===");
    PrintFormat("  Alignment: %s (Bias: %.1f)", alignment.alignment, alignment.netBias);
    PrintFormat("  BUY Confidence: %.1f/100", alignment.buyConfidence);
    PrintFormat("  SELL Confidence: %.1f/100", alignment.sellConfidence);
    
    if(alignment.warning != "") {
        PrintFormat("  Warnings: %s", alignment.warning);
    }
    if(alignment.isCritical) {
        PrintFormat("  ⚠️ CRITICAL CONDITION DETECTED");
    }
    PrintFormat("  ==================================");
    
    // Return appropriate confidence based on trend
    // In UPTREND: Use BUY confidence (bullish alignment)
    // In DOWNTREND: Use SELL confidence (bearish alignment)
    return isUptrend ? alignment.buyConfidence : alignment.sellConfidence;
}

//+------------------------------------------------------------------+
//| Get Raw Market Scores - UPDATED VERSION                         |
//+------------------------------------------------------------------+
AdjustedMarketData GetAdjustedMarketData(string symbol) 
{
    AdjustedMarketData adjusted;
    string warningMsg = "";
    
    Print("================================================");
    PrintFormat("PURE SCORE ANALYSIS for %s", symbol);
    Print("================================================");
    
    // ============ 1. GET MTF SCORES ============
    Print("\n[1] MTF SCORES (70-20-10 weights):");
    
    // Get sentiment, trend, and pressure
    adjusted.rawSentiment = CalculateGeneralTrend(symbol);
    adjusted.rawTrend = CalculateLongTermTrend(symbol);
    adjusted.rawPressure = CalculateMarketSentiment(symbol);
    
    double sentimentScore = adjusted.rawSentiment;      // 0-100 scale
    double trendScore = adjusted.rawTrend;              // 0-100 scale
    double pressureScore = adjusted.rawPressure;        // 0-100 scale
    
    PrintFormat("  Sentiment: %.1f/100 (Weight: %.0f%%)", sentimentScore, Weight_Sentiment);
    PrintFormat("  Long-term Trend: %.1f/100 (Weight: %.0f%%)", trendScore, Weight_Trend);
    PrintFormat("  Market Pressure: %.1f/100 (Weight: %.0f%%)", pressureScore, Weight_Pressure);
    
    // Calculate combined MTF score
    double combinedMTFScore = GetCombinedMTFScore(sentimentScore, trendScore, pressureScore);
    PrintFormat("  COMBINED MTF SCORE: %.1f/100", combinedMTFScore);
    
    // Determine trend direction from trend score
    bool isUptrend = (trendScore > 50);
    PrintFormat("  Trend Direction: %s (based on %.1f trend score)", 
                isUptrend ? "UPTREND" : "DOWNTREND", trendScore);
    
    // ============ 2. CHECK SIGNAL CONSISTENCY ============
    double consistencyPenalty = CheckSignalConsistency(combinedMTFScore, isUptrend, warningMsg);
    if(warningMsg != "") {
        PrintFormat("  WARNING: %s (Penalty: %.1f)", warningMsg, consistencyPenalty);
    }
    
    // ============ 3. GET MA RELATIONSHIP SCORE ============
    Print("\n[2] MA RELATIONSHIP SCORE:");
    double maRawScore = GetMARelationshipRawScore(symbol, isUptrend);
    PrintFormat("  Raw MA Score: %.1f (Weight: %.0f%%)", maRawScore, Weight_MA_Relationship);
    
    // ============ 4. GET DIVERGENCE INFO ============
    Print("\n[3] DIVERGENCE ANALYSIS:");
    double divergenceConfidence = GetReversalConfidence(symbol, isUptrend);
    adjusted.divergenceFactor = divergenceConfidence;
    
    if(divergenceConfidence > Divergence_Min_Threshold) {
        adjusted.divergenceType = isUptrend ? "BEARISH" : "BULLISH";
        g_engineMetrics.divergenceSignals++;
        
        PrintFormat("  %s DIVERGENCE DETECTED (%.0f%% confidence)", 
                   adjusted.divergenceType, divergenceConfidence * 100);
        
        // Calculate divergence impact (symmetric)
        double divergenceImpact = Divergence_Impact_Strength * divergenceConfidence;
        if(adjusted.divergenceType == "BEARISH") {
            adjusted.divergenceScore = -divergenceImpact; // Negative for buys, positive for sells
            PrintFormat("  BEARISH divergence → %.1f points impact", -divergenceImpact);
        } else {
            adjusted.divergenceScore = divergenceImpact; // Positive for buys, negative for sells
            PrintFormat("  BULLISH divergence → +%.1f points impact", divergenceImpact);
        }
    } else {
        adjusted.divergenceType = "NONE";
        adjusted.divergenceScore = 0.0;
        PrintFormat("  NO SIGNIFICANT DIVERGENCE (%.0f%% confidence)", 
                   divergenceConfidence * 100);
    }
    
    // ============ 5. CALCULATE TOTAL BUY/SELL SCORES ============
    Print("\n[4] FINAL SCORE CALCULATION:");

    // Get the MA alignment for this symbol
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);

    // Apply consistency penalty to conflicting signals
    double adjustedMTFBuy = combinedMTFScore;
    double adjustedMTFSell = 100 - combinedMTFScore;

    if(consistencyPenalty > 0) {
        if(isUptrend && combinedMTFScore < 40) {
            adjustedMTFBuy -= consistencyPenalty;
        } else if(!isUptrend && combinedMTFScore > 60) {
            adjustedMTFSell -= consistencyPenalty;
        }
    }

    // CALCULATE BUY SCORE:
    double maBuyScore = alignment.buyConfidence;  // BUY confidence from MA alignment
    double baseBuyScore = (adjustedMTFBuy * (Weight_Sentiment + Weight_Trend + Weight_Pressure)/100.0) +
                        (maBuyScore * (Weight_MA_Relationship/100.0));  // Use BUY confidence

    double divergenceImpactBuy = 0;
    if(adjusted.divergenceType == "BEARISH") {
        divergenceImpactBuy = adjusted.divergenceScore; // Negative impact for BUY
    } else if(adjusted.divergenceType == "BULLISH") {
        divergenceImpactBuy = adjusted.divergenceScore; // Positive impact for BUY
    }

    adjusted.buyScore = MathMax(0, MathMin(100, baseBuyScore + divergenceImpactBuy));

    // CALCULATE SELL SCORE:
    double maSellScore = alignment.sellConfidence;  // SELL confidence from MA alignment
    double baseSellScore = (adjustedMTFSell * (Weight_Sentiment + Weight_Trend + Weight_Pressure)/100.0) +
                        (maSellScore * (Weight_MA_Relationship/100.0));  // Use SELL confidence

    double divergenceImpactSell = 0;
    if(adjusted.divergenceType == "BULLISH") {
        divergenceImpactSell = -adjusted.divergenceScore; // Negative impact for SELL
    } else if(adjusted.divergenceType == "BEARISH") {
        divergenceImpactSell = -adjusted.divergenceScore; // Positive impact for SELL
    }

    adjusted.sellScore = MathMax(0, MathMin(100, baseSellScore + divergenceImpactSell));

    // Show calculation breakdown
    Print("  BUY SCORE CALCULATION:");
    PrintFormat("    Combined MTF = %.1f (penalty: %.1f)", 
                combinedMTFScore, consistencyPenalty);
    PrintFormat("    Adjusted MTF = %.1f", adjustedMTFBuy);
    PrintFormat("    MA BUY Confidence = %.1f", maBuyScore);
    PrintFormat("    Base Buy = (%.1f * %.0f%%) + (%.1f * %.0f%%) = %.1f",
                adjustedMTFBuy, (Weight_Sentiment + Weight_Trend + Weight_Pressure),
                maBuyScore, Weight_MA_Relationship, baseBuyScore);
    PrintFormat("    Divergence Impact = %.1f", divergenceImpactBuy);
    PrintFormat("    FINAL BUY SCORE = %.1f + %.1f = %.1f", 
                baseBuyScore, divergenceImpactBuy, adjusted.buyScore);

    Print("  SELL SCORE CALCULATION:");
    PrintFormat("    Combined MTF = %.1f (100 - %.1f)", 
                100 - combinedMTFScore, combinedMTFScore);
    PrintFormat("    Adjusted MTF = %.1f", adjustedMTFSell);
    PrintFormat("    MA SELL Confidence = %.1f", maSellScore);
    PrintFormat("    Base Sell = (%.1f * %.0f%%) + (%.1f * %.0f%%) = %.1f",
                adjustedMTFSell, (Weight_Sentiment + Weight_Trend + Weight_Pressure),
                maSellScore, Weight_MA_Relationship, baseSellScore);
    PrintFormat("    Divergence Impact = %.1f", divergenceImpactSell);
    PrintFormat("    FINAL SELL SCORE = %.1f + %.1f = %.1f", 
                baseSellScore, divergenceImpactSell, adjusted.sellScore);
    
    // ============ 6. SET REMAINING VALUES ============
    adjusted.adjustedSentiment = sentimentScore;
    adjusted.adjustedTrend = trendScore;
    adjusted.adjustedPressure = pressureScore;
    
    // Update metrics
    g_engineMetrics.totalAdjustments++;
    g_engineMetrics.avgDivergenceImpact = (g_engineMetrics.avgDivergenceImpact * 
                                          (g_engineMetrics.totalAdjustments - 1) + 
                                          divergenceConfidence) / g_engineMetrics.totalAdjustments;
    g_engineMetrics.lastCalculation = TimeCurrent();
    
    Print("\n================================================");
    PrintFormat("FINAL PURE SCORES for %s:", symbol);
    PrintFormat("  Trend: %s", isUptrend ? "UPTREND" : "DOWNTREND");
    PrintFormat("  MTF Score: %.1f (S:%.1f, T:%.1f, P:%.1f)", 
                combinedMTFScore, sentimentScore, trendScore, pressureScore);
    PrintFormat("  MA Score: %.1f", maRawScore);
    PrintFormat("  BUY Score: %.1f", adjusted.buyScore);
    PrintFormat("  SELL Score: %.1f", adjusted.sellScore);
    if(warningMsg != "") {
        PrintFormat("  Warning: %s", warningMsg);
    }
    if(adjusted.divergenceType != "NONE") {
        PrintFormat("  Divergence: %s (%.0f%% confidence)", 
                   adjusted.divergenceType, divergenceConfidence * 100);
        PrintFormat("  Divergence Impact: %.1f points", adjusted.divergenceScore);
    }
    Print("================================================");
    
    return adjusted;
}

//+------------------------------------------------------------------+
//| Get Market Data For TradeExecutor                               |
//+------------------------------------------------------------------+
MarketData GetMarketDataForExecutor(string symbol)
{
    MarketData data;
    
    AdjustedMarketData adjusted = GetAdjustedMarketData(symbol);
    
    // TradeExecutor needs these:
    data.sentiment = adjusted.adjustedSentiment;
    data.buyScore = adjusted.buyScore;
    data.sellScore = adjusted.sellScore;
    
    // For logging only:
    data.trend = adjusted.adjustedTrend;
    data.pressure = adjusted.adjustedPressure;
    
    // Position info:
    data.openTrades = CountOpenTrades(symbol);
    
    // Convert trade direction to string (simple cast)
    data.currentDirection = (string)GetCurrentTradeDirection(symbol);
    
    return data;
}

//+------------------------------------------------------------------+
//| Get Engine Metrics                                              |
//+------------------------------------------------------------------+
EngineMetrics GetDecisionEngineMetrics()
{
    return g_engineMetrics;
}

//+------------------------------------------------------------------+
//| Print Engine Status                                             |
//+------------------------------------------------------------------+
void PrintDecisionEngineStatus()
{
    Print("=== PURE SCORE DECISION ENGINE STATUS ===");
    PrintFormat("Total Analyses: %d", g_engineMetrics.totalAdjustments);
    PrintFormat("Divergence Signals: %d", g_engineMetrics.divergenceSignals);
    PrintFormat("Average Divergence Confidence: %.2f", g_engineMetrics.avgDivergenceImpact);
    Print("==========================================");
}

// [KEEP ALL OTHER FUNCTIONS AS-IS]
//+------------------------------------------------------------------+
//| Get Divergence Warning                                          |
//+------------------------------------------------------------------+
string GetDivergenceWarningLevel(double divergenceConfidence)
{
    if(divergenceConfidence > 0.7) 
        return "HIGH_WARNING";
    if(divergenceConfidence > 0.4) 
        return "MODERATE_WARNING";
    return "LOW_WARNING";
}

//+------------------------------------------------------------------+
//| Should Consider Divergence In Trade                             |
//+------------------------------------------------------------------+
bool ShouldConsiderDivergenceInTrade(string symbol, bool forBuyTrade)
{
    AdjustedMarketData adjusted = GetAdjustedMarketData(symbol);
    
    if(adjusted.divergenceType == "NONE") 
        return false;
    
    // Only consider if divergence confidence is significant
    if(adjusted.divergenceFactor < 0.5) 
        return false;
    
    // Check if divergence conflicts with intended trade
    if(forBuyTrade && adjusted.divergenceType == "BEARISH") 
        return true;
    if(!forBuyTrade && adjusted.divergenceType == "BULLISH") 
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Divergence Score for a Specific Trade Direction             |
//+------------------------------------------------------------------+
double GetDivergenceScoreForTrade(string symbol, bool forBuyTrade)
{
    AdjustedMarketData adjusted = GetAdjustedMarketData(symbol);
    
    if(adjusted.divergenceType == "NONE") 
        return 0.0;
    
    // Base impact scaled by confidence
    double baseImpact = Divergence_Impact_Strength * adjusted.divergenceFactor;
    
    if(forBuyTrade) {
        return (adjusted.divergenceType == "BULLISH") ? baseImpact : -baseImpact;
    } else {
        return (adjusted.divergenceType == "BEARISH") ? baseImpact : -baseImpact;
    }
}

//+------------------------------------------------------------------+
//| Analyze Signal Quality                                          |
//+------------------------------------------------------------------+
double AnalyzeSignalQuality(string symbol)
{
    AdjustedMarketData adjusted = GetAdjustedMarketData(symbol);
    bool isUptrend = (adjusted.adjustedTrend > 50);
    
    double qualityScore = 0.0;
    int factorCount = 0;
    
    // 1. Trend-Sentiment alignment (40% weight)
    double alignmentScore = 0.0;
    if(isUptrend && adjusted.adjustedSentiment > 50) {
        alignmentScore = (adjusted.adjustedSentiment - 50) * 2; // 0-100 scale
    } else if(!isUptrend && adjusted.adjustedSentiment < 50) {
        alignmentScore = (50 - adjusted.adjustedSentiment) * 2; // 0-100 scale
    }
    qualityScore += alignmentScore * 0.4;
    factorCount++;
    
    // 2. Divergence strength (30% weight)
    double divergenceQuality = adjusted.divergenceFactor * 100;
    qualityScore += divergenceQuality * 0.3;
    factorCount++;
    
    // 3. Score gap (30% weight)
    double scoreGap = MathAbs(adjusted.buyScore - adjusted.sellScore);
    qualityScore += scoreGap * 0.3;
    factorCount++;
    
    return qualityScore / factorCount;
}