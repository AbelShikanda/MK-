//+------------------------------------------------------------------+
//| SignalScorer.mqh                                                 |
//| Signal Scoring and Ranking Module                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// Includes
#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../config/structures.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../market/trend/MultiTimeframe.mqh"
#include "../market/trend/MomentumCalculator.mqh"
#include "../market/detectors/ReversalDetector.mqh"

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
int signalHistoryCount = 0;

//+------------------------------------------------------------------+
//| Get Ultra-Sensitive Signal Score (0-100)                        |
//| Main scoring function for signal quality assessment            |
//+------------------------------------------------------------------+
int GetUltraSensitiveSignalScore(const string symbol, const bool isBuy)
{
    int score = 0;
    
    // 1. Multi-Timeframe Alignment (40% weight)
    const double mtfAlignment = CalculateMultiTFAlignment(symbol, isBuy);
    score += (int)(mtfAlignment * 0.4);
    
    // 2. Trend Momentum (25% weight)
    const double momentum = CalculateTrendMomentum(symbol, isBuy, TradeTF);
    score += (int)(momentum * 0.25);
    
    // 3. RSI Filter (5 points)
    const int symbolIndex = ArrayPosition(symbol);
    if(symbolIndex != -1)
    {
        const double rsiValue = GetCurrentRSIValue(rsi_M5[symbolIndex]);
        if(isBuy)
        {
            if(rsiValue > 40 && rsiValue < 70) score += 5;
        }
        else
        {
            if(rsiValue < 60 && rsiValue > 30) score += 5;
        }
    }
    
    // 4. Stochastic Filter (5 points)
    if(UseStochasticFilter && symbolIndex != -1)
    {
        double stochK[1], stochD[1];
        if(CopyBuffer(stoch_M5[symbolIndex], 0, 0, 1, stochK) >= 1 &&
           CopyBuffer(stoch_M5[symbolIndex], 1, 0, 1, stochD) >= 1)
        {
            if(isBuy && stochK[0] > stochD[0] && stochK[0] < Stoch_Overbought)
                score += 5;
            else if(!isBuy && stochK[0] < stochD[0] && stochK[0] > Stoch_Oversold)
                score += 5;
        }
    }
    
    // 5. MACD Confirmation (3 points)
    if(UseMACDConfirmation && symbolIndex != -1)
    {
        double macdMain[1], macdSignal[1];
        if(CopyBuffer(macd_M5[symbolIndex], 0, 0, 1, macdMain) >= 1 &&
           CopyBuffer(macd_M5[symbolIndex], 1, 0, 1, macdSignal) >= 1)
        {
            if(isBuy && macdMain[0] > macdSignal[0] && macdMain[0] > 0)
                score += 3;
            else if(!isBuy && macdMain[0] < macdSignal[0] && macdMain[0] < 0)
                score += 3;
        }
    }
    
    // 6. Volume Confirmation (2 points)
    if(UseVolumeConfirmation)
    {
        const long currentVolume = iVolume(symbol, TradeTF, 0);
        const long previousVolume = iVolume(symbol, TradeTF, 1);
        
        if(currentVolume > previousVolume * 1.1)  // 10% higher volume
            score += 2;
    }
    
    // 7. Reversal Risk Penalty (up to 20 points deduction)
    const double reversalRisk = GetReversalConfidence(symbol, isBuy) * 100.0;
    score -= (int)(reversalRisk * 0.2);
    
    // Ensure score is within bounds
    return MathMax(0, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Track Signal with Static Array                                   |
//+------------------------------------------------------------------+
void TrackSignal(const string symbol, const string signalType, const double strength)
{
    // Safety check - ensure we don't exceed array bounds
    if(signalHistoryCount < 0)
    {
        Print("ERROR: signalHistoryCount is negative!");
        return;
    }
    
    // Circular buffer index calculation
    int index = signalHistoryCount % maxSignalHistory;  // 0-99
    
    // Debug: Show what we're doing
    PrintFormat("TRACK_SIGNAL: Storing at index %d (Count: %d, Max: %d)",
                index, signalHistoryCount, maxSignalHistory);
    
    // Store the signal in the static array
    signalHistory[index].symbol = symbol;
    signalHistory[index].type = signalType;
    signalHistory[index].strength = strength;
    signalHistory[index].timestamp = TimeCurrent();
    
    // Increment counter
    signalHistoryCount++;
    
    // Log the signal
    string timeStr = TimeToString(signalHistory[index].timestamp, TIME_DATE|TIME_SECONDS);
    string strengthLabel = (strength >= 70) ? "STRONG" : 
                          (strength >= 30) ? "MEDIUM" : "WEAK";
    
    PrintFormat("✅ SIGNAL #%d TRACKED: %s %s (%.1f%% - %s) at %s",
                signalHistoryCount,
                symbol,
                signalType,
                strength,
                strengthLabel,
                timeStr);
    
    // Optional: Show when buffer wraps around
    if(signalHistoryCount > 0 && signalHistoryCount % maxSignalHistory == 0)
    {
        PrintFormat("⚠️ Signal buffer wrapped around (%d signals total)", 
                   signalHistoryCount);
    }
}

//+------------------------------------------------------------------+
//| Get Enhanced Signal Score with Detailed Breakdown               |
//| Returns score with component breakdown for analysis            |
//+------------------------------------------------------------------+
SignalScore GetEnhancedSignalScore(const string symbol, const bool isBuy)
{
    SignalScore score;
    score.total = 0;
    score.mtfAlignment = 0;
    score.momentum = 0;
    score.rsiFilter = 0;
    score.stochastic = 0;
    score.macdConfirmation = 0;
    score.volumeConfirmation = 0;
    score.reversalPenalty = 0;
    
    const int symbolIndex = ArrayPosition(symbol);
    
    // 1. Multi-Timeframe Alignment
    score.mtfAlignment = CalculateMultiTFAlignment(symbol, isBuy) * 0.4;
    score.total += (int)score.mtfAlignment;
    
    // 2. Trend Momentum
    score.momentum = CalculateTrendMomentum(symbol, isBuy, TradeTF) * 0.25;
    score.total += (int)score.momentum;
    
    // 3. RSI Filter
    if(symbolIndex != -1)
    {
        const double rsiValue = GetCurrentRSIValue(rsi_M5[symbolIndex]);
        if(isBuy && rsiValue > 40 && rsiValue < 70)
        {
            score.rsiFilter = 5.0;
            score.total += 5;
        }
        else if(!isBuy && rsiValue < 60 && rsiValue > 30)
        {
            score.rsiFilter = 5.0;
            score.total += 5;
        }
    }
    
    // 4. Stochastic Filter
    if(UseStochasticFilter && symbolIndex != -1)
    {
        double stochK[1], stochD[1];
        if(CopyBuffer(stoch_M5[symbolIndex], 0, 0, 1, stochK) >= 1 &&
           CopyBuffer(stoch_M5[symbolIndex], 1, 0, 1, stochD) >= 1)
        {
            if(isBuy && stochK[0] > stochD[0] && stochK[0] < Stoch_Overbought)
            {
                score.stochastic = 5.0;
                score.total += 5;
            }
            else if(!isBuy && stochK[0] < stochD[0] && stochK[0] > Stoch_Oversold)
            {
                score.stochastic = 5.0;
                score.total += 5;
            }
        }
    }
    
    // 5. MACD Confirmation
    if(UseMACDConfirmation && symbolIndex != -1)
    {
        double macdMain[1], macdSignal[1];
        if(CopyBuffer(macd_M5[symbolIndex], 0, 0, 1, macdMain) >= 1 &&
           CopyBuffer(macd_M5[symbolIndex], 1, 0, 1, macdSignal) >= 1)
        {
            if(isBuy && macdMain[0] > macdSignal[0] && macdMain[0] > 0)
            {
                score.macdConfirmation = 3.0;
                score.total += 3;
            }
            else if(!isBuy && macdMain[0] < macdSignal[0] && macdMain[0] < 0)
            {
                score.macdConfirmation = 3.0;
                score.total += 3;
            }
        }
    }
    
    // 6. Volume Confirmation
    if(UseVolumeConfirmation)
    {
        const long currentVolume = iVolume(symbol, TradeTF, 0);
        const long previousVolume = iVolume(symbol, TradeTF, 1);
        
        if(currentVolume > previousVolume * 1.1)
        {
            score.volumeConfirmation = 2.0;
            score.total += 2;
        }
    }
    
    // 7. Reversal Penalty
    const double reversalRisk = GetReversalConfidence(symbol, isBuy) * 100.0;
    score.reversalPenalty = reversalRisk * 0.2;
    score.total -= (int)score.reversalPenalty;
    
    // Ensure score is within bounds
    score.total = MathMax(0, MathMin(100, score.total));
    
    // Track the scored signal
    TrackSignal(symbol, isBuy ? "BUY-SCORED" : "SELL-SCORED", score.total);
    
    return score;
}

//+------------------------------------------------------------------+
//| Calculate Signal Strength Level                                 |
//| Categorizes score into strength levels                         |
//+------------------------------------------------------------------+
string GetSignalStrengthLevel(const int score)
{
    if(score >= 90) return "EXCEPTIONAL";
    if(score >= 80) return "STRONG";
    if(score >= 70) return "GOOD";
    if(score >= 60) return "MODERATE";
    if(score >= 50) return "WEAK";
    if(score >= 40) return "POOR";
    return "VERY_POOR";
}

//+------------------------------------------------------------------+
//| Compare Signal Scores                                          |
//| Returns difference between buy and sell scores                 |
//+------------------------------------------------------------------+
int CompareSignalScores(const string symbol)
{
    const int buyScore = GetUltraSensitiveSignalScore(symbol, true);
    const int sellScore = GetUltraSensitiveSignalScore(symbol, false);
    
    return buyScore - sellScore;
}

//+------------------------------------------------------------------+
//| Get Signal Bias                                                 |
//| Returns bias direction based on score comparison               |
//+------------------------------------------------------------------+
string GetSignalBias(const string symbol)
{
    const int comparison = CompareSignalScores(symbol);
    
    if(comparison >= 30) return "STRONGLY_BULLISH";
    if(comparison >= 15) return "BULLISH";
    if(comparison >= 5) return "SLIGHTLY_BULLISH";
    if(comparison <= -30) return "STRONGLY_BEARISH";
    if(comparison <= -15) return "BEARISH";
    if(comparison <= -5) return "SLIGHTLY_BEARISH";
    
    return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Get Score Weighted Position Size                               |
//| Adjusts position size based on signal score                    |
//+------------------------------------------------------------------+
double GetScoreWeightedPositionSize(const string symbol, const bool isBuy, const double baseLotSize)
{
    const int score = GetUltraSensitiveSignalScore(symbol, isBuy);
    
    // Apply score-based multiplier
    double multiplier = 1.0;
    
    if(score >= 90) multiplier = 1.2;      // Exceptional: +20%
    else if(score >= 80) multiplier = 1.1; // Strong: +10%
    else if(score >= 70) multiplier = 1.0; // Good: Normal
    else if(score >= 60) multiplier = 0.8; // Moderate: -20%
    else if(score >= 50) multiplier = 0.5; // Weak: -50%
    else multiplier = 0.3;                 // Poor: -70%
    
    return baseLotSize * multiplier;
}

//+------------------------------------------------------------------+
//| Get Score Weighted Stop Loss                                   |
//| Adjusts stop loss based on signal score                        |
//+------------------------------------------------------------------+
double GetScoreWeightedStopLoss(const string symbol, const bool isBuy, const double baseStopLoss)
{
    const int score = GetUltraSensitiveSignalScore(symbol, isBuy);
    
    // Adjust stop loss based on confidence
    double adjustment = 0.0;
    
    if(score >= 80) adjustment = -0.1;      // Tighter SL for strong signals
    else if(score >= 60) adjustment = 0.0;   // Normal SL for moderate signals
    else adjustment = 0.2;                  // Wider SL for weak signals
    
    return baseStopLoss * (1.0 + adjustment);
}

//+------------------------------------------------------------------+
//| Get Recent Signal History (Updated for Struct Array)            |
//| Returns array of recent signals (newest first)                  |
//+------------------------------------------------------------------+
int GetRecentSignalHistory(string &symbols[], string &types[], string &strengths[], const int maxSignals = 10)
{
    // Calculate how many signals we actually have
    int totalSignals = MathMin(signalHistoryCount, maxSignalHistory);
    int signalsToReturn = MathMin(maxSignals, totalSignals);
    
    if(signalsToReturn == 0)
    {
        ArrayResize(symbols, 0);
        ArrayResize(types, 0);
        ArrayResize(strengths, 0);
        return 0;
    }
    
    // Resize output arrays
    ArrayResize(symbols, signalsToReturn);
    ArrayResize(types, signalsToReturn);
    ArrayResize(strengths, signalsToReturn);
    
    // Fill arrays with most recent signals (newest first)
    for(int i = 0; i < signalsToReturn; i++)
    {
        // Calculate index in circular buffer
        // (signalHistoryCount-1) gets most recent, -i goes backward
        int bufferIndex = (signalHistoryCount - 1 - i) % maxSignalHistory;
        
        // CORRECT: Access struct fields with dot notation
        symbols[i] = signalHistory[bufferIndex].symbol;                     // ✅ FIXED
        types[i] = signalHistory[bufferIndex].type;                         // ✅ FIXED
        strengths[i] = DoubleToString(signalHistory[bufferIndex].strength, 1) + "%"; // ✅ FIXED
    }
    
    return signalsToReturn;
}

//+------------------------------------------------------------------+
//| Clear Signal History (Updated for Struct Array)                 |
//| Clears all stored signal history                               |
//+------------------------------------------------------------------+
void ClearSignalHistory()
{
    // Clear all 100 structs in the array
    for(int i = 0; i < 100; i++)
    {
        // CORRECT: Use dot notation for struct fields
        signalHistory[i].symbol = "";        // ✅ Fixed
        signalHistory[i].type = "";          // ✅ Fixed
        signalHistory[i].strength = 0.0;     // ✅ Fixed (double, not string!)
        signalHistory[i].timestamp = 0;      // ✅ Fixed (datetime, not string!)
    }
    
    signalHistoryCount = 0;
    
    Print("✅ Signal history cleared (100 structs reset)");
}

//+------------------------------------------------------------------+
//| Get Average Signal Score                                       |
//| Calculates average score for a symbol over recent history     |
//+------------------------------------------------------------------+
double GetAverageSignalScore(const string symbol, const bool isBuy, const int lookback = 10)
{
    double totalScore = 0.0;
    int count = 0;
    
    // Simulate recent scores (in practice, would track actual historical scores)
    for(int i = 0; i < MathMin(lookback, 20); i++)
    {
        // This is a simplified version - would need actual historical tracking
        // For now, return current score
        if(i == 0)
        {
            return GetUltraSensitiveSignalScore(symbol, isBuy);
        }
    }
    
    return (count > 0) ? totalScore / count : 0.0;
}

//+------------------------------------------------------------------+
//| Is Signal Score Improving                                      |
//| Checks if signal score is trending upward                     |
//+------------------------------------------------------------------+
bool IsSignalScoreImproving(const string symbol, const bool isBuy)
{
    // Simplified implementation - would need actual historical tracking
    const int currentScore = GetUltraSensitiveSignalScore(symbol, isBuy);
    
    // For now, check if score is above threshold
    return (currentScore >= MinimumSignalScore);
}

//+------------------------------------------------------------------+
//| Get Most Recent Signals                                          |
//+------------------------------------------------------------------+
void PrintRecentSignals(int count = 10)
{
    if(count <= 0) return;
    
    // Calculate how many signals we actually have
    int totalSignals = MathMin(signalHistoryCount, maxSignalHistory);
    int signalsToShow = MathMin(count, totalSignals);
    
    if(signalsToShow == 0)
    {
        Print("No signals tracked yet.");
        return;
    }
    
    PrintFormat("\n=== LAST %d SIGNALS (of %d total) ===", 
                signalsToShow, signalHistoryCount);
    
    for(int i = 0; i < signalsToShow; i++)
    {
        // Calculate index (most recent first)
        int displayNum = i + 1;
        int bufferIndex = (signalHistoryCount - 1 - i) % maxSignalHistory;
        
        // Safety check
        if(bufferIndex < 0 || bufferIndex >= maxSignalHistory) continue;
        
        SignalRecord record = signalHistory[bufferIndex];
        
        if(record.timestamp > 0)  // Valid signal
        {
            string timeStr = TimeToString(record.timestamp, TIME_MINUTES|TIME_SECONDS);
            string strengthLabel = (record.strength >= 70) ? "STRONG" : 
                                  (record.strength >= 30) ? "MEDIUM" : "WEAK";
            
            PrintFormat("%2d. [%s] %-5s %-4s (%.1f%% - %s)",
                       displayNum,
                       timeStr,
                       record.symbol,
                       record.type,
                       record.strength,
                       strengthLabel);
        }
    }
    Print("====================================\n");
}

//+------------------------------------------------------------------+
//| Get Signal Statistics                                            |
//+------------------------------------------------------------------+
void PrintSignalStatistics()
{
    int totalSignals = MathMin(signalHistoryCount, maxSignalHistory);
    
    if(totalSignals == 0)
    {
        Print("Signal Statistics: No signals tracked");
        return;
    }
    
    int buySignals = 0;
    int sellSignals = 0;
    double avgStrength = 0.0;
    datetime oldestTime = TimeCurrent();
    datetime newestTime = 0;
    
    for(int i = 0; i < totalSignals; i++)
    {
        int index = (signalHistoryCount - 1 - i) % maxSignalHistory;
        SignalRecord record = signalHistory[index];
        
        if(record.type == "BUY") buySignals++;
        else if(record.type == "SELL") sellSignals++;
        
        avgStrength += record.strength;
        
        if(record.timestamp < oldestTime) oldestTime = record.timestamp;
        if(record.timestamp > newestTime) newestTime = record.timestamp;
    }
    
    avgStrength /= totalSignals;
    
    Print("=== SIGNAL STATISTICS ===");
    PrintFormat("Total Signals in Buffer: %d", totalSignals);
    PrintFormat("Total Signals Tracked: %d", signalHistoryCount);
    PrintFormat("BUY Signals: %d (%.1f%%)", buySignals, (buySignals*100.0/totalSignals));
    PrintFormat("SELL Signals: %d (%.1f%%)", sellSignals, (sellSignals*100.0/totalSignals));
    PrintFormat("Average Strength: %.1f%%", avgStrength);
    PrintFormat("Time Range: %s to %s",
                TimeToString(oldestTime, TIME_DATE|TIME_MINUTES),
                TimeToString(newestTime, TIME_DATE|TIME_MINUTES));
    PrintFormat("Buffer Usage: %d/%d (%.1f%%)",
                totalSignals, maxSignalHistory, (totalSignals*100.0/maxSignalHistory));
}

//+------------------------------------------------------------------+
//| Print Signal Score Breakdown                                   |
//| Detailed print of signal score components                     |
//+------------------------------------------------------------------+
void PrintSignalScoreBreakdown(const string symbol, const bool isBuy)
{
    const SignalScore score = GetEnhancedSignalScore(symbol, isBuy);
    
    Print("========================================");
    PrintFormat("SIGNAL SCORE BREAKDOWN for %s (%s)", symbol, isBuy ? "BUY" : "SELL");
    PrintFormat("Total Score: %d/100 (%s)", score.total, GetSignalStrengthLevel(score.total));
    PrintFormat("  Multi-Timeframe Alignment: %.1f points", score.mtfAlignment);
    PrintFormat("  Trend Momentum: %.1f points", score.momentum);
    PrintFormat("  RSI Filter: %.1f points", score.rsiFilter);
    PrintFormat("  Stochastic: %.1f points", score.stochastic);
    PrintFormat("  MACD Confirmation: %.1f points", score.macdConfirmation);
    PrintFormat("  Volume Confirmation: %.1f points", score.volumeConfirmation);
    PrintFormat("  Reversal Penalty: -%.1f points", score.reversalPenalty);
    Print("========================================");
}