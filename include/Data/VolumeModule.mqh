//+------------------------------------------------------------------+
//|                           VolumeModule.mqh                       |
//|                Integrated with IndicatorManager                  |
//|                DECOUPLED FROM TRADEPACKAGE DEPENDENCY            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict
#property version   "1.00"

#include "../Utils/Logger.mqh"
#include "IndicatorManager.mqh"

// Debug settings
bool VOLUME_DEBUG_ENABLED = false;

// Volume analysis result structure
struct VolumeAnalysisResult
{
    double momentumScore;     // -100 to +100 (positive = confirms, negative = contradicts)
    double convictionScore;   // 0-100 (strength of conviction)
    string prediction;        // "BULLISH", "BEARISH", "NEUTRAL", "WEAK_BULL", "WEAK_BEAR"
    bool divergence;          // true if volume-price divergence detected
    bool climax;              // true if volume climax/exhaustion detected
    string volumeStatus;      // Text description of volume level
    double volumeRatio;       // Current volume / average volume
    string warning;           // Any warnings (divergence, climax, etc.)
    datetime timestamp;       // Analysis timestamp
    
    // ====== BIAS SCORES ======
    struct BiasScores {
        double bullScore;        // 0-100 for bullish bias strength
        double bearScore;        // 0-100 for bearish bias strength
        double overallConfidence; // 0-100 overall confidence score
        string primaryBias;      // "BULLISH", "BEARISH", "NEUTRAL"
        bool isBullish;          // Quick boolean for bullish
        bool isBearish;          // Quick boolean for bearish
    } bias;
    
    // ====== VOLUME ANALYSIS DATA ======
    struct VolumeData {
        double weightedScore;      // 0-100 weighted volume score
        double directionScore;     // -100 to +100 (negative bearish, positive bullish)
        string recommendation;     // "BUY", "SELL", "HOLD", "CONFIRM", "AVOID"
        double reliabilityScore;   // 0-100 how reliable this volume signal is
        bool hasStrongSignal;      // True if strong volume confirmation
        bool hasWarning;           // True if any warnings present
        string volumeContext;      // "SPIKE", "CLIMAX", "DIVERGENCE", "NORMAL"
    } volume;
    
    // Initialize constructor
    VolumeAnalysisResult() {
        ZeroMemory(this);
        prediction = "NEUTRAL";
        volumeStatus = "NORMAL";
        warning = "";
        timestamp = TimeCurrent();
        
        // Initialize bias scores
        bias.bullScore = 0;
        bias.bearScore = 0;
        bias.overallConfidence = 50;
        bias.primaryBias = "NEUTRAL";
        bias.isBullish = false;
        bias.isBearish = false;
        
        // Initialize volume data
        volume.weightedScore = 50;
        volume.directionScore = 0;
        volume.recommendation = "HOLD";
        volume.reliabilityScore = 50;
        volume.hasStrongSignal = false;
        volume.hasWarning = false;
        volume.volumeContext = "NORMAL";
    }
};

// ==================== VOLUME MODULE CLASS ====================
class VolumeModule
{
private:
    string m_symbol;
    IndicatorManager* m_indicatorManager;
    bool m_initialized;
    double m_volumeSpikeThreshold;
    double m_climaxThreshold;
    ENUM_TIMEFRAMES m_defaultTF;
    
    // Configuration parameters
    struct ModuleConfig {
        bool enableDetailedOutput;    // Enable detailed analysis output
        double bullBiasWeight;        // Weight for bullish bias (0-1)
        double bearBiasWeight;        // Weight for bearish bias (0-1)
        double confidenceBoostOnSpike; // Boost confidence on volume spikes
        double penaltyOnDivergence;    // Penalty on divergence signals
        double climaxWarningThreshold; // Threshold for climax warnings
    } m_config;
    
public:
    // CONSTRUCTOR
    VolumeModule()
    {
        m_symbol = "";
        m_indicatorManager = NULL;
        m_initialized = false;
        m_volumeSpikeThreshold = 2.0;    // 2x average = spike
        m_climaxThreshold = 1.5;         // 1.5x max = climax
        m_defaultTF = PERIOD_H1;
        
        // Initialize configuration
        m_config.enableDetailedOutput = true;
        m_config.bullBiasWeight = 0.6;    // Slightly favor bullish confirmation
        m_config.bearBiasWeight = 0.6;    // Same for bearish
        m_config.confidenceBoostOnSpike = 1.2;  // 20% boost on spikes
        m_config.penaltyOnDivergence = 0.7;     // 30% penalty on divergence
        m_config.climaxWarningThreshold = 3.0;  // Extreme spike threshold
        
        if(VOLUME_DEBUG_ENABLED)
            Logger::Log("VolumeModule", "Module created");
    }
    
