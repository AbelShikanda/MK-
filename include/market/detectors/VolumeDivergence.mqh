//+------------------------------------------------------------------+
//| Enhanced Volume Divergence Checker                              |
//| Checks volume vs price relationship for divergence confirmation |
//+------------------------------------------------------------------+

// Input parameters
input group "=== Volume Divergence Settings ==="
input int     Volume_Lookback = 10;           // Bars to check for volume patterns
input double  Volume_Threshold = 1.5;         // Volume change threshold (1.5 = 50% increase)
input bool    Use_Volume_Confirmation = true; // Enable volume divergence checks

//+------------------------------------------------------------------+
//| Check Volume Divergence Pattern                                 |
//| Returns: -1=Bearish, 0=No Divergence, 1=Bullish                |
//+------------------------------------------------------------------+
int CheckVolumeDivergence(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isUptrend)
{
    if(!Use_Volume_Confirmation) return 0;
    
    // Get volume data for last N bars
    long volumes[];
    ArrayResize(volumes, Volume_Lookback);
    
    for(int i = 0; i < Volume_Lookback; i++)
        volumes[i] = iVolume(symbol, timeframe, i);
    
    // Get price data for last N bars
    double closes[];
    ArrayResize(closes, Volume_Lookback);
    
    for(int i = 0; i < Volume_Lookback; i++)
        closes[i] = iClose(symbol, timeframe, i);
    
    // Find recent swing points in price
    int swingHighIndex = -1, swingLowIndex = -1;
    double swingHighPrice = 0, swingLowPrice = 0;
    long swingHighVolume = 0, swingLowVolume = 0;
    
    // Look for swing high (last 5 bars)
    for(int i = 2; i < 5; i++)
    {
        if(closes[i] > closes[i-1] && closes[i] > closes[i-2] && 
           closes[i] > closes[i+1] && closes[i] > closes[i+2])
        {
            swingHighIndex = i;
            swingHighPrice = closes[i];
            swingHighVolume = volumes[i];
            break;
        }
    }
    
    // Look for swing low (last 5 bars)
    for(int i = 2; i < 5; i++)
    {
        if(closes[i] < closes[i-1] && closes[i] < closes[i-2] && 
           closes[i] < closes[i+1] && closes[i] < closes[i+2])
        {
            swingLowIndex = i;
            swingLowPrice = closes[i];
            swingLowVolume = volumes[i];
            break;
        }
    }
    
    if(isUptrend)
    {
        // Looking for BEARISH volume divergence
        
        if(swingHighIndex >= 0)
        {
            // Get previous swing high (further back)
            for(int i = 5; i < Volume_Lookback - 2; i++)
            {
                if(closes[i] > closes[i-1] && closes[i] > closes[i-2] && 
                   closes[i] > closes[i+1] && closes[i] > closes[i+2])
                {
                    // Found previous swing high
                    double prevPrice = closes[i];
                    long prevVolume = volumes[i];
                    
                    // BEARISH Volume Divergence:
                    // Current price HIGHER than previous, but volume LOWER
                    if(swingHighPrice > prevPrice && swingHighVolume < prevVolume)
                    {
                        // Check if volume drop is significant (at least 30% less)
                        double volumeRatio = (double)swingHighVolume / (double)prevVolume;
                        if(volumeRatio < 0.7)  // Current volume < 70% of previous
                        {
                            PrintFormat("BEARISH Volume Divergence: Price ↑ (%.5f → %.5f) but Volume ↓ (%d → %d)",
                                       prevPrice, swingHighPrice, prevVolume, swingHighVolume);
                            return -1;  // Bearish divergence
                        }
                    }
                    break;
                }
            }
        }
    }
    else
    {
        // Looking for BULLISH volume divergence
        
        if(swingLowIndex >= 0)
        {
            // Get previous swing low (further back)
            for(int i = 5; i < Volume_Lookback - 2; i++)
            {
                if(closes[i] < closes[i-1] && closes[i] < closes[i-2] && 
                   closes[i] < closes[i+1] && closes[i] < closes[i+2])
                {
                    // Found previous swing low
                    double prevPrice = closes[i];
                    long prevVolume = volumes[i];
                    
                    // BULLISH Volume Divergence:
                    // Current price LOWER than previous, but volume HIGHER
                    if(swingLowPrice < prevPrice && swingLowVolume > prevVolume)
                    {
                        // Check if volume increase is significant (at least 30% more)
                        double volumeRatio = (double)swingLowVolume / (double)prevVolume;
                        if(volumeRatio > 1.3)  // Current volume > 130% of previous
                        {
                            PrintFormat("BULLISH Volume Divergence: Price ↓ (%.5f → %.5f) but Volume ↑ (%d → %d)",
                                       prevPrice, swingLowPrice, prevVolume, swingLowVolume);
                            return 1;  // Bullish divergence
                        }
                    }
                    break;
                }
            }
        }
    }
    
    return 0;  // No volume divergence
}

