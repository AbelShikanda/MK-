//+------------------------------------------------------------------+
//|                       TradeExecutor.mqh                         |
//|         Hierarchical MA Gap Decision System                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../config/structures.mqh"
#include "../utils/utils.mqh"
#include "../market/news/NewsFilter.mqh"
#include "../signals/SignalGenerator.mqh"
#include "../market/decision/DecisionEngine.mqh"
#include "../risk/ExposureController.mqh"
#include "PositionManager.mqh"
#include "OrderManager.mqh"
#include "../market/detectors/MARelationship.mqh"
#include "../market/trend/MATrends.mqh"

// ============ SIMPLE TWEAKABLE PARAMETERS ============
// Adjusted results confirmation threshold (1-3 scale, where >1.5 is confirmed)
input double Adjusted_Confirmation_Threshold = 1.5;
datetime lastCloseTime = 0;
input int Close_Position_Min_Interval = 900; // Minimum seconds between position closures (default: 1 minute)

//+------------------------------------------------------------------+
//| Get MATrends Action Based on Hierarchical MA Gaps               |
//+------------------------------------------------------------------+
string GetMATrendsAction(string symbol)
{
    // Get MA alignment data for gap calculations
    MAAlignmentScore alignment = CalculateMAAlignment(symbol);
    
    // Get current MA values for gap calculations
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
    
    if(!dataOk) {
        IndicatorRelease(hVeryFast);
        IndicatorRelease(hFast);
        IndicatorRelease(hMedium);
        IndicatorRelease(hSlow);
        return "WAIT";
    }
    
    // Calculate gaps
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double gap_5_9 = (vfCurrent[0] - fCurrent[0]) / point;
    double gap_9_21 = (fCurrent[0] - mCurrent[0]) / point;
    double gap_21_89 = (mCurrent[0] - sCurrent[0]) / point;
    
    // Get MA actions
    string action_21_89 = GetMA21_89Action(gap_21_89, alignment);
    string action_9_21 = GetMA9_21Action(gap_9_21, alignment);
    string action_5_9 = GetMA5_9Action(gap_5_9, alignment);
    
    // Clean up indicators
    IndicatorRelease(hVeryFast);
    IndicatorRelease(hFast);
    IndicatorRelease(hMedium);
    IndicatorRelease(hSlow);
    
    // ============ HIERARCHICAL DECISION LOGIC (CORRECTED) ============

    // Determine direction from 5-9 action
    string direction = "NEUTRAL";
    if(action_5_9 == "BUYING") direction = "BUY";
    else if(action_5_9 == "SELLING") direction = "SELL";
    else if(gap_5_9 > 0 && action_5_9 == "CLEAR") direction = "BUY";
    else if(gap_5_9 < 0 && action_5_9 == "CLEAR") direction = "SELL";
    else direction = "NEUTRAL";

    // ===== STEP 1: Check 21-89 foundation =====
    if(action_21_89 == "THINKING") {
        // Market is ranging - can still fold/close but not open new positions
        
        // Check for risk management actions (always allowed)
        if(action_5_9 == "FOLDING") {
            return "CLOSE_LOSERS";
        }
        else if(action_9_21 == "HOLDING") {
            return "CLOSE_SLOWLY";
        }
        else if(action_9_21 == "CLOSING") {
            return "CLOSE_SLOWLY";
        }
        
        return "WAIT"; // No new entries in ranging market
    }

    // ===== STEP 2: 21-89 is NOT "THINKING" =====
    // Now we can process entries and other actions

    if(action_21_89 == "CLEAR" || action_21_89 == "TREND_CONFIRMED" || action_21_89 == "REVERSED") {
        // First confirmation achieved
        
        // Check 9-21
        if(action_9_21 == "CLEAR" || action_9_21 == "ADDING") {
            // Second confirmation achieved
            
            // Check 5-9
            if(action_5_9 == "CLEAR" || action_5_9 == "BUYING" || action_5_9 == "SELLING") {
                // Final confirmation - TAKE POSITION
                if(direction == "BUY") return "BUY";
                else if(direction == "SELL") return "SELL";
                else return "WAIT";
            }
            else if(action_5_9 == "FOLDING") {
                // Close losing positions - market ranging
                return "CLOSE_LOSERS";
            }
        }
        else if(action_9_21 == "HOLDING") {
            // Close positions slowly
            return "CLOSE_SLOWLY";
        }
        else if(action_9_21 == "CLOSING") {
            // Close positions
            return "CLOSE_ALL";
        }
    }

    return "WAIT"; // Default case
}

