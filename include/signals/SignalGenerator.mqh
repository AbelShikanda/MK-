//+------------------------------------------------------------------+
//| SignalGenerator.mqh                                             |
//| Trade Signal Generation Module                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../config/structures.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../signals/SignalScorer.mqh"
#include "../signals/ValidationEngine.mqh"
#include "../risk/PositionSizer.mqh"
#include "../utils/TradeUtils.mqh"

//+------------------------------------------------------------------+
//| Input parameters for Signal Generator                           |
//+------------------------------------------------------------------+

input group "=== Volatility Filters ==="
input double MinimumVolatility        = 0.0005; // Minimum ATR volatility (e.g., 5 pips)
input double MaximumVolatility        = 0.0020; // Maximum ATR volatility (e.g., 20 pips)

input group "=== Trading Session Filters ==="
input int    TradingStartHour         = 0;      // Trading session start hour (0-23)
input int    TradingEndHour           = 24;     // Trading session end hour (0-24)
input bool   UseSessionFilter         = true;   // Enable trading session filter

input group "=== Risk Management ==="
input double MaximumRiskPercent       = 2.0;    // Maximum risk per trade (%)
input double MaximumDailyRisk         = 5.0;    // Maximum daily risk (%)
input int    MaxConcurrentTrades      = 3;      // Maximum concurrent trades

//+------------------------------------------------------------------+
//| Get Ultra Buy Signal with Position Info                         |
//+------------------------------------------------------------------+
bool GetUltraBuySignal(const string symbol, double &outLotSize, double &outStopLoss)
{
    // Check candle body
    // bool bullCandle = false, bearCandle = false;
    // if(!CheckCandleBody(symbol, bullCandle, bearCandle) || !bullCandle)
    //     return false;
    
    bool bullCandle = true; // Bypass candle body check for ultra signals
    
    // Check ultra-sensitive entry
    if(!CheckUltraSensitiveEntry(symbol, true))
        return false;
    
    // Validate trade direction
    bool allowBuy = true, allowSell = true;
    if(!ValidateDirection(symbol, allowBuy, allowSell) || !allowBuy)
        return false;
    
    // Track signal
    TrackSignal(symbol, "BUY-ULTRA", 90.0);
    
    // Calculate position size and stop loss
    outLotSize = CalculatePositionForSignal(symbol, true);
    outStopLoss = CalculateStopLossForSignal(symbol, true);
    
    return (outLotSize > 0 && outStopLoss > 0);
}

//+------------------------------------------------------------------+
//| Get Ultra Sell Signal with Position Info                        |
//+------------------------------------------------------------------+
bool GetUltraSellSignal(const string symbol, double &outLotSize, double &outStopLoss)
{
    // Check candle body
    bool bullCandle = false, bearCandle = false;
    if(!CheckCandleBody(symbol, bullCandle, bearCandle) || !bearCandle)
        return false;
    
    // Check ultra-sensitive entry
    if(!CheckUltraSensitiveEntry(symbol, false))
        return false;
    
    // Validate trade direction
    bool allowBuy = true, allowSell = true;
    if(!ValidateDirection(symbol, allowBuy, allowSell) || !allowSell)
        return false;
    
    // Track signal
    TrackSignal(symbol, "SELL-ULTRA", 90.0);
    
    // Calculate position size and stop loss
    outLotSize = CalculatePositionForSignal(symbol, false);
    outStopLoss = CalculateStopLossForSignal(symbol, false);
    
    return (outLotSize > 0 && outStopLoss > 0);
}

//+------------------------------------------------------------------+
//| Calculate Position for Signal                                   |
//+------------------------------------------------------------------+
double CalculatePositionForSignal(const string symbol, const bool isBuy)
{
    double lotSize = CalculateProgressivePositionSize(symbol);
    
    if(lotSize <= 0)
    {
        PrintFormat("POSITION_SIZE_ERROR: Invalid lot size calculated for %s", symbol);
        return 0.0;
    }
    
    // Check maximum position size based on margin
    double maxLots = CalculateMaxPositionSize(symbol);
    if(maxLots > 0 && lotSize > maxLots)
    {
        PrintFormat("POSITION_ADJUSTED: Reducing lot size from %.3f to %.3f (margin limit)",
                   lotSize, maxLots);
        lotSize = maxLots;
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss for Signal                                  |
//+------------------------------------------------------------------+
double CalculateStopLossForSignal(const string symbol, const bool isBuy)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    double atrBuffer[1];
    double slDistance = 0.0;
    const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrBuffer) >= 1)
    {
        const double symbolATRMultiplier = GetSymbolAdjustedMultiplier(symbol, "ATR_MULTIPLIER");
        
        // Calculate base SL from ATR
        const double atrPriceDistance = atrBuffer[0] * symbolATRMultiplier;
        const double atrPips = (atrPriceDistance / pointValue) / 10.0;
        
        // Get minimum required
        const double minRequiredPips = GetMinimumStopLoss(symbol);
        
        // Use whichever is larger - ATR-based or Minimum
        if(atrPips < minRequiredPips)
        {
            // ATR SL is too small - use minimum
            slDistance = minRequiredPips * pointValue * 10.0;
        }
        else
        {
            // ATR SL is good enough
            slDistance = atrPriceDistance;
        }
        
        // Convert to price distance
        const double currentPrice = isBuy ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : 
            SymbolInfoDouble(symbol, SYMBOL_ASK);
            
        return isBuy ? currentPrice - slDistance : currentPrice + slDistance;
    }
    else
    {
        PrintFormat("ERROR: Failed to get M15 ATR for %s", symbol);
        return 0.0;
    }
}

