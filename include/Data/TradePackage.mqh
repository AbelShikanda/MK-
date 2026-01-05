//+------------------------------------------------------------------+
//|                                                      TradePackage|
//|                 Central DATA STRUCTURE ONLY                     |
//|                 NO MODULE INSTANCES - NO INITIALIZATION         |
//+------------------------------------------------------------------+

#include "../Headers/Enums.mqh"
#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"
#include "../Utils/TimeUtils.mqh"


struct POIModuleSignal;

// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED_TP = true;

void DebugLogTP(string context, string message) {
   if(DEBUG_ENABLED_TP) {
      Logger::Log("DEBUG-TP-" + context, message, true, true);
   }
}

// ====================== DATA STRUCTURES ONLY ======================

// Volume Analysis structure
struct VolumeAnalysis {
   double momentumScore;
   double convictionScore;
   string prediction;
   bool divergence;
   bool climax;
   string volumeStatus;
   double volumeRatio;
   double bullishScore;
   double bearishScore;
   string bias;
   double confidence;
   bool hasWarning;
   
   VolumeAnalysis() {
      momentumScore = 0;
      convictionScore = 0;
      prediction = "NEUTRAL";
      divergence = false;
      climax = false;
      volumeStatus = "NORMAL";
      volumeRatio = 1.0;
      bullishScore = 0;
      bearishScore = 0;
      bias = "NEUTRAL";
      confidence = 0;
      hasWarning = false;
   }
};

// RSI Analysis structure
struct RSIAnalysis {
   double bullishBias;
   double bearishBias;
   double netBias;
   double confidence;
   string biasText;
   string rsiLevel;
   double currentRSI;
   
   RSIAnalysis() {
      bullishBias = 50.0;
      bearishBias = 50.0;
      netBias = 0.0;
      confidence = 0.0;
      biasText = "NEUTRAL";
      rsiLevel = "NEUTRAL";
      currentRSI = 50.0;
   }
};

// MACD Analysis structure
struct MACDAnalysis {
   string bias;
   double score;
   double confidence;
   string signalType;
   double macdValue;
   double signalValue;
   double histogramValue;
   double histogramSlope;
   bool isAboveZero;
   bool isCrossover;
   bool isDivergence;
   bool isStrongSignal;
   
   MACDAnalysis() {
      bias = "NEUTRAL";
      score = 0;
      confidence = 0;
      signalType = "NONE";
      macdValue = 0;
      signalValue = 0;
      histogramValue = 0;
      histogramSlope = 0;
      isAboveZero = false;
      isCrossover = false;
      isDivergence = false;
      isStrongSignal = false;
   }
};

// Pattern Analysis structure
struct PatternAnalysis {
   string patternName;
   string direction;
   double confidence;
   string description;
   bool isConfirmed;
   double targetPrice;
   double stopLoss;
   double riskRewardRatio;
   
   PatternAnalysis() {
      patternName = "NONE";
      direction = "NEUTRAL";
      confidence = 0;
      description = "";
      isConfirmed = false;
      targetPrice = 0;
      stopLoss = 0;
      riskRewardRatio = 0;
   }
};

// MTF-specific data
struct MTFData {
   double score;
   double weightedScore;
   int bullishCount;
   int bearishCount;
   int neutralCount;
   double bullishWeightedScore;
   double bearishWeightedScore;
   bool alignedWithEMA89;
   double confidence;
   
   string GetAlignmentString() const {
      string alignment = StringFormat("B:%d/S:%d/N:%d", bullishCount, bearishCount, neutralCount);
      if(bullishWeightedScore > 0 || bearishWeightedScore > 0) {
         alignment += StringFormat(" (WB:%.1f/WS:%.1f)", bullishWeightedScore, bearishWeightedScore);
      }
      return alignment;
   }
};

// In TradePackage.mqh - SIMPLIFIED POISignal (no conversion constructor)
struct POISignal {
   string overallBias;
   string zoneBias;
   double score;
   double confidence;
   int nearestZoneType;
   double distanceToZone;
   double zoneStrength;
   double zoneRelevance;
   string priceAction;
   int zonesInFavor;
   int zonesAgainst;
   
   POISignal() {
      overallBias = "NEUTRAL";
      zoneBias = "NEUTRAL";
      score = 0;
      confidence = 0;
      nearestZoneType = 0;
      distanceToZone = 9999.0;
      zoneStrength = 0;
      zoneRelevance = 0;
      priceAction = "";
      zonesInFavor = 0;
      zonesAgainst = 0;
   }
   
   // NO CONVERSION CONSTRUCTOR NEEDED
   
   string GetSimpleSignal() const {
      if(overallBias == "BULLISH") return "BUY";
      if(overallBias == "BEARISH") return "SELL";
      return "HOLD";
   }
   
   string GetConfidenceString() const {
      return StringFormat("%.0f%%", confidence);
   }
   
   bool IsActionable() const {
      return (overallBias != "NEUTRAL" && confidence > 60 && score > 50);
   }
   
   string GetDisplayString() const {
      return StringFormat("%s | Score: %.0f | Conf: %.0f%% | Dist: $%.2f", 
            overallBias, score, confidence, distanceToZone);
   }
};

// Component display structure
struct ComponentDisplay {
   string name;
   string direction;
   double strength;
   double confidence;
   double weight;
   bool isActive;
   string details;
   
   ComponentDisplay() {
      name = "";
      direction = "NEUTRAL";
      strength = 0;
      confidence = 0;
      weight = 0;
      isActive = false;
      details = "";
   }
   
