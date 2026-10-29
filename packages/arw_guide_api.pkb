-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_guide_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_collection_name  constant arw_collections.name%type   := 'Guide examples';
  gc_no_env_name      constant arw_collections.name%type   := 'No environment';
  -- Two environments with the same paths on different APIs, so switching
  -- the environment visibly changes where a saved request goes.
  gc_environments constant varchar2(4000 char) := q'~
[
  { "name": "dev",  "base_url": "https://jsonplaceholder.typicode.com",
    "variables": [ { "name": "api_key", "value": "demo-key-123" }
                 , { "name": "user_id", "value": "2" }
                 , { "name": "author",  "value": "ARW guide (dev)" } ] },
  { "name": "prod", "base_url": "https://dummyjson.com",
    "variables": [ { "name": "api_key", "value": "prod-key-456" }
                 , { "name": "user_id", "value": "3" }
                 , { "name": "author",  "value": "ARW guide (prod)" } ] }
]
~';

  -- One entry per Guide card, in four sections: quick_get (GET with a
  -- full URL -- the main use), collections (saved requests on {{base_url}},
  -- params and {{variables}}), sending_data (DELETE/POST/PUT/PATCH, simplest
  -- first) and preflight. url is a full URL (sent as written) or a path
  -- behind the environment's {{base_url}}; body is a JSON value sent as the
  -- request body. "no_env": true puts the example in the "No environment"
  -- sub-collection, so a full URL on an environment's host stays a full URL
  -- (arw_endpoint_api would store it as a path otherwise). An ampersand is
  -- written \u0026 so SQL*Plus substitution never prompts. Hosts other than
  -- jsonplaceholder need scripts/grant_guide_hosts.sql; catfact.ninja is
  -- left without an ACL on purpose.
  gc_examples constant varchar2(32767 char) := q'~
