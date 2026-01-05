//+------------------------------------------------------------------+
//|                                              ConfidenceTracker.mqh |
//|                        Copyright 2023, Your Company Name Here    |
//|                                       https://www.yourwebsite.com|
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      "https://www.yourwebsite.com"
#property strict

#include <MathUtils.mqh>
#include <LoggerUtils.mqh>

//+------------------------------------------------------------------+
//| Confidence Trend Enum                                            |
//+------------------------------------------------------------------+
enum ConfidenceTrend 
{
    TREND_UP,      // Confidence is increasing
    TREND_DOWN,    // Confidence is decreasing
    TREND_FLAT,    // Confidence is stable
    TREND_VOLATILE // Confidence is highly volatile
};

//+------------------------------------------------------------------+
//| Confidence Tracker Class                                         |
//+------------------------------------------------------------------+
class ConfidenceTracker
{
private:
    struct ConfidenceData
    {
        double score;
        datetime timestamp;
        string source;
        double weight;
    };
    
    ConfidenceData historyBuffer[];
    string trendAnalyzer;
    int bufferSize;
    
    // Statistical indicators
    double smaValues[];
    double emaValues[];
    double stdDevValues[];
    
    // Alert thresholds
    double degradationThreshold;
    double volatilityThreshold;
    double confidenceFloor;
    
    Logger logger;
    
public:
    ConfidenceTracker(int bufferSize = 100)
    {
        this.bufferSize = bufferSize;
        ArrayResize(historyBuffer, bufferSize);
        InitializeBuffer();
        
        // Initialize statistical arrays
        ArrayResize(smaValues, 0);
        ArrayResize(emaValues, 0);
        ArrayResize(stdDevValues, 0);
        
        // Default thresholds
        degradationThreshold = 0.15; // 15% drop triggers degradation
        volatilityThreshold = 0.25;  // 25% std dev considered volatile
        confidenceFloor = 0.3;       // Below this is considered low confidence
        
        trendAnalyzer = "adaptive";
        
        // Initialize logger
        logger.Initialize("ConfidenceTracker.log", true, true);
    }
    
    ~ConfidenceTracker()
    {
        // Cleanup
        ArrayFree(historyBuffer);
        ArrayFree(smaValues);
        ArrayFree(emaValues);
        ArrayFree(stdDevValues);
    }
    
    // Track score with optional weight
    void TrackScore(double score, string source = "unknown", double weight = 1.0)
    {
        // Validate score
        if(score < 0.0 || score > 1.0)
        {
            logger.LogError("ConfidenceTracker", 
                StringFormat("Invalid confidence score: %.2f (must be 0.0-1.0)", score));
            score = MathMin(MathMax(score, 0.0), 1.0);
        }
        
        // Shift buffer
        for(int i = bufferSize - 1; i > 0; i--)
        {
            historyBuffer[i] = historyBuffer[i - 1];
        }
        
        // Add new data point
        historyBuffer[0].score = score;
        historyBuffer[0].timestamp = TimeCurrent();
        historyBuffer[0].source = source;
        historyBuffer[0].weight = MathMin(MathMax(weight, 0.1), 2.0);
        
        // Update statistical indicators
        UpdateIndicators();
        
        // Log if significant change
        LogSignificantChanges();
    }
    
    // Calculate average confidence (weighted)
    double CalculateAverage(int periods = 0, bool weighted = true)
    {
        if(periods <= 0 || periods > bufferSize)
            periods = bufferSize;
        
        double sum = 0;
        double weightSum = 0;
        int validCount = 0;
        
        for(int i = 0; i < periods; i++)
        {
            if(historyBuffer[i].score >= 0) // Valid score
            {
                if(weighted)
                {
                    sum += historyBuffer[i].score * historyBuffer[i].weight;
                    weightSum += historyBuffer[i].weight;
                }
                else
                {
                    sum += historyBuffer[i].score;
                }
                validCount++;
            }
        }
        
        if(validCount == 0) return 0.0;
        
        if(weighted && weightSum > 0)
            return sum / weightSum;
        else
            return sum / validCount;
    }
    
