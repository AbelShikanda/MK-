//+------------------------------------------------------------------+
//|                                               StopLossManager.mqh|
//|                    Pure MQL5 Stop Loss Manager - Single File     |
//|                             Production Ready                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

#include "../config/enums.mqh"
#include "../config/structures.mqh"
#include "../utils/Utils.mqh"

/*
PURE MQL5 STOP LOSS MANAGER
===========================
Features:
1. Structure-based stops (swing points)
2. ATR-based stops (volatility adjusted)
3. MA-based stops (trend following)
4. Bollinger Band stops
5. Risk management utilities
6. Clean MQL5 syntax with handles

Usage:
#include <StopLossManager.mqh>

// Quick calculation
double sl = StopLoss::Calculate(Symbol(), true, Ask, STOP_STRUCTURE);

// Or use instance
CStopLossManager slm;
double sl2 = slm.Calculate(Symbol(), true, Ask, STOP_ATR);
*/

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| MAIN CLASS: CStopLossManager                                      |
//+------------------------------------------------------------------+
class CStopLossManager
{
private:
   // Configuration
   ENUM_STOP_METHOD   m_defaultMethod;
   double             m_atrMultiplier;
   double             m_fixedPips;
   int                m_maPeriod;
   double             m_bbDeviation;
   
   // State
   string             m_currentSymbol;
   int                m_maHandle;
   int                m_atrHandle;
   int                m_bbHandle;
   
   // Initialize indicator handles
   void InitHandles(const string symbol)
   {
      if(m_currentSymbol != symbol)
      {
         CleanupHandles();
         m_currentSymbol = symbol;
         
         m_maHandle = iMA(symbol, PERIOD_CURRENT, m_maPeriod, 0, MODE_SMA, PRICE_CLOSE);
         m_atrHandle = iATR(symbol, PERIOD_CURRENT, 14);
         m_bbHandle = iBands(symbol, PERIOD_CURRENT, 20, 0, m_bbDeviation, PRICE_CLOSE);
      }
   }
   
