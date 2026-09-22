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

- [ ] CRUD de endpoint/headers/params/bodies, sin UI todavía. Paralelizable
  con 0.4.

> **Estado:** `packages/arw_endpoint_api.pks`/`.pkb` redactados (create/update
> /deactivate de endpoint; add/update/remove de headers y params; set/remove
> de body vía `merge`). Verificado localmente: alineación columna 49,
> espaciado de 8 líneas en blanco entre unidades, JavaDoc completo. **No
> compilado aún** — bloqueado por `LOGGER` (ver nota en 0.4). Rango de
> excepción propio confirmado con el usuario: `-20900` a `-20949`
> (`gc_err_not_found := -20910`).

### 0.4 `arw_auth_utils` — versión mínima

- [ ] Solo `auth_type_code = 'none'` por ahora. Paralelizable con 0.3. Se
  ampliará a basic/bearer/apikey antes de la Fase 1 (ver sección 6).

> **Estado:** `packages/arw_auth_utils.pks`/`.pkb` redactados —
> `get_auth_headers` maneja el caso sin auth (`p_credential_id` null,
> devuelve tabla vacía) y lanza `gc_err_auth_type_not_implemented` para
> cualquier credencial real, ya que ningún tipo de auth está implementado
> todavía. Verificado localmente igual que 0.3.
>
> **Bloqueador compartido (0.3 y 0.4):** el paquete `LOGGER` no está
> instalado en `WKSP_DEVAI1` (confirmado por consulta directa a
> `all_objects`, sin filtro de owner — no hay ni el objeto ni un sinónimo
> público). `plsql-standards.md` §8 exige `logger.log`/`log_error` en todo
> paquete, así que ninguno de estos dos compila todavía. El usuario decidió
> instalarlo él mismo más adelante — no marcar estas casillas ni compilar
> hasta confirmar que `LOGGER` ya está instalado.

### 0.5 `arw_exec_api` — ejecución real mínima

- [ ] Arma la petición (limpia `apex_web_service.g_request_headers` al
  inicio, ver `IMPLEMENTATION.md` §12), llama con `apex_web_service`, escribe
  el resultado en `arw_executions`.

*Salida:* invocado desde SQLcl contra el endpoint de prueba de 0.2, devuelve
status 200 y body no vacío, y queda una fila en `arw_executions`.

### 0.6 `arw_preflight_api` — checklist de supervivencia

- [ ] Verifica ACL de red (`dba_host_aces` / `user_network_acl_privileges`),
  wallet (HTTPS), versión de BD/APEX (`v$version`, `apex_release`),
  existencia de credencial (`apex_credentials`). Solo lee catálogos — puede
  desarrollarse en paralelo a 0.5, no depende de que ese paso ya funcione.

*Salida:* checklist correcto contra el host de prueba, incluyendo al menos
un caso forzado en rojo (host sin ACL) para confirmar que detecta el fallo,
no solo el éxito.

### 0.7 Integración

- [ ] La ejecución real (0.5) solo corre si el preflight (0.6) pasa.

*Salida:* este es el criterio de salida de la Fase 0 completa según
`IMPLEMENTATION.md` §13 — un endpoint público se ejecuta y el preflight
reporta correctamente.

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

*Salida:* un dev consume un endpoint real de punta a punta.

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

- Acceso a APEX 26.1 + SQLcl 26.1.2 para validar salidas `.apx` — bloquea
  la Fase 3, no la Fase 0/1.

- Ejecutar `query-valid-props.mjs` (repo `oracle/skills`) para confirmar
  propiedades exactas de `installScript`, `supportingObject` y tipos de
  `webCredential` disponibles en 26.1 — bloquea Fase 3.

- Decidir si el generador emite objetos calificados por esquema o asume el
  esquema actual — bloquea `arw_codegen_api`/`arw_render_utils` (Fase 1) y
  `arw_apexlang_api` (Fase 3).

- Ampliar `arw_auth_utils` a basic/bearer/apikey antes de la Fase 1 (ver
  sección 5, Fase 1).

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
