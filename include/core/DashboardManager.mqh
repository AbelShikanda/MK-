//+------------------------------------------------------------------+
//| Dashboard Manager - Chart Display                               |
//+------------------------------------------------------------------+
#property strict

#include "../config/inputs.mqh"
#include "../utils/FormatUtils.mqh"
#include "../signals/SignalScorer.mqh"
#include "../market/trend/TrendAnalyzer.mqh"
#include "../execution/TradeExecutor.mqh"
#include "../utils/TradeUtils.mqh"
#include "../market/trend/MATrends.mqh"

// ================================================================
// SECTION 1: DASHBOARD DISPLAY FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Full Dashboard                                              |
//+------------------------------------------------------------------+
string GetFullDashboard()
{
    string dashboard = "\n";
    dashboard += "════════════════════════════════════════════════════\n";
    dashboard += "           SAFE METALS EA v4.5 - TRADING MONITOR    \n";
    dashboard += "════════════════════════════════════════════════════\n\n";
    
    // 1. ACCOUNT OVERVIEW
    dashboard += GetAccountOverview();
    
    // 3. MARKET PUSH (Lower Weight for Trading)
    // dashboard += GetMarketSentimentDisplay();
    
    // 4. GENERAL SENTIMENT (Higher Weight)
    // dashboard += GetGeneralTrendDisplay();
    
    // 5. LONG-TERM TREND (Weekly Outlook)
    // dashboard += GetLongTermTrendDisplay();
    
    // 6. TRADING DECISION
    dashboard += GetTradingDecisionsDisplay();
    
    // Loop through all active symbols
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        dashboard += GetMAAlignmentDashboard(symbol);
        
        if(i < totalSymbols - 1)
            dashboard += "\n────────────────────────────────────────────────\n\n";
    }
    
    return dashboard;
}

//+------------------------------------------------------------------+
//| Get Compact Dashboard (for smaller displays)                    |
//+------------------------------------------------------------------+
string GetCompactDashboard()
{
    string dashboard = "";
    dashboard += "SAFE METALS EA v4.5\n";
    dashboard += "════════════════════\n\n";
    
    // Only show key metrics
    dashboard += GetAccountOverview();
    dashboard += "\n";
    dashboard += GetTradingDecisionsDisplay();
    dashboard += GetRiskLevelIndicator();
    
    dashboard += StringFormat("\n⏰ %s", TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS));
    
    return dashboard;
}

//+------------------------------------------------------------------+
//| Get Symbol-specific Dashboard                                   |
//+------------------------------------------------------------------+
string GetSymbolDashboard(string symbol)
{
    string dashboard = "";
    dashboard += StringFormat("SYMBOL ANALYSIS: %s\n", symbol);
    dashboard += "════════════════════════════\n\n";
    
    dashboard += StringFormat("Account Equity: $%.2f\n", AccountInfoDouble(ACCOUNT_EQUITY));
    dashboard += StringFormat("Daily P/L: $%.2f\n\n", dailyProfitCash);
    
    // Symbol-specific information
    dashboard += "SCORE & DIRECTION:\n";
    dashboard += GetSingleSymbolScore(symbol);
    dashboard += "\n";
    
    dashboard += "MARKET SENTIMENT:\n";
    dashboard += GetSingleSymbolSentiment(symbol);
    dashboard += "\n";
    
    dashboard += "GENERAL TREND:\n";
    dashboard += GetSingleSymbolGeneralTrend(symbol);
    dashboard += "\n";
    
    dashboard += "LONG-TERM TREND:\n";
    // Need to find the index for this symbol
    int symbolIndex = -1;
    for(int i = 0; i < totalSymbols; i++)
    {
        if(activeSymbols[i] == symbol)
        {
            symbolIndex = i;
            break;
        }
    }
    dashboard += GetSingleSymbolTrend(symbol, symbolIndex);
    dashboard += "\n";
    
    dashboard += "TRADING DECISION:\n";
    dashboard += GetSingleSymbolDecision(symbol);
    
    return dashboard;
}

//+------------------------------------------------------------------+
//| Get Specific Section by Number                                  |
//+------------------------------------------------------------------+
string GetDashboardSection(int sectionNumber)
{
    switch(sectionNumber)
    {
        case 1: return GetAccountOverview();
        case 2: return GetSymbolScoresDisplay();
        case 3: return GetMarketSentimentDisplay();
        case 4: return GetGeneralTrendDisplay();
        case 5: return GetLongTermTrendDisplay();
        case 6: return GetTradingDecisionsDisplay();
        case 7: return GetRiskLevelIndicator();
        default: return "Invalid section number (1-7)";
    }
}

//+------------------------------------------------------------------+
//| Update Chart Display - Main Function                            |
//+------------------------------------------------------------------+
void UpdateChartDisplay() 
{ 
    Comment(GetFullDashboard());
}

