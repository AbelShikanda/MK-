





++++++++++++++++++++++
ONLY PROCEED IF THIS PROVIDED FILE NEEDS THESE THINGS 
PLEASE NOTE THAT BEFOR EVERYTHING, YOU SHOULD NOT CHANGE FUNCTIONSLTY, NAMES OF FUNCTIONS OR REMOVE FUNCTIONS
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
THE LOGGER AND COMMENT FILES AND UTILS ARE ALL STATIC AND STATELESS so use static functions for these
++++++++++++++++++++++
give me this file back with (ADD these instruction ONLY OF NECESSAYR, IF NOT JUST STOP AND TELL ME):
- prefer my files below for all your utils needs to avoid redundance.
- prefer the logs and chart comments privided also for uniformity and to avoid confusion.

I WANT:
- only essential logs, like those that would display incase of an errro. still minimal to avoid perfomance issues
- chart comments with scores. also minimal to avoid perfomance issues
- create these functions for it:
    CONSTRUCTOR - sets default values, reserving memory only.
    INITIALIZE() - Takes all dependencies as parameters, Creates actual resources, Sets up internal state, Returns bool and Uses a flag m_initialized
    DEINITIALIZE() - Closes/frees resources, Resets m_initialized flag, Does NOT delete the module itself (thats for the initializer)
    Plus event handlers: OnTick(), OnTimer(), OnTradeTransaction() - ONLY process if m_initialized = true, and only use initialized resources 
- a step-by-step Minimal EA Intergration example.
- a list of all the functions in the file in this manner
        File.mqh
        ++++++++++++++++++++++++++++
        function1(param1, param2)
        function2(param1, param2)
- Proper comments to be able to follow up on the code slowly





Update this module to:
	RETURN their own module-specific data structures
	ADD helper methods that return raw data, NOT TradePackage objects
	Modules should NOT know about TradePackage at all!
WHAT MODULES MUST PROVIDE:
	Their own data structures (e.g., MTFScore, POISignal)
	Analysis methods that return those structures
	NO TradePackage includes or references





+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR UTILS PLEASE PREFER MY FILES AND FUNCITONS:
all utils are static files with static functions only, no classes.
use as static functions only.
prefer this for all your utils needs to avoid redundance.
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
consider mathutils
++++++++++++++++++++++
PipsToPrice(string symbol, double pips)
PriceToPips(string symbol, double price)
CalculatePipValue(string symbol)
CalculatePositionRisk(string symbol, double entryPrice, double stopLoss, double lotSize)
CalculateRiskRewardRatio(double entryPrice, double stopLoss, double takeProfit)
CalculatePercentageChange(double oldValue, double newValue)
CalculateValueFromPercentage(double baseValue, double percentage)
CalculatePercentageOfValue(double part, double whole)
CalculateSimpleMovingAverage(const double &values[], int period)
CalculateWeightedAverage(const double &values[], const double &weights[])
CalculateATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift = 0)
CalculateStandardDeviation(const double &data[])
CalculateDistanceInPips(string symbol, double price1, double price2)
CalculateDistanceAsPercentage(double price1, double price2, double referencePrice)
NormalizePrice(string symbol, double price)
NormalizePriceToTick(string symbol, double price)
NormalizeLotSize(string symbol, double lotSize)
CalculateProfitInPips(string symbol, double entryPrice, double exitPrice, bool isBuy)
CalculateProfitInMoney(string symbol, double entryPrice, double exitPrice, double lotSize, bool isBuy)
CalculateWinProbability(int totalTrades, int winningTrades)
CalculateExpectedValue(double winRatePercent, double avgWin, double avgLoss)
CalculateKellyCriterion(double winRatePercent, double avgWinToLossRatio)
CalculateFibonacciLevel(double high, double low, double level)
CalculateGeometricMean(const double &values[])
CalculateAnnualizedReturn(double totalReturnPercent, double days)
CalculateCompoundedGrowth(double initialAmount, double ratePercent, int periods)
IsValidPrice(string symbol, double price)
IsValidLotSize(string symbol, double lotSize)
CalculatePositionSizeByRisk(string symbol, double entryPrice, double stopLoss, double riskPercent, double accountBalance)
CalculatePositionSize() find out params in indicator file for atr based position sizing
CalculateBreakevenPrice(double entryPrice, bool isBuy, double spreadPips)
CalculateMarginRequired(string symbol, double lotSize, int orderType = ORDER_TYPE_BUY)
CalculateSwap(string symbol, double lotSize, int orderType, int days = 1)
RoundToTick(string symbol, double value)
CalculateCommission(string symbol, double lotSize, double commissionPerLot = 0)
CalculateTotalTradeCost(string symbol, double lotSize, bool isBuy, double commissionPerLot = 0)
CalculatePositionScore()

consider errorutils
++++++++++++++++++++++
CheckError(int errorCode)
GetErrorDescription(int errorCode)
HandleOrderError(int errorCode, Logger &logger)
HandleOrderError(int errorCode)
HandleMarketError(int errorCode, Logger &logger)
HandleMarketError(int errorCode)
GetLastError(Logger &logger)
GetLastError()
CheckErrorWithTime(int errorCode, Logger &logger)
IsRecoverableError(int errorCode)
IsFatalError(int errorCode)
GetRecoverySuggestion(int errorCode)
ResetLastError()
GetErrorDetails(int errorCode)
LogErrorWithDetails(int errorCode, Logger &logger, string context)
HandleErrorWithRetry(int errorCode, Logger &logger, int maxRetries)

consider loggerutils
++++++++++++++++++++++
GetTimestamp()
GetTimeOnly()
BuildMessage(string module, string timestamp, string reason)
LogInternal(string module, string reason, bool logToFile = true, bool logToConsole = true)
Initialize(string fileName = "", bool logToFile = true, bool logToConsole = true)
Shutdown()
Log(string module, string reason, bool logToFile = true, bool logToConsole = true)
LogError(string module, string reason, int errorCode = 0)
LogTrade(string module, string symbol, string operation, double volume, double price = 0.0)
LogFast(string module, string reason)
LogUltraFast(const string &module, const string &reason)
LogTradeFast(const string &module, const string &symbol, const string &operation, double volume)
IsFileLoggingAvailable()
GetLogFileName()
GetFileHandleStatus()
LogMemoryUsage(string module)
Flush()
LogWithTimestamp(string module, string reason, datetime customTime)

consider configutils
++++++++++++++++++++++
ReadDatetime(string key, datetime defaultValue)
ReadColor(string key, color defaultValue)
ReadEnum(string key, int defaultValue)
ReadInt(string key, int defaultValue, string section)
ReadDouble(string key, double defaultValue, string section)
ReadBool(string key, bool defaultValue, string section)
ReadString(string key, string defaultValue, string section)
WriteInt(string key, int value, string section)
WriteDouble(string key, double value, string section)
WriteBool(string key, bool value, string section)
WriteString(string key, string value, string section)
WriteDatetime(string key, datetime value, string section)
WriteColor(string key, color value, string section)
ConfigExists()
GetConfigPath(bool common)

