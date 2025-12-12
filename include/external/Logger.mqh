//+------------------------------------------------------------------+
//| Logger - Enhanced Logging System                               |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, Safe Metals EA"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/FormatUtils.mqh"

// ============ LOGGING CONSTANTS ============
#define LOG_LEVEL_TRACE 0
#define LOG_LEVEL_DEBUG 1
#define LOG_LEVEL_INFO 2
#define LOG_LEVEL_WARN 3
#define LOG_LEVEL_ERROR 4
#define LOG_LEVEL_CRITICAL 5

#define LOG_CATEGORY_SYSTEM "SYSTEM"
#define LOG_CATEGORY_TRADE "TRADE"
#define LOG_CATEGORY_SIGNAL "SIGNAL"
#define LOG_CATEGORY_RISK "RISK"
#define LOG_CATEGORY_PERFORMANCE "PERFORMANCE"
#define LOG_CATEGORY_NEWS "NEWS"

#define MAX_LOG_FILESIZE 10485760  // 10MB maximum log file size
#define LOG_FLUSH_INTERVAL 10      // Flush to file every 10 logs
#define MAX_MEMORY_LOGS 1000       // Keep last 1000 logs in memory

// ============ ENUMERATIONS ============
enum ENUM_LOG_LEVEL {
    LOG_LEVEL_TRACE = 0,
    LOG_LEVEL_DEBUG = 1,
    LOG_LEVEL_INFO = 2,
    LOG_LEVEL_WARN = 3,
    LOG_LEVEL_ERROR = 4,
    LOG_LEVEL_CRITICAL = 5
};

enum ENUM_LOG_OUTPUT {
    LOG_OUTPUT_CONSOLE = 0,
    LOG_OUTPUT_FILE = 1,
    LOG_OUTPUT_BOTH = 2,
    LOG_OUTPUT_NONE = 3
};

// ============ STRUCTURES ============
struct LogEntry {
    datetime timestamp;
    ENUM_LOG_LEVEL level;
    string category;
    string message;
    string details;
    string symbol;
    double value;
    int errorCode;
    ulong ticket;
    string function;
    int line;
};

struct LogConfig {
    ENUM_LOG_LEVEL minLevel;
    ENUM_LOG_OUTPUT output;
    string logDirectory;
    string logFilename;
    bool includeTimestamp;
    bool includeLevel;
    bool includeCategory;
    bool includeSymbol;
    bool rotateFiles;
    int maxFileSize;
    int maxFiles;
    bool compressOldLogs;
    bool debugMode;
};

struct TradeLogEntry {
    datetime openTime;
    datetime closeTime;
    string symbol;
    ENUM_POSITION_TYPE type;
    double volume;
    double openPrice;
    double closePrice;
    double stopLoss;
    double takeProfit;
    double profit;
    double swap;
    double commission;
    ulong ticket;
    string strategy;
    string reason;
    double riskReward;
    double durationHours;
};

// ============ GLOBAL VARIABLES ============
LogConfig g_logConfig;
LogEntry g_logBuffer[];
int g_logBufferCount = 0;
int g_logFlushCounter = 0;
int g_fileHandle = INVALID_HANDLE;
string g_currentLogFile = "";

// ============ INITIALIZATION ============

//+------------------------------------------------------------------+
//| InitializeLogger - Initialize logging system                    |
//+------------------------------------------------------------------+
bool InitializeLogger(LogConfig config = NULL)
{
    Print("Initializing Enhanced Logger...");
    
    if(config == NULL)
    {
        // Default configuration
        g_logConfig.minLevel = LOG_LEVEL_INFO;
        g_logConfig.output = LOG_OUTPUT_BOTH;
        g_logConfig.logDirectory = "Logs";
        g_logConfig.logFilename = "SafeMetals_";
        g_logConfig.includeTimestamp = true;
        g_logConfig.includeLevel = true;
        g_logConfig.includeCategory = true;
        g_logConfig.includeSymbol = true;
        g_logConfig.rotateFiles = true;
        g_logConfig.maxFileSize = MAX_LOG_FILESIZE;
        g_logConfig.maxFiles = 10;
        g_logConfig.compressOldLogs = false;
        g_logConfig.debugMode = false;
    }
    else
    {
        g_logConfig = config;
    }
    
    // Create log directory if it doesn't exist
    if(!CreateLogDirectory())
    {
        Print("Failed to create log directory");
        return false;
    }
    
    // Open log file
    if(!OpenLogFile())
    {
        Print("Failed to open log file");
        return false;
    }
    
    // Initialize log buffer
    ArrayResize(g_logBuffer, MAX_MEMORY_LOGS);
    g_logBufferCount = 0;
    g_logFlushCounter = 0;
    
    // Log initialization
    LogSystemEvent("Logger initialized", 
                   StringFormat("Level: %s, Output: %s", 
                               GetLogLevelName(g_logConfig.minLevel),
                               GetOutputName(g_logConfig.output)));
    
    Print("Logger initialized successfully");
    return true;
}

