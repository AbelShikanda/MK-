

this is my current display, but am currently not sure its displaying the right results:

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
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


so i want a more comprehensive and yet copmact display: inspired by the dicesion engine:
1. Avoid using emojis, better to use special characters if you even have to.
2. Let direction be described as LONG/SHORT and action or recommended action be BUY/SELL or B/S respectively
3. this is the final format i would like to display
  
|---------------- |     DASSHBOARD      | -----------------------------
Account Info    : Balance | Equity | Margin Levels % | Session 
Signals         : RootState (Ranging) | State (High Vol Range) --> Next Likely (Low VOl Range)
Trading Info    : Range/Trend Package | SHORT | Confidence %age
|---------------------these will be conditional------------------------ 
[if trending]   : MTF/B/80% | POI/S/30% | RSI/S/40% | MACD/B/30% | etc.. 
[else if range] : Range (Top&Bottom Prices) | Price Position in % |
[else if range] : COMP1/B/40% | COMP2/B/40% | COMP3/B/40% | etc..
|---------------------------------------------------------------------- 
Setup           : Position Size | SL | TP | RR 
Action          : Caution | High VOlatility | Small Stops | Fade/Follow-->[(in what direction)bull/bear?] 
Description     : State | Reasons | Additional Information (i basically wnat to know the exact reason a decision is made to secure or miss a position)
Decision        : Direction (like BUY) | 2 Positions | LONG
Statistics      : Decisions (like positions taken) | Accuracy (like how many ended up with net profit/ total positions taken) in %age
|----------------------------------------------------------------------













place settings on the top of the file


++++++++++++++++++++++
ONLY PROCEED IF THIS PROVIDED FILE NEEDS THESE THINGS 
PLEASE NOTE THAT BEFOR EVERYTHING, YOU SHOULD NOT CHANGE FUNCTIONSLTY, NAMES OF FUNCTIONS OR REMOVE FUNCTIONS
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
THE LOGGER AND COMMENT FILES AND UTILS ARE ALL STATIC AND STATELESS so use static functions for these
++++++++++++++++++++++
give me this file back with (ADD these instruction ONLY OF NECESSAYR, IF NOT JUST STOP AND TELL ME):
- prefer my files below for all your utils needs to avoid redundance.
- prefer the logs and chart comments privided also for uniformity and to avoid confusion.

I WANT:
- only essential logs, like those that would display incase of an errro. still minimal to avoid perfomance issues
- chart comments with scores. also minimal to avoid perfomance issues
- create these functions for it:
    CONSTRUCTOR - sets default values, reserving memory only.
    INITIALIZE() - Takes all dependencies as parameters, Creates actual resources, Sets up internal state, Returns bool and Uses a flag m_initialized
    DEINITIALIZE() - Closes/frees resources, Resets m_initialized flag, Does NOT delete the module itself (thats for the initializer)
    Plus event handlers: OnTick(), OnTimer(), OnTradeTransaction() - ONLY process if m_initialized = true, and only use initialized resources 
- a step-by-step Minimal EA Intergration example.
- a list of all the functions in the file in this manner
        File.mqh
        ++++++++++++++++++++++++++++
        function1(param1, param2)
        function2(param1, param2)
- Proper comments to be able to follow up on the code slowly





Update this module to:
	RETURN their own module-specific data structures
	ADD helper methods that return raw data, NOT TradePackage objects
	Modules should NOT know about TradePackage at all!
WHAT MODULES MUST PROVIDE:
	Their own data structures (e.g., MTFScore, POISignal)
	Analysis methods that return those structures
	NO TradePackage includes or references





+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR UTILS PLEASE PREFER MY FILES AND FUNCITONS:
all utils are static files with static functions only, no classes.
use as static functions only.
prefer this for all your utils needs to avoid redundance.

these are the functions in all my utils files
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
consider mathutils
++++++++++++++++++++++
PipsToPrice(string symbol, double pips)
PriceToPips(string symbol, double price)
CalculatePipValue(string symbol)
CalculatePositionRisk(string symbol, double entryPrice, double stopLoss, double lotSize)
CalculateRiskRewardRatio(double entryPrice, double stopLoss, double takeProfit)
CalculatePercentageChange(double oldValue, double newValue)
CalculateValueFromPercentage(double baseValue, double percentage)
CalculatePercentageOfValue(double part, double whole)
CalculateSimpleMovingAverage(const double &values[], int period)
CalculateWeightedAverage(const double &values[], const double &weights[])
CalculateATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift = 0)
CalculateStandardDeviation(const double &data[])
CalculateDistanceInPips(string symbol, double price1, double price2)
CalculateDistanceAsPercentage(double price1, double price2, double referencePrice)
NormalizePrice(string symbol, double price)
NormalizePriceToTick(string symbol, double price)
NormalizeLotSize(string symbol, double lotSize)
CalculateProfitInPips(string symbol, double entryPrice, double exitPrice, bool isBuy)
CalculateProfitInMoney(string symbol, double entryPrice, double exitPrice, double lotSize, bool isBuy)
CalculateWinProbability(int totalTrades, int winningTrades)
CalculateExpectedValue(double winRatePercent, double avgWin, double avgLoss)
CalculateKellyCriterion(double winRatePercent, double avgWinToLossRatio)
CalculateFibonacciLevel(double high, double low, double level)
CalculateGeometricMean(const double &values[])
CalculateAnnualizedReturn(double totalReturnPercent, double days)
CalculateCompoundedGrowth(double initialAmount, double ratePercent, int periods)
IsValidPrice(string symbol, double price)
IsValidLotSize(string symbol, double lotSize)
CalculatePositionSizeByRisk(string symbol, double entryPrice, double stopLoss, double riskPercent, double accountBalance)
CalculatePositionSize() find out params in indicator file for atr based position sizing
CalculateBreakevenPrice(double entryPrice, bool isBuy, double spreadPips)
CalculateMarginRequired(string symbol, double lotSize, int orderType = ORDER_TYPE_BUY)
CalculateSwap(string symbol, double lotSize, int orderType, int days = 1)
RoundToTick(string symbol, double value)
CalculateCommission(string symbol, double lotSize, double commissionPerLot = 0)
CalculateTotalTradeCost(string symbol, double lotSize, bool isBuy, double commissionPerLot = 0)
CalculatePositionScore()

consider errorutils
++++++++++++++++++++++
CheckError(int errorCode)
GetErrorDescription(int errorCode)
HandleOrderError(int errorCode, Logger &logger)
HandleOrderError(int errorCode)
HandleMarketError(int errorCode, Logger &logger)
HandleMarketError(int errorCode)
GetLastError(Logger &logger)
GetLastError()
CheckErrorWithTime(int errorCode, Logger &logger)
IsRecoverableError(int errorCode)
IsFatalError(int errorCode)
GetRecoverySuggestion(int errorCode)
ResetLastError()
GetErrorDetails(int errorCode)
LogErrorWithDetails(int errorCode, Logger &logger, string context)
HandleErrorWithRetry(int errorCode, Logger &logger, int maxRetries)

consider loggerutils
++++++++++++++++++++++
GetTimestamp()
GetTimeOnly()
BuildMessage(string module, string timestamp, string reason)
LogInternal(string module, string reason, bool logToFile = true, bool logToConsole = true)
Initialize(string fileName = "", bool logToFile = true, bool logToConsole = true)
Shutdown()
Log(string module, string reason, bool logToFile = true, bool logToConsole = true)
LogError(string module, string reason, int errorCode = 0)
LogTrade(string module, string symbol, string operation, double volume, double price = 0.0)
LogFast(string module, string reason)
LogUltraFast(const string &module, const string &reason)
LogTradeFast(const string &module, const string &symbol, const string &operation, double volume)
IsFileLoggingAvailable()
GetLogFileName()
GetFileHandleStatus()
LogMemoryUsage(string module)
Flush()
LogWithTimestamp(string module, string reason, datetime customTime)

consider configutils
++++++++++++++++++++++
ReadDatetime(string key, datetime defaultValue)
ReadColor(string key, color defaultValue)
ReadEnum(string key, int defaultValue)
ReadInt(string key, int defaultValue, string section)
ReadDouble(string key, double defaultValue, string section)
ReadBool(string key, bool defaultValue, string section)
ReadString(string key, string defaultValue, string section)
WriteInt(string key, int value, string section)
WriteDouble(string key, double value, string section)
WriteBool(string key, bool value, string section)
WriteString(string key, string value, string section)
WriteDatetime(string key, datetime value, string section)
WriteColor(string key, color value, string section)
ConfigExists()
GetConfigPath(bool common)

consider timeutils
++++++++++++++++++++++
IsTradingSession(const string symbol = NULL)
GetTradingSession(const string symbol, datetime &startTime, datetime &endTime)
IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
IsMarketOpen(const string symbol = NULL)
IsEndOfMonth(const string symbol = NULL)
IsStartOfMonth(const string symbol = NULL)
MinutesUntilSession(const string symbol = NULL, bool nextDay = false)
IsHighVolatilityPeriod()
IsTimeInRange(int startHour, int startMinute, int endHour, int endMinute)
TradingDaysBetween(datetime startDate, datetime endDate)
IsPreMarket(const string symbol = NULL)
IsAfterHours(const string symbol = NULL)
NextTradingDay(datetime fromDate = 0)
TimeOfDayToString()
IsRolloverTime()
GetTimestamp()
TimeframeToMinutes(ENUM_TIMEFRAMES tf)
GetBarOpenTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
GetBarCloseTime(const string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


















+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR LOGS PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Prefer my logger functions instead, only where necessary LOGGERS ARE STATIC SO USE STATIC CALLS IE Logger::Log(...)
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
application example: in a file always wrap inside of a debug true false.
// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED = true;

// Simple debug function using Logger
void DebugLogFile(string context, string message) {
   if(DEBUG_ENABLED) {
      Logger::Log(log);
   }
}

//then all the logs and wrapped around the degub
// not chart comments.

so

// Initialize with different configurations
Logger::Initialize();                          // Default: file logging ON, chart ON, 2s updates
Logger::Initialize("MyBot.log", true, true, 1); // Custom settings
Logger::Initialize("", false, true, 5);        // No file logging, chart only, 5s updates
Logger::Shutdown();                           // Clean shutdown
// Runtime control
Logger::EnableChart(false);                   // Disable chart updates temporarily
Logger::SetChartFrequency(3);                 // Change update frequency (seconds)
Logger::ClearChart();                         // Clear all chart comments
Logger::Flush();                              // Flush file buffer
// Status checks
bool canLog = Logger::IsFileLoggingAvailable(); // Check if file is open
string fileName = Logger::GetLogFileName();   // Get current log filename
bool chartOn = Logger::IsChartEnabled();      // Check chart status
// Standard logging (console + file)
Logger::Log("Module", "Message");
Logger::Log("Strategy", "Entry signal detected", true, true); // logToFile, logToConsole
// Error logging
Logger::LogError("API", "Failed to connect");
Logger::LogError("Trade", "Order rejected", 10013); // With error code
// Trade logging
Logger::LogTrade("Portfolio", "EURUSD", "BUY", 0.1, 1.08542); // With price
Logger::LogTrade("Risk", "GBPUSD", "SELL", 0.05);             // Without price
// Performance logging
Logger::LogMemoryUsage("System");            // Log memory usage (MQL5 only)
// Faster with minimal formatting
Logger::LogFast("Module", "Fast message");  // Quick timestamp
Logger::LogUltraFast("Ticker", "Price update: 1.0850"); // No timestamp
// Fast trade logging
Logger::LogTradeFast("Scalper", "EURUSD", "BUY", 0.1);
// Custom timestamp logging
Logger::LogWithTimestamp("Backtest", "Strategy executed", D'2024.01.15 10:30:00');
// Single symbol score display
Logger::ShowScoreFast("EURUSD", 0.85, "BUY", 0.9);
Logger::ShowScoreFast("GBPUSD", 0.42, "SELL", 0.6);
Logger::ShowScoreFast("USDJPY", 0.15, "HOLD", 0.3); // Low score example
Logger::ShowScoreFast("XAUUSD", 0.92, "BUY", 0.95); // High confidence
// Trading decisions
Logger::ShowDecisionFast("EURUSD", 1, 0.92, "Strong bullish divergence on 4H");
Logger::ShowDecisionFast("GBPUSD", -1, 0.75, "Bearish breakout below support");
Logger::ShowDecisionFast("AUDUSD", 0, 0.60, "Waiting for confirmation"); // HOLD decision
// Portfolio overviews
string symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "XAUUSD"};
double scores[] = {0.85, 0.42, 0.73, 0.61, 0.29, 0.92};
int directions[] = {1, -1, 0, 1, -1, 1}; // 1=BUY, -1=SELL, 0=HOLD
Logger::ShowPortfolioFast(symbols, scores, directions);
// Risk metrics display
Logger::ShowRiskMetrics(3.2, 1.8, 1.4, 5); // risk%, drawdown%, sharpe, positions
Logger::ShowRiskMetrics(5.7, 3.2, 0.8, 8); // High risk example
Logger::ShowRiskMetrics(1.5, 0.9, 2.1, 3); // Low risk example
// Mixed use cases
string forexPairs[] = {"EURUSD", "GBPUSD", "USDJPY"};
double forexScores[] = {0.85, 0.42, 0.73};
int forexDirections[] = {1, -1, 0};
Logger::ShowPortfolioFast(forexPairs, forexScores, forexDirections);
// Backtesting scenarios
Logger::LogWithTimestamp("Backtest", "Entry: BUY EURUSD @ 1.0850", D'2024.01.15 10:30:00');
Logger::LogWithTimestamp("Backtest", "Exit: SELL EURUSD @ 1.0900 (+50 pips)", D'2024.01.15 14:45:00');
// Multi-timeframe analysis
Logger::Log("Analysis", "4H: Bullish | 1H: Neutral | 15M: Bearish");
Logger::ShowDecisionFast("EURUSD", 1, 0.82, "4H trend up, 1H pullback to support");
// Correlation analysis
Logger::Log("Correlation", "EURUSD-GBPUSD correlation: 0.72 (High)");
Logger::ShowScoreFast("EURUSD", 0.85, "BUY", 0.9);
Logger::ShowScoreFast("GBPUSD", 0.65, "HOLD", 0.7); // Lower due to correlation
// Position sizing and risk
Logger::Log("Risk", "Position size: 0.15 lots, Risk: $150 (1.5% of account)");
Logger::LogTrade("Execution", "EURUSD", "BUY", 0.15, 1.08542);
Logger::ShowRiskMetrics(1.5, 2.1, 1.2, 4);
// Performance tracking
Logger::Log("Performance", "Win Rate: 65%, Profit Factor: 1.8, Avg Win: $85");
Logger::LogMemoryUsage("Monitor");
// News/Event reactions
Logger::Log("News", "NFP release in 15 minutes - reducing position sizes");
Logger::ShowDecisionFast("USD pairs", 0, 0.40, "Waiting for NFP data");
// System alerts
Logger::LogError("System", "High latency detected: 250ms");
Logger::LogError("Connection", "Feed disconnected", 4065);
Logger::ShowDecisionFast("ALL", 0, 0.10, "Connection issues - pausing trading");
// Portfolio rebalancing
Logger::Log("Rebalance", "Closing 2 positions to reduce correlation risk");
Logger::LogTrade("Rebalance", "EURUSD", "CLOSE", 0.1);
Logger::LogTrade("Rebalance", "GBPUSD", "CLOSE", 0.05);
Logger::ShowRiskMetrics(2.8, 1.5, 1.6, 3); // Updated risk after rebalance
// Strategy parameter optimization
Logger::Log("Optimization", "Testing params: MA1=10, MA2=20, StopLoss=50");
Logger::ShowScoreFast("EURUSD", 0.78, "BUY", 0.8);
Logger::Log("Optimization", "Testing params: MA1=14, MA2=28, StopLoss=60");
Logger::ShowScoreFast("EURUSD", 0.82, "BUY", 0.85);
// Market condition analysis
Logger::Log("Market", "High volatility detected: ATR = 0.0085");
Logger::ShowDecisionFast("EURUSD", 1, 0.68, "High vol - using wider stops");
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


























