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

//+------------------------------------------------------------------+
//| CloseBiggestLosingPosition - Close position with biggest loss   |
//| FIXED: Correct initialization and filtering                     |
//+------------------------------------------------------------------+
bool CloseBiggestLosingPosition(string &outClosedSymbol)
{
    double biggestLoss = DBL_MAX;  // Start with VERY LARGE positive number
    ulong ticketToClose = 0;
    string symbolToClose = "";
    bool foundLoss = false;
    
    Print("=== CLOSE BIGGEST LOSING POSITION START ===");
    Print("Total positions: ", PositionsTotal());
    
    // ============ 1. FIND BIGGEST LOSING POSITION ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            Print("Checking position ", i, ": ", symbol, 
                  " | Profit: $", DoubleToString(profit, 2),
                  " | Volume: ", DoubleToString(volume, 2));
            
            // ONLY consider LOSING positions (profit < 0)
            if(profit < 0)
            {
                foundLoss = true;
                
                // Compare losses: -50 is WORSE than -10 (more negative)
                if(profit < biggestLoss)
                {
                    biggestLoss = profit;
                    ticketToClose = ticket;
                    symbolToClose = symbol;
                    
                    Print("NEW BIGGEST LOSS: ", symbol, 
                          " | Loss: $", DoubleToString(profit, 2));
                }
            }
        }
    }
    
    // ============ 2. CHECK IF WE SHOULD CLOSE ============
    if(!foundLoss)
    {
        Print("No losing positions found. Nothing to close.");
        outClosedSymbol = "";
        return false;
    }
    
    // ============ 3. ADD SAFETY CHECKS ============
    if(ticketToClose <= 0 || symbolToClose == "")
    {
        Print("ERROR: Invalid position selected for closing");
        outClosedSymbol = "";
        return false;
    }
    
    // Get final position details before closing
    if(PositionSelectByTicket(ticketToClose))
    {
        double finalProfit = PositionGetDouble(POSITION_PROFIT);
        double finalVolume = PositionGetDouble(POSITION_VOLUME);
        
        Print("PRE-CLOSE CHECK: ", symbolToClose,
              " | Ticket: ", ticketToClose,
              " | Loss: $", DoubleToString(finalProfit, 2),
              " | Volume: ", DoubleToString(finalVolume, 2));
    }
    
    // ============ 4. CLOSE THE POSITION ============
    Print("Attempting to close biggest losing position: ", 
          symbolToClose, " | Ticket: ", ticketToClose);
    
    bool result = trade.PositionClose(ticketToClose);
    
    if(result)
    {
        outClosedSymbol = symbolToClose;
        
        Print("SUCCESS: Closed biggest losing position");
        Print("  Symbol: ", symbolToClose);
        Print("  Loss: $", DoubleToString(biggestLoss, 2));
        Print("  Ticket: ", ticketToClose);
        
        // Update trade direction tracking
        UpdateTradeDirection(symbolToClose);
        
        // Optional: Add delay to prevent immediate re-entry
        Sleep(100);
    }
    else
    {
        Print("FAILED: Could not close position ", ticketToClose);
        Print("Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        outClosedSymbol = "";
    }
    
    Print("=== CLOSE BIGGEST LOSING POSITION END ===");
    
    return result;
}

