//+------------------------------------------------------------------+
//|                     ErrorHandler.mqh                             |
//|               Static Error Handling Functions                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include <Trade/Trade.mqh>
#include "Logger.mqh"

// ==================== ERROR CODE DEFINITIONS ====================
// Only define if not already defined by MetaTrader
#ifndef ERR_NO_ERROR
   #define ERR_NO_ERROR                        0
#endif
#ifndef ERR_NO_RESULT
   #define ERR_NO_RESULT                       1
#endif
#ifndef ERR_COMMON_ERROR
   #define ERR_COMMON_ERROR                    2
#endif
#ifndef ERR_INVALID_TRADE_PARAMETERS
   #define ERR_INVALID_TRADE_PARAMETERS        3
#endif
#ifndef ERR_SERVER_BUSY
   #define ERR_SERVER_BUSY                     4
#endif
#ifndef ERR_OLD_VERSION
   #define ERR_OLD_VERSION                     5
#endif
#ifndef ERR_NO_CONNECTION
   #define ERR_NO_CONNECTION                   6
#endif
#ifndef ERR_NOT_ENOUGH_RIGHTS
   #define ERR_NOT_ENOUGH_RIGHTS               7
#endif
#ifndef ERR_TOO_FREQUENT_REQUESTS
   #define ERR_TOO_FREQUENT_REQUESTS           8
#endif
#ifndef ERR_MALFUNCTIONAL_TRADE
   #define ERR_MALFUNCTIONAL_TRADE             9
#endif
#ifndef ERR_ACCOUNT_DISABLED
   #define ERR_ACCOUNT_DISABLED                64
#endif
#ifndef ERR_INVALID_ACCOUNT
   #define ERR_INVALID_ACCOUNT                 65
#endif
#ifndef ERR_TRADE_TIMEOUT
   #define ERR_TRADE_TIMEOUT                   128
#endif
#ifndef ERR_INVALID_PRICE
   #define ERR_INVALID_PRICE                   129
#endif
#ifndef ERR_INVALID_STOPS
   #define ERR_INVALID_STOPS                   130
#endif
#ifndef ERR_INVALID_TRADE_VOLUME
   #define ERR_INVALID_TRADE_VOLUME            131
#endif
#ifndef ERR_MARKET_CLOSED
   #define ERR_MARKET_CLOSED                   132
#endif
#ifndef ERR_TRADE_DISABLED
   #define ERR_TRADE_DISABLED                  133
#endif
#ifndef ERR_NOT_ENOUGH_MONEY
   #define ERR_NOT_ENOUGH_MONEY                134
#endif
#ifndef ERR_PRICE_CHANGED
   #define ERR_PRICE_CHANGED                   135
#endif
#ifndef ERR_REQUOTE
   #define ERR_REQUOTE                         136
#endif
#ifndef ERR_ORDER_LOCKED
   #define ERR_ORDER_LOCKED                    137
#endif
#ifndef ERR_LONG_POSITIONS_ONLY_ALLOWED
   #define ERR_LONG_POSITIONS_ONLY_ALLOWED     138
#endif
#ifndef ERR_TOO_MANY_REQUESTS
   #define ERR_TOO_MANY_REQUESTS               139
#endif
#ifndef ERR_TRADE_MODIFY_DENIED
   #define ERR_TRADE_MODIFY_DENIED             145
#endif
#ifndef ERR_TRADE_CONTEXT_BUSY
   #define ERR_TRADE_CONTEXT_BUSY              146
#endif
#ifndef ERR_TRADE_EXPIRATION_DENIED
   #define ERR_TRADE_EXPIRATION_DENIED         147
#endif
#ifndef ERR_TRADE_TOO_MANY_ORDERS
   #define ERR_TRADE_TOO_MANY_ORDERS           148
#endif
#ifndef ERR_TRADE_HEDGE_PROHIBITED
   #define ERR_TRADE_HEDGE_PROHIBITED          149