//+------------------------------------------------------------------+
//| Enhanced Volume Drop Check (for trend exhaustion)               |
//+------------------------------------------------------------------+
bool CheckVolumeDrop(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Get volume for last 5 bars
    long volumes[5];
    for(int i = 0; i < 5; i++)
        volumes[i] = iVolume(symbol, timeframe, i);
    
    // Calculate average volume of bars 2-4
    long avgVolume = (volumes[2] + volumes[3] + volumes[4]) / 3;
    
    // Current volume significantly lower than average?
    // (less than 50% of average volume)
    return (volumes[0] < avgVolume * 0.5);
}

//+------------------------------------------------------------------+
//| Volume Spike Detection                                          |
//+------------------------------------------------------------------+
bool CheckVolumeSpike(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    long currentVolume = iVolume(symbol, timeframe, 0);
    long avgVolume = 0;
    
    // Calculate 10-bar average volume
    for(int i = 1; i <= 10; i++)
        avgVolume += iVolume(symbol, timeframe, i);
    
    avgVolume /= 10;
    
    // Spike = current volume > 2x average
    return (currentVolume > avgVolume * 2.0);
}

//+------------------------------------------------------------------+
//| Get Volume Trend                                                |
//+------------------------------------------------------------------+
int GetVolumeTrend(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    long volumes[3];
    for(int i = 0; i < 3; i++)
        volumes[i] = iVolume(symbol, timeframe, i);
    
    // Check trend
    if(volumes[0] > volumes[1] && volumes[1] > volumes[2])
        return 1;  // Volume increasing
    else if(volumes[0] < volumes[1] && volumes[1] < volumes[2])
        return -1; // Volume decreasing
    else
        return 0;  // Volume choppy/no trend
}

//+------------------------------------------------------------------+
//| Check Volume Confirmation for Price Move                       |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation(const string symbol, const ENUM_TIMEFRAMES timeframe, const bool isBuy)
{
    // For a valid price move, volume should confirm:
    // - Strong upmove should have above-average volume
    // - Strong downmove should have above-average volume
    
    double priceChange = MathAbs(iClose(symbol, timeframe, 0) - iClose(symbol, timeframe, 1));
    double avgRange = iATR(symbol, timeframe, 14);
    
    long currentVolume = iVolume(symbol, timeframe, 0);
    long avgVolume = 0;
    
    // Calculate 20-bar average volume
    for(int i = 1; i <= 20; i++)
        avgVolume += iVolume(symbol, timeframe, i);
    
    avgVolume /= 20;
    
    // If price move is significant (> 50% of ATR)
    if(priceChange > avgRange * 0.5)
    {
        // Volume should be above average for confirmation
        return (currentVolume > avgVolume * 1.2);
    }
    
    return true;  // Small price move doesn't need volume confirmation
}