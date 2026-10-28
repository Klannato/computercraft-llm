# Handoff: ComputerCraft LLM chat (Hermes-style)

## What this is
Hermes-style chat client for ComputerCraft (terminal computer -> turtle via rednet).
Keeps multi-turn conversation, calls an OpenAI-compatible LLM (OpenRouter default),
optionally executes ```lua blocks on a connected turtle.

Files:
- cc_hermes_chat.lua — chat client (runs on a regular computer, not a turtle)
- cc_turtle_server.lua — turtle-side server (executes received code)

## Current issue: "LLM error: Unauthorized" (401)
- http.post now works (allowlist fixed: localhost + openrouter.ai allow rules in computercraft-server.toml).
- Direct test: `http.post(...)` returns `resp=nil err="Unauthorized"`.
- Suspected cause: API key not reaching the request, OR key invalid.
- Script auto-loads key from `apikey.txt` on the computer's disk into settings (`hermes.api_key`) if settings empty, and prints `API key loaded: sk-or-v1-...` or `NONE`.
- User has not yet confirmed which message prints after reboot.

## Next steps
1. Reboot in-game computer; run `cc_hermes_chat`; note "API key loaded: ..." line.
   - If NONE → wrong computer ID folder (try 0/1/2) or apikey.txt not present.
   - If a key shows but still 401 → regenerate key at openrouter.ai/keys; replace in apikey.txt and .settings.
2. Also verify settings via `get hermes.api_key` in-game.
3. Test direct http.post with the key in Authorization header.

## Config
- Server: /home/geo/mc-server/create-custom (Fabric, CC:Restitched)
- Allowlist: localhost, 127.0.0.1, openrouter.ai all allow; $private deny (localhost already allowed above).
- Restart server after config edits (done).

## Environment
- GitHub: Klannato
- No git repo previously; created this repo for handoff.
