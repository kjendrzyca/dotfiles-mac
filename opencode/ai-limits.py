#!/usr/bin/env python3

import argparse
import fcntl
import json
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import termios
import time

CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
OSC_RE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def visible_text(text: str) -> str:
    text = OSC_RE.sub("", text)
    text = CSI_RE.sub("", text)
    text = text.replace("\r", "\n")
    return "".join(ch if ch in "\n\t" or ch >= " " else " " for ch in text)


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", visible_text(text)).strip()


def prefer(*paths: str) -> str | None:
    for path in paths:
        expanded = os.path.expanduser(path)
        if os.path.isfile(expanded) and os.access(expanded, os.X_OK):
            return expanded
    return None


def set_winsize(fd: int, rows: int, cols: int) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def read_available(fd: int, timeout: float = 0.2) -> bytes:
    out = b""
    readable, _, _ = select.select([fd], [], [], timeout)
    if not readable:
        return out
    while True:
        try:
            chunk = os.read(fd, 8192)
        except Exception:
            break
        if not chunk:
            break
        out += chunk
        readable, _, _ = select.select([fd], [], [], 0)
        if not readable:
            break
    return out


def parse_pct(section: str | None) -> int | None:
    if not section:
        return None
    match = re.search(r"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*(used|left)", section, re.I)
    if not match:
        return None
    value = float(match.group(1))
    if match.group(2).lower() == "used":
        return int(round(max(0, min(100, 100 - value))))
    return int(round(max(0, min(100, value))))


def parse_reset(section: str | None) -> str | None:
    if not section:
        return None
    match = re.search(r"Rese[a-z]*\s*(.+)", section, re.I)
    return match.group(1).strip(" .") if match else None


def extract_section(
    compact_text: str, label: str, next_labels: list[str]
) -> str | None:
    lower = compact_text.lower()
    start = lower.find(label.lower())
    if start == -1:
        return None
    end = len(compact_text)
    for next_label in next_labels:
        idx = lower.find(next_label.lower(), start + 1)
        if idx != -1:
            end = min(end, idx)
    return compact_text[start:end].strip()


def run_claude() -> dict:
    claude = prefer("~/.local/bin/claude") or shutil.which("claude")
    if not claude:
        raise RuntimeError("Claude CLI not found")

    command = [
        "/usr/bin/script",
        "-q",
        "/dev/null",
        claude,
        "/usage",
        "--allowed-tools",
        "",
    ]
    process = subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    chunks: list[bytes] = []

    try:
        assert process.stdout is not None
        fd = process.stdout.fileno()
        start = time.time()
        while time.time() - start < 20:
            readable, _, _ = select.select([fd], [], [], 0.25)
            if readable:
                data = os.read(fd, 8192)
                if not data:
                    break
                chunks.append(data)
                output = compact(b"".join(chunks).decode("utf-8", "ignore"))
                if (
                    "current session" in output.lower()
                    and "current week" in output.lower()
                ):
                    time.sleep(1.2)
                    while True:
                        readable2, _, _ = select.select([fd], [], [], 0.1)
                        if not readable2:
                            break
                        data2 = os.read(fd, 8192)
                        if not data2:
                            break
                        chunks.append(data2)
                    break
            if process.poll() is not None:
                break
    finally:
        try:
            process.terminate()
            process.wait(timeout=2)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass

    output = compact(b"".join(chunks).decode("utf-8", "ignore"))
    labels = [
        "Current session",
        "Current week (all models)",
        "Current week (Sonnet only)",
        "Current week (Opus)",
        "Extra usage",
        "Esc to cancel",
    ]
    session = extract_section(output, "Current session", labels[1:])
    week = extract_section(output, "Current week (all models)", labels[2:])
    sonnet = extract_section(output, "Current week (Sonnet only)", labels[3:])
    opus = extract_section(output, "Current week (Opus)", labels[4:])
    secondary = sonnet or opus

    return {
        "session_left": parse_pct(session),
        "session_reset": parse_reset(session),
        "week_left": parse_pct(week),
        "week_reset": parse_reset(week),
        "secondary_left": parse_pct(secondary),
        "secondary_reset": parse_reset(secondary),
        "secondary_label": "sonnet-only week"
        if sonnet
        else ("opus week" if opus else None),
    }