    // DESTRUCTOR
    ~VolumeModule()
    {
        Deinitialize();
    }
    
    // INITIALIZE with IndicatorManager
    bool Initialize(IndicatorManager* indicatorMgr, string symbol = NULL)
    {
        if(m_initialized)
        {
            Logger::Log("VolumeModule", "Already initialized");
            return true;
        }
        
        if(indicatorMgr == NULL)
        {
            Logger::LogError("VolumeModule", "IndicatorManager is NULL");
            return false;
        }
        
        if(!indicatorMgr.IsInitialized())
        {
            Logger::LogError("VolumeModule", "IndicatorManager not initialized");
            return false;
        }
        
        m_indicatorManager = indicatorMgr;
        m_symbol = (symbol == NULL) ? indicatorMgr.GetSymbol() : symbol;
        m_initialized = true;
        
        Logger::Log("VolumeModule", 
            StringFormat("Initialized for %s using IndicatorManager", m_symbol));
        return true;
    }
    
    // DEINITIALIZE
    void Deinitialize()
    {
        if(!m_initialized) return;
        
        m_initialized = false;
        m_indicatorManager = NULL;
        Logger::Log("VolumeModule", "Deinitialized");
    }
    
    // ==================== MAIN ANALYSIS METHODS ====================
    
    // COMPREHENSIVE VOLUME ANALYSIS
    VolumeAnalysisResult Analyze(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, 
                                int lookback = 20, 
                                int fastPeriod = 5)
    {
        VolumeAnalysisResult result;
        
        if(!m_initialized)
        {
            result.warning = "Module not initialized";
            return result;
        }
        
        // Use default if current
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        // Get price and volume data
        double prices[], volumes[];
        if(!GetPriceVolumeData(tf, lookback, fastPeriod, prices, volumes))
        {
            result.warning = "Failed to get price/volume data";
            return result;
        }
        
        // 1. MOMENTUM VALIDATION (-100 to +100)
        result.momentumScore = ValidateMomentum(prices, volumes, fastPeriod);
        
        // 2. CONVICTION SCORE (0-100)
        result.convictionScore = GetConvictionScore(volumes, lookback);
        
        // 3. VOLUME RATIO
        result.volumeRatio = GetVolumeRatio(volumes, lookback);
        
        // 4. PREDICTION
        result.prediction = GetPrediction(prices, volumes, fastPeriod);
        
        // 5. DIVERGENCE DETECTION
        result.divergence = CheckDivergence(prices, volumes, fastPeriod);
        
        // 6. CLIMAX DETECTION
        result.climax = IsClimax(volumes, lookback);
        
        // 7. VOLUME STATUS
        result.volumeStatus = GetVolumeStatusText(result.volumeRatio);
        
        // 8. WARNINGS
        if(result.divergence) result.warning += "DIVERGENCE ";
        if(result.climax) result.warning += "CLIMAX ";
        if(result.volumeRatio > m_volumeSpikeThreshold) result.warning += "SPIKE ";
        if(result.momentumScore < -30) result.warning += "WEAK_CONFIRMATION ";
        
        // Clean up warnings
        StringTrimRight(result.warning);
        
        // ====== CALCULATE BIAS SCORES ======
        CalculateBiasScores(result);
        
        // ====== CALCULATE VOLUME ANALYSIS DATA ======
        CalculateVolumeData(result);
        
        // Debug logging
        if(VOLUME_DEBUG_ENABLED)
        {
            Logger::Log("VolumeModule",
                StringFormat("Analysis: %s | Bull:%.0f Bear:%.0f Conf:%.0f | Score:%.0f Rec:%s",
                result.prediction, 
                result.bias.bullScore,
                result.bias.bearScore,
                result.bias.overallConfidence,
                result.volume.weightedScore,
                result.volume.recommendation));
        }
        
        return result;
    }
    
