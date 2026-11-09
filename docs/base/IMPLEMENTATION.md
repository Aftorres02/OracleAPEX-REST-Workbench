# REST Workbench for Oracle APEX — Implementation

> Complements `CONCEPT.md`. Describes what is built as of Nov 2026 (beta,
> after the `PHASE2-simplified-app` simplification). Step-by-step progress and
> live verifications are in `implementation_plan.md`.
>
> Prefix `arw_`. Custom error range `-20900` to `-20949`. Reference instance:
> workspace `DEV_AI_1` (schema `WKSP_DEVAI1`), APEX 26.1.4, application 142.

---

## 1. Layered Architecture

```
APEX pages (thin, APEXlang in apex/arw/)
   └─ processes / AJAX  →  arw_*_api  (business facade)
        ├─ arw_collections_api     collections + Drafts collection
        ├─ arw_environments_api    environments and {{...}} variables
        ├─ arw_endpoint_api        requests: headers, params, body, simple auth
        ├─ arw_exec_api            runs the real call and writes the history
        │    ├─ arw_preflight_api  ACL, wallet, version (blocks on failure)
        │    └─ arw_auth_utils     Web Credential static ID (hidden)
        ├─ arw_discover_api        samples + automatic data profile
        ├─ arw_codegen_api         orchestrates generation and the demo app
        │    └─ arw_render_utils   token engine and fragment assembly
        ├─ arw_import_api          Postman v2.1
        ├─ arw_guide_api           guide examples
        ├─ arw_credentials_api     APEX Web Credentials (hidden)
        └─ arw_target_profiles_api target profiles (hidden)
```

Rule: thin pages, thick database. Page processes only call the facade.
Packages use `raise_application_error` and never `apex_error`
(`error-handling.md`).

> **Pending:** the app has no global Error Handling Function yet, so
> `ORA-209xx` errors are shown as-is in the notification.

---

## 2. The Three Axes of Generated Code

The whole generator revolves around this matrix. Each axis is a column in
`arw_endpoints` and a `variant_code` in `arw_code_templates`.

| Axis | Column | Values |
|---|---|---|
| **Target runtime** | `runtime_target_code` | `apex` · `job` · `autonomous` |
| **Engine** | `engine_code` | `apex_web_service` · `apex_web_service_b` · `utl_http` · `dbms_cloud_send_request` |
| **Auth** | `auth_type_code` | `none` · `basic` · `bearer` · `api_key` (header or query) |

The **target runtime** is the variable almost nobody considers, and it changes
the whole code: `p_credential_static_id` does not work in a job without
`apex_session.create_session`. The `job` variant already emits that session.

There are auth fragments for more types (`oauth2_client_credentials`,
`oauth2_password`, `oci`, `mtls`, `sigv4`), but execution inside ARW only
applies the four in the table.

> **Note:** the axes affect the **generated code**. Execution inside ARW
> always uses `apex_web_service.make_rest_request_b`, whatever the
> `engine_code`.

---

## 3. Data Model

16 tables and 3 views. Team standard conventions: identity PK
`<entity>_id`, `varchar2(n char)`, `timestamp with local time zone` for audit,
`active_yn` + `created_by/on` + `last_updated_by/on` + compound trigger +
comments via `execute immediate`.

Table DDL is in `tables/`, triggers in `triggers/`, views in `views/`. Changes
after the base install are additive, re-runnable upgrades in `release/code/`.

### 3.1 Core

| Table | Purpose | Key columns |
|---|---|---|
| `arw_collections` | Postman-like collection grouping | `collection_id`, `name`, `parent_collection_id` |
| `arw_environments` | environment (dev/qa/prod) of a collection | `environment_id`, `collection_id`, `base_url` |
| `arw_env_variables` | `{{...}}` variables | `variable_id`, `environment_id`, `var_name`, `var_value`, `is_secret_yn` |
| `arw_endpoints` | the request | `endpoint_id`, `collection_id`, `name`, `http_method`, `url_path`, `timeout_secs`, `runtime_target_code`, `engine_code`, `auth_*`, `credential_id` |
| `arw_endpoint_headers` | request headers | `header_id`, `endpoint_id`, `header_name`, `header_value`, `is_sensitive_yn` |
| `arw_endpoint_params` | path / query / form | `param_id`, `endpoint_id`, `param_kind_code`, `param_name`, `data_type_code`, `is_required_yn` |
| `arw_request_bodies` | body with tokens | `body_id`, `endpoint_id`, `content_type`, `body_template` (clob) |
| `arw_credentials` | APEX Web Credential metadata (hidden in the UI) | `credential_id`, `auth_type_code`, `apex_credential_static_id` |

