//+------------------------------------------------------------------+
//|                                                      TakeProfit.mqh |
//|                        Pure MQL5 Take Profit Module              |
//|                           Clean & Optimized                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "3.0"
#property strict

#include "../utils/System/sys.mqh"

// ==================== ENUMERATIONS ====================
enum ENUM_TP_TYPE
{
    TP_FIXED_RR,           // Fixed Risk:Reward ratio
    TP_ATR_BASED,          // Based on ATR multiple
    TP_STRUCTURE_BASED,    // Based on market structure
    TP_MA_BASED,           // Based on moving average
    TP_MULTIPLE_TARGETS    // Multiple TP levels
};

// ==================== STRUCTURES ====================
struct STpLevel
{
    double price;
    double percentage;     // % of position to close
    string comment;
    bool isHit;
    datetime hitTime;
};

struct SMetrics
{
    int totalTargets;
    int targetsHit;
    double avgRR;
    double bestRR;
    double efficiency;
    datetime lastUpdate;
};

// ==================== MAIN CLASS ====================
class CTakeProfit
{
private:
    // Configuration
    ENUM_TP_TYPE m_tpType;
    double m_fixedRR;
    double m_atrMultiplier;
    int m_structureLookback;
    int m_maPeriod;
    ENUM_MA_METHOD m_maMethod;
    int m_numTargets;
    string m_targetPercentages;
    
    // Internal state
    bool m_initialized;
    int m_atrHandle;
    int m_maHandle;
    SMetrics m_metrics;
    
    // ========== PRIVATE CORE METHODS ==========
    
    // Fixed Risk:Reward calculation
    double CalculateFixedRR(double entry, double sl, bool isBuy) const
    {
        double risk = MathAbs(entry - sl);
        double tpDistance = risk * m_fixedRR;
        return isBuy ? entry + tpDistance : entry - tpDistance;
    }
    
    // ATR-based calculation
    double CalculateATRBased(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                           double entry, bool isBuy)
    {
        double atrValue = GetATRValue(symbol, timeframe, 14);
        if(atrValue <= 0) return CalculateFixedRR(entry, entry * 0.01, isBuy);
        
        double tpDistance = atrValue * m_atrMultiplier;
        return isBuy ? entry + tpDistance : entry - tpDistance;
    }
    
    // Structure-based calculation (using swing points)
    double CalculateStructureBased(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                                 double entry, bool isBuy)
    {
        double structureLevel = GetNearestSwing(symbol, timeframe, m_structureLookback, !isBuy);
        if(structureLevel <= 0) return CalculateATRBased(symbol, timeframe, entry, isBuy);
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double buffer = point * 10; // 10 pip buffer
        return isBuy ? structureLevel - buffer : structureLevel + buffer;
    }
    
    // MA-based calculation
    double CalculateMABased(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                          double entry, bool isBuy)
    {
        double maValue = GetMAValue(symbol, timeframe, 0);
        if(maValue <= 0) return CalculateFixedRR(entry, entry * 0.01, isBuy);
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double buffer = point * 20; // 20 pip buffer
        return isBuy ? maValue - buffer : maValue + buffer;
    }
    
    // ========== HELPER METHODS ==========
    
    // Find nearest swing point (high or low)
    double GetNearestSwing(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                          int bars, bool findHigh) const
    {
        // Get price data
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        
        if(CopyRates(symbol, timeframe, 0, bars, rates) < bars)
            return 0.0;
        
        // Find swing
        for(int i = 1; i < bars - 1; i++)
        {
            if(findHigh)
            {
                if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
                    return rates[i].high;
            }
            else
            {
                if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
                    return rates[i].low;
            }
        }
        
        return 0.0;
    }
    
    // Get MA value with handle management
    double GetMAValue(const string symbol, const ENUM_TIMEFRAMES timeframe, int shift)
    {
        // Create handle if needed
        if(m_maHandle == INVALID_HANDLE)
            m_maHandle = iMA(symbol, timeframe, m_maPeriod, 0, m_maMethod, PRICE_CLOSE);
        
        if(m_maHandle == INVALID_HANDLE)
            return 0.0;
        
        // Get value
        double values[];
        ArraySetAsSeries(values, true);
        
        if(CopyBuffer(m_maHandle, 0, shift, 1, values) < 1)
            return 0.0;
        
        return values[0];
    }
    
