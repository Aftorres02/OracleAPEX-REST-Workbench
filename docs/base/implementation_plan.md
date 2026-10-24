# ARW — Plan de Implementación

> Deriva de `CONCEPT.md` e `IMPLEMENTATION.md` — no los repite, los convierte
> en una lista de trabajo ejecutable. Prefijo de proyecto: `arw_`.

---

## 1. Cómo usar este documento

Este es un checklist vivo, no una foto fija. Cada subpaso tiene una casilla
(`- [ ]` / `- [x]`) y un criterio de salida verificable. Se actualiza a
medida que se ejecuta cada paso — no se reescribe entero en cada sesión.

Regla de trabajo: no se marca una casilla como hecha solo porque un script
"corrió sin error". Cada subpaso se cierra con una verificación directa
(consulta a la tabla, invocación desde SQLcl, revisión del preflight) — ver
la sección 7.

---

## 2. Prefijo y herramientas disponibles

El prefijo `arw_` ya está en uso consistente en `CONCEPT.md` e
`IMPLEMENTATION.md` — se hereda directamente, sin bloquear el arranque.

> **Nota:** `.claude/commands/new-package.md` y `gen-crud-page.md` son hoy
> placeholders sin pasos de generación reales, y
> `.claude/skills/apex-migration/SKILL.md` solo tiene el frontmatter. No
> generan código todavía. El trabajo de este plan se apoya directamente en
> `.claude/templates/table_template.sql`, `package_spec_template.sql`,
> `package_body_template.sql`, `compound_trigger_template.sql`, y en las
> reglas `ddl-conventions.md`, `plsql-standards.md`, `sql-format.md` — no en
> esos comandos/skill hasta que se completen (ver sección 6).

Archivos generados van en las carpetas ya existentes del repo (todas vacías
salvo `.gitkeep`, siguiendo `repo-structure.md`): DDL de tablas en `tables/`,
triggers en `triggers/`, paquetes en `packages/` (`.pks`/`.pkb`), vistas en
`views/`, datos semilla en `data/`.

---

## 3. Modelo de datos — orden de creación

Tres decisiones de relación que `IMPLEMENTATION.md` §3 no fijaba, ya
confirmadas:

- `arw_credentials` es catálogo global reusable; FK saliente única desde
  `arw_endpoints.credential_id` (auth por endpoint, sin herencia desde
  environment).
- `arw_endpoints` **no** lleva `environment_id` — el ambiente se elige en
  tiempo de ejecución (`arw_executions.environment_id`), igual que una
  Postman collection corrida contra distintos environments.
- `arw_response_samples.execution_id` es FK a `arw_executions` — toda
  muestra de discovery proviene de una ejecución ya registrada en el
  historial, en vez de duplicar la captura de status/headers/body en dos
  tablas separadas.

Por esta última decisión, el bloque de ejecución se crea **antes** que el de
discovery, aunque `IMPLEMENTATION.md` los liste en el orden contrario.

### 3.1 Bloque núcleo

- [ ] **`arw_collections`** — agrupador tipo Postman collection. Columnas
  clave: `collection_id`, `name`, `parent_collection_id` (self-FK,
  nullable).

- [ ] **`arw_environments`** — ambiente (dev/qa/prod). FK `collection_id`.
  Columnas clave: `environment_id`, `base_url`.

- [ ] **`arw_credentials`** — metadata de auth, nunca el secreto. Sin FK
  entrante — catálogo global. Columnas clave: `credential_id`,
  `auth_type_code`, `apex_credential_static_id`.

- [ ] **`arw_env_variables`** — variables `{{...}}`. FK `environment_id`.
  Columnas clave: `variable_id`, `var_name`, `var_value`, `is_secret_yn`.

- [ ] **`arw_endpoints`** — la petición. FK `collection_id`; FK
  `credential_id` (nullable). Sin `environment_id` (ver decisión arriba).
  Columnas clave: `endpoint_id`, `http_method`, `url_path`, `timeout_secs`,
  `runtime_target_code`, `engine_code`.

- [ ] **`arw_endpoint_headers`** — headers de request. FK `endpoint_id`.
  Columnas clave: `header_id`, `header_name`, `header_value`,
  `is_sensitive_yn`.

- [ ] **`arw_endpoint_params`** — path / query / form. FK `endpoint_id`.
  Columnas clave: `param_id`, `param_kind_code`, `param_name`,
  `data_type_code`, `is_required_yn`.

