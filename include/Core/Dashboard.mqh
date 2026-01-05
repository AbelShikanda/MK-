//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                        Copyright 2023, Your Company Name Here    |
//|                                       https://www.yourwebsite.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      "https://www.yourwebsite.com"
#property strict

#include <LoggerUtils.mqh>
#include <MathUtils.mqh>

//+------------------------------------------------------------------+
//| Dashboard Class                                                  |
//+------------------------------------------------------------------+
class Dashboard
{
private:
    struct DecisionRecord
    {
        string decision;
        datetime timestamp;
        double confidence;
        string symbol;
        string reason;
    };
    
    struct PerformanceMetrics
    {
        int totalTrades;
        int winningTrades;
        int losingTrades;
        double totalProfit;
        double totalLoss;
        double winRate;
        double profitFactor;
        double averageWin;
        double averageLoss;
        double largestWin;
        double largestLoss;
        double currentDrawdown;
        double maxDrawdown;
        double sharpeRatio;
        double expectancy;
    };
    
    DecisionRecord decisionsHistory[];
    double confidenceScores[];
    PerformanceMetrics metrics;
    Logger logger;
    
    // Chart objects
    string chartPrefix;
    bool chartObjectsCreated;
    
public:
    Dashboard()
    {
        ArrayResize(decisionsHistory, 0);
        ArrayResize(confidenceScores, 0);
        chartPrefix = "DB_";
        chartObjectsCreated = false;
        
        // Initialize metrics
        ResetMetrics();
        
        // Initialize logger
        logger.Initialize("Dashboard.log", true, true);
    }
    
    ~Dashboard()
    {
        CleanupChartObjects();
    }
    
    // Log decision to dashboard
    void LogDecision(string decision, double confidence = 0.0, string symbol = "", string reason = "")
    {
        int size = ArraySize(decisionsHistory);
        ArrayResize(decisionsHistory, size + 1);
        
        decisionsHistory[size].decision = decision;
        decisionsHistory[size].timestamp = TimeCurrent();
        decisionsHistory[size].confidence = confidence;
        decisionsHistory[size].symbol = symbol;
        decisionsHistory[size].reason = reason;
        
        // Keep only last 1000 decisions
        if(size > 1000)
        {
            for(int i = 0; i < size - 1000; i++)
                decisionsHistory[i] = decisionsHistory[i + (size - 1000)];
            ArrayResize(decisionsHistory, 1000);
        }
        
        // Also update confidence scores
        UpdateConfidence(confidence);
        
        // Log to file
        logger.Log("Dashboard", 
            StringFormat("Decision: %s | Confidence: %.2f | Symbol: %s | Reason: %s", 
                decision, confidence, symbol, reason));
    }
    
    // Update confidence score
    void UpdateConfidence(double score)
    {
        int size = ArraySize(confidenceScores);
        ArrayResize(confidenceScores, size + 1);
        confidenceScores[size] = MathMin(MathMax(score, 0.0), 1.0);
        
        // Keep only last 500 scores
        if(size > 500)
        {
            for(int i = 0; i < size - 500; i++)
                confidenceScores[i] = confidenceScores[i + (size - 500)];
            ArrayResize(confidenceScores, 500);
        }
    }
    
    // Display metrics on chart
    void DisplayMetrics()
    {
        CalculateMetrics();
        CreateChartObjects();
        UpdateChartObjects();
        
        // Also print to log
        PrintDashboard();
    }
    
