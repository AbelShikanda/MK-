//+------------------------------------------------------------------+
//| 5UB0_globals.mqh                                                |
//| 5UB0 (Current Strategy) specific variables                      |
//+------------------------------------------------------------------+


#include "enums.mqh"
#include "structures.mqh"

// ULTRA-SENSITIVE INDICATOR HANDLES - MULTI TIMEFRAME
int veryFastMA_M5[], fastMA_M5[], mediumMA_M5[], slowMA_M5[], rsi_M5[], stoch_M5[], macd_M5[];
int fastMA_M15[], mediumMA_M15[], slowMA_M15[], rsi_M15[], stoch_M15[], macd_M15[];
int fastMA_H1[], mediumMA_H1[], slowMA_H1[], rsi_H1[], stoch_H1[], macd_H1[];
int longTermMA_H4[], longTermMA_LT[];  
int atr_handles[];
int atr_handles_M5[];   
int atr_handles_M15[];

// Additional magic number aliases (same values as shared)
int magicNumber = 12345;      // Lowercase m  
int Magic = 12345;            // Just "Magic"
int ExpertMagic = 12345;      // With "Expert"
int EAMagic = 12345;          // "EA" prefix


bool g_CloseBuyPositions = false;
bool g_CloseSellPositions = false;
string g_CloseReason = "";
double g_ClosePercentage = 0;
datetime g_LastCloseSignalTime = 0;

DivergenceOverride divergenceOverride;  // Global override state

//+------------------------------------------------------------------+
//| shared_globals.mqh                                              |
//| SHARED VARIABLES - Used by ALL strategies                       |
//+------------------------------------------------------------------+

string symbolArray[];
int totalSymbols = 0;
string activeSymbols[];

datetime lastTradeCandle[];
string LastDecision = "";
string DebugInfo = "";
double accountBalance = 0;

// Daily tracking variables
double dailyStartBalance = 0;
double dailyProfitCash = 0;
double dailyProfitPips = 0;
double dailyDrawdownCash = 0;
int dailyTradesCount = 0;
datetime dailyResetTime = 0;
bool dailyLimitReached = false;

// Signal tracking
int maxSignalHistory = 10;

string botConclusion = "";

int MagicNumber = 12345;



// Global POI levels cache
int poiLevelCount = 0;
datetime lastPOICalculation = 0;

// bar trade times
datetime g_LastTradedBarTime = 0;
int g_TradesCountThisBar = 0;
bool g_BuyTradedThisBar = false;
bool g_SellTradedThisBar = false;

// ============ TIER CONSTANTS ============
#define TIER_1 1
#define TIER_2 2  
#define TIER_3 3
#define TIER_4 4

// Global tier variable
int AccountTier = TIER_1; // Default to Tier 1