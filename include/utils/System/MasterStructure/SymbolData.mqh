// //+------------------------------------------------------------------+
// //|                        SymbolData.mqh                            |
// //|                  Symbol information & management                 |
// //+------------------------------------------------------------------+
// #ifndef SYMBOL_DATA_MQH
// #define SYMBOL_DATA_MQH

// // ============ SYMBOL ENUMS ============
// enum ENUM_SYMBOL_STATUS
// {
//     SYMBOL_DISABLED = 0,
//     SYMBOL_ENABLED,
//     SYMBOL_SUSPENDED,
//     SYMBOL_WATCH_ONLY,
//     SYMBOL_ERROR
// };

// enum ENUM_ASSET_CLASS
// {
//     ASSET_FOREX = 0,
//     ASSET_METALS,
//     ASSET_INDICES,
//     ASSET_COMMODITIES,
//     ASSET_CRYPTO,
//     ASSET_STOCKS,
//     ASSET_BONDS
// };

// // ============ SYMBOL INFO STRUCTURE ============
// struct SymbolInfo
// {
//     // Basic identification
//     string symbol;
//     string name;
//     ENUM_ASSET_CLASS assetClass;
//     ENUM_SYMBOL_STATUS status;
    
//     // Trading properties
//     double tickSize;
//     double lotSize;
//     double contractSize;
//     double pointValue;
//     double pipValue;
    
//     // Limits
//     double minVolume;
//     double maxVolume;
//     double volumeStep;
//     double marginRequired;
//     double marginMaintenance;
//     double maxSpreadAllowed;
    
//     // Current market data
//     double bid;
//     double ask;
//     double lastPrice;
//     double spread;
//     double dailyHigh;
//     double dailyLow;
//     double dailyRange;
//     double avgSpread;
//     double volatility;
//     datetime lastUpdate;
    
//     // Risk parameters
//     int positionCount;
//     double totalExposure;
//     double maxExposure;
//     int maxPositions;
//     double correlationFactor;
    
//     // Performance tracking
//     int totalTrades;
//     int profitableTrades;
//     double totalProfit;
//     double winRate;
//     int consecutiveWins;
//     int consecutiveLosses;
//     datetime lastTradeTime;
    
//     // Behavior profile
//     string behavior;           // "TRENDY", "RANGY", "VOLATILE"
//     int tradesTaken;
//     int tradesSkipped;
//     bool lastTradeTaken;
//     bool lastTradeProfitable;
//     string lastTradeSummary;
    
//     // Cooldown/blocking
//     bool inCooldown;
//     datetime cooldownUntil;
//     string cooldownReason;
    
//     // Allocation
//     double targetWeight;
//     double currentWeight;
//     double allocatedCapital;
//     double riskBudget;
//     int priority;              // 1-10
    
//     // Constructor
//     SymbolInfo() : symbol(""), name(""), assetClass(ASSET_FOREX),
//                   status(SYMBOL_DISABLED), tickSize(0.0), lotSize(0.0),
//                   contractSize(0.0), pointValue(0.0), pipValue(0.0),
//                   minVolume(0.0), maxVolume(0.0), volumeStep(0.0),
//                   marginRequired(0.0), marginMaintenance(0.0),
//                   maxSpreadAllowed(0.0), bid(0.0), ask(0.0),
//                   lastPrice(0.0), spread(0.0), dailyHigh(0.0),
//                   dailyLow(0.0), dailyRange(0.0), avgSpread(0.0),
//                   volatility(0.0), lastUpdate(0), positionCount(0),
//                   totalExposure(0.0), maxExposure(10.0), maxPositions(3),
//                   correlationFactor(1.0), totalTrades(0), profitableTrades(0),
//                   totalProfit(0.0), winRate(0.0), consecutiveWins(0),
//                   consecutiveLosses(0), lastTradeTime(0), behavior(""),
//                   tradesTaken(0), tradesSkipped(0), lastTradeTaken(false),
//                   lastTradeProfitable(false), lastTradeSummary(""),
//                   inCooldown(false), cooldownUntil(0), cooldownReason(""),
//                   targetWeight(0.0), currentWeight(0.0), allocatedCapital(0.0),
//                   riskBudget(0.0), priority(5) {}
    
//     // Initialize from symbol name
//     bool Initialize(string sym)
//     {
//         symbol = sym;
        
//         if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
//         {
//             status = SYMBOL_ERROR;
//             return false;
//         }
        
//         // Get symbol properties
//         name = SymbolInfoString(sym, SYMBOL_DESCRIPTION);
//         tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
//         lotSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
//         contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
        
//         minVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
//         maxVolume = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
//         volumeStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
        
//         marginRequired = SymbolInfoDouble(sym, SYMBOL_MARGIN_INITIAL);
//         marginMaintenance = SymbolInfoDouble(sym, SYMBOL_MARGIN_MAINTENANCE);
        
//         // Calculate pip value
//         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
//         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
//         pointValue = tickValue * point;
//         pipValue = pointValue * 10.0;
        
