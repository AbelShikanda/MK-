
//+------------------------------------------------------------------+
//|                     MarketStructure.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
MarketStructure.mqh :
    - SUPPLY/DEMAND ZONES - Strong imbalance areas
    - ORDER FLOW CLUSTERS -  Volume accumulation at specific price levels
    - MARKET STRUCTURE SHIFT - Break of significant swing points 
    - BREAK OF MARKET STRUCTURE BOS - Clear directional change
    - CHANGE OF CHARACTER CHOCH - Momentum shift confirmation
    - LIQUIDITY GRABS - Stop hunts that create reversals Stop hunts at obvious levels
    - ORDER_BLOCK

    //+------------------------------------------------------------------+
    //|                     ssddZone.mqh                         |
    //|
    // 1. Swing high/low detection
    // 2. Volume analysis at swing points
    // 3. Imbalance calculation
    // 4. Zone strength scoring                   |
    //+------------------------------------------------------------------+
    - ssddZone.mqh - Strong imbalance areas
            struct SupplyDemandZone {
                double zoneHigh;
                double zoneLow;
                double basePrice;
                datetime formationTime;
                int strength; // 1-10 based on volume, time, touches
                ENUM_ZONE_TYPE type; // Fresh, Rally-Base, Drop-Base
            };
            SupplyDemandZone FindBestZone(string symbol, ENUM_TIMEFRAMES tf) {
                // Steps:
                // 1. Find swing points with strong momentum candles
                // 2. Check for volume spike at swing point
                // 3. Measure subsequent price action (steep move away)
                // 4. Calculate zone width based on ATR
                // 5. Score based on: volume, time since formation, untouched count
            }
    //+------------------------------------------------------------------+
    //|                     OrderFlowCluster.mqh                         |
    //|                  
    // 1. Tick data or 1-minute data with volume
    // 2. Volume Profile indicator
    // 3. Cluster detection algorithm                  |
    //+------------------------------------------------------------------+
    - OrderFlowCluster.mqh  -  Volume accumulation at specific price levels
            struct OrderFlowCluster {
                double priceLevel;
                double volume;
                datetime startTime;
                datetime endTime;
                int clusterType; // 0=bid, 1=ask, 2=balanced
            };
            OrderFlowCluster DetectClusters(string symbol, int lookback=100) {
                // Implementation:
                // 1. Get tick data with bid/ask volumes delta
                // 2. Create price histogram (e.g., 0.0001 increments for forex)
                // 3. Identify clusters where volume > average * 2
                // 4. Classify as bid/ask cluster based on order imbalance
            }
    //+------------------------------------------------------------------+
    //|                     MSS.mqh                  
    // 1. Swing point detection algorithm
    // 2. Trend identification
    // 3. Breakout confirmation                  |
    //+------------------------------------------------------------------+
    - MSS.mqh - Break of significant swing points 
            struct MarketStructure {
                double swingHigh;
                double swingLow;
                int trendDirection; // 1=up, -1=down, 0=range
                datetime lastBreak;
            };
            bool DetectMSS(string symbol, ENUM_TIMEFRAMES tf) {
                // Steps:
                // 1. Identify last 3 swing points (HH, HL for uptrend or LH, LL for downtrend)
                // 2. Check if price breaks previous swing point
                // 3. Confirm with closing beyond swing point
                // 4. Check for follow-through in next candles
            }
    //+------------------------------------------------------------------+
    //|                     BOS.mqh                         |
    //|                  
    // 1. Market structure definition (higher highs/lows or lower highs/lows)
    // 2. Breakout detection with confirmation
    // 3. Momentum validation                   |
    //+------------------------------------------------------------------+
    - BOS.mqh - Clear directional change
            bool DetectBOS(string symbol, ENUM_TIMEFRAMES tf) {
                // For bullish BOS:
                // 1. Previous structure: Lower Highs & Lower Lows
                // 2. Price breaks previous higher high
                // 3. Closes above structure with momentum
                // 4. Creates higher low on retest
                
                // For bearish BOS:
                // 1. Previous structure: Higher Highs & Higher Lows
                // 2. Price breaks previous lower low
                // 3. Closes below structure with momentum
                // 4. Creates lower high on retest
            }
    //+------------------------------------------------------------------+
    //|                     CHOCH.mqh                         |
    //|                  
    // 1. Momentum indicators (RSI, MACD)
    // 2. Volume analysis
    // 3. Price structure analysis                   |
    //+------------------------------------------------------------------+
    - CHOCH.mqh - Momentum shift confirmation
            bool DetectCHoCH(string symbol, ENUM_TIMEFRAMES tf) {
                // Conditions:
                // 1. Break of market structure
                // 2. Momentum divergence (price makes higher high but indicator doesn't)
                // 3. Volume confirmation
                // 4. Follow-through candles
            }
    //+------------------------------------------------------------------+
    //|                     LiquidityGrab.mqh                         |
    //|                  
    // 1. Recent swing highs/lows
    // 2. Round number detection
    // 3. Volume spike detection
    // 4. Rejection pattern recognition                   |
    //+------------------------------------------------------------------+
    - LiquidityGrab.mqh - Stop hunts that create reversals Stop hunts at obvious levels
            bool IsLiquidityGrab(string symbol, ENUM_TIMEFRAMES tf) {
                // Factors to check:
                // 1. Price spikes beyond obvious level (round number, swing high/low)
                // 2. Quick rejection (wick > body * 2)
                // 3. High volume on spike
                // 4. Returns to previous range quickly
                // 5. Often creates Fair Value Gap
                
                return (hasSpike && hasRejection && highVolume && createsFVG);
            }
    //+------------------------------------------------------------------+
    //|                     OrderBLock.mqh                         |
    //|                  
    // 1. 
    // 2. 
    // 3. 
    // 4.                    |
    //+------------------------------------------------------------------+
    - OrderBLock.mqh - Stop hunts that create reversals Stop hunts at obvious levels
