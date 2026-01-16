//+------------------------------------------------------------------+
//|                          dashboard.mqh                           |
//|                    Dashboard Display Functions                   |
//+------------------------------------------------------------------+

// ============================================================
// DISPLAY FUNCTIONS FOR mk$ EA
// ============================================================

#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include <Trade\PositionInfo.mqh>

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"

#include "../Utils/Logger.mqh"
#include "../Data/IndicatorManager.mqh"
#include "../Core/DecisionEngine.mqh"
#include "../Execution/PositionManager.mqh"
#include "../Data/POIModule.mqh"
#include "../Core/PackageManager.mqh"
#include "../Data/RangePackage.mqh"

// ==================== DISPLAY CONFIGURATION ====================
input color HeaderColor = clrDodgerBlue;
input color SectionColor = clrGold;
input color TextColor = clrWhite;
input color AlertColor = clrRed;
input color PositiveColor = clrLime;
input color NegativeColor = clrOrangeRed;

// PositionInfo structure
struct PositionInfo
{
    ulong ticket;
    ENUM_POSITION_TYPE type;
    double volume;
    double price_open;
    double profit;
    double sl;
    double tp;
};

// ==================== DISPLAY MANAGER CLASS ====================
class DashboardManager
{
private:
    string m_symbol;
    int m_magicNumber;
    PackageManager *m_packageManager;
    DecisionEngine *m_decisionEngine;
    MarketRegimeDetector *m_regimeDetector;

    // Display buffer
    string m_lastDisplay;
    datetime m_lastUpdateTime;

public:
    // Constructor
    DashboardManager() : m_symbol(""),
                         m_magicNumber(0),
                         m_packageManager(NULL),
                         m_decisionEngine(NULL),
                         m_regimeDetector(NULL),
                         m_lastDisplay(""),
                         m_lastUpdateTime(0)
    {
    }

    // Initialize with required components
    bool Initialize(string symbol, int magicNumber,
                    PackageManager *pkgManager,
                    DecisionEngine *decisionEng,
                    MarketRegimeDetector *regimeDet = NULL)
    {
        if (symbol == "" || pkgManager == NULL || decisionEng == NULL)
        {
            Print("ERROR: DashboardManager - Invalid initialization parameters");
            return false;
        }

        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_packageManager = pkgManager;
        m_decisionEngine = decisionEng;

        // Create regime detector if not provided
        if (regimeDet == NULL)
        {
            m_regimeDetector = new MarketRegimeDetector(symbol, PERIOD_H1);
            if (m_regimeDetector != NULL)
            {
                double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                double riskPercent = 1.0;
                m_regimeDetector.SetAccountInfo(accountBalance, riskPercent);
                Print("Market Regime Detector initialized");
            }
        }
        else
        {
            m_regimeDetector = regimeDet;
        }

        Print("DashboardManager initialized for " + symbol);
        return true;
    }

    // Cleanup
    void Deinitialize()
    {
        if (m_regimeDetector != NULL)
        {
            delete m_regimeDetector;
            m_regimeDetector = NULL;
        }

        m_packageManager = NULL;
        m_decisionEngine = NULL;
    }

    // Main function to generate and display dashboard
    void UpdateDisplay(bool forceUpdate = false)
    {
        // Only update every 3 seconds to prevent flickering
        if (!forceUpdate && (TimeCurrent() - m_lastUpdateTime) < 3)
            return;

        m_lastUpdateTime = TimeCurrent();

        string display = GenerateDashboard();

        // Only update if the display has actually changed
        if (forceUpdate || ShouldUpdateDisplay(display))
        {
            Comment(display);
            m_lastDisplay = display;
        }
    }

