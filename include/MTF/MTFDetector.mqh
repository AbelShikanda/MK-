//+------------------------------------------------------------------+
//|                          MTFScore.mqh                            |
//|               Multi-Timeframe Market Structure Scorer            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

// ================= INCLUDES =================
#include "../utils/ResourceManager.mqh"  // Logging system

// ================= STRUCTURES =================
struct MTFScore {
    double sentiment;     // 0-100: Weekly/Daily mood
    double trend;         // 0-100: Trend alignment across TFs
    double push;          // 0-100: Lower TF momentum confirmation
    double total;         // 0-100: Overall market structure strength
    string comment;       // Brief analysis
    datetime timestamp;
};

struct TFLevel {
    ENUM_TIMEFRAMES tf;
    int weight;          // Importance weight (1-10)
    double maValue;
    double score;
};

// ================= CLASS =================
class MTFScorer {
private:
    // Configuration
    string m_symbol;
    int m_windowBars;
    double m_pipValue;
    
    // Timeframe hierarchy (fixed for simplicity)
    ENUM_TIMEFRAMES m_tfSentiment;  // Daily
    ENUM_TIMEFRAMES m_tfTrend;      // H4
    ENUM_TIMEFRAMES m_tfPush;       // H1 (validates M15/M5)
    
    // ADDED: Target timeframe for bot logic
    ENUM_TIMEFRAMES m_targetTF;     // Timeframe bot should consider (M15)
    
    // MA Handles (keep it simple: 3 MAs)
    int m_maFastHandle[4];   // 0:Fast, 1:Medium, 2:Slow, 3:Trend
    int m_maMediumHandle[4];
    int m_maSlowHandle[4];
    
    // ADDED: Target TF MA handles for proper drawing
    int m_targetFastHandle;
    int m_targetMediumHandle;
    int m_targetSlowHandle;
    
    // Drawing objects
    string m_commentId;
    string m_scoreLabelId;
    color m_bullColor;
    color m_bearColor;
    
    // State
    bool m_initialized;
    
    // Dependencies - now passed via Initialize()
    ResourceManager* m_logger;
    
    // ================= PERFORMANCE OPTIMIZATIONS =================
    // Cache values to reduce recalculations (PRESERVED)
    datetime m_lastUpdateTime;
    MTFScore m_cachedScore;
    double m_cachedMAValues[3][3];  // [tfIndex][maType] cache for 3 timeframes
    datetime m_maCacheTime;
    
    // String constants for optimization
    static const string LOG_PREFIX;
    
    // Symbol properties cache (PRESERVED)
    double m_cachedPoint;
    double m_cachedTickSize;
    int m_cachedDigits;
    datetime m_lastSymbolPropertiesUpdate;
    
    // Target MA cache (PRESERVED)
    static double m_cachedTargetMAValues[3];
    static datetime m_lastTargetMAUpdate;
    
    // Batch buffer for CopyBuffer (PRESERVED)
    double m_maBufferBatch[9];
    
    // Display throttle (PRESERVED)
    datetime m_lastDrawTime;
    
    // Log throttling (NEW - ONLY LOGGING OPTIMIZATION)
    datetime m_lastSummaryLogTime;
    
public:
    // ================= CONSTRUCTOR =================
    MTFScorer() {
        m_symbol = "";
        m_windowBars = 50;
        m_pipValue = 0;
        
        m_tfSentiment = PERIOD_D1;
        m_tfTrend = PERIOD_H4;
        m_tfPush = PERIOD_H1;
        m_targetTF = PERIOD_M15;  // Bot considers M15 timeframe
        
        m_bullColor = clrLimeGreen;
        m_bearColor = clrTomato;
        m_initialized = false;
        
        m_logger = NULL;
        
        // Initialize handles arrays efficiently
        ArrayInitialize(m_maFastHandle, INVALID_HANDLE);
        ArrayInitialize(m_maMediumHandle, INVALID_HANDLE);
        ArrayInitialize(m_maSlowHandle, INVALID_HANDLE);
        
        // Initialize target TF handles
        m_targetFastHandle = INVALID_HANDLE;
        m_targetMediumHandle = INVALID_HANDLE;
        m_targetSlowHandle = INVALID_HANDLE;
        
        // Generate IDs efficiently
        long tickCount = GetTickCount();
        m_commentId = StringFormat("MTF_Comment_%d", tickCount);
        m_scoreLabelId = StringFormat("MTF_Score_%d", tickCount);
        
        // Initialize performance caches
        m_lastUpdateTime = 0;
        m_maCacheTime = 0;
        m_lastDrawTime = 0;
        m_lastSymbolPropertiesUpdate = 0;
        m_lastSummaryLogTime = 0;
        
        // Initialize arrays
        ArrayInitialize(m_cachedMAValues, 0);
        ArrayInitialize(m_cachedTargetMAValues, 0);
        ArrayInitialize(m_maBufferBatch, 0);
        
        // Initialize cached score with neutral values
        m_cachedScore.sentiment = 50;
        m_cachedScore.trend = 50;
        m_cachedScore.push = 50;
        m_cachedScore.total = 50;
        m_cachedScore.timestamp = 0;
        
        // Initialize symbol caches
        m_cachedPoint = 0;
        m_cachedTickSize = 0;
        m_cachedDigits = 0;
    }
    
