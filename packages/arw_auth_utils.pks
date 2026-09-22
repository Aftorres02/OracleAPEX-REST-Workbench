-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_auth_utils
as
-- =============================================================================
-- Package: arw_auth_utils
-- Purpose: Resolves which apex_credential static ID (if any) arw_exec_api
--          should pass to apex_web_service.make_rest_request's
--          p_credential_static_id parameter. APEX attaches the actual
--          Authorization header or query parameter itself from the Web
--          Credential store, so the secret never passes through this code.
--          Algorithmic auth (SigV4, signed JWT) needs dedicated signer
--          logic in a later phase -- see docs/base/CONCEPT.md decision 5.
--
-- =============================================================================


  function resolve_credential_static_id(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return arw_credentials.apex_credential_static_id%type;


end arw_auth_utils;
/
