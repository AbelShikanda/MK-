//+------------------------------------------------------------------+
//|                     ResourceManager.mqh                          |
//|                  Complete Logging System                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict

#include <Trade/Trade.mqh>
#include <Arrays\ArrayString.mqh>

/*
==============================================================
                            USECASE
==============================================================
// ===== INIT LOGGER =====
ResourceManager* resourceManager = new ResourceManager();

if(!resourceManager.Initialize("DecisionJournal.csv",true,true,true))
{
    Print("Failed to initialize ResourceManager");
    return;
}

resourceManager.KeepNotes(symbol, AUTHORIZE, "Executor", "BUY APPROVED", true, true, 10.5);
resourceManager.KeepNotes(symbol, OBSERVE, "Executor", "TRADE SKIPPED");

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
resourceManager.AutoLogTradeTransaction(trans);
resourceManager.LogPerformanceSummary("XAUUSD");
==============================================================
*/

// ============================================================
//                     LOG LEVELS
// ============================================================
enum RESOURCE_MANAGER
{
    OBSERVE,
    AUTHORIZE,
    WARN,
    ENFORCE,
    AUDIT
};

// ============================================================
//           PER-SYMBOL CONTEXT STRUCTURE
// ============================================================
struct SymbolProfile
{
    string behaviour;
    datetime situation;
    bool isTradable;

    int numberOfTradesTaken;
    int numberOfTradesSkipped;
    int profitableTrades;
    int lostTrades;

    bool lastTradeTaken;
    bool lastProfitableTrade;
    string lastTradeSummary;
    
    SymbolProfile()
    {
        behaviour = "";
        situation = 0;
        isTradable = false;
        numberOfTradesTaken = 0;
        numberOfTradesSkipped = 0;
        profitableTrades = 0;
        lostTrades = 0;
        lastTradeTaken = false;
        lastProfitableTrade = false;
        lastTradeSummary = "";
    }
};

// ============================================================
//                     RESOURCE MANAGER CLASS
// ============================================================
class ResourceManager
{
private:
    string symbols[];
    SymbolProfile pair[];
    string csvFile;
    bool enableExpertLogs;
    bool enableDebugLogs;
    bool enableCSVJournal;
    bool m_initialized;
    int fileHandle; // Track the CSV file handle

public:
    // ================= CONSTRUCTOR =================
    // Just sets default values. Does NOT create resources, open files, or initialize anything.
    ResourceManager()
    {
        csvFile = "";
        enableExpertLogs = false;
        enableDebugLogs = false;
        enableCSVJournal = false;
        m_initialized = false;
        fileHandle = INVALID_HANDLE;
        
        // Initialize arrays to empty state
        ArrayResize(symbols, 0);
        ArrayResize(pair, 0);
    }
    
    // ================= DESTRUCTOR =================
    ~ResourceManager()
    {
        // Ensure proper cleanup if not already done
        if(m_initialized)
        {
            Deinitialize();
        }
    }

