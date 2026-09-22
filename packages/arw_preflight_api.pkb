-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_preflight_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_host_required constant number := -20930;








  -- ===========================================================================
  -- FUNCTION: check_network_acl
  -- ===========================================================================
  /**
   * Checks whether the network ACL grants the given privilege (default
   * "http") to the current schema for a host, using
   * user_network_acl_privileges -- accessible without DBA privileges, unlike
   * dba_host_aces (see IMPLEMENTATION.md section 7). A host typically also
   * needs "resolve" alongside "http"; the corrective_action snippet includes
   * both.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_network_acl(
   *       p_host                                  => 'jsonplaceholder.typicode.com'
   *     , p_privilege                             => 'http'
   *   );
   *   dbms_output.put_line('status_code=' || l_check.status_code);
   *   dbms_output.put_line('check_message=' || l_check.check_message);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host       Host to check, no scheme/path (e.g. api.example.com)
   * @param  p_privilege  ACL privilege to check for; default "http"
   * @return t_check_rec  pass when granted; fail with a corrective dbms_network_acl_admin snippet otherwise
   */
  function check_network_acl(
      p_host                                    in varchar2
    , p_privilege                               in varchar2 default 'http'
  )
  return t_check_rec
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'check_network_acl';
    l_params logger.tab_param;
    l_check  t_check_rec;
    l_status varchar2(10 char);
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_privilege', p_privilege);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name := 'network_acl';

    select max(status)
      into l_status
      from user_network_acl_privileges
     where host = p_host
       and privilege = p_privilege;

    if l_status = 'GRANTED' then
      l_check.status_code   := 'pass';
      l_check.check_message := 'Privilege "' || p_privilege || '" granted for host ' || p_host || '.';
    else
      l_check.status_code       := 'fail';
      l_check.check_message     := case
                                      when l_status is null then 'No network ACL entry found for host ' || p_host || '.'
                                      else 'Privilege "' || p_privilege || '" is ' || l_status || ' for host ' || p_host || '.'
                                    end;
      l_check.corrective_action := 'Run as ' || user || ': begin dbms_network_acl_admin.append_host_ace('
                                    || 'host => ''' || p_host || ''', ace => xs$ace_type(privilege_list => '
                                    || 'xs$name_list(''resolve'', ''' || p_privilege || '''), principal_name '
                                    || '=> ''' || user || ''', principal_type => xs_acl.ptype_db)); end;';
    end if;

    logger.append_param(l_params, 'status_code', l_check.status_code);
    logger.log('END', l_scope, null, l_params);

    return l_check;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end check_network_acl;








  -- ===========================================================================
  -- FUNCTION: check_wallet
  -- ===========================================================================
  /**
   * Attempts a lightweight HTTPS HEAD call against the host to confirm the
   * wallet is usable, catching the two ORA codes IMPLEMENTATION.md section 7
   * documents for a missing/misconfigured wallet (ORA-29024 certificate
   * validation failure, ORA-28759 failure to open the wallet file). Any
   * other failure (DNS, ACL, a non-2xx HTTP status) does not tell us
   * anything about wallet health, so it is reported as "unknown" rather
   * than a false pass/fail.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_wallet(
   *       p_host                                  => 'jsonplaceholder.typicode.com'
   *   );
   *   dbms_output.put_line('status_code=' || l_check.status_code);
   *   dbms_output.put_line('check_message=' || l_check.check_message);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host       Host to check, no scheme/path (e.g. api.example.com)
   * @param  p_port       HTTPS port to probe; default 443
   * @return t_check_rec  pass/fail/unknown -- see description
   */
  function check_wallet(
      p_host                                    in varchar2
    , p_port                                    in number default 443
  )
  return t_check_rec
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'check_wallet';
    l_params logger.tab_param;
    l_check  t_check_rec;
    l_body   clob;
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_port', p_port);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name := 'wallet_https';

    -- g_request_headers is global and persists across calls (IMPLEMENTATION.md
    -- section 12) -- reset it before this probe so it never leaks into it.
    apex_web_service.g_request_headers.delete;

    l_body := apex_web_service.make_rest_request(
        p_url                                   => 'https://' || p_host || ':' || p_port
      , p_http_method                           => 'HEAD'
      , p_transfer_timeout                      => 10
    );

    l_check.status_code   := 'pass';
    l_check.check_message := 'HTTPS handshake with ' || p_host || ':' || p_port
                              || ' succeeded (HTTP status ' || apex_web_service.g_status_code || ').';

    logger.append_param(l_params, 'status_code', l_check.status_code);
    logger.log('END', l_scope, null, l_params);

    return l_check;
  exception
    -- Both branches return a populated check instead of re-raising: an
    -- inconclusive/failed wallet probe is this function's normal, expected
    -- output, not an unhandled error for the caller to propagate.
    when others then
      if sqlcode in (-29024, -28759) then
        l_check.status_code       := 'fail';
        l_check.check_message     := 'Wallet not usable for HTTPS calls to ' || p_host || ': ' || sqlerrm;
        l_check.corrective_action := 'Configure an Oracle wallet with the target CA and register its path '
                                      || '(apex_instance_admin.set_parameter for WALLET_PATH/WALLET_PWD, or '
                                      || 'the wallet already bundled for Autonomous Database).';
        logger.log_error('Wallet check failed', l_scope, null, l_params);
        return l_check;
      end if;

      l_check.status_code       := 'unknown';
      l_check.check_message     := 'Could not determine wallet status for ' || p_host || ': ' || sqlerrm;
      l_check.corrective_action := 'Resolve the underlying network error (ACL, DNS, connectivity) first, '
                                    || 'then re-run this check.';
      logger.log_error('Wallet check inconclusive', l_scope, null, l_params);
      return l_check;
  end check_wallet;








  -- ===========================================================================
  -- FUNCTION: check_database_version
  -- ===========================================================================
  /**
   * Reports the database and APEX version, informationally -- never fails.
   * Uses dbms_db_version (granted to PUBLIC) and the apex_release view
   * (public synonym, confirmed queryable from a plain workspace schema --
   * apex_util has no get_apex_version function, so a prior draft of this
   * check that called it did not compile) instead of v$version, which
   * isn't queryable from this schema.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_database_version;
   *   dbms_output.put_line('check_message=' || l_check.check_message);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @return t_check_rec  status_code = info; check_message carries the versions
   */
  function check_database_version
  return t_check_rec
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'check_database_version';
    l_params       logger.tab_param;
    l_check        t_check_rec;
    l_apex_version apex_release.version_no%type;
  begin
    logger.log('START', l_scope, null, l_params);

    select version_no
      into l_apex_version
      from apex_release;

    l_check.check_name    := 'db_apex_version';
    l_check.status_code   := 'info';
    l_check.check_message := 'Database ' || dbms_db_version.version || '.' || dbms_db_version.release
                              || ', APEX ' || l_apex_version || '.';

    logger.log('END', l_scope, null, l_params);

    return l_check;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end check_database_version;








  -- ===========================================================================
  -- FUNCTION: check_credential
  -- ===========================================================================
  /**
   * Confirms a credential exists, is active, has an
   * apex_credential_static_id linked, and that static_id still resolves via
   * apex_credential.get_credential_details. Passes trivially when
   * p_credential_id is null (the endpoint requires no auth).
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * Note: apex_credential.get_credential_details requires an active APEX
   * session context (apex_util.set_security_group_id) -- confirmed live
   * against 26.1: calling it from a bare SQLcl session raises "package
   * variable g_security_group_id must be set" for *any* static_id, not
   * just a missing one. That failure is reported as status_code = unknown
   * rather than fail, since it says nothing about whether the credential
   * itself exists. Run this check from a real APEX request (or a session
   * with the security group id set) to get a real pass/fail.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_credential(
   *       p_credential_id                         => null
   *   );
   *   dbms_output.put_line('status_code=' || l_check.status_code);
   * end;
   * /
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_credential_id  Credential to check; null means no auth required
   * @return t_check_rec      pass/fail -- see description
   */
  function check_credential(
      p_credential_id                           in arw_credentials.credential_id%type
  )
  return t_check_rec
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'check_credential';
    l_params       logger.tab_param;
    l_check        t_check_rec;
    l_credential_n pls_integer;
    l_static_id    arw_credentials.apex_credential_static_id%type;
    l_details      apex_credential.t_credential_details;
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name := 'credential_exists';

    if p_credential_id is null then
      l_check.status_code   := 'pass';
      l_check.check_message := 'Endpoint requires no credential.';

      logger.log('END', l_scope, null, l_params);
      return l_check;
    end if;

    select count(*)
         , max(apex_credential_static_id)
      into l_credential_n
         , l_static_id
      from arw_credentials
     where credential_id = p_credential_id
       and active_yn = 'Y';

    if l_credential_n = 0 then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Credential not found or inactive: ' || p_credential_id;
      l_check.corrective_action := 'Verify the credential_id, or reactivate it in arw_credentials.';
    elsif l_static_id is null then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Credential ' || p_credential_id || ' has no apex_credential_static_id linked.';
      l_check.corrective_action := 'Link arw_credentials.apex_credential_static_id to a Web Credential '
                                    || 'created in Shared Components > Web Credentials.';
    else
      begin
        l_details := apex_credential.get_credential_details(
            p_credential_static_id                => l_static_id
        );

        l_check.status_code   := 'pass';
        l_check.check_message := 'Credential "' || l_static_id || '" found via apex_credential.';
      exception
        when no_data_found then
          l_check.status_code       := 'fail';
          l_check.check_message     := 'apex_credential_static_id "' || l_static_id || '" not found via apex_credential.';
          l_check.corrective_action := 'Create the Web Credential with Static ID "' || l_static_id
                                        || '" in Shared Components > Web Credentials.';
        when others then
          l_check.status_code       := 'unknown';
          l_check.check_message     := 'Could not verify apex_credential_static_id "' || l_static_id || '": ' || sqlerrm;
          l_check.corrective_action := 'Run this check from within an APEX session context (a page request), '
                                        || 'not a bare SQLcl session -- apex_credential requires '
                                        || 'apex_util.set_security_group_id to already be set.';
      end;
    end if;

    logger.append_param(l_params, 'status_code', l_check.status_code);
    logger.log('END', l_scope, null, l_params);

    return l_check;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end check_credential;








  -- ===========================================================================
  -- FUNCTION: run_preflight
  -- ===========================================================================
  /**
   * Runs the full checklist (network ACL, wallet, DB/APEX version,
   * credential) for a host and returns every result -- the checklist
   * arw_exec_api gates the real call on (implementation_plan.md section 4,
   * 0.6/0.7).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_checks arw_preflight_api.t_check_tab;
   * begin
   *   l_checks := arw_preflight_api.run_preflight(
   *       p_host                                  => 'jsonplaceholder.typicode.com'
   *     , p_credential_id                         => null
   *   );
   *   dbms_output.put_line('check_count=' || l_checks.count);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host           Host to run the checklist against
   * @param  p_credential_id  Credential the endpoint will use; null means no auth
   * @return t_check_tab      One row per check, in the order they ran
   */
  function run_preflight(
      p_host                                    in varchar2
    , p_credential_id                           in arw_credentials.credential_id%type default null
  )
  return t_check_tab
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'run_preflight';
    l_params logger.tab_param;
    l_checks t_check_tab;
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    if p_host is null then
      raise_application_error(gc_err_host_required, 'run_preflight requires a host.');
    end if;

    l_checks(l_checks.count + 1) := check_network_acl(p_host => p_host);
    l_checks(l_checks.count + 1) := check_wallet(p_host => p_host);
    l_checks(l_checks.count + 1) := check_database_version;
    l_checks(l_checks.count + 1) := check_credential(p_credential_id => p_credential_id);

    logger.log('END', l_scope, null, l_params);

    return l_checks;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end run_preflight;








  -- ===========================================================================
  -- FUNCTION: has_failures
  -- ===========================================================================
  /**
   * Y when at least one check in the list has status_code = fail.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_checks arw_preflight_api.t_check_tab;
   * begin
   *   l_checks := arw_preflight_api.run_preflight(p_host => 'jsonplaceholder.typicode.com');
   *   dbms_output.put_line('has_failures=' || arw_preflight_api.has_failures(
   *       p_checks                                => l_checks
   *   ));
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_checks  Result of run_preflight
   * @return varchar2  Y/N
   */
  function has_failures(
      p_checks                                  in t_check_tab
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'has_failures';
    l_params logger.tab_param;
  begin
    logger.log('START', l_scope, null, l_params);

    for i in 1 .. p_checks.count loop
      if p_checks(i).status_code = 'fail' then
        logger.log('END', l_scope, null, l_params);
        return 'Y';
      end if;
    end loop;

    logger.log('END', l_scope, null, l_params);
    return 'N';
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end has_failures;








  -- ===========================================================================
  -- FUNCTION: format_failures
  -- ===========================================================================
  /**
   * Joins every failing check's name, message and corrective_action into one
   * human-readable block, for embedding in the error arw_exec_api raises
   * when the preflight gate blocks a call.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_checks arw_preflight_api.t_check_tab;
   * begin
   *   l_checks := arw_preflight_api.run_preflight(p_host => 'jsonplaceholder.typicode.com');
   *   dbms_output.put_line(arw_preflight_api.format_failures(
   *       p_checks                                => l_checks
   *   ));
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_checks  Result of run_preflight
   * @return varchar2  One line per failing check; empty when none failed
   */
  function format_failures(
      p_checks                                  in t_check_tab
  )
  return varchar2
  is
    l_scope   logger_logs.scope%type := gc_scope_prefix || 'format_failures';
    l_params  logger.tab_param;
    l_message varchar2(32000 char);
  begin
    logger.log('START', l_scope, null, l_params);

    for i in 1 .. p_checks.count loop
      if p_checks(i).status_code = 'fail' then
        l_message := l_message
                     || p_checks(i).check_name || ': ' || p_checks(i).check_message
                     || case
                          when p_checks(i).corrective_action is not null then ' Fix: ' || p_checks(i).corrective_action
                        end
                     || chr(10);
      end if;
    end loop;

    logger.log('END', l_scope, null, l_params);
    return l_message;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end format_failures;


end arw_preflight_api;
/
