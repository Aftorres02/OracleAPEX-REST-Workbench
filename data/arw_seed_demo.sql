-- Implements: .claude/rules/ddl-conventions.md section 8 (seed data pattern), sql-format.md section 9 (merge)
-- =============================================================================
-- Data: Demo data for the full ARW application (#25) -- real rows that stay
--       in the schema so Home, History, Environments, Target profiles and
--       Preflight have something to show:
--         * Collection "JSONPlaceholder" (env "dev" ->
--           https://jsonplaceholder.typicode.com): five more endpoints on
--           top of the Phase 0 "Get sample todo" (query params, a JSON
--           body and a Content-Type header).
--         * Collection "Sandbox" (env "dev" -> https://httpbin.org, no
--           network ACE) with a GET /bearer endpoint linked to the
--           "Sandbox bearer" credential, whose SANDBOX_BEARER static ID is
--           not in the APEX credential store -- the preflight shows the ACL
--           check failing and the credential missing, as in the mockup.
--         * Target profiles "Default -- APEX + logger" (the default: lowest
--           id), "Scheduler job" and "Plain", with db_version/apex_version
--           taken from this instance.
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25 (Phase 1 - full ARW application)
-- =============================================================================
-- Runs after data/arw_seed_phase0_endpoint.sql (release/all_data.sql), which
-- creates the JSONPlaceholder collection, its "dev" environment and the
-- "Get sample todo" endpoint.
--
-- Re-runnable: every merge matches on a natural key (names; for children
-- the parent's name plus their own name/kind) instead of a fixed id. Rows
-- matched again get their seed values back but keep their active_yn, so a
-- demo row the user deactivated stays deactivated. Only query parameters
-- are seeded -- arw_exec_api rejects path/form parameters today.
-- JSON strings use — for the em dash so the script stays ASCII.

set serveroutput on


-- =============================================================================
-- 1. CREDENTIALS
-- =============================================================================
prompt arw_credentials (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "name": "Sandbox bearer",
    "auth_type_code": "bearer",
    "apex_credential_static_id": "SANDBOX_BEARER"
  }
]
!';

  for data in (
    select jt.name                                                     as name
         , jt.auth_type_code                                           as auth_type_code
         , jt.apex_credential_static_id                                as apex_credential_static_id
      from json_table(l_json, '$[*]' columns
             name                        varchar2(200 char) path '$.name'
           , auth_type_code              varchar2(30 char)  path '$.auth_type_code'
           , apex_credential_static_id   varchar2(255 char) path '$.apex_credential_static_id'
           ) jt
  )
  loop
    merge into arw_credentials dest
    using (
      select data.name as name
        from dual
    ) src
    on (dest.name = src.name)
    when matched then
      update
         set dest.auth_type_code            = data.auth_type_code
           , dest.apex_credential_static_id = data.apex_credential_static_id
    when not matched then
      insert (
             name
           , auth_type_code
           , apex_credential_static_id
      )
      values (
             data.name
           , data.auth_type_code
           , data.apex_credential_static_id
      );
  end loop;
end;
/


-- =============================================================================
-- 2. COLLECTIONS
-- =============================================================================
prompt arw_collections (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "name": "JSONPlaceholder",
    "description": "Public fake REST API for testing and prototyping (jsonplaceholder.typicode.com)."
  },
  {
    "name": "Sandbox",
    "description": "Scratch collection on httpbin.org. The schema has no network ACE for httpbin.org yet, so its preflight shows the ACL check failing."
  }
]
!';

  for data in (
    select jt.name                                                     as name
         , jt.description                                              as description
      from json_table(l_json, '$[*]' columns
             name                        varchar2(200 char) path '$.name'
           , description                 varchar2(500 char) path '$.description'
           ) jt
  )
  loop
    merge into arw_collections dest
    using (
      select data.name as name
        from dual
    ) src
    on (dest.name = src.name)
    when matched then
      update
         set dest.description = data.description
    when not matched then
      insert (
             name
           , description
      )
      values (
             data.name
           , data.description
      );
  end loop;
end;
/


-- =============================================================================
-- 3. ENVIRONMENTS
-- =============================================================================
prompt arw_environments (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "JSONPlaceholder",
    "name": "dev",
    "base_url": "https://jsonplaceholder.typicode.com"
  },
  {
    "collection_name": "Sandbox",
    "name": "dev",
    "base_url": "https://httpbin.org"
  }
]
!';

  for data in (
    select (select min(c.collection_id)
              from arw_collections c
             where c.name = jt.collection_name)                        as collection_id
         , jt.name                                                     as name
         , jt.base_url                                                 as base_url
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , name                        varchar2(200 char)  path '$.name'
           , base_url                    varchar2(1000 char) path '$.base_url'
           ) jt
  )
  loop
    merge into arw_environments dest
    using (
      select data.collection_id as collection_id
           , data.name          as name
        from dual
    ) src
    on (dest.collection_id = src.collection_id and dest.name = src.name)
    when matched then
      update
         set dest.base_url = data.base_url
    when not matched then
      insert (
             collection_id
           , name
           , base_url
      )
      values (
             data.collection_id
           , data.name
           , data.base_url
      );
  end loop;
