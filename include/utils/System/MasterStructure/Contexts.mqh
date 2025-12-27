// //+------------------------------------------------------------------+
// //|                          Contexts.mqh                            |
// //|                Context-based data chaining system                |
// //+------------------------------------------------------------------+
// #ifndef CONTEXTS_MQH
// #define CONTEXTS_MQH

// #include "DataAnalysis.mqh"
// #include "TradingInfo.mqh"
// #include "RiskIntel.mqh"
// #include "SymbolData.mqh"

// // ============ ANALYSIS CONTEXT ============
// // Pure technical analysis, NO risk or account data
// struct AnalysisContext
// {
//     // Basic identification
//     string symbol;
//     datetime analysisTime;
//     ENUM_TIMEFRAMES timeframe;
    
//     // Technical analysis data
//     MarketStructure marketStructure;
//     TrendHealth trendHealth;
//     TrendMomentum trendMomentum;
//     DivergenceSignal divergence;
    
//     // POI and swing points
//     POILevel poiLevels[20];
//     int poiCount;
//     SwingPoint swingHighs[10];
//     SwingPoint swingLows[10];
//     int swingCount;
    
//     // Current price data
//     double currentPrice;
//     double currentBid;
//     double currentAsk;
//     double currentSpread;
    
//     // Technical indicators (simplified)
//     double rsiValue;
//     double macdValue;
//     double stochValue;
//     double atrValue;
    
//     // Analysis results
//     string bias;                    // "BULLISH", "BEARISH", "NEUTRAL"
//     double confidence;              // 0-100
//     bool hasSignal;
//     string signalType;              // "BREAKOUT", "REVERSAL", "CONTINUATION"
    
//     // Constructor
//     AnalysisContext(string sym = "", ENUM_TIMEFRAMES tf = PERIOD_H1) : 
//                   symbol(sym), analysisTime(0), timeframe(tf),
//                   currentPrice(0.0), currentBid(0.0), currentAsk(0.0),
//                   currentSpread(0.0), rsiValue(0.0), macdValue(0.0),
//                   stochValue(0.0), atrValue(0.0), bias("NEUTRAL"),
//                   confidence(0.0), hasSignal(false), signalType(""),
//                   poiCount(0), swingCount(0) {}
    
//     // Initialize with symbol
//     bool Initialize(string sym, ENUM_TIMEFRAMES tf = PERIOD_H1)
//     {
//         symbol = sym;
//         timeframe = tf;
//         analysisTime = TimeCurrent();
        
//         if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
//             return false;
        
//         // Initialize structures
//         // marketStructure.Initialize(sym);
//         // trendHealth.Initialize(sym);
//         // trendMomentum.Initialize(sym);
        
//         // Get current prices
//         currentBid = SymbolInfoDouble(sym, SYMBOL_BID);
//         currentAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
//         currentPrice = (currentBid + currentAsk) / 2.0;
//         currentSpread = (currentAsk - currentBid) / SymbolInfoDouble(sym, SYMBOL_POINT);
        
//         return true;
//     }
    
//     // Perform analysis
//     void Analyze()
//     {
//         analysisTime = TimeCurrent();
        
//         // Update market structure
//         UpdateMarketStructure();
        
//         // Analyze trend
//         AnalyzeTrend();
        
//         // Look for divergence
//         FindDivergence();
        
//         // Find POI levels
//         FindPOILevels();
        
//         // Calculate overall bias
//         CalculateBias();
        
//         // Determine if we have a signal
//         DetermineSignal();
        
//         // Calculate confidence
//         CalculateConfidence();
//     }
    
//     // Update market structure (simplified)
//     void UpdateMarketStructure()
//     {
//         // This would contain actual market structure analysis logic
//         marketStructure.UpdateRange(currentPrice * 1.01, currentPrice * 0.99, 10);
//     }
    
//     // Analyze trend (simplified)
//     void AnalyzeTrend()
//     {
//         // This would contain actual trend analysis logic
//         trendHealth.Update(70.0, 30.0);
//         trendMomentum.Update(5.0, 80.0);
//     }
    
