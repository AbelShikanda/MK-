//+------------------------------------------------------------------+
//| Order Manager - Order Execution Utilities                      |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/TradeUtils.mqh"
#include "../market/News/NewsFilter.mqh"
#include "../signals/SignalGenerator.mqh"
#include "../risk/PositionSizer.mqh"

// ============ GLOBAL VARIABLES ============
// Note: These would normally be in GlobalVariables.mqh
// string LastDecision = "";
// int dailyTradesCount = 0;
// string activeSymbols[];
// int totalSymbols;

// ============ ORDER EXECUTION FUNCTIONS ============

//+------------------------------------------------------------------+
//| Enhanced TryOpenTrade with Reason Tag                           |
//+------------------------------------------------------------------+
bool TryOpenTradeWithReason(string symbol, bool isBuy, double lot, double sl, double tp, string reason = "")
{
    // Validate lot size
    double maxSafeLot = CalculateMaxSafeLotSize(symbol);
    if(lot > maxSafeLot)
    {
        Print("LOT_TOO_LARGE: Reducing from ", lot, " to ", maxSafeLot, " for ", symbol);
        lot = maxSafeLot;
    }
    
    // Check margin
    if(!CheckMarginRequirement(symbol, lot))
    {
        Print("INSUFFICIENT_MARGIN: Cannot open ", lot, " lots for ", symbol);
        return false;
    }
    
    // Round lot to step size
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    if(stepLot > 0)
        lot = MathRound(lot / stepLot) * stepLot;
    
    bool result;
    string direction = isBuy ? "BUY" : "SELL"; // DECLARE direction HERE
    
    if(isBuy)
        result = trade.Buy(lot, symbol, 0, sl, tp);
    else
        result = trade.Sell(lot, symbol, 0, sl, tp);
    
    if(result)
    {
        LastDecision = StringFormat("%s %s opened: Lot=%.3f, Reason=%s", 
                                     direction, symbol, lot, reason);
        
        // Add to trade log
        LogTrade(symbol, direction, lot, sl, tp, reason);
        
        // ==================== CRITICAL ADDITION ====================
        // Update divergence override tracking AFTER successful trade
        UpdateTradeDirection(symbol);
        // ===========================================================
        
        return true;
    }
    else
    {
        int error = GetLastError();
        Print("TRADE_FAILED: Failed to open ", direction, " for ", symbol, 
              " | Lot: ", lot, " | Error: ", error, " - ", PositionErrorDescription(error));
        return false;
    }
}

//+------------------------------------------------------------------+
//| CloseAllTradesForSymbol - Close all positions for a symbol      |
//+------------------------------------------------------------------+
void CloseAllTradesForSymbol(string symbol)
{
    int closedCount = 0;
    string closedTickets = "";
    
    // ============ 1. COLLECT AND CLOSE POSITIONS ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            
            if(positionSymbol == symbol)
            {
                if(trade.PositionClose(ticket))
                {
                    closedCount++;
                    closedTickets += (closedTickets == "" ? "" : ", ") + IntegerToString(ticket);
                    Print("CLOSED: Position ", ticket, " for ", symbol);
                }
                else
                {
                    Print("FAILED to close position ", ticket, 
                          " for ", symbol, " - Error: ", GetLastError());
                }
            }
        }
    }
    
    // ============ 2. POST-CLOSURE PROCESSING ============
    if(closedCount > 0)
    {
        Print("SUMMARY: Closed ", closedCount, " position(s) for ", symbol, 
              " | Tickets: ", closedTickets);
        
        // Update trade direction tracking
        UpdateTradeDirection(symbol);
    }
}

