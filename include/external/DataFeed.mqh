//+------------------------------------------------------------------+
//| Data Feed - Market Data Access                                 |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, Safe Metals EA"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include "../config/inputs.mqh"

// ============ DATA FEED CONSTANTS ============
#define DATA_CACHE_DURATION 60           // 1 minute cache duration
#define MAX_HISTORICAL_BARS 1000         // Maximum bars for historical data
#define DATA_FEED_TIMEOUT 5000           // 5 second timeout for data requests
#define DEFAULT_TIMEFRAME PERIOD_M15     // Default timeframe
#define TICK_HISTORY_SIZE 1000           // Size of tick history buffer

// ============ ENUMERATIONS ============
enum ENUM_DATA_SOURCE {
    DATA_SOURCE_LOCAL = 0,      // Local terminal data
    DATA_SOURCE_WEB = 1,        // Web API data
    DATA_SOURCE_FILE = 2,       // File-based data
    DATA_SOURCE_CUSTOM = 3      // Custom data source
};

enum ENUM_DATA_TYPE {
    DATA_TYPE_TICKS = 0,        // Tick data
    DATA_TYPE_BARS = 1,         // Bar data (OHLC)
    DATA_TYPE_INDICATORS = 2,   // Indicator data
    DATA_TYPE_FUNDAMENTAL = 3   // Fundamental data
};

enum ENUM_DATA_QUALITY {
    DATA_QUALITY_REAL_TIME = 0, // Real-time data
    DATA_QUALITY_DELAYED = 1,   // Delayed data
    DATA_QUALITY_HISTORICAL = 2 // Historical data
};

// ============ STRUCTURES ============
struct MarketData {
    string symbol;
    double bid;
    double ask;
    double last;
    double volume;
    datetime time;
    double spread;
    double point;
    int digits;
    double tickSize;
    double tickValue;
    double high;
    double low;
    double open;
    double change;
    double changePercent;
    long volumeTotal;
    bool isConnected;
    ENUM_DATA_QUALITY quality;
};

struct HistoricalData {
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    datetime timestamps[];
    double open[];
    double high[];
    double low[];
    double close[];
    long volume[];
    double spread[];
    int bars;
    datetime fromDate;
    datetime toDate;
    bool isComplete;
};

struct TickData {
    datetime time;
    double bid;
    double ask;
    double last;
    long volume;
    int flags;
    string symbol;
};

struct DataRequest {
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    ENUM_DATA_TYPE dataType;
    int barsRequired;
    datetime fromDate;
    datetime toDate;
    bool includeVolume;
    bool includeSpread;
    ENUM_DATA_SOURCE source;
};

struct DataFeedConfig {
    ENUM_DATA_SOURCE primarySource;
    ENUM_DATA_SOURCE fallbackSource;
    int cacheDuration;
    bool autoRefresh;
    int refreshInterval;
    bool validateData;
    bool logRequests;
    string apiKey;              // For web APIs
    string apiEndpoint;         // For web APIs
};

// ============ GLOBAL VARIABLES ============
MarketData g_cachedMarketData[];
HistoricalData g_cachedHistoricalData[];
TickData g_tickHistory[];
int g_tickHistoryCount = 0;
datetime g_lastDataUpdate = 0;
DataFeedConfig g_dataConfig;

// ============ INITIALIZATION ============

//+------------------------------------------------------------------+
//| InitializeDataFeed - Initialize data feed with configuration    |
//+------------------------------------------------------------------+
bool InitializeDataFeed(DataFeedConfig config)
{
    Print("Initializing Data Feed...");
    
    g_dataConfig = config;
    
    // Validate configuration
    if(!ValidateDataFeedConfig(config))
    {
        Print("Invalid data feed configuration");
        return false;
    }
    
    // Initialize arrays
    ArrayFree(g_cachedMarketData);
    ArrayFree(g_cachedHistoricalData);
    ArrayFree(g_tickHistory);
    
    // Initialize tick history buffer
    ArrayResize(g_tickHistory, TICK_HISTORY_SIZE);
    g_tickHistoryCount = 0;
    
    // Test connection to primary data source
    if(!TestDataSource(config.primarySource))
    {
        Print("Primary data source unavailable");
        
        if(config.fallbackSource != DATA_SOURCE_LOCAL)
        {
            Print("Testing fallback data source...");
            if(!TestDataSource(config.fallbackSource))
            {
                Print("All data sources unavailable");
                return false;
            }
        }
    }
    
    Print("Data Feed initialized successfully");
    Print("Primary Source: ", EnumToString(config.primarySource));
    Print("Fallback Source: ", EnumToString(config.fallbackSource));
    Print("Auto Refresh: ", config.autoRefresh ? "Enabled" : "Disabled");
    
    return true;
}