//     // Find divergence (simplified)
//     void FindDivergence()
//     {
//         // This would contain actual divergence detection logic
//         divergence.exists = false;
//     }
    
//     // Find POI levels (simplified)
//     void FindPOILevels()
//     {
//         poiCount = 0;
//         // Add some example POI levels
//         AddPOI(currentPrice * 1.02, "RESISTANCE", "H1", true);
//         AddPOI(currentPrice * 0.98, "SUPPORT", "H1", true);
//     }
    
//     // Add POI level
//     void AddPOI(double price, string type, string tf, bool major)
//     {
//         if(poiCount < 20)
//         {
//             poiLevels[poiCount].price = price;
//             poiLevels[poiCount].type = type;
//             poiLevels[poiCount].timeframe = tf;
//             poiLevels[poiCount].isMajor = major;
//             poiLevels[poiCount].timestamp = analysisTime;
//             poiCount++;
//         }
//     }
    
//     // Calculate bias
//     void CalculateBias()
//     {
//         // Simplified bias calculation
//         if(trendHealth.strength > 60 && trendMomentum.acceleration > 0)
//             bias = "BULLISH";
//         else if(trendHealth.strength > 60 && trendMomentum.acceleration < 0)
//             bias = "BEARISH";
//         else
//             bias = "NEUTRAL";
//     }
    
//     // Determine signal
//     void DetermineSignal()
//     {
//         // Simplified signal detection
//         hasSignal = trendHealth.strength > 60 && MathAbs(trendMomentum.acceleration) > 5;
        
//         if(hasSignal)
//         {
//             if(bias == "BULLISH")
//                 signalType = "CONTINUATION";
//             else if(bias == "BEARISH")
//                 signalType = "REVERSAL";
//         }
//     }
    
//     // Calculate confidence
//     void CalculateConfidence()
//     {
//         // Simplified confidence calculation
//         confidence = trendHealth.strength * 0.6 + 
//                     trendMomentum.consistency * 0.2 + 
//                     (divergence.exists ? divergence.score * 0.2 : 0);
        
//         confidence = MathMin(confidence, 100.0);
//     }
    
//     // Get nearest POI - returns reference to the POI level
//       bool GetNearestPOI(double price, POILevel &nearestPOI)
//       {
//           if(poiCount == 0) return false;
          
//           int nearestIdx = 0;
//           double minDistance = MathAbs(poiLevels[0].price - price);
          
//           for(int i = 1; i < poiCount; i++)
//           {
//               double distance = MathAbs(poiLevels[i].price - price);
//               if(distance < minDistance)
//               {
//                   minDistance = distance;
//                   nearestIdx = i;
//               }
//           }
          
//           // Copy data to output parameter
//           nearestPOI = poiLevels[nearestIdx];
//           return true;
//       }
    
//     // Get analysis summary
//     string GetSummary() const
//     {
//         string summary = StringFormat("Analysis: %s | %s | %.5f", 
//                                     symbol, EnumToString(timeframe), currentPrice);
//         summary += StringFormat("\nBias: %s | Confidence: %.1f%%", bias, confidence);
//         summary += "\nTrend: " + trendHealth.GetSummary();
//         summary += "\nMarket: " + marketStructure.GetDescription();
        
//         if(divergence.exists)
//             summary += "\nDivergence: " + divergence.GetDescription();
            
//         if(hasSignal)
//             summary += StringFormat("\nSignal: %s detected", signalType);
            
//         return summary;
//     }
// };

// // ============ TRADING CONTEXT ============
// // Adds risk and account data to analysis context
// struct TradingContext
// {
//     // Analysis results
//     AnalysisContext analysis;
    
//     // Risk data
//     RiskMetrics riskMetrics;
//     SymbolInfo symbolInfo;
    
//     // Account state
//     double accountBalance;
//     double accountEquity;
//     double freeMargin;
//     double usedMargin;
//     int totalPositions;
    
