//+------------------------------------------------------------------+
//| Pattern Divergence Detector (Strictly Patterns)                 |
//| Returns a score (0-100) based on candlestick pattern strength   |
//| at key points of interest (support/resistance)                  |
//+------------------------------------------------------------------+
double GetPatternDivergenceScore(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isUptrend)
{
    // Start neutral - 50 means no clear pattern
    double patternScore = 50.0;
    
    // Get recent price action
    double open[5], high[5], low[5], close[5];
    for(int i = 0; i < 5; i++)
    {
        open[i] = iOpen(symbol, timeframe, i);
        high[i] = iHigh(symbol, timeframe, i);
        low[i] = iLow(symbol, timeframe, i);
        close[i] = iClose(symbol, timeframe, i);
    }
    
    // Identify key points of interest
    double recentHigh = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, 20, 0));
    double recentLow = iLow(symbol, timeframe, iLowest(symbol, timeframe, MODE_LOW, 20, 0));
    
    // Check if price is near key levels (within 2%)
    bool nearResistance = (close[0] >= recentHigh * 0.98 && close[0] <= recentHigh * 1.02);
    bool nearSupport = (close[0] >= recentLow * 0.98 && close[0] <= recentLow * 1.02);
    
    // BEARISH PATTERN DETECTION (for uptrend reversal)
    if(isUptrend)
    {
        double bearishStrength = 0.0;
        
        // 1. PRIMARY REVERSAL PATTERNS (Strong signals at resistance)
        if(nearResistance)
        {
            // Evening Star at resistance (STRONGEST: -25 points)
            if(CheckEveningStar(open, high, low, close))
            {
                patternScore -= 25.0;
                Print("STRONG: Evening Star at resistance");
            }
            // Shooting Star at resistance (STRONG: -20 points)
            else if(CheckShootingStar(open, high, low, close, 1))
            {
                patternScore -= 20.0;
                Print("STRONG: Shooting Star at resistance");
            }
            // Bearish Engulfing at resistance (STRONG: -18 points)
            else if(CheckBearishEngulfing(open, high, low, close))
            {
                patternScore -= 18.0;
                Print("STRONG: Bearish Engulfing at resistance");
            }
            // Gravestone Doji at resistance (MEDIUM: -15 points)
            else if(CheckGravestoneDoji(open, high, low, close, 1))
            {
                patternScore -= 15.0;
                Print("MEDIUM: Gravestone Doji at resistance");
            }
        }
        
        // 2. SECONDARY REVERSAL PATTERNS (Moderate signals)
        // Dark Cloud Cover (MEDIUM: -15 points)
        if(CheckDarkCloudCover(open, high, low, close))
        {
            patternScore -= 15.0;
            Print("MEDIUM: Dark Cloud Cover");
        }
        
        // Bearish Harami (WEAK: -8 points)
        if(CheckBearishHarami(open, high, low, close))
        {
            patternScore -= 8.0;
            Print("WEAK: Bearish Harami");
        }
        
        // Three Black Crows (STRONG: -22 points if consecutive)
        if(CheckThreeBlackCrows(open, high, low, close))
        {
            patternScore -= 22.0;
            Print("STRONG: Three Black Crows");
        }
    }
    // BULLISH PATTERN DETECTION (for downtrend reversal)
    else
    {
        // 1. PRIMARY REVERSAL PATTERNS (Strong signals at support)
        if(nearSupport)
        {
            // Morning Star at support (STRONGEST: +25 points)
            if(CheckMorningStar(open, high, low, close))
            {
                patternScore += 25.0;
                Print("STRONG: Morning Star at support");
            }
            // Hammer at support (STRONG: +20 points)
            else if(CheckHammer(open, high, low, close, 1))
            {
                patternScore += 20.0;
                Print("STRONG: Hammer at support");
            }
            // Bullish Engulfing at support (STRONG: +18 points)
            else if(CheckBullishEngulfing(open, high, low, close))
            {
                patternScore += 18.0;
                Print("STRONG: Bullish Engulfing at support");
            }
            // Dragonfly Doji at support (MEDIUM: +15 points)
            else if(CheckDragonflyDoji(open, high, low, close, 1))
            {
                patternScore += 15.0;
                Print("MEDIUM: Dragonfly Doji at support");
            }
        }
        
        // 2. SECONDARY REVERSAL PATTERNS (Moderate signals)
        // Piercing Pattern (MEDIUM: +15 points)
        if(CheckPiercingPattern(open, high, low, close))
        {
            patternScore += 15.0;
            Print("MEDIUM: Piercing Pattern");
        }
        
        // Bullish Harami (WEAK: +8 points)
        if(CheckBullishHarami(open, high, low, close))
        {
            patternScore += 8.0;
            Print("WEAK: Bullish Harami");
        }
        
        // Three White Soldiers (STRONG: +22 points if consecutive)
        if(CheckThreeWhiteSoldiers(open, high, low, close))
        {
            patternScore += 22.0;
            Print("STRONG: Three White Soldiers");
        }
    }
    
    // Apply pattern multiplier based on how many patterns align
    int patternCount = CountPatternConfirmations(open, high, low, close, isUptrend);
    if(patternCount >= 2)
    {
        // Multiple patterns increase confidence
        double multiplier = 1.0 + (patternCount * 0.1);
        if(isUptrend)
            patternScore = 50.0 + ((patternScore - 50.0) * multiplier);
        else
            patternScore = 50.0 + ((patternScore - 50.0) * multiplier);
    }
    
    // Clamp to 0-100 range
    return MathMin(MathMax(patternScore, 0.0), 100.0);
}

