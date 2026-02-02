//+------------------------------------------------------------------+
//|                                                   MarketRegime.mq5|
//|             Simplified Market Regime & Lifecycle Detection       |
//+------------------------------------------------------------------+
// Logger Integration Status: FULLY INTEGRATED
// All logging uses static DebugRegimeLogFile() calls with debug wrapper
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property version "1.00"
#property strict

#include <Math\Stat\Math.mqh>

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"
#include "../Data/IndicatorManager.mqh"
#include "../Utils/Logger.mqh"

// ====================== INPUT PARAMETERS ======================
// User-adjustable thresholds for Strategy Tester optimization
input group "=== Market Regime Detection Settings ===" input double Inp_ADX_Trending_Threshold = 25.0; // ADX trending threshold (>=)
input double Inp_ADX_Trend_Confirmation = 20.0;                                                        // ADX trend confirmation level
input double Inp_ADX_Exhaustion = 40.0;                                                                // ADX exhaustion level (overbought/oversold)
input double Inp_ADX_Contraction = 15.0;                                                               // ADX contraction (range) level

input group "=== Price & Moving Average Settings ===" input double Inp_Price_Far_From_MA = 0.5; // Price far from MA (%) 1.0
input double Inp_Price_Near_MA = 0.5;                                                           // Price near MA (%)
input double Inp_Price_Too_Far_For_Range = 0.8;                                                 // Price too far for range (%)

input group "=== Volatility Settings ===" input double Inp_Volatility_High = 0.7; // High volatility threshold
input double Inp_Volatility_Low = 0.3;                                            // Low volatility threshold
input double Inp_Volatility_For_New_Range = 0.5;                                  // Volatility for new range creation

input group "=== Range Settings ===" input int Inp_Range_Touches_Weak = 1; // Weak range touches (minimum)
input int Inp_Range_Touches_Strong = 2;                                    // Strong range touches
input int Inp_Range_Lookback_Bars = 40;                                    // Bars to look back for range
input int Inp_Structure_Lookback_Bars = 40;                                // Bars to look back for range
input int Inp_Invalidation_Cooldown_Bars = 8;                              // Bars to wait after range invalidation
input double Inp_Breakout_Margin_Multiplier = 0.8;                         // Change from 0.5 to 0.8 or 1.2 for more strict

input group "=== Account & Risk Settings ===" input double Inp_Account_Balance = 10000.0; // Account balance for position sizing
input double Inp_Account_Risk_Percent = 1.0;                                              // Risk percentage per trade

input group "=== Debug Settings ===" input bool Inp_Debug_Regime_Enabled = false; // Enable debug logging

// ====================== DEBUG SETTINGS ======================
bool DEBUG_REGIME_ENABLED = Inp_Debug_Regime_Enabled;

// Enhanced debug wrapper functions using Logger
void DebugRegimeLogFile(string context, string message, bool logToFile = true, bool logToConsole = true)
{
   if (DEBUG_REGIME_ENABLED)
   {
      Logger::Log("MarketRegime", StringFormat("%s: %s", context, message), logToFile, logToConsole);
   }
}

void DebugRegimeError(string context, string message)
{
   if (DEBUG_REGIME_ENABLED)
   {
      string fullMsg = StringFormat("%s: %s", context, message);
      Logger::LogError("MarketRegime", fullMsg);
      DebugRegimeLogFile("ERROR", fullMsg, true, true);
   }
}

void DebugRegimeWarning(string context, string message)
{
   if (DEBUG_REGIME_ENABLED)
   {
      DebugRegimeLogFile("WARNING", StringFormat("%s: %s", context, message), true, true);
   }
}

void DebugRegimePrint(string context, string message)
{
   if (DEBUG_REGIME_ENABLED)
   {
      DebugRegimeLogFile(context, message, true, true);
   }
}

// ==================== GLOBAL INSTANCE COUNTER ====================
int globalInstanceCounter = 0;

//+------------------------------------------------------------------+
//| Market Regime Detector Class                                     |
//+------------------------------------------------------------------+
class MarketRegimeDetector
{
private:
   // ==================== THRESHOLD MEMBER VARIABLES ====================
   // These are now instance variables initialized from input parameters
   double m_adxTrendingThreshold;
   double m_adxTrendConfirmation;
   double m_adxExhaustion;
   double m_adxContraction;

   double m_priceFarFromMA;
   double m_priceNearMA;
   double m_priceTooFarForRange;

   double m_volatilityHigh;
   double m_volatilityLow;
   double m_volatilityForNewRange;

   int m_rangeTouchesWeak;
   int m_rangeTouchesStrong;

   // Add these with other member variables
   ENUM_MARKET_STATE m_lastState;
   int m_statePersistence; // Bars in current state
   int m_minStateBars;     // Minimum bars before changing

   // ==================== CACHE STRUCT ====================
   struct MarketStateCache
   {
      datetime timestamp;
      double adx;
      double atr;
      double ma50;
      double ma50_5; // MA 5 bars ago for slope
      double currentPrice;
      double priceVsMAPercent;  // (price-ma50)/ma50*100
      double priceVsMAAbsolute; // MathAbs(price-ma50)
      double volatilityScore;
      double bbWidth;
      int rangeTouches;
      bool priceInRange;
      bool rangeActive;
      double priceChange8; // Last 8 bars change
      double maSlope;

      MarketRegimeDetector *m_detector; // Reference to parent detector

      // Check if price is too far from MA for range
      bool IsPriceTooFarForRange()
      {
         if (m_detector == NULL)
            return false;
         return priceVsMAPercent > m_detector.m_priceTooFarForRange;
      }

      void Calculate(MarketRegimeDetector &detector)
      {
         m_detector = &detector;

         datetime currentBarTime = iTime(detector.m_symbol, detector.m_timeframe, 0);

         // Check if we're on the same bar
         if (timestamp == currentBarTime)
         {
            DebugRegimeLogFile("Cache", "CACHE HIT - Updating tick-sensitive values");

            // Even on cache hit, we MUST update these values (they change every tick):
            // 1. Current price (changes every tick)
            currentPrice = iClose(detector.m_symbol, detector.m_timeframe, 0);
            DebugRegimeLogFile("Cache", StringFormat("Updated current price = %.5f", currentPrice));

            // 2. ATR (volatility changes)
            atr = detector.GetATR(14);
            DebugRegimeLogFile("Cache", StringFormat("Updated ATR = %.5f", atr));

            // 3. Recalculate price vs MA (price changed)
            if (ma50 > 0)
            {
               priceVsMAPercent = MathAbs(currentPrice - ma50) / ma50 * 100;
               priceVsMAAbsolute = MathAbs(currentPrice - ma50);
               DebugRegimeLogFile("Cache", StringFormat("Updated PriceVsMA Percent = %.2f%%", priceVsMAPercent));
            }

            // 4. Update volatility score (depends on ATR)
            volatilityScore = detector.CalculateVolatilityScore(atr, bbWidth);
            DebugRegimeLogFile("Cache", StringFormat("Updated volatility score = %.3f", volatilityScore));

            // 5. Check range status (price might have moved)
            priceInRange = detector.IsPriceInFixedRange(currentPrice);
            DebugRegimeLogFile("Cache", StringFormat("Price in range? %s", priceInRange ? "YES" : "NO"));

            // 6. Get fresh range touches count
            rangeTouches = detector.CountRangeTouches();
            DebugRegimeLogFile("Cache", StringFormat("Range touches = %d", rangeTouches));

            // BAR-BASED VALUES STAY CACHED (only change on new bar):
            // - MA values (calculated from bar close prices)
            // - ADX (based on bar data)
            // - Structure analysis (bar-based)

            return; // Skip bar-based recalculations
         }

         DebugRegimeLogFile("Cache", "CACHE MISS - Calculating ALL values for new bar");
         timestamp = currentBarTime;

         // ==================== BAR-BASED CALCULATIONS ====================
         // These only change when a new bar forms

         // Get indicator values
         DebugRegimeLogFile("Cache", "Getting indicator values for new bar...");
         adx = detector.GetADX(14);
         atr = detector.GetATR(14);
         ma50 = detector.GetMAValue(50, 0);
         ma50_5 = detector.GetMAValue(50, 5);
         bbWidth = detector.GetBollingerWidth(20, 2);
         priceChange8 = detector.GetPriceChange(8);

         DebugRegimeLogFile("Cache", StringFormat("ADX = %.1f, ATR = %.5f, BB Width = %.3f%%, Price change (8 bars) = %.2f%%",
                                                  adx, atr, bbWidth, priceChange8));

         // Get current price
         currentPrice = iClose(detector.m_symbol, detector.m_timeframe, 0);
         DebugRegimeLogFile("Cache", StringFormat("Current Price = %.5f", currentPrice));

         // Calculate MA-based values
         if (ma50 > 0)
         {
            priceVsMAPercent = MathAbs(currentPrice - ma50) / ma50 * 100;
            priceVsMAAbsolute = MathAbs(currentPrice - ma50);
            maSlope = (ma50 - ma50_5) / 5.0;

            DebugRegimeLogFile("Cache", StringFormat("✅ MA50 valid: PriceVsMA Percent = %.2f%%, Absolute = %.5f, Slope = %.5f",
                                                     priceVsMAPercent, priceVsMAAbsolute, maSlope));
         }
         else
         {
            DebugRegimeError("Cache", StringFormat("MA50 <= 0! Value = %.5f, MA50_5 = %.5f", ma50, ma50_5));

            // Try to get MA value directly as fallback
            double testMA = iMA(detector.m_symbol, detector.m_timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
            DebugRegimeLogFile("Cache", StringFormat("Direct iMA test: %.5f", testMA));

            // Keep previous values if MA calculation fails
            if (priceVsMAPercent == 0)
            {
               priceVsMAPercent = 0.5; // Default value
               DebugRegimeLogFile("Cache", "Using default PriceVsMA: 0.5%");
            }
         }

         // Calculate derived values
         volatilityScore = detector.CalculateVolatilityScore(atr, bbWidth);
         rangeTouches = detector.CountRangeTouches();
         priceInRange = detector.IsPriceInFixedRange(currentPrice);
         rangeActive = detector.m_rangeActive;

         DebugRegimeLogFile("Cache", StringFormat("Volatility score = %.3f, Range touches = %d, Price in range? %s, Range active? %s",
                                                  volatilityScore, rangeTouches, priceInRange ? "YES" : "NO", rangeActive ? "YES" : "NO"));
         DebugRegimeLogFile("Cache", "END CACHE CALCULATION");
      }
   };

   // ==================== MEMBER VARIABLES ====================
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   double m_fixedRangeTop;
   double m_fixedRangeBottom;
   datetime m_rangeStartTime;
   bool m_rangeActive;
   int m_lookbackBars;

   // Account info for position sizing
   double m_accountBalance;
   double m_accountRiskPercent;

   // Indicator Manager instance
   IndicatorManager *m_indicatorManager;
   bool m_useIndicatorManager;

   int m_rangeLookbackBars; // How many bars to look back for the range
   int m_structureLookbackBars;
   int m_barsSinceLastRangeInit;  // Bars since last range initialization
   datetime m_lastRangeCheckTime; // Last time we checked for reinitialization

   // Range invalidation tracking
   datetime m_lastInvalidationTime; // Track when range was invalidated
   int m_invalidationCooldownBars;  // Bars to wait before new range

   // Cache instance
   MarketStateCache m_cache;

   // Instance tracking
   int m_instanceId;
   static int m_totalInstances;

