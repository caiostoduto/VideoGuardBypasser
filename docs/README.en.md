<div align="right">

**English** · [Português (Brasil)](/docs/README.pt-BR.md)

</div>

# VideoGuardBypasser

> [!NOTE]
> The point is to demonstrate that client-reported data is under the client's control: a server must not trust a self-reported address as proof of a user's location or use it as the sole basis for application-layer (OSI Layer 7) policy decisions.

An educational proof of concept for studying two client-side voice and screenshare flows in Discord. It has two independent parts:

- On startup, it overrides the `2026-08-video-guard` experiment with `-1` (disabled). The experiment controls a client-side UI gate that can block screensharing.
- During voice connection setup, the client communicates with a `*.discord.media` websocket, receives an RTC/SFU address and port, connects to that RTC/SFU, and then reports its IPv4 address to the websocket. This plugin intercepts the `selectProtocol` response and substitutes a configured IPv4 address and port before the client reports them. Discord's location policy treats the reported IPv4 as the client's address, so it considers the substituted address's location instead of the client's actual location.

## Install

> [!WARNING]
> This tool might be against [Discord's ToS](https://discord.com/terms). Use it at your own risk.

This is a Vencord userplugin, so it must be built as part of a Vencord source checkout; it cannot be compiled as a standalone TypeScript package. If you have not set up a source checkout yet, follow Vencord's [Building Vencord guide](https://docs.vencord.dev/installing/#building-vencord) first. The [custom plugin instructions](https://docs.vencord.dev/installing/custom-plugins/) describe the `src/userplugins` layout in more detail.

Copy this repository's `videoGuardBypasser` folder into `<Vencord checkout>/src/userplugins/`, so the plugin's entry point is at `src/userplugins/videoGuardBypasser/index.ts`. From the Vencord checkout, build for your target platform:

```sh
pnpm build
```

For a web build, use `pnpm buildWeb` instead. After rebuilding, restart Discord and enable **VideoGuardBypasser** in Vencord's plugin settings.

## Settings

- **Subnets**: whitespace-separated IPv4 CIDR ranges. The plugin selects an address from the configured ranges. For prefixes up to `/30`, network and broadcast addresses are excluded. If none are valid, a localized error toast is shown and the address is left unchanged.
- **Port range**: inclusive `min-max` range. Both endpoints must be between 1024 and 65535; ranges including reserved ports (0–1023) are rejected and fall back to `10000-20000`, with a localized error toast. Reversed endpoints are accepted.
