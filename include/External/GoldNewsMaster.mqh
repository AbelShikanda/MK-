//+------------------------------------------------------------------+
//|                                              GoldNewsMaster.mqh   |
//|                     Gold-Specific News with Directional Support  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link "http://www.yoururl.com"
#property version "2.00"
#property strict

// REMOVE THIS LINE: #include <FundamentalsEverywhere.mqh>
// We're embedding FundamentalsEverywhere directly in this file

//+------------------------------------------------------------------+
//| FundamentalsEverywhere namespace (EMBEDDED)                      |
//+------------------------------------------------------------------+
namespace FundamentalsEverywhere
{
    //+------------------------------------------------------------------+
    //| Fundamental Data Structure                                       |
    //+------------------------------------------------------------------+
    struct FundamentalData
    {
        datetime news_time;
        string currency;
        string event;
        double previous_value;
        double actual_value;
        double forecast_value;
        int impact_level; // 0=low, 1=medium, 2=high, 3=very high

        FundamentalData() : news_time(0),
                            previous_value(0.0),
                            actual_value(0.0),
                            forecast_value(0.0),
                            impact_level(0) {}
    };

    //+------------------------------------------------------------------+
    //| News Configuration Structure                                    |
    //+------------------------------------------------------------------+
    struct NewsConfig
    {
        int pre_news_minutes;         // Minutes before news to avoid trading
        int post_news_minutes;        // Minutes after news to avoid trading
        double high_impact_threshold; // Threshold for high impact events
        bool enable_news_filtering;
        bool use_forecast_deviations;
        bool enable_logging;

        NewsConfig() : pre_news_minutes(15),
                       post_news_minutes(30),
                       high_impact_threshold(0.5), // 0.5% deviation threshold
                       enable_news_filtering(true),
                       use_forecast_deviations(true),
                       enable_logging(true)
        {
        }
    };

    //+------------------------------------------------------------------+
    //| News Analysis Results Structure                                 |
    //+------------------------------------------------------------------+
    struct NewsAnalysis
    {
        double news_impact_score;       // 0-100 (higher = more dangerous)
        double trade_suitability_score; // 0-100 (higher = better for trading)
        bool in_avoidance_zone;
        string recommendation;
        string next_event_name;
        datetime next_event_time;
        int next_event_impact;

        NewsAnalysis() : news_impact_score(0.0),
                         trade_suitability_score(0.0),
                         in_avoidance_zone(false),
                         recommendation("No News Data"),
                         next_event_name(""),
                         next_event_time(0),
                         next_event_impact(0) {}
    };

    // Global state variables
    NewsConfig g_config;
    FundamentalData g_next_news;
    FundamentalData g_last_news;
    bool g_has_news_data = false;

    //+------------------------------------------------------------------+
    //| Initialize with custom configuration                             |
    //+------------------------------------------------------------------+
    void Initialize(const NewsConfig &config)
    {
        g_config = config;
        g_has_news_data = false;

        if (g_config.enable_logging)
        {
            Print("FundamentalsEverywhere: Initialized with custom configuration");
        }
    }

    //+------------------------------------------------------------------+
    //| Initialize with default configuration                            |
    //+------------------------------------------------------------------+
    void Initialize()
    {
        NewsConfig default_config;
        Initialize(default_config);
    }

    //+------------------------------------------------------------------+
    //| Update news data                                                 |
    //+------------------------------------------------------------------+
    void UpdateNewsData(string currency, datetime news_time, string event_name,
                        double previous, double forecast, double actual = 0.0,
                        int impact = 0)
    {
        g_next_news.currency = currency;
        g_next_news.news_time = news_time;
        g_next_news.event = event_name;
        g_next_news.previous_value = previous;
        g_next_news.forecast_value = forecast;
        g_next_news.actual_value = actual;
        g_next_news.impact_level = impact;

        g_has_news_data = true;

        if (g_config.enable_logging)
        {
            Print(StringFormat("FundamentalsEverywhere: News Updated: %s %s at %s (Impact: %d)",
                               currency, event_name, TimeToString(news_time), impact));
        }
    }

