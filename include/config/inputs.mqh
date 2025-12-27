#include "enums.mqh"
//------------------ PROGRESSIVE ACCOUNT SCALING --------------------
input group "=== PROGRESSIVE SYMBOL SCALING ==="
input double BalanceForSecondSymbol  = 500.0;
input double BalanceForThirdSymbol   = 1000.0;
input double BalanceForFourthSymbol  = 2000.0;

//------------------ SYMBOL CONFIGURATION ---------------------------
input group "=== SYMBOL CONFIGURATION ==="
input string AvailableSymbols = "XAUUSD,XAGUSD,XPTUSD,COPPER,GBPUSD,USDJPY,USDCHF";
input ENUM_TIMEFRAMES TradeTF       = PERIOD_M5;
input ENUM_TIMEFRAMES MediumTF      = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTF       = PERIOD_H1;
input ENUM_TIMEFRAMES LongTermTF    = PERIOD_H4;

//------------------ ULTRA-SENSITIVE INDICATOR SETTINGS -------------
input group "=== ULTRA-SENSITIVE INDICATOR SETTINGS ==="
input int    VeryFastMA_Period      = 5;
input int    FastMA_Period          = 9;
input int    MediumMA_Period        = 21;
input int    SlowMA_Period          = 89;
input int    LongTermMA_Period      = 150;

input int    RSI_Period             = 7;
input int    RSI_Overbought         = 70;
input int    RSI_Oversold           = 30;
input double MinCandleBodyPips      = 1.5;
input int    ATR_Period             = 7;
input double ATR_SL_Multiplier      = 10.0;
input ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_CLOSE;

//------------------ TREND CONFIRMATION SETTINGS -------------------
input group "=== MULTI-TIMEFRAME TREND CONFIRMATION ==="
input bool   RequireLongTermTrend   = true;
input int    Stoch_K_Period         = 5;
input int    Stoch_D_Period         = 3;
input int    Stoch_Slowing          = 3;
input double Stoch_Overbought       = 80;
input double Stoch_Oversold         = 20;

input int    MACD_Fast              = 5;
input int    MACD_Slow              = 13;
input int    MACD_Signal            = 1;

input bool UseStochasticFilter    = true;
input bool UseMACDConfirmation    = true;

//------------------ RISK MANAGEMENT --------------------------------
input group "=== RISK MANAGEMENT ==="
input double RiskPercent            = 0.5;
input double ManualLotSize          = 0.01;
input double MaxLotCap              = 0.01;
input double RiskRewardRatio = 1.5;
input bool UseManualLot = true;

//------------------ TREND SENSITIVITY SETTINGS ---------------------
input group "=== ULTRA-SENSITIVE TREND DETECTION ==="
input int    ConsecutiveBarsCount   = 2;
input bool   UseAggressiveEntries   = true;
input double PullbackEntryPercent   = 30.0;
input bool   UseVolumeConfirmation  = true;

//------------------ TRADE LIMITS ----------------------------------
input group "=== TRADE LIMITS ==="
input int    MaxTradesPerSymbol     = 5;
input int    MaxSpreadPips          = 50.0;

input group "=== TRADE FILTERS ==="
input double MaxAllowedSpread = 5.0;  // Maximum allowed spread in pips

//------------------ SILVER OPTIMIZATION ---------------------------
input group "=== SILVER-SPECIFIC SETTINGS ==="
input bool EnableSilverOptimization = true;
input double Silver_ATR_Multiplier    = 1.5;
input double Silver_MinBodyPips       = 2.0;
input int    Silver_ConsecutiveBars   = 2;

//------------------ DAILY TRACKING & LIMITS -----------------------
input group "=== DAILY TRACKING & LIMITS ==="
input bool EnableDailyLimits = true;
input double DailyProfitLimitCash    = 150.0;
input double DailyDrawdownLimitCash  = 40.0;

//------------------ NEWS FILTER -----------------------------------
input group "=== NEWS FILTER ==="
input bool EnableNewsFilter = true;
input int    NewsFilterMinutesBefore = 30;
input int    NewsFilterMinutesAfter  = 30;

//------------------ SYMBOL SCORING --------------------------------
input group "=== SYMBOL SCORING SYSTEM ==="
input double IdealSpreadPips         = 60.0;
input int    ScoringMomentumBars     = 3;
input double MinMomentumPips         = 8.0;

//------------------ REVERSAL DETECTION SETTINGS -------------------
input group "=== REVERSAL DETECTION SYSTEM ==="
input double ReversalPenaltyMax      = 2.0;
input double M5_Weight               = 0.5;
input double M15_Weight              = 0.3;
input double H1_Weight               = 0.2;
input double HighRiskThreshold       = 0.8;
input double MediumRiskThreshold     = 0.5;
input int    MinReversalSignals      = 3;
input int    SignalScoreThreshold    = 20;

//------------------ AGGRESSIVE TRAILING STOPS --------------------
input group "=== AGGRESSIVE TRAILING STOPS ==="
input int    Above1000TrailDistance = 150;

//------------------ TRAILING STOP SETTINGS --------------------------------
input group "=== TRAILING STOP SETTINGS ==="
input bool UseTrailingStop = true;
input bool UseDynamicTrailing = true;

//+------------------------------------------------------------------+
//| TRAILING STOP INPUT PARAMETERS                                   |
//+------------------------------------------------------------------+
input group "====== BREAKEVEN SETTINGS ======";
input int BreakevenTriggerPips = 150;
input int BreakevenPlusPips = 10;