+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
give the provided file back using this file as reference to build it properly.
the indicator manager primary needs to be able to provide all necessary indicator values.
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
IndicatorManager(string symbol = NULL)
~IndicatorManager()
Initialize()
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
GetMAValues(ENUM_TIMEFRAMES tf, double &ma_fast, double &ma_slow, double &ma_medium, int shift = 0)
GetRSI(ENUM_TIMEFRAMES tf, int shift = 0)
GetMACDValues(ENUM_TIMEFRAMES tf, double &macd_main, double &macd_signal, int shift = 0)
GetADXValues(ENUM_TIMEFRAMES tf, double &adx, double &plus_di, double &minus_di, int shift = 0)
GetStochasticValues(ENUM_TIMEFRAMES tf, double &stoch_main, double &stoch_signal, int shift = 0)
GetATR(ENUM_TIMEFRAMES tf, int shift = 0)
GetVolume(ENUM_TIMEFRAMES tf, int shift = 0)
GetBollingerBandsValues(ENUM_TIMEFRAMES tf, double &upper, double &middle, double &lower, int shift = 0)
IsTrendBullish(ENUM_TIMEFRAMES tf)
IsTrendBearish(ENUM_TIMEFRAMES tf)
IsOverbought(ENUM_TIMEFRAMES tf)
IsOversold(ENUM_TIMEFRAMES tf)
IsStrongTrend(ENUM_TIMEFRAMES tf, int threshold = 25)
GetADXTrendDirection(ENUM_TIMEFRAMES tf)
GetMACDCrossover(ENUM_TIMEFRAMES tf)
GetMultiTimeframeConfirmation(int &bullish_tf_count, int &bearish_tf_count)
GetBBandsPosition(ENUM_TIMEFRAMES tf, double price)
CalculatePositionSize(double risk_percent, double stop_loss_pips, ENUM_TIMEFRAMES tf = PERIOD_H1)
GetMarketScore()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++



















+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS TRADEPACKAGE PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR TRADING PACKAGE PLEASE PREFER MY FILES AND FUNCITONS:
give me a way to populate the tradepackage given the file provided
rebuild this file to be able to populate my  tradepackage properly.
the trade package primary needs a re bull and bear bias and score and the confidence in that score
then any unique variables that the file can profide.
this functions constitute the trade package file
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
TradePackage.mqh
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
File-level functions:
DebugLogTP(string context, string message)

Struct ComponentDisplay:
ComponentDisplay()
ComponentDisplay(string n, string d, double s, double c, double w, bool a, string dt = "")
string GetFormattedLine(bool useIcons = true, bool showDetails = false)
string GetDirectionIcon(string dir, bool useIcons)

Struct DirectionAnalysis:
string GetDisplayString() const

Struct TradeSignal:
string GetOrderTypeString() const
string GetSimpleSignal() const

Struct TradeSetup:
bool IsValid() const
string GetRRRString() const

Struct MTFData:
string GetAlignmentString() const

Struct RiskManagement:
string GetSettingsString() const

Struct POISignal (nested in TradePackage):
POISignal()
string GetSimpleSignal() const
string GetConfidenceString() const
bool IsActionable() const
string GetDisplayString() const

Struct TradePackage:
TradePackage()
void CalculateWeightedScore()
double CalculateOverallConfidence()
void NormalizeWeights()
bool ValidatePackage(double minConfidence = 60.0)
void DisplayTabular()
string GenerateTabularDisplay()
static void DisplayMultiSymbol(const TradePackage &packages[], bool showAllComponents = false)
string GetTabularHeader()
string GetSymbolHeader() const
void CollectComponents(ComponentDisplay &components[]) const
string GetOverallSummary()
string GetSetupInfo()
string GetValidationStatus()
string GetMTFDirection() const
string GetSignalIcon() const
string GetDirectionIcon(string dir, bool useIcons)
void ConfigureDisplay(bool tabularFormat = true, bool useColors = true, bool showInactive = false, bool showDetails = false)
void SetMaxComponentsPerLine(int max)
void DisplayOnChart()
string GenerateChartDisplay()
void LogCompletePackage()
string GenerateLogEntry()
void LogKeyMetrics()
void CalculatePositionSize(double accountBalance)
void CalculateRiskReward()
string GetSummary()
bool HasMTFData() const
bool HasSetup() const
double GetPositionSizeMultiplier() const
int GetTradeDecision() const
double GetConfidenceDecimal() const
void Display()
string RepeatString(string str, int count)
void SetDecisionEngine(DecisionEngine* de)
bool ProcessAndExecute()
bool UpdateAndExecute()
bool Validate() const
int StringCount(const string text, const string search)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




































