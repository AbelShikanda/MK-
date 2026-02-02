//+------------------------------------------------------------------+
//|                                       IndicatorManager.mqh       |
//|               Efficient multi-timeframe indicator management     |
//|                       WITH FIXED ATR VALIDATION                 |
//+------------------------------------------------------------------+

#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"

// Debug configuration - using Logger instead of Print
bool DEBUG_INDICATOR_ENABLED = false;

// Simple debug function using Logger
void DebugLogIndicator(string context, string message)
{
   if (DEBUG_INDICATOR_ENABLED)
   {
      Logger::LogFast(context, message);
   }
}

void DebugLogIndicatorError(string context, string message, int error_code = 0)
{
   if (DEBUG_INDICATOR_ENABLED)
   {
      if (error_code != 0)
      {
         Logger::LogError(context, message, error_code);
      }
      else
      {
         Logger::LogError(context, message);
      }
   }
}

class IndicatorManager
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframes[7];
   int m_timeframe_count;
   static IndicatorManager *m_instance; // Singleton instance

   // Indicator handles organized by timeframe index
   struct IndicatorHandles
   {
      int ma_fast;   // Fast MA (e.g., 9 period)
      int ma_medium; // Medium MA (e.g., 21 period)
      int ma_slow;   // Slow MA (e.g., 89 period)
      int rsi;       // RSI
      int macd;      // MACD
      int adx;       // ADX
      int stoch;     // Stochastic
      int atr;       // ATR
      int volume;    // Volumes
      int bbands;    // Bollinger Bands
   };

   IndicatorHandles m_handles[];
   bool m_initialized;

   // ========== SIMPLE MA CACHE (FIXED FOR MQL4) ==========
   int m_ma_cache_periods[7][20]; // [timeframe_index][cache_index] -> period
   int m_ma_cache_handles[7][20]; // [timeframe_index][cache_index] -> handle
   int m_ma_cache_sizes[7];       // Current size of cache for each timeframe
   const int MAX_MA_CACHE_SIZE;   // Maximum MA periods to cache per timeframe

   // ========== ADD PRIVATE INITIALIZATION METHOD ==========
   bool PrivateInitialize(string symbol = NULL)
   {
      if (symbol != NULL && symbol != "")
      {
         m_symbol = symbol;
         DebugLogIndicator("IndicatorManager", "Symbol updated to: " + m_symbol);
      }

      // Now initialize with the current symbol
      return Initialize();
   }

