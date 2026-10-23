# ARW (APEX REST Workbench) — Oracle APEX / PL/SQL Code Standards

This file is an **index only**. It does not contain standards content itself.
Detailed standards live under `.claude/rules/` — the shared standards
package, consumed as this project's `.claude/` directory via git submodule.

See `.claude/STRUCTURE.md` for a full explanation of how this configuration
directory is organized (rules vs. agents vs. commands vs. skills vs. hooks).

## Rules (always loaded)

Claude Code loads every `.claude/rules/*.md` file automatically at session
start, so they are listed here for reference only — deliberately **not**
`@`-imported, which would be redundant.

| File | Covers |
|---|---|
| `.claude/rules/sql-format.md` | SELECT/INSERT/MERGE formatting, JOIN alignment, CTEs, optimizer hint formatting |
| `.claude/rules/plsql-standards.md` | Package structure, `%type`, parameter/call formatting, logging, doc tags |
| `.claude/rules/ddl-conventions.md` | Table/constraint naming, data types, audit columns, triggers, seed data |
| `.claude/rules/apex-ux.md` | Error handling, AJAX, process conditions, page/region/button naming, CSS |
| `.claude/rules/security.md` | SQL injection prevention, error-message exposure |
| `.claude/rules/javascript-standards.md` | Module pattern, naming, AJAX, DOM/event handling |
| `.claude/rules/git-workflow.md` | Branch naming, compilation code, PR-only workflow, merge-conflict check, PR/code-review checklist |
| `.claude/rules/repo-structure.md` | Generated-project repo layout, release process pointer, APEX export strategy |
| `.claude/rules/documentation-formatting.md` | Markdown conventions for standalone docs — headings, lists, dividers, callouts |
| `.claude/rules/error-handling.md` | Layer separation between `raise_application_error` (business packages) and `apex_error.add_error` (APEX layer) |
| `.claude/rules/language.md` | English for identifiers, code comments, and every standards file; what may use the team's language |

## Other configuration

- Reviewer/generator subagents: `.claude/agents/`
- Slash commands: `.claude/commands/`
- Multi-step guides: `.claude/skills/`
- Git hooks: `.claude/hooks/`

## Project context

- **Object prefix:** `arw_` for every table, view, and package.

- **Custom error code range:** `-20900` to `-20949` — the project's answer
  to `error-handling.md` §5 (see `docs/base/implementation_plan.md` §0.3).

- **Plan and live status:** `docs/base/implementation_plan.md`. Concept
  and design: `docs/base/CONCEPT.md`, `docs/base/IMPLEMENTATION.md`.
  Planning docs are in Spanish; code and comments stay in English
  (`language.md`).

- **APEX app:** hand-authored APEXlang under `apex/arw/` — see the
  `apexlang-lessons` skill and this repo's environment notes in
  `docs/apexlang_lessons/README.md`.

- **Release process:** `docs/RELEASE.md`.
