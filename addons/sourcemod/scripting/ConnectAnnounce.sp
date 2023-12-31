#pragma semicolon 1

#include <sourcemod>
#include <geoip>
#include <multicolors>
#tryinclude <connect>

#pragma newdecls required

#define MSGLENGTH            100
#define ANNOUNCER_DELAY      1.5
#define DATABASE_NAME        "connect_announce"
#define MAX_SQL_QUERY_LENGTH 1024
#define MAX_CHAT_LENGTH      256

char g_sDataFile[128];
char g_sCustomMessageFile[128];

/* Database connection state */
enum DatabaseState
{
	DatabaseState_Disconnected = 0,
	DatabaseState_Wait,
	DatabaseState_Connecting,
	DatabaseState_Connected,
}
DatabaseState g_DatabaseState;

Database g_hDatabase;
Database g_hDatabase_Hlstatsx;

ConVar g_hCvar_Enabled;
ConVar g_cvQueryRetry;
ConVar g_hCvar_StorageType;
ConVar g_hCvar_UseHlstatsx;

char g_sJoinMessageTemplate[MAX_CHAT_LENGTH * 2] = "";
char g_sClientJoinMessage[MAXPLAYERS + 1][MAX_CHAT_LENGTH];
char g_sAuthID[MAXPLAYERS + 1][64];
char g_sPlayerIP[MAXPLAYERS + 1][64];
char g_sPlayerName[MAXPLAYERS + 1][64];
int  g_sClientJoinMessageBanned[MAXPLAYERS + 1] = { -1, ... };
int  iUserSerial[MAXPLAYERS + 1];
int  iUserID[MAXPLAYERS + 1];
int  g_iConnectLock = 0;
int  g_iSequence = 0;

float RetryTime = 15.0;

