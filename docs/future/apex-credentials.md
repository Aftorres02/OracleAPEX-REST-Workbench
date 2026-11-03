# Auth con APEX Web Credentials (oculto desde Phase 2)

Desde Phase 2 el tab Auth del editor usa auth simple guardada en ARW. La
integración con APEX Web Credentials sigue instalada, pero la UI ya no la
usa. Este documento explica cómo funcionaba y cómo reactivarla.

---

## Cómo funcionaba

`arw_credentials` guarda solo metadatos: nombre, tipo y el static ID de una
Web Credential de APEX. El secreto vive en el credential store de APEX y ARW
nunca lo ve.

- **Ejecución:** `arw_exec_api.execute_endpoint` resuelve el static ID con
  `arw_auth_utils.resolve_credential_static_id` y lo pasa como
  `p_credential_static_id` a `apex_web_service`. APEX agrega el header o el
  query param.

- **Tipos:** basic, bearer, api_key_header, api_key_query,
  oauth2_client_credentials, oauth2_password, oci, mtls, sigv4, jwt_signed.

- **Páginas:** 600 (lista) y 610 (crear la Web Credential en APEX con
  `apex_credential`, vía `arw_credentials_api`).

- **Preflight:** el check `credential_exists` confirma que la Web Credential
  existe y si es válida para el host.

- **Import de Postman:** `arw_import_api.resolve_credential` creaba un
  registro en `arw_credentials` por cada tipo de auth de la colección.

---

## Qué cambió en Phase 2

### Auth simple por request

Columnas nuevas en `arw_endpoints`: `auth_type_code` (none, basic, bearer,
api_key), `auth_username`, `auth_password`, `auth_token`, `auth_key_name`,
`auth_key_value` y `auth_key_location_code` (header o query).

- `arw_endpoint_api.set_auth` las guarda y `arw_exec_api.apply_simple_auth`
  las aplica en cada Send.

- Los valores aceptan `{{variables}}` del environment activo.

- En History el valor se guarda como `***REDACTED***`.

> **Limitación conocida:** el secreto queda en texto plano en
> `arw_endpoints` y se ve en el editor. Es aceptable en beta, con datos de
> demo; no lo uses con secretos reales.

### Código generado

`arw_codegen_api` convierte la auth simple en una Web Credential "virtual",
con static ID `<COLECCION>_<TIPO>` (por ejemplo, `SANDBOX_BEARER`). El
paquete, el cURL y el REST Data Source referencian esa credencial y nunca
llevan el secreto. Después de instalar, el dev crea la Web Credential en
APEX con ese static ID.

### Qué se ocultó

- **Editor (p210):** se quitaron el selector `P210_CREDENTIAL_ID` y el botón
  "Manage credentials". Guardar un request deja `credential_id` en null.

- **Preflight (p800):** `P800_CREDENTIAL_ID` quedó oculto y siempre en null,
  y se quitó el botón "Credentials". El check `credential_exists` no se
  muestra.

- **Import:** `apply_postman_auth` llena la auth simple. Los tipos
  `basic`, `bearer` y `apikey` se importan; los demás se reportan como no
  soportados.

---

## Cómo reactivarlo

### Volver a enlazar credenciales en el editor

Restaurar `P210_CREDENTIAL_ID` y pasarlo a `create_endpoint` y
`update_endpoint` en el proceso `save-endpoint`. La ejecución todavía
respeta `credential_id`: si un endpoint tiene uno, APEX aplica la Web
Credential además de la auth simple.

### Volver a mostrar el preflight de credenciales

Convertir `P800_CREDENTIAL_ID` otra vez en select list y quitar el filtro
`check_name != 'credential_exists'`.

### Volver a importar credenciales

Llamar a `resolve_credential` desde `import_request`; la función sigue en
`arw_import_api`.

> **Nota:** el estado previo completo está en `main` antes del PR de
> Phase 2: `git show 66eec29:apex/arw/pages/p00210-endpoint-editor.apx`.