//+------------------------------------------------------------------+
//| ClosePositionType - Close specific type of positions            |
//+------------------------------------------------------------------+
void ClosePositionType(string symbol, int positionType = -1)
{
    int closedCount = 0;
    string directionText = positionType == -1 ? "ALL" : 
                          (positionType == POSITION_TYPE_BUY ? "BUY" : "SELL");
    
    // ============ 1. CLOSE SPECIFIED POSITION TYPE ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            int currentType = (int)PositionGetInteger(POSITION_TYPE);
            
            if(positionSymbol == symbol && 
               (positionType == -1 || currentType == positionType))
            {
                if(trade.PositionClose(ticket))
                {
                    closedCount++;
                    Print("CLOSED: ", GetDirectionText(currentType), 
                          " position ", ticket, " for ", symbol);
                }
                else
                {
                    Print("FAILED to close ", GetDirectionText(currentType), 
                          " position ", ticket, " - Error: ", GetLastError());
                }
            }
        }
    }
    
    // ============ 2. POST-CLOSURE PROCESSING ============
    if(closedCount > 0)
    {
        Print("SUMMARY: Closed ", closedCount, " ", directionText, 
              " position(s) for ", symbol);
        
        // Update trade direction tracking
        UpdateTradeDirection(symbol);
    }
}

//+------------------------------------------------------------------+
//| CloseBiggestLosingPosition - Close position with biggest loss   |
//+------------------------------------------------------------------+
bool CloseBiggestLosingPosition(string &outClosedSymbol)
{
    double biggestLoss = 0;
    ulong ticketToClose = 0;
    string symbolToClose = "";
    
    // ============ 1. FIND BIGGEST LOSING POSITION ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            if(profit < biggestLoss) // More negative = bigger loss
            {
                biggestLoss = profit;
                ticketToClose = ticket;
                symbolToClose = PositionGetString(POSITION_SYMBOL);
            }
        }
    }
    
    // ============ 2. CLOSE THE POSITION ============
    if(ticketToClose > 0)
    {
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("CLOSED: Biggest losing position for ", symbolToClose,
                  " | Loss: $", DoubleToString(biggestLoss, 2),
                  " | Ticket: ", ticketToClose);
            
            // Update trade direction tracking
            UpdateTradeDirection(symbolToClose);
        }
        
        return result;
    }
    
    outClosedSymbol = "";
    return false;
}

//+------------------------------------------------------------------+
//| CloseSmallestPosition - Close position with smallest volume     |
//+------------------------------------------------------------------+
bool CloseSmallestPosition(string &outClosedSymbol)
{
    double smallestVolume = DBL_MAX;
    ulong ticketToClose = 0;
    string symbolToClose = "";
    
    // ============ 1. FIND SMALLEST POSITION ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            if(volume < smallestVolume)
            {
                smallestVolume = volume;
                ticketToClose = ticket;
                symbolToClose = PositionGetString(POSITION_SYMBOL);
            }
        }
    }
    
    // ============ 2. CLOSE THE POSITION ============
    if(ticketToClose > 0)
    {
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            
            Print("CLOSED: Smallest position for ", symbolToClose,
                  " | Volume: ", DoubleToString(smallestVolume, 2),
                  " | Ticket: ", ticketToClose);
            
            // Update trade direction tracking
            UpdateTradeDirection(symbolToClose);
        }
        
        return result;
    }
    
    outClosedSymbol = "";
    return false;
}

// ============ SUPPORT FUNCTIONS ============

bool PreTradeValidation(string symbol, double lotSize, double stopLoss, double takeProfit)
{
    // Check if symbol is tradeable
    if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
    {
        Print("ERROR: Symbol ", symbol, " not tradeable");
        return false;
    }
    
    // Check lot size
    if(lotSize <= 0)
    {
        Print("ERROR: Invalid lot size: ", lotSize);
        return false;
    }
    
    // Check stops
    if(stopLoss <= 0 || takeProfit <= 0)
    {
        Print("WARNING: Invalid stop loss or take profit values");
        // Not necessarily fatal, but log it
    }
    
    // Check news filter if applicable
    #ifdef __MQL5__
    if(IsNewsBlackoutPeriod(symbol))
    {
        Print("BLOCKED: News blackout period for ", symbol);
        return false;
    }
    #endif
    
    return true;
}

