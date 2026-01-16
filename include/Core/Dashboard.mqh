//+------------------------------------------------------------------+
//|                     ENHANCED DASHBOARD v2.0                     |
//|                    Compact Professional Display                 |
//+------------------------------------------------------------------+

#ifndef DASHBOARD_MQH_V2
#define DASHBOARD_MQH_V2

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

// ==================== DASHBOARD MANAGER CLASS ====================
class CompactDashboard
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
    CompactDashboard() : m_symbol(""),
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
                    DecisionEngine *decisionEng)
    {
        if (symbol == "" || pkgManager == NULL || decisionEng == NULL)
        {
            Print("ERROR: CompactDashboard - Invalid initialization parameters");
            return false;
        }

        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_packageManager = pkgManager;
        m_decisionEngine = decisionEng;

        // Create regime detector
        m_regimeDetector = new MarketRegimeDetector(symbol, PERIOD_H1);
        if (m_regimeDetector != NULL)
        {
            double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            double riskPercent = 1.0;
            m_regimeDetector.SetAccountInfo(accountBalance, riskPercent);
            Print("Market Regime Detector initialized");
        }

        Print("CompactDashboard initialized for " + symbol);
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
    }

    // Main update function
    void UpdateDisplay(bool forceUpdate = false)
    {
        // Update every 2 seconds
        if (!forceUpdate && (TimeCurrent() - m_lastUpdateTime) < 2)
            return;

        m_lastUpdateTime = TimeCurrent();

        string display = GenerateCompactDashboard();

        if (forceUpdate || display != m_lastDisplay)
        {
            Comment(display);
            m_lastDisplay = display;
        }
    }

    // Generate compact dashboard
    string GenerateCompactDashboard()
    {
        string display = "";

        display += "\n\n";

        // ==================== HEADER ====================
        display += StringFormat("|%s|%s|\n",
                                PadCenter("mk$ EA v3.11 - GOLD SPECIALIST", 50),
                                PadRight(TimeToString(TimeCurrent(), TIME_SECONDS), 8));

        display += SeparatorLine();

        display += StringFormat("|%s|%s|%s|\n",
                                PadRight(m_symbol, 10),
                                PadRight(TimeframeToString(Period()), 4),
                                GetTradingSessionShort());

        display += SeparatorLine();

        // ==================== ACCOUNT INFO ====================
        display += GenerateAccountInfoSection();

        display += SeparatorLine();

        // ==================== SIGNALS SECTION ====================
        display += GenerateSignalsSection();

        display += SeparatorLine();

        // ==================== TRADING INFO ====================
        display += GenerateTradingInfoSection();

        display += SeparatorLine();

        // ==================== CONDITIONAL DISPLAY ====================
        display += GenerateConditionalSection();

        display += SeparatorLine();

        // ==================== SETUP SECTION ====================
        display += GenerateSetupSection();

        display += SeparatorLine();

        // ==================== ACTION SECTION ====================
        display += GenerateActionSection();

        display += SeparatorLine();

        // ==================== DESCRIPTION ====================
        display += GenerateDescriptionSection();

        display += SeparatorLine();

        // ==================== DECISION & STATS ====================
        display += GenerateDecisionStatsSection();

        display += SeparatorLine();

        return display;
    }

