// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //
// ++++++++++++++++++++++++++      MTF ENGINE (Multi-Timeframe)     ++++++++++++++++++++++ //
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ //

#property copyright "Copyright 2024"
#property strict
#property version   "1.00"

/*
==============================================================
MULTI-TIMEFRAME ENGINE
==============================================================
Core Principles:
1. Dynamic Component Integration
2. Weighted Confidence (Always totals 100%)
3. Adaptive Weight Distribution
==============================================================
*/

#include "../utils/Utils.mqh"
#include "../utils/ResourceManager.mqh"
#include "../config/enums.mqh"
#include "../MTF/MTFDetector.mqh"

// ================= ENUMS =================
enum MTF_SIGNAL {
    MTF_SIGNAL_NONE,
    MTF_SIGNAL_STRONG_BUY,
    MTF_SIGNAL_STRONG_SELL,
    MTF_SIGNAL_WEAK_BUY,
    MTF_SIGNAL_WEAK_SELL,
    MTF_SIGNAL_NEUTRAL
};

enum MTF_CONTEXT {
    CONTEXT_TRENDING,
    CONTEXT_RANGING,
    CONTEXT_BREAKOUT,
    CONTEXT_REVERSAL,
    CONTEXT_CHOPPY
};

// ================= STRUCTURES =================
struct ComponentScore {
    string componentName;
    double rawScore;
    double normalizedScore;
    double baseWeight;
    double adjustedWeight;
    double weightedScore;
    int rank;
    bool isAvailable;
    string direction;
    int confidenceLevel;
};

struct MTFAnalysis {
    ComponentScore components[7];
    double totalConfidence;
    MTF_CONTEXT context;
    datetime analysisTime;
    string primaryBias;
    MTF_SIGNAL signal;
    bool isConfluent;
    string recommendedAction;
    double divergenceScore;
    double marketBiasStrength;
};

struct ComponentConfiguration {
    string componentName;
    double baseWeight;
    double minScoreThreshold;
    double maxScoreThreshold;
    bool isRequired;
};

// ================= CLASS DEFINITION =================
class MTFEngine
{
private:
    string m_symbol;
    int m_maxComponents;
    ComponentConfiguration m_componentConfigs[7];
    bool m_componentAvailability[7];
    MTFAnalysis m_currentAnalysis;
    MTF_CONTEXT m_currentContext;
    double m_baseWeights[7];
    double m_availableWeights[7];
    int m_availableCount;
    double m_trendingMultiplier;
    double m_rangingMultiplier;
    double m_breakoutMultiplier;
    double m_reversalMultiplier;
    ResourceManager* m_logger;
    MTFScorer* m_mtfScorer;
    bool m_initialized;
    bool m_ownsLogger;
    bool m_showOnlyImportant;
    int m_minConfidenceForDisplay;
    
    // Performance optimizations
    int m_adxHandle;
    int m_atrHandle;
    double m_cachedBid;
    datetime m_lastBidUpdate;
    static double s_pointValue;
    datetime m_lastContextDetection;
    MTF_CONTEXT m_cachedContext;
    string m_cachedSymbolForContext;
    bool m_forceRefresh;
    datetime m_lastFullRefresh;
    bool m_cacheValid;
    
    // Log timing control
    static datetime s_lastPeriodicLog;
    static int s_logCount;
    
    // String constants
    const string STR_MTFENGINE;
    const string STR_MTFSCORE;
    const string STR_NEUTRAL;
    const string STR_BULLISH;
    const string STR_BEARISH;
    
public:
    MTFEngine();
    ~MTFEngine();
    
    bool Initialize(ResourceManager* logger = NULL, 
                   MTFScorer* mtfScorer = NULL, 
                   string symbol = "",
                   bool showOnlyImportant = true,
                   int minConfidenceForDisplay = 60);
    
    void OnTick();
    void OnTimer();
    void OnTradeTransaction();
    void Deinitialize();
    
    bool IsInitialized() const { return m_initialized; }
    
    MTFAnalysis Analyze(string symbol, bool forceRefresh = false);
    double GetOverallConfidence(string symbol, bool forceRefresh = false);
    string GetMarketBias(string symbol, bool forceRefresh = false);
    MTF_SIGNAL GetSignal(string symbol, bool forceRefresh = false);
    
    void RegisterComponent(string componentName, double baseWeight);
    void SetComponentAvailability(string componentName, bool isAvailable);
    double GetComponentScore(string componentName);
    
    string GetRecommendedAction(string symbol);
    bool IsSignalValid(string symbol, double minConfidence = 70.0);
    MTF_CONTEXT GetMarketContext(string symbol);
    void SetDisplayMinConfidence(int minConfidence);
    void ForceRefresh() { m_forceRefresh = true; }
    void InvalidateCache() { m_cacheValid = false; }
    
    ResourceManager* GetLogger() const { return m_logger; }
    
private:
    // Component scoring
    double GetMTFScore(string symbol);
    double GetMTFSSDDConfluence(string symbol);
    double GetSwingFailurePatternScore(string symbol);
    double GetMSSScore(string symbol);
    double GetTrendScore(string symbol);
    double GetOrderFlowScore(string symbol);
    double GetMomentumScore(string symbol);
    
