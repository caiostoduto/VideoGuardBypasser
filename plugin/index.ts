/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Caio Stoduto
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { definePluginSettings } from "@api/Settings";
import definePlugin, { OptionType } from "@utils/types";
import { findStoreLazy } from "@webpack";
import { LocaleStore, showToast, UserStore } from "@webpack/common";

// ---------------------------------------------------------------------------
// Constants & types
// ---------------------------------------------------------------------------

const VIDEO_GUARD_EXPERIMENT = "2026-08-video-guard";
const DISABLED_VARIANT = "-1";

const CIDR_PATTERN = /^(\d{1,3}(?:\.\d{1,3}){3})\/(\d{1,2})$/;
const PORT_RANGE_PATTERN = /^\s*(\d+)\s*-\s*(\d+)\s*$/;

const VALID_PORTS: PortRange = { min: 1024, max: 65535 };
const FALLBACK_PORTS: PortRange = { min: 10000, max: 20000 };

interface PortRange { min: number; max: number; }
interface AddressRange { first: number; count: number; }
interface LocalizedMessage { en: string; ptBR: string; }

interface ExperimentStore {
    getServerAssignment(type: string, id: string, experiment: string): { variantId: string; };
    createOverride(experiment: string, variant: string): void;
    // ...
}

const ExperimentStore: ExperimentStore = findStoreLazy("ApexExperimentStore");

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Config error reporting (each distinct bad value is toasted only once)
// ---------------------------------------------------------------------------

const lastReportedValue = new Map<string, string>();

function reportConfigError(setting: string, value: string, message: LocalizedMessage): void {
    if (lastReportedValue.get(setting) === value) return;
    lastReportedValue.set(setting, value);

    const isPortuguese = LocaleStore.locale.toLowerCase().startsWith("pt");
    showToast({ text: isPortuguese ? message.ptBR : message.en, variant: "critical" });
}

function clearConfigError(setting: string): void {
    lastReportedValue.delete(setting);
}

// ---------------------------------------------------------------------------
// Experiment gate
// ---------------------------------------------------------------------------

/**
 * Sets the Video Guard experiment to the disabled variant for the current user,
 * if it isn't already. This client-side gate can prevent the screenshare UI from starting.
 */
function disableVideoGuardExperiment(): void {
    const user = UserStore.getCurrentUser();
    if (!user) return;

    const { variantId } = ExperimentStore.getServerAssignment("user", user.id, VIDEO_GUARD_EXPERIMENT);
    if (variantId !== DISABLED_VARIANT) {
        ExperimentStore.createOverride(VIDEO_GUARD_EXPERIMENT, DISABLED_VARIANT);
    }
}

// ---------------------------------------------------------------------------
// IPv4 helpers
// ---------------------------------------------------------------------------

function randomInt(min: number, max: number): number {
    return min + Math.floor(Math.random() * (max - min + 1));
}

function ipv4ToNumber(octets: number[]): number {
    return octets.reduce((value, octet) => value * 256 + octet, 0);
}

function numberToIpv4(address: number): string {
    return [24, 16, 8, 0]
        .map(shift => Math.floor(address / 2 ** shift) % 256)
        .join(".");
}

/**
 * Parses a CIDR block into the range of usable host addresses.
 * Network and broadcast addresses are excluded, except for /31 and /32 blocks.
 */
function parseCidr(cidr: string): AddressRange | null {
    const match = cidr.match(CIDR_PATTERN);
    if (!match) return null;

    const octets = match[1].split(".").map(Number);
    const prefix = Number(match[2]);
    if (octets.some(octet => octet > 255) || prefix > 32) return null;

    const blockSize = 2 ** (32 - prefix);
    const network = Math.floor(ipv4ToNumber(octets) / blockSize) * blockSize;
    const hasReservedAddresses = prefix <= 30;

    return hasReservedAddresses
        ? { first: network + 1, count: blockSize - 2 }
        : { first: network, count: blockSize };
}

