//+------------------------------------------------------------------+
//|                                                   MarketRegime.mq5|
//|             Simplified Market Regime & Lifecycle Detection       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.00"
#property strict

#include <Math\Stat\Math.mqh>

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"
#include "../Data/IndicatorManager.mqh" // Include IndicatorManager

//+------------------------------------------------------------------+
//| Market Regime Detector Class                                     |
//+------------------------------------------------------------------+
class MarketRegimeDetector
{
private:
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

public:
   MarketRegimeDetector(string symbol = NULL,
                        ENUM_TIMEFRAMES tf = PERIOD_H1,
                        double accountBalance = 10000,
                        double riskPercent = 1.0,
                        bool useIndicatorManager = true)
   {
      m_symbol = (symbol == NULL) ? Symbol() : symbol;
      m_timeframe = tf;
      m_rangeActive = false;
      m_lookbackBars = 8;
      m_accountBalance = accountBalance;
      m_accountRiskPercent = riskPercent;
      m_useIndicatorManager = useIndicatorManager;

      // Initialize indicator manager if requested
      if (m_useIndicatorManager)
      {
         m_indicatorManager = new IndicatorManager(m_symbol);
         if (!m_indicatorManager.Initialize())
         {
            Print("WARNING: IndicatorManager failed to initialize. Falling back to direct indicators.");
            m_useIndicatorManager = false;
         }
      }
      else
      {
         m_indicatorManager = NULL;
      }

      // Initialize fixed range
      InitializeFixedRange();
   }

   ~MarketRegimeDetector()
   {
      if (m_indicatorManager != NULL)
      {
         m_indicatorManager.Deinitialize();
         delete m_indicatorManager;
      }
   }

   //+------------------------------------------------------------------+
   //| MAIN PUBLIC METHOD: Get complete market analysis                |
   //+------------------------------------------------------------------+
   MarketAnalysis GetMarketRegime()
   {
      MarketAnalysis analysis;

      // 1. Initialize fixed range (5-bar lookback)
      if (!m_rangeActive)
      {
         InitializeFixedRange();
      }

      // 2. Get current state using indicators
      analysis.state = DetectCurrentState();
      analysis.rootState = GetRootState(analysis.state);
      analysis.confidence = CalculateConfidence(analysis.state);

      // 3. Determine next likely state
      analysis.nextLikelyState = PredictNextState(analysis.state);

      // 4. Generate trading recommendations
      GenerateRecommendations(analysis);

      // 5. Set description
      analysis.description = GenerateDescription(analysis);

      return analysis;
   }

   //+------------------------------------------------------------------+
   //| FIXED RANGE MANAGEMENT                                          |
   //+------------------------------------------------------------------+
private:
   double GetMAValue(int period, int shift = 0)
   {
      if (m_useIndicatorManager && m_indicatorManager != NULL && m_indicatorManager.IsInitialized())
      {
         // Use IndicatorManager for MA values
         double ma9, ma21, ma50, ma89;
         if (period == 50 || period == 89)
         {
            if (m_indicatorManager.GetMAValuesForRange(m_timeframe, ma9, ma21, ma50, ma89, shift))
            {
               if (period == 50)
                  return ma50;
               if (period == 89)
                  return ma89;
            }
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
            double ma50_5 = GetMAValue(50, 5);
            double ma89_5 = GetMAValue(89, 5);

            if (ma50 <= 0 || ma89 <= 0)
               return false;

            // Calculate separation percentage
            double separation = MathAbs(ma50 - ma89) / ((ma50 + ma89) / 2) * 100;

            // Check alignment and slope
            bool maAlignedBullish = (ma50 > ma89) && (ma50_5 > ma89_5);
            bool maAlignedBearish = (ma50 < ma89) && (ma50_5 < ma89_5);
            bool maSlopeBullish = (ma50 > ma50_5);
            bool maSlopeBearish = (ma50 < ma50_5);

            // Significant separation with same slope = strong trend
            if (separation > 0.5) // 0.5% separation threshold
            {
               if ((maAlignedBullish && maSlopeBullish) ||
                   (maAlignedBearish && maSlopeBearish))
               {
                  return true;
               }
            }
         }
      }

      return false;
   }

