<h1 align="center">VideoGuardBypasser</h1>

<p align="center">
    <a href="https://discord.com"><img src="https://img.shields.io/badge/Discord-242629?logo=discord" alt="Discord"/></a>
    <a href="https://vencord.dev"><img src="https://img.shields.io/badge/Vencord-242629?logo=vencord" alt="Vencord"/></a>
</p>

<p align="center"><strong>English</strong> · <a href="/docs/README.pt-BR.md">Português (Brasil)</a></p>

This plugin allows Discord users in Brazil to restore Go Live and video chat features<sup>[∗](https://discord.com/blog/a-letter-to-the-discord-community-in-brazil)</sup>. It does so by exploiting a small vulnerability in Discord's implementation of location-based restriction policies.

> [!NOTE]
> This repository is intended purely for educational purposes.

<p align="center"><a href="#how-it-works-technical">How it works (technical)</a> · <a href="#installation-vencord">Installation</a> · <a href="#settings">Settings</a></p>

## How it works (technical)

This repository contains a [Vencord](https://vencord.dev/) plugin (a Discord client modification) that changes some client behavior ([Discord Desktop](https://discord.com/download), [Vesktop](https://vesktop.dev/), or [Browser](https://discord.com/app)) to get around the imposed restrictions. The restriction consists of two parts:

### Client-side

This is the code that runs on your computer and handles interaction between the user and the server. Since it runs locally, it is easy to modify. For this reason, many user-created modifications add new features to the client, as Vencord itself does.

The restriction imposed by Discord in its client is a simple hidden "flag" (`2026-08-video-guard`<sup>[∗](https://github.com/EduardoVasconceloss/StreamFix/blob/4ab98977fa15e6c841106ef40b89c5034938a02d/streamFix/tunnel/trava.ts#L24)</sup>) that determines how Discord behaves based on its value. The value is set when the application starts, based on your IP address. If the flag's value is `-1`, Discord behaves as if the restriction does not apply to you, and its interface remains unblocked. If the value is different, the interface visually disables the buttons for turning on your camera and sharing your screen, and also hides other people's screen shares.

To get around this, the plugin simply forces the flag's value to `-1`, removing the visual block implemented in a way that cannot be traced<sup>[∗](https://github.com/caiostoduto/VideoGuardBypasser/blob/90ddcd6b4798dc61a136e789bb6d8c4dfb911cca/vencord/index.ts#L27)</sup>.

### Server-side

This refers to Discord's servers, and obviously it is not possible to modify the code running on them.

When you join a call (or click to watch a screen share) in Discord, your client (the application) exchanges messages over WebSocket Secure with the media server you want to connect to (`*.discord.media`), requesting a WebRTC connection (the calling protocol used by Discord) with the other peers. While the client and server exchange these messages, the client establishes a connection with Interactive Connectivity Establishment (ICE), which returns the client's public IPv4 address. Finally, the client sends this IP address to the media server in the message exchange (only in Discord Desktop). The server receives the address, infers your location from it, and, if necessary, applies its location-based restriction policies to prevent you from viewing other people's streams or other people from viewing your stream.

This system has a well-known vulnerability<sup>[∗](https://cwe.mitre.org/data/definitions/20.html)</sup>: data sent by the client should never be trusted without validation. As described in the previous [Client-side](#client-side) section, users can modify client behavior, including its communication with the server.

To get around the restriction applied by the media server, the plugin intercepts the message the client sends with its IP address and changes its contents to include a different address that is not subject to the restriction<sup>[∗](https://github.com/caiostoduto/VideoGuardBypasser/blob/90ddcd6b4798dc61a136e789bb6d8c4dfb911cca/vencord/index.ts#L117)</sup>, because the server does not validate it correctly.

## Installation (Vencord)

> [!WARNING]
> Using this plugin may violate [Discord's Terms of Service](https://discord.com/terms). Use it at your own risk.

### Automated script

Because of Vencord's architecture, installing a custom plugin is not straightforward. To simplify the process, an interactive script was created to automate all the steps.

<details closed>
<summary>What the script does</summary>

1. Checks whether the prerequisites are installed
2. (Windows) Installs `git` via `winget` if it is not already installed
3. Installs Node.js and pnpm locally if needed (if not installed or outdated)
4. Downloads the plugin
5. Builds Vencord with the plugin
6. (Discord Desktop) Inject Vencord into Discord
</details>

#### Windows (PowerShell)

Open a PowerShell window and run:

```powershell
irm https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1 | iex
```

After installation, restart Discord. If you installed it in Discord Desktop, you might need to run the command again after a Discord update<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

<details closed>
<summary>To specify the Vencord installation location</summary>

```powershell
$installer = irm 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1'
& ([scriptblock]::Create($installer)) -VencordDir "$HOME\Vencord"
```
</details>

#### Linux/MacOS

Prerequisites: `git` and `curl` or `wget`

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh | bash
```

After installation, restart Discord. If you installed it in Discord Desktop, you might need to run the command again after a Discord update<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

<details closed>
<summary>To specify the Vencord installation location</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh \
  | bash -s -- --vencord-dir "$HOME/Vencord"
```
</details>

### Manual

This is a [Vencord](https://vencord.dev) _userplugin_ and must be built as part of a checkout of its source code. Before proceeding, I recommend reading at least the [Building Vencord](https://docs.vencord.dev/installing/#building-vencord) guide.

```sh
# Building Vencord (https://docs.vencord.dev/installing/#building-vencord)
git clone https://github.com/Vendicated/Vencord
cd Vencord
pnpm install --frozen-lockfile

# Custom Plugins (https://docs.vencord.dev/installing/custom-plugins/)
mkdir -p src/userplugins/videoGuardBypasser
curl https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts -o src/userplugins/videoGuardBypasser/index.ts

pnpm build # or pnpm buildWeb
pnpm inject # Discord Desktop only
```

After installation, restart Discord. If you installed it in Discord Desktop, you might need to run the command again after a Discord update<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

## Settings

| Setting | Default value | Description |
| --- | --- | --- |
| **Subnets** | `190.98.192.0/18` | IPv4 ranges in CIDR notation, separated by spaces. |
| **Port range** | `10000-20000` | Inclusive range in `minimum-maximum` format; both ports must be between 1024 and 65535. |