   // ==================== PRIVATE SINGLETON CONSTRUCTOR ====================
   MarketRegimeDetector(string symbol = NULL,
                        ENUM_TIMEFRAMES tf = PERIOD_M15,
                        double accountBalance = 0, // Will use input parameter if not provided
                        double riskPercent = 0,    // Will use input parameter if not provided
                        bool useIndicatorManager = true)
   {
      m_instanceId = globalInstanceCounter++;
      m_totalInstances++;

      DebugRegimePrint("Constructor", StringFormat("Creating Market Regime Detector Instance #%d (Total: %d)",
                                                   m_instanceId, m_totalInstances));

      m_symbol = (symbol == NULL) ? Symbol() : symbol;
      m_timeframe = tf;
      m_rangeActive = false;
      m_lookbackBars = 10;

      // Use provided values or input parameters
      m_accountBalance = (accountBalance > 0) ? accountBalance : Inp_Account_Balance;
      m_accountRiskPercent = (riskPercent > 0) ? riskPercent : Inp_Account_Risk_Percent;

      m_useIndicatorManager = useIndicatorManager;

      m_rangeLookbackBars = Inp_Range_Lookback_Bars;
      m_structureLookbackBars = Inp_Structure_Lookback_Bars;
      m_barsSinceLastRangeInit = 0;
      m_lastRangeCheckTime = 0;

      // Initialize invalidation tracking
      m_lastInvalidationTime = 0;
      m_invalidationCooldownBars = Inp_Invalidation_Cooldown_Bars;

      // ==================== INITIALIZE THRESHOLDS FROM INPUT PARAMETERS ====================
      m_adxTrendingThreshold = Inp_ADX_Trending_Threshold;
      m_adxTrendConfirmation = Inp_ADX_Trend_Confirmation;
      m_adxExhaustion = Inp_ADX_Exhaustion;
      m_adxContraction = Inp_ADX_Contraction;

      m_priceFarFromMA = Inp_Price_Far_From_MA;
      m_priceNearMA = Inp_Price_Near_MA;
      m_priceTooFarForRange = Inp_Price_Too_Far_For_Range;

      m_volatilityHigh = Inp_Volatility_High;
      m_volatilityLow = Inp_Volatility_Low;
      m_volatilityForNewRange = Inp_Volatility_For_New_Range;

      m_rangeTouchesWeak = Inp_Range_Touches_Weak;
      m_rangeTouchesStrong = Inp_Range_Touches_Strong;

      m_lastState = STATE_UNKNOWN;
      m_statePersistence = 0;
      m_minStateBars = 3;

      DebugRegimeLogFile("Constructor", StringFormat("Instance #%d: Initializing detector for %s timeframe %d",
                                                     m_instanceId, m_symbol, m_timeframe));

      // ==================== ✅ UPDATED: USE SINGLETON INSTEAD OF CREATING NEW ====================
      if (m_useIndicatorManager)
      {
         // ✅ GET THE SINGLETON INSTANCE
         m_indicatorManager = IndicatorManager::Instance();

         if (m_indicatorManager == NULL)
         {
            DebugRegimeError("Constructor", "Failed to get IndicatorManager singleton. Falling back to direct indicators.");
            m_useIndicatorManager = false;
         }
         else
         {
            // ✅ Ensure singleton is initialized
            if (!m_indicatorManager.IsInitialized())
            {
               DebugRegimeLogFile("Constructor", "IndicatorManager singleton not initialized, initializing now...");
               if (!m_indicatorManager.Initialize())
               {
                  DebugRegimeError("Constructor", "Failed to initialize IndicatorManager singleton. Falling back to direct indicators.");
                  m_useIndicatorManager = false;
                  m_indicatorManager = NULL;
               }
               else
               {
                  DebugRegimeLogFile("Constructor", "IndicatorManager singleton initialized successfully");
               }
            }
            else
            {
               DebugRegimeLogFile("Constructor", "IndicatorManager singleton already initialized");
            }
         }
      }
      else
      {
         m_indicatorManager = NULL;
         DebugRegimeLogFile("Constructor", "Using direct indicators (no IndicatorManager)");
      }

      // Initialize fixed range
      InitializeFixedRange();
   }

public:
   // ==================== PUBLIC GETTER METHODS ====================
   string GetSymbol() const { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }
   int GetInstanceId() const { return m_instanceId; }
   static int GetTotalInstances() { return m_totalInstances; }

   // ==================== SINGLETON PATTERN ====================
   static MarketRegimeDetector *Instance(string symbol = NULL,
                                         ENUM_TIMEFRAMES tf = PERIOD_M15,
                                         double accountBalance = 0,
                                         double riskPercent = 0,
                                         bool useIndicatorManager = true)
   {
      static MarketRegimeDetector *instance = NULL;

      if (instance == NULL)
      {
         // Create ONCE, on first call
         instance = new MarketRegimeDetector(symbol, tf, accountBalance, riskPercent, useIndicatorManager);
         DebugRegimePrint("Singleton", StringFormat("MARKET REGIME DETECTOR CREATED: Instance #%d for %s %s",
                                                    instance.GetInstanceId(),
                                                    (symbol == NULL ? Symbol() : symbol),
                                                    EnumToString(tf)));
      }
      else
      {
         // Warn if trying to use different timeframe (THIS SHOULD NEVER HAPPEN!)
         string currentSymbol = (symbol == NULL ? Symbol() : symbol);
         if (instance.GetSymbol() != currentSymbol || instance.GetTimeframe() != tf)
         {
            DebugRegimeWarning("Singleton", StringFormat("Singleton requested for different symbol/timeframe! Existing: %s %s, Requested: %s %s",
                                                         instance.GetSymbol(), EnumToString(instance.GetTimeframe()),
                                                         currentSymbol, EnumToString(tf)));
         }
      }

      return instance;
   }

   static void DeleteInstance()
   {
      static MarketRegimeDetector *instance = NULL;
      if (instance != NULL)
      {
         DebugRegimePrint("Singleton", StringFormat("Deleting Market Regime Detector Singleton: Instance #%d", instance.GetInstanceId()));
         delete instance;
         instance = NULL;
         m_totalInstances--;
         DebugRegimeLogFile("Singleton", "Deleted MarketRegimeDetector instance");
      }
   }

   ~MarketRegimeDetector()
   {
      DebugRegimeLogFile("Destructor", StringFormat("Cleaning up MarketRegimeDetector Instance #%d", m_instanceId));

      // ✅ DO NOT delete IndicatorManager - it's a singleton!
      // Just clear the pointer
      m_indicatorManager = NULL;

      m_totalInstances--;

      DebugRegimeLogFile("MarketRegime", StringFormat("Detector Instance #%d shutdown complete", m_instanceId), true, false);
   }

   //+------------------------------------------------------------------+
   //| MAIN PUBLIC METHOD: Get complete market analysis                |
   //+------------------------------------------------------------------+
   MarketAnalysis GetMarketRegime()
   {
      DebugRegimeLogFile("GetMarketRegime", StringFormat("=== INSTANCE #%d: STARTING MARKET ANALYSIS ===", m_instanceId));

      // Log instance identifier
      static int callCount = 0;
      callCount++;

      DebugRegimeLogFile("GetMarketRegime",
                         StringFormat("CALL #%d | Instance #%d: %s %s",
                                      callCount, m_instanceId, m_symbol, EnumToString(m_timeframe)));

      // CALCULATE EVERYTHING ONCE PER BAR
      m_cache.Calculate(this);

      // VERIFY RANGE STATUS BEFORE ANALYSIS
      VerifyRangeStatus();

      MarketAnalysis analysis;

      // 1. Check if we should reinitialize existing range
      CheckAndReinitializeRange();

      // 2. Initialize fixed range if not active AND conditions are right
      if (!m_rangeActive && ShouldCreateNewRange())
      {
         InitializeFixedRange();
         m_cache.rangeActive = true;
         m_cache.priceInRange = true;
      }

      // 3. Get current state using CACHED values
      analysis.state = DetectCurrentState();
      analysis.rootState = GetRootState(analysis.state);
      analysis.confidence = CalculateConfidence(analysis.state);

      // 4. LOG FINAL DETERMINATION
      LogFinalStateDetermination(analysis.state, analysis.rootState);

      // 5. Verify cache is synchronized
      if (m_cache.rangeActive != m_rangeActive)
      {
         DebugRegimeWarning("CacheSync",
                            StringFormat("CACHE OUT OF SYNC! m_rangeActive=%s, cache.rangeActive=%s - FIXING",
                                         m_rangeActive ? "true" : "false",
                                         m_cache.rangeActive ? "true" : "false"));
         m_cache.rangeActive = m_rangeActive;
         m_cache.priceInRange = m_rangeActive && IsPriceInFixedRange(m_cache.currentPrice);
      }

      DebugRegimeLogFile("GetMarketRegime", StringFormat("Detected state: %s with %.1f%% confidence",
                                                         MarketAnalysis::GetStateString(analysis.state), analysis.confidence));

      // 6. Determine next likely state
      analysis.nextLikelyState = PredictNextState(analysis.state);

      // 7. Generate trading recommendations
      GenerateRecommendations(analysis);

      if (DEBUG_REGIME_ENABLED)
      {
         LogTradeSignal(analysis);
      }

      // 8. Set description
      analysis.description = GenerateDescription(analysis);

      // 9. FINAL VERIFICATION
      VerifyRangeStatus();

      DebugRegimeLogFile("GetMarketRegime", "Analysis complete");

      // Log final analysis summary
      string summary = StringFormat("INSTANCE #%d | ANALYSIS: %s | Confidence: %.0f%% | Action: %s | R/R: %.1f",
                                    m_instanceId,
                                    MarketAnalysis::GetStateString(analysis.state),
                                    analysis.confidence,
                                    analysis.action,
                                    analysis.riskRewardRatio);

      DebugRegimePrint("MarketRegime", "=== MARKET REGIME SUMMARY ===");
      DebugRegimePrint("MarketRegime", summary);
      DebugRegimePrint("MarketRegime", "=============================");

      return analysis;
   }

private:

   // Add this method in private section
   ENUM_MARKET_STATE ApplyHysteresis(ENUM_MARKET_STATE newState)
   {
      // Apply hysteresis to prevent whipsaw
      if (newState == m_lastState)
      {
         m_statePersistence++;
         DebugRegimeLogFile("StatePersistence",
                            StringFormat("Instance #%d | State %s maintained for %d bars",
                                         m_instanceId, MarketAnalysis::GetStateString(newState), m_statePersistence));
      }
      else if (m_statePersistence < m_minStateBars && m_lastState != STATE_UNKNOWN)
      {
         // Not enough bars in old state - block change
         DebugRegimeLogFile("StateHysteresis",
                            StringFormat("Instance #%d | BLOCKING state change: %s -> %s (only %d bars in current)",
                                         m_instanceId,
                                         MarketAnalysis::GetStateString(m_lastState),
                                         MarketAnalysis::GetStateString(newState),
                                         m_statePersistence));

         // Return old state
         m_statePersistence++; // Count this as persistence in old state
         return m_lastState;
      }
      else
      {
         // State change allowed
         DebugRegimeLogFile("StateChange",
                            StringFormat("Instance #%d | State changed: %s -> %s (was in %s for %d bars)",
                                         m_instanceId,
                                         MarketAnalysis::GetStateString(m_lastState),
                                         MarketAnalysis::GetStateString(newState),
                                         MarketAnalysis::GetStateString(m_lastState),
                                         m_statePersistence));

         m_lastState = newState;
         m_statePersistence = 1;
      }

      return newState;
   }

   // Add these helper methods
   bool IsPricePulledBackToMA50()
   {
      // Check if price was far from MA50 and now returned
      double priceVsMA_Now = m_cache.priceVsMAPercent;
      double priceVsMA_5BarsAgo = GetPriceVsMA(5);

      // Was price > 0.8% away 5 bars ago?
      bool wasFarAway = MathAbs(priceVsMA_5BarsAgo) > 0.8;

      // Is now close to MA50?
      bool nowClose = MathAbs(priceVsMA_Now) < 0.3;

      // Is price decelerating toward MA50?
      bool slowingDown = MathAbs(m_cache.maSlope) < 0.0002;

      bool result = wasFarAway && nowClose && slowingDown;

      if (result)
      {
         DebugRegimeLogFile("IsPricePulledBackToMA50",
                            StringFormat("Instance #%d | Pullback detected: Was %.2f%%, Now %.2f%%, Slope %.5f",
                                         m_instanceId, priceVsMA_5BarsAgo, priceVsMA_Now, m_cache.maSlope));
      }

      return result;
   }

