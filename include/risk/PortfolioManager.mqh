//+------------------------------------------------------------------+
//|                     SimplePortfolioManager.mqh                  |
//|                 Minimal 5-Function Portfolio Manager            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

// ============ SIMPLE CONFIGURATION ============
input double    Account_Tier_1 = 500.0;      // Tier 1: $0-$500
input double    Account_Tier_2 = 5000.0;     // Tier 2: $500-$5000
input double    Account_Tier_3 = 20000.0;    // Tier 3: $5000-$20000
input double    Account_Tier_4 = 100000.0;   // Tier 4: $20000-$100000

input double    Base_Lot_Size = 0.01;        // Base lot size for smallest tier
input double    Lot_Multiplier_T2 = 2.0;     // Tier 2: 2x base
input double    Lot_Multiplier_T3 = 5.0;     // Tier 3: 5x base
input double    Lot_Multiplier_T4 = 10.0;    // Tier 4: 10x base

input double    Profit_Take_T1 = 5.0;        // Take profit at $5 (Tier 1)
input double    Profit_Take_T2 = 25.0;       // Take profit at $25 (Tier 2)
input double    Profit_Take_T3 = 100.0;      // Take profit at $100 (Tier 3)
input double    Profit_Take_T4 = 500.0;      // Take profit at $500 (Tier 4)

input double    Signal_Threshold_Base = 70.0;  // Base signal threshold %
input double    Threshold_Increment = 2.0;     // Increase threshold by 2% each win
input double    Max_Threshold = 85.0;          // Max threshold %

input int       Max_Symbols_T1 = 1;           // Tier 1: Trade 1 symbol
input int       Max_Symbols_T2 = 2;           // Tier 2: Trade 2 symbols
input int       Max_Symbols_T3 = 3;           // Tier 3: Trade 3 symbols
input int       Max_Symbols_T4 = 5;           // Tier 4: Trade 5 symbols

// ============ GLOBAL VARIABLES ============
double currentThreshold;
int consecutiveWins;
double totalProfitToday;
datetime lastProfitTime;

// Symbol priority list (most traded to least)
string symbolPriority[] = {"XAUUSD", "XAGUSD", "GBPUSD", "USDJPY", "USDCHF"};

//+------------------------------------------------------------------+
//| FUNCTION 1: Determine Account Tier                              |
//+------------------------------------------------------------------+
int GetAccountTier()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance < Account_Tier_1) return 1;
    else if(balance < Account_Tier_2) return 2;
    else if(balance < Account_Tier_3) return 3;
    else if(balance < Account_Tier_4) return 4;
    else return 5; // Above $100k
    
    PrintFormat("Account Tier: %d (Balance: $%.2f)", tier, balance);
    return tier;
}

//+------------------------------------------------------------------+
//| FUNCTION 2: Decide Which Symbol to Trade                        |
//+------------------------------------------------------------------+
string GetSymbolToTrade()
{
    int tier = GetAccountTier();
    int maxSymbols;
    
    // Get max symbols based on tier
    switch(tier)
    {
        case 1: maxSymbols = Max_Symbols_T1; break;
        case 2: maxSymbols = Max_Symbols_T2; break;
        case 3: maxSymbols = Max_Symbols_T3; break;
        case 4: maxSymbols = Max_Symbols_T4; break;
        case 5: maxSymbols = 8; break; // Unlimited (but reasonable)
        default: maxSymbols = 1;
    }
    
    // Count currently trading symbols
    int currentSymbols = CountTradingSymbols();
    
    // If we're at max symbols, return empty
    if(currentSymbols >= maxSymbols)
    {
        Print("Max symbols reached (", currentSymbols, "/", maxSymbols, ")");
        return "";
    }
    
    // Get next symbol from priority list
    for(int i = 0; i < ArraySize(symbolPriority); i++)
    {
        string symbol = symbolPriority[i];
        
        // Check if symbol is already being traded
        if(!IsSymbolTrading(symbol))
        {
            // Check if symbol is tradeable
            if(IsSymbolTradeable(symbol))
            {
                Print("Selected symbol: ", symbol, " (Priority: ", i+1, ")");
                return symbol;
            }
        }
    }
    
    return "";
}

