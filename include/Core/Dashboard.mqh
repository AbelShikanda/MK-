//+------------------------------------------------------------------+
//|                     ENHANCED DASHBOARD v3.0                     |
//|                    Complete Component Display                   |
//+------------------------------------------------------------------+

#ifndef DASHBOARD_MQH_V3
#define DASHBOARD_MQH_V3

#include <Trade\PositionInfo.mqh>

#include "../Headers/Enums.mqh"
#include "../Headers/Structures.mqh"

#include "../Utils/Logger.mqh"
#include "../Core/DecisionEngine.mqh"
#include "../Execution/PositionManager.mqh"
#include "../Core/PackageManager.mqh"

// ==================== DEBUG SETTINGS ====================
bool DEBUG_DASHBOARD_ENABLED = false;

void DebugLogDashboard(string context, string message, bool logToFile = true, bool logToConsole = false)
{
    if (DEBUG_DASHBOARD_ENABLED)
        Logger::Log("DASHBOARD-" + context, message, logToFile, logToConsole);
}

// ==================== DISPLAY CONFIGURATION ====================
input color HeaderColor = clrDodgerBlue;
input color SectionColor = clrGold;
input color TextColor = clrWhite;
input color AlertColor = clrRed;
input color PositiveColor = clrLime;
input color NegativeColor = clrOrangeRed;

// ==================== DASHBOARD MANAGER CLASS ====================
class EnhancedDashboard
{
private:
    string m_symbol;
    int m_magicNumber;
    PackageManager *m_packageManager;
    DecisionEngine *m_decisionEngine;

    // Display buffer
    string m_lastDisplay;
    datetime m_lastUpdateTime;

public:
    // Constructor
    EnhancedDashboard() : m_symbol(""),
                          m_magicNumber(0),
                          m_packageManager(NULL),
                          m_decisionEngine(NULL),
                          m_lastDisplay(""),
                          m_lastUpdateTime(0)
    {
        DebugLogDashboard("CONSTRUCTOR", "EnhancedDashboard created");
    }

    // Initialize with required components
    bool Initialize(string symbol, int magicNumber,
                    PackageManager *pkgManager,
                    DecisionEngine *decisionEng)
    {
        DebugLogDashboard("INIT", StringFormat("Initializing dashboard for %s, magic: %d", symbol, magicNumber));
        
        if (symbol == "" || pkgManager == NULL || decisionEng == NULL)
        {
            DebugLogDashboard("ERROR", "Invalid initialization parameters");
            return false;
        }

        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_packageManager = pkgManager;
        m_decisionEngine = decisionEng;

        DebugLogDashboard("INIT", "EnhancedDashboard initialized successfully for " + symbol);
        return true;
    }

    // Cleanup
    void Deinitialize()
    {
        DebugLogDashboard("DEINIT", "Deinitializing dashboard");
        // Nothing to delete
        DebugLogDashboard("DEINIT", "Dashboard cleanup complete");
    }

    // Main update function
    void UpdateDisplay(bool forceUpdate = false)
    {
        // Update every 2 seconds
        if (!forceUpdate && (TimeCurrent() - m_lastUpdateTime) < 2)
        {
            DebugLogDashboard("UPDATE", "Skipping update (too soon)");
            return;
        }

        m_lastUpdateTime = TimeCurrent();

        string display = GenerateEnhancedDashboard();

        if (forceUpdate || display != m_lastDisplay)
        {
            Comment(display);
            m_lastDisplay = display;
            DebugLogDashboard("UPDATE", "Display updated successfully");
        }
        else
        {
            DebugLogDashboard("UPDATE", "Display unchanged, skipping update");
        }
    }