//     // Existing positions for this symbol
//     int symbolPositions;
//     double symbolExposure;
//     double symbolPnL;
    
//     // Decision parameters
//     double maxRiskPercent;
//     double maxPositionSize;
//     bool canOpenNewTrades;
//     bool canAddToPositions;
    
//     // Generated decision
//     TradeDecision decision;
    
//     // Constructor
//     TradingContext() : accountBalance(0.0), accountEquity(0.0),
//                       freeMargin(0.0), usedMargin(0.0), totalPositions(0),
//                       symbolPositions(0), symbolExposure(0.0), symbolPnL(0.0),
//                       maxRiskPercent(2.0), maxPositionSize(0.01),
//                       canOpenNewTrades(true), canAddToPositions(true) {}
    
//     // Initialize with analysis context
//     bool Initialize(AnalysisContext &analContext)
//     {
//         analysis = analContext;
        
//         // Get account data
//         accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
//         accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
//         usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
//         freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
//         totalPositions = PositionsTotal();
        
//         // Initialize symbol info
//         if(!symbolInfo.Initialize(analysis.symbol))
//             return false;
            
//         symbolInfo.UpdateMarketData();
        
//         // Get positions for this symbol
//         UpdateSymbolPositions();
        
//         return true;
//     }
    
//     // Update symbol positions
//     void UpdateSymbolPositions()
//     {
//         symbolPositions = 0;
//         symbolExposure = 0.0;
//         symbolPnL = 0.0;
        
//         for(int i = 0; i < totalPositions; i++)
//         {
//             if(PositionGetSymbol(i) == analysis.symbol)
//             {
//                 symbolPositions++;
//                 symbolExposure += PositionGetDouble(POSITION_VOLUME);
//                 symbolPnL += PositionGetDouble(POSITION_PROFIT);
//             }
//         }
//     }
    
//     // Generate trade signal from analysis
//     TradeSignal GenerateSignal()
//     {
//         TradeSignal signal;
//         signal.symbol = analysis.symbol;
//         signal.generationTime = TimeCurrent();
//         signal.confidence = analysis.confidence;
        
//         // Determine signal type based on analysis
//         if(analysis.bias == "BULLISH" && analysis.confidence > 60)
//         {
//             signal.type = analysis.confidence > 80 ? SIGNAL_ULTRA_BUY : SIGNAL_STRONG_BUY;
//             signal.action = TRADE_ACTION_ENTER_BUY;
//         }
//         else if(analysis.bias == "BEARISH" && analysis.confidence > 60)
//         {
//             signal.type = analysis.confidence > 80 ? SIGNAL_ULTRA_SELL : SIGNAL_STRONG_SELL;
//             signal.action = TRADE_ACTION_ENTER_SELL;
//         }
//         else
//         {
//             signal.type = SIGNAL_NONE;
//             signal.action = TRADE_ACTION_HOLD;
//             signal.isValid = false;
//             return signal;
//         }
        
//         // Set price levels
//         signal.entryPrice = analysis.currentPrice;
//         signal.optimalEntry = analysis.currentPrice;
        
//         // Calculate stop loss based on ATR or POI
//         CalculateStopLossTakeProfit(signal);
        
//         // Validate
//         signal.Validate();
        
//         return signal;
//     }
    
//     // Calculate stop loss and take profit
//     void CalculateStopLossTakeProfit(TradeSignal &signal)
//     {
//         // Use ATR for stop distance
//         double atr = analysis.atrValue > 0 ? analysis.atrValue : 0.001;
//         double stopDistance = atr * 2.0;  // 2 ATRs
        
//         if(signal.IsBuy())
//         {
//             signal.stopLoss = signal.entryPrice - stopDistance;
//             signal.takeProfit = signal.entryPrice + (stopDistance * 2.0);  // 1:2 RR
//         }
//         else
//         {
//             signal.stopLoss = signal.entryPrice + stopDistance;
//             signal.takeProfit = signal.entryPrice - (stopDistance * 2.0);
//         }
        
