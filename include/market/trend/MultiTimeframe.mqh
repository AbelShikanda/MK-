//+------------------------------------------------------------------+
//| MultiTimeframe.mqh                                              |
//| Multi-Timeframe Trend Analysis Module                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes - Updated to new structure
#include "../../config/inputs.mqh"
#include "../../config/GlobalVariables.mqh"
#include "../../config/structures.mqh"
#include "../../utils/IndicatorUtils.mqh"
#include "../../utils/SymbolUtils.mqh"

//+------------------------------------------------------------------+
//| Calculate Multi-Timeframe Alignment (0-100%)                    |
//| Consolidated from TrendAnalysis.mqh                             |
//+------------------------------------------------------------------+
double CalculateMultiTFAlignment(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    // Weight distribution for timeframes (sums to 1.0 = 100%)
    const double M5_WEIGHT  = 0.35;  // Most sensitive - short-term
    const double M15_WEIGHT = 0.30;  // Medium-term
    const double H1_WEIGHT  = 0.25;  // Intermediate-term
    const double H4_WEIGHT  = 0.10;  // Long-term bias
    
    double totalScore = 0.0;
    
    // Calculate timeframe-specific scores
    const double m5Score = CalculateMATrendStack(symbol, isBuy, PERIOD_M5);
    const double m15Score = CalculateMATrendStack(symbol, isBuy, PERIOD_M15);
    const double h1Score = CalculateMATrendStack(symbol, isBuy, PERIOD_H1);
    
    // Weighted combination
    totalScore = (m5Score * M5_WEIGHT) + 
                 (m15Score * M15_WEIGHT) + 
                 (h1Score * H1_WEIGHT);
    
    // Add long-term bias if required
    if(RequireLongTermTrend)
    {
        const double h4Bias = GetH4TrendBias(symbol, isBuy);
        totalScore += h4Bias * H4_WEIGHT;
    }
    
    // Apply price position validation
    if(!IsPriceInFavor(symbol, isBuy))
    {
        totalScore *= 0.7;  // Penalize if price not cooperating
    }
    
    return MathMin(totalScore, 100.0);
}

//+------------------------------------------------------------------+
//| Calculate MA Trend Stack Alignment                               |
//| Evaluates multiple MA alignment for a specific timeframe        |
//+------------------------------------------------------------------+
double CalculateMATrendStack(const string symbol, const bool isBuy, const ENUM_TIMEFRAMES timeframe)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    double vfMA = 0.0, fMA = 0.0, mMA = 0.0, sMA = 0.0;
    
    // Get appropriate MA values based on timeframe
    switch(timeframe)
    {
        case PERIOD_M5:
            vfMA = GetCurrentMAValue(veryFastMA_M5[symbolIndex]);
            fMA = GetCurrentMAValue(fastMA_M5[symbolIndex]);
            mMA = GetCurrentMAValue(mediumMA_M5[symbolIndex]);
            sMA = GetCurrentMAValue(slowMA_M5[symbolIndex]);
            break;
            
        case PERIOD_M15:
            vfMA = GetCurrentMAValue(fastMA_M15[symbolIndex]);  // M15 uses fast as very fast
            fMA = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
            mMA = GetCurrentMAValue(slowMA_M15[symbolIndex]);
            sMA = GetCurrentMAValue(longTermMA_H4[symbolIndex]);  // Long-term context
            break;
            
        case PERIOD_H1:
            fMA = GetCurrentMAValue(fastMA_H1[symbolIndex]);
            mMA = GetCurrentMAValue(mediumMA_H1[symbolIndex]);
            sMA = GetCurrentMAValue(slowMA_H1[symbolIndex]);
            vfMA = fMA;  // Use fast as very fast for consistency
            break;
            
        default:
            return 0.0;
    }
    
    // Count conditions met for perfect MA stack
    int conditionsMet = 0;
    int totalConditions = 0;
    
    if(isBuy)
    {
        // Bullish stack: vfMA > fMA > mMA > sMA
        if(vfMA > 0.0 && fMA > 0.0)
        {
            if(vfMA > fMA) conditionsMet++;
            totalConditions++;
        }
        
        if(fMA > 0.0 && mMA > 0.0)
        {
            if(fMA > mMA) conditionsMet++;
            totalConditions++;
        }
        
        if(mMA > 0.0 && sMA > 0.0)
        {
            if(mMA > sMA) conditionsMet++;
            totalConditions++;
        }
    }
    else
    {
        // Bearish stack: vfMA < fMA < mMA < sMA
        if(vfMA > 0.0 && fMA > 0.0)
        {
            if(vfMA < fMA) conditionsMet++;
            totalConditions++;
        }
        
        if(fMA > 0.0 && mMA > 0.0)
        {
            if(fMA < mMA) conditionsMet++;
            totalConditions++;
        }
        
        if(mMA > 0.0 && sMA > 0.0)
        {
            if(mMA < sMA) conditionsMet++;
            totalConditions++;
        }
    }
    
    // Calculate alignment percentage
    double score = 0.0;
    if(totalConditions > 0)
    {
        score = ((double)conditionsMet / (double)totalConditions) * 100.0;
        
        // Bonus for perfect stack alignment
        if(totalConditions >= 3 && conditionsMet == 3)
        {
            score = MathMin(score + 10.0, 100.0);  // Bonus for perfect alignment
        }
    }
    
    return score;
}

