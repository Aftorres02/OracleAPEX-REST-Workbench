-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_collections_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_not_found      constant number := -20940;
  gc_err_invalid_parent constant number := -20941;
  gc_err_has_dependents constant number := -20942;








  -- ===========================================================================
  -- PROCEDURE: validate_parent (private)
  -- ===========================================================================
  /**
   * Raises gc_err_invalid_parent unless p_parent_collection_id is a valid
   * parent: an active collection that is neither p_collection_id itself nor
   * one of its descendants (which would create a cycle). A null parent is
   * always valid -- it makes the collection a root.
   *
   * @example
   * -- Private: exercised through the public API. Making a collection its
   * -- own parent fails with ORA-20941.
   * begin
   *   arw_collections_api.update_collection(
   *       p_collection_id                      => 1
   *     , p_name                               => 'Sample collection'
   *     , p_description                        => null
   *     , p_parent_collection_id               => 1
   *   );
   * end;
   * /
   *
   * @issue   #23 (Fase 1 - Collections editor)
   *
   * @author  Angel Flores (Developer)
   * @created October 22, 2026
   *
   * @param p_collection_id Collection being saved; null when it is being created
   * @param p_parent_collection_id Proposed parent collection; null for a root collection
   */
  procedure validate_parent(
      p_collection_id                           in arw_collections.collection_id%type
    , p_parent_collection_id                    in arw_collections.parent_collection_id%type
  )
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'validate_parent';
    l_params    logger.tab_param;
    l_parent_n  number;
    l_subtree_n number;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_parent_collection_id', p_parent_collection_id);
    logger.log('START', l_scope, null, l_params);

    if p_parent_collection_id is null then
      logger.log('END - root collection, nothing to validate', l_scope, null, l_params);
      return;
    end if;

    select count(1)                                        as parent_n
      into l_parent_n
      from arw_collections c
     where c.collection_id = p_parent_collection_id
       and c.active_yn = 'Y';

    if l_parent_n = 0 then
      raise_application_error(gc_err_invalid_parent, 'Parent collection not found or inactive: ' || p_parent_collection_id);
    end if;

    if p_collection_id is not null then
      -- The proposed parent must not sit in this collection's own subtree
      -- (the start with row is the collection itself)
      select count(1)                                      as subtree_n
        into l_subtree_n
        from arw_collections c
       where c.collection_id = p_parent_collection_id
       start with c.collection_id = p_collection_id
      connect by nocycle prior c.collection_id = c.parent_collection_id;

      if l_subtree_n > 0 then
        raise_application_error(gc_err_invalid_parent, 'A collection cannot be its own parent or the parent of one of its ancestors.');
      end if;
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end validate_parent;








  -- ===========================================================================
  -- FUNCTION: create_collection
  -- ===========================================================================
  /**
   * Creates a collection, optionally nested under an active parent.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_collection_id arw_collections.collection_id%type;
   * begin
   *   l_collection_id := arw_collections_api.create_collection(
   *       p_name                               => 'Sample collection'
   *     , p_description                        => 'Created from the @example'
   *   );
   *   dbms_output.put_line('collection_id = ' || l_collection_id);
   * end;
   * /
   *
   * @issue   #23 (Fase 1 - Collections editor)
   *
   * @author  Angel Flores (Developer)
   * @created October 22, 2026
   *
   * @param p_name Display name of the collection
   * @param p_description Free-text description; null when not needed
   * @param p_parent_collection_id Parent collection; null for a root collection
   * @return arw_collections.collection_id%type  Identifier of the created collection
   */
  function create_collection(
      p_name                                    in arw_collections.name%type
    , p_description                             in arw_collections.description%type default null
    , p_parent_collection_id                    in arw_collections.parent_collection_id%type default null
  )
  return arw_collections.collection_id%type
  is
    l_scope         logger_logs.scope%type := gc_scope_prefix || 'create_collection';
    l_params        logger.tab_param;
    l_collection_id arw_collections.collection_id%type;
  begin
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_parent_collection_id', p_parent_collection_id);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject an inactive or missing parent before inserting.
    -- =========================================================================

    validate_parent(
        p_collection_id                         => null
      , p_parent_collection_id                  => p_parent_collection_id
    );
    -- =========================================================================

    insert
      into arw_collections (
           name
         , description
         , parent_collection_id
      )
    values (
           p_name
         , p_description
         , p_parent_collection_id
      )
    returning collection_id into l_collection_id;

    logger.append_param(l_params, 'l_collection_id', l_collection_id);
    logger.log('END', l_scope, null, l_params);

    return l_collection_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end create_collection;








  -- ===========================================================================
  -- PROCEDURE: update_collection
  -- ===========================================================================
  /**
   * Updates an active collection's name, description and parent.
   *
   * @example
   * begin
   *   arw_collections_api.update_collection(
   *       p_collection_id                      => 1
   *     , p_name                               => 'Sample collection'
   *     , p_description                        => 'Updated from the @example'
   *     , p_parent_collection_id               => null
   *   );
   * end;
   * /
   *
   * @issue   #23 (Fase 1 - Collections editor)
   *
   * @author  Angel Flores (Developer)
   * @created October 22, 2026
   *
   * @param p_collection_id Collection to update
   * @param p_name Display name of the collection
   * @param p_description Free-text description; null when not needed
   * @param p_parent_collection_id Parent collection; null for a root collection
   */
  procedure update_collection(
      p_collection_id                           in arw_collections.collection_id%type
    , p_name                                    in arw_collections.name%type
    , p_description                             in arw_collections.description%type
    , p_parent_collection_id                    in arw_collections.parent_collection_id%type
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'update_collection';
    l_params logger.tab_param;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.append_param(l_params, 'p_name', p_name);
    logger.append_param(l_params, 'p_parent_collection_id', p_parent_collection_id);
    logger.log('START', l_scope, null, l_params);


    -- =========================================================================
    -- Reject a missing/inactive parent, or one that would create a cycle.
    -- =========================================================================

    validate_parent(
        p_collection_id                         => p_collection_id
      , p_parent_collection_id                  => p_parent_collection_id
    );
    -- =========================================================================

    update arw_collections
       set name                  = p_name
         , description           = p_description
         , parent_collection_id  = p_parent_collection_id
     where collection_id = p_collection_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Collection not found: ' || p_collection_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_collection;








  -- ===========================================================================
  -- PROCEDURE: deactivate_collection
  -- ===========================================================================
  /**
   * Soft-deletes a collection (active_yn = N). Refuses while the collection
   * still has active child collections, endpoints or environments, so
   * nothing is left pointing at an inactive collection. last_updated_by/on
   * are left to the compound trigger, per ddl-conventions.md section 5.
   *
   * @example
   * begin
   *   arw_collections_api.deactivate_collection(
   *       p_collection_id                      => 1
   *   );
   * end;
   * /
   *
   * @issue   #23 (Fase 1 - Collections editor)
   *
   * @author  Angel Flores (Developer)
   * @created October 22, 2026
   *
   * @param p_collection_id Collection to deactivate
   */
  procedure deactivate_collection(
      p_collection_id                           in arw_collections.collection_id%type
  )
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'deactivate_collection';
    l_params       logger.tab_param;
    l_dependents_n number;
  begin
    logger.append_param(l_params, 'p_collection_id', p_collection_id);
    logger.log('START', l_scope, null, l_params);

    select (select count(1)
              from arw_collections ch
             where ch.parent_collection_id = p_collection_id
               and ch.active_yn = 'Y')
         + (select count(1)
              from arw_endpoints e
             where e.collection_id = p_collection_id
               and e.active_yn = 'Y')
         + (select count(1)
              from arw_environments v
             where v.collection_id = p_collection_id
               and v.active_yn = 'Y')                     as dependents_n
      into l_dependents_n
      from dual;

    if l_dependents_n > 0 then
      raise_application_error(gc_err_has_dependents, 'Collection still has active child collections, endpoints or environments -- deactivate those first.');
    end if;

    update arw_collections
       set active_yn = 'N'
     where collection_id = p_collection_id
       and active_yn = 'Y';

    if sql%rowcount = 0 then
      raise_application_error(gc_err_not_found, 'Collection not found: ' || p_collection_id);
    end if;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end deactivate_collection;


end arw_collections_api;
/
