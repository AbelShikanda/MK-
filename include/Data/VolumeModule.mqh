//+------------------------------------------------------------------+
//|                           VolumeModule.mqh                       |
//|                Integrated with IndicatorManager                  |
//|                DECOUPLED FROM TrendPackage DEPENDENCY            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict
#property version "1.00"

#include "../Utils/Logger.mqh"
#include "IndicatorManager.mqh"

// Debug settings
bool VOLUME_DEBUG_ENABLED = false;

// Volume analysis result structure
struct VolumeAnalysisResult
{
    double momentumScore;   // -100 to +100 (positive = confirms, negative = contradicts)
    double convictionScore; // 0-100 (strength of conviction)
    string prediction;      // "BULLISH", "BEARISH", "NEUTRAL", "WEAK_BULL", "WEAK_BEAR"
    bool divergence;        // true if volume-price divergence detected
    bool climax;            // true if volume climax/exhaustion detected
    string volumeStatus;    // Text description of volume level
    double volumeRatio;     // Current volume / average volume
    string warning;         // Any warnings (divergence, climax, etc.)
    datetime timestamp;     // Analysis timestamp

    // ====== BIAS SCORES ======
    struct BiasScores
    {
        double bullScore;         // 0-100 for bullish bias strength
        double bearScore;         // 0-100 for bearish bias strength
        double overallConfidence; // 0-100 overall confidence score
        string primaryBias;       // "BULLISH", "BEARISH", "NEUTRAL"
        bool isBullish;           // Quick boolean for bullish
        bool isBearish;           // Quick boolean for bearish
    } bias;

    // ====== VOLUME ANALYSIS DATA ======
    struct VolumeData
    {
        double weightedScore;    // 0-100 weighted volume score
        double directionScore;   // -100 to +100 (negative bearish, positive bullish)
        string recommendation;   // "CONFIRM_BUY", "CONFIRM_SELL", "SUPPORT", "HOLD", "CAUTION", "AVOID"
        double reliabilityScore; // 0-100 how reliable this volume signal is
        bool hasStrongSignal;    // True if strong volume confirmation
        bool hasWarning;         // True if any warnings present
        string volumeContext;    // "SPIKE", "CLIMAX", "DIVERGENCE", "NORMAL"
    } volume;