consider timeutils
++++++++++++++++++++++
IsTradingSession(const string symbol = NULL)
GetTradingSession(const string symbol, datetime &startTime, datetime &endTime)
IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
IsMarketOpen(const string symbol = NULL)
IsEndOfMonth(const string symbol = NULL)
IsStartOfMonth(const string symbol = NULL)
MinutesUntilSession(const string symbol = NULL, bool nextDay = false)
IsHighVolatilityPeriod()
IsTimeInRange(int startHour, int startMinute, int endHour, int endMinute)
TradingDaysBetween(datetime startDate, datetime endDate)
IsPreMarket(const string symbol = NULL)
IsAfterHours(const string symbol = NULL)
NextTradingDay(datetime fromDate = 0)
TimeOfDayToString()
IsRolloverTime()
GetTimestamp()
TimeframeToMinutes(ENUM_TIMEFRAMES tf)
GetBarOpenTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
GetBarCloseTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


















+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR LOGS PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Prefer my logger functions instead, only where necessary LOGGERS ARE STATIC SO USE STATIC CALLS IE Logger::Log(...)
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
application example: in a file always wrap inside of a debug true false.
// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED = true;

// Simple debug function using Logger
void DebugLogFile(string context, string message) {
   if(DEBUG_ENABLED) {
      Logger::Log(log);
   }
}

//then all the logs and wrapped around the degub
// not chart comments.

so

// Initialize with different configurations
Logger::Initialize();                          // Default: file logging ON, chart ON, 2s updates
Logger::Initialize("MyBot.log", true, true, 1); // Custom settings
Logger::Initialize("", false, true, 5);        // No file logging, chart only, 5s updates
Logger::Shutdown();                           // Clean shutdown
// Runtime control
Logger::EnableChart(false);                   // Disable chart updates temporarily
Logger::SetChartFrequency(3);                 // Change update frequency (seconds)
Logger::ClearChart();                         // Clear all chart comments
Logger::Flush();                              // Flush file buffer
// Status checks
bool canLog = Logger::IsFileLoggingAvailable(); // Check if file is open
string fileName = Logger::GetLogFileName();   // Get current log filename
bool chartOn = Logger::IsChartEnabled();      // Check chart status
// Standard logging (console + file)
Logger::Log("Module", "Message");
Logger::Log("Strategy", "Entry signal detected", true, true); // logToFile, logToConsole
// Error logging
Logger::LogError("API", "Failed to connect");
Logger::LogError("Trade", "Order rejected", 10013); // With error code
// Trade logging
Logger::LogTrade("Portfolio", "EURUSD", "BUY", 0.1, 1.08542); // With price
Logger::LogTrade("Risk", "GBPUSD", "SELL", 0.05);             // Without price
// Performance logging
Logger::LogMemoryUsage("System");            // Log memory usage (MQL5 only)
// Faster with minimal formatting
Logger::LogFast("Module", "Fast message");  // Quick timestamp
Logger::LogUltraFast("Ticker", "Price update: 1.0850"); // No timestamp
// Fast trade logging
Logger::LogTradeFast("Scalper", "EURUSD", "BUY", 0.1);
// Custom timestamp logging
Logger::LogWithTimestamp("Backtest", "Strategy executed", D'2024.01.15 10:30:00');
// Single symbol score display
Logger::ShowScoreFast("EURUSD", 0.85, "BUY", 0.9);
Logger::ShowScoreFast("GBPUSD", 0.42, "SELL", 0.6);
Logger::ShowScoreFast("USDJPY", 0.15, "HOLD", 0.3); // Low score example
Logger::ShowScoreFast("XAUUSD", 0.92, "BUY", 0.95); // High confidence
// Trading decisions
Logger::ShowDecisionFast("EURUSD", 1, 0.92, "Strong bullish divergence on 4H");
Logger::ShowDecisionFast("GBPUSD", -1, 0.75, "Bearish breakout below support");
Logger::ShowDecisionFast("AUDUSD", 0, 0.60, "Waiting for confirmation"); // HOLD decision
// Portfolio overviews
string symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "XAUUSD"};
double scores[] = {0.85, 0.42, 0.73, 0.61, 0.29, 0.92};
int directions[] = {1, -1, 0, 1, -1, 1}; // 1=BUY, -1=SELL, 0=HOLD
Logger::ShowPortfolioFast(symbols, scores, directions);
// Risk metrics display
Logger::ShowRiskMetrics(3.2, 1.8, 1.4, 5); // risk%, drawdown%, sharpe, positions
Logger::ShowRiskMetrics(5.7, 3.2, 0.8, 8); // High risk example
Logger::ShowRiskMetrics(1.5, 0.9, 2.1, 3); // Low risk example
// Mixed use cases
string forexPairs[] = {"EURUSD", "GBPUSD", "USDJPY"};
double forexScores[] = {0.85, 0.42, 0.73};
int forexDirections[] = {1, -1, 0};
Logger::ShowPortfolioFast(forexPairs, forexScores, forexDirections);
// Backtesting scenarios
Logger::LogWithTimestamp("Backtest", "Entry: BUY EURUSD @ 1.0850", D'2024.01.15 10:30:00');
Logger::LogWithTimestamp("Backtest", "Exit: SELL EURUSD @ 1.0900 (+50 pips)", D'2024.01.15 14:45:00');
// Multi-timeframe analysis
Logger::Log("Analysis", "4H: Bullish | 1H: Neutral | 15M: Bearish");
Logger::ShowDecisionFast("EURUSD", 1, 0.82, "4H trend up, 1H pullback to support");
// Correlation analysis
Logger::Log("Correlation", "EURUSD-GBPUSD correlation: 0.72 (High)");
Logger::ShowScoreFast("EURUSD", 0.85, "BUY", 0.9);
Logger::ShowScoreFast("GBPUSD", 0.65, "HOLD", 0.7); // Lower due to correlation
// Position sizing and risk
Logger::Log("Risk", "Position size: 0.15 lots, Risk: $150 (1.5% of account)");
Logger::LogTrade("Execution", "EURUSD", "BUY", 0.15, 1.08542);
Logger::ShowRiskMetrics(1.5, 2.1, 1.2, 4);
// Performance tracking
Logger::Log("Performance", "Win Rate: 65%, Profit Factor: 1.8, Avg Win: $85");
Logger::LogMemoryUsage("Monitor");
// News/Event reactions
Logger::Log("News", "NFP release in 15 minutes - reducing position sizes");
Logger::ShowDecisionFast("USD pairs", 0, 0.40, "Waiting for NFP data");
// System alerts
Logger::LogError("System", "High latency detected: 250ms");
Logger::LogError("Connection", "Feed disconnected", 4065);
Logger::ShowDecisionFast("ALL", 0, 0.10, "Connection issues - pausing trading");
// Portfolio rebalancing
Logger::Log("Rebalance", "Closing 2 positions to reduce correlation risk");
Logger::LogTrade("Rebalance", "EURUSD", "CLOSE", 0.1);
Logger::LogTrade("Rebalance", "GBPUSD", "CLOSE", 0.05);
Logger::ShowRiskMetrics(2.8, 1.5, 1.6, 3); // Updated risk after rebalance
// Strategy parameter optimization
Logger::Log("Optimization", "Testing params: MA1=10, MA2=20, StopLoss=50");
Logger::ShowScoreFast("EURUSD", 0.78, "BUY", 0.8);
Logger::Log("Optimization", "Testing params: MA1=14, MA2=28, StopLoss=60");
Logger::ShowScoreFast("EURUSD", 0.82, "BUY", 0.85);
// Market condition analysis
Logger::Log("Market", "High volatility detected: ATR = 0.0085");
Logger::ShowDecisionFast("EURUSD", 1, 0.68, "High vol - using wider stops");
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


























