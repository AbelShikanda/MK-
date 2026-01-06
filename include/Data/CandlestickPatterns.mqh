//+------------------------------------------------------------------+
//|                      CandlestickPatterns.mqh                    |
//|      Integrated with Static Utils - Using Your Provided Functions|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

// Note: Using ONLY static utility functions as specified
// All utils are static files with static functions only, no classes
// #include "../Utils/Logger.mqh"      // Using Logger::Log(), Logger::LogError(), etc.
#include "../Utils/MathUtils.mqh"   // Using MathUtils::CalculateATR(), MathUtils::CalculatePositionSizeByRisk(), etc.
#include "../Utils/ErrorHandler.mqh"  // Using ErrorHandler::GetLastError(), ErrorHandler::HandleErrorWithRetry(), etc.
#include "../Utils/TimeUtils.mqh"   // Using TimeUtils::IsNewBar(), TimeUtils::TimeframeToMinutes(), etc.

// ====================== MODULE-SPECIFIC DATA STRUCTURES ======================

// CandlePatternSignal structure for Candle Pattern analysis
struct CandlePatternSignal {
    string overallBias;        // "BULLISH", "BEARISH", "NEUTRAL"
    string patternType;        // "HAMMER", "ENGULFING", "DOJI", "MORNING_STAR", etc.
    double score;              // 0-100 pattern strength score
    double confidence;         // 0-100 confidence level
    string patternDescription; // Description of the candle pattern
    int patternStrength;       // Strength level (1-5 or similar)
    double riskRewardRatio;    // Suggested risk/reward ratio
    datetime timestamp;        // When this signal was generated
    
    CandlePatternSignal() {
        overallBias = "NEUTRAL";
        patternType = "NONE";
        score = 0.0;
        confidence = 0.0;
        patternDescription = "";
        patternStrength = 0;
        riskRewardRatio = 0.0;
        timestamp = TimeCurrent();
    }
    
    string ToString() const {
        return StringFormat("Pattern: %s/%s | Score: %.1f | Conf: %.1f%% | Strength: %d | R:R: %.1f",
            patternType, overallBias, score, confidence, patternStrength, riskRewardRatio);
    }
    
    // Helper function (optional - add at top of file after includes)
    bool StringContains(const string text, const string search) {
        return StringFind(text, search) >= 0;
    }

    // Then in your CandlePatternSignal struct:
    bool IsValid() const { return score > 0 && confidence > 0; }
    bool IsBullish() const { return overallBias == "BULLISH"; }
    bool IsBearish() const { return overallBias == "BEARISH"; }
    bool IsHammer() const { 
        return patternType == "HAMMER" || StringFind(patternType, "HAMMER") >= 0; 
    }
    bool IsEngulfing() const { 
        return StringFind(patternType, "ENGULFING") >= 0; 
    }
    bool IsDoji() const { 
        return StringFind(patternType, "DOJI") >= 0; 
    }
    bool IsStarPattern() const { 
        return StringFind(patternType, "STAR") >= 0; 
    }
    bool IsReversalPattern() const { 
        return StringFind(patternType, "STAR") >= 0 || 
            StringFind(patternType, "HAMMER") >= 0 || 
            StringFind(patternType, "SHOOTING") >= 0; 
    }
};

// CandleComponentDisplay for UI/display purposes
struct CandleComponentDisplay {
    string componentName;
    string bias;
    double score;
    double confidence;
    double weight;
    bool isActive;
    string details;
    color textColor;
    color bgColor;
    
    CandleComponentDisplay() {
        componentName = "";
        bias = "NEUTRAL";
        score = 0.0;
        confidence = 0.0;
        weight = 0.0;
        isActive = false;
        details = "";
        textColor = clrBlack;
        bgColor = clrWhite;
    }
    
    CandleComponentDisplay(string name, string biasVal, double scoreVal, double confVal, 
                    double weightVal, bool active, string detailStr) {
        componentName = name;
        bias = biasVal;
        score = scoreVal;
        confidence = confVal;
        weight = weightVal;
        isActive = active;
        details = detailStr;
        
        // Set colors based on bias
        if(biasVal == "BULLISH") {
            textColor = clrGreen;
            bgColor = clrPaleGreen;
        }
        else if(biasVal == "BEARISH") {
            textColor = clrRed;
            bgColor = clrMistyRose;
        }
        else {
            textColor = clrGray;
            bgColor = clrWhiteSmoke;
        }
    }
    
