//+------------------------------------------------------------------+
//|                          SymbolManager.mqh                      |
//|                   Comprehensive Symbol Management               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include <Arrays/ArrayString.mqh>
#include "../utils/ResourceManager.mqh"

/*
==============================================================
                            USECASE
==============================================================

==============================================================
*/

// ============ ENUMERATIONS ============
enum SYMBOL_STATUS
{
    SYMBOL_DISABLED,       // Manually disabled
    SYMBOL_TRADABLE,       // Available for trading
    SYMBOL_SUSPENDED,      // Market suspended
    SYMBOL_CLOSED,         // Market closed
    SYMBOL_HIGH_RISK       // High risk/volatility
};

enum MARKET_SESSION
{
    SESSION_ASIA,
    SESSION_LONDON,
    SESSION_NEWYORK,
    SESSION_OVERLAP,
    SESSION_CLOSED
};

// ============ SYMBOL DATA STRUCTURE ============
struct SymbolData
{
    string symbol;
    bool enabled;
    SYMBOL_STATUS status;
    
    // Trading properties
    double tickSize;
    double lotSize;
    double contractSize;
    double pointValue;
    double pipValue;
    
    // Limits
    double minVolume;
    double maxVolume;
    double volumeStep;
    double marginRequired;
    
    // Market data
    double bid;
    double ask;
    double spread;
    double lastPrice;
    datetime lastUpdate;
    
    // Risk tracking
    int positionCount;
    double totalExposure;
    double maxExposure;
    int maxPositions;
    
    // Performance
    double dailyHigh;
    double dailyLow;
    double dailyRange;
    double avgSpread;
    double volatility;
    
    // Configuration
    bool allowHedging;
    bool allowScalping;
    double maxSpreadAllowed;
    int tradePriority; // 1-10, higher = more priority
};

// ============ SYMBOL MANAGER CLASS ============
class SymbolManager
{
private:
    SymbolData m_symbols[];           // Array of symbol data
    int allAvailableSymbols;          // Number of managed symbols
    ResourceManager* ResourceManager; // Pointer to logger

    double m_correlationMatrix[];     // Missing: correlation matrix
    int m_symbolCount;                // Missing: symbol count
    
    // Configuration
    double m_maxSpreadMultiplier;     // Spread multiplier for filtering
    double m_minLiquidity;            // Minimum liquidity threshold
    int m_maxSymbolsPerAccountTier[5]; // Max symbols per account tier
    
public:
    // ============ CONSTRUCTOR & DESTRUCTOR ============
    SymbolManager()
    {
        allAvailableSymbols = 0;
        m_symbolCount = 0;  // Add this
        ResourceManager = NULL;
        m_maxSpreadMultiplier = 2.0;
        m_minLiquidity = 1000000.0;
    
        // Default max symbols per tier
        m_maxSymbolsPerAccountTier[0] = 2;  // Tier 1
        m_maxSymbolsPerAccountTier[1] = 3;  // Tier 2
        m_maxSymbolsPerAccountTier[2] = 5;  // Tier 3
        m_maxSymbolsPerAccountTier[3] = 8;  // Tier 4
        m_maxSymbolsPerAccountTier[4] = 12; // Tier 5
    }
    
    ~SymbolManager()
    {
        ArrayFree(m_symbols);
    }
    
    // ============ INITIALIZATION ============
    void Init(string &symbols[], ResourceManager* logger = NULL)
    {
        ResourceManager = logger;
        allAvailableSymbols = ArraySize(symbols);
        ArrayResize(m_symbols, allAvailableSymbols);
        
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            InitializeSymbolData(symbols[i], i);
        }
        