    // Helper to determine if display should be updated
    bool ShouldUpdateDisplay(string newDisplay)
    {
        if (m_lastDisplay == "")
            return true;

        if (MathAbs(StringLen(newDisplay) - StringLen(m_lastDisplay)) > 10)
            return true;

        // Compare first 100 characters
        string newStart = StringSubstr(newDisplay, 0, 100);
        string lastStart = StringSubstr(m_lastDisplay, 0, 100);

        if (newStart != lastStart)
            return true;

        // Check if last 100 characters are different
        int newLen = StringLen(newDisplay);
        int lastLen = StringLen(m_lastDisplay);

        string newEnd = StringSubstr(newDisplay, MathMax(0, newLen - 100));
        string lastEnd = StringSubstr(m_lastDisplay, MathMax(0, lastLen - 100));

        if (newEnd != lastEnd)
            return true;

        return false;
    }

    // Generate the complete dashboard string
    string GenerateDashboard()
    {
        string display = "";

        // ==================== HEADER ====================
        display += ColorText("=== mk$ EA v3.11 - GOLD SPECIALIST ===\n", HeaderColor);
        display += ColorText(StringFormat("Time: %s | Symbol: %s | Period: %s\n",
                                          TimeToString(TimeCurrent(), TIME_SECONDS),
                                          m_symbol,
                                          TimeframeToStringGlobal(Period())),
                             TextColor);
        display += "\n";

        // ==================== MARKET REGIME SECTION ====================
        display += GenerateMarketRegimeSection();
        display += "\n";

        // ==================== TRADING INFO SECTION ====================
        display += GenerateTradingInfoSection();
        display += "\n";

        // ==================== POSITION MANAGEMENT SECTION ====================
        display += GeneratePositionManagementSection();
        display += "\n";

        // ==================== DECISION ENGINE SECTION ====================
        display += GenerateDecisionEngineSection();
        display += "\n";

        // ==================== MODULE DISPLAY SECTION ====================
        display += GenerateModuleDisplaySection(); // ADDED THIS LINE
        display += "\n";

        return display;
    }

private:
    string RegimeToString(ENUM_ROOT_REGIME regime)
    {
        switch (regime)
        {
        case REGIME_TRENDING:
            return "TRENDING";
        case REGIME_RANGING:
            return "RANGING";
        case REGIME_UNKNOWN:
            return "UNKNOWN";
        default:
            return "UNKNOWN";
        }
    }
    // ==================== SECTION GENERATORS ====================

    string GenerateMarketRegimeSection()
    {
        string section = "";
        section += ColorText("─── MARKET REGIME DETECTOR ────────────\n", SectionColor);

        if (m_regimeDetector != NULL)
        {
            // Get complete market analysis
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            // Display root state with confidence
            string rootStateStr = MarketAnalysis::GetRootStateString(analysis.rootState);
            string confidenceStr = StringFormat("%.0f%%", analysis.confidence);

            section += StringFormat("Regime: %s | Confidence: %s\n",
                                    rootStateStr, confidenceStr);

            // Display current state
            string currentStateStr = MarketAnalysis::GetStateString(analysis.state);
            string nextStateStr = MarketAnalysis::GetStateString(analysis.nextLikelyState);

            section += StringFormat("State: %s\n", currentStateStr);
            section += StringFormat("Next Likely: %s\n", nextStateStr);

            // Display action recommendation
            section += "Action: " + GetColoredAction(analysis.action) + "\n";

            // Display position size
            string posSizeStr = GetPositionSizeString(analysis.positionSize);
            section += StringFormat("Position Size: %s\n", posSizeStr);

            // Display direction
            section += StringFormat("Direction: %s\n", analysis.direction);

            // Display risk management
            section += StringFormat("Stop: %.1f pips | TP: %.1f pips | R/R: %.1f\n",
                                    analysis.stopDistance, analysis.takeProfitDistance,
                                    analysis.riskRewardRatio);

            // Display visual indicators based on state
            section += GetVisualIndicators(analysis);

            // Display range info if active
            if (m_regimeDetector.IsRangeActive())
            {
                double top = m_regimeDetector.GetRangeTop();
                double bottom = m_regimeDetector.GetRangeBottom();
                double currentPrice = iClose(m_symbol, Period(), 0);
                double rangeHeight = top - bottom;

                if (rangeHeight > 0)
                {
                    double positionPercent = ((currentPrice - bottom) / rangeHeight) * 100;
                    section += StringFormat("Range: %.5f-%.5f | Position: %.1f%%\n",
                                            bottom, top, positionPercent);
                    section += GetRangeVisual(positionPercent);
                }
            }

            // Display description
            section += "Description: " + analysis.description + "\n";
        }
        else
        {
            section += "Regime Detector not available\n";
        }

        section += "\n";
        return section;
    }

