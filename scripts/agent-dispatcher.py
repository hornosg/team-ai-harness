#!/usr/bin/env python3
"""Opt-in provider-neutral per-agent dispatcher for Team AI Harness."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path


PROVIDERS = ("claude", "codex", "ollama")
CONTEXT_MODES = ("full", "native")

# Qué modo de contexto le corresponde a cada provider por defecto.
#
# `full` inyecta inline TODO el contexto (CLAUDE.md del lab, PROJECT.md, routing-rules,
# ceremony-levels y el texto completo de cada skill del agente). Es lo correcto para `codex`: no
# conoce el harness, no carga CLAUDE.md solo y no tiene el tool `Skill` — si no viaja en el pack,
# no existe.
#
# `native` es para los providers que corren SOBRE Claude Code — `claude` y también `ollama`, que
# es `ollama launch claude` (el mismo Claude Code apuntando al endpoint de Ollama, con el harness
# instalado). Ahí ese pack es REDUNDANTE y caro: el runtime ya carga los CLAUDE.md del lab y del
# cwd por sí solo, y las skills están instaladas en `.claude/skills/` accesibles por el tool
# `Skill`. Inyectarlas otra vez duplica el contenido dentro de la misma ventana. Medido
# 2026-07-27 sobre los 32 agentes: 2,52 MB de pack full contra 182 KB en native (-92,8%); para
# `meta-router`, 123,9 KB → 12,0 KB, sobre una iteración de loop que ya arrancaba en ~202 KB. En
# native el pack lleva las instrucciones del agente (que es lo que el runtime NO carga solo) y
# punteros por path al resto, para que el agente lea bajo demanda sólo lo que la tarea necesita.
DEFAULT_CONTEXT_MODE = {"claude": "native", "codex": "full", "ollama": "native"}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def find_lab_root() -> Path:
    configured = os.environ.get("DEVY_PATH")
    starts = []
    if configured:
        starts.append(Path(configured).expanduser().resolve())
    starts.extend((Path.cwd().resolve(), Path(__file__).resolve()))
    for start in starts:
        for candidate in (start, *start.parents):
            if (candidate / "management" / "PROJECT.md").is_file():
                return candidate
    raise SystemExit("No pude resolver el lab: definí DEVY_PATH o ejecutá dentro de Projects.")


def harness_root() -> Path:
    # This file lives directly under management/scripts or team-ai-harness/scripts.
    return Path(__file__).resolve().parent.parent


def split_frontmatter(text: str) -> tuple[str, str] | None:
    """Separa el bloque YAML del cuerpo, cerrando en una LÍNEA que sea exactamente `---`.

    El `text.split("---", 2)` anterior cortaba en la primera aparición de `---` en cualquier
    posición: `agents/dev/senior-backend.md` cerraba su frontmatter con `|---` (typo) y el
    parser lo aceptaba igual, dejando basura en el bloque. Peor: cualquier `---` dentro de una
    descripción habría truncado el frontmatter en silencio, y el agente se habría despachado
    sin `model` (o con uno equivocado) sin ningún error visible.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])
    return None


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    split = split_frontmatter(text)
    if split is None:
        return {}, text
    block, body = split
    values = {}
    for line in block.splitlines():
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*?)\s*$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"')
    return values, body.lstrip()


def find_agent(name: str) -> tuple[Path, dict[str, str], str]:
    root = harness_root() / "agents"
    for path in sorted(root.rglob("*.md")):
        frontmatter, body = parse_frontmatter(read_text(path))
        if frontmatter.get("name") == name:
            return path, frontmatter, body
    raise SystemExit(f"Agente no encontrado: {name} en {root}")


def skill_refs(agent_path: Path) -> list[str]:
    split = split_frontmatter(read_text(agent_path))
    if split is None:
        return []
    block = split[0]
    refs = []
    active = False
    for line in block.splitlines():
        if re.match(r"^skills:\s*$", line):
            active = True
            continue
        if active and re.match(r"^\S", line):
            active = False
        if active:
            match = re.match(r"^\s*-\s+(.+?)\s*$", line)
            if match:
                refs.append(match.group(1).strip())
    return refs