    // Core calculations
    void CalculateTotalConfidence();
    void NormalizeScores();
    void ApplyContextAdjustments();
    void RebalanceWeights();
    void DistributeWeights();
    void AdjustWeightsForContext();
    
    // Helpers
    int GetComponentIndex(string componentName);
    double GetDefaultScore(string componentName);
    bool IsComponentRequired(string componentName);
    double GetAvailableWeightTotal();
    MTF_SIGNAL GenerateSignal();
    string DetermineBias();
    double CalculateBiasStrength();
    void DetectContext(string symbol);
    double GetADXValue(string symbol);
    double GetATRPercent(string symbol);
    bool CheckConfluence();
    double CalculateDivergence();
    void InitializeComponents();
    double GetComponentRawScore(string componentName);
    string CalculateRecommendedAction(MTFAnalysis& analysis);
    
    // Performance optimizations
    void InitializeIndicatorHandles(string symbol);
    void CleanupIndicatorHandles();
    double GetSymbolBid(string symbol);
    bool IsAnalysisStale(datetime analysisTime, int maxSeconds = 1);
    bool ShouldUseCache(string symbol);
    
    // Optimized logging
    void LogPeriodicStatus();
    void LogImportant(string message, RESOURCE_MANAGER level = OBSERVE);
    void LogComponentScores(bool force = false);
    void LogAnalysisResult();
};

// Static initializations
double MTFEngine::s_pointValue = 0.0;
datetime MTFEngine::s_lastPeriodicLog = 0;
int MTFEngine::s_logCount = 0;

// ================= EXTERNAL INTERFACE =================
double MTF_GetConfidence(string symbol)
{
    MTFEngine engine;
    if(engine.Initialize(NULL)) {
        double result = engine.GetOverallConfidence(symbol, true);
        engine.Deinitialize();
        return result;
    }
    return 0.0;
}

MTF_SIGNAL MTF_GetSignal(string symbol)
{
    MTFEngine engine;
    if(engine.Initialize(NULL)) {
        MTF_SIGNAL result = engine.GetSignal(symbol, true);
        engine.Deinitialize();
        return result;
    }
    return MTF_SIGNAL_NONE;
}

bool MTF_IsSignalValid(string symbol, double minConfidence = 70.0)
{
    MTFEngine engine;
    if(engine.Initialize(NULL)) {
        bool result = engine.IsSignalValid(symbol, minConfidence);
        engine.Deinitialize();
        return result;
    }
    return false;
}

// ================= IMPLEMENTATION =================

MTFEngine::MTFEngine() : 
    STR_MTFENGINE("MTFEngine"),
    STR_MTFSCORE("MTFScore"),
    STR_NEUTRAL("NEUTRAL"),
    STR_BULLISH("BULLISH"),
    STR_BEARISH("BEARISH")
{
    m_symbol = _Symbol;
    m_maxComponents = 7;
    m_availableCount = 0;
    m_trendingMultiplier = 1.2;
    m_rangingMultiplier = 0.9;
    m_breakoutMultiplier = 1.3;
    m_reversalMultiplier = 1.1;
    m_logger = NULL;
    m_mtfScorer = NULL;
    m_ownsLogger = false;
    m_showOnlyImportant = true;
    m_minConfidenceForDisplay = 60;
    m_adxHandle = INVALID_HANDLE;
    m_atrHandle = INVALID_HANDLE;
    m_cachedBid = 0.0;
    m_lastBidUpdate = 0;
    m_lastContextDetection = 0;
    m_cachedContext = CONTEXT_CHOPPY;
    m_cachedSymbolForContext = "";
    m_forceRefresh = true;
    m_cacheValid = false;
    m_lastFullRefresh = 0;
    
    for(int i = 0; i < m_maxComponents; i++) {
        m_componentAvailability[i] = false;
        m_baseWeights[i] = 0;
        m_availableWeights[i] = 0;
    }
    
    ZeroMemory(m_currentAnalysis);
    m_initialized = false;
}

MTFEngine::~MTFEngine()
{
    if(m_initialized) {
        Deinitialize();
    }
}

bool MTFEngine::Initialize(ResourceManager* logger, MTFScorer* mtfScorer, string symbol,
                          bool showOnlyImportant, int minConfidenceForDisplay)
{
    if(m_initialized) {
        m_forceRefresh = true;
        m_cacheValid = false;
        return true;
    }
    
    if(StringLen(symbol) == 0) {
        symbol = _Symbol;
    }
    
    if(logger != NULL) {
        m_logger = logger;
        m_ownsLogger = false;
    } else {
        m_logger = new ResourceManager();
        m_ownsLogger = true;
        if(!m_logger.Initialize("MTFEngine_Journal.csv", true, true, true)) {
            delete m_logger;
            m_logger = NULL;
            m_ownsLogger = false;
            return false;
        }
    }
    
    if(mtfScorer != NULL) {
        m_mtfScorer = mtfScorer;
        LogImportant("Using provided MTFScorer instance", OBSERVE);
    } else {
        m_mtfScorer = new MTFScorer();
        if(!m_mtfScorer.Initialize(m_logger, symbol)) {
            LogImportant("Failed to initialize MTFScorer", WARN);
            delete m_mtfScorer;
            m_mtfScorer = NULL;
        } else {
            LogImportant("MTFScorer created and initialized", AUTHORIZE);
        }
    }
    
    m_symbol = symbol;
    m_showOnlyImportant = showOnlyImportant;
    m_minConfidenceForDisplay = minConfidenceForDisplay;
    
    InitializeComponents();
    InitializeIndicatorHandles(symbol);
    
    if(s_pointValue == 0.0) {
        s_pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    }
    
    RegisterComponent(STR_MTFSCORE, 40.0);
    
    m_initialized = true;
    LogImportant("Engine initialized", OBSERVE);
    
    return true;
}

