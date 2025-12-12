//+------------------------------------------------------------------+
//| DirectionManager.mqh                                            |
//| Trade Direction Validation Module                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/inputs.mqh"
#include "../config/enums.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/TradeUtils.mqh"
#include "../market/detectors/ReversalDetector.mqh"

static int lastKnownDirection = -1;  // Track direction for override management

//+------------------------------------------------------------------+
//| Validate Trade Direction                                        |
//| Main function for direction validation with divergence override|
//+------------------------------------------------------------------+
bool ValidateDirection(const string symbol, bool &outAllowBuy, bool &outAllowSell)
{
    const int currentDirection = GetCurrentTradeDirection(symbol);
    
    outAllowBuy = true;
    outAllowSell = true;
    
    // Step 1: Check for new divergence signals
    const DivergenceSignal divergence = CheckDivergence(symbol, Default_Timeframe);
    
    // Step 2: Divergence override logic
    if(divergence.exists && divergence.score >= 60)
    {
        const string divergenceType = divergence.bullish ? "BULLISH" : "BEARISH";
        
        // Check if we need to activate a new override
        if(!divergenceOverride.active || 
           (divergenceOverride.active && divergence.latestTime > divergenceOverride.activatedTime))
        {
            bool shouldOverride = false;
            
            if(currentDirection == POSITION_TYPE_BUY && !divergence.bullish)
            {
                // Bullish positions but BEARISH divergence detected
                shouldOverride = true;
                divergenceOverride.forceBuy = false;
                divergenceOverride.forceSell = true;
                divergenceOverride.reason = StringFormat("BEARISH_DIVERGENCE_OVERRIDE: Type=%s, Score=%.1f", 
                                                        divergence.type, divergence.score);
            }
            else if(currentDirection == POSITION_TYPE_SELL && divergence.bullish)
            {
                // Bearish positions but BULLISH divergence detected
                shouldOverride = true;
                divergenceOverride.forceBuy = true;
                divergenceOverride.forceSell = false;
                divergenceOverride.reason = StringFormat("BULLISH_DIVERGENCE_OVERRIDE: Type=%s, Score=%.1f", 
                                                        divergence.type, divergence.score);
            }
            else if(currentDirection == -1)  // No existing positions
            {
                // No existing positions - override based on divergence direction
                shouldOverride = true;
                if(divergence.bullish)
                {
                    divergenceOverride.forceBuy = true;
                    divergenceOverride.forceSell = false;
                    divergenceOverride.reason = StringFormat("BULLISH_DIVERGENCE_ENTRY: Score=%.1f", divergence.score);
                }
                else
                {
                    divergenceOverride.forceBuy = false;
                    divergenceOverride.forceSell = true;
                    divergenceOverride.reason = StringFormat("BEARISH_DIVERGENCE_ENTRY: Score=%.1f", divergence.score);
                }
            }
            
            // Activate the override if needed
            if(shouldOverride)
            {
                ActivateDivergenceOverride(symbol, divergence, currentDirection, divergenceType);
            }
        }
    }
    
    // Step 3: Apply override if active
    if(divergenceOverride.active)
    {
        // Apply override direction
        outAllowBuy = divergenceOverride.forceBuy;
        outAllowSell = divergenceOverride.forceSell;
        
        // Track trades made under this override
        if(outAllowBuy || outAllowSell)
        {
            divergenceOverride.tradeCount++;
        }
        
        // Log override status
        if(divergenceOverride.tradeCount <= 1 || divergenceOverride.tradeCount % 5 == 0)
        {
            PrintFormat("DIVERGENCE_OVERRIDE_ACTIVE: %s | Trades: %d | Age: %s",
                       divergenceOverride.reason,
                       divergenceOverride.tradeCount,
                       TimeToString(TimeCurrent() - divergenceOverride.activatedTime, TIME_SECONDS));
        }
        
        // Skip normal direction logic when override is active
        return (outAllowBuy || outAllowSell);
    }
    
    // Step 4: Normal direction logic (only runs if no override)
    ApplyNormalDirectionLogic(symbol, currentDirection, outAllowBuy, outAllowSell);
    
    return (outAllowBuy || outAllowSell);
}

