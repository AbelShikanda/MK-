//+------------------------------------------------------------------+
//| StopLossManager.mqh                                             |
//| Stop Loss and Take Profit Calculations Module                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/GlobalVariables.mqh"
#include "../../utils/SymbolUtils.mqh"
#include "../../utils/IndicatorUtils.mqh"

//+------------------------------------------------------------------+
//| Get Average Stop Loss from Existing Positions                   |
//| Calculates weighted average SL for existing positions          |
//+------------------------------------------------------------------+
double GetAverageStopLoss(const string symbol, const bool isBuy)
{
    double totalSL = 0.0;
    double totalVolume = 0.0;
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                const ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if((isBuy && currentType == POSITION_TYPE_BUY) ||
                   (!isBuy && currentType == POSITION_TYPE_SELL))
                {
                    const double positionVolume = PositionGetDouble(POSITION_VOLUME);
                    const double positionSL = PositionGetDouble(POSITION_SL);
                    
                    totalSL += positionSL * positionVolume;
                    totalVolume += positionVolume;
                    count++;
                }
            }
        }
    }
    
    if(count > 0 && totalVolume > 0)
    {
        const double weightedAverageSL = totalSL / totalVolume;
        PrintFormat("Average Stop Loss for %s (%s): %.5f (weighted by volume)",
                   symbol, isBuy ? "BUY" : "SELL", weightedAverageSL);
        return weightedAverageSL;
    }
    
    // If no existing positions, calculate new stop loss
    PrintFormat("No existing positions found for %s, calculating default stop loss",
               symbol);
    return CalculateDefaultStopLoss(symbol, isBuy);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                           |
//| Calculates take profit based on risk-reward ratio              |
//+------------------------------------------------------------------+
double CalculateTakeProfit(const string symbol, const bool isBuy, const double stopLoss)
{
    const double entryPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Get risk-reward ratio from inputs
    double riskReward = RiskRewardRatio;
    if(riskReward <= 0) riskReward = 1.5;  // Default 1:1.5
    
    // Calculate stop distance in price terms
    const double stopDistance = MathAbs(entryPrice - stopLoss);
    
    // Calculate take profit distance
    const double takeProfitDistance = stopDistance * riskReward;
    
    // Calculate take profit price
    const double takeProfit = isBuy ? 
        entryPrice + takeProfitDistance : 
        entryPrice - takeProfitDistance;
    
    // Calculate and display RR information
    const double stopPips = stopDistance / (point * 10.0);
    const double tpPips = takeProfitDistance / (point * 10.0);
    
    PrintFormat("Take Profit Calculation for %s (%s):",
               symbol, isBuy ? "BUY" : "SELL");
    PrintFormat("  Entry: %.5f, Stop Loss: %.5f", entryPrice, stopLoss);
    PrintFormat("  Stop Distance: %.1f pips, TP Distance: %.1f pips", stopPips, tpPips);
    PrintFormat("  Risk-Reward Ratio: 1:%.1f", riskReward);
    PrintFormat("  Take Profit: %.5f", takeProfit);
    
    return takeProfit;
}

