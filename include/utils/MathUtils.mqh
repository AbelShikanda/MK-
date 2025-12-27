//+------------------------------------------------------------------+
//| Math Utilities - Calculations and Conversions                  |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"


// ============ PRICE AND PIP CONVERSIONS ============

//+------------------------------------------------------------------+
//| PipsToPrice - Convert pips to price value                       |
//+------------------------------------------------------------------+
double PipsToPrice(string symbol, double pips)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // For 5-digit brokers, 1 pip = 10 points
    // For 4-digit brokers, 1 pip = 1 point
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
    
    return pips * pipValue;
}

//+------------------------------------------------------------------+
//| PriceToPips - Convert price difference to pips                  |
//+------------------------------------------------------------------+
double PriceToPips(string symbol, double price)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // For 5-digit brokers, 1 pip = 10 points
    // For 4-digit brokers, 1 pip = 1 point
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
    
    if(pipValue != 0)
        return price / pipValue;
    
    return 0;
}

// ============ POSITION CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculatePositionRisk - Calculate risk amount for a position    |
//+------------------------------------------------------------------+
double CalculatePositionRisk(string symbol, double entryPrice, 
                           double stopLoss, double lotSize)
{
    // Get the tick value for the symbol (value per 1 lot per 1 point)
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Calculate stop distance in points
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double points = stopDistance / point;
    
    // Calculate risk: points × tick value × lot size
    return points * tickValue * lotSize;
}

//+------------------------------------------------------------------+
//| CalculateRiskRewardRatio - Calculate R:R for a position         |
//+------------------------------------------------------------------+
double CalculateRiskRewardRatio(double entryPrice, double stopLoss, 
                              double takeProfit)
{
    double risk = MathAbs(entryPrice - stopLoss);
    double reward = MathAbs(takeProfit - entryPrice);
    
    if(risk == 0)
        return 0;
    
    return reward / risk;
}

// ============ PERCENTAGE CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculatePercentageChange - Calculate % change between values   |
//+------------------------------------------------------------------+
double CalculatePercentageChange(double oldValue, double newValue)
{
    if(oldValue == 0)
        return 0;
    
    return ((newValue - oldValue) / oldValue) * 100;
}

//+------------------------------------------------------------------+
//| CalculateValueFromPercentage - Get value from percentage        |
//+------------------------------------------------------------------+
double CalculateValueFromPercentage(double baseValue, double percentage)
{
    return baseValue * (percentage / 100);
}

//+------------------------------------------------------------------+
//| CalculatePercentageOfValue - Get percentage of value            |
//+------------------------------------------------------------------+
double CalculatePercentageOfValue(double part, double whole)
{
    if(whole == 0)
        return 0;
    
    return (part / whole) * 100;
}

// ============ AVERAGE CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateSimpleMovingAverage - Calculate SMA of values          |
//+------------------------------------------------------------------+
double CalculateSimpleMovingAverage(const double &values[], int period)
{
    if(ArraySize(values) < period || period <= 0)
        return 0;
    
    double sum = 0;
    int count = MathMin(period, ArraySize(values));
    
    for(int i = 0; i < count; i++)
        sum += values[i];
    
    return sum / count;
}

//+------------------------------------------------------------------+
//| CalculateWeightedAverage - Calculate weighted average           |
//+------------------------------------------------------------------+
double CalculateWeightedAverage(const double &values[], const double &weights[])
{
    if(ArraySize(values) != ArraySize(weights))
        return 0;
    
    double weightedSum = 0;
    double weightSum = 0;
    
    for(int i = 0; i < ArraySize(values); i++)
    {
        weightedSum += values[i] * weights[i];
        weightSum += weights[i];
    }
    
    if(weightSum == 0)
        return 0;
    
    return weightedSum / weightSum;
}

// ============ DISTANCE CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateDistanceInPips - Distance between two prices in pips   |
//+------------------------------------------------------------------+
double CalculateDistanceInPips(string symbol, double price1, double price2)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    double distance = MathAbs(price1 - price2);
    double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
    
    if(pipValue != 0)
        return distance / pipValue;
    
    return 0;
}

//+------------------------------------------------------------------+
//| CalculateDistanceAsPercentage - Distance as % of price          |
//+------------------------------------------------------------------+
double CalculateDistanceAsPercentage(double price1, double price2, double referencePrice)
{
    if(referencePrice == 0)
        return 0;
    
    double distance = MathAbs(price1 - price2);
    return (distance / referencePrice) * 100;
}

// ============ NORMALIZATION FUNCTIONS ============

//+------------------------------------------------------------------+
//| NormalizePrice - Normalize price to symbol digits               |
//+------------------------------------------------------------------+
double NormalizePrice(string symbol, double price)
{
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| NormalizeLotSize - Normalize lot size to symbol constraints     |
//+------------------------------------------------------------------+
double NormalizeLotSize(string symbol, double lotSize)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Apply minimum and maximum
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    
    // Adjust to lot step
    if(lotStep > 0)
        lotSize = MathRound(lotSize / lotStep) * lotStep;
    
    return NormalizeDouble(lotSize, 2);
}