    // ================= INITIALIZE =================
    // The ONE AND ONLY real initialization method
    bool Initialize(string file="DecisionJournal.csv", bool expert=true, bool debug=true, bool csv=true)
    {
        // Check if already initialized
        if(m_initialized)
        {
            Print("ResourceManager: Already initialized");
            return true;
        }
        
        csvFile = file;
        enableExpertLogs = expert;
        enableDebugLogs = debug;
        enableCSVJournal = csv;
        
        // Initialize arrays
        ArrayResize(symbols, 0);
        ArrayResize(pair, 0);
        
        // Create CSV file if enabled
        if(enableCSVJournal && csvFile != "")
        {
            // Open the file to create it if it doesn't exist
            fileHandle = FileOpen(csvFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
            if(fileHandle != INVALID_HANDLE)
            {
                // Write header if file is empty
                if(FileSize(fileHandle) == 0)
                {
                    FileWrite(fileHandle, "time", "symbol", "tf", "decision", "summary", "trace");
                }
                FileClose(fileHandle);
                fileHandle = INVALID_HANDLE;
            }
            else
            {
                Print("ResourceManager: Warning - Could not create CSV file: ", csvFile);
                // Don't fail initialization just because of CSV file
            }
        }
        
        m_initialized = true;
        Print("ResourceManager: Initialized successfully");
        return true;
    }
    
    // ================= DEINITIALIZE =================
    void Deinitialize()
    {
        if(!m_initialized)
        {
            Print("ResourceManager: Not initialized, nothing to deinitialize");
            return;
        }
        
        // Auto-flush any remaining contexts
        AutoFlushAllSymbols();
        
        // Close file handle if open
        if(fileHandle != INVALID_HANDLE)
        {
            FileClose(fileHandle);
            fileHandle = INVALID_HANDLE;
        }
        
        // Clear all data
        ClearAllData();
        
        // Reset initialization flag
        m_initialized = false;
        
        Print("ResourceManager: Deinitialized successfully");
    }
    
    // ================= CHECK INITIALIZATION =================
    bool IsInitialized() const
    {
        return m_initialized;
    }

    // ================= INTERNAL METHODS =================
private:
    int GetSymbolIndex(const string symbol)
    {
        // Safety check
        if(!m_initialized) return -1;
        
        for(int i=0;i<ArraySize(symbols);i++)
            if(symbols[i]==symbol) return i;

        int newIndex = ArraySize(symbols);
        ArrayResize(symbols,newIndex+1);
        ArrayResize(pair,newIndex+1);

        symbols[newIndex] = symbol;
        pair[newIndex] = SymbolProfile();

        return newIndex;
    }

    void TakeNoteOf(RESOURCE_MANAGER level,string source,string message,string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return;
        if(!enableExpertLogs) return;
        if(level==AUDIT && !enableDebugLogs) return;

        string levelStr;
        switch(level)
        {
            case OBSERVE: levelStr="OBSERVATION"; break;
            case AUTHORIZE: levelStr="AUTHORIZED"; break;
            case WARN: levelStr="FLAG"; break;
            case ENFORCE: levelStr="REINFORCED"; break;
            case AUDIT: levelStr="AUDITING"; break;
        }

        PrintFormat("[%s][%s][%s][%s] %s",
            levelStr, source, symbol, EnumToString((ENUM_TIMEFRAMES)_Period), message);
    }

    void AddContext(int idx,string key,string value,bool important=false)
    {
        // Only process if initialized
        if(!m_initialized) return;
        if(idx < 0 || idx >= ArraySize(pair)) return;
        if(!pair[idx].isTradable) return;
        
        string prefix = important ? "!" : "";
        pair[idx].behaviour += prefix + key + "=" + value + " | \n";
    }

public:
    // ================= CONTEXT METHODS =================
    void StartContextWith(const string symbol,string reason)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        int idx = GetSymbolIndex(symbol);
        if(idx < 0) return;
        
        datetime situation = iTime(symbol,_Period,0);

        if(situation!=pair[idx].situation)
        {
            pair[idx].behaviour="";
            pair[idx].situation = situation;
        }

        pair[idx].isTradable = true;
        pair[idx].behaviour += "[BEGIN:" + reason + "] ";
    }

