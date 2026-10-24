-- Implements: .claude/rules/ddl-conventions.md (constraint naming, re-runnable scripts)
-- =============================================================================
-- Script:  codegen_upgrade.sql
-- Purpose: Widens the code generator's catalog checks (additive, idempotent):
--          - arw_generated_artifacts.artifact_type_code gains
--            apexlang_automation
--          - arw_code_templates.template_type_code gains table_ddl and
--            apexlang_automation
--          - arw_code_templates.section_code gains spec and footer
--          Each check is dropped and re-added with a superset of its values
--          only when its current condition does not list the new value yet.
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25 (Fase 1 - full app: code generation)
-- =============================================================================

prompt codegen_upgrade: widen arw_generated_artifacts / arw_code_templates checks

declare
  -- ---------------------------------------------------------------------------
  -- Re-creates p_constraint_name on p_table_name with p_condition unless the
  -- current condition already mentions p_marker_value.
  -- ---------------------------------------------------------------------------
  procedure widen_check(
      p_table_name                              in varchar2
    , p_constraint_name                         in varchar2
    , p_marker_value                            in varchar2
    , p_condition                               in varchar2
  )
  is
    l_condition varchar2(32767);
    l_exists_n  number;
  begin
    select count(1)                                        as exists_n
      into l_exists_n
      from user_constraints uc
     where uc.table_name = upper(p_table_name)
       and uc.constraint_name = upper(p_constraint_name);

    if l_exists_n > 0 then
      select uc.search_condition_vc                        as search_condition_vc
        into l_condition
        from user_constraints uc
       where uc.table_name = upper(p_table_name)
         and uc.constraint_name = upper(p_constraint_name);

      if instr(l_condition, '''' || p_marker_value || '''') > 0 then
        dbms_output.put_line(p_constraint_name || ': already widened');
        return;
      end if;

      execute immediate 'alter table ' || dbms_assert.simple_sql_name(p_table_name)
                        || ' drop constraint ' || dbms_assert.simple_sql_name(p_constraint_name);
    end if;

    execute immediate 'alter table ' || dbms_assert.simple_sql_name(p_table_name)
                      || ' add constraint ' || dbms_assert.simple_sql_name(p_constraint_name)
                      || ' check (' || p_condition || ')';
    dbms_output.put_line(p_constraint_name || ': widened');
  end widen_check;
begin
  widen_check(
      p_table_name                              => 'arw_generated_artifacts'
    , p_constraint_name                         => 'ck_arw_generated_artifacts_type'
    , p_marker_value                            => 'apexlang_automation'
    , p_condition                               => 'artifact_type_code in ('
                                                   || '''plsql_block'', ''plsql_package'', ''json_table'', ''curl'', ''table_ddl'''
                                                   || ', ''apexlang_rds'', ''apexlang_install_script'', ''apexlang_ai_tool'', ''apexlang_automation'')'
  );

  widen_check(
      p_table_name                              => 'arw_code_templates'
    , p_constraint_name                         => 'ck_arw_code_templates_type'
    , p_marker_value                            => 'apexlang_automation'
    , p_condition                               => 'template_type_code in ('
                                                   || '''plsql_block'', ''plsql_package'', ''json_table'', ''table_ddl'', ''curl'''
                                                   || ', ''apexlang_rds'', ''apexlang_install_script'', ''apexlang_ai_tool'', ''apexlang_automation'')'
  );

  widen_check(
      p_table_name                              => 'arw_code_templates'
    , p_constraint_name                         => 'ck_arw_code_templates_section'
    , p_marker_value                            => 'footer'
    , p_condition                               => 'section_code in ('
                                                   || '''spec'', ''declaration'', ''headers'', ''auth'', ''invocation'''
                                                   || ', ''status'', ''parsing'', ''example'', ''footer'')'
  );
end;
/

begin
  execute immediate 'comment on column arw_code_templates.template_type_code is ''Output type: plsql_block, plsql_package, json_table, table_ddl, curl, apexlang_rds, apexlang_install_script, apexlang_ai_tool or apexlang_automation.''';
  execute immediate 'comment on column arw_code_templates.section_code is ''Assembly pipeline section, in order: spec, declaration, headers, auth, invocation, status, parsing, example, footer.''';
end;
/
