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

// +------------------------------------------------------------------+
// | 1. M15 TREND STRENGTH (Your existing code)                      |
// +------------------------------------------------------------------+
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


//+------------------------------------------------------------------+
// Risk level enumeration (if not already defined elsewhere)   |
//+------------------------------------------------------------------+

// enum ENUM_RISK_LEVEL
// {
//     RISK_CRITICAL,     // Stop all trading
//     RISK_HIGH,         // Reduce position sizes
//     RISK_MODERATE,     // Normal trading
//     RISK_LOW,          // Can increase exposure
//     RISK_OPTIMAL       // Best conditions
// };



// enum ENUM_ASSET_CLASS
// {
//     ASSET_FOREX_MAJOR,      // Major forex pairs
//     ASSET_FOREX_MINOR,      // Minor forex pairs
//     ASSET_FOREX_EXOTIC,     // Exotic forex pairs
//     ASSET_METAL,            // Precious metals
//     ASSET_ENERGY,           // Energy commodities
//     ASSET_INDEX,            // Stock indices
//     ASSET_CRYPTO            // Cryptocurrencies
// };

enum ENUM_ACCOUNT_HEALTH
{
    HEALTH_CRITICAL,
    HEALTH_WARNING,
    HEALTH_GOOD,
    HEALTH_EXCELLENT
};



// ============ TRADING ENUMS ============
// enum ENUM_TRADE_SIGNAL_TYPE
// {
//     SIGNAL_NONE = 0,
//     SIGNAL_ULTRA_BUY,
//     SIGNAL_ULTRA_SELL,
//     SIGNAL_STRONG_BUY,
//     SIGNAL_STRONG_SELL,
//     SIGNAL_WEAK_BUY,
//     SIGNAL_WEAK_SELL
// };

enum ENUM_TRADE_ACTION
{
    TRADE_ACTION_NONE,
    TRADE_ACTION_ENTER_BUY,
    TRADE_ACTION_ENTER_SELL,
    TRADE_ACTION_EXIT,
    TRADE_ACTION_REVERSE,
    TRADE_ACTION_ADD,
    TRADE_ACTION_REDUCE,
    TRADE_ACTION_HOLD
};

// ============ SYMBOL ENUMS ============
enum ENUM_SYMBOL_STATUS
{
    SYMBOL_DISABLED = 0,
    SYMBOL_ENABLED,
    SYMBOL_SUSPENDED,
    SYMBOL_WATCH_ONLY,
    SYMBOL_ERROR
};

enum ENUM_ASSET_CLASS
{
    ASSET_FOREX = 0,
    ASSET_METALS,
    ASSET_INDICES,
    ASSET_COMMODITIES,
    ASSET_CRYPTO,
    ASSET_STOCKS,
    ASSET_BONDS
};

// ============ RISK ENUMS ============
enum ENUM_RISK_LEVEL
{
    RISK_CRITICAL = 0,    // Stop trading
    RISK_HIGH = 1,        // Reduce position sizes
    RISK_MODERATE = 2,    // Normal trading
    RISK_LOW = 3,         // Can increase sizes
    RISK_OPTIMAL = 4      // Aggressive trading
};

enum ENUM_DIVERGENCE_TYPE
{
    DIVERGENCE_NONE = 0,
    DIVERGENCE_REGULAR_BULLISH,
    DIVERGENCE_REGULAR_BEARISH,
    DIVERGENCE_HIDDEN_BULLISH,
    DIVERGENCE_HIDDEN_BEARISH
};

enum ENUM_MARKET_PHASE
{
    PHASE_ACCUMULATION,
    PHASE_MARKUP,
    PHASE_DISTRIBUTION,
    PHASE_MARKDOWN,
    PHASE_RANGE
};


enum ENUM_POSITION_SIZING_METHOD
{
    PS_FIXED_FRACTIONAL,
    PS_KELLY,
    PS_FIXED_LOTS,
    PS_VOLATILITY_ADJUSTED
};


// ================= COMPONENT RANKING =================
enum COMPONENT_RANK {
    RANK_MARKET_STRUCTURE = 1,
    RANK_MTF_CONFIRMATION = 2,
    RANK_LIQUIDITY = 3,
    RANK_PATTERN_RECOGNITION = 4,
    RANK_MOMENTUM = 5,
    RANK_MARKET_CONTEXT = 6,
    RANK_RISK_REWARD = 7,
    RANK_CONFLUENCE_DENSITY = 8,
    RANK_ADVANCED_CONCEPTS = 9,
    RANK_FINANCE = 10,
    RANK_TRADE_MANAGER = 11
};



// ================= BASE WEIGHTS (Total = 100%) =================
enum COMPONENT_WEIGHT {
    WEIGHT_MARKET_STRUCTURE = 15,
    WEIGHT_MTF_ENGINE = 12,
    WEIGHT_LIQUID = 10,
    WEIGHT_PATTERN_RECOGNITION = 9,
    WEIGHT_MOMENTUM = 8,
    WEIGHT_MARKET_CONTEXT = 8,
    WEIGHT_RISK_REWARD = 10,
    WEIGHT_CONFLUENCE_DENSITY = 8,
    WEIGHT_ADVANCED_CONCEPTS = 7,
    WEIGHT_FINANCE = 7,
    WEIGHT_TRADE_MANAGER = 6
};



//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_STOP_METHOD
{
   STOP_STRUCTURE = 0,    // Based on swing points
   STOP_ATR,              // Based on Average True Range
   STOP_MA,               // Based on Moving Average
   STOP_BB,               // Based on Bollinger Bands
   STOP_FIXED             // Fixed distance in pips
};


enum POSITION_STATE {
    STATE_NO_POSITION,
    STATE_HAS_BUY,
    STATE_HAS_SELL,
    STATE_HAS_BOTH
};