    // Alert user
    void AlertUser(string message, int alertType = 0) // 0=info, 1=warning, 2=error
    {
        string alertPrefix;
        color alertColor;
        
        switch(alertType)
        {
            case 1:
                alertPrefix = "WARNING: ";
                alertColor = clrOrange;
                break;
            case 2:
                alertPrefix = "ERROR: ";
                alertColor = clrRed;
                break;
            default:
                alertPrefix = "INFO: ";
                alertColor = clrDodgerBlue;
                break;
        }
        
        string fullMessage = alertPrefix + message;
        
        // Send alert
        Alert("DecisionBot: ", fullMessage);
        
        // Print to experts log
        Print(fullMessage);
        
        // Log to file
        logger.Log("Dashboard", "Alert: " + message);
        
        // Display on chart if enabled
        if(chartObjectsCreated)
        {
            ObjectCreate(0, chartPrefix + "Alert", OBJ_LABEL, 0, 0, 0);
            ObjectSetString(0, chartPrefix + "Alert", OBJPROP_TEXT, fullMessage);
            ObjectSetInteger(0, chartPrefix + "Alert", OBJPROP_COLOR, alertColor);
            ObjectSetInteger(0, chartPrefix + "Alert", OBJPROP_FONTSIZE, 10);
            ObjectSetInteger(0, chartPrefix + "Alert", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, chartPrefix + "Alert", OBJPROP_XDISTANCE, 10);
            ObjectSetInteger(0, chartPrefix + "Alert", OBJPROP_YDISTANCE, 30);
            
            // Auto-remove after 10 seconds
            EventSetTimer(10);
        }
    }
    
    // Update trade performance
    void UpdateTradePerformance(bool isWin, double profit, double confidence)
    {
        metrics.totalTrades++;
        
        if(isWin)
        {
            metrics.winningTrades++;
            metrics.totalProfit += profit;
            metrics.averageWin = (metrics.averageWin * (metrics.winningTrades - 1) + profit) / metrics.winningTrades;
            
            if(profit > metrics.largestWin)
                metrics.largestWin = profit;
        }
        else
        {
            metrics.losingTrades++;
            metrics.totalLoss += MathAbs(profit);
            metrics.averageLoss = (metrics.averageLoss * (metrics.losingTrades - 1) + MathAbs(profit)) / metrics.losingTrades;
            
            if(MathAbs(profit) > metrics.largestLoss)
                metrics.largestLoss = MathAbs(profit);
        }
        
        // Update current drawdown
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        metrics.currentDrawdown = (currentBalance - equity) / currentBalance * 100;
        
        if(metrics.currentDrawdown > metrics.maxDrawdown)
            metrics.maxDrawdown = metrics.currentDrawdown;
        
        // Recalculate metrics
        CalculateMetrics();
    }
    
    // Get recent decisions
    string GetRecentDecisions(int count = 10)
    {
        string result = "Recent Decisions:\n";
        int start = MathMax(0, ArraySize(decisionsHistory) - count);
        
        for(int i = start; i < ArraySize(decisionsHistory); i++)
        {
            result += StringFormat("%s - %s (%.2f) - %s\n",
                TimeToString(decisionsHistory[i].timestamp, TIME_DATE|TIME_MINUTES),
                decisionsHistory[i].decision,
                decisionsHistory[i].confidence,
                decisionsHistory[i].reason);
        }
        
        return result;
    }
    
    // Get confidence statistics
    string GetConfidenceStats()
    {
        if(ArraySize(confidenceScores) == 0)
            return "No confidence data available";
        
        double sum = 0;
        double minVal = 1.0;
        double maxVal = 0.0;
        
        for(int i = 0; i < ArraySize(confidenceScores); i++)
        {
            sum += confidenceScores[i];
            if(confidenceScores[i] < minVal) minVal = confidenceScores[i];
            if(confidenceScores[i] > maxVal) maxVal = confidenceScores[i];
        }
        
        double avg = sum / ArraySize(confidenceScores);
        
        // Calculate standard deviation
        double variance = 0;
        for(int i = 0; i < ArraySize(confidenceScores); i++)
            variance += MathPow(confidenceScores[i] - avg, 2);
        variance /= ArraySize(confidenceScores);
        double stdDev = MathSqrt(variance);
        
        return StringFormat("Confidence Stats:\n" +
                           "  Average: %.2f\n" +
                           "  Min: %.2f\n" +
                           "  Max: %.2f\n" +
                           "  Std Dev: %.2f\n" +
                           "  Samples: %d",
                           avg, minVal, maxVal, stdDev, ArraySize(confidenceScores));
    }
    
private:
    // Reset metrics
    void ResetMetrics()
    {
        metrics.totalTrades = 0;
        metrics.winningTrades = 0;
        metrics.losingTrades = 0;
        metrics.totalProfit = 0;
        metrics.totalLoss = 0;
        metrics.winRate = 0;
        metrics.profitFactor = 0;
        metrics.averageWin = 0;
        metrics.averageLoss = 0;
        metrics.largestWin = 0;
        metrics.largestLoss = 0;
        metrics.currentDrawdown = 0;
        metrics.maxDrawdown = 0;
        metrics.sharpeRatio = 0;
        metrics.expectancy = 0;
    }
    
