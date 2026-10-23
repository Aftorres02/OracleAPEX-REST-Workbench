-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_environments_api
as
-- =============================================================================
-- Package: arw_environments_api
-- Purpose: Create, update and deactivate the environments of a collection
--          (dev/qa/prod base_url) and their {{var}} variables, and resolve
--          the active environment by name (application item ARW_ENV_NAME).
--          Backs the Environments pages (300/310) -- see
--          docs/base/implementation_plan.md section 5 (Fase 1).
--
-- =============================================================================


  function create_environment(
      p_collection_id                           in arw_environments.collection_id%type
    , p_name                                    in arw_environments.name%type
    , p_base_url                                in arw_environments.base_url%type
  )
  return arw_environments.environment_id%type;


  procedure update_environment(
      p_environment_id                          in arw_environments.environment_id%type
    , p_name                                    in arw_environments.name%type
    , p_base_url                                in arw_environments.base_url%type
  );


  procedure deactivate_environment(
      p_environment_id                          in arw_environments.environment_id%type
  );


  function set_variable(
      p_environment_id                          in arw_env_variables.environment_id%type
    , p_var_name                                in arw_env_variables.var_name%type
    , p_var_value                               in arw_env_variables.var_value%type
    , p_is_secret_yn                            in arw_env_variables.is_secret_yn%type default 'N'
  )
  return arw_env_variables.variable_id%type;


  procedure remove_variable(
      p_variable_id                             in arw_env_variables.variable_id%type
  );


  function resolve_environment_id(
      p_collection_id                           in arw_environments.collection_id%type
    , p_environment_name                        in arw_environments.name%type
  )
  return arw_environments.environment_id%type;


end arw_environments_api;
/
