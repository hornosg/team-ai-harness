#!/usr/bin/env python3
"""
wire-adrs.py — Valida el cableado ADR ↔ skill.

Cada ADR declara en su frontmatter qué skills lo llevan a cabo y cuáles
controlan que se cumpla:

    ---
    adr: ADR-002
    status: accepted
    skills:
      implement:
        - dev/hexagonal-go
        - dev/prometheus
      verify:
        - dev/go-hex-audit
        - dev/code-reviewer
    ---

Este script recorre <adr_dir>, parsea ese bloque y valida que cada skill exista
en <skills_dir> (busca <area>/<slug>/SKILL.md y, como fallback, <slug>/SKILL.md).
A diferencia de wire-skills.py NO siembra (un ADR no referencia skills en prosa):
el mapa se cura a mano en el frontmatter; esto sólo lo verifica y reporta.

Uso:
  ./wire-adrs.py <adr_dir> <skills_dir>

Sale con código 2 si hay referencias rotas o ADRs sin cablear.
"""
import re
import sys
from pathlib import Path

ROLES = ("implement", "verify")          # se validan: deben existir
INFO_ROLES = ("pending",)                # skills deseadas aún inexistentes (no se validan)
ALL_ROLES = ROLES + INFO_ROLES


def parse_frontmatter(text: str):
    """Devuelve dict {implement:[...], verify:[...], pending:[...]} o None."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return None
    fm = lines[1:end]

    out = {r: [] for r in ALL_ROLES}
    in_skills = False
    current = None
    for ln in fm:
        if re.match(r"^skills:\s*$", ln):
            in_skills = True
            continue
        if in_skills:
            m_role = re.match(r"^\s{2}(\w+):\s*(#.*)?$", ln)
            m_item = re.match(r"^\s{4}-\s+([^\s#]+)", ln)
            if m_role and m_role.group(1) in ALL_ROLES:
                current = m_role.group(1)
            elif m_role:                    # sub-clave desconocida → ignorar items
                current = None
            elif m_item and current:
                out[current].append(m_item.group(1))
            elif re.match(r"^\S", ln):       # otra clave top-level → fin del bloque
                in_skills = False
    return out if any(out[r] for r in ALL_ROLES) else None


def skill_exists(skills_dir: Path, ref: str) -> bool:
    slug = ref.split("/")[-1]
    return (skills_dir / ref / "SKILL.md").is_file() or \
           (skills_dir / slug / "SKILL.md").is_file()


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    adr_dir, skills_dir = Path(sys.argv[1]), Path(sys.argv[2])
    if not adr_dir.is_dir() or not skills_dir.is_dir():
        print(f"✗ dir inválido: {adr_dir} / {skills_dir}")
        sys.exit(1)

    print(f"\nValidando {adr_dir} ↔ {skills_dir}\n")
    broken = uncabled = 0
    pending_all = set()
    for f in sorted(adr_dir.glob("*.md")):
        fm = parse_frontmatter(f.read_text(encoding="utf-8"))
        if fm is None:
            uncabled += 1
            print(f"  ⚠ {f.name:40s} SIN cablear (falta skills.implement/verify)")
            continue
        miss = []
        for role in ROLES:
            for ref in fm[role]:
                if not skill_exists(skills_dir, ref):
                    miss.append(f"{role}:{ref}")
        impl = ", ".join(fm["implement"]) or "—"
        ver = ", ".join(fm["verify"]) or "—"
        if miss:
            broken += len(miss)
            print(f"  ✗ {f.name:40s} ROTO: {', '.join(miss)}")
        else:
            print(f"  ✓ {f.name:40s} impl[{impl}]  verify[{ver}]")
        if fm["pending"]:
            pending_all.update(fm["pending"])
            print(f"    ℹ pending (skills a crear): {', '.join(fm['pending'])}")

    print(f"\n  {broken} referencias rotas, {uncabled} ADRs sin cablear")
    if pending_all:
        print(f"  {len(pending_all)} skills pendientes únicas: {', '.join(sorted(pending_all))}")
    if broken or uncabled:
        sys.exit(2)


if __name__ == "__main__":
    main()
