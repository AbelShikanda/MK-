//+------------------------------------------------------------------+
//| Position Manager - Position Management                         |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../market/news/NewsFilter.mqh"
#include "../signals/SignalScorer.mqh"
#include "../signals/SignalGenerator.mqh"
#include "../risk/PositionSizer.mqh"
#include "../signals/ValidationEngine.mqh"
#include "OrderManager.mqh"


// In your EA's input section (usually at the top of the .mq5 file):
input group "=== Expert Advisor Settings ==="
input int    ExpertMagicNumber   = 12345;     // Unique EA magic number
input string ExpertComment       = "MyEA";    // Trade comment prefix
input int    SlippagePoints      = 5;         // Slippage in points

// ============ GLOBAL VARIABLES ============
// These would normally be in GlobalVariables.mqh, but kept for reference
// int dailyTradesCount = 0;
// datetime lastTradeCandle[];

//+------------------------------------------------------------------+
//| OpenNewPosition - Opens a new trade with comprehensive checks   |
//+------------------------------------------------------------------+
bool OpenNewPosition(string symbol, bool isBuy, string reason = "ENTRY")
{
    if(!Validated(symbol, isBuy))
    {
        Print("Primary Validation Failed for ", (isBuy ? "BUY" : "SELL"), 
              " addition - No action");
        return false;
    }

    // Get position size and stop loss
    double lotSize = 0, stopLoss = 0;
    
    if(isBuy)
    {
        bool signal = GetUltraBuySignal(symbol, lotSize, stopLoss);
        if(!signal) return false;
    }
    else
    {
        bool signal = GetUltraSellSignal(symbol, lotSize, stopLoss);
        if(!signal) return false;
    }
    
    // Validate lot size
    if(lotSize <= 0)
    {
        lotSize = CalculateProgressivePositionSize(symbol);
        if(lotSize <= 0) return false;
    }
    
    // Calculate take profit if not provided
    double takeProfit = CalculateTakeProfit(symbol, isBuy, stopLoss);
    
    // Open trade
    bool result = TryOpenTradeWithReason(symbol, isBuy, lotSize, stopLoss, takeProfit, reason);
    
    if(result)
    {
        // Print("OPENED: New ", (isBuy ? "BUY" : "SELL"), " position for ", symbol,
        //       " | Lot: ", lotSize, " | SL: ", stopLoss, " | Reason: ", reason);
        
        // Update last trade candle
        int pos = ArrayPosition(symbol);
        if(pos != -1)
            lastTradeCandle[pos] = iTime(symbol, TradeTF, 0);
        
        dailyTradesCount++;
    }
    
    return result;
}  

//+------------------------------------------------------------------+
//| Add to Existing Position                                        |
//+------------------------------------------------------------------+
bool AddToPosition(string symbol, bool isBuy, string reason = "ADDITION")
{
    if(!Validated(symbol, isBuy))
    {
        Print("Primary Validation Failed for ", (isBuy ? "BUY" : "SELL"), 
              " addition - No action");
        return false;
    }
    
    // 2. Comprehensive addition validation
    bool ValidationResults = AddPositionValidated(symbol, isBuy, reason);
    
    if(!ValidationResults)  // If validation FAILS, return false immediately
    {
        Print("FAILED: Position Validation for ", symbol);
        return false;
    }
    
    // If we get here, validation PASSED
    // Print("SUCCESS: Position addition Allowed for ", symbol);
    
    // Check if we have existing position in same direction
    int currentDir = GetCurrentTradeDirection(symbol);
    if((isBuy && currentDir != POSITION_TYPE_BUY) || 
       (!isBuy && currentDir != POSITION_TYPE_SELL))
    {
        Print("CANNOT ADD: No existing ", (isBuy ? "BUY" : "SELL"), " position for ", symbol);
        return false;
    }
    
    // 5. Get current price for logging
    double currentPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                                  SymbolInfoDouble(symbol, SYMBOL_BID);
    
    
    // Get position size (same as new entry)
    double lotSize = CalculateProgressivePositionSize(symbol);
    if(lotSize <= 0) return false;
    
    // Use average stop loss from existing positions
    double avgStopLoss = GetAverageStopLoss(symbol, isBuy);
    
    // Calculate take profit
    double takeProfit = CalculateTakeProfit(symbol, isBuy, avgStopLoss);
    
    // Open additional trade
    bool result = TryOpenTradeWithReason(symbol, isBuy, lotSize, avgStopLoss, takeProfit, reason);
    
    if(result)
    {
        // Print("ADDED: Additional ", (isBuy ? "BUY" : "SELL"), " position for ", symbol,
        //       " | Lot: ", lotSize, " | Price: ", currentPrice,
        //       " | SL: ", avgStopLoss, " | TP: ", takeProfit, " | Reason: ", reason);
        
        dailyTradesCount++;
        return true;
    }
    else
    {
        Print("FAILED: Could not execute addition for ", symbol);
        return false;
    }
}

