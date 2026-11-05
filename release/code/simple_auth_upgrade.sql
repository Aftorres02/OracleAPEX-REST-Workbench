-- Implements: .claude/rules/ddl-conventions.md (additive DDL, comments)
-- =============================================================================
-- Script:  simple_auth_upgrade.sql
-- Purpose: Additive, re-runnable upgrade for simple per-request auth (none,
--          basic, bearer, api_key) applied by ARW itself, without APEX Web
--          Credentials. Fresh installs get the same definition from
--          tables/arw_endpoints.sql. Every step checks the data dictionary
--          first, so running it twice is a no-op.
--
-- @author  Angel Flores (Developer)
-- @created November 03, 2026
-- @ticket  PHASE2-simplified
-- =============================================================================

prompt simple_auth_upgrade: arw_endpoints auth columns

declare
  -- -----------------------------------------------------------------------------
  -- Add a column only when it is missing
  -- -----------------------------------------------------------------------------
  procedure add_column(
      p_column_name                             in user_tab_columns.column_name%type
    , p_definition                              in varchar2
  )
  is
    l_count number;
  begin
    select count(1)                                        as column_n
      into l_count
      from user_tab_columns utc
     where utc.table_name = 'ARW_ENDPOINTS'
       and utc.column_name = upper(p_column_name);

    if l_count = 0 then
      execute immediate 'alter table arw_endpoints add (' || dbms_assert.simple_sql_name(p_column_name) || ' ' || p_definition || ')';
      dbms_output.put_line('arw_endpoints.' || p_column_name || ' added');
    end if;
  end add_column;


  -- -----------------------------------------------------------------------------
  -- Add a check constraint only when it is missing
  -- -----------------------------------------------------------------------------
  procedure add_check(
      p_constraint_name                         in user_constraints.constraint_name%type
    , p_condition                               in varchar2
  )
  is
    l_count number;
  begin
    select count(1)                                        as constraint_n
      into l_count
      from user_constraints uc
     where uc.table_name = 'ARW_ENDPOINTS'
       and uc.constraint_name = upper(p_constraint_name);

    if l_count = 0 then
      execute immediate 'alter table arw_endpoints add constraint ' || dbms_assert.simple_sql_name(p_constraint_name) || ' check (' || p_condition || ')';
      dbms_output.put_line(p_constraint_name || ' added');
    end if;
  end add_check;
begin
  add_column('auth_type_code',         'varchar2(20 char) default ''none'' not null');
  add_column('auth_username',          'varchar2(400 char)');
  add_column('auth_password',          'varchar2(4000 char)');
  add_column('auth_token',             'varchar2(4000 char)');
  add_column('auth_key_name',          'varchar2(200 char)');
  add_column('auth_key_value',         'varchar2(4000 char)');
  add_column('auth_key_location_code', 'varchar2(10 char) default ''header'' not null');

  add_check('ck_arw_endpoints_auth_type',         'auth_type_code in (''none'', ''basic'', ''bearer'', ''api_key'')');
  add_check('ck_arw_endpoints_auth_key_location', 'auth_key_location_code in (''header'', ''query'')');


  -- ===========================================================================
  -- Comments (re-runnable by nature)
  -- ===========================================================================
  execute immediate 'comment on column arw_endpoints.auth_type_code is ''Simple auth applied by ARW itself: none, basic, bearer or api_key. Independent of credential_id (APEX Web Credentials, hidden since the Nov 2026 simplification).''';
  execute immediate 'comment on column arw_endpoints.auth_username is ''Basic auth user name; supports {{var}} tokens.''';
  execute immediate 'comment on column arw_endpoints.auth_password is ''Basic auth password, stored as typed (demo/beta); supports {{var}} tokens.''';
  execute immediate 'comment on column arw_endpoints.auth_token is ''Bearer token, stored as typed (demo/beta); supports {{var}} tokens.''';
  execute immediate 'comment on column arw_endpoints.auth_key_name is ''API key header or query parameter name (e.g. x-api-key).''';
  execute immediate 'comment on column arw_endpoints.auth_key_value is ''API key value, stored as typed (demo/beta); supports {{var}} tokens.''';
  execute immediate 'comment on column arw_endpoints.auth_key_location_code is ''Where the API key goes: header or query.''';
end;
/
