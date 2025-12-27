// //+------------------------------------------------------------------+
// //|                     DashboardManager.mqh                         |
// //|                  Complete Dashboard System                       |
// //+------------------------------------------------------------------+
// #property copyright "Copyright 2024"
// #property strict

// #include "../config/inputs.mqh"
// #include "../utils/FormatUtils.mqh"
// #include "../signals/SignalScorer.mqh"
// #include "../market/trend/TrendAnalyzer.mqh"
// #include "../execution/TradeExecutor.mqh"
// #include "../utils/TradeUtils.mqh"
// #include "../market/trend/MATrends.mqh"
// #include "../utils/ResourceManager.mqh"  // Logging system

// // ============================================================
// //                     DASHBOARD MODES
// // ============================================================
// enum DASHBOARD_MODE
// {
//     MODE_FULL,      // Complete dashboard with all sections
//     MODE_COMPACT,   // Compact version for smaller displays
//     MODE_SYMBOL     // Single symbol analysis
// };

// // ============================================================
// //                     DASHBOARD ITEM STRUCTURE
// // ============================================================
// struct DashboardItem
// {
//     string label;
//     string value;
//     int line;
//     color textColor;
//     int fontSize;
//     string prefix;
//     string suffix;
// };

// // ============================================================
// //                     MAIN DASHBOARD CLASS
// // ============================================================
// class DashboardManager
// {
// private:
//     // Display Configuration
//     DashboardItem m_items[50];
//     int m_itemCount;
//     string m_eaName;
//     string m_eaVersion;
//     DASHBOARD_MODE m_currentMode;
//     int m_currentSymbolIndex;
//     bool m_initialized;
    
//     // Performance Tracking
//     datetime m_lastUpdateTime;
//     int m_updateCount;
    
//     // Display State
//     bool m_showMarketSentiment;
//     bool m_showGeneralTrend;
//     bool m_showLongTermTrend;
    
//     // Data storage (instead of references)
//     double m_dailyProfitCash;
//     double m_dailyDrawdownCash;
//     string m_activeSymbols[];
//     int m_totalSymbols;
//     double m_riskPercent;
//     double m_currentManualLotSize;
//     double m_dailyDrawdownLimitCash;
//     double m_dailyProfitLimitCash;
//     int m_dailyTradesCount;
//     int m_longTermMA_LT[];
//     string m_botConclusion;
    
//     // Data getter callbacks (for real-time data)
//     // Function pointers for getting data from SystemInitializer
//     typedef double (*GetDoubleFunc)();
//     typedef int (*GetIntFunc)();
//     typedef string (*GetStringFunc)();
    
//     GetDoubleFunc m_getDailyProfitCashFunc;
//     GetDoubleFunc m_getDailyDrawdownCashFunc;
//     GetIntFunc m_getDailyTradesCountFunc;
//     GetIntFunc m_getTotalSymbolsFunc;
    
// public:
//     // ================= CONSTRUCTOR & DESTRUCTOR =================
//     DashboardManager(string eaName = "Safe Metals EA", 
//                      string version = "4.5",
//                      bool enableLogging = true) : 
//         m_eaName(eaName),
//         m_eaVersion(version),
//         m_currentMode(MODE_FULL),
//         m_currentSymbolIndex(0),
//         m_initialized(false),
//         m_lastUpdateTime(0),
//         m_updateCount(0),
//         m_showMarketSentiment(true),
//         m_showGeneralTrend(true),
//         m_showLongTermTrend(true)
//     {
//         // Initialize references (these need to be set properly)
//         // Note: In actual implementation, these should be passed properly
//     }
    
//     ~DashboardManager()
//     {
//         Cleanup();
//     }
    
//     // ================= INITIALIZATION =================
//     void Initialize()
//     {
//         if(m_initialized)
//             return;
            
//         // Initialize logging
//         m_logger.Init("DashboardLog.csv", true, true, true);
        
//         // Create all chart objects
//         CreateDashboardObjects();
        