void MTFEngine::InitializeIndicatorHandles(string symbol)
{
    if(m_adxHandle == INVALID_HANDLE) {
        m_adxHandle = iADX(symbol, PERIOD_H4, 14);
    }
    
    if(m_atrHandle == INVALID_HANDLE) {
        m_atrHandle = iATR(symbol, PERIOD_H4, 14);
    }
}

void MTFEngine::CleanupIndicatorHandles()
{
    if(m_adxHandle != INVALID_HANDLE) {
        IndicatorRelease(m_adxHandle);
        m_adxHandle = INVALID_HANDLE;
    }
    
    if(m_atrHandle != INVALID_HANDLE) {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
}

double MTFEngine::GetSymbolBid(string symbol)
{
    datetime currentTime = TimeCurrent();
    if(currentTime > m_lastBidUpdate + 1) {
        m_cachedBid = SymbolInfoDouble(symbol, SYMBOL_BID);
        m_lastBidUpdate = currentTime;
    }
    return m_cachedBid;
}

bool MTFEngine::IsAnalysisStale(datetime analysisTime, int maxSeconds)
{
    return (TimeCurrent() - analysisTime) >= maxSeconds;
}

bool MTFEngine::ShouldUseCache(string symbol)
{
    if(m_forceRefresh) return false;
    if(!m_cacheValid) return false;
    if(IsAnalysisStale(m_currentAnalysis.analysisTime)) return false;
    if(m_symbol != symbol) return false;
    if(m_currentAnalysis.totalConfidence < 40.0) return false;
    
    return true;
}

void MTFEngine::OnTick()
{
    if(!m_initialized) return;
    
    static datetime lastAnalysisTime = 0;
    datetime currentTime = TimeCurrent();
    if(currentTime - lastAnalysisTime < 1) return;
    
    m_forceRefresh = true;
    MTFAnalysis analysis = Analyze(_Symbol, true);
    lastAnalysisTime = currentTime;
    
    // Periodic status logging (every 5 minutes)
    if(currentTime - s_lastPeriodicLog >= 60) {
        LogPeriodicStatus();
        s_lastPeriodicLog = currentTime;
    }
}

void MTFEngine::OnTimer()
{
    if(!m_initialized) return;
    
    // Minimal timer processing
    if(m_logger != NULL) {
        s_logCount++;
    }
}

void MTFEngine::OnTradeTransaction()
{
    // No logging in trade transaction handler for performance
}

void MTFEngine::Deinitialize()
{
    if(!m_initialized) return;
    
    LogImportant("Engine deinitialized", OBSERVE);
    CleanupIndicatorHandles();
    
    if(m_logger != NULL && m_ownsLogger) {
        delete m_logger;
        m_logger = NULL;
        m_ownsLogger = false;
    }
    
    m_symbol = _Symbol;
    m_availableCount = 0;
    
    int maxComponents = m_maxComponents;
    for(int i = 0; i < maxComponents; i++) {
        m_componentAvailability[i] = false;
        m_baseWeights[i] = 0;
        m_availableWeights[i] = 0;
    }
    
    ZeroMemory(m_currentAnalysis);
    m_currentContext = CONTEXT_CHOPPY;
    m_cachedContext = CONTEXT_CHOPPY;
    m_lastContextDetection = 0;
    m_cachedSymbolForContext = "";
    m_forceRefresh = true;
    m_cacheValid = false;
    m_lastFullRefresh = 0;
    m_initialized = false;
}

void MTFEngine::InitializeComponents()
{
    // Component configurations (no logging)
    m_componentConfigs[0].componentName = STR_MTFSCORE;
    m_componentConfigs[0].baseWeight = 40.0;
    m_componentConfigs[0].minScoreThreshold = 0.0;
    m_componentConfigs[0].maxScoreThreshold = 100.0;
    m_componentConfigs[0].isRequired = true;
    
    m_componentConfigs[1].componentName = "MTFSSDDConfluence";
    m_componentConfigs[1].baseWeight = 15.0;
    m_componentConfigs[1].minScoreThreshold = 35.0;
    m_componentConfigs[1].maxScoreThreshold = 100.0;
    m_componentConfigs[1].isRequired = false;
    
    m_componentConfigs[2].componentName = "SwingFailurePattern";
    m_componentConfigs[2].baseWeight = 15.0;
    m_componentConfigs[2].minScoreThreshold = 30.0;
    m_componentConfigs[2].maxScoreThreshold = 100.0;
    m_componentConfigs[2].isRequired = false;
    
    m_componentConfigs[3].componentName = "MSS";
    m_componentConfigs[3].baseWeight = 10.0;
    m_componentConfigs[3].minScoreThreshold = 35.0;
    m_componentConfigs[3].maxScoreThreshold = 100.0;
    m_componentConfigs[3].isRequired = false;
    
    m_componentConfigs[4].componentName = "Trend";
    m_componentConfigs[4].baseWeight = 10.0;
    m_componentConfigs[4].minScoreThreshold = 25.0;
    m_componentConfigs[4].maxScoreThreshold = 100.0;
    m_componentConfigs[4].isRequired = false;
    
    m_componentConfigs[5].componentName = "OrderFlow";
    m_componentConfigs[5].baseWeight = 5.0;
    m_componentConfigs[5].minScoreThreshold = 20.0;
    m_componentConfigs[5].maxScoreThreshold = 100.0;
    m_componentConfigs[5].isRequired = false;
    
    m_componentConfigs[6].componentName = "Momentum";
    m_componentConfigs[6].baseWeight = 5.0;
    m_componentConfigs[6].minScoreThreshold = 15.0;
    m_componentConfigs[6].maxScoreThreshold = 100.0;
    m_componentConfigs[6].isRequired = false;
}

void MTFEngine::RegisterComponent(string componentName, double baseWeight)
{
    if(!m_initialized) return;
    
    int index = GetComponentIndex(componentName);
    if(index >= 0) {
        m_componentConfigs[index].baseWeight = baseWeight;
        m_componentAvailability[index] = true;
        m_availableCount++;
        m_cacheValid = false;
        m_forceRefresh = true;
        
        LogImportant(StringFormat("Component %s registered with weight %.1f", componentName, baseWeight), AUTHORIZE);
    } else {
        LogImportant(StringFormat("Failed to register component %s - not found", componentName), WARN);
    }
}

void MTFEngine::SetComponentAvailability(string componentName, bool isAvailable)
{
    if(!m_initialized) return;
    
    int index = GetComponentIndex(componentName);
    if(index >= 0) {
        bool wasAvailable = m_componentAvailability[index];
        m_componentAvailability[index] = isAvailable;
        
        if(isAvailable && !wasAvailable) {
            m_availableCount++;
        } else if(!isAvailable && wasAvailable) {
            m_availableCount--;
        }
        
        m_cacheValid = false;
        m_forceRefresh = true;
        
        if(wasAvailable != isAvailable) {
            LogImportant(StringFormat("Component %s availability changed to %s", 
                componentName, isAvailable ? "Available" : "Unavailable"), AUTHORIZE);
        }
    }
}

MTFAnalysis MTFEngine::Analyze(string symbol, bool forceRefresh)
{
    if(forceRefresh) {
        m_forceRefresh = true;
    }
    
    if(ShouldUseCache(symbol)) {
        return m_currentAnalysis;
    }
    
    m_symbol = symbol;
    
    if(m_mtfScorer != NULL && m_mtfScorer.IsInitialized() && !m_componentAvailability[0]) {
        RegisterComponent(STR_MTFSCORE, 40.0);
    }
    
    DetectContext(symbol);
    
    int componentCount = 0;
    int maxComponents = m_maxComponents;
    for(int i = 0; i < maxComponents; i++) {
        if(m_componentAvailability[i]) {
            ComponentScore score;
            score.componentName = m_componentConfigs[i].componentName;
            score.rawScore = GetComponentRawScore(score.componentName);
            score.baseWeight = m_componentConfigs[i].baseWeight;
            score.adjustedWeight = m_componentConfigs[i].baseWeight;
            score.rank = i + 1;
            score.isAvailable = true;
            
            m_currentAnalysis.components[componentCount] = score;
            componentCount++;
        }
    }
    
    if(componentCount == 0) {
        ComponentScore defaultScore;
        defaultScore.componentName = STR_MTFSCORE;
        defaultScore.rawScore = 50.0;
        defaultScore.baseWeight = 100.0;
        defaultScore.adjustedWeight = 100.0;
        defaultScore.rank = 1;
        defaultScore.isAvailable = true;
        
        m_currentAnalysis.components[0] = defaultScore;
        componentCount = 1;
    }
    
    m_availableCount = componentCount;
    
    DistributeWeights();
    AdjustWeightsForContext();
    NormalizeScores();
    CalculateTotalConfidence();
    
    m_currentAnalysis.signal = GenerateSignal();
    m_currentAnalysis.primaryBias = DetermineBias();
    m_currentAnalysis.marketBiasStrength = CalculateBiasStrength();
    m_currentAnalysis.isConfluent = CheckConfluence();
    m_currentAnalysis.divergenceScore = CalculateDivergence();
    m_currentAnalysis.analysisTime = TimeCurrent();
    m_currentAnalysis.context = m_currentContext;
    m_currentAnalysis.recommendedAction = CalculateRecommendedAction(m_currentAnalysis);
    
    m_cacheValid = true;
    m_forceRefresh = false;
    m_lastFullRefresh = TimeCurrent();
    
    LogAnalysisResult();
    return m_currentAnalysis;
}

double MTFEngine::GetComponentRawScore(string componentName)
{
    if(!m_initialized) {
        return GetDefaultScore(componentName);
    }
    
    double score = 0;
    
    if(componentName == STR_MTFSCORE) {
        score = GetMTFScore(m_symbol);
    }
    else if(componentName == "MTFSSDDConfluence") {
        score = GetMTFSSDDConfluence(m_symbol);
    }
    else if(componentName == "SwingFailurePattern") {
        score = GetSwingFailurePatternScore(m_symbol);
    }
    else if(componentName == "MSS") {
        score = GetMSSScore(m_symbol);
    }
    else if(componentName == "Trend") {
        score = GetTrendScore(m_symbol);
    }
    else if(componentName == "OrderFlow") {
        score = GetOrderFlowScore(m_symbol);
    }
    else if(componentName == "Momentum") {
        score = GetMomentumScore(m_symbol);
    }
    else {
        score = GetDefaultScore(componentName);
    }
    
    return score;
}

double MTFEngine::GetADXValue(string symbol)
{
    if(m_adxHandle == INVALID_HANDLE) {
        InitializeIndicatorHandles(symbol);
    }
    
    if(m_adxHandle != INVALID_HANDLE) {
        double buffer[1];
        if(CopyBuffer(m_adxHandle, 0, 0, 1, buffer) > 0) {
            return buffer[0];
        }
    }
    
    return iADX(symbol, PERIOD_H4, 14);
}

double MTFEngine::GetATRPercent(string symbol)
{
    if(m_atrHandle == INVALID_HANDLE) {
        InitializeIndicatorHandles(symbol);
    }
    
    double atrValue = 0;
    
    if(m_atrHandle != INVALID_HANDLE) {
        double buffer[1];
        if(CopyBuffer(m_atrHandle, 0, 0, 1, buffer) > 0) {
            atrValue = buffer[0];
        }
    } else {
        atrValue = iATR(symbol, PERIOD_H4, 14);
    }
    
    double bid = GetSymbolBid(symbol);
    if(bid > 0) {
        return (atrValue / bid) * 100;
    }
    
    return 0.0;
}

double MTFEngine::GetMTFScore(string symbol)
{
    if(!m_initialized) {
        if(!Initialize(NULL, NULL, symbol)) {
            return 50.0;
        }
    }
    
    double score = 50.0;
    
    if(m_mtfScorer != NULL && m_mtfScorer.IsInitialized()) {
        MTFScore mtfScore = m_mtfScorer.CalculateScore();
        score = mtfScore.total;
    } else {
        if(m_mtfScorer == NULL) {
            m_mtfScorer = new MTFScorer();
            if(!m_mtfScorer.Initialize(m_logger, symbol)) {
                delete m_mtfScorer;
                m_mtfScorer = NULL;
            } else {
                MTFScore mtfScore = m_mtfScorer.CalculateScore();
                score = mtfScore.total;
            }
        }
    }
    
    return score;
}

double MTFEngine::GetMTFSSDDConfluence(string symbol) { return 50.0; }
double MTFEngine::GetSwingFailurePatternScore(string symbol) { return 50.0; }
double MTFEngine::GetMSSScore(string symbol) { return 50.0; }
double MTFEngine::GetTrendScore(string symbol) { return 50.0; }
double MTFEngine::GetOrderFlowScore(string symbol) { return 50.0; }
double MTFEngine::GetMomentumScore(string symbol) { return 50.0; }

double MTFEngine::GetDefaultScore(string componentName)
{
    return 50.0;
}

void MTFEngine::DistributeWeights()
{
    if(!m_initialized) return;
    
    double totalBaseWeight = 0;
    int availableComponents = 0;
    
    int maxComponents = m_maxComponents;
    for(int i = 0; i < maxComponents; i++) {
        if(m_componentAvailability[i]) {
            totalBaseWeight += m_componentConfigs[i].baseWeight;
            availableComponents++;
        }
    }
    
    if(availableComponents == 0) {
        if(m_currentAnalysis.components[0].componentName != "") {
            m_currentAnalysis.components[0].adjustedWeight = 100.0;
        }
        return;
    }
    
    double redistributionFactor = 100.0 / totalBaseWeight;
    
    int availableCount = m_availableCount;
    for(int i = 0; i < availableCount; i++) {
        string compName = m_currentAnalysis.components[i].componentName;
        int configIndex = GetComponentIndex(compName);
        
        if(configIndex >= 0) {
            double newWeight = m_componentConfigs[configIndex].baseWeight * redistributionFactor;
            m_currentAnalysis.components[i].adjustedWeight = newWeight;
        }
    }
}

void MTFEngine::AdjustWeightsForContext()
{
    if(!m_initialized) return;
    
    double multiplier = 1.0;
    int availableCount = m_availableCount;
    
    switch(m_currentContext) {
        case CONTEXT_TRENDING:
            multiplier = m_trendingMultiplier;
            for(int i = 0; i < availableCount; i++) {
                string compName = m_currentAnalysis.components[i].componentName;
                if(compName == "Trend" || compName == "Momentum") {
                    m_currentAnalysis.components[i].adjustedWeight *= multiplier;
                }
            }
            break;
            
        case CONTEXT_RANGING:
            multiplier = m_rangingMultiplier;
            for(int i = 0; i < availableCount; i++) {
                string compName = m_currentAnalysis.components[i].componentName;
                if(compName == "SwingFailurePattern" || compName == "MTFSSDDConfluence") {
                    m_currentAnalysis.components[i].adjustedWeight *= multiplier;
                }
            }
            break;
            
        case CONTEXT_BREAKOUT:
            multiplier = m_breakoutMultiplier;
            for(int i = 0; i < availableCount; i++) {
                string compName = m_currentAnalysis.components[i].componentName;
                if(compName == "MSS" || compName == STR_MTFSCORE) {
                    m_currentAnalysis.components[i].adjustedWeight *= multiplier;
                }
            }
            break;
            
        case CONTEXT_REVERSAL:
            multiplier = m_reversalMultiplier;
            for(int i = 0; i < availableCount; i++) {
                string compName = m_currentAnalysis.components[i].componentName;
                if(compName == "SwingFailurePattern" || compName == "OrderFlow") {
                    m_currentAnalysis.components[i].adjustedWeight *= multiplier;
                }
            }
            break;
    }
    
    RebalanceWeights();
}

void MTFEngine::RebalanceWeights()
{
    if(!m_initialized) return;
    
    double totalWeight = 0;
    int componentCount = 0;
    
    int maxComponents = m_maxComponents;
    for(int i = 0; i < maxComponents; i++) {
        if(m_currentAnalysis.components[i].componentName != "") {
            totalWeight += m_currentAnalysis.components[i].adjustedWeight;
            componentCount++;
        }
    }
    
    if(componentCount == 0 || totalWeight == 0) return;
    
    double rebalanceFactor = 100.0 / totalWeight;
    
    for(int i = 0; i < componentCount; i++) {
        m_currentAnalysis.components[i].adjustedWeight *= rebalanceFactor;
    }
}

void MTFEngine::NormalizeScores()
{
    if(!m_initialized) return;
    
    int availableCount = m_availableCount;
    for(int i = 0; i < availableCount; i++) {
        double rawScore = m_currentAnalysis.components[i].rawScore;
        double minThreshold = 0;
        double maxThreshold = 100;
        
        int configIndex = GetComponentIndex(m_currentAnalysis.components[i].componentName);
        if(configIndex >= 0) {
            minThreshold = m_componentConfigs[configIndex].minScoreThreshold;
            maxThreshold = m_componentConfigs[configIndex].maxScoreThreshold;
        }
        
        double normalizedScore;
        if(rawScore < minThreshold) {
            normalizedScore = 0;
        } else if(rawScore > maxThreshold) {
            normalizedScore = 100;
        } else {
            double normalized = ((rawScore - minThreshold) / (maxThreshold - minThreshold)) * 100;
            normalizedScore = MathMax(0, MathMin(100, normalized));
        }
        
        m_currentAnalysis.components[i].normalizedScore = normalizedScore;
    }
}

void MTFEngine::CalculateTotalConfidence()
{
    if(!m_initialized) return;
    
    double weightedSum = 0;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        ComponentScore comp = m_currentAnalysis.components[i];
        comp.weightedScore = (comp.normalizedScore * comp.adjustedWeight) / 100.0;
        weightedSum += comp.weightedScore;
        m_currentAnalysis.components[i] = comp;
    }
    
    m_currentAnalysis.totalConfidence = MathMin(100.0, MathMax(0.0, weightedSum));
}