    //+------------------------------------------------------------------+
    //| Calculate news impact score (0-100, higher = more dangerous)    |
    //+------------------------------------------------------------------+
    double CalculateNewsImpactScore()
    {
        if (!g_has_news_data)
            return 0.0; // No news = no impact

        datetime current_time = TimeCurrent();
        double time_factor = 1.0;

        // Calculate time proximity factor
        double minutes_to_news = (g_next_news.news_time - current_time) / 60.0;

        if (minutes_to_news > 0)
        {
            // Approaching news
            if (minutes_to_news <= g_config.pre_news_minutes)
                time_factor = 1.0 - (minutes_to_news / g_config.pre_news_minutes);
            else if (minutes_to_news <= g_config.pre_news_minutes * 2)
                time_factor = 0.5;
            else
                time_factor = 0.0;
        }
        else
        {
            // News passed
            double minutes_since_news = MathAbs(minutes_to_news);
            if (minutes_since_news <= g_config.post_news_minutes)
                time_factor = 1.0 - (minutes_since_news / g_config.post_news_minutes);
            else
                time_factor = 0.0;
        }

        // Calculate impact based on event importance
        double impact_factor = 0.0;
        switch (g_next_news.impact_level)
        {
        case 0:
            impact_factor = 0.1;
            break; // Low impact
        case 1:
            impact_factor = 0.3;
            break; // Medium impact
        case 2:
            impact_factor = 0.7;
            break; // High impact
        case 3:
            impact_factor = 1.0;
            break; // Very high impact
        }

        // Calculate forecast deviation if actual is available
        double deviation_factor = 0.0;
        if (g_config.use_forecast_deviations && g_next_news.actual_value != 0.0)
        {
            double deviation = MathAbs(g_next_news.actual_value - g_next_news.forecast_value);
            double percent_deviation = (deviation / MathAbs(g_next_news.forecast_value)) * 100.0;

            if (percent_deviation > g_config.high_impact_threshold)
                deviation_factor = 1.0;
            else
                deviation_factor = percent_deviation / g_config.high_impact_threshold;
        }

        // Combine factors
        double news_score = 0.0;

        if (g_next_news.actual_value != 0.0) // News already released
        {
            // Post-news: 70% deviation, 30% impact level
            news_score = (deviation_factor * 70.0) + (impact_factor * 30.0);
        }
        else // News pending
        {
            // Pre-news: 40% time factor, 40% impact level, 20% historical volatility
            news_score = (time_factor * 40.0) + (impact_factor * 40.0) + (0.2 * 20.0);
        }

        // Apply time factor to final score
        news_score *= time_factor;

        if (g_config.enable_logging)
        {
            Print(StringFormat("FundamentalsEverywhere: News Score: %.1f (TimeFactor: %.2f, Impact: %.2f, Deviation: %.2f)",
                               news_score, time_factor, impact_factor, deviation_factor));
        }

        return MathMin(100.0, news_score);
    }

    //+------------------------------------------------------------------+
    //| Check if currently in news avoidance zone                        |
    //+------------------------------------------------------------------+
    bool IsInNewsAvoidanceZone()
    {
        if (!g_config.enable_news_filtering || !g_has_news_data)
            return false;

        datetime current_time = TimeCurrent();

        // Check if we're within pre-news window
        if (current_time >= (g_next_news.news_time - g_config.pre_news_minutes * 60) &&
            current_time <= g_next_news.news_time)
        {
            if (g_config.enable_logging)
            {
                Print(StringFormat("FundamentalsEverywhere: PRE-NEWS AVOIDANCE: %d minutes before %s",
                                   g_config.pre_news_minutes, g_next_news.event));
            }
            return true;
        }

        // Check if we're within post-news window
        if (current_time >= g_next_news.news_time &&
            current_time <= (g_next_news.news_time + g_config.post_news_minutes * 60))
        {
            if (g_config.enable_logging)
            {
                Print(StringFormat("FundamentalsEverywhere: POST-NEWS AVOIDANCE: %d minutes after %s",
                                   g_config.post_news_minutes, g_next_news.event));
            }
            return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Get trading recommendation based on news                         |
    //+------------------------------------------------------------------+
    string GetNewsRecommendation()
    {
        double score = CalculateNewsImpactScore();

        if (score >= 70.0)
            return "AVOID - High News Impact";
        else if (score >= 40.0)
            return "CAUTION - Moderate News Impact";
        else if (score >= 20.0)
            return "MONITOR - Low News Impact";
        else
            return "CLEAR - No Significant News";
    }

    //+------------------------------------------------------------------+
    //| Calculate overall trade suitability score (0-100, higher=better) |
    //+------------------------------------------------------------------+
    double CalculateTradeSuitabilityScore(double technical_score)
    {
        if (!g_config.enable_news_filtering)
            return technical_score; // No news filtering, use technical score directly

        double news_score = CalculateNewsImpactScore();

        // Convert news impact to suitability (inverse relationship)
        double news_suitability = MathMax(0.0, 100.0 - news_score);

        // Combine: 70% technical, 30% news suitability
        double final_score = (technical_score * 0.7) + (news_suitability * 0.3);

        if (g_config.enable_logging)
        {
            Print(StringFormat("FundamentalsEverywhere: Trade Suitability: %.1f (Technical: %.1f, News: %.1f)",
                               final_score, technical_score, news_suitability));
        }

        return final_score;
    }

    //+------------------------------------------------------------------+
    //| Display news information on chart                                |
    //+------------------------------------------------------------------+
    void DisplayNewsInfo()
    {
        if (!g_has_news_data || !g_config.enable_logging)
            return;

        string obj_name = "NewsInfo_" + IntegerToString(ChartID());

        // Create or update text object
        if (ObjectFind(0, obj_name) < 0)
        {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, 10);
            ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, 60);
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrYellow);
            ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
        }

        string display_text = "Next News: " + g_next_news.event + "\n" +
                              "Time: " + TimeToString(g_next_news.news_time) + "\n" +
                              "Impact: " + IntegerToString(g_next_news.impact_level) + "\n" +
                              "Status: " + GetNewsRecommendation();

