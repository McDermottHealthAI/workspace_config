# Claude Code Setup

[Claude Code](https://docs.claude.com/en/docs/claude-code) is Anthropic's terminal-based coding
agent. This document captures the **global, machine-level** setup I use so a fresh box behaves the
same as the rest of my environment: the `gh` CLI, web-search and library-docs MCP servers, and my
default permission / auto-approval settings. It is deliberately project-agnostic — per-project
conventions belong in that project's `AGENTS.md` / `CLAUDE.md`, not here.

All of this is `--scope user` / `~/.claude`-level, so it applies across every project once set up.

## Install & authenticate

Claude Code ships as an npm package and needs Node.js ≥ 18 (the same `nodejs`/`npm` install covered
in the [Neovim](README.md#neovim) section of the main README).

```bash
npm install -g @anthropic-ai/claude-code
claude --version
claude auth login
```

Run `claude` inside a project directory and it reads that project's `AGENTS.md` / `CLAUDE.md`
automatically on session start.

## GitHub CLI (`gh`)

Use the `gh` CLI for all GitHub operations (PRs, issues, releases, Actions logs, code search). It is
faster, more reliable, and far cheaper in tokens than the GitHub MCP server — and my global
preferences explicitly forbid the GitHub MCP server in favor of `gh`.

```bash
# Ubuntu/Debian
sudo apt-get install gh

# macOS
brew install gh

gh auth login
```

## MCP servers

Claude Code has no built-in internet access. Two `stdio` MCP servers cover the gaps; install both
with `--scope user` so they are available in every project, not just the current one. Both run via
`npx`, so they need Node.js/`npm` (see above).

### Web search — Brave Search

[Brave Search](https://brave.com/search/api/) gives general-purpose web search for looking up
current docs, verifying library behavior, and checking recent releases. The free tier is plenty for
interactive use. Grab a key from the Brave Search API dashboard, then:

```bash
claude mcp add brave-search --scope user \
    -e BRAVE_API_KEY=your-key \
    -- npx -y @modelcontextprotocol/server-brave-search
```

### Library docs — Context7

[Context7](https://context7.com/) fetches current, version-specific documentation for libraries,
frameworks, and SDKs. No API key required. It is more reliable than web search for
library-specific questions because it pulls from the actual docs.

```bash
claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

### Account-level (remote) MCP servers — optional

Beyond the two local servers above, Claude Code can connect to remote MCP servers tied to your
Anthropic/claude.ai account via OAuth (Figma, Slack, Gmail, Google Calendar, Google Drive, etc.).
These are added interactively (`claude mcp add --transport http <name> <url>`, then authenticate in
the browser) and are not reproducible from a config file the way the `npx` servers are — set them up
on demand. Verify everything is wired up with:

```bash
claude mcp list
```

## Global defaults (`~/.claude/settings.json`)

My machine-level defaults live in `~/.claude/settings.json`. The key behaviors:

- **`defaultMode: "auto"`** — sessions start in **auto mode**, so reads, edits, and allow-listed
  Bash commands run without a prompt while genuinely risky actions still pause for confirmation.
- **`skipAutoPermissionPrompt: true`** — skips the one-time "enable auto mode?" prompt on new
  projects (I've already opted in).
- **`permissions.allow`** — an allow-list of safe, high-frequency tools so they never prompt:
  `Edit`/`Read`, and Bash for `git`, `gh`, `uv`, `python`/`pytest`/`ruff`/`pre-commit`, `make`, the
  LaTeX toolchain (`latexmk`/`pdflatex`/`xelatex`/`bibtex`), and common read-only shell utilities
  (`cat`, `ls`, `find`, `grep`, `head`/`tail`, `wc`, `diff`, `sort`, `sed`, `awk`), plus a few
  file-management and viewer commands (`mkdir`/`cp`/`mv`/`touch`, `xdg-open`, `pdftoppm`, `jupyter`).
- **`permissions.deny`** — a hard block-list that auto mode cannot override: `rm -rf /`, and raw
  `curl`/`wget` (web fetches should go through the Brave Search MCP, not arbitrary shell downloads).

A reproducible starting point:

```json
{
  "permissions": {
    "allow": [
      "Edit",
      "Read",
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(uv *)",
      "Bash(python *)",
      "Bash(pytest *)",
      "Bash(ruff *)",
      "Bash(pre-commit *)",
      "Bash(make *)",
      "Bash(latexmk *)",
      "Bash(pdflatex *)",
      "Bash(xelatex *)",
      "Bash(bibtex *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(diff *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(mv *)",
      "Bash(touch *)",
      "Bash(echo *)",
      "Bash(sort *)",
      "Bash(sed *)",
      "Bash(awk *)",
      "Bash(xdg-open *)",
      "Bash(pdftoppm *)",
      "Bash(jupyter *)",
      "Bash(pip *)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(curl *)",
      "Bash(wget *)"
    ],
    "defaultMode": "auto"
  },
  "skipAutoPermissionPrompt": true
}
```

> **Tune the allow-list to your own risk tolerance.** Auto mode + a broad allow-list trades safety
> prompts for speed; it suits a single-user dev box, not a shared or production machine. Drop
> entries you don't want running unprompted.

## Global preferences (`~/.claude/CLAUDE.md`)

Cross-project *preferences* (as opposed to *permissions*) live in `~/.claude/CLAUDE.md` — e.g. "use
`uv` for Python, never `pip`", "use `gh` for GitHub, not the MCP server", "use `xdg-open` on Linux",
LaTeX/figure conventions, and my PR workflow. Claude Code loads it on every session in every
project. Keep machine-level habits there; keep repo-specific conventions in each repo's `AGENTS.md`.

## Warp marketplace plugin (optional)

I run Claude Code inside [Warp](https://www.warp.dev/). The
[`warpdotdev/claude-code-warp`](https://github.com/warpdotdev/claude-code-warp) marketplace adds
Warp-specific integration; it's registered under `extraKnownMarketplaces` in `~/.claude/settings.json`
and is entirely optional if you use a different terminal.
