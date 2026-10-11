<div align="right">

**English** · [Português (Brasil)](/docs/README.pt-BR.md)

</div>

# VideoGuardBypasser

> [!NOTE]
> The point is to demonstrate that client-reported data is under the client's control: a server must not trust a self-reported address as proof of a user's location or use it as the sole basis for application-layer (OSI Layer 7) policy decisions.

An educational proof of concept for studying two client-side voice and screenshare flows in Discord. It has two independent parts:

- On startup, it overrides the `2026-08-video-guard` experiment with `-1` (disabled). The experiment controls a client-side UI gate that can block screensharing.
- During voice connection setup, the client communicates with a `*.discord.media` websocket, receives an RTC/SFU address and port, connects to that RTC/SFU, and then reports its IPv4 address to the websocket. This plugin intercepts the `selectProtocol` response and substitutes a configured IPv4 address and port before the client reports them. Discord's location policy treats the reported IPv4 as the client's address, so it considers the substituted address's location instead of the client's actual location.

## Install (Vencord)

> [!WARNING]
> This tool might be against [Discord's ToS](https://discord.com/terms). Use it at your own risk.

### Automatic

#### Linux/MacOS

Requirements: `git` and `curl` or `wget`.

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh | bash
```

The installer uses `~/Vencord` by default. Pass options through `bash -s --` to use another checkout or language:

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh \
  | bash -s -- --vencord-dir "$HOME/src/Vencord" --lang pt
```

Supported options are `--vencord-dir PATH` and `--lang en|pt` (also accepted as `--vencord-dir=PATH` and `--lang=pt`). The language is detected from the system locale when `--lang` is omitted.

#### Windows (PowerShell)

Run this in an interactive PowerShell window. Git is required; if it is missing, the installer offers to install Git for Windows with `winget`. `winget.exe` is needed for that option. `curl.exe` or `wget.exe` is also required.

```powershell
irm https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1 | iex
```

The default Vencord checkout is `$HOME\Vencord`. To pass a different path or select a language, download and invoke the script block with parameters:

```powershell
$installer = irm 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1'
& ([scriptblock]::Create($installer)) -VencordDir "$HOME\src\Vencord" -Language pt
```

`-VencordDir` accepts a checkout path and `-Language` accepts `en` or `pt`. If PowerShell blocks a saved `.ps1` file because of the execution policy, you can allow scripts for the current PowerShell window only with `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`; closing the window resets that setting.

#### What the automatic installer does

It clones Vencord into the default path (or updates the existing checkout after asking), reads the required Node.js and pnpm versions from Vencord's `package.json`, installs the plugin, and builds the selected target. It checks for a suitable Node.js and pnpm first. If either is missing or too old, it asks before downloading/installing it locally: Node.js uses an LTS release that meets Vencord's minimum version (about 100 MB installed), and pnpm uses the version required by Vencord (about 10 MB installed). These tools are stored under `~/.local/share/vencord-installer/` on Linux/macOS or `%LOCALAPPDATA%\vencord-installer\` on Windows, and are added to `PATH` for the installer run only.

The installer asks which target to build. For the Discord app target, follow the injector prompts. When it finishes, restart Discord and enable **VideoGuardBypasser** under **Settings → Plugins → VideoGuardBypasser**. For Vesktop and web builds, it prints Vencord's custom-build instructions.

###  Manual

This is a Vencord userplugin, so it must be built as part of a Vencord source checkout; it cannot be compiled as a standalone TypeScript package. If you have not set up a source checkout yet, follow Vencord's [Building Vencord guide](https://docs.vencord.dev/installing/#building-vencord) first. The [custom plugin instructions](https://docs.vencord.dev/installing/custom-plugins/) describe the `src/userplugins` layout in more detail.

```sh
git clone https://github.com/Vendicated/Vencord
cd Vencord
pnpm install --frozen-lockfile
mkdir -p src/userplugins/videoGuardBypasser
curl https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts -o src/userplugins/videoGuardBypasser/index.ts
pnpm build
pnpm inject
```

For a web build, use `pnpm buildWeb` instead of `pnpm build`; follow the custom-build guide to load it in the browser. After installing the Discord app build, restart Discord and enable **VideoGuardBypasser** under **Settings → Plugins → VideoGuardBypasser**.

## Settings

| Setting | Default | Description |
| --- | --- | --- |
| **Subnets** | `190.98.192.0/18` | Space-separated IPv4 ranges in CIDR notation. |
| **Port range** | `10000-20000` | Inclusive `min-max` range; both ports must be between 1024 and 65535. |
