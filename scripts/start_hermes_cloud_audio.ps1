param(
    [string]$KeyFile = (Join-Path $env:USERPROFILE ".hermes-cloud-audio\api_key"),
    [string]$AudioBaseUrl = "https://gpt.isoziyuan.com/v1"
)

if (-not $env:HERMES_API_KEY) {
    throw "Set HERMES_API_KEY to Hermes' API_SERVER_KEY before starting."
}
if (-not (Test-Path -LiteralPath $KeyFile)) {
    throw "Cloud audio key file not found: $KeyFile"
}

$env:SUB2API_AUDIO_API_KEY = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
$env:SUB2API_AUDIO_BASE_URL = $AudioBaseUrl
uv run speech-to-speech local --hermes --hermes-cloud-audio
