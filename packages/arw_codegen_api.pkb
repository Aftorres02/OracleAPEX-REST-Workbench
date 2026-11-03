-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_codegen_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_not_found     constant number := -20945;
  gc_err_invalid_input constant number := -20946;

  gc_lf constant varchar2(1) := chr(10);

  gc_artifact_types constant varchar2(400 char) := ':plsql_package:plsql_block:json_table:table_ddl:curl'
                                                   || ':apexlang_rds:apexlang_install_script:apexlang_ai_tool:apexlang_automation:';
  gc_apexlang_types constant varchar2(200 char) := ':apexlang_rds:apexlang_install_script:apexlang_ai_tool:apexlang_automation:';

  -- Auth types a Web Credential + p_credential_static_id can carry
  gc_credential_auth_types constant varchar2(200 char) := ':basic:bearer:api_key_header:api_key_query'
                                                          || ':oauth2_client_credentials:oauth2_password:oci:';

  -- Note: the private list builders below run many times per artifact; their
  -- START/END logs are compiled in only with VERBOSE_OUTPUT:TRUE
  -- (plsql-standards.md section 13). Errors are always logged.

  type t_param_rec is record (
      kind_code                                 arw_endpoint_params.param_kind_code%type
    , param_name                                arw_endpoint_params.param_name%type
    , param_value                               arw_endpoint_params.param_value%type
    , data_type_code                            arw_endpoint_params.data_type_code%type
    , is_required_yn                            arw_endpoint_params.is_required_yn%type
    , ident                                     varchar2(128 char)
    , plsql_type                                varchar2(30 char)
  );
  type t_param_tab is table of t_param_rec index by pls_integer;

  type t_header_rec is record (
      header_name                               arw_endpoint_headers.header_name%type
    , header_value                              varchar2(4000 char)
    , is_sensitive_yn                           varchar2(1 char)
    , ident                                     varchar2(128 char)
  );
  type t_header_tab is table of t_header_rec index by pls_integer;

  type t_column_rec is record (
      column_id                                 arw_profile_columns.column_id%type
    , parent_column_id                          arw_profile_columns.parent_column_id%type
    , column_name                               arw_profile_columns.column_name%type
    , path_expression                           arw_profile_columns.path_expression%type
    , data_type_code                            arw_profile_columns.data_type_code%type
    , source_data_type                          arw_profile_columns.source_data_type%type
    , format_mask                               arw_profile_columns.format_mask%type
    , max_observed_length                       arw_profile_columns.max_observed_length%type
    , is_nullable_yn                            arw_profile_columns.is_nullable_yn%type
    , is_primary_key_yn                         arw_profile_columns.is_primary_key_yn%type
    , ident                                     varchar2(128 char)
    , has_children_yn                           varchar2(1 char)
    , is_json_yn                                varchar2(1 char)
  );
  type t_column_tab is table of t_column_rec index by pls_integer;

  type t_id_map is table of varchar2(255 char) index by pls_integer;

  type t_ctx is record (
      endpoint_id                               arw_endpoints.endpoint_id%type
    , endpoint_name                             arw_endpoints.name%type
    , collection_name                           arw_collections.name%type
    , http_method                               arw_endpoints.http_method%type
    , url_path                                  varchar2(4000 char)
    , timeout_secs                              arw_endpoints.timeout_secs%type
    , runtime_target_code                       arw_endpoints.runtime_target_code%type
    , engine_code                               arw_endpoints.engine_code%type
    , credential_id                             arw_credentials.credential_id%type
    , credential_name                           arw_credentials.name%type
    , auth_type_code                            arw_credentials.auth_type_code%type
    , credential_static_id                      arw_credentials.apex_credential_static_id%type
    , api_key_name                              arw_endpoints.auth_key_name%type
    , base_url                                  varchar2(1000 char)
    , content_type                              arw_request_bodies.content_type%type
    , body_template                             clob
    , data_profile_id                           arw_data_profiles.data_profile_id%type
    , profile_name                              arw_data_profiles.name%type
    , row_selector                              arw_data_profiles.row_selector%type
    , target_profile_id                         arw_target_profiles.target_profile_id%type
    , object_prefix                             arw_target_profiles.object_prefix%type
    , target_schema                             arw_target_profiles.target_schema%type
    , trace_mode_code                           arw_target_profiles.trace_mode_code%type
    , audit_enabled_yn                          arw_target_profiles.audit_enabled_yn%type
    , resource_name                             varchar2(128 char)
    , entity_name                               varchar2(128 char)
    , is_single_yn                              varchar2(1 char)
    , function_name                             varchar2(128 char)
    , json_function_name                        varchar2(128 char)
    , package_name                              varchar2(128 char)
    , rec_type                                  varchar2(128 char)
    , tab_type                                  varchar2(128 char)
    , table_name                                varchar2(128 char)
    , params                                    t_param_tab
    , headers                                   t_header_tab
    , profile_columns                                   t_column_tab
  );








  -- ===========================================================================
  -- FUNCTION: has_profile (private)
  -- ===========================================================================
  /**
   * True when the endpoint has a usable data profile (at least one column).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return boolean True when typed output can be generated
   */
  function has_profile(
      p_ctx                                     in t_ctx
  )
  return boolean
  is
  begin
    return p_ctx.data_profile_id is not null and p_ctx.profile_columns.count > 0;
  end has_profile;








  -- ===========================================================================
  -- FUNCTION: has_credential (private)
  -- ===========================================================================
  /**
   * True when the endpoint's credential can be passed to APEX as a Web
   * Credential static id (basic, bearer, API key, OAuth2, OCI).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return boolean True when p_credential_static_id applies
   */
  function has_credential(
      p_ctx                                     in t_ctx
  )
  return boolean
  is
  begin
    return p_ctx.credential_static_id is not null
       and instr(gc_credential_auth_types, ':' || p_ctx.auth_type_code || ':') > 0;
  end has_credential;








  -- ===========================================================================
  -- FUNCTION: apply_env_vars (private)
  -- ===========================================================================
  /**
   * Replaces {{name}} placeholders with the non-secret variables of the
   * environment. Secret variables are left as placeholders and reported
   * through o_uses_secret so the caller never inlines them.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Text with {{name}} placeholders
   * @param p_environment_id Environment whose variables apply; null = none
   * @param o_uses_secret True when the text references a secret variable
   * @return clob Text with the non-secret placeholders resolved
   */
  function apply_env_vars(
      p_text                                    in clob
    , p_environment_id                          in arw_environments.environment_id%type
    , o_uses_secret                             out boolean
  )
  return clob
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'apply_env_vars';
    l_params logger.tab_param;
    l_text   clob := p_text;
  begin
    o_uses_secret := false;

    if p_text is null or p_environment_id is null then
      return p_text;
    end if;

    for l_rec in (
      select v.var_name                                    as var_name
           , v.var_value                                   as var_value
           , v.is_secret_yn                                as is_secret_yn
        from arw_env_variables v
       where v.environment_id = p_environment_id
         and v.active_yn = 'Y'
    )
    loop
      if dbms_lob.instr(l_text, '{{' || l_rec.var_name || '}}') > 0 then
        if l_rec.is_secret_yn = 'Y' then
          o_uses_secret := true;
        else
          l_text := replace(l_text, '{{' || l_rec.var_name || '}}', l_rec.var_value);
        end if;
      end if;
    end loop;

    return l_text;
  exception
    when others then
      logger.append_param(l_params, 'p_environment_id', p_environment_id);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end apply_env_vars;








  -- ===========================================================================
  -- PROCEDURE: derive_names (private)
  -- ===========================================================================
  /**
   * Derives the generated object names from the URL path: the last path
   * segment that is not a parameter, a number or a version (v1, api) is the
   * resource (orders); its singular is the entity (order). GET /v1/orders
   * gives get_orders in <prefix>_orders_api with t_order_rec/t_order_tab;
   * a path ending in an id or a non-GET method uses the entity (get_order,
   * create_order).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param io_ctx Generation context; naming fields are filled in
   */
  procedure derive_names(
      io_ctx                                    in out nocopy t_ctx
  )
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'derive_names';
    l_params   logger.tab_param;
    l_path     varchar2(4000 char);
    l_segments apex_t_varchar2;
    l_segment  varchar2(4000 char);
    l_prefix   varchar2(30 char);
    l_verb     varchar2(30 char);
  begin
    io_ctx.is_single_yn := 'N';

    l_path     := trim(both '/' from regexp_replace(io_ctx.url_path, '\?.*$'));
    l_segments := apex_string.split(l_path, '/');

    for i in reverse 1 .. l_segments.count loop
      l_segment := l_segments(i);
      if l_segment is null then
        continue;
      end if;

      if regexp_like(l_segment, '^(\{.*\}|:.+|[0-9]+)$') then
        if i = l_segments.count then
          io_ctx.is_single_yn := 'Y';
        end if;
        continue;
      end if;

      if regexp_like(l_segment, '^v[0-9]+(\.[0-9]+)*$', 'i') or lower(l_segment) in ('api', 'rest', 'ords') then
        continue;
      end if;

      io_ctx.resource_name := arw_render_utils.to_identifier(l_segment, 60);
      exit;
    end loop;

    if io_ctx.resource_name is null then
      io_ctx.resource_name := arw_render_utils.to_identifier(io_ctx.endpoint_name, 60);
    end if;

    io_ctx.entity_name := arw_render_utils.singular(io_ctx.resource_name);

    l_verb := case io_ctx.http_method
                when 'GET'    then 'get'
                when 'POST'   then 'create'
                when 'PUT'    then 'update'
                when 'PATCH'  then 'update'
                when 'DELETE' then 'delete'
                else lower(io_ctx.http_method)
              end;

    io_ctx.function_name := l_verb || '_'
                            || case
                                 when io_ctx.is_single_yn = 'Y' or io_ctx.http_method != 'GET' then io_ctx.entity_name
                                 else io_ctx.resource_name
                               end;
    io_ctx.json_function_name := io_ctx.function_name || '_json';

    l_prefix := rtrim(lower(nvl(io_ctx.object_prefix, 'app')), '_');

    io_ctx.package_name := l_prefix || '_' || io_ctx.resource_name || '_api';
    io_ctx.rec_type     := 't_' || io_ctx.entity_name || '_rec';
    io_ctx.tab_type     := 't_' || io_ctx.entity_name || '_tab';
    io_ctx.table_name   := l_prefix || '_' || io_ctx.resource_name;
  exception
    when others then
      logger.append_param(l_params, 'url_path', io_ctx.url_path);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end derive_names;








  -- ===========================================================================
  -- FUNCTION: load_context (private)
  -- ===========================================================================
  /**
   * Reads everything generation needs: the endpoint and its collection,
   * credential, first active environment (base URL, non-secret variables),
   * params, headers, body, the current data profile
   * (arw_discover_api.current_profile_id) with its columns, and the target
   * profile (null = lowest active; none at all = built-in defaults: prefix
   * app, logger tracing, audit on, current schema).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint to generate for
   * @param p_target_profile_id Target profile; null = default profile
   * @return t_ctx Generation context
   */
  function load_context(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type
  )
  return t_ctx
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'load_context';
    l_params         logger.tab_param;
    l_ctx            t_ctx;
    l_collection_id  arw_endpoints.collection_id%type;
    l_simple_auth    arw_endpoints.auth_type_code%type;
    l_key_in         arw_endpoints.auth_key_location_code%type;
    l_environment_id arw_environments.environment_id%type;
    l_uses_secret    boolean;
    l_idx            pls_integer := 0;
    l_seen           apex_t_varchar2 := apex_t_varchar2();
    l_ident          varchar2(128 char);
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.log('START', l_scope, null, l_params);

    begin
      select e.endpoint_id                                 as endpoint_id
           , e.name                                        as endpoint_name
           , c.name                                        as collection_name
           , e.http_method                                 as http_method
           , e.url_path                                    as url_path
           , e.timeout_secs                                as timeout_secs
           , e.runtime_target_code                         as runtime_target_code
           , e.engine_code                                 as engine_code
           , e.credential_id                               as credential_id
           , e.collection_id                               as collection_id
           , e.auth_type_code                              as auth_type_code
           , e.auth_key_name                               as auth_key_name
           , e.auth_key_location_code                      as auth_key_location_code
        into l_ctx.endpoint_id
           , l_ctx.endpoint_name
           , l_ctx.collection_name
           , l_ctx.http_method
           , l_ctx.url_path
           , l_ctx.timeout_secs
           , l_ctx.runtime_target_code
           , l_ctx.engine_code
           , l_ctx.credential_id
           , l_collection_id
           , l_simple_auth
           , l_ctx.api_key_name
           , l_key_in
        from arw_endpoints   e
        join arw_collections c on c.collection_id = e.collection_id
       where e.endpoint_id = p_endpoint_id
         and e.active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end;

    if l_ctx.credential_id is not null then
      begin
        select cr.name                                     as credential_name
             , cr.auth_type_code                           as auth_type_code
             , cr.apex_credential_static_id                as apex_credential_static_id
          into l_ctx.credential_name
             , l_ctx.auth_type_code
             , l_ctx.credential_static_id
          from arw_credentials cr
         where cr.credential_id = l_ctx.credential_id;
      exception
        when no_data_found then
          l_ctx.credential_id := null;
      end;
    end if;

    -- ===========================================================================
    -- Simple auth (Auth tab): generated code never carries the secret, so it
    -- is rendered as a Web Credential the developer creates in APEX, named
    -- after the collection and the auth type (e.g. JSONPLACEHOLDER_BEARER).
    -- ===========================================================================
    if l_ctx.credential_id is null and l_simple_auth != 'none' then
      l_ctx.auth_type_code       := case
                                      when l_simple_auth = 'api_key' and l_key_in = 'query' then 'api_key_query'
                                      when l_simple_auth = 'api_key'                        then 'api_key_header'
                                      else l_simple_auth
                                    end;
      l_ctx.credential_static_id := upper(arw_render_utils.to_identifier(l_ctx.collection_name, 40))
                                    || '_' || upper(l_simple_auth);
      l_ctx.credential_name      := substr(l_ctx.collection_name, 1, 180) || ' (' || l_simple_auth || ')';
    else
      l_ctx.api_key_name := null;
    end if;

    -- ===========================================================================
    -- Base URL: the collection's first active environment.
    -- ===========================================================================
    begin
      select env.environment_id                            as environment_id
           , rtrim(env.base_url, '/')                      as base_url
        into l_environment_id
           , l_ctx.base_url
        from arw_environments env
       where env.collection_id = l_collection_id
         and env.active_yn = 'Y'
       order by env.environment_id
       fetch first 1 row only;
    exception
      when no_data_found then
        l_ctx.base_url := '{{base_url}}';
    end;

    l_ctx.url_path := apply_env_vars(l_ctx.url_path, l_environment_id, l_uses_secret);

    -- A full-URL endpoint ignores the environment: its own scheme://host
    -- becomes the base, the rest the path, so every template still renders
    -- base_url || url_path.
    if arw_endpoint_api.is_absolute_url_yn(p_url => l_ctx.url_path) = 'Y' then
      l_ctx.base_url := regexp_substr(l_ctx.url_path, '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*');
      l_ctx.url_path := coalesce(substr(l_ctx.url_path, length(l_ctx.base_url) + 1), '/');
    end if;

    for l_rec in (
      select p.param_kind_code                             as param_kind_code
           , p.param_name                                  as param_name
           , p.param_value                                 as param_value
           , p.data_type_code                              as data_type_code
           , p.is_required_yn                              as is_required_yn
        from arw_endpoint_params p
       where p.endpoint_id = p_endpoint_id
         and p.active_yn = 'Y'
       order by case p.param_kind_code when 'path' then 1 when 'query' then 2 else 3 end
              , p.param_id
    )
    loop
      l_idx   := l_idx + 1;
      l_ident := 'p_' || arw_render_utils.to_identifier(l_rec.param_name, 100);
      if l_ident member of l_seen or l_ident = 'p_body' then
        l_ident := l_ident || '_' || l_idx;
      end if;
      l_seen.extend;
      l_seen(l_seen.count) := l_ident;

      l_ctx.params(l_idx).kind_code      := l_rec.param_kind_code;
      l_ctx.params(l_idx).param_name     := l_rec.param_name;
      l_ctx.params(l_idx).param_value    := l_rec.param_value;
      l_ctx.params(l_idx).data_type_code := l_rec.data_type_code;
      l_ctx.params(l_idx).is_required_yn := case when l_rec.param_kind_code = 'path' then 'Y' else l_rec.is_required_yn end;
      l_ctx.params(l_idx).ident          := l_ident;
      l_ctx.params(l_idx).plsql_type     := case l_rec.data_type_code
                                              when 'number'  then 'number'
                                              when 'date'    then 'date'
                                              when 'boolean' then 'boolean'
                                              else 'varchar2'
                                            end;
    end loop;

    l_idx := 0;
    for l_rec in (
      select h.header_name                                 as header_name
           , h.header_value                                as header_value
           , h.is_sensitive_yn                             as is_sensitive_yn
        from arw_endpoint_headers h
       where h.endpoint_id = p_endpoint_id
         and h.active_yn = 'Y'
       order by h.header_id
    )
    loop
      l_idx := l_idx + 1;
      l_ctx.headers(l_idx).header_name  := l_rec.header_name;
      l_ctx.headers(l_idx).header_value := dbms_lob.substr(apply_env_vars(l_rec.header_value, l_environment_id, l_uses_secret), 4000, 1);
      l_ctx.headers(l_idx).is_sensitive_yn := case when l_rec.is_sensitive_yn = 'Y' or l_uses_secret then 'Y' else 'N' end;
      l_ctx.headers(l_idx).ident        := arw_render_utils.to_identifier(l_rec.header_name, 100);
    end loop;

    begin
      select b.content_type                                as content_type
           , b.body_template                               as body_template
        into l_ctx.content_type
           , l_ctx.body_template
        from arw_request_bodies b
       where b.endpoint_id = p_endpoint_id
         and b.active_yn = 'Y'
       order by b.body_id desc
       fetch first 1 row only;

      l_ctx.body_template := apply_env_vars(replace(l_ctx.body_template, chr(13) || gc_lf, gc_lf), l_environment_id, l_uses_secret);
      if dbms_lob.getlength(l_ctx.body_template) = 0 then
        l_ctx.body_template := null;
      end if;
    exception
      when no_data_found then
        null;
    end;


    -- ===========================================================================
    -- Current data profile (agent A contract) and its active columns.
    -- ===========================================================================

    l_ctx.data_profile_id := arw_discover_api.current_profile_id(
        p_endpoint_id                           => p_endpoint_id
    );
    -- ===========================================================================

    if l_ctx.data_profile_id is not null then
      select dp.name                                       as profile_name
           , dp.row_selector                               as row_selector
        into l_ctx.profile_name
           , l_ctx.row_selector
        from arw_data_profiles dp
       where dp.data_profile_id = l_ctx.data_profile_id;

      l_idx  := 0;
      l_seen := apex_t_varchar2();
      for l_rec in (
        select pc.column_id                                as column_id
             , pc.parent_column_id                         as parent_column_id
             , pc.column_name                              as column_name
             , pc.path_expression                          as path_expression
             , pc.data_type_code                           as data_type_code
             , pc.source_data_type                         as source_data_type
             , pc.format_mask                              as format_mask
             , pc.max_observed_length                      as max_observed_length
             , pc.is_nullable_yn                           as is_nullable_yn
             , pc.is_primary_key_yn                        as is_primary_key_yn
             , case
                 when exists (
                   select 1
                     from arw_profile_columns ch
                    where ch.parent_column_id = pc.column_id
                      and ch.active_yn = 'Y'
                 ) then 'Y'
                 else 'N'
               end                                         as has_children_yn
          from arw_profile_columns pc
         where pc.data_profile_id = l_ctx.data_profile_id
           and pc.active_yn = 'Y'
         order by pc.sequence_num nulls last
                , pc.column_id
      )
      loop
        l_idx   := l_idx + 1;
        l_ident := arw_render_utils.to_identifier(l_rec.column_name, 100);
        if l_ident member of l_seen then
          l_ident := l_ident || '_' || l_idx;
        end if;
        l_seen.extend;
        l_seen(l_seen.count) := l_ident;

        l_ctx.profile_columns(l_idx).column_id           := l_rec.column_id;
        l_ctx.profile_columns(l_idx).parent_column_id    := l_rec.parent_column_id;
        l_ctx.profile_columns(l_idx).column_name         := l_rec.column_name;
        l_ctx.profile_columns(l_idx).path_expression     := l_rec.path_expression;
        l_ctx.profile_columns(l_idx).data_type_code      := l_rec.data_type_code;
        l_ctx.profile_columns(l_idx).source_data_type    := l_rec.source_data_type;
        l_ctx.profile_columns(l_idx).format_mask         := l_rec.format_mask;
        l_ctx.profile_columns(l_idx).max_observed_length := l_rec.max_observed_length;
        l_ctx.profile_columns(l_idx).is_nullable_yn      := l_rec.is_nullable_yn;
        l_ctx.profile_columns(l_idx).is_primary_key_yn   := l_rec.is_primary_key_yn;
        l_ctx.profile_columns(l_idx).ident               := l_ident;
        l_ctx.profile_columns(l_idx).has_children_yn     := l_rec.has_children_yn;
        l_ctx.profile_columns(l_idx).is_json_yn          := case
                                                      when lower(l_rec.source_data_type) in ('array', 'object') then 'Y'
                                                      else 'N'
                                                    end;
      end loop;

      if l_ctx.profile_columns.count = 0 then
        l_ctx.data_profile_id := null;
      end if;
    end if;


    -- ===========================================================================
    -- Target profile: explicit, else the default (lowest active id), else
    -- built-in defaults (not stored: arw_generated_artifacts needs a
    -- target_profile_id).
    -- ===========================================================================
    begin
      select tp.target_profile_id                          as target_profile_id
           , tp.object_prefix                              as object_prefix
           , tp.target_schema                              as target_schema
           , tp.trace_mode_code                            as trace_mode_code
           , tp.audit_enabled_yn                           as audit_enabled_yn
        into l_ctx.target_profile_id
           , l_ctx.object_prefix
           , l_ctx.target_schema
           , l_ctx.trace_mode_code
           , l_ctx.audit_enabled_yn
        from arw_target_profiles tp
       where tp.active_yn = 'Y'
         and (   tp.target_profile_id = p_target_profile_id
              or (    p_target_profile_id is null
                  and tp.target_profile_id = (
                        select min(tp2.target_profile_id)  as target_profile_id
                          from arw_target_profiles tp2
                         where tp2.active_yn = 'Y'
                      )))
         ;
    exception
      when no_data_found then
        if p_target_profile_id is not null then
          raise_application_error(gc_err_not_found, 'Target profile not found: ' || p_target_profile_id);
        end if;

        l_ctx.object_prefix    := 'app';
        l_ctx.trace_mode_code  := 'logger';
        l_ctx.audit_enabled_yn := 'Y';
    end;

    derive_names(io_ctx => l_ctx);

    logger.append_param(l_params, 'package_name', l_ctx.package_name);
    logger.append_param(l_params, 'data_profile_id', l_ctx.data_profile_id);
    logger.log('END', l_scope, null, l_params);

    return l_ctx;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end load_context;








  -- ===========================================================================
  -- FUNCTION: join_lines (private)
  -- ===========================================================================
  /**
   * Joins collected lines with LF; null when there are none (a standalone
   * template token then drops its line).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_lines Lines to join
   * @return clob Joined text, or null
   */
  function join_lines(
      p_lines                                   in apex_t_varchar2
  )
  return clob
  is
  begin
    if p_lines is null or p_lines.count = 0 then
      return null;
    end if;

    return apex_string.join_clob(p_lines, gc_lf);
  end join_lines;








  -- ===========================================================================
  -- PROCEDURE: add (private)
  -- ===========================================================================
  /**
   * Appends one line to a line collection.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param io_lines Line collection
   * @param p_line Line to append
   */
  procedure add(
      io_lines                                  in out nocopy apex_t_varchar2
    , p_line                                    in varchar2
  )
  is
  begin
    io_lines.extend;
    io_lines(io_lines.count) := p_line;
  end add;








  -- ===========================================================================
  -- FUNCTION: sql_type (private)
  -- ===========================================================================
  /**
   * SQL/PL/SQL type of a profile column (PL/SQL type mapping is logic, not
   * text): varchar2(n char) from max_observed_length, number, date,
   * timestamp with time zone, clob; JSON booleans are varchar2(5 char)
   * ('true'/'false', a conservative floor that compiles on 19c too) and
   * nested arrays/objects are clob (json_table reads them FORMAT JSON).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_column Profile column
   * @return varchar2 Type declaration
   */
  function sql_type(
      p_column                                  in t_column_rec
  )
  return varchar2
  is
  begin
    if p_column.is_json_yn = 'Y' then
      return 'clob';
    end if;

    return case p_column.data_type_code
             when 'number'                   then 'number'
             when 'date'                     then 'date'
             when 'timestamp_with_time_zone' then 'timestamp with time zone'
             when 'boolean'                  then 'varchar2(5 char)'
             when 'clob'                     then 'clob'
             else case
                    when nvl(p_column.max_observed_length, 4000) > 4000 then 'clob'
                    else 'varchar2(' || greatest(nvl(p_column.max_observed_length, 4000), 1) || ' char)'
                  end
           end;
  end sql_type;








  -- ===========================================================================
  -- FUNCTION: param_to_text (private)
  -- ===========================================================================
  /**
   * PL/SQL expression converting a parameter to the text sent on the wire.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_param Endpoint parameter
   * @return varchar2 Expression yielding varchar2
   */
  function param_to_text(
      p_param                                   in t_param_rec
  )
  return varchar2
  is
  begin
    return case p_param.plsql_type
             when 'number'  then 'to_char(' || p_param.ident || ')'
             when 'date'    then 'to_char(' || p_param.ident || ', ''YYYY-MM-DD'')'
             when 'boolean' then 'case when ' || p_param.ident || ' then ''true'' else ''false'' end'
             else p_param.ident
           end;
  end param_to_text;








  -- ===========================================================================
  -- FUNCTION: sample_literal (private)
  -- ===========================================================================
  /**
   * PL/SQL literal of a parameter's sample value (the value saved in the
   * editor), used in @example blocks, the AI tool fallback and the
   * automation call.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_param Endpoint parameter
   * @return varchar2 Literal
   */
  function sample_literal(
      p_param                                   in t_param_rec
  )
  return varchar2
  is
  begin
    if p_param.param_value is null then
      return 'null';
    end if;

    return case p_param.plsql_type
             when 'number'  then case
                                   when regexp_like(p_param.param_value, '^-?[0-9]+(\.[0-9]+)?$') then p_param.param_value
                                   else 'null'
                                 end
             when 'boolean' then case when lower(p_param.param_value) in ('true', 'y', '1') then 'true' else 'false' end
             when 'date'    then 'to_date(' || arw_render_utils.quote_literal(p_param.param_value) || ', ''YYYY-MM-DD'')'
             else arw_render_utils.quote_literal(p_param.param_value)
           end;
  end sample_literal;








  -- ===========================================================================
  -- FUNCTION: signature_lines (private)
  -- ===========================================================================
  /**
   * "function <name>(" + one line per parameter (path, query, form, then
   * p_body when the endpoint has a body template) + ")" -- the parameter
   * list is rendered at indent 2, with "in" in column 49.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_function_name Function to declare
   * @return clob Signature lines (no "return" clause)
   */
  function signature_lines(
      p_ctx                                     in t_ctx
    , p_function_name                           in varchar2
  )
  return clob
  is
    l_scope logger_logs.scope%type := gc_scope_prefix || 'signature_lines';
    l_params logger.tab_param;
    l_lines apex_t_varchar2 := apex_t_varchar2();
    l_lead  varchar2(2);
  begin
    if p_ctx.params.count = 0 and p_ctx.body_template is null then
      return 'function ' || p_function_name;
    end if;

    add(l_lines, 'function ' || p_function_name || '(');

    for i in 1 .. p_ctx.params.count loop
      l_lead := case when l_lines.count = 1 then '  ' else ', ' end;
      add(l_lines, '  ' || arw_render_utils.aligned(
                               p_lead           => l_lead
                             , p_name           => p_ctx.params(i).ident
                             , p_rest           => 'in ' || p_ctx.params(i).plsql_type
                                                   || case when p_ctx.params(i).is_required_yn = 'N' then ' default null' end
                             , p_base_indent    => 4
                           ));
    end loop;

    if p_ctx.body_template is not null then
      l_lead := case when l_lines.count = 1 then '  ' else ', ' end;
      add(l_lines, '  ' || arw_render_utils.aligned(l_lead, 'p_body', 'in clob default null', 4));
    end if;

    add(l_lines, ')');

    return join_lines(l_lines);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end signature_lines;








  -- ===========================================================================
  -- FUNCTION: call_lines (private)
  -- ===========================================================================
  /**
   * A call statement with named notation: "<head>(" + "p_x => <value>"
   * lines + ");". p_mode picks the actual values: 'pass' passes the
   * caller's own parameters through, 'sample' uses the saved sample
   * values, 'bind' uses AI-tool binds (:NAME).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_head Text before "(", e.g. "l_rows := pkg.get_orders"
   * @param p_mode pass | sample | bind
   * @param p_indent Column offset the lines are rendered at (for "=>" alignment)
   * @return clob Statement lines
   */
  function call_lines(
      p_ctx                                     in t_ctx
    , p_head                                    in varchar2
    , p_mode                                    in varchar2
    , p_indent                                  in pls_integer
  )
  return clob
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'call_lines';
    l_params logger.tab_param;
    l_lines  apex_t_varchar2 := apex_t_varchar2();
    l_names  apex_t_varchar2 := apex_t_varchar2();
    l_values apex_t_varchar2 := apex_t_varchar2();
    l_bind   varchar2(200 char);
  begin
    for i in 1 .. p_ctx.params.count loop
      add(l_names, p_ctx.params(i).ident);
      l_bind := ':' || upper(substr(p_ctx.params(i).ident, 3));
      add(l_values, case p_mode
                      when 'pass'   then p_ctx.params(i).ident
                      when 'sample' then sample_literal(p_ctx.params(i))
                      else case p_ctx.params(i).plsql_type
                             when 'date'    then 'to_date(' || l_bind || ', ''YYYY-MM-DD'')'
                             when 'boolean' then 'upper(' || l_bind || ') in (''Y'', ''TRUE'', ''1'')'
                             else l_bind
                           end
                    end);
    end loop;

    if p_ctx.body_template is not null and p_mode in ('pass', 'bind') then
      add(l_names, 'p_body');
      add(l_values, case p_mode when 'pass' then 'p_body' else ':BODY' end);
    end if;

    if l_names.count = 0 then
      return p_head || ';';
    end if;

    add(l_lines, p_head || '(');
    for i in 1 .. l_names.count loop
      add(l_lines, '  ' || arw_render_utils.aligned(
                               p_lead           => case when i = 1 then '  ' else ', ' end
                             , p_name           => l_names(i)
                             , p_rest           => '=> ' || l_values(i)
                             , p_base_indent    => p_indent + 2
                           ));
    end loop;
    add(l_lines, ');');

    return join_lines(l_lines);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end call_lines;








  -- ===========================================================================
  -- FUNCTION: url_build_lines (private)
  -- ===========================================================================
  /**
   * PL/SQL statements building l_url: gc_base_url + path (path parameters
   * url-encoded in place of {name} / {{name}} / :name) + the query string
   * from the query parameters (optional ones only when not null).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return clob Statement lines
   */
  function url_build_lines(
      p_ctx                                     in t_ctx
  )
  return clob
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'url_build_lines';
    l_params    logger.tab_param;
    l_lines     apex_t_varchar2 := apex_t_varchar2();
    l_expr      varchar2(32767);
    l_has_query boolean := false;
    l_placeholders apex_t_varchar2;
  begin
    l_expr := 'gc_base_url || ' || arw_render_utils.quote_literal(p_ctx.url_path);

    for i in 1 .. p_ctx.params.count loop
      if p_ctx.params(i).kind_code = 'path' then
        l_placeholders := apex_t_varchar2(
                              '{{' || p_ctx.params(i).param_name || '}}'
                            , '{' || p_ctx.params(i).param_name || '}'
                            , ':' || p_ctx.params(i).param_name
                          );
        for j in 1 .. l_placeholders.count loop
          l_expr := replace(l_expr, l_placeholders(j)
                          , ''' || apex_util.url_encode(' || param_to_text(p_ctx.params(i)) || ') || ''');
        end loop;
      end if;
    end loop;

    l_expr := replace(l_expr, ' || ''''', '');
    add(l_lines, 'l_url := ' || l_expr || ';');

    for i in 1 .. p_ctx.params.count loop
      if p_ctx.params(i).kind_code = 'query' then
        l_has_query := true;
        if p_ctx.params(i).is_required_yn = 'N' then
          add(l_lines, 'if ' || p_ctx.params(i).ident || ' is not null then');
          add(l_lines, '  l_query := l_query || ' || arw_render_utils.quote_literal('&' || apex_util.url_encode(p_ctx.params(i).param_name) || '=')
                       || ' || apex_util.url_encode(' || param_to_text(p_ctx.params(i)) || ');');
          add(l_lines, 'end if;');
        else
          add(l_lines, 'l_query := l_query || ' || arw_render_utils.quote_literal('&' || apex_util.url_encode(p_ctx.params(i).param_name) || '=')
                       || ' || apex_util.url_encode(' || param_to_text(p_ctx.params(i)) || ');');
        end if;
      end if;
    end loop;

    if l_has_query then
      add(l_lines, 'if l_query is not null then');
      add(l_lines, '  l_url := l_url || case when instr(l_url, ''?'') > 0 then ''&'' else ''?'' end || substr(l_query, 2);');
      add(l_lines, 'end if;');
    end if;

    return join_lines(l_lines);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end url_build_lines;








  -- ===========================================================================
  -- FUNCTION: sample_url (private)
  -- ===========================================================================
  /**
   * The literal URL with the saved sample values: path parameters
   * substituted (or left as {name} when they have no value) and the query
   * string appended -- used by the anonymous block and cURL.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return varchar2 Full URL
   */
  function sample_url(
      p_ctx                                     in t_ctx
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'sample_url';
    l_params logger.tab_param;
    l_url    varchar2(32767) := p_ctx.base_url || p_ctx.url_path;
    l_query  varchar2(32767);
  begin
    for i in 1 .. p_ctx.params.count loop
      if p_ctx.params(i).kind_code = 'path' and p_ctx.params(i).param_value is not null then
        l_url := replace(l_url, '{{' || p_ctx.params(i).param_name || '}}', apex_util.url_encode(p_ctx.params(i).param_value));
        l_url := replace(l_url, '{' || p_ctx.params(i).param_name || '}', apex_util.url_encode(p_ctx.params(i).param_value));
        l_url := replace(l_url, ':' || p_ctx.params(i).param_name, apex_util.url_encode(p_ctx.params(i).param_value));
      elsif p_ctx.params(i).kind_code = 'query' and p_ctx.params(i).param_value is not null then
        l_query := l_query || '&' || apex_util.url_encode(p_ctx.params(i).param_name) || '=' || apex_util.url_encode(p_ctx.params(i).param_value);
      end if;
    end loop;

    if l_query is not null then
      l_url := l_url || case when instr(l_url, '?') > 0 then '&' else '?' end || substr(l_query, 2);
    end if;

    return l_url;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end sample_url;








  -- ===========================================================================
  -- FUNCTION: form_body_expr (private)
  -- ===========================================================================
  /**
   * PL/SQL expression of an application/x-www-form-urlencoded body built
   * from the form parameters; null when the endpoint has none.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_sample True for the sample-value literal, false for the parameter expression
   * @return varchar2 Expression, or null
   */
  function form_body_expr(
      p_ctx                                     in t_ctx
    , p_sample                                  in boolean
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'form_body_expr';
    l_params logger.tab_param;
    l_expr   varchar2(32767);
    l_text   varchar2(32767);
  begin
    for i in 1 .. p_ctx.params.count loop
      if p_ctx.params(i).kind_code = 'form' then
        if p_sample then
          l_text := l_text || '&' || apex_util.url_encode(p_ctx.params(i).param_name) || '=' || apex_util.url_encode(p_ctx.params(i).param_value);
        else
          l_expr := l_expr || case when l_expr is not null then ' || ' end
                    || arw_render_utils.quote_literal(case when l_expr is not null then '&' end || apex_util.url_encode(p_ctx.params(i).param_name) || '=')
                    || ' || apex_util.url_encode(' || param_to_text(p_ctx.params(i)) || ')';
        end if;
      end if;
    end loop;

    return case when p_sample then case when l_text is not null then arw_render_utils.quote_literal(substr(l_text, 2)) end else l_expr end;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end form_body_expr;








  -- ===========================================================================
  -- FUNCTION: effective_content_type (private)
  -- ===========================================================================
  /**
   * Content-Type the generated code adds when the endpoint sends a body and
   * no explicit Content-Type header exists; null otherwise.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return varchar2 Content type, or null
   */
  function effective_content_type(
      p_ctx                                     in t_ctx
  )
  return varchar2
  is
  begin
    for i in 1 .. p_ctx.headers.count loop
      if lower(p_ctx.headers(i).header_name) = 'content-type' then
        return null;
      end if;
    end loop;

    if form_body_expr(p_ctx, false) is not null then
      return 'application/x-www-form-urlencoded';
    end if;

    if p_ctx.body_template is not null then
      return nvl(p_ctx.content_type, 'application/json');
    end if;

    return null;
  end effective_content_type;








  -- ===========================================================================
  -- FUNCTION: header_lines (private)
  -- ===========================================================================
  /**
   * Header-setting statements for one engine style: 'apex' assigns
   * apex_web_service.g_request_headers(n), 'utl_http' calls
   * utl_http.set_header. Sensitive values reference a variable
   * (p_var_prefix || header) instead of the value.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_style apex | utl_http
   * @param p_var_prefix Variable prefix for sensitive values (g_header_ / l_header_)
   * @return clob Statement lines, or null
   */
  function header_lines(
      p_ctx                                     in t_ctx
    , p_style                                   in varchar2
    , p_var_prefix                              in varchar2
  )
  return clob
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'header_lines';
    l_params       logger.tab_param;
    l_lines        apex_t_varchar2 := apex_t_varchar2();
    l_names        apex_t_varchar2 := apex_t_varchar2();
    l_values       apex_t_varchar2 := apex_t_varchar2();
    l_content_type varchar2(500 char) := effective_content_type(p_ctx);
  begin
    for i in 1 .. p_ctx.headers.count loop
      add(l_names, arw_render_utils.quote_literal(p_ctx.headers(i).header_name));
      add(l_values, case
                      when p_ctx.headers(i).is_sensitive_yn = 'Y' then p_var_prefix || p_ctx.headers(i).ident
                      else arw_render_utils.quote_literal(p_ctx.headers(i).header_value)
                    end);
    end loop;

    if l_content_type is not null then
      add(l_names, '''Content-Type''');
      add(l_values, arw_render_utils.quote_literal(l_content_type));
    end if;

    for i in 1 .. l_names.count loop
      if p_style = 'apex' then
        add(l_lines, 'apex_web_service.g_request_headers(' || i || ').name  := ' || l_names(i) || ';');
        add(l_lines, 'apex_web_service.g_request_headers(' || i || ').value := ' || l_values(i) || ';');
      else
        add(l_lines, 'utl_http.set_header(r => l_request, name => ' || l_names(i) || ', value => ' || l_values(i) || ');');
      end if;
    end loop;

    return join_lines(l_lines);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end header_lines;








  -- ===========================================================================
  -- FUNCTION: dbms_cloud_headers (private)
  -- ===========================================================================
  /**
   * json_object(...) expression with the request headers for
   * dbms_cloud.send_request; 'null' when there are none.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_var_prefix Variable prefix for sensitive values
   * @return varchar2 Expression
   */
  function dbms_cloud_headers(
      p_ctx                                     in t_ctx
    , p_var_prefix                              in varchar2
  )
  return varchar2
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'dbms_cloud_headers';
    l_params       logger.tab_param;
    l_expr         varchar2(32767);
    l_content_type varchar2(500 char) := effective_content_type(p_ctx);
  begin
    for i in 1 .. p_ctx.headers.count loop
      l_expr := l_expr || case when l_expr is not null then ', ' end
                || arw_render_utils.quote_literal(p_ctx.headers(i).header_name) || ' value '
                || case
                     when p_ctx.headers(i).is_sensitive_yn = 'Y' then p_var_prefix || p_ctx.headers(i).ident
                     else arw_render_utils.quote_literal(p_ctx.headers(i).header_value)
                   end;
    end loop;

    if l_content_type is not null then
      l_expr := l_expr || case when l_expr is not null then ', ' end
                || '''Content-Type'' value ' || arw_render_utils.quote_literal(l_content_type);
    end if;

    return case when l_expr is null then 'null' else 'json_object(' || l_expr || ')' end;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end dbms_cloud_headers;








  -- ===========================================================================
  -- FUNCTION: sensitive_header_lines (private)
  -- ===========================================================================
  /**
   * Declarations of the variables that hold sensitive header values
   * (never inlined), each with a TODO to load it from a secure source.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_var_prefix g_header_ (package) or l_header_ (block)
   * @param p_todo_tag TODO tag for the comment
   * @return clob Declaration lines, or null
   */
  function sensitive_header_lines(
      p_ctx                                     in t_ctx
    , p_var_prefix                              in varchar2
    , p_todo_tag                                in varchar2
  )
  return clob
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'sensitive_header_lines';
    l_params logger.tab_param;
    l_lines  apex_t_varchar2 := apex_t_varchar2();
  begin
    for i in 1 .. p_ctx.headers.count loop
      if p_ctx.headers(i).is_sensitive_yn = 'Y' then
        add(l_lines, rpad(p_var_prefix || p_ctx.headers(i).ident, 30) || ' varchar2(4000 char); -- '
                     || p_todo_tag || ' value of header ' || p_ctx.headers(i).header_name);
      end if;
    end loop;

    return join_lines(l_lines);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end sensitive_header_lines;








  -- ===========================================================================
  -- FUNCTION: column_lines (private)
  -- ===========================================================================
  /**
   * Profile-column driven lists. p_kind:
   *   record   record fields (spec, rendered at indent 4)
   *   select   "select jt.x as x" list (rendered at indent 4)
   *   jt       json_table columns clause (top level only, arrays as clob
   *            FORMAT JSON)
   *   jt_nested json_table columns clause with NESTED PATH for arrays of
   *            objects (json_table artifact)
   *   select_nested select list matching jt_nested
   *   print    dbms_output concatenation for the anonymous block
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_kind List kind (see above)
   * @param p_parent_id Parent column for nested levels; null = top level
   * @return clob Lines, or null
   */
  function column_lines(
      p_ctx                                     in t_ctx
    , p_kind                                    in varchar2
    , p_parent_id                               in arw_profile_columns.column_id%type default null
  )
  return clob
  is
    l_scope   logger_logs.scope%type := gc_scope_prefix || 'column_lines';
    l_params  logger.tab_param;
    l_lines   apex_t_varchar2 := apex_t_varchar2();
    l_col     t_column_rec;
    l_lead    varchar2(2);
    l_nested  clob;
    l_parts   apex_t_varchar2;
    l_expr    varchar2(1000 char);
  begin
    for i in 1 .. p_ctx.profile_columns.count loop
      l_col := p_ctx.profile_columns(i);

      if (p_parent_id is null and l_col.parent_column_id is null)
         or l_col.parent_column_id = p_parent_id then

        l_lead := case when l_lines.count = 0 then '  ' else ', ' end;

        if p_kind in ('jt_nested', 'select_nested') and l_col.has_children_yn = 'Y' then
          l_nested := column_lines(p_ctx, p_kind, l_col.column_id);
          if p_kind = 'jt_nested' then
            add(l_lines, l_lead || 'nested path ' || arw_render_utils.quote_literal(arw_render_utils.json_path(l_col.path_expression) || '[*]'));
            add(l_lines, '  columns (');
            l_parts := apex_string.split(l_nested, gc_lf);
            for j in 1 .. l_parts.count loop
              add(l_lines, '    ' || l_parts(j));
            end loop;
            add(l_lines, '  )');
          else
            l_parts := apex_string.split(l_nested, gc_lf);
            for j in 1 .. l_parts.count loop
              add(l_lines, case when l_lines.count = 0 then regexp_replace(l_parts(j), '^     , ', 'select ') else regexp_replace(l_parts(j), '^select ', '     , ') end);
            end loop;
          end if;
          continue;
        end if;

        if p_kind in ('jt', 'select', 'record', 'print') and p_parent_id is null and l_col.has_children_yn = 'Y' then
          -- Typed outputs keep a nested array as one JSON clob column
          l_col.is_json_yn := 'Y';
        elsif p_kind in ('jt', 'select', 'record', 'print') and l_col.parent_column_id is not null then
          continue;
        end if;

        case p_kind
          when 'record' then
            add(l_lines, arw_render_utils.aligned(l_lead, l_col.ident, sql_type(l_col), 4));
          when 'select' then
            add(l_lines, case when l_lines.count = 0 then 'select ' else '     , ' end
                         || rpad('jt.' || l_col.ident, 40) || ' as ' || l_col.ident);
          when 'select_nested' then
            add(l_lines, case when l_lines.count = 0 then 'select ' else '     , ' end
                         || rpad('jt.' || l_col.ident, 52) || ' as ' || l_col.ident);
          when 'print' then
            l_expr := case
                        when sql_type(l_col) = 'clob'                     then 'dbms_lob.substr(l_rec.' || l_col.ident || ', 200, 1)'
                        when sql_type(l_col) = 'timestamp with time zone' then 'to_char(l_rec.' || l_col.ident || ', ''YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'')'
                        when sql_type(l_col) = 'date'                     then 'to_char(l_rec.' || l_col.ident || ', ''YYYY-MM-DD'')'
                        when sql_type(l_col) = 'number'                   then 'to_char(l_rec.' || l_col.ident || ')'
                        else 'l_rec.' || l_col.ident
                      end;
            add(l_lines, case when l_lines.count = 0 then '  ' else '|| ' end
                         || arw_render_utils.quote_literal(case when l_lines.count > 0 then ', ' end || l_col.ident || '=')
                         || ' || ' || l_expr);
          else
            add(l_lines, l_lead || rpad(l_col.ident, 30) || ' '
                         || rpad(sql_type(l_col) || case when l_col.is_json_yn = 'Y' then ' format json' end, 30)
                         || ' path ' || arw_render_utils.quote_literal(arw_render_utils.json_path(l_col.path_expression)));
        end case;
      end if;
    end loop;

    return join_lines(l_lines);
  exception
    when others then
      logger.append_param(l_params, 'p_kind', p_kind);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end column_lines;








  -- ===========================================================================
  -- FUNCTION: common_tokens (private)
  -- ===========================================================================
  /**
   * Tokens and flags shared by every artifact (names, axes, flags, lists
   * derived from params/headers/profile). Artifact-specific tokens are
   * added by add_artifact_tokens.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @return arw_render_utils.t_tokens Token values
   */
  function common_tokens(
      p_ctx                                     in t_ctx
  )
  return arw_render_utils.t_tokens
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'common_tokens';
    l_params        logger.tab_param;
    l_t             arw_render_utils.t_tokens;
    l_schema_prefix varchar2(130 char);
    l_lines         apex_t_varchar2 := apex_t_varchar2();
    l_has_query     boolean := false;
    l_has_sensitive boolean := false;
    l_form_expr     varchar2(32767);
    l_todo_tag      varchar2(60 char);
  begin
    logger.append_param(l_params, 'endpoint_id', p_ctx.endpoint_id);
    logger.log('START', l_scope, null, l_params);

    l_schema_prefix := case when p_ctx.target_schema is not null then lower(p_ctx.target_schema) || '.' end;
    l_todo_tag      := 'TODO_ARW_' || to_char(sysdate, 'fmMONTH-DD-YYYY', 'nls_date_language=english');

    arw_render_utils.set_token(l_t, 'generated_on', to_char(sysdate, 'fmMonth DD, YYYY', 'nls_date_language=english'));
    arw_render_utils.set_token(l_t, 'todo_tag', l_todo_tag);
    arw_render_utils.set_token(l_t, 'endpoint_name', p_ctx.endpoint_name);
    arw_render_utils.set_token(l_t, 'endpoint_name_apx', arw_render_utils.apx_text(p_ctx.endpoint_name));
    arw_render_utils.set_token(l_t, 'collection_name', p_ctx.collection_name);
    arw_render_utils.set_token(l_t, 'http_method', p_ctx.http_method);
    arw_render_utils.set_token(l_t, 'http_method_lower', case when p_ctx.http_method in ('HEAD', 'OPTIONS') then 'get' else lower(p_ctx.http_method) end);
    arw_render_utils.set_token(l_t, 'url_path', p_ctx.url_path);
    arw_render_utils.set_token(l_t, 'url_path_sq', replace(p_ctx.url_path, '''', ''''''));
    arw_render_utils.set_token(l_t, 'base_url', p_ctx.base_url);
    arw_render_utils.set_token(l_t, 'base_url_literal', arw_render_utils.quote_literal(p_ctx.base_url));
    arw_render_utils.set_token(l_t, 'timeout_secs', to_char(nvl(p_ctx.timeout_secs, 30)));
    arw_render_utils.set_token(l_t, 'runtime_target', p_ctx.runtime_target_code);
    arw_render_utils.set_token(l_t, 'engine_code', p_ctx.engine_code);
    arw_render_utils.set_token(l_t, 'trace_mode', p_ctx.trace_mode_code);
    arw_render_utils.set_token(l_t, 'audit_label', case when p_ctx.audit_enabled_yn = 'Y' then 'yes' else 'no' end);
    arw_render_utils.set_token(l_t, 'auth_type', nvl(p_ctx.auth_type_code, 'none'));
    arw_render_utils.set_token(l_t, 'schema_prefix', l_schema_prefix);
    arw_render_utils.set_token(l_t, 'package_name', p_ctx.package_name);
    arw_render_utils.set_token(l_t, 'package_ref', l_schema_prefix || p_ctx.package_name);
    arw_render_utils.set_token(l_t, 'function_name', p_ctx.function_name);
    arw_render_utils.set_token(l_t, 'json_function_name', p_ctx.json_function_name);
    arw_render_utils.set_token(l_t, 'rec_type', p_ctx.rec_type);
    arw_render_utils.set_token(l_t, 'tab_type', p_ctx.tab_type);
    arw_render_utils.set_token(l_t, 'resource_label', p_ctx.resource_name);
    arw_render_utils.set_token(l_t, 'table_name', p_ctx.table_name);
    arw_render_utils.set_token(l_t, 'table_ref', l_schema_prefix || p_ctx.table_name);
    arw_render_utils.set_token(l_t, 'profile_name', nvl(p_ctx.profile_name, upper(arw_render_utils.to_identifier(p_ctx.endpoint_name))));
    arw_render_utils.set_token(l_t, 'row_selector', p_ctx.row_selector);
    arw_render_utils.set_token(l_t, 'row_path', case
                                                  when p_ctx.row_selector is null then '$[*]'
                                                  else arw_render_utils.json_path(p_ctx.row_selector) || '[*]'
                                                end);
    arw_render_utils.set_token(l_t, 'credential_static_id', p_ctx.credential_static_id);
    arw_render_utils.set_token(l_t, 'credential_static_id_literal', arw_render_utils.quote_literal(p_ctx.credential_static_id));
    arw_render_utils.set_token(l_t, 'dbms_cloud_credential', case
                                                               when has_credential(p_ctx) then arw_render_utils.quote_literal(upper(p_ctx.credential_static_id))
                                                               else 'null'
                                                             end);
    arw_render_utils.set_token(l_t, 'audit_sink_doc', case
                                                        when p_ctx.trace_mode_code = 'logger' then
                                                          'Sink: logger.log_info, which writes in its own autonomous' || gc_lf
                                                          || 'transaction -- the line survives a caller rollback.'
                                                        else
                                                          'Sink: apex_debug.message(p_force => true), recorded even with' || gc_lf
                                                          || 'debug off (inside an APEX session).'
                                                      end);

    arw_render_utils.set_flag(l_t, 'has_profile', has_profile(p_ctx));
    arw_render_utils.set_flag(l_t, 'has_credential', has_credential(p_ctx));
    arw_render_utils.set_flag(l_t, 'needs_token_url', has_credential(p_ctx) and p_ctx.auth_type_code like 'oauth2%');
    arw_render_utils.set_flag(l_t, 'auth_unsupported', p_ctx.credential_static_id is not null and not has_credential(p_ctx));
    arw_render_utils.set_flag(l_t, 'needs_session', has_credential(p_ctx)
                                                    and p_ctx.runtime_target_code in ('job', 'autonomous')
                                                    and p_ctx.engine_code like 'apex_web_service%');
    arw_render_utils.set_flag(l_t, 'trace_logger', p_ctx.trace_mode_code = 'logger');
    arw_render_utils.set_flag(l_t, 'trace_apex_debug', p_ctx.trace_mode_code = 'apex_debug');
    arw_render_utils.set_flag(l_t, 'has_trace', p_ctx.trace_mode_code in ('logger', 'apex_debug'));
    arw_render_utils.set_flag(l_t, 'audit', p_ctx.audit_enabled_yn = 'Y');
    arw_render_utils.set_flag(l_t, 'engine_apex_b', p_ctx.engine_code = 'apex_web_service_b');
    arw_render_utils.set_flag(l_t, 'engine_utl_http', p_ctx.engine_code = 'utl_http');
    arw_render_utils.set_flag(l_t, 'engine_dbms_cloud', p_ctx.engine_code = 'dbms_cloud_send_request');

    -- ---------------------------------------------------------------------------
    -- Parameters, body and headers
    -- ---------------------------------------------------------------------------
    for i in 1 .. p_ctx.params.count loop
      if p_ctx.params(i).kind_code = 'query' then
        l_has_query := true;
      end if;
    end loop;

    for i in 1 .. p_ctx.headers.count loop
      if p_ctx.headers(i).is_sensitive_yn = 'Y' then
        l_has_sensitive := true;
      end if;
    end loop;

    l_form_expr := form_body_expr(p_ctx, false);

    arw_render_utils.set_flag(l_t, 'has_params', p_ctx.params.count > 0 or p_ctx.body_template is not null);
    arw_render_utils.set_flag(l_t, 'has_query', l_has_query);
    arw_render_utils.set_flag(l_t, 'has_sensitive_headers', l_has_sensitive);
    arw_render_utils.set_flag(l_t, 'has_body', l_form_expr is not null or p_ctx.body_template is not null);
    arw_render_utils.set_flag(l_t, 'has_body_template', p_ctx.body_template is not null);

    if p_ctx.body_template is not null then
      arw_render_utils.set_token(l_t, 'body_literal', arw_render_utils.q_literal(p_ctx.body_template));
      arw_render_utils.set_token(l_t, 'body_build', 'l_body := coalesce(p_body, to_clob(gc_body_template));');
      arw_render_utils.set_token(l_t, 'block_body_literal', arw_render_utils.q_literal(p_ctx.body_template));
    elsif l_form_expr is not null then
      arw_render_utils.set_token(l_t, 'body_build', 'l_body := ' || l_form_expr || ';');
      arw_render_utils.set_token(l_t, 'block_body_literal', form_body_expr(p_ctx, true));
    end if;

    arw_render_utils.set_token(l_t, 'url_build', url_build_lines(p_ctx));
    arw_render_utils.set_token(l_t, 'block_url_literal', arw_render_utils.quote_literal(sample_url(p_ctx)));
    arw_render_utils.set_token(l_t, 'json_signature', signature_lines(p_ctx, p_ctx.json_function_name));
    arw_render_utils.set_token(l_t, 'typed_signature', signature_lines(p_ctx, p_ctx.function_name));
    arw_render_utils.set_token(l_t, 'json_call', call_lines(p_ctx, 'l_response := ' || p_ctx.json_function_name, 'pass', 4));
    arw_render_utils.set_token(l_t, 'example_json_call', call_lines(p_ctx, 'l_response := ' || l_schema_prefix || p_ctx.package_name || '.' || p_ctx.json_function_name, 'sample', 5));
    arw_render_utils.set_token(l_t, 'example_typed_call', call_lines(p_ctx, 'l_rows := ' || l_schema_prefix || p_ctx.package_name || '.' || p_ctx.function_name, 'sample', 5));

    for i in 1 .. p_ctx.params.count loop
      add(l_lines, '* @param ' || p_ctx.params(i).ident || ' '
                   || initcap(p_ctx.params(i).kind_code) || ' parameter ' || p_ctx.params(i).param_name
                   || case when p_ctx.params(i).is_required_yn = 'N' then ' (optional)' end);
    end loop;
    if p_ctx.body_template is not null then
      add(l_lines, '* @param p_body Request body; null sends the body template saved in ARW');
    end if;
    arw_render_utils.set_token(l_t, 'param_docs', join_lines(l_lines));

    l_lines := apex_t_varchar2();
    for i in 1 .. p_ctx.params.count loop
      add(l_lines, 'logger.append_param(l_params, ''' || p_ctx.params(i).ident || ''', ' || p_ctx.params(i).ident || ');');
    end loop;
    arw_render_utils.set_token(l_t, 'logger_append_params', join_lines(l_lines));

    arw_render_utils.set_token(l_t, 'header_assignments', header_lines(p_ctx, 'apex', 'g_header_'));
    arw_render_utils.set_token(l_t, 'utl_http_headers', header_lines(p_ctx, 'utl_http', 'g_header_'));
    arw_render_utils.set_token(l_t, 'dbms_cloud_headers', dbms_cloud_headers(p_ctx, 'g_header_'));
    arw_render_utils.set_token(l_t, 'sensitive_header_globals', sensitive_header_lines(p_ctx, 'g_header_', l_todo_tag));

    -- ---------------------------------------------------------------------------
    -- Data profile lists
    -- ---------------------------------------------------------------------------
    if has_profile(p_ctx) then
      arw_render_utils.set_token(l_t, 'record_fields', column_lines(p_ctx, 'record'));
      arw_render_utils.set_token(l_t, 'typed_select', column_lines(p_ctx, 'select'));
      arw_render_utils.set_token(l_t, 'json_table_columns', column_lines(p_ctx, 'jt'));
      arw_render_utils.set_token(l_t, 'print_concat', column_lines(p_ctx, 'print'));
    end if;

    logger.log('END', l_scope, null, l_params);

    return l_t;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end common_tokens;








  -- ===========================================================================
  -- FUNCTION: table_tokens (private)
  -- ===========================================================================
  /**
   * Adds the table_ddl tokens: column, constraint and comment lines. The
   * profile PK becomes the primary key (a generic id is renamed
   * <entity>_id); without one an identity <entity>_id is added. JSON
   * booleans become <name>_yn flags, arrays clob IS JSON columns; names
   * that clash with the audit columns get a _src suffix.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param io_tokens Token values to extend
   */
  procedure table_tokens(
      p_ctx                                     in t_ctx
    , io_tokens                                 in out nocopy arw_render_utils.t_tokens
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'table_tokens';
    l_params      logger.tab_param;
    l_columns     apex_t_varchar2 := apex_t_varchar2();
    l_constraints apex_t_varchar2 := apex_t_varchar2();
    l_comments    apex_t_varchar2 := apex_t_varchar2();
    l_table_ref   varchar2(300 char);
    l_entity_id   varchar2(128 char) := p_ctx.entity_name || '_id';
    l_pk_count    pls_integer := 0;
    l_pk_list     varchar2(4000 char);
    l_ident       varchar2(128 char);
    l_type        varchar2(100 char);
    l_comment     varchar2(4000 char);
    l_col         t_column_rec;

    procedure add_column(
        p_name                                  in varchar2
      , p_definition                            in varchar2
      , p_comment                               in varchar2
    )
    is
    begin
      add(l_columns, arw_render_utils.aligned(case when l_columns.count = 0 then '  ' else ', ' end, p_name, p_definition, 2, 35));
      add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.' || p_name
                      || ' is ''''' || replace(p_comment, '''') || ''''''';');
    end add_column;
  begin
    l_table_ref := case when p_ctx.target_schema is not null then lower(p_ctx.target_schema) || '.' end || p_ctx.table_name;

    add(l_comments, 'execute immediate ''comment on table ' || l_table_ref || ' is ''''Rows returned by '
                    || p_ctx.http_method || ' ' || replace(p_ctx.url_path, '''') || ' (' || replace(p_ctx.endpoint_name, '''') || ').'''''';');

    if has_profile(p_ctx) then
      for i in 1 .. p_ctx.profile_columns.count loop
        if p_ctx.profile_columns(i).parent_column_id is null and p_ctx.profile_columns(i).is_primary_key_yn = 'Y' then
          l_pk_count := l_pk_count + 1;
        end if;
      end loop;
    end if;

    if l_pk_count = 0 then
      add_column(l_entity_id, 'number generated by default on null as identity (start with 1) primary key not null', 'Primary key (identity).');
    end if;

    if has_profile(p_ctx) then
      for i in 1 .. p_ctx.profile_columns.count loop
        l_col := p_ctx.profile_columns(i);
        continue when l_col.parent_column_id is not null;

        if l_col.has_children_yn = 'Y' then
          l_col.is_json_yn := 'Y';
        end if;

        l_ident := l_col.ident;
        if l_pk_count = 1 and l_col.is_primary_key_yn = 'Y' and l_ident = 'id' then
          l_ident := l_entity_id;
        elsif l_col.data_type_code = 'boolean' and l_col.is_json_yn = 'N' and l_ident not like '%\_yn' escape '\' then
          l_ident := l_ident || '_yn';
        end if;

        if l_ident in ('active_yn', 'created_by', 'created_on', 'last_updated_by', 'last_updated_on') then
          l_ident := l_ident || '_src';
        end if;

        l_type := case
                    when l_col.data_type_code = 'boolean' and l_col.is_json_yn = 'N' then 'varchar2(1 char)'
                    else sql_type(l_col)
                  end;

        l_comment := 'JSON path ' || arw_render_utils.json_path(l_col.path_expression)
                     || case
                          when l_col.data_type_code = 'boolean' and l_col.is_json_yn = 'N' then ' (JSON boolean stored as Y/N).'
                          when l_col.is_json_yn = 'Y' then ' (nested JSON).'
                          else ' (' || nvl(l_col.source_data_type, l_col.data_type_code) || ').'
                        end;

        if l_pk_count = 1 and l_col.is_primary_key_yn = 'Y' then
          add_column(l_ident, l_type || ' not null primary key', 'Primary key; ' || l_comment);
        else
          add_column(l_ident, l_type || case when l_col.is_nullable_yn = 'N' then ' not null' end, l_comment);
          if l_col.is_primary_key_yn = 'Y' then
            l_pk_list := l_pk_list || case when l_pk_list is not null then ', ' end || l_ident;
          end if;
        end if;

        if l_col.data_type_code = 'boolean' and l_col.is_json_yn = 'N' then
          add(l_constraints, ', constraint ck_' || p_ctx.table_name || '_' || l_ident || ' check (' || l_ident || ' in (''Y'', ''N''))');
        elsif l_col.is_json_yn = 'Y' then
          add(l_constraints, ', constraint ck_' || p_ctx.table_name || '_' || l_ident || ' check (' || l_ident || ' is json)');
        end if;
      end loop;

      if l_pk_count > 1 then
        add(l_constraints, ', constraint pk_' || p_ctx.table_name || ' primary key (' || l_pk_list || ')');
      end if;
    else
      add_column('response_json', 'clob', 'Response body as returned by the service (JSON).');
      add(l_constraints, ', constraint ck_' || p_ctx.table_name || '_response_json check (response_json is json)');
    end if;

    add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.active_yn is ''''Soft-delete flag: Y = active, N = inactive.'''''';');
    add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.created_by is ''''User who created the row.'''''';');
    add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.created_on is ''''When the row was created.'''''';');
    add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.last_updated_by is ''''User who last updated the row.'''''';');
    add(l_comments, 'execute immediate ''comment on column ' || l_table_ref || '.last_updated_on is ''''When the row was last updated.'''''';');

    arw_render_utils.set_token(io_tokens, 'table_columns', join_lines(l_columns));
    arw_render_utils.set_token(io_tokens, 'table_constraints', join_lines(l_constraints));
    arw_render_utils.set_token(io_tokens, 'table_comments', join_lines(l_comments));
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end table_tokens;








  -- ===========================================================================
  -- PROCEDURE: curl_tokens (private)
  -- ===========================================================================
  /**
   * Adds the cURL tokens: quoted URL, header options (sensitive values and
   * credentials as ${VAR} placeholders), body and an auth note.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param io_tokens Token values to extend
   */
  procedure curl_tokens(
      p_ctx                                     in t_ctx
    , io_tokens                                 in out nocopy arw_render_utils.t_tokens
  )
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'curl_tokens';
    l_params       logger.tab_param;
    l_lines        apex_t_varchar2 := apex_t_varchar2();
    l_var          varchar2(200 char);
    l_content_type varchar2(500 char) := effective_content_type(p_ctx);
    l_body         clob;
  begin
    arw_render_utils.set_token(io_tokens, 'curl_url', arw_render_utils.shell_quote(sample_url(p_ctx)));

    for i in 1 .. p_ctx.headers.count loop
      if p_ctx.headers(i).is_sensitive_yn = 'Y' then
        add(l_lines, '--header "' || p_ctx.headers(i).header_name || ': ${' || upper(p_ctx.headers(i).ident) || '}"');
      else
        add(l_lines, '--header ' || arw_render_utils.shell_quote(p_ctx.headers(i).header_name || ': ' || p_ctx.headers(i).header_value));
      end if;
    end loop;

    if l_content_type is not null then
      add(l_lines, '--header ' || arw_render_utils.shell_quote('Content-Type: ' || l_content_type));
    end if;

    arw_render_utils.set_token(io_tokens, 'curl_headers', join_lines(l_lines));

    l_body := coalesce(p_ctx.body_template, to_clob(substr(form_body_expr(p_ctx, true), 2, length(form_body_expr(p_ctx, true)) - 2)));
    if l_body is not null and dbms_lob.getlength(l_body) > 0 then
      arw_render_utils.set_token(io_tokens, 'curl_body', arw_render_utils.shell_quote(dbms_lob.substr(l_body, 32000, 1)));
    end if;

    l_var := upper(arw_render_utils.to_identifier(nvl(p_ctx.credential_static_id, 'api'), 60));
    arw_render_utils.set_token(io_tokens, 'secret_token_var', '${' || l_var || '_TOKEN}');
    arw_render_utils.set_token(io_tokens, 'secret_user_var', '${' || l_var || '_USERNAME}');
    arw_render_utils.set_token(io_tokens, 'secret_password_var', '${' || l_var || '_PASSWORD}');
    arw_render_utils.set_token(io_tokens, 'secret_key_var', '${' || l_var || '_KEY}');
    arw_render_utils.set_token(io_tokens, 'secret_key_header_var', '${' || l_var || '_HEADER_NAME}');
    arw_render_utils.set_token(io_tokens, 'secret_key_param_var', '${' || l_var || '_PARAM_NAME}');
    arw_render_utils.set_token(io_tokens, 'auth_note', case p_ctx.auth_type_code
      when 'oauth2_client_credentials' then 'OAuth2 client credentials: get a token from the token URL first and export it as ' || l_var || '_TOKEN.'
      when 'oauth2_password'           then 'OAuth2 password flow: get a token from the token URL first and export it as ' || l_var || '_TOKEN.'
      when 'oci'                       then 'OCI request signing is not plain cURL: use "oci raw-request" with the same URL.'
      when 'jwt_signed'                then 'Signed JWT: sign a token first and send it as an Authorization header.'
      when 'mtls'                      then 'mTLS: point CLIENT_CERT_FILE / CLIENT_KEY_FILE at the client certificate and key.'
      when 'sigv4'                     then 'SigV4: export AWS_REGION, AWS_SERVICE and the access keys first.'
    end);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end curl_tokens;








  -- ===========================================================================
  -- PROCEDURE: rds_url_parts (private)
  -- ===========================================================================
  /**
   * Splits the request path for a REST Data Source: the URL path prefix is
   * the static part before the first path parameter; the rest (with :name
   * parameters) is the operation's URL pattern ("." when there is none).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   PHASE2-simplified (demo app download)
   *
   * @author  Angel Flores (Developer)
   * @created November 3, 2026
   *
   * @param p_ctx Generation context
   * @param o_prefix URL path prefix
   * @param o_pattern Operation URL pattern
   */
  procedure rds_url_parts(
      p_ctx                                     in t_ctx
    , o_prefix                                  out varchar2
    , o_pattern                                 out varchar2
  )
  is
    l_path      varchar2(4000 char);
    l_param_pos pls_integer;
  begin
    l_path      := regexp_replace(p_ctx.url_path, '\?.*$');
    l_path      := regexp_replace(l_path, '\{\{([A-Za-z0-9_]+)\}\}', ':\1');
    l_path      := regexp_replace(l_path, '\{([A-Za-z0-9_]+)\}', ':\1');
    l_param_pos := regexp_instr(l_path, '/:[A-Za-z0-9_]');
    if l_param_pos > 0 then
      o_prefix  := substr(l_path, 1, l_param_pos);
      o_pattern := substr(l_path, l_param_pos + 1);
    else
      o_prefix  := nvl(l_path, '/');
      o_pattern := '.';
    end if;
  end rds_url_parts;








  -- ===========================================================================
  -- FUNCTION: apx_name (private)
  -- ===========================================================================
  /**
   * An APEXlang name value: kept as-is when it is a plain token, otherwise
   * double-quoted.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Value
   * @return varchar2 APEXlang value
   */
  function apx_name(
      p_text                                    in varchar2
  )
  return varchar2
  is
  begin
    return case
             when regexp_like(p_text, '^[A-Za-z0-9_][A-Za-z0-9_.-]*$') then p_text
             else '"' || replace(replace(p_text, '\', '\\'), '"', '\"') || '"'
           end;
  end apx_name;








  -- ===========================================================================
  -- PROCEDURE: apexlang_tokens (private)
  -- ===========================================================================
  /**
   * Adds the APEXlang tokens: server/credential/REST source ids, parameter
   * and dataProfileColumn blocks, operation, AI tool and automation code.
   * Web Credential types follow IMPLEMENTATION.md section 10.4; the
   * credential's component id is its APEX static id, so the generated
   * package and the REST source use the same credential.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param io_tokens Token values to extend
   */
  procedure apexlang_tokens(
      p_ctx                                     in t_ctx
    , io_tokens                                 in out nocopy arw_render_utils.t_tokens
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'apexlang_tokens';
    l_params      logger.tab_param;
    l_lines       apex_t_varchar2 := apex_t_varchar2();
    l_host        varchar2(1000 char);
    l_prefix      varchar2(4000 char);
    l_pattern     varchar2(4000 char);
    l_seq         pls_integer := 0;
    l_id          varchar2(255 char);
    l_ids         apex_t_varchar2 := apex_t_varchar2();
    l_type        varchar2(30 char);
    l_parent_name varchar2(200 char);
    l_package_ref varchar2(300 char);
    l_call_fn     varchar2(128 char);
    l_parts       apex_t_varchar2;
    l_column_ids  t_id_map;

    function unique_id(
        p_base                                  in varchar2
    )
    return varchar2
    is
      l_candidate varchar2(255 char) := p_base;
      l_n         pls_integer := 1;
    begin
      while l_candidate member of l_ids loop
        l_n := l_n + 1;
        l_candidate := p_base || '-' || l_n;
      end loop;
      l_ids.extend;
      l_ids(l_ids.count) := l_candidate;
      return l_candidate;
    end unique_id;

    procedure add_value_block(
        p_static                                in boolean
      , p_value                                 in varchar2
    )
    is
    begin
      add(l_lines, '    value {');
      add(l_lines, '        static: ' || case when p_static then 'true' else 'false' end);
      add(l_lines, '        defaultValueType: staticValue');
      add(l_lines, '        staticValue:');
      add(l_lines, '            ```');
      add(l_lines, '            ' || p_value);
      add(l_lines, '            ```');
      add(l_lines, '    }');
    end add_value_block;
  begin
    l_package_ref := case when p_ctx.target_schema is not null then lower(p_ctx.target_schema) || '.' end || p_ctx.package_name;

    -- ---------------------------------------------------------------------------
    -- Server, credential, REST source
    -- ---------------------------------------------------------------------------
    l_host := regexp_substr(p_ctx.base_url, '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)', 1, 1, null, 1);
    arw_render_utils.set_token(io_tokens, 'server_id', arw_render_utils.to_static_id(nvl(l_host, 'rest-server')));
    arw_render_utils.set_token(io_tokens, 'server_name', nvl(l_host, 'rest-server'));
    arw_render_utils.set_token(io_tokens, 'server_url', p_ctx.base_url || '/');

    arw_render_utils.set_token(io_tokens, 'cred_id', apx_name(p_ctx.credential_static_id));
    arw_render_utils.set_token(io_tokens, 'cred_file', arw_render_utils.to_static_id(p_ctx.credential_static_id));
    arw_render_utils.set_token(io_tokens, 'cred_name', arw_render_utils.apx_text(nvl(p_ctx.credential_name, p_ctx.credential_static_id)));
    arw_render_utils.set_token(io_tokens, 'api_key_name', coalesce(
                                                            p_ctx.api_key_name
                                                          , case when p_ctx.auth_type_code = 'api_key_query' then 'api_key' else 'X-API-Key' end
                                                          ));
    arw_render_utils.set_flag(io_tokens, 'rds_has_credential', has_credential(p_ctx));

    arw_render_utils.set_token(io_tokens, 'rds_id', arw_render_utils.to_static_id(p_ctx.endpoint_name));
    arw_render_utils.set_token(io_tokens, 'rds_name', arw_render_utils.apx_text(p_ctx.endpoint_name));

    rds_url_parts(
        p_ctx                                   => p_ctx
      , o_prefix                                => l_prefix
      , o_pattern                               => l_pattern
    );
    arw_render_utils.set_token(io_tokens, 'rds_url_prefix', l_prefix);
    arw_render_utils.set_token(io_tokens, 'op_url_pattern', l_pattern);
    arw_render_utils.set_token(io_tokens, 'op_id', lower(p_ctx.http_method));
    arw_render_utils.set_token(io_tokens, 'op_db_operation', case p_ctx.http_method
                                                               when 'POST'   then 'insert'
                                                               when 'PUT'    then 'update'
                                                               when 'PATCH'  then 'update'
                                                               when 'DELETE' then 'delete'
                                                               else 'fetchRows'
                                                             end);
    arw_render_utils.set_flag(io_tokens, 'op_has_body', p_ctx.body_template is not null and p_ctx.http_method not in ('GET', 'HEAD', 'OPTIONS'));
    arw_render_utils.set_token(io_tokens, 'op_body_template', p_ctx.body_template);

    -- ---------------------------------------------------------------------------
    -- REST source parameters
    -- ---------------------------------------------------------------------------
    for i in 1 .. p_ctx.params.count loop
      continue when p_ctx.params(i).kind_code = 'form';

      if l_lines.count > 0 then
        add(l_lines, '');
      end if;
      add(l_lines, 'parameter ' || unique_id(arw_render_utils.to_static_id(p_ctx.params(i).param_name)) || ' (');
      add(l_lines, '    name: ' || apx_name(p_ctx.params(i).param_name));
      add(l_lines, '    parameter {');
      add(l_lines, '        type: ' || case p_ctx.params(i).kind_code when 'path' then 'urlPattern' else 'urlQueryString' end);
      add(l_lines, '        dataType: ' || case p_ctx.params(i).plsql_type
                                             when 'number'  then 'numeric'
                                             when 'date'    then 'date'
                                             when 'boolean' then 'boolean'
                                             else 'string'
                                           end);
      add(l_lines, '    }');
      if p_ctx.params(i).param_value is not null then
        add_value_block(false, p_ctx.params(i).param_value);
      end if;
      add(l_lines, '    validation {');
      add(l_lines, '        required: ' || case when p_ctx.params(i).is_required_yn = 'Y' then 'true' else 'false' end);
      add(l_lines, '    }');
      add(l_lines, ')');
    end loop;

    for i in 1 .. p_ctx.headers.count loop
      if l_lines.count > 0 then
        add(l_lines, '');
      end if;

      if p_ctx.headers(i).is_sensitive_yn = 'Y' then
        add(l_lines, '// Header ' || p_ctx.headers(i).header_name || ' is sensitive: move it into the Web Credential.');
        continue;
      end if;

      add(l_lines, 'parameter ' || unique_id(arw_render_utils.to_static_id(p_ctx.headers(i).header_name)) || ' (');
      add(l_lines, '    name: ' || apx_name(p_ctx.headers(i).header_name));
      add(l_lines, '    parameter {');
      add(l_lines, '        type: httpHeader');
      add(l_lines, '        dataType: string');
      add(l_lines, '    }');
      add_value_block(true, p_ctx.headers(i).header_value);
      add(l_lines, ')');
    end loop;

    arw_render_utils.set_flag(io_tokens, 'has_rds_parameters', l_lines.count > 0);
    arw_render_utils.set_token(io_tokens, 'rds_parameters', join_lines(l_lines));

    -- ---------------------------------------------------------------------------
    -- dataProfileColumn blocks
    -- ---------------------------------------------------------------------------
    l_lines := apex_t_varchar2();
    if has_profile(p_ctx) then
      for i in 1 .. p_ctx.profile_columns.count loop
        l_seq := l_seq + 1;
        l_type := case
                    when p_ctx.profile_columns(i).has_children_yn = 'Y' then 'array'
                    when p_ctx.profile_columns(i).is_json_yn = 'Y'      then 'clob'
                    else case p_ctx.profile_columns(i).data_type_code
                           when 'timestamp_with_time_zone' then 'timestampWithTimeZone'
                           else p_ctx.profile_columns(i).data_type_code
                         end
                  end;

        -- parentColumn references the parent column's component id (@id)
        l_parent_name := null;
        if p_ctx.profile_columns(i).parent_column_id is not null
           and l_column_ids.exists(p_ctx.profile_columns(i).parent_column_id) then
          l_parent_name := '@' || l_column_ids(p_ctx.profile_columns(i).parent_column_id);
        end if;

        if l_lines.count > 0 then
          add(l_lines, '');
        end if;
        l_id := unique_id(arw_render_utils.to_static_id(p_ctx.profile_columns(i).ident));
        l_column_ids(p_ctx.profile_columns(i).column_id) := l_id;
        add(l_lines, 'dataProfileColumn ' || l_id || ' (');
        add(l_lines, '    columnName: ' || upper(p_ctx.profile_columns(i).ident));
        add(l_lines, '    source {');
        add(l_lines, '        sequence: ' || l_seq);
        add(l_lines, '        dataType: ' || l_type);
        if l_type = 'varchar2' then
          add(l_lines, '        maxLength: ' || least(greatest(nvl(p_ctx.profile_columns(i).max_observed_length, 4000), 1), 4000));
        end if;
        if p_ctx.profile_columns(i).is_primary_key_yn = 'Y' and p_ctx.profile_columns(i).parent_column_id is null then
          add(l_lines, '        primaryKey: true');
        end if;
        if l_parent_name is not null then
          add(l_lines, '        parentColumn: ' || l_parent_name);
        end if;
        add(l_lines, '    }');
        add(l_lines, '    parsing {');
        add(l_lines, '        pathExpression: ' || p_ctx.profile_columns(i).path_expression);
        if p_ctx.profile_columns(i).format_mask is not null and l_type in ('date', 'timestampWithTimeZone') then
          add(l_lines, '        formatMask: ' || p_ctx.profile_columns(i).format_mask);
        end if;
        add(l_lines, '    }');
        add(l_lines, ')');
      end loop;
    end if;
    arw_render_utils.set_token(io_tokens, 'rds_columns', join_lines(l_lines));

    -- ---------------------------------------------------------------------------
    -- AI agent tool
    -- ---------------------------------------------------------------------------
    arw_render_utils.set_token(io_tokens, 'agent_id', arw_render_utils.to_static_id(p_ctx.package_name || '-agent'));
    arw_render_utils.set_token(io_tokens, 'agent_name', arw_render_utils.apx_text(initcap(replace(p_ctx.resource_name, '_', ' ')) || ' agent'));
    arw_render_utils.set_token(io_tokens, 'tool_id', arw_render_utils.to_static_id(p_ctx.function_name));
    arw_render_utils.set_token(io_tokens, 'tool_name', p_ctx.function_name);

    l_lines := apex_t_varchar2();
    add(l_lines, 'declare');
    add(l_lines, '  l_response clob;');
    add(l_lines, 'begin');
    l_parts := apex_string.split(call_lines(p_ctx, 'l_response := ' || l_package_ref || '.' || p_ctx.json_function_name, 'bind', 2), gc_lf);
    for j in 1 .. l_parts.count loop
      add(l_lines, '  ' || l_parts(j));
    end loop;
    add(l_lines, '  apex_ai.set_tool_result(p_result => l_response);');
    add(l_lines, 'end;');
    arw_render_utils.set_token(io_tokens, 'tool_plsql', join_lines(l_lines));

    l_lines := apex_t_varchar2();
    for i in 1 .. p_ctx.params.count loop
      if l_lines.count > 0 then
        add(l_lines, '');
      end if;
      add(l_lines, 'parameter ' || upper(substr(p_ctx.params(i).ident, 3)) || ' (');
      add(l_lines, '    description:');
      add(l_lines, '        ```');
      add(l_lines, '        ' || initcap(p_ctx.params(i).kind_code) || ' parameter ' || p_ctx.params(i).param_name
                   || case when p_ctx.params(i).param_value is not null then ', for example ' || p_ctx.params(i).param_value end || '.');
      add(l_lines, '        ```');
      add(l_lines, '    value {');
      add(l_lines, '        dataType: ' || case p_ctx.params(i).plsql_type when 'date' then 'varchar2' else p_ctx.params(i).plsql_type end);
      add(l_lines, '    }');
      add(l_lines, '    validation {');
      add(l_lines, '        required: ' || case when p_ctx.params(i).is_required_yn = 'Y' then 'true' else 'false' end);
      add(l_lines, '    }');
      add(l_lines, ')');
    end loop;

    if p_ctx.body_template is not null then
      if l_lines.count > 0 then
        add(l_lines, '');
      end if;
      add(l_lines, 'parameter BODY (');
      add(l_lines, '    description:');
      add(l_lines, '        ```');
      add(l_lines, '        JSON request body; leave empty to send the saved body template.');
      add(l_lines, '        ```');
      add(l_lines, '    value {');
      add(l_lines, '        dataType: clob');
      add(l_lines, '    }');
      add(l_lines, '    validation {');
      add(l_lines, '        required: false');
      add(l_lines, '    }');
      add(l_lines, ')');
    end if;

    arw_render_utils.set_flag(io_tokens, 'has_tool_parameters', l_lines.count > 0);
    arw_render_utils.set_token(io_tokens, 'tool_parameters', join_lines(l_lines));

    -- ---------------------------------------------------------------------------
    -- Automation
    -- ---------------------------------------------------------------------------
    l_call_fn := case when has_profile(p_ctx) then p_ctx.function_name else p_ctx.json_function_name end;
    arw_render_utils.set_token(io_tokens, 'call_function_name', l_call_fn);
    arw_render_utils.set_token(io_tokens, 'automation_id', arw_render_utils.to_static_id(p_ctx.package_name || '-' || p_ctx.function_name));
    arw_render_utils.set_token(io_tokens, 'automation_name', arw_render_utils.apx_text('Run ' || p_ctx.package_name || '.' || l_call_fn));
    arw_render_utils.set_token(io_tokens, 'automation_action_id', arw_render_utils.to_static_id('call-' || l_call_fn));
    arw_render_utils.set_token(io_tokens, 'automation_action_name', arw_render_utils.apx_text('Call ' || l_call_fn));

    l_lines := apex_t_varchar2();
    add(l_lines, 'declare');
    if has_profile(p_ctx) then
      add(l_lines, '  l_rows ' || l_package_ref || '.' || p_ctx.tab_type || ';');
    else
      add(l_lines, '  l_response clob;');
    end if;
    add(l_lines, 'begin');
    l_parts := apex_string.split(call_lines(p_ctx
                                          , case when has_profile(p_ctx) then 'l_rows' else 'l_response' end
                                            || ' := ' || l_package_ref || '.' || l_call_fn
                                          , 'sample'
                                          , 2), gc_lf);
    for j in 1 .. l_parts.count loop
      add(l_lines, '  ' || l_parts(j));
    end loop;
    if has_profile(p_ctx) then
      add(l_lines, '  apex_automation.log_info(''' || l_call_fn || ' returned '' || l_rows.count || '' row(s).'');');
    else
      add(l_lines, '  apex_automation.log_info(''' || l_call_fn || ' returned '' || dbms_lob.getlength(l_response) || '' characters.'');');
    end if;
    add(l_lines, 'end;');
    arw_render_utils.set_token(io_tokens, 'automation_plsql', join_lines(l_lines));

    arw_render_utils.set_token(io_tokens, 'install_spec_id', arw_render_utils.to_static_id(p_ctx.package_name || '-spec'));
    arw_render_utils.set_token(io_tokens, 'install_body_id', arw_render_utils.to_static_id(p_ctx.package_name || '-body'));
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end apexlang_tokens;








  -- ===========================================================================
  -- FUNCTION: variant_codes (private)
  -- ===========================================================================
  /**
   * Colon-delimited variant list (most specific first) the template
   * sections are resolved against: runtime (job when a session must be
   * created), engine (apex_web_service_b falls back to apex_web_service),
   * auth type, profile/raw, default.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_artifact_type_code Artifact being generated
   * @return varchar2 Variant list
   */
  function variant_codes(
      p_ctx                                     in t_ctx
    , p_artifact_type_code                      in varchar2
  )
  return varchar2
  is
    l_session boolean;
    l_list    varchar2(400 char);
  begin
    l_session := has_credential(p_ctx)
                 and p_ctx.engine_code like 'apex_web_service%'
                 and (p_ctx.runtime_target_code in ('job', 'autonomous') or p_artifact_type_code = 'plsql_block');

    if l_session and p_artifact_type_code in ('plsql_package', 'plsql_block') then
      l_list := 'job:';
    end if;

    l_list := l_list || case p_ctx.engine_code
                          when 'apex_web_service_b' then 'apex_web_service_b:apex_web_service'
                          else p_ctx.engine_code
                        end;

    if p_ctx.credential_static_id is not null then
      l_list := l_list || ':' || case
                                   when p_artifact_type_code = 'apexlang_rds' and not has_credential(p_ctx) then 'unsupported'
                                   else p_ctx.auth_type_code
                                 end;
    end if;

    return l_list || ':' || case when has_profile(p_ctx) then 'profile' else 'raw' end || ':default';
  end variant_codes;








  -- ===========================================================================
  -- PROCEDURE: continue_curl_lines (private)
  -- ===========================================================================
  /**
   * Adds the shell line continuation (" \") to every cURL line that is
   * followed by another option line ("  --...").
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param io_content cURL artifact text
   */
  procedure continue_curl_lines(
      io_content                                in out nocopy clob
  )
  is
    l_lines  apex_t_varchar2;
    l_result apex_t_varchar2 := apex_t_varchar2();
  begin
    l_lines := apex_string.split(io_content, gc_lf);

    for i in 1 .. l_lines.count loop
      if i < l_lines.count and l_lines(i + 1) like '  --%' then
        add(l_result, l_lines(i) || ' \');
      else
        add(l_result, l_lines(i));
      end if;
    end loop;

    io_content := apex_string.join_clob(l_result, gc_lf);
  end continue_curl_lines;








  -- ===========================================================================
  -- FUNCTION: generate (private)
  -- ===========================================================================
  /**
   * Generates one artifact for an already-loaded context.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context
   * @param p_artifact_type_code Artifact type
   * @return clob Artifact content
   */
  function generate(
      p_ctx                                     in t_ctx
    , p_artifact_type_code                      in varchar2
  )
  return clob
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'generate';
    l_params   logger.tab_param;
    l_tokens   arw_render_utils.t_tokens;
    l_content  clob;
    l_variants varchar2(400 char);
  begin
    logger.append_param(l_params, 'p_artifact_type_code', p_artifact_type_code);
    logger.log('START', l_scope, null, l_params);

    l_tokens   := common_tokens(p_ctx);
    l_variants := variant_codes(p_ctx, p_artifact_type_code);

    case p_artifact_type_code
      when 'plsql_block' then
        -- A worksheet has no APEX session: a credential always needs one
        arw_render_utils.set_flag(l_tokens, 'needs_session', has_credential(p_ctx) and p_ctx.engine_code like 'apex_web_service%');
        arw_render_utils.set_token(l_tokens, 'header_assignments', header_lines(p_ctx, 'apex', 'l_header_'));
        arw_render_utils.set_token(l_tokens, 'utl_http_headers', header_lines(p_ctx, 'utl_http', 'l_header_'));
        arw_render_utils.set_token(l_tokens, 'dbms_cloud_headers', dbms_cloud_headers(p_ctx, 'l_header_'));
        arw_render_utils.set_token(l_tokens, 'sensitive_header_locals', sensitive_header_lines(p_ctx, 'l_header_', l_tokens('todo_tag')));
      when 'json_table' then
        if has_profile(p_ctx) then
          arw_render_utils.set_token(l_tokens, 'json_select', column_lines(p_ctx, 'select_nested'));
          arw_render_utils.set_token(l_tokens, 'json_table_columns', column_lines(p_ctx, 'jt_nested'));
        end if;
      when 'table_ddl' then
        table_tokens(p_ctx, l_tokens);
      when 'curl' then
        curl_tokens(p_ctx, l_tokens);
      when 'apexlang_install_script' then
        apexlang_tokens(p_ctx, l_tokens);
        arw_render_utils.set_token(l_tokens, 'package_spec_text', rtrim(arw_render_utils.assemble('plsql_package', variant_codes(p_ctx, 'plsql_package'), l_tokens, 'spec'), gc_lf));
        arw_render_utils.set_token(l_tokens, 'package_body_text', rtrim(arw_render_utils.assemble('plsql_package', variant_codes(p_ctx, 'plsql_package'), l_tokens
                                                                                                 , 'declaration:headers:auth:invocation:status:parsing:example:footer'), gc_lf));
      else
        if p_artifact_type_code like 'apexlang%' then
          apexlang_tokens(p_ctx, l_tokens);
        end if;
    end case;

    l_content := arw_render_utils.assemble(
        p_template_type_code                    => p_artifact_type_code
      , p_variant_codes                         => l_variants
      , p_tokens                                => l_tokens
    );

    if p_artifact_type_code = 'curl' then
      continue_curl_lines(l_content);
    end if;

    l_content := rtrim(l_content, gc_lf) || gc_lf;

    logger.log('END', l_scope, null, l_params);

    return l_content;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end generate;








  -- ===========================================================================
  -- PROCEDURE: validate_type (private)
  -- ===========================================================================
  /**
   * Raises gc_err_invalid_input for an unknown artifact type.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_artifact_type_code Artifact type to check
   * @param p_types Colon-wrapped list of allowed types
   */
  procedure validate_type(
      p_artifact_type_code                      in varchar2
    , p_types                                   in varchar2 default gc_artifact_types
  )
  is
  begin
    if p_artifact_type_code is null or instr(p_types, ':' || p_artifact_type_code || ':') = 0 then
      raise_application_error(gc_err_invalid_input, 'Unknown or unsupported artifact type: ' || nvl(p_artifact_type_code, '(null)')
                                                    || '. Valid: ' || replace(trim(both ':' from p_types), ':', ', '));
    end if;
  end validate_type;








  -- ===========================================================================
  -- PROCEDURE: write_artifact (private)
  -- ===========================================================================
  /**
   * Stores a new version of the artifact unless the latest stored version
   * of (endpoint, target profile, type) has the same checksum. Runs in the
   * caller's transaction and never commits -- see store_artifact for the
   * autonomous variant and get_artifact for which one is used when.
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context (endpoint, target and data profile)
   * @param p_artifact_type_code Artifact type
   * @param p_content Generated content
   * @param p_checksum Checksum of the content (date-independent)
   */
  procedure write_artifact(
      p_ctx                                     in t_ctx
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_content                                 in clob
    , p_checksum                                in arw_generated_artifacts.checksum%type
  )
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'write_artifact';
    l_params       logger.tab_param;
    l_last_sum     arw_generated_artifacts.checksum%type;
    l_last_version arw_generated_artifacts.version_num%type;
  begin
    logger.append_param(l_params, 'endpoint_id', p_ctx.endpoint_id);
    logger.append_param(l_params, 'p_artifact_type_code', p_artifact_type_code);
    logger.log('START', l_scope, null, l_params);

    begin
      select ga.checksum                                   as checksum
           , ga.version_num                                as version_num
        into l_last_sum
           , l_last_version
        from arw_generated_artifacts ga
       where ga.endpoint_id = p_ctx.endpoint_id
         and ga.target_profile_id = p_ctx.target_profile_id
         and ga.artifact_type_code = p_artifact_type_code
         and ga.active_yn = 'Y'
       order by ga.version_num desc
       fetch first 1 row only;
    exception
      when no_data_found then
        l_last_sum     := null;
        l_last_version := 0;
    end;

    if l_last_sum is null or l_last_sum != p_checksum then
      insert
        into arw_generated_artifacts (
             endpoint_id
           , target_profile_id
           , data_profile_id
           , artifact_type_code
           , content
           , checksum
           , version_num
      )
      values (
             p_ctx.endpoint_id
           , p_ctx.target_profile_id
           , p_ctx.data_profile_id
           , p_artifact_type_code
           , p_content
           , p_checksum
           , l_last_version + 1
      );
      logger.append_param(l_params, 'version_num', l_last_version + 1);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end write_artifact;








  -- ===========================================================================
  -- PROCEDURE: store_artifact (private)
  -- ===========================================================================
  /**
   * write_artifact in its own autonomous transaction -- the artifact history
   * is a log, like arw_executions -- so get_artifact also works from a SQL
   * query or a region source. Only safe when the caller has no uncommitted
   * work: an artifact referencing a data profile the caller just created
   * would wait on the caller's own transaction (ORA-00060).
   *
   * @example N/A -- private package-body unit; exercised through get_artifact.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx Generation context (endpoint, target and data profile)
   * @param p_artifact_type_code Artifact type
   * @param p_content Generated content
   * @param p_checksum Checksum of the content (date-independent)
   */
  procedure store_artifact(
      p_ctx                                     in t_ctx
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_content                                 in clob
    , p_checksum                                in arw_generated_artifacts.checksum%type
  )
  is
    pragma autonomous_transaction;
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'store_artifact';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_artifact_type_code', p_artifact_type_code);
    logger.log('START', l_scope, null, l_params);

    write_artifact(
        p_ctx                                   => p_ctx
      , p_artifact_type_code                    => p_artifact_type_code
      , p_content                               => p_content
      , p_checksum                              => p_checksum
    );

    commit;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      rollback;
      raise;
  end store_artifact;








  -- ===========================================================================
  -- FUNCTION: render_artifact
  -- ===========================================================================
  /**
   * Generates an artifact without storing it (preview). Works with or
   * without a data profile: without one the typed parts degrade to the
   * raw clob/JSON (package returns only the _json function, json_table
   * returns rows as JSON, the table keeps the response as JSON).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_code clob;
   * begin
   *   l_code := arw_codegen_api.render_artifact(
   *       p_endpoint_id                        => 1
   *     , p_artifact_type_code                 => 'curl'
   *   );
   *   dbms_output.put_line(l_code);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint to generate for
   * @param p_artifact_type_code plsql_package, plsql_block, json_table, table_ddl, curl, apexlang_rds, apexlang_install_script, apexlang_ai_tool or apexlang_automation
   * @param p_target_profile_id Target profile; null = default profile (lowest active id)
   * @return clob Generated content
   */
  function render_artifact(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob
  is
    l_scope   logger_logs.scope%type := gc_scope_prefix || 'render_artifact';
    l_params  logger.tab_param;
    l_content clob;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_artifact_type_code', p_artifact_type_code);
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.log('START', l_scope, null, l_params);

    validate_type(p_artifact_type_code => p_artifact_type_code);

    l_content := generate(
        p_ctx                                   => load_context(p_endpoint_id, p_target_profile_id)
      , p_artifact_type_code                    => p_artifact_type_code
    );

    logger.log('END', l_scope, null, l_params);

    return l_content;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end render_artifact;








  -- ===========================================================================
  -- FUNCTION: get_artifact
  -- ===========================================================================
  /**
   * Generates the artifact, stores a new version in
   * arw_generated_artifacts when its checksum differs from the latest
   * stored version (the generation date is excluded from the checksum, so
   * regenerating unchanged code on another day adds no version), and
   * returns the content. Storage is skipped when no target profile exists
   * at all (built-in defaults are used then).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_code clob;
   * begin
   *   l_code := arw_codegen_api.get_artifact(
   *       p_endpoint_id                        => 1
   *     , p_artifact_type_code                 => 'plsql_package'
   *   );
   *   dbms_output.put_line(dbms_lob.substr(l_code, 4000, 1));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint to generate for
   * @param p_artifact_type_code Artifact type (see render_artifact)
   * @param p_target_profile_id Target profile; null = default profile (lowest active id)
   * @return clob Generated content
   */
  function get_artifact(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'get_artifact';
    l_params   logger.tab_param;
    l_ctx      t_ctx;
    l_content  clob;
    l_checksum arw_generated_artifacts.checksum%type;

    e_dml_in_query exception;
    pragma exception_init(e_dml_in_query, -14551);
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_artifact_type_code', p_artifact_type_code);
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.log('START', l_scope, null, l_params);

    validate_type(p_artifact_type_code => p_artifact_type_code);

    l_ctx     := load_context(p_endpoint_id, p_target_profile_id);
    l_content := generate(l_ctx, p_artifact_type_code);

    if l_ctx.target_profile_id is not null then
      l_checksum := arw_render_utils.sha256_hex(
                      replace(replace(l_content
                                    , to_char(sysdate, 'fmMonth DD, YYYY', 'nls_date_language=english'))
                                    , to_char(sysdate, 'fmMONTH-DD-YYYY', 'nls_date_language=english'))
                    );


      -- =========================================================================
      -- Version only when the content changed. With nothing pending in the
      -- caller's transaction, store autonomously (works from SQL too);
      -- otherwise store in the caller's transaction, since the artifact may
      -- reference rows it has not committed yet. From a query with pending
      -- work (ORA-14551) the version is simply not recorded.
      -- =========================================================================

      if dbms_transaction.local_transaction_id is null then
        store_artifact(
            p_ctx                               => l_ctx
          , p_artifact_type_code                => p_artifact_type_code
          , p_content                           => l_content
          , p_checksum                          => l_checksum
        );
      else
        begin
          write_artifact(
              p_ctx                             => l_ctx
            , p_artifact_type_code              => p_artifact_type_code
            , p_content                         => l_content
            , p_checksum                        => l_checksum
          );
        exception
          when e_dml_in_query then
            logger.log('Version not stored: called from a query with pending work', l_scope, null, l_params);
        end;
      end if;
      -- =========================================================================
    end if;

    logger.log('END', l_scope, null, l_params);

    return l_content;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end get_artifact;








  -- ===========================================================================
  -- FUNCTION: build_apx_bundle
  -- ===========================================================================
  /**
   * Concatenates the chosen APEXlang artifacts (each generated and
   * versioned through get_artifact) into one .apx text with a header
   * comment. Every component keeps its "// file:" marker naming the file
   * it belongs to in an APEXlang app tree.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_apx clob;
   * begin
   *   l_apx := arw_codegen_api.build_apx_bundle(
   *       p_endpoint_id                        => 1
   *     , p_artifact_type_codes                => 'apexlang_rds:apexlang_install_script:apexlang_ai_tool'
   *   );
   *   dbms_output.put_line(dbms_lob.substr(l_apx, 4000, 1));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint to generate for
   * @param p_artifact_type_codes Colon-delimited APEXlang artifact types
   * @param p_target_profile_id Target profile; null = default profile (lowest active id)
   * @return clob .apx bundle text
   */
  function build_apx_bundle(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_codes                     in varchar2
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'build_apx_bundle';
    l_params logger.tab_param;
    l_codes  apex_t_varchar2;
    l_done   apex_t_varchar2 := apex_t_varchar2();
    l_ctx    t_ctx;
    l_bundle clob;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_artifact_type_codes', p_artifact_type_codes);
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.log('START', l_scope, null, l_params);

    l_codes := apex_string.split(trim(p_artifact_type_codes), ':');

    for i in 1 .. l_codes.count loop
      if trim(l_codes(i)) is not null and trim(l_codes(i)) not member of l_done then
        validate_type(trim(l_codes(i)), gc_apexlang_types);
        add(l_done, trim(l_codes(i)));
      end if;
    end loop;

    if l_done.count = 0 then
      raise_application_error(gc_err_invalid_input, 'Choose at least one APEXlang component for the bundle.');
    end if;

    l_ctx := load_context(p_endpoint_id, p_target_profile_id);

    dbms_lob.createtemporary(l_bundle, true);
    dbms_lob.append(l_bundle, '// =============================================================================' || gc_lf
                              || '// ARW .apx bundle: ' || l_ctx.endpoint_name || ' (' || l_ctx.http_method || ' ' || l_ctx.url_path || ')' || gc_lf
                              || '// Generated on ' || to_char(sysdate, 'fmMonth DD, YYYY', 'nls_date_language=english')
                              || ' -- components: ' || apex_string.join(l_done, ', ') || gc_lf
                              || '// Split it at the "// file:" markers into an APEXlang app tree, then run' || gc_lf
                              || '// apex validate before apex import.' || gc_lf
                              || '// =============================================================================' || gc_lf);

    for i in 1 .. l_done.count loop
      dbms_lob.append(l_bundle, gc_lf);
      dbms_lob.append(l_bundle, get_artifact(
                                    p_endpoint_id                      => p_endpoint_id
                                  , p_artifact_type_code               => l_done(i)
                                  , p_target_profile_id                => p_target_profile_id
                                ));
    end loop;

    logger.log('END', l_scope, null, l_params);

    return l_bundle;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end build_apx_bundle;








  -- ===========================================================================
  -- FUNCTION: bundle_file_name
  -- ===========================================================================
  /**
   * Download file name for the .apx bundle of an endpoint
   * (<endpoint-name>.apx, kebab-case).
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_codegen_api.bundle_file_name(p_endpoint_id => 1));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint
   * @return varchar2 File name
   */
  function bundle_file_name(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'bundle_file_name';
    l_params logger.tab_param;
    l_name   arw_endpoints.name%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    begin
      select e.name                                        as name
        into l_name
        from arw_endpoints e
       where e.endpoint_id = p_endpoint_id;
    exception
      when no_data_found then
        raise_application_error(gc_err_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end;

    logger.log('END', l_scope, null, l_params);

    return arw_render_utils.to_static_id(l_name) || '.apx';
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end bundle_file_name;








  -- ===========================================================================
  -- FUNCTION: demo_secret_lines (private)
  -- ===========================================================================
  /**
   * Install script of the demo app's supporting objects: stores the
   * request's auth values in the Web Credential, so the app works right
   * after install. Values come from the Auth tab, with {{variables}}
   * resolved against the same environment as the base URL (the
   * collection's first active one).
   *
   * @example N/A -- private package-body unit; exercised through build_demo_app_sql.
   *
   * @issue   PHASE2-simplified (demo app download)
   *
   * @author  Angel Flores (Developer)
   * @created November 3, 2026
   *
   * @param p_ctx Generation context with a simple-auth credential
   * @return apex_t_varchar2 Script lines
   */
  function demo_secret_lines(
      p_ctx                                     in t_ctx
  )
  return apex_t_varchar2
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'demo_secret_lines';
    l_params         logger.tab_param;
    l_lines          apex_t_varchar2 := apex_t_varchar2();
    l_username       arw_endpoints.auth_username%type;
    l_password       arw_endpoints.auth_password%type;
    l_token          arw_endpoints.auth_token%type;
    l_key_value      arw_endpoints.auth_key_value%type;
    l_environment_id arw_environments.environment_id%type;
    l_name_arg       varchar2(30 char);
    l_secret_arg     varchar2(30 char);
    l_name           varchar2(4000 char);
    l_secret         varchar2(4000 char);

    function resolved(
        p_text                                  in varchar2
    )
    return varchar2
    is
      l_text varchar2(4000 char) := p_text;
    begin
      for l_rec in (
        select v.var_name                                  as var_name
             , v.var_value                                 as var_value
          from arw_env_variables v
         where v.environment_id = l_environment_id
           and v.active_yn = 'Y'
      )
      loop
        l_text := replace(l_text, '{{' || l_rec.var_name || '}}', l_rec.var_value);
      end loop;

      if regexp_like(l_text, '\{\{[^}]+\}\}') then
        raise_application_error(gc_err_invalid_input, 'The auth value ' || regexp_substr(l_text, '\{\{[^}]+\}\}')
                                                      || ' is not defined in the environment.');
      end if;

      return l_text;
    end resolved;
  begin
    logger.append_param(l_params, 'endpoint_id', p_ctx.endpoint_id);
    logger.log('START', l_scope, null, l_params);

    select e.auth_username                                 as auth_username
         , e.auth_password                                 as auth_password
         , e.auth_token                                    as auth_token
         , e.auth_key_value                                as auth_key_value
      into l_username
         , l_password
         , l_token
         , l_key_value
      from arw_endpoints e
     where e.endpoint_id = p_ctx.endpoint_id;

    begin
      select env.environment_id                            as environment_id
        into l_environment_id
        from arw_environments env
        join arw_endpoints    e on e.collection_id = env.collection_id
       where e.endpoint_id = p_ctx.endpoint_id
         and env.active_yn = 'Y'
       order by env.environment_id
       fetch first 1 row only;
    exception
      when no_data_found then
        l_environment_id := null;
    end;

    case p_ctx.auth_type_code
      when 'basic' then
        l_name_arg   := 'p_username';
        l_secret_arg := 'p_password';
        l_name       := resolved(l_username);
        l_secret     := resolved(l_password);
      when 'bearer' then
        l_name       := 'Authorization';
        l_secret     := 'Bearer ' || resolved(l_token);
      else
        l_name       := resolved(p_ctx.api_key_name);
        l_secret     := resolved(l_key_value);
    end case;
    l_name_arg   := nvl(l_name_arg, 'p_client_id');
    l_secret_arg := nvl(l_secret_arg, 'p_client_secret');

    add(l_lines, '-- Demo only: the secret below was copied from ARW in plain text.');
    add(l_lines, 'begin');
    add(l_lines, '  apex_credential.set_persistent_credentials(');
    add(l_lines, '      p_credential_static_id => ' || arw_render_utils.quote_literal(p_ctx.credential_static_id));
    add(l_lines, '    , ' || rpad(l_name_arg, 22) || ' => ' || arw_render_utils.quote_literal(l_name));
    add(l_lines, '    , ' || rpad(l_secret_arg, 22) || ' => ' || arw_render_utils.quote_literal(l_secret));
    add(l_lines, '  );');
    add(l_lines, 'end;');
    add(l_lines, '/');

    logger.log('END', l_scope, null, l_params);

    return l_lines;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end demo_secret_lines;








  -- ===========================================================================
  -- FUNCTION: build_demo_app_sql
  -- ===========================================================================
  /**
   * Builds a ready-to-import APEX application export (.sql, the classic
   * export format) for a GET endpoint: a public page with an Interactive
   * Report on a REST Data Source for the request, with its Remote Server
   * and, when the request has auth, its Web Credential. Import it in App
   * Builder (Import > Application) or run it with SQLcl.
   *
   * The file follows the export of the same app written in APEXlang and
   * imported with SQLcl (APEX 26.1). App Builder imports a .sql export
   * without ORDS, unlike an APEXlang zip.
   *
   * Remote Server and Web Credential are workspace components: when the
   * current workspace already has one with the same static id, its id and
   * settings are reused, so the import updates nothing.
   *
   * With p_include_secrets_yn = 'Y' the app also carries a supporting
   * objects install script that stores the request's auth values in the
   * Web Credential; otherwise the developer sets them in Shared Components
   * > Web Credentials after install.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_sql clob;
   * begin
   *   l_sql := arw_codegen_api.build_demo_app_sql(
   *       p_endpoint_id                        => 64
   *     , p_include_secrets_yn                 => 'N'
   *   );
   *   dbms_output.put_line(dbms_lob.getlength(l_sql) || ' characters');
   * end;
   * /
   *
   * @issue   PHASE2-simplified (demo app download)
   *
   * @author  Angel Flores (Developer)
   * @created November 3, 2026
   *
   * @param p_endpoint_id Endpoint (GET, with a data profile)
   * @param p_include_secrets_yn Y = install the auth values with the app
   * @return clob Application export script
   */
  function build_demo_app_sql(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_include_secrets_yn                      in varchar2 default 'N'
  )
  return clob
  is
    l_scope            logger_logs.scope%type := gc_scope_prefix || 'build_demo_app_sql';
    l_params           logger.tab_param;
    l_ctx              t_ctx;
    l_lines            apex_t_varchar2 := apex_t_varchar2();
    l_static_ids       apex_t_varchar2 := apex_t_varchar2();
    l_secret_lines     apex_t_varchar2;
    l_version_no       apex_release.version_no%type;
    l_api_date         apex_release.api_compatibility%type;
    l_workspace_id     apex_workspace_schemas.workspace_id%type;
    l_workspace        apex_workspace_schemas.workspace_name%type;
    l_owner            varchar2(128 char) := sys_context('userenv', 'current_schema');
    l_app_id           pls_integer;
    l_base_id          number;
    l_next_id          pls_integer := 0;
    l_title            varchar2(400 char);
    l_rds_static_id    varchar2(255 char);
    l_host             varchar2(1000 char);
    l_server_id        number;
    l_server_name      varchar2(400 char);
    l_server_static_id varchar2(255 char);
    l_server_url       varchar2(1000 char);
    l_has_credential   boolean;
    l_cred_id          number;
    l_cred_name        varchar2(400 char);
    l_cred_type        varchar2(100 char);
    l_cred_comment     varchar2(4000 char);
    l_module_id        number;
    l_profile_id       number;
    l_auth_id          number;
    l_menu_id          number;
    l_bar_id           number;
    l_install_id       number;
    l_worksheet_id     number;
    l_prefix           varchar2(4000 char);
    l_pattern          varchar2(4000 char);
    l_n                pls_integer := 0;
    l_col_type         varchar2(30 char);
    l_report_columns   varchar2(4000 char);

    function new_id
    return number
    is
    begin
      l_next_id := l_next_id + 1;
      return l_base_id + l_next_id;
    end new_id;

    function imp_id(
        p_id                                    in number
    )
    return varchar2
    is
    begin
      return 'wwv_flow_imp.id(' || to_char(p_id, 'fm99999999999999999999') || ')';
    end imp_id;

    function lit(
        p_text                                  in varchar2
    )
    return varchar2
    is
    begin
      return arw_render_utils.quote_literal(p_text);
    end lit;

    function unique_static_id(
        p_base                                  in varchar2
    )
    return varchar2
    is
      l_candidate varchar2(255 char) := p_base;
      l_suffix    pls_integer := 1;
    begin
      while l_candidate member of l_static_ids loop
        l_suffix    := l_suffix + 1;
        l_candidate := p_base || '-' || l_suffix;
      end loop;
      l_static_ids.extend;
      l_static_ids(l_static_ids.count) := l_candidate;
      return l_candidate;
    end unique_static_id;

    -- IR column identifiers: A .. Z, AA .. ZZ
    function column_identifier(
        p_position                              in pls_integer
    )
    return varchar2
    is
    begin
      return case
               when p_position <= 26 then chr(64 + p_position)
               else chr(64 + trunc((p_position - 1) / 26)) || chr(65 + mod(p_position - 1, 26))
             end;
    end column_identifier;

    procedure open_block(
        p_prompt                                in varchar2
    )
    is
    begin
      add(l_lines, 'prompt --' || p_prompt);
      add(l_lines, 'begin');
    end open_block;

    procedure close_block
    is
    begin
      add(l_lines, 'end;');
      add(l_lines, '/');
    end close_block;

    procedure null_block(
        p_prompt                                in varchar2
    )
    is
    begin
      open_block(p_prompt);
      add(l_lines, 'null;');
      close_block;
    end null_block;

    -- Data profile columns and report columns: top-level, non-array only
    function is_report_column(
        p_column                                in t_column_rec
    )
    return boolean
    is
    begin
      return p_column.parent_column_id is null and nvl(p_column.has_children_yn, 'N') = 'N';
    end is_report_column;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.append_param(l_params, 'p_include_secrets_yn', p_include_secrets_yn);
    logger.log('START', l_scope, null, l_params);

    l_ctx := load_context(p_endpoint_id, null);

    if l_ctx.http_method != 'GET' then
      raise_application_error(gc_err_invalid_input, 'The demo app supports GET requests only.');
    end if;

    if l_ctx.data_profile_id is null then
      raise_application_error(gc_err_invalid_input, 'Send the request once (with a JSON response) so ARW can build the data profile.');
    end if;

    select r.version_no                                    as version_no
         , r.api_compatibility                             as api_compatibility
      into l_version_no
         , l_api_date
      from apex_release r;

    select s.workspace_id                                  as workspace_id
         , s.workspace_name                                as workspace_name
      into l_workspace_id
         , l_workspace
      from apex_workspace_schemas s
     where s.schema = l_owner
     order by s.workspace_id
     fetch first 1 row only;

    l_title          := l_ctx.endpoint_name;
    l_app_id         := 100000 + p_endpoint_id;
    l_base_id        := trunc(dbms_random.value(1e12, 9e12)) * 1000;
    l_has_credential := has_credential(l_ctx);
    l_rds_static_id  := arw_render_utils.to_static_id(l_ctx.endpoint_name);

    -- ---------------------------------------------------------------------------
    -- Workspace components: reuse the workspace's own when the static id exists
    -- ---------------------------------------------------------------------------
    l_host             := nvl(regexp_substr(l_ctx.base_url, '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)', 1, 1, null, 1), 'rest-server');
    l_server_static_id := arw_render_utils.to_static_id(l_host);
    begin
      select rs.remote_server_id                           as remote_server_id
           , rs.remote_server_name                         as remote_server_name
           , rs.base_url                                   as base_url
        into l_server_id
           , l_server_name
           , l_server_url
        from apex_workspace_remote_servers rs
       where rs.workspace = l_workspace
         and rs.remote_server_static_id = l_server_static_id;
    exception
      when no_data_found then
        l_server_id   := new_id;
        l_server_name := l_host;
        l_server_url  := l_ctx.base_url || '/';
    end;

    if l_has_credential then
      begin
        select c.credential_id                             as credential_id
             , c.name                                      as name
             , c.credential_type_code                      as credential_type_code
             , c.comments                                  as comments
          into l_cred_id
             , l_cred_name
             , l_cred_type
             , l_cred_comment
          from apex_workspace_credentials c
         where c.workspace = l_workspace
           and c.static_id = l_ctx.credential_static_id;
      exception
        when no_data_found then
          l_cred_id      := new_id;
          l_cred_name    := nvl(l_ctx.credential_name, l_ctx.credential_static_id);
          l_cred_comment := 'Created by an ARW demo app. Set the secret in Shared Components > Web Credentials.';
          l_cred_type    := case l_ctx.auth_type_code
                              when 'basic'                     then 'BASIC'
                              when 'bearer'                    then 'HTTP_HEADER'
                              when 'api_key_header'            then 'HTTP_HEADER'
                              when 'api_key_query'             then 'HTTP_QUERY_STRING'
                              when 'oauth2_client_credentials' then 'OAUTH2_CLIENT_CREDENTIALS'
                              when 'oci'                       then 'OCI'
                            end;
          if l_cred_type is null then
            raise_application_error(gc_err_invalid_input, 'The demo app does not support auth type ' || l_ctx.auth_type_code
                                                          || ' unless its Web Credential exists in this workspace.');
          end if;
      end;
    end if;

    l_module_id  := new_id;
    l_profile_id := new_id;
    l_auth_id    := new_id;
    l_menu_id    := new_id;
    l_bar_id     := new_id;

    -- ---------------------------------------------------------------------------
    -- Environment and application
    -- ---------------------------------------------------------------------------
    add(l_lines, 'prompt --application/set_environment');
    add(l_lines, 'set define off verify off feedback off');
    add(l_lines, 'whenever sqlerror exit sql.sqlcode rollback');
    add(l_lines, '--------------------------------------------------------------------------------');
    add(l_lines, '--');
    add(l_lines, '-- Oracle APEX export file, generated by ARW (APEX REST Workbench) for');
    add(l_lines, '-- ' || replace(l_ctx.http_method || ' ' || l_ctx.url_path, chr(10)) || ' (' || l_ctx.endpoint_name || ').');
    add(l_lines, '--');
    add(l_lines, '-- Import it in App Builder (Import > Application), or run it with SQLcl');
    add(l_lines, '-- connected as the workspace schema.');
    add(l_lines, '--');
    add(l_lines, '--------------------------------------------------------------------------------');
    add(l_lines, 'begin');
    add(l_lines, 'wwv_flow_imp.import_begin (');
    add(l_lines, ' p_version_yyyy_mm_dd=>' || lit(l_api_date));
    add(l_lines, ',p_release=>' || lit(l_version_no));
    add(l_lines, ',p_default_workspace_id=>' || to_char(l_workspace_id, 'fm99999999999999999999'));
    add(l_lines, ',p_default_application_id=>' || l_app_id);
    add(l_lines, ',p_default_id_offset=>0');
    add(l_lines, ',p_default_owner=>' || lit(l_owner));
    add(l_lines, ');');
    add(l_lines, 'end;');
    add(l_lines, '/');
    add(l_lines, ' ');
    add(l_lines, 'prompt APPLICATION ' || l_app_id || ' - ' || l_title || ' - ARW demo');

    open_block('application/delete_application');
    add(l_lines, 'wwv_flow_imp.remove_flow(wwv_flow.g_flow_id);');
    close_block;

    open_block('application/create_application');
    add(l_lines, 'wwv_imp_workspace.create_flow(');
    add(l_lines, ' p_id=>wwv_flow.g_flow_id');
    add(l_lines, ',p_owner=>nvl(wwv_flow_application_install.get_schema,' || lit(l_owner) || ')');
    add(l_lines, ',p_name=>nvl(wwv_flow_application_install.get_application_name,' || lit(substr(l_title || ' - ARW demo', 1, 255)) || ')');
    add(l_lines, ',p_alias=>nvl(wwv_flow_application_install.get_application_alias,' || lit(upper(l_rds_static_id) || '-DEMO') || ')');
    add(l_lines, ',p_page_view_logging=>''YES''');
    add(l_lines, ',p_page_protection_enabled_y_n=>''Y''');
    add(l_lines, ',p_bookmark_checksum_function=>''SH512''');
    add(l_lines, ',p_compatibility_mode=>' || lit(regexp_substr(l_version_no, '^\d+\.\d+')));
    add(l_lines, ',p_flow_language=>''en''');
    add(l_lines, ',p_flow_language_derived_from=>''FLOW_PRIMARY_LANGUAGE''');
    add(l_lines, ',p_flow_image_prefix=>nvl(wwv_flow_application_install.get_image_prefix,'''')');
    add(l_lines, ',p_authentication_id=>' || imp_id(l_auth_id));
    add(l_lines, ',p_application_tab_set=>0');
    add(l_lines, ',p_logo_type=>''T''');
    add(l_lines, ',p_logo_text=>' || lit(l_title));
    add(l_lines, ',p_proxy_server=>nvl(wwv_flow_application_install.get_proxy,'''')');
    add(l_lines, ',p_no_proxy_domains=>nvl(wwv_flow_application_install.get_no_proxy_domains,'''')');
    add(l_lines, ',p_flow_version=>''Release 1.0''');
    add(l_lines, ',p_flow_status=>''AVAILABLE_W_EDIT_LINK''');
    add(l_lines, ',p_browser_cache=>''N''');
    add(l_lines, ',p_browser_frame=>''D''');
    add(l_lines, ',p_authorize_batch_job=>''N''');
    add(l_lines, ',p_rejoin_existing_sessions=>''N''');
    add(l_lines, ',p_csv_encoding=>''Y''');
    add(l_lines, ',p_file_prefix=>nvl(wwv_flow_application_install.get_static_app_file_prefix,'''')');
    add(l_lines, ',p_print_server_type=>''NATIVE''');
    add(l_lines, ',p_file_storage=>''DB''');
    add(l_lines, ',p_is_pwa=>''N''');
    add(l_lines, ',p_theme_id=>42');
    add(l_lines, ',p_home_url=>''f?p=&APP_ID.:1:&SESSION.::&DEBUG.''');
    add(l_lines, ',p_theme_style_by_user_pref=>false');
    add(l_lines, ',p_global_page_id=>0');
    add(l_lines, ',p_navigation_list_id=>' || imp_id(l_menu_id));
    add(l_lines, ',p_navigation_list_position=>''SIDE''');
    add(l_lines, ',p_navigation_list_template_id=>2469215554099805162');
    add(l_lines, ',p_nav_list_template_options=>''#DEFAULT#''');
    add(l_lines, ',p_nav_bar_type=>''LIST''');
    add(l_lines, ',p_nav_bar_list_id=>' || imp_id(l_bar_id));
    add(l_lines, ',p_nav_bar_list_template_id=>2849019392706229583');
    add(l_lines, ',p_nav_bar_template_options=>''#DEFAULT#''');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Web Credential and Remote Server (workspace components)
    -- ---------------------------------------------------------------------------
    if l_has_credential then
      open_block('workspace/credentials/' || lower(arw_render_utils.to_identifier(l_ctx.credential_static_id)));
      add(l_lines, 'wwv_imp_workspace.create_credential(');
      add(l_lines, ' p_id=>' || to_char(l_cred_id, 'fm99999999999999999999'));
      add(l_lines, ',p_name=>' || lit(l_cred_name));
      add(l_lines, ',p_static_id=>' || lit(l_ctx.credential_static_id));
      add(l_lines, ',p_authentication_type=>' || lit(l_cred_type));
      add(l_lines, ',p_prompt_on_install=>false');
      if l_cred_comment is not null then
        add(l_lines, ',p_credential_comment=>' || lit(l_cred_comment));
      end if;
      add(l_lines, ');');
      close_block;
    end if;

    open_block('workspace/remote_servers/' || replace(l_server_static_id, '-', '_'));
    add(l_lines, 'wwv_imp_workspace.create_remote_server(');
    add(l_lines, ' p_id=>' || to_char(l_server_id, 'fm99999999999999999999'));
    add(l_lines, ',p_name=>' || lit(l_server_name));
    add(l_lines, ',p_static_id=>' || lit(l_server_static_id));
    add(l_lines, ',p_base_url=>nvl(wwv_flow_application_install.get_remote_server_base_url(' || lit(l_server_static_id) || '),' || lit(l_server_url) || ')');
    add(l_lines, ',p_https_host=>nvl(wwv_flow_application_install.get_remote_server_https_host(' || lit(l_server_static_id) || '),'''')');
    add(l_lines, ',p_server_type=>''WEB_SERVICE''');
    add(l_lines, ',p_ords_timezone=>nvl(wwv_flow_application_install.get_remote_server_ords_tz(' || lit(l_server_static_id) || '),'''')');
    add(l_lines, ',p_prompt_on_install=>false');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- REST Data Source: module, parameters, data profile, operation
    -- ---------------------------------------------------------------------------
    rds_url_parts(
        p_ctx                                   => l_ctx
      , o_prefix                                => l_prefix
      , o_pattern                               => l_pattern
    );

    open_block('application/shared_components/web_sources/' || replace(l_rds_static_id, '-', '_'));
    add(l_lines, 'wwv_flow_imp_shared.create_web_source_module(');
    add(l_lines, ' p_id=>' || imp_id(l_module_id));
    add(l_lines, ',p_name=>' || lit(l_ctx.endpoint_name));
    add(l_lines, ',p_static_id=>' || lit(l_rds_static_id));
    add(l_lines, ',p_web_source_type=>''NATIVE_HTTP''');
    add(l_lines, ',p_data_profile_id=>' || imp_id(l_profile_id));
    add(l_lines, ',p_remote_server_id=>' || to_char(l_server_id, 'fm99999999999999999999'));
    add(l_lines, ',p_url_path_prefix=>' || lit(l_prefix));
    if l_has_credential then
      add(l_lines, ',p_credential_id=>' || to_char(l_cred_id, 'fm99999999999999999999'));
    end if;
    add(l_lines, ',p_timeout=>' || nvl(l_ctx.timeout_secs, 30));
    add(l_lines, ');');

    for i in 1 .. l_ctx.params.count loop
      continue when l_ctx.params(i).kind_code = 'form';

      add(l_lines, 'wwv_flow_imp_shared.create_web_source_param(');
      add(l_lines, ' p_id=>' || imp_id(new_id));
      add(l_lines, ',p_web_src_module_id=>' || imp_id(l_module_id));
      add(l_lines, ',p_name=>' || lit(l_ctx.params(i).param_name));
      add(l_lines, ',p_static_id=>' || lit(unique_static_id(arw_render_utils.to_static_id(l_ctx.params(i).param_name))));
      add(l_lines, ',p_param_type=>' || case l_ctx.params(i).kind_code when 'path' then '''URL_PATTERN''' else '''QUERY_STRING''' end);
      add(l_lines, ',p_data_type=>' || case l_ctx.params(i).plsql_type
                                         when 'number'  then '''NUMBER'''
                                         when 'date'    then '''DATE'''
                                         when 'boolean' then '''BOOLEAN'''
                                         else '''VARCHAR2'''
                                       end);
      add(l_lines, ',p_is_required=>' || case when l_ctx.params(i).is_required_yn = 'Y' then 'true' else 'false' end);
      if l_ctx.params(i).param_value is not null then
        add(l_lines, ',p_default_value_type=>''STATIC''');
        add(l_lines, ',p_value=>' || lit(l_ctx.params(i).param_value));
      end if;
      add(l_lines, ');');
    end loop;

    -- Sensitive headers belong in the Web Credential: left out, as in the .apx
    for i in 1 .. l_ctx.headers.count loop
      continue when l_ctx.headers(i).is_sensitive_yn = 'Y';

      add(l_lines, 'wwv_flow_imp_shared.create_web_source_param(');
      add(l_lines, ' p_id=>' || imp_id(new_id));
      add(l_lines, ',p_web_src_module_id=>' || imp_id(l_module_id));
      add(l_lines, ',p_name=>' || lit(l_ctx.headers(i).header_name));
      add(l_lines, ',p_static_id=>' || lit(unique_static_id(arw_render_utils.to_static_id(l_ctx.headers(i).header_name))));
      add(l_lines, ',p_param_type=>''HEADER''');
      add(l_lines, ',p_data_type=>''VARCHAR2''');
      add(l_lines, ',p_default_value_type=>''STATIC''');
      add(l_lines, ',p_value=>' || lit(l_ctx.headers(i).header_value));
      add(l_lines, ',p_is_static=>true');
      add(l_lines, ');');
    end loop;

    add(l_lines, 'wwv_flow_imp_shared.create_data_profile(');
    add(l_lines, ' p_id=>' || imp_id(l_profile_id));
    add(l_lines, ',p_name=>' || lit(nvl(l_ctx.profile_name, upper(arw_render_utils.to_identifier(l_ctx.endpoint_name)))));
    add(l_lines, ',p_format=>''JSON''');
    if l_ctx.row_selector is not null then
      add(l_lines, ',p_row_selector=>' || lit(l_ctx.row_selector));
    end if;
    add(l_lines, ',p_use_raw_json_selectors=>false');
    add(l_lines, ',p_is_single_row=>false');
    add(l_lines, ');');

    l_static_ids := apex_t_varchar2();
    for i in 1 .. l_ctx.profile_columns.count loop
      continue when not is_report_column(l_ctx.profile_columns(i));

      l_n := l_n + 1;
      l_col_type := case
                      when l_ctx.profile_columns(i).is_json_yn = 'Y' then 'CLOB'
                      else case l_ctx.profile_columns(i).data_type_code
                             when 'number'                   then 'NUMBER'
                             when 'boolean'                  then 'BOOLEAN'
                             when 'date'                     then 'DATE'
                             when 'timestamp_with_time_zone' then 'TIMESTAMP WITH TIME ZONE'
                             when 'clob'                     then 'CLOB'
                             else 'VARCHAR2'
                           end
                    end;

      add(l_lines, 'wwv_flow_imp_shared.create_data_profile_col(');
      add(l_lines, ' p_id=>' || imp_id(new_id));
      add(l_lines, ',p_data_profile_id=>' || imp_id(l_profile_id));
      add(l_lines, ',p_name=>' || lit(upper(l_ctx.profile_columns(i).ident)));
      add(l_lines, ',p_static_id=>' || lit(unique_static_id(arw_render_utils.to_static_id(l_ctx.profile_columns(i).ident))));
      add(l_lines, ',p_sequence=>' || l_n);
      if l_ctx.profile_columns(i).is_primary_key_yn = 'Y' then
        add(l_lines, ',p_is_primary_key=>true');
      end if;
      add(l_lines, ',p_column_type=>''DATA''');
      add(l_lines, ',p_data_type=>' || lit(l_col_type));
      if l_col_type = 'VARCHAR2' then
        add(l_lines, ',p_max_length=>' || least(greatest(nvl(l_ctx.profile_columns(i).max_observed_length, 4000), 1), 4000));
      end if;
      if l_ctx.profile_columns(i).format_mask is not null and l_col_type in ('DATE', 'TIMESTAMP WITH TIME ZONE') then
        add(l_lines, ',p_format_mask=>' || lit(l_ctx.profile_columns(i).format_mask));
      end if;
      add(l_lines, ',p_selector=>' || lit(l_ctx.profile_columns(i).path_expression));
      add(l_lines, ');');
    end loop;

    add(l_lines, 'wwv_flow_imp_shared.create_web_source_operation(');
    add(l_lines, ' p_id=>' || imp_id(new_id));
    add(l_lines, ',p_web_src_module_id=>' || imp_id(l_module_id));
    add(l_lines, ',p_static_id=>''get''');
    add(l_lines, ',p_operation=>''GET''');
    add(l_lines, ',p_database_operation=>''FETCH_COLLECTION''');
    add(l_lines, ',p_url_pattern=>' || lit(l_pattern));
    add(l_lines, ',p_force_error_for_http_404=>false');
    add(l_lines, ',p_allow_fetch_all_rows=>false');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Navigation: menu with one entry, empty navigation bar
    -- ---------------------------------------------------------------------------
    open_block('application/shared_components/navigation/lists/navigation_bar');
    add(l_lines, 'wwv_flow_imp_shared.create_list(');
    add(l_lines, ' p_id=>' || imp_id(l_bar_id));
    add(l_lines, ',p_name=>''Navigation Bar''');
    add(l_lines, ',p_static_id=>''navigation-bar''');
    add(l_lines, ');');
    close_block;

    open_block('application/shared_components/navigation/lists/navigation_menu');
    add(l_lines, 'wwv_flow_imp_shared.create_list(');
    add(l_lines, ' p_id=>' || imp_id(l_menu_id));
    add(l_lines, ',p_name=>''Navigation Menu''');
    add(l_lines, ',p_static_id=>''navigation-menu''');
    add(l_lines, ');');
    add(l_lines, 'wwv_flow_imp_shared.create_list_item(');
    add(l_lines, ' p_id=>' || imp_id(new_id));
    add(l_lines, ',p_list_item_display_sequence=>10');
    add(l_lines, ',p_list_item_link_text=>' || lit(l_title));
    add(l_lines, ',p_static_id=>''home''');
    add(l_lines, ',p_list_item_link_target=>''f?p=&APP_ID.:1:&SESSION.::&DEBUG.''');
    add(l_lines, ',p_list_item_icon=>''fa-table''');
    add(l_lines, ',p_list_item_current_type=>''TARGET_PAGE''');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Universal Theme 42 (subscribed to the instance master theme)
    -- ---------------------------------------------------------------------------
    open_block('application/shared_components/user_interface/themes');
    add(l_lines, 'wwv_flow_imp_shared.create_theme(');
    add(l_lines, ' p_id=>' || imp_id(new_id));
    add(l_lines, ',p_theme_id=>42');
    add(l_lines, ',p_static_id=>''universal-theme''');
    add(l_lines, ',p_theme_name=>''Universal Theme''');
    add(l_lines, ',p_theme_internal_name=>''UNIVERSAL_THEME''');
    add(l_lines, ',p_version_identifier=>''26.1''');
    add(l_lines, ',p_navigation_type=>''L''');
    add(l_lines, ',p_nav_bar_type=>''LIST''');
    add(l_lines, ',p_is_locked=>false');
    add(l_lines, ',p_current_theme_style_id=>2243014446517417');
    add(l_lines, ',p_default_page_template=>4073832297226169690');
    add(l_lines, ',p_default_dialog_template=>2101883943284197310');
    add(l_lines, ',p_error_template=>2102634289808461002');
    add(l_lines, ',p_printer_friendly_template=>4073832297226169690');
    add(l_lines, ',p_login_template=>2102634289808461002');
    add(l_lines, ',p_default_button_template=>4073839297780169708');
    add(l_lines, ',p_default_region_template=>4073835273271169698');
    add(l_lines, ',p_default_chart_template=>4073835273271169698');
    add(l_lines, ',p_default_form_template=>4073835273271169698');
    add(l_lines, ',p_default_reportr_template=>4073835273271169698');
    add(l_lines, ',p_default_wizard_template=>4073835273271169698');
    add(l_lines, ',p_default_menur_template=>2532939663579242476');
    add(l_lines, ',p_default_listr_template=>4073835273271169698');
    add(l_lines, ',p_default_irr_template=>2102002977963900996');
    add(l_lines, ',p_default_report_template=>2540130677583398057');
    add(l_lines, ',p_default_label_template=>1610598304472262251');
    add(l_lines, ',p_default_menu_template=>4073839682315169711');
    add(l_lines, ',p_default_list_template=>4073837480889169704');
    add(l_lines, ',p_default_top_nav_list_temp=>2528231041045349458');
    add(l_lines, ',p_default_side_nav_list_temp=>2469215554099805162');
    add(l_lines, ',p_default_nav_list_position=>''SIDE''');
    add(l_lines, ',p_default_dialogbtnr_template=>2127905476394690047');
    add(l_lines, ',p_default_dialogr_template=>4502917002193490937');
    add(l_lines, ',p_default_option_label=>1610598304472262251');
    add(l_lines, ',p_default_required_label=>1610598484065263269');
    add(l_lines, ',p_default_navbar_list_template=>2849019392706229583');
    add(l_lines, ',p_file_prefix=>nvl(wwv_flow_application_install.get_static_theme_file_prefix(42),''#APEX_FILES#themes/theme_42/26.1/'')');
    add(l_lines, ',p_icon_library=>''FONTAPEX''');
    add(l_lines, ',p_javascript_file_urls=>wwv_flow_string.join(wwv_flow_t_varchar2(');
    add(l_lines, '''#APEX_FILES#libraries/apex/#MIN_DIRECTORY#widget.stickyWidget#MIN#.js?v=#APEX_VERSION#'',');
    add(l_lines, '''#THEME_FILES#js/theme42#MIN#.js?v=#APEX_VERSION#''))');
    add(l_lines, ',p_css_file_urls=>''#THEME_FILES#css/Core#MIN#.css?v=#APEX_VERSION#''');
    add(l_lines, ',p_reference_id=>wwv_imp_util.get_subscription_id(4073840274158169736,2000,''universal-theme'',8842.261)');
    add(l_lines, ',p_version_scn_master=>''SH256:WOPVC8vP1TPWUxczh2dJ4mCZcNGSTzA1cn8DjR2oQjY''');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Authentication: none, page 1 is public
    -- ---------------------------------------------------------------------------
    open_block('application/shared_components/security/authentications/no_authentication');
    add(l_lines, 'wwv_flow_imp_shared.create_authentication(');
    add(l_lines, ' p_id=>' || imp_id(l_auth_id));
    add(l_lines, ',p_name=>''No Authentication''');
    add(l_lines, ',p_static_id=>''no-authentication''');
    add(l_lines, ',p_scheme_type=>''NATIVE_DAD''');
    add(l_lines, ',p_use_secure_cookie_yn=>''N''');
    add(l_lines, ',p_ras_mode=>0');
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Pages: global page and page 1 with the Interactive Report
    -- ---------------------------------------------------------------------------
    open_block('application/pages/page_00000');
    add(l_lines, 'wwv_flow_imp_page.create_page(');
    add(l_lines, ' p_id=>0');
    add(l_lines, ',p_name=>''Global Page''');
    add(l_lines, ',p_autocomplete_on_off=>''OFF''');
    add(l_lines, ',p_protection_level=>''D''');
    add(l_lines, ');');
    close_block;

    open_block('application/pages/page_00001');
    add(l_lines, 'wwv_flow_imp_page.create_page(');
    add(l_lines, ' p_id=>1');
    add(l_lines, ',p_name=>' || lit(l_title));
    add(l_lines, ',p_alias=>''HOME''');
    add(l_lines, ',p_step_title=>' || lit(l_title));
    add(l_lines, ',p_first_item=>''AUTO_FIRST_ITEM''');
    add(l_lines, ',p_autocomplete_on_off=>''ON''');
    add(l_lines, ',p_step_template=>4073832297226169690');
    add(l_lines, ',p_page_template_options=>''#DEFAULT#''');
    add(l_lines, ',p_page_is_public_y_n=>''Y''');
    add(l_lines, ');');
    add(l_lines, 'wwv_flow_imp_page.create_page_plug(');
    add(l_lines, ' p_id=>' || imp_id(new_id));
    add(l_lines, ',p_plug_name=>' || lit(l_title));
    add(l_lines, ',p_static_id=>' || lit(l_rds_static_id || '-report'));
    add(l_lines, ',p_region_template_options=>''#DEFAULT#''');
    add(l_lines, ',p_plug_template=>2102002977963900996');
    add(l_lines, ',p_plug_display_sequence=>10');
    add(l_lines, ',p_plug_item_display_point=>''ABOVE''');
    add(l_lines, ',p_location=>''WEB_SOURCE''');
    add(l_lines, ',p_web_src_module_id=>' || imp_id(l_module_id));
    add(l_lines, ',p_plug_source_type=>''NATIVE_IR''');
    add(l_lines, ');');
    l_worksheet_id := new_id;
    add(l_lines, 'wwv_flow_imp_page.create_worksheet(');
    add(l_lines, ' p_id=>' || imp_id(l_worksheet_id));
    add(l_lines, ',p_report_list_mode=>''TABS''');
    add(l_lines, ',p_lazy_loading=>false');
    add(l_lines, ',p_show_detail_link=>''N''');
    add(l_lines, ',p_show_notify=>''Y''');
    add(l_lines, ',p_download_formats=>''CSV:HTML:XLSX:PDF''');
    add(l_lines, ',p_enable_mail_download=>''Y''');
    add(l_lines, ',p_internal_uid=>' || to_char(l_worksheet_id, 'fm99999999999999999999'));
    add(l_lines, ');');

    l_n := 0;
    for i in 1 .. l_ctx.profile_columns.count loop
      continue when not is_report_column(l_ctx.profile_columns(i));

      l_n := l_n + 1;
      if l_n > 1 then
        l_report_columns := l_report_columns || ':';
      end if;
      l_report_columns := l_report_columns || upper(l_ctx.profile_columns(i).ident);

      add(l_lines, 'wwv_flow_imp_page.create_worksheet_column(');
      add(l_lines, ' p_id=>' || imp_id(new_id));
      add(l_lines, ',p_db_column_name=>' || lit(upper(l_ctx.profile_columns(i).ident)));
      add(l_lines, ',p_display_order=>' || l_n * 10);
      add(l_lines, ',p_column_identifier=>' || lit(column_identifier(l_n)));
      add(l_lines, ',p_column_label=>' || lit(initcap(replace(l_ctx.profile_columns(i).ident, '_', ' '))));
      add(l_lines, ',p_column_type=>' || case
                                           when l_ctx.profile_columns(i).is_json_yn = 'Y' then '''CLOB'''
                                           else case l_ctx.profile_columns(i).data_type_code
                                                  when 'number'                   then '''NUMBER'''
                                                  when 'date'                     then '''DATE'''
                                                  when 'timestamp_with_time_zone' then '''TIMESTAMP_TZ'''
                                                  when 'clob'                     then '''CLOB'''
                                                  else '''STRING'''
                                                end
                                         end);
      add(l_lines, ',p_heading_alignment=>''LEFT''');
      add(l_lines, ',p_use_as_row_header=>''N''');
      add(l_lines, ',p_available_clientside=>''N''');
      add(l_lines, ');');
    end loop;

    add(l_lines, 'wwv_flow_imp_page.create_worksheet_rpt(');
    add(l_lines, ' p_id=>' || imp_id(new_id));
    add(l_lines, ',p_application_user=>''APXWS_DEFAULT''');
    add(l_lines, ',p_report_seq=>10');
    add(l_lines, ',p_report_alias=>''primary''');
    add(l_lines, ',p_status=>''PUBLIC''');
    add(l_lines, ',p_is_default=>''Y''');
    add(l_lines, ',p_report_columns=>' || lit(l_report_columns));
    add(l_lines, ');');
    close_block;

    -- ---------------------------------------------------------------------------
    -- Supporting objects: auth values, only for simple auth (Auth tab) -- a
    -- linked APEX Web Credential already holds its own secret
    -- ---------------------------------------------------------------------------
    if p_include_secrets_yn = 'Y' and l_has_credential and l_ctx.credential_id is null then
      l_secret_lines := demo_secret_lines(l_ctx);
      l_install_id   := new_id;

      open_block('application/deployment/definition');
      add(l_lines, 'wwv_flow_imp.g_varchar2_table := wwv_flow_imp.empty_varchar2_table;');
      add(l_lines, 'wwv_flow_imp_shared.create_install(');
      add(l_lines, ' p_id=>' || imp_id(l_install_id));
      add(l_lines, ',p_include_in_export_yn=>''I''');
      add(l_lines, ',p_deinstall_script_clob=>wwv_flow_imp.varchar2_to_clob(wwv_flow_imp.g_varchar2_table)');
      add(l_lines, ');');
      close_block;

      open_block('application/deployment/install/install_set_credential_secret');
      add(l_lines, 'wwv_flow_imp.g_varchar2_table := wwv_flow_imp.empty_varchar2_table;');
      for i in 1 .. l_secret_lines.count loop
        add(l_lines, 'wwv_flow_imp.g_varchar2_table(' || i || ') := ' || lit(l_secret_lines(i))
                     || case when i < l_secret_lines.count then '||wwv_flow.LF' end || ';');
      end loop;
      add(l_lines, 'wwv_flow_imp_shared.create_install_script(');
      add(l_lines, ' p_id=>' || imp_id(new_id));
      add(l_lines, ',p_install_id=>' || imp_id(l_install_id));
      add(l_lines, ',p_name=>''set-credential-secret''');
      add(l_lines, ',p_sequence=>10');
      add(l_lines, ',p_script_type=>''INSTALL''');
      add(l_lines, ',p_script_clob=>wwv_flow_imp.varchar2_to_clob(wwv_flow_imp.g_varchar2_table)');
      add(l_lines, ');');
      close_block;
    else
      null_block('application/deployment/definition');
    end if;

    open_block('application/end_environment');
    add(l_lines, 'wwv_flow_imp.import_end(p_auto_install_sup_obj => nvl(wwv_flow_application_install.get_auto_install_sup_obj, false)');
    add(l_lines, ');');
    add(l_lines, 'commit;');
    close_block;
    add(l_lines, 'set verify on feedback on define on');
    add(l_lines, 'prompt  ...done');

    logger.log('END', l_scope, null, l_params);

    return join_lines(l_lines) || gc_lf;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end build_demo_app_sql;








  -- ===========================================================================
  -- FUNCTION: demo_app_file_name
  -- ===========================================================================
  /**
   * Download file name for the demo app of an endpoint
   * (<endpoint-name>-demo.sql, kebab-case).
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_codegen_api.demo_app_file_name(p_endpoint_id => 64));
   * end;
   * /
   *
   * @issue   PHASE2-simplified (demo app download)
   *
   * @author  Angel Flores (Developer)
   * @created November 3, 2026
   *
   * @param p_endpoint_id Endpoint
   * @return varchar2 File name
   */
  function demo_app_file_name(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'demo_app_file_name';
    l_params logger.tab_param;
  begin
    return regexp_replace(bundle_file_name(p_endpoint_id => p_endpoint_id), '\.apx$', '-demo.sql');
  exception
    when others then
      logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end demo_app_file_name;


end arw_codegen_api;
/