// ============ PROFIT CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateProfitInPips - Calculate profit/loss in pips           |
//+------------------------------------------------------------------+
double CalculateProfitInPips(string symbol, double entryPrice, 
                           double exitPrice, bool isBuy)
{
    double profit = 0;
    
    if(isBuy)
        profit = exitPrice - entryPrice;
    else
        profit = entryPrice - exitPrice;
    
    return PriceToPips(symbol, profit);
}

//+------------------------------------------------------------------+
//| CalculateProfitInMoney - Calculate profit/loss in money         |
//+------------------------------------------------------------------+
double CalculateProfitInMoney(string symbol, double entryPrice, 
                            double exitPrice, double lotSize, bool isBuy)
{
    double profitInPips = CalculateProfitInPips(symbol, entryPrice, exitPrice, isBuy);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double pipValue = tickValue * lotSize;
    
    return profitInPips * pipValue;
}

// ============ PROBABILITY CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateWinProbability - Calculate win probability from stats  |
//+------------------------------------------------------------------+
double CalculateWinProbability(int totalTrades, int winningTrades)
{
    if(totalTrades == 0)
        return 0;
    
    return (double)winningTrades / totalTrades * 100;
}

//+------------------------------------------------------------------+
//| CalculateExpectedValue - Calculate expected value of a trade    |
//+------------------------------------------------------------------+
double CalculateExpectedValue(double winRatePercent, double avgWin, double avgLoss)
{
    double winRate = winRatePercent / 100;
    double lossRate = 1 - winRate;
    
    return (winRate * avgWin) - (lossRate * avgLoss);
}

// ============ MONEY MANAGEMENT CALCULATIONS ============

// //+------------------------------------------------------------------+
// //| CalculatePositionSizeByRisk - Calculate lot size based on risk %|
// //+------------------------------------------------------------------+
// double CalculatePositionSizeByRisk(string symbol, double entryPrice, 
//                                  double stopLoss, double riskPercent)
// {
//     double riskAmount = accountBalance * (riskPercent / 100);
//     double riskPerLot = CalculatePositionRisk(symbol, entryPrice, stopLoss, 1.0);
    
//     if(riskPerLot == 0)
//         return 0;
    
//     double lotSize = riskAmount / riskPerLot;
    
//     return NormalizeLotSize(symbol, lotSize);
// }

//+------------------------------------------------------------------+
//| CalculateKellyCriterion - Calculate optimal position size       |
//+------------------------------------------------------------------+
double CalculateKellyCriterion(double winRatePercent, double avgWinToLossRatio)
{
    double winRate = winRatePercent / 100;
    double lossRate = 1 - winRate;
    
    // Kelly Criterion formula: f* = (bp - q) / b
    // where: b = avgWin/avgLoss, p = winRate, q = lossRate
    double b = avgWinToLossRatio;
    double p = winRate;
    double q = lossRate;
    
    if(b == 0)
        return 0;
    
    double kelly = (b * p - q) / b;
    
    // Typically use half-Kelly for safety
    return MathMax(kelly * 0.5, 0);
}

// ============ GEOMETRIC CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateFibonacciLevel - Calculate Fibonacci retracement level |
//+------------------------------------------------------------------+
double CalculateFibonacciLevel(double high, double low, double level)
{
    double range = high - low;
    return low + (range * level);
}

//+------------------------------------------------------------------+
//| CalculateGeometricMean - Calculate geometric mean of values     |
//+------------------------------------------------------------------+
double CalculateGeometricMean(const double &values[])
{
    if(ArraySize(values) == 0)
        return 0;
    
    double product = 1;
    for(int i = 0; i < ArraySize(values); i++)
    {
        if(values[i] <= 0)
            return 0;
        product *= values[i];
    }
    
    return MathPow(product, 1.0 / ArraySize(values));
}

// ============ TIME-BASED CALCULATIONS ============

//+------------------------------------------------------------------+
//| CalculateAnnualizedReturn - Calculate annualized return %       |
//+------------------------------------------------------------------+
double CalculateAnnualizedReturn(double totalReturnPercent, double days)
{
    if(days == 0)
        return 0;
    
    double totalReturn = totalReturnPercent / 100;
    double years = days / 365.25;
    
    return (MathPow(1 + totalReturn, 1 / years) - 1) * 100;
}

//+------------------------------------------------------------------+
//| CalculateCompoundedGrowth - Calculate compounded growth         |
//+------------------------------------------------------------------+
double CalculateCompoundedGrowth(double initialAmount, double ratePercent, 
                               int periods)
{
    double rate = ratePercent / 100;
    return initialAmount * MathPow(1 + rate, periods);
}

// ============ VALIDATION FUNCTIONS ============

//+------------------------------------------------------------------+
//| IsValidPrice - Check if price is valid for symbol              |
//+------------------------------------------------------------------+
bool IsValidPrice(string symbol, double price)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickSize > 0)
    {
        double normalized = MathRound(price / tickSize) * tickSize;
        return MathAbs(price - normalized) < (point / 2);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| IsValidLotSize - Check if lot size is valid for symbol         |
//+------------------------------------------------------------------+
bool IsValidLotSize(string symbol, double lotSize)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Check min/max
    if(lotSize < minLot || lotSize > maxLot)
        return false;
    
    // Check step
    if(lotStep > 0)
    {
        double steps = lotSize / lotStep;
        if(MathAbs(steps - MathRound(steps)) > 0.0001)
            return false;
    }
    
    return true;
}