//+------------------------------------------------------------------+
//| Check for Direction Change                                      |
//| Called after trades to detect direction changes                |
//+------------------------------------------------------------------+
void CheckForDirectionChange(const string symbol)
{
    const int newDirection = GetCurrentTradeDirection(symbol);
    
    // Only check if we have an active override
    if(divergenceOverride.active)
    {
        // On first call, initialize with current direction
        if(lastKnownDirection == -1)
        {
            lastKnownDirection = newDirection;
            return;
        }
        
        // Check if direction has actually changed (not just no positions)
        if(newDirection != lastKnownDirection && newDirection != -1)
        {
            // Direction has changed! Clear the override
            ClearDivergenceOverride(symbol, lastKnownDirection, newDirection);
        }
        
        // Update last known direction
        lastKnownDirection = newDirection;
    }
}

//+------------------------------------------------------------------+
//| Update Trade Direction                                          |
//| Call this AFTER opening or closing trades                       |
//+------------------------------------------------------------------+
void UpdateTradeDirection(const string symbol)
{
    CheckForDirectionChange(symbol);
}

//+------------------------------------------------------------------+
//| Position Type to String                                         |
//+------------------------------------------------------------------+
string PositionTypeToString(const int positionType)
{
    switch(positionType)
    {
        case POSITION_TYPE_BUY: return "BUY";
        case POSITION_TYPE_SELL: return "SELL";
        case -1: return "NONE";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Get Current Market Direction                                    |
//| Returns market direction based on positions                    |
//+------------------------------------------------------------------+
string GetCurrentMarketDirection(const string symbol)
{
    const int direction = GetCurrentTradeDirection(symbol);
    return PositionTypeToString(direction);
}

//+------------------------------------------------------------------+
//| Get Direction Bias                                              |
//| Returns bias for buy or sell trades                           |
//+------------------------------------------------------------------+
ENUM_TRADE_BIAS GetDirectionBias(const string symbol)
{
    const int direction = GetCurrentTradeDirection(symbol);
    
    if(direction == POSITION_TYPE_BUY)
        return BIAS_BUY_ONLY;
    else if(direction == POSITION_TYPE_SELL)
        return BIAS_SELL_ONLY;
    else
        return BIAS_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Get Direction Strength                                          |
//| Returns strength of current direction bias                     |
//+------------------------------------------------------------------+
double GetDirectionStrength(const string symbol)
{
    const int direction = GetCurrentTradeDirection(symbol);
    
    if(direction == -1)  // No positions
        return 0.0;
    
    // Calculate average profit/loss for current positions
    double totalProfit = 0.0;
    int positionCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                totalProfit += PositionGetDouble(POSITION_PROFIT);
                positionCount++;
            }
        }
    }
    
    if(positionCount == 0) return 0.0;
    
    // Normalize profit to 0-100 scale
    const double avgProfit = totalProfit / positionCount;
    const double normalizedStrength = MathMin(MathMax(avgProfit / 100.0, 0.0), 1.0) * 100.0;
    
    return normalizedStrength;
}

//+------------------------------------------------------------------+
//| Validate Direction with Divergence                              |
//| Enhanced validation with divergence consideration              |
//+------------------------------------------------------------------+
bool ValidateDirectionWithDivergence(const string symbol, const bool isBuy)
{
    bool allowBuy = true, allowSell = true;
    
    // Get base direction validation
    if(!ValidateDirection(symbol, allowBuy, allowSell))
        return false;
    
    // Check specific direction
    if(isBuy && !allowBuy)
        return false;
    if(!isBuy && !allowSell)
        return false;
    
    // Additional divergence check for extra confidence
    if(IsDivergencePresent(symbol, isBuy))
    {
        PrintFormat("Direction validation enhanced with divergence for %s (%s)", 
                   symbol, isBuy ? "BUY" : "SELL");
        return true;
    }
    
    return true;  // Valid even without divergence
}