//         // Determine asset class
//         string symLower = sym;  // First copy the string
//         StringToLower(symLower); // Then convert in-place
//         if(StringFind(symLower, "xau") >= 0 || StringFind(symLower, "xag") >= 0)
//             assetClass = ASSET_METALS;
//         else if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0)
//             assetClass = ASSET_CRYPTO;
//         else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "SPX") >= 0)
//             assetClass = ASSET_INDICES;
//         else
//             assetClass = ASSET_FOREX;
        
//         status = SYMBOL_ENABLED;
//         lastUpdate = TimeCurrent();
//         return true;
//     }
    
//     // Update market data
//     void UpdateMarketData()
//     {
//         if(symbol == "") return;
        
//         bid = SymbolInfoDouble(symbol, SYMBOL_BID);
//         ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
//         lastPrice = (bid + ask) / 2.0;
//         spread = (ask - bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);
        
//         // Update daily high/low
//         MqlRates rates[];
//         ArraySetAsSeries(rates, true);
//         if(CopyRates(symbol, PERIOD_D1, 0, 1, rates) == 1)
//         {
//             dailyHigh = rates[0].high;
//             dailyLow = rates[0].low;
//             dailyRange = dailyHigh - dailyLow;
//         }
        
//         lastUpdate = TimeCurrent();
//     }
    
//     // Check if symbol can trade
//     bool CanTrade() const
//     {
//         if(status != SYMBOL_ENABLED) return false;
//         if(inCooldown && TimeCurrent() < cooldownUntil) return false;
//         if(spread > maxSpreadAllowed && maxSpreadAllowed > 0) return false;
//         if(positionCount >= maxPositions) return false;
        
//         return true;
//     }
    
//     // Check if can add position
//     bool CanAddPosition(double newExposure = 0.0) const
//     {
//         if(!CanTrade()) return false;
//         if((totalExposure + newExposure) > maxExposure) return false;
        
//         return true;
//     }
    
//     // Add exposure (called when opening position)
//     void AddExposure(double exposure)
//     {
//         positionCount++;
//         totalExposure += exposure;
//         currentWeight = (totalExposure / maxExposure) * 100.0;
//     }
    
//     // Remove exposure (called when closing position)
//     void RemoveExposure(double exposure)
//     {
//         positionCount = MathMax(0, positionCount - 1);
//         totalExposure = MathMax(0.0, totalExposure - exposure);
//         currentWeight = (totalExposure / maxExposure) * 100.0;
//     }
    
//     // Update trade result
//     void UpdateTradeResult(bool isWin, double profit)
//     {
//         totalTrades++;
        
//         if(isWin)
//         {
//             profitableTrades++;
//             consecutiveWins++;
//             consecutiveLosses = 0;
//             totalProfit += profit;
//         }
//         else
//         {
//             consecutiveLosses++;
//             consecutiveWins = 0;
//         }
        
//         winRate = (totalTrades > 0) ? (double)profitableTrades / totalTrades * 100.0 : 0.0;
//         lastTradeTime = TimeCurrent();
//         lastTradeTaken = true;
//         lastTradeProfitable = isWin;
        
//         // Apply cooldown after consecutive losses
//         if(consecutiveLosses >= 3)
//         {
//             ApplyCooldown(60, "3 consecutive losses");
//         }
//     }
    
//     // Apply cooldown
//     void ApplyCooldown(int minutes, string reason = "")
//     {
//         inCooldown = true;
//         cooldownUntil = TimeCurrent() + (minutes * 60);
//         cooldownReason = reason;
//     }
    
//     // Check cooldown status
//     string GetCooldownStatus() const
//     {
//         if(!inCooldown) return "ACTIVE";
        
//         if(TimeCurrent() >= cooldownUntil)
//         {
//             // Return status but don't modify - caller should call ClearExpiredCooldown()
//             return "COOLDOWN_EXPIRED";
//         }
        
//         int remaining = int((cooldownUntil - TimeCurrent()) / 60);
//         return StringFormat("COOLDOWN (%d min): %s", remaining, cooldownReason);
//     }
    
//     // Add a method to clear expired cooldown
//     bool ClearExpiredCooldown()
//     {
//         if(inCooldown && TimeCurrent() >= cooldownUntil)
//         {
//             inCooldown = false;
//             cooldownReason = "";
//             return true;
//         }
//         return false;
//     }
    
//     // Get exposure level
//     double GetExposurePercent() const
//     {
//         return maxExposure > 0 ? (totalExposure / maxExposure) * 100.0 : 0.0;
//     }
    
//     // Get symbol summary
//     string GetSummary() const
//     {
//         string summary = StringFormat("%s [%s]", symbol, name);
//         summary += StringFormat("\nStatus: %s | Exposure: %.1f%%/%0.f%%", 
//                               GetCooldownStatus(), GetExposurePercent(), maxExposure);
//         summary += StringFormat("\nPrice: %.5f | Spread: %.1f pips", lastPrice, spread);
//         summary += StringFormat("\nTrades: %d | Win Rate: %.1f%% | Profit: $%.2f",
//                               totalTrades, winRate, totalProfit);
        
//         return summary;
//     }
// };

// #endif // SYMBOL_DATA_MQH