//+------------------------------------------------------------------+
//|                                            OrderBlockSimple.mqh |
//|                                     Minimal Order Block Engine   |
//+------------------------------------------------------------------+
#property copyright "Order Block Module"
#property strict

#include "../utils/ResourceManager.mqh"
#include "../utils/Utils.mqh"

enum ENUM_BLOCK_TYPE {
   BLOCK_NONE = 0,
   BLOCK_BULLISH = 1,
   BLOCK_BEARISH = 2
};

enum ENUM_BLOCK_STATUS {
   STATUS_PENDING = 0,
   STATUS_ACTIVE = 1,
   STATUS_MITIGATED = 2,
   STATUS_FAILED = 3
};

struct SimpleOrderBlock {
   string id;
   ENUM_BLOCK_TYPE type;
   ENUM_BLOCK_STATUS status;
   datetime time;
   double high;
   double low;
   double entry;
   double score;
   bool drawn;
   datetime mitigatedTime;
   string label;
};

class COrderBlock {
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int m_lookback;
   double m_atrMultiplier;
   bool m_enableDrawing;
   color m_bullishColor;
   color m_bearishColor;
   string m_prefix;
   
   SimpleOrderBlock m_blocks[];
   int m_blockCount;
   datetime m_lastBarTime;
   
   string m_drawnObjects[];
   
   ResourceManager* m_logger;
   
   bool m_initialized;
   
   // Indicator handles
   int m_atrHandle;
   static double m_point;
   static double m_tickSize;
   
   // Cached data arrays
   static double m_open[];
   static double m_high[];
   static double m_low[];
   static double m_close[];
   static long m_volume[];
   static datetime m_time[];
   static int m_bars;
   
   // Time-based caching
   static datetime m_lastATRCalc;
   static double m_cachedATR;
   static datetime m_lastBarsUpdate;
   static MqlTick m_lastTick;
   static datetime m_lastTickTime;
   
   bool IsEngulfing(int shift);
   double CalculateATR();
   double CalculateScore(int shift, ENUM_BLOCK_TYPE type);
   void DrawBlock(SimpleOrderBlock &block);
   void RemoveBlockDrawing(SimpleOrderBlock &block);
   string GenerateId(datetime time, ENUM_BLOCK_TYPE type);
   void CleanOldBlocks();
   void UpdateBlockStatus();
   
   // Optimized data access methods
   double GetOpen(int shift)    { return (shift >= 0 && shift < m_bars) ? m_open[shift] : 0; }
   double GetClose(int shift)   { return (shift >= 0 && shift < m_bars) ? m_close[shift] : 0; }
   double GetHigh(int shift)    { return (shift >= 0 && shift < m_bars) ? m_high[shift] : 0; }
   double GetLow(int shift)     { return (shift >= 0 && shift < m_bars) ? m_low[shift] : 0; }
   double GetVolume(int shift)  { return (shift >= 0 && shift < m_bars) ? (double)m_volume[shift] : 0.0; }
   datetime GetTime(int shift)  { return (shift >= 0 && shift < m_bars) ? m_time[shift] : 0; }
   int GetBars()                { return m_bars; }
   
   void UpdatePriceData();
   void CacheStaticData();
   
   SimpleOrderBlock GetNearestBlockByType(double price, ENUM_BLOCK_TYPE type);
   int GetActiveBlockCount();
   bool IsSwingHigh(int shift, int lookback);
   bool IsSwingLow(int shift, int lookback);
   bool IsPinBar(int shift);
   bool HasHighVolume(int shift);
   bool PriceMovedAway(int shift, ENUM_BLOCK_TYPE type);
   bool IsFreshBlock(int shift);
   
public:
   COrderBlock();
   COrderBlock(string symbol, ENUM_TIMEFRAMES tf);
   
   bool Initialize(
      ResourceManager* logger,
      string symbol = NULL,
      ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
      int lookback = 100,
      double atrMultiplier = 1.0,
      bool enableDrawing = true,
      color bullishColor = clrLimeGreen,
      color bearishColor = clrCrimson
   );
   
   void Deinitialize();
   
   void OnTick();
   void OnTradeTransaction(const MqlTradeTransaction &trans);
   
   void Update();
   void ScanBlocks();
   void DrawAllBlocks();
   void DisplayScores();
   
   int GetBlockCount() { return m_blockCount; }
   double GetScoreAtPrice(double price);
   SimpleOrderBlock GetNearestBlock(double price);
   bool IsPriceInBlock(double price, double tolerance=0.00001);
   double GetCurrentATR() { return CalculateATR(); }
   