- [ ] **`arw_request_bodies`** — cuerpo con tokens. FK `endpoint_id`.
  Columnas clave: `body_id`, `content_type`, `body_template` (clob).

### 3.2 Bloque ejecución

- [ ] **`arw_executions`** — historial de llamadas reales. FK
  `endpoint_id`, `environment_id`. Columnas clave: `execution_id`, `status`,
  `elapsed_ms`, request enviado (headers redactados), response.

### 3.3 Bloque discovery

- [ ] **`arw_response_samples`** — respuesta cruda observada. FK
  `endpoint_id`, `execution_id`. Columnas clave: `sample_id` (clob/blob),
  `status`, `headers`, `elapsed_ms`.

- [ ] **`arw_data_profiles`** — perfil derivado de una muestra. FK
  `response_sample_id`. Columnas clave: `data_profile_id`, `row_selector`,
  `format_code`.

- [ ] **`arw_profile_columns`** — una fila por campo descubierto. FK
  `data_profile_id`; self-FK `parent_column_id` (nullable, jerarquía
  anidada). Columnas clave: `path_expression`, `data_type_code`,
  `source_data_type`, `format_mask`, `max_observed_length`,
  `is_nullable_yn`, `is_primary_key_yn`.

  > Esta es la tabla más importante del sistema — alimenta el `json_table`,
  > el `dataProfileColumn` de APEXlang y el record type del paquete
  > generado (ver `IMPLEMENTATION.md` §3.2).

### 3.4 Bloque ejecución y generación (resto)

- [ ] **`arw_target_profiles`** — perfil de destino (prefijo, esquema,
  traza, auditoría, tipo de instancia, versión BD/APEX). Sin FK entrante —
  catálogo de configuración.

- [ ] **`arw_code_templates`** — fragmentos versionados del generador, por
  sección y variante. Sin FK entrante — catálogo/seed.

- [ ] **`arw_generated_artifacts`** — salida generada. FK `endpoint_id`,
  `target_profile_id`; FK `data_profile_id` (nullable). Columnas clave:
  tipo, contenido, checksum, versión, fecha.

Cada tabla sigue el orden de archivo de `ddl-conventions.md` §7: creación
(con constraints inline) → índices de performance → trigger compuesto de
auditoría → comments vía `execute immediate`. Todas llevan `active_yn` +
columnas de auditoría + trigger compuesto según `ddl-conventions.md` §4-5.

---

## 4. Fase 0 — paso a paso

Descompone el bloque único "Modelo de datos + preflight" de
`IMPLEMENTATION.md` §13 en subpasos verificables por separado.

> **Fase 0: completa** (2026-09-22) — los 7 subpasos (0.1-0.7) están
> verificados en vivo contra `AI_dev_ai_1`, incluyendo el criterio de salida
> completo de `IMPLEMENTATION.md` §13: `arw_exec_api.execute_endpoint`
> ejecutó una llamada real contra el endpoint semilla y quedó la fila
> correspondiente en `arw_executions`. Antes de arrancar la Fase 1, ver la
> sección 6 — `arw_auth_utils` todavía solo cubre `auth_type_code = 'none'`.

### 0.1 Confirmar prefijo

- [x] `arw_` heredado de `CONCEPT.md`/`IMPLEMENTATION.md` — sin bloqueo.

### 0.2 DDL completo del modelo de datos

- [x] Crear las 15 tablas de la sección 3 (núcleo + ejecución + discovery +
  generación) en una sola migración, con triggers e índices.
- [x] Insertar una fila de prueba de punta a punta: 1 collection, 1
  environment, 1 endpoint público sin auth (`auth_type_code = 'none'`).

*Salida:* el script corre limpio contra un esquema vacío; la fila de prueba
es consultable.