    // Initialize constructor
    VolumeAnalysisResult()
    {
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
    IndicatorManager *m_indicatorManager;
    bool m_initialized;
    double m_volumeSpikeThreshold;
    double m_climaxThreshold;
    ENUM_TIMEFRAMES m_defaultTF;

    // Configuration parameters
    struct ModuleConfig
    {
        bool enableDetailedOutput;     // Enable detailed analysis output
        double bullBiasWeight;         // Weight for bullish bias (0-1)
        double bearBiasWeight;         // Weight for bearish bias (0-1)
        double confidenceBoostOnSpike; // Boost confidence on volume spikes
        double penaltyOnDivergence;    // Penalty on divergence signals
        double climaxWarningThreshold; // Threshold for climax warnings
    } m_config;

    // Simple debug logging using your Logger class
    void DebugLog(string context, string message)
    {
        if (VOLUME_DEBUG_ENABLED)
        {
            Logger::Log("VOL-" + context, message);
        }
    }

    // Log analysis summary
    void LogAnalysisSummary(const VolumeAnalysisResult &result, ENUM_TIMEFRAMES tf)
    {
        if (!VOLUME_DEBUG_ENABLED)
            return;

        string tfStr = EnumToString(tf);

        // Show ratio with 2 decimal places
        string summary = StringFormat(
            "%s: %s | Bull:%.0f Bear:%.0f | Score:%.0f Rec:%s | Ratio:%.2fx %s",
            tfStr,
            result.prediction,
            result.bias.bullScore,
            result.bias.bearScore,
            result.volume.weightedScore,
            result.volume.recommendation,
            result.volumeRatio, // Now shows 0.04 instead of 1.0
            (result.warning != "" ? "⚠️" : ""));

        DebugLog("Analysis", summary);
    }

public:
    // CONSTRUCTOR
    VolumeModule()
    {
        m_symbol = "";
        m_indicatorManager = NULL;
        m_initialized = false;
        m_volumeSpikeThreshold = 2.0; // 2x average = spike
        m_climaxThreshold = 1.5;      // 1.5x max = climax
        m_defaultTF = PERIOD_M15;

        // Initialize configuration
        m_config.enableDetailedOutput = true;
        m_config.bullBiasWeight = 0.6;         // Slightly favor bullish confirmation
        m_config.bearBiasWeight = 0.6;         // Same for bearish
        m_config.confidenceBoostOnSpike = 1.2; // 20% boost on spikes
        m_config.penaltyOnDivergence = 0.7;    // 30% penalty on divergence
        m_config.climaxWarningThreshold = 3.0; // Extreme spike threshold

        if (VOLUME_DEBUG_ENABLED)
            Logger::Log("VolumeModule", "Module created");
    }

    // DESTRUCTOR
    ~VolumeModule()
    {
        Deinitialize();
    }

    // INITIALIZE with IndicatorManager
    bool Initialize(IndicatorManager *indicatorMgr, string symbol = NULL)
    {
        if (m_initialized)
        {
            Logger::Log("VolumeModule", "Already initialized");
            return true;
        }

        if (indicatorMgr == NULL)
        {
            Logger::LogError("VolumeModule", "IndicatorManager is NULL");
            return false;
        }

        if (!indicatorMgr.IsInitialized())
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
        if (!m_initialized)
            return;

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

        if (!m_initialized)
        {
            result.warning = "Module not initialized";
            DebugLog("Error", "Module not initialized");
            return result;
        }

        // Use default if current
        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        // Get price and volume data
        double prices[], volumes[];
        if (!GetPriceVolumeData(tf, lookback, fastPeriod, prices, volumes))
        {
            result.warning = "Failed to get price/volume data";
            DebugLog("Error", "Failed to get price/volume data");
            return result;
        }

        // 1. MOMENTUM VALIDATION (-100 to +100)
        result.momentumScore = ValidateMomentum(prices, volumes, fastPeriod);

        // 2. CONVICTION SCORE (0-100)
        result.convictionScore = GetConvictionScore(volumes, lookback);

        // 3. VOLUME RATIO
        result.volumeRatio = GetVolumeRatio(volumes, lookback);

        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("RatioCheck",
                     StringFormat("After GetVolumeRatio: result.volumeRatio=%.2f",
                                  result.volumeRatio));
        }

        // 4. PREDICTION
        result.prediction = GetPrediction(prices, volumes, fastPeriod);

        // 5. DIVERGENCE DETECTION
        result.divergence = CheckDivergence(prices, volumes, fastPeriod);

        // 6. CLIMAX DETECTION
        result.climax = IsClimax(volumes, lookback);

        // 7. VOLUME STATUS
        result.volumeStatus = GetVolumeStatusText(result.volumeRatio);

        // 8. WARNINGS
        if (result.divergence)
            result.warning += "DIVERGENCE ";
        if (result.climax)
            result.warning += "CLIMAX ";
        if (result.volumeRatio > m_volumeSpikeThreshold)
            result.warning += "SPIKE ";
        if (result.momentumScore < -30)
            result.warning += "WEAK_CONFIRMATION ";

        // Clean up warnings
        StringTrimRight(result.warning);

        // Log warnings if any
        if (result.warning != "")
        {
            DebugLog("Warning", StringFormat("%s: %s", result.prediction, result.warning));
        }

        // ====== CALCULATE BIAS SCORES ======
        CalculateBiasScores(result);

        // ====== CALCULATE VOLUME ANALYSIS DATA ======
        CalculateVolumeData(result);

        // Log analysis summary
        LogAnalysisSummary(result, tf);

        return result;
    }

    // GET SIMPLIFIED ANALYSIS RESULTS
    struct SimpleVolumeResult
    {
        double score;       // 0-100 overall volume score
        string direction;   // "BULLISH", "BEARISH", "NEUTRAL"
        double confidence;  // 0-100 confidence level
        bool hasWarning;    // True if warnings present
        string warningType; // Type of warning if any
        double volumeRatio; // Current volume / average volume
    };