private:
    // ==================== SECTION GENERATORS ====================

    string GenerateAccountInfoSection()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double margin = AccountInfoDouble(ACCOUNT_MARGIN);
        double marginLevel = margin > 0 ? equity / margin * 100 : 0;

        return StringFormat("Account: $%.0f | Eq: $%.0f | ML: %.1f%% | %s\n",
                            balance, equity, marginLevel, GetTradingSessionShort());
    }

    string GenerateSignalsSection()
    {
        string section = "";

        if (m_regimeDetector != NULL)
        {
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            // Root State
            string rootState = MarketAnalysis::GetRootStateString(analysis.rootState);
            string state = MarketAnalysis::GetStateString(analysis.state);
            string nextState = MarketAnalysis::GetStateString(analysis.nextLikelyState);

            section += StringFormat("Sig: %s | %s -> %s\n",
                                    rootState, state, nextState);
        }
        else
        {
            section += "Signal: NO_DATA | NO_DATA -> NO_DATA\n";
        }

        return section;
    }

    string GenerateTradingInfoSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);

            if (lastPackage.IsValid())
            {
                string packageType = lastPackage.IsRangePackage() ? "Range" : "Trend";
                string direction = ConvertDirection(lastPackage.dominantDirection);

                section += StringFormat("Pkg: %s | %s | Conf: %.0f%%\n",
                                        packageType, direction, lastPackage.overallConfidence);
            }
            else
            {
                section += "Package: NONE | NONE | Conf: 0%\n";
            }
        }

        return section;
    }

    string GenerateConditionalSection()
    {
        string section = "";

        if (m_regimeDetector == NULL || m_decisionEngine == NULL)
            return section;

        MarketAnalysis regime = m_regimeDetector.GetMarketRegime();
        DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);

        if (regime.IsTrending())
        {
            // Display trend components
            section += "Trend Info: ";
            if (lastPackage.IsValid())
            {
                // Simple component display - in real implementation, you would extract these from modules
                section += "MTF/" + GetDirectionSymbol(lastPackage.dominantDirection) + "/80% ";
                section += "POI/" + GetDirectionSymbol(lastPackage.dominantDirection) + "/75% ";
                section += "RSI/" + GetDirectionSymbol(lastPackage.dominantDirection) + "/70%";
            }
            section += "\n";
        }
        else if (regime.IsRanging())
        {
            // Display range info
            if (m_regimeDetector.IsRangeActive())
            {
                double top = m_regimeDetector.GetRangeTop();
                double bottom = m_regimeDetector.GetRangeBottom();
                double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

                if (top > bottom)
                {
                    double positionPercent = ((currentPrice - bottom) / (top - bottom)) * 100;
                    section += StringFormat("Range Info: %.2f-%.2f | Pos: %.0f%%\n",
                                            bottom, top, positionPercent);
                }
            }

            // Display range components
            section += "Comp: COMP1/B/40% COMP2/B/40% COMP3/B/40%\n";
        }

        return section;
    }

    string GenerateSetupSection()
    {
        string section = "";

        if (m_regimeDetector != NULL)
        {
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            section += StringFormat("Setup: %s | SL: %.1f | TP: %.1f | RR: %.1f\n",
                                    GetPositionSizeShort(analysis.positionSize),
                                    analysis.stopDistance,
                                    analysis.takeProfitDistance,
                                    analysis.riskRewardRatio);
        }
        else
        {
            section += "Setup: NONE | SL: 0.0 | TP: 0.0 | RR: 0.0\n";
        }

        return section;
    }

    string GenerateActionSection()
    {
        string section = "";

        if (m_regimeDetector != NULL)
        {
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            // Get action with direction
            string action = GetCompactAction(analysis.action, analysis.direction);

            // Add market state warnings
            string warning = "";
            if (analysis.state == STATE_RANGING_HIGH_VOL || analysis.state == STATE_CHURN)
                warning = "High Volatility ";
            else if (analysis.state == STATE_CONTRACTION)
                warning = "Small Stops ";

            section += StringFormat("Action: %s%s\n", warning, action);
        }

        return section;
    }

    string GenerateDescriptionSection()
    {
        string section = "";

        if (m_regimeDetector != NULL)
        {
            MarketAnalysis analysis = m_regimeDetector.GetMarketRegime();

            // Truncate description to fit
            string shortDesc = TruncateString(analysis.description, 60);

            section += StringFormat("Description: %s\n", shortDesc);
        }

        return section;
    }

    string GenerateDecisionStatsSection()
    {
        string section = "";

        // Decision
        if (m_decisionEngine != NULL)
        {
            DECISION_ACTION lastDecision = m_decisionEngine.GetLastDecision(m_symbol);
            string decisionStr = ConvertDecisionToDirection(lastDecision);

            // Get position count
            int positionCount = GetPositionCount();
            string positionStr = positionCount > 0 ? StringFormat("%d Positions", positionCount) : "NO_POS";

            section += StringFormat("Decision: %s | %s", decisionStr, positionStr);
        }
        else
        {
            section += "Decision: NONE | NO_POS";
        }

        // Statistics
        if (m_decisionEngine != NULL)
        {
            DecisionMetrics metrics = m_decisionEngine.GetMetrics();

            // Safety check
            if (metrics.totalDecisions < 0)
                metrics.totalDecisions = 0;
            if (metrics.profitableDecisions < 0)
                metrics.profitableDecisions = 0;
            if (metrics.profitableDecisions > metrics.totalDecisions)
                metrics.profitableDecisions = metrics.totalDecisions;

            // Add win/loss count for clarity
            int losingTrades = metrics.totalDecisions - metrics.profitableDecisions;

            string accuracyStr = "0%";
            if (metrics.totalDecisions > 0)
            {
                // Calculate fresh accuracy
                double accuracy = ((double)metrics.profitableDecisions / metrics.totalDecisions) * 100.0;

                // Bounds check
                if (accuracy < 0)
                    accuracy = 0;
                if (accuracy > 100)
                    accuracy = 100;

                accuracyStr = StringFormat("%.1f%%", accuracy);
            }

            section += StringFormat(" | Trades: %d | W:%d L:%d | WinRate: %s\n",
                                    metrics.totalDecisions,
                                    metrics.profitableDecisions,
                                    losingTrades,
                                    accuracyStr);
        }
        else
        {
            section += " | Trades: 0 | W:0 L:0 | Win: 0.0%\n";
        }

        return section;
    }

    // ==================== HELPER FUNCTIONS ====================

    string ConvertDirection(string direction)
    {
        if (direction == "BULLISH")
            return "LONG";
        if (direction == "BEARISH")
            return "SHORT";
        if (direction == "NEUTRAL")
            return "NEUTRAL";
        return "NONE";
    }

    string GetDirectionSymbol(string direction)
    {
        if (direction == "BULLISH")
            return "B";
        if (direction == "BEARISH")
            return "S";
        return "N";
    }

    string ConvertDecisionToDirection(DECISION_ACTION decision)
    {
        switch (decision)
        {
        case ACTION_OPEN_BUY:
        case ACTION_CLOSE_SELL:
            return "LONG";
        case ACTION_OPEN_SELL:
        case ACTION_CLOSE_BUY:
            return "SHORT";
        case ACTION_HOLD:
            return "HOLD";
        case ACTION_WAITING_FOR_PACKAGE:
            return "WAIT";
        default:
            return "NONE";
        }
    }

    string GetCompactAction(string action, string direction)
    {
        string dirShort = "";
        if (direction == "Bullish")
            dirShort = " (BULL)";
        else if (direction == "Bearish")
            dirShort = " (BEAR)";

        if (StringFind(action, "Fade") >= 0)
            return "FADE" + dirShort;
        if (StringFind(action, "Add") >= 0 || StringFind(action, "Test") >= 0)
            return "FOLLOW" + dirShort;
        if (StringFind(action, "Take") >= 0)
            return "TAKE_PROFIT";
        if (StringFind(action, "Exit") >= 0 || StringFind(action, "Wait") >= 0)
            return "EXIT/WAIT";
        if (StringFind(action, "Prepare") >= 0)
            return "PREPARE" + dirShort;

        return action + dirShort;
    }

    string GetPositionSizeShort(ENUM_POSITION_SIZE size)
    {
        switch (size)
        {
        case SIZE_ZERO:
            return "ZERO";
        case SIZE_VERY_SMALL:
            return "VSML";
        case SIZE_SMALL:
            return "SML";
        case SIZE_MEDIUM:
            return "MED";
        case SIZE_LARGE:
            return "LRG";
        default:
            return "NONE";
        }
    }

    string GetTradingSessionShort()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);

        if (dt.hour >= 0 && dt.hour < 5)
            return "ASIA";
        if (dt.hour >= 5 && dt.hour < 14)
            return "LONDON";
        if (dt.hour >= 14 && dt.hour < 21)
            return "US";
        return "NIGHT";
    }

    int GetPositionCount()
    {
        int count = 0;
        for (int i = 0; i < PositionsTotal(); i++)
        {
            if (PositionGetTicket(i))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);

                if (posSymbol == m_symbol && posMagic == m_magicNumber)
                {
                    count++;
                }
            }
        }
        return count;
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
        default:
            return IntegerToString(tf);
        }
    }

    string PadRight(string text, int length)
    {
        int textLen = StringLen(text);
        if (textLen >= length)
            return text;

        string padding = "";
        for (int i = 0; i < length - textLen; i++)
            padding += " ";

        return text + padding;
    }

    string PadLeft(string text, int length)
    {
        int textLen = StringLen(text);
        if (textLen >= length)
            return text;

        string padding = "";
        for (int i = 0; i < length - textLen; i++)
            padding += " ";

        return padding + text;
    }

    string PadCenter(string text, int length)
    {
        int textLen = StringLen(text);
        if (textLen >= length)
            return StringSubstr(text, 0, length);

        int leftPad = (length - textLen) / 2;
        int rightPad = length - textLen - leftPad;

        string result = "";
        for (int i = 0; i < leftPad; i++)
            result += " ";
        result += text;
        for (int i = 0; i < rightPad; i++)
            result += " ";

        return result;
    }

    string SeparatorLine()
    {
        return "--------------------------------------------------------------------\n";
    }

    string TruncateString(string text, int maxLength)
    {
        if (StringLen(text) <= maxLength)
            return text;
        return StringSubstr(text, 0, maxLength - 3) + "...";
    }
};

// ==================== GLOBAL FUNCTION ====================

void ShowCompactDashboard(string symbol,
                          int magicNumber,
                          PackageManager &pkgManager,
                          DecisionEngine &decisionEngineObj)
{
    static CompactDashboard dashboard;
    static bool initialized = false;

    if (!initialized)
    {
        if (dashboard.Initialize(symbol, magicNumber, GetPointer(pkgManager),
                                 GetPointer(decisionEngineObj)))
        {
            initialized = true;
            Print("CompactDashboard initialized");
        }
    }

    if (initialized)
    {
        dashboard.UpdateDisplay();
    }
}

#endif // DASHBOARD_MQH_V2