+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
give the provided file back using this file as reference to build it properly.
the indicator manager primary needs to be able to provide all necessary indicator values.
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
IndicatorManager(string symbol = NULL)
~IndicatorManager()
Initialize()
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
GetMAValues(ENUM_TIMEFRAMES tf, double &ma_fast, double &ma_slow, double &ma_medium, int shift = 0)
GetRSI(ENUM_TIMEFRAMES tf, int shift = 0)
GetMACDValues(ENUM_TIMEFRAMES tf, double &macd_main, double &macd_signal, int shift = 0)
GetADXValues(ENUM_TIMEFRAMES tf, double &adx, double &plus_di, double &minus_di, int shift = 0)
GetStochasticValues(ENUM_TIMEFRAMES tf, double &stoch_main, double &stoch_signal, int shift = 0)
GetATR(ENUM_TIMEFRAMES tf, int shift = 0)
GetVolume(ENUM_TIMEFRAMES tf, int shift = 0)
GetBollingerBandsValues(ENUM_TIMEFRAMES tf, double &upper, double &middle, double &lower, int shift = 0)
IsTrendBullish(ENUM_TIMEFRAMES tf)
IsTrendBearish(ENUM_TIMEFRAMES tf)
IsOverbought(ENUM_TIMEFRAMES tf)
IsOversold(ENUM_TIMEFRAMES tf)
IsStrongTrend(ENUM_TIMEFRAMES tf, int threshold = 25)
GetADXTrendDirection(ENUM_TIMEFRAMES tf)
GetMACDCrossover(ENUM_TIMEFRAMES tf)
GetMultiTimeframeConfirmation(int &bullish_tf_count, int &bearish_tf_count)
GetBBandsPosition(ENUM_TIMEFRAMES tf, double price)
CalculatePositionSize(double risk_percent, double stop_loss_pips, ENUM_TIMEFRAMES tf = PERIOD_H1)
GetMarketScore()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++



















+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS TRADEPACKAGE PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR TRADING PACKAGE PLEASE PREFER MY FILES AND FUNCITONS:
give me a way to populate the tradepackage given the file provided
rebuild this file to be able to populate my  tradepackage properly.
the trade package primary needs a re bull and bear bias and score and the confidence in that score
then any unique variables that the file can profide.
this functions constitute the trade package file
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
TradePackage.mqh
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
File-level functions:
DebugLogTP(string context, string message)

Struct ComponentDisplay:
ComponentDisplay()
ComponentDisplay(string n, string d, double s, double c, double w, bool a, string dt = "")
string GetFormattedLine(bool useIcons = true, bool showDetails = false)
string GetDirectionIcon(string dir, bool useIcons)

Struct DirectionAnalysis:
string GetDisplayString() const

Struct TradeSignal:
string GetOrderTypeString() const
string GetSimpleSignal() const

Struct TradeSetup:
bool IsValid() const
string GetRRRString() const

Struct MTFData:
string GetAlignmentString() const

Struct RiskManagement:
string GetSettingsString() const

Struct POISignal (nested in TradePackage):
POISignal()
string GetSimpleSignal() const
string GetConfidenceString() const
bool IsActionable() const
string GetDisplayString() const

Struct TradePackage:
TradePackage()
void CalculateWeightedScore()
double CalculateOverallConfidence()
void NormalizeWeights()
bool ValidatePackage(double minConfidence = 60.0)
void DisplayTabular()
string GenerateTabularDisplay()
static void DisplayMultiSymbol(const TradePackage &packages[], bool showAllComponents = false)
string GetTabularHeader()
string GetSymbolHeader() const
void CollectComponents(ComponentDisplay &components[]) const
string GetOverallSummary()
string GetSetupInfo()
string GetValidationStatus()
string GetMTFDirection() const
string GetSignalIcon() const
string GetDirectionIcon(string dir, bool useIcons)
void ConfigureDisplay(bool tabularFormat = true, bool useColors = true, bool showInactive = false, bool showDetails = false)
void SetMaxComponentsPerLine(int max)
void DisplayOnChart()
string GenerateChartDisplay()
void LogCompletePackage()
string GenerateLogEntry()
void LogKeyMetrics()
void CalculatePositionSize(double accountBalance)
void CalculateRiskReward()
string GetSummary()
bool HasMTFData() const
bool HasSetup() const
double GetPositionSizeMultiplier() const
int GetTradeDecision() const
double GetConfidenceDecimal() const
void Display()
string RepeatString(string str, int count)
void SetDecisionEngine(DecisionEngine* de)
bool ProcessAndExecute()
bool UpdateAndExecute()
bool Validate() const
int StringCount(const string text, const string search)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




































