# ConnectAnnounce Plugin - Copilot Instructions

## Repository Overview

This repository contains **ConnectAnnounce**, a SourceMod plugin for Source engine games that announces player connections with customizable messages. The plugin integrates with various game server extensions and supports SQL databases for persistent storage.

### Key Features
- Customizable player connection announcements
- Asynchronous SQL database integration (MySQL/SQLite)
- Integration with HLStatsX, SourceBans++, EntWatch, KnockbackRestrict, and PlayerManager
- Support for multiple authentication methods (Steam2/3/64, Engine)
- Threaded queries to prevent server freezing
- Country detection via GeoIP
- Admin command access control

## Technical Environment

- **Language**: SourcePawn
- **Platform**: SourceMod 1.11+ (see sourceknight.yaml for exact version)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight build system
- **Build Tool**: SourceKnight (configured in `sourceknight.yaml`)
- **CI/CD**: GitHub Actions (`.github/workflows/ci.yml`)

## Build System

### SourceKnight Configuration
The project uses SourceKnight for dependency management and building:
- **Config File**: `sourceknight.yaml`
- **Dependencies**: Automatically downloads SourceMod, MultiColors, PlayerManager, SourceBans++, EntWatch, KnockbackRestrict
- **Output**: Compiled plugins go to `/addons/sourcemod/plugins`

### Building the Plugin
```bash
# Using SourceKnight (recommended)
sourceknight build

# Manual compilation (if needed)
spcomp -i addons/sourcemod/scripting/include addons/sourcemod/scripting/ConnectAnnounce.sp
```

### CI/CD Pipeline
- **Trigger**: Push to main/master branches or tags
- **Process**: Build → Package → Release
- **Artifacts**: tar.gz package with plugin and configuration files

## Project Structure

```
├── addons/sourcemod/scripting/
│   └── ConnectAnnounce.sp          # Main plugin file (1406 lines)
├── common/addons/sourcemod/configs/connect_announce/
│   ├── settings.cfg                # Message format configuration
│   └── custom-messages.cfg         # Custom message templates
├── .github/workflows/ci.yml        # CI/CD pipeline
├── sourceknight.yaml              # Build configuration
└── README.md                      # Plugin documentation
```

## Code Standards & Conventions

### SourcePawn Style Guide
- **Indentation**: Tabs (4 spaces equivalent)
- **Variables**: 
  - Local variables/parameters: `camelCase`
  - Function names: `PascalCase` 
  - Global variables: `g_` prefix + `PascalCase`
- **Pragmas**: Always include `#pragma semicolon 1` and `#pragma newdecls required`
- **Memory Management**: Use `delete` directly without null checks

### Plugin-Specific Patterns

#### Database Operations
```sourcepawn
// ✅ Correct: Always use async queries
Database.Connect(OnDatabaseConnected, "connect_announce");

// ✅ Use transactions for multiple related queries
Transaction txn = new Transaction();
txn.AddQuery("INSERT INTO...", data);
db.Execute(txn, OnTransactionSuccess, OnTransactionFailure);

// ✅ Properly escape strings
char escapedName[MAX_NAME_LENGTH * 2 + 1];
db.Escape(playerName, escapedName, sizeof(escapedName));
```

#### Memory Management
```sourcepawn
// ✅ Direct deletion without null checks
delete g_hDatabase;
g_hDatabase = null;

// ✅ Use delete instead of .Clear() for containers
delete g_hPlayerData;
g_hPlayerData = new StringMap();

// ❌ Avoid .Clear() as it creates memory leaks
// g_hPlayerData.Clear(); // DON'T DO THIS
```

#### Event Handling
```sourcepawn
public void OnPluginStart()
{
    // Initialize CVars, commands, and hooks
    CreateConVar("sm_connect_announce", "1", "Enable/disable plugin");
    HookEvent("player_connect", OnPlayerConnect);
}

public void OnPluginEnd()
{
    // Cleanup resources if necessary
    delete g_hDatabase;
}
```

## Configuration System

