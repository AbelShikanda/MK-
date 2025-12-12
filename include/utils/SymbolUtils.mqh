//+------------------------------------------------------------------+
//| Symbol Utilities - Symbol Management                           |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/enums.mqh"
#include "../config/structures.mqh"
#include "../config/GlobalVariables.mqh"
#include "utils.mqh"

// ============ SORTING CONSTANTS ============
#define SORT_ASCEND 0
#define SORT_DESCEND 1

//+------------------------------------------------------------------+
//| IsSilver - Check if symbol is silver                            |
//+------------------------------------------------------------------+
bool IsSilver(string symbol)
{
    string silverSymbols[] = {
        "XAGUSD", "XAGUSDm", "SILVER", 
        "XAGUSD.", "SILVER.", "XAG"
    };
    
    symbol = StringSubstr(symbol, 0, 6); // Get first 6 characters
    
    for(int i = 0; i < ArraySize(silverSymbols); i++)
        if(StringFind(symbol, silverSymbols[i]) >= 0)
            return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| IsGold - Check if symbol is gold                                |
//+------------------------------------------------------------------+
bool IsGold(string symbol)
{
    string goldSymbols[] = {
        "XAUUSD", "XAUUSDm", "GOLD", 
        "XAUUSD.", "GOLD.", "XAU"
    };
    
    symbol = StringSubstr(symbol, 0, 6); // Get first 6 characters
    
    for(int i = 0; i < ArraySize(goldSymbols); i++)
        if(StringFind(symbol, goldSymbols[i]) >= 0)
            return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| IsMetal - Check if symbol is a metal                            |
//+------------------------------------------------------------------+
bool IsMetal(string symbol)
{
    return IsGold(symbol) || IsSilver(symbol);
}

// ============ SYMBOL PARAMETERS ============

//+------------------------------------------------------------------+
//| GetSymbolAdjustedMultiplier - Get adjusted parameter for symbol |
//+------------------------------------------------------------------+
double GetSymbolAdjustedMultiplier(string symbol, string paramType)
{
    // Silver optimization
    if(EnableSilverOptimization && IsSilver(symbol))
    {
        if(paramType == "ATR_MULTIPLIER") return Silver_ATR_Multiplier;
        if(paramType == "MIN_BODY") return Silver_MinBodyPips;
        if(paramType == "TREND_BARS") return Silver_ConsecutiveBars;
        if(paramType == "VOLATILITY_MULTIPLIER") return 1.5; // Silver more volatile
    }
    
    // Gold specific parameters
    if(IsGold(symbol))
    {
        if(paramType == "ATR_MULTIPLIER") return ATR_SL_Multiplier * 1.2;
        if(paramType == "MIN_BODY") return MinCandleBodyPips * 1.5;
        if(paramType == "TREND_BARS") return ConsecutiveBarsCount;
    }
    
    // Default values for other symbols
    if(paramType == "ATR_MULTIPLIER") return ATR_SL_Multiplier;
    if(paramType == "MIN_BODY") return MinCandleBodyPips;
    if(paramType == "TREND_BARS") return ConsecutiveBarsCount;
    if(paramType == "VOLATILITY_MULTIPLIER") return 1.0;
    
    return 0;
}

//+------------------------------------------------------------------+
//| GetSymbolPointValue - Get point value for symbol                |
//+------------------------------------------------------------------+
double GetSymbolPointValue(string symbol)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Adjust for 5-digit brokers
    if(digits == 5 || digits == 3)
        point *= 10;
    
    return point;
}

//+------------------------------------------------------------------+
//| GetSymbolTickValue - Get tick value per lot                     |
//+------------------------------------------------------------------+
double GetSymbolTickValue(string symbol)
{
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue <= 0 || tickSize <= 0)
        return 0.01; // Default fallback
    
    return tickValue;
}

// ============ MARKET ANALYSIS ============

//+------------------------------------------------------------------+
//| CountConsecutiveBars - Count consecutive bars in direction      |
//+------------------------------------------------------------------+
int CountConsecutiveBars(string symbol, bool isBuy, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
    int consecutive = 0;
    int maxBars = 20; // Increased for better accuracy
    
    for(int i = 1; i <= maxBars; i++)
    {
        double open = iOpen(symbol, timeframe, i);
        double close = iClose(symbol, timeframe, i);
        
        // Check for valid data
        if(open == 0 || close == 0)
            break;
            
        if(isBuy && close > open)
            consecutive++;
        else if(!isBuy && close < open)
            consecutive++;
        else
            break;
    }
    
    return consecutive;
}

