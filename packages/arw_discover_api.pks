-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_discover_api
as
-- =============================================================================
-- Package: arw_discover_api
-- Purpose: Discovery -- turns successful JSON executions into response
--          samples and consolidates every active sample of an endpoint into
--          an editable data profile (arw_data_profiles + arw_profile_columns).
--          See docs/base/IMPLEMENTATION.md sections 3.2 and 6 and the Page 210
--          Response / Discovery mockups.
--
-- Profile conventions consumed by the code generators:
--   - row_selector null  = the rows are the root value. A root array yields
--     one row per element; a root object yields a single row. json_table
--     row path is '$[*]' in both cases (lax mode wraps a lone object), and
--     the APEXlang dataProfile omits rowSelector. Otherwise row_selector is
--     a dotted path (e.g. items, data.items) and the row path is
--     '$.' || row_selector || '[*]'.
--   - path_expression is relative to the row (e.g. id, customer.code).
--   - A nested array of objects is one column with data_type_code 'clob' and
--     source_data_type 'array'; its fields are child columns
--     (parent_column_id) whose path_expression is relative to the array
--     element. An array of scalars is a single 'clob' / 'array' column.
--   - Exactly zero or one column per profile has is_primary_key_yn = 'Y'.
--
-- Errors: -20943 not found (execution, endpoint samples, profile, column);
--         -20944 invalid input (data type, Y/N flag, column name, length).
-- =============================================================================


  function save_sample(
      p_execution_id                            in arw_executions.execution_id%type
  )
  return arw_response_samples.sample_id%type;


  function sample_count(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return number;


  function derive_profile(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return arw_data_profiles.data_profile_id%type;


  function current_profile_id(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return arw_data_profiles.data_profile_id%type;


  procedure update_column(
      p_column_id                               in arw_profile_columns.column_id%type
    , p_column_name                             in arw_profile_columns.column_name%type
    , p_data_type_code                          in arw_profile_columns.data_type_code%type
    , p_max_observed_length                     in arw_profile_columns.max_observed_length%type
    , p_format_mask                             in arw_profile_columns.format_mask%type
    , p_is_nullable_yn                          in arw_profile_columns.is_nullable_yn%type
    , p_is_primary_key_yn                       in arw_profile_columns.is_primary_key_yn%type
  );


  procedure accept_profile(
      p_data_profile_id                         in arw_data_profiles.data_profile_id%type
  );


  function data_type_label(
      p_data_type_code                          in arw_profile_columns.data_type_code%type
  )
  return varchar2
  deterministic;


end arw_discover_api;
/
