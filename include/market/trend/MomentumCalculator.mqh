//+------------------------------------------------------------------+
//| MomentumCalculator.mqh                                          |
//| Trend Momentum & Pullback Analysis                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes - Updated to new structure
#include "../../config/inputs.mqh"
#include "../../signals/SignalScorer.mqh"
#include "../../market/trend/MultiTimeframe.mqh"

//+------------------------------------------------------------------+
//| Calculate Trend Momentum Score (0-100%)                         |
//| Consolidated from TrendMomentum.mqh                             |
//+------------------------------------------------------------------+
double CalculateTrendMomentum(const string symbol, const bool isBuy, const ENUM_TIMEFRAMES timeframe)
{
    double momentum = 0.0;
    const int periods = 5;  // Analyze last 5 bars
    
    for(int i = 1; i <= periods; i++)
    {
        const double open = iOpen(symbol, timeframe, i);
        const double close = iClose(symbol, timeframe, i);
        const double high = iHigh(symbol, timeframe, i);
        const double low = iLow(symbol, timeframe, i);
        
        // Calculate candle strength metrics
        const double bodySize = MathAbs(close - open);
        const double totalRange = high - low;
        
        if(totalRange > 0.0)
        {
            const double bodyRatio = bodySize / totalRange;
            const bool isBullish = (close > open);
            const bool isBearish = (close < open);
            
            // Apply momentum based on trade direction
            if((isBuy && isBullish) || (!isBuy && isBearish))
            {
                momentum += bodyRatio * 20.0;  // Maximum 20% per candle
            }
            
            // Volume confirmation (if enabled)
            if(UseVolumeConfirmation)
            {
                const long currentVolume = iVolume(symbol, timeframe, i);
                const long previousVolume = iVolume(symbol, timeframe, i + 1);
                
                if(previousVolume > 0 && currentVolume > previousVolume * 1.2)
                {
                    momentum += 4.0;  // Volume boost
                }
            }
        }
    }
    
    return MathMin(momentum, 100.0);
}

//+------------------------------------------------------------------+
//| Check for Aggressive Pullback Entry Condition                   |
//| Consolidated from PullBack.mqh                                  |
//+------------------------------------------------------------------+
bool CheckAggressivePullback(const string symbol, const bool isBuy)
{
    if(!UseAggressiveEntries) return false;
    
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return false;
    
    // Get current price based on trade direction
    const double currentPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_BID) : 
        SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    // Calculate recent swing extremes
    double swingHigh = 0.0;
    double swingLow = 0.0;
    bool firstBar = true;
    const int lookbackBars = 50;
    
    for(int i = 1; i <= lookbackBars; i++)
    {
        const double barHigh = iHigh(symbol, TradeTF, i);
        const double barLow = iLow(symbol, TradeTF, i);
        
        if(firstBar)
        {
            swingHigh = barHigh;
            swingLow = barLow;
            firstBar = false;
        }
        else
        {
            swingHigh = MathMax(swingHigh, barHigh);
            swingLow = MathMin(swingLow, barLow);
        }
    }
    
    // Calculate pullback percentage
    double pullbackPercent = 0.0;
    const double tolerance = 5.0;  // ±5% tolerance
    
    if(isBuy)
    {
        // Buy: Pullback from swing high toward swing low
        const double recentHigh = swingHigh;
        const double pullbackDistance = recentHigh - currentPrice;
        const double totalMove = recentHigh - swingLow;
        
        if(totalMove > 0.0)
        {
            pullbackPercent = (pullbackDistance / totalMove) * 100.0;
        }
    }
    else
    {
        // Sell: Pullback from swing low toward swing high
        const double recentLow = swingLow;
        const double pullbackDistance = currentPrice - recentLow;
        const double totalMove = swingHigh - recentLow;
        
        if(totalMove > 0.0)
        {
            pullbackPercent = (pullbackDistance / totalMove) * 100.0;
        }
    }
    
    // Check if pullback is within target range
    const bool withinRange = 
        (pullbackPercent >= (PullbackEntryPercent - tolerance)) && 
        (pullbackPercent <= (PullbackEntryPercent + tolerance));
    
    // Optional logging (uncomment if needed)
    // if(withinRange)
    // {
    //     PrintFormat("PULLBACK_DETECTED: %s | Direction: %s | Pullback: %.1f%% (Target: %.1f%%)",
    //                symbol, isBuy ? "BUY" : "SELL", pullbackPercent, PullbackEntryPercent);
    // }
    
    return withinRange;
}

