-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_auth_utils
as
-- =============================================================================
-- Package: arw_auth_utils
-- Purpose: Builds the authentication headers for a credential. Simple auth
--          (basic, bearer, API key) resolves inline; algorithmic auth
--          (SigV4, signed JWT) is emitted as dedicated signer logic in a
--          later phase -- see docs/base/CONCEPT.md decision 5.
--
-- =============================================================================


  type t_header_rec is record (
      header_name                               arw_endpoint_headers.header_name%type
    , header_value                              arw_endpoint_headers.header_value%type
  );

  type t_header_tab is table of t_header_rec index by pls_integer;


  function get_auth_headers(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return t_header_tab;


end arw_auth_utils;
/
