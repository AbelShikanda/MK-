//+------------------------------------------------------------------+
//| ReversalDetector.mqh                                            |
//| Market Reversal Detection Module                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes - Updated to new structure
#include "../../config/inputs.mqh"
#include "../../config/structures.mqh"
#include "../../utils/IndicatorUtils.mqh"
#include "../detectors/PatternDivergence.mqh"
#include "MomentumDivergence.mqh"
#include "MARelationship.mqh"
#include "VolumeDivergence.mqh"

//+------------------------------------------------------------------+
//| Calculate Enhanced Reversal Confidence with Pattern Weighting    |
//+------------------------------------------------------------------+
double GetReversalConfidence(const string symbol, const bool isUptrend)
{
    double baseConfidence = 0.0;
    
    // ============ BASE SIGNALS ============
    if(CheckMomentumDivergence(symbol, PERIOD_M15, isUptrend)) 
        baseConfidence += 0.10;
    
    if(CheckSmartMACrossover(symbol, PERIOD_M15, isUptrend)) 
        baseConfidence += 0.80;
    
    if(CheckVolumeDrop(symbol, PERIOD_M15)) 
        baseConfidence += 0.10;
    
    // ============ PATTERN ANALYSIS ============
    double patternScore = GetPatternDivergenceScore(symbol, PERIOD_M15, isUptrend);
    string patternInterpretation = GetPatternStrengthInterpretation(patternScore);
    
    // Get pattern confidence based on score
    double patternConfidence = GetPatternConfidenceFromScore(patternScore, isUptrend);
    
    // Weight patterns dynamically based on their strength
    double patternWeight = GetPatternWeight(patternInterpretation);
    double patternContribution = patternConfidence * patternWeight;
    
    baseConfidence += patternContribution;
    
    // ============ RSI DIVERGENCE BONUS ============
    double divergenceBoost = GetDivergenceConfirmation(symbol, isUptrend);
    baseConfidence += (divergenceBoost * 0.15);
    
    // Clamp to 0-1.0
    return MathMin(MathMax(baseConfidence, 0.0), 1.0);
}

//+------------------------------------------------------------------+
//| Get Pattern Confidence From Score                               |
//| Converts 0-100 pattern score to 0-1.0 confidence                |
//+------------------------------------------------------------------+
double GetPatternConfidenceFromScore(double patternScore, bool isUptrend)
{
    if(isUptrend) {
        // For uptrend reversal, LOW scores indicate bearish patterns
        if(patternScore < 30) return 0.9;      // Very strong bearish
        if(patternScore < 40) return 0.7;      // Strong bearish
        if(patternScore < 50) return 0.4;      // Moderate bearish
        if(patternScore < 60) return 0.1;      // Weak bearish
        return 0.0;                            // Bullish (wrong direction)
    }
    else {
        // For downtrend reversal, HIGH scores indicate bullish patterns
        if(patternScore > 70) return 0.9;      // Very strong bullish
        if(patternScore > 60) return 0.7;      // Strong bullish
        if(patternScore > 50) return 0.4;      // Moderate bullish
        if(patternScore > 40) return 0.1;      // Weak bullish
        return 0.0;                            // Bearish (wrong direction)
    }
}

//+------------------------------------------------------------------+
//| Get Pattern Weight Based on Interpretation                      |
//+------------------------------------------------------------------+
double GetPatternWeight(string patternInterpretation)
{
    // Assign weights based on pattern strength
    if(StringFind(patternInterpretation, "VERY STRONG") >= 0) return 0.25;
    if(StringFind(patternInterpretation, "STRONG") >= 0) return 0.20;
    if(StringFind(patternInterpretation, "MODERATE") >= 0) return 0.15;
    if(StringFind(patternInterpretation, "MILD") >= 0) return 0.10;
    if(StringFind(patternInterpretation, "NEUTRAL") >= 0) return 0.05;
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get Divergence Confirmation Boost                               |
//| Returns 0-1.0 based on RSI divergence alignment                 |
//+------------------------------------------------------------------+
double GetDivergenceConfirmation(const string symbol, const bool isUptrend)
{
    DivergenceSignal divergence = CheckDivergence(symbol, PERIOD_M15);
    
    if(!divergence.exists) 
        return 0.0;
    
    // Check if divergence aligns with expected reversal direction
    bool alignmentMatch = false;
    
    if(isUptrend) 
    {
        // For uptrend reversal (bearish), we want bearish divergence
        alignmentMatch = !divergence.bullish;
    }
    else 
    {
        // For downtrend reversal (bullish), we want bullish divergence
        alignmentMatch = divergence.bullish;
    }
    
    if(!alignmentMatch) 
        return 0.0;
    
    // Return normalized divergence strength (0.0 to 1.0)
    return MathMin(divergence.score / Max_Score, 1.0);
}

//+------------------------------------------------------------------+
//| Get Confidence Level String                                     |
//+------------------------------------------------------------------+
string GetConfidenceLevel(double confidence)
{
    if(confidence >= 0.80) return "VERY HIGH CONFIDENCE";
    if(confidence >= 0.70) return "HIGH CONFIDENCE";
    if(confidence >= 0.60) return "MODERATE CONFIDENCE";
    if(confidence >= 0.50) return "LOW CONFIDENCE";
    if(confidence >= 0.30) return "VERY LOW CONFIDENCE";
    return "NO CONFIDENCE";
}

//+------------------------------------------------------------------+
//| Check If Reversal Signal Is Strong Enough                       |
//+------------------------------------------------------------------+
bool IsStrongReversalSignal(const string symbol, const bool isUptrend, double minConfidence = 0.65)
{
    double confidence = GetReversalConfidence(symbol, isUptrend);
    return (confidence >= minConfidence);
}

//+------------------------------------------------------------------+
//| Get Reversal Signal Details                                     |
//+------------------------------------------------------------------+
string GetReversalSignalDetails(const string symbol, const bool isUptrend)
{
    double confidence = GetReversalConfidence(symbol, isUptrend);
    string direction = isUptrend ? "BEARISH" : "BULLISH";
    
    return StringFormat("%s REVERSAL | Confidence: %.0f%% (%s)",
                       direction,
                       confidence * 100,
                       GetConfidenceLevel(confidence));
}