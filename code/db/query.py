#!/usr/bin/env python3
"""Ad-hoc query helper for the SOYPRINT database.

    .venv/bin/python code/db/query.py "SELECT * FROM production LIMIT 5"
    .venv/bin/python code/db/query.py -f myquery.sql
    .venv/bin/python code/db/query.py --tables          # list tables + views
    .venv/bin/python code/db/query.py "SELECT ..." --csv > out.csv

No SQL given -> opens an interactive DuckDB shell on the database.
Read-only: safe to run while the pipeline is writing elsewhere.
"""
import sys
from pathlib import Path

import duckdb

DB = Path(__file__).resolve().parents[2] / "data/db/soyprint.duckdb"


def main() -> None:
    args = sys.argv[1:]
    as_csv = "--csv" in args
    args = [a for a in args if a != "--csv"]
    con = duckdb.connect(str(DB), read_only=True)

    if not args:
        print(f"Interactive DuckDB shell on {DB.name} (Ctrl-D to exit).")
        con.close()
        import subprocess
        subprocess.run([sys.executable, "-c",
            f"import duckdb;duckdb.connect(r'{DB}',read_only=True).cursor()"
            ".execute('.shell')"]) if False else _repl(str(DB))
        return

    if args[0] == "--tables":
        print(con.sql("""
            SELECT table_type, table_name FROM information_schema.tables
            WHERE table_schema='main' ORDER BY table_type, table_name
        """).df().to_string(index=False))
        return

    sql = Path(args[1]).read_text() if args[0] in ("-f", "--file") else args[0]
    rel = con.sql(sql)
    if as_csv:
        sys.stdout.write(rel.df().to_csv(index=False))
    else:
        import pandas as pd
        with pd.option_context("display.max_rows", 100, "display.width", 200):
            print(rel.df().to_string(index=False))


def _repl(db: str) -> None:
    con = duckdb.connect(db, read_only=True)
    import pandas as pd
    while True:
        try:
            q = input("soyprint> ").strip()
        except EOFError:
            print(); break
        if not q:
            continue
        try:
            with pd.option_context("display.max_rows", 100, "display.width", 200):
                print(con.sql(q).df().to_string(index=False))
        except Exception as e:  # noqa: BLE001 - surface the SQL error, keep going
            print(f"error: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