    // Generate enhanced dashboard
    string GenerateEnhancedDashboard()
    {
        DebugLogDashboard("GENERATE", "Generating dashboard display");
        
        string display = "";

        display += "\n\n";

        // ==================== HEADER ====================
        display += StringFormat("|%s|%s|\n",
                                PadCenter("mk$ EA v3.11 - GOLD SPECIALIST", 50),
                                PadRight(TimeToString(TimeCurrent(), TIME_SECONDS), 8));

        display += SeparatorLine();

        display += StringFormat("| %s|%s|%s|\n",
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

        // ==================== PACKAGE INFO ====================
        display += GeneratePackageInfoSection();

        // Add debug info if there's a mismatch
        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
            string actualProcessor = m_decisionEngine.GetLastProcessorUsed(m_symbol);

            // Check for mismatch between package type and processor
            bool isRangePackage = lastPackage.IsRangePackage();
            bool usingRangeProcessor = (actualProcessor == "RANGE");

            if (isRangePackage != usingRangeProcessor)
            {
                display += UnderLining();
                display += "| WARNING: Package/Processor Mismatch!\n";
                display += StringFormat("| Package says: %s | Processor says: %s\n",
                                        isRangePackage ? "RANGE" : "TREND",
                                        actualProcessor);
                display += UnderLining();
                
                DebugLogDashboard("WARNING", StringFormat("Package/Processor mismatch: Package=%s, Processor=%s",
                                                         isRangePackage ? "RANGE" : "TREND",
                                                         actualProcessor));
            }
        }

        display += SeparatorLine();

        // ==================== COMPONENT BREAKDOWN ====================
        display += GenerateComponentBreakdown();

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

        DebugLogDashboard("GENERATE", "Dashboard generation complete");
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

        string section = StringFormat("| Account      : $%.0f | Eq: $%.0f | ML: %.1f%% | %s\n",
                            balance, equity, marginLevel, GetTradingSessionShort());
        
        DebugLogDashboard("ACCOUNT_INFO", StringFormat("Balance: $%.0f, Equity: $%.0f, MarginLevel: %.1f%%", 
                                                       balance, equity, marginLevel));
        
        return section;
    }

    string GenerateSignalsSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
            
