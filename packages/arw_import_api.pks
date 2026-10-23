-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_import_api
as
-- =============================================================================
-- Package: arw_import_api
-- Purpose: Imports a Postman Collection v2.1 file into ARW: one collection
--          (folders flattened into it, names prefixed with the folder
--          path), its endpoints with headers, query/path params and
--          bodies, a "dev" environment holding the base URL and the
--          collection variables, and credential metadata for the auth the
--          collection uses. Secrets are never imported: sensitive header,
--          parameter and variable values are dropped and credentials are
--          created without their secret -- the user creates the Web
--          Credential afterwards (preflight offers it). Backs the Import
--          page (700) -- see docs/base/IMPLEMENTATION.md section 9.
--
-- =============================================================================


  function import_postman(
      p_collection_json                         in clob
    , p_collection_name                         in varchar2 default null
  )
  return arw_collections.collection_id%type;


  function last_import_summary
  return varchar2;


end arw_import_api;
/