   double GetPriceVsMA(int barsAgo)
   {
      double ma = GetMAValue(50, barsAgo);
      double price = iClose(m_symbol, m_timeframe, barsAgo);

      if (ma > 0)
         return MathAbs(price - ma) / ma * 100;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| FINAL STATE LOGGING METHOD                                      |
   //+------------------------------------------------------------------+
   void LogFinalStateDetermination(ENUM_MARKET_STATE state, ENUM_ROOT_REGIME rootState)
   {
      string finalState = MarketAnalysis::GetStateString(state);
      string rootRegime = (rootState == REGIME_TRENDING) ? "TREND" : "RANGE";

      string finalMsg = StringFormat("INSTANCE #%d | FINAL RESULT: %s . %s regime",
                                     m_instanceId, finalState, rootRegime);

      // Log with special markers for easy identification
      DebugRegimePrint("FINAL_STATE", "================================================");
      DebugRegimePrint("FINAL_STATE", finalMsg);
      DebugRegimePrint("FINAL_STATE", "================================================");

      // Additional context
      DebugRegimeLogFile("StateDetails",
                         StringFormat("Instance #%d | State: %s, Root: %s, Price: %.5f, RangeActive: %s",
                                      m_instanceId, finalState, rootRegime,
                                      m_cache.currentPrice,
                                      m_rangeActive ? "YES" : "NO"));
   }

   //+------------------------------------------------------------------+
   //| RANGE STATUS VERIFICATION METHOD                                |
   //+------------------------------------------------------------------+
   void VerifyRangeStatus()
   {
      string rangeStatus = StringFormat(
          "Instance #%d | RANGE VERIFICATION | Active: %s | Top: %.5f | Bottom: %.5f | PriceInRange: %s | Touches: %d",
          m_instanceId,
          m_rangeActive ? "YES" : "NO",
          m_fixedRangeTop,
          m_fixedRangeBottom,
          IsPriceInFixedRange(m_cache.currentPrice) ? "YES" : "NO",
          m_cache.rangeTouches);

      DebugRegimeLogFile("RangeVerification", rangeStatus);
   }

   //+------------------------------------------------------------------+
   //| SIMPLE TRADE LOGGING                                            |
   //+------------------------------------------------------------------+
   void LogTradeSignal(const MarketAnalysis &analysis)
   {
      if (!DEBUG_REGIME_ENABLED)
         return;

      // Determine trade signal
      string tradeSignal = "HOLD";
      if (analysis.direction == "Bullish breakout")
         tradeSignal = "BUY";
      else if (analysis.direction == "Bearish breakout")
         tradeSignal = "SELL";
      else if (analysis.action == "Fade range extremes" ||
               analysis.action == "Fade carefully with tight stops")
         tradeSignal = "FADE";
      else if (analysis.action == "Add to winning positions")
         tradeSignal = "ADD_TO_TREND";
      else if (analysis.action == "Take partial profits")
         tradeSignal = "TAKE_PROFIT";
      else if (analysis.action == "Exit positions, wait for clarity")
         tradeSignal = "EXIT_ALL";

      // Calculate position size in lots
      double positionLots = 0;
      switch (analysis.positionSize)
      {
      case SIZE_VERY_SMALL:
         positionLots = 0.01;
         break;
      case SIZE_SMALL:
         positionLots = 0.05;
         break;
      case SIZE_MEDIUM:
         positionLots = 0.10;
         break;
      case SIZE_LARGE:
         positionLots = 0.20;
         break;
      }

      // Create trade log message
      string tradeMsg = StringFormat("Instance #%d | %s %s | State: %s | Action: %s | Size: %s (%.2f lots) | R/R: %.1f",
                                     m_instanceId, tradeSignal, m_symbol,
                                     MarketAnalysis::GetStateString(analysis.state),
                                     analysis.action,
                                     GetPositionSizeString(analysis.positionSize),
                                     positionLots,
                                     analysis.riskRewardRatio);

      // Log using debug wrapper
      DebugRegimeLogFile("TradeSignal", tradeMsg, true, false);

      // For BUY/SELL signals, also use Logger::LogTrade
      if (tradeSignal == "BUY" || tradeSignal == "SELL")
      {
         string tradeDetail = StringFormat("Instance #%d | Trade Signal: %s %s %.2f lots @ %.5f",
                                           m_instanceId, tradeSignal, m_symbol, positionLots, m_cache.currentPrice);
         Logger::LogTrade("MarketRegime", m_symbol, tradeSignal, positionLots, m_cache.currentPrice);
      }
   }

   void CheckAndReinitializeRange()
   {
      datetime currentTime = iTime(m_symbol, m_timeframe, 0);

      if (m_lastRangeCheckTime == currentTime)
         return;

      m_lastRangeCheckTime = currentTime;
      m_barsSinceLastRangeInit++;

      DebugRegimeLogFile("CheckAndReinitializeRange",
                         StringFormat("Instance #%d | === RANGE MAINTENANCE CHECK === | Bars since init: %d",
                                      m_instanceId, m_barsSinceLastRangeInit));

      // CRITICAL DEBUG: Log before invalidation
      DebugRegimeLogFile("CheckAndReinitializeRange",
                         StringFormat("Instance #%d | BEFORE Invalidation: m_rangeActive=%s, cache.rangeActive=%s",
                                      m_instanceId, m_rangeActive ? "true" : "false", m_cache.rangeActive ? "true" : "false"));

      // 1. FIRST check if range should be invalidated (regardless of m_rangeActive)
      CheckAndInvalidateRange();

      // CRITICAL DEBUG: Log after invalidation
      DebugRegimeLogFile("CheckAndReinitializeRange",
                         StringFormat("Instance #%d | AFTER Invalidation: m_rangeActive=%s, cache.rangeActive=%s",
                                      m_instanceId, m_rangeActive ? "true" : "false", m_cache.rangeActive ? "true" : "false"));

      // 2. ONLY THEN check reinitialization for ACTIVE ranges
      if (m_rangeActive && ShouldSmartReinitialize())
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", StringFormat("Instance #%d | Range needs reinitialization", m_instanceId));
         ReinitializeRange();
      }
      else if (m_rangeActive)
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", StringFormat("Instance #%d | Range active, no reinitialization needed", m_instanceId));
      }
      else
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", StringFormat("Instance #%d | No active range", m_instanceId));
      }
   }

   //+------------------------------------------------------------------+
   //| SMART RANGE REINITIALIZATION                                    |
   //+------------------------------------------------------------------+
   bool ShouldSmartReinitialize()
   {
      DebugRegimeLogFile("ShouldSmartReinitialize", StringFormat("Instance #%d | Checking if smart reinitialization is needed", m_instanceId));

      // Get current market state (uses cached values)
      ENUM_MARKET_STATE state = DetectCurrentState();
      double confidence = CalculateConfidence(state);

      // Condition 1: Clear ranging state with high confidence
      bool isClearRanging = (state == STATE_RANGING_LOW_VOL || state == STATE_RANGING_HIGH_VOL) &&
                            confidence > 50;

      // Condition 2: Range is too old (more than X bars)
      bool rangeIsOld = m_barsSinceLastRangeInit >= m_rangeLookbackBars;

      // Condition 3: Price has moved slightly outside the range
      bool priceOutOfRange = false;
      if (m_rangeActive)
      {
         double rangeWidth = m_fixedRangeTop - m_fixedRangeBottom;
         double atr = m_cache.atr;

         if (m_cache.currentPrice > m_fixedRangeTop + (rangeWidth * 0.3) ||
             m_cache.currentPrice < m_fixedRangeBottom - (rangeWidth * 0.3))
         {
            priceOutOfRange = true;
         }
      }

      // Decision matrix
      if (rangeIsOld)
      {
         if (isClearRanging || priceOutOfRange)
         {
            DebugRegimeLogFile("ShouldSmartReinitialize", StringFormat("Instance #%d | Conditions met for smart reinitialization", m_instanceId));
            return true;
         }

         // Reinitialize if market is in contraction/expansion phase
         if (state == STATE_CONTRACTION || state == STATE_EXPANSION)
         {
            DebugRegimeLogFile("ShouldSmartReinitialize", StringFormat("Instance #%d | Contraction/Expansion phase detected", m_instanceId));
            return true;
         }
      }

      DebugRegimeLogFile("ShouldSmartReinitialize", StringFormat("Instance #%d | No need for smart reinitialization", m_instanceId));
      return false;
   }

   void ReinitializeRange()
   {
      DebugRegimeLogFile("ReinitializeRange", StringFormat("Instance #%d | Reinitializing fixed range...", m_instanceId));
      InitializeFixedRange();
      m_barsSinceLastRangeInit = 0;
   }

   void InitializeFixedRange()
   {
      DebugRegimeLogFile("InitializeFixedRange", StringFormat("Instance #%d | === ATTEMPTING RANGE INITIALIZATION ===", m_instanceId));

      // ==================== CHECK FOR DUPLICATE INITIALIZATION ====================
      // Use static variable to track last initialization time
      static datetime lastInitTime = 0;
      datetime currentTime = iTime(m_symbol, m_timeframe, 0);

      if (lastInitTime == currentTime && m_rangeActive)
      {
         DebugRegimeLogFile("InitializeFixedRange", StringFormat("Instance #%d | Already initialized this bar, skipping duplicate", m_instanceId));
         return;
      }

      // ==================== COMPREHENSIVE GUARDS ====================
      // GUARD 1: Don't initialize if range is already active
      if (m_rangeActive)
      {
         DebugRegimeLogFile("InitializeFixedRange",
                            StringFormat("Instance #%d | Range already active (Top: %.5f, Bottom: %.5f), skipping",
                                         m_instanceId, m_fixedRangeTop, m_fixedRangeBottom));
         return;
      }

      // GUARD 2: Check cooldown after invalidation
      if (m_lastInvalidationTime > 0)
      {
         int barsSinceInvalidation = iBarShift(m_symbol, m_timeframe, m_lastInvalidationTime);
         if (barsSinceInvalidation < m_invalidationCooldownBars)
         {
            DebugRegimeLogFile("InitializeFixedRange",
                               StringFormat("Instance #%d | Still in cooldown: %d/%d bars since invalidation",
                                            m_instanceId, barsSinceInvalidation, m_invalidationCooldownBars));
            return;
         }
      }

      // GUARD 3: Check if market conditions are suitable for range creation
      if (!ShouldCreateNewRange())
      {
         DebugRegimeLogFile("InitializeFixedRange", StringFormat("Instance #%d | Market conditions not suitable for new range", m_instanceId));
         return;
      }

      // ==================== ACTUAL RANGE CREATION ====================
      DebugRegimeLogFile("InitializeFixedRange", StringFormat("Instance #%d | All guards passed, creating new range", m_instanceId));

      int bars = Inp_Range_Lookback_Bars;
      double highest = 0;
      double lowest = DBL_MAX;

      for (int i = 0; i < bars; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         double low = iLow(m_symbol, m_timeframe, i);

         if (high > highest)
            highest = high;
         if (low < lowest)
            lowest = low;
      }

      if (highest > lowest)
      {
         m_fixedRangeTop = highest;
         m_fixedRangeBottom = lowest;
         m_rangeStartTime = currentTime;
         m_rangeActive = true;
         m_barsSinceLastRangeInit = 0;
         lastInitTime = currentTime; // Track when we initialized

         // CRITICAL: Update cache to reflect new range
         m_cache.rangeActive = true;
         m_cache.priceInRange = IsPriceInFixedRange(m_cache.currentPrice);

         string rangeInfo = StringFormat("Instance #%d | Fixed Range Initialized: %.5f - %.5f (Width: %.2f%%)",
                                         m_instanceId, lowest, highest,
                                         ((highest - lowest) / ((highest + lowest) / 2)) * 100);

         // Log using debug wrapper
         DebugRegimePrint("RangeInfo", rangeInfo);

         // Log range details separately
         if (DEBUG_REGIME_ENABLED)
         {
            DebugRegimeLogFile("RangeDetails",
                               StringFormat("Instance #%d | Range created: %.5f-%.5f | Mid: %.5f | Current Price: %.5f",
                                            m_instanceId, lowest, highest, (highest + lowest) / 2, m_cache.currentPrice));
         }
      }
      else
      {
         DebugRegimeError("InitializeFixedRange", StringFormat("Instance #%d | Failed to initialize fixed range (highest <= lowest)", m_instanceId));
      }
   }

   //+------------------------------------------------------------------+
   //| SHOULD CREATE NEW RANGE METHOD                                   |
   //+------------------------------------------------------------------+
   bool ShouldCreateNewRange()
   {
      DebugRegimeLogFile("ShouldCreateNewRange",
                         StringFormat("Instance #%d | === Checking if new range should be created ===", m_instanceId));

      // GUARD 0: Already active?
      if (m_rangeActive)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Range already active", m_instanceId));
         return false;
      }

      // 1. Check cooldown period
      if (m_lastInvalidationTime > 0)
      {
         int barsSinceInvalidation = iBarShift(m_symbol, m_timeframe, m_lastInvalidationTime);
         if (barsSinceInvalidation < m_invalidationCooldownBars)
         {
            DebugRegimeLogFile("ShouldCreateNewRange",
                               StringFormat("Instance #%d | Still in cooldown: %d/%d bars",
                                            m_instanceId, barsSinceInvalidation, m_invalidationCooldownBars));
            return false;
         }
      }

      // 2. Market must be clearly ranging (not trending) - USE CACHED ADX
      if (m_cache.adx >= m_adxTrendingThreshold)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | ADX too high for new range: %.1f (>=%.1f)",
                                         m_instanceId, m_cache.adx, m_adxTrendingThreshold));
         return false;
      }

      // 3. Price should be near MA50 (consolidating)
      if (m_cache.ma50 <= 0)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Invalid MA50 value", m_instanceId));
         return false;
      }

      if (m_cache.priceVsMAPercent > m_priceTooFarForRange)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Price too far from MA50: %.2f%% (>%.1f%%)",
                                         m_instanceId, m_cache.priceVsMAPercent, m_priceTooFarForRange));
         return false;
      }

      // 4. ✅ CRITICAL FIX: Relax volatility threshold from 0.5 to 0.7
      if (m_cache.volatilityScore > 0.7) // CHANGED FROM 0.5 to 0.7
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Volatility too high: %.2f (>0.7)",
                                         m_instanceId, m_cache.volatilityScore));
         return false;
      }

      // 5. Look for price compression (last 5 bars)
      double high = iHigh(m_symbol, m_timeframe, 0);
      double low = iLow(m_symbol, m_timeframe, 0);

      for (int i = 1; i < 5; i++)
      {
         high = MathMax(high, iHigh(m_symbol, m_timeframe, i));
         low = MathMin(low, iLow(m_symbol, m_timeframe, i));
      }

      double rangeHeight = high - low;
      double avgPrice = (high + low) / 2;

      if (avgPrice <= 0)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Invalid average price", m_instanceId));
         return false;
      }

      double rangePercent = (rangeHeight / avgPrice) * 100;

      if (rangePercent > 0.5) // Range too wide
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Range too wide: %.2f%% (>0.5%%)",
                                         m_instanceId, rangePercent));
         return false;
      }

      // 6. Wait for price to stabilize after movement
      double priceChange5 = GetPriceChange(5);
      if (MathAbs(priceChange5) > 0.8) // Price moved more than 0.8% in 5 bars
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("Instance #%d | Price still moving: %.2f%% change in 5 bars",
                                         m_instanceId, priceChange5));
         return false;
      }

      DebugRegimeLogFile("ShouldCreateNewRange",
                         StringFormat("Instance #%d | All conditions met for new range creation", m_instanceId));
      return true;
   }

   //+------------------------------------------------------------------+
   //| STATE DETECTION LOGIC - NO UNKNOWN STATES                        |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE DetectCurrentState()
   {
      DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | === STARTING STATE DETECTION ===", m_instanceId));

      // ==================== STEP 1: DEBUG INITIAL STATE ====================
      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Instance #%d | INITIAL: m_rangeActive=%s, cache.rangeActive=%s, cache.priceInRange=%s",
                                      m_instanceId,
                                      m_rangeActive ? "true" : "false",
                                      m_cache.rangeActive ? "true" : "false",
                                      m_cache.priceInRange ? "true" : "false"));

      // ==================== STEP 2: CALCULATE & VALIDATE INDICATORS ====================
      m_cache.Calculate(this);
      CheckAndReinitializeRange();

      // ==================== STEP 3: FIX - SYNCHRONIZE CACHE WITH REALITY ====================
      // CRITICAL: Ensure cache matches actual range state after potential invalidation
      if (m_cache.rangeActive != m_rangeActive)
      {
         DebugRegimeWarning("DetectCurrentState",
                            StringFormat("Instance #%d | CACHE MISMATCH FIX: m_rangeActive=%s, cache.rangeActive=%s",
                                         m_instanceId, m_rangeActive ? "true" : "false", m_cache.rangeActive ? "true" : "false"));
         m_cache.rangeActive = m_rangeActive;
         m_cache.priceInRange = m_rangeActive && IsPriceInFixedRange(m_cache.currentPrice);
      }

      // ==================== STEP 4: FIX - CLEAR RANGE EVIDENCE DEFINITION ====================
      // CRITICAL FIX: Range evidence ONLY exists when:
      // 1. Range is ACTIVE (m_rangeActive = true)
      // 2. Price is INSIDE range (m_cache.priceInRange = true)
      bool hasActiveRange = (m_rangeActive && m_cache.priceInRange);

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Instance #%d | [RangeEvidence] hasActiveRange=%s (m_rangeActive=%s, priceInRange=%s)",
                                      m_instanceId,
                                      hasActiveRange ? "true" : "false",
                                      m_rangeActive ? "true" : "false",
                                      m_cache.priceInRange ? "true" : "false"));

      // ==================== STEP 5: GET CACHED VALUES ====================
      double adx = m_cache.adx;
      double atr = m_cache.atr;
      double priceChange = m_cache.priceChange8;
      double rangeTouches = m_cache.rangeTouches;
      double ma50 = m_cache.ma50;
      double currentPrice = m_cache.currentPrice;
      double priceVsMA = m_cache.priceVsMAPercent;
      double maSlope = m_cache.maSlope;
      double volatilityScore = m_cache.volatilityScore;

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Instance #%d | Indicators: ADX=%.1f, ATR=%.5f, PriceVsMA=%.2f%%, RangeTouches=%d",
                                      m_instanceId, adx, atr, priceVsMA, rangeTouches));

      // ==================== STEP 6: FIX - PRICE STRUCTURE ANALYSIS ====================
      bool isTrendingStructure = IsTrendingStructure(); // HH/HL or LH/LL patterns
      // FIX: isRangingStructure should only be true if we have an ACTIVE range
      bool isRangingStructure = hasActiveRange; // Simplified: Range exists AND price is inside

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Instance #%d | Structure: Trending=%s, Ranging=%s",
                                      m_instanceId,
                                      isTrendingStructure ? "true" : "false",
                                      isRangingStructure ? "true" : "false"));

      // ==================== STEP 7: FIX - RANGE VALIDITY CHECK ====================
      if (hasActiveRange && rangeTouches < m_rangeTouchesWeak)
      {
         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Instance #%d | Range weak: only %d touches (need %d)",
                                         m_instanceId, rangeTouches, m_rangeTouchesWeak));
         return STATE_EXPANSION; // Weak range suggests breakout
      }

      // ==================== STEP 8: CLEAR CASE DETECTION ====================
      bool volatilityLow = volatilityScore < m_volatilityLow;
      bool volatilityHigh = volatilityScore > m_volatilityHigh;
      bool volatilityRising = IsVolatilityRising();

      // 1. Contraction/Squeeze
      if (volatilityLow && !volatilityRising && adx < m_adxContraction && rangeTouches < m_rangeTouchesWeak)
      {
         DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | Clear case: STATE_CONTRACTION", m_instanceId));
         return ApplyHysteresis(STATE_CONTRACTION);
      }

      // 2. Expansion/Breakout
      if (HasRangeBroken(currentPrice) && MathAbs(priceChange) > atr * 2)
      {
         DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | Clear case: STATE_EXPANSION", m_instanceId));
         return ApplyHysteresis(STATE_EXPANSION);
      }

      // 3. Churn/Exhaustion
      if (volatilityHigh && volatilityRising && adx > m_adxExhaustion && MathAbs(priceChange) < atr * 0.5)
      {
         DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | Clear case: STATE_CHURN", m_instanceId));
         return ApplyHysteresis(STATE_CHURN);
      }

      // ==================== STEP 9: FIX - MA50 OVERRIDE LOGIC ====================
      // CRITICAL FIX: When price is trending away from MA50, override range
      // CHANGED: Lowered threshold from m_priceFarFromMA (1.0%) to 0.5%
      if (isTrendingStructure && MathAbs(priceVsMA) > 0.5)
      {
         // Check MA alignment
         bool maAlignedBullish = (currentPrice > ma50 && maSlope > 0);
         bool maAlignedBearish = (currentPrice < ma50 && maSlope < 0);

         if ((maAlignedBullish || maAlignedBearish) && MathAbs(maSlope) > 0.0001)
         {
            // Strong trend away from MA - override range
            if (hasActiveRange)
            {
               DebugRegimeLogFile("DetectCurrentState",
                                  StringFormat("Instance #%d | MA50 TREND OVERRIDE: Price %.2f%% from MA50 with slope %.5f",
                                               m_instanceId, priceVsMA, maSlope));
            }

            // Return trending state based on volatility
            ENUM_MARKET_STATE trendState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
            return ApplyHysteresis(trendState);
         }
      }

      // ==================== STEP 10: FIXED DECISION LOGIC ====================
      // Simple scoring based on your existing logic
      double trendScore = 0;
      double rangeScore = 0;

      // TREND FACTORS (MORE CONSERVATIVE)
      if (adx >= 30)
         trendScore += 0.5; // Strong trend
      else if (adx >= 25)
         trendScore += 0.3; // Moderate trend
      else if (adx >= 20)
         trendScore += 0.1; // Weak trend (barely counts)

      if (isTrendingStructure)
         trendScore += 0.3;

      // PriceVsMA: Only count if STRONGLY away from MA50
      if (MathAbs(priceVsMA) > 1.0)
         trendScore += 0.3; // Very far
      else if (MathAbs(priceVsMA) > 0.7)
         trendScore += 0.2; // Far
      else if (MathAbs(priceVsMA) > 0.5)
         trendScore += 0.1; // Somewhat far

      // RANGE FACTORS (WITH ADX CONTEXT)
      if (hasActiveRange)
      {
         // Range strength DEPENDS on ADX level
         if (adx < 15)
            rangeScore += 0.7; // Strong range (low ADX)
         else if (adx < 20)
            rangeScore += 0.5; // Moderate range
         else if (adx < 25)
            rangeScore += 0.3; // Weak range (ADX rising)
         else
            rangeScore += 0.1; // Very weak (ADX ≥ 25)
      }

      if (rangeTouches >= m_rangeTouchesStrong)
         rangeScore += 0.3;

      // MA50 PROXIMITY - HEAVILY WEIGHTED for range
      if (MathAbs(priceVsMA) < 0.25)
         rangeScore += 0.4; // Very close
      else if (MathAbs(priceVsMA) < 0.5)
         rangeScore += 0.2;
      else if (MathAbs(priceVsMA) < 1.0)
         rangeScore += 0.1;

      // EXTRA: Pullback to MA50 detection
      if (IsPricePulledBackToMA50())
         rangeScore += 0.3;

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Instance #%d | Fixed Scores: Trend=%.2f, Range=%.2f",
                                      m_instanceId, trendScore, rangeScore));

      // Clear Trend case - CHANGED: Lowered threshold from 0.7 to 0.6
      if (trendScore >= 0.6 && rangeScore <= 0.4)
      {
         DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | Clear trend detected", m_instanceId));
         ENUM_MARKET_STATE trendState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
         return ApplyHysteresis(trendState);
      }

      // Clear Range case
      if (rangeScore >= 0.7 && trendScore <= 0.3)
      {
         DebugRegimeLogFile("DetectCurrentState", StringFormat("Instance #%d | Clear range detected", m_instanceId));
         ENUM_MARKET_STATE rangeState = (volatilityHigh) ? STATE_RANGING_HIGH_VOL : STATE_RANGING_LOW_VOL;
         return ApplyHysteresis(rangeState);
      }

      // ==================== STEP 11: CONFLICT RESOLUTION ====================
      // Both signals exist (ambiguous case)
      if (trendScore > 0.5 && rangeScore > 0.5)
      {
         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Instance #%d | CONFLICT DETECTED: Trend=%.2f, Range=%.2f",
                                         m_instanceId, trendScore, rangeScore));

         // RULE 1: ADX > 25 favors trend
         if (adx >= 25)
         {
            DebugRegimeLogFile("DetectCurrentState",
                               StringFormat("Instance #%d | Conflict resolved by ADX (%.1f) - TREND wins",
                                            m_instanceId, adx));
            ENUM_MARKET_STATE trendState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
            return ApplyHysteresis(trendState);
         }

         // RULE 2: Strong MA separation favors trend - CHANGED: Lowered from 1.0% to 0.5%
         if (MathAbs(priceVsMA) > 0.5 && isTrendingStructure)
         {
            DebugRegimeLogFile("DetectCurrentState",
                               StringFormat("Instance #%d | Conflict resolved by PriceVsMA (%.2f%%) - TREND wins",
                                            m_instanceId, priceVsMA));
            ENUM_MARKET_STATE trendState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
            return ApplyHysteresis(trendState);
         }

         // RULE 3: Default to trend if structure is trending
         if (isTrendingStructure)
         {
            DebugRegimeLogFile("DetectCurrentState",
                               StringFormat("Instance #%d | Conflict resolved by trending structure - TREND wins",
                                            m_instanceId));
            ENUM_MARKET_STATE trendState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
            return ApplyHysteresis(trendState);
         }

         // RULE 4: Otherwise, range wins
         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Instance #%d | Conflict resolved: RANGE wins by default",
                                         m_instanceId));
         ENUM_MARKET_STATE rangeState = (volatilityHigh) ? STATE_RANGING_HIGH_VOL : STATE_RANGING_LOW_VOL;
         return ApplyHysteresis(rangeState);
      }

      // ==================== STEP 12: FINAL DECISION ====================
      // If we reach here, choose based on which score is higher
      ENUM_MARKET_STATE finalState;

      if (trendScore > rangeScore)
      {
         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Instance #%d | Trend wins (%.2f vs %.2f)",
                                         m_instanceId, trendScore, rangeScore));
         finalState = (volatilityHigh) ? STATE_TRENDING_HIGH_VOL : STATE_TRENDING_LOW_VOL;
      }
      else
      {
         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Instance #%d | Range wins (%.2f vs %.2f)",
                                         m_instanceId, rangeScore, trendScore));
         finalState = (volatilityHigh) ? STATE_RANGING_HIGH_VOL : STATE_RANGING_LOW_VOL;
      }

      return ApplyHysteresis(finalState);
   }

   //+------------------------------------------------------------------+
   //| CHECK AND INVALIDATE RANGE METHOD - WITH ENHANCED DEBUGGING     |
   //+------------------------------------------------------------------+
   void CheckAndInvalidateRange()
   {
      DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | === STARTING RANGE INVALIDATION ===", m_instanceId));

      if (!m_cache.rangeActive)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | Range not active, skipping", m_instanceId));
         return;
      }

      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | Checking: Price=%.5f, Range=%.5f-%.5f, Width=%.5f",
                                      m_instanceId, m_cache.currentPrice, m_fixedRangeBottom, m_fixedRangeTop,
                                      m_fixedRangeTop - m_fixedRangeBottom));

      double currentPrice = m_cache.currentPrice;

      // ========== RULE 1: Consecutive closes outside range ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 1: Consecutive closes outside range", m_instanceId));
      int consecutiveOutside = 0;
      string barStatus = "";
      for (int i = 0; i < 3; i++)
      {
         double price = iClose(m_symbol, m_timeframe, i);
         bool inRange = IsPriceInFixedRange(price);
         barStatus += StringFormat("Bar %d: %.5f %s | ", i, price, inRange ? "IN RANGE" : "OUTSIDE");
         if (!inRange)
            consecutiveOutside++;
         else
            break;
      }

      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | Bar status: %s", m_instanceId, barStatus));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | Consecutive outside: %d/2 needed", m_instanceId, consecutiveOutside));

      if (consecutiveOutside >= 2)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 1 TRIGGERED: 2+ consecutive closes outside range", m_instanceId));
         InvalidateRange("2+ consecutive closes outside range");
         return;
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 1 NOT MET: Need 2 consecutive outside", m_instanceId));
      }

      // ========== RULE 2: Strong momentum break with ATR expansion ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 2: Strong momentum breakout", m_instanceId));
      double atr = m_cache.atr;
      double atr_5 = GetATRValue(14, 5);
      double priceChange = GetPriceChange(3);
      bool hasBroken = HasRangeBroken(currentPrice);
      bool atrExpanded = atr > atr_5 * 1.2;
      bool strongMomentum = MathAbs(priceChange) > atr * 1.5;

      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | HasRangeBroken: %s (Current: %.5f, Top+Buf: %.5f, Bot-Buf: %.5f)",
                                      m_instanceId, hasBroken ? "YES" : "NO",
                                      currentPrice,
                                      m_fixedRangeTop + (atr * 0.5),
                                      m_fixedRangeBottom - (atr * 0.5)));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | ATR Expansion: %.5f > %.5f*1.2 = %.5f? %s",
                                      m_instanceId, atr, atr_5, atr_5 * 1.2, atrExpanded ? "YES" : "NO"));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Instance #%d | Momentum: |%.2f%%| > %.5f*1.5 = %.5f? %s",
                                      m_instanceId, priceChange, atr, atr * 1.5, strongMomentum ? "YES" : "NO"));

      bool strongBreakout = hasBroken && atrExpanded && strongMomentum;

      if (strongBreakout)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | RULE 2 TRIGGERED: Strong momentum breakout with ATR expansion", m_instanceId));
         InvalidateRange("Strong momentum breakout with ATR expansion");
         return;
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | RULE 2 NOT MET: hasBroken=%s, ATRexp=%s, Momentum=%s",
                                         m_instanceId, hasBroken ? "YES" : "NO",
                                         atrExpanded ? "YES" : "NO",
                                         strongMomentum ? "YES" : "NO"));
      }

      // ========== RULE 3: MA confirms trend (not range) ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 3: MA confirms trend", m_instanceId));
      double ma50 = m_cache.ma50;
      double adx = m_cache.adx;

      if (ma50 > 0)
      {
         double priceDistance = m_cache.priceVsMAAbsolute;
         bool awayFromMA50 = priceDistance > atr;
         double prevMA50 = GetMAValue(50, 1);
         double prevPrice = iClose(m_symbol, m_timeframe, 1);
         bool prevAwayFromMA50 = (prevMA50 > 0) ? MathAbs(prevPrice - prevMA50) > (atr * 0.8) : false;

         bool bullishTrend = (currentPrice > ma50) && awayFromMA50;
         bool bearishTrend = (currentPrice < ma50) && awayFromMA50;
         bool adxConfirms = adx >= m_adxTrendConfirmation;

         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | MA50: %.5f, Current: %.5f, Distance: %.5f (%.2f%%)",
                                         m_instanceId, ma50, currentPrice, priceDistance, (priceDistance / ma50 * 100)));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | AwayFromMA50: %.5f > %.5f? %s",
                                         m_instanceId, priceDistance, atr, awayFromMA50 ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | PrevAwayFromMA50: %.5f > %.5f? %s",
                                         m_instanceId, MathAbs(prevPrice - prevMA50), atr * 0.8, prevAwayFromMA50 ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | Trend: Bullish=%s, Bearish=%s",
                                         m_instanceId, bullishTrend ? "YES" : "NO", bearishTrend ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Instance #%d | ADX Confirmation: %.1f >= %.1f? %s",
                                         m_instanceId, adx, m_adxTrendConfirmation, adxConfirms ? "YES" : "NO"));

         if ((bullishTrend || bearishTrend) && awayFromMA50 && prevAwayFromMA50 && adxConfirms)
         {
            string trendType = bullishTrend ? "bullish" : "bearish";
            string message = StringFormat("Price %s away from MA50 (Distance: %.2f%%, ATR: %.5f)",
                                          trendType, (priceDistance / ma50 * 100), atr);
            DebugRegimeLogFile("CheckAndInvalidateRange",
                               StringFormat("Instance #%d | RULE 3 TRIGGERED: %s", m_instanceId, message));
            InvalidateRange(message);
            return;
         }
         else
         {
            DebugRegimeLogFile("CheckAndInvalidateRange",
                               StringFormat("Instance #%d | RULE 3 NOT MET: One or more conditions failed", m_instanceId));
         }
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | RULE 3 SKIPPED: Invalid MA50 value", m_instanceId));
      }

      DebugRegimeLogFile("CheckAndInvalidateRange", StringFormat("Instance #%d | ALL INVALIDATION CHECKS PASSED - Range remains active", m_instanceId));
   }

   //+------------------------------------------------------------------+
   //| INVALIDATE RANGE HELPER - WITH CRITICAL CACHE SYNC              |
   //+------------------------------------------------------------------+
   void InvalidateRange(string reason)
   {
      DebugRegimeLogFile("InvalidateRange", StringFormat("Instance #%d | === STARTING RANGE INVALIDATION ===", m_instanceId));

      // CRITICAL DEBUG: Log before state changes
      DebugRegimeLogFile("InvalidateRange",
                         StringFormat("Instance #%d | BEFORE: m_rangeActive=%s, cache.rangeActive=%s, cache.priceInRange=%s",
                                      m_instanceId, m_rangeActive ? "true" : "false",
                                      m_cache.rangeActive ? "true" : "false",
                                      m_cache.priceInRange ? "true" : "false"));

      m_rangeActive = false;

      // CRITICAL: Update cache immediately
      m_cache.rangeActive = false;
      m_cache.priceInRange = false;

      // CRITICAL DEBUG: Log after state changes
      DebugRegimeLogFile("InvalidateRange",
                         StringFormat("Instance #%d | AFTER: m_rangeActive=%s, cache.rangeActive=%s, cache.priceInRange=%s",
                                      m_instanceId, m_rangeActive ? "true" : "false",
                                      m_cache.rangeActive ? "true" : "false",
                                      m_cache.priceInRange ? "true" : "false"));

      m_lastInvalidationTime = iTime(m_symbol, m_timeframe, 0);

      string invalidationMsg = StringFormat("Instance #%d | Range Invalidated: %s (Cooldown: %d bars)",
                                            m_instanceId, reason, m_invalidationCooldownBars);

      // Log using debug wrapper
      DebugRegimePrint("RangeInvalidation", invalidationMsg);

      // Log trade event for range invalidation
      if (DEBUG_REGIME_ENABLED)
      {
         DebugRegimeLogFile("Range",
                            StringFormat("Instance #%d | Range invalidated: %s | Price: %.5f",
                                         m_instanceId, reason, iClose(m_symbol, m_timeframe, 0)));
      }
   }

   bool IsPriceInFixedRange(double price)
   {
      if (!m_rangeActive)
         return false;
      return price >= m_fixedRangeBottom && price <= m_fixedRangeTop;
   }

   //+------------------------------------------------------------------+
   //| MODIFIED HasRangeBroken()                                        |
   //+------------------------------------------------------------------+
   bool HasRangeBroken(double price)
   {
      if (!m_rangeActive)
      {
         DebugRegimeLogFile("HasRangeBroken", StringFormat("Instance #%d | Range not active, cannot be broken", m_instanceId));
         return false;
      }

      double atr = m_cache.atr;
      double margin = atr * Inp_Breakout_Margin_Multiplier;
      double upperBreakLevel = m_fixedRangeTop + margin;
      double lowerBreakLevel = m_fixedRangeBottom - margin;

      bool brokenAbove = price > upperBreakLevel;
      bool brokenBelow = price < lowerBreakLevel;
      bool broken = brokenAbove || brokenBelow;

      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Instance #%d | Price: %.5f, Range: %.5f-%.5f, Margin: %.5f, Upper: %.5f, Lower: %.5f",
                                      m_instanceId, price, m_fixedRangeBottom, m_fixedRangeTop, margin,
                                      upperBreakLevel, lowerBreakLevel));
      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Instance #%d | Broken Above: %.5f > %.5f? %s",
                                      m_instanceId, price, upperBreakLevel, brokenAbove ? "YES" : "NO"));
      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Instance #%d | Broken Below: %.5f < %.5f? %s",
                                      m_instanceId, price, lowerBreakLevel, brokenBelow ? "YES" : "NO"));

      return broken;
   }

   string GetPositionSizeString(ENUM_POSITION_SIZE size)
   {
      switch (size)
      {
      case SIZE_ZERO:
         return "ZERO";
      case SIZE_VERY_SMALL:
         return "VERY_SMALL";
      case SIZE_SMALL:
         return "SMALL";
      case SIZE_MEDIUM:
         return "MEDIUM";
      case SIZE_LARGE:
         return "LARGE";
      default:
         return "UNKNOWN";
      }
   }

   double GetMAValue(int period, int shift = 0)
   {
      DebugRegimeLogFile("GetMAValue", StringFormat("Requested: MA%d shift %d", period, shift));

      // ✅ Check for valid singleton pointer
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         // Use IndicatorManager for MA values
         double ma9, ma21, ma50, ma89;
         bool success = m_indicatorManager.GetMAValuesForRange(m_timeframe, ma9, ma21, ma50, ma89, shift);

         DebugRegimeLogFile("GetMAValue", StringFormat("IndicatorManager success: %s, MA50: %.5f", success ? "true" : "false", ma50));

         if (success && period == 50)
         {
            return ma50;
         }
         if (success && period == 89)
         {
            return ma89;
         }
      }
      else
      {
         DebugRegimeLogFile("GetMAValue", "IndicatorManager not available, using fallback");
      }

      // Fallback to direct MA calculation
      int handle = iMA(m_symbol, m_timeframe, period, 0, MODE_SMA, PRICE_CLOSE);

      if (handle == INVALID_HANDLE)
      {
         DebugRegimeError("GetMAValue", "INVALID HANDLE!");
         return 0;
      }

      double values[];
      ArraySetAsSeries(values, true);

      int copied = CopyBuffer(handle, 0, shift, 1, values);
      DebugRegimeLogFile("GetMAValue", StringFormat("Copied: %d bars, value[0] = %.5f", copied, values[0]));

      IndicatorRelease(handle);

      return values[0];
   }

   bool IsMATrendAligned()
   {
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         // Use IndicatorManager for MA values
         double ma9, ma21, ma50, ma89;
         if (m_indicatorManager.GetMAValuesForRange(m_timeframe, ma9, ma21, ma50, ma89, 0))
         {
            double ma50_10 = GetMAValue(50, 8);
            double ma89_10 = GetMAValue(89, 8);

            if (ma50 <= 0 || ma89 <= 0)
               return false;

            // Calculate separation percentage
            double separation = MathAbs(ma50 - ma89) / ((ma50 + ma89) / 2) * 100;

            // Check alignment and slope
            bool maAlignedBullish = (ma50 > ma89) && (ma50_10 > ma89_10);
            bool maAlignedBearish = (ma50 < ma89) && (ma50_10 < ma89_10);
            bool maSlopeBullish = (ma50 > ma50_10);
            bool maSlopeBearish = (ma50 < ma50_10);

            // Significant separation with same slope = strong trend
            if (separation > 0.5) // 0.5% separation threshold
            {
               if ((maAlignedBullish && maSlopeBullish) ||
                   (maAlignedBearish && maSlopeBearish))
               {
                  DebugRegimeLogFile("IsMATrendAligned", StringFormat("Instance #%d | MA trend alignment confirmed", m_instanceId));
                  return true;
               }
            }
         }
      }

      return false;
   }

   ENUM_ROOT_REGIME GetRootState(ENUM_MARKET_STATE state)
   {
      ENUM_ROOT_REGIME rootState;

      switch (state)
      {
      case STATE_TRENDING_LOW_VOL:
      case STATE_TRENDING_HIGH_VOL:
      case STATE_EXPANSION: // Expansion is treated as trend-like
         rootState = REGIME_TRENDING;
         break;

      case STATE_RANGING_LOW_VOL:
      case STATE_RANGING_HIGH_VOL:
      case STATE_CONTRACTION: // Contraction is treated as range-like
      case STATE_CHURN:       // Churn is treated as range-like
         rootState = REGIME_RANGING;
         break;

      default:
      {
         // Safety fallback - if we get here, classify based on ADX
         double adx = m_cache.adx;
         if (adx >= m_adxTrendingThreshold)
            rootState = REGIME_TRENDING;
         else
            rootState = REGIME_RANGING;
         break;
      }
      }

      DebugRegimeLogFile("GetRootState",
                         StringFormat("Instance #%d | Root state for %s: %s",
                                      m_instanceId, MarketAnalysis::GetStateString(state),
                                      rootState == REGIME_TRENDING ? "TRENDING" : "RANGING"));

      return rootState;
   }

   //+------------------------------------------------------------------+
   //| INDICATOR CALCULATIONS (using IndicatorManager when available)  |
   //+------------------------------------------------------------------+
   double GetADX(int period)
   {
      DebugRegimeLogFile("GetADX", StringFormat("Getting ADX (period=%d)", period));

      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         double adx, plus_di, minus_di;
         bool success = m_indicatorManager.GetADXValues(m_timeframe, adx, plus_di, minus_di);
         DebugRegimeLogFile("GetADX", StringFormat("IndicatorManager ADX: success=%s, value=%.1f", success ? "true" : "false", adx));

         if (success)
         {
            return adx;
         }
      }

      // Fallback
      int handle = iADX(m_symbol, m_timeframe, period);
      if (handle == INVALID_HANDLE)
      {
         DebugRegimeError("GetADX", "ADX handle invalid!");
         return 0;
      }

      double adx_val[];
      ArraySetAsSeries(adx_val, true);
      int copied = CopyBuffer(handle, 0, 0, 1, adx_val);
      DebugRegimeLogFile("GetADX", StringFormat("Copied: %d, ADX value: %.1f", copied, adx_val[0]));

      IndicatorRelease(handle);
      return adx_val[0];
   }

   double GetATR(int period)
   {
      // ✅ Check for valid singleton pointer
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         return m_indicatorManager.GetATR(m_timeframe);
      }

      // Fallback to direct calculation
      int handle = iATR(m_symbol, m_timeframe, period);
      if (handle == INVALID_HANDLE)
         return 0;

      double atr[];
      ArraySetAsSeries(atr, true);

      if (CopyBuffer(handle, 0, 0, 1, atr) > 0)
      {
         IndicatorRelease(handle);
         return atr[0];
      }

      IndicatorRelease(handle);
      return 0;
   }

   double GetBollingerWidth(int period, double deviations)
   {
      // ✅ First check IndicatorManager
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         double upper, middle, lower;
         if (m_indicatorManager.GetBollingerBandsValues(m_timeframe, upper, middle, lower))
         {
            // CRITICAL: Calculate width as PERCENTAGE
            if (middle > 0)
            {
               double width = ((upper - lower) / middle) * 100.0;
               DebugRegimeLogFile("GetBollingerWidth",
                                  StringFormat("Upper=%.5f, Lower=%.5f, Middle=%.5f, Width=%.3f%%",
                                               upper, lower, middle, width));
               return width;
            }
         }
      }

      // Fallback to direct calculation
      int handle = iBands(m_symbol, m_timeframe, period, 0, deviations, PRICE_CLOSE);

      if (handle == INVALID_HANDLE)
      {
         DebugRegimeError("GetBollingerWidth", "BBands handle invalid");
         return 0.5; // Default moderate width
      }

      double upper[], middle[], lower[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(middle, true);
      ArraySetAsSeries(lower, true);

      // Copy 2 bars for safety
      if (CopyBuffer(handle, 1, 0, 2, upper) <= 0 ||
          CopyBuffer(handle, 0, 0, 2, middle) <= 0 ||
          CopyBuffer(handle, 2, 0, 2, lower) <= 0)
      {
         IndicatorRelease(handle);
         DebugRegimeError("GetBollingerWidth", "Failed to copy BBands buffers");
         return 0.5;
      }

      double width = 0;
      if (middle[0] > 0)
      {
         width = ((upper[0] - lower[0]) / middle[0]) * 100.0;
         DebugRegimeLogFile("GetBollingerWidth",
                            StringFormat("Direct: Upper=%.5f, Lower=%.5f, Middle=%.5f, Width=%.3f%%",
                                         upper[0], lower[0], middle[0], width));
      }

      IndicatorRelease(handle);
      return width;
   }

   double GetPriceChange(int bars)
   {
      double current = iClose(m_symbol, m_timeframe, 0);
      double past = iClose(m_symbol, m_timeframe, bars);

      if (past > 0)
         return ((current - past) / past) * 100;

      return 0;
   }

   int CountRangeTouches()
   {
      if (!m_rangeActive)
         return 0;

      int touches = 0;
      double atr = m_cache.atr; // Use cached ATR
      double tolerance = atr * 0.1;

      for (int i = 0; i < 20; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         double low = iLow(m_symbol, m_timeframe, i);

         if (MathAbs(high - m_fixedRangeTop) < tolerance ||
             MathAbs(low - m_fixedRangeBottom) < tolerance)
         {
            touches++;
         }
      }

      DebugRegimeLogFile("CountRangeTouches", StringFormat("Instance #%d | Range touches: %d", m_instanceId, touches));
      return touches;
   }

   // In CalculateVolatilityScore() function:
   double CalculateVolatilityScore(double atr, double bbWidth)
   {
      // 1. Convert ATR to percentage of current price
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double atrPercent = (atr / currentPrice) * 100.0;

      // 2. BB Width is already a percentage (e.g., 0.5 for 0.5%)
      double bbPercent = bbWidth;

      // 3. Diagnostic print
      DebugRegimeLogFile("VolatilityCalc",
                         StringFormat("Inputs: ATR=%.5f -> %.3f%%, BB Width=%.3f%%",
                                      atr, atrPercent, bbPercent));

      // 4. Use weighted average (ATR is more reliable)
      double combinedVolatility = (atrPercent * 0.7) + (bbPercent * 0.3);

      // 5. Normalize with realistic thresholds for XAUUSD
      double volatilityScore = 0.0;

      if (combinedVolatility <= 0.1)
      { // < 0.1%: Very low
         volatilityScore = 0.1;
      }
      else if (combinedVolatility <= 0.3)
      { // 0.1-0.3%: Low
         volatilityScore = 0.3;
      }
      else if (combinedVolatility <= 0.7)
      { // 0.3-0.7%: Moderate
         volatilityScore = 0.5;
      }
      else if (combinedVolatility <= 1.2)
      { // 0.7-1.2%: High
         volatilityScore = 0.8;
      }
      else
      { // > 1.2%: Very high
         volatilityScore = 1.0;
      }

      DebugRegimeLogFile("VolatilityCalc",
                         StringFormat("Combined=%.3f%%, Score=%.3f", combinedVolatility, volatilityScore));

      return volatilityScore;
   }

   bool IsVolatilityRising()
   {
      double atrNow = m_cache.atr; // Use cached ATR
      double atrBefore = GetATRValue(14, 5);

      bool rising = atrNow > atrBefore * 1.1;
      DebugRegimeLogFile("IsVolatilityRising",
                         StringFormat("Instance #%d | ATR now=%.5f, before=%.5f, rising=%s",
                                      m_instanceId, atrNow, atrBefore, rising ? "true" : "false"));
      return rising;
   }

   double GetATRValue(int period, int shift)
   {
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         return m_indicatorManager.GetATR(m_timeframe, shift);
      }

      // Fallback to direct calculation
      int handle = iATR(m_symbol, m_timeframe, period);
      if (handle == INVALID_HANDLE)
         return 0;

      double atr[];
      ArraySetAsSeries(atr, true);

      if (CopyBuffer(handle, 0, shift, 1, atr) > 0)
      {
         IndicatorRelease(handle);
         return atr[0];
      }

      IndicatorRelease(handle);
      return 0;
   }

   bool IsTrendingStructure()
   {
      DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | Checking for trending price structure", m_instanceId));

      // ========== NEW: ADD MOVING AVERAGE CONFIRMATION ==========
      // Get MA values using IndicatorManager or direct
      double ma50 = m_cache.ma50; // Use cached MA50
      double ma50_10 = GetMAValue(50, 8);
      double ma89 = GetMAValue(89, 0);
      double ma89_10 = GetMAValue(89, 8);
      double ma200 = GetMAValue(200, 0);

      // Check if we got valid values
      if (ma50 <= 0 || ma89 <= 0 || ma200 <= 0)
      {
         DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | Invalid MA values, falling back to basic structure check", m_instanceId));
         // Fall back to original price structure logic
         return CheckBasicTrendStructure();
      }

      // Calculate MA separation percentage
      double maDistancePercent = 0;
      double avgPrice = (ma50 + ma89) / 2;
      if (avgPrice > 0)
      {
         maDistancePercent = MathAbs(ma50 - ma89) / avgPrice * 100;
      }

      // Check MA alignment
      bool maAlignedBullish = (ma50 > ma89) && (ma50_10 > ma89_10);
      bool maAlignedBearish = (ma50 < ma89) && (ma50_10 < ma89_10);

      // ========== ENHANCED PRICE STRUCTURE (more forgiving) ==========
      // Look at 8 bars instead of 5
      int lookback = m_structureLookbackBars;
      double highs[], lows[];
      ArrayResize(highs, lookback);
      ArrayResize(lows, lookback);

      for (int i = 0; i < lookback; i++)
      {
         highs[i] = iHigh(m_symbol, m_timeframe, i);
         lows[i] = iLow(m_symbol, m_timeframe, i);
      }

      // More forgiving trend detection (60% rule instead of 100%)
      int uptrendSignals = 0;
      int downtrendSignals = 0;

      for (int i = 1; i < lookback; i++)
      {
         // Check HH pattern
         if (highs[i] > highs[i - 1])
            uptrendSignals++;
         if (lows[i] > lows[i - 1])
            uptrendSignals++;

         // Check LH pattern
         if (highs[i] < highs[i - 1])
            downtrendSignals++;
         if (lows[i] < lows[i - 1])
            downtrendSignals++;
      }

      int totalChecks = (lookback - 1) * 2;
      double uptrendRatio = totalChecks > 0 ? (double)uptrendSignals / totalChecks : 0;
      double downtrendRatio = totalChecks > 0 ? (double)downtrendSignals / totalChecks : 0;

      DebugRegimeLogFile("IsTrendingStructure",
                         StringFormat("Instance #%d | Price structure: Uptrend ratio=%.2f, Downtrend ratio=%.2f",
                                      m_instanceId, uptrendRatio, downtrendRatio));

      // ========== DECISION LOGIC (BALANCED) ==========

      // CRITICAL: If MAs are significantly separated (>0.75%), GENTLE trend bias
      // Changed from 0.5% to 0.75% for more selective bias
      if (maDistancePercent > 0.6) // Increase to 0.5 - need clearer MA separation
      {
         // Strong MA separation = trend gets MODERATE priority
         // Changed from 0.4 to 0.5 threshold - need clearer trend structure
         if (maAlignedBullish && uptrendRatio > 0.45)
         {
            DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | MA aligned bullish with uptrend structure", m_instanceId));
            return true; // Need 50% confirmation (was 40%)
         }
         if (maAlignedBearish && downtrendRatio > 0.45)
         {
            DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | MA aligned bearish with downtrend structure", m_instanceId));
            return true;
         }
      }

      // Original logic - keep as primary
      if (uptrendRatio > 0.6 || downtrendRatio > 0.6) // 70% threshold
      {
         DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | Strong price structure detected", m_instanceId));
         return true;
      }

      // Additional check: If price consistently above/below key MAs
      double currentPrice = m_cache.currentPrice; // Use cached price

      // Price far from 200 MA suggests trend
      double distanceFromMA = MathAbs(currentPrice - ma200) / ma200 * 100;
      if (distanceFromMA > 1.0) // Changed from 1.0% to 1.5% - more conservative
      {
         DebugRegimeLogFile("IsTrendingStructure",
                            StringFormat("Instance #%d | Price far from MA200 (%.2f%%), forcing trend classification", m_instanceId, distanceFromMA));
         return true; // Force trend classification
      }

      DebugRegimeLogFile("IsTrendingStructure", StringFormat("Instance #%d | No trending structure detected", m_instanceId));
      return false;
   }

   bool CheckBasicTrendStructure()
   {
      DebugRegimeLogFile("CheckBasicTrendStructure", StringFormat("Instance #%d | Running basic 5-bar trend structure check", m_instanceId));

      // Your original 5-bar HH/HL or LH/LL logic
      double highs[5], lows[5];

      for (int i = 0; i < 5; i++)
      {
         highs[i] = iHigh(m_symbol, m_timeframe, i);
         lows[i] = iLow(m_symbol, m_timeframe, i);
      }

      // Check for uptrend structure
      bool uptrend = true;
      for (int i = 1; i < 5; i++)
      {
         if (highs[i] <= highs[i - 1] || lows[i] <= lows[i - 1])
         {
            uptrend = false;
            break;
         }
      }

      // Check for downtrend structure
      bool downtrend = true;
      for (int i = 1; i < 5; i++)
      {
         if (highs[i] >= highs[i - 1] || lows[i] >= lows[i - 1])
         {
            downtrend = false;
            break;
         }
      }

      bool result = uptrend || downtrend;
      DebugRegimeLogFile("CheckBasicTrendStructure",
                         StringFormat("Instance #%d | Basic trend check result: %s (Uptrend: %s, Downtrend: %s)",
                                      m_instanceId, result ? "true" : "false", uptrend ? "true" : "false", downtrend ? "true" : "false"));

      return result;
   }

   bool IsRangingStructure()
   {
      if (!m_rangeActive)
      {
         DebugRegimeLogFile("IsRangingStructure", StringFormat("Instance #%d | Range not active", m_instanceId));
         return false;
      }

      double currentPrice = m_cache.currentPrice; // Use cached price
      bool inRange = IsPriceInFixedRange(currentPrice);

      DebugRegimeLogFile("IsRangingStructure",
                         StringFormat("Instance #%d | Price %.5f in range %.5f-%.5f: %s",
                                      m_instanceId, currentPrice, m_fixedRangeBottom, m_fixedRangeTop, inRange ? "true" : "false"));

      return inRange;
   }

   double CalculateConfidence(ENUM_MARKET_STATE state)
   {
      DebugRegimeLogFile("CalculateConfidence",
                         StringFormat("Instance #%d | Calculating confidence for state: %s",
                                      m_instanceId, MarketAnalysis::GetStateString(state)));

      double adx = m_cache.adx;                  // Use cached ADX
      double atrScore = m_cache.volatilityScore; // Use cached volatility score
      double structureConfidence = 0;

      if (state == STATE_TRENDING_LOW_VOL || state == STATE_TRENDING_HIGH_VOL)
      {
         structureConfidence = IsTrendingStructure() ? 80 : 40;
      }
      else if (state == STATE_RANGING_LOW_VOL || state == STATE_RANGING_HIGH_VOL)
      {
         structureConfidence = IsRangingStructure() ? 80 : 40;
      }

      double confidence = 0;

      switch (state)
      {
      case STATE_CONTRACTION:
         confidence = (1.0 - atrScore) * 100 * 0.7 + (adx < 20 ? 30 : 0);
         break;

      case STATE_EXPANSION:
         confidence = (HasRangeBroken(m_cache.currentPrice) ? 80 : 30);
         break;

      case STATE_TRENDING_LOW_VOL:
         confidence = MathMin(100, adx * 2) * 0.6 + structureConfidence * 0.4;
         break;

      case STATE_TRENDING_HIGH_VOL:
         confidence = MathMin(100, adx) * 0.7 + structureConfidence * 0.3;
         break;

      case STATE_RANGING_LOW_VOL:
      case STATE_RANGING_HIGH_VOL:
         confidence = (m_rangeActive ? 70 : 30) + (m_cache.rangeTouches * 5); // Use cached range touches
         break;

      case STATE_CHURN:
         confidence = (atrScore > 0.7 ? 70 : 30) + (adx > 40 ? 30 : 0);
         break;
      }

      confidence = MathMin(100, MathMax(0, confidence));

      DebugRegimeLogFile("CalculateConfidence",
                         StringFormat("Instance #%d | Final confidence: %.1f%% (ADX=%.1f, ATRScore=%.2f, StructureConf=%.0f)",
                                      m_instanceId, confidence, adx, atrScore, structureConfidence));

      return confidence;
   }

   //+------------------------------------------------------------------+
   //| STATE PREDICTION                                                |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE PredictNextState(ENUM_MARKET_STATE currentState)
   {
      DebugRegimeLogFile("PredictNextState",
                         StringFormat("Instance #%d | Predicting next state from: %s",
                                      m_instanceId, MarketAnalysis::GetStateString(currentState)));

      ENUM_MARKET_STATE nextState;

      // State transition probabilities
      switch (currentState)
      {
      case STATE_RANGING_LOW_VOL:
         // Could compress further or expand into high volatility range
         nextState = STATE_CONTRACTION;
         break;

      case STATE_CONTRACTION:
         // Compression leads to expansion
         nextState = STATE_EXPANSION;
         break;

      case STATE_EXPANSION:
         // Breakout leads to trending or failed breakout leads back to range
         nextState = STATE_TRENDING_LOW_VOL;
         break;

      case STATE_TRENDING_LOW_VOL:
         // Healthy trend matures into high volatility trend
         nextState = STATE_TRENDING_HIGH_VOL;
         break;

      case STATE_TRENDING_HIGH_VOL:
         // Exhaustion leads to churn
         nextState = STATE_CHURN;
         break;

      case STATE_CHURN:
         // Churn leads to new range (high vol)
         nextState = STATE_RANGING_HIGH_VOL;
         break;

      case STATE_RANGING_HIGH_VOL:
         // High vol range stabilizes into low vol range
         nextState = STATE_RANGING_LOW_VOL;
         break;

      default:
         nextState = STATE_UNKNOWN;
      }

      DebugRegimeLogFile("PredictNextState",
                         StringFormat("Instance #%d | Predicted next state: %s",
                                      m_instanceId, MarketAnalysis::GetStateString(nextState)));

      return nextState;
   }

   //+------------------------------------------------------------------+
   //| TRADING RECOMMENDATIONS                                         |
   //+------------------------------------------------------------------+
   void GenerateRecommendations(MarketAnalysis &analysis)
   {
      DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | Generating trading recommendations", m_instanceId));

      double currentPrice = m_cache.currentPrice; // Use cached price
      double atr = m_cache.atr;                   // Use cached ATR

      // Default values
      analysis.action = "Wait for clarity";
      analysis.positionSize = SIZE_ZERO;
      analysis.stopDistance = atr * 1.5;
      analysis.takeProfitDistance = atr * 3.0;
      analysis.riskRewardRatio = 2.0;
      analysis.direction = "Neutral";

      // State-specific recommendations
      switch (analysis.state)
      {
      case STATE_RANGING_LOW_VOL:
         analysis.action = "Fade range extremes";
         analysis.positionSize = SIZE_SMALL;
         analysis.stopDistance = (m_fixedRangeTop - m_fixedRangeBottom) * 0.2;
         analysis.takeProfitDistance = (m_fixedRangeTop - m_fixedRangeBottom) * 0.6;
         analysis.riskRewardRatio = 3.0;
         analysis.direction = "Mean reversion";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | RANGING_LOW_VOL: Fade extremes, mean reversion", m_instanceId));
         break;

      case STATE_RANGING_HIGH_VOL:
         analysis.action = "Fade carefully with tight stops";
         analysis.positionSize = SIZE_VERY_SMALL;
         analysis.stopDistance = atr * 0.8;
         analysis.takeProfitDistance = atr * 1.5;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "Neutral (dangerous)";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | RANGING_HIGH_VOL: Fade carefully, tight stops", m_instanceId));
         break;

      case STATE_CONTRACTION:
         analysis.action = "Prepare for breakout - no trades";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (waiting)";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | CONTRACTION: No trades, prepare for breakout", m_instanceId));
         break;

      case STATE_EXPANSION:
         analysis.action = "Test breakout entry";
         analysis.positionSize = SIZE_MEDIUM;
         analysis.stopDistance = atr * 1.2;
         analysis.takeProfitDistance = atr * 3.6;
         analysis.riskRewardRatio = 3.0;

         if (currentPrice > m_fixedRangeTop)
         {
            analysis.direction = "Bullish breakout";
            DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | EXPANSION: Bullish breakout entry", m_instanceId));
         }
         else if (currentPrice < m_fixedRangeBottom)
         {
            analysis.direction = "Bearish breakout";
            DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | EXPANSION: Bearish breakout entry", m_instanceId));
         }
         else
         {
            analysis.direction = "Testing";
            DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | EXPANSION: Testing breakout", m_instanceId));
         }
         break;

      case STATE_TRENDING_LOW_VOL:
         analysis.action = "Add to winning positions";
         analysis.positionSize = SIZE_LARGE;
         analysis.stopDistance = atr * 2.0;
         analysis.takeProfitDistance = atr * 6.0;
         analysis.riskRewardRatio = 3.0;
         analysis.direction = IsTrendingStructure() ? "With trend" : "Neutral";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | TRENDING_LOW_VOL: Add to winning positions", m_instanceId));
         break;

      case STATE_TRENDING_HIGH_VOL:
         analysis.action = "Take partial profits";
         analysis.positionSize = SIZE_MEDIUM;
         analysis.stopDistance = atr * 1.0;
         analysis.takeProfitDistance = atr * 2.0;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "With trend (cautious)";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | TRENDING_HIGH_VOL: Take partial profits", m_instanceId));
         break;

      case STATE_CHURN:
         analysis.action = "Exit positions, wait for clarity";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (avoid)";
         DebugRegimeLogFile("GenerateRecommendations", StringFormat("Instance #%d | CHURN: Exit positions, wait for clarity", m_instanceId));
         break;
      }

      // Adjust position size based on account
      analysis.positionSize = AdjustPositionSize(analysis.positionSize);

      DebugRegimeLogFile("GenerateRecommendations",
                         StringFormat("Instance #%d | Final recommendation: %s, Position: %s, Stop: %.2f, TP: %.2f, R/R: %.1f",
                                      m_instanceId, analysis.action, GetPositionSizeString(analysis.positionSize),
                                      analysis.stopDistance, analysis.takeProfitDistance, analysis.riskRewardRatio));

      // Log trading recommendation
      if (DEBUG_REGIME_ENABLED)
      {
         string tradeSignal = "HOLD";
         if (analysis.direction == "Bullish breakout")
            tradeSignal = "BUY";
         else if (analysis.direction == "Bearish breakout")
            tradeSignal = "SELL";

         // Simple log message
         string tradeMsg = StringFormat("Instance #%d | Trade Signal: %s | Action: %s | Position Size: %s | R/R: %.1f",
                                        m_instanceId, tradeSignal,
                                        analysis.action,
                                        GetPositionSizeString(analysis.positionSize),
                                        analysis.riskRewardRatio);

         // Use debug wrapper
         DebugRegimeLogFile("Recommendation", tradeMsg);
      }

      // Convert to pips for display if needed
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if (point > 0)
      {
         analysis.stopDistance = analysis.stopDistance / point;
         analysis.takeProfitDistance = analysis.takeProfitDistance / point;
      }
   }

   ENUM_POSITION_SIZE AdjustPositionSize(ENUM_POSITION_SIZE baseSize)
   {
      // Adjust based on account size and risk
      double riskAmount = m_accountBalance * (m_accountRiskPercent / 100);

      ENUM_POSITION_SIZE adjustedSize = baseSize;

      if (riskAmount < 100) // Very small account
      {
         switch (baseSize)
         {
         case SIZE_LARGE:
            adjustedSize = SIZE_MEDIUM;
            DebugRegimeLogFile("AdjustPositionSize", StringFormat("Instance #%d | Account small: LARGE -> MEDIUM", m_instanceId));
            break;
         case SIZE_MEDIUM:
            adjustedSize = SIZE_SMALL;
            DebugRegimeLogFile("AdjustPositionSize", StringFormat("Instance #%d | Account small: MEDIUM -> SMALL", m_instanceId));
            break;
         default:
            adjustedSize = baseSize;
         }
      }

      DebugRegimeLogFile("AdjustPositionSize",
                         StringFormat("Instance #%d | Position size: %s -> %s (Account: $%.2f, Risk: $%.2f)",
                                      m_instanceId, GetPositionSizeString(baseSize),
                                      GetPositionSizeString(adjustedSize),
                                      m_accountBalance, riskAmount));

      return adjustedSize;
   }

   //+------------------------------------------------------------------+
   //| UTILITY FUNCTIONS                                               |
   //+------------------------------------------------------------------+
   double ArrayAverage(double &arr[], int count)
   {
      double sum = 0;
      int validCount = 0;

      for (int i = 0; i < count && i < ArraySize(arr); i++)
      {
         sum += arr[i];
         validCount++;
      }

      double avg = validCount > 0 ? sum / validCount : 0;
      return avg;
   }

   string GenerateDescription(MarketAnalysis &analysis)
   {
      string desc = "";

      switch (analysis.state)
      {
      case STATE_RANGING_LOW_VOL:
         desc = "Low volatility consolidation. Market is balanced, awaiting catalyst.";
         break;

      case STATE_RANGING_HIGH_VOL:
         desc = "High volatility range. Emotional swings, frequent stop hunts.";
         break;

      case STATE_CONTRACTION:
         desc = "Volatility squeeze/compression. Energy building for next move.";
         break;

      case STATE_EXPANSION:
         desc = "Breakout/expansion phase. New trend may be forming.";
         break;

      case STATE_TRENDING_LOW_VOL:
         desc = "Healthy institutional trend. Ideal trading conditions.";
         break;

      case STATE_TRENDING_HIGH_VOL:
         desc = "Parabolic/exhaustion trend. Late stage, reversal risk high.";
         break;

      case STATE_CHURN:
         desc = "Exhaustion/distribution. Directionless volatility, avoid trading.";
         break;

      default:
         desc = "Market state unclear. Wait for better signals.";
      }

      DebugRegimeLogFile("GenerateDescription", StringFormat("Instance #%d | Description: %s", m_instanceId, desc));

      return desc;
   }

