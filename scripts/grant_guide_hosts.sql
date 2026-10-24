-- =============================================================================
-- Script:  grant_guide_hosts.sql
-- Purpose: Network ACLs for the public APIs the in-app Guide examples call
--          (page 910). Without them the preflight refuses those examples.
--          jsonplaceholder.typicode.com is not listed: it was granted for
--          Phase 0. catfact.ninja is left out on purpose -- the "Blocked
--          host" example shows the preflight refusing it.
--
--          Run as ADMIN (Autonomous Database) or a DBA: the ARW schema cannot
--          see dbms_network_acl_admin, so it cannot grant itself access.
--          Re-runnable: append_host_ace ignores an ACE that already exists.
--
-- Usage:   @scripts/grant_guide_hosts.sql <ARW schema>
--          e.g. @scripts/grant_guide_hosts.sql WKSP_DEVAI1
--
-- @author  Angel Flores (Developer)
-- @created October 24, 2026
-- @ticket  #25 (Phase 1 - in-app guide)
-- =============================================================================
set define on;
set verify off;

declare
  type t_hosts is table of varchar2(255 char);
  l_hosts t_hosts := t_hosts(
                         'dummyjson.com'          -- JSON, generated images, POST/PUT/PATCH
                       , 'httpbin.org'            -- JPEG photo, XML
                       , 'upload.wikimedia.org'   -- MP3 audio
                       , 'www.w3.org'             -- PDF file
                     );
begin
  for i in 1 .. l_hosts.count loop
    dbms_network_acl_admin.append_host_ace(
        host => l_hosts(i)
      , ace  => xs$ace_type(
                    privilege_list => xs$name_list('http', 'resolve')
                  , principal_name => upper('&1')
                  , principal_type => xs_acl.ptype_db
                )
    );
    dbms_output.put_line('Granted http + resolve on ' || l_hosts(i) || ' to ' || upper('&1'));
  end loop;
end;
/
