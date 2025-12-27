// //+------------------------------------------------------------------+
// //|                         RiskData.mqh                             |
// //|                   Risk metrics & management data                 |
// //+------------------------------------------------------------------+
// #ifndef RISK_DATA_MQH
// #define RISK_DATA_MQH

// #include "../MasterConfig/enums.mqh"

// // ============ RISK ENUMS ============
// enum ENUM_RISK_LEVEL
// {
//     RISK_CRITICAL = 0,    // Stop trading
//     RISK_HIGH = 1,        // Reduce position sizes
//     RISK_MODERATE = 2,    // Normal trading
//     RISK_LOW = 3,         // Can increase sizes
//     RISK_OPTIMAL = 4      // Aggressive trading
// };

// // ============ RISK METRICS STRUCTURE ============
// struct RiskMetrics
// {
//     // Daily Performance
//     double dailyPnL;
//     double dailyMaxLoss;
//     int tradesToday;
//     int winsToday;
//     int lossesToday;
    
//     // Period Performance
//     double weeklyPnL;
//     double monthlyPnL;
//     double quarterlyPnL;
//     double yearlyPnL;
    
//     // Core Metrics
//     double winRate;
//     double expectancy;
//     double avgRiskReward;
//     double profitFactor;
    
//     // Drawdown
//     double maxDrawdown;
//     double currentDrawdown;
//     double recoveryFactor;
    
//     // Totals
//     int totalTrades;
//     int totalWins;
//     int totalLosses;
//     double totalProfit;
//     double totalLoss;
    
//     // Portfolio Metrics
//     double totalCapital;
//     double allocatedCapital;
//     double availableCapital;
//     double portfolioReturn;
//     double portfolioVolatility;
//     double sharpeRatio;
//     double sortinoRatio;
    
//     // Account Health
//     double accountEquity;
//     double accountBalance;
//     double accountMargin;
//     double freeMarginPercent;
//     string accountStatus;
    
//     // System Metrics
//     int totalAdjustments;
//     int divergenceSignals;
//     double avgDivergenceImpact;
//     datetime lastCalculation;
    
//     // Timestamps
//     datetime sessionStart;
//     datetime lastTradeTime;
//     datetime metricsTime;
    
//     // Constructor
//     RiskMetrics() : dailyPnL(0.0), dailyMaxLoss(0.0), tradesToday(0),
//                    winsToday(0), lossesToday(0), weeklyPnL(0.0),
//                    monthlyPnL(0.0), quarterlyPnL(0.0), yearlyPnL(0.0),
//                    winRate(0.0), expectancy(0.0), avgRiskReward(0.0),
//                    profitFactor(0.0), maxDrawdown(0.0), currentDrawdown(0.0),
//                    recoveryFactor(0.0), totalTrades(0), totalWins(0),
//                    totalLosses(0), totalProfit(0.0), totalLoss(0.0),
//                    totalCapital(0.0), allocatedCapital(0.0),
//                    availableCapital(0.0), portfolioReturn(0.0),
//                    portfolioVolatility(0.0), sharpeRatio(0.0),
//                    sortinoRatio(0.0), accountEquity(0.0),
//                    accountBalance(0.0), accountMargin(0.0),
//                    freeMarginPercent(0.0), accountStatus(""),
//                    totalAdjustments(0), divergenceSignals(0),
//                    avgDivergenceImpact(0.0), lastCalculation(0),
//                    sessionStart(0), lastTradeTime(0), metricsTime(0) {}
    
//     // Initialize with starting balance
//     void Initialize(double startingBalance = 0.0)
//     {
//         if(startingBalance == 0.0)
//             startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            
//         totalCapital = startingBalance;
//         accountBalance = startingBalance;
//         accountEquity = startingBalance;
//         sessionStart = TimeCurrent();
//         metricsTime = TimeCurrent();
        
//         ResetDaily();
//         ResetPeriodic();
//     }
    
//     // Reset daily metrics
//     void ResetDaily()
//     {
//         dailyPnL = 0.0;
//         dailyMaxLoss = 0.0;
//         tradesToday = 0;
//         winsToday = 0;
//         lossesToday = 0;
//         currentDrawdown = 0.0;
//     }
    
//     // Reset weekly/monthly metrics
//     void ResetPeriodic()
//     {
//         weeklyPnL = 0.0;
//         monthlyPnL = 0.0;
//     }
    
//     // Update after trade
//     void UpdateAfterTrade(bool win, double profit, double riskAmount, double equity)
//     {
//         totalTrades++;
//         tradesToday++;
        
//         if(win)
//         {
//             totalWins++;
//             winsToday++;
//             totalProfit += profit;
//             dailyPnL += profit;
//         }
//         else
//         {
//             totalLosses++;
//             lossesToday++;
//             totalLoss += MathAbs(profit);
//             dailyPnL -= MathAbs(profit);
            
//             // Track maximum daily loss
//             if(MathAbs(dailyPnL) > dailyMaxLoss)
//                 dailyMaxLoss = MathAbs(dailyPnL);
//         }
        
//         // Update account equity
//         accountEquity = equity;
        