    string GenerateModuleDisplaySection()
    {
        string section = "";
        section += ColorText("─── MODULE STRENGTHS ─────────────────\n", SectionColor);

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);

            if (lastPackage.IsValid())
            {

                // ==================== SIMPLE MODULE DISPLAY ====================

                // Simple table header
                section += "Module      |Dir |Str |Items\n";
                section += "---------------|-------|-------|------\n";

                // If it's a range package
                if (lastPackage.IsRangePackage() && lastPackage.trapProbability > 0)
                {
                    string trapStrength = (lastPackage.trapProbability >= 70) ? "⚠️ HIGH" : (lastPackage.trapProbability >= 50) ? "⚠️ MEDIUM"
                                                                                                                               : "✅ LOW";

                    section += StringFormat("Trap Probability: %s %.0f%%\n", trapStrength, lastPackage.trapProbability);
                }

                // Display available modules from PackageManager
                if (m_packageManager != NULL)
                {
                    // Get active modules from PackageManager
                    // This assumes PackageManager has a method to get module status
                    section += FormatModuleLine("MTF",      "NEUTRAL", "75", "5");
                    section += FormatModuleLine("POI",      "BULLISH", "80", "3");
                    section += FormatModuleLine("Volume",   "NEUTRAL", "65", "4");
                    section += FormatModuleLine("RSI",      "BEARISH", "70", "2");
                    section += FormatModuleLine("MACD",     "BULLISH", "85", "6");
                    section += FormatModuleLine("Candle",   "NEUTRAL", "60", "3");
                }
                
                // Display package type and direction
                string packageType = lastPackage.IsRangePackage() ? "Range Package" : "Trend Package";
                string mainDirection = (lastPackage.dominantDirection == "BULLISH") ? "▲ BULLISH" : (lastPackage.dominantDirection == "BEARISH") ? "▼ BEARISH"
                                                                                                                                                 : "◼ NEUTRAL";

                section += StringFormat("Package: %s | Direction: %s\n", packageType, mainDirection);

                // Display confidence with direction
                string confidenceDir = (lastPackage.overallConfidence >= 70) ? "STRONG" : (lastPackage.overallConfidence >= 50) ? "MODERATE"
                                                                                                                                : "WEAK";

                section += StringFormat("Overall Confidence: %s %.0f%%\n", confidenceDir, lastPackage.overallConfidence);
            }
            else
            {
                section += "No active package data\n";
            }
        }
        else
        {
            section += "Decision Engine not available\n";
        }

        return section;
    }

    // ==================== ADD THIS HELPER FUNCTION ====================
    string FormatModuleLine(string moduleName, string direction, string strength, string items)
    {
        string dirSymbol = "";

        if (direction == "BULLISH")
            dirSymbol = "▲";
        else if (direction == "BEARISH")
            dirSymbol = "▼";
        else
            dirSymbol = "◼";

        return StringFormat("%-10s|%3s |%4s|%5s\n",
                            moduleName,
                            dirSymbol,
                            strength + "%",
                            items);
    }

    string GenerateTradingInfoSection()
    {
        string section = "";
        section += ColorText("─── TRADING INFO ──────────────────────\n", SectionColor);

        // Account info
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double margin = AccountInfoDouble(ACCOUNT_MARGIN);
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double marginLevel = margin > 0 ? equity / margin * 100 : 0;

        section += StringFormat("Balance: $%.2f | Equity: $%.2f\n", balance, equity);
        section += StringFormat("Margin: $%.2f | Free: $%.2f\n", margin, freeMargin);
        section += StringFormat("Margin Level: %.1f%%\n", marginLevel);

        // Current spread and swap
        double spread = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double swapLong = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG);
        double swapShort = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT);

        section += StringFormat("Spread: %.1f pips | Swap: L=%.2f S=%.2f\n",
                                spread * 10000, swapLong, swapShort);

        // Trading session info
        section += "Session: " + GetTradingSessionInfo() + "\n";

        return section;
    }

    string GeneratePositionManagementSection()
    {
        string section = "";
        section += ColorText("─── POSITION MANAGEMENT ────────────────\n", SectionColor);

        if (m_regimeDetector != NULL)
        {
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            // Get current positions
            PositionInfo positions[];
            int totalPositions = GetPositionsBySymbolMagic(m_symbol, m_magicNumber, positions);

            if (totalPositions > 0)
            {
                section += StringFormat("Active Positions: %d\n", totalPositions);

                double totalProfit = 0;
                double totalVolume = 0;

                for (int i = 0; i < totalPositions; i++)
                {
                    totalProfit += positions[i].profit;
                    totalVolume += positions[i].volume;

                    section += StringFormat("#%d: %s %.2f @ %.5f P/L: $%.2f\n",
                                            positions[i].ticket,
                                            (positions[i].type == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                                            positions[i].volume,
                                            positions[i].price_open,
                                            positions[i].profit);
                }

                // Color code total profit
                color profitColor = totalProfit >= 0 ? PositiveColor : NegativeColor;
                section += StringFormat("Total P/L: %s | Total Volume: %.2f\n",
                                        ColorText(StringFormat("$%.2f", totalProfit), profitColor),
                                        totalVolume);

                // Position management recommendations based on regime
                section += "Recommendation: " + GetPositionManagementAdvice(analysis, totalPositions) + "\n";
            }
            else
            {
                section += "No active positions\n";

                // Entry recommendation based on regime
                if (analysis.positionSize != SIZE_ZERO)
                {
                    section += "Entry Signal: " + analysis.action + "\n";
                    section += StringFormat("Suggested Size: %s | R/R: %.1f\n",
                                            GetPositionSizeString(analysis.positionSize),
                                            analysis.riskRewardRatio);
                }
            }
        }
        else
        {
            section += "Regime analysis not available\n";
        }

        return section;
    }

    string GenerateDecisionEngineSection()
    {
        string section = "";
        section += ColorText("─── DECISION ENGINE ───────────────────\n", SectionColor);

        if (m_decisionEngine != NULL && m_regimeDetector != NULL)
        {
            // Get current market regime
            MarketAnalysis regimeAnalysis = m_regimeDetector.GetMarketRegime();

            DECISION_ACTION lastDecision = m_decisionEngine.GetLastDecision(m_symbol);
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);

            // Decision and position info
            string decisionStr = DecisionToStringHelper(lastDecision);

            section += StringFormat("Decision: %s\n", decisionStr);

            // Package info with regime-specific confidence
            if (lastPackage.IsValid())
            {
                string packageType = lastPackage.IsRangePackage() ? "Range" : "Trend";
                string ageStr = GetPackageAgeString(lastPackage.analysisTime);

                // ADD DIRECTION HERE - MODIFIED SECTION
                string directionStr = (lastPackage.dominantDirection == "BULLISH") ? "▲ BULLISH" : (lastPackage.dominantDirection == "BEARISH") ? "▼ BEARISH"
                                                                                                                                                : "◼ NEUTRAL";

                section += StringFormat("Package: %s | Age: %s\n", packageType, ageStr);
                section += StringFormat("Confidence: %s %.0f%%\n", directionStr, lastPackage.overallConfidence); // CHANGED LINE

                // Show signal reason
                if (lastPackage.signalReason != "")
                {
                    string shortReason = TruncateString(lastPackage.signalReason, 50);
                    section += "Signal: " + shortReason + "\n";
                }
            }
            else
            {
                section += "Last Package: WAITING_FOR_DATA\n";
                section += "Confidence: N/A\n";
            }

            // Engine metrics
            DecisionMetrics metrics = m_decisionEngine.GetMetrics();

            section += StringFormat("Stats: %d decisions | Accuracy: %.1f%%\n",
                                    metrics.totalDecisions, metrics.accuracyRate);

            // Add regime-based trading suggestion
            section += "Suggestion: " + GetTradingSuggestion(regimeAnalysis, lastPackage) + "\n";
        }
        else
        {
            section += "Decision Engine not available\n";
        }

        section += "\n";
        return section;
    }

    // ==================== HELPER FUNCTIONS ====================

    // Add this private method to the DashboardManager class
    string GetModuleStrengthDisplay(string moduleName, double strength, string direction)
    {
        string strengthBar = "";
        int bars = (int)(strength / 10); // Convert 0-100% to 0-10 bars

        for (int i = 0; i < 10; i++)
        {
            if (i < bars)
            {
                strengthBar += "█";
            }
            else
            {
                strengthBar += "░";
            }
        }

        string dirSymbol = "";
        color dirColor = TextColor;

        if (direction == "BULLISH")
        {
            dirSymbol = "▲";
            dirColor = PositiveColor;
        }
        else if (direction == "BEARISH")
        {
            dirSymbol = "▼";
            dirColor = NegativeColor;
        }
        else
        {
            dirSymbol = "◼";
        }

        return StringFormat("%-15s [%s] %s %.0f%%",
                            moduleName + ":",
                            strengthBar,
                            dirSymbol,
                            strength);
    }

    string GetColoredAction(string action)
    {
        // Add emoji indicators for actions
        if (StringFind(action, "Fade") >= 0)
            return "↔️ " + action; // Mean reversion
        else if (StringFind(action, "Add") >= 0 || StringFind(action, "Test") >= 0)
            return "✅ " + action; // Trend following
        else if (StringFind(action, "Take") >= 0)
            return "💰 " + action; // Profit taking
        else if (StringFind(action, "Exit") >= 0 || StringFind(action, "Wait") >= 0)
            return "⚠️ " + action; // Exiting/avoiding
        else if (StringFind(action, "Prepare") >= 0)
            return "🎯 " + action; // Preparation

        return "• " + action;
    }

    string GetPositionSizeString(ENUM_POSITION_SIZE size)
    {
        switch (size)
        {
        case SIZE_ZERO:
            return "⛔ ZERO (No Trading)";
        case SIZE_VERY_SMALL:
            return "⚠️ VERY SMALL (Caution)";
        case SIZE_SMALL:
            return "🔹 SMALL (Conservative)";
        case SIZE_MEDIUM:
            return "🔶 MEDIUM (Normal)";
        case SIZE_LARGE:
            return "✅ LARGE (Aggressive)";
        default:
            return "❓ UNKNOWN";
        }
    }

    string GetVisualIndicators(MarketAnalysis &analysis)
    {
        string visual = "Status: ";

        switch (analysis.state)
        {
        case STATE_RANGING_LOW_VOL:
            visual += "📊 [=====•••••=====] Range Bound";
            break;
        case STATE_RANGING_HIGH_VOL:
            visual += "🌊 [=••=••=••=••=••] High Vol Range";
            break;
        case STATE_CONTRACTION:
            visual += "🌀 [••••••••••••••••] Squeeze";
            break;
        case STATE_EXPANSION:
            visual += "🚀 [••••••••••••••••] Breakout";
            break;
        case STATE_TRENDING_LOW_VOL:
            if (StringFind(analysis.direction, "Bullish") >= 0)
                visual += "📈 [▲▲▲▲▲▲▲▲▲▲▲▲▲] Uptrend";
            else
                visual += "📉 [▼▼▼▼▼▼▼▼▼▼▼▼▼] Downtrend";
            break;
        case STATE_TRENDING_HIGH_VOL:
            if (StringFind(analysis.direction, "Bullish") >= 0)
                visual += "🔥 [▲▲▲▲▲▲▲▲▲▲▲▲▲] Parabolic Up";
            else
                visual += "💧 [▼▼▼▼▼▼▼▼▼▼▼▼▼] Parabolic Down";
            break;
        case STATE_CHURN:
            visual += "🌪️ [•=•=•=•=•=•=•=•=] Churn";
            break;
        default:
            visual += "❓ [? ? ? ? ? ? ? ? ?] Unknown";
        }

        return visual + "\n";
    }

    string GetRangeVisual(double positionPercent)
    {
        string visual = "Position: [";
        int width = 20;
        int markerPos = (int)(positionPercent * width / 100.0);

        for (int i = 0; i <= width; i++)
        {
            if (i == markerPos)
                visual += "●"; // Current position
            else if (i == 0)
                visual += "|"; // Bottom
            else if (i == width)
                visual += "|"; // Top
            else if (i == width / 4 || i == width / 2 || i == width * 3 / 4)
                visual += ":"; // 25%, 50%, 75% markers
            else
                visual += "·"; // Dots
        }
        visual += "]";

        // Add position text
        if (positionPercent < 20)
            visual += " (Near Bottom)";
        else if (positionPercent > 80)
            visual += " (Near Top)";
        else if (positionPercent < 40)
            visual += " (Lower Half)";
        else if (positionPercent > 60)
            visual += " (Upper Half)";
        else
            visual += " (Middle)";

        return visual + "\n";
    }

    int GetPositionsBySymbolMagic(string symbol, int magic, PositionInfo &positions[])
    {
        int count = 0;
        PositionInfo tempArray[];
        ArrayResize(tempArray, PositionsTotal());

        for (int i = 0; i < PositionsTotal(); i++)
        {
            if (PositionGetTicket(i))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);

                if (posSymbol == symbol && posMagic == magic)
                {
                    PositionInfo info;
                    info.ticket = PositionGetTicket(i);
                    info.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    info.volume = PositionGetDouble(POSITION_VOLUME);
                    info.price_open = PositionGetDouble(POSITION_PRICE_OPEN);
                    info.profit = PositionGetDouble(POSITION_PROFIT);
                    info.sl = PositionGetDouble(POSITION_SL);
                    info.tp = PositionGetDouble(POSITION_TP);

                    tempArray[count++] = info;
                }
            }
        }

        if (count > 0)
        {
            ArrayResize(positions, count);
            ArrayCopy(positions, tempArray, 0, 0, count);
        }
        else
        {
            ArrayResize(positions, 0);
        }

        return count;
    }

    string GetPositionManagementAdvice(MarketAnalysis &analysis, int positionCount)
    {
        if (positionCount == 0)
            return "No positions to manage";

        switch (analysis.state)
        {
        case STATE_TRENDING_HIGH_VOL:
            return "💰 Take partial profits - tighten stops";
        case STATE_CHURN:
            return "⚠️ Consider closing positions - high volatility";
        case STATE_RANGING_HIGH_VOL:
            return "🎯 Manage carefully - potential stop hunts";
        case STATE_EXPANSION:
            return "⏳ Hold for trend confirmation";
        case STATE_TRENDING_LOW_VOL:
            return "✅ Hold and consider adding to position";
        case STATE_RANGING_LOW_VOL:
            return "📊 Manage at range boundaries";
        case STATE_CONTRACTION:
            return "🎯 Prepare for potential breakout";
        default:
            return "👁️ Monitor positions";
        }
    }

    string GetTradingSuggestion(MarketAnalysis &regimeAnalysis, DecisionEngineInterface &lastPackage)
    {
        if (!lastPackage.IsValid())
            return "⏳ Wait for package data";

        switch (regimeAnalysis.state)
        {
        case STATE_RANGING_LOW_VOL:
            return "📊 Fade range extremes - trade boundaries";
        case STATE_RANGING_HIGH_VOL:
            return "⚠️ Caution - high volatility range, tight stops";
        case STATE_CONTRACTION:
            return "🎯 Prepare for breakout - wait for signal";
        case STATE_EXPANSION:
            return "🚀 Test breakout entry - confirm direction";
        case STATE_TRENDING_LOW_VOL:
            return "✅ Follow trend - add on pullbacks";
        case STATE_TRENDING_HIGH_VOL:
            return "💰 Take profits - trend may be exhausted";
        case STATE_CHURN:
            return "⚠️ Avoid trading - wait for clarity";
        default:
            return "👁️ Monitor market conditions";
        }
    }

    string GetPositionInfoString()
    {
        int count = 0;
        double totalProfit = 0;
        double buyVolume = 0;
        double sellVolume = 0;

        for (int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0)
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);

                if (posSymbol == m_symbol && posMagic == m_magicNumber)
                {
                    count++;
                    totalProfit += PositionGetDouble(POSITION_PROFIT);

                    long posType = PositionGetInteger(POSITION_TYPE);
                    double volume = PositionGetDouble(POSITION_VOLUME);

                    if (posType == POSITION_TYPE_BUY)
                        buyVolume += volume;
                    else if (posType == POSITION_TYPE_SELL)
                        sellVolume += volume;
                }
            }
        }

        if (count == 0)
            return "No positions";

        string profitStr = StringFormat("$%.2f", totalProfit);

        return StringFormat("%d pos (B:%.2f|S:%.2f) P/L: %s",
                            count, buyVolume, sellVolume, profitStr);
    }

    string GetPackageAgeString(datetime packageTime)
    {
        if (packageTime == 0)
            return "N/A";

        int ageSeconds = (int)(TimeCurrent() - packageTime);

        if (ageSeconds < 60)
            return StringFormat("%ds", ageSeconds);
        else if (ageSeconds < 3600)
            return StringFormat("%dm %ds", ageSeconds / 60, ageSeconds % 60);
        else
            return StringFormat("%dh %dm", ageSeconds / 3600, (ageSeconds % 3600) / 60);
    }

    string GetTradingSessionInfo()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);

        if (dt.hour >= 0 && dt.hour < 5)
            return "🌏 Asian Session";
        else if (dt.hour >= 5 && dt.hour < 14)
            return "🇬🇧 London Session";
        else if (dt.hour >= 14 && dt.hour < 21)
            return "🇺🇸 US Session";
        else
            return "🌙 Overnight Session";
    }

    string TruncateString(string text, int maxLength)
    {
        if (StringLen(text) <= maxLength)
            return text;
        return StringSubstr(text, 0, maxLength) + "...";
    }

    string ColorText(string text, color clr)
    {
        // Note: Comment() doesn't support colors, but we'll format for future use
        return text;
    }
};