    // Detect degradation in confidence
    bool DetectDegradation(int shortPeriod = 5, int longPeriod = 20)
    {
        if(GetValidDataCount() < longPeriod)
            return false;
        
        double shortTermAvg = CalculateAverage(shortPeriod, true);
        double longTermAvg = CalculateAverage(longPeriod, true);
        
        if(longTermAvg <= 0) return false;
        
        double degradation = (longTermAvg - shortTermAvg) / longTermAvg;
        
        bool isDegrading = (degradation >= degradationThreshold);
        
        if(isDegrading)
        {
            logger.Log("ConfidenceTracker",
                StringFormat("Degradation detected: Short=%.2f, Long=%.2f, Degradation=%.1f%%",
                    shortTermAvg, longTermAvg, degradation * 100));
        }
        
        return isDegrading;
    }
    
    // Get confidence trend
    ConfidenceTrend GetTrend(int lookback = 10)
    {
        if(GetValidDataCount() < lookback)
            return TREND_FLAT;
        
        // Calculate slope using linear regression
        double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
        int n = 0;
        
        for(int i = 0; i < lookback; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                sumX += i;
                sumY += historyBuffer[i].score;
                sumXY += i * historyBuffer[i].score;
                sumX2 += i * i;
                n++;
            }
        }
        
        if(n < 3) return TREND_FLAT;
        
        double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
        
        // Calculate volatility
        double avg = sumY / n;
        double variance = 0;
        for(int i = 0; i < lookback; i++)
        {
            if(historyBuffer[i].score >= 0)
                variance += MathPow(historyBuffer[i].score - avg, 2);
        }
        variance /= n;
        double volatility = MathSqrt(variance);
        
