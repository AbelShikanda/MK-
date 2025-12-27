// //+------------------------------------------------------------------+
// //|                        AnalysisData.mqh                          |
// //|                 Pure technical analysis structures               |
// //|                    No risk data, no account data                 |
// //+------------------------------------------------------------------+
// #ifndef ANALYSIS_DATA_MQH
// #define ANALYSIS_DATA_MQH

// #include <Trade/Trade.mqh>
// #include <Arrays/ArrayObj.mqh>

// // ============ ENUMS ============
// enum ENUM_TREND_STRENGTH
// {
//     TREND_VERY_WEAK = 0,     // 0-20
//     TREND_WEAK = 1,          // 21-40
//     TREND_NEUTRAL = 2,       // 41-60
//     TREND_STRONG = 3,        // 61-80
//     TREND_VERY_STRONG = 4    // 81-100
// };

// enum ENUM_DIVERGENCE_TYPE
// {
//     DIVERGENCE_NONE = 0,
//     DIVERGENCE_REGULAR_BULLISH,
//     DIVERGENCE_REGULAR_BEARISH,
//     DIVERGENCE_HIDDEN_BULLISH,
//     DIVERGENCE_HIDDEN_BEARISH
// };

// enum ENUM_MARKET_PHASE
// {
//     PHASE_ACCUMULATION,
//     PHASE_MARKUP,
//     PHASE_DISTRIBUTION,
//     PHASE_MARKDOWN,
//     PHASE_RANGE
// };

// // ============ CORE ANALYSIS STRUCTURES ============

// // Swing point structure
// struct SwingPoint
// {
//     datetime time;
//     double price;
//     double rsi;
//     int type;           // 1 = High, -1 = Low
//     int barIndex;
//     int strength;       // Strength rating (1-3)
    
//     // Constructor
//     SwingPoint() : time(0), price(0.0), rsi(0.0), type(0), barIndex(0), strength(1) {}
// };

// // Divergence signal
// struct DivergenceSignal
// {
//     bool exists;
//     ENUM_DIVERGENCE_TYPE type;
//     datetime latestTime;
//     double priceLevel;
//     double rsiLevel;
//     int strength;       // 1-3 scale
//     int confirmations;
//     double score;       // Divergence score (0-100)
//     datetime firstDetected;
//     string category;    // "Regular" or "Hidden"
    
//     // Constructor
//     DivergenceSignal() : exists(false), type(DIVERGENCE_NONE), latestTime(0),
//                         priceLevel(0.0), rsiLevel(0.0), strength(0), confirmations(0),
//                         score(0.0), firstDetected(0), category("") {}
    
//     // Methods
//     bool IsBullish() const { return type == DIVERGENCE_REGULAR_BULLISH || type == DIVERGENCE_HIDDEN_BULLISH; }
//     bool IsBearish() const { return type == DIVERGENCE_REGULAR_BEARISH || type == DIVERGENCE_HIDDEN_BEARISH; }
//     bool IsRegular() const { return type == DIVERGENCE_REGULAR_BULLISH || type == DIVERGENCE_REGULAR_BEARISH; }
//     bool IsHidden() const { return type == DIVERGENCE_HIDDEN_BULLISH || type == DIVERGENCE_HIDDEN_BEARISH; }
    
//     string GetDescription() const
//     {
//         if(!exists) return "No Divergence";
//         string desc = (IsBullish() ? "Bullish " : "Bearish ");
//         desc += (IsRegular() ? "Regular" : "Hidden");
//         desc += StringFormat(" (Score: %.1f)", score);
//         return desc;
//     }
// };

// // Point of Interest (POI) level
// struct POILevel
// {
//     double price;
//     string type;        // "RESISTANCE", "SUPPORT", "SWING_HIGH", "SWING_LOW", "LIQUIDITY"
//     string timeframe;   // "M15", "H1", "H4", "D1"
//     datetime timestamp;
//     bool isMajor;
//     bool isBroken;
//     int brokenSinceBar;
//     double strength;    // 0-100
    
//     // Constructor
//     POILevel() : price(0.0), type(""), timeframe(""), timestamp(0),
//                 isMajor(false), isBroken(false), brokenSinceBar(0), strength(0.0) {}
    
//     // Methods
//     bool IsResistance() const { return StringFind(type, "RESISTANCE") >= 0 || StringFind(type, "SWING_HIGH") >= 0; }
//     bool IsSupport() const { return StringFind(type, "SUPPORT") >= 0 || StringFind(type, "SWING_LOW") >= 0; }
    
//     double DistanceFrom(double currentPrice) const
//     {
//         return MathAbs(price - currentPrice) / price * 10000; // In pips * 10
//     }
    
//     string GetSummary() const
//     {
//         return StringFormat("%s @ %.5f (%s) - %s", type, price, timeframe, 
//                            isMajor ? "Major" : "Minor");
//     }
// };

// // Trend health tracking
// struct TrendHealth
// {
//     string symbol;
//     double strength;           // 0-100
//     double reversalRisk;       // 0-100
//     string protectionLevel;    // "SAFE", "WARNING", "DANGER"
//     string status;             // "INTACT", "WEAKENING", "BROKEN"
//     double multiTFSync;        // Multi-timeframe synchronization (0-100)
//     double momentum;           // Momentum strength (0-100)
//     double volumeConfirmation; // Volume confirmation (0-100)
//     datetime lastUpdate;
    
//     // Constructor
//     TrendHealth(string sym = "") : symbol(sym), strength(0.0), reversalRisk(0.0),
//                                   protectionLevel("SAFE"), status("INTACT"),
//                                   multiTFSync(0.0), momentum(0.0), volumeConfirmation(0.0),
//                                   lastUpdate(0) {}
    
