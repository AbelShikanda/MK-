//+------------------------------------------------------------------+
//|                                       IndicatorManager.mqh       |
//|               Efficient multi-timeframe indicator management     |
//|                       WITH FIXED ATR VALIDATION                 |
//+------------------------------------------------------------------+

#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"
// #include "../Data/tradepackage.mqh"

// Debug configuration
bool DEBUG_INDICATOR_ENABLED = true;

// Simple debug function using Logger
void DebugLogIndicator(string context, string message) {
   if(DEBUG_INDICATOR_ENABLED) {
      Logger::Log(context, message);
   }
}

void DebugLogIndicatorError(string context, string message, int error_code = 0) {
   if(DEBUG_INDICATOR_ENABLED) {
      if(error_code != 0) {
         Logger::LogError(context, message, error_code);
      } else {
         Logger::LogError(context, message);
      }
   }
}

void DebugLogIndicatorFast(string context, string message) {
   if(DEBUG_INDICATOR_ENABLED) {
      Logger::LogFast(context, message);
   }
}

class IndicatorManager
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframes[7];
   int m_timeframe_count;
   
   // Indicator handles organized by timeframe index
   struct IndicatorHandles
   {
      int ma_fast;      // Fast MA (e.g., 9 period)
      int ma_slow;      // Slow MA (e.g., 21 period)
      int rsi;          // RSI
      int macd;         // MACD
      int adx;          // ADX
      int stoch;        // Stochastic
      int atr;          // ATR
      int volume;       // Volumes
      int ma_medium;    // Medium MA (e.g., 89 period)
      int bbands;       // Bollinger Bands
   };
   
   IndicatorHandles m_handles[];
   bool m_initialized;
   