   void InitializeFixedRange()
   {
      int bars = 8; // Fixed 5-bar lookback for initial range
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

         Print(StringFormat("Fixed Range Initialized: %.5f - %.5f (Width: %.2f%%)",
                            lowest, highest,
                            ((highest - lowest) / ((highest + lowest) / 2)) * 100));
      }
   }

   bool IsPriceInFixedRange(double price)
   {
      if (!m_rangeActive)
         return false;
      return price >= m_fixedRangeBottom && price <= m_fixedRangeTop;
   }

   bool HasRangeBroken(double price)
   {
      if (!m_rangeActive)
         return false;

      double atr = GetATR(14);
      double margin = atr * 0.3; // 0.3 ATR margin for breakout

      return (price > m_fixedRangeTop + margin) ||
             (price < m_fixedRangeBottom - margin);
   }

   //+------------------------------------------------------------------+
   //| STATE DETECTION LOGIC                                           |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE DetectCurrentState()
   {
      // Get key indicator values
      double adx = GetADX(14);
      double atr = GetATR(14);
      double bbWidth = GetBollingerWidth(20, 2);
      double priceChange = GetPriceChange(5);
      double rangeTouches = CountRangeTouches();

      // ========== FIXED: MA SEPARATION as CONFIDENCE BOOST, not VETO ==========
      double ma50 = GetMAValue(50, 0);
      double ma89 = GetMAValue(89, 0);
      double maDistancePercent = 0;

      if (ma50 > 0 && ma89 > 0)
      {
         maDistancePercent = MathAbs(ma50 - ma89) / ((ma50 + ma89) / 2) * 100;
      }

      // ========== TREND BIAS: If MAs are far apart, INCREASE trend confidence ==========
      double trendBias = 0; // 0 = no bias, 1.0 = strong trend bias
      double rangeBias = 0; // 0 = no bias, 1.0 = strong range bias

      if (maDistancePercent > 0.5) // 0.5% separation = moderate trend bias
      {
         trendBias = MathMin(1.0, (maDistancePercent - 0.5) / 1.0); // Scales 0.5-1.5% to 0-1.0

         // Get MA slope (5 bars ago vs now)
         double ma50_5 = GetMAValue(50, 5);
         bool maSlopeUp = (ma50 > ma50_5);
         bool maSlopeDown = (ma50 < ma50_5);

         // If MAs are diverging (getting further apart), stronger trend bias
         if ((maDistancePercent > 0.75) && (maSlopeUp || maSlopeDown))
         {
            trendBias = MathMin(1.0, trendBias + 0.3); // Extra bias for strong separation with slope
         }
      }

      // Rest of your existing code continues below...
      double volatilityScore = CalculateVolatilityScore(atr, bbWidth);
      bool volatilityLow = volatilityScore < 0.3;
      bool volatilityHigh = volatilityScore > 0.7;
      bool volatilityRising = IsVolatilityRising();

      // Price structure analysis
      bool isTrendingStructure = IsTrendingStructure();
      bool isRangingStructure = IsRangingStructure();

      // Decision matrix
      // 1. Check for Contraction/Squeeze (STATE_CONTRACTION)
      if (volatilityLow && !volatilityRising && adx < 15 && rangeTouches < 2)
      {
         return STATE_CONTRACTION;
      }

      // 2. Check for Expansion/Breakout (STATE_EXPANSION)
      if (HasRangeBroken(iClose(m_symbol, m_timeframe, 0)) &&
          MathAbs(priceChange) > atr * 2)
      {
         return STATE_EXPANSION;
      }

      // 3. Check for Churn/Exhaustion (STATE_CHURN)
      if (volatilityHigh && volatilityRising && adx > 40 &&
          MathAbs(priceChange) < atr * 0.5)
      {
         return STATE_CHURN;
      }

      // ========== ADD RANGE STRENGTH CHECK ==========
      // Check if price is respecting range boundaries
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
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
         if (rangeTouches >= 3)
         {
            rangeBias = MathMin(1.0, rangeBias + 0.3);
         }
      }

      // ========== BALANCED DECISION MAKING ==========

      // 4. Check trending states WITH BIAS CONSIDERATION
      if (isTrendingStructure)
      {
         // RESTORE ADX THRESHOLD to 25 (from 20)
         if (adx >= 25) // Changed BACK to 25 from 20
         {
            // Apply trend bias if MAs are separated
            double trendStrength = adx / 100.0; // Normalize ADX 0-1
            double finalTrendScore = trendStrength + (trendBias * 0.3) - (rangeBias * 0.3);

            // Need reasonable trend strength even with MA bias
            if (finalTrendScore > 0.35) // Combined score threshold
            {
               // Healthy trend
               if (volatilityLow || volatilityScore < 0.5)
                  return STATE_TRENDING_LOW_VOL;
               else
                  return STATE_TRENDING_HIGH_VOL;
            }
         }
         else if (adx > 40) // Keep this for exhaustion trend
         {
            // Exhaustion trend
            return STATE_TRENDING_HIGH_VOL;
         }
      }

      // 5. Check ranging states WITH BIAS CONSIDERATION
      if (isRangingStructure || m_rangeActive)
      {
         // Apply range bias if price is respecting range
         double rangeStrength = (m_rangeActive ? 0.7 : 0.3) + (rangeTouches * 0.05);
         double finalRangeScore = rangeStrength + (rangeBias * 0.3) - (trendBias * 0.3);

         if (finalRangeScore > 0.4) // Need reasonable range strength
         {
            if (volatilityHigh)
               return STATE_RANGING_HIGH_VOL;
            else
               return STATE_RANGING_LOW_VOL;
         }
      }

      // ========== TIE-BREAKER: If both trend and range have similar scores ==========
      if (isTrendingStructure && m_rangeActive)
      {
         // ========== BALANCED SCORING ==========
         // Trend factors (0-1 scale)
         double trendADX = MathMin(1.0, adx / 100.0);              // ADX contribution
         double trendMA = MathMin(0.3, maDistancePercent / 500.0); // REDUCED: MA contributes max 0.3 (was 0.75)
         double trendStructure = isTrendingStructure ? 0.4 : 0.1;  // Price structure

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
         double trendScore = (trendADX * 0.5) + (trendMA * 0.3) + (trendStructure * 0.2);
         double rangeScore = (rangeActive * 0.4) + (rangeTouchesScore * 0.3) + (rangePositionScore * 0.3);

         // Debug output (optional)
         // Print(StringFormat("TrendScore: %.2f (ADX:%.2f, MA:%.2f, Struct:%.2f)",
         //      trendScore, trendADX, trendMA, trendStructure));
         // Print(StringFormat("RangeScore: %.2f (Active:%.2f, Touches:%.2f, Pos:%.2f)",
         //      rangeScore, rangeActive, rangeTouchesScore, rangePositionScore));

         // ========== DECISION WITH THRESHOLDS ==========
         // Both need reasonable minimum scores
         bool trendValid = trendScore >= 0.3;
         bool rangeValid = rangeScore >= 0.3;

         if (trendValid && !rangeValid)
         {
            // Clear trend
            if (volatilityLow || volatilityScore < 0.5)
               return STATE_TRENDING_LOW_VOL;
            else
               return STATE_TRENDING_HIGH_VOL;
         }
         else if (rangeValid && !trendValid)
         {
            // Clear range
            if (volatilityHigh)
               return STATE_RANGING_HIGH_VOL;
            else
               return STATE_RANGING_LOW_VOL;
         }
         else if (trendValid && rangeValid)
         {
            // Both valid - check dominance
            double scoreDifference = trendScore - rangeScore;

            // Trend needs to be SIGNIFICANTLY stronger (>0.15) to win
            if (scoreDifference > 0.15) // Changed from 0.2 to 0.15
            {
               if (volatilityLow || volatilityScore < 0.5)
                  return STATE_TRENDING_LOW_VOL;
               else
                  return STATE_TRENDING_HIGH_VOL;
            }
            // Range needs to be SIGNIFICANTLY stronger to win
            else if (scoreDifference < -0.15) // Changed from -0.2 to -0.15
            {
               if (volatilityHigh)
                  return STATE_RANGING_HIGH_VOL;
               else
                  return STATE_RANGING_LOW_VOL;
            }
            // Close scores = check additional factors
            else
            {
               // Close call - check additional factors
               // 1. Check ADX strength
               if (adx >= 30)
               {
                  // Strong ADX favors trend
                  if (volatilityLow || volatilityScore < 0.5)
                     return STATE_TRENDING_LOW_VOL;
                  else
                     return STATE_TRENDING_HIGH_VOL;
               }
               // 2. Check volatility context
               else if (volatilityHigh)
               {
                  // High volatility favors range (noisy)
                  return STATE_RANGING_HIGH_VOL;
               }
               // 3. Check recent price action
               else
               {
                  // Default to range for safety
                  return STATE_RANGING_LOW_VOL;
               }
            }
         }
      }

      return STATE_UNKNOWN;
   }

   ENUM_ROOT_REGIME GetRootState(ENUM_MARKET_STATE state)
   {
      switch (state)
      {
      case STATE_TRENDING_LOW_VOL:
      case STATE_TRENDING_HIGH_VOL:
         return REGIME_TRENDING;

      case STATE_RANGING_LOW_VOL:
      case STATE_RANGING_HIGH_VOL:
         return REGIME_RANGING;

      default:
         return REGIME_UNKNOWN;
      }
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
      double atr = GetATR(14);
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

      return touches;
   }

   double CalculateVolatilityScore(double atr, double bbWidth)
   {
      // Normalize ATR (0-1 scale based on recent history)
      double atrValues[20];
      for (int i = 0; i < 20; i++)
      {
         double price = iClose(m_symbol, m_timeframe, i);
         atrValues[i] = GetATR(14) / price;
      }

      double currentAtrNorm = atr / iClose(m_symbol, m_timeframe, 0);
      double avgAtrNorm = ArrayAverage(atrValues, 20);

      if (avgAtrNorm > 0)
         return MathMin(1.0, currentAtrNorm / avgAtrNorm);

      return 0.5;
   }

   bool IsVolatilityRising()
   {
      double atrNow = GetATR(14);
      double atrBefore = GetATRValue(14, 5);

      return atrNow > atrBefore * 1.1;
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
      // ========== NEW: ADD MOVING AVERAGE CONFIRMATION ==========
      // Get MA values using IndicatorManager or direct
      double ma50 = GetMAValue(50, 0);
      double ma50_5 = GetMAValue(50, 5);
      double ma89 = GetMAValue(89, 0);
      double ma89_5 = GetMAValue(89, 5);
      double ma200 = GetMAValue(200, 0);

      // Check if we got valid values
      if (ma50 <= 0 || ma89 <= 0 || ma200 <= 0)
      {
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
      bool maAlignedBullish = (ma50 > ma89) && (ma50_5 > ma89_5);
      bool maAlignedBearish = (ma50 < ma89) && (ma50_5 < ma89_5);

      // ========== ENHANCED PRICE STRUCTURE (more forgiving) ==========
      // Look at 8 bars instead of 5
      int lookback = 8;
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

      // ========== DECISION LOGIC (BALANCED) ==========

      // CRITICAL: If MAs are significantly separated (>0.75%), GENTLE trend bias
      // Changed from 0.5% to 0.75% for more selective bias
      if (maDistancePercent > 0.75) // 0.75% separation between 50 and 89 MA
      {
         // Strong MA separation = trend gets MODERATE priority
         // Changed from 0.4 to 0.5 threshold - need clearer trend structure
         if (maAlignedBullish && uptrendRatio > 0.5)
            return true; // Need 50% confirmation (was 40%)
         if (maAlignedBearish && downtrendRatio > 0.5)
            return true;
      }

      // Original logic - keep as primary
      if (uptrendRatio > 0.7 || downtrendRatio > 0.7) // 70% threshold
      {
         return true;
      }

      // Additional check: If price consistently above/below key MAs
      double currentPrice = iClose(m_symbol, m_timeframe, 0);

      // Price far from 200 MA suggests trend
      double distanceFromMA = MathAbs(currentPrice - ma200) / ma200 * 100;
      if (distanceFromMA > 1.5) // Changed from 1.0% to 1.5% - more conservative
      {
         return true; // Force trend classification
      }

      return false;
   }

   bool CheckBasicTrendStructure()
   {
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

      return uptrend || downtrend;
   }

   bool IsRangingStructure()
   {
      if (!m_rangeActive)
         return false;

      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      return IsPriceInFixedRange(currentPrice);
   }

   double CalculateConfidence(ENUM_MARKET_STATE state)
   {
      double adx = GetADX(14);
      double atrScore = CalculateVolatilityScore(GetATR(14), GetBollingerWidth(20, 2));
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
         confidence = (HasRangeBroken(iClose(m_symbol, m_timeframe, 0)) ? 80 : 30);
         break;

      case STATE_TRENDING_LOW_VOL:
         confidence = MathMin(100, adx * 2) * 0.6 + structureConfidence * 0.4;
         break;

      case STATE_TRENDING_HIGH_VOL:
         confidence = MathMin(100, adx) * 0.7 + structureConfidence * 0.3;
         break;

      case STATE_RANGING_LOW_VOL:
      case STATE_RANGING_HIGH_VOL:
         confidence = (m_rangeActive ? 70 : 30) + (CountRangeTouches() * 5);
         break;

      case STATE_CHURN:
         confidence = (atrScore > 0.7 ? 70 : 30) + (adx > 40 ? 30 : 0);
         break;
      }

      return MathMin(100, MathMax(0, confidence));
   }

   //+------------------------------------------------------------------+
   //| STATE PREDICTION                                                |
   //+------------------------------------------------------------------+
   ENUM_MARKET_STATE PredictNextState(ENUM_MARKET_STATE currentState)
   {
      // State transition probabilities
      switch (currentState)
      {
      case STATE_RANGING_LOW_VOL:
         // Could compress further or expand into high volatility range
         return STATE_CONTRACTION;

      case STATE_CONTRACTION:
         // Compression leads to expansion
         return STATE_EXPANSION;

      case STATE_EXPANSION:
         // Breakout leads to trending or failed breakout leads back to range
         return STATE_TRENDING_LOW_VOL;

      case STATE_TRENDING_LOW_VOL:
         // Healthy trend matures into high volatility trend
         return STATE_TRENDING_HIGH_VOL;

      case STATE_TRENDING_HIGH_VOL:
         // Exhaustion leads to churn
         return STATE_CHURN;

      case STATE_CHURN:
         // Churn leads to new range (high vol)
         return STATE_RANGING_HIGH_VOL;

      case STATE_RANGING_HIGH_VOL:
         // High vol range stabilizes into low vol range
         return STATE_RANGING_LOW_VOL;

      default:
         return STATE_UNKNOWN;
      }
   }

   //+------------------------------------------------------------------+
   //| TRADING RECOMMENDATIONS                                         |
   //+------------------------------------------------------------------+
   void GenerateRecommendations(MarketAnalysis &analysis)
   {
      double currentPrice = iClose(m_symbol, m_timeframe, 0);
      double atr = GetATR(14);

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
         break;

      case STATE_RANGING_HIGH_VOL:
         analysis.action = "Fade carefully with tight stops";
         analysis.positionSize = SIZE_VERY_SMALL;
         analysis.stopDistance = atr * 0.8;
         analysis.takeProfitDistance = atr * 1.5;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "Neutral (dangerous)";
         break;

      case STATE_CONTRACTION:
         analysis.action = "Prepare for breakout - no trades";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (waiting)";
         break;

      case STATE_EXPANSION:
         analysis.action = "Test breakout entry";
         analysis.positionSize = SIZE_MEDIUM;
         analysis.stopDistance = atr * 1.2;
         analysis.takeProfitDistance = atr * 3.6;
         analysis.riskRewardRatio = 3.0;

         if (currentPrice > m_fixedRangeTop)
            analysis.direction = "Bullish breakout";
         else if (currentPrice < m_fixedRangeBottom)
            analysis.direction = "Bearish breakout";
         else
            analysis.direction = "Testing";
         break;

      case STATE_TRENDING_LOW_VOL:
         analysis.action = "Add to winning positions";
         analysis.positionSize = SIZE_LARGE;
         analysis.stopDistance = atr * 2.0;
         analysis.takeProfitDistance = atr * 6.0;
         analysis.riskRewardRatio = 3.0;
         analysis.direction = IsTrendingStructure() ? "With trend" : "Neutral";
         break;

      case STATE_TRENDING_HIGH_VOL:
         analysis.action = "Take partial profits";
         analysis.positionSize = SIZE_MEDIUM;
         analysis.stopDistance = atr * 1.0;
         analysis.takeProfitDistance = atr * 2.0;
         analysis.riskRewardRatio = 2.0;
         analysis.direction = "With trend (cautious)";
         break;

      case STATE_CHURN:
         analysis.action = "Exit positions, wait for clarity";
         analysis.positionSize = SIZE_ZERO;
         analysis.stopDistance = 0;
         analysis.takeProfitDistance = 0;
         analysis.riskRewardRatio = 0;
         analysis.direction = "Neutral (avoid)";
         break;
      }

      // Adjust position size based on account
      analysis.positionSize = AdjustPositionSize(analysis.positionSize);

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

      if (riskAmount < 100) // Very small account
      {
         switch (baseSize)
         {
         case SIZE_LARGE:
            return SIZE_MEDIUM;
         case SIZE_MEDIUM:
            return SIZE_SMALL;
         default:
            return baseSize;
         }
      }

      return baseSize;
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

      return validCount > 0 ? sum / validCount : 0;
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

      return desc;
   }

