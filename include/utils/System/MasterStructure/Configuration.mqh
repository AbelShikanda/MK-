// //+------------------------------------------------------------------+
// //|                       Configuration.mqh                          |
// //|                   Settings and configuration                     |
// //+------------------------------------------------------------------+
// #ifndef CONFIGURATION_MQH
// #define CONFIGURATION_MQH

// // Remove these enums if they don't exist or define them
// #ifndef ENUM_POSITION_SIZING_METHOD
// enum ENUM_POSITION_SIZING_METHOD
// {
//     PS_FIXED_FRACTIONAL,
//     PS_KELLY,
//     PS_FIXED_LOTS,
//     PS_VOLATILITY_ADJUSTED
// };
// #endif

// // ============ BASE CONFIGURATION ============
// struct BaseConfig
// {
//     string configName;
//     string version;
//     datetime lastModified;
//     bool isDefault;
    
//     // Constructor
//     BaseConfig(string name = "") : configName(name), version("1.0"),
//                                  lastModified(0), isDefault(true) {}
    
//     // REMOVE THE = 0 PURE SPECIFIERS:
//     void SetDefaults() {}  // Empty implementation in base
//     bool Validate() const { return true; }  // Default validation
//     string ToJSON() const { return ""; }
//     bool FromJSON(string json) { return false; }
// };

// // ============ TRADING CONFIGURATION ============
// struct TradingConfig : public BaseConfig
// {
//     // General trading
//     string symbol;
//     ENUM_TIMEFRAMES tradeTimeframe;
//     bool allowMultiplePairs;
//     bool allowHedging;
//     int maxConcurrentTrades;
//     int tradingStartHour;
//     int tradingEndHour;
//     bool useSessionFilter;
    
//     // Risk management
//     double maximumRiskPercent;
//     double maximumDailyRisk;
//     double maximumPositionRisk;
//     double maximumPortfolioExposure;
//     double stopLossATRMultiplier;
//     double takeProfitRRRatio;
//     double breakevenTriggerRR;
    
//     // Signal filters
//     double minimumConfidence;
//     double minimumTrendStrength;
//     double maximumReversalRisk;
//     bool requireVolumeConfirmation;
//     bool requireDivergence;
//     double minimumMomentumThreshold;
    
//     // Constructor - REMOVE override keyword
//     TradingConfig() : BaseConfig("TradingConfig")
//     {
//         SetDefaults();
//     }
    
//     // Set default values - REMOVE override keyword
//     void SetDefaults()
//     {
//         symbol = "EURUSD";
//         tradeTimeframe = PERIOD_H1;
//         allowMultiplePairs = true;
//         allowHedging = false;
//         maxConcurrentTrades = 3;
//         tradingStartHour = 0;
//         tradingEndHour = 24;
//         useSessionFilter = false;
        
//         maximumRiskPercent = 2.0;
//         maximumDailyRisk = 5.0;
//         maximumPositionRisk = 5.0;
//         maximumPortfolioExposure = 30.0;
//         stopLossATRMultiplier = 2.0;
//         takeProfitRRRatio = 2.0;
//         breakevenTriggerRR = 1.0;
        
//         minimumConfidence = 60.0;
//         minimumTrendStrength = 50.0;
//         maximumReversalRisk = 70.0;
//         requireVolumeConfirmation = true;
//         requireDivergence = false;
//         minimumMomentumThreshold = 0.0;
        
//         lastModified = TimeCurrent();
//     }
    
//     // Validate configuration - REMOVE override keyword
//     bool Validate() const
//     {
//         if(maximumRiskPercent <= 0 || maximumRiskPercent > 10)
//             return false;
//         if(maximumDailyRisk <= 0 || maximumDailyRisk > 20)
//             return false;
//         if(maxConcurrentTrades <= 0 || maxConcurrentTrades > 20)
//             return false;
//         if(takeProfitRRRatio < 1.0)
//             return false;
            
//         return true;
//     }
    
