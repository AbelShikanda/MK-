//+------------------------------------------------------------------+
//|                                                   PackageManager  |
//|          Controller that orchestrates all 6 modules              |
//|          Clean architecture with NO circular dependencies        |
//+------------------------------------------------------------------+

#include "../Headers/Enums.mqh"
#include "../Utils/Logger.mqh"
#include "../Utils/MathUtils.mqh"
#include "../Utils/TimeUtils.mqh"
#include "../Data/IndicatorManager.mqh"

#include "../Data/TradePackage.mqh"

#include "../Data/MTFAnalyser.mqh"
#include "../Data/POIModule.mqh"
#include "../Data/VolumeModule.mqh"
#include "../Data/RSIModule.mqh"
#include "../Data/MACDModule.mqh"
#include "../Data/CandlestickPatterns.mqh"


// ====================== DEBUG SETTINGS ======================
bool DEBUG_ENABLED_PM = false;

void DebugLogPM(string context, string message) {
   if(DEBUG_ENABLED_PM) {
      Logger::Log("DEBUG-PM-" + context, message, true, true);
   }
}

// ====================== PACKAGE MANAGER CLASS ======================

class TradePackageManager
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_primaryTF;
    bool m_initialized;
    datetime m_lastUpdateTime;
    
    // Module instances for all 6 components
    MTFAnalyser* m_mtfAnalyser;
    POIModule* m_poiModule;
    VolumeModule* m_volumeModule;
    SimpleRSI* m_rsiModule;
    MACDModule* m_macdModule;
    CandlestickPatternAnalyzer* m_candleAnalyzer;
    
    IndicatorManager* m_indicatorManager;
    
    // Configuration for all 6 components (NO DUPLICATE WEIGHTS - weights only in TradePackage)
    struct Config {
        // Module activation
        bool useMTF;
        bool usePOI;
        bool useVolume;
        bool useRSI;
        bool useMACD;
        bool useCandlePatterns;
        
        // Module-specific settings
        bool mtfUse89EMAFilter;
        bool poiDrawOnChart;
        int poiSensitivity;
        int volumeLookbackPeriod;
        int rsiLookbackPeriod;
        ENUM_TIMEFRAMES macdTimeframe;
        int candlePatternShift;
        
        // Update intervals
        int updateIntervalSeconds;
        bool updateOnTick;
        bool updateOnTimer;
        bool updateOnNewBar;
        
        // Validation thresholds
        double minOverallConfidence;
        double minComponentScore;
        int minComponentsRequired;
        
        // Display settings
        bool displayOnChart;
        bool useTabularFormat;
        
        Config() {
            // Default: enable all 6 modules
            useMTF = true;
            usePOI = true;
            useVolume = true;
            useRSI = true;
            useMACD = true;
            useCandlePatterns = true;
            
            // Default module settings
            mtfUse89EMAFilter = true;
            poiDrawOnChart = false;
            poiSensitivity = 2;
            volumeLookbackPeriod = 20;
            rsiLookbackPeriod = 14;
            macdTimeframe = PERIOD_H1;
            candlePatternShift = 1;
            
            // Update settings
            updateIntervalSeconds = 3;
            updateOnTick = false;
            updateOnTimer = true;
            updateOnNewBar = true;
            
            // Validation thresholds
            minOverallConfidence = 65.0;
            minComponentScore = 50.0;
            minComponentsRequired = 3;  // Need at least 3 of 6 components
            
            // Display settings
            displayOnChart = true;
            useTabularFormat = true;
        }
    } m_config;
    
    // Performance tracking
    struct PerformanceStats {
        int totalPackagesGenerated;
        int validPackages;
        int modulesActive;
        double avgProcessingTime;
        datetime lastUpdateTime;
        
        // Component success rates
        int mtfSuccess;
        int poiSuccess;
        int volumeSuccess;
        int rsiSuccess;
        int macdSuccess;
        int candleSuccess;
        
        PerformanceStats() {
            totalPackagesGenerated = 0;
            validPackages = 0;
            modulesActive = 0;
            avgProcessingTime = 0;
            lastUpdateTime = 0;
            mtfSuccess = 0;
            poiSuccess = 0;
            volumeSuccess = 0;
            rsiSuccess = 0;
            macdSuccess = 0;
            candleSuccess = 0;
        }
        
        void UpdateComponentSuccess(int componentIndex, bool success) {
            switch(componentIndex) {
                case 0: if(success) mtfSuccess++; break;
                case 1: if(success) poiSuccess++; break;
                case 2: if(success) volumeSuccess++; break;
                case 3: if(success) rsiSuccess++; break;
                case 4: if(success) macdSuccess++; break;
                case 5: if(success) candleSuccess++; break;
            }
        }
        
        string GetComponentStats() const {
            return StringFormat(
                "MTF: %d/%d | POI: %d/%d | VOL: %d/%d\nRSI: %d/%d | MACD: %d/%d | CANDLE: %d/%d",
                mtfSuccess, totalPackagesGenerated,
                poiSuccess, totalPackagesGenerated,
                volumeSuccess, totalPackagesGenerated,
                rsiSuccess, totalPackagesGenerated,
                macdSuccess, totalPackagesGenerated,
                candleSuccess, totalPackagesGenerated
            );
        }
    } m_stats;
    
    // Cache
    TradePackage m_currentPackage;
    bool m_packageReady;
    