int MTFEngine::GetComponentIndex(string componentName)
{
    int maxComponents = m_maxComponents;
    for(int i = 0; i < maxComponents; i++) {
        if(m_componentConfigs[i].componentName == componentName) {
            return i;
        }
    }
    return -1;
}

void MTFEngine::DetectContext(string symbol)
{
    if(!m_initialized) return;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - m_lastContextDetection < 2 && m_cachedSymbolForContext == symbol) {
        m_currentContext = m_cachedContext;
        return;
    }
    
    double adx = GetADXValue(symbol);
    double atrPercent = GetATRPercent(symbol);
    
    MTF_CONTEXT detectedContext = CONTEXT_CHOPPY;
    
    if(adx > 25) {
        detectedContext = CONTEXT_TRENDING;
    }
    else if(atrPercent < 0.3) {
        detectedContext = CONTEXT_RANGING;
    }
    else {
        static double highBuffer[11];
        static double lowBuffer[11];
        
        int copiedHigh = CopyHigh(symbol, PERIOD_D1, 0, 11, highBuffer);
        int copiedLow = CopyLow(symbol, PERIOD_D1, 0, 11, lowBuffer);
        
        if(copiedHigh >= 11 && copiedLow >= 11) {
            double currentRange = highBuffer[0] - lowBuffer[0];
            double avgRange = 0;
            
            for(int i = 10; i >= 1; i--) {
                avgRange += highBuffer[i] - lowBuffer[i];
            }
            avgRange /= 10;
            
            if(currentRange > avgRange * 1.5) {
                detectedContext = CONTEXT_BREAKOUT;
            } else {
                detectedContext = CONTEXT_REVERSAL;
            }
        }
    }
    
    m_currentContext = detectedContext;
    m_cachedContext = detectedContext;
    m_cachedSymbolForContext = symbol;
    m_lastContextDetection = currentTime;
}

