-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_exec_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_endpoint_not_found         constant number := -20920;
  gc_err_environment_not_found      constant number := -20921;
  gc_err_environment_mismatch       constant number := -20922;
  gc_err_preflight_failed           constant number := -20923;
  gc_err_param_kind_not_implemented constant number := -20924;
  gc_err_engine_not_implemented     constant number := -20925;








  -- ===========================================================================
  -- FUNCTION: extract_host (private)
  -- ===========================================================================
  /**
   * Extracts the host (no scheme, no port, no path) from a base_url, for
   * arw_preflight_api.run_preflight.
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_url    Full base_url (e.g. https://api.example.com:443)
   * @return varchar2 Host only (e.g. api.example.com); null when p_url does not match
   */
  function extract_host(
      p_url                                     in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'extract_host';
    l_params logger.tab_param;
    l_host   varchar2(1000 char);
  begin
    logger.append_param(l_params, 'p_url', p_url);
    logger.log('START', l_scope, null, l_params);

    l_host := regexp_substr(p_url, '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)', 1, 1, null, 1);

    logger.append_param(l_params, 'l_host', l_host);
    logger.log('END', l_scope, null, l_params);

    return l_host;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end extract_host;








  -- ===========================================================================
  -- PROCEDURE: reject_unsupported_params (private)
  -- ===========================================================================
  /**
   * Fails loudly when the endpoint has active path/form parameters, instead
   * of silently executing a request that ignores them. Phase 0 only
   * substitutes query parameters -- see docs/base/implementation_plan.md
   * section 4 (0.5, "ejecucion real minima").
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id  Endpoint to check
   */
  procedure reject_unsupported_params(
      p_endpoint_id                             in arw_endpoint_params.endpoint_id%type
  )
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'reject_unsupported_params';
    l_params        logger.tab_param;
    l_unsupported_n pls_integer;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    select count(*)
      into l_unsupported_n
      from arw_endpoint_params
     where endpoint_id = p_endpoint_id
       and active_yn = 'Y'
       and param_kind_code in ('path', 'form');

    if l_unsupported_n > 0 then
      raise_application_error(
          gc_err_param_kind_not_implemented
        , 'path/form parameters are not yet substituted by arw_exec_api (endpoint_id=' || p_endpoint_id
          || '); only query parameters are applied in Phase 0.'
      );
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end reject_unsupported_params;








  -- ===========================================================================
  -- FUNCTION: build_query_string (private)
  -- ===========================================================================
  /**
   * Builds the "?a=1&b=2" query string from the endpoint's active query
   * parameters, url-encoded via apex_util.url_encode.
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id  Endpoint whose query parameters are read
   * @return varchar2       Query string starting with "?"; null when there are none
   */
  function build_query_string(
      p_endpoint_id                             in arw_endpoint_params.endpoint_id%type
  )
  return varchar2
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'build_query_string';
    l_params       logger.tab_param;
    l_query_string varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    for l_rec in (
      select param_name
           , param_value
        from arw_endpoint_params
       where endpoint_id = p_endpoint_id
         and active_yn = 'Y'
         and param_kind_code = 'query'
       order by param_id
    )
    loop
      l_query_string := l_query_string
                         || case when l_query_string is null then '?' else '&' end
                         || apex_util.url_encode(l_rec.param_name) || '=' || apex_util.url_encode(l_rec.param_value);
    end loop;

    logger.append_param(l_params, 'l_query_string', l_query_string);
    logger.log('END', l_scope, null, l_params);

    return l_query_string;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end build_query_string;








  -- ===========================================================================
  -- PROCEDURE: get_body (private)
  -- ===========================================================================
  /**
   * Reads the endpoint's active request body template and content_type, if
   * one is configured. o_body/o_content_type are left null when the
   * endpoint has no body (e.g. a GET).
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id   Endpoint to read the body for
   * @param  o_body          Body template, {{var}} tokens not yet substituted
   * @param  o_content_type  Content-Type configured for the body
   */
  procedure get_body(
      p_endpoint_id                             in arw_request_bodies.endpoint_id%type
    , o_body                                    out clob
    , o_content_type                            out arw_request_bodies.content_type%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'get_body';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    begin
      select body_template
           , content_type
        into o_body
           , o_content_type
        from arw_request_bodies
       where endpoint_id = p_endpoint_id
         and active_yn = 'Y';
    exception
      when no_data_found then
        o_body         := null;
        o_content_type := null;
    end;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end get_body;








  -- ===========================================================================
  -- FUNCTION: apply_request_headers (private)
  -- ===========================================================================
  /**
   * Resets apex_web_service.g_request_headers (global, persists across calls
   * -- IMPLEMENTATION.md section 12) and repopulates it from the endpoint's
   * active static headers, a Content-Type header when the body needs one,
   * and the auth headers arw_auth_utils.get_auth_headers resolves for the
   * credential. Returns a redacted "name: value" summary for storage in
   * arw_executions.request_headers -- static headers are redacted per
   * is_sensitive_yn, auth-derived headers are always redacted
   * unconditionally (not optional, per IMPLEMENTATION.md section 12).
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id    Endpoint whose static headers are applied
   * @param  p_credential_id  Credential to resolve auth headers for; null means no auth
   * @param  p_content_type   Content-Type to add when the body needs one and no header already sets it
   * @return clob             Redacted "name: value" summary of every header actually sent
   */
  function apply_request_headers(
      p_endpoint_id                             in arw_endpoint_headers.endpoint_id%type
    , p_credential_id                           in arw_credentials.credential_id%type
    , p_content_type                            in arw_request_bodies.content_type%type
  )
  return clob
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'apply_request_headers';
    l_params       logger.tab_param;
    l_summary      clob;
    l_header_idx   pls_integer := 0;
    l_has_ct       boolean := false;
    l_auth_headers arw_auth_utils.t_header_tab;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    apex_web_service.g_request_headers.delete;

    for l_rec in (
      select header_name
           , header_value
           , is_sensitive_yn
        from arw_endpoint_headers
       where endpoint_id = p_endpoint_id
         and active_yn = 'Y'
       order by header_id
    )
    loop
      l_header_idx := l_header_idx + 1;
      apex_web_service.g_request_headers(l_header_idx).name  := l_rec.header_name;
      apex_web_service.g_request_headers(l_header_idx).value := l_rec.header_value;

      if lower(l_rec.header_name) = 'content-type' then
        l_has_ct := true;
      end if;

      l_summary := l_summary || l_rec.header_name || ': '
                   || case when l_rec.is_sensitive_yn = 'Y' then '***REDACTED***' else l_rec.header_value end
                   || chr(10);
    end loop;

    if p_content_type is not null and not l_has_ct then
      l_header_idx := l_header_idx + 1;
      apex_web_service.g_request_headers(l_header_idx).name  := 'Content-Type';
      apex_web_service.g_request_headers(l_header_idx).value := p_content_type;

      l_summary := l_summary || 'Content-Type: ' || p_content_type || chr(10);
    end if;


    -- ===========================================================================
    -- Resolve and append auth headers for this credential.
    -- ===========================================================================

    l_auth_headers := arw_auth_utils.get_auth_headers(
        p_credential_id                         => p_credential_id
    );
    -- ===========================================================================

    for i in 1 .. l_auth_headers.count loop
      l_header_idx := l_header_idx + 1;
      apex_web_service.g_request_headers(l_header_idx).name  := l_auth_headers(i).header_name;
      apex_web_service.g_request_headers(l_header_idx).value := l_auth_headers(i).header_value;

      l_summary := l_summary || l_auth_headers(i).header_name || ': ***REDACTED***' || chr(10);
    end loop;

    logger.log('END', l_scope, null, l_params);

    return l_summary;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end apply_request_headers;








  -- ===========================================================================
  -- FUNCTION: log_execution (private)
  -- ===========================================================================
  /**
   * Inserts the execution row in its own autonomous transaction and commits
   * immediately, so the call history survives even when the caller's own
   * transaction later rolls back -- IMPLEMENTATION.md section 12 ("Auditoria
   * perdida por rollback del llamador").
   *
   * @example N/A -- private package-body unit, not callable outside arw_exec_api;
   *           see execute_endpoint's runnable example, which exercises this indirectly.
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id           Endpoint that was executed
   * @param  p_environment_id        Environment it was executed against
   * @param  p_request_status_code   success, error or timeout
   * @param  p_http_status_code      HTTP status returned; null on error/timeout
   * @param  p_elapsed_ms            Elapsed time of the call, in milliseconds
   * @param  p_request_headers       Redacted "name: value" summary already built by apply_request_headers
   * @param  p_request_body          Body sent with the request
   * @param  p_response_headers      Headers returned by the service
   * @param  p_response_body_clob    Response body, or the error text when the call failed
   * @return arw_executions.execution_id%type  Identifier of the inserted row
   */
  function log_execution(
      p_endpoint_id                             in arw_executions.endpoint_id%type
    , p_environment_id                          in arw_executions.environment_id%type
    , p_request_status_code                     in arw_executions.request_status_code%type
    , p_http_status_code                        in arw_executions.http_status_code%type
    , p_elapsed_ms                              in arw_executions.elapsed_ms%type
    , p_request_headers                         in arw_executions.request_headers%type
    , p_request_body                            in arw_executions.request_body%type
    , p_response_headers                        in arw_executions.response_headers%type
    , p_response_body_clob                      in arw_executions.response_body_clob%type
  )
  return arw_executions.execution_id%type
  is
    pragma autonomous_transaction;
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'log_execution';
    l_params       logger.tab_param;
    l_execution_id arw_executions.execution_id%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_request_status_code', p_request_status_code);
    logger.log('START', l_scope, null, l_params);

    insert
      into arw_executions (
           endpoint_id
         , environment_id
         , request_status_code
         , http_status_code
         , elapsed_ms
         , request_headers
         , request_body
         , response_headers
         , response_body_clob
      )
    values (
           p_endpoint_id
         , p_environment_id
         , p_request_status_code
         , p_http_status_code
         , p_elapsed_ms
         , p_request_headers
         , p_request_body
         , p_response_headers
         , p_response_body_clob
      )
    returning execution_id into l_execution_id;

    commit;

    logger.append_param(l_params, 'l_execution_id', l_execution_id);
    logger.log('END', l_scope, null, l_params);

    return l_execution_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      rollback;
      raise;
  end log_execution;








  -- ===========================================================================
  -- FUNCTION: execute_endpoint
  -- ===========================================================================
  /**
   * Executes the real HTTP call for an endpoint against an environment and
   * writes the outcome to arw_executions. Always returns the execution_id,
   * even when the call itself failed (request_status_code = error/timeout)
   * -- callers check that column rather than catching an exception for a
   * plain failed call; execute_endpoint only raises for configuration
   * problems (endpoint/environment not found, environment from a different
   * collection, an unimplemented engine/param kind, or a failing
   * preflight).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_execution_id arw_executions.execution_id%type;
   * begin
   *   l_execution_id := arw_exec_api.execute_endpoint(
   *       p_endpoint_id                           => 1
   *     , p_environment_id                        => 1
   *   );
   *   dbms_output.put_line('execution_id=' || l_execution_id);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_endpoint_id     Endpoint to execute
   * @param  p_environment_id  Environment to resolve base_url/host against
   * @return arw_executions.execution_id%type  Identifier of the history row written
   */
  function execute_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_environment_id                          in arw_environments.environment_id%type
  )
  return arw_executions.execution_id%type
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'execute_endpoint';
    l_params logger.tab_param;

    l_endpoint_collection_id arw_endpoints.collection_id%type;
    l_credential_id          arw_endpoints.credential_id%type;
    l_http_method            arw_endpoints.http_method%type;
    l_url_path               arw_endpoints.url_path%type;
    l_timeout_secs           arw_endpoints.timeout_secs%type;
    l_engine_code            arw_endpoints.engine_code%type;

    l_environment_collection_id arw_environments.collection_id%type;
    l_base_url                  arw_environments.base_url%type;

    l_host             varchar2(1000 char);
    l_preflight_checks arw_preflight_api.t_check_tab;

    l_url             varchar2(2000 char);
    l_body            clob;
    l_content_type    arw_request_bodies.content_type%type;
    l_request_headers clob;

    l_response_body    clob;
    l_response_headers clob;

    l_start_cs pls_integer;
    l_end_cs   pls_integer;

    l_request_status_code arw_executions.request_status_code%type;
    l_http_status_code    arw_executions.http_status_code%type;
    l_execution_id        arw_executions.execution_id%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_environment_id', p_environment_id);
    logger.log('START', l_scope, null, l_params);

    begin
      select collection_id
           , credential_id
           , http_method
           , url_path
           , timeout_secs
           , engine_code
        into l_endpoint_collection_id
           , l_credential_id
           , l_http_method
           , l_url_path
           , l_timeout_secs
           , l_engine_code
        from arw_endpoints
       where endpoint_id = p_endpoint_id
         and active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_endpoint_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end;

    begin
      select collection_id
           , base_url
        into l_environment_collection_id
           , l_base_url
        from arw_environments
       where environment_id = p_environment_id
         and active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_environment_not_found, 'Environment not found: ' || p_environment_id);
    end;

    if l_environment_collection_id != l_endpoint_collection_id then
      raise_application_error(
          gc_err_environment_mismatch
        , 'Environment ' || p_environment_id || ' does not belong to endpoint ' || p_endpoint_id || '''s collection.'
      );
    end if;

    if l_engine_code != 'apex_web_service' then
      raise_application_error(gc_err_engine_not_implemented, 'Engine not yet implemented: ' || l_engine_code);
    end if;

    reject_unsupported_params(p_endpoint_id => p_endpoint_id);

    l_host := extract_host(p_url => l_base_url);


    -- ===========================================================================
    -- Gate the real call on the preflight checklist -- never call out when
    -- it reports a failing check (implementation_plan.md section 4, 0.7).
    -- ===========================================================================

    l_preflight_checks := arw_preflight_api.run_preflight(
        p_host                                  => l_host
      , p_credential_id                         => l_credential_id
    );
    -- ===========================================================================

    if arw_preflight_api.has_failures(p_checks => l_preflight_checks) = 'Y' then
      raise_application_error(
          gc_err_preflight_failed
        , 'Preflight failed for host ' || l_host || ':' || chr(10)
          || arw_preflight_api.format_failures(p_checks => l_preflight_checks)
      );
    end if;

    get_body(
        p_endpoint_id                           => p_endpoint_id
      , o_body                                  => l_body
      , o_content_type                          => l_content_type
    );

    l_url := l_base_url || l_url_path || build_query_string(p_endpoint_id => p_endpoint_id);

    l_request_headers := apply_request_headers(
        p_endpoint_id                           => p_endpoint_id
      , p_credential_id                         => l_credential_id
      , p_content_type                          => l_content_type
    );

    l_start_cs := dbms_utility.get_time;

    begin
      l_response_body := apex_web_service.make_rest_request(
          p_url                                 => l_url
        , p_http_method                         => l_http_method
        , p_body                                => l_body
        , p_transfer_timeout                    => l_timeout_secs
      );

      l_end_cs               := dbms_utility.get_time;
      l_http_status_code     := apex_web_service.g_status_code;
      l_request_status_code  := 'success';

      for i in 1 .. apex_web_service.g_headers.count loop
        l_response_headers := l_response_headers || apex_web_service.g_headers(i).name || ': '
                               || apex_web_service.g_headers(i).value || chr(10);
      end loop;
    exception
      when others then
        l_end_cs               := dbms_utility.get_time;
        l_http_status_code     := null;
        l_response_body        := sqlerrm;
        -- ORA-29273 is the generic HTTP-failure wrapper (DNS, refused,
        -- SSL, timeout, ...), not timeout-specific -- only the message
        -- text itself reliably says "timeout".
        l_request_status_code  := case
                                     when lower(sqlerrm) like '%timeout%' then 'timeout'
                                     else 'error'
                                   end;
    end;

    l_execution_id := log_execution(
        p_endpoint_id                           => p_endpoint_id
      , p_environment_id                        => p_environment_id
      , p_request_status_code                   => l_request_status_code
      , p_http_status_code                      => l_http_status_code
      , p_elapsed_ms                            => (l_end_cs - l_start_cs) * 10
      , p_request_headers                       => l_request_headers
      , p_request_body                          => l_body
      , p_response_headers                      => l_response_headers
      , p_response_body_clob                    => l_response_body
    );

    logger.append_param(l_params, 'l_execution_id', l_execution_id);
    logger.append_param(l_params, 'l_request_status_code', l_request_status_code);
    logger.log('END', l_scope, null, l_params);

    return l_execution_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end execute_endpoint;


end arw_exec_api;
/