   void SetSymbol(string symbol) { if(!m_initialized) m_symbol = symbol; }
   void SetTimeframe(ENUM_TIMEFRAMES tf) { if(!m_initialized) m_timeframe = tf; }
   void SetLookback(int bars) { if(!m_initialized) m_lookback = bars; }
   void EnableDrawing(bool enable) { if(!m_initialized) m_enableDrawing = enable; }
   
   bool IsInitialized() const { return m_initialized; }
   
   void Cleanup() { Deinitialize(); }
   void OnInit() {}
};

// Initialize static variables
double COrderBlock::m_point = 0;
double COrderBlock::m_tickSize = 0;
double COrderBlock::m_open[];
double COrderBlock::m_high[];
double COrderBlock::m_low[];
double COrderBlock::m_close[];
long COrderBlock::m_volume[];
datetime COrderBlock::m_time[];
int COrderBlock::m_bars = 0;
datetime COrderBlock::m_lastATRCalc = 0;
double COrderBlock::m_cachedATR = 0;
datetime COrderBlock::m_lastBarsUpdate = 0;
MqlTick COrderBlock::m_lastTick;
datetime COrderBlock::m_lastTickTime = 0;

COrderBlock::COrderBlock() {
   m_symbol = _Symbol;
   m_timeframe = _Period;
   m_lookback = 100;
   m_atrMultiplier = 1.0;
   m_enableDrawing = true;
   m_bullishColor = clrLimeGreen;
   m_bearishColor = clrCrimson;
   m_prefix = "OB_";
   
   m_blockCount = 0;
   m_lastBarTime = 0;
   ArrayResize(m_blocks, 50);
   ArrayResize(m_drawnObjects, 0);
   
   m_atrHandle = INVALID_HANDLE;
   
   m_logger = NULL;
   
   m_initialized = false;
}

COrderBlock::COrderBlock(string symbol, ENUM_TIMEFRAMES tf) {
   m_symbol = symbol;
   m_timeframe = tf;
   m_lookback = 100;
   m_atrMultiplier = 1.0;
   m_enableDrawing = true;
   m_bullishColor = clrLimeGreen;
   m_bearishColor = clrCrimson;
   m_prefix = "OB_";
   
   m_blockCount = 0;
   m_lastBarTime = 0;
   ArrayResize(m_blocks, 50);
   ArrayResize(m_drawnObjects, 0);
   
   m_atrHandle = INVALID_HANDLE;
   
   m_logger = NULL;
   
   m_initialized = false;
}

void COrderBlock::CacheStaticData() {
   if(m_point == 0) {
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   }
}

void COrderBlock::UpdatePriceData() {
   // Early exit if no significant time has passed
   datetime currentTime = TimeCurrent();
   if(currentTime <= m_lastBarsUpdate + 1) return;
   
   m_lastBarsUpdate = currentTime;
   m_bars = iBars(m_symbol, m_timeframe);
   
   if(m_bars <= 0) return;
   
   // Batch copy all price data at once
   int toCopy = MathMin(m_bars, m_lookback + 100);
   
   // Resize arrays if needed
   if(ArraySize(m_open) < toCopy) {
      ArraySetAsSeries(m_open, false);
      ArraySetAsSeries(m_high, false);
      ArraySetAsSeries(m_low, false);
      ArraySetAsSeries(m_close, false);
      ArraySetAsSeries(m_volume, false);
      ArraySetAsSeries(m_time, false);
      
      ArrayResize(m_open, toCopy);
      ArrayResize(m_high, toCopy);
      ArrayResize(m_low, toCopy);
      ArrayResize(m_close, toCopy);
      ArrayResize(m_volume, toCopy);
      ArrayResize(m_time, toCopy);
   }
   
   // Copy all data in batch operations
   CopyOpen(m_symbol, m_timeframe, 0, toCopy, m_open);
   CopyHigh(m_symbol, m_timeframe, 0, toCopy, m_high);
   CopyLow(m_symbol, m_timeframe, 0, toCopy, m_low);
   CopyClose(m_symbol, m_timeframe, 0, toCopy, m_close);
   CopyTickVolume(m_symbol, m_timeframe, 0, toCopy, m_volume);
   CopyTime(m_symbol, m_timeframe, 0, toCopy, m_time);
}