//+------------------------------------------------------------------+
//| INDIVIDUAL PATTERN DETECTION FUNCTIONS                          |
//+------------------------------------------------------------------+

// BEARISH PATTERNS
bool CheckEveningStar(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Bullish bar, small body, bearish bar
    if(close[3] > open[3] &&  // First: bullish
       MathAbs(close[2] - open[2]) < MathAbs(close[3] - open[3]) * 0.3 &&  // Second: small body (doji-like)
       close[1] < open[1] &&  // Third: bearish
       close[1] < (close[3] + open[3]) / 2.0)  // Closes below midpoint of first bar
    {
        return true;
    }
    return false;
}

bool CheckShootingStar(double &open[], double &high[], double &low[], double &close[], int barIndex)
{
    double bodySize = MathAbs(close[barIndex] - open[barIndex]);
    double totalRange = high[barIndex] - low[barIndex];
    
    if(bodySize == 0 || totalRange == 0) return false;
    
    double upperShadow = high[barIndex] - MathMax(open[barIndex], close[barIndex]);
    double lowerShadow = MathMin(open[barIndex], close[barIndex]) - low[barIndex];
    
    // Long upper shadow (at least 2x body), tiny lower shadow, bearish close
    return (upperShadow >= bodySize * 2.0 && 
            lowerShadow <= bodySize * 0.3 && 
            close[barIndex] < open[barIndex]);
}

bool CheckBearishEngulfing(double &open[], double &high[], double &low[], double &close[])
{
    // Current bearish bar completely engulfs previous bullish bar
    return (close[2] > open[2] &&  // Previous: bullish
            close[1] < open[1] &&  // Current: bearish
            open[1] > close[2] &&  // Open above previous close
            close[1] < open[2]);   // Close below previous open
}

