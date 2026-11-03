-- Implements: .claude/rules/ddl-conventions.md section 8 (seed data pattern), sql-format.md section 9 (merge)
-- =============================================================================
-- Data: Phase 2 demo data -- simple auth and environments with real public
--       APIs the schema has a network ACE for:
--         * Collection "Sandbox" (httpbin.org): environments "dev" and
--           "prod" on the same host with different {{variables}} (user,
--           password, token, api_key). httpbin echoes what it receives, so
--           switching the environment shows a different token/user in the
--           response. One request per auth type: basic, bearer, API key in
--           a header and in the query string.
--         * Collection "DummyJSON" (dummyjson.com): a real login flow --
--           "1. Login" returns an accessToken; paste it into the "token"
--           variable of the "dev" environment and "2. Current user" answers
--           200 with Bearer {{token}}.
--
-- @author  Angel Flores (Developer)
-- @created November 03, 2026
-- @ticket  PHASE2-simplified
-- =============================================================================
-- Runs after data/arw_seed_demo.sql (release/all_data.sql), which creates the
-- Sandbox collection, its "dev" environment and "Bearer auth check".
--
-- Re-runnable: every merge matches on a natural key (names) instead of a
-- fixed id, like arw_seed_demo.sql. Secrets are demo values, visible on
-- purpose (beta); password/token/api_key variables are is_secret_yn = Y so
-- generated code never embeds them.

set serveroutput on