bool COrderBlock::Initialize(
   ResourceManager* logger,
   string symbol,
   ENUM_TIMEFRAMES tf,
   int lookback,
   double atrMultiplier,
   bool enableDrawing,
   color bullishColor,
   color bearishColor
) {
   if(m_initialized) {
      Print("COrderBlock: Already initialized");
      return true;
   }
   
   if(logger == NULL) {
      Print("COrderBlock ERROR: ResourceManager (logger) is required");
      return false;
   }
   
   m_logger = logger;
   
   if(symbol != NULL) m_symbol = symbol;
   if(tf != PERIOD_CURRENT) m_timeframe = tf;
   m_lookback = lookback;
   m_atrMultiplier = atrMultiplier;
   m_enableDrawing = enableDrawing;
   m_bullishColor = bullishColor;
   m_bearishColor = bearishColor;
   
   // Cache static data
   CacheStaticData();
   
   // Create indicator handles once in initialization
   m_atrHandle = iATR(m_symbol, m_timeframe, 14);
   if(m_atrHandle == INVALID_HANDLE) {
      Print("COrderBlock ERROR: Failed to create ATR indicator");
      return false;
   }
   
   m_logger.StartContextWith(m_symbol, "OrderBlock_Initialize");
   m_logger.AddToContext(m_symbol, "Action", "Initializing Order Block Engine");
   m_logger.AddToContext(m_symbol, "Symbol", m_symbol);
   m_logger.AddToContext(m_symbol, "Timeframe", EnumToString(m_timeframe));
   m_logger.AddToContext(m_symbol, "Lookback", IntegerToString(m_lookback));
   
   // Initialize price data arrays
   UpdatePriceData();
   
   int deletedCount = 0;
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects-1; i >= 0; i--) {
      string name = ObjectName(0, i);
      if(StringFind(name, m_prefix) == 0) {
         ObjectDelete(0, name);
         deletedCount++;
      }
   }
   
   m_logger.AddToContext(m_symbol, "DeletedObjects", IntegerToString(deletedCount));
   
   ScanBlocks();
   if(m_enableDrawing) {
      DrawAllBlocks();
   }
   
   m_logger.AddToContext(m_symbol, "InitialBlocksFound", IntegerToString(m_blockCount));
   m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_Initialize", "Order Block Engine Initialized", false);
   
   m_initialized = true;
   
   return true;
}

void COrderBlock::Deinitialize() {
   if(!m_initialized) return;
   
   if(m_logger != NULL) {
      m_logger.StartContextWith(m_symbol, "OrderBlock_Deinitialize");
      m_logger.AddToContext(m_symbol, "Action", "Deinitializing Order Block Engine");
   }
   
   // Release indicator handles
   if(m_atrHandle != INVALID_HANDLE) {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
   
   int deletedCount = 0;
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects-1; i >= 0; i--) {
      string name = ObjectName(0, i);
      if(StringFind(name, m_prefix) == 0) {
         ObjectDelete(0, name);
         deletedCount++;
      }
   }
   
   if(m_logger != NULL) {
      m_logger.AddToContext(m_symbol, "DeletedObjects", IntegerToString(deletedCount));
      m_logger.AddToContext(m_symbol, "BlockCount", IntegerToString(m_blockCount));
      m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_Deinitialize", "Order Block Engine Deinitialized", false);
   }
   
   ArrayFree(m_blocks);
   ArrayFree(m_drawnObjects);
   
   m_blockCount = 0;
   m_lastBarTime = 0;
   
   m_logger = NULL;
   
   m_initialized = false;
}

void COrderBlock::OnTick() {
   if(!m_initialized) return;
   
   // Early exit if tick hasn't changed
   MqlTick currentTick;
   if(SymbolInfoTick(m_symbol, currentTick)) {
      if(currentTick.time == m_lastTickTime && 
         currentTick.bid == m_lastTick.bid &&
         currentTick.ask == m_lastTick.ask) {
         return;
      }
      m_lastTick = currentTick;
      m_lastTickTime = currentTick.time;
   }
   
   datetime currentBarTime = GetTime(0);
   if(currentBarTime == m_lastBarTime) return;
   
   m_lastBarTime = currentBarTime;
   Update();
}

void COrderBlock::OnTradeTransaction(const MqlTradeTransaction &trans) {
   if(!m_initialized) return;
   
   if(m_logger != NULL) {
      m_logger.AutoLogTradeTransaction(trans);
   }
}