Relationship decisions:

- `arw_endpoints` has **no** `environment_id`. The environment is chosen at
  execution time, just like a Postman collection run against different
  environments.

- `url_path` accepts a **full URL**. If it starts with `http(s)://` it is sent
  as-is, without `{{base_url}}` or an environment. If it starts with the
  `base_url` of one of the collection's environments, it is stored as a path.

- **Simple auth** (`release/code/simple_auth_upgrade.sql`): `auth_type_code`,
  `auth_username`, `auth_password`, `auth_token`, `auth_key_name`,
  `auth_key_value`, `auth_key_location_code` (header or query). They accept
  `{{variables}}`.

  > **Known limitation:** these values are stored as plain text. Acceptable in
  > beta with demo data; do not use with real secrets.

- A request without a collection goes to the **Drafts** collection, which is
  created on demand (`arw_collections_api.drafts_collection_id`).

### 3.2 Execution

| Table | Purpose |
|---|---|
| `arw_executions` | history: `request_status_code` (success/error/timeout), `http_status_code`, `elapsed_ms`, request sent with redacted headers, `response_headers`, `response_body_clob` or `response_body_blob` + `response_is_binary_yn` |

`environment_id` is nullable (full-URL requests,
`release/code/absolute_url_upgrade.sql`). An attempt refused by the preflight
is recorded too, as `error`.

### 3.3 Discovery — The Differentiator

| Table | Purpose |
|---|---|
| `arw_response_samples` | observed sample; FK to `arw_executions` (does not duplicate status or body) |
| `arw_data_profiles` | consolidated profile: `row_selector`, `format_code` (`json`), `profile_status_code` (proposal/accepted), `sample_count` |
| `arw_profile_columns` | one row per field: `path_expression`, `data_type_code`, `source_data_type`, `format_mask`, `max_observed_length`, `is_nullable_yn`, `is_primary_key_yn`, `parent_column_id` |

`arw_profile_columns` is the most important table in the system. It feeds the
`json_table`, the APEXlang `dataProfileColumn`, the target DDL and the
package's record type. The nested hierarchy is modeled with
`parent_column_id`.

### 3.4 Generation

| Table | Purpose |
|---|---|
| `arw_target_profiles` | target profile: `object_prefix`, `target_schema`, `trace_mode_code` (none/apex_debug/logger), `audit_enabled_yn`, `instance_type_code`, versions (hidden in the UI) |
| `arw_code_templates` | generator fragments: `template_type_code`, `variant_code`, `section_code`, `sequence_num`, `template_body` |
| `arw_generated_artifacts` | versioned output: `artifact_type_code`, `content`, `checksum`, `version_num`, FKs to endpoint, target profile and data profile |

### 3.5 Guide

| Table | Purpose |
|---|---|
| `arw_guide_examples` | cards on the Examples page: `example_code`, `category_code`, `title`, `summary`, `display_seq`, `endpoint_id` (`release/code/guide_upgrade.sql`) |

### 3.6 Views

| View | Used by |
|---|---|
| `arw_collection_summary_vw` | collections with endpoint and environment counts (Home, page 100) |
| `arw_endpoint_summary_vw` | endpoints with their last execution (page 200) |
| `arw_execution_log_vw` | readable history (pages 400 / 410, Home) |

---

## 4. Packages

Packages only, `%type` anchors, implicit `for` loops, `merge` for upserts,
`gc_scope_prefix := lower($$plsql_unit)||'.'`, JavaDoc and `logger` in every
unit. Source in `packages/` (`.pks` / `.pkb`).