        // Determine trend
        if(volatility > volatilityThreshold)
            return TREND_VOLATILE;
        else if(slope > 0.01)
            return TREND_UP;
        else if(slope < -0.01)
            return TREND_DOWN;
        else
            return TREND_FLAT;
    }
    
    // Get confidence score with momentum
    double GetConfidenceWithMomentum()
    {
        double currentAvg = CalculateAverage(5, true); // Short-term average
        ConfidenceTrend trend = GetTrend(10);
        
        double momentumFactor = 1.0;
        
        switch(trend)
        {
            case TREND_UP:
                momentumFactor = 1.1; // Boost confidence if trending up
                break;
            case TREND_DOWN:
                momentumFactor = 0.9; // Reduce confidence if trending down
                break;
            case TREND_VOLATILE:
                momentumFactor = 0.8; // Significant reduction for volatility
                break;
        }
        
        return MathMin(MathMax(currentAvg * momentumFactor, 0.0), 1.0);
    }
    
    // Get confidence stability score (0.0-1.0)
    double GetStabilityScore(int periods = 20)
    {
        if(GetValidDataCount() < periods)
            return 0.5; // Neutral if not enough data
        
        // Calculate standard deviation of recent scores
        double scores[];
        ArrayResize(scores, periods);
        int count = 0;
        
        for(int i = 0; i < periods; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                scores[count] = historyBuffer[i].score;
                count++;
            }
        }
        
        if(count < 3) return 0.5;
        
        ArrayResize(scores, count);
        double stdDev = CalculateStandardDeviation(scores);
        
        // Convert to stability score (higher std dev = lower stability)
        double stability = 1.0 - MathMin(stdDev * 2.0, 1.0);
        
        return MathMax(stability, 0.0);
    }
    
    // Predict next confidence value
    double PredictNext(int method = 0) // 0=SMA, 1=EMA, 2=Linear
    {
        if(GetValidDataCount() < 5)
            return CalculateAverage(5, true);
        
        switch(method)
        {
            case 0: // Simple Moving Average
                if(ArraySize(smaValues) > 0)
                    return smaValues[ArraySize(smaValues) - 1];
                break;
                
            case 1: // Exponential Moving Average
                if(ArraySize(emaValues) > 0)
                    return emaValues[ArraySize(emaValues) - 1];
                break;
                
            case 2: // Linear Regression
                return PredictLinear();
        }
        
        return CalculateAverage(5, true);
    }
    
    // Get confidence histogram data
    void GetHistogramData(double &bins[], int binCount = 10)
    {
        ArrayResize(bins, binCount);
        ArrayInitialize(bins, 0);
        
        int total = 0;
        for(int i = 0; i < bufferSize; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                int binIndex = (int)(historyBuffer[i].score * binCount);
                if(binIndex >= binCount) binIndex = binCount - 1;
                bins[binIndex]++;
                total++;
            }
        }
        
        // Convert to percentages
        if(total > 0)
        {
            for(int i = 0; i < binCount; i++)
                bins[i] = bins[i] / total * 100;
        }
    }
    
    // Reset tracker
    void Reset()
    {
        InitializeBuffer();
        ArrayResize(smaValues, 0);
        ArrayResize(emaValues, 0);
        ArrayResize(stdDevValues, 0);
        
        logger.Log("ConfidenceTracker", "Tracker reset");
    }
    
    // Get statistics report
    string GetStatisticsReport()
    {
        int validCount = GetValidDataCount();
        
        if(validCount == 0)
            return "No confidence data available";
        
        double avg = CalculateAverage(validCount, true);
        double minVal = 1.0;
        double maxVal = 0.0;
        double weightedSum = 0;
        double weightSum = 0;
        
        for(int i = 0; i < validCount; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                if(historyBuffer[i].score < minVal) minVal = historyBuffer[i].score;
                if(historyBuffer[i].score > maxVal) maxVal = historyBuffer[i].score;
                weightedSum += historyBuffer[i].score * historyBuffer[i].weight;
                weightSum += historyBuffer[i].weight;
            }
        }
        
        double weightedAvg = weightSum > 0 ? weightedSum / weightSum : 0;
        
        // Calculate percentiles
        double scores[];
        ArrayResize(scores, validCount);
        int count = 0;
        
        for(int i = 0; i < validCount; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                scores[count] = historyBuffer[i].score;
                count++;
            }
        }
        
        ArrayResize(scores, count);
        ArraySort(scores);
        
        double median = count > 0 ? scores[count/2] : 0;
        double percentile25 = count > 0 ? scores[count/4] : 0;
        double percentile75 = count > 0 ? scores[count*3/4] : 0;
        
        ConfidenceTrend trend = GetTrend();
        string trendStr = TrendToString(trend);
        
        return StringFormat(
            "Confidence Statistics:\n" +
            "  Samples: %d\n" +
            "  Average: %.3f (Weighted: %.3f)\n" +
            "  Min/Max: %.3f / %.3f\n" +
            "  Median: %.3f\n" +
            "  25th/75th Percentile: %.3f / %.3f\n" +
            "  Current Trend: %s\n" +
            "  Stability: %.3f\n" +
            "  Degradation: %s",
            validCount, avg, weightedAvg, minVal, maxVal,
            median, percentile25, percentile75,
            trendStr, GetStabilityScore(),
            DetectDegradation() ? "DETECTED" : "None"
        );
    }
    
    // Get confidence time series for analysis
    void GetTimeSeries(double &scores[], datetime ×tamps[], int maxPoints = 100)
    {
        int validCount = GetValidDataCount();
        int points = MathMin(validCount, maxPoints);
        
        ArrayResize(scores, points);
        ArrayResize(timestamps, points);
        
        int index = 0;
        for(int i = 0; i < bufferSize && index < points; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                scores[index] = historyBuffer[i].score;
                timestamps[index] = historyBuffer[i].timestamp;
                index++;
            }
        }
        
        if(index < points)
        {
            ArrayResize(scores, index);
            ArrayResize(timestamps, index);
        }
    }
    