bool g_bSQLite = true;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name        = "Connect Announce",
	author      = "Neon + Botox + maxime1907",
	description = "Connect Announcer",
	version     = "2.3.4",
	url         = ""
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	g_hCvar_Enabled     = CreateConVar("sm_connect_announce", "1", "Should the plugin be enabled ?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar_StorageType = CreateConVar("sm_connect_announce_storage", "sql", "Storage type used for connect messages [sql, local]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar_UseHlstatsx = CreateConVar("sm_connect_announce_hlstatsx", "0", "Add hlstatsx informations on player connection?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvQueryRetry 		= CreateConVar("sm_connect_announce_query_retry", "5", "How many times should the plugin retry after a fail-to-run query?", FCVAR_NONE, true, 0.0, false, 0.0);

	RegAdminCmd("sm_joinmsg", Command_JoinMsg, ADMFLAG_CUSTOM1, "Sets a custom message which will be shown upon connecting to the server");
	RegAdminCmd("sm_resetjoinmsg", Command_ResetJoinMsg, ADMFLAG_CUSTOM1, "Resets your custom connect message");
	RegAdminCmd("sm_announce", Command_Announce, ADMFLAG_CUSTOM1, "Show your custom connect message to yourself");

	RegAdminCmd("sm_joinmsg_ban", Command_Ban, ADMFLAG_BAN, "Ban a player custom message (-1 = Unban)");

	AutoExecConfig(true);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapEnd()
{
	// Clean up on map end just so we can start a fresh connection when we need it later.
	// Also it is necessary for using SQL_SetCharset
	if (g_hDatabase != null)
	{
		delete g_hDatabase;
		g_hDatabase = null;
	}

	if (g_hDatabase_Hlstatsx != null)
	{
		delete g_hDatabase_Hlstatsx;
		g_hDatabase_Hlstatsx = null;
	}
}

public void OnConfigsExecuted()
{
	char g_sCustomMessageFilePath[256] = "configs/connect_announce/custom-messages.cfg";
	char g_sDataFilePath[256]          = "configs/connect_announce/settings.cfg";

	BuildPath(Path_SM, g_sCustomMessageFile, sizeof(g_sCustomMessageFile), g_sCustomMessageFilePath);
	BuildPath(Path_SM, g_sDataFile, sizeof(g_sDataFile), g_sDataFilePath);

	char sStorageType[256];
	g_hCvar_StorageType.GetString(sStorageType, sizeof(sStorageType));

	if (StrEqual(sStorageType, "sql"))
	{
		DB_Connect();
	}

	if (GetConVarBool(g_hCvar_UseHlstatsx))
	{
		char error[255];

		if (SQL_CheckConfig("hlstatsx"))
		{
			g_hDatabase_Hlstatsx = SQL_Connect("hlstatsx", true, error, sizeof(error));
		}

		if (g_hDatabase_Hlstatsx == null)
		{
			LogError("Could not connect to database: %s", error);
		}
	}

	Handle hFile = OpenFile(g_sDataFile, "r");
	if (hFile != INVALID_HANDLE)
	{
		ReadFileLine(hFile, g_sJoinMessageTemplate, sizeof(g_sJoinMessageTemplate));
		TrimString(g_sJoinMessageTemplate);
		CloseHandle(hFile);
	}
	else
	{
		LogError("[SM] File not found! (%s)", g_sDataFilePath);
		return;
	}
}

public void OnClientPutInServer(int client)
{
	char sSteamID[64];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
	FormatEx(g_sAuthID[client], sizeof(g_sAuthID[]), "%s", sSteamID);

	char sIP[64];
	GetClientIP(client, sIP, sizeof(sIP));
	FormatEx(g_sPlayerIP[client], sizeof(g_sPlayerIP[]), "%s", sIP);

	FormatEx(g_sPlayerName[client], sizeof(g_sPlayerName[]), "%N", client);

	iUserSerial[client] = GetClientSerial(client);
	iUserID[client] = GetClientUserId(client);
}

public void OnClientPostAdminCheck(int client)
{
	char sStorageType[256];
	g_hCvar_StorageType.GetString(sStorageType, sizeof(sStorageType));

	if (StrEqual(sStorageType, "local"))
	{
		PrintToChatAll("Auth: %s", g_sAuthID[client]);

		Handle hCustomMessageFile = CreateKeyValues("custom_messages");

		if (!FileToKeyValues(hCustomMessageFile, g_sCustomMessageFile))
		{
			SetFailState("[ConnectAnnounce] Config file missing!");
			return;
		}

		KvRewind(hCustomMessageFile);

		if (KvJumpToKey(hCustomMessageFile, g_sAuthID[client]))
		{
			char sBanned[16];
			KvGetString(hCustomMessageFile, "banned", sBanned, sizeof(sBanned), "");
			int iBannedTime = StringToInt(sBanned, 10);
			if (StrEqual(sBanned, "true"))
				g_sClientJoinMessageBanned[client] = 0;
			else if (sBanned[0] != '\0')
				g_sClientJoinMessageBanned[client] = iBannedTime;

			KvGetString(hCustomMessageFile, "message", g_sClientJoinMessage[client], sizeof(g_sClientJoinMessage[]), "");
		}

		if (hCustomMessageFile != null)
		{
			CloseHandle(hCustomMessageFile);
			hCustomMessageFile = null;
		}

		CreateTimer(ANNOUNCER_DELAY, DelayAnnouncer, iUserSerial[client]);
	}
	else if (StrEqual(sStorageType, "sql"))
	{
		SQLSelect_JoinClient(client);
	}
}

public void OnClientDisconnect(int client)
{
	FormatEx(g_sAuthID[client], sizeof(g_sAuthID[]), "");
	FormatEx(g_sPlayerName[client], sizeof(g_sPlayerName[]), "");
	FormatEx(g_sPlayerIP[client], sizeof(g_sPlayerIP[]), "");
	g_sClientJoinMessage[client]       = "";
	g_sClientJoinMessageBanned[client] = -1;
	iUserSerial[client] = -1;
	iUserID[client] = -1;
}

//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"
//

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_JoinMsg(int client, int args)
{
	if (!g_hCvar_Enabled.BoolValue)
		return Plugin_Continue;

	if (!client)
	{
		ReplyToCommand(client, "[ConnectAnnounce] Cannot use command from server console");
		return Plugin_Handled;
	}

	char sStorageType[256];
	g_hCvar_StorageType.GetString(sStorageType, sizeof(sStorageType));

	Handle hCustomMessageFile = null;
	if (StrEqual(sStorageType, "local"))
	{
		hCustomMessageFile = CreateKeyValues("custom_messages");

		if (!FileToKeyValues(hCustomMessageFile, g_sCustomMessageFile))
		{
			SetFailState("[ConnectAnnounce] Config file missing!");
			return Plugin_Handled;
		}

		KvRewind(hCustomMessageFile);
	}

	if (args < 1)
	{
		if (StrEqual(g_sClientJoinMessage[client], "reset") || strlen(g_sClientJoinMessage[client]) < 1)
			CPrintToChat(client, "[ConnectAnnounce] No Join Message set! Use sm_joinmsg <your message here> to set one.");
		else
			CPrintToChat(client, "[ConnectAnnounce] Your Join Message is: %s", g_sClientJoinMessage[client]);
	}
	else
	{
		char sArg[256];
		GetCmdArgString(sArg, sizeof(sArg));
		
		ReplaceString(sArg, sizeof(sArg), "%d", "d"); // Fix String formatted incorrectly by adding a new parameter
		ReplaceString(sArg, sizeof(sArg), "%i", "i"); // https://github.com/srcdslab/sm-plugin-ConnectAnnounce/issues/2
		ReplaceString(sArg, sizeof(sArg), "%u", "u");
		ReplaceString(sArg, sizeof(sArg), "%b", "b");
		ReplaceString(sArg, sizeof(sArg), "%f", "f");
		ReplaceString(sArg, sizeof(sArg), "%x", "x");
		ReplaceString(sArg, sizeof(sArg), "%X", "X");
		ReplaceString(sArg, sizeof(sArg), "%s", "s");
		ReplaceString(sArg, sizeof(sArg), "%t", "t");
		ReplaceString(sArg, sizeof(sArg), "%T", "T");
		ReplaceString(sArg, sizeof(sArg), "%c", "C");
		ReplaceString(sArg, sizeof(sArg), "%L", "L");
		ReplaceString(sArg, sizeof(sArg), "%N", "N");

		g_sClientJoinMessage[client] = sArg;

		if (StrEqual(sStorageType, "local"))
		{
			if (KvJumpToKey(hCustomMessageFile, g_sAuthID[client], true))
				KvSetString(hCustomMessageFile, "message", g_sClientJoinMessage[client]);
			else
			{
				SetFailState("[ConnectAnnounce] Could not find/create Key Value!");
				return Plugin_Handled;
			}

			KvRewind(hCustomMessageFile);
			KeyValuesToFile(hCustomMessageFile, g_sCustomMessageFile);

			CPrintToChat(client, "[ConnectAnnounce] Successfully set your join message to: %s", g_sClientJoinMessage[client]);
		}
		else if (StrEqual(sStorageType, "sql"))
		{
			SQLInsertUpdate_JoinClient(client);
		}
	}

	if (StrEqual(sStorageType, "local"))
	{
		if (hCustomMessageFile != null)
		{
			CloseHandle(hCustomMessageFile);
			hCustomMessageFile = null;
		}
	}

	return Plugin_Handled;
}

public Action Command_ResetJoinMsg(int client, int args)
{
	if (!g_hCvar_Enabled.BoolValue)
		return Plugin_Continue;

	if (!client)
	{
		ReplyToCommand(client, "[ConnectAnnounce] Cannot use command from server console");
		return Plugin_Handled;
	}

	char sStorageType[256];
	g_hCvar_StorageType.GetString(sStorageType, sizeof(sStorageType));

	if (StrEqual(sStorageType, "local"))
	{
		Handle hCustomMessageFile = CreateKeyValues("custom_messages");

		if (!FileToKeyValues(hCustomMessageFile, g_sCustomMessageFile))
		{
			SetFailState("[ConnectAnnounce] Config file missing!");
			return Plugin_Handled;
		}

		KvRewind(hCustomMessageFile);

		if (KvJumpToKey(hCustomMessageFile, g_sAuthID[client], true))
			KvSetString(hCustomMessageFile, "message", "reset");

		KvRewind(hCustomMessageFile);

		KeyValuesToFile(hCustomMessageFile, g_sCustomMessageFile);

		if (hCustomMessageFile != null)
			CloseHandle(hCustomMessageFile);
	}
	else if (StrEqual(sStorageType, "sql"))
	{
		g_sClientJoinMessage[client] = "reset";
		SQLInsertUpdate_JoinClient(client);
	}

	CPrintToChat(client, "{green}[ConnectAnnounce] {white}Your Join Message got reset.");
	return Plugin_Handled;
}

public Action Command_Ban(int client, int args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "{green}[SM] {default}Usage: sm_joinmsg_ban <name|#userid|@filter> <optional:time>");
		return Plugin_Handled;
	}

	int  iTarget;
	char sTarget[64];
	char sTime[128];
	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (args > 1)
	{
		GetCmdArg(2, sTime, sizeof(sTime));
		g_sClientJoinMessageBanned[client] = StringToInt(sTime, 10);
	}
	else
	{
		g_sClientJoinMessageBanned[client] = 0;    // Perma ban
	}

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return Plugin_Handled;
	}

	char sStorageType[256];
	g_hCvar_StorageType.GetString(sStorageType, sizeof(sStorageType));

	if (StrEqual(sStorageType, "local"))
	{
		Handle hCustomMessageFile = CreateKeyValues("custom_messages");

		if (!FileToKeyValues(hCustomMessageFile, g_sCustomMessageFile))
		{
			SetFailState("[ConnectAnnounce] Config file missing!");
			return Plugin_Handled;
		}

		KvRewind(hCustomMessageFile);

		char sBannedTime[256];
		IntToString(g_sClientJoinMessageBanned[client], sBannedTime, sizeof(sBannedTime));

		if (KvJumpToKey(hCustomMessageFile, g_sAuthID[client], true))
			KvSetString(hCustomMessageFile, "banned", sBannedTime);
		else
		{
			LogError("[ConnectAnnounce] Could not find/create Key Value!");
			return Plugin_Handled;
		}

		KvRewind(hCustomMessageFile);

		KeyValuesToFile(hCustomMessageFile, g_sCustomMessageFile);

		if (hCustomMessageFile != null)
			CloseHandle(hCustomMessageFile);
	}
	else if (StrEqual(sStorageType, "sql"))
	{
		// TODO: Implement me
	}

	if (g_sClientJoinMessageBanned[client] == -1)
		CReplyToCommand(client, "{green}[ConnectAnnounce] {white}%L has been un-banned.", iTarget);
	else
		CReplyToCommand(client, "{green}[ConnectAnnounce] {white}%L has been banned.", iTarget);
	return Plugin_Handled;
}

