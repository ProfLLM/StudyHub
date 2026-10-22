import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:studyhub/enrichment/safe_lecture_html.dart';

Document clean(String source) =>
    parser.parse(SafeLectureHtml.parse(source).document);

void main() {
  test(
    'preserves semantic notes, typography, tables, and local navigation',
    () {
      final result = SafeLectureHtml.parse('''
      <html lang="fr" onload="alert(1)"><head>
      <style>h1 { color: #2563eb; } table { border: 1px solid; }</style>
      </head><body background="https://example.test/bg">
      <main lang="fr"><h1 id="motion">Mouvement &amp; énergie</h1>
      <p class="summary" style="font-weight:700; color:teal">
      Keep <strong>force</strong> and <em>acceleration</em> together.</p>
      <table><caption>Measurements</caption><tr><th scope="col">Time</th>
      <td>2 s</td></tr></table><a href="#motion">Return</a></main>
      </body></html>
    ''');
      final document = parser.parse(result.document);
      expect(document.querySelector('main')!.attributes['lang'], 'fr');
      expect(document.querySelector('h1')!.text, 'Mouvement & énergie');
      expect(document.querySelector('strong')!.text, 'force');
      expect(document.querySelector('em')!.text, 'acceleration');
      expect(document.querySelector('caption')!.text, 'Measurements');
      expect(document.querySelector('th')!.attributes['scope'], 'col');
      expect(document.querySelector('a')!.attributes['href'], '#motion');
      expect(
        document.querySelector('p')!.attributes['style'],
        contains('teal'),
      );
      expect(document.querySelectorAll('style').last.text, contains('#2563eb'));
      expect(document.documentElement!.attributes['onload'], isNull);
      expect(document.body!.attributes['background'], isNull);
      expect(result.plainText, contains('Mouvement & énergie'));
      expect(result.plainText, contains('Measurements'));
    },
  );

  test('preserves inline static SVG diagrams and their local references', () {
    final document = clean('''
      <svg viewBox="0 0 300 120" aria-label="Force diagram">
        <title>Force diagram</title><desc>Two connected objects</desc>
        <defs><marker id="arrow" markerWidth="6" markerHeight="6"
          refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 Z"/></marker>
          <linearGradient id="gradient"><stop offset="0%" stop-color="blue"/>
          <stop offset="100%" stop-color="green"/></linearGradient>
          <clipPath id="clip"><rect width="300" height="120"/></clipPath>
          <g id="shape"><circle cx="40" cy="50" r="20"/></g>
        </defs>
        <g clip-path="url(#clip)"><rect width="300" height="120" fill="url(#gradient)"/>
          <line x1="60" y1="50" x2="200" y2="50" marker-end="url(#arrow)"/>
          <use href="#shape"/><use id="legacy" xlink:href="#shape"/>
          <text x="80" y="40">F = ma</text></g>
      </svg>
    ''');
    expect(document.querySelector('svg')!.attributes['viewBox'], '0 0 300 120');
    expect(document.querySelector('svg title')!.text, 'Force diagram');
    expect(
      document.querySelector('line')!.attributes['marker-end'],
      'url(#arrow)',
    );
    expect(document.querySelector('use')!.attributes['href'], '#shape');
    expect(
      document.querySelector('#legacy')!.attributes.values,
      contains('#shape'),
    );
    expect(
      document.querySelector('g[clip-path]')!.attributes['clip-path'],
      'url(#clip)',
    );
    expect(
      document.querySelector('rect[fill]')!.attributes['fill'],
      'url(#gradient)',
    );
    expect(document.querySelector('#gradient')!.localName, 'linearGradient');
    expect(document.querySelector('#clip')!.localName, 'clipPath');
    expect(document.querySelector('text')!.text, 'F = ma');
  });

  test('preserves MathML equations without a script dependency', () {
    final document = clean('''
      <h2>Quadratic formula</h2><math display="block" aria-label="Quadratic roots">
      <mrow><mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo>
      <msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi>
      </msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac></mrow></math>
    ''');
    expect(document.querySelector('math')!.attributes['display'], 'block');
    expect(document.querySelector('mfrac'), isNotNull);
    expect(document.querySelector('msup')!.text, 'b2');
    expect(document.querySelector('msqrt')!.text.trim(), 'b2−4ac');
    expect(document.querySelector('script'), isNull);
  });

  test('removes active trees, including their text and nested styles', () {
    final document = clean('''
      <p>Keep these notes.</p><script>window.BAD_SCRIPT = true</script>
      <iframe srcdoc="<script>alert(1)</script>">BAD_FRAME</iframe>
      <form action="https://example.test"><p>BAD_FORM</p>
        <style>.BAD_FORM_STYLE { display:none }</style><button>BAD_BUTTON</button></form>
      <template><style>.BAD_TEMPLATE_STYLE {display:none}</style>BAD_TEMPLATE</template>
      <svg><foreignObject><div>BAD_FOREIGN</div>
        <style>.BAD_FOREIGN_STYLE {display:none}</style></foreignObject>
        <animate attributeName="href" values="https://example.test"/>
        <set attributeName="onload" to="alert(1)"/>
        <text>Keep the diagram.</text></svg>
      <audio src="https://example.test">BAD_AUDIO</audio>
      <video src="https://example.test">BAD_VIDEO</video>
      <object data="https://example.test">BAD_OBJECT</object>
    ''');
    expect(document.querySelector('p')!.text, 'Keep these notes.');
    expect(document.querySelector('text')!.text, 'Keep the diagram.');
    expect(document.outerHtml, isNot(contains('BAD_')));
    expect(
      document.querySelector(
        'script,iframe,form,template,foreignObject,animate,set,audio,video,object',
      ),
      isNull,
    );
  });

  test('handles malformed nesting without resurrecting executable markup', () {
    final document = clean('''
      <h1>Topic<p>Intro<strong>bold</p>tail</strong>
      <table><p>Table preface<tr><td>Cell<script>BAD_SCRIPT</script></table>
      <svg><g><foreignObject><p>BAD_FOREIGN</p></foreignObject>
      <text>Diagram</text></g></svg><p>Conclusion
    ''');
    expect(document.body!.text, contains('Topic'));
    expect(document.body!.text, contains('Cell'));
    expect(document.body!.text, contains('Diagram'));
    expect(document.body!.text, contains('Conclusion'));
    expect(document.outerHtml, isNot(contains('BAD_')));
    expect(document.querySelector('script,foreignObject'), isNull);
  });

  test(
    'decodes attribute entities before rejecting handlers and remote links',
    () {
      final document = clean('''
      <p onclick="BAD_HANDLER" style="background:&#117;rl(&quot;https://example.test/bg&quot;)">Notes</p>
      <a href="jav&#x61;script:BAD_SCRIPT" target="_blank" ping="https://example.test">Link</a>
      <img src="https://example.test/image.png" srcset="https://example.test/2.png 2x"
        onerror="BAD_ERROR" alt="Preserve image description">
      <svg onload="BAD_SVG"><use href="&#104;ttps://example.test/file.svg#x"
        xlink:href="https://example.test/file.svg#x"/></svg>
    ''');
      expect(document.querySelector('p')!.attributes, isEmpty);
      expect(document.querySelector('a')!.attributes, isEmpty);
      expect(document.querySelector('img')!.attributes, {
        'alt': 'Preserve image description',
      });
      expect(document.querySelector('svg')!.attributes, isEmpty);
      expect(document.querySelector('use')!.attributes, isEmpty);
      expect(document.outerHtml, isNot(contains('BAD_')));
      expect(document.outerHtml, isNot(contains('example.test')));
    },
  );

  test(
    'keeps supported raster data images but strips SVG data and file URLs',
    () {
      final document = clean('''
      <p>Illustrations</p><img id="png" src="data:image/png;base64,iVBORw0KGgo=">
      <img id="svg" src="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=">
      <img id="file" src="file:///private/notes.png">
      <img id="bad" src="data:image/png;base64,invalid!">
    ''');
      expect(
        document.querySelector('#png')!.attributes['src'],
        startsWith('data:image/png;'),
      );
      for (final id in ['svg', 'file', 'bad']) {
        expect(document.querySelector('#$id')!.attributes['src'], isNull);
      }
    },
  );

  test('rejects CSS resources, imports, escapes, expressions, and obfuscation', () {
    final unsafeStyles = [
      'background:url(https://example.test/bg)',
      'background:URL (https://example.test/bg)',
      'background:u/**/rl(https://example.test/bg)',
      '@import "https://example.test/style.css";',
      '@im/**/port "https://example.test/style.css";',
      '@font-face {font-family:custom; src:local(system)}',
      '@namespace url(https://example.test/namespace);',
      'background:image-set("https://example.test/bg" 1x)',
      'background:-webkit-image-set("https://example.test/bg" 1x)',
      'background:image("https://example.test/bg")',
      'background:src("https://example.test/bg")',
      r'background:\75rl(https://example.test/bg)',
      'width:expression(BAD_EXPRESSION)',
      'color:red; /* unclosed comment',
    ];
    for (final css in unsafeStyles) {
      final document = clean('<style>$css</style><p>Notes</p>');
      expect(document.querySelectorAll('style'), hasLength(1), reason: css);
      // Attribute entities are decoded by the parser before the same CSS check.
      final attributeCss = css.replaceAll('"', '&quot;');
      final inline = clean('<p style="$attributeCss">Notes</p>');
      expect(
        inline.querySelector('p')!.attributes['style'],
        isNull,
        reason: css,
      );
    }
  });

  test('remote SVG presentation URLs are removed while local refs survive', () {
    final unsafeValues = [
      'url(https://example.test/paint)',
      'url (https://example.test/paint)',
      'u/**/rl(https://example.test/paint)',
      'URL(https://example.test/paint)',
      r'\75rl(https://example.test/paint)',
    ];
    for (final value in unsafeValues) {
      final document = clean(
        '<svg><path d="M0 0L1 1" fill="$value" marker-end="$value"/></svg>',
      );
      expect(
        document.querySelector('path')!.attributes['fill'],
        isNull,
        reason: value,
      );
      expect(
        document.querySelector('path')!.attributes['marker-end'],
        isNull,
        reason: value,
      );
      expect(document.querySelector('path')!.attributes['d'], 'M0 0L1 1');
    }
    final local = clean('<svg><path marker-end="url(#arrow)"/></svg>');
    expect(
      local.querySelector('path')!.attributes['marker-end'],
      'url(#arrow)',
    );
  });

  test(
    'safe CSS survives literal less-than characters without HTML escaping',
    () {
      final document = clean('''
      <style>p::before { content: "< 3"; } p { color: teal; }</style>
      <p>Read x &lt; 3.</p>
    ''');
      final css = document.querySelectorAll('style').last.text;
      expect(css, contains('content: "< 3"'));
      expect(css, isNot(contains('&lt;')));
      expect(document.querySelector('p')!.text, 'Read x < 3.');
      final injection = clean('''
      <p style="content: '&lt;/style&gt;&lt;script&gt;BAD&lt;/script&gt;'">Safe</p>
    ''');
      expect(injection.querySelector('p')!.attributes['style'], isNull);
      expect(injection.querySelector('script'), isNull);
    },
  );

  test('removes animations and transitions while retaining ordinary styling', () {
    final document = clean('''
      <style>p { animation: flash 1s infinite; transition: color 1s; color:teal; }</style>
      <p style="transition-duration: 10s; animation-name: flash; -webkit-animation: flash 1s; font-weight:bold">Static</p>
    ''');
    expect(
      document.querySelectorAll('style').last.text,
      contains('color:teal'),
    );
    expect(
      document.querySelectorAll('style').last.text,
      isNot(contains('flash')),
    );
    expect(
      document.querySelector('p')!.attributes['style'],
      contains('font-weight:bold'),
    );
    expect(
      document.querySelector('p')!.attributes['style'],
      isNot(contains('transition')),
    );
    expect(
      document.querySelector('p')!.attributes['style'],
      isNot(contains('-webkit-')),
    );
    final keyframes = clean(
      '<style>@keyframes flash { to {opacity:0} }</style><p>Static</p>',
    );
    expect(keyframes.querySelectorAll('style'), hasLength(1));
    final vendorKeyframes = clean(
      '<style>@-webkit-keyframes flash { to {opacity:0} }</style><p>Static</p>',
    );
    expect(vendorKeyframes.querySelectorAll('style'), hasLength(1));
  });

  test(
    'generated document fixes CSP and excludes provider metadata and bases',
    () {
      final document = clean('''
      <html><head><meta http-equiv="refresh" content="0;url=https://example.test">
      <meta http-equiv="Content-Security-Policy" content="default-src *">
      <base href="https://example.test/"><link rel="stylesheet" href="https://example.test/style.css">
      </head><body><p>Notes</p></body></html>
    ''');
      final csp = document
          .querySelectorAll('meta')
          .where(
            (element) =>
                element.attributes['http-equiv'] == 'Content-Security-Policy',
          )
          .single;
      expect(csp.attributes['content'], SafeLectureHtml.contentSecurityPolicy);
      expect(csp.attributes['content'], contains("script-src 'none'"));
      expect(csp.attributes['content'], contains("connect-src 'none'"));
      expect(document.querySelector('base,link'), isNull);
      expect(document.outerHtml, isNot(contains('example.test')));
      expect(document.querySelectorAll('meta[http-equiv]'), hasLength(1));
    },
  );

  test(
    'escaped source examples stay text and are never promoted to markup',
    () {
      final result = SafeLectureHtml.parse('''
      <pre><code>&lt;script&gt;alert("example")&lt;/script&gt;</code></pre>
      <unknown-wrapper><p>Retain content inside unfamiliar wrappers.</p></unknown-wrapper>
    ''');
      final document = parser.parse(result.document);
      expect(document.querySelector('script'), isNull);
      expect(
        document.querySelector('code')!.text,
        '<script>alert("example")</script>',
      );
      expect(result.plainText, contains('<script>alert("example")</script>'));
      expect(document.querySelector('unknown-wrapper'), isNull);
      expect(document.querySelector('p')!.text, contains('Retain content'));
    },
  );

  test(
    'supports provider HTML code fences and rejects unreadable documents',
    () {
      expect(
        SafeLectureHtml.parse('```html\n<h1>Notes</h1>\n```').plainText,
        'Notes',
      );
      for (final source in [
        '',
        '   ',
        '<script>Only script</script>',
        '<div></div>',
        '<style>p{color:red}</style>',
      ]) {
        expect(() => SafeLectureHtml.parse(source), throwsFormatException);
      }
    },
  );

  test(
    'enforces input bytes, output bytes, element count, and nesting depth',
    () {
      expect(
        () => SafeLectureHtml.parse(
          '<p>${'é' * (SafeLectureHtml.maxBytes ~/ 2)}</p>',
        ),
        throwsFormatException,
      );
      // The source fits, but the wrapper and escaping push the safe document over.
      expect(
        () => SafeLectureHtml.parse(
          '<p>${'x' * (SafeLectureHtml.maxBytes - 8)}</p>',
        ),
        throwsFormatException,
      );
      expect(
        () => SafeLectureHtml.parse('<p>Notes</p>${'<span></span>' * 20001}'),
        throwsFormatException,
      );
      expect(
        () => SafeLectureHtml.parse('${'<div>' * 140}Notes${'</div>' * 140}'),
        throwsFormatException,
      );
      expect(
        SafeLectureHtml.parse('${'<div>' * 120}Notes${'</div>' * 120}')
            .plainText,
        'Notes',
      );
    },
  );
}