//+------------------------------------------------------------------+
//|                     Liquidity.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
Liquidity.mqh:
    - VOLUME PROFILE - High volume nodes - POC, Value Area
    - VOLUME SPIKES - Institutional participation
    - LIQUIDITY POOLS - Above/below current price
    - DELTA DIVERGENCE - Volume vs price divergence
    - IMBALANCE VOLUME - Absence of opposing orders

    //+------------------------------------------------------------------+
    //|                     VolumeProfile.mqh                         |
    //|                  
    // 1. Volume-at-price data collection
    // 2. Histogram construction
    // 3. Statistical calculations                   |
    //+------------------------------------------------------------------+
    - VolumeProfile.mqh - High volume nodes - POC, Value Area
            struct VolumeProfileData {
                double poc;              // Point of Control (highest volume)
                double valueAreaHigh;    // 70% volume area high
                double valueAreaLow;     // 70% volume area low
                double volumeNodes[20];  // Top volume nodes
                double totalVolume;
            };
            VolumeProfileData CalculateVolumeProfile(string symbol, 
                                                   ENUM_TIMEFRAMES tf, 
                                                   int lookback=100) {
                // Steps:
                // 1. Collect volume at each price level
                // 2. Create histogram of volume distribution
                // 3. Find POC (peak volume)
                // 4. Calculate Value Area (70% of total volume around POC)
                // 5. Identify volume nodes (clusters > average)
            }
    //+------------------------------------------------------------------+
    //|                     VolumeSpike.mqh                         |
    //|                  
    // 1. Volume moving average calculation
    // 2. Spike threshold definition
    // 3. Anomaly detection                   |
    //+------------------------------------------------------------------+
    - VolumeSpike.mqh - Institutional participation
            bool DetectVolumeSpike(string symbol, ENUM_TIMEFRAMES tf, 
                                 double thresholdMultiplier=2.5) {
                // Calculate:
                // 1. Current volume
                // 2. Volume MA (20 period typical)
                // 3. Volume standard deviation
                // 4. Spike if: volume > MA + (stdDev * thresholdMultiplier)
                // 5. Additional: Check for news events at same time
            }
    //+------------------------------------------------------------------+
    //|                     LiquidityPool.mqh                         |
    //|                  
    // 1. Recent swing point identification
    // 2. Round number detection
    // 3. Volume cluster analysis
    // 4. Option open interest data (if available)                    |
    //+------------------------------------------------------------------+
    - LiquidityPool.mqh - Above/below current price
            struct LiquidityPool {
                double priceLevel;
                ENUM_POOL_TYPE type;     // Swing, RoundNumber, OptionsStrike
                double expectedSize;     // Estimated liquidity
                datetime formedTime;
                bool isAboveCurrent;
                double distanceFromPrice; // Pips from current price
            };
            LiquidityPool FindNearestLiquidityPool(string symbol, 
                                                  bool abovePrice=true) {
                // Look for:
                // 1. Recent swing highs/lows (stop loss clusters)
                // 2. Round numbers (psychological levels)
                // 3. High volume nodes from volume profile
                // 4. Option strike prices (if data available)
                // 5. Previous support/resistance that broke
            }
    //+------------------------------------------------------------------+
    //|                     DeltaDivergence.mqh                         |
    //|                  
    // 1. Bid/Ask volume data (tick data)
    // 2. Delta calculation: Delta = Ask Volume - Bid Volume
    // 3. Price momentum indicator                   |
    //+------------------------------------------------------------------+
    - DeltaDivergence.mqh - Volume vs price divergence
            bool HasDeltaDivergence(string symbol) {
                // Types of divergence:
                // 1. Regular Bearish: Price ↑, Delta ↓
                // 2. Regular Bullish: Price ↓, Delta ↑
                // 3. Hidden Bearish: Price ↓, Delta ↑↑ (strong selling)
                // 4. Hidden Bullish: Price ↑, Delta ↓↓ (strong buying)
                
                // Implementation requires:
                // - Tick data processor
                // - Delta histogram
                // - Price momentum calculation
            }
    //+------------------------------------------------------------------+
    //|                     VolumeImbalance.mqh                         |
    //|                  
    // 1. Order book data (Level 2)
    // 2. Market depth analysis
    // 3. Volume-at-price analysis                    |
    //+------------------------------------------------------------------+
    - VolumeImbalance.mqh - Absence of opposing orders
            struct VolumeImbalance {
                double priceLevel;
                double bidVolume;
                double askVolume;
                double imbalanceRatio; // askVolume / bidVolume
            };

            VolumeImbalance FindImbalances(string symbol) {
                // Look for:
                // 1. Large bid/ask stacks with little opposition
                // 2. Order book gaps
                // 3. High volume at price with low opposite volume
            }


