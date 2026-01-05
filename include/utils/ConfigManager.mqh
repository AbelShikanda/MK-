// ConfigManager - Static functions for configuration management
class ConfigManager
{
private:
    // Private constructor to prevent instantiation
    ConfigManager() {}
    
public:
    // Time-related functions
    static datetime ReadDatetime(string key, datetime defaultValue = 0)
    {
        string valueStr = ReadString(key, TimeToString(defaultValue, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
        return StringToTime(valueStr);
    }
    
    static color ReadColor(string key, color defaultValue = clrNONE)
    {
        string valueStr = ReadString(key, ColorToString(defaultValue));
        return StringToColor(valueStr);
    }
    
    static int ReadEnum(string key, int defaultValue = 0)
    {
        string valueStr = ReadString(key, IntegerToString(defaultValue));
        return (int)StringToInteger(valueStr);
    }
    
    // Core configuration functions
    static int ReadInt(string key, int defaultValue = 0, string section = "Settings")
    {
        string valueStr = ReadString(key, IntegerToString(defaultValue), section);
        return (int)StringToInteger(valueStr);
    }
    
    static double ReadDouble(string key, double defaultValue = 0.0, string section = "Settings")
    {
        string valueStr = ReadString(key, DoubleToString(defaultValue, 8), section);
        return StringToDouble(valueStr);
    }
    
    static bool ReadBool(string key, bool defaultValue = false, string section = "Settings")
    {
        string valueStr = ReadString(key, defaultValue ? "true" : "false", section);
        valueStr = StringToLower(StringTrim(valueStr));
        return (valueStr == "true" || valueStr == "1" || valueStr == "yes" || valueStr == "y");
    }
    
    static string ReadString(string key, string defaultValue = "", string section = "Settings")
    {
        if (key == "") return defaultValue;
        
        string configFile = MQLInfoString(MQL_PROGRAM_NAME) + ".ini";
        
        // Try to read from INI file using MQL5's built-in function
        string value = "";
        
        // First try common directory
        ResetLastError();
        value = ReadIniValue(configFile, section, key, defaultValue, true);
        
        // If not found in common, try local
        if (value == defaultValue && GetLastError() != 0)
        {
            ResetLastError();
            value = ReadIniValue(configFile, section, key, defaultValue, false);
        }
        
        return value;
    }
    
private:
    static string ReadIniValue(string filename, string section, string key, string defaultValue, bool common = false)
    {
        string value = "";
        
        if (common)
        {
            // Read from common directory
            ResetLastError();
            if (FileIsExist(filename, FILE_COMMON))
            {
                int flags = FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON;
                int handle = FileOpen(filename, flags);
                if (handle != INVALID_HANDLE)
                {
                    value = ReadFromIniFile(handle, section, key, defaultValue);
                    FileClose(handle);
                }
            }
        }
        else
        {
            // Read from local directory
            ResetLastError();
            if (FileIsExist(filename))
            {
                int flags = FILE_READ | FILE_TXT | FILE_ANSI;
                int handle = FileOpen(filename, flags);
                if (handle != INVALID_HANDLE)
                {
                    value = ReadFromIniFile(handle, section, key, defaultValue);
                    FileClose(handle);
                }
            }
        }
        
        return (value == "") ? defaultValue : value;
    }
    
    static string ReadFromIniFile(int handle, string section, string key, string defaultValue)
    {
        string value = defaultValue;
        bool inSection = false;
        
        while (!FileIsEnding(handle))
        {
            string line = FileReadString(handle);
            line = StringTrim(line);
            
            // Skip empty lines and comments
            if (line == "" || StringGetChar(line, 0) == ';' || StringGetChar(line, 0) == '#')
                continue;
            
            // Check for section
            if (StringGetChar(line, 0) == '[' && StringGetChar(line, StringLen(line)-1) == ']')
            {
                string currentSection = StringSubstr(line, 1, StringLen(line)-2);
                inSection = (StringTrim(currentSection) == section);
                continue;
            }
            
            // If we're in the right section, look for the key
            if (inSection)
            {
                int separatorPos = StringFind(line, "=");
                if (separatorPos > 0)
                {
                    string currentKey = StringSubstr(line, 0, separatorPos);
                    currentKey = StringTrim(currentKey);
                    
                    if (currentKey == key)
                    {
                        value = StringSubstr(line, separatorPos + 1);
                        value = StringTrim(value);
                        break;
                    }
                }
            }
        }
        
        return value;
    }
    
public:
    // Write functions
    static bool WriteInt(string key, int value, string section = "Settings")
    {
        return WriteString(key, IntegerToString(value), section);
    }
    
    static bool WriteDouble(string key, double value, string section = "Settings")
    {
        return WriteString(key, DoubleToString(value, 8), section);
    }
    
    static bool WriteBool(string key, bool value, string section = "Settings")
    {
        return WriteString(key, value ? "true" : "false", section);
    }
    
    static bool WriteString(string key, string value, string section = "Settings")
    {
        if (key == "") return false;
        
        string configFile = MQLInfoString(MQL_PROGRAM_NAME) + ".ini";
        
        // Write to common directory by default
        string path = TerminalInfoString(TERMINAL_COMMON_PATH) + "\\MQL5\\Files\\" + configFile;
        
        // Use MQL5's built-in function for simplicity
        ResetLastError();
        bool success = false;
        
        // For actual implementation, you might need to:
        // 1. Read entire file
        // 2. Modify the specific key in the section
        // 3. Write back the entire file
        
        // This is a simplified version - in production you'd want a complete INI parser/writer
        return success;
    }
    
    static bool WriteDatetime(string key, datetime value, string section = "Settings")
    {
        return WriteString(key, TimeToString(value, TIME_DATE|TIME_MINUTES|TIME_SECONDS), section);
    }
    
    static bool WriteColor(string key, color value, string section = "Settings")
    {
        return WriteString(key, ColorToString(value), section);
    }
    
    // Utility functions
    static bool ConfigExists()
    {
        string configFile = MQLInfoString(MQL_PROGRAM_NAME) + ".ini";
        return (FileIsExist(configFile, FILE_COMMON) || FileIsExist(configFile));
    }
    
    static string GetConfigPath(bool common = true)
    {
        string configFile = MQLInfoString(MQL_PROGRAM_NAME) + ".ini";
        if (common)
            return TerminalInfoString(TERMINAL_COMMON_PATH) + "\\MQL5\\Files\\" + configFile;
        else
            return configFile;
    }
};