def resolve_skill(ref: str) -> Path | None:
    root = harness_root() / "skills"
    direct = root / ref / "SKILL.md"
    if direct.is_file():
        return direct
    fallback = root / ref.rsplit("/", 1)[-1] / "SKILL.md"
    return fallback if fallback.is_file() else None


def context_files(lab_root: Path, project: str | None) -> list[tuple[str, Path]]:
    files = []
    for label, path in (
        ("lab AGENTS", lab_root / "AGENTS.md"),
        ("lab CLAUDE", lab_root / "CLAUDE.md"),
        ("lab PROJECT", lab_root / "management" / "PROJECT.md"),
        ("routing rules", harness_root() / "config" / "routing-rules.yaml"),
        ("ceremony levels", harness_root() / "config" / "ceremony-levels.yaml"),
    ):
        if path.is_file():
            files.append((label, path))
    if project:
        pointer = lab_root / "management" / "projects" / project / "PROJECT.md"
        if pointer.is_file():
            files.append((f"project pointer: {project}", pointer))
        elif project != "platform":
            raise SystemExit(f"No existe el PROJECT.md de {project}: {pointer}")
    return files


def build_context(
    agent: str,
    agent_path: Path,
    frontmatter: dict[str, str],
    body: str,
    lab_root: Path,
    project: str | None,
    task: str,
    origin: str | None,
    provider: str,
    model: str,
    codex_caveman: str | None,
    context_mode: str,
) -> str:
    sections = [
        "# Team AI Harness - provider dispatch",
        "",
        "## Runtime contract",
        f"- agent: {agent}",
        f"- execution_origin: {origin or 'unspecified'}",
        f"- agent_provider: {provider}",
        f"- model: {model}",
        f"- project: {project or 'unspecified'}",
        f"- context_mode: {context_mode}",
        f"- codex_style: {codex_caveman or 'off'}",
        "",
        "This is an isolated invocation. Do not assume conversation history.",
        "Do not claim a file, test, escalation, commit, or handoff exists unless verified on disk.",
        "L4 auth, identity, money, PII, RLS, and compliance work requires frontier review and owner sign-off.",
    ]
    if context_mode == "native":
        # Punteros, no contenido: el runtime ya carga los CLAUDE.md y tiene el tool `Skill`.
        # Cargar de acá sólo lo que la tarea concreta pida.
        sections += [
            "",
            "## Context files (leer BAJO DEMANDA, no de entrada)",
            "El runtime ya cargó los CLAUDE.md del lab. Estos NO están cargados; leelos sólo si"
            " la tarea los necesita:",
        ]
        sections += [f"- {label}: {path}" for label, path in context_files(lab_root, project)]
    else:
        for label, path in context_files(lab_root, project):
            sections += ["", f"## Context file: {label} ({path})", "~~~text", read_text(path), "~~~"]
    if provider == "codex" and codex_caveman:
        # `/caveman` is an interactive CLI shortcut. `$caveman` is the explicit
        # skill invocation that can travel inside a headless `codex exec` prompt.
        task = f"$caveman {codex_caveman}\n\n{task}"
    sections += [
        "",
        f"## Canonical agent: {agent_path}",
        "### Frontmatter",
        "~~~yaml",
        json.dumps(frontmatter, ensure_ascii=False, indent=2),
        "~~~",
        "### Instructions",
        "~~~markdown",
        body,
        "~~~",
    ]
    refs = skill_refs(agent_path)
    if context_mode == "native":
        # El tool `Skill` las carga por nombre; inyectar el texto acá las duplicaría en la ventana.
        sections += ["", "## Skills del agente (invocar con el tool `Skill`, NO están precargadas)"]
        for ref in refs:
            path = resolve_skill(ref)
            name = ref.rsplit("/", 1)[-1]
            sections.append(f"- {name}" + (f"  ({path})" if path else "  (SIN RESOLVER)"))
    else:
        for ref in refs:
            path = resolve_skill(ref)
            if path is None:
                sections += ["", f"## Missing skill reference: {ref}"]
            else:
                sections += ["", f"## Skill: {ref} ({path})", "~~~markdown", read_text(path), "~~~"]
    sections += [
        "",
        "## Dispatcher handoff policy",
        "The caller owns the handoff for this isolated invocation.",
        "If the Task says read-only or no handoff, do not call mem_session_summary or any other write-capable MCP tool.",
        "If the Task explicitly requests memory, use an explicit project and do not invent a session_id.",
        "",
        "## Task",
        task,
        "",
        "## Required final marker",
        "End with exactly one line: DISPATCH: success|blocked|empty|checkpoint|rate_limited|auth_error|tool_error|interrupted|unknown_error",
    ]
    return "\n".join(sections) + "\n"