//+------------------------------------------------------------------+
//|                     MTFConfirmation.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
MTFConfirmation.mqh :
    - MTF TREND DIRECTION - All TFs pointing same way
    - MTF SUPPLY/DEMAND CONFLUENCE - Zones align across TFs
    - SWING FAILURE PATTERNS - Failed breaks on higher TF
    - MTF_ALIGNMENT
    
    //+------------------------------------------------------------------+
    //|                     MTFDetector.mqh                         |
    //|                  
    // 1. Multi-timeframe price data
    // 2. S/R detection on higher TFs
    // 3. Alignment validation                    |
    //+------------------------------------------------------------------+
    - MTFDetector.mqh  - All TFs pointing same way
            bool IsAlignedWithHigherTFSR(string symbol, 
                                        ENUM_TIMEFRAMES currentTF,
                                        double currentLevel) {
                // Check higher TFs (2-3 levels up):
                // 1. H1 S/R for M5 trade
                // 2. H4 S/R for H1 trade
                // 3. D1 S/R for H4 trade
                // Alignment if: currentLevel within X pips of higher TF level
            }
    //+------------------------------------------------------------------+
    //|                     MTFSSDDConfluence.mqh                         |
    //|                  
    // 1. Trend detection on multiple timeframes
    // 2. Direction consistency check
    // 3. Strength measurement                    |
    //+------------------------------------------------------------------+
    - MTFSSDDConfluence.mqh    - Zones align across TFs
            enum TREND_ALIGNMENT {
                ALIGNED_BULLISH,      // All TFs bullish
                ALIGNED_BEARISH,      // All TFs bearish
                MIXED,                // TFs conflicting
                RANGING               // Most TFs neutral
            };
            TREND_ALIGNMENT GetMTFTrendAlignment(string symbol, 
                                               ENUM_TIMEFRAMES entryTF) {
                // Check 3-4 timeframes (e.g., M15, H1, H4, D1)
                // Use: MA slopes, market structure, ADX > 25
                // Score each TF: +1 bullish, -1 bearish, 0 neutral
                // Alignment based on sum of scores
            }
    //+------------------------------------------------------------------+
    //|                     SwingFailurePattern.mqh                         |
    //|                  
    // 1. Supply/Demand zone detection on multiple TFs
    // 2. Zone overlap analysis
    // 3. Confluence scoring                    |
    //+------------------------------------------------------------------+
    - SwingFailurePattern.mqh - Failed breaks on higher TF
            struct MTFZoneConfluence {
                double confluenceZoneHigh;
                double confluenceZoneLow;
                int numberOfTFsAligned;  // How many TFs have zone here
                double totalStrength;    // Sum of zone strengths
                ENUM_TIMEFRAMES dominantTF; // Strongest zone TF
            };
            MTFZoneConfluence FindMTFZoneConfluence(string symbol) {
                // Look for zones that overlap across:
                // 1. Entry TF (e.g., M15)
                // 2. Intermediate TF (e.g., H1)
                // 3. Higher TF (e.g., H4)
                // Confluence if zones overlap within X% of ATR
            }