//     // Convert to JSON string - REMOVE override keyword
//     string ToJSON() const
//     {
//         string json = "{";
//         json += StringFormat("\"configName\":\"%s\",", configName);
//         json += StringFormat("\"version\":\"%s\",", version);
//         json += StringFormat("\"symbol\":\"%s\",", symbol);
//         json += StringFormat("\"tradeTimeframe\":%d,", tradeTimeframe);
//         json += StringFormat("\"maxConcurrentTrades\":%d,", maxConcurrentTrades);
//         json += StringFormat("\"maximumRiskPercent\":%.2f,", maximumRiskPercent);
//         json += StringFormat("\"maximumDailyRisk\":%.2f,", maximumDailyRisk);
//         json += StringFormat("\"stopLossATRMultiplier\":%.2f,", stopLossATRMultiplier);
//         json += StringFormat("\"takeProfitRRRatio\":%.2f", takeProfitRRRatio);
//         json += "}";
//         return json;
//     }
// };

// // ============ RISK CONFIGURATION ============
// struct RiskConfig : public BaseConfig
// {
//     // Drawdown limits
//     double maxDailyDrawdownPercent;
//     double maxTotalDrawdownPercent;
//     double warningDrawdownPercent;
//     double criticalDrawdownPercent;
    
//     // Position sizing
//     ENUM_POSITION_SIZING_METHOD sizingMethod;
//     double fixedFractionalPercent;
//     double kellyFractionPercent;
//     double minimumPositionSize;
//     double maximumPositionSize;
    
//     // Exposure limits
//     double maxSymbolExposurePercent;
//     double maxAssetClassExposurePercent;
//     double maxDirectionalExposurePercent;
//     double maxCorrelatedExposurePercent;
    
//     // Cooldown rules
//     int cooldownAfterLossMinutes;
//     int cooldownAfterBigWinMinutes;
//     int cooldownAfterConsecutiveLosses;
//     int maxTradesPerDay;
    
//     // Constructor
//     RiskConfig() : BaseConfig("RiskConfig")
//     {
//         SetDefaults();
//     }
    
//     // Set default values
//     void SetDefaults()
//     {
//         maxDailyDrawdownPercent = 5.0;
//         maxTotalDrawdownPercent = 20.0;
//         warningDrawdownPercent = 10.0;
//         criticalDrawdownPercent = 15.0;
        
//         sizingMethod = PS_FIXED_FRACTIONAL;
//         fixedFractionalPercent = 2.0;
//         kellyFractionPercent = 25.0;
//         minimumPositionSize = 0.01;
//         maximumPositionSize = 10.0;
        
//         maxSymbolExposurePercent = 10.0;
//         maxAssetClassExposurePercent = 40.0;
//         maxDirectionalExposurePercent = 50.0;
//         maxCorrelatedExposurePercent = 20.0;
        
//         cooldownAfterLossMinutes = 30;
//         cooldownAfterBigWinMinutes = 15;
//         cooldownAfterConsecutiveLosses = 3;
//         maxTradesPerDay = 20;
        
//         lastModified = TimeCurrent();
//     }
    
//     // Validate configuration
//     bool Validate() const
//     {
//         if(maxDailyDrawdownPercent <= 0 || maxDailyDrawdownPercent > 20)
//             return false;
//         if(maxTotalDrawdownPercent <= maxDailyDrawdownPercent)
//             return false;
//         if(fixedFractionalPercent <= 0 || fixedFractionalPercent > 10)
//             return false;
//         if(maxTradesPerDay <= 0 || maxTradesPerDay > 100)
//             return false;
            
//         return true;
//     }
// };

// // ============ ANALYSIS CONFIGURATION ============
// struct AnalysisConfig : public BaseConfig
// {
//     // Timeframe settings
//     ENUM_TIMEFRAMES primaryTimeframe;
//     ENUM_TIMEFRAMES confirmationTimeframe;
//     bool useMultiTimeframeAnalysis;
//     int multiTimeframeCount;
//     ENUM_TIMEFRAMES multiTimeframes[5];
    
//     // Indicator settings
//     int rsiPeriod;
//     int stochasticPeriod;
//     int macdFast;
//     int macdSlow;
//     int macdSignal;
//     int atrPeriod;
//     int maFastPeriod;
//     int maSlowPeriod;
//     int maTrendPeriod;
    
