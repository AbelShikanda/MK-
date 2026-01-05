//+------------------------------------------------------------------+
//|                              MACDModule.mqh                     |
//|                Clean MACD Analysis with Bias and Confidence      |
//|                [INTEGRATED WITH UTILS, LOGGER, INDICATOR & NO TRADEPACKAGE]|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"
#include "../Data/IndicatorManager.mqh"
#include "../Utils/TimeUtils.mqh"

// ==================== DEBUG SETTINGS ====================
bool MACD_DEBUG_ENABLED = false;

// Debug function using integrated Logger
void DebugLogMACD(string context, string message) {
   if(MACD_DEBUG_ENABLED) {
      Logger::Log(context, message);
   }
}

// ==================== ENUMERATIONS ====================
enum ENUM_MACD_BIAS
{
    MACD_BIAS_BULLISH,
    MACD_BIAS_BEARISH,
    MACD_BIAS_NEUTRAL,
    MACD_BIAS_WEAK_BULLISH,
    MACD_BIAS_WEAK_BEARISH
};

// ==================== STRUCTURES ====================

// Define raw data structures FIRST
struct MACDRawData {
    double macdValue;
    double signalValue;
    double histogramValue;
    double histogramSlope;
    bool isAboveZero;
    bool isCrossover;
    bool isDivergence;
    bool isStrongSignal;
    datetime timestamp;
    string symbol;
};

struct MACDSignalData {
    string signal;
    string bias;
    double score;
    double confidence;
    string signalType;
    datetime timestamp;
    bool isActionable;
};

struct MACDSignal
{
    ENUM_MACD_BIAS bias;                // Primary bias
    string biasString;                  // "BULLISH", "BEARISH", "NEUTRAL", etc.
    double score;                       // 0-100 overall score
    double confidence;                  // 0-100 confidence in bias
    ENUM_MACD_SIGNAL_TYPE signalType;   // Type of signal
    double macdValue;                   // Current MACD value
    double signalValue;                 // Current signal value
    double histogramValue;              // Current histogram value
    double histogramSlope;              // Histogram slope (trend)
    bool isAboveZero;                   // Is MACD above zero line?
    bool isCrossover;                   // Is there a recent crossover?
    bool isDivergence;                  // Is there price/MACD divergence?
    bool isStrongSignal;                // Is this a strong signal?
    datetime timestamp;                 // When signal was generated
    string symbol;                      // Symbol for display purposes
    
    // Constructor
    MACDSignal() {
        bias = MACD_BIAS_NEUTRAL;
        biasString = "NEUTRAL";
        score = 0;
        confidence = 0;
        signalType = MACD_SIGNAL_NONE;
        macdValue = 0;
        signalValue = 0;
        histogramValue = 0;
        histogramSlope = 0;
        isAboveZero = false;
        isCrossover = false;
        isDivergence = false;
        isStrongSignal = false;
        timestamp = TimeCurrent();
        symbol = "";
    }
    
    // Get simple signal
    string GetSimpleSignal() const {
        if(bias == MACD_BIAS_BULLISH || bias == MACD_BIAS_WEAK_BULLISH) return "BUY";
        if(bias == MACD_BIAS_BEARISH || bias == MACD_BIAS_WEAK_BEARISH) return "SELL";
        return "HOLD";
    }
    
    // Get confidence as percentage string
    string GetConfidenceString() const {
        return StringFormat("%.0f%%", confidence);
    }
    
    // Check if signal is actionable
    bool IsActionable() const {
        return ((bias == MACD_BIAS_BULLISH || bias == MACD_BIAS_BEARISH) && 
                confidence > 65 && 
                score > 55);
    }
    
    // Get formatted display
    string GetDisplayString() const {
        string biasIcon = "";
        if(bias == MACD_BIAS_BULLISH) biasIcon = "▲";
        else if(bias == MACD_BIAS_BEARISH) biasIcon = "▼";
        else if(bias == MACD_BIAS_WEAK_BULLISH) biasIcon = "↗";
        else if(bias == MACD_BIAS_WEAK_BEARISH) biasIcon = "↘";
        
        string signalStr = "";
        switch(signalType) {
            case MACD_SIGNAL_CROSSOVER: signalStr = "CROSS"; break;
            case MACD_SIGNAL_DIVERGENCE: signalStr = "DIV"; break;
            case MACD_SIGNAL_TREND: signalStr = "TREND"; break;
            case MACD_SIGNAL_ZERO_LINE: signalStr = "ZERO"; break;
        }
        
        return StringFormat("%s %s | Score: %.0f | Conf: %.0f%% | %s", 
            biasIcon, biasString, score, confidence, signalStr);
    }
    
    // Get detailed analysis
    string GetDetailedAnalysis() const {
        return StringFormat(
            "MACD Analysis:\n"
            "Bias: %s\n"
            "Confidence: %.0f%%\n"
            "Score: %.0f\n"
            "Signal Type: %s\n"
            "MACD: %.4f | Signal: %.4f | Hist: %.4f\n"
            "Above Zero: %s | Crossover: %s\n"
            "Divergence: %s | Strong: %s\n"
            "Histogram Slope: %.4f",
            biasString,
            confidence,
            score,
            SignalTypeToString(signalType),
            macdValue, signalValue, histogramValue,
            isAboveZero ? "YES" : "NO",
            isCrossover ? "YES" : "NO",
            isDivergence ? "YES" : "NO",
            isStrongSignal ? "YES" : "NO",
            histogramSlope
        );
    }
    