    string ToString() const {
        return StringFormat("%s: %s (%.1f/%.1f) | %s", 
            componentName, bias, score, confidence, details);
    }
};

// ====================== ENUMERATIONS ======================
enum ENUM_CANDLE_PATTERN {
    PATTERN_NONE = 0,
    PATTERN_HAMMER, PATTERN_INVERTED_HAMMER, PATTERN_SHOOTING_STAR, 
    PATTERN_HANGING_MAN, PATTERN_SPINNING_TOP, PATTERN_MARUBOZU_BULLISH,
    PATTERN_MARUBOZU_BEARISH, PATTERN_STANDARD_DOJI, PATTERN_DRAGONFLY_DOJI,
    PATTERN_GRAVESTONE_DOJI, PATTERN_LONG_LEGGED_DOJI, PATTERN_BULLISH_ENGULFING,
    PATTERN_BEARISH_ENGULFING, PATTERN_BULLISH_HARAMI, PATTERN_BEARISH_HARAMI,
    PATTERN_PIERCING_LINE, PATTERN_DARK_CLOUD_COVER, PATTERN_MORNING_STAR,
    PATTERN_EVENING_STAR, PATTERN_THREE_WHITE_SOLDIERS, PATTERN_THREE_BLACK_CROWS
};

// ====================== STRUCTURES ======================
struct CandleData {
    double open, high, low, close, body, upperWick, lowerWick, totalRange, bodyRatio;
    datetime time;
    color candleColor;
    
    bool IsBullish() const { return close > open; }
    bool IsBearish() const { return close < open; }
    bool IsDoji(double threshold = 0.1) const { return bodyRatio < threshold; }
};

struct PatternResult {
    ENUM_CANDLE_PATTERN pattern;
    string direction;
    double confidence;
    string description;
    datetime patternTime;
    int barsInvolved;
    double targetPrice, stopLoss, riskRewardRatio;
    bool isConfirmed;
    bool maConfirmed, rsiConfirmed, macdConfirmed, adxConfirmed, stochConfirmed, bbandsConfirmed;
    
    // Entry/Exit signals for trading
    double entryPrice;
    string signalType;  // "BUY", "SELL", "NONE"
    
    bool IsActionable() const { return confidence >= 70.0 && IndicatorsConfirm(); }
    bool IndicatorsConfirm() const { 
        int confirmCount = 0;
        if(maConfirmed) confirmCount++;
        if(rsiConfirmed) confirmCount++;
        if(macdConfirmed) confirmCount++;
        if(adxConfirmed) confirmCount++;
        if(stochConfirmed) confirmCount++;
        if(bbandsConfirmed) confirmCount++;
        return confirmCount >= 2;
    }
    
    bool HasSignal() const { return signalType == "BUY" || signalType == "SELL"; }
    bool IsBuySignal() const { return signalType == "BUY"; }
    bool IsSellSignal() const { return signalType == "SELL"; }
    
    string ToString() const {
        return StringFormat("%s | %s | %.1f%% | Conf:%s | Signal:%s", 
            description, direction, confidence, IndicatorsConfirm() ? "YES" : "NO", signalType);
    }
    
    // Get CandlePatternSignal from PatternResult
    CandlePatternSignal GetCandlePatternSignal() const {
        CandlePatternSignal signal;
        signal.overallBias = direction;
        signal.patternType = description;
        
        if(IsActionable()) {
            signal.patternType = description + "_STRONG";
        }
        
        signal.score = confidence;
        signal.confidence = confidence;
        signal.patternDescription = description + (IndicatorsConfirm() ? " [CONFIRMED]" : "");
        signal.patternStrength = IsActionable() ? 5 : (confidence > 50 ? 3 : 1);
        signal.riskRewardRatio = riskRewardRatio;
        
        if(stopLoss > 0 && targetPrice > 0) {
            signal.riskRewardRatio = riskRewardRatio;
        }
        
        signal.timestamp = patternTime;
        return signal;
    }
    
