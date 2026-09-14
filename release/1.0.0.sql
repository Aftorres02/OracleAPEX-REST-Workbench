-- =============================================================================
-- Release 1.0.0 -- ARW initial data model (Phase 0)
-- =============================================================================
-- Installs the full ARW data model: core + execution + discovery +
-- generation tables, their audit compound triggers, and the Phase 0
-- smoke-test seed row. See docs/base/implementation_plan.md sections 3-4.
--
-- Adapted from _release.sql for this first release: the APEX
-- disable/install steps are intentionally omitted -- no APEX application
-- exists yet (that starts in Phase 1+). Re-introduce them in a later
-- release once apex/ holds a real exported application.
-- =============================================================================
clear screen

whenever sqlerror exit sql.sqlcode

-- load_env_vars.sql is skipped here: its blank ''define env_schema_name=''
-- does not stop a later ''&env_schema_name.'' reference from prompting
-- interactively in this SQLcl version, which breaks a non-interactive
-- release run. This release targets the ARW dev schema directly instead.
prompt loading environment variables
define env_schema_name=WKSP_DEVAI1

set verify off
set feedback on
set timing on
set serveroutput on
set sqlblanklines off;

define logname = ''

set termout on
column my_logname new_val logname
select 'release_1.0.0_'||sys_context('userenv','service_name')||'_'||to_char(sysdate, 'YYYY-MM-DD_HH24-MI-SS')||'.log' my_logname from dual;
column my_logname clear
set termout on
spool &logname
prompt Log File: &logname


prompt check DB user is expected user
declare
begin
  if user != '&env_schema_name' or '&env_schema_name' is null then
    raise_application_error(-20001, 'Must be run as &env_schema_name');
  end if;
end;
/


-- *** Release specific tasks ***
@code/_run_code.sql


-- *** Tables, views, triggers ***
@all_tables.sql
@all_views.sql
@all_triggers.sql


prompt Invalid objects
select object_name, object_type
from user_objects
where status != 'VALID'
order by object_name
;


-- *** DATA ***
@all_data.sql


prompt recompile invalid schema objects
begin
  dbms_utility.compile_schema(schema => user, compile_all => false);
end;
/


-- *** APEX ***
-- Intentionally skipped for release 1.0.0: no APEX application exists yet.


prompt Invalid objects (final)
select object_name, object_type
from user_objects
where status != 'VALID'
order by object_name
;


spool off
exit