-- =============================================================================
-- 1. COLLECTIONS
-- =============================================================================
prompt arw_collections (phase 2 demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "name": "Sandbox",
    "description": "httpbin.org: one request per auth type (basic, bearer, API key). dev and prod use different {{variables}} -- switch the environment and Send again."
  },
  {
    "name": "DummyJSON",
    "description": "dummyjson.com: Send 1. Login, copy accessToken into the token variable of dev, then Send 2. Current user."
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
-- 2. ENVIRONMENTS
-- =============================================================================
prompt arw_environments (phase 2 demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "Sandbox",
    "name": "dev",
    "base_url": "https://httpbin.org"
  },
  {
    "collection_name": "Sandbox",
    "name": "prod",
    "base_url": "https://httpbin.org"
  },
  {
    "collection_name": "DummyJSON",
    "name": "dev",
    "base_url": "https://dummyjson.com"
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
-- 3. ENVIRONMENT VARIABLES
-- =============================================================================
prompt arw_env_variables (phase 2 demo)

declare
  l_json clob;
begin
  -- DummyJSON "token" starts empty: the user pastes the accessToken that
  -- "1. Login" returns. A re-run keeps whatever value was pasted.
  l_json := q'!
[
  { "collection_name": "Sandbox",   "environment_name": "dev",  "var_name": "env",      "var_value": "dev",            "is_secret_yn": "N" },
  { "collection_name": "Sandbox",   "environment_name": "dev",  "var_name": "user",     "var_value": "demo",           "is_secret_yn": "N" },
  { "collection_name": "Sandbox",   "environment_name": "dev",  "var_name": "password", "var_value": "demo123",        "is_secret_yn": "Y" },
  { "collection_name": "Sandbox",   "environment_name": "dev",  "var_name": "token",    "var_value": "dev-token-123",  "is_secret_yn": "Y" },
  { "collection_name": "Sandbox",   "environment_name": "dev",  "var_name": "api_key",  "var_value": "dev-key-111",    "is_secret_yn": "Y" },
  { "collection_name": "Sandbox",   "environment_name": "prod", "var_name": "env",      "var_value": "prod",           "is_secret_yn": "N" },
  { "collection_name": "Sandbox",   "environment_name": "prod", "var_name": "user",     "var_value": "admin",          "is_secret_yn": "N" },
  { "collection_name": "Sandbox",   "environment_name": "prod", "var_name": "password", "var_value": "prod-pass-456",  "is_secret_yn": "Y" },
  { "collection_name": "Sandbox",   "environment_name": "prod", "var_name": "token",    "var_value": "prod-token-456", "is_secret_yn": "Y" },
  { "collection_name": "Sandbox",   "environment_name": "prod", "var_name": "api_key",  "var_value": "prod-key-222",   "is_secret_yn": "Y" },
  { "collection_name": "DummyJSON", "environment_name": "dev",  "var_name": "username", "var_value": "emilys",         "is_secret_yn": "N" },
  { "collection_name": "DummyJSON", "environment_name": "dev",  "var_name": "password", "var_value": "emilyspass",     "is_secret_yn": "Y" },
  { "collection_name": "DummyJSON", "environment_name": "dev",  "var_name": "token",    "var_value": null,             "is_secret_yn": "Y" }
]
!';

  for data in (
    select (select min(v.environment_id)
              from arw_environments v
              join arw_collections  c on c.collection_id = v.collection_id
             where c.name = jt.collection_name
               and v.name = jt.environment_name)                       as environment_id
         , jt.var_name                                                 as var_name
         , jt.var_value                                                as var_value
         , jt.is_secret_yn                                             as is_secret_yn
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , environment_name            varchar2(200 char)  path '$.environment_name'
           , var_name                    varchar2(200 char)  path '$.var_name'
           , var_value                   varchar2(4000 char) path '$.var_value'
           , is_secret_yn                varchar2(1 char)    path '$.is_secret_yn'
           ) jt
  )
  loop
    merge into arw_env_variables dest
    using (
      select data.environment_id as environment_id
           , data.var_name       as var_name
        from dual
    ) src
    on (dest.environment_id = src.environment_id and dest.var_name = src.var_name)
    when matched then
      update
         set dest.var_value    = coalesce(data.var_value, dest.var_value)
           , dest.is_secret_yn = data.is_secret_yn
    when not matched then
      insert (
             environment_id
           , var_name
           , var_value
           , is_secret_yn
      )
      values (
             data.environment_id
           , data.var_name
           , data.var_value
           , data.is_secret_yn
      );
  end loop;
end;
/


-- =============================================================================
-- 4. ENDPOINTS (with simple auth)
-- =============================================================================
prompt arw_endpoints (phase 2 demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  {
    "collection_name": "Sandbox",
    "name": "Bearer auth check",
    "http_method": "GET",
    "url_path": "/bearer",
    "auth_type_code": "bearer",
    "auth_token": "{{token}}"
  },
  {
    "collection_name": "Sandbox",
    "name": "Basic auth check",
    "http_method": "GET",
    "url_path": "/basic-auth/{{user}}/{{password}}",
    "auth_type_code": "basic",
    "auth_username": "{{user}}",
    "auth_password": "{{password}}"
  },
  {
    "collection_name": "Sandbox",
    "name": "API key in header",
    "http_method": "GET",
    "url_path": "/headers",
    "auth_type_code": "api_key",
    "auth_key_name": "X-Api-Key",
    "auth_key_value": "{{api_key}}",
    "auth_key_location_code": "header"
  },
  {
    "collection_name": "Sandbox",
    "name": "API key in query",
    "http_method": "GET",
    "url_path": "/get",
    "auth_type_code": "api_key",
    "auth_key_name": "api_key",
    "auth_key_value": "{{api_key}}",
    "auth_key_location_code": "query"
  },
  {
    "collection_name": "Sandbox",
    "name": "Which environment?",
    "http_method": "GET",
    "url_path": "/get"
  },
  {
    "collection_name": "DummyJSON",
    "name": "1. Login",
    "http_method": "POST",
    "url_path": "/auth/login"
  },
  {
    "collection_name": "DummyJSON",
    "name": "2. Current user",
    "http_method": "GET",
    "url_path": "/auth/me",
    "auth_type_code": "bearer",
    "auth_token": "{{token}}"
  },
  {
    "collection_name": "DummyJSON",
    "name": "Products",
    "http_method": "GET",
    "url_path": "/products"
  },
  {
    "collection_name": "DummyJSON",
    "name": "Search products",
    "http_method": "GET",
    "url_path": "/products/search"
  }
]
!';

  for data in (
    select (select min(c.collection_id)
              from arw_collections c
             where c.name = jt.collection_name)                        as collection_id
         , jt.name                                                     as name
         , jt.http_method                                              as http_method
         , jt.url_path                                                 as url_path
         , jt.auth_type_code                                           as auth_type_code
         , jt.auth_username                                            as auth_username
         , jt.auth_password                                            as auth_password
         , jt.auth_token                                               as auth_token
         , jt.auth_key_name                                            as auth_key_name
         , jt.auth_key_value                                           as auth_key_value
         , jt.auth_key_location_code                                   as auth_key_location_code
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , name                        varchar2(200 char)  path '$.name'
           , http_method                 varchar2(10 char)   path '$.http_method'
           , url_path                    varchar2(1000 char) path '$.url_path'
           , auth_type_code              varchar2(20 char)   path '$.auth_type_code'    default 'none' on empty
           , auth_username               varchar2(400 char)  path '$.auth_username'
           , auth_password               varchar2(4000 char) path '$.auth_password'
           , auth_token                  varchar2(4000 char) path '$.auth_token'
           , auth_key_name               varchar2(200 char)  path '$.auth_key_name'
           , auth_key_value              varchar2(4000 char) path '$.auth_key_value'
           , auth_key_location_code      varchar2(10 char)   path '$.auth_key_location_code' default 'header' on empty
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
         set dest.http_method            = data.http_method
           , dest.url_path               = data.url_path
           , dest.credential_id          = null
           , dest.auth_type_code         = data.auth_type_code
           , dest.auth_username          = data.auth_username
           , dest.auth_password          = data.auth_password
           , dest.auth_token             = data.auth_token
           , dest.auth_key_name          = data.auth_key_name
           , dest.auth_key_value         = data.auth_key_value
           , dest.auth_key_location_code = data.auth_key_location_code
    when not matched then
      insert (
             collection_id
           , name
           , http_method
           , url_path
           , auth_type_code
           , auth_username
           , auth_password
           , auth_token
           , auth_key_name
           , auth_key_value
           , auth_key_location_code
      )
      values (
             data.collection_id
           , data.name
           , data.http_method
           , data.url_path
           , data.auth_type_code
           , data.auth_username
           , data.auth_password
           , data.auth_token
           , data.auth_key_name
           , data.auth_key_value
           , data.auth_key_location_code
      );
  end loop;
end;
/


-- =============================================================================
-- 5. ENDPOINT PARAMETERS (query only)
-- =============================================================================
prompt arw_endpoint_params (phase 2 demo)

declare
  l_json clob;
begin
  l_json := q'!
[
  { "collection_name": "Sandbox",   "endpoint_name": "Which environment?", "param_name": "env",   "param_value": "{{env}}", "data_type_code": "varchar2" },
  { "collection_name": "DummyJSON", "endpoint_name": "Products",           "param_name": "limit", "param_value": "5",       "data_type_code": "number" },
  { "collection_name": "DummyJSON", "endpoint_name": "Search products",    "param_name": "q",     "param_value": "phone",   "data_type_code": "varchar2" },
  { "collection_name": "DummyJSON", "endpoint_name": "Search products",    "param_name": "limit", "param_value": "3",       "data_type_code": "number" }
]
!';

  for data in (
    select (select min(e.endpoint_id)
              from arw_endpoints   e
              join arw_collections c on c.collection_id = e.collection_id
             where c.name = jt.collection_name
               and e.name = jt.endpoint_name)                          as endpoint_id
         , jt.param_name                                               as param_name
         , jt.param_value                                              as param_value
         , jt.data_type_code                                           as data_type_code
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , endpoint_name               varchar2(200 char)  path '$.endpoint_name'
           , param_name                  varchar2(200 char)  path '$.param_name'
           , param_value                 varchar2(4000 char) path '$.param_value'
           , data_type_code              varchar2(20 char)   path '$.data_type_code'
           ) jt
  )
  loop
    merge into arw_endpoint_params dest
    using (
      select data.endpoint_id as endpoint_id
           , 'query'          as param_kind_code
           , data.param_name  as param_name
        from dual
    ) src
    on (    dest.endpoint_id     = src.endpoint_id
        and dest.param_kind_code = src.param_kind_code
        and dest.param_name      = src.param_name)
    when matched then
      update
         set dest.param_value    = data.param_value
           , dest.data_type_code = data.data_type_code
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
           , 'query'
           , data.param_name
           , data.param_value
           , data.data_type_code
           , 'N'
      );
  end loop;
