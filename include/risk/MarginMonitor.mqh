//+------------------------------------------------------------------+
//| Margin Monitor - Account Margin Monitoring                     |
//+------------------------------------------------------------------+
#property strict

#include "../config/enums.mqh"
#include "../config/inputs.mqh"
#include "../utils/TradeUtils.mqh"

// ============ MARGIN PROTECTION CONSTANTS ============
#define MAX_ACCOUNT_EXPOSURE_PERCENT 30.0     // Maximum 30% of account at risk
#define MAX_MARGIN_USAGE_PERCENT 30.0         // Maximum 30% margin usage
#define MIN_MARGIN_LEVEL 200.0                // NEVER go below 200% margin level
#define MIN_FREE_MARGIN_PERCENT 40.0          // Keep at least 40% free margin buffer
#define EMERGENCY_MARGIN_LEVEL 150.0          // Emergency position reduction level
#define CRITICAL_MARGIN_LEVEL 120.0           // Critical - start closing positions
#define MARGIN_CALL_LEVEL 100.0               // Broker will margin call at this level

#define GOLD_CONTRACT_SIZE 100.0              // 100 oz per standard lot
#define STANDARD_CONTRACT_SIZE 100000.0       // 100,000 units for forex majors

// ============ GLOBAL MARGIN TRACKING ============
double g_worstMarginLevel = 1000.0;           // Tracks worst margin level during session
datetime g_lastMarginCheck = 0;

// ============ CORE MARGIN VALIDATION ============
bool ValidateExposure(string symbol, ENUM_POSITION_TYPE positionType, 
                      double volume, double entryPrice, double stopLoss, 
                      EXPOSURE_METHOD method = EXPOSURE_RISK_BASED) {
    
    // First safety check: current margin status
    if(!CheckCurrentMarginSafety()) {
        Print("❌ BLOCKED: Current margin level unsafe - cannot add positions");
        return false;
    }
    
    // Second safety check: projected margin after addition
    if(!CheckMarginSafetyForAddition(symbol, volume)) {
        Print("❌ BLOCKED: Adding position would risk margin call");
        return false;
    }
    
    // Get account information
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentFreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    if(currentEquity <= 0) {
        Print("ERROR: Invalid account equity: $", currentEquity);
        return false;
    }
    
    // Calculate current margin metrics
    double currentMarginLevel = CalculateMarginLevel(currentEquity, currentMargin);
    double contractSize = GetContractSize(symbol);
    double notionalValue = entryPrice * volume * contractSize;
    double marginRequired = CalculateMarginRequired(symbol, volume);
    
    // Calculate risk based on exposure method
    double riskAmount = 0;
    double exposurePercent = 0;
    string exposureType = "";
    
    switch(method) {
        case EXPOSURE_MARGIN_BASED:
            exposurePercent = (marginRequired / currentEquity) * 100;
            exposureType = "Margin";
            break;
            
        case EXPOSURE_RISK_BASED:
            riskAmount = CalculateRiskAmount(symbol, positionType, volume, 
                                           entryPrice, stopLoss, contractSize);
            exposurePercent = (riskAmount / currentEquity) * 100;
            exposureType = "Risk";
            break;
            
        case EXPOSURE_NOTIONAL_BASED:
            exposurePercent = (notionalValue / currentEquity) * 100;
            exposureType = "Notional";
            break;
    }
    
    // Calculate projected metrics after position addition
    MarginProjection projection = CalculateMarginProjection(
        currentEquity, currentMargin, currentFreeMargin, marginRequired);
    
    // Comprehensive margin safety validation
    bool validationPassed = PerformMarginValidation(
        symbol, volume, exposureType, exposurePercent, 
        marginRequired, currentEquity, projection);
    
    // Log detailed margin report
    if(validationPassed) {
        LogMarginValidation(symbol, volume, currentEquity, currentMarginLevel,
                          exposurePercent, exposureType, projection, marginRequired);
        
        // Update worst margin level tracker
        if(projection.marginLevel < g_worstMarginLevel) {
            g_worstMarginLevel = projection.marginLevel;
        }
    }
    
    return validationPassed;
}

// ============ MARGIN SAFETY CHECKS ============

