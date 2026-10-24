-- Implements: .claude/rules/ddl-conventions.md (additive DDL, comments)
-- =============================================================================
-- Script:  absolute_url_upgrade.sql
-- Purpose: Additive, re-runnable upgrade for full-URL endpoints: an endpoint
--          whose url_path is a full http(s) URL runs with no environment, so
--          arw_executions.environment_id becomes nullable. Fresh installs get
--          the same definition from tables/arw_executions.sql. Every step
--          checks the data dictionary first, so running it twice is a no-op.
--
-- @author  Angel Flores (Developer)
-- @created October 24, 2026
-- @ticket  #25
-- =============================================================================

prompt absolute_url_upgrade: arw_executions.environment_id / arw_endpoints.url_path

declare
  l_nullable user_tab_columns.nullable%type;
begin
  -- ===========================================================================
  -- arw_executions.environment_id -> nullable
  -- ===========================================================================
  select utc.nullable                                      as nullable
    into l_nullable
    from user_tab_columns utc
   where utc.table_name = 'ARW_EXECUTIONS'
     and utc.column_name = 'ENVIRONMENT_ID';

  if l_nullable = 'N' then
    execute immediate 'alter table arw_executions modify (environment_id null)';
    dbms_output.put_line('arw_executions.environment_id is now nullable');
  end if;


  -- ===========================================================================
  -- Comments (re-runnable by nature)
  -- ===========================================================================
  execute immediate 'comment on column arw_executions.environment_id is ''Environment this call was executed against; null for a full-URL endpoint run without one.''';
  execute immediate 'comment on column arw_endpoints.url_path is ''Path relative to the active environment base_url, or a full http(s) URL sent as written; supports {{var}} tokens.''';
end;
/
