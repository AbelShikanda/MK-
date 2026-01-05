//+------------------------------------------------------------------+
//|                              POIModule.mqh                       |
//|                Enhanced with IndicatorManager Integration        |
//|                NO TRADEPACKAGE DEPENDENCIES                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Headers/Enums.mqh"
#include "../Data/IndicatorManager.mqh"

// ==================== DEBUG SETTINGS ====================
bool POI_DEBUG_ENABLED = false;

void DebugLogPOI(string context, string message) {
   if(POI_DEBUG_ENABLED) {
      Logger::Log(context, message);
   }
}

// ==================== STRUCTURES ====================

struct POIZone
{
    double priceLevel;
    ENUM_POI_TYPE type;
    double strength;
    double bufferDistance;
    datetime lastTouchTime;
    int touchCount;
    bool isActive;
    int lineHandle;
    int labelHandle;
    string bias;
    double distanceToPrice;
    
    // Zone cleanup fields
    datetime creationTime;      // When zone was created
    int failedTests;           // Count of failed price tests
    double relevance;          // 0.0-1.0 relevance score
    bool isArchived;           // Archived but not deleted
    double lastATR;           // Last ATR distance
    ENUM_TIMEFRAMES tfSource; // Source timeframe for expiry rules
    
    // Constructor
    POIZone() {
        priceLevel = 0.0;
        type = POI_SUPPORT;
        strength = 0.0;
        bufferDistance = 2.0;
        lastTouchTime = 0;
        touchCount = 0;
        isActive = false;
        lineHandle = -1;
        labelHandle = -1;
        bias = "NEUTRAL";
        distanceToPrice = 999999.0;
        creationTime = 0;
        failedTests = 0;
        relevance = 1.0;
        isArchived = false;
        lastATR = 0.0;
        tfSource = PERIOD_D1;
    }
};

// POI Signal Structure - Module-specific output
struct POIModuleSignal
{
    ENUM_POI_BIAS overallBias;        // Primary bias
    string biasString;                // "BULLISH", "BEARISH", "NEUTRAL", "CONFLICTED"
    string zoneBias;                  // "BUY ZONE", "SELL ZONE", "BUY BIAS", "SELL BIAS"
    double score;                     // 0-100 overall score
    double confidence;                // 0-100 confidence in bias
    ENUM_POI_TYPE nearestZoneType;    // Type of nearest zone
    double distanceToZone;            // Price distance to nearest zone ($)
    double distanceInATR;             // Distance in ATR units
    double zoneStrength;              // 0-1 strength of the zone
    double zoneRelevance;             // 0-1 relevance score
    string priceAction;               // "Bounce", "Rejection", "Breakout", "Consolidation", "Approaching", "Far"
    int zonesInFavor;                 // How many zones support this bias
    int zonesAgainst;                 // How many zones oppose this bias
    bool isInsideZone;                // Is price inside a zone buffer?
    bool isActionable;                // Is this an actionable signal?
    datetime timestamp;               // When signal was generated
    
    // Constructor
    POIModuleSignal() {
        overallBias = POI_BIAS_NEUTRAL;
        biasString = "NEUTRAL";
        zoneBias = "NEUTRAL";
        score = 0;
        confidence = 0;
        nearestZoneType = POI_SUPPORT;
        distanceToZone = 9999.0;
        distanceInATR = 0;
        zoneStrength = 0;
        zoneRelevance = 0;
        priceAction = "";
        zonesInFavor = 0;
        zonesAgainst = 0;
        isInsideZone = false;
        isActionable = false;
        timestamp = TimeCurrent();
    }
    
    // Get simple signal
    string GetSimpleSignal() const {
        if(overallBias == POI_BIAS_BULLISH) return "BUY";
        if(overallBias == POI_BIAS_BEARISH) return "SELL";
        return "HOLD";
    }
    
    // Get confidence as percentage string
    string GetConfidenceString() const {
        return StringFormat("%.0f%%", confidence);
    }
    
    // Check if signal is actionable
    bool IsActionable() const {
        return (overallBias != POI_BIAS_NEUTRAL && 
                confidence > 60 && 
                score > 50 && 
                isActionable);
    }
    
    // Get formatted display
    string GetDisplayString() const {
        string biasIcon = "";
        if(overallBias == POI_BIAS_BULLISH) biasIcon = "▲";
        else if(overallBias == POI_BIAS_BEARISH) biasIcon = "▼";
        
        return StringFormat("%s %s | Score: %.0f | Conf: %.0f%% | Dist: $%.2f", 
            biasIcon, biasString, score, confidence, distanceToZone);
    }
    
    // Get detailed analysis
    string GetDetailedAnalysis() const {
        return StringFormat(
            "POI Analysis:\n"
            "Bias: %s\n"
            "Confidence: %.0f%%\n"
            "Score: %.0f\n"
            "Zone: %s\n"
            "Distance: $%.2f (%.1f ATR)\n"
            "Action: %s\n"
            "Favoring: %d zones | Against: %d zones\n"
            "Inside Zone: %s | Actionable: %s",
            biasString,
            confidence,
            score,
            (nearestZoneType == POI_SUPPORT) ? "SUPPORT" : "RESISTANCE",
            distanceToZone,
            distanceInATR,
            priceAction,
            zonesInFavor,
            zonesAgainst,
            isInsideZone ? "YES" : "NO",
            isActionable ? "YES" : "NO"
        );
    }
};

// ==================== POI SCORES STRUCTURE ====================
// Module-specific data structure for returning POI scores
struct POIScores
{
    double bullScore;         // 0-100 bullish bias score
    double bearScore;         // 0-100 bearish bias score
    double overallScore;      // 0-100 overall POI score
    double confidence;        // 0-100 confidence level
    string bias;              // "BULLISH", "BEARISH", "NEUTRAL", "CONFLICTED"
    bool isActionable;        // Whether the signal is actionable
    datetime timestamp;       // When scores were calculated
    