        ObjectSetString(0, obj_name, OBJPROP_TEXT, display_text);
    }

    //+------------------------------------------------------------------+
    //| Perform comprehensive news analysis                              |
    //+------------------------------------------------------------------+
    NewsAnalysis AnalyzeNews(double technical_score = 50.0)
    {
        NewsAnalysis analysis;

        if (!g_has_news_data)
        {
            analysis.recommendation = "No News Data Available";
            analysis.trade_suitability_score = technical_score;
            return analysis;
        }

        analysis.news_impact_score = CalculateNewsImpactScore();
        analysis.in_avoidance_zone = IsInNewsAvoidanceZone();
        analysis.recommendation = GetNewsRecommendation();
        analysis.next_event_name = g_next_news.event;
        analysis.next_event_time = g_next_news.news_time;
        analysis.next_event_impact = g_next_news.impact_level;

        // Calculate trade suitability
        analysis.trade_suitability_score = CalculateTradeSuitabilityScore(technical_score);

        // Display on chart
        if (g_config.enable_logging)
            DisplayNewsInfo();

        return analysis;
    }

    //+------------------------------------------------------------------+
    //| Get detailed analysis string                                    |
    //+------------------------------------------------------------------+
    string GetAnalysisString(double technical_score = 50.0)
    {
        NewsAnalysis analysis = AnalyzeNews(technical_score);

        string result = "=== FUNDAMENTALS ANALYSIS ===\n\n";
        result += StringFormat("Next Event: %s\n", analysis.next_event_name);
        result += StringFormat("Event Time: %s\n", TimeToString(analysis.next_event_time));
        result += StringFormat("Impact Level: %d\n", analysis.next_event_impact);
        result += StringFormat("News Impact Score: %.1f/100\n", analysis.news_impact_score);
        result += StringFormat("In Avoidance Zone: %s\n", analysis.in_avoidance_zone ? "YES" : "NO");
        result += StringFormat("Recommendation: %s\n", analysis.recommendation);
        result += StringFormat("Trade Suitability Score: %.1f/100\n", analysis.trade_suitability_score);

        // Add timing information
        if (g_has_news_data)
        {
            datetime current_time = TimeCurrent();
            if (current_time < g_next_news.news_time)
            {
                double minutes_to_news = (g_next_news.news_time - current_time) / 60.0;
                result += StringFormat("Time to News: %.1f minutes\n", minutes_to_news);
            }
            else
            {
                double minutes_since_news = (current_time - g_next_news.news_time) / 60.0;
                result += StringFormat("Time Since News: %.1f minutes\n", minutes_since_news);
            }
        }

        return result;
    }

    //+------------------------------------------------------------------+
    //| Update configuration                                             |
    //+------------------------------------------------------------------+
    void UpdateConfig(const NewsConfig &config)
    {
        g_config = config;

        if (g_config.enable_logging)
        {
            Print("FundamentalsEverywhere: Configuration updated");
        }
    }

    //+------------------------------------------------------------------+
    //| Get current configuration                                        |
    //+------------------------------------------------------------------+
    NewsConfig GetConfig()
    {
        return g_config;
    }

    //+------------------------------------------------------------------+
    //| Check if news data is available                                  |
    //+------------------------------------------------------------------+
    bool HasNewsData()
    {
        return g_has_news_data;
    }

    //+------------------------------------------------------------------+
    //| Get next news event                                              |
    //+------------------------------------------------------------------+
    FundamentalData GetNextNews()
    {
        return g_next_news;
    }

    //+------------------------------------------------------------------+
    //| Get last news event                                              |
    //+------------------------------------------------------------------+
    FundamentalData GetLastNews()
    {
        return g_last_news;
    }

    //+------------------------------------------------------------------+
    //| Helper Functions                                                 |
    //+------------------------------------------------------------------+

    // Quick news impact check
    double QuickNewsImpactCheck()
    {
        NewsConfig temp_config;
        temp_config.enable_logging = false;

        // Save current state
        NewsConfig original_config = g_config;
        FundamentalData original_news = g_next_news;
        bool original_has_data = g_has_news_data;

        // Temporarily use default config
        g_config = temp_config;
        double score = CalculateNewsImpactScore();

        // Restore original state
        g_config = original_config;
        g_next_news = original_news;
        g_has_news_data = original_has_data;

        return score;
    }

    // Quick trading suitability check
    double QuickTradingSuitability(double technical_score)
    {
        NewsConfig temp_config;
        temp_config.enable_logging = false;

        // Save current state
        NewsConfig original_config = g_config;

        // Temporarily use default config
        g_config = temp_config;
        double score = CalculateTradeSuitabilityScore(technical_score);

        // Restore original state
        g_config = original_config;

        return score;
    }

    // Get impact level name
    string GetImpactLevelName(int impact_level)
    {
        switch (impact_level)
        {
        case 0:
            return "Low";
        case 1:
            return "Medium";
        case 2:
            return "High";
        case 3:
            return "Very High";
        default:
            return "Unknown";
        }
    }

    // Get recommendation from score
    string GetRecommendationFromScore(double score)
    {
        if (score >= 70.0)
            return "AVOID - High News Impact";
        else if (score >= 40.0)
            return "CAUTION - Moderate News Impact";
        else if (score >= 20.0)
            return "MONITOR - Low News Impact";
        else
            return "CLEAR - No Significant News";
    }

    //+------------------------------------------------------------------+
    //| Clear all news data                                              |
    //+------------------------------------------------------------------+
    void ClearNewsData()
    {
        g_next_news = FundamentalData();
        g_last_news = FundamentalData();
        g_has_news_data = false;

        if (g_config.enable_logging)
        {
            Print("FundamentalsEverywhere: News data cleared");
        }
    }
}

