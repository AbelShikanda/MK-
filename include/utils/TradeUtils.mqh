//+------------------------------------------------------------------+
//| Trade Utilities - Trade-Related Functions                      |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../config/structures.mqh"

// ============ STRUCTURES ============

struct TradeInfo {
    int count;
    double totalVolume;
    double averagePrice;
    double totalProfit;
    int buyCount;
    int sellCount;
};

struct PositionDetails {
    ulong ticket;
    string symbol;
    int type;
    double volume;
    double price;
    double sl;
    double tp;
    double profit;
    double swap;
    double commission;
};

// ============ POSITION COUNTING ============

//+------------------------------------------------------------------+
//| CountOpenTrades - Count open trades for a symbol                |
//+------------------------------------------------------------------+
int CountOpenTrades(string symbol)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| CountTotalOpenTrades - Count all open trades                    |
//+------------------------------------------------------------------+
int CountTotalOpenTrades()
{
    return PositionsTotal();
}

//+------------------------------------------------------------------+
//| CountOpenTradesByType - Count trades by position type          |
//+------------------------------------------------------------------+
int CountOpenTradesByType(string symbol, ENUM_POSITION_TYPE type)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol &&
               (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| GetTradeInfo - Get comprehensive trade information              |
//+------------------------------------------------------------------+
TradeInfo GetTradeInfo(string symbol)
{
    TradeInfo info;
    info.count = 0;
    info.totalVolume = 0;
    info.averagePrice = 0;
    info.totalProfit = 0;
    info.buyCount = 0;
    info.sellCount = 0;
    
    double totalPriceVolume = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                info.count++;
                
                double volume = PositionGetDouble(POSITION_VOLUME);
                double price = PositionGetDouble(POSITION_PRICE_OPEN);
                ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                info.totalVolume += volume;
                totalPriceVolume += price * volume;
                info.totalProfit += PositionGetDouble(POSITION_PROFIT);
                
                if(type == POSITION_TYPE_BUY)
                    info.buyCount++;
                else if(type == POSITION_TYPE_SELL)
                    info.sellCount++;
            }
        }
    }
    
    if(info.totalVolume > 0)
        info.averagePrice = totalPriceVolume / info.totalVolume;
    
    return info;
}

// ============ POSITION DIRECTION ============

//+------------------------------------------------------------------+
//| GetCurrentTradeDirection - Get current trade direction          |
//+------------------------------------------------------------------+
int GetCurrentTradeDirection(string symbol)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                return (int)PositionGetInteger(POSITION_TYPE);
            }
        }
    }
    return WRONG_VALUE;
}

//+------------------------------------------------------------------+
//| GetDominantTradeDirection - Get dominant direction for symbol   |
//+------------------------------------------------------------------+
int GetDominantTradeDirection(string symbol)
{
    TradeInfo info = GetTradeInfo(symbol);
    
    if(info.buyCount > info.sellCount)
        return POSITION_TYPE_BUY;
    else if(info.sellCount > info.buyCount)
        return POSITION_TYPE_SELL;
    
    return WRONG_VALUE; // Equal or no positions
}

//+------------------------------------------------------------------+
//| HasOpenPosition - Check if symbol has any open position        |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
{
    return CountOpenTrades(symbol) > 0;
}

//+------------------------------------------------------------------+
//| HasOpenBuyPosition - Check if symbol has buy position          |
//+------------------------------------------------------------------+
bool HasOpenBuyPosition(string symbol)
{
    return CountOpenTradesByType(symbol, POSITION_TYPE_BUY) > 0;
}

//+------------------------------------------------------------------+
//| HasOpenSellPosition - Check if symbol has sell position        |
//+------------------------------------------------------------------+
bool HasOpenSellPosition(string symbol)
{
    return CountOpenTradesByType(symbol, POSITION_TYPE_SELL) > 0;
}

// ============ POSITION DETAILS ============