    // Display score on chart using integrated Logger
    void DisplayScoreOnChart() const {
        if(IsActionable()) {
            string signalStr = GetSimpleSignal();  // Store in variable first
            Logger::ShowScoreFast(symbol, score, signalStr, confidence/100.0);
        }
    }
    
    // Display decision on chart using integrated Logger
    void DisplayDecisionOnChart(string reason = "") const {
        int decision = 0;
        if(bias == MACD_BIAS_BULLISH || bias == MACD_BIAS_WEAK_BULLISH) decision = 1;
        else if(bias == MACD_BIAS_BEARISH || bias == MACD_BIAS_WEAK_BEARISH) decision = -1;
        
        Logger::ShowDecisionFast(symbol, decision, confidence/100.0, reason);
    }
    
    // Get raw data structure for external consumption
    MACDRawData GetRawData() const {
        MACDRawData data;
        data.macdValue = macdValue;
        data.signalValue = signalValue;
        data.histogramValue = histogramValue;
        data.histogramSlope = histogramSlope;
        data.isAboveZero = isAboveZero;
        data.isCrossover = isCrossover;
        data.isDivergence = isDivergence;
        data.isStrongSignal = isStrongSignal;
        data.timestamp = timestamp;
        data.symbol = symbol;
        return data;
    }
    
    // Get signal data for external modules
    MACDSignalData GetSignalData() const {
        MACDSignalData data;
        data.signal = GetSimpleSignal();
        data.bias = biasString;
        data.score = score;
        data.confidence = confidence;
        data.timestamp = timestamp;
        data.isActionable = IsActionable();
        
        switch(signalType) {
            case MACD_SIGNAL_CROSSOVER: data.signalType = "CROSSOVER"; break;
            case MACD_SIGNAL_DIVERGENCE: data.signalType = "DIVERGENCE"; break;
            case MACD_SIGNAL_ZERO_LINE: data.signalType = "ZERO_LINE"; break;
            case MACD_SIGNAL_TREND: data.signalType = "TREND"; break;
            default: data.signalType = "NONE"; break;
        }
        
        return data;
    }
    
private:
    string SignalTypeToString(ENUM_MACD_SIGNAL_TYPE type) const {
        switch(type) {
            case MACD_SIGNAL_CROSSOVER: return "Crossover";
            case MACD_SIGNAL_DIVERGENCE: return "Divergence";
            case MACD_SIGNAL_TREND: return "Trend";
            case MACD_SIGNAL_ZERO_LINE: return "Zero Line";
            default: return "None";
        }
    }
};

// Additional data structures for component data (keep these at the end)
struct RSIData {
    double value;
    bool isOverbought;
    bool isOversold;
    string description;
    double score;
    double confidence;
};

struct ADXData {
    double value;
    bool isStrongTrend;
    bool isModerateTrend;
    bool isWeakTrend;
    string description;
    double score;
    double confidence;
};

struct MTFConfirmationData {
    int bullish_tf_count;
    int bearish_tf_count;
    int total_tf_count;
    string description;
    double score;
    double confidence;
};

struct MACDConfirmationData {
    MACDRawData macdData;
    MACDSignalData signalData;
    RSIData rsiData;
    ADXData adxData;
    MTFConfirmationData mtfData;
};

// ==================== MACD MODULE CLASS ====================
class MACDModule
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_initialized;
    
    // Signal generation
    MACDSignal m_lastSignal;
    datetime m_lastSignalTime;
    
    // Indicator Manager (integrated with your IndicatorManager)
    IndicatorManager* m_indicatorManager;
    
public:
    MACDModule()
    {
        m_symbol = "";
        m_timeframe = PERIOD_H1;
        m_initialized = false;
        m_lastSignal = MACDSignal();
        m_lastSignalTime = 0;
        m_indicatorManager = NULL;
    }
    
    ~MACDModule()
    {
        Deinitialize();
    }
    