//+------------------------------------------------------------------+
//|                     MarketContext.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
MarketContext.mqh :
    - SESSION CONFLUENCE - London/New York overlap alignment
    - ECONOMIC EVENT AWARENESS - Trading around/avoiding news
    - MARKET SENTIMENT - Risk-on/risk-off environment match
    - CORRELATION CONFIRMATION - Related pairs confirming move
    - SEASONALITY PATTERNS - Time-of-day, day-of-week tendencies
    
    //+------------------------------------------------------------------+
    //|                     Session.mqh                         |
    //|                  
    // 1. Session time definitions
    // 2. Current time detection
    // 3. Volatility pattern matching                    |
    //+------------------------------------------------------------------+
    - Session.mqh - London/New York overlap alignment
            bool IsInHighConfluenceSession() {
                // Major sessions:
                // 1. Asian: 00:00-09:00 GMT
                // 2. London: 08:00-17:00 GMT
                // 3. New York: 13:00-22:00 GMT
                // 4. London/NY Overlap: 13:00-17:00 GMT (highest confluence)
                
                // Check: Is current time in overlap period?
                // Additional: Day of week effects (avoid Friday late session)
            }
    //+------------------------------------------------------------------+
    //|                     EconomicEvents.mqh                         |
    //|                  
    // 1. Economic calendar integration
    // 2. Impact rating system
    // 3. Pre/post news volatility analysis                    |
    //+------------------------------------------------------------------+
    - EconomicEvents.mqh - Trading around/avoiding news
            struct EconomicEvent {
                string eventName;
                datetime eventTime;
                ENUM_EVENT_IMPACT impact; // Low, Medium, High
                string currency;
                double previousValue;
                double forecastValue;
            };
            bool ShouldAvoidTrading(string symbol, int minutesBefore=60, 
                                  int minutesAfter=30) {
                // Check for high impact news:
                // 1. NFP, CPI, Interest Rate decisions
                // 2. Central bank speeches
                // 3. Major geopolitical events
                // Avoid if: High impact event within time window
            }
    //+------------------------------------------------------------------+
    //|                     MarketSentiment.mqh                         |
    //|                  
    // 1. Safe-haven vs risk asset correlation
    // 2. Volatility index (VIX) monitoring
    // 3. Cross-market analysis                    |
    //+------------------------------------------------------------------+
    - MarketSentiment.mqh - Risk-on/risk-off environment match
            enum MARKET_SENTIMENT {
                SENTIMENT_RISK_ON,    // Stocks ↑, Gold ↓, JPY ↓
                SENTIMENT_RISK_OFF,   // Stocks ↓, Gold ↑, JPY ↑
                SENTIMENT_NEUTRAL,    // Mixed signals
                SENTIMENT_EXTREME     // Panic/greed extremes
            };
            MARKET_SENTIMENT GetMarketSentiment() {
                // Indicators:
                // 1. S&P 500 direction
                // 2. USD/JPY direction (risk proxy)
                // 3. Gold price direction
                // 4. Bond yields
                // 5. VIX level
            }
    //+------------------------------------------------------------------+
    //|                     Corelation.mqh                         |
    //|                  
    // 1. Correlation matrix of multiple pairs
    // 2. Real-time price movement comparison
    // 3. Statistical correlation calculation                    |
    //+------------------------------------------------------------------+
    - Corelation.mqh - Related pairs confirming move
            struct CorrelationData {
                string pair1;
                string pair2;
                double correlation; // -1 to +1
                int timeframe; // M1, M5, M15, etc
                datetime lastUpdate;
            };
            double CalculateCorrelation(string pair1, string pair2, int periods=50) {
                // Pearson correlation formula:
                // ρ = Σ[(xi - x̄)(yi - ȳ)] / √[Σ(xi - x̄)² * Σ(yi - ȳ)²]
                
                // Implementation:
                // 1. Get price arrays for both pairs
                // 2. Calculate returns
                // 3. Apply correlation formula
                // 4. Return correlation coefficient
            }
    //+------------------------------------------------------------------+
    //|                     SeasonalPatterns.mqh                         |
    //|                  
    // 1. Historical time-based analysis
    // 2. Statistical significance testing
    // 3. Pattern database                    |
    //+------------------------------------------------------------------+
    - SeasonalPatterns.mqh - Time-of-day, day-of-week tendencies
            struct SeasonalityPattern {
                int hourOfDay;        // 0-23
                int dayOfWeek;        // 1-5 (Mon-Fri)
                double successRate;   // Historical win rate
                double averageMove;   // Typical pip movement
                int sampleSize;       // Number of occurrences
            };
            SeasonalityPattern GetCurrentSeasonality(string symbol) {
                // Analyze:
                // 1. Best/worst trading hours for pair
                // 2. Day of week effects (e.g., Monday gaps)
                // 3. Month/quarter patterns
                // 4. Holiday effects
            }



//+------------------------------------------------------------------+
//|                     RR.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
RR.mqh :
    - RISK-REWARD RATIO > 1:2 - Favorable asymmetry
    - POSITION SIZING CONFIDENCE - Proper risk % per trade
    - ENTRY PRECISION - Tight stop loss placement
    - BREAKEVEN SCALING - Ability to move SL to breakeven quickly
    - PARTIAL PROFIT TAKING ZONES - Clear exit points
    
    //+------------------------------------------------------------------+
    //|                     FavourableAssymetry.mqh                         |
    //|                  
            // 1. Stop loss calculation
            // 2. Take profit calculation
            // 3. Ratio validation                    |
    //+------------------------------------------------------------------+
    - FavourableAssymetry.mqh > 1:2 - Favorable asymmetry
            double CalculateRiskRewardRatio(string symbol, 
                                          double entryPrice,
                                          double stopLoss,
                                          double takeProfit) {
                // Formula:
                // Risk = |Entry - StopLoss|
                // Reward = |TakeProfit - Entry|
                // R:R = Reward / Risk
                
                // Additional: Adjust for win rate expectancy:
                // Required R:R = (1 - WinRate) / WinRate
            }
    //+------------------------------------------------------------------+
    //|                     PositionConfidence.mqh                         |
    //|                  
            // 1. Account equity/balance
            // 2. Risk percentage per trade
            // 3. Lot size calculation
            // 4. Margin requirement                    |
    //+------------------------------------------------------------------+
    - PositionConfidence.mqh - Proper risk % per trade
            double CalculateOptimalPositionSize(string symbol,
                                              double entryPrice,
                                              double stopLoss,
                                              double riskPercent=1.0) {
                // Formula:
                // RiskAmount = AccountBalance * (riskPercent/100)
                // PipValue = (0.0001 / CurrentPrice) * LotSize
                // PipDistance = |Entry - StopLoss| in pips
                // LotSize = RiskAmount / (PipDistance * PipValue)
                
                // Constraints:
                // - Minimum/maximum lot size
                // - Margin requirements
                // - Portfolio exposure limits
            }
    //+------------------------------------------------------------------+
    //|                     EntryPrecision.mqh                         |
    //|                  
            // 1. Key level identification
            // 2. Market noise measurement (ATR)
            // 3. Stop placement just beyond structure                    |
    //+------------------------------------------------------------------+
    - EntryPrecision.mqh - Tight stop loss placement
            double CalculateOptimalStopDistance(string symbol,
                                              ENUM_TIMEFRAMES tf,
                                              bool isBuy) {
                // Options:
                // 1. Recent swing low/high + buffer
                // 2. ATR multiple (1.5-2x ATR)
                // 3. Support/resistance break level
                // 4. Volatility-adjusted distance
                
                // Goal: Stop beyond market noise but within risk limits
            }
    //+------------------------------------------------------------------+
    //|                     BreakevenScaling.mqh                         |
    //|                  
            // 1. Profit threshold detection
            // 2. Stop movement rules
            // 3. Risk-free level calculation                    |
    //+------------------------------------------------------------------+
    - BreakevenScaling.mqh - Ability to move SL to breakeven quickly
            bool ShouldMoveToBreakeven(ulong ticket, 
                                     double profitThreshold=1.0) {
                // Conditions:
                // 1. Profit reaches X times risk (e.g., 1R profit)
                // 2. Price reaches key technical level
                // 3. Time-based condition (e.g., after N bars)
                // 4. Volatility allows safe breakeven move
            }
    //+------------------------------------------------------------------+
    //|                     ProfitTaking.mqh                         |
    //|                  
            // 1. Multiple TP level identification
            // 2. Risk-adjusted position sizing for each TP
            // 3. Trailing stop integration                    |
    //+------------------------------------------------------------------+
    - TakeProfit.mqh - Clear exit points
            struct ProfitTarget {
                double priceLevel;
                double percentageOfPosition; // % to close
                string reason;               // S/R, Fib, etc.
                bool moveStopToBreakeven;    // After hitting
            };
            
            ProfitTarget[] DefineProfitTargets(string symbol,
                                             bool isBuy,
                                             double entryPrice,
                                             double stopLoss) {
                // Common levels:
                // 1. 1:1 R:R (close 25-33%)
                // 2. Next S/R level (close another 25-33%)
                // 3. Extended target with trailing stop (remainder)
            }