public:
   // CONSTRUCTOR - ONLY sets default values, NO indicator creation
   IndicatorManager(string symbol = NULL) 
   {
      m_symbol = (symbol == NULL) ? Symbol() : symbol;
      m_initialized = false;
      
      // ========== UPDATE: Add ALL timeframes your EA actually uses ==========
      // Your logs show: M1, M5, M15, M30, H1, H4, D1
      m_timeframes[0] = PERIOD_M1;    // Your EA uses M1
      m_timeframes[1] = PERIOD_M5;
      m_timeframes[2] = PERIOD_M15;
      m_timeframes[3] = PERIOD_M30;   // ← ADD THIS: Your EA uses M30!
      m_timeframes[4] = PERIOD_H1;
      m_timeframes[5] = PERIOD_H4;
      m_timeframes[6] = PERIOD_D1;
      m_timeframe_count = 7; // Now 7 timeframes
      // ========== END UPDATE ==========
      
      ArrayResize(m_handles, m_timeframe_count);
      ResetHandles();
   }
   
   ~IndicatorManager()
   {
      Deinitialize();
   }
   
   // INITIALIZE() - Creates actual resources, Sets up internal state
   bool Initialize()
   {
      if(m_initialized)
      {
         DebugLogIndicatorFast("IndicatorManager", "Already initialized");
         return true;
      }
      
      // Validate symbol exists BEFORE creating indicators
      if(!SymbolInfoInteger(m_symbol, SYMBOL_SELECT))
      {
         DebugLogIndicatorError("IndicatorManager", 
               StringFormat("Symbol %s not available for trading", m_symbol));
         return false;
      }
      
      for(int i = 0; i < m_timeframe_count; i++)
      {
         ENUM_TIMEFRAMES currentTF = m_timeframes[i];
         
         // ========== REMOVE THIS SECTION ==========
         // Delete this PERIOD_CURRENT special handling:
         // if(currentTF == PERIOD_CURRENT) {
         //     currentTF = PERIOD_H1;
         //     DebugLogIndicator("IndicatorManager", "Using H1 for PERIOD_CURRENT indicators");
         // }
         // ========== END REMOVE ==========
         
         // Validate timeframe is valid
         if(!IsTimeframeAvailable(currentTF))
         {
               DebugLogIndicatorError("IndicatorManager", 
                  StringFormat("Timeframe %d not available for %s", 
                  currentTF, m_symbol));
               continue;
         }
         
         // Create indicators with the actual timeframe
         m_handles[i].ma_fast = iMA(m_symbol, currentTF, 9, 0, MODE_EMA, PRICE_CLOSE);
         m_handles[i].ma_slow = iMA(m_symbol, currentTF, 21, 0, MODE_SMA, PRICE_CLOSE);
         m_handles[i].ma_medium = iMA(m_symbol, currentTF, 89, 0, MODE_SMA, PRICE_CLOSE);
         m_handles[i].rsi = iRSI(m_symbol, currentTF, 14, PRICE_CLOSE);
         m_handles[i].macd = iMACD(m_symbol, currentTF, 12, 26, 9, PRICE_CLOSE);
         m_handles[i].adx = iADX(m_symbol, currentTF, 14);
         m_handles[i].stoch = iStochastic(m_symbol, currentTF, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
         m_handles[i].atr = iATR(m_symbol, currentTF, 14);
         m_handles[i].volume = iVolumes(m_symbol, currentTF, VOLUME_TICK); // see if you can also fine real volume
         m_handles[i].bbands = iBands(m_symbol, currentTF, 20, 0, 2.0, PRICE_CLOSE);
         
         // Log what we created
         DebugLogIndicator("IndicatorManager", 
               StringFormat("Created indicators for TF: %d (array index: %d)", 
               currentTF, i));
         
         // Test ATR handle specifically
         if(!ValidateHandle(m_handles[i].atr))
         {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Failed to create ATR for timeframe %d", 
                  currentTF));
         }
      }
      
      m_initialized = true;
      DebugLogIndicatorFast("IndicatorManager", "Initialized successfully with M1 support");
      return true;
   }
   
   // DEINITIALIZE() - Closes/frees resources, Resets m_initialized flag
   void Deinitialize()
   {
      if(!m_initialized) return;
      
      for(int i = 0; i < m_timeframe_count; i++)
      {
         if(ValidateHandle(m_handles[i].ma_fast)) IndicatorRelease(m_handles[i].ma_fast);
         if(ValidateHandle(m_handles[i].ma_slow)) IndicatorRelease(m_handles[i].ma_slow);
         if(ValidateHandle(m_handles[i].ma_medium)) IndicatorRelease(m_handles[i].ma_medium);
         if(ValidateHandle(m_handles[i].rsi)) IndicatorRelease(m_handles[i].rsi);
         if(ValidateHandle(m_handles[i].macd)) IndicatorRelease(m_handles[i].macd);
         if(ValidateHandle(m_handles[i].adx)) IndicatorRelease(m_handles[i].adx);
         if(ValidateHandle(m_handles[i].stoch)) IndicatorRelease(m_handles[i].stoch);
         if(ValidateHandle(m_handles[i].atr)) IndicatorRelease(m_handles[i].atr);
         if(ValidateHandle(m_handles[i].volume)) IndicatorRelease(m_handles[i].volume);
         if(ValidateHandle(m_handles[i].bbands)) IndicatorRelease(m_handles[i].bbands);
      }
      
      ResetHandles();
      m_initialized = false;
      DebugLogIndicatorFast("IndicatorManager", "Deinitialized");
   }
   
   // Check if timeframe is available
   bool IsTimeframeAvailable(ENUM_TIMEFRAMES tf)
   {
      // Validate timeframe is within valid range
      return (tf >= PERIOD_M1 && tf <= PERIOD_MN1);
   }
   
   // EVENT HANDLERS - only process if initialized
   void OnTick()
   {
      if(!m_initialized) return;
      
      // Optional: Update indicator values or perform tick-based calculations
   }
   
   void OnTimer()
   {
      if(!m_initialized) return;
      
      // Optional: Periodic updates or monitoring
   }
   
   void OnTradeTransaction(const MqlTradeTransaction& trans,
                          const MqlTradeRequest& request,
                          const MqlTradeResult& result)
   {
      if(!m_initialized) return;
      
      // Optional: Handle trade-related events
   }
   
   // Get Moving Average values
   bool GetMAValues(ENUM_TIMEFRAMES tf, double &ma_fast, double &ma_slow, double &ma_medium, int shift = 0)
   {
      if(!m_initialized) 
      {
         ma_fast = ma_slow = ma_medium = 0.0;
         return false;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         ma_fast = ma_slow = ma_medium = 0.0;
         return false;
      }
      
      ma_fast = GetIndicatorValue(m_handles[idx].ma_fast, 0, shift);
      ma_slow = GetIndicatorValue(m_handles[idx].ma_slow, 0, shift);
      ma_medium = GetIndicatorValue(m_handles[idx].ma_medium, 0, shift);
      
      bool allValid = (ma_fast != 0.0 && ma_slow != 0.0 && ma_medium != 0.0);
      
      if(!allValid)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Some MA values invalid: fast=%.5f, slow=%.5f, medium=%.5f", 
            ma_fast, ma_slow, ma_medium));
      }
      
      return allValid;
   }
   
   // Get RSI value
   double GetRSI(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      if(!m_initialized) 
      {
         DebugLogIndicator("IndicatorManager", "Not initialized in GetRSI");
         return 50.0; // Return neutral RSI
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Timeframe %d not found in GetRSI", tf));
         return 50.0;
      }
      
      double rsiValue = GetIndicatorValue(m_handles[idx].rsi, 0, shift);
      
      // Validate RSI is in reasonable range
      if(rsiValue <= 0 || rsiValue >= 100)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Invalid RSI value: %.1f, using 50.0", rsiValue));
         return 50.0;
      }
      
      return rsiValue;
   }
   
   // Get MACD values
   bool GetMACDValues(ENUM_TIMEFRAMES tf, double &macd_main, double &macd_signal, int shift = 0)
   {
      if(!m_initialized) 
      {
         macd_main = macd_signal = 0.0;
         return false;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         macd_main = macd_signal = 0.0;
         return false;
      }
      
      macd_main = GetIndicatorValue(m_handles[idx].macd, MAIN_LINE, shift);
      macd_signal = GetIndicatorValue(m_handles[idx].macd, SIGNAL_LINE, shift);
      
      bool bothValid = (macd_main != 0.0 && macd_signal != 0.0);
      
      if(!bothValid)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Invalid MACD values: main=%.5f, signal=%.5f", 
            macd_main, macd_signal));
      }
      
      return bothValid;
   }
   
   // Get ADX values (ADX, +DI, -DI)
   bool GetADXValues(ENUM_TIMEFRAMES tf, double &adx, double &plus_di, double &minus_di, int shift = 0)
   {
      if(!m_initialized) 
      {
         adx = plus_di = minus_di = 0.0;
         return false;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         adx = plus_di = minus_di = 0.0;
         return false;
      }
      
      adx = GetIndicatorValue(m_handles[idx].adx, 0, shift);       // ADX line
      plus_di = GetIndicatorValue(m_handles[idx].adx, 1, shift);   // +DI line
      minus_di = GetIndicatorValue(m_handles[idx].adx, 2, shift);  // -DI line
      
      bool allValid = (adx != 0.0 && plus_di != 0.0 && minus_di != 0.0);
      
      if(!allValid)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Invalid ADX values: ADX=%.5f, +DI=%.5f, -DI=%.5f", 
            adx, plus_di, minus_di));
      }
      
      return allValid;
   }
   
   // Get Stochastic values
   bool GetStochasticValues(ENUM_TIMEFRAMES tf, double &stoch_main, double &stoch_signal, int shift = 0)
   {
      if(!m_initialized) 
      {
         stoch_main = stoch_signal = 0.0;
         return false;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         stoch_main = stoch_signal = 0.0;
         return false;
      }
      
      stoch_main = GetIndicatorValue(m_handles[idx].stoch, 0, shift);   // %K line
      stoch_signal = GetIndicatorValue(m_handles[idx].stoch, 1, shift); // %D line
      
      bool bothValid = (stoch_main != 0.0 && stoch_signal != 0.0);
      
      if(!bothValid)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Invalid Stochastic values: main=%.5f, signal=%.5f", 
            stoch_main, stoch_signal));
      }
      
      return bothValid;
   }
   
   // Get ATR value (for stop loss, position sizing) - FIXED VERSION
   double GetATR(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      if(!m_initialized) 
      {
         DebugLogIndicatorError("IndicatorManager", "Not initialized in GetATR");
         return GetDefaultATR();
      }
      
      int idx = GetTimeframeIndex(tf);
      
      // DEBUG: Log what we're looking for
      DebugLogIndicator("IndicatorManager", 
         StringFormat("GetATR called: tf=%d, GetTimeframeIndex returned: %d", tf, idx));
      
      if(idx == -1) 
      {
         // Provide better error message
         DebugLogIndicatorError("IndicatorManager", 
               StringFormat("Timeframe %d not found in GetATR. Available TFs: M1=%d, M5=%d, M15=%d, H1=%d, H4=%d, D1=%d",
               tf, PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1));
         
         // Try to use H1 as fallback
         idx = GetTimeframeIndex(PERIOD_H1);
         if(idx == -1) {
               return GetDefaultATR();
         }
      }
      
      // Check if we have a valid handle at this index
      if(idx < 0 || idx >= m_timeframe_count)
      {
         DebugLogIndicatorError("IndicatorManager", 
               StringFormat("Invalid index %d for timeframe %d (array size: %d)", 
               idx, tf, m_timeframe_count));
         return GetDefaultATR();
      }
      
      if(m_handles[idx].atr == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager", 
               StringFormat("ATR handle invalid at index %d for timeframe %d", idx, tf));
         
         // Try to create the handle on the fly
         DebugLogIndicator("IndicatorManager", "Creating ATR handle on the fly...");
         m_handles[idx].atr = iATR(m_symbol, tf, 14);
         
         if(m_handles[idx].atr == INVALID_HANDLE) {
               return GetDefaultATR();
         }
      }
      
      double atrValue = GetIndicatorValue(m_handles[idx].atr, 0, shift);
      
      // Validate ATR value
      if(atrValue <= 0 || !MathIsValidNumber(atrValue))
      {
         DebugLogIndicator("IndicatorManager", 
               StringFormat("Invalid ATR value: %.5f on TF %d (idx: %d)", atrValue, tf, idx));
         return GetDefaultATR();
      }
      
      // ========== ADD M1 VALIDATION ==========
      if(tf == PERIOD_M1)
      {
         // M1 ATR is very small - add special validation
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         
         if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         {
               // Gold M1 ATR should be around 0.05-0.8
               double minGoldATR = 0.05;  // $0.05 minimum (5 cents)
               double maxGoldATR = 0.8;   // $0.80 maximum (80 cents)
               
               if(atrValue < minGoldATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Gold M1 ATR too small: %.5f, using %.2f", 
                     atrValue, minGoldATR));
                  atrValue = minGoldATR;
               }
               else if(atrValue > maxGoldATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Gold M1 ATR too large: %.5f, using %.2f", 
                     atrValue, maxGoldATR));
                  atrValue = maxGoldATR;
               }
         }
         else if(StringFind(m_symbol, "XAG") >= 0 || StringFind(m_symbol, "SILVER") >= 0)
         {
               // Silver M1 ATR should be around 0.01-0.15
               double minSilverATR = 0.01;  // $0.01 minimum
               double maxSilverATR = 0.15;  // $0.15 maximum
               
               if(atrValue < minSilverATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Silver M1 ATR too small: %.5f, using %.2f", 
                     atrValue, minSilverATR));
                  atrValue = minSilverATR;
               }
               else if(atrValue > maxSilverATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Silver M1 ATR too large: %.5f, using %.2f", 
                     atrValue, maxSilverATR));
                  atrValue = maxSilverATR;
               }
         }
         else if(StringFind(m_symbol, "BTC") >= 0 || StringFind(m_symbol, "ETH") >= 0)
         {
               // Crypto M1 ATR should be around 5-50
               double minCryptoATR = 5.0;   // $5 minimum
               double maxCryptoATR = 50.0;  // $50 maximum
               
               if(atrValue < minCryptoATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Crypto M1 ATR too small: %.5f, using %.1f", 
                     atrValue, minCryptoATR));
                  atrValue = minCryptoATR;
               }
               else if(atrValue > maxCryptoATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Crypto M1 ATR too large: %.5f, using %.1f", 
                     atrValue, maxCryptoATR));
                  atrValue = maxCryptoATR;
               }
         }
         else
         {
               // Forex M1 ATR should be around 0.00003-0.0003 (0.3-3 pips)
               double minForexATR = 0.00003;  // 0.3 pips minimum
               double maxForexATR = 0.0003;   // 3 pips maximum
               
               if(atrValue < minForexATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Forex M1 ATR too small: %.6f, using %.6f", 
                     atrValue, minForexATR));
                  atrValue = minForexATR;
               }
               else if(atrValue > maxForexATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Forex M1 ATR too large: %.6f, using %.6f", 
                     atrValue, maxForexATR));
                  atrValue = maxForexATR;
               }
         }
      }
      // ========== END M1 VALIDATION ==========

      // ========== ADD M30 VALIDATION ==========
      if(tf == PERIOD_M30)
      {
         if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         {
               // Gold M30 ATR should be around 1.0-4.0
               double minGoldATR = 1.0;   // $1.00 minimum
               double maxGoldATR = 4.0;   // $4.00 maximum
               
               if(atrValue < minGoldATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Gold M30 ATR too small: %.5f, using %.1f", 
                     atrValue, minGoldATR));
                  atrValue = minGoldATR;
               }
               else if(atrValue > maxGoldATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Gold M30 ATR too large: %.5f, using %.1f", 
                     atrValue, maxGoldATR));
                  atrValue = maxGoldATR;
               }
         }
         else
         {
               // Forex M30 ATR should be around 0.0005-0.0015 (5-15 pips)
               double minForexATR = 0.0005;   // 5 pips minimum
               double maxForexATR = 0.0015;   // 15 pips maximum
               
               if(atrValue < minForexATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Forex M30 ATR too small: %.6f, using %.6f", 
                     atrValue, minForexATR));
                  atrValue = minForexATR;
               }
               else if(atrValue > maxForexATR) {
                  DebugLogIndicator("IndicatorManager", 
                     StringFormat("Forex M30 ATR too large: %.6f, using %.6f", 
                     atrValue, maxForexATR));
                  atrValue = maxForexATR;
               }
         }
      }
      // ========== END M30 VALIDATION ==========
      
      // Existing ATR validation with symbol-specific limits
      if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
      {
         // Gold ATR sanity checks based on timeframe
         double maxATR = 50.0;
         double minATR = 1.0;
         
         if(tf == PERIOD_M1) {
               maxATR = 0.8;    // M1: max $0.8
               minATR = 0.05;   // M1: min $0.05
         } else if(tf == PERIOD_M5) {
               maxATR = 2.0;    // M5: max $2
               minATR = 0.2;    // M5: min $0.2
         } else if(tf == PERIOD_M15) {
               maxATR = 3.0;    // M15: max $3
               minATR = 0.5;    // M15: min $0.5
         } else if(tf == PERIOD_M30) {  // ← ADD M30
               maxATR = 4.0;    // M30: max $4
               minATR = 1.0;    // M30: min $1
         } else if(tf == PERIOD_H1) {
               maxATR = 5.0;    // H1: max $5
               minATR = 1.0;    // H1: min $1
         } else if(tf == PERIOD_H4) {
               maxATR = 8.0;    // H4: max $8
               minATR = 2.0;    // H4: min $2
         } else if(tf == PERIOD_D1) {
               maxATR = 15.0;   // D1: max $15
               minATR = 5.0;    // D1: min $5
         }
         
         if(atrValue > maxATR) {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Gold ATR too large: %.5f > %.1f, capping to %.1f", 
                  atrValue, maxATR, maxATR));
               atrValue = maxATR;
         } else if(atrValue < minATR) {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Gold ATR too small: %.5f < %.1f, using %.1f", 
                  atrValue, minATR, minATR));
               atrValue = minATR;
         }
      }
      else
      {
         double maxATR = 0.01;    // 100 pips max
         double minATR = 0.0001;  // 1 pip min
         
         // Adjust based on timeframe
         if(tf == PERIOD_M1) {
               maxATR = 0.0003;    // M1: 3 pips max
               minATR = 0.00003;   // M1: 0.3 pips min
         } else if(tf == PERIOD_M5) {
               maxATR = 0.0008;    // M5: 8 pips max
               minATR = 0.0001;    // M5: 1 pip min
         } else if(tf == PERIOD_M15) {
               maxATR = 0.0015;    // M15: 15 pips max
               minATR = 0.0003;    // M15: 3 pips min
         } else if(tf == PERIOD_M30) {  // ← ADD M30
               maxATR = 0.0020;    // M30: 20 pips max
               minATR = 0.0005;    // M30: 5 pips min
         } else if(tf == PERIOD_H1) {
               maxATR = 0.0030;    // H1: 30 pips max
               minATR = 0.0010;    // H1: 10 pips min
         }
         
         if(atrValue > maxATR) {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Forex ATR too large: %.5f > %.5f, capping to %.5f", 
                  atrValue, maxATR, maxATR));
               atrValue = maxATR;
         } else if(atrValue < minATR) {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Forex ATR too small: %.5f < %.5f, using %.5f", 
                  atrValue, minATR, minATR));
               atrValue = minATR;
         }
      }
      
      DebugLogIndicator("IndicatorManager", 
         StringFormat("GetATR result: symbol=%s, tf=%d, idx=%d, shift=%d, value=%.5f", 
         m_symbol, tf, idx, shift, atrValue));
      
      return atrValue;
   }
   
   // Enhanced ATR method with fallback
   double GetATRWithFallback(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      double atrValue = GetATR(tf, shift);
      
      if(atrValue > 0)
      {
         return atrValue; // Valid ATR
      }
      
      DebugLogIndicator("IndicatorManager", 
         StringFormat("Primary ATR failed on TF %d, trying fallback...", tf));
      
      // Try other timeframes in order of reliability
      ENUM_TIMEFRAMES fallbackTFs[] = {PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_M15};
      
      for(int i = 0; i < ArraySize(fallbackTFs); i++)
      {
         if(fallbackTFs[i] == tf) continue; // Skip the one that failed
         
         int idx = GetTimeframeIndex(fallbackTFs[i]);
         if(idx != -1 && m_handles[idx].atr != INVALID_HANDLE)
         {
            double fallbackATR = GetIndicatorValue(m_handles[idx].atr, 0, shift);
            if(fallbackATR > 0)
            {
               DebugLogIndicator("IndicatorManager", 
                  StringFormat("Got ATR from fallback TF %d: %.5f", 
                  fallbackTFs[i], fallbackATR));
               return fallbackATR;
            }
         }
      }
      
      // If all else fails, calculate ATR directly
      DebugLogIndicator("IndicatorManager", "All ATRs failed, calculating directly...");
      return CalculateDirectATR();
   }
   
   // Get Volume value
   double GetVolume(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      if(!m_initialized) 
      {
         DebugLogIndicator("IndicatorManager", "Not initialized in GetVolume");
         return 0.0;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Timeframe %d not found in GetVolume", tf));
         return 0.0;
      }
      
      return GetIndicatorValue(m_handles[idx].volume, 0, shift);
   }
   
   // Get Bollinger Bands values
   bool GetBollingerBandsValues(ENUM_TIMEFRAMES tf, double &upper, double &middle, double &lower, int shift = 0)
   {
      if(!m_initialized) 
      {
         upper = middle = lower = 0.0;
         return false;
      }
      
      int idx = GetTimeframeIndex(tf);
      if(idx == -1) 
      {
         upper = middle = lower = 0.0;
         return false;
      }
      
      upper = GetIndicatorValue(m_handles[idx].bbands, 0, shift);   // Upper band
      middle = GetIndicatorValue(m_handles[idx].bbands, 1, shift);  // Middle band
      lower = GetIndicatorValue(m_handles[idx].bbands, 2, shift);   // Lower band
      
      bool allValid = (upper != 0.0 && middle != 0.0 && lower != 0.0);
      
      if(!allValid)
      {
         DebugLogIndicator("IndicatorManager", 
            StringFormat("Invalid BBands values: upper=%.5f, middle=%.5f, lower=%.5f", 
            upper, middle, lower));
      }
      
      return allValid;
   }
   
   // Comprehensive trend analysis across timeframes
   bool IsTrendBullish(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return false;
      
      double ma_fast, ma_slow, ma_medium;
      if(!GetMAValues(tf, ma_fast, ma_slow, ma_medium))
         return false;
      
      // Bullish if fast MA > slow MA > medium MA
      return (ma_fast > ma_slow && ma_slow > ma_medium);
   }
   
   bool IsTrendBearish(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return false;
      
      double ma_fast, ma_slow, ma_medium;
      if(!GetMAValues(tf, ma_fast, ma_slow, ma_medium))
         return false;
      
      // Bearish if fast MA < slow MA < medium MA
      return (ma_fast < ma_slow && ma_slow < ma_medium);
   }
   
   // Check if market is overbought on RSI and Stochastic
   bool IsOverbought(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return false;
      
      double rsi = GetRSI(tf);
      double stoch_main, stoch_signal;
      if(!GetStochasticValues(tf, stoch_main, stoch_signal))
         return false;
      
      return (rsi > 70 && stoch_main > 80);
   }
   
   // Check if market is oversold on RSI and Stochastic
   bool IsOversold(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return false;
      
      double rsi = GetRSI(tf);
      double stoch_main, stoch_signal;
      if(!GetStochasticValues(tf, stoch_main, stoch_signal))
         return false;
      
      return (rsi < 30 && stoch_main < 20);
   }
   
   // Check trend strength using ADX
   bool IsStrongTrend(ENUM_TIMEFRAMES tf, int threshold = 25)
   {
      if(!m_initialized) return false;
      
      double adx, plus_di, minus_di;
      if(!GetADXValues(tf, adx, plus_di, minus_di))
         return false;
      
      return (adx > threshold);
   }
   
   // Get trend direction using ADX (+DI vs -DI)
   int GetADXTrendDirection(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return 0;
      
      double adx, plus_di, minus_di;
      if(!GetADXValues(tf, adx, plus_di, minus_di))
         return 0;
      
      if(plus_di > minus_di) return 1;   // Bullish
      if(plus_di < minus_di) return -1;  // Bearish
      return 0;                          // Neutral
   }
   
   // Check for MACD crossover
   int GetMACDCrossover(ENUM_TIMEFRAMES tf)
   {
      if(!m_initialized) return 0;
      
      double macd_main_current, macd_signal_current;
      double macd_main_prev, macd_signal_prev;
      
      if(!GetMACDValues(tf, macd_main_current, macd_signal_current, 0))
         return 0;
      if(!GetMACDValues(tf, macd_main_prev, macd_signal_prev, 1))
         return 0;
      
      // Bullish crossover: MACD crosses above signal
      if(macd_main_prev <= macd_signal_prev && macd_main_current > macd_signal_current)
         return 1;
      
      // Bearish crossover: MACD crosses below signal
      if(macd_main_prev >= macd_signal_prev && macd_main_current < macd_signal_current)
         return -1;
      
      return 0;
   }
   
   // Multi-timeframe confirmation with chart score display
   bool GetMultiTimeframeConfirmation(int &bullish_tf_count, int &bearish_tf_count)
   {
      if(!m_initialized) return false;
      
      bullish_tf_count = 0;
      bearish_tf_count = 0;
      
      for(int i = 0; i < m_timeframe_count; i++)
      {
         if(IsTrendBullish(m_timeframes[i]))
            bullish_tf_count++;
         else if(IsTrendBearish(m_timeframes[i]))
            bearish_tf_count++;
      }
      
      // Show score on chart using Logger's static method
      if(bullish_tf_count > 0 || bearish_tf_count > 0)
      {
         double score = (double)bullish_tf_count / (m_timeframe_count * 1.0);
         string signal = bullish_tf_count > bearish_tf_count ? "BUY" : 
                        bearish_tf_count > bullish_tf_count ? "SELL" : "NEUTRAL";
         
         // Use Logger's static method for chart display
         Logger::ShowScoreFast(m_symbol, score, signal, 0.8);
      }
      
      return (bullish_tf_count > 0 || bearish_tf_count > 0);
   }
   
   // Get price position relative to Bollinger Bands
   int GetBBandsPosition(ENUM_TIMEFRAMES tf, double price)
   {
      if(!m_initialized) return 0;
      
      double upper, middle, lower;
      if(!GetBollingerBandsValues(tf, upper, middle, lower))
         return 0;
      
      if(price >= upper) return 1;     // Overbought/upper band
      if(price <= lower) return -1;    // Oversold/lower band
      if(price > middle) return 2;     // Upper half
      if(price < middle) return -2;    // Lower half
      return 0;                        // At middle band
   }
   
   // Calculate position size based on ATR
   double CalculatePositionSize(double risk_percent, double stop_loss_pips, ENUM_TIMEFRAMES tf = PERIOD_H1)
   {
      if(!m_initialized) return 0.01;
      
      double atr_value = GetATRWithFallback(tf);
      
      if(atr_value <= 0)
         return 0.01;
      
      double atr_pips = MathUtils::PriceToPips(m_symbol, atr_value);
      
      // Ensure stop loss is at least 1 ATR
      if(stop_loss_pips < atr_pips)
         stop_loss_pips = atr_pips;
      
      double current_price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      return MathUtils::CalculatePositionSizeByRisk(m_symbol, current_price, 
                current_price - (stop_loss_pips * Point()), 
                risk_percent, account_balance);
   }
   
   // Get current market analysis score (0-1)
   double GetMarketScore()
   {
      if(!m_initialized) return 0.5;
      
      int bullish_tf_count, bearish_tf_count;
      GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
      
      double rsi = GetRSI(PERIOD_H1);
      double atr = GetATRWithFallback(PERIOD_H1);
      
      // Simple scoring logic
      double score = 0.5;
      
      if(bullish_tf_count > bearish_tf_count)
         score += 0.2;
      else if(bearish_tf_count > bullish_tf_count)
         score -= 0.2;
         
      if(rsi > 70) score -= 0.1;
      else if(rsi < 30) score += 0.1;
      
      return MathMax(0.0, MathMin(1.0, score));
   }
   
   // Get initialization status
   bool IsInitialized() const { return m_initialized; }
   
   // Get current symbol
   string GetSymbol() const { return m_symbol; }
   
   // Test method to verify ATR functionality
   void TestATRFunctionality()
   {
      if(!m_initialized)
      {
         DebugLogIndicator("IndicatorManager", "IndicatorManager not initialized");
         return;
      }
      
      DebugLogIndicatorFast("IndicatorManager", "=== ATR Functionality Test ===");
      DebugLogIndicator("IndicatorManager", StringFormat("Symbol: %s", m_symbol));
      
      for(int i = 0; i < m_timeframe_count; i++)
      {
         double atr = GetATR(m_timeframes[i], 0);
         DebugLogIndicator("IndicatorManager", StringFormat("TF %d ATR: %.5f (handle: %d)", 
               m_timeframes[i], atr, m_handles[i].atr));
      }
      
      // Test fallback
      double fallbackATR = GetATRWithFallback(PERIOD_H1, 0);
      DebugLogIndicator("IndicatorManager", StringFormat("Fallback ATR: %.5f", fallbackATR));
      DebugLogIndicatorFast("IndicatorManager", "=== End Test ===");
   }
   
