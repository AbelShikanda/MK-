//+------------------------------------------------------------------+
//| POIManager.mqh                                                   |
//| Points of Interest Management Module                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../../config/inputs.mqh"
#include "../../config/GlobalVariables.mqh"
#include "../../config/structures.mqh"
#include "../../utils/SymbolUtils.mqh"
#include "../../utils/TradeUtils.mqh"

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
datetime lastCleanupTime = 0;
int lastPoiCount = 0;

//+------------------------------------------------------------------+
//| Initialize POI System                                           |
//+------------------------------------------------------------------+
void InitializePOISystem(const string symbol)
{
    // Clear any existing lines
    RemoveAllPOIObjects(symbol);
    ArrayResize(poiLevels, 0);
    lastPoiCount = 0;
    
    PrintFormat("POI System Initialized for %s", symbol);
}

//+------------------------------------------------------------------+
//| Cleanup POI System                                              |
//+------------------------------------------------------------------+
void CleanupPOISystem(const string symbol)
{
    RemoveAllPOIObjects(symbol);
    ArrayResize(poiLevels, 0);
    lastPoiCount = 0;
    
    PrintFormat("POI System Cleaned up for %s", symbol);
}

//+------------------------------------------------------------------+
//| Get All POI Levels for a Symbol                                 |
//+------------------------------------------------------------------+
int GetAllPOILevels(const string symbol, const double currentPrice, POILevel &levels[])
{
    ArrayResize(levels, 0);
    
    // Find all POI levels
    FindSwingPoints(symbol, currentPrice);
    FindSRLevels(symbol, currentPrice);
    FindLiquidityLevels(symbol, currentPrice);
    UpdateBrokenLevels(symbol, currentPrice);
    
    // Copy to output array
    int count = ArraySize(poiLevels);
    if(count > 0)
    {
        ArrayResize(levels, count);
        for(int i = 0; i < count; i++)
        {
            levels[i] = poiLevels[i];
        }
    }
    
    lastPoiCount = count;
    return count;
}

//+------------------------------------------------------------------+
//| Get Current Trailing SL Distance in Pips                        |
//+------------------------------------------------------------------+
double GetCurrentTrailingSLPips(const string symbol, const double currentPrice, const double profitPips)
{
    // Determine which stage based on profit
    if(profitPips >= Stage3Threshold)
    {
        return Stage3Distance;
    }
    else if(profitPips >= Stage2Threshold)
    {
        return Stage2Distance;
    }
    else if(profitPips >= Stage1Threshold)
    {
        return Stage1Distance;
    }
    
    // Default to Stage1 if no profit yet
    return Stage1Distance;
}

//+------------------------------------------------------------------+
//| Get Dynamic Required Distance                                   |
//+------------------------------------------------------------------+
double GetDynamicRequiredDistance(const string symbol, const double currentTrailingSLPips)
{
    // Get base multiplier based on symbol
    double symbolMultiplier = 1.0;
    if(StringFind(symbol, "XAU") >= 0)
    {
        symbolMultiplier = GoldDistanceMultiplier;
    }
    else if(StringFind(symbol, "XAG") >= 0)
    {
        symbolMultiplier = SilverDistanceMultiplier;
    }
    
    // Calculate base distance
    double baseDistance = MinimumBaseDistance * symbolMultiplier;
    
    // Add dynamic component based on trailing SL
    double dynamicDistance = baseDistance + (currentTrailingSLPips * BaseDistanceMultiplier);
    
    // Apply maximum limit
    return MathMin(dynamicDistance, MaximumDistance);
}

//+------------------------------------------------------------------+
//| Check if Level is Active                                        |
//+------------------------------------------------------------------+
bool IsLevelActive(const string symbol, const POILevel &level, const double currentPrice, 
                   const double requiredDistancePips)
{
    const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double distancePips = MathAbs(currentPrice - level.price) / pointValue;
    
    // Major levels are always active if ShowMajorLevels is true
    if(level.isMajor && ShowMajorLevels)
    {
        return true;
    }
    
    // Broken levels are active if ShowBreakouts is true and within breakout period
    if(level.isBroken && ShowBreakouts && level.brokenSinceBar <= BreakoutBars)
    {
        return true;
    }
    
    // Regular levels are active if within required distance
    return (distancePips <= requiredDistancePips);
}

