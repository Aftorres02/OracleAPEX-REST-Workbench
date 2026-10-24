-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_guide_api
as
-- =============================================================================
-- Package: arw_guide_api
-- Purpose: In-app Guide (pages 900 Quick start / 910 Examples): installs and
--          restores the "Guide examples" collection -- its dev environment,
--          the ready-to-send example endpoints and their card text in
--          arw_guide_examples.
--
-- =============================================================================


  procedure install_examples;


end arw_guide_api;
/
