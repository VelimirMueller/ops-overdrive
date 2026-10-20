#!/usr/bin/env python3
"""overdrive trace — per-tool cost of one Claude Code session, read AFTER the fact.

Zero runtime cost: nothing is instrumented. This reads what already exists:
  * the transcript  ~/.claude/projects/<proj>/<session>.jsonl  (+ <session>/subagents/*.jsonl)
  * the session log ~/.claude/.local_ai_setup_logs/sessions/<session>.log (SESSION-LOG.md)

Per local tool: calls, total/max wall time (tool_use timestamp -> tool_result timestamp),
≈ctx tok its outputs added (result text chars / 4 — an estimate, labelled as one), and
real model tokens where the tool's own session-log lines carry `tokens=<in>/<out>`
(FLAIR.md: `done <cmd> in <ms> ms tokens=…`). Session totals come from message.usage.

Called by `overdrive trace`; run with `python3 -I` (stdlib only). Streams line by line,
and skips lines that cannot matter before json-decoding them, so 100 MB stays fast.
"""
import json
import os
import re
import sys
from datetime import datetime

# ── canonical local tools: name -> glyph (FLAIR.md / statusline) ────────────────────────
GLYPH = {
    "rig": "⚙", "impl-run": "⚙", "glm-run": "⚙", "deepseek-run": "⚙",
    "tix": "⬢", "dual-review": "⚖", "rag-vault": "⛁", "rag-verify": "✓",
    "code-context": "●", "rag-context": "◆", "doc-creator": "✎", "image-gen": "◈",
    "release-pilot": "⚑", "overdrive": "⏣",
}
# MCP server names that are Velimir's own local servers (mcp__<server>__…)
LOCAL_MCP = {"code-context", "rag-context", "doc-creator", "image-gen", "release-pilot"}

# command word (basename, ".sh"/".py" stripped) -> canonical tool
BASH_TOOLS = {
    "rig": "rig", "tix": "tix", "dual-review": "dual-review", "relpilot": "release-pilot",
    "overdrive": "overdrive", "rag-vault-commit": "rag-vault", "rag-vault": "rag-vault",
    "rag-vault-commit-launchd": "rag-vault", "impl-run": "impl-run", "glm-run": "glm-run",
    "deepseek-run": "deepseek-run", "rag-context": "rag-context", "rag-verify": "rag-verify",
    "code-context": "code-context", "doc-creator": "doc-creator", "image-gen": "image-gen",
    "sessionlog": "overdrive", "code-context-reindex": "code-context",
}
# `python -m <module>` -> canonical tool
PY_MODULES = {"rag_context": "rag-context", "release_pilot": "release-pilot",
              "doc_creator": "doc-creator", "image_gen": "image-gen"}
WRAPPERS = {"time", "nohup", "env", "command", "exec", "bash", "sh", "zsh", "sudo",
            "caffeinate", "nice", "xargs", "builtin", "then", "do", "else", "!", "{"}
_SEG = re.compile(r"\$\(|&&|\|\||[;|&()`\n{}]")
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_PYMOD = re.compile(r"(?:^|\s)-m\s+([A-Za-z_][A-Za-z0-9_]*)")
_SHELL_C = re.compile(r"\b(?:bash|sh|zsh)\s+(?:-[a-z]+\s+)*-c\s+(['\"])(.*?)\1", re.S)
_ASSIGN_ALL = re.compile(r"(?:^|[\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)")
_VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
# …/.claude/tools/<dir>/[sub/]file — must END in a file name: a bare folder like "$B/" is a
# quoted sed/grep fragment that _SEG cut out of a string, never a command
_TOOL_DIR = re.compile(r"/\.claude/tools/([A-Za-z0-9_-]+)/(?:[^\s\"'/]+/)*[^\s\"'/]+$")
# a command word whose path runs through ~/.claude/tools/<dir>/ belongs to that tool
TOOL_DIRS = {"rig": "rig", "dual-review": "dual-review", "rag-vault": "rag-vault", "overdrive": "overdrive",
             "rag-verify": "rag-verify", "relpilot": "release-pilot", "bench": "bench"}


