//+------------------------------------------------------------------+
//| ExposureController.mqh                                          |
//| Risk Exposure Management Module                                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/enums.mqh"
#include "../config/inputs.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/TradeUtils.mqh"
#include "../signals/DirectionManager.mqh"

// ============ EXPOSURE CONTROL CONSTANTS ============
#define MAX_ACCOUNT_EXPOSURE_PERCENT 30.0     // Maximum 30% of account at risk
#define MAX_MARGIN_USAGE_PERCENT 30.0         // Maximum 30% margin usage
#define MIN_MARGIN_LEVEL 200.0                // Never go below 200% margin level
#define MIN_FREE_MARGIN_PERCENT 40.0          // Keep at least 40% free margin buffer
#define EMERGENCY_MARGIN_LEVEL 150.0          // Emergency position reduction level
#define CRITICAL_MARGIN_LEVEL 120.0           // Critical - start closing positions
#define MARGIN_CALL_LEVEL 100.0               // Broker will margin call at this level

#define GOLD_CONTRACT_SIZE 100.0              // 100 oz per standard lot
#define STANDARD_CONTRACT_SIZE 100000.0       // 100,000 units for forex majors

// ============ GLOBAL VARIABLES ============
double g_worstMarginLevel = 1000.0;           // Tracks worst margin level during session
datetime g_lastMarginCheck = 0;

