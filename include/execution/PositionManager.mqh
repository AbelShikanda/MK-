//+------------------------------------------------------------------+
//| PositionManager.mqh - Simple OOP Position Management            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include "../config/inputs.mqh"
#include "../config/GlobalVariables.mqh"
#include "../utils/SymbolUtils.mqh"
#include "../utils/IndicatorUtils.mqh"
#include "../risk/RiskManager.mqh"
#include "../validation/ValidationEngine.mqh"
#include "OrderManager.mqh"
#include "../utils/System/sys.mqh"

//+------------------------------------------------------------------+
//| PositionManager Class                                            |
//+------------------------------------------------------------------+
class PositionManager
{
private:
    bool m_initialized;
    
    // Core properties
    string          m_expertComment;
    int             m_expertMagic;
    int             m_slippagePoints;
    ResourceManager *m_logger;           // Optional logger
    RiskManager     *m_riskManager;      // Risk manager instance
    
    // Trade counters
    int             m_dailyTradesCount;
    int             m_weeklyTradesCount;
    int             m_monthlyTradesCount;
    int             m_totalPositionsOpened;
    int             m_totalPositionsClosed;
    
    // Tier 1 Optimizations: Cached handles and frequently used values
    int             m_atrHandles[];
    double          m_cachedPoint[];
    static double   m_cachedPointGlobal;
    static double   m_cachedAccountBalance;
    static datetime m_lastBalanceCheck;
    static datetime m_lastRiskCheck;
    
    // Logging control
    static datetime m_lastStatusLog;
    static int      m_tickCounter;
    
public:
    // ================= CONSTRUCTOR & DESTRUCTOR =================
    PositionManager() : 
        m_initialized(false),
        m_expertComment(""),
        m_expertMagic(0),
        m_slippagePoints(0),
        m_logger(NULL),
        m_riskManager(NULL),
        m_dailyTradesCount(0),
        m_weeklyTradesCount(0),
        m_monthlyTradesCount(0),
        m_totalPositionsOpened(0),
        m_totalPositionsClosed(0)
    {
        // Constructor only sets default values - NO resource creation
        ArrayResize(m_atrHandles, 0, 100);
        ArrayResize(m_cachedPoint, 0, 100);
    }
    
    ~PositionManager()
    {
        // Destructor - call Deinitialize if needed
        if(m_initialized)
        {
            Deinitialize();
        }
        
        // Release all indicator handles
        for(int i = ArraySize(m_atrHandles) - 1; i >= 0; i--)
        {
            if(m_atrHandles[i] != INVALID_HANDLE)
            {
                IndicatorRelease(m_atrHandles[i]);
            }
        }
    }
    
    // ================= PROPER INITIALIZATION =================
    
    // CONSTRUCTOR ALTERNATIVE - Minimal initialization (if needed)
    void SetDefaults(string comment = "", int magic = 0, int slippage = 0)
    {
        // Only set values, no actual initialization
        m_expertComment = comment;
        m_expertMagic = magic;
        m_slippagePoints = slippage;
    }
    
    // INITIALIZE() - The ONE AND ONLY real initialization method
    bool Initialize(string comment, int magic, int slippage, 
                   ResourceManager *logger = NULL, RiskManager *riskManager = NULL)
    {
        // Early exit for invalid states
        if(m_initialized) 
        {
            Print("PositionManager already initialized!");
            return true;
        }
        
        // Set parameters
        m_expertComment = comment;
        m_expertMagic = magic;
        m_slippagePoints = slippage;
        m_logger = logger;
        m_riskManager = riskManager;
        
        // Reset counters
        m_dailyTradesCount = 0;
        m_weeklyTradesCount = 0;
        m_monthlyTradesCount = 0;
        m_totalPositionsOpened = 0;
        m_totalPositionsClosed = 0;
        
        // Initialize static logging variables
        m_lastStatusLog = 0;
        m_tickCounter = 0;
        
        // Mark as initialized
        m_initialized = true;
        
        PrintFormat("PositionManager successfully initialized: %s Magic: %d", comment, magic);
        return true;
    }
    
    // Deinitialize - cleanup counterpart
    void Deinitialize()
    {
        if(!m_initialized) return;
        
        // Reset all pointers to external dependencies
        m_logger = NULL;
        m_riskManager = NULL;
        
        // Reset initialization flag
        m_initialized = false;
        
        Print("PositionManager deinitialized");
    }
    
    // Check if initialized
    bool IsInitialized() const 
    { 
        return m_initialized; 
    }
    
    // ================= EVENT HANDLERS (PROTECTED) =================
    
    // OnTick() - ONLY processes if initialized
    void OnTick()
    {
        if(!m_initialized) return;
        
        // Increment tick counter for periodic logging
        m_tickCounter++;
        
        // Execute regular tick-based operations (minimal logging)
        CheckOpenPositions();
        UpdateTrailingStops();
        CheckProfitTargets();
        UpdateCounters();
    }
    
    // OnTimer() - ONLY processes if initialized
    void OnTimer()
    {
        if(!m_initialized) return;
        
        // Execute timer-based operations (called periodically)
        ResetDailyCountersIfNeeded();
        
        // Log status every 60 seconds
        datetime now = TimeCurrent();
        if(now > m_lastStatusLog + 60)
        {
            LogStatusUpdate();
            m_lastStatusLog = now;
        }
        
        CheckRiskLimits();
        UpdateStatistics();
    }
    
