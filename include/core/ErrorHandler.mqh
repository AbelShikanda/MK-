//+------------------------------------------------------------------+
//| Error Handler - Centralized Error Management                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/FormatUtils.mqh"

// ================================================================
// SECTION 1: ERROR TYPES AND CATEGORIES
// ================================================================

enum ENUM_ERROR_CATEGORY
{
    ERROR_CATEGORY_TRADE,      // Trade execution errors
    ERROR_CATEGORY_INDICATOR,  // Indicator/technical errors
    ERROR_CATEGORY_SYSTEM,     // System/account errors
    ERROR_CATEGORY_VALIDATION, // Validation/parameter errors
    ERROR_CATEGORY_MARKET,     // Market condition errors
    ERROR_CATEGORY_NETWORK     // Connection/timeout errors
};

enum ENUM_ERROR_SEVERITY
{
    ERROR_SEVERITY_INFO,       // Informational only
    ERROR_SEVERITY_WARNING,    // Warning - can continue
    ERROR_SEVERITY_ERROR,      // Error - action failed
    ERROR_SEVERITY_CRITICAL    // Critical - system may be unstable
};

// ================================================================
// SECTION 2: CORE ERROR LOGGING FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Log Error - Enhanced Version with Context                      |
//+------------------------------------------------------------------+
void LogError(string context, string symbol = "", int errorCode = -1, 
              ENUM_ERROR_CATEGORY category = ERROR_CATEGORY_SYSTEM,
              ENUM_ERROR_SEVERITY severity = ERROR_SEVERITY_ERROR)
{
    if(errorCode == -1) errorCode = GetLastError();
    
    string errorMessage = GetErrorDescription(errorCode);
    string severityText = GetSeverityText(severity);
    string categoryText = GetCategoryText(category);
    
    string logEntry = StringFormat("%s | %s | %s", 
                                   severityText, categoryText, context);
    
    if(symbol != "")
        logEntry += StringFormat(" [%s]", symbol);
    
    logEntry += StringFormat(" | Error %d: %s", errorCode, errorMessage);
    
    // Add timestamp for tracking
    logEntry = StringFormat("[%s] %s", 
                           TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), 
                           logEntry);
    
    // Log based on severity
    switch(severity)
    {
        case ERROR_SEVERITY_CRITICAL:
            Print("‼️ CRITICAL: ", logEntry);
            SendNotification("CRITICAL ERROR: " + context + " - " + errorMessage);
            break;
        case ERROR_SEVERITY_ERROR:
            Print("❌ ERROR: ", logEntry);
            break;
        case ERROR_SEVERITY_WARNING:
            Print("⚠️ WARNING: ", logEntry);
            break;
        case ERROR_SEVERITY_INFO:
            Print("ℹ️ INFO: ", logEntry);
            break;
    }
}

//+------------------------------------------------------------------+
//| Handle Trade Error                                             |
//+------------------------------------------------------------------+
bool HandleTradeError(int errorCode, string symbol, string operation)
{
    string errorMessage = GetTradeErrorDescription(errorCode);
    ENUM_ERROR_SEVERITY severity = ERROR_SEVERITY_ERROR;
    
    // Categorize trade errors
    switch(errorCode)
    {
        case 10004: // Requote
        case 10021: // No quotes
        case 138:   // Requote
            severity = ERROR_SEVERITY_WARNING;
            LogError("Trade " + operation + " - Market quote issue", 
                    symbol, errorCode, ERROR_CATEGORY_TRADE, severity);
            return true; // Retry might be possible
            
        case 10006: // Request rejected
        case 10013: // Invalid request
        case 10014: // Invalid volume
        case 10015: // Invalid price
        case 10016: // Invalid stops
            LogError("Trade " + operation + " - Invalid parameters", 
                    symbol, errorCode, ERROR_CATEGORY_VALIDATION, ERROR_SEVERITY_ERROR);
            return false; // Cannot retry - parameters wrong
            
        case 10019: // Not enough money
        case 134:   // Not enough money
            LogError("Trade " + operation + " - Insufficient funds", 
                    symbol, errorCode, ERROR_CATEGORY_SYSTEM, ERROR_SEVERITY_CRITICAL);
            SendNotification("INSUFFICIENT FUNDS: Cannot execute " + operation + " for " + symbol);
            return false;
            
        case 10029: // Order frozen
        case 146:   // Trade context busy
            severity = ERROR_SEVERITY_WARNING;
            LogError("Trade " + operation + " - System busy", 
                    symbol, errorCode, ERROR_CATEGORY_SYSTEM, severity);
            return true; // Can retry after delay
            
        case 132:   // Market closed
        case 133:   // Trade disabled
            LogError("Trade " + operation + " - Trading not allowed", 
                    symbol, errorCode, ERROR_CATEGORY_MARKET, ERROR_SEVERITY_ERROR);
            return false;
            
        default:
            LogError("Trade " + operation + " - Unknown error", 
                    symbol, errorCode, ERROR_CATEGORY_TRADE, ERROR_SEVERITY_ERROR);
            return false;
    }
}