| Package | Responsibility | Errors |
|---|---|---|
| `arw_auth_utils` | resolves the Web Credential `static_id` of an endpoint | `-20900`..`-20902` |
| `arw_endpoint_api` | CRUD of requests, headers, params, body and simple auth (`set_auth`) | `-20910`, `-20911` |
| `arw_exec_api` | runs the real call; see §7 | `-20920`..`-20925` |
| `arw_preflight_api` | environment checklist; `run_preflight` and `preflight_report` (pipelined) | `-20930` |
| `arw_collections_api` | cycle-free collection CRUD; Drafts collection | `-20940`..`-20942` |
| `arw_discover_api` | samples, automatic profile, column editing | `-20943`, `-20944` |
| `arw_codegen_api` | generates artifacts, the `.apx` bundle and the demo app | `-20945`, `-20946` |
| `arw_render_utils` | token substitution and fragment assembly | `-20946` |
| `arw_environments_api` | environments, variables, active environment | `-20947` |
| `arw_target_profiles_api` | target profile CRUD | `-20947` |
| `arw_credentials_api` | creates the real Web Credential with `apex_credential` | `-20948` |
| `arw_import_api` | imports Postman v2.1 | `-20949` |
| `arw_guide_api` | installs and restores the guide examples | — |

> **Note:** the `-20900`..`-20949` range is almost exhausted, and some codes
> are shared between packages (`-20946`, `-20947`). A new package needs a
> wider range or a deliberate reuse of codes.

The `arw_apexlang_api` and `arw_audit_api` packages from the original design
were not created: APEXlang outputs are `arw_code_templates` fragments rendered
by `arw_codegen_api`, and auditing is a procedure inside the generated
package, not an ARW package.

---

## 5. Generation Engine — Hybrid

**Fragments in a table, logic in PL/SQL.** `arw_code_templates` holds 59
fragments (`data/arw_code_templates.sql`, loaded with `merge` from JSON).

Each fragment has:

- `template_type_code`: `plsql_package`, `plsql_block`, `json_table`,
  `table_ddl`, `curl`, `apexlang_rds`, `apexlang_install_script`,
  `apexlang_ai_tool`, `apexlang_automation`.

- `variant_code`: the axis value it applies to (`default`, `basic`, `bearer`,
  `api_key_header`, `job`, `utl_http`, `profile`, `raw`...).

- `section_code` + `sequence_num`, assembled in this order:

```
spec → declaration → headers → auth → invocation → status → parsing → footer
```

What is **not** text lives in PL/SQL: type inference, the nested hierarchy,
length calculation and variant selection.

Benefit: adding a new auth type = inserting rows, not recompiling.

### Auth in the Generated Code

`arw_codegen_api` turns the request's simple auth into a "virtual" Web
Credential with static ID `<COLLECTION>_<TYPE>` (e.g. `SANDBOX_BEARER`). The
package, the cURL and the REST Data Source reference it and **never carry the
secret**. The dev creates that Web Credential at install time.

### Target Profile

`p_target_profile_id` is optional. With null, the active profile with the
lowest id is used; with no profiles, prefix `app`, tracing `logger` and
auditing `Y`. Without `target_schema`, objects are emitted unqualified.

---

## 6. Automatic Data Profile

Every Send with a successful JSON response calls
`arw_discover_api.auto_profile`: it saves the sample, consolidates all active
samples of the endpoint, and leaves the profile ready for the generator. There
is no manual "Derive / Accept" step in the UI.

The algorithm:

1. Detect the `row_selector`: the first array of objects. Null means the rows
   are the root (an array, or an object that counts as one row).

2. Walk recursively and record each leaf with its `path_expression`, relative
   to the row.

3. Infer `data_type_code`:

   - number → `number`

   - JSON boolean → `boolean`

   - string that parses as ISO 8601 → `timestamp_with_time_zone` +
     `format_mask`

   - string → `varchar2`, with `max_observed_length` rounded up

   - array of objects → a `clob` / `array` column with child columns
     (`parent_column_id`); array of scalars → a single `clob` column

