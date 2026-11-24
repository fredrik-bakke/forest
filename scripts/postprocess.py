"""Apply the theme to fresh Forester HTML. Run from the repository root."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote


THEME = Path("theme")
HEADERS = re.compile(r"<header>.*?</header>", re.DOTALL)
BIBTEX = re.compile(r"<pre>\s*@[^<]*</pre>")


def transform_xml(xsltproc, stylesheet, files=("-",), content=None):
    """Share the theme's XSL templates with Forester's native HTML renderer."""
    result = subprocess.run(
        [xsltproc, "--nonet", "--novalid", str(THEME / stylesheet), *files],
        input=content,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode:
        raise RuntimeError(f"{stylesheet}: {result.stderr.strip()}")
    return result.stdout.removesuffix("\n")


def inline_styles(html, css):
    """Avoid a flash of unstyled content; keep asset URLs relative to the CSS."""

    def replace(match):
        base = match[1]
        rebased = re.sub(
            r"url\(([\"']?)(fonts/[^)\"']+|(?:email|github|mastodon|orcid)\.svg)\1\)",
            lambda url: f"url({url[1]}{base}{url[2]}{url[1]})",
            css,
        )
        return f"<style>\n{rebased}</style>"

    return re.sub(
        r'<link\s+rel="stylesheet"\s+href="([^"]*/|)style\.css"\s*/?>',
        replace,
        html,
    )


def render_metadata(pages, xsltproc):
    """Give xsltproc one document per page so it can reuse the stylesheet."""
    inputs = {}
    with tempfile.TemporaryDirectory() as tmp:
        for page, html in pages.items():
            xml = page.with_suffix(".xml")
            if xml.is_file():
                headers = "".join(HEADERS.findall(html))
                source = Path(tmp) / f"{len(inputs)}.xml"
                source.write_text(
                    f'<headers tree-xml="{xml.resolve().as_uri()}">{headers}</headers>',
                    encoding="utf-8",
                )
                inputs[page] = source
        if not inputs:
            return
        rendered = transform_xml(xsltproc, "local-metadata.xsl", inputs.values())
    groups = re.findall(r"<headers>(.*?)</headers>|<headers\s*/>", rendered, re.DOTALL)
    if len(groups) != len(inputs):
        raise RuntimeError("Missing page in transformed metadata")
    for page, group in zip(inputs, groups):
        headers = HEADERS.findall(group)
        if len(headers) != len(HEADERS.findall(pages[page])):
            raise RuntimeError(f"Metadata header count changed for {page}")
        replacements = iter(headers)
        pages[page] = HEADERS.sub(lambda _: next(replacements), pages[page])


def highlight_bibliographies(pages, xsltproc):
    blocks = dict.fromkeys(
        block for html in pages.values() for block in BIBTEX.findall(html)
    )
    if blocks:
        rendered = transform_xml(
            xsltproc, "static.xsl", content="<blocks>" + "".join(blocks) + "</blocks>"
        )
        highlighted = re.findall(r"<pre\b[^>]*>.*?</pre>", rendered, re.DOTALL)
        if len(highlighted) != len(blocks):
            raise RuntimeError("Bibliography block count changed during highlighting")
        replacements = dict(zip(blocks, highlighted))
        for page, html in pages.items():
            pages[page] = BIBTEX.sub(lambda block: replacements[block[0]], html)


def normalize_line_breaks(html):
    # Forester emits <br></br>, and HTML interprets </br> as another line break.
    return re.sub(r"</br\s*>", "", html, flags=re.IGNORECASE)


def normalize_preformatted(html):
    # Match ASC's Firefox fix. The comment protects intentional extra blank lines
    # from HTML parsers, which otherwise strip another newline after <pre>.
    return re.sub(
        r"(<pre\b[^>]*>)\n",
        r"\1<!--This is a guard for intentional leading blank lines.-->",
        html,
    )


def add_search_button(html, button):
    return re.sub(
        r'(<div\s+class="logo">.*?)(</div>)',
        lambda logo: logo[1] + button + logo[2],
        html,
        flags=re.DOTALL,
    )


def add_counter(html, snippet, path):
    if not re.search(r"<body\b", html, flags=re.IGNORECASE):
        return html
    # Match the browser's encoded pathname, then encode it as a query value.
    snippet = snippet.replace("{{path}}", quote(quote(path), safe=""))
    existing = (
        r"<script\b[^>]*\bdata-goatcounter\s*=[^>]*>.*?</script\s*>\s*"
        r"(?:<noscript\b[^>]*\bdata-goatcounter-pixel\b[^>]*>.*?</noscript\s*>\s*)?"
    )
    html = re.sub(existing, "", html, flags=re.IGNORECASE | re.DOTALL)
    # A noscript image belongs in the body, not in the head.
    return re.sub(
        r"</body\s*>",
        lambda _: snippet + "\n</body>",
        html,
        count=1,
        flags=re.IGNORECASE,
    )


def write_page(page, html):
    # Replace each page only after all transformations have succeeded.
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=page.parent, suffix=".tmp", delete=False
    ) as file:
        temporary = Path(file.name)
        try:
            file.write(html)
            file.close()
            temporary.chmod(page.stat().st_mode & 0o777)
            temporary.replace(page)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Forester output directory")
    parser.add_argument("--xsltproc", default="xsltproc")
    args = parser.parse_args()
    if not args.output.is_dir():
        parser.error(f"Output directory does not exist: {args.output}")

    css = (
        (THEME / "style.css")
        .read_text(encoding="utf-8")
        .replace(
            '@import url("custom.css");',
            (THEME / "custom.css").read_text(encoding="utf-8"),
        )
    )
    button = (THEME / "search-button.html").read_text(encoding="utf-8").rstrip("\n")
    counter = (THEME / "counter.html").read_text(encoding="utf-8").rstrip("\n")
    pages = {}
    for page in sorted(args.output.rglob("*.html")):
        source = page.read_text(encoding="utf-8")
        html = inline_styles(source, css)
        if html != source:
            pages[page] = html
    render_metadata(pages, args.xsltproc)
    highlight_bibliographies(pages, args.xsltproc)
    for page, html in pages.items():
        html = normalize_line_breaks(html)
        html = normalize_preformatted(html)
        html = add_search_button(html, button)
        path = "/" + page.relative_to(args.output).as_posix().removesuffix("index.html")
        html = add_counter(html, counter, path)
        write_page(page, html)


if __name__ == "__main__":
    main()
