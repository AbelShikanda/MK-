//+------------------------------------------------------------------+
//|                                              CorrelationEngine.mqh |
//|                                      Correlation Analysis Engine  |
//+------------------------------------------------------------------+
#include <Math\Alglib\alglib.mqh>

//+------------------------------------------------------------------+
//| Correlation Engine Class                                         |
//+------------------------------------------------------------------+
class CorrelationEngine {
private:
   int m_correlationWindow;
   ENUM_TIMEFRAMES m_defaultTimeframe;
   
public:
   CorrelationEngine(int window = 20, ENUM_TIMEFRAMES timeframe = PERIOD_H1) {
      m_correlationWindow = window;
      m_defaultTimeframe = timeframe;
   }
   
   // Main interface methods
   double CalculatePairCorrelation(string symbol1, string symbol2, 
                                   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, 
                                   int period = 0) {
      if(timeframe == PERIOD_CURRENT) timeframe = m_defaultTimeframe;
      if(period == 0) period = m_correlationWindow;
      
      // Get price data for both symbols
      double prices1[], prices2[];
      if(!GetPriceData(symbol1, timeframe, period, prices1) || 
         !GetPriceData(symbol2, timeframe, period, prices2)) {
         return 0.0;
      }
      
      // Calculate returns
      double returns1[], returns2[];
      ArrayResize(returns1, period - 1);
      ArrayResize(returns2, period - 1);
      
      for(int i = 0; i < period - 1; i++) {
         if(prices1[i+1] != 0) returns1[i] = (prices1[i] - prices1[i+1]) / prices1[i+1];
         if(prices2[i+1] != 0) returns2[i] = (prices2[i] - prices2[i+1]) / prices2[i+1];
      }
      
      // Calculate Pearson correlation
      return CalculatePearsonCorrelation(returns1, returns2);
   }
   
   double[][] BuildCorrelationMatrix(string &symbols[]) {
      int size = ArraySize(symbols);
      double matrix[][];
      ArrayResize(matrix, size);
      ArrayResize(matrix[0], size);
      
      // Initialize diagonal with 1.0
      for(int i = 0; i < size; i++) {
         for(int j = 0; j < size; j++) {
            if(i == j) {
               matrix[i][j] = 1.0;
            } else if(i < j) {
               matrix[i][j] = CalculatePairCorrelation(symbols[i], symbols[j]);
            } else {
               matrix[i][j] = matrix[j][i]; // Use symmetry
            }
         }
      }
      
      return matrix;
   }
   
   string[] FindLowCorrelationPairs(string &symbols[], double threshold = 0.3) {
      string lowCorrPairs[];
      int count = 0;
      
      for(int i = 0; i < ArraySize(symbols); i++) {
         for(int j = i + 1; j < ArraySize(symbols); j++) {
            double corr = MathAbs(CalculatePairCorrelation(symbols[i], symbols[j]));
            if(corr < threshold) {
               ArrayResize(lowCorrPairs, count + 1);
               lowCorrPairs[count] = symbols[i] + "," + symbols[j] + ":" + DoubleToString(corr, 3);
               count++;
            }
         }
      }
      
      return lowCorrPairs;
   }
   
   bool DetectCrowding(string &symbols[]) {
      if(ArraySize(symbols) < 3) return false;
      
      // Calculate average absolute correlation
      double totalCorr = 0;
      int pairs = 0;
      
      for(int i = 0; i < ArraySize(symbols); i++) {
         for(int j = i + 1; j < ArraySize(symbols); j++) {
            totalCorr += MathAbs(CalculatePairCorrelation(symbols[i], symbols[j]));
            pairs++;
         }
      }
      
      double avgCorr = totalCorr / pairs;
      
      // Crowding if average correlation > 0.6
      return avgCorr > 0.6;
   }
   
   // Advanced correlation analysis
   double CalculateRollingCorrelation(string symbol1, string symbol2, 
                                      int window = 20, int lookback = 100) {
      double rollingCorrs[];
      ArrayResize(rollingCorrs, lookback - window + 1);
      
      for(int i = 0; i < ArraySize(rollingCorrs); i++) {
         double corr = CalculatePairCorrelation(symbol1, symbol2, PERIOD_CURRENT, window);
         rollingCorrs[i] = corr;
         
         // Shift window (simplified - in reality would need to get new data)
      }
      
      // Return average of rolling correlations
      double sum = 0;
      for(int i = 0; i < ArraySize(rollingCorrs); i++) {
         sum += rollingCorrs[i];
      }
      
      return sum / ArraySize(rollingCorrs);
   }
   
