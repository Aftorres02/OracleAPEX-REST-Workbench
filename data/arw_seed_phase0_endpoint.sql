-- Implements: .claude/rules/ddl-conventions.md section 8 (seed data pattern), sql-format.md section 9 (merge)
-- =============================================================================
-- Data: Phase 0 fixture -- 1 collection, 1 environment and 1 public
--       endpoint with no authentication, used as the end-to-end case for
--       subpaths 0.2/0.5/0.6 (see docs/base/implementation_plan.md).
--
-- @author  Angel Flores (Developer)
-- @created September 09, 2026
-- @ticket  N/A (Phase 0 - initial ARW data model)
-- =============================================================================
-- Re-runnable: every merge matches on a natural key (name) instead of
-- assuming a fixed id, so this script can run more than once without
-- duplicating rows.

set serveroutput on

declare
  l_collection_id   arw_collections.collection_id%type;
  l_environment_id  arw_environments.environment_id%type;
  l_endpoint_id     arw_endpoints.endpoint_id%type;
begin
  merge into arw_collections dest
  using (
    select 'ARW Phase 0 - Smoke Test' as name
      from dual
  ) src
  on (dest.name = src.name)
  when matched then
    update
       set dest.description = 'Test collection for the Phase 0 exit criterion.'
  when not matched then
    insert (
           name
         , description
    )
    values (
           src.name
         , 'Test collection for the Phase 0 exit criterion.'
    );

  select collection_id
    into l_collection_id
    from arw_collections
   where name = 'ARW Phase 0 - Smoke Test';


  merge into arw_environments dest
  using (
    select l_collection_id as collection_id
         , 'Public Test API' as name
      from dual
  ) src
  on (dest.collection_id = src.collection_id and dest.name = src.name)
  when matched then
    update
       set dest.base_url = 'https://jsonplaceholder.typicode.com'
  when not matched then
    insert (
           collection_id
         , name
         , base_url
    )
    values (
           src.collection_id
         , src.name
         , 'https://jsonplaceholder.typicode.com'
    );

  select environment_id
    into l_environment_id
    from arw_environments
   where collection_id = l_collection_id
     and name = 'Public Test API';


  merge into arw_endpoints dest
  using (
    select l_collection_id as collection_id
         , 'Get sample todo' as name
      from dual
  ) src
  on (dest.collection_id = src.collection_id and dest.name = src.name)
  when matched then
    update
       set dest.http_method = 'GET'
         , dest.url_path     = '/todos/1'
  when not matched then
    insert (
           collection_id
         , name
         , http_method
         , url_path
    )
    values (
           src.collection_id
         , src.name
         , 'GET'
         , '/todos/1'
    );

  select endpoint_id
    into l_endpoint_id
    from arw_endpoints
   where collection_id = l_collection_id
     and name = 'Get sample todo';

  dbms_output.put_line('collection_id='  || l_collection_id);
  dbms_output.put_line('environment_id=' || l_environment_id);
  dbms_output.put_line('endpoint_id='    || l_endpoint_id);
end;
/
commit;
