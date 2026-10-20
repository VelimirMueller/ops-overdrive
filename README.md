<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/banner/hero-v2-light.svg">
  <img alt="ops-overdrive — Your terminal, but louder. CLI · MODS · STATUSLINE · FLAIR." src="assets/banner/hero-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/lead-v2-light.svg">
  <img alt="Overdrive treats a local Claude Code setup as one versioned tool. It adds a loud terminal look and two Claude Code mods: a tab band above the prompt and colored, foldable tool rows." src="assets/readme/lead-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/stats-v2-light.svg">
  <img alt="11 CLI COMMANDS. 2 CLAUDE CODE MODS. 5 STATUSLINE ROWS. 68 MOD TESTS" src="assets/readme/stats-v2-dark.svg" width="100%">
</picture>
</p>

<br>

<p>
<img alt="01 WHAT IT DOES. ONE RIG. ONE VERSION. ONE SERPENT." src="assets/readme/divider-what-v2.svg" width="100%">
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/features-v2-light.svg">
  <img alt="VERSION: The overdrive CLI versions ~/.claude as a local git repo and pins every tool repo by SHA in one lock file. MODS: overdrive-tabs draws a tab band above the prompt. overdrive-tools colors every tool row and folds it. LOOK: An output style, a session banner and a five-row statusline share one neon palette and one art language" src="assets/readme/features-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/what-v2-light.svg">
  <img alt="One version for the setup: VERSION holds the semver, overdrive.lock pins components by SHA, and every version keeps its own log. Drift on session start: A SessionStart hook checks the pins in under 150 ms and records drift in the background. Colored tool rows: INF cyan for reads, CHG magenta for changes, RUN yellow for shell and agents. Click a tag to fold or open the row. Tab band: Code, tickets, Claude usage, overdrive state and a serpent pet, in a pink box above the prompt. Session log: Every tool appends INFO, WARN and CRITICAL lines to one crash-safe log per Claude session. Trace: overdrive trace reads a finished session: tool calls, wall time and token counts per tool" src="assets/readme/what-v2-dark.svg" width="100%">
</picture>
</p>

<br>

<p>
<img alt="02 QUICK START. TWO MODS IN FOUR COMMANDS." src="assets/readme/divider-start-v2.svg" width="100%">
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/start-v2-light.svg">
  <img alt="Terminal: $ git clone https://github.com/VelimirMueller/overdrive &amp;&amp; cd overdrive | $ claude plugin marketplace add ./mods | $ claude plugin install overdrive-tools@overdrive-mods | $ claude plugin install overdrive-tabs@overdrive-mods | # then, inside Claude Code: /tools folded" src="assets/readme/start-v2-dark.svg" width="100%">
</picture>
</p>

<details>
<summary><picture><source media="(prefers-color-scheme: light)" srcset="assets/readme/links-4-v2-light.svg"><img alt="Plain text" src="assets/readme/links-4-v2-dark.svg" width="32%"></picture></summary>

```bash
git clone https://github.com/VelimirMueller/overdrive && cd overdrive
claude plugin marketplace add ./mods
claude plugin install overdrive-tools@overdrive-mods
claude plugin install overdrive-tabs@overdrive-mods
```

</details>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/extras-v2-light.svg">
  <img alt="output-styles/overdrive.md: Copy to ~/.claude/output-styles/, then select it under Output style in /config. statusline-command.sh: Point statusLine.command in ~/.claude/settings.json at it. Chips for tools you lack stay empty. hooks/overdrive-banner.sh: A SessionStart hook: the pink banner and the frame reminder. tools/overdrive/overdrive: Link into your PATH. It expects ~/.claude to be a local git repo" src="assets/readme/extras-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/needs-v2-light.svg">
  <img alt="claude: Claude Code with function hooks (early access). Built on 2.1.303. bash · git · python3: For the CLI, the hooks and overdrive trace. rig tools: Optional. The tickets tab reads tix and code-context and shows empty rows without them" src="assets/readme/needs-v2-dark.svg" width="100%">
</picture>
</p>

<br>