public:
    // Initialize with specific timeframe
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_H1) 
    {
        if(m_initialized) return true;
        
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        // Initialize Logger if needed
        if(!Logger::IsFileLoggingAvailable()) {
            Logger::Initialize("MACD_Module.log", true, true);
        }
        
        // Initialize IndicatorManager using your provided class
        m_indicatorManager = new IndicatorManager(m_symbol);
        if(m_indicatorManager == NULL || !m_indicatorManager.Initialize()) {
            Logger::LogError("MACDModule", "Failed to initialize IndicatorManager");
            return false;
        }
        
        m_initialized = true;
        Logger::Log("MACDModule", StringFormat("Initialized for %s on timeframe %d", 
            m_symbol, m_timeframe));
        return true;
    }
    
    void Deinitialize()
    {
        if(!m_initialized) return;
        
        // Deinitialize IndicatorManager
        if(m_indicatorManager != NULL) {
            m_indicatorManager.Deinitialize();
            delete m_indicatorManager;
            m_indicatorManager = NULL;
        }
        
        m_initialized = false;
        Logger::Log("MACDModule", "Deinitialized");
    }
    
    // ==================== PUBLIC INTERFACE ====================
    
    // Get complete MACD signal (MAIN METHOD)
    MACDSignal GetMACDSignal() 
    {
        if(!m_initialized) {
            Logger::LogError("GetMACDSignal", "Module not initialized");
            return m_lastSignal;
        }
        
        // Check if market is open using integrated TimeUtils
        if(!TimeUtils::IsMarketOpen(m_symbol)) {
            Logger::Log("GetMACDSignal", "Market is closed - using cached signal");
            return m_lastSignal;
        }
        
        // Use cached signal if recent (less than 30 seconds old)
        if(TimeCurrent() - m_lastSignalTime < 30 && m_lastSignal.timestamp > 0) {
            return m_lastSignal;
        }
        
        Logger::Log("GetMACDSignal", "Generating new MACD signal");
        
        // Generate new signal
        MACDSignal signal;
        signal.timestamp = TimeCurrent();
        signal.symbol = m_symbol;
        
        // Get MACD values using integrated IndicatorManager
        double macdMain, macdSignal;
        if(!GetMACDValues(macdMain, macdSignal, signal.histogramValue, 0)) {
            Logger::LogError("GetMACDSignal", "Failed to get MACD values");
            return signal;
        }
        
        signal.macdValue = macdMain;
        signal.signalValue = macdSignal;
        signal.histogramValue = macdMain - macdSignal;
        
        // Calculate bias
        signal.bias = CalculateBias(signal);
        signal.biasString = BiasToString(signal.bias);
        
        // Check for crossovers
        CheckCrossovers(signal);
        
        // Check for zero line position
        CheckZeroLine(signal);
        
        // Calculate histogram slope
        CalculateHistogramSlope(signal);
        
        // Check for divergences
        CheckDivergences(signal);
        
        // Get additional indicator confirmations
        GetIndicatorConfirmations(signal);
        
        // Calculate score and confidence
        CalculateScoreAndConfidence(signal);
        
        // Cache the signal
        m_lastSignal = signal;
        m_lastSignalTime = TimeCurrent();
        
        // Log the signal using integrated Logger
        LogSignal(signal);
        
        // Display on chart if actionable
        if(signal.IsActionable()) {
            signal.DisplayScoreOnChart();
            signal.DisplayDecisionOnChart(GetSignalReason(signal));
        }
        
        return signal;
    }
    
    // Get signal for specific bias
    MACDSignal GetMACDSignalForBias(ENUM_MACD_BIAS targetBias) 
    {
        MACDSignal signal = GetMACDSignal();
        
        if(signal.bias == targetBias) {
            return signal;
        }
        
        // Return empty signal if bias doesn't match
        MACDSignal empty;
        return empty;
    }
    
    // Get trend strength (0-100)
    double GetTrendStrength() 
    {
        MACDSignal signal = GetMACDSignal();
        return signal.confidence;
    }
    
    // Check if there's a crossover signal
    bool HasCrossoverSignal() 
    {
        MACDSignal signal = GetMACDSignal();
        return signal.isCrossover;
    }
    
    // Get crossover direction (1 = bullish, -1 = bearish, 0 = none)
    int GetCrossoverDirection() 
    {
        if(!m_initialized) return 0;
        
        double macdCurrent, signalCurrent;
        double macdPrev, signalPrev;
        
        if(!GetMACDValues(macdCurrent, signalCurrent, 0))
            return 0;
        if(!GetMACDValues(macdPrev, signalPrev, 1))
            return 0;
        
        // Bullish crossover: MACD crosses above signal
        if(macdPrev <= signalPrev && macdCurrent > signalCurrent)
            return 1;
        
        // Bearish crossover: MACD crosses below signal
        if(macdPrev >= signalPrev && macdCurrent < signalCurrent)
            return -1;
        
        return 0;
    }
    
    // Get MACD values directly using integrated IndicatorManager
    bool GetMACDValues(double &macdMain, double &macdSignal, double &histogram, int shift = 0) 
    {
        if(!m_initialized) return false;
        
        if(!m_indicatorManager.GetMACDValues(m_timeframe, macdMain, macdSignal, shift))
            return false;
        
        histogram = macdMain - macdSignal;
        return true;
    }
    
    // Overloaded version without histogram
    bool GetMACDValues(double &macdMain, double &macdSignal, int shift = 0) 
    {
        double histogram;
        return GetMACDValues(macdMain, macdSignal, histogram, shift);
    }
    
    // Get RSI value for confirmation using integrated IndicatorManager
    double GetRSIValue(int shift = 0) 
    {
        if(!m_initialized) return 0;
        
        return m_indicatorManager.GetRSI(m_timeframe, shift);
    }
    
    // Get ADX trend strength using integrated IndicatorManager
    double GetADXTrendStrength(int shift = 0) 
    {
        if(!m_initialized) return 0;
        
        double adx, plus_di, minus_di;
        if(!m_indicatorManager.GetADXValues(m_timeframe, adx, plus_di, minus_di, shift))
            return 0;
        
        return adx;
    }
    
    // Get market score using integrated IndicatorManager
    double GetMarketScore() 
    {
        if(!m_initialized) return 0;
        
        return m_indicatorManager.GetMarketScore();
    }
    
    // Get multi-timeframe confirmation using integrated IndicatorManager
    void GetMultiTimeframeConfirmation(int &bullish_tf_count, int &bearish_tf_count) 
    {
        if(!m_initialized) {
            bullish_tf_count = 0;
            bearish_tf_count = 0;
            return;
        }
        
        m_indicatorManager.GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
    }
    
    // Check if trend is bullish using integrated IndicatorManager
    bool IsTrendBullish() 
    {
        if(!m_initialized) return false;
        
        return m_indicatorManager.IsTrendBullish(m_timeframe);
    }
    
    // Check if trend is bearish using integrated IndicatorManager
    bool IsTrendBearish() 
    {
        if(!m_initialized) return false;
        
        return m_indicatorManager.IsTrendBearish(m_timeframe);
    }
    
    // Check if market is overbought using integrated IndicatorManager
    bool IsOverbought() 
    {
        if(!m_initialized) return false;
        
        return m_indicatorManager.IsOverbought(m_timeframe);
    }
    
    // Check if market is oversold using integrated IndicatorManager
    bool IsOversold() 
    {
        if(!m_initialized) return false;
        
        return m_indicatorManager.IsOversold(m_timeframe);
    }
    
    // Calculate position size based on MACD signal strength and risk
    double CalculateMACDPositionSize(double entryPrice, double stopLoss, double riskPercent = 2.0, double accountBalance = 0) 
    {
        if(accountBalance <= 0) {
            accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        }
        
        MACDSignal signal = GetMACDSignal();
        
        // Adjust risk based on MACD confidence
        double adjustedRisk = riskPercent;
        
        if(signal.confidence > 80) {
            adjustedRisk *= 1.5;
            Logger::Log("PositionSizing", StringFormat("High confidence (%.0f%%) - increasing risk to %.1f%%", 
                signal.confidence, adjustedRisk));
        } else if(signal.confidence < 50) {
            adjustedRisk *= 0.5;
            Logger::Log("PositionSizing", StringFormat("Low confidence (%.0f%%) - reducing risk to %.1f%%", 
                signal.confidence, adjustedRisk));
        }
        
        // Calculate stop loss in pips for position sizing
        double stopLossPips = MathUtils::PriceToPips(m_symbol, MathAbs(entryPrice - stopLoss));
        
        // Use integrated IndicatorManager for position sizing
        double positionSize = m_indicatorManager.CalculatePositionSize(adjustedRisk, stopLossPips, m_timeframe);
        
        // Log position size calculation
        Logger::Log("PositionSizing", StringFormat(
            "Symbol: %s, Entry: %.5f, SL: %.5f, Risk: %.1f%%, Size: %.2f lots",
            m_symbol, entryPrice, stopLoss, adjustedRisk, positionSize
        ));
        
        return positionSize;
    }
    
    // Calculate stop loss based on ATR using integrated IndicatorManager
    double CalculateATRBasedStopLoss(int period = 14, double multiplier = 2.0) 
    {
        double atr = m_indicatorManager.GetATR(m_timeframe, 0);
        double stopLoss = atr * multiplier;
        
        Logger::Log("StopLoss", StringFormat("ATR Stop Loss: %.5f (ATR: %.5f * %.1f)", 
            stopLoss, atr, multiplier));
        
        return stopLoss;
    }
    
    // Display portfolio overview using integrated Logger
    void DisplayPortfolioOverview(string &symbols[], double &scores[], int &directions[]) 
    {
        Logger::ShowPortfolioFast(symbols, scores, directions);
    }
    
    // Display risk metrics using integrated Logger
    void DisplayRiskMetrics(double riskPercent, double drawdownPercent, double sharpeRatio, int positions) 
    {
        Logger::ShowRiskMetrics(riskPercent, drawdownPercent, sharpeRatio, positions);
    }
    
    // Check if initialized
    bool IsInitialized() const { return m_initialized; }
    
    // Get last generated signal
    MACDSignal GetLastSignal() const { return m_lastSignal; }
    
    // Get current market session info using TimeUtils
    string GetMarketSessionInfo() 
    {
        datetime startTime, endTime;
        if(TimeUtils::GetTradingSession(m_symbol, startTime, endTime)) {
            return StringFormat("Market Session: %s to %s", 
                TimeToString(startTime, TIME_MINUTES),
                TimeToString(endTime, TIME_MINUTES));
        }
        return "Market session info unavailable";
    }
    
    // Log trade execution using integrated Logger
    void LogTradeExecution(string operation, double volume, double price = 0.0) 
    {
        if(price > 0) {
            Logger::LogTrade("MACD_Execution", m_symbol, operation, volume, price);
        } else {
            Logger::LogTradeFast("MACD_Execution", m_symbol, operation, volume);
        }
    }
    
    // Log memory usage using integrated Logger
    void LogMemoryUsage() 
    {
        Logger::LogMemoryUsage("MACDModule");
    }
    
    // ==================== HELPER METHODS FOR EXTERNAL CONSUMPTION ====================
    
    // Get raw MACD data for external modules
    MACDRawData GetMACDRawData() {
        MACDSignal signal = GetMACDSignal();
        return signal.GetRawData();
    }
    
    // Get MACD signal data for external modules
    MACDSignalData GetMACDSignalData() {
        MACDSignal signal = GetMACDSignal();
        return signal.GetSignalData();
    }
    
    // Get MACD component description for external modules
    string GetMACDComponentDescription() {
        MACDSignal signal = GetMACDSignal();
        
        string desc = "";
        if(signal.isCrossover) {
            desc = StringFormat("MACD %s Crossover", signal.isAboveZero ? "Above Zero" : "Below Zero");
        } else if(signal.isDivergence) {
            desc = StringFormat("%s Divergence", signal.biasString);
        } else if(signal.signalType == MACD_SIGNAL_ZERO_LINE) {
            desc = "Zero Line Crossover";
        } else {
            desc = StringFormat("MACD %s Trend", signal.biasString);
        }
        
        if(signal.isStrongSignal) {
            desc += " (Strong)";
        }
        
        return desc;
    }
    
    // Get MACD component details for external modules
    string GetMACDComponentDetails() {
        MACDSignal signal = GetMACDSignal();
        return StringFormat(
            "MACD: %.4f | Signal: %.4f | Hist: %.4f | Slope: %.4f | Above Zero: %s",
            signal.macdValue, signal.signalValue, signal.histogramValue,
            signal.histogramSlope, signal.isAboveZero ? "YES" : "NO"
        );
    }
    
    // Get RSI component data for external modules
    RSIData GetRSIComponentData() {
        RSIData data;
        data.value = GetRSIValue();
        data.isOverbought = data.value > 70;
        data.isOversold = data.value < 30;
        data.description = GetRSIComponentDescription(data.value);
        data.score = GetRSIScore(data.value);
        data.confidence = GetRSIConfidence(data.value);
        return data;
    }
    
    // Get ADX component data for external modules
    ADXData GetADXComponentData() {
        ADXData data;
        data.value = GetADXTrendStrength();
        data.isStrongTrend = data.value > 25;
        data.isModerateTrend = data.value > 20 && data.value <= 25;
        data.isWeakTrend = data.value <= 20;
        data.description = GetADXComponentDescription(data.value);
        data.score = GetADXScore(data.value);
        data.confidence = GetADXConfidence(data.value);
        return data;
    }
    
    // Get Multi-timeframe confirmation data for external modules
    MTFConfirmationData GetMTFConfirmationData() {
        MTFConfirmationData data;
        GetMultiTimeframeConfirmation(data.bullish_tf_count, data.bearish_tf_count);
        data.total_tf_count = data.bullish_tf_count + data.bearish_tf_count;
        data.description = GetMTFComponentDescription(data.bullish_tf_count, data.bearish_tf_count);
        data.score = GetMTFScore(data.bullish_tf_count, data.bearish_tf_count);
        data.confidence = GetMTFConfidence(data.bullish_tf_count, data.bearish_tf_count);
        return data;
    }
    
    // Get all confirmation data in one structure
    MACDConfirmationData GetAllConfirmationData() {
        MACDConfirmationData data;
        
        MACDSignal signal = GetMACDSignal();
        data.macdData = signal.GetRawData();
        data.signalData = signal.GetSignalData();
        data.rsiData = GetRSIComponentData();
        data.adxData = GetADXComponentData();
        data.mtfData = GetMTFConfirmationData();
        
        return data;
    }
    