[
  { "code": "basics_full_url", "category": "quick_get", "seq": 10, "no_env": true,
    "title": "List of records",
    "summary": "Paste a URL, press Send. Returns an array.",
    "method": "GET", "url": "https://jsonplaceholder.typicode.com/users" },
  { "code": "qg_one", "category": "quick_get", "seq": 20, "no_env": true,
    "title": "One record",
    "summary": "An id at the end of the URL returns a single object.",
    "method": "GET", "url": "https://jsonplaceholder.typicode.com/users/1" },
  { "code": "qg_filter", "category": "quick_get", "seq": 30, "no_env": true,
    "title": "Filter with ?params",
    "summary": "Query params can go straight in the URL.",
    "method": "GET", "url": "https://jsonplaceholder.typicode.com/comments?postId=1" },
  { "code": "qg_product", "category": "quick_get", "seq": 40, "no_env": true,
    "title": "Another API",
    "summary": "Any public API works once its host has a network ACL.",
    "method": "GET", "url": "https://dummyjson.com/products/1" },
  { "code": "qg_fields", "category": "quick_get", "seq": 50, "no_env": true,
    "title": "Pick fields, limit rows",
    "summary": "Two params: 5 rows, only title and price.",
    "method": "GET", "url": "https://dummyjson.com/products?limit=5\u0026select=title,price" },
  { "code": "qg_search", "category": "quick_get", "seq": 60, "no_env": true,
    "title": "Search",
    "summary": "A search endpoint with q=phone.",
    "method": "GET", "url": "https://dummyjson.com/products/search?q=phone\u0026limit=3" },
  { "code": "qg_image", "category": "quick_get", "seq": 70, "no_env": true,
    "title": "Image (PNG)",
    "summary": "Files are previewed in the Response tab.",
    "method": "GET", "url": "https://dummyjson.com/image/400x200/008080/ffffff?text=ARW" },
  { "code": "qg_photo", "category": "quick_get", "seq": 80, "no_env": true,
    "title": "Photo (JPEG)",
    "summary": "Another image type.",
    "method": "GET", "url": "https://httpbin.org/image/jpeg" },
  { "code": "qg_audio", "category": "quick_get", "seq": 90, "no_env": true,
    "title": "Audio (MP3)",
    "summary": "Plays right in the Response tab.",
    "method": "GET", "url": "https://upload.wikimedia.org/wikipedia/commons/transcoded/c/c8/Example.ogg/Example.ogg.mp3" },
  { "code": "qg_pdf", "category": "quick_get", "seq": 100, "no_env": true,
    "title": "File (PDF)",
    "summary": "Shown inline, with a download link.",
    "method": "GET", "url": "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf" },
  { "code": "qg_xml", "category": "quick_get", "seq": 110, "no_env": true,
    "title": "XML",
    "summary": "Text that is not JSON is shown as is.",
    "method": "GET", "url": "https://httpbin.org/xml" },

  { "code": "basics_path", "category": "collections", "seq": 10,
    "title": "Path + {{base_url}}",
    "summary": "A saved request keeps only the path; the environment adds the base.",
    "method": "GET", "url": "/posts/1" },
  { "code": "coll_switch_env", "category": "collections", "seq": 20,
    "title": "Same request, two environments",
    "summary": "dev = jsonplaceholder, prod = dummyjson. Change Environment, Send again.",
    "method": "GET", "url": "/users/1" },
  { "code": "basics_query", "category": "collections", "seq": 30,
    "title": "Saved query params",
    "summary": "Params tab, kind query: sends ?userId=1.",
    "method": "GET", "url": "/posts",
    "params": [ { "kind": "query", "name": "userId", "value": "1" } ] },
  { "code": "basics_path_param", "category": "collections", "seq": 40,
    "title": "Path param",
    "summary": "{id} in the URL takes its value from the Params tab.",
    "method": "GET", "url": "/posts/{id}/comments",
    "params": [ { "kind": "path", "name": "id", "value": "1" } ] },
  { "code": "coll_var_url", "category": "collections", "seq": 50,
    "title": "Variable in the URL",
    "summary": "{{user_id}} comes from the environment's variables.",
    "method": "GET", "url": "/users/{{user_id}}" },
  { "code": "vars_header", "category": "collections", "seq": 60,
    "title": "Variable in a header",
    "summary": "Headers tab: X-Api-Key = {{api_key}}.",
    "method": "GET", "url": "/users/1",
    "headers": [ { "name": "X-Api-Key", "value": "{{api_key}}" } ] },

  { "code": "send_delete", "category": "sending_data", "seq": 10, "no_env": true,
    "title": "DELETE (no body)",
    "summary": "The simplest write: just the method and the URL.",
    "method": "DELETE", "url": "https://jsonplaceholder.typicode.com/posts/1" },
  { "code": "send_post", "category": "sending_data", "seq": 20, "no_env": true,
    "title": "POST JSON",
    "summary": "Body tab holds the JSON; the answer has the new id.",
    "method": "POST", "url": "https://dummyjson.com/products/add",
    "body": { "title": "ARW mug", "price": 9.99 } },
  { "code": "send_put", "category": "sending_data", "seq": 30, "no_env": true,
    "title": "PUT (replace)",
    "summary": "Sends the whole record.",
    "method": "PUT", "url": "https://jsonplaceholder.typicode.com/posts/1",
    "body": { "id": 1, "title": "Replaced", "body": "Full update", "userId": 1 } },
  { "code": "send_patch", "category": "sending_data", "seq": 40, "no_env": true,
    "title": "PATCH (one field)",
    "summary": "Sends only the field that changes.",
    "method": "PATCH", "url": "https://dummyjson.com/products/1",
    "body": { "title": "Renamed by ARW" } },
  { "code": "coll_post_vars", "category": "sending_data", "seq": 50,
    "title": "POST with {{variables}}",
    "summary": "Variables work inside the body too (environment dev).",
    "method": "POST", "url": "/posts",
    "body": { "title": "Hello from {{author}}", "body": "Saved request", "userId": 1 } },

  { "code": "preflight_blocked", "category": "preflight", "seq": 10, "no_env": true,
    "title": "Blocked host",
    "summary": "No network ACL for this host on purpose: Send is refused, Preflight shows the fix.",
    "method": "GET", "url": "https://catfact.ninja/fact" }
]
~';








  -- ===========================================================================
  -- FUNCTION: guide_collection_id (private)
  -- ===========================================================================
  /**
   * Returns the "Guide examples" collection, creating it when missing, and
   * puts its environments (gc_environments: dev on jsonplaceholder, prod on
   * dummyjson) and their variables back to their original values.
   *
   * @example
   * -- Private: exercised through install_examples.
   *
   * @issue   #25 (Phase 1 - in-app guide)
   *
   * @author  Angel Flores (Developer)
   * @created October 24, 2026
   *
   * @return arw_collections.collection_id%type  Identifier of the Guide examples collection
   */
  function guide_collection_id
  return arw_collections.collection_id%type
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'guide_collection_id';
    l_params         logger.tab_param;
    l_collection_id  arw_collections.collection_id%type;
    l_environment_id arw_environments.environment_id%type;
    l_variable_id    arw_env_variables.variable_id%type;
  begin
    logger.log('START', l_scope, null, l_params);

    select min(c.collection_id)                            as collection_id
      into l_collection_id
      from arw_collections c
     where c.name = gc_collection_name
       and c.parent_collection_id is null
       and c.active_yn = 'Y';

    if l_collection_id is null then
      l_collection_id := arw_collections_api.create_collection(
                             p_name                     => gc_collection_name
                           , p_description              => 'Ready-to-send examples from the Guide -- Reset examples restores them.'
                         );
    end if;

    for l_env in (
      select je.env_name                                   as env_name
           , je.base_url                                   as base_url
           , je.variables_json                             as variables_json
        from json_table(gc_environments, '$[*]' columns
               env_name       varchar2(100 char)  path '$.name'
             , base_url       varchar2(1000 char) path '$.base_url'
             , variables_json clob format json    path '$.variables'
             ) je
    )
    loop
      select min(v.environment_id)                         as environment_id
        into l_environment_id
        from arw_environments v
       where v.collection_id = l_collection_id
         and v.name = l_env.env_name
         and v.active_yn = 'Y';

      if l_environment_id is null then
        l_environment_id := arw_environments_api.create_environment(
                                p_collection_id         => l_collection_id
                              , p_name                  => l_env.env_name
                              , p_base_url              => l_env.base_url
                            );
      else
        arw_environments_api.update_environment(
            p_environment_id                    => l_environment_id
          , p_name                              => l_env.env_name
          , p_base_url                          => l_env.base_url
        );
      end if;

      for l_var in (
        select jv.var_name                                 as var_name
             , jv.var_value                                as var_value
          from json_table(l_env.variables_json, '$[*]' columns
                 var_name  varchar2(100 char)  path '$.name'
               , var_value varchar2(4000 char) path '$.value'
               ) jv
      )
      loop
        l_variable_id := arw_environments_api.set_variable(
                             p_environment_id           => l_environment_id
                           , p_var_name                 => l_var.var_name
                           , p_var_value                => l_var.var_value
                         );
      end loop;
    end loop;

    logger.append_param(l_params, 'l_collection_id', l_collection_id);
    logger.log('END', l_scope, null, l_params);

    return l_collection_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end guide_collection_id;








  -- ===========================================================================
  -- FUNCTION: no_env_collection_id (private)
  -- ===========================================================================
  /**
   * Returns the "No environment" sub-collection of the Guide examples
   * collection, creating it when missing. It has no environment on
   * purpose: its full-URL examples are sent exactly as written.
   *
   * @example
   * -- Private: exercised through install_examples.
   *
   * @issue   #25 (Phase 1 - in-app guide)
   *
   * @author  Angel Flores (Developer)
   * @created October 24, 2026
   *
   * @param p_parent_collection_id The Guide examples collection
   * @return arw_collections.collection_id%type  Identifier of the No environment sub-collection
   */
  function no_env_collection_id(
      p_parent_collection_id                    in arw_collections.collection_id%type
  )
  return arw_collections.collection_id%type
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'no_env_collection_id';
    l_params        logger.tab_param;
    l_collection_id arw_collections.collection_id%type;
  begin
    logger.append_param(l_params, 'p_parent_collection_id', p_parent_collection_id);
    logger.log('START', l_scope, null, l_params);

    select min(c.collection_id)                            as collection_id
      into l_collection_id
      from arw_collections c
     where c.name = gc_no_env_name
       and c.parent_collection_id = p_parent_collection_id
       and c.active_yn = 'Y';

    if l_collection_id is null then
      l_collection_id := arw_collections_api.create_collection(
                             p_name                     => gc_no_env_name
                           , p_description              => 'Guide examples sent with a full URL -- no environment needed.'
                           , p_parent_collection_id     => p_parent_collection_id
                         );
    end if;

    logger.append_param(l_params, 'l_collection_id', l_collection_id);
    logger.log('END', l_scope, null, l_params);

    return l_collection_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end no_env_collection_id;








  -- ===========================================================================
  -- PROCEDURE: reset_request_parts (private)
  -- ===========================================================================
  /**
   * Replaces an example endpoint's params, headers and body with the ones
   * in its gc_examples entry: every active param and header is removed,
   * then the example's own are added; a null body removes the body.
   *
   * @example
   * -- Private: exercised through install_examples.
   *
   * @issue   #25 (Phase 1 - in-app guide)
   *
   * @author  Angel Flores (Developer)
   * @created October 24, 2026
   *
   * @param p_endpoint_id Example endpoint to reset
   * @param p_params_json JSON array of { kind, name, value }; null for none
   * @param p_headers_json JSON array of { name, value }; null for none
   * @param p_body_json JSON value sent as the body; null for no body
   */
  procedure reset_request_parts(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
    , p_params_json                             in clob
    , p_headers_json                            in clob
    , p_body_json                               in clob
  )
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'reset_request_parts';
    l_params    logger.tab_param;
    l_id        number;
    l_body      clob;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    for l_rec in (
      select p.param_id                                    as param_id
        from arw_endpoint_params p
       where p.endpoint_id = p_endpoint_id
         and p.active_yn = 'Y'
    )
    loop
      arw_endpoint_api.remove_param(
          p_param_id                            => l_rec.param_id
      );
    end loop;

    for l_rec in (
      select h.header_id                                   as header_id
        from arw_endpoint_headers h
       where h.endpoint_id = p_endpoint_id
         and h.active_yn = 'Y'
    )
    loop
      arw_endpoint_api.remove_header(
          p_header_id                           => l_rec.header_id
      );
    end loop;

    if p_params_json is not null then
      for l_rec in (
        select jt.param_kind_code                          as param_kind_code
             , jt.param_name                               as param_name
             , jt.param_value                              as param_value
          from json_table(p_params_json, '$[*]' columns
                 param_kind_code varchar2(20 char)   path '$.kind'
               , param_name      varchar2(200 char)  path '$.name'
               , param_value     varchar2(4000 char) path '$.value'
               ) jt
      )
      loop
        l_id := arw_endpoint_api.add_param(
                    p_endpoint_id               => p_endpoint_id
                  , p_param_kind_code           => l_rec.param_kind_code
                  , p_param_name                => l_rec.param_name
                  , p_param_value               => l_rec.param_value
                );
      end loop;
    end if;

    if p_headers_json is not null then
      for l_rec in (
        select jt.header_name                              as header_name
             , jt.header_value                             as header_value
          from json_table(p_headers_json, '$[*]' columns
                 header_name     varchar2(200 char)  path '$.name'
               , header_value    varchar2(4000 char) path '$.value'
               ) jt
      )
      loop
        l_id := arw_endpoint_api.add_header(
                    p_endpoint_id               => p_endpoint_id
                  , p_header_name               => l_rec.header_name
                  , p_header_value              => l_rec.header_value
                );
      end loop;
    end if;

    if p_body_json is not null then
      select json_serialize(p_body_json returning clob pretty)
        into l_body
        from dual;
    end if;


    -- =========================================================================
    -- A null body removes it (see arw_endpoint_api.set_body).
    -- =========================================================================

    arw_endpoint_api.set_body(
        p_endpoint_id                           => p_endpoint_id
      , p_content_type                          => 'application/json'
      , p_body_template                         => l_body
    );
    -- =========================================================================

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end reset_request_parts;








  -- ===========================================================================
  -- PROCEDURE: install_examples
  -- ===========================================================================
  /**
   * Installs the Guide examples, or restores them after the user edited
   * them: the "Guide examples" collection and its dev environment, one
   * endpoint per gc_examples entry (method, URL, params, headers, body put
   * back to the original) and its card row in arw_guide_examples.
   * Re-runnable: existing examples are matched by example_code and
   * updated, never duplicated. Backs data/arw_seed_guide.sql and the
   * Reset examples button on page 910.
   *
   * @example
   * begin
   *   arw_guide_api.install_examples;
   * end;
   * /
   *
   * @issue   #25 (Phase 1 - in-app guide)
   *
   * @author  Angel Flores (Developer)
   * @created October 24, 2026
   */
  procedure install_examples
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'install_examples';
    l_params        logger.tab_param;
    l_collection_id arw_collections.collection_id%type;
    l_no_env_id     arw_collections.collection_id%type;
    l_target_id     arw_collections.collection_id%type;
    l_endpoint_id   arw_endpoints.endpoint_id%type;
  begin
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Collection, dev environment and its api_key variable.
    -- =========================================================================

    l_collection_id := guide_collection_id;
    l_no_env_id     := no_env_collection_id(
                           p_parent_collection_id       => l_collection_id
                       );
    -- =========================================================================

    for l_rec in (
      select jt.example_code                               as example_code
           , jt.category_code                              as category_code
           , jt.display_seq                                as display_seq
           , jt.title                                      as title
           , jt.summary                                    as summary
           , jt.http_method                                as http_method
           , jt.url_path                                   as url_path
           , jt.params_json                                as params_json
           , jt.headers_json                               as headers_json
           , jt.body_json                                  as body_json
           , case jt.no_env_flag
               when 'true' then 'Y'
               else 'N'
             end                                           as no_env_yn
        from json_table(gc_examples, '$[*]' columns
               example_code  varchar2(50 char)   path '$.code'
             , category_code varchar2(30 char)   path '$.category'
             , display_seq   number              path '$.seq'
             , title         varchar2(200 char)  path '$.title'
             , summary       varchar2(500 char)  path '$.summary'
             , http_method   varchar2(10 char)   path '$.method'
             , url_path      varchar2(1000 char) path '$.url'
             , params_json   clob format json    path '$.params'
             , headers_json  clob format json    path '$.headers'
             , body_json     clob format json    path '$.body'
             , no_env_flag   varchar2(5 char)    path '$.no_env'
             ) jt
    )
    loop
      l_target_id := case
                       when l_rec.no_env_yn = 'Y' then l_no_env_id
                       else l_collection_id
                     end;

      select min(e.endpoint_id)                            as endpoint_id
        into l_endpoint_id
        from arw_guide_examples g
        join arw_endpoints      e on e.endpoint_id = g.endpoint_id
                                 and e.active_yn = 'Y'
       where g.example_code = l_rec.example_code;

      if l_endpoint_id is null then
        l_endpoint_id := arw_endpoint_api.create_endpoint(
                             p_collection_id            => l_target_id
                           , p_name                     => l_rec.title
                           , p_http_method              => l_rec.http_method
                           , p_url_path                 => l_rec.url_path
                         );
      else
        arw_endpoint_api.update_endpoint(
            p_endpoint_id                       => l_endpoint_id
          , p_name                              => l_rec.title
          , p_http_method                       => l_rec.http_method
          , p_url_path                          => l_rec.url_path
          , p_credential_id                     => null
          , p_timeout_secs                      => 30
          , p_runtime_target_code               => 'apex'
          , p_engine_code                       => 'apex_web_service'
          , p_collection_id                     => l_target_id
        );
      end if;


      -- =======================================================================
      -- Params, headers and body back to the example's own.
      -- =======================================================================

      reset_request_parts(
          p_endpoint_id                         => l_endpoint_id
        , p_params_json                         => l_rec.params_json
        , p_headers_json                        => l_rec.headers_json
        , p_body_json                           => l_rec.body_json
      );
      -- =======================================================================

      merge into arw_guide_examples dest
      using (
        select l_rec.example_code as example_code
          from dual
      ) src
      on (dest.example_code = src.example_code)
      when matched then
        update
           set dest.category_code = l_rec.category_code
             , dest.title         = l_rec.title
             , dest.summary       = l_rec.summary
             , dest.display_seq   = l_rec.display_seq
             , dest.endpoint_id   = l_endpoint_id
             , dest.active_yn     = 'Y'
      when not matched then
        insert (
               example_code
             , category_code
             , title
             , summary
             , display_seq
             , endpoint_id
        )
        values (
               src.example_code
             , l_rec.category_code
             , l_rec.title
             , l_rec.summary
             , l_rec.display_seq
             , l_endpoint_id
        );
    end loop;

    -- Cards dropped from gc_examples disappear from the Guide
    update arw_guide_examples g
       set g.active_yn = 'N'
     where g.active_yn = 'Y'
       and g.example_code not in (
             select jt.example_code
               from json_table(gc_examples, '$[*]' columns example_code varchar2(50 char) path '$.code') jt
           );

    logger.append_param(l_params, 'l_collection_id', l_collection_id);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end install_examples;


end arw_guide_api;
/
