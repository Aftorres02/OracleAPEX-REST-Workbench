-- Listing for tables
-- Unlike views/packages/triggers, tables are not glob-scanned: creation
-- order matters (FK dependencies), so this defers to the explicit,
-- dependency-ordered installer instead of listing files here directly.
@../tables/_install_arw_tables.sql
