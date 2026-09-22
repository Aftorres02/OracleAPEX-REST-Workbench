-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_endpoint_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_not_found constant number := -20910;








  -- ===========================================================================
  -- FUNCTION: create_endpoint
  -- ===========================================================================
  /**
   * Creates an endpoint (method, path, timeout, runtime/engine) inside a collection.
   *
   * @example
   * l_endpoint_id := arw_endpoint_api.create_endpoint(
   *     p_collection_id                          => 1
   *   , p_name                                    => 'Get sample todo'
   *   , p_http_method                             => 'GET'
   *   , p_url_path                                => '/todos/1'
   * );
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_collection_id Collection this endpoint belongs to
   * @param p_name Display name of the endpoint
   * @param p_http_method HTTP verb of the request
   * @param p_url_path Path relative to the active environment base_url
   * @param p_credential_id Credential to authenticate with; null when not needed
   * @param p_timeout_secs Call timeout, in seconds
   * @param p_runtime_target_code Target runtime: apex, job or autonomous
   * @param p_engine_code Invocation engine: apex_web_service, apex_web_service_b, utl_http or dbms_cloud_send_request
   * @return arw_endpoints.endpoint_id%type  Identifier of the created endpoint
   */
  function create_endpoint(
      p_collection_id                           in arw_endpoints.collection_id%type
    , p_name                                    in arw_endpoints.name%type
    , p_http_method                             in arw_endpoints.http_method%type
    , p_url_path                                in arw_endpoints.url_path%type
    , p_credential_id                           in arw_endpoints.credential_id%type default null
    , p_timeout_secs                            in arw_endpoints.timeout_secs%type default 30
    , p_runtime_target_code                     in arw_endpoints.runtime_target_code%type default 'apex'
    , p_engine_code                             in arw_endpoints.engine_code%type default 'apex_web_service'
  )
  return arw_endpoints.endpoint_id%type
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'create_endpoint';
    l_params      logger.tab_param;
    l_endpoint_id arw_endpoints.endpoint_id%type;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_http_method', p_http_method);
    logger.append_param(l_params, 'p_url_path', p_url_path);
    logger.log('START', l_scope, null, l_params);

    insert
      into arw_endpoints (
           collection_id
         , name
         , http_method
         , url_path
         , credential_id
         , timeout_secs
         , runtime_target_code
         , engine_code
      )
    values (
           p_collection_id
         , p_name
         , p_http_method
         , p_url_path
         , p_credential_id
         , p_timeout_secs
         , p_runtime_target_code
         , p_engine_code
      )
    returning endpoint_id into l_endpoint_id;

    logger.append_param(l_params, 'l_endpoint_id', l_endpoint_id);
    logger.log('END', l_scope, null, l_params);

    return l_endpoint_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_endpoint;








  -- ===========================================================================
  -- PROCEDURE: update_endpoint
  -- ===========================================================================
  /**
   * Updates an existing endpoint definition.
   *
   * @example
   * begin
   *   arw_endpoint_api.update_endpoint(
   *       p_endpoint_id                           => 1
   *     , p_name                                   => 'Get sample todo'
   *     , p_http_method                             => 'GET'
   *     , p_url_path                                => '/todos/1'
   *     , p_credential_id                           => null
   *     , p_timeout_secs                            => 30
   *     , p_runtime_target_code                     => 'apex'
   *     , p_engine_code                              => 'apex_web_service'
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint to update
   * @param p_name Display name of the endpoint
   * @param p_http_method HTTP verb of the request
   * @param p_url_path Path relative to the active environment base_url
   * @param p_credential_id Credential to authenticate with; null when not needed
   * @param p_timeout_secs Call timeout, in seconds
   * @param p_runtime_target_code Target runtime: apex, job or autonomous
   * @param p_engine_code Invocation engine identifier
   */
  procedure update_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_name                                    in arw_endpoints.name%type
    , p_http_method                             in arw_endpoints.http_method%type
    , p_url_path                                in arw_endpoints.url_path%type
    , p_credential_id                           in arw_endpoints.credential_id%type
    , p_timeout_secs                            in arw_endpoints.timeout_secs%type
    , p_runtime_target_code                     in arw_endpoints.runtime_target_code%type
    , p_engine_code                             in arw_endpoints.engine_code%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'update_endpoint';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoints
       set name                 = p_name
         , http_method          = p_http_method
         , url_path             = p_url_path
         , credential_id        = p_credential_id
         , timeout_secs         = p_timeout_secs
         , runtime_target_code  = p_runtime_target_code
         , engine_code          = p_engine_code
     where endpoint_id = p_endpoint_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_endpoint;








  -- ===========================================================================
  -- PROCEDURE: deactivate_endpoint
  -- ===========================================================================
  /**
   * Soft-deletes an endpoint (active_yn = N). last_updated_by/on are left
   * to the compound trigger, per ddl-conventions.md section 5.
   *
   * @example
   * begin
   *   arw_endpoint_api.deactivate_endpoint(
   *       p_endpoint_id                           => 1
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint to deactivate
   */
  procedure deactivate_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'deactivate_endpoint';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoints
       set active_yn = 'N'
     where endpoint_id = p_endpoint_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end deactivate_endpoint;








  -- ===========================================================================
  -- FUNCTION: add_header
  -- ===========================================================================
  /**
   * Adds a request header to an endpoint.
   *
   * @example
   * l_header_id := arw_endpoint_api.add_header(
   *     p_endpoint_id                             => 1
   *   , p_header_name                              => 'Accept'
   *   , p_header_value                             => 'application/json'
   * );
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint this header belongs to
   * @param p_header_name HTTP header name
   * @param p_header_value Header value; supports {{var}} tokens
   * @param p_is_sensitive_yn Y to redact this header in the execution history
   * @return arw_endpoint_headers.header_id%type  Identifier of the created header
   */
  function add_header(
      p_endpoint_id                             in arw_endpoint_headers.endpoint_id%type
    , p_header_name                             in arw_endpoint_headers.header_name%type
    , p_header_value                            in arw_endpoint_headers.header_value%type
    , p_is_sensitive_yn                         in arw_endpoint_headers.is_sensitive_yn%type default 'N'
  )
  return arw_endpoint_headers.header_id%type
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'add_header';
    l_params    logger.tab_param;
    l_header_id arw_endpoint_headers.header_id%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_header_name', p_header_name);
    logger.log('START', l_scope, null, l_params);

    insert
      into arw_endpoint_headers (
           endpoint_id
         , header_name
         , header_value
         , is_sensitive_yn
      )
    values (
           p_endpoint_id
         , p_header_name
         , p_header_value
         , p_is_sensitive_yn
      )
    returning header_id into l_header_id;

    logger.append_param(l_params, 'l_header_id', l_header_id);
    logger.log('END', l_scope, null, l_params);

    return l_header_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end add_header;








  -- ===========================================================================
  -- PROCEDURE: update_header
  -- ===========================================================================
  /**
   * Updates an existing endpoint header.
   *
   * @example
   * begin
   *   arw_endpoint_api.update_header(
   *       p_header_id                             => 1
   *     , p_header_name                            => 'Accept'
   *     , p_header_value                           => 'application/json'
   *     , p_is_sensitive_yn                        => 'N'
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_header_id Header to update
   * @param p_header_name HTTP header name
   * @param p_header_value Header value; supports {{var}} tokens
   * @param p_is_sensitive_yn Y to redact this header in the execution history
   */
  procedure update_header(
      p_header_id                               in arw_endpoint_headers.header_id%type
    , p_header_name                             in arw_endpoint_headers.header_name%type
    , p_header_value                            in arw_endpoint_headers.header_value%type
    , p_is_sensitive_yn                         in arw_endpoint_headers.is_sensitive_yn%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'update_header';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_header_id', p_header_id);
    logger.append_param(l_params, 'p_header_name', p_header_name);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoint_headers
       set header_name      = p_header_name
         , header_value     = p_header_value
         , is_sensitive_yn  = p_is_sensitive_yn
     where header_id = p_header_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Header not found: ' || p_header_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_header;








  -- ===========================================================================
  -- PROCEDURE: remove_header
  -- ===========================================================================
  /**
   * Soft-deletes an endpoint header (active_yn = N).
   *
   * @example
   * begin
   *   arw_endpoint_api.remove_header(
   *       p_header_id                             => 1
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_header_id Header to remove
   */
  procedure remove_header(
      p_header_id                               in arw_endpoint_headers.header_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'remove_header';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_header_id', p_header_id);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoint_headers
       set active_yn = 'N'
     where header_id = p_header_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Header not found: ' || p_header_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end remove_header;








  -- ===========================================================================
  -- FUNCTION: add_param
  -- ===========================================================================
  /**
   * Adds a path/query/form parameter to an endpoint.
   *
   * @example
   * l_param_id := arw_endpoint_api.add_param(
   *     p_endpoint_id                             => 1
   *   , p_param_kind_code                          => 'path'
   *   , p_param_name                               => 'id'
   * );
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint this parameter belongs to
   * @param p_param_kind_code Parameter kind: path, query or form
   * @param p_param_name Parameter name
   * @param p_param_value Default/sample value; supports {{var}} tokens
   * @param p_data_type_code Parameter data type: varchar2, number, date or boolean
   * @param p_is_required_yn Y when the parameter is required to execute the endpoint
   * @return arw_endpoint_params.param_id%type  Identifier of the created parameter
   */
  function add_param(
      p_endpoint_id                             in arw_endpoint_params.endpoint_id%type
    , p_param_kind_code                         in arw_endpoint_params.param_kind_code%type
    , p_param_name                              in arw_endpoint_params.param_name%type
    , p_param_value                             in arw_endpoint_params.param_value%type default null
    , p_data_type_code                          in arw_endpoint_params.data_type_code%type default 'varchar2'
    , p_is_required_yn                          in arw_endpoint_params.is_required_yn%type default 'N'
  )
  return arw_endpoint_params.param_id%type
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'add_param';
    l_params   logger.tab_param;
    l_param_id arw_endpoint_params.param_id%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_param_kind_code', p_param_kind_code);
    logger.append_param(l_params, 'p_param_name', p_param_name);
    logger.log('START', l_scope, null, l_params);

    insert
      into arw_endpoint_params (
           endpoint_id
         , param_kind_code
         , param_name
         , param_value
         , data_type_code
         , is_required_yn
      )
    values (
           p_endpoint_id
         , p_param_kind_code
         , p_param_name
         , p_param_value
         , p_data_type_code
         , p_is_required_yn
      )
    returning param_id into l_param_id;

    logger.append_param(l_params, 'l_param_id', l_param_id);
    logger.log('END', l_scope, null, l_params);

    return l_param_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end add_param;








  -- ===========================================================================
  -- PROCEDURE: update_param
  -- ===========================================================================
  /**
   * Updates an existing endpoint parameter.
   *
   * @example
   * begin
   *   arw_endpoint_api.update_param(
   *       p_param_id                              => 1
   *     , p_param_kind_code                        => 'path'
   *     , p_param_name                              => 'id'
   *     , p_param_value                             => '1'
   *     , p_data_type_code                          => 'varchar2'
   *     , p_is_required_yn                          => 'Y'
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_param_id Parameter to update
   * @param p_param_kind_code Parameter kind: path, query or form
   * @param p_param_name Parameter name
   * @param p_param_value Default/sample value; supports {{var}} tokens
   * @param p_data_type_code Parameter data type: varchar2, number, date or boolean
   * @param p_is_required_yn Y when the parameter is required to execute the endpoint
   */
  procedure update_param(
      p_param_id                                in arw_endpoint_params.param_id%type
    , p_param_kind_code                         in arw_endpoint_params.param_kind_code%type
    , p_param_name                              in arw_endpoint_params.param_name%type
    , p_param_value                             in arw_endpoint_params.param_value%type
    , p_data_type_code                          in arw_endpoint_params.data_type_code%type
    , p_is_required_yn                          in arw_endpoint_params.is_required_yn%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'update_param';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_param_id', p_param_id);
    logger.append_param(l_params, 'p_param_name', p_param_name);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoint_params
       set param_kind_code  = p_param_kind_code
         , param_name       = p_param_name
         , param_value      = p_param_value
         , data_type_code   = p_data_type_code
         , is_required_yn   = p_is_required_yn
     where param_id = p_param_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Parameter not found: ' || p_param_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_param;








  -- ===========================================================================
  -- PROCEDURE: remove_param
  -- ===========================================================================
  /**
   * Soft-deletes an endpoint parameter (active_yn = N).
   *
   * @example
   * begin
   *   arw_endpoint_api.remove_param(
   *       p_param_id                              => 1
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_param_id Parameter to remove
   */
  procedure remove_param(
      p_param_id                                in arw_endpoint_params.param_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'remove_param';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_param_id', p_param_id);
    logger.log('START', l_scope, null, l_params);

    update arw_endpoint_params
       set active_yn = 'N'
     where param_id = p_param_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Parameter not found: ' || p_param_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end remove_param;








  -- ===========================================================================
  -- PROCEDURE: set_body
  -- ===========================================================================
  /**
   * Creates or replaces the request body for an endpoint (upsert, one body
   * per endpoint per uk_request_bodies_endpoint).
   *
   * @example
   * begin
   *   arw_endpoint_api.set_body(
   *       p_endpoint_id                           => 1
   *     , p_content_type                           => 'application/json'
   *     , p_body_template                          => '{"status":"{{status}}"}'
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint this body belongs to
   * @param p_content_type Content-Type of the body
   * @param p_body_template Template of the request body; supports {{var}} tokens
   */
  procedure set_body(
      p_endpoint_id                             in arw_request_bodies.endpoint_id%type
    , p_content_type                            in arw_request_bodies.content_type%type default 'application/json'
    , p_body_template                           in arw_request_bodies.body_template%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'set_body';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_content_type', p_content_type);
    logger.log('START', l_scope, null, l_params);

    merge into arw_request_bodies dest
    using (
      select p_endpoint_id as endpoint_id
        from dual
    ) src
    on (dest.endpoint_id = src.endpoint_id)
    when matched then
      update
         set dest.content_type  = p_content_type
           , dest.body_template = p_body_template
           , dest.active_yn     = 'Y'
    when not matched then
      insert (
             endpoint_id
           , content_type
           , body_template
      )
      values (
             src.endpoint_id
           , p_content_type
           , p_body_template
      );

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end set_body;








  -- ===========================================================================
  -- PROCEDURE: remove_body
  -- ===========================================================================
  /**
   * Soft-deletes the request body of an endpoint (active_yn = N).
   *
   * @example
   * begin
   *   arw_endpoint_api.remove_body(
   *       p_endpoint_id                           => 1
   *   );
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param p_endpoint_id Endpoint whose body should be removed
   */
  procedure remove_body(
      p_endpoint_id                             in arw_request_bodies.endpoint_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'remove_body';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    update arw_request_bodies
       set active_yn = 'N'
     where endpoint_id = p_endpoint_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Body not found for endpoint: ' || p_endpoint_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end remove_body;


end arw_endpoint_api;
/