//+------------------------------------------------------------------+
//|                     TradeManager.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
TradeManager.mqh:
    - CLEAR STOP LOSS LEVEL - Obvious invalidation point
    - MULTIPLE TAKE PROFIT LEVELS - Scaling out plan
    - TRAILING STOP METHOD - Profit protection strategy
    - HEDGING CAPABILITY - Can protect if wrong
    - ADD-ON CONFIRMATION LEVELS - Where to pyramid
    
    //+------------------------------------------------------------------+
    //|                     StopLoss.mqh                         |
    //|                  
    // 1. Market structure invalidation points
    // 2. Technical level breaks
    // 3. Price action confirmation                    |
    //+------------------------------------------------------------------+
    - StopLoss.mqh - Obvious invalidation point
            double DefineStopLossLevel(string symbol,
                                     bool isBuy,
                                     double entryPrice) {
                // Options:
                // 1. Beyond recent swing point
                // 2. Beyond supply/demand zone
                // 3. Beyond key moving average
                // 4. Beyond volatility band (Bollinger, Keltner)
                
                // Must be: Clear, logical, beyond market noise
            }
    //+------------------------------------------------------------------+
    //|                     TakeProfit.mqh                         |
    //|                  
    // 1. Profit target hierarchy
    // 2. Position splitting logic
    // 3. Exit timing rules                   |
    //+------------------------------------------------------------------+
    - TakeProfit.mqh - Scaling out plan
            void ExecuteScaledExit(ulong ticket,
                                 double currentPrice,
                                 ProfitTarget &targets[]) {
                // Implementation:
                // 1. Monitor price vs target levels
                // 2. Execute partial closes at each target
                // 3. Adjust stop loss for remaining position
                // 4. Trail stop on final portion
            }
    //+------------------------------------------------------------------+
    //|                     TrailingSL.mqh                         |
    //|                  
    // 1. Trail activation condition
    // 2. Trail distance calculation
    // 3. Update frequency rules                    |
    //+------------------------------------------------------------------+
    - TrailingSL.mqh - Profit protection strategy
            enum TRAIL_TYPE {
                TRAIL_FIXED_PIPS,      // Fixed distance
                TRAIL_ATR_MULTIPLE,    // ATR-based
                TRAIL_SWING_POINTS,    // Recent swings
                TRAIL_PARABOLIC        // SAR-style
            };
            
            double CalculateTrailingStop(ulong ticket,
                                       TRAIL_TYPE trailType,
                                       double activationProfit=1.5) {
                // Only activate after X profit
                // Update when new extreme reached
                // Never move stop against position
            }
    //+------------------------------------------------------------------+
    //|                     Hedging.mqh                         |
    //|                  
    // 1. Correlation analysis for hedge pairs
    // 2. Hedge ratio calculation
    // 3. Hedge timing rules                    |
    //+------------------------------------------------------------------+
    - Hedging.mqh  - Can protect if wrong
            bool ShouldHedgePosition(string symbol,
                                   bool originalIsBuy,
                                   double unrealizedLoss) {
                // Conditions for hedging:
                // 1. Loss exceeds threshold (e.g., 2R loss)
                // 2. Market conditions changed
                // 3. Strong counter-signal appears
                // 4. Option: Use correlated pair in opposite direction
            }
    //+------------------------------------------------------------------+
    //|                     ConfirmationLevels.mqh                         |
    //|                  
    // 1. Addition zone identification
    // 2. Risk-adjusted addition sizing
    // 3. Maximum position limit                    |
    //+------------------------------------------------------------------+
    - ConfirmationLevels.mqh - Where to pyramid
            struct AddOnLevel {
                double priceLevel;
                double additionSize;  // % of original
                string confirmation;  // What confirms addition
                double newStopLoss;   // Updated SL for all positions
            };
            
            AddOnLevel DefineAddOnLevels(string symbol,
                                       bool isBuy,
                                       double originalEntry,
                                       double originalSL) {
                // Common add-on points:
                // 1. Retest of breakout level
                // 2. Pullback to moving average
                // 3. Minor S/R within trend
                // 4. After partial profit taken
            }


