//+------------------------------------------------------------------+
//| News Service - Enhanced News Data Access                       |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2024, Safe Metals EA"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include "../config/inputs.mqh"
#include "../config/structures.mqh"

// ============ NEWS CONSTANTS ============
#define NEWS_CACHE_DURATION 300           // 5 minutes cache duration
#define ECONOMIC_CALENDAR_URL "https://example.com/economic-calendar" // Replace with actual URL
#define MAX_NEWS_EVENTS 100               // Maximum news events to store
#define IMPORTANCE_HIGH 3
#define IMPORTANCE_MEDIUM 2
#define IMPORTANCE_LOW 1

// ============ ENUMERATIONS ============
enum ENUM_NEWS_IMPORTANCE {
    NEWS_IMPORTANCE_LOW = 1,
    NEWS_IMPORTANCE_MEDIUM = 2,
    NEWS_IMPORTANCE_HIGH = 3
};

enum ENUM_NEWS_CURRENCY {
    NEWS_CURRENCY_USD = 0,
    NEWS_CURRENCY_EUR = 1,
    NEWS_CURRENCY_GBP = 2,
    NEWS_CURRENCY_JPY = 3,
    NEWS_CURRENCY_CAD = 4,
    NEWS_CURRENCY_AUD = 5,
    NEWS_CURRENCY_NZD = 6,
    NEWS_CURRENCY_CHF = 7,
    NEWS_CURRENCY_XAU = 8,    // Gold
    NEWS_CURRENCY_XAG = 9     // Silver
};

// ============ STRUCTURES ============
struct NewsEvent {
    string title;
    string country;
    string currency;
    datetime dateTime;
    ENUM_NEWS_IMPORTANCE importance;
    string previousValue;
    string forecastValue;
    string actualValue;
    int impactLevel;          // 0-100 impact score
    string symbol;            // Affected trading symbol
    bool isScheduled;
    bool isLive;
    string source;
    string eventId;
};

struct EconomicCalendar {
    NewsEvent events[];
    datetime lastUpdate;
    int totalEvents;
    int highImpactEvents;
    int mediumImpactEvents;
    int lowImpactEvents;
};

struct NewsFilter {
    string symbols[];
    ENUM_NEWS_IMPORTANCE minImportance;
    datetime startTime;
    datetime endTime;
    bool includeLiveOnly;
    bool includeScheduledOnly;
    int maxEvents;
};

// ============ GLOBAL VARIABLES ============
EconomicCalendar g_economicCalendar;
datetime g_lastNewsUpdate = 0;
NewsEvent g_cachedNewsEvents[];
int g_cachedEventCount = 0;

// ============ MAIN FUNCTIONS ============

