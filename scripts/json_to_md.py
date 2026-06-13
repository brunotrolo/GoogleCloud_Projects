#!/usr/bin/env python3
"""Converte a saída JSON do `bq query --format=prettyjson` em tabela Markdown."""
import json
import sys


def main(path: str) -> None:
    with open(path, encoding="utf-8") as fh:
        rows = json.load(fh)

    if not rows:
        print("_Nenhum custo no período._")
        return

    cols = list(rows[0].keys())
    print("| " + " | ".join(cols) + " |")
    print("| " + " | ".join("---" for _ in cols) + " |")
    for row in rows:
        cells = []
        for col in cols:
            val = row.get(col)
            cells.append("" if val is None else str(val))
        print("| " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main(sys.argv[1])