//+------------------------------------------------------------------+
//| Handle Indicator Error                                         |
//+------------------------------------------------------------------+
bool HandleIndicatorError(int errorCode, string symbol, string indicatorName)
{
    string errorMessage = GetIndicatorErrorDescription(errorCode);
    ENUM_ERROR_SEVERITY severity = ERROR_SEVERITY_ERROR;
    
    switch(errorCode)
    {
        case 4001: // Indicator: no memory
        case 4002: // Indicator: wrong parameters
        case 4003: // Indicator: custom indicator error
            LogError("Indicator " + indicatorName + " - Configuration error", 
                    symbol, errorCode, ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_ERROR);
            return false;
            
        case 4004: // Indicator: invalid handle
            LogError("Indicator " + indicatorName + " - Invalid handle", 
                    symbol, errorCode, ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_CRITICAL);
            return false;
            
        case 4005: // Indicator: no data
        case 4006: // Indicator: wrong handle
            severity = ERROR_SEVERITY_WARNING;
            LogError("Indicator " + indicatorName + " - Data issue", 
                    symbol, errorCode, ERROR_CATEGORY_INDICATOR, severity);
            return true; // Might recover
        
        case 4014: // Indicator: some error
        case 4018: // Indicator: internal error
            LogError("Indicator " + indicatorName + " - Internal error", 
                    symbol, errorCode, ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_ERROR);
            return false;
            
        default:
            LogError("Indicator " + indicatorName + " - Unknown error", 
                    symbol, errorCode, ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_ERROR);
            return false;
    }
}

// ================================================================
// SECTION 3: VALIDATION ERROR HANDLING
// ================================================================

//+------------------------------------------------------------------+
//| Handle Validation Error                                        |
//+------------------------------------------------------------------+
void HandleValidationError(string context, string symbol, string reason)
{
    LogError("Validation failed: " + context + " - " + reason, 
             symbol, 0, ERROR_CATEGORY_VALIDATION, ERROR_SEVERITY_WARNING);
    
    // Store validation failures for reporting
    static string validationErrors[];
    static int errorCount = 0;
    
    if(errorCount < 100) // Prevent memory issues
    {
        ArrayResize(validationErrors, errorCount + 1);
        validationErrors[errorCount] = StringFormat("[%s] %s: %s - %s", 
                                                   TimeToString(TimeCurrent(), TIME_SECONDS),
                                                   symbol, context, reason);
        errorCount++;
    }
}

//+------------------------------------------------------------------+
//| Get Validation Error Summary                                   |
//+------------------------------------------------------------------+
string GetValidationErrorSummary()
{
    static string validationErrors[];
    static int errorCount = 0;
    
    if(errorCount == 0)
        return "No validation errors";
    
    string summary = StringFormat("=== VALIDATION ERRORS (%d) ===\n", errorCount);
    for(int i = 0; i < MathMin(errorCount, 10); i++) // Show last 10 errors
    {
        summary += validationErrors[i] + "\n";
    }
    
    if(errorCount > 10)
        summary += StringFormat("... and %d more errors\n", errorCount - 10);
    
    return summary;
}

// ================================================================
// SECTION 4: ERROR RECOVERY FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Attempt Error Recovery                                         |
//+------------------------------------------------------------------+
bool AttemptErrorRecovery(ENUM_ERROR_CATEGORY category, int errorCode, string symbol = "")
{
    switch(category)
    {
        case ERROR_CATEGORY_INDICATOR:
            return RecoverIndicatorError(errorCode, symbol);
            
        case ERROR_CATEGORY_TRADE:
            return RecoverTradeError(errorCode, symbol);
            
        case ERROR_CATEGORY_NETWORK:
            return RecoverNetworkError(errorCode);
            
        default:
            return false; // Cannot recover from other error types
    }
}