    void AddToContext(const string symbol,string key,string value,bool important=false)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        int idx = GetSymbolIndex(symbol);
        if(idx < 0) return;
        AddContext(idx,key,value,important);
    }

    void AddBoolContext(const string symbol,string key,bool v)
    {
        // Only process if initialized
        if(!m_initialized) return;
        AddToContext(symbol,key,v?"TRUE":"FALSE");
    }

    void AddDoubleContext(const string symbol,string key,double v,int d=2)
    {
        // Only process if initialized
        if(!m_initialized) return;
        AddToContext(symbol,key,DoubleToString(v,d));
    }

    // ================= FLUSH =================
    void FlushContext(const string symbol,RESOURCE_MANAGER level,string source,string summary,bool tradeTaken)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        int idx = GetSymbolIndex(symbol);
        if(idx < 0) return;
        if(!pair[idx].isTradable) return;

        string full = summary + "\nTRACE: " + pair[idx].behaviour;
        TakeNoteOf(level,source,full,symbol);

        pair[idx].lastTradeTaken = tradeTaken;
        pair[idx].lastTradeSummary = summary;
        if(tradeTaken) pair[idx].numberOfTradesTaken++;
        else pair[idx].numberOfTradesSkipped++;

        // CSV journaling
        if(enableCSVJournal && csvFile != "")
        {
            int fh = FileOpen(csvFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
            if(fh != INVALID_HANDLE)
            {
                if(FileSize(fh)==0)
                    FileWrite(fh,"time","symbol","tf","decision","summary","trace");

                FileSeek(fh,0,SEEK_END);
                FileWrite(fh,
                    TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                    symbol,
                    EnumToString((ENUM_TIMEFRAMES)_Period),
                    tradeTaken?"TAKEN":"SKIPPED",
                    summary,
                    pair[idx].behaviour
                );
                FileClose(fh);
            }
        }

        pair[idx].behaviour="";
        pair[idx].isTradable=false;
    }

    // ================= PERFORMANCE =================
    void RecordTradeOutcome(const string symbol,bool win)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        int idx = GetSymbolIndex(symbol);
        if(idx < 0) return;
        pair[idx].lastProfitableTrade = win;
        if(win) pair[idx].profitableTrades++;
        else pair[idx].lostTrades++;
    }

    void LogPerformanceSummary(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        int idx = GetSymbolIndex(symbol);
        if(idx < 0) return;
        
        TakeNoteOf(OBSERVE,"Performance",
            StringFormat("Trades=%d Skipped=%d Profitable Trades=%d Lost Trades=%d",
                pair[idx].numberOfTradesTaken,
                pair[idx].numberOfTradesSkipped,
                pair[idx].profitableTrades,
                pair[idx].lostTrades),
            symbol);
    }

    // ================= AUTO LOGGING =================
    void AutoLogTradeTransaction(const MqlTradeTransaction &trans)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
        
        // Get deal ticket to access profit information
        ulong dealTicket = trans.deal;
        double profit = 0.0;
        bool win = false;
        
        // Try to get deal information from HistoryDealSelect
        if(HistoryDealSelect(dealTicket))
        {
            profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            win = (profit > 0);
        }
        else
        {
            // Fallback: Try to get position profit
            string symbol = trans.symbol;
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong positionTicket = PositionGetTicket(i);
                if(PositionSelectByTicket(positionTicket))
                {
                    if(PositionGetString(POSITION_SYMBOL) == symbol)
                    {
                        profit = PositionGetDouble(POSITION_PROFIT);
                        win = (profit > 0);
                        break;
                    }
                }
            }
        }
        
        RecordTradeOutcome(trans.symbol, win);
        
        StartContextWith(trans.symbol, "TRADE_DONE");
        AddToContext(trans.symbol, "DealType", EnumToString(trans.deal_type));
        AddDoubleContext(trans.symbol, "Profit", profit, 2);
        AddBoolContext(trans.symbol, "Win", win);
        FlushContext(trans.symbol, AUTHORIZE, "ResourceAutoLogger", "Trade closed", true);
    }

    void AutoFlushAllSymbols()
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        for(int i=0;i<ArraySize(symbols);i++)
        {
            if(pair[i].isTradable)
                FlushContext(symbols[i],OBSERVE,"AutoFlush","Bar ended",pair[i].lastTradeTaken);
        }
    }

    // ================= SINGLE-LINE LOGGER =================
    void KeepNotes(
        const string symbol,
        const RESOURCE_MANAGER level,
        const string source,
        const string summary,
        bool tradeTaken=false,
        bool win=false,
        double profit=0.0)
    {
        // Only process if initialized
        if(!m_initialized) return;
        
        StartContextWith(symbol,"AutoLog");
        AddToContext(symbol,"Summary",summary,true);
        AddDoubleContext(symbol,"Profit",profit,2);
        AddBoolContext(symbol,"TradeTaken",tradeTaken);
        AddBoolContext(symbol,"Win",win);

        if(tradeTaken)
            RecordTradeOutcome(symbol,win);

        FlushContext(symbol,level,source,summary,tradeTaken);
    }
    
    // ================= UTILITY METHODS =================
    int GetTotalSymbols()
    {
        // Only process if initialized
        if(!m_initialized) return 0;
        return ArraySize(symbols);
    }
    
    bool HasSymbolData(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return false;
        int idx = GetSymbolIndex(symbol);
        return (idx >= 0);
    }
    
    void ClearAllData()
    {
        ArrayFree(symbols);
        ArrayFree(pair);
    }
    
    // ================= GETTERS =================
    string GetSymbolBehaviour(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return "";
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].behaviour;
        return "";
    }
    
    bool IsSymbolTradable(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return false;
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].isTradable;
        return false;
    }
    
    int GetTradesTaken(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return 0;
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].numberOfTradesTaken;
        return 0;
    }
    
    int GetTradesSkipped(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return 0;
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].numberOfTradesSkipped;
        return 0;
    }
    
    int GetProfitableTrades(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return 0;
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].profitableTrades;
        return 0;
    }
    
    int GetLostTrades(const string symbol)
    {
        // Only process if initialized
        if(!m_initialized) return 0;
        
        int idx = GetSymbolIndex(symbol);
        if(idx >= 0)
            return pair[idx].lostTrades;
        return 0;
    }
};