private:
   // Helper function to get indicator value - FIXED VERSION
   double GetIndicatorValue(int handle, int buffer_num, int shift)
   {
      if(handle == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("Invalid handle in GetIndicatorValue: handle=%d", handle));
         return 0.0; // Return 0.0, NOT EMPTY_VALUE
      }
      
      double buffer[1];
      ArrayInitialize(buffer, 0.0); // Initialize to 0
      
      int copied = CopyBuffer(handle, buffer_num, shift, 1, buffer);
      
      if(copied <= 0)
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("CopyBuffer failed: handle=%d, buffer=%d, shift=%d, copied=%d", 
            handle, buffer_num, shift, copied));
         return 0.0; // Return 0.0 on failure
      }
      
      double value = buffer[0];
      
      // CRITICAL: Check for EMPTY_VALUE (which equals DBL_MAX = 1.79e+308)
      if(value == EMPTY_VALUE)
      {
         DebugLogIndicatorError("IndicatorManager", "EMPTY_VALUE detected in GetIndicatorValue");
         return 0.0; // Return 0.0
      }
      
      // Check if value is a valid number (not NaN or infinite)
      if(!MathIsValidNumber(value))
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("NaN or infinite value detected: %.5f", value));
         return 0.0; // Return 0.0
      }
      
      // Additional validation for unrealistically large values
      if(MathAbs(value) > 1e100) // Unrealistically large
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("Unrealistic value: %.5f (abs > 1e100)", value));
         return 0.0; // Return 0.0
      }
      
      return value;
   }

   int GetTimeframeIndex(ENUM_TIMEFRAMES tf)
   {
      // Simple exact match search
      for(int i = 0; i < m_timeframe_count; i++)
      {
         if(m_timeframes[i] == tf)
               return i;
      }
      
      // If not found, provide helpful error message
      // REMOVE THIS LINE: string tfNames[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};
      string requestedTF = "Unknown";
      
      // Convert timeframe enum to name for better logging
      switch(tf)
      {
         case PERIOD_M1:  requestedTF = "M1"; break;
         case PERIOD_M5:  requestedTF = "M5"; break;
         case PERIOD_M15: requestedTF = "M15"; break;
         case PERIOD_M30: requestedTF = "M30"; break;
         case PERIOD_H1:  requestedTF = "H1"; break;
         case PERIOD_H4:  requestedTF = "H4"; break;
         case PERIOD_D1:  requestedTF = "D1"; break;
         default: requestedTF = "TF-" + IntegerToString(tf); break;
      }
      
      DebugLogIndicatorError("IndicatorManager", 
         StringFormat("Timeframe %s (%d) not found. Available: M1, M5, M15, M30, H1, H4, D1", 
         requestedTF, tf));

      // ExpertRemove(); // Critical: remove EA to prevent further errors
      return -1;
   }
   
   // Validate handle
   bool ValidateHandle(int handle)
   {
      if(handle == INVALID_HANDLE || handle == 0)
      {
         return false;
      }
      
      return true;
   }
   
   // Reset all handles
   void ResetHandles()
   {
      for(int i = 0; i < m_timeframe_count; i++)
      {
         m_handles[i].ma_fast = INVALID_HANDLE;
         m_handles[i].ma_slow = INVALID_HANDLE;
         m_handles[i].ma_medium = INVALID_HANDLE;
         m_handles[i].rsi = INVALID_HANDLE;
         m_handles[i].macd = INVALID_HANDLE;
         m_handles[i].adx = INVALID_HANDLE;
         m_handles[i].stoch = INVALID_HANDLE;
         m_handles[i].atr = INVALID_HANDLE;
         m_handles[i].volume = INVALID_HANDLE;
         m_handles[i].bbands = INVALID_HANDLE;
      }
   }
   
   // Direct ATR calculation as last resort
   double CalculateDirectATR()
   {
      DebugLogIndicator("IndicatorManager", 
         StringFormat("Calculating direct ATR for %s on H4", m_symbol));
      
      // Use H4 timeframe for reliability
      int atrHandle = iATR(m_symbol, PERIOD_H4, 14);
      if(atrHandle == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager", "Direct ATR calculation failed");
         return GetDefaultATR();
      }
      
      double buffer[1];
      ArrayInitialize(buffer, 0.0);
      
      int copied = CopyBuffer(atrHandle, 0, 0, 1, buffer);
      IndicatorRelease(atrHandle);
      
      if(copied <= 0)
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("Direct ATR CopyBuffer failed, copied=%d", copied));
         return GetDefaultATR();
      }
      
      double atrValue = buffer[0];
      
      // Validate the direct calculation
      if(atrValue <= 0 || !MathIsValidNumber(atrValue))
      {
         DebugLogIndicatorError("IndicatorManager", 
            StringFormat("Invalid direct ATR: %.5f", atrValue));
         return GetDefaultATR();
      }
      
      DebugLogIndicator("IndicatorManager", 
         StringFormat("Direct ATR calculated: %.5f", atrValue));
      
      return atrValue;
   }
   
   // Get default ATR based on symbol - IMPROVED VERSION
   double GetDefaultATR()
   {
      if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Gold ATR: 10.0 ($10)");
         return 10.0; // $10 for Gold (reasonable default for H1 timeframe)
      }
      else if(StringFind(m_symbol, "XAG") >= 0 || StringFind(m_symbol, "SILVER") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Silver ATR: 0.15 ($0.15)");
         return 0.15; // $0.15 for Silver
      }
      else if(StringFind(m_symbol, "BTC") >= 0 || StringFind(m_symbol, "ETH") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Crypto ATR: 100.0 ($100)");
         return 100.0; // $100 for Crypto
      }
      else if(StringFind(m_symbol, "EURUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default EURUSD ATR: 0.0005 (5 pips)");
         return 0.0005; // 5 pips for EURUSD
      }
      else if(StringFind(m_symbol, "GBPUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default GBPUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for GBPUSD
      }
      else if(StringFind(m_symbol, "USDJPY") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default USDJPY ATR: 0.08 (8 pips)");
         return 0.08; // 8 pips for USDJPY
      }
      else if(StringFind(m_symbol, "AUDUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default AUDUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for AUDUSD
      }
      else if(StringFind(m_symbol, "USDCAD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default USDCAD ATR: 0.0007 (7 pips)");
         return 0.0007; // 7 pips for USDCAD
      }
      else if(StringFind(m_symbol, "NZDUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default NZDUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for NZDUSD
      }
      else if(StringFind(m_symbol, "USDCHF") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default USDCHF ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for USDCHF
      }
      else
      {
         DebugLogIndicator("IndicatorManager", "Using generic default ATR: 0.0007 (7 pips)");
         return 0.0007; // 7 pips generic default
      }
   }

   // // NEW METHOD: Update all modules and auto-execute
   //  bool UpdateAllModulesAndExecute() {
   //      DebugLogEA("IndicatorManager", "Updating all modules and auto-executing...");
        
   //      // 1. Update all analysis modules
   //      if(!UpdateAllModules()) {
   //          DebugLogEA("IndicatorManager", "Failed to update modules");
   //          return false;
   //      }
        
   //      // 2. Check if TradePackage exists
   //      if(m_tradePackage == NULL) {
   //          DebugLogEA("IndicatorManager", "TradePackage not set");
   //          return false;
   //      }
        
   //      // 3. Let TradePackage handle auto-execution
   //      bool executed = m_tradePackage->UpdateAndExecute();
        
   //      if(executed) {
   //          DebugLogEA("IndicatorManager", "TradePackage executed successfully via auto-execution");
   //      }
   //      else {
   //          DebugLogEA("IndicatorManager", "TradePackage not executed (low confidence or no action)");
   //      }
        
   //      return executed;
   //  }
    
   //  // Update existing UpdateAllModules to return bool
   //  bool UpdateAllModules() {
   //      bool success = true;
        
   //      // Update each module
   //      for(int i = 0; i < modules.Count(); i++) {
   //          BaseModule* module = modules[i];
   //          if(!module->Update()) {
   //              DebugLogEA("IndicatorManager", StringFormat("Module %d failed to update", i));
   //              success = false;
   //          }
   //      }
        
   //      return success;
   //  }
};