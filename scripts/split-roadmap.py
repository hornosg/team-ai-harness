#!/usr/bin/env python3
"""Parte roadmap.yaml en índice + descripciones, y verifica que siga partido.

POR QUÉ (medido 2026-07-27): `roadmap.yaml` pesaba 122,1 KB con 115 épicas, y el 53% de eso eran
campos `descripcion:`. Toda iteración del loop lo cargaba entero — incluidas ~32,7 KB de
descripciones de épicas con `estado: completo`, que se leen para no usarse nunca. La selección de
tarea sólo necesita el índice (id/proyecto/estado/prioridad/hito/depende_de/archivo); la
descripción se necesita en UNA épica por iteración, y sólo cuando no tiene `archivo:` (§1bis).

QUÉ HACE
  split  — mueve el cuerpo de cada `descripcion:` de hitos y épicas a `roadmap-descripciones.yaml`
           (mapa id → descripción), dejando el índice sin ellas. Idempotente.
  check  — falla si el índice volvió a tener descripciones o si algún id perdió la suya. Pensado
           para correr después de que una skill toque el roadmap.

NO usa PyYAML a propósito: el roadmap está lleno de comentarios (el bloque de convenciones, el
mapa `prefijos:`, el árbol narrativo) que un round-trip por yaml.safe_load/dump borraría en
silencio. La manipulación es textual y conservadora — no toca ninguna línea que no sea parte de
un bloque `descripcion:`.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

INDEX_HEADER_MARK = "# DESCRIPCIONES: viven en roadmap-descripciones.yaml"

SIBLING_HEADER = """# roadmap-descripciones.yaml — hermano de roadmap.yaml (split 2026-07-27, PLAT-E39)
#
# Mapa `id -> descripcion`. Lo genera y verifica `scripts/split-roadmap.py`.
#
# El índice (`roadmap.yaml`) es lo que TODA iteración del loop carga entero para elegir la próxima
# tarea. Este archivo NO se carga de entrada: se abre bajo demanda, para UNA épica, y sólo cuando
# la descripción hace falta de verdad — típicamente cuando la épica no tiene `archivo:` todavía y
# su descripción es la única spec disponible (ver §1bis de la skill loop-next-task). Si la épica
# tiene `archivo:`, la fuente de verdad es ese archivo, no esta descripción.
#
# Al crear o cerrar una épica se escribe la entrada acá, no en el índice (ver la skill
# roadmap-management). `split-roadmap.py check` falla si una descripción vuelve al índice.
"""

# Un campo de entrada: dos espacios de indentación y `clave:`. Marca el fin del bloque anterior.
FIELD_RE = re.compile(r"^  [A-Za-z_][A-Za-z0-9_]*:")
ITEM_RE = re.compile(r"^- id:\s*(\S+)")
DESC_RE = re.compile(r"^  descripcion:")


def extract(text: str) -> tuple[str, dict[str, list[str]]]:
    """Devuelve (índice sin descripciones, {id: líneas crudas del bloque descripcion}) ."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    descriptions: dict[str, list[str]] = {}
    current_id: str | None = None
    index = 0

    while index < len(lines):
        line = lines[index]
        item = ITEM_RE.match(line)
        if item:
            current_id = item.group(1)
            out.append(line)
            index += 1
            continue
        if DESC_RE.match(line) and current_id:
            block = [line]
            index += 1
            # El cuerpo son las continuaciones indentadas: todo lo que no abra otro campo de la
            # entrada, ni otra entrada de la lista, ni una clave top-level.
            while index < len(lines):
                nxt = lines[index]
                if FIELD_RE.match(nxt) or nxt.startswith("- ") or re.match(r"^[A-Za-z_]", nxt):
                    break
                block.append(nxt)
                index += 1
            descriptions[current_id] = block
            continue
        out.append(line)
        index += 1

    return "".join(out), descriptions


def render_sibling(descriptions: dict[str, list[str]]) -> str:
    chunks = [SIBLING_HEADER]
    for key, block in descriptions.items():
        body = "".join(block)
        # `  descripcion:` (indentado, campo de una entrada de lista) pasa a `<id>:` top-level.
        body = body.replace("  descripcion:", f"{key}:", 1)
        # Las continuaciones estaban indentadas para un item de lista; se desindenta un nivel.
        rendered = []
        for position, raw in enumerate(body.splitlines(keepends=True)):
            rendered.append(raw if position == 0 else re.sub(r"^  ", "", raw))
        chunks.append("".join(rendered))
    return "".join(chunks)


def sibling_ids(text: str) -> set[str]:
    return set(re.findall(r"^([A-Za-z]+-[A-Za-z0-9]+):", text, flags=re.M))


def stamp_index(text: str) -> str:
    if INDEX_HEADER_MARK in text:
        return text
    note = (
        f"{INDEX_HEADER_MARK} (hermano generado por scripts/split-roadmap.py).\n"
        "# Este archivo es el ÍNDICE: id/proyecto/nombre/estado/prioridad/hito/depende_de/archivo.\n"
        "# Es lo único que el loop carga entero por iteración — mantenerlo chico es el punto.\n"
        "# La descripción de una épica se lee del hermano, bajo demanda y de a una.\n"
        "#\n"
    )
    return note + text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=("split", "check"))
    parser.add_argument("--roadmap", type=Path, default=Path("roadmap.yaml"))
    args = parser.parse_args()

    roadmap: Path = args.roadmap
    sibling = roadmap.with_name("roadmap-descripciones.yaml")
    if not roadmap.is_file():
        print(f"No existe el roadmap: {roadmap}", file=sys.stderr)
        return 2

    text = roadmap.read_text(encoding="utf-8")
    index_text, descriptions = extract(text)

    if args.mode == "check":
        problems = []
        if descriptions:
            problems.append(
                f"{len(descriptions)} descripcion(es) volvieron al índice: "
                + ", ".join(sorted(descriptions)[:5])
            )
        if not sibling.is_file():
            problems.append(f"falta el hermano {sibling.name}")
        else:
            known = sibling_ids(sibling.read_text(encoding="utf-8"))
            ids = set(re.findall(r"^- id:\s*(\S+)", text, flags=re.M))
            missing = sorted(ids - known)
            if missing:
                problems.append(f"{len(missing)} id(s) sin descripción en el hermano: {missing[:5]}")
        for problem in problems:
            print(f"FALLA: {problem}", file=sys.stderr)
        if problems:
            return 1
        print(f"OK — índice sin descripciones ({roadmap.stat().st_size} B), hermano al día.")
        return 0

    if not descriptions:
        print("Nada que mover: el índice ya está sin descripciones.")
        return 0

    before = len(text.encode())
    merged = descriptions
    if sibling.is_file():
        # Split incremental: conservar lo ya movido y agregar lo nuevo.
        previous = sibling.read_text(encoding="utf-8")
        kept = {k: v for k, v in descriptions.items() if k not in sibling_ids(previous)}
        sibling.write_text(previous.rstrip("\n") + "\n" + render_sibling(kept).replace(SIBLING_HEADER, ""), encoding="utf-8")
        merged = kept
    else:
        sibling.write_text(render_sibling(descriptions), encoding="utf-8")

    roadmap.write_text(stamp_index(index_text), encoding="utf-8")
    after = roadmap.stat().st_size
    print(f"Movidas {len(merged)} descripciones a {sibling.name}")
    print(f"{roadmap.name}: {before} B -> {after} B ({100 * (1 - after / before):.1f}% menos)")
    print(f"{sibling.name}: {sibling.stat().st_size} B")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
