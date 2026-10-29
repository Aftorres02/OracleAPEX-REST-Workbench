/*
 * ==========================================================================
 * ARW-CODE.JS
 * ==========================================================================
 *
 * @description App-wide code block component. Every <pre class="arw-code">
 *              in the app -- on page load and after any region refresh --
 *              gets a Copy button and syntax colors, with no per-region
 *              setup. A region only renders:
 *                <pre class="arw-code" data-lang="plsql">...escaped code...</pre>
 *              data-lang: plsql, sql, json, markup (XML/HTML), bash,
 *              apexlang, or none (Copy button only). Highlighting uses the
 *              bundled Prism (lib/prism/prism.js); APEXlang has its own small
 *              grammar below.
 * @author      Angel Flores
 * @created     October 2026
 * @issue       #25
 * @version     1.0
 */
var arw = arw || {};

arw.code = (function(namespace, $, undefined) {
  'use strict';

  var MODULE_NAME = 'Code';

  var CONFIG = {
      BLOCK_SELECTOR: 'pre.arw-code'
    , DONE_ATTR: 'data-arw-code'
    , WRAPPER_CLASS: 'arw-codeblock'
    , COPY_CLASS: 'arw-codeblock__copy'
    , COPY_LABEL: 'Copy'
    , COPIED_LABEL: 'Copied'
    , COPIED_MS: 1500
    , MAX_HIGHLIGHT_CHARS: 200000
  };

  var _PREFIX = '[' + MODULE_NAME + ']';
  var logger = {
      log:     function(msg, data) { console.log(_PREFIX, msg, data || ''); }
    , warning: function(msg, data) { console.warn(_PREFIX, msg, data || ''); }
    , error:   function(msg, data) { console.error(_PREFIX, msg, data || ''); }
  };

  /* ================================================================ */
  /* APEXlang grammar                                                 */
  /* ================================================================ */

  /**
   * Register a small Prism grammar for APEXlang (.apx): components,
   * group blocks, properties, @references, substitutions and fenced
   * SQL / PL/SQL blocks (highlighted as PL/SQL)
   */
  var _registerApexlang = function() {
    if (!window.Prism || Prism.languages.apexlang) {
      return;
    }
    Prism.languages.apexlang = {
        'fenced-sql': {
            pattern: /```(?:sql|plsql)[\s\S]*?```/
          , greedy: true
          , inside: {
                'punctuation': /^```\w*|```$/
              , rest: Prism.languages.plsql
            }
        }
      , 'fenced': {
            pattern: /```[\s\S]*?```/
          , greedy: true
          , alias: 'string'
        }
      , 'comment': {
            pattern: /\/\/.*/
          , greedy: true
        }
      , 'string': {
            pattern: /"(?:\\.|[^"\\\r\n])*"/
          , greedy: true
        }
      , 'keyword': {
            pattern: /(^[ \t]*)[a-zA-Z]+(?=[ \t]+[^\s(]+[ \t]*\()/m
          , lookbehind: true
        }
      , 'class-name': {
            pattern: /(^[ \t]*)[a-zA-Z]+(?=[ \t]*\{)/m
          , lookbehind: true
        }
      , 'property': {
            pattern: /(^[ \t]*)[a-zA-Z][\w$]*(?=[ \t]*:)/m
          , lookbehind: true
        }
      , 'variable': /@[\w\/.$-]+|&[A-Z0-9_$]+\.|#[A-Z0-9_$]+#/
      , 'boolean': /\b(?:true|false)\b/
      , 'number': /\b\d+(?:\.\d+)?\b/
      , 'punctuation': /[{}()[\],:]/
    };
  };

  /* ================================================================ */
  /* Private helpers                                                  */
  /* ================================================================ */

  /**
   * Color one code block when its language is known and it is not huge
   * @param {Element} pre - The <pre class="arw-code"> element
   * @param {Element} code - Its <code> child
   */
  var _highlight = function(pre, code) {
    var lang = (pre.getAttribute('data-lang') || 'none').toLowerCase();

    if (!window.Prism || lang === 'none' || !Prism.languages[lang]) {
      return;
    }
    if (code.textContent.length > CONFIG.MAX_HIGHLIGHT_CHARS) {
      logger.log('Too large to highlight', {length: code.textContent.length});
      return;
    }
    pre.classList.add('language-' + lang);
    code.classList.add('language-' + lang);
    try {
      Prism.highlightElement(code);
    } catch (e) {
      logger.error('Highlight failed', {lang: lang, error: e.message});
    }
  };

  /**
   * Turn one <pre class="arw-code"> into a code block: <code> child,
   * colors, and a wrapper holding the Copy button
   * @param {Element} pre - The <pre class="arw-code"> element
   */
  var _decorate = function(pre) {
    var code = pre.querySelector('code');
    var wrapper;
    var button;

    if (pre.getAttribute(CONFIG.DONE_ATTR)) {
      return;
    }
    pre.setAttribute(CONFIG.DONE_ATTR, 'Y');

    if (!code) {
      code = document.createElement('code');
      while (pre.firstChild) {
        code.appendChild(pre.firstChild);
      }
      pre.appendChild(code);
    }

    _highlight(pre, code);

    wrapper = document.createElement('div');
    wrapper.className = CONFIG.WRAPPER_CLASS;
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);

    button = document.createElement('button');
    button.type = 'button';
    button.className = 't-Button t-Button--small t-Button--noUI t-Button--iconLeft ' + CONFIG.COPY_CLASS;
    button.setAttribute('aria-label', 'Copy code to the clipboard');
    button.innerHTML = '<span class="t-Icon t-Icon--left fa fa-copy" aria-hidden="true"></span>'
                     + '<span class="t-Button-label">' + CONFIG.COPY_LABEL + '</span>';
    wrapper.appendChild(button);
  };

  /**
   * Copy text with the Clipboard API, falling back to a hidden textarea
   * @param {string} text - Text to copy
   * @param {Function} callback - Receives true when the copy worked
   */
  var _copyText = function(text, callback) {
    var area;
    var ok = false;

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(
          function() { callback(true); }
        , function() { callback(false); }
      );
      return;
    }

    area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try {
      ok = document.execCommand('copy');
    } catch (e) {
      logger.error('Copy fallback failed', {error: e.message});
    }
    document.body.removeChild(area);
    callback(ok);
  };

  /**
   * Click on a Copy button: copy its block's text and confirm on the button
   * @param {Event} event - The click event
   */
  var _handleCopyClick = function(event) {
    var button = event.target.closest('.' + CONFIG.COPY_CLASS);
    var label;
    var pre;

    if (!button) {
      return;
    }
    event.preventDefault();
    pre = button.parentNode.querySelector(CONFIG.BLOCK_SELECTOR);
    label = button.querySelector('.t-Button-label');

    _copyText(pre ? pre.textContent : '', function(ok) {
      if (!ok) {
        apex.message.showErrors([{
            type: 'error'
          , location: 'page'
          , message: 'Could not copy -- select the code and copy it manually.'
        }]);
        return;
      }
      label.textContent = CONFIG.COPIED_LABEL;
      setTimeout(function() { label.textContent = CONFIG.COPY_LABEL; }, CONFIG.COPIED_MS);
    });
  };

  /* ================================================================ */
  /* Public API                                                       */
  /* ================================================================ */

  /**
   * Decorate every code block not decorated yet
   * @param {Element} [root] - Where to look; the whole document by default
   */
  var decorateAll = function(root) {
    var blocks = (root || document).querySelectorAll(CONFIG.BLOCK_SELECTOR);
    var i;

    for (i = 0; i < blocks.length; i++) {
      _decorate(blocks[i]);
    }
  };

  /**
   * Wire the component once: grammar, first pass, refreshes, copy clicks
   */
  var initialize = function() {
    _registerApexlang();
    decorateAll();

    // Regions re-render their HTML on refresh: decorate the new blocks
    $(document).on('apexafterrefresh', function(event) {
      decorateAll(event.target);
    });
    document.addEventListener('click', _handleCopyClick);
  };

  /* ================================================================ */
  /* Return public API                                                */
  /* ================================================================ */
  return {
      // Lifecycle
      initialize: initialize

      // Rendering
    , decorateAll: decorateAll
  };

})(arw, apex.jQuery);

apex.jQuery(function() {
  arw.code.initialize();
});