// ==================== GLOBAL HELPER FUNCTIONS ====================

string RegimeToStringHelper(ENUM_ROOT_REGIME regime)
{
    switch (regime)
    {
    case REGIME_TRENDING:
        return "TRENDING";
    case REGIME_RANGING:
        return "RANGING";
    case REGIME_UNKNOWN:
        return "UNKNOWN";
    default:
        return "UNKNOWN";
    }
}

string DecisionToStringHelper(DECISION_ACTION decision)
{
    switch (decision)
    {
    case ACTION_OPEN_BUY:
        return "✅ OPEN_BUY";
    case ACTION_OPEN_SELL:
        return "✅ OPEN_SELL";
    case ACTION_CLOSE_BUY:
        return "❌ CLOSE_BUY";
    case ACTION_CLOSE_SELL:
        return "❌ CLOSE_SELL";
    case ACTION_CLOSE_ALL:
        return "⚠️ CLOSE_ALL";
    case ACTION_HOLD:
        return "⏳ HOLD";
    case ACTION_WAITING_FOR_PACKAGE:
        return "🔄 WAITING";
    default:
        return "❓ UNKNOWN";
    }
}

string TimeframeToStringGlobal(ENUM_TIMEFRAMES timeframe)
{
    switch (timeframe)
    {
    case PERIOD_M1:
        return "M1";
    case PERIOD_M5:
        return "M5";
    case PERIOD_M15:
        return "M15";
    case PERIOD_M30:
        return "M30";
    case PERIOD_H1:
        return "H1";
    case PERIOD_H4:
        return "H4";
    case PERIOD_D1:
        return "D1";
    case PERIOD_W1:
        return "W1";
    case PERIOD_MN1:
        return "MN1";
    default:
        return IntegerToString(timeframe);
    }
}

