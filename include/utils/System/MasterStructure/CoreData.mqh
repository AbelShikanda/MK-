//+------------------------------------------------------------------+
//|                            CoreData.mqh                          |
//|                    Consolidated Structure Library                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "yourwebsite.com"
#property strict
#property version   "1.00"

#ifndef CORE_DATA_MQH
#define CORE_DATA_MQH

// Forward declarations
struct AnalysisContext;
struct TradingContext;
struct ExecutionContext;
struct RiskMetrics;
struct SymbolInfo;
struct MarketAnalysis;
struct TradeSignal;
struct TradeDecision;

// Include all modules
#include "DataAnalysis.mqh"      // Pure technical analysis
#include "TradingInfo.mqh"       // Trading & risk decisions
#include "RiskIntel.mqh"          // Risk metrics & management
#include "SymbolData.mqh"        // Symbol information
#include "Configuration.mqh"     // Settings & configuration
// #include "ExecutionData.mqh"     // Order execution
// #include "IndicatorData.mqh"     // Technical indicators

// Context structures that combine modules
#include "Contexts.mqh"          // Analysis, Trading, Execution contexts

#endif