### Message Templates (`common/addons/sourcemod/configs/connect_announce/settings.cfg`)
- **Format**: Single line template with placeholder variables
- **Variables**: `{PLAYERTYPE}`, `{RANK}`, `{STEAMID}`, `{NAME}`, `{COUNTRY}`, `{BANS}`, etc.
- **Colors**: Uses MultiColors syntax (`{WHITE}`, `{GREEN}`, `{BLUE}`, etc.)

### ConVars
Key configuration variables defined in the plugin:
- `sm_connect_announce`: Enable/disable plugin
- `sm_connect_announce_storage`: Storage type (sql/local)
- `sm_connect_announce_hlstatsx`: Enable HLStatsX integration
- `sm_connect_announce_query_retry`: SQL retry attempts

## Integration Points

### External Plugin Dependencies
- **MultiColors**: For chat color formatting
- **PlayerManager**: Player data management
- **SourceBans++**: Ban information (`{BANS}`, `{COMMS}`, `{MUTES}`, `{GAGS}`)
- **HLStatsX**: Player statistics and rankings (`{RANK}`)
- **EntWatch**: Entity restrictions (`{EBANS}`)
- **KnockbackRestrict**: Knockback restrictions (`{KBANS}`)

### Database Schema
The plugin manages its own database tables:
- Primary table: `join` (stores player connection messages)
- Required columns: `steamid`, `message`, `is_banned`
- Supports both MySQL and SQLite

## Development Workflow

### Making Changes
1. **Small Changes**: Edit `ConnectAnnounce.sp` directly
2. **New Features**: Consider impact on database schema and configuration
3. **Testing**: Use development server with SourceMod debugging enabled
4. **Dependencies**: Update `sourceknight.yaml` if adding new plugin dependencies

### Common Development Tasks

#### Adding New Message Variables
1. Define the variable in the message parsing function
2. Add corresponding data retrieval logic
3. Update configuration documentation in README.md

#### Database Changes
1. Update SQL schema in the connection handler
2. Add migration queries to README.md
3. Test with both MySQL and SQLite

#### Performance Optimization
- Cache expensive operations (e.g., country lookups)
- Minimize database queries in frequently called functions
- Use timers sparingly - prefer event-driven programming

### Testing & Validation

#### Pre-commit Checks
```bash
# Build the plugin
sourceknight build

# Check for compilation errors
# Validate SQL queries are async
# Test with development server
```

#### Integration Testing
- Test with various player authentication types
- Verify database connections (MySQL/SQLite)
- Test external plugin integrations
- Validate message formatting with different variables

#### Performance Testing
- Monitor server tick rate impact
- Test with multiple concurrent connections
- Validate SQL query performance

## Common Pitfalls

### ❌ Avoid These Patterns
```sourcepawn
// DON'T: Synchronous database queries
db.Query("SELECT * FROM table");

// DON'T: Using .Clear() on containers
stringMap.Clear();

// DON'T: Hardcoded values
PrintToChat(client, "Welcome to MyServer!");

// DON'T: Missing error handling
db.Query(callback, "INSERT INTO...");
```

### ✅ Use These Patterns Instead
```sourcepawn
// DO: Async queries with error handling
db.Query(OnQueryComplete, "SELECT * FROM table", GetClientUserId(client));

// DO: Delete and recreate containers
delete stringMap;
stringMap = new StringMap();

// DO: Use configuration files and translation
CPrintToChat(client, "%s%T", g_sTag, "Welcome Message", client);

// DO: Always handle SQL errors
public void OnQueryComplete(Database db, DBResultSet results, const char[] error, int userid)
{
    if (!db || !results || error[0])
    {
        LogError("Query failed: %s", error);
        return;
    }
    // Process results...
}
```

## Version Management

- **Versioning**: Follow semantic versioning (MAJOR.MINOR.PATCH)
- **Releases**: Automatic via GitHub Actions on tag push
- **Plugin Info**: Update version info in plugin header
- **Database Migrations**: Document schema changes in README.md

## Documentation Requirements

### Code Documentation
- Document complex logic sections with comments
- Use descriptive function and variable names
- Avoid unnecessary header comments (follows SourcePawn conventions)

### Configuration Documentation
- Update README.md when adding new ConVars
- Document new message variables
- Provide migration steps for database schema changes

This plugin serves as a foundation for player connection announcements and can be extended to integrate with additional game server systems while maintaining performance and reliability standards.