bool CheckCurrentMarginSafety() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(equity <= 0 || margin < 0) return false;
    
    double marginLevel = CalculateMarginLevel(equity, margin);
    double freeMarginPercent = (equity > 0) ? (freeMargin / equity) * 100 : 100.0;
    
    // Update worst margin level
    if(marginLevel < g_worstMarginLevel) {
        g_worstMarginLevel = marginLevel;
    }
    
    // Execute margin protection if needed
    return ExecuteMarginProtection(marginLevel);
}

bool CheckMarginSafetyForAddition(string symbol, double volume) {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    double newPositionMargin = CalculateMarginRequired(symbol, volume);
    double totalMarginAfter = currentMargin + newPositionMargin;
    double projectedMarginLevel = (totalMarginAfter > 0) ? 
                                  (equity / totalMarginAfter) * 100 : 1000.0;
    
    // Safety rules
    if(totalMarginAfter > equity * 0.5) {
        Print("❌ Would use ", (totalMarginAfter/equity)*100, 
              "% of equity as margin (max 50%)");
        return false;
    }
    
    if(freeMargin - newPositionMargin < 30) {
        Print("❌ Free margin would drop below $30");
        return false;
    }
    
    if(projectedMarginLevel < MIN_MARGIN_LEVEL) {
        Print("❌ Projected margin level: ", projectedMarginLevel, "% (min ", MIN_MARGIN_LEVEL, "%)");
        return false;
    }
    
    Print("✅ Margin safe: Level=", projectedMarginLevel, 
          "%, Used=$", totalMarginAfter, " of $", equity);
    
    return true;
}

// ============ PERIODIC MONITORING ============

void CheckMarginLevelPeriodically() {
    static datetime lastCheck = 0;
    if(TimeCurrent() - lastCheck < 10) return;
    lastCheck = TimeCurrent();
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    if(margin <= 0) return;
    
    double marginLevel = CalculateMarginLevel(equity, margin);
    
    // Update worst margin level
    if(marginLevel < g_worstMarginLevel) {
        g_worstMarginLevel = marginLevel;
    }
    
    // Periodic logging
    static int logCounter = 0;
    if(logCounter++ % 30 == 0) {
        Print("MARGIN MONITOR: Level=", DoubleToString(marginLevel, 1), 
              "%, Worst=", DoubleToString(g_worstMarginLevel, 1), "%");
    }
    
    // Automatic protection
    if(marginLevel < CRITICAL_MARGIN_LEVEL) {
        ExecuteEmergencyProtection(marginLevel);
    }
}

// ============ MARGIN REPORTING ============

void PrintMarginReport() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    double marginLevel = CalculateMarginLevel(equity, margin);
    double freeMarginPercent = (equity > 0) ? (freeMargin / equity) * 100 : 100.0;
    
    Print("=== MARGIN SAFETY REPORT ===");
    Print("  Equity: $", DoubleToString(equity, 2));
    Print("  Balance: $", DoubleToString(balance, 2));
    Print("  Margin Used: $", DoubleToString(margin, 2));
    Print("  Free Margin: $", DoubleToString(freeMargin, 2), 
          " (", DoubleToString(freeMarginPercent, 1), "%)");
    Print("  Margin Level: ", DoubleToString(marginLevel, 1), "%");
    Print("  Worst This Session: ", DoubleToString(g_worstMarginLevel, 1), "%");
    Print("  Safety Status: ", GetMarginSafetyStatus(marginLevel));
    Print("============================");
}

string GetMarginSafetyStatus(double marginLevel) {
    if(marginLevel >= 500) return "VERY SAFE 🟢";
    if(marginLevel >= MIN_MARGIN_LEVEL) return "SAFE 🟡";
    if(marginLevel >= 150) return "CAUTION 🟠";
    if(marginLevel >= 120) return "WARNING 🔴";
    if(marginLevel >= 100) return "CRITICAL 🚨";
    return "MARGIN CALL IMMINENT ‼️";
}

// ============ HELPER FUNCTIONS ============

struct MarginProjection {
    double marginLevel;
    double freeMargin;
    double freeMarginPercent;
};

