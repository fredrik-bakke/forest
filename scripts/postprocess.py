"""Apply the theme to fresh Forester HTML. Run from the repository root."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


THEME = Path("theme")


def transform_xml(content, stylesheet, xsltproc, *parameters):
    """Share the theme's XSL templates with Forester's native HTML renderer."""
    result = subprocess.run(
        [xsltproc, "--nonet", "--novalid", *parameters, str(THEME / stylesheet), "-"],
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


def render_metadata(html, page, xsltproc):
    xml = page.with_suffix(".xml")
    if not xml.is_file():
        return html
    headers = re.findall(r"<header>.*?</header>", html, flags=re.DOTALL)
    rendered = transform_xml(
        "<headers>" + "".join(headers) + "</headers>",
        "local-metadata.xsl",
        xsltproc,
        "--stringparam",
        "tree-xml",
        xml.resolve().as_uri(),
    )
    updated = re.findall(r"<header>.*?</header>", rendered, flags=re.DOTALL)
    if len(headers) != len(updated):
        raise RuntimeError(f"Metadata header count changed for {page}")
    replacements = iter(updated)
    return re.sub(
        r"<header>.*?</header>", lambda _: next(replacements), html, flags=re.DOTALL
    )


def highlight_bibliography(html, xsltproc):
    return re.sub(
        r"<pre>\s*@[^<]*</pre>",
        lambda block: transform_xml(block[0], "static.xsl", xsltproc),
        html,
    )


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


def add_counter(html, snippet):
    if not re.search(r"<body\b", html, flags=re.IGNORECASE):
        return html
    existing = r"<script\b[^>]*\bdata-goatcounter\s*=[^>]*>.*?</script\s*>"
    if re.search(existing, html, flags=re.IGNORECASE | re.DOTALL):
        return re.sub(
            existing, lambda _: snippet, html, flags=re.IGNORECASE | re.DOTALL
        )
    return re.sub(
        r"</head\s*>", snippet + "\n</head>", html, count=1, flags=re.IGNORECASE
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
    for page in sorted(args.output.rglob("*.html")):
        html = page.read_text(encoding="utf-8")
        html = inline_styles(html, css)
        html = render_metadata(html, page, args.xsltproc)
        html = highlight_bibliography(html, args.xsltproc)
        html = normalize_line_breaks(html)
        html = normalize_preformatted(html)
        html = add_search_button(html, button)
        html = add_counter(html, counter)
        write_page(page, html)


if __name__ == "__main__":
    main()
