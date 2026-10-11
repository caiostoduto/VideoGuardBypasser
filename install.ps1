# Vencord + VideoGuardBypasser installer for Windows PowerShell.
# Usage: .\install.ps1 [-Language en|pt] [-VencordDir PATH]
param(
    [string]$Language = '',
    [string]$VencordDir = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $VencordDir) { $VencordDir = Join-Path $HOME 'Vencord' }
$VencordRepo = 'https://github.com/Vendicated/Vencord.git'
$PluginName = 'videoGuardBypasser'
$PluginUrl = 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts'
$DocsUrl = 'https://docs.vencord.dev/installing/#installing-your-custom-build'
$InstallerDir = Join-Path $env:LOCALAPPDATA 'vencord-installer'
$PnpmHome = Join-Path $InstallerDir 'pnpm'
$script:NodeExe = $null
$script:PnpmCmd = $null

if (-not $Language) {
    $locale = @($env:VG_LANG,
        [Globalization.CultureInfo]::CurrentUICulture.Name,
        [Globalization.CultureInfo]::CurrentCulture.Name,
        $env:LC_ALL, $env:LC_MESSAGES, $env:LANG) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1
    if ($locale -like 'pt*') { $Language = 'pt' } else { $Language = 'en' }
}
if ($Language -notin @('en', 'pt')) { throw 'Language must be en or pt.' }

function T([string]$English, [string]$Portuguese) {
    if ($Language -eq 'pt') { return $Portuguese }
    return $English
}

function Write-Info([string]$English, [string]$Portuguese) { Write-Host "  ● $(T $English $Portuguese)" -ForegroundColor Blue }
function Write-Ok([string]$English, [string]$Portuguese) { Write-Host "  ✔ $(T $English $Portuguese)" -ForegroundColor Green }
function Write-Warn([string]$English, [string]$Portuguese) { Write-Host "  ! $(T $English $Portuguese)" -ForegroundColor Yellow }
function Stop-Install([string]$Message) {
    Write-Host "  ✖ $Message" -ForegroundColor Red
    exit 1
}