4. Set `is_nullable_yn` when the field is missing or `null` in any sample.

5. Propose at most one PK: `id` first, then `*_id`, `uuid` or `code`.

The profile can be edited through the API (`update_column`), but page 215,
which used to edit it, was removed. The Response tab only keeps a note with
the column count of the current profile.

---

## 7. Execution

`arw_exec_api.execute_endpoint(p_endpoint_id, p_environment_id)`:

1. Resolves the URL: a full URL as-is, or the environment's `base_url` + path.
   Substitutes the environment's `{{variables}}` and the path and form params.

2. Runs `arw_preflight_api.run_preflight` against the real host. If a check
   fails, it records the attempt as `error` and raises `-20923` without going
   out to the network.

3. Clears `apex_web_service.g_request_headers`, applies headers, body and
   simple auth (`apply_simple_auth`). If the endpoint has a `credential_id`,
   it also passes the Web Credential `static_id`.

4. Calls `make_rest_request_b` and decides by Content-Type: text (JSON, XML,
   SVG...) is stored in `response_body_clob`; binary (image, audio, video,
   PDF) in `response_body_blob`.

5. Writes `arw_executions` with sensitive headers and auth as
   `***REDACTED***`.

The editor shows binary responses with a preview and *Download file*.

---

## 8. Preflight — The Survival Feature

| Check | Source | On failure |
|---|---|---|
| Network ACL for the host | `user_network_acl_privileges` | proposes `dbms_network_acl_admin.append_host_ace` (run by an ADMIN) |
| Wallet / HTTPS | real call to the host, catches `ORA-29024` / `ORA-28759` | instructions |
| DB and APEX version | `v$version`, `apex_release` | informational |
| Web Credential exists | `apex_credential.get_credential_details` | hidden since Nov 2026 |

It runs before every Send and can be checked on page 800 as a checklist with a
corrective action per item.

> **Note:** `WKSP_DEVAI1` cannot execute `dbms_network_acl_admin`; the ADMIN
> user does the grants. `scripts/grant_guide_hosts.sql` grants ACLs to the
> hosts used by the guide examples.

---

## 9. Page Map

Module × 100, detail × 10 convention. The app is hand-written APEXlang in
`apex/arw/` (see `docs/apexlang_lessons/README.md`).

| Page | Content | Menu |
|---|---|---|
| 1 | Home: "Get started" row with 6 shortcuts, recent collections and executions | yes |
| 100 / 110 | Collections (IR) / modal editor | yes |
| 200 | Endpoints (IR) | from collections |
| 210 | **Request editor** (see below) | top bar: *New request* |
| 300 / 310 | Environments / variables, "Set active" | yes |
| 400 / 410 | History / execution detail (request and response) | yes |
| 500 / 510 | Target profiles | hidden |
| 600 / 610 | Web Credentials | hidden |
| 700 | Postman import | yes |
| 800 | Preflight | yes |
| 900 / 910 | Guide: Quick start / Examples | yes, last |
| 9999 | Login | — |

The navigation bar has *New request* and the active environment selector
(`ARW_ENV_NAME`).

### Page 210 — Request Editor

- **Bar:** method, URL, environment, **Send** and **Save**. Below it, the
  resolved URL.

- **Send = save + execute** in a single submit. Save only saves. The name is
  optional (defaults to method + URL).

- **Request tabs:** Params, Auth (none/basic/bearer/API key), Headers, Body,
  Settings (collection, runtime, engine, timeout).

- **Response:** status, time, headers, formatted body or binary preview, and
  the data profile note.

- **Code:** PASTE (`_api` package, anonymous block, `json_table`, target DDL,
  cURL) and INSTALL (`restDataSource`), with Prism highlighting and a Copy
  button. For GET, **Download demo app (.zip)** (see §10.5).

- Every button and region has a Static ID; the page JS needs them
  (`arw-code.js`).

### Guide (900 / 910)

- **900 Quick start:** 3 steps (New request → paste URL → Send) and cards
  pointing to the rest of the app.