bool ApplySafetyLimits(string symbol, double &lotSize)
{
    // ============ 1. CHECK MARGIN ============
    if(!CheckMarginRequirement(symbol, lotSize))
    {
        Print("MARGIN CHECK FAILED for ", symbol);
        return false;
    }
    
    // ============ 2. ADJUST LOT SIZE TO SAFE LIMIT ============
    double maxSafeLot = CalculateMaxSafeLotSize(symbol);
    
    if(lotSize > maxSafeLot)
    {
        Print("LOT_SIZE_ADJUSTED: Reduced from ", lotSize, 
              " to ", maxSafeLot, " for ", symbol);
        lotSize = maxSafeLot;
    }
    
    // ============ 3. CHECK MAX TRADES PER SYMBOL ============
    int openTrades = CountOpenTrades(symbol);
    if(openTrades >= MaxTradesPerSymbol)
    {
        Print("MAX_TRADES_REACHED: ", openTrades, 
              " trades already open for ", symbol);
        return false;
    }
    
    return true;
}

double AdjustLotSizeToConstraints(string symbol, double lotSize)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Apply minimum and maximum
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    
    // Adjust to lot step
    if(lotStep > 0)
    {
        lotSize = MathRound(lotSize / lotStep) * lotStep;
    }
    
    return NormalizeDouble(lotSize, 2);
}

bool ExecuteTradeOrder(string symbol, bool isBuy, double lotSize, 
                      double stopLoss, double takeProfit, string reason)
{
    string direction = isBuy ? "BUY" : "SELL";
    bool result;
    
    if(isBuy)
    {
        result = trade.Buy(lotSize, symbol, 0, stopLoss, takeProfit, reason);
    }
    else
    {
        result = trade.Sell(lotSize, symbol, 0, stopLoss, takeProfit, reason);
    }
    
    if(!result)
    {
        int error = GetLastError();
        Print("TRADE_EXECUTION_FAILED: Failed to open ", direction, 
              " for ", symbol, " | Error: ", error, 
              " - ", GetOrderErrorDescription(error));
        return false;
    }
    
    return true;
}

void ProcessSuccessfulTrade(string symbol, bool isBuy, double lotSize, string reason)
{
    string direction = isBuy ? "BUY" : "SELL";
    
    // Update LastDecision global variable
    LastDecision = StringFormat("%s %s opened: Lot=%.3f, Reason=%s", 
                                 direction, symbol, lotSize, reason);
    
    // Log the trade
    LogTrade(symbol, direction, lotSize, 0, 0, reason); // Note: SL/TP would be actual values
    
    // Update trade direction tracking
    UpdateTradeDirection(symbol);
    
    // Increment daily trades counter
    dailyTradesCount++;
}

// ============ UTILITY FUNCTIONS ============

bool CheckMarginRequirement(string symbol, double lotSize)
{
    double marginRequired = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL) * lotSize;
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    // Safety buffer: use max 80% of free margin
    if(marginRequired > freeMargin * 0.8)
    {
        Print("MARGIN_INSUFFICIENT: Required $%.2f, Available $%.2f", 
              marginRequired, freeMargin);
        return false;
    }
    
    return true;
}

string GetOrderErrorDescription(int errorCode)
{
    // Common MQL5 error codes
    switch(errorCode)
    {
        case 0:   return "No error";
        case 1:   return "No error, but result unknown";
        case 2:   return "Common error";
        case 3:   return "Invalid trade parameters";
        case 4:   return "Trade server is busy";
        case 5:   return "Old version";
        case 6:   return "No connection with trade server";
        case 7:   return "Not enough rights";
        case 8:   return "Too frequent requests";
        case 64:  return "Account disabled";
        case 65:  return "Invalid account";
        case 128: return "Trade timeout";
        case 129: return "Invalid price";
        case 130: return "Invalid stops";
        case 131: return "Invalid trade volume";
        case 132: return "Market is closed";
        case 133: return "Trade is disabled";
        case 134: return "Not enough money";
        case 135: return "Price changed";
        case 136: return "Off quotes";
        case 137: return "Broker is busy";
        case 138: return "Requote";
        case 139: return "Order is locked";
        case 140: return "Long positions only allowed";
        case 141: return "Too many requests";
        case 145: return "Modification denied (order too close to market)";
        case 146: return "Trade context is busy";
        case 147: return "Expirations denied by broker";
        case 148: return "Too many open and pending orders";
        default:  return StringFormat("Unknown error code: %d", errorCode);
    }
}