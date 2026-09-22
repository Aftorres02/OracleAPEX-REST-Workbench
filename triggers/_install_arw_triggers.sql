-- Installs the ARW audit compound triggers (Phase 0.2), after running
-- tables/_install_arw_tables.sql. Order does not matter between them --
-- each trigger only depends on its own table already existing.
--
-- Note: release/all_triggers.sql already does "@../triggers/*.sql" (a glob
-- over this whole folder), so this script is only for installing/testing in
-- isolation before a real release exists -- see
-- docs/base/implementation_plan.md section 2.

@arw_collections_compound_trg.sql
@arw_environments_compound_trg.sql
@arw_credentials_compound_trg.sql
@arw_env_variables_compound_trg.sql
@arw_endpoints_compound_trg.sql
@arw_endpoint_headers_compound_trg.sql
@arw_endpoint_params_compound_trg.sql
@arw_request_bodies_compound_trg.sql
@arw_executions_compound_trg.sql
@arw_response_samples_compound_trg.sql
@arw_data_profiles_compound_trg.sql
@arw_profile_columns_compound_trg.sql
@arw_target_profiles_compound_trg.sql
@arw_code_templates_compound_trg.sql
@arw_generated_artifacts_compound_trg.sql

prompt --- ARW triggers installed ---