    // Get CandleComponentDisplay from PatternResult
    CandleComponentDisplay GetCandleComponentDisplay() const {
        bool isActive = confidence > 0;
        string details = description;
        if(IndicatorsConfirm()) details += " [CONF]";
        
        return CandleComponentDisplay(
            "CANDLE",
            direction,
            confidence,
            confidence,
            10.0, // Weight
            isActive,
            details
        );
    }
};

// ====================== INDICATOR FUNCTIONS (Static) ======================
// These replace the IndicatorManager class
namespace IndicatorUtils {
    
    // Get indicator values using built-in MQL5 functions
    bool GetMAValues(string symbol, ENUM_TIMEFRAMES tf, double &fastMA, double &slowMA, double &mediumMA, int shift = 0) {
        int fastHandle = iMA(symbol, tf, 9, 0, MODE_EMA, PRICE_CLOSE);
        int slowHandle = iMA(symbol, tf, 21, 0, MODE_SMA, PRICE_CLOSE);
        int mediumHandle = iMA(symbol, tf, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || mediumHandle == INVALID_HANDLE) 
            return false;
        
        double buffer[1];
        if(CopyBuffer(fastHandle, 0, shift, 1, buffer) > 0) fastMA = buffer[0];
        if(CopyBuffer(slowHandle, 0, shift, 1, buffer) > 0) slowMA = buffer[0];
        if(CopyBuffer(mediumHandle, 0, shift, 1, buffer) > 0) mediumMA = buffer[0];
        
        IndicatorRelease(fastHandle);
        IndicatorRelease(slowHandle);
        IndicatorRelease(mediumHandle);
        
        return (fastMA > 0 && slowMA > 0 && mediumMA > 0);
    }
    
    double GetRSI(string symbol, ENUM_TIMEFRAMES tf, int shift = 0) {
        int handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return 0;
        
        double buffer[1];
        double result = 0;
        if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) result = buffer[0];
        
        IndicatorRelease(handle);
        return result;
    }
    
    bool GetMACDValues(string symbol, ENUM_TIMEFRAMES tf, double &main, double &signal, int shift = 0) {
        int handle = iMACD(symbol, tf, 12, 26, 9, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return false;
        
        double buffer[1];
        if(CopyBuffer(handle, MAIN_LINE, shift, 1, buffer) > 0) main = buffer[0];
        if(CopyBuffer(handle, SIGNAL_LINE, shift, 1, buffer) > 0) signal = buffer[0];
        
        IndicatorRelease(handle);
        return (main != 0 && signal != 0);
    }
    
    bool GetADXValues(string symbol, ENUM_TIMEFRAMES tf, double &adx, double &plusDI, double &minusDI, int shift = 0) {
        int handle = iADX(symbol, tf, 14);
        if(handle == INVALID_HANDLE) return false;
        
        double buffer[1];
        if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) adx = buffer[0];
        if(CopyBuffer(handle, 1, shift, 1, buffer) > 0) plusDI = buffer[0];
        if(CopyBuffer(handle, 2, shift, 1, buffer) > 0) minusDI = buffer[0];
        
        IndicatorRelease(handle);
        return (adx > 0);
    }
    
    bool GetStochasticValues(string symbol, ENUM_TIMEFRAMES tf, double &main, double &signal, int shift = 0) {
        int handle = iStochastic(symbol, tf, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
        if(handle == INVALID_HANDLE) return false;
        
        double buffer[1];
        if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) main = buffer[0];
        if(CopyBuffer(handle, 1, shift, 1, buffer) > 0) signal = buffer[0];
        
        IndicatorRelease(handle);
        return (main > 0);
    }
    
    bool GetBollingerBandsValues(string symbol, ENUM_TIMEFRAMES tf, double &upper, double &middle, double &lower, int shift = 0) {
        int handle = iBands(symbol, tf, 20, 0, 2, PRICE_CLOSE);
        if(handle == INVALID_HANDLE) return false;
        
        double buffer[1];
        if(CopyBuffer(handle, 1, shift, 1, buffer) > 0) upper = buffer[0];
        if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) middle = buffer[0];
        if(CopyBuffer(handle, 2, shift, 1, buffer) > 0) lower = buffer[0];
        
        IndicatorRelease(handle);
        return (upper > 0 && lower > 0);
    }
    
    int GetBBandsPosition(string symbol, ENUM_TIMEFRAMES tf, double price, int shift = 0) {
        double upper = 0, middle = 0, lower = 0;
        if(!GetBollingerBandsValues(symbol, tf, upper, middle, lower, shift))
            return 0;
        
        double bandWidth = upper - lower;
        double pricePos = (price - lower) / bandWidth;
        
        if(pricePos > 0.8) return 2;      // Above upper band
        if(pricePos > 0.6) return 1;      // Upper half
        if(pricePos < 0.2) return -2;     // Below lower band
        if(pricePos < 0.4) return -1;     // Lower half
        return 0;                          // Middle band
    }
    
    double GetATR(string symbol, ENUM_TIMEFRAMES tf, int shift = 0) {
        int handle = iATR(symbol, tf, 14);
        if(handle == INVALID_HANDLE) return 0;
        
        double buffer[1];
        double result = 0;
        if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) result = buffer[0];
        
        IndicatorRelease(handle);
        return result;
    }
    
    double GetATRWithFallback(string symbol, ENUM_TIMEFRAMES tf, int shift = 0) {
        double atr = GetATR(symbol, tf, shift);
        if(atr > 0) return atr;
        
        // Fallback using MathUtils
        return MathUtils::CalculateATR(symbol, tf, 14, shift);
    }
    
    double CalculatePositionSize(string symbol, double riskPercent, double stopLossPips, ENUM_TIMEFRAMES tf) {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double stopLossPrice = entryPrice - (stopLossPips * SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
        
        return MathUtils::CalculatePositionSizeByRisk(symbol, entryPrice, stopLossPrice, riskPercent, accountBalance);
    }
}