   ComponentDisplay(string n, string d, double s, double c, double w, bool a, string dt = "") {
      name = n;
      direction = d;
      strength = s;
      confidence = c;
      weight = w;
      isActive = a;
      details = dt;
   }
   
   string GetFormattedLine(bool useIcons = true, bool showDetails = false) {
        string dirIcon = GetDirectionIcon(direction, useIcons);
        string activeIcon = isActive ? "•" : " ";
        
        string baseLine = StringFormat("%s %s: %s %3.0f%% (C:%3.0f%%, W:%3.0f%%)",
            activeIcon,
            StringSubstr(name, 0, 3),
            dirIcon,
            strength,
            confidence,
            weight);
        
        if(showDetails && details != "") {
            baseLine += StringFormat(" | %s", details);
        }
        
        return baseLine;
    }
   
private:
   string GetDirectionIcon(string dir, bool useIcons) {
      if(dir == "BULLISH") return "▲";  
      if(dir == "BEARISH") return "▼";  
      return "●";                          
   }
};

// Direction Analysis structure
struct DirectionAnalysis {
   double bullishConfidence;
   double bearishConfidence;
   double neutralConfidence;
   string dominantDirection;
   bool isConflict;
   
   DirectionAnalysis() {
      bullishConfidence = 0;
      bearishConfidence = 0;
      neutralConfidence = 0;
      dominantDirection = "NEUTRAL";
      isConflict = false;
   }
   
   string GetDisplayString() const {
      string conflictText = isConflict ? " [CONFLICT]" : "";
      return StringFormat("%s (B:%.1f%% | S:%.1f%% | N:%.1f%%)%s",
         dominantDirection, bullishConfidence, bearishConfidence, 
         neutralConfidence, conflictText);
   }
};

// Base signal structure
struct TradeSignal {
   string symbol;
   ENUM_ORDER_TYPE orderType;
   double confidence;
   datetime timestamp;
   string signalSource;
   string reason;
   
   TradeSignal() {
      symbol = "";
      orderType = ORDER_TYPE_BUY_LIMIT;
      confidence = 0;
      timestamp = 0;
      signalSource = "";
      reason = "";
   }
   
   string GetOrderTypeString() const {
      switch(orderType) {
         case ORDER_TYPE_BUY: return "BUY";
         case ORDER_TYPE_SELL: return "SELL";
         case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT";
         case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
         case ORDER_TYPE_BUY_STOP: return "BUY STOP";
         case ORDER_TYPE_SELL_STOP: return "SELL STOP";
         default: return "HOLD";
      }
   }
   
   string GetSimpleSignal() const {
      switch(orderType) {
         case ORDER_TYPE_BUY: return "BUY";
         case ORDER_TYPE_SELL: return "SELL";
         default: return "HOLD";
      }
   }
};

// Entry/exit structure
struct TradeSetup {
   double entryPrice;
   double stopLoss;
   double takeProfit1;
   double takeProfit2;
   double riskRewardRatio;
   double positionSize;
   double riskAmount;
   string setupType;
   datetime expiryTime;
   
   TradeSetup() {
      entryPrice = 0;
      stopLoss = 0;
      takeProfit1 = 0;
      takeProfit2 = 0;
      riskRewardRatio = 0;
      positionSize = 0;
      riskAmount = 0;
      setupType = "";
      expiryTime = 0;
   }
   
   bool IsValid() const {
      return (entryPrice > 0 && stopLoss > 0 && positionSize > 0);
   }
   
   string GetRRRString() const {
      if(riskRewardRatio > 0) {
         return StringFormat("1:%.1f", riskRewardRatio);
      }
      return "N/A";
   }
};

// Risk management
struct RiskManagement {
   double maxRiskPercent;
   double minRiskReward;
   double maxPositionSize;
   bool useDynamicSizing;
   double volatilityFactor;
   double accountRisk;
   
   RiskManagement() {
      maxRiskPercent = 2.0;
      minRiskReward = 1.5;
      maxPositionSize = 10.0;
      useDynamicSizing = true;
      volatilityFactor = 1.0;
      accountRisk = 0;
   }
   
   string GetSettingsString() const {
      return StringFormat("Risk:%.1f%% RR:%.1f", 
         maxRiskPercent, minRiskReward);
   }
};

// Display configuration structure
struct DisplayConfig {
   bool useTabularFormat;
   bool useColorCodes;
   bool showInactiveModules;
   bool showDetails;
   int maxComponentsPerLine;
   string separator;
   
   DisplayConfig() {
      useTabularFormat = true;
      useColorCodes = true;
      showInactiveModules = false;
      showDetails = false;
      maxComponentsPerLine = 10;
      separator = "─";
   }
};

// ====================== TRADE PACKAGE CLASS ======================

class TradePackage
{
public:
   // Core signal and setup
   TradeSignal signal;
   TradeSetup setup;
   DirectionAnalysis directionAnalysis;
   
   // Module-specific DATA STRUCTURES ONLY - NO INSTANCES!
   MTFData mtfData;
   POISignal poiSignal;
   VolumeAnalysis volumeData;
   RSIAnalysis rsiData;
   MACDAnalysis macdData;
   PatternAnalysis patternData;
   
   // Risk management
   RiskManagement riskParams;
   
   // Module scores and weights - ALL 6 COMPONENTS
   struct ModuleScores {
      double mtfScore;
      double volumeScore;
      double rsiScore;
      double macdScore;
      double patternScore;
      double poiScore;    // NEW: For POI module (replaces srScore)
   } scores;
   
   struct ModuleWeights {
      double mtfWeight;
      double volumeWeight;
      double rsiWeight;
      double macdWeight;
      double patternWeight;
      double poiWeight;   // NEW: For POI module (replaces srWeight)
   } weights;
   