    SimpleVolumeResult GetSimpleAnalysis(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        SimpleVolumeResult simple;
        ZeroMemory(simple);
        simple.score = 50;
        simple.direction = "NEUTRAL";
        simple.confidence = 50;

        if (!m_initialized)
            return simple;

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
    struct ComponentData
    {
        string name;       // Component name
        string direction;  // Direction: "BULLISH", "BEARISH", "NEUTRAL"
        double strength;   // Strength score 0-100
        double confidence; // Confidence score 0-100
        bool isActive;     // Is component active
        string details;    // Detailed information
    };

    ComponentData GetComponentData(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        ComponentData component;
        component.name = "VOL";

        if (!m_initialized)
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

        if (analysis.warning != "")
            details += " " + analysis.warning;

        component.details = details;

        return component;
    }

    // ==================== QUICK CHECK METHODS ====================

    // SIMPLIFIED ANALYSIS (returns score 0-100)
    double GetVolumeScore(ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                          bool isBullishMove = true)
    {
        if (!m_initialized)
            return 50.0;

        VolumeAnalysisResult analysis = Analyze(tf);

        // Base score on conviction
        double score = analysis.convictionScore;

        // Adjust based on momentum validation
        if (isBullishMove)
        {
            if (analysis.momentumScore > 0)
                score += 15;
            else if (analysis.momentumScore < 0)
                score -= 15;
        }
        else
        {
            if (analysis.momentumScore > 0)
                score -= 15;
            else if (analysis.momentumScore < 0)
                score += 15;
        }

        // Penalize for warnings
        if (analysis.divergence)
            score -= 20;
        if (analysis.climax)
            score -= 25;

        return MathMax(0, MathMin(100, score));
    }

    // Check if volume confirms price move
    bool IsVolumeConfirming(ENUM_TIMEFRAMES tf, bool expectingBullish)
    {
        if (!m_initialized)
            return false;

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double priceChange = iClose(m_symbol, tf, 0) - iClose(m_symbol, tf, 1);
        double volCurrent = m_indicatorManager.GetVolume(tf, 0);
        double volPrev = m_indicatorManager.GetVolume(tf, 1);

        if (MathAbs(priceChange) < 0.00001)
            return true; // No significant price move

        if (expectingBullish)
            return (priceChange > 0 && volCurrent > volPrev);
        else
            return (priceChange < 0 && volCurrent > volPrev);
    }

    // Check for volume spike
    bool HasSpike(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, double threshold = 2.0)
    {
        if (!m_initialized)
            return false;

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double currentVol = m_indicatorManager.GetVolume(tf, 0);
        double avgVol = 0;

        for (int i = 1; i <= 20; i++)
            avgVol += m_indicatorManager.GetVolume(tf, i);
        avgVol /= 20.0;

        if (avgVol <= 0)
            return false;

        bool spike = (currentVol > avgVol * threshold);

        if (spike && VOLUME_DEBUG_ENABLED)
        {
            DebugLog("HasSpike",
                     StringFormat("Volume spike on %s: %.0f > %.0fx average",
                                  EnumToString(tf), currentVol, currentVol / avgVol));
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

    // Quick test - minimal logging
    void QuickTest()
    {
        if (!m_initialized)
        {
            Logger::LogError("VolumeModule", "Not initialized");
            return;
        }

        Logger::Log("VolumeModule", "=== Quick Test Start ===");

        // Test 1: Basic analysis
        VolumeAnalysisResult result = Analyze(m_defaultTF);

        // Test 2: Raw data check
        RawVolumeData raw = GetRawVolumeData(m_defaultTF, 10);
        Logger::Log("VolumeModule",
                    StringFormat("Raw: Cur=%.0f Avg=%.0f (%.1fx)",
                                 raw.currentVolume, raw.averageVolume,
                                 raw.currentVolume / MathMax(raw.averageVolume, 1)));

        // Test 3: Key metrics
        Logger::Log("VolumeModule",
                    StringFormat("Result: %s Score=%.0f Bias=%s Conf=%.0f%%",
                                 result.prediction,
                                 result.volume.weightedScore,
                                 result.bias.primaryBias,
                                 result.bias.overallConfidence));

        // Test 4: Component data
        ComponentData comp = GetComponentData(m_defaultTF);
        Logger::Log("VolumeModule",
                    StringFormat("Component: %s Str=%.0f Conf=%.0f",
                                 comp.direction, comp.strength, comp.confidence));

        Logger::Log("VolumeModule", "=== Quick Test End ===");
    }

    // Display volume analysis on chart
    void DisplayOnChart(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int corner = 2,
                        int x = 10, int y = 20)
    {
        if (!m_initialized)
            return;

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
            analysis.volume.recommendation);

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
    struct RawVolumeData
    {
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

        if (!m_initialized || m_indicatorManager == NULL)
            return data;

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double volumes[];
        ArrayResize(volumes, lookback);

        // Collect volume data
        for (int i = 0; i < lookback; i++)
        {
            volumes[i] = m_indicatorManager.GetVolume(tf, i);
        }

        // Calculate statistics
        data.currentVolume = volumes[0];
        data.maxVolume = volumes[0];
        data.minVolume = volumes[0];
        double sum = 0;

        for (int i = 0; i < lookback; i++)
        {
            sum += volumes[i];
            if (volumes[i] > data.maxVolume)
                data.maxVolume = volumes[i];
            if (volumes[i] < data.minVolume)
                data.minVolume = volumes[i];
        }

        data.averageVolume = sum / lookback;

        // Calculate standard deviation
        double variance = 0;
        for (int i = 0; i < lookback; i++)
        {
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
        if (!m_initialized)
            return false;

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double prices[], volumes[];
        ArraySetAsSeries(prices, true);
        ArraySetAsSeries(volumes, true);

        int bars = period * 2;
        if (CopyClose(m_symbol, tf, 0, bars, prices) < bars)
            return false;

        for (int i = 0; i < bars; i++)
            volumes[i] = m_indicatorManager.GetVolume(tf, i);

        // Check both bullish and bearish divergences
        return CheckVolumeDivergence(prices, volumes, period);
    }

    // Check for volume climax (public method)
    bool IsClimaxVolume(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20)
    {
        if (!m_initialized)
            return false;

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double volumes[];
        ArraySetAsSeries(volumes, true);
        ArrayResize(volumes, lookback);

        // Get volumes via IndicatorManager
        for (int i = 0; i < lookback; i++)
            volumes[i] = m_indicatorManager.GetVolume(tf, i);

        return IsClimax(volumes, lookback);
    }

    // Get volume status string
    string GetStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        if (!m_initialized)
            return "NOT_INIT";

        if (tf == PERIOD_CURRENT)
            tf = m_defaultTF;

        double currentVol = m_indicatorManager.GetVolume(tf, 0);
        double avgVol = 0;

        for (int i = 1; i <= 20; i++)
            avgVol += m_indicatorManager.GetVolume(tf, i);
        avgVol /= 20.0;

        if (avgVol <= 0)
            return "ERROR";

        double ratio = currentVol / avgVol;
        return GetVolumeStatusText(ratio);
    }

private:
    // ==================== PRIVATE HELPER METHODS ====================

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
        if (CopyClose(m_symbol, tf, 0, bars, prices) < bars)
        {
            DebugLog("DataError", "Failed to copy price data");
            return false;
        }

        // DEBUG: Log before IndicatorManager calls
        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("DataStart",
                     StringFormat("Getting %d bars for %s | Time[0]: %s",
                                  bars, EnumToString(tf), TimeToString(iTime(m_symbol, tf, 0))));
        }

        // Get volume data via IndicatorManager
        for (int i = 0; i < bars; i++)
        {
            double volume = m_indicatorManager.GetVolume(tf, i);
            volumes[i] = volume;

            // DEBUG: Log each call for first 3 bars
            if (VOLUME_DEBUG_ENABLED && i < 3)
            {
                datetime barTime = iTime(m_symbol, tf, i);
                DebugLog("IndicatorCall",
                         StringFormat("GetVolume(tf=%s, shift=%d) = %.0f | Time: %s",
                                      EnumToString(tf), i, volume, TimeToString(barTime)));
            }
        }

        // DEBUG: Comprehensive data check
        if (VOLUME_DEBUG_ENABLED)
        {
            // Log first 5 volumes with their bar times
            string volumeInfo = "Volumes with times: ";
            for (int i = 0; i < MathMin(5, bars); i++)
            {
                datetime barTime = iTime(m_symbol, tf, i);
                volumeInfo += StringFormat("[%d]%.0f@%s ",
                                           i, volumes[i], TimeToString(barTime, TIME_SECONDS));
            }
            DebugLog("VolumeData", volumeInfo);

            // Log first 5 prices for correlation
            string priceInfo = "Prices: ";
            for (int i = 0; i < MathMin(5, bars); i++)
            {
                priceInfo += StringFormat("[%d]%.5f ", i, prices[i]);
            }
            DebugLog("PriceData", priceInfo);

            // Check for stale data (identical consecutive volumes)
            int identicalCount = 0;
            for (int i = 1; i < MathMin(10, bars); i++)
            {
                if (MathAbs(volumes[i] - volumes[i - 1]) < 0.1)
                    identicalCount++;
            }

            if (identicalCount >= 3)
            {
                DebugLog("DataIssue",
                         StringFormat("WARNING: %d consecutive identical volumes!", identicalCount));

                // Log the exact values that are identical
                for (int i = 0; i < MathMin(identicalCount + 1, 6); i++)
                {
                    if (i < bars)
                    {
                        DebugLog("IdenticalCheck",
                                 StringFormat("Volume[%d] = %.0f", i, volumes[i]));
                    }
                }
            }

            // Calculate and display ratio info
            if (bars >= lookback)
            {
                double currentVol = volumes[0];
                double avgVol = 0;
                for (int i = 1; i < lookback; i++)
                    avgVol += volumes[i];
                avgVol /= (lookback - 1);

                DebugLog("RatioCalc",
                         StringFormat("Current=%.0f | Avg(%d)=%.0f | Ratio=%.2f",
                                      currentVol, lookback - 1, avgVol, (avgVol > 0 ? currentVol / avgVol : 0)));
            }

            // Verify data alignment (prices and volumes same bars)
            if (bars >= 2)
            {
                datetime priceTime1 = iTime(m_symbol, tf, 0);
                datetime priceTime2 = iTime(m_symbol, tf, 1);
                datetime volumeBarTime1 = iTime(m_symbol, tf, 0); // Should be same
                datetime volumeBarTime2 = iTime(m_symbol, tf, 1); // Should be same

                if (priceTime1 != volumeBarTime1 || priceTime2 != volumeBarTime2)
                {
                    DebugLog("DataError", "PRICE/VOLUME TIME MISMATCH!");
                    DebugLog("DataError",
                             StringFormat("PriceTimes: %s, %s | Expected same for volumes",
                                          TimeToString(priceTime1), TimeToString(priceTime2)));
                }
            }
        }

        return true;
    }

    // 1. VALIDATE MOMENTUM (-100 to +100)
    double ValidateMomentum(const double &price[], const double &volume[], int period)
    {
        if (ArraySize(price) <= period || ArraySize(volume) <= period)
            return 0;

        double priceChange = ((price[0] - price[period]) / price[period]) * 100;

        // FIXED: Add zero division protection for volume calculation
        double volumeChange = 0;
        if (volume[period] > 0)
        {
            volumeChange = ((double)volume[0] - (double)volume[period]) / (double)volume[period] * 100;
        }
        else if (volume[0] > 0)
        {
            // If previous volume was 0 but current isn't, assume 100% increase
            volumeChange = 100.0;
        }

        // No significant price move
        if (MathAbs(priceChange) < 0.1)
            return 0;

        // Same direction = confirmation
        if ((priceChange > 0 && volumeChange > 0) || (priceChange < 0 && volumeChange < 0))
            return MathMin(100, MathAbs(priceChange) * 2); // Amplify confirmation
        else
            return -MathMin(100, MathAbs(priceChange) * 2); // Negative for contradiction
    }

    // 2. GET CONVICTION SCORE (0-100)
    double GetConvictionScore(const double &volume[], int lookback)
    {
        // FIX: Changed from <= to <
        if (ArraySize(volume) < lookback)
        {
            DebugLog("ConvictionError",
                     StringFormat("Array size too small! ArraySize=%d, lookback=%d",
                                  ArraySize(volume), lookback));
            return 50;
        }

        double currentVol = volume[0];
        double avgVol = 0;

        // Calculate average volume (excluding current)
        for (int i = 1; i < lookback; i++)
            avgVol += volume[i];
        avgVol /= (lookback - 1);

        if (avgVol <= 0)
            return 50;

        double ratio = currentVol / avgVol;

        // Convert ratio to 0-100 score
        double score = GetScoreFromRatio(ratio);

        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("GetConvictionScore",
                     StringFormat("Ratio=%.2f | Score=%.1f", ratio, score));
        }

        return score;
    }

