Set-StrictMode -Version Latest

$script:LocalAIContainerName = "localai-rtx4090"
$script:DefaultWarmupModel = "eurollm-9b-instruct"
$script:DefaultPort = 8080

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Ensure-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI not found in PATH."
    }

    & docker version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon is not reachable. Start Docker Desktop first."
    }
}

function Get-ContainerState {
    param(
        [string]$ContainerName = $script:LocalAIContainerName
    )

    $state = & docker inspect -f "{{.State.Status}}" $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0) {
        return "missing"
    }

    if (-not $state) {
        return "unknown"
    }

    return ($state | Select-Object -First 1).Trim()
}

function Get-LocalAILanIPv4 {
    $all = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.AddressState -eq "Preferred"
        }

    if (-not $all) {
        return "127.0.0.1"
    }

    $private = $all | Where-Object {
        $_.IPAddress -like "192.168.*" -or
        $_.IPAddress -like "10.*" -or
        $_.IPAddress -match "^172\.(1[6-9]|2[0-9]|3[0-1])\."
    }

    $picked = $null
    if ($private) {
        $picked = $private | Sort-Object -Property InterfaceMetric | Select-Object -First 1
    } else {
        $picked = $all | Sort-Object -Property InterfaceMetric | Select-Object -First 1
    }

    if ($picked -and $picked.IPAddress) {
        return $picked.IPAddress
    }

    return "127.0.0.1"
}

function Get-LocalAIBaseUrl {
    param(
        [string]$Host,
        [int]$Port = $script:DefaultPort
    )

    $resolvedHost = $Host
    if (-not $resolvedHost) {
        $resolvedHost = $env:LOCALAI_HOST
    }
    if (-not $resolvedHost) {
        $resolvedHost = Get-LocalAILanIPv4
    }

    return ("http://{0}:{1}" -f $resolvedHost, $Port)
}

function Get-LocalAIHeaders {
    $headers = @{}
    if ($env:LOCALAI_API_KEY) {
        $headers["Authorization"] = ("Bearer {0}" -f $env:LOCALAI_API_KEY)
    }
    return $headers
}

function Test-LocalAIReady {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl
    )

    try {
        $response = Invoke-WebRequest -Uri ("{0}/readyz" -f $BaseUrl) -Method Get -TimeoutSec 5 -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Invoke-LocalAIReadyWait {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$TimeoutSeconds = 120,
        [int]$PollIntervalSeconds = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-LocalAIReady -BaseUrl $BaseUrl) {
            return $true
        }
        Start-Sleep -Seconds $PollIntervalSeconds
    }

    return $false
}