    POIScores() {
        bullScore = 0;
        bearScore = 0;
        overallScore = 0;
        confidence = 0;
        bias = "NEUTRAL";
        isActionable = false;
        timestamp = TimeCurrent();
    }
    
    string GetSummary() const {
        return StringFormat("Bias: %s | Bull:%.0f | Bear:%.0f | Score:%.0f | Conf:%.0f%% | Actionable:%s",
            bias, bullScore, bearScore, overallScore, confidence, isActionable ? "YES" : "NO");
    }
    
    // Check for conflict
    bool IsConflict() const {
        return (bullScore > 40 && bearScore > 40 && MathAbs(bullScore - bearScore) < 20);
    }
    
    // Get dominant direction
    string GetDominantDirection() const {
        if(bullScore > bearScore && bullScore > 50) return "BULLISH";
        if(bearScore > bullScore && bearScore > 50) return "BEARISH";
        return "NEUTRAL";
    }
};

// ==================== POI ZONE DATA STRUCTURE ====================
struct POIZoneData
{
    int totalZones;           // Total active zones
    int supportZones;         // Number of support zones
    int resistanceZones;      // Number of resistance zones
    double nearestZonePrice;  // Price of nearest zone
    double nearestZoneDistance; // Distance to nearest zone
    ENUM_POI_TYPE nearestZoneType; // Type of nearest zone
    bool isInsideZone;        // Is price inside any zone?
    POIZone zones[];          // Array of zone data
    
    POIZoneData() {
        totalZones = 0;
        supportZones = 0;
        resistanceZones = 0;
        nearestZonePrice = 0;
        nearestZoneDistance = 9999.0;
        nearestZoneType = POI_SUPPORT;
        isInsideZone = false;
        ArrayResize(zones, 0);
    }
    
    string GetSummary() const {
        return StringFormat("Zones: %d (S:%d/R:%d) | Nearest: %s at %.5f ($%.2f away) | Inside: %s",
            totalZones, supportZones, resistanceZones,
            (nearestZoneType == POI_SUPPORT) ? "SUPPORT" : "RESISTANCE",
            nearestZonePrice, nearestZoneDistance,
            isInsideZone ? "YES" : "NO");
    }
};

// ==================== POI MODULE CLASS ====================
class POIModule
{
private:
    string m_symbol;
    POIZone m_zones[100];
    int m_zoneCount;
    bool m_initialized;
    bool m_drawOnChart;
    double m_defaultBuffer;
    color m_supportColor;
    color m_resistanceColor;
    long m_chartId;
    
    bool m_showScores;
    double m_lastOverallScore;
    string m_lastOverallBias;
    
    int m_maxDisplayZones;
    int m_displayMode;
    
    // Cleanup tracking
    datetime m_lastCleanupTime;
    double m_currentATR;
    
    // Signal generation
    POIModuleSignal m_lastSignal;
    datetime m_lastSignalTime;
    
    // Indicator Manager
    IndicatorManager* m_indicatorManager;
    
public:
    POIModule()
    {
        m_symbol = "";
        m_zoneCount = 0;
        m_initialized = false;
        m_drawOnChart = false;
        m_defaultBuffer = 2.0;
        m_supportColor = clrLimeGreen;
        m_resistanceColor = clrRed;
        m_chartId = 0;
        
        m_showScores = true;
        m_lastOverallScore = 0.0;
        m_lastOverallBias = "NEUTRAL";
        
        m_maxDisplayZones = 10;
        m_displayMode = 1;
        
        // Initialize cleanup tracking
        m_lastCleanupTime = 0;
        m_currentATR = 0.0;
        
        // Initialize signal
        m_lastSignal = POIModuleSignal();
        m_lastSignalTime = 0;
        
        // Initialize IndicatorManager
        m_indicatorManager = NULL;
    }
    
    ~POIModule()
    {
        Deinitialize();
    }
    
public:
    bool Initialize(string symbol, bool drawOnChart = false, double defaultBuffer = 2.0, 
               int maxDisplayZones = 10, int displayMode = 1)
    {
        if(m_initialized) return true;
        
        m_symbol = symbol;
        m_drawOnChart = drawOnChart;
        m_defaultBuffer = defaultBuffer;
        m_chartId = ChartID();
        
        m_maxDisplayZones = maxDisplayZones;
        m_displayMode = displayMode;
        
        // Initialize IndicatorManager
        m_indicatorManager = new IndicatorManager(m_symbol);
        if(m_indicatorManager == NULL || !m_indicatorManager.Initialize()) {
            DebugLogPOI("POIModule", "Failed to initialize IndicatorManager");
            return false;
        }
        
        // Get current ATR using IndicatorManager
        m_currentATR = m_indicatorManager.GetATR(PERIOD_H1, 0);
        if(m_currentATR <= 0) {
            m_currentATR = m_defaultBuffer;
            DebugLogPOI("POIModule", "Using default buffer as ATR");
        }
        
        if(!CalculateZones()) {
            DebugLogPOI("POIModule", "Failed to calculate initial zones");
            return false;
        }
        
        m_initialized = true;
        
        if(m_drawOnChart) {
            DrawZonesOnChart();
            Logger::ShowScoreFast(m_symbol, 0.5, "POI_INIT", 0.7);
        }
        
        DebugLogPOI("POIModule", StringFormat("Initialized for %s with %d zones, ATR: %.4f", 
            m_symbol, m_zoneCount, m_currentATR));
        return true;
    }
    
    void Deinitialize()
    {
        if(!m_initialized) return;
        
        RemoveChartObjects();
        
        // Deinitialize IndicatorManager
        if(m_indicatorManager != NULL) {
            m_indicatorManager.Deinitialize();
            delete m_indicatorManager;
            m_indicatorManager = NULL;
        }
        
        // Reset zones
        for(int i = 0; i < m_zoneCount; i++) {
            m_zones[i].lineHandle = -1;
            m_zones[i].labelHandle = -1;
            m_zones[i].isActive = false;
        }
        m_zoneCount = 0;
        
        m_initialized = false;
        DebugLogPOI("POIModule", "Deinitialized");
    }
    