//+------------------------------------------------------------------+
//| CloseSmallestProfitPosition - Close position with smallest gain |
//| Returns true if closed successfully, false otherwise             |
//+------------------------------------------------------------------+
bool CloseSmallestProfitPosition(string &outClosedSymbol)
{
    double smallestProfit = DBL_MAX;  // Start with VERY LARGE positive
    ulong ticketToClose = 0;
    string symbolToClose = "";
    bool foundPosition = false;
    
    Print("=== CLOSE SMALLEST PROFIT POSITION START ===");
    Print("Total positions: ", PositionsTotal());
    
    // ============ 1. FIND POSITION WITH SMALLEST PROFIT ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double volume = PositionGetDouble(POSITION_VOLUME);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            Print("Checking position ", i, ": ", symbol, 
                  " | Type: ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " | Profit: $", DoubleToString(profit, 2),
                  " | Volume: ", DoubleToString(volume, 2));
            
            // Consider ALL positions (profit or loss)
            foundPosition = true;
            
            // Compare absolute profit value (smallest = closest to zero)
            if(MathAbs(profit) < MathAbs(smallestProfit))
            {
                smallestProfit = profit;
                ticketToClose = ticket;
                symbolToClose = symbol;
                
                Print("NEW SMALLEST PROFIT: ", symbol, 
                      " | Profit: $", DoubleToString(profit, 2));
            }
        }
    }
    
    // ============ 2. CHECK IF WE SHOULD CLOSE ============
    if(!foundPosition)
    {
        Print("No positions found. Nothing to close.");
        outClosedSymbol = "";
        return false;
    }
    
    // ============ 3. ADD SAFETY CHECKS ============
    if(ticketToClose <= 0 || symbolToClose == "")
    {
        Print("ERROR: Invalid position selected for closing");
        outClosedSymbol = "";
        return false;
    }
    
    // Get final position details before closing
    if(PositionSelectByTicket(ticketToClose))
    {
        double finalProfit = PositionGetDouble(POSITION_PROFIT);
        double finalVolume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE finalType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        Print("PRE-CLOSE CHECK: ", symbolToClose,
              " | Type: ", (finalType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
              " | Ticket: ", ticketToClose,
              " | Profit: $", DoubleToString(finalProfit, 2),
              " | Volume: ", DoubleToString(finalVolume, 2));
    }
    
    // ============ 4. CLOSE THE POSITION ============
    Print("Attempting to close smallest profit position: ", 
          symbolToClose, " | Ticket: ", ticketToClose);
    
    bool result = trade.PositionClose(ticketToClose);
    
    if(result)
    {
        outClosedSymbol = symbolToClose;
        
        Print("SUCCESS: Closed smallest profit position");
        Print("  Symbol: ", symbolToClose);
        Print("  Profit: $", DoubleToString(smallestProfit, 2));
        Print("  Ticket: ", ticketToClose);
        
        // Update trade direction tracking (if you have this function)
        UpdateTradeDirection(symbolToClose);
        
        // Optional: Add delay to prevent immediate re-entry
        Sleep(100);
    }
    else
    {
        Print("FAILED: Could not close position ", ticketToClose);
        Print("Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        outClosedSymbol = "";
    }
    
    Print("=== CLOSE SMALLEST PROFIT POSITION END ===");
    
    return result;
}

//+------------------------------------------------------------------+
//| CloseSmallestWinFirst - Complete version                         |
//| Closes the smallest WINNING position first                       |
//+------------------------------------------------------------------+
bool CloseSmallestWinFirst(string &outClosedSymbol, double minProfit = 0.01)
{
    double smallestWin = DBL_MAX;  // Start with large positive
    ulong ticketToClose = 0;
    string symbolToClose = "";
    bool foundWin = false;
    
    Print("=== CLOSE SMALLEST WIN FIRST (Min: $", minProfit, ") ===");
    Print("Total positions: ", PositionsTotal());
    
    // ============ 1. FIND SMALLEST WINNING POSITION ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            Print("Checking position ", i, ": ", symbol, 
                  " | Profit: $", DoubleToString(profit, 2),
                  " | Volume: ", DoubleToString(volume, 2));
            
            // Only consider WINNING positions above minimum
            if(profit >= minProfit)
            {
                foundWin = true;
                
                // Find smallest winning position
                if(profit < smallestWin)
                {
                    smallestWin = profit;
                    ticketToClose = ticket;
                    symbolToClose = symbol;
                    
                    Print("NEW SMALLEST WIN: ", symbol, 
                          " | Profit: $", DoubleToString(profit, 2));
                }
            }
        }
    }
    
    // ============ 2. FALLBACK TO SMALLEST LOSS IF NO WINS ============
    if(!foundWin)
    {
        Print("No winning positions found (min: $", minProfit, "). Checking losses...");
        return CloseSmallestLossFirst(outClosedSymbol);
    }
    
    // ============ 3. SAFETY CHECKS ============
    if(ticketToClose <= 0 || symbolToClose == "")
    {
        Print("ERROR: Invalid position selected for closing");
        outClosedSymbol = "";
        return false;
    }
    
    // Get final details
    if(PositionSelectByTicket(ticketToClose))
    {
        double finalProfit = PositionGetDouble(POSITION_PROFIT);
        double finalVolume = PositionGetDouble(POSITION_VOLUME);
        
        Print("PRE-CLOSE: ", symbolToClose,
              " | Ticket: ", ticketToClose,
              " | Profit: $", DoubleToString(finalProfit, 2),
              " | Volume: ", DoubleToString(finalVolume, 2));
    }
    
    // ============ 4. CLOSE THE POSITION ============
    Print("Closing smallest win: ", symbolToClose, " | Ticket: ", ticketToClose);
    
    bool result = trade.PositionClose(ticketToClose);
    
    if(result)
    {
        outClosedSymbol = symbolToClose;
        
        Print("SUCCESS: Closed smallest winning position");
        Print("  Symbol: ", symbolToClose);
        Print("  Profit: $", DoubleToString(smallestWin, 2));
        Print("  Ticket: ", ticketToClose);
        
        // Update trade direction tracking
        UpdateTradeDirection(symbolToClose);
    }
    else
    {
        Print("FAILED: Could not close position ", ticketToClose);
        Print("Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        outClosedSymbol = "";
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| CloseSmallestLossFirst - Complete version                        |
//| Closes the smallest LOSS first (least negative)                  |
//+------------------------------------------------------------------+
bool CloseSmallestLossFirst(string &outClosedSymbol)
{
    double smallestLoss = 0;  // Start at 0 (least negative possible)
    ulong ticketToClose = 0;
    string symbolToClose = "";
    bool foundLoss = false;
    
    Print("=== CLOSE SMALLEST LOSS FIRST ===");
    Print("Total positions: ", PositionsTotal());
    
    // ============ 1. FIND SMALLEST LOSS ============
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double volume = PositionGetDouble(POSITION_VOLUME);
            
            Print("Checking position ", i, ": ", symbol, 
                  " | Profit: $", DoubleToString(profit, 2),
                  " | Volume: ", DoubleToString(volume, 2));
            
            // Only consider LOSING positions
            if(profit < 0)
            {
                foundLoss = true;
                
                // Find least negative loss (closest to zero)
                // -$1 is SMALLER loss than -$10 (so -1 > -10)
                if(profit > smallestLoss)
                {
                    smallestLoss = profit;
                    ticketToClose = ticket;
                    symbolToClose = symbol;
                    
                    Print("NEW SMALLEST LOSS: ", symbol, 
                          " | Loss: $", DoubleToString(profit, 2));
                }
            }
        }
    }
    
    // ============ 2. CHECK IF WE SHOULD CLOSE ============
    if(!foundLoss)
    {
        Print("No losing positions found.");
        outClosedSymbol = "";
        return false;
    }
    
    // ============ 3. SAFETY CHECKS ============
    if(ticketToClose <= 0 || symbolToClose == "")
    {
        Print("ERROR: Invalid position selected for closing");
        outClosedSymbol = "";
        return false;
    }
    
    // Get final details
    if(PositionSelectByTicket(ticketToClose))
    {
        double finalProfit = PositionGetDouble(POSITION_PROFIT);
        double finalVolume = PositionGetDouble(POSITION_VOLUME);
        
        Print("PRE-CLOSE: ", symbolToClose,
              " | Ticket: ", ticketToClose,
              " | Loss: $", DoubleToString(finalProfit, 2),
              " | Volume: ", DoubleToString(finalVolume, 2));
    }
    
    // ============ 4. CLOSE THE POSITION ============
    Print("Closing smallest loss: ", symbolToClose, " | Ticket: ", ticketToClose);
    
    bool result = trade.PositionClose(ticketToClose);
    
    if(result)
    {
        outClosedSymbol = symbolToClose;
        
        Print("SUCCESS: Closed smallest losing position");
        Print("  Symbol: ", symbolToClose);
        Print("  Loss: $", DoubleToString(smallestLoss, 2));
        Print("  Ticket: ", ticketToClose);
        
        // Update trade direction tracking
        UpdateTradeDirection(symbolToClose);
    }
    else
    {
        Print("FAILED: Could not close position ", ticketToClose);
        Print("Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        outClosedSymbol = "";
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Smart Close Position - Decision based on strategy                |
//| Chooses which position to close based on current market state    |
//+------------------------------------------------------------------+
enum ENUM_CLOSE_PRIORITY {
    CLOSE_SMALLEST_PROFIT,    // Default for folding - minimize impact
    CLOSE_BIGGEST_LOSS,       // For damage control
    CLOSE_SMALLEST_LOSS,      // For gradual recovery
    CLOSE_OLDEST,             // Based on opening time
    CLOSE_NEWEST              // Based on opening time
};

bool SmartClosePosition(string &outClosedSymbol, ENUM_CLOSE_PRIORITY priority = CLOSE_SMALLEST_PROFIT)
{
    switch(priority)
    {
        case CLOSE_SMALLEST_PROFIT:
            return CloseSmallestProfitPosition(outClosedSymbol);
        
        case CLOSE_BIGGEST_LOSS:
            return CloseBiggestLosingPosition(outClosedSymbol);
        
        case CLOSE_SMALLEST_LOSS:
            return CloseSmallestLossFirst(outClosedSymbol);
        
        case CLOSE_OLDEST:
            return CloseOldestPosition(outClosedSymbol);
        
        case CLOSE_NEWEST:
            return CloseNewestPosition(outClosedSymbol);
    }
    
    outClosedSymbol = "";
    return false;
}

//+------------------------------------------------------------------+
//| Get Folding Recommendation - Which position to close for folding |
//+------------------------------------------------------------------+
ENUM_CLOSE_PRIORITY GetFoldingRecommendation()
{
    int totalPositions = PositionsTotal();
    int winningPositions = 0;
    int losingPositions = 0;
    double totalProfit = 0;
    
    // Analyze current positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            totalProfit += profit;
            
            if(profit >= 0)
                winningPositions++;
            else
                losingPositions++;
        }
    }
    
    Print("Folding Analysis: Total=", totalPositions, 
          " | Wins=", winningPositions, 
          " | Losses=", losingPositions,
          " | Total Profit=$", DoubleToString(totalProfit, 2));
    
    // Decision logic
    if(totalProfit >= 0)
    {
        // Overall profitable - close smallest win to preserve capital
        Print("Recommendation: CLOSE_SMALLEST_PROFIT (portfolio is green)");
        return CLOSE_SMALLEST_PROFIT;
    }
    else if(losingPositions)
    {
        // Mostly losing - close smallest loss to reduce damage
        Print("Recommendation: CLOSE_SMALLEST_LOSS (mostly losing positions)");
        return CLOSE_SMALLEST_LOSS;
    }
    else
    {
        // Mixed or mostly winning but overall loss - close biggest loss
        Print("Recommendation: CLOSE_BIGGEST_LOSS (mixed but overall loss)");
        return CLOSE_BIGGEST_LOSS;
    }
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

//+------------------------------------------------------------------+
//| CloseOldestPosition - Close position opened earliest            |
//+------------------------------------------------------------------+
bool CloseOldestPosition(string &outClosedSymbol)
{
    datetime oldestTime = D'3000.01.01';  // Far future
    ulong ticketToClose = 0;
    string symbolToClose = "";
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(openTime < oldestTime)
            {
                oldestTime = openTime;
                ticketToClose = ticket;
                symbolToClose = PositionGetString(POSITION_SYMBOL);
            }
        }
    }
    
    if(ticketToClose > 0)
    {
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            Print("Closed oldest position: ", symbolToClose, 
                  " | Opened: ", TimeToString(oldestTime));
            UpdateTradeDirection(symbolToClose);
        }
        
        return result;
    }
    
    outClosedSymbol = "";
    return false;
}

//+------------------------------------------------------------------+
//| CloseNewestPosition - Close position opened most recently       |
//+------------------------------------------------------------------+
bool CloseNewestPosition(string &outClosedSymbol)
{
    datetime newestTime = 0;  // Far past
    ulong ticketToClose = 0;
    string symbolToClose = "";
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            if(openTime > newestTime)
            {
                newestTime = openTime;
                ticketToClose = ticket;
                symbolToClose = PositionGetString(POSITION_SYMBOL);
            }
        }
    }
    
    if(ticketToClose > 0)
    {
        bool result = trade.PositionClose(ticketToClose);
        
        if(result)
        {
            outClosedSymbol = symbolToClose;
            Print("Closed newest position: ", symbolToClose, 
                  " | Opened: ", TimeToString(newestTime));
            UpdateTradeDirection(symbolToClose);
        }
        
        return result;
    }
    
    outClosedSymbol = "";
    return false;
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