// ==================== SIMPLE FUNCTION FOR BASIC DISPLAY ====================

// Function to create and display a simple dashboard
void ShowDashboard(string symbol,
                   int magicNumber,
                   PackageManager &pkgManager,
                   DecisionEngine &decisionEngineObj,
                   ENUM_ROOT_REGIME currentRegime,
                   bool forceUpdate = false)
{
    static DashboardManager dashboard;
    static bool initialized = false;
    static ENUM_ROOT_REGIME lastRegime = REGIME_UNKNOWN;

    // Initialize if needed
    if (!initialized)
    {
        if (dashboard.Initialize(symbol, magicNumber, GetPointer(pkgManager),
                                 GetPointer(decisionEngineObj), NULL))
        {
            initialized = true;
            Print("Dashboard initialized with Market Regime Detector");
        }
    }

    // Update if initialized
    if (initialized)
    {
        // Check if market regime has changed
        if (currentRegime != lastRegime)
        {
            string regimeStr = "";
            switch (currentRegime)
            {
            case REGIME_TRENDING:
                regimeStr = "TRENDING";
                break;
            case REGIME_RANGING:
                regimeStr = "RANGING";
                break;
            case REGIME_UNKNOWN:
                regimeStr = "UNKNOWN";
                break;
            default:
                regimeStr = "UNKNOWN";
                break;
            }
            Print("Market Regime updated: " + regimeStr);
            lastRegime = currentRegime;
        }

        dashboard.UpdateDisplay(forceUpdate);
    }
}

