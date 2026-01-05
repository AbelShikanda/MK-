

enum ENUM_STOP_METHOD {
    STOP_STRUCTURE,     // Market structure
    STOP_ATR,          // ATR volatility
    STOP_FIXED_PIPS,   // Fixed distance
    STOP_BOLLINGER,    // Bollinger Bands
    STOP_DYNAMIC       // Dynamic with multiple indicators
};

enum ENUM_POI_TYPE
{
    POI_SUPPORT,
    POI_RESISTANCE,
    POI_ORDER_BLOCK_BUY,
    POI_ORDER_BLOCK_SELL,
    POI_MAJOR_HIGH,
    POI_MAJOR_LOW
};



enum ENUM_MACD_SIGNAL_TYPE
{
    MACD_SIGNAL_CROSSOVER,
    MACD_SIGNAL_DIVERGENCE,
    MACD_SIGNAL_TREND,
    MACD_SIGNAL_ZERO_LINE,
    MACD_SIGNAL_NONE
};

// POI Enums needed for conversion
enum ENUM_POI_BIAS {
    POI_BIAS_NEUTRAL,
    POI_BIAS_BULLISH,
    POI_BIAS_BEARISH,
    POI_BIAS_CONFLICTED
};