-- Installs the full ARW data model (Phase 0.2), in FK dependency order --
-- see docs/base/implementation_plan.md sections 3-4.
--
-- Run once against a fresh schema. Not re-runnable: running it again fails
-- with ORA-00955 (name already used) since this is DDL, not a data script.

prompt --- Core ---
@arw_collections.sql
@arw_environments.sql
@arw_credentials.sql
@arw_env_variables.sql
@arw_endpoints.sql
@arw_endpoint_headers.sql
@arw_endpoint_params.sql
@arw_request_bodies.sql

prompt --- Execution ---
@arw_executions.sql

prompt --- Discovery ---
@arw_response_samples.sql
@arw_data_profiles.sql
@arw_profile_columns.sql

prompt --- Generation ---
@arw_target_profiles.sql
@arw_code_templates.sql
@arw_generated_artifacts.sql

prompt --- ARW tables installed. Continue with triggers/_install_arw_triggers.sql ---