    // ==================== PUBLIC INTERFACE ====================
    
    void ShowScores(bool show = true) {
        m_showScores = show;
        if(m_drawOnChart && m_initialized) {
            if(show) DrawZonesOnChart();
            else DrawSimpleZones();
        }
    }
    
    void SetDisplayMode(int mode) {
        if(mode == 0 || mode == 1) {
            m_displayMode = mode;
            if(m_initialized && m_drawOnChart) DrawZonesOnChart();
        }
    }
    
    int GetDisplayMode() const { return m_displayMode; }
    
    void SetMaxDisplayZones(int maxZones) {
        if(maxZones > 0 && maxZones <= 50) {
            m_maxDisplayZones = maxZones;
            if(m_initialized && m_drawOnChart) DrawZonesOnChart();
        } else {
            Logger::LogError("POIModule", StringFormat("Invalid max zones value: %d (must be 1-50)", maxZones));
        }
    }
    
    int GetMaxDisplayZones() const { return m_maxDisplayZones; }
    
    bool GetNearestZones(POIZone &outZones[], int count = 10, double currentPrice = 0) {
        if(!m_initialized || count <= 0 || count > m_zoneCount) return false;
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        // Sort zones by distance
        POIZone tempZones[];
        ArrayResize(tempZones, m_zoneCount);
        int activeCount = 0;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(m_zones[i].isActive && !m_zones[i].isArchived) {
                tempZones[activeCount] = m_zones[i];
                tempZones[activeCount].distanceToPrice = MathAbs(currentPrice - m_zones[i].priceLevel);
                activeCount++;
            }
        }
        
        if(activeCount == 0) return false;
        
        // Sort by distance (bubble sort - simple for small arrays)
        for(int i = 0; i < activeCount - 1; i++) {
            for(int j = i + 1; j < activeCount; j++) {
                if(tempZones[j].distanceToPrice < tempZones[i].distanceToPrice) {
                    POIZone temp = tempZones[i];
                    tempZones[i] = tempZones[j];
                    tempZones[j] = temp;
                }
            }
        }
        
        int copyCount = MathMin(count, activeCount);
        ArrayResize(outZones, copyCount);
        
        for(int i = 0; i < copyCount; i++) {
            outZones[i] = tempZones[i];
        }
        
