# ==============================================
# KATARI - Backend Server + Cloudflare Tunnel
# ==============================================
# Este script APENAS inicia o servidor Node.js
# e cria um tunnel Cloudflare para ele.
# ==============================================

$ErrorActionPreference = "Stop"

# -- Configuracao --
$cloudflaredPath = Resolve-Path "..\cloudflared.exe" | Select-Object -ExpandProperty Path
$envFile = ".env"
$logFile = "tunnel.log"
$port = 3000
$maxWaitSeconds = 60

# -- Funcoes Auxiliares --

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $line = "=" * 50
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-Step {
    param([string]$Msg)
    Write-Host "`n>> $Msg" -ForegroundColor Yellow
}

function Write-Ok   { param([string]$Msg) Write-Host "   [OK] $Msg" -ForegroundColor Green }
function Write-Err  { param([string]$Msg) Write-Host "   [ERR] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "   > $Msg" -ForegroundColor Gray }

function Stop-OldProcesses {
    Write-Step "Limpando processos antigos..."
    
    # Para cloudflared
    $cloudflared = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($cloudflared) {
        Stop-Process -Name "cloudflared" -Force -ErrorAction SilentlyContinue
        Write-Info "Cloudflared antigo encerrado"
    }
    
    # Para Node.js na porta 3000
    $nodeProcesses = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | 
                     Select-Object -ExpandProperty OwningProcess -Unique
    
    foreach ($procId in $nodeProcesses) {
        try {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $procId -Force
                Write-Info "Processo na porta $port (PID: $procId) encerrado"
            }
        } catch { }
    }
    
    Write-Ok "Processos antigos limpos"
}

function Start-CloudflareTunnel {
    Write-Step "Iniciando Cloudflare Tunnel..."
    
    if (-not (Test-Path $cloudflaredPath)) {
        throw "cloudflared.exe nao encontrado em: $cloudflaredPath"
    }
    
    # Limpa log antigo
    if (Test-Path $logFile) { Remove-Item $logFile -Force }
    
    # Inicia tunnel em background
    Start-Process -FilePath $cloudflaredPath `
                  -ArgumentList "tunnel --url http://localhost:$port" `
                  -RedirectStandardError $logFile `
                  -WindowStyle Hidden
    
    Write-Info "Tunnel iniciado. Aguardando URL no log..."
    
    # Aguarda URL no log
    $url = $null
    for ($i = 0; $i -lt $maxWaitSeconds; $i++) {
        if (Test-Path $logFile) {
            try {
                Copy-Item $logFile "$logFile.tmp" -Force -ErrorAction SilentlyContinue
                if (Test-Path "$logFile.tmp") {
                    $content = Get-Content "$logFile.tmp" -Raw
                    if ($content -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
                        $url = $matches[0].Trim().Trim('|').Trim()
                        Remove-Item "$logFile.tmp" -ErrorAction SilentlyContinue
                        break
                    }
                    Remove-Item "$logFile.tmp" -ErrorAction SilentlyContinue
                }
            } catch { }
        }
        Start-Sleep -Seconds 1
        Write-Host "." -NoNewline
    }
    
    if (-not $url) {
        throw "`nTimeout: Nao foi possivel obter URL do tunnel. Verifique $logFile"
    }
    
    Write-Host ""
    Write-Ok "Tunnel URL obtida: $url"
    return $url
}

function Update-EnvFile {
    param([string]$TunnelUrl)
    
    Write-Step "Atualizando arquivo .env..."
    
    if (-not (Test-Path $envFile)) {
        throw "Arquivo .env nao encontrado no diretorio atual"
    }
    
    $envContent = Get-Content $envFile
    $newEnvContent = @()
    $webhookKey = "PIXGO_WEBHOOK_URL"
    $found = $false
    
    foreach ($line in $envContent) {
        if ($line -match "^$webhookKey=") {
            $newEnvContent += "$webhookKey=$TunnelUrl"
            $found = $true
        } else {
            $newEnvContent += $line
        }
    }
    
    if (-not $found) {
        $newEnvContent += "$webhookKey=$TunnelUrl"
    }
    
    $newEnvContent | Set-Content $envFile
    Write-Ok "Arquivo .env atualizado com PIXGO_WEBHOOK_URL=$TunnelUrl"

    # Atualizar api_constants.dart do Flutter
    $dartFile = Resolve-Path "..\App-android-web\lib\core\constants\api_constants.dart" -ErrorAction SilentlyContinue
    if ($dartFile) {
        $dartContent = Get-Content $dartFile.Path -Raw
        $dartContent = $dartContent -replace "static const String _tunnelUrl = '.*?';", "static const String _tunnelUrl = '$TunnelUrl';"
        Set-Content -Path $dartFile.Path -Value $dartContent -NoNewline
        Write-Ok "api_constants.dart atualizado com nova URL do tunnel"
    } else {
        Write-Info "api_constants.dart nao encontrado, pulando atualizacao do frontend"
    }
}