public Action Command_Announce(int client, int args)
{
	if (IsFakeClient(client))
		return Plugin_Handled;

	Announcer(client, -1, false);
	return Plugin_Handled;
}

//  #####   #####  #
// #     # #     # #
// #       #     # #
//  #####  #     # #
//       # #   # # #
// #     # #    #  #
//  #####   #### # #######

stock bool DB_Connect()
{
	//PrintToServer("DB_Connect(handle %d, state %d, lock %d)", g_hDatabase, g_DatabaseState, g_iConnectLock);

	if (g_hDatabase != null && g_DatabaseState == DatabaseState_Connected)
		return true;

	// 100k connections in a minute is bad idea..
	if (g_DatabaseState == DatabaseState_Wait)
		return false;

	if (g_DatabaseState != DatabaseState_Connecting)
	{
		if (!SQL_CheckConfig(DATABASE_NAME))
  			SetFailState("Could not find \"%s\" entry in databases.cfg.", DATABASE_NAME);

		g_DatabaseState = DatabaseState_Connecting;
		g_iConnectLock = g_iSequence++;
		Database.Connect(GotDatabase, DATABASE_NAME, g_iConnectLock);
	}

	return false;
}

public void GotDatabase(Database db, const char[] error, any data)
{
	// See if the connection is valid.
	if (db == null)
	{
		LogError("Connecting to database \"%s\" failed: %s", DATABASE_NAME, error);
		return;
	}

	LogMessage("Connected to database.");

	//PrintToServer("GotDatabase(data: %d, lock: %d, g_h: %d, db: %d)", data, g_iConnectLock, g_hDatabase, db);

	// If this happens to be an old connection request, ignore it.
	if (data != g_iConnectLock || (g_hDatabase != null && g_DatabaseState == DatabaseState_Connected))
	{
		if (db)
			delete db;
		return;
	}

	char sDriver[16];
	SQL_GetDriverIdent(g_hDatabase, sDriver, sizeof(sDriver));

	if (!strncmp(sDriver, "my", 2, false))
		g_bSQLite = false;
	else
		g_bSQLite = true;

	g_iConnectLock = 0;
	g_DatabaseState = DatabaseState_Connected;
	g_hDatabase = db;

	DB_SetNames(db);
	DB_CreateTable(db);
}

