# proxy-retry-skill

A Codex skill for resilient CLI execution when network issues break downloads or pushes.

中文说明: [README.zh-CN.md](README.zh-CN.md)

## What it does

- Runs your command once without proxy.
- If it fails with network-like errors, retries with a temporary proxy.
- Proxy resolution priority: explicit `-Proxy` argument -> environment proxy -> Windows system proxy -> `http://127.0.0.1:7890`.
- Does not persist global proxy settings.
- Supports npm/pnpm/yarn/git/curl and other networked CLIs.

## Skill files

- `SKILL.md` - skill behavior and usage
- `scripts/invoke_with_proxy_retry.ps1` - retry runner
- `agents/openai.yaml` - metadata
- `LICENSE` - MIT

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "npm install"
```

By default it auto-detects proxy from system settings (no extra argument required).

Custom proxy:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "git push origin main" -Proxy "http://127.0.0.1:7890"
```

Force proxy retry even when pattern detection is uncertain:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "curl https://example.com" -ForceProxyRetry
```

## License

MIT
