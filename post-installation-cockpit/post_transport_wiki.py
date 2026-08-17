"""Renderer for the curated post-transport wiki export.

Displays selected sections of post_transport_wiki_content.json (text,
code, lists, tables, and screenshots) in their original wiki order.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import streamlit as st


CONTENT_FILE = Path(__file__).with_name("post_transport_wiki_content.json")
APP_DIR = Path(__file__).parent


@st.cache_data
def load_post_transport_wiki_content() -> dict[str, Any]:
    """Load the curated wiki export used by the post-transport runbook."""
    with CONTENT_FILE.open(encoding="utf-8") as content_file:
        return json.load(content_file)


def _render_list(block: dict[str, Any]) -> None:
    ordered = bool(block.get("ordered"))
    start = int(block.get("start", 1))
    lines: list[str] = []

    for offset, item in enumerate(block.get("items", [])):
        marker = f"{start + offset}." if ordered else "-"
        text = str(item).replace("\n", "\n   ")
        lines.append(f"{marker} {text}")

    if lines:
        st.markdown("\n".join(lines))


def _render_table(block: dict[str, Any]) -> None:
    rows = block.get("rows", [])
    if not rows:
        return

    width = max(len(row) for row in rows)

    def cells(row: list[Any]) -> list[str]:
        values = [str(value).replace("|", "\\|").replace("\n", " ") for value in row]
        return values + [""] * (width - len(values))

    header = cells(rows[0])
    markdown_rows = [
        f"| {' | '.join(header)} |",
        f"| {' | '.join(['---'] * width)} |",
    ]
    markdown_rows.extend(f"| {' | '.join(cells(row))} |" for row in rows[1:])
    st.markdown("\n".join(markdown_rows))


def _render_block(block: dict[str, Any]) -> None:
    kind = block.get("kind")
    text = str(block.get("text", "")).strip()

    if kind == "markdown" and text:
        st.markdown(text)
    elif kind == "heading" and text:
        source_level = int(block.get("level", 2))
        display_level = min(6, max(4, source_level + 2))
        st.markdown(f"{'#' * display_level} {text}")
    elif kind == "code" and text:
        st.code(text, language="text")
    elif kind == "list":
        _render_list(block)
    elif kind == "image":
        relative_path = Path(str(block.get("path", "")))
        image_path = (APP_DIR / relative_path).resolve()
        if (
            image_path.is_relative_to(APP_DIR.resolve())
            and image_path.is_file()
            and image_path.stat().st_size > 0
        ):
            caption = str(block.get("alt", "")).strip() or None
            st.image(str(image_path), caption=caption)
        else:
            st.warning(f"Wiki screenshot is unavailable: `{relative_path}`")
    elif kind == "table":
        _render_table(block)
    elif kind == "note" and text:
        st.info(text)
    elif kind == "warning" and text:
        st.warning(text)


def _render_wiki_page(page: dict[str, Any]) -> None:
    title = str(page.get("title", "Wiki-Unterseite"))
    url = str(page.get("url", "")).strip()

    with st.expander(title):
        if url:
            st.markdown(f"[Originalen Wiki-Artikel öffnen]({url})")
        for block in page.get("blocks", []):
            _render_block(block)


def render_post_transport_wiki(
    section_titles: tuple[str, ...] | None = None,
    *,
    show_header: bool = False,
    show_omitted: bool = False,
) -> None:
    """Render selected manual wiki sections in their original order."""
    content = load_post_transport_wiki_content()
    source = content.get("source", {})

    if show_header:
        st.header("Post-Installation ab Transportimport")
        st.caption(
            "Inhalt und Reihenfolge entsprechen dem Post-Installation-Wiki. "
            "Automatisierte Arbeitsschritte bleiben als Bedienelemente sichtbar, "
            "ihre manuellen Wiki-Anleitungen sind jedoch ausgelassen."
        )
        if source.get("url"):
            st.markdown(
                f"**Wiki-Quelle:** [{source.get('title', 'Post-Installation Configuration')}]"
                f"({source['url']})"
            )

    if show_omitted:
        omitted = content.get("automatedStepsOmitted", [])
        if omitted:
            omitted_lines = "\n".join(f"- {step}" for step in omitted)
            st.info(f"**Automatisierte Wiki-Anleitungen ausgelassen:**\n\n{omitted_lines}")

    for section in content.get("sections", []):
        if section_titles is not None and section.get("title") not in section_titles:
            continue
        st.markdown("---")
        st.subheader(str(section.get("title", "")))

        intro = str(section.get("intro", "")).strip()
        if intro:
            st.markdown(intro)
        for notice in section.get("notices", []):
            st.warning(str(notice))
        for page in section.get("pages", []):
            _render_wiki_page(page)