MarginProjection CalculateMarginProjection(double equity, double currentMargin, 
                                         double currentFreeMargin, double additionalMargin) {
    MarginProjection projection;
    double projectedMargin = currentMargin + additionalMargin;
    
    projection.marginLevel = (projectedMargin > 0) ? (equity / projectedMargin) * 100 : 1000.0;
    projection.freeMargin = currentFreeMargin - additionalMargin;
    projection.freeMarginPercent = (equity > 0) ? (projection.freeMargin / equity) * 100 : 0;
    
    return projection;
}

bool PerformMarginValidation(string symbol, double volume, string exposureType,
                           double exposurePercent, double marginRequired,
                           double equity, MarginProjection &projection) {
    
    double marginUsagePercent = (marginRequired / equity) * 100;
    
    // Check 1: Projected margin level
    if(projection.marginLevel < MIN_MARGIN_LEVEL) {
        Print("❌ FAILED: Projected margin level ", DoubleToString(projection.marginLevel, 1),
              "% below minimum ", MIN_MARGIN_LEVEL, "%");
        return false;
    }
    
    // Check 2: Projected free margin buffer
    if(projection.freeMarginPercent < MIN_FREE_MARGIN_PERCENT) {
        Print("❌ FAILED: Projected free margin ", DoubleToString(projection.freeMarginPercent, 1),
              "% below minimum ", MIN_FREE_MARGIN_PERCENT, "%");
        return false;
    }
    
    // Check 3: Exposure limit
    if(exposurePercent > MAX_ACCOUNT_EXPOSURE_PERCENT) {
        Print("❌ FAILED: ", exposureType, " exposure ", DoubleToString(exposurePercent, 1),
              "% exceeds maximum ", MAX_ACCOUNT_EXPOSURE_PERCENT, "%");
        return false;
    }
    
    // Check 4: Margin usage limit
    if(marginUsagePercent > MAX_MARGIN_USAGE_PERCENT) {
        Print("❌ FAILED: Margin usage ", DoubleToString(marginUsagePercent, 1),
              "% exceeds maximum ", MAX_MARGIN_USAGE_PERCENT, "%");
        return false;
    }
    
    return true;
}

void LogMarginValidation(string symbol, double volume, double equity,
                       double currentMarginLevel, double exposurePercent,
                       string exposureType, MarginProjection &projection,
                       double marginRequired) {
    
    Print("✅ PASSED: Margin safety check for ", symbol);
    Print("   Volume: ", volume, " lots");
    Print("   Account Equity: $", DoubleToString(equity, 2));
    Print("   Margin Level: ", DoubleToString(currentMarginLevel, 1), 
          "% → ", DoubleToString(projection.marginLevel, 1), "%");
    Print("   ", exposureType, " Exposure: ", DoubleToString(exposurePercent, 1), "%");
    Print("   Margin Required: $", DoubleToString(marginRequired, 2));
    Print("   Free Margin: ", DoubleToString(projection.freeMarginPercent, 1), "%");
    Print("   Worst this session: ", DoubleToString(g_worstMarginLevel, 1), "%");
}

// ============ MARGIN PROTECTION ACTIONS ============

bool ExecuteMarginProtection(double marginLevel) {
    if(marginLevel < MARGIN_CALL_LEVEL) {
        Print("‼️‼️ CRITICAL: Margin call IMMINENT! Level: ", 
              DoubleToString(marginLevel, 1), "%");
        ExecuteEmergencyProtection(marginLevel);
        return false;
    }
    
    if(marginLevel < CRITICAL_MARGIN_LEVEL) {
        Print("‼️ CRITICAL: Margin level ", DoubleToString(marginLevel, 1), 
              "% - Automatic position reduction");
        ReducePositionsForMarginSafety(0.5);
        return false;
    }
    
    if(marginLevel < EMERGENCY_MARGIN_LEVEL) {
        Print("⚠️ EMERGENCY: Margin level ", DoubleToString(marginLevel, 1), 
              "% - Reducing exposure");
        ReducePositionsForMarginSafety(0.25);
    }
    
    return true;
}

