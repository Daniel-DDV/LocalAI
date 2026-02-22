[CmdletBinding()]
param(
    [string]$Model = "eurollm-9b-instruct",
    [int]$MaxTokens = 8,
    [int]$ReadyTimeoutSeconds = 120,
    [int]$RequestTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ai-common.ps1"

try {
    Ensure-DockerAvailable

    $state = Get-ContainerState -ContainerName $script:LocalAIContainerName
    if ($state -ne "running") {
        throw ("Container '{0}' is not running. Run ai-on.ps1 first." -f $script:LocalAIContainerName)
    }

    $baseUrl = Get-LocalAIBaseUrl
    if (-not (Invoke-LocalAIReadyWait -BaseUrl $baseUrl -TimeoutSeconds $ReadyTimeoutSeconds)) {
        throw ("LocalAI did not become ready within {0}s." -f $ReadyTimeoutSeconds)
    }

    $headers = Get-LocalAIHeaders
    $payload = @{
        model       = $Model
        messages    = @(
            @{
                role    = "user"
                content = "warmup"
            }
        )
        max_tokens  = $MaxTokens
        temperature = 0
    } | ConvertTo-Json -Depth 8

    Write-Info ("Warming model '{0}'..." -f $Model)

    $response = Invoke-RestMethod `
        -Uri ("{0}/v1/chat/completions" -f $baseUrl) `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
        -TimeoutSec $RequestTimeoutSeconds `
        -ErrorAction Stop

    $content = $null
    if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message) {
        $content = $response.choices[0].message.content
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-WarnLine "Warmup request succeeded but returned empty content."
    } else {
        Write-Info ("Warmup successful. Sample output: {0}" -f $content.Trim())
    }

    exit 0
} catch {
    Write-ErrLine $_.Exception.Message
    exit 1
}