            if (lastPackage.IsValid())
            {
                // Use ONLY package information
                string regimeFromPackage = lastPackage.marketRegime;
                
                // Get package age for context
                int packageAge = (int)(TimeCurrent() - lastPackage.analysisTime);
                
                // Display package regime with timestamp context
                section += StringFormat("| Signal       : %s (from package, %d sec ago)\n",
                                        regimeFromPackage, packageAge);
                
                DebugLogDashboard("SIGNALS", StringFormat("Regime: %s, Age: %d sec", regimeFromPackage, packageAge));
            }
            else
            {
                section += "| Signal       : NO_PACKAGE | WAITING\n";
                DebugLogDashboard("SIGNALS", "No valid package available");
            }
        }
        else
        {
            section += "| Signal       : NO_DECISION_ENGINE\n";
            DebugLogDashboard("ERROR", "No decision engine available");
        }

        return section;
    }

    string GeneratePackageInfoSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);

            // Get ACTUAL processor used (not just guessing from package type)
            string actualProcessor = m_decisionEngine.GetLastProcessorUsed(m_symbol);

            if (lastPackage.IsValid())
            {
                // FIX 1: Use the ACTUAL package type from the processor used
                string packageType = (actualProcessor == "RANGE") ? "Range Package" : (actualProcessor == "TREND") ? "Trend Package"
                                                                                                                   : "Unknown Package";

                // FIX 2: Get direction and confidence from the actual package
                string direction = ConvertDirection(lastPackage.dominantDirection);
                string action = GetCompactAction(lastPackage.recommendedAction, lastPackage.dominantDirection);

                // FIX 3: Add processor info to the display
                section += StringFormat("| Package      : %s | %s | Act:%s | Conf: %.0f%%\n",
                                        packageType, direction, action,
                                        lastPackage.overallConfidence);

                // Show trap info if available
                if (lastPackage.trapProbability > 0)
                {
                    section += SeparatorLine();
                    section += StringFormat("| Trap         : %.0f%% | Trap Zone: %s\n",
                                            lastPackage.trapProbability,
                                            lastPackage.isTrapZone ? "YES" : "NO");
                }
                
                DebugLogDashboard("PACKAGE_INFO", 
                                 StringFormat("Type: %s, Direction: %s, Action: %s, Confidence: %.0f%%, Processor: %s",
                                             packageType, direction, action, lastPackage.overallConfidence, actualProcessor));
            }
            else
            {
                section += "| Package      : NO_VALID_PACKAGE | Proc: NONE | Conf: 0%\n";
                DebugLogDashboard("PACKAGE_INFO", "No valid package available");
            }
        }
        else
        {
            section += "| Package      : NO_DECISION_ENGINE\n";
            DebugLogDashboard("ERROR", "No decision engine available");
        }

        return section;
    }

    // Update GenerateComponentBreakdown to match actual processor
    string GenerateComponentBreakdown()
    {
        string section = "";

        if (m_decisionEngine == NULL)
        {
            section = "| Components    : NO DATA\n";
            DebugLogDashboard("COMPONENTS", "No decision engine available");
            return section;
        }

        DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
        string actualProcessor = m_decisionEngine.GetLastProcessorUsed(m_symbol);

        if (!lastPackage.IsValid())
        {
            section = "| Components    : NO VALID PACKAGE\n";
            DebugLogDashboard("COMPONENTS", "No valid package available");
            return section;
        }

        section += "| Components    : ";

        // Use the ACTUAL processor, not guessing from package type
        if (actualProcessor == "RANGE")
        {
            section += GetDetailedRangeComponents(lastPackage);
            DebugLogDashboard("COMPONENTS", "Using RANGE processor components");
        }
        else if (actualProcessor == "TREND")
        {
            section += GetDetailedTrendComponents(lastPackage);
            DebugLogDashboard("COMPONENTS", "Using TREND processor components");
        }
        else
        {
            // If we don't know the processor, check the package type
            if (lastPackage.IsRangePackage())
            {
                section += GetDetailedRangeComponents(lastPackage);
                DebugLogDashboard("COMPONENTS", "Falling back to RANGE components (by package type)");
            }
            else
            {
                section += GetDetailedTrendComponents(lastPackage);
                DebugLogDashboard("COMPONENTS", "Falling back to TREND components (by package type)");
            }
        }

        section += "\n";
        return section;
    }

    string GetDetailedTrendComponents(const DecisionEngineInterface &package)
    {
        string components = "";

        // Check if we have access to PackageManager for detailed components
        if (m_packageManager != NULL)
        {
            TrendPackage trendPackage = m_packageManager.GetTrendPackage(false);

            if (trendPackage.isValid)
            {
                // ==================== OVERALL DIRECTION & SCORE ====================
                string overallDir = GetShortDirection(trendPackage.directionAnalysis.dominantDirection);
                double overallScore = trendPackage.weightedScore;
                
                components += StringFormat("%s/%.1f ", overallDir, overallScore);
                components += UnderLining();
                
                // ==================== COMPONENT BREAKDOWN ====================
                // MTF Component
                if (trendPackage.scores.mtfScore > 0)
                {
                    string mtfDir = trendPackage.GetMTFDirection();
                    components += StringFormat("                    MTF/%s/%.0f%%",
                                               GetShortDirection(mtfDir),
                                               trendPackage.scores.mtfScore);
                }

                // POI Component
                if (trendPackage.scores.poiScore > 0)
                {
                    components += StringFormat(" | POI/%s/%.0f%%",
                                               GetShortDirection(trendPackage.poiSignal.overallBias),
                                               trendPackage.scores.poiScore);
                }

                // Volume Component
                if (trendPackage.scores.volumeScore > 0)
                {
                    components += StringFormat(" | VOL/%s/%.0f%%",
                                               GetShortDirection(trendPackage.volumeData.bias),
                                               trendPackage.scores.volumeScore);
                }

                // RSI Component
                if (trendPackage.scores.rsiScore > 0)
                {
                    components += StringFormat(" | RSI/%s/%.0f%%",
                                               GetShortDirection(trendPackage.rsiData.biasText),
                                               trendPackage.scores.rsiScore);
                }

                // MACD Component
                if (trendPackage.scores.macdScore > 0)
                {
                    components += StringFormat(" | MACD/%s/%.0f%%",
                                               GetShortDirection(trendPackage.macdData.bias),
                                               trendPackage.scores.macdScore);
                }

                // Pattern Component
                if (trendPackage.scores.patternScore > 0)
                {
                    components += StringFormat(" | PAT/%s/%.0f%%",
                                               GetShortDirection(trendPackage.patternData.direction),
                                               trendPackage.scores.patternScore);
                }

                components += "\n";
                components += UnderLining();

                // Add alignment info
                components += StringFormat("B:%d/S:%d",
                                           trendPackage.mtfData.bullishCount,
                                           trendPackage.mtfData.bearishCount);
                                           
                // Add overall confidence
                components += StringFormat(" | Overall: %.0f%%", trendPackage.overallConfidence);
                
                DebugLogDashboard("TREND_COMPONENTS", 
                                 StringFormat("Direction: %s, Score: %.1f, Confidence: %.0f%%, Bulls: %d, Bears: %d",
                                             overallDir, overallScore, trendPackage.overallConfidence,
                                             trendPackage.mtfData.bullishCount, trendPackage.mtfData.bearishCount));
            }
            else
            {
                components = "NO_TREND_DATA";
                DebugLogDashboard("TREND_COMPONENTS", "No trend data available");
            }
        }
        else
        {
            // Fallback to basic package info
            string dirSymbol = GetDirectionSymbol(package.dominantDirection);
            components = StringFormat("%s/%.1f ", dirSymbol, package.weightedScore);
            components += UnderLining();
            components += StringFormat("TREND/%s/%d%%", dirSymbol, (int)package.overallConfidence);
            
            DebugLogDashboard("TREND_COMPONENTS", 
                             StringFormat("Fallback: Direction: %s, Score: %.1f, Confidence: %.0f%%",
                                         dirSymbol, package.weightedScore, package.overallConfidence));
        }

        return components;
    }

    string GetDetailedRangeComponents(const DecisionEngineInterface &package)
    {
        string components = "";

        // Show overall direction from package
        string overallDir = GetShortDirection(package.dominantDirection);
        
        components += StringFormat("%s/%.1f ", overallDir, package.weightedScore);
        components += UnderLining();
        
        // Simple range display using package info
        components += StringFormat("                    RANGE/%s/%d%%", 
                                  overallDir,
                                  (int)package.overallConfidence);

        if (package.trapProbability > 0)
        {
            components += StringFormat(" | TRAP:%.0f%%", package.trapProbability);
        }

        if (package.rangeAction != "" && package.rangeAction != "NONE")
        {
            components += StringFormat(" | ACT:%s", package.rangeAction);
        }
        
        DebugLogDashboard("RANGE_COMPONENTS", 
                         StringFormat("Direction: %s, Score: %.1f, Confidence: %.0f%%, Trap: %.0f%%, Action: %s",
                                     overallDir, package.weightedScore, package.overallConfidence,
                                     package.trapProbability, package.rangeAction));

        return components;
    }

    string GenerateSetupSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
            
            if (lastPackage.IsValid())
            {
                // Use setup information FROM THE PACKAGE
                double stopLoss = lastPackage.stopLoss;
                double takeProfit = lastPackage.takeProfit1;
                
                // Calculate risk-reward ratio if both are valid
                double riskReward = 0.0;
                if (stopLoss > 0 && takeProfit > 0)
                {
                    riskReward = takeProfit / stopLoss;
                }
                
                // Get position size from package
                string posSize = "MED"; // Default
                if (lastPackage.positionSize > 0)
                {
                    if (lastPackage.positionSize <= 0.01) posSize = "VSML";
                    else if (lastPackage.positionSize <= 0.08) posSize = "SML";
                    else if (lastPackage.positionSize <= 2.05) posSize = "MED";
                    else if (lastPackage.positionSize <= 5.1) posSize = "LRG";
                }
                
                section += StringFormat("| Setup        : %s | SL: %.1f | TP: %.1f | RR: %.1f\n",
                                        posSize, stopLoss, takeProfit, riskReward);
                
                DebugLogDashboard("SETUP", 
                                 StringFormat("Size: %s, SL: %.1f, TP: %.1f, RR: %.1f",
                                             posSize, stopLoss, takeProfit, riskReward));
            }
            else
            {
                section += "| Setup        : NO_PACKAGE | SL: 0.0 | TP: 0.0 | RR: 0.0\n";
                DebugLogDashboard("SETUP", "No package available for setup");
            }
        }
        else
        {
            section += "| Setup        : NO_DECISION_ENGINE\n";
            DebugLogDashboard("ERROR", "No decision engine available for setup");
        }

        return section;
    }

    string GenerateActionSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
            
            if (lastPackage.IsValid())
            {
                // Use action information FROM THE PACKAGE
                string action = lastPackage.recommendedAction;
                string warning = "";
                
                // Add warnings based on package trap info
                if (lastPackage.isTrapZone)
                    warning = "TRAP ZONE ";
                else if (lastPackage.trapProbability > 70)
                    warning = "HIGH TRAP ";
                else if (lastPackage.isAvoidSignal)
                    warning = "AVOID ";
                    
                section += StringFormat("| Action       : %s%s\n", warning, action);
                
                DebugLogDashboard("ACTION", 
                                 StringFormat("Action: %s%s, TrapZone: %s, TrapProb: %.0f%%, Avoid: %s",
                                             warning, action,
                                             lastPackage.isTrapZone ? "YES" : "NO",
                                             lastPackage.trapProbability,
                                             lastPackage.isAvoidSignal ? "YES" : "NO"));
            }
            else
            {
                section += "| Action       : NO_PACKAGE\n";
                DebugLogDashboard("ACTION", "No package available for action");
            }
        }

        return section;
    }

    string GenerateDescriptionSection()
    {
        string section = "";

        if (m_decisionEngine != NULL)
        {
            DecisionEngineInterface lastPackage = m_decisionEngine.GetLastPackage(m_symbol);
            
            if (lastPackage.IsValid())
            {
                // Use description FROM THE PACKAGE
                string description = lastPackage.signalReason;
                
                // If signalReason is empty, use recommendedAction
                if (description == "" || description == "NONE")
                    description = lastPackage.recommendedAction;
                    
                section += StringFormat("| Description  : %s\n", TruncateString(description, 60));
                
                DebugLogDashboard("DESCRIPTION", 
                                 StringFormat("Description: %s", TruncateString(description, 60)));
            }
            else
            {
                section += "| Description  : NO_PACKAGE\n";
                DebugLogDashboard("DESCRIPTION", "No package available for description");
            }
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
            string positionStr = positionCount > 0 ? StringFormat("%d Pos", positionCount) : "NO_POS";

            // Get position direction
            string positionDir = positionCount > 0 ? GetCurrentPositionDirection() : "NO_DIR";

            section += StringFormat("| Decision     : %s | %s | %s",
                                    decisionStr, positionStr, positionDir);
                                    
            DebugLogDashboard("DECISION", 
                             StringFormat("Decision: %s, Positions: %d, Direction: %s",
                                         decisionStr, positionCount, positionDir));
        }
        else
        {
            section += "| Decision      : NONE | NO_POS | NO_DIR";
            DebugLogDashboard("DECISION", "No decision engine available");
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

            section += StringFormat(" | Trades: %d | W:%d L:%d | Win: %s\n",
                                    metrics.totalDecisions,
                                    metrics.profitableDecisions,
                                    losingTrades,
                                    accuracyStr);
                                    
            DebugLogDashboard("STATS", 
                             StringFormat("Trades: %d, Wins: %d, Losses: %d, Accuracy: %s",
                                         metrics.totalDecisions, metrics.profitableDecisions,
                                         losingTrades, accuracyStr));
        }
        else
        {
            section += " | Trades: 0 | W:0 L:0 | Win: 0.0%\n";
            DebugLogDashboard("STATS", "No statistics available");
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

    string GetShortDirection(string direction)
    {
        if (direction == "BULLISH" || direction == "Bullish")
            return "BUY";
        if (direction == "BEARISH" || direction == "Bearish")
            return "SELL";
        if (direction == "NEUTRAL" || direction == "Neutral")
            return "NON";
        if (direction == "CONFLICTED")
            return "CONFLICT";
        return "?";
    }

    string GetDirectionSymbol(string direction)
    {
        if (direction == "BULLISH")
            return "B";
        if (direction == "BEARISH")
            return "S";
        if (direction == "NEUTRAL")
            return "N";
        return "?";
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
        if (StringFind(action, "Avoid") >= 0)
            return "AVOID";

        return action + dirShort;
    }

    string GetCurrentPositionDirection()
    {
        if (GetPositionCount() == 0)
        {
            DebugLogDashboard("POSITIONS", "No positions found");
            return "NO_DIR";
        }

        // Get the first position's direction
        for (int i = 0; i < PositionsTotal(); i++)
        {
            if (PositionGetTicket(i))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);
                long posType = PositionGetInteger(POSITION_TYPE);

                if (posSymbol == m_symbol && posMagic == m_magicNumber)
                {
                    string direction = (posType == POSITION_TYPE_BUY) ? "B" : "S";
                    DebugLogDashboard("POSITIONS", StringFormat("Found position: %s", direction));
                    return direction;
                }
            }
        }
        
        DebugLogDashboard("POSITIONS", "No matching positions found");
        return "NO_DIR";
    }

    string GetTradingSessionShort()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);

        string session;
        if (dt.hour >= 0 && dt.hour < 5)
            session = "ASIA";
        else if (dt.hour >= 5 && dt.hour < 14)
            session = "LONDON";
        else if (dt.hour >= 14 && dt.hour < 21)
            session = "US";
        else
            session = "NIGHT";
            
        DebugLogDashboard("SESSION", StringFormat("Current session: %s (Hour: %d)", session, dt.hour));
        return session;
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
        
        DebugLogDashboard("POSITION_COUNT", StringFormat("Found %d positions", count));
        return count;
    }

    string TimeframeToString(ENUM_TIMEFRAMES tf)
    {
        string tfStr;
        switch (tf)
        {
        case PERIOD_M1:
            tfStr = "M1";
            break;
        case PERIOD_M5:
            tfStr = "M5";
            break;
        case PERIOD_M15:
            tfStr = "M15";
            break;
        case PERIOD_M30:
            tfStr = "M30";
            break;
        case PERIOD_H1:
            tfStr = "H1";
            break;
        case PERIOD_H4:
            tfStr = "H4";
            break;
        case PERIOD_D1:
            tfStr = "D1";
            break;
        default:
            tfStr = IntegerToString(tf);
            break;
        }
        
        DebugLogDashboard("TIMEFRAME", StringFormat("Timeframe: %s", tfStr));
        return tfStr;
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
        return "-----------------------------------------------------------------------------------------------------------------\n";
    }

    string UnderLining()
    {
        return "--------------------------------------------------------------------------\n";
    }

    string TruncateString(string text, int maxLength)
    {
        if (StringLen(text) <= maxLength)
            return text;
        string truncated = StringSubstr(text, 0, maxLength - 3) + "...";
        DebugLogDashboard("TRUNCATE", StringFormat("Truncated '%s' to '%s'", text, truncated));
        return truncated;
    }
};

// ==================== GLOBAL FUNCTION ====================

void ShowEnhancedDashboard(string symbol,
                           int magicNumber,
                           PackageManager &pkgManager,
                           DecisionEngine &decisionEngineObj)
{
    static EnhancedDashboard dashboard;
    static bool initialized = false;

    if (!initialized)
    {
        if (dashboard.Initialize(symbol, magicNumber, GetPointer(pkgManager),
                                 GetPointer(decisionEngineObj)))
        {
            initialized = true;
            DebugLogDashboard("GLOBAL", "EnhancedDashboard initialized successfully");
        }
        else
        {
            DebugLogDashboard("ERROR", "Failed to initialize EnhancedDashboard");
        }
    }

    if (initialized)
    {
        dashboard.UpdateDisplay();
    }
}

#endif // DASHBOARD_MQH_V3