//+------------------------------------------------------------------+
//|                     PattenRecognition.mqh                        |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
PattenRecognition.mqh:
    - PRICE ACTION PATTERNS - Pin bars, engulfing, inside bars
    - CHARTPATTERN COMPLETION - Triangles, flags, H&S completion
    - FIBONACCI CONFLUENCE - Multiple fib levels aligning
    - SUPPORT BECOMES RESISTANCE or vice versa - Role reversal
    - ROUND NUMBER REACTIONS - Psychological levels
    - POINT_OF_INTEREST
    
    //+------------------------------------------------------------------+
    //|                     PriceAction.mqh                         |
    //|                  
            // 1. Candle pattern detection algorithms
            // 2. Pattern confirmation rules
            // 3. Location context analysis                   |
    //+------------------------------------------------------------------+
    - PriceAction.mqh  - Pin bars, engulfing, inside bars
            enum CANDLE_PATTERN {
                PATTERN_PINBAR,
                PATTERN_ENGULFING,
                PATTERN_INSIDEBAR,
                PATTERN_OUTSIDEBAR,
                PATTERN_DOJI,
                PATTERN_MORNING_STAR,
                PATTERN_EVENING_STAR,
                PATTERN_HAMMER,
                PATTERN_SHOOTING_STAR
            };
            
            CANDLE_PATTERN DetectCandlePattern(int shift=1) {
                // Analyze:
                // 1. Candle body size vs wicks
                // 2. Previous candle relationship
                // 3. Location relative to S/R
                // 4. Volume confirmation
            }
    //+------------------------------------------------------------------+
    //|                     ChartPatterns.mqh                         |
    //|                  
            // 1. Pattern geometry detection
            // 2. Breakout point identification
            // 3. Measured move calculation                    |
    //+------------------------------------------------------------------+
    - ChartPatterns.mqh - Triangles, flags, H&S completion
            struct ChartPattern {
                ENUM_PATTERN_TYPE type; // Triangle, Flag, H&S, etc.
                double breakoutLevel;
                double measuredMoveTarget;
                double patternHeight;
                int completionPercent; // 0-100%
            };
            
            ChartPattern DetectChartPattern(string symbol,
                                          ENUM_TIMEFRAMES tf) {
                // Common patterns:
                // 1. Triangles (ascending, descending, symmetrical)
                // 2. Flags/Pennants
                // 3. Head & Shoulders
                // 4. Double Tops/Bottoms
                // 5. Wedges
            }
    //+------------------------------------------------------------------+
    //|                     Fib.mqh                         |
    //|                  
            // 1. Swing point identification for fib drawing
            // 2. Multiple fib retracement/extension calculations
            // 3. Confluence zone identification                  |
    //+------------------------------------------------------------------+
    - Fib.mqh - Multiple fib levels aligning
            struct FibonacciConfluence {
                double priceLevel;
                int confluenceScore; // Number of fib levels aligned
                double zoneHigh;
                double zoneLow;
                string fibTypes[];   // Which fibs align (e.g., ["0.618", "1.272"])
            };
            
            FibonacciConfluence FindFibConfluence(string symbol,
                                                double swingHigh,
                                                double swingLow) {
                // Check confluence of:
                // 1. Main retracements (0.382, 0.5, 0.618, 0.786)
                // 2. Extensions (1.272, 1.618, 2.0, 2.618)
                // 3. Multiple swing point projections
                // Confluence if 2+ fib levels within X pips
            }
    //+------------------------------------------------------------------+
    //|                     SSTurnDD.mqh                         |
    //|                  
            // 1. Previous S/R level tracking
            // 2. Break and retest detection
            // 3. Role change confirmation                    |
    //+------------------------------------------------------------------+
    - SSTurnDD.mqh or vice versa - Role reversal
            bool DetectRoleReversal(string symbol,
                                  double level,
                                  bool wasSupport) {
                // Conditions:
                // 1. Price breaks through level
                // 2. Retests from other side
                // 3. Rejects at former level
                // 4. New role confirmed by price action
            }
    //+------------------------------------------------------------------+
    //|                     RoundNumberReactons.mqh                         |
    //|                  
            // 1. Round number detection (e.g., 1.1000, 1.1050)
            // 2. Reaction strength measurement
            // 3. Historical significance analysis                    |
    //+------------------------------------------------------------------+
    - RoundNumberReactons.mqh - Psychological levels
            struct RoundNumberLevel {
                double priceLevel;
                int decimalPlaces; // e.g., 4 for 1.1000, 2 for 110.00
                double reactionStrength; // How strongly price reacts
                int touchCount;    // Historical touches
            };
            
            RoundNumberLevel FindNearestRoundNumber(string symbol,
                                                  double currentPrice,
                                                  int decimalPlaces=4) {
                // Calculate nearest round number
                // Check historical reactions
                // Consider current market context
            }


