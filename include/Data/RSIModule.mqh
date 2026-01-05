//+------------------------------------------------------------------+
//|                           SimpleRSI.mqh                          |
//|           RSI Bias & Confidence with IndicatorManager            |
//|           MODULE-ONLY VERSION - NO TRADEPACKAGE DEPENDENCIES     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Utils/Logger.mqh"
#include "IndicatorManager.mqh"

// ==================== DEBUG SETTINGS ====================
bool DEBUG_SIMPLE_RSI = false;

// Simple debug function using Logger
void DebugLogSimpleRSI(string context, string message) {
   if(DEBUG_SIMPLE_RSI) {
      Logger::Log("DEBUG-SimpleRSI-" + context, message, true, true);
   }
}

// ==================== RSI DATA STRUCTURES ====================

// RSI Bias Structure
struct RSIBias
{
    double bullishBias;     // 0 to +100 (how bullish)
    double bearishBias;     // 0 to +100 (how bearish)
    double netBias;         // -100 to +100 (net direction)
    double confidence;      // 0-100 (how confident we are in the bias)
    string biasText;        // "STRONG_BULLISH", etc.
    string rsiLevel;        // "OVERSOLD", "OVERBOUGHT", "NEUTRAL"
    bool usingIndicatorManager; // true if using IndicatorManager, false if direct
    double currentRSI;
    
    // Constructor for easy initialization
    RSIBias()
    {
        bullishBias = 50.0;
        bearishBias = 50.0;
        netBias = 0.0;
        confidence = 0.0;
        biasText = "NEUTRAL";
        rsiLevel = "NEUTRAL";
        usingIndicatorManager = false;
        currentRSI = 50.0;
    }
    
    // Get string representation
    string ToString() const
    {
        return StringFormat("RSIBias: %s (Bull:%.1f/Bear:%.1f/Net:%.1f) Conf:%.1f%% Level:%s RSI:%.1f %s",
            biasText, bullishBias, bearishBias, netBias, confidence, rsiLevel, currentRSI,
            usingIndicatorManager ? "[IndicatorManager]" : "[Direct]");
    }
};

// Simple RSI Signal Structure
struct RSISignal
{
    ENUM_ORDER_TYPE orderType;  // ORDER_TYPE_BUY or ORDER_TYPE_SELL
    string signalSource;        // "RSI"
    string reason;              // Reason for the signal
    double confidence;          // 0-100 confidence level
    double netBias;             // Net bias value
    string biasText;            // Bias text description
    
    // Constructor
    RSISignal()
    {
        orderType = ORDER_TYPE_BUY;
        signalSource = "RSI";
        reason = "No signal";
        confidence = 0.0;
        netBias = 0.0;
        biasText = "NEUTRAL";
    }
    
    // Check if signal is valid
    bool IsValid() const
    {
        return (confidence > 50.0 && (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL));
    }
    
    // Get string representation
    string ToString() const
    {
        if(!IsValid())
            return "RSISignal: No valid signal";
            
        string type = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
        return StringFormat("RSISignal: %s | %s | Conf:%.1f%% | Bias:%s(%.1f)",
            type, reason, confidence, biasText, netBias);
    }
    
    // Get simple signal string
    string GetSimpleSignal() const
    {
        if(!IsValid())
            return "NEUTRAL";
            
        string type = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
        return StringFormat("%s_%.0f", type, confidence);
    }
};

// RSI Component Display Structure (for UI/display purposes)
struct RSIComponentDisplay
{
    string componentName;    // "RSI"
    string direction;        // "BULLISH", "BEARISH", "NEUTRAL"
    double strength;         // 0-100 strength
    double confidence;       // 0-100 confidence
    double weight;           // Suggested weight (0-100)
    bool isActive;           // Whether component is active
    string details;          // Additional details
    