// ============ STRUCTURES ============

struct TradeParameters {
    double lotSize;
    double stopLoss;
    double takeProfit;
    double entryPrice;
    bool isBuy;
    double riskPercent;
};

struct AdditionParameters {
    double lotSize;
    double stopLoss;
    double takeProfit;
    double entryPrice;
    bool isBuy;
    double averagePrice;
    double averageStopLoss;
    int existingPositions;
};

struct PositionValidationResult {
    bool isValid;
    string reason;
    int errorCode;
};

// ============ VALIDATION FUNCTIONS ============

bool PositionPreValidation(string symbol, bool isBuy, string actionType)
{
    PositionValidationResult result;
    
    // Basic symbol validation
    if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
    {
        Print("ERROR: Symbol ", symbol, " not tradeable");
        return false;
    }
    
    // News filter check
    if(IsNewsBlackoutPeriod(symbol))
    {
        Print("BLOCKED: News blackout period for ", symbol);
        return false;
    }
    
    // Account validation
    if(!ValidateAccountState(symbol, isBuy, actionType))
    {
        Print("Account validation failed");
        return false;
    }
    
    return true;
}

bool ValidateAccountState(string symbol, bool isBuy, string actionType)
{
    // Check daily limit
    if(dailyLimitReached)
    {
        Print("Daily trade limit reached");
        return false;
    }
    
    // Check max trades per symbol
    int openTrades = CountOpenTrades(symbol);
    if(openTrades >= MaxTradesPerSymbol && actionType == "OPEN")
    {
        Print("Max trades per symbol reached: ", openTrades);
        return false;
    }
    
    // Check margin requirements
    if(!ValidateMarginRequirements(symbol, isBuy, actionType))
    {
        Print("Margin requirements not met");
        return false;
    }
    
    return true;
}

bool ValidateMarginRequirements(string symbol, bool isBuy, string actionType)
{
    // This would call MarginMonitor.mqh functions
    // For now, implement basic check
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(freeMargin < (equity * 0.1)) // Minimum 10% free margin
    {
        Print("Insufficient free margin: $", freeMargin);
        return false;
    }
    
    return true;
}

bool ValidatePositionDirection(string symbol, bool isBuy)
{
    int currentDir = GetCurrentTradeDirection(symbol);
    
    if((isBuy && currentDir != POSITION_TYPE_BUY) || 
       (!isBuy && currentDir != POSITION_TYPE_SELL))
    {
        return false;
    }
    
    return true;
}

bool ValidatePositionAddition(string symbol, bool isBuy, string reason)
{
    // Check if addition is allowed based on current market conditions
    double currentPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    double averagePrice = GetAverageEntryPrice(symbol, isBuy);
    
    // Don't add if price moved too far from average
    double priceDistance = MathAbs(currentPrice - averagePrice);
    double allowedDistance = CalculateAllowedAdditionDistance(symbol);
    
    if(priceDistance > allowedDistance)
    {
        Print("Price too far from average for addition: ", priceDistance, 
              " (max: ", allowedDistance, ")");
        return false;
    }
    
    return true;
}

// ============ PARAMETER PREPARATION FUNCTIONS ============

TradeParameters PrepareTradeParameters(string symbol, bool isBuy)
{
    TradeParameters params;
    params.isBuy = isBuy;
    params.entryPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Get lot size from position sizer
    params.lotSize = CalculatePositionSize(symbol, isBuy);
    
    // Calculate stop loss
    params.stopLoss = CalculateStopLoss(symbol, isBuy, params.entryPrice, false);
    
    // Calculate take profit
    params.takeProfit = CalculateTakeProfit(symbol, isBuy, params.stopLoss);
    
    // Calculate risk percentage
    params.riskPercent = CalculateRiskPercentage(symbol, params.lotSize, params.entryPrice, params.stopLoss);
    
    return params;
}

