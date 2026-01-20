//+------------------------------------------------------------------+
//|                                                   MarketRegime.mq5|
//|             Simplified Market Regime & Lifecycle Detection       |
//+------------------------------------------------------------------+
// Logger Integration Status: FULLY INTEGRATED
// All logging uses static Logger::Log() calls with debug wrapper
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

input group "=== Price & Moving Average Settings ===" input double Inp_Price_Far_From_MA = 1.0; // Price far from MA (%)
input double Inp_Price_Near_MA = 0.5;                                                           // Price near MA (%)
input double Inp_Price_Too_Far_For_Range = 0.8;                                                 // Price too far for range (%)

input group "=== Volatility Settings ===" input double Inp_Volatility_High = 0.7; // High volatility threshold
input double Inp_Volatility_Low = 0.3;                                            // Low volatility threshold
input double Inp_Volatility_For_New_Range = 0.5;                                  // Volatility for new range creation

input group "=== Range Settings ===" input int Inp_Range_Touches_Weak = 2; // Weak range touches (minimum)
input int Inp_Range_Touches_Strong = 3;                                    // Strong range touches
input int Inp_Range_Lookback_Bars = 10;                                    // Bars to look back for range
input int Inp_Structure_Lookback_Bars = 10;                                // Bars to look back for range
input int Inp_Invalidation_Cooldown_Bars = 8;                              // Bars to wait after range invalidation

input group "=== Account & Risk Settings ===" input double Inp_Account_Balance = 10000.0; // Account balance for position sizing
input double Inp_Account_Risk_Percent = 1.0;                                              // Risk percentage per trade

input group "=== Debug Settings ===" input bool Inp_Debug_Regime_Enabled = true; // Enable debug logging

// ====================== DEBUG SETTINGS ======================
bool DEBUG_REGIME_ENABLED = Inp_Debug_Regime_Enabled;

// Simple debug function using Logger
void DebugRegimeLogFile(string context, string message)
{
   if (DEBUG_REGIME_ENABLED)
   {
      Logger::Log("MarketRegime", StringFormat("%s: %s", context, message), true, false);
   }
}

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

         if (timestamp == iTime(detector.m_symbol, detector.m_timeframe, 0))
            return;

         timestamp = iTime(detector.m_symbol, detector.m_timeframe, 0);

         // Get all indicator values ONCE
         adx = detector.GetADX(14);
         atr = detector.GetATR(14);
         ma50 = detector.GetMAValue(50, 0);
         ma50_5 = detector.GetMAValue(50, 5);
         currentPrice = iClose(detector.m_symbol, detector.m_timeframe, 0);
         bbWidth = detector.GetBollingerWidth(20, 2);
         priceChange8 = detector.GetPriceChange(8);

         // Calculate derived values ONCE
         if (ma50 > 0)
         {
            priceVsMAPercent = MathAbs(currentPrice - ma50) / ma50 * 100;
            priceVsMAAbsolute = MathAbs(currentPrice - ma50);
            maSlope = (ma50 - ma50_5) / 5.0;
         }

         volatilityScore = detector.CalculateVolatilityScore(atr, bbWidth);
         rangeTouches = detector.CountRangeTouches();
         priceInRange = detector.IsPriceInFixedRange(currentPrice);
         rangeActive = detector.m_rangeActive;
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