//         m_initialized = true;
//         m_lastUpdateTime = TimeCurrent();
        
//         m_logger.KeepNotes("GLOBAL", AUDIT, "Dashboard", "Dashboard initialized", false, false, 0.0);
//     }
    
//     // ================= MAIN UPDATE METHOD =================
//     void Update()
//     {
//         if(!m_initialized)
//             return;
            
//         string dashboardText = "";
        
//         switch(m_currentMode)
//         {
//             case MODE_FULL:
//                 dashboardText = GetFullDashboard();
//                 break;
//             case MODE_COMPACT:
//                 dashboardText = GetCompactDashboard();
//                 break;
//             case MODE_SYMBOL:
//                 if(m_currentSymbolIndex >= 0 && m_currentSymbolIndex < totalSymbols)
//                 {
//                     dashboardText = GetSymbolDashboard(activeSymbols[m_currentSymbolIndex]);
//                 }
//                 else
//                 {
//                     dashboardText = GetFullDashboard();
//                 }
//                 break;
//         }
        
//         // Update chart display
//         Comment(dashboardText);
        
//         // Update performance counters
//         m_updateCount++;
//         m_lastUpdateTime = TimeCurrent();
        
//         // Log periodic update
//         if(m_updateCount % 100 == 0)
//         {
//             m_logger.KeepNotes("GLOBAL", OBSERVE, "Dashboard", 
//                 StringFormat("Dashboard updated %d times", m_updateCount), 
//                 false, false, 0.0);
//         }
//     }
    
//     // ================= MODE CONTROL =================
//     void SetMode(DASHBOARD_MODE mode)
//     {
//         m_currentMode = mode;
//         m_logger.KeepNotes("GLOBAL", OBSERVE, "Dashboard", 
//             "Mode changed to: " + EnumToString(mode), false, false, 0.0);
//     }
    
//     void SetSymbolMode(string symbol)
//     {
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             if(activeSymbols[i] == symbol)
//             {
//                 m_currentSymbolIndex = i;
//                 m_currentMode = MODE_SYMBOL;
//                 m_logger.KeepNotes(symbol, OBSERVE, "Dashboard", 
//                     "Switched to symbol mode", false, false, 0.0);
//                 return;
//             }
//         }
        
//         // Symbol not found, revert to full mode
//         m_currentMode = MODE_FULL;
//     }
    
//     void ToggleSection(int sectionNumber)
//     {
//         switch(sectionNumber)
//         {
//             case 3: m_showMarketSentiment = !m_showMarketSentiment; break;
//             case 4: m_showGeneralTrend = !m_showGeneralTrend; break;
//             case 5: m_showLongTermTrend = !m_showLongTermTrend; break;
//         }
        
//         m_logger.KeepNotes("GLOBAL", OBSERVE, "Dashboard", 
//             StringFormat("Section %d toggled", sectionNumber), false, false, 0.0);
//     }
    
//     // ================= EMERGENCY MODE =================
//     void SetEmergency(bool emergency, string message = "")
//     {
//         color textColor = emergency ? clrRed : clrWhite;
        
//         // Update all text colors
//         for(int i = 0; i < m_itemCount; i++)
//         {
//             ObjectSetInteger(0, "db_" + m_items[i].label, OBJPROP_COLOR, textColor);
//         }
        
//         if(emergency && message != "")
//         {
//             UpdateItem("title", "!!! " + message + " !!!");
//             m_logger.KeepNotes("GLOBAL", WARN, "Dashboard", 
//                 "Emergency mode: " + message, false, false, 0.0);
//         }
//     }
    
//     // ================= CLEANUP =================
//     void Cleanup()
//     {
//         if(!m_initialized)
//             return;
            
//         // Remove all chart objects
//         for(int i = 0; i < m_itemCount; i++)
//         {
//             ObjectDelete(0, "db_" + m_items[i].label);
//         }
        
//         // Clear chart comment
//         Comment("");
        
//         m_initialized = false;
        
