# APEX Application Specification — Schema Explorer

## Summary

- Application purpose: Read-only browser over Oracle data dictionary metadata (objects, tables, users) for the target instance.
- Target users: Authenticated APEX workspace users (developers/DBAs reviewing schema metadata). Default authentication/authorization only, no custom roles requested.
- Primary workflows: View dashboard KPIs/chart of object metadata; browse and filter objects; drill into a single object's full dictionary row; browse tables metadata.
- Authoritative sources: User-provided verified data-dictionary column list (ALL_OBJECTS, ALL_TABLES, ALL_USERS) plus the user-provided page/behavior requirements. Both are `user_asserted` (verified by the user against the live target instance on 2026-09-09); no offline schema-dictionary file or data-model export exists in this repository, so there was nothing else to discover during local-context resolution (`workspace probe` returned `discovered_sources: []`).
- Target app path: `docs/apexlang-example/app` (explicit, user-specified — not the standard `applications/` root).
- Runtime mode: live DB check later (check-only; import is explicitly out of scope for this run).
- Destination APEX workspace: `DEV_AI_1` (user-specified; recorded in session `context-resolution.json` under `db_context.workspace`).
- Known exclusions: No insert/update/delete anywhere (read-only app). No columns beyond the exact verified list. No custom roles/authorization schemes (default auth/authz only).

## Requirement Coverage Matrix

| Requirement ID | Requirement Text / Cue | Planned Page / Region / Action | Frozen Plan Reference | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| FR-001 | Page 1 Home dashboard: 4 KPI cards (total objects, distinct owners, distinct object types, changed last 7 days), all excluding synonyms | Page 1 / region `dashboard-kpis` (Metric Card) | Frozen App Plan row Page 1; Frozen Region Plan row 1.10 | covered | user_asserted |
| FR-002 | Page 1: horizontal bar chart of object counts by object_type, excluding synonyms, top 10 descending | Page 1 / region `objects-by-type` (chart, bar, horizontal) | Frozen App Plan row Page 1; Frozen Region Plan row 1.20 | covered | user_asserted; chart orientation confirmed via compiler-truth (`chartAppearance.orientation` = horizontal/vertical, componentTypeId 7810 NATIVE_JET_CHART) |
| FR-003 | Page 100 Objects: IR over ALL_OBJECTS (owner, object_name, object_type, status, created, last_ddl_time), excluding synonyms by default, clearable by the user | Page 100 / region `objects` (interactiveReport) with `savedReport` primaryDefault `filter` (column=OBJECT_TYPE, operator=!=, value=SYNONYM) | Frozen Region Plan row 100.20 | covered | user_asserted; default-report removable filter confirmed via grammar (`filter-a` nested in `savedReport`) |
| FR-004 | Page 100: highlight rows where status = INVALID | Page 100 / region `objects` `highlight` block | Frozen Region Plan row 100.20 | covered | user_asserted |
| FR-005 | Page 100: page items to filter by owner and by object_type | Page 100 / pageItems `P100_OWNER` (shared LOV), `P100_OBJECT_TYPE` (inline SQL LOV) | Frozen Region Plan row 100.10 | covered | user_asserted |
| FR-006 | Page 110 Object Detail: modal dialog opened from a link on object_name on page 100; full ALL_OBJECTS row for selected object_id, read-only | Page 110 / region `object-detail` (form, no `edit` block, no DML process). Launch mechanism resolved to a generic selection button per user decision (option 3, "Botón genérico de selección") after both declarative link mechanisms failed live -- see FR-006 resolution below. | Frozen App Plan row Page 110; Frozen Region Plan row 110.10 | covered | user_asserted; launch mechanism confirmed via live apex validate on dev_ai_1 |
| FR-007 | Page 200 Tables: IR over ALL_TABLES (owner, table_name, tablespace_name, num_rows, last_analyzed, partitioned) | Page 200 / region `tables` (interactiveReport) | Frozen App Plan row Page 200; Frozen Region Plan row 200.10 | covered | user_asserted |
| FR-008 | Page 9999 Login | Page 9999 (materialized by scaffold, unmodified) | Frozen App Plan row Page 9999 | covered | user_asserted / scaffold default |
| FR-009 | Shared LOV for owners, sourced from ALL_USERS (username as display and return), ordered by username; used on Page 100 owner filter | shared-components/lovs.apx `lov owners` | LOVs — Dynamic LOVs | covered | user_asserted |
| FR-010 | Navigation menu with entries for Home, Objects, Tables | shared-components/lists.apx `list navigation-menu` | Application Composition Plan — Navigation menu | covered | user_asserted |
| FR-011 | Breadcrumbs on every page | shared-components/breadcrumbs.apx entries `home`, `objects`, `tables`; Page 110 exempt (modal) | Application Composition Plan — Breadcrumb Hierarchy | covered / excluded (Page 110, Page 9999, Page 0 exempt per workflow rule) | user_asserted |
| FR-012 | Default authentication and authorization | shared-components/authentications.apx (`oracle-apex-accounts`, scaffold default), shared-components/authorizations.apx (scaffold default, unused by pages) | Data/Validation/Behavior — Security | covered | scaffold default |
| FR-013 | Read-only application — no insert/update/delete anywhere | No `edit.enabled`, no `formAutoRowProcessing` / `interactiveGridAutomaticRowProcessing` process anywhere; no Create/Save/Delete buttons | Form Processes and Delete Rules | covered | user_asserted (hard constraint) |
| FR-014 | Every page item/region references only the listed columns; ask before guessing | All SQL below restricted to: ALL_OBJECTS(owner, object_name, object_type, object_id, status, created, last_ddl_time, oracle_maintained), ALL_TABLES(owner, table_name, tablespace_name, num_rows, blocks, avg_row_len, last_analyzed, partitioned), ALL_USERS(username, user_id, created) | Source Evidence Matrix | covered | user_asserted (hard constraint) — no unresolved column needed, so no Missing Inputs stop triggered |
| FR-015 | LF line endings in every .apx file | All generated `.apx` files written with `\n` line endings | Generation Readiness | covered | tool-enforced (see Assumptions) |
| DW-001 | Global Page 0 | Page 0, unmodified scaffold default | Frozen App Plan row Page 0 | covered (derived, scaffold default) | scaffold default |

