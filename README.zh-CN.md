# proxy-retry-skill

英文说明: [README.md](README.md)

这是一个给 Codex 使用的技能，用来在命令行网络请求失败时自动回退到“临时代理重试”，减少 `npm install`、`git push`、`curl` 等命令因网络问题失败的情况。

## 主要能力

- 先按原始命令执行一次（不走代理）
- 如果报错符合网络连通性失败特征，则自动用临时代理重试
- 代理选择优先级：
  `-Proxy` 显式参数 -> 环境变量代理 -> Windows 系统代理 -> `http://127.0.0.1:7890`
- 不会写入系统级永久代理配置（仅当前进程临时生效）
- 适用于 `npm/pnpm/yarn/git/curl` 等常见命令

## 目录结构

- `SKILL.md`：技能触发条件与使用规则
- `scripts/invoke_with_proxy_retry.ps1`：核心重试脚本
- `agents/openai.yaml`：技能元信息
- `LICENSE`：MIT 协议

## 使用示例

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "npm install"
```

默认会自动读取系统代理，不需要额外参数。

手动指定代理地址：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "git push origin main" -Proxy "http://127.0.0.1:7890"
```

强制进行代理重试（即使未命中内置网络错误模式）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/invoke_with_proxy_retry.ps1 -Command "curl https://example.com" -ForceProxyRetry
```

## License

MIT
