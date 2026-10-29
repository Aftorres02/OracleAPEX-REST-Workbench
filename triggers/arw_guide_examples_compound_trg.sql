-- Implements: .claude/rules/ddl-conventions.md (trigger patterns / audit automation)
-- =============================================================================
-- Trigger: arw_guide_examples_compound_trg
-- Purpose: Automatically maintains audit columns (last_updated_by,
--          last_updated_on) on every update to arw_guide_examples.
--
-- @author  Angel Flores (Developer)
-- @created October 24, 2026
-- @ticket  #25 (Phase 1 - in-app guide)
-- =============================================================================
create or replace trigger arw_guide_examples_compound_trg
for insert or update on arw_guide_examples
compound trigger

  before each row is
  begin
    if updating then
      :new.last_updated_on := localtimestamp;
      :new.last_updated_by := coalesce(
                                sys_context('APEX$SESSION','app_user')
                              , regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
                              , sys_context('userenv','session_user')
                              );
    end if;
  end before each row;

end arw_guide_examples_compound_trg;
/
