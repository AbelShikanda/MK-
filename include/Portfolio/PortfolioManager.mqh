//+------------------------------------------------------------------+
//|                                               PortfolioManager.mqh |
//|                                    Portfolio Management System    |
//+------------------------------------------------------------------+
#include "SymbolManager.mqh"
#include "CorrelationEngine.mqh"
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Decision Structures                                             |
//+------------------------------------------------------------------+
enum ENUM_DECISION_TYPE {
   DECISION_BUY,
   DECISION_SELL,
   DECISION_HOLD
};

struct Decision {
   string symbol;
   ENUM_DECISION_TYPE type;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double confidence;
   datetime timestamp;
   string signalSource;
};

struct FilterDecision {
   Decision decision;
   bool isValid;
   string reason;
   double adjustedLotSize;
   double positionScore;
};

//+------------------------------------------------------------------+
//| Portfolio Manager Class                                         |
//+------------------------------------------------------------------+
class PortfolioManager {
private:
   string m_currentSymbols[];
   double m_symbolWeights[];
   double m_correlationMatrix[][];
   double m_riskBudget;
   int m_maxPositions;
   double m_currentRisk;
   SymbolManager* m_symbolManager;
   CorrelationEngine* m_correlationEngine;
   CPositionInfo m_positionInfo;
   
   // Risk metrics
   double m_dailyPnL;
   double m_maxDrawdown;
   double m_sharpeRatio;
   
public:
   // Constructor/Destructor
   PortfolioManager() {
      m_riskBudget = 5.0; // Default 5% portfolio risk
      m_maxPositions = 5;
      m_currentRisk = 0.0;
      m_dailyPnL = 0.0;
      m_maxDrawdown = 0.0;
      m_sharpeRatio = 0.0;
      
      m_symbolManager = new SymbolManager();
      m_correlationEngine = new CorrelationEngine();
      
      ArrayResize(m_currentSymbols, 0);
      ArrayResize(m_symbolWeights, 0);
   }
   
   ~PortfolioManager() {
      delete m_symbolManager;
      delete m_correlationEngine;
   }
   
   // Main interface methods
   FilterDecision FilterDecision(const Decision &decision) {
      FilterDecision filtered;
      filtered.decision = decision;
      filtered.isValid = true;
      filtered.reason = "Decision accepted";
      
      // 1. Check max positions
      if(ArraySize(m_currentSymbols) >= m_maxPositions) {
         filtered.isValid = false;
         filtered.reason = "Maximum positions reached: " + IntegerToString(m_maxPositions);
         return filtered;
      }
      
      // 2. Check if symbol already in portfolio
      if(IsSymbolInPortfolio(decision.symbol)) {
         filtered.isValid = false;
         filtered.reason = "Symbol " + decision.symbol + " already in portfolio";
         return filtered;
      }
      
      // 3. Check correlation with existing positions
      if(EnableCorrelationFilter) {
         double maxCorr = GetMaxCorrelationWithPortfolio(decision.symbol);
         if(maxCorr > MaxCorrelation) {
            filtered.isValid = false;
            filtered.reason = StringFormat("High correlation (%.2f) with portfolio", maxCorr);
            return filtered;
         }
      }
      
      // 4. Calculate position size based on risk
      filtered.adjustedLotSize = CalculatePositionSize(decision);
      
      // 5. Calculate position score (for allocation optimization)
      filtered.positionScore = CalculatePositionScore(decision, filtered.adjustedLotSize);
      
      return filtered;
   }
   
   double CalculatePositionSize(const Decision &decision) {
      // Use the provided mathutils function
      #ifdef __MATHUTILS__
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return CalculatePositionSizeByRisk(
         decision.symbol,
         decision.entryPrice,
         decision.stopLoss,
         RiskPerTrade,
         accountBalance
      );
      #else
      // Fallback implementation
      double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPerTrade / 100.0);
      double stopLossDistance = MathAbs(decision.entryPrice - decision.stopLoss);
      double stopLossPips = PriceToPips(decision.symbol, stopLossDistance);
      double pipValue = CalculatePipValue(decision.symbol);
      