    // ================= DESTRUCTOR =================
    ~MTFScorer() {
        Deinitialize();
    }
    
    // ================= INITIALIZE =================
    bool Initialize(ResourceManager* logger, string symbol) {
        // Early exit: already initialized
        if(m_initialized) {
            return true;
        }
        
        // Store dependencies
        m_logger = logger;
        m_symbol = symbol;
        
        // Early exit: no logger
        if(!m_logger) {
            PrintFormat("%s ERROR: No logger provided for %s", LOG_PREFIX, m_symbol);
            return false;
        }
        
        // Log initialization (ESSENTIAL - kept)
        m_logger.KeepNotes(m_symbol, AUTHORIZE, LOG_PREFIX, 
            StringFormat("Initializing for %s", m_symbol));
        
        // Cache symbol properties (PRESERVED original caching logic)
        datetime currentTime = TimeCurrent();
        if(currentTime - m_lastSymbolPropertiesUpdate > 30) {
            m_cachedPoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            m_cachedTickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
            m_cachedDigits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
            m_pipValue = m_cachedPoint * 10;
            m_lastSymbolPropertiesUpdate = currentTime;
        }
        
        // Create MA handles for each timeframe
        if(!CreateMAHandles()) {
            m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, "Failed to create MA handles");
            return false;
        }
        
