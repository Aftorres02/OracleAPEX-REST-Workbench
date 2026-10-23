-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_target_profiles_api
as
-- =============================================================================
-- Package: arw_target_profiles_api
-- Purpose: Create, update and deactivate target profiles (object prefix,
--          target schema, tracing, auditing, instance type) the code
--          generator renders against, and pick the default profile. Backs
--          the Target profiles pages (500/510) -- see
--          docs/base/IMPLEMENTATION.md section 7.
--
-- =============================================================================


  function create_profile(
      p_name                                    in arw_target_profiles.name%type
    , p_object_prefix                           in arw_target_profiles.object_prefix%type
    , p_target_schema                           in arw_target_profiles.target_schema%type default null
    , p_trace_mode_code                         in arw_target_profiles.trace_mode_code%type default 'logger'
    , p_audit_enabled_yn                        in arw_target_profiles.audit_enabled_yn%type default 'Y'
    , p_instance_type_code                      in arw_target_profiles.instance_type_code%type default 'apex'
    , p_db_version                              in arw_target_profiles.db_version%type default null
    , p_apex_version                            in arw_target_profiles.apex_version%type default null
  )
  return arw_target_profiles.target_profile_id%type;


  procedure update_profile(
      p_target_profile_id                       in arw_target_profiles.target_profile_id%type
    , p_name                                    in arw_target_profiles.name%type
    , p_object_prefix                           in arw_target_profiles.object_prefix%type
    , p_target_schema                           in arw_target_profiles.target_schema%type
    , p_trace_mode_code                         in arw_target_profiles.trace_mode_code%type
    , p_audit_enabled_yn                        in arw_target_profiles.audit_enabled_yn%type
    , p_instance_type_code                      in arw_target_profiles.instance_type_code%type
    , p_db_version                              in arw_target_profiles.db_version%type default null
    , p_apex_version                            in arw_target_profiles.apex_version%type default null
  );


  procedure deactivate_profile(
      p_target_profile_id                       in arw_target_profiles.target_profile_id%type
  );


  function default_profile_id
  return arw_target_profiles.target_profile_id%type;


end arw_target_profiles_api;
/