// ============ MAIN FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetMarketData - Get current market data for symbols             |
//+------------------------------------------------------------------+
MarketData GetMarketData(string symbol, bool forceUpdate = false)
{
    // Check cache first
    if(!forceUpdate && IsMarketDataCacheValid(symbol))
    {
        if(g_dataConfig.logRequests)
            Print("Using cached market data for ", symbol);
        
        return GetCachedMarketData(symbol);
    }
    
    MarketData data;
    data.symbol = symbol;
    data.time = TimeCurrent();
    data.isConnected = false;
    
    // Try primary source first
    bool success = FetchMarketDataFromSource(symbol, data, g_dataConfig.primarySource);
    
    // Fallback if primary fails
    if(!success && g_dataConfig.fallbackSource != g_dataConfig.primarySource)
    {
        if(g_dataConfig.logRequests)
            Print("Primary source failed, trying fallback for ", symbol);
        
        success = FetchMarketDataFromSource(symbol, data, g_dataConfig.fallbackSource);
    }
    
    if(success)
    {
        data.isConnected = true;
        UpdateMarketDataCache(symbol, data);
        
        if(g_dataConfig.logRequests)
            Print("Market data retrieved for ", symbol, 
                  " | Bid: ", data.bid, " | Ask: ", data.ask);
    }
    else
    {
        Print("Failed to retrieve market data for ", symbol);
        data = GetFallbackMarketData(symbol);
    }
    
    return data;
}

//+------------------------------------------------------------------+
//| GetHistoricalData - Get historical data for symbols             |
//+------------------------------------------------------------------+
HistoricalData GetHistoricalData(DataRequest request)
{
    HistoricalData data;
    data.symbol = request.symbol;
    data.timeframe = request.timeframe;
    data.isComplete = false;
    
    // Check cache first
    if(IsHistoricalDataCacheValid(request))
    {
        if(g_dataConfig.logRequests)
            Print("Using cached historical data for ", request.symbol);
        
        return GetCachedHistoricalData(request);
    }
    
    // Try primary source
    bool success = FetchHistoricalDataFromSource(request, data, g_dataConfig.primarySource);
    
    // Fallback if primary fails
    if(!success && g_dataConfig.fallbackSource != g_dataConfig.primarySource)
    {
        if(g_dataConfig.logRequests)
            Print("Primary source failed, trying fallback for historical data");
        
        success = FetchHistoricalDataFromSource(request, data, g_dataConfig.fallbackSource);
    }
    
    if(success)
    {
        data.isComplete = true;
        UpdateHistoricalDataCache(request, data);
        
        if(g_dataConfig.logRequests)
            Print("Historical data retrieved for ", request.symbol, 
                  " | Bars: ", data.bars, " | Timeframe: ", TimeframeToString(request.timeframe));
    }
    else
    {
        Print("Failed to retrieve historical data for ", request.symbol);
        data = GetFallbackHistoricalData(request);
    }
    
    return data;
}

// ============ DATA SOURCE IMPLEMENTATIONS ============