        if(ResourceManager != NULL)
        {
            ResourceManager.KeepNotes("SYSTEM", OBSERVE, "SymbolManager",
                StringFormat("Initialized with %d symbols", allAvailableSymbols));
        }
    }
    
    // ============ SYMBOL INFORMATION MANAGEMENT ============
    
    // Get basic symbol information
    bool GetSymbolInfo(string symbol, SymbolData &data)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            data = m_symbols[index];
            return true;
        }
        return false;
    }
    
    // Update all symbol data
    void UpdateAllSymbolData()
    {
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            UpdateSymbolData(i);
        }
    }
    
    // Update specific symbol data
    bool UpdateSymbolData(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            UpdateSymbolData(index);
            return true;
        }
        return false;
    }
    
    // ============ MARKET STATUS & ELIGIBILITY ============
    
    // Check if symbol is tradable
    bool IsSymbolTradable(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0) return false;
        
        SymbolData data = m_symbols[index];
        
        // Check all conditions
        return data.enabled &&
               data.status == SYMBOL_TRADABLE &&
               IsMarketOpen(symbol) &&
               IsSpreadAcceptable(symbol) &&
               IsLiquiditySufficient(symbol);
    }
    
    // Check if market is open
    bool IsMarketOpen(string symbol)
    {
        // Get current day of week
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int dayOfWeek = dt.day_of_week;  // 0-Sunday, 1-Monday, etc.
        
        // Check for weekends
        if(dayOfWeek == 0)  // Sunday
        {
            // Forex market opens Sunday 5 PM EST
            if(dt.hour < 17) return false;
        }
        else if(dayOfWeek == 5)  // Friday
        {
            // Forex market closes Friday 5 PM EST
            if(dt.hour >= 17) return false;
        }
        
        return true;
    }
    
    // Get current market session
    MARKET_SESSION GetCurrentSession(string symbol)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int hour = dt.hour;
        
        // EST timezone (simplified)
        if(hour >= 0 && hour < 5) return SESSION_ASIA;
        if(hour >= 5 && hour < 8) return SESSION_OVERLAP; // Asia/London overlap
        if(hour >= 8 && hour < 13) return SESSION_LONDON;
        if(hour >= 13 && hour < 17) return SESSION_OVERLAP; // London/NY overlap
        if(hour >= 17 && hour < 22) return SESSION_NEWYORK;
        return SESSION_CLOSED;
    }
    
    // Check if spread is acceptable
    bool IsSpreadAcceptable(string symbol, double maxSpreadMultiplier = 0.0)
    {
        if(maxSpreadMultiplier <= 0) maxSpreadMultiplier = m_maxSpreadMultiplier;
        
        int index = FindSymbolIndex(symbol);
        if(index < 0) return false;
        
        double currentSpread = m_symbols[index].spread;
        double avgSpread = m_symbols[index].avgSpread;
        
        if(avgSpread <= 0) return true; // No data yet
        
        return currentSpread <= (avgSpread * maxSpreadMultiplier);
    }
    
    // ============ SYMBOL PRICING & DATA ACCESS ============
    
    // Get current bid price
    double GetBid(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            UpdateSymbolData(index);
            return m_symbols[index].bid;
        }
        return 0.0;
    }
    
    // Get current ask price
    double GetAsk(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            UpdateSymbolData(index);
            return m_symbols[index].ask;
        }
        return 0.0;
    }
    
    // Get current spread in points
    double GetCurrentSpread(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            UpdateSymbolData(index);
            return m_symbols[index].spread;
        }
        return 0.0;
    }
    
    // Get pip value for a lot size
    double GetPipValue(string symbol, double lots = 1.0)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].pipValue * lots;
        }
        return 0.0;
    }
    
    // Get point value
    double GetPointValue(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].pointValue;
        }
        return 0.0;
    }
    
    // Get daily volatility (ATR or range-based)
    double GetDailyVolatility(string symbol, int period = 14)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0) return 0.0;
        
        // Simple ATR calculation
        double atr = iATR(symbol, PERIOD_D1, period);
        double price = m_symbols[index].bid;
        
        if(price > 0)
            return (atr / price) * 100.0;
        
        return 0.0;
    }
    
    // ============ RISK & EXPOSURE CONTROLS ============
    
    // Get position count for symbol
    int GetPositionCount(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].positionCount;
        }
        return 0;
    }
    
    // Get total exposure for symbol
    double GetSymbolExposure(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].totalExposure;
        }
        return 0.0;
    }
    
    // Check if we can open new position on symbol
    // bool CanOpenPosition(string symbol, double lots = 0.0)
    // {
    //     int index = FindSymbolIndex(symbol);
    //     if(index < 0) return false;
        
    //     SymbolData data = m_symbols[index];
        
    //     // Check position count limit
    //     if(data.positionCount >= data.maxPositions)
    //         return false;
        
    //     // Check exposure limit
    //     if(lots > 0)
    //     {
    //         double newExposure = CalculateExposure(symbol, lots);
    //         if((data.totalExposure + newExposure) > data.maxExposure)
    //             return false;
    //     }
        
    //     return true;
    // }
    
    // Update position tracking
    void UpdatePositionInfo(string symbol, double lots, bool isBuy)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0) return;
        
        m_symbols[index].positionCount++;
        m_symbols[index].totalExposure += CalculateExposure(symbol, lots);
    }

    // ============ CORRELATION MANAGEMENT ============

    // Calculate correlation matrix for all managed symbols
    void CalculateCorrelationMatrix(ENUM_TIMEFRAMES timeframe = PERIOD_H1, int period = 100)
    {
        int symbolCount = allAvailableSymbols;  // Use allAvailableSymbols instead of m_symbolCount
        int matrixSize = symbolCount * symbolCount;
        
        // Resize matrix if needed
        if(ArraySize(m_correlationMatrix) != matrixSize)
        {
            ArrayResize(m_correlationMatrix, matrixSize);
        }
        
        // Calculate correlations
        for(int i = 0; i < symbolCount; i++)
        {
            for(int j = 0; j < symbolCount; j++)
            {
                if(i == j)
                {
                    m_correlationMatrix[i * symbolCount + j] = 1.0; // Self-correlation
                }
                else
                {
                    double correlation = CalculateSymbolCorrelation(
                        m_symbols[i].symbol, 
                        m_symbols[j].symbol, 
                        timeframe, 
                        period
                    );
                    
                    m_correlationMatrix[i * symbolCount + j] = correlation;
                }
            }
        }
        
        if(ResourceManager != NULL)
        {
            ResourceManager.KeepNotes("SYSTEM", OBSERVE, "SymbolManager",
                StringFormat("Correlation matrix calculated for %d symbols", symbolCount));
        }
    }

    // Get correlation between two symbols
    double GetCorrelation(string symbol1, string symbol2)
    {
        int index1 = FindSymbolIndex(symbol1);
        int index2 = FindSymbolIndex(symbol2);
        
        if(index1 >= 0 && index2 >= 0 && ArraySize(m_correlationMatrix) > 0)
        {
            int symbolCount = m_symbolCount;
            return m_correlationMatrix[index1 * symbolCount + index2];
        }
        
        // Calculate on-demand if not in matrix
        return CalculateSymbolCorrelation(symbol1, symbol2);
    }
    
    double GetSymbolCorrelation(string symbol)
    {
        int index = FindSymbolIndex(symbol);  // Changed from GetSymbolIndex
        if(index < 0) return 0.0;
        
        double maxCorrelation = 0.0;
        int symbolCount = allAvailableSymbols;  // Use allAvailableSymbols
        
        for(int i = 0; i < symbolCount; i++)
        {
            if(i != index)
            {
                double correlation = MathAbs(m_correlationMatrix[index * symbolCount + i]);
                if(correlation > maxCorrelation)
                {
                    maxCorrelation = correlation;
                }
            }
        }
        
        return maxCorrelation;
    }

    // Find highly correlated pairs above threshold
    int FindHighlyCorrelatedPairs(string &pairs[][2], double &correlations[], 
                                double threshold = 0.7)
    {
        ArrayResize(pairs, 0);
        ArrayResize(correlations, 0);
        
        int pairCount = 0;
        int symbolCount = m_symbolCount;
        
        for(int i = 0; i < symbolCount; i++)
        {
            for(int j = i + 1; j < symbolCount; j++)
            {
                double correlation = MathAbs(m_correlationMatrix[i * symbolCount + j]);
                
                if(correlation > threshold)
                {
                    ArrayResize(pairs, pairCount + 1);
                    ArrayResize(correlations, pairCount + 1);
                    
                    pairs[pairCount][0] = m_symbols[i].symbol;
                    pairs[pairCount][1] = m_symbols[j].symbol;
                    correlations[pairCount] = correlation;
                    
                    pairCount++;
                }
            }
        }
        
        return pairCount;
    }

    // Get average correlation for a symbol
    double GetAverageCorrelation(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0 || ArraySize(m_correlationMatrix) == 0) return 0.0;
        
        double sum = 0.0;
        int count = 0;
        int symbolCount = m_symbolCount;
        
        for(int i = 0; i < symbolCount; i++)
        {
            if(i != index && m_symbols[i].enabled)
            {
                sum += MathAbs(m_correlationMatrix[index * symbolCount + i]);
                count++;
            }
        }
        
        return count > 0 ? sum / count : 0.0;
    }

    // Get portfolio average correlation
    double GetPortfolioAverageCorrelation()
    {
        if(ArraySize(m_correlationMatrix) == 0) return 0.0;
        
        double sum = 0.0;
        int count = 0;
        int symbolCount = m_symbolCount;
        
        for(int i = 0; i < symbolCount; i++)
        {
            if(m_symbols[i].enabled)
            {
                for(int j = i + 1; j < symbolCount; j++)
                {
                    if(m_symbols[j].enabled)
                    {
                        sum += MathAbs(m_correlationMatrix[i * symbolCount + j]);
                        count++;
                    }
                }
            }
        }
        
        return count > 0 ? sum / count : 0.0;
    }

    // Check if adding a position would exceed correlation limits
    bool CheckCorrelationLimit(string symbol, double threshold = 0.7)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0) return true;
        
        int symbolCount = m_symbolCount;
        
        // Check correlation with all enabled symbols with positions
        for(int i = 0; i < symbolCount; i++)
        {
            if(i != index && m_symbols[i].enabled && m_symbols[i].positionCount > 0)
            {
                double correlation = MathAbs(m_correlationMatrix[index * symbolCount + i]);
                if(correlation > threshold)
                {
                    if(ResourceManager != NULL)
                    {
                        ResourceManager.KeepNotes(symbol, WARN, "SymbolManager",
                            StringFormat("High correlation with %s: %.2f > %.2f",
                            m_symbols[i].symbol, correlation, threshold));
                    }
                    return false;
                }
            }
        }
        
        return true;
    }

    // Get correlated symbols for a given symbol
    void GetCorrelatedSymbols(string symbol, string &correlatedSymbols[], 
                            double &correlationValues[], double threshold = 0.6)
    {
        ArrayResize(correlatedSymbols, 0);
        ArrayResize(correlationValues, 0);
        
        int index = FindSymbolIndex(symbol);
        if(index < 0) return;
        
        int count = 0;
        int symbolCount = m_symbolCount;
        
        for(int i = 0; i < symbolCount; i++)
        {
            if(i != index && m_symbols[i].enabled)
            {
                double correlation = m_correlationMatrix[index * symbolCount + i];
                
                if(MathAbs(correlation) > threshold)
                {
                    ArrayResize(correlatedSymbols, count + 1);
                    ArrayResize(correlationValues, count + 1);
                    
                    correlatedSymbols[count] = m_symbols[i].symbol;
                    correlationValues[count] = correlation;
                    
                    count++;
                }
            }
        }
    }
    
    // ============ SYMBOL LIFECYCLE & CONFIGURATION ============
    
    // Add new symbol to manage
    bool AddSymbol(string symbol)
    {
        // Check if symbol already exists
        if(FindSymbolIndex(symbol) >= 0)
            return false;
        
        // Resize array
        int newIndex = allAvailableSymbols;
        allAvailableSymbols++;
        m_symbolCount = allAvailableSymbols;
        ArrayResize(m_symbols, allAvailableSymbols);
        
        // Initialize new symbol
        InitializeSymbolData(symbol, newIndex);
        
        if(ResourceManager != NULL)
        {
            ResourceManager.KeepNotes("SYSTEM", OBSERVE, "SymbolManager",
                StringFormat("Added new symbol: %s", symbol));
        }
        
        return true;
    }
    
    // Remove symbol from management
    bool RemoveSymbol(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index < 0) return false;
        
        // Shift array
        for(int i = index; i < allAvailableSymbols - 1; i++)
        {
            m_symbols[i] = m_symbols[i + 1];
        }
        
        allAvailableSymbols--;
        ArrayResize(m_symbols, allAvailableSymbols);
        
        if(ResourceManager != NULL)
        {
            ResourceManager.KeepNotes("SYSTEM", OBSERVE, "SymbolManager",
                StringFormat("Removed symbol: %s", symbol));
        }
        
        return true;
    }
    
    // Enable/disable symbol
    void SetSymbolEnabled(string symbol, bool enabled)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            m_symbols[index].enabled = enabled;
            m_symbols[index].status = enabled ? SYMBOL_TRADABLE : SYMBOL_DISABLED;
            
            if(ResourceManager != NULL)
            {
                string status = enabled ? "enabled" : "disabled";
                ResourceManager.KeepNotes(symbol, OBSERVE, "SymbolManager",
                    StringFormat("Symbol %s", status));
            }
        }
    }
    
    // Check if symbol is enabled
    bool IsSymbolEnabled(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].enabled;
        }
        return false;
    }
    
    // Set symbol trade priority (1-10)
    void SetSymbolPriority(string symbol, int priority)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            m_symbols[index].tradePriority = MathMax(1, MathMin(10, priority));
        }
    }
    
    // Get symbol priority
    int GetSymbolPriority(string symbol)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].tradePriority;
        }
        return 1;
    }
    
    // ============ GETTERS ============
    
    // Get all managed symbols
    void GetAllSymbols(string &symbols[])
    {
        ArrayResize(symbols, allAvailableSymbols);
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            symbols[i] = m_symbols[i].symbol;
        }
    }
    
    // Get tradable symbols
    void GetTradableSymbols(string &symbols[])
    {
        // Count tradable symbols first
        int count = 0;
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            if(IsSymbolTradable(m_symbols[i].symbol))
            {
                count++;
            }
        }
        
        // Resize array
        ArrayResize(symbols, count);
        
        // Fill array
        int index = 0;
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            if(IsSymbolTradable(m_symbols[i].symbol))
            {
                symbols[index] = m_symbols[i].symbol;
                index++;
            }
        }
    }
    
    // Get symbol count
    int GetSymbolCount() { return allAvailableSymbols; }
    
    // Get max symbols for account tier
    int GetMaxSymbolsForTier(int tier)
    {
        if(tier >= 1 && tier <= 5)
            return m_maxSymbolsPerAccountTier[tier - 1];
        return 1;
    }
    
    // Get max positions per symbol
    int GetMaxPositionsPerSymbol(string symbol = "")
    {
        if(symbol == "")
        {
            // Default value
            return 3;
        }
        
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            return m_symbols[index].maxPositions;
        }
        return 1;
    }
    
    // ============ SETTERS ============
    
    // Set max spread multiplier
    void SetMaxSpreadMultiplier(double multiplier)
    {
        m_maxSpreadMultiplier = MathMax(1.0, multiplier);
    }
    
    // Set minimum liquidity
    void SetMinLiquidity(double liquidity)
    {
        m_minLiquidity = MathMax(0.0, liquidity);
    }
    
    // Set max symbols per tier
    void SetMaxSymbolsPerTier(int tier, int maxSymbols)
    {
        if(tier >= 1 && tier <= 5)
        {
            m_maxSymbolsPerAccountTier[tier - 1] = MathMax(1, maxSymbols);
        }
    }
    
    // Set symbol-specific max positions
    void SetSymbolMaxPositions(string symbol, int maxPositions)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            m_symbols[index].maxPositions = MathMax(1, maxPositions);
        }
    }
    
    // Set symbol max exposure
    void SetSymbolMaxExposure(string symbol, double maxExposure)
    {
        int index = FindSymbolIndex(symbol);
        if(index >= 0)
        {
            m_symbols[index].maxExposure = MathMax(0.0, maxExposure);
        }
    }
    
