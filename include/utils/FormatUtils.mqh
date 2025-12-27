//+------------------------------------------------------------------+
//|                                     Utils.mqh                   |
//|                           Copyright 2024, Safe Metals EA v4.5   |
//|                                              https://www.mql5.com|
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../config/structures.mqh"
#include "../config/GlobalVariables.mqh"



//+------------------------------------------------------------------+
//| Create a repeated string pattern                                 |
//+------------------------------------------------------------------+
string StringRepeat(string pattern, int count)
{
    string result = "";
    for(int i = 0; i < count; i++)
        result += pattern;
    return result;
}


// Dynamic lot sizes
double currentManualLotSize = 0.0;

//+------------------------------------------------------------------+
//| EXTERN VARIABLES (from main EA)                                 |
//+------------------------------------------------------------------+

extern string activeSymbols[];  // Array of active symbols
extern int totalSymbols;        // Total number of active symbols

//+------------------------------------------------------------------+
//| UTILITY FUNCTION IMPLEMENTATIONS                                |
//+------------------------------------------------------------------+

// //+------------------------------------------------------------------+
// //| Get current trade direction for a symbol                        |
// //+------------------------------------------------------------------+
// int GetCurrentTradeDirection(string symbol)
// {
//     for(int i = PositionsTotal() - 1; i >= 0; i--)
//     {
//         ulong ticket = PositionGetTicket(i);
//         if(ticket > 0)
//         {
//             string posSymbol = PositionGetString(POSITION_SYMBOL);
//             if(posSymbol == symbol && PositionGetInteger(POSITION_MAGIC) == 12345)
//             {
//                 return (int)PositionGetInteger(POSITION_TYPE);
//             }
//         }
//     }
//     return -1; // No positions found
// }

// //+------------------------------------------------------------------+
// //| Attempt to open a trade                                         |
// //+------------------------------------------------------------------+
// bool TryOpenTrade(string symbol, bool isBuy, double lot, double sl, double tp)
// {
    
//     bool result;
    
//     if(isBuy)
//         result = trade.Buy(lot, symbol, 0, sl, tp);
//     else
//         result = trade.Sell(lot, symbol, 0, sl, tp);
    
//     if(result)
//     {
//         LastDecision = StringFormat("%s %s opened: Lot=%.3f", isBuy ? "BUY" : "SELL", symbol, lot);
//         return true;
//     }
//     else
//     {
//         Print("TRADE_FAILED: Failed to open ", isBuy ? "BUY" : "SELL", " ", symbol, ": Error ", GetLastError());
//         return false;
//     }
// }