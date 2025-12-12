//+------------------------------------------------------------------+
//| TrendAnalyzer.mqh                                               |
//| Market Trend Analysis Module                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/GlobalVariables.mqh"
#include "../../utils/MathUtils.mqh"
#include "../../signals/SignalScorer.mqh"
#include "../../market/trend/MomentumCalculator.mqh"
#include "../../market/trend/MultiTimeframe.mqh"



//+------------------------------------------------------------------+
//| Calculate Market Sentiment                                      |
//| Consolidated sentiment analysis functions                       |
//+------------------------------------------------------------------+
double CalculateMarketSentiment(const string symbol)
{
    double sentiment = 50.0;
    
    // Combine multiple sentiment indicators
    sentiment += AnalyzePriceMomentum(symbol) * 0.4;
    sentiment += AnalyzeVolumeSentiment(symbol) * 0.3;
    sentiment += AnalyzeTimeframeAlignment(symbol) * 0.3;
    
    // Clamp between 0 and 100
    sentiment = MathMax(0.0, MathMin(100.0, sentiment));
    return sentiment;
}

//+------------------------------------------------------------------+
//| Calculate General Market Trend (0-100%)                         |
//| Consolidated from GeneralMarketTrend.mqh                        |
//+------------------------------------------------------------------+
double CalculateGeneralTrend(const string symbol)
{
    double trend = 0.0;
    
    // 1. H4 Long-term MA Analysis (40% weight)
    const int h4Index = ArrayPosition(symbol);
    if(h4Index != -1)
    {
        const double longTermMAValue = GetCurrentMAValue(longTermMA_H4[h4Index]);
        const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        if(longTermMAValue > 0.0)
        {
            const double distancePercent = MathAbs((currentPrice - longTermMAValue) / longTermMAValue) * 100.0;
            
            if(currentPrice > longTermMAValue)
                trend += 50.0 + MathMin(distancePercent * 2.0, 25.0); // Bullish: 50-75
            else
                trend += 50.0 - MathMin(distancePercent * 2.0, 25.0); // Bearish: 25-50
        }
    }
    
    // 2. Multi-Timeframe Alignment (30% weight)
    const double mtfBuyStrength = CalculateMultiTFAlignment(symbol, true);
    const double mtfSellStrength = CalculateMultiTFAlignment(symbol, false);
    trend += ((mtfBuyStrength - mtfSellStrength + 100.0) / 2.0) * 0.3;
    
    // 3. Consecutive Bar Momentum (30% weight)
    const int bullishBars = CountConsecutiveBars(symbol, true);
    const int bearishBars = CountConsecutiveBars(symbol, false);
    
    if(bullishBars > bearishBars)
        trend += (bullishBars * 10.0); // Up to 30 points
    else if(bearishBars > bullishBars)
        trend -= (bearishBars * 10.0); // Down to 0 points
    
    // Clamp the value between 0 and 100
    trend = MathMax(0.0, MathMin(100.0, trend));
    
    return trend;
}

//+------------------------------------------------------------------+
//| Calculate Long-Term Trend (H1 MA100)                            |
//| Consolidated from GeneralMarketTrend.mqh                        |
//+------------------------------------------------------------------+
double CalculateLongTermTrend(const string symbol)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1 || longTermMA_LT[symbolIndex] == -1)
        return 50.0;
    
    double trend = 50.0;
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Get H1 MA100 value
    double maBuffer[1];
    if(CopyBuffer(longTermMA_LT[symbolIndex], 0, 0, 1, maBuffer) >= 1)
    {
        const double h1MA100 = maBuffer[0];
        
        if(h1MA100 > 0.0)
        {
            // MA Position Score (70% weight)
            double maPositionScore = 50.0;
            if(currentPrice > h1MA100)
                maPositionScore = 75.0;
            else
                maPositionScore = 25.0;
            
            // H1 Momentum Score (30% weight)
            const double h1OpenPrice = iOpen(symbol, PERIOD_H1, 0);
            double h1MomentumScore = 50.0;
            if(currentPrice > h1OpenPrice)
                h1MomentumScore = 70.0;
            else
                h1MomentumScore = 30.0;
            
            // Weighted combination
            trend = (maPositionScore * 0.7) + (h1MomentumScore * 0.3);
        }
    }
    
    // Clamp the value between 0 and 100
    trend = MathMax(0.0, MathMin(100.0, trend));
    
    return trend;
}

//+------------------------------------------------------------------+
//| Analyze Price Momentum                                          |
//| Helper function for sentiment calculation                       |
//+------------------------------------------------------------------+
double AnalyzePriceMomentum(const string symbol)
{
    const int barsToCheck = 5;
    double bullishCount = 0.0;
    
    for(int i = 0; i < barsToCheck; i++)
    {
        const double open = iOpen(symbol, PERIOD_H1, i);
        const double close = iClose(symbol, PERIOD_H1, i);
        
        if(close > open)
            bullishCount += 1.0;
    }
    
    return (bullishCount / barsToCheck) * 100.0;
}

//+------------------------------------------------------------------+
//| Analyze Volume Sentiment                                        |
//| Helper function for sentiment calculation                       |
//+------------------------------------------------------------------+
double AnalyzeVolumeSentiment(const string symbol)
{
    // Get current volume (iVolume returns long, so cast to double)
    const long currentVolumeLong = iVolume(symbol, PERIOD_H1, 0);
    const double currentVolume = (double)currentVolumeLong;
    
    // Get average volume (using iMA correctly)
    // iMA parameters: symbol, timeframe, period, ma_shift, method, applied_price
    double avgVolumeArray[1];
    int maHandle = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_TYPICAL);
    
    if(maHandle == INVALID_HANDLE || CopyBuffer(maHandle, 0, 0, 1, avgVolumeArray) < 1)
    {
        if(maHandle != INVALID_HANDLE) 
            IndicatorRelease(maHandle);
        return 50.0;
    }
    
    IndicatorRelease(maHandle);
    const double avgVolume = avgVolumeArray[0];
    
    if(avgVolume > 0.0)
    {
        const double volumeRatio = currentVolume / avgVolume;
        
        // Higher volume suggests stronger conviction
        if(volumeRatio > 1.5)
        {
            const double closePrice = iClose(symbol, PERIOD_H1, 0);
            const double openPrice = iOpen(symbol, PERIOD_H1, 0);
            
            if(openPrice > 0.0)
            {
                const double priceChange = ((closePrice - openPrice) / openPrice) * 100.0;
                return priceChange > 0 ? 80.0 : 20.0;
            }
        }
    }
    
    return 50.0;
}

//+------------------------------------------------------------------+
//| Analyze Timeframe Alignment                                     |
//| Helper function for sentiment calculation                       |
//+------------------------------------------------------------------+
double AnalyzeTimeframeAlignment(const string symbol)
{
    // Check alignment across multiple timeframes
    int alignedBullish = 0;
    int alignedBearish = 0;
    
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
    
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        const double open = iOpen(symbol, timeframes[i], 0);
        const double close = iClose(symbol, timeframes[i], 0);
        
        if(close > open)
            alignedBullish++;
        else
            alignedBearish++;
    }
    
    const double alignmentRatio = (double)alignedBullish / (double)(alignedBullish + alignedBearish);
    return alignmentRatio * 100.0;
}