stock bool DB_Conn_Lost(DBResultSet db)
{
	if (db == null)
	{
		if (g_hDatabase != null)
		{
			LogError("Lost connection to DB. Reconnect after delay.");
			delete g_hDatabase;
			g_hDatabase = null;
		}

		if (g_DatabaseState != DatabaseState_Wait && g_DatabaseState != DatabaseState_Connecting)
		{
			g_DatabaseState = DatabaseState_Wait;
			CreateTimer(RetryTime, Timer_DBReconnect, _, TIMER_FLAG_NO_MAPCHANGE);
		}

		return true;
	}

	return false;
}

stock void DB_Reconnect()
{
	g_DatabaseState = DatabaseState_Disconnected;
	DB_Connect();
}

stock void DB_SetNames(Database db)
{
	static int retries = 0;
	char sQuery[MAX_SQL_QUERY_LENGTH];
	Format(sQuery, sizeof(sQuery), "SET NAMES \"UTF8MB4\"");

	if (DB_Connect())
	{
		db.Query(Query_ErrorCheck, sQuery);
	}
	else
	{
		if (retries < g_cvQueryRetry.IntValue)
		{
			PrintToServer("[ConnectAnnounce] Failed to connect to database, retrying... (%d/%d)", retries, g_cvQueryRetry.IntValue);
			PrintToServer("[ConnectAnnounce] Query: %s", sQuery);
			DB_SetNames(db);
			retries++;
		}
		else
		{
			LogError("Failed to connect to database after %d retries, aborting", retries);
		}

	}

	retries = 0;
}

