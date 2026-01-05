// Logger.mqh - Enhanced Static Logger with Chart Display and Portfolio Visualization
class Logger
{
private:
    // File handle - minimal state for file operations
    static int fileHandle;
    static string currentFileName;
    
    // Chart display settings
    static bool chartEnabled;
    static int chartUpdateFrequency;
    static datetime lastChartUpdate;
    static string chartBuffer;
    static bool bufferNeedsClearing;  // NEW: Track if buffer needs clearing
    
    // Get formatted timestamp
    static string GetTimestamp()
    {
        datetime currentTime = TimeCurrent();
        return TimeToString(currentTime, TIME_DATE|TIME_SECONDS);
    }
    
    // Get time only (for fast logging)
    static string GetTimeOnly()
    {
        datetime currentTime = TimeCurrent();
        return TimeToString(currentTime, TIME_SECONDS);
    }
    
    // Build log message
    static string BuildMessage(string module, string timestamp, string reason)
    {
        return StringFormat("[%s] [%s] %s", module, timestamp, reason);
    }
    
    // Core logging function
    static void LogInternal(string module, string reason, 
                           bool logToFile = true, bool logToConsole = true)
    {
        string timestamp = GetTimestamp();
        string message = BuildMessage(module, timestamp, reason);
        
        // Log to console if enabled
        if (logToConsole)
            Print(message);
        
        // Log to file if enabled and file is open
        if (logToFile && fileHandle != INVALID_HANDLE)
            FileWrite(fileHandle, message);
    }
    
    // Update chart display if needed
    static void UpdateChartIfNeeded()
    {
        if (!chartEnabled) return;
        
        datetime currentTime = TimeCurrent();
        if (currentTime - lastChartUpdate >= chartUpdateFrequency)
        {
            Comment(chartBuffer);
            lastChartUpdate = currentTime;
        }
    }
    
    // Add text to chart buffer (with optional clearing)
    static void AddToChartBuffer(string text, bool clearFirst = false)
    {
        if (clearFirst || bufferNeedsClearing)
        {
            chartBuffer = "";
            bufferNeedsClearing = false;
        }
        chartBuffer += text + "\n";
        UpdateChartIfNeeded();
    }
    
    // Clear chart buffer
    static void ClearChartBuffer()
    {
        chartBuffer = "";
        bufferNeedsClearing = false;
        if (chartEnabled)
            Comment("");
    }
    
    // Mark buffer for clearing on next add
    static void MarkBufferForClearing()
    {
        bufferNeedsClearing = true;
    }

public:
    // Initialize logger with file (call once at start)
    static bool Initialize(string fileName = "", bool logToFile = true, bool logToConsole = true, int chartFrequency = 2)
    {
        // Default filename if not provided
        if (fileName == "")
            fileName = MQLInfoString(MQL_PROGRAM_NAME) + ".log";
        
        // Store the filename
        currentFileName = fileName;
        
        // Initialize chart settings
        chartEnabled = logToConsole;
        chartUpdateFrequency = chartFrequency;
        lastChartUpdate = 0;
        chartBuffer = "";
        bufferNeedsClearing = false;  // Initialize new flag
        
        // Close existing file if open
        if (fileHandle != INVALID_HANDLE)
        {
            FileClose(fileHandle);
            fileHandle = INVALID_HANDLE;
        }
            
        // Open new file if needed
        if (logToFile)
        {
            int flags = FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_ANSI;
            fileHandle = FileOpen(fileName, flags);
            if (fileHandle != INVALID_HANDLE)
            {
                FileSeek(fileHandle, 0, SEEK_END);
                LogInternal("Logger", "Log file opened: " + fileName, false, logToConsole);
                return true;
            }
            return false;
        }
        
        return true;
    }
    
    // Shutdown logger (call at end)
    static void Shutdown()
    {
        if (fileHandle != INVALID_HANDLE)
        {
            LogInternal("Logger", "Logger shutting down", false, true);
            FileClose(fileHandle);
            fileHandle = INVALID_HANDLE;
        }
        currentFileName = "";
        ClearChartBuffer();
    }
    
    // ===== CHART CONTROL METHODS =====
    
    // Enable/disable chart updates
    static void EnableChart(bool enable)
    {
        chartEnabled = enable;
        if (!enable)
            ClearChartBuffer();
    }
    
