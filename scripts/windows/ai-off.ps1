[CmdletBinding()]
param(
    [string]$ContainerName = "localai-rtx4090"
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
        Write-WarnLine ("Container '{0}' is already '{1}'." -f $ContainerName, $state)
        exit 0
    }

    Write-Info ("Stopping container '{0}'..." -f $ContainerName)
    & docker stop $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("Failed to stop container '{0}'." -f $ContainerName)
    }

    Write-Info ("Container '{0}' stopped. VRAM should now be available for games." -f $ContainerName)
    exit 0
} catch {
    Write-ErrLine $_.Exception.Message
    exit 1
}
