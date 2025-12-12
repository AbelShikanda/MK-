//+------------------------------------------------------------------+
//| Indicator Utilities - Indicator Access                         |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "utils.mqh"

// ============ STRUCTURES ============

struct IndicatorValue {
    double value;
    bool isValid;
    int errorCode;
    string errorMessage;
};

struct IndicatorBuffer {
    double values[];
    int count;
    bool isFilled;
    datetime timestamps[];
};

//+------------------------------------------------------------------+
//| GetCurrentRSIValue - Get current RSI value                      |
//+------------------------------------------------------------------+
double GetCurrentRSIValue(int rsi_handle)
{
    IndicatorValue result = GetIndicatorValue(rsi_handle, 0);
    return result.value;
}

//+------------------------------------------------------------------+
//| GetIndicatorValue - Generic function to get indicator value     |
//+------------------------------------------------------------------+
IndicatorValue GetIndicatorValue(int handle, int buffer = 0, int shift = 0)
{
    IndicatorValue result;
    result.isValid = false;
    result.errorCode = 0;
    result.errorMessage = "";
    
    if(handle == INVALID_HANDLE)
    {
        result.errorCode = 1;
        result.errorMessage = "Invalid indicator handle";
        return result;
    }
    
    double value[1];
    int copied = CopyBuffer(handle, buffer, shift, 1, value);
    
    if(copied <= 0)
    {
        result.errorCode = GetLastError();
        result.errorMessage = "Failed to copy indicator buffer";
        return result;
    }
    
    result.value = value[0];
    result.isValid = true;
    
    return result;
}

//+------------------------------------------------------------------+
//| GetIndicatorValues - Get multiple indicator values              |
//+------------------------------------------------------------------+
IndicatorBuffer GetIndicatorValues(int handle, int buffer = 0, int count = 10, int shift = 0)
{
    IndicatorBuffer result;
    result.isFilled = false;
    result.count = 0;
    
    if(handle == INVALID_HANDLE || count <= 0)
        return result;
    
    ArrayResize(result.values, count);
    ArrayResize(result.timestamps, count);
    
    int copied = CopyBuffer(handle, buffer, shift, count, result.values);
    
    if(copied > 0)
    {
        result.count = copied;
        result.isFilled = true;
        
        // Get corresponding timestamps if needed
        for(int i = 0; i < copied; i++)
            result.timestamps[i] = iTime(_Symbol, PERIOD_CURRENT, shift + i);
    }
    
    return result;
}

// ============ MOVING AVERAGES ============

//+------------------------------------------------------------------+
//| GetMAAverage - Calculate average of MA values                   |
//+------------------------------------------------------------------+
double GetMAAverage(int handle, int period = 5)
{
    IndicatorBuffer buffer = GetIndicatorValues(handle, 0, period);
    
    if(!buffer.isFilled || buffer.count < period)
        return 0;
    
    double sum = 0;
    for(int i = 0; i < period; i++)
        sum += buffer.values[i];
    
    return sum / period;
}

//+------------------------------------------------------------------+
//| GetMASlope - Calculate slope/direction of MA                    |
//+------------------------------------------------------------------+
double GetMASlope(int handle, int lookback = 3)
{
    IndicatorBuffer buffer = GetIndicatorValues(handle, 0, lookback + 1);
    
    if(!buffer.isFilled || buffer.count < lookback + 1)
        return 0;
    
    // Simple slope calculation: (current - previous) / lookback
    double current = buffer.values[0];
    double previous = buffer.values[lookback];
    
    return (current - previous) / lookback;
}

// ============ RSI UTILITIES ============