//+------------------------------------------------------------------+
//| FUNCTION 3: Decide Which Positions to Close (Profit Taking)     |
//+------------------------------------------------------------------+
void SecureProfitablePositions()
{
    int tier = GetAccountTier();
    double profitTarget;
    
    // Get profit target based on tier
    switch(tier)
    {
        case 1: profitTarget = Profit_Take_T1; break;
        case 2: profitTarget = Profit_Take_T2; break;
        case 3: profitTarget = Profit_Take_T3; break;
        case 4: profitTarget = Profit_Take_T4; break;
        case 5: profitTarget = 1000.0; break; // $1000 for >$100k
        default: profitTarget = Profit_Take_T1;
    }
    
    PrintFormat("Profit Target for Tier %d: $%.2f", tier, profitTarget);
    
    // Check all open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            // Close if profit exceeds target
            if(profit >= profitTarget)
            {
                PrintFormat("Closing position: %s | Profit: $%.2f (Target: $%.2f)", 
                           symbol, profit, profitTarget);
                
                // Record this as a win for threshold adjustment
                if(profit > 0)
                {
                    RecordWin();
                }
                
                // Close the position
                ClosePositionByTicket(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCTION 4: Adjust Signal Threshold After Wins                  |
//+------------------------------------------------------------------+
double GetCurrentSignalThreshold()
{
    // Initialize on first run
    if(currentThreshold == 0)
    {
        currentThreshold = Signal_Threshold_Base;
        consecutiveWins = 0;
        totalProfitToday = 0.0;
        lastProfitTime = TimeCurrent();
    }
    
    // Check if we should reset (new day)
    datetime now = TimeCurrent();
    if(TimeDay(now) != TimeDay(lastProfitTime))
    {
        consecutiveWins = 0;
        currentThreshold = Signal_Threshold_Base;
        totalProfitToday = 0.0;
        Print("New day - Reset threshold to base: ", currentThreshold, "%");
    }
    
    PrintFormat("Current Signal Threshold: %.1f%% | Consecutive Wins: %d | Today's Profit: $%.2f",
               currentThreshold, consecutiveWins, totalProfitToday);
    
    return currentThreshold;
}

//+------------------------------------------------------------------+
//| FUNCTION 5: Determine Lot Size Based on Portfolio               |
//+------------------------------------------------------------------+
double GetPortfolioLotSize(string symbol)
{
    int tier = GetAccountTier();
    double baseLot;
    
    // Get base lot multiplier based on tier
    switch(tier)
    {
        case 1: baseLot = Base_Lot_Size; break;
        case 2: baseLot = Base_Lot_Size * Lot_Multiplier_T2; break;
        case 3: baseLot = Base_Lot_Size * Lot_Multiplier_T3; break;
        case 4: baseLot = Base_Lot_Size * Lot_Multiplier_T4; break;
        case 5: baseLot = Base_Lot_Size * 20.0; break; // 20x for >$100k
        default: baseLot = Base_Lot_Size;
    }
    
    // Adjust for symbol volatility
    double volatilityAdjustment = GetVolatilityAdjustment(symbol);
    double lotSize = baseLot * volatilityAdjustment;
    
    // Apply threshold adjustment (higher threshold = smaller position)
    double threshold = GetCurrentSignalThreshold();
    double thresholdAdjustment = 1.0 - ((threshold - Signal_Threshold_Base) / 50.0);
    thresholdAdjustment = MathMax(thresholdAdjustment, 0.5); // Don't go below 50%
    
    lotSize *= thresholdAdjustment;
    
    // Apply broker limits
    lotSize = NormalizeLotSize(symbol, lotSize);
    
    PrintFormat("Portfolio Lot Size for %s: %.3f (Tier: %d, Base: %.3f, Vol Adj: %.2f, Thresh Adj: %.2f)",
               symbol, lotSize, tier, baseLot, volatilityAdjustment, thresholdAdjustment);
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+

// Count how many symbols are currently being traded
int CountTradingSymbols()
{
    int symbolCount = 0;
    string tradedSymbols[100]; // Array to store unique symbols
    
    // Reset array
    ArrayInitialize(tradedSymbols, "");
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            
            // Check if we've already counted this symbol
            bool alreadyCounted = false;
            for(int j = 0; j < symbolCount; j++)
            {
                if(tradedSymbols[j] == symbol)
                {
                    alreadyCounted = true;
                    break;
                }
            }
            
            // If new symbol, add to array
            if(!alreadyCounted && symbolCount < 100)
            {
                tradedSymbols[symbolCount] = symbol;
                symbolCount++;
            }
        }
    }
    
    return symbolCount;
}

// Check if a symbol is currently being traded
bool IsSymbolTrading(string symbol)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
                return true;
        }
    }
    return false;
}

// Check if symbol is tradeable
bool IsSymbolTradeable(string symbol)
{
    // Check if market is open for this symbol
    long tradeMode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        Print(symbol, " is disabled for trading");
        return false;
    }
    
    // Check spread
    double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(spread/point > 50.0) // More than 50 pips spread
    {
        Print(symbol, " has too high spread: ", DoubleToString(spread/point, 1), " pips");
        return false;
    }
    
    return true;
}

