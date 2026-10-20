"""classify_bash() cases — run: python3 -I ~/.claude/tools/overdrive/test_trace.py
Built 2026-10-09 from the Bash calls of a real session. A case that must NOT count is as
important as one that must: over-attribution makes `overdrive trace` lie about tool use."""
import importlib.util
import os
import sys
import unittest

_spec = importlib.util.spec_from_file_location("trace", os.path.join(os.path.dirname(os.path.abspath(__file__)), "trace.py"))
trace = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(trace)

COUNTS = [
    ("env -u ANTHROPIC_API_KEY X=1 ~/.claude/tools/bench/run.sh --probe", "bench"),
    ("B=~/.claude/tools/bench; [ -f $B/request ] && $B/run.sh --if-requested", "bench"),
    ("B=~/.claude/tools/bench; $B/run.sh --probe", "bench"),
    ("~/.claude/tools/bench/lib/fixture.sh verify", "bench"),
    ("bash -c 'cd ~/.claude && tix lint x.md'", "tix"),
    ("cd ~/x && OVERDRIVE_FLAIR=0 dual-review 2>&1 | head", "dual-review"),
    ("~/.claude/tools/rig/impl-run.sh --provider glm --cwd .", "impl-run"),
    ("timeout 30 rig quota", "rig"),
    ("~/Desktop/Workspace/mcp-servers/bin/code-context-reindex.sh --all", "code-context"),
    (".venv/bin/python -m rag_context.cli verify status", "rag-context"),
    ("D=~/.claude/tools/dual-review; git -C $D pull -q && dual-review --version", "dual-review"),
    ('date; B=~/.claude/tools/bench; find $B -type f | sed "s|$B/||" | head; rig quota', "rig"),
]
NOT_COUNTS = [
    "cat ~/Desktop/RAG/system/rig.md",
    "git -C ~/.claude/tools/rig worktree list",
    "gh pr merge 9 -R VelimirMueller/tix --merge",
    "grep -n tix ~/.claude/CLAUDE.md",
    "sed -n 1,40p ~/.claude/tools/overdrive/overdrive",
    "cp tools/dual-review/hooks/dual-review-gate.sh ~/.claude/hooks/",
    "for b in tix rig; do $b --version; done",
    "cd ~/.claude/tools/bench/",
]


class ClassifyBash(unittest.TestCase):
    def test_counts(self):
        for cmd, tool in COUNTS:
            with self.subTest(cmd=cmd):
                self.assertEqual(trace.classify_bash(cmd), tool)

    def test_does_not_count(self):
        for cmd in NOT_COUNTS:
            with self.subTest(cmd=cmd):
                self.assertIsNone(trace.classify_bash(cmd))


if __name__ == "__main__":
    sys.exit(not unittest.main(exit=False, verbosity=1).result.wasSuccessful())