    // Helper function
    double GetScoreFromRatio(double ratio)
    {
        // More reasonable scoring curve
        if (ratio >= 2.5)
            return MathMin(100, 95 + (ratio - 2.5) * 3);
        if (ratio >= 2.0)
            return MathMin(94, 85 + (ratio - 2.0) * 10);
        if (ratio >= 1.5)
            return MathMin(84, 70 + (ratio - 1.5) * 30);
        if (ratio >= 1.2)
            return MathMin(69, 55 + (ratio - 1.2) * 50);
        if (ratio >= 1.0)
            return MathMin(54, 45 + (ratio - 1.0) * 45);
        if (ratio >= 0.8)
            return MathMin(44, 35 + (ratio - 0.8) * 45);
        if (ratio >= 0.6)
            return MathMin(34, 25 + (ratio - 0.6) * 50);
        if (ratio >= 0.4)
            return MathMin(24, 15 + (ratio - 0.4) * 45);
        if (ratio >= 0.2)
            return MathMin(14, 10 + (ratio - 0.2) * 20); // Less harsh drop
        if (ratio >= 0.1)
            return MathMin(9, 5 + (ratio - 0.1) * 40);
        return MathMin(4, ratio * 40); // Don't drop to 0 immediately
    }

    // 3. GET VOLUME RATIO
    double GetVolumeRatio(const double &volume[], int lookback)
    {
        // FIX: Changed from <= to <
        if (ArraySize(volume) < lookback)
        {
            DebugLog("RatioError",
                     StringFormat("Array size too small! ArraySize=%d, lookback=%d",
                                  ArraySize(volume), lookback));
            return 1.0;
        }

        double currentVol = volume[0];
        double avgVol = 0;

        // FIX: Use lookback-1 for the loop to exclude current bar
        for (int i = 1; i < lookback; i++)
            avgVol += volume[i];

        avgVol /= (lookback - 1);

        double ratio = (avgVol > 0) ? currentVol / avgVol : 1.0;

        // DEBUG
        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("GetVolumeRatio-FIXED",
                     StringFormat("ArraySize=%d, lookback=%d | Current=%.0f | Avg(%d)=%.0f | Ratio=%.2f",
                                  ArraySize(volume), lookback,
                                  currentVol, lookback - 1, avgVol, ratio));
        }