#endif
#ifndef ERR_TRADE_PROHIBITED_BY_FIFO
   #define ERR_TRADE_PROHIBITED_BY_FIFO        150
#endif

// ==================== ERROR HANDLER CLASS ====================
class ErrorHandler
{
private:
    // Private constructor to prevent instantiation
    ErrorHandler() {}
    
    // Function pointer type for retry operations
    typedef bool (*OperationFunc)();
    
public:
    // Check if error code indicates an error
    static bool CheckError(int errorCode)
    {
        return (errorCode != ERR_NO_ERROR && errorCode != ERR_NO_RESULT);
    }
    
    // Get error description
    static string GetErrorDescription(int errorCode)
    {
        string description = "Unknown error (" + IntegerToString(errorCode) + ")";
        
        if(errorCode == ERR_NO_ERROR) description = "No error";
        else if(errorCode == ERR_NO_RESULT) description = "No result";
        else if(errorCode == ERR_COMMON_ERROR) description = "Common error";
        else if(errorCode == ERR_INVALID_TRADE_PARAMETERS) description = "Invalid trade parameters";
        else if(errorCode == ERR_SERVER_BUSY) description = "Server busy";
        else if(errorCode == ERR_OLD_VERSION) description = "Old client version";
        else if(errorCode == ERR_NO_CONNECTION) description = "No connection to server";
        else if(errorCode == ERR_NOT_ENOUGH_RIGHTS) description = "Not enough rights";
        else if(errorCode == ERR_TOO_FREQUENT_REQUESTS) description = "Too frequent requests";
        else if(errorCode == ERR_MALFUNCTIONAL_TRADE) description = "Malfunctional trade";
        else if(errorCode == ERR_ACCOUNT_DISABLED) description = "Account disabled";
        else if(errorCode == ERR_INVALID_ACCOUNT) description = "Invalid account";
        else if(errorCode == ERR_TRADE_TIMEOUT) description = "Trade timeout";
        else if(errorCode == ERR_INVALID_PRICE) description = "Invalid price";
        else if(errorCode == ERR_INVALID_STOPS) description = "Invalid stops";
        else if(errorCode == ERR_INVALID_TRADE_VOLUME) description = "Invalid trade volume";
        else if(errorCode == ERR_MARKET_CLOSED) description = "Market closed";
        else if(errorCode == ERR_TRADE_DISABLED) description = "Trade disabled";
        else if(errorCode == ERR_NOT_ENOUGH_MONEY) description = "Not enough money";
        else if(errorCode == ERR_PRICE_CHANGED) description = "Price changed";
        else if(errorCode == ERR_REQUOTE) description = "Requote";
        else if(errorCode == ERR_ORDER_LOCKED) description = "Order locked";
        else if(errorCode == ERR_LONG_POSITIONS_ONLY_ALLOWED) description = "Long positions only allowed";
        else if(errorCode == ERR_TOO_MANY_REQUESTS) description = "Too many requests";
        else if(errorCode == ERR_TRADE_MODIFY_DENIED) description = "Trade modify denied";
        else if(errorCode == ERR_TRADE_CONTEXT_BUSY) description = "Trade context busy";
        else if(errorCode == ERR_TRADE_EXPIRATION_DENIED) description = "Trade expiration denied";
        else if(errorCode == ERR_TRADE_TOO_MANY_ORDERS) description = "Too many orders";
        else if(errorCode == ERR_TRADE_HEDGE_PROHIBITED) description = "Hedge prohibited";
        else if(errorCode == ERR_TRADE_PROHIBITED_BY_FIFO) description = "Trade prohibited by FIFO";
        
        return description;
    }
    
    // ... [Keep all the other functions exactly as they were in the previous version]
    // Just copy everything from HandleOrderError() onward
    
