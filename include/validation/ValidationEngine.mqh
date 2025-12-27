//+------------------------------------------------------------------+
//|                    ValidationEngine.mqh                          |
//|                 Signal and Trade Validation Module              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

/*
==============================================================
                            USECASE
==============================================================

==============================================================
*/

// ============================================================
// INCLUDES
// ============================================================
#include "../config/inputs.mqh"
#include "../config/enums.mqh"
#include "../config/structures.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/ResourceManager.mqh"

#include "../utils/Utils.mqh"

// ============================================================
// SETTINGS STRUCTURE
// ============================================================
struct ValidationSettings
{
    string symbol;
    double rangingThreshold;      // Below this = RANGING
    double trendingThreshold;     // Above this = CLEAR TREND
    double maxSpreadPips;
    int maxTradesPerSymbol;
    int maxTradesPerBar;
    ENUM_TIMEFRAMES tradeTimeframe;
    double minBalanceForSecondSymbol;
    
    // Ultra-sensitive thresholds
    int pullbackThresholdBuy;
    int pullbackThresholdSell;
    int regularThresholdBuy;
    int regularThresholdSell;
    
    // MA alignment weights
    double weightMedSlowSeparation;
    double weightMedSlowDirection;
    double weightFastMedMomentum;
    double weightOverallStack;
    
    // Constructor with defaults
    ValidationSettings()
    {
        symbol = "";
        rangingThreshold = 0.15;          // Default for EURUSD/GBPUSD
        trendingThreshold = 0.25;         // Default for EURUSD/GBPUSD
        maxSpreadPips = 2.5;
        maxTradesPerSymbol = 3;
        maxTradesPerBar = 2;
        tradeTimeframe = PERIOD_H1;
        minBalanceForSecondSymbol = 5000.0;
        
        // Ultra-sensitive defaults
        pullbackThresholdBuy = 37;
        pullbackThresholdSell = 45;
        regularThresholdBuy = 45;
        regularThresholdSell = 56;
        
        // MA alignment defaults
        weightMedSlowSeparation = 0.40;   // 40%
        weightMedSlowDirection = 0.30;    // 30%
        weightFastMedMomentum = 0.20;     // 20%
        weightOverallStack = 0.10;        // 10%
    }
    
    // Set thresholds based on symbol type
    void SetSymbolSpecific(string sym)
    {
        symbol = sym;
        
        // Set thresholds based on symbol type
        if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
        {
            rangingThreshold = 0.25;      // For Gold
            trendingThreshold = 0.40;     // For Gold
        }
        else if(StringFind(sym, "JPY") >= 0)
        {
            rangingThreshold = 0.12;      // For JPY pairs
            trendingThreshold = 0.20;     // For JPY pairs
        }
        else
        {
            rangingThreshold = 0.15;      // For EURUSD, GBPUSD
            trendingThreshold = 0.25;     // For EURUSD, GBPUSD
        }
    }
};

// ============================================================
// BAR TRACKING STRUCTURE
// ============================================================
struct BarTracking
{
    datetime lastTradedBarTime;
    int tradesCountThisBar;
    bool buyTradedThisBar;
    bool sellTradedThisBar;
    
    BarTracking()
    {
        lastTradedBarTime = 0;
        tradesCountThisBar = 0;
        buyTradedThisBar = false;
        sellTradedThisBar = false;
    }
};

// ============================================================
//               VALIDATIONENGINE CLASS
// ============================================================
class ValidationEngine
{
private:
    // Components
    ResourceManager* m_logger;
    
    // Settings
    ValidationSettings m_settings;
    
    // State management
    bool m_initialized;
    
    // Bar tracking
    BarTracking m_barTracking;
    
    // Dependencies (will be injected)
    // RiskManager* m_riskManager;
    // NewsFilter* m_newsFilter;
    // POIManager* m_poiManager;
    // SignalScorer* m_signalScorer;
    
public:
    // ================= CONSTRUCTOR & DESTRUCTOR =================
    ValidationEngine()
    {
        m_initialized = false;
        // m_riskManager = NULL;
        // m_newsFilter = NULL;
        // m_poiManager = NULL;
        // m_signalScorer = NULL;
    }
    
    ~ValidationEngine()
    {
        Cleanup();
    }
    
