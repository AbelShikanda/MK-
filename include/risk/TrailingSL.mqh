//+------------------------------------------------------------------+
//|                                                   TrailingSL.mqh |
//|                                        Minimal Trailing Stop System |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

// ================= INCLUDES =================
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Indicators/Indicator.mqh>
#include <Arrays/ArrayDouble.mqh>

// ================= ENUMS =================
enum ENUM_TRAIL_METHOD {
    TRAIL_FIXED_PIPS,
    TRAIL_ATR_MULTIPLE,
    TRAIL_MA,
    TRAIL_HIGH_LOW,
    TRAIL_PARABOLIC_SAR
};

enum ENUM_TRAIL_ACTIVATION {
    ACTIVATION_IMMEDIATE,      // Start trailing immediately
    ACTIVATION_ATR_MULTIPLE,   // Start after X× ATR profit
    ACTIVATION_FIXED_PIPS      // Start after fixed pips profit
};

// ================= STRUCTURES =================
struct TrailConfig {
    ENUM_TRAIL_METHOD method;
    double distance;          // Pips or ATR multiple
    double activation;        // Activation profit in pips
    int ma_period;           // For MA method
    ENUM_MA_METHOD ma_method;
    ENUM_APPLIED_PRICE ma_price;
    int high_low_bars;       // Bars for High/Low method
    bool use_buffer;         // Add extra buffer
    double buffer_pips;      // Buffer in pips
    bool use_percentage_buffer; // Add percentage of profit
    double percentage_buffer;    // Percentage value (0.10 = 10%)
};

// ================= CLASS DEFINITION =================
class TrailingStopManager
{
private:
    CTrade *m_trade;
    CPositionInfo m_position;
    TrailConfig m_config;
    int m_atr_handle;
    int m_ma_handle;
    int m_sar_handle;
    
public:
    // ================= CONSTRUCTOR/DESTRUCTOR =================
    TrailingStopManager()
    {
        m_trade = new CTrade();
        m_atr_handle = INVALID_HANDLE;
        m_ma_handle = INVALID_HANDLE;
        m_sar_handle = INVALID_HANDLE;
    }
    
    ~TrailingStopManager()
    {
        delete m_trade;
        if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
        if(m_ma_handle != INVALID_HANDLE) IndicatorRelease(m_ma_handle);
        if(m_sar_handle != INVALID_HANDLE) IndicatorRelease(m_sar_handle);
    }
    
    // ================= INITIALIZE =================
    void Initialize(const TrailConfig &config)
    {
        m_config = config;
        
        // Create indicator handles if needed
        if(config.method == TRAIL_ATR_MULTIPLE || config.method == TRAIL_PARABOLIC_SAR)
        {
            m_atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
        }
        
        if(config.method == TRAIL_MA)
        {
            m_ma_handle = iMA(_Symbol, PERIOD_CURRENT, config.ma_period, 0, 
                            config.ma_method, config.ma_price);
        }
        
        if(config.method == TRAIL_PARABOLIC_SAR)
        {
            m_sar_handle = iSAR(_Symbol, PERIOD_CURRENT, 0.02, 0.2);
        }
    }
    
    // ================= ONTICK =================
    void OnTick()
    {
        UpdateAllTrails();
    }
    
    // ================= MAIN PUBLIC INTERFACE =================
    
    // Update all positions with trailing stop
    void UpdateAllTrails()
    {
        int total = PositionsTotal();
        for(int i = total-1; i >= 0; i--)
        {
            if(m_position.SelectByIndex(i))
            {
                ulong ticket = m_position.Ticket();
                UpdateTrail(ticket);
            }
        }
    }
    