public:
   //+------------------------------------------------------------------+
   //| MANUAL RANGE REINITIALIZATION                                   |
   //+------------------------------------------------------------------+
   void ResetRange()
   {
      DebugRegimeLogFile("ResetRange", StringFormat("Instance #%d | Manual range reset requested", m_instanceId));
      ReinitializeRange();
   }

   //+------------------------------------------------------------------+
   //| GET/SET RANGE CONFIGURATION                                     |
   //+------------------------------------------------------------------+
   int GetBarsSinceLastRangeInit() const { return m_barsSinceLastRangeInit; }
   int GetRangeLookbackBars() const { return m_rangeLookbackBars; }

   void SetRangeLookbackBars(int bars)
   {
      m_rangeLookbackBars = bars;
      string msg = StringFormat("Instance #%d | Range lookback bars set to: %d", m_instanceId, bars);
      DebugRegimePrint("SetRangeLookbackBars", msg);
   }

   //+------------------------------------------------------------------+
   //| GETTER METHODS                                                  |
   //+------------------------------------------------------------------+
   double GetRangeTop() const { return m_fixedRangeTop; }
   double GetRangeBottom() const { return m_fixedRangeBottom; }
   bool IsRangeActive() const { return m_rangeActive; }

   void SetAccountInfo(double balance, double riskPercent)
   {
      m_accountBalance = balance;
      m_accountRiskPercent = riskPercent;

      DebugRegimeLogFile("SetAccountInfo",
                         StringFormat("Instance #%d | Account info updated: Balance=$%.2f, Risk=%.1f%%",
                                      m_instanceId, balance, riskPercent));
   }

   // Access to IndicatorManager for other uses
   IndicatorManager *GetIndicatorManager() const { return m_indicatorManager; }

   // Method to get IndicatorManager initialization status
   bool IsIndicatorManagerInitialized() const
   {
      bool initialized = (m_indicatorManager != NULL && m_indicatorManager.IsInitialized());
      DebugRegimeLogFile("IsIndicatorManagerInitialized",
                         StringFormat("Instance #%d | IndicatorManager initialized: %s", m_instanceId, initialized ? "true" : "false"));
      return initialized;
   }

   // ==================== GETTERS FOR INPUT PARAMETERS ====================
   double GetADXTrendingThreshold() const { return m_adxTrendingThreshold; }
   double GetADXTrendConfirmation() const { return m_adxTrendConfirmation; }
   double GetADXExhaustion() const { return m_adxExhaustion; }
   double GetADXContraction() const { return m_adxContraction; }
   double GetPriceFarFromMA() const { return m_priceFarFromMA; }
   double GetPriceNearMA() const { return m_priceNearMA; }
   double GetPriceTooFarForRange() const { return m_priceTooFarForRange; }
   double GetVolatilityHigh() const { return m_volatilityHigh; }
   double GetVolatilityLow() const { return m_volatilityLow; }
   double GetVolatilityForNewRange() const { return m_volatilityForNewRange; }
   int GetRangeTouchesWeak() const { return m_rangeTouchesWeak; }
   int GetRangeTouchesStrong() const { return m_rangeTouchesStrong; }
};

