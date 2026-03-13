---
name: cleanup-opencode-orphans
description: Inspect and clean orphaned OpenCode main processes that were left behind after terminal or app exit.
compatibility: opencode
metadata:
  category: maintenance
  scope: local-machine
---

## What I do

- Find orphaned OpenCode main processes on the local machine.
- Report the exact PIDs before making changes.
- Clean only processes that match the safe orphan rule.
- Verify the result after cleanup.

## Safe orphan rule

Treat a process as an orphaned OpenCode process only when all of the following are true:

- The process parent PID (`PPID`) is `1`.
- The command line points to an `opencode` executable path.
- The command is the main `opencode` binary, not `opencode run ...`, not `opencode serve ...`, and not another unrelated process that merely contains the word `opencode`.

Use this inspection command:

```bash
ps -eo pid,ppid,lstart,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print}'
```

Use this PID-only command when cleanup is explicitly requested:

```bash
ps -eo pid,ppid,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print $1}'
```

## How to work

1. Run the inspection command and show the matching processes.
2. If the user asked to clean them, collect the PIDs from the PID-only command.
3. If the PID list is empty, say that there is nothing to clean.
4. If the PID list is non-empty, terminate them with `kill`.
5. Re-run the inspection command and report what remains.

Cleanup command:

```bash
ps -eo pid,ppid,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print $1}' | xargs kill
```

Verification command:

```bash
ps -eo pid,ppid,lstart,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print}'
```

## Safety notes

- Do not kill any OpenCode process whose `PPID` is not `1`.
- Do not use `kill -9` unless the user explicitly asks for a force kill after normal termination fails.
- Do not assume that every process containing the word `opencode` is safe to terminate.
- If a current OpenCode session is active, it should normally not match this orphan rule.

## When to use me

Use this when OpenCode has leaked background processes after terminal close, app close, disconnect, or session crashes, and the machine feels slow because of accumulated orphaned OpenCode processes.
