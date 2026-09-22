-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_endpoint_api
as
-- =============================================================================
-- Package: arw_endpoint_api
-- Purpose: CRUD for endpoints and their headers, params and request body.
--          No UI yet -- see docs/base/implementation_plan.md section 4 (0.3).
--
-- =============================================================================


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
  return arw_endpoints.endpoint_id%type;


  procedure update_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_name                                    in arw_endpoints.name%type
    , p_http_method                             in arw_endpoints.http_method%type
    , p_url_path                                in arw_endpoints.url_path%type
    , p_credential_id                           in arw_endpoints.credential_id%type
    , p_timeout_secs                            in arw_endpoints.timeout_secs%type
    , p_runtime_target_code                     in arw_endpoints.runtime_target_code%type
    , p_engine_code                             in arw_endpoints.engine_code%type
  );


  procedure deactivate_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  );


  function add_header(
      p_endpoint_id                             in arw_endpoint_headers.endpoint_id%type
    , p_header_name                             in arw_endpoint_headers.header_name%type
    , p_header_value                            in arw_endpoint_headers.header_value%type
    , p_is_sensitive_yn                         in arw_endpoint_headers.is_sensitive_yn%type default 'N'
  )
  return arw_endpoint_headers.header_id%type;


  procedure update_header(
      p_header_id                               in arw_endpoint_headers.header_id%type
    , p_header_name                             in arw_endpoint_headers.header_name%type
    , p_header_value                            in arw_endpoint_headers.header_value%type
    , p_is_sensitive_yn                         in arw_endpoint_headers.is_sensitive_yn%type
  );


  procedure remove_header(
      p_header_id                               in arw_endpoint_headers.header_id%type
  );


  function add_param(
      p_endpoint_id                             in arw_endpoint_params.endpoint_id%type
    , p_param_kind_code                         in arw_endpoint_params.param_kind_code%type
    , p_param_name                              in arw_endpoint_params.param_name%type
    , p_param_value                             in arw_endpoint_params.param_value%type default null
    , p_data_type_code                          in arw_endpoint_params.data_type_code%type default 'varchar2'
    , p_is_required_yn                          in arw_endpoint_params.is_required_yn%type default 'N'
  )
  return arw_endpoint_params.param_id%type;


  procedure update_param(
      p_param_id                                in arw_endpoint_params.param_id%type
    , p_param_kind_code                         in arw_endpoint_params.param_kind_code%type
    , p_param_name                              in arw_endpoint_params.param_name%type
    , p_param_value                             in arw_endpoint_params.param_value%type
    , p_data_type_code                          in arw_endpoint_params.data_type_code%type
    , p_is_required_yn                          in arw_endpoint_params.is_required_yn%type
  );


  procedure remove_param(
      p_param_id                                in arw_endpoint_params.param_id%type
  );


  procedure set_body(
      p_endpoint_id                             in arw_request_bodies.endpoint_id%type
    , p_content_type                            in arw_request_bodies.content_type%type default 'application/json'
    , p_body_template                           in arw_request_bodies.body_template%type
  );


  procedure remove_body(
      p_endpoint_id                             in arw_request_bodies.endpoint_id%type
  );


end arw_endpoint_api;
/