// Initialize static member
int MarketRegimeDetector::m_totalInstances = 0;

void DrawHorizontalLine(long chartId, string name, double price, color clr,
                        ENUM_LINE_STYLE style, int width)
{
   if (ObjectFind(chartId, name) >= 0)
      ObjectDelete(chartId, name);

   ObjectCreate(chartId, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_STYLE, style);
   ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, true);
}

void DrawText(long chartId, string name, datetime time, double price,
              string text, color clr, int fontSize, string font)
{
   if (ObjectFind(chartId, name) >= 0)
      ObjectDelete(chartId, name);

   ObjectCreate(chartId, name, OBJ_TEXT, 0, time, price);
   ObjectSetString(chartId, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(chartId, name, OBJPROP_FONT, font);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| SIMPLIFIED: Show range ONLY when market is ranging              |
//+------------------------------------------------------------------+
void DisplayMarketRegimeOnChart(MarketAnalysis &analysis,
                                string symbol = NULL,
                                ENUM_TIMEFRAMES tf = PERIOD_M15,
                                int corner = CORNER_RIGHT_UPPER)
{
   DebugRegimeLogFile("DisplayMarketRegimeOnChart", "Updating chart display");

   if (symbol == NULL)
      symbol = Symbol();

   long chartId = ChartID();
   string prefix = "MarketRegime_";

   // Remove ALL previous drawings first
   RemoveAllRegimeDrawings(chartId, prefix);

   // ==================== CRITICAL CHECK: Only show in ranging states ====================
   bool shouldShowRange = false;

   switch (analysis.state)
   {
   case STATE_RANGING_LOW_VOL:
   case STATE_RANGING_HIGH_VOL:
   case STATE_CONTRACTION: // Contraction/squeeze is also a ranging state
      shouldShowRange = true;
      DebugRegimeLogFile("DisplayMarketRegimeOnChart", "Showing range (ranging state detected)");
      break;

   case STATE_TRENDING_LOW_VOL:
   case STATE_TRENDING_HIGH_VOL:
   case STATE_EXPANSION: // Expansion/breakout = trending
   case STATE_CHURN:     // Churn/exhaustion = unclear
   case STATE_UNKNOWN:
   default:
      shouldShowRange = false;
      DebugRegimeLogFile("DisplayMarketRegimeOnChart", "Hiding range (non-ranging state)");
   }

   // Only proceed if we should show range
   if (!shouldShowRange)
   {
      // Remove any existing drawings and exit
      ChartRedraw(chartId);
      return;
   }

   // Get singleton instance instead of creating new detector
   MarketRegimeDetector *detector = MarketRegimeDetector::Instance(symbol, tf);

   // Double-check: Is range actually active?
   if (shouldShowRange && detector != NULL)
   {
      double top = detector.GetRangeTop();
      double bottom = detector.GetRangeBottom();

      // Only draw if range is meaningful (not too narrow)
      double rangeHeight = top - bottom;
      double avgPrice = (top + bottom) / 2;

      if (avgPrice > 0 && (rangeHeight / avgPrice) * 100 > 0.05) // 0.05% minimum width
      {
         // Draw ONLY the range lines (no text, no labels)
         DrawHorizontalLine(chartId, prefix + "RangeTop", top, clrDodgerBlue, STYLE_DASH, 2);
         DrawHorizontalLine(chartId, prefix + "RangeBottom", bottom, clrDodgerBlue, STYLE_DASH, 2);

         DebugRegimeLogFile("DisplayMarketRegimeOnChart",
                            StringFormat("Range drawn: Top=%.5f, Bottom=%.5f, Height=%.2f%%",
                                         top, bottom, (rangeHeight / avgPrice) * 100));
      }
   }

   // If we get here and range shouldn't be shown, the RemoveAllRegimeDrawings
   // at the beginning already cleared any existing drawings

   ChartRedraw(chartId);
}

void RemoveAllRegimeDrawings(long chartId, string prefix = "MarketRegime_")
{
   int total = ObjectsTotal(chartId);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chartId, i);
      if (StringFind(name, prefix) == 0)
      {
         ObjectDelete(chartId, name);
      }
   }
}