    // GET SIMPLIFIED ANALYSIS RESULTS
    struct SimpleVolumeResult {
        double score;           // 0-100 overall volume score
        string direction;       // "BULLISH", "BEARISH", "NEUTRAL"
        double confidence;      // 0-100 confidence level
        bool hasWarning;        // True if warnings present
        string warningType;     // Type of warning if any
        double volumeRatio;     // Current volume / average volume
    };
    
    SimpleVolumeResult GetSimpleAnalysis(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        SimpleVolumeResult simple;
        ZeroMemory(simple);
        simple.score = 50;
        simple.direction = "NEUTRAL";
        simple.confidence = 50;
        
        if(!m_initialized) return simple;
        
        VolumeAnalysisResult detailed = Analyze(tf);
        
        simple.score = detailed.volume.weightedScore;
        simple.direction = detailed.bias.primaryBias;
        simple.confidence = detailed.bias.overallConfidence;
        simple.hasWarning = (detailed.warning != "");
        simple.warningType = detailed.warning;
        simple.volumeRatio = detailed.volumeRatio;
        
        return simple;
    }
    
    // GET VOLUME COMPONENT DATA FOR EXTERNAL SYSTEMS
    struct ComponentData {
        string name;           // Component name
        string direction;      // Direction: "BULLISH", "BEARISH", "NEUTRAL"
        double strength;       // Strength score 0-100
        double confidence;     // Confidence score 0-100
        bool isActive;         // Is component active
        string details;        // Detailed information
    };
    
    ComponentData GetComponentData(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        ComponentData component;
        component.name = "VOL";
        
        if(!m_initialized)
        {
            component.direction = "NEUTRAL";
            component.strength = 0;
            component.confidence = 0;
            component.isActive = false;
            component.details = "Not initialized";
            return component;
        }
        
        VolumeAnalysisResult analysis = Analyze(tf);
        
        // Set component data
        component.direction = GetSimpleDirection(analysis);
        component.strength = analysis.volume.weightedScore;
        component.confidence = analysis.bias.overallConfidence;
        component.isActive = true;
        
        // Build details string
        string details = StringFormat("Mom:%.0f Conv:%.0f Ratio:%.1f", 
            analysis.momentumScore, 
            analysis.convictionScore,
            analysis.volumeRatio);
        
        if(analysis.warning != "")
            details += " " + analysis.warning;
        
        component.details = details;
        
        return component;
    }
    
    // ==================== QUICK CHECK METHODS ====================
    
    // SIMPLIFIED ANALYSIS (returns score 0-100)
    double GetVolumeScore(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, 
                         bool isBullishMove = true)
    {
        if(!m_initialized) return 50.0;
        
        VolumeAnalysisResult analysis = Analyze(tf);
        
        // Base score on conviction
        double score = analysis.convictionScore;
        
        // Adjust based on momentum validation
        if(isBullishMove)
        {
            if(analysis.momentumScore > 0) score += 15;
            else if(analysis.momentumScore < 0) score -= 15;
        }
        else
        {
            if(analysis.momentumScore > 0) score -= 15;
            else if(analysis.momentumScore < 0) score += 15;
        }
        
        // Penalize for warnings
        if(analysis.divergence) score -= 20;
        if(analysis.climax) score -= 25;
        
        return MathMax(0, MathMin(100, score));
    }
    
    // Check if volume confirms price move
    bool IsVolumeConfirming(ENUM_TIMEFRAMES tf, bool expectingBullish)
    {
        if(!m_initialized) return false;
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double priceChange = iClose(m_symbol, tf, 0) - iClose(m_symbol, tf, 1);
        double volCurrent = m_indicatorManager.GetVolume(tf, 0);
        double volPrev = m_indicatorManager.GetVolume(tf, 1);
        
        if(MathAbs(priceChange) < 0.00001) return true; // No significant price move
        
        if(expectingBullish)
            return (priceChange > 0 && volCurrent > volPrev);
        else
            return (priceChange < 0 && volCurrent > volPrev);
    }
    
    // Check for volume spike
    bool HasSpike(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, double threshold = 2.0)
    {
        if(!m_initialized) return false;
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double currentVol = m_indicatorManager.GetVolume(tf, 0);
        double avgVol = 0;
        
        for(int i = 1; i <= 20; i++)
            avgVol += m_indicatorManager.GetVolume(tf, i);
        avgVol /= 20.0;
        
        if(avgVol <= 0) return false;
        
        bool spike = (currentVol > avgVol * threshold);
        
        if(spike && VOLUME_DEBUG_ENABLED)
        {
            DebugLogVolume("HasSpike",
                StringFormat("Volume spike on %s: %.0f > %.0fx average",
                EnumToString(tf), currentVol, currentVol/avgVol));
        }
        
        return spike;
    }
    
