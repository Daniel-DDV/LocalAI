# LocalAI Full Handover (LAN + UI + Models)

Date: 2026-02-22  
Host: Windows machine (`192.168.2.57`)  
Primary runtime: Docker container `localai-rtx4090` on port `8080`

## 1. Executive summary

LocalAI is operational in Docker, reachable from LAN, and verified from:
- local host (Windows)
- remote Ubuntu server on same network

Validated working:
- UI: `http://192.168.2.57:8080/chat`
- health: `GET /readyz`
- model list: `GET /v1/models`
- chat completions: `POST /v1/chat/completions` with `eurollm-9b-instruct`

Main root cause for Ubuntu timeouts was Windows firewall inbound policy on `Private` profile. This is now fixed with an explicit allow rule for TCP `8080`.

## 2. Final runtime state

## Container inventory (intended state)
- `localai-rtx4090` (healthy)
- Port mapping: `0.0.0.0:8080->8080/tcp` and `[::]:8080->8080/tcp`

No extra LocalAI runtime containers are required for normal operation.

## Active models (from `/v1/models`)
- `eurollm-9b-instruct`
- `eurovlm-9b-preview`
- `qwen2.5-7b-instruct`
- `bge-large-en-v1.5`
- `jina-reranker-v1-base-en`
- `text-embedding-ada-002`
- `tts-1`

## 3. What was changed

## 3.1 UI robustness for small context windows
File changed:
- `core/http/static/chat.js`

Changes made:
- aggressive context trimming before request
- token-budget guardrails for ~2048 context behavior
- cap of outgoing `max_tokens` based on remaining budget
- reduced retained media context to avoid oversized multimodal prompts
- user-visible status when context is trimmed

Reason:
- prevent prompt overflow and first-turn failures caused by oversized chat history/context.

## 3.2 Docker compose HF token passthrough
File changed:
- `docker-compose.rtx4090.yml`

Env passthrough added:
- `HF_TOKEN=${HF_TOKEN}`
- `HUGGINGFACE_HUB_TOKEN=${HUGGINGFACE_HUB_TOKEN}`
- `HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_HUB_TOKEN}`

Reason:
- allow gated/private HF access when account has permissions.

## 3.3 EuroLLM switched to local GGUF + llama-cpp
File changed:
- `models/eurollm-9b-instruct.yaml`

Change:
- moved from gated HF direct route to local GGUF with `llama-cpp` backend
- wired chat template/stopwords for stable chat behavior

Reason:
- HF gated access returned `403`; local Ollama GGUF was available and valid.

## 3.4 Model file import from local Ollama store
Model copied:
- source: local Ollama blob store on host
- destination: `D:\LocalAI\models\eurollm-9b-instruct.ollama.gguf`

Reason:
- use existing locally available model instead of blocked remote pull.

## 3.5 Missing backend installed in container
Installed backend:
- `localai@cuda12-llama-cpp`

Reason:
- required to serve local GGUF model through LocalAI.

## 3.6 LAN firewall fix (critical)
Windows rule created (Administrator PowerShell):
- display name: `LocalAI 8080 LAN (Private)`
- direction: inbound
- action: allow
- protocol: TCP
- local port: `8080`
- profile: `Private`
- remote address: `192.168.2.0/24`

Reason:
- Ubuntu server had hard connection timeouts to `192.168.2.57:8080`.

## 4. Root-cause timeline

## Symptom A: “No model loaded / cannot select model in UI”
Contributors:
- model/backend mismatch
- missing backend for GGUF path
- gated HF access for EuroLLM source

Resolution:
- install `cuda12-llama-cpp`
- point `eurollm-9b-instruct` to local GGUF
- keep model visible in `/v1/models`

## Symptom B: API gave `404` in PowerShell
Cause:
- endpoint string broken across lines (`/v1/chat/` + newline + `completions`)

Resolution:
- use one-line URL construction.

## Symptom C: PowerShell invalid URI (`http:///v1/...`)
Cause:
- malformed interpolation in string expression

Resolution:
- use format string:
`("http://{0}:8080/v1/chat/completions" -f $ip)`

