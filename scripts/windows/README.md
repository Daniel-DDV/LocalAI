# Windows quick buttons for LocalAI (Game Mode / AI Mode)

This folder provides one-click PowerShell scripts to control the LocalAI Docker container:

- `ai-off.ps1`: stop LocalAI and free VRAM for gaming
- `ai-on.ps1`: start LocalAI and wait until `readyz` is up
- `ai-warmup.ps1`: load the default chat model into memory
- `ai-warmup-all.ps1`: sequentially warm chat + embedding + rerank (optional vision/TTS)
- `ai-status.ps1`: show health and model availability

Default assumptions:
- container name: `localai-rtx4090`
- warmup model: `eurollm-9b-instruct`
- host base URL: auto-detected LAN IP on port `8080`

## 1) One-time prerequisites

Run in PowerShell (current user scope):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Keep Docker Desktop running when using the scripts.

## 2) Direct usage

From repo root (`D:\LocalAI`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-off.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-on.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-warmup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-warmup-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-status.ps1
```

Optional custom model for warmup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-warmup.ps1 -Model qwen2.5-7b-instruct
```

Optional extended warmup:

```powershell
# include vision and tts ping too
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-warmup-all.ps1 -IncludeVision -IncludeTTS
```

## 3) Desktop button setup

Create 4 desktop shortcuts manually.

For each shortcut:
1. Right-click desktop -> `New` -> `Shortcut`
2. Use one of these targets (adjust path if repo location differs):

`AI OFF (Gaming)`:
```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\LocalAI\scripts\windows\ai-off.ps1"
```

`AI ON`:
```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\LocalAI\scripts\windows\ai-on.ps1"
```

`AI Warmup`:
```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\LocalAI\scripts\windows\ai-warmup.ps1"
```

`AI Warmup All`:
```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\LocalAI\scripts\windows\ai-warmup-all.ps1"
```

`AI Status`:
```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\LocalAI\scripts\windows\ai-status.ps1"
```

After creation, right-click shortcut -> `Pin to Start` and/or `Pin to taskbar`.

## 4) Typical workflow

Before gaming:
1. Click `AI OFF (Gaming)`
2. Optional: run `nvidia-smi` to confirm VRAM release

After gaming:
1. Click `AI ON`
2. Click `AI Warmup` (or `AI Warmup All` if you need embeddings/rerank immediately)
3. Optional: click `AI Status`

## 5) Optional env overrides

Use environment variables if needed:

- `LOCALAI_HOST`: force specific host/IP (instead of auto-detect)
- `LOCALAI_API_KEY`: send `Authorization: Bearer <key>` for protected setups

Example:

```powershell
$env:LOCALAI_HOST = "192.168.2.57"
$env:LOCALAI_API_KEY = "your-key-here"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\ai-status.ps1
```

## 6) Troubleshooting

- Error `Docker CLI not found in PATH`:
  - Docker Desktop/CLI not installed or PATH not loaded in session.
- Error `Docker daemon is not reachable`:
  - start Docker Desktop first.
- Status shows ready `FAIL`:
  - run `ai-on.ps1` and check firewall/network config.
- Warmup fails for model:
  - verify with `/v1/models` and use existing model id.
- `ai-warmup-all.ps1` has partial failures:
  - expected on limited VRAM; warm only the model(s) you need for this session.
