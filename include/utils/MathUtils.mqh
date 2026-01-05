// MathUtils.mqh - Complete Trading Math Utilities
class MathUtils
{
public:
    // ============ PRICE AND PIP CONVERSIONS ============
    
    // Convert pips to price value
    static double PipsToPrice(string symbol, double pips)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // For 5-digit brokers, 1 pip = 10 points
        // For 4-digit brokers, 1 pip = 1 point
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
        
        return pips * pipValue;
    }
    
    // Convert price difference to pips
    static double PriceToPips(string symbol, double price)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // For 5-digit brokers, 1 pip = 10 points
        // For 4-digit brokers, 1 pip = 1 point
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
        
        if(pipValue != 0)
            return price / pipValue;
        
        return 0;
    }
    
    // Calculate pip value for a symbol (superior version)
    static double CalculatePipValue(string symbol)
    {
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if (point == 0) return 0;
        
        // For 5-digit brokers, 1 pip = 10 points
        double pipSize = (SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || 
                         SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3) ? point * 10 : point;
        
        return tickValue * (pipSize / tickSize);
    }
    
    // ============ POSITION CALCULATIONS ============
    
    // Calculate risk amount for a position
    static double CalculatePositionRisk(string symbol, double entryPrice, 
                                       double stopLoss, double lotSize)
    {
        // Get the tick value for the symbol (value per 1 lot per 1 point)
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // Calculate stop distance in points
        double stopDistance = MathAbs(entryPrice - stopLoss);
        double points = stopDistance / point;
        
        // Calculate risk: points × tick value × lot size
        return points * tickValue * lotSize;
    }
    
    // Calculate R:R for a position
    static double CalculateRiskRewardRatio(double entryPrice, double stopLoss, 
                                          double takeProfit)
    {
        double risk = MathAbs(entryPrice - stopLoss);
        double reward = MathAbs(takeProfit - entryPrice);
        
        if(risk == 0)
            return 0;
        
        return reward / risk;
    }
    
    // ============ PERCENTAGE CALCULATIONS ============
    
    // Calculate % change between values
    static double CalculatePercentageChange(double oldValue, double newValue)
    {
        if(oldValue == 0)
            return 0;
        
        return ((newValue - oldValue) / oldValue) * 100;
    }
    
    // Get value from percentage
    static double CalculateValueFromPercentage(double baseValue, double percentage)
    {
        return baseValue * (percentage / 100);
    }
    
    // Get percentage of value
    static double CalculatePercentageOfValue(double part, double whole)
    {
        if(whole == 0)
            return 0;
        
        return (part / whole) * 100;
    }
    
    // ============ AVERAGE CALCULATIONS ============
    
    // Calculate SMA of values
    static double CalculateSimpleMovingAverage(const double &values[], int period)
    {
        if(ArraySize(values) < period || period <= 0)
            return 0;
        
        double sum = 0;
        int count = MathMin(period, ArraySize(values));
        
        for(int i = 0; i < count; i++)
            sum += values[i];
        
        return sum / count;
    }
    
    // Calculate weighted average
    static double CalculateWeightedAverage(const double &values[], const double &weights[])
    {
        if(ArraySize(values) != ArraySize(weights))
            return 0;
        
        double weightedSum = 0;
        double weightSum = 0;
        
        for(int i = 0; i < ArraySize(values); i++)
        {
            weightedSum += values[i] * weights[i];
            weightSum += weights[i];
        }
        
        if(weightSum == 0)
            return 0;
        
        return weightedSum / weightSum;
    }
    
    // Calculate Average True Range (superior version - uses indicator)
    static double CalculateATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift = 0)
    {
        double atrValues[];
        ArraySetAsSeries(atrValues, true);
        
        int handle = iATR(symbol, timeframe, period);
        if (handle == INVALID_HANDLE) return 0;
        
        if (CopyBuffer(handle, 0, shift, 1, atrValues) < 1)
        {
            IndicatorRelease(handle);
            return 0;
        }
        
        IndicatorRelease(handle);
        return atrValues[0];
    }
    
    // Calculate Standard Deviation (superior version)
    static double CalculateStandardDeviation(const double &data[])
    {
        int size = ArraySize(data);
        if (size == 0) return 0;
        
        double sum = 0;
        double mean = 0;
        
        // Calculate mean
        for (int i = 0; i < size; i++)
            sum += data[i];
        mean = sum / size;
        
        // Calculate variance
        double variance = 0;
        for (int i = 0; i < size; i++)
            variance += MathPow(data[i] - mean, 2);
        variance /= size;
        
        return MathSqrt(variance);
    }
    
    // ============ DISTANCE CALCULATIONS ============
    
    // Distance between two prices in pips
    static double CalculateDistanceInPips(string symbol, double price1, double price2)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        double distance = MathAbs(price1 - price2);
        double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
        
        if(pipValue != 0)
            return distance / pipValue;
        
        return 0;
    }
    
    // Distance as % of price
    static double CalculateDistanceAsPercentage(double price1, double price2, double referencePrice)
    {
        if(referencePrice == 0)
            return 0;
        
        double distance = MathAbs(price1 - price2);
        return (distance / referencePrice) * 100;
    }
    
    // ============ NORMALIZATION FUNCTIONS ============
    
    // Normalize price to symbol digits (keeping simpler version)
    static double NormalizePrice(string symbol, double price)
    {
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        return NormalizeDouble(price, digits);
    }
    
    // Normalize price to symbol's tick size (superior version - more precise)
    static double NormalizePriceToTick(string symbol, double price)
    {
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        if (tickSize == 0) return price;
        
        return NormalizeDouble(MathRound(price / tickSize) * tickSize, 
                              (int)MathMax(-MathLog10(tickSize), 0));
    }
    
    // Normalize lot size to symbol constraints (keeping more complete version)
    static double NormalizeLotSize(string symbol, double lotSize)
    {
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        // Apply minimum and maximum
        lotSize = MathMax(lotSize, minLot);
        lotSize = MathMin(lotSize, maxLot);
        
        // Adjust to lot step
        if(lotStep > 0)
            lotSize = MathRound(lotSize / lotStep) * lotStep;
        
        return NormalizeDouble(lotSize, 2);
    }
   
   // Normalize market score
   static double NormalizeScore(int bullish_tf_count, int bearish_tf_count, 
                                double rsi, double atr, int total_tf_count)
   {
      double score = 0.5;
      
      // Trend alignment contribution (40%)
      double trend_score = 0.0;
      if(bullish_tf_count > bearish_tf_count)
         trend_score = (double)bullish_tf_count / total_tf_count;
      else if(bearish_tf_count > bullish_tf_count)
         trend_score = -(double)bearish_tf_count / total_tf_count;
      
      score += trend_score * 0.4;
      
      // RSI contribution (30%)
      double rsi_score = 0.0;
      if(rsi > 50) rsi_score = (rsi - 50) / 50.0; // 0 to 1 for bullish
      else rsi_score = -(50 - rsi) / 50.0; // -1 to 0 for bearish
      
      score += rsi_score * 0.3;
      
      // ATR volatility adjustment (30% - lower volatility = more confident)
      double atr_score = 1.0 - MathMin(atr / (100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)), 1.0);
      score *= atr_score;
      
      return MathMax(0.0, MathMin(1.0, score));
   }
    
    // ============ PROFIT CALCULATIONS ============
    
    // Calculate profit/loss in pips
    static double CalculateProfitInPips(string symbol, double entryPrice, 
                                       double exitPrice, bool isBuy)
    {
        double profit = 0;
        
        if(isBuy)
            profit = exitPrice - entryPrice;
        else
            profit = entryPrice - exitPrice;
        
        return PriceToPips(symbol, profit);
    }
    
    // Calculate profit/loss in money
    static double CalculateProfitInMoney(string symbol, double entryPrice, 
                                        double exitPrice, double lotSize, bool isBuy)
    {
        double profitInPips = CalculateProfitInPips(symbol, entryPrice, exitPrice, isBuy);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double pipValue = tickValue * lotSize;
        
        return profitInPips * pipValue;
    }
    
    // ============ PROBABILITY CALCULATIONS ============
    
    // Calculate win probability from stats
    static double CalculateWinProbability(int totalTrades, int winningTrades)
    {
        if(totalTrades == 0)
            return 0;
        
        return (double)winningTrades / totalTrades * 100;
    }
    
    // Calculate expected value of a trade
    static double CalculateExpectedValue(double winRatePercent, double avgWin, double avgLoss)
    {
        double winRate = winRatePercent / 100;
        double lossRate = 1 - winRate;
        
        return (winRate * avgWin) - (lossRate * avgLoss);
    }
    
    // ============ MONEY MANAGEMENT CALCULATIONS ============
    
    // Calculate optimal position size using Kelly Criterion
    static double CalculateKellyCriterion(double winRatePercent, double avgWinToLossRatio)
    {
        double winRate = winRatePercent / 100;
        double lossRate = 1 - winRate;
        
        // Kelly Criterion formula: f* = (bp - q) / b
        // where: b = avgWin/avgLoss, p = winRate, q = lossRate
        double b = avgWinToLossRatio;
        double p = winRate;
        double q = lossRate;
        
        if(b == 0)
            return 0;
        
        double kelly = (b * p - q) / b;
        
        // Typically use half-Kelly for safety
        return MathMax(kelly * 0.5, 0);
    }
    
    // ============ GEOMETRIC CALCULATIONS ============
    
    // Calculate Fibonacci retracement level
    static double CalculateFibonacciLevel(double high, double low, double level)
    {
        double range = high - low;
        return low + (range * level);
    }
    
    // Calculate geometric mean of values
    static double CalculateGeometricMean(const double &values[])
    {
        if(ArraySize(values) == 0)
            return 0;
        
        double product = 1;
        for(int i = 0; i < ArraySize(values); i++)
        {
            if(values[i] <= 0)
                return 0;
            product *= values[i];
        }
        
        return MathPow(product, 1.0 / ArraySize(values));
    }
    
    // ============ TIME-BASED CALCULATIONS ============
    
    // Calculate annualized return %
    static double CalculateAnnualizedReturn(double totalReturnPercent, double days)
    {
        if(days == 0)
            return 0;
        
        double totalReturn = totalReturnPercent / 100;
        double years = days / 365.25;
        
        return (MathPow(1 + totalReturn, 1 / years) - 1) * 100;
    }
    
    // Calculate compounded growth
    static double CalculateCompoundedGrowth(double initialAmount, double ratePercent, 
                                           int periods)
    {
        double rate = ratePercent / 100;
        return initialAmount * MathPow(1 + rate, periods);
    }
    
    // ============ VALIDATION FUNCTIONS ============
    
    // Check if price is valid for symbol
    static bool IsValidPrice(string symbol, double price)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(tickSize > 0)
        {
            double normalized = MathRound(price / tickSize) * tickSize;
            return MathAbs(price - normalized) < (point / 2);
        }
        
        return true;
    }
    
    // Check if lot size is valid for symbol
    static bool IsValidLotSize(string symbol, double lotSize)
    {
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        // Check min/max
        if(lotSize < minLot || lotSize > maxLot)
            return false;
        
        // Check step
        if(lotStep > 0)
        {
            double steps = lotSize / lotStep;
            if(MathAbs(steps - MathRound(steps)) > 0.0001)
                return false;
        }
        
        return true;
    }
    
    // ============ HELPER/UTILITY FUNCTIONS ============
    
    // Calculate position size based on risk percentage (requires account balance)
    static double CalculatePositionSizeByRisk(string symbol, double entryPrice, 
                                            double stopLoss, double riskPercent, 
                                            double accountBalance)
    {
        double riskAmount = accountBalance * (riskPercent / 100);
        double riskPerLot = CalculatePositionRisk(symbol, entryPrice, stopLoss, 1.0);
        
        if(riskPerLot == 0)
            return 0;
        
        double lotSize = riskAmount / riskPerLot;
        
        return NormalizeLotSize(symbol, lotSize);
    }

    // Calculate position size based on ATR
    static double CalculatePositionSizeByATR(const string symbol, double atr, 
                                                double risk_percent, double stop_loss_pips)
    {
        double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_amount = account_balance * (risk_percent / 100.0);
        
        // Convert ATR to pips
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double atr_pips = atr / point;
        
        // Ensure stop loss is at least 1 ATR
        if(stop_loss_pips < atr_pips)
            stop_loss_pips = atr_pips;
        
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double position_size = risk_amount / (stop_loss_pips * tick_value);
        
        // Normalize to allowed lot sizes
        double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        position_size = MathMax(position_size, min_lot);
        position_size = MathMin(position_size, max_lot);
        position_size = MathRound(position_size / lot_step) * lot_step;
        
        return position_size;
    }
    
    // Calculate breakeven point including spread
    static double CalculateBreakevenPrice(double entryPrice, bool isBuy, double spreadPips)
    {
        double spreadPrice = PipsToPrice(_Symbol, spreadPips);
        
        if(isBuy)
            return entryPrice + spreadPrice;  // BUY: need price to move up by spread
        else
            return entryPrice - spreadPrice;  // SELL: need price to move down by spread
    }
    
    // Calculate margin required for a position
    static double CalculateMarginRequired(string symbol, double lotSize, int orderType = ORDER_TYPE_BUY)
    {
        double margin = 0;
        double price = (orderType == ORDER_TYPE_BUY) ? 
                    SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                    SymbolInfoDouble(symbol, SYMBOL_BID);
        
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
        
        if(leverage > 0)
            margin = (contractSize * lotSize * price) / leverage;
        
        return margin;
    }
    
    // Calculate swap for a position
    static double CalculateSwap(string symbol, double lotSize, int orderType, int days = 1)
    {
        double swap = 0;
        double swapLong = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
        double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
        
        if(orderType == ORDER_TYPE_BUY)
            swap = swapLong * lotSize * days;
        else if(orderType == ORDER_TYPE_SELL)
            swap = swapShort * lotSize * days;
        
        return swap;
    }
    
    // Round to nearest tick size
    static double RoundToTick(string symbol, double value)
    {
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        if(tickSize <= 0) return value;
        
        return MathRound(value / tickSize) * tickSize;
    }
    
    // Calculate commission for a trade
    static double CalculateCommission(string symbol, double lotSize, double commissionPerLot = 0)
    {
        // If commission not specified, try to get from symbol
        if(commissionPerLot == 0)
        {
            // Some brokers provide commission info
            // This is broker-specific
        }
        
        return commissionPerLot * lotSize;
    }
    
    // Calculate total cost of trade (spread + commission)
    static double CalculateTotalTradeCost(string symbol, double lotSize, bool isBuy, 
                                         double commissionPerLot = 0)
    {
        double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        double spreadCost = CalculateProfitInMoney(symbol, 
            SymbolInfoDouble(symbol, SYMBOL_BID),
            SymbolInfoDouble(symbol, SYMBOL_ASK),
            lotSize, isBuy);
        
        double commission = CalculateCommission(symbol, lotSize, commissionPerLot);
        
        return spreadCost + commission;
    }
};