def selected_model(frontmatter: dict[str, str], provider: str, override: str | None) -> str:
    if override:
        return override
    declared = frontmatter.get("model", "")
    if provider == "claude" and declared:
        return declared.split("/", 1)[-1]
    raise SystemExit(f"Falta --model para provider externo: {provider}")


def resolve_codex_binary() -> str:
    """Resolve Codex even when the VS Code extension directory is not on PATH."""
    configured = os.environ.get("CODEX_BIN")
    if configured:
        path = Path(configured).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
        raise SystemExit(f"CODEX_BIN no apunta a un ejecutable: {path}")

    on_path = shutil.which("codex")
    if on_path:
        return on_path

    candidates = [Path.home() / ".local" / "bin" / "codex", Path.home() / ".cargo" / "bin" / "codex"]
    for extensions_root in (Path.home() / ".vscode-server" / "extensions", Path.home() / ".vscode" / "extensions"):
        if extensions_root.is_dir():
            candidates.extend(sorted(extensions_root.glob("openai.chatgpt-*/bin/*/codex"), reverse=True))
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    raise SystemExit(
        "Codex no está en el PATH. Definí CODEX_BIN=/ruta/al/binario/codex "
        "o agregá su directorio al PATH."
    )


def build_command(
    provider: str,
    model: str,
    prompt: str,
    cwd: Path,
    max_turns: int,
    unattended: bool,
    codex_sandbox: str,
    codex_bin: str | None,
) -> tuple[list[str], str | None]:
    if provider == "claude":
        command = ["claude", "-p", prompt, "--model", model, "--max-turns", str(max_turns)]
        if unattended:
            command.append("--dangerously-skip-permissions")
        return command, None
    if provider == "codex":
        command = [codex_bin or "codex", "exec", "--ephemeral", "--json", "--cd", str(cwd), "--model", model]
        if unattended:
            command.append("--dangerously-bypass-approvals-and-sandbox")
        else:
            command += ["--sandbox", codex_sandbox]
        command.append("-")
        return command, prompt
    command = ["ollama", "launch", "claude", "--model", model, "--", "-p", prompt, "--max-turns", str(max_turns)]
    if unattended:
        command.append("--dangerously-skip-permissions")
    return command, None


def classify(returncode: int, output: str) -> str:
    lowered = output.lower()
    markers = re.findall(
        r"dispatch:\s*(success|blocked|empty|checkpoint|rate_limited|auth_error|tool_error|interrupted|unknown_error)",
        output,
        flags=re.IGNORECASE,
    )
    if markers:
        return markers[-1].lower()
    if re.search(r"NEXT-TASK:\s*blocked", output, flags=re.IGNORECASE):
        return "blocked"
    if re.search(r"NEXT-TASK:\s*empty", output, flags=re.IGNORECASE):
        return "empty"
    if re.search(r"NEXT-TASK:\s*checkpoint", output, flags=re.IGNORECASE):
        return "checkpoint"
    if any(value in lowered for value in ("rate limit", "rate_limit", "too many requests", "429")):
        return "rate_limited"
    if any(value in lowered for value in ("not authenticated", "unauthorized", "api key", "authentication")):
        return "auth_error"
    if returncode < 0:
        return "interrupted"
    return "success" if returncode == 0 else "tool_error"