//+------------------------------------------------------------------+
//| FetchMarketDataFromSource - Fetch market data from source       |
//+------------------------------------------------------------------+
bool FetchMarketDataFromSource(string symbol, MarketData &data, ENUM_DATA_SOURCE source)
{
    switch(source)
    {
        case DATA_SOURCE_LOCAL:
            return GetMarketDataFromLocal(symbol, data);
        case DATA_SOURCE_WEB:
            return GetMarketDataFromWeb(symbol, data);
        case DATA_SOURCE_FILE:
            return GetMarketDataFromFile(symbol, data);
        case DATA_SOURCE_CUSTOM:
            return GetMarketDataFromCustom(symbol, data);
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| FetchHistoricalDataFromSource - Fetch historical data           |
//+------------------------------------------------------------------+
bool FetchHistoricalDataFromSource(DataRequest request, HistoricalData &data, ENUM_DATA_SOURCE source)
{
    switch(source)
    {
        case DATA_SOURCE_LOCAL:
            return GetHistoricalDataFromLocal(request, data);
        case DATA_SOURCE_WEB:
            return GetHistoricalDataFromWeb(request, data);
        case DATA_SOURCE_FILE:
            return GetHistoricalDataFromFile(request, data);
        case DATA_SOURCE_CUSTOM:
            return GetHistoricalDataFromCustom(request, data);
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| GetMarketDataFromLocal - Get market data from local terminal    |
//+------------------------------------------------------------------+
bool GetMarketDataFromLocal(string symbol, MarketData &data)
{
    // Check if symbol is selected
    if(!SymbolSelect(symbol, true))
    {
        Print("Symbol not available locally: ", symbol);
        return false;
    }
    
    // Get current prices
    data.bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    data.ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    data.last = SymbolInfoDouble(symbol, SYMBOL_LAST);
    
    // Get market info
    data.spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    data.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    data.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    data.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    data.tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    
    // Get volume
    data.volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME);
    data.volumeTotal = SymbolInfoInteger(symbol, SYMBOL_VOLUME_TOTAL);
    
    // Get daily prices
    data.high = SymbolInfoDouble(symbol, SYMBOL_LASTHIGH);
    data.low = SymbolInfoDouble(symbol, SYMBOL_LASTLOW);
    data.open = iOpen(symbol, PERIOD_D1, 0);
    
    // Calculate change
    double previousClose = iClose(symbol, PERIOD_D1, 1);
    if(previousClose > 0)
    {
        data.change = data.last - previousClose;
        data.changePercent = (data.change / previousClose) * 100;
    }
    
    data.quality = DATA_QUALITY_REAL_TIME;
    data.time = TimeCurrent();
    
    return ValidateMarketData(data);
}

//+------------------------------------------------------------------+
//| GetHistoricalDataFromLocal - Get historical data locally        |
//+------------------------------------------------------------------+
bool GetHistoricalDataFromLocal(DataRequest request, HistoricalData &data)
{
    string symbol = request.symbol;
    ENUM_TIMEFRAMES timeframe = request.timeframe;
    int barsRequired = request.barsRequired;
    
    if(barsRequired <= 0 || barsRequired > MAX_HISTORICAL_BARS)
        barsRequired = MAX_HISTORICAL_BARS;
    
    // Resize arrays
    ArrayResize(data.timestamps, barsRequired);
    ArrayResize(data.open, barsRequired);
    ArrayResize(data.high, barsRequired);
    ArrayResize(data.low, barsRequired);
    ArrayResize(data.close, barsRequired);
    
    if(request.includeVolume)
        ArrayResize(data.volume, barsRequired);
    if(request.includeSpread)
        ArrayResize(data.spread, barsRequired);
    
    // Copy data
    int copied = CopyTime(symbol, timeframe, 0, barsRequired, data.timestamps);
    if(copied <= 0) return false;
    
    copied = CopyOpen(symbol, timeframe, 0, barsRequired, data.open);
    if(copied <= 0) return false;
    
    copied = CopyHigh(symbol, timeframe, 0, barsRequired, data.high);
    if(copied <= 0) return false;
    
    copied = CopyLow(symbol, timeframe, 0, barsRequired, data.low);
    if(copied <= 0) return false;
    
    copied = CopyClose(symbol, timeframe, 0, barsRequired, data.close);
    if(copied <= 0) return false;
    
    if(request.includeVolume)
        CopyTickVolume(symbol, timeframe, 0, barsRequired, data.volume);
    
    // Get spread data if requested
    if(request.includeSpread)
    {
        for(int i = 0; i < barsRequired; i++)
        {
            // Spread is not directly available in historical data
            // You might need to calculate or estimate this
            data.spread[i] = 0;
        }
    }
    
    data.bars = barsRequired;
    data.fromDate = data.timestamps[barsRequired - 1];
    data.toDate = data.timestamps[0];
    
    return ValidateHistoricalData(data);
}

//+------------------------------------------------------------------+
//| GetMarketDataFromWeb - Get market data from web API             |
//+------------------------------------------------------------------+
bool GetMarketDataFromWeb(string symbol, MarketData &data)
{
    if(g_dataConfig.apiEndpoint == "" || g_dataConfig.apiKey == "")
    {
        Print("Web API not configured");
        return false;
    }
    
    // Build API request URL
    string url = BuildMarketDataAPIURL(symbol);
    string headers = BuildAPIHeaders();
    
    // Send web request
    char dataBuffer[], result[];
    string resultString = "";
    
    int res = WebRequest("GET", url, headers, DATA_FEED_TIMEOUT, dataBuffer, result, headers);
    
    if(res == 200) // HTTP OK
    {
        resultString = CharArrayToString(result);
        return ParseMarketDataJSON(resultString, data);
    }
    else
    {
        Print("Web API request failed: ", res);
        return false;
    }
}

//+------------------------------------------------------------------+
//| GetHistoricalDataFromWeb - Get historical data from web API     |
//+------------------------------------------------------------------+
bool GetHistoricalDataFromWeb(DataRequest request, HistoricalData &data)
{
    if(g_dataConfig.apiEndpoint == "" || g_dataConfig.apiKey == "")
    {
        Print("Web API not configured");
        return false;
    }
    
    // Build API request URL
    string url = BuildHistoricalDataAPIURL(request);
    string headers = BuildAPIHeaders();
    
    // Send web request
    char dataBuffer[], result[];
    string resultString = "";
    
    int res = WebRequest("GET", url, headers, DATA_FEED_TIMEOUT, dataBuffer, result, headers);
    
    if(res == 200) // HTTP OK
    {
        resultString = CharArrayToString(result);
        return ParseHistoricalDataJSON(resultString, data);
    }
    else
    {
        Print("Web API request failed: ", res);
        return false;
    }
}

//+------------------------------------------------------------------+
//| GetMarketDataFromFile - Get market data from file               |
//+------------------------------------------------------------------+
bool GetMarketDataFromFile(string symbol, MarketData &data)
{
    string filename = "market_data_" + symbol + ".csv";
    
    if(!FileIsExist(filename, FILE_COMMON))
    {
        Print("Market data file not found: ", filename);
        return false;
    }
    
    int filehandle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON);
    if(filehandle == INVALID_HANDLE)
    {
        Print("Failed to open market data file: ", filename);
        return false;
    }
    
    // Read the latest data (assuming CSV with newest data first)
    string line = FileReadString(filehandle);
    FileClose(filehandle);
    
    return ParseMarketDataCSV(line, data);
}

//+------------------------------------------------------------------+
//| GetHistoricalDataFromFile - Get historical data from file       |
//+------------------------------------------------------------------+
bool GetHistoricalDataFromFile(DataRequest request, HistoricalData &data)
{
    string filename = "historical_" + request.symbol + "_" + 
                      IntegerToString(request.timeframe) + ".csv";
    
    if(!FileIsExist(filename, FILE_COMMON))
    {
        Print("Historical data file not found: ", filename);
        return false;
    }
    
    int filehandle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON);
    if(filehandle == INVALID_HANDLE)
    {
        Print("Failed to open historical data file: ", filename);
        return false;
    }
    
    // Skip header
    FileReadString(filehandle);
    
    int barsRead = 0;
    int maxBars = MathMin(request.barsRequired, MAX_HISTORICAL_BARS);
    
    ArrayResize(data.timestamps, maxBars);
    ArrayResize(data.open, maxBars);
    ArrayResize(data.high, maxBars);
    ArrayResize(data.low, maxBars);
    ArrayResize(data.close, maxBars);
    
    if(request.includeVolume)
        ArrayResize(data.volume, maxBars);
    
    while(!FileIsEnding(filehandle) && barsRead < maxBars)
    {
        string line = FileReadString(filehandle);
        if(line == "") continue;
        
        if(ParseHistoricalDataCSVLine(line, data, barsRead))
            barsRead++;
    }
    
    FileClose(filehandle);
    
    data.bars = barsRead;
    if(barsRead > 0)
    {
        data.fromDate = data.timestamps[barsRead - 1];
        data.toDate = data.timestamps[0];
    }
    
    return barsRead > 0;
}

// ============ CUSTOM DATA SOURCE PLACEHOLDERS ============

//+------------------------------------------------------------------+
//| GetMarketDataFromCustom - Custom market data implementation     |
//+------------------------------------------------------------------+
bool GetMarketDataFromCustom(string symbol, MarketData &data)
{
    // Placeholder for custom data source implementation
    // Override this function in your derived class
    
    Print("Custom market data source not implemented");
    return false;
}

//+------------------------------------------------------------------+
//| GetHistoricalDataFromCustom - Custom historical data impl       |
//+------------------------------------------------------------------+
bool GetHistoricalDataFromCustom(DataRequest request, HistoricalData &data)
{
    // Placeholder for custom data source implementation
    // Override this function in your derived class
    
    Print("Custom historical data source not implemented");
    return false;
}

// ============ CACHE MANAGEMENT ============

//+------------------------------------------------------------------+
//| UpdateMarketDataCache - Update market data cache                |
//+------------------------------------------------------------------+
void UpdateMarketDataCache(string symbol, MarketData &data)
{
    int index = FindCachedMarketDataIndex(symbol);
    
    if(index == -1)
    {
        // Add new entry
        int size = ArraySize(g_cachedMarketData);
        ArrayResize(g_cachedMarketData, size + 1);
        g_cachedMarketData[size] = data;
    }
    else
    {
        // Update existing entry
        g_cachedMarketData[index] = data;
    }
    
    g_lastDataUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| UpdateHistoricalDataCache - Update historical data cache        |
//+------------------------------------------------------------------+
void UpdateHistoricalDataCache(DataRequest request, HistoricalData &data)
{
    // Simple cache implementation - could be enhanced with hash keys
    int size = ArraySize(g_cachedHistoricalData);
    ArrayResize(g_cachedHistoricalData, size + 1);
    g_cachedHistoricalData[size] = data;
}

//+------------------------------------------------------------------+
//| GetCachedMarketData - Get market data from cache                |
//+------------------------------------------------------------------+
MarketData GetCachedMarketData(string symbol)
{
    int index = FindCachedMarketDataIndex(symbol);
    
    if(index != -1)
        return g_cachedMarketData[index];
    
    // Return empty data if not found
    MarketData emptyData;
    emptyData.symbol = symbol;
    return emptyData;
}

//+------------------------------------------------------------------+
//| GetCachedHistoricalData - Get historical data from cache        |
//+------------------------------------------------------------------+
HistoricalData GetCachedHistoricalData(DataRequest request)
{
    // Simple implementation - returns first matching cache
    for(int i = 0; i < ArraySize(g_cachedHistoricalData); i++)
    {
        if(g_cachedHistoricalData[i].symbol == request.symbol &&
           g_cachedHistoricalData[i].timeframe == request.timeframe &&
           g_cachedHistoricalData[i].bars >= request.barsRequired)
        {
            return g_cachedHistoricalData[i];
        }
    }
    
    // Return empty data if not found
    HistoricalData emptyData;
    emptyData.symbol = request.symbol;
    return emptyData;
}

//+------------------------------------------------------------------+
//| IsMarketDataCacheValid - Check if market data cache is valid    |
//+------------------------------------------------------------------+
bool IsMarketDataCacheValid(string symbol)
{
    if((TimeCurrent() - g_lastDataUpdate) > g_dataConfig.cacheDuration)
        return false;
    
    return FindCachedMarketDataIndex(symbol) != -1;
}

//+------------------------------------------------------------------+
//| IsHistoricalDataCacheValid - Check historical data cache        |
//+------------------------------------------------------------------+
bool IsHistoricalDataCacheValid(DataRequest request)
{
    // Check cache for matching request
    for(int i = 0; i < ArraySize(g_cachedHistoricalData); i++)
    {
        if(g_cachedHistoricalData[i].symbol == request.symbol &&
           g_cachedHistoricalData[i].timeframe == request.timeframe &&
           g_cachedHistoricalData[i].bars >= request.barsRequired)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FindCachedMarketDataIndex - Find index of cached market data    |
//+------------------------------------------------------------------+
int FindCachedMarketDataIndex(string symbol)
{
    for(int i = 0; i < ArraySize(g_cachedMarketData); i++)
    {
        if(g_cachedMarketData[i].symbol == symbol)
            return i;
    }
    
    return -1;
}

// ============ FALLBACK FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetFallbackMarketData - Get fallback market data                |
//+------------------------------------------------------------------+
MarketData GetFallbackMarketData(string symbol)
{
    MarketData data;
    data.symbol = symbol;
    data.time = TimeCurrent();
    data.isConnected = false;
    data.quality = DATA_QUALITY_DELAYED;
    
    // Try to get basic data from symbol properties
    data.bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    data.ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    data.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    data.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    return data;
}

//+------------------------------------------------------------------+
//| GetFallbackHistoricalData - Get fallback historical data        |
//+------------------------------------------------------------------+
HistoricalData GetFallbackHistoricalData(DataRequest request)
{
    HistoricalData data;
    data.symbol = request.symbol;
    data.timeframe = request.timeframe;
    data.isComplete = false;
    
    // Try to get minimal historical data
    int bars = MathMin(request.barsRequired, 100);
    
    ArrayResize(data.close, bars);
    int copied = CopyClose(request.symbol, request.timeframe, 0, bars, data.close);
    
    if(copied > 0)
    {
        data.bars = copied;
        data.isComplete = true;
    }
    
    return data;
}

// ============ VALIDATION FUNCTIONS ============

//+------------------------------------------------------------------+
//| ValidateMarketData - Validate market data integrity             |
//+------------------------------------------------------------------+
bool ValidateMarketData(MarketData &data)
{
    if(data.symbol == "")
        return false;
    
    if(data.bid <= 0 || data.ask <= 0)
        return false;
    
    if(data.ask <= data.bid) // Ask should be higher than bid
        return false;
    
    if(data.point <= 0)
        return false;
    
    if(data.digits < 2 || data.digits > 8)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| ValidateHistoricalData - Validate historical data integrity     |
//+------------------------------------------------------------------+
bool ValidateHistoricalData(HistoricalData &data)
{
    if(data.symbol == "" || data.bars <= 0)
        return false;
    
    if(data.bars != ArraySize(data.close) || 
       data.bars != ArraySize(data.open) ||
       data.bars != ArraySize(data.high) ||
       data.bars != ArraySize(data.low))
        return false;
    
    // Check for valid prices
    for(int i = 0; i < data.bars; i++)
    {
        if(data.open[i] <= 0 || data.high[i] <= 0 || 
           data.low[i] <= 0 || data.close[i] <= 0)
            return false;
        
        if(data.high[i] < data.low[i])
            return false;
        
        if(data.high[i] < data.open[i] || data.high[i] < data.close[i])
            return false;
        
        if(data.low[i] > data.open[i] || data.low[i] > data.close[i])
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| ValidateDataFeedConfig - Validate data feed configuration       |
//+------------------------------------------------------------------+
bool ValidateDataFeedConfig(DataFeedConfig config)
{
    if(config.cacheDuration <= 0)
        return false;
    
    if(config.refreshInterval <= 0 && config.autoRefresh)
        return false;
    
    if(config.primarySource == DATA_SOURCE_WEB && 
       (config.apiEndpoint == "" || config.apiKey == ""))
    {
        Print("Web API requires endpoint and API key");
        return false;
    }
    
    return true;
}

// ============ API URL BUILDERS ============

//+------------------------------------------------------------------+
//| BuildMarketDataAPIURL - Build URL for market data API           |
//+------------------------------------------------------------------+
string BuildMarketDataAPIURL(string symbol)
{
    string url = g_dataConfig.apiEndpoint + "/marketdata/" + symbol;
    url += "?apikey=" + g_dataConfig.apiKey;
    url += "&format=json";
    
    return url;
}

//+------------------------------------------------------------------+
//| BuildHistoricalDataAPIURL - Build URL for historical data API   |
//+------------------------------------------------------------------+
string BuildHistoricalDataAPIURL(DataRequest request)
{
    string url = g_dataConfig.apiEndpoint + "/historical/" + request.symbol;
    url += "?apikey=" + g_dataConfig.apiKey;
    url += "&timeframe=" + IntegerToString(request.timeframe);
    url += "&bars=" + IntegerToString(request.barsRequired);
    
    if(request.fromDate > 0)
        url += "&from=" + TimeToString(request.fromDate, TIME_DATE);
    
    if(request.toDate > 0)
        url += "&to=" + TimeToString(request.toDate, TIME_DATE);
    
    url += "&format=json";
    
    return url;
}

//+------------------------------------------------------------------+
//| BuildAPIHeaders - Build headers for API requests                |
//+------------------------------------------------------------------+
string BuildAPIHeaders()
{
    string headers = "Content-Type: application/json\r\n";
    headers += "Authorization: Bearer " + g_dataConfig.apiKey + "\r\n";
    headers += "User-Agent: SafeMetalsEA/1.0\r\n";
    
    return headers;
}

// ============ PARSING FUNCTIONS ============

//+------------------------------------------------------------------+
//| ParseMarketDataJSON - Parse market data from JSON               |
//+------------------------------------------------------------------+
bool ParseMarketDataJSON(string jsonData, MarketData &data)
{
    // JSON parsing implementation
    // This is a simplified placeholder
    
    Print("Parsing market data JSON...");
    
    // Extract fields from JSON
    data.bid = StringToDouble(ExtractJSONValue(jsonData, "bid"));
    data.ask = StringToDouble(ExtractJSONValue(jsonData, "ask"));
    data.last = StringToDouble(ExtractJSONValue(jsonData, "last"));
    data.volume = StringToDouble(ExtractJSONValue(jsonData, "volume"));
    
    return ValidateMarketData(data);
}

//+------------------------------------------------------------------+
//| ParseHistoricalDataJSON - Parse historical data from JSON       |
//+------------------------------------------------------------------+
bool ParseHistoricalDataJSON(string jsonData, HistoricalData &data)
{
    // JSON parsing implementation
    // This is a simplified placeholder
    
    Print("Parsing historical data JSON...");
    
    // Parse JSON array of bars
    // Implementation would depend on the specific API response format
    
    return true;
}

//+------------------------------------------------------------------+
//| ParseMarketDataCSV - Parse market data from CSV                 |
//+------------------------------------------------------------------+
bool ParseMarketDataCSV(string csvLine, MarketData &data)
{
    string fields[];
    int fieldCount = StringSplit(csvLine, ',', fields);
    
    if(fieldCount >= 5)
    {
        data.symbol = fields[0];
        data.bid = StringToDouble(fields[1]);
        data.ask = StringToDouble(fields[2]);
        data.last = StringToDouble(fields[3]);
        data.volume = StringToDouble(fields[4]);
        data.time = StringToTime(fields[5]);
        
        return ValidateMarketData(data);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| ParseHistoricalDataCSVLine - Parse historical data CSV line     |
//+------------------------------------------------------------------+
bool ParseHistoricalDataCSVLine(string csvLine, HistoricalData &data, int index)
{
    string fields[];
    int fieldCount = StringSplit(csvLine, ',', fields);
    
    if(fieldCount >= 6)
    {
        data.timestamps[index] = StringToTime(fields[0]);
        data.open[index] = StringToDouble(fields[1]);
        data.high[index] = StringToDouble(fields[2]);
        data.low[index] = StringToDouble(fields[3]);
        data.close[index] = StringToDouble(fields[4]);
        
        if(ArraySize(data.volume) > index)
            data.volume[index] = StringToInteger(fields[5]);
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| ExtractJSONValue - Extract value from JSON string               |
//+------------------------------------------------------------------+
string ExtractJSONValue(string json, string key)
{
    string pattern = "\"" + key + "\":\"([^\"]+)\"";
    int pos = StringFind(json, pattern);
    
    if(pos >= 0)
    {
        int start = StringFind(json, ":", pos) + 2; // Skip : and "
        int end = StringFind(json, "\"", start);
        return StringSubstr(json, start, end - start);
    }
    
    return "";
}

// ============ TEST FUNCTIONS ============

//+------------------------------------------------------------------+
//| TestDataSource - Test connectivity to data source               |
//+------------------------------------------------------------------+
bool TestDataSource(ENUM_DATA_SOURCE source)
{
    switch(source)
    {
        case DATA_SOURCE_LOCAL:
            return TestLocalDataSource();
        case DATA_SOURCE_WEB:
            return TestWebDataSource();
        case DATA_SOURCE_FILE:
            return TestFileDataSource();
        case DATA_SOURCE_CUSTOM:
            return TestCustomDataSource();
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| TestLocalDataSource - Test local data source                    |
//+------------------------------------------------------------------+
bool TestLocalDataSource()
{
    // Test by getting a common symbol
    double bid = SymbolInfoDouble("EURUSD", SYMBOL_BID);
    return bid > 0;
}

//+------------------------------------------------------------------+
//| TestWebDataSource - Test web data source                        |
//+------------------------------------------------------------------+
bool TestWebDataSource()
{
    if(g_dataConfig.apiEndpoint == "")
        return false;
    
    // Simple ping test
    string url = g_dataConfig.apiEndpoint + "/ping";
    string headers = BuildAPIHeaders();
    
    char data[], result[];
    int res = WebRequest("GET", url, headers, DATA_FEED_TIMEOUT, data, result, headers);
    
    return res == 200;
}

//+------------------------------------------------------------------+
//| TestFileDataSource - Test file data source                      |
//+------------------------------------------------------------------+
bool TestFileDataSource()
{
    // Check if we can access a test file
    string testFile = "test_market_data.csv";
    
    if(FileIsExist(testFile, FILE_COMMON))
        return true;
    
    // Try to create a test file
    int filehandle = FileOpen(testFile, FILE_WRITE|FILE_CSV|FILE_COMMON);
    if(filehandle != INVALID_HANDLE)
    {
        FileWrite(filehandle, "Test data");
        FileClose(filehandle);
        FileDelete(testFile, FILE_COMMON);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| TestCustomDataSource - Test custom data source                  |
//+------------------------------------------------------------------+
bool TestCustomDataSource()
{
    // Custom implementation
    return true;
}

// ============ UTILITY FUNCTIONS ============

//+------------------------------------------------------------------+
//| TimeframeToString - Convert timeframe to string                 |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return IntegerToString(tf);
    }
}

//+------------------------------------------------------------------+
//| EnumToString - Convert enum to string (simplified)              |
//+------------------------------------------------------------------+
string EnumToString(ENUM_DATA_SOURCE source)
{
    switch(source)
    {
        case DATA_SOURCE_LOCAL: return "LOCAL";
        case DATA_SOURCE_WEB: return "WEB";
        case DATA_SOURCE_FILE: return "FILE";
        case DATA_SOURCE_CUSTOM: return "CUSTOM";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| ClearDataCache - Clear all data caches                          |
//+------------------------------------------------------------------+
void ClearDataCache()
{
    ArrayFree(g_cachedMarketData);
    ArrayFree(g_cachedHistoricalData);
    ArrayFree(g_tickHistory);
    g_tickHistoryCount = 0;
    g_lastDataUpdate = 0;
    
    Print("Data cache cleared");
}

//+------------------------------------------------------------------+
//| PrintDataFeedStatus - Print data feed status                    |
//+------------------------------------------------------------------+
void PrintDataFeedStatus()
{
    Print("=== DATA FEED STATUS ===");
    Print("Primary Source: ", EnumToString(g_dataConfig.primarySource));
    Print("Fallback Source: ", EnumToString(g_dataConfig.fallbackSource));
    Print("Auto Refresh: ", g_dataConfig.autoRefresh ? "Enabled" : "Disabled");
    Print("Cache Duration: ", g_dataConfig.cacheDuration, " seconds");
    Print("Cached Market Data: ", ArraySize(g_cachedMarketData), " symbols");
    Print("Cached Historical Data: ", ArraySize(g_cachedHistoricalData), " datasets");
    Print("Last Update: ", TimeToString(g_lastDataUpdate, TIME_DATE|TIME_SECONDS));
    Print("=========================");
}

//+------------------------------------------------------------------+
//| GetDataFeedConfiguration - Get current configuration            |
//+------------------------------------------------------------------+
DataFeedConfig GetDataFeedConfiguration()
{
    return g_dataConfig;
}

//+------------------------------------------------------------------+
//| UpdateDataFeedConfiguration - Update configuration              |
//+------------------------------------------------------------------+
bool UpdateDataFeedConfiguration(DataFeedConfig newConfig)
{
    if(!ValidateDataFeedConfig(newConfig))
        return false;
    
    g_dataConfig = newConfig;
    ClearDataCache();
    
    Print("Data feed configuration updated");
    return true;
}