#!/usr/bin/env python3
"""Devuelve las épicas ELEGIBLES de un proyecto, resueltas — para no cargar el roadmap entero.

POR QUÉ: la fase SELECT del loop sólo necesita saber "qué épica toca y qué tareas tiene". Leer
`roadmap.yaml` entero para eso mete 47,8 KB en la ventana, de los cuales >90% son épicas de otros
proyectos o ya completas que sólo existen para que `depende_de:` las pueda referenciar. Esta
consulta hace ese trabajo afuera del modelo y devuelve unos pocos KB.

Resuelve, contra el índice:
  - filtro por proyecto (y por épica puntual con --epica);
  - `depende_de:` — marca cada épica como elegible o bloqueada, y por qué;
  - el orden de selección de la skill: `en-progreso` del hito `fase_actual` por prioridad, y
    recién después las `pendiente`.

NO decide: sólo informa. La skill sigue siendo la que elige y la que ejecuta. Si esta salida y el
roadmap se contradijeran, manda el roadmap — pero entonces hay un bug acá y hay que reportarlo.

Uso:
  scripts/roadmap-query.py --proyecto platform
  scripts/roadmap-query.py --epica PLAT-E38
  scripts/roadmap-query.py --proyecto platform --json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("Falta PyYAML: pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)

PRIORITY_ORDER = {"critica": 0, "alta": 1, "media": 2, "baja": 3}
ACTIVE_STATES = ("en-progreso", "pendiente")


def default_roadmap() -> Path:
    configured = os.environ.get("DEVY_ROADMAP_PATH")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / "Projects" / "management" / "roadmap.yaml"


def resolve_project(data: dict, epica_id: str) -> str | None:
    """Proyecto dueño de una épica, vía el bloque `prefijos:` (fuente de verdad de las keys)."""
    key = epica_id.split("-", 1)[0]
    return (data.get("prefijos") or {}).get(key)


def blockers(epica: dict, by_id: dict[str, dict]) -> list[str]:
    reasons = []
    for dep in epica.get("depende_de") or []:
        target = by_id.get(dep)
        if target is None:
            reasons.append(f"{dep} (INEXISTENTE — roadmap inconsistente)")
        elif target.get("estado") != "completo":
            reasons.append(f"{dep} ({target.get('estado')})")
    return reasons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--roadmap", type=Path, default=default_roadmap())
    parser.add_argument("--proyecto")
    parser.add_argument("--epica", help="id prefijado; resuelve el proyecto por el bloque prefijos:")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if not args.proyecto and not args.epica:
        parser.error("indicá --proyecto o --epica")

    data = yaml.safe_load(args.roadmap.read_text(encoding="utf-8"))
    epicas = data.get("epicas") or []
    by_id = {e["id"]: e for e in epicas if "id" in e}

    project = args.proyecto
    if args.epica:
        resolved = resolve_project(data, args.epica)
        if resolved is None:
            print(f"NEXT-TASK: blocked {args.epica} — prefijo desconocido en el bloque prefijos:", file=sys.stderr)
            return 1
        if project and project != resolved:
            print(f"NEXT-TASK: blocked {args.epica} — proyecto-mismatch (--proyecto={project}, prefijo={resolved})", file=sys.stderr)
            return 1
        project = resolved

    hitos = [h for h in (data.get("hitos") or []) if h.get("proyecto") == project]
    fase_actual = (data.get("proyectos", {}).get(project, {}) or {}).get("fase_actual")
    if project == "platform":
        fase_actual = fase_actual or (data.get("proyecto_lab") or {}).get("fase_actual")

    if args.epica:
        target = by_id.get(args.epica)
        if target is None:
            print(f"NEXT-TASK: blocked {args.epica} — epica-inexistente", file=sys.stderr)
            return 1
        if target.get("estado") == "completo":
            # Épica fijada y ya completa: no hay nada que ejecutar. Se emite el marcador que le
            # corresponde para que la fase SELECT no tenga que deducirlo (ni abrir el archivo).
            print(f"NEXT-TASK: empty  # {args.epica} está completo")
            return 0
        if target.get("estado") == "deprecado":
            print(f"NEXT-TASK: blocked {args.epica} — epica deprecada", file=sys.stderr)
            return 1
        candidates = [target]
    else:
        candidates = [e for e in epicas if e.get("proyecto") == project and e.get("estado") in ACTIVE_STATES]

    rows = []
    for epica in candidates:
        reasons = blockers(epica, by_id)
        rows.append({
            "id": epica.get("id"),
            "nombre": epica.get("nombre"),
            "estado": epica.get("estado"),
            "prioridad": epica.get("prioridad"),
            "hito": epica.get("hito"),
            "ceremony": epica.get("ceremony"),
            "archivo": epica.get("archivo"),
            "servicios": epica.get("servicios") or [],
            "elegible": not reasons and epica.get("estado") in ACTIVE_STATES,
            "bloqueada_por": reasons,
        })

    # Mismo orden que aplica la skill: en-progreso del hito actual primero, luego por prioridad.
    rows.sort(key=lambda r: (
        0 if r["estado"] == "en-progreso" else 1,
        0 if r["hito"] == fase_actual else 1,
        PRIORITY_ORDER.get(r["prioridad"], 9),
        str(r["id"]),
    ))

    if args.json:
        print(json.dumps({"proyecto": project, "fase_actual": fase_actual, "epicas": rows},
                         ensure_ascii=False, indent=2))
        return 0

    print(f"# proyecto: {project} · fase_actual: {fase_actual} · hitos: {len(hitos)}")
    elegibles = [r for r in rows if r["elegible"]]
    if not elegibles:
        print("# SIN ÉPICAS ELEGIBLES (ninguna en-progreso/pendiente con depende_de satisfecho)")
    for row in rows:
        mark = "ELEGIBLE" if row["elegible"] else "BLOQUEADA"
        print(f"\n[{mark}] {row['id']} — {row['nombre']}")
        print(f"  estado={row['estado']} prioridad={row['prioridad']} hito={row['hito']} ceremony={row['ceremony']}")
        print(f"  archivo={row['archivo'] or '(SIN ARCHIVO — escribirlo es la tarea de la iteración)'}")
        if row["servicios"]:
            print(f"  servicios={', '.join(row['servicios'])}")
        if row["bloqueada_por"]:
            print(f"  depende_de pendiente: {', '.join(row['bloqueada_por'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