public:
   MarketRegimeDetector(string symbol = NULL,
                        ENUM_TIMEFRAMES tf = PERIOD_H1,
                        double accountBalance = 0, // Will use input parameter if not provided
                        double riskPercent = 0,    // Will use input parameter if not provided
                        bool useIndicatorManager = true)
   {
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

      DebugRegimeLogFile("Constructor", StringFormat("Initializing detector for %s timeframe %d",
                                                     m_symbol, m_timeframe));
      DebugRegimeLogFile("Constructor", StringFormat("ADX Thresholds: Trending=%.1f, Confirmation=%.1f, Exhaustion=%.1f, Contraction=%.1f",
                                                     m_adxTrendingThreshold, m_adxTrendConfirmation,
                                                     m_adxExhaustion, m_adxContraction));
      DebugRegimeLogFile("Constructor", StringFormat("Price MA Thresholds: Far=%.1f%%, Near=%.1f%%, TooFar=%.1f%%",
                                                     m_priceFarFromMA, m_priceNearMA, m_priceTooFarForRange));
      DebugRegimeLogFile("Constructor", StringFormat("Volatility Thresholds: High=%.1f, Low=%.1f, NewRange=%.1f",
                                                     m_volatilityHigh, m_volatilityLow, m_volatilityForNewRange));
      DebugRegimeLogFile("Constructor", StringFormat("Range Touches: Weak=%d, Strong=%d",
                                                     m_rangeTouchesWeak, m_rangeTouchesStrong));
      DebugRegimeLogFile("Constructor", StringFormat("Account: Balance=$%.2f, Risk=%.1f%%",
                                                     m_accountBalance, m_accountRiskPercent));

      // Initialize indicator manager if requested
      if (m_useIndicatorManager)
      {
         m_indicatorManager = new IndicatorManager(m_symbol);
         if (!m_indicatorManager.Initialize())
         {
            Logger::LogError("MarketRegime", "IndicatorManager failed to initialize. Falling back to direct indicators.");
            m_useIndicatorManager = false;
         }
         else
         {
            DebugRegimeLogFile("Constructor", "IndicatorManager initialized successfully");
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

   ~MarketRegimeDetector()
   {
      DebugRegimeLogFile("Destructor", "Cleaning up MarketRegimeDetector");

      if (m_indicatorManager != NULL)
      {
         m_indicatorManager.Deinitialize();
         delete m_indicatorManager;
         DebugRegimeLogFile("Destructor", "IndicatorManager cleaned up");
      }

      Logger::Log("MarketRegime", "Detector shutdown complete", true, false);
   }

   //+------------------------------------------------------------------+
   //| MAIN PUBLIC METHOD: Get complete market analysis                |
   //+------------------------------------------------------------------+
   MarketAnalysis GetMarketRegime()
   {
      DebugRegimeLogFile("GetMarketRegime", "Starting market analysis");

      // CALCULATE EVERYTHING ONCE PER BAR
      m_cache.Calculate(this);

      MarketAnalysis analysis;

      // 1. Check if we should reinitialize existing range
      CheckAndReinitializeRange();

      // 2. Initialize fixed range if not active AND conditions are right
      if (!m_rangeActive && ShouldCreateNewRange())
      {
         InitializeFixedRange();
         m_cache.rangeActive = true; // Update cache
         m_cache.priceInRange = true;
      }

      // 3. Get current state using CACHED values
      analysis.state = DetectCurrentState();
      analysis.rootState = GetRootState(analysis.state);
      analysis.confidence = CalculateConfidence(analysis.state);

      DebugRegimeLogFile("GetMarketRegime", StringFormat("Detected state: %s with %.1f%% confidence",
                                                         MarketAnalysis::GetStateString(analysis.state), analysis.confidence));

      // 4. Determine next likely state
      analysis.nextLikelyState = PredictNextState(analysis.state);

      DebugRegimeLogFile("GetMarketRegime", StringFormat("Next likely state: %s",
                                                         MarketAnalysis::GetStateString(analysis.nextLikelyState)));

      // 5. Generate trading recommendations
      GenerateRecommendations(analysis);

      DebugRegimeLogFile("GetMarketRegime", StringFormat("Recommendation: %s (Position: %s)",
                                                         analysis.action, GetPositionSizeString(analysis.positionSize)));

      // 6. Set description
      analysis.description = GenerateDescription(analysis);

      DebugRegimeLogFile("GetMarketRegime", "Analysis complete");

      // Log final analysis summary
      Logger::Log("MarketRegime", StringFormat("ANALYSIS: %s | Confidence: %.0f%% | Action: %s | R/R: %.1f", MarketAnalysis::GetStateString(analysis.state), analysis.confidence, analysis.action, analysis.riskRewardRatio),
                  true, true);

      return analysis;
   }

private:
   void CheckAndReinitializeRange()
   {
      datetime currentTime = iTime(m_symbol, m_timeframe, 0);

      if (m_lastRangeCheckTime == currentTime)
         return;

      m_lastRangeCheckTime = currentTime;
      m_barsSinceLastRangeInit++;

      DebugRegimeLogFile("CheckAndReinitializeRange",
                         StringFormat("=== RANGE MAINTENANCE CHECK === | Bars since init: %d",
                                      m_barsSinceLastRangeInit));

      // 1. FIRST check if range should be invalidated (regardless of m_rangeActive)
      CheckAndInvalidateRange(); // ← CRITICAL MISSING LINE!

      // 2. ONLY THEN check reinitialization for ACTIVE ranges
      if (m_rangeActive && ShouldSmartReinitialize())
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", "Range needs reinitialization");
         ReinitializeRange();
      }
      else if (m_rangeActive)
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", "Range active, no reinitialization needed");
      }
      else
      {
         DebugRegimeLogFile("CheckAndReinitializeRange", "No active range (either never existed or was invalidated)");
      }
   }

   //+------------------------------------------------------------------+
   //| SMART RANGE REINITIALIZATION                                    |
   //+------------------------------------------------------------------+
   bool ShouldSmartReinitialize()
   {
      DebugRegimeLogFile("ShouldSmartReinitialize", "Checking if smart reinitialization is needed");

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
            DebugRegimeLogFile("ShouldSmartReinitialize", "Conditions met for smart reinitialization");
            return true;
         }

         // Reinitialize if market is in contraction/expansion phase
         if (state == STATE_CONTRACTION || state == STATE_EXPANSION)
         {
            DebugRegimeLogFile("ShouldSmartReinitialize", "Contraction/Expansion phase detected");
            return true;
         }
      }

      DebugRegimeLogFile("ShouldSmartReinitialize", "No need for smart reinitialization");
      return false;
   }

   void ReinitializeRange()
   {
      DebugRegimeLogFile("ReinitializeRange", "Reinitializing fixed range...");
      Logger::Log("MarketRegime", "Reinitializing fixed range", true, false);
      InitializeFixedRange();
      m_barsSinceLastRangeInit = 0;
   }

   void InitializeFixedRange()
   {
      DebugRegimeLogFile("InitializeFixedRange", "=== ATTEMPTING RANGE INITIALIZATION ===");

      // ==================== COMPREHENSIVE GUARDS ====================

      // GUARD 1: Don't initialize if range is already active
      if (m_rangeActive)
      {
         DebugRegimeLogFile("InitializeFixedRange",
                            StringFormat("❌ Range already active (Top: %.5f, Bottom: %.5f), skipping",
                                         m_fixedRangeTop, m_fixedRangeBottom));
         return;
      }

      // ==================== ACTUAL RANGE CREATION ====================
      DebugRegimeLogFile("InitializeFixedRange", "✅ All guards passed, creating new range");

      int bars = 10;
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
         m_rangeStartTime = iTime(m_symbol, m_timeframe, 0);
         m_rangeActive = true;
         m_barsSinceLastRangeInit = 0;

         string rangeInfo = StringFormat("✅ Fixed Range Initialized: %.5f - %.5f (Width: %.2f%%)",
                                         lowest, highest,
                                         ((highest - lowest) / ((highest + lowest) / 2)) * 100);

         Print(rangeInfo);
         Logger::Log("MarketRegime", rangeInfo, true, true);
         DebugRegimeLogFile("InitializeFixedRange", rangeInfo);

         // Log range details
         Logger::LogTrade("Range", m_symbol, "RANGE", 0, (highest + lowest) / 2);
      }
      else
      {
         DebugRegimeLogFile("InitializeFixedRange", "❌ Failed to initialize fixed range (highest <= lowest)");
      }
   }

   //+------------------------------------------------------------------+
   //| SHOULD CREATE NEW RANGE METHOD                                   |
   //+------------------------------------------------------------------+
   bool ShouldCreateNewRange()
   {
      DebugRegimeLogFile("ShouldCreateNewRange", "=== Checking if new range should be created ===");

      // GUARD 0: Already active? (shouldn't get here with Guard 1 above, but just in case)
      if (m_rangeActive)
      {
         DebugRegimeLogFile("ShouldCreateNewRange", "❌ Range already active");
         return false;
      }

      // 1. Check cooldown period (redundant with Guard 2, but good for clarity)
      if (m_lastInvalidationTime > 0)
      {
         int barsSinceInvalidation = iBarShift(m_symbol, m_timeframe, m_lastInvalidationTime);
         if (barsSinceInvalidation < m_invalidationCooldownBars)
         {
            DebugRegimeLogFile("ShouldCreateNewRange",
                               StringFormat("❌ Still in cooldown: %d/%d bars",
                                            barsSinceInvalidation, m_invalidationCooldownBars));
            return false; // Still in cooldown
         }
      }

      // 2. Market must be clearly ranging (not trending) - USE CACHED ADX
      if (m_cache.adx >= m_adxTrendingThreshold) // ADX >= threshold
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("❌ ADX too high for new range: %.1f (>=%.1f)",
                                         m_cache.adx, m_adxTrendingThreshold));
         return false;
      }

      // 3. Price should be near MA50 (consolidating)
      if (m_cache.ma50 <= 0)
      {
         DebugRegimeLogFile("ShouldCreateNewRange", "❌ Invalid MA50 value");
         return false;
      }

      if (m_cache.priceVsMAPercent > m_priceTooFarForRange)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("❌ Price too far from MA50: %.2f%% (>%.1f%%)",
                                         m_cache.priceVsMAPercent, m_priceTooFarForRange));
         return false;
      }

      // 4. Check for consolidation (low volatility)
      if (m_cache.volatilityScore > m_volatilityForNewRange)
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("❌ Volatility too high: %.2f (>%.1f)",
                                         m_cache.volatilityScore, m_volatilityForNewRange));
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
         DebugRegimeLogFile("ShouldCreateNewRange", "❌ Invalid average price");
         return false;
      }

      double rangePercent = (rangeHeight / avgPrice) * 100;

      if (rangePercent > 0.5) // Range too wide
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("❌ Range too wide: %.2f%% (>0.5%%)", rangePercent));
         return false;
      }

      // 6. ADDED: Wait for price to stabilize after movement
      double priceChange5 = GetPriceChange(5);
      if (MathAbs(priceChange5) > 0.8) // Price moved more than 0.8% in 5 bars
      {
         DebugRegimeLogFile("ShouldCreateNewRange",
                            StringFormat("❌ Price still moving: %.2f%% change in 5 bars", priceChange5));
         return false;
      }

      DebugRegimeLogFile("ShouldCreateNewRange", "✅ All conditions met for new range creation");
      return true;
   }

   //+------------------------------------------------------------------+
   //| STATE DETECTION LOGIC - NO UNKNOWN STATES                        |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE DetectCurrentState()
   {
      DebugRegimeLogFile("DetectCurrentState", "Starting state detection - NO UNKNOWN states");

      // Check if current range should be invalidated
      CheckAndInvalidateRange();

      // USE CACHED VALUES (already calculated)
      double adx = m_cache.adx;
      double atr = m_cache.atr;
      double bbWidth = m_cache.bbWidth;
      double priceChange = m_cache.priceChange8;
      double rangeTouches = m_cache.rangeTouches;
      double ma50 = m_cache.ma50;
      double currentPrice = m_cache.currentPrice;
      double priceVsMA = m_cache.priceVsMAPercent;
      double maSlope = m_cache.maSlope;
      double volatilityScore = m_cache.volatilityScore;

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Indicators: ADX=%.1f, ATR=%.5f, BBWidth=%.4f, PriceChange=%.2f%%, RangeTouches=%d, PriceVsMA=%.2f%%",
                                      adx, atr, bbWidth, priceChange, rangeTouches, priceVsMA));

      // Calculate biases using cached values
      double trendBias = 0;
      double rangeBias = 0;

      if (ma50 > 0)
      {
         bool priceFarFromMA = priceVsMA > m_priceFarFromMA;
         bool maHasSlope = MathAbs(maSlope) > 0.0001;
         bool priceAboveMA = currentPrice > ma50;
         bool priceBelowMA = currentPrice < ma50;

         if (priceFarFromMA && maHasSlope)
         {
            // Check if price and MA alignment suggests trend
            if ((priceAboveMA && maSlope > 0) || (priceBelowMA && maSlope < 0))
            {
               // Strong uptrend or downtrend
               trendBias = MathMin(1.0, priceVsMA / 2.0);
               trendBias = MathMax(0.3, trendBias);

               // Extra bias for very strong moves
               if (priceVsMA > 1.5 && MathAbs(maSlope) > 0.0002)
               {
                  trendBias = MathMin(1.0, trendBias + 0.2);
               }
            }
            else if ((priceAboveMA && maSlope < 0) || (priceBelowMA && maSlope > 0))
            {
               // Price is pulling back to MA - possible range or correction
               rangeBias = MathMin(1.0, 0.3 + (priceVsMA / 3.0));
            }
         }
         else if (priceVsMA < m_priceNearMA)
         {
            // Price close to MA50 suggests ranging
            rangeBias = MathMin(1.0, 0.5 - (priceVsMA * 0.8));
         }
      }

      bool volatilityLow = volatilityScore < m_volatilityLow;
      bool volatilityHigh = volatilityScore > m_volatilityHigh;
      bool volatilityRising = IsVolatilityRising();

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Volatility: Score=%.2f, Low=%s, High=%s, Rising=%s",
                                      volatilityScore, volatilityLow ? "true" : "false",
                                      volatilityHigh ? "true" : "false", volatilityRising ? "true" : "false"));

      // Price structure analysis
      bool isTrendingStructure = IsTrendingStructure();
      bool isRangingStructure = IsRangingStructure();

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Structure: Trending=%s, Ranging=%s",
                                      isTrendingStructure ? "true" : "false",
                                      isRangingStructure ? "true" : "false"));

      // State confidence check before ranging logic
      if (m_rangeActive)
      {
         // Check if range is still valid before using it
         if (rangeTouches < m_rangeTouchesWeak) // Not enough touches
         {
            // Range exists but isn't being respected
            DebugRegimeLogFile("DetectCurrentState",
                               StringFormat("Range weak: only %d touches, likely breaking out", rangeTouches));
            CheckAndInvalidateRange(); // Mark as invalid
            // Return expansion (trend-like state) instead of unknown
            DebugRegimeLogFile("DetectCurrentState", "Range weak, returning STATE_EXPANSION (trend-like)");
            Logger::Log("MarketRegime", "Market State: EXPANSION (Weak range breaking out)", true, false);
            return STATE_EXPANSION;
         }
      }

      // Decision matrix - FIRST PASS: Clear cases
      // 1. Check for Contraction/Squeeze (STATE_CONTRACTION) - treat as RANGE
      if (volatilityLow && !volatilityRising && adx < m_adxContraction && rangeTouches < m_rangeTouchesWeak)
      {
         DebugRegimeLogFile("DetectCurrentState", "Detected STATE_CONTRACTION (treat as RANGE)");
         Logger::Log("MarketRegime", "Market State: CONTRACTION (Volatility squeeze - RANGE)", true, false);
         return STATE_CONTRACTION; // Contraction is a ranging state
      }

      // 2. Check for Expansion/Breakout (STATE_EXPANSION) - treat as TREND
      if (HasRangeBroken(currentPrice) &&
          MathAbs(priceChange) > atr * 2)
      {
         DebugRegimeLogFile("DetectCurrentState", "Detected STATE_EXPANSION (treat as TREND)");
         Logger::Log("MarketRegime", "Market State: EXPANSION (Breakout detected - TREND)", true, false);
         return STATE_EXPANSION; // Expansion is a trend state
      }

      // 3. Check for Churn/Exhaustion (STATE_CHURN) - treat as RANGE
      if (volatilityHigh && volatilityRising && adx > m_adxExhaustion &&
          MathAbs(priceChange) < atr * 0.5)
      {
         DebugRegimeLogFile("DetectCurrentState", "Detected STATE_CHURN (treat as RANGE)");
         Logger::Log("MarketRegime", "Market State: CHURN (Exhaustion phase - RANGE)", true, false);
         return STATE_CHURN; // Churn is a ranging state
      }

      // ========== ADD RANGE STRENGTH CHECK ==========
      // Check if price is respecting range boundaries
      bool priceNearRangeBoundary = false;
      if (m_rangeActive)
      {
         double rangeHeight = m_fixedRangeTop - m_fixedRangeBottom;
         double pricePosition = (currentPrice - m_fixedRangeBottom) / rangeHeight;

         // Price near top or bottom (within 15% of boundary)
         if (pricePosition < 0.15 || pricePosition > 0.85)
         {
            priceNearRangeBoundary = true;
            rangeBias = MathMin(1.0, rangeBias + 0.4);
         }

         // Multiple range touches = stronger range
         if (rangeTouches >= m_rangeTouchesStrong)
         {
            rangeBias = MathMin(1.0, rangeBias + 0.3);
         }
      }

      // ========== BALANCED DECISION MAKING ==========

      // 4. Check trending states WITH BIAS CONSIDERATION
      if (isTrendingStructure)
      {
         if (adx >= m_adxTrendingThreshold) // ADX >= threshold (default 25)
         {
            // Apply trend bias from MA50 analysis
            double trendStrength = adx / 100.0; // Normalize ADX 0-1
            double finalTrendScore = trendStrength + (trendBias * 0.25) - (rangeBias * 0.35);

            // Need reasonable trend strength even with MA bias
            if (finalTrendScore > 0.45) // higher score to make harder for trend to qualify
            {
               // Healthy trend
               if (volatilityLow || volatilityScore < 0.5)
               {
                  DebugRegimeLogFile("DetectCurrentState", "Detected STATE_TRENDING_LOW_VOL");
                  Logger::Log("MarketRegime", "Market State: TRENDING_LOW_VOL (Healthy trend)", true, false);
                  return STATE_TRENDING_LOW_VOL;
               }
               else
               {
                  DebugRegimeLogFile("DetectCurrentState", "Detected STATE_TRENDING_HIGH_VOL");
                  Logger::Log("MarketRegime", "Market State: TRENDING_HIGH_VOL (High vol trend)", true, false);
                  return STATE_TRENDING_HIGH_VOL;
               }
            }
         }
         else if (adx > m_adxExhaustion) // ADX > exhaustion threshold
         {
            // Exhaustion trend
            DebugRegimeLogFile("DetectCurrentState", "Detected STATE_TRENDING_HIGH_VOL (Exhaustion)");
            Logger::Log("MarketRegime", "Market State: TRENDING_HIGH_VOL (Exhaustion)", true, false);
            return STATE_TRENDING_HIGH_VOL;
         }
      }

      // 5. Check ranging states WITH BIAS CONSIDERATION
      // SIMPLIFIED RANGING LOGIC
      if (m_rangeActive && m_cache.priceInRange)
      {
         // Check range strength
         if (!(rangeTouches < m_rangeTouchesWeak)) // Range has been respected (>=2 touches)
         {
            // Simple: If in range and price is within it, we're ranging
            if (volatilityHigh)
            {
               DebugRegimeLogFile("DetectCurrentState", "Detected STATE_RANGING_HIGH_VOL");
               Logger::Log("MarketRegime", "Market State: RANGING_HIGH_VOL (High volatility range)", true, false);
               return STATE_RANGING_HIGH_VOL;
            }
            else
            {
               DebugRegimeLogFile("DetectCurrentState", "Detected STATE_RANGING_LOW_VOL");
               Logger::Log("MarketRegime", "Market State: RANGING_LOW_VOL (Low volatility range)", true, false);
               return STATE_RANGING_LOW_VOL;
            }
         }
      }

      // ========== TIE-BREAKER: If both trend and range have similar scores ==========
      if (isTrendingStructure && m_rangeActive)
      {
         DebugRegimeLogFile("DetectCurrentState", "Running tie-breaker logic (both trend and range possible)");

         // ========== BALANCED SCORING ==========
         // Trend factors (0-1 scale)
         double trendADX = MathMin(1.0, adx / 100.0);             // ADX contribution
         double trendPriceMA = MathMin(0.3, priceVsMA / 3.0);     // Price distance from MA50
         double trendStructure = isTrendingStructure ? 0.4 : 0.1; // Price structure

         // Range factors (0-1 scale)
         double rangeActive = m_rangeActive ? 0.5 : 0.0;              // Range is active
         double rangeTouchesScore = MathMin(0.3, rangeTouches * 0.1); // Range touches
         double rangePositionScore = 0.0;

         // Calculate price position in range (if in range)
         if (m_rangeActive)
         {
            double rangeHeight = m_fixedRangeTop - m_fixedRangeBottom;
            double pricePosition = (currentPrice - m_fixedRangeBottom) / rangeHeight;
            // Price in middle of range = stronger range evidence
            if (pricePosition > 0.3 && pricePosition < 0.7)
               rangePositionScore = 0.2;
         }

         // Composite scores with BALANCED weights
         double trendScore = (trendADX * 0.5) + (trendPriceMA * 0.3) + (trendStructure * 0.2);
         double rangeScore = (rangeActive * 0.4) + (rangeTouchesScore * 0.3) + (rangePositionScore * 0.3);

         DebugRegimeLogFile("DetectCurrentState",
                            StringFormat("Tie-breaker scores: Trend=%.2f, Range=%.2f", trendScore, rangeScore));

         // ========== DECISION WITH THRESHOLDS ==========
         // Both need reasonable minimum scores
         bool trendValid = trendScore >= 0.3;
         bool rangeValid = rangeScore >= 0.3;

         if (trendValid && !rangeValid)
         {
            // Clear trend
            if (volatilityLow || volatilityScore < 0.5)
            {
               DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Clear trend (TRENDING_LOW_VOL)");
               return STATE_TRENDING_LOW_VOL;
            }
            else
            {
               DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Clear trend (TRENDING_HIGH_VOL)");
               return STATE_TRENDING_HIGH_VOL;
            }
         }
         else if (rangeValid && !trendValid)
         {
            // Clear range
            if (volatilityHigh)
            {
               DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Clear range (RANGING_HIGH_VOL)");
               return STATE_RANGING_HIGH_VOL;
            }
            else
            {
               DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Clear range (RANGING_LOW_VOL)");
               return STATE_RANGING_LOW_VOL;
            }
         }
         else if (trendValid && rangeValid)
         {
            // Both valid - check dominance
            double scoreDifference = trendScore - rangeScore;

            // Trend needs to be SIGNIFICANTLY stronger (>0.15) to win
            if (scoreDifference > 0.15) // Changed from 0.2 to 0.15
            {
               if (volatilityLow || volatilityScore < 0.5)
               {
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Trend dominant (TRENDING_LOW_VOL)");
                  return STATE_TRENDING_LOW_VOL;
               }
               else
               {
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Trend dominant (TRENDING_HIGH_VOL)");
                  return STATE_TRENDING_HIGH_VOL;
               }
            }
            // Range needs to be SIGNIFICANTLY stronger to win
            else if (scoreDifference < -0.15) // Range needs larger numbers for advantage
            {
               if (volatilityHigh)
               {
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Range dominant (RANGING_HIGH_VOL)");
                  return STATE_RANGING_HIGH_VOL;
               }
               else
               {
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Range dominant (RANGING_LOW_VOL)");
                  return STATE_RANGING_LOW_VOL;
               }
            }
            // Close scores = check additional factors
            else
            {
               DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Close scores, checking additional factors");

               // Close call - check additional factors
               // 1. Check ADX strength
               if (adx >= 30)
               {
                  // Strong ADX favors trend
                  if (volatilityLow || volatilityScore < 0.5)
                  {
                     DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: ADX favors trend (TRENDING_LOW_VOL)");
                     return STATE_TRENDING_LOW_VOL;
                  }
                  else
                  {
                     DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: ADX favors trend (TRENDING_HIGH_VOL)");
                     return STATE_TRENDING_HIGH_VOL;
                  }
               }
               // 2. Check volatility context
               else if (volatilityHigh)
               {
                  // High volatility favors range (noisy)
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: High vol favors range (RANGING_HIGH_VOL)");
                  return STATE_RANGING_HIGH_VOL;
               }
               // 3. Check recent price action
               else
               {
                  // Default to range for safety (as requested)
                  DebugRegimeLogFile("DetectCurrentState", "Tie-breaker: Default to range (RANGING_LOW_VOL)");
                  return STATE_RANGING_LOW_VOL;
               }
            }
         }
      }

      // ========== FINAL DECISION: NO UNKNOWN STATES ==========
      // If we get here, we need to make a definitive choice

      // Check if we have ANY range evidence
      bool hasRangeEvidence = m_rangeActive || rangeTouches > 0 || volatilityHigh || priceVsMA < m_priceNearMA;

      // Check if we have ANY trend evidence
      bool hasTrendEvidence = adx > 20 || isTrendingStructure || priceVsMA > m_priceFarFromMA;

      DebugRegimeLogFile("DetectCurrentState",
                         StringFormat("Final decision: RangeEvidence=%s, TrendEvidence=%s, PriceVsMA=%.2f%%, Volatility=%.2f, ADX=%.1f",
                                      hasRangeEvidence ? "YES" : "NO",
                                      hasTrendEvidence ? "YES" : "NO",
                                      priceVsMA, volatilityScore, adx));

      // DECISION RULES (prioritize RANGE when unclear):
      // 1. If we have ANY range evidence, favor RANGE
      // 2. If ADX is low (<threshold) and volatility is not high, favor RANGE
      // 3. Only return TREND if we have strong evidence

      if (hasRangeEvidence || adx < m_adxTrendingThreshold || volatilityScore < 0.6)
      {
         // Favor RANGE (safer default)
         if (volatilityHigh)
         {
            DebugRegimeLogFile("DetectCurrentState", "Ambiguous: Favoring STATE_RANGING_HIGH_VOL (safety default)");
            Logger::Log("MarketRegime", "Market State: RANGING_HIGH_VOL (ambiguous, safety default)", true, false);
            return STATE_RANGING_HIGH_VOL;
         }
         else
         {
            DebugRegimeLogFile("DetectCurrentState", "Ambiguous: Favoring STATE_RANGING_LOW_VOL (safety default)");
            Logger::Log("MarketRegime", "Market State: RANGING_LOW_VOL (ambiguous, safety default)", true, false);
            return STATE_RANGING_LOW_VOL;
         }
      }
      else
      {
         // Strong trend evidence
         if (volatilityLow || volatilityScore < 0.5)
         {
            DebugRegimeLogFile("DetectCurrentState", "Ambiguous but strong trend evidence: STATE_TRENDING_LOW_VOL");
            Logger::Log("MarketRegime", "Market State: TRENDING_LOW_VOL (strong evidence)", true, false);
            return STATE_TRENDING_LOW_VOL;
         }
         else
         {
            DebugRegimeLogFile("DetectCurrentState", "Ambiguous but strong trend evidence: STATE_TRENDING_HIGH_VOL");
            Logger::Log("MarketRegime", "Market State: TRENDING_HIGH_VOL (strong evidence)", true, false);
            return STATE_TRENDING_HIGH_VOL;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| CHECK AND INVALIDATE RANGE METHOD                                |
   //+------------------------------------------------------------------+
   void CheckAndInvalidateRange()
   {
      if (!m_cache.rangeActive)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", "Range not active, nothing to invalidate");
         return;
      }

      DebugRegimeLogFile("CheckAndInvalidateRange", "=== STARTING INVALIDATION CHECKS ===");
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Current: %.5f, Range: %.5f-%.5f, Width: %.5f",
                                      m_cache.currentPrice, m_fixedRangeBottom, m_fixedRangeTop,
                                      m_fixedRangeTop - m_fixedRangeBottom));

      double currentPrice = m_cache.currentPrice;

      // ========== RULE 1: Consecutive closes outside range ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", "--- RULE 1: Consecutive closes outside range ---");
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
                         StringFormat("Bar status: %s", barStatus));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Consecutive outside: %d/2 needed", consecutiveOutside));

      if (consecutiveOutside >= 2)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", "✅ RULE 1 TRIGGERED: 2+ consecutive closes outside range");
         InvalidateRange("2+ consecutive closes outside range");
         return;
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", "❌ RULE 1 NOT MET: Need 2 consecutive outside");
      }

      // ========== RULE 2: Strong momentum break with ATR expansion ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", "--- RULE 2: Strong momentum breakout ---");
      double atr = m_cache.atr;
      double atr_5 = GetATRValue(14, 5);
      double priceChange = GetPriceChange(3);
      bool hasBroken = HasRangeBroken(currentPrice);
      bool atrExpanded = atr > atr_5 * 1.2;
      bool strongMomentum = MathAbs(priceChange) > atr * 1.5;

      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("HasRangeBroken: %s (Current: %.5f, Top+Buf: %.5f, Bot-Buf: %.5f)",
                                      hasBroken ? "YES" : "NO",
                                      currentPrice,
                                      m_fixedRangeTop + (atr * 0.5),
                                      m_fixedRangeBottom - (atr * 0.5)));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("ATR Expansion: %.5f > %.5f*1.2 = %.5f? %s",
                                      atr, atr_5, atr_5 * 1.2, atrExpanded ? "YES" : "NO"));
      DebugRegimeLogFile("CheckAndInvalidateRange",
                         StringFormat("Momentum: |%.2f%%| > %.5f*1.5 = %.5f? %s",
                                      priceChange, atr, atr * 1.5, strongMomentum ? "YES" : "NO"));

      bool strongBreakout = hasBroken && atrExpanded && strongMomentum;

      if (strongBreakout)
      {
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            "✅ RULE 2 TRIGGERED: Strong momentum breakout with ATR expansion");
         InvalidateRange("Strong momentum breakout with ATR expansion");
         return;
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("❌ RULE 2 NOT MET: hasBroken=%s, ATRexp=%s, Momentum=%s",
                                         hasBroken ? "YES" : "NO",
                                         atrExpanded ? "YES" : "NO",
                                         strongMomentum ? "YES" : "NO"));
      }

      // ========== RULE 3: MA confirms trend (not range) ==========
      DebugRegimeLogFile("CheckAndInvalidateRange", "--- RULE 3: MA confirms trend ---");
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
                            StringFormat("MA50: %.5f, Current: %.5f, Distance: %.5f (%.2f%%)",
                                         ma50, currentPrice, priceDistance, (priceDistance / ma50 * 100)));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("AwayFromMA50: %.5f > %.5f? %s",
                                         priceDistance, atr, awayFromMA50 ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("PrevAwayFromMA50: %.5f > %.5f? %s",
                                         MathAbs(prevPrice - prevMA50), atr * 0.8, prevAwayFromMA50 ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("Trend: Bullish=%s, Bearish=%s",
                                         bullishTrend ? "YES" : "NO", bearishTrend ? "YES" : "NO"));
         DebugRegimeLogFile("CheckAndInvalidateRange",
                            StringFormat("ADX Confirmation: %.1f >= %.1f? %s",
                                         adx, m_adxTrendConfirmation, adxConfirms ? "YES" : "NO"));

         if ((bullishTrend || bearishTrend) && awayFromMA50 && prevAwayFromMA50 && adxConfirms)
         {
            string trendType = bullishTrend ? "bullish" : "bearish";
            string message = StringFormat("Price %s away from MA50 (Distance: %.2f%%, ATR: %.5f)",
                                          trendType, (priceDistance / ma50 * 100), atr);
            DebugRegimeLogFile("CheckAndInvalidateRange",
                               StringFormat("✅ RULE 3 TRIGGERED: %s", message));
            InvalidateRange(message);
            return;
         }
         else
         {
            DebugRegimeLogFile("CheckAndInvalidateRange",
                               "❌ RULE 3 NOT MET: One or more conditions failed");
         }
      }
      else
      {
         DebugRegimeLogFile("CheckAndInvalidateRange", "❌ RULE 3 SKIPPED: Invalid MA50 value");
      }

      DebugRegimeLogFile("CheckAndInvalidateRange", "✅ ALL INVALIDATION CHECKS PASSED - Range remains active");
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
         DebugRegimeLogFile("HasRangeBroken", "Range not active, cannot be broken");
         return false;
      }

      double atr = m_cache.atr;
      double margin = atr * 0.5;
      double upperBreakLevel = m_fixedRangeTop + margin;
      double lowerBreakLevel = m_fixedRangeBottom - margin;

      bool brokenAbove = price > upperBreakLevel;
      bool brokenBelow = price < lowerBreakLevel;
      bool broken = brokenAbove || brokenBelow;

      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Price: %.5f, Range: %.5f-%.5f, Margin: %.5f, Upper: %.5f, Lower: %.5f",
                                      price, m_fixedRangeBottom, m_fixedRangeTop, margin,
                                      upperBreakLevel, lowerBreakLevel));
      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Broken Above: %.5f > %.5f? %s",
                                      price, upperBreakLevel, brokenAbove ? "YES" : "NO"));
      DebugRegimeLogFile("HasRangeBroken",
                         StringFormat("Broken Below: %.5f < %.5f? %s",
                                      price, lowerBreakLevel, brokenBelow ? "YES" : "NO"));

      return broken;
   }

   //+------------------------------------------------------------------+
   //| INVALIDATE RANGE HELPER                                          |
   //+------------------------------------------------------------------+
   void InvalidateRange(string reason)
   {
      DebugRegimeLogFile("InvalidateRange", StringFormat("Invalidating range: %s", reason));

      m_rangeActive = false;
      m_cache.rangeActive = false; // Update cache
      m_lastInvalidationTime = iTime(m_symbol, m_timeframe, 0);

      string invalidationMsg = StringFormat("Range Invalidated: %s (Cooldown: %d bars)",
                                            reason, m_invalidationCooldownBars);

      Print(invalidationMsg);
      Logger::Log("MarketRegime", invalidationMsg, true, true);
      DebugRegimeLogFile("InvalidateRange", invalidationMsg);

      // Log trade event for range invalidation
      Logger::LogTrade("Range", m_symbol, "INVALIDATE", 0, iClose(m_symbol, m_timeframe, 0));
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
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         // Use IndicatorManager for MA values
         double ma9, ma21, ma50, ma89;
         if (m_indicatorManager.GetMAValuesForRange(m_timeframe, ma9, ma21, ma50, ma89, shift))
         {
            if (period == 50)
               return ma50;
            if (period == 89)
               return ma89;
         }
         else
         {
            double ma_fast, ma_slow, ma_medium;
            if (m_indicatorManager.GetMAValues(m_timeframe, ma_fast, ma_slow, ma_medium, shift))
            {
               if (period == 9)
                  return ma_fast;
               if (period == 21)
                  return ma_medium;
               if (period == 89)
                  return ma_slow;
            }
         }
      }

      // Fallback to direct MA calculation
      int handle = iMA(m_symbol, m_timeframe, period, 0, MODE_SMA, PRICE_CLOSE);
      if (handle == INVALID_HANDLE)
         return 0;

      double values[];
      ArraySetAsSeries(values, true);

      if (CopyBuffer(handle, 0, shift, 1, values) > 0)
      {
         IndicatorRelease(handle);
         return values[0];
      }

      IndicatorRelease(handle);
      return 0;
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
                  DebugRegimeLogFile("IsMATrendAligned", "MA trend alignment confirmed");
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
         rootState = REGIME_TRENDING;
         break;

      case STATE_RANGING_LOW_VOL:
      case STATE_RANGING_HIGH_VOL:
         rootState = REGIME_RANGING;
         break;

      default:
         rootState = REGIME_UNKNOWN;
      }

      DebugRegimeLogFile("GetRootState",
                         StringFormat("Root state for %s: %s",
                                      MarketAnalysis::GetStateString(state),
                                      rootState == REGIME_TRENDING ? "TRENDING" : rootState == REGIME_RANGING ? "RANGING"
                                                                                                              : "UNKNOWN"));

      return rootState;
   }

   //+------------------------------------------------------------------+
   //| INDICATOR CALCULATIONS (using IndicatorManager when available)  |
   //+------------------------------------------------------------------+
   double GetADX(int period)
   {
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         double adx, plus_di, minus_di;
         if (m_indicatorManager.GetADXValues(m_timeframe, adx, plus_di, minus_di))
         {
            return adx;
         }
      }

      // Fallback to direct calculation
      int handle = iADX(m_symbol, m_timeframe, period);
      if (handle == INVALID_HANDLE)
         return 0;

      double adx[];
      ArraySetAsSeries(adx, true);

      if (CopyBuffer(handle, 0, 0, 1, adx) > 0)
      {
         IndicatorRelease(handle);
         return adx[0];
      }

      IndicatorRelease(handle);
      return 0;
   }

   double GetATR(int period)
   {
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
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         double upper, middle, lower;
         if (m_indicatorManager.GetBollingerBandsValues(m_timeframe, upper, middle, lower))
         {
            double currentPrice = iClose(m_symbol, m_timeframe, 0);
            if (currentPrice > 0)
               return (upper - lower) / currentPrice;
         }
      }

      // Fallback to direct calculation
      int handle = iBands(m_symbol, m_timeframe, period, 0, deviations, PRICE_CLOSE);
      if (handle == INVALID_HANDLE)
         return 0;

      double upper[], lower[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);

      if (CopyBuffer(handle, 1, 0, 1, upper) > 0 &&
          CopyBuffer(handle, 2, 0, 1, lower) > 0)
      {
         IndicatorRelease(handle);
         double currentPrice = iClose(m_symbol, m_timeframe, 0);
         if (currentPrice > 0)
            return (upper[0] - lower[0]) / currentPrice;
      }

      IndicatorRelease(handle);
      return 0;
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

      DebugRegimeLogFile("CountRangeTouches", StringFormat("Range touches: %d", touches));
      return touches;
   }

   // In CalculateVolatilityScore() function:
   double CalculateVolatilityScore(double atr, double bbWidth)
   {
      // Use longer period for smoothing (increase from 20 to 50)
      double atrValues[10];
      int lookback = m_structureLookbackBars; // Increased from 20

      for (int i = 0; i < lookback; i++)
      {
         double price = iClose(m_symbol, m_timeframe, i);
         if (price > 0)
            atrValues[i] = GetATRValue(14, i) / price;
      }

      double currentAtrNorm = atr / iClose(m_symbol, m_timeframe, 0);
      double avgAtrNorm = ArrayAverage(atrValues, lookback);

      if (avgAtrNorm > 0)
      {
         // Apply smoothing to reduce noise
         static double smoothedScore = 0.5;
         double rawScore = MathMin(1.0, currentAtrNorm / avgAtrNorm);
         smoothedScore = smoothedScore * 0.3 + rawScore * 0.7; // 50% weight to previous value
         return smoothedScore;
      }

      return 0.5;
   }

   bool IsVolatilityRising()
   {
      double atrNow = m_cache.atr; // Use cached ATR
      double atrBefore = GetATRValue(14, 5);

      bool rising = atrNow > atrBefore * 1.1;
      DebugRegimeLogFile("IsVolatilityRising", StringFormat("ATR now=%.5f, before=%.5f, rising=%s",
                                                            atrNow, atrBefore, rising ? "true" : "false"));
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
      DebugRegimeLogFile("IsTrendingStructure", "Checking for trending price structure");

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
         DebugRegimeLogFile("IsTrendingStructure", "Invalid MA values, falling back to basic structure check");
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
                         StringFormat("Price structure: Uptrend ratio=%.2f, Downtrend ratio=%.2f",
                                      uptrendRatio, downtrendRatio));

      // ========== DECISION LOGIC (BALANCED) ==========

      // CRITICAL: If MAs are significantly separated (>0.75%), GENTLE trend bias
      // Changed from 0.5% to 0.75% for more selective bias
      if (maDistancePercent > 0.6) // Increase to 0.5 - need clearer MA separation
      {
         // Strong MA separation = trend gets MODERATE priority
         // Changed from 0.4 to 0.5 threshold - need clearer trend structure
         if (maAlignedBullish && uptrendRatio > 0.45)
         {
            DebugRegimeLogFile("IsTrendingStructure", "MA aligned bullish with uptrend structure");
            return true; // Need 50% confirmation (was 40%)
         }
         if (maAlignedBearish && downtrendRatio > 0.45)
         {
            DebugRegimeLogFile("IsTrendingStructure", "MA aligned bearish with downtrend structure");
            return true;
         }
      }

      // Original logic - keep as primary
      if (uptrendRatio > 0.6 || downtrendRatio > 0.6) // 70% threshold
      {
         DebugRegimeLogFile("IsTrendingStructure", "Strong price structure detected");
         return true;
      }

      // Additional check: If price consistently above/below key MAs
      double currentPrice = m_cache.currentPrice; // Use cached price

      // Price far from 200 MA suggests trend
      double distanceFromMA = MathAbs(currentPrice - ma200) / ma200 * 100;
      if (distanceFromMA > 1.0) // Changed from 1.0% to 1.5% - more conservative
      {
         DebugRegimeLogFile("IsTrendingStructure",
                            StringFormat("Price far from MA200 (%.2f%%), forcing trend classification", distanceFromMA));
         return true; // Force trend classification
      }

      DebugRegimeLogFile("IsTrendingStructure", "No trending structure detected");
      return false;
   }

   bool CheckBasicTrendStructure()
   {
      DebugRegimeLogFile("CheckBasicTrendStructure", "Running basic 5-bar trend structure check");

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
                         StringFormat("Basic trend check result: %s (Uptrend: %s, Downtrend: %s)",
                                      result ? "true" : "false", uptrend ? "true" : "false", downtrend ? "true" : "false"));

      return result;
   }

   bool IsRangingStructure()
   {
      if (!m_rangeActive)
      {
         DebugRegimeLogFile("IsRangingStructure", "Range not active");
         return false;
      }

      double currentPrice = m_cache.currentPrice; // Use cached price
      bool inRange = IsPriceInFixedRange(currentPrice);

      DebugRegimeLogFile("IsRangingStructure",
                         StringFormat("Price %.5f in range %.5f-%.5f: %s",
                                      currentPrice, m_fixedRangeBottom, m_fixedRangeTop, inRange ? "true" : "false"));

      return inRange;
   }

   double CalculateConfidence(ENUM_MARKET_STATE state)
   {
      DebugRegimeLogFile("CalculateConfidence",
                         StringFormat("Calculating confidence for state: %s", MarketAnalysis::GetStateString(state)));

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
                         StringFormat("Final confidence: %.1f%% (ADX=%.1f, ATRScore=%.2f, StructureConf=%.0f)",
                                      confidence, adx, atrScore, structureConfidence));

      return confidence;
   }

   //+------------------------------------------------------------------+
   //| STATE PREDICTION                                                |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE PredictNextState(ENUM_MARKET_STATE currentState)
   {
      DebugRegimeLogFile("PredictNextState",
                         StringFormat("Predicting next state from: %s", MarketAnalysis::GetStateString(currentState)));

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
                         StringFormat("Predicted next state: %s", MarketAnalysis::GetStateString(nextState)));

      return nextState;
   }

   //+------------------------------------------------------------------+
   //| TRADING RECOMMENDATIONS                                         |
   //+------------------------------------------------------------------+
   void GenerateRecommendations(MarketAnalysis &analysis)
   {
      DebugRegimeLogFile("GenerateRecommendations", "Generating trading recommendations");

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
         DebugRegimeLogFile("GenerateRecommendations", "RANGING_LOW_VOL: Fade extremes, mean reversion");
         break;

      case STATE_RANGING_HIGH_VOL:
         analysis.action = "Fade carefully with tight stops";
         analysis.positionSize = SIZE_VERY_SMALL;
         analysis.stopDistance = atr * 0.8;
         analysis.takeProfitDistance = atr * 1.5;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "Neutral (dangerous)";
         DebugRegimeLogFile("GenerateRecommendations", "RANGING_HIGH_VOL: Fade carefully, tight stops");
         break;

      case STATE_CONTRACTION:
         analysis.action = "Prepare for breakout - no trades";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (waiting)";
         DebugRegimeLogFile("GenerateRecommendations", "CONTRACTION: No trades, prepare for breakout");
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
            DebugRegimeLogFile("GenerateRecommendations", "EXPANSION: Bullish breakout entry");
         }
         else if (currentPrice < m_fixedRangeBottom)
         {
            analysis.direction = "Bearish breakout";
            DebugRegimeLogFile("GenerateRecommendations", "EXPANSION: Bearish breakout entry");
         }
         else
         {
            analysis.direction = "Testing";
            DebugRegimeLogFile("GenerateRecommendations", "EXPANSION: Testing breakout");
         }
         break;

      case STATE_TRENDING_LOW_VOL:
         analysis.action = "Add to winning positions";
         analysis.positionSize = SIZE_LARGE;
         analysis.stopDistance = atr * 2.0;
         analysis.takeProfitDistance = atr * 6.0;
         analysis.riskRewardRatio = 3.0;
         analysis.direction = IsTrendingStructure() ? "With trend" : "Neutral";
         DebugRegimeLogFile("GenerateRecommendations", "TRENDING_LOW_VOL: Add to winning positions");
         break;

      case STATE_TRENDING_HIGH_VOL:
         analysis.action = "Take partial profits";
         analysis.positionSize = SIZE_MEDIUM;
         analysis.stopDistance = atr * 1.0;
         analysis.takeProfitDistance = atr * 2.0;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "With trend (cautious)";
         DebugRegimeLogFile("GenerateRecommendations", "TRENDING_HIGH_VOL: Take partial profits");
         break;

      case STATE_CHURN:
         analysis.action = "Exit positions, wait for clarity";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (avoid)";
         DebugRegimeLogFile("GenerateRecommendations", "CHURN: Exit positions, wait for clarity");
         break;
      }

      // Adjust position size based on account
      analysis.positionSize = AdjustPositionSize(analysis.positionSize);

      DebugRegimeLogFile("GenerateRecommendations",
                         StringFormat("Final recommendation: %s, Position: %s, Stop: %.2f, TP: %.2f, R/R: %.1f",
                                      analysis.action, GetPositionSizeString(analysis.positionSize),
                                      analysis.stopDistance, analysis.takeProfitDistance, analysis.riskRewardRatio));

      // Log trading recommendation
      Logger::LogTrade("Recommendation", m_symbol,
                       analysis.direction == "Bullish breakout" ? "BUY" : analysis.direction == "Bearish breakout" ? "SELL"
                                                                                                                   : "HOLD",
                       0, currentPrice);

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
            DebugRegimeLogFile("AdjustPositionSize", "Account small: LARGE -> MEDIUM");
            break;
         case SIZE_MEDIUM:
            adjustedSize = SIZE_SMALL;
            DebugRegimeLogFile("AdjustPositionSize", "Account small: MEDIUM -> SMALL");
            break;
         default:
            adjustedSize = baseSize;
         }
      }

      DebugRegimeLogFile("AdjustPositionSize",
                         StringFormat("Position size: %s -> %s (Account: $%.2f, Risk: $%.2f)",
                                      GetPositionSizeString(baseSize),
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

      DebugRegimeLogFile("GenerateDescription", StringFormat("Description: %s", desc));

      return desc;
   }

public:
   //+------------------------------------------------------------------+
   //| MANUAL RANGE REINITIALIZATION                                   |
   //+------------------------------------------------------------------+
   void ResetRange()
   {
      DebugRegimeLogFile("ResetRange", "Manual range reset requested");
      Logger::Log("MarketRegime", "Manual range reset", true, true);
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
      string msg = "Range lookback bars set to: " + IntegerToString(bars);
      Print(msg);
      Logger::Log("MarketRegime", msg, true, false);
      DebugRegimeLogFile("SetRangeLookbackBars", msg);
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
                         StringFormat("Account info updated: Balance=$%.2f, Risk=%.1f%%",
                                      balance, riskPercent));
   }

   // Access to IndicatorManager for other uses
   IndicatorManager *GetIndicatorManager() const { return m_indicatorManager; }

   // Method to get IndicatorManager initialization status
   bool IsIndicatorManagerInitialized() const
   {
      bool initialized = (m_indicatorManager != NULL && m_indicatorManager.IsInitialized());
      DebugRegimeLogFile("IsIndicatorManagerInitialized",
                         StringFormat("IndicatorManager initialized: %s", initialized ? "true" : "false"));
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
                                ENUM_TIMEFRAMES tf = PERIOD_H1,
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

   // Draw fixed range on chart if active
   MarketRegimeDetector detector(symbol, tf);

   // Double-check: Is range actually active?
   if (shouldShowRange)
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
                                          ENUM_TIMEFRAMES tf = PERIOD_H1,
                                          bool showPanel = true,
                                          int panelCorner = CORNER_RIGHT_UPPER,
                                          bool useIndicatorManager = true)
{
   static MarketRegimeDetector *detector = NULL;

   if (detector == NULL)
   {
      detector = new MarketRegimeDetector(symbol, tf, 0, 0, useIndicatorManager); // Use input parameters
      Logger::Log("MarketRegime", StringFormat("Global detector initialized for %s using input parameters", symbol), true, false);
   }

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