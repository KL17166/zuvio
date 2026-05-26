# ==============================================
# KATARI - Frontend Deployment
# Flutter Web + Cloudflare Tunnel
# ==============================================
# ATENÇÃO: Execute o backend PRIMEIRO!
# ==============================================

$ErrorActionPreference = "Stop"

# ── Configuração ──────────────────────────────
$rootDir           = Resolve-Path ".." | Select-Object -ExpandProperty Path
$cloudflaredPath   = Join-Path $rootDir "cloudflared.exe"
$flutterAppDir     = $PSScriptRoot  # Diretório atual (App-android-web)
$apiConstantsFile  = Join-Path $flutterAppDir "lib\core\constants\api_constants.dart"
$backendEnvFile    = Join-Path $rootDir "Server para o consorcio\.env"
$frontendLogFile   = Join-Path $flutterAppDir "frontend_tunnel.log"
$frontendPort      = 8080
$tunnelWaitSeconds = 60
$buildWebDir       = Join-Path $flutterAppDir "build\web"

# ── Garantir Flutter no PATH ──────────────────
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    $searchPaths = @(
        "C:\flutter\bin",
        "$env:USERPROFILE\flutter\bin",
        "$env:LOCALAPPDATA\flutter\bin",
        "C:\src\flutter\bin"
    )
    foreach ($sp in $searchPaths) {
        if (Test-Path (Join-Path $sp "flutter.bat")) {
            $env:PATH = "$sp;$env:PATH"
            break
        }
    }
}

# ── Funções Auxiliares ────────────────────────

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $line = "=" * 50
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-Step {
    param([int]$Num, [int]$Total, [string]$Msg)
    Write-Host "`n[$Num/$Total] $Msg" -ForegroundColor Yellow
}

function Write-Ok   { param([string]$Msg) Write-Host "   ✓  $Msg" -ForegroundColor Green }
function Write-Err  { param([string]$Msg) Write-Host "   ✗  $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "   ›  $Msg" -ForegroundColor Gray }
function Write-Warn { param([string]$Msg) Write-Host "   ⚠  $Msg" -ForegroundColor DarkYellow }

function Stop-OldProcesses {
    # Para processos Python na porta do frontend
    Get-Process -Name "python" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdLine -and $cmdLine -match "$frontendPort") {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                Write-Info "Processo Python antigo (PID $($_.Id)) encerrado"
            }
        } catch { }
    }
    
    # Para cloudflared do frontend (não mexe no backend)
    # (só se identificarmos pelo log file)
}

function Get-BackendUrl {
    <#
    .SYNOPSIS
        Obtém a URL do backend do arquivo .env
    #>
    $url = $null
    
    if (Test-Path $backendEnvFile) {
        foreach ($line in (Get-Content $backendEnvFile)) {
            if ($line -match "^PIXGO_WEBHOOK_URL=(.+)$") {
                $candidate = $matches[1].Trim()
                if ($candidate -match "^https://") { 
                    $url = $candidate 
                }
            }
        }
    }
    
    return $url
}

function Update-ApiConstants {
    param([string]$BackendUrl)
    
    if (-not (Test-Path $apiConstantsFile)) {
        throw "Arquivo api_constants.dart não encontrado em: $apiConstantsFile"
    }
    
    $content = Get-Content $apiConstantsFile -Raw
    $updated = $content -replace "(?s)static const String _tunnelUrl\s*=\s*'https://[^']+';" , "static const String _tunnelUrl = '$BackendUrl';"
    $updated | Set-Content $apiConstantsFile -NoNewline -Encoding UTF8
    
    Write-Ok "api_constants.dart atualizado com: $BackendUrl"
}

function Build-FlutterWeb {
    Push-Location $flutterAppDir
    try {
        Write-Info "Compilando Flutter Web (isso pode levar alguns minutos)..."
        $output = cmd /c "flutter build web --release --no-web-resources-cdn 2>&1"
        $exitCode = $LASTEXITCODE
        
        # Mostra output
        $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        
        if ($exitCode -ne 0) {
            throw "Flutter build web falhou (exit code $exitCode)"
        }
        Write-Ok "Flutter Web compilado com sucesso!"
    } finally {
        Pop-Location
    }
}

function Start-HttpServer {
    <#
    .SYNOPSIS
        Inicia servidor HTTP Python para servir os arquivos
    .OUTPUTS
        Retorna o objeto do processo
    #>
    if (-not (Test-Path $buildWebDir)) {
        throw "Diretório de build não encontrado: $buildWebDir"
    }
    
    $absPath = Resolve-Path $buildWebDir | Select-Object -ExpandProperty Path
    $args = "-m http.server $frontendPort --directory `"$absPath`""
    
    $proc = Start-Process -FilePath "python" `
                          -ArgumentList $args `
                          -PassThru `
                          -WindowStyle Hidden
    
    Start-Sleep -Milliseconds 800
    
    if ($proc.HasExited) {
        throw "Servidor HTTP falhou ao iniciar. Verifique se a porta $frontendPort está livre"
    }
    
    Write-Ok "Servidor HTTP rodando em http://localhost:$frontendPort (PID: $($proc.Id))"
    return $proc
}