    // Handle order-related errors with your Logger
    static void HandleOrderError(int errorCode, string context = "")
    {
        if (CheckError(errorCode))
        {
            string errorMsg = GetErrorDescription(errorCode);
            string fullMsg = "Order Error: " + errorMsg;
            if (context != "") fullMsg += " [" + context + "]";
            
            Logger::LogError("ErrorHandler", fullMsg);
        }
    }
    
    // Handle market-related errors
    static void HandleMarketError(int errorCode, string context = "")
    {
        if (CheckError(errorCode))
        {
            string errorMsg = GetErrorDescription(errorCode);
            string fullMsg = "Market Error: " + errorMsg;
            if (context != "") fullMsg += " [" + context + "]";
            
            Logger::LogError("ErrorHandler", fullMsg);
        }
    }
    
    // Get and handle last error
    static int GetLastError(string context = "")
    {
        int errorCode = ::GetLastError();
        if (CheckError(errorCode))
        {
            string errorMsg = GetErrorDescription(errorCode);
            string fullMsg = "System Error: " + errorMsg;
            if (context != "") fullMsg += " [" + context + "]";
            
            Logger::LogError("ErrorHandler", fullMsg);
        }
        return errorCode;
    }
    
    // Check error with timestamp for logging
    static bool CheckErrorWithTime(int errorCode, string context = "")
    {
        if (CheckError(errorCode))
        {
            string errorMsg = GetErrorDescription(errorCode);
            string timeStr = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
            string fullMsg = timeStr + " - Error: " + errorMsg;
            if (context != "") fullMsg += " [" + context + "]";
            
            Logger::LogError("ErrorHandler", fullMsg);
            return true;
        }
        return false;
    }
    
    // Check if error is recoverable (can retry)
    static bool IsRecoverableError(int errorCode)
    {
        if(errorCode == ERR_SERVER_BUSY) return true;
        if(errorCode == ERR_TOO_FREQUENT_REQUESTS) return true;
        if(errorCode == ERR_TRADE_TIMEOUT) return true;
        if(errorCode == ERR_PRICE_CHANGED) return true;
        if(errorCode == ERR_REQUOTE) return true;
        if(errorCode == ERR_TRADE_CONTEXT_BUSY) return true;
        if(errorCode == ERR_NO_CONNECTION) return true;
        return false;
    }
    
    // Check if error is fatal (needs immediate attention)
    static bool IsFatalError(int errorCode)
    {
        if(errorCode == ERR_ACCOUNT_DISABLED) return true;
        if(errorCode == ERR_INVALID_ACCOUNT) return true;
        if(errorCode == ERR_NOT_ENOUGH_RIGHTS) return true;
        if(errorCode == ERR_MARKET_CLOSED) return true;
        if(errorCode == ERR_TRADE_DISABLED) return true;
        return false;
    }
    
    // Suggest recovery action for error
    static string GetRecoverySuggestion(int errorCode)
    {
        if(errorCode == ERR_NOT_ENOUGH_MONEY) return "Check account balance or reduce position size";
        if(errorCode == ERR_INVALID_STOPS) return "Adjust stop levels according to broker requirements";
        if(errorCode == ERR_INVALID_TRADE_VOLUME) return "Check volume limits and adjust trade size";
        if(errorCode == ERR_PRICE_CHANGED || errorCode == ERR_REQUOTE) return "Refresh prices and retry trade";
        if(errorCode == ERR_TRADE_CONTEXT_BUSY) return "Wait and retry after short delay";
        if(errorCode == ERR_NO_CONNECTION) return "Check internet connection and restart terminal if needed";
        if(errorCode == ERR_MARKET_CLOSED) return "Wait for market opening hours";
        if(errorCode == ERR_TOO_MANY_REQUESTS) return "Reduce request frequency and implement delays";
        return "Check error details and adjust trading parameters";
    }
    
    // Reset last error
    static void ResetLastError()
    {
        ::ResetLastError();
    }
    