//+------------------------------------------------------------------+
//| COLOR FUNCTIONS FOR VISUAL FEEDBACK                             |
//+------------------------------------------------------------------+

color GetStateColor(ENUM_MARKET_STATE state)
{
   switch (state)
   {
   case STATE_RANGING_LOW_VOL:
      return clrSteelBlue; // Blue for consolidation
   case STATE_RANGING_HIGH_VOL:
      return clrOrangeRed; // Red-orange for dangerous range
   case STATE_TRENDING_LOW_VOL:
      return clrLimeGreen; // Green for healthy trend
   case STATE_TRENDING_HIGH_VOL:
      return clrGold; // Gold/yellow for exhaustion
   case STATE_CONTRACTION:
      return clrDarkSlateGray; // Dark gray for compression
   case STATE_EXPANSION:
      return clrDodgerBlue; // Bright blue for expansion
   case STATE_CHURN:
      return clrDarkOrange; // Orange for churn
   default:
      return clrGray;
   }
}

color GetTransitionColor(ENUM_MARKET_STATE current, ENUM_MARKET_STATE next)
{
   // Color transitions based on expected move
   if ((current == STATE_CONTRACTION && next == STATE_EXPANSION) ||
       (current == STATE_EXPANSION && next == STATE_TRENDING_LOW_VOL))
      return clrLime; // Green for positive transitions

   if ((current == STATE_TRENDING_HIGH_VOL && next == STATE_CHURN) ||
       (current == STATE_CHURN && next == STATE_RANGING_HIGH_VOL))
      return clrOrangeRed; // Red for negative transitions

   return clrYellow; // Yellow for neutral transitions
}