public:
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
   }

   // Access to IndicatorManager for other uses
   IndicatorManager *GetIndicatorManager() const { return m_indicatorManager; }

   // Method to get IndicatorManager initialization status
   bool IsIndicatorManagerInitialized() const
   {
      return (m_indicatorManager != NULL && m_indicatorManager.IsInitialized());
   }
};

//+------------------------------------------------------------------+
//| SIMPLE CHART DRAWING FUNCTIONS                                   |
//+------------------------------------------------------------------+
void DrawMarketRegime(MarketAnalysis &analysis, string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
   if (symbol == NULL)
      symbol = Symbol();

   long chartId = ChartID();

   // Remove previous drawings
   RemoveRegimeDrawings(chartId);

   // Draw fixed range if active
   MarketRegimeDetector detector(symbol, tf);
   if (detector.IsRangeActive())
   {
      double top = detector.GetRangeTop();
      double bottom = detector.GetRangeBottom();

      // Draw range lines
      DrawHorizontalLine(chartId, "Regime_Range_Top", top, clrBlue, STYLE_DASH, 2);
      DrawHorizontalLine(chartId, "Regime_Range_Bottom", bottom, clrBlue, STYLE_DASH, 2);
   }

   // Draw regime info box
   string infoText = StringFormat(
       "State: %s (%.0f%%)\n" +
           "Action: %s\n" +
           "Position: %s\n" +
           "Direction: %s\n" +
           "R/R: %.1f",
       MarketAnalysis::GetStateString(analysis.state),
       analysis.confidence,
       analysis.action,
       MarketAnalysis::GetStateString(analysis.nextLikelyState),
       analysis.direction,
       analysis.riskRewardRatio);

   DrawText(chartId, "Regime_Info", TimeCurrent() + PeriodSeconds(tf) * 15,
            iClose(symbol, tf, 0), infoText, clrWhite, 10, "Arial");

   ChartRedraw(chartId);
}

