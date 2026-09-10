# REST Workbench for Oracle APEX — Implementación

> Complementa `CONCEPT.md`. Prefijo `arw_` provisional.
> APEX 26.1 real antes de codificar.

---

## 1. Arquitectura en capas

```
Páginas APEX (thin)
   └─ AJAX / procesos  →  arw_*_api  (fachada de negocio)
                            ├─ arw_exec_api      ejecuta la llamada real
                            ├─ arw_discover_api  infiere el perfil de la respuesta
                            ├─ arw_codegen_api   orquesta la generación
                            ├─ arw_render_utils  motor de plantillas y tokens
                            ├─ arw_preflight_api ACL, wallet, versión
                            └─ arw_import_api    Postman / OpenAPI
```

Regla: páginas delgadas, base de datos gruesa. Ningún proceso de página contiene
lógica más allá de invocar la fachada y mapear errores con `apex_error.add_error`.

---

## 2. Los tres ejes que determinan el código generado

Todo el generador gira sobre esta matriz. Modelarla bien desde el día 1 evita
rediseños.

| Eje | Valores |
|---|---|
| **Runtime destino** | APEX (sesión viva) · Job/scheduler (sin sesión APEX) · Autonomous |
| **Motor** | `apex_web_service.make_rest_request` / `_b` · `utl_http` · `dbms_cloud.send_request` |
| **Auth** | none · basic · bearer · API key (header/query) · OAuth2 client credentials · OAuth2 password · OCI · mTLS · SigV4 · JWT firmado |

El **runtime destino** es la variable que casi nadie considera y cambia el código
completo: `p_credential_static_id` no funciona en un job sin
`apex_session.create_session`. Resolver eso automáticamente ya justifica la
herramienta.

---

## 3. Modelo de datos

Convenciones (según estándar del equipo): PK identity `<entidad>_id` sin prefijo
en la columna, `varchar2(n char)` siempre, `timestamp with local time zone` para
auditoría, toda tabla lleva `active_yn` + `created_by/on` + `last_updated_by/on`
+ trigger compuesto + comments vía `execute immediate`.

### 3.1 Núcleo

| Tabla | Propósito | Columnas clave |
|---|---|---|
| `arw_collections` | agrupador tipo Postman collection | `collection_id`, `name`, `parent_collection_id` |
| `arw_environments` | ambiente (dev/qa/prod) | `environment_id`, `collection_id`, `base_url` |
| `arw_env_variables` | variables `{{...}}` | `variable_id`, `environment_id`, `var_name`, `var_value`, `is_secret_yn` |
| `arw_credentials` | **metadata** de auth, nunca el secreto | `credential_id`, `auth_type_code`, `apex_credential_static_id` |
| `arw_endpoints` | la petición | `endpoint_id`, `collection_id`, `http_method`, `url_path`, `timeout_secs`, `runtime_target_code`, `engine_code` |
| `arw_endpoint_headers` | headers de request | `header_id`, `endpoint_id`, `header_name`, `header_value`, `is_sensitive_yn` |
| `arw_endpoint_params` | path / query / form | `param_id`, `endpoint_id`, `param_kind_code`, `param_name`, `data_type_code`, `is_required_yn` |
| `arw_request_bodies` | cuerpo con tokens | `body_id`, `endpoint_id`, `content_type`, `body_template` (clob) |

### 3.2 Discovery — el diferenciador

| Tabla | Propósito |
|---|---|
| `arw_response_samples` | respuesta cruda observada (clob/blob), status, headers, elapsed_ms |
| `arw_data_profiles` | perfil derivado de una muestra: `row_selector`, `format_code` |
| `arw_profile_columns` | una fila por campo descubierto: `path_expression`, `data_type_code`, `source_data_type`, `format_mask`, `max_observed_length`, `is_nullable_yn`, `is_primary_key_yn`, `parent_column_id` |

`arw_profile_columns` es la tabla más importante del sistema. Alimenta el
`json_table`, el `dataProfileColumn` de APEXlang y el record type del paquete.
La jerarquía anidada se modela con `parent_column_id` (autorreferencia).

### 3.3 Ejecución y generación

| Tabla | Propósito |
|---|---|
| `arw_executions` | historial: status, elapsed, request enviado (headers redactados), response |
| `arw_target_profiles` | perfil de destino: prefijo, esquema, traza, auditoría, tipo de instancia, versión BD/APEX |
| `arw_code_templates` | fragmentos versionados del generador, por sección y por variante |
| `arw_generated_artifacts` | salida: tipo, contenido, checksum, versión, fecha |

---

## 4. Paquetes

Solo paquetes, `%type` anchors, loops `for` implícitos, `merge` para upserts,
`gc_scope_prefix := lower($$plsql_unit)||'.'`, JavaDoc completo en cada unidad.

