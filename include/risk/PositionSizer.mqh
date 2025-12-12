//+------------------------------------------------------------------+
//| PositionSizer.mqh                                               |
//| Risk-Based Position Sizing Module                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../market/News/NewsFilter.mqh"

//+------------------------------------------------------------------+
//| Calculate Progressive Position Size                            |
//| Main position sizing function with progressive scaling         |
//+------------------------------------------------------------------+
double CalculateProgressivePositionSize(const string symbol)
{
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Progressive risk based on account size
    const double riskPercent = GetProgressiveRiskPercent(balance);
    
    // Progressive ATR multiplier based on account size
    const double atrMultiplier = GetProgressiveATRMultiplier(balance);
    
    // Calculate position size with progressive parameters
    return CalculatePositionSizeATRProgressive(symbol, riskPercent, atrMultiplier);
}

//+------------------------------------------------------------------+
//| Manage Aggressive Trailing Stops                               |
//| Advanced trailing stop management with progressive stages     |
//+------------------------------------------------------------------+
void ManageAggressiveTrailing()
{
    static datetime lastStopUpdate = 0;
    
    // Check update frequency
    if(TimeCurrent() - lastStopUpdate < TrailUpdateFrequencySec || !UseTrailingStop)
        return;
    
    lastStopUpdate = TimeCurrent();
    
    // Loop through all positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            const string symbol = PositionGetString(POSITION_SYMBOL);
            const bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            const double currentSL = PositionGetDouble(POSITION_SL);
            const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            const datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            // Get current price
            const double currentPrice = isBuy ? 
                SymbolInfoDouble(symbol, SYMBOL_BID) : 
                SymbolInfoDouble(symbol, SYMBOL_ASK);
            
            // Calculate profit in pips
            const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            const double profitPips = isBuy ? 
                (currentPrice - openPrice) / (point * 10.0) : 
                (openPrice - currentPrice) / (point * 10.0);
            
            const int minutesOpen = int(TimeCurrent() - openTime) / 60;
            
            // 1. Breakeven + Buffer
            if(profitPips >= BreakevenTriggerPips && currentSL != openPrice)
            {
                const double breakevenSL = isBuy ? 
                    (openPrice - (BreakevenPlusPips * point * 10.0)) : 
                    (openPrice + (BreakevenPlusPips * point * 10.0));
                
                // Only move if new SL is better
                if((isBuy && breakevenSL > currentSL) || (!isBuy && breakevenSL < currentSL))
                {
                    if(trade.PositionModify(ticket, breakevenSL, 0))
                    {
                        continue;
                    }
                }
            }
            
            // 2. Check if ready for trailing
            if(minutesOpen < MinMinutesOpen || profitPips < TrailStartPips)
                continue;
            
            // 3. Progressive trailing distances
            double trailDistance = Stage1Distance;
            
            if(profitPips >= Stage3Threshold)
            {
                trailDistance = Stage3Distance;
            }
            else if(profitPips >= Stage2Threshold)
            {
                trailDistance = Stage2Distance;
            }
            
            // 4. Dynamic adjustment (optional)
            if(UseDynamicTrailing)
            {
                const int atrHandle = iCustom(symbol, PERIOD_M15, "Examples\\ATR", 14);
                if(atrHandle != INVALID_HANDLE)
                {
                    double atrValues[1];
                    if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) > 0)
                    {
                        const double atrPips = atrValues[0] / (point * 10.0);
                        double dynamicDistance = atrPips * ATRMultiplier;
                        
                        // Use dynamic distance if it's tighter than current
                        if(dynamicDistance < trailDistance)
                        {
                            trailDistance = dynamicDistance;
                        }
                        
                        // Apply maximum limit
                        trailDistance = MathMin(trailDistance, MaxTrailDistance);
                    }
                    IndicatorRelease(atrHandle);
                }
            }
            
            // 5. Calculate new stop loss
            double newSL = isBuy ? 
                (currentPrice - (trailDistance * point * 10.0)) : 
                (currentPrice + (trailDistance * point * 10.0));
            
            // 6. Safety checks
            const double minSL = isBuy ? 
                (openPrice - (BreakevenPlusPips * point * 10.0)) : 
                (openPrice + (BreakevenPlusPips * point * 10.0));
            
            if((isBuy && newSL < minSL) || (!isBuy && newSL > minSL))
            {
                newSL = minSL;
            }
            
            // Never move SL into loss
            if((isBuy && newSL < openPrice) || (!isBuy && newSL > openPrice))
            {
                newSL = openPrice;
            }
            
            // 7. Apply trailing stop
            const double minMovePips = 5.0;
            const double currentDiff = MathAbs(currentPrice - currentSL) / (point * 10.0);
            const double newDiff = MathAbs(currentPrice - newSL) / (point * 10.0);
            
            if((isBuy && newSL > currentSL && (newSL - currentSL) >= (minMovePips * point * 10.0)) ||
               (!isBuy && newSL < currentSL && (currentSL - newSL) >= (minMovePips * point * 10.0)))
            {
                if(trade.PositionModify(ticket, newSL, 0))
                {
                    const double lockedProfit = isBuy ? 
                        (newSL - openPrice) / (point * 10.0) : 
                        (openPrice - newSL) / (point * 10.0);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Position Size with ATR Progressive                   |
//+------------------------------------------------------------------+
double CalculatePositionSizeATRProgressive(const string symbol, const double riskPercent, 
                                          const double atrMultiplier)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return 0.0;
    
    double atrValue[1];
    double positionSize = 0.0;
    
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
    {
        const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // Check if ATR value is reasonable
        if(atrValue[0] < 0.01)
        {
            atrValue[0] = GetMinimumStopLoss(symbol) * point * 10.0;
        }
        
        double stopLossPoints = (atrValue[0] * atrMultiplier) / point;
        double stopLossPips = stopLossPoints / 10.0;
        
        // Enforce minimum stop loss
        const double minStopLoss = GetMinimumStopLoss(symbol);
        if(stopLossPips < minStopLoss)
        {
            stopLossPips = minStopLoss;
        }
        
        // Maximum stop loss to prevent tiny lots
        const double maxStopLoss = 100.0;
        if(stopLossPips > maxStopLoss)
        {
            stopLossPips = maxStopLoss;
        }
        
        // Get tick value for metals
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        if(tickValue <= 0)
        {
            if(symbol == "XAUUSD" || symbol == "XAGUSD")
                tickValue = 0.01;
            else
                tickValue = 0.0001;
        }
        
        // Correct calculation
        const double valuePerPip = tickValue * 10.0;
        const double riskAmount = balance * (riskPercent / 100.0);
        
        if(stopLossPips > 0 && valuePerPip > 0)
        {
            positionSize = riskAmount / (stopLossPips * valuePerPip);
        }
        
        // Apply minimum lot size
        const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        const double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        
        if(positionSize < minLot)
        {
            positionSize = minLot;
        }
        
        // Apply account-based caps
        positionSize = ApplyProgressiveLotCaps(symbol, positionSize, balance);
        
        // Final rounding
        const double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        if(stepLot > 0)
            positionSize = MathRound(positionSize / stepLot) * stepLot;
            
        positionSize = MathMin(positionSize, maxLot);
    }
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Calculate Maximum Position Size                                 |
//+------------------------------------------------------------------+
double CalculateMaxPositionSize(const string symbol)
{
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    const double marginPerLot = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
    
    if(marginPerLot > 0)
        return freeMargin / marginPerLot;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get Dynamic Trailing Distance                                   |
//+------------------------------------------------------------------+
double GetDynamicTrailingDistance(const string symbol)
{
    if(!UseDynamicTrailing) return Above1000TrailDistance;
    
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return Above1000TrailDistance;
    
    double atrValue[1];
    double distance = Above1000TrailDistance;
    
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
    {
        const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        const double atrPips = atrValue[0] / (point * 10.0);
        distance = MathMax(Above1000TrailDistance, atrPips * 1.5);
        
        // Safety cap
        distance = MathMin(distance, 300.0);
    }
    
    return distance;
}

//+------------------------------------------------------------------+
//| Get Progressive Risk Percent                                   |
//+------------------------------------------------------------------+
double GetProgressiveRiskPercent(const double balance)
{
    if(balance < 500.0)
        return 2.0;
    else if(balance < 1000.0)
        return 3.0;
    else if(balance < 5000.0)
        return 4.0;
    else
        return 5.0;
}

//+------------------------------------------------------------------+
//| Get Progressive ATR Multiplier                                 |
//+------------------------------------------------------------------+
double GetProgressiveATRMultiplier(const double balance)
{
    if(balance < 500.0)
        return 2.5;
    else if(balance < 1000.0)
        return 2.0;
    else if(balance < 5000.0)
        return 1.8;
    else
        return 1.5;
}

//+------------------------------------------------------------------+
//| Apply Progressive Lot Caps                                     |
//+------------------------------------------------------------------+
double ApplyProgressiveLotCaps(const string symbol, const double lotSize, const double balance)
{
    double maxLot = 0.0;
    
    // Progressive caps based on account size
    if(balance < 500.0)
        maxLot = (symbol == "XAUUSD" || symbol == "XAGUSD") ? 0.05 : 0.10;
    else if(balance < 1000.0)
        maxLot = (symbol == "XAUUSD" || symbol == "XAGUSD") ? 0.10 : 0.25;
    else if(balance < 5000.0)
        maxLot = (symbol == "XAUUSD" || symbol == "XAGUSD") ? 0.25 : 0.50;
    else
        maxLot = (symbol == "XAUUSD" || symbol == "XAGUSD") ? 0.50 : 1.00;
    
    if(lotSize > maxLot)
    {
        PrintFormat("PROGRESSIVE_CAP: Reducing %s from %.3f to %.3f lots (balance: $%.2f)",
                   symbol, lotSize, maxLot, balance);
        return maxLot;
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Get Appropriate ATR Timeframe                                   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetAppropriateATRTimeframe(const string symbol)
{
    // Metals need longer timeframe ATR for proper stops
    if(IsSilver(symbol) || symbol == "XAUUSD" || symbol == "XAGUSD")
        return PERIOD_M15;
    else
        return PERIOD_M5;
}

//+------------------------------------------------------------------+
//| Get Minimum Stop Loss                                           |
//+------------------------------------------------------------------+
double GetMinimumStopLoss(const string symbol)
{
    if(symbol == "XAUUSD" || symbol == "XAGUSD")
        return 80.0;
    else if(symbol == "EURUSD" || symbol == "GBPUSD")
        return 30.0;
    else
        return 20.0;
}

//+------------------------------------------------------------------+
//| Calculate Position Size by Fixed Risk                          |
//+------------------------------------------------------------------+
double CalculatePositionSizeFixedRisk(const string symbol, const double stopLossPips)
{
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    const double riskPercent = GetProgressiveRiskPercent(balance);
    const double riskAmount = balance * (riskPercent / 100.0);
    
    const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double valuePerPip = tickValue * 10.0;
    
    if(tickValue <= 0)
    {
        if(symbol == "XAUUSD" || symbol == "XAGUSD")
            valuePerPip = 10.0;
        else
            valuePerPip = 1.0;
    }
    
    if(stopLossPips > 0 && valuePerPip > 0)
    {
        double positionSize = riskAmount / (stopLossPips * valuePerPip);
        
        // Apply caps and rounding
        positionSize = ApplyPositionSizeLimits(symbol, positionSize);
        
        return positionSize;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Apply Position Size Limits                                      |
//+------------------------------------------------------------------+
double ApplyPositionSizeLimits(const string symbol, const double positionSize)
{
    const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    const double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    const double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    double result = positionSize;
    
    // Ensure minimum lot size
    if(result < minLot)
        result = minLot;
    
    // Apply step rounding
    if(stepLot > 0)
        result = MathRound(result / stepLot) * stepLot;
    
    // Ensure maximum lot size
    if(result > maxLot)
        result = maxLot;
    
    // Apply margin-based maximum
    const double marginMax = CalculateMaxPositionSize(symbol);
    if(marginMax > 0 && result > marginMax)
        result = marginMax;
    
    return result;
}

//+------------------------------------------------------------------+
//| Get Optimal Stop Loss Distance                                 |
//+------------------------------------------------------------------+
double GetOptimalStopLossDistance(const string symbol, const ENUM_TIMEFRAMES timeframe = PERIOD_M15)
{
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex == -1) return GetMinimumStopLoss(symbol);
    
    double atrValue[1];
    if(CopyBuffer(atr_handles_M15[symbolIndex], 0, 0, 1, atrValue) >= 1)
    {
        const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        const double atrPips = atrValue[0] / (point * 10.0);
        const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        const double atrMultiplier = GetProgressiveATRMultiplier(balance);
        
        double optimalDistance = atrPips * atrMultiplier;
        
        // Ensure minimum stop loss
        const double minStopLoss = GetMinimumStopLoss(symbol);
        if(optimalDistance < minStopLoss)
            optimalDistance = minStopLoss;
        
        return optimalDistance;
    }
    
    return GetMinimumStopLoss(symbol);
}

//+------------------------------------------------------------------+
//| Calculate Risk per Trade                                       |
//+------------------------------------------------------------------+
double CalculateRiskPerTrade(const string symbol, const double lotSize, const double stopLossPips)
{
    const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double valuePerPip = tickValue * 10.0;
    
    if(tickValue <= 0)
    {
        if(symbol == "XAUUSD" || symbol == "XAGUSD")
            valuePerPip = 10.0;
        else
            valuePerPip = 1.0;
    }
    
    const double riskAmount = stopLossPips * valuePerPip * lotSize;
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance > 0)
        return (riskAmount / balance) * 100.0;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Validate Position Size                                         |
//+------------------------------------------------------------------+
bool ValidatePositionSize(const string symbol, const double lotSize)
{
    if(lotSize <= 0)
        return false;
    
    const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    const double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if(lotSize < minLot || lotSize > maxLot)
        return false;
    
    const double maxMarginLot = CalculateMaxPositionSize(symbol);
    if(maxMarginLot > 0 && lotSize > maxMarginLot)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Position Size Summary                                       |
//+------------------------------------------------------------------+
string GetPositionSizeSummary(const string symbol)
{
    const double progressiveSize = CalculateProgressivePositionSize(symbol);
    const double maxMarginSize = CalculateMaxPositionSize(symbol);
    const double optimalSL = GetOptimalStopLossDistance(symbol);
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    const double riskPercent = GetProgressiveRiskPercent(balance);
    
    const double riskAmount = CalculateRiskPerTrade(symbol, progressiveSize, optimalSL);
    
    return StringFormat("Position Size Summary for %s:\n" +
                       "  Progressive Size: %.3f lots\n" +
                       "  Max Margin Size: %.3f lots\n" +
                       "  Optimal SL: %.1f pips\n" +
                       "  Account Risk: %.1f%%\n" +
                       "  Trade Risk: $%.2f (%.2f%% of balance)\n" +
                       "  Valid: %s",
                       symbol,
                       progressiveSize,
                       maxMarginSize,
                       optimalSL,
                       riskPercent,
                       riskAmount * balance / 100.0,
                       riskAmount,
                       ValidatePositionSize(symbol, progressiveSize) ? "YES" : "NO");
}

//+------------------------------------------------------------------+
//| Calculate Martingale Position Size                             |
//+------------------------------------------------------------------+
double CalculateMartingalePositionSize(const string symbol, const int consecutiveLosses)
{
    if(consecutiveLosses <= 0)
        return CalculateProgressivePositionSize(symbol);
    
    const double baseSize = CalculateProgressivePositionSize(symbol);
    const double martingaleMultiplier = MathPow(2.0, consecutiveLosses);
    const double martingaleSize = baseSize * martingaleMultiplier;
    
    // Apply safety limits
    return ApplyMartingaleLimits(symbol, martingaleSize, consecutiveLosses);
}

//+------------------------------------------------------------------+
//| Apply Martingale Limits                                        |
//+------------------------------------------------------------------+
double ApplyMartingaleLimits(const string symbol, const double martingaleSize, const int consecutiveLosses)
{
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    const double maxRiskPercent = 10.0;  // Maximum 10% of balance for martingale
    
    // Calculate maximum allowed martingale size based on risk
    const double maxRiskAmount = balance * (maxRiskPercent / 100.0);
    const double optimalSL = GetOptimalStopLossDistance(symbol);
    const double tickValue = GetSymbolTickValue(symbol);
    const double maxSizeByRisk = maxRiskAmount / (optimalSL * tickValue);
    
    // Apply both risk and margin limits
    double limitedSize = MathMin(martingaleSize, maxSizeByRisk);
    limitedSize = ApplyPositionSizeLimits(symbol, limitedSize);
    
    // Apply maximum consecutive losses limit
    const int maxConsecutiveLosses = 5;
    if(consecutiveLosses >= maxConsecutiveLosses)
    {
        PrintFormat("MARTINGALE_LIMIT: Maximum consecutive losses (%d) reached for %s", 
                   maxConsecutiveLosses, symbol);
        return CalculateProgressivePositionSize(symbol);  // Reset to base size
    }
    
    return limitedSize;
}