//         signal.riskRewardRatio = 2.0;
//     }
    
//     // Make trading decision with risk management
//     TradeDecision MakeDecision()
//     {
//         // Generate signal from analysis
//         TradeSignal signal = GenerateSignal();
        
//         if(!signal.isValid)
//         {
//             decision.Reject("Invalid signal");
//             return decision;
//         }
        
//         // Check trading permissions
//         if(!canOpenNewTrades)
//         {
//             decision.Reject("Trading disabled");
//             return decision;
//         }
        
//         // Check symbol status
//         if(!symbolInfo.CanTrade())
//         {
//             decision.Reject("Symbol not tradable: " + symbolInfo.GetCooldownStatus());
//             return decision;
//         }
        
//         // Check exposure limits
//         if(symbolPositions >= symbolInfo.maxPositions)
//         {
//             decision.Reject("Max positions reached for symbol");
//             return decision;
//         }
        
//         // Calculate position size
//         double stopDistance = MathAbs(signal.entryPrice - signal.stopLoss);
//         double point = SymbolInfoDouble(analysis.symbol, SYMBOL_POINT);
//         double stopPips = stopDistance / (point * 10.0);
        
//         double lotSize = CalculatePositionSize(stopPips, maxRiskPercent);
        
//         // Check if lot size is valid
//         if(lotSize < symbolInfo.minVolume)
//         {
//             decision.Reject("Position size too small");
//             return decision;
//         }
        
//         if(lotSize > symbolInfo.maxVolume)
//         {
//             decision.Reject("Position size exceeds maximum");
//             return decision;
//         }
        
//         // Create decision
//         decision.decisionId = "DEC_" + IntegerToString(GetTickCount());
//         decision.decisionTime = TimeCurrent();
//         decision.signal = signal;
//         decision.accountBalance = accountBalance;
//         decision.accountEquity = accountEquity;
//         decision.freeMargin = freeMargin;
//         decision.openPositions = totalPositions;
        
//         // Approve with calculated parameters
//         decision.Approve(lotSize, maxRiskPercent, 
//                         "Auto-approved based on analysis", "RISK_MANAGER");
        
//         return decision;
//     }
    
//     // Calculate position size
//     double CalculatePositionSize(double stopPips, double riskPercent)
//     {
//         double riskAmount = accountBalance * (riskPercent / 100.0);
//         double pipValue = symbolInfo.pipValue;
        
//         if(pipValue <= 0 || stopPips <= 0) return symbolInfo.minVolume;
        
//         double lots = riskAmount / (stopPips * pipValue);
        
//         // Apply broker limits
//         lots = MathMax(lots, symbolInfo.minVolume);
//         lots = MathMin(lots, symbolInfo.maxVolume);
        
//         // Round to lot step
//         if(symbolInfo.volumeStep > 0)
//             lots = MathRound(lots / symbolInfo.volumeStep) * symbolInfo.volumeStep;
        
//         return NormalizeDouble(lots, 2);
//     }
    
//     // Get context summary
//     string GetSummary() const
//     {
//         string summary = "TRADING CONTEXT:\n";
//         summary += analysis.GetSummary();
//         summary += StringFormat("\n\nAccount: $%.2f | Margin: $%.2f (%.1f%% free)",
//                               accountBalance, usedMargin, freeMargin/accountBalance*100);
//         summary += StringFormat("\nSymbol Positions: %d | Exposure: %.3f lots | P&L: $%.2f",
//                               symbolPositions, symbolExposure, symbolPnL);
//         summary += StringFormat("\nTrading Allowed: %s | Risk Limit: %.1f%%",
//                               canOpenNewTrades ? "Yes" : "No", maxRiskPercent);
        
//         if(decision.isApproved)
//             summary += "\n\n" + decision.GetDecisionSummary();
            
//         return summary;
//     }
// };

// #endif // CONTEXTS_MQH