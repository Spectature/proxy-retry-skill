---
name: proxy-retry
description: Automatically retry failing network commands with a temporary proxy when errors indicate connectivity issues (for npm, git, pnpm, yarn, curl, and similar CLI tools). Use when installs/pushes/downloads fail due to timeout, TLS, connection reset, or proxy-required network errors.
---

# Proxy Retry

Use this skill when a command fails due to network issues and you want a safe fallback retry with a temporary proxy.

## When to Trigger

Use this workflow when commands fail with errors like:

- `Failed to connect`
- `Connection timed out`
- `ECONNRESET`, `ETIMEDOUT`, `ENOTFOUND`, `EAI_AGAIN`
- `TLS handshake timeout`
- `unable to access` (git HTTP/S remote)

Common commands:

- `npm install`, `pnpm install`, `yarn install`
- `git fetch/pull/push/clone`
- `curl`, `Invoke-WebRequest`
- Other CLI commands that depend on external network access

## Core Rules

- Always try the original command once first.
- Only enable proxy retry when failure looks like network/connectivity failure.
- Use temporary proxy settings only; do not persist global config unless user explicitly asks.
- Proxy resolution priority: explicit `-Proxy` argument -> environment proxy -> Windows system proxy -> `http://127.0.0.1:7890`.

## Script

Use bundled script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "npm install"
```

Useful options:

```powershell
# Custom proxy
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "git push origin main" -Proxy "http://127.0.0.1:7890"

# More retry rounds after proxy fallback
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "pnpm install" -MaxProxyRetries 2

# Force proxy retry even if pattern check does not match
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "curl https://example.com" -ForceProxyRetry
```

## Behavior

1. Run command normally.
2. If success, stop.
3. If failed and error matches network patterns (or `-ForceProxyRetry` is set), rerun with temporary proxy env vars.
4. If command is `git`, inject per-command `-c http.proxy=... -c https.proxy=...` for stronger compatibility.
5. Restore environment variables after each proxy attempt.

## Scope

This skill is focused on resilient CLI execution during transient network failures without permanently mutating machine-wide proxy settings.
