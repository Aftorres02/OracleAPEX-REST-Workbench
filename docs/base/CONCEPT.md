# REST Workbench for Oracle APEX — Concepto

> Estado: planeación. Prefijo de objetos `arw_` (provisional).
> Requiere Oracle APEX 26.1 y SQLcl 26.1.2+ para las salidas APEXlang.

---

## 1. El problema

Un desarrollador Oracle que necesita consumir una API REST hoy hace esto:

1. Prueba el endpoint en Postman. Funciona.
2. Traduce a PL/SQL. Falla.
3. Pierde horas en cosas que Postman no podía anticipar: ACL de red ausente,
   certificado fuera del wallet, proxy de la base de datos, TLS no negociado,
   tipos reales distintos a los documentados, errores devueltos dentro de un 200.

Postman genera snippets en ~20 lenguajes. **Ninguno es PL/SQL.**

Y una IA generativa tampoco resuelve el problema de fondo: puede escribir la
llamada, pero **no puede observar la respuesta real**, así que el mapeo de datos
y el contrato del servicio siempre serán una suposición.

---

## 2. Qué es

Una aplicación Oracle APEX que se instala en el entorno de cada desarrollador y
funciona como Postman — pero **probando desde la base de datos** y devolviendo
código Oracle listo para implementar.

> **La frase que define el producto:**
> Postman prueba desde tu laptop. Esta herramienta prueba desde tu base de datos.
> Un test verde aquí significa que va a funcionar en producción.

---

## 3. El ciclo

```
Configurar → Ejecutar (desde la BD) → Observar respuesta real → Materializar
```

La materialización tiene **dos categorías**, y esa distinción es el corazón del
producto:

| Categoría | Qué hace el dev con el resultado |
|---|---|
| **Pegar** | Va dentro de su código: bloque anónimo, paquete, `json_table`, cURL |
| **Instalar** | No se pega. Se importa con SQLcl y **crea componentes APEX** |

Postman solo tiene la primera categoría. La segunda existe únicamente porque
APEXlang convirtió las aplicaciones APEX en texto con gramática formal.

---

## 4. Catálogo de salidas

### Categoría "pegar"

| Salida | Cuándo |
|---|---|
| Bloque anónimo con `apex_web_service` | prueba rápida, copiar y correr |
| Paquete `_api` completo | integración real, con estándares y JavaDoc |
| `utl_http` crudo | esquema sin APEX instalado |
| `dbms_cloud.send_request` | Autonomous Database |
| `json_table` | parsear la respuesta (derivado de la respuesta observada) |
| DDL de tabla o tipo destino | persistir el resultado |
| cURL | reportar el problema al proveedor del servicio |

### Categoría "instalar" (APEXlang `.apx`)

| Componente | Resultado en la app del dev |
|---|---|
| `restDataSourceServer` + `webCredential` + `restDataSource` + `dataProfile` | REST Data Source configurado, listo para un Interactive Report |
| `installScript` (`type: packageBody`) | el paquete generado viaja dentro del export de la app |
| `tool` dentro de `aiAgent` | el endpoint queda invocable por el chatbot de la app |
| `automation` con `restSynchronization` | sincronización programada del endpoint a tabla local |
| `jsonDualityView` | lectura/escritura JSON sobre los datos sincronizados |

### Scripts de entorno

- `apex_credential.create_credential` (por ambiente, secretos aparte)
- `dbms_network_acl_admin.append_host_ace` (ACL de red)

---

## 5. Por qué esto no lo cubre otra herramienta

| Alternativa | Qué le falta |
|---|---|
| **Postman** | cero salidas Oracle; prueba desde la laptop, no desde la BD |
| **Una IA generativa** | no observa la respuesta real; el `dataProfile` sería inventado. La propia skill de Oracle prohíbe adivinarlo: *"Never guess profile shape"* |
| **REST Data Sources nativo** | atado al runtime APEX; no sirve para jobs ni paquetes externos; no cubre auth exótica |
| **APEXlang (skill oficial)** | cubre el consumo declarativo pero **no menciona `apex_web_service` en ningún archivo**; y no tiene forma de descubrir el perfil de datos |

