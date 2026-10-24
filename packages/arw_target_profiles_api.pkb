-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_target_profiles_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  -- One code for every C1 validation/not-found error (allocation in the
  -- #25 build brief); the message tells the cases apart.
  gc_err_invalid constant number := -20947;








  -- ===========================================================================
  -- FUNCTION: instance_db_version (private)
  -- ===========================================================================
  /**
   * Returns the release name of the database this code runs on, in the
   * format the target profile stores (e.g. 19c, 21c, 23ai).
   *
   * @example N/A -- private package-body unit, not callable outside
   *           arw_target_profiles_api; see create_profile's runnable example,
   *           which fills db_version through it when p_db_version is null.
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @return arw_target_profiles.db_version%type  Release name of the current database
   */
  function instance_db_version
  return arw_target_profiles.db_version%type
  is
    l_scope      logger_logs.scope%type := gc_scope_prefix || 'instance_db_version';
    l_params     logger.tab_param;
    l_db_version arw_target_profiles.db_version%type;
  begin
    logger.log('START', l_scope, null, l_params);

    l_db_version := dbms_db_version.version
                    || case when dbms_db_version.version >= 23 then 'ai' else 'c' end;

    logger.append_param(l_params, 'l_db_version', l_db_version);
    logger.log('END', l_scope, null, l_params);

    return l_db_version;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end instance_db_version;








  -- ===========================================================================
  -- FUNCTION: instance_apex_version (private)
  -- ===========================================================================
  /**
   * Returns the major.minor APEX version installed on this instance (e.g.
   * 26.1), the format the target profile stores.
   *
   * @example N/A -- private package-body unit, not callable outside
   *           arw_target_profiles_api; see create_profile's runnable example,
   *           which fills apex_version through it when p_apex_version is null.
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @return arw_target_profiles.apex_version%type  major.minor APEX version; null when APEX is not installed
   */
  function instance_apex_version
  return arw_target_profiles.apex_version%type
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'instance_apex_version';
    l_params       logger.tab_param;
    l_apex_version arw_target_profiles.apex_version%type;
  begin
    logger.log('START', l_scope, null, l_params);

    select regexp_substr(r.version_no, '^[0-9]+\.[0-9]+') as apex_version
      into l_apex_version
      from apex_release r;

    logger.append_param(l_params, 'l_apex_version', l_apex_version);
    logger.log('END', l_scope, null, l_params);

    return l_apex_version;
  exception
    when no_data_found then
      logger.log('END - apex_release returned no row', l_scope, null, l_params);
      return null;
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end instance_apex_version;








  -- ===========================================================================
  -- PROCEDURE: validate_profile (private)
  -- ===========================================================================
  /**
   * Validates a target profile before it is saved and raises gc_err_invalid
   * with a user-facing message: name required and unique among active
   * profiles (case-insensitive), object prefix a valid identifier start,
   * target schema a simple SQL name, and the trace mode, audit flag and
   * instance type within their allowed values.
   *
   * @example
   * -- Private: exercised through the public API. An unknown trace mode
   * -- fails with ORA-20947.
   * set serveroutput on
   * declare
   *   l_target_profile_id arw_target_profiles.target_profile_id%type;
   * begin
   *   l_target_profile_id := arw_target_profiles_api.create_profile(
   *       p_name                               => 'Broken profile'
   *     , p_object_prefix                      => 'app'
   *     , p_trace_mode_code                    => 'dbms_output'
   *   );
   * exception
   *   when others then
   *     dbms_output.put_line(sqlerrm);
   *     rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_target_profile_id Profile being saved; null when it is being created
   * @param p_name Display name of the profile
   * @param p_object_prefix Prefix of the generated objects, already normalized
   * @param p_target_schema Target schema, already normalized; null for the current schema
   * @param p_trace_mode_code Tracing framework: none, apex_debug or logger
   * @param p_audit_enabled_yn Y when the generated code audits its calls
   * @param p_instance_type_code Target instance type: apex or autonomous
   */
  procedure validate_profile(
      p_target_profile_id                       in arw_target_profiles.target_profile_id%type
    , p_name                                    in arw_target_profiles.name%type
    , p_object_prefix                           in arw_target_profiles.object_prefix%type
    , p_target_schema                           in arw_target_profiles.target_schema%type
    , p_trace_mode_code                         in arw_target_profiles.trace_mode_code%type
    , p_audit_enabled_yn                        in arw_target_profiles.audit_enabled_yn%type
    , p_instance_type_code                      in arw_target_profiles.instance_type_code%type
  )
  is
    l_scope       logger_logs.scope%type := gc_scope_prefix || 'validate_profile';
    l_params      logger.tab_param;
    l_duplicate_n number;
  begin
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_object_prefix', p_object_prefix);
    logger.append_param(l_params, 'p_target_schema', p_target_schema);
    logger.append_param(l_params, 'p_trace_mode_code', p_trace_mode_code);
    logger.append_param(l_params, 'p_audit_enabled_yn', p_audit_enabled_yn);
    logger.append_param(l_params, 'p_instance_type_code', p_instance_type_code);
    logger.log('START', l_scope, null, l_params);

    if trim(p_name) is null then
      raise_application_error(gc_err_invalid, 'Target profile name is required.');
    end if;

    select count(1)                                        as duplicate_n
      into l_duplicate_n
      from arw_target_profiles tp
     where lower(tp.name) = lower(trim(p_name))
       and tp.active_yn = 'Y'
       and (p_target_profile_id is null or tp.target_profile_id != p_target_profile_id);

    if l_duplicate_n > 0 then
      raise_application_error(gc_err_invalid, 'A target profile named "' || trim(p_name) || '" already exists.');
    end if;

    if not regexp_like(p_object_prefix, '^[a-z][a-z0-9_$#]*$') then
      raise_application_error(gc_err_invalid, 'Object prefix must start with a letter and contain only letters, digits, "_", "$" or "#".');
    end if;

    if p_target_schema is not null
       and not regexp_like(p_target_schema, '^[A-Z][A-Z0-9_$#]*$')
    then
      raise_application_error(gc_err_invalid, 'Target schema must be a simple schema name (letters, digits, "_", "$", "#"): ' || p_target_schema);
    end if;

    if p_trace_mode_code is null or p_trace_mode_code not in ('none', 'apex_debug', 'logger') then
      raise_application_error(gc_err_invalid, 'Trace mode must be none, apex_debug or logger.');
    end if;

    if p_audit_enabled_yn is null or p_audit_enabled_yn not in ('Y', 'N') then
      raise_application_error(gc_err_invalid, 'audit_enabled_yn must be Y or N.');
    end if;

    if p_instance_type_code is null or p_instance_type_code not in ('apex', 'autonomous') then
      raise_application_error(gc_err_invalid, 'Instance type must be apex or autonomous.');
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end validate_profile;








  -- ===========================================================================
  -- FUNCTION: create_profile
  -- ===========================================================================
  /**
   * Creates a target profile. The object prefix is stored lowercase without
   * a trailing underscore (the generator appends "_"), the target schema
   * uppercase. db_version/apex_version default to the versions of this
   * instance when not given. When an inactive profile with exactly the
   * same name exists (uk_target_profiles_name also covers inactive rows),
   * that row is reactivated with the new values and its id is returned.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_target_profile_id arw_target_profiles.target_profile_id%type;
   * begin
   *   l_target_profile_id := arw_target_profiles_api.create_profile(
   *       p_name                               => 'Sample profile'
   *     , p_object_prefix                      => 'app'
   *     , p_target_schema                      => null
   *     , p_trace_mode_code                    => 'logger'
   *     , p_audit_enabled_yn                   => 'Y'
   *     , p_instance_type_code                 => 'apex'
   *   );
   *   dbms_output.put_line('target_profile_id = ' || l_target_profile_id);
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_name Display name of the profile
   * @param p_object_prefix Prefix of the generated objects (e.g. app)
   * @param p_target_schema Target schema; null for the current schema
   * @param p_trace_mode_code Tracing framework: none, apex_debug or logger
   * @param p_audit_enabled_yn Y when the generated code audits its calls
   * @param p_instance_type_code Target instance type: apex or autonomous
   * @param p_db_version Target database release (e.g. 19c, 23ai); null for this instance's
   * @param p_apex_version Target APEX version (e.g. 24.2); null for this instance's
   * @return arw_target_profiles.target_profile_id%type  Identifier of the created (or reactivated) profile
   */
  function create_profile(
      p_name                                    in arw_target_profiles.name%type
    , p_object_prefix                           in arw_target_profiles.object_prefix%type
    , p_target_schema                           in arw_target_profiles.target_schema%type default null
    , p_trace_mode_code                         in arw_target_profiles.trace_mode_code%type default 'logger'
    , p_audit_enabled_yn                        in arw_target_profiles.audit_enabled_yn%type default 'Y'
    , p_instance_type_code                      in arw_target_profiles.instance_type_code%type default 'apex'
    , p_db_version                              in arw_target_profiles.db_version%type default null
    , p_apex_version                            in arw_target_profiles.apex_version%type default null
  )
  return arw_target_profiles.target_profile_id%type
  is
    l_scope             logger_logs.scope%type := gc_scope_prefix || 'create_profile';
    l_params            logger.tab_param;
    l_name              arw_target_profiles.name%type          := trim(p_name);
    l_object_prefix     arw_target_profiles.object_prefix%type := rtrim(lower(trim(p_object_prefix)), '_');
    l_target_schema     arw_target_profiles.target_schema%type := upper(trim(p_target_schema));
    l_db_version        arw_target_profiles.db_version%type    := coalesce(trim(p_db_version), instance_db_version);
    l_apex_version      arw_target_profiles.apex_version%type  := coalesce(trim(p_apex_version), instance_apex_version);
    l_target_profile_id arw_target_profiles.target_profile_id%type;
  begin
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_object_prefix', p_object_prefix);
    logger.append_param(l_params, 'p_trace_mode_code', p_trace_mode_code);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject a duplicate name or an out-of-range code before saving.
    -- =========================================================================

    validate_profile(
        p_target_profile_id                     => null
      , p_name                                  => l_name
      , p_object_prefix                         => l_object_prefix
      , p_target_schema                         => l_target_schema
      , p_trace_mode_code                       => p_trace_mode_code
      , p_audit_enabled_yn                      => p_audit_enabled_yn
      , p_instance_type_code                    => p_instance_type_code
    );
    -- =========================================================================

    update arw_target_profiles
       set object_prefix       = l_object_prefix
         , target_schema       = l_target_schema
         , trace_mode_code     = p_trace_mode_code
         , audit_enabled_yn    = p_audit_enabled_yn
         , instance_type_code  = p_instance_type_code
         , db_version          = l_db_version
         , apex_version        = l_apex_version
         , active_yn           = 'Y'
     where name = l_name
       and active_yn = 'N'
    returning target_profile_id into l_target_profile_id;

    if l_target_profile_id is null then
      insert
        into arw_target_profiles (
             name
           , object_prefix
           , target_schema
           , trace_mode_code
           , audit_enabled_yn
           , instance_type_code
           , db_version
           , apex_version
        )
      values (
             l_name
           , l_object_prefix
           , l_target_schema
           , p_trace_mode_code
           , p_audit_enabled_yn
           , p_instance_type_code
           , l_db_version
           , l_apex_version
        )
      returning target_profile_id into l_target_profile_id;
    end if;

    logger.append_param(l_params, 'l_target_profile_id', l_target_profile_id);
    logger.log('END', l_scope, null, l_params);

    return l_target_profile_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_profile;








  -- ===========================================================================
  -- PROCEDURE: update_profile
  -- ===========================================================================
  /**
   * Updates an active target profile, applying the same normalization and
   * validation as create_profile. A null db_version/apex_version is
   * refreshed from this instance.
   *
   * @example
   * begin
   *   arw_target_profiles_api.update_profile(
   *       p_target_profile_id                  => 1
   *     , p_name                               => 'Sample profile'
   *     , p_object_prefix                      => 'app'
   *     , p_target_schema                      => null
   *     , p_trace_mode_code                    => 'logger'
   *     , p_audit_enabled_yn                   => 'Y'
   *     , p_instance_type_code                 => 'apex'
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_target_profile_id Profile to update
   * @param p_name Display name of the profile
   * @param p_object_prefix Prefix of the generated objects (e.g. app)
   * @param p_target_schema Target schema; null for the current schema
   * @param p_trace_mode_code Tracing framework: none, apex_debug or logger
   * @param p_audit_enabled_yn Y when the generated code audits its calls
   * @param p_instance_type_code Target instance type: apex or autonomous
   * @param p_db_version Target database release (e.g. 19c, 23ai); null for this instance's
   * @param p_apex_version Target APEX version (e.g. 24.2); null for this instance's
   */
  procedure update_profile(
      p_target_profile_id                       in arw_target_profiles.target_profile_id%type
    , p_name                                    in arw_target_profiles.name%type
    , p_object_prefix                           in arw_target_profiles.object_prefix%type
    , p_target_schema                           in arw_target_profiles.target_schema%type
    , p_trace_mode_code                         in arw_target_profiles.trace_mode_code%type
    , p_audit_enabled_yn                        in arw_target_profiles.audit_enabled_yn%type
    , p_instance_type_code                      in arw_target_profiles.instance_type_code%type
    , p_db_version                              in arw_target_profiles.db_version%type default null
    , p_apex_version                            in arw_target_profiles.apex_version%type default null
  )
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'update_profile';
    l_params        logger.tab_param;
    l_name          arw_target_profiles.name%type          := trim(p_name);
    l_object_prefix arw_target_profiles.object_prefix%type := rtrim(lower(trim(p_object_prefix)), '_');
    l_target_schema arw_target_profiles.target_schema%type := upper(trim(p_target_schema));
    l_db_version    arw_target_profiles.db_version%type    := coalesce(trim(p_db_version), instance_db_version);
    l_apex_version  arw_target_profiles.apex_version%type  := coalesce(trim(p_apex_version), instance_apex_version);
    l_inactive_n    number;
  begin
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_object_prefix', p_object_prefix);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject a duplicate name or an out-of-range code before saving.
    -- =========================================================================

    validate_profile(
        p_target_profile_id                     => p_target_profile_id
      , p_name                                  => l_name
      , p_object_prefix                         => l_object_prefix
      , p_target_schema                         => l_target_schema
      , p_trace_mode_code                       => p_trace_mode_code
      , p_audit_enabled_yn                      => p_audit_enabled_yn
      , p_instance_type_code                    => p_instance_type_code
    );
    -- =========================================================================

    -- uk_target_profiles_name also covers inactive rows: explain the clash
    -- instead of surfacing a bare ORA-00001.
    select count(1)                                        as inactive_n
      into l_inactive_n
      from arw_target_profiles tp
     where tp.name = l_name
       and tp.active_yn = 'N';

    if l_inactive_n > 0 then
      raise_application_error(gc_err_invalid, 'An inactive target profile named "' || l_name || '" exists -- choose another name.');
    end if;

    update arw_target_profiles
       set name                = l_name
         , object_prefix       = l_object_prefix
         , target_schema       = l_target_schema
         , trace_mode_code     = p_trace_mode_code
         , audit_enabled_yn    = p_audit_enabled_yn
         , instance_type_code  = p_instance_type_code
         , db_version          = l_db_version
         , apex_version        = l_apex_version
     where target_profile_id = p_target_profile_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_invalid, 'Target profile not found: ' || p_target_profile_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_profile;








  -- ===========================================================================
  -- PROCEDURE: deactivate_profile
  -- ===========================================================================
  /**
   * Soft-deletes a target profile (active_yn = N). Refuses to deactivate the
   * last active profile, because the code generator falls back to
   * default_profile_id when no profile is chosen. Artifacts already
   * generated with the profile are kept. last_updated_by/on are left to
   * the compound trigger, per ddl-conventions.md section 5.
   *
   * @example
   * begin
   *   arw_target_profiles_api.deactivate_profile(
   *       p_target_profile_id                  => 3
   *   );
   *   rollback;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_target_profile_id Profile to deactivate
   */
  procedure deactivate_profile(
      p_target_profile_id                       in arw_target_profiles.target_profile_id%type
  )
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'deactivate_profile';
    l_params   logger.tab_param;
    l_others_n number;
  begin
    logger.append_param(l_params, 'p_target_profile_id', p_target_profile_id);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as others_n
      into l_others_n
      from arw_target_profiles tp
     where tp.target_profile_id != p_target_profile_id
       and tp.active_yn = 'Y';

    if l_others_n = 0 then
      raise_application_error(gc_err_invalid, 'At least one active target profile is required -- create another one before deactivating this one.');
    end if;

    update arw_target_profiles
       set active_yn = 'N'
     where target_profile_id = p_target_profile_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_invalid, 'Target profile not found: ' || p_target_profile_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end deactivate_profile;








  -- ===========================================================================
  -- FUNCTION: default_profile_id
  -- ===========================================================================
  /**
   * Returns the default target profile: the active profile with the lowest
   * target_profile_id. Used by the code generator when no profile is
   * chosen.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line('default_profile_id = ' || arw_target_profiles_api.default_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - full ARW application)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @return arw_target_profiles.target_profile_id%type  Default profile; null when there is no active profile
   */
  function default_profile_id
  return arw_target_profiles.target_profile_id%type
  is
    l_scope             logger_logs.scope%type := gc_scope_prefix || 'default_profile_id';
    l_params            logger.tab_param;
    l_target_profile_id arw_target_profiles.target_profile_id%type;
  begin
    logger.log('START', l_scope, null, l_params);

    select min(tp.target_profile_id)                       as target_profile_id
      into l_target_profile_id
      from arw_target_profiles tp
     where tp.active_yn = 'Y';

    logger.append_param(l_params, 'l_target_profile_id', l_target_profile_id);
    logger.log('END', l_scope, null, l_params);

    return l_target_profile_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end default_profile_id;


end arw_target_profiles_api;
/