    // Set chart update frequency
    static void SetChartFrequency(int seconds)
    {
        chartUpdateFrequency = seconds;
    }
    
    // Clear all chart comments
    static void ClearChart()
    {
        ClearChartBuffer();
    }
    
    // Check if chart is enabled
    static bool IsChartEnabled()
    {
        return chartEnabled;
    }
    
    // ===== MAIN LOGGING METHODS =====
    
    // Generic log method
    static void Log(string module, string reason, 
                   bool logToFile = true, bool logToConsole = true)
    {
        LogInternal(module, reason, logToFile, logToConsole);
    }
    
    // Log with error code
    static void LogError(string module, string reason, int errorCode = 0)
    {
        string errorMsg = (errorCode != 0) ? reason + " (Error: " + IntegerToString(errorCode) + ")" : reason;
        LogInternal(module, errorMsg, true, true);
    }
    
    // Log trade-related information
    static void LogTrade(string module, string symbol, string operation, double volume, double price = 0.0)
    {
        string reason;
        if (price > 0)
            reason = StringFormat("%s %s %.2f lots @ %.5f", operation, symbol, volume, price);
        else
            reason = StringFormat("%s %s %.2f lots", operation, symbol, volume);
        
        LogInternal(module, reason, true, true);
    }
    
    // ===== PERFORMANCE-ORIENTED METHODS =====
    
    // Fast logging - minimal string concatenation
    static void LogFast(string module, string reason)
    {
        string timeStr = GetTimeOnly();
        string message;
        StringConcatenate(message, 
            "[", module, "] ",
            "[", timeStr, "] ",
            reason
        );
        Print(message);
        
        // Also write to file if open (minimal check)
        if (fileHandle != INVALID_HANDLE)
            FileWrite(fileHandle, message);
    }
    
    // Ultra-fast logging - pre-formatted module
    static void LogUltraFast(const string &module, const string &reason)
    {
        string timeStr = GetTimeOnly();
        Print("[", module, "] [", timeStr, "] ", reason);
    }
    
    // Ultra-fast trade logging
    static void LogTradeFast(const string &module, const string &symbol, const string &operation, double volume)
    {
        string timeStr = GetTimeOnly();
        Print("[", module, "] [", timeStr, "] ", operation, " ", symbol, " ", DoubleToString(volume, 2), " lots");
    }
    
    // ===== CHART VISUALIZATION METHODS =====
    
    // Show single symbol score on chart
    static void ShowScoreFast(const string &symbol, double score, const string &signal, double confidence = 0.0)
    {
        // Mark buffer for clearing on next frame
        MarkBufferForClearing();
        
        string colorCode;
        string strength;
        
        if (score >= 0.8)
        {
            colorCode = (signal == "BUY") ? "\\x25" : "\\x26"; // Green up/down arrow
            strength = "STRONG";
        }
        else if (score >= 0.6)
        {
            colorCode = (signal == "BUY") ? "\\x25" : "\\x26"; // Green up/down arrow (lighter)
            strength = "MODERATE";
        }
        else if (score >= 0.4)
        {
            colorCode = "\\xA6"; // Yellow diamond
            strength = "WEAK";
        }
        else
        {
            colorCode = "\\xA8"; // Gray dot
            strength = "VERY WEAK";
        }
        
        string displayText;
        if (confidence > 0)
            displayText = StringFormat("%s %s: %.2f (%s) [%.0f%%]", 
                colorCode, symbol, score, signal, confidence * 100);
        else
            displayText = StringFormat("%s %s: %.2f (%s)", 
                colorCode, symbol, score, signal);
        
        AddToChartBuffer(displayText);
    }
    
    // Show trading decision
    static void ShowDecisionFast(const string &symbol, int direction, double confidence, const string &reason)
    {
        // Mark buffer for clearing on next frame
        MarkBufferForClearing();
        
        string signal;
        string arrow;
        
        switch(direction)
        {
            case 1:
                signal = "BUY";
                arrow = "\\x25"; // Up arrow
                break;
            case -1:
                signal = "SELL";
                arrow = "\\x26"; // Down arrow
                break;
            default:
                signal = "HOLD";
                arrow = "\\xA6"; // Yellow diamond
                break;
        }
        
        string displayText = StringFormat("%s %s: %s (%.0f%%)\n   %s", 
            arrow, symbol, signal, confidence * 100, reason);
        
        AddToChartBuffer(displayText);
    }
    
