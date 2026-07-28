#!/usr/bin/env python3
"""Detecta criterios de aceptación que NO verifican lo que su contrato promete.

EL PATRÓN QUE ATACA (tres apariciones en dos días, 2026-07-26/28):

  1. PLAT-E38 · T-STK-M3 cerró con un spam de `/health` que la tarea anterior ya había
     declarado insuficiente. El criterio se cumplía sin medir lo que importaba.
  2. PLAT-E39 · @dev-security objetó (B1) que el "Hecho cuando" de T2–T6 pedía paridad de
     datos — "devuelve la misma lista que pim" — y no autorización. Habría pasado con los
     seis agujeros de aislamiento abiertos, que son la razón de existir de la épica.
  3. PLAT-E39 · T1a: el contrato pedía `src/<módulo>/{domain,application,infrastructure}`
     y el criterio sólo miraba healthy + /health + /metrics. El agente cumplió el criterio
     literal y marcó [x] con razón: la estructura hexagonal no estaba en ningún check.

Las tres veces el agente hizo lo correcto según la letra. El defecto está un nivel más arriba,
en la redacción — y por eso lo caza un linter y no un revisor con mejor criterio.

QUÉ CHEQUEA, por tarea:

  A. Cobertura — cada artefacto verificable que el Contrato nombra (paths, archivos, comandos,
     endpoints) aparece en el "Hecho cuando". Es heurístico y por eso avisa, no bloquea.
  B. Ejecutabilidad — el criterio contiene al menos un comando o check concreto, no sólo prosa.
  C. Prueba negativa — el criterio dice qué debe FALLAR, no sólo qué debe funcionar. Un criterio
     que sólo comprueba el camino feliz pasa igual con el control ausente: es el defecto de B1.
  D. Verificabilidad temporal — el criterio no depende de artefactos que otra tarea posterior
     recién va a crear (el caso T1c: "sin JWT → 401" cuando las rutas llegan cinco tareas después;
     en disco daba 404, que no es 401 ni por asomo).

Uso:
  scripts/check-criterios.py platform/epicas/PLAT-E39-*.md
  scripts/check-criterios.py --all          # todas las épicas activas
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TASK_RE = re.compile(r"^- \[([ x])\] \*\*(?P<id>T[\w.-]+)\s*·\s*(?P<title>.+?)\*\*\s*$")
FIELD_RE = re.compile(r"^\s+(?P<key>Objetivo|Contrato|Hecho cuando|Depende de|Ceremony):\s*(?P<val>.*)$")

# Señales de que el criterio se puede ejecutar y no es prosa.
EXECUTABLE = re.compile(
    r"`[^`]*(?:curl|docker|go |grep|psql|make|npm|pytest|test |ls |cat |find|\./"
    # SQL cuenta como check ejecutable: una consulta con resultado esperado es tan verificable
    # como un curl. Sin esto el linter marcaba como "prosa" criterios que decían
    # `SELECT tablename FROM pg_tables …` → 0 filas.
    r"|SELECT |INSERT |DROP |UPDATE |GRANT )[^`]*`"
    r"|HTTP \d{3}|→ *\d{3}|\b\d{3}\b(?= *(?:/|,|;|\.|$))|\*\*\d+ filas?\*\*|→ *\*\*\d+"
)
# Señales de que el criterio prueba que algo FALLA cuando debe fallar.
NEGATIVE = re.compile(
    r"\bfalla\b|\bFALLA\b|\b0 filas\b|\bidéntico\b|\bdebe fallar\b|\bsin resultados\b|\bno encuentra\b|\bsin JWT\b|\brechaza\b"
    r"|\b40[13]\b|\b4\d\d\b|\bdeny\b|\bno devuelve\b|\bsin \w+\b.*→|error de permisos|por permisos",
    re.IGNORECASE,
)
# Artefactos concretos que un contrato puede prometer.
ARTIFACT = re.compile(r"`([^`]+)`")
NOISE = {"cmd/", "tmp/", "external: true", "true", "false", "GET", "POST", "PUT", "DELETE"}


def split_tasks(text: str) -> list[dict]:
    tasks, current = [], None
    for line in text.splitlines():
        match = TASK_RE.match(line)
        if match:
            if current:
                tasks.append(current)
            current = {"id": match.group("id"), "title": match.group("title"),
                       "done": match.group(1) == "x", "fields": {}}
            continue
        if current:
            field = FIELD_RE.match(line)
            if field:
                current["fields"][field.group("key")] = field.group("val")
            elif line.strip() and not line.startswith(" "):
                tasks.append(current)
                current = None
    if current:
        tasks.append(current)
    return tasks


def artifacts(text: str) -> set[str]:
    """Cosas concretas que el contrato promete y que deberían poder chequearse."""
    found: set[str] = set()
    for raw in ARTIFACT.findall(text):
        value = raw.strip()
        if value in NOISE or len(value) < 4:
            continue
        # Los `.md` son referencias documentales ("ver platform-architecture.md"), no artefactos
        # que la tarea produzca: exigir que el criterio los chequee es ruido, y un linter que
        # marca todo se ignora justo cuando dice algo real.
        if value.endswith(".md"):
            continue
        # Lo que el contrato dice explícitamente que NO produce tampoco es su entregable: paths que
        # declara no tocar, no crear, o de los que sólo se cuida de no colisionar.
        escaped = re.escape(value)
        if re.search(rf"(?:no colision\w*|sin tocar|\*\*(?:NO|no)\*\*|\bno se cre\w+|\bnunca\b)[^`]*`{escaped}`", text, re.I):
            continue
        if re.search(rf"`{escaped}`[^.;]*\b(?:NO|no) se cre\w+", text, re.I):
            continue
        # Sólo paths, archivos y comandos — no prosa entre backticks.
        if "/" in value or value.endswith((".go", ".sql", ".yml", ".yaml", ".toml")):
            found.add(value)
    return found


def normalize(value: str) -> str:
    """`src/<módulo>/{domain,application}` → tokens comparables."""
    value = re.sub(r"<[^>]+>", "*", value)
    return re.sub(r"[{},]", " ", value)


def covered(artifact: str, criterion: str) -> bool:
    parts = [p for p in re.split(r"[/ *]+", normalize(artifact)) if len(p) > 3]
    if not parts:
        return True
    return any(p.lower() in criterion.lower() for p in parts)


def temporal_risk(task: dict, criterion: str) -> str | None:
    """¿El criterio depende de algo que otra tarea posterior recién va a crear?

    El caso T1c: pedía `curl sin JWT → 401` cuando ninguna ruta de datos existía todavía (llegan
    en T2). En disco daba 404 — que no es 200, así que "parecía" cumplirse, sin probar nada.
    Un criterio E2E sobre una superficie que la propia tarea no monta es inverificable por
    construcción, y su forma más peligrosa es la que devuelve un error distinto del esperado.
    """
    mounts_routes = re.search(r"\bmonta\b|\bruta[s]? de datos\b|\bendpoint\b|\bhandler\b|\bcontroller\b",
                              task["fields"].get("Contrato", ""), re.I)
    needs_http = re.search(r"`?curl`?[^;]*(?:/api/|:PORT|localhost)", criterion, re.I)
    if needs_http and not mounts_routes:
        return ("el criterio hace un request HTTP a una ruta que esta tarea no monta — si la ruta "
                "no existe todavía la respuesta será 404 y el check no prueba nada")
    return None


def check(task: dict) -> list[str]:
    contract = task["fields"].get("Contrato", "")
    criterion = task["fields"].get("Hecho cuando", "")
    problems = []

    if not criterion:
        return ["sin 'Hecho cuando' — no hay forma de saber si está terminada"]

    missing = sorted(a for a in artifacts(contract) if not covered(a, criterion))
    if missing:
        problems.append(
            "el contrato promete artefactos que el criterio no chequea: " + ", ".join(f"`{m}`" for m in missing[:4])
        )
    if not EXECUTABLE.search(criterion):
        problems.append("el criterio es prosa: no tiene ningún comando ni código de respuesta concreto")
    if not NEGATIVE.search(criterion):
        problems.append(
            "sólo prueba el camino feliz: agregá qué debe FALLAR (un control ausente lo pasaría igual)"
        )
    riesgo = temporal_risk(task, criterion)
    if riesgo:
        problems.append(riesgo)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("archivos", nargs="*", type=Path)
    parser.add_argument("--all", action="store_true", help="todas las épicas bajo platform/ y projects/")
    parser.add_argument("--solo-abiertas", action="store_true", help="ignorar las ya marcadas [x]")
    args = parser.parse_args()

    files = list(args.archivos)
    if args.all:
        root = Path(__file__).resolve().parent.parent
        files = sorted(root.glob("platform/epicas/*.md")) + sorted(root.glob("projects/*/epicas/*.md"))
    if not files:
        parser.error("pasá archivos o --all")

    total = flagged = 0
    for path in files:
        if not path.is_file():
            continue
        tasks = split_tasks(path.read_text(encoding="utf-8"))
        rows = []
        for task in tasks:
            if args.solo_abiertas and task["done"]:
                continue
            total += 1
            problems = check(task)
            if problems:
                flagged += 1
                rows.append((task, problems))
        if rows:
            print(f"\n{path.name}")
            for task, problems in rows:
                mark = "x" if task["done"] else " "
                print(f"  [{mark}] {task['id']} · {task['title'][:60]}")
                for problem in problems:
                    print(f"      → {problem}")

    print(f"\n{flagged} de {total} tareas con criterios débiles.")
    print("Heurístico: avisa, no bloquea. Un aviso falso se ignora; uno real cuesta una épica entera.")
    return 1 if flagged else 0


if __name__ == "__main__":
    raise SystemExit(main())
