//+------------------------------------------------------------------+
//| PatternScanner.mqh                                               |
//| Market Pattern Detection Module                                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/structures.mqh"
#include "../../utils/IndicatorUtils.mqh"

// Pattern types enumeration
enum ENUM_PATTERN_TYPE
{
    PATTERN_NONE = 0,
    PATTERN_DOUBLE_TOP,
    PATTERN_DOUBLE_BOTTOM,
    PATTERN_HEAD_SHOULDERS,
    PATTERN_INVERSE_HEAD_SHOULDERS,
    PATTERN_TRIANGLE,
    PATTERN_WEDGE,
    PATTERN_FLAG,
    PATTERN_PENNANT,
    PATTERN_BREAKOUT,
    PATTERN_CANDLESTICK_SINGLE,
    PATTERN_CANDLESTICK_MULTIPLE
};

// Pattern structure
struct PatternSignal
{
    ENUM_PATTERN_TYPE  patternType;
    bool               bullish;
    double             confidence;      // 0-100%
    datetime           detectedTime;
    double             entryPrice;
    double             targetPrice;
    double             stopLossPrice;
    string             description;
    int                timeframe;       // Timeframe where pattern was detected
    int                barsSinceStart;  // How many bars since pattern started
};

// Candlestick pattern types
enum ENUM_CANDLE_PATTERN
{
    CANDLE_NONE = 0,
    CANDLE_DOJI,
    CANDLE_HAMMER,
    CANDLE_SHOOTING_STAR,
    CANDLE_BULLISH_ENGULFING,
    CANDLE_BEARISH_ENGULFING,
    CANDLE_MORNING_STAR,
    CANDLE_EVENING_STAR,
    CANDLE_PIERCING_LINE,
    CANDLE_DARK_CLOUD_COVER,
    CANDLE_HARAMI,
    CANDLE_INVERTED_HAMMER,
    CANDLE_HANGING_MAN
};

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
PatternSignal lastPatterns[10];  // Store last 10 detected patterns
int patternCount = 0;

