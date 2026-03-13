---
description: Clean orphaned OpenCode main processes left behind after terminal or app exit
agent: build
---
Current orphaned OpenCode main processes:
!`ps -eo pid,ppid,lstart,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print}'`

Inspect and clean orphaned OpenCode main processes on the local machine.

Treat a process as an orphaned OpenCode process only when all of the following are true:

- The process parent PID (`PPID`) is `1`.
- The command line points to an `opencode` executable path.
- The command is the main `opencode` binary, not `opencode run ...`, not `opencode serve ...`, and not another unrelated process that merely contains the word `opencode`.

Use this inspection command:

```bash
ps -eo pid,ppid,lstart,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print}'
```

Use this PID-only command to collect processes to terminate:

```bash
ps -eo pid,ppid,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print $1}'
```

If the PID list is empty, say that there is nothing to clean and stop.

If the PID list is non-empty, terminate those PIDs with a normal `kill`, then re-run the inspection command and report what remains.

Cleanup command:

```bash
ps -eo pid,ppid,args | grep -i opencode | grep -v grep | awk '$2 == 1 && $NF ~ /(^|\/)(opencode)$/ {print $1}' | xargs kill
```

Safety rules:

- Do not kill any OpenCode process whose `PPID` is not `1`.
- Do not use `kill -9` unless I explicitly ask for a force kill after normal termination fails.
- Show the matching processes before cleanup and verify the result after cleanup.
