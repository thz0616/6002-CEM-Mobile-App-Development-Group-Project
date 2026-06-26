param(
    [string]$HostIp = "10.0.2.2",
    [string]$LlmModel = "gemma4:31b-cloud"
)

$ErrorActionPreference = "Stop"

Write-Host ">>> Ollama host: $HostIp" -ForegroundColor Green
Write-Host ">>> Ollama model: $LlmModel" -ForegroundColor Green

$ProbeHost = if ($HostIp -eq "10.0.2.2") { "127.0.0.1" } else { $HostIp }
$TagsUrl = "http://${ProbeHost}:11434/api/tags"
$GenerateUrl = "http://${ProbeHost}:11434/api/generate"
$IsCloudModel = $LlmModel.EndsWith("-cloud")

try {
    if ($IsCloudModel) {
        $ProbeBody = @{
            model = $LlmModel
            prompt = "Reply with OK only."
            stream = $false
            think = $false
        } | ConvertTo-Json
        $ProbeResponse = Invoke-RestMethod -Uri $GenerateUrl -Method Post -TimeoutSec 20 -ContentType "application/json" -Body $ProbeBody
        if ($ProbeResponse.error) {
            throw "Cloud model probe failed: $($ProbeResponse.error)"
        }
        Write-Host ">>> Ollama connection verified; cloud model is reachable." -ForegroundColor Green
    }
    else {
        $Tags = Invoke-RestMethod -Uri $TagsUrl -Method Get -TimeoutSec 10
        $InstalledModels = @($Tags.models | ForEach-Object { $_.name })
        if ($InstalledModels -notcontains $LlmModel) {
            throw "Model '$LlmModel' is not installed. Installed models: $($InstalledModels -join ', ')"
        }
        Write-Host ">>> Ollama connection verified; model is installed." -ForegroundColor Green
    }
}
catch {
    Write-Error "Cannot use Ollama at $TagsUrl. Start Ollama and verify model '$LlmModel'. Details: $($_.Exception.Message)"
}

Write-Host ">>> Launching Flutter app..." -ForegroundColor Cyan
flutter run --dart-define=HOST_IP=$HostIp --dart-define=LLM_MODEL=$LlmModel
