-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_auth_utils
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_credential_not_found      constant number := -20900;
  gc_err_auth_type_not_implemented constant number := -20901;
  gc_err_credential_misconfigured  constant number := -20902;








  -- ===========================================================================
  -- FUNCTION: resolve_credential_static_id
  -- ===========================================================================
  /**
   * Resolves the apex_credential static ID that arw_exec_api should pass to
   * apex_web_service.make_rest_request's p_credential_static_id parameter.
   * APEX attaches the actual Authorization header (basic/bearer/API key in
   * a header) or query parameter (API key in the query string) itself from
   * the Web Credential store at call time, so the secret never passes
   * through this code. Returns null when p_credential_id is null (no auth).
   *
   * basic/bearer/api_key_header/api_key_query all resolve the same way --
   * they're distinguished only by how the credential itself was created in
   * Shared Components > Web Credentials (BASIC / HTTP_HEADER /
   * HTTP_QUERY_STRING), not by anything this function does differently.
   * Any other auth_type_code raises gc_err_auth_type_not_implemented until
   * its signer logic is built in a later phase -- see
   * docs/base/implementation_plan.md section 6.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_static_id arw_credentials.apex_credential_static_id%type;
   * begin
   *   l_static_id := arw_auth_utils.resolve_credential_static_id(
   *       p_credential_id                         => null
   *   );
   *   dbms_output.put_line('static_id=' || l_static_id);
   * end;
   * /
   *
   * @issue   N/A (Phase 1 - basic/bearer/API key auth)
   *
   * @author  Angel Flores (Developer)
   * @created September 22, 2026
   *
   * @param  p_credential_id  Credential to resolve; null means no auth
   * @return varchar2         apex_credential static ID to pass through; null when no auth
   */
  function resolve_credential_static_id(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return arw_credentials.apex_credential_static_id%type
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'resolve_credential_static_id';
    l_params    logger.tab_param;
    l_auth_type arw_credentials.auth_type_code%type;
    l_static_id arw_credentials.apex_credential_static_id%type;
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    if p_credential_id is null then
      logger.log('END', l_scope, null, l_params);
      return null;
    end if;

    select auth_type_code
         , apex_credential_static_id
      into l_auth_type
         , l_static_id
      from arw_credentials
     where credential_id = p_credential_id
       and active_yn = 'Y';

    if l_auth_type not in ('basic', 'bearer', 'api_key_header', 'api_key_query') then
      raise_application_error(
          gc_err_auth_type_not_implemented
        , 'Auth type not yet implemented: ' || l_auth_type
      );
    end if;

    if l_static_id is null then
      raise_application_error(
          gc_err_credential_misconfigured
        , 'Credential ' || p_credential_id || ' has no apex_credential_static_id linked.'
      );
    end if;

    logger.append_param(l_params, 'l_static_id', l_static_id);
    logger.log('END', l_scope, null, l_params);

    return l_static_id;
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
  end resolve_credential_static_id;


end arw_auth_utils;
/
