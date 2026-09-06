# CLAUDE.md

Start every session by reading **@AGENTS.md** and following it.

- Then follow the documentation reading order it defines
  (README → docs/PROJECT_CHARTER → docs/CURRENT_STATE → docs/ARCHITECTURE →
  docs/ROADMAP → docs/DECISIONS → docs/RUNBOOK), and inspect `git status` /
  `git log` / relevant code.
- Treat the repository documentation as the persistent project context. **Do not assume any
  previous chat history exists.**
- Follow the source-of-truth precedence and the end-of-work continuity requirement in
  `AGENTS.md` — update `docs/CURRENT_STATE.md` before finishing a substantial task.
- Do not deploy, build, push images, or make AWS changes unless the task explicitly asks.
- Preserve existing unrelated working-tree changes.