public:
    // CONSTRUCTOR
    TradePackageManager()
    {
        m_symbol = "";
        m_primaryTF = PERIOD_CURRENT;
        m_initialized = false;
        m_lastUpdateTime = 0;
        
        // Initialize all 6 module pointers to NULL
        m_mtfAnalyser = NULL;
        m_poiModule = NULL;
        m_volumeModule = NULL;
        m_rsiModule = NULL;
        m_macdModule = NULL;
        m_candleAnalyzer = NULL;
        m_indicatorManager = NULL;
        
        m_packageReady = false;
        
        DebugLogPM("PackageManager", "Controller created with support for 6 components");
    }
    
    // DESTRUCTOR
    ~TradePackageManager()
    {
        Deinitialize();
    }
    
    // ==================== INITIALIZATION ====================
    
    bool Initialize(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                   IndicatorManager* indicatorMgr = NULL)
    {
        if(m_initialized) {
            DebugLogPM("Initialize", "Already initialized");
            return true;
        }
        
        DebugLogPM("Initialize", "=== INITIALIZING 6-COMPONENT PACKAGE MANAGER ===");
        
        // Validate inputs
        if(indicatorMgr == NULL) {
            DebugLogPM("Initialize", "ERROR: IndicatorManager is required");
            return false;
        }
        
        if(CheckPointer(indicatorMgr) == POINTER_INVALID) {
            DebugLogPM("Initialize", "ERROR: IndicatorManager pointer is invalid");
            return false;
        }
        
        // Set symbol and timeframe
        m_symbol = (symbol == NULL || symbol == "") ? Symbol() : symbol;
        m_primaryTF = (tf == PERIOD_CURRENT) ? Period() : tf;
        
        // Validate symbol
        if(!SymbolInfoInteger(m_symbol, SYMBOL_SELECT)) {
            DebugLogPM("Initialize", "ERROR: Symbol " + m_symbol + " not available");
            return false;
        }
        
        // Store indicator manager
        m_indicatorManager = indicatorMgr;
        
        DebugLogPM("Initialize", 
            StringFormat("Initializing for %s on %s timeframe", 
            m_symbol, EnumToString(m_primaryTF)));
        
        // ==================== INITIALIZE ALL 6 MODULES ====================
        
        int modulesInitialized = 0;
        
        // 1. Initialize MTF Analyser
        if(m_config.useMTF) {
            DebugLogPM("Initialize", "Initializing MTF Analyser...");
            m_mtfAnalyser = new MTFAnalyser();
            if(m_mtfAnalyser.Initialize(m_symbol, m_primaryTF, m_indicatorManager)) {
                m_mtfAnalyser.Use89EMAFilter(m_config.mtfUse89EMAFilter);
                modulesInitialized++;
                DebugLogPM("Initialize", "✓ MTF Analyser initialized");
            } else {
                DebugLogPM("Initialize", "Failed to initialize MTF Analyser");
                delete m_mtfAnalyser;
                m_mtfAnalyser = NULL;
                m_config.useMTF = false;
            }
        }
        
        // 2. Initialize POI Module
        if(m_config.usePOI) {
            DebugLogPM("Initialize", "Initializing POI Module...");
            m_poiModule = new POIModule();
            if(m_poiModule.Initialize(m_symbol, m_config.poiDrawOnChart, m_config.poiSensitivity)) {
                modulesInitialized++;
                DebugLogPM("Initialize", "✓ POI Module initialized");
            } else {
                DebugLogPM("Initialize", "Failed to initialize POI Module");
                delete m_poiModule;
                m_poiModule = NULL;
                m_config.usePOI = false;
            }
        }
        
        // 3. Initialize Volume Module
        if(m_config.useVolume) {
            DebugLogPM("Initialize", "Initializing Volume Module...");
            m_volumeModule = new VolumeModule();
            if(m_volumeModule.Initialize(m_indicatorManager, m_symbol)) {
                modulesInitialized++;
                DebugLogPM("Initialize", "✓ Volume Module initialized");
            } else {
                DebugLogPM("Initialize", "Failed to initialize Volume Module");
                delete m_volumeModule;
                m_volumeModule = NULL;
                m_config.useVolume = false;
            }
        }
        
        // 4. Initialize RSI Module
        if(m_config.useRSI) {
            DebugLogPM("Initialize", "Initializing RSI Module...");
            m_rsiModule = new SimpleRSI(m_symbol, m_primaryTF, m_config.rsiLookbackPeriod, m_indicatorManager);
            modulesInitialized++;
            DebugLogPM("Initialize", "✓ RSI Module initialized");
        }
        
        // 5. Initialize MACD Module
        if(m_config.useMACD) {
            DebugLogPM("Initialize", "Initializing MACD Module...");
            m_macdModule = new MACDModule();
            if(m_macdModule.Initialize(m_symbol, m_config.macdTimeframe)) {
                modulesInitialized++;
                DebugLogPM("Initialize", "✓ MACD Module initialized");
            } else {
                DebugLogPM("Initialize", "Failed to initialize MACD Module");
                delete m_macdModule;
                m_macdModule = NULL;
                m_config.useMACD = false;
            }
        }
        
        // 6. Initialize Candle Patterns Module
        if(m_config.useCandlePatterns) {
            DebugLogPM("Initialize", "Initializing Candle Patterns Module...");
            m_candleAnalyzer = new CandlestickPatternAnalyzer();
            if(m_candleAnalyzer.Initialize(m_symbol, m_primaryTF)) {
                modulesInitialized++;
                DebugLogPM("Initialize", "✓ Candle Patterns Module initialized");
            } else {
                DebugLogPM("Initialize", "Failed to initialize Candle Patterns Module");
                delete m_candleAnalyzer;
                m_candleAnalyzer = NULL;
                m_config.useCandlePatterns = false;
            }
        }
        
        // Check if we have enough modules
        m_stats.modulesActive = modulesInitialized;
        if(modulesInitialized < m_config.minComponentsRequired) {
            DebugLogPM("Initialize", 
                StringFormat("Insufficient modules initialized: %d/%d required", 
                modulesInitialized, m_config.minComponentsRequired));
            Deinitialize();
            return false;
        }
        
        m_initialized = true;
        m_lastUpdateTime = TimeCurrent();
        
        DebugLogPM("Initialize", "=== INITIALIZATION COMPLETE ===");
        DebugLogPM("Initialize", 
            StringFormat("Active modules: %d (MTF: %s, POI: %s, VOL: %s, RSI: %s, MACD: %s, CANDLE: %s)",
            modulesInitialized,
            m_config.useMTF ? "ON" : "OFF",
            m_config.usePOI ? "ON" : "OFF",
            m_config.useVolume ? "ON" : "OFF",
            m_config.useRSI ? "ON" : "OFF",
            m_config.useMACD ? "ON" : "OFF",
            m_config.useCandlePatterns ? "ON" : "OFF"));
        
        return true;
    }
    
    void Deinitialize()
    {
        if(!m_initialized) return;
        
        DebugLogPM("Deinitialize", "Deinitializing all 6 modules...");
        
        // Clean up all 6 modules
        if(CheckPointer(m_mtfAnalyser) != POINTER_INVALID) { delete m_mtfAnalyser; m_mtfAnalyser = NULL; }
        if(CheckPointer(m_poiModule) != POINTER_INVALID) { delete m_poiModule; m_poiModule = NULL; }
        if(CheckPointer(m_volumeModule) != POINTER_INVALID) { delete m_volumeModule; m_volumeModule = NULL; }
        if(CheckPointer(m_rsiModule) != POINTER_INVALID) { delete m_rsiModule; m_rsiModule = NULL; }
        if(CheckPointer(m_macdModule) != POINTER_INVALID) { delete m_macdModule; m_macdModule = NULL; }
        if(CheckPointer(m_candleAnalyzer) != POINTER_INVALID) { delete m_candleAnalyzer; m_candleAnalyzer = NULL; }
        
        m_indicatorManager = NULL;
        m_initialized = false;
        m_packageReady = false;
        
        DebugLogPM("Deinitialize", "All modules deinitialized");
    }
    
    // ==================== MAIN PACKAGE GENERATION ====================
    
    TradePackage GenerateTradePackage(bool forceUpdate = false)
    {
        DebugLogPM("GenerateTradePackage", "=== GENERATING 6-COMPONENT TRADE PACKAGE ===");
        
        if(!m_initialized) {
            DebugLogPM("GenerateTradePackage", "ERROR: Not initialized");
            return CreateErrorPackage("PackageManager not initialized");
        }
        
        // Check if we should update
        if(!ShouldUpdate(forceUpdate) && m_packageReady) {
            DebugLogPM("GenerateTradePackage", "Using cached package");
            return m_currentPackage;
        }
        
        // Start timing
        uint startTime = GetTickCount();
        
        // Create fresh package
        TradePackage package;
        package.signal.symbol = m_symbol;
        package.signal.timestamp = TimeCurrent();
        package.signal.signalSource = "6-Component PackageManager";
        
        // Configure display
        package.ConfigureDisplay(m_config.useTabularFormat, true, false, false);
        
        // Set default weights for 6 components (weights come from TradePackage class)
        // Using default weights: MTF=25, POI=20, VOL=15, RSI=15, MACD=15, PAT=10
        package.SetComponentWeights(25.0, 20.0, 15.0, 15.0, 15.0, 10.0);
        
        // ==================== POPULATE FROM ALL 6 MODULES ====================
        
        int modulesSuccessful = 0;
        
        // 1. MTF Module
        if(m_config.useMTF && CheckPointer(m_mtfAnalyser) != POINTER_INVALID && m_mtfAnalyser.IsInitialized()) {
            DebugLogPM("GenerateTradePackage", "Processing MTF Module...");
            if(PopulateFromMTF(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(0, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ MTF Score: %.1f", package.scores.mtfScore));
            } else {
                m_stats.UpdateComponentSuccess(0, false);
            }
        }
        
        // 2. POI Module
        if(m_config.usePOI && CheckPointer(m_poiModule) != POINTER_INVALID && m_poiModule.IsInitialized()) {
            DebugLogPM("GenerateTradePackage", "Processing POI Module...");
            if(PopulateFromPOI(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(1, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ POI Score: %.1f", package.scores.poiScore));
            } else {
                m_stats.UpdateComponentSuccess(1, false);
            }
        }
        
        // 3. Volume Module
        if(m_config.useVolume && CheckPointer(m_volumeModule) != POINTER_INVALID && m_volumeModule.IsInitialized()) {
            DebugLogPM("GenerateTradePackage", "Processing Volume Module...");
            if(PopulateFromVolume(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(2, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ Volume Score: %.1f", package.scores.volumeScore));
            } else {
                m_stats.UpdateComponentSuccess(2, false);
            }
        }
        
        // 4. RSI Module
        if(m_config.useRSI && CheckPointer(m_rsiModule) != POINTER_INVALID) {
            DebugLogPM("GenerateTradePackage", "Processing RSI Module...");
            if(PopulateFromRSI(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(3, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ RSI Score: %.1f", package.scores.rsiScore));
            } else {
                m_stats.UpdateComponentSuccess(3, false);
            }
        }
        
        // 5. MACD Module
        if(m_config.useMACD && CheckPointer(m_macdModule) != POINTER_INVALID && m_macdModule.IsInitialized()) {
            DebugLogPM("GenerateTradePackage", "Processing MACD Module...");
            if(PopulateFromMACD(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(4, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ MACD Score: %.1f", package.scores.macdScore));
            } else {
                m_stats.UpdateComponentSuccess(4, false);
            }
        }
        
        // 6. Candle Patterns Module
        if(m_config.useCandlePatterns && CheckPointer(m_candleAnalyzer) != POINTER_INVALID && m_candleAnalyzer.IsInitialized()) {
            DebugLogPM("GenerateTradePackage", "Processing Candle Patterns Module...");
            if(PopulateFromCandlePatterns(package)) {
                modulesSuccessful++;
                m_stats.UpdateComponentSuccess(5, true);
                DebugLogPM("GenerateTradePackage", StringFormat("✓ Candle Score: %.1f", package.scores.patternScore));
            } else {
                m_stats.UpdateComponentSuccess(5, false);
            }
        }
        
        DebugLogPM("GenerateTradePackage", 
            StringFormat("Modules successful: %d/%d", modulesSuccessful, m_stats.modulesActive));
        
        // ==================== FINAL CALCULATIONS ====================
        
        if(modulesSuccessful >= m_config.minComponentsRequired) {
            // Calculate weighted score
            package.CalculateWeightedScore();
            
            // Determine dominant direction based on all components
            DetermineDominantDirection(package);
            
            // Set final signal
            package.signal.confidence = package.overallConfidence;
            
            // Validate the package
            package.ValidatePackage(m_config.minOverallConfidence);
            
            // Add component summary
            if(package.validationMessage == "Not analyzed" || package.validationMessage == "") {
                package.validationMessage = StringFormat("Components: %d/%d | Confidence: %.1f%%", 
                    modulesSuccessful, m_stats.modulesActive, package.overallConfidence);
            }
            
            // Cache the package
            m_currentPackage = package;
            m_packageReady = true;
            m_lastUpdateTime = TimeCurrent();
            
            // Update statistics
            m_stats.totalPackagesGenerated++;
            if(package.isValid) m_stats.validPackages++;
            
            uint processingTime = GetTickCount() - startTime;
            m_stats.avgProcessingTime = (m_stats.avgProcessingTime * (m_stats.totalPackagesGenerated - 1) + 
                                        processingTime) / m_stats.totalPackagesGenerated;
            m_stats.lastUpdateTime = TimeCurrent();
            
            DebugLogPM("GenerateTradePackage", 
                StringFormat("✓ Package generated: Valid=%s, Confidence=%.1f%%, Score=%.2f, Time=%d ms",
                package.isValid ? "YES" : "NO",
                package.overallConfidence,
                package.weightedScore,
                processingTime));
            
            // Display on chart if configured
            if(m_config.displayOnChart && package.isValid) {
                DisplayPackageOnChart(package);
            }
            
        } else {
            package.isValid = false;
            package.validationMessage = StringFormat("Insufficient components: %d/%d required", 
                modulesSuccessful, m_config.minComponentsRequired);
            DebugLogPM("GenerateTradePackage", "✗ Insufficient components");
        }
        
        package.analysisTime = TimeCurrent();
        
        DebugLogPM("GenerateTradePackage", "=== GENERATION COMPLETE ===");
        return package;
    }
    
    // ==================== INDIVIDUAL MODULE POPULATION METHODS ====================
    
private:
    bool PopulateFromMTF(TradePackage &package)
    {
        DebugLogPM("PopulateFromMTF", "Getting MTF data...");
        
        // Check if MTF analyser is available
        if(CheckPointer(m_mtfAnalyser) == POINTER_INVALID) {
            DebugLogPM("PopulateFromMTF", "ERROR: MTF analyser pointer is invalid");
            return false;
        }
        
        // Get MTF analysis from MTFAnalyser
        MTFAnalyser::MTFScore mtfScore = m_mtfAnalyser.AnalyzeMultiTimeframe(m_symbol);
        
        DebugLogPM("PopulateFromMTF", 
            StringFormat("MTF Score: %.1f, Weighted: %.1f, B:%d/S:%d/N:%d",
            mtfScore.score, mtfScore.weightedScore,
            mtfScore.bullishTFCount, mtfScore.bearishTFCount, mtfScore.neutralTFCount));
        
        // Populate TradePackage using setter method
        package.SetMTFData(
            mtfScore.score,              // score
            mtfScore.weightedScore,      // mtfWeightedScore
            mtfScore.bullishTFCount,     // bullishCount
            mtfScore.bearishTFCount,     // bearishCount
            mtfScore.neutralTFCount,     // neutralCount
            mtfScore.bullishWeightedScore, // bullishWeightedScore
            mtfScore.bearishWeightedScore, // bearishWeightedScore
            mtfScore.alignedWithEMA89,   // alignedWithEMA89
            mtfScore.confidence          // confidence
        );
        
        // Set initial signal from MTF (strongest component)
        if(mtfScore.bullishWeightedScore > mtfScore.bearishWeightedScore) {
            package.signal.orderType = ORDER_TYPE_BUY;
            package.signal.reason = StringFormat("MTF bullish: %d/%d timeframes", 
                mtfScore.bullishTFCount, mtfScore.bullishTFCount + mtfScore.bearishTFCount + mtfScore.neutralTFCount);
        } else if(mtfScore.bearishWeightedScore > mtfScore.bullishWeightedScore) {
            package.signal.orderType = ORDER_TYPE_SELL;
            package.signal.reason = StringFormat("MTF bearish: %d/%d timeframes", 
                mtfScore.bearishTFCount, mtfScore.bullishTFCount + mtfScore.bearishTFCount + mtfScore.neutralTFCount);
        } else {
            package.signal.orderType = ORDER_TYPE_BUY_LIMIT;
            package.signal.reason = "MTF neutral";
        }
        
        // Update direction analysis with MTF confidence
        if(mtfScore.bullishWeightedScore > mtfScore.bearishWeightedScore) {
            package.directionAnalysis.bullishConfidence += mtfScore.confidence * (package.weights.mtfWeight / 100.0);
        } else if(mtfScore.bearishWeightedScore > mtfScore.bullishWeightedScore) {
            package.directionAnalysis.bearishConfidence += mtfScore.confidence * (package.weights.mtfWeight / 100.0);
        }
        
        return true;
    }
    
    bool PopulateFromPOI(TradePackage &package)
    {
    DebugLogPM("PopulateFromPOI", "Getting POI data...");
    
    // Check if POI module is available
    if(CheckPointer(m_poiModule) == POINTER_INVALID) {
        DebugLogPM("PopulateFromPOI", "ERROR: POI module pointer is invalid");
        return false;
    }
    
    // Get current price for POI analysis
    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // Get POIModuleSignal from POIModule
    POIModuleSignal moduleSignal = m_poiModule.GetPOIModuleSignal(currentPrice);
    
    // Convert POIModuleSignal to POISignal
    POISignal poiSignal;
    
    // Convert overallBias enum to string
    string overallBiasStr;
    switch(moduleSignal.overallBias) {
        case POI_BIAS_BULLISH: 
            overallBiasStr = "BULLISH";
            break;
        case POI_BIAS_BEARISH: 
            overallBiasStr = "BEARISH";
            break;
        case POI_BIAS_CONFLICTED: 
            overallBiasStr = "CONFLICTED";
            break;
        case POI_BIAS_NEUTRAL: 
        default:
            overallBiasStr = "NEUTRAL";
            break;
    }
    
    // If biasString exists in moduleSignal, use it (cleaner)
    // Check if moduleSignal has a biasString field
    // Based on your POIModuleSignal definition, it should have it
    
    // Map all fields from moduleSignal to poiSignal
    poiSignal.overallBias = overallBiasStr;
    poiSignal.zoneBias = moduleSignal.zoneBias;
    poiSignal.score = moduleSignal.score;
    poiSignal.confidence = moduleSignal.confidence;
    poiSignal.nearestZoneType = (int)moduleSignal.nearestZoneType;
    poiSignal.distanceToZone = moduleSignal.distanceToZone;
    poiSignal.zoneStrength = moduleSignal.zoneStrength;
    poiSignal.zoneRelevance = moduleSignal.zoneRelevance;
    poiSignal.priceAction = moduleSignal.priceAction;
    poiSignal.zonesInFavor = moduleSignal.zonesInFavor;
    poiSignal.zonesAgainst = moduleSignal.zonesAgainst;
    
    // Determine direction from bias for the package logic
    string bias = "";
    if(poiSignal.overallBias == "BULLISH" || poiSignal.overallBias == "BUY ZONE" || poiSignal.overallBias == "BUY BIAS") {
        bias = "BULLISH";
    } else if(poiSignal.overallBias == "BEARISH" || poiSignal.overallBias == "SELL ZONE" || poiSignal.overallBias == "SELL BIAS") {
        bias = "BEARISH";
    } else {
        bias = "NEUTRAL";
    }
    
    // Populate TradePackage with POI data using the setter
    package.SetPOIData(
        poiSignal.overallBias,        // overallBias
        poiSignal.zoneBias,           // zoneBias
        poiSignal.score,              // score
        poiSignal.confidence,         // confidence
        poiSignal.nearestZoneType,    // nearestZoneType
        poiSignal.distanceToZone,     // distanceToZone
        poiSignal.zoneStrength,       // zoneStrength
        poiSignal.zoneRelevance,      // zoneRelevance
        poiSignal.priceAction,        // priceAction
        poiSignal.zonesInFavor,       // zonesInFavor
        poiSignal.zonesAgainst        // zonesAgainst
    );
    
    // Update direction analysis
    if(bias == "BULLISH") {
        package.directionAnalysis.bullishConfidence += poiSignal.confidence * (package.weights.poiWeight / 100.0);
    } else if(bias == "BEARISH") {
        package.directionAnalysis.bearishConfidence += poiSignal.confidence * (package.weights.poiWeight / 100.0);
    }
    
    // Add to reason if significant
    if(poiSignal.score > 50) {
        if(package.signal.reason != "") package.signal.reason += " | ";
        package.signal.reason += "POI: " + poiSignal.priceAction;
    }
    
    return true;
    }
    
    bool PopulateFromVolume(TradePackage &package)
    {
    DebugLogPM("PopulateFromVolume", "Getting Volume data...");
    
    // Check if Volume module is available
    if(CheckPointer(m_volumeModule) == POINTER_INVALID) {
        DebugLogPM("PopulateFromVolume", "ERROR: Volume module pointer is invalid");
        return false;
    }
    
    // Get volume analysis - CORRECT TYPE: VolumeAnalysisResult (not VolumeModule::VolumeAnalysisResult)
    VolumeAnalysisResult volumeData = m_volumeModule.Analyze(m_primaryTF, m_config.volumeLookbackPeriod);
    
    // Convert bias to string
    string volumeBias = volumeData.bias.primaryBias;
    
    // Determine direction from bias
    string direction = "";
    if(volumeBias == "BULLISH") {
        direction = "BULLISH";
    } else if(volumeBias == "BEARISH") {
        direction = "BEARISH";
    } else {
        direction = "NEUTRAL";
    }
    
    // Populate TradePackage with volume data
    package.SetVolumeData(
        volumeData.momentumScore,              // momentumScore
        volumeData.convictionScore,            // convictionScore
        direction,                             // prediction
        volumeData.divergence,                 // divergence
        volumeData.climax,                     // climax
        volumeData.volumeStatus,               // volumeStatus
        volumeData.volumeRatio,                // volumeRatio
        volumeData.bias.bullScore,             // bullishScore
        volumeData.bias.bearScore,             // bearishScore
        volumeBias,                            // bias
        volumeData.bias.overallConfidence,     // confidence
        volumeData.volume.hasWarning           // hasWarning
    );
    
    // Update direction based on volume bias
    if(direction == "BULLISH") {
        package.directionAnalysis.bullishConfidence += volumeData.bias.overallConfidence * (package.weights.volumeWeight / 100.0);
        if(package.signal.reason != "") package.signal.reason += " | ";
        package.signal.reason += "Volume: " + volumeData.volumeStatus;
    } else if(direction == "BEARISH") {
        package.directionAnalysis.bearishConfidence += volumeData.bias.overallConfidence * (package.weights.volumeWeight / 100.0);
        if(package.signal.reason != "") package.signal.reason += " | ";
        package.signal.reason += "Volume: " + volumeData.volumeStatus;
    }
    
    // Add volume warning if present
    if(volumeData.volume.hasWarning) {
        package.signal.reason += " (Volume warning)";
    }
    
    return true;
    }
    
    bool PopulateFromRSI(TradePackage &package)
    {
        DebugLogPM("PopulateFromRSI", "Getting RSI data...");
        
        // Check if RSI module is available
        if(CheckPointer(m_rsiModule) == POINTER_INVALID) {
            DebugLogPM("PopulateFromRSI", "ERROR: RSI module pointer is invalid");
            return false;
        }
        
        // Get RSI bias
        RSIBias rsiBias = m_rsiModule.GetBiasAndConfidence(m_config.rsiLookbackPeriod);
        
        // Determine direction from bias
        string direction = "";
        if(rsiBias.netBias > 20) {
            direction = "BULLISH";
        } else if(rsiBias.netBias < -20) {
            direction = "BEARISH";
        } else {
            direction = "NEUTRAL";
        }
        
        // Populate TradePackage with RSI data
        package.SetRSIData(
            rsiBias.bullishBias,    // bullishBias
            rsiBias.bearishBias,    // bearishBias
            rsiBias.netBias,        // netBias
            rsiBias.confidence,     // confidence
            rsiBias.biasText,       // biasText
            rsiBias.rsiLevel,       // rsiLevel
            rsiBias.currentRSI      // currentRSI
        );
        
        // Update direction analysis
        if(direction == "BULLISH") {
            package.directionAnalysis.bullishConfidence += rsiBias.confidence * (package.weights.rsiWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("RSI: %s (%.0f)", rsiBias.biasText, rsiBias.netBias);
        } else if(direction == "BEARISH") {
            package.directionAnalysis.bearishConfidence += rsiBias.confidence * (package.weights.rsiWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("RSI: %s (%.0f)", rsiBias.biasText, rsiBias.netBias);
        }
        
        return true;
    }
    
    bool PopulateFromMACD(TradePackage &package)
    {
        DebugLogPM("PopulateFromMACD", "Getting MACD data...");
        
        // Check if MACD module is available
        if(CheckPointer(m_macdModule) == POINTER_INVALID) {
            DebugLogPM("PopulateFromMACD", "ERROR: MACD module pointer is invalid");
            return false;
        }
        
        // Get MACD signal
        MACDSignal macdSignal = m_macdModule.GetMACDSignal();
        
        // Determine direction from bias
        string direction = "";
        if(macdSignal.bias == MACD_BIAS_BULLISH || macdSignal.bias == MACD_BIAS_WEAK_BULLISH) {
            direction = "BULLISH";
        } else if(macdSignal.bias == MACD_BIAS_BEARISH || macdSignal.bias == MACD_BIAS_WEAK_BEARISH) {
            direction = "BEARISH";
        } else {
            direction = "NEUTRAL";
        }
        
        // Convert signal type to string
        string signalTypeStr = "";
        switch(macdSignal.signalType) {
            case MACD_SIGNAL_CROSSOVER: signalTypeStr = "CROSSOVER"; break;
            case MACD_SIGNAL_DIVERGENCE: signalTypeStr = "DIVERGENCE"; break;
            case MACD_SIGNAL_TREND: signalTypeStr = "TREND"; break;
            case MACD_SIGNAL_ZERO_LINE: signalTypeStr = "ZERO_LINE"; break;
            default: signalTypeStr = "NONE"; break;
        }
        
        // Populate TradePackage with MACD data
        package.SetMACDData(
            direction,                    // biasString
            macdSignal.score,            // score
            macdSignal.confidence,       // confidence
            signalTypeStr,               // signalType
            macdSignal.macdValue,        // macdValue
            macdSignal.signalValue,      // signalValue
            macdSignal.histogramValue,   // histogramValue
            macdSignal.histogramSlope,   // histogramSlope
            macdSignal.isAboveZero,      // isAboveZero
            macdSignal.isCrossover,      // isCrossover
            macdSignal.isDivergence,     // isDivergence
            macdSignal.isStrongSignal    // isStrongSignal
        );
        
        // Update direction analysis
        if(direction == "BULLISH") {
            package.directionAnalysis.bullishConfidence += macdSignal.confidence * (package.weights.macdWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("MACD: %s (%.0f)", macdSignal.biasString, macdSignal.score);
        } else if(direction == "BEARISH") {
            package.directionAnalysis.bearishConfidence += macdSignal.confidence * (package.weights.macdWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("MACD: %s (%.0f)", macdSignal.biasString, macdSignal.score);
        }
        
        return true;
    }
    
    bool PopulateFromCandlePatterns(TradePackage &package)
    {
        DebugLogPM("PopulateFromCandlePatterns", "Getting Candle Patterns data...");
        
        // Check if Candle Patterns module is available
        if(CheckPointer(m_candleAnalyzer) == POINTER_INVALID) {
            DebugLogPM("PopulateFromCandlePatterns", "ERROR: Candle Patterns module pointer is invalid");
            return false;
        }
        
        // Get pattern result
        PatternResult patternResult = m_candleAnalyzer.AnalyzeCurrentPattern(m_config.candlePatternShift);
        
        // Determine direction
        string direction = patternResult.direction;
        
        // Get pattern name from enum - FIXED
        string patternName = GetPatternDescription(patternResult.pattern);
        
        // Populate TradePackage with pattern data - FIXED
        package.SetPatternData(
            patternName,                 // patternName (converted from enum)
            direction,                   // direction
            patternResult.confidence,    // confidence
            patternResult.description,   // description
            patternResult.isConfirmed,   // isConfirmed
            patternResult.targetPrice,   // targetPrice
            patternResult.stopLoss,      // stopLoss
            patternResult.riskRewardRatio // riskRewardRatio
        );
        
        // Update direction analysis
        if(direction == "BULLISH") {
            double weight = patternResult.isConfirmed ? 1.0 : 0.5;
            package.directionAnalysis.bullishConfidence += 
                patternResult.confidence * weight * (package.weights.patternWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("Pattern: %s (%.0f)", 
                patternName, patternResult.confidence);
        } else if(direction == "BEARISH") {
            double weight = patternResult.isConfirmed ? 1.0 : 0.5;
            package.directionAnalysis.bearishConfidence += 
                patternResult.confidence * weight * (package.weights.patternWeight / 100.0);
            if(package.signal.reason != "") package.signal.reason += " | ";
            package.signal.reason += StringFormat("Pattern: %s (%.0f)", 
                patternName, patternResult.confidence);
        }
        
        return true;
    }
    
    // ==================== HELPER METHODS ====================
    
    void DetermineDominantDirection(TradePackage &package)
    {
        // Normalize direction confidence to sum to 100
        double totalDirection = package.directionAnalysis.bullishConfidence + 
                               package.directionAnalysis.bearishConfidence;
        
        if(totalDirection > 0) {
            package.directionAnalysis.bullishConfidence = 
                (package.directionAnalysis.bullishConfidence / totalDirection) * 100;
            package.directionAnalysis.bearishConfidence = 
                (package.directionAnalysis.bearishConfidence / totalDirection) * 100;
        }
        
        package.directionAnalysis.neutralConfidence = 
            100 - package.directionAnalysis.bullishConfidence - 
            package.directionAnalysis.bearishConfidence;
        
        // Set dominant direction
        if(package.directionAnalysis.bullishConfidence > package.directionAnalysis.bearishConfidence && 
           package.directionAnalysis.bullishConfidence > package.directionAnalysis.neutralConfidence) {
            package.directionAnalysis.dominantDirection = "BULLISH";
        } else if(package.directionAnalysis.bearishConfidence > package.directionAnalysis.bullishConfidence && 
                  package.directionAnalysis.bearishConfidence > package.directionAnalysis.neutralConfidence) {
            package.directionAnalysis.dominantDirection = "BEARISH";
        } else {
            package.directionAnalysis.dominantDirection = "NEUTRAL";
        }
        
        // Check for conflict
        package.directionAnalysis.isConflict = 
            (package.directionAnalysis.bullishConfidence >= 40.0 && 
             package.directionAnalysis.bearishConfidence >= 40.0);
        
        DebugLogPM("DetermineDominantDirection", 
            StringFormat("Direction: %s, B:%.1f%%, S:%.1f%%, N:%.1f%%, Conflict:%s",
            package.directionAnalysis.dominantDirection,
            package.directionAnalysis.bullishConfidence,
            package.directionAnalysis.bearishConfidence,
            package.directionAnalysis.neutralConfidence,
            package.directionAnalysis.isConflict ? "YES" : "NO"));
    }
    
    bool ShouldUpdate(bool forceUpdate)
    {
        if(forceUpdate) return true;
        
        // Time-based update
        if(TimeCurrent() - m_lastUpdateTime >= m_config.updateIntervalSeconds) {
            return true;
        }
        
        // Check for new bar if configured
        if(m_config.updateOnNewBar) {
            static datetime lastBarTime = 0;
            datetime currentBarTime = iTime(m_symbol, m_primaryTF, 0);
            if(currentBarTime != lastBarTime) {
                lastBarTime = currentBarTime;
                return true;
            }
        }
        
        return false;
    }
    
    TradePackage CreateErrorPackage(string errorMessage)
    {
        TradePackage errorPackage;
        errorPackage.isValid = false;
        errorPackage.validationMessage = errorMessage;
        errorPackage.signal.symbol = m_symbol;
        errorPackage.analysisTime = TimeCurrent();
        return errorPackage;
    }
    
    void DisplayPackageOnChart(const TradePackage &package) {
        if(!m_config.displayOnChart || !package.isValid) return;
        
        // Use the detailed tabular display
        string displayText = package.GenerateDetailedTabularDisplay();
        
        // Create or update chart object
        string objName = "PackageManager_Display_" + m_symbol;
        if(ObjectFind(0, objName) < 0) {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        }
        
        ObjectSetString(0, objName, OBJPROP_TEXT, displayText);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
    }
    
public:
    // ==================== PUBLIC INTERFACE ====================
    
    TradePackage GetTradePackage(bool forceUpdate = false)
    {
        if(!m_initialized) {
            return CreateErrorPackage("Not initialized");
        }
        
        return GenerateTradePackage(forceUpdate);
    }
    
    TradePackage GetCurrentPackage()
    {
        if(!m_initialized || !m_packageReady) {
            return CreateErrorPackage("No package available");
        }
        
        return m_currentPackage;
    }
    
    bool HasTradingOpportunity(double minConfidence = 0)
    {
        if(!m_initialized || !m_packageReady) return false;
        
        double requiredConfidence = (minConfidence > 0) ? minConfidence : m_config.minOverallConfidence;
        
        return m_currentPackage.isValid && m_currentPackage.overallConfidence >= requiredConfidence;
    }
    
    void ForceUpdate()
    {
        if(m_initialized) {
            m_currentPackage = GenerateTradePackage(true);
        }
    }
    
    // ==================== CONFIGURATION METHODS ====================
    
    void ConfigureModules(bool useMTF = true, bool usePOI = true, bool useVolume = true,
                         bool useRSI = true, bool useMACD = true, bool useCandlePatterns = true)
    {
        m_config.useMTF = useMTF;
        m_config.usePOI = usePOI;
        m_config.useVolume = useVolume;
        m_config.useRSI = useRSI;
        m_config.useMACD = useMACD;
        m_config.useCandlePatterns = useCandlePatterns;
        
        DebugLogPM("ConfigureModules", 
            StringFormat("Modules: MTF=%s, POI=%s, VOL=%s, RSI=%s, MACD=%s, CANDLE=%s",
            useMTF ? "ON" : "OFF",
            usePOI ? "ON" : "OFF",
            useVolume ? "ON" : "OFF",
            useRSI ? "ON" : "OFF",
            useMACD ? "ON" : "OFF",
            useCandlePatterns ? "ON" : "OFF"));
    }
    
    void ConfigureModuleSettings(bool mtfUse89EMA = true, bool poiDraw = false, int poiSens = 2,
                                int volumePeriod = 20, int rsiPeriod = 14, 
                                ENUM_TIMEFRAMES macdTF = PERIOD_H1, int candleShift = 1)
    {
        m_config.mtfUse89EMAFilter = mtfUse89EMA;
        m_config.poiDrawOnChart = poiDraw;
        m_config.poiSensitivity = poiSens;
        m_config.volumeLookbackPeriod = volumePeriod;
        m_config.rsiLookbackPeriod = rsiPeriod;
        m_config.macdTimeframe = macdTF;
        m_config.candlePatternShift = candleShift;
        
        // Apply MTF setting if module exists
        if(CheckPointer(m_mtfAnalyser) != POINTER_INVALID) {
            m_mtfAnalyser.Use89EMAFilter(mtfUse89EMA);
        }
        
        DebugLogPM("ConfigureModuleSettings", "Module settings updated");
    }
    
    void ConfigureUpdateBehavior(bool onTick = false, bool onTimer = true,
                                bool onNewBar = true, int intervalSec = 3)
    {
        m_config.updateOnTick = onTick;
        m_config.updateOnTimer = onTimer;
        m_config.updateOnNewBar = onNewBar;
        m_config.updateIntervalSeconds = MathMax(1, intervalSec);
        
        DebugLogPM("ConfigureUpdateBehavior", 
            StringFormat("Update: Tick=%s, Timer=%s, NewBar=%s, Interval=%d sec",
            onTick ? "ON" : "OFF", onTimer ? "ON" : "OFF", 
            onNewBar ? "ON" : "OFF", intervalSec));
    }
    
    void ConfigureValidation(double minConfidence = 65.0, double minScore = 50.0,
                            int minComponents = 3)
    {
        m_config.minOverallConfidence = MathMax(0, MathMin(100, minConfidence));
        m_config.minComponentScore = MathMax(0, MathMin(100, minScore));
        m_config.minComponentsRequired = MathMax(1, MathMin(6, minComponents));
        
        DebugLogPM("ConfigureValidation", 
            StringFormat("Validation: MinConf=%.1f%%, MinScore=%.1f, MinComps=%d",
            minConfidence, minScore, minComponents));
    }
    
    void ConfigureDisplay(bool displayChart = true, bool tabularFormat = true)
    {
        m_config.displayOnChart = displayChart;
        m_config.useTabularFormat = tabularFormat;
        
        DebugLogPM("ConfigureDisplay", 
            StringFormat("Display: Chart=%s, Format=%s",
            displayChart ? "ON" : "OFF", tabularFormat ? "TABULAR" : "FREE"));
    }
    
    // ==================== STATUS & INFORMATION ====================
    
    bool IsInitialized() const { return m_initialized; }
    bool IsPackageReady() const { return m_packageReady; }
    string GetSymbol() const { return m_symbol; }
    ENUM_TIMEFRAMES GetPrimaryTF() const { return m_primaryTF; }
    
    int GetActiveModuleCount() const { return m_stats.modulesActive; }
    
    string GetStatus() const
    {
        if(!m_initialized) return "NOT INITIALIZED";
        
        return StringFormat(
            "=== 6-COMPONENT PACKAGE MANAGER ===\n"
            "Symbol: %s | TF: %s\n"
            "Active Modules: %d/6 | Package Ready: %s\n"
            "Last Update: %s\n"
            "--- Statistics ---\n"
            "Total Packages: %d | Valid: %d (%.1f%%)\n"
            "Avg Processing Time: %.1f ms\n"
            "--- Component Success ---\n"
            "%s",
            m_symbol,
            EnumToString(m_primaryTF),
            m_stats.modulesActive,
            m_packageReady ? "YES" : "NO",
            TimeToString(m_stats.lastUpdateTime, TIME_SECONDS),
            m_stats.totalPackagesGenerated,
            m_stats.validPackages,
            (m_stats.totalPackagesGenerated > 0) ? 
                (double)m_stats.validPackages / m_stats.totalPackagesGenerated * 100 : 0,
            m_stats.avgProcessingTime,
            m_stats.GetComponentStats()
        );
    }
    
    string GetComponentStatus() const
    {
        string status = "=== COMPONENT STATUS ===\n";
        
        // MTF
        status += StringFormat("MTF: %s%s",
            m_config.useMTF ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_mtfAnalyser) != POINTER_INVALID && m_mtfAnalyser.IsInitialized()) ? " (✓)" : " (✗)");
        
        // POI
        status += StringFormat("\nPOI: %s%s",
            m_config.usePOI ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_poiModule) != POINTER_INVALID && m_poiModule.IsInitialized()) ? " (✓)" : " (✗)");
        
        // Volume
        status += StringFormat("\nVOL: %s%s",
            m_config.useVolume ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_volumeModule) != POINTER_INVALID && m_volumeModule.IsInitialized()) ? " (✓)" : " (✗)");
        
        // RSI
        status += StringFormat("\nRSI: %s%s",
            m_config.useRSI ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_rsiModule) != POINTER_INVALID) ? " (✓)" : " (✗)");
        
        // MACD
        status += StringFormat("\nMACD: %s%s",
            m_config.useMACD ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_macdModule) != POINTER_INVALID && m_macdModule.IsInitialized()) ? " (✓)" : " (✗)");
        
        // Candle Patterns
        status += StringFormat("\nCANDLE: %s%s",
            m_config.useCandlePatterns ? "ACTIVE" : "INACTIVE",
            (CheckPointer(m_candleAnalyzer) != POINTER_INVALID && m_candleAnalyzer.IsInitialized()) ? " (✓)" : " (✗)");
        
        return status;
    }
    
    // ==================== EVENT HANDLERS ====================
    
    void OnTick()
    {
        if(!m_initialized) return;
        
        if(m_config.updateOnTick) {
            ForceUpdate();
        }
    }
    
    void OnTimer()
    {
        if(!m_initialized) return;
        
        if(m_config.updateOnTimer) {
            ForceUpdate();
        }
    }
    
    // ==================== DISPLAY METHODS ====================
    
    // Display the current package with all 6 component details
    void DisplayCurrentPackage() {
        DebugLogPM("DisplayCurrentPackage", "Displaying current package details");
        
        if(!m_initialized || !m_packageReady) {
            DebugLogPM("DisplayCurrentPackage", "No valid package available");
            Logger::DisplaySingleFrame("No valid package available");
            return;
        }
        
        // Generate detailed display
        string display = m_currentPackage.GenerateDetailedTabularDisplay();
        
        // Display it using Logger
        Logger::DisplaySingleFrame(display);
        
        DebugLogPM("DisplayCurrentPackage", "Package displayed successfully");
    }
    
    // Get package display as string (for printing or logging)
    string GetCurrentPackageDisplay() {
        if(!m_initialized || !m_packageReady) {
            return "No valid package available";
        }
        
        return m_currentPackage.GenerateDetailedTabularDisplay();
    }
};