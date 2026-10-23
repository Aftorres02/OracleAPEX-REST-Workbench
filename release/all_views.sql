-- Listing for views
-- One explicit line per view file; order matters when a view selects from
-- another view (arw_endpoint_summary_vw reads arw_execution_log_vw).
@../views/arw_execution_log_vw.sql
@../views/arw_endpoint_summary_vw.sql
@../views/arw_collection_summary_vw.sql