private:
    // ============ PRIVATE HELPER FUNCTIONS ============
    
    // Find symbol index
    int FindSymbolIndex(string symbol)
    {
        for(int i = 0; i < allAvailableSymbols; i++)
        {
            if(m_symbols[i].symbol == symbol)
                return i;
        }
        return -1;
    }
    
    // Initialize symbol data
    void InitializeSymbolData(string symbol, int index)
    {
        SymbolData data;
        ZeroMemory(data);
        
        data.symbol = symbol;
        data.enabled = true;
        data.status = SYMBOL_TRADABLE;
        
        // Get symbol properties
        data.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        data.lotSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        data.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        data.pointValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        data.pipValue = CalculatePipValue(symbol);
        
        // Get limits
        data.minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        data.maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        data.volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        data.marginRequired = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        
        // Initialize market data
        data.bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        data.ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        data.spread = (data.ask - data.bid) / data.tickSize;
        data.lastPrice = SymbolInfoDouble(symbol, SYMBOL_LAST);
        data.lastUpdate = TimeCurrent();
        
        // Initialize risk tracking
        data.positionCount = 0;
        data.totalExposure = 0.0;
        data.maxExposure = 10000.0; // Default $10,000
        data.maxPositions = 3; // Default 3 positions
        
        // Initialize performance
        data.dailyHigh = SymbolInfoDouble(symbol, SYMBOL_LASTHIGH);
        data.dailyLow = SymbolInfoDouble(symbol, SYMBOL_LASTLOW);
        data.dailyRange = data.dailyHigh - data.dailyLow;
        data.avgSpread = data.spread;
        data.volatility = GetDailyVolatility(symbol);
        
        // Default configuration
        data.allowHedging = true;
        data.allowScalping = true;
        data.maxSpreadAllowed = 3.0; // 3 pips default
        data.tradePriority = 5; // Medium priority
        
        m_symbols[index] = data;
    }
    
    // Update symbol data
    void UpdateSymbolData(int index)
    {
        string symbol = m_symbols[index].symbol;
        
        // Update market data
        m_symbols[index].bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        m_symbols[index].ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        if(m_symbols[index].tickSize > 0)
        {
            m_symbols[index].spread = (m_symbols[index].ask - m_symbols[index].bid) / m_symbols[index].tickSize;
        }
        
        m_symbols[index].lastPrice = SymbolInfoDouble(symbol, SYMBOL_LAST);
        m_symbols[index].lastUpdate = TimeCurrent();
        
        // Update daily range
        m_symbols[index].dailyHigh = SymbolInfoDouble(symbol, SYMBOL_LASTHIGH);
        m_symbols[index].dailyLow = SymbolInfoDouble(symbol, SYMBOL_LASTLOW);
        m_symbols[index].dailyRange = m_symbols[index].dailyHigh - m_symbols[index].dailyLow;
        
        // Update average spread (exponential moving average)
        m_symbols[index].avgSpread = (m_symbols[index].avgSpread * 0.9) + (m_symbols[index].spread * 0.1);
        
        // Update volatility
        m_symbols[index].volatility = GetDailyVolatility(symbol);
        
        // Update position count
        m_symbols[index].positionCount = CountSymbolPositions(symbol);
    }
    
    // Calculate pip value
    double CalculatePipValue(string symbol)
    {
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        
        // For Forex, pip is usually 10 points
        double pipSize = tickSize * 10;
        
        if(pipSize > 0)
            return (tickValue / tickSize) * pipSize;
        
        return 0.0;
    }
    
    // Calculate exposure for a position
    double CalculateExposure(string symbol, double lots)
    {
        // Simplified exposure calculation
        double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        return lots * contractSize * price;
    }
    
    // Count positions for a symbol
    int CountSymbolPositions(string symbol)
    {
        int count = 0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                    count++;
            }
        }
        
        return count;
    }
    
    // Check if liquidity is sufficient
    bool IsLiquiditySufficient(string symbol)
    {
        // Simplified liquidity check
        // In real implementation, you might check volume or bid/ask sizes
        
        double volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_REAL);
        return volume >= m_minLiquidity;
    }

    // Calculate correlation between two symbols over a period
    double CalculateSymbolCorrelation(string symbol1, string symbol2, 
                                ENUM_TIMEFRAMES timeframe = PERIOD_H1, 
                                int period = 100)
    {
        // Get price data for both symbols
        double prices1[], prices2[];
        ArraySetAsSeries(prices1, true);
        ArraySetAsSeries(prices2, true);
        
        // Copy closing prices
        int copied1 = CopyClose(symbol1, timeframe, 0, period, prices1);
        int copied2 = CopyClose(symbol2, timeframe, 0, period, prices2);
        
        if(copied1 != period || copied2 != period || copied1 != copied2)
        {
            if(ResourceManager != NULL)  // Changed from RessourceManager
            {
                ResourceManager.KeepNotes("SYSTEM", WARN, "SymbolManager",
                    StringFormat("Cannot calculate correlation %s-%s: Insufficient data (%d/%d)",
                    symbol1, symbol2, copied1, copied2));
            }
            return 0.0;
        }
        
        // Calculate returns
        double returns1[], returns2[];
        ArrayResize(returns1, period - 1);
        ArrayResize(returns2, period - 1);
        
        for(int i = 0; i < period - 1; i++)
        {
            if(prices1[i+1] > 0 && prices2[i+1] > 0)
            {
                returns1[i] = (prices1[i] - prices1[i+1]) / prices1[i+1];
                returns2[i] = (prices2[i] - prices2[i+1]) / prices2[i+1];
            }
            else
            {
                returns1[i] = 0.0;
                returns2[i] = 0.0;
            }
        }
        
        // Calculate means
        double mean1 = 0.0, mean2 = 0.0;
        for(int i = 0; i < period - 1; i++)
        {
            mean1 += returns1[i];
            mean2 += returns2[i];
        }
        mean1 /= (period - 1);
        mean2 /= (period - 1);
        
        // Calculate covariance and variances
        double covariance = 0.0;
        double variance1 = 0.0;
        double variance2 = 0.0;
        
        for(int i = 0; i < period - 1; i++)
        {
            double diff1 = returns1[i] - mean1;
            double diff2 = returns2[i] - mean2;
            
            covariance += diff1 * diff2;
            variance1 += diff1 * diff1;
            variance2 += diff2 * diff2;
        }
        
        covariance /= (period - 2);
        variance1 /= (period - 2);
        variance2 /= (period - 2);
        
        // Calculate correlation coefficient
        if(variance1 > 0 && variance2 > 0)
        {
            double correlation = covariance / MathSqrt(variance1 * variance2);
            
            // Bound between -1 and 1
            correlation = MathMax(-1.0, MathMin(1.0, correlation));
            
            return correlation;
        }
        
        return 0.0;
    }
};

// Global instance
SymbolManager symbolManager;