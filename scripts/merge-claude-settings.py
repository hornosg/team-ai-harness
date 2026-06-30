#!/usr/bin/env python3
"""merge-claude-settings.py

Mergea la configuración MCP de Engram en .claude/settings.local.json sin pisar
otros valores (ej. permissions.allow). Crea el archivo si no existe.

Uso:
  merge-claude-settings.py <project_root>
"""

import json
import sys
from pathlib import Path

ENGRAM_MCP = {
    "engram": {
        "command": "engram",
        "args": ["mcp", "--tools=agent"]
    }
}


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: merge-claude-settings.py <project_root>", file=sys.stderr)
        return 1

    root = Path(sys.argv[1]).resolve()
    claude_dir = root / ".claude"
    settings_file = claude_dir / "settings.local.json"

    claude_dir.mkdir(parents=True, exist_ok=True)

    if settings_file.exists():
        try:
            with settings_file.open("r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as exc:
            print(f"Error: {settings_file} existe pero no es JSON válido: {exc}", file=sys.stderr)
            return 2
    else:
        data = {}

    if "mcpServers" not in data:
        data["mcpServers"] = {}

    if "engram" in data["mcpServers"]:
        print(f"ℹ MCP Engram ya configurado en {settings_file} — actualizando entry")

    data["mcpServers"].update(ENGRAM_MCP)

    with settings_file.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"✓ MCP Engram configurado en {settings_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