//     // Divergence settings
//     bool enableDivergenceDetection;
//     int divergenceLookbackBars;
//     double divergenceMinimumStrength;
//     bool requireHiddenDivergence;
    
//     // POI settings
//     bool enablePOIDetection;
//     double poiSwingStrength;
//     int poiLookbackBars;
//     bool markMajorPOIOnly;
    
//     // Constructor
//     AnalysisConfig() : BaseConfig("AnalysisConfig")
//     {
//         SetDefaults();
//     }
    
//     // Set default values
//     void SetDefaults()
//     {
//         primaryTimeframe = PERIOD_H1;
//         confirmationTimeframe = PERIOD_H4;
//         useMultiTimeframeAnalysis = true;
//         multiTimeframeCount = 3;
//         multiTimeframes[0] = PERIOD_M15;
//         multiTimeframes[1] = PERIOD_H1;
//         multiTimeframes[2] = PERIOD_H4;
        
//         rsiPeriod = 14;
//         stochasticPeriod = 14;
//         macdFast = 12;
//         macdSlow = 26;
//         macdSignal = 9;
//         atrPeriod = 14;
//         maFastPeriod = 9;
//         maSlowPeriod = 21;
//         maTrendPeriod = 50;
        
//         enableDivergenceDetection = true;
//         divergenceLookbackBars = 50;
//         divergenceMinimumStrength = 0.6;
//         requireHiddenDivergence = false;
        
//         enablePOIDetection = true;
//         poiSwingStrength = 1.5;
//         poiLookbackBars = 100;
//         markMajorPOIOnly = false;
        
//         lastModified = TimeCurrent();
//     }
    
//     // Validate configuration
//     bool Validate() const
//     {
//         if(rsiPeriod <= 0 || rsiPeriod > 100)
//             return false;
//         if(atrPeriod <= 0 || atrPeriod > 100)
//             return false;
//         if(divergenceLookbackBars <= 0 || divergenceLookbackBars > 200)
//             return false;
            
//         return true;
//     }
// };

// // ============ SYSTEM CONFIGURATION ============
// struct SystemConfig : public BaseConfig
// {
//     // Logging
//     bool enableLogging;
//     int logLevel;  // 0=Error, 1=Warning, 2=Info, 3=Debug
//     string logFilePath;
//     bool logToFile;
//     bool logToTerminal;
    
//     // Alerts
//     bool enableEmailAlerts;
//     string emailRecipient;
//     bool enablePushNotifications;
//     string pushToken;
    
//     // Performance
//     int healthCheckInterval;      // Seconds
//     int metricsUpdateInterval;    // Seconds
//     int positionUpdateInterval;   // Seconds
//     bool enablePerformanceMetrics;
    
//     // Safety
//     bool enableEmergencyStop;
//     double emergencyStopDrawdown;
//     int maxRuntimeHours;
//     bool autoRestartOnError;
    
//     // Constructor
//     SystemConfig() : BaseConfig("SystemConfig")
//     {
//         SetDefaults();
//     }
    
//     // Set default values
//     void SetDefaults()
//     {
//         enableLogging = true;
//         logLevel = 2;
//         logFilePath = "Logs/";
//         logToFile = true;
//         logToTerminal = true;
        
//         enableEmailAlerts = false;
//         emailRecipient = "";
//         enablePushNotifications = false;
//         pushToken = "";
        
//         healthCheckInterval = 60;
//         metricsUpdateInterval = 5;
//         positionUpdateInterval = 1;
//         enablePerformanceMetrics = true;
        
//         enableEmergencyStop = true;
//         emergencyStopDrawdown = 25.0;
//         maxRuntimeHours = 24;
//         autoRestartOnError = false;
        
//         lastModified = TimeCurrent();
//     }
    
//     // Validate configuration
//     bool Validate() const
//     {
//         if(logLevel < 0 || logLevel > 3)
//             return false;
//         if(healthCheckInterval <= 0 || healthCheckInterval > 3600)
//             return false;
//         if(emergencyStopDrawdown <= 0 || emergencyStopDrawdown > 50)
//             return false;
            
//         return true;
//     }
// };

// #endif // CONFIGURATION_MQH