//+------------------------------------------------------------------+
//| Get H4 Trend Bias                                                |
//| Long-term trend bias using H4 timeframe                         |
//+------------------------------------------------------------------+
double GetH4TrendBias(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 50.0;  // Neutral
    
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    const double longTermMA = GetCurrentMAValue(longTermMA_H4[symbolIndex]);
    
    // Basic price vs. long-term MA check
    if((isBuy && currentPrice > longTermMA) || (!isBuy && currentPrice < longTermMA))
    {
        return 80.0;  // Strong bias in favor
    }
    
    // Check H1 MA alignment as proxy for medium-term trend
    const double h1FastMA = GetCurrentMAValue(fastMA_H1[symbolIndex]);
    const double h1MediumMA = GetCurrentMAValue(mediumMA_H1[symbolIndex]);
    
    if(isBuy)
    {
        if(h1FastMA > h1MediumMA && h1MediumMA > longTermMA)
            return 90.0;  // Perfect bullish alignment
        if(h1FastMA > longTermMA)
            return 70.0;  // Positive but not perfect
    }
    else
    {
        if(h1FastMA < h1MediumMA && h1MediumMA < longTermMA)
            return 90.0;  // Perfect bearish alignment
        if(h1FastMA < longTermMA)
            return 70.0;  // Negative but not perfect
    }
    
    return 30.0;  // Weak or contrary bias
}

//+------------------------------------------------------------------+
//| Check if Price Position is Favorable                            |
//| Validates price relative to key moving average                  |
//+------------------------------------------------------------------+
bool IsPriceInFavor(const string symbol, const bool isBuy)
{
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    const int symbolIndex = ArrayPosition(symbol);
    
    if(symbolIndex == -1) return false;
    
    // Use M15 fast MA for price position validation
    const double keyMA = GetCurrentMAValue(fastMA_M15[symbolIndex]);
    
    if(isBuy)
    {
        return currentPrice > keyMA;  // Price should be above key MA for buys
    }
    else
    {
        return currentPrice < keyMA;  // Price should be below key MA for sells
    }
}

//+------------------------------------------------------------------+
//| Calculate Timeframe Alignment Strength                          |
//| Enhanced multi-timeframe analysis with detailed scoring         |
//+------------------------------------------------------------------+
double CalculateTimeframeAlignmentStrength(const string symbol, const bool isBuy)
{
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
    double alignmentScores[4];
    double totalWeight = 0.0;
    
    // Calculate and weight scores for each timeframe
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        double timeframeWeight = 0.0;
        
        switch(timeframes[i])
        {
            case PERIOD_M5:  timeframeWeight = 0.35; break;
            case PERIOD_M15: timeframeWeight = 0.30; break;
            case PERIOD_H1:  timeframeWeight = 0.25; break;
            case PERIOD_H4:  timeframeWeight = 0.10; break;
        }
        
        if(timeframes[i] == PERIOD_H4 && !RequireLongTermTrend)
        {
            alignmentScores[i] = 50.0;  // Neutral if not required
        }
        else
        {
            alignmentScores[i] = CalculateMATrendStack(symbol, isBuy, timeframes[i]);
        }
        
        totalWeight += timeframeWeight;
    }
    
    // Calculate weighted average
    double weightedScore = 0.0;
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        double timeframeWeight = 0.0;
        switch(timeframes[i])
        {
            case PERIOD_M5:  timeframeWeight = 0.35; break;
            case PERIOD_M15: timeframeWeight = 0.30; break;
            case PERIOD_H1:  timeframeWeight = 0.25; break;
            case PERIOD_H4:  timeframeWeight = 0.10; break;
        }
        
        weightedScore += alignmentScores[i] * (timeframeWeight / totalWeight);
    }
    
    return MathMin(weightedScore, 100.0);
}

//+------------------------------------------------------------------+
//| Check if Multiple Timeframes are Aligned                        |
//| Returns true if all specified timeframes show same direction    |
//+------------------------------------------------------------------+
bool IsMultiTFAligned(const string symbol, const bool isBuy, const int minTimeframes = 2)
{
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1};
    int alignedCount = 0;
    
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        const double score = CalculateMATrendStack(symbol, isBuy, timeframes[i]);
        if(score >= 60.0)  // Threshold for alignment
        {
            alignedCount++;
        }
    }
    
    return alignedCount >= minTimeframes;
}

//+------------------------------------------------------------------+
//| Get Dominant Timeframe Trend                                    |
//| Identifies which timeframe shows strongest trend                |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetDominantTimeframeTrend(const string symbol, const bool isBuy)
{
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
    double strongestScore = 0.0;
    ENUM_TIMEFRAMES dominantTF = PERIOD_CURRENT;
    
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        const double score = CalculateMATrendStack(symbol, isBuy, timeframes[i]);
        if(score > strongestScore)
        {
            strongestScore = score;
            dominantTF = timeframes[i];
        }
    }
    
    return dominantTF;
}