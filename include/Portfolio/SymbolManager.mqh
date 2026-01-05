//+------------------------------------------------------------------+
//|                                                   SymbolManager.mqh |
//|                                       Symbol Management System    |
//+------------------------------------------------------------------+
#include "CorrelationEngine.mqh"

//+------------------------------------------------------------------+
//| Symbol Properties Structure                                     |
//+------------------------------------------------------------------+
struct SymbolProperties {
   string symbol;
   double spread;
   double swapLong;
   double swapShort;
   double commission;
   double marginRequired;
   int digits;
   double point;
   double tickSize;
   double lotMin;
   double lotMax;
   double lotStep;
   double contractSize;
   ENUM_SYMBOL_TRADE_MODE tradeMode;
   ENUM_SYMBOL_TRADE_EXECUTION executionMode;
   datetime sessionStart;
   datetime sessionEnd;
};

//+------------------------------------------------------------------+
//| Validation Rules Structure                                       |
//+------------------------------------------------------------------+
struct ValidationRules {
   double minSpread;
   double maxSpread;
   double minVolume;
   double maxSwap;
   int minDigits;
   bool allowHedging;
   bool allowNetting;
   string allowedSessions[];
};

//+------------------------------------------------------------------+
//| Symbol Manager Class                                            |
//+------------------------------------------------------------------+
class SymbolManager {
private:
   string m_tradableSymbols[];
   SymbolProperties m_symbolProperties[];
   ValidationRules m_validationRules;
   CorrelationEngine* m_correlationEngine;
   
public:
   SymbolManager() {
      m_correlationEngine = new CorrelationEngine();
      InitializeValidationRules();
      RefreshTradableSymbols();
   }
   
   ~SymbolManager() {
      delete m_correlationEngine;
   }
   
   // Main interface methods
   string[] GetTradableSymbols() {
      RefreshTradableSymbols();
      string filteredSymbols[];
      ArrayResize(filteredSymbols, ArraySize(m_tradableSymbols));
      ArrayCopy(filteredSymbols, m_tradableSymbols);
      return filteredSymbols;
   }
   
   SymbolInfo GetSymbolInfo(const string symbol) {
      SymbolInfo info;
      info.symbol = symbol;
      info.bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      info.ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      info.spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      info.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      info.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      info.tradeMode = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      info.lotMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      info.lotMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      info.lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      // Additional calculated properties
      info.tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      info.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      info.marginInitial = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
      info.marginMaintenance = SymbolInfoDouble(symbol, SYMBOL_MARGIN_MAINTENANCE);
      
      // Session times
      info.sessionStart = (datetime)SymbolInfoInteger(symbol, SYMBOL_SESSION_START);
      info.sessionEnd = (datetime)SymbolInfoInteger(symbol, SYMBOL_SESSION_END);
      
      return info;
   }
   
   double CalculateCorrelation(string symbol1, string symbol2, 
                               ENUM_TIMEFRAMES timeframe = PERIOD_H1, 
                               int period = 20) {
      return m_correlationEngine.CalculatePairCorrelation(symbol1, symbol2, timeframe, period);
   }
   
   string[] FilterByCriteria(const string criteria) {
      string filtered[];
      ArrayResize(filtered, 0);
      
      // Parse criteria string (e.g., "spread<10,volume>100000,session=LONDON")
      string conditions[];
      StringSplit(criteria, ',', conditions);
      
      for(int i = 0; i < ArraySize(m_tradableSymbols); i++) {
         string symbol = m_tradableSymbols[i];
         bool passesAll = true;
         
         for(int j = 0; j < ArraySize(conditions); j++) {
            if(!CheckCondition(symbol, conditions[j])) {
               passesAll = false;
               break;
            }
         }
         
         if(passesAll) {
            int size = ArraySize(filtered);
            ArrayResize(filtered, size + 1);
            filtered[size] = symbol;
         }
      }
      
      return filtered;
   }
   
