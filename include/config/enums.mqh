// enums.mqh - Shared enumerations
enum EXPOSURE_METHOD {
    EXPOSURE_MARGIN_BASED,      // Based on margin requirement
    EXPOSURE_RISK_BASED,        // Based on stop loss risk
    EXPOSURE_NOTIONAL_BASED     // Based on position notional value
};

//POI validation
enum ENUM_POI_VALIDATION_METHOD {
    POI_MARGIN_BASED = 0,      // Based on margin requirement
    POI_RISK_BASED = 1,        // Based on stop loss risk  
    POI_NOTIONAL_BASED = 2     // Based on position notional value
};

//+------------------------------------------------------------------+
//| 1. M15 TREND STRENGTH (Your existing code)                      |
//+------------------------------------------------------------------+
enum ENUM_TREND_STRENGTH {
    TREND_STRONG_BULLISH,
    TREND_MODERATE_BULLISH,
    TREND_WEAK_BULLISH,
    TREND_NEUTRAL,
    TREND_WEAK_BEARISH,
    TREND_MODERATE_BEARISH,
    TREND_STRONG_BEARISH
};

//+------------------------------------------------------------------+
//| Exit Signals for Position Management                            |
//+------------------------------------------------------------------+

enum ENUM_EXIT_SIGNAL {
    EXIT_NONE,              // No exit signal
    EXIT_PARTIAL_PROFIT,    // Take partial profits (25-50%)
    EXIT_FULL_PROFIT,       // Take full profits
    EXIT_REVERSE_SIGNAL,    // Opposite signal detected
    EXIT_STOP_LOSS,         // Stop loss hit (handled automatically)
    EXIT_RSI_EXTREME,       // RSI reached overbought/oversold
    EXIT_RSI_AGAINST_TREND, // RSI at 50 moving against trend
    EXIT_TRAILING_STOP      // Trailing stop activated
};

//+------------------------------------------------------------------+
//| Trade Bias Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_TRADE_BIAS
{
    BIAS_NEUTRAL,      // No bias - allow both buy and sell
    BIAS_BUY_ONLY,     // Only allow buy trades
    BIAS_SELL_ONLY,    // Only allow sell trades
    BIAS_BUY_STRONG,   // Strong buy bias
    BIAS_SELL_STRONG,  // Strong sell bias
    BIAS_BUY_WEAK,     // Weak buy bias  
    BIAS_SELL_WEAK     // Weak sell bias
};