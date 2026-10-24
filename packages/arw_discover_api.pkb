-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_discover_api
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_not_found constant number := -20943;
  gc_err_invalid   constant number := -20944;

  -- Format masks proposed for ISO-8601 strings. The UTC mask (the one in
  -- the Page 210 mockup) parses "...Z" values with or without fractional
  -- seconds; the offset mask also parses +hh:mm, +hhmm and values without
  -- any time zone, so it is the fallback whenever not every value ends in Z.
  gc_mask_utc     constant varchar2(100 char) := 'YYYY"-"MM"-"DD"T"HH24":"MI:SS.FF9TZR';
  gc_mask_offset  constant varchar2(100 char) := 'YYYY"-"MM"-"DD"T"HH24":"MI:SS.FF9TZH:TZM';
  gc_mask_date    constant varchar2(100 char) := 'YYYY"-"MM"-"DD';
  gc_ts_pattern   constant varchar2(200 char) := '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})?$';
  gc_date_pattern constant varchar2(50 char)  := '^\d{4}-\d{2}-\d{2}$';

  gc_varchar2_min constant pls_integer := 16;
  gc_varchar2_max constant pls_integer := 4000;
  gc_name_max     constant pls_integer := 128;
  gc_path_max     constant pls_integer := 500;
  gc_note_max     constant pls_integer := 500;
  gc_walk_depth   constant pls_integer := 10;
  gc_find_depth   constant pls_integer := 2;

  -- Internal markers for "the rows are the root value" (stored as a null
  -- row_selector) and the key of the top-level row context.
  gc_sel_root     constant varchar2(10 char) := '$root';
  gc_sel_single   constant varchar2(10 char) := '$single';
  gc_ctx_top      constant varchar2(1 char)  := '#';

  gc_note_dash    constant varchar2(10 char) := unistr(' \2014 ');

  -- Oracle SQL + PL/SQL reserved words: a proposed column name that equals
  -- one of these gets a _val suffix so generated DDL/records compile.
  gc_reserved_words constant varchar2(4000 char) :=
       ' access add all alter and any as asc at audit begin between by case'
    || ' char check cluster clusters colauth column column_value columns'
    || ' comment compress connect crash create current cursor date decimal'
    || ' declare default delete desc distinct drop else end exception'
    || ' exclusive exists fetch file float for from function goto grant'
    || ' group having identified if immediate in increment index indexes'
    || ' initial insert integer intersect into is level like lock long'
    || ' maxextents minus mlslabel mode modify nested_table_id noaudit'
    || ' nocompress not nowait null number of offline on online option or'
    || ' order overlaps pctfree prior procedure public raw rename resource'
    || ' revoke row rowid rownum rows select session set share size'
    || ' smallint sql start subtype successful synonym sysdate tabauth'
    || ' table then to trigger type uid union unique update user validate'
    || ' values varchar varchar2 view views when whenever where with ';

  -- Envelope keys that say nothing about the entity: an "id" under one of
  -- these takes its entity name from the URL path instead.
  gc_generic_words constant varchar2(1000 char) :=
       ' items item data results result records rows content contents value'
    || ' values list elements entries hits objects docs documents payload'
    || ' response body entities collection nodes edges api rest ords search ';

  -- Leaf names that get an _on suffix when they hold a date/timestamp, and
  -- an _pct suffix when they hold a 0-100 number.
  gc_audit_leaves   constant varchar2(200 char) := ' created updated modified deleted ';
  gc_percent_leaves constant varchar2(200 char) := ' discount margin markup commission ';


  -- ===========================================================================
  -- Discovery state. Reset at the start of every derive_profile call; only
  -- ever touched inside that call (one derivation per call, no reentrancy).
  -- ===========================================================================
  type t_shape_tab is table of varchar2(100 char) index by varchar2(10 char);

  type t_col_rec is record (
      ctx_key                 varchar2(4000 char)
    , path                    varchar2(4000 char)
    , leaf_name               varchar2(4000 char)
    , parent_idx              pls_integer
    , n_string                pls_integer := 0
    , n_number                pls_integer := 0
    , n_boolean               pls_integer := 0
    , n_array_scalar          pls_integer := 0
    , n_array_object          pls_integer := 0
    , n_array_empty           pls_integer := 0
    , n_timestamp             pls_integer := 0
    , n_date                  pls_integer := 0
    , n_tz_utc                pls_integer := 0
    , n_tz_other              pls_integer := 0
    , ts_shapes               t_shape_tab
    , num_min                 number
    , num_max                 number
    , max_length              pls_integer := 0
    , is_long_yn              varchar2(1 char) := 'N'
    , present_rows            pls_integer := 0
    , null_rows               pls_integer := 0
    , present_in_sample       pls_integer := 0
    , null_in_sample          pls_integer := 0
    , samples_missing         pls_integer := 0
    -- Final proposal, filled by finalize_columns
    , emit_yn                 varchar2(1 char) := 'Y'
    , column_name             arw_profile_columns.column_name%type
    , data_type_code          arw_profile_columns.data_type_code%type
    , source_data_type        arw_profile_columns.source_data_type%type
    , format_mask             arw_profile_columns.format_mask%type
    , max_observed_length     arw_profile_columns.max_observed_length%type
    , is_nullable_yn          arw_profile_columns.is_nullable_yn%type := 'N'
    , is_primary_key_yn       arw_profile_columns.is_primary_key_yn%type := 'N'
    , observation_note        arw_profile_columns.observation_note%type
    , column_id               arw_profile_columns.column_id%type
  );
  type t_col_tab is table of t_col_rec index by pls_integer;
  type t_col_map is table of pls_integer index by varchar2(4000 char);

  type t_ctx_rec is record (
      rows_total              pls_integer := 0
    , rows_in_sample          pls_integer := 0
    , samples_with_rows       pls_integer := 0
  );
  type t_ctx_tab is table of t_ctx_rec index by varchar2(4000 char);

  type t_name_set is table of varchar2(1 char) index by varchar2(200 char);

  g_cols    t_col_tab;
  g_col_map t_col_map;
  g_ctxs    t_ctx_tab;








  -- ===========================================================================
  -- FUNCTION: is_reserved_word (private)
  -- ===========================================================================
  /**
   * Returns true when p_name (any case) is an Oracle SQL or PL/SQL reserved
   * word, so it cannot be used as-is as a column or record field name.
   *
   * @example
   * -- Private: exercised through update_column. Renaming a column to
   * -- "order" fails with ORA-20944.
   * begin
   *   arw_discover_api.update_column(
   *       p_column_id                          => 1
   *     , p_column_name                        => 'order'
   *     , p_data_type_code                     => 'number'
   *     , p_max_observed_length                => null
   *     , p_format_mask                        => null
   *     , p_is_nullable_yn                     => 'N'
   *     , p_is_primary_key_yn                  => 'N'
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_name Candidate identifier
   * @return boolean  True when the identifier is reserved
   */
  function is_reserved_word(
      p_name                                    in varchar2
  )
  return boolean
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'is_reserved_word';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);
    $end

    return instr(gc_reserved_words, ' ' || lower(p_name) || ' ') > 0;
  exception
    when others then
      logger.append_param(l_params, 'p_name', p_name);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end is_reserved_word;








  -- ===========================================================================
  -- FUNCTION: to_snake (private)
  -- ===========================================================================
  /**
   * Converts a JSON key or dotted path into a snake_case identifier:
   * camelCase and acronym boundaries become underscores, anything other than
   * a-z/0-9 becomes an underscore, runs of underscores collapse, and a name
   * that would start with a digit gets a c_ prefix. Examples: userId ->
   * user_id, customer.code -> customer_code, HTTPStatus -> http_status.
   *
   * @example
   * -- Private: exercised through derive_profile (column and profile names).
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Key, dotted path or free text to convert
   * @return varchar2  snake_case identifier (never null)
   */
  function to_snake(
      p_text                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'to_snake';
    l_params logger.tab_param;
    l_text   varchar2(4000 char);
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_text', p_text);
    logger.log('START', l_scope, null, l_params);
    $end

    l_text := regexp_replace(p_text, '([a-z0-9])([A-Z])', '\1_\2');
    l_text := regexp_replace(l_text, '([A-Z]+)([A-Z][a-z])', '\1_\2');
    l_text := lower(l_text);
    l_text := regexp_replace(l_text, '[^a-z0-9]+', '_');
    l_text := trim(both '_' from l_text);

    if l_text is null then
      l_text := 'col';
    elsif regexp_like(l_text, '^[0-9]') then
      l_text := 'c_' || l_text;
    end if;

    return l_text;
  exception
    when others then
      logger.append_param(l_params, 'p_text', p_text);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end to_snake;








  -- ===========================================================================
  -- FUNCTION: singular (private)
  -- ===========================================================================
  /**
   * Naive English singular of a snake_case word, enough for REST resource
   * names: categories -> category, addresses -> address, boxes -> box,
   * orders -> order, order_items -> order_item. Words ending in ss/us/is
   * (status, analysis) are left alone.
   *
   * @example
   * -- Private: exercised through derive_profile. An "id" under rowSelector
   * -- "items" on /v1/orders becomes order_id.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_word snake_case word (plural or singular)
   * @return varchar2  Singular form
   */
  function singular(
      p_word                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'singular';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_word', p_word);
    logger.log('START', l_scope, null, l_params);
    $end

    return case
             when p_word is null or length(p_word) <= 3          then p_word
             when regexp_like(p_word, 'ies$')                     then regexp_replace(p_word, 'ies$', 'y')
             when regexp_like(p_word, '(ss|x|ch|sh|z)es$')        then regexp_replace(p_word, 'es$', '')
             when regexp_like(p_word, '(ss|us|is)$')              then p_word
             when regexp_like(p_word, 's$')                       then regexp_replace(p_word, 's$', '')
             else p_word
           end;
  exception
    when others then
      logger.append_param(l_params, 'p_word', p_word);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end singular;








  -- ===========================================================================
  -- FUNCTION: entity_name (private)
  -- ===========================================================================
  /**
   * Proposes the entity a row represents, used to rename a top-level "id"
   * to <entity>_id. Takes the last segment of the row selector unless it is
   * a generic envelope word (items, data, results...), otherwise the last
   * meaningful segment of the endpoint URL path (skipping numbers,
   * {placeholders}, :params, version segments like v1 and api/rest).
   * Examples: items on /v1/orders -> order; orders on /v1/x -> order; root
   * array on /todos -> todo; /todos/1 -> todo.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_row_selector Dotted row selector; null when the rows are the root value
   * @param p_url_path Endpoint URL path (e.g. /v1/orders)
   * @return varchar2  Singular snake_case entity name, or null when none can be inferred
   */
  function entity_name(
      p_row_selector                            in arw_data_profiles.row_selector%type
    , p_url_path                                in arw_endpoints.url_path%type
  )
  return varchar2
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'entity_name';
    l_params   logger.tab_param;
    l_segment  varchar2(4000 char);
    l_path     varchar2(4000 char);
    l_entity   varchar2(4000 char);
  begin
    logger.append_param(l_params, 'p_row_selector', p_row_selector);
    logger.append_param(l_params, 'p_url_path', p_url_path);
    logger.log('START', l_scope, null, l_params);

    if p_row_selector is not null then
      l_segment := lower(regexp_substr(p_row_selector, '[^.]+$'));
      if instr(gc_generic_words, ' ' || l_segment || ' ') = 0 then
        l_entity := singular(to_snake(l_segment));
      end if;
    end if;

    if l_entity is null then
      -- Drop scheme://host of a full-URL endpoint, then query and fragment
      l_path := regexp_replace(p_url_path, '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*', '');
      l_path := regexp_replace(l_path, '[?#].*$', '');

      for i in reverse 1 .. nvl(regexp_count(l_path, '[^/]+'), 0)
      loop
        l_segment := regexp_substr(l_path, '[^/]+', 1, i);

        if not regexp_like(l_segment, '^\d+$')
           and not regexp_like(lower(l_segment), '^v\d+(\.\d+)*$')
           and instr(l_segment, '{') = 0
           and instr(l_segment, '}') = 0
           and substr(l_segment, 1, 1) != ':'
           and instr(gc_generic_words, ' ' || lower(l_segment) || ' ') = 0
        then
          l_entity := singular(to_snake(l_segment));
          exit;
        end if;
      end loop;
    end if;

    logger.append_param(l_params, 'l_entity', l_entity);
    logger.log('END', l_scope, null, l_params);

    return l_entity;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end entity_name;








  -- ===========================================================================
  -- FUNCTION: round_length (private)
  -- ===========================================================================
  /**
   * Rounds an observed string length up to the proposed varchar2 length:
   * the next power of two, never below 16 and never above 4000. Examples:
   * 4 -> 16, 17 -> 32, 3000 -> 4000.
   *
   * @example
   * -- Private: exercised through derive_profile (max_observed_length).
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_length Longest observed length, in characters
   * @return pls_integer  Proposed varchar2 length
   */
  function round_length(
      p_length                                  in pls_integer
  )
  return pls_integer
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'round_length';
    l_params logger.tab_param;
    l_length pls_integer := gc_varchar2_min;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_length', p_length);
    logger.log('START', l_scope, null, l_params);
    $end

    while l_length < nvl(p_length, 0) and l_length < gc_varchar2_max
    loop
      l_length := l_length * 2;
    end loop;

    return least(l_length, gc_varchar2_max);
  exception
    when others then
      logger.append_param(l_params, 'p_length', p_length);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end round_length;








  -- ===========================================================================
  -- FUNCTION: has_object_elements (private)
  -- ===========================================================================
  /**
   * Returns true when the JSON array holds at least one object -- the test
   * for "array of rows" (row selector) and for nested child columns.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_array JSON array to inspect
   * @return boolean  True when any element is an object
   */
  function has_object_elements(
      p_array                                   in json_array_t
  )
  return boolean
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'has_object_elements';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.log('START', l_scope, null, l_params);
    $end

    for i in 0 .. p_array.get_size - 1
    loop
      if p_array.get(i).is_object then
        return true;
      end if;
    end loop;

    return false;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end has_object_elements;








  -- ===========================================================================
  -- PROCEDURE: find_row_selector (private)
  -- ===========================================================================
  /**
   * Detects the row selector of one sample body. A root array means "rows
   * are the root" (gc_sel_root). For a root object, the first key (breadth
   * first, root keys then one level down) holding an array of objects wins
   * (strong vote); failing that, the first empty array is a weak guess
   * (the caller also gives single-row a weak vote, so a lone detail object
   * with an empty array stays single-row); failing that, the object itself
   * is the single row (gc_sel_single). A scalar body casts no vote (null).
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_root Parsed sample body
   * @param o_selector Dotted selector, gc_sel_root, gc_sel_single, or null (no vote)
   * @param o_strong_yn Y when the selector is certain, N when it is a guess
   */
  procedure find_row_selector(
      p_root                                    in json_element_t
    , o_selector                                out varchar2
    , o_strong_yn                               out varchar2
  )
  is
    type t_obj_tab is table of json_object_t index by pls_integer;
    type t_prefix_tab is table of varchar2(4000 char) index by pls_integer;

    l_scope       logger_logs.scope%type := gc_scope_prefix || 'find_row_selector';
    l_params      logger.tab_param;
    l_level_objs  t_obj_tab;
    l_level_pfx   t_prefix_tab;
    l_next_objs   t_obj_tab;
    l_next_pfx    t_prefix_tab;
    l_keys        json_key_list;
    l_elem        json_element_t;
    l_path        varchar2(4000 char);
    l_weak        varchar2(4000 char);
  begin
    logger.log('START', l_scope, null, l_params);

    if p_root.is_array then
      o_selector  := gc_sel_root;
      o_strong_yn := 'Y';
    elsif not p_root.is_object then
      o_selector  := null;
      o_strong_yn := 'N';
    else
      l_level_objs(1) := treat(p_root as json_object_t);
      l_level_pfx(1)  := null;

      <<levels>>
      for l_depth in 1 .. gc_find_depth
      loop
        l_next_objs.delete;
        l_next_pfx.delete;

        for i in 1 .. l_level_objs.count
        loop
          l_keys := l_level_objs(i).get_keys;

          for k in 1 .. l_keys.count
          loop
            l_elem := l_level_objs(i).get(l_keys(k));
            l_path := l_level_pfx(i) || l_keys(k);

            if l_elem.is_array then
              if has_object_elements(treat(l_elem as json_array_t)) then
                o_selector  := l_path;
                o_strong_yn := 'Y';
                exit levels;
              elsif l_weak is null and treat(l_elem as json_array_t).get_size = 0 then
                l_weak := l_path;
              end if;
            elsif l_elem.is_object then
              l_next_objs(l_next_objs.count + 1) := treat(l_elem as json_object_t);
              l_next_pfx(l_next_pfx.count + 1)   := l_path || '.';
            end if;
          end loop;
        end loop;

        exit levels when l_next_objs.count = 0;
        l_level_objs := l_next_objs;
        l_level_pfx  := l_next_pfx;
      end loop levels;

      if o_selector is null then
        o_selector  := coalesce(l_weak, gc_sel_single);
        o_strong_yn := case when l_weak is null then 'Y' else 'N' end;
      end if;
    end if;

    logger.append_param(l_params, 'o_selector', o_selector);
    logger.append_param(l_params, 'o_strong_yn', o_strong_yn);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end find_row_selector;








  -- ===========================================================================
  -- PROCEDURE: ensure_ctx (private)
  -- ===========================================================================
  /**
   * Registers a row context (the top-level rows, or the elements of one
   * nested array column) the first time it is seen.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx_key Context key: gc_ctx_top or the key of the array column
   */
  procedure ensure_ctx(
      p_ctx_key                                 in varchar2
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'ensure_ctx';
    l_params logger.tab_param;
    l_ctx    t_ctx_rec;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
    logger.log('START', l_scope, null, l_params);
    $end

    if not g_ctxs.exists(p_ctx_key) then
      g_ctxs(p_ctx_key) := l_ctx;
    end if;
  exception
    when others then
      logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end ensure_ctx;








  -- ===========================================================================
  -- PROCEDURE: start_row (private)
  -- ===========================================================================
  /**
   * Counts one more row in a row context (overall and for the current
   * sample) before its fields are walked.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx_key Context key: gc_ctx_top or the key of the array column
   */
  procedure start_row(
      p_ctx_key                                 in varchar2
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'start_row';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
    logger.log('START', l_scope, null, l_params);
    $end

    g_ctxs(p_ctx_key).rows_total     := g_ctxs(p_ctx_key).rows_total + 1;
    g_ctxs(p_ctx_key).rows_in_sample := g_ctxs(p_ctx_key).rows_in_sample + 1;
  exception
    when others then
      logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end start_row;








  -- ===========================================================================
  -- FUNCTION: register_column (private)
  -- ===========================================================================
  /**
   * Returns the index of the column for (context, path), creating it on
   * first sight. Index order is first-seen order and becomes sequence_num.
   * A column first seen after earlier samples already had rows in its
   * context starts with those samples counted as "missing".
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_ctx_key Row context the column belongs to
   * @param p_path Path relative to the row (e.g. customer.code)
   * @param p_leaf_name Last key of the path (e.g. code)
   * @param p_parent_idx Index of the nested array column; null for top-level rows
   * @return pls_integer  Index of the column in g_cols
   */
  function register_column(
      p_ctx_key                                 in varchar2
    , p_path                                    in varchar2
    , p_leaf_name                               in varchar2
    , p_parent_idx                              in pls_integer
  )
  return pls_integer
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'register_column';
    l_params logger.tab_param;
    l_key    varchar2(4000 char) := p_ctx_key || '|' || p_path;
    l_col    t_col_rec;
    l_idx    pls_integer;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
    logger.append_param(l_params, 'p_path', p_path);
    logger.log('START', l_scope, null, l_params);
    $end

    if g_col_map.exists(l_key) then
      return g_col_map(l_key);
    end if;

    l_col.ctx_key         := p_ctx_key;
    l_col.path            := p_path;
    l_col.leaf_name       := p_leaf_name;
    l_col.parent_idx      := p_parent_idx;
    l_col.samples_missing := g_ctxs(p_ctx_key).samples_with_rows;

    l_idx            := g_cols.count + 1;
    g_cols(l_idx)    := l_col;
    g_col_map(l_key) := l_idx;

    return l_idx;
  exception
    when others then
      logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
      logger.append_param(l_params, 'p_path', p_path);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end register_column;








  -- ===========================================================================
  -- PROCEDURE: observe_scalar (private)
  -- ===========================================================================
  /**
   * Records one non-null scalar value of an object member: its JSON type,
   * length, numeric range, and whether a string is an ISO-8601 timestamp
   * (with its shape: fraction yes/no, Z / offset / no time zone) or a
   * YYYY-MM-DD date. Strings longer than 32767 are measured as CLOB.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_idx Index of the column in g_cols
   * @param p_obj Object holding the value
   * @param p_key Member key within p_obj
   * @param p_elem The member value (already known to be a non-null scalar)
   */
  procedure observe_scalar(
      p_idx                                     in pls_integer
    , p_obj                                     in json_object_t
    , p_key                                     in varchar2
    , p_elem                                    in json_element_t
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'observe_scalar';
    l_params logger.tab_param;
    l_string varchar2(32767);
    l_length pls_integer;
    l_number number;
    l_shape  varchar2(10 char);
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_idx', p_idx);
    logger.append_param(l_params, 'p_key', p_key);
    logger.log('START', l_scope, null, l_params);
    $end

    if p_elem.is_string then
      g_cols(p_idx).n_string := g_cols(p_idx).n_string + 1;

      begin
        l_string := p_obj.get_string(p_key);
        l_length := nvl(length(l_string), 0);
      exception
        when value_error then
          -- Longer than a PL/SQL varchar2: measure it as a CLOB instead
          l_string := null;
          l_length := dbms_lob.getlength(p_obj.get_clob(p_key));
          g_cols(p_idx).is_long_yn := 'Y';
      end;

      g_cols(p_idx).max_length := greatest(g_cols(p_idx).max_length, l_length);

      if l_length between 10 and 40 then
        if regexp_like(l_string, gc_ts_pattern)
           and validate_conversion(l_string as timestamp with time zone, 'YYYY"-"MM"-"DD"T"HH24":"MI:SS.FF9TZH:TZM') = 1
        then
          g_cols(p_idx).n_timestamp := g_cols(p_idx).n_timestamp + 1;

          l_shape := case when instr(l_string, '.') > 0 then 'F' else 'S' end
                  || case
                       when substr(l_string, -1) = 'Z'                then 'Z'
                       when regexp_like(l_string, '[+-]\d{2}:\d{2}$') then 'C'
                       when regexp_like(l_string, '[+-]\d{4}$')       then 'O'
                       else 'N'
                     end;

          if substr(l_shape, 2) = 'Z' then
            g_cols(p_idx).n_tz_utc := g_cols(p_idx).n_tz_utc + 1;
          else
            g_cols(p_idx).n_tz_other := g_cols(p_idx).n_tz_other + 1;
          end if;

          if not g_cols(p_idx).ts_shapes.exists(l_shape) then
            g_cols(p_idx).ts_shapes(l_shape) := l_string;
          end if;
        elsif regexp_like(l_string, gc_date_pattern)
              and validate_conversion(l_string as date, 'YYYY"-"MM"-"DD') = 1
        then
          g_cols(p_idx).n_date := g_cols(p_idx).n_date + 1;
        end if;
      end if;
    elsif p_elem.is_number then
      l_number := p_obj.get_number(p_key);

      g_cols(p_idx).n_number   := g_cols(p_idx).n_number + 1;
      g_cols(p_idx).num_min    := least(nvl(g_cols(p_idx).num_min, l_number), l_number);
      g_cols(p_idx).num_max    := greatest(nvl(g_cols(p_idx).num_max, l_number), l_number);
      g_cols(p_idx).max_length := greatest(g_cols(p_idx).max_length, length(to_char(l_number)));
    elsif p_elem.is_boolean then
      g_cols(p_idx).n_boolean  := g_cols(p_idx).n_boolean + 1;
      g_cols(p_idx).max_length := greatest(g_cols(p_idx).max_length, 5);
    end if;

    g_cols(p_idx).present_rows      := g_cols(p_idx).present_rows + 1;
    g_cols(p_idx).present_in_sample := g_cols(p_idx).present_in_sample + 1;
  exception
    when others then
      logger.append_param(l_params, 'p_idx', p_idx);
      logger.append_param(l_params, 'p_key', p_key);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end observe_scalar;








  -- ===========================================================================
  -- PROCEDURE: walk_object (private)
  -- ===========================================================================
  /**
   * Walks one row object and records every field. Nested objects flatten
   * into dotted paths (customer.code); an array of objects becomes a column
   * whose elements are rows of a child context (child columns point to it
   * via parent_idx, paths relative to the element); an array of scalars is a
   * single column; JSON null counts as present-but-null.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_obj Row object (or nested object) to walk
   * @param p_ctx_key Row context of the row
   * @param p_prefix Dotted prefix of p_obj within the row; null at the row itself
   * @param p_parent_idx Index of the nested array column owning the row; null for top-level rows
   * @param p_depth Nesting depth, capped by gc_walk_depth
   */
  procedure walk_object(
      p_obj                                     in json_object_t
    , p_ctx_key                                 in varchar2
    , p_prefix                                  in varchar2
    , p_parent_idx                              in pls_integer
    , p_depth                                   in pls_integer
  )
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'walk_object';
    l_params    logger.tab_param;
    l_keys      json_key_list;
    l_elem      json_element_t;
    l_array     json_array_t;
    l_child     json_element_t;
    l_path      varchar2(4000 char);
    l_idx       pls_integer;
    l_child_ctx varchar2(4000 char);
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
    logger.append_param(l_params, 'p_prefix', p_prefix);
    logger.log('START', l_scope, null, l_params);
    $end

    l_keys := p_obj.get_keys;

    for k in 1 .. l_keys.count
    loop
      l_path := p_prefix || l_keys(k);
      l_elem := p_obj.get(l_keys(k));

      if l_elem.is_object then
        if p_depth < gc_walk_depth then
          walk_object(
              p_obj                             => treat(l_elem as json_object_t)
            , p_ctx_key                         => p_ctx_key
            , p_prefix                          => l_path || '.'
            , p_parent_idx                      => p_parent_idx
            , p_depth                           => p_depth + 1
          );
        end if;
      else
        l_idx := register_column(
                     p_ctx_key                  => p_ctx_key
                   , p_path                     => l_path
                   , p_leaf_name                => l_keys(k)
                   , p_parent_idx               => p_parent_idx
                 );

        if l_elem.is_null then
          g_cols(l_idx).null_rows      := g_cols(l_idx).null_rows + 1;
          g_cols(l_idx).null_in_sample := g_cols(l_idx).null_in_sample + 1;
        elsif l_elem.is_array then
          l_array := treat(l_elem as json_array_t);

          g_cols(l_idx).present_rows      := g_cols(l_idx).present_rows + 1;
          g_cols(l_idx).present_in_sample := g_cols(l_idx).present_in_sample + 1;

          if l_array.get_size = 0 then
            g_cols(l_idx).n_array_empty := g_cols(l_idx).n_array_empty + 1;
          elsif has_object_elements(l_array) and p_depth < gc_walk_depth then
            g_cols(l_idx).n_array_object := g_cols(l_idx).n_array_object + 1;
            l_child_ctx := p_ctx_key || '|' || l_path;
            ensure_ctx(
                p_ctx_key                       => l_child_ctx
            );

            for j in 0 .. l_array.get_size - 1
            loop
              l_child := l_array.get(j);

              if l_child.is_object then
                start_row(
                    p_ctx_key                   => l_child_ctx
                );
                walk_object(
                    p_obj                       => treat(l_child as json_object_t)
                  , p_ctx_key                   => l_child_ctx
                  , p_prefix                    => null
                  , p_parent_idx                => l_idx
                  , p_depth                     => p_depth + 1
                );
              end if;
            end loop;
          else
            g_cols(l_idx).n_array_scalar := g_cols(l_idx).n_array_scalar + 1;
          end if;
        else
          observe_scalar(
              p_idx                             => l_idx
            , p_obj                             => p_obj
            , p_key                             => l_keys(k)
            , p_elem                            => l_elem
          );
        end if;
      end if;
    end loop;
  exception
    when others then
      logger.append_param(l_params, 'p_ctx_key', p_ctx_key);
      logger.append_param(l_params, 'p_prefix', p_prefix);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end walk_object;








  -- ===========================================================================
  -- PROCEDURE: end_sample (private)
  -- ===========================================================================
  /**
   * Closes one sample: every column whose context had rows in this sample
   * but that was missing or null in at least one of them counts the sample
   * as "missing"; per-sample counters then reset.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   */
  procedure end_sample
  is
    l_scope   logger_logs.scope%type := gc_scope_prefix || 'end_sample';
    l_params  logger.tab_param;
    l_ctx_key varchar2(4000 char);
  begin
    logger.log('START', l_scope, null, l_params);

    for i in 1 .. g_cols.count
    loop
      if g_ctxs(g_cols(i).ctx_key).rows_in_sample > 0
         and g_cols(i).present_in_sample < g_ctxs(g_cols(i).ctx_key).rows_in_sample
      then
        g_cols(i).samples_missing := g_cols(i).samples_missing + 1;
      end if;

      g_cols(i).present_in_sample := 0;
      g_cols(i).null_in_sample    := 0;
    end loop;

    l_ctx_key := g_ctxs.first;
    while l_ctx_key is not null
    loop
      if g_ctxs(l_ctx_key).rows_in_sample > 0 then
        g_ctxs(l_ctx_key).samples_with_rows := g_ctxs(l_ctx_key).samples_with_rows + 1;
      end if;

      g_ctxs(l_ctx_key).rows_in_sample := 0;
      l_ctx_key := g_ctxs.next(l_ctx_key);
    end loop;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end end_sample;








  -- ===========================================================================
  -- PROCEDURE: consume_sample (private)
  -- ===========================================================================
  /**
   * Walks every row of one parsed sample body under the chosen row
   * selector: the root array's objects, the single root object, or the
   * objects of the array found at the dotted selector path. A sample that
   * lacks the selector contributes no rows. Ends with end_sample.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_root Parsed sample body
   * @param p_selector Chosen selector: dotted path, gc_sel_root or gc_sel_single
   */
  procedure consume_sample(
      p_root                                    in json_element_t
    , p_selector                                in varchar2
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'consume_sample';
    l_params logger.tab_param;
    l_value  json_element_t := p_root;
    l_array  json_array_t;
  begin
    logger.append_param(l_params, 'p_selector', p_selector);
    logger.log('START', l_scope, null, l_params);

    if p_selector not in (gc_sel_root, gc_sel_single) then
      for i in 1 .. regexp_count(p_selector, '[^.]+')
      loop
        if l_value is null or not l_value.is_object then
          l_value := null;
          exit;
        end if;

        l_value := treat(l_value as json_object_t).get(regexp_substr(p_selector, '[^.]+', 1, i));
      end loop;
    end if;

    if l_value is not null then
      if l_value.is_array then
        l_array := treat(l_value as json_array_t);

        for j in 0 .. l_array.get_size - 1
        loop
          if l_array.get(j).is_object then
            start_row(
                p_ctx_key                       => gc_ctx_top
            );
            walk_object(
                p_obj                           => treat(l_array.get(j) as json_object_t)
              , p_ctx_key                       => gc_ctx_top
              , p_prefix                        => null
              , p_parent_idx                    => null
              , p_depth                         => 1
            );
          end if;
        end loop;
      elsif l_value.is_object then
        start_row(
            p_ctx_key                           => gc_ctx_top
        );
        walk_object(
            p_obj                               => treat(l_value as json_object_t)
          , p_ctx_key                           => gc_ctx_top
          , p_prefix                            => null
          , p_parent_idx                        => null
          , p_depth                             => 1
        );
      end if;
    end if;

    end_sample;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end consume_sample;








  -- ===========================================================================
  -- FUNCTION: pick_timestamp_mask (private)
  -- ===========================================================================
  /**
   * Chooses the format mask for a column whose strings are all ISO-8601
   * timestamps: the UTC mask when every value ends in Z (as in the Page 210
   * mockup), else the offset mask. One example of every observed shape must
   * convert with the chosen mask; when it does not, the offset mask is
   * tried; when neither works, null is returned (column stays varchar2).
   *
   * @example
   * -- Private: exercised through derive_profile (format_mask).
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_idx Index of the column in g_cols
   * @return varchar2  Format mask, or null when no candidate parses every shape
   */
  function pick_timestamp_mask(
      p_idx                                     in pls_integer
  )
  return varchar2
  is
    type t_mask_tab is table of varchar2(100 char);

    l_scope  logger_logs.scope%type := gc_scope_prefix || 'pick_timestamp_mask';
    l_params logger.tab_param;
    l_masks  t_mask_tab;
    l_shape  varchar2(10 char);
    l_ok     boolean;
  begin
    logger.append_param(l_params, 'p_idx', p_idx);
    logger.append_param(l_params, 'path', g_cols(p_idx).path);
    logger.log('START', l_scope, null, l_params);

    l_masks := case
                 when g_cols(p_idx).n_tz_other = 0 then t_mask_tab(gc_mask_utc, gc_mask_offset)
                 else t_mask_tab(gc_mask_offset)
               end;

    for m in 1 .. l_masks.count
    loop
      l_ok    := true;
      l_shape := g_cols(p_idx).ts_shapes.first;

      while l_shape is not null and l_ok
      loop
        l_ok    := validate_conversion(g_cols(p_idx).ts_shapes(l_shape) as timestamp with time zone, l_masks(m)) = 1;
        l_shape := g_cols(p_idx).ts_shapes.next(l_shape);
      end loop;

      if l_ok then
        logger.append_param(l_params, 'mask', l_masks(m));
        logger.log('END', l_scope, null, l_params);
        return l_masks(m);
      end if;
    end loop;

    logger.log('END - no mask parses every shape', l_scope, null, l_params);
    return null;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end pick_timestamp_mask;








  -- ===========================================================================
  -- PROCEDURE: finalize_columns (private)
  -- ===========================================================================
  /**
   * Turns the accumulated observations into the proposal: data type,
   * source type, format mask, rounded length, nullability with its
   * observation note, Oracle-safe unique column name, and a single PK.
   *
   * Type rules: array of objects -> clob/array (parent of child columns);
   * array of scalars -> clob/array; only numbers -> number; only booleans
   * -> boolean; only ISO-8601 timestamps -> timestamp_with_time_zone + mask;
   * only YYYY-MM-DD -> date + mask; other strings -> varchar2 (next power of
   * two, min 16) or clob above 4000; mixed types -> varchar2 (note); only
   * nulls -> varchar2(16) (note).
   *
   * Naming: dotted path -> underscores; top-level id -> <entity>_id;
   * child columns -> <singular parent>_<path>; created/updated/modified/
   * deleted timestamps -> _on; 0-100 discount/margin/markup/commission ->
   * _pct; reserved words -> _val; duplicates -> _2, _3...
   *
   * PK: top-level, not nullable, number/varchar2 -- "id" first, else the
   * first *_id / uuid / code.
   *
   * @example
   * -- Private: exercised through derive_profile.
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_entity Entity name for a top-level id (see entity_name); null keeps "id"
   */
  procedure finalize_columns(
      p_entity                                  in varchar2
  )
  is
    l_scope        logger_logs.scope%type := gc_scope_prefix || 'finalize_columns';
    l_params       logger.tab_param;
    l_used         t_name_set;
    l_kinds        pls_integer;
    l_absent_rows  pls_integer;
    l_rows_total   pls_integer;
    l_ctx_samples  pls_integer;
    l_missing_kind varchar2(30 char);
    l_note         varchar2(4000 char);
    l_leaf         varchar2(4000 char);
    l_base         varchar2(4000 char);
    l_name         varchar2(4000 char);
    l_suffix_n     pls_integer;
    l_pk_idx       pls_integer;
    l_snake_path   varchar2(4000 char);

    -- Appends one observation to the column's note ("; " separated)
    procedure add_note(
        p_text                                  in varchar2
    )
    is
    begin
      l_note := case when l_note is null then p_text else l_note || '; ' || p_text end;
    end add_note;
  begin
    logger.append_param(l_params, 'p_entity', p_entity);
    logger.append_param(l_params, 'column_count', g_cols.count);
    logger.log('START', l_scope, null, l_params);

    for i in 1 .. g_cols.count
    loop
      l_note  := null;
      l_kinds := sign(g_cols(i).n_string) + sign(g_cols(i).n_number)
               + sign(g_cols(i).n_boolean) + sign(g_cols(i).n_array_scalar);


      -- -----------------------------------------------------------------------
      -- Skip what cannot become a column: over-long paths, a parent whose
      -- elements never were objects, and an always-null key that elsewhere
      -- is an object (its fields already are columns).
      -- -----------------------------------------------------------------------
      if length(g_cols(i).path) > gc_path_max
         or (g_cols(i).parent_idx is not null and g_cols(g_cols(i).parent_idx).emit_yn = 'N')
      then
        g_cols(i).emit_yn := 'N';
      elsif l_kinds = 0 and g_cols(i).n_array_object = 0 and g_cols(i).n_array_empty = 0 then
        for j in 1 .. g_cols.count
        loop
          if g_cols(j).ctx_key = g_cols(i).ctx_key
             and substr(g_cols(j).path, 1, length(g_cols(i).path) + 1) = g_cols(i).path || '.'
          then
            g_cols(i).emit_yn := 'N';
            exit;
          end if;
        end loop;
      end if;

      if g_cols(i).emit_yn = 'Y' then

        -- ---------------------------------------------------------------------
        -- Data type, source type, format mask, length
        -- ---------------------------------------------------------------------
        if g_cols(i).n_array_object > 0
           or (l_kinds = 0 and g_cols(i).n_array_empty > 0)
           or (l_kinds = 1 and g_cols(i).n_array_scalar > 0)
        then
          g_cols(i).data_type_code   := 'clob';
          g_cols(i).source_data_type := 'array';
        elsif l_kinds = 0 then
          g_cols(i).data_type_code      := 'varchar2';
          g_cols(i).source_data_type    := 'null';
          g_cols(i).max_observed_length := gc_varchar2_min;
          add_note('only null values observed' || gc_note_dash || 'proposed as varchar2');
        elsif l_kinds > 1 then
          g_cols(i).source_data_type := 'mixed';
          if g_cols(i).is_long_yn = 'Y' or g_cols(i).max_length > gc_varchar2_max or g_cols(i).n_array_scalar > 0 then
            g_cols(i).data_type_code := 'clob';
          else
            g_cols(i).data_type_code      := 'varchar2';
            g_cols(i).max_observed_length := round_length(g_cols(i).max_length);
          end if;
          add_note('mixed JSON types observed' || gc_note_dash || 'proposed as ' || g_cols(i).data_type_code);
        elsif g_cols(i).n_number > 0 then
          g_cols(i).data_type_code   := 'number';
          g_cols(i).source_data_type := 'number';
        elsif g_cols(i).n_boolean > 0 then
          g_cols(i).data_type_code   := 'boolean';
          g_cols(i).source_data_type := 'boolean';
        else
          g_cols(i).source_data_type := 'string';

          if g_cols(i).is_long_yn = 'Y' or g_cols(i).max_length > gc_varchar2_max then
            g_cols(i).data_type_code := 'clob';
          elsif g_cols(i).n_timestamp = g_cols(i).n_string then
            g_cols(i).format_mask := pick_timestamp_mask(
                                         p_idx  => i
                                     );

            if g_cols(i).format_mask is not null then
              g_cols(i).data_type_code := 'timestamp_with_time_zone';
            else
              g_cols(i).data_type_code      := 'varchar2';
              g_cols(i).max_observed_length := round_length(g_cols(i).max_length);
              add_note('timestamps in mixed formats' || gc_note_dash || 'proposed as varchar2');
            end if;
          elsif g_cols(i).n_date = g_cols(i).n_string then
            g_cols(i).data_type_code := 'date';
            g_cols(i).format_mask    := gc_mask_date;
          else
            g_cols(i).data_type_code      := 'varchar2';
            g_cols(i).max_observed_length := round_length(g_cols(i).max_length);
          end if;
        end if;


        -- ---------------------------------------------------------------------
        -- Nullability and its observation note
        -- ---------------------------------------------------------------------
        l_rows_total  := g_ctxs(g_cols(i).ctx_key).rows_total;
        l_ctx_samples := g_ctxs(g_cols(i).ctx_key).samples_with_rows;
        l_absent_rows := l_rows_total - g_cols(i).present_rows - g_cols(i).null_rows;

        if g_cols(i).present_rows < l_rows_total then
          g_cols(i).is_nullable_yn := 'Y';

          l_missing_kind := case
                              when l_absent_rows > 0 and g_cols(i).null_rows > 0 then 'missing or null'
                              when g_cols(i).null_rows > 0                        then 'null'
                              else 'missing'
                            end;

          if l_ctx_samples > 1 then
            add_note(l_missing_kind || ' in ' || g_cols(i).samples_missing || ' of ' || l_ctx_samples || ' samples' || gc_note_dash || 'marked as nullable');
          else
            add_note(l_missing_kind || ' in ' || (l_rows_total - g_cols(i).present_rows) || ' of ' || l_rows_total || ' rows' || gc_note_dash || 'marked as nullable');
          end if;
        end if;

        g_cols(i).observation_note := substr(l_note, 1, gc_note_max);


        -- ---------------------------------------------------------------------
        -- Column name
        -- ---------------------------------------------------------------------
        l_leaf       := to_snake(g_cols(i).leaf_name);
        l_snake_path := to_snake(g_cols(i).path);

        if g_cols(i).parent_idx is null then
          l_base := case
                      when l_snake_path = 'id' and p_entity is not null then p_entity || '_id'
                      else l_snake_path
                    end;
        else
          l_base := singular(g_cols(g_cols(i).parent_idx).column_name)
                 || '_' || l_snake_path;
        end if;

        if g_cols(i).data_type_code in ('timestamp_with_time_zone', 'date')
           and instr(gc_audit_leaves, ' ' || l_leaf || ' ') > 0
        then
          l_base := l_base || '_on';
        elsif g_cols(i).data_type_code = 'number'
              and instr(gc_percent_leaves, ' ' || l_leaf || ' ') > 0
              and g_cols(i).num_min >= 0
              and g_cols(i).num_max <= 100
        then
          l_base := l_base || '_pct';
        end if;

        l_base := substr(l_base, 1, gc_name_max);
        if is_reserved_word(l_base) then
          l_base := l_base || '_val';
        end if;

        l_name     := l_base;
        l_suffix_n := 1;
        while l_used.exists(l_name)
        loop
          l_suffix_n := l_suffix_n + 1;
          l_name     := substr(l_base, 1, gc_name_max - length(l_suffix_n) - 1) || '_' || l_suffix_n;
        end loop;

        l_used(l_name)        := 'Y';
        g_cols(i).column_name := l_name;
      end if;
    end loop;


    -- -------------------------------------------------------------------------
    -- Primary key proposal: top-level "id" first, else the first *_id / uuid
    -- / code; never nullable, never a nested or non-key type.
    -- -------------------------------------------------------------------------
    for l_pass in 1 .. 2
    loop
      for i in 1 .. g_cols.count
      loop
        if g_cols(i).emit_yn = 'Y'
           and g_cols(i).parent_idx is null
           and instr(g_cols(i).path, '.') = 0
           and g_cols(i).is_nullable_yn = 'N'
           and g_cols(i).data_type_code in ('number', 'varchar2')
        then
          l_snake_path := to_snake(g_cols(i).path);

          if (l_pass = 1 and l_snake_path = 'id')
             or (l_pass = 2 and (l_snake_path like '%\_id' escape '\' or l_snake_path in ('uuid', 'code')))
          then
            l_pk_idx := i;
            exit;
          end if;
        end if;
      end loop;

      exit when l_pk_idx is not null;
    end loop;

    if l_pk_idx is not null then
      g_cols(l_pk_idx).is_primary_key_yn := 'Y';
    end if;

    logger.append_param(l_params, 'l_pk_idx', l_pk_idx);
    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end finalize_columns;








  -- ===========================================================================
  -- FUNCTION: save_sample
  -- ===========================================================================
  /**
   * Marks an execution as a discovery sample of its endpoint. Only a
   * successful call (request_status_code = success, HTTP 2xx, text body)
   * whose body is a JSON object or array qualifies; anything else returns
   * null without raising. Idempotent: an execution already saved returns
   * its existing sample (reactivated when it had been deactivated).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_sample_id arw_response_samples.sample_id%type;
   * begin
   *   l_sample_id := arw_discover_api.save_sample(
   *       p_execution_id                       => 1
   *   );
   *   dbms_output.put_line('sample_id = ' || nvl(to_char(l_sample_id), '<not a sample>'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_execution_id Execution to save as a sample
   * @return arw_response_samples.sample_id%type  Sample id, or null when the execution does not qualify
   */
  function save_sample(
      p_execution_id                            in arw_executions.execution_id%type
  )
  return arw_response_samples.sample_id%type
  is
    l_scope          logger_logs.scope%type := gc_scope_prefix || 'save_sample';
    l_params         logger.tab_param;
    l_endpoint_id    arw_executions.endpoint_id%type;
    l_status_code    arw_executions.request_status_code%type;
    l_http_status    arw_executions.http_status_code%type;
    l_is_binary_yn   arw_executions.response_is_binary_yn%type;
    l_is_json_yn     varchar2(1 char);
    l_sample_id      arw_response_samples.sample_id%type;
  begin
    logger.append_param(l_params, 'p_execution_id', p_execution_id);
    logger.log('START', l_scope, null, l_params);

    begin
      select e.endpoint_id                                 as endpoint_id
           , e.request_status_code                         as request_status_code
           , e.http_status_code                            as http_status_code
           , e.response_is_binary_yn                       as response_is_binary_yn
           , case
               when e.response_body_clob is json disallow scalars then 'Y'
               else 'N'
             end                                           as is_json_yn
        into l_endpoint_id
           , l_status_code
           , l_http_status
           , l_is_binary_yn
           , l_is_json_yn
        from arw_executions e
       where e.execution_id = p_execution_id
         and e.active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_not_found, 'Execution not found: ' || p_execution_id);
    end;

    if l_status_code != 'success'
       or nvl(l_http_status, 0) not between 200 and 299
       or l_is_binary_yn = 'Y'
       or l_is_json_yn = 'N'
    then
      logger.log('END - execution does not qualify as a sample', l_scope, null, l_params);
      return null;
    end if;

    select max(s.sample_id)                                as sample_id
      into l_sample_id
      from arw_response_samples s
     where s.execution_id = p_execution_id;

    if l_sample_id is null then
      begin
        insert
          into arw_response_samples (
               endpoint_id
             , execution_id
        )
        values (
               l_endpoint_id
             , p_execution_id
        )
        returning sample_id into l_sample_id;
      exception
        when dup_val_on_index then
          -- Saved concurrently by another session: reuse that sample
          select s.sample_id                               as sample_id
            into l_sample_id
            from arw_response_samples s
           where s.execution_id = p_execution_id;
      end;
    else
      update arw_response_samples s
         set s.active_yn = 'Y'
       where s.sample_id = l_sample_id
         and s.active_yn = 'N';
    end if;

    logger.append_param(l_params, 'l_sample_id', l_sample_id);
    logger.log('END', l_scope, null, l_params);

    return l_sample_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end save_sample;








  -- ===========================================================================
  -- FUNCTION: sample_count
  -- ===========================================================================
  /**
   * Number of active response samples collected for an endpoint (the
   * "Sample saved -- 3 collected for this endpoint" line on Page 210).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_sample_count number;
   * begin
   *   l_sample_count := arw_discover_api.sample_count(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('samples = ' || l_sample_count);
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint whose samples are counted
   * @return number  Active samples of the endpoint (0 when none)
   */
  function sample_count(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return number
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'sample_count';
    l_params logger.tab_param;
    l_count  number;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as sample_n
      into l_count
      from arw_response_samples s
     where s.endpoint_id = p_endpoint_id
       and s.active_yn = 'Y';

    logger.append_param(l_params, 'l_count', l_count);
    logger.log('END', l_scope, null, l_params);

    return l_count;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end sample_count;








  -- ===========================================================================
  -- FUNCTION: derive_profile
  -- ===========================================================================
  /**
   * Consolidates ALL active samples of an endpoint into a new data profile
   * in 'proposal' status (IMPLEMENTATION.md section 6, Page 210 Discovery
   * mockup). The row selector is voted across samples; every row of every
   * sample is walked; types, lengths, masks, nullability (with an
   * observation note), names and a single PK are proposed. The new profile
   * links to the newest sample, records sample_count, and replaces the
   * endpoint's previous active profiles (soft-deleted with their columns).
   *
   * @example
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.derive_profile(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || l_data_profile_id);
   *   for c in (
   *     select pc.column_name || ' ' || pc.path_expression || ' ' || pc.data_type_code
   *            || ' ' || pc.max_observed_length || ' null=' || pc.is_nullable_yn
   *            || ' pk=' || pc.is_primary_key_yn                  as line
   *       from arw_profile_columns pc
   *      where pc.data_profile_id = l_data_profile_id
   *      order by pc.sequence_num
   *   )
   *   loop
   *     dbms_output.put_line(c.line);
   *   end loop;
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint whose samples are consolidated
   * @return arw_data_profiles.data_profile_id%type  Identifier of the new profile
   */
  function derive_profile(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return arw_data_profiles.data_profile_id%type
  is
    type t_root_tab is table of json_element_t index by pls_integer;
    type t_vote_tab is table of pls_integer index by varchar2(4000 char);

    l_scope            logger_logs.scope%type := gc_scope_prefix || 'derive_profile';
    l_params           logger.tab_param;
    l_endpoint_name    arw_endpoints.name%type;
    l_url_path         arw_endpoints.url_path%type;
    l_roots            t_root_tab;
    l_votes            t_vote_tab;
    l_newest_sample_id arw_response_samples.sample_id%type;
    l_selector         varchar2(4000 char);
    l_strong_yn        varchar2(1 char);
    l_best_selector    varchar2(4000 char);
    l_best_votes       pls_integer := 0;
    l_row_selector     arw_data_profiles.row_selector%type;
    l_entity           varchar2(4000 char);
    l_profile_name     arw_data_profiles.name%type;
    l_sample_count     arw_data_profiles.sample_count%type;
    l_data_profile_id  arw_data_profiles.data_profile_id%type;
    l_sequence_num     pls_integer := 0;
    l_column_id        arw_profile_columns.column_id%type;
    l_parent_id        arw_profile_columns.column_id%type;

    -- Adds p_weight votes to a row selector; the latest selector wins a tie
    procedure cast_vote(
        p_selector                              in varchar2
      , p_weight                                in pls_integer
    )
    is
    begin
      l_votes(p_selector) := case when l_votes.exists(p_selector) then l_votes(p_selector) else 0 end + p_weight;

      if l_votes(p_selector) >= l_best_votes then
        l_best_votes    := l_votes(p_selector);
        l_best_selector := p_selector;
      end if;
    end cast_vote;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    g_cols.delete;
    g_col_map.delete;
    g_ctxs.delete;

    begin
      select e.name                                        as endpoint_name
           , e.url_path                                    as url_path
        into l_endpoint_name
           , l_url_path
        from arw_endpoints e
       where e.endpoint_id = p_endpoint_id;
    exception
      when no_data_found then
        raise_application_error(gc_err_not_found, 'Endpoint not found: ' || p_endpoint_id);
    end;


    -- -------------------------------------------------------------------------
    -- Parse every active sample (oldest first) and vote the row selector
    -- -------------------------------------------------------------------------
    for l_sample in (
      select s.sample_id                                   as sample_id
           , e.response_body_clob                          as response_body
        from arw_response_samples s
        join arw_executions       e on e.execution_id = s.execution_id
       where s.endpoint_id = p_endpoint_id
         and s.active_yn = 'Y'
       order by s.sample_id
    )
    loop
      l_roots(l_roots.count + 1) := json_element_t.parse(l_sample.response_body);
      l_newest_sample_id         := l_sample.sample_id;

      find_row_selector(
          p_root                                => l_roots(l_roots.count)
        , o_selector                            => l_selector
        , o_strong_yn                           => l_strong_yn
      );

      -- A certain selector weighs 2; a guess (empty array) weighs 1 and gives
      -- single-row 1 as well, voted last so single-row wins a tie.
      if l_selector is not null then
        cast_vote(
            p_selector                          => l_selector
          , p_weight                            => case when l_strong_yn = 'Y' then 2 else 1 end
        );

        if l_strong_yn = 'N' then
          cast_vote(
              p_selector                        => gc_sel_single
            , p_weight                          => 1
          );
        end if;
      end if;
    end loop;

    if l_roots.count = 0 then
      raise_application_error(gc_err_not_found, 'No active samples found for endpoint ' || p_endpoint_id || ' -- save a successful JSON response first.');
    end if;

    if l_best_selector is null then
      raise_application_error(gc_err_invalid, 'The samples of endpoint ' || p_endpoint_id || ' hold no JSON object or array to profile.');
    end if;

    l_row_selector := case when l_best_selector in (gc_sel_root, gc_sel_single) then null else l_best_selector end;
    logger.append_param(l_params, 'l_row_selector', l_row_selector);


    -- =========================================================================
    -- Walk every row of every sample, then turn observations into a proposal.
    -- =========================================================================

    ensure_ctx(
        p_ctx_key                               => gc_ctx_top
    );

    for i in 1 .. l_roots.count
    loop
      consume_sample(
          p_root                                => l_roots(i)
        , p_selector                            => l_best_selector
      );
    end loop;

    if g_ctxs(gc_ctx_top).rows_total = 0 or g_cols.count = 0 then
      raise_application_error(gc_err_invalid, 'The samples of endpoint ' || p_endpoint_id || ' contain no rows with fields to profile.');
    end if;

    l_entity := entity_name(
                    p_row_selector              => l_row_selector
                  , p_url_path                  => l_url_path
                );

    finalize_columns(
        p_entity                                => l_entity
    );
    -- =========================================================================


    -- -------------------------------------------------------------------------
    -- Replace the endpoint's previous active profiles
    -- -------------------------------------------------------------------------
    update arw_profile_columns pc
       set pc.active_yn = 'N'
     where pc.active_yn = 'Y'
       and pc.data_profile_id in (
             select p.data_profile_id                      as data_profile_id
               from arw_data_profiles     p
               join arw_response_samples  s on s.sample_id = p.response_sample_id
              where s.endpoint_id = p_endpoint_id
                and p.active_yn = 'Y'
           );

    update arw_data_profiles p
       set p.active_yn = 'N'
     where p.active_yn = 'Y'
       and p.response_sample_id in (
             select s.sample_id                            as sample_id
               from arw_response_samples s
              where s.endpoint_id = p_endpoint_id
           );


    -- -------------------------------------------------------------------------
    -- Store the new proposal
    -- -------------------------------------------------------------------------
    l_profile_name := substr(upper(to_snake(l_endpoint_name)), 1, gc_name_max);
    l_sample_count := l_roots.count;

    insert
      into arw_data_profiles (
           response_sample_id
         , name
         , row_selector
         , format_code
         , profile_status_code
         , sample_count
    )
    values (
           l_newest_sample_id
         , l_profile_name
         , l_row_selector
         , 'json'
         , 'proposal'
         , l_sample_count
    )
    returning data_profile_id into l_data_profile_id;

    for i in 1 .. g_cols.count
    loop
      if g_cols(i).emit_yn = 'Y' then
        l_sequence_num := l_sequence_num + 1;
        l_parent_id    := case when g_cols(i).parent_idx is not null then g_cols(g_cols(i).parent_idx).column_id end;

        insert
          into arw_profile_columns (
               data_profile_id
             , parent_column_id
             , column_name
             , path_expression
             , sequence_num
             , data_type_code
             , source_data_type
             , format_mask
             , max_observed_length
             , is_nullable_yn
             , is_primary_key_yn
             , observation_note
        )
        values (
               l_data_profile_id
             , l_parent_id
             , g_cols(i).column_name
             , g_cols(i).path
             , l_sequence_num
             , g_cols(i).data_type_code
             , g_cols(i).source_data_type
             , g_cols(i).format_mask
             , g_cols(i).max_observed_length
             , g_cols(i).is_nullable_yn
             , g_cols(i).is_primary_key_yn
             , g_cols(i).observation_note
        )
        returning column_id into l_column_id;

        g_cols(i).column_id := l_column_id;
      end if;
    end loop;

    logger.append_param(l_params, 'l_sample_count', l_sample_count);
    logger.append_param(l_params, 'column_count', l_sequence_num);
    logger.append_param(l_params, 'l_data_profile_id', l_data_profile_id);
    logger.log('END', l_scope, null, l_params);

    g_cols.delete;
    g_col_map.delete;
    g_ctxs.delete;

    return l_data_profile_id;
  exception
    when others then
      g_cols.delete;
      g_col_map.delete;
      g_ctxs.delete;
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end derive_profile;








  -- ===========================================================================
  -- FUNCTION: current_profile_id
  -- ===========================================================================
  /**
   * The endpoint's active data profile (the newest one, should more than
   * one ever be active), or null when it has none yet.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_data_profile_id arw_data_profiles.data_profile_id%type;
   * begin
   *   l_data_profile_id := arw_discover_api.current_profile_id(
   *       p_endpoint_id                        => 1
   *   );
   *   dbms_output.put_line('data_profile_id = ' || nvl(to_char(l_data_profile_id), '<none>'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_endpoint_id Endpoint whose profile is looked up
   * @return arw_data_profiles.data_profile_id%type  Active profile id, or null
   */
  function current_profile_id(
      p_endpoint_id                             in arw_endpoints.endpoint_id%type
  )
  return arw_data_profiles.data_profile_id%type
  is
    l_scope           logger_logs.scope%type := gc_scope_prefix || 'current_profile_id';
    l_params          logger.tab_param;
    l_data_profile_id arw_data_profiles.data_profile_id%type;
  begin
    logger.append_param(l_params, 'p_endpoint_id', p_endpoint_id);
    logger.log('START', l_scope, null, l_params);

    select max(p.data_profile_id)                          as data_profile_id
      into l_data_profile_id
      from arw_data_profiles     p
      join arw_response_samples  s on s.sample_id = p.response_sample_id
     where s.endpoint_id = p_endpoint_id
       and p.active_yn = 'Y';

    logger.append_param(l_params, 'l_data_profile_id', l_data_profile_id);
    logger.log('END', l_scope, null, l_params);

    return l_data_profile_id;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end current_profile_id;








  -- ===========================================================================
  -- PROCEDURE: update_column
  -- ===========================================================================
  /**
   * Saves the developer's edit of one proposed column (Page 215) and puts
   * the profile back in 'proposal' status. Validates the data type, the Y/N
   * flags, the column name (Oracle-safe, not reserved, unique in the
   * profile), the varchar2 length, and that a primary key is a top-level,
   * non-nullable column; marking a column as PK clears any other PK of the
   * profile. Length is kept only for varchar2 (the only type that uses it).
   *
   * @example
   * begin
   *   arw_discover_api.update_column(
   *       p_column_id                          => 1
   *     , p_column_name                        => 'discount_pct'
   *     , p_data_type_code                     => 'number'
   *     , p_max_observed_length                => null
   *     , p_format_mask                        => null
   *     , p_is_nullable_yn                     => 'Y'
   *     , p_is_primary_key_yn                  => 'N'
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_column_id Column to update
   * @param p_column_name New column name (stored in lowercase)
   * @param p_data_type_code varchar2, number, date, timestamp_with_time_zone, boolean or clob
   * @param p_max_observed_length varchar2 length (1-32767); ignored for other types
   * @param p_format_mask Format mask (dates/timestamps); null when not needed
   * @param p_is_nullable_yn Y when the column may be null
   * @param p_is_primary_key_yn Y to make this the profile's only primary key
   */
  procedure update_column(
      p_column_id                               in arw_profile_columns.column_id%type
    , p_column_name                             in arw_profile_columns.column_name%type
    , p_data_type_code                          in arw_profile_columns.data_type_code%type
    , p_max_observed_length                     in arw_profile_columns.max_observed_length%type
    , p_format_mask                             in arw_profile_columns.format_mask%type
    , p_is_nullable_yn                          in arw_profile_columns.is_nullable_yn%type
    , p_is_primary_key_yn                       in arw_profile_columns.is_primary_key_yn%type
  )
  is
    l_scope           logger_logs.scope%type := gc_scope_prefix || 'update_column';
    l_params          logger.tab_param;
    l_data_profile_id arw_profile_columns.data_profile_id%type;
    l_parent_id       arw_profile_columns.parent_column_id%type;
    l_column_name     arw_profile_columns.column_name%type := lower(trim(p_column_name));
    l_duplicate_n     number;
  begin
    logger.append_param(l_params, 'p_column_id', p_column_id);
    logger.append_param(l_params, 'p_column_name', p_column_name);
    logger.append_param(l_params, 'p_data_type_code', p_data_type_code);
    logger.append_param(l_params, 'p_max_observed_length', p_max_observed_length);
    logger.append_param(l_params, 'p_format_mask', p_format_mask);
    logger.append_param(l_params, 'p_is_nullable_yn', p_is_nullable_yn);
    logger.append_param(l_params, 'p_is_primary_key_yn', p_is_primary_key_yn);
    logger.log('START', l_scope, null, l_params);

    begin
      select pc.data_profile_id                            as data_profile_id
           , pc.parent_column_id                           as parent_column_id
        into l_data_profile_id
           , l_parent_id
        from arw_profile_columns pc
        join arw_data_profiles   p on p.data_profile_id = pc.data_profile_id
       where pc.column_id = p_column_id
         and pc.active_yn = 'Y'
         and p.active_yn = 'Y';
    exception
      when no_data_found then
        raise_application_error(gc_err_not_found, 'Profile column not found: ' || p_column_id);
    end;


    -- -------------------------------------------------------------------------
    -- Validate the edit
    -- -------------------------------------------------------------------------
    if p_data_type_code is null
       or p_data_type_code not in ('varchar2', 'number', 'date', 'timestamp_with_time_zone', 'boolean', 'clob')
    then
      raise_application_error(gc_err_invalid, 'Invalid data type: ' || nvl(p_data_type_code, '<null>') || ' (expected varchar2, number, date, timestamp_with_time_zone, boolean or clob).');
    end if;

    if nvl(p_is_nullable_yn, '?') not in ('Y', 'N') or nvl(p_is_primary_key_yn, '?') not in ('Y', 'N') then
      raise_application_error(gc_err_invalid, 'Nullable and primary key flags must be Y or N.');
    end if;

    if l_column_name is null
       or length(l_column_name) > gc_name_max
       or not regexp_like(l_column_name, '^[a-z][a-z0-9_$#]*$')
    then
      raise_application_error(gc_err_invalid, 'Invalid column name: use a letter followed by letters, digits or underscores (max ' || gc_name_max || ' characters).');
    end if;

    if is_reserved_word(l_column_name) then
      raise_application_error(gc_err_invalid, 'Column name "' || l_column_name || '" is an Oracle reserved word.');
    end if;

    select count(1)                                        as duplicate_n
      into l_duplicate_n
      from arw_profile_columns pc
     where pc.data_profile_id = l_data_profile_id
       and pc.column_id != p_column_id
       and pc.active_yn = 'Y'
       and pc.column_name = l_column_name;

    if l_duplicate_n > 0 then
      raise_application_error(gc_err_invalid, 'Another column of this profile is already named "' || l_column_name || '".');
    end if;

    if p_data_type_code = 'varchar2'
       and (p_max_observed_length is null
            or p_max_observed_length != trunc(p_max_observed_length)
            or p_max_observed_length not between 1 and 32767)
    then
      raise_application_error(gc_err_invalid, 'A varchar2 column needs a whole length between 1 and 32767.');
    end if;

    if p_is_primary_key_yn = 'Y' then
      if p_is_nullable_yn = 'Y' then
        raise_application_error(gc_err_invalid, 'A primary key column cannot be nullable.');
      elsif l_parent_id is not null then
        raise_application_error(gc_err_invalid, 'Only a top-level column can be the primary key.');
      elsif p_data_type_code in ('boolean', 'clob') then
        raise_application_error(gc_err_invalid, 'A ' || p_data_type_code || ' column cannot be the primary key.');
      end if;
    end if;


    -- -------------------------------------------------------------------------
    -- Save: single PK per profile, profile back to proposal
    -- -------------------------------------------------------------------------
    if p_is_primary_key_yn = 'Y' then
      update arw_profile_columns pc
         set pc.is_primary_key_yn = 'N'
       where pc.data_profile_id = l_data_profile_id
         and pc.column_id != p_column_id
         and pc.is_primary_key_yn = 'Y';
    end if;

    update arw_profile_columns pc
       set pc.column_name          = l_column_name
         , pc.data_type_code       = p_data_type_code
         , pc.max_observed_length  = case when p_data_type_code = 'varchar2' then p_max_observed_length end
         , pc.format_mask          = p_format_mask
         , pc.is_nullable_yn       = p_is_nullable_yn
         , pc.is_primary_key_yn    = p_is_primary_key_yn
     where pc.column_id = p_column_id;

    update arw_data_profiles p
       set p.profile_status_code = 'proposal'
     where p.data_profile_id = l_data_profile_id
       and p.profile_status_code != 'proposal';

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end update_column;








  -- ===========================================================================
  -- PROCEDURE: accept_profile
  -- ===========================================================================
  /**
   * Marks an active profile as reviewed ('accepted'), the "Accept profile"
   * button of the Page 210 Discovery tab. Refuses a profile without any
   * active column.
   *
   * @example
   * begin
   *   arw_discover_api.accept_profile(
   *       p_data_profile_id                    => 1
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_data_profile_id Profile to accept
   */
  procedure accept_profile(
      p_data_profile_id                         in arw_data_profiles.data_profile_id%type
  )
  is
    l_scope     logger_logs.scope%type := gc_scope_prefix || 'accept_profile';
    l_params    logger.tab_param;
    l_profile_n number;
    l_column_n  number;
  begin
    logger.append_param(l_params, 'p_data_profile_id', p_data_profile_id);
    logger.log('START', l_scope, null, l_params);

    select count(1)                                        as profile_n
      into l_profile_n
      from arw_data_profiles p
     where p.data_profile_id = p_data_profile_id
       and p.active_yn = 'Y';

    if l_profile_n = 0 then
      raise_application_error(gc_err_not_found, 'Data profile not found or inactive: ' || p_data_profile_id);
    end if;

    select count(1)                                        as column_n
      into l_column_n
      from arw_profile_columns pc
     where pc.data_profile_id = p_data_profile_id
       and pc.active_yn = 'Y';

    if l_column_n = 0 then
      raise_application_error(gc_err_invalid, 'Data profile ' || p_data_profile_id || ' has no columns to accept.');
    end if;

    update arw_data_profiles p
       set p.profile_status_code = 'accepted'
     where p.data_profile_id = p_data_profile_id;

    logger.log('END', l_scope, null, l_params);
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end accept_profile;








  -- ===========================================================================
  -- FUNCTION: data_type_label
  -- ===========================================================================
  /**
   * Display label of a data_type_code as the Page 210 mockup and the
   * APEXlang dataProfileColumn show it (timestamp_with_time_zone ->
   * timestampWithTimeZone); other codes are returned unchanged.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(
   *     arw_discover_api.data_type_label(
   *         p_data_type_code                   => 'timestamp_with_time_zone'
   *     )
   *   );
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - Discovery)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_data_type_code Data type code of a profile column
   * @return varchar2  Display label
   */
  function data_type_label(
      p_data_type_code                          in arw_profile_columns.data_type_code%type
  )
  return varchar2
  deterministic
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'data_type_label';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_data_type_code', p_data_type_code);
    logger.log('START', l_scope, null, l_params);
    $end

    return case p_data_type_code
             when 'timestamp_with_time_zone' then 'timestampWithTimeZone'
             else p_data_type_code
           end;
  exception
    when others then
      logger.append_param(l_params, 'p_data_type_code', p_data_type_code);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end data_type_label;


end arw_discover_api;
/
