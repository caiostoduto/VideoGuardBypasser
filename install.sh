#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  Vencord + VideoGuardBypasser installer (Linux / macOS)
#  Instalador do Vencord + VideoGuardBypasser (Linux / macOS)
#
#  Usage / Uso:
#    ./install.sh [--lang en|pt] [--vencord-dir PATH]
# ──────────────────────────────────────────────────────────────────────────────

VENCORD_REPO="https://github.com/Vendicated/Vencord.git"
PLUGIN_NAME="videoGuardBypasser"
PLUGIN_URL="https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts"
DOCS_URL="https://docs.vencord.dev/installing/#installing-your-custom-build"

# ── Language ──────────────────────────────────────────────────────────────────
LANG_CODE=""
VENCORD_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --lang) LANG_CODE="$2"; shift 2 ;;
        --lang=*) LANG_CODE="${1#*=}"; shift ;;
        --vencord-dir) VENCORD_DIR="$2"; shift 2 ;;
        --vencord-dir=*) VENCORD_DIR="${1#*=}"; shift ;;
        *) shift ;;
    esac
done
VENCORD_DIR="${VENCORD_DIR:-$HOME/Vencord}"
if [ -z "$LANG_CODE" ]; then
    case "${VG_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}" in
        pt*|PT*) LANG_CODE="pt" ;;
        *) LANG_CODE="en" ;;
    esac
fi
[ "$LANG_CODE" != "pt" ] && LANG_CODE="en"

# L "english" "português"  → prints the string for the active language
L() { if [ "$LANG_CODE" = "pt" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
fi

LOG="$(mktemp -t vencord-install.XXXXXX)"
cleanup() { printf '\033[?25h'; rm -f "$LOG"; }
trap cleanup EXIT
trap 'echo; printf "  %s✖%s %s\n" "$RED" "$RESET" "$(L "Cancelled." "Cancelado.")"; exit 130' INT TERM

# ── Output helpers ────────────────────────────────────────────────────────────
info()    { printf "  %s●%s %s\n" "$BLUE" "$RESET" "$(L "$1" "$2")"; }
ok()      { printf "  %s✔%s %s\n" "$GREEN" "$RESET" "$(L "$1" "$2")"; }
warn()    { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$(L "$1" "$2")"; }
fail()    { printf "  %s✖%s %s\n" "$RED" "$RESET" "$(L "$1" "$2")" >&2; }
die()     { fail "$1" "$2"; exit 1; }
section() { # en pt [dim suffix]
    printf "\n%s%s▸ %s%s" "$BOLD" "$MAGENTA" "$(L "$1" "$2")" "$RESET"
    [ -n "$3" ] && printf "  %s%s%s" "$DIM" "$3" "$RESET"
    echo
}

banner() {
    printf "\n%s%s" "$BOLD" "$CYAN"
    echo "  ╭──────────────────────────────────────────────╮"
    echo "  │                                              │"
    echo "  │      Vencord  ×  VideoGuardBypasser          │"
    local title title_bytes title_chars title_width
    title="$(L "Automatic installer" "Instalador automático")"
    title_bytes="$(printf '%s' "$title" | wc -c | tr -d ' ')"
    title_chars="$(printf '%s' "$title" | wc -m | tr -d ' ')"
    title_width=$((39 + title_bytes - title_chars))
    printf "  │      %-*s │\n" "$title_width" "$title"
    echo "  │                                              │"
    echo "  ╰──────────────────────────────────────────────╯"
    printf "%s\n" "$RESET"
}

# read_key → reads a single keypress from the terminal (no Enter needed)
# Sets KEY to the character ("" for Enter). Returns 1 if no terminal is available.
read_key() {
    KEY=""
    IFS= read -r -s -n 1 KEY </dev/tty 2>/dev/null || return 1
    return 0
}

# Replaces the prompt line with the next output (tty) or echoes the answer (non-tty)
_answered() { # yes|no
    if [ -t 2 ]; then printf '\r\033[K' >&2
    elif [ "$1" = "yes" ]; then echo "$(L yes sim)" >&2
    else echo "$(L no não)" >&2; fi
}

# ask_yn "en" "pt" [Y|N]  → returns 0 for yes, 1 for no (single keypress; Enter = default)
ask_yn() {
    local def="${3:-Y}" hint
    if [ "$def" = "Y" ]; then hint="$(L 'Y/n' 'S/n')"; else hint="$(L 'y/N' 's/N')"; fi
    printf "  %s?%s %s %s[%s]%s " "$YELLOW" "$RESET" "$(L "$1" "$2")" "$DIM" "$hint" "$RESET" >&2
    while true; do
        if ! read_key; then echo >&2; [ "$def" = "Y" ]; return; fi
        case "$KEY" in
            "")      if [ "$def" = "Y" ]; then _answered yes; return 0; else _answered no; return 1; fi ;;
            [YySs])  _answered yes; return 0 ;;
            [Nn])    _answered no; return 1 ;;
        esac
    done
}