function Invoke-Quiet([string]$FilePath, [string[]]$Arguments, [string]$WorkingMessage) {
    $log = Join-Path $env:TEMP ("vencord-install-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $argumentsJson = ConvertTo-Json -InputObject @($Arguments) -Compress
    $frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $frameIndex = 0
    $interactive = $true
    try {
        $job = Start-Job -ArgumentList $FilePath, $argumentsJson, $log -ScriptBlock {
            param($CommandPath, $CommandArgumentsJson, $LogPath)
            $ErrorActionPreference = 'Continue'
            $commandArguments = @(ConvertFrom-Json -InputObject $CommandArgumentsJson)
            & $CommandPath @commandArguments *> $LogPath
            if ($null -eq $LASTEXITCODE) { return 1 }
            return [int]$LASTEXITCODE
        }
        try {
            try { [void][Console]::WindowWidth } catch { $interactive = $false }
            while ($job.State -in @('NotStarted', 'Running')) {
                if ($interactive) {
                    $previousColor = [Console]::ForegroundColor
                    [Console]::ForegroundColor = [ConsoleColor]::Cyan
                    [Console]::Write("`r  {0}" -f $frames[$frameIndex])
                    [Console]::ForegroundColor = $previousColor
                    [Console]::Write(" {0}..." -f $WorkingMessage)
                    $frameIndex = ($frameIndex + 1) % $frames.Count
                }
                Wait-Job -Job $job -Timeout 0.1 | Out-Null
            }
            $exitCode = Receive-Job -Job $job -Wait
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        if ($interactive) { Clear-CurrentLine }
        if ($null -eq $exitCode) { $exitCode = 1 }
        if ($exitCode -ne 0) {
            Write-Host "  $(T 'Command failed' 'Falha no comando'): $FilePath $($Arguments -join ' ')" -ForegroundColor Red
            if (Test-Path $log) { Get-Content -LiteralPath $log -Tail 25 | ForEach-Object { Write-Host "    $_" } }
            throw "$FilePath exited with code $exitCode."
        }
    } finally {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
}

function Clear-CurrentLine {
    try {
        $width = [Console]::WindowWidth
        [Console]::Write("`r" + (' ' * [Math]::Max(1, $width - 1)) + "`r")
    } catch { Write-Host '' }
}

function Show-LineStatus([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    Clear-CurrentLine
    Write-Host "  $Message" -ForegroundColor $Color
}

function Invoke-Status([string]$WorkingEnglish, [string]$WorkingPortuguese,
    [string]$DoneEnglish, [string]$DonePortuguese,
    [string]$FilePath, [string[]]$Arguments, [switch]$ClearOnSuccess) {
    $working = T $WorkingEnglish $WorkingPortuguese
    if (-not [Console]::IsOutputRedirected) { Write-Host -NoNewline "  $working..." }
    try { Invoke-Quiet $FilePath $Arguments $working }
    catch { Clear-CurrentLine; throw }
    if ($ClearOnSuccess) { Clear-CurrentLine }
    else { Show-LineStatus (T $DoneEnglish $DonePortuguese) ([ConsoleColor]::Green) }
}

function Invoke-ActionStatus([string]$WorkingEnglish, [string]$WorkingPortuguese,
    [string]$DoneEnglish, [string]$DonePortuguese, [scriptblock]$Action,
    [object[]]$ActionArguments = @(), [switch]$ClearOnSuccess) {
    $working = T $WorkingEnglish $WorkingPortuguese
    $log = Join-Path $env:TEMP ("vencord-install-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $argumentsJson = ConvertTo-Json -InputObject @($ActionArguments) -Compress
    $frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $frameIndex = 0
    $interactive = $true
    try {
        $job = Start-Job -ArgumentList $Action.ToString(), $argumentsJson, $log -ScriptBlock {
            param($ActionText, $ArgumentsJson, $LogPath)
            $ErrorActionPreference = 'Continue'
            try {
                $actionArguments = @(ConvertFrom-Json -InputObject $ArgumentsJson)
                $action = [scriptblock]::Create($ActionText)
                & $action @actionArguments *> $LogPath
                if ($?) { return 0 }
                return 1
            } catch {
                $_ | Out-File -FilePath $LogPath -Append
                return 1
            }
        }
        try {
            try { [void][Console]::WindowWidth } catch { $interactive = $false }
            while ($job.State -in @('NotStarted', 'Running')) {
                if ($interactive) {
                    $previousColor = [Console]::ForegroundColor
                    [Console]::ForegroundColor = [ConsoleColor]::Cyan
                    [Console]::Write("`r  {0}" -f $frames[$frameIndex])
                    [Console]::ForegroundColor = $previousColor
                    [Console]::Write(" {0}..." -f $working)
                    $frameIndex = ($frameIndex + 1) % $frames.Count
                }
                Wait-Job -Job $job -Timeout 0.1 | Out-Null
            }
            $exitCode = Receive-Job -Job $job -Wait
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        if ($interactive) { Clear-CurrentLine }
        if ($exitCode -ne 0) {
            Write-Host "  $(T 'Operation failed' 'Falha na operação')" -ForegroundColor Red
            if (Test-Path $log) { Get-Content -LiteralPath $log -Tail 25 | ForEach-Object { Write-Host "    $_" } }
            throw 'Action failed.'
        }
    } finally {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
    if ($ClearOnSuccess) { Clear-CurrentLine }
    else { Show-LineStatus (T $DoneEnglish $DonePortuguese) ([ConsoleColor]::Green) }
}

function Write-Section([string]$English, [string]$Portuguese, [string]$Suffix = '') {
    $label = T $English $Portuguese
    if ($Suffix) { $label += "  $Suffix" }
    Write-Host "`n▸ $label" -ForegroundColor Magenta
}

function Ask-YesNo([string]$English, [string]$Portuguese, [bool]$DefaultYes = $true) {
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    if ($Language -eq 'pt') { $hint = if ($DefaultYes) { 'S/n' } else { 's/N' } }
    Write-Host -NoNewline -ForegroundColor Yellow '  ?'
    Write-Host -NoNewline " $(T $English $Portuguese) [$hint] "
    while ($true) {
        try {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $answer = [string]$key.Character
            if ($key.VirtualKeyCode -eq 13) {
                Clear-CurrentLine
                return $DefaultYes
            }
        } catch {
            Clear-CurrentLine
            $answer = Read-Host "  $(T $English $Portuguese) [$hint]"
            if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        }
        if ($answer -match '^(?i:y|s)$') { Clear-CurrentLine; return $true }
        if ($answer -match '^(?i:n)$') { Clear-CurrentLine; return $false }
    }
}

function Get-Downloader {
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) { return 'curl.exe' }
    if (Get-Command wget.exe -ErrorAction SilentlyContinue) { return 'wget.exe' }
    return $null
}

function Get-ToolVersion([string]$Name) {
    switch ($Name) {
        'git' { return ((& git --version) -replace '^git version\s+', '') }
        'curl.exe' { return ((& curl.exe --version | Select-Object -First 1) -replace '^curl\s+', '') }
        'wget.exe' { return ((& wget.exe --version | Select-Object -First 1) -replace '^GNU Wget\s+', '') }
    }
}

function Compare-Version([string]$A, [string]$B) {
    $A = ($A -split '[-+]')[0]
    $B = ($B -split '[-+]')[0]
    $left = @($A.Split('.'))
    $right = @($B.Split('.'))
    for ($i = 0; $i -lt 3; $i++) {
        $x = 0; $y = 0
        if ($i -lt $left.Count) { [void][int]::TryParse($left[$i], [ref]$x) }
        if ($i -lt $right.Count) { [void][int]::TryParse($right[$i], [ref]$y) }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

function Get-NodePlatform {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { $null }
    }
    if (-not $arch) { throw "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE" }
    return "win-$arch"
}

function Get-LatestLtsNode([string]$RequiredVersion) {
    $releases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
    $release = $releases | Where-Object {
        $_.lts -and (Compare-Version ([string]$_.version).TrimStart('v') $RequiredVersion) -ge 0
    } | Select-Object -First 1
    if (-not $release) { throw "No Node.js LTS release meets the required version $RequiredVersion." }
    return ([string]$release.version).TrimStart('v')
}

function Get-NodeVersion {
    if (-not $script:NodeExe) {
        $node = Get-Command node.exe -ErrorAction SilentlyContinue
        if (-not $node) { return '' }
        $script:NodeExe = $node.Source
    }
    return ((& $script:NodeExe --version 2>$null) -replace '^v', '').Trim()
}

function Get-PnpmVersion {
    if (-not $script:PnpmCmd) {
        $pnpm = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
        if (-not $pnpm) { return '' }
        Set-PnpmCommand $pnpm.Source
    }
    Push-Location $env:TEMP
    try { return ((& $script:PnpmCmd --version 2>$null | Select-Object -Last 1).Trim()) }
    finally { Pop-Location }
}

function Set-NodeCommand([string]$Path) {
    $script:NodeExe = $Path
    $nodeDirectory = Split-Path -Parent $Path
    $env:PATH = "$nodeDirectory;$env:PATH"
}

function Set-PnpmCommand([string]$Path) {
    $script:PnpmCmd = $Path
    $pnpmDirectory = Split-Path -Parent $Path
    $env:PATH = "$pnpmDirectory;$env:PATH"
}

function Invoke-PnpmStatus([string]$WorkingEnglish, [string]$WorkingPortuguese,
    [string]$DoneEnglish, [string]$DonePortuguese, [string[]]$Arguments) {
    if (-not $script:PnpmCmd) {
        $pnpm = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
        if (-not $pnpm) { throw 'pnpm.cmd was not found on PATH.' }
        Set-PnpmCommand $pnpm.Source
    }
    Invoke-Status $WorkingEnglish $WorkingPortuguese $DoneEnglish $DonePortuguese $script:PnpmCmd $Arguments
}

function Use-LocalNode([string]$RequiredVersion) {
    $platform = Get-NodePlatform
    $bestHome = $null
    $bestVersion = $null
    if (Test-Path $InstallerDir) {
        foreach ($directory in (Get-ChildItem -LiteralPath $InstallerDir -Directory -Filter "node-v*-$platform")) {
            $match = [regex]::Match($directory.Name, '^node-v(.+)-' + [regex]::Escape($platform) + '$')
            $localNode = Join-Path $directory.FullName 'node.exe'
            if (-not $match.Success -or -not (Test-Path $localNode)) { continue }
            $localVersion = $match.Groups[1].Value
            if ((Compare-Version $localVersion $RequiredVersion) -ge 0 -and
                (-not $bestVersion -or (Compare-Version $localVersion $bestVersion) -gt 0)) {
                $bestHome = $directory.FullName
                $bestVersion = $localVersion
            }
        }
    }
    if ($bestHome) { Set-NodeCommand (Join-Path $bestHome 'node.exe') }
}

function Use-LocalPnpm([string]$RequiredVersion) {
    $localBin = Join-Path $PnpmHome 'node_modules\.bin'
    $localPnpm = Join-Path $localBin 'pnpm.cmd'
    if (Test-Path $localPnpm) {
        Push-Location $env:TEMP
        try { $localVersion = (& $localPnpm --version 2>$null | Select-Object -Last 1).Trim() }
        finally { Pop-Location }
        if (-not $RequiredVersion -or (Compare-Version $localVersion $RequiredVersion) -ge 0) {
            Set-PnpmCommand $localPnpm
        }
    }
}

function Install-Node([string]$RequiredVersion) {
    $nodeVersion = Get-LatestLtsNode $RequiredVersion
    if (-not (Ask-YesNo "Download Node.js LTS $nodeVersion (~100 MB installed)?" "Baixar Node.js LTS $nodeVersion (~100 MB instalado)?")) {
        Write-Host "  ! $(T 'Node.js download cancelled.' 'Download do Node.js cancelado.')" -ForegroundColor Red
        exit 1
    }
    $platform = Get-NodePlatform
    $archive = Join-Path $InstallerDir "node-v$nodeVersion-$platform.zip"
    New-Item -ItemType Directory -Force -Path $InstallerDir | Out-Null
    $url = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-$platform.zip"
    $downloader = Get-Downloader
    if ($downloader -eq 'curl.exe') {
        Invoke-Status "Downloading Node.js LTS $nodeVersion" "Baixando Node.js LTS $nodeVersion" `
            "Node.js LTS $nodeVersion downloaded" "Node.js LTS $nodeVersion baixado" `
            $downloader @('-fLsS', '--output', $archive, $url) -ClearOnSuccess
    } else {
        Invoke-Status "Downloading Node.js LTS $nodeVersion" "Baixando Node.js LTS $nodeVersion" `
            "Node.js LTS $nodeVersion downloaded" "Node.js LTS $nodeVersion baixado" `
            $downloader @('-q', '-O', $archive, $url) -ClearOnSuccess
    }
    Invoke-ActionStatus 'Extracting Node.js' 'Extraindo o Node.js' `
        'Node.js extracted' 'Node.js extraído' {
        param($ArchivePath, $DestinationPath)
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force -ErrorAction Stop
        Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction Stop
    } @($archive, $InstallerDir) -ClearOnSuccess
    $nodeHome = Join-Path $InstallerDir "node-v$nodeVersion-$platform"
    Set-NodeCommand (Join-Path $nodeHome 'node.exe')
}

function Install-Pnpm([string]$Version) {
    $spec = "pnpm@$Version"
    if (-not (Ask-YesNo "Download $spec with npm (about 10 MB installed)?" "Baixar $spec com npm (cerca de 10 MB instalado)?")) {
        Write-Host "  ! $(T 'pnpm download cancelled.' 'Download do pnpm cancelado.')" -ForegroundColor Red
        exit 1
    }
    New-Item -ItemType Directory -Force -Path $InstallerDir | Out-Null
    Invoke-Status "Installing $spec locally" "Instalando $spec localmente" `
        "$spec installed" "$spec instalado" 'npm.cmd' @('install', '--prefix', $PnpmHome, $spec)
    Set-PnpmCommand (Join-Path (Join-Path $PnpmHome 'node_modules\.bin') 'pnpm.cmd')
}

function Show-Banner {
    Write-Host ''
    Write-Host '  ╭──────────────────────────────────────────────╮' -ForegroundColor Cyan
    Write-Host '  │                                              │' -ForegroundColor Cyan
    Write-Host '  │      Vencord  ×  VideoGuardBypasser          │' -ForegroundColor Cyan
    $title = T 'Automatic installer' 'Instalador automático'
    Write-Host ("  │      {0,-39} │" -f $title) -ForegroundColor Cyan
    Write-Host '  │                                              │' -ForegroundColor Cyan
    Write-Host '  ╰──────────────────────────────────────────────╯' -ForegroundColor Cyan
}

try {
    Show-Banner
    Write-Section 'Checking requirements' 'Verificando requisitos'
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) {
            Stop-Install (T 'git.exe is required, and winget.exe is not available to install it.' 'git.exe é necessário, mas winget.exe não está disponível para instalá-lo.')
        }
        if (-not (Ask-YesNo 'git.exe is missing. Install Git for Windows with winget?' 'git.exe não encontrado. Instalar o Git for Windows com winget?')) {
            Stop-Install (T 'Git installation cancelled.' 'Instalação do Git cancelada.')
        }
        Invoke-Status 'Installing Git for Windows with winget' 'Instalando Git for Windows com winget' `
            'Git for Windows installed' 'Git for Windows instalado' 'winget.exe' `
            @('install', '--id', 'Git.Git', '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
        $gitDirectories = @(
            (Join-Path $env:ProgramFiles 'Git\cmd'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd')
        )
        foreach ($gitDirectory in $gitDirectories) {
            if (Test-Path (Join-Path $gitDirectory 'git.exe')) {
                $env:PATH = "$gitDirectory;$env:PATH"
                break
            }
        }
        if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
            Stop-Install (T 'Git was installed. Open a new terminal and run this script again.' 'O Git foi instalado. Abra um novo terminal e execute este script novamente.')
        }
    }
    $downloader = Get-Downloader
    if (-not $downloader) {
        Stop-Install (T 'curl.exe or wget.exe is required. Install one and run this script again.' 'curl.exe ou wget.exe é necessário. Instale um deles e execute este script novamente.')
    }
    Write-Ok "git $(Get-ToolVersion 'git')  ·  $($downloader -replace '\.exe$', '') $(Get-ToolVersion $downloader)" `
        "git $(Get-ToolVersion 'git')  ·  $($downloader -replace '\.exe$', '') $(Get-ToolVersion $downloader)"

    Write-Section 'Vencord repository' 'Repositório do Vencord'
    if (Test-Path (Join-Path $VencordDir '.git')) {
        if (Ask-YesNo "Vencord found at $VencordDir. Update it?" "Vencord encontrado em $VencordDir. Atualizar?") {
            Invoke-Status 'Updating Vencord' 'Atualizando Vencord' `
                "Vencord updated ($VencordDir)" "Vencord atualizado ($VencordDir)" `
                'git.exe' @('-C', $VencordDir, 'pull', '--ff-only')
        } else {
            Write-Ok "Vencord at $VencordDir (not updated)" "Vencord em $VencordDir (não atualizado)"
        }
    } elseif (Test-Path $VencordDir) {
        Stop-Install (T "$VencordDir exists but is not a Git repository." "$VencordDir existe, mas não é um repositório Git.")
    } else {
        Invoke-Status 'Cloning Vencord' 'Clonando Vencord' `
            "Vencord cloned to $VencordDir" "Vencord clonado em $VencordDir" `
            'git.exe' @('clone', $VencordRepo, $VencordDir)
    }
    Set-Location $VencordDir

    if (-not (Test-Path 'package.json')) { Stop-Install (T 'package.json not found.' 'package.json não encontrado.') }
    $package = Get-Content 'package.json' -Raw | ConvertFrom-Json
    $nodeRequirement = [string]$package.engines.node
    $nodeMatch = [regex]::Match($nodeRequirement, '(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    $requiredNode = if ($nodeMatch.Success) {
        '{0}.{1}.{2}' -f $nodeMatch.Groups[1].Value, $(if ($nodeMatch.Groups[2].Success) { $nodeMatch.Groups[2].Value } else { '0' }), $(if ($nodeMatch.Groups[3].Success) { $nodeMatch.Groups[3].Value } else { '0' })
    } else { '22.0.0' }
    $packageManager = [string]$package.packageManager
    $pnpmMatch = [regex]::Match($packageManager, 'pnpm@([^+]+)')
    $requiredPnpm = if ($pnpmMatch.Success) { $pnpmMatch.Groups[1].Value } else { '' }
    Write-Section 'Node.js & pnpm' 'Node.js e pnpm' "Node ≥ $requiredNode · pnpm $(if ($requiredPnpm) { $requiredPnpm } else { 'latest' })"

    Use-LocalNode $requiredNode
    $currentNode = Get-NodeVersion
    if (-not $currentNode -or (Compare-Version $currentNode $requiredNode) -lt 0) {
        if ($currentNode) {
            Write-Warn "Node.js v$currentNode is too old" "Node.js v$currentNode está desatualizado"
        } else {
            Write-Warn 'Node.js is not installed' 'Node.js não está instalado'
        }
        Install-Node $requiredNode
        $currentNode = Get-NodeVersion
        if (-not $currentNode -or (Compare-Version $currentNode $requiredNode) -lt 0) {
            Stop-Install (T "Node.js $requiredNode+ is still unavailable." "Node.js $requiredNode+ ainda está indisponível.")
        }
        Write-Ok "Node.js v$currentNode (local download)" "Node.js v$currentNode (download local)"
    } else { Write-Ok "Node.js v$currentNode" "Node.js v$currentNode" }

    Use-LocalPnpm $requiredPnpm
    $currentPnpm = Get-PnpmVersion
    if (-not $currentPnpm -or ($requiredPnpm -and (Compare-Version $currentPnpm $requiredPnpm) -lt 0)) {
        if ($currentPnpm) {
            Write-Warn "pnpm $currentPnpm is older than $requiredPnpm" "pnpm $currentPnpm é mais antigo que $requiredPnpm"
        } else {
            Write-Warn 'pnpm is not installed' 'pnpm não está instalado'
        }
        if (-not $requiredPnpm) { Stop-Install (T 'Could not read the required pnpm version from package.json.' 'Não foi possível ler a versão necessária do pnpm em package.json.') }
        Install-Pnpm $requiredPnpm
        $currentPnpm = Get-PnpmVersion
        if (-not $currentPnpm) { Stop-Install (T 'pnpm was not found after installation.' 'pnpm não foi encontrado após a instalação.') }
        Write-Ok "pnpm $currentPnpm (local npm install)" "pnpm $currentPnpm (instalação local via npm)"
    } elseif ($requiredPnpm -and (Compare-Version $currentPnpm $requiredPnpm) -gt 0) {
        Write-Warn "pnpm $currentPnpm (newer than $requiredPnpm)" "pnpm $currentPnpm (mais recente que $requiredPnpm)"
    } else { Write-Ok "pnpm $currentPnpm" "pnpm $currentPnpm" }

    Write-Section 'Setting up' 'Configurando'
    Invoke-PnpmStatus 'Installing dependencies' 'Instalando dependências' `
        'Dependencies installed' 'Dependências instaladas' @('install', '--frozen-lockfile')

    $pluginDir = Join-Path (Join-Path 'src' 'userplugins') $PluginName
    New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
    $pluginPath = Join-Path $pluginDir 'index.ts'
    $downloader = Get-Downloader
    if ($downloader -eq 'curl.exe') {
        Invoke-Status 'Downloading VideoGuardBypasser plugin' 'Baixando o plugin VideoGuardBypasser' `
            'VideoGuardBypasser plugin downloaded' 'Plugin VideoGuardBypasser baixado' `
            $downloader @('-fLsS', '--output', $pluginPath, $PluginUrl)
    } else {
        Invoke-Status 'Downloading VideoGuardBypasser plugin' 'Baixando o plugin VideoGuardBypasser' `
            'VideoGuardBypasser plugin downloaded' 'Plugin VideoGuardBypasser baixado' `
            $downloader @('-q', '-O', $pluginPath, $PluginUrl)
    }

    Write-Section 'Build target' 'Destino da build'
    Write-Host (T '  1) Discord app' '  1) Aplicativo do Discord')
    Write-Host '  2) Vesktop'
    Write-Host (T '  3) Web (browser)' '  3) Web (navegador)')
    Write-Host -NoNewline -ForegroundColor Yellow '  ?'
    Write-Host -NoNewline (T ' Choose [1/2/3]: ' ' Escolha [1/2/3]: ')
    $choice = ''
    while ($choice -notin @('1', '2', '3')) {
        try {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.Character -match '^[1-3]$') { $choice = [string]$key.Character }
            elseif ($key.VirtualKeyCode -eq 13) { continue }
        } catch {
            $choice = Read-Host (T '  Choose [1/2/3]' '  Escolha [1/2/3]')
            break
        }
    }
    if ($choice -notin @('1', '2', '3')) { Stop-Install (T 'Invalid build target.' 'Destino de compilação inválido.') }
    Write-Host $choice

    switch ($choice) {
        '1' {
            Invoke-PnpmStatus 'Building Vencord' 'Compilando o Vencord' `
                'Vencord built' 'Vencord compilado' @('build')
            Write-Host (T '  Running the injector — follow its prompts.' '  Executando o injetor — siga as instruções.')
            & $script:PnpmCmd inject
            if ($LASTEXITCODE -ne 0) { Stop-Install (T 'Injection failed.' 'Falha na injeção.') }
            $final = T 'Restart Discord to load the modification. Enable the plugin at Settings → Plugins → VideoGuardBypasser.' 'Reinicie o Discord para carregar a modificação. Ative o plugin em Configurações → Plugins → VideoGuardBypasser.'
        }
        '2' {
            Invoke-PnpmStatus 'Building Vencord' 'Compilando o Vencord' `
                'Vencord built' 'Vencord compilado' @('build')
            Write-Info "To use your custom build in Vesktop, follow: $DocsUrl" "Para usar sua build personalizada no Vesktop, siga: $DocsUrl"
            $final = T 'Follow the guide above to use your custom build in Vesktop.' 'Siga o guia acima para usar sua build personalizada no Vesktop.'
        }
        '3' {
            Invoke-PnpmStatus 'Building Vencord for Web' 'Compilando o Vencord para Web' `
                'Vencord for Web built' 'Vencord para Web compilado' @('buildWeb')
            Write-Info "To load the browser extension, follow: $DocsUrl" "Para carregar a extensão no navegador, siga: $DocsUrl"
            $final = T 'Follow the guide above to load the extension in your browser.' 'Siga o guia acima para carregar a extensão no seu navegador.'
        }
    }
    Write-Host "`n  ╭──────────────────────────────────────────────╮" -ForegroundColor Green
    $complete = T 'All done! Installation complete.' 'Tudo pronto! Instalação concluída.'
    $completeWidth = 42 + [Text.Encoding]::UTF8.GetByteCount($complete) - $complete.Length
    Write-Host ("  │  ✔ {0,-$completeWidth}│" -f $complete) -ForegroundColor Green
    Write-Host '  ╰──────────────────────────────────────────────╯' -ForegroundColor Green
    Write-Info $final $final
} catch {
    Stop-Install (T "Installer failed: $($_.Exception.Message)" "Falha no instalador: $($_.Exception.Message)")
}