- **910 Examples:** 23 examples in 4 sections (Quick GET, Collections and
  variables, POST/PUT/PATCH/DELETE, Preflight) that open ready to Send. They
  are marked *Needs ACL* when the host has no permission. *Reset examples*
  restores them.

---

## 10. APEXlang Outputs

Syntax verified against `assets/grammar/apexlang.ebnf` from the
`oracle/skills` repo (build `26.1.0+3102`). The APEXlang generated by ARW
passes `apex validate` against the instance.

### 10.1 REST Data Source

The only INSTALL output visible in the Code tab. It is shown as text with
`// file:` markers for people working with APEXlang in Git.

```apexlang
restDataSourceServer acme-api (
    name: acme-api
    endpointUrl { url: "https://api.acme.com/" }
)

webCredential acme-bearer (
    name: Acme Bearer Token
    type: httpHeader
    authentication { credentialName: Authorization }
)

restDataSource acme-orders (
    name: Acme Orders
    source {
        type: http
        remoteServer: @acme-api
        urlPathPrefix: /v1/orders
    }
    authentication { credentials: @acme-bearer }

    parameter status (
        name: status
        parameter { type: urlQueryString }
    )

    dataProfile {
        name: ACME_ORDERS
        rowSelector: items
    }
    dataProfileColumn order-id (
        columnName: ORDER_ID
        source  { sequence: 1  dataType: number  primaryKey: true }
        parsing { pathExpression: id }
    )
    dataProfileColumn created-on (
        columnName: CREATED_ON
        source  { sequence: 2  dataType: timestampWithTimeZone }
        parsing {
            pathExpression: created
            formatMask: YYYY"-"MM"-"DD"T"HH24":"MI:SS.FF9TZR
        }
    )

    operation get_rows (
        label: GET
        operation { urlPattern: .  httpMethod: get  databaseOperation: fetchRows }
    )
)
```

The `.apx` bundle download was removed from the UI: it was a fragment, not an
app, and App Builder does not import it on its own.
`arw_codegen_api.build_apx_bundle` is still in the package.

### 10.2 The Generated Package, Bundled Into the App

Generated by `apexlang_install_script`; no selector in the UI.

```apexlang
installScript acme-orders-api (
    name: Acme Orders API
    execution { sequence: 10 }
    script {
        type: packageBody
        content:
            ```
            create or replace package body acme_orders_api as
              ...
            end acme_orders_api;
            ```
    }
)
```

`script.type` accepts `packageSpec` | `packageBody` | `table`.

### 10.3 The Endpoint as an Agent Tool

Generated by `apexlang_ai_tool`; no selector in the UI.

```apexlang
tool get-open-orders (
    name: get_open_orders
    type: executeServersideCode
    executionPoint: onDemand
    description:
        ```
        Returns the open Acme orders for a customer code.
        ```
    settings {
        language: plsql
        plsqlCode:
            ```plsql
            apex_ai.set_tool_result
              ( p_result => acme_orders_api.get_open_orders_json
                              ( p_customer_code => :CUSTOMER_CODE ) );
            ```
    }
)
```

### 10.4 Web Credential Types in the Grammar

`basicAuthentication` · `oauth2ClientCredentialsFlow` · `oci` · `httpHeader` ·
`urlQueryString` · `keyPair` · `certificatePrivateKeyPair` ·
`oauth2PasswordFlow` · `signedUserAssertion` · `userAssertionSigningCertificate`

What is **not** in that list (SigV4, custom signed JWT) can only be solved
through the `apex_web_service` route with a signer package, not through
`restDataSource`. That is exactly the gap the tool covers.

### 10.5 Demo App (.zip)

`arw_codegen_api.build_demo_app_zip`, GET requests only. It is a complete
APEXlang app:

- one public page (no login) with an Interactive Report on the REST Data
  Source;

- the Remote Server and the Web Credential;

- `deployments/default.json` with the suggested ID `100000 + endpoint_id`.
  Without that file, App Builder returns an ORDS HTTP 400 on *Next*.

It is imported in App Builder (Import > Application, requires ORDS 26.1.1+) or
with SQLcl (`-id` to change the ID). With the *Include auth values* switch on,
a supporting object stores the Auth tab secret in the Web Credential at
install time (plain text, demo only).