def run_codex() -> dict:
    codex = prefer("/opt/homebrew/bin/codex") or shutil.which("codex")
    if not codex:
        raise RuntimeError("Codex CLI not found")

    master, slave = pty.openpty()
    set_winsize(master, 60, 200)
    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    env.setdefault("LANG", "en_US.UTF-8")
    process = subprocess.Popen(
        [codex, "-s", "read-only", "-a", "untrusted"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        cwd=os.getcwd(),
        env=env,
        close_fds=True,
    )
    os.close(slave)

    buffer = b""
    start = time.time()
    sent = False
    last_enter = 0.0
    resend = 0

    try:
        while time.time() - start < 20:
            data = read_available(master, 0.25)
            if data:
                buffer += data
                output = buffer.decode("utf-8", "ignore")
                compact_output = compact(output).lower()
                if "update available" in compact_output and "codex" in compact_output:
                    time.sleep(0.3)
                    os.write(master, b"\x1b[B")
                    time.sleep(0.4)
                    os.write(master, b"\r")
                    time.sleep(0.5)
                    buffer = b""
                    sent = False
                    continue
                if "5h limit:" in output and "weekly limit:" in output:
                    time.sleep(1.0)
                    buffer += read_available(master, 0.1)
                    break

            elapsed = time.time() - start
            if not sent and elapsed >= 0.4:
                os.write(master, b"/status")
                os.write(master, b"\r")
                sent = True
                last_enter = time.time()
            elif sent and time.time() - last_enter >= 1.2:
                os.write(master, b"\r")
                last_enter = time.time()

            if (
                sent
                and elapsed >= 5 + resend * 3
                and resend < 2
                and b"5h limit:" not in buffer
            ):
                os.write(master, b"/status")
                os.write(master, b"\r")
                resend += 1
                last_enter = time.time()

            if process.poll() is not None:
                break
    finally:
        try:
            os.write(master, b"/exit\r")
        except Exception:
            pass
        try:
            process.terminate()
            process.wait(timeout=2)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass
        try:
            os.close(master)
        except Exception:
            pass

    output = compact(buffer.decode("utf-8", "ignore"))
    five = re.search(
        r"5h limit:\s*.*?(\d+)%\s*left\s*\(resets\s*([^\)]+)\)", output, re.I
    )
    week = re.search(
        r"Weekly limit:\s*.*?(\d+)%\s*left\s*\(resets\s*([^\)]+)\)", output, re.I
    )

    return {
        "five_hour_left": int(five.group(1)) if five else None,
        "five_hour_reset": five.group(2).strip() if five else None,
        "week_left": int(week.group(1)) if week else None,
        "week_reset": week.group(2).strip() if week else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    claude = run_claude()
    codex = run_codex()

    payload = {
        "claude": claude,
        "codex": codex,
    }

    if args.json:
        print(json.dumps(payload, indent=2))
        return

    print("Claude")
    print(
        f"  session: {claude['session_left']}% left"
        + (f" - resets {claude['session_reset']}" if claude["session_reset"] else "")
    )
    print(
        f"  week (all models): {claude['week_left']}% left"
        + (f" - resets {claude['week_reset']}" if claude["week_reset"] else "")
    )
    if claude["secondary_label"]:
        print(
            f"  {claude['secondary_label']}: {claude['secondary_left']}% left"
            + (
                f" - resets {claude['secondary_reset']}"
                if claude["secondary_reset"]
                else ""
            )
        )

    print()
    print("Codex")
    print(
        f"  5h limit: {codex['five_hour_left']}% left"
        + (f" - resets {codex['five_hour_reset']}" if codex["five_hour_reset"] else "")
    )
    print(
        f"  weekly limit: {codex['week_left']}% left"
        + (f" - resets {codex['week_reset']}" if codex["week_reset"] else "")
    )


if __name__ == "__main__":
    main()