   // Cleanup indicator handles
   void CleanupHandles()
   {
      if(m_maHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_maHandle);
         m_maHandle = INVALID_HANDLE;
      }
      if(m_atrHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atrHandle);
         m_atrHandle = INVALID_HANDLE;
      }
      if(m_bbHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_bbHandle);
         m_bbHandle = INVALID_HANDLE;
      }
   }
   
   // Get indicator values
   double GetMAValue()
   {
      if(m_maHandle == INVALID_HANDLE) return 0;
      
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(m_maHandle, 0, 0, 1, buffer) < 1) return 0;
      return buffer[0];
   }
   
   double GetATRValue()
   {
      if(m_atrHandle == INVALID_HANDLE) return 0;
      
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(m_atrHandle, 0, 0, 1, buffer) < 1) return 0;
      return buffer[0];
   }
   
   bool GetBBValues(double &upper, double &middle, double &lower)
   {
      if(m_bbHandle == INVALID_HANDLE) return false;
      
      double upperBuffer[], middleBuffer[], lowerBuffer[];
      ArraySetAsSeries(upperBuffer, true);
      ArraySetAsSeries(middleBuffer, true);
      ArraySetAsSeries(lowerBuffer, true);
      
      if(CopyBuffer(m_bbHandle, 1, 0, 1, upperBuffer) < 1) return false;
      if(CopyBuffer(m_bbHandle, 0, 0, 1, middleBuffer) < 1) return false;
      if(CopyBuffer(m_bbHandle, 2, 0, 1, lowerBuffer) < 1) return false;
      
      upper = upperBuffer[0];
      middle = middleBuffer[0];
      lower = lowerBuffer[0];
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStopLossManager() :
      m_defaultMethod(STOP_ATR),
      m_atrMultiplier(2.0),
      m_fixedPips(20),
      m_maPeriod(20),
      m_bbDeviation(2.0),
      m_currentSymbol(""),
      m_maHandle(INVALID_HANDLE),
      m_atrHandle(INVALID_HANDLE),
      m_bbHandle(INVALID_HANDLE)
   {
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
   ~CStopLossManager()
   {
      CleanupHandles();
   }
   
   //+------------------------------------------------------------------+
   //| MAIN CALCULATION FUNCTION (Simple)                              |
   //+------------------------------------------------------------------+
   double Calculate(const string symbol, const bool isBuy, const double entryPrice,
               ENUM_STOP_METHOD method = STOP_STRUCTURE)
   {
      SStopLevel info;
      return Calculate(symbol, entryPrice, isBuy, method, info);
   }

   //+------------------------------------------------------------------+
   //| MAIN CALCULATION FUNCTION (With Info)                           |
   //+------------------------------------------------------------------+
   double Calculate(const string symbol,  double entryPrice, const bool isBuy,
                  ENUM_STOP_METHOD method, SStopLevel &info)
   {
      // Initialize indicator handles
      InitHandles(symbol);
      
      double stopPrice = 0;
      string reason = "";
      
      // Calculate based on selected method
      switch(method)
      {
         case STOP_STRUCTURE:
               stopPrice = CalculateStructureStop(symbol, isBuy, entryPrice, reason);
               break;
               
         case STOP_ATR:
               stopPrice = CalculateATRStop(symbol, isBuy, entryPrice, reason);
               break;
               
         case STOP_MA:
               stopPrice = CalculateMAStop(symbol, isBuy, entryPrice, reason);
               break;
               
         case STOP_BB:
               stopPrice = CalculateBBStop(symbol, isBuy, entryPrice, reason);
               break;
               
         case STOP_FIXED:
               stopPrice = CalculateFixedStop(symbol, isBuy, entryPrice, reason);
               break;
               
         default:
               stopPrice = CalculateStructureStop(symbol, isBuy, entryPrice, reason);
      }
      
      // Validate and normalize
      stopPrice = NormalizePrice(symbol, stopPrice);
      
      // Fill info structure
      info.price = stopPrice;
      info.method = method;
      info.reason = reason;
      info.time = TimeCurrent();
      
      return stopPrice;
   }
   
   //+------------------------------------------------------------------+
   //| SETTERS                                                          |
   //+------------------------------------------------------------------+
   void SetDefaultMethod(ENUM_STOP_METHOD method) { m_defaultMethod = method; }
   void SetATRMultiplier(double multiplier) { m_atrMultiplier = multiplier; }
   void SetFixedPips(double pips) { m_fixedPips = pips; }
   void SetMAPeriod(int period) { m_maPeriod = period; }
   void SetBBDeviation(double deviation) { m_bbDeviation = deviation; }

private:
   //+------------------------------------------------------------------+
   //| STOP CALCULATION METHODS                                         |
   //+------------------------------------------------------------------+
   
   // Structure-based (swing points)
   double CalculateStructureStop(const string symbol, const bool isBuy, 
                                 const double entryPrice, string &reason)
   {
      double stopPrice = 0;
      
      if(isBuy)
      {
         // For BUY: find swing low
         double swingLow = FindSwingLow(symbol, 30);
         if(swingLow > 0 && swingLow < entryPrice)
         {
            stopPrice = swingLow - GetPipDistance(symbol, 5);
            reason = "Below swing low";
         }
         else
         {
            // Fallback: recent low
            double lows[];
            CopyLow(symbol, PERIOD_CURRENT, 0, 10, lows);
            if(ArraySize(lows) > 0)
            {
               double recentLow = lows[ArrayMinimum(lows)];
               stopPrice = recentLow - GetPipDistance(symbol, 10);
               reason = "Below recent low";
            }
         }
      }
      else // SELL
      {
         // For SELL: find swing high
         double swingHigh = FindSwingHigh(symbol, 30);
         if(swingHigh > 0 && swingHigh > entryPrice)
         {
            stopPrice = swingHigh + GetPipDistance(symbol, 5);
            reason = "Above swing high";
         }
         else
         {
            // Fallback: recent high
            double highs[];
            CopyHigh(symbol, PERIOD_CURRENT, 0, 10, highs);
            if(ArraySize(highs) > 0)
            {
               double recentHigh = highs[ArrayMaximum(highs)];
               stopPrice = recentHigh + GetPipDistance(symbol, 10);
               reason = "Above recent high";
            }
         }
      }
      
      return stopPrice;
   }
   
   // ATR-based (volatility adjusted)
   double CalculateATRStop(const string symbol, const bool isBuy, 
                           const double entryPrice, string &reason)
   {
      double atr = GetATRValue();
      if(atr <= 0) return 0;
      
      if(isBuy)
      {
         double stopPrice = entryPrice - (atr * m_atrMultiplier);
         reason = StringFormat("ATR-based (%.1fx)", m_atrMultiplier);
         return stopPrice;
      }
      else
      {
         double stopPrice = entryPrice + (atr * m_atrMultiplier);
         reason = StringFormat("ATR-based (%.1fx)", m_atrMultiplier);
         return stopPrice;
      }
   }
   
   // MA-based
   double CalculateMAStop(const string symbol, const bool isBuy, 
                          const double entryPrice, string &reason)
   {
      double maValue = GetMAValue();
      if(maValue <= 0) return 0;
      
      if(isBuy)
      {
         double stopPrice = maValue - GetPipDistance(symbol, m_fixedPips);
         reason = StringFormat("Below %d-period MA", m_maPeriod);
         return stopPrice;
      }
      else
      {
         double stopPrice = maValue + GetPipDistance(symbol, m_fixedPips);
         reason = StringFormat("Above %d-period MA", m_maPeriod);
         return stopPrice;
      }
   }
   
   // Bollinger Bands based
   double CalculateBBStop(const string symbol, const bool isBuy, 
                          const double entryPrice, string &reason)
   {
      double upper, middle, lower;
      if(!GetBBValues(upper, middle, lower)) return 0;
      
      if(isBuy)
      {
         double stopPrice = lower - GetPipDistance(symbol, 5);
         reason = StringFormat("Below BB lower (%.1fσ)", m_bbDeviation);
         return stopPrice;
      }
      else
      {
         double stopPrice = upper + GetPipDistance(symbol, 5);
         reason = StringFormat("Above BB upper (%.1fσ)", m_bbDeviation);
         return stopPrice;
      }
   }
   
   // Fixed pips distance
   double CalculateFixedStop(const string symbol, const bool isBuy, 
                             const double entryPrice, string &reason)
   {
      if(isBuy)
      {
         double stopPrice = entryPrice - GetPipDistance(symbol, m_fixedPips);
         reason = StringFormat("Fixed %d pip stop", (int)m_fixedPips);
         return stopPrice;
      }
      else
      {
         double stopPrice = entryPrice + GetPipDistance(symbol, m_fixedPips);
         reason = StringFormat("Fixed %d pip stop", (int)m_fixedPips);
         return stopPrice;
      }
   }
   
   //+------------------------------------------------------------------+
   //| UTILITY METHODS                                                  |
   //+------------------------------------------------------------------+
   
   // Find swing low (simplified)
   double FindSwingLow(const string symbol, const int bars)
   {
      double lows[];
      ArraySetAsSeries(lows, true);
      if(CopyLow(symbol, PERIOD_CURRENT, 0, bars, lows) < bars) return 0;
      
      // Simple: lowest of last N bars
      return lows[ArrayMinimum(lows)];
   }
   
   // Find swing high (simplified)
   double FindSwingHigh(const string symbol, const int bars)
   {
      double highs[];
      ArraySetAsSeries(highs, true);
      if(CopyHigh(symbol, PERIOD_CURRENT, 0, bars, highs) < bars) return 0;
      
      // Simple: highest of last N bars
      return highs[ArrayMaximum(highs)];
   }
   
   // Convert pips to price distance
   double GetPipDistance(const string symbol, const double pips)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return pips * point * 10;
   }
   
   // Normalize price
   double NormalizePrice(const string symbol, double price)
   {
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      if(tickSize > 0)
         return NormalizeDouble(MathRound(price/tickSize)*tickSize, digits);
      
      return NormalizeDouble(price, digits);
   }
   
   // Validate stop placement
   bool ValidateStop(const string symbol, const double entry, 
                     const double stop, const bool isBuy)
   {
      if(stop <= 0) return false;
      
      double minDistance = GetPipDistance(symbol, 3);
      double distance = MathAbs(entry - stop);
      
      if(distance < minDistance) return false;
      
      if(isBuy && stop >= entry) return false;
      if(!isBuy && stop <= entry) return false;
      
      return true;
   }
};