def classify_bash(command, _depth=0):
    """Which local tool does this Bash command call?  -> canonical name, or None.

    Rule (refined 2026-10-09 against the 160 Bash calls of a real session):
    split the command into segments (; && || | & ( ) $( ` newlines), skip leading
    VAR=value words and wrappers (time, nohup, env [-u NAME], bash, timeout N, xargs …),
    and judge the COMMAND WORD only — never a substring, so `cat …/rig.md`,
    `git -C ~/.claude/tools/rig …` and `gh pr merge -R …/tix` do NOT count. The word
    matches when
      1. its basename (.sh/.py stripped) is in BASH_TOOLS, or
      2. its path runs through a tool folder (TOOL_DIRS: ~/.claude/tools/<dir>/…),
         which also catches bench's run.sh / weekly.sh / publish.sh, or
      3. it is `python -m <module>` with the module in PY_MODULES.
    Before judging, simple assignments made earlier in the same command are expanded
    (`B=~/.claude/tools/bench; $B/run.sh`), and the quoted body of `bash|sh|zsh -c '…'`
    is classified recursively. The first matching segment wins. Blind spots: tools
    called inside scripts/Makefiles, and variables set outside the command.
    """
    if not command or _depth > 3:
        return None
    # bash -c '…' / sh -c "…": the body is a command line of its own
    for m in _SHELL_C.finditer(command):
        hit = classify_bash(m.group(2), _depth + 1)
        if hit:
            return hit
    env_vars = {k: v.strip("\"'") for k, v in _ASSIGN_ALL.findall(command)}
    for seg in _SEG.split(command):
        words = seg.strip().split()
        i = 0
        while i < len(words):
            w = words[i].strip("\"'")
            if w == "env":                      # env [-i] [-u NAME] [NAME=v] cmd …
                i += 1
                while i < len(words) and words[i].startswith("-"):
                    i += 2 if words[i] in ("-u", "--unset", "-C", "--chdir", "-S") else 1
                continue
            if _ASSIGN.match(w) or w in WRAPPERS or w.startswith("-"):
                i += 1
                continue
            if w == "timeout" and i + 1 < len(words):   # timeout 30 cmd …
                i += 2
                continue
            break
        if i >= len(words):
            continue
        raw = _expand(words[i].strip("\"'"), env_vars)
        word = os.path.basename(raw)
        for ext in (".sh", ".py"):
            if word.endswith(ext):
                word = word[: -len(ext)]
        if word in BASH_TOOLS:
            return BASH_TOOLS[word]
        m = _TOOL_DIR.search(raw)
        if m and m.group(1) in TOOL_DIRS:
            return TOOL_DIRS[m.group(1)]
        if word.startswith("python"):
            m = _PYMOD.search(seg)
            if m:
                mod = m.group(1).split(".")[0]
                if mod in PY_MODULES:
                    return PY_MODULES[mod]
    return None


def _expand(word, env_vars):
    """$NAME / ${NAME} from assignments in the same command; ~ and $HOME stay literal
    (the folder rule matches on '/.claude/tools/<dir>/' wherever it sits)."""
    return _VAR.sub(lambda m: env_vars.get(m.group(1) or m.group(2), m.group(0)), word)


def classify(name, inp):
    """tool_use -> (bucket name, kind, is_local)."""
    if name.startswith("mcp__"):
        server = name[5:].split("__", 1)[0]
        if server in LOCAL_MCP:
            return server, "mcp", True
        return "mcp:" + server, "mcp", False
    if name == "Bash":
        tool = classify_bash((inp or {}).get("command", ""))
        if tool:
            return tool, "cli", True
    return name, "builtin", False


def ts_ms(s):
    if not s:
        return None
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def result_chars(content):
    """Text characters a tool_result put into the context; images counted separately."""
    if isinstance(content, str):
        return len(content), 0
    n = imgs = 0
    if isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text":
                n += len(b.get("text") or "")
            elif b.get("type") == "image":
                imgs += 1
    return n, imgs


USAGE_KEYS = (("input_tokens", "input"), ("output_tokens", "output"),
              ("cache_read_input_tokens", "cache_read"),
              ("cache_creation_input_tokens", "cache_creation"))


def scan(path, tools, usage, pending, span, sub):
    """Stream one transcript. Usage is deduped by message.id (one API message is split
    over several records — thinking, text, tool_use — that each repeat its usage)."""
    seen = {}
    with open(path, "rb") as fh:
        for raw in fh:
            if b'"tool_use"' not in raw and b'"tool_result"' not in raw and b'"usage"' not in raw:
                continue
            try:
                o = json.loads(raw)
            except ValueError:
                continue
            t = ts_ms(o.get("timestamp"))
            if t:
                span[0] = t if span[0] is None else min(span[0], t)
                span[1] = t if span[1] is None else max(span[1], t)
            m = o.get("message")
            if not isinstance(m, dict):
                continue
            u = m.get("usage")
            if o.get("type") == "assistant" and isinstance(u, dict) and m.get("id"):
                seen[m["id"]] = u      # last record of a message carries the final usage
            content = m.get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    bucket, kind, local = classify(b.get("name") or "?", b.get("input"))
                    pending[b.get("id")] = (bucket, t)
                    d = tools.setdefault(bucket, new_tool(bucket, kind, local))
                    d["calls"] += 1
                    if sub:
                        d["sub_calls"] += 1
                elif b.get("type") == "tool_result":
                    p = pending.pop(b.get("tool_use_id"), None)
                    if not p:
                        continue
                    d = tools[p[0]]
                    n, imgs = result_chars(b.get("content"))
                    d["ctx_chars"] += n
                    d["images"] += imgs
                    if b.get("is_error"):
                        d["errors"] += 1
                    if p[1] and t and t >= p[1]:
                        dt = t - p[1]
                        d["wall_ms_total"] += dt
                        d["wall_ms_max"] = max(d["wall_ms_max"], dt)
    tgt = usage["subagents" if sub else "main"]
    for u in seen.values():
        for k, short in USAGE_KEYS:
            v = u.get(k)
            if isinstance(v, int):
                tgt[short] += v
    tgt["messages"] += len(seen)