public:
   // ========== ADD PRIVATE CONSTRUCTOR ==========
   IndicatorManager() : MAX_MA_CACHE_SIZE(20)
   {
      // Set default symbol to current chart symbol
      m_symbol = Symbol();
      m_initialized = false;

      // Timeframes your EA actually uses
      m_timeframes[0] = PERIOD_M1;
      m_timeframes[1] = PERIOD_M5;
      m_timeframes[2] = PERIOD_M15;
      m_timeframes[3] = PERIOD_M30;
      m_timeframes[4] = PERIOD_H1;
      m_timeframes[5] = PERIOD_H4;
      m_timeframes[6] = PERIOD_D1;
      m_timeframe_count = 7;

      ArrayResize(m_handles, m_timeframe_count);

      // Initialize MA cache arrays (fixed size in MQL4)
      for (int i = 0; i < m_timeframe_count; i++)
      {
         m_ma_cache_sizes[i] = 0; // Start with empty cache

         // Initialize cache arrays
         for (int j = 0; j < MAX_MA_CACHE_SIZE; j++)
         {
            m_ma_cache_periods[i][j] = 0;
            m_ma_cache_handles[i][j] = INVALID_HANDLE;
         }
      }

      ResetHandles();

      DebugLogIndicator("IndicatorManager", "Singleton instance created for symbol: " + m_symbol);
   }

   // ========== SINGLETON ACCESSOR - UPDATED ==========
   static IndicatorManager *Instance(string symbol = NULL)
   {
      if (m_instance == NULL)
      {
         DebugLogIndicator("IndicatorManager", "Creating new singleton instance");
         m_instance = new IndicatorManager();

         // If symbol is specified, update it
         if (symbol != NULL && symbol != "")
         {
            DebugLogIndicator("IndicatorManager", "Reinitializing with symbol: " + symbol);
            delete m_instance; // Delete old instance
            m_instance = new IndicatorManager();
            DebugLogIndicatorError("IndicatorManager", "WARNING: IndicatorManager singleton already created. New symbol will be ignored.");
         }
      }
      else if (symbol != NULL && symbol != "" && m_instance.m_symbol != symbol)
      {
         // Warning if trying to change symbol on existing instance
         DebugLogIndicatorError("IndicatorManager", "WARNING: IndicatorManager singleton already exists for symbol " +
               m_instance.m_symbol + ". Cannot change to " + symbol);
      }

      // Ensure it's initialized
      if (!m_instance.m_initialized)
      {
         if (!m_instance.Initialize())
         {
            DebugLogIndicatorError("IndicatorManager", "ERROR: Failed to initialize IndicatorManager singleton");
            return NULL;
         }
      }

      return m_instance;
   }

   // ========== STATIC METHOD TO GET OR CREATE INSTANCE ==========
   static IndicatorManager *GetInstance()
   {
      return Instance(NULL);
   }

   // ========== STATIC METHOD TO DESTROY INSTANCE ==========
   static void DestroyInstance()
   {
      if (m_instance != NULL)
      {
         delete m_instance;
         m_instance = NULL;
         DebugLogIndicator("IndicatorManager", "Singleton instance destroyed");
      }
   }

   // ========== DELETE COPY CONSTRUCTOR AND ASSIGNMENT ==========
   IndicatorManager(const IndicatorManager &) = delete;
   void operator=(const IndicatorManager &) = delete;

   ~IndicatorManager()
   {
      Deinitialize();
   }

   // INITIALIZE() - Creates actual resources, Sets up internal state
   bool Initialize()
   {
      if (m_initialized)
      {
         DebugLogIndicator("IndicatorManager", "Already initialized");
         return true;
      }

      DebugLogIndicator("IndicatorManager", "=== STARTING INITIALIZATION ===");

      // Validate symbol exists BEFORE creating indicators
      if (!SymbolInfoInteger(m_symbol, SYMBOL_SELECT))
      {
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("Symbol %s not available for trading", m_symbol));
         return false;
      }

      DebugLogIndicator("IndicatorManager",
                        StringFormat("Initializing IndicatorManager for %s", m_symbol));

      // ============================================================
      // CRITICAL: FORCE DOWNLOAD OF HISTORICAL DATA FIRST
      // ============================================================
      DebugLogIndicator("IndicatorManager", "=== FORCING HISTORICAL DATA DOWNLOAD ===");

      bool allTimeframesHaveData = true;

      for (int tfIndex = 0; tfIndex < m_timeframe_count; tfIndex++)
      {
         ENUM_TIMEFRAMES currentTF = m_timeframes[tfIndex];
         string tfName = GetTimeframeName(currentTF);

         DebugLogIndicator("IndicatorManager",
                           StringFormat("Loading data for %s (TF: %d)...", tfName, currentTF));

         // Determine minimum bars needed based on timeframe
         int minBarsRequired = GetMinimumBarsForTF(currentTF);
         int loadedBars = 0;
         int maxAttempts = 10; // 10 second timeout per timeframe

         for (int attempt = 1; attempt <= maxAttempts; attempt++)
         {
            // Check current bars available
            loadedBars = iBars(m_symbol, currentTF);

            DebugLogIndicator("IndicatorManager",
                              StringFormat("Attempt %d/%d: %d bars loaded for %s (need %d)",
                                           attempt, maxAttempts, loadedBars, tfName, minBarsRequired));

            // If we have enough bars, break
            if (loadedBars >= minBarsRequired)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("✅ %s: Sufficient data (%d bars)",
                                              tfName, loadedBars));
               break;
            }

            // If we don't have enough bars, force data download
            if (attempt < maxAttempts)
            {
               // Method 1: Request bars using CopyRates (forces download)
               MqlRates rates[];
               int ratesRequested = MathMax(minBarsRequired, 200);
               int ratesCopied = CopyRates(m_symbol, currentTF, 0, ratesRequested, rates);

               DebugLogIndicator("IndicatorManager",
                                 StringFormat("CopyRates requested %d, got %d",
                                              ratesRequested, ratesCopied));

               // Method 2: Try to get recent bars specifically
               if (ratesCopied <= 0)
               {
                  // Try getting fewer bars
                  ratesCopied = CopyRates(m_symbol, currentTF, 0, 50, rates);
               }

               // Wait before next attempt
               Sleep(1000); // Wait 1 second

               // Update loaded bars count
               loadedBars = iBars(m_symbol, currentTF);
            }
         }

         // Check if we got enough data
         if (loadedBars < minBarsRequired)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("❌ %s: Only %d bars (need %d) - indicators may fail",
                                           tfName, loadedBars, minBarsRequired));
            allTimeframesHaveData = false;

            if (loadedBars < 50)
            {
               DebugLogIndicatorError("IndicatorManager",
                                      StringFormat("CRITICAL: %s has VERY LOW data (%d bars)",
                                                   tfName, loadedBars));
            }
         }
      }

      if (!allTimeframesHaveData)
      {
         DebugLogIndicatorError("IndicatorManager",
                                "WARNING: Not all timeframes have sufficient data!");
         DebugLogIndicator("IndicatorManager",
                           "Trying to create indicators anyway...");
      }
      else
      {
         DebugLogIndicator("IndicatorManager",
                           "✅ All timeframes have sufficient data");
      }

      // ============================================================
      // CREATE INDICATORS (now that data should be loaded)
      // ============================================================
      DebugLogIndicator("IndicatorManager", "=== CREATING INDICATORS ===");

      for (int i = 0; i < m_timeframe_count; i++)
      {
         ENUM_TIMEFRAMES currentTF = m_timeframes[i];
         string tfName = GetTimeframeName(currentTF);

         // Validate timeframe is valid
         if (!IsTimeframeAvailable(currentTF))
         {
            DebugLogIndicatorError("IndicatorManager",
                                   StringFormat("Timeframe %s not available for %s",
                                                tfName, m_symbol));
            continue;
         }

         // Check if we have ANY data for this timeframe
         int availableBars = iBars(m_symbol, currentTF);
         if (availableBars < 10)
         {
            DebugLogIndicatorError("IndicatorManager",
                                   StringFormat("Skipping %s: Only %d bars available",
                                                tfName, availableBars));
            continue;
         }

         DebugLogIndicator("IndicatorManager",
                           StringFormat("Creating indicators for %s (%d bars available)",
                                        tfName, availableBars));

         // Create indicators with the actual timeframe
         m_handles[i].ma_fast = iMA(m_symbol, currentTF, 9, 0, MODE_EMA, PRICE_CLOSE);
         m_handles[i].ma_medium = iMA(m_symbol, currentTF, 21, 0, MODE_SMA, PRICE_CLOSE);
         m_handles[i].ma_slow = iMA(m_symbol, currentTF, 89, 0, MODE_SMA, PRICE_CLOSE);
         m_handles[i].rsi = iRSI(m_symbol, currentTF, 14, PRICE_CLOSE);
         m_handles[i].macd = iMACD(m_symbol, currentTF, 12, 26, 9, PRICE_CLOSE);
         m_handles[i].adx = iADX(m_symbol, currentTF, 14);
         m_handles[i].stoch = iStochastic(m_symbol, currentTF, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
         m_handles[i].atr = iATR(m_symbol, currentTF, 14);
         m_handles[i].volume = iVolumes(m_symbol, currentTF, VOLUME_TICK);
         m_handles[i].bbands = iBands(m_symbol, currentTF, 20, 0, 2.0, PRICE_CLOSE);

         // Log what we created
         DebugLogIndicator("IndicatorManager",
                           StringFormat("Created indicators for TF: %s (index: %d)",
                                        tfName, i));

         // Validate handles immediately
         bool allHandlesValid = true;

         if (!ValidateHandle(m_handles[i].ma_fast))
         {
            DebugLogIndicatorError("IndicatorManager", "MA Fast handle invalid");
            allHandlesValid = false;
         }
         if (!ValidateHandle(m_handles[i].atr))
         {
            DebugLogIndicatorError("IndicatorManager",
                                   StringFormat("Failed to create ATR for %s", tfName));
            allHandlesValid = false;
         }

         if (!allHandlesValid)
         {
            DebugLogIndicatorError("IndicatorManager",
                                   StringFormat("Some indicators failed for %s", tfName));
         }
      }

      // ============================================================
      // WAIT FOR INDICATORS TO CALCULATE (CRITICAL FOR REAL ACCOUNTS)
      // ============================================================
      DebugLogIndicator("IndicatorManager", "=== WAITING FOR INDICATOR CALCULATION ===");

      int waitAttempts = 0;
      const int maxWaitAttempts = 20; // 4 second timeout
      bool indicatorsReady = false;

      while (waitAttempts < maxWaitAttempts && !indicatorsReady)
      {
         indicatorsReady = true;

         // Test if any indicator is ready by trying to get values
         for (int i = 0; i < m_timeframe_count; i++)
         {
            if (m_handles[i].ma_fast != INVALID_HANDLE)
            {
               double testValue[1];
               int copied = CopyBuffer(m_handles[i].ma_fast, 0, 0, 1, testValue);

               if (copied <= 0 || testValue[0] == EMPTY_VALUE || testValue[0] == 0)
               {
                  indicatorsReady = false;
                  break;
               }
            }
         }

         if (!indicatorsReady)
         {
            waitAttempts++;
            Sleep(200); // Wait 200ms between checks

            if (waitAttempts % 5 == 0) // Log every 5 attempts
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Waiting for indicators... (%d/%d)",
                                              waitAttempts, maxWaitAttempts));
            }
         }
      }

      if (indicatorsReady)
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("✅ Indicators ready after %d ms", waitAttempts * 200));
      }
      else
      {
         DebugLogIndicatorError("IndicatorManager",
                                "⚠️ Indicators not fully ready (will retry on first use)");
      }

      m_initialized = true;
      DebugLogIndicator("IndicatorManager", "=== INITIALIZATION COMPLETE ===");
      DebugLogIndicator("IndicatorManager", "Initialized successfully with historical data support");

      // Test one indicator to verify
      TestIndicatorReadiness();

      return true;
   }

   // DEINITIALIZE() - Closes/frees resources, Resets m_initialized flag
   void Deinitialize()
   {
      if (!m_initialized)
         return;

      // Release main indicator handles
      for (int i = 0; i < m_timeframe_count; i++)
      {
         if (ValidateHandle(m_handles[i].ma_fast))
            IndicatorRelease(m_handles[i].ma_fast);
         if (ValidateHandle(m_handles[i].ma_medium))
            IndicatorRelease(m_handles[i].ma_medium);
         if (ValidateHandle(m_handles[i].ma_slow))
            IndicatorRelease(m_handles[i].ma_slow);
         if (ValidateHandle(m_handles[i].rsi))
            IndicatorRelease(m_handles[i].rsi);
         if (ValidateHandle(m_handles[i].macd))
            IndicatorRelease(m_handles[i].macd);
         if (ValidateHandle(m_handles[i].adx))
            IndicatorRelease(m_handles[i].adx);
         if (ValidateHandle(m_handles[i].stoch))
            IndicatorRelease(m_handles[i].stoch);
         if (ValidateHandle(m_handles[i].atr))
            IndicatorRelease(m_handles[i].atr);
         if (ValidateHandle(m_handles[i].volume))
            IndicatorRelease(m_handles[i].volume);
         if (ValidateHandle(m_handles[i].bbands))
            IndicatorRelease(m_handles[i].bbands);
      }

      // Release MA cache handles
      for (int i = 0; i < m_timeframe_count; i++)
      {
         for (int j = 0; j < m_ma_cache_sizes[i]; j++)
         {
            if (m_ma_cache_handles[i][j] != INVALID_HANDLE)
            {
               IndicatorRelease(m_ma_cache_handles[i][j]);
               m_ma_cache_handles[i][j] = INVALID_HANDLE;
            }
            m_ma_cache_periods[i][j] = 0;
         }
         m_ma_cache_sizes[i] = 0;
      }

      ResetHandles();
      m_initialized = false;
      DebugLogIndicator("IndicatorManager", "Deinitialized");
   }

   // EVENT HANDLERS - only process if initialized
   void OnTick()
   {
      if (!m_initialized)
         return;

      // Optional: Update indicator values or perform tick-based calculations
   }

   void OnTimer()
   {
      if (!m_initialized)
         return;

      // Optional: Periodic updates or monitoring
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
   {
      if (!m_initialized)
         return;

      // Optional: Handle trade-related events
   }

   // Get Moving Average values
   bool GetMAValues(ENUM_TIMEFRAMES tf, double &ma_fast, double &ma_medium, double &ma_slow, int shift = 0)
   {
      if (!m_initialized)
      {
         ma_fast = ma_slow = ma_medium = EMPTY_VALUE;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         ma_fast = ma_slow = ma_medium = EMPTY_VALUE;
         return false;
      }

      // Get values with retry
      ma_fast = GetIndicatorValue(m_handles[idx].ma_fast, 0, shift);
      ma_slow = GetIndicatorValue(m_handles[idx].ma_slow, 0, shift);
      ma_medium = GetIndicatorValue(m_handles[idx].ma_medium, 0, shift);

      // Check if any are EMPTY_VALUE
      bool allValid = (ma_fast != EMPTY_VALUE && ma_slow != EMPTY_VALUE && ma_medium != EMPTY_VALUE);

      if (!allValid)
      {
         // Try alternative shift if current shift failed
         if (ma_fast == EMPTY_VALUE || ma_slow == EMPTY_VALUE || ma_medium == EMPTY_VALUE)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("MA values invalid at shift %d, trying shift 1...", shift));

            ma_fast = GetIndicatorValue(m_handles[idx].ma_fast, 0, shift + 1);
            ma_slow = GetIndicatorValue(m_handles[idx].ma_slow, 0, shift + 1);
            ma_medium = GetIndicatorValue(m_handles[idx].ma_medium, 0, shift + 1);

            allValid = (ma_fast != EMPTY_VALUE && ma_slow != EMPTY_VALUE && ma_medium != EMPTY_VALUE);
         }
      }

      if (!allValid)
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("Some MA values invalid after retry: fast=%s, slow=%s, medium=%s",
                                        (ma_fast == EMPTY_VALUE) ? "EMPTY" : DoubleToString(ma_fast, 5),
                                        (ma_slow == EMPTY_VALUE) ? "EMPTY" : DoubleToString(ma_slow, 5),
                                        (ma_medium == EMPTY_VALUE) ? "EMPTY" : DoubleToString(ma_medium, 5)));
      }
      else
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("✅ MA values valid: fast=%.5f, medium=%.5f, slow=%.5f",
                                        ma_fast, ma_medium, ma_slow));
      }

      return allValid;
   }

   // Get Moving Average values for RangeScanner (with 4 MAs: 9, 21, 50, 89)
   bool GetMAValuesForRange(ENUM_TIMEFRAMES tf, double &ma9, double &ma21, double &ma50, double &ma89, int shift = 0)
   {
      // ADD THIS DEBUG AT THE TOP
      DebugLogIndicator("GetMAValuesForRange", "=== DEBUG GetMAValuesForRange ===");
      DebugLogIndicator("GetMAValuesForRange", "Timeframe: " + IntegerToString(tf) + " (" + EnumToString(tf) + ")");
      DebugLogIndicator("GetMAValuesForRange", "Symbol: " + m_symbol);
      DebugLogIndicator("GetMAValuesForRange", "Initialized: " + string(m_initialized));

      if (!m_initialized)
      {
         DebugLogIndicator("GetMAValuesForRange", "❌ NOT INITIALIZED!");
         ma9 = ma21 = ma50 = ma89 = 0.0;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      DebugLogIndicator("GetMAValuesForRange", "Timeframe index: " + IntegerToString(idx));

      if (idx == -1)
      {
         DebugLogIndicator("GetMAValuesForRange", "❌ TIMEFRAME NOT FOUND!");
         ma9 = ma21 = ma50 = ma89 = 0.0;
         return false;
      }

      // Get existing MAs
      ma9 = GetIndicatorValue(m_handles[idx].ma_fast, 0, shift);
      ma21 = GetIndicatorValue(m_handles[idx].ma_medium, 0, shift);
      ma89 = GetIndicatorValue(m_handles[idx].ma_slow, 0, shift);

      DebugLogIndicator("GetMAValuesForRange", "MA9: " + DoubleToString(ma9, 5) + " | MA21: " + DoubleToString(ma21, 5) + " | MA89: " + DoubleToString(ma89, 5));

      // For MA50 - CRITICAL DEBUG
      DebugLogIndicator("GetMAValuesForRange", "--- CREATING MA50 ---");
      int ma50_handle = GetOrCreateMAHandle(tf, 50);
      DebugLogIndicator("GetMAValuesForRange", "MA50 handle: " + IntegerToString(ma50_handle));

      if (ma50_handle == INVALID_HANDLE)
      {
         DebugLogIndicator("GetMAValuesForRange", "❌ MA50 HANDLE IS INVALID_HANDLE!");

         // Try direct creation to see error
         DebugLogIndicator("GetMAValuesForRange", "--- Testing direct iMA creation ---");
         int test_handle = iMA(m_symbol, tf, 50, 0, MODE_SMA, PRICE_CLOSE);
         DebugLogIndicator("GetMAValuesForRange", "Direct iMA handle: " + IntegerToString(test_handle));

         if (test_handle == INVALID_HANDLE)
         {
            int error = GetLastError();
            DebugLogIndicatorError("GetMAValuesForRange", "Direct iMA error: " + IntegerToString(error) + " - " + GetErrorDescription(error));
         }
         else
         {
            // Test if we can get a value
            double test_value[1];
            int copied = CopyBuffer(test_handle, 0, 0, 1, test_value);
            DebugLogIndicator("GetMAValuesForRange", "Direct CopyBuffer result: copied=" + IntegerToString(copied) + ", value=" + DoubleToString(test_value[0], 5));
            IndicatorRelease(test_handle);
         }

         ma9 = ma21 = ma50 = ma89 = 0.0;
         DebugLogIndicator("GetMAValuesForRange", "=== END DEBUG GetMAValuesForRange (FAILED) ===");
         return false;
      }

      ma50 = GetIndicatorValue(ma50_handle, 0, shift);
      DebugLogIndicator("GetMAValuesForRange", "MA50 value: " + DoubleToString(ma50, 5));

      // Check bars available
      int bars = iBars(m_symbol, tf);
      DebugLogIndicator("GetMAValuesForRange", "Bars available for TF " + IntegerToString(tf) + ": " + IntegerToString(bars));

      bool allValid = (ma9 != 0.0 && ma21 != 0.0 && ma50 != 0.0 && ma89 != 0.0);
      DebugLogIndicator("GetMAValuesForRange", "All MA values valid? " + string(allValid));
      DebugLogIndicator("GetMAValuesForRange", "=== END DEBUG GetMAValuesForRange ===");

      return allValid;
   }

   // Helper function to get or create MA handle for specific period
   int GetOrCreateMAHandle(ENUM_TIMEFRAMES tf, int period)
   {
      DebugLogIndicator("GetOrCreateMAHandle", "=== DEBUG GetOrCreateMAHandle ===");
      DebugLogIndicator("GetOrCreateMAHandle", "Requested: MA" + IntegerToString(period) + " for TF " + IntegerToString(tf));

      int idx = GetTimeframeIndex(tf);
      DebugLogIndicator("GetOrCreateMAHandle", "Timeframe index: " + IntegerToString(idx));

      if (idx == -1)
      {
         DebugLogIndicator("GetOrCreateMAHandle", "❌ Timeframe index not found!");
         DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (FAILED) ===");
         return INVALID_HANDLE;
      }

      // Check cache
      for (int i = 0; i < m_ma_cache_sizes[idx]; i++)
      {
         if (m_ma_cache_periods[idx][i] == period)
         {
            DebugLogIndicator("GetOrCreateMAHandle", "✅ Found in cache at index " + IntegerToString(i));
            DebugLogIndicator("GetOrCreateMAHandle", "Cached handle: " + IntegerToString(m_ma_cache_handles[idx][i]));
            DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (FROM CACHE) ===");
            return m_ma_cache_handles[idx][i];
         }
      }

      DebugLogIndicator("GetOrCreateMAHandle", "Not in cache, creating new...");

      // Check if we have enough bars
      int bars_needed = period + 20; // MA needs period + buffer
      int bars_available = iBars(m_symbol, tf);
      DebugLogIndicator("GetOrCreateMAHandle", "Bars needed: " + IntegerToString(bars_needed) + " | Bars available: " + IntegerToString(bars_available));

      if (bars_available < bars_needed)
      {
         DebugLogIndicator("GetOrCreateMAHandle", "❌ INSUFFICIENT BARS! Need at least " + IntegerToString(bars_needed));

         // Try to force load data
         DebugLogIndicator("GetOrCreateMAHandle", "Attempting to load more data...");
         MqlRates rates[];
         int to_copy = MathMax(bars_needed, 200);
         int copied = CopyRates(m_symbol, tf, 0, to_copy, rates);
         DebugLogIndicator("GetOrCreateMAHandle", "Copied " + IntegerToString(copied) + " rates");

         bars_available = iBars(m_symbol, tf);
         DebugLogIndicator("GetOrCreateMAHandle", "New bars available: " + IntegerToString(bars_available));

         if (bars_available < period)
         {
            DebugLogIndicator("GetOrCreateMAHandle", "❌ Still insufficient after copy");
            DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (INSUFFICIENT DATA) ===");
            return INVALID_HANDLE;
         }
      }

      // Now create the handle
      DebugLogIndicator("GetOrCreateMAHandle", "Creating iMA handle...");
      int handle = iMA(m_symbol, tf, period, 0, MODE_SMA, PRICE_CLOSE);
      DebugLogIndicator("GetOrCreateMAHandle", "Handle created: " + IntegerToString(handle));

      if (handle == INVALID_HANDLE)
      {
         int error = GetLastError();
         DebugLogIndicatorError("GetOrCreateMAHandle", "❌ iMA failed! Error: " + IntegerToString(error) + " - " + GetErrorDescription(error));
         DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (iMA FAILED) ===");
         return INVALID_HANDLE;
      }

      // Test if handle works
      double test_value[1];
      int test_copied = CopyBuffer(handle, 0, 0, 1, test_value);
      DebugLogIndicator("GetOrCreateMAHandle", "Test CopyBuffer: copied=" + IntegerToString(test_copied) + ", value=" + DoubleToString(test_value[0], 5));

      if (test_copied <= 0 || test_value[0] == 0 || test_value[0] == EMPTY_VALUE)
      {
         DebugLogIndicator("GetOrCreateMAHandle", "❌ Handle created but returns invalid value!");
         IndicatorRelease(handle);
         DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (INVALID VALUES) ===");
         return INVALID_HANDLE;
      }

      DebugLogIndicator("GetOrCreateMAHandle", "✅ Handle works! Value: " + DoubleToString(test_value[0], 5));

      // Cache it if we have space
      if (m_ma_cache_sizes[idx] < MAX_MA_CACHE_SIZE)
      {
         int cacheIndex = m_ma_cache_sizes[idx];
         m_ma_cache_periods[idx][cacheIndex] = period;
         m_ma_cache_handles[idx][cacheIndex] = handle;
         m_ma_cache_sizes[idx]++;
         DebugLogIndicator("GetOrCreateMAHandle", "Cached at index " + IntegerToString(cacheIndex));
      }

      DebugLogIndicator("GetOrCreateMAHandle", "=== END DEBUG GetOrCreateMAHandle (SUCCESS) ===");
      return handle;
   }

   // Get RSI value
   double GetRSI(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      if (!m_initialized)
      {
         DebugLogIndicator("GetRSI", "Not initialized");
         return 50.0;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         DebugLogIndicatorError("GetRSI",
                                StringFormat("Timeframe %d not found", tf));
         return 50.0;
      }

      // Recreate RSI handle if invalid
      if (m_handles[idx].rsi == INVALID_HANDLE || !ValidateHandle(m_handles[idx].rsi))
      {
         DebugLogIndicator("GetRSI",
                           StringFormat("RSI handle invalid for TF %d, recreating...", tf));

         if (m_handles[idx].rsi != INVALID_HANDLE)
         {
            IndicatorRelease(m_handles[idx].rsi);
         }

         m_handles[idx].rsi = iRSI(m_symbol, tf, 14, PRICE_CLOSE);

         if (m_handles[idx].rsi == INVALID_HANDLE)
         {
            DebugLogIndicatorError("GetRSI",
                                   StringFormat("Failed to recreate RSI for TF %d", tf));
            return 50.0;
         }

         // Give it time to initialize
         Sleep(10);
      }

      double rsiValue = GetIndicatorValue(m_handles[idx].rsi, 0, shift);

      // Better validation
      if (rsiValue == EMPTY_VALUE || !MathIsValidNumber(rsiValue))
      {
         DebugLogIndicator("GetRSI",
                           StringFormat("RSI returned EMPTY_VALUE for TF %d, shift %d", tf, shift));
         return 50.0;
      }

      // Extreme value validation
      if (rsiValue < 0 || rsiValue > 100)
      {
         DebugLogIndicator("GetRSI",
                           StringFormat("RSI out of range: %.2f for TF %d, using 50.0", rsiValue, tf));
         return 50.0;
      }

      DebugLogIndicator("GetRSI",
                        StringFormat("✅ RSI value: %.2f for TF %d, shift %d", rsiValue, tf, shift));

      return rsiValue;
   }

   // Get MACD values
   bool GetMACDValues(ENUM_TIMEFRAMES tf, double &macd_main, double &macd_signal, int shift = 0)
   {
      if (!m_initialized)
      {
         macd_main = macd_signal = 0.0;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         macd_main = macd_signal = 0.0;
         return false;
      }

      macd_main = GetIndicatorValue(m_handles[idx].macd, MAIN_LINE, shift);
      macd_signal = GetIndicatorValue(m_handles[idx].macd, SIGNAL_LINE, shift);

      bool bothValid = (macd_main != 0.0 && macd_signal != 0.0);

      if (!bothValid)
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
      if (!m_initialized)
      {
         adx = plus_di = minus_di = 0.0;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         adx = plus_di = minus_di = 0.0;
         return false;
      }

      adx = GetIndicatorValue(m_handles[idx].adx, 0, shift);      // ADX line
      plus_di = GetIndicatorValue(m_handles[idx].adx, 1, shift);  // +DI line
      minus_di = GetIndicatorValue(m_handles[idx].adx, 2, shift); // -DI line

      bool allValid = (adx != 0.0 && plus_di != 0.0 && minus_di != 0.0);

      if (!allValid)
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
      if (!m_initialized)
      {
         stoch_main = stoch_signal = 0.0;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         stoch_main = stoch_signal = 0.0;
         return false;
      }

      stoch_main = GetIndicatorValue(m_handles[idx].stoch, 0, shift);   // %K line
      stoch_signal = GetIndicatorValue(m_handles[idx].stoch, 1, shift); // %D line

      bool bothValid = (stoch_main != 0.0 && stoch_signal != 0.0);

      if (!bothValid)
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
      if (!m_initialized)
      {
         DebugLogIndicatorError("IndicatorManager", "Not initialized in GetATR");
         return GetDefaultATR();
      }

      int idx = GetTimeframeIndex(tf);

      // DEBUG: Log what we're looking for
      DebugLogIndicator("IndicatorManager",
                        StringFormat("GetATR called: tf=%d, GetTimeframeIndex returned: %d", tf, idx));

      if (idx == -1)
      {
         // Provide better error message
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("Timeframe %d not found in GetATR. Available TFs: M1=%d, M5=%d, M15=%d, H1=%d, H4=%d, D1=%d",
                                             tf, PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1));

         // Try to use H1 as fallback
         idx = GetTimeframeIndex(PERIOD_H1);
         if (idx == -1)
         {
            return GetDefaultATR();
         }
      }

      // Check if we have a valid handle at this index
      if (idx < 0 || idx >= m_timeframe_count)
      {
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("Invalid index %d for timeframe %d (array size: %d)",
                                             idx, tf, m_timeframe_count));
         return GetDefaultATR();
      }

      if (m_handles[idx].atr == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("ATR handle invalid at index %d for timeframe %d", idx, tf));

         // Try to create the handle on the fly
         DebugLogIndicator("IndicatorManager", "Creating ATR handle on the fly...");
         m_handles[idx].atr = iATR(m_symbol, tf, 14);

         if (m_handles[idx].atr == INVALID_HANDLE)
         {
            return GetDefaultATR();
         }
      }

      double atrValue = GetIndicatorValue(m_handles[idx].atr, 0, shift);

      // Validate ATR value
      if (atrValue <= 0 || !MathIsValidNumber(atrValue))
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("Invalid ATR value: %.5f on TF %d (idx: %d)", atrValue, tf, idx));
         return GetDefaultATR();
      }

      // ========== ADD M1 VALIDATION ==========
      if (tf == PERIOD_M15)
      {
         // M1 ATR is very small - add special validation
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

         if (StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         {
            // Gold M1 ATR should be around 0.05-0.8
            double minGoldATR = 0.05; // $0.05 minimum (5 cents)
            double maxGoldATR = 0.8;  // $0.80 maximum (80 cents)

            if (atrValue < minGoldATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Gold M1 ATR too small: %.5f, using %.2f",
                                              atrValue, minGoldATR));
               atrValue = minGoldATR;
            }
            else if (atrValue > maxGoldATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Gold M1 ATR too large: %.5f, using %.2f",
                                              atrValue, maxGoldATR));
               atrValue = maxGoldATR;
            }
         }
         else if (StringFind(m_symbol, "XAG") >= 0 || StringFind(m_symbol, "SILVER") >= 0)
         {
            // Silver M1 ATR should be around 0.01-0.15
            double minSilverATR = 0.01; // $0.01 minimum
            double maxSilverATR = 0.15; // $0.15 maximum

            if (atrValue < minSilverATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Silver M1 ATR too small: %.5f, using %.2f",
                                              atrValue, minSilverATR));
               atrValue = minSilverATR;
            }
            else if (atrValue > maxSilverATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Silver M1 ATR too large: %.5f, using %.2f",
                                              atrValue, maxSilverATR));
               atrValue = maxSilverATR;
            }
         }
         else if (StringFind(m_symbol, "BTC") >= 0 || StringFind(m_symbol, "ETH") >= 0)
         {
            // Crypto M1 ATR should be around 5-50
            double minCryptoATR = 5.0;  // $5 minimum
            double maxCryptoATR = 50.0; // $50 maximum

            if (atrValue < minCryptoATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Crypto M1 ATR too small: %.5f, using %.1f",
                                              atrValue, minCryptoATR));
               atrValue = minCryptoATR;
            }
            else if (atrValue > maxCryptoATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Crypto M1 ATR too large: %.5f, using %.1f",
                                              atrValue, maxCryptoATR));
               atrValue = maxCryptoATR;
            }
         }
         else
         {
            // Forex M1 ATR should be around 0.00003-0.0003 (0.3-3 pips)
            double minForexATR = 0.00003; // 0.3 pips minimum
            double maxForexATR = 0.0003;  // 3 pips maximum

            if (atrValue < minForexATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Forex M1 ATR too small: %.6f, using %.6f",
                                              atrValue, minForexATR));
               atrValue = minForexATR;
            }
            else if (atrValue > maxForexATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Forex M1 ATR too large: %.6f, using %.6f",
                                              atrValue, maxForexATR));
               atrValue = maxForexATR;
            }
         }
      }
      // ========== END M1 VALIDATION ==========

      // ========== ADD M30 VALIDATION ==========
      if (tf == PERIOD_M30)
      {
         if (StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         {
            // Gold M30 ATR should be around 1.0-4.0
            double minGoldATR = 1.0; // $1.00 minimum
            double maxGoldATR = 4.0; // $4.00 maximum

            if (atrValue < minGoldATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Gold M30 ATR too small: %.5f, using %.1f",
                                              atrValue, minGoldATR));
               atrValue = minGoldATR;
            }
            else if (atrValue > maxGoldATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Gold M30 ATR too large: %.5f, using %.1f",
                                              atrValue, maxGoldATR));
               atrValue = maxGoldATR;
            }
         }
         else
         {
            // Forex M30 ATR should be around 0.0005-0.0015 (5-15 pips)
            double minForexATR = 0.0005; // 5 pips minimum
            double maxForexATR = 0.0015; // 15 pips maximum

            if (atrValue < minForexATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Forex M30 ATR too small: %.6f, using %.6f",
                                              atrValue, minForexATR));
               atrValue = minForexATR;
            }
            else if (atrValue > maxForexATR)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("Forex M30 ATR too large: %.6f, using %.6f",
                                              atrValue, maxForexATR));
               atrValue = maxForexATR;
            }
         }
      }
      // ========== END M30 VALIDATION ==========

      // Existing ATR validation with symbol-specific limits
      if (StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
      {
         // Gold ATR sanity checks based on timeframe
         double maxATR = 50.0;
         double minATR = 1.0;

         if (tf == PERIOD_M1)
         {
            maxATR = 0.8;  // M1: max $0.8
            minATR = 0.05; // M1: min $0.05
         }
         else if (tf == PERIOD_M5)
         {
            maxATR = 2.0; // M5: max $2
            minATR = 0.2; // M5: min $0.2
         }
         else if (tf == PERIOD_M15)
         {
            maxATR = 3.0; // M15: max $3
            minATR = 0.5; // M15: min $0.5
         }
         else if (tf == PERIOD_M30)
         {                // ← ADD M30
            maxATR = 4.0; // M30: max $4
            minATR = 1.0; // M30: min $1
         }
         else if (tf == PERIOD_H1)
         {
            maxATR = 5.0; // H1: max $5
            minATR = 1.0; // H1: min $1
         }
         else if (tf == PERIOD_H4)
         {
            maxATR = 8.0; // H4: max $8
            minATR = 2.0; // H4: min $2
         }
         else if (tf == PERIOD_D1)
         {
            maxATR = 15.0; // D1: max $15
            minATR = 5.0;  // D1: min $5
         }

         if (atrValue > maxATR)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("Gold ATR too large: %.5f > %.1f, capping to %.1f",
                                           atrValue, maxATR, maxATR));
            atrValue = maxATR;
         }
         else if (atrValue < minATR)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("Gold ATR too small: %.5f < %.1f, using %.1f",
                                           atrValue, minATR, minATR));
            atrValue = minATR;
         }
      }
      else
      {
         double maxATR = 0.01;   // 100 pips max
         double minATR = 0.0001; // 1 pip min

         // Adjust based on timeframe
         if (tf == PERIOD_M1)
         {
            maxATR = 0.0003;  // M1: 3 pips max
            minATR = 0.00003; // M1: 0.3 pips min
         }
         else if (tf == PERIOD_M5)
         {
            maxATR = 0.0008; // M5: 8 pips max
            minATR = 0.0001; // M5: 1 pip min
         }
         else if (tf == PERIOD_M15)
         {
            maxATR = 0.0015; // M15: 15 pips max
            minATR = 0.0003; // M15: 3 pips min
         }
         else if (tf == PERIOD_M30)
         {                   // ← ADD M30
            maxATR = 0.0020; // M30: 20 pips max
            minATR = 0.0005; // M30: 5 pips min
         }
         else if (tf == PERIOD_H1)
         {
            maxATR = 0.0030; // H1: 30 pips max
            minATR = 0.0010; // H1: 10 pips min
         }

         if (atrValue > maxATR)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("Forex ATR too large: %.5f > %.5f, capping to %.5f",
                                           atrValue, maxATR, maxATR));
            atrValue = maxATR;
         }
         else if (atrValue < minATR)
         {
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

      if (atrValue > 0)
      {
         return atrValue; // Valid ATR
      }

      DebugLogIndicator("IndicatorManager",
                        StringFormat("Primary ATR failed on TF %d, trying fallback...", tf));

      // Try other timeframes in order of reliability
      ENUM_TIMEFRAMES fallbackTFs[] = {PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_M15};

      for (int i = 0; i < ArraySize(fallbackTFs); i++)
      {
         if (fallbackTFs[i] == tf)
            continue; // Skip the one that failed

         int idx = GetTimeframeIndex(fallbackTFs[i]);
         if (idx != -1 && m_handles[idx].atr != INVALID_HANDLE)
         {
            double fallbackATR = GetIndicatorValue(m_handles[idx].atr, 0, shift);
            if (fallbackATR > 0)
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
      if (!m_initialized)
      {
         DebugLogIndicator("IndicatorManager", "Not initialized in GetVolume");
         return 0.0;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
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
      if (!m_initialized)
      {
         upper = middle = lower = 0.0;
         return false;
      }

      int idx = GetTimeframeIndex(tf);
      if (idx == -1)
      {
         upper = middle = lower = 0.0;
         return false;
      }

      upper = GetIndicatorValue(m_handles[idx].bbands, 0, shift);  // Upper band
      middle = GetIndicatorValue(m_handles[idx].bbands, 1, shift); // Middle band
      lower = GetIndicatorValue(m_handles[idx].bbands, 2, shift);  // Lower band

      bool allValid = (upper != 0.0 && middle != 0.0 && lower != 0.0);

      if (!allValid)
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
      if (!m_initialized)
         return false;

      double ma_fast, ma_slow, ma_medium;
      if (!GetMAValues(tf, ma_fast, ma_slow, ma_medium))
         return false;

      // Bullish if fast MA > slow MA > medium MA
      return (ma_fast > ma_slow && ma_slow > ma_medium);
   }

   bool IsTrendBearish(ENUM_TIMEFRAMES tf)
   {
      if (!m_initialized)
         return false;

      double ma_fast, ma_slow, ma_medium;
      if (!GetMAValues(tf, ma_fast, ma_slow, ma_medium))
         return false;

      // Bearish if fast MA < slow MA < medium MA
      return (ma_fast < ma_slow && ma_slow < ma_medium);
   }

   // Check if market is overbought on RSI and Stochastic
   bool IsOverbought(ENUM_TIMEFRAMES tf)
   {
      if (!m_initialized)
         return false;

      double rsi = GetRSI(tf);
      double stoch_main, stoch_signal;
      if (!GetStochasticValues(tf, stoch_main, stoch_signal))
         return false;

      return (rsi > 70 && stoch_main > 80);
   }

   // Check if market is oversold on RSI and Stochastic
   bool IsOversold(ENUM_TIMEFRAMES tf)
   {
      if (!m_initialized)
         return false;

      double rsi = GetRSI(tf);
      double stoch_main, stoch_signal;
      if (!GetStochasticValues(tf, stoch_main, stoch_signal))
         return false;

      return (rsi < 30 && stoch_main < 20);
   }

   // Check trend strength using ADX
   bool IsStrongTrend(ENUM_TIMEFRAMES tf, int threshold = 25)
   {
      if (!m_initialized)
         return false;

      double adx, plus_di, minus_di;
      if (!GetADXValues(tf, adx, plus_di, minus_di))
         return false;

      return (adx > threshold);
   }

   // Get trend direction using ADX (+DI vs -DI)
   int GetADXTrendDirection(ENUM_TIMEFRAMES tf)
   {
      if (!m_initialized)
         return 0;

      double adx, plus_di, minus_di;
      if (!GetADXValues(tf, adx, plus_di, minus_di))
         return 0;

      if (plus_di > minus_di)
         return 1; // Bullish
      if (plus_di < minus_di)
         return -1; // Bearish
      return 0;     // Neutral
   }

   // Check for MACD crossover
   int GetMACDCrossover(ENUM_TIMEFRAMES tf)
   {
      if (!m_initialized)
         return 0;

      double macd_main_current, macd_signal_current;
      double macd_main_prev, macd_signal_prev;

      if (!GetMACDValues(tf, macd_main_current, macd_signal_current, 0))
         return 0;
      if (!GetMACDValues(tf, macd_main_prev, macd_signal_prev, 1))
         return 0;

      // Bullish crossover: MACD crosses above signal
      if (macd_main_prev <= macd_signal_prev && macd_main_current > macd_signal_current)
         return 1;

      // Bearish crossover: MACD crosses below signal
      if (macd_main_prev >= macd_signal_prev && macd_main_current < macd_signal_current)
         return -1;

      return 0;
   }

   // Multi-timeframe confirmation with chart score display
   bool GetMultiTimeframeConfirmation(int &bullish_tf_count, int &bearish_tf_count)
   {
      if (!m_initialized)
         return false;

      bullish_tf_count = 0;
      bearish_tf_count = 0;

      for (int i = 0; i < m_timeframe_count; i++)
      {
         if (IsTrendBullish(m_timeframes[i]))
            bullish_tf_count++;
         else if (IsTrendBearish(m_timeframes[i]))
            bearish_tf_count++;
      }

      // Show score on chart using Logger's static method
      if (bullish_tf_count > 0 || bearish_tf_count > 0)
      {
         double score = (double)bullish_tf_count / (m_timeframe_count * 1.0);
         string signal = bullish_tf_count > bearish_tf_count ? "BUY" : bearish_tf_count > bullish_tf_count ? "SELL"
                                                                                                           : "NEUTRAL";

         // Use Logger's static method for chart display
         Logger::ShowScoreFast(m_symbol, score, signal, 0.8);
      }

      return (bullish_tf_count > 0 || bearish_tf_count > 0);
   }

   // Get price position relative to Bollinger Bands
   int GetBBandsPosition(ENUM_TIMEFRAMES tf, double price)
   {
      if (!m_initialized)
         return 0;

      double upper, middle, lower;
      if (!GetBollingerBandsValues(tf, upper, middle, lower))
         return 0;

      if (price >= upper)
         return 1; // Overbought/upper band
      if (price <= lower)
         return -1; // Oversold/lower band
      if (price > middle)
         return 2; // Upper half
      if (price < middle)
         return -2; // Lower half
      return 0;     // At middle band
   }

   // Calculate position size based on ATR
   double CalculatePositionSize(double risk_percent, double stop_loss_pips, ENUM_TIMEFRAMES tf = PERIOD_M15)
   {
      if (!m_initialized)
         return 0.01;

      double atr_value = GetATRWithFallback(tf);

      if (atr_value <= 0)
         return 0.01;

      double atr_pips = MathUtils::PriceToPips(m_symbol, atr_value);

      // Ensure stop loss is at least 1 ATR
      if (stop_loss_pips < atr_pips)
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
      if (!m_initialized)
         return 0.5;

      int bullish_tf_count, bearish_tf_count;
      GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);

      double rsi = GetRSI(PERIOD_H1);
      double atr = GetATRWithFallback(PERIOD_H1);

      // Simple scoring logic
      double score = 0.5;

      if (bullish_tf_count > bearish_tf_count)
         score += 0.2;
      else if (bearish_tf_count > bullish_tf_count)
         score -= 0.2;

      if (rsi > 70)
         score -= 0.1;
      else if (rsi < 30)
         score += 0.1;

      return MathMax(0.0, MathMin(1.0, score));
   }

   // Get initialization status
   bool IsInitialized() const { return m_initialized; }

   // Get current symbol
   string GetSymbol() const { return m_symbol; }

   // Test method to verify ATR functionality
   void TestATRFunctionality()
   {
      if (!m_initialized)
      {
         DebugLogIndicator("IndicatorManager", "IndicatorManager not initialized");
         return;
      }

      DebugLogIndicator("IndicatorManager", "=== ATR Functionality Test ===");
      DebugLogIndicator("IndicatorManager", "Symbol: " + m_symbol);

      for (int i = 0; i < m_timeframe_count; i++)
      {
         double atr = GetATR(m_timeframes[i], 0);
         DebugLogIndicator("IndicatorManager", StringFormat("TF %d ATR: %.5f (handle: %d)",
                                                            m_timeframes[i], atr, m_handles[i].atr));
      }

      // Test fallback
      double fallbackATR = GetATRWithFallback(PERIOD_H1, 0);
      DebugLogIndicator("IndicatorManager", StringFormat("Fallback ATR: %.5f", fallbackATR));
      DebugLogIndicator("IndicatorManager", "=== End Test ===");
   }

private:
   // Helper function to get indicator value - UPDATED WITH RETRY LOGIC
   double GetIndicatorValue(int handle, int buffer_num, int shift)
   {
      // Check handle validity
      if (handle == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("❌ Invalid handle in GetIndicatorValue: handle=%d", handle));
         return EMPTY_VALUE; // Return EMPTY_VALUE so caller knows it's invalid
      }

      double buffer[1];
      ArrayInitialize(buffer, EMPTY_VALUE); // Initialize to EMPTY_VALUE

      // ============================================
      // CRITICAL: ADD RETRY LOGIC WITH TIMEOUT
      // ============================================
      int maxRetries = 3;
      int retryDelay = 10; // ms
      int copied = 0;

      for (int retry = 0; retry < maxRetries; retry++)
      {
         copied = CopyBuffer(handle, buffer_num, shift, 1, buffer);

         // SUCCESS: We got valid data
         if (copied > 0 && buffer[0] != EMPTY_VALUE &&
             MathIsValidNumber(buffer[0]) && buffer[0] != 0)
         {
            // Additional validation for reasonable values
            if (MathAbs(buffer[0]) > 1e100) // Unrealistically large
            {
               DebugLogIndicatorError("IndicatorManager",
                                      StringFormat("⚠️ Unrealistic value on retry %d: %.5f (abs > 1e100)",
                                                   retry, buffer[0]));
               continue; // Try again
            }

            // VALID VALUE FOUND
            DebugLogIndicator("IndicatorManager",
                              StringFormat("✅ GetIndicatorValue success on retry %d: handle=%d, value=%.5f",
                                           retry, handle, buffer[0]));
            return buffer[0];
         }

         // If not last retry, wait and try again
         if (retry < maxRetries - 1)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("Retry %d/%d failed (copied=%d), waiting %dms...",
                                           retry + 1, maxRetries, copied, retryDelay));
            Sleep(retryDelay);
         }
      }

      // ============================================
      // RETRY WITH DIFFERENT SHIFT IF ORIGINAL FAILS
      // ============================================
      DebugLogIndicator("IndicatorManager",
                        StringFormat("Primary shift %d failed, trying alternative shifts...", shift));

      // Try with positive shift (older data)
      for (int altShift = 1; altShift <= 3; altShift++)
      {
         copied = CopyBuffer(handle, buffer_num, shift + altShift, 1, buffer);

         if (copied > 0 && buffer[0] != EMPTY_VALUE &&
             MathIsValidNumber(buffer[0]) && buffer[0] != 0)
         {
            DebugLogIndicator("IndicatorManager",
                              StringFormat("✅ Got value at shift+%d: %.5f (original shift %d failed)",
                                           altShift, buffer[0], shift));
            return buffer[0];
         }
      }

      // Try with negative shift (if shift > 0)
      if (shift > 0)
      {
         for (int altShift = 1; altShift <= MathMin(shift, 3); altShift++)
         {
            copied = CopyBuffer(handle, buffer_num, shift - altShift, 1, buffer);

            if (copied > 0 && buffer[0] != EMPTY_VALUE &&
                MathIsValidNumber(buffer[0]) && buffer[0] != 0)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("✅ Got value at shift-%d: %.5f (original shift %d failed)",
                                              altShift, buffer[0], shift));
               return buffer[0];
            }
         }
      }

      // ============================================
      // ALL ATTEMPTS FAILED - PROVIDE DETAILED ERROR
      // ============================================
      string errorMsg = StringFormat("❌ GetIndicatorValue FAILED after %d retries and alternative shifts: handle=%d, buffer=%d, shift=%d",
                                     maxRetries, handle, buffer_num, shift);

      // Add specific error information
      int lastError = GetLastError();
      if (lastError != 0)
      {
         errorMsg += StringFormat(", LastError=%d", lastError);
      }

      DebugLogIndicatorError("IndicatorManager", errorMsg);

      // Try one last time with different parameters for debugging
      DebugLogIndicator("IndicatorManager", "Debug: Trying one last time with shift=0...");
      copied = CopyBuffer(handle, buffer_num, 0, 1, buffer);
      if (copied > 0)
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("Debug: shift=0 worked: copied=%d, value=%s",
                                        copied, (buffer[0] == EMPTY_VALUE) ? "EMPTY_VALUE" : DoubleToString(buffer[0], 5)));
      }

      return EMPTY_VALUE; // Return EMPTY_VALUE to indicate complete failure
   }

   int GetTimeframeIndex(ENUM_TIMEFRAMES tf)
   {
      // Simple exact match search
      for (int i = 0; i < m_timeframe_count; i++)
      {
         if (m_timeframes[i] == tf)
            return i;
      }

      // If not found, provide helpful error message
      string requestedTF = "Unknown";

      // Convert timeframe enum to name for better logging
      switch (tf)
      {
      case PERIOD_M1:
         requestedTF = "M1";
         break;
      case PERIOD_M5:
         requestedTF = "M5";
         break;
      case PERIOD_M15:
         requestedTF = "M15";
         break;
      case PERIOD_M30:
         requestedTF = "M30";
         break;
      case PERIOD_H1:
         requestedTF = "H1";
         break;
      case PERIOD_H4:
         requestedTF = "H4";
         break;
      case PERIOD_D1:
         requestedTF = "D1";
         break;
      default:
         requestedTF = "TF-" + IntegerToString(tf);
         break;
      }

      DebugLogIndicatorError("IndicatorManager",
                             StringFormat("Timeframe %s (%d) not found. Available: M1, M5, M15, M30, H1, H4, D1",
                                          requestedTF, tf));

      return -1;
   }

   // Helper to get timeframe name
   string GetTimeframeName(ENUM_TIMEFRAMES tf)
   {
      switch (tf)
      {
      case PERIOD_M1:
         return "M1";
      case PERIOD_M5:
         return "M5";
      case PERIOD_M15:
         return "M15";
      case PERIOD_M30:
         return "M30";
      case PERIOD_H1:
         return "H1";
      case PERIOD_H4:
         return "H4";
      case PERIOD_D1:
         return "D1";
      case PERIOD_W1:
         return "W1";
      case PERIOD_MN1:
         return "MN1";
      default:
         return IntegerToString(tf);
      }
   }

   // Helper to determine minimum bars needed
   int GetMinimumBarsForTF(ENUM_TIMEFRAMES tf)
   {
      switch (tf)
      {
      case PERIOD_M1:
         return 1000; // M1 needs lots of bars
      case PERIOD_M5:
         return 500; // M5
      case PERIOD_M15:
         return 300; // M15
      case PERIOD_M30:
         return 200; // M30
      case PERIOD_H1:
         return 150; // H1
      case PERIOD_H4:
         return 100; // H4
      case PERIOD_D1:
         return 80; // D1
      case PERIOD_W1:
         return 60; // W1
      case PERIOD_MN1:
         return 30; // MN1
      default:
         return 100;
      }
   }

   // Helper to test if timeframe is available
   bool IsTimeframeAvailable(ENUM_TIMEFRAMES tf)
   {
      // Check if timeframe is valid
      if (tf < PERIOD_M1 || tf > PERIOD_MN1)
         return false;

      // Try to get bars for this timeframe
      int bars = iBars(m_symbol, tf);
      if (bars <= 0 && GetLastError() != 0)
         return false;

      return true;
   }

   // Test indicator readiness
   void TestIndicatorReadiness()
   {
      DebugLogIndicator("IndicatorManager", "=== TESTING INDICATOR READINESS ===");

      int successfulTests = 0;
      int totalTests = 0;

      for (int i = 0; i < m_timeframe_count; i++)
      {
         ENUM_TIMEFRAMES tf = m_timeframes[i];
         string tfName = GetTimeframeName(tf);

         if (m_handles[i].ma_fast != INVALID_HANDLE)
         {
            totalTests++;

            double testValue[1];
            int copied = CopyBuffer(m_handles[i].ma_fast, 0, 0, 1, testValue);

            if (copied > 0 && testValue[0] != EMPTY_VALUE && testValue[0] != 0)
            {
               DebugLogIndicator("IndicatorManager",
                                 StringFormat("✅ %s MA: %.4f", tfName, testValue[0]));
               successfulTests++;
            }
            else
            {
               DebugLogIndicatorError("IndicatorManager",
                                      StringFormat("❌ %s MA: Failed (copied=%d)", tfName, copied));

               // Try with a shift if current bar fails
               if (copied <= 0)
               {
                  copied = CopyBuffer(m_handles[i].ma_fast, 0, 1, 1, testValue);
                  if (copied > 0 && testValue[0] != EMPTY_VALUE)
                  {
                     DebugLogIndicator("IndicatorManager",
                                       StringFormat("   Using shift 1: %.4f", testValue[0]));
                  }
               }
            }
         }
      }

      DebugLogIndicator("IndicatorManager",
                        StringFormat("Test results: %d/%d successful",
                                     successfulTests, totalTests));

      if (successfulTests == totalTests && totalTests > 0)
      {
         DebugLogIndicator("IndicatorManager", "✅ All indicators working!");
      }
      else if (successfulTests > 0)
      {
         DebugLogIndicator("IndicatorManager",
                           StringFormat("⚠️ %d/%d indicators working",
                                        successfulTests, totalTests));
      }
      else
      {
         DebugLogIndicatorError("IndicatorManager", "❌ No indicators working!");
      }
   }

   // Helper to validate handle
   bool ValidateHandle(int handle)
   {
      if (handle == INVALID_HANDLE)
         return false;

      // Try to get a value
      double test[1];
      int copied = CopyBuffer(handle, 0, 0, 1, test);

      if (copied <= 0)
      {
         int error = GetLastError();
         DebugLogIndicator("ValidateHandle",
                           StringFormat("Handle %d invalid: copied=%d, error=%d", handle, copied, error));
         return false;
      }

      return true;
   }

   // Reset all handles
   void ResetHandles()
   {
      for (int i = 0; i < m_timeframe_count; i++)
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
      if (atrHandle == INVALID_HANDLE)
      {
         DebugLogIndicatorError("IndicatorManager", "Direct ATR calculation failed");
         return GetDefaultATR();
      }

      double buffer[1];
      ArrayInitialize(buffer, 0.0);

      int copied = CopyBuffer(atrHandle, 0, 0, 1, buffer);
      IndicatorRelease(atrHandle);

      if (copied <= 0)
      {
         DebugLogIndicatorError("IndicatorManager",
                                StringFormat("Direct ATR CopyBuffer failed, copied=%d", copied));
         return GetDefaultATR();
      }

      double atrValue = buffer[0];

      // Validate the direct calculation
      if (atrValue <= 0 || !MathIsValidNumber(atrValue))
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
      if (StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Gold ATR: 10.0 ($10)");
         return 10.0; // $10 for Gold (reasonable default for H1 timeframe)
      }
      else if (StringFind(m_symbol, "XAG") >= 0 || StringFind(m_symbol, "SILVER") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Silver ATR: 0.15 ($0.15)");
         return 0.15; // $0.15 for Silver
      }
      else if (StringFind(m_symbol, "BTC") >= 0 || StringFind(m_symbol, "ETH") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default Crypto ATR: 100.0 ($100)");
         return 100.0; // $100 for Crypto
      }
      else if (StringFind(m_symbol, "EURUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default EURUSD ATR: 0.0005 (5 pips)");
         return 0.0005; // 5 pips for EURUSD
      }
      else if (StringFind(m_symbol, "GBPUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default GBPUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for GBPUSD
      }
      else if (StringFind(m_symbol, "USDJPY") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default USDJPY ATR: 0.08 (8 pips)");
         return 0.08; // 8 pips for USDJPY
      }
      else if (StringFind(m_symbol, "AUDUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default AUDUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for AUDUSD
      }
      else if (StringFind(m_symbol, "USDCAD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default USDCAD ATR: 0.0007 (7 pips)");
         return 0.0007; // 7 pips for USDCAD
      }
      else if (StringFind(m_symbol, "NZDUSD") >= 0)
      {
         DebugLogIndicator("IndicatorManager", "Using default NZDUSD ATR: 0.0006 (6 pips)");
         return 0.0006; // 6 pips for NZDUSD
      }
      else if (StringFind(m_symbol, "USDCHF") >= 0)
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

   // Add this helper function:
   string GetErrorDescription(int error_code)
   {
      switch (error_code)
      {
      case 0:
         return "No error";
      case 1:
         return "No error (reserved)";
      case 2:
         return "Common error";
      case 3:
         return "Invalid trade parameters";
      case 4:
         return "Trade server is busy";
      case 5:
         return "Old version of the client terminal";
      case 6:
         return "No connection with trade server";
      case 7:
         return "Not enough rights";
      case 8:
         return "Too frequent requests";
      case 9:
         return "Malfunctional trade operation";
      case 64:
         return "Account disabled";
      case 65:
         return "Invalid account";
      case 128:
         return "Trade timeout";
      case 129:
         return "Invalid price";
      case 130:
         return "Invalid stops";
      case 131:
         return "Invalid trade volume";
      case 132:
         return "Market is closed";
      case 133:
         return "Trade is disabled";
      case 134:
         return "Not enough money";
      case 135:
         return "Price changed";
      case 136:
         return "Off quotes";
      case 137:
         return "Broker is busy";
      case 138:
         return "Requote";
      case 139:
         return "Order is locked";
      case 140:
         return "Long positions only allowed";
      case 141:
         return "Too many requests";
      case 145:
         return "Modification denied because order is too close to market";
      case 146:
         return "Trade context is busy";
      case 147:
         return "Expirations are denied by broker";
      case 148:
         return "Too many open and pending orders";
      case 4000:
         return "No error (unknown)";
      case 4001:
         return "Wrong function pointer";
      case 4002:
         return "Array index is out of range";
      case 4003:
         return "No memory for function call stack";
      case 4004:
         return "Recursive stack overflow";
      case 4005:
         return "Not enough stack for parameter";
      case 4006:
         return "No memory for parameter string";
      case 4007:
         return "No memory for temp string";
      case 4008:
         return "Not initialized string";
      case 4009:
         return "Not initialized string in array";
      case 4010:
         return "No memory for array string";
      case 4011:
         return "Too long string";
      case 4012:
         return "Remainder from zero divide";
      case 4013:
         return "Zero divide";
      case 4014:
         return "Unknown command";
      case 4015:
         return "Wrong jump (never generated error)";
      case 4016:
         return "Not initialized array";
      case 4017:
         return "DLL calls are not allowed";
      case 4018:
         return "Cannot load library";
      case 4019:
         return "Cannot call function";
      case 4020:
         return "Expert function calls are not allowed";
      case 4021:
         return "Not enough memory for temp string returned from function";
      case 4022:
         return "System is busy (never generated error)";
      case 4050:
         return "Invalid function parameters count";
      case 4051:
         return "Invalid function parameter value";
      case 4052:
         return "String function internal error";
      case 4053:
         return "Some array error";
      case 4054:
         return "Incorrect series array using";
      case 4055:
         return "Custom indicator error";
      case 4056:
         return "Arrays are incompatible";
      case 4057:
         return "Global variables processing error";
      case 4058:
         return "Global variable not found";
      case 4059:
         return "Function is not allowed in testing mode";
      case 4060:
         return "Function is not confirmed";
      case 4061:
         return "Send mail error";
      case 4062:
         return "String parameter expected";
      case 4063:
         return "Integer parameter expected";
      case 4064:
         return "Double parameter expected";
      case 4065:
         return "Array as parameter expected";
      case 4066:
         return "Requested history data in updating state";
      case 4067:
         return "Some error in trade operation";
      case 4099:
         return "End of file";
      case 4100:
         return "Some file error";
      case 4101:
         return "Wrong file name";
      case 4102:
         return "Too many opened files";
      case 4103:
         return "Cannot open file";
      case 4104:
         return "Incompatible access to a file";
      case 4105:
         return "No order selected";
      case 4106:
         return "Unknown symbol";
      case 4107:
         return "Invalid price parameter for trade function";
      case 4108:
         return "Invalid ticket";
      case 4109:
         return "Trade is not allowed";
      case 4110:
         return "Longs are not allowed";
      case 4111:
         return "Shorts are not allowed";
      case 4200:
         return "Object already exists";
      case 4201:
         return "Unknown object property";
      case 4202:
         return "Object does not exist";
      case 4203:
         return "Unknown object type";
      case 4204:
         return "No object name";
      case 4205:
         return "Object coordinates error";
      case 4206:
         return "No specified subwindow";
      case 4207:
         return "Some error in object function";
      default:
         return "Unknown error " + IntegerToString(error_code);
      }
   }
};

IndicatorManager *IndicatorManager::m_instance = NULL;