private:
    // Initialize buffer with invalid values
    void InitializeBuffer()
    {
        for(int i = 0; i < bufferSize; i++)
        {
            historyBuffer[i].score = -1.0; // Invalid marker
            historyBuffer[i].timestamp = 0;
            historyBuffer[i].source = "";
            historyBuffer[i].weight = 1.0;
        }
    }
    
    // Count valid data points
    int GetValidDataCount()
    {
        int count = 0;
        for(int i = 0; i < bufferSize; i++)
        {
            if(historyBuffer[i].score >= 0)
                count++;
        }
        return count;
    }
    
    // Update statistical indicators
    void UpdateIndicators()
    {
        int validCount = GetValidDataCount();
        if(validCount < 5) return;
        
        // Calculate SMA (5-period)
        double sma = CalculateAverage(5, false);
        ArrayResize(smaValues, ArraySize(smaValues) + 1);
        smaValues[ArraySize(smaValues) - 1] = sma;
        
        // Calculate EMA (5-period, alpha = 0.33)
        double alpha = 0.33;
        double ema = 0;
        if(ArraySize(emaValues) == 0)
            ema = sma;
        else
            ema = alpha * historyBuffer[0].score + (1 - alpha) * emaValues[ArraySize(emaValues) - 1];
        
        ArrayResize(emaValues, ArraySize(emaValues) + 1);
        emaValues[ArraySize(emaValues) - 1] = ema;
        
        // Calculate Std Dev (10-period)
        if(validCount >= 10)
        {
            double recentScores[];
            ArrayResize(recentScores, 10);
            int count = 0;
            
            for(int i = 0; i < 10; i++)
            {
                if(historyBuffer[i].score >= 0)
                {
                    recentScores[count] = historyBuffer[i].score;
                    count++;
                }
            }
            
            if(count >= 5)
            {
                ArrayResize(recentScores, count);
                double stdDev = CalculateStandardDeviation(recentScores);
                ArrayResize(stdDevValues, ArraySize(stdDevValues) + 1);
                stdDevValues[ArraySize(stdDevValues) - 1] = stdDev;
            }
        }
    }
    
    // Predict using linear regression
    double PredictLinear()
    {
        int lookback = MathMin(10, GetValidDataCount());
        if(lookback < 3) return 0.5;
        
        double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
        int n = 0;
        
        for(int i = 0; i < lookback; i++)
        {
            if(historyBuffer[i].score >= 0)
            {
                sumX += i;
                sumY += historyBuffer[i].score;
                sumXY += i * historyBuffer[i].score;
                sumX2 += i * i;
                n++;
            }
        }
        
        if(n < 3) return sumY / n;
        
        double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
        double intercept = (sumY - slope * sumX) / n;
        
        // Predict next value (x = -1 since we want to predict the next one)
        return intercept + slope * (-1);
    }
    
    // Log significant changes
    void LogSignificantChanges()
    {
        static double lastLoggedScore = -1;
        
        if(GetValidDataCount() < 2) return;
        
        double current = historyBuffer[0].score;
        
        if(lastLoggedScore < 0)
        {
            lastLoggedScore = current;
            return;
        }
        
        double change = MathAbs(current - lastLoggedScore);
        
        if(change > 0.2) // 20% change is significant
        {
            logger.Log("ConfidenceTracker",
                StringFormat("Significant confidence change: %.2f -> %.2f (Δ%.1f%%)",
                    lastLoggedScore, current, change * 100));
            
            lastLoggedScore = current;
        }
    }
    
    // Convert trend to string
    string TrendToString(ConfidenceTrend trend)
    {
        switch(trend)
        {
            case TREND_UP: return "UP ↗";
            case TREND_DOWN: return "DOWN ↘";
            case TREND_FLAT: return "FLAT →";
            case TREND_VOLATILE: return "VOLATILE ⚡";
            default: return "UNKNOWN";
        }
    }
};