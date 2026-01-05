// DecisionEngineInterface.mqh

#ifndef DECISION_ENGINE_INTERFACE_MQH
#define DECISION_ENGINE_INTERFACE_MQH

// ====================== TRADE PACKAGE INTERFACE ======================
// Minimal interface that contains ONLY what DecisionEngine needs
struct DecisionEngineInterface
{
    // Core signal data needed for decision making
    string symbol;
    double overallConfidence;
    string dominantDirection; // "BULLISH", "BEARISH", "NEUTRAL"
    datetime analysisTime;
    bool isValid;
    double weightedScore;
    
    // Signal info (minimal)
    ENUM_ORDER_TYPE orderType;
    double signalConfidence;
    string signalReason;
    
    // Basic setup info (if available)
    double entryPrice;
    double stopLoss;
    double takeProfit1;
    double positionSize;
    
    // MTF data (basic)
    int mtfBullishCount;
    int mtfBearishCount;
    double mtfWeight;
    
    DecisionEngineInterface() {
        symbol = "";
        overallConfidence = 0;
        dominantDirection = "NEUTRAL";
        analysisTime = 0;
        isValid = false;
        weightedScore = 0;
        orderType = ORDER_TYPE_BUY_LIMIT;
        signalConfidence = 0;
        signalReason = "";
        entryPrice = 0;
        stopLoss = 0;
        takeProfit1 = 0;
        positionSize = 0;
        mtfBullishCount = 0;
        mtfBearishCount = 0;
        mtfWeight = 0;
    }
    
    // Check if interface is valid
    bool IsValid() const {
        return (symbol != "" && analysisTime > 0);
    }
    
    // Get simple signal
    string GetSimpleSignal() const {
        switch(orderType) {
            case ORDER_TYPE_BUY: return "BUY";
            case ORDER_TYPE_SELL: return "SELL";
            default: return "HOLD";
        }
    }
    
    // Get MTF summary
    string GetMTFSummary() const {
        return StringFormat("B%d/S%d", mtfBullishCount, mtfBearishCount);
    }
};

#endif