---

## 11. Postman Collection Import

`arw_import_api.import_postman` (page 700) parses the v2.1 format with
`json_table`:

- one collection; folders are flattened and their path is prepended to the
  request name

- `item[]` → `arw_endpoints`, with `request.header[]`, `request.url.query[]`
  and path params, and `request.body.raw`

- a `dev` environment with the base URL and `variable[]`

- `request.auth` basic / bearer / apikey → the request's simple auth, usually
  as `{{variables}}`; other types are reported as unsupported

Sensitive values in headers, params and variables are **not imported**. An
auth value typed literally in Postman is kept in the Auth tab (beta, see
§3.1).

OpenAPI / Swagger is still pending.

---

## 12. Install and Upgrade

Today the app is installed with the scripts in `release/` (see
`docs/RELEASE.md`):

- `release/_release.sql` is the release template: it runs the upgrades in
  `release/code/_run_code.sql` and then `all_views`, `all_packages`,
  `all_triggers`, `all_data` and `all_apex`.

- `release/1.0.0.sql` was the Phase 0 base install: tables, views, triggers
  and data, with no packages and no app.

The upgrades (`discovery`, `codegen`, `absolute_url`, `guide`, `simple_auth`)
are additive and re-runnable: they check the data dictionary before every
change.

Distributing the installer with the APEXlang `supportingObject` is still an
open goal:

```apexlang
supportingObject (
    prerequisites { freeSpace: ...  systemPrivileges: [...] }
    installation  { ... }
    upgrade       { ... }
    deinstall     { scriptFile: deinstall-script.sql }
    advanced      { includeInAppExport: true }
)
```

---

## 13. Known Technical Pitfalls

| Pitfall | Mitigation |
|---|---|
| `apex_web_service.g_request_headers` is global and persists between calls | cleared at the start of every execution |
| Binary responses or responses over 32k | always `make_rest_request_b`; text to clob, binary to blob |
| Inferring types from a single sample | the profile consolidates all active samples of the endpoint |
| `Authorization` header in the history | mandatory redaction |
| `apex_credential` without an APEX session | requires `apex_util.set_security_group_id`; the preflight reports that case as `unknown` |
| `apex_util.get_apex_version` and the `apex_credentials` view do not exist in 26.1 | use `apex_release` and `apex_credential.get_credential_details` |
| PL/SQL identifiers starting with `_` | do not compile (`PLS-00103`); private units are named like public ones |
| Generating REST Data Sources via `apex_application_api` | fragile and version-dependent; use APEXlang |
| Importing APEXlang in App Builder without `deployments/default.json` | ORDS HTTP 400 |
| `httpbingo.org` from the ADB | returns 402; the examples use `httpbin.org` |

---

## 14. Phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Data model + preflight | done (2026-09-22) |
| 1 | CRUD + execution + history + "paste" targets | done (2026-10-23/24, issue #25), plus the guide |
| 2 | Postman import | done, pulled forward into Phase 1; Nov 2026 simplification (PR #27) |
| 3 | APEXlang outputs + SQLcl validation | partial: `restDataSource` and demo app; `query-valid-props.mjs` and validating the rest are missing |
| 4 | Assertions + JSON Schema (23ai) + runner | pending |
| 5 | Algorithmic auth, `dbms_cloud`, `automation`, OpenAPI | pending |

---

## 15. Pending

- Global Error Handling Function for the app.

- Validate the remaining APEXlang outputs in the browser (`installScript`, AI
  tool, `automation`) and decide whether they return to the Code tab.

- `query-valid-props.mjs` for `installScript`, `supportingObject` and Web
  Credential types.

- The `dbms_cloud_send_request` variant does not compile in `WKSP_DEVAI1`
  (no `EXECUTE` on `DBMS_CLOUD`).

- The `job` variant leaves `gc_app_id` as a TODO for the dev to set their
  application.

- Store simple auth outside plain text before leaving beta.

- Widen or reorganize the `-209xx` error range.
