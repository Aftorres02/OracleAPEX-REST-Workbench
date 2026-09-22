-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_auth_utils
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_credential_not_found      constant number := -20900;
  gc_err_auth_type_not_implemented constant number := -20901;








  -- ===========================================================================
  -- FUNCTION: get_auth_headers
  -- ===========================================================================
  /**
   * Builds the request headers needed to authenticate a call for the given
   * credential. Phase 0 only supports the no-auth case (p_credential_id is
   * null, returning an empty table); any real credential raises
   * gc_err_auth_type_not_implemented until its auth type is built in a
   * later phase -- see docs/base/implementation_plan.md section 6.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_headers arw_auth_utils.t_header_tab;
   * begin
   *   l_headers := arw_auth_utils.get_auth_headers(
   *       p_credential_id                         => null
   *   );
   *   dbms_output.put_line('header_count=' || l_headers.count);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 10, 2026
   *
   * @param  p_credential_id  Credential to resolve; null means no auth
   * @return t_header_tab     Headers to add to the request; empty when no auth
   */
  function get_auth_headers(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return t_header_tab
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'get_auth_headers';
    l_params    logger.tab_param;
    l_auth_type arw_credentials.auth_type_code%type;
    l_headers   t_header_tab;
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    if p_credential_id is null then
      logger.log('END', l_scope, null, l_params);
      return l_headers;
    end if;

    select auth_type_code
      into l_auth_type
      from arw_credentials
     where credential_id = p_credential_id
       and active_yn = 'Y';

    raise_application_error(
        gc_err_auth_type_not_implemented
      , 'Auth type not yet implemented: ' || l_auth_type
    );
  exception
    when no_data_found then
      logger.log_error('Credential not found', l_scope, null, l_params);
      raise_application_error(
          gc_err_credential_not_found
        , 'Credential not found: ' || p_credential_id
      );
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end get_auth_headers;


end arw_auth_utils;
/