      if(stopLossPips <= 0 || pipValue <= 0) return 0.01;
      
      double positionSize = riskAmount / (stopLossPips * pipValue);
      positionSize = NormalizeLotSize(decision.symbol, positionSize);
      
      // Ensure within symbol limits
      double lotMin = SymbolInfoDouble(decision.symbol, SYMBOL_VOLUME_MIN);
      double lotMax = SymbolInfoDouble(decision.symbol, SYMBOL_VOLUME_MAX);
      positionSize = MathMax(lotMin, MathMin(lotMax, positionSize));
      
      return positionSize;
      #endif
   }
   
   void OptimizeAllocation() {
      // Update correlation matrix
      string symbols[];
      GetCurrentPortfolioSymbols(symbols);
      if(ArraySize(symbols) > 0) {
         m_correlationMatrix = m_correlationEngine.BuildCorrelationMatrix(symbols);
      }
      
      // Calculate current weights
      CalculateCurrentWeights();
      
      // Check for rebalancing needs
      if(ShouldRebalance()) {
         Rebalance();
      }
      
      // Check for risk concentration
      if(IsRiskConcentrated()) {
         AdjustForRiskConcentration();
      }
      
      Log("PortfolioManager", "Allocation optimization completed");
   }
   
   void Rebalance() {
      Log("PortfolioManager", "Starting portfolio rebalance");
      
      // 1. Close positions that no longer meet criteria
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            // Check if position should be closed
            if(ShouldClosePosition(symbol, profit)) {
               ClosePosition(ticket, symbol);
               RemoveSymbolFromPortfolio(symbol);
            }
         }
      }
      
      // 2. Adjust existing positions to target weights
      AdjustPositionsToTargetWeights();
      
      // 3. Update portfolio metrics
      UpdatePortfolioMetrics();
      
      Log("PortfolioManager", "Portfolio rebalance completed");
   }
   
   // Configuration methods
   void SetRiskBudget(double riskPercent) { m_riskBudget = riskPercent; }
   void SetMaxPositions(int maxPos) { m_maxPositions = maxPos; }
   double GetCurrentRisk() const { return m_currentRisk; }
   int GetCurrentPositions() const { return ArraySize(m_currentSymbols); }
   
   // Portfolio analysis methods
   double CalculatePortfolioVolatility() {
      if(ArraySize(m_currentSymbols) == 0) return 0.0;
      
      double totalVolatility = 0.0;
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         double atr = CalculateATR(m_currentSymbols[i], PERIOD_D1, 14);
         double symbolVolatility = atr / SymbolInfoDouble(m_currentSymbols[i], SYMBOL_BID);
         totalVolatility += symbolVolatility * m_symbolWeights[i];
      }
      
      return totalVolatility;
   }
   
   double CalculatePortfolioBeta() {
      // Simplified beta calculation (would need benchmark data)
      // For now, return average correlation to USD basket
      if(ArraySize(m_currentSymbols) == 0) return 1.0;
      
      double totalBeta = 0.0;
      int count = 0;
      
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         // Check correlation with USD index
         string usdPairs[] = {"EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDJPY", "USDCAD", "USDCHF"};
         for(int j = 0; j < ArraySize(usdPairs); j++) {
            if(StringFind(m_currentSymbols[i], "USD") >= 0) {
               double corr = m_correlationEngine.CalculatePairCorrelation(m_currentSymbols[i], usdPairs[j]);
               totalBeta += corr;
               count++;
               break;
            }
         }
      }
      
      return count > 0 ? totalBeta / count : 1.0;
   }
   