//+------------------------------------------------------------------+
//| NOW THE GOLD NEWS MASTER NAMESPACE                               |
//+------------------------------------------------------------------+
namespace GoldNewsMaster
{
    //+------------------------------------------------------------------+
    //| Directional Analysis                                             |
    //+------------------------------------------------------------------+
    enum NEWS_DIRECTION
    {
        DIRECTION_NONE = 0,     // No clear direction
        DIRECTION_BULLISH = 1,  // News supports higher prices
        DIRECTION_BEARISH = -1, // News supports lower prices
        DIRECTION_NEUTRAL = 2   // Mixed or no impact
    };

    //+------------------------------------------------------------------+
    //| Enhanced News Structure with Direction                          |
    //+------------------------------------------------------------------+
    struct EnhancedNewsData
    {
        FundamentalsEverywhere::FundamentalData basic_data;
        NEWS_DIRECTION direction;    // Bullish/Bearish/Neutral
        double strength;             // 0-100, how strong is the signal
        string reasoning;            // Why this direction
        double price_target;         // Expected price move
        int confidence;              // 0-100, confidence in analysis
        bool supports_trading;       // True if news supports trading
        string trade_recommendation; // "BUY", "SELL", "AVOID", "SCALP"

        EnhancedNewsData() : direction(DIRECTION_NONE),
                             strength(0.0),
                             price_target(0.0),
                             confidence(0),
                             supports_trading(false) {}
    };

    //+------------------------------------------------------------------+
    //| Gold-Specific Event Database                                    |
    //+------------------------------------------------------------------+
    struct GoldEventPattern
    {
        string event_name;
        string pattern;           // Regex or keyword pattern
        NEWS_DIRECTION direction; // Typical direction
        double base_strength;     // Base strength (0-100)
        string reasoning;         // Economic reasoning
        bool supports_trading;    // Can we trade this?
    };

    // Gold's unique reaction patterns
    GoldEventPattern GOLD_EVENT_PATTERNS[] = {
        // HIGH IMPACT BULLISH FOR GOLD
        {"FED Rate Cut", "Rate Cut|Decrease|Lower", DIRECTION_BULLISH, 85,
         "Lower rates reduce USD yield, gold becomes more attractive", true},
        {"High Inflation", "CPI|Inflation|PPI", DIRECTION_BULLISH, 75,
         "Gold is inflation hedge, high CPI = gold bullish", true},
        {"Geopolitical Risk", "War|Conflict|Tension|Sanction", DIRECTION_BULLISH, 90,
         "Gold is safe haven during uncertainty", true},
        {"Weak USD Data", "NFP Miss|Unemployment Rise|Retail Sales Fall", DIRECTION_BULLISH, 70,
         "Weak USD = stronger gold", true},
        {"Dovish Fed", "Dovish|Accommodative|Patient", DIRECTION_BULLISH, 65,
         "Dovish policy = weaker USD = gold support", true},

        // HIGH IMPACT BEARISH FOR GOLD
        {"FED Rate Hike", "Rate Hike|Increase|Higher", DIRECTION_BEARISH, 85,
         "Higher rates strengthen USD, gold becomes less attractive", true},
        {"Strong USD Data", "NFP Beat|Unemployment Drop|Retail Sales Rise", DIRECTION_BEARISH, 70,
         "Strong USD = weaker gold", true},
        {"Risk-On Sentiment", "Risk On|Stock Rally|Optimism", DIRECTION_BEARISH, 60,
         "Gold loses safe-haven appeal", false}, // Usually avoid trading
        {"Hawkish Fed", "Hawkish|Tighten|Aggressive", DIRECTION_BEARISH, 75,
         "Hawkish policy = stronger USD = gold pressure", true},
        {"Deflation Risk", "Deflation|Disinflation", DIRECTION_BEARISH, 80,
         "Gold loses inflation hedge appeal", true},

        // NEUTRAL/MIXED
        {"Fed Meeting", "FOMC|Meeting|Decision", DIRECTION_NEUTRAL, 50,
         "Depends on statement and dot plot", false}, // Wait for clarity
        {"Mixed Data", "Mixed|Unchanged|Stable", DIRECTION_NEUTRAL, 30,
         "No clear direction", false}};

    //+------------------------------------------------------------------+
    //| Hybrid Fetcher Implementation                                   |
    //+------------------------------------------------------------------+
    EnhancedNewsData g_current_gold_news;
    datetime g_last_update = 0;
    bool g_has_gold_news = false;

    //+------------------------------------------------------------------+
    //| Missing Helper Function Stubs                                   |
    //+------------------------------------------------------------------+

    // These functions need to be implemented based on your needs
    bool CheckFFCalForGoldNews()
    {
        // Implement FFCal indicator checking
        // Return true if found relevant news
        return false;
    }

    bool TryForexFactoryWebParsing()
    {
        // Implement web parsing for Forex Factory
        // Return true if successful
        return false;
    }

    string GetObjectColor(string obj_name)
    {
        // Get object color for impact analysis
        return "Red"; // Default to high impact
    }