//+------------------------------------------------------------------+
//| Check Candle Body Requirements                                  |
//+------------------------------------------------------------------+
bool CheckCandleBody(const string symbol, bool &outBullCandle, bool &outBearCandle)
{
    const double open = iOpen(symbol, TradeTF, 1);
    const double close = iClose(symbol, TradeTF, 1);
    
    const double symbolMinBody = GetSymbolAdjustedMultiplier(symbol, "MIN_BODY");
    const double candleBody = MathAbs(close - open) / SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    outBullCandle = (close > open) && (candleBody >= symbolMinBody);
    outBearCandle = (close < open) && (candleBody >= symbolMinBody);
    
    return (outBullCandle || outBearCandle);
}

//+------------------------------------------------------------------+
//| Get Standard Buy Signal                                         |
//| Regular buy signal without ultra-sensitive check               |
//+------------------------------------------------------------------+
bool GetStandardBuySignal(const string symbol, double &outLotSize, double &outStopLoss)
{
    // Check candle body
    bool bullCandle = false, bearCandle = false;
    if(!CheckCandleBody(symbol, bullCandle, bearCandle) || !bullCandle)
        return false;
    
    // Validate trade direction
    bool allowBuy = true, allowSell = true;
    if(!ValidateDirection(symbol, allowBuy, allowSell) || !allowBuy)
        return false;
    
    // Check basic signal conditions
    if(!CheckBasicSignalConditions(symbol, true))
        return false;
    
    // Track signal
    TrackSignal(symbol, "BUY-STANDARD", 70.0);
    
    // Calculate position size and stop loss
    outLotSize = CalculatePositionForSignal(symbol, true);
    outStopLoss = CalculateStopLossForSignal(symbol, true);
    
    return (outLotSize > 0 && outStopLoss > 0);
}

//+------------------------------------------------------------------+
//| Get Standard Sell Signal                                        |
//| Regular sell signal without ultra-sensitive check              |
//+------------------------------------------------------------------+
bool GetStandardSellSignal(const string symbol, double &outLotSize, double &outStopLoss)
{
    // Check candle body
    bool bullCandle = false, bearCandle = false;
    if(!CheckCandleBody(symbol, bullCandle, bearCandle) || !bearCandle)
        return false;
    
    // Validate trade direction
    bool allowBuy = true, allowSell = true;
    if(!ValidateDirection(symbol, allowBuy, allowSell) || !allowSell)
        return false;
    
    // Check basic signal conditions
    if(!CheckBasicSignalConditions(symbol, false))
        return false;
    
    // Track signal
    TrackSignal(symbol, "SELL-STANDARD", 70.0);
    
    // Calculate position size and stop loss
    outLotSize = CalculatePositionForSignal(symbol, false);
    outStopLoss = CalculateStopLossForSignal(symbol, false);
    
    return (outLotSize > 0 && outStopLoss > 0);
}