//         m_logger.KeepNotes("GLOBAL", AUDIT, "Dashboard", 
//             "Dashboard cleaned up", false, false, 0.0);
//     }
    
//     // ================= UTILITY METHODS =================
//     string GetCurrentTier()
//     {
//         // This should be implemented based on your logic
//         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
//         if(equity >= 10000) return "TIER 3";
//         if(equity >= 5000) return "TIER 2";
//         if(equity >= 1000) return "TIER 1";
//         return "STARTER";
//     }
    
//     void RefreshDisplay()
//     {
//         for(int i = 0; i < m_itemCount; i++)
//         {
//             RefreshItem(i);
//         }
//         ChartRedraw();
//     }
    
//     // ================= GETTERS =================
//     DASHBOARD_MODE GetCurrentMode() const { return m_currentMode; }
//     int GetUpdateCount() const { return m_updateCount; }
//     datetime GetLastUpdateTime() const { return m_lastUpdateTime; }
//     bool IsInitialized() const { return m_initialized; }
//     ResourceManager* GetLogger() { return &m_logger; }
    
//     // ================= SETTERS FOR GLOBAL REFERENCES =================
//     void SetDailyProfitCash(double value) { dailyProfitCash = value; }
//     void SetDailyDrawdownCash(double value) { dailyDrawdownCash = value; }
//     void SetTotalSymbols(int value) { totalSymbols = value; }
//     void SetRiskPercent(double value) { RiskPercent = value; }
//     void SetCurrentManualLotSize(double value) { currentManualLotSize = value; }
//     void SetDailyDrawdownLimitCash(double value) { DailyDrawdownLimitCash = value; }
//     void SetDailyProfitLimitCash(double value) { DailyProfitLimitCash = value; }
//     void SetDailyTradesCount(int value) { dailyTradesCount = value; }
//     void SetBotConclusion(string value) { botConclusion = value; }
//     void SetActiveSymbols(string &value[]) { activeSymbols = value; }
//     void SetLongTermMA_LT(int &value[]) { longTermMA_LT = value; }
    
//     // ================= DASHBOARD CONTENT GENERATORS =================
// private:
//     string GetFullDashboard()
//     {
//         string dashboard = "\n";
//         dashboard += "════════════════════════════════════════════════════\n";
//         dashboard += StringFormat("           %s v%s - TRADING MONITOR    \n", m_eaName, m_eaVersion);
//         dashboard += "════════════════════════════════════════════════════\n\n";
        
//         // 1. ACCOUNT OVERVIEW
//         dashboard += GetAccountOverview();
        
//         // 3. MARKET SENTIMENT (if enabled)
//         if(m_showMarketSentiment)
//             dashboard += GetMarketSentimentDisplay();
        
//         // 4. GENERAL SENTIMENT (if enabled)
//         if(m_showGeneralTrend)
//             dashboard += GetGeneralTrendDisplay();
        
//         // 5. LONG-TERM TREND (if enabled)
//         if(m_showLongTermTrend)
//             dashboard += GetLongTermTrendDisplay();
        
//         // 6. TRADING DECISION
//         dashboard += GetTradingDecisionsDisplay();
        
//         // Loop through all active symbols
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             dashboard += GetMAAlignmentDashboard(symbol);
            
//             if(i < totalSymbols - 1)
//                 dashboard += "\n────────────────────────────────────────────────\n\n";
//         }
        
//         return dashboard;
//     }
    
//     string GetCompactDashboard()
//     {
//         string dashboard = "";
//         dashboard += StringFormat("%s v%s\n", m_eaName, m_eaVersion);
//         dashboard += "════════════════════\n\n";
        
//         // Only show key metrics
//         dashboard += GetAccountOverview();
//         dashboard += "\n";
//         dashboard += GetTradingDecisionsDisplay();
//         dashboard += GetRiskLevelIndicator();
        
//         dashboard += StringFormat("\n⏰ %s", TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS));
        
//         return dashboard;
//     }
    