+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MTFANALYZER MANAGEMENT PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
MTFAnalyser() - Constructor, sets default values
Initialize(symbol, primaryTF, indicatorManager) - Initializes the analyzer with dependencies
Deinitialize() - Cleans up resources
OnTick() - Handles tick events
OnTimer() - Handles timer events
OnTradeTransaction(trans, request, result) - Handles trade transaction events
AnalyzeMultiTimeframe(symbol) - Analyzes alignment across multiple timeframes
CheckAlignment(symbol, minScore) - Checks if timeframes are aligned above minimum score
GetDominantTF(symbol) - Gets the timeframe with strongest trend
IsInitialized() - Returns initialization status
GetSymbol() - Gets current symbol
GetPrimaryTF() - Gets primary timeframe
AnalyzeTrend(symbol, timeframe) - PRIVATE: Analyzes trend for specific timeframe
GetEMA(symbol, timeframe, period) - PRIVATE: Gets EMA value
CalculateTrendStrength(symbol, timeframe) - PRIVATE: Calculates trend strength using ADX
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR POSITION MANAGER PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PositionManager::OpenPosition(symbol, isBuy, comment, magic, stopMethod, riskPercent, rrRatio, reason)
PositionManager::OpenPositionWithTradePackage(symbol, isBuy, package)
PositionManager::CloseAllPositions(symbol, magic, reason)
PositionManager::SmartClosePosition(priority, magic, outClosedSymbol)
PositionManager::GetPositionCount(symbol, magic)
PositionManager::GetTotalProfit(symbol, magic)
PositionManager::UpdateTrailingStops(trailMethod, magic)
PositionManager::CheckMargin(symbol, lotSize, safetyBuffer)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR DECISION ENGINE PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
DecisionEngine() - Constructor
~DecisionEngine() - Destructor
Initialize(PositionManager, RiskManager, engineComment, engineMagicBase, slippage, chartUpdateSeconds)
Deinitialize()
MakeDecisionFromPackage(symbol, package)
ExecuteDecision(symbol, decision, package)
AddSymbol(symbol, params)
RemoveSymbol(symbol)
HasSymbol(symbol)
GetSymbolCount()
SetSymbolParameters(symbol, params)
SetTradePackageFunction(func)
SetDebugMode(debug)
SetUseComponentWeights(use)
SetMinConfidenceThreshold(threshold)
SetChartUpdateSeconds(seconds)
GetSymbolParameters(symbol)
GetLastPackage(symbol)
GetCurrentDecision(symbol)
GetDecisionAccuracy()
GetStatus()
DecisionToString(decision)
ResetStatistics()
QuickInitialize(symbol, buyThreshold, sellThreshold, riskPercent, cooldownMinutes, maxPositions)
OnTick()
OnTimer()
OnTradeTransaction(trans, request, result)
UpdateChartDisplay()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
MarketData(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
double GetBid(string symbol = NULL)
double GetAsk(string symbol = NULL)
double GetSpread(string symbol = NULL)
MqlTick GetTick(string symbol = NULL)
bool GetOHLC(string symbol, ENUM_TIMEFRAMES timeframe, int shift, double &open, double &high, double &low, double &close)
long GetVolume(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, int shift = 0)
long GetVolume(string symbol = NULL)
bool IsFresh()
void Refresh()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR POI PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
POIModule() - Constructor
Initialize(string symbol, bool drawOnChart = false, double defaultBuffer = 2.0)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
GetPOIScore(double currentPrice, ENUM_POI_TYPE &outZoneType, double &outDistanceToZone)
IsInsidePOIZone(double currentPrice, ENUM_POI_TYPE &outZoneType)
GetNearestZone(double currentPrice, POIZone &outZone)
IsInitialized()
GetZoneCount()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR VOLUME PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VolumeModule() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES analysisTF = PERIOD_H1)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
AnalyzeVolume(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetVolumeScore(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
HasVolumeDivergence(bool isBuyTrade, const double &prices, int period = 5)
IsInitialized()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR RSI PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
RSIModule() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES analysisTF = PERIOD_H1, 
          int rsiPeriod = 14, ENUM_APPLIED_PRICE appliedPrice = PRICE_CLOSE)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(...)
AnalyzeRSI(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetRSIScore(bool isBuyTrade, bool isInsidePOI, double distanceToPOI, double poiScore)
GetCurrentRSIValue()
GetRSITrend(int barsToCheck = 5)
HasFailureSwing(bool isBuyTrade)
IsInitialized()
GetAnalysisTimeframe()
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR RISK MANAGER PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
RiskCalculator::CanOpenTrade(maxDailyLossPercent, maxDrawdownPercent)
RiskCalculator::CalculatePositionSize(symbol, entryPrice, stopLoss, riskPercent)
RiskCalculator::CalculatePositionSizeWithConfidence(symbol, entryPrice, stopLoss, confidence, baseRiskPercent)
RiskCalculator::CalculateStopLoss(symbol, isBuy, entryPrice, method, atrMultiplier)
RiskCalculator::CalculateTakeProfit(symbol, isBuy, entryPrice, stopLoss, rrRatio)
RiskCalculator::CalculateTakeProfitWithConfidence(symbol, isBuy, entryPrice, stopLoss, confidence, baseRR)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR VolumeModule.mqh PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VolumeModule() - Constructor, sets default values
~VolumeModule() - Destructor, calls Deinitialize()
Initialize(IndicatorManager* indicatorMgr, string symbol = NULL) - Initialize module
Deinitialize() - Clean up resources
Analyze(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20, int fastPeriod = 5) - Comprehensive analysis
GetVolumeScore(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, bool isBullishMove = true) - Simplified 0-100 score
IsVolumeConfirming(ENUM_TIMEFRAMES tf, bool expectingBullish) - Check volume confirmation
HasSpike(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, double threshold = 2.0) - Check for volume spike
GetStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get volume status string
HasDivergence(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int period = 5) - Check for divergence
IsClimaxVolume(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int lookback = 20) - Check for climax
SetSpikeThreshold(double threshold) - Set spike threshold
SetClimaxThreshold(double threshold) - Set climax threshold
SetDefaultTimeframe(ENUM_TIMEFRAMES tf) - Set default timeframe
IsInitialized() - Check if initialized
GetSymbol() - Get symbol
ConfigureTradePackageIntegration(bool enable = true, double bullWeight = 0.6, double bearWeight = 0.6) - Configure TP integration
DisplayOnChart(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int corner = 2, int x = 10, int y = 20) - Display on chart
GetTradePackageComponent(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get ComponentDisplay for TradePackage
GetVolumeScoreForTradePackage(ENUM_TIMEFRAMES tf = PERIOD_CURRENT, string expectedDirection = "") - Get TP-formatted score
GetDirectionalBias(double &bullScore, double &bearScore, double &overallConfidence, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get bias scores
GetTradeRecommendation(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get trade recommendation
GetConfirmationStatus(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) - Get confirmation status
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR SimpleRSI.mqh PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
SimpleRSI(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1, int period = 14, IndicatorManager* indicatorMgr = NULL)
RSIBias GetBiasAndConfidence(int lookback = 20)
void PopulateTradePackage(TradePackage &package, int lookback = 20)
ComponentDisplay GetComponentDisplay(int lookback = 15)
void AddToComponentsArray(ComponentDisplay &components[], int lookback = 15)
bool IsBullishBias(int lookback = 10)
bool IsBearishBias(int lookback = 10)
double GetNetBiasScore(int lookback = 10)
double GetConfidence(int lookback = 10)
double GetCurrentRSI()
void SetIndicatorManager(IndicatorManager* indicatorMgr)
bool IsUsingIndicatorManager() const

UltraSimpleRSI (Static Class)
++++++++++++++++++++++++++++
static void GetBias(string symbol, ENUM_TIMEFRAMES tf, double &biasScore, double &confidence, IndicatorManager* indicatorMgr = NULL)
static bool IsBullish(string symbol, ENUM_TIMEFRAMES tf, IndicatorManager* indicatorMgr = NULL)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
CandlestickPatterns.mqh
+++++++++++++++++++++++++++
CandlestickPatternAnalyzer() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars = 100)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction()
AnalyzeCurrentPattern(int shift = 1)
GetPatternScore(int shift = 1)
GetPatternSignal(int shift = 1)
IsHammer(const CandleData &candle)
IsInvertedHammer(const CandleData &candle)
IsShootingStar(const CandleData &candle)
IsHangingMan(const CandleData &candle)
IsSpinningTop(const CandleData &candle)
IsMarubozuBullish(const CandleData &candle)
IsMarubozuBearish(const CandleData &candle)
IsDoji(const CandleData &candle, ENUM_CANDLE_PATTERN &dojiType)
CheckBullishEngulfing(CandleData &candle1, CandleData &candle2)
CheckBearishEngulfing(CandleData &candle1, CandleData &candle2)
CheckHarami(CandleData &candle1, CandleData &candle2, bool bullish)
CheckPiercingLine(CandleData &candle1, CandleData &candle2)
CheckDarkCloudCover(CandleData &candle1, CandleData &candle2)
CheckMorningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckEveningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeWhiteSoldiers(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeBlackCrows(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckSingleCandlePattern(CandleData &candle)
CheckTwoCandlePattern(CandleData &candle1, CandleData &candle2)
CheckThreeCandlePattern(CandleData &candle1, CandleData &candle2, CandleData &candle3)
GetCandleData(int shift)
GetDojiDescription(ENUM_CANDLE_PATTERN dojiType)
PatternToString(ENUM_CANDLE_PATTERN pattern)
IsInitialized()
GetSymbol()
GetTimeframe()
HasStrongPattern(int shift = 1)
GetSimpleDirection(int shift = 1)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
CandlestickPatterns.mqh
++++++++++++++++++++++++++++
CandlestickPatternAnalyzer() - Constructor
Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars = 100)
Deinitialize()
OnTick()
OnTimer()
OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
AnalyzeCurrentPattern(int shift = 1)
GetPatternScore(int shift = 1)
GetPatternSignal(int shift = 1)
IsHammer(const CandleData &candle)
IsInvertedHammer(const CandleData &candle)
IsShootingStar(const CandleData &candle)
IsHangingMan(const CandleData &candle)
IsSpinningTop(const CandleData &candle)
IsMarubozuBullish(const CandleData &candle)
IsMarubozuBearish(const CandleData &candle)
IsDoji(const CandleData &candle, ENUM_CANDLE_PATTERN &dojiType)
CheckBullishEngulfing(CandleData &candle1, CandleData &candle2)
CheckBearishEngulfing(CandleData &candle1, CandleData &candle2)
CheckHarami(CandleData &candle1, CandleData &candle2, bool bullish)
CheckPiercingLine(CandleData &candle1, CandleData &candle2)
CheckDarkCloudCover(CandleData &candle1, CandleData &candle2)
CheckMorningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckEveningStar(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeWhiteSoldiers(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckThreeBlackCrows(CandleData &candle1, CandleData &candle2, CandleData &candle3)
CheckSingleCandlePattern(CandleData &candle)
CheckTwoCandlePattern(CandleData &candle1, CandleData &candle2)
CheckThreeCandlePattern(CandleData &candle1, CandleData &candle2, CandleData &candle3)
UpdateChartComments()
ShowScoreOnChart(const PatternResult &result)
GetCandleData(int shift)
GetDojiDescription(ENUM_CANDLE_PATTERN dojiType)
PatternToString(ENUM_CANDLE_PATTERN pattern)
TimeframeToString(ENUM_TIMEFRAMES tf)
IsInitialized()
GetSymbol()
GetTimeframe()
HasStrongPattern(int shift = 1)
GetSimpleDirection(int shift = 1)
SetDebugEnabled(bool enabled)
SetChartUpdateFrequency(int seconds)

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
ONLY PROCEED IF THIS FINE NEEDS INDICATORS PLEASE PREFER MY FILES AND FUNCITONS:
AT THE TOP AFTER THE FILE NAME LET IT STATE THAT ITS ALREADY INTERGRATED THIS IF YOU THIS PROCESS IS APPLICABLE
FOR MARKET DATA PLEASE PREFER MY FILES AND FUNCITONS:
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




BUILDING A UTIL FILE WITH STATIC, STATELESS FUNCTIONS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
make this file static and make sure all functions are stateless
add the necessary time functions i may have missed if any 
make all functions static and mql5 friendly
make sure functions are stateless




FILE PERMORMANCE OPTIMIZATION INSTRUCTIONS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Please optimize the performance of this MQL5 code by removing 
excessive logging, debugging prints, and unnecessary console output 
while preserving essential error messages and critical information. 

Follow these guidelines:
- Remove ALL debug prints (Print()) from tight loops like OnTick(), OnTimer(), and position update functions
- Keep only essential logs for:
    - Initialization/deinitialization
    - Trade execution (open/close/modify)
    - Error conditions
    - Major state changes (emergency stop, risk level changes)
    - Configuration changes
- Optimize logging frequency:
    - Replace frequent prints with periodic summaries (e.g., every 1 minutes)
    - Use static timers to limit print frequency
    - Aggregate multiple messages into single prints
- Remove redundant information:
    - Dont log the same status repeatedly
    - Combine related information into single messages
    - Remove timestamp prefixes if MT5 already adds them
- Preserve critical information:
    - Keep trade execution confirmations
    - Keep error messages and warnings
    - Keep risk limit violations
    - Keep account/position state changes

ALSO:
- Cache position data to avoid repeated PositionGet calls in loops
- Use PrintFormat() instead of multiple Print() calls
- Remove logging from hot paths (functions called every tick)
- Add log levels enum RESOURCE_MANAGER
        {
            OBSERVE,
            AUTHORIZE,
            WARN,
            ENFORCE,
            AUDIT
        };
    with configurable verbosity
- Use static variables to track last log time and prevent spamming
- Move detailed logs to separate debug functions that are conditionally called
- Batch similar messages into periodic status reports instead of tick-by-tick logging
- Focus on the most performance-critical areas:
    - OnTick() and OnTimer() methods
    - Position update loops
    - Indicator calculations
    - Market data processing functions**

    
DO NOT CHANGE FUNCTIONALITY PLEASE
USE MINIMAL CODE CHANGE



CREATE AN MQL5 CHART COMMENT DASHBOARD
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Create an optimized MQL5 chart comment file (.mqh) that displays essential account and trading information with maximum performance. This should be a visual dashboard that traders can place on their charts for at-a-glance monitoring.

## PERFORMANCE REQUIREMENTS:
- **Ultra-efficient updates**: Update only when values change, not every tick
- **Minimal CPU usage**: Use caching, static variables, and update throttling
- **Zero tight-loop operations**: No heavy calculations in OnTick()
- **Memory efficient**: Reuse string buffers, no string concatenation in loops
- **Clean rendering**: No flickering, smooth updates

## ESSENTIAL DISPLAY ELEMENTS (Creative & Visual):

### 1. ACCOUNT STATUS PANEL (Top Left)
```
╔══════════════════════════════════╗
║        ACCOUNT STATUS            ║
╠══════════════════════════════════╣
║ Balance:     $25,430.75  📊      ║
║ Equity:      $26,120.50  ↗️      ║
║ Margin:      $1,230.75   🔒      ║
║ Free Margin: $24,889.75  ✅      ║
║ Margin Level: 2,123%     🛡️      ║
║ Daily P/L:   +$689.75    📈      ║
╚══════════════════════════════════╝
```

### 2. TRADING SESSION INFO (Top Right)
```
╔══════════════════════════════════╗
║       TRADING SESSION            ║
╠══════════════════════════════════╣
║ Session:    LONDON/NY OVERLAP    ║
║ Time Left:  02:15:43     ⏳      ║
║ Volatility: HIGH          🌊      ║
║ Spread:     1.2 pips     ⚡      ║
║ Trend:      BULLISH      ↗️      ║
║ Market Hours: 09:00-17:00🕐      ║
╚══════════════════════════════════╝
```

### 3. POSITIONS OVERVIEW (Center Left)
```
╔══════════════════════════════════╗
║      ACTIVE POSITIONS            ║
╠══════════════════════════════════╣
║ EUR/USD:   BUY  1.0950  +$320    ║
║            SL: 1.0900   TP:1.1050║
║            R:R 3.2:1    🔥       ║
╠══════════════════════════════════╣
║ GBP/USD:   SELL 1.2650  -$45     ║
║            SL: 1.2700   TP:1.2550║
║            R:R 2.0:1    ⚠️       ║
╠══════════════════════════════════╣
║ TOTAL:     2 positions  +$275    ║
║            Risk: 1.8%    ✅      ║
╚══════════════════════════════════╝
```

### 4. PERFORMANCE METRICS (Center Right)
```
╔══════════════════════════════════╗
║    PERFORMANCE METRICS           ║
╠══════════════════════════════════╣
║ Win Rate:       68%      🎯      ║
║ Profit Factor:  2.4      💎      ║
║ Avg Win:       +$420     🚀      ║
║ Avg Loss:      -$180     🛡️      ║
║ Max DD:        -$1,200   ⚠️      ║
║ Recovery:      85%       📈      ║
║ Consecutive:   4 wins    🔥      ║
╚══════════════════════════════════╝
```

### 5. RISK MANAGEMENT (Bottom Left)
```
╔══════════════════════════════════╗
║      RISK MANAGEMENT             ║
╠══════════════════════════════════╣
║ Max Risk/Trade:   2.0%   ✅      ║
║ Daily Loss Limit: 5.0%   🛡️      ║
║ Max Positions:    5      🎯      ║
║ Current Risk:     1.8%   📊      ║
║ Available Risk:   3.2%   💰      ║
║ Volatility Adj:   85%    🌊      ║
║ Safety Level:     GREEN  ✅      ║
╚══════════════════════════════════╝
```

### 6. MARKET CONDITIONS (Bottom Right)
```
╔══════════════════════════════════╗
║     MARKET CONDITIONS            ║
╠══════════════════════════════════╣
║ Trend Strength:  85%     ↗️      ║
║ Market Phase:   ACCUMULATION    ║
║ Volatility:      HIGH    🌊      ║
║ Liquidity:       GOOD    💧      ║
║ News Impact:     MEDIUM  📰      ║
║ Bias:           BULLISH  🐂      ║
║ Confidence:      78%     ✅      ║
╚══════════════════════════════════╝
```

OnTick() (every 10s)
    ↓
IndicatorManager.UpdateAllModulesAndExecute()
    ↓
[Modules update TradePackage fields]
    ↓
TradePackage.UpdateAndExecute()
    ↓
TradePackage.ProcessAndExecute() → DecisionEngine → Trade Execution




















































































































































//+------------------------------------------------------------------+
//|                                              MarketRegime.mqh    |
//|           Advanced Market Regime & Lifecycle Detection System   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.00"
#property strict

#include <Math\Stat\Math.mqh>
#include <ChartObjects\ChartObjectsLines.mqh>
#include <ChartObjects\ChartObjectsShapes.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

//+------------------------------------------------------------------+
//| Market Regime Types                                             |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
    REGIME_TRENDING_UP,   // Strong uptrend
    REGIME_TRENDING_DOWN, // Strong downtrend
    REGIME_RANGING,       // Sideways/consolidation
    REGIME_UNKNOWN        // Unable to determine
};

//+------------------------------------------------------------------+
//| Market Lifecycle States                                         |
//+------------------------------------------------------------------+
enum ENUM_MARKET_LIFECYCLE
{
    LIFECYCLE_RANGE_FORMING,     // Consolidation forming (needs validation)
    LIFECYCLE_RANGE_ACTIVE,      // Validated range/consolidation
    LIFECYCLE_BREAKOUT_DETECTED, // Range broken, initial breakout
    LIFECYCLE_TREND_CONFIRMED,   // Breakout confirmed, trend established
    LIFECYCLE_PULLBACK_FORMING,  // Trend pullback forming
    LIFECYCLE_PULLBACK_ACTIVE,   // Validated pullback range
    LIFECYCLE_TREND_RESUMING,    // Pullback broken, trend resuming
    LIFECYCLE_TREND_WEAKENING,   // Trend losing momentum
    LIFECYCLE_UNKNOWN
};

//+------------------------------------------------------------------+
//| Regime Detection Result                                         |
//+------------------------------------------------------------------+
struct RegimeResult
{
    ENUM_MARKET_REGIME regime; // Primary regime classification
    double confidence;         // 0-100% confidence in detection
    double trendStrength;      // -100 to +100 (negative=bearish, positive=bullish)
    double rangeStrength;      // 0-100 strength of ranging conditions
    string description;        // Human-readable description

    // Constructor
    RegimeResult()
    {
        regime = REGIME_UNKNOWN;
        confidence = 0.0;
        trendStrength = 0.0;
        rangeStrength = 0.0;
        description = "Not analyzed";
    }

    // String representation
    string ToString() const
    {
        string regimeStr;
        switch (regime)
        {
        case REGIME_TRENDING_UP:
            regimeStr = "TRENDING_UP";
            break;
        case REGIME_TRENDING_DOWN:
            regimeStr = "TRENDING_DOWN";
            break;
        case REGIME_RANGING:
            regimeStr = "RANGING";
            break;
        default:
            regimeStr = "UNKNOWN";
            break;
        }

        return StringFormat("%s (%.0f%%) | Trend: %.1f | Range: %.1f | %s",
                            regimeStr, confidence, trendStrength, rangeStrength, description);
    }

    // Quick helper methods
    bool IsTrending() const { return regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN; }
    bool IsRanging() const { return regime == REGIME_RANGING; }
    bool IsUpTrend() const { return regime == REGIME_TRENDING_UP; }
    bool IsDownTrend() const { return regime == REGIME_TRENDING_DOWN; }
};

//+------------------------------------------------------------------+
//| Lifecycle State Structure                                       |
//+------------------------------------------------------------------+
struct LifecycleState
{
    ENUM_MARKET_LIFECYCLE state;
    datetime startTime;
    int durationBars;
    string description;

    LifecycleState()
    {
        state = LIFECYCLE_UNKNOWN;
        startTime = 0;
        durationBars = 0;
        description = "Initial state";
    }

    string ToString() const
    {
        return StringFormat("%s | Started: %s | Bars: %d | %s",
                            GetStateString(state),
                            TimeToString(startTime, TIME_DATE | TIME_MINUTES),
                            durationBars,
                            description);
    }

    static string GetStateString(ENUM_MARKET_LIFECYCLE s)
    {
        switch (s)
        {
        case LIFECYCLE_RANGE_FORMING:
            return "RANGE_FORMING";
        case LIFECYCLE_RANGE_ACTIVE:
            return "RANGE_ACTIVE";
        case LIFECYCLE_BREAKOUT_DETECTED:
            return "BREAKOUT_DETECTED";
        case LIFECYCLE_TREND_CONFIRMED:
            return "TREND_CONFIRMED";
        case LIFECYCLE_PULLBACK_FORMING:
            return "PULLBACK_FORMING";
        case LIFECYCLE_PULLBACK_ACTIVE:
            return "PULLBACK_ACTIVE";
        case LIFECYCLE_TREND_RESUMING:
            return "TREND_RESUMING";
        case LIFECYCLE_TREND_WEAKENING:
            return "TREND_WEAKENING";
        default:
            return "UNKNOWN";
        }
    }
};

//+------------------------------------------------------------------+
//| Range Information Structure                                     |
//+------------------------------------------------------------------+
struct RangeInfo
{
    double top;
    double bottom;
    double widthPct;
    datetime startTime;
    int touchCount;
    bool validated;
    int barsSinceFormation;
    double currentPosition; // 0-100% where price is within range (NEW)

    // Default constructor
    RangeInfo()
    {
        top = 0.0;
        bottom = 0.0;
        widthPct = 0.0;
        startTime = 0;
        touchCount = 0;
        validated = false;
        barsSinceFormation = 0;
        currentPosition = 50.0; // Default to middle
    }

    // Copy constructor
    RangeInfo(const RangeInfo &other)
    {
        this = other;
    }

    // Assignment operator
    void operator=(const RangeInfo &other)
    {
        top = other.top;
        bottom = other.bottom;
        widthPct = other.widthPct;
        startTime = other.startTime;
        touchCount = other.touchCount;
        validated = other.validated;
        barsSinceFormation = other.barsSinceFormation;
        currentPosition = other.currentPosition;
    }

    bool IsValid() const { return top > bottom && widthPct > 0.1; }

    bool IsPriceInside(double price) const
    {
        return price >= bottom && price <= top;
    }

    bool IsPriceAbove(double price) const
    {
        return price > top;
    }

    bool IsPriceBelow(double price) const
    {
        return price < bottom;
    }

    // NEW: Calculate where price is within the range (0-100%)
    double CalculatePosition(double price) const
    {
        if (!IsValid())
            return 50.0;

        if (price >= top)
            return 100.0;
        if (price <= bottom)
            return 0.0;

        return ((price - bottom) / (top - bottom)) * 100.0;
    }

    string ToString() const
    {
        return StringFormat("Range: %.5f-%.5f (%.2f%%) | Pos: %.1f%% | Touches: %d | Valid: %s",
                            bottom, top, widthPct, currentPosition, touchCount, validated ? "Yes" : "No");
    }
};

//+------------------------------------------------------------------+
//| Trend Information Structure                                     |
//+------------------------------------------------------------------+
struct TrendInfo
{
    ENUM_MARKET_REGIME direction;
    double startPrice;
    datetime startTime;
    double strongestPoint;
    double currentPrice;
    int trendBars;
    double totalMovePct;

    TrendInfo()
    {
        direction = REGIME_UNKNOWN;
        startPrice = 0.0;
        startTime = 0;
        strongestPoint = 0.0;
        currentPrice = 0.0;
        trendBars = 0;
        totalMovePct = 0.0;
    }

    void Update(double price)
    {
        currentPrice = price;
        trendBars++;

        if (direction == REGIME_TRENDING_UP)
        {
            strongestPoint = MathMax(strongestPoint, price);
            totalMovePct = ((price - startPrice) / startPrice) * 100.0;
        }
        else if (direction == REGIME_TRENDING_DOWN)
        {
            strongestPoint = MathMin(strongestPoint, price);
            totalMovePct = ((startPrice - price) / startPrice) * 100.0;
        }
    }

    double GetCurrentRetracementPct() const
    {
        if (direction == REGIME_TRENDING_UP)
        {
            double highest = MathMax(startPrice, strongestPoint);
            double denominator = (highest - startPrice);

            // FIX: Check for zero denominator
            if (MathAbs(denominator) < 0.00001) // Use a small epsilon instead of exact zero
                return 0.0;

            return ((highest - currentPrice) / denominator) * 100.0;
        }
        else if (direction == REGIME_TRENDING_DOWN)
        {
            double lowest = MathMin(startPrice, strongestPoint);
            double denominator = (startPrice - lowest);

            // FIX: Check for zero denominator
            if (MathAbs(denominator) < 0.00001) // Use a small epsilon instead of exact zero
                return 0.0;

            return ((currentPrice - lowest) / denominator) * 100.0;
        }
        return 0.0;
    }

    bool IsRetracementSignificant(double threshold = 20.0) const
    {
        return GetCurrentRetracementPct() > threshold;
    }

    string ToString() const
    {
        string dirStr = (direction == REGIME_TRENDING_UP) ? "UP" : (direction == REGIME_TRENDING_DOWN) ? "DOWN"
                                                                                                       : "NONE";
        return StringFormat("Trend %s | Start: %.5f | Move: %.2f%% | Retrace: %.1f%%",
                            dirStr, startPrice, totalMovePct, GetCurrentRetracementPct());
    }
};

//+------------------------------------------------------------------+
//| Market Regime Detection Class                                   |
//+------------------------------------------------------------------+
class MarketRegimeDetector
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_lookbackPeriod;

    // Detection parameters
    double m_adxTrendThreshold;
    double m_adxRangeThreshold;
    double m_slopeThreshold;
    double m_atrRatioThreshold;
    double m_stdDevThreshold;

public:
    // Constructor
    MarketRegimeDetector(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        m_symbol = (symbol == NULL) ? Symbol() : symbol;
        m_timeframe = tf;
        m_lookbackPeriod = 24; // 24 bars default

        // Default thresholds (optimize these for your trading style)
        m_adxTrendThreshold = 25.0; // ADX above 25 = trending
        m_adxRangeThreshold = 20.0; // ADX below 20 = ranging
        m_slopeThreshold = 0.04;    // % slope per bar for trend was 0.08
        m_atrRatioThreshold = 1.1;  // Price change / ATR ratio was 2.5
        m_stdDevThreshold = 80.0;   // % of prices inside 2 std dev bands was 70
    }

    //+------------------------------------------------------------------+
    //| MAIN REGIME DETECTION FUNCTION                                 |
    //+------------------------------------------------------------------+
    RegimeResult DetectRegime()
    {
        RegimeResult result;

        // 1. Calculate all mathematical indicators
        double adxValue = CalculateADX();
        double slope = CalculateLinearRegressionSlope();
        double priceChangeRatio = CalculatePriceChangeATRRatio();
        double stdDevScore = CalculateStdDevContainment();
        double rangeTouches = CalculateRangeTouches();
        double netPriceChange = CalculateNetPriceChange();

        // 2. Calculate trend strength (-100 to +100)
        result.trendStrength = CalculateTrendStrength(adxValue, slope, priceChangeRatio, netPriceChange);

        // 3. Calculate range strength (0 to 100)
        result.rangeStrength = CalculateRangeStrength(adxValue, stdDevScore, rangeTouches, netPriceChange);

        // 4. Apply decision rules
        result = ApplyDecisionRules(result, adxValue, slope, stdDevScore, priceChangeRatio, rangeTouches);

        // 5. Set description
        result.description = GenerateDescription(result, adxValue, slope);

        return result;
    }

    //+------------------------------------------------------------------+
    //| TREND STRENGTH CALCULATION                                      |
    //+------------------------------------------------------------------+
    double CalculateTrendStrength(double adx, double slope, double priceChangeRatio, double netChange)
    {
        double strength = 0.0;

        // 1. Slope direction (primary)
        if (MathAbs(slope) > m_slopeThreshold)
        {
            strength = (slope > 0) ? 60.0 : -60.0;
        }

        // 2. ADX confirmation
        if (adx > m_adxTrendThreshold)
        {
            double adxFactor = MathMin(1.0, (adx - m_adxTrendThreshold) / 20.0);
            strength *= (1.0 + adxFactor * 0.5);
        }
        else if (adx < m_adxRangeThreshold)
        {
            // Reduce trend strength if ADX is low
            strength *= 0.7;
        }

        // 3. Price change to ATR ratio
        if (priceChangeRatio > m_atrRatioThreshold)
        {
            strength *= (1.0 + (priceChangeRatio - m_atrRatioThreshold) * 0.3);
        }

        // 4. Net price change adjustment
        if (MathAbs(netChange) > 1.0)
        {
            strength *= (1.0 + MathAbs(netChange) * 0.1);
        }

        // Cap between -100 and +100
        if (strength > 100.0)
            strength = 100.0;
        if (strength < -100.0)
            strength = -100.0;

        return strength;
    }

    //+------------------------------------------------------------------+
    //| RANGE STRENGTH CALCULATION                                      |
    //+------------------------------------------------------------------+
    double CalculateRangeStrength(double adx, double stdDevScore, double rangeTouches, double netChange)
    {
        double strength = 0.0;

        // 1. Low ADX
        if (adx < m_adxRangeThreshold)
        {
            strength += 40.0;
        }

        // 2. High standard deviation containment
        if (stdDevScore > m_stdDevThreshold)
        {
            strength += 30.0;
        }

        // 3. Range touches
        strength += rangeTouches * 0.3;

        // 4. Low net movement
        if (MathAbs(netChange) < 1.0)
        {
            strength += 20.0;
        }

        // Cap at 100
        if (strength > 100.0)
            strength = 100.0;

        return strength;
    }

    //+------------------------------------------------------------------+
    //| DECISION RULES                                                  |
    //+------------------------------------------------------------------+
    RegimeResult ApplyDecisionRules(RegimeResult &result, double adx, double slope,
                                    double stdDevScore, double priceChangeRatio, double rangeTouches)
    {
        bool isTrendingByRules = false;
        bool isRangingByRules = false;

        // RULE 1: ADX > threshold AND significant slope → TRENDING
        if (adx > m_adxTrendThreshold && MathAbs(slope) > m_slopeThreshold)
        {
            isTrendingByRules = true;
        }

        // RULE 2: Low ADX AND high std dev containment → RANGING
        if (adx < m_adxRangeThreshold && stdDevScore > m_stdDevThreshold)
        {
            isRangingByRules = true;
        }

        // RULE 3: PriceChange/ATR ratio > threshold → TRENDING
        if (priceChangeRatio > m_atrRatioThreshold)
        {
            isTrendingByRules = true;
        }

        // RULE 4: Multiple range touches → RANGING
        if (rangeTouches > 60.0) // Approximately 3 touches
        {
            isRangingByRules = true;
        }

        // Apply rules
        if (isTrendingByRules && !isRangingByRules)
        {
            // Clear trending case
            result.regime = (result.trendStrength > 0) ? REGIME_TRENDING_UP : REGIME_TRENDING_DOWN;
            result.confidence = MathAbs(result.trendStrength);
        }
        else if (!isTrendingByRules && isRangingByRules)
        {
            // Clear ranging case
            result.regime = REGIME_RANGING;
            result.confidence = result.rangeStrength;
        }
        else if (isTrendingByRules && isRangingByRules)
        {
            // Conflicting signals - use strength comparison
            if (MathAbs(result.trendStrength) > result.rangeStrength)
            {
                result.regime = (result.trendStrength > 0) ? REGIME_TRENDING_UP : REGIME_TRENDING_DOWN;
                result.confidence = MathAbs(result.trendStrength);
            }
            else
            {
                result.regime = REGIME_RANGING;
                result.confidence = result.rangeStrength;
            }
        }
        else
        {
            // Weak signals - use Golden Ratio
            double goldenScore = (slope * 100.0) + (adx * 2.0) + (priceChangeRatio * 10.0);

            if (goldenScore > 100.0 && MathAbs(result.trendStrength) > 60.0)
            {
                result.regime = (result.trendStrength > 0) ? REGIME_TRENDING_UP : REGIME_TRENDING_DOWN;
                result.confidence = MathAbs(result.trendStrength);
            }
            else if (goldenScore < 50.0 && result.rangeStrength > 60.0)
            {
                result.regime = REGIME_RANGING;
                result.confidence = result.rangeStrength;
            }
            else
            {
                // Uncertain
                result.regime = REGIME_UNKNOWN;
                result.confidence = MathMax(result.rangeStrength, MathAbs(result.trendStrength));
            }
        }

        // Ensure confidence is capped
        if (result.confidence > 100.0)
            result.confidence = 100.0;

        return result;
    }

    //+------------------------------------------------------------------+
    //| INDICATOR CALCULATION FUNCTIONS                                 |
    //+------------------------------------------------------------------+

    // Calculate ADX value
    double CalculateADX(int period = 14)
    {
        int handle = iADX(m_symbol, m_timeframe, period);
        if (handle == INVALID_HANDLE)
            return 0.0;

        double adx[];
        ArraySetAsSeries(adx, true);

        if (CopyBuffer(handle, 0, 0, 1, adx) > 0)
        {
            IndicatorRelease(handle);
            return adx[0];
        }

        IndicatorRelease(handle);
        return 0.0;
    }

    // Calculate linear regression slope (% per bar)
    double CalculateLinearRegressionSlope()
    {
        double closes[];
        ArrayResize(closes, m_lookbackPeriod);
        ArraySetAsSeries(closes, true);

        // Get close prices
        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            closes[i] = iClose(m_symbol, m_timeframe, i);
        }

        // Calculate slope using least squares
        double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;

        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            sumX += i;
            sumY += closes[i];
            sumXY += i * closes[i];
            sumX2 += i * i;
        }

        double N = (double)m_lookbackPeriod;
        double slope = (N * sumXY - sumX * sumY) / (N * sumX2 - sumX * sumX);

        // FIX: Check for zero or very small close price before division
        double lastClose = closes[m_lookbackPeriod - 1];
        if (MathAbs(lastClose) < 0.00001)
            return 0.0;

        // Convert to percentage change per bar
        return (slope / lastClose) * 100.0;
    }

    // Calculate Price Change / ATR Ratio
    double CalculatePriceChangeATRRatio()
    {
        double currentPrice = iClose(m_symbol, m_timeframe, 0);
        double firstPrice = iClose(m_symbol, m_timeframe, m_lookbackPeriod - 1);

        // FIX: Check for zero or negative prices
        if (firstPrice <= 0.0 || currentPrice <= 0.0)
            return 0.0;

        // Calculate price change percentage
        double priceChangePct = MathAbs((currentPrice - firstPrice) / firstPrice) * 100.0;

        // Calculate ATR percentage
        double atr = CalculateATR(14);

        // FIX: Check for zero ATR
        if (atr <= 0.0 || currentPrice <= 0.0)
            return 0.0;

        double atrPct = (atr / currentPrice) * 100.0;

        if (atrPct > 0.0)
        {
            return priceChangePct / atrPct;
        }

        return 0.0;
    }

    // Calculate Standard Deviation Containment (% of prices inside 2 std dev bands)
    double CalculateStdDevContainment()
    {
        double closes[];
        ArrayResize(closes, m_lookbackPeriod);

        // Get close prices
        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            closes[i] = iClose(m_symbol, m_timeframe, i);
        }

        // Calculate mean
        double mean = 0.0;
        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            mean += closes[i];
        }
        mean /= m_lookbackPeriod;

        // Calculate standard deviation
        double variance = 0.0;
        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            double diff = closes[i] - mean;
            variance += diff * diff;
        }
        variance /= m_lookbackPeriod;
        double stdDev = MathSqrt(variance);

        // Create bands at +/- 2 standard deviations
        double upperBand = mean + (2.0 * stdDev);
        double lowerBand = mean - (2.0 * stdDev);

        // Count how many closes are inside the bands
        int insideCount = 0;
        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            if (closes[i] >= lowerBand && closes[i] <= upperBand)
            {
                insideCount++;
            }
        }

        // Return percentage
        return ((double)insideCount / m_lookbackPeriod) * 100.0;
    }

    // Calculate range touches (support/resistance)
    double CalculateRangeTouches()
    {
        // Find highest high and lowest low in lookback period
        double highest = 0.0;
        double lowest = 1e10;

        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            double low = iLow(m_symbol, m_timeframe, i);

            if (high > highest)
                highest = high;
            if (low < lowest)
                lowest = low;
        }

        if (highest <= lowest)
            return 0.0;

        // Calculate ATR for tolerance
        double atr = CalculateATR(14);
        double currentPrice = iClose(m_symbol, m_timeframe, 0);
        double tolerance = (atr / currentPrice) * 100.0 * 0.5;

        // Count touches of support and resistance
        int touchCount = 0;

        for (int i = 0; i < m_lookbackPeriod; i++)
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            double low = iLow(m_symbol, m_timeframe, i);

            // Check if price touched resistance (within tolerance)
            if (MathAbs((high - highest) / currentPrice * 100.0) < tolerance)
            {
                touchCount++;
            }

            // Check if price touched support (within tolerance)
            if (MathAbs((low - lowest) / currentPrice * 100.0) < tolerance)
            {
                touchCount++;
            }
        }

        // Calculate score (max 100)
        double touchScore = MathMin(100.0, touchCount * 20.0);

        // Adjust for range width (narrower ranges score higher)
        double rangeWidthPct = ((highest - lowest) / currentPrice) * 100.0;
        double widthScore = MathMax(0.0, 100.0 - (rangeWidthPct * 40.0));

        // Combine scores
        return (touchScore * 0.6 + widthScore * 0.4);
    }

    // Calculate net price change percentage
    double CalculateNetPriceChange()
    {
        double currentPrice = iClose(m_symbol, m_timeframe, 0);
        double firstPrice = iClose(m_symbol, m_timeframe, m_lookbackPeriod - 1);

        if (firstPrice <= 0.0)
            return 0.0;

        return ((currentPrice - firstPrice) / firstPrice) * 100.0;
    }

    // Calculate ATR
    double CalculateATR(int period = 14)
    {
        int handle = iATR(m_symbol, m_timeframe, period);
        if (handle == INVALID_HANDLE)
            return 0.0;

        double atr[];
        ArraySetAsSeries(atr, true);

        if (CopyBuffer(handle, 0, 0, 1, atr) > 0)
        {
            IndicatorRelease(handle);
            return atr[0];
        }

        IndicatorRelease(handle);
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| HELPER FUNCTIONS                                                |
    //+------------------------------------------------------------------+

    // Generate description for the regime
    string GenerateDescription(RegimeResult &result, double adx, double slope)
    {
        string desc = "";

        switch (result.regime)
        {
        case REGIME_TRENDING_UP:
            desc = StringFormat("Strong Uptrend | ADX: %.1f > %.1f | Slope: +%.3f%%/bar",
                                adx, m_adxTrendThreshold, MathAbs(slope));
            break;

        case REGIME_TRENDING_DOWN:
            desc = StringFormat("Strong Downtrend | ADX: %.1f > %.1f | Slope: -%.3f%%/bar",
                                adx, m_adxTrendThreshold, MathAbs(slope));
            break;

        case REGIME_RANGING:
            desc = StringFormat("Sideways Market | ADX: %.1f < %.1f | Consolidation",
                                adx, m_adxRangeThreshold);
            break;

        default:
            desc = "Market unclear - mixed signals detected";
            break;
        }

        return desc;
    }

    //+------------------------------------------------------------------+
    //| SETTER METHODS                                                  |
    //+------------------------------------------------------------------+

    void SetSymbol(string symbol) { m_symbol = symbol; }
    void SetTimeframe(ENUM_TIMEFRAMES tf) { m_timeframe = tf; }
    void SetLookbackPeriod(int period) { m_lookbackPeriod = period; }

    void SetThresholds(double adxTrend = 25.0, double adxRange = 20.0,
                       double slope = 0.08, double atrRatio = 2.5,
                       double stdDev = 70.0)
    {
        m_adxTrendThreshold = adxTrend;
        m_adxRangeThreshold = adxRange;
        m_slopeThreshold = slope;
        m_atrRatioThreshold = atrRatio;
        m_stdDevThreshold = stdDev;
    }
};