//+------------------------------------------------------------------+
//| Check Adjusted Results Confirmation                             |
//+------------------------------------------------------------------+
bool CheckAdjustedConfirmation(AdjustedMarketData &marketData, string direction)
{
    // Calculate confirmation score (1-3 scale)
    // double confirmationScore = 0;
    
    // if(direction == "BUY") {
    //     if(marketData.adjustedSentiment > 0) confirmationScore++;
    //     if(marketData.adjustedTrend > 0) confirmationScore++;
    //     if(marketData.adjustedPressure > 0) confirmationScore++;
    // } else if(direction == "SELL") {
    //     if(marketData.adjustedSentiment < 0) confirmationScore++;
    //     if(marketData.adjustedTrend < 0) confirmationScore++;
    //     if(marketData.adjustedPressure < 0) confirmationScore++;
    // }
    
    // return (confirmationScore >= Adjusted_Confirmation_Threshold);
    return true;
}

//+------------------------------------------------------------------+
//| ExecuteTradeBasedOnDecision - Hierarchical MA Gaps              |
//+------------------------------------------------------------------+
string ExecuteTradeBasedOnDecision(string symbol)
{
    Print("=== HIERARCHICAL MA EXECUTOR START: ", symbol, " ===");
    
    // ============ 1. GET HIERARCHICAL MATRENDS DECISION ============
    string matrendsAction = GetMATrendsAction(symbol);
    
    // ============ 2. GET SECONDARY ADJUSTED RESULTS ============
    AdjustedMarketData marketData = GetAdjustedMarketData(symbol);
    
    // ============ 3. CHECK POSITIONS AND DIRECTION ============
    int openTrades = CountOpenTrades(symbol);
    int currentDirection = GetCurrentTradeDirection(symbol);
    
    string decision = "THINKING";
    string botThoughts = "THINKING";
    
    bool isBlocked = (openTrades >= MaxTradesPerSymbol) || dailyLimitReached || IsNewsBlackoutPeriod(symbol);
    
    // LOG THE HIERARCHICAL DECISION ALWAYS
    PrintFormat("\n=== HIERARCHICAL MA ANALYSIS ===");
    PrintFormat("Hierarchical MA Action: %s", matrendsAction);
    PrintFormat("Buy Score: %.1f, Sell Score: %.1f", marketData.buyScore, marketData.sellScore);
    PrintFormat("Positions: %d open, Direction: %s", 
                openTrades, 
                currentDirection == POSITION_TYPE_BUY ? "BUY" : 
                currentDirection == POSITION_TYPE_SELL ? "SELL" : "NONE");
    PrintFormat("Blocked Conditions:");
    PrintFormat("  Max Trades: %d/%d %s", openTrades, MaxTradesPerSymbol, 
                openTrades >= MaxTradesPerSymbol ? "❌ BLOCKED" : "✅ OK");
    PrintFormat("  Daily Limit: %s", dailyLimitReached ? "❌ REACHED" : "✅ OK");
    PrintFormat("  News Blackout: %s", IsNewsBlackoutPeriod(symbol) ? "❌ ACTIVE" : "✅ OK");
    PrintFormat("Overall Status: %s", isBlocked ? "🚫 PARTIALLY BLOCKED" : "✅ FULL ACCESS");
    
    // ============ 4. EXECUTE BASED ON HIERARCHICAL ACTION ============
    if(!isBlocked) {
        // ============ NO BLOCKING CONDITIONS - FULL ACCESS ============
        Print("\n✅ FULL ACCESS: Executing all actions");
        
        if(matrendsAction == "WAIT") {
            botThoughts = "MA_HIERARCHY_WAIT";
            decision = "WAIT";
            Print("ACTION: Wait (21-89 MA: THINKING)");
        }
        else if(matrendsAction == "CLOSE_LOSERS") {
            botThoughts = "MA_HIERARCHY_CLOSE_LOSERS";
            decision = "FOLDING";
            if(openTrades > 0) {
                Print("ACTION: Folding - Closing biggest losing position");
                CloseBiggestLosingPosition(symbol);  // Fold losing positions
            }
        }
        else if(matrendsAction == "CLOSE_SLOWLY") {
            botThoughts = "MA_HIERARCHY_CLOSE_SLOWLY";
            decision = "FOLDING_SLOWLY";
            if(openTrades > 0) {
                datetime currentTime = TimeCurrent();
                
                if(currentTime - lastCloseTime >= Close_Position_Min_Interval) {
                    Print("ACTION: Folding slowly - Closing biggest losing position");
                    if(CloseBiggestLosingPosition(symbol)) {
                        lastCloseTime = currentTime;
                    }
                } else {
                    PrintFormat("Skipping closure - Too soon. Next available in %d seconds", 
                            Close_Position_Min_Interval - (currentTime - lastCloseTime));
                }
            }
        }
        else if(matrendsAction == "CLOSE_ALL") {
            // CRITICAL FIX: "CLOSE_ALL" should fold first, not immediately close everything
            if(openTrades > 0) {
                // FIRST: Try folding (close losers only)
                botThoughts = "MA_HIERARCHY_CLOSE_ALL_FOLD_FIRST";
                decision = "FOLDING_ALL";
                Print("ACTION: Close All signal received - Attempting to fold losing positions first");
                
                // Try folding losing positions
                if(CloseBiggestLosingPosition(symbol)) {
                    Print("Folded one losing position");
                    // Check if we need to fold more
                    if(openTrades > 1) {
                        // Wait for next tick to fold more if needed
                        // Don't close all positions immediately
                    }
                } else {
                    // If no losing positions to fold, consider closing all
                    botThoughts = "MA_HIERARCHY_CLOSE_ALL_NO_LOSERS";
                    decision = "CLOSING_ALL";
                    Print("ACTION: No losing positions to fold - Closing all positions");
                    CloseAllPositions();
                }
            }
        }
        else if(matrendsAction == "BUY") {
            bool adjustedConfirm = CheckAdjustedConfirmation(marketData, "BUY");
            
            if(currentDirection == POSITION_TYPE_SELL && openTrades > 0) {
                botThoughts = "MA_HIERARCHY_CLOSE_SELL_FOR_BUY";
                decision = "LONG";
                Print("ACTION: Closing SELL for BUY (Hierarchical MA BUY signal)");
                ClosePositionType(symbol, POSITION_TYPE_SELL);
                if(adjustedConfirm) OpenNewPosition(symbol, true);
            }
            else if(currentDirection != POSITION_TYPE_BUY && openTrades == 0) {
                botThoughts = "MA_HIERARCHY_BUY_ENTRY";
                decision = "LONG";
                Print("ACTION: Opening BUY (Hierarchical MA BUY signal)");
                if(adjustedConfirm) OpenNewPosition(symbol, true);
            }
            else if(currentDirection == POSITION_TYPE_BUY && openTrades < MaxTradesPerSymbol) {
                botThoughts = "MA_HIERARCHY_ADD_TO_BUY";
                decision = "ADDING";
                Print("ACTION: Adding to BUY (Hierarchical MA BUY signal)");
                if(adjustedConfirm) AddToPosition(symbol, true);
            }
            else {
                botThoughts = "MA_HIERARCHY_HOLD_BUY";
                decision = "HOLDING";
                Print("ACTION: Hold existing BUY (Hierarchical MA BUY signal)");
            }
        }
        else if(matrendsAction == "SELL") {
            bool adjustedConfirm = CheckAdjustedConfirmation(marketData, "SELL");
            
            if(currentDirection == POSITION_TYPE_BUY && openTrades > 0) {
                botThoughts = "MA_HIERARCHY_CLOSE_BUY_FOR_SELL";
                decision = "SHORT";
                Print("ACTION: Closing BUY for SELL (Hierarchical MA SELL signal)");
                ClosePositionType(symbol, POSITION_TYPE_BUY);
                if(adjustedConfirm) OpenNewPosition(symbol, false);
            }
            else if(currentDirection != POSITION_TYPE_SELL && openTrades == 0) {
                botThoughts = "MA_HIERARCHY_SELL_ENTRY";
                decision = "SHORT";
                Print("ACTION: Opening SELL (Hierarchical MA SELL signal)");
                if(adjustedConfirm) OpenNewPosition(symbol, false);
            }
            else if(currentDirection == POSITION_TYPE_SELL && openTrades < MaxTradesPerSymbol) {
                botThoughts = "MA_HIERARCHY_ADD_TO_SELL";
                decision = "ADDING";
                Print("ACTION: Adding to SELL (Hierarchical MA SELL signal)");
                if(adjustedConfirm) AddToPosition(symbol, false);
            }
            else {
                botThoughts = "MA_HIERARCHY_HOLD_SELL";
                decision = "HOLDING";
                Print("ACTION: Hold existing SELL (Hierarchical MA SELL signal)");
            }
        }
    }
    else {
        // ============ BLOCKING CONDITIONS - SELECTIVE ACCESS ============
        Print("\n🚫 PARTIAL ACCESS: Checking what actions are possible");
        
        // STRATEGIC LOGIC: What CAN we do even when blocked?
        
        if(matrendsAction == "WAIT") {
            // Always allowed - just waiting
            botThoughts = "MA_HIERARCHY_WAIT_BLOCKED";
            decision = "WAIT";
            Print("ACTION: Wait (21-89 MA: THINKING) - Allowed even when blocked");
        }
        else if(matrendsAction == "CLOSE_LOSERS") {
            botThoughts = "MA_HIERARCHY_CLOSE_LOSERS_BLOCKED";
            decision = "FOLDING_BLOCKED";
            if(openTrades > 0) {
                Print("ACTION: Folding - Closing biggest losing position - ALLOWED (Risk management)");
                CloseBiggestLosingPosition(symbol);
            }
        }
        else if(matrendsAction == "CLOSE_SLOWLY") {
            botThoughts = "MA_HIERARCHY_CLOSE_SLOWLY_BLOCKED";
            decision = "FOLDING_BLOCKED";
            if(openTrades > 0) {
                datetime currentTime = TimeCurrent();
                if(currentTime - lastCloseTime >= Close_Position_Min_Interval) {
                    Print("ACTION: Folding slowly - Closing biggest losing position - ALLOWED (Risk management)");
                    if(CloseBiggestLosingPosition(symbol)) {
                        lastCloseTime = currentTime;
                    }
                }
            }
        }
        else if(matrendsAction == "CLOSE_ALL") {
            // CRITICAL FIX: Even when blocked, fold first
            botThoughts = "MA_HIERARCHY_CLOSE_ALL_FOLD_FIRST_BLOCKED";
            decision = "FOLDING_BLOCKED";
            if(openTrades > 0) {
                Print("ACTION: Close All signal (blocked) - Attempting to fold losing positions");
                if(!CloseBiggestLosingPosition(symbol)) {
                    // If no losers to fold, check if we should close all
                    Print("No losing positions to fold while blocked");
                    // Don't close all while blocked - too aggressive
                }
            }
        }
        else if(matrendsAction == "BUY") {
            // Check what's specifically blocking us
            bool canReverse = false;
            bool canCloseForReverse = false;
            
            if(openTrades >= MaxTradesPerSymbol) {
                Print("Blocked by: Position limit");
                // Can we reverse existing positions?
                if(currentDirection == POSITION_TYPE_SELL && openTrades > 0) {
                    canCloseForReverse = true;
                }
            }
            
            if(dailyLimitReached) {
                Print("Blocked by: Daily limit reached");
            }
            
            if(IsNewsBlackoutPeriod(symbol)) {
                Print("Blocked by: News blackout");
            }
            
            // Strategic decision based on blocking type
            if(canCloseForReverse) {
                botThoughts = "MA_HIERARCHY_CLOSE_SELL_FOR_BUY_BLOCKED";
                decision = "LONG_BLOCKED_CAN_REVERSE";
                Print("ACTION: Closing SELL position to make room for BUY");
                ClosePositionType(symbol, POSITION_TYPE_SELL);
            }
            else if(openTrades > 0 && currentDirection == POSITION_TYPE_BUY) {
                // When blocked from adding to BUY, consider folding losing positions
                botThoughts = "MA_HIERARCHY_FOLD_LOSING_BUY_BLOCKED";
                decision = "FOLDING_BLOCKED";
                Print("ACTION: Blocked from adding to BUY - Checking if we should fold losing positions");
                CloseBiggestLosingPosition(symbol);
            }
            else {
                botThoughts = "MA_HIERARCHY_BUY_BLOCKED";
                decision = "BLOCKED";
                Print("ACTION: BUY signal - COMPLETELY BLOCKED");
            }
        }
        else if(matrendsAction == "SELL") {
            // Check what's specifically blocking us
            bool canReverse = false;
            bool canCloseForReverse = false;
            
            if(openTrades >= MaxTradesPerSymbol) {
                Print("Blocked by: Position limit");
                // Can we reverse existing positions?
                if(currentDirection == POSITION_TYPE_BUY && openTrades > 0) {
                    canCloseForReverse = true;
                }
            }
            
            if(dailyLimitReached) {
                Print("Blocked by: Daily limit reached");
            }
            
            if(IsNewsBlackoutPeriod(symbol)) {
                Print("Blocked by: News blackout");
            }
            
            // Strategic decision based on blocking type
            if(canCloseForReverse) {
                botThoughts = "MA_HIERARCHY_CLOSE_BUY_FOR_SELL_BLOCKED";
                decision = "SHORT_BLOCKED_CAN_REVERSE";
                Print("ACTION: Closing BUY position to make room for SELL");
                ClosePositionType(symbol, POSITION_TYPE_BUY);
            }
            else if(openTrades > 0 && currentDirection == POSITION_TYPE_SELL) {
                // When blocked from adding to SELL, consider folding losing positions
                botThoughts = "MA_HIERARCHY_FOLD_LOSING_SELL_BLOCKED";
                decision = "FOLDING_BLOCKED";
                Print("ACTION: Blocked from adding to SELL - Checking if we should fold losing positions");
                CloseBiggestLosingPosition(symbol);
            }
            else {
                botThoughts = "MA_HIERARCHY_SELL_BLOCKED";
                decision = "BLOCKED";
                Print("ACTION: SELL signal - COMPLETELY BLOCKED");
            }
        }
    }
    // ============ 5. LOGGING ============
    PrintFormat("\n=== FINAL DECISION ===");
    PrintFormat("Hierarchical MA Action: %s", matrendsAction);
    PrintFormat("Adjusted Confirmation: %s", CheckAdjustedConfirmation(marketData, 
               matrendsAction == "BUY" ? "BUY" : (matrendsAction == "SELL" ? "SELL" : "NEUTRAL")) ? "YES" : "NO");
    PrintFormat("Final Decision: %s", decision);
    PrintFormat("Bot Thoughts: %s", botThoughts);
    Print("=== HIERARCHICAL MA EXECUTOR END ===\n");
    
    botConclusion = botThoughts;
    return decision;
}