//+------------------------------------------------------------------+
//| Calculate Pullback Depth Percentage                             |
//| Helper function for pullback analysis                           |
//+------------------------------------------------------------------+
double CalculatePullbackDepth(const string symbol, const bool isBuy, const ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
    const int lookback = 20;
    double swingHigh = 0.0;
    double swingLow = 0.0;
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Find swing extremes
    for(int i = 1; i <= lookback; i++)
    {
        swingHigh = MathMax(swingHigh, iHigh(symbol, timeframe, i));
        swingLow = (i == 1) ? iLow(symbol, timeframe, i) : MathMin(swingLow, iLow(symbol, timeframe, i));
    }
    
    if(isBuy)
    {
        // For buy entries: distance from swing high
        if(swingHigh > 0.0 && swingLow < swingHigh)
        {
            return ((swingHigh - currentPrice) / (swingHigh - swingLow)) * 100.0;
        }
    }
    else
    {
        // For sell entries: distance from swing low
        if(swingLow > 0.0 && swingHigh > swingLow)
        {
            return ((currentPrice - swingLow) / (swingHigh - swingLow)) * 100.0;
        }
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Momentum Convergence                                  |
//| Enhanced momentum analysis across multiple factors              |
//+------------------------------------------------------------------+
double CalculateMomentumConvergence(const string symbol, const bool isBuy)
{
    double convergence = 0.0;
    
    // 1. Price Momentum (40% weight)
    const double priceMomentum = CalculateTrendMomentum(symbol, isBuy, TradeTF);
    convergence += priceMomentum * 0.4;
    
    // 2. Volume Momentum (30% weight)
    convergence += CalculateVolumeMomentum(symbol, isBuy) * 0.3;
    
    // 3. Multi-Timeframe Alignment (30% weight)
    convergence += CalculateMultiTFMomentum(symbol, isBuy) * 0.3;
    
    return MathMin(convergence, 100.0);
}

//+------------------------------------------------------------------+
//| Calculate Volume Momentum                                       |
//| Helper function for volume-based momentum                       |
//+------------------------------------------------------------------+
double CalculateVolumeMomentum(const string symbol, const bool isBuy, const ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
    const int barsToAnalyze = 3;
    double volumeRatioSum = 0.0;
    int validBars = 0;
    
    for(int i = 0; i < barsToAnalyze; i++)
    {
        const long currentVolume = iVolume(symbol, timeframe, i);
        const long previousVolume = iVolume(symbol, timeframe, i + 1);
        
        if(previousVolume > 0)
        {
            const double volumeRatio = (double)currentVolume / (double)previousVolume;
            
            // Check if volume supports the price direction
            const double close = iClose(symbol, timeframe, i);
            const double open = iOpen(symbol, timeframe, i);
            
            if((isBuy && close > open && volumeRatio > 1.0) || 
               (!isBuy && close < open && volumeRatio > 1.0))
            {
                volumeRatioSum += MathMin(volumeRatio, 2.0);  // Cap at 2.0
                validBars++;
            }
        }
    }
    
    if(validBars > 0)
    {
        return (volumeRatioSum / validBars) * 50.0;  // Convert to 0-100 scale
    }
    
    return 50.0;  // Neutral
}

//+------------------------------------------------------------------+
//| Calculate Multi-Timeframe Momentum                              |
//| Helper function for MTF momentum alignment                      |
//+------------------------------------------------------------------+
double CalculateMultiTFMomentum(const string symbol, const bool isBuy)
{
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4};
    int alignedCount = 0;
    
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        const double momentum = CalculateTrendMomentum(symbol, isBuy, timeframes[i]);
        if(momentum > 60.0)  // Strong momentum threshold
        {
            alignedCount++;
        }
    }
    
    return (double)alignedCount / (double)ArraySize(timeframes) * 100.0;
}