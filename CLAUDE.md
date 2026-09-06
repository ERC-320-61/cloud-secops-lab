# CLAUDE.md

**[AGENTS.md](AGENTS.md) is the canonical guide for working in this repository. Read it first
and follow it.** This file only carries notes specific to this one tool.

- Start every session by reading `AGENTS.md`, then follow the documentation reading order it
  defines (README → docs/PROJECT_CHARTER → docs/CURRENT_STATE → docs/ARCHITECTURE →
  docs/ROADMAP → docs/DECISIONS → docs/RUNBOOK) and inspect `git status` / `git log` /
  relevant code.
- Treat this repository as the sole source of project context; do not rely on anything from
  outside it.
- Follow the source-of-truth precedence and the end-of-work continuity requirement in
  `AGENTS.md` — update `docs/CURRENT_STATE.md` before finishing a substantial task.
- Do not deploy, build, push images, or make AWS changes unless the task explicitly asks.
- Preserve existing unrelated working-tree changes.