//+------------------------------------------------------------------+
//| Is Divergence Present                                           |
//| Checks if divergence supports the trade direction              |
//+------------------------------------------------------------------+
bool IsDivergencePresent(const string symbol, const bool isBuy)
{
    const DivergenceSignal divergence = CheckDivergence(symbol, Default_Timeframe);
    
    if(!divergence.exists)
        return false;
    
    // Check if divergence supports the trade direction
    if(isBuy && divergence.bullish)
        return true;
    if(!isBuy && !divergence.bullish)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Direction Change Recommendation                             |
//| Suggests if direction should change based on analysis          |
//+------------------------------------------------------------------+
string GetDirectionChangeRecommendation(const string symbol)
{
    const int currentDirection = GetCurrentTradeDirection(symbol);
    const DivergenceSignal divergence = CheckDivergence(symbol, Default_Timeframe);
    
    if(currentDirection == -1)  // No positions
    {
        if(divergence.exists)
        {
            if(divergence.bullish)
                return "START_BUY - Bullish divergence detected";
            else
                return "START_SELL - Bearish divergence detected";
        }
        return "NEUTRAL - No clear direction";
    }
    
    // Check if divergence suggests direction change
    if(divergence.exists)
    {
        if(currentDirection == POSITION_TYPE_BUY && !divergence.bullish)
            return "CONSIDER_SELL - Bearish divergence against buy positions";
        if(currentDirection == POSITION_TYPE_SELL && divergence.bullish)
            return "CONSIDER_BUY - Bullish divergence against sell positions";
    }
    
    // Check profit/loss status
    const double directionStrength = GetDirectionStrength(symbol);
    if(directionStrength < -30.0)  // Significant losses
        return "RECONSIDER - Significant losses in current direction";
    if(directionStrength > 50.0)   // Strong profits
        return "CONTINUE - Strong profits in current direction";
    
    return "HOLD - Maintain current direction";
}

//+------------------------------------------------------------------+
//| Clear Direction Override                                        |
//| Clears any active direction override                          |
//+------------------------------------------------------------------+
void ClearDirectionOverride()
{
    divergenceOverride.active = false;
    divergenceOverride.forceBuy = false;
    divergenceOverride.forceSell = false;
    divergenceOverride.reason = "";
    divergenceOverride.activatedTime = 0;
    divergenceOverride.tradeCount = 0;
    lastKnownDirection = -1;
    
    Print("Direction override cleared");
}

//+------------------------------------------------------------------+
//| Get Direction Summary                                           |
//| Returns summary of current direction status                    |
//+------------------------------------------------------------------+
string GetDirectionSummary(const string symbol)
{
    const int currentDirection = GetCurrentTradeDirection(symbol);
    const string marketDirection = GetCurrentMarketDirection(symbol);
    const ENUM_TRADE_BIAS bias = GetDirectionBias(symbol);
    const double strength = GetDirectionStrength(symbol);
    const string recommendation = GetDirectionChangeRecommendation(symbol);
    
    string overrideInfo = "No active override";
    if(divergenceOverride.active)
    {
        overrideInfo = StringFormat("Override: %s (Active for %d trades, %s)",
                                   divergenceOverride.reason,
                                   divergenceOverride.tradeCount,
                                   TimeToString(TimeCurrent() - divergenceOverride.activatedTime, TIME_SECONDS));
    }
    
    return StringFormat("Direction Summary for %s:\n" +
                       "  Current: %s\n" +
                       "  Bias: %s\n" +
                       "  Strength: %.1f%%\n" +
                       "  Recommendation: %s\n" +
                       "  %s",
                       symbol,
                       marketDirection,
                       GetBiasString(bias),
                       strength,
                       recommendation,
                       overrideInfo);
}

//+------------------------------------------------------------------+
//| Is Direction Locked                                             |
//| Checks if direction is locked (override active)               |
//+------------------------------------------------------------------+
bool IsDirectionLocked()
{
    return divergenceOverride.active;
}

//+------------------------------------------------------------------+
//| Get Locked Direction                                            |
//| Returns which direction is locked if any                      |
//+------------------------------------------------------------------+
string GetLockedDirection()
{
    if(!divergenceOverride.active)
        return "NONE";
    
    if(divergenceOverride.forceBuy && !divergenceOverride.forceSell)
        return "BUY-ONLY";
    if(!divergenceOverride.forceBuy && divergenceOverride.forceSell)
        return "SELL-ONLY";
    
    return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Helper Functions                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Activate Divergence Override                                    |
//+------------------------------------------------------------------+
void ActivateDivergenceOverride(const string symbol, const DivergenceSignal &divergence, 
                               const int currentDirection, const string divergenceType)
{
    divergenceOverride.active = true;
    divergenceOverride.activatedTime = TimeCurrent();
    divergenceOverride.tradeCount = 0;
    
    Print("========================================");
    PrintFormat("🎯 DIVERGENCE OVERRIDE ACTIVATED!");
    PrintFormat("   Symbol: %s", symbol);
    PrintFormat("   Type: %s %s", divergence.type, divergenceType);
    PrintFormat("   Score: %.1f/100", divergence.score);
    PrintFormat("   Current Positions: %s", PositionTypeToString(currentDirection));
    PrintFormat("   Override Direction: %s", 
               divergenceOverride.forceBuy ? "BUY-ONLY" : "SELL-ONLY");
    PrintFormat("   Reason: %s", divergenceOverride.reason);
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Clear Divergence Override                                       |
//+------------------------------------------------------------------+
void ClearDivergenceOverride(const string symbol, const int lastDirection, const int newDirection)
{
    Print("========================================");
    PrintFormat("🎯 DIVERGENCE OVERRIDE CLEARED!");
    PrintFormat("   Symbol: %s", symbol);
    PrintFormat("   Direction Changed: %s → %s",
               PositionTypeToString(lastDirection),
               PositionTypeToString(newDirection));
    PrintFormat("   Override was active for: %d trades, %s",
               divergenceOverride.tradeCount,
               TimeToString(TimeCurrent() - divergenceOverride.activatedTime, TIME_SECONDS));
    PrintFormat("   Reason: Trade direction has successfully changed");
    Print("========================================");
    
    ClearDirectionOverride();
}

//+------------------------------------------------------------------+
//| Apply Normal Direction Logic                                    |
//+------------------------------------------------------------------+
void ApplyNormalDirectionLogic(const string symbol, const int currentDirection, 
                              bool &allowBuy, bool &allowSell)
{
    if(currentDirection == POSITION_TYPE_BUY)
    {
        // Existing BUY positions - only allow more BUYs
        allowSell = false;
        PrintFormat("NORMAL_DIRECTION: Existing BUY positions for %s - only allowing BUYs", symbol);
    }
    else if(currentDirection == POSITION_TYPE_SELL)
    {
        // Existing SELL positions - only allow more SELLs  
        allowBuy = false;
        PrintFormat("NORMAL_DIRECTION: Existing SELL positions for %s - only allowing SELLs", symbol);
    }
    else  // -1 means no positions
    {
        // No existing trades - allow both directions
        if(GetDivergenceDebugMode())
        {
            PrintFormat("NORMAL_DIRECTION: No existing trades for %s - allowing new positions", symbol);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Bias String                                                 |
//+------------------------------------------------------------------+
string GetBiasString(const ENUM_TRADE_BIAS bias)
{
    switch(bias)
    {
        case BIAS_BUY_ONLY: return "BUY-ONLY";
        case BIAS_SELL_ONLY: return "SELL-ONLY";
        case BIAS_NEUTRAL: return "NEUTRAL";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Check Direction Consistency                                     |
//| Ensures all trades are in the same direction                   |
//+------------------------------------------------------------------+
bool CheckDirectionConsistency(const string symbol)
{
    int buyCount = 0;
    int sellCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                const long type = PositionGetInteger(POSITION_TYPE);
                if(type == POSITION_TYPE_BUY)
                    buyCount++;
                else if(type == POSITION_TYPE_SELL)
                    sellCount++;
            }
        }
    }
    
    // Check if we have mixed positions
    if(buyCount > 0 && sellCount > 0)
    {
        PrintFormat("WARNING: Mixed positions detected for %s - %d BUYs, %d SELLs", 
                   symbol, buyCount, sellCount);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Position Count by Direction                                 |
//+------------------------------------------------------------------+
int GetPositionCountByDirection(const string symbol, const bool isBuy)
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                const long type = PositionGetInteger(POSITION_TYPE);
                if((isBuy && type == POSITION_TYPE_BUY) || (!isBuy && type == POSITION_TYPE_SELL))
                    count++;
            }
        }
    }
    
    return count;
}