    // Get ATR value with handle management
    double GetATRValue(const string symbol, const ENUM_TIMEFRAMES timeframe, int period)
    {
        // Create handle if needed
        if(m_atrHandle == INVALID_HANDLE)
            m_atrHandle = iATR(symbol, timeframe, period);
        
        if(m_atrHandle == INVALID_HANDLE)
            return 0.0;
        
        // Get value
        double values[];
        ArraySetAsSeries(values, true);
        
        if(CopyBuffer(m_atrHandle, 0, 0, 1, values) < 1)
            return 0.0;
        
        return values[0];
    }
    
    // Release indicator handles
    void ReleaseIndicators()
    {
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        if(m_maHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_maHandle);
            m_maHandle = INVALID_HANDLE;
        }
    }
    
    // Validate TP against basic rules
    bool IsTPValidInternal(double entry, double sl, double tp, bool isBuy, double minRR = 1.0) const
    {
        // Basic validation
        if(entry <= 0 || sl <= 0 || tp <= 0)
            return false;
        
        // Check direction
        if(isBuy && tp <= entry)
            return false;
        if(!isBuy && tp >= entry)
            return false;
        
        // Check risk:reward
        double risk = MathAbs(entry - sl);
        double reward = MathAbs(tp - entry);
        
        if(risk == 0 || reward / risk < minRR)
            return false;
        
        return true;
    }
    
    // Normalize price to symbol precision
    double NormalizePrice(double price, const string symbol) const
    {
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        if(tickSize <= 0)
            return price;
        
        return NormalizeDouble(MathRound(price / tickSize) * tickSize, 
                              (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    }
    
public:
    // ========== CONSTRUCTOR / DESTRUCTOR ==========
    CTakeProfit() : 
        m_tpType(TP_FIXED_RR),
        m_fixedRR(2.0),
        m_atrMultiplier(2.0),
        m_structureLookback(50),
        m_maPeriod(20),
        m_maMethod(MODE_SMA),
        m_numTargets(1),
        m_targetPercentages("100"),
        m_initialized(false),
        m_atrHandle(INVALID_HANDLE),
        m_maHandle(INVALID_HANDLE)
    {
        ResetMetrics();
    }
    
    ~CTakeProfit()
    {
        Cleanup();
    }
    
    // ========== INITIALIZATION ==========
    void OnInit()
    {
        if(!m_initialized)
            Initialize();
    }
    
    void Initialize(ENUM_TP_TYPE tpType = TP_FIXED_RR,
                   double fixedRR = 2.0,
                   double atrMultiplier = 2.0,
                   int structureLookback = 50,
                   int maPeriod = 20,
                   ENUM_MA_METHOD maMethod = MODE_SMA,
                   int numTargets = 1,
                   string targetPercentages = "100")
    {
        // Validate and set parameters
        m_tpType = tpType;
        m_fixedRR = MathMax(0.5, fixedRR);
        m_atrMultiplier = MathMax(0.5, atrMultiplier);
        m_structureLookback = MathMax(10, structureLookback);
        m_maPeriod = MathMax(2, maPeriod);
        m_maMethod = maMethod;
        m_numTargets = MathMax(1, MathMin(numTargets, 5)); // Max 5 targets
        m_targetPercentages = targetPercentages;
        
        // Reset handles
        ReleaseIndicators();
        
        m_initialized = true;
        
        PrintFormat("CTakeProfit initialized: Type=%s, RR=%.1f, Targets=%d",
                   EnumToString(m_tpType), m_fixedRR, m_numTargets);
    }
    
    // ========== MAIN CALCULATION METHODS ==========
    
    // Calculate single TP level
    double CalculateTP(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      double entryPrice,
                      double stopLoss,
                      bool isBuy,
                      double lotSize = 0.01)
    {
        if(!m_initialized)
            Initialize();
        
        // Normalize input prices
        entryPrice = NormalizePrice(entryPrice, symbol);
        stopLoss = NormalizePrice(stopLoss, symbol);
        
        double tp = 0.0;
        
        // Calculate based on selected method
        switch(m_tpType)
        {
            case TP_FIXED_RR:
                tp = CalculateFixedRR(entryPrice, stopLoss, isBuy);
                break;
                
            case TP_ATR_BASED:
                tp = CalculateATRBased(symbol, timeframe, entryPrice, isBuy);
                break;
                
            case TP_STRUCTURE_BASED:
                tp = CalculateStructureBased(symbol, timeframe, entryPrice, isBuy);
                break;
                
            case TP_MA_BASED:
                tp = CalculateMABased(symbol, timeframe, entryPrice, isBuy);
                break;
        }
        
        // Normalize and validate
        tp = NormalizePrice(tp, symbol);
        
        if(!IsTPValidInternal(entryPrice, stopLoss, tp, isBuy, 1.0))
        {
            // Fallback to fixed RR
            tp = CalculateFixedRR(entryPrice, stopLoss, isBuy);
            tp = NormalizePrice(tp, symbol);
        }
        
        // Update metrics
        UpdateMetrics(entryPrice, stopLoss, tp, isBuy);
        
        return tp;
    }
    
    // ========== TARGET MONITORING ==========
    
    // Check if target has been hit
    bool IsTargetHit(const STpLevel &target, double currentPrice, double bufferPoints = 5.0) const
    {
        if(target.isHit)
            return true;
            
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double buffer = point * bufferPoints;
        
        return MathAbs(currentPrice - target.price) <= buffer;
    }
    
    // Update target hit status
    void UpdateTargetStatus(STpLevel &target, double currentPrice)
    {
        if(!target.isHit && IsTargetHit(target, currentPrice))
        {
            target.isHit = true;
            target.hitTime = TimeCurrent();
            m_metrics.targetsHit++;
            
            PrintFormat("Target hit: %s at %s", 
                       target.comment, TimeToString(target.hitTime));
        }
    }
    
    // ========== UTILITY METHODS ==========
    
    // Calculate Risk:Reward ratio
    static double CalculateRR(double entry, double sl, double tp, bool isBuy)
    {
        double risk = MathAbs(entry - sl);
        double reward = MathAbs(tp - entry);
        
        return (risk > 0) ? reward / risk : 0.0;
    }
    
    // Adjust TP for current volatility
    double AdjustForVolatility(const string symbol, const ENUM_TIMEFRAMES timeframe,
                              double tp, bool isBuy)
    {
        double atr = GetATRValue(symbol, timeframe, 14);
        if(atr <= 0)
            return tp;
            
        double currentPrice = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
                                    : SymbolInfoDouble(symbol, SYMBOL_BID);
                                    
        double distance = MathAbs(tp - currentPrice);
        double volatilityFactor = MathMin(atr / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 100), 2.0);
        
        double adjustedDistance = distance * volatilityFactor;
        
        return isBuy ? currentPrice + adjustedDistance : currentPrice - adjustedDistance;
    }
    
    // ========== EVENT HANDLERS ==========
    
    // Called on each tick
    void OnTick()
    {
        // Update timestamp
        m_metrics.lastUpdate = TimeCurrent();
    }
    
    // Called on trade transaction
    void OnTradeTransaction(const MqlTradeTransaction &trans)
    {
        // Optional: Update metrics based on trades
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
            // Could track performance here
        }
    }
    
    // ========== CLEANUP ==========
    
    void Cleanup()
    {
        ReleaseIndicators();
        m_initialized = false;
        Print("CTakeProfit: Cleanup completed");
    }
    
    // ========== GETTERS ==========
    
    SMetrics GetMetrics() const { return m_metrics; }
    bool IsInitialized() const { return m_initialized; }
    ENUM_TP_TYPE GetTPType() const { return m_tpType; }
    double GetFixedRR() const { return m_fixedRR; }
    
    // ========== SETTERS ==========
    
    void SetTPType(ENUM_TP_TYPE type) 
    { 
        m_tpType = type; 
        PrintFormat("TP type changed to: %s", EnumToString(type));
    }
    
    void SetFixedRR(double rr) 
    { 
        m_fixedRR = MathMax(0.5, rr); 
        PrintFormat("Fixed RR changed to: %.1f", m_fixedRR);
    }
    
    void SetNumTargets(int num) 
    { 
        m_numTargets = MathMax(1, MathMin(num, 5));
        PrintFormat("Number of targets changed to: %d", m_numTargets);
    }
    