    // Constructor
    RSIComponentDisplay()
    {
        componentName = "RSI";
        direction = "NEUTRAL";
        strength = 0.0;
        confidence = 0.0;
        weight = 15.0;  // Default RSI weight
        isActive = false;
        details = "";
    }
    
    // Get string representation
    string ToString() const
    {
        return StringFormat("RSIComponent: %s | Dir:%s | Str:%.1f | Conf:%.1f | Wgt:%.1f | Active:%s | %s",
            componentName, direction, strength, confidence, weight,
            isActive ? "Yes" : "No", details);
    }
};

// ==================== SIMPLE RSI MODULE ====================
class SimpleRSI
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int m_period;
    double m_overbought;
    double m_oversold;
    IndicatorManager* m_indicatorMgr;
    
public:
    // CONSTRUCTOR - With optional IndicatorManager
    SimpleRSI(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1, int period = 14, 
             IndicatorManager* indicatorMgr = NULL)
    {
        m_symbol = symbol;
        m_tf = tf;
        m_period = period;
        m_overbought = 70.0;
        m_oversold = 30.0;
        m_indicatorMgr = indicatorMgr;
        
        DebugLogSimpleRSI("Constructor", 
            StringFormat("Created for %s on TF %d, Period=%d", symbol, tf, period));
    }
    
    // ==================== CORE METHODS ====================
    
    // MAIN FUNCTION: Get bias and confidence
    RSIBias GetBiasAndConfidence(int lookback = 20)
    {
        RSIBias result;
        ZeroMemory(result);
        result.biasText = "NEUTRAL";
        result.rsiLevel = "NEUTRAL";
        result.usingIndicatorManager = false;
        
        double rsiValues[];
        
        // Try to get RSI from IndicatorManager first
        if(m_indicatorMgr != NULL && m_indicatorMgr.IsInitialized())
        {
            result = GetBiasFromIndicatorManager(lookback);
            result.usingIndicatorManager = true;
            
            // If we got valid data, return it
            if(result.confidence > 0 || result.netBias != 0)
                return result;
            
            // Fall through to direct calculation if IndicatorManager failed
            Logger::Log("SimpleRSI", "IndicatorManager failed, falling back to direct RSI");
        }
        
        // DIRECT CALCULATION (fallback)
        result = GetBiasDirect(lookback);
        result.usingIndicatorManager = false;
        
        return result;
    }
    
    // Get RSI Signal
    RSISignal GetSignal(int lookback = 20)
    {
        DebugLogSimpleRSI("GetSignal", "Getting RSI signal");
        
        RSISignal signal;
        RSIBias bias = GetBiasAndConfidence(lookback);
        
        // Determine signal based on bias
        if(bias.netBias > 50 && bias.confidence > 70)
        {
            signal.orderType = ORDER_TYPE_BUY;
            signal.signalSource = "RSI";
            signal.reason = StringFormat("RSI %s (%.0f/%.0f) with %.0f%% confidence", 
                bias.biasText, bias.bullishBias, bias.bearishBias, bias.confidence);
            signal.confidence = bias.confidence;
            signal.netBias = bias.netBias;
            signal.biasText = bias.biasText;
        }
        else if(bias.netBias < -50 && bias.confidence > 70)
        {
            signal.orderType = ORDER_TYPE_SELL;
            signal.signalSource = "RSI";
            signal.reason = StringFormat("RSI %s (%.0f/%.0f) with %.0f%% confidence", 
                bias.biasText, bias.bullishBias, bias.bearishBias, bias.confidence);
            signal.confidence = bias.confidence;
            signal.netBias = bias.netBias;
            signal.biasText = bias.biasText;
        }
        
        DebugLogSimpleRSI("GetSignal", 
            StringFormat("Signal: %s, Confidence: %.1f%%, Bias: %.1f", 
            signal.GetSimpleSignal(), signal.confidence, signal.netBias));
            
        return signal;
    }
    
    // Get RSI Component Display (for UI/display)
    RSIComponentDisplay GetComponentDisplay(int lookback = 15)
    {
        DebugLogSimpleRSI("GetComponentDisplay", "Creating RSIComponentDisplay");
        
        RSIBias bias = GetBiasAndConfidence(lookback);
        
        RSIComponentDisplay display;
        
        // Determine direction based on net bias
        if(bias.netBias > 20) 
            display.direction = "BULLISH";
        else if(bias.netBias < -20) 
            display.direction = "BEARISH";
        else
            display.direction = "NEUTRAL";
        
        // Calculate strength (0-100)
        display.strength = MathAbs(bias.netBias);
        display.confidence = bias.confidence;
        display.isActive = (display.strength > 0);
        
        // Create details string
        display.details = StringFormat("RSI=%.1f, Level=%s", GetCurrentRSI(), bias.rsiLevel);
        
        DebugLogSimpleRSI("GetComponentDisplay", 
            StringFormat("Created: %s", display.ToString()));
        
        return display;
    }
    
    // Get all RSI data in one call
    void GetAllRSIData(RSIBias &bias, RSISignal &signal, RSIComponentDisplay &display, int lookback = 20)
    {
        bias = GetBiasAndConfidence(lookback);
        signal = GetSignal(lookback);
        display = GetComponentDisplay(lookback);
    }
    
    // ==================== QUICK CHECKS ====================
    
    bool IsBullishBias(int lookback = 10)
    {
        RSIBias bias = GetBiasAndConfidence(lookback);
        return (bias.netBias > 20 && bias.confidence > 50);
    }
    
    bool IsBearishBias(int lookback = 10)
    {
        RSIBias bias = GetBiasAndConfidence(lookback);
        return (bias.netBias < -20 && bias.confidence > 50);
    }
    
    double GetNetBiasScore(int lookback = 10)
    {
        RSIBias bias = GetBiasAndConfidence(lookback);
        return bias.netBias;
    }
    
    double GetConfidence(int lookback = 10)
    {
        RSIBias bias = GetBiasAndConfidence(lookback);
        return bias.confidence;
    }
    
    // Get RSI value (uses IndicatorManager if available)
    double GetCurrentRSI()
    {
        // Try IndicatorManager first
        if(m_indicatorMgr != NULL && m_indicatorMgr.IsInitialized())
        {
            double rsi = m_indicatorMgr.GetRSI(m_tf, 0);
            if(rsi > 0 && rsi < 100)
                return rsi;
        }
        
        // Fallback to direct calculation - MQL5 VERSION
        int handle = iRSI(m_symbol, m_tf, m_period, PRICE_CLOSE);
        if(handle == INVALID_HANDLE)
            return 0.0;
            
        double buffer[1];
        int copied = CopyBuffer(handle, 0, 0, 1, buffer);
        IndicatorRelease(handle);
        
        return (copied > 0) ? buffer[0] : 0.0;
    }
    
    // Get RSI values array
    bool GetRSIValues(double &rsiValues[], int count = 20, int startShift = 0)
    {
        ArrayResize(rsiValues, count);
        ArraySetAsSeries(rsiValues, true);
        
        // Try IndicatorManager first
        if(m_indicatorMgr != NULL && m_indicatorMgr.IsInitialized())
        {
            for(int i = 0; i < count; i++)
            {
                rsiValues[i] = m_indicatorMgr.GetRSI(m_tf, i + startShift);
            }
            return true;
        }
        
        // Fallback to direct calculation
        int rsiHandle = iRSI(m_symbol, m_tf, m_period, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
            return false;
            
        int copied = CopyBuffer(rsiHandle, 0, startShift, count, rsiValues);
        IndicatorRelease(rsiHandle);
        
        return (copied == count);
    }
    
    // Set IndicatorManager after construction
    void SetIndicatorManager(IndicatorManager* indicatorMgr)
    {
        m_indicatorMgr = indicatorMgr;
        if(indicatorMgr != NULL)
            Logger::Log("SimpleRSI", "IndicatorManager set successfully");
    }
    
    // Check if using IndicatorManager
    bool IsUsingIndicatorManager() const
    {
        return (m_indicatorMgr != NULL && m_indicatorMgr.IsInitialized());
    }
    
    // Get overbought/oversold levels
    double GetOverboughtLevel() const { return m_overbought; }
    double GetOversoldLevel() const { return m_oversold; }
    
    // Set overbought/oversold levels
    void SetLevels(double overbought, double oversold)
    {
        m_overbought = overbought;
        m_oversold = oversold;
        DebugLogSimpleRSI("SetLevels", 
            StringFormat("Set OB=%.1f, OS=%.1f", overbought, oversold));
    }
    
private:
    RSIBias GetBiasFromIndicatorManager(int lookback)
    {
        RSIBias result;
        ZeroMemory(result);
        
        // Get RSI values from IndicatorManager
        double rsiValues[];
        ArraySetAsSeries(rsiValues, true);
        ArrayResize(rsiValues, lookback);
        
        // Fill array with RSI values from IndicatorManager
        for(int i = 0; i < lookback; i++)
        {
            rsiValues[i] = m_indicatorMgr.GetRSI(m_tf, i);
            
            // Validate RSI value
            if(rsiValues[i] <= 0 || rsiValues[i] >= 100)
            {
                // Invalid value, fall back to direct
                Logger::Log("SimpleRSI", 
                    StringFormat("Invalid RSI from IndicatorManager: %.1f at shift %d", 
                    rsiValues[i], i));
                return result; // Return empty result to trigger fallback
            }
        }
        
        double currentRSI = rsiValues[0];
        
        // Calculate bias using IndicatorManager data
        result.bullishBias = CalculateBullishBias(currentRSI, rsiValues);
        result.bearishBias = CalculateBearishBias(currentRSI, rsiValues);
        result.netBias = result.bullishBias - result.bearishBias;
        result.confidence = CalculateConfidence(rsiValues, lookback);
        result.biasText = GetBiasText(result.netBias);
        result.rsiLevel = GetRSILevel(currentRSI);
        result.currentRSI = currentRSI;  // ADD THIS LINE
        result.usingIndicatorManager = true;  // Also add this
        
        return result;
    }
    
    RSIBias GetBiasDirect(int lookback)
    {
        RSIBias result;
        ZeroMemory(result);
        
        // Direct RSI calculation
        double rsiValues[];
        ArraySetAsSeries(rsiValues, true);
        
        int rsiHandle = iRSI(m_symbol, m_tf, m_period, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            Logger::LogError("SimpleRSI", "Failed to create RSI handle");
            return result;
        }
            
        int copied = CopyBuffer(rsiHandle, 0, 0, lookback, rsiValues);
        IndicatorRelease(rsiHandle);
        
        if(copied < lookback)
        {
            Logger::LogError("SimpleRSI", 
                StringFormat("Failed to copy RSI data: %d/%d", copied, lookback));
            return result;
        }
        
        double currentRSI = rsiValues[0];
        
        // Calculate bias using direct data
        result.bullishBias = CalculateBullishBias(currentRSI, rsiValues);
        result.bearishBias = CalculateBearishBias(currentRSI, rsiValues);
        result.netBias = result.bullishBias - result.bearishBias;
        result.confidence = CalculateConfidence(rsiValues, lookback);
        result.biasText = GetBiasText(result.netBias);
        result.rsiLevel = GetRSILevel(currentRSI);
        result.currentRSI = currentRSI;  // ADD THIS LINE
        result.usingIndicatorManager = false;  // Also add this
        
        return result;
    }
    
    // ==================== SHARED CALCULATION METHODS ====================
    
    double CalculateBullishBias(double currentRSI, const double &rsiValues[])  // ADD [] HERE
    {
        double score = 0.0;
        
        if(currentRSI > 50)
            score += (currentRSI - 50) * 1.0;
        
        if(IsRSIRising(rsiValues, 3))
            score += 30.0;
        else if(IsRSIRising(rsiValues, 5))
            score += 15.0;
        
        if(currentRSI < m_oversold)
            score += 20.0 - ((m_oversold - currentRSI) * 0.5);
        
        return MathMin(100.0, score);
    }
    
    double CalculateBearishBias(double currentRSI, const double &rsiValues[])  // ADD [] HERE
    {
        double score = 0.0;
        
        if(currentRSI < 50)
            score += (50 - currentRSI) * 1.0;
        
        if(IsRSIFalling(rsiValues, 3))
            score += 30.0;
        else if(IsRSIFalling(rsiValues, 5))
            score += 15.0;
        
        if(currentRSI > m_overbought)
            score += 20.0 - ((currentRSI - m_overbought) * 0.5);
        
        return MathMin(100.0, score);
    }
    
    double CalculateConfidence(const double &rsiValues[], int lookback)  // ADD [] HERE
    {
        if(lookback < 5) return 0.0;
        
        double confidence = 0.0;
        double currentRSI = rsiValues[0];
        double distance = MathAbs(currentRSI - 50);
        
        confidence += MathMin(40.0, distance * 0.8);
        
        if(IsRSIInTrend(rsiValues, 5))
            confidence += 30.0;
        else if(IsRSIInTrend(rsiValues, 3))
            confidence += 15.0;
        
        if(currentRSI > m_overbought || currentRSI < m_oversold)
            confidence += 30.0;
        else if(currentRSI > 60 || currentRSI < 40)
            confidence += 15.0;
        
        return MathMin(100.0, confidence);
    }
    
    bool IsRSIRising(const double &rsiValues[], int period)  // ADD [] HERE
    {
        if(ArraySize(rsiValues) <= period) return false;
        return (rsiValues[0] > rsiValues[period]);
    }
    
    bool IsRSIFalling(const double &rsiValues[], int period)  // ADD [] HERE
    {
        if(ArraySize(rsiValues) <= period) return false;
        return (rsiValues[0] < rsiValues[period]);
    }
    
    bool IsRSIInTrend(const double &rsiValues[], int period)  // ADD [] HERE
    {
        if(ArraySize(rsiValues) <= period) return false;
        
        int upCount = 0;
        for(int i = 0; i < period; i++)
        {
            if(rsiValues[i] > 50) upCount++;
        }
        
        return (upCount >= period - 1) || (upCount <= 1);
    }
    
    string GetBiasText(double netBias)
    {
        if(netBias > 60) return "STRONG_BULLISH";
        if(netBias > 20) return "BULLISH";
        if(netBias > 10) return "WEAK_BULLISH";
        if(netBias < -60) return "STRONG_BEARISH";
        if(netBias < -20) return "BEARISH";
        if(netBias < -10) return "WEAK_BEARISH";
        return "NEUTRAL";
    }
    
    string GetRSILevel(double rsi)
    {
        if(rsi > m_overbought) return "OVERBOUGHT";
        if(rsi < m_oversold) return "OVERSOLD";
        if(rsi > 55) return "BULLISH_BIAS";
        if(rsi < 45) return "BEARISH_BIAS";
        return "NEUTRAL";
    }
};

