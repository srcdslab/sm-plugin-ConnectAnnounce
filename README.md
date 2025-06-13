# ConnectAnnounce

ConnectAnnounce is a SourceMod plugin designed to announce player connections with customizable messages. It supports threaded queries to prevent server freeze and integrates with HLstatsX for additional player information.

> [!IMPORTANT]
> For versions 3.5.0: If you are using an older version of the plugin, please perform the migration by [following the provided steps](#migration).

## Features

- Announce player connections with customizable messages.
- Support for threaded SQL queries to prevent server freeze.
- Admin command access control for setting join messages.
- Integration with (for retrieving player information):
  - Connect extension
  - Sourcebans++
  - HLStatsX
  - EntWatch
  - KbRestrict

## Installation

1. Download the latest release from the [Releases](https://github.com/srcdslab/sm-plugin-ConnectAnnounce/releases) page.
2. Extract the contents of the release archive to your SourceMod `plugins` directory.
3. Configure the plugin by editing the `connectannounce.cfg` file located in the `cfg/sourcemod` directory.

## Configuration

The plugin can be configured using the `connectannounce.cfg` file. Here are some of the available settings:

```plaintext
// Enable or disable the plugin
sm_connect_announce "1"

// Storage type used for connect messages [sql, local]
sm_connect_announce_storage "sql"

// Add HLstatsX informations on player connection?
sm_connect_announce_hlstatsx "1"

// How many times should the plugin retry after a fail-to-run query?
sm_connect_announce_query_retry "5"

// Formating returned bans count [0 = Count only 1 = Count only if > 0 | 2 = Count + Text]
sm_connect_announce_ban_format "0"

// AuthID type used for connect messages [0 = Engine, 1 = Steam2, 2 = Steam3, 3 = Steam64]
sm_connect_announce_authid_type "1"

// Set the HLstatsX database configuration name (Server game code used for hlstatsx)
sm_connect_announce_hlstatsx_table "css-ze"
```

**You can configured the player connect message like you want in** `addons/sourcemod/configs/connect_announce/settings.cfg`

## Variables

These variables can be used in `addons/sourcemod/configs/connect_announce/settings.cfg` to display information about the player.

- `{PLAYERTYPE}` - Categorizes players based on their role or behavior in the server.

- `{RANK}` - Tracks player rankings.

- `{NOSTEAM}` - Specifically handles players who are not connected via NoSteam.

- `{EBANS}` - Numbers of Ebans.

- `{KBANS}` - Numbers of Kbans.

- `{BANS}` - Number of bans. (SBPP only)

- `{COMMS}` - Number of bans. (SBPP only)

- `{MUTES}` - Number of mutes (SBPP only)

- `{GAGS}` - Number of gags (SBPP only)

- `{STEAMID}` - Player SteamID. [See cvar: `sm_connect_announce_authid_type`]

- `{NAME}` - Player name

- `{COUNTRY}` - Country from which the player connects.

# Migration
## 3.4.1 to 3.5.0

You need to run the following queries:

### MYSQL & SQLITE
```sql
ALTER TABLE `join` ADD COLUMN `is_banned` INTEGER DEFAULT -1;
```