stock void DB_CreateTable(Database db)
{
	static int retries = 0;
	char sQuery[MAX_SQL_QUERY_LENGTH];

	if (g_bSQLite)
		FormatEx(sQuery, sizeof(sQuery), 
			"CREATE TABLE IF NOT EXISTS `join` ( \
			`steamid` TEXT NOT NULL, \
			`name` TEXT NOT NULL, \
			`message` TEXT, \
			PRIMARY KEY(`steamid`) \
			)"
		);
	else
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `join` ( \
			`steamid` VARCHAR(32) NOT NULL, \
			`name` VARCHAR(32) NOT NULL, \
			`message` VARCHAR(256), \
			PRIMARY KEY(`steamid`) \
			);"
		);

	if (DB_Connect())
	{
		db.Query(Query_ErrorCheck, sQuery);
	}
	else
	{
		if (retries < g_cvQueryRetry.IntValue)
		{
			PrintToServer("[ConnectAnnounce] Failed to connect to database, retrying... (%d/%d)", retries, g_cvQueryRetry.IntValue);
			PrintToServer("[ConnectAnnounce] Query: %s", sQuery);
			DB_CreateTable(db);
			retries++;
		}
		else
		{
			LogError("Failed to connect to database after %d retries, aborting", retries);
		}

	}

	retries = 0;
}

public void Query_ErrorCheck(Database db, DBResultSet results, const char[] error, any data)
{
	if (DB_Conn_Lost(results) || error[0])
		LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
}

public Action Timer_DBReconnect(Handle timer, any data)
{
	DB_Reconnect();
	return Plugin_Continue;
}

stock void SQLSelect_JoinClient(any client)
{
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(g_sAuthID[client]);

	SQLSelect_Join(pack);
}