| Paquete | Responsabilidad |
|---|---|
| `arw_endpoint_api` | CRUD de endpoints, headers, params, bodies |
| `arw_exec_api` | ejecuta la llamada real; limpia `g_request_headers`; captura status/elapsed/response |
| `arw_discover_api` | infiere el perfil desde una muestra: paths, tipos, longitudes, máscaras, jerarquía |
| `arw_codegen_api` | orquesta: recibe endpoint + perfil + target profile, devuelve el artefacto |
| `arw_render_utils` | motor de tokens y ensamblado de fragmentos |
| `arw_apexlang_api` | emite los bloques `.apx` y el bundle |
| `arw_auth_utils` | construye headers de auth simple; firmadores para auth algorítmica |
| `arw_preflight_api` | verifica ACL, wallet, versión de BD/APEX antes de la primera llamada |
| `arw_import_api` | parsea colecciones Postman y OpenAPI con `json_table` |
| `arw_audit_api` | escritura de auditoría independiente de la transacción del llamador |

---

## 5. Motor de generación — híbrido

**Fragmentos en tabla, lógica en PL/SQL.**

`arw_code_templates` guarda los fragmentos ensamblados por sección ordenada:

```
declaracion → headers → auth → invocacion → status → parseo → ejemplo
```

Cada fragmento tiene `template_type_code` (plsql_block, plsql_package,
json_table, apexlang_rds, apexlang_install_script, apexlang_ai_tool, curl) y
`variant_code` (el valor del eje que aplica: `basic`, `bearer`, `job`, etc.).

Lo que **no** es texto vive en PL/SQL: la inferencia de tipos, la construcción de
la jerarquía anidada, la paginación, el cálculo de longitudes.

Ventaja: agregar un tipo de auth nuevo = insertar filas, no recompilar. Esto es
también lo que permite contribución de la comunidad sin tocar código.

---

## 6. Inferencia del perfil de datos

El algoritmo de `arw_discover_api`, en orden:

1. Detectar el `rowSelector`: el primer array del JSON con objetos homogéneos.
2. Recorrer recursivamente y registrar cada hoja con su `path_expression`.
3. Inferir `data_type_code` por el tipo JSON observado, con reglas:
   - número entero sin decimales en todas las muestras → `number`
   - string que parsea como ISO 8601 → `timestamp with time zone` + `format_mask`
   - string → `varchar2`, con `max_observed_length` redondeado hacia arriba
   - array anidado → nuevo nivel con `parent_column_id`
4. Marcar `is_nullable_yn` si el campo falta o es `null` en alguna muestra.
5. Proponer `is_primary_key_yn` para campos llamados `id`, `*_id`, `code`, `uuid`.

**Todo esto es una propuesta editable.** El dev revisa y ajusta antes de generar.
La herramienta no impone; observa y sugiere.

Nota crítica: inferir de **una sola** respuesta es frágil. La UI debe permitir
acumular varias muestras y consolidar el perfil sobre todas.

---

## 7. Preflight — la funcionalidad de supervivencia

Se ejecuta antes de la primera llamada a un host nuevo:

| Verificación | Fuente | Si falla |
|---|---|---|
| ACL de red para el host | `dba_host_aces` / `user_network_acl_privileges` | emite `dbms_network_acl_admin.append_host_ace` |
| Wallet configurado (HTTPS) | intento de llamada, captura `ORA-29024` / `ORA-28759` | instrucciones + script |
| Versión de BD y APEX | `v$version`, `apex_release` | ajusta las salidas disponibles |
| Credencial existe | `apex_credentials` | ofrece crearla |

El resultado se muestra como checklist con acción correctiva por ítem, no como un
error crudo.

---

## 8. Mapa de páginas

Convención módulo × 100, detalle × 10.

| Página | Contenido |
|---|---|
| 1 | Home: colecciones recientes, ambiente activo |
| 100 / 110 | Colecciones (IR) / detalle |
| 200 | Endpoints (IR) |
| 210 | **Editor de endpoint** — tabs: General, Auth, Headers, Params, Body, Response, Code |
| 300 / 310 | Ambientes / variables |
| 400 / 410 | Historial de ejecuciones / detalle con diff |
| 500 / 510 | Perfiles de destino |
| 600 / 610 | Plantillas de código (admin) |
| 700 | Import (Postman / OpenAPI) |
| 800 | Preflight y diagnóstico de entorno |

### Página 210 — detalle