//+------------------------------------------------------------------+
//| Scan Chart Patterns for a Symbol                                |
//| Main function to scan all available patterns                   |
//+------------------------------------------------------------------+
PatternSignal ScanChartPatterns(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan = 100)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    signal.confidence = 0.0;
    
    // Scan for different pattern types
    PatternSignal doublePattern = DetectDoubleTopBottom(symbol, timeframe, barsToScan);
    if(doublePattern.confidence > signal.confidence) signal = doublePattern;
    
    PatternSignal hsPattern = DetectHeadShoulders(symbol, timeframe, barsToScan);
    if(hsPattern.confidence > signal.confidence) signal = hsPattern;
    
    PatternSignal trianglePattern = DetectTrianglePattern(symbol, timeframe, barsToScan);
    if(trianglePattern.confidence > signal.confidence) signal = trianglePattern;
    
    PatternSignal wedgePattern = DetectWedgePattern(symbol, timeframe, barsToScan);
    if(wedgePattern.confidence > signal.confidence) signal = wedgePattern;
    
    PatternSignal flagPattern = DetectFlagPattern(symbol, timeframe, barsToScan);
    if(flagPattern.confidence > signal.confidence) signal = flagPattern;
    
    PatternSignal breakoutPattern = DetectBreakoutPattern(symbol, timeframe, barsToScan);
    if(breakoutPattern.confidence > signal.confidence) signal = breakoutPattern;
    
    // Update pattern history
    if(signal.patternType != PATTERN_NONE)
    {
        UpdatePatternHistory(signal);
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Candlestick Patterns                                     |
//| Single and multiple candlestick patterns                       |
//+------------------------------------------------------------------+
CANDLE_PATTERN DetectCandlestickPatterns(const string symbol, const ENUM_TIMEFRAMES timeframe, const int lookbackBars = 5)
{
    CANDLE_PATTERN pattern = CANDLE_NONE;
    double confidence = 0.0;
    
    // Check for single candle patterns first (most recent)
    pattern = DetectSingleCandlePattern(symbol, timeframe, 0);
    if(pattern != CANDLE_NONE) return pattern;
    
    // Check for multi-candle patterns
    pattern = DetectMultiCandlePattern(symbol, timeframe, lookbackBars);
    
    return pattern;
}

//+------------------------------------------------------------------+
//| Detect Double Top/Bottom Patterns                               |
//+------------------------------------------------------------------+
PatternSignal DetectDoubleTopBottom(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    signal.confidence = 0.0;
    
    double highs[], lows[];
    ArrayResize(highs, barsToScan);
    ArrayResize(lows, barsToScan);
    
    CopyHigh(symbol, timeframe, 0, barsToScan, highs);
    CopyLow(symbol, timeframe, 0, barsToScan, lows);
    
    // Find potential swing highs for double top
    int swingHighs[];
    if(FindSwingHighs(highs, 3, swingHighs) >= 2)
    {
        double firstTop = highs[swingHighs[0]];
        double secondTop = highs[swingHighs[1]];
        double valley = lows[MathMin(swingHighs[0], swingHighs[1])];
        
        double difference = MathAbs(firstTop - secondTop);
        double avgTop = (firstTop + secondTop) / 2.0;
        double percentDiff = (difference / avgTop) * 100.0;
        
        // Valid double top if tops are within 1% and valley is at least 3% lower
        if(percentDiff < 1.0 && ((avgTop - valley) / avgTop * 100.0) > 3.0)
        {
            signal.patternType = PATTERN_DOUBLE_TOP;
            signal.bearish = true;
            signal.confidence = 100.0 - percentDiff * 10.0;
            signal.detectedTime = iTime(symbol, timeframe, 0);
            signal.entryPrice = valley;
            signal.targetPrice = valley - (avgTop - valley);
            signal.stopLossPrice = avgTop * 1.01;
            signal.description = StringFormat("Double Top | Tops: %.5f, %.5f | Valley: %.5f", 
                                             firstTop, secondTop, valley);
            signal.timeframe = timeframe;
            signal.barsSinceStart = MathMax(swingHighs[0], swingHighs[1]);
        }
    }
    
    // Find potential swing lows for double bottom
    int swingLows[];
    if(FindSwingLows(lows, 3, swingLows) >= 2)
    {
        double firstBottom = lows[swingLows[0]];
        double secondBottom = lows[swingLows[1]];
        double peak = highs[MathMin(swingLows[0], swingLows[1])];
        
        double difference = MathAbs(firstBottom - secondBottom);
        double avgBottom = (firstBottom + secondBottom) / 2.0;
        double percentDiff = (difference / avgBottom) * 100.0;
        
        // Valid double bottom if bottoms are within 1% and peak is at least 3% higher
        if(percentDiff < 1.0 && ((peak - avgBottom) / avgBottom * 100.0) > 3.0)
        {
            signal.patternType = PATTERN_DOUBLE_BOTTOM;
            signal.bullish = true;
            signal.confidence = 100.0 - percentDiff * 10.0;
            signal.detectedTime = iTime(symbol, timeframe, 0);
            signal.entryPrice = peak;
            signal.targetPrice = peak + (peak - avgBottom);
            signal.stopLossPrice = avgBottom * 0.99;
            signal.description = StringFormat("Double Bottom | Bottoms: %.5f, %.5f | Peak: %.5f", 
                                             firstBottom, secondBottom, peak);
            signal.timeframe = timeframe;
            signal.barsSinceStart = MathMax(swingLows[0], swingLows[1]);
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Head & Shoulders Patterns                                |
//+------------------------------------------------------------------+
PatternSignal DetectHeadShoulders(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    
    // Implementation would go here
    // This is a placeholder for the head & shoulders detection logic
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Triangle Patterns                                        |
//+------------------------------------------------------------------+
PatternSignal DetectTrianglePattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    
    // Implementation would go here
    // This is a placeholder for triangle pattern detection
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Wedge Patterns                                           |
//+------------------------------------------------------------------+
PatternSignal DetectWedgePattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    
    // Implementation would go here
    // This is a placeholder for wedge pattern detection
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Flag Patterns                                            |
//+------------------------------------------------------------------+
PatternSignal DetectFlagPattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    
    // Implementation would go here
    // This is a placeholder for flag pattern detection
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Breakout Patterns                                        |
//+------------------------------------------------------------------+
PatternSignal DetectBreakoutPattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barsToScan)
{
    PatternSignal signal;
    signal.patternType = PATTERN_NONE;
    signal.confidence = 0.0;
    
    // Check for recent consolidation followed by breakout
    double closes[];
    ArrayResize(closes, barsToScan);
    CopyClose(symbol, timeframe, 0, barsToScan, closes);
    
    // Calculate price range for last 20 bars
    double range = CalculatePriceRange(closes, 20);
    double currentVolatility = CalculateVolatility(symbol, timeframe);
    
    // Check for breakout from consolidation
    if(range < currentVolatility * 0.5)  // Consolidation: range is less than half of normal volatility
    {
        double recentHigh = ArrayMaximum(closes, 0, 20);
        double recentLow = ArrayMinimum(closes, 0, 20);
        double currentPrice = closes[0];
        
        // Breakout above consolidation
        if(currentPrice > recentHigh)
        {
            signal.patternType = PATTERN_BREAKOUT;
            signal.bullish = true;
            signal.confidence = 75.0;
            signal.detectedTime = iTime(symbol, timeframe, 0);
            signal.entryPrice = currentPrice;
            signal.targetPrice = currentPrice + (recentHigh - recentLow);
            signal.stopLossPrice = recentLow;
            signal.description = "Bullish Breakout from Consolidation";
            signal.timeframe = timeframe;
        }
        // Breakout below consolidation
        else if(currentPrice < recentLow)
        {
            signal.patternType = PATTERN_BREAKOUT;
            signal.bearish = true;
            signal.confidence = 75.0;
            signal.detectedTime = iTime(symbol, timeframe, 0);
            signal.entryPrice = currentPrice;
            signal.targetPrice = currentPrice - (recentHigh - recentLow);
            signal.stopLossPrice = recentHigh;
            signal.description = "Bearish Breakout from Consolidation";
            signal.timeframe = timeframe;
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Detect Single Candle Patterns                                   |
//+------------------------------------------------------------------+
CANDLE_PATTERN DetectSingleCandlePattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barIndex)
{
    double open = iOpen(symbol, timeframe, barIndex);
    double high = iHigh(symbol, timeframe, barIndex);
    double low = iLow(symbol, timeframe, barIndex);
    double close = iClose(symbol, timeframe, barIndex);
    
    double bodySize = MathAbs(close - open);
    double totalRange = high - low;
    
    if(totalRange == 0) return CANDLE_NONE;
    
    double bodyRatio = bodySize / totalRange;
    double upperShadow = high - MathMax(open, close);
    double lowerShadow = MathMin(open, close) - low;
    
    // Doji: Very small body (less than 10% of range)
    if(bodyRatio < 0.1)
    {
        return CANDLE_DOJI;
    }
    
    // Hammer: Small body at top, long lower shadow (at least 2x body)
    if(bodyRatio < 0.3 && lowerShadow >= bodySize * 2.0 && upperShadow <= bodySize * 0.5)
    {
        return (close > open) ? CANDLE_HAMMER : CANDLE_INVERTED_HAMMER;
    }
    
    // Hanging Man/Shooting Star: Small body at bottom, long upper shadow
    if(bodyRatio < 0.3 && upperShadow >= bodySize * 2.0 && lowerShadow <= bodySize * 0.5)
    {
        return (close > open) ? CANDLE_HANGING_MAN : CANDLE_SHOOTING_STAR;
    }
    
    return CANDLE_NONE;
}

//+------------------------------------------------------------------+
//| Detect Multi-Candle Patterns                                    |
//+------------------------------------------------------------------+
CANDLE_PATTERN DetectMultiCandlePattern(const string symbol, const ENUM_TIMEFRAMES timeframe, const int lookbackBars)
{
    // Need at least 3 bars for multi-candle patterns
    if(lookbackBars < 3) return CANDLE_NONE;
    
    // Check for engulfing patterns
    double open1 = iOpen(symbol, timeframe, 1);
    double close1 = iClose(symbol, timeframe, 1);
    double open0 = iOpen(symbol, timeframe, 0);
    double close0 = iClose(symbol, timeframe, 0);
    
    // Bullish Engulfing
    if(close1 < open1 && close0 > open0 && open0 < close1 && close0 > open1)
    {
        return CANDLE_BULLISH_ENGULFING;
    }
    
    // Bearish Engulfing
    if(close1 > open1 && close0 < open0 && open0 > close1 && close0 < open1)
    {
        return CANDLE_BEARISH_ENGULFING;
    }
    
    // Check for harami pattern (need 2 bars)
    if(lookbackBars >= 2)
    {
        // Harami pattern
        double body1 = MathAbs(close1 - open1);
        double body0 = MathAbs(close0 - open0);
        
        if(body1 > body0 * 3.0)  // First candle has much larger body
        {
            bool firstBullish = (close1 > open1);
            bool secondBullish = (close0 > open0);
            
            if(firstBullish != secondBullish)
            {
                if(open0 > MathMin(open1, close1) && close0 < MathMax(open1, close1))
                {
                    return CANDLE_HARAMI;
                }
            }
        }
    }
    
    // Check for morning/evening star (need 3 bars)
    if(lookbackBars >= 3)
    {
        double open2 = iOpen(symbol, timeframe, 2);
        double close2 = iClose(symbol, timeframe, 2);
        
        // Morning Star: Down, doji/small body, up
        if(close2 < open2 && 
           MathAbs(close1 - open1) < (MathAbs(close2 - open2) * 0.3) &&
           close0 > open0 && close0 > (open2 + close2) / 2.0)
        {
            return CANDLE_MORNING_STAR;
        }
        
        // Evening Star: Up, doji/small body, down
        if(close2 > open2 && 
           MathAbs(close1 - open1) < (MathAbs(close2 - open2) * 0.3) &&
           close0 < open0 && close0 < (open2 + close2) / 2.0)
        {
            return CANDLE_EVENING_STAR;
        }
    }
    
    return CANDLE_NONE;
}

//+------------------------------------------------------------------+
//| Helper Functions                                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Find Swing Highs                                                |
//+------------------------------------------------------------------+
int FindSwingHighs(const double &highs[], const int lookAround, int &swingIndexes[])
{
    int count = 0;
    ArrayResize(swingIndexes, 0);
    
    for(int i = lookAround; i < ArraySize(highs) - lookAround; i++)
    {
        bool isSwingHigh = true;
        
        for(int j = i - lookAround; j <= i + lookAround; j++)
        {
            if(j == i) continue;
            if(highs[i] <= highs[j])
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh)
        {
            count++;
            ArrayResize(swingIndexes, count);
            swingIndexes[count-1] = i;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Find Swing Lows                                                 |
//+------------------------------------------------------------------+
int FindSwingLows(const double &lows[], const int lookAround, int &swingIndexes[])
{
    int count = 0;
    ArrayResize(swingIndexes, 0);
    
    for(int i = lookAround; i < ArraySize(lows) - lookAround; i++)
    {
        bool isSwingLow = true;
        
        for(int j = i - lookAround; j <= i + lookAround; j++)
        {
            if(j == i) continue;
            if(lows[i] >= lows[j])
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow)
        {
            count++;
            ArrayResize(swingIndexes, count);
            swingIndexes[count-1] = i;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Price Range                                           |
//+------------------------------------------------------------------+
double CalculatePriceRange(const double &prices[], const int period)
{
    if(ArraySize(prices) < period) return 0.0;
    
    double minPrice = prices[0];
    double maxPrice = prices[0];
    
    for(int i = 1; i < period; i++)
    {
        if(prices[i] < minPrice) minPrice = prices[i];
        if(prices[i] > maxPrice) maxPrice = prices[i];
    }
    
    return maxPrice - minPrice;
}

//+------------------------------------------------------------------+
//| Calculate Volatility                                            |
//+------------------------------------------------------------------+
double CalculateVolatility(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period = 20)
{
    double closes[];
    ArrayResize(closes, period);
    
    if(CopyClose(symbol, timeframe, 0, period, closes) < period) return 0.0;
    
    double sum = 0.0;
    for(int i = 0; i < period; i++) sum += closes[i];
    double mean = sum / period;
    
    double variance = 0.0;
    for(int i = 0; i < period; i++)
    {
        variance += MathPow(closes[i] - mean, 2);
    }
    variance /= period;
    
    return MathSqrt(variance);
}

//+------------------------------------------------------------------+
//| Update Pattern History                                          |
//+------------------------------------------------------------------+
void UpdatePatternHistory(const PatternSignal &pattern)
{
    // Shift array if full
    if(patternCount >= ArraySize(lastPatterns))
    {
        for(int i = 1; i < ArraySize(lastPatterns); i++)
        {
            lastPatterns[i-1] = lastPatterns[i];
        }
        patternCount--;
    }
    
    // Add new pattern
    lastPatterns[patternCount] = pattern;
    patternCount++;
}

//+------------------------------------------------------------------+
//| Get Pattern Description                                         |
//+------------------------------------------------------------------+
string GetPatternDescription(const ENUM_PATTERN_TYPE patternType)
{
    switch(patternType)
    {
        case PATTERN_DOUBLE_TOP: return "Double Top - Bearish Reversal";
        case PATTERN_DOUBLE_BOTTOM: return "Double Bottom - Bullish Reversal";
        case PATTERN_HEAD_SHOULDERS: return "Head & Shoulders - Bearish Reversal";
        case PATTERN_INVERSE_HEAD_SHOULDERS: return "Inverse Head & Shoulders - Bullish Reversal";
        case PATTERN_TRIANGLE: return "Triangle - Consolidation";
        case PATTERN_WEDGE: return "Wedge - Continuation/Reversal";
        case PATTERN_FLAG: return "Flag - Continuation";
        case PATTERN_PENNANT: return "Pennant - Continuation";
        case PATTERN_BREAKOUT: return "Breakout - Continuation";
        case PATTERN_CANDLESTICK_SINGLE: return "Single Candlestick Pattern";
        case PATTERN_CANDLESTICK_MULTIPLE: return "Multiple Candlestick Pattern";
        default: return "No Pattern";
    }
}

//+------------------------------------------------------------------+
//| Get Candlestick Pattern Description                             |
//+------------------------------------------------------------------+
string GetCandlePatternDescription(const CANDLE_PATTERN candlePattern)
{
    switch(candlePattern)
    {
        case CANDLE_DOJI: return "Doji - Indecision";
        case CANDLE_HAMMER: return "Hammer - Bullish Reversal";
        case CANDLE_SHOOTING_STAR: return "Shooting Star - Bearish Reversal";
        case CANDLE_BULLISH_ENGULFING: return "Bullish Engulfing - Bullish Reversal";
        case CANDLE_BEARISH_ENGULFING: return "Bearish Engulfing - Bearish Reversal";
        case CANDLE_MORNING_STAR: return "Morning Star - Bullish Reversal";
        case CANDLE_EVENING_STAR: return "Evening Star - Bearish Reversal";
        case CANDLE_PIERCING_LINE: return "Piercing Line - Bullish Reversal";
        case CANDLE_DARK_CLOUD_COVER: return "Dark Cloud Cover - Bearish Reversal";
        case CANDLE_HARAMI: return "Harami - Potential Reversal";
        case CANDLE_INVERTED_HAMMER: return "Inverted Hammer - Bullish Reversal";
        case CANDLE_HANGING_MAN: return "Hanging Man - Bearish Reversal";
        default: return "No Candlestick Pattern";
    }
}

//+------------------------------------------------------------------+
//| Get Recent Patterns                                             |
//+------------------------------------------------------------------+
int GetRecentPatterns(PatternSignal &patterns[], const int maxPatterns = 10)
{
    int count = MathMin(patternCount, maxPatterns);
    ArrayResize(patterns, count);
    
    for(int i = 0; i < count; i++)
    {
        patterns[i] = lastPatterns[i];
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Clear Pattern History                                           |
//+------------------------------------------------------------------+
void ClearPatternHistory()
{
    patternCount = 0;
    for(int i = 0; i < ArraySize(lastPatterns); i++)
    {
        lastPatterns[i].patternType = PATTERN_NONE;
        lastPatterns[i].confidence = 0.0;
    }
}