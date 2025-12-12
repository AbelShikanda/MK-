//+------------------------------------------------------------------+
//| MA Alignment Dashboard Display                                  |
//| Displays Enhanced MA Relationship Analyzer results on chart     |
//+------------------------------------------------------------------+
#property strict
#property copyright "Enhanced MA Dashboard"
#property description "Displays MA relationship analysis for each symbol"
#property version   "1.00"

#include "../../config/structures.mqh"
#include "../detectors/MARelationship.mqh"
//+------------------------------------------------------------------+
//| Get MA Alignment Dashboard Section                              |
//+------------------------------------------------------------------+
string GetMAAlignmentDashboard(const string symbol)
{
    string dashboard = "";
    
    // Get MA alignment data
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    // Get detailed MA values for display
    string maDetails = GetDetailedMAValues(symbol);
    
    // Display confidence scores
    // dashboard += "CONFIDENCE SCORES:\n";
    dashboard += "\n";
    dashboard += StringFormat("  Net Bias: %3.0f%% (%s)\n", alignment.netBias, alignment.alignment);
    dashboard += "\n";
    
    // Display MA relationships with your requested format
    dashboard += "MA RELATIONSHIP ANALYSIS:\n";
    dashboard += GetMARelationshipDisplay(symbol, alignment);
    
    // Display warnings if any
    if(alignment.warning != "")
    {
        dashboard += "\n⚠️  WARNINGS:\n";
        dashboard += StringFormat("  %s\n", alignment.warning);
    }
    
    // Display trading recommendations
    // dashboard += "\nTRADING RECOMMENDATIONS:\n";
    // dashboard += GetTradingRecommendations(alignment);
    
    // dashboard += "\n════════════════════════════════════════════════════\n";
    
    return dashboard;
}