stock void SQLSelect_Join(any data)
{
	static int retries = 0;
	char sClientSteamID[32], sQuery[MAX_SQL_QUERY_LENGTH];

	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	pack.ReadCell();
	pack.ReadString(sClientSteamID, sizeof(sClientSteamID));

	Format(sQuery, sizeof(sQuery), "SELECT `message` FROM `join` WHERE `steamid` = '%s';", sClientSteamID);

	if (DB_Connect())
	{
		g_hDatabase.Query(OnSQLSelect_Join, sQuery, data);
	}
	else
	{
		if (retries < g_cvQueryRetry.IntValue)
		{
			PrintToServer("[ConnectAnnounce] Failed to connect to database, retrying... (%d/%d)", retries, g_cvQueryRetry.IntValue);
			PrintToServer("[ConnectAnnounce] Query: %s", sQuery);
			SQLSelect_Join(data);
			retries++;
		}
		else
		{
			LogError("Failed to connect to database after %d retries, aborting", retries);
			delete pack;
		}

	}

	retries = 0;
}

stock void OnSQLSelect_Join(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();
	delete pack;

	if (DB_Conn_Lost(results) || error[0] != '\0')
	{
		LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
		return;
	}

	if (results.FetchRow())
		results.FetchString(0, g_sClientJoinMessage[client], sizeof(g_sClientJoinMessage[]));

	delete results;

	CreateTimer(ANNOUNCER_DELAY, DelayAnnouncer, iUserSerial[client]);
}

stock void SQLInsertUpdate_Join(any data)
{
	static int retries = 0;

	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sQuery[MAX_SQL_QUERY_LENGTH];
	char sClientSteamID[32], sClientName[32], sClientNameEscaped[32];
	char sMessage[MAX_CHAT_LENGTH], sMessageEscaped[2 * MAX_CHAT_LENGTH + 1];

	pack.ReadCell();
	pack.ReadString(sClientSteamID, sizeof(sClientSteamID));
	pack.ReadString(sClientName, sizeof(sClientName));
	pack.ReadString(sMessage, sizeof(sMessage));

	SQL_EscapeString(g_hDatabase, sClientName, sClientNameEscaped, sizeof(sClientNameEscaped));
	SQL_EscapeString(g_hDatabase, sMessage, sMessageEscaped, sizeof(sMessageEscaped));

	Format(sQuery, sizeof(sQuery), "INSERT INTO `join` (`steamid`, `name`, `message`) VALUES ('%s', '%s', '%s') ON DUPLICATE KEY UPDATE name='%s', message='%s';",
			sClientSteamID, sClientNameEscaped, sMessageEscaped, sClientNameEscaped, sMessageEscaped);

	if (DB_Connect())
	{
		g_hDatabase.Query(OnSQLInsertUpdate_Join, sQuery, data);
	}
	else
	{
		if (retries < g_cvQueryRetry.IntValue)
		{
			PrintToServer("[ConnectAnnounce] Failed to connect to database, retrying... (%d/%d)", retries, g_cvQueryRetry.IntValue);
			PrintToServer("[ConnectAnnounce] Query: %s", sQuery);
			SQLInsertUpdate_Join(data);
			retries++;
		}
		else
		{
			LogError("Failed to connect to database after %d retries, aborting", retries);
			delete pack;
		}
	}

	retries = 0;
}

stock void OnSQLInsertUpdate_Join(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sClientSteamID[32];
	char sClientName[32];
	char sMessage[MAX_CHAT_LENGTH];
	char sMessageEscaped[2 * MAX_CHAT_LENGTH + 1];

	int client = pack.ReadCell();
	pack.ReadString(sClientSteamID, sizeof(sClientSteamID));
	pack.ReadString(sClientName, sizeof(sClientName));
	pack.ReadString(sMessage, sizeof(sMessage));
	delete pack;

	SQL_EscapeString(g_hDatabase, sMessage, sMessageEscaped, sizeof(sMessageEscaped));

	if (DB_Conn_Lost(results) || error[0] != '\0')
	{
		LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
		CPrintToChat(client, "[ConnectAnnounce] An error occurred while saving your join message, please try again later.");
		return;
	}

	CPrintToChat(client, "[ConnectAnnounce] Successfully set your join message to: %s", sMessageEscaped);

	delete results;
}

stock void SQLInsertUpdate_JoinClient(any client)
{
	char sClientSteamID[32];
	char sClientName[32];

	FormatEx(sClientSteamID, sizeof(sClientSteamID), "%s", g_sAuthID[client]);
	FormatEx(sClientName, sizeof(sClientName), "%s", g_sPlayerName[client]);
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sClientSteamID);
	pack.WriteString(sClientName);
	pack.WriteString(g_sClientJoinMessage[client]);

	SQLInsertUpdate_Join(pack);
}