def new_tool(name, kind, local):
    return {"name": name, "glyph": GLYPH.get(name, ""), "kind": kind, "local": local,
            "calls": 0, "sub_calls": 0, "errors": 0, "wall_ms_total": 0, "wall_ms_max": 0,
            "ctx_chars": 0, "images": 0, "model_tokens_in": 0, "model_tokens_out": 0,
            "log_lines": 0, "log_done_ms": 0}


_TOK = re.compile(r"\btokens=(\d+)/(\d+)")
_DONE = re.compile(r"\bdone \S+ in (\d+) ms")
LOG_ALIAS = {"relpilot": "release-pilot", "rag-vault-commit": "rag-vault"}


def read_slog(path, tools):
    if not path or not os.path.isfile(path):
        return False
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t", 4)
            if len(f) < 5:
                continue
            name = f[2].rsplit("@", 1)[0]
            name = LOG_ALIAS.get(name, name)
            d = tools.get(name)
            if d is None:
                d = tools[name] = new_tool(name, "log", True)
            d["log_lines"] += 1
            m = _TOK.search(f[4])
            if m:
                d["model_tokens_in"] += int(m.group(1))
                d["model_tokens_out"] += int(m.group(2))
            m = _DONE.search(f[4])
            if m:
                d["log_done_ms"] += int(m.group(1))
    return True


# ── rendering ───────────────────────────────────────────────────────────────────────────
PAL = {"mag": "238;79;255", "cyan": "0;255;247", "green": "5;255;161",
       "yellow": "240;255;25", "red": "255;42;109", "dim": "90;80;130"}


class Pen:
    def __init__(self, color):
        self.color = color

    def __call__(self, name, s):
        return f"\033[38;2;{PAL[name]}m{s}\033[0m" if self.color else s


def fms(ms):
    if ms < 1000:
        return f"{ms} ms"
    s = ms / 1000
    if s < 60:
        return f"{s:.1f}s"
    m, s = divmod(int(s), 60)
    if m < 60:
        return f"{m}m{s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h{m:02d}m"


def fnum(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.1f}k"
    return str(n)


def bar(v, vmax, width=14):
    if vmax <= 0 or v <= 0:
        return " " * width
    cells = v / vmax * width
    full = int(cells)
    rest = cells - full
    s = "█" * full
    if full < width:
        s += "▓" if rest > .66 else "▒" if rest > .33 else "░" if rest > 0.05 or full == 0 else " "
    return s.ljust(width)