    // Calculate all metrics
    void CalculateMetrics()
    {
        if(metrics.totalTrades > 0)
        {
            metrics.winRate = (double)metrics.winningTrades / metrics.totalTrades * 100;
            
            if(metrics.totalLoss > 0)
                metrics.profitFactor = metrics.totalProfit / metrics.totalLoss;
            else
                metrics.profitFactor = metrics.totalProfit > 0 ? 999.99 : 0;
            
            metrics.expectancy = (metrics.winRate / 100 * metrics.averageWin) - 
                                 ((100 - metrics.winRate) / 100 * metrics.averageLoss);
            
            // Simple Sharpe ratio approximation
            if(metrics.averageLoss > 0)
                metrics.sharpeRatio = (metrics.averageWin - metrics.averageLoss) / 
                                      MathSqrt(metrics.averageLoss);
            else
                metrics.sharpeRatio = metrics.averageWin > 0 ? 3.0 : 0;
        }
    }
    
    // Create chart objects
    void CreateChartObjects()
    {
        if(chartObjectsCreated) return;
        
        // Create background
        ObjectCreate(0, chartPrefix + "Background", OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_COLOR, clrDarkSlateGray);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_BGCOLOR, clrDarkSlateGray);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_WIDTH, 300);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, chartPrefix + "Background", OBJPROP_YDISTANCE, 20);
        
        // Create metric labels
        string labels[] = {"TotalTrades", "WinRate", "ProfitFactor", "Expectancy", 
                          "AvgWin", "AvgLoss", "Drawdown", "Confidence"};
        
        for(int i = 0; i < ArraySize(labels); i++)
        {
            // Label
            ObjectCreate(0, chartPrefix + "Label_" + labels[i], OBJ_LABEL, 0, 0, 0);
            ObjectSetString(0, chartPrefix + "Label_" + labels[i], OBJPROP_TEXT, labels[i] + ":");
            ObjectSetInteger(0, chartPrefix + "Label_" + labels[i], OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(0, chartPrefix + "Label_" + labels[i], OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, chartPrefix + "Label_" + labels[i], OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, chartPrefix + "Label_" + labels[i], OBJPROP_XDISTANCE, 15);
            ObjectSetInteger(0, chartPrefix + "Label_" + labels[i], OBJPROP_YDISTANCE, 45 + i * 20);
            
            // Value
            ObjectCreate(0, chartPrefix + "Value_" + labels[i], OBJ_LABEL, 0, 0, 0);
            ObjectSetString(0, chartPrefix + "Value_" + labels[i], OBJPROP_TEXT, "0.00");
            ObjectSetInteger(0, chartPrefix + "Value_" + labels[i], OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, chartPrefix + "Value_" + labels[i], OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, chartPrefix + "Value_" + labels[i], OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, chartPrefix + "Value_" + labels[i], OBJPROP_XDISTANCE, 120);
            ObjectSetInteger(0, chartPrefix + "Value_" + labels[i], OBJPROP_YDISTANCE, 45 + i * 20);
        }
        
        chartObjectsCreated = true;
    }
    
    // Update chart objects
    void UpdateChartObjects()
    {
        if(!chartObjectsCreated) return;
        
        // Confidence indicator (visual bar)
        double avgConfidence = 0;
        if(ArraySize(confidenceScores) > 0)
        {
            for(int i = 0; i < MathMin(20, ArraySize(confidenceScores)); i++)
                avgConfidence += confidenceScores[i];
            avgConfidence /= MathMin(20, ArraySize(confidenceScores));
        }
        
        // Update values
        ObjectSetString(0, chartPrefix + "Value_TotalTrades", OBJPROP_TEXT, (string)metrics.totalTrades);
        ObjectSetString(0, chartPrefix + "Value_WinRate", OBJPROP_TEXT, StringFormat("%.1f%%", metrics.winRate));
        ObjectSetString(0, chartPrefix + "Value_ProfitFactor", OBJPROP_TEXT, StringFormat("%.2f", metrics.profitFactor));
        ObjectSetString(0, chartPrefix + "Value_Expectancy", OBJPROP_TEXT, StringFormat("%.2f", metrics.expectancy));
        ObjectSetString(0, chartPrefix + "Value_AvgWin", OBJPROP_TEXT, StringFormat("%.2f", metrics.averageWin));
        ObjectSetString(0, chartPrefix + "Value_AvgLoss", OBJPROP_TEXT, StringFormat("%.2f", metrics.averageLoss));
        ObjectSetString(0, chartPrefix + "Value_Drawdown", OBJPROP_TEXT, StringFormat("%.1f%%", metrics.currentDrawdown));
        ObjectSetString(0, chartPrefix + "Value_Confidence", OBJPROP_TEXT, StringFormat("%.2f", avgConfidence));
        
        // Color coding based on values
        ObjectSetInteger(0, chartPrefix + "Value_WinRate", OBJPROP_COLOR, 
            metrics.winRate > 50 ? clrLime : clrRed);
        ObjectSetInteger(0, chartPrefix + "Value_ProfitFactor", OBJPROP_COLOR, 
            metrics.profitFactor > 1.5 ? clrLime : (metrics.profitFactor > 1.0 ? clrYellow : clrRed));
        ObjectSetInteger(0, chartPrefix + "Value_Drawdown", OBJPROP_COLOR, 
            metrics.currentDrawdown > 20 ? clrRed : (metrics.currentDrawdown > 10 ? clrOrange : clrLime));
        ObjectSetInteger(0, chartPrefix + "Value_Confidence", OBJPROP_COLOR, 
            avgConfidence > 0.7 ? clrLime : (avgConfidence > 0.5 ? clrYellow : clrRed));
    }
    
    // Cleanup chart objects
    void CleanupChartObjects()
    {
        string names[];
        int total = ObjectsTotal(0);
        
        for(int i = 0; i < total; i++)
        {
            string name = ObjectName(0, i);
            if(StringFind(name, chartPrefix) == 0)
                ObjectDelete(0, name);
        }
        
        chartObjectsCreated = false;
    }
    
    // Print dashboard to log
    void PrintDashboard()
    {
        string output = "\n" +
            "╔══════════════════════════════════════╗\n" +
            "║          DECISION BOT DASHBOARD      ║\n" +
            "╠══════════════════════════════════════╣\n" +
            "║ Performance Metrics:                 ║\n" +
            "║   Total Trades: " + StringFormat("%-17d", metrics.totalTrades) + "║\n" +
            "║   Win Rate: " + StringFormat("%-21.1f%%", metrics.winRate) + "║\n" +
            "║   Profit Factor: " + StringFormat("%-16.2f", metrics.profitFactor) + "║\n" +
            "║   Expectancy: " + StringFormat("%-19.2f", metrics.expectancy) + "║\n" +
            "║   Avg Win/Loss: " + StringFormat("%-16.2f/%.2f", metrics.averageWin, metrics.averageLoss) + "║\n" +
            "║   Current Drawdown: " + StringFormat("%-12.1f%%", metrics.currentDrawdown) + "║\n" +
            "║   Max Drawdown: " + StringFormat("%-16.1f%%", metrics.maxDrawdown) + "║\n" +
            "║   Sharpe Ratio: " + StringFormat("%-17.2f", metrics.sharpeRatio) + "║\n" +
            "╠══════════════════════════════════════╣\n" +
            "║ Confidence Stats:                    ║\n";
        
        if(ArraySize(confidenceScores) > 0)
        {
            double avgConfidence = 0;
            for(int i = 0; i < ArraySize(confidenceScores); i++)
                avgConfidence += confidenceScores[i];
            avgConfidence /= ArraySize(confidenceScores);
            
            output += "║   Average: " + StringFormat("%-22.2f", avgConfidence) + "║\n" +
                     "║   Samples: " + StringFormat("%-22d", ArraySize(confidenceScores)) + "║\n";
        }
        
        output += "║ Recent Decisions: " + StringFormat("%-15d", ArraySize(decisionsHistory)) + "║\n" +
                 "╚══════════════════════════════════════╝\n";
        
        Print(output);
    }
};