    // Update trailing stop for a specific position
    bool UpdateTrail(ulong ticket)
    {
        if(!m_position.SelectByTicket(ticket))
            return false;
            
        string symbol = m_position.Symbol();
        ENUM_POSITION_TYPE type = m_position.PositionType();
        double current_price = GetCurrentPrice(symbol, type);
        double entry_price = m_position.PriceOpen();
        double stop_loss = m_position.StopLoss();
        double take_profit = m_position.TakeProfit();
        
        // Check if we should activate trailing
        if(!ShouldActivate(symbol, entry_price, current_price, type))
            return false;
            
        // Calculate new stop loss
        double new_stop = CalculateTrailStop(symbol, type, current_price, entry_price);
        
        // Apply buffers if enabled
        new_stop = ApplyBuffers(symbol, type, new_stop, current_price, entry_price);
        
        // Validate new stop level
        if(!IsValidStopLevel(symbol, type, new_stop, current_price))
        {
            Print("Invalid stop level calculated: ", new_stop);
            return false;
        }
        
        // Only move stop if it's in our favor
        if((type == POSITION_TYPE_BUY && new_stop > stop_loss) ||
           (type == POSITION_TYPE_SELL && new_stop < stop_loss))
        {
            // Preserve take profit
            if(take_profit == 0)
            {
                // If no TP, modify only SL
                return m_trade.PositionModify(ticket, new_stop, 0);
            }
            else
            {
                return m_trade.PositionModify(ticket, new_stop, take_profit);
            }
        }
        
        return false;
    }
    
private:
    // ================= PRICE FUNCTIONS =================
    double GetCurrentPrice(string symbol, ENUM_POSITION_TYPE type) const
    {
        if(type == POSITION_TYPE_BUY)
            return SymbolInfoDouble(symbol, SYMBOL_BID);
        else
            return SymbolInfoDouble(symbol, SYMBOL_ASK);
    }
    
    // ================= ACTIVATION CHECK =================
    bool ShouldActivate(string symbol, double entry, double current, ENUM_POSITION_TYPE type) const
    {
        if(m_config.activation <= 0)
            return true;  // Immediate activation
            
        double profit = 0;
        if(type == POSITION_TYPE_BUY)
            profit = current - entry;
        else
            profit = entry - current;
            
        if(profit <= 0)
            return false;  // Not in profit
            
        double profit_pips = profit / SymbolInfoDouble(symbol, SYMBOL_POINT);
        return profit_pips >= m_config.activation;
    }
    
    // ================= TRAIL CALCULATIONS =================
    double CalculateTrailStop(string symbol, ENUM_POSITION_TYPE type, 
                              double current_price, double entry_price)
    {
        switch(m_config.method)
        {
            case TRAIL_FIXED_PIPS:
                return CalculateFixedPips(symbol, type, current_price);
                
            case TRAIL_ATR_MULTIPLE:
                return CalculateATRTrail(symbol, type, current_price);
                
            case TRAIL_MA:
                return CalculateMATrail(symbol, type);
                
            case TRAIL_HIGH_LOW:
                return CalculateHighLowTrail(symbol, type);
                
            case TRAIL_PARABOLIC_SAR:
                return CalculateParabolicSAR(symbol, type);
        }
        
        return 0.0;
    }
    
    double CalculateFixedPips(string symbol, ENUM_POSITION_TYPE type, double current_price)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double pip_distance = m_config.distance * point;
        
        if(type == POSITION_TYPE_BUY)
            return current_price - pip_distance;
        else
            return current_price + pip_distance;
    }
    
    double CalculateATRTrail(string symbol, ENUM_POSITION_TYPE type, double current_price)
    {
        double atr[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr) <= 0)
        {
            // Fallback to iATR if handle fails
            atr[0] = iATR(symbol, PERIOD_CURRENT, 14);
        }
        
        double trail_distance = atr[0] * m_config.distance;
        
        if(type == POSITION_TYPE_BUY)
            return current_price - trail_distance;
        else
            return current_price + trail_distance;
    }
    
    double CalculateMATrail(string symbol, ENUM_POSITION_TYPE type)
    {
        double ma[1];
        if(CopyBuffer(m_ma_handle, 0, 0, 1, ma) <= 0)
        {
            // Fallback to iMA if handle fails
            ma[0] = iMA(symbol, PERIOD_CURRENT, m_config.ma_period, 0, 
                       m_config.ma_method, m_config.ma_price);
        }
        
        return ma[0];
    }
    
    double CalculateHighLowTrail(string symbol, ENUM_POSITION_TYPE type)
    {
        int bars = m_config.high_low_bars > 0 ? m_config.high_low_bars : 20;
        
        if(type == POSITION_TYPE_BUY)
        {
            // For buys, trail at the lowest low
            double lows[];
            ArraySetAsSeries(lows, true);
            CopyLow(symbol, PERIOD_CURRENT, 0, bars, lows);
            return lows[ArrayMinimum(lows)];
        }
        else
        {
            // For sells, trail at the highest high
            double highs[];
            ArraySetAsSeries(highs, true);
            CopyHigh(symbol, PERIOD_CURRENT, 0, bars, highs);
            return highs[ArrayMaximum(highs)];
        }
    }
    
    double CalculateParabolicSAR(string symbol, ENUM_POSITION_TYPE type)
    {
        double sar[1];
        if(CopyBuffer(m_sar_handle, 0, 0, 1, sar) <= 0)
        {
            sar[0] = iSAR(symbol, PERIOD_CURRENT, 0.02, 0.2);
        }
        
        // Add buffer to SAR
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double buffer = 10 * point;  // 10 pip buffer from SAR
        
        if(type == POSITION_TYPE_BUY)
            return sar[0] - buffer;
        else
            return sar[0] + buffer;
    }
    
    // ================= BUFFER APPLICATIONS =================
    double ApplyBuffers(string symbol, ENUM_POSITION_TYPE type, double base_stop,
                        double current_price, double entry_price)
    {
        double stop = base_stop;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // Add fixed buffer
        if(m_config.use_buffer && m_config.buffer_pips > 0)
        {
            double buffer = m_config.buffer_pips * point;
            if(type == POSITION_TYPE_BUY)
                stop -= buffer;  // Lower for buys
            else
                stop += buffer;  // Higher for sells
        }
        
        // Add percentage of profit buffer
        if(m_config.use_percentage_buffer && m_config.percentage_buffer > 0)
        {
            double profit = (type == POSITION_TYPE_BUY) ? 
                           (current_price - entry_price) : 
                           (entry_price - current_price);
            
            if(profit > 0)
            {
                double extra_buffer = profit * m_config.percentage_buffer;
                if(type == POSITION_TYPE_BUY)
                    stop -= extra_buffer;
                else
                    stop += extra_buffer;
            }
        }
        
        return stop;
    }
    
    // ================= VALIDATION =================
    bool IsValidStopLevel(string symbol, ENUM_POSITION_TYPE type, 
                         double stop, double current_price) const
    {
        if(stop <= 0) return false;
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double min_stop_distance = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
        
        if(type == POSITION_TYPE_BUY)
        {
            double max_stop = current_price - min_stop_distance;
            return stop < max_stop;
        }
        else
        {
            double min_stop = current_price + min_stop_distance;
            return stop > min_stop;
        }
    }
};