end;
/


-- =============================================================================
-- 4. ENDPOINTS
-- =============================================================================
prompt arw_endpoints (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "JSONPlaceholder",
    "name": "Get todos",
    "http_method": "GET",
    "url_path": "/todos"
  },
  {
    "collection_name": "JSONPlaceholder",
    "name": "Get users",
    "http_method": "GET",
    "url_path": "/users"
  },
  {
    "collection_name": "JSONPlaceholder",
    "name": "Get posts by user",
    "http_method": "GET",
    "url_path": "/posts"
  },
  {
    "collection_name": "JSONPlaceholder",
    "name": "Get comments",
    "http_method": "GET",
    "url_path": "/comments"
  },
  {
    "collection_name": "JSONPlaceholder",
    "name": "Create post",
    "http_method": "POST",
    "url_path": "/posts"
  },
  {
    "collection_name": "Sandbox",
    "name": "Bearer auth check",
    "http_method": "GET",
    "url_path": "/bearer",
    "credential_name": "Sandbox bearer"
  }
]
!';

  for data in (
    select (select min(c.collection_id)
              from arw_collections c
             where c.name = jt.collection_name)                        as collection_id
         , (select min(cr.credential_id)
              from arw_credentials cr
             where cr.name = jt.credential_name)                       as credential_id
         , jt.name                                                     as name
         , jt.http_method                                              as http_method
         , jt.url_path                                                 as url_path
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , credential_name             varchar2(200 char)  path '$.credential_name'
           , name                        varchar2(200 char)  path '$.name'
           , http_method                 varchar2(10 char)   path '$.http_method'
           , url_path                    varchar2(1000 char) path '$.url_path'
           ) jt
  )
  loop
    merge into arw_endpoints dest
    using (
      select data.collection_id as collection_id
           , data.name          as name
        from dual
    ) src
    on (dest.collection_id = src.collection_id and dest.name = src.name)
    when matched then
      update
         set dest.http_method   = data.http_method
           , dest.url_path      = data.url_path
           , dest.credential_id = data.credential_id
    when not matched then
      insert (
             collection_id
           , name
           , http_method
           , url_path
           , credential_id
      )
      values (
             data.collection_id
           , data.name
           , data.http_method
           , data.url_path
           , data.credential_id
      );
  end loop;
end;
/


-- =============================================================================
-- 5. ENDPOINT PARAMETERS (query only)
-- =============================================================================
prompt arw_endpoint_params (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "JSONPlaceholder",
    "endpoint_name": "Get posts by user",
    "param_kind_code": "query",
    "param_name": "userId",
    "param_value": "1",
    "data_type_code": "number",
    "is_required_yn": "N"
  },
  {
    "collection_name": "JSONPlaceholder",
    "endpoint_name": "Get comments",
    "param_kind_code": "query",
    "param_name": "postId",
    "param_value": "1",
    "data_type_code": "number",
    "is_required_yn": "N"
  }
]
!';

  for data in (
    select (select min(e.endpoint_id)
              from arw_endpoints   e
              join arw_collections c on c.collection_id = e.collection_id
             where c.name = jt.collection_name
               and e.name = jt.endpoint_name)                          as endpoint_id
         , jt.param_kind_code                                          as param_kind_code
         , jt.param_name                                               as param_name
         , jt.param_value                                              as param_value
         , jt.data_type_code                                           as data_type_code
         , jt.is_required_yn                                           as is_required_yn
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , endpoint_name               varchar2(200 char)  path '$.endpoint_name'
           , param_kind_code             varchar2(10 char)   path '$.param_kind_code'
           , param_name                  varchar2(200 char)  path '$.param_name'
           , param_value                 varchar2(4000 char) path '$.param_value'
           , data_type_code              varchar2(20 char)   path '$.data_type_code'
           , is_required_yn              varchar2(1 char)    path '$.is_required_yn'
           ) jt
  )
  loop
    merge into arw_endpoint_params dest
    using (
      select data.endpoint_id     as endpoint_id
           , data.param_kind_code as param_kind_code
           , data.param_name      as param_name
        from dual
    ) src
    on (    dest.endpoint_id     = src.endpoint_id
        and dest.param_kind_code = src.param_kind_code
        and dest.param_name      = src.param_name)
    when matched then
      update
         set dest.param_value    = data.param_value
           , dest.data_type_code = data.data_type_code
           , dest.is_required_yn = data.is_required_yn
    when not matched then
      insert (
             endpoint_id
           , param_kind_code
           , param_name
           , param_value
           , data_type_code
           , is_required_yn
      )
      values (
             data.endpoint_id
           , data.param_kind_code
           , data.param_name
           , data.param_value
           , data.data_type_code
           , data.is_required_yn
      );
  end loop;