color GetActionColor(string action)
{
   if (StringFind(action, "Fade") >= 0)
      return clrDodgerBlue; // Blue for mean reversion
   if (StringFind(action, "Add") >= 0 || StringFind(action, "Test") >= 0)
      return clrLime; // Green for trend following
   if (StringFind(action, "Take") >= 0)
      return clrGold; // Yellow for profit taking
   if (StringFind(action, "Exit") >= 0 || StringFind(action, "Wait") >= 0)
      return clrOrangeRed; // Red for exiting/avoiding

   return clrWhite;
}

color GetPositionSizeColor(ENUM_POSITION_SIZE size)
{
   switch (size)
   {
   case SIZE_ZERO:
      return clrGray;
   case SIZE_VERY_SMALL:
      return clrOrangeRed;
   case SIZE_SMALL:
      return clrOrange;
   case SIZE_MEDIUM:
      return clrYellow;
   case SIZE_LARGE:
      return clrLime;
   default:
      return clrWhite;
   }
}

color GetDirectionColor(string direction)
{
   if (StringFind(direction, "Bullish") >= 0 || StringFind(direction, "Up") >= 0)
      return clrLime;
   if (StringFind(direction, "Bearish") >= 0 || StringFind(direction, "Down") >= 0)
      return clrRed;
   if (StringFind(direction, "With trend") >= 0)
      return clrLimeGreen;
   if (StringFind(direction, "Mean reversion") >= 0)
      return clrDodgerBlue;
   if (StringFind(direction, "Neutral") >= 0)
      return clrGray;

   return clrYellow;
}

