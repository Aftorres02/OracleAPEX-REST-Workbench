-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_exec_api
as
-- =============================================================================
-- Package: arw_exec_api
-- Purpose: Executes the real HTTP call for an endpoint against a chosen
--          environment, and writes status/elapsed/response into
--          arw_executions. Runs arw_preflight_api.run_preflight against the
--          resolved host first and refuses to call out when it reports a
--          failing check -- see docs/base/implementation_plan.md section 4
--          (0.5/0.7) and docs/base/IMPLEMENTATION.md section 12 (known
--          pitfalls: g_request_headers reset, Authorization redaction).
--
-- Phase 0 scope: engine_code = 'apex_web_service' only, query parameters
-- only (path/form parameters and {{var}} environment substitution are not
-- yet implemented -- both fail loudly instead of silently mis-executing).
-- =============================================================================


  function execute_endpoint(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_environment_id                          in arw_environments.environment_id%type
  )
  return arw_executions.execution_id%type;


end arw_exec_api;
/