//+------------------------------------------------------------------+
//| Market Lifecycle Tracker Class                                  |
//+------------------------------------------------------------------+
class MarketLifecycleTracker
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // Current state
    LifecycleState m_currentState;
    RangeInfo m_currentRange;
    TrendInfo m_currentTrend;
    RangeInfo m_pullbackRange;

    // Detection parameters
    int m_minRangeTouches;
    int m_minPullbackTouches;
    double m_breakoutMargin; // ATR multiplier
    double m_minRangeWidthPct;
    double m_pullbackThresholdPct;

    // History
    double m_lastPrices[5];
    datetime m_lastUpdateTime;

    int m_rangeInitializationBars; // Bars to use for initial range
    bool m_rangeInitialized;       // Track if range is initialized

public:
    // Constructor
    MarketLifecycleTracker(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        m_symbol = (symbol == NULL) ? Symbol() : symbol;
        m_timeframe = tf;

        // Initialize with default parameters
        m_minRangeTouches = 3;
        m_minPullbackTouches = 2;
        m_breakoutMargin = 0.3;        // 0.3 * ATR
        m_minRangeWidthPct = 0.5;      // Minimum 0.5% range width
        m_pullbackThresholdPct = 20.0; // 20% retracement to consider pullback

        m_rangeInitializationBars = 5; // Use last 5 bars for initialization
        m_rangeInitialized = false;

        Reset();
    }

    //+------------------------------------------------------------------+
    //| MAIN UPDATE FUNCTION                                           |
    //+------------------------------------------------------------------+
    LifecycleState Update()
    {
        // Check if it's a new bar
        if (!IsNewBar())
            return m_currentState;

        // 1. Get current price
        double currentPrice = iClose(m_symbol, m_timeframe, 0);

        // 2. Update price history
        UpdatePriceHistory(currentPrice);

        // 3. Check for range reinitialization (NEW)
        CheckForRangeReinitialization(currentPrice);

        // 4. Process based on current state
        switch (m_currentState.state)
        {
        case LIFECYCLE_UNKNOWN:
            InitialDetection(currentPrice);
            break;

        case LIFECYCLE_RANGE_FORMING:
            ProcessRangeForming(currentPrice);
            break;

        case LIFECYCLE_RANGE_ACTIVE:
            ProcessRangeActive(currentPrice);
            break;

        case LIFECYCLE_BREAKOUT_DETECTED:
            ProcessBreakoutDetected(currentPrice);
            break;

        case LIFECYCLE_TREND_CONFIRMED:
            ProcessTrendConfirmed(currentPrice);
            break;

        case LIFECYCLE_PULLBACK_FORMING:
            ProcessPullbackForming(currentPrice);
            break;

        case LIFECYCLE_PULLBACK_ACTIVE:
            ProcessPullbackActive(currentPrice);
            break;

        case LIFECYCLE_TREND_RESUMING:
            ProcessTrendResuming(currentPrice);
            break;

        case LIFECYCLE_TREND_WEAKENING:
            ProcessTrendWeakening(currentPrice);
            break;
        }

        // 4. Update state duration
        UpdateStateDuration();

        return m_currentState;
    }

    //+------------------------------------------------------------------+
    //| STATE PROCESSING FUNCTIONS                                      |
    //+------------------------------------------------------------------+