//+------------------------------------------------------------------+
//| GetPositionDetails - Get details of all positions for symbol   |
//+------------------------------------------------------------------+
int GetPositionDetails(string symbol, PositionDetails &details[])
{
    int count = 0;
    ArrayResize(details, PositionsTotal());
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                details[count].ticket = ticket;
                details[count].symbol = PositionGetString(POSITION_SYMBOL);
                details[count].type = (int)PositionGetInteger(POSITION_TYPE);
                details[count].volume = PositionGetDouble(POSITION_VOLUME);
                details[count].price = PositionGetDouble(POSITION_PRICE_OPEN);
                details[count].sl = PositionGetDouble(POSITION_SL);
                details[count].tp = PositionGetDouble(POSITION_TP);
                details[count].profit = PositionGetDouble(POSITION_PROFIT);
                details[count].swap = PositionGetDouble(POSITION_SWAP);
                details[count].commission = 0; // Commission not directly available
                
                count++;
            }
        }
    }
    
    ArrayResize(details, count);
    return count;
}

//+------------------------------------------------------------------+
//| GetTotalProfitForSymbol - Get total profit for symbol          |
//+------------------------------------------------------------------+
double GetTotalProfitForSymbol(string symbol)
{
    double totalProfit = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
            {
                totalProfit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| GetAverageEntryPrice - Get average entry price for symbol      |
//+------------------------------------------------------------------+
double GetAverageEntryPrice(string symbol)
{
    TradeInfo info = GetTradeInfo(symbol);
    return info.averagePrice;
}

//+------------------------------------------------------------------+
//| GetTotalVolume - Get total volume for symbol                   |
//+------------------------------------------------------------------+
double GetTotalVolume(string symbol)
{
    TradeInfo info = GetTradeInfo(symbol);
    return info.totalVolume;
}

//+------------------------------------------------------------------+
//| GetMaxSymbolsForTier - Get maximum symbols for current tier    |
//+------------------------------------------------------------------+
int GetMaxSymbolsForTier()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance < BalanceForSecondSymbol)
        return 1;
    else if(balance < BalanceForThirdSymbol)
        return 2;
    else if(balance < BalanceForFourthSymbol)
        return 3;
    else
        return 4;
}

//+------------------------------------------------------------------+
//| IsTierUpgradeAvailable - Check if tier upgrade is available    |
//+------------------------------------------------------------------+
bool IsTierUpgradeAvailable()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    int currentMax = GetMaxSymbolsForTier();
    
    if(currentMax == 1 && balance >= BalanceForSecondSymbol)
        return true;
    else if(currentMax == 2 && balance >= BalanceForThirdSymbol)
        return true;
    else if(currentMax == 3 && balance >= BalanceForFourthSymbol)
        return true;
    
    return false;
}

// ============ ERROR DESCRIPTIONS ============

//+------------------------------------------------------------------+
//| PositionErrorDescription - Get description for position errors |
//+------------------------------------------------------------------+
string PositionErrorDescription(int errorCode)
{
    switch(errorCode)
    {
        // MQL5 Trade Server Return Codes
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10007: return "Request canceled by trader";
        case 10008: return "Order placed";
        case 10009: return "Request completed";
        case 10010: return "Only part of the request was completed";
        case 10011: return "Request processing error";
        case 10012: return "Request canceled by timeout";
        case 10013: return "Invalid request";
        case 10014: return "Invalid volume in the request";
        case 10015: return "Invalid price in the request";
        case 10016: return "Invalid stops in the request";
        case 10017: return "Trade is disabled";
        case 10018: return "Market is closed";
        case 10019: return "There is not enough money to complete the request";
        case 10020: return "Prices changed";
        case 10021: return "There are no quotes to process the request";
        case 10022: return "Invalid order expiration date in the request";
        case 10023: return "Order state changed";
        case 10024: return "Too frequent requests";
        case 10025: return "No changes in request";
        case 10026: return "Autotrading disabled by server";
        case 10027: return "Autotrading disabled by client terminal";
        case 10028: return "Request locked for processing";
        case 10029: return "Order or position frozen";
        case 10030: return "Invalid order filling type";
        
        // Additional common errors
        case 4001: return "Array out of range";
        case 4002: return "No history data";
        case 4003: return "Invalid indicator parameters";
        case 4006: return "Invalid indicator handle";
        case 4010: return "CopyBuffer failed";
        case 4011: return "Not enough data";
        
        default: return StringFormat("Unknown error: %d", errorCode);
    }
}

