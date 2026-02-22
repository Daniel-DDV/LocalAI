# Claude Code on Ubuntu with LocalAI over LAN

Date: 2026-02-22

This document is for running Claude Code (CC) on Ubuntu while using your Windows-hosted LocalAI service as backend AI.

## 1) Current service target

- LocalAI base URL: `http://192.168.2.57:8080`
- Chat UI: `http://192.168.2.57:8080/chat`
- Swagger UI: `http://192.168.2.57:8080/swagger/index.html`
- Health: `GET /readyz`
- Model list: `GET /v1/models`

Set environment on Ubuntu:

```bash
export LOCALAI_BASE_URL="http://192.168.2.57:8080"
# only if API key enforcement is enabled later:
export LOCALAI_API_KEY=""
```

## 2) Can Claude Code poll the service?

Yes. It should.

Recommended probe sequence before heavy work:
1. `GET /readyz` with short timeout
2. `GET /v1/models` and verify required model IDs
3. Run one small warmup request for the chosen model

Example:

```bash
curl -i --connect-timeout 3 --max-time 15 "$LOCALAI_BASE_URL/readyz"
curl -s --connect-timeout 3 --max-time 20 "$LOCALAI_BASE_URL/v1/models" | jq '.data[].id'
```

## 3) API endpoints to use

## Core
- `GET /readyz`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/embeddings`
- `POST /v1/rerank`

## Optional/available in this deployment
- `POST /v1/responses`
- `POST /v1/audio/speech`
- `POST /v1/audio/transcriptions`
- `POST /v1/images/generations`
- `POST /v1/images/inpainting`

## 4) Endpoint examples

## Chat
```bash
curl -s --connect-timeout 5 --max-time 180 "$LOCALAI_BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"eurollm-9b-instruct","messages":[{"role":"user","content":"Geef een korte testzin."}],"max_tokens":128}' \
| jq -r '.choices[0].message.content // .error.message // "<no content>"'
```

## Embeddings
```bash
curl -s --connect-timeout 5 --max-time 300 "$LOCALAI_BASE_URL/v1/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-ada-002","input":"Dit is een testzin."}' \
| jq '.data[0].embedding | length'
```

## Rerank
```bash
curl -s --connect-timeout 5 --max-time 180 "$LOCALAI_BASE_URL/v1/rerank" \
  -H "Content-Type: application/json" \
  -d '{"model":"jina-reranker-v1-base-en","query":"beste optie","documents":["optie a","optie b","optie c"]}' \
| jq
```

## 5) Cold-start, VRAM, and timeouts

Expected behavior with big models:
- first request can be slow (30-120s, sometimes more)
- first request can fail once during load
- immediate retry often succeeds

Practical rules for CC on Ubuntu:
1. avoid parallel cold starts for different big models
2. use longer total timeout (`--max-time 180` to `300`)
3. retry once on timeout/500
4. prefer one primary model per session for stability

## 6) Gaming impact and operator workflow

When gaming on the Windows host, LocalAI should usually be stopped to free VRAM.

## Before gaming (Windows)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\LocalAI\scripts\windows\ai-off.ps1
```

## After gaming (Windows)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\LocalAI\scripts\windows\ai-on.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\LocalAI\scripts\windows\ai-warmup.ps1
# or full stack warmup:
powershell -NoProfile -ExecutionPolicy Bypass -File D:\LocalAI\scripts\windows\ai-warmup-all.ps1
```

Then re-check from Ubuntu:

```bash
curl -i --connect-timeout 3 --max-time 15 "$LOCALAI_BASE_URL/readyz"
curl -s --connect-timeout 3 --max-time 20 "$LOCALAI_BASE_URL/v1/models" | jq '.data[].id'
```

## 7) Edge-case matrix

`curl: (28) timeout reached`
- cause: cold model load or network stall
- action: retry once with higher `--max-time`; if persistent, switch to already-warm model

`URL rejected: No host part in the URL`
- cause: empty/malformed `$LOCALAI_BASE_URL`
- action: `echo "$LOCALAI_BASE_URL"` and export again

`200` from `/readyz` but inference times out
- cause: service alive, target model/backend still cold or evicted
- action: do a minimal warmup request first

`404` endpoint not found
- cause: typo/broken URL path
- action: re-check exact endpoint path

`500` from chat/embeddings
- cause: backend load failure or model config mismatch
- action: inspect host-side LocalAI logs and retry after warmup

## 8) Should we use Swagger here?

Yes, for API discoverability and operator onboarding:
- use Swagger UI: `http://192.168.2.57:8080/swagger/index.html`
- use it to inspect request/response shapes quickly

But do not rely only on Swagger for runtime capability decisions:
- model availability is dynamic in this setup
- always check `/v1/models` at runtime before selecting a model

Recommended policy:
1. Swagger for interface reference
2. `/v1/models` + probe calls for runtime truth

## 9) Minimal CC operating checklist

1. Check `/readyz`
2. Check `/v1/models`
3. Select one primary model for this run
4. Warm that model with a tiny request
5. Run workload with conservative concurrency
6. On timeout: single retry, then fallback model