// ====================== MAIN CLASS ======================
class CandlestickPatternAnalyzer {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_initialized;
    
    CandleData GetCandleData(int shift) {
        CandleData candle;
        candle.open = iOpen(m_symbol, m_timeframe, shift);
        candle.high = iHigh(m_symbol, m_timeframe, shift);
        candle.low = iLow(m_symbol, m_timeframe, shift);
        candle.close = iClose(m_symbol, m_timeframe, shift);
        candle.time = iTime(m_symbol, m_timeframe, shift);
        
        if(candle.close <= 0) return candle;
        
        candle.body = MathAbs(candle.close - candle.open);
        candle.totalRange = candle.high - candle.low;
        
        if(candle.IsBullish()) {
            candle.upperWick = candle.high - candle.close;
            candle.lowerWick = candle.open - candle.low;
            candle.candleColor = clrGreen;
        } else {
            candle.upperWick = candle.high - candle.open;
            candle.lowerWick = candle.close - candle.low;
            candle.candleColor = clrRed;
        }
        
        candle.bodyRatio = (candle.totalRange > 0) ? candle.body / candle.totalRange : 0;
        return candle;
    }
    
    // Pattern detection methods
    bool IsHammer(const CandleData &candle) {
        if(!candle.IsBullish()) return false;
        return (candle.lowerWick >= 2.0 * candle.body && candle.bodyRatio <= 0.3);
    }
    
    bool IsShootingStar(const CandleData &candle) {
        if(!candle.IsBearish()) return false;
        return (candle.upperWick >= 2.0 * candle.body && candle.bodyRatio <= 0.3);
    }
    
    bool IsDoji(const CandleData &candle) {
        return candle.bodyRatio < 0.1;
    }
    
    // Pattern checkers
    PatternResult CheckSingleCandlePattern(CandleData &candle) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        
        if(IsHammer(candle)) {
            result.pattern = PATTERN_HAMMER;
            result.direction = "BULLISH";
            result.confidence = 65.0;
            result.description = "Hammer";
            result.barsInvolved = 1;
        }
        else if(IsShootingStar(candle)) {
            result.pattern = PATTERN_SHOOTING_STAR;
            result.direction = "BEARISH";
            result.confidence = 65.0;
            result.description = "Shooting Star";
            result.barsInvolved = 1;
        }
        else if(IsDoji(candle)) {
            result.pattern = PATTERN_STANDARD_DOJI;
            result.direction = "NEUTRAL";
            result.confidence = 55.0;
            result.description = "Doji";
            result.barsInvolved = 1;
        }
        