// ================= EXTERNAL INTERFACE FUNCTIONS =================
TrailingStopManager g_TrailingManager;

void TrailingSL_Initialize(const TrailConfig &config)
{
    g_TrailingManager.Initialize(config);
}

void TrailingSL_OnTick()
{
    g_TrailingManager.OnTick();
}

bool TrailingSL_UpdatePosition(ulong ticket)
{
    return g_TrailingManager.UpdateTrail(ticket);
}

// ================= SELF-CONTAINED CONFIGURATION PRESETS =================
// Add these functions for easy self-contained usage

// Get default configuration
TrailConfig GetDefaultTrailingConfig()
{
    TrailConfig config;
    
    // Sensible defaults
    config.method = TRAIL_FIXED_PIPS;
    config.distance = 50.0;          // 50 pips
    config.activation = 20.0;        // 20 pips profit before trailing
    config.ma_period = 20;
    config.ma_method = MODE_SMA;
    config.ma_price = PRICE_CLOSE;
    config.high_low_bars = 20;
    config.use_buffer = false;
    config.buffer_pips = 5.0;
    config.use_percentage_buffer = false;
    config.percentage_buffer = 0.10;
    
    return config;
}

// Get configuration for scalping (tight stops)
TrailConfig GetScalpingTrailingConfig()
{
    TrailConfig config = GetDefaultTrailingConfig();
    config.method = TRAIL_FIXED_PIPS;
    config.distance = 20.0;      // Tight 20 pip stops
    config.activation = 10.0;    // Start trailing at 10 pips profit
    return config;
}

// Get configuration for swing trading (medium stops)
TrailConfig GetSwingTrailingConfig()
{
    TrailConfig config = GetDefaultTrailingConfig();
    config.method = TRAIL_ATR_MULTIPLE;
    config.distance = 1.5;       // 1.5× ATR distance
    config.activation = 30.0;    // Wait for 30 pips profit
    return config;
}

// Get configuration for trend following (loose stops)
TrailConfig GetTrendTrailingConfig()
{
    TrailConfig config = GetDefaultTrailingConfig();
    config.method = TRAIL_HIGH_LOW;
    config.distance = 80.0;      // 80 pips as fallback
    config.activation = 50.0;    // Wait for 50 pips profit
    config.high_low_bars = 50;   // Look at more bars
    return config;
}

// Get configuration for volatility-based stops
TrailConfig GetVolatilityTrailingConfig()
{
    TrailConfig config = GetDefaultTrailingConfig();
    config.method = TRAIL_ATR_MULTIPLE;
    config.distance = 2.0;       // 2× ATR for volatile markets
    config.activation = 25.0;    // 25 pips activation
    return config;
}

