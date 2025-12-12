//+------------------------------------------------------------------+
//| LevelAnalyzer.mqh                                                |
//| Support & Resistance Level Analysis Module                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/structures.mqh"
#include "../../utils/IndicatorUtils.mqh"

// Level structure for detailed analysis
struct LevelAnalysis
{
    double price;               // Price level
    string type;               // "SUPPORT" or "RESISTANCE"
    string timeframe;          // Timeframe where level was identified
    datetime timestamp;        // When level was formed
    double strength;           // Strength score 0-100
    int touches;              // Number of price touches
    int rejections;           // Number of price rejections
    double volumeProfile;      // Volume at this level
    double breakProbability;   // Probability of break 0-100
    bool isMajor;             // Major level flag
    bool isRecent;            // Recent level flag
    bool isBroken;            // Broken level flag
    int barsSinceLastTouch;   // Bars since last touch
};

// Level cluster structure for grouped levels
struct LevelCluster
{
    double centerPrice;        // Center price of cluster
    double clusterRange;       // Range of the cluster
    int levelCount;           // Number of levels in cluster
    double totalStrength;      // Combined strength
    double averageStrength;    // Average strength
    string dominantType;      // Most common type in cluster
    datetime latestTouch;      // Latest touch time
};

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
LevelAnalysis recentLevels[100];
int totalLevels = 0;