# spin_run "en" "pt" command args...  → runs hidden, with spinner
#   SPIN_CLEAR=1           erase the line on success (caller prints its own result)
#   SPIN_DONE_EN/PT="..."  message shown on the ✔ line instead of the progress text
spin_run() {
    local msg done frames i=0 pid rc
    msg="$(L "$1" "$2")"; shift 2
    done="$msg"; [ -n "$SPIN_DONE_EN" ] && done="$(L "$SPIN_DONE_EN" "$SPIN_DONE_PT")"
    frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    : > "$LOG"
    "$@" >>"$LOG" 2>&1 </dev/null &
    pid=$!
    if [ -t 1 ]; then
        printf '\033[?25l'
        while kill -0 "$pid" 2>/dev/null; do
            printf "\r  %s%s%s %s" "$CYAN" "${frames[i % 10]}" "$RESET" "$msg"
            i=$((i + 1))
            sleep 0.1
        done
        printf '\033[?25h'
    fi
    wait "$pid"; rc=$?
    if [ $rc -eq 0 ]; then
        if [ -n "$SPIN_CLEAR" ]; then
            if [ -t 1 ]; then printf "\r\033[K"; fi
        else
            printf "\r\033[K  %s✔%s %s\n" "$GREEN" "$RESET" "$done"
        fi
    else
        printf "\r\033[K  %s✖%s %s\n" "$RED" "$RESET" "$msg"
        printf "\n%s" "$DIM"; tail -n 25 "$LOG"; printf "%s\n" "$RESET"
    fi
    return $rc
}

# ── Prerequisites ────────────────────────────────────────────────────────────
tool_version() {
    case "$1" in
        git)  git --version 2>/dev/null | awk '{print $3}' ;;
        curl) curl --version 2>/dev/null | awk 'NR==1{print $2}' ;;
        wget) wget --version 2>/dev/null | awk 'NR==1{print $3}' ;;
    esac
}

# ── Downloader: curl or wget (whichever is available) ─────────────────────────
fetch_stdout() { # <url>
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"; else wget -qO- "$1"; fi
}
fetch_to() { # <url> <file>
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"; else wget -qO "$2" "$1"; fi
}

# ensure_cmd <command>  → appends "name version" to TOOLS_LINE (printed once)
TOOLS_LINE=""
ensure_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 \
        || die "$cmd is required but not installed. Install it and run this script again." \
               "$cmd é necessário, mas não está instalado. Instale-o e execute este script novamente."
    TOOLS_LINE+="${TOOLS_LINE:+ ${DIM}·${RESET} }$cmd $(tool_version "$cmd")"
}

# ensure_downloader  → accepts curl OR wget; errors if neither exists
ensure_downloader() {
    local d
    for d in curl wget; do
        if command -v "$d" >/dev/null 2>&1; then
            TOOLS_LINE+="${TOOLS_LINE:+ ${DIM}·${RESET} }$d $(tool_version "$d")"
            return 0
        fi
    done
    die "Neither curl nor wget is installed. Install one and run this script again." \
        "curl e wget não estão instalados. Instale um deles e execute este script novamente."
}

# ── Node / pnpm ───────────────────────────────────────────────────────────────
INSTALLER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/vencord-installer"
PNPM_HOME="$INSTALLER_DIR/pnpm"