private:
    bool ShouldReinitializeForPullback(double price)
    {
        // Only reinitialize during pullback formation if:
        // 1. We're in a pullback state
        // 2. A valid range is forming (width > minWidth)

        if (m_currentState.state == LIFECYCLE_PULLBACK_FORMING ||
            m_currentState.state == LIFECYCLE_PULLBACK_ACTIVE)
        {
            // Check if pullback range has formed with sufficient width
            if (m_pullbackRange.IsValid() &&
                m_pullbackRange.widthPct >= m_minRangeWidthPct)
            {
                // Valid pullback range detected - time to reinitialize main range
                Print("Valid pullback range detected (width=" +
                      DoubleToString(m_pullbackRange.widthPct, 2) +
                      "%), reinitializing main range");
                return true;
            }
        }

        return false;
    }

    bool ShouldReinitializeForNewRange(double price)
    {
        // Check if we're transitioning to a new range state
        if (m_currentState.state == LIFECYCLE_RANGE_FORMING)
        {
            // Wait for range to form with sufficient width
            if (m_currentRange.IsValid() &&
                m_currentRange.widthPct >= m_minRangeWidthPct &&
                m_currentRange.touchCount >= m_minRangeTouches)
            {
                // Valid new range formed
                return true;
            }
        }

        return false;
    }

    void InitialDetection(double price)
    {
        // Use MarketRegimeDetector to determine initial state
        MarketRegimeDetector detector(m_symbol, m_timeframe);
        RegimeResult regime = detector.DetectRegime();

        if (regime.IsRanging() && regime.confidence > 60)
        {
            // Start with range detection
            m_currentState.state = LIFECYCLE_RANGE_FORMING;
            InitializeRange();
            m_currentState.description = "Initial range detection started";
        }
        else if (regime.IsTrending() && regime.confidence > 70)
        {
            // Already in trend
            m_currentState.state = LIFECYCLE_TREND_CONFIRMED;
            InitializeTrend(regime);
            m_currentState.description = "Already in confirmed trend";
        }
        else
        {
            m_currentState.description = "Market unclear, waiting for formation";
        }
    }

    void ProcessRangeForming(double price)
    {
        // Update range boundaries if price extends beyond current range
        UpdateRangeBoundaries(price);

        // Check for touches
        if (IsRangeTouch(price))
        {
            m_currentRange.touchCount++;
            m_currentState.description = StringFormat("Range forming - Touch %d/%d",
                                                      m_currentRange.touchCount, m_minRangeTouches);
        }

        // Validate range after enough touches
        if (m_currentRange.touchCount >= m_minRangeTouches)
        {
            m_currentRange.validated = true;
            m_currentState.state = LIFECYCLE_RANGE_ACTIVE;
            m_currentState.description = "Range validated and active";
        }

        // Check for early breakout
        if (CheckRangeBreakout(price))
        {
            m_currentState.state = LIFECYCLE_BREAKOUT_DETECTED;
            m_currentState.description = "Early breakout from forming range";
        }
    }

    void ProcessRangeActive(double price)
    {
        // Update range if price extends it
        UpdateRangeBoundaries(price);

        // Check for breakout
        if (CheckRangeBreakout(price))
        {
            m_currentState.state = LIFECYCLE_BREAKOUT_DETECTED;
            m_currentState.description = "Breakout detected from active range";
        }
        else if (IsRangeTouch(price))
        {
            m_currentRange.touchCount++;
            m_currentState.description = StringFormat("Range active - Touch %d",
                                                      m_currentRange.touchCount);
        }
    }

    void ProcessBreakoutDetected(double price)
    {
        // Check for breakout confirmation (3 consecutive closes outside range)
        if (ConfirmBreakout(price))
        {
            // Determine trend direction
            MarketRegimeDetector detector(m_symbol, m_timeframe);
            RegimeResult regime = detector.DetectRegime();

            if (regime.IsTrending())
            {
                m_currentState.state = LIFECYCLE_TREND_CONFIRMED;
                InitializeTrend(regime);
                m_currentState.description = "Breakout confirmed, trend established";
            }
        }
        else if (CheckFalseBreakout(price))
        {
            // Price returned to range
            m_currentState.state = LIFECYCLE_RANGE_ACTIVE;
            m_currentState.description = "False breakout, range still active";
        }
    }

    void ProcessTrendConfirmed(double price)
    {
        // Update trend information
        m_currentTrend.Update(price);

        // Check for pullback
        if (m_currentTrend.IsRetracementSignificant(m_pullbackThresholdPct))
        {
            m_currentState.state = LIFECYCLE_PULLBACK_FORMING;
            InitializePullbackRange(price);
            m_currentState.description = StringFormat("Pullback forming (%.1f%% retracement)",
                                                      m_currentTrend.GetCurrentRetracementPct());
        }
        else
        {
            m_currentState.description = StringFormat("Trend continuing - Move: %.2f%%",
                                                      m_currentTrend.totalMovePct);
        }
    }

    void ProcessPullbackForming(double price)
    {
        // Update pullback range (this can expand normally)
        UpdatePullbackRange(price);

        // Check for touches
        if (IsPullbackTouch(price))
        {
            m_pullbackRange.touchCount++;
            m_currentState.description = StringFormat("Pullback forming - Touch %d/%d",
                                                      m_pullbackRange.touchCount, m_minPullbackTouches);
        }

        // Validate pullback after enough touches
        if (m_pullbackRange.touchCount >= m_minPullbackTouches)
        {
            m_pullbackRange.validated = true;
            m_currentState.state = LIFECYCLE_PULLBACK_ACTIVE;
            m_currentState.description = "Pullback range validated";

            // Check if pullback range is wide enough to reinitialize main range
            if (m_pullbackRange.widthPct >= m_minRangeWidthPct)
            {
                Print("Wide pullback detected - will reinitialize main range on breakout");
            }
        }

        // Check if trend resumes
        if (CheckPullbackBreakout(price))
        {
            m_currentState.state = LIFECYCLE_TREND_RESUMING;
            m_currentState.description = "Trend resuming from pullback";
        }
    }

    void ProcessPullbackActive(double price)
    {
        // Check for breakout from pullback range
        if (CheckPullbackBreakout(price))
        {
            m_currentState.state = LIFECYCLE_TREND_RESUMING;
            m_currentState.description = "Breakout from pullback range";

            // When breakout occurs, check if we should use pullback as new range
            if (m_pullbackRange.widthPct >= m_minRangeWidthPct)
            {
                // Pullback was significant - reinitialize main range
                m_currentRange = m_pullbackRange;
                m_currentRange.startTime = TimeCurrent();
                m_rangeInitialized = true;

                Print("Main range reinitialized from significant pullback after breakout");
            }
        }
        else if (IsPullbackTouch(price))
        {
            m_pullbackRange.touchCount++;
            m_currentState.description = StringFormat("Pullback active - Touch %d",
                                                      m_pullbackRange.touchCount);
        }
    }

    void ProcessTrendResuming(double price)
    {
        // Check for trend resumption confirmation
        if (ConfirmTrendResumption(price))
        {
            m_currentState.state = LIFECYCLE_TREND_CONFIRMED;
            // Clear pullback range
            m_pullbackRange = RangeInfo();
            m_currentState.description = "Trend fully resumed";
        }
    }

    void ProcessTrendWeakening(double price)
    {
        // Check if trend regains strength or transitions to range
        MarketRegimeDetector detector(m_symbol, m_timeframe);
        RegimeResult regime = detector.DetectRegime();

        if (regime.confidence > 70 && regime.IsTrending())
        {
            m_currentState.state = LIFECYCLE_TREND_CONFIRMED;
            m_currentState.description = "Trend regained strength";
        }
        else if (regime.IsRanging() && regime.confidence > 60)
        {
            // Transition back to range
            m_currentState.state = LIFECYCLE_RANGE_FORMING;
            InitializeRange();
            m_currentState.description = "Trend ended, new range forming";
        }
    }

    //+------------------------------------------------------------------+
    //| HELPER FUNCTIONS                                                |
    //+------------------------------------------------------------------+

    bool CheckRangeBreakout(double price)
    {
        if (!m_currentRange.IsValid())
            return false;

        double atr = CalculateATR(14);
        double margin = atr * m_breakoutMargin;

        if (price > m_currentRange.top + margin)
        {
            m_currentTrend.direction = REGIME_TRENDING_UP;
            return true;
        }
        else if (price < m_currentRange.bottom - margin)
        {
            m_currentTrend.direction = REGIME_TRENDING_DOWN;
            return true;
        }

        return false;
    }

    bool ConfirmBreakout(double price)
    {
        // Need 3 consecutive closes outside range
        int consecutive = 0;
        for (int i = 0; i < 3; i++)
        {
            double closePrice = iClose(m_symbol, m_timeframe, i);

            if (m_currentTrend.direction == REGIME_TRENDING_UP)
            {
                if (closePrice > m_currentRange.top)
                    consecutive++;
            }
            else if (m_currentTrend.direction == REGIME_TRENDING_DOWN)
            {
                if (closePrice < m_currentRange.bottom)
                    consecutive++;
            }
        }

        return consecutive >= 3;
    }

    bool CheckFalseBreakout(double price)
    {
        if (!m_currentRange.IsValid())
            return false;

        // If price returns inside the range, it's a false breakout
        return m_currentRange.IsPriceInside(price);
    }

    bool CheckPullbackBreakout(double price)
    {
        if (!m_pullbackRange.IsValid())
            return false;

        // Breakout from pullback in the direction of the main trend
        if (m_currentTrend.direction == REGIME_TRENDING_UP)
        {
            return price > m_pullbackRange.top;
        }
        else if (m_currentTrend.direction == REGIME_TRENDING_DOWN)
        {
            return price < m_pullbackRange.bottom;
        }

        return false;
    }

    bool ConfirmTrendResumption(double price)
    {
        // Price should continue in trend direction
        MarketRegimeDetector detector(m_symbol, m_timeframe);
        RegimeResult regime = detector.DetectRegime();

        if (m_currentTrend.direction == REGIME_TRENDING_UP)
        {
            return regime.IsUpTrend() && regime.confidence > 60;
        }
        else if (m_currentTrend.direction == REGIME_TRENDING_DOWN)
        {
            return regime.IsDownTrend() && regime.confidence > 60;
        }

        return false;
    }

    bool IsRangeTouch(double price)
    {
        if (!m_currentRange.IsValid())
            return false;

        double atr = CalculateATR(14);
        double tolerance = atr * 0.1; // 0.1 * ATR tolerance

        // Check if price touches range boundaries
        return (MathAbs(price - m_currentRange.top) < tolerance) ||
               (MathAbs(price - m_currentRange.bottom) < tolerance);
    }

    bool IsPullbackTouch(double price)
    {
        if (!m_pullbackRange.IsValid())
            return false;

        double atr = CalculateATR(14);
        double tolerance = atr * 0.1;

        return (MathAbs(price - m_pullbackRange.top) < tolerance) ||
               (MathAbs(price - m_pullbackRange.bottom) < tolerance);
    }

    void UpdateRangeBoundaries(double price)
    {
        if (!m_rangeInitialized)
        {
            InitializeRange();
            return;
        }

        // FIXED RANGE: Only update position, NEVER change boundaries
        m_currentRange.currentPosition = m_currentRange.CalculatePosition(price);
    }

    // NEW: Check for pullback-based reinitialization
    void ProcessStateForReinitialization()
    {
        // Only reinitialize during pullback->range transitions
        if ((m_currentState.state == LIFECYCLE_PULLBACK_ACTIVE ||
             m_currentState.state == LIFECYCLE_TREND_WEAKENING) &&
            m_pullbackRange.IsValid() &&
            m_pullbackRange.widthPct >= m_minRangeWidthPct)
        {
            // Use pullback range as new main range
            m_currentRange = m_pullbackRange;
            Print("Range reinitialized from pullback: width=" + 
                  DoubleToString(m_pullbackRange.widthPct, 2) + "%");
        }
    }

    void UpdatePullbackRange(double price)
    {
        if (!m_pullbackRange.IsValid())
        {
            m_pullbackRange.top = price;
            m_pullbackRange.bottom = price;
        }
        else
        {
            m_pullbackRange.top = MathMax(m_pullbackRange.top, price);
            m_pullbackRange.bottom = MathMin(m_pullbackRange.bottom, price);
        }

        double mid = (m_pullbackRange.top + m_pullbackRange.bottom) / 2;
        m_pullbackRange.widthPct = ((m_pullbackRange.top - m_pullbackRange.bottom) / mid) * 100.0;
    }

    void InitializeRange()
    {
        // Always use last 5 bars to find initial range
        int bars = 5;
        double highest = 0;
        double lowest = 1e10;

        for (int i = 0; i < bars; i++)
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            double low = iLow(m_symbol, m_timeframe, i);

            if (high > highest)
                highest = high;
            if (low < lowest)
                lowest = low;
        }

        m_currentRange.top = highest;
        m_currentRange.bottom = lowest;
        m_currentRange.startTime = TimeCurrent();
        m_currentRange.touchCount = 1;
        m_currentRange.validated = false;

        double mid = (highest + lowest) / 2;
        if (mid > 0)
            m_currentRange.widthPct = ((highest - lowest) / mid) * 100.0;
        else
            m_currentRange.widthPct = 0.0;

        double currentPrice = iClose(m_symbol, m_timeframe, 0);
        m_currentRange.currentPosition = m_currentRange.CalculatePosition(currentPrice);

        m_rangeInitialized = true;

        Print(StringFormat("FIXED Range Initialized: Top=%.5f, Bottom=%.5f, Width=%.2f%%, Bars: 5",
                           highest, lowest, m_currentRange.widthPct));
    }

    void InitializeTrend(RegimeResult &regime)
    {
        m_currentTrend.direction = regime.regime;
        m_currentTrend.startPrice = iClose(m_symbol, m_timeframe, 0);
        m_currentTrend.startTime = TimeCurrent();
        m_currentTrend.strongestPoint = m_currentTrend.startPrice;
        m_currentTrend.currentPrice = m_currentTrend.startPrice;
        m_currentTrend.trendBars = 0;
        m_currentTrend.totalMovePct = 0.0;
    }

    void InitializePullbackRange(double price)
    {
        m_pullbackRange.top = price;
        m_pullbackRange.bottom = price;
        m_pullbackRange.startTime = TimeCurrent();
        m_pullbackRange.touchCount = 1;
        m_pullbackRange.validated = false;
        m_pullbackRange.widthPct = 0.0;
    }

    void UpdatePriceHistory(double price)
    {
        // Shift array
        for (int i = 4; i > 0; i--)
        {
            m_lastPrices[i] = m_lastPrices[i - 1];
        }
        m_lastPrices[0] = price;
    }

    void UpdateStateDuration()
    {
        m_currentState.durationBars++;
    }

    bool IsNewBar()
    {
        datetime currentTime = iTime(m_symbol, m_timeframe, 0);
        if (m_lastUpdateTime != currentTime)
        {
            m_lastUpdateTime = currentTime;
            return true;
        }
        return false;
    }

    // Utility function from original detector
    double CalculateATR(int period = 14)
    {
        int handle = iATR(m_symbol, m_timeframe, period);
        if (handle == INVALID_HANDLE)
            return 0.0;

        double atr[];
        ArraySetAsSeries(atr, true);

        if (CopyBuffer(handle, 0, 0, 1, atr) > 0)
        {
            IndicatorRelease(handle);
            return atr[0];
        }

        IndicatorRelease(handle);
        return 0.0;
    }