private:
    // ========== METRICS MANAGEMENT ==========
    
    void ResetMetrics()
    {
        m_metrics.totalTargets = 0;
        m_metrics.targetsHit = 0;
        m_metrics.avgRR = 0.0;
        m_metrics.bestRR = 0.0;
        m_metrics.efficiency = 0.0;
        m_metrics.lastUpdate = TimeCurrent();
    }
    
    void UpdateMetrics(double entry, double sl, double tp, bool isBuy)
    {
        m_metrics.totalTargets++;
        
        double rr = CalculateRR(entry, sl, tp, isBuy);
        m_metrics.avgRR = (m_metrics.avgRR * (m_metrics.totalTargets - 1) + rr) / m_metrics.totalTargets;
        
        if(rr > m_metrics.bestRR)
            m_metrics.bestRR = rr;
    }
};

// ==================== EXTERNAL UTILITY FUNCTIONS ====================
// Static functions that can be used without creating class instance

namespace TakeProfitUtils
{
    // Validate TP (basic checks)
    bool IsValidTP(double entry, double sl, double tp, bool isBuy, double minRR = 1.0)
    {
        if(entry <= 0 || sl <= 0 || tp <= 0)
            return false;
        
        // Direction check
        if(isBuy && tp <= entry) return false;
        if(!isBuy && tp >= entry) return false;
        
        // SL check
        if(isBuy && tp <= sl) return false;
        if(!isBuy && tp >= sl) return false;
        
        // Risk:Reward check
        double risk = MathAbs(entry - sl);
        double reward = MathAbs(tp - entry);
        
        return (risk > 0) && (reward / risk >= minRR);
    }
    
