# REST Workbench for Oracle APEX — Concept

> **Status (Nov 2026):** working beta. The app (ARW, prefix `arw_`) is built
> and imported into `DEV_AI_1`. The technical detail of what was built is in
> `IMPLEMENTATION.md`, and step-by-step progress is in
> `implementation_plan.md`.
>
> Requires Oracle APEX 26.1 (tested on 26.1.4) and, to import the APEXlang
> outputs, SQLcl 26.1.2+ or ORDS 26.1.1+.

---

## 1. The Problem

An Oracle developer who needs to consume a REST API today does this:

1. Tests the endpoint in Postman. It works.
2. Translates it to PL/SQL. It fails.
3. Loses hours on things Postman could not anticipate: a missing network ACL,
   a certificate missing from the wallet, the database proxy, TLS not
   negotiated, real types that differ from the documented ones, errors
   returned inside a 200.

Postman generates snippets in ~20 languages. **None of them is PL/SQL.**

Generative AI does not solve the underlying problem either: it can write the
call, but it **cannot observe the real response**, so the data mapping and the
service contract will always be a guess.

---

## 2. What It Is

An Oracle APEX application installed in each developer's environment that
works like Postman — but **tests from the database** and returns Oracle code
ready to implement.

> **The sentence that defines the product:**
> Postman tests from your laptop. This tool tests from your database.
> A green test here means it will work in production.

---

## 3. The Cycle

```
Configure → Execute (from the DB) → Observe the real response → Materialize
```

In the app the cycle is a single gesture: **New request → paste the URL →
Send**. Send saves and executes; the Response tab shows the real result and
the Code tab generates code from that response.

Materialization has **two categories**, and that distinction is the heart of
the product:

| Category | What the dev does with the result |
|---|---|
| **Paste** | It goes inside their code: anonymous block, package, `json_table`, cURL |
| **Install** | It is not pasted. It is imported with SQLcl or App Builder and **creates APEX components** |

Postman only has the first category. The second one exists only because
APEXlang turned APEX applications into text with a formal grammar.

---

## 4. Output Catalog

The "Today" column shows what the app's Code tab offers. "Generator" means
`arw_codegen_api` already produces it, but the UI has not shown it since the
Nov 2026 simplification.

### Paste Category

| Output | When | Today |
|---|---|---|
| Full `_api` package | real integration, with standards and JavaDoc | yes |
| Anonymous block with `apex_web_service` | quick test, copy and run | yes |
| `json_table` | parse the response (derived from the observed response) | yes |
| Target table DDL | persist the result | yes |
| cURL | report the problem to the service provider | yes |
| Raw `utl_http` | schema without APEX installed | template variant, no selector in the UI |
| `dbms_cloud.send_request` | Autonomous Database | template variant; does not compile without `EXECUTE` on `DBMS_CLOUD` |

### Install Category

| Component | Result in the dev's app | Today |
|---|---|---|
| `restDataSourceServer` + `webCredential` + `restDataSource` + `dataProfile` | REST Data Source configured, ready for an Interactive Report | yes, as text with `// file:` markers |
| **Demo app (.zip)**, GET only | complete APEXlang app: a public page with an Interactive Report on the REST Data Source | yes |
| `installScript` (`type: packageBody`) | the generated package travels inside the app export | generator |
| `tool` inside `aiAgent` | the endpoint can be invoked by the app's chatbot | generator |
| `automation` with `restSynchronization` | scheduled sync of the endpoint into a local table | generator |
| `jsonDualityView` | JSON read/write over the synced data | pending |

The **demo app** was not in the original concept. It solves a practical
problem: App Builder does not import a loose `restDataSource` fragment, but it
does import a complete app. It is the shortest way to see the REST Data Source
working.

### Environment Scripts

- `dbms_network_acl_admin.append_host_ace` (network ACL): the preflight
  proposes it when it is missing; a database ADMIN runs it.

- `apex_credential.create_credential`: the generated code references a Web
  Credential by `static_id`, and the dev creates it at install time.

---

## 5. Why No Other Tool Covers This

| Alternative | What it lacks |
|---|---|
| **Postman** | zero Oracle outputs; tests from the laptop, not from the DB |
| **Generative AI** | does not observe the real response; the `dataProfile` would be invented. Oracle's own skill forbids guessing it: *"Never guess profile shape"* |
| **Native REST Data Sources** | tied to the APEX runtime; not usable from jobs or external packages; does not cover exotic auth |
| **APEXlang (official skill)** | covers declarative consumption but **does not mention `apex_web_service` in any file**, and has no way to discover the data profile |

The gap is real and verifiable: APEXlang requires an exact `dataProfile` and
provides no way to obtain it. This tool is that missing link: in ARW the
profile is derived automatically from every successful JSON response.