        return ratio;
    }

    // 4. GET PREDICTION
    string GetPrediction(const double &price[], const double &volume[], int period)
    {
        if (ArraySize(price) <= period || ArraySize(volume) <= period)
            return "NEUTRAL";

        bool priceUp = price[0] > price[period];
        bool volUp = volume[0] > volume[period];

        if (priceUp && volUp)
            return "BULLISH";
        if (!priceUp && !volUp)
            return "BEARISH";
        if (priceUp && !volUp)
            return "WEAK_BULL";
        if (!priceUp && volUp)
            return "WEAK_BEAR";
        return "NEUTRAL";
    }

    // Calculate bias scores
    void CalculateBiasScores(VolumeAnalysisResult &result)
    {
        // Reset scores
        result.bias.bullScore = 50;
        result.bias.bearScore = 50;
        result.bias.primaryBias = "NEUTRAL";
        result.bias.isBullish = false;
        result.bias.isBearish = false;

        // Start with conviction score as base
        double baseScore = result.convictionScore;

        // Apply prediction bias - FIXED VERSION
        if (result.prediction == "BULLISH")
        {
            result.bias.bullScore = MathMin(100, baseScore + 30);       // Higher boost
            result.bias.bearScore = MathMax(0, 30 - (baseScore * 0.3)); // Much lower
            result.bias.primaryBias = "BULLISH";
            result.bias.isBullish = true;
        }
        else if (result.prediction == "BEARISH")
        {
            result.bias.bullScore = MathMax(0, 30 - (baseScore * 0.3)); // Much lower
            result.bias.bearScore = MathMin(100, baseScore + 30);       // Higher boost
            result.bias.primaryBias = "BEARISH";
            result.bias.isBearish = true;
        }
        else if (result.prediction == "WEAK_BULL")
        {
            result.bias.bullScore = MathMin(100, baseScore + 15);       // Moderate boost
            result.bias.bearScore = MathMax(0, 50 - (baseScore * 0.2)); // Moderate
            result.bias.primaryBias = "BULLISH";
            result.bias.isBullish = true;
        }
        else if (result.prediction == "WEAK_BEAR")
        {
            result.bias.bullScore = MathMax(0, 50 - (baseScore * 0.2)); // Moderate
            result.bias.bearScore = MathMin(100, baseScore + 15);       // Moderate boost
            result.bias.primaryBias = "BEARISH";
            result.bias.isBearish = true;
        }

        // Momentum adjustment (max ±20 points)
        double momentumAdjust = result.momentumScore * 0.2;
        result.bias.bullScore += momentumAdjust;
        result.bias.bearScore -= momentumAdjust;

        // Volume spike boost
        if (result.volumeRatio >= 2.0)
        {
            double boost = (result.volumeRatio - 1.0) * 15;
            if (result.bias.isBullish)
                result.bias.bullScore = MathMin(100, result.bias.bullScore + boost);
            else if (result.bias.isBearish)
                result.bias.bearScore = MathMin(100, result.bias.bearScore + boost);
        }

        // Divergence penalty (reduce confidence, not bias)
        if (result.divergence)
        {
            // Reduce both scores but keep the relationship
            result.bias.bullScore *= 0.85;
            result.bias.bearScore *= 0.85;
        }

        // Ensure bounds
        result.bias.bullScore = MathMax(0, MathMin(100, result.bias.bullScore));
        result.bias.bearScore = MathMax(0, MathMin(100, result.bias.bearScore));

        // Overall confidence
        result.bias.overallConfidence = MathMax(0, MathMin(100,
                                                           (result.convictionScore * 0.7) + (MathMin(100, result.volumeRatio * 33) * 0.3)));
    }

    // Calculate volume analysis data
    void CalculateVolumeData(VolumeAnalysisResult &result)
    {
        // Start with higher base (70% conviction, 30% ratio)
        double score = (result.convictionScore * 0.7) +
                       (MathMin(100, result.volumeRatio * 33) * 0.3);

        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("ScoreCalc",
                     StringFormat("Base: Conv=%.1f*0.7=%.1f + Ratio=%.2f*33=%.1f*0.3=%.1f = %.1f",
                                  result.convictionScore, result.convictionScore * 0.7,
                                  result.volumeRatio, MathMin(100, result.volumeRatio * 33),
                                  MathMin(100, result.volumeRatio * 33) * 0.3,
                                  score));
        }

        // Add momentum contribution (±25 max)
        if (MathAbs(result.momentumScore) > 5)
        {
            if (result.momentumScore > 0)
                score += MathMin(25, result.momentumScore * 0.4);
            else
                score -= MathMin(15, MathAbs(result.momentumScore) * 0.3);
        }

        // Volume ratio bonus/penalty (more balanced)
        if (result.volumeRatio > 1.2)
            score += MathMin(20, (result.volumeRatio - 1.0) * 25);
        else if (result.volumeRatio < 0.8)
            score -= MathMin(15, (1.0 - result.volumeRatio) * 30);

        // Smaller penalties
        if (result.divergence)
            score -= 8;
        if (result.climax)
            score -= 10;
        if (result.warning != "")
            score -= 3;

        // FIX: Remove the 35 minimum or make it much lower
        // score = MathMax(35, MathMin(100, score));  // OLD - REMOVE THIS

        // NEW: Allow scores as low as 10 for very poor volume conditions
        score = MathMax(10, MathMin(100, score));

        // Set final scores
        result.volume.weightedScore = score;
        result.volume.directionScore = result.momentumScore;
        result.volume.reliabilityScore = result.convictionScore;

        // Determine recommendation
        // FIX: Adjust thresholds to match new score range
        if (score >= 75 && result.bias.overallConfidence >= 65)
        {
            if (result.bias.primaryBias == "BULLISH")
                result.volume.recommendation = "CONFIRM_BUY";
            else if (result.bias.primaryBias == "BEARISH")
                result.volume.recommendation = "CONFIRM_SELL";
            else
                result.volume.recommendation = "CONFIRM";
        }
        else if (score >= 60)
        {
            result.volume.recommendation = "SUPPORT";
        }
        else if (score >= 45)
        {
            result.volume.recommendation = "HOLD";
        }
        else if (score >= 25) // Lowered from 35 to 25
        {
            result.volume.recommendation = "CAUTION";
        }
        else if (score >= 15) // New threshold for very weak
        {
            result.volume.recommendation = "WEAK";
        }
        else
        {
            result.volume.recommendation = "AVOID";
        }

        if (VOLUME_DEBUG_ENABLED)
        {
            DebugLog("ScoreFinal",
                     StringFormat("Final score: %.1f | Recommendation: %s",
                                  score, result.volume.recommendation));
        }

        // Set flags
        result.volume.hasStrongSignal = (score >= 70 && result.bias.overallConfidence >= 60);
        result.volume.hasWarning = (result.warning != "" || result.divergence || result.climax);

        // Set context
        if (result.volumeRatio >= 3.0)
            result.volume.volumeContext = "EXTREME_SPIKE";
        else if (result.volumeRatio >= 2.0)
            result.volume.volumeContext = "SPIKE";
        else if (result.climax)
            result.volume.volumeContext = "CLIMAX";
        else if (result.divergence)
            result.volume.volumeContext = "DIVERGENCE";
        else if (result.volumeRatio >= 1.3)
            result.volume.volumeContext = "ABOVE_AVERAGE";
        else if (result.volumeRatio <= 0.7)
            result.volume.volumeContext = "BELOW_AVERAGE";
        else
            result.volume.volumeContext = "NORMAL";
    }

    // Get simple direction string
    string GetSimpleDirection(const VolumeAnalysisResult &result)
    {
        if (result.bias.primaryBias == "BULLISH")
            return "BULLISH";
        if (result.bias.primaryBias == "BEARISH")
            return "BEARISH";
        return "NEUTRAL";
    }

    // Check specific divergence (private helper - renamed from HasDivergence)
    bool CheckDivergence(const double &price[], const double &volume[], int period)
    {
        if (ArraySize(price) <= period || ArraySize(volume) <= period)
            return false;

        // Require minimum price movement (0.5%)
        double priceChange = MathAbs((price[0] - price[period]) / price[period]) * 100;
        if (priceChange < 0.5)
            return false;

        // Bullish divergence: Price lower, volume significantly higher
        bool bullDiv = (price[0] < price[period]) && (volume[0] > volume[period] * 1.3); // 1.3x instead of 1.2x

        // Bearish divergence: Price higher, volume significantly lower
        bool bearDiv = (price[0] > price[period]) && (volume[0] < volume[period] * 0.7); // 0.7x instead of 0.8x

        return bullDiv || bearDiv;
    }

    // 5. CHECK DIVERGENCE PATTERN (private helper)
    bool CheckVolumeDivergence(const double &price[], const double &volume[], int period)
    {
        if (ArraySize(price) < period * 2 || ArraySize(volume) < period * 2)
            return false;

        // Bullish divergence: Price making lower lows, volume making higher lows
        bool bullishDiv = true;
        // Bearish divergence: Price making higher highs, volume making lower highs
        bool bearishDiv = true;

        for (int i = 0; i < period; i++)
        {
            int idx1 = i;
            int idx2 = i + period;

            if (idx2 >= ArraySize(price) || idx2 >= ArraySize(volume))
                break;

            // Check bullish divergence pattern
            if (!(price[idx1] < price[idx2] && volume[idx1] > volume[idx2]))
                bullishDiv = false;

            // Check bearish divergence pattern
            if (!(price[idx1] > price[idx2] && volume[idx1] < volume[idx2]))
                bearishDiv = false;
        }

        return bullishDiv || bearishDiv;
    }

    // 6. CHECK CLIMAX (private helper)
    bool IsClimax(const double &volume[], int lookback)
    {
        if (ArraySize(volume) <= lookback)
            return false;

        double currentVol = volume[0];
        double maxVol = 0;

        // Find maximum volume in lookback period (excluding current)
        for (int i = 1; i < lookback; i++)
        {
            if (volume[i] > maxVol)
                maxVol = volume[i];
        }

        // Current volume is significantly higher than previous max
        return (currentVol > maxVol * m_climaxThreshold);
    }

    // 7. GET VOLUME STATUS TEXT
    string GetVolumeStatusText(double ratio)
    {
        if (ratio >= 3.0)
            return "🔥 EXTREME SPIKE";
        if (ratio >= 2.0)
            return "🔥 VERY HIGH";
        if (ratio >= 1.5)
            return "↑ HIGH";
        if (ratio >= 1.2)
            return "↗ ABOVE AVG";
        if (ratio >= 0.8)
            return "→ NORMAL";
        if (ratio >= 0.5)
            return "↘ LOW";
        if (ratio >= 0.3)
            return "↓ VERY LOW";
        return "⚠️ DEAD";
    }
};