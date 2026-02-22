# LocalAI + EuroLLM (via Ollama GGUF) + LAN Runbook

## Scope
- LocalAI draait in Docker op deze host.
- Web UI en OpenAI-compatible API zijn actief op poort `8080`.
- `eurollm-9b-instruct` draait nu via lokale Ollama GGUF + `llama-cpp` backend.
- `eurovlm-9b-preview` blijft beschikbaar via `vllm`.

## Current host and access
- Host LAN IP: `192.168.2.57`
- UI: `http://192.168.2.57:8080/chat`
- Models endpoint: `http://192.168.2.57:8080/v1/models`
- Container name: `localai-rtx4090`

## What was changed

### 1) Chat UI hardening for 2048 context windows
- File: `core/http/static/chat.js`
- Added:
- aggressive message/context trimming before request
- prompt budget logic for 2048-token model windows
- multimodal throttling (limited retained media context)
- dynamic `max_tokens` cap based on remaining budget
- status message when context is trimmed
- Result: voorkomt `decoder prompt > max_model_len` fouten in de UI flow.

### 2) Docker compose env passthrough for HF tokens
- File: `docker-compose.rtx4090.yml`
- Added env mapping:
- `HF_TOKEN=${HF_TOKEN}`
- `HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_HUB_TOKEN}`
- `HUGGINGFACE_HUB_TOKEN=${HUGGINGFACE_HUB_TOKEN}`
- Purpose: gated HF repos kunnen werken als token toegang heeft.

### 3) EuroLLM switched from gated HF vLLM source to local GGUF source
- File: `models/eurollm-9b-instruct.yaml`
- Changed from `backend: vllm` + HF model id to:
- `backend: llama-cpp`
- local model file `eurollm-9b-instruct.ollama.gguf`
- context tuned for stable local usage
- chat template via tokenizer template (`use_jinja:true`, stopwords for ChatML markers)

### 4) Ollama model copied into LocalAI models path
- Source:
- `C:\Users\DDVer\.ollama\models\blobs\sha256-785a3b2883532381704ef74f866f822f179a931801d1ed1cf12e6deeb838806b`
- Destination:
- `D:\LocalAI\models\eurollm-9b-instruct.ollama.gguf`

### 5) Installed missing backend in running container
- Installed backend:
- `localai@cuda12-llama-cpp`
- Installed path in container:
- `/backends/cuda12-llama-cpp/run.sh`
- Container restarted after install.

## Why this path was needed
- HF repo `utter-project/EuroLLM-9B-Instruct` is gated and returned `403` with provided token.
- The local Ollama blob is valid GGUF and works with `llama-cpp`.
- Therefore LocalAI was configured to use the local GGUF file directly.

## Validation results
- `/v1/models` includes:
- `eurollm-9b-instruct`
- `eurovlm-9b-preview`
- `jina-reranker-v1-base-en`
- etc.
- Chat completion test succeeded:
- `model: eurollm-9b-instruct`
- HTTP `200`
- Returned assistant text.
- LAN call from PowerShell on client succeeded and returned content.

## LAN PowerShell commands

### Read models
```powershell
$ip='192.168.2.57'; Invoke-RestMethod -Uri ("http://{0}:8080/v1/models" -f $ip) -Method Get
```

### Chat completion (stable form)
```powershell
$ip='192.168.2.57'; $url=("http://{0}:8080/v1/chat/completions" -f $ip); $body=@{model='eurollm-9b-instruct';messages=@(@{role='user';content='Geef een korte testzin.'});max_tokens=128} | ConvertTo-Json -Depth 8; (Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))).choices[0].message.content
```

## Known first-request behavior
- First request after backend/model cold start can be slow.
- One initial request can timeout/cancel while model/tensors are initializing.
- Retrying immediately after warmup generally succeeds.
- This is expected with large models and backend cold loads.

## API key status (current)
- No active API key enforcement was detected in container env.
- Calls currently work without `Authorization: Bearer ...`.
- If key enforcement is enabled later, add:
- `-Headers @{ Authorization = 'Bearer <KEY>' }` to `Invoke-RestMethod`.

## Ubuntu LAN diagnostics (no response case)
- If `curl -s ... | jq ...` returns nothing or appears to hang, remove `-s` and add explicit timeouts first.
- Use this exact sequence from Ubuntu:

```bash
IP=192.168.2.57
curl -v --connect-timeout 3 --max-time 15 "http://${IP}:8080/readyz"
curl -v --connect-timeout 3 --max-time 20 "http://${IP}:8080/v1/models"
curl -v --connect-timeout 5 --max-time 180 "http://${IP}:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"eurollm-9b-instruct","messages":[{"role":"user","content":"Geef een korte testzin."}],"max_tokens":128}'
```

- Then (only after the raw chat call works), pipe to `jq`:

```bash
curl --connect-timeout 5 --max-time 180 -s "http://${IP}:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"eurollm-9b-instruct","messages":[{"role":"user","content":"Geef een korte testzin."}],"max_tokens":128}' \
| jq -r '.choices[0].message.content // .error.message // "<no content>"'
```

- Interpretation:
- timeout before headers: network path/firewall problem
- HTTP `200` with empty `choices[0].message.content`: inspect full JSON, then model/backend logs
- HTTP `500`: model/backend load error (see `docker logs`)

## Windows host firewall/admin notes
- Docker publishes `0.0.0.0:8080->8080/tcp` and host-local LAN-IP checks succeeded.
- In this session, firewall write operations returned `Access is denied` (non-admin shell), so firewall changes must be done in elevated PowerShell.
- Minimal rule (run as Administrator):

```powershell
New-NetFirewallRule -DisplayName "LocalAI 8080 LAN" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -Profile Private
```

- Verify rule (Administrator):

```powershell
Get-NetFirewallRule -DisplayName "LocalAI 8080 LAN" | Format-Table DisplayName,Enabled,Direction,Action,Profile -AutoSize
```

## Troubleshooting quick notes
- `404 Resource not found` on chat endpoint:
- URL accidentally broken over two lines (`/v1/chat/` + newline + `completions`).
- `Invalid URI: http:///...` in PowerShell:
- string interpolation issue with `"$ip:8080"`; use format string `("http://{0}:8080/..." -f $ip)` or `${ip}`.
- Ubuntu `curl -s ... | jq ...` shows no output:
- `-s` hides connect/protocol errors and `jq` may emit nothing when response is not chat JSON; first test with `curl -v` and timeouts.
- `backend not found: llama-cpp`:
- `llama-cpp` backend not installed in container. Install backend and restart.
- HF `403 gated repo`:
- token/account has no access to gated model. Use local GGUF route or request access.

## Operational checklist
- Check health:
- `http://192.168.2.57:8080/readyz`
- Check model list:
- `http://192.168.2.57:8080/v1/models`
- Test one prompt in UI:
- `http://192.168.2.57:8080/chat`
- If first prompt hangs:
- retry once after 30-120s warmup.