//+------------------------------------------------------------------+
//|                     Momentum.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
Momentum.mqh  :
    - STRONG MOMENTUM CANDLES - Large-bodied, minimal wicks
    - FOLLOW-THROUGH - Next candle confirms move
    - ABSENCE OF CHOPPINESS - Clean, directional movement
    - VELOCITY ACCELERATION - Increasing momentum
    - IMPULSE VS CORRECTION - Trading in impulse direction
    - FAIR_VALUE_GAP
    
    //+------------------------------------------------------------------+
    //|                     PriceAction.mqh                         |
    //|                  
            // 1. Candle body size calculation
            // 2. Wick-to-body ratio
            // 3. Volume confirmation                    |
    //+------------------------------------------------------------------+
    - PriceAction.mqh  - Large-bodied, minimal wicks
            bool IsMomentumCandle(int shift=0,
                                double minBodyRatio=0.7,
                                double maxWickRatio=0.2) {
                // Conditions:
                // 1. Body > (High-Low) * minBodyRatio
                // 2. Wicks < (High-Low) * maxWickRatio
                // 3. Above average volume
                // 4. Closes near extreme
            }
    //+------------------------------------------------------------------+
    //|                     CRT.mqh                         |
    //|                  
            // 1. Direction consistency check
            // 2. Momentum continuation analysis
            // 3. Volume persistence                    |
    //+------------------------------------------------------------------+
    - CRT.mqh - Next candle confirms move
            bool HasFollowThrough(int startShift,
                                int barsToCheck=3,
                                double minContinuation=0.5) {
                // Check next N bars after signal:
                // 1. Continue in same direction
                // 2. Maintain momentum (similar body sizes)
                // 3. Volume remains elevated
                // 4. No strong counter candles
                // 4. Candle-by-candle price action / tape-reading style analysis
            }
    //+------------------------------------------------------------------+
    //|                     Range.mqh                         |
    //|                  
            // 1. Choppiness index calculation
            // 2. Range vs trend analysis
            // 3. Clean move identification                   |
    //+------------------------------------------------------------------+
    - Range.mqh - Clean, directional movement
            double CalculateChoppinessIndex(string symbol,
                                          ENUM_TIMEFRAMES tf,
                                          int periods=14) {
                // Formula: 
                // CI = 100 * log10(ATR(1) / ATR(periods)) / log10(periods)
                // Low CI (< 38.2) = trending
                // High CI (> 61.8) = choppy
            }
    //+------------------------------------------------------------------+
    //|                     VelocityAcceleration.mqh                         |
    //|                 
            // 1. Momentum rate of change
            // 2. Acceleration calculation
            // 3. Trend strength measurement                    |
    //+------------------------------------------------------------------+
    - VelocityAcceleration.mqh - Increasing momentum
            bool IsAccelerating(string symbol,
                              bool isBuy,
                              int lookback=5) {
                // Check:
                // 1. Increasing candle body sizes
                // 2. Steeper moving average slopes
                // 3. Momentum indicators accelerating (RSI, MACD)
                // 4. Volume increasing with price
            }
    //+------------------------------------------------------------------+
    //|                     ImpulseAndCorrection.mqh                         |
    //|                  
            // 1. Elliott Wave or market structure analysis
            // 2. Impulse move characteristics
            // 3. Correction identification                   |
    //+------------------------------------------------------------------+
    - ImpulseAndCorrection.mqh - Trading in impulse direction
            bool IsInImpulsePhase(string symbol,
                                ENUM_TIMEFRAMES tf) {
                // Impulse characteristics:
                // 1. 5-wave structure
                // 2. Strong momentum candles
                // 3. High volume
                // 4. Breaks of structure
                
                // Correction characteristics:
                // 1. 3-wave structure (ABC)
                // 2. Overlapping price action
                // 3. Lower volume
                // 4. Respects structure
            }


//+------------------------------------------------------------------+
//|                     ConfluenceDensity.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
ConfluenceDensity.mqh :
    - 3+ CONFLUENCE FACTORS - More factors = higher probability
    - QUALITY OVER QUANTITY - Strong confluence beats many weak factors
    - HIERARCHICAL ALIGNMENT - Major factors align before minor ones
    - NO CONTRADICTING SIGNALS - Absence of conflicting evidence