//+------------------------------------------------------------------+
//| STATIC INTERFACE CLASS (Easy access)                             |
//+------------------------------------------------------------------+
class StopLoss
{
private:
   static CStopLossManager m_manager;
   
public:
   // Quick calculation methods - FIXED PARAMETER ORDER
   static double Calculate(const string symbol, const bool isBuy, 
                           const double entryPrice, ENUM_STOP_METHOD method = STOP_STRUCTURE)
   {
      SStopLevel info;
      return m_manager.Calculate(symbol, entryPrice, isBuy, method, info);
   }
   
   static double CalculateWithInfo(const string symbol, const bool isBuy, 
                                   const double entryPrice, ENUM_STOP_METHOD method,
                                   SStopLevel &info)
   {
      return m_manager.Calculate(symbol, entryPrice, isBuy, method, info);
   }
   
   // Method-specific shortcuts - ALL FIXED
   static double FromStructure(const string symbol, const bool isBuy, const double entryPrice)
   {
      SStopLevel info;
      return m_manager.Calculate(symbol, entryPrice, isBuy, STOP_STRUCTURE, info);
   }
   
   static double FromATR(const string symbol, const bool isBuy, const double entryPrice, 
                         double multiplier = 1.5)
   {
      SStopLevel info;
      m_manager.SetATRMultiplier(multiplier);
      return m_manager.Calculate(symbol, entryPrice, isBuy, STOP_ATR, info);
   }
   