//     string GetSymbolDashboard(string symbol)
//     {
//         string dashboard = "";
//         dashboard += StringFormat("SYMBOL ANALYSIS: %s\n", symbol);
//         dashboard += "════════════════════════════\n\n";
        
//         dashboard += StringFormat("Account Equity: $%.2f\n", AccountInfoDouble(ACCOUNT_EQUITY));
//         dashboard += StringFormat("Daily P/L: $%.2f\n\n", dailyProfitCash);
        
//         // Symbol-specific information
//         dashboard += "SCORE & DIRECTION:\n";
//         dashboard += GetSingleSymbolScore(symbol);
//         dashboard += "\n";
        
//         dashboard += "MARKET SENTIMENT:\n";
//         dashboard += GetSingleSymbolSentiment(symbol);
//         dashboard += "\n";
        
//         dashboard += "GENERAL TREND:\n";
//         dashboard += GetSingleSymbolGeneralTrend(symbol);
//         dashboard += "\n";
        
//         dashboard += "LONG-TERM TREND:\n";
//         // Need to find the index for this symbol
//         int symbolIndex = -1;
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             if(activeSymbols[i] == symbol)
//             {
//                 symbolIndex = i;
//                 break;
//             }
//         }
//         dashboard += GetSingleSymbolTrend(symbol, symbolIndex);
//         dashboard += "\n";
        
//         dashboard += "TRADING DECISION:\n";
//         dashboard += GetSingleSymbolDecision(symbol);
        
//         return dashboard;
//     }
    
//     // ================= SECTION GENERATORS =================
//     string GetAccountOverview()
//     {
//         string statusText = "";
//         statusText += "1️⃣ ACCOUNT OVERVIEW:\n";
        
//         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
//         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
//         double margin = AccountInfoDouble(ACCOUNT_MARGIN);
//         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
//         double marginLevel = (margin > 0) ? (equity / margin * 100) : 0;
        
//         statusText += FormatAccountMetrics(balance, equity, margin, freeMargin, marginLevel);
//         statusText += "\n";
        
//         return statusText;
//     }
    
//     string GetRiskLevelIndicator()
//     {
//         string riskText = "\n⚠️  RISK LEVEL: ";
        
//         if(dailyDrawdownCash >= DailyDrawdownLimitCash * 0.8)
//             riskText += "HIGH (Near drawdown limit)";
//         else if(dailyDrawdownCash >= DailyDrawdownLimitCash * 0.5)
//             riskText += "MEDIUM";
//         else
//             riskText += "LOW";
        
//         return riskText;
//     }
    
//     string GetSymbolScoresDisplay()
//     {
//         string statusText = "";
//         statusText += "2️⃣ SYMBOL SCORE:\n";
        
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             statusText += GetSingleSymbolScore(symbol);
//         }
//         statusText += "\n";
        
//         return statusText;
//     }
    
//     string GetMarketSentimentDisplay()
//     {
//         string statusText = "";
//         statusText += "3️⃣ MARKET SENTIMENT:\n";
        
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             statusText += GetSingleSymbolSentiment(symbol);
//         }
//         statusText += "\n";
        
//         return statusText;
//     }
    
//     string GetGeneralTrendDisplay()
//     {
//         string statusText = "";
//         statusText += "4️⃣ TREND SENTIMENT:\n";
        
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             statusText += GetSingleSymbolGeneralTrend(symbol);
//         }
//         statusText += "\n";
        
//         return statusText;
//     }
    
//     string GetLongTermTrendDisplay()
//     {
//         string statusText = "";
//         statusText += "5️⃣ LONG-TERM TREND:\n";
        
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             statusText += GetSingleSymbolTrend(symbol, i);
//         }
//         statusText += "\n";
        
//         return statusText;
//     }
    
//     string GetTradingDecisionsDisplay()
//     {
//         string statusText = "";
//         statusText += "6️⃣ TRADING DECISION:\n";
        