> **Estado: ejecutado y verificado** (2026-09-09) — `release/1.0.0.sql`
> (adaptado de `_release.sql`, sin los pasos de disable/install APEX porque
> aún no existe app) corrió contra `WKSP_DEVAI1` (workspace `DEV_AI_1`,
> conexión SQLcl guardada como `AI_dev_ai_1` (guion bajo, no espacio —
> `docs/apexlang_lessons/README.md` traía `AI dev_ai_1` con espacio hasta
> el 2026-09-21, cuando se re-verificó en vivo y se corrigió), no
> `dev_ai_1`. Confirmado por consulta
> directa: 15 tablas, 15 triggers, 0 objetos inválidos, fila semilla
> (`collection_id=1`, `environment_id=1`, `endpoint_id=1`) consultable via
> join. DDL en `tables/*.sql` + `tables/_install_arw_tables.sql`, triggers en
> `triggers/*.sql` + `triggers/_install_arw_triggers.sql`, seed en
> `data/arw_seed_phase0_endpoint.sql`, orquestados desde
> `release/all_tables.sql` / `all_triggers.sql` / `all_data.sql`.

### 0.3 `arw_endpoint_api` — CRUD mínimo

- [x] CRUD de endpoint/headers/params/bodies, sin UI todavía. Paralelizable
  con 0.4.

> **Estado: ejecutado y verificado** (2026-09-22) — `packages/arw_endpoint_api.pks`/
> `.pkb` compilan `VALID` contra `AI_dev_ai_1` (workspace `WKSP_DEVAI1`, APEX
> 26.1.4) — `LOGGER` ya está instalado (ver nota bajo 0.4), el bloqueador
> previo quedó resuelto. Verificado con una invocación real por SQLcl:
> `create_endpoint` (incluyendo `p_name`, obligatorio y sin default) crea un
> endpoint, `deactivate_endpoint` lo desactiva. Rango de excepción propio
> confirmado con el usuario: `-20900` a `-20949` (`gc_err_not_found := -20910`).

### 0.4 `arw_auth_utils` — versión mínima

- [x] Solo `auth_type_code = 'none'` por ahora. Paralelizable con 0.3. Se
  ampliará a basic/bearer/apikey antes de la Fase 1 (ver sección 6).

> **Estado: ejecutado y verificado** (2026-09-22) — `packages/arw_auth_utils.pks`/
> `.pkb` compilan `VALID` contra `AI_dev_ai_1`. `get_auth_headers(p_credential_id
> => null)` invocado por SQLcl devuelve una tabla vacía (`header_count=0`),
> confirmando el caso sin auth. Cualquier credencial real todavía lanza
> `gc_err_auth_type_not_implemented` (no probado en vivo — no hay credenciales
> reales en Fase 0, ver sección 6).
>
> **Bloqueador previo (0.3 y 0.4) resuelto:** `LOGGER` ya está instalado en
> `WKSP_DEVAI1` (confirmado 2026-09-22 — sinónimo válido a `LOGGER_USER.LOGGER`,
> con `SELECT`/`DELETE` directos sobre `LOGGER_LOGS`). El estado `INVALID`
> que tenían los bodies en la base era solo por falta de recompilación desde
> que se otorgó el grant — no un bloqueador real. Recompilados en limpio
> 2026-09-22, cero errores.
>
> **Actualización (2026-09-22, prerequisito de Fase 1 resuelto):** `get_auth_headers`
> quedó reemplazada por `resolve_credential_static_id` — ver la nota bajo
> "Pendientes y decisiones abiertas" (sección 6) para el detalle completo
> del rediseño y de la verificación en vivo (basic/bearer/`api_key_header`/
> `api_key_query`, las cuatro cubiertas).

### 0.5 `arw_exec_api` — ejecución real mínima

- [x] Arma la petición (limpia `apex_web_service.g_request_headers` al
  inicio, ver `IMPLEMENTATION.md` §12), llama con `apex_web_service`, escribe
  el resultado en `arw_executions`.

*Salida:* invocado desde SQLcl contra el endpoint de prueba de 0.2, devuelve
status 200 y body no vacío, y queda una fila en `arw_executions`.

> **Estado: ejecutado y verificado de punta a punta** (2026-09-22) —
> `packages/arw_exec_api.pks`/`.pkb` compilan `VALID` contra `AI_dev_ai_1`.
> Bug real corregido antes de que compilara: los 6 helpers privados del body
> (`extract_host`, `reject_unsupported_params`, `build_query_string`,
> `get_body`, `apply_request_headers`, `log_execution`) estaban escritos con
> prefijo `_` — convención de "privado" tomada de `javascript-standards.md`
> §7, pero un identificador PL/SQL no puede empezar con `_` (`PLS-00103`).
> Renombrados sin el prefijo.
>
> `execute_endpoint(p_endpoint_id => 1, p_environment_id => 1)` invocado en
> vivo contra el endpoint semilla de 0.2 tras resolver el bloqueador de ACL
> (ver 0.6/0.7): devolvió `execution_id=1`, y la fila en `arw_executions`
> quedó con `request_status_code='success'`, `http_status_code=200`,
> `elapsed_ms=240` y el body real de `jsonplaceholder.typicode.com/todos/1`
> (`{"userId": 1, "id": 1, "title": "delectus aut autem", "completed": false}`).
> Salida cumplida.

### 0.6 `arw_preflight_api` — checklist de supervivencia

- [x] Verifica ACL de red (`dba_host_aces` / `user_network_acl_privileges`),
  wallet (HTTPS), versión de BD/APEX (`v$version`, `apex_release`),
  existencia de credencial (`apex_credentials`). Solo lee catálogos — puede
  desarrollarse en paralelo a 0.5, no depende de que ese paso ya funcione.

*Salida:* checklist correcto contra el host de prueba, incluyendo al menos
un caso forzado en rojo (host sin ACL) para confirmar que detecta el fallo,
no solo el éxito.

> **Estado: ejecutado y verificado** (2026-09-22) — `packages/arw_preflight_api.pks`/
> `.pkb` compilan `VALID` contra `AI_dev_ai_1`. Dos bugs reales corregidos
> antes de que compilara:
>
> - `check_database_version` llamaba `apex_util.get_apex_version`, que no
>   existe (`PLS-00302`). Reemplazado por `select version_no from
>   apex_release` — la vista sí es accesible desde este schema (sinónimo
>   público → `APEX_260100.APEX_RELEASE`, confirmado en vivo: `26.1.4`),
>   contrario a lo que asumía el comentario original.
>
> - `check_credential` hacía `select count(*) from apex_credentials where
>   static_id = ...` (`ORA-00942` — esa vista no existe en 26.1, ni en
>   plural ni singular). Reemplazado por `apex_credential.get_credential_details`,
>   la API real de 26.1 (paquete, no vista). Detalle importante confirmado
>   en vivo: esa función exige contexto de sesión APEX
>   (`apex_util.set_security_group_id`) — llamarla desde una sesión SQLcl
>   pelada lanza "package variable g_security_group_id must be set" para
>   cualquier `static_id`, no solo uno inexistente. El check ahora distingue
>   ese caso (`status_code = unknown`) de un `no_data_found` real
>   (`status_code = fail`) — no probado con una credencial real todavía
>   porque Fase 0 solo usa `p_credential_id = null` (ver sección 6).
>
> Invocado en vivo por SQLcl, antes y después de resolver el bloqueador de
> ACL: (1) `run_preflight('jsonplaceholder.typicode.com', null)` — **antes**
> del grant: `network_acl=fail` (sin ACE registrada), `wallet_https=pass`
> (HTTPS real, status 200), `db_apex_version=info` (`Database 23.0, APEX
> 26.1.4`), `credential_exists=pass`, `has_failures=Y`; (2)
> `run_preflight('this-host-has-no-acl.example.invalid', null)` →
> `network_acl=fail`, `wallet_https=unknown` (`ORA-29273`), mismos
> `db_apex_version`/`credential_exists`, `has_failures=Y`; (3) **después**
> del grant (ver nota de ACL abajo): mismo host real →
> `network_acl=pass` ("Privilege \"http\" granted..."), `wallet_https=pass`,
> `db_apex_version=info`, `credential_exists=pass`, `has_failures=N`. El
> checklist detecta tanto fallos reales como el estado sano — criterio de
> salida cumplido con los tres casos.
>
> **ACL de red — resuelto** (2026-09-22): `WKSP_DEVAI1` no tiene privilegio
> para ejecutar `dbms_network_acl_admin` directamente (`PLS-00201`, el
> paquete ni siquiera es visible desde ese schema) — el grant se hizo
> conectado como el usuario ADMIN de la base, no como `WKSP_DEVAI1`. Una vez
> otorgada la ACE (`resolve` + `http` para `jsonplaceholder.typicode.com`,
> confirmada `GRANTED` en `user_network_acl_privileges` desde `WKSP_DEVAI1`),
> `check_network_acl` pasó a `pass` y el flujo completo de 0.7 funcionó.
> (El HTTP saliente ya funcionaba *antes* del grant para esta llamada
> puntual porque `check_wallet` hace su propia llamada real y no depende de
> `check_network_acl` — pero `execute_endpoint` sí depende de que **todos**
> los checks pasen, así que el grant era indispensable para que el flujo
> completo, no solo el wallet-check aislado, funcionara.)

### 0.7 Integración

- [x] La ejecución real (0.5) solo corre si el preflight (0.6) pasa.

*Salida:* este es el criterio de salida de la Fase 0 completa según
`IMPLEMENTATION.md` §13 — un endpoint público se ejecuta y el preflight
reporta correctamente.

> **Estado: ejecutado y verificado — Fase 0 completa** (2026-09-22) —
> verificados los dos caminos en vivo:
>
> - **Bloqueo correcto:** antes del grant de ACL, `arw_exec_api.execute_endpoint(
>   p_endpoint_id => 1, p_environment_id => 1)` contra el endpoint semilla de
>   0.2 (`GET https://jsonplaceholder.typicode.com/todos/1`, sin credencial)
>   se negó a salir y lanzó `ORA-20923: Preflight failed for host
>   jsonplaceholder.typicode.com: network_acl: No network ACL entry found...`
>   con el mensaje formateado por `format_failures`.
>
> - **Camino de éxito:** una vez registrada la ACE de red (como usuario
>   ADMIN de la base — `WKSP_DEVAI1` no tiene privilegio para
>   `dbms_network_acl_admin` directamente, ver la nota de ACL bajo 0.6), el
>   mismo `execute_endpoint(1, 1)` corrió la llamada real y devolvió
>   `execution_id=1`, con la fila en `arw_executions` mostrando
>   `request_status_code='success'`, `http_status_code=200` y el body real.
>
> Ambos caminos confirman que "0.5 solo corre si 0.6 pasa" funciona como
> está diseñado, y que un endpoint público se ejecuta de punta a punta con
> el preflight reportando correctamente — criterio de salida de la Fase 0
> cumplido.

---

## 5. Fases 1-5 — resumen accionable

El detalle completo de cada fase vive en `IMPLEMENTATION.md` §13; aquí solo
el alcance, el criterio de salida, y qué debe estar resuelto antes de
empezarla.

### Fase 1 — CRUD + ejecución + historial + 4 targets "pegar"

Alcance: UI de páginas (mapa de páginas en `IMPLEMENTATION.md` §8), y los
cuatro targets "pegar" base (bloque anónimo, paquete `_api`, `json_table`,
cURL).

Antes de empezar: `arw_auth_utils` debe cubrir ya basic/bearer/apikey, no
solo `none` — los targets "pegar" con auth real no tienen sentido sobre la
versión mínima de la Fase 0.

> **Prerequisito resuelto** (2026-09-22) — ver el detalle en la sección 6
> bajo "Pendientes y decisiones abiertas".

*Salida:* un dev consume un endpoint real de punta a punta.

> **Estado (2026-09-22): arranque del build de páginas, vía APEXlang.**
> Decisión con el usuario: las páginas propias de ARW se autoran a mano
> como `.apx` (mismo toolchain que Fase 3 formaliza para la salida
> generada), no en APEX Builder — ver `.claude/skills/apexlang-lessons/SKILL.md`.
>
> Primer corte, deliberadamente chico (arrancar por `apex validate`
> temprano, no al final — ver la sección "Suggested flow" de esa skill):
> scaffold completo de la app (`apex/arw/` — `application.apx`,
> `deployments/default.json`, tema Universal Theme, autenticación
> `oracleApexAccounts`, listas de navegación, página 0 global, página 9999
> de login) + **página 1 (Home)** con un classic report de colecciones
> recientes + **página 100 (Collections)** con un interactive report de
> `arw_collections`, ambas de solo lectura. `apex import icons`/static
> files se omitieron a propósito (no se usan todavía) siguiendo la regla
> de la skill "skip unless the app actually uses them".
>
> `apex validate -input apex/arw` pasó limpio contra `AI_dev_ai_1` (APEX
> 26.1.4) — "Validation successful.", cero errores. En el camino, dos
> bugs reales encontrados y corregidos que no estaban documentados en la
> skill: una columna `classicReport` con `type: hidden` no acepta bloque
> `heading`, y **ninguna** columna `classicReport` acepta `source { dataType:
> ... }` (a diferencia de `interactiveReport`, que sí lo exige) — el
> template canónico de `classic-report-page.example.md` ya lo mostraba
> así, el error fue mío por copiar el patrón de columna de
> `interactive-report-page` sin fijarme en esa diferencia.
>
> **`apex import` NO se corrió** — es una escritura real contra el
> workspace en vivo; la skill exige pedirlo explícitamente, no inferirlo
> de "seguí". Falta decidir/confirmar antes de importar.
>
> **Pendiente, ya identificado:** la página 110 (editor de Collection,
> modal) necesita un paquete `arw_collections_api` que todavía no existe
> — este repo no tiene lógica de negocio en páginas (`IMPLEMENTATION.md`
> §1: "páginas delgadas, base de datos gruesa"), así que el proceso DML
> de esa página debe llamar a un paquete, no hacer `insert`/`update`
> directo. Por eso 110 quedó fuera de este primer corte — página 100 es
> de solo lectura por ahora. Mismo patrón le va a hacer falta a 200/210
> (Endpoints — aunque para ese ya existe `arw_endpoint_api`) y a
> 300/310 (Environments — necesita `arw_environments_api`, tampoco
> existe todavía).
>
> **Actualización (2026-10-22, issue #23): editor de Collections hecho.**
>
> - `arw_collections_api` (`create_collection`, `update_collection`,
>   `deactivate_collection`) compila `VALID`. Valida el padre (existe,
>   activo, no es la misma colección ni un descendiente — sin ciclos) y
>   no desactiva una colección con hijas, endpoints o environments
>   activos. Códigos `-20940` (no encontrada), `-20941` (padre inválido),
>   `-20942` (tiene dependientes). Probado en vivo: 10 casos (camino feliz
>   + cada error) dentro de una transacción con `rollback`, cero filas de
>   prueba remanentes.
>
> - Página 110 (modal): formulario sobre `arw_collections`; los botones
>   CREATE/SAVE/DELETE disparan procesos PL/SQL que llaman al paquete (sin
>   Automatic Row Processing), con condiciones Expression sobre
>   `:REQUEST`.
>
> - Página 100: link por fila declarativo (`link { linkColumn:
>   customTarget, target { page: 110 ... } }`, la forma de la plantilla
>   oficial del IR — validó al primer intento, sin JavaScript), botón
>   CREATE y refresco del IR al cerrar el diálogo.
>
> - `apex validate -input apex/arw` limpio, cero warnings.
>
> **`apex import` sigue pendiente:** el usuario lo autorizó, pero el
> permiso de la sesión del agente lo bloqueó como despliegue en vivo. ARW
> todavía no existe en `DEV_AI_1` (ids actuales: 106, 111, 114, 10402),
> así que el primer import va sin `-id`; los siguientes, con `-id <id>`.
>
> **Falta además:** la app no tiene Error Handling Function global
> (`error-handling.md` §3), así que los errores `ORA-2094x` del paquete se
> muestran tal cual en la notificación.
>
> **Actualización (2026-10-23, issue #25): app completa según los mockups
> `docs/base/mockups/files_v2`, importada como aplicación 142 en
> `DEV_AI_1`.** Donde el plan y los mockups difieren, mandan los mockups.
>
> - Backend nuevo: `arw_discover_api` (muestras + perfil editable,
>   `profile_status_code` proposal/accepted), `arw_codegen_api` +
>   `arw_render_utils` + 59 fragmentos en `arw_code_templates` (los 9
>   artefactos: `_api` package, bloque anónimo, `json_table`, DDL de tabla,
>   cURL, y APEXlang restDataSource / installScript / aiAgent tool /
>   automation; el APEXlang generado pasa `apex validate`),
>   `arw_environments_api`, `arw_target_profiles_api`,
>   `arw_credentials_api` (incluye crear la Web Credential real),
>   `arw_import_api` (Postman v2.1 — adelanta la Fase 2),
>   `arw_preflight_api.preflight_report` (pipelined) y tres vistas
>   (`arw_collection_summary_vw`, `arw_execution_log_vw`,
>   `arw_endpoint_summary_vw`). `arw_exec_api` ahora sustituye path/form
>   params y `{{var}}` del ambiente, y registra como ejecución `error` las
>   llamadas rechazadas por el preflight.
> - Páginas: 1 Home, 100/110 Collections, 200 Endpoints, 210 editor
>   (General, Auth, Headers, Params, Body, Response con perfil derivado,
>   Code con descarga del bundle `.apx`), 215 columna del perfil, 300/310
>   Environments (+ variables, "Set active"), 400/410 History, 500/510
>   Target profiles, 600/610 Credentials, 700 Import, 800 Preflight.
> - Datos demo: colecciones JSONPlaceholder (6 endpoints, perfilados) y
>   Sandbox (httpbin.org, sin ACL → el preflight lo bloquea, como el
>   mockup), tres target profiles, historial real.
> - Verificado: `apex validate` limpio; las 31 consultas de regiones/LOVs
>   parsean y las 32 piezas de PL/SQL embebido compilan contra el esquema;
>   flujo completo Send → muestra → Derive → Accept → 9 artefactos →
>   bundle probado en vivo.
>
> **Pendiente:** revisión visual en el navegador (no hubo navegador en la
> sesión que lo construyó); la variante `dbms_cloud_send_request` del
> generador no compila aquí (el esquema no tiene EXECUTE sobre
> `DBMS_CLOUD`); la ruta `job` del código generado deja `gc_app_id` /
> `gc_app_user` como TODO; sigue sin Error Handling Function global.

### Fase 2 — Import de colecciones Postman

Alcance: parseo con `json_table` de `item[]`, `request.header[]`,
`request.url.query[]`, `request.auth`, `variable[]`, `request.body.raw`
(ver `IMPLEMENTATION.md` §9). Los secretos de la colección nunca se
importan.

*Salida:* una colección de 20 endpoints entra y genera código.

### Fase 3 — Salidas APEXlang + validación con SQLcl

Alcance: `arw_apexlang_api` emitiendo `restDataSourceServer` +
`webCredential` + `restDataSource` + `dataProfile`, `installScript`,
`tool` de AI agent (sintaxis confirmada en `IMPLEMENTATION.md` §10).

Antes de empezar: acceso real a APEX 26.1 + SQLcl 26.1.2, y la decisión de
calificación por esquema (bloquea también `arw_codegen_api`/
`arw_render_utils` de la Fase 1). Usar `docs/apexlang_lessons/README.md`
como referencia práctica de gramática y trampas conocidas.

> **Ambos prerequisitos resueltos** (acceso 2026-09-22, decisión de
> esquema 2026-10-22) — ver la sección 6. Sigue pendiente correr
> `query-valid-props.mjs`, también en la sección 6.

*Salida:* el `.apx` generado pasa `apex validate`/`apexctl runtime validate`
e importa.

### Fase 4 — Aserciones + JSON Schema (23ai) + runner

Alcance: `is json validate using schema`, runner de colección.

*Salida:* detección de cambios de contrato entre ejecuciones.

### Fase 5 — Auth algorítmica, dbms_cloud, automation, OpenAPI

Alcance: SigV4, JWT firmado, mTLS, `dbms_cloud`/Autonomous, `automation` +
`jsonDualityView`, import de OpenAPI/Swagger.

---

## 6. Pendientes y decisiones abiertas

- Completar `.claude/commands/new-package.md`, `gen-crud-page.md` y
  `.claude/skills/apex-migration/SKILL.md` con pasos reales — hoy son
  placeholders y no se puede depender de ellos como generadores.

- ~~Acceso a APEX 26.1 + SQLcl 26.1.2 para validar salidas `.apx`~~ —
  **resuelto** (2026-09-22). `AI_dev_ai_1` corre APEX `26.1.4` (confirmado
  vía la vista `apex_release`) y SQLcl local es `26.2.2.0` — ambos superan
  el mínimo pedido. Confirmado además que el toolchain de validación en sí
  está disponible, no solo la versión: `apex validate`/`apex import` (SQLcl)
  y `apexctl.mjs runtime validate`/`runtime doctor`/`apexlang validate`/
  `apexlang compiler-truth audit` (repo `oracle/skills`, plugin
  `oracle-skills`) responden con `--help` y aceptan `--db-connection-name`.
  No se corrió ninguno contra un `.apx` real todavía — eso pasa cuando
  exista contenido que validar (Fase 3), pero la infraestructura ya no es
  un bloqueador.

- Ejecutar `query-valid-props.mjs` (repo `oracle/skills`, mismo plugin,
  en `apex/apexlang/tools/`) para confirmar propiedades exactas de
  `installScript`, `supportingObject` y tipos de `webCredential`
  disponibles en 26.1 — sigue bloqueando Fase 3. La herramienta existe y
  corre localmente (`--component`, `--component-type-id`, `--json`), pero
  necesita `--compiler-oracle-home` apuntando a una instalación real (SQL
  Developer / SQLcl / dbtools) para la verdad respaldada por el compilador
  — no ejecutado todavía, queda para cuando se arranque Fase 3 en serio.

- ~~Decidir si el generador emite objetos calificados por esquema o asume el
  esquema actual~~ — **resuelto** (2026-10-22, confirmado por el usuario).
  Ya no bloquea `arw_codegen_api`/`arw_render_utils` (Fase 1) ni
  `arw_apexlang_api` (Fase 3).

  > **Decisión** (propuesta 2026-09-22, confirmada 2026-10-22):
  > `arw_target_profiles.target_schema` ya modela esto — su propio
  > comentario de columna dice "null when the generator assumes the current
  > schema". Por defecto (perfil sin `target_schema`) el generador emite
  > objetos **sin calificar**
  > (matching el espíritu de los targets "pegar" — el dev corre el
  > snippet en su propia sesión/esquema, calificarlo de más solo agrega
  > ruido); cuando el perfil sí trae `target_schema`, el generador
  > antepone `<target_schema>.` a cada referencia a tabla/paquete/vista
  > generada. Esto no requiere cambiar el modelo de datos — ya está
  > soportado por la columna existente.

- ~~Ampliar `arw_auth_utils` a basic/bearer/apikey antes de la Fase 1~~ —
  **resuelto** (2026-09-22). Verificado en vivo contra `AI_dev_ai_1` (APEX
  26.1.4) que la forma correcta y segura de resolver estos cuatro tipos
  (`basic`, `bearer`, `api_key_header`, `api_key_query`) es pasar el
  `apex_credential_static_id` directo a
  `apex_web_service.make_rest_request`'s `p_credential_static_id` — APEX
  adjunta el header/query real desde el Web Credential store sin que
  nuestro PL/SQL toque el secreto en ningún momento. Esto es distinto al
  diseño original de `get_auth_headers`, que asumía que este paquete
  armaría el header manualmente (lo que hubiera requerido extraer el
  secreto a una variable PL/SQL, contradiciendo el propio comentario de
  `arw_credentials`: "el secreto vive en apex_credential, nunca se
  almacena acá").

  Cambios: `arw_auth_utils.get_auth_headers` (y los tipos `t_header_rec`/
  `t_header_tab`, sin otro uso) fueron reemplazados por
  `resolve_credential_static_id(p_credential_id) return
  apex_credential_static_id%type` — null cuando no hay auth, el
  `static_id` para los 4 tipos simples, y sigue lanzando
  `gc_err_auth_type_not_implemented` para el resto (`oauth2_*`, `oci`,
  `mtls`, `sigv4`, `jwt_signed` — Fase 5). `arw_exec_api.apply_request_headers`
  ya no arma headers de auth; solo dejó una línea de auditoría redactada en
  el resumen. `execute_endpoint` resuelve el `static_id` y lo pasa tanto a
  `apply_request_headers` (para el log) como directo a `make_rest_request`.

  Verificado con una credencial real de tipo `bearer` (`HTTP_HEADER` en
  `apex_credential`, creada con `apex_credential.create_credential` +
  `set_persistent_credentials`, requiere sesión APEX real —
  `apex_util.set_security_group_id` — igual que en 0.6): una llamada cruda
  contra `https://httpbin.org/bearer` con `p_credential_static_id` devolvió
  `{"authenticated": true, "token": "arw-test-token-123"}`, confirmando que
  APEX adjuntó el header real. También se probó el camino de rechazo: la
  misma credencial contra un host fuera de su `p_allowed_urls` devolvió
  `ORA-20987: Credential is not allowed to be used for this URL endpoint`,
  y `execute_endpoint` lo capturó correctamente como
  `request_status_code = 'error'` (sin excepción sin manejar, `execution_id`
  igual devuelto). Toda la credencial y el endpoint de prueba se
  limpiaron después (`apex_credential.drop_credential` + filas
  desactivadas).

---

## 7. Verificación

Cada subpaso se cierra así, no solo con "el script corrió sin error":

- DDL/datos semilla: consulta directa a la tabla recién creada, no solo
  ejecución del script.
- Paquetes: invocación real desde SQLcl (conexión `dev_ai_1` — ver
  `docs/apexlang_lessons/README.md`, sección "Entorno de este repo") con
  `dbms_output`/`logger` visible.
- Preflight: al menos un caso verde y uno rojo forzado, para confirmar que
  detecta fallos y no solo éxitos.
- APEXlang (Fase 3+): `apex validate` real contra la instancia, nunca solo
  el linter/formatter local — ver los falsos positivos conocidos en
  `docs/apexlang_lessons/README.md`, sección "Compiler-truth audit".