public:
    //+------------------------------------------------------------------+
    //| GETTER METHODS                                                  |
    //+------------------------------------------------------------------+

    LifecycleState GetCurrentState() const { return m_currentState; }
    RangeInfo GetCurrentRange() const { return m_currentRange; }
    TrendInfo GetCurrentTrend() const { return m_currentTrend; }
    RangeInfo GetPullbackRange() const { return m_pullbackRange; }

    //+------------------------------------------------------------------+
    //| SETTER METHODS                                                  |
    //+------------------------------------------------------------------+

    void SetParameters(int minRangeTouches = 3, int minPullbackTouches = 2,
                       double breakoutMargin = 0.3, double minRangeWidthPct = 0.5,
                       double pullbackThresholdPct = 20.0)
    {
        m_minRangeTouches = minRangeTouches;
        m_minPullbackTouches = minPullbackTouches;
        m_breakoutMargin = breakoutMargin;
        m_minRangeWidthPct = minRangeWidthPct;
        m_pullbackThresholdPct = pullbackThresholdPct;
    }

    void Reset()
    {
        m_currentState = LifecycleState();
        m_currentRange = RangeInfo();
        m_currentTrend = TrendInfo();
        m_pullbackRange = RangeInfo();
        m_lastUpdateTime = 0;
        ArrayInitialize(m_lastPrices, 0.0);
    }

    //+------------------------------------------------------------------+
    //| QUICK STATUS CHECK                                              |
    //+------------------------------------------------------------------+

    string GetFullStatus() const
    {
        string status = "=== MARKET LIFECYCLE STATUS ===\n";
        status += "State: " + m_currentState.ToString() + "\n";

        if (m_currentRange.IsValid())
        {
            status += "Current Range: " + m_currentRange.ToString() + "\n";
        }

        if (m_currentTrend.direction != REGIME_UNKNOWN)
        {
            status += "Current Trend: " + m_currentTrend.ToString() + "\n";
        }

        if (m_pullbackRange.IsValid())
        {
            status += "Pullback Range: " + m_pullbackRange.ToString() + "\n";
        }

        return status;
    }

    // Called from Update() to check for reinitialization
    void CheckForRangeReinitialization(double price)
    {
        // Reinitialize only in specific conditions:

        // 1. When transitioning from trend to pullback with valid range
        if (ShouldReinitializeForPullback(price))
        {
            // Use pullback range as the new main range
            m_currentRange = m_pullbackRange;
            m_currentRange.startTime = TimeCurrent();
            m_rangeInitialized = true;

            Print("Main range reinitialized from pullback: " + m_currentRange.ToString());
            return;
        }

        // 2. When a new range is actively forming (after trend ends)
        if (ShouldReinitializeForNewRange(price))
        {
            // Already have a valid range, just mark as initialized
            m_rangeInitialized = true;
            Print("New range established: " + m_currentRange.ToString());
        }

        // 3. Never reinitialize due to price moving outside range
        //    (that's the whole point of fixed ranges!)
    }
};

//+------------------------------------------------------------------+
//| Market Analysis Manager Class                                   |
//+------------------------------------------------------------------+
class MarketManager
{
private:
    MarketRegimeDetector m_regimeDetector;
    MarketLifecycleTracker m_lifecycleTracker;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

public:
    MarketManager(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1) : m_regimeDetector(symbol, tf),
                                                                          m_lifecycleTracker(symbol, tf)
    {
        m_symbol = (symbol == NULL) ? Symbol() : symbol;
        m_timeframe = tf;
    }

    //+------------------------------------------------------------------+
    //| PUBLIC INTERFACE METHODS                                        |
    //+------------------------------------------------------------------+

    // Unified analysis
    struct MarketAnalysis
    {
        RegimeResult regime;      // Current regime
        LifecycleState lifecycle; // Current lifecycle state
        datetime analysisTime;
        double currentPrice;

        string ToString() const
        {
            string result = "=== MARKET ANALYSIS ===\n";
            result += "Time: " + TimeToString(analysisTime, TIME_DATE | TIME_SECONDS) + "\n";
            result += "Price: " + DoubleToString(currentPrice, 5) + "\n";
            result += "Regime: " + regime.ToString() + "\n";
            result += "Lifecycle: " + lifecycle.ToString() + "\n";
            return result;
        }
    };

    MarketAnalysis GetCompleteAnalysis()
    {
        MarketAnalysis analysis;
        analysis.regime = m_regimeDetector.DetectRegime();
        analysis.lifecycle = m_lifecycleTracker.Update();
        analysis.analysisTime = TimeCurrent();
        analysis.currentPrice = iClose(m_symbol, m_timeframe, 0);

        return analysis;
    }

    //+------------------------------------------------------------------+
    //| REGIME DETECTOR WRAPPERS                                        |
    //+------------------------------------------------------------------+

    RegimeResult DetectRegime()
    {
        return m_regimeDetector.DetectRegime();
    }

    void SetRegimeThresholds(double adxTrend = 25.0, double adxRange = 20.0,
                             double slope = 0.08, double atrRatio = 2.5,
                             double stdDev = 70.0)
    {
        m_regimeDetector.SetThresholds(adxTrend, adxRange, slope, atrRatio, stdDev);
    }

    void SetRegimeSymbol(string symbol)
    {
        m_regimeDetector.SetSymbol(symbol);
    }

    void SetRegimeTimeframe(ENUM_TIMEFRAMES tf)
    {
        m_regimeDetector.SetTimeframe(tf);
    }

    void SetRegimeLookback(int period)
    {
        m_regimeDetector.SetLookbackPeriod(period);
    }

    //+------------------------------------------------------------------+
    //| LIFECYCLE TRACKER WRAPPERS                                      |
    //+------------------------------------------------------------------+

    LifecycleState UpdateLifecycle()
    {
        return m_lifecycleTracker.Update();
    }

    string GetLifecycleStatus() const
    {
        return m_lifecycleTracker.GetFullStatus();
    }

    LifecycleState GetCurrentLifecycleState() const
    {
        return m_lifecycleTracker.GetCurrentState();
    }

    RangeInfo GetCurrentRange() const
    {
        return m_lifecycleTracker.GetCurrentRange();
    }

    TrendInfo GetCurrentTrend() const
    {
        return m_lifecycleTracker.GetCurrentTrend();
    }

    void SetLifecycleParameters(int minRangeTouches = 3, int minPullbackTouches = 2,
                                double breakoutMargin = 0.3, double minRangeWidthPct = 0.5,
                                double pullbackThresholdPct = 20.0)
    {
        m_lifecycleTracker.SetParameters(minRangeTouches, minPullbackTouches,
                                         breakoutMargin, minRangeWidthPct,
                                         pullbackThresholdPct);
    }

    void ResetLifecycle()
    {
        m_lifecycleTracker.Reset();
    }

    //+------------------------------------------------------------------+
    //| TRADING SIGNAL GENERATION                                       |
    //+------------------------------------------------------------------+

    bool IsRangeTradingSignal()
    {
        MarketAnalysis analysis = GetCompleteAnalysis();

        // Signal for range trading when:
        // 1. In active range
        // 2. Price near range boundaries
        // 3. Good regime confidence

        if (analysis.lifecycle.state == LIFECYCLE_RANGE_ACTIVE &&
            analysis.regime.IsRanging() &&
            analysis.regime.confidence > 60)
        {
            RangeInfo range = GetCurrentRange();
            double currentPrice = analysis.currentPrice;
            double atr = CalculateATR(14);

            // Check if price near range edges
            double tolerance = atr * 0.15;

            bool nearTop = MathAbs(currentPrice - range.top) < tolerance;
            bool nearBottom = MathAbs(currentPrice - range.bottom) < tolerance;

            return nearTop || nearBottom;
        }

        return false;
    }

    bool IsBreakoutSignal()
    {
        MarketAnalysis analysis = GetCompleteAnalysis();

        // Signal for breakout when:
        // 1. Breakout just detected
        // 2. Or pullback breakout (trend resumption)

        return (analysis.lifecycle.state == LIFECYCLE_BREAKOUT_DETECTED ||
                analysis.lifecycle.state == LIFECYCLE_TREND_RESUMING);
    }

    bool IsTrendFollowingSignal()
    {
        MarketAnalysis analysis = GetCompleteAnalysis();

        // Signal for trend following when:
        // 1. In confirmed trend
        // 2. Good trend strength
        // 3. Not in significant pullback

        return (analysis.lifecycle.state == LIFECYCLE_TREND_CONFIRMED &&
                analysis.regime.IsTrending() &&
                analysis.regime.confidence > 70);
    }

    //+------------------------------------------------------------------+
    //| RISK MANAGEMENT HELPERS                                         |
    //+------------------------------------------------------------------+

    double GetRangeStopLossDistance()
    {
        RangeInfo range = GetCurrentRange();
        if (!range.IsValid())
            return 0.0;

        return (range.top - range.bottom) * 0.5; // Half the range width
    }

    double GetTrendStopLossDistance()
    {
        double atr = CalculateATR(14);
        return atr * 2.0; // 2 ATR for trend trades
    }

    //+------------------------------------------------------------------+
    //| UTILITY METHODS                                                 |
    //+------------------------------------------------------------------+

    void SetSymbol(string symbol)
    {
        m_symbol = symbol;
        m_regimeDetector.SetSymbol(symbol);
        // Note: MarketLifecycleTracker needs to be recreated or have a SetSymbol method
    }

    void SetTimeframe(ENUM_TIMEFRAMES tf)
    {
        m_timeframe = tf;
        m_regimeDetector.SetTimeframe(tf);
        // Note: MarketLifecycleTracker needs to be recreated or have a SetTimeframe method
    }

    string GetSymbol() const { return m_symbol; }
    ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }

    RangeInfo GetPullbackRange() const
    {
        return m_lifecycleTracker.GetPullbackRange();
    }
    
    bool ShouldReinitializeRange() const
    {
        // Check if we're in a pullback with valid range
        LifecycleState state = m_lifecycleTracker.GetCurrentState();
        RangeInfo pullback = m_lifecycleTracker.GetPullbackRange();
        
        return ((state.state == LIFECYCLE_PULLBACK_FORMING || 
                 state.state == LIFECYCLE_PULLBACK_ACTIVE) &&
                pullback.IsValid() && 
                pullback.widthPct >= 0.5); // Using minRangeWidthPct
    }
    
    
    // Manual reinitialization (for debugging)
    void ForceReinitializeRange()
    {
        // You'll need to add a public method to MarketLifecycleTracker
        // m_lifecycleTracker.InitializeRange();
    }

private:
    // Helper to calculate ATR
    double CalculateATR(int period = 14)
    {
        int handle = iATR(m_symbol, m_timeframe, period);
        if (handle == INVALID_HANDLE)
            return 0.0;

        double atr[];
        ArraySetAsSeries(atr, true);

        if (CopyBuffer(handle, 0, 0, 1, atr) > 0)
        {
            IndicatorRelease(handle);
            return atr[0];
        }

        IndicatorRelease(handle);
        return 0.0;
    }
};

//+------------------------------------------------------------------+
//| GLOBAL HELPER FUNCTIONS FOR DECISION ENGINE                    |
//+------------------------------------------------------------------+

// Quick unified analysis
MarketManager::MarketAnalysis QuickMarketAnalysis(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    static MarketManager *manager = NULL;

    if (manager == NULL || manager.GetSymbol() != symbol || manager.GetTimeframe() != tf)
    {
        if (manager != NULL)
            delete manager;
        manager = new MarketManager(symbol, tf);
    }

    return manager.GetCompleteAnalysis();
}

// Quick trading signal checks
bool IsGoodForRangeTrading(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    static MarketManager *manager = NULL;

    if (manager == NULL || manager.GetSymbol() != symbol || manager.GetTimeframe() != tf)
    {
        if (manager != NULL)
            delete manager;
        manager = new MarketManager(symbol, tf);
    }

    return manager.IsRangeTradingSignal();
}

bool IsGoodForBreakoutTrading(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    static MarketManager *manager = NULL;

    if (manager == NULL || manager.GetSymbol() != symbol || manager.GetTimeframe() != tf)
    {
        if (manager != NULL)
            delete manager;
        manager = new MarketManager(symbol, tf);
    }

    return manager.IsBreakoutSignal();
}

bool IsGoodForTrendTrading(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    static MarketManager *manager = NULL;

    if (manager == NULL || manager.GetSymbol() != symbol || manager.GetTimeframe() != tf)
    {
        if (manager != NULL)
            delete manager;
        manager = new MarketManager(symbol, tf);
    }

    return manager.IsTrendFollowingSignal();
}

//+------------------------------------------------------------------+
//| Market Drawing Manager Class - ADDED TO EXISTING FILE           |
//+------------------------------------------------------------------+
class MarketDrawingManager
{
private:
    MarketManager *m_marketManager;
    long m_chartId;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;

    // Drawing settings
    color m_trendUpColor;
    color m_trendDownColor;
    color m_rangeColor;
    color m_oldRangeColor;
    color m_unknownColor;
    color m_textColor;
    color m_rangeFillColor;
    color m_positionIndicatorColor;
    int m_fontSize;
    string m_fontName;

    // Range tracking for visualization
    RangeInfo m_currentRangeDisplay;
    RangeInfo m_previousRange;
    datetime m_rangeStartTime;
    bool m_hasValidRange;
    int m_rangeHistoryCount;
    RangeInfo m_rangeHistory[5]; // Keep last 5 ranges for context

