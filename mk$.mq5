//+------------------------------------------------------------------+
//| Safe Metals EA v4.5 - Ultra-Sensitive Trend Following           |
//+------------------------------------------------------------------+
#property version "4.5"
#property strict

#include <Trade/Trade.mqh>
#include <Arrays/ArrayString.mqh>
#include "include/config/inputs.mqh"
#include "include/config/GlobalVariables.mqh"
#include "include/config/structures.mqh"
#include "include/core/SystemInitializer.mqh"
#include "include/core/DashboardManager.mqh"


datetime lastBarTime = 0;
ENUM_TIMEFRAMES healthReportTF = PERIOD_M15; // Report every hour

// Add global variables:
datetime lastPOIUpdate = 0;
int POIUpdateSeconds = 900; // Update every 5 seconds

//+------------------------------------------------------------------+
//| Expert initialization function - SIMPLIFIED                     |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!InitializeEA())
    {
        Print("EA_INIT: Failed to initialize EA");
        return INIT_FAILED;
    }
    
    // Return success when initialization succeeds
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| MODIFIED OnTick for ULTRA-SENSITIVE TRADING                    |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar on report timeframe
    datetime currentBarTime = iTime(_Symbol, healthReportTF, 0);
    if(currentBarTime != lastBarTime)
    {
        GetHealthStatusReport();
        lastBarTime = currentBarTime;
    }

    // Display the dashboard ON THE CHART
    string dashboard = GetFullDashboard();
    Comment(dashboard);
    
    // Update POI every 5 seconds
    if(TimeCurrent() - lastPOIUpdate >= POIUpdateSeconds)
    {
        UpdatePOIDisplay();
        lastPOIUpdate = TimeCurrent();
        // Optional: Print for debugging
        // Print("POI Updated at: ", TimeToString(TimeCurrent(), TIME_SECONDS));
    }

    // exe ute trading logic
    ExecuteTradingLogic();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    CleanupEA();
}