    // ==================== UTILITY METHODS ====================
    
    // Set volume spike threshold
    void SetSpikeThreshold(double threshold) { m_volumeSpikeThreshold = threshold; }
    
    // Set climax threshold
    void SetClimaxThreshold(double threshold) { m_climaxThreshold = threshold; }
    
    // Set default timeframe
    void SetDefaultTimeframe(ENUM_TIMEFRAMES tf) { m_defaultTF = tf; }
    
    // Get initialization status
    bool IsInitialized() const { return m_initialized; }
    
    // Get symbol
    string GetSymbol() const { return m_symbol; }
    
    // Configure module settings
    void Configure(bool enableDetailedOutput = true, double bullWeight = 0.6, 
                   double bearWeight = 0.6)
    {
        m_config.enableDetailedOutput = enableDetailedOutput;
        m_config.bullBiasWeight = MathMax(0, MathMin(1, bullWeight));
        m_config.bearBiasWeight = MathMax(0, MathMin(1, bearWeight));
    }
    
    // Display volume analysis on chart
    void DisplayOnChart(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int corner = 2, 
                       int x = 10, int y = 20)
    {
        if(!m_initialized) return;
        
        VolumeAnalysisResult analysis = Analyze(tf);
        
        string text = StringFormat(
            "Volume Analysis (%s):\n" +
            "Status: %s\n" +
            "Momentum: %.0f\n" +
            "Conviction: %.0f\n" +
            "Prediction: %s\n" +
            "Warnings: %s\n" +
            "Bias: Bull %.0f / Bear %.0f\n" +
            "Confidence: %.0f%%\n" +
            "Recommendation: %s",
            EnumToString(tf),
            analysis.volumeStatus,
            analysis.momentumScore,
            analysis.convictionScore,
            analysis.prediction,
            analysis.warning,
            analysis.bias.bullScore,
            analysis.bias.bearScore,
            analysis.bias.overallConfidence,
            analysis.volume.recommendation
        );
        
        string objName = "VolumeModule_Display_" + EnumToString(tf);
        ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
    }
    
    // Get raw volume data
    struct RawVolumeData {
        double currentVolume;
        double averageVolume;
        double maxVolume;
        double minVolume;
        double volumeStdDev;
    };
    
    RawVolumeData GetRawVolumeData(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20)
    {
        RawVolumeData data;
        ZeroMemory(data);
        
        if(!m_initialized || m_indicatorManager == NULL) return data;
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double volumes[];
        ArrayResize(volumes, lookback);
        
        // Collect volume data
        for(int i = 0; i < lookback; i++) {
            volumes[i] = m_indicatorManager.GetVolume(tf, i);
        }
        
        // Calculate statistics
        data.currentVolume = volumes[0];
        data.maxVolume = volumes[0];
        data.minVolume = volumes[0];
        double sum = 0;
        
        for(int i = 0; i < lookback; i++) {
            sum += volumes[i];
            if(volumes[i] > data.maxVolume) data.maxVolume = volumes[i];
            if(volumes[i] < data.minVolume) data.minVolume = volumes[i];
        }
        
        data.averageVolume = sum / lookback;
        
        // Calculate standard deviation
        double variance = 0;
        for(int i = 0; i < lookback; i++) {
            double diff = volumes[i] - data.averageVolume;
            variance += diff * diff;
        }
        variance /= lookback;
        data.volumeStdDev = MathSqrt(variance);
        
        return data;
    }
    
    // Check for volume divergence (public method)
    bool HasDivergence(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int period = 5)
    {
        if(!m_initialized) return false;
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double prices[], volumes[];
        ArraySetAsSeries(prices, true);
        ArraySetAsSeries(volumes, true);
        
        int bars = period * 2;
        if(CopyClose(m_symbol, tf, 0, bars, prices) < bars)
            return false;
        
        for(int i = 0; i < bars; i++)
            volumes[i] = m_indicatorManager.GetVolume(tf, i);
        
        // Check both bullish and bearish divergences
        return CheckVolumeDivergence(prices, volumes, period);
    }
    