        return copyCount > 0;
    }
    
    // ==================== MODULE-SPECIFIC DATA METHODS ====================
    
    // MAIN METHOD: Get complete POI analysis data
    POIModuleSignal GetPOIModuleSignal(double currentPrice = 0) 
    {
        if(!m_initialized) {
            DebugLogPOI("GetPOIModuleSignal", "Module not initialized");
            return m_lastSignal;
        }
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        // Use cached signal if recent (less than 60 seconds old)
        if(TimeCurrent() - m_lastSignalTime < 60 && m_lastSignal.timestamp > 0) {
            DebugLogPOI("GetPOIModuleSignal", "Using cached signal");
            return m_lastSignal;
        }
        
        DebugLogPOI("GetPOIModuleSignal", "Generating new POI signal");
        
        // Generate new signal
        POIModuleSignal signal;
        signal.timestamp = TimeCurrent();
        
        // Get basic POI data using IndicatorManager
        signal.biasString = GetOverallBias(currentPrice);
        signal.overallBias = StringToBias(signal.biasString);
        signal.score = GetOverallScore(currentPrice);
        
        // Get detailed zone info
        ENUM_POI_TYPE zoneType;
        double distance;
        double detailedScore = GetPOIScore(currentPrice, zoneType, distance);
        
        signal.nearestZoneType = zoneType;
        signal.distanceToZone = distance;
        signal.score = MathMax(signal.score, detailedScore);
        
        // Get nearest zone for more context
        POIZone nearestZone;
        if(GetNearestZone(currentPrice, nearestZone)) {
            signal.zoneBias = nearestZone.bias;
            signal.zoneStrength = nearestZone.strength;
            signal.zoneRelevance = nearestZone.relevance;
            signal.distanceInATR = nearestZone.lastATR;
        }
        
        // Check if price is inside a zone
        ENUM_POI_TYPE insideZoneType;
        signal.isInsideZone = IsInsidePOIZone(currentPrice, insideZoneType);
        
        // Calculate confidence
        signal.confidence = CalculateSignalConfidence(signal, nearestZone);
        
        // Determine price action
        signal.priceAction = DetermineSignalPriceAction(signal, currentPrice, nearestZone);
        
        // Count supporting zones
        CountSupportingZones(currentPrice, signal);
        
        // Determine if signal is actionable
        signal.isActionable = DetermineIfActionable(signal);
        
        // Cache the signal
        m_lastSignal = signal;
        m_lastSignalTime = TimeCurrent();
        
        DebugLogPOI("GetPOIModuleSignal", StringFormat(
            "Signal Generated: %s | Score: %.1f | Conf: %.1f%% | Actionable: %s",
            signal.biasString, signal.score, signal.confidence, 
            signal.isActionable ? "YES" : "NO"
        ));
        
        return signal;
    }
    
    // Get POI scores only (lightweight method)
    POIScores GetPOIScores(double currentPrice = 0)
    {
        POIScores scores;
        
        if(!m_initialized) {
            DebugLogPOI("GetPOIScores", "Module not initialized");
            return scores;
        }
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        // Calculate bull and bear bias scores
        CalculateBiasScores(currentPrice, scores.bullScore, scores.bearScore);
        
        // Get overall score
        scores.overallScore = GetOverallScore(currentPrice);
        
        // Get POI signal for confidence and bias
        POIModuleSignal signal = GetPOIModuleSignal(currentPrice);
        scores.confidence = signal.confidence;
        scores.bias = signal.biasString;
        scores.isActionable = signal.isActionable;
        scores.timestamp = TimeCurrent();
        
        DebugLogPOI("GetPOIScores", 
            StringFormat("Bull:%.1f, Bear:%.1f, Overall:%.1f, Conf:%.1f%%, Bias:%s",
                scores.bullScore, scores.bearScore, scores.overallScore, 
                scores.confidence, scores.bias));
        
        return scores;
    }
    
    // Get zone data only
    POIZoneData GetZoneData(double currentPrice = 0)
    {
        POIZoneData zoneData;
        
        if(!m_initialized || m_zoneCount == 0) {
            DebugLogPOI("GetZoneData", "Module not initialized or no zones");
            return zoneData;
        }
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        // Count zones by type
        zoneData.supportZones = 0;
        zoneData.resistanceZones = 0;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(m_zones[i].isActive && !m_zones[i].isArchived) {
                if(m_zones[i].type == POI_SUPPORT || m_zones[i].type == POI_ORDER_BLOCK_BUY) {
                    zoneData.supportZones++;
                } else {
                    zoneData.resistanceZones++;
                }
            }
        }
        
        zoneData.totalZones = zoneData.supportZones + zoneData.resistanceZones;
        
        // Get nearest zone
        POIZone nearestZone;
        if(GetNearestZone(currentPrice, nearestZone)) {
            zoneData.nearestZonePrice = nearestZone.priceLevel;
            zoneData.nearestZoneDistance = MathAbs(currentPrice - nearestZone.priceLevel);
            zoneData.nearestZoneType = nearestZone.type;
        }
        
        // Check if inside zone
        ENUM_POI_TYPE insideZoneType;
        zoneData.isInsideZone = IsInsidePOIZone(currentPrice, insideZoneType);
        
        // Get array of zones
        if(zoneData.totalZones > 0) {
            ArrayResize(zoneData.zones, zoneData.totalZones);
            int index = 0;
            for(int i = 0; i < m_zoneCount; i++) {
                if(m_zones[i].isActive && !m_zones[i].isArchived) {
                    zoneData.zones[index++] = m_zones[i];
                }
            }
        }
        
        return zoneData;
    }
    
    // Get simplified signal only (for quick checks)
    string GetSimpleSignal(double currentPrice = 0)
    {
        if(!m_initialized) return "NEUTRAL";
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        POIModuleSignal signal = GetPOIModuleSignal(currentPrice);
        return signal.GetSimpleSignal();
    }
    
    // Get actionable recommendation (for decision making)
    string GetActionableRecommendation(double currentPrice = 0)
    {
        if(!m_initialized) return "HOLD - POI Not Initialized";
        
        if(currentPrice == 0) currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        POIModuleSignal signal = GetPOIModuleSignal(currentPrice);
        
        if(!signal.isActionable) {
            return "HOLD - Not Actionable";
        }
        
        if(signal.overallBias == POI_BIAS_BULLISH) {
            return StringFormat("BUY - %s (Score: %.0f, Conf: %.0f%%)", 
                signal.priceAction, signal.score, signal.confidence);
        } 
        else if(signal.overallBias == POI_BIAS_BEARISH) {
            return StringFormat("SELL - %s (Score: %.0f, Conf: %.0f%%)", 
                signal.priceAction, signal.score, signal.confidence);
        }
        
        return "HOLD - Neutral Bias";
    }
    
    // Get overall bias
    string GetOverallBias(double currentPrice) {
        if(!m_initialized) return "NEUTRAL";
        
        POIZone nearestZone;
        if(GetNearestZone(currentPrice, nearestZone)) {
            double distance = MathAbs(currentPrice - nearestZone.priceLevel);
            
            if(distance <= nearestZone.bufferDistance) {
                if(nearestZone.type == POI_SUPPORT || nearestZone.type == POI_ORDER_BLOCK_BUY)
                    return "BULLISH";
                else if(nearestZone.type == POI_RESISTANCE || nearestZone.type == POI_ORDER_BLOCK_SELL)
                    return "BEARISH";
            } else {
                if(currentPrice < nearestZone.priceLevel) {
                    if(nearestZone.type == POI_SUPPORT) return "BULLISH";
                    else return "BEARISH";
                } else {
                    if(nearestZone.type == POI_SUPPORT) return "BEARISH";
                    else return "BULLISH";
                }
            }
        }
        
        return "NEUTRAL";
    }
    
    double GetOverallScore(double currentPrice) {
        ENUM_POI_TYPE zoneType;
        double distance;
        return GetPOIScore(currentPrice, zoneType, distance);
    }
    
    double GetPOIScore(double currentPrice, ENUM_POI_TYPE &outZoneType, double &outDistanceToZone) {
        if(!m_initialized || m_zoneCount == 0) {
            outZoneType = POI_SUPPORT;
            outDistanceToZone = 9999.0;
            return 0.0;
        }
        
        double bestScore = 0.0;
        ENUM_POI_TYPE bestType = POI_SUPPORT;
        double bestDistance = 9999.0;
        
        int zonesToCheck = MathMin(m_zoneCount, m_maxDisplayZones * 2);
        
        for(int i = 0; i < zonesToCheck; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            double buffer = m_zones[i].bufferDistance;
            
            double zoneScore = 0.0;
            
            if(distance <= buffer) {
                zoneScore = m_zones[i].relevance * 100.0;
            } else {
                double distanceFactor = 1.0 - MathMin(1.0, (distance - buffer) / (buffer * 3.0));
                zoneScore = m_zones[i].relevance * 100.0 * distanceFactor;
            }
            
            if(zoneScore > bestScore) {
                bestScore = zoneScore;
                bestType = m_zones[i].type;
                bestDistance = distance;
            }
        }
        
        outZoneType = bestType;
        outDistanceToZone = bestDistance;
        
        if(bestScore > 50.0 && POI_DEBUG_ENABLED) {
            DebugLogPOI("POIModule", 
                StringFormat("Price %.2f: POI Score=%.0f, Type=%d, Distance=$%.2f",
                currentPrice, bestScore, bestType, bestDistance));
        }
        
        return bestScore;
    }
    
    bool IsInsidePOIZone(double currentPrice, ENUM_POI_TYPE &outZoneType) {
        if(!m_initialized) return false;
        
        int zonesToCheck = MathMin(m_zoneCount, m_maxDisplayZones * 2);
        
        for(int i = 0; i < zonesToCheck; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            if(distance <= m_zones[i].bufferDistance) {
                outZoneType = m_zones[i].type;
                return true;
            }
        }
        
        return false;
    }
    
    bool GetNearestZone(double currentPrice, POIZone &outZone) {
        if(!m_initialized || m_zoneCount == 0) return false;
        
        double minDistance = 999999.0;
        int nearestIndex = -1;
        
        int zonesToCheck = MathMin(m_zoneCount, m_maxDisplayZones * 2);
        
        for(int i = 0; i < zonesToCheck; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            if(distance < minDistance) {
                minDistance = distance;
                nearestIndex = i;
            }
        }
        
        if(nearestIndex >= 0) {
            outZone = m_zones[nearestIndex];
            return true;
        }
        
        return false;
    }
    
    // Helper method to get zone count information
    void GetZoneCounts(int &totalZones, int &supportZones, int &resistanceZones)
    {
        totalZones = 0;
        supportZones = 0;
        resistanceZones = 0;
        
        if(!m_initialized) return;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(m_zones[i].isActive && !m_zones[i].isArchived) {
                totalZones++;
                if(m_zones[i].type == POI_SUPPORT || m_zones[i].type == POI_ORDER_BLOCK_BUY) {
                    supportZones++;
                } else {
                    resistanceZones++;
                }
            }
        }
    }
    
    bool IsInitialized() const { return m_initialized; }
    int GetZoneCount() const { return m_zoneCount; }
    bool IsShowingScores() const { return m_showScores; }
    POIModuleSignal GetLastSignal() const { return m_lastSignal; }
    
    // EVENT HANDLERS
    void OnTick() {
        if(!m_initialized) return;
        
        UpdateZoneDistances();
        CheckZoneTouches();
        CheckFailedTests();
        RunHourlyCleanup();
        
        if(m_drawOnChart) {
            static int tickCounter = 0;
            tickCounter++;
            
            if(tickCounter >= 500) {
                DrawZonesOnChart();
                tickCounter = 0;
            }
        }
    }
    
    void OnTimer() {
        if(!m_initialized) return;
        
        static datetime lastUpdate = 0;
        if(TimeCurrent() - lastUpdate >= 300) {
            UpdateZones();
            lastUpdate = TimeCurrent();
        }
    }
    
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                          const MqlTradeRequest& request,
                          const MqlTradeResult& result) {
        if(!m_initialized) return;
    }
    