//+------------------------------------------------------------------+
//| Check Basic Signal Conditions                                   |
//+------------------------------------------------------------------+
bool CheckBasicSignalConditions(const string symbol, const bool isBuy)
{
    // Check momentum
    if(!CheckSignalMomentum(symbol, isBuy))
        return false;
    
    // Check trend alignment
    if(!CheckTrendAlignment(symbol, isBuy))
        return false;
    
    // Check volatility
    if(!CheckVolatilityConditions(symbol))
        return false;
    
    // Check time restrictions
    if(!CheckTradingTime())
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Signal Momentum                                           |
//+------------------------------------------------------------------+
bool CheckSignalMomentum(const string symbol, const bool isBuy)
{
    const double momentum = CalculateTrendMomentum(symbol, isBuy, TradeTF);
    return (momentum >= MinimumMomentumThreshold);
}

//+------------------------------------------------------------------+
//| Check Trend Alignment                                           |
//+------------------------------------------------------------------+
bool CheckTrendAlignment(const string symbol, const bool isBuy)
{
    const double trendScore = CalculateMultiTFAlignment(symbol, isBuy);
    return (trendScore >= MinimumTrendAlignment);
}

//+------------------------------------------------------------------+
//| Check Volatility Conditions                                     |
//+------------------------------------------------------------------+
bool CheckVolatilityConditions(const string symbol)
{
    const double volatility = GetCurrentVolatility(symbol);
    return (volatility >= MinimumVolatility && volatility <= MaximumVolatility);
}

//+------------------------------------------------------------------+
//| Check Trading Time Restrictions - MQL5 Version                  |
//+------------------------------------------------------------------+
bool CheckTradingTime()
{
    // MQL5: Use MqlDateTime structure for better time handling
    MqlDateTime time_struct;
    TimeCurrent(time_struct);  // MQL5: TimeCurrent() with parameter
    
    int currentHour = time_struct.hour;
    
    // Check if within trading hours
    if(currentHour < TradingStartHour || currentHour >= TradingEndHour)
        return false;
    
    // Check for news avoidance
    if(IsHighImpactNewsScheduled())
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Combined Signal (Ultra + Standard)                          |
//+------------------------------------------------------------------+
bool GetCombinedSignal(const string symbol, double &outLotSize, double &outStopLoss, bool &outIsBuy)
{
    double ultraBuyLot, ultraBuySL, ultraSellLot, ultraSellSL;
    double stdBuyLot, stdBuySL, stdSellLot, stdSellSL;
    
    bool ultraBuy = GetUltraBuySignal(symbol, ultraBuyLot, ultraBuySL);
    bool ultraSell = GetUltraSellSignal(symbol, ultraSellLot, ultraSellSL);
    bool stdBuy = GetStandardBuySignal(symbol, stdBuyLot, stdBuySL);
    bool stdSell = GetStandardSellSignal(symbol, stdSellLot, stdSellSL);
    
    // Priority: Ultra signals first
    if(ultraBuy)
    {
        outLotSize = ultraBuyLot;
        outStopLoss = ultraBuySL;
        outIsBuy = true;
        return true;
    }
    else if(ultraSell)
    {
        outLotSize = ultraSellLot;
        outStopLoss = ultraSellSL;
        outIsBuy = false;
        return true;
    }
    // Fallback: Standard signals
    else if(stdBuy)
    {
        outLotSize = stdBuyLot;
        outStopLoss = stdBuySL;
        outIsBuy = true;
        return true;
    }
    else if(stdSell)
    {
        outLotSize = stdSellLot;
        outStopLoss = stdSellSL;
        outIsBuy = false;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Helper Functions                                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get Position Type String                                        |
//+------------------------------------------------------------------+
string GetPositionTypeString(const int positionType)
{
    switch(positionType)
    {
        case POSITION_TYPE_BUY: return "BUY";
        case POSITION_TYPE_SELL: return "SELL";
        case -1: return "NONE";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Clear Divergence Override                                       |
//+------------------------------------------------------------------+
void ClearDivergenceOverride()
{
    divergenceOverride.active = false;
    divergenceOverride.forceBuy = false;
    divergenceOverride.forceSell = false;
    divergenceOverride.reason = "";
    divergenceOverride.activatedTime = 0;
    divergenceOverride.tradeCount = 0;
}

//+------------------------------------------------------------------+
//| Get Current Volatility                                          |
//+------------------------------------------------------------------+
double GetCurrentVolatility(const string symbol)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    double atrBuffer[1];
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrBuffer) >= 1)
    {
        return atrBuffer[0];
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Check High Impact News Scheduled                               |
//+------------------------------------------------------------------+
bool IsHighImpactNewsScheduled()
{
    // Implementation depends on news feed integration
    // This is a placeholder
    return false;
}

//+------------------------------------------------------------------+
//| Get Signal Summary                                              |
//+------------------------------------------------------------------+
string GetSignalSummary(const string symbol)
{
    double buyLot, buySL, sellLot, sellSL;
    bool ultraBuy = GetUltraBuySignal(symbol, buyLot, buySL);
    bool ultraSell = GetUltraSellSignal(symbol, sellLot, sellSL);
    
    return StringFormat("Signal Status for %s | Ultra Buy: %s | Ultra Sell: %s",
                       symbol, ultraBuy ? "AVAILABLE" : "NOT AVAILABLE", 
                       ultraSell ? "AVAILABLE" : "NOT AVAILABLE");
}