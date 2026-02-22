[CmdletBinding()]
param(
    [string]$ContainerName = "localai-rtx4090",
    [string]$WarmupModel = "eurollm-9b-instruct"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ai-common.ps1"

try {
    Ensure-DockerAvailable

    $baseUrl = Get-LocalAIBaseUrl
    $hostIp = ($baseUrl -replace "^http://", "") -replace ":8080$", ""
    $state = Get-ContainerState -ContainerName $ContainerName

    $ready = $false
    $modelList = @()
    $modelPresent = $false
    $headers = Get-LocalAIHeaders

    try {
        $readyResponse = Invoke-WebRequest -Uri ("{0}/readyz" -f $baseUrl) -Method Get -TimeoutSec 5 -ErrorAction Stop
        $ready = ($readyResponse.StatusCode -eq 200)
    } catch {
        $ready = $false
    }

    if ($ready) {
        try {
            $modelsResponse = Invoke-RestMethod -Uri ("{0}/v1/models" -f $baseUrl) -Method Get -Headers $headers -TimeoutSec 10 -ErrorAction Stop
            if ($modelsResponse.data) {
                $modelList = @($modelsResponse.data | ForEach-Object { $_.id })
                $modelPresent = $modelList -contains $WarmupModel
            }
        } catch {
            $modelList = @()
            $modelPresent = $false
        }
    }

    $checks = @(
        [pscustomobject]@{
            Check  = "Container state"
            Status = if ($state -eq "running") { "OK" } else { "FAIL" }
            Detail = $state
        }
        [pscustomobject]@{
            Check  = "Ready endpoint"
            Status = if ($ready) { "OK" } else { "FAIL" }
            Detail = if ($ready) { "200" } else { "unreachable" }
        }
        [pscustomobject]@{
            Check  = "Warmup model present"
            Status = if ($modelPresent) { "OK" } else { "FAIL" }
            Detail = $WarmupModel
        }
    )

    Write-Host ("Base URL : {0}" -f $baseUrl)
    Write-Host ("Host IP  : {0}" -f $hostIp)
    $checks | Format-Table -AutoSize

    if ($modelList.Count -gt 0) {
        Write-Host ""
        Write-Host ("Models   : {0}" -f ($modelList -join ", "))
    }

    $allOk = ($state -eq "running") -and $ready -and $modelPresent
    if ($allOk) {
        exit 0
    }

    exit 1
} catch {
    Write-ErrLine $_.Exception.Message
    exit 1
}