void RemoveRegimeDrawings(long chartId)
{
   int total = ObjectsTotal(chartId);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chartId, i);
      if (StringFind(name, "Regime_") == 0)
      {
         ObjectDelete(chartId, name);
      }
   }
}

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
//| GLOBAL HELPER FUNCTION                                           |
//+------------------------------------------------------------------+
MarketAnalysis GetCurrentMarketRegime(string symbol = NULL,
                                      ENUM_TIMEFRAMES tf = PERIOD_H1,
                                      bool drawOnChart = true,
                                      bool useIndicatorManager = true)
{
   static MarketRegimeDetector *detector = NULL;

   if (detector == NULL)
   {
      detector = new MarketRegimeDetector(symbol, tf, 10000, 1.0, useIndicatorManager);
   }

   MarketAnalysis analysis = detector.GetMarketRegime();

   if (drawOnChart)
   {
      DrawMarketRegime(analysis, symbol, tf);
   }

   return analysis;
}

//+------------------------------------------------------------------+
//| QUICK TEST FUNCTION                                              |
//+------------------------------------------------------------------+
void TestMarketRegime()
{
   MarketAnalysis analysis = GetCurrentMarketRegime();
   Print(analysis.ToString());
}

//+------------------------------------------------------------------+
//| ENHANCED CHART DISPLAY FUNCTIONS                                |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| SIMPLIFIED: Show range ONLY when market is ranging              |
//+------------------------------------------------------------------+
void DisplayMarketRegimeOnChart(MarketAnalysis &analysis,
                                string symbol = NULL,
                                ENUM_TIMEFRAMES tf = PERIOD_H1,
                                int corner = CORNER_RIGHT_UPPER)
{
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
      break;

   case STATE_TRENDING_LOW_VOL:
   case STATE_TRENDING_HIGH_VOL:
   case STATE_EXPANSION: // Expansion/breakout = trending
   case STATE_CHURN:     // Churn/exhaustion = unclear
   case STATE_UNKNOWN:
   default:
      shouldShowRange = false;
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
   if (detector.IsRangeActive() && shouldShowRange)
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

         // ==================== OPTIONAL: Minimal text (comment out if not wanted) ====================
         // Uncomment ONE of these options if you want minimal labels:

         // Option A: Just the price values
         // DrawTextOnChart(chartId, prefix + "RangeTopLabel",
         //                 TimeCurrent() - PeriodSeconds(tf) * 30, top,
         //                 StringFormat("%.5f", top),
         //                 clrDodgerBlue, 8, "Arial", ANCHOR_LEFT_UPPER);
         //
         // DrawTextOnChart(chartId, prefix + "RangeBottomLabel",
         //                 TimeCurrent() - PeriodSeconds(tf) * 30, bottom,
         //                 StringFormat("%.5f", bottom),
         //                 clrDodgerBlue, 8, "Arial", ANCHOR_LEFT_UPPER);

         // Option B: Simple "R" markers
         // DrawTextOnChart(chartId, prefix + "RangeTopMarker",
         //                 TimeCurrent() - PeriodSeconds(tf) * 30, top,
         //                 "R",
         //                 clrDodgerBlue, 8, "Wingdings", ANCHOR_LEFT_UPPER);
         //
         // DrawTextOnChart(chartId, prefix + "RangeBottomMarker",
         //                 TimeCurrent() - PeriodSeconds(tf) * 30, bottom,
         //                 "R",
         //                 clrDodgerBlue, 8, "Wingdings", ANCHOR_LEFT_UPPER);
      }
   }

   // If we get here and range shouldn't be shown, the RemoveAllRegimeDrawings
   // at the beginning already cleared any existing drawings

   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