MTF_SIGNAL MTFEngine::GenerateSignal()
{
    if(!m_initialized) return MTF_SIGNAL_NEUTRAL;
    
    if(m_currentAnalysis.totalConfidence < 50) {
        return MTF_SIGNAL_NEUTRAL;
    }
    
    double bullScore = 0, bearScore = 0;
    double totalWeight = 0;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        ComponentScore comp = m_currentAnalysis.components[i];
        
        if(comp.normalizedScore > 60) {
            bullScore += comp.weightedScore;
        } else if(comp.normalizedScore < 40) {
            bearScore += comp.weightedScore;
        }
        
        totalWeight += comp.adjustedWeight;
    }
    
    if(totalWeight > 0) {
        bullScore = (bullScore / totalWeight) * 100;
        bearScore = (bearScore / totalWeight) * 100;
    }
    
    if(bullScore > bearScore && bullScore > 60) {
        return MTF_SIGNAL_STRONG_BUY;
    }
    else if(bullScore > bearScore && bullScore > 40) {
        return MTF_SIGNAL_WEAK_BUY;
    }
    else if(bearScore > bullScore && bearScore > 60) {
        return MTF_SIGNAL_STRONG_SELL;
    }
    else if(bearScore > bullScore && bearScore > 40) {
        return MTF_SIGNAL_WEAK_SELL;
    }
    
    return MTF_SIGNAL_NEUTRAL;
}