        return result;
    }
    
    PatternResult CheckBullishEngulfing(CandleData &c1, CandleData &c2) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        if(c1.IsBearish() && c2.IsBullish() && c2.open < c1.close && c2.close > c1.open) {
            result.pattern = PATTERN_BULLISH_ENGULFING;
            result.direction = "BULLISH";
            result.confidence = 75.0;
            result.description = "Bullish Engulfing";
            result.barsInvolved = 2;
        }
        return result;
    }
    
    PatternResult CheckBearishEngulfing(CandleData &c1, CandleData &c2) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        if(c1.IsBullish() && c2.IsBearish() && c2.open > c1.close && c2.close < c1.open) {
            result.pattern = PATTERN_BEARISH_ENGULFING;
            result.direction = "BEARISH";
            result.confidence = 75.0;
            result.description = "Bearish Engulfing";
            result.barsInvolved = 2;
        }
        return result;
    }
    
    PatternResult CheckTwoCandlePattern(CandleData &c1, CandleData &c2) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        PatternResult patterns[2];
        
        patterns[0] = CheckBullishEngulfing(c1, c2);
        patterns[1] = CheckBearishEngulfing(c1, c2);
        
        for(int i = 0; i < 2; i++) {
            if(patterns[i].confidence > result.confidence) result = patterns[i];
        }
        return result;
    }
    
    PatternResult CheckMorningStar(CandleData &c1, CandleData &c2, CandleData &c3) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        if(c1.IsBearish() && c3.IsBullish() && c1.bodyRatio > 0.6 && c3.bodyRatio > 0.6 &&
           c2.low > c1.close && c3.open > c2.high && c2.bodyRatio < 0.3) {
            result.pattern = PATTERN_MORNING_STAR;
            result.direction = "BULLISH";
            result.confidence = 85.0;
            result.description = "Morning Star";
            result.barsInvolved = 3;
        }
        return result;
    }
    
    PatternResult CheckEveningStar(CandleData &c1, CandleData &c2, CandleData &c3) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        if(c1.IsBullish() && c3.IsBearish() && c1.bodyRatio > 0.6 && c3.bodyRatio > 0.6 &&
           c2.low > c1.close && c3.open < c2.low && c2.bodyRatio < 0.3) {
            result.pattern = PATTERN_EVENING_STAR;
            result.direction = "BEARISH";
            result.confidence = 85.0;
            result.description = "Evening Star";
            result.barsInvolved = 3;
        }
        return result;
    }
    
    PatternResult CheckThreeCandlePattern(CandleData &c1, CandleData &c2, CandleData &c3) {
        PatternResult result = {PATTERN_NONE, "NEUTRAL", 0.0};
        PatternResult patterns[2];
        
        patterns[0] = CheckMorningStar(c1, c2, c3);
        patterns[1] = CheckEveningStar(c1, c2, c3);
        
        for(int i = 0; i < 2; i++) {
            if(patterns[i].confidence > result.confidence) result = patterns[i];
        }
        return result;
    }
    
    // Indicator confirmation methods using static IndicatorUtils
    void CheckIndicatorConfirmations(PatternResult &result, int shift = 0) {
        result.maConfirmed = CheckMAConfirmation(result, shift);
        result.rsiConfirmed = CheckRSIConfirmation(result, shift);
        result.macdConfirmed = CheckMACDConfirmation(result, shift);
        result.adxConfirmed = CheckADXConfirmation(result, shift);
        result.stochConfirmed = CheckStochasticConfirmation(result, shift);
        result.bbandsConfirmed = CheckBBandsConfirmation(result, shift);
        
        // Adjust confidence based on indicators using MathUtils
        if(result.IndicatorsConfirm()) {
            result.confidence = MathMin(100.0, MathUtils::CalculateValueFromPercentage(result.confidence, 120.0)); // +20% boost
        }
        
        // Set signal type based on actionable status
        if(result.IsActionable()) {
            result.signalType = (result.direction == "BULLISH") ? "BUY" : 
                               (result.direction == "BEARISH") ? "SELL" : "NONE";
        } else {
            result.signalType = "NONE";
        }
        
        // Set entry price
        result.entryPrice = iClose(m_symbol, m_timeframe, shift);
    }
    
    bool CheckMAConfirmation(PatternResult &result, int shift) {
        double ma_fast = 0, ma_slow = 0, ma_medium = 0;
        if(!IndicatorUtils::GetMAValues(m_symbol, m_timeframe, ma_fast, ma_slow, ma_medium, shift)) 
            return false;
        
        double price = iClose(m_symbol, m_timeframe, shift);
        
        if(result.direction == "BULLISH") return (price > ma_fast && price > ma_slow);
        if(result.direction == "BEARISH") return (price < ma_fast && price < ma_slow);
        return false;
    }
    
    bool CheckRSIConfirmation(PatternResult &result, int shift) {
        double rsi = IndicatorUtils::GetRSI(m_symbol, m_timeframe, shift);
        if(rsi <= 0) return false;
        
        if(result.direction == "BULLISH") return (rsi < 70 && rsi > 30);
        if(result.direction == "BEARISH") return (rsi > 30 && rsi < 70);
        return false;
    }
    
    bool CheckMACDConfirmation(PatternResult &result, int shift) {
        double macd_main = 0, macd_signal = 0;
        if(!IndicatorUtils::GetMACDValues(m_symbol, m_timeframe, macd_main, macd_signal, shift))
            return false;
        
        if(result.direction == "BULLISH") return (macd_main > macd_signal);
        if(result.direction == "BEARISH") return (macd_main < macd_signal);
        return false;
    }
    
    bool CheckADXConfirmation(PatternResult &result, int shift) {
        double adx = 0, plus_di = 0, minus_di = 0;
        if(!IndicatorUtils::GetADXValues(m_symbol, m_timeframe, adx, plus_di, minus_di, shift))
            return false;
        
        if(result.direction == "BULLISH") return (adx > 25 && plus_di > minus_di);
        if(result.direction == "BEARISH") return (adx > 25 && minus_di > plus_di);
        return false;
    }
    
    bool CheckStochasticConfirmation(PatternResult &result, int shift) {
        double stoch_main = 0, stoch_signal = 0;
        if(!IndicatorUtils::GetStochasticValues(m_symbol, m_timeframe, stoch_main, stoch_signal, shift))
            return false;
        
        if(result.direction == "BULLISH") return (stoch_main < 30);
        if(result.direction == "BEARISH") return (stoch_main > 70);
        return false;
    }
    
    bool CheckBBandsConfirmation(PatternResult &result, int shift) {
        double upper = 0, middle = 0, lower = 0;
        if(!IndicatorUtils::GetBollingerBandsValues(m_symbol, m_timeframe, upper, middle, lower, shift))
            return false;
        
        double price = iClose(m_symbol, m_timeframe, shift);
        int bbandsPos = IndicatorUtils::GetBBandsPosition(m_symbol, m_timeframe, price, shift);
        
        if(result.direction == "BULLISH") return (bbandsPos == -1 || bbandsPos == -2);
        if(result.direction == "BEARISH") return (bbandsPos == 1 || bbandsPos == 2);
        return false;
    }
    
    void CalculateATRBasedLevels(PatternResult &result, int shift = 0) {
        double atr = IndicatorUtils::GetATRWithFallback(m_symbol, m_timeframe, shift);
        if(atr <= 0) return;
        
        double currentPrice = iClose(m_symbol, m_timeframe, shift);
        
        if(result.direction == "BULLISH") {
            result.stopLoss = currentPrice - (atr * 1.5);
            result.targetPrice = currentPrice + (atr * 3.0);
        }
        else if(result.direction == "BEARISH") {
            result.stopLoss = currentPrice + (atr * 1.5);
            result.targetPrice = currentPrice - (atr * 3.0);
        }
        
        // Calculate risk/reward ratio using MathUtils
        if(result.stopLoss > 0 && result.targetPrice > 0) {
            result.riskRewardRatio = MathUtils::CalculateRiskRewardRatio(currentPrice, result.stopLoss, result.targetPrice);
        }
    }