//+------------------------------------------------------------------+
//|                     AdvancedConcepts.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
AdvancedConcepts.mqh :
    - SMART MONEY CONCEPT ALIGNMENT - Following institutional flow
    - OPTIONS FLOW DATA - Large options positioning
    - COMMITMENT OF TRADERS DATA - Commercial vs retail positioning
    - VOLATILITY REGIME MATCH - Strategy matches current volatility
    - SPREAD ANALYSIS - Tight spreads indicating liquidity
    
    //+------------------------------------------------------------------+
    //|                     SMT.mqh                         |
    //|                  
            // 1. Order flow analysis
            // 2. Large trade detection
            // 3. Institutional pattern recognition                    |
    //+------------------------------------------------------------------+
    - SMT.mqh - Following institutional flow
            bool IsSmartMoneyBuying(string symbol) {
                // Signs of smart money accumulation:
                // 1. Large volume at lows without price drop
                // 2. Absorption of selling pressure
                // 3. Hidden divergence (price down, delta up)
                // 4. Order book stacking (large bids supporting price)
            }
    //+------------------------------------------------------------------+
    //|                     OptionsFlowData.mqh                         |
    //|                  
            // 1. Options data feed integration
            // 2. Large/unusual options flow detection
            // 3. Gamma exposure calculation                    |
    //+------------------------------------------------------------------+
    - OptionsFlowData.mqh - Large options positioning
            struct OptionsFlow {
                double strikePrice;
                int contractSize;
                bool isCall;
                bool isBuy; // Buying or selling options
                datetime expiration;
                double openInterest;
            };
            OptionsFlow[] GetSignificantOptionsFlow(string symbol) {
                // Look for:
                // 1. Large block trades
                // 2. Unusual volume spikes
                // 3. Sweeps (buying across multiple strikes)
                // 4. High open interest levels
            }
    //+------------------------------------------------------------------+
    //|                     TraderCommitmentData.mqh                         |
    //|                  
            // 1. COT report data integration
            // 2. Commercial vs non-commercial analysis
            // 3. Positioning extremes detection                    |
    //+------------------------------------------------------------------+
    - TraderCommitmentData.mqh - Commercial vs retail positioning
            struct COTData {
                long commercialLong;
                long commercialShort;
                long nonCommercialLong;
                long nonCommercialShort;
                long nonReportableLong; // Retail
                long nonReportableShort; // Retail
                double netPosition;
                datetime reportDate;
            };
            COTData GetLatestCOTData(string symbol) {
                // Analyze:
                // 1. Commercial positioning (smart money)
                // 2. Non-commercial (hedge funds)
                // 3. Retail positioning (usually wrong at extremes)
                // 4. Net position changes week-over-week
            }
    //+------------------------------------------------------------------+
    //|                     Volatility.mqh                         |
    //|                  
            // 1. ATR (Average True Range) calculation
            // 2. Volatility classification
            // 3. Regime detection algorithm                   |
    //+------------------------------------------------------------------+
    - Volatility.mqh - Strategy matches current volatility
            enum VOLATILITY_REGIME {
                REGIME_LOW_VOL,      // ATR < 20% of average
                REGIME_NORMAL_VOL,   // ATR 20-80% of average
                REGIME_HIGH_VOL,     // ATR > 80% of average
                REGIME_EXTREME_VOL   // ATR > 120% of average
            };
            VOLATILITY_REGIME DetectVolatilityRegime(string symbol, ENUM_TIMEFRAMES tf) {
                // Calculate:
                // 1. Current ATR (14 period)
                // 2. Historical ATR average (100 period)
                // 3. Current/Historical ratio
                // 4. Classify based on ratio
            }
    //+------------------------------------------------------------------+
    //|                     spreadAnalysis.mqh                         |
    //|                 
            // 1. Bid-ask spread monitoring
            // 2. Spread historical analysis
            // 3. Liquidity condition assessment                   |
    //+------------------------------------------------------------------+
    - spreadAnalysis.mqh - Tight spreads indicating liquidity
            struct SpreadAnalysis {
                double currentSpread; // In pips
                double averageSpread; // Daily average
                double spreadPercent; // Spread as % of price
                bool isTight;         // Below threshold
                datetime worstTime;   // When spreads widen
            };
            SpreadAnalysis AnalyzeSpread(string symbol) {
                // Conditions:
                // 1. Tight spread (< 2 pips for majors) = good liquidity
                // 2. Wide spread (> 5 pips) = poor liquidity, avoid
                // 3. Spread widening during news/volatility
            }


//+------------------------------------------------------------------+
//|                     Finance.mqh                         |
//|                  Hierarchical Decision System                    |
//+------------------------------------------------------------------+
Finance.mqh :
    - EXPOSURE

    //+------------------------------------------------------------------+
    //|                     ExposureController.mqh                         |
    //|                  
            // 1. All open positions data
            // 2. Correlation matrix between positions
            // 3. Risk calculation per position
            // 4. Portfolio aggregation                   |
    //+------------------------------------------------------------------+
    - ExposureController.mqh
            class ExposureManager {
            private:
                double m_totalRisk;
                double m_maxAllowedRisk;
                double m_correlationAdjustedExposure;
                
            public:
                // Required calculations:
                double CalculateTotalExposure();                    // Sum of all position risks
                double CalculateNetExposure(string symbolGroup);   // Net directional exposure
                double CalculateCorrelationAdjustedExposure();     // Adjust for correlated positions
                double CalculateLeverageRatio();                   // Total exposure / Equity
                
                // Risk metrics needed:
                double GetValueAtRisk(double confidence=95.0);     // VaR calculation
                double GetMaximumDrawdown();                       // Worst case scenario
                double GetRiskPerSymbol(string symbol);            // Risk concentrated in one symbol
                double GetHedgingEffectiveness();                  // How well positions hedge each other
                
                // Position sizing constraints:
                bool CanOpenNewPosition(string symbol, double riskAmount);
                bool WouldExceedMaxExposure(double additionalRisk);
                double GetAvailableRiskBudget();
            };

