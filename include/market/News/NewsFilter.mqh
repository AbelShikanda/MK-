//+------------------------------------------------------------------+
//|                                   NewsFilter.mqh                 |
//|                        News Event Detection and Filtering        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include "../../config/inputs.mqh"

//+------------------------------------------------------------------+
//| News Event Structure                                            |
//+------------------------------------------------------------------+
struct NewsEvent
{
    datetime time;
    string currency;
    string impact;
};

// Global news events array (externally accessible)
NewsEvent newsEvents[];

//+------------------------------------------------------------------+
//| Initialize news events                                          |
//+------------------------------------------------------------------+
void InitializeNewsEvents()
{
    ArrayResize(newsEvents, 2);
    
    // Example news events (simplified implementation)
    // In a real system, you would load these from an API or file
    newsEvents[0].time = TimeCurrent() + 3600;
    newsEvents[0].currency = "USD";
    newsEvents[0].impact = "High";
    
    newsEvents[1].time = TimeCurrent() + 7200;
    newsEvents[1].currency = "EUR";
    newsEvents[1].impact = "Medium";
    
    // Print("NEWS_INIT: News events loaded (simplified implementation)");
}

//+------------------------------------------------------------------+
//| Check if we're in news blackout period                          |
//+------------------------------------------------------------------+
bool IsNewsBlackoutPeriod(string symbol)
{
    if(!EnableNewsFilter) return false;
    
    datetime now = TimeCurrent();
    string symbolCurrency = StringSubstr(symbol, 0, 3);
    
    for(int i = 0; i < ArraySize(newsEvents); i++)
    {
        if(newsEvents[i].currency == symbolCurrency || newsEvents[i].currency == "USD")
        {
            datetime newsTime = newsEvents[i].time;
            datetime startBlackout = newsTime - (NewsFilterMinutesBefore * 60);
            datetime endBlackout = newsTime + (NewsFilterMinutesAfter * 60);
            
            if(now >= startBlackout && now <= endBlackout)
            {
                // Print("NEWS_FILTER: News blackout for ", symbol, ": ", newsEvents[i].currency, " ", 
                //       newsEvents[i].impact, " impact at ", TimeToString(newsTime));
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Load news events from file or API (example implementation)      |
//+------------------------------------------------------------------+
void LoadNewsEventsFromSource()
{
    // This is a template for loading real news data
    // You could implement loading from:
    // 1. CSV file
    // 2. Web API (ForexFactory, Investing.com, etc.)
    // 3. RSS feed
    
    // Print("NEWS_LOAD: Loading news events from external source...");
    
    // Example: Clear and resize array
    ArrayFree(newsEvents);
    ArrayResize(newsEvents, 0);
    
    // Example: Add some test events
    int count = 0;
    
    // Add today's FOMC meeting (example)
    MqlDateTime today;
    TimeToStruct(TimeCurrent(), today);
    today.hour = 14;
    today.min = 0;
    today.sec = 0;
    
    ArrayResize(newsEvents, count + 1);
    newsEvents[count].time = StructToTime(today);
    newsEvents[count].currency = "USD";
    newsEvents[count].impact = "High";
    count++;
    
    // Add ECB press conference (example)
    today.hour = 12;
    today.min = 45;
    
    ArrayResize(newsEvents, count + 1);
    newsEvents[count].time = StructToTime(today);
    newsEvents[count].currency = "EUR";
    newsEvents[count].impact = "Medium";
    count++;
    
    // PrintFormat("NEWS_LOAD: Loaded %d news events", count);
}

//+------------------------------------------------------------------+
//| Check for upcoming high-impact news                             |
//+------------------------------------------------------------------+
bool HasUpcomingHighImpactNews(string symbol, int minutesAhead = 60)
{
    datetime now = TimeCurrent();
    datetime futureTime = now + (minutesAhead * 60);
    string symbolCurrency = StringSubstr(symbol, 0, 3);
    
    for(int i = 0; i < ArraySize(newsEvents); i++)
    {
        if((newsEvents[i].currency == symbolCurrency || newsEvents[i].currency == "USD") && 
           newsEvents[i].impact == "High")
        {
            if(newsEvents[i].time >= now && newsEvents[i].time <= futureTime)
            {
                // Print("UPCOMING_HIGH_IMPACT: ", symbol, " has high impact news at ", 
                //       TimeToString(newsEvents[i].time));
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get time until next news event (in minutes)                     |
//+------------------------------------------------------------------+
int MinutesUntilNextNews(string symbol)
{
    datetime now = TimeCurrent();
    string symbolCurrency = StringSubstr(symbol, 0, 3);
    int minMinutes = INT_MAX;
    
    for(int i = 0; i < ArraySize(newsEvents); i++)
    {
        if(newsEvents[i].currency == symbolCurrency || newsEvents[i].currency == "USD")
        {
            if(newsEvents[i].time > now)
            {
                int minutes = int((newsEvents[i].time - now) / 60);
                minMinutes = MathMin(minMinutes, minutes);
            }
        }
    }
    
    return (minMinutes == INT_MAX) ? -1 : minMinutes;
}

//+------------------------------------------------------------------+
//| Reduce position sizes before high-impact news                   |
//+------------------------------------------------------------------+
double GetNewsAdjustedLotSize(string symbol, double originalLotSize)
{
    if(!EnableNewsFilter) return originalLotSize;
    
    int minutesUntilNews = MinutesUntilNextNews(symbol);
    
    if(minutesUntilNews >= 0 && minutesUntilNews <= 30)
    {
        // Reduce lot size as news approaches
        double reductionFactor = 0.5; // Reduce to 50% normal size
        // PrintFormat("NEWS_ADJUSTMENT: Reducing lot size to %.0f%% before upcoming news", 
        //            reductionFactor * 100);
        return originalLotSize * reductionFactor;
    }
    
    return originalLotSize;
}