+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MTFANALYZER MANAGEMENT PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
MTFAnalyser() - Constructor, sets default values
Initialize(symbol, primaryTF, indicatorManager) - Initializes the analyzer with dependencies
Deinitialize() - Cleans up resources
OnTick() - Handles tick events
OnTimer() - Handles timer events
OnTradeTransaction(trans, request, result) - Handles trade transaction events
AnalyzeMultiTimeframe(symbol) - Analyzes alignment across multiple timeframes
CheckAlignment(symbol, minScore) - Checks if timeframes are aligned above minimum score
GetDominantTF(symbol) - Gets the timeframe with strongest trend
IsInitialized() - Returns initialization status
GetSymbol() - Gets current symbol
GetPrimaryTF() - Gets primary timeframe
AnalyzeTrend(symbol, timeframe) - PRIVATE: Analyzes trend for specific timeframe
GetEMA(symbol, timeframe, period) - PRIVATE: Gets EMA value
CalculateTrendStrength(symbol, timeframe) - PRIVATE: Calculates trend strength using ADX
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR POSITION MANAGER PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PositionManager::OpenPosition(symbol, isBuy, comment, magic, stopMethod, riskPercent, rrRatio, reason)
PositionManager::OpenPositionWithTradePackage(symbol, isBuy, package)
PositionManager::CloseAllPositions(symbol, magic, reason)
PositionManager::SmartClosePosition(priority, magic, outClosedSymbol)
PositionManager::GetPositionCount(symbol, magic)
PositionManager::GetTotalProfit(symbol, magic)
PositionManager::UpdateTrailingStops(trailMethod, magic)
PositionManager::CheckMargin(symbol, lotSize, safetyBuffer)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR DECISION ENGINE PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
DecisionEngine() - Constructor
~DecisionEngine() - Destructor
Initialize(PositionManager, RiskManager, engineComment, engineMagicBase, slippage, chartUpdateSeconds)
Deinitialize()
MakeDecisionFromPackage(symbol, package)
ExecuteDecision(symbol, decision, package)
AddSymbol(symbol, params)
RemoveSymbol(symbol)
HasSymbol(symbol)
GetSymbolCount()
SetSymbolParameters(symbol, params)
SetTradePackageFunction(func)
SetDebugMode(debug)
SetUseComponentWeights(use)
SetMinConfidenceThreshold(threshold)
SetChartUpdateSeconds(seconds)
GetSymbolParameters(symbol)
GetLastPackage(symbol)
GetCurrentDecision(symbol)
GetDecisionAccuracy()
GetStatus()
DecisionToString(decision)
ResetStatistics()
QuickInitialize(symbol, buyThreshold, sellThreshold, riskPercent, cooldownMinutes, maxPositions)
OnTick()
OnTimer()
OnTradeTransaction(trans, request, result)
UpdateChartDisplay()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
MarketData(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
double GetBid(string symbol = NULL)
double GetAsk(string symbol = NULL)
double GetSpread(string symbol = NULL)
MqlTick GetTick(string symbol = NULL)
bool GetOHLC(string symbol, ENUM_TIMEFRAMES timeframe, int shift, double &open, double &high, double &low, double &close)
long GetVolume(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, int shift = 0)
long GetVolume(string symbol = NULL)
bool IsFresh()
void Refresh()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR POI PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
POIModule() - Constructor
Initialize(string symbol, bool drawOnChart = false, double defaultBuffer = 2.0)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
GetPOIScore(double currentPrice, ENUM_POI_TYPE &outZoneType, double &outDistanceToZone)
IsInsidePOIZone(double currentPrice, ENUM_POI_TYPE &outZoneType)
GetNearestZone(double currentPrice, POIZone &outZone)
IsInitialized()
GetZoneCount()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR VOLUME PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VolumeModule() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES analysisTF = PERIOD_H1)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
AnalyzeVolume(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetVolumeScore(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
HasVolumeDivergence(bool isBuyTrade, const double &prices, int period = 5)
IsInitialized()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR RSI PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
RSIModule() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES analysisTF = PERIOD_H1, 
          int rsiPeriod = 14, ENUM_APPLIED_PRICE appliedPrice = PRICE_CLOSE)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
AnalyzeRSI(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetRSIScore(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetCurrentRSIValue()
GetRSITrend(int barsToCheck = 5)
HasFailureSwing(bool isBuyTrade)
IsInitialized()
GetAnalysisTimeframe()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR RISK MANAGER PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
RiskCalculator::CanOpenTrade(maxDailyLossPercent, maxDrawdownPercent)
RiskCalculator::CalculatePositionSize(symbol, entryPrice, stopLoss, riskPercent)
RiskCalculator::CalculatePositionSizeWithConfidence(symbol, entryPrice, stopLoss, confidence, baseRiskPercent)
RiskCalculator::CalculateStopLoss(symbol, isBuy, entryPrice, method, atrMultiplier)
RiskCalculator::CalculateTakeProfit(symbol, isBuy, entryPrice, stopLoss, rrRatio)
RiskCalculator::CalculateTakeProfitWithConfidence(symbol, isBuy, entryPrice, stopLoss, confidence, baseRR)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR VolumeModule.mqh PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VolumeModule() - Constructor, sets default values
~VolumeModule() - Destructor, calls Deinitialize()
Initialize(IndicatorManager* indicatorMgr, string symbol = NULL) - Initialize module
Deinitialize() - Clean up resources
Analyze(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20, int fastPeriod = 5) - Comprehensive analysis
GetVolumeScore(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, bool isBullishMove = true) - Simplified 0-100 score
IsVolumeConfirming(ENUM_TIMEFRAMES tf, bool expectingBullish) - Check volume confirmation
HasSpike(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, double threshold = 2.0) - Check for volume spike
GetStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get volume status string
HasDivergence(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int period = 5) - Check for divergence
IsClimaxVolume(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20) - Check for climax
SetSpikeThreshold(double threshold) - Set spike threshold
SetClimaxThreshold(double threshold) - Set climax threshold
SetDefaultTimeframe(ENUM_TIMEFRAMES tf) - Set default timeframe
IsInitialized() - Check if initialized
GetSymbol() - Get symbol
ConfigureTradePackageIntegration(bool enable = true, double bullWeight = 0.6, double bearWeight = 0.6) - Configure TP integration
DisplayOnChart(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int corner = 2, int x = 10, int y = 20) - Display on chart
GetTradePackageComponent(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get ComponentDisplay for TradePackage
GetVolumeScoreForTradePackage(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, string expectedDirection = "") - Get TP-formatted score
GetDirectionalBias(double &bullScore, double &bearScore, double &overallConfidence, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get bias scores
GetTradeRecommendation(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get trade recommendation
GetConfirmationStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get confirmation status
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR SimpleRSI.mqh PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
SimpleRSI(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1, int period = 14, IndicatorManager* indicatorMgr = NULL)
RSIBias GetBiasAndConfidence(int lookback = 20)
void PopulateTradePackage(TradePackage &package, int lookback = 20)
ComponentDisplay GetComponentDisplay(int lookback = 15)
void AddToComponentsArray(ComponentDisplay &components[], int lookback = 15)
bool IsBullishBias(int lookback = 10)
bool IsBearishBias(int lookback = 10)
double GetNetBiasScore(int lookback = 10)
double GetConfidence(int lookback = 10)
double GetCurrentRSI()
void SetIndicatorManager(IndicatorManager* indicatorMgr)
bool IsUsingIndicatorManager() const

UltraSimpleRSI (Static Class)
++++++++++++++++++++++++++++
static void GetBias(string symbol, ENUM_TIMEFRAMES tf, double &biasScore, double &confidence, IndicatorManager* indicatorMgr = NULL)
static bool IsBullish(string symbol, ENUM_TIMEFRAMES tf, IndicatorManager* indicatorMgr = NULL)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
CandlestickPatterns.mqh
+++++++++++++++++++++++++++
CandlestickPatternAnalyzer() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars = 100)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction()
AnalyzeCurrentPattern(int shift = 1)
GetPatternScore(int shift = 1)
GetPatternSignal(int shift = 1)
IsHammer(const CandleData &candle)
IsInvertedHammer(const CandleData &candle)
IsShootingStar(const CandleData &candle)
IsHangingMan(const CandleData &candle)
IsSpinningTop(const CandleData &candle)
IsMarubozuBullish(const CandleData &candle)
IsMarubozuBearish(const CandleData &candle)
IsDoji(const CandleData &candle, ENUM_CANDLE_PATTERN &dojiType)
CheckBullishEngulfing(CandleData &candle1, CandleData &candle2)
CheckBearishEngulfing(CandleData &candle1, CandleData &candle2)
CheckHarami(CandleData &candle1, CandleData &candle2, bool bullish)
CheckPiercingLine(CandleData &candle1, CandleData &candle2)
CheckDarkCloudCover(CandleData &candle1, CandleData &candle2)
CheckMorningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckEveningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeWhiteSoldiers(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeBlackCrows(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckSingleCandlePattern(CandleData &candle)
CheckTwoCandlePattern(CandleData &candle1, CandleData &candle2)
CheckThreeCandlePattern(CandleData &candle1, CandleData &candle2, CandleData &candle3)
GetCandleData(int shift)
GetDojiDescription(ENUM_CANDLE_PATTERN dojiType)
PatternToString(ENUM_CANDLE_PATTERN pattern)
IsInitialized()
GetSymbol()
GetTimeframe()
HasStrongPattern(int shift = 1)
GetSimpleDirection(int shift = 1)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
CandlestickPatterns.mqh
++++++++++++++++++++++++++++
CandlestickPatternAnalyzer() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars = 100)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
AnalyzeCurrentPattern(int shift = 1)
GetPatternScore(int shift = 1)
GetPatternSignal(int shift = 1)
IsHammer(const CandleData &candle)
IsInvertedHammer(const CandleData &candle)
IsShootingStar(const CandleData &candle)
IsHangingMan(const CandleData &candle)
IsSpinningTop(const CandleData &candle)
IsMarubozuBullish(const CandleData &candle)
IsMarubozuBearish(const CandleData &candle)
IsDoji(const CandleData &candle, ENUM_CANDLE_PATTERN &dojiType)
CheckBullishEngulfing(CandleData &candle1, CandleData &candle2)
CheckBearishEngulfing(CandleData &candle1, CandleData &candle2)
CheckHarami(CandleData &candle1, CandleData &candle2, bool bullish)
CheckPiercingLine(CandleData &candle1, CandleData &candle2)
CheckDarkCloudCover(CandleData &candle1, CandleData &candle2)
CheckMorningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckEveningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeWhiteSoldiers(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeBlackCrows(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckSingleCandlePattern(CandleData &candle)
CheckTwoCandlePattern(CandleData &candle1, CandleData &candle2)
CheckThreeCandlePattern(CandleData &candle1, CandleData &candle2, CandleData &candle3)
UpdateChartComments()
ShowScoreOnChart(const PatternResult &result)
GetCandleData(int shift)
GetDojiDescription(ENUM_CANDLE_PATTERN dojiType)
PatternToString(ENUM_CANDLE_PATTERN pattern)
TimeframeToString(ENUM_TIMEFRAMES tf)
IsInitialized()
GetSymbol()
GetTimeframe()
HasStrongPattern(int shift = 1)
GetSimpleDirection(int shift = 1)
SetDebugEnabled(bool enabled)
SetChartUpdateFrequency(int seconds)

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




BUILDING A UTIL FILE WITH STATIC, STATELESS FUNCTIONS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
make this file static and make sure all functions are stateless
add the necessary time functions i may have missed if any 
make all functions static and mql5 friendly
make sure functions are stateless




FILE PERMORMANCE OPTIMIZATION INSTRUCTIONS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Please optimize the performance of this MQL5 code by removing 
excessive logging, debugging prints, and unnecessary console output 
while preserving essential error messages and critical information. 

Follow these guidelines:
- Remove ALL debug prints (Print()) from tight loops like OnTick(), OnTimer(), and position update functions
- Keep only essential logs for:
    - Initialization/deinitialization
    - Trade execution (open/close/modify)
    - Error conditions
    - Major state changes (emergency stop, risk level changes)
    - Configuration changes
- Optimize logging frequency:
    - Replace frequent prints with periodic summaries (e.g., every 1 minutes)
    - Use static timers to limit print frequency
    - Aggregate multiple messages into single prints
- Remove redundant information:
    - Dont log the same status repeatedly
    - Combine related information into single messages
    - Remove timestamp prefixes if MT5 already adds them
- Preserve critical information:
    - Keep trade execution confirmations
    - Keep error messages and warnings
    - Keep risk limit violations
    - Keep account/position state changes

ALSO:
- Cache position data to avoid repeated PositionGet calls in loops
- Use PrintFormat() instead of multiple Print() calls
- Remove logging from hot paths (functions called every tick)
- Add log levels enum RESOURCE_MANAGER
        {
            OBSERVE,
            AUTHORIZE,
            WARN,
            ENFORCE,
            AUDIT
        };
    with configurable verbosity
- Use static variables to track last log time and prevent spamming
- Move detailed logs to separate debug functions that are conditionally called
- Batch similar messages into periodic status reports instead of tick-by-tick logging
- Focus on the most performance-critical areas:
    - OnTick() and OnTimer() methods
    - Position update loops
    - Indicator calculations
    - Market data processing functions**

    
DO NOT CHANGE FUNCTIONALITY PLEASE
USE MINIMAL CODE CHANGE



CREATE AN MQL5 CHART COMMENT DASHBOARD
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Create an optimized MQL5 chart comment file (.mqh) that displays essential account and trading information with maximum performance. This should be a visual dashboard that traders can place on their charts for at-a-glance monitoring.

## PERFORMANCE REQUIREMENTS:
- **Ultra-efficient updates**: Update only when values change, not every tick
- **Minimal CPU usage**: Use caching, static variables, and update throttling
- **Zero tight-loop operations**: No heavy calculations in OnTick()
- **Memory efficient**: Reuse string buffers, no string concatenation in loops
- **Clean rendering**: No flickering, smooth updates

## ESSENTIAL DISPLAY ELEMENTS (Creative & Visual):

### 1. ACCOUNT STATUS PANEL (Top Left)
```
╔══════════════════════════════════╗
║        ACCOUNT STATUS            ║
╠══════════════════════════════════╣
║ Balance:     $25,430.75  📊      ║
║ Equity:      $26,120.50  ↗️      ║
║ Margin:      $1,230.75   🔒      ║
║ Free Margin: $24,889.75  ✅      ║
║ Margin Level: 2,123%     🛡️      ║
║ Daily P/L:   +$689.75    📈      ║
╚══════════════════════════════════╝
```

### 2. TRADING SESSION INFO (Top Right)
```
╔══════════════════════════════════╗
║       TRADING SESSION            ║
╠══════════════════════════════════╣
║ Session:    LONDON/NY OVERLAP    ║
║ Time Left:  02:15:43     ⏳      ║
║ Volatility: HIGH          🌊      ║
║ Spread:     1.2 pips     ⚡      ║
║ Trend:      BULLISH      ↗️      ║
║ Market Hours: 09:00-17:00🕐      ║
╚══════════════════════════════════╝
```

### 3. POSITIONS OVERVIEW (Center Left)
```
╔══════════════════════════════════╗
║      ACTIVE POSITIONS            ║
╠══════════════════════════════════╣
║ EUR/USD:   BUY  1.0950  +$320    ║
║            SL: 1.0900   TP:1.1050║
║            R:R 3.2:1    🔥       ║
╠══════════════════════════════════╣
║ GBP/USD:   SELL 1.2650  -$45     ║
║            SL: 1.2700   TP:1.2550║
║            R:R 2.0:1    ⚠️       ║
╠══════════════════════════════════╣
║ TOTAL:     2 positions  +$275    ║
║            Risk: 1.8%    ✅      ║
╚══════════════════════════════════╝
```

### 4. PERFORMANCE METRICS (Center Right)
```
╔══════════════════════════════════╗
║    PERFORMANCE METRICS           ║
╠══════════════════════════════════╣
║ Win Rate:       68%      🎯      ║
║ Profit Factor:  2.4      💎      ║
║ Avg Win:       +$420     🚀      ║
║ Avg Loss:      -$180     🛡️      ║
║ Max DD:        -$1,200   ⚠️      ║
║ Recovery:      85%       📈      ║
║ Consecutive:   4 wins    🔥      ║
╚══════════════════════════════════╝
```

### 5. RISK MANAGEMENT (Bottom Left)
```
╔══════════════════════════════════╗
║      RISK MANAGEMENT             ║
╠══════════════════════════════════╣
║ Max Risk/Trade:   2.0%   ✅      ║
║ Daily Loss Limit: 5.0%   🛡️      ║
║ Max Positions:    5      🎯      ║
║ Current Risk:     1.8%   📊      ║
║ Available Risk:   3.2%   💰      ║
║ Volatility Adj:   85%    🌊      ║
║ Safety Level:     GREEN  ✅      ║
╚══════════════════════════════════╝
```

### 6. MARKET CONDITIONS (Bottom Right)
```
╔══════════════════════════════════╗
║     MARKET CONDITIONS            ║
╠══════════════════════════════════╣
║ Trend Strength:  85%     ↗️      ║
║ Market Phase:   ACCUMULATION    ║
║ Volatility:      HIGH    🌊      ║
║ Liquidity:       GOOD    💧      ║
║ News Impact:     MEDIUM  📰      ║
║ Bias:           BULLISH  🐂      ║
║ Confidence:      78%     ✅      ║
╚══════════════════════════════════╝
```

OnTick() (every 10s)
    ↓
IndicatorManager.UpdateAllModulesAndExecute()
    ↓
[Modules update TradePackage fields]
    ↓
TradePackage.UpdateAndExecute()
    ↓
TradePackage.ProcessAndExecute() → DecisionEngine → Trade Execution























































































To call the existing `GenerateDetailedTabularDisplay()` function from `TradePackage` and a similar display function from your Decision Engine (I'll assume it exists), you need to expose them through a public interface. Here's how to do it:

## 1. First, let me see what you have in Decision Engine (you mentioned `DisplayDecisionEngineView`)

Since I don't have your Decision Engine code, I'll show you two approaches:

## Approach 1: Simple Method Calls (If you have instance access)

### In your main EA, if you have instances:
```mql4
// Main EA

// Assuming you have these instances somewhere
TradePackage tradePackage;
// DecisionEngine decisionEngine; // Your decision engine instance

// Call the display functions
void DisplayTradePackage() {
    string displayText = tradePackage.GenerateDetailedTabularDisplay();
    Logger::DisplaySingleFrame(displayText);
}

void DisplayDecisionEngine() {
    // If you have a method in DecisionEngine like:
    // decisionEngine.DisplayDecisionEngineView();
    // or if it's a static method:
    // DecisionEngine::DisplayDecisionEngineView();
}
```

## Approach 2: Create a Display Manager Interface (Recommended)

Create a simple interface class to manage all displays:

```mql4
// DisplayManager.mqh
#include "Data/TradePackage.mqh"
// #include "DecisionEngine.mqh" // Include your decision engine

class DisplayManager {
public:
    // Method to display TradePackage
    static void DisplayTradePackage(const TradePackage &package) {
        string displayText = package.GenerateDetailedTabularDisplay();
        Logger::DisplaySingleFrame(displayText);
    }
    
    // Method to display Decision Engine view
    static void DisplayDecisionEngineView() {
        // Option A: If you have a static method
        // DecisionEngine::DisplayDecisionEngineView();
        
        // Option B: If you need an instance
        // DecisionEngine engine;
        // engine.DisplayView();
        
        // Option C: If you need to pass parameters
        // DecisionEngine::DisplayView("EURUSD", PERIOD_H1);
    }
    
    // Combined display
    static void DisplayAll(const TradePackage &package) {
        DisplayTradePackage(package);
        DisplayDecisionEngineView();
    }
};
```

## Approach 3: Direct Call in OnTick() or OnTimer()

In your main EA's event handlers:

```mql4
// Main EA (Example)
#include "Data/TradePackage.mqh"
#include "Utils/DisplayManager.mqh" // If using Approach 2

// Global/class member
TradePackage g_tradePackage;

// In OnTick() or a timer function
void OnTick() {
    // Your trading logic...
    
    // Display when needed (e.g., on button press or condition)
    if(ShouldDisplay()) {
        // Direct call
        string tpDisplay = g_tradePackage.GenerateDetailedTabularDisplay();
        Logger::DisplaySingleFrame(tpDisplay);
        
        // Or using DisplayManager
        DisplayManager::DisplayTradePackage(g_tradePackage);
    }
}

// Or create a custom function
void ShowCurrentAnalysis() {
    // 1. Display Trade Package
    string tpText = g_tradePackage.GenerateDetailedTabularDisplay();
    Logger::DisplaySingleFrame("=== TRADE PACKAGE ===");
    Logger::DisplaySingleFrame(tpText);
    
    // 2. Display Decision Engine View
    // This depends on how your DecisionEngine is structured
    // If it has a static method:
    // DecisionEngine::DisplayDecisionEngineView();
    
    // If it's an instance:
    // if(g_decisionEngine != NULL) {
    //     g_decisionEngine.DisplayView();
    // }
}
```

## Approach 4: Event-Driven Display

Add keyboard shortcuts or chart events:

```mql4
// In OnChartEvent()
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_KEYDOWN) {
        // F2 key to display Trade Package
        if(lparam == 113) { // F2 key code
            DisplayTradePackageNow();
        }
        // F3 key to display Decision Engine
        else if(lparam == 114) { // F3 key code
            DisplayDecisionEngineNow();
        }
    }
}

void DisplayTradePackageNow() {
    TradePackage currentPackage; // Or use your existing instance
    // Populate with current data...
    string display = currentPackage.GenerateDetailedTabularDisplay();
    Comment(display); // Or use your Logger
}

void DisplayDecisionEngineNow() {
    // Call your decision engine display method
}
```

## Quick Solution for TradePackage:

Since you already have the working `GenerateDetailedTabularDisplay()` method in `TradePackage`, you can simply:

1. **Make sure the method is public** (it is, since it's in the class definition)
2. **Create a TradePackage instance** in your main EA
3. **Populate it with data** (from your modules)
4. **Call the method** when needed

```mql4
// Minimal working example in main EA:
#include <Data/TradePackage.mqh>

TradePackage g_currentPackage;

void UpdateAndDisplayPackage() {
    // 1. Update package with current data (from your modules)
    g_currentPackage.SetMTFData(...);
    g_currentPackage.SetPOIData(...);
    // ... set other data
    
    // 2. Calculate and validate
    g_currentPackage.CalculateDirectionAnalysis();
    g_currentPackage.CalculateWeightedScore();
    g_currentPackage.ValidatePackage();
    
    // 3. Display
    string display = g_currentPackage.GenerateDetailedTabularDisplay();
    Logger::DisplaySingleFrame(display);
}
```

## For Decision Engine:

You need to check what method is available. If you don't have `DisplayDecisionEngineView()`, look for similar display methods like:
- `Display()`
- `ShowView()`
- `GenerateDisplay()`
- `GetDisplayText()`

## Summary:

1. **TradePackage**: Already has `GenerateDetailedTabularDisplay()` - just call it on an instance
2. **Decision Engine**: Need to check the exact method name and how to call it
3. **Integration**: Either call directly or create a DisplayManager helper class

**Which approach do you prefer?** If you can show me your Decision Engine class definition, I can give you the exact code to call its display method.


+++++++++++++++++++++++++++++++++++++++++++

could you clear all displays here and call them directly in the most simple way

//+------------------------------------------------------------------+
//|                           mk$.mq5                                |
//|                    Enhanced Trading EA with 6-Component Analysis |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property version   "3.00"
#property strict

// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED_EA = true;

void DebugLogEA(string context, string message) {
   if(DEBUG_ENABLED_EA) Logger::Log("DEBUG-EA-" + context, message, true, true);
}

// ============================================================
// INCLUDES
// ============================================================
#include "include/Utils/Logger.mqh"
#include "include/Data/IndicatorManager.mqh"
#include "include/Core/DecisionEngine.mqh"
#include "include/Data/POIModule.mqh"
#include "include/Core/PackageManager.mqh"

// ============================================================
// INPUT PARAMETERS
// ============================================================
input int TimerInterval = 5;
input bool POI_Enabled = true;

// Package Manager Configuration
input bool UseMTFModule = true;
input bool UsePOIModule = true;
input bool UseVolumeModule = true;
input bool UseRSIModule = true;
input bool UseMACDModule = true;
input bool UseCandlePatternsModule = true;

input int PackageUpdateInterval = 10;

// Decision Engine Configuration
input bool UseDecisionEngine = true;
input double MaxRiskPerTrade = 1.0;
input int PositionCooldownMinutes = 30;
input bool UseAutoExecution = true;

// ============================================================
// GLOBAL DECLARATIONS
// ============================================================
IndicatorManager* g_indicatorManager = NULL;
DecisionEngine decisionEngine;
POIModule poiModule;
TradePackageManager* g_packageManager = NULL;

// ============================================================
// DISPLAY TOGGLE SYSTEM (NUMBER KEYS 0-9)
// ============================================================

enum DISPLAY_MODE {
    DISPLAY_NONE = 0,
    DISPLAY_DECISION_ENGINE_ONLY = 1,
    DISPLAY_TRADE_PACKAGE_ONLY = 2,
    DISPLAY_COMPONENTS_VIEW = 3,
    DISPLAY_DECISION_ENGINE_VIEW = 4,
    DISPLAY_COMBINED_VIEW = 5,
    DISPLAY_TRADE_PACKAGE_TABULAR = 6,
    DISPLAY_TRADE_PACKAGE_DETAILED = 7,
    DISPLAY_POI = 8,
    DISPLAY_ALL_MODULES = 9
};

DISPLAY_MODE g_currentDisplay = DISPLAY_NONE;

// ============================================================
// CHART EVENT HANDLER FOR KEYBOARD SHORTCUTS
// ============================================================
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam) {
    // Handle keyboard events
    if(id == CHARTEVENT_KEYDOWN) {  // Use CHARTEVENT_KEYDOWN instead of CHART_EVENT_KEYDOWN
        int keyCode = (int)lparam;
        
        // Handle number keys 0-9
        if(keyCode >= '0' && keyCode <= '9') {
            int displayNum = keyCode - '0';
            g_currentDisplay = (DISPLAY_MODE)displayNum;
            
            // Update display immediately
            UpdateDisplay();
            
            PrintFormat("Display mode changed to: %d", displayNum);
        }
    }
}

// ============================================================
// SIMPLE DISPLAY UPDATER - CALLS EXISTING FUNCTIONS
// ============================================================
void UpdateDisplay() {
    // DO NOT clear comment here - let the functions handle it
    
    switch(g_currentDisplay) {
        case DISPLAY_NONE:
            Comment("");  // Clear only for NONE mode
            return;
            
        case DISPLAY_DECISION_ENGINE_ONLY:
            decisionEngine.DisplayDecisionEngineOnly();
            break;
            
        case DISPLAY_TRADE_PACKAGE_ONLY:
            if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
                TradePackage package = g_packageManager.GetTradePackage(false);
                package.Display();
            }
            break;
            
        case DISPLAY_COMPONENTS_VIEW:
            decisionEngine.DisplayComponentsView();
            break;
            
        case DISPLAY_DECISION_ENGINE_VIEW:
            decisionEngine.DisplayDecisionEngineView();
            break;
            
        case DISPLAY_COMBINED_VIEW:
            decisionEngine.DisplayCombinedView();
            break;
            
        case DISPLAY_TRADE_PACKAGE_TABULAR:
            if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
                TradePackage package = g_packageManager.GetTradePackage(false);
                package.DisplayTabular();
            }
            break;
            
        case DISPLAY_TRADE_PACKAGE_DETAILED:
            if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
                TradePackage package = g_packageManager.GetTradePackage(false);
                package.DisplayDetailedTabular();
            }
            break;
            
        case DISPLAY_POI:
            // Simple POI display
            if(POI_Enabled) {
                string display = "=== POI MODULE ===\n";
                display += "Status: ACTIVE\n";
                display += "Symbol: " + Symbol() + "\n";
                display += "Time: " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n";
                display += "\nPress 0 to clear, 1-9 for other views";
                Comment(display);
            } else {
                Comment("POI Module: DISABLED\nEnable in inputs\nPress 0-9 to switch views");
            }
            break;
            
        case DISPLAY_ALL_MODULES:
            {
                string display = "=== ALL MODULES ===\n";
                display += TimeToString(TimeCurrent(), TIME_SECONDS) + "\n\n";
                
                // Decision Engine status
                display += "DECISION ENGINE:\n";
                display += decisionEngine.GetStatus() + "\n\n";
                
                // Trade Package status
                display += "TRADE PACKAGE:\n";
                if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
                    TradePackage package = g_packageManager.GetTradePackage(false);
                    if(package.isValid) {
                        display += StringFormat("Confidence: %.1f%%\n", package.overallConfidence);
                        display += StringFormat("Direction: %s\n", package.directionAnalysis.dominantDirection);
                    } else {
                        display += "No valid package\n";
                    }
                } else {
                    display += "Package Manager not available\n";
                }
                
                // POI status
                display += "\nPOI MODULE:\n";
                display += POI_Enabled ? "ACTIVE" : "DISABLED";
                
                display += "\n\nType 0-9 to switch views";
                Comment(display);
            }
            break;
    }
}

// ============================================================
// INITIALIZATION FUNCTION
// ============================================================
int OnInit()
{
    Print("=== INITIALIZING mk$ EA v3.00 ===");
    
    // Initialize Logger
    if(!Logger::Initialize()) {
        Print("ERROR: Failed to initialize Logger");
        return INIT_FAILED;
    }
    
    // Create IndicatorManager
    g_indicatorManager = new IndicatorManager();
    if(!g_indicatorManager.Initialize()) {
        Print("ERROR: Failed to initialize IndicatorManager");
        delete g_indicatorManager;
        return INIT_FAILED;
    }
    
    // Create PackageManager
    g_packageManager = new TradePackageManager();
    if(g_packageManager == NULL) {
        Print("ERROR: Failed to create TradePackageManager");
        delete g_indicatorManager;
        return INIT_FAILED;
    }
    
    // Configure PackageManager
    g_packageManager.ConfigureModules(
        UseMTFModule, UsePOIModule, UseVolumeModule, 
        UseRSIModule, UseMACDModule, UseCandlePatternsModule
    );
    
    if(!g_packageManager.Initialize(Symbol(), Period(), g_indicatorManager)) {
        Print("ERROR: Failed to initialize TradePackageManager");
        delete g_packageManager;
        delete g_indicatorManager;
        return INIT_FAILED;
    }
    
    // Initialize POI Module
    if(POI_Enabled && !poiModule.Initialize(Symbol(), true, 2.0, 3)) {
        Print("WARNING: Failed to initialize POI Module");
    }
    
    // Initialize DecisionEngine
    if(!decisionEngine.Initialize("mk$ 6-Component Mode", 10000, UseAutoExecution)) {
        Print("ERROR: Failed to initialize DecisionEngine");
        delete g_packageManager;
        delete g_indicatorManager;
        return INIT_FAILED;
    }
    
    // Configure DecisionEngine
    DecisionParams params;
    params.riskPercent = MaxRiskPerTrade;
    params.cooldownMinutes = PositionCooldownMinutes;
    params.buyConfidenceThreshold = 65.0;
    params.sellConfidenceThreshold = 65.0;
    
    if(!decisionEngine.RegisterSymbol(Symbol(), params)) {
        Print("ERROR: Failed to register symbol");
        delete g_packageManager;
        delete g_indicatorManager;
        decisionEngine.Deinitialize();
        return INIT_FAILED;
    }
    
    // Set up timer
    if(TimerInterval > 0) EventSetTimer(TimerInterval);
    
    // Enable keyboard events
    ChartSetInteger(0, CHART_EVENT_KEYDOWN, true);
    
    // Show keyboard shortcuts help
    Print("\n=== DISPLAY CONTROLS ===");
    Print("Press number keys 0-9:");
    Print("0: Clear display");
    Print("1: Decision Engine Only");
    Print("2: Trade Package Only");
    Print("3: Components View");
    Print("4: Decision Engine View");
    Print("5: Combined View");
    Print("6: Trade Package Tabular");
    Print("7: Trade Package Detailed");
    Print("8: POI Display");
    Print("9: All Modules Summary");
    Print("==============================\n");
    
    // Start with Decision Engine display
    g_currentDisplay = DISPLAY_DECISION_ENGINE_ONLY;
    
    Print("✅ mk$ EA v3.00 INITIALIZED - Press 0-9 to toggle displays");
    return INIT_SUCCEEDED;
}

// ============================================================
// TICK HANDLER
// ============================================================
void OnTick()
{
    static datetime lastPackageUpdate = 0;
    static datetime lastDisplayUpdate = 0;
    
    // POI updates
    if(POI_Enabled) poiModule.OnTick();
    
    // PackageManager updates
    if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
        g_packageManager.OnTick();
        
        // Generate new package periodically
        if(TimeCurrent() - lastPackageUpdate >= PackageUpdateInterval) {
            lastPackageUpdate = TimeCurrent();
            TradePackage freshPackage = g_packageManager.GetTradePackage(true);
            
            // Send MINIMAL interface to DecisionEngine
            if(UseDecisionEngine && freshPackage.isValid) {
                DecisionEngineInterface deInterface;
                
                // ONLY fields that DecisionEngine ACTUALLY needs:
                deInterface.symbol = Symbol();
                deInterface.overallConfidence = freshPackage.overallConfidence;
                deInterface.analysisTime = TimeCurrent();
                deInterface.isValid = freshPackage.isValid;
                
                // Get direction from available field
                if(freshPackage.directionAnalysis.dominantDirection != "") {
                    deInterface.dominantDirection = freshPackage.directionAnalysis.dominantDirection;
                } else {
                    deInterface.dominantDirection = "NEUTRAL";
                }
                
                // Set defaults for other fields (DecisionEngine can work with defaults)
                deInterface.weightedScore = freshPackage.overallConfidence;
                deInterface.orderType = (deInterface.dominantDirection == "BULLISH") ? ORDER_TYPE_BUY : 
                                       (deInterface.dominantDirection == "BEARISH") ? ORDER_TYPE_SELL : 
                                       ORDER_TYPE_BUY_LIMIT;
                deInterface.signalConfidence = freshPackage.overallConfidence;
                deInterface.signalReason = "6-Component Analysis";
                
                // Trade setup defaults (DecisionEngine will calculate if needed)
                deInterface.entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                deInterface.stopLoss = 0;
                deInterface.takeProfit1 = 0;
                deInterface.positionSize = 0.01;
                
                // MTF defaults
                deInterface.mtfBullishCount = (deInterface.dominantDirection == "BULLISH") ? 4 : 2;
                deInterface.mtfBearishCount = (deInterface.dominantDirection == "BEARISH") ? 4 : 2;
                deInterface.mtfWeight = freshPackage.overallConfidence;
                
                // Send MINIMAL interface to DecisionEngine
                decisionEngine.ProcessTradePackage(deInterface);
            }
        }
    }
    
    // DecisionEngine updates
    decisionEngine.OnTick();
    
    // Update display less frequently (every 2 seconds) to prevent blinking
    if(TimeCurrent() - lastDisplayUpdate >= 2) {
        lastDisplayUpdate = TimeCurrent();
        UpdateDisplay();
    }
}

// ============================================================
// TIMER HANDLER
// ============================================================
void OnTimer()
{
    if(POI_Enabled) poiModule.OnTimer();
    
    if(g_packageManager != NULL && g_packageManager.IsInitialized()) {
        g_packageManager.OnTimer();
    }
    
    if(g_indicatorManager != NULL) {
        g_indicatorManager.OnTimer();
    }
    
    decisionEngine.OnTimer();
}

// ============================================================
// CLEANUP FUNCTION
// ============================================================
void OnDeinit(const int reason)
{
    Print("=== DEINITIALIZING mk$ EA v3.00 ===");
    
    EventKillTimer();
    
    // Clear any display
    Comment("");
    
    if(g_packageManager != NULL) delete g_packageManager;
    if(g_indicatorManager != NULL) {
        g_indicatorManager.Deinitialize();
        delete g_indicatorManager;
    }
    
    decisionEngine.Deinitialize();
    Logger::Shutdown();
    
    Print("✅ DEINITIALIZATION COMPLETE");
}

// ============================================================
// TRADE TRANSACTION HANDLER
// ============================================================
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    if(POI_Enabled) poiModule.OnTradeTransaction(trans, request, result);
    decisionEngine.OnTradeTransaction(trans, request, result);
}