//+------------------------------------------------------------------+
//| Get Detailed MA Values                                          |
//+------------------------------------------------------------------+
string GetDetailedMAValues(const string symbol)
{
    string details = "";
    
    // Get MA handles
    int hVeryFast = iMA(symbol, MA_Analysis_Timeframe, VeryFastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hFast = iMA(symbol, MA_Analysis_Timeframe, FastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hMedium = iMA(symbol, MA_Analysis_Timeframe, MediumMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hSlow = iMA(symbol, MA_Analysis_Timeframe, SlowMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    
    // Get current values
    double vfCurrent[1], fCurrent[1], mCurrent[1], sCurrent[1];
    double vfPrevious[1], fPrevious[1], mPrevious[1], sPrevious[1];
    
    bool dataOk = true;
    dataOk = dataOk && (CopyBuffer(hVeryFast, 0, 0, 1, vfCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hFast, 0, 0, 1, fCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hMedium, 0, 0, 1, mCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hSlow, 0, 0, 1, sCurrent) >= 1);
    
    if(!dataOk)
    {
        IndicatorRelease(hVeryFast);
        IndicatorRelease(hFast);
        IndicatorRelease(hMedium);
        IndicatorRelease(hSlow);
        return "Failed to get MA data";
    }
    
    // Get previous values for trend direction
    CopyBuffer(hVeryFast, 0, 1, 1, vfPrevious);
    CopyBuffer(hFast, 0, 1, 1, fPrevious);
    CopyBuffer(hMedium, 0, 1, 1, mPrevious);
    CopyBuffer(hSlow, 0, 1, 1, sPrevious);
    
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    details += StringFormat("Current Price: %.5f\n", currentPrice);
    details += StringFormat("MA%d: %.5f %s\n", VeryFastMA_Period_Enhanced, vfCurrent[0], 
                          vfCurrent[0] > vfPrevious[0] ? "↗" : "↘");
    details += StringFormat("MA%d: %.5f %s\n", FastMA_Period_Enhanced, fCurrent[0],
                          fCurrent[0] > fPrevious[0] ? "↗" : "↘");
    details += StringFormat("MA%d: %.5f %s\n", MediumMA_Period_Enhanced, mCurrent[0],
                          mCurrent[0] > mPrevious[0] ? "↗" : "↘");
    details += StringFormat("MA%d: %.5f %s\n", SlowMA_Period_Enhanced, sCurrent[0],
                          sCurrent[0] > sPrevious[0] ? "↗" : "↘");
    
    // Clean up
    IndicatorRelease(hVeryFast);
    IndicatorRelease(hFast);
    IndicatorRelease(hMedium);
    IndicatorRelease(hSlow);
    
    return details;
}

//+------------------------------------------------------------------+
//| Get MA Relationship Display (Your requested format)             |
//+------------------------------------------------------------------+
string GetMARelationshipDisplay(const string symbol, MAAlignmentScore &alignment)
{
    string display = "";
    
    // Get MA handles
    int hVeryFast = iMA(symbol, MA_Analysis_Timeframe, VeryFastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hFast = iMA(symbol, MA_Analysis_Timeframe, FastMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hMedium = iMA(symbol, MA_Analysis_Timeframe, MediumMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    int hSlow = iMA(symbol, MA_Analysis_Timeframe, SlowMA_Period_Enhanced, 0, MODE_EMA, PRICE_CLOSE);
    
    // Get current values
    double vfCurrent[1], fCurrent[1], mCurrent[1], sCurrent[1];
    
    bool dataOk = true;
    dataOk = dataOk && (CopyBuffer(hVeryFast, 0, 0, 1, vfCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hFast, 0, 0, 1, fCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hMedium, 0, 0, 1, mCurrent) >= 1);
    dataOk = dataOk && (CopyBuffer(hSlow, 0, 0, 1, sCurrent) >= 1);
    
    if(!dataOk)
    {
        IndicatorRelease(hVeryFast);
        IndicatorRelease(hFast);
        IndicatorRelease(hMedium);
        IndicatorRelease(hSlow);
        return "Failed to get MA data";
    }
    
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Calculate gaps in pips
    double gap_5_9 = (vfCurrent[0] - fCurrent[0]) / point;
    double gap_9_21 = (fCurrent[0] - mCurrent[0]) / point;
    double gap_21_89 = (mCurrent[0] - sCurrent[0]) / point;
    
    // Determine relationship type
    string relation5_9 = gap_5_9 > 0 ? "Bull" : "Bear";
    string relation9_21 = gap_9_21 > 0 ? "Bull" : "Bear";
    string relation21_89 = gap_21_89 > 0 ? "Bull" : "Bear";
    
    // Format gap display
    string gap5_9_str = StringFormat("%.1f pips", MathAbs(gap_5_9));
    string gap9_21_str = StringFormat("%.1f pips", MathAbs(gap_9_21));
    string gap21_89_str = StringFormat("%.1f pips", MathAbs(gap_21_89));
    
    // Get action recommendations based on gaps and buffer zones
    string action5_9 = GetMA5_9Action(gap_5_9, alignment);
    string action9_21 = GetMA9_21Action(gap_9_21, alignment);
    string action21_89 = GetMA21_89Action(gap_21_89, alignment);
    
    // Build the display in your requested format
    display += StringFormat("(5-9)MAs  | %-4s | %-12s | %s\n", 
                          relation5_9, gap5_9_str, action5_9);
    display += StringFormat("(9-21)MAs | %-4s | %-12s | %s\n", 
                          relation9_21, gap9_21_str, action9_21);
    display += StringFormat("(21-89)MAs| %-4s | %-12s | %s\n", 
                          relation21_89, gap21_89_str, action21_89);
    
    // Clean up
    IndicatorRelease(hVeryFast);
    IndicatorRelease(hFast);
    IndicatorRelease(hMedium);
    IndicatorRelease(hSlow);
    
    return display;
}

//+------------------------------------------------------------------+
//| Get MA 5-9 Action Recommendation                                |
//+------------------------------------------------------------------+
string GetMA5_9Action(double gap, MAAlignmentScore &alignment)
{
    double absGap = MathAbs(gap);
    
    // Check buffer zone first
    if(absGap < Buffer_5_9)
        return "FOLDING";
    
    // Check if gap is beyond max threshold (over-extended)
    if(absGap > Gap_5_9_Max * 1.5)
        return "CLEAR";
    
    // Check if gap is good for trading
    if(absGap > Gap_5_9_Min && absGap < Gap_5_9_Max)
    {
        if(gap > 0) // Bullish
            return "CLEARING";
        else        // Bearish
            return "CLEARING";
    }
    
    // Gap is too small for meaningful action
    if(absGap < Gap_5_9_Min)
        return "FOLDING";
    
    // Over-extended
    return "FOLDING";
}

//+------------------------------------------------------------------+
//| Get MA 9-21 Action Recommendation                               |
//+------------------------------------------------------------------+
string GetMA9_21Action(double gap, MAAlignmentScore &alignment)
{
    double absGap = MathAbs(gap);
    
    // Check buffer zone first
    if(absGap < Buffer_9_21)
        return "HOLDING";
    
    // Critical crossing detected
    if(alignment.isCritical && StringFind(alignment.warning, "9-21") >= 0)
        return "CLOSING";
    
    // Check if gap is beyond max threshold (over-extended)
    if(absGap > Gap_9_21_Max * 1.5)
        return "CLEAR";
    
    // Check if gap is good for trading
    if(absGap > Gap_9_21_Min && absGap < Gap_9_21_Max)
    {
        if(gap > 0) // Bullish
            return "CLEARING";
        else        // Bearish
            return "CLEARING";
    }
    
    // Gap is too small for meaningful action
    if(absGap < Gap_9_21_Min)
        return "HOLDING";
    
    // Over-extended
    return "CLOSING";
}

//+------------------------------------------------------------------+
//| Get MA 21-89 Action Recommendation                              |
//+------------------------------------------------------------------+
string GetMA21_89Action(double gap, MAAlignmentScore &alignment)
{
    double absGap = MathAbs(gap);
    
    // Check buffer zone first
    if(absGap < Buffer_21_89)
        return "THINKING";
    
    // Check for trend change
    if(alignment.alignment == "STRONGLY_BEARISH" && gap > 0)
        return "REVERSING";
    
    if(alignment.alignment == "STRONGLY_BULLISH" && gap < 0)
        return "REVERSING";
    
    // Check if gap is beyond max threshold (over-extended)
    if(absGap > Gap_21_89_Max * 1.5)
        return "CLEAR";
    
    // Check if gap is good for trend confirmation
    if(absGap > Gap_21_89_Min && absGap < Gap_21_89_Max)
    {
        return "TREND_CONFIRMED";
    }
    
    // Gap is too small for meaningful trend
    if(absGap < Gap_21_89_Min)
        return "THINKING";
    
    // Over-extended or trend change
    return "REVERSING";
}

//+------------------------------------------------------------------+
//| Get Trading Recommendations                                     |
//+------------------------------------------------------------------+
string GetTradingRecommendations(MAAlignmentScore &alignment)
{
    string recommendations = "";
    
    // Critical condition - avoid all trades
    if(alignment.isCritical)
    {
        recommendations += "  ⚠️ CRITICAL: DROP ALL TRADES\n";
        recommendations += "  - MAs crossing or in buffer zone\n";
        recommendations += "  - Wait for clear separation\n";
        return recommendations;
    }
    
    // Strong bullish alignment
    if(alignment.netBias > 25)
    {
        recommendations += "  ✅ STRONG BULLISH BIAS\n";
        recommendations += "  - Favor BUY positions\n";
        recommendations += "  - Consider adding to existing buys\n";
        recommendations += StringFormat("  - Confidence: %.0f%%\n", alignment.buyConfidence);
    }
    // Moderate bullish
    else if(alignment.netBias > 10)
    {
        recommendations += "  ✅ BULLISH BIAS\n";
        recommendations += "  - Can open new BUY positions\n";
        recommendations += "  - Hold existing buys\n";
        recommendations += StringFormat("  - Confidence: %.0f%%\n", alignment.buyConfidence);
    }
    // Strong bearish alignment
    else if(alignment.netBias < -25)
    {
        recommendations += "  ✅ STRONG BEARISH BIAS\n";
        recommendations += "  - Favor SELL positions\n";
        recommendations += "  - Consider adding to existing sells\n";
        recommendations += StringFormat("  - Confidence: %.0f%%\n", alignment.sellConfidence);
    }
    // Moderate bearish
    else if(alignment.netBias < -10)
    {
        recommendations += "  ✅ BEARISH BIAS\n";
        recommendations += "  - Can open new SELL positions\n";
        recommendations += "  - Hold existing sells\n";
        recommendations += StringFormat("  - Confidence: %.0f%%\n", alignment.sellConfidence);
    }
    // Neutral
    else
    {
        recommendations += "  ⏸️  NEUTRAL MARKET\n";
        recommendations += "  - Wait for clearer direction\n";
        recommendations += "  - Consider reducing position sizes\n";
        recommendations += "  - Monitor for breakout\n";
    }
    
    // Add warnings if present
    if(alignment.warning != "")
    {
        recommendations += "\n  ⚠️  CAUTIONS:\n";
        string warnings[];
        StringSplit(alignment.warning, '|', warnings);
        for(int i = 0; i < ArraySize(warnings); i++)
        {
            recommendations += StringFormat("  - %s\n", StringTrimLeft(warnings[i]));
        }
    }
    
    return recommendations;
}

//+------------------------------------------------------------------+
//| Update Dashboard with MA Alignment                              |
//+------------------------------------------------------------------+
void UpdateMAAlignmentDashboard()
{
    string dashboard = "\n";
    dashboard += "════════════════════════════════════════════════════\n";
    dashboard += "           ENHANCED MA ALIGNMENT DASHBOARD          \n";
    dashboard += "════════════════════════════════════════════════════\n\n";
    
    // Assuming you have an array of active symbols
    // You'll need to adapt this to your symbol array structure
    string symbols[] = {"XAUUSD", "XAGUSD"}; // Example symbols
    
    for(int i = 0; i < ArraySize(symbols); i++)
    {
        dashboard += GetMAAlignmentDashboard(symbols[i]);
        if(i < ArraySize(symbols) - 1)
            dashboard += "\n";
    }
    
    dashboard += StringFormat("\n⏰ Last Updated: %s", TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS));
    dashboard += "\n════════════════════════════════════════════════════\n";
    
    Comment(dashboard);
}

//+------------------------------------------------------------------+
//| Get Compact MA Alignment for Main Dashboard                     |
//+------------------------------------------------------------------+
string GetCompactMAAlignment(const string symbol)
{
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    string compact = "";
    compact += StringFormat("%s MA Alignment: ", symbol);
    compact += StringFormat("%s (Bias: %+.0f%%)\n", alignment.alignment, alignment.netBias);
    compact += StringFormat("Buy: %3.0f%% | Sell: %3.0f%%", 
                          alignment.buyConfidence, alignment.sellConfidence);
    
    if(alignment.isCritical)
        compact += " ⚠️ CRITICAL";
    
    return compact;
}

//+------------------------------------------------------------------+
//| Example of how to integrate into your existing dashboard        |
//+------------------------------------------------------------------+
/*
// In your existing dashboard manager, you can add:

string GetFullDashboard()
{
    string dashboard = "\n";
    dashboard += "════════════════════════════════════════════════════\n";
    dashboard += "           SAFE METALS EA v4.5 - TRADING MONITOR    \n";
    dashboard += "════════════════════════════════════════════════════\n\n";
    
    // 1. ACCOUNT OVERVIEW
    dashboard += GetAccountOverview();
    
    // 2. MA ALIGNMENT ANALYSIS (NEW SECTION)
    dashboard += "\n7️⃣ MA ALIGNMENT ANALYSIS:\n";
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        dashboard += GetCompactMAAlignment(symbol) + "\n";
    }
    
    // 3. MARKET SENTIMENT
    dashboard += GetMarketSentimentDisplay();
    
    // ... rest of your dashboard
}
*/

//+------------------------------------------------------------------+
//| Display specific symbol MA analysis on chart                    |
//+------------------------------------------------------------------+
void DisplaySpecificSymbolMA(const string symbol)
{
    Comment(GetMAAlignmentDashboard(symbol));
}

//+------------------------------------------------------------------+
//| Test function to see MA analysis for a symbol                   |
//+------------------------------------------------------------------+
void TestMAAlignment(string symbol = "XAUUSD")
{
    Print(GetMAAlignmentDashboard(symbol));
}