string MTFEngine::DetermineBias()
{
    if(!m_initialized) return STR_NEUTRAL;
    
    double avgScore = 0;
    double totalWeight = 0;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        avgScore += m_currentAnalysis.components[i].normalizedScore * 
                   m_currentAnalysis.components[i].adjustedWeight;
        totalWeight += m_currentAnalysis.components[i].adjustedWeight;
    }
    
    if(totalWeight > 0) {
        avgScore /= totalWeight;
    }
    
    string bias;
    if(avgScore > 70) bias = "STRONG_BULLISH";
    else if(avgScore > 55) bias = STR_BULLISH;
    else if(avgScore > 45) bias = STR_NEUTRAL;
    else if(avgScore > 30) bias = STR_BEARISH;
    else bias = "STRONG_BEARISH";
    
    m_currentAnalysis.primaryBias = bias;
    return bias;
}

double MTFEngine::CalculateBiasStrength()
{
    if(!m_initialized) return 0.0;
    
    double avgScore = 0;
    double totalWeight = 0;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        avgScore += m_currentAnalysis.components[i].normalizedScore * 
                   m_currentAnalysis.components[i].adjustedWeight;
        totalWeight += m_currentAnalysis.components[i].adjustedWeight;
    }
    
    if(totalWeight > 0) {
        avgScore /= totalWeight;
    }
    
    double strength = MathAbs(avgScore - 50) * 2;
    return MathMin(100.0, MathMax(0.0, strength));
}

