#!/usr/bin/env python3
"""
wire-skills.py — Cablea agentes ↔ skills de forma declarativa.

Para cada agente en <agents_dir>:
  1. Deriva las skills que referencia en su cuerpo (patrón skills/<area>/<slug>).
  2. Valida que cada skill exista en <skills_dir> (busca <area>/<slug>/SKILL.md
     y, como fallback, <slug>/SKILL.md para árboles con skills planas).
  3. Reescribe el frontmatter:
       - garantiza que `Skill` esté en `tools:`
       - agrega/reemplaza el bloque `skills:` (lista YAML) como FUENTE DE VERDAD
         del mapa agente→skill.

El cuerpo del agente NO se toca: el mapa vive en el frontmatter; el sync
materializa el resto (instalar SKILL.md en .claude/skills/, inyectar la lista).

Uso:
  ./wire-skills.py <agents_dir> <skills_dir> [--dry-run]
"""
import re
import sys
from pathlib import Path

SKILL_REF = re.compile(r"skills/([a-z0-9-]+)/([a-z0-9-]+)")


def split_frontmatter(text: str):
    """Devuelve (fm_lines, body) o (None, text) si no hay frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], "\n".join(lines[i + 1:])
    return None, text


def parse_tools(fm_lines):
    for ln in fm_lines:
        m = re.match(r"\s*tools:\s*\[(.*)\]\s*$", ln)
        if m:
            inner = m.group(1).strip()
            items = [x.strip() for x in inner.split(",")] if inner else []
            return [x for x in items if x]
    return None  # sin tools declaradas


def skill_exists(skills_dir: Path, area: str, slug: str) -> bool:
    return (skills_dir / area / slug / "SKILL.md").is_file() or \
           (skills_dir / slug / "SKILL.md").is_file()


def rewrite(agent_file: Path, skills_dir: Path, dry: bool):
    text = agent_file.read_text(encoding="utf-8")
    fm_lines, body = split_frontmatter(text)
    if fm_lines is None:
        return ("skip", agent_file.name, [], [])

    # 1. skills referenciadas en el cuerpo (dedup, orden de aparición)
    refs, seen = [], set()
    for area, slug in SKILL_REF.findall(body):
        key = f"{area}/{slug}"
        if key not in seen:
            seen.add(key)
            refs.append((area, slug))

    valid, missing = [], []
    for area, slug in refs:
        (valid if skill_exists(skills_dir, area, slug) else missing).append(f"{area}/{slug}")

    # 2. tools: garantizar Skill
    tools = parse_tools(fm_lines)
    if tools is None:
        tools = []
    if valid and "Skill" not in tools:
        tools = tools + ["Skill"]

    # 3. reconstruir frontmatter
    out = []
    skipping_skills_block = False
    for ln in fm_lines:
        if re.match(r"\s*skills:\s*$", ln) or re.match(r"\s*skills:\s*\[.*\]\s*$", ln):
            skipping_skills_block = True
            continue
        if skipping_skills_block:
            if re.match(r"\s*-\s+", ln):   # ítem de la lista vieja
                continue
            skipping_skills_block = False
        if re.match(r"\s*tools:\s*", ln):
            out.append(f"tools: [{', '.join(tools)}]")
            continue
        out.append(ln)

    # insertar bloque skills: después de tools (o al final si no hay tools)
    new_fm = []
    inserted = False
    for ln in out:
        new_fm.append(ln)
        if not inserted and ln.startswith("tools:"):
            if valid:
                new_fm.append("skills:")
                new_fm.extend(f"  - {s}" for s in valid)
            inserted = True
    if not inserted and valid:
        new_fm.append("skills:")
        new_fm.extend(f"  - {s}" for s in valid)

    new_text = "---\n" + "\n".join(new_fm) + "\n---\n" + body
    if not new_text.endswith("\n"):
        new_text += "\n"

    if not dry and new_text != text:
        agent_file.write_text(new_text, encoding="utf-8")

    status = "wired" if valid else "no-skills"
    return (status, agent_file.name, valid, missing)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 2:
        print(__doc__)
        sys.exit(1)
    agents_dir, skills_dir = Path(args[0]), Path(args[1])
    if not agents_dir.is_dir() or not skills_dir.is_dir():
        print(f"✗ dir inválido: {agents_dir} / {skills_dir}")
        sys.exit(1)

    print(f"\n{'[DRY RUN] ' if dry else ''}Cableando {agents_dir} ↔ {skills_dir}\n")
    wired = total_missing = 0
    for f in sorted(agents_dir.rglob("*.md")):
        status, name, valid, missing = rewrite(f, skills_dir, dry)
        if status == "wired":
            wired += 1
            print(f"  ✓ {name:28s} → {', '.join(valid)}")
        if missing:
            total_missing += len(missing)
            print(f"  ⚠ {name:28s} REFERENCIAS ROTAS: {', '.join(missing)}")
    print(f"\n  {wired} agentes cableados" +
          (f", {total_missing} referencias rotas" if total_missing else ", sin referencias rotas"))
    if total_missing:
        sys.exit(2)


if __name__ == "__main__":
    main()