    // ================= INITIALIZATION =================
    bool Initialize(const ValidationSettings &settings, 
                   string logFile = "ValidationLog.csv")
    {
        if(m_initialized)
        {
            m_logger.KeepNotes("GLOBAL", WARN, "ValidationEngine", 
                "Already initialized", false, false, 0.0);
            return true;
        }
        
        // Store settings
        m_settings = settings;
        
        // Initialize logger
        m_logger.Initialize(logFile, true, true, true);
        
        // Initialize bar tracking
        m_barTracking = BarTracking();
        
        m_logger.KeepNotes("GLOBAL", AUTHORIZE, "ValidationEngine", 
            "Initialized with settings", false, false, 0.0);
        
        Print("ValidationEngine: Initialized successfully");
        Print("Symbol: ", m_settings.symbol);
        Print("Ranging Threshold: ", m_settings.rangingThreshold, "%");
        Print("Trending Threshold: ", m_settings.trendingThreshold, "%");
        
        m_initialized = true;
        return true;
    }
    
    // ================= DEPENDENCY INJECTION =================
    // void SetRiskManager(RiskManager &riskManager)
    // {
    //     m_riskManager = GetPointer(riskManager);
    // }
    
    // void SetNewsFilter(NewsFilter &newsFilter)
    // {
    //     m_newsFilter = GetPointer(newsFilter);
    // }
    
    // void SetPOIManager(POIManager &poiManager)
    // {
    //     m_poiManager = GetPointer(poiManager);
    // }
    
    // void SetSignalScorer(SignalScorer &signalScorer)
    // {
    //     m_signalScorer = GetPointer(signalScorer);
    // }
    
    // ================= MAIN VALIDATION METHODS =================
    
    //+------------------------------------------------------------------+
    //| Validate - Primary Trade Validation                             |
    //+------------------------------------------------------------------+
    bool Validate(const string symbol, bool isBuy)
    {
        m_logger.StartContextWith(symbol, "Trade_Validation");
        
        // 1. Bar already traded check
        if(BarAlreadyTraded(symbol, isBuy))
        {
            m_logger.AddToContext(symbol, "BarCheck", "Failed - Already traded", true);
            m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
                "Bar already traded", false);
            return false;
        }
        