// ============ KEEP THE REST EXACTLY AS IS ============
// The functions below remain unchanged from your original file
//+------------------------------------------------------------------+
//| GetBotConclusion                                                |
//+------------------------------------------------------------------+
string GetBotConclusion()
{
    return botConclusion;
}

//+------------------------------------------------------------------+
//| ExecuteTradingLogic                                             |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbol = activeSymbols[i];
        ExecuteTradeBasedOnDecision(symbol);
    }
}

//+------------------------------------------------------------------+
//| ExecuteSymbolManagementLogic                                    |
//+------------------------------------------------------------------+
void ExecuteSymbolManagementLogic()
{
    Print("Executing symbol management logic...");
    
    CheckSymbolRotation();
    UpdateSymbolPriority();
    LogSymbolStatus();
}

// ============ SYMBOL MANAGEMENT FUNCTIONS ============

void CheckSymbolRotation() {
    Print("Checking symbol rotation...");
}

void UpdateSymbolPriority() {
    Print("Updating symbol priority...");
}

void LogSymbolStatus() {
    Print("Logging symbol status...");
}

//+------------------------------------------------------------------+
//| Test Trade Execution (for debugging)                            |
//+------------------------------------------------------------------+
void TestTradeExecution(string symbol = "XAUUSD")
{
    Print("=== FORCED TRADE TEST ===");
    
    // Check basic conditions
    PrintFormat("Symbol: %s", symbol);
    PrintFormat("MaxTradesPerSymbol: %d", MaxTradesPerSymbol);
    PrintFormat("Current open trades: %d", CountOpenTrades(symbol));
    PrintFormat("dailyLimitReached: %s", dailyLimitReached ? "TRUE" : "FALSE");
    PrintFormat("IsNewsBlackoutPeriod: %s", IsNewsBlackoutPeriod(symbol) ? "TRUE" : "FALSE");
    
    // Try to open a small position
    double testSize = 0.01;
    PrintFormat("Attempting to open SELL with %.3f lots", testSize);
    
    bool result = OpenNewPosition(symbol, false, DoubleToString(testSize, 2));
    PrintFormat("OpenNewPosition result: %s (Error: %d)", 
                result ? "SUCCESS" : "FAILED", GetLastError());
    
    if(!result) {
        Print("Possible issues:");
        Print("1. Insufficient margin");
        Print("2. Broker restrictions (stop levels, freeze levels)");
        Print("3. Symbol not tradeable");
        Print("4. Trading disabled");
    }
}

//+------------------------------------------------------------------+
//| Debug Position Sizing                                           |
//+------------------------------------------------------------------+
void DebugPositionSizing(string symbol = "XAUUSD")
{
    Print("=== POSITION SIZING DEBUG ===");
    
    // Get current account info
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    PrintFormat("Account Info:");
    PrintFormat("  Balance: $%.2f", balance);
    PrintFormat("  Equity: $%.2f", equity);
    PrintFormat("  Free Margin: $%.2f", freeMargin);
    
    // Check symbol info
    PrintFormat("Symbol Info for %s:", symbol);
    PrintFormat("  Tradeable: %s", SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) ? "YES" : "NO");
    
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    PrintFormat("  Min Lot: %.2f", minLot);
    PrintFormat("  Max Lot: %.2f", maxLot);
    PrintFormat("  Lot Step: %.2f", lotStep);
    
    // Try progressive position sizing
    Print("Testing progressive position sizing...");
    
    // You'll need to call your actual position sizing function
    // double size = CalculateProgressivePositionSize(symbol);
    // PrintFormat("  Calculated size: %.3f lots", size);
}