function Start-NodeServer {
    Write-Step "Iniciando servidor Node.js..."
    Write-Info "Executando: npm run dev"
    Write-Host ""
    
    # Inicia o servidor (bloqueia aqui)
    cmd /c "npm run dev"
}

function Cleanup {
    Write-Host "`n`nEncerrando backend..." -ForegroundColor Yellow
    Stop-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    Write-Info "Cloudflare Tunnel encerrado"
    Write-Host "Backend encerrado." -ForegroundColor Yellow
    Write-Host "  (PostgreSQL Docker continua rodando. Use 'docker compose down' para parar)" -ForegroundColor Gray
}

function Start-PostgresDocker {
    Write-Step "Verificando PostgreSQL (Docker)..."

    # Verifica se o Docker esta disponivel
    try {
        $dockerVer = docker version --format "{{.Server.Version}}" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "fail" }
    } catch {
        throw "Docker nao encontrado ou nao esta rodando. Inicie o Docker Desktop."
    }

    # Verifica se o container ja esta rodando
    $running = docker ps --filter "name=katari-postgres" --filter "status=running" -q 2>&1
    if ($running) {
        Write-Ok "PostgreSQL ja esta rodando (container katari-postgres)"
    } else {
        Write-Info "Iniciando PostgreSQL via Docker Compose..."
        docker compose up -d postgres 2>&1 | Out-Null
        
        # Aguarda ficar pronto
        Write-Info "Aguardando PostgreSQL ficar pronto..."
        $maxRetries = 30
        for ($i = 0; $i -lt $maxRetries; $i++) {
            try {
                $health = docker inspect --format "{{.State.Health.Status}}" katari-postgres 2>&1
                if ($health -match "healthy") {
                    break
                }
            } catch { }
            Start-Sleep -Seconds 1
            Write-Host "." -NoNewline
        }
        Write-Host ""
        
        # Verifica se subiu
        $finalCheck = docker ps --filter "name=katari-postgres" --filter "status=running" -q 2>&1
        if (-not $finalCheck) {
            throw "Falha ao iniciar PostgreSQL. Execute 'docker compose logs postgres' para ver os erros."
        }
        Write-Ok "PostgreSQL iniciado com sucesso!"
    }

    # Rodar Prisma migrate
    Write-Info "Executando Prisma migrations..."
    try {
        npx prisma migrate deploy 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Migrations aplicadas com sucesso"
        } else {
            Write-Info "Tentando gerar Prisma client..."
            npx prisma generate 2>&1 | Out-Null
            npx prisma db push --accept-data-loss 2>&1 | Out-Null
            Write-Ok "Schema sincronizado via db push"
        }
    } catch {
        Write-Info "Migration falhou, tentando db push..."
        npx prisma db push --accept-data-loss 2>&1 | Out-Null
        Write-Ok "Schema sincronizado via db push"
    }
}

# -- Execucao Principal --

try {
    Write-Banner "KATARI - Backend Server"
    
    # Verificar se esta no diretorio correto
    if (-not (Test-Path "package.json")) {
        Write-Err "Este script deve ser executado no diretorio do servidor Node.js"
        Write-Info "Navegue ate a pasta 'Server para o consorcio' e execute novamente"
        exit 1
    }
    
    # Passo 1: Limpar processos antigos
    Stop-OldProcesses
    
    # Passo 2: Iniciar Cloudflare Tunnel
    $tunnelUrl = Start-CloudflareTunnel
    
    # Passo 3: Atualizar .env
    Update-EnvFile -TunnelUrl $tunnelUrl
    
    # Passo 4: Resultado
    Write-Banner "BACKEND PRONTO!" "Green"
    Write-Host ""
    Write-Host "  Backend URL: $tunnelUrl/admin" -ForegroundColor Cyan
    Write-Host "  Local: http://localhost:$port/admin" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Agora voce pode iniciar o frontend!" -ForegroundColor White
    Write-Banner "" "Green"
    Write-Host ""
    
    # Passo 5: Iniciar PostgreSQL via Docker
    Start-PostgresDocker
    
    # Passo 6: Iniciar servidor Node.js (bloqueia)
    Start-NodeServer
    
} catch {
    Write-Err $_.Exception.Message
    exit 1
    
} finally {
    Cleanup
}