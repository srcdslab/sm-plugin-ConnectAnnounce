# ConnectAnnounce

ConnectAnnounce is a SourceMod plugin designed to announce player connections with customizable messages. It supports threaded queries to prevent server freeze and integrates with HLstatsX for additional player information.

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
sm_connectannounce_enable "1"

// Set the default join message
sm_connectannounce_default_message "Welcome to the server, {name}!"

// Enable or disable HLstatsX integration
sm_connectannounce_hlstatsx_enable "1"

// Set the HLstatsX database configuration name
sm_connectannounce_hlstatsx_db "hlstatsx"
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

- `{STEAMID}` - Player identification provided by Steam AuthId_Steam2 format.

- `{NAME}` - Player name

- `{COUNTRY}` - Country where the player connection from.