public:
    CandlestickPatternAnalyzer() {
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_initialized = false;
    }
    
    bool Initialize(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) {
        if(m_initialized) {
            // Logger::Log("CandlePatterns", "Already initialized", false, true);
            return false;
        }
        
        m_symbol = (symbol == NULL || symbol == "") ? Symbol() : symbol;
        m_timeframe = (timeframe == PERIOD_CURRENT) ? Period() : timeframe;
        
        // Test data retrieval with error handling
        double testClose = iClose(m_symbol, m_timeframe, 0);
        if(testClose <= 0) {
            int errorCode = ErrorHandler::GetLastError();
            // Logger::LogError("CandlePatterns", "Failed to retrieve candle data", errorCode);
            return false;
        }
        
        m_initialized = true;
        // Logger::Log("CandlePatterns", "Initialized for " + m_symbol + " on timeframe " + 
                // IntegerToString(TimeUtils::TimeframeToMinutes(m_timeframe)) + " minutes");
        return true;
    }
    
    // MAIN ANALYSIS METHOD - Returns module-specific PatternResult
    PatternResult AnalyzeCurrentPattern(int shift = 1) {
        PatternResult bestResult = {PATTERN_NONE, "NEUTRAL", 0.0};
        if(!m_initialized) return bestResult;
        
        CandleData candles[5];
        for(int i = 0; i < 5; i++) {
            candles[i] = GetCandleData(shift + i);
            if(candles[i].close <= 0) {
                int errorCode = ErrorHandler::GetLastError();
                if(errorCode != 0) {
                    // Logger::LogError("CandlePatterns", "Failed to get candle data at shift " + 
                                   // IntegerToString(shift + i), errorCode);
                }
                return bestResult;
            }
        }
        
        bestResult = CheckSingleCandlePattern(candles[0]);
        
        for(int i = 0; i < 4; i++) {
            PatternResult twoCandle = CheckTwoCandlePattern(candles[i], candles[i+1]);
            if(twoCandle.confidence > bestResult.confidence) bestResult = twoCandle;
        }
        
        for(int i = 0; i < 3; i++) {
            PatternResult threeCandle = CheckThreeCandlePattern(candles[i], candles[i+1], candles[i+2]);
            if(threeCandle.confidence > bestResult.confidence) bestResult = threeCandle;
        }
        
        if(bestResult.pattern != PATTERN_NONE) {
            bestResult.patternTime = candles[0].time;
            CheckIndicatorConfirmations(bestResult, shift);
            CalculateATRBasedLevels(bestResult, shift);
            bestResult.isConfirmed = bestResult.IndicatorsConfirm();
            
            if(bestResult.IsActionable()) {
                string logMsg = StringFormat("Actionable pattern: %s (%.1f%% | RR:%.1f)", 
                    bestResult.description, bestResult.confidence, bestResult.riskRewardRatio);
                // Logger::Log("CandlePatterns", logMsg, true, true);
            }
        }
        
        return bestResult;
    }
    
    // Returns module-specific CandlePatternSignal structure
    CandlePatternSignal GetCandlePatternSignal(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.GetCandlePatternSignal();
    }
    
    // Returns module-specific CandleComponentDisplay structure
    CandleComponentDisplay GetCandleComponentDisplay(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.GetCandleComponentDisplay();
    }
    
    // Returns raw score for integration purposes
    double GetPatternScore(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        double baseScore = MathUtils::CalculatePercentageOfValue(result.confidence, 100.0);
        return result.IndicatorsConfirm() ? 
               MathUtils::CalculateValueFromPercentage(baseScore, 120.0) : // Boost for confirmation
               baseScore;
    }
    
    // Returns pattern direction
    string GetPatternDirection(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.direction;
    }
    
    // Check if pattern is actionable
    bool HasStrongPattern(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.IsActionable();
    }
    
    // Check for specific signals
    bool HasBuySignal(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.IsBuySignal();
    }
    
    bool HasSellSignal(int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        return result.IsSellSignal();
    }
    
    // Get trade setup data (entry, stop loss, take profit)
    bool GetTradeSetup(double &entry, double &stopLoss, double &takeProfit, double &riskReward, int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        if(!result.HasSignal()) return false;
        
        entry = result.entryPrice;
        stopLoss = result.stopLoss;
        takeProfit = result.targetPrice;
        riskReward = result.riskRewardRatio;
        return true;
    }
    
    // Get position size calculation
    double GetRecommendedPositionSize(double riskPercent = 1.0, int shift = 1) {
        PatternResult result = AnalyzeCurrentPattern(shift);
        if(!result.HasSignal()) return 0.0;
        
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        return MathUtils::CalculatePositionSizeByRisk(m_symbol, result.entryPrice, 
                                                     result.stopLoss, riskPercent, accountBalance);
    }
    
    bool IsInitialized() const { return m_initialized; }
    
    // Get all patterns in a window (for confluence analysis)
    PatternResult AnalyzePatternsInWindow(int windowSize = 10) {
        PatternResult strongest = {PATTERN_NONE, "NEUTRAL", 0.0};
        
        for(int i = 0; i < windowSize; i++) {
            PatternResult current = AnalyzeCurrentPattern(i + 1);
            if(current.confidence > strongest.confidence) {
                strongest = current;
            }
        }
        
        return strongest;
    }
};