function Start-FrontendTunnel {
    <#
    .SYNOPSIS
        Cria Cloudflare Quick Tunnel para o frontend
    .OUTPUTS
        Retorna a URL pública do tunnel
    #>
    if (-not (Test-Path $cloudflaredPath)) {
        throw "cloudflared.exe não encontrado em: $cloudflaredPath"
    }
    
    # Limpa log anterior
    if (Test-Path $frontendLogFile) { Remove-Item $frontendLogFile -Force }
    
    Start-Process -FilePath $cloudflaredPath `
                  -ArgumentList "tunnel --url http://localhost:$frontendPort" `
                  -RedirectStandardError $frontendLogFile `
                  -WindowStyle Hidden
    
    Write-Info "Aguardando URL do tunnel (max ${tunnelWaitSeconds}s)..."
    
    $frontendUrl = $null
    for ($i = 0; $i -lt $tunnelWaitSeconds; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Test-Path $frontendLogFile)) { continue }
        
        try {
            $tmpLog = "$frontendLogFile.tmp"
            Copy-Item $frontendLogFile $tmpLog -Force -ErrorAction SilentlyContinue
            if (Test-Path $tmpLog) {
                $text = Get-Content $tmpLog -Raw
                if ($text -match "(https://[a-zA-Z0-9-]+\.trycloudflare\.com)") {
                    $frontendUrl = $matches[1].Trim()
                    Remove-Item $tmpLog -ErrorAction SilentlyContinue
                    break
                }
                Remove-Item $tmpLog -ErrorAction SilentlyContinue
            }
        } catch { }
        
        Write-Host "." -NoNewline
    }
    
    if (-not $frontendUrl) {
        throw "`nTimeout: Não foi possível obter URL do tunnel. Verifique $frontendLogFile"
    }
    
    Write-Host ""
    return $frontendUrl
}

function Cleanup {
    param([System.Diagnostics.Process]$HttpProcess)
    
    Write-Host "`n`nEncerrando frontend..." -ForegroundColor Yellow
    
    if ($HttpProcess -and -not $HttpProcess.HasExited) {
        Stop-Process -Id $HttpProcess.Id -Force -ErrorAction SilentlyContinue
        Write-Info "Servidor HTTP encerrado"
    }
    
    # Para APENAS cloudflared do frontend
    # (identificar pelo processo ou log file para não matar o backend)
    $cloudflaredProcs = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    foreach ($proc in $cloudflaredProcs) {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdLine -and $cmdLine -match "$frontendPort") {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Write-Info "Cloudflare Tunnel do frontend encerrado"
            }
        } catch { }
    }
    
    Write-Host "Frontend encerrado." -ForegroundColor Yellow
}

# ── Execução Principal ────────────────────────

$httpProcess = $null
$totalSteps  = 5

try {
    Write-Banner "KATARI - Frontend Deployment"
    
    # ── Passo 1: Verificar pré-requisitos ─────────
    Write-Step 1 $totalSteps "Verificando pré-requisitos..."
    
    if (-not (Test-Path $cloudflaredPath)) {
        Write-Err "cloudflared.exe não encontrado em $cloudflaredPath"
        exit 1
    }
    Write-Ok "cloudflared.exe encontrado"
    
    $pythonVersion = & python --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Python não encontrado. Instale o Python 3"
        exit 1
    }
    Write-Ok "Python detectado: $pythonVersion"
    
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        Write-Err "Flutter não encontrado. Instale o Flutter SDK"
        exit 1
    }
    $flutterVersion = & flutter --version 2>&1 | Select-Object -First 1
    Write-Ok "Flutter detectado: $flutterVersion"
    
    # ── Passo 2: Ler URL do backend ───────────────
    Write-Step 2 $totalSteps "Verificando backend..."
    
    $backendUrl = Get-BackendUrl
    if (-not $backendUrl) {
        Write-Err "URL do backend não encontrada!"
        Write-Host ""
        Write-Warn "VOCÊ PRECISA INICIAR O BACKEND PRIMEIRO!"
        Write-Info "Execute na pasta 'Server para o consorcio':"
        Write-Info "  .\start_backend.ps1"
        Write-Host ""
        exit 1
    }
    Write-Ok "Backend detectado: $backendUrl"
    
    # ── Passo 3: Atualizar api_constants.dart ─────
    Write-Step 3 $totalSteps "Atualizando api_constants.dart..."
    Update-ApiConstants -BackendUrl $backendUrl
    
    # ── Passo 4: Build + Servir Flutter Web ───────
    Write-Step 4 $totalSteps "Compilando e servindo Flutter Web..."
    Stop-OldProcesses
    Build-FlutterWeb
    $httpProcess = Start-HttpServer
    
    # ── Passo 5: Cloudflare Tunnel ────────────────
    Write-Step 5 $totalSteps "Iniciando Cloudflare Tunnel..."
    $frontendUrl = Start-FrontendTunnel
    
    # ── Resultado Final ───────────────────────────
    Write-Banner "✨ TUDO PRONTO! ✨" "Green"
    Write-Host ""
    Write-Host "  🌐 FRONTEND:  " -NoNewline -ForegroundColor White
    Write-Host "$frontendUrl" -ForegroundColor Cyan
    Write-Host "  📡 BACKEND:   " -NoNewline -ForegroundColor White
    Write-Host "$backendUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  📱 Compartilhe o link do FRONTEND" -ForegroundColor White
    Write-Host "  para qualquer pessoa acessar o app!" -ForegroundColor White
    Write-Banner "" "Green"
    Write-Host ""
    Write-Host "Pressione Ctrl+C para encerrar..." -ForegroundColor Gray
    
    # Manter vivo
    while ($true) { Start-Sleep -Seconds 5 }
    
} catch {
    Write-Err $_.Exception.Message
    exit 1
    
} finally {
    Cleanup -HttpProcess $httpProcess
}