   double CalculatePartialCorrelation(string symbol1, string symbol2, string controlSymbol) {
      // Calculate partial correlation between symbol1 and symbol2, controlling for controlSymbol
      double corr12 = CalculatePairCorrelation(symbol1, symbol2);
      double corr1c = CalculatePairCorrelation(symbol1, controlSymbol);
      double corr2c = CalculatePairCorrelation(symbol2, controlSymbol);
      
      // Partial correlation formula
      double numerator = corr12 - (corr1c * corr2c);
      double denominator = MathSqrt((1 - corr1c * corr1c) * (1 - corr2c * corr2c));
      
      if(denominator == 0) return 0.0;
      return numerator / denominator;
   }
   
   // Portfolio diversification metrics
   double CalculatePortfolioCorrelationScore(string &symbols[]) {
      if(ArraySize(symbols) < 2) return 1.0; // Perfect score for single symbol
      
      double totalAbsCorr = 0;
      int pairs = 0;
      
      for(int i = 0; i < ArraySize(symbols); i++) {
         for(int j = i + 1; j < ArraySize(symbols); j++) {
            totalAbsCorr += MathAbs(CalculatePairCorrelation(symbols[i], symbols[j]));
            pairs++;
         }
      }
      
      double avgCorr = totalAbsCorr / pairs;
      
      // Convert to score (0-1, higher is better)
      // Perfect diversification would have 0 average correlation
      return 1.0 - avgCorr;
   }
   
   string FindBestDiversifier(string &existingSymbols[], string &candidateSymbols[]) {
      string bestSymbol = "";
      double bestScore = -1.0;
      
      for(int i = 0; i < ArraySize(candidateSymbols); i++) {
         string candidate = candidateSymbols[i];
         
         // Skip if already in portfolio
         bool alreadyExists = false;
         for(int j = 0; j < ArraySize(existingSymbols); j++) {
            if(existingSymbols[j] == candidate) {
               alreadyExists = true;
               break;
            }
         }
         if(alreadyExists) continue;
         
         // Calculate average correlation with existing portfolio
         double totalCorr = 0;
         for(int j = 0; j < ArraySize(existingSymbols); j++) {
            totalCorr += MathAbs(CalculatePairCorrelation(candidate, existingSymbols[j]));
         }
         
         double avgCorr = totalCorr / ArraySize(existingSymbols);
         double diversificationScore = 1.0 - avgCorr;
         
         if(diversificationScore > bestScore) {
            bestScore = diversificationScore;
            bestSymbol = candidate;
         }
      }
      
      return bestSymbol;
   }
   
   // Time-based correlation analysis
   double CalculateTimeVaryingCorrelation(string symbol1, string symbol2, 
                                          ENUM_TIMEFRAMES timeframe, 
                                          int segmentSize = 50) {
      // Get longer price series
      int totalBars = 200;
      double prices1[], prices2[];
      GetPriceData(symbol1, timeframe, totalBars, prices1);
      GetPriceData(symbol2, timeframe, totalBars, prices2);
      
      // Calculate correlation for each segment
      int segments = totalBars / segmentSize;
      double segmentCorrs[];
      ArrayResize(segmentCorrs, segments);
      
      for(int s = 0; s < segments; s++) {
         int startIdx = s * segmentSize;
         double segReturns1[], segReturns2[];
         ArrayResize(segReturns1, segmentSize - 1);
         ArrayResize(segReturns2, segmentSize - 1);
         
         for(int i = 0; i < segmentSize - 1; i++) {
            int idx = startIdx + i;
            if(prices1[idx+1] != 0) segReturns1[i] = (prices1[idx] - prices1[idx+1]) / prices1[idx+1];
            if(prices2[idx+1] != 0) segReturns2[i] = (prices2[idx] - prices2[idx+1]) / prices2[idx+1];
         }
         
         segmentCorrs[s] = CalculatePearsonCorrelation(segReturns1, segReturns2);
      }
      
      // Calculate variance of correlations (measure of stability)
      return CalculateStandardDeviation(segmentCorrs);
   }
   
private:
   // Data retrieval methods
   bool GetPriceData(string symbol, ENUM_TIMEFRAMES timeframe, int bars, double &prices[]) {
      ArrayResize(prices, bars);
      
      for(int i = 0; i < bars; i++) {
         prices[i] = iClose(symbol, timeframe, i);
         if(prices[i] == 0) {
            // Try alternative price source
            prices[i] = SymbolInfoDouble(symbol, SYMBOL_BID);
            if(prices[i] == 0) {
               return false;
            }
         }
      }
      
      return true;
   }
   
   // Statistical calculation methods
   double CalculatePearsonCorrelation(const double &x[], const double &y[]) {
      int n = ArraySize(x);
      if(n != ArraySize(y) || n < 2) return 0.0;
      
      double sumX = 0, sumY = 0, sumXY = 0;
      double sumX2 = 0, sumY2 = 0;
      
      for(int i = 0; i < n; i++) {
         sumX += x[i];
         sumY += y[i];
         sumXY += x[i] * y[i];
         sumX2 += x[i] * x[i];
         sumY2 += y[i] * y[i];
      }
      
      double numerator = n * sumXY - sumX * sumY;
      double denominator = MathSqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
      
      if(denominator == 0) return 0.0;
      return numerator / denominator;
   }
   