// ================================================================
// SECTION 2: ACCOUNT & RISK DISPLAY FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Account Overview Section                                    |
//+------------------------------------------------------------------+
string GetAccountOverview()
{
    string statusText = "";
    statusText += "1️⃣ ACCOUNT OVERVIEW:\n";
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = (margin > 0) ? (equity / margin * 100) : 0;
    
    statusText += FormatAccountMetrics(balance, equity, margin, freeMargin, marginLevel);
    statusText += "\n";
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Risk Level Indicator                                        |
//+------------------------------------------------------------------+
string GetRiskLevelIndicator()
{
    string riskText = "\n⚠️  RISK LEVEL: ";
    
    if(dailyDrawdownCash >= DailyDrawdownLimitCash * 0.8)
        riskText += "HIGH (Near drawdown limit)";
    else if(dailyDrawdownCash >= DailyDrawdownLimitCash * 0.5)
        riskText += "MEDIUM";
    else
        riskText += "LOW";
    
    return riskText;
}

// ================================================================
// SECTION 3: SYMBOL SCORE & DIRECTION FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Symbol Scores Display                                       |
//+------------------------------------------------------------------+
string GetSymbolScoresDisplay()
{
    string statusText = "";
    statusText += "2️⃣ SYMBOL SCORE:\n";
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        statusText += GetSingleSymbolScore(symbol);
    }
    statusText += "\n";
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Single Symbol Score                                         |
//+------------------------------------------------------------------+
string GetSingleSymbolScore(string symbol)
{
    double directionPercent;
    double buyScore = GetUltraSensitiveSignalScore(symbol, true);
    double sellScore = GetUltraSensitiveSignalScore(symbol, false);
    
    string direction = "NEUTRAL";
    directionPercent = 0;
    
    double difference = buyScore - sellScore;
    
    if(MathAbs(difference) > 10)
    {
        if(difference > 0)
        {
            directionPercent = difference;
            direction = "BULL";
        }
        else
        {
            directionPercent = MathAbs(difference);
            direction = "BEAR";
        }
    }
    
    return StringFormat("   %-7s: %-5s %3.0f%%\n", symbol, direction, directionPercent);
}

//+------------------------------------------------------------------+
//| Calculate Symbol Direction                                      |
//+------------------------------------------------------------------+
double CalculateSymbolDirection(string symbol, double &outDirectionPercent)
{
    double buyScore = GetUltraSensitiveSignalScore(symbol, true);
    double sellScore = GetUltraSensitiveSignalScore(symbol, false);
    
    double difference = buyScore - sellScore;
    outDirectionPercent = 0;
    
    if(MathAbs(difference) > 10)
    {
        outDirectionPercent = MathAbs(difference);
    }
    
    return difference;  // Positive = bullish, Negative = bearish
}

// ================================================================
// SECTION 4: MARKET ANALYSIS DISPLAY FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Market Sentiment Display                                    |
//+------------------------------------------------------------------+
string GetMarketSentimentDisplay()
{
    string statusText = "";
    statusText += "3️⃣ MARKET SENTIMENT:\n";
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        statusText += GetSingleSymbolSentiment(symbol);
    }
    statusText += "\n";
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Single Symbol Sentiment                                     |
//+------------------------------------------------------------------+
string GetSingleSymbolSentiment(string symbol)
{
    double sentiment = CalculateMarketSentiment(symbol);
    string sentimentText = GetSentimentText(sentiment);
    
    return StringFormat("   %-7s: %-15s %3.0f%%\n", symbol, sentimentText, sentiment);
}

//+------------------------------------------------------------------+
//| Get General Trend Display                                       |
//+------------------------------------------------------------------+
string GetGeneralTrendDisplay()
{
    string statusText = "";
    statusText += "4️⃣ TREND SENTIMENT:\n";
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        statusText += GetSingleSymbolGeneralTrend(symbol);
    }
    statusText += "\n";
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Single Symbol General Trend                                 |
//+------------------------------------------------------------------+
string GetSingleSymbolGeneralTrend(string symbol)
{
    double trend = CalculateGeneralTrend(symbol);
    string trendText = GetGeneralTrendText(trend);
    
    return StringFormat("   %-7s: %-15s %3.0f%%\n", symbol, trendText, trend);
}

//+------------------------------------------------------------------+
//| Get Long-term Trend Display                                     |
//+------------------------------------------------------------------+
string GetLongTermTrendDisplay()
{
    string statusText = "";
    statusText += "5️⃣ LONG-TERM TREND:\n";
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        statusText += GetSingleSymbolTrend(symbol, i);
    }
    statusText += "\n";
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Single Symbol Trend                                         |
//+------------------------------------------------------------------+
string GetSingleSymbolTrend(string symbol, int maHandleIndex)
{
    double trend = CalculateLongTermTrend(symbol);
    string trendText = GetTrendText(trend);
    string maInfo = GetMAPositionInfo(symbol, maHandleIndex);
    
    if(StringFind(maInfo, "No MA100") != -1)
    {
        return StringFormat("   %-7s: %-12s %3.0f%% (No MA100 data)\n", 
                          symbol, trendText, trend);
    }
    
    return StringFormat("   %-7s: %-12s %3.0f%%\n", symbol, trendText, trend);
}

// ================================================================
// SECTION 5: TRADING DECISION FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Get Trading Decisions Display                                   |
//+------------------------------------------------------------------+
string GetTradingDecisionsDisplay()
{
    string statusText = "";
    statusText += "6️⃣ TRADING DECISION:\n";
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        statusText += GetSingleSymbolDecision(symbol);
    }
    
    return statusText;
}