bool MTFEngine::CheckConfluence()
{
    if(!m_initialized) return false;
    
    if(m_availableCount < 2) {
        m_currentAnalysis.isConfluent = true;
        return true;
    }
    
    int bullishCount = 0, bearishCount = 0;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        double score = m_currentAnalysis.components[i].normalizedScore;
        
        if(score > 60) bullishCount++;
        else if(score < 40) bearishCount++;
    }
    
    bool confluence = (bullishCount >= availableCount * 0.6) || 
                      (bearishCount >= availableCount * 0.6);
    
    m_currentAnalysis.isConfluent = confluence;
    return confluence;
}

double MTFEngine::CalculateDivergence()
{
    if(!m_initialized) return 100.0;
    
    if(m_availableCount < 2) {
        m_currentAnalysis.divergenceScore = 0.0;
        return 0.0;
    }
    
    double maxScore = 0, minScore = 100;
    int availableCount = m_availableCount;
    
    for(int i = 0; i < availableCount; i++) {
        double score = m_currentAnalysis.components[i].normalizedScore;
        maxScore = MathMax(maxScore, score);
        minScore = MathMin(minScore, score);
    }
    
    double divergence = maxScore - minScore;
    m_currentAnalysis.divergenceScore = divergence;
    return divergence;
}

double MTFEngine::GetOverallConfidence(string symbol, bool forceRefresh)
{
    if(!m_initialized) return 0.0;
    
    MTFAnalysis analysis = Analyze(symbol, forceRefresh);
    return analysis.totalConfidence;
}

string MTFEngine::GetMarketBias(string symbol, bool forceRefresh)
{
    if(!m_initialized) return STR_NEUTRAL;
    
    MTFAnalysis analysis = Analyze(symbol, forceRefresh);
    return analysis.primaryBias;
}

