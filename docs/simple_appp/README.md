# Simple Demo (APEXlang Speed Test)

A minimal, hand-authored APEXlang application, generated independently and
in parallel with [`../apexlang-example/`](../apexlang-example/) — that one is
the full Schema Explorer build; this one exists to answer a narrower question
fast: can an AI-generated Oracle APEX app be authored end-to-end from a
prompt with no data model at all?

One page. No tables, no views, no reports, no charts.

## What it shows

Page 1 (Home) renders two read-only values:

- **Connected User** — mirrors the built-in `APP_USER` session item.
- **Current Time** — a single PL/SQL expression (`systimestamp`), not a query.

Everything else (global page, login page, theme, navigation, authentication)
is copied unmodified from the APEXlang base-app-structure scaffold, since a
runnable app still needs those regardless of how simple the content is.

## Layout

```
app/
  application.apx
  pages/
    p00000-global-page.apx
    p00001-home.apx          -- the actual content
    p09999-login.apx
  shared-components/
    authentications.apx
    lists.apx                -- nav bar / nav menu
    static-files.apx + icons/
    themes/universal-theme/theme.apx
  deployments/default.json   -- targets workspace DEV_AI_1, same instance as apexlang-example
```

## Status

Generated, not yet checked or imported. Same gate as the sibling example:

```bash
apex validate -input <absolute path to app/>
apex import -input <absolute path to app/>   # only after explicit approval
```