//+------------------------------------------------------------------+
//| Get Single Symbol Decision                                      |
//+------------------------------------------------------------------+
string GetSingleSymbolDecision(string symbol)
{
    // Call unified executor to populate botConclusion
    string unifiedResult = ExecuteTradeBasedOnDecision(symbol);
    
    int openTrades = CountOpenTrades(symbol);
    string decision = unifiedResult;
    
    // Get bot thoughts from the global variable
    string botThoughts = botConclusion;
    
    int currentDirection = GetCurrentTradeDirection(symbol);
    string positionStatus = "NO POSITIONS";
    
    if(currentDirection == POSITION_TYPE_BUY)
        positionStatus = StringFormat("BUY POSITIONS: %d", openTrades);
    else if(currentDirection == POSITION_TYPE_SELL)
        positionStatus = StringFormat("SELL POSITIONS: %d", openTrades);
    
    // If positions are full, show both the action and bot's thoughts
    if(decision == "FULL" || StringFind(decision, "FULL|") >= 0)
    {
        return StringFormat("   %-7s: %s | %s : %s\n", 
                          symbol, decision, positionStatus, botThoughts);
    }
    else
    {
        return StringFormat("   %-7s: %s | %s\n", symbol, decision, positionStatus);
    }
}

// ================================================================
// SECTION 6: FORMATTING HELPER FUNCTIONS
// ================================================================

//+------------------------------------------------------------------+
//| Format Account Metrics                                          |
//+------------------------------------------------------------------+
string FormatAccountMetrics(double balance, double equity, double margin, 
                           double freeMargin, double marginLevel)
{
    string formattedText = "";
    
    formattedText += StringFormat("   Balance: $%-10.2f | Equity: $%-10.2f\n", balance, equity);
    formattedText += StringFormat("   Free Margin: $%-7.2f | Margin Level: %5.1f%%\n", freeMargin, marginLevel);
    formattedText += StringFormat("   Daily P/L: %s$%-8.2f | Trades Today: %d\n", 
                                  (dailyProfitCash >= 0 ? "+" : ""), dailyProfitCash, dailyTradesCount);
    formattedText += StringFormat("   Daily Limit: $%.2f/%d%% | Drawdown: $%.2f/%.1f%%\n",
                                  MathMin(dailyProfitCash, DailyProfitLimitCash),
                                  (int)((dailyProfitCash / DailyProfitLimitCash) * 100),
                                  dailyDrawdownCash,
                                  (dailyDrawdownCash / DailyDrawdownLimitCash) * 100);
    formattedText += StringFormat("   Risk: %.1f%% | Lot: %.3f | Tier: %s\n",
                                  RiskPercent, currentManualLotSize, GetCurrentTier());
    
    return formattedText;
}

//+------------------------------------------------------------------+
//| Get Sentiment Text                                              |
//+------------------------------------------------------------------+
string GetSentimentText(double sentiment)
{
    if(sentiment >= 70) return "STRONG BUY";
    if(sentiment >= 60) return "BUY";
    if(sentiment >= 40 && sentiment <= 60) return "NEUTRAL";
    if(sentiment >= 30) return "SELL";
    return "STRONG SELL";
}

//+------------------------------------------------------------------+
//| Get General Trend Text                                          |
//+------------------------------------------------------------------+
string GetGeneralTrendText(double trend)
{
    if(trend >= 75) return "STRONG BULL";
    if(trend >= 62) return "BULL";
    if(trend >= 38) return "NEUTRAL";
    if(trend >= 25) return "BEAR";
    return "STRONG BEAR";
}

//+------------------------------------------------------------------+
//| Get Trend Text                                                  |
//+------------------------------------------------------------------+
string GetTrendText(double trend)
{
    if(trend >= 70) return "STRONG BULL";
    if(trend >= 60) return "BULLISH";
    if(trend <= 30) return "STRONG BEAR";
    if(trend <= 40) return "BEARISH";
    return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Get MA Position Info                                            |
//+------------------------------------------------------------------+
string GetMAPositionInfo(string symbol, int maHandleIndex)
{
    double ma100 = 0;
    
    if(maHandleIndex >= 0 && maHandleIndex < ArraySize(longTermMA_LT) && longTermMA_LT[maHandleIndex] != -1)
    {
        double maBuffer[1];
        if(CopyBuffer(longTermMA_LT[maHandleIndex], 0, 0, 1, maBuffer) >= 1)
        {
            ma100 = maBuffer[0];
        }
    }
    
    if(ma100 > 0)
    {
        return "MA100 Available";
    }
    
    return "No MA100 data";
}