   // Symbol analysis methods
   bool IsSymbolTradable(const string symbol) {
      // Check basic trade mode
      if(SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) {
         return false;
      }
      
      // Check spread
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(spread > m_validationRules.maxSpread) {
         return false;
      }
      
      // Check session
      if(!IsSymbolInTradingSession(symbol)) {
         return false;
      }
      
      // Check liquidity (bid/ask availability)
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid == 0 || ask == 0) {
         return false;
      }
      
      return true;
   }
   
   double CalculateSymbolLiquidity(const string symbol, int period = 20) {
      // Estimate liquidity based on average volume and spread
      double totalVolume = 0;
      double totalSpread = 0;
      
      for(int i = 0; i < period; i++) {
         totalVolume += iVolume(symbol, PERIOD_H1, i);
         double spread = (iHigh(symbol, PERIOD_H1, i) - iLow(symbol, PERIOD_H1, i)) / 
                         SymbolInfoDouble(symbol, SYMBOL_POINT);
         totalSpread += spread;
      }
      
      double avgVolume = totalVolume / period;
      double avgSpread = totalSpread / period;
      
      // Liquidity score: higher volume + lower spread = better liquidity
      double volumeScore = MathLog(avgVolume + 1) / 10.0; // Normalize
      double spreadScore = 1.0 / (avgSpread / 100); // Inverse relationship
      
      return (volumeScore + spreadScore) / 2.0;
   }
   
   SymbolProperties GetDetailedProperties(const string symbol) {
      SymbolProperties props;
      props.symbol = symbol;
      props.spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      props.swapLong = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
      props.swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
      props.commission = SymbolInfoDouble(symbol, SYMBOL_COMMISSION);
      props.marginRequired = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
      props.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      props.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      props.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      props.lotMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      props.lotMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      props.lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      props.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      props.tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      props.executionMode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
      
      // Session times
      props.sessionStart = (datetime)SymbolInfoInteger(symbol, SYMBOL_SESSION_START);
      props.sessionEnd = (datetime)SymbolInfoInteger(symbol, SYMBOL_SESSION_END);
      
      return props;
   }
   
   // Grouping methods
   string[] GroupSymbolsByAssetClass() {
      string majors[], crosses[], exotics[], metals[], indices[], crypto[];
      int majCount = 0, crossCount = 0, exoCount = 0, metCount = 0, idxCount = 0, cryCount = 0;
      
      for(int i = 0; i < ArraySize(m_tradableSymbols); i++) {
         string symbol = m_tradableSymbols[i];
         
         if(IsMajorPair(symbol)) {
            ArrayResize(majors, majCount + 1);
            majors[majCount++] = symbol;
         }
         else if(IsCrossPair(symbol)) {
            ArrayResize(crosses, crossCount + 1);
            crosses[crossCount++] = symbol;
         }
         else if(IsExoticPair(symbol)) {
            ArrayResize(exotics, exoCount + 1);
            exotics[exoCount++] = symbol;
         }
         else if(IsMetal(symbol)) {
            ArrayResize(metals, metCount + 1);
            metals[metCount++] = symbol;
         }
         else if(IsIndex(symbol)) {
            ArrayResize(indices, idxCount + 1);
            indices[idxCount++] = symbol;
         }
         else if(IsCryptocurrency(symbol)) {
            ArrayResize(crypto, cryCount + 1);
            crypto[cryCount++] = symbol;
         }
      }
      
      // Return as array of arrays (simplified)
      string groups[];
      ArrayResize(groups, 0);
      
      AddGroup(groups, "MAJORS", majors);
      AddGroup(groups, "CROSSES", crosses);
      AddGroup(groups, "EXOTICS", exotics);
      AddGroup(groups, "METALS", metals);
      AddGroup(groups, "INDICES", indices);
      AddGroup(groups, "CRYPTO", crypto);
      
      return groups;
   }
   