        m_initialized = true;
        m_logger.KeepNotes(m_symbol, AUTHORIZE, LOG_PREFIX, "Initialized successfully");
        return true;
    }
    
    // ================= DEINITIALIZE =================
    void Deinitialize() {
        // Early exit: not initialized
        if(!m_initialized) return;
        
        // Log cleanup (ESSENTIAL - kept)
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, AUDIT, LOG_PREFIX, "Starting cleanup");
        }
        
        // Release all MA handles (PRESERVED original logic)
        int releasedHandles = 0;
        
        int handleCount = ArraySize(m_maFastHandle);
        for(int i = 0; i < handleCount; i++) {
            if(m_maFastHandle[i] != INVALID_HANDLE) {
                IndicatorRelease(m_maFastHandle[i]);
                m_maFastHandle[i] = INVALID_HANDLE;
                releasedHandles++;
            }
            if(m_maMediumHandle[i] != INVALID_HANDLE) {
                IndicatorRelease(m_maMediumHandle[i]);
                m_maMediumHandle[i] = INVALID_HANDLE;
                releasedHandles++;
            }
            if(m_maSlowHandle[i] != INVALID_HANDLE) {
                IndicatorRelease(m_maSlowHandle[i]);
                m_maSlowHandle[i] = INVALID_HANDLE;
                releasedHandles++;
            }
        }
        
        // Release target TF handles
        if(m_targetFastHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetFastHandle);
            m_targetFastHandle = INVALID_HANDLE;
            releasedHandles++;
        }
        if(m_targetMediumHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetMediumHandle);
            m_targetMediumHandle = INVALID_HANDLE;
            releasedHandles++;
        }
        if(m_targetSlowHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetSlowHandle);
            m_targetSlowHandle = INVALID_HANDLE;
            releasedHandles++;
        }
        
        // Remove drawings
        ObjectDelete(0, m_commentId);
        ObjectDelete(0, m_scoreLabelId);
        
        // Log cleanup completion (ESSENTIAL - kept)
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, AUDIT, LOG_PREFIX, 
                StringFormat("Cleanup completed: %d handles released", releasedHandles));
        }
        
        // Reset state
        m_initialized = false;
        m_logger = NULL;
    }
    
    // ================= EVENT HANDLERS =================
    
    void OnTick() {
        // Early exit: not initialized (NO LOGGING IN HOT PATH)
        if(!m_initialized) {
            return;
        }
        
        // PERFORMANCE OPTIMIZATION: Update only once per second (PRESERVED)
        datetime currentTime = TimeCurrent();
        if(currentTime <= m_lastUpdateTime) {
            DisplayOnChart(m_cachedScore);
            return;
        }
        
        m_lastUpdateTime = currentTime;
        
        // Log periodic summary every 5 minutes (NEW - reduces spam)
        if(currentTime - m_lastSummaryLogTime >= 60) {
            if(m_logger) {
                m_logger.KeepNotes(m_symbol, OBSERVE, LOG_PREFIX, 
                    StringFormat("Active - Last score: %.0f (age: %d sec)", 
                        m_cachedScore.total, 
                        (int)(currentTime - m_cachedScore.timestamp)));
            }
            m_lastSummaryLogTime = currentTime;
        }
        
        // Update scores and display
        MTFScore score = CalculateScore();
        DisplayOnChart(score);
        
        // Cache the score for next tick (PRESERVED)
        m_cachedScore = score;
    }
    
    void OnTimer() {
        // Early exit: not initialized (NO LOGGING)
        if(!m_initialized) {
            return;
        }
        
        // Timer-based updates could go here
        // No logging to avoid spam
    }
    
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result) {
        // Early exit: not initialized
        if(!m_initialized || !m_logger) {
            return;
        }
        
        // Only log trade execution events and errors (ESSENTIAL)
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD || result.retcode != 0) {
            m_logger.KeepNotes(m_symbol, AUDIT, LOG_PREFIX, 
                StringFormat("Trade: %s (retcode: %d)", 
                    EnumToString(trans.type), result.retcode));
        }
    }
    
    // ================= PUBLIC METHODS =================
    
    MTFScore CalculateScore() {
        // Early exit: not initialized
        if(!m_initialized) {
            MTFScore empty;
            empty.timestamp = TimeCurrent();
            empty.sentiment = 50;
            empty.trend = 50;
            empty.push = 50;
            empty.total = 50;
            empty.comment = "Not initialized";
            return empty;
        }
        
        MTFScore score;
        score.timestamp = TimeCurrent();
        
        // PERFORMANCE OPTIMIZATION: Get all MA values at once (PRESERVED)
        double sentimentFast, sentimentMedium, sentimentSlow;
        double trendFast, trendMedium, trendSlow;
        double pushFast, pushMedium, pushSlow;
        
        if(!GetAllMAValues(sentimentFast, sentimentMedium, sentimentSlow,
                        trendFast, trendMedium, trendSlow,
                        pushFast, pushMedium, pushSlow)) {
            // If failed, return neutral score
            score.sentiment = 50;
            score.trend = 50;
            score.push = 50;
            score.total = 50;
            score.comment = "MA fetch failed";
            
            // Log error (ESSENTIAL - but limited frequency)
            static datetime lastErrorLog = 0;
            if(TimeCurrent() - lastErrorLog > 60) { // Log max once per minute
                if(m_logger) m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, "Failed to get MA values");
                lastErrorLog = TimeCurrent();
            }
            return score;
        }
        
        // Calculate scores (PRESERVED original logic)
        score.sentiment = CalculateSentimentScore(sentimentFast, sentimentMedium, sentimentSlow);
        score.trend = CalculateTrendScore(sentimentFast, sentimentMedium,
                                        trendFast, trendMedium,
                                        pushFast, pushMedium);
        
        double targetFast = GetTargetMAValue(0);
        double targetMedium = GetTargetMAValue(1);
        score.push = CalculatePushScore(sentimentFast, sentimentMedium,
                                    trendFast, trendMedium,
                                    targetFast, targetMedium);
        
        score.total = (score.sentiment * 0.4) + (score.trend * 0.4) + (score.push * 0.2);
        
        // Store in cache (PRESERVED)
        m_cachedScore = score;
        
        return score;
    }
    
    bool IsInitialized() const { return m_initialized; }
    
    void SetTargetTF(ENUM_TIMEFRAMES tf) {
        m_targetTF = tf;
        
        // Early exit: not initialized yet
        if(!m_initialized) return;
        
        // Recreate target TF MA handles if already initialized
        if(m_targetFastHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetFastHandle);
            m_targetFastHandle = INVALID_HANDLE;
        }
        if(m_targetMediumHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetMediumHandle);
            m_targetMediumHandle = INVALID_HANDLE;
        }
        if(m_targetSlowHandle != INVALID_HANDLE) {
            IndicatorRelease(m_targetSlowHandle);
            m_targetSlowHandle = INVALID_HANDLE;
        }
        
        CreateTargetTFMAHandles();
        
        // Log configuration change (ESSENTIAL)
        if(m_logger) {
            m_logger.KeepNotes(m_symbol, AUTHORIZE, LOG_PREFIX, 
                StringFormat("Target timeframe changed to %s", EnumToString(tf)));
        }
        
        // Clear MA cache since timeframe changed (PRESERVED)
        m_maCacheTime = 0;
        ArrayInitialize(m_cachedMAValues, 0);
        ArrayInitialize(m_cachedTargetMAValues, 0);
        m_lastTargetMAUpdate = 0;
    }
    
    // ================= PRIVATE METHODS =================
    