/**
 * Picks a uniformly random IPv4 address across all the given subnets.
 * @param subnets IPv4 subnets in CIDR notation, separated by whitespace.
 * @returns The address, or undefined if no valid subnet was provided.
 */
function randomIpFromSubnets(subnets: string): string | undefined {
    const ranges = subnets
        .split(/\s+/)
        .map(parseCidr)
        .filter((range): range is AddressRange => range !== null);

    const totalAddresses = ranges.reduce((sum, range) => sum + range.count, 0);
    if (!totalAddresses) return undefined;

    let offset = Math.floor(Math.random() * totalAddresses);
    for (const range of ranges) {
        if (offset < range.count) return numberToIpv4(range.first + offset);
        offset -= range.count;
    }
}

// ---------------------------------------------------------------------------
// Port helpers
// ---------------------------------------------------------------------------

function isValidPort(port: number): boolean {
    return port >= VALID_PORTS.min && port <= VALID_PORTS.max;
}

/** Parses "min-max" into an ordered range, or null if malformed or out of bounds. */
function parsePortRange(input: string): PortRange | null {
    const match = input.match(PORT_RANGE_PATTERN);
    if (!match) return null;

    const first = Number(match[1]);
    const second = Number(match[2]);
    if (!isValidPort(first) || !isValidPort(second)) return null;

    return { min: Math.min(first, second), max: Math.max(first, second) };
}

/** Returns the configured port range, falling back to the default (with a toast) if invalid. */
function resolvePortRange(input: string): PortRange {
    const range = parsePortRange(input);

    if (range) {
        clearConfigError("portRange");
        return range;
    }

    reportConfigError("portRange", input, {
        en: "Invalid port range. Use min-max with both ports from 1024 to 65535; using 10000-20000.",
        ptBR: "Intervalo de portas inválido. Use mínimo-máximo com ambas entre 1024 e 65535; usando 10000-20000."
    });
    return FALLBACK_PORTS;
}

// ---------------------------------------------------------------------------
// Plugin
// ---------------------------------------------------------------------------

export default definePlugin({
    name: "VideoGuardBypasser",
    description: "Educational PoC: disables the Video Guard screenshare gate and replaces the IPv4 address and port reported to the voice websocket.",
    authors: [{ name: "Caio Stoduto", id: 0n }],
    enabledByDefault: true,
    settings,

    patches: [
        {
            find: "Connect called with already existing websocket",
            replacement: [
                {
                    match: /selectProtocol\((\i),(\i),(\i),(\i)\)\{/,
                    replace: "selectProtocol($1,$2,$3,$4){$3=$self.onSelectProtocol(this,$1,$3);"
                }
            ]
        }
    ],

    start() {
        disableVideoGuardExperiment();
        console.log(`[Video Guard bypasser] Started`);
    },

    /**
     * Rewrites the address/port the client reports to the voice websocket after connecting to the RTC/SFU.
     * The client-reported IPv4 is used by the websocket for application-layer location policy censoring.
     * @param _sock The socket
     * @param protocol The connection protocol
     * @param data The connection data
     * @returns The updated connection data
     */
    onSelectProtocol(_sock: unknown, protocol: string, data: object) {
        console.log(`[Video Guard bypasser] before patch`, protocol, data);
        if (protocol !== "udp") return data;

        const address = randomIpFromSubnets(settings.store.subnets);
        if (!address) {
            reportConfigError("subnets", settings.store.subnets, {
                en: "No valid IPv4 CIDR subnets configured. Check the Subnets setting.",
                ptBR: "Nenhuma sub-rede IPv4 CIDR válida configurada. Verifique a opção Subnets."
            });
            return data;
        }
        clearConfigError("subnets");

        const { min, max } = resolvePortRange(settings.store.portRange);
        const port = randomInt(min, max);

        console.log(`[Video Guard bypasser] after patch`, data);
        return { ...data, address, port };
    }
});