bool CheckGravestoneDoji(double &open[], double &high[], double &low[], double &close[], int barIndex)
{
    double bodySize = MathAbs(close[barIndex] - open[barIndex]);
    double totalRange = high[barIndex] - low[barIndex];
    
    if(totalRange == 0) return false;
    
    // Very small body (doji) with long upper shadow
    double upperShadow = high[barIndex] - MathMax(open[barIndex], close[barIndex]);
    double lowerShadow = MathMin(open[barIndex], close[barIndex]) - low[barIndex];
    
    return (bodySize <= totalRange * 0.1 &&  // Doji: small body
            upperShadow >= totalRange * 0.7 &&  // Long upper shadow
            lowerShadow <= totalRange * 0.1);  // Tiny or no lower shadow
}

bool CheckDarkCloudCover(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Bullish bar followed by bearish bar that opens above high, closes below midpoint
    if(close[2] > open[2] &&  // Previous: bullish
       close[1] < open[1] &&  // Current: bearish
       open[1] > high[2] &&   // Opens above previous high
       close[1] < (close[2] + open[2]) / 2.0)  // Closes below midpoint of previous bar
    {
        return true;
    }
    return false;
}

bool CheckBearishHarami(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Large bullish bar followed by small bearish bar inside
    double bodySize1 = MathAbs(close[2] - open[2]);
    double bodySize2 = MathAbs(close[1] - open[1]);
    
    return (close[2] > open[2] &&  // First: bullish
            close[1] < open[1] &&  // Second: bearish
            bodySize2 < bodySize1 * 0.5 &&  // Small body inside
            open[1] > open[2] && open[1] < close[2] &&  // Opens inside
            close[1] > open[2] && close[1] < close[2]); // Closes inside
}

bool CheckThreeBlackCrows(double &open[], double &high[], double &low[], double &close[])
{
    // Three consecutive bearish bars with lower lows and lower highs
    return (close[3] < open[3] && close[2] < open[2] && close[1] < open[1] &&  // All bearish
            close[3] > close[2] && close[2] > close[1] &&  // Lower closes
            open[3] > open[2] && open[2] > open[1]);  // Lower opens
}

// BULLISH PATTERNS
bool CheckMorningStar(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Bearish bar, small body, bullish bar
    if(close[3] < open[3] &&  // First: bearish
       MathAbs(close[2] - open[2]) < MathAbs(close[3] - open[3]) * 0.3 &&  // Second: small body
       close[1] > open[1] &&  // Third: bullish
       close[1] > (close[3] + open[3]) / 2.0)  // Closes above midpoint of first bar
    {
        return true;
    }
    return false;
}

bool CheckHammer(double &open[], double &high[], double &low[], double &close[], int barIndex)
{
    double bodySize = MathAbs(close[barIndex] - open[barIndex]);
    double totalRange = high[barIndex] - low[barIndex];
    
    if(bodySize == 0 || totalRange == 0) return false;
    
    double upperShadow = high[barIndex] - MathMax(open[barIndex], close[barIndex]);
    double lowerShadow = MathMin(open[barIndex], close[barIndex]) - low[barIndex];
    
    // Long lower shadow (at least 2x body), tiny upper shadow, bullish close
    return (lowerShadow >= bodySize * 2.0 && 
            upperShadow <= bodySize * 0.3 && 
            close[barIndex] > open[barIndex]);
}

bool CheckBullishEngulfing(double &open[], double &high[], double &low[], double &close[])
{
    // Current bullish bar completely engulfs previous bearish bar
    return (close[2] < open[2] &&  // Previous: bearish
            close[1] > open[1] &&  // Current: bullish
            open[1] < close[2] &&  // Open below previous close
            close[1] > open[2]);   // Close above previous open
}

bool CheckDragonflyDoji(double &open[], double &high[], double &low[], double &close[], int barIndex)
{
    double bodySize = MathAbs(close[barIndex] - open[barIndex]);
    double totalRange = high[barIndex] - low[barIndex];
    
    if(totalRange == 0) return false;
    
    // Very small body (doji) with long lower shadow
    double upperShadow = high[barIndex] - MathMax(open[barIndex], close[barIndex]);
    double lowerShadow = MathMin(open[barIndex], close[barIndex]) - low[barIndex];
    
    return (bodySize <= totalRange * 0.1 &&  // Doji: small body
            lowerShadow >= totalRange * 0.7 &&  // Long lower shadow
            upperShadow <= totalRange * 0.1);  // Tiny or no upper shadow
}

