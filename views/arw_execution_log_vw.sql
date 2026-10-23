-- Implements: .claude/rules/sql-format.md (views and WITH clause)
-- =============================================================================
-- View:    arw_execution_log_vw
-- Purpose: Execution history for History (page 400/410), the Home "recent
--          executions" list and the endpoint editor Response chips: one row
--          per active execution of an active endpoint, with display-ready
--          status data (label, class, reason phrase), the most meaningful
--          ORA- error code, the response Content-Type and size.
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25 (Phase 1 - full ARW application)
-- =============================================================================
-- Notes:
--   * status_class drives the arw-chip modifier (ok = 2xx, warn = 3xx,
--     error = 4xx/5xx or a call that never got an HTTP response, info =
--     anything else); status_label is the HTTP status, or an em dash when
--     the call never got one.
--   * error_code skips the generic wrappers ORA-29273 (HTTP request failed)
--     and ORA-06512 (at line) so the root cause (e.g. ORA-24247) surfaces;
--     it falls back to the first ORA- code when only wrappers are present.
--   * response_size_bytes is null for failed calls: response_body_clob then
--     holds the error text, not a response. For text bodies it is the
--     character length (equal to bytes for ASCII/JSON payloads).
--   * display_path mirrors arw_endpoint_api.display_url without the
--     {{base_url}} prefix, built from the endpoint's current active query
--     parameters (arw_executions does not store the resolved URL). chr(38)
--     is the ampersand, kept out of the source so SQL*Plus substitution
--     never prompts.
create or replace view arw_execution_log_vw
as
with w_base as (
  select x.execution_id                                                as execution_id
       , x.endpoint_id                                                 as endpoint_id
       , e.name                                                        as endpoint_name
       , e.collection_id                                               as collection_id
       , e.http_method                                                 as http_method
       , e.url_path                                                    as url_path
       , x.environment_id                                              as environment_id
       , x.request_status_code                                         as request_status_code
       , x.http_status_code                                            as http_status_code
       , x.elapsed_ms                                                  as elapsed_ms
       , x.response_is_binary_yn                                       as response_is_binary_yn
       , x.created_on                                                  as executed_on
       , x.created_by                                                  as executed_by
       , dbms_lob.substr(x.response_body_clob, 2000, 1)                as error_text
       , dbms_lob.substr(
             regexp_substr(x.response_headers, '^content-type:[ ]*([^;' || chr(13) || chr(10) || ']+)', 1, 1, 'im', 1)
           , 255
           , 1
         )                                                             as content_type
       , case
           when x.response_is_binary_yn = 'Y' then dbms_lob.getlength(x.response_body_blob)
           else dbms_lob.getlength(x.response_body_clob)
         end                                                           as response_length
    from arw_executions                  x
    join arw_endpoints                   e on e.endpoint_id = x.endpoint_id
                                          and e.active_yn = 'Y'
   where x.active_yn = 'Y'
), w_query as (
  select p.endpoint_id                                                 as endpoint_id
       , '?' || listagg(p.param_name || '=' || p.param_value, chr(38) on overflow truncate)
                 within group (order by p.param_id)                    as query_string
    from arw_endpoint_params             p
    join arw_endpoints                   e on e.endpoint_id = p.endpoint_id
                                          and e.active_yn = 'Y'
   where p.active_yn = 'Y'
     and p.param_kind_code = 'query'
   group by p.endpoint_id
)
select b.execution_id                                                  as execution_id
     , b.endpoint_id                                                   as endpoint_id
     , b.endpoint_name                                                 as endpoint_name
     , b.collection_id                                                 as collection_id
     , c.name                                                          as collection_name
     , b.environment_id                                                as environment_id
     , v.name                                                          as environment_name
     , b.http_method                                                   as http_method
     , b.url_path                                                      as url_path
     , b.url_path || q.query_string                                    as display_path
     , b.request_status_code                                           as request_status_code
     , b.http_status_code                                              as http_status_code
     , coalesce(to_char(b.http_status_code), to_char(unistr('\2014'))) as status_label
     , case
         when b.request_status_code != 'success'        then 'error'
         when b.http_status_code between 200 and 299    then 'ok'
         when b.http_status_code between 300 and 399    then 'warn'
         when b.http_status_code >= 400                 then 'error'
         else 'info'
       end                                                             as status_class
     , case
         when b.request_status_code = 'timeout'         then 'Timeout'
         when b.request_status_code = 'error'           then 'Error'
         else
           case b.http_status_code
             when 100 then 'Continue'
             when 200 then 'OK'
             when 201 then 'Created'
             when 202 then 'Accepted'
             when 204 then 'No Content'
             when 206 then 'Partial Content'
             when 301 then 'Moved Permanently'
             when 302 then 'Found'
             when 303 then 'See Other'
             when 304 then 'Not Modified'
             when 307 then 'Temporary Redirect'
             when 308 then 'Permanent Redirect'
             when 400 then 'Bad Request'
             when 401 then 'Unauthorized'
             when 403 then 'Forbidden'
             when 404 then 'Not Found'
             when 405 then 'Method Not Allowed'
             when 406 then 'Not Acceptable'
             when 408 then 'Request Timeout'
             when 409 then 'Conflict'
             when 410 then 'Gone'
             when 413 then 'Content Too Large'
             when 415 then 'Unsupported Media Type'
             when 422 then 'Unprocessable Content'
             when 429 then 'Too Many Requests'
             when 500 then 'Internal Server Error'
             when 501 then 'Not Implemented'
             when 502 then 'Bad Gateway'
             when 503 then 'Service Unavailable'
             when 504 then 'Gateway Timeout'
           end
       end                                                             as status_text
     , b.elapsed_ms                                                    as elapsed_ms
     , case
         when b.request_status_code != 'success' then
           coalesce(
               regexp_substr(regexp_replace(b.error_text, 'ORA-(29273|06512)', 'ORA_'), 'ORA-[0-9]{5}')
             , regexp_substr(b.error_text, 'ORA-[0-9]{5}')
           )
       end                                                             as error_code
     , lower(trim(b.content_type))                                     as content_type
     , case
         when b.request_status_code = 'success' then b.response_length
       end                                                             as response_size_bytes
     , b.executed_on                                                   as executed_on
     , b.executed_by                                                   as executed_by
  from w_base                            b
  join arw_collections                   c on c.collection_id = b.collection_id
  join arw_environments                  v on v.environment_id = b.environment_id
  left join w_query                      q on q.endpoint_id = b.endpoint_id;