## Source Evidence Matrix

| Fact Type | Object / Column / Relationship / Behavior | Evidence Source | Evidence Detail | Status | Notes / Conflict |
| --- | --- | --- | --- | --- | --- |
| view | ALL_OBJECTS | user_asserted | Columns used: owner, object_name, object_type, object_id, status, created, last_ddl_time, oracle_maintained (subset of the 9 verified columns; oracle_maintained used only on Page 110's full-row detail) | resolved | none |
| view | ALL_TABLES | user_asserted | Columns used: owner, table_name, tablespace_name, num_rows, last_analyzed, partitioned (subset of the 8 verified columns; avg_row_len and blocks verified but not requested on any page, so intentionally unused) | resolved | none |
| view | ALL_USERS | user_asserted | Columns used: username (display+return), for shared LOV ordering | resolved | none |
| data shape | ALL_OBJECTS row counts (34,391 total; 28,236 PUBLIC SYNONYM; 6,155 / 24 types / 23 owners after exclusion) | user_asserted | Measured by the user on the target instance 2026-09-09; drives the default-exclude-synonyms design and the "top 10 types" chart cap | resolved | none |
| SQL-bearing | Page 1 KPI region `dashboard-kpis` | user_asserted | `select ... from all_objects where object_type != 'SYNONYM' [and last_ddl_time >= sysdate - 7]` | resolved | none |
| SQL-bearing | Page 1 chart region `objects-by-type` | user_asserted | `select object_type, count(*) from all_objects where object_type != 'SYNONYM' group by object_type order by count(*) desc fetch first 10 rows only` | resolved | none |
| SQL-bearing | Page 100 IR region `objects` | user_asserted | `select owner, object_name, object_type, object_id, status, created, last_ddl_time from all_objects` plus bind-driven owner/object_type equality filters; synonym exclusion applied via removable default-report filter, not baked into the WHERE clause | resolved | none |
| SQL-bearing | Page 100 pageItem `P100_OBJECT_TYPE` inline LOV | user_asserted | `select distinct object_type, object_type from all_objects where object_type != 'SYNONYM' order by object_type` | resolved | none |
| SQL-bearing | Page 110 form region `object-detail` | user_asserted | `select owner, object_name, object_type, object_id, status, created, last_ddl_time, oracle_maintained from all_objects where object_id = :P110_OBJECT_ID` | resolved | none |
| SQL-bearing | Page 200 IR region `tables` | user_asserted | `select owner, table_name, tablespace_name, num_rows, last_analyzed, partitioned from all_tables` | resolved | none |
| SQL-bearing | shared LOV `owners` | user_asserted | `source.tableName: ALL_USERS`, `columnMapping.return/display: USERNAME`, `defaultSort: USERNAME` | resolved | none |
| target page / target item / key column | Page 100 `objects.object_name` link -> Page 110 | user_asserted | `link.target.page: 110`, `items: { P110_OBJECT_ID: #OBJECT_ID# }`, key column OBJECT_ID | resolved | none |

Stop conditions checked: no same-rank source conflicts found; no required object/column/relationship/page/item/compiler-truth decision remained unresolved (the two decisions that needed compiler-truth — chart bar orientation, and the default-report removable filter mechanism — were both resolved with direct compiler/grammar evidence, see Rich UI Pattern Plan and FR-003 evidence above).

## Deterministic Planning Rules Applied

- FR order (as given in the user's page list) drives page order: 1, 100, 110, 200, 9999, plus scaffold-derived Page 0.
- Page 110 (drill/detail page) is placed immediately after its source page 100, consistent with the deterministic ordering rule.
- Column order on Page 100 / Page 200 IRs follows the exact order given in the requirement text (not schema order), since FR is explicit about display order.
- Simple single-object reports (Page 200) default to a `sqlQuery` source rather than `tableName` because ALL_TABLES is a foreign dictionary view, not an owned table — using `sqlQuery` keeps the region unambiguously read-only and avoids implying DML capability.

## Canonical Frozen Plans

### Frozen Application Plan

| Page | Name | Group | Type / Native Pattern | Page Mode | Menu | Breadcrumb Entry | Requirement ID | Primary Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | Global Page | none | Global Page | Normal | No | exempt | DW-001 | none |
| 1 | Home | none | Dashboard (Metric Card strip + chart) | Normal, user-facing | Yes (Home) | home (root) | FR-001, FR-002 | ALL_OBJECTS (sql) |
| 100 | Objects | none | Interactive Report | Normal, user-facing | Yes (Objects) | objects (parent: home) | FR-003, FR-004, FR-005 | ALL_OBJECTS (sql) |
| 110 | Object Detail | none | Read-only Form / detail | Modal Dialog | No | exempt (modal) | FR-006 | ALL_OBJECTS (sql, single row) |
| 200 | Tables | none | Interactive Report | Normal, user-facing | Yes (Tables) | tables (parent: home) | FR-007 | ALL_TABLES (sql) |
| 9999 | Login | none | Login | Normal, login/global | No | exempt | FR-008 | none |

Per-page notes:
- Page 1: exists to satisfy FR-001/FR-002 (dashboard). User-facing. Template family: `dashboard-page` construction pack. No compiler-truth question remained open (chart orientation resolved).
- Page 100: exists to satisfy FR-003/FR-004/FR-005. User-facing. Template family: `interactive-report-page`. Compiler-truth question (default removable filter shape) resolved via grammar evidence for `savedReport`/`filter`.
- Page 110: exists to satisfy FR-006 (drill-down detail). Modal/dialog, launched from Page 100 via a Select column (per-row radio) plus a page-level "View Detail" button and a JavaScript-backed dynamic action (see FR-006 resolution below), not a report/column link. Form presentation: standard modal dialog (`@/modal-dialog`), not a drawer — the requirement explicitly says "modal dialog," which overrides the report-to-form drawer default in the workflow rules. Template family: `modal-dialog.basic` page layout + `form.basic` region, with the create/update/delete portions of that pack intentionally omitted (read-only deviation, see Assumptions).
- Page 200: exists to satisfy FR-007. User-facing, standalone (no drill-down requested). Template family: `interactive-report-page` (link/highlight/savedReport-filter omitted — not requested).
- Page 9999 / Page 0: scaffold defaults, unmodified; login/global pages are exempt from breadcrumb and menu requirements.

### Frozen Region Plan

| Page | Order | Region Name | Native Component Family | Parent/Child Role | Source Shape | Source Object / Query Intent | Layout Recipe | Columns / Display Mappings | Links / Actions | Filters | Refresh / Context |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 10 | breadcrumb-bar | breadcrumb region | none | none/staticContent | breadcrumb `@breadcrumb` entry `home` | kpi-strip precedes this in slot order; breadcrumb occupies REGION_POSITION_01 | n/a | none | none | none |
| 1 | 20 | dashboard-kpis | Metric Card (themeTemplateComponent/metricCard) | none | sql | 4-row UNION ALL over ALL_OBJECTS (excl. synonyms): total objects, distinct owners, distinct object types, changed last 7 days | kpi-strip (metric-card-strip) | ID, TITLE, METRIC, META | none | none | none |
| 1 | 30 | objects-by-type | chart (bar, horizontal) | none | sql | object_type, count(*) from ALL_OBJECTS excl. synonyms, top 10 desc | single full-width chart row | LABEL=object_type, VALUE=count | none | none | none |
| 100 | 5 | breadcrumb-bar | breadcrumb region | none | none/staticContent | breadcrumb `@breadcrumb` entry `objects` | breadcrumb row | n/a | none | none | none |
| 100 | 10 | {filters} | static content host for filter items | none | none/staticContent | n/a (hidden-style filter host region) | filter row above IR | n/a | none | P100_OWNER, P100_OBJECT_TYPE | submits to `objects` IR |
| 100 | 20 | objects | interactiveReport | none | sql | owner, object_name, object_type, object_id (hidden), status, created, last_ddl_time from ALL_OBJECTS | IR body | apex$select_row (radio, synthetic), owner, object_name, object_type, status, created, last_ddl_time (visible); object_id (hidden) | Select column (radio) + page-level `VIEW_DETAIL` button -> Page 110, via JS dynamic action (see FR-006 Resolution) | bind filters via `source.pageItemsToSubmit`; default-report filter excludes SYNONYM (removable) | dialog-close refresh (Page 110 closes -> refresh `objects`) |
| 110 | 10 | object-detail | form (read-only) | none | sql | full ALL_OBJECTS row where object_id = :P110_OBJECT_ID | single-column detail layout | owner, object_name, object_type, object_id, status, created, last_ddl_time, oracle_maintained (all display-only) | none | none | fetched once via `formInitialization`, no DML |
| 200 | 5 | breadcrumb-bar | breadcrumb region | none | none/staticContent | breadcrumb `@breadcrumb` entry `tables` | breadcrumb row | n/a | none | none | none |
| 200 | 10 | tables | interactiveReport | none | sql | owner, table_name, tablespace_name, num_rows, last_analyzed, partitioned from ALL_TABLES | IR body | owner, table_name, tablespace_name, num_rows, last_analyzed, partitioned | none | none | none |

Region names above are frozen and reused exactly in the `.apx` artifacts, breadcrumb links, and this app-ux-contract mirror.

## Application Composition Plan

- Application scope: single new APEX application "Schema Explorer," 5 user-relevant pages (0, 1, 100, 110, 200, 9999).
- Artifact scope: `application.apx`, `page-groups.apx`, `pages/p00000-*.apx` (scaffold), `pages/p00001-home.apx`, `pages/p00100-objects.apx`, `pages/p00110-object-detail.apx`, `pages/p00200-tables.apx`, `pages/p09999-login.apx` (scaffold), `shared-components/{breadcrumbs,lists,lovs,authentications,authorizations,build-options,component-settings,static-files}.apx`, `shared-components/themes/universal-theme/theme.apx`, `supporting-objects/*`, `deployments/default.json`.
- Page groups: none requested; scaffold's default `administration` page group left untouched and unused (no pages assigned to it).
- Shared LOVs: `owners` (ALL_USERS, dynamic/table-sourced).
- Navigation menu: Home, Objects, Tables (in that order), each with a conservative `fa-*` icon.
- Static files/icons: scaffold default app icons, unmodified.
- Plan-to-artifact traceability: every row in the Frozen Application/Region Plans above maps 1:1 to a named `.apx` block; no additional pages/regions were added beyond what is listed.

### Management Or Launch Hub Entries

None — this app has no hub/launcher page; navigation is a flat 3-entry menu (Home, Objects, Tables).

### Breadcrumb Hierarchy

| Page | Entry | Root | Parent Entry | Parent Page | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | home | true | — | — | FR-011 |
| 100 | objects | false | home | 1 | FR-011 |
| 200 | tables | false | home | 1 | FR-011 |
| 110 | (exempt — modal dialog) | — | — | — | workflow rule: modal/dialog pages are exempt |
| 9999 | (exempt — login) | — | — | — | workflow rule: login pages are exempt |
| 0 | (exempt — global) | — | — | — | workflow rule: page 0 is exempt |

## Behavior Coverage

### FR-006 Resolution: Object Detail Launch Mechanism

Both declarative Interactive Report link mechanisms failed live validation against `dev_ai_1` (build 26.1.0+3102):

- Region-level link (`region.link { linkColumn: customTarget target: {...} linkIcon: ... }`) — rejected by a hardcoded packaged-tool rule (`REPORT_REGION_LINK_BLOCK_UNSUPPORTED_001`).
- Column-level link (`column.link { target: {...} linkText: ... }`) — accepted by local static checks and matches the package's own canonical example, but **live `apex validate` rejected it**: `Invalid property: target` / `Invalid property: linkText` (confirmed twice).

Given no supported native Interactive Report row-link exists for this build, the user selected option 3 ("Botón genérico de selección"): a generic page-level button that acts on whichever row is currently selected. Resolved implementation, confirmed live-clean:

1. **Selection affordance**: `column APEX$SELECT_ROW` (synthetic identifier, exempt from source-projection matching per the `apex$` prefix convention used throughout this DSL) renders one native HTML radio input per row via `columnFormatting.htmlExpression` (`<input type="radio" name="P100_SELECT_ROW" value="#OBJECT_ID#" ...>`), an APEX-native, declarative "Column HTML Expression" (per apex-ux.md's own endorsed alternative to embedding markup in SQL) — not raw SQL-concatenated HTML. This is a deliberate substitute for the DSL's own IR "Row Selector" column type/`rowSelection.currentSelectionPageItem` feature, which exists at the raw Oracle APEX metadata level (confirmed via compiler-truth componentTypeId 7030) but has no supported authoring path through this packaged DSL's own schema (`assets/component-attributes.json` fixes `interactiveReport.column.allowedBlocks` with no `rowSelection` entry, and the local linter hard-rejects the block).
2. **Button**: page-level `button view-detail (buttonName: VIEW_DETAIL label: View Detail)` in the `objects` region's `RIGHT_OF_IR_SEARCH_BAR` slot, `behavior.action: definedByDynamicAction` (per apex-ux.md button-naming convention: static id/buttonName matches the label, uppercase).
3. **Dynamic action**: `dynamicAction open-object-detail`, `when { event: click selectionType: button button: @view-detail }`, one `action: executeJsCode` reading the checked radio (`$("input[name='P100_SELECT_ROW']:checked").val()`) and either calling `apex.navigation.dialog(...)` with a hand-built `f?p=` URL targeting page 110 (`P110_OBJECT_ID` item) when a row is selected, or `apex.message.showErrors(...)` when none is selected (per this project's javascript-standards.md conventions and this task's explicit instruction to use `apex.message` for the no-selection case).
4. **Close refresh**: `dynamicAction refresh-objects-on-close` (`apexafterclosedialog` -> refresh `@objects`) retained per the general project rule that every report opening a modal page needs a close-refresh; `apex.navigation.dialog()` still fires this event on the originating page, matching declarative-link behavior.

Known local-lint false positive from this design: `apexlang validate`'s `MODAL_REPORT_LAUNCH_REQUIRED_001`/`page_has_modal_launcher` heuristic can only recognize a `link` block or a button with `behavior.action: redirectThisApp` as a "launcher" — it cannot see into `executeJsCode` JavaScript strings, so it still reports "no declarative report link or page/report button to a modal page" even though the live database round-trip (`apex validate`) passes cleanly with this exact structure. This is an inherent, unavoidable heuristic gap for any JS-driven dynamic navigation target (the button's destination row is only known at click time, so a static `redirectThisApp` target could never have carried it anyway).

### Modal Targets And Cross-Page Links

| Source Page | Source Region / Column / Action | Target Page | Target Items | Key Column | Presentation | Close Refresh Region | Requirement ID |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 100 | `objects` region, `APEX$SELECT_ROW` radio selection + `VIEW_DETAIL` button, via `open-object-detail` dynamic action (`executeJsCode` + `apex.navigation.dialog`) | 110 | `P110_OBJECT_ID: <selected row's object_id>` | OBJECT_ID | Standard modal dialog (JS-invoked, not a declarative link) | `objects` (Page 100) | FR-006 |

### Page-Level Actions

| Page | Label | Target Page | Item Mappings | Placement | Requirement ID |
| --- | --- | --- | --- | --- | --- |
| 100 | View Detail (`VIEW_DETAIL`) | 110 (via JS, not a declarative target) | `P110_OBJECT_ID` set from the selected row's `object_id` at click time | Interactive Report toolbar (`RIGHT_OF_IR_SEARCH_BAR`) | FR-006 |

### Parent-Child Context And Action Coverage

None. There is no master-detail relationship in this app; Page 100 -> Page 110 is a plain read-only report-to-detail drill-down (single-row selection + button, no same-page parent context item, no child-region refresh-on-select behavior — Page 110 is a separate modal page, not an inline child region).

### Form Validations, Context, And Defaults

| Page | Item | Behavior Type | Message / Source | Required When / Trigger | Editable / Visible | Requirement ID |
| --- | --- | --- | --- | --- | --- | --- |
| 110 | P110_OBJECT_ID | context | Populated by the `f?p=` URL built client-side in Page 100's `open-object-detail` dynamic action from the selected row's `object_id` | Always, on page load (when reached via the View Detail flow) | Hidden, not user-editable (drives the read-only row fetch) | FR-006 |
| 100 | (validation) | validation | "Select a row before choosing View Detail." via `apex.message.showErrors(...)` | When View Detail is clicked with no row selected | n/a (client-side message, not a page item) | FR-006 |

No other validations/defaults apply — the app has no editable form fields anywhere.

### Form Processes And Delete Rules

| Page | Form Region | Process Intent | Create | Update | Delete | Delete Restrictions | Requirement ID |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 110 | object-detail | None (read fetch only via `formInitialization`; no Automatic Row DML) | No | No | No | N/A — read-only app, no delete anywhere | FR-006, FR-013 |

### Refresh Dependencies

| Event Source | Event | Affected Region / Item | Refresh / Set-Value Behavior | Requirement ID |
| --- | --- | --- | --- | --- |
| Page 110 (dialog) | `apexafterclosedialog` | Page 100 `objects` region | Refresh region | FR-006 |

### Security, Guidance, And Empty States

| Page / Region / Item | Coverage Type | Planned Behavior / Text | Evidence | Requirement ID |
| --- | --- | --- | --- | --- |
| Application | authorization | Default authenticated-user assumption; no custom roles requested | user_asserted | FR-012 |
| 100 / `objects` | no-data | Default IR "No data found." message | scaffold/native default | n/a |
| 200 / `tables` | no-data | Default IR "No data found." message | scaffold/native default | n/a |
| 100, 200 filter items | help | Concise help text on each visible filter/select item per project item-documentation convention | user_asserted (item template contract) | FR-005 |

### Map Marker Targets And Viewport

None — no map pages in this app.

## Rich UI Pattern Plan

| Pattern | Page / Region | Native APEX Component | Evidence | Generation Notes |
| --- | --- | --- | --- | --- |
| KPI / metric card strip | Page 1 / `dashboard-kpis` | `themeTemplateComponent/metricCard`, `componentAppearance.display: report`, one UNION ALL row per KPI | FR-001; `metric-card._common.md` | 4 cards, `appearance.template: @/blank-with-attributes` (no visible chrome, per dashboard KPI default) |
| Bar chart, horizontal | Page 1 / `objects-by-type` | `region type: chart`, `chart.type: bar`, `chartAppearance.orientation: horizontal` | FR-002; compiler-truth componentTypeId 7810 (NATIVE_JET_CHART) confirms `chartAppearance.orientation` enum `vertical`/`horizontal` | Single series, legend hidden (only one series), x/y axis per `chart.bar.md` |
| Interactive report with default removable filter | Page 100 / `objects` | `region type: interactiveReport` + `savedReport (visibility: primaryDefault)` containing a `filter (type: column, column: OBJECT_TYPE, operator: !=, value: SYNONYM)` | FR-003; grammar evidence `filter-a` nested under `saved-report-a-child-component` | Ships pre-filtered; user can remove the filter chip from the IR toolbar without any code change |
| Row highlight | Page 100 / `objects` | `highlight` block, `condition { column: STATUS, operator: =, value: INVALID }` | FR-004; `interactive-report-page.example.md` highlight pattern | Background color signals invalid objects |
| Generic row-selection button (declarative row link substitute) | Page 100 / `objects` | `column APEX$SELECT_ROW` (`type: plainText`, `columnFormatting.htmlExpression` radio input) + `button VIEW_DETAIL` + `dynamicAction` (`executeJsCode`) | FR-006; confirmed compiler-truth componentTypeId 7030 has a native `NATIVE_ROW_SELECTOR` column type with no supported APEXlang authoring path (schema/local-lint reject it); live apex validate confirms this radio+button+JS substitute | User-selected resolution (option 3) after both declarative link mechanisms failed live; see Behavior Coverage FR-006 Resolution |
| Read-only detail (single-row form, no DML) | Page 110 / `object-detail` | `region type: form`, `source.type: sqlQuery`, no `edit {}` block, `displayOnly` items, `formInitialization` process only | FR-006, FR-013 | Deliberate deviation from the `report-modal-form` pack's default (which assumes CRUD): no Create button, no `formAutoRowProcessing` process, all items `displayOnly` |
| Plain interactive report | Page 200 / `tables` | `region type: interactiveReport` | FR-007 | No filters/links/highlights requested, so none added |

Dashboard KPI details are implemented as one Metric Card region (not a Classic Report), per the mandatory dashboard KPI rule.

## LOVs

### Static LOVs

None.

### Dynamic LOVs

| LOV | Display Column | Return Column | Source Object | Evidence | Consuming Pages / Items |
| --- | --- | --- | --- | --- | --- |
| `owners` (shared component) | USERNAME | USERNAME | ALL_USERS | FR-009 | Page 100 `P100_OWNER` |
| Page 100 object-type filter (inline, page-item-level SQL LOV — not a shared component; not requested to be shared) | OBJECT_TYPE | OBJECT_TYPE | ALL_OBJECTS (`select distinct object_type ... where object_type != 'SYNONYM' order by object_type`) | FR-005 | Page 100 `P100_OBJECT_TYPE` |

Both filter items use `lov.displayNullValue: true` with `nullDisplayValue: &SELECT_LABEL.` (project item-null-label convention) so users can clear either filter back to "no filter."

## Data, Validation, And Behavior

- Required fields: none (no forms with required input; Page 110 is read-only).
- Optional fields: Page 100 filters (`P100_OWNER`, `P100_OBJECT_TYPE`) are both optional/clearable.
- Conditional validations: none.
- Context-owned hidden/display-only items: Page 110 `P110_OBJECT_ID` (hidden, launch-context, drives the row fetch).
- Defaulted items and override policy: none.
- Foreign keys: none (dictionary views have no FK metadata surfaced by the allowed column list).
- Check constraints: none (not our schema).
- Date/time handling: `created` and `last_ddl_time` are DATE columns; displayed using the IR/form defaults (no custom format mask requested).
- Derived metrics and totals: Page 1 KPIs (counts/distincts) and chart aggregate (`count(*)` by object_type).
- Delete restrictions: N/A, read-only app.
- Report-to-form behavior: Page 100 -> Page 110 opens read-only, closing the dialog refreshes the Page 100 report; no save/return-value flow (no DML).
- Modal return behavior: none (no data is written back).
- Security and authorization assumptions: default APEX authentication scheme (`oracle-apex-accounts` scaffold default) and default authorization; no page/region-level authorization scheme requested or added.
- Help, accessibility, and guidance text: help text on Page 1/100/200 report regions (per interactive-report page-example convention) and on the two filter items.
- No-data and empty-state behavior: native IR default "No data found." messages; no custom empty-state copy requested.

## Plan Consistency Gate

- Every requirement row (FR-001 .. FR-015, DW-001) is covered or explicitly noted as a scaffold default / exempt by workflow rule; none are unresolved or silently dropped.
- Every DB object/column used in the frozen plan is limited to the exact verified column list; the Source Evidence Matrix cites each one.
- Every frozen page (0, 1, 100, 110, 200, 9999) has a page inventory entry mirrored in `app-ux-contract.json`.
- Every frozen region has a page-local entry in the Frozen Region Plan and a native component family.
- Every source mode decision is frozen as `sql` (Pages 1, 100, 110, 200) or `none/staticContent` (breadcrumb/filter host regions).
- The one link/modal target (Page 100 -> Page 110) and its one refresh dependency are declared above and mirrored in `app-ux-contract.json`.
- The one shared LOV and all three breadcrumb entries are declared above before artifact drafting.
- No generated artifact adds, removes, renames, or reorders pages/regions/actions/LOVs/breadcrumbs/source shapes beyond what is frozen here.

## Generation Readiness

- Required canonical templates or construction packs: `dashboard-page` (Page 1), `interactive-report-page` (Pages 100, 200), `modal-dialog.basic` + `form.basic` (Page 110, DML portions omitted), `metric-card` template component, `chart.bar`, `select-list.lov-shared` / `select-list._common` (filter items), `display-only.standard` (Page 110 items), `lovs.dynamic.table` (shared LOV), `breadcrumb-entries` / `list-entries` (shared components), `breadcrumb.standard` (in-page breadcrumb region).
- Required compiler-truth queries: region componentTypeId 5110 (`NATIVE_SVG_CHART`/`NATIVE_IR` when-clauses) confirming group surface; componentTypeId 7810 (`NATIVE_JET_CHART` attributes) confirming `chartAppearance.orientation`; pageItem componentTypeId 5120 (`NATIVE_SELECT_LIST` when-clause) confirming `lov.nullDisplayValue`/`nullReturnValue`. All captured above with evidence.
- Required local validation: `apexlang format --strict-structure`, `apexlang validate`, `apexlang grammar audit` (per component), `apexlang compiler-truth audit`.
- Required live validation: `runtime validate` (SQLcl-backed, check-only) against `db_connection_name: dev_ai_1`, workspace `DEV_AI_1`.
- Import eligibility blockers: none technical, but import is explicitly out of scope for this run per the user's instruction ("Check the APEXlang code before any import. Do not import until I explicitly approve it."). This is a hard stop enforced by the operator, not a tooling limitation.

## Test Plan

| Scenario | Requirement / Acceptance Criteria | Pages / Regions | Expected Result | Validation Method |
| --- | --- | --- | --- | --- |
| Dashboard loads | FR-001, FR-002 | Page 1 | 4 KPI cards + horizontal bar chart render without error, synonyms excluded | Live `runtime validate` (check-only) |
| Objects report default state | FR-003, FR-004 | Page 100 | IR shows non-synonym objects by default, INVALID rows highlighted, filter chip removable | Live `runtime validate` (check-only) |
| Owner/type filters | FR-005, FR-009 | Page 100 | Selecting an owner or object type narrows the report; clearing returns to unfiltered (within the default-report scope) | Local validation + live check-only |
| Object detail drill-down | FR-006 | Page 100 -> Page 110 | Selecting a row's radio button, then clicking View Detail, opens a read-only modal with the full row for that object_id; closing refreshes Page 100. Clicking View Detail with no row selected shows an error message instead of navigating. | Local validation + live check-only |
| Tables report | FR-007 | Page 200 | IR shows the 6 required ALL_TABLES columns | Local validation + live check-only |
| Read-only guarantee | FR-013 | All pages | No Create/Save/Delete controls exist anywhere; grammar/compiler-truth audit confirms no `edit.enabled`/DML process nodes | `apexlang grammar audit`, `apexlang compiler-truth audit` |
| Column allowlist | FR-014 | All pages | Every `column`/`source.databaseColumn`/SQL projection traces to the verified list | Source Evidence Matrix cross-check (manual, this spec) |
| Navigation and breadcrumbs | FR-010, FR-011 | All user pages | Home/Objects/Tables menu entries present; breadcrumb trail correct on Pages 1/100/200 | Local validation |

## Assumptions

Low-risk assumptions only:

- Chart type `bar` in this DSL renders as APEX's native JET "Bar" chart; the requirement's "horizontal bar chart" is satisfied by the compiler-confirmed `chartAppearance.orientation: horizontal` property rather than a different chart type token.
- The "excludes them by default... clear that filter themselves" behavior is implemented as a native APEX Interactive-Report default-report filter (removable in the IR UI) on Page 100 only, since Page 100 is the only page in this app with the interactive report filter-chip mechanism the requirement describes. The Page 1 KPI/chart SQL hardcodes `object_type != 'SYNONYM'` directly (no interactive "clear filter" affordance exists for metric cards or standalone charts in Oracle APEX), and Page 200 has no synonym-exclusion requirement at all (it queries ALL_TABLES, which has no synonym rows).
- `.apx` files are written with LF line endings by direct file authoring (the local file-write path used does not introduce CRLF); this was not separately re-verified with a byte-level tool pass but is the default behavior of the write tooling used.
- No custom authorization scheme was requested, so Page 100/110/200 rely on the application's default authentication only (any authenticated workspace user can view all pages) — consistent with "Default authentication and authorization."
- The Select column's radio input (`APEX$SELECT_ROW`) is single-select by name-grouping (`name="P100_SELECT_ROW"` shared across all rows), so only one row can be checked at a time; there is no native declarative "row selector" enforcement of this (see FR-006 Resolution), it relies on standard HTML radio-group semantics.
- `apex.navigation.dialog()` invoked from client-side JS (rather than a declarative link/button target) still triggers the standard APEX modal-dialog lifecycle, including firing `apexafterclosedialog` on the originating page — this was not separately unit-tested beyond the live `apex validate` structural pass (which does not execute the running page), but is standard, documented Oracle APEX client-side API behavior.

## Missing Inputs / Blockers

- Planning blockers: none.
- Generation blockers: none. The one open item from the initial generation pass — how to launch Page 110 from Page 100 — is now resolved; see "FR-006 Resolution: Object Detail Launch Mechanism" under Behavior Coverage. Both declarative Interactive Report link mechanisms (region-level and column-level) were confirmed to fail live `apex validate` against `dev_ai_1` (build 26.1.0+3102); the user selected option 3 ("Botón genérico de selección") as the resolution, implemented as a radio-button Select column + `VIEW_DETAIL` page-level button + `executeJsCode` dynamic action, and this exact structure has passed live check-only validation twice (with and without the close-refresh dynamic action re-added).
- Live validation/import blockers: none for check-only validation. Import is intentionally not attempted in this run (operator instruction), not because of a technical blocker.
- Known, triaged tool false positives (not real defects, documented for the reviewer):
  1. `apexlang format --strict-structure` flags "structural block must be multiline" / "properties must occupy separate lines" on lines whose *values* legitimately contain parentheses, braces, or extra colons (the `name: "{filters}"` hidden-region convention from apex-ux.md, the mandatory multi-colon `comments: Display Label: ... Read Only: ...` column-documentation convention from `interactive-report._columns._common.md`, the `HH24:MI:SS` time format mask, and the single-line `// layout_row_plan: [...]` trace comment required by `APP_UX_LAYOUT_RECIPE_REQUIRED_001`) -- the same false positives reproduce verbatim on the untouched scaffold's own `pages/p09999-login.apx`, proving they are pre-existing formatter limitations, not authoring defects.
  2. `apexlang compiler-truth audit` flags `series`/`axis` under `region` (chart) and `filter` under `region` (should be under `savedReport`) as "not valid under parent region" -- this is the known "attributes" flattening gap documented in `chart._common.md` itself (chart/series/axis/savedReport/filter are modeled by the compiler under an implicit `attributes` node that is never written literally in `.apx` text), independently confirmed via direct compiler-metadata queries (componentTypeId 7810/7820/7830/7050/7055) and via `apexlang validate` passing cleanly on the same structure.
  3. `apexlang validate`'s `MODAL_REPORT_LAUNCH_REQUIRED_001` reports "no declarative report link or page/report button to a modal page" for Page 100 even after the FR-006 resolution, because its `page_has_modal_launcher` heuristic only recognizes a `link` block or a button with `behavior.action: redirectThisApp` — it cannot detect the JS-driven navigation inside `executeJsCode`. Confirmed via live `apex validate` (twice) that the actual structure is accepted by the real database/APEX metadata layer regardless of this local heuristic gap.