end;
/


-- =============================================================================
-- 6. ENDPOINT HEADERS
-- =============================================================================
prompt arw_endpoint_headers (demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "JSONPlaceholder",
    "endpoint_name": "Create post",
    "header_name": "Content-Type",
    "header_value": "application/json",
    "is_sensitive_yn": "N"
  }
]
!';

  for data in (
    select (select min(e.endpoint_id)
              from arw_endpoints   e
              join arw_collections c on c.collection_id = e.collection_id
             where c.name = jt.collection_name
               and e.name = jt.endpoint_name)                          as endpoint_id
         , jt.header_name                                              as header_name
         , jt.header_value                                             as header_value
         , jt.is_sensitive_yn                                          as is_sensitive_yn
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , endpoint_name               varchar2(200 char)  path '$.endpoint_name'
           , header_name                 varchar2(200 char)  path '$.header_name'
           , header_value                varchar2(4000 char) path '$.header_value'
           , is_sensitive_yn             varchar2(1 char)    path '$.is_sensitive_yn'
           ) jt
  )
  loop
    merge into arw_endpoint_headers dest
    using (
      select data.endpoint_id as endpoint_id
           , data.header_name as header_name
        from dual
    ) src
    on (dest.endpoint_id = src.endpoint_id and lower(dest.header_name) = lower(src.header_name))
    when matched then
      update
         set dest.header_value    = data.header_value
           , dest.is_sensitive_yn = data.is_sensitive_yn
    when not matched then
      insert (
             endpoint_id
           , header_name
           , header_value
           , is_sensitive_yn
      )
      values (
             data.endpoint_id
           , data.header_name
           , data.header_value
           , data.is_sensitive_yn
      );
  end loop;
end;
/


-- =============================================================================
-- 7. REQUEST BODIES
-- =============================================================================
prompt arw_request_bodies (demo)

declare
  l_json clob;
begin
  -- body_template is a JSON object here; json_table returns it serialized
  -- (format json), json_serialize pretty-prints it for the Body tab and the
  -- regexp_replace turns Oracle's "key" : value into the usual "key": value.
  l_json := q'!
[
  {
    "collection_name": "JSONPlaceholder",
    "endpoint_name": "Create post",
    "content_type": "application/json",
    "body_template": {
      "title": "ARW demo post",
      "body": "Created by the ARW demo seed.",
      "userId": 1
    }
  }
]
!';

  for data in (
    select (select min(e.endpoint_id)
              from arw_endpoints   e
              join arw_collections c on c.collection_id = e.collection_id
             where c.name = jt.collection_name
               and e.name = jt.endpoint_name)                          as endpoint_id
         , jt.content_type                                             as content_type
         , regexp_replace(
               json_serialize(jt.body_template returning clob pretty)
             , '" : '
             , '": '
           )                                                           as body_template
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , endpoint_name               varchar2(200 char)  path '$.endpoint_name'
           , content_type                varchar2(200 char)  path '$.content_type'
           , body_template               clob format json    path '$.body_template'
           ) jt
  )
  loop
    merge into arw_request_bodies dest
    using (
      select data.endpoint_id as endpoint_id
        from dual
    ) src
    on (dest.endpoint_id = src.endpoint_id)
    when matched then
      update
         set dest.content_type  = data.content_type
           , dest.body_template = data.body_template
    when not matched then
      insert (
             endpoint_id
           , content_type
           , body_template
      )
      values (
             data.endpoint_id
           , data.content_type
           , data.body_template
      );
  end loop;
