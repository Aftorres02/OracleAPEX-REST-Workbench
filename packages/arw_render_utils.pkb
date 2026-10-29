-- Implements: .claude/rules/plsql-standards.md (package body spacing, parameter alignment, logging, doc tags)
create or replace package body arw_render_utils
as

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

  gc_err_invalid_template constant number := -20946;

  gc_lf constant varchar2(1) := chr(10);

  -- Words that cannot be used as unquoted SQL/PL/SQL identifiers; a
  -- generated name that collides gets a "_col" suffix.
  gc_reserved_words constant varchar2(4000 char) := ':access:add:all:alter:and:any:as:asc:audit:begin:between:by:case:char'
    || ':check:cluster:column:comment:compress:connect:create:current:cursor:date:decimal:declare:default:delete:desc'
    || ':distinct:drop:else:elsif:end:exception:exclusive:exists:file:float:for:from:function:goto:grant:group:having'
    || ':identified:if:immediate:in:increment:index:initial:insert:integer:intersect:into:is:level:like:lock:long:loop'
    || ':maxextents:minus:mlslabel:mode:modify:noaudit:nocompress:not:nowait:null:number:of:offline:on:online:option'
    || ':or:order:package:pctfree:prior:procedure:public:raw:record:rename:resource:return:revoke:row:rowid:rownum'
    || ':rows:select:session:set:share:size:smallint:start:successful:synonym:sysdate:table:then:to:trigger:uid:union'
    || ':unique:update:user:validate:values:varchar:varchar2:view:when:whenever:where:while:with:';

  -- Note: render/render_line run once per template line; their START/END
  -- logs are compiled in only with VERBOSE_OUTPUT:TRUE
  -- (plsql-standards.md section 13) so a generation does not flood
  -- logger_logs. Errors are always logged.








  -- ===========================================================================
  -- PROCEDURE: set_token
  -- ===========================================================================
  /**
   * Sets (or overwrites) one token value.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_tokens arw_render_utils.t_tokens;
   * begin
   *   arw_render_utils.set_token(
   *       io_tokens                            => l_tokens
   *     , p_name                               => 'package_name'
   *     , p_value                              => 'demo_todos_api'
   *   );
   *   dbms_output.put_line(arw_render_utils.render('create package {{package_name}}', l_tokens));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param io_tokens Token collection to update
   * @param p_name Token name (letters, digits, underscore)
   * @param p_value Token value; null makes the token falsy
   */
  procedure set_token(
      io_tokens                                 in out nocopy t_tokens
    , p_name                                    in varchar2
    , p_value                                   in clob
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'set_token';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);
    $end

    io_tokens(p_name) := p_value;

    $if $$verbose_output $then
    logger.log('END', l_scope, null, l_params);
    $end
  exception
    when others then
      logger.append_param(l_params, 'p_name', p_name);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end set_token;








  -- ===========================================================================
  -- PROCEDURE: set_flag
  -- ===========================================================================
  /**
   * Sets a boolean token for {{#name}} / {{^name}} blocks: 'Y' when p_on,
   * 'N' otherwise.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_tokens arw_render_utils.t_tokens;
   * begin
   *   arw_render_utils.set_flag(
   *       io_tokens                            => l_tokens
   *     , p_name                               => 'has_credential'
   *     , p_on                                 => false
   *   );
   *   dbms_output.put_line(arw_render_utils.render('auth:{{#has_credential}}yes{{/has_credential}}{{^has_credential}}no{{/has_credential}}', l_tokens));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param io_tokens Token collection to update
   * @param p_name Flag name
   * @param p_on True to make the flag truthy
   */
  procedure set_flag(
      io_tokens                                 in out nocopy t_tokens
    , p_name                                    in varchar2
    , p_on                                      in boolean
  )
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'set_flag';
    l_params logger.tab_param;
  begin
    $if $$verbose_output $then
    logger.append_param(l_params, 'p_name', p_name);
    logger.log('START', l_scope, null, l_params);
    $end

    io_tokens(p_name) := case when p_on then 'Y' else 'N' end;

    $if $$verbose_output $then
    logger.log('END', l_scope, null, l_params);
    $end
  exception
    when others then
      logger.append_param(l_params, 'p_name', p_name);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end set_flag;








  -- ===========================================================================
  -- FUNCTION: is_truthy (private)
  -- ===========================================================================
  /**
   * True when the token is set, not empty and not 'N'.
   *
   * @example N/A -- private package-body unit; exercised through render.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_tokens Token collection
   * @param p_name Token name
   * @return boolean True when the token counts as "on"
   */
  function is_truthy(
      p_tokens                                  in t_tokens
    , p_name                                    in varchar2
  )
  return boolean
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'is_truthy';
    l_params logger.tab_param;
  begin
    if not p_tokens.exists(p_name) then
      return false;
    end if;

    return p_tokens(p_name) is not null
       and dbms_lob.getlength(p_tokens(p_name)) > 0
       and dbms_lob.compare(p_tokens(p_name), to_clob('N')) != 0;
  exception
    when others then
      logger.append_param(l_params, 'p_name', p_name);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end is_truthy;








  -- ===========================================================================
  -- FUNCTION: render_line (private)
  -- ===========================================================================
  /**
   * Renders one template line: resolves inline {{#x}}..{{/x}} blocks, then
   * replaces every {{token}} that is set. Returns null when the line must
   * be dropped (a standalone token whose value is empty); otherwise the
   * rendered line(s) without the trailing line feed.
   *
   * @example N/A -- private package-body unit; exercised through render.
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_line Template line, without its line feed
   * @param p_tokens Token values
   * @param o_drop True when the line renders to nothing and must be dropped
   * @return clob Rendered text of the line
   */
  function render_line(
      p_line                                    in varchar2
    , p_tokens                                  in t_tokens
    , o_drop                                    out boolean
  )
  return clob
  is
    lc_open_pattern constant varchar2(100) := '\{\{[#^][A-Za-z0-9_]+\}\}';

    l_scope  logger_logs.scope%type := gc_scope_prefix || 'render_line';
    l_params logger.tab_param;

    l_line       varchar2(32767) := p_line;
    l_kind       varchar2(1);
    l_name       varchar2(100);
    l_keep       boolean;
    l_out        clob;
    l_pos        pls_integer := 1;
    l_start      pls_integer;
    l_end        pls_integer;
    l_close_pos  pls_integer;
    l_prefix     varchar2(32767);
    l_rest       varchar2(32767);
    l_value      clob;
    l_value_pos  pls_integer;
    l_value_nl   pls_integer;
    l_value_len  pls_integer;
    l_value_line varchar2(32767);
    l_repeat     varchar2(32767);
  begin
    o_drop := false;

    -- Inline conditional blocks: take the first opening tag, find its own
    -- closing tag, keep or drop the text in between; repeat.
    loop
      l_start := regexp_instr(l_line, lc_open_pattern);
      exit when l_start = 0;

      l_end  := instr(l_line, '}}', l_start);
      l_kind := substr(l_line, l_start + 2, 1);
      l_name := substr(l_line, l_start + 3, l_end - l_start - 3);
      l_close_pos := instr(l_line, '{{/' || l_name || '}}', l_end + 2);

      if l_close_pos = 0 then
        raise_application_error(gc_err_invalid_template, 'Inline block {{' || l_kind || l_name || '}} is never closed.');
      end if;

      l_keep := is_truthy(p_tokens, l_name);
      if l_kind = '^' then
        l_keep := not l_keep;
      end if;

      l_line := substr(l_line, 1, l_start - 1)
                || case when l_keep then substr(l_line, l_end + 2, l_close_pos - l_end - 2) end
                || substr(l_line, l_close_pos + length(l_name) + 5);
    end loop;

    l_start := null;
    l_end   := null;

    dbms_lob.createtemporary(l_out, true);

    loop
      l_start := instr(l_line, '{{', l_pos);
      exit when l_start = 0;
      l_end := instr(l_line, '}}', l_start + 2);
      exit when l_end = 0;

      l_name := substr(l_line, l_start + 2, l_end - l_start - 2);

      if regexp_like(l_name, '^[A-Za-z0-9_]+$') and p_tokens.exists(l_name) then
        l_prefix := substr(l_line, 1, l_start - 1);
        l_rest   := substr(l_line, l_end + 2);
        l_value  := p_tokens(l_name);

        -- Standalone token with an empty value: drop the whole line
        if trim(l_prefix) is null and trim(l_rest) is null
           and (l_value is null or dbms_lob.getlength(l_value) = 0) then
          o_drop := true;
          return null;
        end if;

        if l_start > l_pos then
          dbms_lob.append(l_out, substr(l_line, l_pos, l_start - l_pos));
        end if;

        if l_value is not null and dbms_lob.getlength(l_value) > 0 then
          if dbms_lob.instr(l_value, gc_lf) > 0
             and trim(l_rest) is null
             and regexp_like(l_prefix, '^ *(\*|--|//)? *$') then
            -- Multi-line value at the end of the line: repeat the line's
            -- indentation / comment prefix on every following line.
            l_repeat    := l_prefix;
            l_value_len := dbms_lob.getlength(l_value);
            l_value_pos := 1;
            loop
              l_value_nl := dbms_lob.instr(l_value, gc_lf, l_value_pos);
              if l_value_nl = 0 then
                l_value_line := dbms_lob.substr(l_value, l_value_len - l_value_pos + 1, l_value_pos);
              else
                l_value_line := dbms_lob.substr(l_value, l_value_nl - l_value_pos, l_value_pos);
              end if;

              if l_value_pos > 1 then
                dbms_lob.append(l_out, gc_lf);
                if l_value_line is not null then
                  dbms_lob.append(l_out, l_repeat);
                elsif rtrim(l_repeat) is not null then
                  dbms_lob.append(l_out, rtrim(l_repeat));
                end if;
              end if;

              if l_value_line is not null then
                dbms_lob.append(l_out, l_value_line);
              end if;

              exit when l_value_nl = 0 or l_value_nl = l_value_len;
              l_value_pos := l_value_nl + 1;
            end loop;
          else
            dbms_lob.append(l_out, l_value);
          end if;
        end if;
      else
        -- Not a set token: keep the text verbatim (e.g. a {{base_url}}
        -- placeholder the generated code must show)
        dbms_lob.append(l_out, substr(l_line, l_pos, l_end + 2 - l_pos));
      end if;

      l_pos := l_end + 2;
    end loop;

    if l_pos <= nvl(length(l_line), 0) then
      dbms_lob.append(l_out, substr(l_line, l_pos));
    end if;

    return l_out;
  exception
    when others then
      logger.append_param(l_params, 'p_line', substr(p_line, 1, 4000));
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end render_line;








  -- ===========================================================================
  -- FUNCTION: render
  -- ===========================================================================
  /**
   * Renders a template: drops standalone {{#x}}/{{^x}}/{{/x}} tag lines and
   * the lines inside falsy blocks (blocks nest), then renders every
   * remaining line with its tokens. Line feeds are normalized to LF and the
   * result always ends with one LF.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_tokens arw_render_utils.t_tokens;
   * begin
   *   arw_render_utils.set_token(l_tokens, 'name', 'get_todos');
   *   arw_render_utils.set_flag(l_tokens, 'has_body', false);
   *   dbms_output.put_line(arw_render_utils.render(
   *       p_template                           => 'function {{name}}' || chr(10)
   *                                               || '{{#has_body}}' || chr(10) || '  p_body' || chr(10) || '{{/has_body}}'
   *     , p_tokens                             => l_tokens
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_template Template text
   * @param p_tokens Token values
   * @return clob Rendered text
   */
  function render(
      p_template                                in clob
    , p_tokens                                  in t_tokens
  )
  return clob
  is
    type t_frame is record (
        name                                    varchar2(100)
      , include_yn                              varchar2(1)
    );
    type t_stack is table of t_frame index by pls_integer;

    l_scope    logger_logs.scope%type := gc_scope_prefix || 'render';
    l_params   logger.tab_param;
    l_template clob;
    l_result   clob;
    l_stack    t_stack;
    l_depth    pls_integer := 0;
    l_include  boolean := true;
    l_len      pls_integer;
    l_pos      pls_integer := 1;
    l_nl       pls_integer;
    l_line     varchar2(32767);
    l_trim     varchar2(32767);
    l_name     varchar2(100);
    l_truthy   boolean;
    l_rendered clob;
    l_drop     boolean;
  begin
    $if $$verbose_output $then
    logger.log('START', l_scope, null, l_params);
    $end

    dbms_lob.createtemporary(l_result, true);

    if p_template is null or dbms_lob.getlength(p_template) = 0 then
      return l_result;
    end if;

    l_template := replace(p_template, chr(13) || gc_lf, gc_lf);
    l_len      := dbms_lob.getlength(l_template);

    while l_pos <= l_len loop
      l_nl := dbms_lob.instr(l_template, gc_lf, l_pos);
      if l_nl = 0 then
        l_line := dbms_lob.substr(l_template, l_len - l_pos + 1, l_pos);
        l_pos  := l_len + 1;
      else
        l_line := case when l_nl > l_pos then dbms_lob.substr(l_template, l_nl - l_pos, l_pos) end;
        l_pos  := l_nl + 1;
      end if;

      l_trim := trim(l_line);

      if regexp_like(l_trim, '^\{\{[#^][A-Za-z0-9_]+\}\}$') then
        l_name   := substr(l_trim, 4, length(l_trim) - 5);
        l_truthy := is_truthy(p_tokens, l_name);
        if substr(l_trim, 3, 1) = '^' then
          l_truthy := not l_truthy;
        end if;

        l_depth := l_depth + 1;
        l_stack(l_depth).name       := l_name;
        l_stack(l_depth).include_yn := case when l_include then 'Y' else 'N' end;
        l_include := l_include and l_truthy;
      elsif regexp_like(l_trim, '^\{\{/[A-Za-z0-9_]+\}\}$') then
        l_name := substr(l_trim, 4, length(l_trim) - 5);
        if l_depth = 0 or l_stack(l_depth).name != l_name then
          raise_application_error(gc_err_invalid_template, 'Template block {{/' || l_name || '}} closes nothing or the wrong block.');
        end if;

        l_include := l_stack(l_depth).include_yn = 'Y';
        l_depth   := l_depth - 1;
      elsif l_include then
        if l_line is null then
          dbms_lob.append(l_result, gc_lf);
        else
          l_rendered := render_line(l_line, p_tokens, l_drop);
          if not l_drop then
            if l_rendered is not null and dbms_lob.getlength(l_rendered) > 0 then
              dbms_lob.append(l_result, l_rendered);
            end if;
            dbms_lob.append(l_result, gc_lf);
          end if;
        end if;
      end if;
    end loop;

    if l_depth > 0 then
      raise_application_error(gc_err_invalid_template, 'Template block {{#' || l_stack(l_depth).name || '}} is never closed.');
    end if;

    $if $$verbose_output $then
    logger.log('END', l_scope, null, l_params);
    $end

    return l_result;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end render;








  -- ===========================================================================
  -- FUNCTION: get_fragment
  -- ===========================================================================
  /**
   * Returns the raw template text of one section: the first variant of
   * p_variant_codes (colon-delimited, most specific first) that has active
   * rows for the type/section wins, and its rows are joined in
   * sequence_num order. Null when no variant has rows (the section is
   * skipped).
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.get_fragment(
   *       p_template_type_code                 => 'plsql_package'
   *     , p_section_code                       => 'invocation'
   *     , p_variant_codes                      => 'apex_web_service:default'
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_template_type_code Output type (arw_code_templates.template_type_code)
   * @param p_section_code Pipeline section
   * @param p_variant_codes Colon-delimited variant codes, most specific first
   * @return clob Joined fragment text; null when the section has no rows
   */
  function get_fragment(
      p_template_type_code                      in arw_code_templates.template_type_code%type
    , p_section_code                            in arw_code_templates.section_code%type
    , p_variant_codes                           in varchar2
  )
  return clob
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'get_fragment';
    l_params   logger.tab_param;
    l_variants apex_t_varchar2;
    l_fragment clob;
  begin
    logger.append_param(l_params, 'p_template_type_code', p_template_type_code);
    logger.append_param(l_params, 'p_section_code', p_section_code);
    logger.append_param(l_params, 'p_variant_codes', p_variant_codes);
    $if $$verbose_output $then
    logger.log('START', l_scope, null, l_params);
    $end

    l_variants := apex_string.split(p_variant_codes, ':');

    for i in 1 .. l_variants.count loop
      for l_rec in (
        select ct.template_body                            as template_body
          from arw_code_templates ct
         where ct.template_type_code = p_template_type_code
           and ct.section_code = p_section_code
           and ct.variant_code = l_variants(i)
           and ct.active_yn = 'Y'
         order by ct.sequence_num
                , ct.code_template_id
      )
      loop
        if l_fragment is null then
          dbms_lob.createtemporary(l_fragment, true);
        end if;

        dbms_lob.append(l_fragment, l_rec.template_body);
        if dbms_lob.substr(l_rec.template_body, 1, dbms_lob.getlength(l_rec.template_body)) != gc_lf then
          dbms_lob.append(l_fragment, gc_lf);
        end if;
      end loop;

      exit when l_fragment is not null;
    end loop;

    $if $$verbose_output $then
    logger.log('END', l_scope, null, l_params);
    $end

    return l_fragment;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end get_fragment;








  -- ===========================================================================
  -- FUNCTION: assemble
  -- ===========================================================================
  /**
   * Assembles an artifact: for every section of p_section_codes (pipeline
   * order spec, declaration, headers, auth, invocation, status, parsing,
   * example, footer by default) picks the best variant fragment and
   * renders it with p_tokens; sections without rows are skipped.
   *
   * @example
   * set serveroutput on
   * declare
   *   l_tokens arw_render_utils.t_tokens;
   * begin
   *   arw_render_utils.set_token(l_tokens, 'curl_url', '''https://jsonplaceholder.typicode.com/todos/1''');
   *   dbms_output.put_line(arw_render_utils.assemble(
   *       p_template_type_code                 => 'curl'
   *     , p_variant_codes                      => 'none:default'
   *     , p_tokens                             => l_tokens
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_template_type_code Output type
   * @param p_variant_codes Colon-delimited variant codes, most specific first
   * @param p_tokens Token values
   * @param p_section_codes Colon-delimited sections to render, in order
   * @return clob Assembled text
   */
  function assemble(
      p_template_type_code                      in arw_code_templates.template_type_code%type
    , p_variant_codes                           in varchar2
    , p_tokens                                  in t_tokens
    , p_section_codes                           in varchar2 default gc_section_order
  )
  return clob
  is
    l_scope    logger_logs.scope%type := gc_scope_prefix || 'assemble';
    l_params   logger.tab_param;
    l_sections apex_t_varchar2;
    l_fragment clob;
    l_result   clob;
  begin
    logger.append_param(l_params, 'p_template_type_code', p_template_type_code);
    logger.append_param(l_params, 'p_variant_codes', p_variant_codes);
    logger.append_param(l_params, 'p_section_codes', p_section_codes);
    logger.log('START', l_scope, null, l_params);

    dbms_lob.createtemporary(l_result, true);
    l_sections := apex_string.split(p_section_codes, ':');

    for i in 1 .. l_sections.count loop
      l_fragment := get_fragment(
          p_template_type_code                  => p_template_type_code
        , p_section_code                        => l_sections(i)
        , p_variant_codes                       => p_variant_codes
      );

      if l_fragment is not null then
        dbms_lob.append(l_result, render(p_template => l_fragment, p_tokens => p_tokens));
      end if;
    end loop;

    logger.log('END', l_scope, null, l_params);

    return l_result;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end assemble;








  -- ===========================================================================
  -- FUNCTION: to_identifier
  -- ===========================================================================
  /**
   * Turns free text into a lowercase snake_case identifier: camelCase is
   * split (userId -> user_id), anything outside [a-z0-9_] becomes "_", a
   * leading digit gets a "c_" prefix and a reserved word a "_col" suffix.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.to_identifier(p_text => 'company.catchPhrase'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Source text (JSON key, endpoint name, header name...)
   * @param p_max_length Maximum identifier length
   * @return varchar2 Valid unquoted identifier
   */
  function to_identifier(
      p_text                                    in varchar2
    , p_max_length                              in pls_integer default 128
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'to_identifier';
    l_params logger.tab_param;
    l_ident  varchar2(4000 char);
  begin
    l_ident := regexp_replace(p_text, '([a-z0-9])([A-Z])', '\1_\2');
    l_ident := lower(l_ident);
    l_ident := regexp_replace(l_ident, '[^a-z0-9_]', '_');
    l_ident := regexp_replace(l_ident, '_{2,}', '_');
    l_ident := trim(both '_' from l_ident);

    if l_ident is null then
      l_ident := 'x';
    end if;

    if regexp_like(l_ident, '^[0-9]') then
      l_ident := 'c_' || l_ident;
    end if;

    if instr(gc_reserved_words, ':' || l_ident || ':') > 0 then
      l_ident := l_ident || '_col';
    end if;

    return substr(l_ident, 1, p_max_length);
  exception
    when others then
      logger.append_param(l_params, 'p_text', p_text);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end to_identifier;








  -- ===========================================================================
  -- FUNCTION: to_static_id
  -- ===========================================================================
  /**
   * Turns free text into an APEXlang component id: lowercase kebab-case.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.to_static_id(p_text => 'jsonplaceholder.typicode.com'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Source text
   * @return varchar2 Kebab-case id (letters, digits, "-")
   */
  function to_static_id(
      p_text                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'to_static_id';
    l_params logger.tab_param;
    l_id     varchar2(4000 char);
  begin
    l_id := regexp_replace(p_text, '([a-z0-9])([A-Z])', '\1-\2');
    l_id := lower(l_id);
    l_id := regexp_replace(l_id, '[^a-z0-9]+', '-');
    l_id := trim(both '-' from l_id);

    return substr(nvl(l_id, 'component'), 1, 255);
  exception
    when others then
      logger.append_param(l_params, 'p_text', p_text);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end to_static_id;








  -- ===========================================================================
  -- FUNCTION: singular
  -- ===========================================================================
  /**
   * Naive English singular of a resource name (orders -> order,
   * categories -> category, addresses -> address); words that do not look
   * plural are returned unchanged.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.singular(p_word => 'todos'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_word Plural word
   * @return varchar2 Singular word
   */
  function singular(
      p_word                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'singular';
    l_params logger.tab_param;
  begin
    return case
             when p_word is null                                  then null
             when regexp_like(p_word, '[^aeiou]ies$')             then regexp_replace(p_word, 'ies$', 'y')
             when regexp_like(p_word, '(ss|x|ch|sh)es$')          then regexp_replace(p_word, 'es$')
             when regexp_like(p_word, 'ss$|us$|is$')              then p_word
             when regexp_like(p_word, 's$') and length(p_word) > 2 then regexp_replace(p_word, 's$')
             else p_word
           end;
  exception
    when others then
      logger.append_param(l_params, 'p_word', p_word);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end singular;








  -- ===========================================================================
  -- FUNCTION: quote_literal
  -- ===========================================================================
  /**
   * Single-quoted SQL/PL/SQL string literal ('it''s'); 'null' for null.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.quote_literal(p_text => 'it''s'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Text to quote
   * @return varchar2 Literal, or the keyword null
   */
  function quote_literal(
      p_text                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'quote_literal';
    l_params logger.tab_param;
  begin
    if p_text is null then
      return 'null';
    end if;

    return '''' || replace(p_text, '''', '''''') || '''';
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end quote_literal;








  -- ===========================================================================
  -- FUNCTION: q_literal
  -- ===========================================================================
  /**
   * Alternative-quoting literal (q'[...]') for multi-line text such as a
   * request body, choosing a delimiter that does not occur in the text.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.q_literal(p_text => '{"title": "it''s"}'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Text to quote
   * @return clob q-quoted literal, or the keyword null
   */
  function q_literal(
      p_text                                    in clob
  )
  return clob
  is
    lc_open  constant varchar2(10) := '[{<~!#^|';
    lc_close constant varchar2(10) := ']}>~!#^|';

    l_scope  logger_logs.scope%type := gc_scope_prefix || 'q_literal';
    l_params logger.tab_param;
  begin
    if p_text is null or dbms_lob.getlength(p_text) = 0 then
      return 'null';
    end if;

    for i in 1 .. length(lc_open) loop
      if dbms_lob.instr(p_text, substr(lc_close, i, 1) || '''') = 0 then
        return 'q''' || substr(lc_open, i, 1) || p_text || substr(lc_close, i, 1) || '''';
      end if;
    end loop;

    raise_application_error(gc_err_invalid_template, 'No q-quote delimiter available for the given text.');
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end q_literal;








  -- ===========================================================================
  -- FUNCTION: shell_quote
  -- ===========================================================================
  /**
   * POSIX shell single-quoted word ('it'\''s') for the cURL artifact.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.shell_quote(p_text => 'it''s'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Text to quote
   * @return varchar2 Quoted shell word
   */
  function shell_quote(
      p_text                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'shell_quote';
    l_params logger.tab_param;
  begin
    return '''' || replace(p_text, '''', '''\''''') || '''';
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end shell_quote;








  -- ===========================================================================
  -- FUNCTION: apx_text
  -- ===========================================================================
  /**
   * Makes free text safe as a single-line APEXlang value (name, label):
   * keeps letters, digits, space and _ . , - and collapses the rest.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.apx_text(p_text => 'Get todos (v2): "open"'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Source text
   * @return varchar2 Sanitized text
   */
  function apx_text(
      p_text                                    in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'apx_text';
    l_params logger.tab_param;
  begin
    return nvl(trim(regexp_replace(regexp_replace(p_text, '[^A-Za-z0-9 _.,-]', ' '), ' {2,}', ' ')), 'Unnamed');
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end apx_text;








  -- ===========================================================================
  -- FUNCTION: json_path
  -- ===========================================================================
  /**
   * Turns a data-profile path_expression (relative to the row, e.g.
   * address.geo.lat) into a SQL/JSON path ($.address.geo.lat), quoting the
   * steps that are not plain identifiers. A path already starting with $
   * is returned unchanged.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.json_path(p_path_expression => 'data.Hard disk size'));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_path_expression Relative path from arw_profile_columns
   * @return varchar2 SQL/JSON path expression
   */
  function json_path(
      p_path_expression                         in varchar2
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'json_path';
    l_params logger.tab_param;
    l_steps  apex_t_varchar2;
    l_path   varchar2(4000 char) := '$';
  begin
    if p_path_expression is null then
      return '$';
    end if;

    if substr(p_path_expression, 1, 1) = '$' then
      return p_path_expression;
    end if;

    l_steps := apex_string.split(p_path_expression, '.');

    for i in 1 .. l_steps.count loop
      if regexp_like(l_steps(i), '^[A-Za-z_][A-Za-z0-9_]*(\[[0-9*]+\])*$')
         or regexp_like(l_steps(i), '^".*"$') then
        l_path := l_path || '.' || l_steps(i);
      else
        l_path := l_path || '."' || replace(l_steps(i), '"', '\"') || '"';
      end if;
    end loop;

    return l_path;
  exception
    when others then
      logger.append_param(l_params, 'p_path_expression', p_path_expression);
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end json_path;








  -- ===========================================================================
  -- FUNCTION: aligned
  -- ===========================================================================
  /**
   * Builds one line of a leading-comma list so that p_rest starts in
   * p_column (default 49, plsql-standards.md section 6) once the line is
   * rendered at p_base_indent: p_lead ("  " for the first entry, ", " for
   * the others) + padded name + p_rest. A name too long for the column
   * simply gets one space.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line('    ' || arw_render_utils.aligned(
   *       p_lead                               => ', '
   *     , p_name                               => 'p_status'
   *     , p_rest                               => 'in varchar2'
   *     , p_base_indent                        => 4
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_lead Two-character lead ("  " or ", ")
   * @param p_name Name to pad
   * @param p_rest Text that must start in p_column
   * @param p_base_indent Indentation the line will be rendered at
   * @param p_column 1-based target column of p_rest
   * @return varchar2 The list line, without the base indentation
   */
  function aligned(
      p_lead                                    in varchar2
    , p_name                                    in varchar2
    , p_rest                                    in varchar2
    , p_base_indent                             in pls_integer
    , p_column                                  in pls_integer default 49
  )
  return varchar2
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'aligned';
    l_params logger.tab_param;
    l_width  pls_integer;
  begin
    l_width := greatest(p_column - 1 - p_base_indent - nvl(length(p_lead), 0), nvl(length(p_name), 0) + 1);

    return p_lead || rpad(p_name, l_width) || p_rest;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end aligned;








  -- ===========================================================================
  -- FUNCTION: indent_lines
  -- ===========================================================================
  /**
   * Prefixes every non-empty line of p_text with p_prefix.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.indent_lines(
   *       p_text                               => 'begin' || chr(10) || '  null;' || chr(10) || 'end;'
   *     , p_prefix                             => '    '
   *   ));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_text Text to indent
   * @param p_prefix Prefix for each non-empty line
   * @return clob Indented text
   */
  function indent_lines(
      p_text                                    in clob
    , p_prefix                                  in varchar2
  )
  return clob
  is
    l_scope  logger_logs.scope%type := gc_scope_prefix || 'indent_lines';
    l_params logger.tab_param;
    l_result clob;
    l_len    pls_integer;
    l_pos    pls_integer := 1;
    l_nl     pls_integer;
    l_line   varchar2(32767);
  begin
    dbms_lob.createtemporary(l_result, true);

    if p_text is null then
      return l_result;
    end if;

    l_len := dbms_lob.getlength(p_text);

    while l_pos <= l_len loop
      l_nl := dbms_lob.instr(p_text, gc_lf, l_pos);
      if l_nl = 0 then
        l_line := dbms_lob.substr(p_text, l_len - l_pos + 1, l_pos);
        l_pos  := l_len + 1;
      else
        l_line := case when l_nl > l_pos then dbms_lob.substr(p_text, l_nl - l_pos, l_pos) end;
        l_pos  := l_nl + 1;
      end if;

      if l_line is not null then
        dbms_lob.append(l_result, p_prefix || l_line);
      end if;

      if l_nl > 0 then
        dbms_lob.append(l_result, gc_lf);
      end if;
    end loop;

    return l_result;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end indent_lines;








  -- ===========================================================================
  -- FUNCTION: sha256_hex
  -- ===========================================================================
  /**
   * SHA-256 checksum (64 lowercase hex chars) via standard_hash
   * (dbms_crypto is not granted to the workspace schema). Content up to
   * 8000 characters is hashed directly -- the true SHA-256 of its UTF-8
   * bytes. Longer content is hashed in 8000-character chunks chained as
   * h = sha256(h || sha256(chunk)): still deterministic and
   * change-sensitive, which is all arw_generated_artifacts needs.
   *
   * @example
   * set serveroutput on
   * begin
   *   dbms_output.put_line(arw_render_utils.sha256_hex(p_content => to_clob('abc')));
   * end;
   * /
   *
   * @issue   #25 (Fase 1 - full app: code generation)
   *
   * @author  Angel Flores (Developer)
   * @created October 23, 2026
   *
   * @param p_content Content to hash
   * @return varchar2 SHA-256 hex digest; null for null content
   */
  function sha256_hex(
      p_content                                 in clob
  )
  return varchar2
  is
    lc_chunk constant pls_integer := 8000;

    l_scope  logger_logs.scope%type := gc_scope_prefix || 'sha256_hex';
    l_params logger.tab_param;
    l_len    pls_integer;
    l_pos    pls_integer := 1;
    l_text   varchar2(32767);
    l_hash   varchar2(64);
    l_chunk  varchar2(64);
  begin
    if p_content is null then
      return null;
    end if;

    l_len := dbms_lob.getlength(p_content);

    if l_len <= lc_chunk then
      l_text := dbms_lob.substr(p_content, lc_chunk, 1);
      select lower(rawtohex(standard_hash(l_text, 'SHA256')))  as digest
        into l_hash
        from dual;
      return l_hash;
    end if;

    while l_pos <= l_len loop
      l_text := dbms_lob.substr(p_content, lc_chunk, l_pos);
      select lower(rawtohex(standard_hash(l_text, 'SHA256')))  as digest
        into l_chunk
        from dual;

      l_text := l_hash || l_chunk;
      select lower(rawtohex(standard_hash(l_text, 'SHA256')))  as digest
        into l_hash
        from dual;

      l_pos := l_pos + lc_chunk;
    end loop;

    return l_hash;
  exception
    when others then
      logger.log_error('Unhandled Exception', l_scope, null, l_params);
      raise;
  end sha256_hex;


end arw_render_utils;
/
