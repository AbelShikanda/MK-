//+------------------------------------------------------------------+
//| SystemInitializer.mqh - Core EA Setup                           |
//| Merged from: init.mqh + HealthMonitor.mqh                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../config/structures.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../utils/TradeUtils.mqh"
#include "../market/trend/MultiTimeframe.mqh"
#include "../market/detectors/ReversalDetector.mqh"

// ================================================================
// SECTION 1: SYSTEM INITIALIZATION (from init.mqh)
// ================================================================

//+------------------------------------------------------------------+
//| Initialize the entire EA                                        |
//+------------------------------------------------------------------+
bool InitializeEA()
{
    Print("========================================");
    Print("  SAFE METALS EA v4.5 - INITIALIZATION  ");
    Print("========================================");
    
    // Step 0: Check if we're in Strategy Tester
    bool isTester = MQLInfoInteger(MQL_TESTER);
    bool isVisual = MQLInfoInteger(MQL_VISUAL_MODE);
    
    if(isTester || isVisual)
    {
        Print("Running in Strategy Tester/Visual Mode");
        Print("Only using current symbol: ", _Symbol);
        
        // In tester, only use the current symbol
        totalSymbols = 1;
        ArrayResize(activeSymbols, 1);
        activeSymbols[0] = _Symbol;
    }
    else
    {
        // Step 1: Get account info
        accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        Print("Step 1: Account Balance: $", DoubleToString(accountBalance, 2));
        
        // Step 2: Determine symbols to trade (LIVE trading only)
        string selectedSymbols[];
        double minScore = 60.0;
        int symbolCount = DetermineActiveSymbols(selectedSymbols, minScore);

        // ========== CRITICAL FIX ==========
        // Copy selected symbols to global arrays
        if(symbolCount > 0)
        {
            totalSymbols = symbolCount;
            ArrayResize(activeSymbols, totalSymbols);
            
            for(int i = 0; i < totalSymbols; i++)
            {
                activeSymbols[i] = selectedSymbols[i];
            }
            
            Print("Step 2: Selected ", totalSymbols, " symbols");
            
            // Log what we selected
            for(int i = 0; i < totalSymbols; i++)
            {
                Print("  ", i+1, ". ", activeSymbols[i]);
            }
        }
        else
        // ========== END FIX ==========

        if(totalSymbols == 0)
        {
            Print("✗ ERROR: No symbols available for trading");
            return false;
        }
        Print("Step 2: Selected ", totalSymbols, " symbols");
    }
    
    // Step 3: Initialize arrays
    InitializeAllArrays();
    InitializeIndicatorArrays();
    Print("Step 3: Arrays initialized");
    
    InitDivergenceTracker();
    
    // Step 4: Initialize daily tracking
    InitializeDailyTracking();
    Print("Step 4: Daily tracking initialized");
    
    // Step 5: Create indicators
    if(!CreateAllIndicatorsForSymbols())
    {
        Print("✗ ERROR: Indicator creation failed");
        return false;
    }
    Print("Step 5: Indicators created");
    
    // Step 6: Configure trade settings
    trade.SetExpertMagicNumber(12345);
    trade.SetDeviationInPoints(10);
    // UpdateTradingParameters();
    Print("Step 6: Trade settings configured");
    
    // Step 7: Initialize health monitoring
    InitializeHealthMonitor();
    
    Print("✓ INITIALIZATION COMPLETE");
    Print("========================================");
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize all dynamic arrays                                   |
//+------------------------------------------------------------------+
void InitializeAllArrays()
{
    // Signal tracking// Instead, just initialize the values:
    for(int i = 0; i < 100; i++)
    {
        signalHistory[i].symbol = "";
        signalHistory[i].type = "";
        signalHistory[i].strength = 0.0;
        signalHistory[i].timestamp = 0;
    }
    
    // Make sure maxSignalHistory matches the actual array size
    maxSignalHistory = 100;  // IMPORTANT!
    
    // Position tracking
    ArrayResize(positionTracker, 100);
    
    // Trend tracking
    ArrayResize(trendHealth, 10);
    ArrayResize(trendMomentum, 10);
    
    Print("INIT: All dynamic arrays initialized");
}

//+------------------------------------------------------------------+
//| Initialize indicator arrays                                     |
//+------------------------------------------------------------------+
void InitializeIndicatorArrays()
{
    // M5 arrays
    ArrayResize(veryFastMA_M5, totalSymbols);
    ArrayResize(fastMA_M5, totalSymbols);
    ArrayResize(mediumMA_M5, totalSymbols);
    ArrayResize(slowMA_M5, totalSymbols);
    ArrayResize(rsi_M5, totalSymbols);
    ArrayResize(stoch_M5, totalSymbols);
    ArrayResize(macd_M5, totalSymbols);
    
    // M15 arrays
    ArrayResize(fastMA_M15, totalSymbols);
    ArrayResize(mediumMA_M15, totalSymbols);
    ArrayResize(slowMA_M15, totalSymbols);
    ArrayResize(rsi_M15, totalSymbols);
    ArrayResize(stoch_M15, totalSymbols);
    ArrayResize(macd_M15, totalSymbols);
    
    // H1 arrays
    ArrayResize(fastMA_H1, totalSymbols);
    ArrayResize(mediumMA_H1, totalSymbols);
    ArrayResize(slowMA_H1, totalSymbols);
    ArrayResize(rsi_H1, totalSymbols);
    ArrayResize(stoch_H1, totalSymbols);
    ArrayResize(macd_H1, totalSymbols);
    
    // Other indicators
    ArrayResize(longTermMA_H4, totalSymbols);
    ArrayResize(longTermMA_LT, totalSymbols);
    ArrayResize(atr_handles, totalSymbols);
    ArrayResize(lastTradeCandle, totalSymbols);
    ArrayResize(atr_handles_M5, totalSymbols);
    ArrayResize(atr_handles_M15, totalSymbols);
    
    // Initialize to -1 (invalid handle)
    InitializeArrayValues();
    
    Print("INIT: Indicator arrays initialized for ", totalSymbols, " symbols");
}

//+------------------------------------------------------------------+
//| Initialize array values to default                              |
//+------------------------------------------------------------------+
void InitializeArrayValues()
{
    // Initialize all indicator arrays to -1
    ArrayInitialize(veryFastMA_M5, -1);
    ArrayInitialize(fastMA_M5, -1);
    ArrayInitialize(mediumMA_M5, -1);
    ArrayInitialize(slowMA_M5, -1);
    ArrayInitialize(rsi_M5, -1);
    ArrayInitialize(stoch_M5, -1);
    ArrayInitialize(macd_M5, -1);
    
    ArrayInitialize(fastMA_M15, -1);
    ArrayInitialize(mediumMA_M15, -1);
    ArrayInitialize(slowMA_M15, -1);
    ArrayInitialize(rsi_M15, -1);
    ArrayInitialize(stoch_M15, -1);
    ArrayInitialize(macd_M15, -1);
    
    ArrayInitialize(fastMA_H1, -1);
    ArrayInitialize(mediumMA_H1, -1);
    ArrayInitialize(slowMA_H1, -1);
    ArrayInitialize(rsi_H1, -1);
    ArrayInitialize(stoch_H1, -1);
    ArrayInitialize(macd_H1, -1);
    
    ArrayInitialize(longTermMA_H4, -1);
    ArrayInitialize(longTermMA_LT, -1);
    ArrayInitialize(atr_handles, -1);
    ArrayInitialize(lastTradeCandle, 0);
    
    ArrayInitialize(atr_handles_M5, -1);
    ArrayInitialize(atr_handles_M15, -1);
}

//+------------------------------------------------------------------+
//| Create M5 indicators for a symbol                               |
//+------------------------------------------------------------------+
bool CreateM5Indicators(string symbol, int index)
{
    veryFastMA_M5[index] = iMA(symbol, PERIOD_M5, VeryFastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    fastMA_M5[index] = iMA(symbol, PERIOD_M5, FastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    mediumMA_M5[index] = iMA(symbol, PERIOD_M5, MediumMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    slowMA_M5[index] = iMA(symbol, PERIOD_M5, SlowMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsi_M5[index] = iRSI(symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    stoch_M5[index] = iStochastic(symbol, PERIOD_M5, Stoch_K_Period, Stoch_D_Period, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
    macd_M5[index] = iMACD(symbol, PERIOD_M5, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    
    return (veryFastMA_M5[index] != -1 && fastMA_M5[index] != -1);
}

//+------------------------------------------------------------------+
//| Create M15 indicators for a symbol                              |
//+------------------------------------------------------------------+
bool CreateM15Indicators(string symbol, int index)
{
    fastMA_M15[index] = iMA(symbol, PERIOD_M15, FastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    mediumMA_M15[index] = iMA(symbol, PERIOD_M15, MediumMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    slowMA_M15[index] = iMA(symbol, PERIOD_M15, SlowMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsi_M15[index] = iRSI(symbol, PERIOD_M15, RSI_Period, PRICE_CLOSE);
    stoch_M15[index] = iStochastic(symbol, PERIOD_M15, Stoch_K_Period, Stoch_D_Period, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
    macd_M15[index] = iMACD(symbol, PERIOD_M15, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    
    return (fastMA_M15[index] != -1 && mediumMA_M15[index] != -1);
}

//+------------------------------------------------------------------+
//| Create H1 indicators for a symbol                               |
//+------------------------------------------------------------------+
bool CreateH1Indicators(string symbol, int index)
{
    fastMA_H1[index] = iMA(symbol, PERIOD_H1, FastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    mediumMA_H1[index] = iMA(symbol, PERIOD_H1, MediumMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    slowMA_H1[index] = iMA(symbol, PERIOD_H1, SlowMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsi_H1[index] = iRSI(symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
    stoch_H1[index] = iStochastic(symbol, PERIOD_H1, Stoch_K_Period, Stoch_D_Period, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
    macd_H1[index] = iMACD(symbol, PERIOD_H1, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    
    return (fastMA_H1[index] != -1 && mediumMA_H1[index] != -1);
}

//+------------------------------------------------------------------+
//| Create other indicators for a symbol                            |
//+------------------------------------------------------------------+
bool CreateOtherIndicators(string symbol, int index)
{
    longTermMA_H4[index] = iMA(symbol, PERIOD_H4, LongTermMA_Period, 0, MODE_SMA, PRICE_CLOSE);
    longTermMA_LT[index] = iMA(symbol, PERIOD_H1, LongTermMA_Period, 0, MODE_SMA, PRICE_CLOSE);
    atr_handles_M5[index] = iATR(symbol, PERIOD_M5, ATR_Period);
    atr_handles_M15[index] = iATR(symbol, PERIOD_M15, ATR_Period);
    lastTradeCandle[index] = 0;
    
    // Check all handles were created
    if(atr_handles_M5[index] == INVALID_HANDLE || atr_handles_M15[index] == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create ATR handles for ", symbol);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Create all indicators for all symbols                           |
//+------------------------------------------------------------------+
bool CreateAllIndicatorsForSymbols()
{
    bool allSuccess = true;
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        bool symbolSuccess = true;
        
        symbolSuccess = symbolSuccess && CreateM5Indicators(symbol, i);
        symbolSuccess = symbolSuccess && CreateM15Indicators(symbol, i);
        symbolSuccess = symbolSuccess && CreateH1Indicators(symbol, i);
        symbolSuccess = symbolSuccess && CreateOtherIndicators(symbol, i);
        
        if(symbolSuccess)
            Print("INIT: Indicators created for ", symbol);
        else
        {
            Print("INIT_ERROR: Failed to create indicators for ", symbol);
            allSuccess = false;
        }
    }
    
    return allSuccess;
}

//+------------------------------------------------------------------+
//| SECTION 2: DAILY TRACKING                                       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Initialize daily tracking system                                |
//+------------------------------------------------------------------+
void InitializeDailyTracking()
{
    // Reset to start of day
    MqlDateTime today;
    TimeToStruct(TimeCurrent(), today);
    today.hour = 0;
    today.min = 0;
    today.sec = 0;
    dailyResetTime = StructToTime(today);
    
    // Reset daily values
    dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dailyProfitCash = 0;
    dailyProfitPips = 0;
    dailyDrawdownCash = 0;
    dailyTradesCount = 0;
    dailyLimitReached = false;
    
    Print("INIT: Daily tracking initialized");
}

//+------------------------------------------------------------------+
//| Update daily P/L tracking                                       |
//+------------------------------------------------------------------+
void UpdateDailyTracking()
{
    datetime now = TimeCurrent();
    if(now >= dailyResetTime + 86400)
    {
        InitializeDailyTracking();
    }
    
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    dailyProfitCash = currentBalance - dailyStartBalance;
    dailyDrawdownCash = MathMax(0, dailyStartBalance - currentEquity);
    
    if(EnableDailyLimits)
    {
        if(dailyProfitCash >= DailyProfitLimitCash)
        {
            dailyLimitReached = true;
            Print("DAILY_LIMIT: Daily profit limit reached: $", DoubleToString(dailyProfitCash, 2), 
                  " >= $", DoubleToString(DailyProfitLimitCash, 2));
        }
        
        if(dailyDrawdownCash >= DailyDrawdownLimitCash)
        {
            dailyLimitReached = true;
            Print("DAILY_LIMIT: Daily drawdown limit reached: $", DoubleToString(dailyDrawdownCash, 2), 
                  " >= $", DoubleToString(DailyDrawdownLimitCash, 2));
        }
    }
}

//+------------------------------------------------------------------+
//| SECTION 3: CLEANUP FUNCTIONS                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Cleanup all resources on shutdown                               |
//+------------------------------------------------------------------+
void CleanupEA()
{
    Print("CLEANUP: Releasing all resources...");
    
    // Release all indicator handles
    for(int i = 0; i < totalSymbols; i++)
    {
        if(veryFastMA_M5[i] != -1) { IndicatorRelease(veryFastMA_M5[i]); veryFastMA_M5[i] = -1; }
        if(fastMA_M5[i] != -1) { IndicatorRelease(fastMA_M5[i]); fastMA_M5[i] = -1; }
        if(mediumMA_M5[i] != -1) { IndicatorRelease(mediumMA_M5[i]); mediumMA_M5[i] = -1; }
        if(slowMA_M5[i] != -1) { IndicatorRelease(slowMA_M5[i]); slowMA_M5[i] = -1; }
        if(rsi_M5[i] != -1) { IndicatorRelease(rsi_M5[i]); rsi_M5[i] = -1; }
        if(stoch_M5[i] != -1) { IndicatorRelease(stoch_M5[i]); stoch_M5[i] = -1; }
        if(macd_M5[i] != -1) { IndicatorRelease(macd_M5[i]); macd_M5[i] = -1; }
        
        if(fastMA_M15[i] != -1) { IndicatorRelease(fastMA_M15[i]); fastMA_M15[i] = -1; }
        if(mediumMA_M15[i] != -1) { IndicatorRelease(mediumMA_M15[i]); mediumMA_M15[i] = -1; }
        if(slowMA_M15[i] != -1) { IndicatorRelease(slowMA_M15[i]); slowMA_M15[i] = -1; }
        if(rsi_M15[i] != -1) { IndicatorRelease(rsi_M15[i]); rsi_M15[i] = -1; }
        if(stoch_M15[i] != -1) { IndicatorRelease(stoch_M15[i]); stoch_M15[i] = -1; }
        if(macd_M15[i] != -1) { IndicatorRelease(macd_M15[i]); macd_M15[i] = -1; }
        
        if(fastMA_H1[i] != -1) { IndicatorRelease(fastMA_H1[i]); fastMA_H1[i] = -1; }
        if(mediumMA_H1[i] != -1) { IndicatorRelease(mediumMA_H1[i]); mediumMA_H1[i] = -1; }
        if(slowMA_H1[i] != -1) { IndicatorRelease(slowMA_H1[i]); slowMA_H1[i] = -1; }
        if(rsi_H1[i] != -1) { IndicatorRelease(rsi_H1[i]); rsi_H1[i] = -1; }
        if(stoch_H1[i] != -1) { IndicatorRelease(stoch_H1[i]); stoch_H1[i] = -1; }
        if(macd_H1[i] != -1) { IndicatorRelease(macd_H1[i]); macd_H1[i] = -1; }
        
        if(longTermMA_H4[i] != -1) { IndicatorRelease(longTermMA_H4[i]); longTermMA_H4[i] = -1; }
        if(longTermMA_LT[i] != -1) { IndicatorRelease(longTermMA_LT[i]); longTermMA_LT[i] = -1; }
        if(atr_handles[i] != -1) { IndicatorRelease(atr_handles[i]); atr_handles[i] = -1; }
        
        if(atr_handles_M5[i] != -1) { IndicatorRelease(atr_handles_M5[i]); atr_handles_M5[i] = -1; }
        if(atr_handles_M15[i] != -1) { IndicatorRelease(atr_handles_M15[i]); atr_handles_M15[i] = -1; }
    }
    
    Print("CLEANUP: All resources released");
}

//+------------------------------------------------------------------+
//| Check all indicator handles                                     |
//+------------------------------------------------------------------+
void CheckAllIndicatorHandles()
{
    Print("=== CHECKING ALL INDICATOR HANDLES ===");
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        Print("Symbol: ", symbol);
        Print("  M5 ATR Handle: ", atr_handles_M5[i], " (", 
              atr_handles_M5[i] == INVALID_HANDLE ? "INVALID" : "OK", ")");
        Print("  M15 ATR Handle: ", atr_handles_M15[i], " (", 
              atr_handles_M15[i] == INVALID_HANDLE ? "INVALID" : "OK", ")");
        
        // Test copy from each handle
        double testValue[1];
        int copiedM5 = CopyBuffer(atr_handles_M5[i], 0, 0, 1, testValue);
        Print("  M5 Copy result: ", copiedM5, " Value: ", testValue[0]);
        
        int copiedM15 = CopyBuffer(atr_handles_M15[i], 0, 0, 1, testValue);
        Print("  M15 Copy result: ", copiedM15, " Value: ", testValue[0]);
    }
    
    Print("=== END HANDLE CHECK ===");
}

// ================================================================
// SECTION 4: HEALTH MONITORING (from HealthMonitor.mqh)
// ================================================================

//+------------------------------------------------------------------+
//| Log Error Helper Function                                       |
//+------------------------------------------------------------------+
void LogError(string context, string symbol)
{
    Print("HealthMonitor Error: ", context, " failed for ", symbol, 
          ", error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Monitor ATR Handles - Prevents timeout/stale handles           |
//+------------------------------------------------------------------+
void MonitorATRHandles()
{
    static int debugCounter = 0;
    if(debugCounter++ % 100 == 0)
    {
        for(int i = 0; i < totalSymbols; i++)
        {
            string symbol = activeSymbols[i];
            int pos = ArrayPosition(symbol);
            if(pos >= 0)
            {
                // Always check M5 (both strategies)
                if(atr_handles_M5[pos] != INVALID_HANDLE)
                {
                    double atrVal[1];
                    int copied = CopyBuffer(atr_handles_M5[pos], 0, 0, 1, atrVal);
                    if(copied < 0) LogError("M5 ATR", symbol);
                }
                
                // Also check M1 if it exists (scalping)
                // if(atr_handles_M1[pos] != INVALID_HANDLE)
                // {
                //     double atrValM1[1];
                //     int copiedM1 = CopyBuffer(atr_handles_M1[pos], 0, 0, 1, atrValM1);
                //     if(copiedM1 < 0) LogError("M1 ATR", symbol);
                // }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Monitor Account Balance - Updates trading parameters on change  |
//+------------------------------------------------------------------+
void MonitorAccountBalance()
{
    static int tickCount = 0;
    if(tickCount++ % 50 == 0)  // Check more frequently
    {
        double newBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(newBalance != accountBalance)
        {
            accountBalance = newBalance;
            // UpdateTradingParameters();
            
            // Re-evaluate symbols when balance changes
            // DetermineActiveSymbols();
            
            // Optional: Log balance change
            // Print("Balance Monitor: Balance changed to $", accountBalance, 
            //       ", updating trading parameters.");
        }
    }
}

//+------------------------------------------------------------------+
//| Perform All Health Checks - Combined monitoring function        |
//+------------------------------------------------------------------+
void PerformHealthChecks()
{
    MonitorATRHandles();
    MonitorAccountBalance();
}

//+------------------------------------------------------------------+
//| Initialize Health Monitoring                                    |
//+------------------------------------------------------------------+
void InitializeHealthMonitor()
{
    // Print("Health Monitor: Initializing system health monitoring...");
    
    // Perform initial checks
    MonitorATRHandles();
    
    // Set initial balance
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Print("Health Monitor: Initial balance set to $", accountBalance);
}

//+------------------------------------------------------------------+
//| Check Individual Symbol ATR Handle                              |
//+------------------------------------------------------------------+
bool CheckSymbolATRHandle(string symbol)
{
    int pos = ArrayPosition(symbol);
    if(pos >= 0 && atr_handles_M5[pos] != INVALID_HANDLE)
    {
        double atrVal[1];
        int copied = CopyBuffer(atr_handles_M5[pos], 0, 0, 1, atrVal);
        return (copied >= 0);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Health Status Report                                        |
//+------------------------------------------------------------------+
string GetHealthStatusReport()
{
    string report = "=== SYSTEM HEALTH REPORT ===\n";
    
    // Check ATR handles
    report += "ATR Handles Status:\n";
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        bool atrOk = CheckSymbolATRHandle(symbol);
        report += StringFormat("   %s: %s\n", symbol, (atrOk ? "OK" : "FAILED"));
    }
    
    // Account status
    report += "\nAccount Status:\n";
    report += StringFormat("   Balance: $%.2f\n", accountBalance);
    report += StringFormat("   Equity: $%.2f\n", AccountInfoDouble(ACCOUNT_EQUITY));
    
    return report;
}