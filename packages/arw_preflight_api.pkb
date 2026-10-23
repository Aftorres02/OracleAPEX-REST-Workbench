-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_preflight_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_host_required constant number := -20930;

  -- The schema that owns ARW (the APEX workspace's parsing schema) -- the
  -- principal a network ACE must name. $$plsql_unit_owner instead of
  -- "user": inside an APEX request "user" is the gateway account
  -- (APEX_PUBLIC_USER / ORDS_PUBLIC_USER), not the workspace schema.
  gc_schema constant varchar2(128 char) := $$plsql_unit_owner;

  -- Minimum APEX release for the APEXlang (.apx) outputs (CONCEPT.md)
  gc_min_apex_apexlang constant number := 2601;

  -- Minimum database release the generated PL/SQL targets
  gc_min_db_version constant number := 19;








  -- ===========================================================================
  -- FUNCTION: host_of
  -- ===========================================================================
  /**
   * Extracts the host name from a URL or a bare host: strips the scheme,
   * user info, port, path, query and fragment, and lowercases the result.
   * Returns null when what is left is not a valid DNS host name (letters,
   * digits, hyphens and dots only) -- e.g. a {{base_url}} placeholder.
   * The result is safe to embed in a generated script.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_preflight_api.host_of(
   *       p_url                                   => 'https://API.Example.com:8443/v1/items?id=1'
   *   ));
   *   -- api.example.com
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_url     Full URL (https://api.example.com/v1) or a bare host (api.example.com)
   * @return varchar2  Lowercase host name; null when p_url holds no valid host
   */
  function host_of(
      p_url                                     in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'host_of';
    l_params logger.tab_param;
    l_host   varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_url', p_url);
    logger.log('START', l_scope, null, l_params);

    l_host := lower(trim(p_url));
    l_host := regexp_replace(l_host, '^[a-z][a-z0-9+.-]*://', '');  -- scheme
    l_host := regexp_replace(l_host, '^[^/?#@]*@', '');              -- user info
    l_host := regexp_substr(l_host, '^[^/?#]+');                     -- path, query, fragment
    l_host := regexp_replace(l_host, ':[0-9]*$', '');                -- port

    if l_host is null
       or length(l_host) > 253
       or not regexp_like(l_host, '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$')
    then
      l_host := null;
    end if;

    logger.append_param(l_params, 'l_host', l_host);
    logger.log('END', l_scope, null, l_params);

    return l_host;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end host_of;








  -- ===========================================================================
  -- FUNCTION: acl_script (private)
  -- ===========================================================================
  /**
   * Builds the ready-to-paste dbms_network_acl_admin.append_host_ace script
   * that grants the ARW schema http + resolve on a host. The workspace
   * schema cannot run it itself -- dbms_network_acl_admin is not even
   * visible from it (PLS-00201) -- so the script's first line says to run
   * it as ADMIN (Autonomous Database) or a DBA. Every value is quoted with
   * dbms_assert.enquote_literal (security.md section 1).
   *
   * @example
   * -- Private: surfaced as corrective_action of the network_acl check.
   * select r.corrective_action as corrective_action
   *   from table(arw_preflight_api.preflight_report(
   *            p_host                         => 'httpbin.org'
   *        )) r
   *  where r.check_name = 'network_acl';
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_host       Host to grant, already validated by host_of
   * @param  p_privilege  Network privilege granted alongside resolve (normally http)
   * @return varchar2     Multi-line PL/SQL script, ending with "/"
   */
  function acl_script(
      p_host                                    in varchar2
    , p_privilege                               in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'acl_script';
    l_params logger.tab_param;
    l_script varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_privilege', p_privilege);
    logger.log('START', l_scope, null, l_params);

    l_script := '-- Run as ADMIN (Autonomous Database) or a DBA: ' || gc_schema || ' cannot see'                  || chr(10)
             || '-- dbms_network_acl_admin, so it cannot grant itself network access.'                          || chr(10)
             || 'begin'                                                                                          || chr(10)
             || '  dbms_network_acl_admin.append_host_ace('                                                      || chr(10)
             || '      host => ' || dbms_assert.enquote_literal(p_host)                                          || chr(10)
             || '    , ace  => xs$ace_type('                                                                     || chr(10)
             || '                  privilege_list => xs$name_list('
             ||                      dbms_assert.enquote_literal(lower(p_privilege)) || ', ''resolve'')'       || chr(10)
             || '                , principal_name => ' || dbms_assert.enquote_literal(gc_schema)                 || chr(10)
             || '                , principal_type => xs_acl.ptype_db'                                            || chr(10)
             || '              )'                                                                                || chr(10)
             || '  );'                                                                                           || chr(10)
             || 'end;'                                                                                           || chr(10)
             || '/';

    logger.log('END', l_scope, null, l_params);

    return l_script;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end acl_script;








  -- ===========================================================================
  -- FUNCTION: check_network_acl
  -- ===========================================================================
  /**
   * Checks whether the network ACL grants the given privilege (default
   * "http") and "resolve" to the ARW schema for a host, using
   * user_network_acl_privileges -- accessible without DBA privileges, unlike
   * dba_host_aces (see IMPLEMENTATION.md section 7). Exact host entries and
   * wildcard entries (*.example.com, *) both count.
   *
   * - http missing: fail (blocking) -- "Every call will raise ORA-24247".
   * - http granted, resolve missing: warn.
   * - both granted: pass.
   * fail/warn carry a ready-to-paste append_host_ace script in
   * corrective_action. Note: on Autonomous Database apex_web_service calls
   * were observed to succeed without the schema's own ACE
   * (.claude/skills/apex-outbound-rest/SKILL.md), so the wallet probe may
   * pass while this check fails.
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
   * @issue   #25 (Fase 1 - full app build): title, resolve, wildcards, multi-line ADMIN script
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host       Host to check, or a full URL (the host is extracted)
   * @param  p_privilege  ACL privilege to check for; default "http"
   * @return t_check_rec  pass, warn or fail -- see description
   */
  function check_network_acl(
      p_host                                    in varchar2
    , p_privilege                               in varchar2 default 'http'
  )
  return t_check_rec
  is
    l_scope      logger_logs.scope%type := gc_scope_prefix || 'check_network_acl';
    l_params     logger.tab_param;
    l_check      t_check_rec;
    l_host       varchar2(253 char);
    l_granted_yn varchar2(1 char);
    l_resolve_yn varchar2(1 char);
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_privilege', p_privilege);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name  := 'network_acl';
    l_check.check_title := 'Network ACL';

    l_host := host_of(p_url => p_host);

    if l_host is null then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Not a valid host name: ' || nvl(substr(p_host, 1, 200), '(empty)') || '.';
      l_check.corrective_action := 'Enter a host such as api.example.com, or a full URL such as https://api.example.com/v1.';

      logger.append_param(l_params, 'status_code', l_check.status_code);
      logger.log('END - invalid host', l_scope, null, l_params);
      return l_check;
    end if;

    select max(case
                 when p.privilege = lower(p_privilege) and p.status = 'GRANTED' then 'Y'
               end)                                        as granted_yn
         , max(case
                 when p.privilege = 'resolve' and p.status = 'GRANTED' then 'Y'
               end)                                        as resolve_yn
      into l_granted_yn
         , l_resolve_yn
      from user_network_acl_privileges p
     where lower(p.host) = l_host
        or p.host = '*'
        or (    p.host like '*.%'
            and l_host like '%' || lower(substr(p.host, 2)));

    if l_granted_yn = 'Y' and l_resolve_yn = 'Y' then
      l_check.status_code   := 'pass';
      l_check.check_message := lower(p_privilege) || ' and resolve privileges granted to ' || gc_schema || ' on this host.';
    elsif l_granted_yn = 'Y' then
      l_check.status_code       := 'warn';
      l_check.check_message     := lower(p_privilege) || ' privilege granted, but no resolve privilege on this host for the current schema. '
                                    || 'Host name resolution may raise ORA-24247.';
      l_check.corrective_action := acl_script(
                                       p_host       => l_host
                                     , p_privilege  => p_privilege
                                   );
    else
      l_check.status_code       := 'fail';
      l_check.check_message     := 'No ' || lower(p_privilege) || ' privilege on this host for the current schema. '
                                    || 'Every call will raise ORA-24247.';
      l_check.corrective_action := acl_script(
                                       p_host       => l_host
                                     , p_privilege  => p_privilege
                                   );
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
   * wallet holds a usable root certificate, and times it. Any HTTP status
   * (even 4xx/5xx) proves the TLS handshake completed -> pass. The wallet
   * error codes IMPLEMENTATION.md section 7 documents (ORA-29024
   * certificate validation failure, ORA-28759 failure to open the wallet
   * file) and fatal TLS errors (ORA-28860, ORA-28857) anywhere in the error
   * stack -> fail (blocking: no call can succeed). Any other failure (DNS,
   * ACL, timeout) says nothing about the wallet -> warn, not blocking.
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
   * @issue   #25 (Fase 1 - full app build): title, handshake timing, warn instead of unknown
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host       Host to check, or a full URL (the host is extracted)
   * @param  p_port       HTTPS port to probe; default 443
   * @return t_check_rec  pass, fail or warn -- see description
   */
  function check_wallet(
      p_host                                    in varchar2
    , p_port                                    in number default 443
  )
  return t_check_rec
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'check_wallet';
    l_params      logger.tab_param;
    l_check       t_check_rec;
    l_host        varchar2(253 char);
    l_body        clob;
    l_started_on  timestamp with time zone;
    l_elapsed     interval day to second;
    l_elapsed_ms  number;
    l_error_stack varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_port', p_port);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name  := 'wallet_https';
    l_check.check_title := 'Wallet and TLS chain';

    l_host := host_of(p_url => p_host);

    if l_host is null then
      l_check.status_code   := 'warn';
      l_check.check_message := 'Skipped: no valid host to probe.';

      logger.append_param(l_params, 'status_code', l_check.status_code);
      logger.log('END - invalid host', l_scope, null, l_params);
      return l_check;
    end if;

    -- g_request_headers is global and persists across calls (IMPLEMENTATION.md
    -- section 12) -- reset it before this probe so it never leaks into it.
    apex_web_service.g_request_headers.delete;

    l_started_on := systimestamp;

    l_body := apex_web_service.make_rest_request(
        p_url                                   => 'https://' || l_host
                                                   || case when nvl(p_port, 443) != 443 then ':' || p_port end
                                                   || '/'
      , p_http_method                           => 'HEAD'
      , p_transfer_timeout                      => 10
    );

    l_elapsed    := systimestamp - l_started_on;
    l_elapsed_ms := round(  extract(day    from l_elapsed) * 86400000
                          + extract(hour   from l_elapsed) * 3600000
                          + extract(minute from l_elapsed) * 60000
                          + extract(second from l_elapsed) * 1000);

    l_check.status_code   := 'pass';
    l_check.check_message := 'Root certificate present. Handshake completed in ' || l_elapsed_ms || ' ms.';

    logger.append_param(l_params, 'status_code', l_check.status_code);
    logger.append_param(l_params, 'http_status_code', apex_web_service.g_status_code);
    logger.append_param(l_params, 'l_elapsed_ms', l_elapsed_ms);
    logger.log('END', l_scope, null, l_params);

    return l_check;
  exception
    -- Every branch returns a populated check instead of re-raising: an
    -- inconclusive/failed wallet probe is this function's normal, expected
    -- output, not an unhandled error for the caller to propagate.
    when others then
      -- Keep the ORA-nnnnn messages, drop the "ORA-06512: at ..." frames
      l_error_stack := substr(dbms_utility.format_error_stack, 1, 4000);
      l_error_stack := trim(regexp_replace(regexp_replace(l_error_stack, 'ORA-06512: at [^' || chr(10) || ']*'), '\s+', ' '));

      if regexp_like(l_error_stack, 'ORA-(29024|28759|28860|28857)') then
        l_check.status_code       := 'fail';
        l_check.check_message     := 'TLS handshake with ' || l_host || ' failed: the wallet is missing or lacks the root certificate. '
                                      || l_error_stack;
        l_check.corrective_action := 'Configure an Oracle wallet with the target CA and register its path '
                                      || '(apex_instance_admin.set_parameter for WALLET_PATH/WALLET_PWD, or '
                                      || 'the wallet already bundled for Autonomous Database).';
        logger.log_error('Wallet check failed', l_scope, null, l_params);
        return l_check;
      end if;

      l_check.status_code       := 'warn';
      l_check.check_message     := 'Could not complete an HTTPS handshake with ' || l_host || ': '
                                    || l_error_stack;
      l_check.corrective_action := 'Resolve the underlying network error (DNS, ACL, connectivity), '
                                    || 'then re-run this check.';
      logger.log_warning('Wallet check inconclusive', l_scope, null, l_params);
      return l_check;
  end check_wallet;








  -- ===========================================================================
  -- FUNCTION: check_database_version
  -- ===========================================================================
  /**
   * Reports the database and APEX version, and whether every ARW output
   * can be produced for them: pass with "all outputs available" on Oracle
   * 19c+ and APEX 26.1+; warn when the APEXlang (.apx) outputs need a newer
   * APEX, or the database is older than the generated code targets. Uses
   * dbms_db_version (granted to PUBLIC) and the apex_release view (public
   * synonym, confirmed queryable from a plain workspace schema --
   * apex_util has no get_apex_version function) instead of v$version,
   * which a definer-rights package cannot rely on.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_database_version;
   *   dbms_output.put_line(l_check.status_code || ': ' || l_check.check_message);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   * @issue   #25 (Fase 1 - full app build): title, output availability, pass/warn
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @return t_check_rec  pass or warn; check_message reads e.g. "Oracle 23ai (middle dot) APEX 26.1 (em dash) all outputs available"
   */
  function check_database_version
  return t_check_rec
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'check_database_version';
    l_params       logger.tab_param;
    l_check        t_check_rec;
    l_apex_version apex_release.version_no%type;
    l_apex_release varchar2(20 char);
    l_apex_number  number;
    l_db_label     varchar2(30 char);
    l_summary      varchar2(200 char);
  begin
    logger.log('START', l_scope, null, l_params);

    select r.version_no                                    as version_no
      into l_apex_version
      from apex_release r;

    l_apex_release := regexp_substr(l_apex_version, '^[0-9]+\.[0-9]+');
    l_apex_number  := to_number(regexp_substr(l_apex_version, '[0-9]+', 1, 1)) * 100
                    + to_number(regexp_substr(l_apex_version, '[0-9]+', 1, 2));

    l_db_label := dbms_db_version.version
                  || case
                       when dbms_db_version.version >= 23 then 'ai'
                       when dbms_db_version.version >= 12 then 'c'
                     end;

    l_summary := 'Oracle ' || l_db_label || ' ' || unistr('\00B7') || ' APEX ' || l_apex_release || ' ' || unistr('\2014') || ' ';

    l_check.check_name  := 'db_apex_version';
    l_check.check_title := 'Database and APEX version';

    if dbms_db_version.version < gc_min_db_version then
      l_check.status_code       := 'warn';
      l_check.check_message     := l_summary || 'generated code targets Oracle ' || gc_min_db_version || 'c or later';
      l_check.corrective_action := 'Review generated code before installing it on this database.';
    elsif l_apex_number < gc_min_apex_apexlang then
      l_check.status_code       := 'warn';
      l_check.check_message     := l_summary || 'APEXlang (.apx) outputs need APEX 26.1 or later';
      l_check.corrective_action := 'Use the PL/SQL outputs (package, anonymous block, json_table) on this instance.';
    else
      l_check.status_code   := 'pass';
      l_check.check_message := l_summary || 'all outputs available';
    end if;

    logger.append_param(l_params, 'l_apex_version', l_apex_version);
    logger.append_param(l_params, 'status_code', l_check.status_code);
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
   * Confirms the endpoint's credential is usable: active, of an auth type
   * the executor supports, linked to a Web Credential static ID, and that
   * static ID present in the APEX credential store
   * (arw_credentials_api.web_credential_exists).
   *
   * - No credential linked: pass (the call goes out without auth).
   * - Credential missing/inactive, unsupported auth type, or no static ID:
   *   fail -- arw_auth_utils would refuse the call anyway.
   * - Static ID not in the credential store: warn, NOT blocking -- the
   *   mockup counts it outside "N of 4 blocking"; the call is allowed and
   *   fails at call time (recorded in arw_executions) until the Web
   *   Credential is created.
   * - Credential store not readable in this session: warn, with the
   *   explanation. (The store is read through apex_workspace_credentials,
   *   which works with or without an APEX session.)
   *
   * @example
   * set serveroutput on
   * declare
   *   l_check arw_preflight_api.t_check_rec;
   * begin
   *   l_check := arw_preflight_api.check_credential(
   *       p_credential_id                         => null
   *   );
   *   dbms_output.put_line(l_check.status_code || ': ' || l_check.check_message);
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   * @issue   #25 (Fase 1 - full app build): title, missing Web Credential is warn (not blocking)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_credential_id  Credential to check; null means no auth required
   * @return t_check_rec      pass, warn or fail -- see description
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
    l_name         arw_credentials.name%type;
    l_auth_type    arw_credentials.auth_type_code%type;
    l_static_id    arw_credentials.apex_credential_static_id%type;
    l_exists_yn    varchar2(1 char);
  begin
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    l_check.check_name  := 'credential_exists';
    l_check.check_title := 'Credential';

    if p_credential_id is null then
      l_check.status_code   := 'pass';
      l_check.check_message := 'No credential linked. Calls go out without authentication.';

      logger.log('END - no credential', l_scope, null, l_params);
      return l_check;
    end if;

    select count(1)                                        as credential_n
         , max(c.name)                                     as name
         , max(c.auth_type_code)                           as auth_type_code
         , max(c.apex_credential_static_id)                as apex_credential_static_id
      into l_credential_n
         , l_name
         , l_auth_type
         , l_static_id
      from arw_credentials c
     where c.credential_id = p_credential_id
       and c.active_yn = 'Y';

    if l_credential_n = 0 then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Credential ' || p_credential_id || ' not found or inactive.';
      l_check.corrective_action := 'Pick an active credential for the endpoint, or remove the link.';
    elsif l_auth_type not in ('basic', 'bearer', 'api_key_header', 'api_key_query') then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Auth type ' || l_auth_type || ' is not supported by the executor yet.';
      l_check.corrective_action := 'Use a basic, bearer, api_key_header or api_key_query credential to execute '
                                    || 'this endpoint; code generation still works.';
    elsif l_static_id is null then
      l_check.status_code       := 'fail';
      l_check.check_message     := 'Credential "' || l_name || '" has no Web Credential static ID linked.';
      l_check.corrective_action := 'Edit the credential and set the static ID of its Web Credential.';
    else
      l_exists_yn := arw_credentials_api.web_credential_exists(p_static_id => l_static_id);

      if l_exists_yn = 'Y' then
        l_check.status_code   := 'pass';
        l_check.check_message := l_static_id || ' found in the credential store.';
      elsif l_exists_yn = 'N' then
        l_check.status_code       := 'warn';
        l_check.check_message     := l_static_id || ' not found in the credential store';
        l_check.corrective_action := 'Create the Web Credential ' || l_static_id
                                      || ' (Create credential, or Shared Components > Web Credentials).';
      else
        l_check.status_code       := 'warn';
        l_check.check_message     := l_static_id || ' could not be checked: the credential store '
                                      || '(apex_workspace_credentials) is not readable in this session.';
        l_check.corrective_action := 'Run the preflight from the application (page 800).';
      end if;
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
   * Runs the full checklist for a host and returns every result, in the
   * order the Environment preflight page shows them: network ACL, wallet
   * and TLS chain, database/APEX version, credential. This is the
   * checklist arw_exec_api gates the real call on (implementation_plan.md
   * section 4, 0.6/0.7) -- only fail blocks.
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
   *   for i in 1 .. l_checks.count loop
   *     dbms_output.put_line(l_checks(i).check_name || ' = ' || l_checks(i).status_code);
   *   end loop;
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_host           Host (or full URL) to run the checklist against
   * @param  p_credential_id  Credential the endpoint will use; null means no auth
   * @return t_check_tab      One row per check, in display order
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
  -- FUNCTION: preflight_report
  -- ===========================================================================
  /**
   * Pipelined view of run_preflight for SQL -- the source of the
   * Environment preflight page (800). One row per check, in display order:
   * network_acl, wallet_https, db_apex_version, credential_exists. Columns:
   * check_name, check_title, status_code (pass, fail, warn, info),
   * check_message, corrective_action (the ADMIN append_host_ace script for
   * network_acl). The blocking count is count(status_code = 'fail').
   * p_host may be a bare host or a full URL. No rows when p_host is empty.
   *
   * @example
   * select r.check_title                                    as check_title
   *      , r.status_code                                    as status_code
   *      , r.check_message                                  as check_message
   *   from table(arw_preflight_api.preflight_report(
   *            p_host                         => 'jsonplaceholder.typicode.com'
   *          , p_credential_id                => null
   *        )) r;
   *
   * @issue   #25 (Fase 1 - full app build)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param  p_host           Host (or full URL) to check
   * @param  p_credential_id  Credential the endpoint will use; null means no auth
   * @return t_check_list     Pipelined rows, one per check
   */
  function preflight_report(
      p_host                                    in varchar2
    , p_credential_id                           in arw_credentials.credential_id%type default null
  )
  return t_check_list pipelined
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'preflight_report';
    l_params logger.tab_param;
    l_checks t_check_tab;
  begin
    logger.append_param(l_params, 'p_host', p_host);
    logger.append_param(l_params, 'p_credential_id', p_credential_id);
    logger.log('START', l_scope, null, l_params);

    if trim(p_host) is null then
      logger.log('END - no host, no rows', l_scope, null, l_params);
      return;
    end if;


    -- =========================================================================
    -- Run the same checklist arw_exec_api gates on.
    -- =========================================================================

    l_checks := run_preflight(
        p_host                                  => trim(p_host)
      , p_credential_id                         => p_credential_id
    );
    -- =========================================================================

    for i in 1 .. l_checks.count loop
      pipe row (l_checks(i));
    end loop;

    logger.log('END', l_scope, null, l_params);
    return;
  exception
    when no_data_needed then
      -- The consumer stopped fetching early (e.g. rownum filter): not an error
      raise;
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end preflight_report;








  -- ===========================================================================
  -- FUNCTION: has_failures
  -- ===========================================================================
  /**
   * Y when at least one check in the list has status_code = fail -- the
   * only blocking status. warn/info never block.
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
   * Joins every failing check's title, message and corrective_action into
   * one human-readable block, for embedding in the error arw_exec_api raises
   * when the preflight gate blocks a call.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_checks arw_preflight_api.t_check_tab;
   * begin
   *   l_checks := arw_preflight_api.run_preflight(p_host => 'httpbin.org');
   *   dbms_output.put_line(arw_preflight_api.format_failures(
   *       p_checks                                => l_checks
   *   ));
   * end;
   * /
   *
   * @issue   N/A (Phase 0 - initial ARW packages)
   * @issue   #25 (Fase 1 - full app build): check_title in the message
   *
   * @author  Angel Flores (Developer)
   * @created September 13, 2026
   *
   * @param  p_checks  Result of run_preflight
   * @return varchar2  One block per failing check; empty when none failed
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
                     || nvl(p_checks(i).check_title, p_checks(i).check_name) || ': ' || p_checks(i).check_message
                     || case
                          when p_checks(i).corrective_action is not null then ' Fix:' || chr(10) || p_checks(i).corrective_action
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