private:
    // ==================== PRIVATE METHODS ====================
    
    // Log signal using integrated Logger
    void LogSignal(const MACDSignal &signal) 
    {
        string action = signal.IsActionable() ? "ACTIONABLE" : "MONITOR";
        
        Logger::Log("MACD_Signal", StringFormat(
            "%s | %s | Score: %.0f | Conf: %.0f%% | %s | Hist: %.4f",
            m_symbol, signal.biasString, signal.score, signal.confidence,
            action, signal.histogramValue
        ));
        
        if(signal.isCrossover) {
            Logger::Log("MACD_Event", StringFormat("%s CROSSOVER detected", m_symbol));
        }
        
        if(signal.isDivergence) {
            Logger::Log("MACD_Event", StringFormat("%s DIVERGENCE detected", m_symbol));
        }
    }
    
    // Get signal reason for display
    string GetSignalReason(const MACDSignal &signal) 
    {
        string reason = "";
        
        if(signal.signalType == MACD_SIGNAL_CROSSOVER) {
            reason = StringFormat("%s crossover", signal.isAboveZero ? "Above zero" : "Below zero");
        } else if(signal.signalType == MACD_SIGNAL_DIVERGENCE) {
            reason = signal.bias == MACD_BIAS_BULLISH ? "Bullish divergence" : "Bearish divergence";
        } else if(signal.signalType == MACD_SIGNAL_ZERO_LINE) {
            reason = "Zero line crossover";
        } else if(signal.signalType == MACD_SIGNAL_TREND) {
            reason = signal.isAboveZero ? "Trend above zero" : "Trend below zero";
        }
        
        if(signal.isStrongSignal) {
            reason += " (STRONG)";
        }
        
        return reason;
    }
    
    // Get additional indicator confirmations
    void GetIndicatorConfirmations(MACDSignal &signal) 
    {
        if(!m_initialized) return;
        
        // Get RSI for overbought/oversold confirmation
        double rsi = GetRSIValue();
        
        // Get ADX for trend strength
        double adx = GetADXTrendStrength();
        
        // Get multi-timeframe confirmation
        int bullish_tf_count, bearish_tf_count;
        GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
        
        // Log indicator confirmations
        Logger::Log("IndicatorConfirmations", StringFormat(
            "RSI: %.1f, ADX: %.1f, Bullish TFs: %d, Bearish TFs: %d",
            rsi, adx, bullish_tf_count, bearish_tf_count
        ));
    }
    
    // Calculate bias based on MACD values
    ENUM_MACD_BIAS CalculateBias(MACDSignal &signal) 
    {
        // Strong bullish: MACD above signal AND above zero
        if(signal.macdValue > signal.signalValue && signal.macdValue > 0) {
            signal.signalType = MACD_SIGNAL_TREND;
            return MACD_BIAS_BULLISH;
        }
        
        // Strong bearish: MACD below signal AND below zero
        if(signal.macdValue < signal.signalValue && signal.macdValue < 0) {
            signal.signalType = MACD_SIGNAL_TREND;
            return MACD_BIAS_BEARISH;
        }
        
        // Weak bullish: MACD above signal but below zero
        if(signal.macdValue > signal.signalValue && signal.macdValue <= 0) {
            signal.signalType = MACD_SIGNAL_TREND;
            return MACD_BIAS_WEAK_BULLISH;
        }
        
        // Weak bearish: MACD below signal but above zero
        if(signal.macdValue < signal.signalValue && signal.macdValue >= 0) {
            signal.signalType = MACD_SIGNAL_TREND;
            return MACD_BIAS_WEAK_BEARISH;
        }
        
        // Neutral
        return MACD_BIAS_NEUTRAL;
    }
    
    // Check for crossovers
    void CheckCrossovers(MACDSignal &signal) 
    {
        if(!m_initialized) return;
        
        double macdPrev, signalPrev;
        if(!GetMACDValues(macdPrev, signalPrev, 1))
            return;
        
        // Bullish crossover
        if(macdPrev <= signalPrev && signal.macdValue > signal.signalValue) {
            signal.isCrossover = true;
            signal.signalType = MACD_SIGNAL_CROSSOVER;
            
            // If crossover happens above zero, it's stronger
            if(signal.macdValue > 0) {
                signal.bias = MACD_BIAS_BULLISH;
                signal.isStrongSignal = true;
            } else {
                signal.bias = MACD_BIAS_WEAK_BULLISH;
            }
            signal.biasString = BiasToString(signal.bias);
        }
        // Bearish crossover
        else if(macdPrev >= signalPrev && signal.macdValue < signal.signalValue) {
            signal.isCrossover = true;
            signal.signalType = MACD_SIGNAL_CROSSOVER;
            
            // If crossover happens below zero, it's stronger
            if(signal.macdValue < 0) {
                signal.bias = MACD_BIAS_BEARISH;
                signal.isStrongSignal = true;
            } else {
                signal.bias = MACD_BIAS_WEAK_BEARISH;
            }
            signal.biasString = BiasToString(signal.bias);
        }
    }
    
    // Check zero line position
    void CheckZeroLine(MACDSignal &signal) 
    {
        signal.isAboveZero = (signal.macdValue > 0);
        
        // Crossing zero line is a strong signal
        double macdPrev, signalPrev;
        if(!GetMACDValues(macdPrev, signalPrev, 1))
            return;
        
        // MACD crosses above zero
        if(macdPrev <= 0 && signal.macdValue > 0) {
            signal.signalType = MACD_SIGNAL_ZERO_LINE;
            signal.isStrongSignal = true;
            signal.bias = MACD_BIAS_BULLISH;
            signal.biasString = BiasToString(signal.bias);
        }
        // MACD crosses below zero
        else if(macdPrev >= 0 && signal.macdValue < 0) {
            signal.signalType = MACD_SIGNAL_ZERO_LINE;
            signal.isStrongSignal = true;
            signal.bias = MACD_BIAS_BEARISH;
            signal.biasString = BiasToString(signal.bias);
        }
    }
    
    // Calculate histogram slope (trend strength)
    void CalculateHistogramSlope(MACDSignal &signal) 
    {
        if(!m_initialized) return;
        
        double histPrev1, histPrev2;
        double macdPrev1, signalPrev1, macdPrev2, signalPrev2;
        
        if(!GetMACDValues(macdPrev1, signalPrev1, 1))
            return;
        if(!GetMACDValues(macdPrev2, signalPrev2, 2))
            return;
        
        histPrev1 = macdPrev1 - signalPrev1;
        histPrev2 = macdPrev2 - signalPrev2;
        
        // Calculate slope (rate of change)
        signal.histogramSlope = signal.histogramValue - histPrev1;
        
        // Check if histogram is expanding (strengthening trend)
        if(signal.bias == MACD_BIAS_BULLISH || signal.bias == MACD_BIAS_WEAK_BULLISH) {
            // Bullish: histogram should be positive and increasing
            if(signal.histogramValue > 0 && signal.histogramSlope > 0) {
                signal.isStrongSignal = true;
            }
        } 
        else if(signal.bias == MACD_BIAS_BEARISH || signal.bias == MACD_BIAS_WEAK_BEARISH) {
            // Bearish: histogram should be negative and decreasing
            if(signal.histogramValue < 0 && signal.histogramSlope < 0) {
                signal.isStrongSignal = true;
            }
        }
    }
    
    // Check for divergences
    void CheckDivergences(MACDSignal &signal) 
    {
        if(!m_initialized) return;
        
        // Need price data for divergence detection
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double pricePrev1 = iClose(m_symbol, m_timeframe, 1);
        double pricePrev2 = iClose(m_symbol, m_timeframe, 2);
        
        double macdPrev1, signalPrev1, macdPrev2, signalPrev2;
        if(!GetMACDValues(macdPrev1, signalPrev1, 1))
            return;
        if(!GetMACDValues(macdPrev2, signalPrev2, 2))
            return;
        
        // Bullish divergence: price makes lower low, MACD makes higher low
        if(currentPrice < pricePrev1 && pricePrev1 < pricePrev2 &&  // Price: lower lows
           signal.macdValue > macdPrev1 && macdPrev1 > macdPrev2) { // MACD: higher lows
            signal.isDivergence = true;
            signal.signalType = MACD_SIGNAL_DIVERGENCE;
            signal.bias = MACD_BIAS_BULLISH;
            signal.biasString = BiasToString(signal.bias);
            signal.isStrongSignal = true;
        }
        // Bearish divergence: price makes higher high, MACD makes lower high
        else if(currentPrice > pricePrev1 && pricePrev1 > pricePrev2 &&  // Price: higher highs
                signal.macdValue < macdPrev1 && macdPrev1 < macdPrev2) { // MACD: lower highs
            signal.isDivergence = true;
            signal.signalType = MACD_SIGNAL_DIVERGENCE;
            signal.bias = MACD_BIAS_BEARISH;
            signal.biasString = BiasToString(signal.bias);
            signal.isStrongSignal = true;
        }
    }
    
    // Calculate score and confidence
    void CalculateScoreAndConfidence(MACDSignal &signal) 
    {
        double baseScore = 50.0;
        
        // Factor 1: MACD position relative to signal line (30%)
        double macdPosition = MathAbs(signal.macdValue - signal.signalValue);
        double positionScore = MathMin(macdPosition * 100, 30.0);
        baseScore += (signal.macdValue > signal.signalValue) ? positionScore : -positionScore;
        
        // Factor 2: Zero line position (20%)
        double zeroScore = MathAbs(signal.macdValue) * 50;
        if(signal.macdValue > 0) {
            baseScore += MathMin(zeroScore, 20.0);
        } else {
            baseScore -= MathMin(zeroScore, 20.0);
        }
        
        // Factor 3: Histogram strength (20%)
        double histScore = MathAbs(signal.histogramValue) * 40;
        baseScore += (signal.histogramValue > 0) ? MathMin(histScore, 20.0) : -MathMin(histScore, 20.0);
        
        // Factor 4: Signal strength bonuses (30%)
        double bonusScore = 0;
        
        if(signal.isCrossover) bonusScore += 15.0;
        if(signal.isDivergence) bonusScore += 20.0;
        if(signal.isAboveZero && signal.macdValue > signal.signalValue) bonusScore += 10.0;
        if(!signal.isAboveZero && signal.macdValue < signal.signalValue) bonusScore += 10.0;
        if(signal.isStrongSignal) bonusScore += 15.0;
        
        // Apply bonus based on bias direction
        if(signal.bias == MACD_BIAS_BULLISH || signal.bias == MACD_BIAS_WEAK_BULLISH) {
            baseScore += bonusScore;
        } else if(signal.bias == MACD_BIAS_BEARISH || signal.bias == MACD_BIAS_WEAK_BEARISH) {
            baseScore -= bonusScore;
        }
        
        // Clamp score between 0-100
        signal.score = MathMax(0.0, MathMin(100.0, baseScore));
        
        // Calculate confidence with indicator confirmations
        signal.confidence = CalculateConfidence(signal);
    }
    
    // Calculate confidence based on multiple factors
    double CalculateConfidence(MACDSignal &signal) 
    {
        double confidence = 0.0;
        
        // Base confidence from score (40%)
        confidence += signal.score * 0.4;
        
        // Signal strength factors (30%)
        double strengthFactor = 0.0;
        if(signal.isCrossover) strengthFactor += 20.0;
        if(signal.isDivergence) strengthFactor += 25.0;
        if(signal.isStrongSignal) strengthFactor += 15.0;
        confidence += MathMin(strengthFactor, 30.0);
        
        // Histogram consistency (15%)
        double histConsistency = MathAbs(signal.histogramSlope) * 50;
        confidence += MathMin(histConsistency, 15.0);
        
        // Zero line alignment (15%)
        if((signal.isAboveZero && signal.bias == MACD_BIAS_BULLISH) ||
           (!signal.isAboveZero && signal.bias == MACD_BIAS_BEARISH)) {
            confidence += 15.0;
        } else if((signal.isAboveZero && signal.bias == MACD_BIAS_BEARISH) ||
                 (!signal.isAboveZero && signal.bias == MACD_BIAS_BULLISH)) {
            confidence -= 10.0;
        }
        
        // Clamp confidence between 0-100
        confidence = MathMax(0.0, MathMin(100.0, confidence));
        
        // Additional validation with other indicators from IndicatorManager
        if(m_indicatorManager != NULL) {
            double rsi = GetRSIValue();
            
            if(signal.bias == MACD_BIAS_BULLISH && rsi < 70) {
                confidence += 5.0;
            } else if(signal.bias == MACD_BIAS_BULLISH && rsi >= 70) {
                confidence -= 10.0;
            }
            
            if(signal.bias == MACD_BIAS_BEARISH && rsi > 30) {
                confidence += 5.0;
            } else if(signal.bias == MACD_BIAS_BEARISH && rsi <= 30) {
                confidence -= 10.0;
            }
            
            double adx = GetADXTrendStrength();
            if(adx > 25) {
                confidence += 5.0;
            } else if(adx < 20) {
                confidence -= 5.0;
            }
            
            int bullish_tf_count, bearish_tf_count;
            GetMultiTimeframeConfirmation(bullish_tf_count, bearish_tf_count);
            
            if(signal.bias == MACD_BIAS_BULLISH && bullish_tf_count > bearish_tf_count) {
                confidence += 10.0;
            } else if(signal.bias == MACD_BIAS_BEARISH && bearish_tf_count > bullish_tf_count) {
                confidence += 10.0;
            } else if((signal.bias == MACD_BIAS_BULLISH && bearish_tf_count > bullish_tf_count) ||
                     (signal.bias == MACD_BIAS_BEARISH && bullish_tf_count > bearish_tf_count)) {
                confidence -= 10.0;
            }
        }
        
        // Check if we're in a trading session using TimeUtils
        if(!TimeUtils::IsTradingSession(m_symbol)) {
            confidence *= 0.8;
        }
        
        // Check for new bar using TimeUtils
        if(TimeUtils::IsNewBar(m_symbol, m_timeframe)) {
            confidence += 5.0;
        }
        
        return MathMax(0.0, MathMin(100.0, confidence));
    }
    
    // Helper: Convert bias to string
    string BiasToString(ENUM_MACD_BIAS bias) 
    {
        switch(bias) {
            case MACD_BIAS_BULLISH: return "BULLISH";
            case MACD_BIAS_BEARISH: return "BEARISH";
            case MACD_BIAS_NEUTRAL: return "NEUTRAL";
            case MACD_BIAS_WEAK_BULLISH: return "WEAK BULLISH";
            case MACD_BIAS_WEAK_BEARISH: return "WEAK BEARISH";
            default: return "UNKNOWN";
        }
    }
    
    // ==================== COMPONENT METHODS ====================
    
    // Get RSI component description
    string GetRSIComponentDescription(double rsi) 
    {
        MACDSignal signal = GetMACDSignal();
        
        if(rsi > 70) return "Overbought";
        if(rsi < 30) return "Oversold";
        
        if(signal.bias == MACD_BIAS_BULLISH && rsi < 70) {
            return "RSI Confirms Bullish";
        } else if(signal.bias == MACD_BIAS_BEARISH && rsi > 30) {
            return "RSI Confirms Bearish";
        } else if(signal.bias == MACD_BIAS_BULLISH && rsi >= 70) {
            return "RSI Contradicts Bullish (Overbought)";
        } else if(signal.bias == MACD_BIAS_BEARISH && rsi <= 30) {
            return "RSI Contradicts Bearish (Oversold)";
        }
        
        return "RSI Neutral";
    }
    
    // Get RSI score
    double GetRSIScore(double rsi) 
    {
        MACDSignal signal = GetMACDSignal();
        double score = 50.0;
        
        if(signal.bias == MACD_BIAS_BULLISH) {
            if(rsi < 70) score = 80.0;
            else if(rsi >= 70) score = 30.0;
        } else if(signal.bias == MACD_BIAS_BEARISH) {
            if(rsi > 30) score = 80.0;
            else if(rsi <= 30) score = 30.0;
        }
        
        return score;
    }
    
    // Get RSI confidence
    double GetRSIConfidence(double rsi) 
    {
        MACDSignal signal = GetMACDSignal();
        double confidence = 0.0;
        
        if(signal.bias == MACD_BIAS_BULLISH && rsi < 70) {
            confidence = 80.0;
        } else if(signal.bias == MACD_BIAS_BULLISH && rsi >= 70) {
            confidence = 40.0;
        } else if(signal.bias == MACD_BIAS_BEARISH && rsi > 30) {
            confidence = 80.0;
        } else if(signal.bias == MACD_BIAS_BEARISH && rsi <= 30) {
            confidence = 40.0;
        } else {
            confidence = 60.0;
        }
        
        return confidence;
    }
    
    // Get ADX component description
    string GetADXComponentDescription(double adx) 
    {
        if(adx > 25) return "Strong Trend";
        if(adx > 20) return "Moderate Trend";
        return "Weak or No Trend";
    }
    
    // Get ADX score
    double GetADXScore(double adx) 
    {
        if(adx > 25) return 85.0;
        if(adx > 20) return 70.0;
        return 50.0;
    }
    
    // Get ADX confidence
    double GetADXConfidence(double adx) 
    {
        if(adx > 25) return 85.0;
        if(adx > 20) return 70.0;
        return 50.0;
    }
    
    // Get MTF component description
    string GetMTFComponentDescription(int bullish_tf_count, int bearish_tf_count) 
    {
        if(bullish_tf_count > bearish_tf_count) {
            return "MTF Bullish Confirmation";
        } else if(bearish_tf_count > bullish_tf_count) {
            return "MTF Bearish Confirmation";
        } else {
            return "MTF Mixed Signals";
        }
    }
    
    // Get MTF score
    double GetMTFScore(int bullish_tf_count, int bearish_tf_count) 
    {
        MACDSignal signal = GetMACDSignal();
        
        if(signal.bias == MACD_BIAS_BULLISH && bullish_tf_count > bearish_tf_count) {
            return 90.0;
        } else if(signal.bias == MACD_BIAS_BEARISH && bearish_tf_count > bullish_tf_count) {
            return 90.0;
        } else if(signal.bias == MACD_BIAS_BULLISH && bearish_tf_count > bullish_tf_count) {
            return 40.0;
        } else if(signal.bias == MACD_BIAS_BEARISH && bullish_tf_count > bearish_tf_count) {
            return 40.0;
        }
        return 60.0;
    }
    
    // Get MTF confidence
    double GetMTFConfidence(int bullish_tf_count, int bearish_tf_count) 
    {
        MACDSignal signal = GetMACDSignal();
        int total = bullish_tf_count + bearish_tf_count;
        if(total == 0) return 50.0;
        
        double ratio = 0.0;
        if(signal.bias == MACD_BIAS_BULLISH) {
            ratio = (double)bullish_tf_count / total;
        } else if(signal.bias == MACD_BIAS_BEARISH) {
            ratio = (double)bearish_tf_count / total;
        }
        
        return ratio * 100.0;
    }
};

//+------------------------------------------------------------------+