// Adjust for symbol volatility
double GetVolatilityAdjustment(string symbol)
{
    // Simple volatility categories
    if(symbol == "XAUUSD" || symbol == "BTCUSD") // High volatility
        return 0.5; // Half size
    
    else if(symbol == "GBPJPY" || symbol == "AUDJPY") // Medium-high volatility
        return 0.75; // Three-quarters size
    
    else if(symbol == "EURUSD" || symbol == "USDJPY") // Medium volatility
        return 1.0; // Normal size
    
    else if(symbol == "EURCHF" || symbol == "USDCHF") // Low volatility
        return 1.5; // Slightly larger size
    
    else
        return 1.0; // Default
}

// Normalize lot size to broker limits
double NormalizeLotSize(string symbol, double lots)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Apply min/max
    lots = MathMax(lots, minLot);
    lots = MathMin(lots, maxLot);
    
    // Round to lot step
    if(lotStep > 0)
    {
        lots = MathRound(lots / lotStep) * lotStep;
    }
    
    // Ensure we don't exceed margin
    double marginRequired = CalculateMargin(symbol, lots);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(marginRequired > freeMargin * 0.8) // Don't use more than 80% of free margin
    {
        lots = lots * 0.5; // Reduce by half
        Print("Reduced lot size due to margin constraints");
    }
    
    return lots;
}

// Calculate margin required for a position
double CalculateMargin(string symbol, double lots)
{
    // Simplified margin calculation
    double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double leverage = AccountInfoDouble(ACCOUNT_LEVERAGE);
    
    if(leverage <= 0) leverage = 100; // Default to 1:100
    
    double margin = (lots * contractSize * price) / leverage;
    
    return margin;
}

// Record a win and adjust threshold
void RecordWin()
{
    consecutiveWins++;
    lastProfitTime = TimeCurrent();
    
    // Increase threshold for each consecutive win
    if(consecutiveWins > 0)
    {
        currentThreshold = Signal_Threshold_Base + (consecutiveWins * Threshold_Increment);
        currentThreshold = MathMin(currentThreshold, Max_Threshold);
        
        PrintFormat("WIN #%d! Threshold increased to %.1f%%", 
                   consecutiveWins, currentThreshold);
    }
}

// Record a loss and reset threshold
void RecordLoss()
{
    consecutiveWins = 0;
    currentThreshold = Signal_Threshold_Base;
    
    Print("Loss recorded. Threshold reset to base: ", currentThreshold, "%");
}

// Close position by ticket
void ClosePositionByTicket(ulong ticket)
{
    // This should use your existing closing logic
    // For now, just print
    Print("Closing position ticket: ", ticket);
    
    // In reality, you'd call:
    // trade.PositionClose(ticket);
}

//+------------------------------------------------------------------+
//| Main Portfolio Execution Function                               |
//+------------------------------------------------------------------+
void ExecutePortfolioManagement()
{
    Print("\n=== PORTFOLIO MANAGEMENT CYCLE ===");
    
    // 1. Check account tier
    int tier = GetAccountTier();
    PrintFormat("Account Tier: %d", tier);
    
    // 2. Check which positions to close (profit taking)
    SecureProfitablePositions();
    
    // 3. Get current signal threshold
    double threshold = GetCurrentSignalThreshold();
    
    // 4. Log portfolio status
    PrintPortfolioStatus();
    
    Print("=== END PORTFOLIO CYCLE ===\n");
}

//+------------------------------------------------------------------+
//| Portfolio Status Report                                         |
//+------------------------------------------------------------------+
void PrintPortfolioStatus()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    PrintFormat("\n📊 PORTFOLIO STATUS:");
    PrintFormat("   Balance: $%.2f | Equity: $%.2f", balance, equity);
    PrintFormat("   Margin Used: $%.2f | Free Margin: $%.2f", margin, freeMargin);
    PrintFormat("   Margin Level: %.1f%%", (equity/margin)*100);
    
    int positions = PositionsTotal();
    if(positions > 0)
    {
        PrintFormat("   Open Positions: %d", positions);
        
        double totalProfit = 0.0;
        for(int i = 0; i < positions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                double volume = PositionGetDouble(POSITION_VOLUME);
                
                PrintFormat("   %s: %.2f lots | P&L: $%.2f", 
                           symbol, volume, profit);
                
                totalProfit += profit;
            }
        }
        PrintFormat("   Total P&L: $%.2f", totalProfit);
    }
    else
    {
        Print("   No open positions");
    }
}

//+------------------------------------------------------------------+
//| Get Symbol for Trading (Main Interface)                         |
//+------------------------------------------------------------------+
string GetNextTradingSymbol()
{
    return GetSymbolToTrade();
}

//+------------------------------------------------------------------+
//| Get Lot Size for Symbol (Main Interface)                        |
//+------------------------------------------------------------------+
double GetAdjustedLotSize(string symbol)
{
    return GetPortfolioLotSize(symbol);
}

//+------------------------------------------------------------------+
//| Get Signal Threshold (Main Interface)                           |
//+------------------------------------------------------------------+
double GetSignalThreshold()
{
    return GetCurrentSignalThreshold();
}