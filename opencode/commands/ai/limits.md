---
description: Show real Claude Code and Codex limits from native CLI screens
agent: build
model: anthropic/claude-haiku-4-5
allowed-tools: Bash
---

Check the real current Claude Code and Codex limits.

Use the `bash` tool to run:

```bash
$HOME/.config/opencode/ai-limits.py --json
```

Then return a compact summary with:
- Claude session left and reset
- Claude weekly left and reset
- Claude secondary weekly bucket if present
- Codex 5h limit left and reset
- Codex weekly limit left and reset

Rules:
- Use the native CLI-derived output from `$HOME/.config/opencode/ai-limits.py --json`
- Do not use `opencode stats` or any wrapper/proxy usage stats
- If the script fails, show the key error and stop