bool CheckPiercingPattern(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Bearish bar followed by bullish bar that opens below low, closes above midpoint
    if(close[2] < open[2] &&  // Previous: bearish
       close[1] > open[1] &&  // Current: bullish
       open[1] < low[2] &&    // Opens below previous low
       close[1] > (close[2] + open[2]) / 2.0)  // Closes above midpoint of previous bar
    {
        return true;
    }
    return false;
}

bool CheckBullishHarami(double &open[], double &high[], double &low[], double &close[])
{
    // Pattern: Large bearish bar followed by small bullish bar inside
    double bodySize1 = MathAbs(close[2] - open[2]);
    double bodySize2 = MathAbs(close[1] - open[1]);
    
    return (close[2] < open[2] &&  // First: bearish
            close[1] > open[1] &&  // Second: bullish
            bodySize2 < bodySize1 * 0.5 &&  // Small body inside
            open[1] > close[2] && open[1] < open[2] &&  // Opens inside
            close[1] > close[2] && close[1] < open[2]); // Closes inside
}

bool CheckThreeWhiteSoldiers(double &open[], double &high[], double &low[], double &close[])
{
    // Three consecutive bullish bars with higher highs and higher lows
    return (close[3] > open[3] && close[2] > open[2] && close[1] > open[1] &&  // All bullish
            close[3] < close[2] && close[2] < close[1] &&  // Higher closes
            open[3] < open[2] && open[2] < open[1]);  // Higher opens
}

//+------------------------------------------------------------------+
//| Count Pattern Confirmations                                     |
//+------------------------------------------------------------------+
int CountPatternConfirmations(double &open[], double &high[], double &low[], double &close[], bool isUptrend)
{
    int count = 0;
    
    if(isUptrend)
    {
        // Count bearish patterns
        if(CheckEveningStar(open, high, low, close)) count++;
        if(CheckShootingStar(open, high, low, close, 1)) count++;
        if(CheckBearishEngulfing(open, high, low, close)) count++;
        if(CheckGravestoneDoji(open, high, low, close, 1)) count++;
        if(CheckDarkCloudCover(open, high, low, close)) count++;
        if(CheckBearishHarami(open, high, low, close)) count++;
        if(CheckThreeBlackCrows(open, high, low, close)) count++;
    }
    else
    {
        // Count bullish patterns
        if(CheckMorningStar(open, high, low, close)) count++;
        if(CheckHammer(open, high, low, close, 1)) count++;
        if(CheckBullishEngulfing(open, high, low, close)) count++;
        if(CheckDragonflyDoji(open, high, low, close, 1)) count++;
        if(CheckPiercingPattern(open, high, low, close)) count++;
        if(CheckBullishHarami(open, high, low, close)) count++;
        if(CheckThreeWhiteSoldiers(open, high, low, close)) count++;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Pattern Strength Interpreter                                    |
//+------------------------------------------------------------------+
string GetPatternStrengthInterpretation(double score)
{
    if(score >= 80) return "VERY STRONG BULLISH REVERSAL";
    if(score >= 70) return "STRONG BULLISH REVERSAL";
    if(score >= 60) return "MODERATE BULLISH REVERSAL";
    if(score >= 55) return "MILD BULLISH REVERSAL";
    if(score >= 45 && score <= 55) return "NEUTRAL - NO CLEAR PATTERN";
    if(score <= 45) return "MILD BEARISH REVERSAL";
    if(score <= 40) return "MODERATE BEARISH REVERSAL";
    if(score <= 30) return "STRONG BEARISH REVERSAL";
    return "VERY STRONG BEARISH REVERSAL";
}