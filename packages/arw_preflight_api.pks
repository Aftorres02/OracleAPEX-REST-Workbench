-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_preflight_api
as
-- =============================================================================
-- Package: arw_preflight_api
-- Purpose: Verifies network ACL, wallet/HTTPS readiness, DB/APEX version and
--          credential existence before the first real call to a host --
--          see docs/base/IMPLEMENTATION.md section 7 and
--          docs/base/implementation_plan.md section 4 (0.6). Read-only: only
--          queries catalogs and attempts a lightweight HTTPS call, never
--          mutates ARW data.
--
-- =============================================================================


  type t_check_rec is record (
      check_name                                varchar2(60 char)
    , status_code                               varchar2(10 char)
    , check_message                             varchar2(4000 char)
    , corrective_action                         varchar2(4000 char)
  );

  type t_check_tab is table of t_check_rec index by pls_integer;


  function check_network_acl(
      p_host                                    in varchar2
    , p_privilege                               in varchar2 default 'http'
  )
  return t_check_rec;


  function check_wallet(
      p_host                                    in varchar2
    , p_port                                    in number default 443
  )
  return t_check_rec;


  function check_database_version
  return t_check_rec;


  function check_credential(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return t_check_rec;


  function run_preflight(
      p_host                                    in varchar2
    , p_credential_id                           in arw_credentials.credential_id%type default null
  )
  return t_check_tab;


  function has_failures(
      p_checks                                  in t_check_tab
  )
  return varchar2;


  function format_failures(
      p_checks                                  in t_check_tab
  )
  return varchar2;


end arw_preflight_api;
/