// ==================== ULTRA SIMPLE VERSION (Static) ====================
class UltraSimpleRSI
{
public:
    // Get RSI bias and confidence
    static void GetBias(string symbol, ENUM_TIMEFRAMES tf, 
                       double &biasScore, double &confidence,
                       IndicatorManager* indicatorMgr = NULL)
    {
        biasScore = 0.0;
        confidence = 0.0;
        
        double rsi = 0.0;
        
        // Try IndicatorManager first
        if(indicatorMgr != NULL && indicatorMgr.IsInitialized())
        {
            rsi = indicatorMgr.GetRSI(tf, 0);
        }
        
        // Fallback to direct calculation - MQL5 VERSION
        if(rsi <= 0 || rsi >= 100)
        {
            // MQL5: iRSI() returns a handle, need to use CopyBuffer
            int handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
            if(handle != INVALID_HANDLE)
            {
                double buffer[1];
                int copied = CopyBuffer(handle, 0, 0, 1, buffer);
                if(copied > 0)
                    rsi = buffer[0];
                IndicatorRelease(handle);
            }
        }
        
        // Calculate bias and confidence
        if(rsi > 0 && rsi < 100)
        {
            biasScore = (rsi - 50) * 2.0;
            double distance = MathAbs(rsi - 50);
            confidence = MathMin(100.0, distance * 2.0);
            
            if(rsi > 70 || rsi < 30)
                confidence = 80.0;
        }
    }
    