El hueco es real y verificable: APEXlang exige un `dataProfile` exacto y no
provee la manera de obtenerlo. Esta herramienta es ese eslabón.

---

## 6. Modelo de distribución

Igual que Postman:

- **Se instala en el entorno de cada desarrollador.** Sus endpoints, sus
  ambientes, sus credenciales — nunca salen de su base de datos.
- **Lo único compartido es el instalador**, que se distribuye y actualiza usando
  el propio `supportingObject` de APEXlang (prerequisites / installation /
  upgrade / deinstall).
- Los secretos **nunca** se guardan en tablas propias: viven en el credential
  store nativo de APEX y el código generado solo referencia el `static_id`.

---

## 7. Decisiones de diseño ya tomadas

1. **Traza y auditoría son ejes independientes**, no una escala. El dev elige
   traza (ninguna / `apex_debug` / `logger`) y auditoría (sí / no) por separado.
   `apex_debug` es el default porque no tiene dependencias.
2. **`apex_debug` o `logger` se invocan desde un único punto** dentro del paquete
   generado, para que cambiar de framework toque un solo lugar.
3. **La auditoría redacta headers sensibles siempre**, no como opción. Guardar
   `Authorization` en claro sería guardar la contraseña.
4. **La auditoría escribe fuera de la transacción del llamador**, para no perder
   la evidencia justo cuando el proceso falla y hace rollback.
5. **Auth simple vs. auth algorítmica.** Basic / Bearer / API key son *datos* y
   se resuelven inline. SigV4 / JWT firmado / OAuth2 con refresh son *algoritmos*
   y se emiten como paquete firmador compartido, una sola vez por proyecto.
6. **Perfil de destino** (prefijo, esquema, traza, auditoría, tipo de instancia,
   versión de BD/APEX) se define una vez y se reutiliza. Generar código que no
   compila en la instancia del usuario destruye la confianza en el primer intento.

---

## 8. Alcance

### Dentro de v1

- Colecciones, ambientes, variables `{{...}}`
- Credenciales vía `apex_credential` (basic, bearer, API key)
- Ejecución real con `apex_web_service` + historial de request/response
- **Preflight de ACL y wallet** con script de corrección
- Code panel: bloque anónimo, paquete `_api`, `json_table`, cURL
- Import de colecciones de Postman (`.json`)

### v2

- Salidas APEXlang (`restDataSource`, `installScript`, AI tool)
- Aserciones sobre la respuesta + `is json validate using schema` (23ai)
- Runner de colección
- OAuth2 client credentials

### v3+

- Auth algorítmica (SigV4, JWT firmado, mTLS)
- `dbms_cloud` / Autonomous
- `automation` + `jsonDualityView`
- Import de OpenAPI / Swagger

### Fuera de alcance

- Publicar servicios REST (eso es ORDS, otro producto)
- Mock servers, WebSocket, GraphQL
- Clonar la experiencia de usuario de Postman

---

## 9. El riesgo que hay que atacar primero

**La primera ejecución es el momento de la verdad.** Si el dev instala, prueba un
endpoint y recibe `ORA-24247`, abandona la herramienta y no vuelve.

El preflight de ACL/wallet no es una feature secundaria. Es supervivencia y
tiene que estar en v1.

---

## 10. Pendientes de validar contra una instancia real

| Punto | Cómo |
|---|---|
| Propiedades exactas de `installScript` y `supportingObject` | `node tools/query-valid-props.mjs` del repo `oracle/skills` |
| Tipos de `webCredential` disponibles en 26.1 | mismo comando |
| Que el `.apx` generado pase validación | `apexctl.mjs runtime validate` |

Nada de esto se ha ejecutado. La gramática EBNF (11.743 líneas, build
`26.1.0+3102`) es la fuente de verdad usada para redactar estos documentos.
