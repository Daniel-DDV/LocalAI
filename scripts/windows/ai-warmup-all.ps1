[CmdletBinding()]
param(
    [string[]]$ChatModels = @("eurollm-9b-instruct", "qwen2.5-7b-instruct"),
    [string[]]$EmbeddingModels = @("text-embedding-ada-002", "bge-large-en-v1.5"),
    [string]$RerankModel = "jina-reranker-v1-base-en",
    [switch]$IncludeVision,
    [string]$VisionModel = "eurovlm-9b-preview",
    [switch]$IncludeTTS,
    [string]$TTSModel = "tts-1",
    [int]$ReadyTimeoutSeconds = 120,
    [int]$RequestTimeoutSeconds = 240,
    [int]$RetryCount = 1,
    [int]$RetryDelaySeconds = 5
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ai-common.ps1"

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [int]$TimeoutSec = 180
    )

    $json = $Payload | ConvertTo-Json -Depth 10
    return Invoke-RestMethod `
        -Uri $Uri `
        -Method Post `
        -Headers $Headers `
        -ContentType "application/json" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) `
        -TimeoutSec $TimeoutSec `
        -ErrorAction Stop
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$Retries = 1,
        [int]$DelaySeconds = 5
    )

    $attempt = 0
    while ($true) {
        try {
            return & $Action
        } catch {
            if ($attempt -ge $Retries) {
                throw
            }
            Write-WarnLine ("{0} failed ({1}). Retry in {2}s..." -f $Label, $_.Exception.Message, $DelaySeconds)
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][ref]$Collection,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][double]$Seconds,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $Collection.Value.Add([pscustomobject]@{
        Type   = $Type
        Model  = $Model
        Status = $Status
        Sec    = [Math]::Round($Seconds, 2)
        Detail = $Detail
    })
}

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

    Write-Info ("Starting sequential warmup against {0}" -f $baseUrl)
    Write-WarnLine "This may trigger model evictions on limited VRAM. Use ai-warmup.ps1 for single-model warmup."

    $headers = Get-LocalAIHeaders
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($model in $ChatModels) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Info ("Warmup chat model '{0}'..." -f $model)
            $null = Invoke-WithRetry -Label ("chat:{0}" -f $model) -Retries $RetryCount -DelaySeconds $RetryDelaySeconds -Action {
                Invoke-JsonPost -Uri ("{0}/v1/chat/completions" -f $baseUrl) -Headers $headers -TimeoutSec $RequestTimeoutSeconds -Payload @{
                    model       = $model
                    messages    = @(@{ role = "user"; content = "warmup" })
                    max_tokens  = 8
                    temperature = 0
                }
            }
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "chat" -Model $model -Status "OK" -Seconds $sw.Elapsed.TotalSeconds -Detail "warmed"
        } catch {
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "chat" -Model $model -Status "FAIL" -Seconds $sw.Elapsed.TotalSeconds -Detail $_.Exception.Message
        }
    }

    foreach ($model in $EmbeddingModels) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Info ("Warmup embedding model '{0}'..." -f $model)
            $null = Invoke-WithRetry -Label ("embed:{0}" -f $model) -Retries $RetryCount -DelaySeconds $RetryDelaySeconds -Action {
                Invoke-JsonPost -Uri ("{0}/v1/embeddings" -f $baseUrl) -Headers $headers -TimeoutSec $RequestTimeoutSeconds -Payload @{
                    model = $model
                    input = "warmup embedding sentence"
                }
            }
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "embedding" -Model $model -Status "OK" -Seconds $sw.Elapsed.TotalSeconds -Detail "warmed"
        } catch {
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "embedding" -Model $model -Status "FAIL" -Seconds $sw.Elapsed.TotalSeconds -Detail $_.Exception.Message
        }
    }

    if ($RerankModel) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Info ("Warmup rerank model '{0}'..." -f $RerankModel)
            $null = Invoke-WithRetry -Label ("rerank:{0}" -f $RerankModel) -Retries $RetryCount -DelaySeconds $RetryDelaySeconds -Action {
                Invoke-JsonPost -Uri ("{0}/v1/rerank" -f $baseUrl) -Headers $headers -TimeoutSec $RequestTimeoutSeconds -Payload @{
                    model     = $RerankModel
                    query     = "warmup"
                    documents = @("warmup document a", "warmup document b")
                }
            }
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "rerank" -Model $RerankModel -Status "OK" -Seconds $sw.Elapsed.TotalSeconds -Detail "warmed"
        } catch {
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "rerank" -Model $RerankModel -Status "FAIL" -Seconds $sw.Elapsed.TotalSeconds -Detail $_.Exception.Message
        }
    }

    if ($IncludeVision) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Info ("Warmup vision model '{0}' (text-only ping)..." -f $VisionModel)
            $null = Invoke-WithRetry -Label ("vision:{0}" -f $VisionModel) -Retries $RetryCount -DelaySeconds $RetryDelaySeconds -Action {
                Invoke-JsonPost -Uri ("{0}/v1/chat/completions" -f $baseUrl) -Headers $headers -TimeoutSec $RequestTimeoutSeconds -Payload @{
                    model       = $VisionModel
                    messages    = @(@{ role = "user"; content = "warmup" })
                    max_tokens  = 8
                    temperature = 0
                }
            }
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "vision" -Model $VisionModel -Status "OK" -Seconds $sw.Elapsed.TotalSeconds -Detail "warmed"
        } catch {
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "vision" -Model $VisionModel -Status "FAIL" -Seconds $sw.Elapsed.TotalSeconds -Detail $_.Exception.Message
        }
    }

    if ($IncludeTTS) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Info ("Warmup TTS model '{0}'..." -f $TTSModel)
            $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("localai-tts-warmup-{0}.wav" -f ([Guid]::NewGuid().ToString("N")))
            try {
                $null = Invoke-WithRetry -Label ("tts:{0}" -f $TTSModel) -Retries $RetryCount -DelaySeconds $RetryDelaySeconds -Action {
                    $payload = @{
                        model = $TTSModel
                        voice = "alloy"
                        input = "warmup"
                    } | ConvertTo-Json -Depth 6

                    Invoke-WebRequest `
                        -Uri ("{0}/v1/audio/speech" -f $baseUrl) `
                        -Method Post `
                        -Headers $headers `
                        -ContentType "application/json" `
                        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
                        -OutFile $tempOut `
                        -TimeoutSec $RequestTimeoutSeconds `
                        -ErrorAction Stop | Out-Null
                }
            } finally {
                if (Test-Path $tempOut) {
                    Remove-Item $tempOut -Force -ErrorAction SilentlyContinue
                }
            }

            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "tts" -Model $TTSModel -Status "OK" -Seconds $sw.Elapsed.TotalSeconds -Detail "warmed"
        } catch {
            $sw.Stop()
            Add-Result -Collection ([ref]$results) -Type "tts" -Model $TTSModel -Status "FAIL" -Seconds $sw.Elapsed.TotalSeconds -Detail $_.Exception.Message
        }
    }

    Write-Host ""
    $results | Format-Table -AutoSize

    $failCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
    if ($failCount -gt 0) {
        Write-WarnLine ("Warmup completed with {0} failure(s)." -f $failCount)
        exit 1
    }

    Write-Info "Warmup completed successfully."
    exit 0
} catch {
    Write-ErrLine $_.Exception.Message
    exit 1
}
