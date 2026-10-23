-- Implements: .claude/rules/sql-format.md (views and WITH clause)
-- =============================================================================
-- View:    arw_endpoint_summary_vw
-- Purpose: One row per active endpoint for the Endpoints list (page 200) and
--          the endpoint editor (page 210): the display URL shown in the URL
--          bar, how many samples were collected, the status of its current
--          data profile and the status chip of its last execution.
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25 (Phase 1 - full ARW application)
-- =============================================================================
-- Notes:
--   * display_url is '{{base_url}}' || url_path || '?k=v' + chr(38) + 'k=v'
--     built from the active query parameters in param_id order, values not
--     url-encoded (it is a display string, as in the mockup URL bar). This
--     view is the single definition: arw_endpoint_api.display_url reads it,
--     so report queries never call a logging PL/SQL function once per row.
--   * data_profile_id / profile_status_code come from the endpoint's newest
--     active data profile (arw_data_profiles -> arw_response_samples);
--     both are null when the endpoint has no profile yet.
--   * The last_* columns reuse arw_execution_log_vw so the status label,
--     class and reason phrase are defined only once.
create or replace view arw_endpoint_summary_vw
as
with w_base as (
  select e.endpoint_id                                                 as endpoint_id
       , e.collection_id                                               as collection_id
       , c.name                                                        as collection_name
       , e.name                                                        as name
       , e.http_method                                                 as http_method
       , e.url_path                                                    as url_path
       , e.credential_id                                               as credential_id
       , e.runtime_target_code                                         as runtime_target_code
    from arw_endpoints                   e
    join arw_collections                 c on c.collection_id = e.collection_id
   where e.active_yn = 'Y'
), w_query as (
  select p.endpoint_id                                                 as endpoint_id
       , '?' || listagg(p.param_name || '=' || p.param_value, chr(38) on overflow truncate)
                 within group (order by p.param_id)                    as query_string
    from arw_endpoint_params             p
    join w_base                          b on b.endpoint_id = p.endpoint_id
   where p.active_yn = 'Y'
     and p.param_kind_code = 'query'
   group by p.endpoint_id
), w_samples as (
  select rs.endpoint_id                                                as endpoint_id
       , count(1)                                                      as sample_count
    from arw_response_samples            rs
    join w_base                          b on b.endpoint_id = rs.endpoint_id
   where rs.active_yn = 'Y'
   group by rs.endpoint_id
), w_profiles as (
  select rs.endpoint_id                                                as endpoint_id
       , max(dp.data_profile_id)                                       as data_profile_id
    from arw_data_profiles               dp
    join arw_response_samples            rs on rs.sample_id = dp.response_sample_id
    join w_base                          b on b.endpoint_id = rs.endpoint_id
   where dp.active_yn = 'Y'
   group by rs.endpoint_id
), w_last as (
  select x.endpoint_id                                                 as endpoint_id
       , max(x.execution_id)                                           as last_execution_id
    from arw_executions                  x
    join w_base                          b on b.endpoint_id = x.endpoint_id
   where x.active_yn = 'Y'
   group by x.endpoint_id
)
select b.endpoint_id                                                   as endpoint_id
     , b.collection_id                                                 as collection_id
     , b.collection_name                                               as collection_name
     , b.name                                                          as name
     , b.http_method                                                   as http_method
     , b.url_path                                                      as url_path
     , b.url_path || q.query_string                                    as display_path
     , '{{base_url}}' || b.url_path || q.query_string                  as display_url
     , b.credential_id                                                 as credential_id
     , b.runtime_target_code                                           as runtime_target_code
     , coalesce(s.sample_count, 0)                                     as sample_count
     , p.data_profile_id                                               as data_profile_id
     , case
         when p.data_profile_id is not null then 'proposal'
       end                                                             as profile_status_code
     , l.last_execution_id                                             as last_execution_id
     , xl.status_label                                                 as last_status_label
     , xl.status_class                                                 as last_status_class
     , xl.status_text                                                  as last_status_text
     , xl.elapsed_ms                                                   as last_elapsed_ms
     , xl.executed_on                                                  as last_executed_on
  from w_base                            b
  left join w_query                      q on q.endpoint_id = b.endpoint_id
  left join w_samples                    s on s.endpoint_id = b.endpoint_id
  left join w_profiles                   p on p.endpoint_id = b.endpoint_id
  left join w_last                       l on l.endpoint_id = b.endpoint_id
  left join arw_execution_log_vw        xl on xl.execution_id = l.last_execution_id;