    // Get error details with timestamp
    static string GetErrorDetails(int errorCode, string context = "")
    {
        string details = "Error " + IntegerToString(errorCode) + ": " + GetErrorDescription(errorCode);
        details += "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
        details += "\nAccount: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
        details += "\nSymbol: " + Symbol();
        
        if (context != "") details += "\nContext: " + context;
        
        if (IsRecoverableError(errorCode))
            details += "\nType: Recoverable";
        else if (IsFatalError(errorCode))
            details += "\nType: Fatal";
        else
            details += "\nType: Standard";
            
        details += "\nSuggestion: " + GetRecoverySuggestion(errorCode);
            
        return details;
    }
    
    // Log error with comprehensive details using your Logger
    static void LogErrorWithDetails(int errorCode, string context = "")
    {
        if (CheckError(errorCode))
        {
            string details = GetErrorDetails(errorCode, context);
            Logger::LogError("ErrorHandler", details);
        }
    }
    
    // Handle error with retry logic suggestion
    static int HandleErrorWithRetry(int errorCode, string context = "", int maxRetries = 3)
    {
        if (!CheckError(errorCode))
            return errorCode;
            
        if (IsRecoverableError(errorCode))
        {
            string msg = GetErrorDescription(errorCode) + " - Retry suggested [" + context + "]";
            Logger::Log("ErrorHandler", msg);
            
            // Calculate wait time based on retry count
            int waitMs = 1000 * (maxRetries - 3 + 1);
            Sleep(waitMs);
            
            return maxRetries - 1;
        }
        
        // Log non-recoverable errors
        LogErrorWithDetails(errorCode, context);
            
        return 0;
    }
    
    // Try operation with retry logic
    static bool TryOperationWithRetry(OperationFunc operationFunc, string context = "", int maxRetries = 3)
    {
        int retriesLeft = maxRetries;
        
        while (retriesLeft > 0)
        {
            // Execute operation
            if (operationFunc())
                return true;
                
            // Get error
            int errorCode = GetLastError(context);
            
            // Check if we should retry
            if (IsRecoverableError(errorCode))
            {
                retriesLeft--;
                Logger::Log("ErrorHandler", "Retrying operation (" + IntegerToString(maxRetries - retriesLeft) + "/" + IntegerToString(maxRetries) + ")");
                Sleep(1000);
            }
            else
            {
                return false;
            }
        }
        
        return false;
    }
    
    // Get formatted error message for display
    static string GetDisplayError(int errorCode, string context = "")
    {
        string display = "⚠️ ";
        
        if (IsFatalError(errorCode))
            display += "FATAL: ";
        else if (IsRecoverableError(errorCode))
            display += "WARNING: ";
        else
            display += "ERROR: ";
            
        display += GetErrorDescription(errorCode);
        
        if (context != "")
            display += " [" + context + "]";
            
        display += "\n" + GetRecoverySuggestion(errorCode);
        
        return display;
    }
    
    // Quick error check and log
    static bool QuickCheck(int errorCode, string context = "")
    {
        if (CheckError(errorCode))
        {
            Logger::LogError("ErrorHandler", GetDisplayError(errorCode, context));
            return true;
        }
        return false;
    }
    
    // Get last error without logging
    static int PeekLastError()
    {
        return ::GetLastError();
    }
    
    // Clear and reset error state
    static void ClearErrors()
    {
        ::ResetLastError();
    }
};

// ==================== SIMPLIFIED STATIC FUNCTIONS ====================

// Log error if present
void LogIfError(int errorCode, string context = "")
{
    if (ErrorHandler::CheckError(errorCode))
    {
        Logger::LogError("Error", ErrorHandler::GetErrorDescription(errorCode) + 
                         (context != "" ? " [" + context + "]" : ""));
    }
}

// Get last error and log it
int GetAndLogLastError(string context = "")
{
    int error = ::GetLastError();
    LogIfError(error, context);
    return error;
}