    // Drawing objects tracking
    datetime m_lastUpdateTime;
    int m_lastLifecycleState;

public:
    // Constructor
    MarketDrawingManager(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
    {
        m_symbol = (symbol == NULL) ? Symbol() : symbol;
        m_timeframe = tf;
        m_chartId = ChartID();
        m_enabled = true;

        // Initialize drawing settings
        m_trendUpColor = clrLimeGreen;
        m_trendDownColor = clrRed;
        m_rangeColor = clrDodgerBlue;
        m_oldRangeColor = clrGray;
        m_unknownColor = clrGray;
        m_textColor = clrWhite;
        m_rangeFillColor = (color)ColorToARGB(clrDodgerBlue, 10); // Very transparent
        m_positionIndicatorColor = clrYellow;
        m_fontSize = 10;
        m_fontName = "Arial";

        // Initialize range tracking
        m_currentRangeDisplay = RangeInfo();
        m_previousRange = RangeInfo();
        m_rangeStartTime = 0;
        m_hasValidRange = false;
        m_rangeHistoryCount = 0;

        // Create MarketManager
        m_marketManager = new MarketManager(m_symbol, m_timeframe);
        m_lastUpdateTime = 0;
        m_lastLifecycleState = LIFECYCLE_UNKNOWN;

        Print("MarketDrawingManager initialized for " + m_symbol + " on " + TimeframeToString(m_timeframe));
    }

    // Destructor
    ~MarketDrawingManager()
    {
        RemoveAllDrawings();
        delete m_marketManager;
    }

    //+------------------------------------------------------------------+
    //| PUBLIC INTERFACE                                                |
    //+------------------------------------------------------------------+

    // Enable/disable drawing
    void EnableDrawing(bool enable = true)
    {
        m_enabled = enable;
        if (!enable)
            RemoveAllDrawings();
        else
            Update(true); // Force update when enabling
    }

    bool IsDrawingEnabled() const { return m_enabled; }

    // Update and draw current market state
    void Update(bool force = false)
    {
        if (!m_enabled)
            return;

        // Only update every 30 seconds to prevent flickering
        if (!force && TimeCurrent() - m_lastUpdateTime < 30)
            return;

        m_lastUpdateTime = TimeCurrent();

        // Get current market analysis
        MarketManager::MarketAnalysis analysis = m_marketManager.GetCompleteAnalysis();

        // Get current range and update position percentage
        RangeInfo currentRange = m_marketManager.GetCurrentRange();
        if (currentRange.IsValid())
        {
            // Calculate current position in range
            currentRange.currentPosition = currentRange.CalculatePosition(analysis.currentPrice);

            // Check if this is a new range
            if (!m_currentRangeDisplay.IsValid() ||
                MathAbs(m_currentRangeDisplay.top - currentRange.top) > 0.0001 ||
                MathAbs(m_currentRangeDisplay.bottom - currentRange.bottom) > 0.0001)
            {
                // Save old range to history
                if (m_currentRangeDisplay.IsValid())
                {
                    SaveRangeToHistory(m_currentRangeDisplay);
                }

                // Update current range
                m_currentRangeDisplay = currentRange;
                m_rangeStartTime = TimeCurrent();
                m_hasValidRange = true;
            }
            else
            {
                // Update position in existing range
                m_currentRangeDisplay.currentPosition = currentRange.currentPosition;
                m_currentRangeDisplay.touchCount = currentRange.touchCount;
            }
        }
        else
        {
            m_hasValidRange = false;
        }

        // Remove old drawings
        RemoveAllDrawings();

        // Draw range visualizations if we have valid range
        if (m_hasValidRange)
        {
            DrawRangeInfo(analysis);
            DrawRangePositionIndicator(); // NEW: Shows real-time % within range
        }

        DrawTrendInfo(analysis);
        DrawRangeHistory(); // NEW: Shows previous ranges

        // Update chart
        ChartRedraw(m_chartId);
    }

    // Quick status update (less frequent)
    void OnTimer()
    {
        Update(false);
    }

    //+------------------------------------------------------------------+
    //| DRAWING METHODS                                                 |
    //+------------------------------------------------------------------+

private:
    // Draw range information with enhanced features
    void DrawRangeInfo(const MarketManager::MarketAnalysis &analysis)
    {
        if (!m_currentRangeDisplay.IsValid())
            return;

        double currentPrice = analysis.currentPrice;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

        // Draw range top
        string topName = "Range_Top_Line";
        DrawHorizontalLine(topName, m_currentRangeDisplay.top, m_rangeColor, STYLE_DASH, 2,
                           StringFormat("Range Top: %.5f (%.2f%%)", m_currentRangeDisplay.top,
                                        ((m_currentRangeDisplay.top - currentPrice) / currentPrice) * 100.0));

        // Draw range bottom
        string bottomName = "Range_Bottom_Line";
        DrawHorizontalLine(bottomName, m_currentRangeDisplay.bottom, m_rangeColor, STYLE_DASH, 2,
                           StringFormat("Range Bottom: %.5f (%.2f%%)", m_currentRangeDisplay.bottom,
                                        ((currentPrice - m_currentRangeDisplay.bottom) / currentPrice) * 100.0));

        // Draw range area (semi-transparent)
        DrawRectangleOnChart("Range_Area", TimeCurrent() - (PeriodSeconds() * 50),
                             m_currentRangeDisplay.top,
                             TimeCurrent() + (PeriodSeconds() * 10),
                             m_currentRangeDisplay.bottom,
                             ColorToARGB(m_rangeColor, 10),
                             ColorToARGB(m_rangeColor, 100));

        // Draw range info box with position indicator
        string rangeInfoText = StringFormat("Range Width: %.2f%%\nTouches: %d\nCurrent Pos: %.1f%%",
                                            m_currentRangeDisplay.widthPct,
                                            m_currentRangeDisplay.touchCount,
                                            m_currentRangeDisplay.currentPosition);

        DrawTextOnChart("Range_Info", TimeCurrent() + (PeriodSeconds() * 15),
                        m_currentRangeDisplay.bottom + ((m_currentRangeDisplay.top - m_currentRangeDisplay.bottom) * 0.7),
                        rangeInfoText,
                        m_rangeColor, m_fontSize, m_fontName, ANCHOR_LEFT_UPPER);

        // Draw percentage scale on the right side
        DrawRangePercentageScale();
    }

    // NEW: Draw real-time position indicator within range
    void DrawRangePositionIndicator()
    {
        if (!m_currentRangeDisplay.IsValid())
            return;

        double rangeHeight = m_currentRangeDisplay.top - m_currentRangeDisplay.bottom;
        if (rangeHeight <= 0)
            return;

        // Draw position indicator line at current price
        // string positionLineName = "Range_Position_Line";
        // DrawHorizontalLine(positionLineName, iClose(m_symbol, m_timeframe, 0),
        //                    m_positionIndicatorColor, STYLE_DOT, 2,
        //                    StringFormat("Current: %.1f%%", m_currentRangeDisplay.currentPosition));

        // Draw percentage markers every 25%
        for (int i = 25; i <= 75; i += 25)
        {
            double priceLevel = m_currentRangeDisplay.bottom + (rangeHeight * i / 100.0);
            string markerName = "Range_Marker_" + IntegerToString(i);
            DrawHorizontalLine(markerName, priceLevel, clrDarkGray, STYLE_DOT, 1,
                               StringFormat("%d%%", i));

            // Add percentage label
            DrawTextOnChart("Range_Marker_Label_" + IntegerToString(i),
                            TimeCurrent() + (PeriodSeconds() * 5), priceLevel,
                            StringFormat("%d%%", i),
                            clrDarkGray, m_fontSize - 2, m_fontName, ANCHOR_LEFT);
        }
    }

    // NEW: Draw percentage scale on chart
    void DrawRangePercentageScale()
    {
        if (!m_currentRangeDisplay.IsValid())
            return;

        double rangeHeight = m_currentRangeDisplay.top - m_currentRangeDisplay.bottom;
        if (rangeHeight <= 0)
            return;

        // Draw vertical percentage bar
        for (int i = 0; i <= 100; i += 10)
        {
            double priceLevel = m_currentRangeDisplay.bottom + (rangeHeight * i / 100.0);
            string scaleName = "Range_Scale_" + IntegerToString(i);

            // Draw tick mark
            DrawTextOnChart(scaleName, TimeCurrent() - (PeriodSeconds() * 40), priceLevel,
                            StringFormat("%d%%", i),
                            clrGray, m_fontSize - 1, m_fontName, ANCHOR_RIGHT);
        }
    }

    // NEW: Save range to history
    void SaveRangeToHistory(RangeInfo &range)
    {
        if (m_rangeHistoryCount >= 5)
        {
            // Shift array
            for (int i = 0; i < 4; i++)
            {
                m_rangeHistory[i] = m_rangeHistory[i + 1];
            }
            m_rangeHistoryCount = 4;
        }

        m_rangeHistory[m_rangeHistoryCount] = range;
        m_rangeHistoryCount++;
    }

    // NEW: Draw range history
    void DrawRangeHistory()
    {
        for (int i = 0; i < m_rangeHistoryCount; i++)
        {
            if (m_rangeHistory[i].IsValid())
            {
                // Draw faded range lines for historical ranges
                string topName = "Range_History_Top_" + IntegerToString(i);
                string bottomName = "Range_History_Bottom_" + IntegerToString(i);

                DrawHorizontalLine(topName, m_rangeHistory[i].top, m_oldRangeColor, STYLE_DOT, 1,
                                   StringFormat("Old Range Top (%.2f%%)", m_rangeHistory[i].widthPct));
                DrawHorizontalLine(bottomName, m_rangeHistory[i].bottom, m_oldRangeColor, STYLE_DOT, 1,
                                   StringFormat("Old Range Bottom", ""));

                // Faded area
                DrawRectangleOnChart("Range_History_Area_" + IntegerToString(i),
                                     TimeCurrent() - (PeriodSeconds() * 100), m_rangeHistory[i].top,
                                     TimeCurrent() - (PeriodSeconds() * 50), m_rangeHistory[i].bottom,
                                     ColorToARGB(m_oldRangeColor, 5),
                                     ColorToARGB(m_oldRangeColor, 30));
            }
        }
    }

    // Draw trend information
    void DrawTrendInfo(const MarketManager::MarketAnalysis &analysis)
    {
        TrendInfo trend = m_marketManager.GetCurrentTrend();
        if (trend.direction == REGIME_UNKNOWN)
            return;

        // Draw trend info box
        color trendColor = (trend.direction == REGIME_TRENDING_UP) ? m_trendUpColor : m_trendDownColor;

        DrawTextOnChart("Trend_Info", TimeCurrent() + (PeriodSeconds() * 20),
                        trend.currentPrice,
                        StringFormat("Trend: %s\nMove: %.2f%%\nBars: %d",
                                     (trend.direction == REGIME_TRENDING_UP) ? "UP" : "DOWN",
                                     trend.totalMovePct,
                                     trend.trendBars),
                        trendColor, m_fontSize, m_fontName, ANCHOR_LEFT_UPPER);

        // Draw trend line (simplified - connects start to current)
        if (trend.trendBars > 5) // Only draw after enough bars
        {
            string trendLineName = "Trend_Line";
            DrawTrendLine(trendLineName, TimeCurrent() - (PeriodSeconds() * trend.trendBars),
                          trend.startPrice, TimeCurrent(), trend.currentPrice,
                          trendColor, STYLE_SOLID, 2);
        }

        // Draw pullback info if applicable
        double retracePct = trend.GetCurrentRetracementPct();
        if (retracePct > 10.0) // Significant retracement
        {
            DrawTextOnChart("Retracement", TimeCurrent() - (PeriodSeconds() * 2), trend.currentPrice,
                            StringFormat("Retrace: %.1f%%", retracePct),
                            (retracePct > 50.0) ? clrOrangeRed : clrOrange,
                            m_fontSize - 1, m_fontName, ANCHOR_LEFT_LOWER);
        }
    }

    //+------------------------------------------------------------------+
    //| VISUALIZATION HELPERS                                           |
    //+------------------------------------------------------------------+

    void DrawRangeVisualization()
    {
        // Draw dots showing recent price action within range
        for (int i = 0; i < 20; i++)
        {
            double price = iClose(m_symbol, m_timeframe, i);
            if (m_currentRangeDisplay.IsValid() && m_currentRangeDisplay.IsPriceInside(price))
            {
                string dotName = "Range_Dot_" + IntegerToString(i);
                DrawDot(dotName, TimeCurrent() - (PeriodSeconds() * i), price,
                        m_rangeColor, 3);
            }
        }
    }

    void DrawTrendVisualization()
    {
        TrendInfo trend = m_marketManager.GetCurrentTrend();
        if (trend.direction == REGIME_UNKNOWN)
            return;

        // Draw trend momentum dots
        for (int i = 0; i < 10; i++)
        {
            double price = iClose(m_symbol, m_timeframe, i);
            string dotName = "Trend_Dot_" + IntegerToString(i);
            DrawDot(dotName, TimeCurrent() - (PeriodSeconds() * i), price,
                    (trend.direction == REGIME_TRENDING_UP) ? m_trendUpColor : m_trendDownColor,
                    2);
        }
    }

    void DrawPullbackVisualization()
    {
        RangeInfo pullback = m_marketManager.GetPullbackRange();
        if (!pullback.IsValid())
            return;

        // Draw pullback range
        string topName = "Pullback_Top_Line";
        DrawHorizontalLine(topName, pullback.top, clrOrange, STYLE_DOT, 1);

        string bottomName = "Pullback_Bottom_Line";
        DrawHorizontalLine(bottomName, pullback.bottom, clrOrange, STYLE_DOT, 1);

        // Draw pullback area
        DrawRectangleOnChart("Pullback_Area", TimeCurrent() - (PeriodSeconds() * 20),
                             pullback.top, TimeCurrent(), pullback.bottom,
                             ColorToARGB(clrOrange, 10), ColorToARGB(clrOrange, 50));
    }

    void DrawBreakoutVisualization()
    {
        if (!m_currentRangeDisplay.IsValid())
            return;

        // Highlight breakout direction
        double currentPrice = iClose(m_symbol, m_timeframe, 0);
        color breakoutColor = (currentPrice > m_currentRangeDisplay.top) ? m_trendUpColor : m_trendDownColor;

        // Draw breakout arrow
        string arrowName = "Breakout_Arrow";
        double arrowPrice = (currentPrice > m_currentRangeDisplay.top) ? m_currentRangeDisplay.top : m_currentRangeDisplay.bottom;
        DrawArrow(arrowName, TimeCurrent() - PeriodSeconds(), arrowPrice,
                  breakoutColor, (currentPrice > m_currentRangeDisplay.top) ? OBJ_ARROW_UP : OBJ_ARROW_DOWN);
    }

    void DrawTrendResumptionVisualization()
    {
        // Draw resumption confirmation dots
        for (int i = 0; i < 5; i++)
        {
            double price = iClose(m_symbol, m_timeframe, i);
            string dotName = "Resumption_Dot_" + IntegerToString(i);
            DrawDot(dotName, TimeCurrent() - (PeriodSeconds() * i), price,
                    clrLimeGreen, 3);
        }
    }

    //+------------------------------------------------------------------+
    //| DRAWING PRIMITIVES                                              |
    //+------------------------------------------------------------------+

    void DrawText(string name, int x, int y, string text, color clr, int fontSize = 10,
                  string fontName = "Arial", bool bold = false)
    {
        // Delete object if it exists
        if (ObjectFind(m_chartId, name) >= 0)
            ObjectDelete(m_chartId, name);

        ObjectCreate(m_chartId, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y);
        ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, fontSize);

        if (bold)
            ObjectSetString(m_chartId, name, OBJPROP_FONT, "Arial Bold");
        else
            ObjectSetString(m_chartId, name, OBJPROP_FONT, fontName);

        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawTextOnChart(string name, datetime time, double price, string text,
                         color clr, int fontSize = 10, string fontName = "Arial",
                         ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER)
    {
        ObjectCreate(m_chartId, name, OBJ_TEXT, 0, time, price);
        ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, fontSize);
        ObjectSetString(m_chartId, name, OBJPROP_FONT, fontName);
        ObjectSetInteger(m_chartId, name, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawRectangle(string name, int x1, int y1, int x2, int y2,
                       color bgColor, color borderColor)
    {
        ObjectCreate(m_chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x1);
        ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y1);
        ObjectSetInteger(m_chartId, name, OBJPROP_XSIZE, x2 - x1);
        ObjectSetInteger(m_chartId, name, OBJPROP_YSIZE, y2 - y1);
        ObjectSetInteger(m_chartId, name, OBJPROP_BGCOLOR, bgColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(m_chartId, name, OBJPROP_BORDER_COLOR, borderColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawRectangleOnChart(string name, datetime time1, double price1,
                              datetime time2, double price2, color bgColor, color borderColor)
    {
        ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, borderColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BGCOLOR, bgColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawHorizontalLine(string name, double price, color clr, ENUM_LINE_STYLE style = STYLE_SOLID,
                            int width = 1, string description = "")
    {
        ObjectCreate(m_chartId, name, OBJ_HLINE, 0, 0, price);
        ObjectSetDouble(m_chartId, name, OBJPROP_PRICE, price);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, style);
        ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);

        if (description != "")
        {
            ObjectSetString(m_chartId, name, OBJPROP_TOOLTIP, description);
        }
    }

    void DrawTrendLine(string name, datetime time1, double price1,
                       datetime time2, double price2, color clr,
                       ENUM_LINE_STYLE style = STYLE_SOLID, int width = 1)
    {
        ObjectCreate(m_chartId, name, OBJ_TREND, 0, time1, price1, time2, price2);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, style);
        ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_RAY, false);
    }

    void DrawDot(string name, datetime time, double price, color clr, int size = 3)
    {
        ObjectCreate(m_chartId, name, OBJ_ARROW, 0, time, price);
        ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, 108);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, size);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawArrow(string name, datetime time, double price, color clr, int arrowCode)
    {
        // Delete object if it exists
        if (ObjectFind(m_chartId, name) >= 0)
            ObjectDelete(m_chartId, name);

        ObjectCreate(m_chartId, name, OBJ_ARROW, 0, time, price);
        ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
    }

