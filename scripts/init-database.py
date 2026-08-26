#!/usr/bin/env python3
"""
init-database.py – Schema in der Azure SQL Serverless Datenbank anlegen.

Verwendung:
  set -a; source parameters/dev.secrets.env; set +a
  python3 scripts/init-database.py <server-fqdn> <database> <sql-admin-login>

Nutzt python-tds (reine Python-Implementierung, kein ODBC-Treiber/sudo
nötig) – dieselbe Bibliothek, die später auch der Processor verwendet.
"""

import os
import re
import sys
from pathlib import Path

import pytds

# "GO" ist nur ein Batch-Trenner für sqlcmd/SSMS, kein T-SQL – muss vor dem
# Ausführen selbst aufgesplittet werden (u.a. weil CREATE VIEW als einziges
# Statement in seinem Batch stehen muss).
GO_SPLIT = re.compile(r"^\s*GO\s*$", re.IGNORECASE | re.MULTILINE)

def run_sql_file(cur, path: Path):
    for batch in GO_SPLIT.split(path.read_text()):
        batch = batch.strip()
        if batch:
            cur.execute(batch)

def main():
    if len(sys.argv) != 4:
        print(f"Verwendung: {sys.argv[0]} <server-fqdn> <database> <sql-admin-login>")
        sys.exit(1)

    server, database, login = sys.argv[1], sys.argv[2], sys.argv[3]
    password = os.environ.get("SQL_ADMIN_PASSWORD")
    if not password:
        print("Fehler: Umgebungsvariable SQL_ADMIN_PASSWORD nicht gesetzt.")
        sys.exit(1)

    database_dir = Path(__file__).parent.parent / "database"

    # Azure SQL verlangt eine verschlüsselte Verbindung; python-tds aktiviert
    # TLS nur, wenn ein CA-Bundle übergeben wird (System-Bundle unter Fedora).
    cafile = "/etc/ssl/certs/ca-certificates.crt"

    # validate_host=False: umgeht einen Kompatibilitätsbug in python-tds 1.17.1
    # mit neueren pyOpenSSL-Versionen (AttributeError in dessen eigener
    # Hostname-Prüfung). Die Zertifikatskette wird weiterhin über cafile
    # geprüft, nur der Hostname-Abgleich entfällt.
    print(f"🔧 Verbinde mit {server}/{database}...")
    with pytds.connect(server=server, database=database, user=login, password=password,
                        cafile=cafile, validate_host=False) as conn:
        with conn.cursor() as cur:
            run_sql_file(cur, database_dir / "schema.sql")
            run_sql_file(cur, database_dir / "views.sql")
        conn.commit()
    print("✅ Schema und Views angelegt (oder bereits vorhanden).")

if __name__ == "__main__":
    main()