node_version() { node -v 2>/dev/null | sed 's/^v//'; }

use_local_node() {
    local platform node_home version best_home="" best_version=""
    platform="$(node_platform 2>/dev/null)" || return 0
    for node_home in "$INSTALLER_DIR"/node-v*-"$platform"; do
        [ -x "$node_home/bin/node" ] || continue
        version="$("$node_home/bin/node" -v 2>/dev/null | sed 's/^v//')"
        if [ -n "$version" ] && [ "$(ver_cmp "$version" "$REQ_NODE")" -ge 0 ] && \
           { [ -z "$best_version" ] || [ "$(ver_cmp "$version" "$best_version")" -gt 0 ]; }; then
            best_home="$node_home"
            best_version="$version"
        fi
    done
    if [ -n "$best_home" ]; then
        NODE_HOME="$best_home"
        export PATH="$best_home/bin:$PATH"
        hash -r
    fi
}

use_local_pnpm() {
    local local_ver
    [ -x "$PNPM_HOME/node_modules/.bin/pnpm" ] || return 0
    local_ver="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && "$PNPM_HOME/node_modules/.bin/pnpm" -v 2>/dev/null | tail -n 1)"
    if [ -n "$local_ver" ] && { [ -z "$REQ_PNPM" ] || [ "$(ver_cmp "$local_ver" "$REQ_PNPM")" -ge 0 ]; }; then
        export PATH="$PNPM_HOME/node_modules/.bin:$PATH"
        hash -r
    fi
}

cancelled() {
    printf "  %s!%s %s\n" "$RED" "$RESET" "$(L "$1" "$2")"
}

# pnpm version, read OUTSIDE the project so pnpm doesn't warn about packageManager mismatches
pnpm_version() {
    command -v pnpm >/dev/null 2>&1 || return 0
    ( cd "${TMPDIR:-/tmp}" 2>/dev/null && pnpm -v 2>/dev/null | tail -n 1 )
}

# ver_cmp A B → prints -1 (A<B), 0 (A=B) or 1 (A>B); ignores pre-release suffixes
ver_cmp() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        sub(/[-+].*/, "", a); sub(/[-+].*/, "", b)
        split(a, av, /[.]/); split(b, bv, /[.]/)
        for (i = 1; i <= 3; i++) {
            x = av[i] + 0; y = bv[i] + 0
            if (x < y) { print -1; exit }
            if (x > y) { print 1; exit }
        }
        print 0
    }'
}

node_platform() {
    local os arch
    case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) return 1 ;; esac
    case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        armv7l) [ "$os" = linux ] || return 1; arch=armv7l ;;
        *) return 1 ;;
    esac
    printf '%s-%s' "$os" "$arch"
}

latest_lts_node() { # <minimum version>
    local versions version
    versions="$(fetch_stdout https://nodejs.org/dist/index.json \
        | sed -nE '/"lts":"[^"]+"/s/.*"version":"v([^"]+)".*/\1/p')"
    while IFS= read -r version; do
        [ -n "$version" ] || continue
        if [ "$(ver_cmp "$version" "$1")" -ge 0 ]; then
            printf '%s' "$version"
            return 0
        fi
    done <<< "$versions"
    return 1
}

install_node() {
    local platform archive extracted
    NODE_VERSION="$(latest_lts_node "$REQ_NODE")" \
        || die "No Node.js LTS release meets the required version $REQ_NODE." \
               "Nenhuma versão LTS do Node.js atende à versão necessária $REQ_NODE."
    if ! ask_yn "Download Node.js LTS $NODE_VERSION (~100 MB installed)?" \
                "Baixar Node.js $NODE_VERSION (~100 MB instalado)?" Y; then
        cancelled "Node.js download cancelled." "Download do Node.js cancelado."
        return 1
    fi
    platform="$(node_platform)" || die "Unsupported platform for the Node.js LTS build." "Plataforma não compatível com a versão LTS do Node.js."
    archive="$INSTALLER_DIR/node-v$NODE_VERSION-$platform.tar.xz"
    extracted="$INSTALLER_DIR/node-v$NODE_VERSION-$platform"
    mkdir -p "$INSTALLER_DIR" || return 1
    SPIN_CLEAR=1 \
    spin_run "Downloading Node.js LTS $NODE_VERSION..." "Baixando Node.js LTS $NODE_VERSION..." \
        fetch_to "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$platform.tar.xz" "$archive" || return 1
    SPIN_CLEAR=1 \
    spin_run "Extracting Node.js..." "Extraindo Node.js..." tar -xJf "$archive" -C "$INSTALLER_DIR" || return 1
    rm -f "$archive"
    NODE_HOME="$extracted"
    export PATH="$NODE_HOME/bin:$PATH"
    hash -r
    CHOSEN="local download"
}

