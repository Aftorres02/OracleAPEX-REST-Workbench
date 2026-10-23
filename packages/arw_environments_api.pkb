-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_environments_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  -- One code for every C1 validation/not-found error (allocation in the
  -- #25 build brief); the message tells the cases apart.
  gc_err_invalid  constant number := -20947;

  -- {{base_url}} is resolved from the environment itself, never from a
  -- variable -- see arw_endpoint_api.display_url.
  gc_reserved_var constant varchar2(30 char) := 'base_url';








  -- ===========================================================================
  -- FUNCTION: normalize_base_url (private)
  -- ===========================================================================
  /**
   * Validates and normalizes a base_url: it must start with http:// or
   * https:// and is returned trimmed and without trailing slashes, since
   * every url_path starts with "/" (avoids "//" in the executed URL).
   *
   * @example
   * -- Private: exercised through the public API. A base_url without a
   * -- scheme fails with ORA-20947.
   * set serveroutput on
   * declare
   *   l_environment_id arw_environments.environment_id%type;
   * begin
   *   l_environment_id := arw_environments_api.create_environment(
   *       p_collection_id                      => 1
   *     , p_name                               => 'qa'
   *     , p_base_url                           => 'api.example.com'
   *   );
   * exception
   *   when others then
   *     dbms_output.put_line(sqlerrm);
   *     rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_base_url Base URL entered by the user
   * @return arw_environments.base_url%type  Trimmed base URL without trailing slashes
   */
  function normalize_base_url(
      p_base_url                                in arw_environments.base_url%type
  )
  return arw_environments.base_url%type
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'normalize_base_url';
    l_params   logger.tab_param;
    l_base_url arw_environments.base_url%type;
  begin
    logger.append_param(l_params, 'p_base_url', p_base_url);
    logger.log('START', l_scope, null, l_params);

    l_base_url := rtrim(trim(p_base_url), '/');

    if not regexp_like(l_base_url, '^https?://[^/[:space:]]+', 'i') then
      raise_application_error(gc_err_invalid, 'Base URL must start with http:// or https:// followed by a host: ' || p_base_url);
    end if;

    logger.append_param(l_params, 'l_base_url', l_base_url);
    logger.log('END', l_scope, null, l_params);

    return l_base_url;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end normalize_base_url;








  -- ===========================================================================
  -- PROCEDURE: validate_environment_name (private)
  -- ===========================================================================
  /**
   * Raises gc_err_invalid when the name is empty or another active
   * environment of the same collection already uses it. The comparison
   * ignores case, so resolve_environment_id never has to choose between
   * "dev" and "Dev".
   *
   * @example
   * -- Private: exercised through the public API. A second "dev" in the
   * -- same collection fails with ORA-20947.
   * set serveroutput on
   * declare
   *   l_environment_id arw_environments.environment_id%type;
   * begin
   *   l_environment_id := arw_environments_api.create_environment(
   *       p_collection_id                      => 1
   *     , p_name                               => 'DEV'
   *     , p_base_url                           => 'https://api.example.com'
   *   );
   * exception
   *   when others then
   *     dbms_output.put_line(sqlerrm);
   *     rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_collection_id Collection the environment belongs to
   * @param p_environment_id Environment being saved; null when it is being created
   * @param p_name Proposed environment name
   */
  procedure validate_environment_name(
      p_collection_id                           in arw_environments.collection_id%type
    , p_environment_id                          in arw_environments.environment_id%type
    , p_name                                    in arw_environments.name%type
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'validate_environment_name';
    l_params      logger.tab_param;
    l_duplicate_n number;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_environment_id', p_environment_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);

    if trim(p_name) is null then
      raise_application_error(gc_err_invalid, 'Environment name is required.');
    end if;

    select count(1)                                        as duplicate_n
      into l_duplicate_n
      from arw_environments v
     where v.collection_id = p_collection_id
       and lower(v.name) = lower(trim(p_name))
       and v.active_yn = 'Y'
       and (p_environment_id is null or v.environment_id != p_environment_id);

    if l_duplicate_n > 0 then
      raise_application_error(gc_err_invalid, 'An environment named "' || trim(p_name) || '" already exists in this collection.');
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end validate_environment_name;








  -- ===========================================================================
  -- FUNCTION: create_environment
  -- ===========================================================================
  /**
   * Creates an environment (name + base_url) in an active collection. When
   * an inactive environment with exactly the same name exists in the
   * collection (uk_environments_name also covers inactive rows), that row
   * is reactivated with the new base_url and its id is returned instead.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_environment_id arw_environments.environment_id%type;
   * begin
   *   l_environment_id := arw_environments_api.create_environment(
   *       p_collection_id                      => 1
   *     , p_name                               => 'qa'
   *     , p_base_url                           => 'https://qa.api.example.com'
   *   );
   *   dbms_output.put_line('environment_id = ' || l_environment_id);
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_collection_id Collection the environment belongs to
   * @param p_name Display name of the environment (e.g. dev, qa, prod)
   * @param p_base_url Base URL (http:// or https://) endpoints resolve against
   * @return arw_environments.environment_id%type  Identifier of the created (or reactivated) environment
   */
  function create_environment(
      p_collection_id                           in arw_environments.collection_id%type
    , p_name                                    in arw_environments.name%type
    , p_base_url                                in arw_environments.base_url%type
  )
  return arw_environments.environment_id%type
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'create_environment';
    l_params         logger.tab_param;
    l_collection_n   number;
    l_base_url       arw_environments.base_url%type;
    l_environment_id arw_environments.environment_id%type;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_base_url', p_base_url);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as collection_n
      into l_collection_n
      from arw_collections c
     where c.collection_id = p_collection_id
       and c.active_yn = 'Y';

    if l_collection_n = 0 then
      raise_application_error(gc_err_invalid, 'Collection not found or inactive: ' || p_collection_id);
    end if;


    -- =========================================================================
    -- Reject a duplicate name and a base_url without http(s)://.
    -- =========================================================================

    validate_environment_name(
        p_collection_id                         => p_collection_id
      , p_environment_id                        => null
      , p_name                                  => p_name
    );
    -- =========================================================================

    l_base_url := normalize_base_url(p_base_url => p_base_url);

    update arw_environments
       set base_url   = l_base_url
         , active_yn  = 'Y'
     where collection_id = p_collection_id
       and name = trim(p_name)
       and active_yn = 'N'
    returning environment_id into l_environment_id;

    if l_environment_id is null then
      insert
        into arw_environments (
             collection_id
           , name
           , base_url
        )
      values (
             p_collection_id
           , trim(p_name)
           , l_base_url
        )
      returning environment_id into l_environment_id;
    end if;

    logger.append_param(l_params, 'l_environment_id', l_environment_id);
    logger.log('END', l_scope, null, l_params);

    return l_environment_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_environment;








  -- ===========================================================================
  -- PROCEDURE: update_environment
  -- ===========================================================================
  /**
   * Renames an active environment and/or changes its base_url.
   *
   * @example
   * begin
   *   arw_environments_api.update_environment(
   *       p_environment_id                     => 1
   *     , p_name                               => 'dev'
   *     , p_base_url                           => 'https://jsonplaceholder.typicode.com'
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_environment_id Environment to update
   * @param p_name Display name of the environment
   * @param p_base_url Base URL (http:// or https://) endpoints resolve against
   */
  procedure update_environment(
      p_environment_id                          in arw_environments.environment_id%type
    , p_name                                    in arw_environments.name%type
    , p_base_url                                in arw_environments.base_url%type
  )
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'update_environment';
    l_params        logger.tab_param;
    l_collection_id arw_environments.collection_id%type;
    l_base_url      arw_environments.base_url%type;
    l_inactive_n    number;
  begin
    logger.append_param(l_params, 'p_environment_id', p_environment_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_base_url', p_base_url);
    logger.log('START', l_scope, null, l_params);

    begin
      select v.collection_id                               as collection_id
        into l_collection_id
        from arw_environments v
       where v.environment_id = p_environment_id
         and v.active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_invalid, 'Environment not found: ' || p_environment_id);
    end;


    -- =========================================================================
    -- Reject a duplicate name and a base_url without http(s)://.
    -- =========================================================================

    validate_environment_name(
        p_collection_id                         => l_collection_id
      , p_environment_id                        => p_environment_id
      , p_name                                  => p_name
    );
    -- =========================================================================

    l_base_url := normalize_base_url(p_base_url => p_base_url);

    -- uk_environments_name also covers inactive rows: explain the clash
    -- instead of surfacing a bare ORA-00001.
    select count(1)                                        as inactive_n
      into l_inactive_n
      from arw_environments v
     where v.collection_id = l_collection_id
       and v.name = trim(p_name)
       and v.active_yn = 'N';

    if l_inactive_n > 0 then
      raise_application_error(gc_err_invalid, 'An inactive environment named "' || trim(p_name) || '" exists in this collection -- choose another name.');
    end if;

    update arw_environments
       set name      = trim(p_name)
         , base_url  = l_base_url
     where environment_id = p_environment_id
       and active_yn = 'Y';

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_environment;








  -- ===========================================================================
  -- PROCEDURE: deactivate_environment
  -- ===========================================================================
  /**
   * Soft-deletes an environment (active_yn = N). Its variables and its
   * execution history are kept. last_updated_by/on are left to the
   * compound trigger, per ddl-conventions.md section 5.
   *
   * @example
   * begin
   *   arw_environments_api.deactivate_environment(
   *       p_environment_id                     => 1
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_environment_id Environment to deactivate
   */
  procedure deactivate_environment(
      p_environment_id                          in arw_environments.environment_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'deactivate_environment';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_environment_id', p_environment_id);
    logger.log('START', l_scope, null, l_params);

    update arw_environments
       set active_yn = 'N'
     where environment_id = p_environment_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_invalid, 'Environment not found: ' || p_environment_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end deactivate_environment;








  -- ===========================================================================
  -- FUNCTION: set_variable
  -- ===========================================================================
  /**
   * Creates or updates (upsert by name) a {{var}} variable of an active
   * environment; a previously removed variable with the same name is
   * reactivated. The value is never written to the logger -- it may be a
   * secret.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_variable_id arw_env_variables.variable_id%type;
   * begin
   *   l_variable_id := arw_environments_api.set_variable(
   *       p_environment_id                     => 1
   *     , p_var_name                           => 'user_id'
   *     , p_var_value                          => '1'
   *   );
   *   dbms_output.put_line('variable_id = ' || l_variable_id);
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_environment_id Environment the variable belongs to
   * @param p_var_name Variable name, referenced as {{var_name}}
   * @param p_var_value Variable value
   * @param p_is_secret_yn Y to hide the value on screen and in the history
   * @return arw_env_variables.variable_id%type  Identifier of the created or updated variable
   */
  function set_variable(
      p_environment_id                          in arw_env_variables.environment_id%type
    , p_var_name                                in arw_env_variables.var_name%type
    , p_var_value                               in arw_env_variables.var_value%type
    , p_is_secret_yn                            in arw_env_variables.is_secret_yn%type default 'N'
  )
  return arw_env_variables.variable_id%type
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'set_variable';
    l_params        logger.tab_param;
    l_environment_n number;
    l_var_name      arw_env_variables.var_name%type := trim(p_var_name);
    l_variable_id   arw_env_variables.variable_id%type;
  begin
    logger.append_param(l_params, 'p_environment_id', p_environment_id);
    logger.append_param(l_params, 'p_var_name', p_var_name);
    logger.append_param(l_params, 'p_is_secret_yn', p_is_secret_yn);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as environment_n
      into l_environment_n
      from arw_environments v
     where v.environment_id = p_environment_id
       and v.active_yn = 'Y';

    if l_environment_n = 0 then
      raise_application_error(gc_err_invalid, 'Environment not found: ' || p_environment_id);
    end if;

    if not regexp_like(l_var_name, '^[A-Za-z_][A-Za-z0-9_.-]*$') then
      raise_application_error(gc_err_invalid, 'Variable name must start with a letter or underscore and contain only letters, digits, "_", "." or "-": ' || p_var_name);
    end if;

    if lower(l_var_name) = gc_reserved_var then
      raise_application_error(gc_err_invalid, '{{base_url}} is the environment base URL and cannot be redefined as a variable.');
    end if;

    if p_is_secret_yn is null or p_is_secret_yn not in ('Y', 'N') then
      raise_application_error(gc_err_invalid, 'is_secret_yn must be Y or N.');
    end if;

    merge into arw_env_variables dest
    using (
      select p_environment_id as environment_id
           , l_var_name       as var_name
        from dual
    ) src
    on (dest.environment_id = src.environment_id and dest.var_name = src.var_name)
    when matched then
      update
         set dest.var_value    = p_var_value
           , dest.is_secret_yn = p_is_secret_yn
           , dest.active_yn    = 'Y'
    when not matched then
      insert (
             environment_id
           , var_name
           , var_value
           , is_secret_yn
      )
      values (
             src.environment_id
           , src.var_name
           , p_var_value
           , p_is_secret_yn
      );

    select ev.variable_id                                  as variable_id
      into l_variable_id
      from arw_env_variables ev
     where ev.environment_id = p_environment_id
       and ev.var_name = l_var_name;

    logger.append_param(l_params, 'l_variable_id', l_variable_id);
    logger.log('END', l_scope, null, l_params);

    return l_variable_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end set_variable;








  -- ===========================================================================
  -- PROCEDURE: remove_variable
  -- ===========================================================================
  /**
   * Soft-deletes an environment variable (active_yn = N). set_variable
   * with the same name reactivates it.
   *
   * @example
   * begin
   *   arw_environments_api.remove_variable(
   *       p_variable_id                        => 1
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_variable_id Variable to remove
   */
  procedure remove_variable(
      p_variable_id                             in arw_env_variables.variable_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'remove_variable';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_variable_id', p_variable_id);
    logger.log('START', l_scope, null, l_params);

    update arw_env_variables
       set active_yn = 'N'
     where variable_id = p_variable_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_invalid, 'Variable not found: ' || p_variable_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end remove_variable;








  -- ===========================================================================
  -- FUNCTION: resolve_environment_id
  -- ===========================================================================
  /**
   * Resolves the environment an endpoint of the collection runs against for
   * the active environment name (application item ARW_ENV_NAME): the active
   * environment with that name (case-insensitive), else the collection's
   * lowest active environment id, else null.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_environment_id arw_environments.environment_id%type;
   * begin
   *   l_environment_id := arw_environments_api.resolve_environment_id(
   *       p_collection_id                      => 1
   *     , p_environment_name                   => 'dev'
   *   );
   *   dbms_output.put_line('environment_id = ' || l_environment_id);
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_collection_id Collection whose environments are searched
   * @param p_environment_name Active environment name (e.g. dev); null falls back to the lowest active id
   * @return arw_environments.environment_id%type  Matching environment; null when the collection has no active environment
   */
  function resolve_environment_id(
      p_collection_id                           in arw_environments.collection_id%type
    , p_environment_name                        in arw_environments.name%type
  )
  return arw_environments.environment_id%type
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'resolve_environment_id';
    l_params         logger.tab_param;
    l_environment_id arw_environments.environment_id%type;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_environment_name', p_environment_name);
    logger.log('START', l_scope, null, l_params);

    -- Exact (case-insensitive) name match first, then the lowest active id
    select v.environment_id                                as environment_id
      into l_environment_id
      from arw_environments v
     where v.collection_id = p_collection_id
       and v.active_yn = 'Y'
     order by case
                when lower(v.name) = lower(trim(p_environment_name)) then 0
                else 1
              end
            , v.environment_id
     fetch first 1 row only;

    logger.append_param(l_params, 'l_environment_id', l_environment_id);
    logger.log('END', l_scope, null, l_params);

    return l_environment_id;
  exception
    when no_data_found then
      logger.log('END - no active environment in the collection', l_scope, null, l_params);
      return null;
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end resolve_environment_id;


end arw_environments_api;
/
