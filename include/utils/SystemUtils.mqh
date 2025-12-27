//+------------------------------------------------------------------+
//|                                                      SystemUtilsUtils.mqh |
//|                     Unified Trading Utilities for MQL5           |
//|                       Price, Indicators, Risk, Trading           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"
#property strict

/*
UNIFIED TRADING UTILITIES FOR MQL5
==================================
This file contains all unified utility functions including:
1. Price manipulation utilities
2. Indicator value retrieval
3. Market structure analysis
4. Risk management calculations
5. Validation functions
6. Helper utilities

NOTE: Position management and order execution functions have been 
moved to PositionManager.mqh and OrderManager.mqh respectively.
*/

#include <Trade/Trade.mqh>
#include <Arrays/ArrayDouble.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum DECISION_ACTION 
{
    ACTION_NONE,
    ACTION_OPEN_BUY,
    ACTION_OPEN_SELL,
    ACTION_ADD_BUY,
    ACTION_ADD_SELL,
    ACTION_CLOSE_BUY,
    ACTION_CLOSE_SELL,
    ACTION_CLOSE_ALL,
    ACTION_HOLD,
    ACTION_THINKING
};

// Note: ENUM_CLOSE_PRIORITY and ENUM_FIND_CRITERIA moved to OrderManager.mqh

//+------------------------------------------------------------------+
//| NAMESPACE: SystemUtils - Contains all utility functions                   |
//+------------------------------------------------------------------+
namespace SystemUtils
{
   // Indicator handles cache to improve performance
   struct SIndicatorHandle
   {
      int      atrHandles[10];    // Cached ATR handles for different periods
      int      maHandles[10];     // Cached MA handles for different periods
      int      bbHandles[10];     // Cached BB handles for different periods
      string   symbol;
      datetime lastUpdate;
   };
   
   static SIndicatorHandle g_indicatorCache;
   
   //+------------------------------------------------------------------+
   //| SECTION 1: PRICE UTILITIES                                      |
   //+------------------------------------------------------------------+
   
   // Normalize price to symbol's tick size and digits
   double NormalizePrice(const string symbol, const double price)
   {
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      if(tickSize > 0)
      {
         // Round to nearest tick
         double normalized = MathRound(price / tickSize) * tickSize;
         return NormalizeDouble(normalized, digits);
      }
      
      return NormalizeDouble(price, digits);
   }
   