install_pnpm() {
    local ver="$1" spec="pnpm@$1"
    if ! ask_yn "Download $spec with npm (about 10 MB installed)?" \
                "Baixar $spec com npm (cerca de 10 MB instalado)?" Y; then
        cancelled "pnpm download cancelled." "Download do pnpm cancelado."
        return 1
    fi
    mkdir -p "$INSTALLER_DIR" || return 1
    SPIN_CLEAR=1 spin_run "Installing $spec locally..." "Instalando $spec localmente..." \
        npm install --prefix "$PNPM_HOME" "$spec" || return 1
    export PATH="$PNPM_HOME/node_modules/.bin:$PATH"
    hash -r
    CHOSEN="local npm install"
}

# report_pnpm [install description]  → version and newer-than-required warning
report_pnpm() {
    local v en="" pt="" newer=0 ne="" np=""
    v="$(pnpm_version)"
    if [ -n "$1" ]; then
        en="installed via $1"; pt="instalado via $1"
    fi
    if [ -n "$REQ_PNPM" ] && [ "$(ver_cmp "$v" "$REQ_PNPM")" -gt 0 ]; then
        newer=1
        en="${en:+$en, }newer than $REQ_PNPM"; pt="${pt:+$pt, }mais recente que $REQ_PNPM"
    fi
    if [ -n "$en" ]; then ne=" ${DIM}($en)${RESET}"; np=" ${DIM}($pt)${RESET}"; fi
    if [ "$newer" -eq 1 ]; then warn "pnpm $v$ne" "pnpm $v$np"; else ok "pnpm $v$ne" "pnpm $v$np"; fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════════════════
clear 2>/dev/null || true
banner

# 1 ── Git & curl/wget ──────────────────────────────────────────────────────────────
section "Checking requirements" "Verificando requisitos"
ensure_cmd git
ensure_downloader
ok "$TOOLS_LINE" "$TOOLS_LINE"

# 2 ── Vencord repository ──────────────────────────────────────────────────────
case "$VENCORD_DIR" in "$HOME"/*) VENCORD_SHOW="~${VENCORD_DIR#"$HOME"}" ;; *) VENCORD_SHOW="$VENCORD_DIR" ;; esac
section "Vencord repository" "Repositório do Vencord"
if [ -d "$VENCORD_DIR/.git" ]; then
    if ask_yn "Vencord found at $VENCORD_SHOW. Update it?" "Vencord encontrado em $VENCORD_SHOW. Atualizar?" Y; then
        SPIN_DONE_EN="Vencord updated ($VENCORD_SHOW)" SPIN_DONE_PT="Vencord atualizado ($VENCORD_SHOW)" \
        spin_run "Updating Vencord..." "Atualizando o Vencord..." \
            git -C "$VENCORD_DIR" pull --ff-only \
            || die "Update failed. Resolve the issue above and try again." \
                   "Falha ao atualizar. Resolva o problema acima e tente novamente."
    else
        ok "Vencord at $VENCORD_SHOW ${DIM}(not updated)${RESET}" "Vencord em $VENCORD_SHOW ${DIM}(não atualizado)${RESET}"
    fi
elif [ -e "$VENCORD_DIR" ]; then
    die "$VENCORD_SHOW exists but is not a git repository." \
        "$VENCORD_SHOW existe, mas não é um repositório git."
else
    SPIN_DONE_EN="Vencord cloned to $VENCORD_SHOW" SPIN_DONE_PT="Vencord clonado em $VENCORD_SHOW" \
    spin_run "Cloning Vencord..." "Clonando o Vencord..." \
        git clone "$VENCORD_REPO" "$VENCORD_DIR" \
        || die "Clone failed." "Falha ao clonar."
fi
cd "$VENCORD_DIR" || die "Cannot enter $VENCORD_SHOW" "Não foi possível entrar em $VENCORD_SHOW"

# 3 ── Node & pnpm (versions from package.json) ────────────────────────────────
[ -f package.json ] || die "package.json not found." "package.json não encontrado."

REQ_NODE="$(sed -n '/"engines"/,/}/p' package.json | grep '"node"' | head -1 \
            | sed -E 's/.*"node"[^"]*"[^0-9]*([0-9]+).*/\1/')"
REQ_PNPM="$(grep '"packageManager"' package.json | head -1 \
            | sed -nE 's/.*"pnpm@([^"+]+).*/\1/p')"
REQ_NODE="${REQ_NODE:-22.0.0}"

section "Node.js & pnpm" "Node.js e pnpm" "Node ≥ $REQ_NODE · pnpm ${REQ_PNPM:-latest}"

# Node
use_local_node
CUR_NODE="$(node_version)"
if [ -n "$CUR_NODE" ] && [ "$(ver_cmp "$CUR_NODE" "$REQ_NODE")" -ge 0 ]; then
    ok "Node.js $(node -v)" "Node.js $(node -v)"
else
    if [ -n "$CUR_NODE" ]; then
        R_EN="Node.js $(node -v) is too old"; R_PT="Node.js $(node -v) é muito antigo"
    else
        R_EN="Node.js is not installed"; R_PT="Node.js não está instalado"
    fi
    install_node || exit 1
    CUR_NODE="$(node_version)"
    { [ -n "$CUR_NODE" ] && [ "$(ver_cmp "$CUR_NODE" "$REQ_NODE")" -ge 0 ]; } \
        || die "Node.js $REQ_NODE+ still not available. Open a new terminal and retry." \
               "Node.js $REQ_NODE+ ainda indisponível. Abra um novo terminal e tente novamente."
    ok "Node.js $(node -v) ${DIM}($(L "installed via" "instalado via") $CHOSEN)${RESET}" \
       "Node.js $(node -v) ${DIM}($(L "installed via" "instalado via") $CHOSEN)${RESET}"
fi

# pnpm (a newer version is fine; an older one or none triggers the installer prompt)
use_local_pnpm
PNPM_VER="$(pnpm_version)"
if [ -n "$PNPM_VER" ] && { [ -z "$REQ_PNPM" ] || [ "$(ver_cmp "$PNPM_VER" "$REQ_PNPM")" -ge 0 ]; }; then
    report_pnpm
else
    install_pnpm "$REQ_PNPM" || exit 1
    hash -r
    [ -n "$(pnpm_version)" ] \
        || die "pnpm not found after install. Open a new terminal and retry." \
               "pnpm não encontrado após a instalação. Abra um novo terminal e tente novamente."
    report_pnpm "$CHOSEN"
fi

# 4 ── Dependencies + plugin ───────────────────────────────────────────────────
section "Setting up" "Configurando"

SPIN_DONE_EN="Dependencies installed" SPIN_DONE_PT="Dependências instaladas" \
spin_run "Installing dependencies..." "Instalando dependências..." \
    pnpm install --frozen-lockfile \
    || die "Dependency installation failed." "Falha ao instalar as dependências."

download_plugin() {
    mkdir -p "src/userplugins/$PLUGIN_NAME" \
        && fetch_to "$PLUGIN_URL" "src/userplugins/$PLUGIN_NAME/index.ts"
}
SPIN_DONE_EN="VideoGuardBypasser plugin installed" SPIN_DONE_PT="Plugin VideoGuardBypasser instalado" \
spin_run "Downloading VideoGuardBypasser plugin..." "Baixando o plugin VideoGuardBypasser..." \
    download_plugin \
    || die "Plugin download failed." "Falha ao baixar o plugin."

# 5 ── Target ──────────────────────────────────────────────────────────────────
section "Build target" "Destino da build"
printf "    %s1)%s %s\n" "$CYAN" "$RESET" "$(L "Discord app" "App do Discord")"
printf "    %s2)%s %s\n" "$CYAN" "$RESET" "Vesktop"
printf "    %s3)%s %s\n" "$CYAN" "$RESET" "$(L "Web (browser)" "Web (navegador)")"
echo
printf "  %s?%s %s " "$YELLOW" "$RESET" "$(L "Choose [1/2/3]:" "Escolha [1/2/3]:")"
while true; do
    read_key || die "No terminal available for input." "Nenhum terminal disponível para entrada."
    case "$KEY" in 1|2|3) CHOICE="$KEY"; echo "$CHOICE"; break ;; esac
done
echo

show_docs_link() {
    echo
    info "To install your custom build, follow this guide:" \
         "Para instalar sua build personalizada, siga este guia:"
    printf "\n    %s%s%s\n" "$BOLD$BLUE" "$DOCS_URL" "$RESET"
    printf "    %s%s%s\n" "$DIM" "$(L "Built files: $VENCORD_DIR/dist" "Arquivos gerados: $VENCORD_DIR/dist")" "$RESET"
}

case "$CHOICE" in
    1)  # Discord app
        SPIN_DONE_EN="Vencord built" SPIN_DONE_PT="Vencord compilado" \
        spin_run "Building Vencord..." "Compilando o Vencord..." pnpm build \
            || die "Build failed." "Falha na build."

        info "Running the injector — follow the prompts below." \
             "Executando o injetor — siga as instruções abaixo."
        echo
        pnpm inject </dev/tty \
            || die "Injection failed." "Falha na injeção."
        echo
        FINAL_EN="Restart Discord to load the modification."
        FINAL_PT="Reinicie o Discord para carregar a modificação."
        ;;
    2)  # Vesktop
        SPIN_DONE_EN="Vencord built" SPIN_DONE_PT="Vencord compilado" \
        spin_run "Building Vencord..." "Compilando o Vencord..." pnpm build \
            || die "Build failed." "Falha na build."
        show_docs_link
        FINAL_EN="Follow the guide above to use your custom build in Vesktop."
        FINAL_PT="Siga o guia acima para usar sua build personalizada no Vesktop."
        ;;
    3)  # Web
        SPIN_DONE_EN="Vencord (web) built" SPIN_DONE_PT="Vencord (web) compilado" \
        spin_run "Building Vencord for Web..." "Compilando o Vencord para Web..." pnpm buildWeb \
            || die "Build failed." "Falha na build."
        show_docs_link
        FINAL_EN="Follow the guide above to load the extension in your browser."
        FINAL_PT="Siga o guia acima para carregar a extensão no seu navegador."
        ;;
esac

# 6 ── Done ────────────────────────────────────────────────────────────────────
printf "\n%s%s" "$BOLD" "$GREEN"
echo "  ╭──────────────────────────────────────────────╮"
DONE_MSG="$(L "All done! Installation complete." "Tudo pronto! Instalação concluída.")"
DONE_BYTES="$(printf '%s' "$DONE_MSG" | wc -c | tr -d ' ')"
DONE_CHARS="$(printf '%s' "$DONE_MSG" | wc -m | tr -d ' ')"
DONE_WIDTH=$((42 + DONE_BYTES - DONE_CHARS))
printf "  │  ✔ %-*s│\n" "$DONE_WIDTH" "$DONE_MSG"
echo "  ╰──────────────────────────────────────────────╯"
printf "%s\n" "$RESET"
info "$FINAL_EN" "$FINAL_PT"
if [ "$CHOICE" = "2" ] || [ "$CHOICE" = "3" ]; then
    info "If installing on Vesktop or Web, please take a look at:" \
         "Se estiver instalando no Vesktop ou na Web, consulte:"
    printf "    %s%s%s\n" "$BOLD$BLUE" "https://github.com/caiostoduto/VideoGuardBypasser/issues/1" "$RESET"
fi
echo