//+------------------------------------------------------------------+
//| Calculate Default Stop Loss                                     |
//| Calculates ATR-based stop loss with minimum enforcement        |
//+------------------------------------------------------------------+
double CalculateDefaultStopLoss(const string symbol, const bool isBuy)
{
    const double entryPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double minStopLossPips = GetMinimumStopLoss(symbol);
    
    // Get ATR-based stop loss
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex != -1)
    {
        double atrValue[1];
        if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
        {
            const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            const double atrMultiplier = GetProgressiveATRMultiplier(balance);
            const double atrStop = atrValue[0] * atrMultiplier;
            
            // Convert to pips and ensure minimum
            double atrStopPips = atrStop / (point * 10.0);
            
            PrintFormat("ATR-based Stop Loss: %.1f pips (ATR: %.3f, Multiplier: %.1f)",
                       atrStopPips, atrValue[0], atrMultiplier);
            
            // Enforce minimum stop loss
            if(atrStopPips < minStopLossPips)
            {
                PrintFormat("Enforcing minimum stop loss: %.1f pips (ATR was %.1f pips)",
                           minStopLossPips, atrStopPips);
                atrStopPips = minStopLossPips;
            }
            
            const double stopDistance = atrStopPips * point * 10.0;
            
            const double stopLoss = isBuy ? 
                entryPrice - stopDistance : 
                entryPrice + stopDistance;
            
            PrintFormat("Default Stop Loss for %s (%s): %.5f (%.1f pips)",
                       symbol, isBuy ? "BUY" : "SELL", stopLoss, atrStopPips);
            
            return stopLoss;
        }
    }
    
    // Fallback: fixed stop loss based on minimum
    PrintFormat("Using fallback stop loss for %s (minimum %.1f pips)", 
               symbol, minStopLossPips);
    
    const double stopDistance = minStopLossPips * point * 10.0;
    const double stopLoss = isBuy ? 
        entryPrice - stopDistance : 
        entryPrice + stopDistance;
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss                                     |
//| Advanced stop loss with multiple calculation methods           |
//+------------------------------------------------------------------+
double CalculateDynamicStopLoss(const string symbol, const bool isBuy, 
                               const ENUM_STOP_LOSS_METHOD method = SL_ATR_BASED)
{
    const double entryPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double stopLossPips = 0.0;
    string methodDescription = "";
    
    switch(method)
    {
        case SL_ATR_BASED:
            stopLossPips = CalculateATRStopLoss(symbol);
            methodDescription = "ATR-based";
            break;
            
        case SL_PERCENTAGE_BASED:
            stopLossPips = CalculatePercentageStopLoss(symbol, entryPrice);
            methodDescription = "Percentage-based";
            break;
            
        case SL_SUPPORT_RESISTANCE:
            stopLossPips = CalculateSupportResistanceStopLoss(symbol, isBuy, entryPrice);
            methodDescription = "Support/Resistance-based";
            break;
            
        case SL_VOLATILITY_BASED:
            stopLossPips = CalculateVolatilityStopLoss(symbol);
            methodDescription = "Volatility-based";
            break;
            
        default:
            stopLossPips = GetMinimumStopLoss(symbol);
            methodDescription = "Minimum default";
    }
    
    // Ensure minimum stop loss
    const double minStopLossPips = GetMinimumStopLoss(symbol);
    if(stopLossPips < minStopLossPips)
    {
        PrintFormat("Adjusting %s stop loss from %.1f to minimum %.1f pips",
                   methodDescription, stopLossPips, minStopLossPips);
        stopLossPips = minStopLossPips;
    }
    
    // Calculate stop loss price
    const double stopDistance = stopLossPips * point * 10.0;
    const double stopLoss = isBuy ? 
        entryPrice - stopDistance : 
        entryPrice + stopDistance;
    
    PrintFormat("Dynamic Stop Loss for %s (%s): %.5f (%.1f pips, %s)",
               symbol, isBuy ? "BUY" : "SELL", stopLoss, stopLossPips, methodDescription);
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate ATR-based Stop Loss                                   |
//+------------------------------------------------------------------+
double CalculateATRStopLoss(const string symbol)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return GetMinimumStopLoss(symbol);
    
    double atrValue[1];
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
    {
        const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        const double atrMultiplier = GetProgressiveATRMultiplier(balance);
        
        const double atrPips = atrValue[0] / (point * 10.0);
        const double stopLossPips = atrPips * atrMultiplier;
        
        return stopLossPips;
    }
    
    return GetMinimumStopLoss(symbol);
}

//+------------------------------------------------------------------+
//| Calculate Percentage-based Stop Loss                            |
//+------------------------------------------------------------------+
double CalculatePercentageStopLoss(const string symbol, const double entryPrice)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double percentage = 0.01;  // 1% stop loss
    
    // Calculate price distance for 1% move
    const double priceDistance = entryPrice * percentage;
    const double stopLossPips = priceDistance / (point * 10.0);
    
    return stopLossPips;
}