   // Aggregated results
   double overallConfidence;
   double weightedScore;
   bool isValid;
   string validationMessage;
   datetime analysisTime;
   
   // Display configuration
   DisplayConfig displayConfig;
   
   // Constructor
   TradePackage() {
      DebugLogTP("TradePackage", "Constructor called");
      
      // Initialize weights for 6 components (default balanced weights)
      weights.mtfWeight = 25.0;
      weights.volumeWeight = 15.0;
      weights.rsiWeight = 15.0;
      weights.macdWeight = 15.0;
      weights.patternWeight = 10.0;
      weights.poiWeight = 20.0;  // POI weight
      
      // Initialize aggregated results
      overallConfidence = 0;
      weightedScore = 0;
      isValid = false;
      validationMessage = "Not analyzed";
      analysisTime = TimeCurrent();
      
      DebugLogTP("TradePackage", "Constructor completed");
   }
   
   // ==================== CORE METHODS (PURE DATA PROCESSING) ====================
   
   void CalculateWeightedScore() {
      DebugLogTP("CalculateWeightedScore", "=== START CALCULATION ===");
      
      double totalWeight = 0;
      double weightedSum = 0;
      
      // MTF Module
      if(scores.mtfScore > 0) {
         double contribution = scores.mtfScore * weights.mtfWeight;
         totalWeight += weights.mtfWeight;
         weightedSum += contribution;
         DebugLogTP("CalculateWeightedScore", 
            StringFormat("MTF: Score=%.1f, Weight=%.1f, Contribution=%.1f",
            scores.mtfScore, weights.mtfWeight, contribution));
      }
      
      // Volume Module
      if(scores.volumeScore > 0) {
         double contribution = scores.volumeScore * weights.volumeWeight;
         totalWeight += weights.volumeWeight;
         weightedSum += contribution;
      }
      
      // RSI Module
      if(scores.rsiScore > 0) {
         double contribution = scores.rsiScore * weights.rsiWeight;
         totalWeight += weights.rsiWeight;
         weightedSum += contribution;
      }
      
      // MACD Module
      if(scores.macdScore > 0) {
         double contribution = scores.macdScore * weights.macdWeight;
         totalWeight += weights.macdWeight;
         weightedSum += contribution;
      }
      
      // Pattern Module
      if(scores.patternScore > 0) {
         double contribution = scores.patternScore * weights.patternWeight;
         totalWeight += weights.patternWeight;
         weightedSum += contribution;
      }
      
      // POI Module
      if(scores.poiScore > 0) {
         double contribution = scores.poiScore * weights.poiWeight;
         totalWeight += weights.poiWeight;
         weightedSum += contribution;
         DebugLogTP("CalculateWeightedScore", 
            StringFormat("POI: Score=%.1f, Weight=%.1f, Contribution=%.1f",
            scores.poiScore, weights.poiWeight, contribution));
      }
      
      DebugLogTP("CalculateWeightedScore", 
         StringFormat("totalWeight=%.1f, weightedSum=%.1f", totalWeight, weightedSum));
      
      if(totalWeight > 0) {
         // FIX: Use different variable name to avoid conflict
         double calculatedScore = weightedSum / totalWeight;
         
         // Count active modules
         int activeModules = 0;
         if(scores.mtfScore > 0) activeModules++;
         if(scores.volumeScore > 0) activeModules++;
         if(scores.rsiScore > 0) activeModules++;
         if(scores.macdScore > 0) activeModules++;
         if(scores.patternScore > 0) activeModules++;
         if(scores.poiScore > 0) activeModules++;
         
         double moduleFactor = 1.0 + ((activeModules - 1) * 0.05);
         
         // Assign to class member
         weightedScore = MathMin(calculatedScore * moduleFactor, 100.0);
         
         DebugLogTP("CalculateWeightedScore", 
            StringFormat("Calculated: %.1f / %.1f = %.1f (Factor: %.2f, Final: %.1f)", 
            weightedSum, totalWeight, calculatedScore, moduleFactor, weightedScore));
      } else {
         weightedScore = 0;
         DebugLogTP("CalculateWeightedScore", "No active modules or total weight is 0");
      }
      
      overallConfidence = CalculateOverallConfidence();
      signal.confidence = overallConfidence;
      
      DebugLogTP("CalculateWeightedScore", 
         StringFormat("Final: weightedScore=%.1f, overallConfidence=%.1f", 
         weightedScore, overallConfidence));
   }
   
   // Calculate overall confidence
   double CalculateOverallConfidence() {
      DebugLogTP("CalculateOverallConfidence", "Starting...");
      
      double baseConfidence = weightedScore;
      
      if(directionAnalysis.dominantDirection != "NEUTRAL") {
         double alignmentStrength = MathMax(directionAnalysis.bullishConfidence, 
                                           directionAnalysis.bearishConfidence);
         if(alignmentStrength >= 80) baseConfidence *= 1.2;
         else if(alignmentStrength >= 60) baseConfidence *= 1.1;
      }
      
      if(directionAnalysis.isConflict) {
         baseConfidence *= 0.7;
      }
      
      return MathMin(baseConfidence, 100.0);
   }
   