void COrderBlock::Update() {
   if(!m_initialized || m_logger == NULL) return;
   
   m_logger.StartContextWith(m_symbol, "OrderBlock_Update");
   
   // Update price data efficiently
   UpdatePriceData();
   
   int oldCount = m_blockCount;
   CleanOldBlocks();
   m_logger.AddToContext(m_symbol, "BlocksCleaned", IntegerToString(oldCount - m_blockCount));
   
   int blocksBeforeScan = m_blockCount;
   ScanBlocks();
   m_logger.AddToContext(m_symbol, "NewBlocksFound", IntegerToString(m_blockCount - blocksBeforeScan));
   
   UpdateBlockStatus();
   
   if(m_enableDrawing) {
      DrawAllBlocks();
      m_logger.AddBoolContext(m_symbol, "DrawingEnabled", true);
   }
   
   DisplayScores();
   
   m_logger.AddToContext(m_symbol, "TotalActiveBlocks", IntegerToString(GetActiveBlockCount()));
   m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_Update", "Order Block Update Complete", false);
}

void COrderBlock::ScanBlocks() {
   if(!m_initialized || m_logger == NULL) return;
   
   m_logger.StartContextWith(m_symbol, "OrderBlock_Scan");
   m_logger.AddToContext(m_symbol, "Action", "Scanning for Order Blocks");
   
   int limit = MathMin(m_lookback, m_bars - 1);
   m_logger.AddToContext(m_symbol, "ScanLimit", IntegerToString(limit));
   
   int bullishFound = 0;
   int bearishFound = 0;
   
   // Cache loop limit
   int loopLimit = limit;
   
   for(int i = loopLimit; i > 0; i--) {
      // Early exit if we can't access needed bars
      if(i > m_bars - 2) continue;
      
      double close_i = GetClose(i);
      double open_i = GetOpen(i);
      double close_i1 = GetClose(i+1);
      double open_i1 = GetOpen(i+1);
      
      // Bullish block detection
      if(close_i < open_i && close_i1 > open_i1) {
         if(IsEngulfing(i-1)) {
            SimpleOrderBlock block;
            block.id = GenerateId(GetTime(i), BLOCK_BULLISH);
            block.type = BLOCK_BULLISH;
            block.status = STATUS_PENDING;
            block.time = GetTime(i);
            block.high = GetHigh(i);
            block.low = GetLow(i);
            block.entry = GetHigh(i);
            block.score = CalculateScore(i, BLOCK_BULLISH);
            block.drawn = false;
            block.label = "Bullish OB";
            
            bool exists = false;
            int blockCount = m_blockCount; // Cache array size
            for(int j = 0; j < blockCount; j++) {
               if(m_blocks[j].id == block.id) {
                  exists = true;
                  break;
               }
            }
            
            if(!exists) {
               m_blocks[m_blockCount] = block;
               m_blockCount++;
               bullishFound++;
               
               m_logger.KeepNotes(m_symbol, AUDIT, "OrderBlock_Scan",
                  StringFormat("Bullish OB found at %s, Price: %.5f, Score: %.1f",
                     TimeToString(block.time), block.entry, block.score), false);
                  
               if(m_blockCount >= ArraySize(m_blocks)) {
                  ArrayResize(m_blocks, m_blockCount + 20);
               }
            }
         }
      }
      
      // Bearish block detection
      if(close_i > open_i && close_i1 < open_i1) {
         if(IsEngulfing(i-1)) {
            SimpleOrderBlock block;
            block.id = GenerateId(GetTime(i), BLOCK_BEARISH);
            block.type = BLOCK_BEARISH;
            block.status = STATUS_PENDING;
            block.time = GetTime(i);
            block.high = GetHigh(i);
            block.low = GetLow(i);
            block.entry = GetLow(i);
            block.score = CalculateScore(i, BLOCK_BEARISH);
            block.drawn = false;
            block.label = "Bearish OB";
            
            bool exists = false;
            int blockCount = m_blockCount; // Cache array size
            for(int j = 0; j < blockCount; j++) {
               if(m_blocks[j].id == block.id) {
                  exists = true;
                  break;
               }
            }
            
            if(!exists) {
               m_blocks[m_blockCount] = block;
               m_blockCount++;
               bearishFound++;
               
               m_logger.KeepNotes(m_symbol, AUDIT, "OrderBlock_Scan",
                  StringFormat("Bearish OB found at %s, Price: %.5f, Score: %.1f",
                     TimeToString(block.time), block.entry, block.score), false);
                  
               if(m_blockCount >= ArraySize(m_blocks)) {
                  ArrayResize(m_blocks, m_blockCount + 20);
               }
            }
         }
      }
   }
   
   m_logger.AddToContext(m_symbol, "BullishBlocks", IntegerToString(bullishFound));
   m_logger.AddToContext(m_symbol, "BearishBlocks", IntegerToString(bearishFound));
   m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_Scan", 
      StringFormat("Scan complete: %d new blocks found", bullishFound + bearishFound), false);
}

