[CmdletBinding()]
param(
    [string]$ContainerName = "localai-rtx4090",
    [int]$ReadyTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ai-common.ps1"

try {
    Ensure-DockerAvailable

    $state = Get-ContainerState -ContainerName $ContainerName
    if ($state -eq "missing") {
        throw ("Container '{0}' was not found." -f $ContainerName)
    }

    if ($state -ne "running") {
        Write-Info ("Starting container '{0}'..." -f $ContainerName)
        & docker start $ContainerName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw ("Failed to start container '{0}'." -f $ContainerName)
        }
    } else {
        Write-WarnLine ("Container '{0}' is already running." -f $ContainerName)
    }

    $baseUrl = Get-LocalAIBaseUrl
    Write-Info ("Waiting for LocalAI readiness: {0}/readyz" -f $baseUrl)

    if (-not (Invoke-LocalAIReadyWait -BaseUrl $baseUrl -TimeoutSeconds $ReadyTimeoutSeconds)) {
        throw ("LocalAI did not become ready within {0}s." -f $ReadyTimeoutSeconds)
    }

    Write-Info ("LocalAI is ready at {0}" -f $baseUrl)
    exit 0
} catch {
    Write-ErrLine $_.Exception.Message
    exit 1
}
