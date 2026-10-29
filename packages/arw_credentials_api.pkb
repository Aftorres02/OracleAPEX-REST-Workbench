-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_credentials_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  -- One code for every credential error (validation, not found, still in
  -- use, no APEX session) -- the message tells them apart.
  gc_err_credential constant number := -20948;

  -- Mirrors ck_arw_credentials_auth_type; keep both lists in sync.
  gc_auth_types        constant varchar2(400 char) := ':basic:bearer:api_key_header:api_key_query'
                                                     || ':oauth2_client_credentials:oauth2_password'
                                                     || ':oci:mtls:sigv4:jwt_signed:';

  -- Types resolved purely through a Web Credential static ID (arw_auth_utils)
  gc_simple_auth_types constant varchar2(100 char) := ':basic:bearer:api_key_header:api_key_query:';








  -- ===========================================================================
  -- PROCEDURE: validate_credential (private)
  -- ===========================================================================
  /**
   * Raises gc_err_credential unless the metadata is complete: a name, a
   * known auth_type_code, and -- for the four types that resolve purely
   * through a Web Credential (basic, bearer, api_key_header, api_key_query)
   * -- a static ID to resolve to.
   *
   * @example
   * -- Private: exercised through the public API. A bearer credential
   * -- without a static ID fails with ORA-20948.
   * declare
   *   l_credential_id arw_credentials.credential_id%type;
   * begin
   *   l_credential_id := arw_credentials_api.create_credential(
   *       p_name                               => 'Acme bearer'
   *     , p_auth_type_code                     => 'bearer'
   *     , p_apex_credential_static_id          => null
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_name Display name of the credential
   * @param p_auth_type_code Authentication type code
   * @param p_apex_credential_static_id Static ID of the Web Credential
   */
  procedure validate_credential(
      p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_apex_credential_static_id               in arw_credentials.apex_credential_static_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'validate_credential';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_auth_type_code', p_auth_type_code);
    logger.append_param(l_params, 'p_apex_credential_static_id', p_apex_credential_static_id);
    logger.log('START', l_scope, null, l_params);

    if trim(p_name) is null then
      raise_application_error(gc_err_credential, 'Credential name is required.');
    end if;

    if p_auth_type_code is null
       or instr(gc_auth_types, ':' || p_auth_type_code || ':') = 0
    then
      raise_application_error(gc_err_credential, 'Unknown auth type: ' || nvl(p_auth_type_code, '(null)'));
    end if;

    if instr(gc_simple_auth_types, ':' || p_auth_type_code || ':') > 0
       and trim(p_apex_credential_static_id) is null
    then
      raise_application_error(gc_err_credential, 'Auth type ' || p_auth_type_code || ' needs the static ID of a Web Credential.');
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end validate_credential;








  -- ===========================================================================
  -- FUNCTION: apex_credential_type (private)
  -- ===========================================================================
  /**
   * Maps an ARW auth_type_code to the apex_credential authentication type
   * the Web Credential is created with (SKILL.md Step 2 table). Null for
   * types create_web_credential does not create (OAuth2, OCI, mTLS, SigV4,
   * signed JWT -- those are configured in Shared Components).
   *
   * @example
   * -- Private: exercised through create_web_credential. An unsupported
   * -- type fails with ORA-20948 before any apex_credential call.
   * begin
   *   arw_credentials_api.create_web_credential(
   *       p_static_id                          => 'ACME_SIGV4'
   *     , p_name                               => 'Acme SigV4'
   *     , p_auth_type_code                     => 'sigv4'
   *     , p_client_id                          => 'key-id'
   *     , p_client_secret                      => 'secret'
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_auth_type_code  ARW authentication type code
   * @return varchar2          BASIC, HTTP_HEADER, HTTP_QUERY_STRING, or null
   */
  function apex_credential_type(
      p_auth_type_code                          in arw_credentials.auth_type_code%type
  )
  return varchar2
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'apex_credential_type';
    l_params    logger.tab_param;
    l_apex_type varchar2(60 char);
  begin
    logger.append_param(l_params, 'p_auth_type_code', p_auth_type_code);
    logger.log('START', l_scope, null, l_params);

    l_apex_type := case p_auth_type_code
                     when 'basic'          then apex_credential.c_type_basic
                     when 'bearer'         then apex_credential.c_type_http_header
                     when 'api_key_header' then apex_credential.c_type_http_header
                     when 'api_key_query'  then apex_credential.c_type_http_query_string
                   end;

    logger.append_param(l_params, 'l_apex_type', l_apex_type);
    logger.log('END', l_scope, null, l_params);

    return l_apex_type;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end apex_credential_type;








  -- ===========================================================================
  -- FUNCTION: create_credential
  -- ===========================================================================
  /**
   * Creates credential metadata: a name, an auth type and the static ID of
   * the Web Credential that holds the secret. The Web Credential itself may
   * not exist yet -- preflight reports it as a warning and offers to create
   * it (create_web_credential).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_credential_id arw_credentials.credential_id%type;
   * begin
   *   l_credential_id := arw_credentials_api.create_credential(
   *       p_name                               => 'Acme bearer'
   *     , p_auth_type_code                     => 'bearer'
   *     , p_apex_credential_static_id          => 'ACME_BEARER'
   *   );
   *   dbms_output.put_line('credential_id = ' || l_credential_id);
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_name Display name of the credential
   * @param p_auth_type_code Authentication type code (see ck_arw_credentials_auth_type)
   * @param p_apex_credential_static_id Static ID of the Web Credential; required for basic, bearer, api_key_header, api_key_query
   * @return arw_credentials.credential_id%type  Identifier of the created credential
   */
  function create_credential(
      p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_apex_credential_static_id               in arw_credentials.apex_credential_static_id%type default null
  )
  return arw_credentials.credential_id%type
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'create_credential';
    l_params        logger.tab_param;
    l_credential_id arw_credentials.credential_id%type;
  begin
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_auth_type_code', p_auth_type_code);
    logger.append_param(l_params, 'p_apex_credential_static_id', p_apex_credential_static_id);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject incomplete metadata before inserting.
    -- =========================================================================

    validate_credential(
        p_name                                  => p_name
      , p_auth_type_code                        => p_auth_type_code
      , p_apex_credential_static_id             => p_apex_credential_static_id
    );
    -- =========================================================================

    insert
      into arw_credentials (
           name
         , auth_type_code
         , apex_credential_static_id
      )
    values (
           trim(p_name)
         , p_auth_type_code
         , trim(p_apex_credential_static_id)
      )
    returning credential_id into l_credential_id;

    logger.append_param(l_params, 'l_credential_id', l_credential_id);
    logger.log('END', l_scope, null, l_params);

    return l_credential_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_credential;








  -- ===========================================================================
  -- PROCEDURE: update_credential
  -- ===========================================================================
  /**
   * Updates an active credential's name, auth type and Web Credential
   * static ID.
   *
   * @example
   * begin
   *   arw_credentials_api.update_credential(
   *       p_credential_id                      => 1
   *     , p_name                               => 'Acme bearer'
   *     , p_auth_type_code                     => 'bearer'
   *     , p_apex_credential_static_id          => 'ACME_BEARER'
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_credential_id Credential to update
   * @param p_name Display name of the credential
   * @param p_auth_type_code Authentication type code (see ck_arw_credentials_auth_type)
   * @param p_apex_credential_static_id Static ID of the Web Credential; required for basic, bearer, api_key_header, api_key_query
   */
  procedure update_credential(
      p_credential_id                           in arw_credentials.credential_id%type
    , p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_apex_credential_static_id               in arw_credentials.apex_credential_static_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'update_credential';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_auth_type_code', p_auth_type_code);
    logger.append_param(l_params, 'p_apex_credential_static_id', p_apex_credential_static_id);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject incomplete metadata before updating.
    -- =========================================================================

    validate_credential(
        p_name                                  => p_name
      , p_auth_type_code                        => p_auth_type_code
      , p_apex_credential_static_id             => p_apex_credential_static_id
    );
    -- =========================================================================

    update arw_credentials
       set name                       = trim(p_name)
         , auth_type_code             = p_auth_type_code
         , apex_credential_static_id  = trim(p_apex_credential_static_id)
     where credential_id = p_credential_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_credential, 'Credential not found: ' || p_credential_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_credential;








  -- ===========================================================================
  -- PROCEDURE: deactivate_credential
  -- ===========================================================================
  /**
   * Soft-deletes a credential (active_yn = N). Refuses while an active
   * endpoint still uses it -- arw_auth_utils would otherwise fail every
   * call of that endpoint with "Credential not found". The Web Credential
   * in the APEX store is left untouched (it may be shared with other apps).
   * last_updated_by/on are left to the compound trigger, per
   * ddl-conventions.md section 5.
   *
   * @example
   * begin
   *   arw_credentials_api.deactivate_credential(
   *       p_credential_id                      => 1
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_credential_id Credential to deactivate
   */
  procedure deactivate_credential(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'deactivate_credential';
    l_params      logger.tab_param;
    l_endpoints_n number;
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as endpoints_n
      into l_endpoints_n
      from arw_endpoints e
     where e.credential_id = p_credential_id
       and e.active_yn = 'Y';

    if l_endpoints_n > 0 then
      raise_application_error(gc_err_credential, 'Credential is still used by ' || l_endpoints_n || ' active endpoint(s) -- unlink them first.');
    end if;

    update arw_credentials
       set active_yn = 'N'
     where credential_id = p_credential_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_credential, 'Credential not found: ' || p_credential_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end deactivate_credential;








  -- ===========================================================================
  -- FUNCTION: web_credential_type (private)
  -- ===========================================================================
  /**
   * Returns the APEX authentication type (BASIC, HTTP_HEADER, ...) of the
   * Web Credential with this static ID, or null when there is none. Reads
   * the apex_workspace_credentials dictionary view, which a workspace
   * schema can query even without an APEX session; inside a session it is
   * narrowed to the session's workspace. Raises when the view cannot be
   * read -- web_credential_exists turns that into "?".
   *
   * Deliberately NOT apex_credential.get_credential_details: verified on
   * APEX 26.1, outside a web service call it raises ORA-20987 ("Credential
   * is not allowed to be used for this URL endpoint") for every credential
   * that does exist, and APEX's error handling then rolls back the caller's
   * transaction -- it is not an existence check.
   *
   * @example
   * -- Private: exercised through web_credential_exists.
   * select arw_credentials_api.web_credential_exists(
   *            p_static_id                    => 'ACME_BEARER'
   *        )                                                 as exists_yn
   *   from dual;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_static_id  Static ID of the Web Credential
   * @return varchar2     APEX credential type code; null when not found
   */
  function web_credential_type(
      p_static_id                               in arw_credentials.apex_credential_static_id%type
  )
  return varchar2
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'web_credential_type';
    l_params       logger.tab_param;
    l_workspace    varchar2(255 char);
    l_type_code    varchar2(60 char);
  begin
    logger.append_param(l_params, 'p_static_id', p_static_id);
    logger.log('START', l_scope, null, l_params);

    if sys_context('APEX$SESSION', 'WORKSPACE_ID') is not null then
      l_workspace := apex_util.find_workspace(p_security_group_id => sys_context('APEX$SESSION', 'WORKSPACE_ID'));
    end if;

    select max(c.credential_type_code)                     as credential_type_code
      into l_type_code
      from apex_workspace_credentials c
     where c.static_id = trim(p_static_id)
       and (   l_workspace is null
            or c.workspace = l_workspace);

    logger.append_param(l_params, 'l_type_code', l_type_code);
    logger.log('END', l_scope, null, l_params);

    return l_type_code;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end web_credential_type;








  -- ===========================================================================
  -- FUNCTION: web_credential_exists
  -- ===========================================================================
  /**
   * Y when a Web Credential with this static ID exists in the workspace's
   * credential store, N when it does not (or the static ID is null), ? when
   * the store cannot be read in this context. Works from a page request and
   * from a plain database session alike (see web_credential_type for why
   * it reads apex_workspace_credentials instead of calling
   * apex_credential.get_credential_details). The secret is never read.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line('exists = ' || arw_credentials_api.web_credential_exists(
   *       p_static_id                          => 'ACME_BEARER'
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_static_id  Static ID of the Web Credential
   * @return varchar2     Y (exists), N (does not exist, or null static ID), ? (store not readable here)
   */
  function web_credential_exists(
      p_static_id                               in arw_credentials.apex_credential_static_id%type
  )
  return varchar2
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'web_credential_exists';
    l_params    logger.tab_param;
    l_exists_yn varchar2(1 char);
  begin
    logger.append_param(l_params, 'p_static_id', p_static_id);
    logger.log('START', l_scope, null, l_params);

    if trim(p_static_id) is null then
      l_exists_yn := 'N';
    else
      begin
        l_exists_yn := case
                         when web_credential_type(p_static_id => p_static_id) is not null then 'Y'
                         else 'N'
                       end;
      exception
        when others then
          -- The store could not be read in this context -- report "can't
          -- tell", not "missing".
          logger.log_warning('Credential store not readable: ' || sqlerrm, l_scope, null, l_params);
          l_exists_yn := '?';
      end;
    end if;

    logger.append_param(l_params, 'l_exists_yn', l_exists_yn);
    logger.log('END', l_scope, null, l_params);

    return l_exists_yn;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end web_credential_exists;








  -- ===========================================================================
  -- PROCEDURE: create_web_credential
  -- ===========================================================================
  /**
   * Creates the real Web Credential in the APEX credential store and saves
   * its secret persistently (apex_credential.create_credential +
   * set_persistent_credentials). When the static ID already exists with the
   * same authentication type, only the stored secret (and the allowed URL,
   * when given) is replaced -- a rotation. The secret is passed straight to
   * apex_credential: it is never logged, stored in an ARW table, or
   * returned.
   *
   * Mapping (SKILL.md Step 2):
   *   basic          -> BASIC              client id = user name,   secret = password
   *   bearer         -> HTTP_HEADER        client id = Authorization (default), secret = Bearer <token>
   *   api_key_header -> HTTP_HEADER        client id = header name, secret = key
   *   api_key_query  -> HTTP_QUERY_STRING  client id = parameter name, secret = key
   * Other auth types raise ORA-20948 -- configure them in Shared Components.
   *
   * Needs an APEX session context (a page request, or
   * apex_util.set_security_group_id in a script) and raises ORA-20948
   * without one. From a page, the application must allow Runtime API Usage
   * "Modify Workspace Repository", or APEX raises ORA-20987 "An API call
   * has been prohibited". Does not commit -- the caller's transaction (the
   * page process) does.
   *
   * @example
   * begin
   *   apex_util.set_security_group_id(
   *       p_security_group_id                  => apex_util.find_security_group_id(p_workspace => 'DEV_AI_1')
   *   );
   *   arw_credentials_api.create_web_credential(
   *       p_static_id                          => 'ACME_BEARER'
   *     , p_name                               => 'Acme bearer'
   *     , p_auth_type_code                     => 'bearer'
   *     , p_client_id                          => null
   *     , p_client_secret                      => '<token>'
   *     , p_allowed_url                        => 'https://api.acme.com/'
   *   );
   *   commit;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_static_id Static ID of the Web Credential to create
   * @param p_name Display name of the Web Credential; defaults to the static ID
   * @param p_auth_type_code basic, bearer, api_key_header or api_key_query
   * @param p_client_id User name (basic), header name (api_key_header, bearer -- default Authorization) or query parameter name (api_key_query)
   * @param p_client_secret Password, token or key -- never logged or stored by ARW
   * @param p_allowed_url URL prefix the credential may be sent to; null for no restriction
   */
  procedure create_web_credential(
      p_static_id                               in arw_credentials.apex_credential_static_id%type
    , p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_client_id                               in varchar2
    , p_client_secret                           in varchar2
    , p_allowed_url                             in varchar2 default null
  )
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'create_web_credential';
    l_params        logger.tab_param;
    l_static_id     arw_credentials.apex_credential_static_id%type := trim(p_static_id);
    l_apex_type     varchar2(60 char);
    l_existing_type varchar2(60 char);
    l_client_id     varchar2(4000 char);
    l_secret        varchar2(32767);
    l_allowed_urls  apex_t_varchar2;
  begin
    -- p_client_secret is deliberately never appended to l_params
    logger.append_param(l_params, 'p_static_id', p_static_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_auth_type_code', p_auth_type_code);
    logger.append_param(l_params, 'p_client_id', p_client_id);
    logger.append_param(l_params, 'p_allowed_url', p_allowed_url);
    logger.log('START', l_scope, null, l_params);

    if l_static_id is null then
      raise_application_error(gc_err_credential, 'A static ID is required to create a Web Credential.');
    end if;

    l_apex_type := apex_credential_type(p_auth_type_code => p_auth_type_code);

    if l_apex_type is null then
      raise_application_error(gc_err_credential, 'Web Credentials for auth type ' || nvl(p_auth_type_code, '(null)')
                                                  || ' are not created by ARW -- configure them in Shared Components > Web Credentials.');
    end if;

    if p_client_secret is null then
      raise_application_error(gc_err_credential, 'The secret (password, token or key) is required.');
    end if;

    l_client_id := case p_auth_type_code
                     when 'bearer' then nvl(trim(p_client_id), 'Authorization')
                     else trim(p_client_id)
                   end;

    if l_client_id is null then
      raise_application_error(gc_err_credential, case p_auth_type_code
                                                   when 'basic' then 'The user name is required.'
                                                   when 'api_key_header' then 'The header name is required.'
                                                   else 'The query parameter name is required.'
                                                 end);
    end if;

    if sys_context('APEX$SESSION', 'WORKSPACE_ID') is null then
      raise_application_error(gc_err_credential, 'Creating a Web Credential needs an APEX session -- run it from the application, '
                                                  || 'or call apex_util.set_security_group_id first in a script.');
    end if;

    -- A bearer Web Credential sends its secret verbatim as the header value
    l_secret := case
                  when p_auth_type_code = 'bearer'
                   and lower(p_client_secret) not like 'bearer %' then 'Bearer ' || p_client_secret
                  else p_client_secret
                end;

    if trim(p_allowed_url) is not null then
      l_allowed_urls := apex_t_varchar2(trim(p_allowed_url));
    end if;

    l_existing_type := web_credential_type(p_static_id => l_static_id);

    if l_existing_type is null then
      apex_credential.create_credential(
          p_credential_name                     => nvl(trim(p_name), l_static_id)
        , p_credential_static_id                => l_static_id
        , p_authentication_type                 => l_apex_type
        , p_allowed_urls                        => l_allowed_urls
        , p_credential_comment                  => 'Created by ARW (APEX REST Workbench).'
      );
    elsif l_existing_type != l_apex_type then
      raise_application_error(gc_err_credential, 'Web Credential ' || l_static_id || ' already exists with type '
                                                  || l_existing_type || ', not ' || l_apex_type || '.');
    end if;

    if l_apex_type = apex_credential.c_type_basic then
      apex_credential.set_persistent_credentials(
          p_credential_static_id                => l_static_id
        , p_username                            => l_client_id
        , p_password                            => l_secret
      );
    else
      apex_credential.set_persistent_credentials(
          p_credential_static_id                => l_static_id
        , p_client_id                           => l_client_id
        , p_client_secret                       => l_secret
      );
    end if;

    -- Rotation of an existing credential: replace its allowed URL too
    if l_existing_type is not null and l_allowed_urls is not null then
      apex_credential.set_allowed_urls(
          p_credential_static_id                => l_static_id
        , p_allowed_urls                        => l_allowed_urls
        , p_client_secret                       => l_secret
      );
    end if;

    logger.append_param(l_params, 'l_existing_type', l_existing_type);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_web_credential;


end arw_credentials_api;
/