//         for(int i = 0; i < totalSymbols; i++)
//         {
//             string symbol = activeSymbols[i];
//             statusText += GetSingleSymbolDecision(symbol);
//         }
        
//         return statusText;
//     }
    
//     // ================= SINGLE SYMBOL METHODS =================
//     string GetSingleSymbolScore(string symbol)
//     {
//         double directionPercent;
//         double buyScore = GetUltraSensitiveSignalScore(symbol, true);
//         double sellScore = GetUltraSensitiveSignalScore(symbol, false);
        
//         string direction = "NEUTRAL";
//         directionPercent = 0;
        
//         double difference = buyScore - sellScore;
        
//         if(MathAbs(difference) > 10)
//         {
//             if(difference > 0)
//             {
//                 directionPercent = difference;
//                 direction = "BULL";
//             }
//             else
//             {
//                 directionPercent = MathAbs(difference);
//                 direction = "BEAR";
//             }
//         }
        
//         return StringFormat("   %-7s: %-5s %3.0f%%\n", symbol, direction, directionPercent);
//     }
    
//     string GetSingleSymbolSentiment(string symbol)
//     {
//         double sentiment = CalculateMarketSentiment(symbol);
//         string sentimentText = GetSentimentText(sentiment);
        
//         return StringFormat("   %-7s: %-15s %3.0f%%\n", symbol, sentimentText, sentiment);
//     }
    
//     string GetSingleSymbolGeneralTrend(string symbol)
//     {
//         double trend = CalculateGeneralTrend(symbol);
//         string trendText = GetGeneralTrendText(trend);
        
//         return StringFormat("   %-7s: %-15s %3.0f%%\n", symbol, trendText, trend);
//     }
    
//     string GetSingleSymbolTrend(string symbol, int maHandleIndex)
//     {
//         double trend = CalculateLongTermTrend(symbol);
//         string trendText = GetTrendText(trend);
//         string maInfo = GetMAPositionInfo(symbol, maHandleIndex);
        
//         if(StringFind(maInfo, "No MA100") != -1)
//         {
//             return StringFormat("   %-7s: %-12s %3.0f%% (No MA100 data)\n", 
//                               symbol, trendText, trend);
//         }
        
//         return StringFormat("   %-7s: %-12s %3.0f%%\n", symbol, trendText, trend);
//     }
    
//     string GetSingleSymbolDecision(string symbol)
//     {
//         // Call unified executor to populate botConclusion
//         string unifiedResult = ExecuteTradeBasedOnDecision(symbol);
        
//         int openTrades = CountOpenTrades(symbol);
//         string decision = unifiedResult;
        
//         // Get bot thoughts from the global variable
//         string botThoughts = botConclusion;
        
//         int currentDirection = GetCurrentTradeDirection(symbol);
//         string positionStatus = "NO POSITIONS";
        
//         if(currentDirection == POSITION_TYPE_BUY)
//             positionStatus = StringFormat("BUY POSITIONS: %d", openTrades);
//         else if(currentDirection == POSITION_TYPE_SELL)
//             positionStatus = StringFormat("SELL POSITIONS: %d", openTrades);
        
//         // Log the decision
//         m_logger.KeepNotes(symbol, AUTHORIZE, "Dashboard", 
//             StringFormat("Decision: %s | Status: %s", decision, positionStatus),
//             false, false, 0.0);
        
//         // If positions are full, show both the action and bot's thoughts
//         if(decision == "FULL" || StringFind(decision, "FULL|") >= 0)
//         {
//             return StringFormat("   %-7s: %s | %s : %s\n", 
//                               symbol, decision, positionStatus, botThoughts);
//         }
//         else
//         {
//             return StringFormat("   %-7s: %s | %s\n", symbol, decision, positionStatus);
//         }
//     }
    
//     // ================= HELPER METHODS =================
//     double CalculateSymbolDirection(string symbol, double &outDirectionPercent)
//     {
//         double buyScore = GetUltraSensitiveSignalScore(symbol, true);
//         double sellScore = GetUltraSensitiveSignalScore(symbol, false);
        