// ====================== GLOBAL FUNCTIONS ======================

// Single instance for easy access
CandlestickPatternAnalyzer g_CandleAnalyzer;

bool InitializeCandleAnalyzer(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) {
    return g_CandleAnalyzer.Initialize(symbol, timeframe);
}

// Returns module-specific PatternResult
PatternResult AnalyzeCandlePattern(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) {
        PatternResult empty;
        return empty;
    }
    return g_CandleAnalyzer.AnalyzeCurrentPattern(shift);
}

// Returns module-specific CandlePatternSignal
CandlePatternSignal GetCandlePatternSignal(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) {
        CandlePatternSignal empty;
        return empty;
    }
    return g_CandleAnalyzer.GetCandlePatternSignal(shift);
}

// Returns module-specific CandleComponentDisplay
CandleComponentDisplay GetCandleCandleComponentDisplay(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) {
        return CandleComponentDisplay("CANDLE", "NEUTRAL", 0, 0, 0, false, "Not initialized");
    }
    return g_CandleAnalyzer.GetCandleComponentDisplay(shift);
}

// Utility functions for quick checks
double GetCandlePatternScore(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return 0;
    return g_CandleAnalyzer.GetPatternScore(shift);
}

string GetCandlePatternDirection(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return "NEUTRAL";
    return g_CandleAnalyzer.GetPatternDirection(shift);
}