   static double FromMA(const string symbol, const bool isBuy, const double entryPrice,
                        int period = 20)
   {
      SStopLevel info;
      m_manager.SetMAPeriod(period);
      return m_manager.Calculate(symbol, entryPrice, isBuy, STOP_MA, info);
   }
   
   static double FromBB(const string symbol, const bool isBuy, const double entryPrice,
                        double deviation = 2.0)
   {
      SStopLevel info;
      m_manager.SetBBDeviation(deviation);
      return m_manager.Calculate(symbol, entryPrice, isBuy, STOP_BB, info);
   }
   
   static double FromFixed(const string symbol, const bool isBuy, const double entryPrice,
                           double pips = 20)
   {
      SStopLevel info;
      m_manager.SetFixedPips(pips);
      return m_manager.Calculate(symbol, entryPrice, isBuy, STOP_FIXED, info);
   }
   
   // Configuration
   static void SetDefaultMethod(ENUM_STOP_METHOD method) { m_manager.SetDefaultMethod(method); }
   static void SetATRMultiplier(double multiplier) { m_manager.SetATRMultiplier(multiplier); }
   static void SetFixedPips(double pips) { m_manager.SetFixedPips(pips); }
   static void SetMAPeriod(int period) { m_manager.SetMAPeriod(period); }
   static void SetBBDeviation(double deviation) { m_manager.SetBBDeviation(deviation); }
};

// Initialize static manager
CStopLossManager StopLoss::m_manager;

//+------------------------------------------------------------------+
//| LEGACY FUNCTION INTERFACE (for backward compatibility)           |
//+------------------------------------------------------------------+
// Quick calculation (global function) - USE THE STATIC METHOD
double CalculateStopLoss(const string symbol, const bool isBuy, const double entryPrice,
                         ENUM_STOP_METHOD method = STOP_STRUCTURE)
{
   return StopLoss::Calculate(symbol, isBuy, entryPrice, method);
}