// Function to get just the display string (without showing it)
string GetDashboardString(string symbol,
                          int magicNumber,
                          PackageManager &pkgManager,
                          DecisionEngine &decisionEngineObj)
{
    // Create temporary dashboard for string generation
    DashboardManager tempDashboard;

    if (tempDashboard.Initialize(symbol, magicNumber, GetPointer(pkgManager),
                                 GetPointer(decisionEngineObj), NULL))
    {
        string display = "";

        // Build header
        display += "=== mk$ EA v3.11 - GOLD SPECIALIST ===\n";
        display += StringFormat("Time: %s | Symbol: %s\n",
                                TimeToString(TimeCurrent(), TIME_SECONDS), symbol);
        display += "\n";

        // Get regime analysis
        MarketRegimeDetector regimeDet(symbol, PERIOD_H1);
        MarketAnalysis analysis = regimeDet.GetMarketRegime();

        // Add regime info
        display += "─── MARKET REGIME ────────────────────\n";
        display += StringFormat("Current: %s | Confidence: %.0f%%\n",
                                MarketAnalysis::GetStateString(analysis.state),
                                analysis.confidence);
        display += StringFormat("Action: %s | Position: %s\n",
                                analysis.action,
                                GetPositionSizeStringHelper(analysis.positionSize));
        display += "\n";

        return display;
    }

    return "Dashboard unavailable";
}

string GetPositionSizeStringHelper(ENUM_POSITION_SIZE size)
{
    switch (size)
    {
    case SIZE_ZERO:
        return "ZERO";
    case SIZE_VERY_SMALL:
        return "VERY SMALL";
    case SIZE_SMALL:
        return "SMALL";
    case SIZE_MEDIUM:
        return "MEDIUM";
    case SIZE_LARGE:
        return "LARGE";
    default:
        return "UNKNOWN";
    }
}

#endif // DASHBOARD_MQH