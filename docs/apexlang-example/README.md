# APEXlang Example

Sandbox for the project's first Oracle APEX application generated with
APEXlang. Everything related to that first test lives here so it stays separate
from real project code.

| Path | Contents |
| --- | --- |
| [`PROMPT.md`](PROMPT.md) | The prompt that drives generation, plus why it is written that way |
| `app/` | Generated APEXlang artifacts — the `.apx` tree |

---

## What APEXlang produces

An APEXlang application is not a single installable script. It is a tree of
plain-text `.apx` source files, one per component, which SQLcl compiles and
imports into a workspace:

```
app/
  application.apx
  page-groups.apx
  pages/
    p00001-home.apx
    p00100-objects.apx
    ...
  shared-components/
    lovs.apx
    lists.apx
    authentications.apx
    ...
```

---

## Workflow

### Generate

Claude writes the `.apx` tree into `app/` from the prompt. This step needs no
database.

### Check

SQLcl validates the artifacts against the live APEX instance:

```bash
apex validate -input <absolute path to app/>
```

### Import

Only after explicit approval, and in the same authenticated SQLcl session as
the check:

```bash
apex import -input <absolute path to app/>
```

> **Note:** the same-session rule is enforced by the skill, not just convention.
> If the check and the import run in separate sessions, validation has to be
> repeated before the import is allowed.

---

## Environment

Verified on 2026-09-09:

| Component | Required | Installed |
| --- | --- | --- |
| SQLcl | 26.1.2 or newer | 26.2.2.0 |
| Node.js | any current release | 26.8.1 |
| Java | 17 or 21 | 17.0.13 |
| Oracle APEX | 26.1 | 26.1.4 on the target instance |

Target instance: saved SQLcl connection `dev_ai_1` (Oracle AI Database 26ai,
23.26.3.3.0), APEX workspace `DEV_AI_1`, parsing schema `WKSP_DEVAI1`.

The APEXlang skill itself comes from Oracle's plugin marketplace rather than
this repository, so it is not vendored here:

```bash
claude plugin marketplace add oracle/skills
claude plugin install apex@oracle-skills
claude plugin install db@oracle-skills
```

---

## Open items

The generated application uses only Oracle data dictionary views, so it does
not yet exercise the project's own coding standards for tables or packages.

The repository structure rules still describe APEX exports in YAML and `.sql`
format, which predates APEXlang. That mismatch is deliberately unresolved until
this example proves the approach is worth adopting.