bool COrderBlock::IsEngulfing(int shift) {
   if(shift >= m_bars-1) return false;
   
   double open1 = GetOpen(shift);
   double close1 = GetClose(shift);
   double open2 = GetOpen(shift+1);
   double close2 = GetClose(shift+1);
   
   double bodyCurrent = MathAbs(close1 - open1);
   double bodyPrevious = MathAbs(close2 - open2);
   
   if(bodyCurrent <= bodyPrevious) return false;
   
   if(close1 > open1 && close2 < open2) {
      if(open1 <= close2 && close1 >= open2) {
         return true;
      }
   }
   
   if(close1 < open1 && close2 > open2) {
      if(open1 >= close2 && close1 <= open2) {
         return true;
      }
   }
   
   return false;
}

double COrderBlock::CalculateATR() {
   // Time-based caching for ATR calculation
   datetime currentTime = TimeCurrent();
   if(currentTime <= m_lastATRCalc + 2 && m_cachedATR > 0) {
      return m_cachedATR;
   }
   
   if(m_atrHandle == INVALID_HANDLE) {
      m_atrHandle = iATR(m_symbol, m_timeframe, 14);
      if(m_atrHandle == INVALID_HANDLE) return 0.0;
   }
   
   double atr[1];
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) <= 0) {
      return 0.0;
   }
   
   m_cachedATR = atr[0];
   m_lastATRCalc = currentTime;
   return m_cachedATR;
}

double COrderBlock::CalculateScore(int shift, ENUM_BLOCK_TYPE type) {
   double score = 50.0;
   
   // Early exit if invalid shift
   if(shift >= m_bars) return score;
   
   double volume = GetVolume(shift);
   double avgVolume = 0;
   int lookback = MathMin(20, shift);
   
   // Cache loop limit
   int volumeLookback = lookback;
   for(int i = 1; i <= volumeLookback; i++) {
      int idx = shift + i;
      if(idx < m_bars) {
         avgVolume += GetVolume(idx);
      }
   }
   avgVolume /= volumeLookback;
   
   if(volume > avgVolume * 1.5) score += 30;
   else if(volume > avgVolume) score += 15;
   
   double range = GetHigh(shift) - GetLow(shift);
   double atr = CalculateATR();
   double rangeToATR = range / atr;
   
   if(rangeToATR > 1.5) score += 30;
   else if(rangeToATR > 1.0) score += 15;
   
   double bodySize = MathAbs(GetClose(shift) - GetOpen(shift));
   double upperWick = GetHigh(shift) - MathMax(GetClose(shift), GetOpen(shift));
   double lowerWick = MathMin(GetClose(shift), GetOpen(shift)) - GetLow(shift);
   
   if(type == BLOCK_BULLISH) {
      if(lowerWick > bodySize * 1.5) score += 20;
   } else {
      if(upperWick > bodySize * 1.5) score += 20;
   }
   
   double currentHigh = GetHigh(shift);
   double currentLow = GetLow(shift);
   
   if(shift > 10) {
      double maxHigh = 0;
      double minLow = DBL_MAX;
      int highLowLookback = MathMin(10, shift);
      
      // Cache loop limit
      int hlLoopLimit = highLowLookback;
      for(int i = 1; i <= hlLoopLimit; i++) {
         int idx = shift + i;
         if(idx < m_bars) {
            double high = GetHigh(idx);
            double low = GetLow(idx);
            maxHigh = MathMax(maxHigh, high);
            minLow = MathMin(minLow, low);
         }
      }
      
      if(type == BLOCK_BULLISH) {
         if(currentHigh < maxHigh) score += 10;
         if(currentLow > minLow) score += 10;
      } else {
         if(currentLow > minLow) score += 10;
         if(currentHigh < maxHigh) score += 10;
      }
   }
   
   return MathMin(score, 100.0);
}

