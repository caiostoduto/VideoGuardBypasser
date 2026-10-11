import { definePluginSettings } from "@api/Settings";
import definePlugin, { OptionType } from "@utils/types";
import { findStoreLazy } from "@webpack";
import { LocaleStore, showToast, UserStore } from "@webpack/common";

const VIDEO_GUARD = "2026-08-video-guard";
const notifiedErrors = new Map<string, string>();

function showConfigError(key: string, value: string, message: { en: string; ptBR: string; }) {
    if (notifiedErrors.get(key) === value) return;
    notifiedErrors.set(key, value);

    const locale = LocaleStore.locale.toLowerCase();
    showToast(locale.startsWith("pt") ? message.ptBR : message.en, "failure");
}

interface ApexExperimentStore {
    getServerAssignment(type: string, id: string, experiment: string): { variantId: string; };
    createOverride(experiment: string, variant: string): void;
    // ...
}

/**
 * Sets the `VIDEO_GUARD` experiment to variant `-1` (disabled) for the current user, if it's not already set.
 * This client-side experiment gate can prevent the screenshare UI from starting.
 */
function setVideoGuardExperiment(): void {
    const user = UserStore.getCurrentUser();
    if (!user) return;

    const store = findStoreLazy("ApexExperimentStore") as ApexExperimentStore;

    if (store.getServerAssignment("user", user.id, VIDEO_GUARD).variantId !== "-1") {
        store.createOverride(VIDEO_GUARD, "-1");
    }
}

const settings = definePluginSettings({
    subnets: {
        description: "IPv4 subnets in CIDR notation, separated by spaces.",
        type: OptionType.STRING,
        default: "190.98.192.0/18"
    },
    portRange: {
        description: "Inclusive port range in min-max format (1024-65535)",
        type: OptionType.STRING,
        default: "10000-20000"
    }
});

/**
 * Generates a random IPv4 address from the given subnets in CIDR notation.
 * @param subnets A string containing IPv4 subnets in CIDR notation, separated by whitespace.
 * @returns A random IPv4 address as a string, or undefined if no valid subnets are provided.
 */
function randomIpFromSubnets(subnets: string): string | undefined {
    const ranges: Array<{ first: number; count: number; }> = [];

    for (const line of subnets.split(/\s+/)) {
        const match = line.trim().match(/^(\d{1,3}(?:\.\d{1,3}){3})\/(\d{1,2})$/);
        if (!match) continue;

        const octets = match[1].split(".").map(Number);
        const prefix = Number(match[2]);
        if (octets.some(octet => octet > 255) || prefix > 32) continue;

        const address = octets.reduce((value, octet) => value * 256 + octet, 0);
        const size = 2 ** (32 - prefix);
        const network = Math.floor(address / size) * size;
        const hostCount = prefix <= 30 ? size - 2 : size;
        ranges.push({ first: network + (prefix <= 30 ? 1 : 0), count: hostCount });
    }

    const total = ranges.reduce((sum, range) => sum + range.count, 0);
    if (!total) return;

    let offset = Math.floor(Math.random() * total);
    for (const range of ranges) {
        if (offset < range.count) {
            const address = range.first + offset;
            return [24, 16, 8, 0].map(shift => Math.floor(address / 2 ** shift) % 256).join(".");
        }
        offset -= range.count;
    }
}

export default definePlugin({
    name: "VideoGuardBypasser",
    description: "Educational PoC: disables the Video Guard screenshare gate and replaces the IPv4 address and port reported to the voice websocket.",
    authors: [{ name: "Caio Stoduto", id: 0n }],
    settings,

    start() {
        setVideoGuardExperiment();
        console.log("[Video Guard bypasser] Started");
    },

    patches: [
        {
            find: "Connect called with already existing websocket",
            replacement: [
                {
                    match: /selectProtocol\((\i),(\i),(\i),(\i)\)\{/,
                    replace: "selectProtocol($1,$2,$3,$4){$3=$self.onSelectProtocol(this,$3);"
                }
            ]
        }
    ],

    /**
     * Rewrites the address/port the client reports to the voice websocket after connecting to the RTC/SFU.
     * The client reported IPv4 is used by the websocket for application-layer location policy censoring.
     * @param _sock The socket
     * @param data The connection data
     * @returns The updated connection data
     */
    onSelectProtocol(_sock: unknown, data: {
        address: string;
        mode: string;
        port: number;
    }) {
        const address = randomIpFromSubnets(settings.store.subnets);
        if (!address) {
            showConfigError("subnets", settings.store.subnets, {
                en: "No valid IPv4 CIDR subnets configured. Check the Subnets setting.",
                ptBR: "Nenhuma sub-rede IPv4 CIDR válida configurada. Verifique a opção Subnets."
            });
            return data;
        }
        notifiedErrors.delete("subnets");

        const portRange = settings.store.portRange.match(/^\s*(\d+)\s*-\s*(\d+)\s*$/);
        const startPort = portRange ? Number(portRange[1]) : NaN;
        const endPort = portRange ? Number(portRange[2]) : NaN;
        const validRange = portRange !== null && [startPort, endPort].every(port => port >= 1024 && port <= 65535);
        if (!validRange) {
            showConfigError("portRange", settings.store.portRange, {
                en: "Invalid port range. Use min-max with both ports from 1024 to 65535; using 10000-20000.",
                ptBR: "Intervalo de portas inválido. Use mínimo-máximo com ambas entre 1024 e 65535; usando 10000-20000."
            });
        } else {
            notifiedErrors.delete("portRange");
        }
        const minPort = Math.min(...(validRange ? [startPort, endPort] : [10000, 20000]));
        const maxPort = Math.max(...(validRange ? [startPort, endPort] : [10000, 20000]));
        const port = minPort + Math.floor(Math.random() * (maxPort - minPort + 1));

        console.log("[Video Guard bypasser] selectProtocol", data);

        return {
            ...data,
            address,
            port,
        };
    }
});