//         double difference = buyScore - sellScore;
//         outDirectionPercent = 0;
        
//         if(MathAbs(difference) > 10)
//         {
//             outDirectionPercent = MathAbs(difference);
//         }
        
//         return difference;  // Positive = bullish, Negative = bearish
//     }
    
//     string FormatAccountMetrics(double balance, double equity, double margin, 
//                                double freeMargin, double marginLevel)
//     {
//         string formattedText = "";
        
//         formattedText += StringFormat("   Balance: $%-10.2f | Equity: $%-10.2f\n", balance, equity);
//         formattedText += StringFormat("   Free Margin: $%-7.2f | Margin Level: %5.1f%%\n", freeMargin, marginLevel);
//         formattedText += StringFormat("   Daily P/L: %s$%-8.2f | Trades Today: %d\n", 
//                                       (dailyProfitCash >= 0 ? "+" : ""), dailyProfitCash, dailyTradesCount);
//         formattedText += StringFormat("   Daily Limit: $%.2f/%d%% | Drawdown: $%.2f/%.1f%%\n",
//                                       MathMin(dailyProfitCash, DailyProfitLimitCash),
//                                       (int)((dailyProfitCash / DailyProfitLimitCash) * 100),
//                                       dailyDrawdownCash,
//                                       (dailyDrawdownCash / DailyDrawdownLimitCash) * 100);
//         formattedText += StringFormat("   Risk: %.1f%% | Lot: %.3f | Tier: %s\n",
//                                       RiskPercent, currentManualLotSize, GetCurrentTier());
        
//         return formattedText;
//     }
    
//     string GetSentimentText(double sentiment)
//     {
//         if(sentiment >= 70) return "STRONG BUY";
//         if(sentiment >= 60) return "BUY";
//         if(sentiment >= 40 && sentiment <= 60) return "NEUTRAL";
//         if(sentiment >= 30) return "SELL";
//         return "STRONG SELL";
//     }
    
//     string GetGeneralTrendText(double trend)
//     {
//         if(trend >= 75) return "STRONG BULL";
//         if(trend >= 62) return "BULL";
//         if(trend >= 38) return "NEUTRAL";
//         if(trend >= 25) return "BEAR";
//         return "STRONG BEAR";
//     }
    
//     string GetTrendText(double trend)
//     {
//         if(trend >= 70) return "STRONG BULL";
//         if(trend >= 60) return "BULLISH";
//         if(trend <= 30) return "STRONG BEAR";
//         if(trend <= 40) return "BEARISH";
//         return "NEUTRAL";
//     }
    
//     string GetMAPositionInfo(string symbol, int maHandleIndex)
//     {
//         double ma100 = 0;
        
//         if(maHandleIndex >= 0 && maHandleIndex < ArraySize(longTermMA_LT) && longTermMA_LT[maHandleIndex] != -1)
//         {
//             double maBuffer[1];
//             if(CopyBuffer(longTermMA_LT[maHandleIndex], 0, 0, 1, maBuffer) >= 1)
//             {
//                 ma100 = maBuffer[0];
//             }
//         }
        
//         if(ma100 > 0)
//         {
//             return "MA100 Available";
//         }
        
//         return "No MA100 data";
//     }
    
//     // ================= OBJECT MANAGEMENT =================
//     void CreateDashboardObjects()
//     {
//         // Define dashboard items with proper structure
//         AddItem("title", StringFormat("=== %s v%s ===", m_eaName, m_eaVersion), clrYellow, 12);
//         AddItem("time", "", clrWhite, 10);
//         AddItem("sep1", "─────────────────", clrGray, 10);
        
//         // Account section
//         AddItem("balance", "Balance: $0.00", clrWhite, 10);
//         AddItem("equity", "Equity: $0.00", clrWhite, 10);
//         AddItem("margin", "Margin: $0.00 (0.0%)", clrWhite, 10);
//         AddItem("freemargin", "Free Margin: $0.00", clrWhite, 10);
//         AddItem("marginlevel", "Margin Level: 0.0%", clrWhite, 10);
//         AddItem("sep2", "─────────────────", clrGray, 10);
        