---

## 6. Distribution Model

Same as Postman:

- **It is installed in each developer's environment.** Their endpoints, their
  environments, their credentials — they never leave their database.

- **The only shared piece is the installer.** Today it is the scripts in
  `release/` (see `docs/RELEASE.md`). Packaging it with the APEXlang
  `supportingObject` (prerequisites / installation / upgrade / deinstall) is
  still the goal.

- **Secrets:** the original design kept them only in the APEX credential
  store. In the beta, simple auth (basic, bearer, API key) is stored in
  `arw_endpoints` as plain text so the Auth tab works without creating Web
  Credentials. It is redacted in the history and never reaches the generated
  code, but **it must not be used with real secrets**. The Web Credentials
  integration is still installed and hidden (`docs/future/apex-credentials.md`).

---

## 7. Design Decisions

1. **Tracing and auditing are independent axes**, not a scale. The target
   profile chooses tracing (none / `apex_debug` / `logger`) and auditing
   (yes / no) separately.

   > **Implemented differently:** the concept asked for `apex_debug` by
   > default. The app's default profile uses `logger` + auditing, and target
   > profiles are hidden in the UI (`docs/future/target-profiles.md`).

2. **`apex_debug` or `logger` is called from a single point** inside the
   generated package, so switching frameworks touches one place.

3. **Auditing and the history always redact sensitive headers**, not as an
   option. Storing `Authorization` in clear text would be storing the
   password.

4. **Auditing writes outside the caller's transaction**, so the evidence is
   not lost exactly when the process fails and rolls back.

5. **Simple auth vs. algorithmic auth.** Basic / Bearer / API key are *data*
   and are resolved inline. SigV4 / signed JWT / OAuth2 with refresh are
   *algorithms* and will be emitted as a shared signer package, once per
   project.

6. **The generated code never carries the secret.** It references a Web
   Credential by `static_id` (`<COLLECTION>_<TYPE>`, e.g. `SANDBOX_BEARER`)
   that the dev creates at install time.

7. **Target profile** (prefix, schema, tracing, auditing, instance type,
   DB/APEX version) is defined once and reused. Without `target_schema`, the
   generator emits unqualified objects.

8. **The preflight blocks the call.** If a check fails, ARW does not go out to
   the network and records the attempt in the history with the reason.

9. **The data profile is automatic.** Every Send with a successful JSON
   response re-derives it; the dev does not have to accept it by hand.

---

## 8. Scope

### Done (beta, Nov 2026)

- Collections, environments, `{{...}}` variables, a **Drafts** collection for
  loose requests

- Postman-like editor: method, full URL or a path with `{{base_url}}`,
  Params, Auth, Headers, Body, Settings; Send = save + execute

- Simple per-request auth: none, basic, bearer, API key (header or query)

- Real execution with `apex_web_service` + history; binary responses (image,
  audio, video, PDF) with preview and download

- **ACL, wallet and version preflight** with a fix script

- Automatic data profile from the JSON response

- Code: `_api` package, anonymous block, `json_table`, DDL, cURL,
  `restDataSource` and demo app (.zip)

- Postman v2.1 collection import

- In-app guide: Quick start + 23 ready-to-send examples

### Next

- Validate the remaining APEXlang outputs (`installScript`, AI tool,
  `automation`) and decide whether they return to the UI

- Assertions on the response + `is json validate using schema` (23ai)

- Collection runner

- OAuth2 client credentials

- Global Error Handling Function for the app

### Later

- Algorithmic auth (SigV4, signed JWT, mTLS)

- `dbms_cloud` / Autonomous

- `automation` + `jsonDualityView`

- OpenAPI / Swagger import

### Out of Scope

- Publishing REST services (that is ORDS, another product)

- Mock servers, WebSocket, GraphQL

- Cloning Postman's user experience

---

## 9. The Risk to Attack First

**The first execution is the moment of truth.** If the dev installs, tests an
endpoint and gets `ORA-24247`, they abandon the tool and never come back.

That is why the preflight went into Phase 0, before any screen. Today it runs
before every Send, it can be checked on the Preflight page, and the guide's
examples are marked *Needs ACL* when the host has no permission yet.

---

## 10. Validated Against a Real Instance

| Item | Status |
|---|---|
| APEX 26.1 + SQLcl | `DEV_AI_1` runs APEX 26.1.4; local SQLcl 26.2.2 |
| Generated `.apx` passes validation | the generated APEXlang passes `apex validate`; the demo app imports |
| Exact properties of `installScript` and `supportingObject` | pending: `query-valid-props.mjs` from the `oracle/skills` repo |
| `webCredential` types available in 26.1 | pending: same command |