    void ParseFFCalEvent(string obj_name, string event_text, string impact_color)
    {
        // Parse FFCal event data into g_current_gold_news
        g_current_gold_news.basic_data.currency = "USD";
        g_current_gold_news.basic_data.event = event_text;
        g_current_gold_news.basic_data.news_time = TimeCurrent() + 3600; // 1 hour from now
        g_current_gold_news.basic_data.impact_level = (impact_color == "Red") ? 3 : (impact_color == "Orange") ? 2
                                                                                                               : 1;
    }

    bool ParseFCSAPIForGold(string json_response)
    {
        // Parse FCS API JSON response
        // Implement JSON parsing here
        return false;
    }

    datetime CalculateNextCPITimestamp()
    {
        // Calculate next CPI release (usually monthly, around 13th)
        MqlDateTime now;
        TimeToStruct(TimeCurrent(), now);

        // Find next month, around 13th
        now.day = 13;
        now.hour = 13; // 8:30 AM EST
        now.min = 30;

        datetime next_cpi = StructToTime(now);
        if (next_cpi <= TimeCurrent())
        {
            // Move to next month
            now.mon++;
            if (now.mon > 12)
            {
                now.mon = 1;
                now.year++;
            }
            next_cpi = StructToTime(now);
        }

        return next_cpi;
    }

    datetime CalculateNextFedMeeting()
    {
        // Fed meetings: Jan, Mar, Apr, Jun, Jul, Sep, Nov, Dec
        // Usually Tue-Wed
        MqlDateTime now;
        TimeToStruct(TimeCurrent(), now);

        // Find next month with Fed meeting
        for (int month_offset = 1; month_offset <= 3; month_offset++)
        {
            MqlDateTime target = now;
            target.mon += month_offset;
            if (target.mon > 12)
            {
                target.mon -= 12;
                target.year++;
            }

            // Fed months: 1, 3, 4, 6, 7, 9, 11, 12
            int fed_months[] = {1, 3, 4, 6, 7, 9, 11, 12};
            for (int i = 0; i < 8; i++)
            {
                if (target.mon == fed_months[i])
                {
                    // Usually 3rd Tuesday
                    target.day = 15;  // Start around middle of month
                    target.hour = 14; // 2 PM EST
                    target.min = 0;

                    datetime meeting_time = StructToTime(target);
                    if (meeting_time > TimeCurrent())
                    {
                        return meeting_time;
                    }
                }
            }
        }

        return TimeCurrent() + 86400 * 30; // Default: 30 days from now
    }

    //+------------------------------------------------------------------+
    //| STEP 1: PRIMARY - Forex Factory with Gold Filter                |
    //+------------------------------------------------------------------+
    bool FetchPrimaryGoldNews()
    {
        Print("=== STEP 1: Fetching Forex Factory (Gold-Filtered) ===");

        // Method A: Check if FFCal indicator exists (most reliable)
        if (CheckFFCalForGoldNews())
        {
            Print("✓ Forex Factory FFCal data found");
            return true;
        }

        // Method B: Try web parsing
        if (TryForexFactoryWebParsing())
        {
            Print("✓ Forex Factory web data parsed");
            return true;
        }

        Print("✗ Forex Factory primary source failed");
        return false;
    }

    //+------------------------------------------------------------------+
    //| STEP 2: BACKUP - FCS API with Gold Analysis                     |
    //+------------------------------------------------------------------+
    bool FetchBackupGoldNews()
    {
        Print("=== STEP 2: Trying FCS API Backup ===");

        string api_key = "YOUR_FCS_API_KEY"; // Get from fcsapi.com

        // Fetch USD events only (gold only cares about USD)
        string url = StringFormat(
            "https://fcsapi.com/api-v3/forex-economic-calendar?symbol=USD&access_key=%s",
            api_key);

        char data[];
        char result_data[];
        string headers;
        int result = WebRequest("GET", url, "", 5000, data, result_data, headers);

        if (result == 200)
        {
            string json_response = CharArrayToString(result_data);

            // Parse and filter for gold-relevant events
            if (ParseFCSAPIForGold(json_response))
            {
                Print("✓ FCS API backup successful");
                return true;
            }
        }

        Print("✗ FCS API backup failed");
        return false;
    }

    //+------------------------------------------------------------------+
    //| STEP 3: FALLBACK - Pre-Configured Gold Events                   |
    //+------------------------------------------------------------------+
    bool FetchFallbackGoldNews()
    {
        Print("=== STEP 3: Loading Fallback Gold Events ===");

        // Get next known gold-critical event
        datetime next_nfp = CalculateNextNFPTimestamp();
        datetime next_cpi = CalculateNextCPITimestamp();
        datetime next_fed = CalculateNextFedMeeting();

        // Use the nearest event
        datetime nearest_event = 0;
        string event_name = "";

        if (next_nfp > TimeCurrent() && (nearest_event == 0 || next_nfp < nearest_event))
        {
            nearest_event = next_nfp;
            event_name = "US Non-Farm Payrolls";
        }

        if (next_cpi > TimeCurrent() && (nearest_event == 0 || next_cpi < nearest_event))
        {
            nearest_event = next_cpi;
            event_name = "US CPI Inflation";
        }

        if (next_fed > TimeCurrent() && (nearest_event == 0 || next_fed < nearest_event))
        {
            nearest_event = next_fed;
            event_name = "FED Interest Rate Decision";
        }

        if (nearest_event > 0)
        {
            // Create fallback event
            g_current_gold_news.basic_data.currency = "USD";
            g_current_gold_news.basic_data.event = event_name;
            g_current_gold_news.basic_data.news_time = nearest_event;
            g_current_gold_news.basic_data.impact_level = 3; // High impact

            // Analyze direction
            AnalyzeNewsDirection(event_name, 0, 0, 0); // No values available

            Print("✓ Fallback event loaded: ", event_name, " at ", TimeToString(nearest_event));
            return true;
        }

        Print("✗ No fallback events found");
        return false;
    }