## Symptom D: Ubuntu got no output / no response
Cause:
- `curl -s` hid errors
- actual issue was TCP connect timeout (traffic not reaching service)
- Windows firewall on `Private` profile blocked/omitted path for that flow

Resolution:
- add explicit inbound allow rule for `TCP 8080` on `Private`
- validate with `curl -v` from Ubuntu

## 5. Verified evidence

## From Ubuntu (remote host)
Successful checks:
- `GET /readyz` -> `HTTP/1.1 200 OK`
- `GET /v1/models` -> `HTTP/1.1 200 OK` + expected model list
- `POST /v1/chat/completions` -> assistant text returned:
  - example: `De zon schijnt fel vandaag, en de vogels zingen vrolijk in de bomen.`

## From Windows host
- container healthy on mapped `8080`
- local calls to `/v1/models` succeed

Conclusion:
- end-to-end LAN path is functional now.

## 6. First-message behavior when model is loading

Cold-start behavior is expected for large models:
- first request after idle/restart can be slow
- first request can fail/time out in rare cases while backend/model initializes
- immediate retry usually succeeds after warm-up

Recommended UX policy in UI/API clients:
- show status text:
  - `Model wordt geladen, eerste antwoord kan 30-120 seconden duren.`
- use longer timeout for first request (`120-180s`)
- on timeout/500 during first load:
  - auto-retry once after short delay (3-5s)
- keep spinner/progress visible and avoid duplicate parallel warm-up requests

## 7. Operational commands

## 7.1 Quick health (Windows or LAN)
```powershell
$ip='192.168.2.57'
Invoke-RestMethod -Uri ("http://{0}:8080/readyz" -f $ip) -Method Get
Invoke-RestMethod -Uri ("http://{0}:8080/v1/models" -f $ip) -Method Get
```

## 7.2 PowerShell single-line chat test (LAN)
```powershell
$ip='192.168.2.57'; $url=("http://{0}:8080/v1/chat/completions" -f $ip); $body=@{model='eurollm-9b-instruct';messages=@(@{role='user';content='Geef een korte testzin.'});max_tokens=128} | ConvertTo-Json -Depth 8; (Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))).choices[0].message.content
```

## 7.3 Linux/Ubuntu chat test (LAN)
```bash
IP=192.168.2.57
curl --connect-timeout 5 --max-time 180 -s "http://${IP}:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"eurollm-9b-instruct","messages":[{"role":"user","content":"Geef een korte testzin."}],"max_tokens":128}' \
| jq -r '.choices[0].message.content // .error.message // "<no content>"'
```

## 7.4 Ubuntu diagnostic mode (if issues)
```bash
IP=192.168.2.57
curl -v --connect-timeout 3 --max-time 15 "http://${IP}:8080/readyz"
curl -v --connect-timeout 3 --max-time 20 "http://${IP}:8080/v1/models"
curl -v --connect-timeout 5 --max-time 180 "http://${IP}:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"eurollm-9b-instruct","messages":[{"role":"user","content":"Geef een korte testzin."}],"max_tokens":128}'
```

## 7.5 Firewall verification (Windows Admin PowerShell)
```powershell
Get-NetFirewallRule -DisplayName "LocalAI 8080 LAN (Private)" | Format-Table DisplayName,Enabled,Direction,Action,Profile -AutoSize
```

## 8. Security notes

- Do not store raw HF access tokens in docs, logs, or committed files.
- If a token was shared in plain text during ops/debugging, rotate it in Hugging Face account settings.
- Current LocalAI runtime does not enforce API key by default in this setup.
- If API key enforcement is later enabled, clients must send:
  - `Authorization: Bearer <KEY>`

## 9. Known limitations

- Large models can have high cold-start latency.
- First-call timeout risk remains if client timeout is too short.
- LAN access depends on Windows network profile/rules; profile changes (Private/Public) can affect reachability.

## 10. Recommended steady-state policy

- Keep exactly one production LocalAI container for this host/profile.
- Keep explicit firewall rule for `TCP 8080` on `Private`.
- Use timeout-aware clients (`connect-timeout` + total timeout).
- For first-user-message UX, always show warm-up notice and single automatic retry.
- Keep `LOCALAI_EUROLLM_LAN_RUNBOOK.md` and this file aligned after operational changes.