bool HasStrongCandlePattern(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return false;
    return g_CandleAnalyzer.HasStrongPattern(shift);
}

// Signal checking functions
bool CandlePatternSignalsBuy(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return false;
    return g_CandleAnalyzer.HasBuySignal(shift);
}

bool CandlePatternSignalsSell(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return false;
    return g_CandleAnalyzer.HasSellSignal(shift);
}

// Trade setup functions
bool GetCandleTradeSetup(string symbol, double &entry, double &stopLoss, double &takeProfit, 
                        double &riskReward, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return false;
    return g_CandleAnalyzer.GetTradeSetup(entry, stopLoss, takeProfit, riskReward, shift);
}

// Position size calculation
double GetCandleBasedPositionSize(string symbol = NULL, double riskPercent = 1.0, 
                                 ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int shift = 1) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) return 0.01;
    return g_CandleAnalyzer.GetRecommendedPositionSize(riskPercent, shift);
}

// Pattern analysis in window
PatternResult AnalyzeCandlePatternsInWindow(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, 
                                           int windowSize = 10) {
    if(!g_CandleAnalyzer.Initialize(symbol, tf)) {
        PatternResult empty;
        return empty;
    }
    return g_CandleAnalyzer.AnalyzePatternsInWindow(windowSize);
}

// Helper function to get pattern description
string GetPatternDescription(ENUM_CANDLE_PATTERN pattern) {
    switch(pattern) {
        case PATTERN_HAMMER: return "Hammer";
        case PATTERN_SHOOTING_STAR: return "Shooting Star";
        case PATTERN_BULLISH_ENGULFING: return "Bullish Engulfing";
        case PATTERN_BEARISH_ENGULFING: return "Bearish Engulfing";
        case PATTERN_MORNING_STAR: return "Morning Star";
        case PATTERN_EVENING_STAR: return "Evening Star";
        case PATTERN_STANDARD_DOJI: return "Doji";
        default: return "Unknown Pattern";
    }
}