AdditionParameters PrepareAdditionParameters(string symbol, bool isBuy)
{
    AdditionParameters params;
    params.isBuy = isBuy;
    params.entryPrice = isBuy ? 
        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
        SymbolInfoDouble(symbol, SYMBOL_BID);
    
    // Get existing position info
    params.existingPositions = CountDirectionalTrades(symbol, isBuy);
    params.averagePrice = GetAverageEntryPrice(symbol, isBuy);
    params.averageStopLoss = GetAverageStopLoss(symbol, isBuy);
    
    // Calculate lot size (progressive sizing)
    params.lotSize = CalculateProgressivePositionSize(symbol);
    
    // Use average stop loss for additions
    params.stopLoss = params.averageStopLoss > 0 ? 
        params.averageStopLoss : 
        CalculateStopLoss(symbol, isBuy, params.entryPrice, true);
    
    // Calculate take profit
    params.takeProfit = CalculateTakeProfit(symbol, isBuy, params.stopLoss);
    
    return params;
}

bool ValidateTradeParameters(TradeParameters &params)
{
    if(params.lotSize <= 0)
    {
        Print("Invalid lot size: ", params.lotSize);
        return false;
    }
    
    if(params.stopLoss <= 0 || params.takeProfit <= 0)
    {
        Print("Invalid stop loss or take profit");
        return false;
    }
    
    if(params.riskPercent > 2.0) // Max 2% risk per trade
    {
        Print("Risk too high: ", params.riskPercent, "% (max: 2%)");
        return false;
    }
    
    return true;
}

bool ValidateAdditionParameters(AdditionParameters &params)
{
    if(params.existingPositions == 0)
    {
        Print("No existing positions to add to");
        return false;
    }
    
    if(params.lotSize <= 0)
    {
        Print("Invalid lot size for addition: ", params.lotSize);
        return false;
    }
    
    // Check if addition would exceed max positions
    if(params.existingPositions >= MaxTradesPerSymbol)
    {
        Print("Max additions reached: ", params.existingPositions);
        return false;
    }
    
    return true;
}

TradeParameters ConvertToTradeParameters(AdditionParameters &addParams)
{
    TradeParameters params;
    params.isBuy = addParams.isBuy;
    params.lotSize = addParams.lotSize;
    params.stopLoss = addParams.stopLoss;
    params.takeProfit = addParams.takeProfit;
    params.entryPrice = addParams.entryPrice;
    params.riskPercent = CalculateRiskPercentage(
        "", addParams.lotSize, addParams.entryPrice, addParams.stopLoss);
    
    return params;
}

// ============ CALCULATION FUNCTIONS ============

double CalculatePositionSize(string symbol, bool isBuy)
{
    // Call the PositionSizer.mqh function
    double lotSize = CalculateProgressivePositionSize(symbol);
    
    // Apply minimum and maximum lot size constraints
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    return NormalizeDouble(lotSize, 2);
}

double CalculateStopLoss(string symbol, bool isBuy, double entryPrice, bool isAddition)
{
    if(isAddition)
    {
        double avgStopLoss = GetAverageStopLoss(symbol, isBuy);
        if(avgStopLoss > 0) return avgStopLoss;
    }
    
    return CalculateDefaultStopLoss(symbol, isBuy, entryPrice);
}

double CalculateDefaultStopLoss(string symbol, bool isBuy, double entryPrice)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double minStopLossPips = GetMinimumStopLoss(symbol);
    
    // Try ATR-based stop loss first
    double atrStop = CalculateATRStopLoss(symbol, entryPrice);
    if(atrStop > 0) return atrStop;
    
    // Fallback: fixed stop loss
    double stopDistance = minStopLossPips * point * 10;
    
    // Get digits as int (explicit cast)
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    if(isBuy)
        return NormalizeDouble(entryPrice - stopDistance, digits);
    else
        return NormalizeDouble(entryPrice + stopDistance, digits);
}