//+------------------------------------------------------------------+
//| LoadNewsEventsFromSource - Load news events from various sources|
//+------------------------------------------------------------------+
bool LoadNewsEventsFromSource(string source = "DEFAULT", NewsFilter &filter = NULL)
{
    Print("Loading news events from source: ", source);
    
    // Clear previous cache if reloading
    if(source == "RELOAD")
    {
        ArrayFree(g_cachedNewsEvents);
        g_cachedEventCount = 0;
        g_lastNewsUpdate = 0;
    }
    
    // Check cache validity
    if(IsNewsCacheValid() && source != "FORCE")
    {
        Print("Using cached news data");
        return true;
    }
    
    bool success = false;
    
    // Select source based on input
    if(source == "WEB_API" || source == "DEFAULT")
    {
        success = LoadNewsFromWebAPI(filter);
    }
    else if(source == "FILE")
    {
        success = LoadNewsFromFile(filter);
    }
    else if(source == "MQL5")
    {
        success = LoadNewsFromMQL5(filter);
    }
    else if(source == "ECONOMIC_CALENDAR")
    {
        success = LoadEconomicCalendarEvents(filter);
    }
    else
    {
        Print("Unknown news source: ", source);
        return false;
    }
    
    if(success)
    {
        g_lastNewsUpdate = TimeCurrent();
        Print("Successfully loaded ", g_cachedEventCount, " news events");
        UpdateEconomicCalendarSummary();
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| GetEconomicCalendar - Get comprehensive economic calendar data  |
//+------------------------------------------------------------------+
EconomicCalendar GetEconomicCalendar(NewsFilter &filter = NULL, bool forceUpdate = false)
{
    if(forceUpdate || !IsNewsCacheValid())
    {
        if(!LoadNewsEventsFromSource("ECONOMIC_CALENDAR", filter))
        {
            Print("Failed to load economic calendar");
            return g_economicCalendar;
        }
    }
    
    // Apply filter if provided
    if(filter != NULL)
    {
        EconomicCalendar filteredCalendar;
        ApplyNewsFilter(filter, filteredCalendar);
        return filteredCalendar;
    }
    
    return g_economicCalendar;
}

// ============ NEWS SOURCE IMPLEMENTATIONS ============

//+------------------------------------------------------------------+
//| LoadNewsFromWebAPI - Load news from web API                     |
//+------------------------------------------------------------------+
bool LoadNewsFromWebAPI(NewsFilter &filter)
{
    Print("Loading news from Web API...");
    
    // Initialize web request
    string url = BuildNewsAPIURL(filter);
    string headers = "Content-Type: application/json\r\n";
    char data[], result[];
    string resultString = "";
    
    // Send HTTP request
    int res = WebRequest("GET", url, headers, 5000, data, result, headers);
    
    if(res == 200) // HTTP OK
    {
        resultString = CharArrayToString(result);
        return ParseNewsJSON(resultString, filter);
    }
    else
    {
        Print("Web API request failed: ", res, " - ", GetWebErrorDescription(res));
        return false;
    }
}

//+------------------------------------------------------------------+
//| LoadNewsFromFile - Load news from local file                    |
//+------------------------------------------------------------------+
bool LoadNewsFromFile(NewsFilter &filter)
{
    Print("Loading news from file...");
    
    string filename = "news_data.csv";
    int filehandle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_ANSI);
    
    if(filehandle == INVALID_HANDLE)
    {
        Print("Failed to open news file: ", filename);
        return false;
    }
    
    ArrayFree(g_cachedNewsEvents);
    g_cachedEventCount = 0;
    
    // Skip header if exists
    FileReadString(filehandle);
    
    while(!FileIsEnding(filehandle))
    {
        string line = FileReadString(filehandle);
        if(line == "") continue;
        
        NewsEvent event = ParseCSVNewsLine(line);
        if(ValidateNewsEvent(event) && ApplyFilterToEvent(event, filter))
        {
            if(g_cachedEventCount >= MAX_NEWS_EVENTS)
                break;
                
            ArrayResize(g_cachedNewsEvents, g_cachedEventCount + 1);
            g_cachedNewsEvents[g_cachedEventCount] = event;
            g_cachedEventCount++;
        }
    }
    
    FileClose(filehandle);
    return g_cachedEventCount > 0;
}

//+------------------------------------------------------------------+
//| LoadNewsFromMQL5 - Load news from MQL5 community                |
//+------------------------------------------------------------------+
bool LoadNewsFromMQL5(NewsFilter &filter)
{
    Print("Loading news from MQL5...");
    
    // This would use MQL5's built-in news functionality
    // For now, implement a placeholder
    
    // Example: Get news from SymbolInfoString
    string news = SymbolInfoString(_Symbol, SYMBOL_NEWS);
    if(news != "")
    {
        // Parse news string
        return ParseMQL5News(news, filter);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| LoadEconomicCalendarEvents - Load economic calendar events      |
//+------------------------------------------------------------------+
bool LoadEconomicCalendarEvents(NewsFilter &filter)
{
    Print("Loading economic calendar events...");
    
    // This would connect to an economic calendar API
    // For now, implement with sample data or file loading
    
    bool success = false;
    
    // Try Web API first
    success = LoadNewsFromWebAPI(filter);
    
    // Fallback to file
    if(!success)
    {
        Print("Web API failed, trying file...");
        success = LoadNewsFromFile(filter);
    }
    
    if(success)
    {
        // Convert cached events to economic calendar format
        ConvertToEconomicCalendar();
    }
    
    return success;
}

// ============ PARSING FUNCTIONS ============

//+------------------------------------------------------------------+
//| ParseNewsJSON - Parse JSON news data                            |
//+------------------------------------------------------------------+
bool ParseNewsJSON(string jsonData, NewsFilter &filter)
{
    // JSON parsing implementation
    // This is a simplified version - in reality you'd use a JSON parser
    
    Print("Parsing JSON news data...");
    
    // Clear existing cache
    ArrayFree(g_cachedNewsEvents);
    g_cachedEventCount = 0;
    
    // Example JSON structure (simplified):
    // {"events": [{"title": "NFP", "currency": "USD", "date": "2024-01-01", ...}]}
    
    // Split JSON into lines and parse
    string lines[];
    int lineCount = StringSplit(jsonData, '\n', lines);
    
    for(int i = 0; i < lineCount; i++)
    {
        if(g_cachedEventCount >= MAX_NEWS_EVENTS)
            break;
            
        NewsEvent event = ParseJSONLine(lines[i]);
        if(ValidateNewsEvent(event) && ApplyFilterToEvent(event, filter))
        {
            ArrayResize(g_cachedNewsEvents, g_cachedEventCount + 1);
            g_cachedNewsEvents[g_cachedEventCount] = event;
            g_cachedEventCount++;
        }
    }
    
    return g_cachedEventCount > 0;
}

//+------------------------------------------------------------------+
//| ParseCSVNewsLine - Parse CSV news line                          |
//+------------------------------------------------------------------+
NewsEvent ParseCSVNewsLine(string line)
{
    NewsEvent event;
    string fields[];
    int fieldCount = StringSplit(line, ',', fields);
    
    if(fieldCount >= 8)
    {
        event.title = fields[0];
        event.country = fields[1];
        event.currency = fields[2];
        event.dateTime = StringToTime(fields[3]);
        event.importance = (ENUM_NEWS_IMPORTANCE)StringToInteger(fields[4]);
        event.previousValue = fields[5];
        event.forecastValue = fields[6];
        event.actualValue = fields[7];
        event.symbol = fields[8];
        event.isScheduled = StringToInteger(fields[9]) > 0;
        event.isLive = StringToInteger(fields[10]) > 0;
        
        // Calculate impact level
        event.impactLevel = CalculateImpactLevel(event);
    }
    
    return event;
}

//+------------------------------------------------------------------+
//| ParseJSONLine - Parse single JSON line                          |
//+------------------------------------------------------------------+
NewsEvent ParseJSONLine(string jsonLine)
{
    NewsEvent event;
    
    // Extract fields from JSON (simplified)
    // In real implementation, use proper JSON parsing
    
    event.title = ExtractJSONField(jsonLine, "title");
    event.currency = ExtractJSONField(jsonLine, "currency");
    event.dateTime = StringToTime(ExtractJSONField(jsonLine, "date"));
    event.importance = (ENUM_NEWS_IMPORTANCE)StringToInteger(ExtractJSONField(jsonLine, "importance"));
    
    // Set default values
    event.country = GetCountryFromCurrency(event.currency);
    event.symbol = GetSymbolFromCurrency(event.currency);
    event.impactLevel = CalculateImpactLevel(event);
    event.isScheduled = true;
    event.isLive = TimeCurrent() >= event.dateTime;
    
    return event;
}

//+------------------------------------------------------------------+
//| ParseMQL5News - Parse MQL5 news string                          |
//+------------------------------------------------------------------+
bool ParseMQL5News(string newsString, NewsFilter &filter)
{
    // Parse MQL5 news format
    // Format: Title|Currency|Date|Importance
    
    string parts[];
    int partCount = StringSplit(newsString, '|', parts);
    
    if(partCount >= 4)
    {
        NewsEvent event;
        event.title = parts[0];
        event.currency = parts[1];
        event.dateTime = StringToTime(parts[2]);
        event.importance = (ENUM_NEWS_IMPORTANCE)StringToInteger(parts[3]);
        event.country = GetCountryFromCurrency(event.currency);
        event.symbol = GetSymbolFromCurrency(event.currency);
        event.impactLevel = CalculateImpactLevel(event);
        event.isScheduled = true;
        event.isLive = TimeCurrent() >= event.dateTime;
        
        if(ValidateNewsEvent(event) && ApplyFilterToEvent(event, filter))
        {
            ArrayResize(g_cachedNewsEvents, 1);
            g_cachedNewsEvents[0] = event;
            g_cachedEventCount = 1;
            return true;
        }
    }
    
    return false;
}

// ============ FILTERING FUNCTIONS ============

//+------------------------------------------------------------------+
//| ApplyNewsFilter - Apply filter to news events                   |
//+------------------------------------------------------------------+
void ApplyNewsFilter(NewsFilter &filter, EconomicCalendar &filteredCalendar)
{
    filteredCalendar.totalEvents = 0;
    filteredCalendar.highImpactEvents = 0;
    filteredCalendar.mediumImpactEvents = 0;
    filteredCalendar.lowImpactEvents = 0;
    
    ArrayResize(filteredCalendar.events, g_economicCalendar.totalEvents);
    
    for(int i = 0; i < g_economicCalendar.totalEvents; i++)
    {
        NewsEvent event = g_economicCalendar.events[i];
        
        if(ApplyFilterToEvent(event, filter))
        {
            filteredCalendar.events[filteredCalendar.totalEvents] = event;
            filteredCalendar.totalEvents++;
            
            // Count by importance
            switch(event.importance)
            {
                case NEWS_IMPORTANCE_HIGH:
                    filteredCalendar.highImpactEvents++;
                    break;
                case NEWS_IMPORTANCE_MEDIUM:
                    filteredCalendar.mediumImpactEvents++;
                    break;
                case NEWS_IMPORTANCE_LOW:
                    filteredCalendar.lowImpactEvents++;
                    break;
            }
        }
    }
    
    ArrayResize(filteredCalendar.events, filteredCalendar.totalEvents);
}

//+------------------------------------------------------------------+
//| ApplyFilterToEvent - Check if event passes filter               |
//+------------------------------------------------------------------+
bool ApplyFilterToEvent(NewsEvent &event, NewsFilter &filter)
{
    if(filter == NULL)
        return true;
    
    // Check importance
    if(event.importance < filter.minImportance)
        return false;
    
    // Check date range
    if(filter.startTime > 0 && event.dateTime < filter.startTime)
        return false;
    if(filter.endTime > 0 && event.dateTime > filter.endTime)
        return false;
    
    // Check symbol filter
    if(ArraySize(filter.symbols) > 0)
    {
        bool symbolMatch = false;
        for(int i = 0; i < ArraySize(filter.symbols); i++)
        {
            if(event.symbol == filter.symbols[i] || 
               StringFind(event.currency, filter.symbols[i]) >= 0)
            {
                symbolMatch = true;
                break;
            }
        }
        if(!symbolMatch) return false;
    }
    
    // Check live/scheduled filters
    if(filter.includeLiveOnly && !event.isLive)
        return false;
    if(filter.includeScheduledOnly && !event.isScheduled)
        return false;
    
    return true;
}

// ============ UTILITY FUNCTIONS ============

//+------------------------------------------------------------------+
//| BuildNewsAPIURL - Build URL for news API                        |
//+------------------------------------------------------------------+
string BuildNewsAPIURL(NewsFilter &filter)
{
    string url = ECONOMIC_CALENDAR_URL;
    url += "?format=json";
    
    if(filter != NULL)
    {
        if(filter.startTime > 0)
            url += "&from=" + TimeToString(filter.startTime, TIME_DATE);
        if(filter.endTime > 0)
            url += "&to=" + TimeToString(filter.endTime, TIME_DATE);
        
        if(ArraySize(filter.symbols) > 0)
        {
            url += "&currencies=";
            for(int i = 0; i < ArraySize(filter.symbols); i++)
            {
                if(i > 0) url += ",";
                url += filter.symbols[i];
            }
        }
        
        if(filter.minImportance > NEWS_IMPORTANCE_LOW)
            url += "&importance=" + IntegerToString(filter.minImportance);
    }
    
    return url;
}

//+------------------------------------------------------------------+
//| CalculateImpactLevel - Calculate news impact level              |
//+------------------------------------------------------------------+
int CalculateImpactLevel(NewsEvent &event)
{
    int impact = 0;
    
    // Base impact from importance
    switch(event.importance)
    {
        case NEWS_IMPORTANCE_HIGH:
            impact = 80;
            break;
        case NEWS_IMPORTANCE_MEDIUM:
            impact = 50;
            break;
        case NEWS_IMPORTANCE_LOW:
            impact = 20;
            break;
    }
    
    // Adjust for currency/symbol
    if(event.currency == "USD" || event.symbol == "XAUUSD" || event.symbol == "XAGUSD")
        impact += 10;
    
    // Adjust if actual value differs significantly from forecast
    if(event.actualValue != "" && event.forecastValue != "")
    {
        double actual = StringToDouble(event.actualValue);
        double forecast = StringToDouble(event.forecastValue);
        if(forecast != 0)
        {
            double deviation = MathAbs((actual - forecast) / forecast) * 100;
            if(deviation > 10) impact += 10;
            else if(deviation > 5) impact += 5;
        }
    }
    
    return MathMin(impact, 100);
}

//+------------------------------------------------------------------+
//| GetCountryFromCurrency - Get country from currency code         |
//+------------------------------------------------------------------+
string GetCountryFromCurrency(string currency)
{
    string countries[][2] = {
        {"USD", "USA"},
        {"EUR", "EU"},
        {"GBP", "UK"},
        {"JPY", "Japan"},
        {"CAD", "Canada"},
        {"AUD", "Australia"},
        {"NZD", "New Zealand"},
        {"CHF", "Switzerland"},
        {"XAU", "Global"},
        {"XAG", "Global"}
    };
    
    for(int i = 0; i < ArraySize(countries); i++)
        if(countries[i][0] == currency)
            return countries[i][1];
    
    return "Unknown";
}

//+------------------------------------------------------------------+
//| GetSymbolFromCurrency - Get trading symbol from currency        |
//+------------------------------------------------------------------+
string GetSymbolFromCurrency(string currency)
{
    string symbols[][2] = {
        {"USD", "USD"},
        {"EUR", "EUR"},
        {"GBP", "GBP"},
        {"JPY", "JPY"},
        {"CAD", "CAD"},
        {"AUD", "AUD"},
        {"NZD", "NZD"},
        {"CHF", "CHF"},
        {"XAU", "XAUUSD"},
        {"XAG", "XAGUSD"}
    };
    
    for(int i = 0; i < ArraySize(symbols); i++)
        if(symbols[i][0] == currency)
            return symbols[i][1];
    
    return currency;
}

//+------------------------------------------------------------------+
//| IsNewsCacheValid - Check if news cache is still valid           |
//+------------------------------------------------------------------+
bool IsNewsCacheValid()
{
    return (TimeCurrent() - g_lastNewsUpdate) < NEWS_CACHE_DURATION && g_cachedEventCount > 0;
}

//+------------------------------------------------------------------+
//| ConvertToEconomicCalendar - Convert cache to economic calendar  |
//+------------------------------------------------------------------+
void ConvertToEconomicCalendar()
{
    g_economicCalendar.totalEvents = g_cachedEventCount;
    g_economicCalendar.highImpactEvents = 0;
    g_economicCalendar.mediumImpactEvents = 0;
    g_economicCalendar.lowImpactEvents = 0;
    
    ArrayResize(g_economicCalendar.events, g_cachedEventCount);
    ArrayCopy(g_economicCalendar.events, g_cachedNewsEvents);
    
    for(int i = 0; i < g_cachedEventCount; i++)
    {
        switch(g_cachedNewsEvents[i].importance)
        {
            case NEWS_IMPORTANCE_HIGH:
                g_economicCalendar.highImpactEvents++;
                break;
            case NEWS_IMPORTANCE_MEDIUM:
                g_economicCalendar.mediumImpactEvents++;
                break;
            case NEWS_IMPORTANCE_LOW:
                g_economicCalendar.lowImpactEvents++;
                break;
        }
    }
    
    g_economicCalendar.lastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| UpdateEconomicCalendarSummary - Update calendar summary         |
//+------------------------------------------------------------------+
void UpdateEconomicCalendarSummary()
{
    g_economicCalendar.totalEvents = g_cachedEventCount;
    g_economicCalendar.lastUpdate = TimeCurrent();
    
    // Recalculate counts
    g_economicCalendar.highImpactEvents = 0;
    g_economicCalendar.mediumImpactEvents = 0;
    g_economicCalendar.lowImpactEvents = 0;
    
    for(int i = 0; i < g_cachedEventCount; i++)
    {
        switch(g_cachedNewsEvents[i].importance)
        {
            case NEWS_IMPORTANCE_HIGH:
                g_economicCalendar.highImpactEvents++;
                break;
            case NEWS_IMPORTANCE_MEDIUM:
                g_economicCalendar.mediumImpactEvents++;
                break;
            case NEWS_IMPORTANCE_LOW:
                g_economicCalendar.lowImpactEvents++;
                break;
        }
    }
}

//+------------------------------------------------------------------+
//| ValidateNewsEvent - Validate news event data                    |
//+------------------------------------------------------------------+
bool ValidateNewsEvent(NewsEvent &event)
{
    if(event.title == "" || event.currency == "" || event.dateTime == 0)
        return false;
    
    if(event.importance < NEWS_IMPORTANCE_LOW || event.importance > NEWS_IMPORTANCE_HIGH)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| ExtractJSONField - Extract field from JSON string               |
//+------------------------------------------------------------------+
string ExtractJSONField(string json, string fieldName)
{
    string pattern = "\"" + fieldName + "\":\"([^\"]+)\"";
    int pos = StringFind(json, pattern);
    
    if(pos >= 0)
    {
        int start = StringFind(json, ":", pos) + 2; // Skip : and "
        int end = StringFind(json, "\"", start);
        return StringSubstr(json, start, end - start);
    }
    
    return "";
}

//+------------------------------------------------------------------+
//| GetWebErrorDescription - Get description for web errors         |
//+------------------------------------------------------------------+
string GetWebErrorDescription(int errorCode)
{
    switch(errorCode)
    {
        case -1: return "WebRequest not allowed";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 500: return "Internal Server Error";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        default: return "HTTP Error: " + IntegerToString(errorCode);
    }
}

// ============ HELPER FUNCTIONS ============

//+------------------------------------------------------------------+
//| GetUpcomingHighImpactEvents - Get upcoming high impact events   |
//+------------------------------------------------------------------+
NewsEvent GetUpcomingHighImpactEvents(int hoursAhead = 24)
{
    NewsFilter filter;
    filter.minImportance = NEWS_IMPORTANCE_HIGH;
    filter.startTime = TimeCurrent();
    filter.endTime = TimeCurrent() + (hoursAhead * 3600);
    
    EconomicCalendar calendar = GetEconomicCalendar(filter);
    return calendar;
}

//+------------------------------------------------------------------+
//| IsNewsBlackoutPeriod - Check if symbol in news blackout         |
//+------------------------------------------------------------------+
bool IsNewsBlackoutPeriod(string symbol, int minutesBefore = 30, int minutesAfter = 30)
{
    NewsFilter filter;
    string symbols[1];
    symbols[0] = symbol;
    ArrayCopy(filter.symbols, symbols);
    filter.minImportance = NEWS_IMPORTANCE_MEDIUM;
    
    EconomicCalendar calendar = GetEconomicCalendar(filter);
    
    datetime currentTime = TimeCurrent();
    datetime blackoutStart, blackoutEnd;
    
    for(int i = 0; i < calendar.totalEvents; i++)
    {
        blackoutStart = calendar.events[i].dateTime - (minutesBefore * 60);
        blackoutEnd = calendar.events[i].dateTime + (minutesAfter * 60);
        
        if(currentTime >= blackoutStart && currentTime <= blackoutEnd)
        {
            Print("News blackout for ", symbol, ": ", calendar.events[i].title);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| PrintNewsSummary - Print summary of loaded news                 |
//+------------------------------------------------------------------+
void PrintNewsSummary()
{
    Print("=== NEWS SERVICE SUMMARY ===");
    Print("Last Update: ", TimeToString(g_lastNewsUpdate, TIME_DATE|TIME_SECONDS));
    Print("Cached Events: ", g_cachedEventCount);
    Print("Economic Calendar Events: ", g_economicCalendar.totalEvents);
    Print("High Impact: ", g_economicCalendar.highImpactEvents);
    Print("Medium Impact: ", g_economicCalendar.mediumImpactEvents);
    Print("Low Impact: ", g_economicCalendar.lowImpactEvents);
    Print("============================");
}

//+------------------------------------------------------------------+
//| ClearNewsCache - Clear the news cache                           |
//+------------------------------------------------------------------+
void ClearNewsCache()
{
    ArrayFree(g_cachedNewsEvents);
    ArrayFree(g_economicCalendar.events);
    g_cachedEventCount = 0;
    g_lastNewsUpdate = 0;
    g_economicCalendar.totalEvents = 0;
    g_economicCalendar.highImpactEvents = 0;
    g_economicCalendar.mediumImpactEvents = 0;
    g_economicCalendar.lowImpactEvents = 0;
    
    Print("News cache cleared");
}