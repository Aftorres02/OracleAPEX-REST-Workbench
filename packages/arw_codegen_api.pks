-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_codegen_api
as
-- =============================================================================
-- Package: arw_codegen_api
-- Purpose: Orchestrates code generation for an endpoint (Code tab of page
--          210): reads the endpoint, its headers/params/body, its active
--          data profile and a target profile, assembles the fragments
--          stored in arw_code_templates through arw_render_utils, and
--          versions the result in arw_generated_artifacts. See
--          docs/base/IMPLEMENTATION.md sections 2, 5 and 10.
--
--          Artifact type codes (mockup order):
--            PASTE   plsql_package, plsql_block, json_table, table_ddl, curl
--            INSTALL apexlang_rds, apexlang_install_script,
--                    apexlang_ai_tool, apexlang_automation
--
-- =============================================================================


  function render_artifact(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob;


  function get_artifact(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_code                      in arw_generated_artifacts.artifact_type_code%type
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob;


  function build_apx_bundle(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_artifact_type_codes                     in varchar2
    , p_target_profile_id                       in arw_target_profiles.target_profile_id%type default null
  )
  return clob;


  function bundle_file_name(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return varchar2;


end arw_codegen_api;
/