//+------------------------------------------------------------------+
//| Calculate Support/Resistance Stop Loss                          |
//+------------------------------------------------------------------+
double CalculateSupportResistanceStopLoss(const string symbol, const bool isBuy, 
                                         const double entryPrice)
{
    // This is a simplified version - would integrate with LevelAnalyzer
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // For buys, stop below recent swing low
    // For sells, stop above recent swing high
    const double defaultDistance = 30.0;  // Default 30 pips
    double stopLossPips = defaultDistance;
    
    // Look for recent swing points
    const int lookbackBars = 20;
    
    if(isBuy)
    {
        // Find recent swing low for buy stop loss
        double swingLow = entryPrice;
        for(int i = 1; i <= lookbackBars; i++)
        {
            const double low = iLow(symbol, PERIOD_H1, i);
            if(low < swingLow) swingLow = low;
        }
        
        const double distance = (entryPrice - swingLow) / (point * 10.0);
        if(distance > 10.0 && distance < 100.0)  // Reasonable range
            stopLossPips = distance + 10.0;  // Add buffer
    }
    else
    {
        // Find recent swing high for sell stop loss
        double swingHigh = entryPrice;
        for(int i = 1; i <= lookbackBars; i++)
        {
            const double high = iHigh(symbol, PERIOD_H1, i);
            if(high > swingHigh) swingHigh = high;
        }
        
        const double distance = (swingHigh - entryPrice) / (point * 10.0);
        if(distance > 10.0 && distance < 100.0)  // Reasonable range
            stopLossPips = distance + 10.0;  // Add buffer
    }
    
    return stopLossPips;
}

//+------------------------------------------------------------------+
//| Calculate Volatility-based Stop Loss                            |
//+------------------------------------------------------------------+
double CalculateVolatilityStopLoss(const string symbol)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Calculate recent volatility (standard deviation)
    const int period = 20;
    double closes[];
    ArrayResize(closes, period);
    
    if(CopyClose(symbol, PERIOD_H1, 0, period, closes) < period)
        return GetMinimumStopLoss(symbol);
    
    // Calculate standard deviation
    double sum = 0.0;
    for(int i = 0; i < period; i++) sum += closes[i];
    const double mean = sum / period;
    
    double variance = 0.0;
    for(int i = 0; i < period; i++)
        variance += MathPow(closes[i] - mean, 2);
    variance /= period;
    
    const double stdDev = MathSqrt(variance);
    const double stdDevPips = stdDev / (point * 10.0);
    
    // Use 2x standard deviation for stop loss
    const double stopLossPips = stdDevPips * 2.0;
    
    return MathMax(stopLossPips, GetMinimumStopLoss(symbol));
}

//+------------------------------------------------------------------+
//| Calculate Adaptive Take Profit                                  |
//| Advanced take profit with multiple methods                     |
//+------------------------------------------------------------------+
double CalculateAdaptiveTakeProfit(const string symbol, const bool isBuy, 
                                  const double stopLoss, const double entryPrice,
                                  const ENUM_TAKE_PROFIT_METHOD method = TP_RISK_REWARD)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double takeProfitPips = 0.0;
    string methodDescription = "";
    
    switch(method)
    {
        case TP_RISK_REWARD:
            takeProfitPips = CalculateRiskRewardTakeProfit(symbol, entryPrice, stopLoss);
            methodDescription = "Risk-Reward based";
            break;
            
        case TP_ATR_BASED:
            takeProfitPips = CalculateATRTakeProfit(symbol, entryPrice, stopLoss);
            methodDescription = "ATR-based";
            break;
            
        case TP_RESISTANCE_SUPPORT:
            takeProfitPips = CalculateResistanceSupportTakeProfit(symbol, isBuy, entryPrice);
            methodDescription = "Resistance/Support based";
            break;
            
        case TP_TRAILING_ADJUST:
            takeProfitPips = CalculateTrailingTakeProfit(symbol, isBuy, entryPrice, stopLoss);
            methodDescription = "Trailing adjusted";
            break;
            
        default:
            takeProfitPips = CalculateRiskRewardTakeProfit(symbol, entryPrice, stopLoss);
            methodDescription = "Default Risk-Reward";
    }
    
    // Calculate take profit price
    const double tpDistance = takeProfitPips * point * 10.0;
    const double takeProfit = isBuy ? 
        entryPrice + tpDistance : 
        entryPrice - tpDistance;
    
    PrintFormat("Adaptive Take Profit for %s (%s): %.5f (%.1f pips, %s)",
               symbol, isBuy ? "BUY" : "SELL", takeProfit, takeProfitPips, methodDescription);
    
    return takeProfit;
}