void COrderBlock::DrawBlock(SimpleOrderBlock &block) {
   if(block.drawn || !m_initialized) return;
   
   if(m_logger != NULL) {
      m_logger.StartContextWith(m_symbol, "OrderBlock_Draw");
   }
   
   // String optimization
   const string lineNamePrefix = m_prefix + "Line_";
   const string labelNamePrefix = m_prefix + "Label_";
   
   string nameLine = lineNamePrefix + block.id;
   string nameLabel = labelNamePrefix + block.id;
   
   color lineColor = (block.type == BLOCK_BULLISH) ? m_bullishColor : m_bearishColor;
   
   if(!ObjectCreate(0, nameLine, OBJ_TREND, 0, block.time, block.entry, 
                TimeCurrent(), block.entry)) {
      int error = GetLastError();
      if(m_logger != NULL) {
         m_logger.AddToContext(m_symbol, "Error", IntegerToString(error));
         m_logger.AddToContext(m_symbol, "ErrorMessage", "Failed to create line object");
         m_logger.FlushContext(m_symbol, WARN, "OrderBlock_Draw", "Failed to draw block line", false);
      }
      return;
   }
   
   ObjectSetInteger(0, nameLine, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, nameLine, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nameLine, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nameLine, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, nameLine, OBJPROP_BACK, true);
   
   if(!ObjectCreate(0, nameLabel, OBJ_TEXT, 0, block.time, block.entry)) {
      int error = GetLastError();
      if(m_logger != NULL) {
         m_logger.AddToContext(m_symbol, "Error", IntegerToString(error));
         m_logger.AddToContext(m_symbol, "ErrorMessage", "Failed to create label object");
         m_logger.FlushContext(m_symbol, WARN, "OrderBlock_Draw", "Failed to draw block label", false);
      }
      return;
   }
   
   // String optimization
   string labelText;
   if(block.type == BLOCK_BULLISH) {
      labelText = StringFormat("▲ OB (%.0f)", block.score);
   } else {
      labelText = StringFormat("▼ OB (%.0f)", block.score);
   }
   
   ObjectSetString(0, nameLabel, OBJPROP_TEXT, labelText);
   ObjectSetInteger(0, nameLabel, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, nameLabel, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, nameLabel, OBJPROP_BACK, true);
   
   // Use cached point value
   double labelOffset = 0.0002 * (block.type == BLOCK_BULLISH ? 1 : -1);
   if(m_point > 0) {
      labelOffset = 20 * m_point * (block.type == BLOCK_BULLISH ? 1 : -1);
   }
   
   ObjectSetDouble(0, nameLabel, OBJPROP_PRICE, block.entry + labelOffset);
   
   block.drawn = true;
   
   int count = ArraySize(m_drawnObjects);
   ArrayResize(m_drawnObjects, count + 2);
   m_drawnObjects[count] = nameLine;
   m_drawnObjects[count+1] = nameLabel;
   
   if(m_logger != NULL) {
      m_logger.AddToContext(m_symbol, "BlockType", block.type == BLOCK_BULLISH ? "Bullish" : "Bearish");
      m_logger.AddDoubleContext(m_symbol, "BlockPrice", block.entry, 5);
      m_logger.AddDoubleContext(m_symbol, "BlockScore", block.score, 1);
      m_logger.FlushContext(m_symbol, AUDIT, "OrderBlock_Draw", "Block drawn successfully", false);
   }
}

void COrderBlock::RemoveBlockDrawing(SimpleOrderBlock &block) {
   // String optimization
   const string lineNamePrefix = m_prefix + "Line_";
   const string labelNamePrefix = m_prefix + "Label_";
   
   string nameLine = lineNamePrefix + block.id;
   string nameLabel = labelNamePrefix + block.id;
   
   ObjectDelete(0, nameLine);
   ObjectDelete(0, nameLabel);
   
   block.drawn = false;
   
   if(m_logger != NULL) {
      m_logger.KeepNotes(m_symbol, AUDIT, "OrderBlock_Remove", 
         StringFormat("Block drawing removed: %s at %.5f", 
            block.type == BLOCK_BULLISH ? "Bullish" : "Bearish", block.entry), false);
   }
}

void COrderBlock::DrawAllBlocks() {
   if(!m_initialized) return;
   
   if(m_logger != NULL) {
      m_logger.StartContextWith(m_symbol, "OrderBlock_DrawAll");
   }
   
   int drawnCount = 0;
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status != STATUS_MITIGATED && m_blocks[i].status != STATUS_FAILED) {
         DrawBlock(m_blocks[i]);
         drawnCount++;
      } else {
         RemoveBlockDrawing(m_blocks[i]);
      }
   }
   
   if(m_logger != NULL) {
      m_logger.AddToContext(m_symbol, "BlocksDrawn", IntegerToString(drawnCount));
      m_logger.AddToContext(m_symbol, "TotalBlocks", IntegerToString(blockCount));
      m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_DrawAll", "All blocks drawn", false);
   }
}

void COrderBlock::DisplayScores() {
   if(!m_initialized) return;
   
   Comment("");
}

