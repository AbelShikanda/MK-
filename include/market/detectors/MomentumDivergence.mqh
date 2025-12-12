//+------------------------------------------------------------------+
//| RSI Divergence Tracker Module (MQL5 Version) - Enhanced         |
//| Now includes comprehensive momentum divergence detection        |
//+------------------------------------------------------------------+

#include "../../config/structures.mqh"
#include "../../config/inputs.mqh"

// ================================================================
// CONFIGURABLE PARAMETERS - ADJUST THESE TO YOUR PREFERENCES
// ================================================================

// Minimum score threshold for CheckMomentumDivergence
input double  Min_Divergence_Score = 60.0;  // Minimum score to return true in CheckMomentumDivergence()

// ================================================================
// END OF CONFIGURABLE PARAMETERS
// ================================================================

// Global variables
int rsiDivergenceHandle = INVALID_HANDLE;
bool divergenceDebugMode = Enable_Debug_Mode;

//+------------------------------------------------------------------+
//| ENHANCED: Check Momentum Divergence                              |
//| Uses full divergence analysis instead of just 2-bar comparison   |
//| Parameters: symbol, timeframe, isUptrend                         |
//| Returns: true if strong divergence detected                      |
//+------------------------------------------------------------------+
bool CheckMomentumDivergence(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isUptrend)
{
    // First check for divergence using the full system
    DivergenceSignal signal = CheckDivergence(symbol, timeframe);
    
    if(!signal.exists) 
    {
        // No divergence found by full system
        if(divergenceDebugMode)
            PrintFormat("CheckMomentumDivergence: No divergence found for %s on %s", 
                       symbol, EnumToString(timeframe));
        return false;
    }
    
    // Check if divergence direction matches what we're looking for
    // isUptrend = true: we're looking for bearish divergence (to signal downtrend)
    // isUptrend = false: we're looking for bullish divergence (to signal uptrend)
    
    bool directionMatch = false;
    if(isUptrend)
    {
        // Looking for BEARISH divergence (price up, momentum down)
        directionMatch = !signal.bullish; // Bearish divergence = not bullish
    }
    else
    {
        // Looking for BULLISH divergence (price down, momentum up)
        directionMatch = signal.bullish;
    }
    
    if(!directionMatch)
    {
        if(divergenceDebugMode)
            PrintFormat("CheckMomentumDivergence: Divergence exists but wrong direction. Signal: %s, Looking for: %s",
                       signal.bullish ? "BULLISH" : "BEARISH", 
                       isUptrend ? "BEARISH" : "BULLISH");
        return false;
    }
    
    // Check if score meets minimum threshold
    if(signal.score < Min_Divergence_Score)
    {
        if(divergenceDebugMode)
            PrintFormat("CheckMomentumDivergence: Divergence score too low: %.1f < %.1f",
                       signal.score, Min_Divergence_Score);
        return false;
    }
    
    // Check if divergence is recent enough
    int barsSince = BarsSince(signal.latestTime);
    if(barsSince > Aging_Bars)
    {
        if(divergenceDebugMode)
            PrintFormat("CheckMomentumDivergence: Divergence too old: %d bars", barsSince);
        return false;
    }
    
    if(divergenceDebugMode)
        PrintFormat("CheckMomentumDivergence: STRONG %s divergence detected! Score: %.1f, Type: %s, Age: %d bars",
                   signal.bullish ? "BULLISH" : "BEARISH", 
                   signal.score, signal.type, barsSince);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Divergence Strength Score (0-1.0)                           |
//| Enhanced version for CalculateReversalConfidence                |
//+------------------------------------------------------------------+
double GetDivergenceStrengthScore(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isUptrend)
{
    DivergenceSignal signal = CheckDivergence(symbol, timeframe);
    
    if(!signal.exists) return 0.0;
    
    // Check direction match
    bool directionMatch;
    if(isUptrend)
        directionMatch = !signal.bullish; // Bearish for uptrend reversal
    else
        directionMatch = signal.bullish;  // Bullish for downtrend reversal
    
    if(!directionMatch) return 0.0;
    
    // Calculate normalized score (0.0 to 1.0)
    double normalizedScore = signal.score / Max_Score;
    
    // Apply age decay
    int barsSince = BarsSince(signal.latestTime);
    double ageFactor = 1.0;
    
    if(Enable_Auto_Decay)
    {
        if(barsSince < Fresh_Bars) ageFactor = Fresh_Factor;
        else if(barsSince < Recent_Bars) ageFactor = Recent_Factor;
        else if(barsSince < Aging_Bars) ageFactor = Aging_Factor;
        else if(barsSince < Old_Bars) ageFactor = Old_Factor;
        else ageFactor = Very_Old_Factor;
    }
    
    double finalScore = normalizedScore * ageFactor;
    
    if(divergenceDebugMode)
        PrintFormat("GetDivergenceStrengthScore: %s %s on %s - Raw: %.2f, AgeFactor: %.2f, Final: %.2f",
                   signal.type, signal.bullish ? "BULLISH" : "BEARISH",
                   EnumToString(timeframe), normalizedScore, ageFactor, finalScore);
    
    return MathMin(1.0, MathMax(0.0, finalScore));
}

//+------------------------------------------------------------------+
//| Initialize Divergence Tracker                                    |
//+------------------------------------------------------------------+
void InitDivergenceTracker()
{
    ArrayResize(highSwingPoints, 0);
    ArrayResize(lowSwingPoints, 0);
    currentDivergence.exists = false;
    currentDivergence.firstDetected = 0;
    
    // Set debug mode from parameter
    divergenceDebugMode = Enable_Debug_Mode;
    
    Print("=== RSI DIVERGENCE TRACKER INITIALIZED (ENHANCED) ===");
    Print("Configuration:");
    PrintFormat("  RSI Period: %d, Applied Price: %s", RSI_Period, EnumToString(RSI_AppliedPrice));
    PrintFormat("  Swing Period: %d, Bars to Check: %d", Swing_Period, Bars_To_Check);
    PrintFormat("  Default Timeframe: %s", EnumToString(Default_Timeframe));
    PrintFormat("  Min Divergence Score: %.1f", Min_Divergence_Score);
    PrintFormat("  Debug Mode: %s", divergenceDebugMode ? "ON" : "OFF");
    Print("  Enhanced CheckMomentumDivergence() is now using full swing analysis");
}

//+------------------------------------------------------------------+
//| Update Swing Points                                              |
//+------------------------------------------------------------------+
void UpdateSwingPoints(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
{
    int barsToCheck = Bars_To_Check;
    int swingPeriod = Swing_Period; // Look at bars on each side
    
    double highs[], lows[], rsiValues[];
    ArrayResize(highs, barsToCheck);
    ArrayResize(lows, barsToCheck);
    ArrayResize(rsiValues, barsToCheck);
    
    // MQL5: Copy data using CopyHigh, CopyLow, CopyBuffer
    int copiedHighs = CopyHigh(symbol, timeframe, 0, barsToCheck, highs);
    int copiedLows = CopyLow(symbol, timeframe, 0, barsToCheck, lows);
    
    // Get RSI values
    if(rsiDivergenceHandle == INVALID_HANDLE) {
        rsiDivergenceHandle = iRSI(symbol, timeframe, RSI_Period, RSI_AppliedPrice);
    }
    
    if(rsiDivergenceHandle != INVALID_HANDLE) {
        int copiedRSI = CopyBuffer(rsiDivergenceHandle, 0, 0, barsToCheck, rsiValues);
        
        if(copiedRSI < barsToCheck) {
            if(divergenceDebugMode)
                Print("Error copying RSI data: ", copiedRSI);
            return;
        }
    } else {
        if(divergenceDebugMode)
            Print("Error creating RSI handle");
        return;
    }
    
    if(copiedHighs < barsToCheck || copiedLows < barsToCheck) {
        if(divergenceDebugMode)
            Print("Error copying price data: Highs=", copiedHighs, ", Lows=", copiedLows);
        return;
    }
    
    // Get times array for bar timestamps
    datetime times[];
    if(CopyTime(symbol, timeframe, 0, barsToCheck, times) < barsToCheck) {
        if(divergenceDebugMode)
            Print("Error copying time data");
        return;
    }
    
    // Find swing highs
    ArrayResize(highSwingPoints, 0);
    for(int i = swingPeriod; i < barsToCheck - swingPeriod; i++) {
        bool isHigh = true;
        
        // Check if this is highest among surrounding bars
        for(int j = i - swingPeriod; j <= i + swingPeriod; j++) {
            if(j == i) continue;
            if(highs[i] <= highs[j]) {
                isHigh = false;
                break;
            }
        }
        
        if(isHigh) {
            int size = ArraySize(highSwingPoints);
            ArrayResize(highSwingPoints, size + 1);
            highSwingPoints[size].time = times[i];
            highSwingPoints[size].price = highs[i];
            highSwingPoints[size].rsi = rsiValues[i];
            highSwingPoints[size].type = 1;
            highSwingPoints[size].barIndex = i;
            
            // Calculate strength based on height difference
            double leftDiff = MathAbs(highs[i] - highs[i-swingPeriod]);
            double rightDiff = MathAbs(highs[i] - highs[i+swingPeriod]);
            highSwingPoints[size].strength = int(MathMin(leftDiff + rightDiff, Strength_Limit));
        }
    }
    
    // Find swing lows
    ArrayResize(lowSwingPoints, 0);
    for(int i = swingPeriod; i < barsToCheck - swingPeriod; i++) {
        bool isLow = true;
        
        // Check if this is lowest among surrounding bars
        for(int j = i - swingPeriod; j <= i + swingPeriod; j++) {
            if(j == i) continue;
            if(lows[i] >= lows[j]) {
                isLow = false;
                break;
            }
        }
        
        if(isLow) {
            int size = ArraySize(lowSwingPoints);
            ArrayResize(lowSwingPoints, size + 1);
            lowSwingPoints[size].time = times[i];
            lowSwingPoints[size].price = lows[i];
            lowSwingPoints[size].rsi = rsiValues[i];
            lowSwingPoints[size].type = -1;
            lowSwingPoints[size].barIndex = i;
            
            // Calculate strength based on depth difference
            double leftDiff = MathAbs(lows[i] - lows[i-swingPeriod]);
            double rightDiff = MathAbs(lows[i] - lows[i+swingPeriod]);
            lowSwingPoints[size].strength = int(MathMin(leftDiff + rightDiff, Strength_Limit));
        }
    }
    
    // Log swing points found
    if(divergenceDebugMode) {
        PrintFormat("SWING POINTS [%s %s]:", symbol, EnumToString(timeframe));
        PrintFormat("  Highs found: %d, Lows found: %d", 
                   ArraySize(highSwingPoints), ArraySize(lowSwingPoints));
    }
}

//+------------------------------------------------------------------+
//| Check for Divergence                                             |
//+------------------------------------------------------------------+
DivergenceSignal CheckDivergence(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
{
    // Use default timeframe if not specified
    if(timeframe == PERIOD_CURRENT) timeframe = Default_Timeframe;
    
    DivergenceSignal signal;
    signal.exists = false;
    signal.score = 0;
    signal.firstDetected = 0;
    
    UpdateSwingPoints(symbol, timeframe);
    
    int numHighs = ArraySize(highSwingPoints);
    int numLows = ArraySize(lowSwingPoints);
    
    if(numHighs < 2 && numLows < 2) {
        if(divergenceDebugMode) {
            Print("  Insufficient swing points for divergence check (need at least 2 of either highs or lows)");
        }
        return signal;
    }
    
    // Check for BEARISH divergence (price makes higher high, RSI makes lower high)
    if(numHighs >= 2) {
        SwingPoint latestHigh = highSwingPoints[0];
        SwingPoint previousHigh = highSwingPoints[1];
        
        // Price: Higher High, RSI: Lower High = BEARISH DIVERGENCE
        if(latestHigh.price > previousHigh.price && latestHigh.rsi < previousHigh.rsi) {
            signal.exists = true;
            signal.bullish = false;
            signal.type = "Regular";
            signal.latestTime = latestHigh.time;
            signal.priceLevel = latestHigh.price;
            signal.rsiLevel = latestHigh.rsi;
            signal.firstDetected = TimeCurrent(); // First detection time
            
            // Calculate divergence score
            double priceChangePercent = ((latestHigh.price - previousHigh.price) / previousHigh.price) * 100;
            double rsiChangePercent = ((previousHigh.rsi - latestHigh.rsi) / previousHigh.rsi) * 100;
            
            // Stronger when RSI drops more relative to price rise
            signal.score = MathMin(Max_Score, rsiChangePercent * RSI_Change_Multiplier);
            signal.strength = latestHigh.strength;
            signal.confirmations = 1;
            
            if(divergenceDebugMode) {
                Print("========================================");
                PrintFormat("🎯 REGULAR BEARISH DIVERGENCE DETECTED!");
                PrintFormat("   Symbol: %s, Timeframe: %s", symbol, EnumToString(timeframe));
                PrintFormat("   Price Change: %.5f → %.5f (↑%.3f%%)", 
                           previousHigh.price, latestHigh.price, priceChangePercent);
                PrintFormat("   RSI Change: %.1f → %.1f (↓%.2f%%)", 
                           previousHigh.rsi, latestHigh.rsi, rsiChangePercent);
                PrintFormat("   Strength: %d/3, Score: %.1f/100", signal.strength, signal.score);
                Print("========================================");
            }
        }
    }
    
    // Check for BULLISH divergence (price makes lower low, RSI makes higher low)
    if(numLows >= 2) {
        SwingPoint latestLow = lowSwingPoints[0];
        SwingPoint previousLow = lowSwingPoints[1];
        
        // Price: Lower Low, RSI: Higher Low = BULLISH DIVERGENCE
        if(latestLow.price < previousLow.price && latestLow.rsi > previousLow.rsi) {
            signal.exists = true;
            signal.bullish = true;
            signal.type = "Regular";
            signal.latestTime = latestLow.time;
            signal.priceLevel = latestLow.price;
            signal.rsiLevel = latestLow.rsi;
            signal.firstDetected = TimeCurrent();
            
            // Calculate divergence score
            double priceChangePercent = ((previousLow.price - latestLow.price) / previousLow.price) * 100;
            double rsiChangePercent = ((latestLow.rsi - previousLow.rsi) / previousLow.rsi) * 100;
            
            // Stronger when RSI rises more relative to price drop
            signal.score = MathMin(Max_Score, rsiChangePercent * RSI_Change_Multiplier);
            signal.strength = latestLow.strength;
            signal.confirmations = 1;
            
            if(divergenceDebugMode) {
                Print("========================================");
                PrintFormat("🎯 REGULAR BULLISH DIVERGENCE DETECTED!");
                PrintFormat("   Symbol: %s, Timeframe: %s", symbol, EnumToString(timeframe));
                PrintFormat("   Price Change: %.5f → %.5f (↓%.3f%%)", 
                           previousLow.price, latestLow.price, priceChangePercent);
                PrintFormat("   RSI Change: %.1f → %.1f (↑%.2f%%)", 
                           previousLow.rsi, latestLow.rsi, rsiChangePercent);
                PrintFormat("   Strength: %d/%d, Score: %.1f/%d", signal.strength, Strength_Limit, signal.score, Max_Score);
                Print("========================================");
            }
        }
    }
    
    // Check for hidden divergences (trend continuation) - only if no regular divergence found
    if(!signal.exists) {
        if(numHighs >= 2) {
            SwingPoint latestHigh = highSwingPoints[0];
            SwingPoint previousHigh = highSwingPoints[1];
            
            // Hidden BEARISH: Price Lower High, RSI Higher High
            if(latestHigh.price < previousHigh.price && latestHigh.rsi > previousHigh.rsi) {
                signal.exists = true;
                signal.bullish = false;
                signal.type = "Hidden";
                signal.latestTime = latestHigh.time;
                signal.priceLevel = latestHigh.price;
                signal.rsiLevel = latestHigh.rsi;
                signal.firstDetected = TimeCurrent();
                signal.score = Hidden_Divergence_Score; // Hidden divergences are weaker
                signal.confirmations = 1;
                
                if(divergenceDebugMode) {
                    Print("========================================");
                    PrintFormat("⚠️ HIDDEN BEARISH DIVERGENCE DETECTED (Continuation Signal)");
                    PrintFormat("   Price: Lower High (%.5f → %.5f)", previousHigh.price, latestHigh.price);
                    PrintFormat("   RSI: Higher High (%.1f → %.1f)", previousHigh.rsi, latestHigh.rsi);
                    PrintFormat("   Score: %.1f/%d", signal.score, Max_Score);
                    Print("========================================");
                }
            }
        }
        
        if(numLows >= 2 && !signal.exists) {
            SwingPoint latestLow = lowSwingPoints[0];
            SwingPoint previousLow = lowSwingPoints[1];
            
            // Hidden BULLISH: Price Higher Low, RSI Lower Low
            if(latestLow.price > previousLow.price && latestLow.rsi < previousLow.rsi) {
                signal.exists = true;
                signal.bullish = true;
                signal.type = "Hidden";
                signal.latestTime = latestLow.time;
                signal.priceLevel = latestLow.price;
                signal.rsiLevel = latestLow.rsi;
                signal.firstDetected = TimeCurrent();
                signal.score = Hidden_Divergence_Score;
                signal.confirmations = 1;
                
                if(divergenceDebugMode) {
                    Print("========================================");
                    PrintFormat("⚠️ HIDDEN BULLISH DIVERGENCE DETECTED (Continuation Signal)");
                    PrintFormat("   Price: Higher Low (%.5f → %.5f)", previousLow.price, latestLow.price);
                    PrintFormat("   RSI: Lower Low (%.1f → %.1f)", previousLow.rsi, latestLow.rsi);
                    PrintFormat("   Score: %.1f/%d", signal.score, Max_Score);
                    Print("========================================");
                }
            }
        }
    }
    
    // Update current divergence
    if(signal.exists) {
        if(currentDivergence.exists && 
           signal.bullish == currentDivergence.bullish &&
           MathAbs(signal.priceLevel - currentDivergence.priceLevel) < 0.0001) {
            // Same divergence getting stronger
            currentDivergence.confirmations++;
            currentDivergence.score = MathMax(currentDivergence.score, signal.score);
            currentDivergence.latestTime = signal.latestTime;
        } else {
            // New divergence
            currentDivergence = signal;
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get Divergence Score for Trade Direction                         |
//+------------------------------------------------------------------+
double GetDivergenceScore(bool forBuyTrade)
{
    if(!currentDivergence.exists) {
        return Neutral_Score; // Neutral score
    }
    
    double ageFactor = 1.0;
    int barsSince = BarsSince(currentDivergence.latestTime);
    
    // Decay score based on age (divergence gets less relevant over time)
    if(!Enable_Auto_Decay) {
        ageFactor = 1.0;
    } else {
        if(barsSince < Fresh_Bars) ageFactor = Fresh_Factor;
        else if(barsSince < Recent_Bars) ageFactor = Recent_Factor;
        else if(barsSince < Aging_Bars) ageFactor = Aging_Factor;
        else if(barsSince < Old_Bars) ageFactor = Old_Factor;
        else ageFactor = Very_Old_Factor;
    }
    
    double rawScore = currentDivergence.score * ageFactor;
    
    // Calculate directional score
    double directionalScore;
    if(forBuyTrade) {
        if(currentDivergence.bullish) {
            // Bullish divergence supports BUY trades
            directionalScore = Neutral_Score + (rawScore / 2); // Neutral + 0-50 range
        } else {
            // Bearish divergence opposes BUY trades
            directionalScore = Neutral_Score - (rawScore / 2); // Neutral - 0-50 range
        }
    } else {
        if(!currentDivergence.bullish) {
            // Bearish divergence supports SELL trades
            directionalScore = Neutral_Score + (rawScore / 2); // Neutral + 0-50 range
        } else {
            // Bullish divergence opposes SELL trades
            directionalScore = Neutral_Score - (rawScore / 2); // Neutral - 0-50 range
        }
    }
    
    // Clamp to 0-100 range
    directionalScore = MathMax(0, MathMin(Max_Score, directionalScore));
    
    return directionalScore;
}

//+------------------------------------------------------------------+
//| Get Trade Direction Score (Integration Helper)                   |
//+------------------------------------------------------------------+
double GetTradeDirectionScore(string symbol, bool isBuy)
{
    // Always check for new divergence first
    CheckDivergence(symbol, Default_Timeframe);
    
    // Get the score
    double score = GetDivergenceScore(isBuy);
    
    return score;
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
int BarsSince(datetime time)
{
    datetime times[];
    if(CopyTime(_Symbol, PERIOD_CURRENT, 0, Max_Bars_Since, times) > 0) {
        for(int i = 0; i < ArraySize(times); i++) {
            if(times[i] <= time) {
                return i;
            }
        }
    }
    return Max_Bars_Since; // Max value
}

string GetDivergenceSummary()
{
    if(!currentDivergence.exists) return "No active divergence";
    
    int barsSince = BarsSince(currentDivergence.latestTime);
    datetime firstDetected = currentDivergence.firstDetected;
    
    return StringFormat("%s %s Divergence | Score: %.1f/%d | Confirmations: %d | Age: %d bars",
                       currentDivergence.type,
                       currentDivergence.bullish ? "BULLISH" : "BEARISH",
                       currentDivergence.score, Max_Score,
                       currentDivergence.confirmations,
                       barsSince);
}

void PrintDivergenceStatus()
{
    if(!currentDivergence.exists) {
        Print("=== NO ACTIVE DIVERGENCE ===");
        return;
    }
    
    Print("=== ACTIVE DIVERGENCE STATUS ===");
    PrintFormat("  Type: %s %s", currentDivergence.type, 
               currentDivergence.bullish ? "BULLISH" : "BEARISH");
    PrintFormat("  Current Score: %.1f/%d", currentDivergence.score, Max_Score);
    PrintFormat("  Confirmations: %d", currentDivergence.confirmations);
    
    int barsSince = BarsSince(currentDivergence.latestTime);
    PrintFormat("  Age: %d bars since last confirmation", barsSince);
}

//+------------------------------------------------------------------+
//| Debug Mode Control                                               |
//+------------------------------------------------------------------+
void SetDivergenceDebugMode(bool enable)
{
    divergenceDebugMode = enable;
    PrintFormat("Divergence Debug Mode: %s", enable ? "ON" : "OFF");
}

bool GetDivergenceDebugMode()
{
    return divergenceDebugMode;
}

//+------------------------------------------------------------------+
//| Deinitialize - Clean up handles                                  |
//+------------------------------------------------------------------+
void DeinitDivergenceTracker()
{
    Print("=== Divergence Tracker Shutting Down ===");
    
    if(rsiDivergenceHandle != INVALID_HANDLE) {
        IndicatorRelease(rsiDivergenceHandle);
        rsiDivergenceHandle = INVALID_HANDLE;
    }
    
    PrintDivergenceStatus();
}