double CalculateATRStopLoss(string symbol, double entryPrice, bool isBuy = true)
{
    ENUM_TIMEFRAMES timeframe = PERIOD_M15;  // Use ENUM_TIMEFRAMES type
    int atrPeriod = 14;
    
    double atrValue[1];
    int atrHandle = iATR(symbol, timeframe, atrPeriod);  // timeframe is now correct type
    
    if(atrHandle == INVALID_HANDLE) 
        return 0;
    
    if(CopyBuffer(atrHandle, 0, 0, 1, atrValue) < 1)
    {
        IndicatorRelease(atrHandle);
        return 0;
    }
    
    IndicatorRelease(atrHandle);  // Always release indicator handle
    
    double atrMultiplier = GetProgressiveATRMultiplier(AccountInfoDouble(ACCOUNT_BALANCE));
    double atrStop = atrValue[0] * atrMultiplier;
    
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Calculate stop loss based on direction
    double stopPrice;
    if(isBuy)
        stopPrice = entryPrice - atrStop;  // For buy: stop below entry
    else
        stopPrice = entryPrice + atrStop;  // For sell: stop above entry
    
    return NormalizeDouble(stopPrice, digits);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(string symbol, bool isBuy, double stopLoss)
{
    double entryPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                                SymbolInfoDouble(symbol, SYMBOL_BID);
    
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Risk:Reward ratio from inputs
    double riskReward = RiskRewardRatio;
    if(riskReward <= 0) riskReward = 1.5; // Default 1:1.5
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double takeProfitDistance = stopDistance * riskReward;
    
    if(isBuy)
        return entryPrice + takeProfitDistance;
    else
        return entryPrice - takeProfitDistance;
}

double CalculateRiskPercentage(string symbol, double lotSize, double entryPrice, double stopLoss)
{
    double pointValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = MathAbs(entryPrice - stopLoss) * lotSize * pointValue;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(equity > 0)
        return (riskAmount / equity) * 100;
    
    return 0;
}

// ============ POSITION ANALYSIS FUNCTIONS ============

double GetAverageStopLoss(string symbol, bool isBuy)
{
    double totalSL = 0;
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if((isBuy && currentType == POSITION_TYPE_BUY) ||
                   (!isBuy && currentType == POSITION_TYPE_SELL))
                {
                    totalSL += PositionGetDouble(POSITION_SL);
                    count++;
                }
            }
        }
    }
    
    if(count > 0)
    {
        // Get digits as int to avoid warning
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        return NormalizeDouble(totalSL / count, digits);
    }
    
    return 0;
}

double GetAverageEntryPrice(string symbol, bool isBuy)
{
    double totalPrice = 0;
    double totalVolume = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if((isBuy && currentType == POSITION_TYPE_BUY) ||
                   (!isBuy && currentType == POSITION_TYPE_SELL))
                {
                    double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    double positionVolume = PositionGetDouble(POSITION_VOLUME);
                    
                    totalPrice += positionPrice * positionVolume;
                    totalVolume += positionVolume;
                }
            }
        }
    }
    
    if(totalVolume > 0)
    {
        // Fix: Explicitly cast to int
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        return NormalizeDouble(totalPrice / totalVolume, digits);
    }
    
    return 0;
}

int CountDirectionalTrades(string symbol, bool isBuy)
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if((isBuy && currentType == POSITION_TYPE_BUY) ||
                   (!isBuy && currentType == POSITION_TYPE_SELL))
                {
                    count++;
                }
            }
        }
    }
    
    return count;
}

double CalculateAllowedAdditionDistance(string symbol)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double atrValue[1];
    
    int atrHandle = iATR(symbol, PERIOD_M15, 14);
    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrValue) >= 1)
    {
        return atrValue[0] * 0.5; // Allow additions within half ATR
    }
    
    return 50 * point * 10; // Fallback: 50 pips
}

// ============ POST-TRADE FUNCTIONS ============

void PostTradeActions(string symbol, bool isBuy, double lotSize, string reason)
{
    // Update trade counter
    dailyTradesCount++;
    
    // Update last trade candle
    int pos = ArrayPosition(symbol);
    if(pos != -1)
        lastTradeCandle[pos] = iTime(symbol, TradeTF, 0);
    
    // Log trade to journal
    LogTradeToJournal(symbol, isBuy, lotSize, reason);
}

void LogTradeToJournal(string symbol, bool isBuy, double lotSize, string reason)
{
    // Implementation depends on your logging system
    // Could write to file, send to server, etc.
    Print("Trade logged: ", symbol, " ", (isBuy ? "BUY" : "SELL"), 
          " ", lotSize, " lots - Reason: ", reason);
}

// ============ PRINTING FUNCTIONS ============

void PrintPositionOpened(string symbol, bool isBuy, TradeParameters &params, string reason)
{
    Print("OPENED: New ", (isBuy ? "BUY" : "SELL"), " position for ", symbol,
          " | Lot: ", params.lotSize, 
          " | Entry: ", params.entryPrice,
          " | SL: ", params.stopLoss,
          " | TP: ", params.takeProfit,
          " | Risk: ", DoubleToString(params.riskPercent, 2), "%",
          " | Reason: ", reason);
}

void PrintPositionAdded(string symbol, bool isBuy, AdditionParameters &params, string reason)
{
    Print("ADDED: Additional ", (isBuy ? "BUY" : "SELL"), " position for ", symbol,
          " | Lot: ", params.lotSize,
          " | Entry: ", params.entryPrice,
          " | Avg Price: ", params.averagePrice,
          " | Avg SL: ", params.averageStopLoss,
          " | TP: ", params.takeProfit,
          " | Existing: ", params.existingPositions,
          " | Reason: ", reason);
}