//+------------------------------------------------------------------+
//| ValidationErrorDescription - Get validation error description  |
//+------------------------------------------------------------------+
string ValidationErrorDescription(int errorCode)
{
    switch(errorCode)
    {
        // Common validation errors
        case 0:   return "No error";
        case 1:   return "No error, but result unknown";
        case 2:   return "Common error";
        case 3:   return "Invalid trade parameters";
        case 4:   return "Trade server is busy";
        case 5:   return "Old version of the client terminal";
        case 6:   return "No connection with trade server";
        case 7:   return "Not enough rights";
        case 8:   return "Too frequent requests";
        case 9:   return "Malfunctional trade operation";
        
        // Account-related errors
        case 64:  return "Account disabled";
        case 65:  return "Invalid account";
        
        // Trade execution errors
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
        case 145: return "Modification denied because order is too close to market";
        case 146: return "Trade context is busy";
        case 147: return "Expirations are denied by broker";
        case 148: return "Too many open and pending orders";
        
        // Custom validation errors
        case 1000: return "Symbol not tradable";
        case 1001: return "Margin requirements not met";
        case 1002: return "Maximum trades per symbol reached";
        case 1003: return "Daily trade limit reached";
        case 1004: return "News blackout period";
        case 1005: return "Invalid lot size";
        case 1006: return "Invalid stop loss";
        case 1007: return "Invalid take profit";
        case 1008: return "Risk too high";
        case 1009: return "Signal validation failed";
        case 1010: return "Market conditions not favorable";
        
        default:  return StringFormat("Unknown validation error: %d", errorCode);
    }
}

//+------------------------------------------------------------------+
//| GetTradeErrorDescription - Comprehensive error description     |
//+------------------------------------------------------------------+
string GetTradeErrorDescription(int errorCode)
{
    // Try position errors first
    string description = PositionErrorDescription(errorCode);
    if(description != StringFormat("Unknown error: %d", errorCode))
        return description;
    
    // Try validation errors
    description = ValidationErrorDescription(errorCode);
    if(description != StringFormat("Unknown validation error: %d", errorCode))
        return description;
    
    // Generic fallback
    return StringFormat("Error code: %d", errorCode);
}

// ============ MARGIN AND RISK UTILITIES ============

//+------------------------------------------------------------------+
//| CalculateMaxSafeLotSize - Calculate maximum safe lot size      |
//+------------------------------------------------------------------+
double CalculateMaxSafeLotSize(string symbol)
{
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginPerLot = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
    
    if(marginPerLot <= 0)
        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    
    // Use 50% of free margin for safety
    double maxLots = (freeMargin * 0.5) / marginPerLot;
    
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    maxLots = MathMax(maxLots, minLot);
    maxLots = MathMin(maxLots, maxLot);
    
    return maxLots;
}

//+------------------------------------------------------------------+
//| CalculateFreeMarginPercent - Calculate free margin percentage  |
//+------------------------------------------------------------------+
double CalculateFreeMarginPercent()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(equity <= 0)
        return 0;
    
    return (freeMargin / equity) * 100;
}

//+------------------------------------------------------------------+
//| CalculateMarginLevel - Calculate margin level percentage       |
//+------------------------------------------------------------------+
double CalculateMarginLevel()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    if(margin <= 0)
        return 1000.0; // Very high margin level
    
    return (equity / margin) * 100;
}

// ============ POSITION MANAGEMENT UTILITIES ============

//+------------------------------------------------------------------+
//| IsPositionProfitable - Check if position is profitable         |
//+------------------------------------------------------------------+
bool IsPositionProfitable(ulong ticket)
{
    if(ticket <= 0 || !PositionSelectByTicket(ticket))
        return false;
    
    return PositionGetDouble(POSITION_PROFIT) > 0;
}

//+------------------------------------------------------------------+
//| GetPositionAge - Get position age in hours                     |
//+------------------------------------------------------------------+
double GetPositionAge(ulong ticket)
{
    if(ticket <= 0 || !PositionSelectByTicket(ticket))
        return 0;
    
    datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
    datetime currentTime = TimeCurrent();
    
    return (currentTime - openTime) / 3600.0; // Convert to hours
}

