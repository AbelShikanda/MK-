//+------------------------------------------------------------------+
//|                                                       MarketData |
//|                        Core market data access and manipulation  |
//+------------------------------------------------------------------+
class MarketData
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   MqlTick m_lastTick;
   datetime m_lastUpdate;
   
public:
   // Constructor
   MarketData(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
   {
      m_symbol = (symbol == NULL) ? Symbol() : symbol;
      m_timeframe = (timeframe == PERIOD_CURRENT) ? Period() : timeframe;
      m_lastUpdate = 0;
   }
   
   // Get bid price
   double GetBid(string symbol = NULL)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      return SymbolInfoDouble(sym, SYMBOL_BID);
   }
   
   // Get ask price
   double GetAsk(string symbol = NULL)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      return SymbolInfoDouble(sym, SYMBOL_ASK);
   }
   
   // Get spread in points
   double GetSpread(string symbol = NULL)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      return SymbolInfoInteger(sym, SYMBOL_SPREAD);
   }
   
   // Get current tick data
   MqlTick GetTick(string symbol = NULL)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      MqlTick tick;
      if(SymbolInfoTick(sym, tick))
      {
         m_lastTick = tick;
         m_lastUpdate = TimeCurrent();
      }
      return m_lastTick;
   }
   
   // Get OHLC data for specified bar
   bool GetOHLC(string symbol, ENUM_TIMEFRAMES timeframe, int shift, 
                double &open, double &high, double &low, double &close)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? m_timeframe : timeframe;
      
      open = iOpen(sym, tf, shift);
      high = iHigh(sym, tf, shift);
      low = iLow(sym, tf, shift);
      close = iClose(sym, tf, shift);
      
      return (open > 0 && high > 0 && low > 0 && close > 0);
   }
   
   // Get volume for specified bar
   long GetVolume(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, int shift = 0)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? m_timeframe : timeframe;
      return iVolume(sym, tf, shift);
   }
   
   // Get current volume
   long GetVolume(string symbol = NULL)
   {
      string sym = (symbol == NULL) ? m_symbol : symbol;
      return GetVolume(sym, m_timeframe, 0);
   }
   
   // Check if market data is fresh
   bool IsFresh()
   {
      return (TimeCurrent() - m_lastUpdate) <= 1;
   }
   
   // Refresh tick data
   void Refresh()
   {
      GetTick(m_symbol);
   }
};