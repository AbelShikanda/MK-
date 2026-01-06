//+------------------------------------------------------------------+
//|                                                      MTFAnalyser  |
//|                 Multi-timeframe analysis and alignment           |
//|                   Updated to remove TradePackage dependency      |
//+------------------------------------------------------------------+

#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"
#include "IndicatorManager.mqh"

// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED_MTF = true;

// Simple debug function using Logger
void DebugLogMTF(string context, string message) {
   if(DEBUG_ENABLED_MTF) {
      Logger::Log("DEBUG-MTF-" + context, message, true, true);
   }
}
// ====================== END DEBUG SETTINGS ======================


enum TrendDirection
{
   TREND_UP,
   TREND_DOWN,
   TREND_SIDEWAYS,
   TREND_UNCLEAR
};

class MTFAnalyser
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_primaryTF;
   ENUM_TIMEFRAMES m_timeframes[7];
   double m_timeframeWeights[7];  // NEW: Weighting for each TF
   IndicatorManager *m_indicatorManager;
   bool m_initialized;
   datetime m_lastDisplayTime;
   bool m_use89EMAFilter;  // NEW: 89 EMA filter flag
   
public:
   // Module-specific data structures
   struct MTFScore
   {
      double score; // 0-100
      double weightedScore;  // Weighted score
      string summary;
      int bullishTFCount;
      int bearishTFCount;
      int neutralTFCount;
      double bullishWeightedScore;  // Weighted bullish votes
      double bearishWeightedScore;  // Weighted bearish votes
      bool alignedWithEMA89;        // Alignment with 89 EMA
      double confidence;            // Overall confidence (0-100)
      string dominantDirection;     // BULLISH, BEARISH, or NEUTRAL
   };
   
   // NEW: Direction analysis structure
   struct DirectionAnalysis
   {
      double bullishConfidence;
      double bearishConfidence;
      double neutralConfidence;
      string dominantDirection;
      bool isConflict;
   };
   
   // NEW: Trend analysis structure
   struct TrendAnalysis
   {
      
      TrendDirection trend;
      double strength;
      bool alignedWithEMA89;
   };
   
   // NEW: Full analysis result structure
   struct MTFAnalysisResult
   {
      MTFScore score;
      DirectionAnalysis direction;
      bool isAligned;
      string signalDirection;  // BUY, SELL, or HOLD
      double alignmentScore;   // Alignment percentage (0-100)
      string validationMessage;
      bool isValid;
   };
   
   // CONSTRUCTOR - ONLY sets default values, NO function calls
   MTFAnalyser()
   {
      DebugLogMTF("Constructor", "Creating MTFAnalyser instance");
      
      m_symbol = "";
      m_primaryTF = PERIOD_CURRENT;
      m_indicatorManager = NULL;
      m_initialized = false;
      m_lastDisplayTime = 0;
      m_use89EMAFilter = true;  // Enable by default
      
      // Initialize timeframe array structure only - NO function calls
      m_timeframes[0] = PERIOD_M1;
      m_timeframes[1] = PERIOD_M5;
      m_timeframes[2] = PERIOD_M15;
      m_timeframes[3] = PERIOD_M30;
      m_timeframes[4] = PERIOD_H1;
      m_timeframes[5] = PERIOD_H4;
      m_timeframes[6] = PERIOD_D1;
      
      // NEW: Initialize timeframe weights (higher TF = more weight)
      m_timeframeWeights[0] = 0.5;  // M1
      m_timeframeWeights[1] = 2.0;  // M5
      m_timeframeWeights[2] = 4.5;  // M15
      m_timeframeWeights[3] = 2.0;  // M30
      m_timeframeWeights[4] = 3.0;  // H1
      m_timeframeWeights[5] = 3.0;  // H4
      m_timeframeWeights[6] = 2.0;  // D1 (highest weight)
      
      DebugLogMTF("Constructor", "MTFAnalyser created with timeframe weights configured");
   }
   
   // DESTRUCTOR
   ~MTFAnalyser()
   {
      DebugLogMTF("Destructor", "Destroying MTFAnalyser instance");
      Deinitialize();
   }
   
   // NEW: Enable/disable 89 EMA filter
   void Use89EMAFilter(bool useFilter) { 
      m_use89EMAFilter = useFilter; 
      DebugLogMTF("Use89EMAFilter", "89 EMA filter set to: " + (useFilter ? "ENABLED" : "DISABLED"));
   }
   
   // INITIALIZE - Takes all dependencies, creates resources, sets up internal state
   bool Initialize(string symbol = NULL, ENUM_TIMEFRAMES primaryTF = PERIOD_CURRENT, 
                   IndicatorManager *indicatorManager = NULL)
   {
      DebugLogMTF("Initialize", "=== START INITIALIZATION ===");
      
      if(m_initialized)
      {
         DebugLogMTF("Initialize", "Already initialized, skipping");
         return false;
      }
      
      DebugLogMTF("Initialize", "Starting initialization...");
      
      // Set symbol
      if(symbol == NULL || symbol == "")
         m_symbol = Symbol();
      else
         m_symbol = symbol;
      
      DebugLogMTF("Initialize", "Symbol: " + m_symbol);
      
      // Validate symbol exists BEFORE doing anything else
      if(!SymbolInfoInteger(m_symbol, SYMBOL_SELECT))
      {
         DebugLogMTF("Initialize", "ERROR: Symbol " + m_symbol + " not available");
         return false;
      }
      
      // Set timeframe
      if(primaryTF == PERIOD_CURRENT)
         m_primaryTF = Period();
      else
         m_primaryTF = primaryTF;
      
      DebugLogMTF("Initialize", "Primary TF: " + IntegerToString(m_primaryTF));
      
      // Validate timeframe is valid
      if(m_primaryTF < PERIOD_M1 || m_primaryTF > PERIOD_MN1)
      {
         DebugLogMTF("Initialize", "ERROR: Invalid timeframe " + IntegerToString(m_primaryTF));
         return false;
      }
      
      // Test indicator creation first (including 89 EMA)
      DebugLogMTF("Initialize", "Testing indicator creation...");
      int test_handle = iMA(m_symbol, m_primaryTF, 9, 0, MODE_EMA, PRICE_CLOSE);
      if(test_handle == INVALID_HANDLE)
      {
         DebugLogMTF("Initialize", "ERROR: Cannot create test indicator for " + m_symbol + " on TF " + IntegerToString(m_primaryTF));
         return false;
      }
      IndicatorRelease(test_handle);
      
      // Set indicator manager
      m_indicatorManager = indicatorManager;
      
      m_initialized = true;
      m_lastDisplayTime = TimeCurrent();
      
      DebugLogMTF("Initialize", "=== INITIALIZATION COMPLETE ===");
      DebugLogMTF("Initialize", "Symbol: " + m_symbol + ", Timeframe: " + IntegerToString(m_primaryTF) + ", 89 EMA Filter: " + (m_use89EMAFilter ? "ENABLED" : "DISABLED"));
      
      return true;
   }
   
   // DEINITIALIZE - Closes/frees resources, resets flag
   void Deinitialize()
   {
      if(!m_initialized)
         return;
      
      DebugLogMTF("Deinitialize", "Deinitializing...");
      
      // Release any indicator handles if needed
      m_indicatorManager = NULL;
      m_initialized = false;
      
      DebugLogMTF("Deinitialize", "Deinitialized");
   }
   
   // Event handler for ticks - processes only if initialized
   void OnTick()
   {
      if(!m_initialized)
         return;
         
      // Optional: Update analysis on tick if needed
   }
   
   // Event handler for timer - processes only if initialized
   void OnTimer()
   {
      if(!m_initialized)
         return;
         
      // Update analysis periodically
      if(::IsStopped() || !m_initialized) return;
      
      DebugLogMTF("OnTimer", "Timer triggered");
      
      // FIXED: Call this object's own method
      MTFScore score = AnalyzeMultiTimeframe();
      DebugLogMTF("OnTimer", "Analysis complete: " + score.summary);
   }
   
   // Event handler for trade transactions - processes only if initialized
   void OnTradeTransaction(const MqlTradeTransaction& trans,
                           const MqlTradeRequest& request,
                           const MqlTradeResult& result)
   {
      if(!m_initialized)
         return;
         
      // Optional: React to trade events
   }
   
   // Display chart comment using Logger functions - RESTORED ORIGINAL
   void DisplayChartComment(const MTFScore &score)
   {
      // Only update every 2 seconds to avoid flickering
      if(TimeCurrent() - m_lastDisplayTime < 2)
         return;
         
      m_lastDisplayTime = TimeCurrent();
      
      string signal = "HOLD";
      if(score.bullishTFCount > score.bearishTFCount && score.bullishTFCount > score.neutralTFCount)
         signal = "BUY";
      else if(score.bearishTFCount > score.bullishTFCount && score.bearishTFCount > score.neutralTFCount)
         signal = "SELL";
      
      // Create a single frame display - ORIGINAL EXACTLY
      string displayText = StringFormat("MTF Analyzer: %s\nScore: %.1f%% (Weighted: %.1f%%)\nBullish: %d(%.1f) | Bearish: %d(%.1f) | Neutral: %d\n%s",
                                        signal, score.score, score.weightedScore,
                                        score.bullishTFCount, score.bullishWeightedScore,
                                        score.bearishTFCount, score.bearishWeightedScore,
                                        score.neutralTFCount,
                                        score.summary);
      
      // Use the single frame display method
      // Logger::DisplaySingleFrame(displayText);
      
      // Also log the analysis
      // Logger::Log("MTFAnalyser", StringFormat("Analysis: %s | Score: %.1f%% | Weighted: %.1f%%", 
                  // signal, score.score, score.weightedScore));
   }
   
   // NEW: Main analysis method that returns comprehensive analysis result
   MTFAnalysisResult GetAnalysis(string symbol = NULL, double minAlignmentScore = 60.0)
   {
      DebugLogMTF("GetAnalysis", "=== START COMPREHENSIVE ANALYSIS ===");
      DebugLogMTF("GetAnalysis", "Called with symbol: " + (symbol == NULL ? "NULL" : symbol) + 
                  ", minAlignmentScore: " + DoubleToString(minAlignmentScore, 1));
      
      MTFAnalysisResult result;
      result.isValid = false;
      result.validationMessage = "";
      
      if(!m_initialized)
      {
         result.validationMessage = "MTFAnalyser not initialized";
         DebugLogMTF("GetAnalysis", "ERROR: Not initialized");
         return result;
      }
      
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      DebugLogMTF("GetAnalysis", "Using symbol: " + sym);
      
      // Get MTF analysis
      result.score = AnalyzeMultiTimeframe(symbol);
      DebugLogMTF("GetAnalysis", "MTF Analysis results:");
      DebugLogMTF("GetAnalysis", StringFormat("  Score: %.1f%%, Weighted: %.1f%%", 
                  result.score.score, result.score.weightedScore));
      DebugLogMTF("GetAnalysis", StringFormat("  Bullish: %d (Weighted: %.1f)", 
                  result.score.bullishTFCount, result.score.bullishWeightedScore));
      DebugLogMTF("GetAnalysis", StringFormat("  Bearish: %d (Weighted: %.1f)", 
                  result.score.bearishTFCount, result.score.bearishWeightedScore));
      DebugLogMTF("GetAnalysis", StringFormat("  Neutral: %d", result.score.neutralTFCount));
      
      // Get direction analysis
      result.direction = GetDirectionAnalysis(result.score);
      DebugLogMTF("GetAnalysis", "Direction analysis:");
      DebugLogMTF("GetAnalysis", StringFormat("  Dominant: %s, Conflict: %s", 
                  result.direction.dominantDirection, 
                  result.direction.isConflict ? "YES" : "NO"));
      DebugLogMTF("GetAnalysis", StringFormat("  Bullish: %.1f%%, Bearish: %.1f%%, Neutral: %.1f%%", 
                  result.direction.bullishConfidence, 
                  result.direction.bearishConfidence,
                  result.direction.neutralConfidence));
      
      // Check 89 EMA alignment
      result.score.alignedWithEMA89 = Check89EMAAlignment(symbol);
      DebugLogMTF("GetAnalysis", "89 EMA alignment: " + (result.score.alignedWithEMA89 ? "ALIGNED" : "NOT ALIGNED"));
      
      // Calculate overall confidence
      result.score.confidence = CalculateOverallConfidence(result.score, result.direction);
      DebugLogMTF("GetAnalysis", "Overall confidence: " + DoubleToString(result.score.confidence, 1) + "%");
      
      // Determine signal direction
      result.signalDirection = GetSignalDirection(result.score);
      DebugLogMTF("GetAnalysis", "Signal direction: " + result.signalDirection);
      
      // Check alignment
      result.alignmentScore = result.score.weightedScore;
      result.isAligned = (result.alignmentScore >= minAlignmentScore);
      DebugLogMTF("GetAnalysis", StringFormat("Alignment: Score=%.1f%%, MinRequired=%.1f%%, IsAligned=%s", 
                  result.alignmentScore, minAlignmentScore, result.isAligned ? "YES" : "NO"));
      
      // Apply 89 EMA filter if enabled
      if(m_use89EMAFilter && !result.score.alignedWithEMA89)
      {
         // Apply confidence penalty for counter-trend
         double originalConfidence = result.score.confidence;
         result.score.confidence *= 0.9; // 10% reduction
         result.validationMessage = StringFormat("%s signal (%.1f%%) - Counter-trend (EMA not aligned, -10%%)", 
                                               result.signalDirection, result.score.confidence);
         DebugLogMTF("GetAnalysis", StringFormat("Counter-trend: Confidence reduced from %.1f%% to %.1f%% (-10%%)", 
                     originalConfidence, result.score.confidence));
      }
      else if(m_use89EMAFilter && result.score.alignedWithEMA89)
      {
         // Apply confidence boost for with-trend
         double originalConfidence = result.score.confidence;
         result.score.confidence = MathMin(result.score.confidence * 1.05, 100.0); // 5% boost, max 100%
         result.validationMessage = StringFormat("Valid %s signal (%.1f%%) - With-trend (EMA aligned, +5%%)", 
                                               result.signalDirection, result.score.confidence);
         DebugLogMTF("GetAnalysis", StringFormat("With-trend: Confidence boosted from %.1f%% to %.1f%% (+5%%)", 
                     originalConfidence, result.score.confidence));
      }
      else
      {
         result.validationMessage = StringFormat("%s signal (%.1f%%)", 
                                               result.signalDirection, result.score.confidence);
      }
      
      // Set dominant direction
      result.score.dominantDirection = GetMTFDirection(result.score);
      
      // Final validation
      result.isValid = (result.score.confidence >= minAlignmentScore);
      if(!result.isValid)
      {
         result.validationMessage = StringFormat("Confidence too low: %.1f%% < %.1f%%", 
                                               result.score.confidence, minAlignmentScore);
         DebugLogMTF("GetAnalysis", "Analysis invalid: " + result.validationMessage);
      }
      else
      {
         DebugLogMTF("GetAnalysis", "Analysis valid: " + result.validationMessage);
      }
      
      DebugLogMTF("GetAnalysis", "=== ANALYSIS COMPLETE ===");
      DebugLogMTF("GetAnalysis", "Returning result - isValid=" + (result.isValid ? "true" : "false") + 
                  ", confidence=" + DoubleToString(result.score.confidence, 1) + "%");
      
      return result;
   }
   
   // NEW: Helper method to get raw MTF score (backward compatibility)
   MTFScore AnalyzeMultiTimeframe(string symbol = NULL)
   {
      DebugLogMTF("AnalyzeMultiTimeframe", "=== START RAW MTF ANALYSIS ===");
      
      if(!m_initialized)
      {
         DebugLogMTF("AnalyzeMultiTimeframe", "ERROR: Not initialized");
         MTFScore errorScore;
         InitializeScore(errorScore);
         errorScore.summary = "Not initialized";
         return errorScore;
      }
      
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      DebugLogMTF("AnalyzeMultiTimeframe", "Analyzing symbol: " + sym);
      
      MTFScore score;
      InitializeScore(score);
      
      int totalTF = ArraySize(m_timeframes);
      DebugLogMTF("AnalyzeMultiTimeframe", "Total timeframes to analyze: " + IntegerToString(totalTF));
      
      double weightedBullish = 0;
      double weightedBearish = 0;
      double weightedNeutral = 0;
      double totalWeight = 0;
      int analyzedTF = 0;
      
      // Add timeout protection
      uint startTime = GetTickCount();
      const uint TIMEOUT_MS = 10000; // 10 second timeout
      
      for(int i = 0; i < totalTF; i++)
      {
         // Check timeout
         if(GetTickCount() - startTime > TIMEOUT_MS)
         {
            DebugLogMTF("AnalyzeMultiTimeframe", "WARNING: Analysis timeout after " + IntegerToString(GetTickCount() - startTime) + " ms");
            score.summary = "Analysis timeout";
            break;
         }
         
         if(::IsStopped()) 
         {
            DebugLogMTF("AnalyzeMultiTimeframe", "EA is stopping, aborting analysis");
            break;
         }
         
         ENUM_TIMEFRAMES currentTF = m_timeframes[i];
         double weight = m_timeframeWeights[i];
         DebugLogMTF("AnalyzeMultiTimeframe", "Analyzing timeframe " + IntegerToString(currentTF) + " (" + IntegerToString(i+1) + "/" + IntegerToString(totalTF) + "), weight=" + DoubleToString(weight, 1));
         
         // Get trend with 89 EMA consideration
         TrendAnalysis trendAnalysis = AnalyzeTrendWithEMA89(sym, currentTF);
         
         if(trendAnalysis.trend == TREND_UNCLEAR)
         {
            DebugLogMTF("AnalyzeMultiTimeframe", "TF " + IntegerToString(currentTF) + ": Unclear trend, skipping");
            continue;
         }
         
         totalWeight += weight;
         analyzedTF++;
         
         switch(trendAnalysis.trend)
         {
            case TREND_UP:
               score.bullishTFCount++;
               weightedBullish += weight;
               score.bullishWeightedScore += weight * trendAnalysis.strength;
               DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("TF %d: BULLISH (Strength: %.1f, Weight: %.1f, Contribution: %.1f)", 
                           currentTF, trendAnalysis.strength, weight, weight * trendAnalysis.strength));
               break;
            case TREND_DOWN:
               score.bearishTFCount++;
               weightedBearish += weight;
               score.bearishWeightedScore += weight * trendAnalysis.strength;
               DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("TF %d: BEARISH (Strength: %.1f, Weight: %.1f, Contribution: %.1f)", 
                           currentTF, trendAnalysis.strength, weight, weight * trendAnalysis.strength));
               break;
            case TREND_SIDEWAYS:
               score.neutralTFCount++;
               weightedNeutral += weight;
               DebugLogMTF("AnalyzeMultiTimeframe", "TF " + IntegerToString(currentTF) + ": NEUTRAL/SIDEWAYS (Weight: " + DoubleToString(weight, 1) + ")");
               break;
         }
      }
      
      DebugLogMTF("AnalyzeMultiTimeframe", "Analysis summary:");
      DebugLogMTF("AnalyzeMultiTimeframe", "  Analyzed TFs: " + IntegerToString(analyzedTF) + "/" + IntegerToString(totalTF));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Bullish: %d (Weighted: %.1f)", score.bullishTFCount, weightedBullish));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Bearish: %d (Weighted: %.1f)", score.bearishTFCount, weightedBearish));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Neutral: %d (Weighted: %.1f)", score.neutralTFCount, weightedNeutral));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Total weight: %.1f", totalWeight));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Bullish weighted score: %.1f", score.bullishWeightedScore));
      DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("  Bearish weighted score: %.1f", score.bearishWeightedScore));
      
      // Calculate both regular and weighted alignment scores (0-100)
      if(analyzedTF > 0 && totalWeight > 0)
      {
         double alignment = 0;
         int dominantCount = MathMax(score.bullishTFCount, 
                                    MathMax(score.bearishTFCount, score.neutralTFCount));
         
         if(dominantCount > 0)
         {
            alignment = (double)dominantCount / analyzedTF * 100;
            DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("Dominant count: %d/%d = %.1f%% alignment", 
                        dominantCount, analyzedTF, alignment));
            
            // Penalize mixed signals
            if(score.bullishTFCount > 0 && score.bearishTFCount > 0)
            {
               alignment *= 0.7; // 30% penalty for conflicting signals
               DebugLogMTF("AnalyzeMultiTimeframe", "Mixed signals detected - applying 30%% penalty");
            }
         }
         
         score.score = alignment;
         
         // Calculate weighted score
         double weightedDominant = MathMax(weightedBullish, 
                                         MathMax(weightedBearish, weightedNeutral));
         double weightedAlignment = (weightedDominant / totalWeight) * 100;
         DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("Weighted dominant: %.1f/%.1f = %.1f%% weighted alignment", 
                     weightedDominant, totalWeight, weightedAlignment));
         
         // Penalize mixed signals in weighted score too
         if(weightedBullish > 0 && weightedBearish > 0)
         {
            weightedAlignment *= 0.7;
            DebugLogMTF("AnalyzeMultiTimeframe", "Weighted mixed signals - applying 30%% penalty");
         }
         
         score.weightedScore = weightedAlignment;
         
         DebugLogMTF("AnalyzeMultiTimeframe", StringFormat("Final scores: Regular=%.1f%%, Weighted=%.1f%%", 
                     score.score, score.weightedScore));
      }
      else
      {
         score.score = 0;
         score.weightedScore = 0;
         DebugLogMTF("AnalyzeMultiTimeframe", "ERROR: No timeframes could be analyzed");
      }
      
      // Generate summary with weighted score
      score.summary = StringFormat("Bullish: %d(%.1f), Bearish: %d(%.1f), Neutral: %d | Score: %.1f%% (Weighted: %.1f%%)",
                                   score.bullishTFCount, weightedBullish,
                                   score.bearishTFCount, weightedBearish,
                                   score.neutralTFCount, score.score, score.weightedScore);
      
      DebugLogMTF("AnalyzeMultiTimeframe", "Analysis complete: " + score.summary);
      DebugLogMTF("AnalyzeMultiTimeframe", "=== RAW MTF ANALYSIS COMPLETE in " + IntegerToString(GetTickCount() - startTime) + " ms ===");
      
      return score;
   }
   
   // NEW: Get direction analysis from MTFScore
   DirectionAnalysis GetDirectionAnalysis(const MTFScore &score)
   {
      DirectionAnalysis analysis;
      
      int totalTFs = score.bullishTFCount + score.bearishTFCount + score.neutralTFCount;
      
      if(totalTFs == 0)
      {
         analysis.bullishConfidence = 0;
         analysis.bearishConfidence = 0;
         analysis.neutralConfidence = 100;
         analysis.dominantDirection = "NEUTRAL";
         analysis.isConflict = false;
         return analysis;
      }
      
      // Calculate confidence percentages
      analysis.bullishConfidence = (double)score.bullishTFCount / totalTFs * 100;
      analysis.bearishConfidence = (double)score.bearishTFCount / totalTFs * 100;
      analysis.neutralConfidence = (double)score.neutralTFCount / totalTFs * 100;
      
      // Adjust with weighted scores if available
      double totalWeighted = score.bullishWeightedScore + score.bearishWeightedScore;
      if(totalWeighted > 0)
      {
         analysis.bullishConfidence = score.bullishWeightedScore / totalWeighted * 100;
         analysis.bearishConfidence = score.bearishWeightedScore / totalWeighted * 100;
      }
      
      // Determine dominant direction
      if(analysis.bullishConfidence > analysis.bearishConfidence && 
         analysis.bullishConfidence > analysis.neutralConfidence)
      {
         analysis.dominantDirection = "BULLISH";
      }
      else if(analysis.bearishConfidence > analysis.bullishConfidence && 
              analysis.bearishConfidence > analysis.neutralConfidence)
      {
         analysis.dominantDirection = "BEARISH";
      }
      else
      {
         analysis.dominantDirection = "NEUTRAL";
      }
      
      // Check for conflict (both bullish and bearish have significant presence)
      analysis.isConflict = (analysis.bullishConfidence >= 30.0 && analysis.bearishConfidence >= 30.0);
      
      DebugLogMTF("GetDirectionAnalysis", 
                  StringFormat("Direction Analysis: Bullish %.1f%%, Bearish %.1f%%, Neutral %.1f%%, Dominant: %s, Conflict: %s",
                  analysis.bullishConfidence, analysis.bearishConfidence,
                  analysis.neutralConfidence, analysis.dominantDirection,
                  analysis.isConflict ? "YES" : "NO"));
      
      return analysis;
   }
   
   // NEW: Check if aligned with 89 EMA trend - UPDATED to use IndicatorManager
   bool Check89EMAAlignment(string symbol = NULL)
   {
      if(!m_use89EMAFilter || !m_initialized || !m_indicatorManager)
      {
         DebugLogMTF("Check89EMAAlignment", "Filter disabled or not initialized, returning true");
         return true;
      }
      
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      DebugLogMTF("Check89EMAAlignment", "Checking 89 EMA alignment for " + sym);
      
      // Get D1 MA values from IndicatorManager
      double ma9, ma21, ma89;
      if(!m_indicatorManager.GetMAValues(PERIOD_D1, ma9, ma21, ma89))
      {
         DebugLogMTF("Check89EMAAlignment", "Failed to get MA values from IndicatorManager");
         return false;
      }
      
      double d1_price = iClose(sym, PERIOD_D1, 0);
      
      if(ma89 == EMPTY_VALUE || d1_price == 0)
      {
         DebugLogMTF("Check89EMAAlignment", "Invalid data: ma89=" + (ma89 == EMPTY_VALUE ? "EMPTY" : "VALID") + 
                     ", price=" + DoubleToString(d1_price, 4));
         return false;
      }
      
      bool d1_bullish = (d1_price > ma89);
      DebugLogMTF("Check89EMAAlignment", StringFormat("D1 Price=%.4f, 89EMA=%.4f, D1 is %s", 
                  d1_price, ma89, d1_bullish ? "BULLISH (above)" : "BEARISH (below)"));
      
      // Get MTF direction
      MTFScore score = AnalyzeMultiTimeframe(sym);
      bool mtf_bullish = (score.bullishTFCount > score.bearishTFCount);
      DebugLogMTF("Check89EMAAlignment", "MTF is " + (mtf_bullish ? "BULLISH" : "BEARISH") + 
                  " (Bullish: " + IntegerToString(score.bullishTFCount) + 
                  ", Bearish: " + IntegerToString(score.bearishTFCount) + ")");
      
      bool aligned = (d1_bullish && mtf_bullish) || (!d1_bullish && !mtf_bullish);
      DebugLogMTF("Check89EMAAlignment", "Alignment result: " + (aligned ? "ALIGNED" : "NOT ALIGNED"));
      
      return aligned;
   }
   
   // Check if timeframes are aligned (using weighted score)
   bool CheckAlignment(string symbol = NULL, double minScore = 60.0)
   {
      if(!m_initialized)
      {
         DebugLogMTF("CheckAlignment", "ERROR: Cannot check alignment - not initialized");
         return false;
      }
      
      DebugLogMTF("CheckAlignment", "Checking alignment with min score: " + DoubleToString(minScore, 1));
      MTFScore score = AnalyzeMultiTimeframe(symbol);
      
      // NEW: Use weighted score for alignment check
      bool aligned = score.weightedScore >= minScore;
      DebugLogMTF("CheckAlignment", StringFormat("Weighted score: %.1f >= %.1f = %s", 
                  score.weightedScore, minScore, aligned ? "ALIGNED" : "NOT ALIGNED"));
      
      // NEW: Apply 89 EMA filter if enabled
      if(m_use89EMAFilter && aligned)
      {
         aligned = Check89EMAAlignment(symbol);
         DebugLogMTF("CheckAlignment", "After 89 EMA filter: " + (aligned ? "ALIGNED" : "NOT ALIGNED"));
         if(!aligned)
            DebugLogMTF("CheckAlignment", "Alignment failed 89 EMA filter");
      }
      
      DebugLogMTF("CheckAlignment", "Final alignment result: " + (aligned ? "ALIGNED" : "NOT ALIGNED"));
      
      return aligned;
   }
   
   // Get dominant timeframe - UPDATED
   ENUM_TIMEFRAMES GetDominantTF(string symbol = NULL)
   {
      if(!m_initialized || !m_indicatorManager)
      {
         DebugLogMTF("GetDominantTF", "Not initialized or no IndicatorManager");
         return PERIOD_CURRENT;
      }
      
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      DebugLogMTF("GetDominantTF", "Finding dominant TF for " + sym);
      
      // Analyze trends on all timeframes
      double trendStrengths[7] = {0, 0, 0, 0, 0, 0, 0};
      int validTFs = 0;
      
      uint startTime = GetTickCount();
      const uint TIMEOUT_MS = 5000; // 5 second timeout
      
      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         // Check timeout
         if(GetTickCount() - startTime > TIMEOUT_MS)
         {
            DebugLogMTF("GetDominantTF", "Timeout after " + IntegerToString(GetTickCount() - startTime) + " ms");
            break;
         }
         
         if(::IsStopped()) break;
         
         TrendAnalysis trendAnalysis = AnalyzeTrendWithEMA89(sym, m_timeframes[i]);
         
         if(trendAnalysis.trend == TREND_UNCLEAR)
         {
            trendStrengths[i] = 0;
            continue;
         }
         
         // Use the strength from AnalyzeTrendWithEMA89 (already calculated)
         trendStrengths[i] = trendAnalysis.strength * m_timeframeWeights[i];
         validTFs++;
         DebugLogMTF("GetDominantTF", StringFormat("TF %d: Strength=%.1f, Weight=%.1f, Weighted=%.1f", 
                     m_timeframes[i], trendAnalysis.strength, m_timeframeWeights[i], trendStrengths[i]));
      }
      
      if(validTFs == 0)
      {
         DebugLogMTF("GetDominantTF", "No valid TFs analyzed");
         return PERIOD_CURRENT;
      }
      
      // Find timeframe with strongest trend (weighted)
      int strongestIndex = 0;
      double strongestStrength = 0;
      
      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         if(trendStrengths[i] > strongestStrength)
         {
            strongestStrength = trendStrengths[i];
            strongestIndex = i;
         }
      }
      
      DebugLogMTF("GetDominantTF", "Dominant TF: " + IntegerToString(m_timeframes[strongestIndex]) + 
                  " (Strength: " + DoubleToString(strongestStrength, 1) + ")");
      
      return m_timeframes[strongestIndex];
   }
   
   // NEW: Get trend analysis for specific timeframe
   TrendAnalysis GetTrendAnalysis(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
   {
      if(!m_initialized)
      {
         DebugLogMTF("GetTrendAnalysis", "Not initialized");
         TrendAnalysis errorAnalysis;
         errorAnalysis.trend = TREND_UNCLEAR;
         errorAnalysis.strength = 0;
         errorAnalysis.alignedWithEMA89 = false;
         return errorAnalysis;
      }
      
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      if(timeframe == PERIOD_CURRENT) timeframe = m_primaryTF;
      
      return AnalyzeTrendWithEMA89(sym, timeframe);
   }
   
   // Get current initialization status
   bool IsInitialized() const { return m_initialized; }
   
   // Get current symbol
   string GetSymbol() const { return m_symbol; }
   
   // Get primary timeframe
   ENUM_TIMEFRAMES GetPrimaryTF() const { return m_primaryTF; }
   
   // Get if 89 EMA filter is enabled
   bool Is89EMAFilterEnabled() const { return m_use89EMAFilter; }

private:
   // Helper method to analyze trend with 89 EMA consideration
   TrendAnalysis AnalyzeTrendWithEMA89(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      DebugLogMTF("AnalyzeTrendWithEMA89", "Analyzing trend for " + symbol + " on TF " + IntegerToString(timeframe));
      
      TrendAnalysis analysis;
      analysis.trend = TREND_UNCLEAR;
      analysis.strength = 0;
      analysis.alignedWithEMA89 = true;
      
      // Get basic trend
      TrendDirection basicTrend = AnalyzeTrend(symbol, timeframe);
      analysis.trend = basicTrend;
      
      DebugLogMTF("AnalyzeTrendWithEMA89", "Basic trend: " + 
                  (basicTrend == TREND_UP ? "UP" : 
                   basicTrend == TREND_DOWN ? "DOWN" : 
                   basicTrend == TREND_SIDEWAYS ? "SIDEWAYS" : "UNCLEAR"));
      
      // Calculate trend strength using MA separation (always calculate this)
      if(m_indicatorManager && m_indicatorManager.IsInitialized())
      {
         double ma9, ma21, ma89;
         if(m_indicatorManager.GetMAValues(timeframe, ma9, ma21, ma89))
         {
            double price = iClose(symbol, timeframe, 0);
            if(price > 0 && ma9 != EMPTY_VALUE && ma21 != EMPTY_VALUE && ma89 != EMPTY_VALUE)
            {
               // Strength based on MA separation (0-100 scale)
               double spread_9_21 = MathAbs(ma9 - ma21) / price;
               double spread_21_89 = MathAbs(ma21 - ma89) / price;
               
               // Base strength from MA separation
               double baseStrength = (spread_9_21 + spread_21_89) * 2500; // Scale to 0-100
               
               // Boost strength if MAs are aligned
               if((ma9 > ma21 && ma21 > ma89) || (ma9 < ma21 && ma21 < ma89))
               {
                  baseStrength *= 1.5; // 50% boost for alignment
                  DebugLogMTF("AnalyzeTrendWithEMA89", "MAs aligned - 50%% strength boost");
               }
               
               analysis.strength = MathMin(100.0, baseStrength);
               DebugLogMTF("AnalyzeTrendWithEMA89", StringFormat("MA spreads: 9-21=%.6f, 21-89=%.6f, Base strength=%.1f", 
                           spread_9_21, spread_21_89, analysis.strength));
               
               // Check 89 EMA alignment if enabled
               if(m_use89EMAFilter)
               {
                  bool aboveEMA89 = (price > ma89);
                  bool trendBullish = (basicTrend == TREND_UP);
                  
                  analysis.alignedWithEMA89 = (aboveEMA89 && trendBullish) || (!aboveEMA89 && !trendBullish);
                  
                  DebugLogMTF("AnalyzeTrendWithEMA89", StringFormat("Price=%.4f, 89EMA=%.4f, AboveEMA89=%s, TrendBullish=%s, Aligned=%s", 
                              price, ma89, aboveEMA89 ? "YES" : "NO", 
                              trendBullish ? "YES" : "NO", analysis.alignedWithEMA89 ? "YES" : "NO"));
                  
                  if(!analysis.alignedWithEMA89)
                  {
                     // Reduce strength if not aligned with 89 EMA
                     analysis.strength *= 0.5;
                     DebugLogMTF("AnalyzeTrendWithEMA89", "Not aligned with 89 EMA - 50%% strength penalty");
                  }
               }
            }
            else
            {
               DebugLogMTF("AnalyzeTrendWithEMA89", StringFormat("Invalid data: price=%.4f, ma9=%s, ma21=%s, ma89=%s", 
                           price, ma9 == EMPTY_VALUE ? "EMPTY" : "VALID",
                           ma21 == EMPTY_VALUE ? "EMPTY" : "VALID",
                           ma89 == EMPTY_VALUE ? "EMPTY" : "VALID"));
            }
         }
         else
         {
            DebugLogMTF("AnalyzeTrendWithEMA89", "Failed to get MA values from IndicatorManager");
         }
      }
      else
      {
         DebugLogMTF("AnalyzeTrendWithEMA89", "No IndicatorManager available");
      }
      
      DebugLogMTF("AnalyzeTrendWithEMA89", "Final analysis: Trend=" + 
                  (analysis.trend == TREND_UP ? "UP" : 
                   analysis.trend == TREND_DOWN ? "DOWN" : 
                   analysis.trend == TREND_SIDEWAYS ? "SIDEWAYS" : "UNCLEAR") +
                  ", Strength=" + DoubleToString(analysis.strength, 1) + 
                  ", EMA89Aligned=" + (analysis.alignedWithEMA89 ? "YES" : "NO"));
      
      return analysis;
   }
   
   TrendDirection AnalyzeTrend(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      DebugLogMTF("AnalyzeTrend", "Analyzing basic trend for " + symbol + " on TF " + IntegerToString(timeframe));
      
      // Validate timeframe first
      if(timeframe < PERIOD_M1 || timeframe > PERIOD_MN1)
      {
         DebugLogMTF("AnalyzeTrend", "ERROR: Invalid timeframe " + IntegerToString(timeframe));
         return TREND_UNCLEAR;
      }
      
      // Check if we have enough bars
      int minBars = 100;
      if(timeframe <= PERIOD_M5) minBars = 200;
      if(timeframe <= PERIOD_M1) minBars = 300;
      
      int bars = iBars(symbol, timeframe);
      if(bars < minBars)
      {
         DebugLogMTF("AnalyzeTrend", "Insufficient bars: " + IntegerToString(bars) + " < " + IntegerToString(minBars));
         return TREND_UNCLEAR;
      }
      
      // ============================================
      // UPDATED: Use IndicatorManager instead of creating own handles
      // ============================================
      if(!m_indicatorManager || !m_indicatorManager.IsInitialized())
      {
         DebugLogMTF("AnalyzeTrend", "No IndicatorManager available");
         return TREND_UNCLEAR;
      }
      
      // Get MA values from IndicatorManager
      double ma9, ma21, ma89;
      if(!m_indicatorManager.GetMAValues(timeframe, ma9, ma21, ma89))
      {
         DebugLogMTF("AnalyzeTrend", "Failed to get MA values from IndicatorManager");
         return TREND_UNCLEAR;
      }
      
      double currentClose = iClose(symbol, timeframe, 0);
      
      if(currentClose == 0 || ma9 == EMPTY_VALUE || ma21 == EMPTY_VALUE)
      {
         DebugLogMTF("AnalyzeTrend", StringFormat("Invalid data: Close=%.4f, MA9=%s, MA21=%s", 
                     currentClose, ma9 == EMPTY_VALUE ? "EMPTY" : "VALID",
                     ma21 == EMPTY_VALUE ? "EMPTY" : "VALID"));
         return TREND_UNCLEAR;
      }
      
      DebugLogMTF("AnalyzeTrend", StringFormat("Data: Close=%.4f, MA9=%.4f, MA21=%.4f", currentClose, ma9, ma21));
      
      // Use MA9 and MA21 for trend analysis (from IndicatorManager)
      if(ma9 > ma21 && currentClose > ma9)
      {
         DebugLogMTF("AnalyzeTrend", "Trend: UP (MA9 > MA21 and Price > MA9)");
         return TREND_UP;
      }
      
      if(ma9 < ma21 && currentClose < ma21)
      {
         DebugLogMTF("AnalyzeTrend", "Trend: DOWN (MA9 < MA21 and Price < MA21)");
         return TREND_DOWN;
      }
      
      DebugLogMTF("AnalyzeTrend", "Trend: SIDEWAYS");
      return TREND_SIDEWAYS;
   }
   
   // Helper method to initialize MTFScore structure
   void InitializeScore(MTFScore &score)
   {
      score.score = 0;
      score.weightedScore = 0;
      score.bullishTFCount = 0;
      score.bearishTFCount = 0;
      score.neutralTFCount = 0;
      score.bullishWeightedScore = 0;
      score.bearishWeightedScore = 0;
      score.alignedWithEMA89 = false;
      score.confidence = 0;
      score.dominantDirection = "NEUTRAL";
      score.summary = "";
   }
   
   // Helper method to calculate overall confidence
   double CalculateOverallConfidence(const MTFScore &score, const DirectionAnalysis &direction)
   {
      double confidence = score.weightedScore;
      
      // Boost confidence if direction is clear
      if(direction.dominantDirection == "BULLISH" || direction.dominantDirection == "BEARISH")
      {
         if(!direction.isConflict)
         {
            confidence *= 1.1; // 10% boost for clear direction
            DebugLogMTF("CalculateOverallConfidence", "Clear direction - 10% boost");
         }
      }
      
      // Penalize for mixed signals
      if(score.bullishTFCount > 0 && score.bearishTFCount > 0)
      {
         confidence *= 0.8; // 20% penalty for mixed signals
         DebugLogMTF("CalculateOverallConfidence", "Mixed signals - 20% penalty");
      }
      
      // Cap at 100%
      return MathMin(confidence, 100.0);
   }
   
   // Helper method to get MTF direction
   string GetMTFDirection(const MTFScore &score)
   {
      if(score.bullishWeightedScore > score.bearishWeightedScore) return "BULLISH";
      if(score.bearishWeightedScore > score.bullishWeightedScore) return "BEARISH";
      return "NEUTRAL";
   }
   
   // Helper method to get signal direction
   string GetSignalDirection(const MTFScore &score)
   {
      if(score.bullishTFCount > score.bearishTFCount && score.bullishTFCount > score.neutralTFCount)
         return "BUY";
      if(score.bearishTFCount > score.bullishTFCount && score.bearishTFCount > score.neutralTFCount)
         return "SELL";
      return "HOLD";
   }
};