//+------------------------------------------------------------------+
//| GetPositionRiskReward - Get position risk/reward ratio         |
//+------------------------------------------------------------------+
double GetPositionRiskReward(ulong ticket)
{
    if(ticket <= 0 || !PositionSelectByTicket(ticket))
        return 0;
    
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double stopLoss = PositionGetDouble(POSITION_SL);
    double takeProfit = PositionGetDouble(POSITION_TP);
    
    if(stopLoss == 0 || takeProfit == 0)
        return 0;
    
    double risk = MathAbs(entryPrice - stopLoss);
    double reward = MathAbs(takeProfit - entryPrice);
    
    if(risk == 0)
        return 0;
    
    return reward / risk;
}

// ============ VALIDATION UTILITIES ============

//+------------------------------------------------------------------+
//| ValidateTradeParameters - Validate trade parameters            |
//+------------------------------------------------------------------+
bool ValidateTradeParameters(string symbol, double lotSize, double stopLoss, double takeProfit)
{
    // Check symbol
    if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
    {
        Print("Invalid symbol: ", symbol);
        return false;
    }
    
    // Check lot size
    if(lotSize <= 0)
    {
        Print("Invalid lot size: ", lotSize);
        return false;
    }
    
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if(lotSize < minLot || lotSize > maxLot)
    {
        Print("Lot size out of range: ", lotSize, " (min: ", minLot, ", max: ", maxLot, ")");
        return false;
    }
    
    // Check stop loss and take profit
    if(stopLoss <= 0 || takeProfit <= 0)
    {
        Print("Invalid stop loss or take profit");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| ValidatePositionCount - Validate position count limits         |
//+------------------------------------------------------------------+
bool ValidatePositionCount(string symbol)
{
    int openTrades = CountOpenTrades(symbol);
    
    if(openTrades >= MaxTradesPerSymbol)
    {
        Print("Maximum trades per symbol reached: ", openTrades);
        return false;
    }
    
    return true;
}

// ============ LOGGING UTILITIES ============


//+------------------------------------------------------------------+
//| Log Trade Details                                               |
//+------------------------------------------------------------------+
void LogTrade(string symbol, string m_direction, double lot, double sl, double tp, string reason)
{
    // You can implement logging to file or database here
    string logEntry = StringFormat("%s,%s,%.3f,%.5f,%.5f,%s",
                                   TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                                   m_direction, lot, sl, tp, reason);
    
    // Example: Write to file
    // int file = FileOpen("trades.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
    // FileSeek(file, 0, SEEK_END);
    // FileWrite(file, logEntry);
    // FileClose(file);
    
    Print("TRADE_LOG: ", logEntry);
}

//+------------------------------------------------------------------+
//| LogTradeSummary - Log summary of all trades                    |
//+------------------------------------------------------------------+
void LogTradeSummary()
{
    int totalPositions = PositionsTotal();
    double totalProfit = 0;
    double totalVolume = 0;
    
    Print("=== TRADE SUMMARY ===");
    Print("Total Positions: ", totalPositions);
    
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double volume = PositionGetDouble(POSITION_VOLUME);
            double profit = PositionGetDouble(POSITION_PROFIT);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            totalProfit += profit;
            totalVolume += volume;
            
            PrintFormat("  %s: %s %.2f @ %.5f, P&L: $%.2f",
                       symbol, (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                       volume, price, profit);
        }
    }
    
    Print("Total Profit: $", DoubleToString(totalProfit, 2));
    Print("Total Volume: ", DoubleToString(totalVolume, 2));
    Print("Account Balance: $", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Account Equity: $", AccountInfoDouble(ACCOUNT_EQUITY));
    Print("Free Margin: $", AccountInfoDouble(ACCOUNT_MARGIN_FREE));
    Print("Margin Level: ", DoubleToString(CalculateMarginLevel(), 1), "%");
    Print("====================");
}

//+------------------------------------------------------------------+
//| LogSymbolTrades - Log trades for specific symbol               |
//+------------------------------------------------------------------+
void LogSymbolTrades(string symbol)
{
    TradeInfo info = GetTradeInfo(symbol);
    
    Print("=== ", symbol, " TRADE INFO ===");
    Print("Open Positions: ", info.count);
    Print("Buy Positions: ", info.buyCount);
    Print("Sell Positions: ", info.sellCount);
    Print("Total Volume: ", DoubleToString(info.totalVolume, 2));
    Print("Average Price: ", DoubleToString(info.averagePrice, 5));
    Print("Total Profit: $", DoubleToString(info.totalProfit, 2));
    Print("=========================");
}