//         // Daily performance
//         AddItem("dailypl", "Daily P/L: $0.00", clrWhite, 10);
//         AddItem("dailytrades", "Trades Today: 0", clrWhite, 10);
//         AddItem("risk", "Risk: 0.0% | Lot: 0.000", clrWhite, 10);
//         AddItem("sep3", "─────────────────", clrGray, 10);
        
//         // Symbols (up to 10 symbols)
//         for(int i = 0; i < MathMin(totalSymbols, 10); i++)
//         {
//             string symbol = activeSymbols[i];
//             AddItem("sym_" + symbol, symbol + ": N/A", clrWhite, 10);
//         }
        
//         // Status
//         AddItem("status", "Status: OK", clrLime, 10);
//         AddItem("updatecount", "Updates: 0", clrWhite, 10);
//         AddItem("memory", "Memory: 0MB", clrWhite, 10);
        
//         // Create actual chart objects
//         for(int i = 0; i < m_itemCount; i++)
//         {
//             CreateLabel("db_" + m_items[i].label, 10, 20 + i * 18, 
//                        m_items[i].prefix + m_items[i].value + m_items[i].suffix, 
//                        m_items[i].textColor, m_items[i].fontSize);
//         }
//     }
    
//     void AddItem(string label, string defaultValue = "", color clr = clrWhite, int fontSize = 10, 
//                  string prefix = "", string suffix = "")
//     {
//         if(m_itemCount >= ArraySize(m_items))
//             return;
            
//         m_items[m_itemCount].label = label;
//         m_items[m_itemCount].value = defaultValue;
//         m_items[m_itemCount].line = m_itemCount;
//         m_items[m_itemCount].textColor = clr;
//         m_items[m_itemCount].fontSize = fontSize;
//         m_items[m_itemCount].prefix = prefix;
//         m_items[m_itemCount].suffix = suffix;
//         m_itemCount++;
//     }
    
//     void UpdateItem(string label, string value)
//     {
//         for(int i = 0; i < m_itemCount; i++)
//         {
//             if(m_items[i].label == label)
//             {
//                 m_items[i].value = value;
//                 RefreshItem(i);
//                 return;
//             }
//         }
//     }
    
//     void CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 10)
//     {
//         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
//         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
//         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
//         ObjectSetString(0, name, OBJPROP_TEXT, text);
//         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
//         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
//         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
//     }
    
//     void RefreshItem(int index)
//     {
//         if(index < 0 || index >= m_itemCount)
//             return;
            
//         string displayText = m_items[index].prefix + m_items[index].value + m_items[index].suffix;
//         ObjectSetString(0, "db_" + m_items[index].label, OBJPROP_TEXT, displayText);
//     }
// };

// // ============================================================
// //             GLOBAL DASHBOARD MANAGER INSTANCE
// // ============================================================
// DashboardManager *globalDashboard = NULL;

// // Helper function to initialize the global dashboard
// void InitializeGlobalDashboard()
// {
//     if(globalDashboard == NULL)
//     {
//         globalDashboard = new DashboardManager("Safe Metals EA", "4.5", true);
        
//         // Set up references to global variables
//         // Note: You need to pass the actual global variables here
//         // Example: globalDashboard->SetDailyProfitCashRef(dailyProfitCash);
        
//         globalDashboard->Initialize();
//     }
// }

// // Helper function to update the dashboard
// void UpdateGlobalDashboard()
// {
//     if(globalDashboard != NULL)
//     {
//         globalDashboard->Update();
//     }
// }

// // Helper function to clean up
// void CleanupGlobalDashboard()
// {
//     if(globalDashboard != NULL)
//     {
//         globalDashboard->Cleanup();
//         delete globalDashboard;
//         globalDashboard = NULL;
//     }
// }