end;
/


-- =============================================================================
-- 8. TARGET PROFILES
-- =============================================================================
prompt arw_target_profiles (demo)

declare
  l_json         clob;
  l_db_version   arw_target_profiles.db_version%type;
  l_apex_version arw_target_profiles.apex_version%type;
begin
  -- Same format arw_target_profiles_api stores (e.g. 23ai, 26.1)
  l_db_version := dbms_db_version.version
                  || case when dbms_db_version.version >= 23 then 'ai' else 'c' end;

  select regexp_substr(r.version_no, '^[0-9]+\.[0-9]+')               as apex_version
    into l_apex_version
    from apex_release r;

  -- Array order is the insert order: the first profile gets the lowest id
  -- and is therefore arw_target_profiles_api.default_profile_id.
  l_json := q'!
[
  {
    "name": "Default — APEX + logger",
    "object_prefix": "app",
    "trace_mode_code": "logger",
    "audit_enabled_yn": "Y",
    "instance_type_code": "apex"
  },
  {
    "name": "Scheduler job",
    "object_prefix": "job",
    "trace_mode_code": "logger",
    "audit_enabled_yn": "Y",
    "instance_type_code": "apex"
  },
  {
    "name": "Plain",
    "object_prefix": "app",
    "trace_mode_code": "none",
    "audit_enabled_yn": "N",
    "instance_type_code": "apex"
  }
]
!';

  for data in (
    select jt.name                                                     as name
         , jt.object_prefix                                            as object_prefix
         , jt.target_schema                                            as target_schema
         , jt.trace_mode_code                                          as trace_mode_code
         , jt.audit_enabled_yn                                         as audit_enabled_yn
         , jt.instance_type_code                                       as instance_type_code
      from json_table(l_json, '$[*]' columns
             seq                         for ordinality
           , name                        varchar2(200 char) path '$.name'
           , object_prefix               varchar2(30 char)  path '$.object_prefix'
           , target_schema               varchar2(128 char) path '$.target_schema'
           , trace_mode_code             varchar2(20 char)  path '$.trace_mode_code'
           , audit_enabled_yn            varchar2(1 char)   path '$.audit_enabled_yn'
           , instance_type_code          varchar2(20 char)  path '$.instance_type_code'
           ) jt
     order by jt.seq
  )
  loop
    merge into arw_target_profiles dest
    using (
      select data.name as name
        from dual
    ) src
    on (dest.name = src.name)
    when matched then
      update
         set dest.object_prefix      = data.object_prefix
           , dest.target_schema      = data.target_schema
           , dest.trace_mode_code    = data.trace_mode_code
           , dest.audit_enabled_yn   = data.audit_enabled_yn
           , dest.instance_type_code = data.instance_type_code
           , dest.db_version         = l_db_version
           , dest.apex_version       = l_apex_version
    when not matched then
      insert (
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
             data.name
           , data.object_prefix
           , data.target_schema
           , data.trace_mode_code
           , data.audit_enabled_yn
           , data.instance_type_code
           , l_db_version
           , l_apex_version
      );
  end loop;
end;
/

commit;


-- =============================================================================
-- 9. SUMMARY
-- =============================================================================
begin
  for l_rec in (
    select s.collection_id                                             as collection_id
         , s.name                                                      as name
         , s.endpoint_count                                            as endpoint_count
         , s.environment_count                                         as environment_count
      from arw_collection_summary_vw s
     where s.name in ('JSONPlaceholder', 'Sandbox')
     order by s.collection_id
  )
  loop
    dbms_output.put_line('collection ' || l_rec.collection_id || ' ' || l_rec.name
                         || ': ' || l_rec.endpoint_count || ' endpoints, '
                         || l_rec.environment_count || ' environments');
  end loop;

  -- Same rule as arw_target_profiles_api.default_profile_id, inlined so the
  -- seed does not depend on the packages being installed.
  for l_rec in (
    select min(tp.target_profile_id)                                   as target_profile_id
      from arw_target_profiles tp
     where tp.active_yn = 'Y'
  )
  loop
    dbms_output.put_line('default target profile = ' || l_rec.target_profile_id);
  end loop;
end;
/
