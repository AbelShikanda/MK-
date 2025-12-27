// //+------------------------------------------------------------------+
// //|                        TradingData.mqh                           |
// //|              Trading decisions with risk integration             |
// //+------------------------------------------------------------------+
// #ifndef TRADING_DATA_MQH
// #define TRADING_DATA_MQH

// // #include "DataAnalysis.mqh"

// // // ============ TRADING ENUMS ============
// // enum ENUM_TRADE_SIGNAL_TYPE
// // {
// //     SIGNAL_NONE = 0,
// //     SIGNAL_ULTRA_BUY,
// //     SIGNAL_ULTRA_SELL,
// //     SIGNAL_STRONG_BUY,
// //     SIGNAL_STRONG_SELL,
// //     SIGNAL_WEAK_BUY,
// //     SIGNAL_WEAK_SELL
// // };

// // enum ENUM_TRADE_ACTION
// // {
// //     TRADE_ACTION_NONE,
// //     TRADE_ACTION_ENTER_BUY,
// //     TRADE_ACTION_ENTER_SELL,
// //     TRADE_ACTION_EXIT,
// //     TRADE_ACTION_REVERSE,
// //     TRADE_ACTION_ADD,
// //     TRADE_ACTION_REDUCE,
// //     TRADE_ACTION_HOLD
// // };

// // ============ TRADE SIGNAL STRUCTURE ============
// struct TradeSignal
// {
//     // Core identification
//     string id;
//     string symbol;
//     ENUM_TRADE_SIGNAL_TYPE type;
//     ENUM_TRADE_ACTION action;
//     datetime generationTime;
    
//     // Technical levels
//     double entryPrice;
//     double stopLoss;
//     double takeProfit;
//     double optimalEntry;      // Best price to enter
//     double entryRangeHigh;    // Max entry price
//     double entryRangeLow;     // Min entry price
    
//     // Analysis context
//     ENUM_TREND_STRENGTH trendStrength;
//     DivergenceSignal divergence;
//     TrendHealth trendHealth;
//     double confidence;        // 0-100
    
//     // Risk parameters (added during decision phase)
//     double riskPercent;       // % of account at risk
//     double positionSize;      // Lots
//     double riskAmount;        // Dollar risk
//     double rewardAmount;      // Dollar reward
//     double riskRewardRatio;
    
//     // Validation flags
//     bool isValid;
//     bool isExpired;
//     string reason;
//     string validationErrors[10];
//     int errorCount;
    
//     // Constructor
//     TradeSignal() : id(""), symbol(""), type(SIGNAL_NONE), action(TRADE_ACTION_NONE),
//                    generationTime(0), entryPrice(0.0), stopLoss(0.0), takeProfit(0.0),
//                    optimalEntry(0.0), entryRangeHigh(0.0), entryRangeLow(0.0),
//                    trendStrength(TREND_NEUTRAL), confidence(0.0), riskPercent(0.0),
//                    positionSize(0.0), riskAmount(0.0), rewardAmount(0.0),
//                    riskRewardRatio(0.0), isValid(false), isExpired(false),
//                    reason(""), errorCount(0) {}
    
//     // Methods
//     bool IsBuy() const 
//     { 
//         return type == SIGNAL_ULTRA_BUY || type == SIGNAL_STRONG_BUY || type == SIGNAL_WEAK_BUY; 
//     }
    
//     bool IsSell() const 
//     { 
//         return type == SIGNAL_ULTRA_SELL || type == SIGNAL_STRONG_SELL || type == SIGNAL_WEAK_SELL; 
//     }
    
//     bool IsUltra() const 
//     { 
//         return type == SIGNAL_ULTRA_BUY || type == SIGNAL_ULTRA_SELL; 
//     }
    
//     bool IsStrong() const 
//     { 
//         return type == SIGNAL_STRONG_BUY || type == SIGNAL_STRONG_SELL; 
//     }
    
//     bool IsWeak() const 
//     { 
//         return type == SIGNAL_WEAK_BUY || type == SIGNAL_WEAK_SELL; 
//     }
    
//     void AddValidationError(string error)
//     {
//         if(errorCount < 10)
//         {
//             validationErrors[errorCount] = error;
//             errorCount++;
//             isValid = false;
//         }
//     }
    
//     void Validate()
//     {
//         isValid = true;
//         errorCount = 0;
        
//         if(entryPrice <= 0) AddValidationError("Invalid entry price");
//         if(stopLoss <= 0) AddValidationError("Invalid stop loss");
//         if(takeProfit <= 0 && takeProfit != 0) AddValidationError("Invalid take profit");
//         if(confidence < 50) AddValidationError("Low confidence");
//         if(riskPercent > 5) AddValidationError("Risk too high");
        
//         if(type == SIGNAL_NONE)
//         {
//             AddValidationError("No signal type specified");
//         }
        
