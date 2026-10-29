-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_import_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  -- One code for every import rejection (empty, invalid JSON, not v2.1)
  gc_err_import constant number := -20949;

  gc_environment_name constant arw_environments.name%type := 'dev';

  gc_name_separator constant varchar2(3 char) := ' / ';

  -- Base URL used when the collection's own one cannot be resolved
  gc_placeholder_base_url constant arw_environments.base_url%type := 'https://example.com';

  type t_text_map       is table of varchar2(4000 char) index by varchar2(200 char);
  type t_credential_map is table of arw_credentials.credential_id%type index by varchar2(300 char);

  -- State of the import in progress -- reset by import_postman
  g_collection_id   arw_collections.collection_id%type;
  g_collection_name arw_collections.name%type;
  g_variables       t_text_map;
  g_credentials     t_credential_map;
  g_base_url        arw_environments.base_url%type;
  g_endpoint_n      pls_integer;
  g_header_n        pls_integer;
  g_param_n         pls_integer;
  g_body_n          pls_integer;
  g_variable_n      pls_integer;
  g_credential_n    pls_integer;
  g_redacted_n      pls_integer;
  g_other_base_n    pls_integer;
  g_skipped         varchar2(4000 char);

  -- Summary of the last import in this database session
  g_summary         varchar2(4000 char);








  -- ===========================================================================
  -- PROCEDURE: note_skipped (private)
  -- ===========================================================================
  /**
   * Records an item or element the import could not bring over, for the
   * summary returned by last_import_summary (each reason once).
   *
   * @example
   * -- Private: exercised through import_postman; a formdata body shows up
   * -- in the summary as skipped.
   * select arw_import_api.last_import_summary                as summary
   *   from dual;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_reason Short description of what was skipped and why
   */
  procedure note_skipped(
      p_reason                                  in varchar2
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'note_skipped';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_reason', p_reason);
    logger.log('START', l_scope, null, l_params);

    if g_skipped is null or instr(g_skipped, p_reason) = 0 then
      g_skipped := substr(g_skipped || case when g_skipped is not null then '; ' end || p_reason, 1, 4000);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end note_skipped;








  -- ===========================================================================
  -- FUNCTION: is_sensitive_name (private)
  -- ===========================================================================
  /**
   * Y when a header, parameter or variable name looks like it carries a
   * secret (Authorization, Cookie, *token*, *secret*, *password*, api key,
   * signature, or a bare key/sig/pwd/auth/session word). Its value is then
   * dropped on import -- secrets are never imported.
   *
   * @example
   * -- Private: exercised through import_postman; an "X-API-Key" header is
   * -- imported with is_sensitive_yn = Y and no value.
   * select h.header_name                                     as header_name
   *      , h.is_sensitive_yn                                 as is_sensitive_yn
   *   from arw_endpoint_headers h
   *  where h.header_name = 'X-API-Key';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_name    Header, parameter or variable name
   * @return varchar2  Y/N
   */
  function is_sensitive_name(
      p_name                                    in varchar2
  )
  return varchar2
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'is_sensitive_name';
    l_params       logger.tab_param;
    l_sensitive_yn varchar2(1 char);
  begin
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);

    l_sensitive_yn := case
                        when regexp_like(lower(p_name), '(token|secret|passw|apikey|api[-_]key|authorization|cookie|credential|signature)')
                          or regexp_like(lower(p_name), '(^|[-_. ])(key|sig|pwd|auth|session|sessionid)($|[-_. ])')
                        then 'Y'
                        else 'N'
                      end;

    logger.log('END', l_scope, null, l_params);

    return l_sensitive_yn;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end is_sensitive_name;








  -- ===========================================================================
  -- FUNCTION: safe_value (private)
  -- ===========================================================================
  /**
   * Returns the value to store for a named header/parameter: the value
   * itself when the name is not sensitive; for a sensitive name, only a
   * pure {{variable}} reference (optionally after an auth scheme word,
   * e.g. "Bearer {{token}}") is kept -- any literal secret is dropped and
   * counted as redacted.
   *
   * @example
   * -- Private: exercised through import_postman. "Authorization: Bearer
   * -- {{token}}" keeps its value; "Authorization: Bearer abc123" is dropped.
   * select h.header_value                                    as header_value
   *   from arw_endpoint_headers h
   *  where h.header_name = 'Authorization';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_name    Header, parameter or variable name
   * @param  p_value   Value found in the collection
   * @return varchar2  Value to store; null when it was a literal secret
   */
  function safe_value(
      p_name                                    in varchar2
    , p_value                                   in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'safe_value';
    l_params logger.tab_param;
    l_value  varchar2(4000 char);
  begin
    -- p_value is deliberately not logged: it may be a secret
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);

    if is_sensitive_name(p_name => p_name) = 'N'
       or regexp_like(p_value, '^\s*([A-Za-z]+\s+)?\{\{[^{}]+\}\}\s*$')
    then
      l_value := substr(p_value, 1, 4000);
    elsif p_value is not null then
      g_redacted_n := g_redacted_n + 1;
    end if;

    logger.log('END', l_scope, null, l_params);

    return l_value;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end safe_value;








  -- ===========================================================================
  -- FUNCTION: text_of (private)
  -- ===========================================================================
  /**
   * Reads a Postman "description"-style member that may be a plain string
   * or an object with a "content" member.
   *
   * @example
   * -- Private: exercised through import_postman (info.description becomes
   * -- the collection description).
   * select c.description                                     as description
   *   from arw_collections c
   *  where c.collection_id = 1;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_object  JSON object holding the member
   * @param  p_key     Member name
   * @return varchar2  The text; null when absent
   */
  function text_of(
      p_object                                  in json_object_t
    , p_key                                     in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'text_of';
    l_params logger.tab_param;
    l_text   varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_key', p_key);
    logger.log('START', l_scope, null, l_params);

    if p_object is not null then
      l_text := coalesce(
                    substr(p_object.get_string(p_key), 1, 4000)
                  , case
                      when p_object.get_object(p_key) is not null then substr(p_object.get_object(p_key).get_string('content'), 1, 4000)
                    end
                );
    end if;

    logger.log('END', l_scope, null, l_params);

    return l_text;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end text_of;








  -- ===========================================================================
  -- FUNCTION: auth_attribute (private)
  -- ===========================================================================
  /**
   * Reads one attribute of a Postman auth object, whose attributes live in
   * an array named after the auth type: {"type": "apikey", "apikey":
   * [{"key": "in", "value": "header"}, ...]}. Only non-secret attributes
   * (the key name, its location, the OAuth2 grant type) are ever read.
   *
   * @example
   * -- Private: exercised through import_postman. An apikey auth "in":
   * -- "query" becomes an api_key_query credential.
   * select c.auth_type_code                                  as auth_type_code
   *   from arw_credentials c
   *  where c.apex_credential_static_id like '%API_KEY%';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_auth    Postman auth object
   * @param  p_key     Attribute name (e.g. key, in, grant_type)
   * @return varchar2  Attribute value; null when absent
   */
  function auth_attribute(
      p_auth                                    in json_object_t
    , p_key                                     in varchar2
  )
  return varchar2
  is
    l_scope      logger_logs.scope%type := gc_scope_prefix || 'auth_attribute';
    l_params     logger.tab_param;
    l_attributes json_array_t;
    l_attribute  json_object_t;
    l_value      varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_key', p_key);
    logger.log('START', l_scope, null, l_params);

    l_attributes := p_auth.get_array(p_auth.get_string('type'));

    if l_attributes is not null then
      for i in 0 .. l_attributes.get_size - 1 loop
        if l_attributes.get(i).is_object then
          l_attribute := treat(l_attributes.get(i) as json_object_t);

          if l_attribute.get_string('key') = p_key then
            l_value := substr(l_attribute.get_string('value'), 1, 4000);
            exit;
          end if;
        end if;
      end loop;
    end if;

    logger.log('END', l_scope, null, l_params);

    return l_value;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end auth_attribute;








  -- ===========================================================================
  -- FUNCTION: resolve_credential (private)
  -- ===========================================================================
  /**
   * Maps a Postman auth object to an ARW credential (metadata only -- the
   * secret is never read) and returns its id, creating it on first use:
   * basic -> basic, bearer -> bearer, apikey -> api_key_header or
   * api_key_query (by "in"), oauth2 -> oauth2_client_credentials or
   * oauth2_password (by grant type), awsv4 -> sigv4, jwt -> jwt_signed.
   * The static ID is derived from the collection name and the auth type
   * (e.g. ACME_API_BEARER); an existing active credential with the same
   * static ID and type is reused, so re-imports don't duplicate it. Null
   * for noauth and for types ARW cannot model (noted as skipped).
   *
   * @example
   * -- Private: exercised through import_postman. A collection-level bearer
   * -- auth yields one credential shared by every endpoint that inherits it.
   * select e.name                                            as endpoint_name
   *      , c.apex_credential_static_id                       as static_id
   *   from arw_endpoints e
   *   join arw_credentials c on c.credential_id = e.credential_id;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_auth  Postman auth object in effect for the request; null for none
   * @return arw_credentials.credential_id%type  Credential to link; null for no auth
   */
  function resolve_credential(
      p_auth                                    in json_object_t
  )
  return arw_credentials.credential_id%type
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'resolve_credential';
    l_params        logger.tab_param;
    l_postman_type  varchar2(60 char);
    l_auth_type     arw_credentials.auth_type_code%type;
    l_key_name      varchar2(200 char);
    l_grant_type    varchar2(60 char);
    l_suffix        varchar2(200 char);
    l_static_id     arw_credentials.apex_credential_static_id%type;
    l_name          arw_credentials.name%type;
    l_map_key       varchar2(300 char);
    l_credential_id arw_credentials.credential_id%type;
  begin
    logger.log('START', l_scope, null, l_params);

    if p_auth is null then
      logger.log('END - no auth', l_scope, null, l_params);
      return null;
    end if;

    l_postman_type := lower(p_auth.get_string('type'));
    logger.append_param(l_params, 'l_postman_type', l_postman_type);

    case l_postman_type
      when 'basic' then
        l_auth_type := 'basic';
        l_suffix    := 'BASIC';
      when 'bearer' then
        l_auth_type := 'bearer';
        l_suffix    := 'BEARER';
      when 'apikey' then
        l_key_name  := auth_attribute(p_auth => p_auth, p_key => 'key');
        l_auth_type := case
                         when lower(auth_attribute(p_auth => p_auth, p_key => 'in')) = 'query' then 'api_key_query'
                         else 'api_key_header'
                       end;
        l_suffix    := nvl(upper(trim(both '_' from regexp_replace(l_key_name, '[^A-Za-z0-9]+', '_'))), 'API_KEY');
      when 'oauth2' then
        l_grant_type := lower(auth_attribute(p_auth => p_auth, p_key => 'grant_type'));
        l_auth_type  := case
                          when l_grant_type = 'client_credentials' then 'oauth2_client_credentials'
                          when l_grant_type in ('password', 'password_credentials') then 'oauth2_password'
                        end;
        l_suffix     := case l_auth_type
                          when 'oauth2_client_credentials' then 'OAUTH2'
                          else 'OAUTH2_PASSWORD'
                        end;
      when 'awsv4' then
        l_auth_type := 'sigv4';
        l_suffix    := 'SIGV4';
      when 'jwt' then
        l_auth_type := 'jwt_signed';
        l_suffix    := 'JWT';
      else
        l_auth_type := null;
    end case;

    if l_postman_type = 'noauth' or l_postman_type is null then
      logger.log('END - noauth', l_scope, null, l_params);
      return null;
    end if;

    if l_auth_type is null then
      note_skipped(p_reason => 'auth type "' || l_postman_type || '"'
                               || case when l_grant_type is not null then ' (grant ' || l_grant_type || ')' end
                               || ' not supported -- endpoints imported without credential');
      logger.log('END - unsupported auth type', l_scope, null, l_params);
      return null;
    end if;

    l_map_key := l_auth_type || ':' || l_suffix;

    if not g_credentials.exists(l_map_key) then
      l_static_id := substr(upper(trim(both '_' from regexp_replace(g_collection_name, '[^A-Za-z0-9]+', '_'))), 1, 100)
                     || '_' || l_suffix;
      l_static_id := substr(ltrim(l_static_id, '_'), 1, 255);
      l_name      := substr(g_collection_name || ' ' || l_auth_type
                            || case when l_key_name is not null then ' (' || l_key_name || ')' end, 1, 200);

      select max(c.credential_id)                          as credential_id
        into l_credential_id
        from arw_credentials c
       where c.apex_credential_static_id = l_static_id
         and c.auth_type_code = l_auth_type
         and c.active_yn = 'Y';

      if l_credential_id is null then

        -- =====================================================================
        -- Metadata only: the Web Credential (and its secret) is created
        -- later by the user -- preflight flags it as missing.
        -- =====================================================================

        l_credential_id := arw_credentials_api.create_credential(
            p_name                              => l_name
          , p_auth_type_code                    => l_auth_type
          , p_apex_credential_static_id         => l_static_id
        );
        -- =====================================================================

        g_credential_n := g_credential_n + 1;
      end if;

      g_credentials(l_map_key) := l_credential_id;
    end if;

    logger.append_param(l_params, 'credential_id', g_credentials(l_map_key));
    logger.log('END', l_scope, null, l_params);

    return g_credentials(l_map_key);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end resolve_credential;








  -- ===========================================================================
  -- FUNCTION: resolve_base_url (private)
  -- ===========================================================================
  /**
   * Turns the base part of a request URL (scheme + host, or a {{variable}}
   * such as {{baseUrl}}) into a literal base URL: every {{name}} with a
   * known, non-secret collection variable value is substituted; a missing
   * scheme gets https://; a trailing slash is removed. A {{variable}} with
   * no value is kept as-is (the user fills the environment in later).
   *
   * @example
   * -- Private: exercised through import_postman. With the variable
   * -- baseUrl = https://api.acme.com, "{{baseUrl}}/users" gives the dev
   * -- environment base_url https://api.acme.com.
   * select v.base_url                                        as base_url
   *   from arw_environments v
   *  where v.name = 'dev';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_base    Base part of the URL, e.g. {{baseUrl}} or https://api.acme.com
   * @return varchar2  Literal base URL when resolvable
   */
  function resolve_base_url(
      p_base                                    in varchar2
  )
  return varchar2
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'resolve_base_url';
    l_params   logger.tab_param;
    l_base     varchar2(4000 char) := p_base;
    l_var_name varchar2(200 char);
    l_guard    pls_integer := 0;
  begin
    logger.append_param(l_params, 'p_base', p_base);
    logger.log('START', l_scope, null, l_params);

    -- Substitute known variables; the guard stops self-referencing values
    loop
      l_var_name := regexp_substr(l_base, '\{\{([^{}]+)\}\}', 1, 1, null, 1);
      exit when l_var_name is null
             or not g_variables.exists(l_var_name)
             or g_variables(l_var_name) is null
             or l_guard > 10;

      l_base  := replace(l_base, '{{' || l_var_name || '}}', g_variables(l_var_name));
      l_guard := l_guard + 1;
    end loop;

    l_base := rtrim(trim(l_base), '/');

    if l_base is not null
       and substr(l_base, 1, 2) != '{{'
       and not regexp_like(l_base, '^[A-Za-z][A-Za-z0-9+.-]*://')
    then
      l_base := 'https://' || l_base;
    end if;

    logger.append_param(l_params, 'l_base', l_base);
    logger.log('END', l_scope, null, l_params);

    return substr(l_base, 1, 1000);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end resolve_base_url;








  -- ===========================================================================
  -- PROCEDURE: split_url (private)
  -- ===========================================================================
  /**
   * Splits a Postman raw URL into its base (scheme + authority, or a
   * leading {{variable}}), path and query string; drops the fragment and
   * any user:password@ embedded in the URL.
   * Postman path variables (/:id) become ARW tokens (/{{id}}). A URL with
   * no scheme and no variable is treated as https.
   *
   * @example
   * -- Private: exercised through import_postman.
   * -- "{{baseUrl}}/users/:id?verbose=true" -> base {{baseUrl}},
   * -- path /users/{{id}}, query verbose=true.
   * select e.url_path                                        as url_path
   *   from arw_endpoints e
   *  where e.url_path like '%{{id}}%';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_raw Raw URL from the collection
   * @param o_base Base part (scheme://host[:port] or {{variable}}...)
   * @param o_path Path starting with "/"; "/" when empty
   * @param o_query Query string without the "?"; null when none
   */
  procedure split_url(
      p_raw                                     in varchar2
    , o_base                                    out varchar2
    , o_path                                    out varchar2
    , o_query                                   out varchar2
  )
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'split_url';
    l_params    logger.tab_param;
    l_raw       varchar2(4000 char);
    l_authority varchar2(4000 char);
  begin
    -- p_raw is deliberately not logged: its query string may carry a secret
    logger.log('START', l_scope, null, l_params);

    l_raw := regexp_replace(trim(p_raw), '#.*$', '');

    if instr(l_raw, '?') > 0 then
      o_query := substr(l_raw, instr(l_raw, '?') + 1);
      l_raw   := substr(l_raw, 1, instr(l_raw, '?') - 1);
    end if;

    if substr(l_raw, 1, 2) = '{{' then
      o_base := regexp_substr(l_raw, '^\{\{[^{}]+\}\}[^/]*');
    elsif regexp_like(l_raw, '^[A-Za-z][A-Za-z0-9+.-]*://') then
      o_base := regexp_substr(l_raw, '^[A-Za-z][A-Za-z0-9+.-]*://[^/]*');
    else
      l_authority := regexp_substr(l_raw, '^[^/]*');
      o_base      := case when l_authority is not null then 'https://' || l_authority end;
      l_raw       := 'https://' || l_raw;
    end if;

    o_path := substr(l_raw, nvl(length(o_base), 0) + 1);

    -- Never keep user:password@ credentials embedded in the URL
    o_base := regexp_replace(o_base, '://[^/@]*@', '://');
    o_path := case
                when o_path is null then '/'
                when substr(o_path, 1, 1) != '/' then '/' || o_path
                else o_path
              end;
    o_path := regexp_replace(o_path, '/:([A-Za-z_][A-Za-z0-9_]*)', '/{{\1}}');

    logger.append_param(l_params, 'o_base', o_base);
    logger.append_param(l_params, 'o_path', o_path);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end split_url;








  -- ===========================================================================
  -- PROCEDURE: import_body (private)
  -- ===========================================================================
  /**
   * Imports a Postman request body: raw (content type from the
   * Content-Type header or the raw language), urlencoded (as an
   * application/x-www-form-urlencoded body; sensitive fields become
   * {{name}} placeholders) and graphql (as a JSON body). formdata and file
   * bodies are skipped -- ARW has no multipart support yet.
   *
   * @example
   * -- Private: exercised through import_postman.
   * select b.content_type                                    as content_type
   *      , b.body_template                                   as body_template
   *   from arw_request_bodies b
   *  where b.endpoint_id = 1;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint the body belongs to
   * @param p_endpoint_name Endpoint name, for the skipped-item note
   * @param p_body Postman body object
   * @param p_header_content_type Content-Type header of the request; null when none
   */
  procedure import_body(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_endpoint_name                           in arw_endpoints.name%type
    , p_body                                    in json_object_t
    , p_header_content_type                     in varchar2
  )
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'import_body';
    l_params       logger.tab_param;
    l_mode         varchar2(30 char);
    l_language     varchar2(30 char);
    l_body         clob;
    l_content_type arw_request_bodies.content_type%type;
    l_graphql      json_object_t;
    l_payload      json_object_t;
    l_body_json    clob;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_header_content_type', p_header_content_type);
    logger.log('START', l_scope, null, l_params);

    if p_body is null or p_body.get_string('disabled') = 'true' then
      logger.log('END - no body', l_scope, null, l_params);
      return;
    end if;

    l_mode := lower(p_body.get_string('mode'));

    if l_mode = 'raw' then
      l_body := p_body.get_clob('raw');

      if p_body.get_object('options') is not null
         and p_body.get_object('options').get_object('raw') is not null
      then
        l_language := lower(p_body.get_object('options').get_object('raw').get_string('language'));
      end if;

      l_content_type := coalesce(
                            p_header_content_type
                          , case l_language
                              when 'json'       then 'application/json'
                              when 'xml'        then 'application/xml'
                              when 'html'       then 'text/html'
                              when 'javascript' then 'application/javascript'
                              when 'text'       then 'text/plain'
                            end
                          , case when substr(ltrim(l_body), 1, 1) in ('{', '[') then 'application/json' else 'text/plain' end
                        );
    elsif l_mode = 'urlencoded' then
      l_body_json := p_body.to_clob;

      for l_field in (
        select f.field_key                                 as field_key
             , f.field_value                               as field_value
          from json_table(l_body_json, '$.urlencoded[*]'
                 columns (
                     field_key          varchar2(200 char)  path '$.key'
                   , field_value        varchar2(4000 char) path '$.value'
                   , disabled           varchar2(10 char)   path '$.disabled'
                 )
               ) f
         where nvl(f.disabled, 'false') != 'true'
           and f.field_key is not null
      )
      loop
        l_body := l_body
                  || case when l_body is not null then '&' end
                  || l_field.field_key || '='
                  || case
                       when is_sensitive_name(p_name => l_field.field_key) = 'Y' then '{{' || l_field.field_key || '}}'
                       else l_field.field_value
                     end;
      end loop;

      l_content_type := 'application/x-www-form-urlencoded';
    elsif l_mode = 'graphql' then
      l_graphql := p_body.get_object('graphql');
      l_payload := json_object_t();

      if l_graphql is not null then
        l_payload.put('query', l_graphql.get_string('query'));

        if l_graphql.get_string('variables') is not null then
          begin
            l_payload.put('variables', json_object_t.parse(l_graphql.get_string('variables')));
          exception
            when others then
              -- Variables that are not valid JSON are kept as a string
              l_payload.put('variables', l_graphql.get_string('variables'));
          end;
        end if;
      end if;

      l_body         := l_payload.to_clob;
      l_content_type := 'application/json';
    elsif l_mode in ('formdata', 'file') then
      note_skipped(p_reason => l_mode || ' body of "' || p_endpoint_name || '" (not supported)');
    end if;

    if l_body is not null then
      arw_endpoint_api.set_body(
          p_endpoint_id                         => p_endpoint_id
        , p_content_type                        => substr(l_content_type, 1, 200)
        , p_body_template                       => l_body
      );

      g_body_n := g_body_n + 1;
    end if;

    logger.append_param(l_params, 'l_mode', l_mode);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end import_body;








  -- ===========================================================================
  -- PROCEDURE: import_request (private)
  -- ===========================================================================
  /**
   * Imports one Postman request item as an endpoint of the collection
   * being imported: method, url_path (relative to the dev environment
   * base URL), enabled headers (Content-Type folds into the body; secret
   * values dropped), enabled query params, path variables (as required
   * path params), the body and the credential of the auth in effect.
   * Requests with an unsupported method or no URL are skipped. A request
   * whose base URL differs from the environment's keeps its relative path
   * and is counted in the summary.
   *
   * @example
   * -- Private: exercised through import_postman.
   * select e.name                                            as name
   *      , e.http_method                                     as http_method
   *      , e.url_path                                        as url_path
   *   from arw_endpoints e
   *  where e.collection_id = 1;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_item Postman item holding a request
   * @param p_name_prefix Folder path of the item ("Users / Admin"); null at the root
   * @param p_inherited_auth Auth inherited from the folders/collection; null for none
   */
  procedure import_request(
      p_item                                    in json_object_t
    , p_name_prefix                             in varchar2
    , p_inherited_auth                          in json_object_t
  )
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'import_request';
    l_params        logger.tab_param;
    l_request       json_object_t;
    l_url           json_object_t;
    l_raw_url       varchar2(4000 char);
    l_request_json  clob;
    l_url_json      clob;
    l_name          arw_endpoints.name%type;
    l_method        arw_endpoints.http_method%type;
    l_base          varchar2(4000 char);
    l_path          varchar2(4000 char);
    l_query         varchar2(4000 char);
    l_auth          json_object_t;
    l_credential_id arw_credentials.credential_id%type;
    l_endpoint_id   arw_endpoints.endpoint_id%type;
    l_content_type  varchar2(200 char);
    l_query_n       pls_integer := 0;
    l_body_n        pls_integer;
    l_id            number;
    l_pair          varchar2(4000 char);
    l_path_value    varchar2(4000 char);
  begin
    l_name := substr(p_name_prefix
                     || case when p_name_prefix is not null then gc_name_separator end
                     || nvl(p_item.get_string('name'), 'Unnamed request'), 1, 200);

    logger.append_param(l_params, 'l_name', l_name);
    logger.log('START', l_scope, null, l_params);

    -- "request" may be a bare URL string (GET) or a request object
    if p_item.get('request').is_string then
      l_raw_url := substr(p_item.get_string('request'), 1, 4000);
      l_method  := 'GET';
    else
      l_request := p_item.get_object('request');
      l_method  := upper(nvl(l_request.get_string('method'), 'GET'));

      if l_request.get('url') is null then
        null;
      elsif l_request.get('url').is_string then
        l_raw_url := substr(l_request.get_string('url'), 1, 4000);
      else
        l_url      := l_request.get_object('url');
        l_url_json := l_url.to_clob;
        l_raw_url  := substr(l_url.get_string('raw'), 1, 4000);

        if l_raw_url is null and l_url.get_array('host') is not null then
          -- No raw form: rebuild it from the structured parts
          for l_part in (
            select listagg(h.part, '.') within group (order by h.seq) as host_name
              from json_table(l_url_json, '$.host[*]'
                     columns (
                         seq            for ordinality
                       , part           varchar2(1000 char) path '$'
                     )
                   ) h
          )
          loop
            l_raw_url := case when l_url.get_string('protocol') is not null then l_url.get_string('protocol') || '://' end
                         || l_part.host_name
                         || case when l_url.get_string('port') is not null then ':' || l_url.get_string('port') end;
          end loop;

          for l_part in (
            select listagg(p.part, '/') within group (order by p.seq) as path_name
              from json_table(l_url_json, '$.path[*]'
                     columns (
                         seq            for ordinality
                       , part           varchar2(1000 char) path '$'
                     )
                   ) p
          )
          loop
            l_raw_url := l_raw_url || case when l_part.path_name is not null then '/' || l_part.path_name end;
          end loop;
        end if;
      end if;
    end if;

    if l_raw_url is null then
      note_skipped(p_reason => '"' || l_name || '" (no URL)');
      logger.log('END - no URL', l_scope, null, l_params);
      return;
    end if;

    if l_method not in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS') then
      note_skipped(p_reason => '"' || l_name || '" (method ' || l_method || ' not supported)');
      logger.log('END - unsupported method', l_scope, null, l_params);
      return;
    end if;

    split_url(
        p_raw                                   => l_raw_url
      , o_base                                  => l_base
      , o_path                                  => l_path
      , o_query                                 => l_query
    );

    l_base := resolve_base_url(p_base => l_base);

    if g_base_url is null then
      g_base_url := l_base;
    elsif l_base is not null and l_base != g_base_url then
      g_other_base_n := g_other_base_n + 1;
    end if;

    -- Request-level auth wins; {"type": "noauth"} explicitly disables it
    l_auth := case
                when l_request is not null and l_request.get_object('auth') is not null then l_request.get_object('auth')
                else p_inherited_auth
              end;

    l_credential_id := resolve_credential(p_auth => l_auth);

    l_endpoint_id := arw_endpoint_api.create_endpoint(
        p_collection_id                         => g_collection_id
      , p_name                                  => l_name
      , p_http_method                           => l_method
      , p_url_path                              => substr(l_path, 1, 1000)
      , p_credential_id                         => l_credential_id
    );

    g_endpoint_n := g_endpoint_n + 1;

    if l_request is not null then
      l_request_json := l_request.to_clob;


      -- =======================================================================
      -- Headers -- Content-Type is kept for the body, secrets are dropped.
      -- =======================================================================

      for l_header in (
        select h.header_key                                as header_key
             , h.header_value                              as header_value
          from json_table(l_request_json, '$.header[*]'
                 columns (
                     header_key         varchar2(200 char)  path '$.key'
                   , header_value       varchar2(4000 char) path '$.value'
                   , disabled           varchar2(10 char)   path '$.disabled'
                 )
               ) h
         where nvl(h.disabled, 'false') != 'true'
           and h.header_key is not null
      )
      loop
        if lower(l_header.header_key) = 'content-type' then
          l_content_type := substr(l_header.header_value, 1, 200);
        else
          l_id := arw_endpoint_api.add_header(
              p_endpoint_id                     => l_endpoint_id
            , p_header_name                     => l_header.header_key
            , p_header_value                    => safe_value(
                                                       p_name   => l_header.header_key
                                                     , p_value  => l_header.header_value
                                                   )
            , p_is_sensitive_yn                 => is_sensitive_name(p_name => l_header.header_key)
          );

          g_header_n := g_header_n + 1;
        end if;
      end loop;
      -- =======================================================================


      -- =======================================================================
      -- Query params -- structured url.query[] when present.
      -- =======================================================================

      if l_url is not null then
        for l_param in (
          select q.param_key                               as param_key
               , q.param_value                             as param_value
            from json_table(l_url_json, '$.query[*]'
                   columns (
                       param_key        varchar2(200 char)  path '$.key'
                     , param_value      varchar2(4000 char) path '$.value'
                     , disabled         varchar2(10 char)   path '$.disabled'
                   )
                 ) q
           where nvl(q.disabled, 'false') != 'true'
             and q.param_key is not null
        )
        loop
          l_id := arw_endpoint_api.add_param(
              p_endpoint_id                     => l_endpoint_id
            , p_param_kind_code                 => 'query'
            , p_param_name                      => l_param.param_key
            , p_param_value                     => safe_value(
                                                       p_name   => l_param.param_key
                                                     , p_value  => l_param.param_value
                                                   )
          );

          l_query_n := l_query_n + 1;
        end loop;
      end if;
      -- =======================================================================
    end if;

    -- No structured query list: fall back to the raw query string
    if l_query_n = 0 and l_query is not null then
      for l_part in (
        select s.column_value                              as pair
          from table(apex_string.split(l_query, '&')) s
         where s.column_value is not null
      )
      loop
        l_pair := l_part.pair;

        l_id := arw_endpoint_api.add_param(
            p_endpoint_id                       => l_endpoint_id
          , p_param_kind_code                   => 'query'
          , p_param_name                        => substr(regexp_substr(l_pair, '^[^=]*'), 1, 200)
          , p_param_value                       => safe_value(
                                                     p_name   => regexp_substr(l_pair, '^[^=]*')
                                                   , p_value  => case when instr(l_pair, '=') > 0 then substr(l_pair, instr(l_pair, '=') + 1) end
                                                 )
        );

        l_query_n := l_query_n + 1;
      end loop;
    end if;

    g_param_n := g_param_n + l_query_n;


    -- =========================================================================
    -- Path variables (/:id -> /{{id}}) become required path params.
    -- =========================================================================

    for l_var in (
      select regexp_substr(l_path, '\{\{([^{}]+)\}\}', 1, level, null, 1) as var_name
        from dual
     where l_path like '%{{%'
     connect by level <= regexp_count(l_path, '\{\{[^{}]+\}\}')
    )
    loop
      -- Only Postman path variables (url.variable[]) or :name segments;
      -- {{collection variables}} in the path stay as plain tokens.
      if l_var.var_name is not null
         and not g_variables.exists(l_var.var_name)
         and regexp_like(l_raw_url, '/:' || l_var.var_name || '(/|$|\?|#)')
      then
        l_path_value := null;

        if l_url_json is not null then
          for l_value in (
            select v.var_value                             as var_value
              from json_table(l_url_json, '$.variable[*]'
                     columns (
                         var_key        varchar2(200 char)  path '$.key'
                       , var_value      varchar2(4000 char) path '$.value'
                     )
                   ) v
             where v.var_key = l_var.var_name
          )
          loop
            l_path_value := l_value.var_value;
            exit;
          end loop;
        end if;

        l_id := arw_endpoint_api.add_param(
            p_endpoint_id                       => l_endpoint_id
          , p_param_kind_code                   => 'path'
          , p_param_name                        => l_var.var_name
          , p_param_value                       => safe_value(
                                                     p_name   => l_var.var_name
                                                   , p_value  => l_path_value
                                                 )
          , p_is_required_yn                    => 'Y'
        );

        g_param_n := g_param_n + 1;
      end if;
    end loop;
    -- =========================================================================

    if l_request is not null then
      l_body_n := g_body_n;

      import_body(
          p_endpoint_id                         => l_endpoint_id
        , p_endpoint_name                       => l_name
        , p_body                                => l_request.get_object('body')
        , p_header_content_type                 => l_content_type
      );

      -- No body imported: the Content-Type header stays a plain header
      if g_body_n = l_body_n and l_content_type is not null then
        l_id := arw_endpoint_api.add_header(
            p_endpoint_id                       => l_endpoint_id
          , p_header_name                       => 'Content-Type'
          , p_header_value                      => l_content_type
        );

        g_header_n := g_header_n + 1;
      end if;
    end if;

    logger.append_param(l_params, 'l_endpoint_id', l_endpoint_id);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end import_request;








  -- ===========================================================================
  -- PROCEDURE: import_items (private)
  -- ===========================================================================
  /**
   * Walks a Postman item[] array recursively. A folder (an item with its
   * own item[]) is flattened into the collection: its name is appended to
   * the name prefix of everything below it, and its auth (when set)
   * overrides the inherited one. Flattening -- rather than child
   * collections -- keeps every endpoint in the collection that owns the
   * dev environment, so all of them can be executed right away.
   *
   * @example
   * -- Private: exercised through import_postman. A request "Get user"
   * -- inside folder "Users" > "Admin" is imported as
   * -- "Users / Admin / Get user".
   * select e.name                                            as name
   *   from arw_endpoints e
   *  where e.name like '% / %';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_items Postman item[] array
   * @param p_name_prefix Folder path so far; null at the root
   * @param p_inherited_auth Auth in effect at this level; null for none
   */
  procedure import_items(
      p_items                                   in json_array_t
    , p_name_prefix                             in varchar2
    , p_inherited_auth                          in json_object_t
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'import_items';
    l_params      logger.tab_param;
    l_item        json_object_t;
    l_folder_name varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_name_prefix', p_name_prefix);
    logger.log('START', l_scope, null, l_params);

    if p_items is null then
      logger.log('END - no items', l_scope, null, l_params);
      return;
    end if;

    for i in 0 .. p_items.get_size - 1 loop
      if p_items.get(i).is_object then
        l_item := treat(p_items.get(i) as json_object_t);

        if l_item.get_array('item') is not null then
          l_folder_name := substr(p_name_prefix
                                  || case when p_name_prefix is not null then gc_name_separator end
                                  || nvl(l_item.get_string('name'), 'Folder'), 1, 4000);

          import_items(
              p_items                           => l_item.get_array('item')
            , p_name_prefix                     => l_folder_name
            , p_inherited_auth                  => nvl(l_item.get_object('auth'), p_inherited_auth)
          );
        elsif l_item.get('request') is not null then
          import_request(
              p_item                            => l_item
            , p_name_prefix                     => p_name_prefix
            , p_inherited_auth                  => p_inherited_auth
          );
        end if;
      end if;
    end loop;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end import_items;








  -- ===========================================================================
  -- FUNCTION: import_postman
  -- ===========================================================================
  /**
   * Imports a Postman Collection v2.1 file and returns the new collection.
   *
   * - info.name (or p_collection_name) -> arw_collections; info.description
   *   -> description.
   * - item[] (nested folders flattened, names prefixed with the folder path
   *   "Folder / Subfolder / Request") -> arw_endpoints with headers, query
   *   params, path variables (required path params), body.
   * - Base URL: the first request's base ({{baseUrl}} resolved through the
   *   collection variables) -> a "dev" environment; url_path is relative.
   * - variable[] -> variables of the dev environment; secret-looking ones
   *   (or type "secret") are created empty with is_secret_yn = Y.
   * - auth (collection, folder or request level) -> arw_credentials
   *   metadata with a derived static ID, never the secret.
   * Secrets are never imported: sensitive header/param values are dropped
   * unless they are a pure {{variable}} reference.
   *
   * Does not commit (the page process does); on any error the partial
   * import is rolled back to a savepoint before the error is re-raised.
   * Raises ORA-20949 when the input is empty, not JSON, or not a Postman
   * Collection v2.1 (info.schema). last_import_summary describes the result.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_collection_id arw_collections.collection_id%type;
   * begin
   *   l_collection_id := arw_import_api.import_postman(
   *       p_collection_json                    => q'~{
   *         "info": {"name": "Demo", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
   *         "variable": [{"key": "baseUrl", "value": "https://jsonplaceholder.typicode.com"}],
   *         "item": [{"name": "Get todo", "request": {"method": "GET", "url": "{{baseUrl}}/todos/1"}}]
   *       }~'
   *     , p_collection_name                    => null
   *   );
   *   dbms_output.put_line('collection_id = ' || l_collection_id);
   *   dbms_output.put_line(arw_import_api.last_import_summary);
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_collection_json Content of the Postman Collection v2.1 .json file
   * @param p_collection_name Name for the new collection; null to use info.name
   * @return arw_collections.collection_id%type  Identifier of the created collection
   */
  function import_postman(
      p_collection_json                         in clob
    , p_collection_name                         in varchar2 default null
  )
  return arw_collections.collection_id%type
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'import_postman';
    l_params         logger.tab_param;
    l_root           json_object_t;
    l_info           json_object_t;
    l_schema         varchar2(4000 char);
    l_description    arw_collections.description%type;
    l_environment_id arw_environments.environment_id%type;
    l_variable_id    arw_env_variables.variable_id%type;
    l_var_name       varchar2(200 char);
    l_is_secret_yn   arw_env_variables.is_secret_yn%type;
  begin
    -- The JSON itself is never logged: it may contain secrets
    logger.append_param(l_params, 'p_collection_name', p_collection_name);
    logger.append_param(l_params, 'json_length', dbms_lob.getlength(p_collection_json));
    logger.log('START', l_scope, null, l_params);

    if p_collection_json is null or dbms_lob.getlength(p_collection_json) = 0 then
      raise_application_error(gc_err_import, 'The collection file is empty.');
    end if;

    begin
      l_root := json_object_t.parse(p_collection_json);
    exception
      when others then
        raise_application_error(gc_err_import, 'The file is not a valid JSON object: ' || regexp_substr(sqlerrm, '^[^' || chr(10) || ']*'));
    end;

    l_info   := l_root.get_object('info');
    l_schema := case when l_info is not null then l_info.get_string('schema') end;

    if l_schema is null or not regexp_like(l_schema, '/collection/v2\.1(\.|/|$)', 'i') then
      raise_application_error(gc_err_import, 'Not a Postman Collection v2.1 file (info.schema = '
                                              || nvl(substr(l_schema, 1, 200), 'missing') || '). Export it from Postman as "Collection v2.1".');
    end if;

    if l_root.get_array('item') is null then
      raise_application_error(gc_err_import, 'The collection has no item array.');
    end if;

    savepoint arw_import_start;


    -- =========================================================================
    -- Reset the import state.
    -- =========================================================================

    g_collection_name := substr(coalesce(trim(p_collection_name), trim(l_info.get_string('name')), 'Imported collection'), 1, 200);
    g_variables.delete;
    g_credentials.delete;
    g_base_url     := null;
    g_endpoint_n   := 0;
    g_header_n     := 0;
    g_param_n      := 0;
    g_body_n       := 0;
    g_variable_n   := 0;
    g_credential_n := 0;
    g_redacted_n   := 0;
    g_other_base_n := 0;
    g_skipped      := null;
    g_summary      := null;
    -- =========================================================================

    -- Collection variables first: base URLs resolve through them
    for l_var in (
      select v.var_key                                     as var_key
           , v.var_value                                   as var_value
           , v.var_type                                    as var_type
        from json_table(p_collection_json, '$.variable[*]'
               columns (
                   var_key              varchar2(200 char)  path '$.key'
                 , var_value            varchar2(4000 char) path '$.value'
                 , var_type             varchar2(30 char)   path '$.type'
                 , disabled             varchar2(10 char)   path '$.disabled'
               )
             ) v
       where nvl(v.disabled, 'false') != 'true'
         and v.var_key is not null
    )
    loop
      g_variables(l_var.var_key) := case
                                      when lower(l_var.var_type) = 'secret'
                                        or is_sensitive_name(p_name => l_var.var_key) = 'Y' then null
                                      else l_var.var_value
                                    end;
    end loop;

    l_description := substr(coalesce(text_of(p_object => l_info, p_key => 'description'), 'Imported from a Postman Collection v2.1 file.'), 1, 500);

    g_collection_id := arw_collections_api.create_collection(
        p_name                                  => g_collection_name
      , p_description                           => l_description
    );


    -- =========================================================================
    -- Endpoints, recursively through the folders.
    -- =========================================================================

    import_items(
        p_items                                 => l_root.get_array('item')
      , p_name_prefix                           => null
      , p_inherited_auth                        => l_root.get_object('auth')
    );
    -- =========================================================================


    -- =========================================================================
    -- The dev environment: base URL plus the collection variables.
    -- =========================================================================

    -- arw_environments_api only accepts an http(s)://host base URL; an
    -- unresolved {{variable}} gets a placeholder the user must replace.
    if g_base_url is not null and not regexp_like(g_base_url, '^https?://[^/[:space:]{}]+', 'i') then
      note_skipped(p_reason => 'base URL ' || substr(g_base_url, 1, 200) || ' has no usable value -- set the real one on environment "'
                               || gc_environment_name || '" (placeholder ' || gc_placeholder_base_url || ')');
      g_base_url := gc_placeholder_base_url;
    end if;

    if g_base_url is not null or g_variables.count > 0 then
      l_environment_id := arw_environments_api.create_environment(
          p_collection_id                       => g_collection_id
        , p_name                                => gc_environment_name
        , p_base_url                            => coalesce(g_base_url, gc_placeholder_base_url)
      );
    end if;
    -- =========================================================================

    for l_var in (
      select v.var_key                                     as var_key
           , v.var_value                                   as var_value
           , v.var_type                                    as var_type
        from json_table(p_collection_json, '$.variable[*]'
               columns (
                   var_key              varchar2(200 char)  path '$.key'
                 , var_value            varchar2(4000 char) path '$.value'
                 , var_type             varchar2(30 char)   path '$.type'
                 , disabled             varchar2(10 char)   path '$.disabled'
               )
             ) v
       where nvl(v.disabled, 'false') != 'true'
         and v.var_key is not null
    )
    loop
      l_var_name := l_var.var_key;

      -- {{base_url}} is ARW's own token for the environment base URL
      continue when lower(l_var_name) = 'base_url';

      if not regexp_like(l_var_name, '^[A-Za-z_][A-Za-z0-9_.-]*$') or length(l_var_name) > 200 then
        note_skipped(p_reason => 'variable "' || substr(l_var_name, 1, 100) || '" (name not allowed in ARW)');
        continue;
      end if;

      l_is_secret_yn := case
                          when lower(l_var.var_type) = 'secret'
                            or is_sensitive_name(p_name => l_var_name) = 'Y' then 'Y'
                          else 'N'
                        end;

      if l_is_secret_yn = 'Y' and l_var.var_value is not null then
        g_redacted_n := g_redacted_n + 1;
      end if;

      l_variable_id := arw_environments_api.set_variable(
          p_environment_id                      => l_environment_id
        , p_var_name                            => l_var_name
        , p_var_value                           => case when l_is_secret_yn = 'N' then l_var.var_value end
        , p_is_secret_yn                        => l_is_secret_yn
      );

      g_variable_n := g_variable_n + 1;
    end loop;

    g_summary := substr(
                     g_endpoint_n || ' endpoint(s) in "' || g_collection_name || '", '
                  || g_header_n || ' header(s), '
                  || g_param_n || ' param(s), '
                  || g_body_n || ' request bod' || case when g_body_n = 1 then 'y' else 'ies' end || ', '
                  || g_credential_n || ' new credential(s), '
                  || case
                       when l_environment_id is not null then 'environment "' || gc_environment_name || '" (' || coalesce(g_base_url, '{{baseUrl}}') || ') with '
                                                              || g_variable_n || ' variable(s)'
                       else 'no environment'
                     end
                  || case when g_redacted_n > 0 then '. ' || g_redacted_n || ' secret value(s) not imported' end
                  || case when g_other_base_n > 0 then '. ' || g_other_base_n || ' endpoint(s) use a different base URL -- review them' end
                  || case when g_skipped is not null then '. Skipped: ' || g_skipped end
                  || '.'
                , 1, 4000);

    logger.append_param(l_params, 'g_collection_id', g_collection_id);
    logger.append_param(l_params, 'g_summary', g_summary);
    logger.log('END', l_scope, null, l_params);

    return g_collection_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);

      -- Undo a partial import; nothing to undo when the savepoint was never set
      begin
        rollback to arw_import_start;
      exception
        when others then
          null;
      end;

      raise;
  end import_postman;








  -- ===========================================================================
  -- FUNCTION: last_import_summary
  -- ===========================================================================
  /**
   * One-line summary of the last import_postman call in this database
   * session (counts, base URL, secrets not imported, skipped items) -- for
   * the Import page's success message. Call it in the same request as the
   * import.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_import_api.last_import_summary);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @return varchar2  Summary text; null before any import in this session
   */
  function last_import_summary
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'last_import_summary';
    l_params logger.tab_param;
  begin
    logger.log('START', l_scope, null, l_params);
    logger.log('END', l_scope, null, l_params);

    return g_summary;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end last_import_summary;


end arw_import_api;
/
