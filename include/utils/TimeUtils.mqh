class TimeUtils
{
private:
    // Static variables for tracking last bar times per symbol/timeframe
    static string lastBarTimes[];
    
public:
    // Check if current time is within trading session
    static bool IsTradingSession(const string symbol = NULL)
    {
        string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
        
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // Check day of week (0-Sunday, 1-Monday, ..., 6-Saturday)
        if (dt.day_of_week == 0 || dt.day_of_week == 6) // Weekend
            return false;
        
        // Get symbol session times
        datetime sessionStart, sessionEnd;
        if (!GetTradingSession(sym, sessionStart, sessionEnd))
            return false;
        
        // Convert to minutes since midnight
        MqlDateTime startDt, endDt, currentDt;
        TimeToStruct(sessionStart, startDt);
        TimeToStruct(sessionEnd, endDt);
        TimeCurrent(currentDt);
        
        int startTime = startDt.hour * 60 + startDt.min;
        int endTime = endDt.hour * 60 + endDt.min;
        int currentTime = currentDt.hour * 60 + currentDt.min;
        
        return (currentTime >= startTime && currentTime <= endTime);
    }
    
    // Get trading session times for a symbol
    static bool GetTradingSession(const string symbol, datetime &startTime, datetime &endTime)
    {
        string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
        
        // Try to get session times from symbol info
        // Note: MQL5 doesn't have direct session times in SymbolInfoInteger
        // This is a simplified implementation - adjust based on your broker
        
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // Set default session (example: 00:00-23:59)
        dt.hour = 0;
        dt.min = 0;
        dt.sec = 0;
        startTime = StructToTime(dt);
        
        dt.hour = 23;
        dt.min = 59;
        dt.sec = 59;
        endTime = StructToTime(dt);
        
        return true;
    }
    
    // Check if new bar has formed (improved for multiple symbols/timeframes)
    static bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        string key = symbol + "|" + IntegerToString(timeframe);
        datetime currentBarTime = iTime(symbol, timeframe, 0);
        
        // Find existing key
        for(int i = 0; i < ArraySize(lastBarTimes); i += 2)
        {
            if(lastBarTimes[i] == key)
            {
                datetime lastTime = (datetime)StringToInteger(lastBarTimes[i + 1]);
                if(currentBarTime != lastTime)
                {
                    lastBarTimes[i + 1] = IntegerToString(currentBarTime);
                    return true;
                }
                return false;
            }
        }
        
        // New symbol/timeframe
        int newSize = ArraySize(lastBarTimes) + 2;
        ArrayResize(lastBarTimes, newSize);
        lastBarTimes[newSize - 2] = key;
        lastBarTimes[newSize - 1] = IntegerToString(currentBarTime);
        return true;
    }
    
    // Check if market is open for a symbol
    static bool IsMarketOpen(const string symbol = NULL)
    {
        string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
        
        // Check if symbol exists and is selected
        if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
            return false;
        
        // Check if trading is allowed
        long tradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
        if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || 
           tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
            return false;
        
        // Check market hours
        return IsTradingSession(sym);
    }
    
    // Check if it's the last trading day of the month
    static bool IsEndOfMonth(const string symbol = NULL)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // Get tomorrow's date
        MqlDateTime tomorrow = dt;
        tomorrow.day++;
        if(tomorrow.day > 31)
        {
            tomorrow.day = 1;
            tomorrow.mon++;
        }
        
        // If tomorrow is a new mon, check if it's a trading day
        if(tomorrow.mon != dt.mon)
        {
            // Check if tomorrow would be a trading day (not weekend)
            int tomorrowDayOfWeek = (dt.day_of_week + 1) % 7;
            if(tomorrowDayOfWeek != 0 && tomorrowDayOfWeek != 6) // Not weekend
                return true;
        }
        
        return false;
    }
    
    // Check if it's the first trading day of the month
    static bool IsStartOfMonth(const string symbol = NULL)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // Check if today is the 1st or first trading day after the 1st
        if(dt.day == 1)
        {
            // Check if today is a trading day (not weekend)
            if(dt.day_of_week != 0 && dt.day_of_week != 6)
                return true;
        }
        
        return false;
    }
    
    // Get time until next session
    static int MinutesUntilSession(const string symbol = NULL, bool nextDay = false)
    {
        string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
        
        MqlDateTime currentDt;
        TimeCurrent(currentDt);
        
        // Get session times
        datetime sessionStart, sessionEnd;
        if(!GetTradingSession(sym, sessionStart, sessionEnd))
            return -1;
        
        MqlDateTime startDt;
        TimeToStruct(sessionStart, startDt);
        
        // Calculate minutes until session start
        int currentMinutes = currentDt.hour * 60 + currentDt.min;
        int startMinutes = startDt.hour * 60 + startDt.min;
        
        if(nextDay || currentMinutes > startMinutes)
        {
            // Session already started today, calculate for tomorrow
            return (24 * 60 - currentMinutes) + startMinutes;
        }
        
        return startMinutes - currentMinutes;
    }
    
    // Check if current time is during high volatility periods (NY/London overlap)
    static bool IsHighVolatilityPeriod()
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // NY/London overlap: 13:00-17:00 UTC (8:00-12:00 EST, 1:00-5:00 PM London)
        int currentMinutes = dt.hour * 60 + dt.min;
        int nyStart = 13 * 60;  // 13:00 UTC
        int nyEnd = 17 * 60;    // 17:00 UTC
        
        return (currentMinutes >= nyStart && currentMinutes <= nyEnd);
    }
    
    // Check if time is within a specific range
    static bool IsTimeInRange(int startHour, int startMinute, int endHour, int endMinute)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        
        int currentMinutes = dt.hour * 60 + dt.min;
        int startMinutes = startHour * 60 + startMinute;
        int endMinutes = endHour * 60 + endMinute;
        
        return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
    }
    
    // Get number of trading days between two dates
    static int TradingDaysBetween(datetime startDate, datetime endDate)
    {
        int tradingDays = 0;
        MqlDateTime startDt, endDt, currentDt;
        
        TimeToStruct(startDate, startDt);
        TimeToStruct(endDate, endDt);
        
        // Normalize times to midnight
        startDt.hour = startDt.min = startDt.sec = 0;
        endDt.hour = endDt.min = endDt.sec = 0;
        
        datetime current = StructToTime(startDt);
        datetime end = StructToTime(endDt);
        
        while(current <= end)
        {
            TimeToStruct(current, currentDt);
            
            // Skip weekends
            if(currentDt.day_of_week != 0 && currentDt.day_of_week != 6)
                tradingDays++;
            
            // Move to next day
            current += 86400; // 24 hours in seconds
        }
        
        return tradingDays;
    }
    
    // Check if it's pre-market (before session start)
    static bool IsPreMarket(const string symbol = NULL)
    {
        return (MinutesUntilSession(symbol) > 0);
    }
    
    // Check if it's after hours (after session end)
    static bool IsAfterHours(const string symbol = NULL)
    {
        string sym = (symbol == NULL || symbol == "") ? _Symbol : symbol;
        
        MqlDateTime dt;
        TimeCurrent(dt);
        
        // Get session times
        datetime sessionStart, sessionEnd;
        if(!GetTradingSession(sym, sessionStart, sessionEnd))
            return false;
        
        MqlDateTime endDt;
        TimeToStruct(sessionEnd, endDt);
        
        int currentMinutes = dt.hour * 60 + dt.min;
        int endMinutes = endDt.hour * 60 + endDt.min;
        
        return (currentMinutes > endMinutes);
    }
    
    // Get the next trading day
    static datetime NextTradingDay(datetime fromDate = 0)
    {
        if(fromDate == 0) fromDate = TimeCurrent();
        
        MqlDateTime dt;
        TimeToStruct(fromDate, dt);
        
        // Move forward one day at a time until we find a trading day
        for(int i = 1; i <= 7; i++)
        {
            dt.day++;
            if(dt.day > 31)
            {
                dt.day = 1;
                dt.mon++;
                if(dt.mon > 12)
                {
                    dt.mon = 1;
                    dt.year++;
                }
            }
            
            // Adjust day of week
            dt.day_of_week = (dt.day_of_week + 1) % 7;
            
            // Check if it's a weekday
            if(dt.day_of_week != 0 && dt.day_of_week != 6)
            {
                // Set to market open time (adjust as needed)
                dt.hour = 9;
                dt.min = 30;
                dt.sec = 0;
                return StructToTime(dt);
            }
        }
        
        return 0; // Should never happen
    }
    
    // Get time of day as string
    static string TimeOfDayToString()
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        
        if(dt.hour < 12)
            return "Morning";
        else if(dt.hour < 17)
            return "Afternoon";
        else if(dt.hour < 21)
            return "Evening";
        else
            return "Night";
    }
    
    // Check if it's rollover time (typically 17:00 EST for forex)
    static bool IsRolloverTime()
    {
        // Rollover typically happens at 17:00 EST (21:00 UTC)
        return IsTimeInRange(20, 45, 21, 15); // Check 20:45-21:15 UTC
    }
    
    // Get current timestamp as string
    static string GetTimestamp()
    {
        return TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    }
    
    // Convert timeframe to minutes
    static int TimeframeToMinutes(ENUM_TIMEFRAMES tf)
    {
        switch(tf)
        {
            case PERIOD_M1: return 1;
            case PERIOD_M2: return 2;
            case PERIOD_M3: return 3;
            case PERIOD_M4: return 4;
            case PERIOD_M5: return 5;
            case PERIOD_M6: return 6;
            case PERIOD_M10: return 10;
            case PERIOD_M12: return 12;
            case PERIOD_M15: return 15;
            case PERIOD_M20: return 20;
            case PERIOD_M30: return 30;
            case PERIOD_H1: return 60;
            case PERIOD_H2: return 120;
            case PERIOD_H3: return 180;
            case PERIOD_H4: return 240;
            case PERIOD_H6: return 360;
            case PERIOD_H8: return 480;
            case PERIOD_H12: return 720;
            case PERIOD_D1: return 1440;
            case PERIOD_W1: return 10080;
            case PERIOD_MN1: return 43200;
            default: return 0;
        }
    }
    
    // Get bar opening time
    static datetime GetBarOpenTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
    {
        return iTime(symbol, timeframe, shift);
    }
    
    // Get bar closing time
    static datetime GetBarCloseTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
    {
        datetime openTime = iTime(symbol, timeframe, shift);
        int minutes = TimeframeToMinutes(timeframe);
        return openTime + (minutes * 60);
    }
};

string TimeUtils::lastBarTimes[] = {};