//+------------------------------------------------------------------+
//| Recover Indicator Error                                        |
//+------------------------------------------------------------------+
bool RecoverIndicatorError(int errorCode, string symbol)
{
    switch(errorCode)
    {
        case 4004: // Invalid handle
        case 4006: // Wrong handle
            LogError("Attempting indicator handle recovery", symbol, errorCode, 
                    ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_INFO);
            // In your EA, you would reinitialize indicators here
            // Example: RecreateIndicatorHandles(symbol);
            return true;
            
        case 4005: // No data
            LogError("Waiting for indicator data", symbol, errorCode, 
                    ERROR_CATEGORY_INDICATOR, ERROR_SEVERITY_INFO);
            Sleep(1000); // Wait 1 second for data
            return true;
            
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| Recover Trade Error                                            |
//+------------------------------------------------------------------+
bool RecoverTradeError(int errorCode, string symbol)
{
    switch(errorCode)
    {
        case 10004: // Requote
        case 10021: // No quotes
        case 138:   // Requote
            LogError("Retrying trade after quote issue", symbol, errorCode, 
                    ERROR_CATEGORY_TRADE, ERROR_SEVERITY_INFO);
            Sleep(500); // Wait 0.5 seconds
            return true;
            
        case 146:   // Trade context busy
            LogError("Retrying trade after context busy", symbol, errorCode, 
                    ERROR_CATEGORY_TRADE, ERROR_SEVERITY_INFO);
            Sleep(1000); // Wait 1 second
            return true;
            
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| Recover Network Error                                          |
//+------------------------------------------------------------------+
bool RecoverNetworkError(int errorCode)
{
    switch(errorCode)
    {
        case 4060: // Network error
        case 4061: // Unknown symbol
        case 4062: // Wrong parameter
        case 4063: // History not available
        case 4064: // Account disabled
            LogError("Network error recovery attempted", "", errorCode, 
                    ERROR_CATEGORY_NETWORK, ERROR_SEVERITY_INFO);
            Sleep(2000); // Wait 2 seconds
            return true;
            
        default:
            return false;
    }
}

// ================================================================
// SECTION 5: ERROR DESCRIPTION FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Error Description                                          |
//+------------------------------------------------------------------+
string GetErrorDescription(int errorCode)
{
    // Comprehensive error descriptions
    switch(errorCode)
    {
        // Trade errors
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10007: return "Request canceled by trader";
        case 10008: return "Order placed";
        case 10009: return "Request completed";
        case 10010: return "Only part of request completed";
        case 10011: return "Request processing error";
        case 10012: return "Request canceled by timeout";
        case 10013: return "Invalid request";
        case 10014: return "Invalid volume";
        case 10015: return "Invalid price";
        case 10016: return "Invalid stops";
        case 10017: return "Trade disabled";
        case 10018: return "Market closed";
        case 10019: return "Not enough money";
        case 10020: return "Prices changed";
        case 10021: return "No quotes";
        case 10022: return "Invalid order expiration";
        case 10023: return "Order state changed";
        case 10024: return "Too frequent requests";
        case 10025: return "No changes in request";
        case 10026: return "Autotrading disabled by server";
        case 10027: return "Autotrading disabled by client";
        case 10028: return "Request locked for processing";
        case 10029: return "Order/position frozen";
        case 10030: return "Invalid order filling type";
        
        // Common errors
        case 1:     return "No error, but result unknown";
        case 2:     return "Common error";
        case 3:     return "Invalid trade parameters";
        case 4:     return "Trade server busy";
        case 5:     return "Old client version";
        case 6:     return "No connection with trade server";
        case 7:     return "Not enough rights";
        case 8:     return "Too frequent requests";
        case 9:     return "Malfunctional trade operation";
        
        // Account errors
        case 64:    return "Account disabled";
        case 65:    return "Invalid account";
        case 128:   return "Trade timeout";
        case 129:   return "Invalid price";
        case 130:   return "Invalid stops";
        case 131:   return "Invalid trade volume";
        case 132:   return "Market closed";
        case 133:   return "Trade disabled";
        case 134:   return "Not enough money";
        case 135:   return "Price changed";
        case 136:   return "Off quotes";
        case 137:   return "Broker busy";
        case 138:   return "Requote";
        case 139:   return "Order locked";
        case 140:   return "Long positions only";
        case 141:   return "Too many requests";
        case 145:   return "Modification denied - order too close to market";
        case 146:   return "Trade context busy";
        case 147:   return "Expirations denied by broker";
        case 148:   return "Too many open/pending orders";
        
        // Indicator errors
        case 4001:  return "Indicator: no memory";
        case 4002:  return "Indicator: wrong parameters";
        case 4003:  return "Indicator: custom indicator error";
        case 4004:  return "Indicator: invalid handle";
        case 4005:  return "Indicator: no data";
        case 4006:  return "Indicator: wrong handle";
        case 4007:  return "Indicator: unknown symbol";
        case 4008:  return "Indicator: invalid parameter type";
        case 4009:  return "Indicator: no history";
        case 4010:  return "Indicator: invalid parameter value";
        case 4011:  return "Indicator: out of range";
        case 4012:  return "Indicator: no answer";
        case 4013:  return "Indicator: unknown error";
        case 4014:  return "Indicator: some error";
        case 4015:  return "Indicator: invalid reply";
        case 4016:  return "Indicator: invalid request";
        case 4017:  return "Indicator: request failed";
        case 4018:  return "Indicator: internal error";
        
        // Network errors
        case 4060:  return "Network error";
        case 4061:  return "Unknown symbol";
        case 4062:  return "Wrong parameter";
        case 4063:  return "History not available";
        case 4064:  return "Account disabled";
        
        default:    return StringFormat("Unknown error code: %d", errorCode);
    }
}

//+------------------------------------------------------------------+
//| Get Trade Error Description                                     |
//+------------------------------------------------------------------+
string GetTradeErrorDescription(int errorCode)
{
    // Specialized descriptions for trade errors
    switch(errorCode)
    {
        case 10004: return "Market moved - requote needed";
        case 10006: return "Broker rejected trade request";
        case 10019: return "Account balance insufficient";
        case 134:   return "Margin insufficient for trade";
        case 135:   return "Price changed during execution";
        case 138:   return "Requote - prices updated";
        case 146:   return "Trading system busy - try again";
        default:    return GetErrorDescription(errorCode);
    }
}

//+------------------------------------------------------------------+
//| Get Indicator Error Description                                 |
//+------------------------------------------------------------------+
string GetIndicatorErrorDescription(int errorCode)
{
    // Specialized descriptions for indicator errors
    switch(errorCode)
    {
        case 4001: return "Insufficient memory for indicator";
        case 4002: return "Wrong indicator parameters";
        case 4003: return "Custom indicator calculation error";
        case 4004: return "Indicator handle invalid or expired";
        case 4005: return "No market data available for indicator";
        case 4006: return "Wrong indicator handle type";
        default:   return GetErrorDescription(errorCode);
    }
}

// ================================================================
// SECTION 6: HELPER FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Severity Text                                              |
//+------------------------------------------------------------------+
string GetSeverityText(ENUM_ERROR_SEVERITY severity)
{
    switch(severity)
    {
        case ERROR_SEVERITY_CRITICAL: return "CRITICAL";
        case ERROR_SEVERITY_ERROR:    return "ERROR";
        case ERROR_SEVERITY_WARNING:  return "WARNING";
        case ERROR_SEVERITY_INFO:     return "INFO";
        default:                      return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Get Category Text                                              |
//+------------------------------------------------------------------+
string GetCategoryText(ENUM_ERROR_CATEGORY category)
{
    switch(category)
    {
        case ERROR_CATEGORY_TRADE:      return "TRADE";
        case ERROR_CATEGORY_INDICATOR:  return "INDICATOR";
        case ERROR_CATEGORY_SYSTEM:     return "SYSTEM";
        case ERROR_CATEGORY_VALIDATION: return "VALIDATION";
        case ERROR_CATEGORY_MARKET:     return "MARKET";
        case ERROR_CATEGORY_NETWORK:    return "NETWORK";
        default:                        return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Get Error Statistics                                           |
//+------------------------------------------------------------------+
string GetErrorStatistics()
{
    static int totalErrors = 0;
    static int tradeErrors = 0;
    static int indicatorErrors = 0;
    static int criticalErrors = 0;
    
    return StringFormat("=== ERROR STATISTICS ===\n"
                       "Total Errors: %d\n"
                       "Trade Errors: %d\n"
                       "Indicator Errors: %d\n"
                       "Critical Errors: %d\n"
                       "Last Error Time: %s",
                       totalErrors, tradeErrors, indicatorErrors, criticalErrors,
                       TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Reset Error Statistics                                         |
//+------------------------------------------------------------------+
void ResetErrorStatistics()
{
    // This would reset your error counters
    // Implementation depends on your tracking system
    Print("Error statistics reset at ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
}