void ExecuteEmergencyProtection(double marginLevel) {
    Print("🚨🚨 EMERGENCY MARGIN PROTECTION ACTIVATED!");
    
    if(marginLevel < MARGIN_CALL_LEVEL) {
        Print("‼️‼️ MARGIN CALL IMMINENT - CLOSING ALL POSITIONS!");
        CloseAllPositions();
    }
    else if(marginLevel < CRITICAL_MARGIN_LEVEL) {
        Print("‼️ CRITICAL - Closing 75% of positions");
        ReducePositionsForMarginSafety(0.75);
    }
    else if(marginLevel < EMERGENCY_MARGIN_LEVEL) {
        Print("⚠️ EMERGENCY - Closing 50% of positions");
        ReducePositionsForMarginSafety(0.50);
    }
}

// ============ POSITION MANAGEMENT ============

void ReducePositionsForMarginSafety(double closePercentage) {
    // Implementation depends on your TradeUtils.mqh functions
    Print("Reducing positions by ", closePercentage * 100, "% for margin safety");
    // Add your position reduction logic here
}

void CloseAllPositions() {
    Print("Closing ALL positions for margin safety");
    // Implementation depends on your TradeUtils.mqh functions
    // Add your position closing logic here
}

// ============ CALCULATION FUNCTIONS ============

double CalculateMarginLevel(double equity, double margin) {
    return (margin > 0) ? (equity / margin) * 100 : 1000.0;
}

double GetContractSize(string symbol) {
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
        return GOLD_CONTRACT_SIZE;
    if(StringFind(symbol, "XAG") >= 0 || StringFind(symbol, "SILVER") >= 0)
        return 5000.0;
    
    string forexSymbols[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", 
                            "AUDUSD", "USDCAD", "NZDUSD"};
    for(int i = 0; i < ArraySize(forexSymbols); i++) {
        if(StringFind(symbol, forexSymbols[i]) >= 0)
            return STANDARD_CONTRACT_SIZE;
    }
    
    #ifdef __MQL5__
        return SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    #else
        return MarketInfo(symbol, MODE_LOTSIZE);
    #endif
}

double CalculateMarginRequired(string symbol, double volume) {
    #ifdef __MQL5__
        MqlTick last_tick;
        SymbolInfoTick(symbol, last_tick);
        double price = last_tick.ask;
        
        double margin;
        ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY;
        if(!OrderCalcMargin(order_type, symbol, volume, price, margin)) {
            Print("ERROR: Failed to calculate margin for ", symbol);
            margin = 0;
        }
        
        if(margin > 0) return margin;
    #else
        double margin = MarketInfo(symbol, MODE_MARGINREQUIRED);
        if(margin > 0) return margin * volume;
    #endif
    
    // Fallback calculation
    double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
    double contractSize = GetContractSize(symbol);
    
    #ifdef __MQL5__
        MqlTick tick;
        SymbolInfoTick(symbol, tick);
        double price_fallback = tick.ask;
    #else
        double price_fallback = MarketInfo(symbol, MODE_ASK);
    #endif
    
    return (price_fallback * volume * contractSize) / leverage;
}

double CalculateRiskAmount(string symbol, ENUM_POSITION_TYPE positionType,
                          double volume, double entryPrice, double stopLoss,
                          double contractSize) {
    
    if(stopLoss <= 0) {
        return (entryPrice * volume * contractSize) * 0.01;
    }
    
    double stopLossDistance = 0;
    
    if(positionType == POSITION_TYPE_BUY) {
        stopLossDistance = entryPrice - stopLoss;
    } else {
        stopLossDistance = stopLoss - entryPrice;
    }
    
    if(stopLossDistance <= 0) {
        Print("WARNING: Invalid stop loss distance for ", symbol);
        return 0;
    }
    
    // Calculate risk based on tick values
    #ifdef __MQL5__
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    #else
        double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
        double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
    #endif
    
    if(tickSize > 0 && tickValue > 0) {
        double ticks = stopLossDistance / tickSize;
        return MathAbs(ticks * tickValue * volume);
    }
    
    // Special handling for gold
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) {
        double dollarsPerPip = 0.01;
        double ounces = volume * contractSize;
        double pips = stopLossDistance / 0.01;
        return MathAbs(pips * dollarsPerPip * ounces);
    }
    
    // Generic fallback
    return MathAbs(stopLossDistance * volume * contractSize);
}