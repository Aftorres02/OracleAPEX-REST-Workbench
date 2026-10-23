-- Implements: .claude/rules/plsql-standards.md (package structure, documentation tags)
create or replace package arw_render_utils
as
-- =============================================================================
-- Package: arw_render_utils
-- Purpose: Template engine of the hybrid code generator
--          (docs/base/IMPLEMENTATION.md section 5): token replacement,
--          conditional blocks, fragment selection/assembly from
--          arw_code_templates, and the identifier/quoting helpers the
--          generator needs. Knows nothing about endpoints -- arw_codegen_api
--          computes the tokens, this package only renders text.
--
--          Template syntax (one fragment = template_body of one row):
--            {{name}}              token; replaced by its value, left as-is
--                                  when the token is not set
--            {{#name}}..{{/name}}  kept when the token is truthy (set, not
--                                  empty, not 'N'); {{^name}} = falsy
--            A line holding only a {{#x}}/{{^x}}/{{/x}} tag is dropped.
--            A line holding only {{name}} (plus indentation) is dropped
--            when the value is empty; a multi-line value gets that
--            indentation (or a " * " / "-- " / "// " comment prefix) on
--            every line.
--
-- =============================================================================

  type t_tokens is table of clob index by varchar2(100);

  gc_section_order constant varchar2(200 char) := 'spec:declaration:headers:auth:invocation:status:parsing:example:footer';


  procedure set_token(
      io_tokens                                 in out nocopy t_tokens
    , p_name                                    in varchar2
    , p_value                                   in clob
  );


  procedure set_flag(
      io_tokens                                 in out nocopy t_tokens
    , p_name                                    in varchar2
    , p_on                                      in boolean
  );


  function render(
      p_template                                in clob
    , p_tokens                                  in t_tokens
  )
  return clob;


  function get_fragment(
      p_template_type_code                      in arw_code_templates.template_type_code%type
    , p_section_code                            in arw_code_templates.section_code%type
    , p_variant_codes                           in varchar2
  )
  return clob;


  function assemble(
      p_template_type_code                      in arw_code_templates.template_type_code%type
    , p_variant_codes                           in varchar2
    , p_tokens                                  in t_tokens
    , p_section_codes                           in varchar2 default gc_section_order
  )
  return clob;


  function to_identifier(
      p_text                                    in varchar2
    , p_max_length                              in pls_integer default 128
  )
  return varchar2;


  function to_static_id(
      p_text                                    in varchar2
  )
  return varchar2;


  function singular(
      p_word                                    in varchar2
  )
  return varchar2;


  function quote_literal(
      p_text                                    in varchar2
  )
  return varchar2;


  function q_literal(
      p_text                                    in clob
  )
  return clob;


  function shell_quote(
      p_text                                    in varchar2
  )
  return varchar2;


  function apx_text(
      p_text                                    in varchar2
  )
  return varchar2;


  function json_path(
      p_path_expression                         in varchar2
  )
  return varchar2;


  function aligned(
      p_lead                                    in varchar2
    , p_name                                    in varchar2
    , p_rest                                    in varchar2
    , p_base_indent                             in pls_integer
    , p_column                                  in pls_integer default 49
  )
  return varchar2;


  function indent_lines(
      p_text                                    in clob
    , p_prefix                                  in varchar2
  )
  return clob;


  function sha256_hex(
      p_content                                 in clob
  )
  return varchar2;


end arw_render_utils;
/
