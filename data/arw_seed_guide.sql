-- Implements: .claude/rules/ddl-conventions.md (seed data, re-runnable)
-- =============================================================================
-- Script:  arw_seed_guide.sql
-- Purpose: Installs (or restores) the in-app Guide examples: the "Guide
--          examples" collection, its dev environment and the ready-to-send
--          endpoints behind pages 900/910. The data lives in arw_guide_api
--          (gc_examples) so this script and the Reset examples button
--          always agree. Re-runnable.
--
-- @author  Angel Flores (Developer)
-- @created October 24, 2026
-- @ticket  #25 (Phase 1 - in-app guide)
-- =============================================================================
set define off;

prompt Guide examples

begin
  arw_guide_api.install_examples;
  commit;
end;
/