<p>
<img alt="03 HOW IT WORKS. DRAWINGS CHANGE. RECORDS DO NOT." src="assets/readme/divider-how-v2.svg" width="100%">
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/flow-v2-light.svg">
  <img alt="TOOL CALL -&gt; OVERDRIVE-TOOLS -&gt; TRANSCRIPT ROW. The mod wraps the engine&#x27;s own drawing. The stored row and the model&#x27;s context do not change." src="assets/readme/flow-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/lock-v2-light.svg">
  <img alt="~/.claude -&gt; overdrive snapshot -&gt; overdrive.lock" src="assets/readme/lock-v2-dark.svg" width="100%">
</picture>
</p>

<br>

<p>
<img alt="04 USAGE. EVERY COMMAND, ONE LINE EACH." src="assets/readme/divider-usage-v2.svg" width="100%">
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/cmds-v2-light.svg">
  <img alt="overdrive: Status: version, uncommitted changes, lock drift. Read-only. overdrive snapshot [--if-drift] [&quot;msg&quot;]: Regenerate the lock and commit if anything changed. overdrive bump patch|minor|major &quot;msg&quot;: New version, new log, commit and tag. overdrive history · changelog [N]: Versions with their messages and log lines. overdrive trace [&lt;session&gt;|--last]: Tool calls, wall time and tokens of one session. overdrive catalog · limits: Every tool with its glyph and version. Known limits and caps. overdrive session show|path|list|rm: This session&#x27;s log" src="assets/readme/cmds-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/tools-v2-light.svg">
  <img alt="/tools folded: Default. Every finished tool row starts folded. /tools changes: Fold info rows. Keep changes and runs open. /tools all: Open every row. Bare /tools toggles folded and all. click a tag: Fold or open that one row. Needs the fullscreen layout" src="assets/readme/tools-v2-dark.svg" width="100%">
</picture>
</p>

<br>

<p>
<img alt="05 STATUS. STABLE ON TOP OF AN EARLY API." src="assets/readme/divider-status-v2.svg" width="100%">
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/status-v2-light.svg">
  <img alt="overdrive CLI and lock format: stable. Mod tests: claude plugin test, 68 pass. Function hooks API: early access, may change. Bash classifier in overdrive-tools: stub, every shell row is RUN" src="assets/readme/status-v2-dark.svg" width="100%">
</picture>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/checks-v2-light.svg">
  <img alt="Terminal: $ claude plugin validate mods/overdrive-tools | $ claude plugin test mods/overdrive-tools | $ claude plugin test mods/overdrive-tabs | $ python3 tools/overdrive/test_trace.py" src="assets/readme/checks-v2-dark.svg" width="100%">
</picture>
</p>

<details>
<summary><picture><source media="(prefers-color-scheme: light)" srcset="assets/readme/links-4-v2-light.svg"><img alt="Plain text" src="assets/readme/links-4-v2-dark.svg" width="32%"></picture></summary>

```bash
claude plugin validate mods/overdrive-tools
claude plugin test mods/overdrive-tools
claude plugin test mods/overdrive-tabs
python3 tools/overdrive/test_trace.py
```

</details>

<p align="center">
<a href="tools/overdrive/FLAIR.md"><picture><source media="(prefers-color-scheme: light)" srcset="assets/readme/links-1-v2-light.svg"><img alt="Art language (tools/overdrive/FLAIR.md)" src="assets/readme/links-1-v2-dark.svg" width="32%"></picture></a>
<a href="tools/overdrive/SESSION-LOG.md"><picture><source media="(prefers-color-scheme: light)" srcset="assets/readme/links-2-v2-light.svg"><img alt="Session log (tools/overdrive/SESSION-LOG.md)" src="assets/readme/links-2-v2-dark.svg" width="32%"></picture></a>
<a href="mods/overdrive-tools/SPEC.md"><picture><source media="(prefers-color-scheme: light)" srcset="assets/readme/links-3-v2-light.svg"><img alt="Mod specs (mods/overdrive-tools/SPEC.md)" src="assets/readme/links-3-v2-dark.svg" width="32%"></picture></a>
</p>

<p>
<picture>
  <source media="(prefers-color-scheme: light)" srcset="assets/readme/footer-v2-light.svg">
  <img alt="VM. studio / ops · public tool · MIT · look per vm-brand playbook · -- EOF -- frames in chat only --" src="assets/readme/footer-v2-dark.svg" width="100%">
</picture>
</p>