def printable_command(command: list[str]) -> str:
    args = list(command)
    if args and args[-1] == "-":
        args[-1] = "<context-pack via stdin>"
    else:
        args = [("<context-pack>" if value.startswith("# Team AI Harness") else value) for value in args]
    return shlex.join(args)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", required=True)
    parser.add_argument("--provider", required=True, choices=PROVIDERS)
    parser.add_argument("--model")
    parser.add_argument("--project")
    parser.add_argument("--task")
    parser.add_argument("--task-file", type=Path)
    parser.add_argument("--execution-origin", choices=PROVIDERS)
    parser.add_argument(
        "--context-mode",
        choices=CONTEXT_MODES,
        help="full = inyecta contexto y skills inline (providers externos); native = sólo punteros "
        "(claude ya carga CLAUDE.md y tiene el tool Skill). Default por provider.",
    )
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--max-turns", type=int, default=40)
    parser.add_argument("--codex-sandbox", choices=("read-only", "workspace-write", "danger-full-access"), default="read-only")
    parser.add_argument("--codex-caveman", choices=("lite", "full", "ultra", "wenyan"), help="Activa la skill Caveman en el prompt headless de Codex")
    parser.add_argument("--unattended", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if bool(args.task) == bool(args.task_file):
        parser.error("usar exactamente uno de --task o --task-file")
    task = args.task if args.task is not None else args.task_file.read_text(encoding="utf-8")

    lab_root = find_lab_root()
    agent_path, frontmatter, body = find_agent(args.agent)
    model = selected_model(frontmatter, args.provider, args.model)
    cwd = args.cwd.expanduser().resolve()
    if not cwd.is_dir():
        raise SystemExit(f"--cwd no es un directorio: {cwd}")

    context_mode = args.context_mode or DEFAULT_CONTEXT_MODE[args.provider]
    prompt = build_context(args.agent, agent_path, frontmatter, body, lab_root, args.project, task, args.execution_origin, args.provider, model, args.codex_caveman, context_mode)
    codex_bin = resolve_codex_binary() if args.provider == "codex" else None
    command, stdin_prompt = build_command(args.provider, model, prompt, cwd, args.max_turns, args.unattended, args.codex_sandbox, codex_bin)

    if args.dry_run:
        print(json.dumps({
            "status": "success",
            "dry_run": True,
            "agent": args.agent,
            "provider": args.provider,
            "model": model,
            "context_mode": context_mode,
            "execution_origin": args.execution_origin,
            "codex_caveman": args.codex_caveman,
            "project": args.project,
            "cwd": str(cwd),
            "context_bytes": len(prompt.encode("utf-8")),
            "command": printable_command(command),
        }, ensure_ascii=False))
        return 0

    try:
        completed = subprocess.run(command, input=stdin_prompt, cwd=str(cwd), capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        print(json.dumps({
            "status": "auth_error",
            "agent": args.agent,
            "provider": args.provider,
            "model": model,
            "error": f"provider executable not found: {exc.filename}",
        }, ensure_ascii=False))
        return 127

    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    status = classify(completed.returncode, output)
    print(json.dumps({
        "status": status,
        "agent": args.agent,
        "provider": args.provider,
        "model": model,
        "context_mode": context_mode,
        "execution_origin": args.execution_origin,
        "codex_caveman": args.codex_caveman,
        "project": args.project,
        "cwd": str(cwd),
        "returncode": completed.returncode,
        "output_tail": output[-12000:],
    }, ensure_ascii=False))
    return 0 if completed.returncode == 0 else completed.returncode or 1


if __name__ == "__main__":
    raise SystemExit(main())