//+------------------------------------------------------------------+
//| Find Swing Points (H1)                                          |
//+------------------------------------------------------------------+
void FindSwingPoints(const string symbol, const double currentPrice)
{
    ArrayResize(poiLevels, 0);
    
    const ENUM_TIMEFRAMES timeframe = PERIOD_H1;
    int swingCount = 0;
    
    // Look for swing highs and lows
    for(int i = 3; i < LookbackBars && swingCount < MaxSwingLines * 2; i++)
    {
        const datetime candleTime = iTime(symbol, timeframe, i);
        const double high = iHigh(symbol, timeframe, i);
        const double low = iLow(symbol, timeframe, i);
        
        // Check for swing high
        if(high > iHigh(symbol, timeframe, i + 1) && 
           high > iHigh(symbol, timeframe, i + 2) &&
           high > iHigh(symbol, timeframe, i - 1) &&
           high > iHigh(symbol, timeframe, i - 2))
        {
            AddPOILevel(symbol, high, "SWING_HIGH", "H1", candleTime, (i <= 10));
            swingCount++;
        }
        
        // Check for swing low
        if(low < iLow(symbol, timeframe, i + 1) && 
           low < iLow(symbol, timeframe, i + 2) &&
           low < iLow(symbol, timeframe, i - 1) &&
           low < iLow(symbol, timeframe, i - 2))
        {
            AddPOILevel(symbol, low, "SWING_LOW", "H1", candleTime, (i <= 10));
            swingCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Find Support/Resistance Levels                                  |
//+------------------------------------------------------------------+
void FindSRLevels(const string symbol, const double currentPrice)
{
    const ENUM_TIMEFRAMES timeframes[] = {PERIOD_H1, PERIOD_H4};
    int srCount = 0;
    
    for(int tfIdx = 0; tfIdx < 2 && srCount < MaxSRLines * 2; tfIdx++)
    {
        const ENUM_TIMEFRAMES timeframe = timeframes[tfIdx];
        const string timeframeStr = (timeframe == PERIOD_H1) ? "H1" : "H4";
        const bool isMajor = (timeframe == PERIOD_H4);
        
        for(int i = 1; i < LookbackBars / 2 && srCount < MaxSRLines * 2; i++)
        {
            const double high = iHigh(symbol, timeframe, i);
            const double low = iLow(symbol, timeframe, i);
            const double range = high - low;
            
            // Look for consolidation zones (less than 0.5% range)
            if(range / currentPrice < 0.005)
            {
                // Add resistance level
                AddPOILevel(symbol, high, "RESISTANCE", timeframeStr, iTime(symbol, timeframe, i), isMajor);
                srCount++;
                
                // Add support level
                AddPOILevel(symbol, low, "SUPPORT", timeframeStr, iTime(symbol, timeframe, i), isMajor);
                srCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find Liquidity Points                                           |
//+------------------------------------------------------------------+
void FindLiquidityLevels(const string symbol, const double currentPrice)
{
    int liqCount = 0;
    
    // H4 liquidity (last 5 bars)
    for(int i = 1; i <= 5 && liqCount < MaxLiquidityLines; i++)
    {
        const bool isMajor = (i == 1);
        const datetime candleTime = iTime(symbol, PERIOD_H4, i);
        
        // H4 highs
        AddPOILevel(symbol, iHigh(symbol, PERIOD_H4, i), "LIQUIDITY_HIGH", "H4", candleTime, isMajor);
        liqCount++;
        
        // H4 lows
        AddPOILevel(symbol, iLow(symbol, PERIOD_H4, i), "LIQUIDITY_LOW", "H4", candleTime, isMajor);
        liqCount++;
    }
    
    // D1 liquidity (yesterday only)
    if(liqCount < MaxLiquidityLines * 2)
    {
        const datetime yesterdayTime = iTime(symbol, PERIOD_D1, 1);
        
        // Yesterday's high
        AddPOILevel(symbol, iHigh(symbol, PERIOD_D1, 1), "LIQUIDITY_HIGH", "D1", yesterdayTime, true);
        
        // Yesterday's low
        AddPOILevel(symbol, iLow(symbol, PERIOD_D1, 1), "LIQUIDITY_LOW", "D1", yesterdayTime, true);
    }
}

//+------------------------------------------------------------------+
//| Update Broken Levels Status                                     |
//+------------------------------------------------------------------+
void UpdateBrokenLevels(const string symbol, const double currentPrice)
{
    for(int i = 0; i < ArraySize(poiLevels); i++)
    {
        bool isResistanceType = (poiLevels[i].type == "RESISTANCE" || 
                                 poiLevels[i].type == "SWING_HIGH" || 
                                 poiLevels[i].type == "LIQUIDITY_HIGH");
        
        bool isSupportType = (poiLevels[i].type == "SUPPORT" || 
                              poiLevels[i].type == "SWING_LOW" || 
                              poiLevels[i].type == "LIQUIDITY_LOW");
        
        // Check if resistance is broken (price above level)
        if(isResistanceType && currentPrice > poiLevels[i].price && !poiLevels[i].isBroken)
        {
            poiLevels[i].isBroken = true;
            poiLevels[i].brokenSinceBar = 0;
        }
        
        // Check if support is broken (price below level)
        if(isSupportType && currentPrice < poiLevels[i].price && !poiLevels[i].isBroken)
        {
            poiLevels[i].isBroken = true;
            poiLevels[i].brokenSinceBar = 0;
        }
        
        // Increment broken counter if level is broken
        if(poiLevels[i].isBroken)
        {
            poiLevels[i].brokenSinceBar++;
        }
    }
}

//+------------------------------------------------------------------+
//| Draw All POI Levels on Chart                                    |
//+------------------------------------------------------------------+
void DrawAllPOILevels(const string symbol, const POILevel &levels[], const int count)
{
    if(!ShowPOIOnChart || count == 0) return;
    
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    const double trailingSLPips = GetCurrentTrailingSLPips(symbol, currentPrice, 0);
    const double requiredDistancePips = GetDynamicRequiredDistance(symbol, trailingSLPips);
    
    for(int i = 0; i < count; i++)
    {
        DrawSmartPOILine(symbol, levels[i], currentPrice, requiredDistancePips);
    }
    
    // Clean up old lines if needed
    if(AutoClearOldLines && TimeCurrent() - lastCleanupTime > 3600)
    {
        ClearOldPOILines(symbol);
        lastCleanupTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Draw Smart POI Line with Visual Enhancements                    |
//+------------------------------------------------------------------+
void DrawSmartPOILine(const string symbol, const POILevel &level, const double currentPrice, 
                      const double requiredDistancePips)
{
    if(!ShowPOIOnChart) return;
    
    const bool isActive = IsLevelActive(symbol, level, currentPrice, requiredDistancePips);
    
    // Skip inactive levels if ShowActiveOnly is true
    if(ShowActiveOnly && !isActive && !level.isMajor) return;
    
    // Determine line properties
    color lineColor = GetLevelColor(level);
    ENUM_LINE_STYLE lineStyle = GetLevelStyle(level, isActive);
    int lineWidth = GetLevelWidth(level, isActive);
    string lineText = GetLevelDescription(level, isActive);
    
    // Change to broken color if level is broken and recent
    if(level.isBroken && level.brokenSinceBar <= BreakoutBars)
    {
        lineColor = BrokenLevelColor;
    }
    
    // Create line name
    const string lineName = "POI_" + symbol + "_" + level.type + "_" + 
                           DoubleToString(level.price, 2) + "_" + 
                           IntegerToString(level.timestamp);
    
    // Draw trend line from POI candle to current position
    const datetime startTime = level.timestamp;
    const datetime endTime = TimeCurrent();
    
    // Create or update the line
    if(ObjectFind(0, lineName) < 0)
    {
        ObjectCreate(0, lineName, OBJ_TREND, 0, startTime, level.price, endTime, level.price);
    }
    else
    {
        // Update end point to current time
        ObjectMove(0, lineName, 1, endTime, level.price);
    }
    
    // Set line properties
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, lineName, OBJPROP_STYLE, lineStyle);
    ObjectSetInteger(0, lineName, OBJPROP_WIDTH, lineWidth);
    ObjectSetInteger(0, lineName, OBJPROP_RAY, false);
    ObjectSetString(0, lineName, OBJPROP_TEXT, lineText);
    ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
    ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
    
    // Add arrow at start point
    DrawPOIArrow(symbol, level, lineName, lineColor);
}

//+------------------------------------------------------------------+
//| Update All Chart Graphics                                        |
//+------------------------------------------------------------------+
void UpdateAllChartGraphics(const string symbol, const double currentPrice, const double profitPips = 0)
{
    if(!ShowPOIOnChart) return;
    
    // Get POI levels
    POILevel levels[];
    int count = GetAllPOILevels(symbol, currentPrice, levels);
    
    if(count > 0)
    {
        // Get required distance for display
        const double trailingSLPips = GetCurrentTrailingSLPips(symbol, currentPrice, profitPips);
        const double requiredDistancePips = GetDynamicRequiredDistance(symbol, trailingSLPips);
        
        // Draw all levels
        for(int i = 0; i < count; i++)
        {
            DrawSmartPOILine(symbol, levels[i], currentPrice, requiredDistancePips);
        }
        
        // Clean up old lines if needed
        if(AutoClearOldLines && TimeCurrent() - lastCleanupTime > 3600)
        {
            ClearOldPOILines(symbol);
            lastCleanupTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Update POI Display (Main Call from EA)                          |
//+------------------------------------------------------------------+
void UpdatePOIDisplay()
{
    if(!ShowPOIOnChart) return;
    
    // Rate limiting: Update every 30 seconds max
    static datetime lastUpdate = 0;
    if(TimeCurrent() - lastUpdate < 30) return;
    
    // Get current chart information
    const string symbol = Symbol();
    const double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Calculate profit pips
    const double profitPips = CalculateProfitPipsForSymbol(symbol);
    
    // Update POI graphics
    UpdateAllChartGraphics(symbol, price, profitPips);
    
    // Update timestamp
    lastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Validate POI for Trade Decision                                 |
//+------------------------------------------------------------------+
bool ValidatePOI(const string symbol, const double currentPrice, const bool isBuy, 
                const double profitPips, double &confidenceScore)
{
    if(!EnablePOIValidation)
    {
        confidenceScore = 100.0;
        return true;
    }
    
    confidenceScore = 100.0;
    
    // Get current trailing SL and required distance
    const double trailingSLPips = GetCurrentTrailingSLPips(symbol, currentPrice, profitPips);
    const double requiredDistancePips = GetDynamicRequiredDistance(symbol, trailingSLPips);
    
    // Update all levels
    FindSwingPoints(symbol, currentPrice);
    FindSRLevels(symbol, currentPrice);
    FindLiquidityLevels(symbol, currentPrice);
    UpdateBrokenLevels(symbol, currentPrice);
    
    // Check each level for conflicts
    const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    for(int i = 0; i < ArraySize(poiLevels); i++)
    {
        const double distancePips = MathAbs(currentPrice - poiLevels[i].price) / pointValue;
        
        // Skip if too far away
        if(distancePips > requiredDistancePips * 2) continue;
        
        // Apply POI validation rules
        confidenceScore += CalculatePOIScore(symbol, poiLevels[i], currentPrice, 
                                           distancePips, requiredDistancePips, isBuy);
    }
    
    // Clamp confidence score
    confidenceScore = MathMax(0.0, MathMin(100.0, confidenceScore));
    
    return (confidenceScore >= 70.0);
}

//+------------------------------------------------------------------+
//| Quick POI Check for Fast Validation                            |
//+------------------------------------------------------------------+
bool QuickPOICheck(const string symbol, const double currentPrice, const bool isBuy, const double profitPips = 0)
{
    double confidence;
    return ValidatePOI(symbol, currentPrice, isBuy, profitPips, confidence);
}

//+------------------------------------------------------------------+
//| Clear Old POI Lines                                             |
//+------------------------------------------------------------------+
void ClearOldPOILines(const string symbol)
{
    if(!AutoClearOldLines) return;
    
    const datetime cutoffTime = TimeCurrent() - (ClearLinesAfterBars * PeriodSeconds(PERIOD_H1));
    const string prefix = "POI_" + symbol + "_";
    
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        const string name = ObjectName(0, i);
        if(StringFind(name, prefix) >= 0)
        {
            // Get line creation time from name
            int underscorePos = StringFind(name, "_", StringFind(name, "_", 
                              StringFind(name, "_") + 1) + 1);
            underscorePos = StringFind(name, "_", underscorePos + 1);
            
            if(underscorePos > 0)
            {
                const string timeStr = StringSubstr(name, underscorePos + 1);
                const datetime lineTime = (datetime)StringToInteger(timeStr);
                
                if(lineTime < cutoffTime)
                {
                    ObjectDelete(0, name);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Remove All POI Objects from Chart                               |
//+------------------------------------------------------------------+
void RemoveAllPOIObjects(const string symbol)
{
    const string prefix = "POI_" + symbol + "_";
    
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        const string name = ObjectName(0, i);
        if(StringFind(name, prefix) >= 0)
        {
            ObjectDelete(0, name);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Profit Pips for Symbol                                |
//+------------------------------------------------------------------+
double CalculateProfitPipsForSymbol(const string symbol)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == symbol)
        {
            const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            const double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            const long posType = PositionGetInteger(POSITION_TYPE);
            
            if(posType == POSITION_TYPE_BUY)
            {
                return (currentPrice - openPrice) / point;
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                return (openPrice - currentPrice) / point;
            }
        }
    }
    
    return 0.0;  // No positions
}

//+------------------------------------------------------------------+
//| Helper Functions                                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Add POI Level to Array                                          |
//+------------------------------------------------------------------+
void AddPOILevel(const string symbol, const double price, const string type, 
                const string timeframe, const datetime timestamp, const bool isMajor)
{
    POILevel level;
    level.price = price;
    level.type = type;
    level.timeframe = timeframe;
    level.timestamp = timestamp;
    level.isMajor = isMajor;
    level.isBroken = false;
    level.brokenSinceBar = 0;
    
    int size = ArraySize(poiLevels);
    ArrayResize(poiLevels, size + 1);
    poiLevels[size] = level;
}

//+------------------------------------------------------------------+
//| Get Level Color                                                 |
//+------------------------------------------------------------------+
color GetLevelColor(const POILevel &level)
{
    if(level.type == "RESISTANCE") return ResistanceColor;
    else if(level.type == "SUPPORT") return SupportColor;
    else if(level.type == "SWING_HIGH") return SwingHighColor;
    else if(level.type == "SWING_LOW") return SwingLowColor;
    else if(level.type == "LIQUIDITY_HIGH") return LiquidityHighColor;
    else if(level.type == "LIQUIDITY_LOW") return LiquidityLowColor;
    else return clrGray;
}

//+------------------------------------------------------------------+
//| Get Level Style                                                 |
//+------------------------------------------------------------------+
ENUM_LINE_STYLE GetLevelStyle(const POILevel &level, const bool isActive)
{
    if(level.isMajor) return MajorLineStyle;
    else if(level.isBroken && level.brokenSinceBar <= BreakoutBars) return BrokenLineStyle;
    else if(isActive) return ActiveLineStyle;
    else return InactiveLineStyle;
}

//+------------------------------------------------------------------+
//| Get Level Width                                                 |
//+------------------------------------------------------------------+
int GetLevelWidth(const POILevel &level, const bool isActive)
{
    if(level.isMajor) return MajorLineWidth;
    else if(level.isBroken && level.brokenSinceBar <= BreakoutBars) return BrokenLineWidth;
    else if(isActive) return ActiveLineWidth;
    else return InactiveLineWidth;
}

//+------------------------------------------------------------------+
//| Get Level Description                                           |
//+------------------------------------------------------------------+
string GetLevelDescription(const POILevel &level, const bool isActive)
{
    string status = "";
    
    if(level.isMajor) status = "MAJOR";
    else if(level.isBroken && level.brokenSinceBar <= BreakoutBars) status = "BROKEN";
    else if(isActive) status = "ACTIVE";
    
    return level.type + " (" + level.timeframe + ") - " + status;
}

//+------------------------------------------------------------------+
//| Draw POI Arrow at Start Point                                   |
//+------------------------------------------------------------------+
void DrawPOIArrow(const string symbol, const POILevel &level, const string lineName, const color arrowColor)
{
    string arrowName = lineName + "_ARROW";
    
    if(ObjectFind(0, arrowName) < 0)
    {
        bool isResistanceType = (level.type == "RESISTANCE" || 
                                 level.type == "SWING_HIGH" || 
                                 level.type == "LIQUIDITY_HIGH");
        
        if(isResistanceType)
        {
            ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, level.timestamp, level.price);
        }
        else
        {
            ObjectCreate(0, arrowName, OBJ_ARROW_UP, 0, level.timestamp, level.price);
        }
        
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
    }
}

//+------------------------------------------------------------------+
//| Calculate POI Score for Validation                             |
//+------------------------------------------------------------------+
double CalculatePOIScore(const string symbol, const POILevel &level, const double currentPrice,
                        const double distancePips, const double requiredDistancePips, const bool isBuy)
{
    double scoreAdjustment = 0.0;
    
    if(isBuy)
    {
        // Buying near resistance is bad
        if((level.type == "RESISTANCE" || level.type == "SWING_HIGH" || level.type == "LIQUIDITY_HIGH") &&
           currentPrice < level.price && distancePips < requiredDistancePips)
        {
            scoreAdjustment -= 30.0;
        }
        
        // Buying above broken resistance is good
        if((level.type == "RESISTANCE" || level.type == "LIQUIDITY_HIGH") &&
           level.isBroken && currentPrice > level.price && distancePips < requiredDistancePips * 0.5)
        {
            scoreAdjustment += 15.0;
        }
    }
    else
    {
        // Selling near support is bad
        if((level.type == "SUPPORT" || level.type == "SWING_LOW" || level.type == "LIQUIDITY_LOW") &&
           currentPrice > level.price && distancePips < requiredDistancePips)
        {
            scoreAdjustment -= 30.0;
        }
        
        // Selling below broken support is good
        if((level.type == "SUPPORT" || level.type == "LIQUIDITY_LOW") &&
           level.isBroken && currentPrice < level.price && distancePips < requiredDistancePips * 0.5)
        {
            scoreAdjustment += 15.0;
        }
    }
    
    return scoreAdjustment;
}

//+------------------------------------------------------------------+
//| Get POI System Status                                           |
//+------------------------------------------------------------------+
string GetPOISystemStatus(const string symbol)
{
    const double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    POILevel levels[];
    int count = GetAllPOILevels(symbol, currentPrice, levels);
    
    int activeCount = 0;
    int brokenCount = 0;
    int majorCount = 0;
    
    for(int i = 0; i < count; i++)
    {
        if(levels[i].isMajor) majorCount++;
        if(levels[i].isBroken) brokenCount++;
        
        const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
        const double distancePips = MathAbs(currentPrice - levels[i].price) / pointValue;
        const double trailingSLPips = GetCurrentTrailingSLPips(symbol, currentPrice, 0);
        const double requiredDistancePips = GetDynamicRequiredDistance(symbol, trailingSLPips);
        
        if(distancePips <= requiredDistancePips) activeCount++;
    }
    
    return StringFormat("POI System: %d levels total | %d active | %d major | %d broken", 
                       count, activeCount, majorCount, brokenCount);
}