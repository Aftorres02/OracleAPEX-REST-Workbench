# APEXlang Example Prompt — Schema Explorer

The prompt below is the first end-to-end test of APEXlang generation for this
project. Paste it verbatim into Claude Code once the APEXlang skill is loaded.

> **Note:** it deliberately builds on Oracle data dictionary views only, so the
> app needs no DDL, no seed data, and no project tables. That keeps this first
> run a test of the generation pipeline rather than of our schema.

---

## Target verified on 2026-09-09

Every value below was read from the live connection, not assumed.

| Item | Value |
| --- | --- |
| SQLcl saved connection | `dev_ai_1` (folder ADB-AI) |
| Database | Oracle AI Database 26ai, 23.26.3.3.0 |
| APEX release | 26.1.4 |
| APEX workspace name | `DEV_AI_1` |
| Parsing schema | `WKSP_DEVAI1` |
| Existing applications | none |

> **Careful:** `WKSP_DEVAI1` is the database schema, not the workspace.
> The workspace APEX actually registers is `DEV_AI_1`. New-app materialization
> fails on the wrong one, so the prompt names `DEV_AI_1`.

---

## The Prompt

```text
Create a new Oracle APEX application called "Schema Explorer" in APEX workspace
DEV_AI_1, using saved SQLcl connection dev_ai_1, and write the APEXlang
artifacts to docs/apexlang-example/app/ in this repository.

Data source: Oracle data dictionary views only. Do not create, assume, or
invent any application tables. Use exactly these views and columns — all of
them verified present on the target instance:

  ALL_OBJECTS  — owner, object_name, object_type, object_id, status,
                 created, last_ddl_time, oracle_maintained
  ALL_TABLES   — owner, table_name, tablespace_name, num_rows, blocks,
                 avg_row_len, last_analyzed, partitioned
  ALL_USERS    — username, user_id, created

Important data shape, measured on the target instance: of 34,391 rows in
ALL_OBJECTS, 28,236 are SYNONYM objects owned by PUBLIC. Synonyms would
swamp every chart and report, so every page below excludes them by default
with object_type != 'SYNONYM', leaving 6,155 objects across 24 types and
23 owners. Users may clear that filter themselves in the report.

Pages:

  Page 1     Home — dashboard. Four KPI cards reading from ALL_OBJECTS,
             each excluding synonyms: total objects, distinct owners,
             distinct object types, and objects whose last_ddl_time falls in
             the last 7 days. Below them, a horizontal bar chart of object
             counts by object_type, excluding synonyms, top 10 types
             descending.

  Page 100   Objects — interactive report over ALL_OBJECTS showing owner,
             object_name, object_type, status, created and last_ddl_time,
             excluding synonyms by default. Highlight rows where
             status = 'INVALID'. Include page items to filter by owner and by
             object_type.

  Page 110   Object Detail — modal dialog opened from a link on object_name in
             page 100. Show the full ALL_OBJECTS row for the selected
             object_id, read-only.

  Page 200   Tables — interactive report over ALL_TABLES showing owner,
             table_name, tablespace_name, num_rows, last_analyzed and
             partitioned.

  Page 9999  Login.

Shared components:

  - A shared list of values for owners, sourced from ALL_USERS (username as
    both display and return value), ordered by username. Use it on the owner
    filter item on page 100.
  - Navigation menu with entries for Home, Objects and Tables.
  - Breadcrumbs on every page.
  - Default authentication and authorization.

Behavior and constraints:

  - Read-only application. No insert, update or delete anywhere.
  - Every page item and region must reference only the columns listed above.
    Ask before guessing any column that is not in that list.
  - Use LF line endings in every .apx file.

Check the APEXlang code before any import. Do not import until I explicitly
approve it.
```

---

## Why this shape

Each element maps to something the APEXlang skill asks for in a well-formed
request — the app, the pages, the components, the data evidence, the desired
behavior, and whether live validation is allowed.

### Naming the workspace

New-app materialization is the one operation that requires an exact APEX
workspace name; runtime discovery cannot infer it. That is why the workspace is
stated explicitly, and why the schema-versus-workspace distinction above
matters.

### Pinning the columns

The skill's own rule is that it must not invent database objects. Listing the
views and their columns turns a schema-dependent request into an authoritative
one, and the instruction to ask rather than guess keeps it that way.

### Excluding synonyms

Without that filter the app is technically correct and practically useless: a
single SYNONYM bar 9 times the height of the next type, an owner breakdown that
is 82 percent PUBLIC, and a report whose first thousand rows are all synonyms.
Excluding them is what turns the dataset into something worth looking at.

### Dropping an invalid-objects metric

The instance currently has zero invalid objects, so a KPI card counting them
would read 0 forever. Row highlighting for INVALID stays on the report, where
it costs nothing and starts working the moment something breaks.

### Page numbering

Page numbers follow the project convention: modules increment by 100, detail
and modal pages by 10 within a module. See the APEX UX rules in the standards
submodule.

### Withholding import

The generation workflow is check-first by design. Stating the approval gate in
the prompt matches the skill's own contract, where import runs only after an
explicit choice.