//+------------------------------------------------------------------+
//| CalculateBarStrength - Calculate strength of current bar        |
//+------------------------------------------------------------------+
double CalculateBarStrength(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
    double open = iOpen(symbol, timeframe, 1);
    double close = iClose(symbol, timeframe, 1);
    double high = iHigh(symbol, timeframe, 1);
    double low = iLow(symbol, timeframe, 1);
    
    if(open == 0 || close == 0 || high == low)
        return 0;
    
    double bodySize = MathAbs(close - open);
    double totalRange = high - low;
    
    if(totalRange == 0)
        return 0;
    
    // Body as percentage of total range
    return (bodySize / totalRange) * 100;
}

//+------------------------------------------------------------------+
//| GetCurrentStopLoss - Get current stop loss for symbol           |
//+------------------------------------------------------------------+
double GetCurrentStopLoss(string symbol)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                return PositionGetDouble(POSITION_SL);
            }
        }
    }
    return 0;
}

// ============ SYMBOL SELECTION ============

//+------------------------------------------------------------------+
//| IsSymbolTradable - Check if symbol is available for trading     |
//+------------------------------------------------------------------+
SymbolStatus IsSymbolTradable(string symbol)
{
    SymbolStatus status;
    status.symbol = symbol;
    status.isTradable = false;
    status.reason = "";
    status.errorCode = 0;
    status.score = 0;
    
    // Check if symbol exists
    if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
    {
        status.reason = "Symbol not found";
        status.errorCode = 1;
        return status;
    }
    
    // Check trading mode
    long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        status.reason = "Trading disabled for symbol";
        status.errorCode = 2;
        return status;
    }
    
    // Check market is open
    if(!IsMarketOpen(symbol))
    {
        status.reason = "Market is closed";
        status.errorCode = 3;
        return status;
    }
    
    // Check spread
    long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    if(spread > MaxAllowedSpread * 10) // Convert to points
    {
        status.reason = StringFormat("Spread too high: %.0f", spread);
        status.errorCode = 4;
        return status;
    }
    
    // Check liquidity
    long volume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
    if(volume < 1000) // Minimum volume threshold
    {
        status.reason = "Insufficient liquidity";
        status.errorCode = 5;
        return status;
    }
    
    // Calculate score
    status.score = CalculateSymbolScore(symbol);
    status.isTradable = true;
    status.reason = "Tradable";
    
    return status;
}

//+------------------------------------------------------------------+
//| GetAllAvailableSymbols - Get all available trading symbols      |
//+------------------------------------------------------------------+
int GetAllAvailableSymbols(string &symbols[])
{
    int count = 0;
    ArrayResize(symbols, 100); // Initial size
    
    // Get all symbols from Market Watch
    int total = SymbolsTotal(true);
    
    for(int i = 0; i < total; i++)
    {
        string symbolName = SymbolName(i, true);
        
        // Filter for metals and major pairs
        if(ShouldIncludeSymbol(symbolName))
        {
            if(count >= ArraySize(symbols))
                ArrayResize(symbols, ArraySize(symbols) * 2);
            
            symbols[count] = symbolName;
            count++;
        }
    }
    
    ArrayResize(symbols, count);
    return count;
}

bool ShouldIncludeSymbol(string symbol)
{
    // Include metals
    if(IsMetal(symbol))
        return true;
    
    // Include major forex pairs
    string majorPairs[] = {
        "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
        "AUDUSD", "USDCAD", "NZDUSD", "EURGBP"
    };
    
    for(int i = 0; i < ArraySize(majorPairs); i++)
        if(StringFind(symbol, majorPairs[i]) >= 0)
            return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| CalculateSymbolScore - Calculate trading score for symbol       |
//+------------------------------------------------------------------+
double CalculateSymbolScore(string symbol)
{
    double score = 0;
    int factors = 0;
    
    // 1. Spread factor (lower is better)
    long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    double spreadScore = MathMax(0, 100 - ((double)spread / 10.0)); // Explicit cast
    score += spreadScore;
    factors++;
    
    // 2. Volatility factor (moderate volatility is best)
    double atr = GetATRValue(symbol, PERIOD_H1, 14);
    double volatilityScore = CalculateVolatilityScore(atr);
    score += volatilityScore;
    factors++;
    
    // 3. Liquidity factor
    long volume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
    double liquidityScore = MathMin(100, (double)volume / 10000.0); // Explicit cast
    score += liquidityScore;
    factors++;
    
    // 4. Trend factor
    double trendScore = CalculateTrendScore(symbol);
    score += trendScore;
    factors++;
    
    // 5. Metal bonus
    if(IsMetal(symbol))
        score += 20;
    
    if(factors > 0)
        score /= factors;
    
    return NormalizeDouble(score, 2);
}

double GetATRValue(string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
    double atrValue[1];
    int atrHandle = iATR(symbol, timeframe, period);
    
    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrValue) > 0)
        return atrValue[0];
    
    return 0;
}