private:
    // ==================== PRIVATE METHODS ====================
    
    // Calculate bull and bear bias scores
    void CalculateBiasScores(double currentPrice, double &bullScore, double &bearScore)
    {
        bullScore = 0;
        bearScore = 0;
        
        if(!m_initialized || m_zoneCount == 0) return;
        
        int zonesToCheck = MathMin(m_zoneCount, 20);
        
        for(int i = 0; i < zonesToCheck; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            double buffer = m_zones[i].bufferDistance;
            double zoneWeight = m_zones[i].strength * m_zones[i].relevance;
            
            // Calculate influence based on distance
            double influence = 0;
            if(distance <= buffer) {
                influence = 1.0;
            } else if(distance <= buffer * 3) {
                influence = 1.0 - ((distance - buffer) / (buffer * 2));
            } else {
                continue;
            }
            
            // Apply to appropriate score
            if(m_zones[i].type == POI_SUPPORT || m_zones[i].type == POI_ORDER_BLOCK_BUY) {
                if(currentPrice >= m_zones[i].priceLevel) {
                    bullScore += zoneWeight * influence * 100;
                } else {
                    bearScore += zoneWeight * influence * 100;
                }
            } else if(m_zones[i].type == POI_RESISTANCE || m_zones[i].type == POI_ORDER_BLOCK_SELL) {
                if(currentPrice <= m_zones[i].priceLevel) {
                    bearScore += zoneWeight * influence * 100;
                } else {
                    bullScore += zoneWeight * influence * 100;
                }
            }
        }
        
        // Normalize scores
        double total = bullScore + bearScore;
        if(total > 0) {
            bullScore = (bullScore / total) * 100;
            bearScore = (bearScore / total) * 100;
        }
    }
    
    bool CalculateZones() {
        m_zoneCount = 0;
        
        double highs[], lows[];
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(lows, true);
        
        ENUM_TIMEFRAMES timeframes[] = {PERIOD_D1, PERIOD_H4};
        int lookback = 200;
        
        for(int tf = 0; tf < ArraySize(timeframes); tf++) {
            int copiedHighs = CopyHigh(m_symbol, timeframes[tf], 0, lookback, highs);
            int copiedLows = CopyLow(m_symbol, timeframes[tf], 0, lookback, lows);
            
            if(copiedHighs < lookback || copiedLows < lookback) continue;
            
            // Find swing highs for resistance
            for(int i = 10; i < lookback - 10; i++) {
                if(IsSwingHigh(highs, i, 10)) {
                    AddZone(highs[i], POI_RESISTANCE, 0.8 + (tf * 0.15), timeframes[tf]);
                }
            }
            
            // Find swing lows for support
            for(int i = 10; i < lookback - 10; i++) {
                if(IsSwingLow(lows, i, 10)) {
                    AddZone(lows[i], POI_SUPPORT, 0.8 + (tf * 0.15), timeframes[tf]);
                }
            }
        }
        
        MergeNearbyZones();
        FilterWeakZones();
        UpdateZoneDistances();
        UpdateZoneBiases(SymbolInfoDouble(m_symbol, SYMBOL_BID));
        
        DebugLogPOI("POIModule", StringFormat("Calculated %d POI zones", m_zoneCount));
        return m_zoneCount > 0;
    }
    
    bool IsSwingHigh(const double &data[], int index, int lookback) {
        if(index < lookback || index >= ArraySize(data) - lookback) return false;
        
        double current = data[index];
        
        for(int i = 1; i <= lookback; i++) {
            if(data[index - i] > current) return false;
            if(data[index + i] > current) return false;
        }
        
        return true;
    }
    
    bool IsSwingLow(const double &data[], int index, int lookback) {
        if(index < lookback || index >= ArraySize(data) - lookback) return false;
        
        double current = data[index];
        
        for(int i = 1; i <= lookback; i++) {
            if(data[index - i] < current) return false;
            if(data[index + i] < current) return false;
        }
        
        return true;
    }
    
    void AddZone(double price, ENUM_POI_TYPE type, double strength, ENUM_TIMEFRAMES tfSource = PERIOD_D1) {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double minDistance = 100 * point;
        
        // Check for existing nearby zone
        for(int i = 0; i < m_zoneCount; i++) {
            if(MathAbs(m_zones[i].priceLevel - price) < minDistance) {
                if(strength > m_zones[i].strength) {
                    m_zones[i].priceLevel = price;
                    m_zones[i].type = type;
                    m_zones[i].strength = strength;
                    m_zones[i].tfSource = tfSource;
                }
                return;
            }
        }
        
        // Add new zone
        if(m_zoneCount < ArraySize(m_zones)) {
            POIZone zone;
            zone.priceLevel = NormalizePrice(m_symbol, price);
            zone.type = type;
            zone.strength = strength;
            zone.bufferDistance = m_defaultBuffer;
            zone.lastTouchTime = 0;
            zone.touchCount = 0;
            zone.isActive = true;
            zone.creationTime = TimeCurrent();
            zone.failedTests = 0;
            zone.relevance = 1.0;
            zone.isArchived = false;
            zone.tfSource = tfSource;
            zone.bias = "NEUTRAL";
            zone.distanceToPrice = 999999.0;
            
            m_zones[m_zoneCount++] = zone;
        }
    }
    
    void MergeNearbyZones() {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double mergeDistance = 100 * point;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive) continue;
            
            for(int j = i + 1; j < m_zoneCount; j++) {
                if(!m_zones[j].isActive) continue;
                
                if(MathAbs(m_zones[i].priceLevel - m_zones[j].priceLevel) < mergeDistance) {
                    if(m_zones[i].strength >= m_zones[j].strength) {
                        m_zones[j].isActive = false;
                    } else {
                        m_zones[i].isActive = false;
                        break;
                    }
                }
            }
        }
        
        // Compact array
        int writeIndex = 0;
        for(int i = 0; i < m_zoneCount; i++) {
            if(m_zones[i].isActive) {
                if(writeIndex != i) m_zones[writeIndex] = m_zones[i];
                writeIndex++;
            }
        }
        m_zoneCount = writeIndex;
    }
    
    void FilterWeakZones() {
        int writeIndex = 0;
        for(int i = 0; i < m_zoneCount; i++) {
            if(m_zones[i].strength >= 0.7 || m_zones[i].touchCount >= 2) {
                if(writeIndex != i) m_zones[writeIndex] = m_zones[i];
                writeIndex++;
            } else {
                m_zones[i].isActive = false;
            }
        }
        m_zoneCount = writeIndex;
    }
    
    void UpdateZones() {
        CalculateZones();
        if(m_drawOnChart) DrawZonesOnChart();
    }
    
    void UpdateZoneDistances() {
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            m_zones[i].distanceToPrice = MathAbs(currentPrice - m_zones[i].priceLevel);
            
            if(m_currentATR > 0) {
                m_zones[i].lastATR = m_zones[i].distanceToPrice / m_currentATR;
            } else {
                m_zones[i].lastATR = 0.0;
            }
        }
    }
    
    void CheckZoneTouches() {
        if(!m_initialized) return;
        
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double touchDistance = 10 * point;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            if(distance <= touchDistance) {
                m_zones[i].lastTouchTime = TimeCurrent();
                m_zones[i].touchCount++;
                m_zones[i].strength = MathMin(1.0, m_zones[i].strength + 0.05);
            }
        }
        
        UpdateZoneBiases(currentPrice);
    }
    
    void CheckFailedTests() {
        if(!m_initialized) return;
        
        double currentClose = iClose(m_symbol, PERIOD_CURRENT, 0);
        double prevClose = iClose(m_symbol, PERIOD_CURRENT, 1);
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double zonePrice = m_zones[i].priceLevel;
            double buffer = m_zones[i].bufferDistance;
            
            if(prevClose > zonePrice + buffer || prevClose < zonePrice - buffer) {
                m_zones[i].failedTests++;
                
                if(m_zones[i].failedTests >= 3) {
                    ArchiveZone(i);
                }
            }
        }
    }
    
    void UpdateZoneBiases(double currentPrice) {
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            m_zones[i].bias = GetZoneBias(m_zones[i], currentPrice);
        }
    }
    
    void DrawZonesOnChart() {
        if(!m_drawOnChart || m_chartId == 0) return;
        
        static double lastPrice = 0;
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double priceThreshold = m_currentATR * 0.005;
        
        if(MathAbs(currentPrice - lastPrice) < priceThreshold) return;
        lastPrice = currentPrice;
        
        RemoveChartObjects();
        UpdateZoneDistances();
        UpdateZoneRelevance();
        
        // Get zones sorted by distance
        POIZone sortedZones[];
        if(!GetNearestZones(sortedZones, m_maxDisplayZones, currentPrice)) return;
        
        // Draw zones
        for(int i = 0; i < ArraySize(sortedZones); i++) {
            if(sortedZones[i].relevance >= 0.3) {
                DrawZone(sortedZones[i], i + 1);
            }
        }
        
        ChartRedraw(m_chartId);
    }
    
    void DrawZone(const POIZone &zone, int rank) {
        string baseName = StringFormat("POI_Zone_%s_%d", m_symbol, rank);
        
        // Create or update line
        if(ObjectFind(m_chartId, baseName) < 0) {
            ObjectCreate(m_chartId, baseName, OBJ_HLINE, 0, 0, zone.priceLevel);
        }
        
        // Set properties
        color lineColor = (zone.type == POI_SUPPORT) ? m_supportColor : m_resistanceColor;
        int lineStyle = zone.relevance > 0.8 ? STYLE_SOLID : (zone.relevance > 0.5 ? STYLE_DASH : STYLE_DOT);
        int lineWidth = zone.relevance > 0.8 ? 2 : 1;
        
        ObjectSetDouble(m_chartId, baseName, OBJPROP_PRICE, zone.priceLevel);
        ObjectSetInteger(m_chartId, baseName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(m_chartId, baseName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(m_chartId, baseName, OBJPROP_WIDTH, lineWidth);
        ObjectSetInteger(m_chartId, baseName, OBJPROP_BACK, true);
        
        // Add label
        string labelName = baseName + "_Label";
        if(ObjectFind(m_chartId, labelName) < 0) {
            ObjectCreate(m_chartId, labelName, OBJ_TEXT, 0, TimeCurrent() + (PeriodSeconds() * 20), zone.priceLevel);
        }
        
        string typeStr = (zone.type == POI_SUPPORT) ? "SUP" : "RES";
        string distanceStr = FormatDistance(zone.distanceToPrice);
        
        ObjectSetString(m_chartId, labelName, OBJPROP_TEXT, 
            StringFormat("#%d %s (%s) %.0f%%", rank, typeStr, distanceStr, zone.relevance * 100));
        
        ObjectSetInteger(m_chartId, labelName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(m_chartId, labelName, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(m_chartId, labelName, OBJPROP_BACK, false);
    }
    
    void DrawSimpleZones() {
        if(!m_drawOnChart || m_chartId == 0) return;
        
        // Remove old zones
        int totalObjects = ObjectsTotal(m_chartId);
        for(int i = totalObjects - 1; i >= 0; i--) {
            string objName = ObjectName(m_chartId, i);
            if(StringFind(objName, "POI_") == 0) {
                ObjectDelete(m_chartId, objName);
            }
        }
        
        // Get current zones
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        POIZone zones[];
        if(!GetNearestZones(zones, m_maxDisplayZones, currentPrice)) return;
        
        // Draw simple zones
        for(int i = 0; i < ArraySize(zones); i++) {
            string lineName = StringFormat("POI_Simple_%s_%d", m_symbol, i);
            color lineColor = (zones[i].type == POI_SUPPORT) ? m_supportColor : m_resistanceColor;
            
            ObjectCreate(m_chartId, lineName, OBJ_HLINE, 0, 0, zones[i].priceLevel);
            ObjectSetInteger(m_chartId, lineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(m_chartId, lineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(m_chartId, lineName, OBJPROP_BACK, true);
        }
        
        ChartRedraw(m_chartId);
    }
    
    void RemoveChartObjects() {
        if(m_chartId == 0) return;
        
        int totalObjects = ObjectsTotal(m_chartId);
        for(int i = totalObjects - 1; i >= 0; i--) {
            string objName = ObjectName(m_chartId, i);
            if(StringFind(objName, "POI_") == 0) {
                ObjectDelete(m_chartId, objName);
            }
        }
    }
    
    string GetZoneBias(const POIZone &zone, double currentPrice) {
        double distance = MathAbs(currentPrice - zone.priceLevel);
        
        if(distance <= zone.bufferDistance) {
            if(zone.type == POI_SUPPORT) return "BUY ZONE";
            else return "SELL ZONE";
        } else if(currentPrice < zone.priceLevel) {
            if(zone.type == POI_SUPPORT) return "BUY BIAS";
            else return "SELL BIAS";
        } else {
            if(zone.type == POI_SUPPORT) return "SELL BIAS";
            else return "BUY BIAS";
        }
    }
    
    string FormatDistance(double distance) {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double pips = distance / point;
        
        if(pips < 10) return StringFormat("%.1f", pips);
        else if(pips < 1000) return StringFormat("%.0f", pips);
        else return StringFormat("%.1fK", pips / 1000);
    }
    
    double NormalizePrice(string symbol, double price) {
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        return NormalizeDouble(price, digits);
    }
    
    // ==================== SIGNAL GENERATION METHODS ====================
    
    ENUM_POI_BIAS StringToBias(string biasString) {
        if(biasString == "BULLISH") return POI_BIAS_BULLISH;
        if(biasString == "BEARISH") return POI_BIAS_BEARISH;
        if(biasString == "CONFLICTED") return POI_BIAS_CONFLICTED;
        return POI_BIAS_NEUTRAL;
    }
    
    double CalculateSignalConfidence(POIModuleSignal &signal, const POIZone &zone) {
        double confidence = 0;
        
        // Use IndicatorManager for additional confirmation
        if(m_indicatorManager != NULL) {
            // Get RSI for confirmation
            double rsi = m_indicatorManager.GetRSI(PERIOD_H1, 0);
            if((signal.overallBias == POI_BIAS_BULLISH && rsi < 70) ||
               (signal.overallBias == POI_BIAS_BEARISH && rsi > 30)) {
                confidence += 10.0; // RSI confirms
            }
        }
        
        // Base confidence from zone
        confidence += signal.score * 0.4;
        confidence += zone.strength * 100 * 0.25;
        confidence += zone.relevance * 100 * 0.2;
        
        // Distance factor
        double distanceFactor = CalculateDistanceFactor(signal.distanceToZone, zone.bufferDistance);
        confidence *= (0.85 + (distanceFactor * 0.15));
        
        return MathMin(confidence, 100.0);
    }
    
    double CalculateDistanceFactor(double distance, double buffer) {
        if(distance <= buffer) return 1.0;
        if(distance <= buffer * 2) return 1.0 - ((distance - buffer) / (buffer * 2));
        if(distance <= buffer * 3) {
            double normalized = (distance - buffer * 2) / buffer;
            return 0.5 * (1.0 - normalized * normalized);
        }
        return 0.1;
    }
    
    string DetermineSignalPriceAction(const POIModuleSignal &signal, double currentPrice, const POIZone &zone) {
        double buffer = zone.bufferDistance;
        double distance = signal.distanceToZone;
        
        // Use IndicatorManager for trend confirmation
        if(m_indicatorManager != NULL) {
            bool trendBullish = m_indicatorManager.IsTrendBullish(PERIOD_H1);
            bool trendBearish = m_indicatorManager.IsTrendBearish(PERIOD_H1);
            
            // Check trend alignment
            if((signal.overallBias == POI_BIAS_BULLISH && !trendBullish) ||
               (signal.overallBias == POI_BIAS_BEARISH && !trendBearish)) {
                return "Trend Conflict";
            }
        }
        
        // Determine price action based on zone
        if(distance <= buffer) {
            if(signal.nearestZoneType == POI_SUPPORT) {
                return currentPrice > zone.priceLevel ? "Bounce" : "Support Test";
            } else {
                return currentPrice < zone.priceLevel ? "Rejection" : "Resistance Test";
            }
        } else if(distance <= buffer * 2) {
            return "Approaching Zone";
        }
        
        return "Neutral";
    }
    
    void CountSupportingZones(double currentPrice, POIModuleSignal &signal) {
        signal.zonesInFavor = 0;
        signal.zonesAgainst = 0;
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            double distance = MathAbs(currentPrice - m_zones[i].priceLevel);
            if(distance <= m_zones[i].bufferDistance * 2) {
                bool supportsBullish = (m_zones[i].type == POI_SUPPORT && currentPrice >= m_zones[i].priceLevel) ||
                                      (m_zones[i].type == POI_RESISTANCE && currentPrice <= m_zones[i].priceLevel);
                
                bool supportsBearish = (m_zones[i].type == POI_SUPPORT && currentPrice <= m_zones[i].priceLevel) ||
                                      (m_zones[i].type == POI_RESISTANCE && currentPrice >= m_zones[i].priceLevel);
                
                if(signal.overallBias == POI_BIAS_BULLISH && supportsBullish) {
                    signal.zonesInFavor++;
                } else if(signal.overallBias == POI_BIAS_BEARISH && supportsBearish) {
                    signal.zonesInFavor++;
                } else if(signal.overallBias == POI_BIAS_BULLISH && supportsBearish) {
                    signal.zonesAgainst++;
                } else if(signal.overallBias == POI_BIAS_BEARISH && supportsBullish) {
                    signal.zonesAgainst++;
                }
            }
        }
    }
    
    bool DetermineIfActionable(const POIModuleSignal &signal) {
        if(signal.overallBias == POI_BIAS_NEUTRAL) return false;
        if(signal.confidence < 60) return false;
        if(signal.score < 50) return false;
        
        // Strong price actions are always actionable
        if(signal.priceAction == "Bounce" || signal.priceAction == "Rejection") {
            return true;
        }
        
        // Inside zone with high confidence
        if(signal.isInsideZone && signal.confidence > 70) {
            return true;
        }
        
        return false;
    }
    
    // ==================== CLEANUP METHODS ====================
    
    void RunHourlyCleanup() {
        if(TimeCurrent() - m_lastCleanupTime < 3600) return;
        
        DebugLogPOI("POIModule", "Running hourly cleanup...");
        
        // Update ATR using IndicatorManager
        if(m_indicatorManager != NULL) {
            m_currentATR = m_indicatorManager.GetATR(PERIOD_H1, 0);
        }
        
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            if(CheckZoneExpiry(i)) {
                ArchiveZone(i);
                continue;
            }
            
            if(m_currentATR > 0 && m_zones[i].lastATR > 3.0) {
                ArchiveZone(i);
            }
        }
        
        UpdateZoneRelevance();
        m_lastCleanupTime = TimeCurrent();
    }
    
    bool CheckZoneExpiry(int zoneIndex) {
        int ageSeconds = (int)(TimeCurrent() - m_zones[zoneIndex].creationTime);
        int ageDays = ageSeconds / 86400;
        
        switch(m_zones[zoneIndex].tfSource) {
            case PERIOD_D1:
            case PERIOD_H4:
                return ageDays > 15;
            case PERIOD_H1:
                return ageDays > 7;
            default:
                return ageDays > 15;
        }
    }
    
    void ArchiveZone(int zoneIndex) {
        m_zones[zoneIndex].isArchived = true;
        
        if(m_zones[zoneIndex].lineHandle != -1) {
            ObjectDelete(m_chartId, StringFormat("POI_Zone_%s_%d", m_symbol, zoneIndex));
            m_zones[zoneIndex].lineHandle = -1;
        }
    }
    
    void UpdateZoneRelevance() {
        for(int i = 0; i < m_zoneCount; i++) {
            if(!m_zones[i].isActive || m_zones[i].isArchived) continue;
            
            int ageSeconds = (int)(TimeCurrent() - m_zones[i].creationTime);
            double ageDays = ageSeconds / 86400.0;
            double ageFactor = MathMax(0.0, 1.0 - (ageDays / 30.0));
            double distanceFactor = MathMax(0.0, 1.0 - (m_zones[i].lastATR / 5.0));
            double testFactor = MathMax(0.0, 1.0 - (m_zones[i].failedTests / 3.0));
            
            m_zones[i].relevance = (ageFactor * 0.4) + (distanceFactor * 0.3) + (testFactor * 0.3);
            m_zones[i].relevance = MathMin(1.0, MathMax(0.0, m_zones[i].relevance));
        }
    }
};

//+------------------------------------------------------------------+