MTF_SIGNAL MTFEngine::GetSignal(string symbol, bool forceRefresh)
{
    if(!m_initialized) return MTF_SIGNAL_NEUTRAL;
    
    MTFAnalysis analysis = Analyze(symbol, forceRefresh);
    return analysis.signal;
}

string MTFEngine::GetRecommendedAction(string symbol)
{
    if(!m_initialized) return "WAIT";
    
    if(StringLen(m_currentAnalysis.recommendedAction) == 0 || 
       IsAnalysisStale(m_currentAnalysis.analysisTime)) {
        MTFAnalysis analysis = Analyze(symbol);
        return analysis.recommendedAction;
    }
    
    return m_currentAnalysis.recommendedAction;
}

string MTFEngine::CalculateRecommendedAction(MTFAnalysis& analysis)
{
    string action = "WAIT";
    
    if(analysis.totalConfidence >= 80 && analysis.isConfluent) {
        if(analysis.signal == MTF_SIGNAL_STRONG_BUY) action = "STRONG_BUY";
        else if(analysis.signal == MTF_SIGNAL_STRONG_SELL) action = "STRONG_SELL";
    }
    else if(analysis.totalConfidence >= 60) {
        if(analysis.signal == MTF_SIGNAL_WEAK_BUY || analysis.signal == MTF_SIGNAL_STRONG_BUY) {
            action = "CAUTIOUS_BUY";
        }
        else if(analysis.signal == MTF_SIGNAL_WEAK_SELL || analysis.signal == MTF_SIGNAL_STRONG_SELL) {
            action = "CAUTIOUS_SELL";
        }
    }
    else if(analysis.totalConfidence >= 40) {
        action = "MONITOR";
    }
    
    return action;
}

bool MTFEngine::IsSignalValid(string symbol, double minConfidence)
{
    if(!m_initialized) return false;
    
    MTFAnalysis analysis = Analyze(symbol, true);
    
    bool isValid = (analysis.totalConfidence >= minConfidence && 
                    analysis.signal != MTF_SIGNAL_NEUTRAL &&
                    analysis.isConfluent);
    
    if(isValid) {
        LogImportant(StringFormat("Signal validated with %.1f confidence", analysis.totalConfidence), AUTHORIZE);
    } else {
        LogImportant(StringFormat("Signal invalid (Confidence: %.1f)", analysis.totalConfidence), WARN);
    }
    
    return isValid;
}

double MTFEngine::GetComponentScore(string componentName)
{
    if(!m_initialized) return 0.0;
    
    int availableCount = m_availableCount;
    for(int i = 0; i < availableCount; i++) {
        if(m_currentAnalysis.components[i].componentName == componentName) {
            return m_currentAnalysis.components[i].normalizedScore;
        }
    }
    
    return 0.0;
}

MTF_CONTEXT MTFEngine::GetMarketContext(string symbol)
{
    if(!m_initialized) return CONTEXT_CHOPPY;
    
    DetectContext(symbol);
    return m_currentContext;
}

void MTFEngine::SetDisplayMinConfidence(int minConfidence)
{
    m_minConfidenceForDisplay = minConfidence;
}

void MTFEngine::LogImportant(string message, RESOURCE_MANAGER level)
{
    if(m_logger != NULL) {
        m_logger.KeepNotes(m_symbol, level, STR_MTFENGINE, message, false);
    }
}

void MTFEngine::LogPeriodicStatus()
{
    if(!m_initialized || m_logger == NULL) return;
    
    string status = StringFormat("Periodic Status - Analysis count: %d, Cache hits: %d", 
                                s_logCount, (s_logCount > 0 ? (int)((s_logCount - 1) * 100 / s_logCount) : 0));
    LogImportant(status, OBSERVE);
}

void MTFEngine::LogAnalysisResult()
{
    if(!m_initialized || m_logger == NULL) return;
    
    // Only log important analysis results
    if(m_currentAnalysis.totalConfidence >= m_minConfidenceForDisplay) {
        string signalStr = GetSignalString(m_currentAnalysis.signal);
        string message = StringFormat("Analysis: %s (Confidence: %.1f%%, Bias: %s)", 
                                     signalStr, m_currentAnalysis.totalConfidence, 
                                     m_currentAnalysis.primaryBias);
        LogImportant(message, AUTHORIZE);
    }
}

string GetSignalString(MTF_SIGNAL signal)
{
    switch(signal) {
        case MTF_SIGNAL_STRONG_BUY: return "STRONG BUY";
        case MTF_SIGNAL_STRONG_SELL: return "STRONG SELL";
        case MTF_SIGNAL_WEAK_BUY: return "WEAK BUY";
        case MTF_SIGNAL_WEAK_SELL: return "WEAK SELL";
        case MTF_SIGNAL_NEUTRAL: return "NEUTRAL";
        default: return "NONE";
    }
}

string GetContextString(MTF_CONTEXT context)
{
    switch(context) {
        case CONTEXT_TRENDING: return "TRENDING";
        case CONTEXT_RANGING: return "RANGING";
        case CONTEXT_BREAKOUT: return "BREAKOUT";
        case CONTEXT_REVERSAL: return "REVERSAL";
        case CONTEXT_CHOPPY: return "CHOPPY";
    }
    return "UNKNOWN";
}