double CalculateVolatilityScore(double atrValue)
{
    // Optimal ATR range: 0.0005 to 0.0020
    if(atrValue < 0.0001) return 20;  // Too low
    if(atrValue < 0.0005) return 50;  // Low
    if(atrValue < 0.0020) return 100; // Optimal
    if(atrValue < 0.0050) return 70;  // High
    return 30; // Too high
}

double CalculateTrendScore(string symbol)
{
    // Count consecutive bullish/bearish bars
    int bullishBars = CountConsecutiveBars(symbol, true);
    int bearishBars = CountConsecutiveBars(symbol, false);
    
    int maxBars = MathMax(bullishBars, bearishBars);
    
    // Score based on trend strength
    if(maxBars >= 5) return 100;      // Strong trend
    if(maxBars >= 3) return 70;       // Moderate trend
    if(maxBars >= 1) return 40;       // Weak trend
    return 20;                         // No trend
}

//+------------------------------------------------------------------+
//| DetermineActiveSymbols - Select active symbols based on score   |
//+------------------------------------------------------------------+
int DetermineActiveSymbols(string &selectedSymbols[], double minScore = 60)
{
    // Get all available symbols
    string allSymbols[];
    int totalAvailable = GetAllAvailableSymbols(allSymbols);
    
    // Calculate scores for all symbols
    SymbolScore scores[];
    ArrayResize(scores, totalAvailable);
    
    for(int i = 0; i < totalAvailable; i++)
    {
        scores[i].symbol = allSymbols[i];
        scores[i].score = CalculateSymbolScore(allSymbols[i]);
        
        // Additional metrics - NO CASTING NEEDED for integer values
        scores[i].spread = SymbolInfoInteger(allSymbols[i], SYMBOL_SPREAD);  // This returns long
        scores[i].liquidity = (double)SymbolInfoInteger(allSymbols[i], SYMBOL_VOLUME); // This needs double cast
        scores[i].volatility = GetATRValue(allSymbols[i], PERIOD_H1, 14);
    }
    
    // Sort by score (descending)
    ArraySortStruct(scores, "score", SORT_DESCEND); // Changed from MODE_DESCEND to SORT_DESCEND
    
    // Select top symbols based on account tier
    int symbolsToSelect = CalculateSymbolsToSelect();
    int selectedCount = 0;
    
    ArrayResize(selectedSymbols, symbolsToSelect);
    
    for(int i = 0; i < totalAvailable && selectedCount < symbolsToSelect; i++)
    {
        if(scores[i].score >= minScore)
        {
            selectedSymbols[selectedCount] = scores[i].symbol;
            scores[i].ranking = selectedCount + 1;
            selectedCount++;
        }
    }
    
    // Resize array to actual selected count
    ArrayResize(selectedSymbols, selectedCount);
    
    // Log selection results
    LogSymbolSelection(selectedSymbols, scores, selectedCount);
    
    return selectedCount;
}

int CalculateSymbolsToSelect()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance < BalanceForSecondSymbol)
        return 1; // Gold only
    else if(balance < BalanceForThirdSymbol)
        return 2;
    else if(balance < BalanceForFourthSymbol)
        return 3;
    else
        return 4;
}

