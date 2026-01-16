

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

// ================= ENUMS =================
// enum DECISION_ACTION
// {
//     ACTION_NONE,
//     ACTION_OPEN_BUY,
//     ACTION_OPEN_SELL,
//     ACTION_CLOSE_BUY,
//     ACTION_CLOSE_SELL,
//     ACTION_CLOSE_ALL,
//     ACTION_HOLD,
//     ACTION_WAITING_FOR_PACKAGE
// };

// enum POSITION_STATE
// {
//     STATE_NO_POSITION,
//     STATE_HAS_BUY,
//     STATE_HAS_SELL,
//     STATE_HAS_BOTH
// };

//+------------------------------------------------------------------+
//| Market State Enumerations                                        |
//+------------------------------------------------------------------+
enum ENUM_ROOT_REGIME
  {
   REGIME_TRENDING,
   REGIME_RANGING,
   REGIME_UNKNOWN
  };

enum ENUM_MARKET_STATE
  {
   STATE_RANGING_LOW_VOL,     // 1 - Low volatility range
   STATE_RANGING_HIGH_VOL,    // 2 - High volatility range
   STATE_TRENDING_LOW_VOL,    // 3 - Healthy trend, low vol
   STATE_TRENDING_HIGH_VOL,   // 4 - Parabolic/exhaustion trend
   STATE_CONTRACTION,         // 5 - Squeeze/compression
   STATE_EXPANSION,           // 6 - Breakout/expansion
   STATE_CHURN,               // 7 - Exhaustion/distribution
   STATE_UNKNOWN
  };

enum ENUM_POSITION_SIZE
  {
   SIZE_ZERO,
   SIZE_VERY_SMALL,
   SIZE_SMALL,
   SIZE_MEDIUM,
   SIZE_LARGE
  };