//+------------------------------------------------------------------+
//| Analyze Support & Resistance Levels                             |
//| Main function to analyze all S/R levels for a symbol           |
//+------------------------------------------------------------------+
int AnalyzeSupportResistance(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                             const int lookbackBars, LevelAnalysis &levels[])
{
    ArrayResize(levels, 0);
    
    // Analyze multiple timeframe levels
    const ENUM_TIMEFRAMES analysisTimeframes[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
    int totalFound = 0;
    
    for(int i = 0; i < ArraySize(analysisTimeframes); i++)
    {
        LevelAnalysis tfLevels[];
        int count = AnalyzeTimeframeLevels(symbol, analysisTimeframes[i], lookbackBars / 2, tfLevels);
        
        if(count > 0)
        {
            // Merge into main array
            int oldSize = ArraySize(levels);
            ArrayResize(levels, oldSize + count);
            
            for(int j = 0; j < count; j++)
            {
                levels[oldSize + j] = tfLevels[j];
            }
            
            totalFound += count;
        }
    }
    
    // Calculate strength for all levels
    for(int i = 0; i < totalFound; i++)
    {
        levels[i].strength = CalculateLevelStrength(levels[i], symbol, timeframe);
    }
    
    // Sort by price (ascending)
    SortLevelsByPrice(levels);
    
    // Update recent levels history
    UpdateLevelHistory(levels, totalFound);
    
    return totalFound;
}

//+------------------------------------------------------------------+
//| Calculate Level Strength Score                                  |
//| Returns 0-100 strength score for a level                       |
//+------------------------------------------------------------------+
double CalculateLevelStrength(const LevelAnalysis &level, const string symbol, const ENUM_TIMEFRAMES currentTF)
{
    double strength = 0.0;
    
    // Base strength from timeframe
    strength += GetTimeframeWeight(level.timeframe);
    
    // Add strength from touches
    strength += level.touches * 5.0;
    
    // Add strength from rejections
    strength += level.rejections * 8.0;
    
    // Recent level bonus
    if(level.isRecent)
    {
        strength += 15.0;
    }
    
    // Major level bonus (from higher timeframe)
    if(level.isMajor)
    {
        strength += 20.0;
    }
    
    // Volume profile contribution
    strength += level.volumeProfile * 10.0;
    
    // Break probability adjustment
    strength *= (1.0 - (level.breakProbability / 200.0));
    
    // Time decay for older levels
    strength *= GetTimeDecayFactor(level.timestamp);
    
    return MathMin(strength, 100.0);
}

//+------------------------------------------------------------------+
//| Analyze Levels for Specific Timeframe                          |
//+------------------------------------------------------------------+
int AnalyzeTimeframeLevels(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                           const int lookbackBars, LevelAnalysis &levels[])
{
    ArrayResize(levels, 0);
    
    double highs[], lows[], closes[], volumes[];
    ArrayResize(highs, lookbackBars);
    ArrayResize(lows, lookbackBars);
    ArrayResize(closes, lookbackBars);
    ArrayResize(volumes, lookbackBars);
    
    CopyHigh(symbol, timeframe, 0, lookbackBars, highs);
    CopyLow(symbol, timeframe, 0, lookbackBars, lows);
    CopyClose(symbol, timeframe, 0, lookbackBars, closes);
    CopyTickVolume(symbol, timeframe, 0, lookbackBars, volumes);
    
    // Find significant price levels
    for(int i = 10; i < lookbackBars - 10; i++)
    {
        double currentHigh = highs[i];
        double currentLow = lows[i];
        double currentClose = closes[i];
        
        // Check for resistance candidates
        if(IsResistanceLevel(symbol, timeframe, currentHigh, i, lookbackBars))
        {
            LevelAnalysis level;
            level.price = currentHigh;
            level.type = "RESISTANCE";
            level.timeframe = TimeframeToString(timeframe);
            level.timestamp = iTime(symbol, timeframe, i);
            level.touches = CountTouches(highs, lows, currentHigh, i, lookbackBars);
            level.rejections = CountRejections(highs, lows, currentHigh, i, lookbackBars);
            level.volumeProfile = CalculateVolumeProfile(volumes, i, 5);
            level.breakProbability = CalculateBreakProbability(highs, lows, currentHigh, "RESISTANCE", i, lookbackBars);
            level.isMajor = (timeframe >= PERIOD_H4);
            level.isRecent = (i <= 20);
            level.isBroken = IsLevelBroken(closes, currentHigh, "RESISTANCE", i, lookbackBars);
            level.barsSinceLastTouch = BarsSinceLastTouch(highs, lows, currentHigh, i);
            
            int size = ArraySize(levels);
            ArrayResize(levels, size + 1);
            levels[size] = level;
        }
        
        // Check for support candidates
        if(IsSupportLevel(symbol, timeframe, currentLow, i, lookbackBars))
        {
            LevelAnalysis level;
            level.price = currentLow;
            level.type = "SUPPORT";
            level.timeframe = TimeframeToString(timeframe);
            level.timestamp = iTime(symbol, timeframe, i);
            level.touches = CountTouches(highs, lows, currentLow, i, lookbackBars);
            level.rejections = CountRejections(highs, lows, currentLow, i, lookbackBars);
            level.volumeProfile = CalculateVolumeProfile(volumes, i, 5);
            level.breakProbability = CalculateBreakProbability(highs, lows, currentLow, "SUPPORT", i, lookbackBars);
            level.isMajor = (timeframe >= PERIOD_H4);
            level.isRecent = (i <= 20);
            level.isBroken = IsLevelBroken(closes, currentLow, "SUPPORT", i, lookbackBars);
            level.barsSinceLastTouch = BarsSinceLastTouch(highs, lows, currentLow, i);
            
            int size = ArraySize(levels);
            ArrayResize(levels, size + 1);
            levels[size] = level;
        }
    }
    
    // Merge close levels into clusters
    MergeCloseLevels(levels);
    
    return ArraySize(levels);
}

//+------------------------------------------------------------------+
//| Check if Price is Resistance Level                             |
//+------------------------------------------------------------------+
bool IsResistanceLevel(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                       const double price, const int barIndex, const int lookbackBars)
{
    double highs[], lows[];
    ArrayResize(highs, lookbackBars);
    ArrayResize(lows, lookbackBars);
    
    CopyHigh(symbol, timeframe, 0, lookbackBars, highs);
    CopyLow(symbol, timeframe, 0, lookbackBars, lows);
    
    // Check for price rejection
    int rejectionCount = 0;
    double tolerance = GetPriceTolerance(symbol);
    
    for(int i = MathMax(barIndex - 10, 0); i <= MathMin(barIndex + 10, lookbackBars - 1); i++)
    {
        if(i == barIndex) continue;
        
        // Check if price approached but didn't break
        if(highs[i] >= price - tolerance && highs[i] <= price + tolerance)
        {
            // Check for bearish rejection (long upper shadow)
            double close = iClose(symbol, timeframe, i);
            double open = iOpen(symbol, timeframe, i);
            
            if(close < price && MathAbs(highs[i] - MathMax(open, close)) > MathAbs(close - open) * 1.5)
            {
                rejectionCount++;
            }
        }
    }
    
    return (rejectionCount >= 2);
}

//+------------------------------------------------------------------+
//| Check if Price is Support Level                                |
//+------------------------------------------------------------------+
bool IsSupportLevel(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                    const double price, const int barIndex, const int lookbackBars)
{
    double highs[], lows[];
    ArrayResize(highs, lookbackBars);
    ArrayResize(lows, lookbackBars);
    
    CopyHigh(symbol, timeframe, 0, lookbackBars, highs);
    CopyLow(symbol, timeframe, 0, lookbackBars, lows);
    
    // Check for price rejection
    int rejectionCount = 0;
    double tolerance = GetPriceTolerance(symbol);
    
    for(int i = MathMax(barIndex - 10, 0); i <= MathMin(barIndex + 10, lookbackBars - 1); i++)
    {
        if(i == barIndex) continue;
        
        // Check if price approached but didn't break
        if(lows[i] >= price - tolerance && lows[i] <= price + tolerance)
        {
            // Check for bullish rejection (long lower shadow)
            double close = iClose(symbol, timeframe, i);
            double open = iOpen(symbol, timeframe, i);
            
            if(close > price && MathAbs(MathMin(open, close) - lows[i]) > MathAbs(close - open) * 1.5)
            {
                rejectionCount++;
            }
        }
    }
    
    return (rejectionCount >= 2);
}

//+------------------------------------------------------------------+
//| Count Price Touches to Level                                   |
//+------------------------------------------------------------------+
int CountTouches(const double &highs[], const double &lows[], const double level, 
                 const int referenceBar, const int lookbackBars)
{
    int touches = 0;
    double tolerance = GetPriceToleranceFromArray(highs, lows);
    
    for(int i = 0; i < lookbackBars; i++)
    {
        if(i == referenceBar) continue;
        
        if((highs[i] >= level - tolerance && highs[i] <= level + tolerance) ||
           (lows[i] >= level - tolerance && lows[i] <= level + tolerance))
        {
            touches++;
        }
    }
    
    return touches;
}

//+------------------------------------------------------------------+
//| Count Price Rejections from Level                              |
//+------------------------------------------------------------------+
int CountRejections(const double &highs[], const double &lows[], const double level,
                    const int referenceBar, const int lookbackBars)
{
    int rejections = 0;
    double tolerance = GetPriceToleranceFromArray(highs, lows);
    
    for(int i = MathMax(referenceBar - 10, 0); i <= MathMin(referenceBar + 10, lookbackBars - 1); i++)
    {
        if(i == referenceBar) continue;
        
        // Check for rejection patterns
        if(IsRejectionBar(highs, lows, level, i, tolerance))
        {
            rejections++;
        }
    }
    
    return rejections;
}

//+------------------------------------------------------------------+
//| Calculate Volume Profile at Level                              |
//+------------------------------------------------------------------+
double CalculateVolumeProfile(const long &volumes[], const int barIndex, const int window)
{
    if(ArraySize(volumes) < barIndex + window) return 0.0;
    
    long windowVolume = 0;
    for(int i = barIndex; i < barIndex + window; i++)
    {
        windowVolume += volumes[i];
    }
    
    long totalVolume = 0;
    for(int i = 0; i < ArraySize(volumes); i++)
    {
        totalVolume += volumes[i];
    }
    
    if(totalVolume > 0)
    {
        return (double)windowVolume / (double)totalVolume;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Break Probability                                    |
//+------------------------------------------------------------------+
double CalculateBreakProbability(const double &highs[], const double &lows[], 
                                 const double level, const string type, 
                                 const int barIndex, const int lookbackBars)
{
    double probability = 50.0; // Base probability
    
    // Adjust based on recent price action
    double recentAvgPrice = 0.0;
    int recentBars = MathMin(5, barIndex);
    
    for(int i = 0; i < recentBars; i++)
    {
        recentAvgPrice += (highs[i] + lows[i]) / 2.0;
    }
    
    if(recentBars > 0)
    {
        recentAvgPrice /= recentBars;
        
        if(type == "RESISTANCE")
        {
            if(recentAvgPrice > level) probability += 25.0;
            if(recentAvgPrice < level) probability -= 15.0;
        }
        else if(type == "SUPPORT")
        {
            if(recentAvgPrice < level) probability += 25.0;
            if(recentAvgPrice > level) probability -= 15.0;
        }
    }
    
    return MathMax(0.0, MathMin(100.0, probability));
}

//+------------------------------------------------------------------+
//| Check if Level is Broken                                       |
//+------------------------------------------------------------------+
bool IsLevelBroken(const double &closes[], const double level, const string type, 
                   const int barIndex, const int lookbackBars)
{
    for(int i = 0; i < barIndex; i++)
    {
        if(type == "RESISTANCE" && closes[i] > level)
        {
            return true;
        }
        else if(type == "SUPPORT" && closes[i] < level)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Bars Since Last Touch                                           |
//+------------------------------------------------------------------+
int BarsSinceLastTouch(const double &highs[], const double &lows[], const double level, const int currentBar)
{
    for(int i = currentBar - 1; i >= 0; i--)
    {
        double tolerance = GetPriceToleranceFromArray(highs, lows);
        if(highs[i] >= level - tolerance && highs[i] <= level + tolerance ||
           lows[i] >= level - tolerance && lows[i] <= level + tolerance)
        {
            return currentBar - i;
        }
    }
    
    return currentBar;
}

//+------------------------------------------------------------------+
//| Merge Close Levels into Clusters                               |
//+------------------------------------------------------------------+
void MergeCloseLevels(LevelAnalysis &levels[])
{
    if(ArraySize(levels) <= 1) return;
    
    double tolerance = GetAveragePriceTolerance(levels);
    
    for(int i = 0; i < ArraySize(levels) - 1; i++)
    {
        for(int j = i + 1; j < ArraySize(levels); j++)
        {
            if(MathAbs(levels[i].price - levels[j].price) <= tolerance)
            {
                // Merge levels
                LevelAnalysis merged = MergeTwoLevels(levels[i], levels[j]);
                
                // Replace first level with merged
                levels[i] = merged;
                
                // Remove second level
                for(int k = j; k < ArraySize(levels) - 1; k++)
                {
                    levels[k] = levels[k + 1];
                }
                ArrayResize(levels, ArraySize(levels) - 1);
                j--; // Check same position again
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Merge Two Levels into One                                      |
//+------------------------------------------------------------------+
LevelAnalysis MergeTwoLevels(const LevelAnalysis &level1, const LevelAnalysis &level2)
{
    LevelAnalysis merged;
    
    // Average price
    merged.price = (level1.price + level2.price) / 2.0;
    
    // Use stronger type
    merged.type = (level1.strength >= level2.strength) ? level1.type : level2.type;
    
    // Use higher timeframe
    merged.timeframe = GetHigherTimeframe(level1.timeframe, level2.timeframe);
    
    // Latest timestamp
    merged.timestamp = (level1.timestamp > level2.timestamp) ? level1.timestamp : level2.timestamp;
    
    // Combine counts
    merged.touches = level1.touches + level2.touches;
    merged.rejections = level1.rejections + level2.rejections;
    
    // Average volume profile
    merged.volumeProfile = (level1.volumeProfile + level2.volumeProfile) / 2.0;
    
    // Average break probability
    merged.breakProbability = (level1.breakProbability + level2.breakProbability) / 2.0;
    
    // Combined major status
    merged.isMajor = level1.isMajor || level2.isMajor;
    
    // Combined recent status
    merged.isRecent = level1.isRecent || level2.isRecent;
    
    // Combined broken status
    merged.isBroken = level1.isBroken || level2.isBroken;
    
    // Smaller bars since touch
    merged.barsSinceLastTouch = MathMin(level1.barsSinceLastTouch, level2.barsSinceLastTouch);
    
    return merged;
}

//+------------------------------------------------------------------+
//| Helper Functions                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get Timeframe Weight                                            |
//+------------------------------------------------------------------+
double GetTimeframeWeight(const string timeframe)
{
    if(timeframe == "D1") return 25.0;
    if(timeframe == "H4") return 20.0;
    if(timeframe == "H1") return 15.0;
    if(timeframe == "M15") return 10.0;
    return 5.0;
}

//+------------------------------------------------------------------+
//| Timeframe to String                                            |
//+------------------------------------------------------------------+
string TimeframeToString(const ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "Current";
    }
}

//+------------------------------------------------------------------+
//| Get Higher Timeframe                                           |
//+------------------------------------------------------------------+
string GetHigherTimeframe(const string tf1, const string tf2)
{
    // Simple comparison - can be enhanced
    string timeframes[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};
    
    int idx1 = -1, idx2 = -1;
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        if(tf1 == timeframes[i]) idx1 = i;
        if(tf2 == timeframes[i]) idx2 = i;
    }
    
    if(idx1 >= 0 && idx2 >= 0)
    {
        return timeframes[MathMax(idx1, idx2)];
    }
    
    return tf1;
}

//+------------------------------------------------------------------+
//| Get Price Tolerance for Symbol                                 |
//+------------------------------------------------------------------+
double GetPriceTolerance(const string symbol)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double avgSpread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
    
    return MathMax(point * 10.0, avgSpread * 2.0);
}

//+------------------------------------------------------------------+
//| Get Price Tolerance from Array                                 |
//+------------------------------------------------------------------+
double GetPriceToleranceFromArray(const double &highs[], const double &lows[])
{
    if(ArraySize(highs) < 2) return 0.0001;
    
    double avgRange = 0.0;
    for(int i = 0; i < MathMin(20, ArraySize(highs)); i++)
    {
        avgRange += (highs[i] - lows[i]);
    }
    avgRange /= MathMin(20, ArraySize(highs));
    
    return avgRange * 0.1; // 10% of average range
}

//+------------------------------------------------------------------+
//| Get Average Price Tolerance                                    |
//+------------------------------------------------------------------+
double GetAveragePriceTolerance(const LevelAnalysis &levels[])
{
    if(ArraySize(levels) < 2) return 0.0001;
    
    double avgDistance = 0.0;
    int count = 0;
    
    for(int i = 0; i < ArraySize(levels) - 1; i++)
    {
        for(int j = i + 1; j < ArraySize(levels); j++)
        {
            avgDistance += MathAbs(levels[i].price - levels[j].price);
            count++;
        }
    }
    
    if(count > 0)
    {
        avgDistance /= count;
        return avgDistance * 0.3; // 30% of average distance
    }
    
    return 0.0001;
}

//+------------------------------------------------------------------+
//| Check if Bar Shows Rejection                                   |
//+------------------------------------------------------------------+
bool IsRejectionBar(const double &highs[], const double &lows[], 
                    const double level, const int barIndex, const double tolerance)
{
    // Check if price approached level
    if(highs[barIndex] >= level - tolerance && highs[barIndex] <= level + tolerance)
    {
        // Check for bearish rejection (price closed below level)
        return true;
    }
    
    if(lows[barIndex] >= level - tolerance && lows[barIndex] <= level + tolerance)
    {
        // Check for bullish rejection (price closed above level)
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Time Decay Factor                                          |
//+------------------------------------------------------------------+
double GetTimeDecayFactor(const datetime levelTime)
{
    int hoursSince = int((TimeCurrent() - levelTime) / 3600);
    
    if(hoursSince < 24) return 1.0;        // Within 1 day
    if(hoursSince < 72) return 0.9;        // Within 3 days
    if(hoursSince < 168) return 0.8;       // Within 1 week
    if(hoursSince < 720) return 0.7;       // Within 1 month
    return 0.6;                           // Older than 1 month
}

//+------------------------------------------------------------------+
//| Sort Levels by Price                                           |
//+------------------------------------------------------------------+
void SortLevelsByPrice(LevelAnalysis &levels[])
{
    int size = ArraySize(levels);
    
    for(int i = 0; i < size - 1; i++)
    {
        for(int j = i + 1; j < size; j++)
        {
            if(levels[i].price > levels[j].price)
            {
                LevelAnalysis temp = levels[i];
                levels[i] = levels[j];
                levels[j] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update Level History                                           |
//+------------------------------------------------------------------+
void UpdateLevelHistory(const LevelAnalysis &levels[], const int count)
{
    int maxStore = MathMin(count, 100);
    
    for(int i = 0; i < maxStore; i++)
    {
        recentLevels[i] = levels[i];
    }
    
    totalLevels = maxStore;
}

//+------------------------------------------------------------------+
//| Get Strongest Levels                                           |
//+------------------------------------------------------------------+
int GetStrongestLevels(const LevelAnalysis &levels[], const int count, LevelAnalysis &strongLevels[], 
                       const double minStrength = 60.0)
{
    ArrayResize(strongLevels, 0);
    int strongCount = 0;
    
    for(int i = 0; i < count; i++)
    {
        if(levels[i].strength >= minStrength)
        {
            int size = ArraySize(strongLevels);
            ArrayResize(strongLevels, size + 1);
            strongLevels[size] = levels[i];
            strongCount++;
        }
    }
    
    return strongCount;
}

//+------------------------------------------------------------------+
//| Get Nearest Level to Price                                     |
//+------------------------------------------------------------------+
bool GetNearestLevel(const LevelAnalysis &levels[], const int count, const double price, 
                     const string type, LevelAnalysis &nearestLevel)
{
    double minDistance = 999999.0;
    int nearestIndex = -1;
    
    for(int i = 0; i < count; i++)
    {
        if(type == "ANY" || levels[i].type == type)
        {
            double distance = MathAbs(levels[i].price - price);
            if(distance < minDistance)
            {
                minDistance = distance;
                nearestIndex = i;
            }
        }
    }
    
    if(nearestIndex >= 0)
    {
        nearestLevel = levels[nearestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Level Analysis Summary                                     |
//+------------------------------------------------------------------+
string GetLevelAnalysisSummary(const LevelAnalysis &levels[], const int count)
{
    int supportCount = 0;
    int resistanceCount = 0;
    int majorCount = 0;
    int brokenCount = 0;
    double avgStrength = 0.0;
    
    for(int i = 0; i < count; i++)
    {
        if(levels[i].type == "SUPPORT") supportCount++;
        else if(levels[i].type == "RESISTANCE") resistanceCount++;
        
        if(levels[i].isMajor) majorCount++;
        if(levels[i].isBroken) brokenCount++;
        
        avgStrength += levels[i].strength;
    }
    
    if(count > 0) avgStrength /= count;
    
    return StringFormat("Levels: %d total | Support: %d | Resistance: %d | Major: %d | Broken: %d | Avg Strength: %.1f",
                       count, supportCount, resistanceCount, majorCount, brokenCount, avgStrength);
}