    // Show portfolio overview
    static void ShowPortfolioFast(const string &symbols[], const double &scores[], const int &directions[])
    {
        // Mark buffer for clearing on next frame
        MarkBufferForClearing();
        
        int count = MathMin(ArraySize(symbols), MathMin(ArraySize(scores), ArraySize(directions)));
        
        AddToChartBuffer("=== PORTFOLIO OVERVIEW ===");
        
        for (int i = 0; i < count; i++)
        {
            string arrow;
            switch(directions[i])
            {
                case 1:
                    arrow = "\\x25"; // Up arrow
                    break;
                case -1:
                    arrow = "\\x26"; // Down arrow
                    break;
                default:
                    arrow = "\\xA6"; // Yellow diamond
                    break;
            }
            
            string displayText = StringFormat("%s %s: %.2f", arrow, symbols[i], scores[i]);
            AddToChartBuffer(displayText, (i == 0)); // Clear only on first line
        }
        
        AddToChartBuffer("========================");
    }
    
    // Show risk metrics
    static void ShowRiskMetrics(double riskPercent, double drawdownPercent, double sharpeRatio, int positions)
    {
        // Mark buffer for clearing on next frame
        MarkBufferForClearing();
        
        string riskLevel;
        string riskColor;
        
        if (riskPercent >= 5.0)
        {
            riskLevel = "HIGH";
            riskColor = "\\x27"; // Red triangle
        }
        else if (riskPercent >= 2.5)
        {
            riskLevel = "MEDIUM";
            riskColor = "\\xA6"; // Yellow diamond
        }
        else
        {
            riskLevel = "LOW";
            riskColor = "\\x25"; // Green triangle
        }
        
        AddToChartBuffer("=== RISK METRICS ===");
        AddToChartBuffer(StringFormat("%s Risk: %.1f%% (%s)", riskColor, riskPercent, riskLevel));
        AddToChartBuffer(StringFormat("Drawdown: %.1f%%", drawdownPercent));
        AddToChartBuffer(StringFormat("Sharpe: %.2f", sharpeRatio));
        AddToChartBuffer(StringFormat("Positions: %d", positions));
        AddToChartBuffer("===================");
    }
    
    // Clear and display single frame (for use in timer callbacks)
    static void DisplaySingleFrame(const string &text)
    {
        ClearChartBuffer();
        AddToChartBuffer(text);
    }
    
    // ===== UTILITY METHODS =====
    
    // Check if file logging is available
    static bool IsFileLoggingAvailable()
    {
        return (fileHandle != INVALID_HANDLE);
    }
    
    // Get current log filename (if any)
    static string GetLogFileName()
    {
        if (fileHandle != INVALID_HANDLE)
        {
            return (currentFileName != "") ? currentFileName : "Unknown";
        }
        return "No file open";
    }
    
    // Get file handle status
    static int GetFileHandleStatus()
    {
        return fileHandle;
    }
    
    // Log current memory usage (for debugging)
    static void LogMemoryUsage(string module)
    {
        #ifdef __MQL5__
        // In MQL5, you can use TerminalInfoInteger
        long memoryUsed = TerminalInfoInteger(TERMINAL_MEMORY_USED);
        string reason = "Memory used: " + IntegerToString(memoryUsed) + " bytes";
        LogFast(module, reason);
        #else
        // In MQL4, memory info is not directly available
        LogFast(module, "Memory usage info not available in MQL4");
        #endif
    }
    
    // Flush file buffer
    static void Flush()
    {
        if (fileHandle != INVALID_HANDLE)
        {
            FileFlush(fileHandle);
        }
    }
    
    // Log with custom timestamp
    static void LogWithTimestamp(string module, string reason, datetime customTime)
    {
        string timestamp = TimeToString(customTime, TIME_DATE|TIME_SECONDS);
        string message = BuildMessage(module, timestamp, reason);
        
        Print(message);
        if (fileHandle != INVALID_HANDLE)
            FileWrite(fileHandle, message);
    }
};

// Static member initialization
int Logger::fileHandle = INVALID_HANDLE;
string Logger::currentFileName = "";
bool Logger::chartEnabled = false;
int Logger::chartUpdateFrequency = 2;
datetime Logger::lastChartUpdate = 0;
string Logger::chartBuffer = "";
bool Logger::bufferNeedsClearing = false;  // Initialize new static member