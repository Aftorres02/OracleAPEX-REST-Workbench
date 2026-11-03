# Target profiles (oculto desde Phase 2)

Los target profiles se quitaron del menú y del editor para simplificar la
app. Las páginas, la tabla y el paquete siguen instalados, sin uso desde la
UI. Este documento explica qué hacían y cómo reactivarlos.

---

## Qué hacían

Un target profile describe el entorno donde se va a instalar el código que
genera la pestaña Code de un request. El editor tenía un selector de perfil,
y cada artefacto se generaba con los valores del perfil elegido.

La tabla `arw_target_profiles` tiene estas columnas:

| Columna | Efecto en el código generado |
|---|---|
| `object_prefix` | Prefijo del paquete y de la tabla (`app_users_api`, `app_users`) |
| `target_schema` | Si tiene valor, el DDL y las llamadas usan `schema.objeto` |
| `trace_mode_code` | `logger`, `apex_debug` o `none`: qué instrumentación lleva el paquete |
| `audit_enabled_yn` | `Y` agrega el procedimiento que audita cada llamada REST |
| `instance_type_code`, `db_version`, `apex_version` | Solo informativos, no cambian el código |

`arw_generated_artifacts.target_profile_id` guarda con qué perfil se generó
cada versión de un artefacto.

---

## Cómo funciona ahora

`arw_codegen_api` recibe `p_target_profile_id` con valor por defecto `null`.
Con `null` usa el perfil activo de menor id. Si no hay ninguno, usa los
valores internos: prefijo `app`, trace `logger` y auditoría `Y`.

El seed (`data/arw_seed_demo.sql`) crea primero "Default — APEX + logger"
con esos mismos valores. Por eso el código generado no cambió al ocultar
los perfiles.

---

## Qué se ocultó

- La entrada "Target profiles" del menú (`shared-components/lists.apx`).

- En la página 210: el selector `P210_TARGET_PROFILE_ID`, su computation y
  su dynamic action, y la región de chips "Tracing / Audit" de la pestaña
  Code.

Siguen instalados, sin enlace desde la UI:

- Las páginas 500 (lista) y 510 (formulario).

- El paquete `arw_target_profiles_api` y la tabla `arw_target_profiles`.

---

## Cómo reactivarlo

### Volver a poner el menú

Restaurar la entrada `target-profiles` en `lists.apx` con la página 500.

### Volver a poner el selector en el editor

Restaurar `P210_TARGET_PROFILE_ID` y pasarlo como `p_target_profile_id` a
`arw_codegen_api.get_artifact` (región `codeDC`) y a `build_apx_bundle`
(proceso `download-bundle`).

> **Nota:** el estado previo completo está en `main` antes del PR de
> Phase 2: `git show 66eec29:apex/arw/pages/p00210-endpoint-editor.apx`.