def render(r, color, art):
    p = Pen(color)
    out = []
    ses = r["session"]
    span = r["span"]
    when = ""
    if span["start_ms"]:
        a = datetime.fromtimestamp(span["start_ms"] / 1000).strftime("%Y-%m-%d %H:%M")
        b = datetime.fromtimestamp(span["end_ms"] / 1000).strftime("%H:%M")
        when = f"{a} → {b} ({fms(span['end_ms'] - span['start_ms'])})"
    out.append(p("cyan", f"session {ses}") + p("dim", f"  {when} · {r['transcripts']['subagents']} subagent transcript(s)"
                                                  + ("" if r["session_log"] else " · no session log")))
    div = p("dim", "─" * 78)
    if art:
        out.append(div)
    local = [t for t in r["tools"] if t["local"]]
    other = [t for t in r["tools"] if not t["local"]]
    hdr = f"{'  tool':<17}{'calls':>6}{'wall Σ':>9}{'max':>9}{'≈ctx tok':>10}  {'':14}{'model tok in/out':>18}"
    out.append(p("dim", hdr))
    vmax = max([t["ctx_tok_est"] for t in local] + [1])
    for t in local:
        glyph = (t["glyph"] or "·") if art else " "
        mt = f"{fnum(t['model_tokens_in'])}/{fnum(t['model_tokens_out'])}" if (t["model_tokens_in"] or t["model_tokens_out"]) else "—"
        calls = str(t["calls"]) + ("*" if t["sub_calls"] else "")
        line = (p("cyan", f"{glyph} {t['name']:<14}") + f"{calls:>6}{fms(t['wall_ms_total']) if t['calls'] else '—':>9}"
                f"{fms(t['wall_ms_max']) if t['calls'] else '—':>9}{fnum(t['ctx_tok_est']):>10}  "
                + p("mag", bar(t["ctx_tok_est"], vmax) if art else " " * 14) + f"{mt:>18}")
        if t["errors"]:
            line += p("red", f"  {t['errors']} err")
        out.append(line)
    if not local:
        out.append(p("dim", "  (no local tool was called in this session)"))
    if other:
        oc = sum(t["calls"] for t in other)
        ot = sum(t["ctx_tok_est"] for t in other)
        top = ", ".join(f"{t['name']} {t['calls']}×/{fnum(t['ctx_tok_est'])}" for t in sorted(other, key=lambda x: -x["ctx_tok_est"])[:5])
        out.append(p("dim", f"  everything else: {oc} calls, ≈{fnum(ot)} ctx tok — {top}"))
    if any(t["sub_calls"] for t in local):
        out.append(p("dim", "  * includes calls made inside subagents"))
    if art:
        out.append(div)
    for key, label in (("main", "main"), ("subagents", "subagents")):
        u = r["usage"][key]
        if not u["messages"]:
            continue
        out.append(f"{label:<10}" + p("dim", f"{u['messages']} msgs · ") +
                   f"in {fnum(u['input'])} · out {fnum(u['output'])} · cache read {fnum(u['cache_read'])} · cache write {fnum(u['cache_creation'])}")
    s, e = r.get("slowest"), r.get("most_expensive")
    if s:
        k = "(╯°□°)╯︵ ┻━┻" if art else "-"
        out.append(p("yellow", f"{k} ") + f"slowest {s['glyph'] + ' ' if art else ''}{s['name']} — {fms(s['wall_ms_total'])} total, max {fms(s['wall_ms_max'])}")
    if e:
        k = "ಠ_ಠ" if art else "-"
        out.append(p("red", f"{k} ") + f"heaviest {e['glyph'] + ' ' if art else ''}{e['name']} — ≈{fnum(e['ctx_tok_est'])} ctx tok"
                   + (f", {fnum(e['model_tokens_in'])}/{fnum(e['model_tokens_out'])} model tok" if e["model_tokens_in"] else ""))
    return "\n".join(out)


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="overdrive trace")
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--slog")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--color", action="store_true")
    ap.add_argument("--art", action="store_true")
    a = ap.parse_args(argv)

    tools, pending, span = {}, {}, [None, None]
    usage = {k: {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0, "messages": 0}
             for k in ("main", "subagents")}
    scan(a.transcript, tools, usage, pending, span, False)
    subdir = os.path.join(a.transcript[:-6], "subagents")
    subs = []
    if os.path.isdir(subdir):
        subs = sorted(os.path.join(subdir, f) for f in os.listdir(subdir) if f.endswith(".jsonl"))
        for f in subs:
            scan(f, tools, usage, {}, span, True)
    has_log = read_slog(a.slog, tools)

    rows = []
    for d in tools.values():
        d["ctx_tok_est"] = d["ctx_chars"] // 4
        rows.append(d)
    rows.sort(key=lambda d: (-d["local"], -d["ctx_tok_est"], -d["calls"], d["name"]))
    total = {k: usage["main"][k] + usage["subagents"][k] for k in usage["main"]}
    local = [d for d in rows if d["local"] and d["calls"]]
    res = {
        "session": os.path.basename(a.transcript)[:-6],
        "transcripts": {"main": a.transcript, "subagents": len(subs)},
        "session_log": a.slog if has_log else None,
        "span": {"start_ms": span[0], "end_ms": span[1]},
        "tools": rows,
        "usage": {"main": usage["main"], "subagents": usage["subagents"], "total": total},
        "slowest": max(local, key=lambda d: d["wall_ms_total"]) if local else None,
        "most_expensive": max(local, key=lambda d: (d["ctx_tok_est"], d["model_tokens_in"] + d["model_tokens_out"])) if local else None,
        "unmatched_tool_uses": len(pending),
        "note": "ctx_tok_est = tool_result text chars / 4 (estimate); model_tokens_* only from session-log tokens=in/out",
    }
    if a.json:
        json.dump(res, sys.stdout, ensure_ascii=False, indent=1)
        sys.stdout.write("\n")
    else:
        print(render(res, a.color, a.art))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