    // OnTradeTransaction() - ONLY processes if initialized
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                           const MqlTradeRequest& request,
                           const MqlTradeResult& result)
    {
        if(!m_initialized) return;
        
        // Handle ALL transaction types in one place
        switch(trans.type)
        {
            case TRADE_TRANSACTION_HISTORY_ADD:
                HandleHistoryAdd(trans);
                break;
                
            case TRADE_TRANSACTION_HISTORY_UPDATE:
                HandleHistoryUpdate(trans);
                break;
                
            case TRADE_TRANSACTION_HISTORY_DELETE:
                HandleHistoryDelete(trans);
                break;
                
            case TRADE_TRANSACTION_ORDER_ADD:
            case TRADE_TRANSACTION_ORDER_UPDATE:
            case TRADE_TRANSACTION_DEAL_ADD:
                ProcessTradeTransaction(trans, request, result);
                break;
            
            default:
                break;
        }
    }
    
    // ================= CORE TRADE FUNCTIONS =================
    
    // Open a new position
    bool OpenPosition(string symbol, bool isBuy, string reason = "ENTRY")
    {
        // Early exit conditions ordered from cheapest to most expensive
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        // Early exit for invalid symbol
        if(symbol == "")
            return false;
            
        if(!CanOpenNewPosition(symbol, isBuy))
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, WARN, "PositionManager", 
                    "Position opening validation failed");
            }
            return false;
        }
        
        // Use RiskManager for position size if available
        double lotSize = 0;
        if(m_riskManager != NULL)
        {
            // Get optimal stop loss from RiskManager first
            double entryPrice = GetEntryPrice(symbol, isBuy);
            double stopLoss = GetOptimalStopLoss(symbol, isBuy, entryPrice);
            double point = GetCachedPoint(symbol);
            double stopLossPips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
            
            // Cache account balance with 5-second TTL
            static datetime lastBalanceUpdate = 0;
            static double cachedBalance = 0;
            datetime now = TimeCurrent();
            if(now > lastBalanceUpdate + 5)
            {
                cachedBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                lastBalanceUpdate = now;
            }
            
            // Use RiskManager's position sizing
            lotSize = m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                symbol, cachedBalance, stopLossPips);
        }
        else
        {
            // Fallback to basic calculation
            lotSize = CalculatePositionSize(symbol, isBuy);
        }
        
        if(lotSize <= 0)
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, ENFORCE, "PositionManager", 
                    "Invalid lot size calculated");
            }
            return false;
        }
        
        // Calculate stop loss
        double entryPrice = GetEntryPrice(symbol, isBuy);
        double stopLoss = GetOptimalStopLoss(symbol, isBuy, entryPrice);
        
        // Validate stop loss with RiskManager if available
        if(m_riskManager != NULL)
        {
            m_riskManager.ValidateStopLossPlacement(symbol, stopLoss, entryPrice, isBuy);
        }
        
        // Calculate take profit
        double takeProfit = GetOptimalTakeProfit(symbol, isBuy, entryPrice, stopLoss);
        
        // Check exposure limits with RiskManager
        if(m_riskManager != NULL && !m_riskManager.CheckExposureLimits(symbol, lotSize))
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, ENFORCE, "PositionManager", 
                    "Exposure limits exceeded");
            }
            return false;
        }
        
        // Final permission check with RiskManager
        if(m_riskManager != NULL && !m_riskManager.AllowNewTrade(symbol, lotSize, reason))
        {
            if(m_logger != NULL)
            {
                m_logger.KeepNotes(symbol, ENFORCE, "PositionManager", 
                    "RiskManager blocked the trade");
            }
            return false;
        }
        
        // Execute trade
        bool result = ExecuteTrade(symbol, isBuy, lotSize, stopLoss, takeProfit, reason);
        
        if(result)
        {
            m_dailyTradesCount++;
            m_totalPositionsOpened++;
            
            // Log trade execution
            PrintFormat("OPENED: New %s position for %s | Lot: %.3f | Entry: %.5f | SL: %.5f | TP: %.5f | Reason: %s",
                isBuy ? "BUY" : "SELL", symbol, lotSize, entryPrice, stopLoss, takeProfit, reason);
            
            // Update RiskManager metrics
            if(m_riskManager != NULL)
            {
                double point = GetCachedPoint(symbol);
                double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
                double riskAmount = MathAbs(entryPrice - stopLoss) * lotSize * contractSize;
                m_riskManager.UpdatePerformanceMetrics(true, 0, riskAmount);
            }
        }
        
        return result;
    }
    
    // Add to existing position
    bool AddToPosition(string symbol, bool isBuy, string reason = "ADDITION")
    {
        // Early exit conditions
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        if(symbol == "")
            return false;
            
        if(!CanAddToPosition(symbol, isBuy))
        {
            return false;
        }
        
        // Check existing position direction
        if(GetPositionDirection(symbol) != (isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
        {
            return false;
        }
        
        // Get addition lot size
        double lotSize = 0;
        if(m_riskManager != NULL)
        {
            // Use RiskManager for position size
            double entryPrice = GetEntryPrice(symbol, isBuy);
            double avgStopLoss = GetAverageStopLoss(symbol, isBuy);
            if(avgStopLoss <= 0)
            {
                avgStopLoss = GetOptimalStopLoss(symbol, isBuy, entryPrice);
            }
            
            double point = GetCachedPoint(symbol);
            double stopLossPips = MathAbs(entryPrice - avgStopLoss) / (point * 10.0);
            
            // Cache account balance
            static datetime lastBalanceUpdate = 0;
            static double cachedBalance = 0;
            datetime now = TimeCurrent();
            if(now > lastBalanceUpdate + 5)
            {
                cachedBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                lastBalanceUpdate = now;
            }
            
            // Calculate progressive position size based on existing positions
            double progressiveMultiplier = 1.0 + (GetPositionCount(symbol) * 0.2);
            lotSize = m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                symbol, cachedBalance, stopLossPips);
            lotSize *= progressiveMultiplier;
        }
        else
        {
            // Fallback to basic calculation
            lotSize = CalculateProgressiveLotSize(symbol);
        }
        
        if(lotSize <= 0)
        {
            return false;
        }
        
        // Use average stop loss from existing positions
        double avgStopLoss = GetAverageStopLoss(symbol, isBuy);
        double entryPrice = GetEntryPrice(symbol, isBuy);
        
        // If no average stop loss, calculate new one
        if(avgStopLoss <= 0)
        {
            avgStopLoss = GetOptimalStopLoss(symbol, isBuy, entryPrice);
        }
        
        // Validate stop loss with RiskManager if available
        if(m_riskManager != NULL)
        {
            m_riskManager.ValidateStopLossPlacement(symbol, avgStopLoss, entryPrice, isBuy);
        }
        
        // Calculate take profit
        double takeProfit = GetOptimalTakeProfit(symbol, isBuy, entryPrice, avgStopLoss);
        
        // Check exposure limits with RiskManager
        if(m_riskManager != NULL && !m_riskManager.CheckExposureLimits(symbol, lotSize))
        {
            return false;
        }
        
        // Final permission check with RiskManager
        if(m_riskManager != NULL && !m_riskManager.AllowNewTrade(symbol, lotSize, reason))
        {
            return false;
        }
        
        // Execute addition trade
        bool result = ExecuteTrade(symbol, isBuy, lotSize, avgStopLoss, takeProfit, reason);
        
        if(result)
        {
            m_dailyTradesCount++;
            m_totalPositionsOpened++;
            
            // Log trade addition
            PrintFormat("ADDED: Additional %s position for %s | Lot: %.3f | Entry: %.5f | SL: %.5f | TP: %.5f | Reason: %s",
                isBuy ? "BUY" : "SELL", symbol, lotSize, entryPrice, avgStopLoss, takeProfit, reason);
            
            // Update RiskManager metrics
            if(m_riskManager != NULL)
            {
                double point = GetCachedPoint(symbol);
                double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
                double riskAmount = MathAbs(entryPrice - avgStopLoss) * lotSize * contractSize;
                m_riskManager.UpdatePerformanceMetrics(true, 0, riskAmount);
            }
        }
        
        return result;
    }
    
    // Close all positions for a symbol
    bool CloseAllPositions(string symbol)
    {
        // Early exit
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        if(symbol == "")
            return false;
            
        int totalPositions = PositionsTotal();
        int closedCount = 0;
        double totalProfit = 0;
        
        // Use backward iteration for series arrays
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    double profit = PositionGetDouble(POSITION_PROFIT);
                    if(ClosePosition(ticket))
                    {
                        closedCount++;
                        totalProfit += profit;
                    }
                }
            }
        }
        
        if(closedCount > 0)
        {
            m_totalPositionsClosed += closedCount;
            
            PrintFormat("Closed %d positions for %s | Profit: %.2f", 
                      closedCount, symbol, totalProfit);
            
            // Update RiskManager metrics
            if(m_riskManager != NULL)
            {
                m_riskManager.UpdatePerformanceMetrics((totalProfit > 0), totalProfit, 0);
            }
        }
        
        return (closedCount > 0);
    }
    
    // Close specific position by ticket
    bool ClosePosition(ulong ticket)
    {
        // Early exit
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        if(ticket <= 0)
            return false;
            
        CTrade trade;
        trade.SetExpertMagicNumber(m_expertMagic);
        trade.SetDeviationInPoints(m_slippagePoints);
        
        bool result = trade.PositionClose(ticket, m_slippagePoints);
        
        if(result)
        {
            m_totalPositionsClosed++;
            
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                string symbol = PositionGetString(POSITION_SYMBOL);
                
                PrintFormat("Position %d closed for %s: $%.2f", (int)ticket, symbol, profit);
            }
        }
        
        return result;
    }
    
    // ================= VALIDATION FUNCTIONS =================
    
    bool CanOpenNewPosition(string symbol, bool isBuy)
    {
        // Early exit conditions
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        if(symbol == "")
            return false;
            
        // Use RiskManager validation first if available
        if(m_riskManager != NULL)
        {
            // Check if RiskManager allows new trades (cached check)
            static datetime lastRiskCheck = 0;
            static bool cachedCanTrade = true;
            datetime now = TimeCurrent();
            if(now > lastRiskCheck + 2) // 2-second cache
            {
                cachedCanTrade = m_riskManager.CanOpenNewTrades();
                lastRiskCheck = now;
            }
            
            if(!cachedCanTrade)
            {
                return false;
            }
            
            // Check RiskManager's permission for this specific trade
            if(!m_riskManager.AllowNewTrade(symbol, 0.01, "Pre-validation check"))
            {
                return false;
            }
            
            // Check volatility and spread with caching
            static string lastVolatilitySymbol = "";
            static datetime lastVolatilityCheck = 0;
            static bool cachedVolatility = true;
            
            if(symbol != lastVolatilitySymbol || now > lastVolatilityCheck + 5)
            {
                cachedVolatility = m_riskManager.IsVolatilityAcceptable(symbol) && 
                                  m_riskManager.IsSpreadAcceptable(symbol);
                lastVolatilitySymbol = symbol;
                lastVolatilityCheck = now;
            }
            
            if(!cachedVolatility)
            {
                return false;
            }
            
            // Check margin sufficiency
            double estimatedLots = 0.01; // Minimal lot for checking
            if(!m_riskManager.IsMarginSufficient(symbol, estimatedLots))
            {
                return false;
            }
        }
        
        // Basic symbol validation
        if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE))
        {
            return false;
        }
        
        // Max trades per symbol check
        if(GetPositionCount(symbol) >= MaxTradesPerSymbol)
        {
            return false;
        }
        
        return true;
    }
    
    bool CanAddToPosition(string symbol, bool isBuy)
    {
        // Early exit
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        if(symbol == "")
            return false;
            
        if(!CanOpenNewPosition(symbol, isBuy))
        {
            return false;
        }
        
        // Check if we have existing positions in same direction
        int existingPositions = GetPositionCount(symbol, isBuy);
        if(existingPositions == 0)
        {
            return false;
        }
        
        // Check addition distance
        double currentPrice = GetEntryPrice(symbol, isBuy);
        double avgPrice = GetAveragePrice(symbol, isBuy);
        double allowedDistance = CalculateAllowedAdditionDistance(symbol);
        double distance = MathAbs(currentPrice - avgPrice);
        
        if(distance > allowedDistance)
        {
            return false;
        }
        
        return true;
    }
    
    // ================= POSITION ANALYSIS =================
    
    int GetPositionCount(string symbol = "", bool isBuy = NULL)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        int totalPositions = PositionsTotal();
        int count = 0;
        
        // Use backward iteration and cache array size
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                
                // Check symbol filter
                if(symbol != "" && posSymbol != symbol)
                    continue;
                
                // Check direction filter
                if(isBuy != NULL)
                {
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    if((isBuy && posType != POSITION_TYPE_BUY) || 
                       (!isBuy && posType != POSITION_TYPE_SELL))
                        continue;
                }
                
                count++;
            }
        }
        
        return count;
    }
    
    double GetAveragePrice(string symbol, bool isBuy)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        int totalPositions = PositionsTotal();
        double totalPrice = 0;
        double totalVolume = 0;
        
        // Use backward iteration
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    
                    if((isBuy && posType == POSITION_TYPE_BUY) || 
                       (!isBuy && posType == POSITION_TYPE_SELL))
                    {
                        double price = PositionGetDouble(POSITION_PRICE_OPEN);
                        double volume = PositionGetDouble(POSITION_VOLUME);
                        
                        totalPrice += price * volume;
                        totalVolume += volume;
                    }
                }
            }
        }
        
        if(totalVolume > 0)
        {
            static int cachedDigits = -1;
            if(cachedDigits == -1)
                cachedDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                
            return NormalizeDouble(totalPrice / totalVolume, cachedDigits);
        }
        
        return 0;
    }
    
    double GetAverageStopLoss(string symbol, bool isBuy)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        int totalPositions = PositionsTotal();
        double totalSL = 0;
        int count = 0;
        
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    
                    if((isBuy && posType == POSITION_TYPE_BUY) || 
                       (!isBuy && posType == POSITION_TYPE_SELL))
                    {
                        totalSL += PositionGetDouble(POSITION_SL);
                        count++;
                    }
                }
            }
        }
        
        if(count > 0)
        {
            static int cachedDigits = -1;
            if(cachedDigits == -1)
                cachedDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                
            return NormalizeDouble(totalSL / count, cachedDigits);
        }
        
        return 0;
    }
    
    double GetTotalProfit(string symbol = "")
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        int totalPositions = PositionsTotal();
        double totalProfit = 0;
        
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                
                if(symbol == "" || posSymbol == symbol)
                {
                    totalProfit += PositionGetDouble(POSITION_PROFIT);
                }
            }
        }
        
        return totalProfit;
    }
    
    ENUM_POSITION_TYPE GetPositionDirection(string symbol)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return WRONG_VALUE;
        }
        
        if(symbol == "")
            return WRONG_VALUE;
            
        int totalPositions = PositionsTotal();
        
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                }
            }
        }
        
        return WRONG_VALUE;
    }
    
    // ================= CALCULATION FUNCTIONS =================
    
    double CalculatePositionSize(string symbol, bool isBuy)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        double lotSize = 0;
        // Use RiskManager for position sizing
        double entryPrice = GetEntryPrice(symbol, isBuy);
        double stopLoss = GetOptimalStopLoss(symbol, isBuy, entryPrice);
        double point = GetCachedPoint(symbol);
        double stopLossPips = MathAbs(entryPrice - stopLoss) / (point * 10.0);
        
        if(m_riskManager != NULL)
        {
            // Cache account balance
            static datetime lastBalanceUpdate = 0;
            static double cachedBalance = 0;
            datetime now = TimeCurrent();
            if(now > lastBalanceUpdate + 5)
            {
                cachedBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                lastBalanceUpdate = now;
            }
            
            lotSize = m_riskManager.CalculateRiskAdjustedPositionSizeFromCapital(
                symbol, cachedBalance, stopLossPips);
        }
        else
        {
            // Fallback to progressive position sizing
            lotSize = CalculateProgressiveLotSize(symbol);
        }
        
        // Apply min/max constraints
        static double cachedMinLot = -1;
        static double cachedMaxLot = -1;
        
        if(cachedMinLot == -1)
            cachedMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(cachedMaxLot == -1)
            cachedMaxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        
        if(lotSize < cachedMinLot) lotSize = cachedMinLot;
        if(lotSize > cachedMaxLot) lotSize = cachedMaxLot;
        
        return NormalizeDouble(lotSize, 2);
    }
    
    double CalculateProgressiveLotSize(string symbol)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        // Start with base lot
        double baseLot = 0.01;
        
        // Increase based on number of existing positions
        int existingPositions = GetPositionCount(symbol);
        double multiplier = 1.0 + (existingPositions * 0.2); // 20% increase per addition
        
        double lotSize = baseLot * multiplier;
        
        // Apply constraints
        static double cachedMinLot = -1;
        static double cachedMaxLot = -1;
        
        if(cachedMinLot == -1)
            cachedMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(cachedMaxLot == -1)
            cachedMaxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        
        if(lotSize < cachedMinLot) lotSize = cachedMinLot;
        if(lotSize > cachedMaxLot) lotSize = cachedMaxLot;
        
        return NormalizeDouble(lotSize, 2);
    }
    
    // Get optimal stop loss using RiskManager or fallback
    double GetOptimalStopLoss(string symbol, bool isBuy, double entryPrice)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        double stopLoss = 0;
        
        if(m_riskManager != NULL)
        {
            stopLoss = m_riskManager.GetOptimalStopLoss(symbol, entryPrice, isBuy);
        }
        else
        {
            stopLoss = CalculateDefaultStopLoss(symbol, isBuy, entryPrice);
        }
        
        return stopLoss;
    }
    
    double CalculateDefaultStopLoss(string symbol, bool isBuy, double entryPrice)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        // ADD THIS NULL CHECK
        if(m_riskManager == NULL)
        {
            // Fallback to fixed stop loss
            double point = GetCachedPoint(symbol);
            double stopDistance = 100.0 * point * 10; // 100 pips as fallback
            
            static int cachedDigits = -1;
            if(cachedDigits == -1)
                cachedDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            
            if(isBuy)
                return NormalizeDouble(entryPrice - stopDistance, cachedDigits);
            else
                return NormalizeDouble(entryPrice + stopDistance, cachedDigits);
        }
        
        double point = GetCachedPoint(symbol);
        double minStopLossPips = m_riskManager.GetMinimumStopLoss(symbol);
        
        // Try ATR-based stop loss first
        double atrStop = CalculateATRStopLoss(symbol, entryPrice, isBuy);
        if(atrStop > 0) return atrStop;
        
        // Fallback: fixed stop loss
        double stopDistance = minStopLossPips * point * 10;
        
        static int cachedDigits = -1;
        if(cachedDigits == -1)
            cachedDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        if(isBuy)
            return NormalizeDouble(entryPrice - stopDistance, cachedDigits);
        else
            return NormalizeDouble(entryPrice + stopDistance, cachedDigits);
    }
    
    // Get optimal take profit using RiskManager or fallback
    double GetOptimalTakeProfit(string symbol, bool isBuy, double entryPrice, double stopLoss)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        double takeProfit = 0;
        
        if(m_riskManager != NULL)
        {
            takeProfit = m_riskManager.GetOptimalTakeProfit(symbol, PERIOD_H1, entryPrice, stopLoss, isBuy);
        }
        else
        {
            takeProfit = CalculateDefaultTakeProfit(symbol, isBuy, entryPrice, stopLoss);
        }
        
        return takeProfit;
    }
    
    double CalculateDefaultTakeProfit(string symbol, bool isBuy, double entryPrice, double stopLoss)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        double riskReward = RiskRewardRatio;
        if(riskReward <= 0) riskReward = 1.5;
        
        double stopDistance = MathAbs(entryPrice - stopLoss);
        double takeProfitDistance = stopDistance * riskReward;
        
        if(isBuy)
            return entryPrice + takeProfitDistance;
        else
            return entryPrice - takeProfitDistance;
    }
    
    double CalculateATRStopLoss(string symbol, double entryPrice, bool isBuy = true)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        ENUM_TIMEFRAMES timeframe = PERIOD_M15;
        int atrPeriod = 14;
        
        // Get or create cached ATR handle
        int handleIndex = GetSymbolIndex(symbol);
        if(handleIndex >= 0 && m_atrHandles[handleIndex] != INVALID_HANDLE)
        {
            double atrValue[1];
            if(CopyBuffer(m_atrHandles[handleIndex], 0, 0, 1, atrValue) >= 1)
            {
                double atrMultiplier = 1.5;
                double atrStop = atrValue[0] * atrMultiplier;
                
                static int cachedDigits = -1;
                if(cachedDigits == -1)
                    cachedDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                
                double stopPrice;
                if(isBuy)
                    stopPrice = entryPrice - atrStop;
                else
                    stopPrice = entryPrice + atrStop;
                
                return NormalizeDouble(stopPrice, cachedDigits);
            }
        }
        
        return 0;
    }
    
    double CalculateAllowedAdditionDistance(string symbol)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return 0;
        }
        
        if(symbol == "")
            return 0;
            
        double point = GetCachedPoint(symbol);
        double atrValue[1];
        
        // Use cached ATR handle
        int handleIndex = GetSymbolIndex(symbol);
        if(handleIndex >= 0 && m_atrHandles[handleIndex] != INVALID_HANDLE)
        {
            if(CopyBuffer(m_atrHandles[handleIndex], 0, 0, 1, atrValue) >= 1)
            {
                return atrValue[0] * 0.5; // Allow within half ATR
            }
        }
        
        return 50 * point * 10; // Fallback: 50 pips
    }
    
    bool HasSufficientMargin(string symbol, bool isBuy)
    {
        if(!m_initialized) 
        {
            Print("Error: PositionManager not initialized!");
            return false;
        }
        
        // Cache margin checks with 2-second TTL
        static datetime lastMarginCheck = 0;
        static double cachedFreeMargin = 0;
        static double cachedEquity = 0;
        datetime now = TimeCurrent();
        
        if(now > lastMarginCheck + 2)
        {
            cachedFreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            cachedEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            lastMarginCheck = now;
        }
        
        // Minimum 10% free margin
        return (cachedFreeMargin >= (cachedEquity * 0.1));
    }
    
    // Check if trading is allowed by RiskManager
    bool IsTradingAllowed()
    {
        if(m_riskManager != NULL)
        {
            // Cache with 2-second TTL
            static datetime lastAllowedCheck = 0;
            static bool cachedAllowed = true;
            datetime now = TimeCurrent();
            
            if(now > lastAllowedCheck + 2)
            {
                cachedAllowed = m_riskManager.CanOpenNewTrades();
                lastAllowedCheck = now;
            }
            
            return cachedAllowed;
        }
        return true;
    }
    
    // Get current drawdown from RiskManager
    double GetCurrentDrawdown()
    {
        if(m_riskManager != NULL)
        {
            // Cache with 5-second TTL
            static datetime lastDrawdownCheck = 0;
            static double cachedDrawdown = 0;
            datetime now = TimeCurrent();
            
            if(now > lastDrawdownCheck + 5)
            {
                cachedDrawdown = m_riskManager.GetCurrentDrawdown();
                lastDrawdownCheck = now;
            }
            
            return cachedDrawdown;
        }
        return 0.0;
    }
    
    // ================= INTERNAL TICK/TIMER METHODS =================
    