SimpleOrderBlock COrderBlock::GetNearestBlockByType(double price, ENUM_BLOCK_TYPE type) {
   SimpleOrderBlock empty;
   empty.id = "";
   empty.score = 0;
   
   int bestIndex = -1;
   double minDistance = DBL_MAX;
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_ACTIVE && m_blocks[i].type == type) {
         double distance = MathAbs(price - m_blocks[i].entry);
         if(distance < minDistance) {
            minDistance = distance;
            bestIndex = i;
         }
      }
   }
   
   if(bestIndex >= 0) {
      return m_blocks[bestIndex];
   }
   
   return empty;
}

int COrderBlock::GetActiveBlockCount() {
   int count = 0;
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_ACTIVE) {
         count++;
      }
   }
   return count;
}

string COrderBlock::GenerateId(datetime time, ENUM_BLOCK_TYPE type) {
   return StringFormat("%d_%d_%d", time, type, MathRand());
}

void COrderBlock::CleanOldBlocks() {
   if(!m_initialized || m_logger == NULL) return;
   
   m_logger.StartContextWith(m_symbol, "OrderBlock_CleanOld");
   
   int newCount = 0;
   SimpleOrderBlock temp[];
   ArrayResize(temp, m_blockCount);
   
   int removedActive = 0;
   int removedPending = 0;
   int removedMitigated = 0;
   int removedFailed = 0;
   
   int blockCount = m_blockCount; // Cache array size
   datetime currentTime = TimeCurrent();
   
   for(int i = 0; i < blockCount; i++) {
      bool keepBlock = false;
      
      switch(m_blocks[i].status) {
         case STATUS_ACTIVE:
            keepBlock = true;
            break;
            
         case STATUS_PENDING:
            if((currentTime - m_blocks[i].time) < 172800) {
               keepBlock = true;
            } else {
               removedPending++;
            }
            break;
            
         case STATUS_MITIGATED:
            if((currentTime - m_blocks[i].mitigatedTime) < 86400) {
               keepBlock = true;
            } else {
               removedMitigated++;
            }
            break;
            
         case STATUS_FAILED:
            if((currentTime - m_blocks[i].time) < 43200) {
               keepBlock = true;
            } else {
               removedFailed++;
            }
            break;
      }
      
      if(keepBlock) {
         temp[newCount] = m_blocks[i];
         newCount++;
      } else {
         RemoveBlockDrawing(m_blocks[i]);
         m_logger.KeepNotes(m_symbol, AUDIT, "OrderBlock_CleanOld",
            StringFormat("Old %s block removed: Status=%s, Age=%d hours",
               m_blocks[i].type == BLOCK_BULLISH ? "Bullish" : "Bearish",
               EnumToString(m_blocks[i].status),
               (int)((currentTime - m_blocks[i].time) / 3600)), false);
      }
   }
   
   ArrayFree(m_blocks);
   m_blockCount = newCount;
   ArrayResize(m_blocks, m_blockCount + 10);
   for(int i = 0; i < m_blockCount; i++) {
      m_blocks[i] = temp[i];
   }
   
   m_logger.AddToContext(m_symbol, "BlocksRemovedPending", IntegerToString(removedPending));
   m_logger.AddToContext(m_symbol, "BlocksRemovedMitigated", IntegerToString(removedMitigated));
   m_logger.AddToContext(m_symbol, "BlocksRemovedFailed", IntegerToString(removedFailed));
   m_logger.AddToContext(m_symbol, "BlocksRemaining", IntegerToString(m_blockCount));
   m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_CleanOld", 
      StringFormat("Cleaned %d old blocks", removedPending + removedMitigated + removedFailed), false);
}