//+------------------------------------------------------------------+
//| GetRSIState - Get RSI state (overbought/oversold/neutral)       |
//+------------------------------------------------------------------+
string GetRSIState(int handle, double overbought = 70, double oversold = 30)
{
    double rsi = GetCurrentRSIValue(handle);
    
    if(rsi >= overbought)
        return "OVERBOUGHT";
    else if(rsi <= oversold)
        return "OVERSOLD";
    else
        return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| GetRSIStrength - Calculate RSI strength                         |
//+------------------------------------------------------------------+
double GetRSIStrength(int handle)
{
    double rsi = GetCurrentRSIValue(handle);
    
    // Normalize RSI to -100 to +100 scale
    if(rsi >= 50)
        return (rsi - 50) * 2; // 0-100 scale for bullish
    else
        return (50 - rsi) * -2; // -100 to 0 scale for bearish
}

//+------------------------------------------------------------------+
//| GetRSIDivergence - Check for RSI divergence                     |
//+------------------------------------------------------------------+
bool GetRSIDivergence(string symbol, int rsi_handle, bool lookForBullish = true, int lookback = 10)
{
    IndicatorBuffer priceBuffer = GetPriceBuffer(symbol, lookback + 1);
    IndicatorBuffer rsiBuffer = GetIndicatorValues(rsi_handle, 0, lookback + 1);
    
    if(!priceBuffer.isFilled || !rsiBuffer.isFilled)
        return false;
    
    if(lookForBullish)
    {
        // Bullish divergence: price makes lower low, RSI makes higher low
        double priceLow1 = GetLowest(priceBuffer.values, 0, lookback/2);
        double priceLow2 = GetLowest(priceBuffer.values, lookback/2, lookback);
        double rsiLow1 = GetLowest(rsiBuffer.values, 0, lookback/2);
        double rsiLow2 = GetLowest(rsiBuffer.values, lookback/2, lookback);
        
        return (priceLow2 < priceLow1) && (rsiLow2 > rsiLow1);
    }
    else
    {
        // Bearish divergence: price makes higher high, RSI makes lower high
        double priceHigh1 = GetHighest(priceBuffer.values, 0, lookback/2);
        double priceHigh2 = GetHighest(priceBuffer.values, lookback/2, lookback);
        double rsiHigh1 = GetHighest(rsiBuffer.values, 0, lookback/2);
        double rsiHigh2 = GetHighest(rsiBuffer.values, lookback/2, lookback);
        
        return (priceHigh2 > priceHigh1) && (rsiHigh2 < rsiHigh1);
    }
}

// ============ MACD UTILITIES ============

//+------------------------------------------------------------------+
//| GetMACDSignal - Get MACD signal line value                      |
//+------------------------------------------------------------------+
double GetMACDSignal(int macd_handle, int signal_buffer = 1)
{
    IndicatorValue result = GetIndicatorValue(macd_handle, signal_buffer);
    return result.value;
}

//+------------------------------------------------------------------+
//| GetMACDHistogram - Get MACD histogram value                     |
//+------------------------------------------------------------------+
double GetMACDHistogram(int macd_handle, int histogram_buffer = 2)
{
    IndicatorValue result = GetIndicatorValue(macd_handle, histogram_buffer);
    return result.value;
}

// ============ ATR UTILITIES ============

//+------------------------------------------------------------------+
//| GetCurrentATR - Get current ATR value                           |
//+------------------------------------------------------------------+
double GetCurrentATR(int atr_handle)
{
    IndicatorValue result = GetIndicatorValue(atr_handle, 0);
    return result.value;
}

//+------------------------------------------------------------------+
//| GetATRAverage - Get average ATR over period                     |
//+------------------------------------------------------------------+
double GetATRAverage(int atr_handle, int period = 14)
{
    IndicatorBuffer buffer = GetIndicatorValues(atr_handle, 0, period);
    
    if(!buffer.isFilled || buffer.count < period)
        return 0;
    
    double sum = 0;
    for(int i = 0; i < period; i++)
        sum += buffer.values[i];
    
    return sum / period;
}

//+------------------------------------------------------------------+
//| Get current MA value                                            |
//+------------------------------------------------------------------+
double GetCurrentMAValue(int ma_handle)
{
    double ma_value[1];
    if(CopyBuffer(ma_handle, 0, 0, 1, ma_value) > 0)
        return ma_value[0];
    return 0;
}


//+------------------------------------------------------------------+
//| IsVolatile - Check if market is volatile based on ATR           |
//+------------------------------------------------------------------+
bool IsVolatile(int atr_handle, double multiplier = 1.5)
{
    double currentATR = GetCurrentATR(atr_handle);
    double averageATR = GetATRAverage(atr_handle, 20);
    
    if(averageATR == 0)
        return false;
    
    return currentATR > (averageATR * multiplier);
}

// ============ BOLLINGER BANDS ============

//+------------------------------------------------------------------+
//| GetBollingerBand - Get specific Bollinger Band value            |
//+------------------------------------------------------------------+
double GetBollingerBand(int bb_handle, int band = 0) // 0=base, 1=upper, 2=lower
{
    IndicatorValue result = GetIndicatorValue(bb_handle, band);
    return result.value;
}

//+------------------------------------------------------------------+
//| IsPriceAboveBB - Check if price is above Bollinger Band         |
//+------------------------------------------------------------------+
bool IsPriceAboveBB(string symbol, int bb_handle)
{
    double upperBand = GetBollingerBand(bb_handle, 1);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    return currentPrice > upperBand;
}

//+------------------------------------------------------------------+
//| IsPriceBelowBB - Check if price is below Bollinger Band         |
//+------------------------------------------------------------------+
bool IsPriceBelowBB(string symbol, int bb_handle)
{
    double lowerBand = GetBollingerBand(bb_handle, 2);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    return currentPrice < lowerBand;
}

//+------------------------------------------------------------------+
//| GetBBWidth - Get Bollinger Band width                           |
//+------------------------------------------------------------------+
double GetBBWidth(int bb_handle)
{
    double upperBand = GetBollingerBand(bb_handle, 1);
    double lowerBand = GetBollingerBand(bb_handle, 2);
    
    return upperBand - lowerBand;
}

// ============ STOCHASTIC UTILITIES ============

//+------------------------------------------------------------------+
//| GetStochasticK - Get Stochastic %K value                        |
//+------------------------------------------------------------------+
double GetStochasticK(int stoch_handle)
{
    IndicatorValue result = GetIndicatorValue(stoch_handle, 0);
    return result.value;
}

//+------------------------------------------------------------------+
//| GetStochasticD - Get Stochastic %D value                        |
//+------------------------------------------------------------------+
double GetStochasticD(int stoch_handle)
{
    IndicatorValue result = GetIndicatorValue(stoch_handle, 1);
    return result.value;
}

//+------------------------------------------------------------------+
//| IsStochasticBullish - Check if Stochastic is bullish            |
//+------------------------------------------------------------------+
bool IsStochasticBullish(int stoch_handle)
{
    double k = GetStochasticK(stoch_handle);
    double d = GetStochasticD(stoch_handle);
    
    return k > d;
}

//+------------------------------------------------------------------+
//| IsStochasticBearish - Check if Stochastic is bearish            |
//+------------------------------------------------------------------+
bool IsStochasticBearish(int stoch_handle)
{
    double k = GetStochasticK(stoch_handle);
    double d = GetStochasticD(stoch_handle);
    
    return k < d;
}

// ============ DIRECTION AND TEXT UTILITIES ============

//+------------------------------------------------------------------+
//| GetDirectionText - Convert direction enum to text               |
//+------------------------------------------------------------------+
string GetDirectionText(int direction)
{
    if(direction == POSITION_TYPE_BUY) return "BUY";
    if(direction == POSITION_TYPE_SELL) return "SELL";
    if(direction == ORDER_TYPE_BUY) return "BUY ORDER";
    if(direction == ORDER_TYPE_SELL) return "SELL ORDER";
    return "NONE";
}

//+------------------------------------------------------------------+
//| GetTrendDirection - Determine trend direction from indicator    |
//+------------------------------------------------------------------+
int GetTrendDirection(int ma_handle, int rsi_handle = INVALID_HANDLE)
{
    bool maUp = IsMAUp(ma_handle);
    bool maDown = IsMADown(ma_handle);
    
    if(rsi_handle != INVALID_HANDLE)
    {
        string rsiState = GetRSIState(rsi_handle);
        
        // Combine MA and RSI signals
        if(maUp && rsiState != "OVERBOUGHT")
            return POSITION_TYPE_BUY;
        else if(maDown && rsiState != "OVERSOLD")
            return POSITION_TYPE_SELL;
    }
    else
    {
        // Use MA only
        if(maUp) return POSITION_TYPE_BUY;
        if(maDown) return POSITION_TYPE_SELL;
    }
    
    return -1; // No clear direction
}

//+------------------------------------------------------------------+
//| GetIndicatorConsensus - Get consensus from multiple indicators  |
//+------------------------------------------------------------------+
string GetIndicatorConsensus(int ma_handle, int rsi_handle, int macd_handle)
{
    int bullishCount = 0;
    int bearishCount = 0;
    
    // Check MA
    if(IsMAUp(ma_handle)) bullishCount++;
    else if(IsMADown(ma_handle)) bearishCount++;
    
    // Check RSI
    if(IsRSIOversold(rsi_handle)) bullishCount++;
    else if(IsRSIOverbought(rsi_handle)) bearishCount++;
    
    // Check MACD
    if(IsMACDBullish(macd_handle)) bullishCount++;
    else if(IsMACDBearish(macd_handle)) bearishCount++;
    
    // Determine consensus
    if(bullishCount > bearishCount) return "BULLISH";
    if(bearishCount > bullishCount) return "BEARISH";
    return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Helper functions (need to be declared above or separately)     |
//+------------------------------------------------------------------+
bool IsMAUp(int ma_handle)
{
    double maCurrent[1], maPrevious[1];
    if(CopyBuffer(ma_handle, 0, 0, 1, maCurrent) < 1) return false;
    if(CopyBuffer(ma_handle, 0, 1, 1, maPrevious) < 1) return false;
    return maCurrent[0] > maPrevious[0];
}

bool IsMADown(int ma_handle)
{
    double maCurrent[1], maPrevious[1];
    if(CopyBuffer(ma_handle, 0, 0, 1, maCurrent) < 1) return false;
    if(CopyBuffer(ma_handle, 0, 1, 1, maPrevious) < 1) return false;
    return maCurrent[0] < maPrevious[0];
}

bool IsRSIOversold(int rsi_handle)
{
    double rsiValue[1];
    if(CopyBuffer(rsi_handle, 0, 0, 1, rsiValue) < 1) return false;
    return rsiValue[0] < 30.0;
}

bool IsRSIOverbought(int rsi_handle)
{
    double rsiValue[1];
    if(CopyBuffer(rsi_handle, 0, 0, 1, rsiValue) < 1) return false;
    return rsiValue[0] > 70.0;
}

bool IsMACDBullish(int macd_handle)
{
    double macdMain[1], macdSignal[1];
    if(CopyBuffer(macd_handle, 0, 0, 1, macdMain) < 1) return false;
    if(CopyBuffer(macd_handle, 1, 0, 1, macdSignal) < 1) return false;
    return macdMain[0] > macdSignal[0];
}

bool IsMACDBearish(int macd_handle)
{
    double macdMain[1], macdSignal[1];
    if(CopyBuffer(macd_handle, 0, 0, 1, macdMain) < 1) return false;
    if(CopyBuffer(macd_handle, 1, 0, 1, macdSignal) < 1) return false;
    return macdMain[0] < macdSignal[0];
}

// ============ HELPER FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetPriceBuffer - Get array of price values                      |
//+------------------------------------------------------------------+
IndicatorBuffer GetPriceBuffer(string symbol, int count = 10, int shift = 0)
{
    IndicatorBuffer result;
    result.isFilled = false;
    result.count = 0;
    
    if(count <= 0)
        return result;
    
    ArrayResize(result.values, count);
    
    // Copy close prices
    if(CopyClose(symbol, PERIOD_CURRENT, shift, count, result.values) > 0)
    {
        result.count = count;
        result.isFilled = true;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| GetHighest - Get highest value in array                         |
//+------------------------------------------------------------------+
double GetHighest(const double &array[], int start = 0, int end = -1)
{
    if(end == -1) end = ArraySize(array) - 1;
    if(start < 0 || end >= ArraySize(array) || start > end)
        return 0;
    
    double highest = array[start];
    for(int i = start + 1; i <= end; i++)
        if(array[i] > highest)
            highest = array[i];
    
    return highest;
}

//+------------------------------------------------------------------+
//| GetLowest - Get lowest value in array                           |
//+------------------------------------------------------------------+
double GetLowest(const double &array[], int start = 0, int end = -1)
{
    if(end == -1) end = ArraySize(array) - 1;
    if(start < 0 || end >= ArraySize(array) || start > end)
        return 0;
    
    double lowest = array[start];
    for(int i = start + 1; i <= end; i++)
        if(array[i] < lowest)
            lowest = array[i];
    
    return lowest;
}

//+------------------------------------------------------------------+
//| NormalizeIndicatorValue - Normalize indicator value             |
//+------------------------------------------------------------------+
double NormalizeIndicatorValue(double value, double minRange, double maxRange)
{
    if(maxRange <= minRange)
        return 0;
    
    // Clip value to range
    value = MathMax(MathMin(value, maxRange), minRange);
    
    // Normalize to 0-100 scale
    return ((value - minRange) / (maxRange - minRange)) * 100;
}

//+------------------------------------------------------------------+
//| CalculateIndicatorWeight - Calculate weight for indicator       |
//+------------------------------------------------------------------+
double CalculateIndicatorWeight(string indicatorName, double confidence = 1.0)
{
    // Base weights for different indicators
    double baseWeights[5];
    baseWeights[0] = 0.3; // MA
    baseWeights[1] = 0.25; // RSI
    baseWeights[2] = 0.2; // MACD
    baseWeights[3] = 0.15; // Stochastic
    baseWeights[4] = 0.1; // ATR
    
    // Adjust by confidence
    if(StringFind(indicatorName, "MA") >= 0)
        return baseWeights[0] * confidence;
    else if(StringFind(indicatorName, "RSI") >= 0)
        return baseWeights[1] * confidence;
    else if(StringFind(indicatorName, "MACD") >= 0)
        return baseWeights[2] * confidence;
    else if(StringFind(indicatorName, "STOCH") >= 0)
        return baseWeights[3] * confidence;
    else if(StringFind(indicatorName, "ATR") >= 0)
        return baseWeights[4] * confidence;
    
    return 0.1 * confidence; // Default weight
}

// ============ VALIDATION FUNCTIONS ============

//+------------------------------------------------------------------+
//| IsIndicatorValid - Check if indicator handle is valid           |
//+------------------------------------------------------------------+
bool IsIndicatorValid(int handle)
{
    return handle != INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| ValidateIndicatorData - Validate indicator data                 |
//+------------------------------------------------------------------+
bool ValidateIndicatorData(int handle, int minBars = 3)
{
    if(!IsIndicatorValid(handle))
        return false;
    
    IndicatorBuffer buffer = GetIndicatorValues(handle, 0, minBars);
    return buffer.isFilled && buffer.count >= minBars;
}

//+------------------------------------------------------------------+
//| GetIndicatorError - Get error message for indicator             |
//+------------------------------------------------------------------+
string GetIndicatorError(int handle)
{
    if(handle == INVALID_HANDLE)
        return "Invalid indicator handle";
    
    int error = GetLastError();
    if(error == 0)
        return "No error";
    
    switch(error)
    {
        case 4001: return "Array out of range";
        case 4002: return "No history data";
        case 4003: return "Invalid indicator parameters";
        case 4006: return "Invalid indicator handle";
        case 4010: return "CopyBuffer failed";
        case 4011: return "Not enough data";
        default: return StringFormat("Unknown error: %d", error);
    }
}