    //+------------------------------------------------------------------+
    //| MAIN HYBRID FETCHER                                              |
    //+------------------------------------------------------------------+
    bool FetchGoldNewsWithHybrid()
    {
        // Only update every 30 minutes to avoid rate limits
        if (TimeCurrent() - g_last_update < 1800) // 30 minutes
        {
            return g_has_gold_news;
        }

        Print("\n==================================================");
        Print("GOLD NEWS HYBRID FETCHER - " + TimeToString(TimeCurrent()));
        Print("==================================================");

        bool success = false;

        // STEP 1: PRIMARY (Forex Factory)
        success = FetchPrimaryGoldNews();

        // STEP 2: BACKUP (FCS API)
        if (!success)
        {
            success = FetchBackupGoldNews();
        }

        // STEP 3: FALLBACK (Pre-configured)
        if (!success)
        {
            success = FetchFallbackGoldNews();
        }

        // STEP 4: Update FundamentalsEverywhere
        if (success)
        {
            UpdateFundamentalsEverywhere();
            g_last_update = TimeCurrent();
            g_has_gold_news = true;

            // Display analysis
            // DisplayGoldNewsAnalysis();
        }
        else
        {
            // No news available - market is clear
            g_current_gold_news.trade_recommendation = "CLEAR - No Gold-Relevant News";
            g_current_gold_news.supports_trading = true;
            g_current_gold_news.confidence = 90;
        }

        return success;
    }

    //+------------------------------------------------------------------+
    //| ANALYZE NEWS DIRECTION (CRITICAL NEW FEATURE)                   |
    //+------------------------------------------------------------------+
    void AnalyzeNewsDirection(string event_name, double previous, double forecast, double actual)
    {
        // Default to neutral
        g_current_gold_news.direction = DIRECTION_NEUTRAL;
        g_current_gold_news.strength = 0;
        g_current_gold_news.supports_trading = false;
        g_current_gold_news.reasoning = "";

        // Match against known patterns
        for (int i = 0; i < ArraySize(GOLD_EVENT_PATTERNS); i++)
        {
            if (StringFind(event_name, GOLD_EVENT_PATTERNS[i].pattern) >= 0 ||
                StringFind(event_name, GOLD_EVENT_PATTERNS[i].event_name) >= 0)
            {
                g_current_gold_news.direction = GOLD_EVENT_PATTERNS[i].direction;
                g_current_gold_news.strength = GOLD_EVENT_PATTERNS[i].base_strength;
                g_current_gold_news.reasoning = GOLD_EVENT_PATTERNS[i].reasoning;
                g_current_gold_news.supports_trading = GOLD_EVENT_PATTERNS[i].supports_trading;
                break;
            }
        }

        // Enhance with actual vs forecast analysis
        if (actual != 0 && forecast != 0)
        {
            AnalyzeDeviationDirection(previous, forecast, actual);
        }

        // Generate trade recommendation
        GenerateTradeRecommendation();
    }

