#!/usr/bin/env python3
"""
validate-artifacts.py — Verificación de conformidad del harness y sus artefactos.

Comprueba que una instalación del harness (o el repo canónico) cumpla:
  1. routing-rules.yaml  → provider_routing tiene model_resolution + capability_tiers,
     y el provider ollama declara hermes + kimi.
  2. Templates de épica/propuesta tienen las secciones requeridas.
  3. Épicas marcadas `Detalle de ejecución: reforzado` cumplen el formato ejecutable:
     - sección "Contexto a cargar"
     - cada tarea de `## Tareas` tiene línea "Hecho cuando:" (criterio verificable)
       y "Objetivo:" (path/área).

Uso:
  python3 validate-artifacts.py [DIR]
    DIR = raíz del harness canónico (con config/, roadmap/) o un management/ instalado.
          Default: directorio actual.
  python3 validate-artifacts.py --epics roadmap/epicas/E10.md roadmap/epicas/E11.md
          Valida solo el formato reforzado de las épicas dadas.

Exit 0 si todo pasa; 1 si hay fallos.
"""
import sys, os, re, glob

try:
    import yaml
except ImportError:
    yaml = None

GREEN, RED, YELL, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[0m"
ok = lambda m: print(f"  {GREEN}✓{NC} {m}")
bad = lambda m: print(f"  {RED}✗{NC} {m}")
warn = lambda m: print(f"  {YELL}⚠{NC} {m}")

errors = []


def fail(m):
    errors.append(m)
    bad(m)


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def validate_routing(base):
    p = os.path.join(base, "config", "routing-rules.yaml")
    if not os.path.exists(p):
        warn(f"sin config/routing-rules.yaml en {base} — salteo")
        return
    print(f"\nrouting-rules.yaml ({p})")
    if yaml is None:
        warn("PyYAML no disponible — validación textual")
        txt = read(p)
        for key in ("model_resolution", "capability_tiers", "hermes", "kimi"):
            (ok if key in txt else fail)(f"contiene `{key}`")
        return
    d = yaml.safe_load(read(p))
    pr = (d or {}).get("provider_routing", {})
    (ok if "model_resolution" in pr else fail)("provider_routing.model_resolution presente")
    (ok if "capability_tiers" in pr else fail)("provider_routing.capability_tiers presente")
    models = pr.get("providers", {}).get("ollama", {}).get("models", {})
    (ok if "hermes" in models else fail)("provider ollama declara `hermes`")
    (ok if "kimi" in models else fail)("provider ollama declara `kimi`")


def validate_templates(base):
    specs = [
        ("roadmap/epicas/_TEMPLATE.md", ["## Contexto a cargar", "Detalle de ejecución", "Hecho cuando"]),
        ("roadmap/propuestas/_TEMPLATE.md", ["Detalle de ejecución"]),
    ]
    for rel, needs in specs:
        p = os.path.join(base, rel)
        if not os.path.exists(p):
            warn(f"sin {rel} — salteo")
            continue
        print(f"\n{rel}")
        txt = read(p)
        for n in needs:
            (ok if n in txt else fail)(f"sección/campo `{n}`")


TASK_RE = re.compile(r"^- \[[ x]\] ", re.M)


def validate_reforzado_epic(p):
    """Valida que una épica reforzada tenga Contexto a cargar y tareas con Hecho cuando + Objetivo."""
    txt = read(p)
    name = os.path.basename(p)
    if "Detalle de ejecución:" not in txt:
        return None  # no declara modo → no aplica
    mode = re.search(r"Detalle de ejecución:\*?\*?\s*(\w+)", txt)
    if not mode or mode.group(1).lower() != "reforzado":
        return None
    print(f"\n{name} (reforzado)")
    passed = True
    if "## Contexto a cargar" not in txt:
        fail(f"{name}: falta sección `## Contexto a cargar`"); passed = False
    else:
        ok("Contexto a cargar")
    # Aislar la sección ## Tareas
    m = re.search(r"\n## Tareas\b(.*?)(?=\n## )", txt, re.S)
    if not m:
        fail(f"{name}: no se encontró sección `## Tareas`"); return False
    body = m.group(1)
    # Dividir en bloques por cada item top-level "- [ ]"
    items = re.split(r"\n(?=- \[[ x]\] )", body)
    items = [b for b in items if TASK_RE.match(b.strip().split("\n")[0] or "")]
    if not items:
        fail(f"{name}: sección Tareas sin items"); return False
    missing_done, missing_obj = 0, 0
    for b in items:
        if "Hecho cuando" not in b:
            missing_done += 1
        if "Objetivo:" not in b:
            missing_obj += 1
    if missing_done:
        fail(f"{name}: {missing_done}/{len(items)} tareas sin `Hecho cuando:`"); passed = False
    else:
        ok(f"{len(items)} tareas con `Hecho cuando:`")
    if missing_obj:
        fail(f"{name}: {missing_obj}/{len(items)} tareas sin `Objetivo:`"); passed = False
    else:
        ok(f"{len(items)} tareas con `Objetivo:`")
    return passed


def main():
    args = sys.argv[1:]
    if args and args[0] == "--epics":
        for p in args[1:]:
            r = validate_reforzado_epic(p)
            if r is None:
                warn(f"{os.path.basename(p)}: no declara `reforzado` — salteado")
    else:
        base = args[0] if args else "."
        base = os.path.abspath(base)
        print(f"Validando harness en: {base}")
        validate_routing(base)
        validate_templates(base)
        # Épicas reforzadas en el árbol
        epics = glob.glob(os.path.join(base, "roadmap", "epicas", "E*.md"))
        epics += glob.glob(os.path.join(base, "management", "roadmap", "epicas", "E*.md"))
        checked = 0
        for p in sorted(epics):
            if validate_reforzado_epic(p) is not None:
                checked += 1
        if checked == 0:
            print("\n(sin épicas en modo reforzado para validar)")

    print()
    if errors:
        print(f"{RED}FALLÓ{NC} — {len(errors)} problema(s).")
        sys.exit(1)
    print(f"{GREEN}OK{NC} — sin problemas.")
    sys.exit(0)


if __name__ == "__main__":
    main()