   // Convert pips to price distance (1 pip = 10 points for most FX pairs)
   double GetPipDistance(const string symbol, const double pips)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return pips * point * 10;
   }
   
   // Calculate points between two prices
   double CalculatePoints(const string symbol, const double price1, const double price2)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point > 0)
         return MathAbs(price1 - price2) / point;
      return 0;
   }
   
   // Get tick size for symbol
   double GetTickSize(const string symbol)
   {
      return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   }
   
   // Get digits for symbol
   int GetDigits(const string symbol)
   {
      return (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   }
   
   // Get current bid price
   double GetBid(const string symbol)
   {
      return SymbolInfoDouble(symbol, SYMBOL_BID);
   }
   
   // Get current ask price
   double GetAsk(const string symbol)
   {
      return SymbolInfoDouble(symbol, SYMBOL_ASK);
   }
   
   // Get spread in pips
   double GetSpreadInPips(const string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
      return spread / (point * 10);
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 2: INDICATOR UTILITIES                                  |
   //+------------------------------------------------------------------+
   
   // Get ATR value with caching
   double GetATR(const string symbol, const int period = 14, const int shift = 1)
   {
      // Check cache first
      int handleIndex = period % 10;
      if(g_indicatorCache.symbol != symbol || g_indicatorCache.lastUpdate != TimeCurrent())
      {
         // Reset cache if symbol changed or it's been a while
         ResetIndicatorCache(symbol);
      }
      
      // Create handle if not exists
      if(g_indicatorCache.atrHandles[handleIndex] == INVALID_HANDLE)
      {
         g_indicatorCache.atrHandles[handleIndex] = iATR(symbol, PERIOD_CURRENT, period);
      }
      
      int handle = g_indicatorCache.atrHandles[handleIndex];
      if(handle == INVALID_HANDLE)
         return 0;
      
      // Get ATR value
      double buffer[];
      ArraySetAsSeries(buffer, true);
      
      if(CopyBuffer(handle, 0, shift, 1, buffer) < 1)
         return 0;
      
      return buffer[0];
   }
   
   // Get MA value with caching
   double GetMA(const string symbol, const int period = 20, 
                const ENUM_MA_METHOD method = MODE_SMA, const int shift = 1)
   {
      int handleIndex = period % 10;
      if(g_indicatorCache.symbol != symbol || g_indicatorCache.lastUpdate != TimeCurrent())
      {
         ResetIndicatorCache(symbol);
      }
      
      // Create handle if not exists
      if(g_indicatorCache.maHandles[handleIndex] == INVALID_HANDLE)
      {
         g_indicatorCache.maHandles[handleIndex] = iMA(symbol, PERIOD_CURRENT, period, 0, method, PRICE_CLOSE);
      }
      
      int handle = g_indicatorCache.maHandles[handleIndex];
      if(handle == INVALID_HANDLE)
         return 0;
      
      // Get MA value
      double buffer[];
      ArraySetAsSeries(buffer, true);
      
      if(CopyBuffer(handle, 0, shift, 1, buffer) < 1)
         return 0;
      
      return buffer[0];
   }
   
   // Get Bollinger Bands values
   bool GetBollingerBands(const string symbol, double &upper, double &middle, double &lower,
                          const int period = 20, const double deviation = 2.0)
   {
      int handleIndex = period % 10;
      if(g_indicatorCache.symbol != symbol || g_indicatorCache.lastUpdate != TimeCurrent())
      {
         ResetIndicatorCache(symbol);
      }
      
      // Create handle if not exists
      if(g_indicatorCache.bbHandles[handleIndex] == INVALID_HANDLE)
      {
         g_indicatorCache.bbHandles[handleIndex] = iBands(symbol, PERIOD_CURRENT, period, 0, deviation, PRICE_CLOSE);
      }
      
      int handle = g_indicatorCache.bbHandles[handleIndex];
      if(handle == INVALID_HANDLE)
         return false;
      
      // Get BB values
      double upperBuffer[], middleBuffer[], lowerBuffer[];
      ArraySetAsSeries(upperBuffer, true);
      ArraySetAsSeries(middleBuffer, true);
      ArraySetAsSeries(lowerBuffer, true);
      
      if(CopyBuffer(handle, 1, 0, 1, upperBuffer) < 1) return false;
      if(CopyBuffer(handle, 0, 0, 1, middleBuffer) < 1) return false;
      if(CopyBuffer(handle, 2, 0, 1, lowerBuffer) < 1) return false;
      
      upper = upperBuffer[0];
      middle = middleBuffer[0];
      lower = lowerBuffer[0];
      
      return true;
   }
   
   // Reset indicator cache
   void ResetIndicatorCache(const string symbol = "")
   {
      // Release all handles
      for(int i = 0; i < 10; i++)
      {
         if(g_indicatorCache.atrHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(g_indicatorCache.atrHandles[i]);
            g_indicatorCache.atrHandles[i] = INVALID_HANDLE;
         }
         if(g_indicatorCache.maHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(g_indicatorCache.maHandles[i]);
            g_indicatorCache.maHandles[i] = INVALID_HANDLE;
         }
         if(g_indicatorCache.bbHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(g_indicatorCache.bbHandles[i]);
            g_indicatorCache.bbHandles[i] = INVALID_HANDLE;
         }
      }
      
      // Update cache info
      g_indicatorCache.symbol = symbol;
      g_indicatorCache.lastUpdate = TimeCurrent();
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 3: MARKET STRUCTURE UTILITIES                           |
   //+------------------------------------------------------------------+
   
   // Find swing high (price higher than neighbors)
   double FindSwingHigh(const string symbol, const int bars = 20, const int strength = 3)
   {
      // Get price data
      double highs[];
      ArraySetAsSeries(highs, true);
      
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, bars + strength, highs) < bars + strength)
         return 0;
      
      // Look for swing high
      for(int i = strength; i < bars; i++)
      {
         bool isSwingHigh = true;
         
         // Check if current high is higher than neighbors
         for(int j = 1; j <= strength; j++)
         {
            if(highs[i] <= highs[i - j] || highs[i] <= highs[i + j])
            {
               isSwingHigh = false;
               break;
            }
         }
         
         if(isSwingHigh)
            return highs[i];
      }
      
      return 0;
   }
   
   // Find swing low (price lower than neighbors)
   double FindSwingLow(const string symbol, const int bars = 20, const int strength = 3)
   {
      // Get price data
      double lows[];
      ArraySetAsSeries(lows, true);
      
      if(CopyLow(symbol, PERIOD_CURRENT, 0, bars + strength, lows) < bars + strength)
         return 0;
      
      // Look for swing low
      for(int i = strength; i < bars; i++)
      {
         bool isSwingLow = true;
         
         // Check if current low is lower than neighbors
         for(int j = 1; j <= strength; j++)
         {
            if(lows[i] >= lows[i - j] || lows[i] >= lows[i + j])
            {
               isSwingLow = false;
               break;
            }
         }
         
         if(isSwingLow)
            return lows[i];
      }
      
      return 0;
   }
   
   // Get recent high (simplified - highest of last N bars)
   double GetRecentHigh(const string symbol, const int bars = 20)
   {
      double highs[];
      ArraySetAsSeries(highs, true);
      
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, bars, highs) < bars)
         return 0;
      
      return highs[ArrayMaximum(highs)];
   }
   
   // Get recent low (simplified - lowest of last N bars)
   double GetRecentLow(const string symbol, const int bars = 20)
   {
      double lows[];
      ArraySetAsSeries(lows, true);
      
      if(CopyLow(symbol, PERIOD_CURRENT, 0, bars, lows) < bars)
         return 0;
      
      return lows[ArrayMinimum(lows)];
   }
   
   // Check if market is making higher highs
   bool IsMarketMakingHH(const string symbol, const int bars = 5)
   {
      if(bars < 2) return false;
      
      double highs[];
      ArraySetAsSeries(highs, true);
      
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, bars, highs) < bars)
         return false;
      
      // Check if each high is higher than previous
      for(int i = 0; i < bars - 1; i++)
      {
         if(highs[i] <= highs[i + 1])
            return false;
      }
      
      return true;
   }
   
   // Check if market is making lower lows
   bool IsMarketMakingLL(const string symbol, const int bars = 5)
   {
      if(bars < 2) return false;
      
      double lows[];
      ArraySetAsSeries(lows, true);
      
      if(CopyLow(symbol, PERIOD_CURRENT, 0, bars, lows) < bars)
         return false;
      
      // Check if each low is lower than previous
      for(int i = 0; i < bars - 1; i++)
      {
         if(lows[i] >= lows[i + 1])
            return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 4: RISK MANAGEMENT UTILITIES                            |
   //+------------------------------------------------------------------+
   // NOTE: These are utility calculations only. For actual position sizing,
   // use PositionManager or OrderManager which integrate with RiskManager.
   
   // Calculate Risk:Reward ratio
   double CalculateRR(const double entry, const double sl, const double tp, const bool isBuy)
   {
      double risk = MathAbs(entry - sl);
      if(risk == 0) return 0;
      
      double reward = MathAbs(tp - entry);
      return reward / risk;
   }
   
   // Calculate profit in pips
   double CalculateProfitInPips(const string symbol, const double entry, 
                                const double current, const bool isBuy)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0) return 0;
      
      if(isBuy)
         return (current - entry) / (point * 10);
      else
         return (entry - current) / (point * 10);
   }
   
   // Calculate margin required for position
   double CalculateMarginRequired(const string symbol, const double volume, 
                                  const double price, const ENUM_ORDER_TYPE type)
   {
      double margin = 0;
      if(OrderCalcMargin(type, symbol, volume, price, margin))
         return margin;
      return 0;
   }
   
   // Check if there's enough margin for trade
   bool HasEnoughMargin(const string symbol, const double volume, 
                        const double price, const ENUM_ORDER_TYPE type, 
                        const double safetyBuffer = 0.8)
   {
      double marginRequired = CalculateMarginRequired(symbol, volume, price, type);
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      
      // Apply safety buffer
      return (freeMargin * safetyBuffer >= marginRequired);
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 5: VALIDATION UTILITIES                                 |
   //+------------------------------------------------------------------+
   
   // Check if price is valid for trading
   bool IsValidPrice(const string symbol, const double price)
   {
      if(price <= 0) return false;
      
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      // Allow some buffer (100 pips) for extreme moves
      double buffer = point * 1000;
      
      return (price >= bid - buffer && price <= ask + buffer);
   }
   
   // Validate stop loss placement
   bool IsValidStopLoss(const string symbol, const double entry, 
                        const double sl, const bool isBuy, const double minPips = 5)
   {
      // Basic checks
      if(!IsValidPrice(symbol, entry) || !IsValidPrice(symbol, sl))
         return false;
      
      // Direction check
      if(isBuy && sl >= entry) return false;
      if(!isBuy && sl <= entry) return false;
      
      // Minimum distance check
      double minDistance = GetPipDistance(symbol, minPips);
      double actualDistance = MathAbs(entry - sl);
      
      if(actualDistance < minDistance) return false;
      
      return true;
   }
   
   // Validate take profit placement
   bool IsValidTakeProfit(const string symbol, const double entry, 
                          const double tp, const bool isBuy, const double minPips = 5)
   {
      // Basic checks
      if(!IsValidPrice(symbol, entry) || !IsValidPrice(symbol, tp))
         return false;
      
      // Direction check
      if(isBuy && tp <= entry) return false;
      if(!isBuy && tp >= entry) return false;
      
      // Minimum distance check
      double minDistance = GetPipDistance(symbol, minPips);
      double actualDistance = MathAbs(tp - entry);
      
      if(actualDistance < minDistance) return false;
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 6: DECISION ACTION UTILITIES                            |
   //+------------------------------------------------------------------+
   
   // Convert decision action to string
   string DecisionActionToString(DECISION_ACTION action)
   {
      switch(action) {
         case ACTION_NONE: return "NONE";
         case ACTION_OPEN_BUY: return "OPEN_BUY";
         case ACTION_OPEN_SELL: return "OPEN_SELL";
         case ACTION_ADD_BUY: return "ADD_BUY";
         case ACTION_ADD_SELL: return "ADD_SELL";
         case ACTION_CLOSE_BUY: return "CLOSE_BUY";
         case ACTION_CLOSE_SELL: return "CLOSE_SELL";
         case ACTION_CLOSE_ALL: return "CLOSE_ALL";
         case ACTION_HOLD: return "HOLD";
         case ACTION_THINKING: return "THINKING";
         default: return "UNKNOWN";
      }
   }
   
   // Convert decision to position type
   ENUM_POSITION_TYPE DecisionToPositionType(DECISION_ACTION decision)
   {
      switch(decision) {
         case ACTION_OPEN_BUY:
         case ACTION_ADD_BUY:
            return POSITION_TYPE_BUY;
         case ACTION_OPEN_SELL:
         case ACTION_ADD_SELL:
            return POSITION_TYPE_SELL;
         default:
            return WRONG_VALUE;
      }
   }
   
   // Check if action is an open action
   bool IsOpenAction(DECISION_ACTION decision)
   {
      return (decision == ACTION_OPEN_BUY || decision == ACTION_OPEN_SELL);
   }
   
   // Check if action is a close action
   bool IsCloseAction(DECISION_ACTION decision)
   {
      return (decision == ACTION_CLOSE_BUY || decision == ACTION_CLOSE_SELL || 
              decision == ACTION_CLOSE_ALL);
   }
   
   // Check if action is an add action
   bool IsAddAction(DECISION_ACTION decision)
   {
      return (decision == ACTION_ADD_BUY || decision == ACTION_ADD_SELL);
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 7: MATH/HELPER UTILITIES                                |
   //+------------------------------------------------------------------+
   
   // Custom normalization with error handling
   double NormalizeDoubleCustom(const double value, const int digits)
   {
      if(digits < 0) return value;
      return NormalizeDouble(value, digits);
   }
   
   // Calculate percentage
   double CalculatePercentage(const double part, const double whole)
   {
      if(whole == 0) return 0;
      return (part / whole) * 100.0;
   }
   
   // Convert double to string with precision
   string DoubleToStringPrecision(const double value, const int precision = 5)
   {
      return DoubleToString(value, precision);
   }
   
   // Find maximum value in array
   double ArrayMax(const double &array[], int start = 0, int count = WHOLE_ARRAY)
   {
      if(count == WHOLE_ARRAY) count = ArraySize(array) - start;
      if(count <= 0) return 0;
      
      double maxVal = array[start];
      for(int i = start + 1; i < start + count; i++)
      {
         if(array[i] > maxVal)
            maxVal = array[i];
      }
      return maxVal;
   }
   
   // Find minimum value in array
   double ArrayMin(const double &array[], int start = 0, int count = WHOLE_ARRAY)
   {
      if(count == WHOLE_ARRAY) count = ArraySize(array) - start;
      if(count <= 0) return 0;
      
      double minVal = array[start];
      for(int i = start + 1; i < start + count; i++)
      {
         if(array[i] < minVal)
            minVal = array[i];
      }
      return minVal;
   }
   
   // Calculate average of array
   double ArrayAverage(const double &array[], int start = 0, int count = WHOLE_ARRAY)
   {
      if(count == WHOLE_ARRAY) count = ArraySize(array) - start;
      if(count <= 0) return 0;
      
      double sum = 0;
      for(int i = start; i < start + count; i++)
      {
         sum += array[i];
      }
      return sum / count;
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 8: TIME UTILITIES                                       |
   //+------------------------------------------------------------------+
   
   // Get current time as string
   string GetTimeString()
   {
      return TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   }
   
   // Check if it's a new bar
   bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
   {
      static datetime lastBarTime = 0;
      datetime currentBarTime = iTime(symbol, timeframe, 0);
      
      if(lastBarTime != currentBarTime)
      {
         lastBarTime = currentBarTime;
         return true;
      }
      return false;
   }
   
   // Get time until next bar (in seconds)
   int TimeUntilNextBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
   {
      datetime currentTime = TimeCurrent();
      datetime barStartTime = iTime(symbol, timeframe, 0);
      datetime nextBarTime = barStartTime + PeriodSeconds(timeframe);
      
      return (int)(nextBarTime - currentTime);
   }
   
   // Check if market is open (not weekend)
   bool IsMarketOpen()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Check if it's weekend (Saturday or Sunday)
      if(dt.day_of_week == 0 || dt.day_of_week == 6)
         return false;
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| SECTION 9: LOGGING UTILITIES                                    |
   //+------------------------------------------------------------------+
   
   // Print debug message with timestamp
   void PrintDebug(const string message)
   {
      Print(GetTimeString(), " - ", message);
   }
   
   // Log error with details
   void LogError(const string function, const int errorCode, const string description = "")
   {
      string errorMsg = StringFormat("ERROR in %s: %d - %s", function, errorCode, description);
      PrintDebug(errorMsg);
   }
   
   //+------------------------------------------------------------------+
   //| INITIALIZATION FUNCTIONS                                         |
   //+------------------------------------------------------------------+
   
   // Initialize the utility system
   void Initialize()
   {
      // Reset cache
      ResetIndicatorCache();
      Print("SystemUtilsUtils: Initialized successfully");
   }
   
   // Cleanup resources
   void Cleanup()
   {
      ResetIndicatorCache();
      Print("SystemUtilsUtils: Cleanup completed");
   }
}

//+------------------------------------------------------------------+
//| GLOBAL INITIALIZATION                                            |
//+------------------------------------------------------------------+

// Global initialization on include
void OnSystemUtilsUtilsInit()
{
   SystemUtils::Initialize();
}

//+------------------------------------------------------------------+