    //+------------------------------------------------------------------+
    //| Analyze Actual vs Forecast for Direction                        |
    //+------------------------------------------------------------------+
    void AnalyzeDeviationDirection(double previous, double forecast, double actual)
    {
        // For inflation data (CPI, PPI)
        if (StringFind(g_current_gold_news.basic_data.event, "CPI") >= 0 ||
            StringFind(g_current_gold_news.basic_data.event, "Inflation") >= 0 ||
            StringFind(g_current_gold_news.basic_data.event, "PPI") >= 0)
        {
            // HIGHER inflation = BULLISH for gold
            if (actual > forecast)
            {
                g_current_gold_news.direction = DIRECTION_BULLISH;
                g_current_gold_news.strength = MathMin(100, g_current_gold_news.strength + 20);
                g_current_gold_news.reasoning += " (Actual " + DoubleToString(actual, 1) +
                                                 " > Forecast " + DoubleToString(forecast, 1) +
                                                 " = Inflation Surprise = Gold Bullish)";
            }
            else if (actual < forecast)
            {
                g_current_gold_news.direction = DIRECTION_BEARISH;
                g_current_gold_news.strength = MathMin(100, g_current_gold_news.strength + 15);
                g_current_gold_news.reasoning += " (Lower inflation = Gold Bearish)";
            }
        }

        // For employment data (NFP, Unemployment)
        else if (StringFind(g_current_gold_news.basic_data.event, "NFP") >= 0 ||
                 StringFind(g_current_gold_news.basic_data.event, "Employment") >= 0 ||
                 StringFind(g_current_gold_news.basic_data.event, "Unemployment") >= 0)
        {
            // STRONGER jobs data = BEARISH for gold (strong USD)
            if (actual > forecast)
            {
                g_current_gold_news.direction = DIRECTION_BEARISH;
                g_current_gold_news.strength = MathMin(100, g_current_gold_news.strength + 25);
                g_current_gold_news.reasoning += " (Strong jobs data = USD Strength = Gold Bearish)";
            }
            else if (actual < forecast)
            {
                g_current_gold_news.direction = DIRECTION_BULLISH;
                g_current_gold_news.strength = MathMin(100, g_current_gold_news.strength + 20);
                g_current_gold_news.reasoning += " (Weak jobs data = USD Weakness = Gold Bullish)";
            }
        }

        // For rate decisions
        else if (StringFind(g_current_gold_news.basic_data.event, "Rate") >= 0 ||
                 StringFind(g_current_gold_news.basic_data.event, "FOMC") >= 0)
        {
            // Compare actual rate to forecast
            double deviation = actual - forecast;
            if (MathAbs(deviation) > 0.05) // Significant deviation
            {
                if (deviation < 0) // Rate cut or more dovish
                {
                    g_current_gold_news.direction = DIRECTION_BULLISH;
                    g_current_gold_news.strength = 90;
                    g_current_gold_news.reasoning += " (Dovish surprise = Gold Bullish)";
                }
                else // Rate hike or more hawkish
                {
                    g_current_gold_news.direction = DIRECTION_BEARISH;
                    g_current_gold_news.strength = 90;
                    g_current_gold_news.reasoning += " (Hawkish surprise = Gold Bearish)";
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| GENERATE TRADE RECOMMENDATION                                   |
    //+------------------------------------------------------------------+
    void GenerateTradeRecommendation()
    {
        // Check if we're in avoidance zone first
        if (FundamentalsEverywhere::IsInNewsAvoidanceZone())
        {
            g_current_gold_news.trade_recommendation = "AVOID - Too Close to News";
            g_current_gold_news.supports_trading = false;
            return;
        }

        // Based on direction and strength
        if (g_current_gold_news.supports_trading)
        {
            if (g_current_gold_news.direction == DIRECTION_BULLISH && g_current_gold_news.strength > 60)
            {
                g_current_gold_news.trade_recommendation = "STRONG BUY - News Supports Gold Rise";
                g_current_gold_news.confidence = MathMin(90, (int)g_current_gold_news.strength);
            }
            else if (g_current_gold_news.direction == DIRECTION_BULLISH && g_current_gold_news.strength > 40)
            {
                g_current_gold_news.trade_recommendation = "MODERATE BUY - News Slightly Bullish";
                g_current_gold_news.confidence = (int)g_current_gold_news.strength;
            }
            else if (g_current_gold_news.direction == DIRECTION_BEARISH && g_current_gold_news.strength > 60)
            {
                g_current_gold_news.trade_recommendation = "STRONG SELL - News Supports Gold Drop";
                g_current_gold_news.confidence = MathMin(90, (int)g_current_gold_news.strength);
            }
            else if (g_current_gold_news.direction == DIRECTION_BEARISH && g_current_gold_news.strength > 40)
            {
                g_current_gold_news.trade_recommendation = "MODERATE SELL - News Slightly Bearish";
                g_current_gold_news.confidence = (int)g_current_gold_news.strength;
            }
            else if (g_current_gold_news.direction == DIRECTION_NEUTRAL)
            {
                g_current_gold_news.trade_recommendation = "NEUTRAL - News Has Mixed Signals";
                g_current_gold_news.confidence = 50;
            }
            else
            {
                g_current_gold_news.trade_recommendation = "NO CLEAR DIRECTION - Wait for Confirmation";
                g_current_gold_news.confidence = 30;
            }
        }
        else
        {
            g_current_gold_news.trade_recommendation = "DO NOT TRADE - News Too Volatile/Unclear";
            g_current_gold_news.confidence = 0;
        }

        // Calculate price target based on impact level
        CalculatePriceTarget();
    }

    //+------------------------------------------------------------------+
    //| Calculate Expected Price Move                                   |
    //+------------------------------------------------------------------+
    void CalculatePriceTarget()
    {
        // Based on impact level and direction
        double base_move = 0;

        switch (g_current_gold_news.basic_data.impact_level)
        {
        case 3:
            base_move = 15.0;
            break; // High impact: ~$15
        case 2:
            base_move = 8.0;
            break; // Medium impact: ~$8
        case 1:
            base_move = 3.0;
            break; // Low impact: ~$3
        default:
            base_move = 1.0;
            break;
        }

        // Adjust by strength
        base_move *= (g_current_gold_news.strength / 100.0);

        // Apply direction
        if (g_current_gold_news.direction == DIRECTION_BULLISH)
            g_current_gold_news.price_target = base_move;
        else if (g_current_gold_news.direction == DIRECTION_BEARISH)
            g_current_gold_news.price_target = -base_move;
        else
            g_current_gold_news.price_target = 0;
    }

    //+------------------------------------------------------------------+
    //| Update FundamentalsEverywhere                                   |
    //+------------------------------------------------------------------+
    void UpdateFundamentalsEverywhere()
    {
        FundamentalsEverywhere::UpdateNewsData(
            g_current_gold_news.basic_data.currency,
            g_current_gold_news.basic_data.news_time,
            g_current_gold_news.basic_data.event,
            g_current_gold_news.basic_data.previous_value,
            g_current_gold_news.basic_data.forecast_value,
            g_current_gold_news.basic_data.actual_value,
            g_current_gold_news.basic_data.impact_level);
    }

    //+------------------------------------------------------------------+
    //| Display Gold News Analysis on Chart                             |
    //+------------------------------------------------------------------+
    void DisplayGoldNewsAnalysis()
    {
        string obj_name = "GoldNewsAnalysis_" + IntegerToString(ChartID());

        if (ObjectFind(0, obj_name) < 0)
        {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, 10);
            ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, 100);
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrGold);
            ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
        }

        string direction_text = "";
        color text_color = clrGray;

        switch (g_current_gold_news.direction)
        {
        case DIRECTION_BULLISH:
            direction_text = "▲ BULLISH";
            text_color = clrLime;
            break;
        case DIRECTION_BEARISH:
            direction_text = "▼ BEARISH";
            text_color = clrRed;
            break;
        case DIRECTION_NEUTRAL:
            direction_text = "◼ NEUTRAL";
            text_color = clrYellow;
            break;
        }

        string display_text =
            "GOLD NEWS ANALYSIS\n" +
            "--------------------------------------\n" +
            "Event: " + g_current_gold_news.basic_data.event + "\n" +
            "Time: " + TimeToString(g_current_gold_news.basic_data.news_time) + "\n" +
            "Direction: " + direction_text + "\n" +
            "Strength: " + DoubleToString(g_current_gold_news.strength, 0) + "/100\n" +
            "Recommend: " + g_current_gold_news.trade_recommendation + "\n" +
            "Confidence: " + IntegerToString(g_current_gold_news.confidence) + "%\n";

        if (g_current_gold_news.price_target != 0)
        {
            display_text += "Expected Move: " + DoubleToString(g_current_gold_news.price_target, 1) + "$\n";
        }

        ObjectSetString(0, obj_name, OBJPROP_TEXT, display_text);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, text_color);
    }