//+------------------------------------------------------------------+
//| ArraySortStruct - Sort struct array by field                    |
//+------------------------------------------------------------------+
void ArraySortStruct(SymbolScore &array[], string field, int mode = SORT_ASCEND)
{
    // Simple bubble sort for struct array
    int size = ArraySize(array);
    
    for(int i = 0; i < size - 1; i++)
    {
        for(int j = i + 1; j < size; j++)
        {
            bool shouldSwap = false;
            
            if(field == "score")
            {
                if(mode == SORT_ASCEND && array[i].score > array[j].score)
                    shouldSwap = true;
                else if(mode == SORT_DESCEND && array[i].score < array[j].score)
                    shouldSwap = true;
            }
            else if(field == "symbol")
            {
                if(mode == SORT_ASCEND && array[i].symbol > array[j].symbol)
                    shouldSwap = true;
                else if(mode == SORT_DESCEND && array[i].symbol < array[j].symbol)
                    shouldSwap = true;
            }
            else if(field == "spread")
            {
                if(mode == SORT_ASCEND && array[i].spread > array[j].spread)
                    shouldSwap = true;
                else if(mode == SORT_DESCEND && array[i].spread < array[j].spread)
                    shouldSwap = true;
            }
            
            if(shouldSwap)
            {
                SymbolScore temp = array[i];
                array[i] = array[j];
                array[j] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ReevaluateSymbols - Periodically reevaluate symbol selection    |
//+------------------------------------------------------------------+
void ReevaluateSymbols()
{
    static datetime lastReevaluation = 0;
    datetime currentTime = TimeCurrent();
    
    // Reevaluate every 4 hours
    if(currentTime - lastReevaluation < 14400) // 4 hours in seconds
        return;
    
    lastReevaluation = currentTime;
    
    Print("=== SYMBOL REEVALUATION STARTED ===");
    
    // Get current symbol scores
    SymbolScore currentScores[];
    int symbolCount = 0;
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        SymbolStatus status = IsSymbolTradable(symbol);
        
        if(status.isTradable)
        {
            ArrayResize(currentScores, symbolCount + 1);
            currentScores[symbolCount].symbol = symbol;
            currentScores[symbolCount].score = CalculateSymbolScore(symbol);
            symbolCount++;
        }
        else
        {
            Print("Symbol ", symbol, " no longer tradable: ", status.reason);
        }
    }
    
    // Check if we need to replace any symbols
    string newSymbols[];
    int newCount = DetermineActiveSymbols(newSymbols, 60);
    
    // Compare and update if needed
    bool needsUpdate = CompareSymbolSets(currentScores, newSymbols, newCount);
    
    if(needsUpdate)
    {
        Print("Updating active symbols...");
        
        // Update global arrays
        ArrayCopy(activeSymbols, newSymbols);
        totalSymbols = newCount;
        
        Print("Active symbols updated. New count: ", totalSymbols);
    }
    else
    {
        Print("No symbol changes needed.");
    }
    
    Print("=== SYMBOL REEVALUATION COMPLETED ===");
}

bool CompareSymbolSets(SymbolScore &currentScores[], string &newSymbols[], int newCount)
{
    // If count is different, we need update
    if(ArraySize(currentScores) != newCount)
        return true;
    
    // Check if any symbols are different
    for(int i = 0; i < newCount; i++)
    {
        bool found = false;
        for(int j = 0; j < ArraySize(currentScores); j++)
        {
            if(currentScores[j].symbol == newSymbols[i])
            {
                found = true;
                break;
            }
        }
        
        if(!found)
            return true;
    }
    
    return false;
}

// ============ MARKET STATUS ============

//+------------------------------------------------------------------+
//| IsMarketOpen - Check if market is open for symbol               |
//+------------------------------------------------------------------+
bool IsMarketOpen(string symbol)
{
    // Check session times (simplified)
    // In real implementation, you would check symbol session times
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int hour = dt.hour;
    int dayOfWeek = dt.day_of_week;
    
    // Forex market hours (simplified): Sunday 22:00 - Friday 21:00 GMT
    // Metals: Similar but check specific exchange hours
    
    if(dayOfWeek == 0 && hour < 22) // Sunday before market open
        return false;
    
    if(dayOfWeek == 5 && hour >= 21) // Friday after market close
        return false;
    
    if(dayOfWeek == 6) // Saturday
        return false;
    
    return true;
}

// ============ LOGGING ============



// ============ ACCOUNT TIER ============

//+------------------------------------------------------------------+
//| GetCurrentTier - Get current account trading tier              |
//+------------------------------------------------------------------+
string GetCurrentTier()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance < BalanceForSecondSymbol)
        return "TIER 1 (Gold Only)";
    else if(balance < BalanceForThirdSymbol)
        return "TIER 2 (2 Symbols)";
    else if(balance < BalanceForFourthSymbol)
        return "TIER 3 (3 Symbols)";
    else
        return "TIER 4 (4 Symbols)";
}

//+------------------------------------------------------------------+
//| Get array position for symbol                                   |
//+------------------------------------------------------------------+
int ArrayPosition(string symbol)
{
    for(int i = 0; i < totalSymbols; i++)
        if(activeSymbols[i] == symbol)
            return i;
    return -1;
}

//+------------------------------------------------------------------+
//| LogSymbolSelection - Log symbol selection results               |
//+------------------------------------------------------------------+
void LogSymbolSelection(string &selectedSymbols[], SymbolScore &scores[], int count)
{
    Print("=== SYMBOL SELECTION RESULTS ===");
    Print("Account Tier: ", GetCurrentTier());
    Print("Selected ", count, " symbols:");
    
    for(int i = 0; i < count; i++)
    {
        string symbol = selectedSymbols[i];
        double score = 0;
        long spread = 0;
        
        // Find score for this symbol
        for(int j = 0; j < ArraySize(scores); j++)
        {
            if(scores[j].symbol == symbol)
            {
                score = scores[j].score;
                spread = scores[j].spread;
                break;
            }
        }
        
        PrintFormat("%d. %s - Score: %.1f, Spread: %.0f", 
                   i + 1, symbol, score, spread);
    }
    Print("================================");
}