-- Release specific references to files in this folder
-- This file is automatically executed from the /release/_release.sql file
--
-- Ex: @code/issue-123.sql

-- Issue #25: additive DDL for discovery (profile status, sample count,
-- column notes) and code generation (widened artifact/template checks).
-- Both scripts are idempotent.
@code/discovery_upgrade.sql
@code/codegen_upgrade.sql