    //+------------------------------------------------------------------+
    //| Helper Functions                                                |
    //+------------------------------------------------------------------+
    bool IsGoldRelevantEvent(string event_name)
    {
        // Gold only cares about USD events with economic significance
        string gold_keywords[] = {
            "USD", "US ", "America", "Federal Reserve", "FOMC",
            "CPI", "Inflation", "NFP", "Employment", "Rate",
            "Retail Sales", "GDP", "Manufacturing", "Durable Goods"};

        for (int i = 0; i < ArraySize(gold_keywords); i++)
        {
            if (StringFind(event_name, gold_keywords[i]) >= 0)
                return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Calculate Next NFP Timestamp                                    |
    //+------------------------------------------------------------------+
    datetime CalculateNextNFPTimestamp()
    {
        // NFP: First Friday of each month, 8:30 AM EST
        MqlDateTime now_struct;
        TimeToStruct(TimeCurrent(), now_struct);

        // Find next first Friday
        for (int month_offset = 0; month_offset < 3; month_offset++)
        {
            MqlDateTime target = now_struct;
            target.mon += month_offset;
            if (target.mon > 12)
            {
                target.mon -= 12;
                target.year++;
            }

            // Set to 1st of the month
            target.day = 1;
            target.hour = 13; // 8:30 AM EST = 13:30 GMT
            target.min = 30;
            target.sec = 0;

            datetime first_of_month = StructToTime(target);

            // Get day of week for the 1st
            int day_of_week = target.day_of_week; // This is the day of week in the struct

            // Calculate days to Friday (Friday = 5 in MqlDateTime.day_of_week)
            int days_to_friday = 5 - day_of_week;
            if (days_to_friday < 0)
                days_to_friday += 7;

            // If it's already Friday (days_to_friday == 0), check if it's in the future
            if (days_to_friday == 0)
            {
                // If first is Friday, that's our NFP date
                datetime nfp_time = first_of_month;
                if (nfp_time > TimeCurrent())
                {
                    return nfp_time;
                }
            }
            else
            {
                datetime nfp_time = first_of_month + (days_to_friday * 86400);
                if (nfp_time > TimeCurrent())
                {
                    return nfp_time;
                }
            }
        }

        // Fallback: 30 days from now
        return TimeCurrent() + 30 * 86400;
    }

    //+------------------------------------------------------------------+
    //| Get Current Gold News Analysis                                  |
    //+------------------------------------------------------------------+
    EnhancedNewsData GetCurrentGoldNews()
    {
        // Ensure we have fresh data
        if (!g_has_gold_news || (TimeCurrent() - g_last_update > 1800))
        {
            FetchGoldNewsWithHybrid();
        }

        return g_current_gold_news;
    }

    //+------------------------------------------------------------------+
    //| Check if News Supports Trading                                  |
    //+------------------------------------------------------------------+
    bool ShouldTradeBasedOnNews(double &recommended_lots, string &direction)
    {
        EnhancedNewsData news = GetCurrentGoldNews();

        if (!news.supports_trading)
            return false;

        // Calculate lot size based on confidence
        recommended_lots = NormalizeDouble(news.confidence / 100.0, 2);

        if (news.direction == DIRECTION_BULLISH)
            direction = "BUY";
        else if (news.direction == DIRECTION_BEARISH)
            direction = "SELL";
        else
            direction = "NEUTRAL";

        return (news.direction != DIRECTION_NEUTRAL &&
                news.direction != DIRECTION_NONE &&
                news.confidence > 50);
    }
}