//         // Update derived metrics
//         UpdateDerivedMetrics();
//         metricsTime = TimeCurrent();
//         lastTradeTime = metricsTime;
//     }
    
//     // Update drawdown
//     void UpdateDrawdown(double equity, double peakEquity)
//     {
//         if(equity < peakEquity)
//         {
//             currentDrawdown = ((peakEquity - equity) / peakEquity) * 100.0;
            
//             if(currentDrawdown > maxDrawdown)
//                 maxDrawdown = currentDrawdown;
//         }
//         else
//         {
//             currentDrawdown = 0.0;
//         }
        
//         // Update recovery factor if we have drawdown
//         if(maxDrawdown > 0)
//             recoveryFactor = totalProfit / maxDrawdown;
//     }
    
//     // Calculate derived metrics
//     void UpdateDerivedMetrics()
//     {
//         // Win Rate
//         if(totalTrades > 0)
//             winRate = (double)totalWins / totalTrades * 100.0;
        
//         // Profit Factor
//         if(totalLoss > 0)
//             profitFactor = totalProfit / totalLoss;
        
//         // Expectancy
//         if(totalTrades > 0)
//         {
//             double avgWin = (totalWins > 0) ? totalProfit / totalWins : 0;
//             double avgLoss = (totalLosses > 0) ? totalLoss / totalLosses : 0;
//             double winProbability = winRate / 100.0;
            
//             expectancy = (winProbability * avgWin) - ((1 - winProbability) * avgLoss);
//         }
//     }
    
//     // Risk level determination
//     ENUM_RISK_LEVEL GetRiskLevel() const
//     {
//         double dailyLossPercent = (dailyPnL < 0 ? MathAbs(dailyPnL) / totalCapital : 0) * 100.0;
        
//         if(dailyLossPercent >= 5.0 || currentDrawdown >= 15.0)
//             return RISK_CRITICAL;
//         else if(dailyLossPercent >= 3.0 || currentDrawdown >= 10.0)
//             return RISK_HIGH;
//         else if(dailyLossPercent >= 1.5 || currentDrawdown >= 5.0)
//             return RISK_MODERATE;
//         else if(dailyLossPercent >= 0.5 || currentDrawdown >= 2.0)
//             return RISK_LOW;
//         else
//             return RISK_OPTIMAL;
//     }
    
//     // Account health assessment
//     ENUM_ACCOUNT_HEALTH GetAccountHealth() const
//     {
//         if(freeMarginPercent < 10.0 || currentDrawdown >= 15.0)
//             return HEALTH_CRITICAL;
//         else if(freeMarginPercent < 20.0 || currentDrawdown >= 10.0)
//             return HEALTH_WARNING;
//         else if(freeMarginPercent < 40.0 || currentDrawdown >= 5.0)
//             return HEALTH_GOOD;
//         else
//             return HEALTH_EXCELLENT;
//     }
    
//     // Daily loss limit check
//     bool IsDailyLossLimitExceeded(double limitPercent = 5.0) const
//     {
//         double dailyLossPercent = (dailyPnL < 0 ? MathAbs(dailyPnL) / totalCapital : 0) * 100.0;
//         return dailyLossPercent >= limitPercent;
//     }
    
//     // Reporting
//     string GetDailySummary() const
//     {
//         return StringFormat("Daily P&L: $%.2f (%.2f%%) | Trades: %d | Win Rate: %.1f%%",
//                           dailyPnL, (dailyPnL/totalCapital)*100, tradesToday, 
//                           (tradesToday > 0 ? (double)winsToday/tradesToday*100 : 0));
//     }
    
//     string GetPerformanceSummary() const
//     {
//         return StringFormat("Total Trades: %d | Win Rate: %.1f%% | PF: %.2f | Expectancy: $%.2f",
//                           totalTrades, winRate, profitFactor, expectancy);
//     }
    
//     string GetRiskSummary() const
//     {
//         ENUM_RISK_LEVEL riskLevel = GetRiskLevel();
//         string riskStr;
//         switch(riskLevel)
//         {
//             case RISK_CRITICAL: riskStr = "CRITICAL"; break;
//             case RISK_HIGH: riskStr = "HIGH"; break;
//             case RISK_MODERATE: riskStr = "MODERATE"; break;
//             case RISK_LOW: riskStr = "LOW"; break;
//             case RISK_OPTIMAL: riskStr = "OPTIMAL"; break;
//         }
        
//         return StringFormat("Risk Level: %s | Drawdown: %.2f%% (Max: %.2f%%) | Margin Free: %.1f%%",
//                           riskStr, currentDrawdown, maxDrawdown, freeMarginPercent);
//     }
    
//     void PrintFullReport() const
//     {
//         Print("\n═══════════════════════════════════════");
//         Print("          RISK METRICS REPORT");
//         Print("═══════════════════════════════════════");
//         Print("Daily Summary:");
//         Print("  " + GetDailySummary());
//         Print("\nPerformance Metrics:");
//         Print("  " + GetPerformanceSummary());
//         Print("\nRisk Assessment:");
//         Print("  " + GetRiskSummary());
//         Print("═══════════════════════════════════════\n");
//     }
// };

// #endif // RISK_DATA_MQH