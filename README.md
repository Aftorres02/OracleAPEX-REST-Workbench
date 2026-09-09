# OracleAPEX-REST-Workbench
Test REST APIs directly from your Oracle database and generate production-ready PL/SQL and APEX code. It is like Postman for Oracle APEX developers.

## Repository Structure

This repository follows the standardized [Oracle APEX Project Template](https://github.com/Aftorres02/OracleAPEX-Project-Template) layout, so it stays compatible with our CI/CD pipelines, automated scripts, and deployment strategies.

- **`apex/`**: Exported Oracle APEX applications in `.sql` format.
- **`data/`**: Re-runnable data scripts, most commonly used for populating List of Values (LOV) / lookup tables.
- **`docs/`**: Project documentation.
- **`jobs/`**: Scheduler jobs (`DBMS_SCHEDULER`) definitions.
- **`lib/`**: 3rd party database libraries or utilities needed for the project.
- **`packages/`**: `PL/SQL` package specifications (`.pks`) and bodies (`.pkb`). Ensure all packages follow the logging standards.
- **`release/`**: Versioned release manifests and files that govern the roll-out of database and APEX changes. See [SKILL.md](SKILL.md) for the release strategy.
- **`scripts/`**: Utility execution scripts (e.g. disable an application during deployment, install/export APEX apps).
- **`synonyms/`**: Scripts for creating synonyms.
- **`tables/`**: Table DDL statements.
- **`triggers/`**: Database triggers.
- **`views/`**: View DDL statements.
- **`www/`**: Frontend assets — custom JavaScript, CSS and images, uploaded into the APEX workspace (or a web server) at build time.

## Release Process

Releases go `Dev → Test → Prod` and are driven by a single entry point, `release/_release.sql`. See [SKILL.md](SKILL.md) for the folder layout, the two branching/tagging strategies, and how to run a release manually or in Production.