//         // Check expiration (signals expire after 1 hour)
//         if(TimeCurrent() - generationTime > 3600)
//         {
//             isExpired = true;
//             AddValidationError("Signal expired");
//         }
//     }
    
//     string GetSignalName() const
//     {
//         switch(type)
//         {
//             case SIGNAL_ULTRA_BUY: return "ULTRA_BUY";
//             case SIGNAL_ULTRA_SELL: return "ULTRA_SELL";
//             case SIGNAL_STRONG_BUY: return "STRONG_BUY";
//             case SIGNAL_STRONG_SELL: return "STRONG_SELL";
//             case SIGNAL_WEAK_BUY: return "WEAK_BUY";
//             case SIGNAL_WEAK_SELL: return "WEAK_SELL";
//             default: return "NONE";
//         }
//     }
    
//     string GetSummary() const
//     {
//         string summary = StringFormat("%s %s Signal", symbol, GetSignalName());
//         summary += StringFormat("\nEntry: %.5f | SL: %.5f | TP: %.5f", entryPrice, stopLoss, takeProfit);
//         summary += StringFormat("\nConfidence: %.1f%% | Risk: %.2f%% | RR: %.2f", confidence, riskPercent, riskRewardRatio);
        
//         if(!isValid)
//         {
//             summary += "\nINVALID: ";
//             for(int i = 0; i < errorCount; i++)
//                 summary += validationErrors[i] + "; ";
//         }
        
//         return summary;
//     }
// };

// // ============ TRADE DECISION STRUCTURE ============
// struct TradeDecision
// {
//     // Decision identification
//     string decisionId;
//     TradeSignal signal;
//     datetime decisionTime;
    
//     // Risk-adjusted parameters
//     double approvedLotSize;
//     double approvedRiskPercent;
//     double maxLossAmount;
//     double expectedProfit;
    
//     // Account context at decision time
//     double accountBalance;
//     double accountEquity;
//     double freeMargin;
//     int openPositions;
    
//     // Approval chain
//     bool isApproved;
//     string approver;           // "RISK_MANAGER", "STRATEGY", "MANUAL_OVERRIDE"
//     string approvalNotes;
//     datetime approvalTime;
    
//     // Execution status
//     bool isExecuted;
//     ulong orderTicket;
//     datetime executionTime;
    
//     // Constructor
//     TradeDecision() : decisionId(""), decisionTime(0),
//                      approvedLotSize(0.0), approvedRiskPercent(0.0),
//                      maxLossAmount(0.0), expectedProfit(0.0),
//                      accountBalance(0.0), accountEquity(0.0),
//                      freeMargin(0.0), openPositions(0),
//                      isApproved(false), approver(""), approvalNotes(""),
//                      approvalTime(0), isExecuted(false),
//                      orderTicket(0), executionTime(0) {}
    
//     // Methods
//     void Approve(double lotSize, double riskPercent, string notes = "", string who = "RISK_MANAGER")
//     {
//         approvedLotSize = lotSize;
//         approvedRiskPercent = riskPercent;
//         maxLossAmount = accountBalance * (riskPercent / 100.0);
        
//         // Calculate expected profit based on signal's RR
//         if(signal.riskRewardRatio > 0)
//             expectedProfit = maxLossAmount * signal.riskRewardRatio;
        
//         isApproved = true;
//         approver = who;
//         approvalNotes = notes;
//         approvalTime = TimeCurrent();
//     }
    
//     void Reject(string reason)
//     {
//         isApproved = false;
//         approver = "RISK_MANAGER";
//         approvalNotes = "REJECTED: " + reason;
//         approvalTime = TimeCurrent();
//     }
    
//     double GetRiskAmount() const
//     {
//         return maxLossAmount;
//     }
    
//     double GetRewardAmount() const
//     {
//         return expectedProfit;
//     }
    
//     string GetStatus() const
//     {
//         if(!isApproved) return "REJECTED";
//         if(isExecuted) return "EXECUTED";
//         return "APPROVED_PENDING";
//     }
    
//     string GetDecisionSummary() const
//     {
//         string summary = StringFormat("Decision: %s | Signal: %s", 
//                                     decisionId, signal.GetSignalName());
//         summary += StringFormat("\nStatus: %s | Approved: %s", 
//                               GetStatus(), isApproved ? "Yes" : "No");
        
//         if(isApproved)
//         {
//             summary += StringFormat("\nLot Size: %.3f | Risk: %.2f%% ($%.2f)", 
//                                   approvedLotSize, approvedRiskPercent, maxLossAmount);
//             summary += StringFormat("\nExpected Profit: $%.2f (RR: %.2f)", 
//                                   expectedProfit, signal.riskRewardRatio);
//         }
        
//         if(approvalNotes != "")
//             summary += "\nNotes: " + approvalNotes;
            
//         return summary;
//     }
// };

// #endif // TRADING_DATA_MQH