   double CalculateSpearmanCorrelation(const double &x[], const double &y[]) {
      int n = ArraySize(x);
      if(n != ArraySize(y) || n < 2) return 0.0;
      
      // Create ranked arrays
      double rankX[], rankY[];
      ArrayResize(rankX, n);
      ArrayResize(rankY, n);
      
      // Simple ranking (ties not handled perfectly)
      for(int i = 0; i < n; i++) {
         int rank = 1;
         for(int j = 0; j < n; j++) {
            if(x[j] < x[i]) rank++;
         }
         rankX[i] = rank;
         
         rank = 1;
         for(int j = 0; j < n; j++) {
            if(y[j] < y[i]) rank++;
         }
         rankY[i] = rank;
      }
      
      // Calculate Pearson correlation on ranks
      return CalculatePearsonCorrelation(rankX, rankY);
   }
   
   double CalculateKendallTau(const double &x[], const double &y[]) {
      int n = ArraySize(x);
      if(n != ArraySize(y) || n < 2) return 0.0;
      
      int concordant = 0, discordant = 0;
      
      for(int i = 0; i < n - 1; i++) {
         for(int j = i + 1; j < n; j++) {
            double xDiff = x[i] - x[j];
            double yDiff = y[i] - y[j];
            
            if(xDiff * yDiff > 0) concordant++;
            else if(xDiff * yDiff < 0) discordant++;
            // Tie case ignored for simplicity
         }
      }
      
      int totalPairs = concordant + discordant;
      if(totalPairs == 0) return 0.0;
      
      return (double)(concordant - discordant) / totalPairs;
   }
   
   double CalculateStandardDeviation(const double &data[]) {
      int n = ArraySize(data);
      if(n < 2) return 0.0;
      
      double sum = 0, sumSq = 0;
      for(int i = 0; i < n; i++) {
         sum += data[i];
         sumSq += data[i] * data[i];
      }
      
      double mean = sum / n;
      double variance = (sumSq / n) - (mean * mean);
      
      return MathSqrt(MathMax(variance, 0));
   }
   
   // Matrix operations for portfolio optimization
   double[] CalculateEigenvalues(const double &matrix[][]) {
      int size = ArrayRange(matrix, 0);
      double eigenvalues[];
      ArrayResize(eigenvalues, size);
      
      // Simplified eigenvalue calculation
      // In production, use a proper linear algebra library
      for(int i = 0; i < size; i++) {
         eigenvalues[i] = 1.0; // Placeholder
      }
      
      return eigenvalues;
   }
   
   double CalculateConditionNumber(const double &matrix[][]) {
      // Condition number for stability analysis
      double eigenvalues[] = CalculateEigenvalues(matrix);
      if(ArraySize(eigenvalues) < 2) return 1.0;
      
      double maxEigen = eigenvalues[0];
      double minEigen = eigenvalues[0];
      
      for(int i = 1; i < ArraySize(eigenvalues); i++) {
         if(eigenvalues[i] > maxEigen) maxEigen = eigenvalues[i];
         if(eigenvalues[i] < minEigen) minEigen = eigenvalues[i];
      }
      
      if(minEigen == 0) return 1000.0; // Very ill-conditioned
      return maxEigen / minEigen;
   }
   
   // Utility methods
   bool IsStationary(const double &returns[], double threshold = 0.05) {
      // Simple stationarity test using variance ratio
      int n = ArraySize(returns);
      if(n < 20) return true;
      
      // Calculate variance of returns
      double varFull = CalculateVariance(returns);
      
      // Split into two halves
      int half = n / 2;
      double firstHalf[], secondHalf[];
      ArrayResize(firstHalf, half);
      ArrayResize(secondHalf, n - half);
      
      ArrayCopy(firstHalf, returns, 0, 0, half);
      ArrayCopy(secondHalf, returns, 0, half, n - half);
      
      double varFirst = CalculateVariance(firstHalf);
      double varSecond = CalculateVariance(secondHalf);
      
      // Check if variances are similar
      double varRatio = MathMax(varFirst, varSecond) / MathMin(varFirst, varSecond);
      return varRatio < (1 + threshold);
   }
   
   double CalculateVariance(const double &data[]) {
      int n = ArraySize(data);
      if(n < 2) return 0.0;
      
      double sum = 0, sumSq = 0;
      for(int i = 0; i < n; i++) {
         sum += data[i];
         sumSq += data[i] * data[i];
      }
      
      double mean = sum / n;
      return (sumSq / n) - (mean * mean);
   }
};