- Region Display Selector para los tabs
- **Send** vía AJAX: lee `g_x01..`, devuelve `apex_json` `{success:true/false}`
- Tab Response: status, elapsed, headers, body con formato
- Tab Code: select list de target + área de código con botón copiar / descargar
- Botón **Descargar bundle `.apx`** que junta los componentes APEXlang elegidos
- Todo proceso de tipo Processing lleva condición (preferir Expression)
- Static IDs de región con sufijo `IR` / `CR` / `SR`; de botón = nombre en mayúsculas

---

## 9. Import de colecciones Postman

La palanca de adopción: *"importa tu colección y obtén el PL/SQL de tus 40
endpoints"*.

El formato v2.1 de Postman es JSON público y estable. Se parsea con `json_table`:

- `item[]` recursivo → `arw_collections` + `arw_endpoints`
- `request.header[]` → `arw_endpoint_headers`
- `request.url.query[]` → `arw_endpoint_params`
- `request.auth` → `arw_credentials` (tipo, sin secreto)
- `variable[]` → `arw_env_variables`
- `request.body.raw` → `arw_request_bodies`

Los secretos presentes en la colección **no se importan**; se marca la credencial
como pendiente y se pide crearla en `apex_credential`.

---

## 10. Salidas APEXlang — sintaxis confirmada contra la gramática

Ejemplos verificados contra `assets/grammar/apexlang.ebnf` del repo
`oracle/skills` (build `26.1.0+3102`).

### 10.1 REST Data Source

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

### 10.2 El paquete generado, empaquetado en la app

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

`script.type` admite `packageSpec` | `packageBody` | `table`. la
lista completa de propiedades de `supportingObject.installation`.

### 10.3 El endpoint como herramienta de agente

```apexlang
tool get-open-orders (
    name: get_open_orders
    type: executeServersideCode
    executionPoint: onDemand
    description:
        ```
        Devuelve las ordenes abiertas de Acme para un codigo de cliente.
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

### 10.4 Tipos de `webCredential` en la gramática

`basicAuthentication` · `oauth2ClientCredentialsFlow` · `oci` · `httpHeader` ·
`urlQueryString` · `keyPair` · `certificatePrivateKeyPair` ·
`oauth2PasswordFlow` · `signedUserAssertion` · `userAssertionSigningCertificate`

Lo que **no** está en esa lista (SigV4, JWT firmado propio) solo puede resolverse
por la ruta `apex_web_service` con paquete firmador — no por `restDataSource`.
Ese es exactamente el hueco que la herramienta cubre.

---

## 11. Distribución y upgrade

El instalador se empaqueta con `supportingObject` de APEXlang:

```apexlang
supportingObject (
    prerequisites { freeSpace: ...  systemPrivileges: [...] }
    installation  { ... }
    upgrade       { ... }
    deinstall     { scriptFile: deinstall-script.sql }
    advanced      { includeInAppExport: true }
)
```

La herramienta se distribuye y actualiza con el mismo mecanismo que usa para
generar.  propiedades exactas de `installation` y `upgrade`.

---

## 12. Trampas técnicas conocidas

| Trampa | Mitigación |
|---|---|
| `apex_web_service.g_request_headers` es global y persiste entre llamadas | limpiar con `.delete` al inicio de cada ejecución, siempre |
| Respuestas binarias o mayores a 32k | `make_rest_request_b` + blob; decidir por endpoint |
| Inferir tipos de una sola muestra | acumular varias muestras y consolidar |
| Auditoría perdida por rollback del llamador | escritura independiente de la transacción |
| Header `Authorization` en el historial | redacción obligatoria, no opcional |
| Código generado que no compila en la instancia destino | perfil de destino con versión; piso conservador por defecto |
| Generar REST Data Sources vía `apex_application_api` | frágil y versionado. Usar APEXlang, no la API programática |

---

## 13. Fases

| Fase | Alcance | Criterio de salida |
|---|---|---|
| 0 | Modelo de datos + preflight | un endpoint público se ejecuta y el preflight reporta correctamente |
| 1 | CRUD + ejecución + historial + 4 targets "pegar" | un dev consume un endpoint real de punta a punta |
| 2 | Import Postman | una colección de 20 endpoints entra y genera código |
| 3 | Salidas APEXlang + validación con SQLcl | el `.apx` pasa `apexctl runtime validate` e importa |
| 4 | Aserciones + JSON Schema (23ai) + runner | detección de cambios de contrato |
| 5 | Auth algorítmica, `dbms_cloud`, `automation`, OpenAPI | |

---

## 14. Pendientes antes de escribir DDL

1. **Confirmar prefijo** (`arw_` es provisional).
2. Acceso a APEX 26.1 + SQLcl 26.1.2 para validar las salidas `.apx`.
3. Ejecutar `query-valid-props.mjs` para `installScript`, `supportingObject` y
   `webCredential`.
4. Decidir si el generador emite objetos calificados por esquema o asume el
   esquema actual.