// Quick initialization with defaults
void InitializeDefaultTrailing()
{
    TrailConfig config = GetDefaultTrailingConfig();
    TrailingSL_Initialize(config);
}

// Quick initialization for specific trading style
void InitializeTrailingForStyle(string style = "swing")
{
    TrailConfig config;
    
    if(style == "scalping" || style == "scalp")
        config = GetScalpingTrailingConfig();
    else if(style == "trend" || style == "trending")
        config = GetTrendTrailingConfig();
    else if(style == "volatility" || style == "volatile")
        config = GetVolatilityTrailingConfig();
    else // Default to swing
        config = GetSwingTrailingConfig();
    
    TrailingSL_Initialize(config);
}

// Simple initialization with just the key parameters
void InitializeSimpleTrailing(ENUM_TRAIL_METHOD method = TRAIL_FIXED_PIPS,
                              double distance = 50.0,
                              double activation = 20.0)
{
    TrailConfig config = GetDefaultTrailingConfig();
    config.method = method;
    config.distance = distance;
    config.activation = activation;
    TrailingSL_Initialize(config);
}

// ================= SYMBOL-SPECIFIC PRESETS =================

// Get configuration based on symbol characteristics
TrailConfig GetTrailingConfigForSymbol(string symbol)
{
    TrailConfig config = GetDefaultTrailingConfig();
    
    // Check if symbol is Gold/XAU
    if(StringFind(symbol, "XAU") >= 0 || 
       StringFind(symbol, "GOLD") >= 0 || 
       StringFind(symbol, "XAUTRY") >= 0)
    {
        // Gold is more volatile, use wider stops
        config.method = TRAIL_ATR_MULTIPLE;
        config.distance = 2.5;       // Wider for gold volatility
        config.activation = 150.0;   // Gold moves in bigger increments (pips in gold are larger!)
        config.use_buffer = true;
        config.buffer_pips = 30.0;   // Extra buffer for gold
        return config;
    }
    
    // Check if symbol is a major forex pair
    string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD"};
    for(int i = 0; i < ArraySize(majors); i++)
    {
        if(symbol == majors[i])
        {
            // Major pairs - medium settings
            config.method = TRAIL_ATR_MULTIPLE;
            config.distance = 1.8;
            config.activation = 25.0;
            return config;
        }
    }
    
    // Check if symbol is a cross pair (no USD)
    if(StringFind(symbol, "USD") < 0 && StringLen(symbol) == 6)
    {
        // Cross pairs can be more volatile
        config.method = TRAIL_ATR_MULTIPLE;
        config.distance = 2.0;
        config.activation = 30.0;
        config.use_buffer = true;
        config.buffer_pips = 10.0;
        return config;
    }
    
    // Check if symbol is a crypto
    if(StringFind(symbol, "BTC") >= 0 || 
       StringFind(symbol, "ETH") >= 0 ||
       StringFind(symbol, "XRP") >= 0)
    {
        // Crypto is VERY volatile - extremely wide stops
        config.method = TRAIL_ATR_MULTIPLE;
        config.distance = 3.0;       // Very wide
        config.activation = 200.0;   // Crypto moves 100s of pips quickly
        config.use_buffer = true;
        config.buffer_pips = 50.0;   // Large buffer
        return config;
    }
    
    // Check if symbol is an index
    if(StringFind(symbol, "US30") >= 0 || 
       StringFind(symbol, "NAS100") >= 0 ||
       StringFind(symbol, "SPX500") >= 0 ||
       StringFind(symbol, "DJI") >= 0)
    {
        // Indices - use High/Low method
        config.method = TRAIL_HIGH_LOW;
        config.distance = 100.0;     // Fallback distance
        config.activation = 50.0;
        config.high_low_bars = 30;   // Look at more bars for indices
        return config;
    }
    
    // Default for unknown symbols
    return GetSwingTrailingConfig();
}

// Initialize trailing for specific symbol
void InitializeTrailingForSymbol(string symbol)
{
    TrailConfig config = GetTrailingConfigForSymbol(symbol);
    TrailingSL_Initialize(config);
    
    // Optional: Print what we're using
    Print("Trailing initialized for ", symbol, 
          ": Method=", EnumToString(config.method), 
          ", Distance=", config.distance, 
          ", Activation=", config.activation, " pips");
}

// Initialize trailing for current chart symbol
void InitializeTrailingForCurrentSymbol()
{
    InitializeTrailingForSymbol(_Symbol);
}