    // Check for volume climax (public method)
    bool IsClimaxVolume(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20)
    {
        if(!m_initialized) return false;
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double volumes[];
        ArraySetAsSeries(volumes, true);
        ArrayResize(volumes, lookback);
        
        // Get volumes via IndicatorManager
        for(int i = 0; i < lookback; i++)
            volumes[i] = m_indicatorManager.GetVolume(tf, i);
        
        return IsClimax(volumes, lookback);
    }
    
    // Get volume status string
    string GetStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        if(!m_initialized) return "NOT_INIT";
        
        if(tf == PERIOD_CURRENT) tf = m_defaultTF;
        
        double currentVol = m_indicatorManager.GetVolume(tf, 0);
        double avgVol = 0;
        
        for(int i = 1; i <= 20; i++)
            avgVol += m_indicatorManager.GetVolume(tf, i);
        avgVol /= 20.0;
        
        if(avgVol <= 0) return "ERROR";
        
        double ratio = currentVol / avgVol;
        return GetVolumeStatusText(ratio);
    }
    
private:
    // ==================== PRIVATE HELPER METHODS ====================
    
    // Simple debug function
    void DebugLogVolume(string context, string message) {
        if(VOLUME_DEBUG_ENABLED) {
            Logger::Log("VOLUME-" + context, message);
        }
    }
    
    // Get price and volume data
    bool GetPriceVolumeData(ENUM_TIMEFRAMES tf, int lookback, int fastPeriod,
                           double &prices[], double &volumes[])
    {
        int bars = MathMax(lookback, fastPeriod * 2);
        ArrayResize(prices, bars);
        ArrayResize(volumes, bars);
        ArraySetAsSeries(prices, true);
        ArraySetAsSeries(volumes, true);
        
        // Get price data
        if(CopyClose(m_symbol, tf, 0, bars, prices) < bars)
            return false;
        
        // Get volume data via IndicatorManager
        for(int i = 0; i < bars; i++)
            volumes[i] = m_indicatorManager.GetVolume(tf, i);
        
        return true;
    }
    
    // 1. VALIDATE MOMENTUM (-100 to +100)
    double ValidateMomentum(const double &price[], const double &volume[], int period)
    {
        if(ArraySize(price) <= period || ArraySize(volume) <= period)
            return 0;
        
        double priceChange = ((price[0] - price[period]) / price[period]) * 100;
        double volumeChange = ((double)volume[0] - (double)volume[period]) / (double)volume[period] * 100;
        
        // No significant price move
        if(MathAbs(priceChange) < 0.1) return 0;
        
        // Same direction = confirmation
        if((priceChange > 0 && volumeChange > 0) || (priceChange < 0 && volumeChange < 0))
            return MathMin(100, MathAbs(priceChange) * 2); // Amplify confirmation
        else
            return -MathMin(100, MathAbs(priceChange) * 2); // Negative for contradiction
    }
    
    // 2. GET CONVICTION SCORE (0-100)
    double GetConvictionScore(const double &volume[], int lookback)
    {
        if(ArraySize(volume) <= lookback) return 50;
        
        double currentVol = volume[0];
        double avgVol = 0;
        
        // Calculate average volume (excluding current)
        for(int i = 1; i < lookback; i++)
            avgVol += volume[i];
        avgVol /= (lookback - 1);
        
        if(avgVol <= 0) return 50;
        
        double ratio = currentVol / avgVol;
        
        // Convert ratio to 0-100 score
        if(ratio >= 2.0) return 90 + (ratio - 2.0) * 5;      // Very strong
        if(ratio >= 1.5) return 70 + (ratio - 1.5) * 40;     // Strong
        if(ratio >= 1.0) return 50 + (ratio - 1.0) * 40;     // Above average
        if(ratio >= 0.7) return 30 + (ratio - 0.7) * 66.67;  // Below average
        return 10 + ratio * 28.57;                           // Very weak
    }
    
    // 3. GET VOLUME RATIO
    double GetVolumeRatio(const double &volume[], int lookback)
    {
        if(ArraySize(volume) <= lookback) return 1.0;
        
        double currentVol = volume[0];
        double avgVol = 0;
        
        for(int i = 1; i < lookback; i++)
            avgVol += volume[i];
        avgVol /= (lookback - 1);
        
        return (avgVol > 0) ? currentVol / avgVol : 1.0;
    }
    
    // 4. GET PREDICTION
    string GetPrediction(const double &price[], const double &volume[], int period)
    {
        if(ArraySize(price) <= period || ArraySize(volume) <= period)
            return "NEUTRAL";
        
        bool priceUp = price[0] > price[period];
        bool volUp = volume[0] > volume[period];
        
        if(priceUp && volUp) return "BULLISH";
        if(!priceUp && !volUp) return "BEARISH";
        if(priceUp && !volUp) return "WEAK_BULL";
        if(!priceUp && volUp) return "WEAK_BEAR";
        return "NEUTRAL";
    }
    
    // Calculate bias scores
    void CalculateBiasScores(VolumeAnalysisResult &result)
    {
        // Base scores from prediction
        if(result.prediction == "BULLISH")
        {
            result.bias.bullScore = result.convictionScore * m_config.bullBiasWeight;
            result.bias.bearScore = 100 - result.convictionScore;
            result.bias.primaryBias = "BULLISH";
            result.bias.isBullish = true;
        }
        else if(result.prediction == "BEARISH")
        {
            result.bias.bullScore = 100 - result.convictionScore;
            result.bias.bearScore = result.convictionScore * m_config.bearBiasWeight;
            result.bias.primaryBias = "BEARISH";
            result.bias.isBearish = true;
        }
        else if(result.prediction == "WEAK_BULL")
        {
            result.bias.bullScore = result.convictionScore * 0.7; // Reduced for weak signal
            result.bias.bearScore = 50;
            result.bias.primaryBias = "BULLISH";
            result.bias.isBullish = true;
        }
        else if(result.prediction == "WEAK_BEAR")
        {
            result.bias.bullScore = 50;
            result.bias.bearScore = result.convictionScore * 0.7; // Reduced for weak signal
            result.bias.primaryBias = "BEARISH";
            result.bias.isBearish = true;
        }
        else // NEUTRAL
        {
            result.bias.bullScore = 50;
            result.bias.bearScore = 50;
            result.bias.primaryBias = "NEUTRAL";
        }
        
        // Adjust based on momentum score
        if(result.momentumScore > 0)
        {
            result.bias.bullScore += MathAbs(result.momentumScore) * 0.3;
            result.bias.bearScore -= MathAbs(result.momentumScore) * 0.3;
        }
        else if(result.momentumScore < 0)
        {
            result.bias.bullScore -= MathAbs(result.momentumScore) * 0.3;
            result.bias.bearScore += MathAbs(result.momentumScore) * 0.3;
        }
        
        // Apply volume spike boost
        if(result.volumeRatio >= 2.0)
        {
            result.bias.bullScore *= m_config.confidenceBoostOnSpike;
            result.bias.bearScore *= m_config.confidenceBoostOnSpike;
        }
        
        // Apply divergence penalty
        if(result.divergence)
        {
            result.bias.bullScore *= m_config.penaltyOnDivergence;
            result.bias.bearScore *= m_config.penaltyOnDivergence;
        }
        
        // Calculate overall confidence
        result.bias.overallConfidence = (result.bias.bullScore + result.bias.bearScore) / 2.0;
        
        // Ensure scores are within bounds
        result.bias.bullScore = MathMax(0, MathMin(100, result.bias.bullScore));
        result.bias.bearScore = MathMax(0, MathMin(100, result.bias.bearScore));
        result.bias.overallConfidence = MathMax(0, MathMin(100, result.bias.overallConfidence));
    }
    
    // Calculate volume analysis data
    void CalculateVolumeData(VolumeAnalysisResult &result)
    {
        // Weighted score (combining multiple factors)
        double score = 0;
        
        // Base score from conviction (40% weight)
        score += result.convictionScore * 0.4;
        
        // Momentum adjustment (30% weight)
        if(result.momentumScore > 0)
            score += MathAbs(result.momentumScore) * 0.3;
        else
            score -= MathAbs(result.momentumScore) * 0.3;
        
        // Volume ratio boost (20% weight)
        if(result.volumeRatio > 1.0)
            score += (result.volumeRatio - 1.0) * 20;
        else
            score -= (1.0 - result.volumeRatio) * 20;
        
        // Penalties (10% weight)
        if(result.divergence) score -= 15;
        if(result.climax) score -= 20;
        if(result.warning != "") score -= 10;
        
        // Direction score (-100 to +100)
        result.volume.directionScore = result.momentumScore;
        
        // Determine recommendation
        if(score >= 70 && result.bias.primaryBias == "BULLISH" && !result.divergence)
            result.volume.recommendation = "BUY";
        else if(score >= 70 && result.bias.primaryBias == "BEARISH" && !result.divergence)
            result.volume.recommendation = "SELL";
        else if(score >= 60 && result.bias.overallConfidence >= 60)
            result.volume.recommendation = "CONFIRM";
        else if(score <= 40 || result.divergence)
            result.volume.recommendation = "AVOID";
        else
            result.volume.recommendation = "HOLD";
        
        // Set strong signal flag
        result.volume.hasStrongSignal = (score >= 70 && !result.divergence);
        result.volume.hasWarning = (result.warning != "" || result.divergence || result.climax);
        
        // Set volume context
        if(result.volumeRatio >= m_config.climaxWarningThreshold)
            result.volume.volumeContext = "EXTREME_SPIKE";
        else if(result.volumeRatio >= 2.0)
            result.volume.volumeContext = "SPIKE";
        else if(result.climax)
            result.volume.volumeContext = "CLIMAX";
        else if(result.divergence)
            result.volume.volumeContext = "DIVERGENCE";
        else
            result.volume.volumeContext = "NORMAL";
        
        // Final weighted score
        result.volume.weightedScore = MathMax(0, MathMin(100, score));
        result.volume.reliabilityScore = result.convictionScore;
    }
    
    // Get simple direction string
    string GetSimpleDirection(const VolumeAnalysisResult &result)
    {
        if(result.bias.primaryBias == "BULLISH") return "BULLISH";
        if(result.bias.primaryBias == "BEARISH") return "BEARISH";
        return "NEUTRAL";
    }
    
    // Check specific divergence (private helper - renamed from HasDivergence)
    bool CheckDivergence(const double &price[], const double &volume[], int period)
    {
        if(ArraySize(price) <= period || ArraySize(volume) <= period)
            return false;
        
        // Bullish divergence: Price lower, volume higher
        bool bullDiv = (price[0] < price[period]) && (volume[0] > volume[period] * 1.2);
        
        // Bearish divergence: Price higher, volume lower
        bool bearDiv = (price[0] > price[period]) && (volume[0] < volume[period] * 0.8);
        
        return bullDiv || bearDiv;
    }
    
    // 5. CHECK DIVERGENCE PATTERN (private helper)
    bool CheckVolumeDivergence(const double &price[], const double &volume[], int period)
    {
        if(ArraySize(price) < period * 2 || ArraySize(volume) < period * 2)
            return false;
        
        // Bullish divergence: Price making lower lows, volume making higher lows
        bool bullishDiv = true;
        // Bearish divergence: Price making higher highs, volume making lower highs
        bool bearishDiv = true;
        
        for(int i = 0; i < period; i++)
        {
            int idx1 = i;
            int idx2 = i + period;
            
            if(idx2 >= ArraySize(price) || idx2 >= ArraySize(volume))
                break;
            
            // Check bullish divergence pattern
            if(!(price[idx1] < price[idx2] && volume[idx1] > volume[idx2]))
                bullishDiv = false;
            
            // Check bearish divergence pattern
            if(!(price[idx1] > price[idx2] && volume[idx1] < volume[idx2]))
                bearishDiv = false;
        }
        
        return bullishDiv || bearishDiv;
    }
    
    // 6. CHECK CLIMAX (private helper)
    bool IsClimax(const double &volume[], int lookback)
    {
        if(ArraySize(volume) <= lookback) return false;
        
        double currentVol = volume[0];
        double maxVol = 0;
        
        // Find maximum volume in lookback period (excluding current)
        for(int i = 1; i < lookback; i++)
        {
            if(volume[i] > maxVol)
                maxVol = volume[i];
        }
        
        // Current volume is significantly higher than previous max
        return (currentVol > maxVol * m_climaxThreshold);
    }
    
    // 7. GET VOLUME STATUS TEXT
    string GetVolumeStatusText(double ratio)
    {
        if(ratio >= 3.0) return "🔥 EXTREME SPIKE";
        if(ratio >= 2.0) return "🔥 VERY HIGH";
        if(ratio >= 1.5) return "↑ HIGH";
        if(ratio >= 1.2) return "↗ ABOVE AVG";
        if(ratio >= 0.8) return "→ NORMAL";
        if(ratio >= 0.5) return "↘ LOW";
        if(ratio >= 0.3) return "↓ VERY LOW";
        return "⚠️ DEAD";
    }
};