//+------------------------------------------------------------------+
//| Calculate Risk-Reward Take Profit                               |
//+------------------------------------------------------------------+
double CalculateRiskRewardTakeProfit(const string symbol, const double entryPrice, 
                                    const double stopLoss)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double riskPips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
    
    // Get risk-reward ratio
    double riskReward = RiskRewardRatio;
    if(riskReward <= 0) riskReward = 1.5;
    
    const double takeProfitPips = riskPips * riskReward;
    
    // Ensure minimum profit target
    const double minProfitPips = 15.0;
    return MathMax(takeProfitPips, minProfitPips);
}

//+------------------------------------------------------------------+
//| Calculate ATR-based Take Profit                                 |
//+------------------------------------------------------------------+
double CalculateATRTakeProfit(const string symbol, const double entryPrice, 
                             const double stopLoss)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return CalculateRiskRewardTakeProfit(symbol, entryPrice, stopLoss);
    
    double atrValue[1];
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
    {
        const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        const double atrPips = atrValue[0] / (point * 10.0);
        
        // Use 2x ATR for take profit
        const double takeProfitPips = atrPips * 2.0;
        
        // Ensure minimum profit
        const double minProfitPips = 20.0;
        return MathMax(takeProfitPips, minProfitPips);
    }
    
    return CalculateRiskRewardTakeProfit(symbol, entryPrice, stopLoss);
}

//+------------------------------------------------------------------+
//| Calculate Resistance/Support Take Profit                        |
//+------------------------------------------------------------------+
double CalculateResistanceSupportTakeProfit(const string symbol, const bool isBuy,
                                           const double entryPrice)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Look for nearby resistance/support levels
    const int lookbackBars = 50;
    double targetPrice = entryPrice;
    
    if(isBuy)
    {
        // Find nearby resistance for take profit
        double resistance = entryPrice;
        for(int i = 1; i <= lookbackBars; i++)
        {
            const double high = iHigh(symbol, PERIOD_H1, i);
            if(high > entryPrice && high < resistance)
                resistance = high;
        }
        
        if(resistance > entryPrice)
            targetPrice = resistance - (10.0 * point * 10.0);  // 10 pips below resistance
        else
            targetPrice = entryPrice + (50.0 * point * 10.0);  // Default 50 pips
    }
    else
    {
        // Find nearby support for take profit
        double support = entryPrice;
        for(int i = 1; i <= lookbackBars; i++)
        {
            const double low = iLow(symbol, PERIOD_H1, i);
            if(low < entryPrice && low > support)
                support = low;
        }
        
        if(support < entryPrice)
            targetPrice = support + (10.0 * point * 10.0);  // 10 pips above support
        else
            targetPrice = entryPrice - (50.0 * point * 10.0);  // Default 50 pips
    }
    
    const double takeProfitPips = MathAbs(targetPrice - entryPrice) / (point * 10.0);
    
    return MathMax(takeProfitPips, 20.0);  // Minimum 20 pips
}

//+------------------------------------------------------------------+
//| Calculate Trailing Take Profit                                  |
//+------------------------------------------------------------------+
double CalculateTrailingTakeProfit(const string symbol, const bool isBuy,
                                  const double entryPrice, const double stopLoss)
{
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double riskPips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
    
    // Progressive take profit based on market conditions
    const double volatility = CalculateCurrentVolatility(symbol);
    double multiplier = 1.5;  // Base multiplier
    
    // Adjust based on volatility
    if(volatility > 0.002)  // High volatility
        multiplier = 1.2;    // Tighter TP
    else if(volatility < 0.0005)  // Low volatility
        multiplier = 2.0;    // Wider TP
    
    const double takeProfitPips = riskPips * multiplier;
    
    return MathMax(takeProfitPips, 20.0);  // Minimum 20 pips
}

//+------------------------------------------------------------------+
//| Calculate Current Volatility                                    |
//+------------------------------------------------------------------+
double CalculateCurrentVolatility(const string symbol)
{
    const int period = 10;
    double highs[], lows[];
    ArrayResize(highs, period);
    ArrayResize(lows, period);
    
    if(CopyHigh(symbol, PERIOD_M15, 0, period, highs) < period ||
       CopyLow(symbol, PERIOD_M15, 0, period, lows) < period)
        return 0.001;  // Default medium volatility
    
    double totalRange = 0.0;
    for(int i = 0; i < period; i++)
        totalRange += (highs[i] - lows[i]);
    
    const double avgRange = totalRange / period;
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    return avgRange / currentPrice;  // Return as percentage of price
}