private:
    void CheckOpenPositions()
    {
        int totalPositions = PositionsTotal();
        
        // Use backward iteration
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                // Update position metrics
                UpdatePositionMetrics(ticket);
                
                // Check for profit targets
                CheckPositionProfitTarget(ticket);
            }
        }
    }
    
    void UpdateTrailingStops()
    {
        if(m_riskManager != NULL)
        {
            m_riskManager.UpdateTrailingStops();
        }
    }
    
    void CheckProfitTargets()
    {
        int totalPositions = PositionsTotal();
        
        // Check if any positions have reached profit targets
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                double takeProfit = PositionGetDouble(POSITION_TP);
                
                // Check if profit target reached
                if(takeProfit > 0 && profit > 0)
                {
                    // Optional: Close or adjust position
                }
            }
        }
    }
    
    void UpdateCounters()
    {
        // Update internal counters based on current positions
        // Minimal logging in hot path
    }
    
    void ResetDailyCountersIfNeeded()
    {
        // Check if it's a new day
        MqlDateTime currentTime;
        TimeToStruct(TimeCurrent(), currentTime);
        
        static int lastDay = -1;
        if(lastDay == -1)
        {
            lastDay = currentTime.day;
        }
        
        if(currentTime.day != lastDay)
        {
            // Reset daily counters
            m_dailyTradesCount = 0;
            lastDay = currentTime.day;
        }
    }
    
    void LogStatusUpdate()
    {
        // Log periodic status update every 60 seconds
        if(m_logger != NULL)
        {
            m_logger.KeepNotes("SYSTEM", OBSERVE, "PositionManager", 
                StringFormat("Status update - Active positions: %d, Daily trades: %d", 
                PositionsTotal(), m_dailyTradesCount));
        }
    }
    
    void CheckRiskLimits()
    {
        if(m_riskManager != NULL)
        {
            // Check if risk limits are being approached
            double drawdown = GetCurrentDrawdown();
            if(drawdown > 20.0) // 20% drawdown threshold
            {
                if(m_logger != NULL)
                {
                    m_logger.KeepNotes("SYSTEM", WARN, "PositionManager", 
                        StringFormat("Drawdown approaching limits: %.1f%%", drawdown));
                }
            }
        }
    }
    
    void UpdateStatistics()
    {
        // Update weekly and monthly statistics
        static datetime lastWeekCheck = 0;
        static datetime lastMonthCheck = 0;
        
        datetime now = TimeCurrent();
        
        // Check weekly reset
        if(now - lastWeekCheck >= 7 * 24 * 60 * 60)
        {
            m_weeklyTradesCount = 0;
            lastWeekCheck = now;
        }
        
        // Check monthly reset
        MqlDateTime timeStruct;
        TimeToStruct(now, timeStruct);
        if(timeStruct.mon != lastMonthCheck)
        {
            m_monthlyTradesCount = 0;
            lastMonthCheck = timeStruct.mon;
        }
    }
    
    // ================= UTILITY FUNCTIONS =================
    
    double GetEntryPrice(string symbol, bool isBuy)
    {
        if(symbol == "")
            return 0;
            
        double price = 0;
        if(isBuy)
            price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        else
            price = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        return price;
    }
    
    bool ExecuteTrade(string symbol, bool isBuy, double lotSize, 
                     double stopLoss, double takeProfit, string reason)
    {
        if(symbol == "")
            return false;
            
        CTrade trade;
        trade.SetExpertMagicNumber(m_expertMagic);
        trade.SetDeviationInPoints(m_slippagePoints);
        
        string comment = m_expertComment + "_" + reason;
        
        bool result = false;
        if(isBuy)
        {
            result = trade.Buy(lotSize, symbol, 0, stopLoss, takeProfit, comment);
        }
        else
        {
            result = trade.Sell(lotSize, symbol, 0, stopLoss, takeProfit, comment);
        }
        
        return result;
    }
    
    void LogTradeOpened(string symbol, bool isBuy, double lotSize, double entryPrice,
                       double stopLoss, double takeProfit, string reason)
    {
        // Preserved for backward compatibility
        PrintFormat("OPENED: New %s position for %s | Lot: %.3f | Entry: %.5f | SL: %.5f | TP: %.5f | Reason: %s",
            isBuy ? "BUY" : "SELL", symbol, lotSize, entryPrice, stopLoss, takeProfit, reason);
    }
    
    void LogTradeAdded(string symbol, bool isBuy, double lotSize, double entryPrice,
                      double stopLoss, double takeProfit, string reason)
    {
        // Preserved for backward compatibility
        PrintFormat("ADDED: Additional %s position for %s | Lot: %.3f | Entry: %.5f | SL: %.5f | TP: %.5f | Reason: %s",
            isBuy ? "BUY" : "SELL", symbol, lotSize, entryPrice, stopLoss, takeProfit, reason);
    }
    
    void LogMessage(string message, string type, string source)
    {
        // String optimization
        string formatted = StringFormat("[%s][%s] %s", type, source, message);
        Print(formatted);
    }
    
    // ================= HELPER METHODS FOR TRADE TRANSACTIONS =================
    
    void UpdateTradeMetrics(const MqlTradeTransaction &trans)
    {
        // Update trade metrics based on transaction
        // Minimal logging
    }
    
    void LogTransaction(const MqlTradeTransaction &trans, const MqlTradeResult &result)
    {
        // Minimal logging - only errors
        if(result.retcode != TRADE_RETCODE_DONE)
        {
            PrintFormat("Transaction error: %d - %s", result.retcode, result.comment);
        }
    }
    
    void HandleNewDeal(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleDealUpdate(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleDealDelete(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleNewOrder(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleOrderUpdate(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleOrderDelete(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandlePositionChange(const MqlTradeTransaction &trans)
    {
        // Minimal logging
    }
    
    void HandleRequestProcessed(const MqlTradeTransaction &trans,
                               const MqlTradeRequest& request,
                               const MqlTradeResult& result)
    {
        // Only log failures
        if(result.retcode != 10009)
        {
            PrintFormat("Request failed: Retcode %d - %s", result.retcode, result.comment);
        }
    }
    
    void UpdatePositionMetrics(ulong ticket)
    {
        // Minimal logging
    }
    
    void CheckPositionProfitTarget(ulong ticket)
    {
        // Check if position has reached profit target
        if(PositionSelectByTicket(ticket))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            double takeProfit = PositionGetDouble(POSITION_TP);
            
            if(takeProfit > 0 && profit > 0)
            {
                // Optional: Implement profit target logic
            }
        }
    }
    
    // ================================================
    // IMPLEMENTATION OF HandleHistoryAdd
    // ================================================
    void HandleHistoryAdd(const MqlTradeTransaction &trans)
    {
        // When a deal is added to history, it usually means a position was closed
        if(trans.deal > 0)
        {
            // Select the deal to get details
            if(HistoryDealSelect(trans.deal))
            {
                long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
                string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
                double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                long position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                
                // Check if this is a closing deal (position close)
                if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
                {
                    // This is an opening deal (new position)
                }
                else if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
                {
                    // This is a closing deal (position closed)
                    PrintFormat("Position closed: %I64u, Symbol: %s, Profit: %.2f", 
                               trans.deal, symbol, profit);
                    
                    // Update your position tracking
                    UpdateClosedPosition(position_id, profit);
                }
            }
        }
        
        // Refresh your internal state
        RefreshPositions();
    }
    
    // ================================================
    // IMPLEMENTATION OF HandleHistoryUpdate
    // ================================================
    void HandleHistoryUpdate(const MqlTradeTransaction &trans)
    {
        // Minimal logging for history updates
    }
    
    // ================================================
    // IMPLEMENTATION OF HandleHistoryDelete
    // ================================================
    void HandleHistoryDelete(const MqlTradeTransaction &trans)
    {
        // Only log warnings for history deletions
        PrintFormat("WARNING: HistoryDelete - Order: %I64u, Deal: %I64u", 
                   trans.order, trans.deal);
        
        // Remove from your tracking if you have cached history
        if(trans.deal > 0)
        {
            RemoveDealFromCache(trans.deal);
        }
        
        if(trans.order > 0)
        {
            RemoveOrderFromCache(trans.order);
        }
        
        // Force refresh of all history
        HistorySelect(TimeCurrent() - 86400, TimeCurrent());
    }
    
    // ================================================
    // IMPLEMENTATION OF ProcessTradeTransaction
    // ================================================
    void ProcessTradeTransaction(const MqlTradeTransaction& trans,
                                const MqlTradeRequest& request,
                                const MqlTradeResult& result)
    {
        // Handle different transaction types for active trades
        switch(trans.type)
        {
            case TRADE_TRANSACTION_ORDER_ADD:
                // Handle new order
                HandleNewOrder(trans, request);
                break;
                
            case TRADE_TRANSACTION_ORDER_UPDATE:
                // Handle order modification
                HandleOrderUpdate(trans, request);
                break;
                
            case TRADE_TRANSACTION_DEAL_ADD:
                // Handle executed deal
                HandleNewDeal(trans, result);
                break;
        }
        
        // Update positions after any trade transaction
        RefreshPositions();
    }
    
    // ================================================
    // HELPER FUNCTIONS (You need to implement these too)
    // ================================================

    void UpdateClosedPosition(long position_id, double profit)
    {
        // Implement: Update your closed positions tracking
    }
    
    void RefreshPositions()
    {
        // Implement: Refresh your active positions list
        // This is typically done using PositionSelect()
    }
    
    void UpdateDealProfit(ulong deal_id, double new_profit)
    {
        // Implement: Update profit tracking for a deal
    }
    
    void RemoveDealFromCache(ulong deal_id)
    {
        // Implement: Remove deal from your cache
    }
    
    void RemoveOrderFromCache(ulong order_id)
    {
        // Implement: Remove order from your cache
    }
    
    void HandleNewOrder(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
    {
        // Implement: Handle new order placement
    }
    
    void HandleOrderUpdate(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
    {
        // Implement: Handle order modification
    }
    
    void HandleNewDeal(const MqlTradeTransaction& trans, const MqlTradeResult& result)
    {
        // Implement: Handle executed deal
    }
    
    // ================= OPTIMIZATION HELPER METHODS =================
    
private:
    // Get cached point value for symbol
    double GetCachedPoint(string symbol)
    {
        if(symbol == "")
            return 0;
            
        int index = GetSymbolIndex(symbol);
        if(index >= 0 && m_cachedPoint[index] > 0)
        {
            return m_cachedPoint[index];
        }
        
        // Cache point value
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(index >= 0)
        {
            m_cachedPoint[index] = point;
        }
        return point;
    }
    
    // Get index for symbol in cache arrays
    int GetSymbolIndex(string symbol)
    {
        // Simple linear search - optimize if many symbols
        for(int i = 0; i < ArraySize(m_atrHandles); i++)
        {
            // We'll need to store symbol names if we want to map them properly
            // For now, this is a placeholder
        }
        
        // If not found, add new entry
        int size = ArraySize(m_atrHandles);
        ArrayResize(m_atrHandles, size + 1);
        ArrayResize(m_cachedPoint, size + 1);
        
        // Create ATR handle
        m_atrHandles[size] = iATR(symbol, PERIOD_M15, 14);
        m_cachedPoint[size] = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        return size;
    }
    
    // ================= GETTERS & SETTERS =================
    
    // Getters
    string GetExpertComment() const { return m_expertComment; }
    int GetExpertMagic() const { return m_expertMagic; }
    int GetSlippagePoints() const { return m_slippagePoints; }
    int GetDailyTradesCount() const { return m_dailyTradesCount; }
    int GetWeeklyTradesCount() const { return m_weeklyTradesCount; }
    int GetMonthlyTradesCount() const { return m_monthlyTradesCount; }
    int GetTotalPositionsOpened() const { return m_totalPositionsOpened; }
    int GetTotalPositionsClosed() const { return m_totalPositionsClosed; }
    ResourceManager* GetLogger() const { return m_logger; }
    RiskManager* GetRiskManager() const { return m_riskManager; }
    
    // Setters
    void SetExpertComment(string comment) { 
        m_expertComment = comment; 
    }
    
    void SetExpertMagic(int magic) { 
        m_expertMagic = magic; 
    }
    
    void SetSlippagePoints(int slippage) { 
        m_slippagePoints = slippage; 
    }
    
    void SetLogger(ResourceManager *pm_logger) { 
        m_logger = pm_logger; 
    }
    
    void SetRiskManager(RiskManager *pm_riskManager) { 
        m_riskManager = pm_riskManager; 
    }
    
    // Reset counters
    void ResetDailyCounter() { 
        m_dailyTradesCount = 0; 
    }
    
    void ResetAllCounters() { 
        m_dailyTradesCount = 0;
        m_weeklyTradesCount = 0;
        m_monthlyTradesCount = 0;
        m_totalPositionsOpened = 0;
        m_totalPositionsClosed = 0;
    }
    
    void IncrementDailyCounter() { 
        m_dailyTradesCount++; 
    }
    
    // ================= RISK MANAGER INTEGRATION HELPERS =================
    
    // Apply trailing stops using RiskManager
    void ApplyTrailingStops()
    {
        if(m_riskManager != NULL)
        {
            m_riskManager.UpdateTrailingStops();
        }
    }
    
    // Secure profits using RiskManager
    void SecureProfits()
    {
        if(m_riskManager != NULL)
        {
            int totalPositions = PositionsTotal();
            for(int i = totalPositions - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(PositionSelectByTicket(ticket))
                {
                    m_riskManager.SecureProfit(ticket);
                }
            }
        }
    }
    
    // Move stop to breakeven using RiskManager
    bool MoveStopToBreakeven(ulong ticket)
    {
        if(m_riskManager != NULL)
        {
            return m_riskManager.MoveStopToBreakeven(ticket);
        }
        return false;
    }
    
    // Get current risk level from RiskManager
    string GetCurrentRiskLevel()
    {
        if(m_riskManager != NULL)
        {
            ENUM_RISK_LEVEL riskLevel = m_riskManager.GetRiskLevel();
            string riskLevelStr;
            
            switch(riskLevel)
            {
                case RISK_CRITICAL: riskLevelStr = "CRITICAL"; break;
                case RISK_HIGH: riskLevelStr = "HIGH"; break;
                case RISK_MODERATE: riskLevelStr = "MODERATE"; break;
                case RISK_LOW: riskLevelStr = "LOW"; break;
                case RISK_OPTIMAL: riskLevelStr = "OPTIMAL"; break;
                default: riskLevelStr = "UNKNOWN"; break;
            }
            
            return riskLevelStr;
        }
        return "UNKNOWN";
    }
    
    // Get daily PnL from RiskManager
    double GetDailyPnL()
    {
        if(m_riskManager != NULL)
        {
            // Cache with 5-second TTL
            static datetime lastPnLCheck = 0;
            static double cachedPnL = 0;
            datetime now = TimeCurrent();
            
            if(now > lastPnLCheck + 5)
            {
                cachedPnL = m_riskManager.GetDailyPnL();
                lastPnLCheck = now;
            }
            
            return cachedPnL;
        }
        return 0.0;
    }
    
    // Print position manager status including RiskManager info
    void PrintStatus()
    {
        // String optimization
        string status = "\n═══════════════════════════════════════════\n" +
                       "          POSITION MANAGER STATUS\n" +
                       "═══════════════════════════════════════════\n" +
                       StringFormat("Expert: %s | Magic: %d\n", m_expertComment, m_expertMagic) +
                       StringFormat("Daily Trades: %d\n", m_dailyTradesCount) +
                       StringFormat("Weekly Trades: %d\n", m_weeklyTradesCount) +
                       StringFormat("Monthly Trades: %d\n", m_monthlyTradesCount) +
                       StringFormat("Total Opened: %d | Total Closed: %d\n", 
                            m_totalPositionsOpened, m_totalPositionsClosed) +
                       StringFormat("Active Positions: %d\n", PositionsTotal());
        
        // Add RiskManager info if available
        if(m_riskManager != NULL)
        {
            status += StringFormat("Risk Level: %s\n", GetCurrentRiskLevel()) +
                     StringFormat("Daily P&L: $%.2f\n", GetDailyPnL()) +
                     StringFormat("Current Drawdown: %.1f%%\n", GetCurrentDrawdown());
        }
        
        status += "═══════════════════════════════════════════\n";
        
        Print(status);
    }
    
    // Auto flush all symbols at bar close
    void AutoFlushAllSymbols()
    {
        if(m_logger != NULL)
        {
            m_logger.AutoFlushAllSymbols();
        }
    }
    
    // Handle trade transaction for auto logging
    void HandleTradeTransaction(const MqlTradeTransaction &trans)
    {
        if(m_logger != NULL)
        {
            m_logger.AutoLogTradeTransaction(trans);
        }
    }
    
    // Log performance summary for a symbol
    void LogPerformanceSummary(string symbol)
    {
        if(m_logger != NULL)
        {
            m_logger.LogPerformanceSummary(symbol);
        }
    }
    
    // Get performance statistics for a symbol
    string GetSymbolPerformance(string symbol)
    {
        if(m_logger != NULL)
        {
            int tradesTaken = m_logger.GetTradesTaken(symbol);
            int tradesSkipped = m_logger.GetTradesSkipped(symbol);
            int profitableTrades = m_logger.GetProfitableTrades(symbol);
            int lostTrades = m_logger.GetLostTrades(symbol);
            
            return StringFormat("Trades: %d taken, %d skipped | Win: %d, Loss: %d", 
                tradesTaken, tradesSkipped, profitableTrades, lostTrades);
        }
        return "No logger available";
    }
};

// Define static variables (MQL5 requires this outside the class)
static datetime PositionManager::m_lastStatusLog = 0;
static int PositionManager::m_tickCounter = 0;