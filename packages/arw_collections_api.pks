-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_collections_api
as
-- =============================================================================
-- Package: arw_collections_api
-- Purpose: Create, update and deactivate collections. Backs the Collections
--          editor (page 110) -- see docs/base/implementation_plan.md
--          section 5 (Fase 1).
--
-- =============================================================================


  function create_collection(
      p_name                                    in arw_collections.name%type
    , p_description                             in arw_collections.description%type default null
    , p_parent_collection_id                    in arw_collections.parent_collection_id%type default null
  )
  return arw_collections.collection_id%type;


  procedure update_collection(
      p_collection_id                           in arw_collections.collection_id%type
    , p_name                                    in arw_collections.name%type
    , p_description                             in arw_collections.description%type
    , p_parent_collection_id                    in arw_collections.parent_collection_id%type
  );


  procedure deactivate_collection(
      p_collection_id                           in arw_collections.collection_id%type
  );


  function drafts_collection_id
  return arw_collections.collection_id%type;


end arw_collections_api;
/
