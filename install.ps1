# ──────────────────────────────────────────────────────────────────────────────
#  Vencord + VideoGuardBypasser installer (Windows PowerShell / PowerShell 7)
#  Instalador do Vencord + VideoGuardBypasser (Windows PowerShell / PowerShell 7)
#
#  Usage / Uso:
#    .\install.ps1 [-Language en|pt] [-VencordDir PATH]
# ──────────────────────────────────────────────────────────────────────────────
param(
    [string]$Language = '',
    [string]$VencordDir = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$VencordRepo = 'https://github.com/Vendicated/Vencord.git'
$PluginName  = 'videoGuardBypasser'
$PluginUrl   = 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/plugin/index.ts'
$DocsUrl     = 'https://docs.vencord.dev/installing/#installing-your-custom-build'

if (-not $VencordDir) { $VencordDir = Join-Path $HOME 'Vencord' }
$VencordDir = [IO.Path]::GetFullPath($VencordDir)

# ── Language ──────────────────────────────────────────────────────────────────
if (-not $Language) {
    $Language = @($env:VG_LANG, $env:LC_ALL, $env:LC_MESSAGES, $env:LANG,
                  [Globalization.CultureInfo]::CurrentUICulture.Name) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1
}
if ($Language -like 'pt*') { $Language = 'pt' } else { $Language = 'en' }

function T([string]$En, [string]$Pt) { if ($Language -eq 'pt') { $Pt } else { $En } }

# Mutable state lives in one hashtable so nothing leaks into the caller's session
$S = @{
    Interactive = $false
    PnpmCmd     = $null
    ReqNode     = '22.0.0'
    ReqPnpm     = ''
    Finished    = $false
}
try { $S.Interactive = (-not [Console]::IsOutputRedirected) -and ([Console]::WindowWidth -gt 0) } catch {}

$InstallerDir = Join-Path $env:LOCALAPPDATA 'vencord-installer'
$PnpmHome     = Join-Path $InstallerDir 'pnpm'
$LocalPnpmCmd = Join-Path $PnpmHome 'node_modules\.bin\pnpm.cmd'

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Line([string]$Symbol, [ConsoleColor]$Color, [string]$Text, [string]$Note = '') {
    Write-Host -NoNewline '  '
    Write-Host -NoNewline $Symbol -ForegroundColor $Color
    Write-Host -NoNewline " $Text"
    if ($Note) { Write-Host -NoNewline " ($Note)" -ForegroundColor DarkGray }
    Write-Host ''
}
function Write-Info([string]$Text) { Write-Line '●' Blue $Text }
function Write-Ok([string]$Text, [string]$Note = '') { Write-Line '✔' Green $Text $Note }
function Write-Warn([string]$Text, [string]$Note = '') { Write-Line '!' Yellow $Text $Note }
function Write-Fail([string]$Text) { Write-Line '✖' Red $Text }
function Write-Cancelled([string]$Text) { Write-Line '!' Red $Text }

function Stop-Install([string]$Text) {
    Write-Fail $Text
    $S.Finished = $true
    $global:LASTEXITCODE = 1
    throw 'VG_ABORT'
}
function Stop-Cancelled([string]$Text) {
    Write-Cancelled $Text
    $S.Finished = $true
    $global:LASTEXITCODE = 1
    throw 'VG_ABORT'
}

function Write-Section([string]$Text, [string]$Suffix = '') {
    Write-Host ''
    Write-Host -NoNewline "▸ $Text" -ForegroundColor Magenta
    if ($Suffix) { Write-Host -NoNewline "  $Suffix" -ForegroundColor DarkGray }
    Write-Host ''
}

function Clear-Line {
    if (-not $S.Interactive) { return }
    try {
        $w = [Console]::WindowWidth
        Write-Host -NoNewline ("`r" + (' ' * [Math]::Max(1, $w - 1)) + "`r")
    } catch { Write-Host -NoNewline "`r" }
}

function Show-Banner {
    $title = T 'Automatic installer' 'Instalador automático'
    Write-Host ''
    Write-Host '  ╭──────────────────────────────────────────────╮' -ForegroundColor Cyan
    Write-Host '  │                                              │' -ForegroundColor Cyan
    Write-Host '  │      Vencord  ×  VideoGuardBypasser          │' -ForegroundColor Cyan
    Write-Host ("  │      " + $title.PadRight(39) + " │") -ForegroundColor Cyan
    Write-Host '  │                                              │' -ForegroundColor Cyan
    Write-Host '  ╰──────────────────────────────────────────────╯' -ForegroundColor Cyan
    Write-Host ''
}

# ── Input helpers ─────────────────────────────────────────────────────────────
# Returns the pressed character, '' for Enter, or $null if no terminal is available
function Read-Key {
    try {
        while ($true) {
            $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($k.VirtualKeyCode -eq 13) { return '' }
            if ($k.Character -ne [char]0) { return [string]$k.Character }
        }
    } catch { return $null }
}

function Ask-YesNo([string]$En, [string]$Pt, [bool]$DefaultYes = $true) {
    if ($DefaultYes) { $hint = T 'Y/n' 'S/n' } else { $hint = T 'y/N' 's/N' }
    Write-Host -NoNewline '  '
    Write-Host -NoNewline '?' -ForegroundColor Yellow
    Write-Host -NoNewline " $(T $En $Pt) "
    Write-Host -NoNewline "[$hint]" -ForegroundColor DarkGray
    Write-Host -NoNewline ' '
    while ($true) {
        $k = Read-Key
        if ($null -eq $k) { Write-Host ''; return $DefaultYes }
        if ($k -eq '') { $ans = $DefaultYes }
        elseif ($k -match '^[YySs]$') { $ans = $true }
        elseif ($k -match '^[Nn]$') { $ans = $false }
        else { continue }
        if ($S.Interactive) { Clear-Line }
        elseif ($ans) { Write-Host (T 'yes' 'sim') }
        else { Write-Host (T 'no' 'não') }
        return $ans
    }
}

# ── Process helpers ───────────────────────────────────────────────────────────
function ConvertTo-ArgString([string[]]$Items) {
    ($Items | ForEach-Object {
        if ($_ -eq '' -or $_ -match '[\s"]') {
            '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        } else { $_ }
    }) -join ' '
}

function Find-App([string]$Name) {
    $c = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

# Runs a command hidden with a spinner on a single line (like spin_run in the bash script).
# Returns $true on success, $false on failure (after printing the tail of the log).
function Invoke-Spin {
    param(
        [string]$En, [string]$Pt,
        [string]$File, [string[]]$ArgList = @(),
        [string]$DoneEn = '', [string]$DonePt = '',
        [switch]$Clear,
        [string]$WorkDir = (Get-Location).ProviderPath
    )
    $msg  = T $En $Pt
    $done = if ($DoneEn) { T $DoneEn $DonePt } else { $msg }
    $frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($File -match '\.(cmd|bat)$') {
        $psi.FileName  = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
        $psi.Arguments = '/d /s /c "' + (ConvertTo-ArgString (@($File) + $ArgList)) + '"'
    } else {
        $psi.FileName  = $File
        $psi.Arguments = ConvertTo-ArgString $ArgList
    }
    $psi.WorkingDirectory       = $WorkDir
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $p = $null
    $log = ''
    $rc = 1
    try {
        if ($S.Interactive) { try { [Console]::CursorVisible = $false } catch {} }
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
        } catch {
            $log = $_.Exception.Message
            $p = $null
        }
        if ($p) {
            $p.StandardInput.Close()
            $outTask = $p.StandardOutput.ReadToEndAsync()
            $errTask = $p.StandardError.ReadToEndAsync()
            $i = 0
            while (-not $p.HasExited) {
                if ($S.Interactive) {
                    Write-Host -NoNewline "`r  "
                    Write-Host -NoNewline $frames[$i % $frames.Count] -ForegroundColor Cyan
                    Write-Host -NoNewline " $msg"
                }
                $i++
                Start-Sleep -Milliseconds 100
            }
            $p.WaitForExit()
            $rc  = $p.ExitCode
            $log = $outTask.Result + $errTask.Result
        }
    } finally {
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
        if ($S.Interactive) { try { [Console]::CursorVisible = $true } catch {} }
    }

    if ($rc -eq 0) {
        Clear-Line
        if (-not $Clear) { Write-Ok $done }
        return $true
    }
    Clear-Line
    Write-Fail $msg
    Write-Host ''
    ($log -split "`r?`n" | Where-Object { $_ -ne '' } | Select-Object -Last 25) |
        ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Write-Host ''
    return $false
}

# ── Versions ──────────────────────────────────────────────────────────────────
# -1 (A<B), 0 (A=B), 1 (A>B); ignores pre-release suffixes
function Compare-Version([string]$A, [string]$B) {
    $l = @((($A -split '[-+]')[0]).Split('.'))
    $r = @((($B -split '[-+]')[0]).Split('.'))
    for ($i = 0; $i -lt 3; $i++) {
        $x = 0; $y = 0
        if ($i -lt $l.Count) { [void][int]::TryParse($l[$i], [ref]$x) }
        if ($i -lt $r.Count) { [void][int]::TryParse($r[$i], [ref]$y) }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

function Add-ToPath([string]$Dir) { $env:PATH = "$Dir;$env:PATH" }

# ── Node ──────────────────────────────────────────────────────────────────────
function Get-NodePlatform {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { return 'win-x64' }
        'ARM64' { return 'win-arm64' }
        default { return $null }
    }
}

function Get-NodeVersion {
    $node = Find-App 'node'
    if (-not $node) { return '' }
    $ErrorActionPreference = 'Continue'
    $v = (& $node -v 2>$null | Select-Object -First 1)
    return ([string]$v).Trim() -replace '^v', ''
}

function Use-LocalNode {
    $platform = Get-NodePlatform
    if (-not $platform -or -not (Test-Path $InstallerDir)) { return }
    $bestHome = $null; $bestVersion = $null
    foreach ($dir in (Get-ChildItem -LiteralPath $InstallerDir -Directory -Filter "node-v*-$platform" -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path (Join-Path $dir.FullName 'node.exe'))) { continue }
        $m = [regex]::Match($dir.Name, '^node-v(.+)-' + [regex]::Escape($platform) + '$')
        if (-not $m.Success) { continue }
        $v = $m.Groups[1].Value
        if ((Compare-Version $v $S.ReqNode) -ge 0 -and
            (-not $bestVersion -or (Compare-Version $v $bestVersion) -gt 0)) {
            $bestHome = $dir.FullName; $bestVersion = $v
        }
    }
    if ($bestHome) { Add-ToPath $bestHome }
}

function Get-LatestLtsNode([string]$Minimum) {
    try {
        $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
        foreach ($r in $releases) {
            if (-not $r.lts) { continue }
            $v = ([string]$r.version).TrimStart('v')
            if ((Compare-Version $v $Minimum) -ge 0) { return $v }
        }
    } catch {}
    return $null
}

function Invoke-Fetch([string]$Url, [string]$OutFile, [string]$En, [string]$Pt, [string]$DoneEn = '', [string]$DonePt = '', [switch]$Clear) {
    if ($S.Curl) { $exe = $S.Curl; $a = @('-fsSL', $Url, '-o', $OutFile) }
    else         { $exe = $S.Wget; $a = @('-qO', $OutFile, $Url) }
    $params = @{ En = $En; Pt = $Pt; File = $exe; ArgList = $a; DoneEn = $DoneEn; DonePt = $DonePt }
    if ($Clear) { $params.Clear = $true }
    return (Invoke-Spin @params)
}

function Install-Node {
    $ver = Get-LatestLtsNode $S.ReqNode
    if (-not $ver) {
        Stop-Install (T "No Node.js LTS release meets the required version $($S.ReqNode)." "Nenhuma versão LTS do Node.js atende à versão necessária $($S.ReqNode).")
    }
    if (-not (Ask-YesNo "Download Node.js LTS $ver (~100 MB installed)?" "Baixar Node.js $ver (~100 MB instalado)?" $true)) {
        Stop-Cancelled (T 'Node.js download cancelled.' 'Download do Node.js cancelado.')
    }
    $platform = Get-NodePlatform
    if (-not $platform) { Stop-Install (T 'Unsupported platform for the Node.js LTS build.' 'Plataforma não compatível com a versão LTS do Node.js.') }
    $archive   = Join-Path $InstallerDir "node-v$ver-$platform.zip"
    $extracted = Join-Path $InstallerDir "node-v$ver-$platform"
    New-Item -ItemType Directory -Force -Path $InstallerDir | Out-Null

    if (-not (Invoke-Fetch "https://nodejs.org/dist/v$ver/node-v$ver-$platform.zip" $archive `
            "Downloading Node.js LTS $ver..." "Baixando Node.js LTS $ver..." -Clear)) { Stop-Install (T 'Download failed.' 'Falha no download.') }

    $tar = Find-App 'tar.exe'
    if ($tar) {
        $ok = Invoke-Spin -En 'Extracting Node.js...' -Pt 'Extraindo Node.js...' -Clear `
            -File $tar -ArgList @('-xf', $archive, '-C', $InstallerDir)
    } else {
        $ps = Find-App 'powershell.exe'
        $cmd = "Expand-Archive -LiteralPath '$($archive -replace "'", "''")' -DestinationPath '$($InstallerDir -replace "'", "''")' -Force"
        $ok = Invoke-Spin -En 'Extracting Node.js...' -Pt 'Extraindo Node.js...' -Clear `
            -File $ps -ArgList @('-NoProfile', '-NonInteractive', '-Command', $cmd)
    }
    if (-not $ok) { Stop-Install (T 'Extraction failed.' 'Falha ao extrair.') }
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Add-ToPath $extracted
}

# ── pnpm ──────────────────────────────────────────────────────────────────────
# Reads the version OUTSIDE the project so pnpm doesn't react to packageManager
function Get-PnpmVersionOf([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return '' }
    $ErrorActionPreference = 'Continue'
    Push-Location $env:TEMP
    try { $v = (& $Path -v 2>$null | Select-Object -Last 1) } catch { $v = '' } finally { Pop-Location }
    return ([string]$v).Trim()
}

function Use-LocalPnpm {
    # Prefer our local copy when it satisfies the required version; otherwise use the one on PATH
    $S.PnpmCmd = Find-App 'pnpm'
    $localVer = Get-PnpmVersionOf $LocalPnpmCmd
    if ($localVer -and (-not $S.ReqPnpm -or (Compare-Version $localVer $S.ReqPnpm) -ge 0)) {
        $S.PnpmCmd = $LocalPnpmCmd
        Add-ToPath (Split-Path -Parent $LocalPnpmCmd)
    }
}

function Install-Pnpm {
    $ver  = if ($S.ReqPnpm) { $S.ReqPnpm } else { 'latest' }
    $spec = "pnpm@$ver"
    if (-not (Ask-YesNo "Download $spec with npm (about 10 MB installed)?" "Baixar $spec com npm (cerca de 10 MB instalado)?" $true)) {
        Stop-Cancelled (T 'pnpm download cancelled.' 'Download do pnpm cancelado.')
    }
    $npm = Find-App 'npm.cmd'
    if (-not $npm) { Stop-Install (T 'npm was not found.' 'npm não encontrado.') }
    New-Item -ItemType Directory -Force -Path $InstallerDir | Out-Null
    if (-not (Invoke-Spin -En "Installing $spec locally..." -Pt "Instalando $spec localmente..." -Clear `
            -File $npm -ArgList @('install', '--prefix', $PnpmHome, $spec) -WorkDir $InstallerDir)) {
        Stop-Install (T "Failed to install $spec." "Falha ao instalar $spec.")
    }
    # Always use the freshly installed local copy from here on
    $S.PnpmCmd = $LocalPnpmCmd
    Add-ToPath (Split-Path -Parent $LocalPnpmCmd)
}

function Report-Pnpm([string]$ViaEn = '', [string]$ViaPt = '') {
    $v = Get-PnpmVersionOf $S.PnpmCmd
    $notes = @(); $newer = $false
    if ($ViaEn) { $notes += (T "installed via $ViaEn" "instalado via $ViaPt") }
    if ($S.ReqPnpm -and $v -and (Compare-Version $v $S.ReqPnpm) -gt 0) {
        $newer = $true
        $notes += (T "newer than $($S.ReqPnpm)" "mais recente que $($S.ReqPnpm)")
    }
    $note = $notes -join ', '
    if ($newer) { Write-Warn "pnpm $v" $note } else { Write-Ok "pnpm $v" $note }
}

function Invoke-Pnpm([string]$En, [string]$Pt, [string]$DoneEn, [string]$DonePt, [string[]]$ArgList) {
    return (Invoke-Spin -En $En -Pt $Pt -DoneEn $DoneEn -DonePt $DonePt -File $S.PnpmCmd -ArgList $ArgList)
}

function Show-DocsLink {
    Write-Host ''
    Write-Info (T 'To install your custom build, follow this guide:' 'Para instalar sua build personalizada, siga este guia:')
    Write-Host ''
    Write-Host "    $DocsUrl" -ForegroundColor Blue
    Write-Host ("    " + (T "Built files: $VencordDir\dist" "Arquivos gerados: $VencordDir\dist")) -ForegroundColor DarkGray
}

# ── Git ───────────────────────────────────────────────────────────────────────
# Git may be installed but missing from this session's PATH (e.g. just installed)
function Find-GitInKnownDirs {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if (-not $base) { continue }
        $exe = Join-Path $base 'Git\cmd\git.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

# Picks up PATH entries added by installers after this session started
function Update-PathFromRegistry {
    $current = $env:PATH -split ';'
    $fresh = @([Environment]::GetEnvironmentVariable('Path', 'Machine'),
               [Environment]::GetEnvironmentVariable('Path', 'User')) |
        Where-Object { $_ } | ForEach-Object { $_ -split ';' } | Where-Object { $_ }
    foreach ($p in $fresh) { if ($current -notcontains $p) { $env:PATH += ";$p" } }
}

function Install-Git {
    $winget = Find-App 'winget.exe'
    if (-not $winget) {
        Stop-Install (T 'git is required, and winget is not available to install it. Install git and run this script again.' `
                        'git é necessário, mas o winget não está disponível para instalá-lo. Instale o git e execute este script novamente.')
    }
    if (-not (Ask-YesNo 'Install Git for Windows with winget (~350 MB installed)?' `
                        'Instalar o Git for Windows com winget (~350 MB instalado)?' $true)) {
        Stop-Cancelled (T 'Git installation cancelled.' 'Instalação do Git cancelada.')
    }
    $ok = Invoke-Spin -En 'Installing Git for Windows...' -Pt 'Instalando o Git for Windows...' -Clear `
        -File $winget -ArgList @('install', '--id', 'Git.Git', '--exact', '--source', 'winget', '--silent',
                                 '--accept-package-agreements', '--accept-source-agreements')
    if (-not $ok) { Stop-Install (T 'Git installation failed.' 'Falha ao instalar o Git.') }

    Update-PathFromRegistry
    $git = Find-App 'git.exe'
    if (-not $git) { $git = Find-GitInKnownDirs }
    if (-not $git) {
        Stop-Install (T 'Git was installed but could not be found. Open a new terminal and run this script again.' `
                        'O Git foi instalado, mas não foi encontrado. Abra um novo terminal e execute este script novamente.')
    }
    Add-ToPath (Split-Path -Parent $git)
    return $git
}

# ══════════════════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════════════════
$originalPath = $env:PATH
Push-Location
try {
    if ($S.Interactive) { try { Clear-Host } catch {} }
    Show-Banner

        # 1 ── Git & curl/wget ─────────────────────────────────────────────────────
    Write-Section (T 'Checking requirements' 'Verificando requisitos')
    $gitNote = ''
    $git = Find-App 'git.exe'
    if (-not $git) {
        $known = Find-GitInKnownDirs
        if ($known) {
            $git = $known
            Add-ToPath (Split-Path -Parent $known)
        } else {
            $git = Install-Git
            $gitNote = T 'installed via winget' 'instalado via winget'
        }
    }
    $S.Curl = Find-App 'curl.exe'
    $S.Wget = if ($S.Curl) { $null } else { Find-App 'wget.exe' }
    if (-not $S.Curl -and -not $S.Wget) {
        Stop-Install (T 'Neither curl nor wget is installed. Install one and run this script again.' 'curl e wget não estão instalados. Instale um deles e execute este script novamente.')
    }
    $ErrorActionPreference = 'Continue'
    $gitVer = ((& $git --version 2>$null | Select-Object -First 1) -replace '^git version\s+', '').Trim()
    if ($S.Curl) { $dlName = 'curl'; $dlVer = ((& $S.Curl --version 2>$null | Select-Object -First 1) -split '\s+')[1] }
    else         { $dlName = 'wget'; $dlVer = ((& $S.Wget --version 2>$null | Select-Object -First 1) -split '\s+')[2] }
    $ErrorActionPreference = 'Stop'
    Write-Host -NoNewline '  '
    Write-Host -NoNewline '✔' -ForegroundColor Green
    Write-Host -NoNewline " git $gitVer"
    if ($gitNote) { Write-Host -NoNewline " ($gitNote)" -ForegroundColor DarkGray }
    Write-Host -NoNewline ' '
    Write-Host -NoNewline '·' -ForegroundColor DarkGray
    Write-Host " $dlName $dlVer"

    # 2 ── Vencord repository ──────────────────────────────────────────────────
    $vencordShow = $VencordDir
    $homePrefix = $HOME.TrimEnd('\') + '\'
    if ($VencordDir.StartsWith($homePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $vencordShow = '~\' + $VencordDir.Substring($homePrefix.Length)
    }
    Write-Section (T 'Vencord repository' 'Repositório do Vencord')
    if (Test-Path -LiteralPath (Join-Path $VencordDir '.git') -PathType Container) {
        if (Ask-YesNo "Vencord found at $vencordShow. Update it?" "Vencord encontrado em $vencordShow. Atualizar?" $true) {
            if (-not (Invoke-Spin -En 'Updating Vencord...' -Pt 'Atualizando o Vencord...' `
                    -DoneEn "Vencord updated ($vencordShow)" -DonePt "Vencord atualizado ($vencordShow)" `
                    -File $git -ArgList @('-C', $VencordDir, 'pull', '--ff-only'))) {
                Stop-Install (T 'Update failed. Resolve the issue above and try again.' 'Falha ao atualizar. Resolva o problema acima e tente novamente.')
            }
        } else {
            Write-Ok "Vencord at $vencordShow" (T 'not updated' 'não atualizado')
        }
    } elseif (Test-Path -LiteralPath $VencordDir) {
        Stop-Install (T "$vencordShow exists but is not a git repository." "$vencordShow existe, mas não é um repositório git.")
    } else {
        if (-not (Invoke-Spin -En 'Cloning Vencord...' -Pt 'Clonando o Vencord...' `
                -DoneEn "Vencord cloned to $vencordShow" -DonePt "Vencord clonado em $vencordShow" `
                -File $git -ArgList @('clone', $VencordRepo, $VencordDir))) {
            Stop-Install (T 'Clone failed.' 'Falha ao clonar.')
        }
    }
    try { Set-Location -LiteralPath $VencordDir }
    catch { Stop-Install (T "Cannot enter $vencordShow" "Não foi possível entrar em $vencordShow") }

    # 3 ── Node & pnpm (versions from package.json) ────────────────────────────
    if (-not (Test-Path 'package.json')) { Stop-Install (T 'package.json not found.' 'package.json não encontrado.') }
    $package = Get-Content 'package.json' -Raw | ConvertFrom-Json
    $m = [regex]::Match([string]$package.engines.node, '\d+')
    if ($m.Success) { $S.ReqNode = $m.Value }
    $m = [regex]::Match([string]$package.packageManager, 'pnpm@([^+]+)')
    if ($m.Success) { $S.ReqPnpm = $m.Groups[1].Value }

    $pnpmReqShown = if ($S.ReqPnpm) { $S.ReqPnpm } else { 'latest' }
    Write-Section (T 'Node.js & pnpm' 'Node.js e pnpm') "Node ≥ $($S.ReqNode) · pnpm $pnpmReqShown"

    # Node
    Use-LocalNode
    $curNode = Get-NodeVersion
    if ($curNode -and (Compare-Version $curNode $S.ReqNode) -ge 0) {
        Write-Ok "Node.js v$curNode"
    } else {
        Install-Node
        $curNode = Get-NodeVersion
        if (-not $curNode -or (Compare-Version $curNode $S.ReqNode) -lt 0) {
            Stop-Install (T "Node.js $($S.ReqNode)+ still not available. Open a new terminal and retry." "Node.js $($S.ReqNode)+ ainda indisponível. Abra um novo terminal e tente novamente.")
        }
        Write-Ok "Node.js v$curNode" (T 'installed via local download' 'instalado via download local')
    }

    # pnpm (a newer version is fine; an older one or none triggers the installer prompt)
    Use-LocalPnpm
    $pnpmVer = Get-PnpmVersionOf $S.PnpmCmd
    if ($pnpmVer -and (-not $S.ReqPnpm -or (Compare-Version $pnpmVer $S.ReqPnpm) -ge 0)) {
        Report-Pnpm
    } else {
        Install-Pnpm
        if (-not (Get-PnpmVersionOf $S.PnpmCmd)) {
            Stop-Install (T 'pnpm not found after install. Open a new terminal and retry.' 'pnpm não encontrado após a instalação. Abra um novo terminal e tente novamente.')
        }
        Report-Pnpm 'local npm install' 'npm local'
    }

    # 4 ── Dependencies + plugin ───────────────────────────────────────────────
    Write-Section (T 'Setting up' 'Configurando')
    if (-not (Invoke-Pnpm 'Installing dependencies...' 'Instalando dependências...' 'Dependencies installed' 'Dependências instaladas' @('install', '--frozen-lockfile'))) {
        Stop-Install (T 'Dependency installation failed.' 'Falha ao instalar as dependências.')
    }

    $pluginDir = Join-Path (Join-Path (Join-Path $VencordDir 'src') 'userplugins') $PluginName
    $pluginOk = $false
    try { New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null; $pluginOk = $true } catch {}
    if ($pluginOk) {
        $pluginOk = Invoke-Fetch $PluginUrl (Join-Path $pluginDir 'index.ts') `
            'Downloading VideoGuardBypasser plugin...' 'Baixando o plugin VideoGuardBypasser...' `
            'VideoGuardBypasser plugin installed' 'Plugin VideoGuardBypasser instalado'
    }
    if (-not $pluginOk) { Stop-Install (T 'Plugin download failed.' 'Falha ao baixar o plugin.') }

    # 5 ── Target ──────────────────────────────────────────────────────────────
    Write-Section (T 'Build target' 'Destino da build')
    foreach ($opt in @(@('1', (T 'Discord app' 'App do Discord')), @('2', 'Vesktop'), @('3', (T 'Web (browser)' 'Web (navegador)')))) {
        Write-Host -NoNewline '    '
        Write-Host -NoNewline "$($opt[0]))" -ForegroundColor Cyan
        Write-Host " $($opt[1])"
    }
    Write-Host ''
    Write-Host -NoNewline '  '
    Write-Host -NoNewline '?' -ForegroundColor Yellow
    Write-Host -NoNewline ' ' + (T 'Choose [1/2/3]:' 'Escolha [1/2/3]:') + ' '
    $choice = $null
    while ($true) {
        $k = Read-Key
        if ($null -eq $k) { Write-Host ''; Stop-Install (T 'No terminal available for input.' 'Nenhum terminal disponível para entrada.') }
        if ($k -match '^[123]$') { $choice = $k; Write-Host $choice; break }
    }
    Write-Host ''

    switch ($choice) {
        '1' {
            if (-not (Invoke-Pnpm 'Building Vencord...' 'Compilando o Vencord...' 'Vencord built' 'Vencord compilado' @('build'))) {
                Stop-Install (T 'Build failed.' 'Falha na build.')
            }
            Write-Info (T 'Running the injector — follow the prompts below.' 'Executando o injetor — siga as instruções abaixo.')
            Write-Host ''
            $ErrorActionPreference = 'Continue'
            & $S.PnpmCmd inject
            $injectRc = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($injectRc -ne 0) { Stop-Install (T 'Injection failed.' 'Falha na injeção.') }
            Write-Host ''
            $final = T 'Restart Discord to load the modification.' `
                       'Reinicie o Discord para carregar a modificação.'
        }
        '2' {
            if (-not (Invoke-Pnpm 'Building Vencord...' 'Compilando o Vencord...' 'Vencord built' 'Vencord compilado' @('build'))) {
                Stop-Install (T 'Build failed.' 'Falha na build.')
            }
            Show-DocsLink
            $final = T 'Follow the guide above to use your custom build in Vesktop.' 'Siga o guia acima para usar sua build personalizada no Vesktop.'
        }
        '3' {
            if (-not (Invoke-Pnpm 'Building Vencord for Web...' 'Compilando o Vencord para Web...' 'Vencord (web) built' 'Vencord (web) compilado' @('buildWeb'))) {
                Stop-Install (T 'Build failed.' 'Falha na build.')
            }
            Show-DocsLink
            $final = T 'Follow the guide above to load the extension in your browser.' 'Siga o guia acima para carregar a extensão no seu navegador.'
        }
    }

    # 6 ── Done ────────────────────────────────────────────────────────────────
    $doneMsg = T 'All done! Installation complete.' 'Tudo pronto! Instalação concluída.'
    Write-Host ''
    Write-Host '  ╭──────────────────────────────────────────────╮' -ForegroundColor Green
    Write-Host ("  │  ✔ " + $doneMsg.PadRight(42) + "│") -ForegroundColor Green
    Write-Host '  ╰──────────────────────────────────────────────╯' -ForegroundColor Green
    Write-Host ''
    Write-Info $final
    if ($choice -eq '2' -or $choice -eq '3') {
        Write-Info (T 'If installing on Vesktop or Web, please take a look at:' 'Se estiver instalando no Vesktop ou na Web, consulte:')
        Write-Host '    https://github.com/caiostoduto/VideoGuardBypasser/issues/1' -ForegroundColor Blue
    }
    Write-Host ''
    $S.Finished = $true
    $global:LASTEXITCODE = 0
}
catch {
    if ($_.Exception.Message -ne 'VG_ABORT') {
        Write-Fail (T "Installer failed: $($_.Exception.Message)" "Falha no instalador: $($_.Exception.Message)")
        $global:LASTEXITCODE = 1
        $S.Finished = $true
    }
}
finally {
    if ($S.Interactive) { try { [Console]::CursorVisible = $true } catch {} }
    if (-not $S.Finished) {   # Ctrl+C
        Write-Host ''
        Write-Fail (T 'Cancelled.' 'Cancelado.')
        $global:LASTEXITCODE = 130
    }
    $env:PATH = $originalPath
    Pop-Location
}