private:
   // Helper methods
   bool IsSymbolInPortfolio(const string symbol) {
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         if(m_currentSymbols[i] == symbol) return true;
      }
      return false;
   }
   
   double GetMaxCorrelationWithPortfolio(const string symbol) {
      double maxCorr = 0.0;
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         double corr = MathAbs(m_correlationEngine.CalculatePairCorrelation(symbol, m_currentSymbols[i]));
         if(corr > maxCorr) maxCorr = corr;
      }
      return maxCorr;
   }
   
   void CalculateCurrentWeights() {
      int size = ArraySize(m_currentSymbols);
      ArrayResize(m_symbolWeights, size);
      
      if(size == 0) return;
      
      double totalEquity = 0.0;
      double equityValues[];
      ArrayResize(equityValues, size);
      
      // Calculate equity for each position
      for(int i = 0; i < size; i++) {
         equityValues[i] = GetPositionEquity(m_currentSymbols[i]);
         totalEquity += equityValues[i];
      }
      
      // Calculate weights
      if(totalEquity > 0) {
         for(int i = 0; i < size; i++) {
            m_symbolWeights[i] = equityValues[i] / totalEquity;
         }
      }
   }
   
   double GetPositionEquity(const string symbol) {
      for(int i = 0; i < PositionsTotal(); i++) {
         if(PositionGetSymbol(i) == symbol) {
            return PositionGetDouble(POSITION_VOLUME) * PositionGetDouble(POSITION_PRICE_CURRENT);
         }
      }
      return 0.0;
   }
   
   bool ShouldRebalance() {
      // Check if any position is outside its target weight range
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         double targetWeight = 1.0 / ArraySize(m_currentSymbols); // Equal weight target
         if(MathAbs(m_symbolWeights[i] - targetWeight) > 0.1) { // 10% threshold
            return true;
         }
      }
      return false;
   }
   
   bool IsRiskConcentrated() {
      if(ArraySize(m_symbolWeights) == 0) return false;
      
      // Check if any single position exceeds 30% of portfolio
      for(int i = 0; i < ArraySize(m_symbolWeights); i++) {
         if(m_symbolWeights[i] > 0.3) return true;
      }
      
      // Check if top 2 positions exceed 50%
      if(ArraySize(m_symbolWeights) >= 2) {
         double sortedWeights[];
         ArrayCopy(sortedWeights, m_symbolWeights);
         ArraySort(sortedWeights);
         ArrayReverse(sortedWeights);
         
         if(sortedWeights[0] + sortedWeights[1] > 0.5) return true;
      }
      
      return false;
   }
   
   double CalculatePositionScore(const Decision &decision, double lotSize) {
      double score = 0.0;
      
      // 1. Confidence factor (0-1)
      score += decision.confidence * 0.4;
      
      // 2. Risk-reward ratio factor
      double rrRatio = CalculateRiskRewardRatio(decision.entryPrice, decision.stopLoss, decision.takeProfit);
      score += MathMin(rrRatio / 3.0, 1.0) * 0.3; // Normalize to 0-1
      
      // 3. Volatility factor (prefer moderate volatility)
      double atr = CalculateATR(decision.symbol, PERIOD_D1, 14);
      double dailyVolatility = atr / decision.entryPrice;
      if(dailyVolatility > 0.005 && dailyVolatility < 0.02) { // 0.5% to 2% daily range
         score += 0.2;
      }
      
      // 4. Correlation diversification factor
      double maxCorr = GetMaxCorrelationWithPortfolio(decision.symbol);
      score += (1.0 - maxCorr) * 0.1;
      
      return score;
   }
   
   bool ShouldClosePosition(const string symbol, double profit) {
      // Check stop loss/take profit (handled by broker)
      // Check if position has been open too long
      for(int i = 0; i < PositionsTotal(); i++) {
         if(PositionGetSymbol(i) == symbol) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            datetime currentTime = TimeCurrent();
            int hoursOpen = (int)((currentTime - openTime) / 3600);
            
            // Close if open more than 5 days for day trading
            if(hoursOpen > 120) return true;
            
            // Check trailing stop
            if(profit > 0) {
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
               double trailingStopPips = 50; // 50 pips trailing stop
               
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  double distance = PipsToPrice(symbol, trailingStopPips);
                  if(currentPrice < openPrice + distance) return true;
               } else {
                  double distance = PipsToPrice(symbol, trailingStopPips);
                  if(currentPrice > openPrice - distance) return true;
               }
            }
         }
      }
      return false;
   }
   
   void ClosePosition(ulong ticket, const string symbol) {
      trade.PositionClose(ticket);
      LogTrade("PortfolioManager", symbol, "CLOSE", 0);
   }
   
   void RemoveSymbolFromPortfolio(const string symbol) {
      int newSize = 0;
      string tempSymbols[];
      ArrayResize(tempSymbols, ArraySize(m_currentSymbols));
      
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         if(m_currentSymbols[i] != symbol) {
            tempSymbols[newSize] = m_currentSymbols[i];
            newSize++;
         }
      }
      
      ArrayResize(m_currentSymbols, newSize);
      ArrayCopy(m_currentSymbols, tempSymbols, 0, 0, newSize);
   }
   
   void AdjustPositionsToTargetWeights() {
      // Calculate target equity per position
      double totalEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double targetEquityPerPos = totalEquity / m_maxPositions;
      
      // Adjust existing positions
      for(int i = 0; i < ArraySize(m_currentSymbols); i++) {
         double currentEquity = GetPositionEquity(m_currentSymbols[i]);
         double adjustmentRatio = targetEquityPerPos / currentEquity;
         
         if(MathAbs(1.0 - adjustmentRatio) > 0.1) { // More than 10% difference
            AdjustPositionSize(m_currentSymbols[i], adjustmentRatio);
         }
      }
   }
   
   void AdjustPositionSize(const string symbol, double ratio) {
      for(int i = 0; i < PositionsTotal(); i++) {
         if(PositionGetSymbol(i) == symbol) {
            ulong ticket = PositionGetTicket(i);
            double currentVolume = PositionGetDouble(POSITION_VOLUME);
            double newVolume = currentVolume * ratio;
            
            // Normalize and adjust
            newVolume = NormalizeLotSize(symbol, newVolume);
            
            if(newVolume != currentVolume) {
               trade.PositionClosePartial(ticket, newVolume);
               Log("PortfolioManager", StringFormat("Adjusted %s position: %.2f -> %.2f lots", 
                  symbol, currentVolume, newVolume));
            }
            break;
         }
      }
   }
   
   void AdjustForRiskConcentration() {
      // Reduce size of largest positions
      int size = ArraySize(m_symbolWeights);
      if(size < 2) return;
      
      // Find largest position
      int maxIndex = 0;
      for(int i = 1; i < size; i++) {
         if(m_symbolWeights[i] > m_symbolWeights[maxIndex]) {
            maxIndex = i;
         }
      }
      
      // Reduce by 25%
      AdjustPositionSize(m_currentSymbols[maxIndex], 0.75);
      Log("PortfolioManager", StringFormat("Reduced %s position due to concentration risk", 
         m_currentSymbols[maxIndex]));
   }
   
   void UpdatePortfolioMetrics() {
      m_currentRisk = CalculatePortfolioVolatility() * 100; // Convert to percentage
      m_dailyPnL = CalculateDailyPnL();
      
      // Update max drawdown
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double peakEquity = AccountInfoDouble(ACCOUNT_BALANCE); // Simplified
      double drawdown = (peakEquity - currentEquity) / peakEquity * 100;
      if(drawdown > m_maxDrawdown) m_maxDrawdown = drawdown;
      
      // Update Sharpe ratio (simplified)
      if(m_currentRisk > 0) {
         m_sharpeRatio = (m_dailyPnL / 100) / (m_currentRisk / 100);
      }
   }
   
   double CalculateDailyPnL() {
      double dailyPnL = 0.0;
      datetime today = TimeCurrent();
      MqlDateTime todayStruct;
      TimeToStruct(today, todayStruct);
      todayStruct.hour = 0;
      todayStruct.min = 0;
      todayStruct.sec = 0;
      datetime dayStart = StructToTime(todayStruct);
      
      // Check positions opened today
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime >= dayStart) {
               dailyPnL += PositionGetDouble(POSITION_PROFIT);
            }
         }
      }
      
      return dailyPnL;
   }
   
   void GetCurrentPortfolioSymbols(string &symbols[]) {
      ArrayResize(symbols, ArraySize(m_currentSymbols));
      ArrayCopy(symbols, m_currentSymbols);
   }
};