end;
/


-- =============================================================================
-- 6. REQUEST BODIES
-- =============================================================================
prompt arw_request_bodies (phase 2 demo)

declare
  l_json clob;
begin
  -- {{username}} / {{password}} resolve from the environment at Send time
  l_json := q'!
[
  {
    "collection_name": "DummyJSON",
    "endpoint_name": "1. Login",
    "content_type": "application/json",
    "body_template": "{\n  \"username\": \"{{username}}\",\n  \"password\": \"{{password}}\",\n  \"expiresInMins\": 60\n}"
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
         , jt.body_template                                            as body_template
      from json_table(l_json, '$[*]' columns
             collection_name             varchar2(200 char)  path '$.collection_name'
           , endpoint_name               varchar2(200 char)  path '$.endpoint_name'
           , content_type                varchar2(200 char)  path '$.content_type'
           , body_template               clob                path '$.body_template'
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
-- 7. SUMMARY
-- =============================================================================
begin
  for l_rec in (
    select c.name                                                      as collection_name
         , (select count(1)
              from arw_endpoints e
             where e.collection_id = c.collection_id
               and e.active_yn = 'Y')                                  as endpoint_count
         , (select count(1)
              from arw_environments v
             where v.collection_id = c.collection_id
               and v.active_yn = 'Y')                                  as environment_count
      from arw_collections c
     where c.name in ('Sandbox', 'DummyJSON')
     order by c.name
  )
  loop
    dbms_output.put_line('collection ' || l_rec.collection_name || ': '
                         || l_rec.endpoint_count || ' endpoints, '
                         || l_rec.environment_count || ' environments');
  end loop;
end;
/