//     // Methods
//     bool IsHealthy() const { return strength > 50 && reversalRisk < 60; }
//     bool NeedsProtection() const { return protectionLevel == "WARNING" || protectionLevel == "DANGER"; }

//     void Initialize(string sym = "")
//     {
//         if(sym != "") symbol = sym;
//         strength = 0.0;
//         reversalRisk = 0.0;
//         protectionLevel = "SAFE";
//         status = "INTACT";
//         multiTFSync = 0.0;
//         momentum = 0.0;
//         volumeConfirmation = 0.0;
//         lastUpdate = TimeCurrent();
//     }
    
//     void Update(double newStrength, double newReversalRisk)
//     {
//         strength = newStrength;
//         reversalRisk = newReversalRisk;
//         lastUpdate = TimeCurrent();
        
//         // Update protection level
//         if(reversalRisk > 80) protectionLevel = "DANGER";
//         else if(reversalRisk > 60) protectionLevel = "WARNING";
//         else protectionLevel = "SAFE";
        
//         // Update status
//         if(strength > 70) status = "INTACT";
//         else if(strength > 40) status = "WEAKENING";
//         else status = "BROKEN";
//     }
    
//     string GetSummary() const
//     {
//         return StringFormat("%s: Strength=%.1f, Risk=%.1f, Status=%s, Protection=%s",
//                           symbol, strength, reversalRisk, status, protectionLevel);
//     }
// };

// // Trend momentum tracking
// struct TrendMomentum
// {
//     string symbol;
//     double acceleration;    // Rate of change (positive = accelerating)
//     double consistency;     // How consistent (0-100)
//     double duration;        // How long trend has been active (bars)
//     datetime startTime;
//     datetime lastUpdate;
    
//     // Constructor
//     TrendMomentum(string sym = "") : symbol(sym), acceleration(0.0), 
//                                    consistency(0.0), duration(0.0),
//                                    startTime(0), lastUpdate(0) {}

//     void Initialize(string sym = "")
//     {
//         if(sym != "") symbol = sym;
//         acceleration = 0.0;
//         consistency = 0.0;
//         duration = 0.0;
//         startTime = 0;
//         lastUpdate = TimeCurrent();
//     }
    
//     // Methods
//     bool IsAccelerating() const { return acceleration > 0; }
//     bool IsDecelerating() const { return acceleration < 0; }
//     bool IsConsistent() const { return consistency > 70; }
    
//     void Update(double newAcceleration, double newConsistency)
//     {
//         acceleration = newAcceleration;
//         consistency = newConsistency;
//         lastUpdate = TimeCurrent();
        
//         if(startTime == 0 && MathAbs(acceleration) > 10)
//             startTime = lastUpdate;
            
//         if(startTime > 0)
//             duration = double(lastUpdate - startTime) / 3600.0; // Hours
//     }
    
//     string GetPhase() const
//     {
//         if(duration < 4) return "EARLY";
//         if(duration < 24) return "MATURE";
//         if(duration < 72) return "LATE";
//         return "EXTENDED";
//     }
// };

// // Market structure analysis
// struct MarketStructure
// {
//     string symbol;
//     ENUM_MARKET_PHASE phase;
//     double rangeHigh;
//     double rangeLow;
//     bool isRanging;
//     double rangeWidth;      // Percentage
//     int rangeBars;          // Bars in current range
//     string bias;            // "BULLISH", "BEARISH", "NEUTRAL"
//     datetime phaseStart;
    
//     // Constructor
//     MarketStructure(string sym = "") : symbol(sym), phase(PHASE_RANGE),
//                                      rangeHigh(0.0), rangeLow(0.0),
//                                      isRanging(true), rangeWidth(0.0),
//                                      rangeBars(0), bias("NEUTRAL"), phaseStart(0) {}

//     void Initialize(string sym = "")
//     {
//         if(sym != "") symbol = sym;
//         phase = PHASE_RANGE;
//         rangeHigh = 0.0;
//         rangeLow = 0.0;
//         isRanging = true;
//         rangeWidth = 0.0;
//         rangeBars = 0;
//         bias = "NEUTRAL";
//         phaseStart = TimeCurrent();
//     }
    
//     // Methods
//     bool IsBreakout(double price) const
//     {
//         if(!isRanging) return false;
//         return price > rangeHigh * 1.001 || price < rangeLow * 0.999;
//     }
    
//     void UpdateRange(double high, double low, int bars)
//     {
//         rangeHigh = high;
//         rangeLow = low;
//         rangeBars = bars;
//         rangeWidth = ((high - low) / low) * 100.0;
        
//         // Determine if ranging
//         isRanging = rangeWidth < 1.0 && bars > 10; // Less than 1% range for 10+ bars
        
//         // Determine bias within range
//         double midpoint = (high + low) / 2;
//         // Bias based on position within range (simplified)
//         bias = "NEUTRAL";
//     }
    
//     double GetRangeMidpoint() const { return (rangeHigh + rangeLow) / 2; }
    
//     string GetDescription() const
//     {
//         string phaseStr;
//         switch(phase)
//         {
//             case PHASE_ACCUMULATION: phaseStr = "ACCUMULATION"; break;
//             case PHASE_MARKUP: phaseStr = "MARKUP"; break;
//             case PHASE_DISTRIBUTION: phaseStr = "DISTRIBUTION"; break;
//             case PHASE_MARKDOWN: phaseStr = "MARKDOWN"; break;
//             case PHASE_RANGE: phaseStr = "RANGE"; break;
//         }
        
//         return StringFormat("%s: %s | Range: %.5f-%.5f (%.2f%%) | Bars: %d",
//                           symbol, phaseStr, rangeLow, rangeHigh, rangeWidth, rangeBars);
//     }
// };

// #endif // ANALYSIS_DATA_MQH