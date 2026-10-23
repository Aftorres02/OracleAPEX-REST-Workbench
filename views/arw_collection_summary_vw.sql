-- Implements: .claude/rules/sql-format.md (views and WITH clause)
-- =============================================================================
-- View:    arw_collection_summary_vw
-- Purpose: One row per active collection with the counters shown on the
--          Home collection cards ("12 endpoints - 4 profiled") and the
--          Collections list (page 100).
--
-- @author  Angel Flores (Developer)
-- @created October 23, 2026
-- @ticket  #25 (Phase 1 - full ARW application)
-- =============================================================================
-- Notes:
--   * endpoint_count counts active endpoints; profiled_count counts the
--     active endpoints that have at least one active data profile
--     (arw_data_profiles -> arw_response_samples.endpoint_id), whatever its
--     status (proposal or accepted).
--   * environment_count counts active environments of the collection.
create or replace view arw_collection_summary_vw
as
with w_base as (
  select c.collection_id                                               as collection_id
       , c.name                                                        as name
       , c.description                                                 as description
       , c.parent_collection_id                                        as parent_collection_id
    from arw_collections                 c
   where c.active_yn = 'Y'
), w_endpoints as (
  select e.collection_id                                               as collection_id
       , count(1)                                                      as endpoint_count
    from arw_endpoints                   e
    join w_base                          b on b.collection_id = e.collection_id
   where e.active_yn = 'Y'
   group by e.collection_id
), w_profiled as (
  select e.collection_id                                               as collection_id
       , count(distinct e.endpoint_id)                                 as profiled_count
    from arw_endpoints                   e
    join w_base                          b on b.collection_id = e.collection_id
    join arw_response_samples           rs on rs.endpoint_id = e.endpoint_id
    join arw_data_profiles              dp on dp.response_sample_id = rs.sample_id
                                          and dp.active_yn = 'Y'
   where e.active_yn = 'Y'
   group by e.collection_id
), w_environments as (
  select v.collection_id                                               as collection_id
       , count(1)                                                      as environment_count
    from arw_environments                v
    join w_base                          b on b.collection_id = v.collection_id
   where v.active_yn = 'Y'
   group by v.collection_id
)
select b.collection_id                                                 as collection_id
     , b.name                                                          as name
     , b.description                                                   as description
     , b.parent_collection_id                                          as parent_collection_id
     , coalesce(ep.endpoint_count, 0)                                  as endpoint_count
     , coalesce(pf.profiled_count, 0)                                  as profiled_count
     , coalesce(ev.environment_count, 0)                               as environment_count
  from w_base                            b
  left join w_endpoints                 ep on ep.collection_id = b.collection_id
  left join w_profiled                  pf on pf.collection_id = b.collection_id
  left join w_environments              ev on ev.collection_id = b.collection_id;