    // Quick bullish check
    static bool IsBullish(string symbol, ENUM_TIMEFRAMES tf, IndicatorManager* indicatorMgr = NULL)
    {
        double rsi = 0.0;
        double rsiPrev = 0.0;
        
        if(indicatorMgr != NULL && indicatorMgr.IsInitialized())
        {
            rsi = indicatorMgr.GetRSI(tf, 0);
            rsiPrev = indicatorMgr.GetRSI(tf, 1);
            return (rsi > 55 && rsi > rsiPrev);
        }
        
        // MQL5: Get current and previous RSI values
        int handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
        if(handle != INVALID_HANDLE)
        {
            double buffer[2];
            int copied = CopyBuffer(handle, 0, 0, 2, buffer);
            if(copied == 2)
            {
                rsi = buffer[0];
                rsiPrev = buffer[1];
            }
            IndicatorRelease(handle);
        }
        
        return (rsi > 55 && rsi > rsiPrev);
    }
    
    // Quick bearish check
    static bool IsBearish(string symbol, ENUM_TIMEFRAMES tf, IndicatorManager* indicatorMgr = NULL)
    {
        double rsi = 0.0;
        double rsiPrev = 0.0;
        
        if(indicatorMgr != NULL && indicatorMgr.IsInitialized())
        {
            rsi = indicatorMgr.GetRSI(tf, 0);
            rsiPrev = indicatorMgr.GetRSI(tf, 1);
            return (rsi < 45 && rsi < rsiPrev);
        }
        
        // MQL5: Get current and previous RSI values
        int handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
        if(handle != INVALID_HANDLE)
        {
            double buffer[2];
            int copied = CopyBuffer(handle, 0, 0, 2, buffer);
            if(copied == 2)
            {
                rsi = buffer[0];
                rsiPrev = buffer[1];
            }
            IndicatorRelease(handle);
        }
        
        return (rsi < 45 && rsi < rsiPrev);
    }
    
    // Get overbought/oversold status
    static string GetLevel(string symbol, ENUM_TIMEFRAMES tf, IndicatorManager* indicatorMgr = NULL)
    {
        double rsi = 0.0;
        
        if(indicatorMgr != NULL && indicatorMgr.IsInitialized())
        {
            rsi = indicatorMgr.GetRSI(tf, 0);
        }
        else
        {
            // MQL5: Get current RSI value
            int handle = iRSI(symbol, tf, 14, PRICE_CLOSE);
            if(handle != INVALID_HANDLE)
            {
                double buffer[1];
                int copied = CopyBuffer(handle, 0, 0, 1, buffer);
                if(copied > 0)
                    rsi = buffer[0];
                IndicatorRelease(handle);
            }
        }
        
        if(rsi > 70) return "OVERBOUGHT";
        if(rsi < 30) return "OVERSOLD";
        if(rsi > 55) return "BULLISH_BIAS";
        if(rsi < 45) return "BEARISH_BIAS";
        return "NEUTRAL";
    }
};