    void DrawStrengthBar(string name, int x, int y, double strength, string label, color clr)
    {
        // Draw label
        DrawText(name + "_Label", x, y, label, m_textColor, m_fontSize - 1, m_fontName);

        // Draw background bar
        int barWidth = 100;
        int barHeight = 8;
        DrawRectangle(name + "_BG", x + 90, y - 2, x + 90 + barWidth, y + barHeight + 2,
                      clrDarkGray, clrDarkGray);

        // Draw strength bar (absolute value for display)
        int fillWidth = (int)(barWidth * (MathAbs(strength) / 100.0));
        if (fillWidth > 0)
        {
            DrawRectangle(name + "_Fill", x + 90, y - 2, x + 90 + fillWidth, y + barHeight + 2,
                          clr, clr);
        }

        // Draw strength value with sign
        string sign = strength >= 0 ? "+" : "";
        DrawText(name + "_Value", x + 90 + barWidth + 5, y,
                 StringFormat("%s%.0f", sign, strength), clr, m_fontSize - 1, m_fontName);
    }

    void RemoveAllDrawings()
    {
        int total = ObjectsTotal(m_chartId);
        for (int i = total - 1; i >= 0; i--)
        {
            string name = ObjectName(m_chartId, i);
            if (StringFind(name, "Market_") == 0 ||
                StringFind(name, "Range_") == 0 ||
                StringFind(name, "Trend_") == 0 ||
                StringFind(name, "Lifecycle_") == 0 ||
                StringFind(name, "Pullback_") == 0 ||
                StringFind(name, "Breakout_") == 0 ||
                StringFind(name, "Resumption_") == 0)
            {
                ObjectDelete(m_chartId, name);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| HELPER FUNCTIONS                                                |
    //+------------------------------------------------------------------+

    color GetRegimeColor(ENUM_MARKET_REGIME regime)
    {
        switch (regime)
        {
        case REGIME_TRENDING_UP:
            return m_trendUpColor;
        case REGIME_TRENDING_DOWN:
            return m_trendDownColor;
        case REGIME_RANGING:
            return m_rangeColor;
        default:
            return m_unknownColor;
        }
    }

    color GetLifecycleColor(ENUM_MARKET_LIFECYCLE state)
    {
        switch (state)
        {
        case LIFECYCLE_RANGE_FORMING:
        case LIFECYCLE_RANGE_ACTIVE:
            return m_rangeColor;

        case LIFECYCLE_BREAKOUT_DETECTED:
            return clrOrange;

        case LIFECYCLE_TREND_CONFIRMED:
        case LIFECYCLE_TREND_RESUMING:
            return m_trendUpColor;

        case LIFECYCLE_PULLBACK_FORMING:
        case LIFECYCLE_PULLBACK_ACTIVE:
            return clrOrangeRed;

        case LIFECYCLE_TREND_WEAKENING:
            return clrYellow;

        default:
            return m_unknownColor;
        }
    }

    // NEW: Get color based on position in range
    color GetPositionColor(double position)
    {
        if (position < 20)
            return clrRed; // Near bottom - oversold
        if (position > 80)
            return clrLimeGreen; // Near top - overbought
        if (position < 40)
            return clrOrange; // Lower half
        if (position > 60)
            return clrDodgerBlue; // Upper half
        return clrYellow;         // Middle
    }

    string GetRegimeString(ENUM_MARKET_REGIME regime)
    {
        switch (regime)
        {
        case REGIME_TRENDING_UP:
            return "TRENDING UP";
        case REGIME_TRENDING_DOWN:
            return "TRENDING DOWN";
        case REGIME_RANGING:
            return "RANGING";
        default:
            return "UNKNOWN";
        }
    }

    string TimeframeToString(ENUM_TIMEFRAMES tf)
    {
        switch (tf)
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
            return "MN";
        default:
            return IntegerToString(tf);
        }
    }

    // Convert color to ARGB with alpha transparency
    uint ColorToARGB(color clr, uchar alpha = 255)
    {
        return ((uint)alpha << 24) | ((uint)clr & 0xFFFFFF);
    }
};

//+------------------------------------------------------------------+
//| Global Market Drawing Functions - ADDED TO EXISTING FILE        |
//+------------------------------------------------------------------+

// Global instance for easy access
MarketDrawingManager *g_marketDrawer = NULL;

// Initialize market drawing
void InitializeMarketDrawing(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_H1)
{
    if (g_marketDrawer != NULL)
    {
        delete g_marketDrawer;
    }

    g_marketDrawer = new MarketDrawingManager(symbol, tf);
    Print("Market Drawing initialized");
}

// Update market drawing
void UpdateMarketDrawing(bool force = false)
{
    if (g_marketDrawer != NULL)
    {
        g_marketDrawer.Update(force);
    }
}

// Toggle market drawing
void ToggleMarketDrawing(bool enable)
{
    if (g_marketDrawer != NULL)
    {
        g_marketDrawer.EnableDrawing(enable);
    }
}

// Cleanup market drawing
void CleanupMarketDrawing()
{
    if (g_marketDrawer != NULL)
    {
        delete g_marketDrawer;
        g_marketDrawer = NULL;
    }
}

// Simple function to check if drawing is enabled
bool IsMarketDrawingEnabled()
{
    return g_marketDrawer != NULL && g_marketDrawer.IsDrawingEnabled();
}


++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




Recreate this file to be simple as it now has too many things going on.
i am thinking one file rather than so many different classes. just one properly thought of but simple file.

REGIME SIMPLE LOGIC:

Complete Market Regime Framework: States, Lifecycle, Trading Rules & Display:

getMarketRegime()
    first establish a width:
        price high/low in last few bars "5 bars" using H1. 
            this then becomes a fixed range till invalidated.
            when formed the drawing is displayed and when invalidated then no drawing.
        QUICKLY:
            CHECK for state:
                1. ADX/BB/MAs/CANDLES/VOLUME/ATR/OTHER RELEVANT INDICATORS: 
                ADX:
                - < 20 → Ranging/Contraction
                - 25-40 → Trending
                - > 40 → Exhaustion Risk
                ATR/Bollinger Width:
                - Low & falling → Contraction/Squeeze
                - Low & rising → Early Trend
                - High & rising → Late Trend/Expansion
                - High & stable → Range High Vol

                2. Structure:
                - HH/HL or LH/LL → Trending
                - Horizontal S/R → Ranging
                - Failed extremes → Churn/Exhaustion

            return the state //could be trending with low volatility and rising...


        Then anticipate next most likely move instead of react, ie:
            - Tight candles after long range? → Phase 1 (ACTION_ONE)
            - Just broke out? → Phase 2 (ACTION_TWO)
            - Steady move with pullbacks? → Phase 3 (ACTION_THREE)
            - Parabolic, everyone talking? → Phase 4 (ACTION_FOUR)
            - Wide bars, no progress? → Phase 5/6 (ACTION_FIVE)

    then from the fixed width: 
    return marketState and nextMostLikelyProgression


REGIME SIMPLE LOGIC IMPLIMENTATION LOGIC:

check for the state we are in:
    1. Ranging – Low Volatility (State 1)
        * Volatility: Low & Stable
        * Character: Consolidation, equilibrium, boredom
        * Price/Indicators: 
            - Tight candles inside horizontal S/R
            - Flat MAs (50,89), ADX < 20, ATR low & flat
            - Bollinger Bands squeezed
        * Tradability: High for mean reversion
        * Direction: Neutral
        * Maturity: Late-stage - range established, awaiting catalyst
        * Lifecycle Position: Phase 1/7 - Beginning or end of cycle
        * Trading Rules:
            - Fade range extremes with tight stops
            - Prepare breakout alerts above/below range
            - Reduce position size as range matures
            - Wait for volatility contraction (next phase)

    ---

    2. Contraction/Squeeze (State 5)
        * Volatility: Low & Falling
        * Character: Coiling, compression, indecision
        * Price/Indicators:
            - Extremely tight candles (doji, spinning tops)
            - Bollinger Bands width at multi-period low
            - ADX < 15, ATR at lows
        * Tradability: Prepare, dont trade - no edge until breakout
        * Direction: Neutral (latent)
        * Maturity: Transition - energy building for next move
        * Lifecycle Position: Phase 1 → Phase 2 transition
        * Trading Rules:
            - Set breakout alerts
            - Prepare capital allocation for next move
            - Avoid fading range edges now
            - Wait for the expansion candle

    ---

    3. Expansion/Breakout Test (State 6)
        * Volatility: High & Rising
        * Character: Breakout attempt, momentum surge
        * Price/Indicators:
            - Large candle breaking key level
            - Volume spike, ATR jumps
            - ADX may still be low but rising
        * Tradability: Conditional - true vs false break decision
        * Direction: Emerging
        * Maturity: Infant stage - new trend may be born
        * Lifecycle Position: Phase 2 - Breakout Decision Point
        * Trading Rules:
            - Wait for close beyond range (not just wick)
            - Dont chase - let price retest breakout level
            - Confirm with follow-through candle
            - Beware low-volume breaks (traps)

    ---

    4. Trending – Low Volatility (State 3)
        * Volatility: Low & Rising
        * Character: Healthy, institutional trend
        * Price/Indicators:
            - Steady candles in one direction
            - MAs aligned as dynamic S/R
            - ADX rising (25-40), ATR gradually increasing
        * Tradability: Very High - ideal conditions
        * Direction: Strong (Up/Down)
        * Maturity: Early to Mid-stage - established but not crowded
        * Lifecycle Position: Phase 3 - Trend Birth & Acceptance
        * Trading Rules:
            - Enter on first pullback to breakout level
            - Add to position on subsequent higher lows
            - Use loose trailing stops
            - This is highest probability phase

    ---

        5. Trending – High Volatility (State 4)
        * Volatility: High & Expanding
        * Character: Climactic, emotional, parabolic
        * Price/Indicators:
            - Large candles, gaps, exhaustion patterns
            - ADX > 40, ATR spiking
            - MAs far from price
        * Tradability: Low - caution, reversal risk high
        * Direction: Strong but weakening
        * Maturity: Late-stage - overextended, smart money distributing
        * Lifecycle Position: Phase 4 - Trend Maturity & Euphoria
        * Trading Rules:
            - Take partial profits (25-50%)
            - Tighten stops to protect gains
            - No new entries
            - Watch for exhaustion patterns

    ---

    6. Churn/Exhaustion (State 7)
        * Volatility: High & Unstable
        * Character: Directionless volatility, distribution
        * Price/Indicators:
            - Large, overlapping candles, no progress
            - ADX falling from >40, ATR erratic
            - Broadening formation patterns
        * Tradability: Avoid - whipsaw kills accounts
        * Direction: Neutralizing
        * Maturity: Terminal stage - old trend dying
        * Lifecycle Position: Phase 5 - Distribution & Exhaustion
        * Trading Rules:
            - Exit remaining positions
            - Prepare to fade extremes (small size only)
            - Shift to range/reversal mindset
            - Set alerts for key breaks

    ---

    7. Ranging – High Volatility (State 2)
        * Volatility: High & Stable
        * Character: Choppy, emotional swings within bounds
        * Price/Indicators:
            - Wide candles but failing at S/R
            - High ATR, ADX still low (<25)
            - Volume spikes at edges
        * Tradability: Low - dangerous, stop hunts frequent
        * Direction: Neutral
        * Maturity: Mid-stage - unstable, may precede expansion/contraction
        * Lifecycle Position: Phase 6 Path B or Phase 7 early
        * Trading Rules:
            - Fade extremes but expect stop runs
            - Very tight stops if trading
            - Better to wait for stabilization
            - This is the "trap zone"

    ---

ONCE STATE IS UNDERSTOOD THEN CRITICAL TRANSITIONS & DECISION POINTS

    ---

    NEXT MOST LIKELY PROGRESSION

Root State        | Current State         | Direction if applicable | Next Likely States                            | YOUR RECOMMENDATION       | Position Size | Stop Placement |RR-recomendation
|---------------  |---------------        |-----------------        |-----------------                              |-------------              |---------------|----------------|----------------
REGIME_RANGING    | Ranging Low Vol       | Direction if applicable | Contraction (5) or Range High Vol (2)         | Fade edges                | Small         | Very tight     |RR-recomendation
REGIME_UNKNOWN    | Contraction           | Direction if applicable | Expansion (6)                                 | Wait for break            | Zero          | N/A            |RR-recomendation
REGIME_TRENDING   | Expansion             | Direction if applicable | Trending Low Vol (3) or Range High Vol (2)    | Test entry                | Medium        | Below breakout |RR-recomendation
REGIME_TRENDING   | Trending Low Vol      | Direction if applicable | Trending High Vol (4)                         | Add to winners            | Large         | Loose trailing |RR-recomendation
REGIME_TRENDING   | Trending High Vol     | Direction if applicable | Churn (7)                                     | Take profits              | Reducing      | Tightening     |RR-recomendation
REGIME_UNKNOWN    | Churn                 | Direction if applicable | Range High Vol (2) or Trending Low Vol (3)    | Wait for clarity          | Zero          | N/A            |RR-recomendation
REGIME_RANGING    | Range High Vol        | Direction if applicable | Range Low Vol (1)                             | Fade carefully            | Very small    | Extremely tight|RR-recomendation

    ---






    
so the regime basically comes with:
0. rootState
1. state.
2. next most likely state.
3. action recommendattion.
4. position size recommendation, also base this on acount size and symbol.
5. tp/sl recommendation, also base this on acount size and symbol.
6. risk to reward recommendation.
7. Direction recommendation