private:
    // Create MA handles for all timeframes
    bool CreateMAHandles() {
        // Early exit: no logger
        if(!m_logger) return false;
        
        // Create MA handles (PRESERVED original logic)
        m_maFastHandle[0] = iMA(m_symbol, m_tfSentiment, 9, 0, MODE_EMA, PRICE_CLOSE);
        m_maMediumHandle[0] = iMA(m_symbol, m_tfSentiment, 21, 0, MODE_EMA, PRICE_CLOSE);
        m_maSlowHandle[0] = iMA(m_symbol, m_tfSentiment, 89, 0, MODE_EMA, PRICE_CLOSE);
        
        m_maFastHandle[1] = iMA(m_symbol, m_tfTrend, 9, 0, MODE_EMA, PRICE_CLOSE);
        m_maMediumHandle[1] = iMA(m_symbol, m_tfTrend, 21, 0, MODE_EMA, PRICE_CLOSE);
        m_maSlowHandle[1] = iMA(m_symbol, m_tfTrend, 89, 0, MODE_EMA, PRICE_CLOSE);
        
        m_maFastHandle[2] = iMA(m_symbol, m_tfPush, 9, 0, MODE_EMA, PRICE_CLOSE);
        m_maMediumHandle[2] = iMA(m_symbol, m_tfPush, 21, 0, MODE_EMA, PRICE_CLOSE);
        m_maSlowHandle[2] = iMA(m_symbol, m_tfPush, 89, 0, MODE_EMA, PRICE_CLOSE);
        
        // Check all handles are valid
        for(int i = 0; i < 3; i++) {
            if(m_maFastHandle[i] == INVALID_HANDLE || 
               m_maMediumHandle[i] == INVALID_HANDLE || 
               m_maSlowHandle[i] == INVALID_HANDLE) {
                m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, 
                    StringFormat("Failed to create MA handles for TF index %d", i));
                return false;
            }
        }
        
        // Create target TF handles
        if(!CreateTargetTFMAHandles()) {
            m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, "Failed to create target TF MA handles");
            return false;
        }
        
        return true;
    }
    
    // Create target timeframe MA handles for drawing
    bool CreateTargetTFMAHandles() {
        // Early exit: no logger
        if(!m_logger) return false;
        
        // Create MAs for the target timeframe (PRESERVED)
        m_targetFastHandle = iMA(m_symbol, m_targetTF, 9, 0, MODE_EMA, PRICE_CLOSE);
        m_targetMediumHandle = iMA(m_symbol, m_targetTF, 21, 0, MODE_EMA, PRICE_CLOSE);
        m_targetSlowHandle = iMA(m_symbol, m_targetTF, 89, 0, MODE_EMA, PRICE_CLOSE);
        
        if(m_targetFastHandle == INVALID_HANDLE || 
           m_targetMediumHandle == INVALID_HANDLE || 
           m_targetSlowHandle == INVALID_HANDLE) {
            m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, "Failed to create target TF MA handles");
            return false;
        }
        
        return true;
    }
    
    // Get all MA values at once (reduces CopyBuffer calls) - PRESERVED
    bool GetAllMAValues(double &sentFast, double &sentMed, double &sentSlow,
                    double &trendFast, double &trendMed, double &trendSlow,
                    double &pushFast, double &pushMed, double &pushSlow) {
        // Early exit: not initialized
        if(!m_initialized) return false;
        
        datetime currentTime = TimeCurrent();
        
        // Check cache first (valid for 2 seconds) - EARLY EXIT (PRESERVED)
        if(m_maCacheTime > 0 && (currentTime - m_maCacheTime) <= 2) {
            sentFast = m_cachedMAValues[0][0];
            sentMed = m_cachedMAValues[0][1];
            sentSlow = m_cachedMAValues[0][2];
            
            trendFast = m_cachedMAValues[1][0];
            trendMed = m_cachedMAValues[1][1];
            trendSlow = m_cachedMAValues[1][2];
            
            pushFast = m_cachedMAValues[2][0];
            pushMed = m_cachedMAValues[2][1];
            pushSlow = m_cachedMAValues[2][2];
            
            return true;
        }
        
        // Get all values fresh (PRESERVED original logic)
        double value0[1], value1[1], value2[1], value3[1], value4[1], value5[1], value6[1], value7[1], value8[1];
        
        bool success[9];
        
        success[0] = (CopyBuffer(m_maFastHandle[0], 0, 0, 1, value0) >= 1);
        success[1] = (CopyBuffer(m_maMediumHandle[0], 0, 0, 1, value1) >= 1);
        success[2] = (CopyBuffer(m_maSlowHandle[0], 0, 0, 1, value2) >= 1);
        
        success[3] = (CopyBuffer(m_maFastHandle[1], 0, 0, 1, value3) >= 1);
        success[4] = (CopyBuffer(m_maMediumHandle[1], 0, 0, 1, value4) >= 1);
        success[5] = (CopyBuffer(m_maSlowHandle[1], 0, 0, 1, value5) >= 1);
        
        success[6] = (CopyBuffer(m_maFastHandle[2], 0, 0, 1, value6) >= 1);
        success[7] = (CopyBuffer(m_maMediumHandle[2], 0, 0, 1, value7) >= 1);
        success[8] = (CopyBuffer(m_maSlowHandle[2], 0, 0, 1, value8) >= 1);
        
        // Check if any failed
        int failedCount = 0;
        for(int i = 0; i < 9; i++) {
            if(!success[i]) failedCount++;
        }
        
        // Early exit: too many failures
        if(failedCount > 3) {
            // Log error but throttle (max once per minute)
            static datetime lastCopyError = 0;
            if(TimeCurrent() - lastCopyError > 60) {
                if(m_logger) {
                    m_logger.KeepNotes(m_symbol, WARN, LOG_PREFIX, 
                        StringFormat("Failed to copy %d MA buffers", failedCount));
                }
                lastCopyError = TimeCurrent();
            }
            return false;
        }
        
        // Assign values
        sentFast = value0[0];
        sentMed = value1[0];
        sentSlow = value2[0];
        
        trendFast = value3[0];
        trendMed = value4[0];
        trendSlow = value5[0];
        
        pushFast = value6[0];
        pushMed = value7[0];
        pushSlow = value8[0];
        
        // Update cache (PRESERVED)
        m_cachedMAValues[0][0] = sentFast;
        m_cachedMAValues[0][1] = sentMed;
        m_cachedMAValues[0][2] = sentSlow;
        
        m_cachedMAValues[1][0] = trendFast;
        m_cachedMAValues[1][1] = trendMed;
        m_cachedMAValues[1][2] = trendSlow;
        
        m_cachedMAValues[2][0] = pushFast;
        m_cachedMAValues[2][1] = pushMed;
        m_cachedMAValues[2][2] = pushSlow;
        
        m_maCacheTime = currentTime;
        
        return true;
    }
    
    // Calculate sentiment score using pre-fetched values - PRESERVED
    double CalculateSentimentScore(double fastMA, double mediumMA, double slowMA) {
        if(fastMA == 0 && mediumMA == 0 && slowMA == 0) return 50;
        
        int bullishConditions = 0;
        if(fastMA > mediumMA) bullishConditions++;
        if(mediumMA > slowMA) bullishConditions++;
        
        int bearishConditions = 0;
        if(fastMA < mediumMA) bearishConditions++;
        if(mediumMA < slowMA) bearishConditions++;
        
        double score = 50;
        if(bullishConditions == 2) score = 100;
        else if(bullishConditions == 1) score = 75;
        else if(bearishConditions == 2) score = 0;
        else if(bearishConditions == 1) score = 25;
        
        return score;
    }
    
    // Calculate trend alignment score using pre-fetched values - PRESERVED
    double CalculateTrendScore(double sentimentFast, double sentimentMedium,
                            double trendFast, double trendMedium,
                            double pushFast, double pushMedium) {
        if(sentimentFast == 0 && trendFast == 0 && pushFast == 0) return 50;
        
        double score = 0;
        
        bool dailyBullish = (sentimentFast > sentimentMedium);
        bool dailyBearish = (sentimentFast < sentimentMedium);
        bool h4Bullish = (trendFast > trendMedium);
        bool h4Bearish = (trendFast < trendMedium);
        bool h1Bullish = (pushFast > pushMedium);
        bool h1Bearish = (pushFast < pushMedium);
        
        int bullishSignals = 0;
        int bearishSignals = 0;
        
        if(dailyBullish) bullishSignals++;
        else if(dailyBearish) bearishSignals++;
        
        if(h4Bullish) bullishSignals++;
        else if(h4Bearish) bearishSignals++;
        
        if(h1Bullish) bullishSignals++;
        else if(h1Bearish) bearishSignals++;
        
        if(bullishSignals == 3 || bearishSignals == 3) {
            score += 60;
        }
        else if(bullishSignals == 2 || bearishSignals == 2) {
            score += 40;
        }
        else if((bullishSignals == 1 && bearishSignals == 0) || 
                (bearishSignals == 1 && bullishSignals == 0)) {
            score += 20;
        }
        
        if(score == 0) {
            if(bullishSignals > 0 || bearishSignals > 0) {
                score = 10;
            }
        }
        
        bool allAboveMAs = (sentimentFast > sentimentMedium && 
                        trendFast > trendMedium && 
                        pushFast > pushMedium);
        bool allBelowMAs = (sentimentFast < sentimentMedium && 
                        trendFast < trendMedium && 
                        pushFast < pushMedium);
        
        if(allAboveMAs || allBelowMAs) {
            score += 40;
        }
        else {
            int aboveCount = 0;
            int belowCount = 0;
            
            if(sentimentFast > sentimentMedium) aboveCount++;
            else if(sentimentFast < sentimentMedium) belowCount++;
            
            if(trendFast > trendMedium) aboveCount++;
            else if(trendFast < trendMedium) belowCount++;
            
            if(pushFast > pushMedium) aboveCount++;
            else if(pushFast < pushMedium) belowCount++;
            
            if(aboveCount >= 2 || belowCount >= 2) {
                score += 20;
            }
        }
        
        if(score > 100) score = 100;
        if(score < 10 && (sentimentFast != 0 || trendFast != 0 || pushFast != 0)) {
            score = 10;
        }
        
        return score;
    }
    
    // Calculate push confirmation score using pre-fetched values - PRESERVED
    double CalculatePushScore(double sentimentFast, double sentimentMedium,
                            double trendFast, double trendMedium,
                            double targetFast, double targetMedium) {
        if(targetFast == 0 || targetMedium == 0) {
            return 50;
        }
        
        bool higherBullish = (sentimentFast > sentimentMedium && trendFast > trendMedium);
        bool higherBearish = (sentimentFast < sentimentMedium && trendFast < trendMedium);
        
        if(!higherBullish && !higherBearish) {
            return 50;
        }
        
        bool targetBullish = (targetFast > targetMedium);
        bool targetBearish = (targetFast < targetMedium);
        
        int score = 50;
        
        if((higherBullish && targetBullish) || (higherBearish && targetBearish)) {
            score = 100;
        }
        else if((higherBullish && targetBearish) || (higherBearish && targetBullish)) {
            score = 25;
        }
        
        return score;
    }
    
    // Get target TF MA value (with handle recreation on failure) - PRESERVED
    double GetTargetMAValue(int maType) {
        if(maType < 0 || maType > 2) return 0;
        
        datetime currentTime = TimeCurrent();
        
        // Return cached value if recent (3 seconds) AND not zero (PRESERVED)
        if(m_lastTargetMAUpdate > 0 && (currentTime - m_lastTargetMAUpdate) <= 3) {
            if(m_cachedTargetMAValues[maType] != 0) {
                return m_cachedTargetMAValues[maType];
            }
        }
        
        int handle = INVALID_HANDLE;
        int period = 0;
        
        if(maType == 0) {
            handle = m_targetFastHandle;
            period = 9;
        }
        else if(maType == 1) {
            handle = m_targetMediumHandle;
            period = 21;
        }
        else if(maType == 2) {
            handle = m_targetSlowHandle;
            period = 89;
        }
        
        // If handle is invalid, try to recreate it
        if(handle == INVALID_HANDLE) {
            handle = iMA(m_symbol, m_targetTF, period, 0, MODE_EMA, PRICE_CLOSE);
            
            if(maType == 0) m_targetFastHandle = handle;
            else if(maType == 1) m_targetMediumHandle = handle;
            else if(maType == 2) m_targetSlowHandle = handle;
            
            if(handle == INVALID_HANDLE) {
                return 0;
            }
        }
        
        double maValue[1];
        if(CopyBuffer(handle, 0, 0, 1, maValue) < 1) {
            IndicatorRelease(handle);
            handle = iMA(m_symbol, m_targetTF, period, 0, MODE_EMA, PRICE_CLOSE);
            
            if(maType == 0) m_targetFastHandle = handle;
            else if(maType == 1) m_targetMediumHandle = handle;
            else if(maType == 2) m_targetSlowHandle = handle;
            
            if(handle == INVALID_HANDLE || CopyBuffer(handle, 0, 0, 1, maValue) < 1) {
                return 0;
            }
        }
        
        if(maValue[0] == 0) {
            return 0;
        }
        
        // Update cache (PRESERVED)
        m_cachedTargetMAValues[maType] = maValue[0];
        m_lastTargetMAUpdate = currentTime;
        
        return maValue[0];
    }
    
    // Display scores on chart
    void DisplayOnChart(MTFScore &score) {
        if(!m_initialized) return;
        
        // Only draw every 3 seconds to reduce CPU load (PRESERVED)
        datetime currentTime = TimeCurrent();
        if(currentTime - m_lastDrawTime < 3) return;
        
        m_lastDrawTime = currentTime;
        
        DrawMALines();
    }
    
    // Draw MA lines on chart - PRESERVED
    void DrawMALines() {
        if(!m_initialized) return;
        
        CleanUpMALines();
        
        // Get cached target MA values (no logging in display functions)
        double fastMA = GetTargetMAValue(0);
        double mediumMA = GetTargetMAValue(1);
        double slowMA = GetTargetMAValue(2);
        
        // No logging - display functions should be silent
    }
    
    // Clean up MA lines - PRESERVED
    void CleanUpMALines() {
        static string objects[9] = {
            "MTF_FastMA_" + m_symbol,
            "MTF_MediumMA_" + m_symbol, 
            "MTF_SlowMA_" + m_symbol,
            "MTF_Fast_Zone_" + m_symbol,
            "MTF_Medium_Zone_" + m_symbol,
            "MTF_Slow_Zone_" + m_symbol,
            "MTF_Fast_Label_" + m_symbol,
            "MTF_Medium_Label_" + m_symbol,
            "MTF_Slow_Label_" + m_symbol
        };
        
        int objCount = ArraySize(objects);
        for(int i = 0; i < objCount; i++) {
            ObjectDelete(0, objects[i]);
        }
        
        for(int i = 199; i >= 0; i--) {
            string fastName = "MTF_Fast_" + m_symbol + "_" + IntegerToString(i);
            string mediumName = "MTF_Medium_" + m_symbol + "_" + IntegerToString(i);
            string slowName = "MTF_Slow_" + m_symbol + "_" + IntegerToString(i);
            
            ObjectDelete(0, fastName);
            ObjectDelete(0, mediumName);
            ObjectDelete(0, slowName);
        }
    }
};

// Initialize static constants
const string MTFScorer::LOG_PREFIX = "MTFScorer";
double MTFScorer::m_cachedTargetMAValues[3] = {0, 0, 0};
datetime MTFScorer::m_lastTargetMAUpdate = 0;