   // Calculate direction analysis from component data
   void CalculateDirectionAnalysis() {
      DebugLogTP("CalculateDirectionAnalysis", "Starting...");
      
      int bullishModules = 0;
      int bearishModules = 0;
      int totalDirectionalModules = 0;
      
      // MTF Direction
      if(scores.mtfScore > 0) {
         if(mtfData.bullishWeightedScore > mtfData.bearishWeightedScore) {
            bullishModules++;
         } else if(mtfData.bearishWeightedScore > mtfData.bullishWeightedScore) {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      // Volume Direction
      if(scores.volumeScore > 0) {
         if(volumeData.bias == "BULLISH") {
            bullishModules++;
         } else if(volumeData.bias == "BEARISH") {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      // RSI Direction
      if(scores.rsiScore > 0) {
         if(rsiData.netBias > 20) {
            bullishModules++;
         } else if(rsiData.netBias < -20) {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      // MACD Direction
      if(scores.macdScore > 0) {
         if(macdData.bias == "BULLISH" || macdData.bias == "WEAK BULLISH") {
            bullishModules++;
         } else if(macdData.bias == "BEARISH" || macdData.bias == "WEAK BEARISH") {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      // Pattern Direction
      if(scores.patternScore > 0) {
         if(patternData.direction == "BULLISH") {
            bullishModules++;
         } else if(patternData.direction == "BEARISH") {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      // POI Direction
      if(scores.poiScore > 0) {
         if(poiSignal.overallBias == "BULLISH") {
            bullishModules++;
         } else if(poiSignal.overallBias == "BEARISH") {
            bearishModules++;
         }
         totalDirectionalModules++;
      }
      
      if(totalDirectionalModules > 0) {
         directionAnalysis.bullishConfidence = (double)bullishModules / totalDirectionalModules * 100;
         directionAnalysis.bearishConfidence = (double)bearishModules / totalDirectionalModules * 100;
         directionAnalysis.neutralConfidence = 100 - directionAnalysis.bullishConfidence - directionAnalysis.bearishConfidence;
         
         // Determine dominant direction
         if(directionAnalysis.bullishConfidence > directionAnalysis.bearishConfidence && 
            directionAnalysis.bullishConfidence > directionAnalysis.neutralConfidence) {
            directionAnalysis.dominantDirection = "BULLISH";
         } else if(directionAnalysis.bearishConfidence > directionAnalysis.bullishConfidence && 
                  directionAnalysis.bearishConfidence > directionAnalysis.neutralConfidence) {
            directionAnalysis.dominantDirection = "BEARISH";
         } else {
            directionAnalysis.dominantDirection = "NEUTRAL";
         }
         
         // Check for conflict
         directionAnalysis.isConflict = (directionAnalysis.bullishConfidence >= 30.0 && 
                                       directionAnalysis.bearishConfidence >= 30.0);
      }
      
      DebugLogTP("CalculateDirectionAnalysis", 
         StringFormat("Result: B=%.1f%%, S=%.1f%%, N=%.1f%%, Dir=%s, Conflict=%s",
         directionAnalysis.bullishConfidence, directionAnalysis.bearishConfidence,
         directionAnalysis.neutralConfidence, directionAnalysis.dominantDirection,
         directionAnalysis.isConflict ? "YES" : "NO"));
   }
   
   // Normalize weights to sum to 100%
   void NormalizeWeights() {
      DebugLogTP("NormalizeWeights", "Starting...");
      
      double totalWeight = weights.mtfWeight + weights.volumeWeight + weights.rsiWeight + 
                         weights.macdWeight + weights.patternWeight + weights.poiWeight;
      
      if(totalWeight > 0 && MathAbs(totalWeight - 100.0) > 0.1) {
         double factor = 100.0 / totalWeight;
         weights.mtfWeight *= factor;
         weights.volumeWeight *= factor;
         weights.rsiWeight *= factor;
         weights.macdWeight *= factor;
         weights.patternWeight *= factor;
         weights.poiWeight *= factor;
      }
   }
   
   // Validate the trade package
   bool ValidatePackage(double minConfidence = 60.0) {
      DebugLogTP("ValidatePackage", StringFormat("Min confidence: %.1f", minConfidence));
      
      // First calculate everything
      CalculateDirectionAnalysis();
      CalculateWeightedScore();
      
      if(overallConfidence < minConfidence) {
         validationMessage = StringFormat("Confidence too low: %.1f%% < %.1f%%", 
                                        overallConfidence, minConfidence);
         isValid = false;
         return false;
      }
      
      if(directionAnalysis.dominantDirection == "NEUTRAL") {
         validationMessage = "No clear direction";
         isValid = false;
         return false;
      }
      
      validationMessage = StringFormat("Valid %s signal with %.1f%% confidence", 
                                     directionAnalysis.dominantDirection, overallConfidence);
      isValid = true;
      
      return true;
   }
   
   // ==================== DISPLAY METHODS ====================
   
   // Collect all 6 components for display
   void CollectComponents(ComponentDisplay &components[]) const {
      DebugLogTP("CollectComponents", "Collecting components...");
      ArrayResize(components, 0);
      
      // 1. MTF Component
      int size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "MTF",
         GetMTFDirection(),
         scores.mtfScore,
         mtfData.confidence,
         weights.mtfWeight,
         scores.mtfScore > 0,
         StringFormat("B:%d/S:%d/N:%d EMA89:%s",
            mtfData.bullishCount,
            mtfData.bearishCount,
            mtfData.neutralCount,
            mtfData.alignedWithEMA89 ? "✓" : "✗")
      );
      
      // 2. Volume Component
      size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "VOL",
         volumeData.bias,
         scores.volumeScore,
         volumeData.confidence,
         weights.volumeWeight,
         scores.volumeScore > 0,
         StringFormat("Mom:%.0f Conv:%.0f Ratio:%.1f%s",
            volumeData.momentumScore,
            volumeData.convictionScore,
            volumeData.volumeRatio,
            volumeData.hasWarning ? " ⚠" : "")
      );
      
      // 3. RSI Component
      size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "RSI",
         rsiData.biasText,
         scores.rsiScore,
         rsiData.confidence,
         weights.rsiWeight,
         scores.rsiScore > 0,
         StringFormat("RSI:%.1f Net:%.0f Level:%s",
            rsiData.currentRSI,
            rsiData.netBias,
            rsiData.rsiLevel)
      );
      
      // 4. MACD Component
      size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "MACD",
         macdData.bias,
         scores.macdScore,
         macdData.confidence,
         weights.macdWeight,
         scores.macdScore > 0,
         StringFormat("MACD:%.4f Hist:%.4f%s%s",
            macdData.macdValue,
            macdData.histogramValue,
            macdData.isCrossover ? " X" : "",
            macdData.isDivergence ? " D" : "")
      );
      
      // 5. Pattern Component
      size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "PAT",
         patternData.direction,
         scores.patternScore,
         patternData.confidence,
         weights.patternWeight,
         scores.patternScore > 0,
         StringFormat("%s%s RR:%.1f",
            patternData.patternName,
            patternData.isConfirmed ? " ✓" : "",
            patternData.riskRewardRatio)
      );
      
      // 6. POI Component (replaces SR)
      size = ArraySize(components);
      ArrayResize(components, size + 1);
      components[size] = ComponentDisplay(
         "POI",
         poiSignal.overallBias,
         scores.poiScore,
         poiSignal.confidence,
         weights.poiWeight,
         scores.poiScore > 0,
         StringFormat("Zones:%d/%d Dist:$%.2f",
            poiSignal.zonesInFavor,
            poiSignal.zonesAgainst,
            poiSignal.distanceToZone)
      );
   }
   
   // Generate tabular display
   string GenerateTabularDisplay() const {
      string display = "";
      
      // Header
      display += StringFormat("=== TRADE PACKAGE ===\nTime: %s\n", TimeToString(analysisTime, TIME_SECONDS));
      display += StringFormat("Symbol: %s | Signal: %s | Conf: %.1f%%\n", 
         signal.symbol, signal.GetSimpleSignal(), overallConfidence);
      
      // Component scores
      if(scores.mtfScore > 0) {
         display += StringFormat("MTF: %.1f%% (%s)\n", 
            scores.mtfScore, mtfData.GetAlignmentString());
      }
      
      if(scores.volumeScore > 0) {
         display += StringFormat("VOL: %.1f%% (%s)\n", scores.volumeScore, volumeData.bias);
      }
      
      if(scores.rsiScore > 0) {
         display += StringFormat("RSI: %.1f%% (%s)\n", scores.rsiScore, rsiData.biasText);
      }
      
      if(scores.macdScore > 0) {
         display += StringFormat("MACD: %.1f%% (%s)\n", scores.macdScore, macdData.bias);
      }
      
      if(scores.patternScore > 0) {
         display += StringFormat("PAT: %.1f%% (%s)\n", scores.patternScore, patternData.direction);
      }
      
      if(scores.poiScore > 0) {
         display += StringFormat("POI: %.1f%% (%s)\n", scores.poiScore, poiSignal.overallBias);
      }
      
      // Direction analysis
      display += StringFormat("---\nDirection: %s\n", directionAnalysis.GetDisplayString());
      
      // Setup if available
      if(setup.IsValid()) {
         display += StringFormat("Setup: Entry=%.4f SL=%.4f Size=%.2f lots\n", 
            setup.entryPrice, setup.stopLoss, setup.positionSize);
      }
      
      // Validation
      display += StringFormat("---\nValid: %s\n%s", isValid ? "✓ YES" : "✗ NO", validationMessage);
      
      return display;
   }
   
   void DisplayTabular() {
      string display = GenerateTabularDisplay();
      Logger::DisplaySingleFrame(display);
   }
   
   void DisplayOnChart() {
      string chartText = GenerateChartDisplay();
      Logger::DisplaySingleFrame(chartText);
   }
   
   string GenerateChartDisplay() {
      string display = "";
      display += "=== TRADE PACKAGE ===\n";
      display += StringFormat("Symbol: %s\n", signal.symbol);
      display += StringFormat("Signal: %s | Confidence: %.1f%%\n", signal.GetSimpleSignal(), overallConfidence);
      display += StringFormat("Direction: %s\n", directionAnalysis.GetDisplayString());
      display += StringFormat("Valid: %s\n", isValid ? "YES" : "NO");
      display += validationMessage;
      return display;
   }
   
   void Display() {
      if(displayConfig.useTabularFormat) {
         DisplayTabular();
      } else {
         DisplayOnChart();
      }
   }
   
   // ==================== HELPER METHODS ====================
   
   string GetMTFDirection() const {
      if(mtfData.bullishWeightedScore > mtfData.bearishWeightedScore) return "BULLISH";
      if(mtfData.bearishWeightedScore > mtfData.bullishWeightedScore) return "BEARISH";
      return "NEUTRAL";
   }
   
   string GetSignalIcon() const {
      if(signal.orderType == ORDER_TYPE_BUY) return "▲";
      if(signal.orderType == ORDER_TYPE_SELL) return "▼";
      return "●";
   }
   
   // Check if package has been populated with data
   bool HasData() const {
      int activeCount = 0;
      if(scores.mtfScore > 0) activeCount++;
      if(scores.volumeScore > 0) activeCount++;
      if(scores.rsiScore > 0) activeCount++;
      if(scores.macdScore > 0) activeCount++;
      if(scores.patternScore > 0) activeCount++;
      if(scores.poiScore > 0) activeCount++;
      
      return (activeCount >= 3);
   }
   
   // Get trade decision for execution
   int GetTradeDecision() const {
      if(!isValid || overallConfidence < 65) return 0; // HOLD
      if(signal.orderType == ORDER_TYPE_BUY) return 1; // BUY
      if(signal.orderType == ORDER_TYPE_SELL) return -1; // SELL
      return 0; // HOLD
   }
   
   // Get confidence as decimal (0-1)
   double GetConfidenceDecimal() const {
      return overallConfidence / 100.0;
   }
   
   // ==================== CONFIGURATION METHODS ====================
   
   void ConfigureDisplay(bool tabularFormat = true, bool useColors = true, 
                        bool showInactive = false, bool showDetails = false) {
      displayConfig.useTabularFormat = tabularFormat;
      displayConfig.useColorCodes = useColors;
      displayConfig.showInactiveModules = showInactive;
      displayConfig.showDetails = showDetails;
   }
   
   void SetComponentWeights(double mtfW, double poiW, double volW, 
                          double rsiW, double macdW, double patW) {
      weights.mtfWeight = mtfW;
      weights.poiWeight = poiW;
      weights.volumeWeight = volW;
      weights.rsiWeight = rsiW;
      weights.macdWeight = macdW;
      weights.patternWeight = patW;
      
      NormalizeWeights();
   }
   
   // ==================== DATA POPULATION HELPERS ====================
   
   // These methods allow external modules to populate data
   
   // Populate MTF data
   void SetMTFData(double score, double mtfWeightedScore, int bullishCount, int bearishCount, 
               int neutralCount, double bullishWeightedScore, double bearishWeightedScore,
               bool alignedWithEMA89, double confidence) {
      mtfData.score = score;
      mtfData.weightedScore = mtfWeightedScore;
      mtfData.bullishCount = bullishCount;
      mtfData.bearishCount = bearishCount;
      mtfData.neutralCount = neutralCount;
      mtfData.bullishWeightedScore = bullishWeightedScore;
      mtfData.bearishWeightedScore = bearishWeightedScore;
      mtfData.alignedWithEMA89 = alignedWithEMA89;
      mtfData.confidence = confidence;
      scores.mtfScore = mtfWeightedScore;
   }
   
   // Populate POI data
   void SetPOIData(string overallBias, string zoneBias, double score, double confidence,
                  int nearestZoneType, double distanceToZone, double zoneStrength,
                  double zoneRelevance, string priceAction, int zonesInFavor, int zonesAgainst) {
      poiSignal.overallBias = overallBias;
      poiSignal.zoneBias = zoneBias;
      poiSignal.score = score;
      poiSignal.confidence = confidence;
      poiSignal.nearestZoneType = nearestZoneType;
      poiSignal.distanceToZone = distanceToZone;
      poiSignal.zoneStrength = zoneStrength;
      poiSignal.zoneRelevance = zoneRelevance;
      poiSignal.priceAction = priceAction;
      poiSignal.zonesInFavor = zonesInFavor;
      poiSignal.zonesAgainst = zonesAgainst;
      scores.poiScore = score;
   }
   
   // Populate Volume data
   void SetVolumeData(double momentumScore, double convictionScore, string prediction,
                     bool divergence, bool climax, string volumeStatus, double volumeRatio,
                     double bullishScore, double bearishScore, string bias, double confidence,
                     bool hasWarning) {
      volumeData.momentumScore = momentumScore;
      volumeData.convictionScore = convictionScore;
      volumeData.prediction = prediction;
      volumeData.divergence = divergence;
      volumeData.climax = climax;
      volumeData.volumeStatus = volumeStatus;
      volumeData.volumeRatio = volumeRatio;
      volumeData.bullishScore = bullishScore;
      volumeData.bearishScore = bearishScore;
      volumeData.bias = bias;
      volumeData.confidence = confidence;
      volumeData.hasWarning = hasWarning;
      scores.volumeScore = convictionScore;
   }
   
   // Populate RSI data
   void SetRSIData(double bullishBias, double bearishBias, double netBias, double confidence,
                  string biasText, string rsiLevel, double currentRSI) {
      rsiData.bullishBias = bullishBias;
      rsiData.bearishBias = bearishBias;
      rsiData.netBias = netBias;
      rsiData.confidence = confidence;
      rsiData.biasText = biasText;
      rsiData.rsiLevel = rsiLevel;
      rsiData.currentRSI = currentRSI;
      scores.rsiScore = MathAbs(netBias);
   }
   
   // Populate MACD data
   void SetMACDData(string bias, double score, double confidence, string signalType,
                   double macdValue, double signalValue, double histogramValue,
                   double histogramSlope, bool isAboveZero, bool isCrossover,
                   bool isDivergence, bool isStrongSignal) {
      macdData.bias = bias;
      macdData.score = score;
      macdData.confidence = confidence;
      macdData.signalType = signalType;
      macdData.macdValue = macdValue;
      macdData.signalValue = signalValue;
      macdData.histogramValue = histogramValue;
      macdData.histogramSlope = histogramSlope;
      macdData.isAboveZero = isAboveZero;
      macdData.isCrossover = isCrossover;
      macdData.isDivergence = isDivergence;
      macdData.isStrongSignal = isStrongSignal;
      scores.macdScore = score;
   }
   
   // Populate Pattern data
   void SetPatternData(string patternName, string direction, double confidence,
                      string description, bool isConfirmed, double targetPrice,
                      double stopLoss, double riskRewardRatio) {
      patternData.patternName = patternName;
      patternData.direction = direction;
      patternData.confidence = confidence;
      patternData.description = description;
      patternData.isConfirmed = isConfirmed;
      patternData.targetPrice = targetPrice;
      patternData.stopLoss = stopLoss;
      patternData.riskRewardRatio = riskRewardRatio;
      scores.patternScore = confidence;
   }
   
   // Set signal information
   void SetSignal(string symbol, ENUM_ORDER_TYPE orderType, string reason, string source = "") {
      signal.symbol = symbol;
      signal.orderType = orderType;
      signal.reason = reason;
      signal.timestamp = TimeCurrent();
      signal.signalSource = (source == "") ? "TradePackage" : source;
   }
   
   // Set setup information
   void SetSetup(double entryPrice, double stopLoss, double takeProfit1, 
                double takeProfit2 = 0, string setupType = "") {
      setup.entryPrice = entryPrice;
      setup.stopLoss = stopLoss;
      setup.takeProfit1 = takeProfit1;
      setup.takeProfit2 = takeProfit2;
      setup.setupType = setupType;
   }
   
   // Calculate position size
   void CalculatePositionSize(double accountBalance) {
      if(setup.entryPrice > 0 && setup.stopLoss > 0) {
         setup.positionSize = MathUtils::CalculatePositionSizeByRisk(
            signal.symbol,
            setup.entryPrice,
            setup.stopLoss,
            riskParams.maxRiskPercent,
            accountBalance
         );
         
         // Apply confidence multiplier
         double confidenceMultiplier = GetPositionSizeMultiplier();
         setup.positionSize *= confidenceMultiplier;
         
         // Cap position size
         setup.positionSize = MathMin(setup.positionSize, riskParams.maxPositionSize);
         
         // Normalize lot size
         setup.positionSize = MathUtils::NormalizeLotSize(signal.symbol, setup.positionSize);
      }
   }
   
   double GetPositionSizeMultiplier() const {
      if(overallConfidence >= 85) return 1.5;
      if(overallConfidence >= 75) return 1.2;
      if(overallConfidence >= 65) return 1.0;
      if(overallConfidence >= 55) return 0.7;
      if(overallConfidence >= 40) return 0.3;
      return 0.0;
   }
   
   // Get package summary
   string GetSummary() const {
      string summary = StringFormat(
         "Trade Package Summary for %s:\n"
         "Time: %s | Confidence: %.1f%% | Direction: %s\n"
         "Component Scores: MTF=%.1f%%, VOL=%.1f%%, RSI=%.1f%%, MACD=%.1f%%, PAT=%.1f%%, POI=%.1f%%\n"
         "Active Modules: %d/6 | Valid: %s | Signal: %s",
         signal.symbol,
         TimeToString(analysisTime, TIME_SECONDS),
         overallConfidence,
         directionAnalysis.dominantDirection,
         scores.mtfScore, scores.volumeScore, scores.rsiScore,
         scores.macdScore, scores.patternScore, scores.poiScore,
         (scores.mtfScore > 0 ? 1 : 0) + (scores.volumeScore > 0 ? 1 : 0) +
         (scores.rsiScore > 0 ? 1 : 0) + (scores.macdScore > 0 ? 1 : 0) +
         (scores.patternScore > 0 ? 1 : 0) + (scores.poiScore > 0 ? 1 : 0),
         isValid ? "YES" : "NO",
         signal.GetSimpleSignal()
      );
      
      return summary;
   }

      // ==================== COMPLETE COMPONENT DISPLAY ====================
   
   string GenerateDetailedTabularDisplay() const {
      string display = "";
      
      // Header
      display += "=== 6-COMPONENT TRADE PACKAGE ===\n";
      display += StringFormat("Symbol: %s | Time: %s\n", 
         signal.symbol, TimeToString(analysisTime, TIME_SECONDS));
      display += StringFormat("Confidence: %.1f%% | Direction: %s\n\n", 
         overallConfidence, directionAnalysis.dominantDirection);
      
      // Component Header
      display += "Component     | Bias      | Bull% | Bear% | Conf% | Weight | Score\n";
      display += "-------------|-----------|-------|-------|-------|--------|-------\n";
      
      // 1. MTF Component
      if(scores.mtfScore > 0) {
         string mtfBias = GetMTFDirection();
         double mtfBullScore = mtfData.bullishWeightedScore;
         double mtfBearScore = mtfData.bearishWeightedScore;
         double mtfScoreContrib = scores.mtfScore * (weights.mtfWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "MTF", 
            mtfBias,
            mtfBullScore,
            mtfBearScore,
            mtfData.confidence,
            weights.mtfWeight,
            mtfScoreContrib);
      }
      
      // 2. POI Component
      if(scores.poiScore > 0) {
         double poiBullScore = (poiSignal.overallBias == "BULLISH" || poiSignal.overallBias == "BUY ZONE") ? scores.poiScore : 0;
         double poiBearScore = (poiSignal.overallBias == "BEARISH" || poiSignal.overallBias == "SELL ZONE") ? scores.poiScore : 0;
         double poiScoreContrib = scores.poiScore * (weights.poiWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "POI", 
            poiSignal.overallBias,
            poiBullScore,
            poiBearScore,
            poiSignal.confidence,
            weights.poiWeight,
            poiScoreContrib);
      }
      
      // 3. Volume Component
      if(scores.volumeScore > 0) {
         double volumeBullScore = volumeData.bullishScore;
         double volumeBearScore = volumeData.bearishScore;
         double volumeScoreContrib = scores.volumeScore * (weights.volumeWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "Volume", 
            volumeData.bias,
            volumeBullScore,
            volumeBearScore,
            volumeData.confidence,
            weights.volumeWeight,
            volumeScoreContrib);
      }
      
      // 4. RSI Component
      if(scores.rsiScore > 0) {
         double rsiBullScore = MathMax(0, rsiData.netBias);
         double rsiBearScore = MathMax(0, -rsiData.netBias);
         double rsiScoreContrib = scores.rsiScore * (weights.rsiWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "RSI", 
            rsiData.biasText,
            rsiBullScore,
            rsiBearScore,
            rsiData.confidence,
            weights.rsiWeight,
            rsiScoreContrib);
      }
      
      // 5. MACD Component
      if(scores.macdScore > 0) {
         double macdBullScore = (macdData.bias == "BULLISH" || macdData.bias == "WEAK BULLISH") ? scores.macdScore : 0;
         double macdBearScore = (macdData.bias == "BEARISH" || macdData.bias == "WEAK BEARISH") ? scores.macdScore : 0;
         double macdScoreContrib = scores.macdScore * (weights.macdWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "MACD", 
            macdData.bias,
            macdBullScore,
            macdBearScore,
            macdData.confidence,
            weights.macdWeight,
            macdScoreContrib);
      }
      
      // 6. Pattern Component
      if(scores.patternScore > 0) {
         double patternBullScore = (patternData.direction == "BULLISH") ? scores.patternScore : 0;
         double patternBearScore = (patternData.direction == "BEARISH") ? scores.patternScore : 0;
         double patternScoreContrib = scores.patternScore * (weights.patternWeight / 100.0);
         
         display += StringFormat("%-13s| %-10s| %5.1f | %5.1f | %5.1f | %6.1f | %5.1f\n",
            "Pattern", 
            patternData.direction,
            patternBullScore,
            patternBearScore,
            patternData.confidence,
            weights.patternWeight,
            patternScoreContrib);
      }
      
      // Separator
      display += "-------------|-----------|-------|-------|-------|--------|-------\n";
      
      // Totals
      display += StringFormat("%-13s| %-10s|       |       |       | %6.1f | %5.1f\n\n",
         "TOTAL",
         "",
         100.0,
         weightedScore);
      
      // Direction Breakdown
      display += StringFormat("Direction Breakdown:\n", "");
      display += StringFormat("Bullish: %.1f%% | Bearish: %.1f%% | Neutral: %.1f%%\n",
         directionAnalysis.bullishConfidence,
         directionAnalysis.bearishConfidence,
         directionAnalysis.neutralConfidence);
      
      if(directionAnalysis.isConflict) {
         display += "⚠️ CONFLICTING SIGNALS\n";
      }
      
      // Final Recommendation
      string recommendation = GetRecommendation();
      display += StringFormat("\nRECOMMENDATION: %s\n", recommendation);
      
      // Setup details if available
      if(setup.IsValid()) {
         display += StringFormat("\nSetup: Entry=%.5f | SL=%.5f | TP1=%.5f | Size=%.2f lots | R:R=%.1f\n",
            setup.entryPrice, setup.stopLoss, setup.takeProfit1, 
            setup.positionSize, setup.riskRewardRatio);
      }
      
      // Validation Status
      display += StringFormat("\nValid: %s\n%s",
         isValid ? "✓ YES" : "✗ NO",
         validationMessage);
      
      return display;
   }
   
   string GetRecommendation() const {
      if(!isValid || overallConfidence < 40) return "NO SIGNAL";
      
      string strength = "";
      if(overallConfidence >= 85) strength = "STRONG ";
      else if(overallConfidence >= 70) strength = "MODERATE ";
      else if(overallConfidence >= 55) strength = "WEAK ";
      
      string action = "";
      if(signal.orderType == ORDER_TYPE_BUY) action = "BUY";
      else if(signal.orderType == ORDER_TYPE_SELL) action = "SELL";
      else action = "HOLD";
      
      return StringFormat("%s%s (%.1f%% confidence)", strength, action, overallConfidence);
   }
   
   void DisplayDetailedTabular() {
      string display = GenerateDetailedTabularDisplay();
      Logger::DisplaySingleFrame(display);
   }

      // Get MTF bull/bear scores
   double GetMTFBullScore() const {
      return mtfData.bullishWeightedScore;
   }
   
   double GetMTFBearScore() const {
      return mtfData.bearishWeightedScore;
   }
   
   // Get Volume bull/bear scores
   double GetVolumeBullScore() const {
      return volumeData.bullishScore;
   }
   
   double GetVolumeBearScore() const {
      return volumeData.bearishScore;
   }
   
   // Get RSI bull/bear scores
   double GetRSIBullScore() const {
      return MathMax(0, rsiData.netBias);
   }
   
   double GetRSIBearScore() const {
      return MathMax(0, -rsiData.netBias);
   }
   
   // Get POI bull/bear scores
   double GetPOIBullScore() const {
      return (poiSignal.overallBias == "BULLISH" || poiSignal.overallBias == "BUY ZONE") ? scores.poiScore : 0;
   }
   
   double GetPOIBearScore() const {
      return (poiSignal.overallBias == "BEARISH" || poiSignal.overallBias == "SELL ZONE") ? scores.poiScore : 0;
   }
   
   // Get MACD bull/bear scores
   double GetMACDBullScore() const {
      return (macdData.bias == "BULLISH" || macdData.bias == "WEAK BULLISH") ? scores.macdScore : 0;
   }
   
   double GetMACDBearScore() const {
      return (macdData.bias == "BEARISH" || macdData.bias == "WEAK BEARISH") ? scores.macdScore : 0;
   }
   
   // Get Pattern bull/bear scores
   double GetPatternBullScore() const {
      return (patternData.direction == "BULLISH") ? scores.patternScore : 0;
   }
   
   double GetPatternBearScore() const {
      return (patternData.direction == "BEARISH") ? scores.patternScore : 0;
   }
};