//+------------------------------------------------------------------+
//| Get Stop Loss and Take Profit Summary                           |
//+------------------------------------------------------------------+
string GetSLTPSummary(const string symbol, const bool isBuy, const double entryPrice)
{
    const double defaultStopLoss = CalculateDefaultStopLoss(symbol, isBuy);
    const double defaultTakeProfit = CalculateTakeProfit(symbol, isBuy, defaultStopLoss);
    
    const double dynamicStopLoss = CalculateDynamicStopLoss(symbol, isBuy, SL_ATR_BASED);
    const double adaptiveTakeProfit = CalculateAdaptiveTakeProfit(symbol, isBuy, dynamicStopLoss, entryPrice, TP_RISK_REWARD);
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double defaultSLPips = MathAbs(entryPrice - defaultStopLoss) / (point * 10.0);
    const double defaultTPPips = MathAbs(defaultTakeProfit - entryPrice) / (point * 10.0);
    const double dynamicSLPips = MathAbs(entryPrice - dynamicStopLoss) / (point * 10.0);
    const double adaptiveTPPips = MathAbs(adaptiveTakeProfit - entryPrice) / (point * 10.0);
    
    return StringFormat("SL/TP Summary for %s (%s):\n" +
                       "  Entry Price: %.5f\n" +
                       "  Default SL: %.5f (%.1f pips)\n" +
                       "  Default TP: %.5f (%.1f pips) - RR: 1:%.1f\n" +
                       "  Dynamic SL: %.5f (%.1f pips)\n" +
                       "  Adaptive TP: %.5f (%.1f pips) - RR: 1:%.1f",
                       symbol, isBuy ? "BUY" : "SELL", entryPrice,
                       defaultStopLoss, defaultSLPips,
                       defaultTakeProfit, defaultTPPips, defaultTPPips / defaultSLPips,
                       dynamicStopLoss, dynamicSLPips,
                       adaptiveTakeProfit, adaptiveTPPips, adaptiveTPPips / dynamicSLPips);
}

//+------------------------------------------------------------------+
//| Validate Stop Loss and Take Profit                              |
//+------------------------------------------------------------------+
bool ValidateSLTP(const string symbol, const bool isBuy, const double entryPrice,
                 const double stopLoss, const double takeProfit)
{
    if(stopLoss <= 0 || takeProfit <= 0)
        return false;
    
    const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double minStopLoss = GetMinimumStopLoss(symbol);
    const double stopLossPips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
    
    if(stopLossPips < minStopLoss)
    {
        PrintFormat("Stop Loss validation failed: %.1f pips < minimum %.1f pips",
                   stopLossPips, minStopLoss);
        return false;
    }
    
    // Check if take profit is in the right direction
    if((isBuy && takeProfit <= entryPrice) || (!isBuy && takeProfit >= entryPrice))
    {
        Print("Take Profit validation failed: TP in wrong direction");
        return false;
    }
    
    // Check minimum profit
    const double takeProfitPips = MathAbs(takeProfit - entryPrice) / (point * 10.0);
    const double minProfitPips = 10.0;
    
    if(takeProfitPips < minProfitPips)
    {
        PrintFormat("Take Profit validation failed: %.1f pips < minimum %.1f pips",
                   takeProfitPips, minProfitPips);
        return false;
    }
    
    // Check risk-reward ratio
    const double riskReward = takeProfitPips / stopLossPips;
    const double minRiskReward = 1.0;
    
    if(riskReward < minRiskReward)
    {
        PrintFormat("Risk-Reward validation failed: 1:%.1f < minimum 1:%.1f",
                   riskReward, minRiskReward);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Enumerations                                                    |
//+------------------------------------------------------------------+
enum ENUM_STOP_LOSS_METHOD
{
    SL_ATR_BASED,              // ATR-based stop loss
    SL_PERCENTAGE_BASED,       // Percentage-based stop loss
    SL_SUPPORT_RESISTANCE,     // Support/resistance based
    SL_VOLATILITY_BASED        // Volatility-based
};

enum ENUM_TAKE_PROFIT_METHOD
{
    TP_RISK_REWARD,           // Risk-reward ratio based
    TP_ATR_BASED,             // ATR-based take profit
    TP_RESISTANCE_SUPPORT,    // Resistance/support based
    TP_TRAILING_ADJUST        // Trailing adjusted
};