// ============ MAIN LOGGING FUNCTIONS ============

//+------------------------------------------------------------------+
//| LogTrade - Log trade execution and results                      |
//+------------------------------------------------------------------+
void LogTrade(string symbol, ENUM_POSITION_TYPE type, double volume, 
              double openPrice, double closePrice, double profit,
              string reason = "", ulong ticket = 0, string strategy = "")
{
    TradeLogEntry tradeLog;
    tradeLog.openTime = TimeCurrent();
    tradeLog.symbol = symbol;
    tradeLog.type = type;
    tradeLog.volume = volume;
    tradeLog.openPrice = openPrice;
    tradeLog.closePrice = closePrice;
    tradeLog.profit = profit;
    tradeLog.ticket = ticket;
    tradeLog.strategy = strategy;
    tradeLog.reason = reason;
    
    // Calculate risk/reward if stop loss and take profit are available
    // This would be populated by the calling function
    
    // Create log message
    string message = StringFormat("TRADE %s: %s %.2f lots @ %.5f", 
                                  (profit >= 0 ? "PROFIT" : "LOSS"),
                                  (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                                  volume, openPrice);
    
    if(closePrice > 0)
        message += StringFormat(" -> %.5f", closePrice);
    
    message += StringFormat(" | P&L: $%.2f", profit);
    
    if(reason != "")
        message += " | Reason: " + reason;
    
    if(strategy != "")
        message += " | Strategy: " + strategy;
    
    // Log with details
    LogEntry entry;
    entry.timestamp = tradeLog.openTime;
    entry.level = (profit >= 0) ? LOG_LEVEL_INFO : LOG_LEVEL_WARN;
    entry.category = LOG_CATEGORY_TRADE;
    entry.message = message;
    entry.details = FormatTradeDetails(tradeLog);
    entry.symbol = symbol;
    entry.value = profit;
    entry.ticket = ticket;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
    
    // Also write to trade-specific log file
    LogTradeToFile(tradeLog);
}

//+------------------------------------------------------------------+
//| LogError - Log error with details                               |
//+------------------------------------------------------------------+
void LogError(string message, int errorCode = 0, string symbol = "", 
              string details = "", string function = "", int line = 0)
{
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = LOG_LEVEL_ERROR;
    entry.category = LOG_CATEGORY_SYSTEM;
    entry.message = message;
    entry.details = details;
    entry.symbol = symbol;
    entry.errorCode = errorCode;
    entry.function = (function == "") ? __FUNCTION__ : function;
    entry.line = (line == 0) ? __LINE__ : line;
    
    // Format error message with code
    if(errorCode != 0)
        entry.message += StringFormat(" (Error: %d)", errorCode);
    
    WriteLogEntry(entry);
    
    // Critical errors should also show in terminal
    if(g_logConfig.output != LOG_OUTPUT_NONE)
        Print("ERROR: ", entry.message);
}

//+------------------------------------------------------------------+
//| LogSystemEvent - Log system events and state changes            |
//+------------------------------------------------------------------+
void LogSystemEvent(string event, string details = "", 
                   ENUM_LOG_LEVEL level = LOG_LEVEL_INFO, string symbol = "")
{
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = level;
    entry.category = LOG_CATEGORY_SYSTEM;
    entry.message = event;
    entry.details = details;
    entry.symbol = symbol;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
}

// ============ CATEGORY-SPECIFIC LOGGING ============

//+------------------------------------------------------------------+
//| LogSignal - Log trading signals                                 |
//+------------------------------------------------------------------+
void LogSignal(string symbol, string signalType, double score, 
               double price, string details = "")
{
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = LOG_LEVEL_DEBUG;
    entry.category = LOG_CATEGORY_SIGNAL;
    entry.message = StringFormat("SIGNAL: %s %s (Score: %.1f)", 
                                symbol, signalType, score);
    entry.details = details;
    entry.symbol = symbol;
    entry.value = score;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
}

//+------------------------------------------------------------------+
//| LogRiskEvent - Log risk management events                       |
//+------------------------------------------------------------------+
void LogRiskEvent(string event, string symbol = "", double value = 0, 
                 string details = "")
{
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = LOG_LEVEL_WARN;
    entry.category = LOG_CATEGORY_RISK;
    entry.message = "RISK: " + event;
    entry.details = details;
    entry.symbol = symbol;
    entry.value = value;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
}

//+------------------------------------------------------------------+
//| LogPerformance - Log performance metrics                        |
//+------------------------------------------------------------------+
void LogPerformance(string metric, double value, string symbol = "", 
                   string details = "")
{
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = LOG_LEVEL_INFO;
    entry.category = LOG_CATEGORY_PERFORMANCE;
    entry.message = StringFormat("PERF: %s = %.2f", metric, value);
    entry.details = details;
    entry.symbol = symbol;
    entry.value = value;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
}

//+------------------------------------------------------------------+
//| LogNewsEvent - Log news events                                  |
//+------------------------------------------------------------------+
void LogNewsEvent(string newsTitle, string symbol = "", 
                 ENUM_NEWS_IMPORTANCE importance = NEWS_IMPORTANCE_MEDIUM,
                 datetime newsTime = 0)
{
    if(newsTime == 0)
        newsTime = TimeCurrent();
    
    string importanceText = "";
    switch(importance)
    {
        case NEWS_IMPORTANCE_HIGH: importanceText = "HIGH"; break;
        case NEWS_IMPORTANCE_MEDIUM: importanceText = "MEDIUM"; break;
        case NEWS_IMPORTANCE_LOW: importanceText = "LOW"; break;
    }
    
    LogEntry entry;
    entry.timestamp = TimeCurrent();
    entry.level = LOG_LEVEL_INFO;
    entry.category = LOG_CATEGORY_NEWS;
    entry.message = StringFormat("NEWS: %s (%s Impact)", newsTitle, importanceText);
    entry.details = StringFormat("Time: %s", TimeToString(newsTime, TIME_DATE|TIME_SECONDS));
    entry.symbol = symbol;
    entry.function = __FUNCTION__;
    entry.line = __LINE__;
    
    WriteLogEntry(entry);
}

// ============ CORE LOGGING FUNCTIONS ============

//+------------------------------------------------------------------+
//| WriteLogEntry - Core function to write log entry                |
//+------------------------------------------------------------------+
void WriteLogEntry(LogEntry &entry)
{
    // Check if this log level should be recorded
    if(entry.level < g_logConfig.minLevel)
        return;
    
    // Add to memory buffer
    AddToLogBuffer(entry);
    
    // Write to outputs
    WriteToConsole(entry);
    WriteToFile(entry);
    
    // Flush if needed
    if(++g_logFlushCounter >= LOG_FLUSH_INTERVAL)
    {
        FlushLogs();
        g_logFlushCounter = 0;
    }
}

//+------------------------------------------------------------------+
//| AddToLogBuffer - Add entry to memory buffer                     |
//+------------------------------------------------------------------+
void AddToLogBuffer(LogEntry &entry)
{
    if(g_logBufferCount >= MAX_MEMORY_LOGS)
    {
        // Shift buffer (remove oldest entry)
        for(int i = 1; i < MAX_MEMORY_LOGS; i++)
            g_logBuffer[i-1] = g_logBuffer[i];
        g_logBufferCount--;
    }
    
    g_logBuffer[g_logBufferCount] = entry;
    g_logBufferCount++;
}

//+------------------------------------------------------------------+
//| WriteToConsole - Write log entry to console                     |
//+------------------------------------------------------------------+
void WriteToConsole(LogEntry &entry)
{
    if(g_logConfig.output == LOG_OUTPUT_FILE || 
       g_logConfig.output == LOG_OUTPUT_NONE)
        return;
    
    string consoleMessage = FormatLogEntryForConsole(entry);
    Print(consoleMessage);
}

//+------------------------------------------------------------------+
//| WriteToFile - Write log entry to file                           |
//+------------------------------------------------------------------+
void WriteToFile(LogEntry &entry)
{
    if(g_logConfig.output == LOG_OUTPUT_CONSOLE || 
       g_logConfig.output == LOG_OUTPUT_NONE)
        return;
    
    if(g_fileHandle == INVALID_HANDLE)
    {
        if(!OpenLogFile())
            return;
    }
    
    // Check file size and rotate if needed
    if(g_logConfig.rotateFiles && FileSize(g_fileHandle) > g_logConfig.maxFileSize)
        RotateLogFile();
    
    string fileLine = FormatLogEntryForFile(entry);
    FileWrite(g_fileHandle, fileLine);
}

//+------------------------------------------------------------------+
//| LogTradeToFile - Write trade log to separate file               |
//+------------------------------------------------------------------+
void LogTradeToFile(TradeLogEntry &trade)
{
    string tradeFilename = g_logConfig.logDirectory + "\\Trades_" + 
                          TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
    
    int handle = FileOpen(tradeFilename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
    
    if(handle == INVALID_HANDLE)
    {
        // Try to create file with header
        handle = FileOpen(tradeFilename, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
        if(handle != INVALID_HANDLE)
        {
            FileWrite(handle, 
                     "Timestamp", "Symbol", "Type", "Volume", "OpenPrice", 
                     "ClosePrice", "StopLoss", "TakeProfit", "Profit", 
                     "Swap", "Commission", "Ticket", "Strategy", "Reason", 
                     "RiskReward", "DurationHours");
            FileClose(handle);
            
            // Reopen for appending
            handle = FileOpen(tradeFilename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_APPEND, ',');
        }
    }
    else
    {
        FileSeek(handle, 0, SEEK_END);
    }
    
    if(handle != INVALID_HANDLE)
    {
        FileWrite(handle,
                 TimeToString(trade.openTime, TIME_DATE|TIME_SECONDS),
                 trade.symbol,
                 (trade.type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                 DoubleToString(trade.volume, 2),
                 DoubleToString(trade.openPrice, 5),
                 DoubleToString(trade.closePrice, 5),
                 DoubleToString(trade.stopLoss, 5),
                 DoubleToString(trade.takeProfit, 5),
                 DoubleToString(trade.profit, 2),
                 DoubleToString(trade.swap, 2),
                 DoubleToString(trade.commission, 2),
                 IntegerToString(trade.ticket),
                 trade.strategy,
                 trade.reason,
                 DoubleToString(trade.riskReward, 2),
                 DoubleToString(trade.durationHours, 2));
        FileClose(handle);
    }
}

// ============ FORMATTING FUNCTIONS ============

//+------------------------------------------------------------------+
//| FormatLogEntryForConsole - Format log entry for console output  |
//+------------------------------------------------------------------+
string FormatLogEntryForConsole(LogEntry &entry)
{
    string formatted = "";
    
    if(g_logConfig.includeTimestamp)
        formatted += TimeToString(entry.timestamp, TIME_SECONDS) + " ";
    
    if(g_logConfig.includeLevel)
        formatted += GetLogLevelPrefix(entry.level) + " ";
    
    if(g_logConfig.includeCategory && entry.category != "")
        formatted += "[" + entry.category + "] ";
    
    formatted += entry.message;
    
    if(g_logConfig.includeSymbol && entry.symbol != "")
        formatted += " | " + entry.symbol;
    
    if(entry.errorCode != 0)
        formatted += " | Error: " + IntegerToString(entry.errorCode);
    
    if(entry.details != "" && g_logConfig.debugMode)
        formatted += " | " + entry.details;
    
    return formatted;
}

//+------------------------------------------------------------------+
//| FormatLogEntryForFile - Format log entry for file output        |
//+------------------------------------------------------------------+
string FormatLogEntryForFile(LogEntry &entry)
{
    // CSV format: Timestamp,Level,Category,Symbol,Message,Details,ErrorCode,Ticket,Function,Line
    string line = TimeToString(entry.timestamp, TIME_DATE|TIME_SECONDS) + ",";
    line += GetLogLevelName(entry.level) + ",";
    line += entry.category + ",";
    line += entry.symbol + ",";
    line += EscapeCSV(entry.message) + ",";
    line += EscapeCSV(entry.details) + ",";
    line += IntegerToString(entry.errorCode) + ",";
    line += IntegerToString(entry.ticket) + ",";
    line += entry.function + ",";
    line += IntegerToString(entry.line);
    
    return line;
}

//+------------------------------------------------------------------+
//| FormatTradeDetails - Format trade details for logging           |
//+------------------------------------------------------------------+
string FormatTradeDetails(TradeLogEntry &trade)
{
    string details = StringFormat("Ticket: %d | Strategy: %s", 
                                 trade.ticket, trade.strategy);
    
    if(trade.reason != "")
        details += " | Reason: " + trade.reason;
    
    if(trade.stopLoss > 0)
        details += StringFormat(" | SL: %.5f", trade.stopLoss);
    
    if(trade.takeProfit > 0)
        details += StringFormat(" | TP: %.5f", trade.takeProfit);
    
    if(trade.riskReward > 0)
        details += StringFormat(" | R:R: %.2f", trade.riskReward);
    
    if(trade.durationHours > 0)
        details += StringFormat(" | Duration: %.1fh", trade.durationHours);
    
    return details;
}

//+------------------------------------------------------------------+
//| EscapeCSV - Escape string for CSV format                        |
//+------------------------------------------------------------------+
string EscapeCSV(string text)
{
    // Replace quotes with double quotes and wrap in quotes if contains comma
    text = StringReplace(text, "\"", "\"\"");
    
    if(StringFind(text, ",") >= 0 || StringFind(text, "\"") >= 0)
        text = "\"" + text + "\"";
    
    return text;
}

// ============ FILE MANAGEMENT FUNCTIONS ============

//+------------------------------------------------------------------+
//| CreateLogDirectory - Create log directory                       |
//+------------------------------------------------------------------+
bool CreateLogDirectory()
{
    if(!FileIsExist(g_logConfig.logDirectory, FILE_COMMON))
    {
        if(!FolderCreate(g_logConfig.logDirectory, FILE_COMMON))
        {
            Print("Failed to create log directory: ", g_logConfig.logDirectory);
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| OpenLogFile - Open log file for writing                         |
//+------------------------------------------------------------------+
bool OpenLogFile()
{
    // Close existing file if open
    if(g_fileHandle != INVALID_HANDLE)
        FileClose(g_fileHandle);
    
    // Generate filename with date
    g_currentLogFile = g_logConfig.logDirectory + "\\" + 
                      g_logConfig.logFilename + 
                      TimeToString(TimeCurrent(), TIME_DATE) + ".log";
    
    // Open file
    g_fileHandle = FileOpen(g_currentLogFile, 
                           FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_APPEND, 
                           ',');
    
    if(g_fileHandle == INVALID_HANDLE)
    {
        Print("Failed to open log file: ", g_currentLogFile);
        return false;
    }
    
    // Write header if file is new
    if(FileSize(g_fileHandle) == 0)
    {
        FileWrite(g_fileHandle, 
                 "Timestamp", "Level", "Category", "Symbol", 
                 "Message", "Details", "ErrorCode", "Ticket", 
                 "Function", "Line");
    }
    else
    {
        FileSeek(g_fileHandle, 0, SEEK_END);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| RotateLogFile - Rotate log file when it reaches size limit      |
//+------------------------------------------------------------------+
void RotateLogFile()
{
    if(g_fileHandle == INVALID_HANDLE)
        return;
    
    FileClose(g_fileHandle);
    g_fileHandle = INVALID_HANDLE;
    
    // Rename current file
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    timestamp = StringReplace(timestamp, ":", "");
    timestamp = StringReplace(timestamp, " ", "_");
    
    string newFilename = g_currentLogFile + "." + timestamp;
    FileMove(g_currentLogFile, 0, newFilename, FILE_COMMON);
    
    // Open new file
    OpenLogFile();
    
    // Clean up old files if configured
    if(g_logConfig.maxFiles > 0)
        CleanupOldLogs();
}

//+------------------------------------------------------------------+
//| CleanupOldLogs - Clean up old log files                         |
//+------------------------------------------------------------------+
void CleanupOldLogs()
{
    string files[];
    int fileCount = 0;
    
    // Get all log files
    string searchPattern = g_logConfig.logDirectory + "\\" + 
                          g_logConfig.logFilename + "*.log*";
    
    long handle = FileFindFirst(searchPattern, files[0], FILE_COMMON);
    
    if(handle != INVALID_HANDLE)
    {
        fileCount = 1;
        while(FileFindNext(handle, files[fileCount]))
            fileCount++;
        FileFindClose(handle);
    }
    
    // Sort by modification time (newest first)
    ArraySort(files);
    
    // Delete oldest files beyond maxFiles limit
    for(int i = g_logConfig.maxFiles; i < fileCount; i++)
    {
        string fileToDelete = g_logConfig.logDirectory + "\\" + files[i];
        FileDelete(fileToDelete, FILE_COMMON);
    }
}

//+------------------------------------------------------------------+
//| FlushLogs - Flush buffered logs to file                         |
//+------------------------------------------------------------------+
void FlushLogs()
{
    if(g_fileHandle != INVALID_HANDLE)
        FileFlush(g_fileHandle);
}

// ============ UTILITY FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetLogLevelPrefix - Get prefix for log level                    |
//+------------------------------------------------------------------+
string GetLogLevelPrefix(ENUM_LOG_LEVEL level)
{
    switch(level)
    {
        case LOG_LEVEL_TRACE:    return "[TRACE]";
        case LOG_LEVEL_DEBUG:    return "[DEBUG]";
        case LOG_LEVEL_INFO:     return "[INFO]";
        case LOG_LEVEL_WARN:     return "[WARN]";
        case LOG_LEVEL_ERROR:    return "[ERROR]";
        case LOG_LEVEL_CRITICAL: return "[CRITICAL]";
        default:                 return "[UNKNOWN]";
    }
}

//+------------------------------------------------------------------+
//| GetLogLevelName - Get name for log level                        |
//+------------------------------------------------------------------+
string GetLogLevelName(ENUM_LOG_LEVEL level)
{
    switch(level)
    {
        case LOG_LEVEL_TRACE:    return "TRACE";
        case LOG_LEVEL_DEBUG:    return "DEBUG";
        case LOG_LEVEL_INFO:     return "INFO";
        case LOG_LEVEL_WARN:     return "WARN";
        case LOG_LEVEL_ERROR:    return "ERROR";
        case LOG_LEVEL_CRITICAL: return "CRITICAL";
        default:                 return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| GetOutputName - Get name for output type                        |
//+------------------------------------------------------------------+
string GetOutputName(ENUM_LOG_OUTPUT output)
{
    switch(output)
    {
        case LOG_OUTPUT_CONSOLE: return "CONSOLE";
        case LOG_OUTPUT_FILE:    return "FILE";
        case LOG_OUTPUT_BOTH:    return "BOTH";
        case LOG_OUTPUT_NONE:    return "NONE";
        default:                 return "UNKNOWN";
    }
}

// ============ QUERY AND ANALYSIS FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetLogsByCategory - Get logs filtered by category               |
//+------------------------------------------------------------------+
int GetLogsByCategory(string category, LogEntry &results[])
{
    int count = 0;
    ArrayResize(results, g_logBufferCount);
    
    for(int i = 0; i < g_logBufferCount; i++)
    {
        if(g_logBuffer[i].category == category)
        {
            results[count] = g_logBuffer[i];
            count++;
        }
    }
    
    ArrayResize(results, count);
    return count;
}

//+------------------------------------------------------------------+
//| GetLogsByLevel - Get logs filtered by level                     |
//+------------------------------------------------------------------+
int GetLogsByLevel(ENUM_LOG_LEVEL level, LogEntry &results[])
{
    int count = 0;
    ArrayResize(results, g_logBufferCount);
    
    for(int i = 0; i < g_logBufferCount; i++)
    {
        if(g_logBuffer[i].level == level)
        {
            results[count] = g_logBuffer[i];
            count++;
        }
    }
    
    ArrayResize(results, count);
    return count;
}

//+------------------------------------------------------------------+
//| GetLogsBySymbol - Get logs filtered by symbol                   |
//+------------------------------------------------------------------+
int GetLogsBySymbol(string symbol, LogEntry &results[])
{
    int count = 0;
    ArrayResize(results, g_logBufferCount);
    
    for(int i = 0; i < g_logBufferCount; i++)
    {
        if(g_logBuffer[i].symbol == symbol)
        {
            results[count] = g_logBuffer[i];
            count++;
        }
    }
    
    ArrayResize(results, count);
    return count;
}

//+------------------------------------------------------------------+
//| GetRecentLogs - Get most recent logs                            |
//+------------------------------------------------------------------+
int GetRecentLogs(int count, LogEntry &results[])
{
    count = MathMin(count, g_logBufferCount);
    ArrayResize(results, count);
    
    for(int i = 0; i < count; i++)
    {
        results[i] = g_logBuffer[g_logBufferCount - count + i];
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| CountLogsByLevel - Count logs by level                          |
//+------------------------------------------------------------------+
int CountLogsByLevel(ENUM_LOG_LEVEL level)
{
    int count = 0;
    for(int i = 0; i < g_logBufferCount; i++)
    {
        if(g_logBuffer[i].level == level)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| GetErrorSummary - Get summary of errors                         |
//+------------------------------------------------------------------+
string GetErrorSummary()
{
    int errorCount = CountLogsByLevel(LOG_LEVEL_ERROR);
    int criticalCount = CountLogsByLevel(LOG_LEVEL_CRITICAL);
    int warnCount = CountLogsByLevel(LOG_LEVEL_WARN);
    
    return StringFormat("Errors: %d | Critical: %d | Warnings: %d", 
                       errorCount, criticalCount, warnCount);
}

// ============ CLEANUP FUNCTIONS ============

//+------------------------------------------------------------------+
//| CloseLogger - Close logger and clean up resources               |
//+------------------------------------------------------------------+
void CloseLogger()
{
    // Flush any remaining logs
    FlushLogs();
    
    // Close file handle
    if(g_fileHandle != INVALID_HANDLE)
    {
        FileClose(g_fileHandle);
        g_fileHandle = INVALID_HANDLE;
    }
    
    // Clear buffer
    ArrayFree(g_logBuffer);
    g_logBufferCount = 0;
    
    LogSystemEvent("Logger shutdown", "Resources cleaned up");
    Print("Logger shutdown completed");
}

//+------------------------------------------------------------------+
//| ClearLogBuffer - Clear memory log buffer                        |
//+------------------------------------------------------------------+
void ClearLogBuffer()
{
    ArrayFree(g_logBuffer);
    ArrayResize(g_logBuffer, MAX_MEMORY_LOGS);
    g_logBufferCount = 0;
    
    LogSystemEvent("Log buffer cleared", "Memory log buffer cleared");
}

//+------------------------------------------------------------------+
//| SetLogLevel - Change minimum log level at runtime               |
//+------------------------------------------------------------------+
void SetLogLevel(ENUM_LOG_LEVEL newLevel)
{
    g_logConfig.minLevel = newLevel;
    LogSystemEvent("Log level changed", 
                   StringFormat("New level: %s", GetLogLevelName(newLevel)));
}

//+------------------------------------------------------------------+
//| PrintLogSummary - Print summary of current logging state        |
//+------------------------------------------------------------------+
void PrintLogSummary()
{
    Print("=== LOGGER SUMMARY ===");
    Print("Current Log Level: ", GetLogLevelName(g_logConfig.minLevel));
    Print("Output Mode: ", GetOutputName(g_logConfig.output));
    Print("Log Directory: ", g_logConfig.logDirectory);
    Print("Current Log File: ", g_currentLogFile);
    Print("Buffer Size: ", g_logBufferCount, " / ", MAX_MEMORY_LOGS);
    Print("Errors: ", CountLogsByLevel(LOG_LEVEL_ERROR));
    Print("Warnings: ", CountLogsByLevel(LOG_LEVEL_WARN));
    Print("=========================");
}