color GetRRColor(double rrRatio)
{
   if (rrRatio >= 3.0)
      return clrLime;
   if (rrRatio >= 2.0)
      return clrYellow;
   if (rrRatio > 0)
      return clrOrange;

   return clrGray;
}

color GetRangePositionColor(double positionPercent)
{
   if (positionPercent < 20)
      return clrRed; // Oversold near bottom
   if (positionPercent > 80)
      return clrLime; // Overbought near top
   if (positionPercent < 40)
      return clrOrange; // Lower half
   if (positionPercent > 60)
      return clrDodgerBlue; // Upper half

   return clrYellow; // Middle
}

//+------------------------------------------------------------------+
//| ENHANCED GLOBAL HELPER FUNCTION                                  |
//+------------------------------------------------------------------+
MarketAnalysis GetMarketRegimeWithDisplay(string symbol = NULL,
                                          ENUM_TIMEFRAMES tf = PERIOD_M15,
                                          bool showPanel = true,
                                          int panelCorner = CORNER_RIGHT_UPPER,
                                          bool useIndicatorManager = true)
{
   // ✅ Use the singleton instance
   MarketRegimeDetector *detector = MarketRegimeDetector::Instance(symbol, tf, 0, 0, useIndicatorManager);

   if (detector == NULL)
   {
      DebugRegimeError("GetMarketRegimeWithDisplay", "Failed to get MarketRegimeDetector singleton");
      MarketAnalysis errorAnalysis;
      errorAnalysis.state = STATE_UNKNOWN;
      errorAnalysis.confidence = 0;
      errorAnalysis.action = "ERROR: Detector failed";
      return errorAnalysis;
   }

   // Add instance identifier to logs
   DebugRegimeLogFile("GetMarketRegimeWithDisplay",
                      StringFormat("Using detector instance #%d for %s timeframe %d",
                                   detector.GetInstanceId(), detector.GetSymbol(), detector.GetTimeframe()));

   // Get analysis
   MarketAnalysis analysis = detector.GetMarketRegime();

   // Display on chart if requested
   if (showPanel)
   {
      DisplayMarketRegimeOnChart(analysis, symbol, tf, panelCorner);
   }

   return analysis;
}

//+------------------------------------------------------------------+
//| CLEANUP FUNCTION - Call this in OnDeinit()                       |
//+------------------------------------------------------------------+
void CleanupMarketRegimeDetector()
{
   DebugRegimePrint("Cleanup", "=== CLEANING UP MARKET REGIME DETECTOR ===");
   DebugRegimeLogFile("Cleanup", StringFormat("Total instances before cleanup: %d", MarketRegimeDetector::GetTotalInstances()));
   MarketRegimeDetector::DeleteInstance();
   DebugRegimeLogFile("Cleanup", StringFormat("Total instances after cleanup: %d", MarketRegimeDetector::GetTotalInstances()));
}
//+------------------------------------------------------------------+