//+------------------------------------------------------------------+
//| Validate Exposure for New Position                              |
//| Main exposure validation function                              |
//+------------------------------------------------------------------+
bool ValidateExposure(const string symbol, const ENUM_POSITION_TYPE positionType,
                     const double volume, const double entryPrice, const double stopLoss,
                     const EXPOSURE_METHOD method = EXPOSURE_RISK_BASED)
{
    // First: Check current margin safety BEFORE any calculations
    if(!CheckCurrentMarginSafety())
    {
        Print("❌ BLOCKED: Current margin level unsafe - cannot add positions");
        return false;
    }
    
    // Second: Check if adding this position would cause margin issues
    if(!CheckMarginSafetyForAddition(symbol, volume))
    {
        Print("❌ BLOCKED: Adding position would risk margin call");
        return false;
    }
    
    // Get account information
    const double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    const double currentFreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    const double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    if(currentEquity <= 0)
    {
        PrintFormat("ERROR: Invalid account equity: $%.2f", currentEquity);
        return false;
    }
    
    // Calculate current margin level
    const double currentMarginLevel = (currentMargin > 0) ?
                                     (currentEquity / currentMargin) * 100.0 : 1000.0;
    
    // Print pre-check information
    Print("=== MARGIN SAFETY PRE-CHECK ===");
    PrintFormat("  Current Margin Level: %.1f%%", currentMarginLevel);
    PrintFormat("  Free Margin: $%.2f (%.1f%%)",
               currentFreeMargin, (currentFreeMargin / currentEquity) * 100.0);
    
    // Calculate position metrics
    const double contractSize = GetContractSize(symbol);
    const double notionalValue = entryPrice * volume * contractSize;
    const double marginRequired = CalculateMarginRequired(symbol, volume);
    const double riskAmount = CalculateRiskAmount(symbol, positionType, volume,
                                                 entryPrice, stopLoss, contractSize);
    
    // Calculate exposure based on selected method
    double exposurePercent = 0.0;
    string exposureType = "";
    
    switch(method)
    {
        case EXPOSURE_MARGIN_BASED:
            exposurePercent = (marginRequired / currentEquity) * 100.0;
            exposureType = "Margin";
            break;
            
        case EXPOSURE_RISK_BASED:
            exposurePercent = (riskAmount / currentEquity) * 100.0;
            exposureType = "Risk";
            break;
            
        case EXPOSURE_NOTIONAL_BASED:
            exposurePercent = (notionalValue / currentEquity) * 100.0;
            exposureType = "Notional";
            break;
    }
    
    // Calculate projected metrics after position addition
    const double projectedMargin = currentMargin + marginRequired;
    const double projectedMarginLevel = (projectedMargin > 0) ?
                                       (currentEquity / projectedMargin) * 100.0 : 1000.0;
    
    const double projectedFreeMargin = currentFreeMargin - marginRequired;
    const double projectedFreeMarginPercent = (currentEquity > 0) ?
                                            (projectedFreeMargin / currentEquity) * 100.0 : 0.0;
    
    const double marginUsagePercent = (marginRequired / currentEquity) * 100.0;
    const double freeMarginPercent = (currentFreeMargin / currentEquity) * 100.0;
    
    // Print exposure debug information
    Print("EXPOSURE_DEBUG: Symbol: ", symbol);
    PrintFormat("  Account Equity: $%.2f | Balance: $%.2f | Margin Used: $%.2f",
               currentEquity, currentBalance, currentMargin);
    PrintFormat("  Current Margin Level: %.1f%%", currentMarginLevel);
    PrintFormat("  Volume: %.3f | Contract Size: %.2f", volume, contractSize);
    PrintFormat("  Notional Value: $%.2f", notionalValue);
    PrintFormat("  New Margin Required: $%.2f", marginRequired);
    PrintFormat("  Projected Margin Level: %.1f%%", projectedMarginLevel);
    PrintFormat("  Projected Free Margin: $%.2f (%.1f%% of equity)",
               projectedFreeMargin, projectedFreeMarginPercent);
    PrintFormat("  Risk Amount (SL): $%.2f (%.1f%% of equity)",
               riskAmount, exposurePercent);
    
    // Apply comprehensive margin safety checks
    bool isWithinLimits = true;
    string rejectionReason = "";
    
    // Check 1: Projected margin level must stay above minimum
    if(projectedMarginLevel < MIN_MARGIN_LEVEL)
    {
        isWithinLimits = false;
        rejectionReason = StringFormat("Projected margin level %.1f%% below minimum %.1f%%",
                                      projectedMarginLevel, MIN_MARGIN_LEVEL);
    }
    // Check 2: Projected free margin buffer
    else if(projectedFreeMarginPercent < MIN_FREE_MARGIN_PERCENT)
    {
        isWithinLimits = false;
        rejectionReason = StringFormat("Projected free margin %.1f%% below minimum %.1f%%",
                                      projectedFreeMarginPercent, MIN_FREE_MARGIN_PERCENT);
    }
    // Check 3: Primary exposure check
    else if(exposurePercent > MAX_ACCOUNT_EXPOSURE_PERCENT)
    {
        isWithinLimits = false;
        rejectionReason = StringFormat("%s exposure %.1f%% exceeds maximum %.1f%%",
                                      exposureType, exposurePercent, MAX_ACCOUNT_EXPOSURE_PERCENT);
    }
    // Check 4: Margin usage check
    else if(marginUsagePercent > MAX_MARGIN_USAGE_PERCENT)
    {
        isWithinLimits = false;
        rejectionReason = StringFormat("Margin usage %.1f%% exceeds maximum %.1f%%",
                                      marginUsagePercent, MAX_MARGIN_USAGE_PERCENT);
    }
    
    // Warning for low current margin level
    if(currentMarginLevel < 250.0)
    {
        PrintFormat("⚠️ WARNING: Current margin level is low: %.1f%%", currentMarginLevel);
    }
    
    // Emergency margin level detection
    if(currentMarginLevel < CRITICAL_MARGIN_LEVEL)
    {
        PrintFormat("‼️ CRITICAL: Margin level %.1f%% - Consider closing positions", currentMarginLevel);
    }
    
    if(!isWithinLimits)
    {
        PrintFormat("❌ FAILED: Margin safety check failed: %s", rejectionReason);
        PrintFormat("   Current: %.1f%%, Projected: %.1f%%",
                   currentMarginLevel, projectedMarginLevel);
        return false;
    }
    
    // Update worst margin level tracker
    if(projectedMarginLevel < g_worstMarginLevel)
    {
        g_worstMarginLevel = projectedMarginLevel;
    }
    
    Print("✅ PASSED: Margin safety check");
    PrintFormat("   Margin Level: %.1f%% → %.1f%%", currentMarginLevel, projectedMarginLevel);
    PrintFormat("   Free Margin: %.1f%% → %.1f%%", freeMarginPercent, projectedFreeMarginPercent);
    PrintFormat("   Worst this session: %.1f%%", g_worstMarginLevel);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Position Exposure                                         |
//| Simplified exposure check for existing positions               |
//+------------------------------------------------------------------+
bool CheckPositionExposure(const string symbol, const double averageEntry, const double totalVolume)
{
    // Get account information
    const double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    // Calculate margin-based exposure
    const double marginRequired = CalculateMarginRequired(symbol, totalVolume);
    const double exposurePercent = (currentEquity > 0) ? (marginRequired / currentEquity) * 100.0 : 0.0;
    
    // Calculate current margin level
    const double currentMarginLevel = (currentMargin > 0) ?
                                     (currentEquity / currentMargin) * 100.0 : 1000.0;
    
    Print("EXPOSURE_CHECK: ", symbol);
    PrintFormat("  Account Equity: $%.2f", currentEquity);
    PrintFormat("  Current Margin Level: %.1f%%", currentMarginLevel);
    PrintFormat("  Volume: %.3f | Avg Entry: %.5f", totalVolume, averageEntry);
    PrintFormat("  Margin Required: $%.2f (%.1f%% of equity)", marginRequired, exposurePercent);
    
    // Enhanced safety check
    if(exposurePercent > MAX_ACCOUNT_EXPOSURE_PERCENT)
    {
        PrintFormat("❌ FAILED: Margin exposure %.1f%% exceeds maximum %.1f%%",
                   exposurePercent, MAX_ACCOUNT_EXPOSURE_PERCENT);
        return false;
    }
    
    // Additional margin level check
    if(currentMarginLevel < MIN_MARGIN_LEVEL)
    {
        PrintFormat("❌ FAILED: Current margin level %.1f%% below minimum %.1f%%",
                   currentMarginLevel, MIN_MARGIN_LEVEL);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Current Margin Safety                                     |
//| Checks current margin level without adding new positions       |
//+------------------------------------------------------------------+
bool CheckCurrentMarginSafety()
{
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(equity <= 0 || margin < 0) return false;
    
    // Calculate margin level
    const double marginLevel = (margin > 0) ? (equity / margin) * 100.0 : 1000.0;
    
    // Update worst margin level
    if(marginLevel < g_worstMarginLevel)
    {
        g_worstMarginLevel = marginLevel;
    }
    
    // Check for critical conditions
    if(marginLevel < MARGIN_CALL_LEVEL)
    {
        PrintFormat("‼️‼️ CRITICAL: Margin call IMMINENT! Level: %.1f%%", marginLevel);
        EmergencyMarginProtection();
        return false;
    }
    
    if(marginLevel < CRITICAL_MARGIN_LEVEL)
    {
        PrintFormat("‼️ CRITICAL: Margin level %.1f%% - Automatic position reduction", marginLevel);
        ReducePositionsForMarginSafety(0.5);  // Close 50% of positions
        return false;
    }
    
    if(marginLevel < EMERGENCY_MARGIN_LEVEL)
    {
        PrintFormat("⚠️ EMERGENCY: Margin level %.1f%% - Reducing exposure", marginLevel);
        ReducePositionsForMarginSafety(0.25);  // Close 25% of positions
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Margin Safety for Position Addition                       |
//| Checks if adding new position would cause margin issues        |
//+------------------------------------------------------------------+
bool CheckMarginSafetyForAddition(const string symbol, const double volume)
{
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    const double newPositionMargin = CalculateMarginRequired(symbol, volume);
    
    // Simple rules for safety
    const double totalMarginAfter = currentMargin + newPositionMargin;
    
    // Rule 1: Never use more than 50% of equity as margin
    if(totalMarginAfter > equity * 0.5)
    {
        PrintFormat("❌ Would use %.1f%% of equity as margin (max 50%%)", 
                   (totalMarginAfter / equity) * 100.0);
        return false;
    }
    
    // Rule 2: Keep at least $30 free margin
    if(freeMargin - newPositionMargin < 30.0)
    {
        Print("❌ Free margin would drop below $30");
        return false;
    }
    
    // Rule 3: Keep margin level above minimum
    const double projectedMarginLevel = (totalMarginAfter > 0) ?
                                       (equity / totalMarginAfter) * 100.0 : 1000.0;
    
    if(projectedMarginLevel < MIN_MARGIN_LEVEL)
    {
        PrintFormat("❌ Projected margin level: %.1f%% (minimum %.1f%%)",
                   projectedMarginLevel, MIN_MARGIN_LEVEL);
        return false;
    }
    
    PrintFormat("✅ Margin safe: Level=%.1f%%, Used=$%.2f of $%.2f",
               projectedMarginLevel, totalMarginAfter, equity);
    
    return true;
}

//+------------------------------------------------------------------+
//| Emergency Margin Protection                                     |
//| Activates emergency procedures to prevent margin call          |
//+------------------------------------------------------------------+
void EmergencyMarginProtection()
{
    Print("🚨🚨 EMERGENCY MARGIN PROTECTION ACTIVATED!");
    
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    const double marginLevel = (margin > 0) ? (equity / margin) * 100.0 : 1000.0;
    
    if(marginLevel < MARGIN_CALL_LEVEL)
    {
        Print("‼️‼️ MARGIN CALL IMMINENT - CLOSING ALL POSITIONS!");
        CloseAllPositions();
    }
    else if(marginLevel < CRITICAL_MARGIN_LEVEL)
    {
        Print("‼️ CRITICAL - Closing 75% of positions");
        ReducePositionsForMarginSafety(0.75);
    }
    else if(marginLevel < EMERGENCY_MARGIN_LEVEL)
    {
        Print("⚠️ EMERGENCY - Closing 50% of positions");
        ReducePositionsForMarginSafety(0.50);
    }
}

//+------------------------------------------------------------------+
//| Close All Positions                                             |
//| Emergency function to close all open positions                 |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    Print("Closing ALL positions for margin safety");
    
    int closedCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            const string symbol = PositionGetString(POSITION_SYMBOL);
            
            if(trade.PositionClose(ticket))
            {
                closedCount++;
                PrintFormat("CLOSED: Position for %s | Ticket: %d", symbol, ticket);
                
                // Update direction tracking for each symbol
                UpdateTradeDirection(symbol);
            }
        }
    }
    
    if(closedCount > 0)
    {
        PrintFormat("SUMMARY: Closed %d total positions", closedCount);
    }
}

//+------------------------------------------------------------------+
//| Reduce Positions for Margin Safety                              |
//| Reduces positions by specified percentage                       |
//+------------------------------------------------------------------+
void ReducePositionsForMarginSafety(const double reductionPercent)
{
    PrintFormat("Reducing positions by %.0f%% for margin safety", reductionPercent * 100.0);
    
    int totalPositions = PositionsTotal();
    int positionsToClose = (int)MathCeil(totalPositions * reductionPercent);
    
    if(positionsToClose <= 0) return;
    
    // Sort positions by profit (close losing positions first)
    PositionInfo positions[];
    ArrayResize(positions, totalPositions);
    
    for(int i = 0; i < totalPositions; i++)
    {
        const ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            positions[i].ticket = ticket;
            positions[i].profit = PositionGetDouble(POSITION_PROFIT);
            positions[i].symbol = PositionGetString(POSITION_SYMBOL);
        }
    }
    
    // Sort by profit (ascending - losing positions first)
    for(int i = 0; i < totalPositions - 1; i++)
    {
        for(int j = i + 1; j < totalPositions; j++)
        {
            if(positions[j].profit < positions[i].profit)
            {
                PositionInfo temp = positions[i];
                positions[i] = positions[j];
                positions[j] = temp;
            }
        }
    }
    
    // Close the worst positions
    int closedCount = 0;
    for(int i = 0; i < positionsToClose && i < totalPositions; i++)
    {
        if(trade.PositionClose(positions[i].ticket))
        {
            closedCount++;
            PrintFormat("Reduced: %s (Profit: $%.2f)", 
                       positions[i].symbol, positions[i].profit);
            
            UpdateTradeDirection(positions[i].symbol);
        }
    }
    
    PrintFormat("Margin reduction complete: Closed %d/%d positions",
               closedCount, positionsToClose);
}

//+------------------------------------------------------------------+
//| Check Margin Level Periodically                                 |
//| Should be called from OnTick() or OnTimer()                    |
//+------------------------------------------------------------------+
void CheckMarginLevelPeriodically()
{
    static datetime lastCheck = 0;
    if(TimeCurrent() - lastCheck < 10) return;  // Check every 10 seconds
    
    lastCheck = TimeCurrent();
    
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    if(margin <= 0) return;
    
    const double marginLevel = (equity / margin) * 100.0;
    
    // Update worst margin level
    if(marginLevel < g_worstMarginLevel)
    {
        g_worstMarginLevel = marginLevel;
    }
    
    // Log margin level periodically
    static int logCounter = 0;
    if(logCounter++ % 30 == 0)  // Log every ~5 minutes
    {
        PrintFormat("MARGIN MONITOR: Level=%.1f%%, Worst=%.1f%%",
                   marginLevel, g_worstMarginLevel);
    }
    
    // Automatic protection triggers
    if(marginLevel < CRITICAL_MARGIN_LEVEL)
    {
        EmergencyMarginProtection();
    }
}

//+------------------------------------------------------------------+
//| Print Margin Report                                             |
//| Comprehensive margin status report                              |
//+------------------------------------------------------------------+
void PrintMarginReport()
{
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    const double marginLevel = (margin > 0) ? (equity / margin) * 100.0 : 1000.0;
    const double freeMarginPercent = (equity > 0) ? (freeMargin / equity) * 100.0 : 100.0;
    
    Print("=== MARGIN SAFETY REPORT ===");
    PrintFormat("  Equity: $%.2f", equity);
    PrintFormat("  Balance: $%.2f", balance);
    PrintFormat("  Margin Used: $%.2f", margin);
    PrintFormat("  Free Margin: $%.2f (%.1f%%)", freeMargin, freeMarginPercent);
    PrintFormat("  Margin Level: %.1f%%", marginLevel);
    PrintFormat("  Worst This Session: %.1f%%", g_worstMarginLevel);
    PrintFormat("  Safety Status: %s", GetMarginSafetyStatus(marginLevel));
    Print("============================");
}

//+------------------------------------------------------------------+
//| Calculate Worst Case Loss                                       |
//| Estimates maximum potential loss                               |
//+------------------------------------------------------------------+
double CalculateWorstCaseLoss(const string symbol, const double volume)
{
    const double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double maxRiskPercent = 2.0;
    const double maxRiskDollars = accountEquity * (maxRiskPercent / 100.0);
    
    PrintFormat("WORST_CASE: Account=$%.2f, MaxRisk=$%.2f (%.1f%%)",
               accountEquity, maxRiskDollars, maxRiskPercent);
    
    return maxRiskDollars;
}

//+------------------------------------------------------------------+
//| Get Contract Size                                               |
//| Returns contract size for different symbols                    |
//+------------------------------------------------------------------+
double GetContractSize(const string symbol)
{
    // For metals (gold, silver)
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
        return GOLD_CONTRACT_SIZE;
    
    if(StringFind(symbol, "XAG") >= 0 || StringFind(symbol, "SILVER") >= 0)
        return 5000.0;  // 5000 oz per standard lot for silver
    
    // For forex majors
    const string forexSymbols[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF",
                                  "AUDUSD", "USDCAD", "NZDUSD"};
    
    for(int i = 0; i < ArraySize(forexSymbols); i++)
    {
        if(StringFind(symbol, forexSymbols[i]) >= 0)
            return STANDARD_CONTRACT_SIZE;
    }
    
    // Default (check with broker)
    #ifdef __MQL5__
        return SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    #else
        return MarketInfo(symbol, MODE_LOTSIZE);
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Margin Required                                       |
//| Calculates margin required for a position                      |
//+------------------------------------------------------------------+
double CalculateMarginRequired(const string symbol, const double volume)
{
    // Try to get actual margin from broker
    #ifdef __MQL5__
        MqlTick lastTick;
        SymbolInfoTick(symbol, lastTick);
        const double price = lastTick.ask;
        
        double margin = 0.0;
        const ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
        
        if(!OrderCalcMargin(orderType, symbol, volume, price, margin))
        {
            PrintFormat("ERROR: Failed to calculate margin for %s", symbol);
            margin = 0.0;
        }
        
        if(margin > 0.0)
        {
            return margin;
        }
    #else
        const double margin = MarketInfo(symbol, MODE_MARGINREQUIRED);
        if(margin > 0.0)
        {
            return margin * volume;
        }
    #endif
    
    // Fallback calculation
    const double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
    const double contractSize = GetContractSize(symbol);
    
    #ifdef __MQL5__
        MqlTick tick;
        SymbolInfoTick(symbol, tick);
        const double fallbackPrice = tick.ask;
    #else
        const double fallbackPrice = MarketInfo(symbol, MODE_ASK);
    #endif
    
    return (fallbackPrice * volume * contractSize) / leverage;
}

//+------------------------------------------------------------------+
//| Calculate Risk Amount                                           |
//| Calculates monetary risk based on stop loss                    |
//+------------------------------------------------------------------+
double CalculateRiskAmount(const string symbol, const ENUM_POSITION_TYPE positionType,
                          const double volume, const double entryPrice, const double stopLoss,
                          const double contractSize)
{
    if(stopLoss <= 0.0)
    {
        // If no stop loss, use 1% of position as risk estimate
        return (entryPrice * volume * contractSize) * 0.01;
    }
    
    double stopLossDistance = 0.0;
    
    if(positionType == POSITION_TYPE_BUY)
    {
        stopLossDistance = entryPrice - stopLoss;
    }
    else
    {
        stopLossDistance = stopLoss - entryPrice;
    }
    
    if(stopLossDistance <= 0.0)
    {
        PrintFormat("WARNING: Invalid stop loss distance for %s", symbol);
        return 0.0;
    }
    
    // Convert price distance to monetary risk
    #ifdef __MQL5__
        const double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    #else
        const double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
        const double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
    #endif
    
    if(tickSize > 0.0 && tickValue > 0.0)
    {
        const double ticks = stopLossDistance / tickSize;
        return MathAbs(ticks * tickValue * volume);
    }
    
    // Fallback calculation for gold/XAUUSD
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
    {
        const double dollarsPerPip = 0.01;
        const double ounces = volume * contractSize;
        const double pips = stopLossDistance / 0.01;
        
        return MathAbs(pips * dollarsPerPip * ounces);
    }
    
    // Generic fallback
    return MathAbs(stopLossDistance * volume * contractSize);
}

//+------------------------------------------------------------------+
//| Get Margin Safety Status                                        |
//| Returns safety status based on margin level                    |
//+------------------------------------------------------------------+
string GetMarginSafetyStatus(const double marginLevel)
{
    if(marginLevel >= 500.0) return "VERY SAFE 🟢";
    if(marginLevel >= 200.0) return "SAFE 🟡";
    if(marginLevel >= 150.0) return "CAUTION 🟠";
    if(marginLevel >= 120.0) return "WARNING 🔴";
    if(marginLevel >= 100.0) return "CRITICAL 🚨";
    return "MARGIN CALL IMMINENT ‼️";
}

//+------------------------------------------------------------------+
//| Get Exposure Summary                                            |
//| Returns comprehensive exposure summary                        |
//+------------------------------------------------------------------+
string GetExposureSummary(const string symbol)
{
    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    const double marginLevel = (margin > 0.0) ? (equity / margin) * 100.0 : 1000.0;
    const double marginUsage = (equity > 0.0) ? (margin / equity) * 100.0 : 0.0;
    
    return StringFormat("Exposure Summary:\n" +
                       "  Equity: $%.2f\n" +
                       "  Margin Used: $%.2f (%.1f%%)\n" +
                       "  Free Margin: $%.2f\n" +
                       "  Margin Level: %.1f%%\n" +
                       "  Safety Status: %s\n" +
                       "  Worst Level: %.1f%%",
                       equity,
                       margin, marginUsage,
                       freeMargin,
                       marginLevel,
                       GetMarginSafetyStatus(marginLevel),
                       g_worstMarginLevel);
}

//+------------------------------------------------------------------+
//| Position Info Structure                                         |
//| For sorting positions during reduction                         |
//+------------------------------------------------------------------+
struct PositionInfo
{
    ulong ticket;
    double profit;
    string symbol;
};