public void SQLSelect_HlstatsxCB2(Database db, DBResultSet results, const char[] error, any data)
{
	if (DB_Conn_Lost(results) || error[0] != '\0')
	{
		LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
		return;
	}

	int client = 0;

	if ((client = GetClientOfUserId(data)) == 0)
	{
		return;
	}

	int iRank = -1;
	if (results.RowCount > 0)
	{
		int iField;

		results.FetchRow();
		results.FieldNameToNum("rank", iField);
		iRank = results.FetchInt(iField);
	}

	delete results;

	Announcer(client, iRank, true);
}

public void SQLSelect_HlstatsxCB(Database db, DBResultSet results, const char[] error, any data)
{
	int client = 0;

	if ((client = GetClientOfUserId(data)) == 0)
	{
		return;
	}

	if (DB_Conn_Lost(results) || error[0] != '\0')
	{
		LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
		return;
	}

	int iPlayerId = -1;
	if (results.RowCount > 0)
	{
		int iField;
		results.FetchRow();
		results.FieldNameToNum("playerId", iField);
		iPlayerId = results.FetchInt(iField);
	}

	char sQuery[MAX_SQL_QUERY_LENGTH];
	Format(sQuery, sizeof(sQuery), "SELECT T1.playerid, T1.skill, T2.rank FROM hlstats_Players T1 LEFT JOIN (SELECT skill, (@v_id := @v_Id + 1) AS rank	FROM (SELECT DISTINCT skill FROM hlstats_Players WHERE game = 'css-ze' ORDER BY skill DESC) t, (SELECT @v_id := 0) r) T2 ON T1.skill = T2.skill	WHERE game = 'css-ze' AND playerId = %d	ORDER BY skill DESC", iPlayerId);
	g_hDatabase_Hlstatsx.Query(SQLSelect_HlstatsxCB2, sQuery, iUserID[client]);

	delete results;
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ##
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ##
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ##
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######
public void Announcer(int client, int iRank, bool sendToAll)
{
	char        sFinalMessage[MAX_CHAT_LENGTH * 2];
	static char sCountry[32];

	strcopy(sFinalMessage, sizeof(sFinalMessage), g_sJoinMessageTemplate);

	AdminId aid;

	if (StrContains(sFinalMessage, "{PLAYERTYPE}"))
	{
		aid = GetUserAdmin(client);

		char sPlayerType[256] = "";

		// Admin Type
		if (GetAdminFlag(aid, Admin_Generic) || GetAdminFlag(aid, Admin_Root) || GetAdminFlag(aid, Admin_RCON) || GetAdminFlag(aid, Admin_Custom1))
		{
			bool bGroupFound = false;
			char group[64];
			int  iGroupCount = GetAdminGroupCount(aid);
			for (int i = 0; i < iGroupCount; i++)
			{
				GroupId gid = GetAdminGroup(aid, i, group, sizeof(group));
				if (gid != INVALID_GROUP_ID && (GetAdmGroupAddFlag(gid, Admin_Generic) || GetAdmGroupAddFlag(gid, Admin_Root) || GetAdmGroupAddFlag(gid, Admin_RCON)))
				{
					sPlayerType = group;
					bGroupFound = true;
					break;
				}
				else if (gid != INVALID_GROUP_ID && GetAdmGroupAddFlag(gid, Admin_Custom1))
				{
					sPlayerType = group;
					bGroupFound = true;
				}
			}

			if (!bGroupFound)
			{
				if (GetAdminFlag(aid, Admin_Root))
					sPlayerType = "Community Manager";
				else if (GetAdminFlag(aid, Admin_RCON))
					sPlayerType = "Server Manager";
				else if (GetAdminFlag(aid, Admin_Generic))
					sPlayerType = "Admin";
				else if (GetAdminFlag(aid, Admin_Custom1))
					sPlayerType = "VIP";
			}
		}

		// Player Type
		if (!sPlayerType[0])
		{
			if (GetAdminFlag(aid, Admin_Custom5))
				sPlayerType = "Supporter";
			else if (GetAdminFlag(aid, Admin_Custom6))
				sPlayerType = "Member";
			else
				sPlayerType = "Player";
		}

		// Ranking
		if (!GetAdminFlag(aid, Admin_Root) && !GetAdminFlag(aid, Admin_RCON))
		{
			if (GetAdminFlag(aid, Admin_Custom4))
				StrCat(sPlayerType, sizeof(sPlayerType), " Top25");
			else if (GetAdminFlag(aid, Admin_Custom3))
				StrCat(sPlayerType, sizeof(sPlayerType), " Top50");
		}

		ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{PLAYERTYPE}", sPlayerType);
	}

	if (StrContains(sFinalMessage, "{RANK}"))
	{
		if (iRank != -1)
		{
			char sBuffer[16];
			Format(sBuffer, sizeof(sBuffer), "[#%d] ", iRank);
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{RANK}", sBuffer);
		}
		else
		{
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{RANK}", "");
		}
	}

#if defined _Connect_Included
	if (StrContains(sFinalMessage, "{NOSTEAM}"))
	{
		if (!SteamClientAuthenticated(g_sAuthID[client]))
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{NOSTEAM}", " <NoSteam>");
		else
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{NOSTEAM}", "");
	}
#endif

	if (StrContains(sFinalMessage, "{STEAMID}"))
	{
		ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{STEAMID}", g_sAuthID[client]);
	}

	if (StrContains(sFinalMessage, "{NAME}"))
	{
		ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{NAME}", g_sPlayerName[client]);
	}

	if (StrContains(sFinalMessage, "{COUNTRY}"))
	{
		char  sCountryColor[64] = "";
		Regex regexHEX          = CompileRegex("{COUNTRY_COLOR:(#?)([A-Fa-f0-9]{6})}");
		Regex regexColor        = CompileRegex("{COUNTRY_COLOR:([a-z-A-Z]+)}");

		if ((MatchRegex(regexHEX, sFinalMessage) >= 1 && GetRegexSubString(regexHEX, 0, sCountryColor, sizeof(sCountryColor)))
		    || (MatchRegex(regexColor, sFinalMessage) >= 1 && GetRegexSubString(regexColor, 0, sCountryColor, sizeof(sCountryColor))))
		{
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), sCountryColor, "");
			char[] sTagCountryColor = "{COUNTRY_COLOR:";
			int iStartPos           = strlen(sTagCountryColor);
			Format(sCountryColor, sizeof(sCountryColor), "%s", sCountryColor[iStartPos - 1]);
			sCountryColor[0] = '{';
		}

		if (GeoipCountry(g_sPlayerIP[client], sCountry, sizeof(sCountry)) && !StrEqual("", sCountry))
		{
			char sBuffer[128];
			Format(sBuffer, sizeof(sBuffer), " from %s%s{default}", sCountryColor, sCountry);
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{COUNTRY}", sBuffer);
		}
		else
			ReplaceString(sFinalMessage, sizeof(sFinalMessage), "{COUNTRY}", "");

		delete regexHEX;
		delete regexColor;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////

	if (CheckCommandAccess(client, "sm_joinmsg", ADMFLAG_CUSTOM1) && !StrEqual(g_sClientJoinMessage[client], "reset") && g_sClientJoinMessageBanned[client] == -1)
	{
		Format(sFinalMessage, sizeof(sFinalMessage), "%s %s", sFinalMessage, g_sClientJoinMessage[client]);
	}

	if (sendToAll)
		CPrintToChatAll(sFinalMessage);
	else
		CPrintToChat(client, sFinalMessage);
}

public Action DelayAnnouncer(Handle timer, any serialClient)
{
	int client = GetClientFromSerial(serialClient);

	if (client == 0 || IsFakeClient(client))
		return Plugin_Stop;

	if (g_hDatabase_Hlstatsx == null)
	{
		Announcer(client, -1, true);
	}
	else
	{
		static char sAuth[32];
		strcopy(sAuth, sizeof(sAuth), g_sAuthID[client][8]);

		char sQuery[255];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hlstats_PlayerUniqueIds WHERE uniqueId = '%s' AND game = 'css-ze'", sAuth);
		g_hDatabase_Hlstatsx.Query(SQLSelect_HlstatsxCB, sQuery, iUserID[client]);
	}
	return Plugin_Stop;
}