    // Calculate partial TP level
    double CalculatePartialTP(double entry, double sl, double tp, 
                            double closePercent, bool isBuy)
    {
        double fullDistance = MathAbs(tp - entry);
        double partialDistance = fullDistance * (closePercent / 100.0);
        
        return isBuy ? entry + partialDistance : entry - partialDistance;
    }
    
    // Calculate breakeven level
    double CalculateBreakeven(double entry, double tp, double lockPercent = 50.0)
    {
        double profit = MathAbs(tp - entry);
        double lockAmount = profit * (lockPercent / 100.0);
        
        return (tp > entry) ? entry + lockAmount : entry - lockAmount;
    }
    
    // Calculate distance in points
    double DistanceInPoints(const string symbol, double price1, double price2)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        return (point > 0) ? MathAbs(price1 - price2) / point : 0;
    }
    
    // Adjust TP for spread
    double AdjustForSpread(const string symbol, double tp, bool isBuy)
    {
        double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
        double adjustment = spread * 0.5;
        
        double adjusted = isBuy ? tp - adjustment : tp + adjustment;
        
        // Normalize
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        if(tickSize > 0)
        {
            adjusted = NormalizeDouble(MathRound(adjusted / tickSize) * tickSize,
                                      (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
        }
        
        return adjusted;
    }
}

// ==================== SIMPLE USAGE EXAMPLE ====================
/*
// How to use in your EA:

#include "TakeProfit.mqh"

CTakeProfit g_tpManager;

int OnInit()
{
    // Initialize with your preferred settings
    g_tpManager.Initialize(
        TP_ATR_BASED,      // Use ATR-based TP
        2.5,              // Base RR ratio
        2.0,              // ATR multiplier
        100,              // Structure lookback
        20,               // MA period
        MODE_SMA,         // MA method
        1,                // Single target
        "100"             // Close 100% at target
    );
    
    return INIT_SUCCEEDED;
}

void OnTick()
{
    g_tpManager.OnTick();  // Update internal state
    
    // When you have a trade signal:
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = entry - 50 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    bool isBuy = true;
    
    // Calculate TP
    double tp = g_tpManager.CalculateTP(_Symbol, PERIOD_CURRENT, entry, sl, isBuy, 0.01);
    
    // Validate
    if(TakeProfitUtils::IsValidTP(entry, sl, tp, isBuy, 1.5))
    {
        // Place your trade with this TP
        PrintFormat("Trade Entry: %.5f, SL: %.5f, TP: %.5f", entry, sl, tp);
        PrintFormat("Risk:Reward: %.2f:1", CTakeProfit::CalculateRR(entry, sl, tp, isBuy));
    }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                       const MqlTradeRequest &request,
                       const MqlTradeResult &result)
{
    g_tpManager.OnTradeTransaction(trans);
}

void OnDeinit(const int reason)
{
    g_tpManager.Cleanup();
}
*/

//+------------------------------------------------------------------+
//|                     END OF TAKE PROFIT MODULE                    |
//+------------------------------------------------------------------+