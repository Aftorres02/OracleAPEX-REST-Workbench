-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_credentials_api
as
-- =============================================================================
-- Package: arw_credentials_api
-- Purpose: Credential metadata CRUD (arw_credentials) plus the bridge to the
--          native APEX credential store (apex_credential). ARW never stores a
--          secret: arw_credentials only references a Web Credential by its
--          static ID, and create_web_credential hands the secret straight to
--          apex_credential without logging or persisting it anywhere else.
--          Backs the Credentials pages (600/610) and the preflight
--          "Create credential" action -- see
--          .claude/skills/apex-outbound-rest/SKILL.md (Step 2).
--
-- =============================================================================


  function create_credential(
      p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_apex_credential_static_id               in arw_credentials.apex_credential_static_id%type default null
  )
  return arw_credentials.credential_id%type;


  procedure update_credential(
      p_credential_id                           in arw_credentials.credential_id%type
    , p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_apex_credential_static_id               in arw_credentials.apex_credential_static_id%type
  );


  procedure deactivate_credential(
      p_credential_id                           in arw_credentials.credential_id%type
  );


  function web_credential_exists(
      p_static_id                               in arw_credentials.apex_credential_static_id%type
  )
  return varchar2;


  procedure create_web_credential(
      p_static_id                               in arw_credentials.apex_credential_static_id%type
    , p_name                                    in arw_credentials.name%type
    , p_auth_type_code                          in arw_credentials.auth_type_code%type
    , p_client_id                               in varchar2
    , p_client_secret                           in varchar2
    , p_allowed_url                             in varchar2 default null
  );


end arw_credentials_api;
/