private:
   // Initialization methods
   void InitializeValidationRules() {
      m_validationRules.minSpread = 0.1; // 0.1 pips
      m_validationRules.maxSpread = 20.0; // 20 pips
      m_validationRules.minVolume = 100000; // Minimum average volume
      m_validationRules.maxSwap = 5.0; // Maximum swap in dollars per lot
      m_validationRules.minDigits = 4; // Minimum decimal places
      m_validationRules.allowHedging = true;
      m_validationRules.allowNetting = true;
      
      // Default trading sessions
      ArrayResize(m_validationRules.allowedSessions, 3);
      m_validationRules.allowedSessions[0] = "LONDON";
      m_validationRules.allowedSessions[1] = "NEWYORK";
      m_validationRules.allowedSessions[2] = "TOKYO";
   }
   
   void RefreshTradableSymbols() {
      int totalSymbols = SymbolsTotal(true);
      ArrayResize(m_tradableSymbols, 0);
      
      for(int i = 0; i < totalSymbols; i++) {
         string symbolName = SymbolName(i, true);
         
         // Check if symbol passes validation
         if(ValidateSymbol(symbolName)) {
            int size = ArraySize(m_tradableSymbols);
            ArrayResize(m_tradableSymbols, size + 1);
            m_tradableSymbols[size] = symbolName;
            
            // Cache properties
            UpdateSymbolProperties(symbolName);
         }
      }
      
      Log("SymbolManager", StringFormat("Found %d tradable symbols", ArraySize(m_tradableSymbols)));
   }
   
   bool ValidateSymbol(const string symbol) {
      // Basic validation
      if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL) {
         return false;
      }
      
      // Check spread
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(spread > m_validationRules.maxSpread) {
         return false;
      }
      
      // Check volume (if available)
      if(m_validationRules.minVolume > 0) {
         long volume = SymbolInfoInteger(symbol, SYMBOL_VOLUME_REAL);
         if(volume < m_validationRules.minVolume) {
            return false;
         }
      }
      
      // Check digits
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits < m_validationRules.minDigits) {
         return false;
      }
      
      return true;
   }
   
   void UpdateSymbolProperties(const string symbol) {
      // Update or add properties for symbol
      int index = FindSymbolIndex(symbol);
      if(index == -1) {
         index = ArraySize(m_symbolProperties);
         ArrayResize(m_symbolProperties, index + 1);
      }
      
      m_symbolProperties[index] = GetDetailedProperties(symbol);
   }
   
   int FindSymbolIndex(const string symbol) {
      for(int i = 0; i < ArraySize(m_symbolProperties); i++) {
         if(m_symbolProperties[i].symbol == symbol) {
            return i;
         }
      }
      return -1;
   }
   
   // Condition checking methods
   bool CheckCondition(const string symbol, const string condition) {
      if(StringFind(condition, "spread<") >= 0) {
         double maxSpread = StringToDouble(StringSubstr(condition, 7));
         double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
         return spread < maxSpread;
      }
      else if(StringFind(condition, "volume>") >= 0) {
         double minVolume = StringToDouble(StringSubstr(condition, 7));
         long volume = SymbolInfoInteger(symbol, SYMBOL_VOLUME_REAL);
         return volume > minVolume;
      }
      else if(StringFind(condition, "session=") >= 0) {
         string session = StringSubstr(condition, 8);
         return IsSymbolInSession(symbol, session);
      }
      else if(StringFind(condition, "asset=") >= 0) {
         string assetClass = StringSubstr(condition, 6);
         return IsSymbolOfClass(symbol, assetClass);
      }
      
      return true;
   }
   
   bool IsSymbolInTradingSession(const string symbol) {
      // Use the provided timeutils function
      #ifdef __TIMEUTILS__
      return IsTradingSession(symbol);
      #else
      // Fallback implementation
      datetime now = TimeCurrent();
      MqlDateTime nowStruct;
      TimeToStruct(now, nowStruct);
      
      // Check if within market hours (simplified)
      int hour = nowStruct.hour;
      return (hour >= 1 && hour <= 23); // Most markets open
      #endif
   }
   
   bool IsSymbolInSession(const string symbol, const string session) {
      // Simplified session checking
      datetime now = TimeCurrent();
      MqlDateTime nowStruct;
      TimeToStruct(now, nowStruct);
      int hour = nowStruct.hour;
      
      if(session == "LONDON") return (hour >= 8 && hour <= 16);
      if(session == "NEWYORK") return (hour >= 13 && hour <= 21);
      if(session == "TOKYO") return (hour >= 0 && hour <= 8);
      if(session == "SYDNEY") return (hour >= 22 || hour <= 6);
      
      return true;
   }
   
   bool IsSymbolOfClass(const string symbol, const string assetClass) {
      if(assetClass == "MAJOR") return IsMajorPair(symbol);
      if(assetClass == "CROSS") return IsCrossPair(symbol);
      if(assetClass == "EXOTIC") return IsExoticPair(symbol);
      if(assetClass == "METAL") return IsMetal(symbol);
      if(assetClass == "INDEX") return IsIndex(symbol);
      if(assetClass == "CRYPTO") return IsCryptocurrency(symbol);
      
      return true;
   }
   
   // Symbol classification helpers
   bool IsMajorPair(const string symbol) {
      string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "NZDUSD"};
      for(int i = 0; i < ArraySize(majors); i++) {
         if(symbol == majors[i]) return true;
      }
      return false;
   }
   
   bool IsCrossPair(const string symbol) {
      // Cross pairs don't have USD as base or quote
      if(StringFind(symbol, "USD") >= 0) return false;
      
      // Common crosses
      string crosses[] = {"EURGBP", "EURJPY", "GBPJPY", "EURCHF", "GBPCHF", 
                         "AUDJPY", "CADJPY", "CHFJPY", "EURCAD", "EURAUD"};
      for(int i = 0; i < ArraySize(crosses); i++) {
         if(symbol == crosses[i]) return true;
      }
      
      return StringLen(symbol) == 6; // Assume 6-character pairs are crosses
   }
   
   bool IsExoticPair(const string symbol) {
      // Exotics typically involve emerging market currencies
      string exotics[] = {"USDZAR", "USDMXN", "USDTRY", "USDHKD", "USDSGD",
                         "EURTRY", "GBPTRY", "USDSEK", "USDNOK", "USDDKK"};
      for(int i = 0; i < ArraySize(exotics); i++) {
         if(symbol == exotics[i]) return true;
      }
      
      return false;
   }
   
   bool IsMetal(const string symbol) {
      string metals[] = {"XAUUSD", "XAGUSD", "XAUEUR", "XAGEUR"};
      for(int i = 0; i < ArraySize(metals); i++) {
         if(symbol == metals[i]) return true;
      }
      return false;
   }
   
   bool IsIndex(const string symbol) {
      return StringFind(symbol, "_") > 0 || StringFind(symbol, "500") > 0 || 
             StringFind(symbol, "DJI") > 0 || StringFind(symbol, "FTSE") > 0;
   }
   
   bool IsCryptocurrency(const string symbol) {
      string cryptos[] = {"BTCUSD", "ETHUSD", "XRPUSD", "LTCUSD", "BCHUSD"};
      for(int i = 0; i < ArraySize(cryptos); i++) {
         if(symbol == cryptos[i]) return true;
      }
      return StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0;
   }
   
   void AddGroup(string &groups[], const string groupName, const string &symbols[]) {
      if(ArraySize(symbols) == 0) return;
      
      string groupEntry = groupName + ":";
      for(int i = 0; i < ArraySize(symbols); i++) {
         groupEntry += symbols[i];
         if(i < ArraySize(symbols) - 1) groupEntry += ",";
      }
      
      int size = ArraySize(groups);
      ArrayResize(groups, size + 1);
      groups[size] = groupEntry;
   }
};