input group "====== TRAILING START SETTINGS ======";
input int MinMinutesOpen = 5;
input int TrailStartPips = 50;

input group "====== PROGRESSIVE TRAILING DISTANCES ======";
input int Stage1Threshold = 200;
input int Stage2Threshold = 400;
input int Stage3Threshold = 600;

input double Stage1Distance = 200.0;
input double Stage2Distance = 200.0;
input double Stage3Distance = 200.0;

input int TrailUpdateFrequencySec = 10;

input group "====== DYNAMIC TRAILING SETTINGS ======";
input double ATRMultiplier        = 2.0;
input double MaxTrailDistance     = 150.0;

//------------------ POI SETTINGS ---------------------------------
input group "=== POI VALIDATION SETTINGS ==="
input bool EnablePOIValidation = true;
input EXPOSURE_METHOD POIValidationMethod = EXPOSURE_RISK_BASED;
input bool ShowPOIOnChart = true;

//+------------------------------------------------------------------+
//| POI Input Parameters                                            |
//+------------------------------------------------------------------+
input group "====== POI VALIDATION SETTINGS ======";
input double BaseDistanceMultiplier = 0.4;
input double MinimumBaseDistance = 15.0;
input double MaximumDistance = 200.0;
input double GoldDistanceMultiplier = 2.0;
input double SilverDistanceMultiplier = 2.5;

input group "====== POI CHART DRAWING SETTINGS ======";
input int MaxSwingLines = 5;
input int MaxSRLines = 5;
input int MaxLiquidityLines = 5;
input int LookbackBars = 72;
input int LineDurationHours = 36;

input bool ShowActiveOnly = true;
input bool ShowMajorLevels = true;
input bool ShowBreakouts = true;
input int BreakoutBars = 5;
input bool AutoClearOldLines = true;
input int ClearLinesAfterBars = 100;

//------------------ CHART DRAWING SETTINGS -----------------------
input group "=== CHART DRAWING SETTINGS ==="
input color ResistanceColor = clrRed;
input color SupportColor = clrLimeGreen;
input color SwingHighColor = clrDodgerBlue;
input color SwingLowColor = clrDeepSkyBlue;
input color LiquidityHighColor = clrMagenta;
input color LiquidityLowColor = clrDarkOrchid;
input color BrokenLevelColor = clrOrange;

input ENUM_LINE_STYLE MajorLineStyle = STYLE_SOLID;
input ENUM_LINE_STYLE ActiveLineStyle = STYLE_DASH;
input ENUM_LINE_STYLE InactiveLineStyle = STYLE_DOT;
input ENUM_LINE_STYLE BrokenLineStyle = STYLE_SOLID;

input int MajorLineWidth = 2;
input int ActiveLineWidth = 1;
input int InactiveLineWidth = 1;
input int BrokenLineWidth = 1;

input group "=== DEBUG SETTINGS ==="
input bool Enable_Debug_Mode = false;  // Enable debug logging for divergence detection

input group "=== REVERSAL DETECTION SETTINGS ==="
input int Swing_Period = 14;          // Period for swing point detection
input int Bars_To_Check = 50;         // Number of bars to check for divergences

// Add this section to your inputs.mqh file:
input group "=== DIVERGENCE DETECTION SETTINGS ==="
input int    Strength_Limit           = 3;        // Maximum swing strength
input ENUM_TIMEFRAMES Default_Timeframe = PERIOD_M15;  // Default timeframe for divergence
input double Max_Score                = 100.0;    // Maximum divergence score
input double RSI_Change_Multiplier    = 2.0;      // Multiplier for RSI change
input double Hidden_Divergence_Score  = 50.0;     // Base score for hidden divergences
input double Neutral_Score            = 0.0;      // Neutral divergence score
input bool   Enable_Auto_Decay        = true;     // Enable automatic score decay
input int    Fresh_Bars               = 5;        // Fresh divergence (bars since)
input double Fresh_Factor             = 1.0;      // Fresh divergence factor
input int    Recent_Bars              = 10;       // Recent divergence (bars since)
input double Recent_Factor            = 0.8;      // Recent divergence factor
input int    Aging_Bars               = 20;       // Aging divergence (bars since)
input double Aging_Factor             = 0.6;      // Aging divergence factor
input int    Old_Bars                 = 30;       // Old divergence (bars since)
input double Old_Factor               = 0.4;      // Old divergence factor
input double Very_Old_Factor          = 0.2;      // Very old divergence factor
input int    Max_Bars_Since           = 50;       // Maximum bars to consider divergence 


input group "=== Signal Thresholds ==="
input int    MinimumSignalScore        = 65;    // Minimum overall signal score (0-100)
input int    MinimumStrongScore        = 75;    // Strong signal threshold (0-100)
input double MinimumMomentumThreshold  = 0.3;   // Minimum momentum value (0.0-1.0)
input double MinimumTrendAlignment     = 60.0;  // Minimum trend alignment score (0-100)
input bool UseSignalValidation = true;    // Enable signal validation

input group "=== Bar traded ==="
input int MaxTradesPerBar = 2;  // User can adjust: 1 = once per bar, 2 = twice, etc.
input ENUM_TIMEFRAMES TradeLimitTimeframe = PERIOD_M15;  // Which timeframe to count bars on