void COrderBlock::UpdateBlockStatus() {
   if(!m_initialized || m_logger == NULL) return;
   
   m_logger.StartContextWith(m_symbol, "OrderBlock_UpdateStatus");
   
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double atr = CalculateATR();
   double activationThreshold = atr * 0.1;
   
   int activated = 0;
   int mitigated = 0;
   int failed = 0;
   
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_PENDING) {
         double distanceToEntry = MathAbs(currentPrice - m_blocks[i].entry);
         if(distanceToEntry < activationThreshold) {
            m_blocks[i].status = STATUS_ACTIVE;
            activated++;
            
            m_logger.KeepNotes(m_symbol, AUTHORIZE, "OrderBlock_Activation",
               StringFormat("%s Order Block Activated at %.5f (Score: %.0f)", 
                  m_blocks[i].type == BLOCK_BULLISH ? "Bullish" : "Bearish",
                  m_blocks[i].entry, m_blocks[i].score), false);
         }
      }
      
      if(m_blocks[i].status == STATUS_ACTIVE) {
         double moveFromEntry = currentPrice - m_blocks[i].entry;
         
         if(m_blocks[i].type == BLOCK_BULLISH) {
            if(moveFromEntry > atr * 1.0) {
               m_blocks[i].status = STATUS_MITIGATED;
               m_blocks[i].mitigatedTime = TimeCurrent();
               mitigated++;
               
               m_logger.KeepNotes(m_symbol, AUTHORIZE, "OrderBlock_Mitigation",
                  StringFormat("Bullish OB Mitigated: Entry=%.5f, Current=%.5f, Move=+%.0f pips", 
                     m_blocks[i].entry, currentPrice, moveFromEntry / _Point), false);
            } else if(moveFromEntry < -atr * 0.3) {
               m_blocks[i].status = STATUS_FAILED;
               failed++;
               
               m_logger.KeepNotes(m_symbol, WARN, "OrderBlock_Failure",
                  StringFormat("Bullish OB Failed: Entry=%.5f, Current=%.5f, Move=-%.0f pips", 
                     m_blocks[i].entry, currentPrice, MathAbs(moveFromEntry) / _Point), false);
            }
         } else {
            if(moveFromEntry < -atr * 1.0) {
               m_blocks[i].status = STATUS_MITIGATED;
               m_blocks[i].mitigatedTime = TimeCurrent();
               mitigated++;
               
               m_logger.KeepNotes(m_symbol, AUTHORIZE, "OrderBlock_Mitigation",
                  StringFormat("Bearish OB Mitigated: Entry=%.5f, Current=%.5f, Move=-%.0f pips", 
                     m_blocks[i].entry, currentPrice, MathAbs(moveFromEntry) / _Point), false);
            } else if(moveFromEntry > atr * 0.3) {
               m_blocks[i].status = STATUS_FAILED;
               failed++;
               
               m_logger.KeepNotes(m_symbol, WARN, "OrderBlock_Failure",
                  StringFormat("Bearish OB Failed: Entry=%.5f, Current=%.5f, Move=+%.0f pips", 
                     m_blocks[i].entry, currentPrice, moveFromEntry / _Point), false);
            }
         }
      }
   }
   
   m_logger.AddToContext(m_symbol, "BlocksActivated", IntegerToString(activated));
   m_logger.AddToContext(m_symbol, "BlocksMitigated", IntegerToString(mitigated));
   m_logger.AddToContext(m_symbol, "BlocksFailed", IntegerToString(failed));
   m_logger.AddDoubleContext(m_symbol, "CurrentATR", atr, 5);
   m_logger.AddDoubleContext(m_symbol, "CurrentPrice", currentPrice, 5);
   m_logger.FlushContext(m_symbol, OBSERVE, "OrderBlock_UpdateStatus", 
      StringFormat("Status updated: %d activated, %d mitigated, %d failed", activated, mitigated, failed), false);
}

double COrderBlock::GetScoreAtPrice(double price) {
   if(!m_initialized) return 0.0;
   
   double bestScore = 0;
   double minDistance = DBL_MAX;
   double atr = CalculateATR();
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_ACTIVE) {
         double distance = MathAbs(price - m_blocks[i].entry);
         double distanceFactor = 1.0 - MathMin(distance / (atr * 2.0), 1.0);
         double weightedScore = m_blocks[i].score * distanceFactor;
         
         if(weightedScore > bestScore) {
            bestScore = weightedScore;
         }
      }
   }
   
   return bestScore;
}

SimpleOrderBlock COrderBlock::GetNearestBlock(double price) {
   SimpleOrderBlock empty;
   empty.id = "";
   empty.score = 0;
   
   if(!m_initialized || m_blockCount == 0) return empty;
   
   int bestIndex = -1;
   double minDistance = DBL_MAX;
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_ACTIVE) {
         double distance = MathAbs(price - m_blocks[i].entry);
         if(distance < minDistance) {
            minDistance = distance;
            bestIndex = i;
         }
      }
   }
   
   if(bestIndex >= 0) {
      return m_blocks[bestIndex];
   }
   
   return empty;
}

bool COrderBlock::IsPriceInBlock(double price, double tolerance) {
   if(!m_initialized) return false;
   
   int blockCount = m_blockCount; // Cache array size
   
   for(int i = 0; i < blockCount; i++) {
      if(m_blocks[i].status == STATUS_ACTIVE) {
         if(price >= (m_blocks[i].low - tolerance) && 
            price <= (m_blocks[i].high + tolerance)) {
            return true;
         }
      }
   }
   return false;
}
//+------------------------------------------------------------------+