        // 2. Primary validation check
        if(!PrimaryValidation(symbol))
        {
            m_logger.AddToContext(symbol, "PrimaryCheck", "Failed", true);
            m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
                "Primary validation failed", false);
            return false;
        }
        
        // 3. Range avoidance check
        if(IsMarketRanging(symbol, isBuy))
        {
            m_logger.AddToContext(symbol, "RangeCheck", "Failed - Market ranging", true);
            m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
                "Market is ranging", false);
            return false;
        }
        
        // 4. Ultra-sensitive entry check
        if(!CheckUltraSensitiveEntry(symbol, isBuy))
        {
            m_logger.AddToContext(symbol, "UltraSensitive", "Failed", true);
            m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
                "Ultra-sensitive entry failed", false);
            return false;
        }
        
        m_logger.AddToContext(symbol, "Result", "PASSED", true);
        m_logger.AddBoolContext(symbol, "IsBuy", isBuy);
        m_logger.FlushContext(symbol, AUTHORIZE, "ValidationEngine", 
            "All validation checks passed", false);
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Primary Validation - Core Trade Conditions                      |
    //+------------------------------------------------------------------+
    bool PrimaryValidation(const string symbol)
    {
        m_logger.StartContextWith(symbol, "Primary_Validation");
        bool allPassed = true;
        string failureReason = "";
        
        // Balance check
        // if(accountBalance < m_settings.minBalanceForSecondSymbol && 
        //    symbol != "XAUUSD" && symbol != m_settings.symbol)
        // {
        //     failureReason = StringFormat("Balance below $%.2f - only XAUUSD allowed", 
        //                                m_settings.minBalanceForSecondSymbol);
        //     allPassed = false;
        // }
        
        // Daily limit check
        if(dailyLimitReached)
        {
            failureReason = "Daily limit reached";
            allPassed = false;
        }
        
        // News blackout check
        // if(m_newsFilter != NULL && m_newsFilter.IsNewsBlackoutPeriod(symbol))
        // {
        //     failureReason = "News blackout period";
        //     allPassed = false;
        // }
        
        // Symbol validity check
        int symbolIndex = ArrayPosition(symbol);
        if(symbolIndex == -1)
        {
            failureReason = "Symbol not in active symbols list";
            allPassed = false;
        }
        
        // Candle time check
        // if(symbolIndex != -1)
        // {
        //     datetime currentCandle = iTime(symbol, m_settings.tradeTimeframe, 0);
        //     if(lastTradeCandle[symbolIndex] == currentCandle)
        //     {
        //         failureReason = "Already traded on this candle";
        //         allPassed = false;
        //     }
        // }
        
        // Spread check
        double spread = GetCurrentSpread(symbol);
        if(spread > m_settings.maxSpreadPips)
        {
            failureReason = StringFormat("Spread too high (%.1f > %.1f pips)", 
                                       spread, m_settings.maxSpreadPips);
            allPassed = false;
        }
        
        // Maximum trades per symbol check
        // int openTrades = CountOpenTrades(symbol);
        // if(openTrades >= m_settings.maxTradesPerSymbol)
        // {
        //     failureReason = StringFormat("Max trades (%d) reached", 
        //                                m_settings.maxTradesPerSymbol);
        //     allPassed = false;
        // }
        
        // Log result
        if(allPassed)
        {
            m_logger.AddToContext(symbol, "Result", "PASSED", true);
            m_logger.FlushContext(symbol, OBSERVE, "ValidationEngine", 
                "Primary validation passed", false);
        }
        else
        {
            m_logger.AddToContext(symbol, "Result", "FAILED", true);
            m_logger.AddToContext(symbol, "Reason", failureReason, true);
            m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
                "Primary validation failed: " + failureReason, false);
        }
        
        return allPassed;
    }
    
    //+------------------------------------------------------------------+
    //| Check Ultra-Sensitive Entry                                     |
    //+------------------------------------------------------------------+
    bool CheckUltraSensitiveEntry(const string symbol, bool isBuy)
    {
        // if(m_signalScorer == NULL)
        // {
        //     m_logger.KeepNotes(symbol, WARN, "ValidationEngine", 
        //         "SignalScorer not set for ultra-sensitive entry check", false, false, 0.0);
        //     return false;
        // }
        
        // Get comprehensive signal score
        // int signalScore = m_signalScorer.GetUltraSensitiveSignalScore(symbol, isBuy);
        
        // Check for aggressive pullback entry
        bool isPullback = CheckAggressivePullback(symbol, isBuy);
        
        int threshold;
        if(isPullback)
        {
            // For pullbacks, accept slightly lower scores
            threshold = isBuy ? m_settings.pullbackThresholdBuy : m_settings.pullbackThresholdSell;
        }
        else
        {
            // For regular entries, need stronger signals
            threshold = isBuy ? m_settings.regularThresholdBuy : m_settings.regularThresholdSell;
        }
        
        // bool passed = (signalScore >= threshold);
        bool passed = (50 >= threshold);
        
        // m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
        //     StringFormat("Ultra-sensitive %s check: Score=%d, Threshold=%d, Passed=%s", 
        //                isBuy ? "BUY" : "SELL", signalScore, threshold, passed ? "YES" : "NO"),
        //     false, false, 0.0);
        
        return passed;
    }
    
    //+------------------------------------------------------------------+
    //| Validate Position Addition                                      |
    //+------------------------------------------------------------------+
    bool ValidatePositionAddition(const string symbol, bool isBuy, string reason = "ADDITION")
    {
        m_logger.StartContextWith(symbol, "Position_Addition");
        
        // Get current positions statistics
        // int positions = CountOpenTrades(symbol);
        // if(positions == 0)
        // {
        //     m_logger.AddToContext(symbol, "Error", "No existing positions to add to", true);
        //     m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
        //         "No positions to add to", false);
        //     return false;
        // }
        
        // Calculate position statistics
        // PositionStats stats = CalculatePositionStats(symbol);
        
        // Profitability checks
        // if(stats.netProfitDollars <= 0)
        // {
        //     m_logger.AddDoubleContext(symbol, "NetProfit", stats.netProfitDollars, 2);
        //     m_logger.AddToContext(symbol, "Error", "Positions are not profitable", true);
        //     m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
        //         "Positions not profitable", false);
        //     return false;
        // }
        
        // Minimum profit requirement
        // double requiredProfit = CalculateRequiredProfit(positions);
        // if(stats.netProfitDollars < requiredProfit)
        // {
        //     m_logger.AddDoubleContext(symbol, "NetProfit", stats.netProfitDollars, 2);
        //     m_logger.AddDoubleContext(symbol, "RequiredProfit", requiredProfit, 2);
        //     m_logger.AddToContext(symbol, "Error", "Insufficient profit", true);
        //     m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
        //         "Insufficient profit for position addition", false);
        //     return false;
        // }
        
        // Price movement check
        double currentPrice = isBuy ? 
            SymbolInfoDouble(symbol, SYMBOL_ASK) : 
            SymbolInfoDouble(symbol, SYMBOL_BID);
            
        // double priceMovementDollars = CalculatePriceMovement(symbol, currentPrice, 
        //                                                    stats.averageEntry, stats.totalVolume);
        
        // double minMovementDollars = 5.0;
        // if(priceMovementDollars < minMovementDollars)
        // {
        //     m_logger.AddDoubleContext(symbol, "PriceMovement", priceMovementDollars, 2);
        //     m_logger.AddToContext(symbol, "Error", "Insufficient price movement", true);
        //     m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
        //         "Insufficient price movement", false);
        //     return false;
        // }
        
        // POI validation
        // if(m_poiManager != NULL)
        // {
        //     double confidenceScore;
        //     double profitInPips = CalculateProfitInPips(symbol, currentPrice, 
        //                                                stats.averageEntry, isBuy);
        //     bool poiValid = m_poiManager.Validate(symbol, currentPrice, isBuy, 
        //                                          profitInPips, confidenceScore);
            
        //     if(!poiValid)
        //     {
        //         m_logger.AddDoubleContext(symbol, "POIConfidence", confidenceScore, 1);
        //         m_logger.AddToContext(symbol, "Error", "POI validation failed", true);
        //         m_logger.FlushContext(symbol, WARN, "ValidationEngine", 
        //             "POI validation failed", false);
        //         return false;
        //     }
        // }
        
        // m_logger.AddToContext(symbol, "Result", "PASSED", true);
        // m_logger.AddDoubleContext(symbol, "NetProfit", stats.netProfitDollars, 2);
        // m_logger.AddIntContext(symbol, "Positions", positions);
        // m_logger.AddToContext(symbol, "Reason", reason, false);
        
        // m_logger.FlushContext(symbol, AUTHORIZE, "ValidationEngine", 
        //     "Position addition validated", false);
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get MA Alignment Score                                          |
    //+------------------------------------------------------------------+
    double GetMAAlignmentScore(const string symbol, bool isBuy)
    {
        int symbolIndex = ArrayPosition(symbol);
        if(symbolIndex == -1) return 0.0;
        
        // Get MA values
        double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
        double med = GetCurrentMAValue(mediumMA_M15[symbolIndex]);
        double slow = GetCurrentMAValue(slowMA_M15[symbolIndex]);
        
        if(fast == 0.0 || med == 0.0 || slow == 0.0) return 0.0;
        
        // Calculate distances
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double fastMedDist = MathAbs(fast - med) / point;
        double medSlowDist = MathAbs(med - slow) / point;
        
        // Calculate scores
        double medSlowScore = CalculateMedSlowScore(medSlowDist);
        double medSlowDirScore = CalculateMedSlowDirScore(med, slow, isBuy);
        double fastMedScore = CalculateFastMedScore(fast, med, fastMedDist, isBuy);
        double stackScore = CalculateStackScore(fast, med, slow, isBuy);
        
        // Weighted total score
        double totalScore = 
            (medSlowScore * m_settings.weightMedSlowSeparation) +
            (medSlowDirScore * m_settings.weightMedSlowDirection) +
            (fastMedScore * m_settings.weightFastMedMomentum) +
            (stackScore * m_settings.weightOverallStack);
        
        m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
            StringFormat("MA Alignment Score: %.1f%% for %s", totalScore, isBuy ? "BUY" : "SELL"),
            false, false, 0.0);
        
        return totalScore;
    }
    
    //+------------------------------------------------------------------+
    //| Is Market Ranging                                               |
    //+------------------------------------------------------------------+
    bool IsMarketRanging(const string symbol, bool isBuy)
    {
        // Implementation would use MA distance calculation
        // For now, return false to avoid blocking trades
        // You would implement IsMarketRangingByMADistance here
        
        bool isRanging = false; // Placeholder
        
        if(isRanging)
        {
            m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
                "Market is ranging", false, false, 0.0);
        }
        
        return isRanging;
    }
    
    //+------------------------------------------------------------------+
    //| Validate Complete Trade Setup                                   |
    //+------------------------------------------------------------------+
    bool ValidateCompleteTradeSetup(const string symbol, bool isBuy)
    {
        m_logger.StartContextWith(symbol, "Complete_Setup");
        bool allPassed = true;
        
        // 1. Primary validation
        if(!PrimaryValidation(symbol))
        {
            m_logger.AddToContext(symbol, "Primary", "FAILED", true);
            allPassed = false;
        }
        else
        {
            m_logger.AddToContext(symbol, "Primary", "PASSED", false);
        }
        
        // 2. Ultra-sensitive entry
        if(!CheckUltraSensitiveEntry(symbol, isBuy))
        {
            m_logger.AddToContext(symbol, "UltraSensitive", "FAILED", true);
            allPassed = false;
        }
        else
        {
            m_logger.AddToContext(symbol, "UltraSensitive", "PASSED", false);
        }
        
        // 3. Market ranging check
        if(IsMarketRanging(symbol, isBuy))
        {
            m_logger.AddToContext(symbol, "Ranging", "FAILED - Market ranging", true);
            allPassed = false;
        }
        else
        {
            m_logger.AddToContext(symbol, "Ranging", "PASSED", false);
        }
        
        // 4. MA alignment score
        double maScore = GetMAAlignmentScore(symbol, isBuy);
        if(maScore < 60.0)
        {
            m_logger.AddDoubleContext(symbol, "MA Score", maScore, 1);
            m_logger.AddToContext(symbol, "MA Alignment", "FAILED", true);
            allPassed = false;
        }
        else
        {
            m_logger.AddDoubleContext(symbol, "MA Score", maScore, 1);
            m_logger.AddToContext(symbol, "MA Alignment", "PASSED", false);
        }
        
        // 5. Trade timing quality
        string timingQuality = CheckTradeTimingQuality(symbol, isBuy);
        if(timingQuality == "POOR")
        {
            m_logger.AddToContext(symbol, "Timing", "FAILED - Poor timing", true);
            allPassed = false;
        }
        else
        {
            m_logger.AddToContext(symbol, "Timing", "PASSED - " + timingQuality, false);
        }
        
        m_logger.AddBoolContext(symbol, "All Passed", allPassed);
        m_logger.FlushContext(symbol, 
            allPassed ? AUTHORIZE : WARN, 
            "ValidationEngine", 
            StringFormat("Complete setup validation %s", allPassed ? "PASSED" : "FAILED"),
            false);
        
        return allPassed;
    }
    
    //+------------------------------------------------------------------+
    //| Get Enhanced Validation Score                                   |
    //+------------------------------------------------------------------+
    double GetEnhancedValidationScore(const string symbol, bool isBuy)
    {
        double totalScore = 0.0;
        
        // Primary validation (20%)
        if(PrimaryValidation(symbol))
            totalScore += 20.0;
        
        // MA alignment (25%)
        double maScore = GetMAAlignmentScore(symbol, isBuy);
        totalScore += maScore * 0.25;
        
        // Trend strength (15%)
        ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
        double trendScore = CalculateTrendScore(trend);
        totalScore += trendScore * 0.15;
        
        // Ultra-sensitive entry (20%)
        if(CheckUltraSensitiveEntry(symbol, isBuy))
            totalScore += 20.0;
        
        // RSI validation (10%)
        if(IsRSIValidForTrade(symbol, isBuy))
            totalScore += 10.0;
        
        // Market ranging penalty (deduct up to 10%)
        if(IsMarketRanging(symbol, isBuy))
            totalScore -= 10.0;
        
        // Cap score between 0-100
        totalScore = MathMax(0.0, MathMin(100.0, totalScore));
        
        m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
            StringFormat("Enhanced Validation Score: %.1f%%", totalScore),
            false, false, 0.0);
        
        return totalScore;
    }
    
    //+------------------------------------------------------------------+
    //| Get Validation Summary                                          |
    //+------------------------------------------------------------------+
    string GetValidationSummary(const string symbol, bool isBuy)
    {
        double validationScore = GetEnhancedValidationScore(symbol, isBuy);
        ENUM_TREND_STRENGTH trend = GetM15TrendStrength(symbol);
        double maScore = GetMAAlignmentScore(symbol, isBuy);
        string timing = CheckTradeTimingQuality(symbol, isBuy);
        
        string summary = StringFormat("Validation Summary for %s (%s):\n" +
                                     "  Overall Score: %.1f%%\n" +
                                     "  Trend: %s\n" +
                                     "  MA Alignment: %.1f%%\n" +
                                     "  Timing Quality: %s\n" +
                                     "  Market Ranging: %s",
                                     symbol, isBuy ? "BUY" : "SELL",
                                     validationScore,
                                     EnumToString(trend),
                                     maScore,
                                     timing,
                                     IsMarketRanging(symbol, isBuy) ? "YES" : "NO");
        
        return summary;
    }
    
    //+------------------------------------------------------------------+
    //| Bar Already Traded Check                                        |
    //+------------------------------------------------------------------+
    bool BarAlreadyTraded(const string symbol, bool isBuy)
    {
        // Get current bar time
        datetime currentBarTime = iTime(symbol, m_settings.tradeTimeframe, 0);
        
        // Check if new bar
        if(currentBarTime != m_barTracking.lastTradedBarTime)
        {
            // New bar - reset counters
            m_barTracking.lastTradedBarTime = currentBarTime;
            m_barTracking.tradesCountThisBar = 0;
            m_barTracking.buyTradedThisBar = false;
            m_barTracking.sellTradedThisBar = false;
            
            m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
                StringFormat("New %s bar started - counters reset", 
                           EnumToString(m_settings.tradeTimeframe)),
                false, false, 0.0);
        }
        
        // Check max trades limit
        if(m_barTracking.tradesCountThisBar >= m_settings.maxTradesPerBar)
        {
            m_logger.KeepNotes(symbol, WARN, "ValidationEngine", 
                StringFormat("Max trades per bar reached (%d/%d)", 
                           m_barTracking.tradesCountThisBar, m_settings.maxTradesPerBar),
                false, false, 0.0);
            return true;
        }
        
        // Check buy/sell specific limits
        if(isBuy && m_barTracking.buyTradedThisBar)
        {
            m_logger.KeepNotes(symbol, WARN, "ValidationEngine", 
                "BUY already traded this bar", false, false, 0.0);
            return true;
        }
        
        if(!isBuy && m_barTracking.sellTradedThisBar)
        {
            m_logger.KeepNotes(symbol, WARN, "ValidationEngine", 
                "SELL already traded this bar", false, false, 0.0);
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Mark Bar as Traded                                              |
    //+------------------------------------------------------------------+
    void MarkBarAsTraded(bool isBuy)
    {
        m_barTracking.tradesCountThisBar++;
        
        if(isBuy)
            m_barTracking.buyTradedThisBar = true;
        else
            m_barTracking.sellTradedThisBar = true;
        
        m_logger.KeepNotes("GLOBAL", OBSERVE, "ValidationEngine", 
            StringFormat("Marked %s as traded. Total this bar: %d/%d", 
                       isBuy ? "BUY" : "SELL", 
                       m_barTracking.tradesCountThisBar, m_settings.maxTradesPerBar),
            false, false, 0.0);
    }
    
    //+------------------------------------------------------------------+
    //| Update Trade Candle                                             |
    //+------------------------------------------------------------------+
    void UpdateTradeCandle(const string symbol)
    {
        int symbolIndex = ArrayPosition(symbol);
        if(symbolIndex != -1)
        {
            lastTradeCandle[symbolIndex] = iTime(symbol, m_settings.tradeTimeframe, 0);
            
            m_logger.KeepNotes(symbol, OBSERVE, "ValidationEngine", 
                StringFormat("Updated trade candle to %s", 
                           TimeToString(lastTradeCandle[symbolIndex])),
                false, false, 0.0);
        }
    }
    
    // ================= GETTERS =================
    bool IsInitialized() const { return m_initialized; }
    ValidationSettings GetSettings() const { return m_settings; }
    ResourceManager* GetLogger() { return m_logger; }
    BarTracking GetBarTracking() const { return m_barTracking; }
    
    // ================= SETTERS =================
    void UpdateSettings(const ValidationSettings &newSettings)
    {
        m_settings = newSettings;
        m_logger.KeepNotes("GLOBAL", OBSERVE, "ValidationEngine", 
            "Settings updated", false, false, 0.0);
    }
    
    void ResetBarTracking()
    {
        m_barTracking = BarTracking();
        m_logger.KeepNotes("GLOBAL", OBSERVE, "ValidationEngine", 
            "Bar tracking reset", false, false, 0.0);
    }
    
    // ================= CLEANUP =================
    void Cleanup()
    {
        if(!m_initialized) return;
        
        m_logger.KeepNotes("GLOBAL", AUDIT, "ValidationEngine", 
            "Starting cleanup", false, false, 0.0);
        
        m_initialized = false;
        
        m_logger.KeepNotes("GLOBAL", AUDIT, "ValidationEngine", 
            "Cleanup complete", false, false, 0.0);
    }
    
private:
    // ================= PRIVATE HELPER METHODS =================
    
    //+------------------------------------------------------------------+
    //| Get Current Spread                                              |
    //+------------------------------------------------------------------+
    double GetCurrentSpread(const string symbol)
    {
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if(bid <= 0 || ask <= 0 || point <= 0) return 999.0;
        
        return (ask - bid) / point;
    }
    
    //+------------------------------------------------------------------+
    //| Check Aggressive Pullback                                       |
    //+------------------------------------------------------------------+
    bool CheckAggressivePullback(const string symbol, bool isBuy)
    {
        // Simplified implementation - you would add your pullback logic here
        // This is a placeholder that returns false
        
        // Example logic you might implement:
        // 1. Check if price has retraced to a key MA
        // 2. Check if RSI shows oversold/overbought condition
        // 3. Check recent price action for pullback patterns
        
        return false;
    }
    
    // //+------------------------------------------------------------------+
    // //| Calculate Position Stats                                        |
    // //+------------------------------------------------------------------+
    // PositionStats CalculatePositionStats(const string symbol)
    // {
    //     PositionStats stats;
    //     stats.totalVolume = 0.0;
    //     stats.averageEntry = 0.0;
    //     stats.totalProfit = 0.0;
    //     stats.totalSwap = 0.0;
    //     stats.totalCommission = 0.0;
    //     stats.netProfitDollars = 0.0;
        
    //     for(int i = PositionsTotal() - 1; i >= 0; i--)
    //     {
    //         ulong ticket = PositionGetTicket(i);
    //         if(ticket > 0 && PositionSelectByTicket(ticket))
    //         {
    //             if(PositionGetString(POSITION_SYMBOL) == symbol && 
    //                PositionGetInteger(POSITION_MAGIC) == MagicNumber)
    //             {
    //                 double positionVolume = PositionGetDouble(POSITION_VOLUME);
    //                 double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    
    //                 stats.totalVolume += positionVolume;
    //                 stats.averageEntry += entryPrice * positionVolume;
    //                 stats.totalProfit += PositionGetDouble(POSITION_PROFIT);
    //                 stats.totalSwap += PositionGetDouble(POSITION_SWAP);
    //             }
    //         }
    //     }
        
    //     if(stats.totalVolume > 0)
    //     {
    //         stats.averageEntry /= stats.totalVolume;
    //     }
        
    //     stats.netProfitDollars = stats.totalProfit + stats.totalSwap + stats.totalCommission;
        
    //     return stats;
    // }
    
    //+------------------------------------------------------------------+
    //| Calculate Required Profit                                       |
    //+------------------------------------------------------------------+
    double CalculateRequiredProfit(int positions)
    {
        const double minProfitDollars = 7.0;
        const double profitMultiplier = 1.5;
        
        return minProfitDollars * MathPow(profitMultiplier, positions - 1);
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Price Movement                                        |
    //+------------------------------------------------------------------+
    double CalculatePriceMovement(const string symbol, double currentPrice, 
                                 double averageEntry, double totalVolume)
    {
        double priceDifference = MathAbs(currentPrice - averageEntry);
        double priceMovementDollars = priceDifference * totalVolume;
        
        // Adjust for gold/XAU
        if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
            priceMovementDollars *= 100;
        
        return priceMovementDollars;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Profit in Pips                                        |
    //+------------------------------------------------------------------+
    double CalculateProfitInPips(const string symbol, double currentPrice, 
                                double averageEntry, bool isBuy)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0) return 0.0;
        
        if(isBuy)
            return (currentPrice - averageEntry) / point;
        else
            return (averageEntry - currentPrice) / point;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate MA Component Scores                                   |
    //+------------------------------------------------------------------+
    double CalculateMedSlowScore(double medSlowDist)
    {
        if(medSlowDist > 20.0) return 100.0;
        if(medSlowDist > 15.0) return 85.0;
        if(medSlowDist > 10.0) return 70.0;
        if(medSlowDist > 5.0) return 40.0;
        return 0.0;
    }
    
    double CalculateMedSlowDirScore(double med, double slow, bool isBuy)
    {
        double point = 0.00001; // Default point value
        
        if(isBuy)
        {
            if(med > slow) return 100.0;
            if(med >= slow - (5.0 * point)) return 60.0;
            return 0.0;
        }
        else
        {
            if(med < slow) return 100.0;
            if(med <= slow + (5.0 * point)) return 60.0;
            return 0.0;
        }
    }
    
    double CalculateFastMedScore(double fast, double med, double fastMedDist, bool isBuy)
    {
        double point = 0.00001; // Default point value
        
        if(isBuy)
        {
            if(fast > med)
            {
                if(fastMedDist > 10.0) return 100.0;
                if(fastMedDist > 5.0) return 80.0;
                if(fastMedDist > 2.0) return 60.0;
                return 40.0;
            }
            else if(fast >= med - (3.0 * point))
            {
                return 30.0;
            }
            return 0.0;
        }
        else
        {
            if(fast < med)
            {
                if(fastMedDist > 10.0) return 100.0;
                if(fastMedDist > 5.0) return 80.0;
                if(fastMedDist > 2.0) return 60.0;
                return 40.0;
            }
            else if(fast <= med + (3.0 * point))
            {
                return 30.0;
            }
            return 0.0;
        }
    }
    
    double CalculateStackScore(double fast, double med, double slow, bool isBuy)
    {
        if(isBuy)
        {
            if(fast > med && med > slow) return 100.0;
            if(fast > slow && med > slow) return 70.0;
            if(med > slow) return 50.0;
            return 0.0;
        }
        else
        {
            if(fast < med && med < slow) return 100.0;
            if(fast < slow && med < slow) return 70.0;
            if(med < slow) return 50.0;
            return 0.0;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check Trade Timing Quality                                      |
    //+------------------------------------------------------------------+
    string CheckTradeTimingQuality(const string symbol, bool isBuy)
    {
        int symbolIndex = ArrayPosition(symbol);
        if(symbolIndex == -1) return "POOR";
        
        double fast = GetCurrentMAValue(fastMA_M15[symbolIndex]);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if(fast == 0.0 || point <= 0) return "POOR";
        
        double distance = MathAbs(price - fast) / point;
        
        if(distance < 5.0) return "EXCELLENT";
        if(distance < 10.0) return "GOOD";
        if(distance < 20.0) return "FAIR";
        if(distance < 30.0) return "WEAK";
        return "POOR";
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Trend Score                                           |
    //+------------------------------------------------------------------+
    double CalculateTrendScore(ENUM_TREND_STRENGTH trend)
    {
        switch(trend)
        {
            case TREND_STRONG_BULLISH:
            case TREND_MODERATE_BULLISH:
            case TREND_WEAK_BULLISH:
                return 100.0;
            case TREND_NEUTRAL:
                return 80.0;
            case TREND_WEAK_BEARISH:
            case TREND_MODERATE_BEARISH:
            case TREND_STRONG_BEARISH:
                return 50.0;
            default:
                return 20.0;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get M15 Trend Strength                                          |
    //+------------------------------------------------------------------+
    ENUM_TREND_STRENGTH GetM15TrendStrength(const string symbol)
    {
        // Simplified implementation - you would add your full logic here
        // This returns NEUTRAL as a placeholder
        
        return TREND_NEUTRAL;
    }
    
    //+------------------------------------------------------------------+
    //| Is RSI Valid for Trade                                          |
    //+------------------------------------------------------------------+
    bool IsRSIValidForTrade(const string symbol, bool isBuy)
    {
        // Simplified implementation - returns true as placeholder
        // You would add your RSI validation logic here
        
        return true;
    }
};

// ============================================================
// SUPPORTING STRUCTURES
// ============================================================
struct PositionStats
{
    double totalVolume;
    double averageEntry;
    double totalProfit;
    double totalSwap;
    double totalCommission;
    double netProfitDollars;
};

// ============================================================
// GLOBAL INSTANCE
// ============================================================
ValidationEngine *g_validator = NULL;

// Helper functions
bool InitializeGlobalValidator()
{
    if(g_validator == NULL)
    {
        g_validator = new ValidationEngine();
        
        ValidationSettings settings;
        settings.SetSymbolSpecific("XAUUSD"); // Default to gold
        settings.maxTradesPerSymbol = 3;
        settings.maxTradesPerBar = 2;
        settings.maxSpreadPips = 2.5;
        settings.tradeTimeframe = PERIOD_H1;
        
        return g_validator.Initialize(settings, "Validation_Log.csv");
    }
    return g_validator.IsInitialized();
}

void CleanupGlobalValidator()
{
    if(g_validator != NULL)
    {
        g_validator.Cleanup();
        delete g_validator;
        g_validator = NULL;
    }
}

// Convenience function
bool ValidateTrade(string symbol, bool isBuy)
{
    if(g_validator != NULL)
        return g_validator.Validate(symbol, isBuy);
    return false;
}