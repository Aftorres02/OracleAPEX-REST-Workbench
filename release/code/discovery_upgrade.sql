-- Implements: .claude/rules/ddl-conventions.md (additive DDL, char semantics, check constraint naming, comments)
-- =============================================================================
-- Script:  discovery_upgrade.sql
-- Purpose: Additive, re-runnable upgrade of the discovery tables for
--          arw_discover_api (Page 210 Discovery tab):
--            - arw_data_profiles.profile_status_code ('proposal'/'accepted')
--            - arw_data_profiles.sample_count
--            - arw_profile_columns.observation_note
--          Fresh installs get the same columns from tables/*.sql; this script
--          only brings an existing schema up to date. Every step checks the
--          data dictionary first, so running it twice is a no-op.
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25
-- =============================================================================

prompt discovery_upgrade: arw_data_profiles / arw_profile_columns

declare
  l_count number;
begin
  -- ===========================================================================
  -- arw_data_profiles.profile_status_code
  -- ===========================================================================
  select count(1)                                          as column_n
    into l_count
    from user_tab_columns utc
   where utc.table_name = 'ARW_DATA_PROFILES'
     and utc.column_name = 'PROFILE_STATUS_CODE';

  if l_count = 0 then
    execute immediate q'[alter table arw_data_profiles add (profile_status_code varchar2(20 char) default 'proposal' not null)]';
    dbms_output.put_line('Added arw_data_profiles.profile_status_code');
  end if;

  select count(1)                                          as constraint_n
    into l_count
    from user_constraints uc
   where uc.table_name = 'ARW_DATA_PROFILES'
     and uc.constraint_name = 'CK_ARW_DATA_PROFILES_STATUS';

  if l_count = 0 then
    execute immediate q'[alter table arw_data_profiles add constraint ck_arw_data_profiles_status check (profile_status_code in ('proposal', 'accepted'))]';
    dbms_output.put_line('Added ck_arw_data_profiles_status');
  end if;


  -- ===========================================================================
  -- arw_data_profiles.sample_count
  -- ===========================================================================
  select count(1)                                          as column_n
    into l_count
    from user_tab_columns utc
   where utc.table_name = 'ARW_DATA_PROFILES'
     and utc.column_name = 'SAMPLE_COUNT';

  if l_count = 0 then
    execute immediate 'alter table arw_data_profiles add (sample_count number)';
    dbms_output.put_line('Added arw_data_profiles.sample_count');
  end if;


  -- ===========================================================================
  -- arw_profile_columns.observation_note
  -- ===========================================================================
  select count(1)                                          as column_n
    into l_count
    from user_tab_columns utc
   where utc.table_name = 'ARW_PROFILE_COLUMNS'
     and utc.column_name = 'OBSERVATION_NOTE';

  if l_count = 0 then
    execute immediate 'alter table arw_profile_columns add (observation_note varchar2(500 char))';
    dbms_output.put_line('Added arw_profile_columns.observation_note');
  end if;


  -- ===========================================================================
  -- Comments (re-runnable by nature)
  -- ===========================================================================
  execute immediate 'comment on column arw_data_profiles.profile_status_code is ''Review status: proposal (derived or edited, not yet reviewed) or accepted.''';
  execute immediate 'comment on column arw_data_profiles.sample_count is ''Number of response samples consolidated into this profile.''';
  execute immediate 'comment on column arw_data_profiles.row_selector is ''Dotted path to the array of rows (e.g. items); null when the rows are the root value (root array, or a single root object).''';
  execute immediate 'comment on column arw_profile_columns.observation_note is ''Why the proposal looks the way it does (e.g. missing in 1 of 3 samples -- marked as nullable).''';
end;
/