//| PIXEL-BASED DRAWING FUNCTIONS (for panel)                       |
//+------------------------------------------------------------------+

void DrawTextPixel(long chartId, string name, int x, int y, string text,
                   color clr, int fontSize, string font, int corner)
{
   if (ObjectFind(chartId, name) >= 0)
      ObjectDelete(chartId, name);

   ObjectCreate(chartId, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chartId, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(chartId, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(chartId, name, OBJPROP_FONT, font);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
}

void DrawLinePixel(long chartId, string name, int x1, int y1, int x2, int y2,
                   color clr, int width)
{
   if (ObjectFind(chartId, name) >= 0)
      ObjectDelete(chartId, name);

   ObjectCreate(chartId, name, OBJ_TREND, 0, 0, 0);
   ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x1);
   ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y1);
   ObjectSetInteger(chartId, name, OBJPROP_XSIZE, x2 - x1);
   ObjectSetInteger(chartId, name, OBJPROP_YSIZE, y2 - y1);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartId, name, OBJPROP_RAY, false);
}

void DrawTextOnChart(long chartId, string name, datetime time, double price,
                     string text, color clr, int fontSize, string font,
                     ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if (ObjectFind(chartId, name) >= 0)
      ObjectDelete(chartId, name);

   ObjectCreate(chartId, name, OBJ_TEXT, 0, time, price);
   ObjectSetString(chartId, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(chartId, name, OBJPROP_FONT, font);
   ObjectSetInteger(chartId, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
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
      detector = new MarketRegimeDetector(symbol, tf, 10000, 1.0, useIndicatorManager);
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
//| TEST FUNCTIONS                                                   |
//+------------------------------------------------------------------+
void TestMarketRegimeDisplay()
{
   // Get analysis with visual display
   MarketAnalysis analysis = GetMarketRegimeWithDisplay(NULL, PERIOD_H1, true, CORNER_RIGHT_UPPER, true);

   // Also print to journal
   Print("=== MARKET REGIME ANALYSIS ===");
   Print(analysis.ToString());
   Print("==============================");
}

void CleanupMarketRegime()
{
   EventKillTimer();
   RemoveAllRegimeDrawings(ChartID(), "MarketRegime_");
   Print("Market Regime Display cleaned up");
}
//+------------------------------------------------------------------+