# APEXlang Lessons — This Repo's Environment

The generic APEXlang authoring lessons that used to live in this file
(generation-speed tradeoffs, grammar gotchas, row-level-action pitfalls,
compiler-truth false positives, known packaged-tooling bugs, suggested
build flow) now live in the shared standards package so every project
consuming it benefits:
[`.claude/skills/apexlang-lessons/SKILL.md`](../../.claude/skills/apexlang-lessons/SKILL.md).
Read that first — it's not a replacement for the packaged Oracle skill
(`apex:apex` → `apexlang`) either, same as before.

This file now only keeps what's specific to **this** repo: worked examples
already here, and this project's own connection/environment details.

Worked examples already in this repo, worth reading before starting a new
app:

| Path | What it shows |
| --- | --- |
| [`../apexlang-example/`](../apexlang-example/) | Full app over dictionary views — pages, filters, LOVs, modal detail page |
| [`../simple_appp/`](../simple_appp/) | Minimal one-page app — smallest possible scaffold |

---

## This repo's environment

- Saved SQLcl connection alias: `AI_dev_ai_1` (underscore, not a space --
  an earlier pass of this doc had it as `AI dev_ai_1`, which is not a
  connection SQLcl recognizes and fails with "Unknown connection"; nested
  under the `ADB-AI` folder in `connmgr list`. The bare name `dev_ai_1`
  also resolves to "Unknown connection". Corrected and re-verified
  2026-09-21 by connecting non-interactively and running a live query) --
  an Oracle Cloud wallet connection (Autonomous Database), stored under
  `~/.dbtools/connections/<id>/` (shared store — SQLcl, SQL Developer, and
  the VS Code Oracle extension all read/write it there).
- Targets APEX workspace `DEV_AI_1`, database schema `WKSP_DEVAI1`.
- Every `deployments/default.json` in this repo's APEXlang apps should point
  at that same workspace name unless a new prompt explicitly names a
  different target.

Check and import, always from a terminal (not from inside an agent
session), in the same SQLcl session:

```bash
sql -name "AI_dev_ai_1"
```

```sql
apex validate -input <absolute path to the app/ folder>
apex import -input <absolute path to the app/ folder>   -- only after explicit approval
```

> **Note:** connect with `sql -name "AI_dev_ai_1"`, not `sql -s dev_ai_1`.
> The `-s` (silent) form combined with a piped script hung indefinitely in
> this environment; `-name` is also the exact connect order the packaged
> tooling itself falls back to (`sql -name <name>` → `sql <name>` → `sql
> /nolog` + `connect <name>`). The `--db-connection-name dev_ai_1` values
> below are a separate tool (`apexctl.mjs`) that was not re-verified against
> this corrected alias — check it directly before trusting it.

The packaged CLI wraps the same two gates with structured JSON evidence:

```bash
cd <apexlang skill package root>   # where tools/apexctl.mjs lives
node tools/apexctl.mjs runtime validate --app-path <absolute app/ path> --db-connection-name dev_ai_1

# only after explicit approval -- this is the real import, not another check:
node tools/apexctl.mjs runtime roundtrip --app-path <absolute app/ path> --db-connection-name dev_ai_1 \
  --import-intent validate-and-import --target-resolution-mode create-new --create-new-confirmed
```

`--target-resolution-mode create-new --create-new-confirmed` is required the
first time an app is imported — without it the roundtrip blocks with
`import_status: blocked` / `not_found_in_workspace`, because the tool
refuses to guess whether a brand-new app is really intended.

> **Correction (2026-09-09):** an earlier version of this note claimed
> re-running the roundtrip import was "idempotent by alias." That was
> wrong — it looked true after three back-to-back `create-new` runs
> produced no duplicate, but the actual cause turned out to be that the
> `runtime roundtrip` wrapper can report `import_status: pass` **without
> the underlying `apex import` ever running** (its own transcript showed
> `Could not get workspace name`, then a plain disconnect — no import
> attempted, no error surfaced). The three earlier "successful" reruns were
> likely three more silent no-ops on top of the one real import, not three
> real idempotent imports. **Always verify the live result directly**
> (query `apex_applications`, or diff the component you changed) — don't
> trust `import_status`/`live_check_status` alone as proof anything was
> written.
>
> Separately: **raw `apex import -input <path>` (no `-id`) is not
> idempotent by alias at all — it mints a new application id on every
> run**, since this DSL's `application.apx` carries only an alias, not a
> fixed numeric id. Re-importing the same source twice without `-id`
> produces two separate apps in the workspace (confirmed directly: a plain
> re-import created id 114 "SCHEMA-EXPLORER114" alongside the original
> 111 "SCHEMA-EXPLORER", APEX auto-suffixing the alias to avoid a
> collision). To update an app already in the workspace, always target it
> explicitly:
>
> ```sql
> apex import -input <path> -id <existing_application_id>
> ```
>
> Find the existing id first with a direct, read-only query
> (`select application_id, alias from apex_applications where workspace =
> '<workspace>'`) rather than assuming the packaged tool's target
> resolver will find it — in practice it reported `not_found_in_workspace`
> / `candidate_count: 0` every time in this session, including against an
> app that already existed.

It is still a real write against a live workspace either way, so run it
once, deliberately, after the user has actually asked for the import — not
just asked what the command is — and confirm the result by reading the
database back, not by trusting the tool's JSON report.
