"""
Download script for extending the soyprint model from 2013 to 2025.

Downloads all programmatically available input data for years 2014-2025.
Each dataset is saved in the same format and location the pipeline reads it
from: data/raw/{step}/{SOURCE}/ (e.g. data/raw/00/COMEX_exports/,
data/raw/00/IBGE_livestock/, data/raw/04/), so no manual reorganizing is needed.

Usage:
    python3 download_data.py                    # download all datasets for all years
    python3 download_data.py --years 2020 2021  # download specific years only
    python3 download_data.py --only comex sidra  # download only specific sources
    python3 download_data.py --dry-run           # show what would be downloaded

Data sources that require MANUAL download are listed at the end of this script
with instructions on where to find them.
"""

import os
import sys
import json
import time
import argparse
import urllib.request
import urllib.error
import urllib.parse
import csv
import io
import ssl
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BASE_DIR = Path(__file__).parent
# Write straight into the pipeline's input tree (data/raw/), organized by source
# subfolder, so downloaded files are read by the pipeline with no manual moving.
RAW_DIR = BASE_DIR.parent / "data" / "raw"
YEARS = list(range(2014, 2026))  # 2014 through 2025

# Retry settings
MAX_RETRIES = 3
RETRY_DELAY = 5  # seconds

# SSL context that doesn't verify (some Brazilian gov sites have cert issues)
SSL_CTX = ssl.create_default_context()
SSL_CTX.check_hostname = False
SSL_CTX.verify_mode = ssl.CERT_NONE


def log(msg):
    print(f"[INFO] {msg}")


def warn(msg):
    print(f"[WARN] {msg}", file=sys.stderr)


def error(msg):
    print(f"[ERROR] {msg}", file=sys.stderr)


def download(url, dest, encoding=None, timeout=120):
    """Download a URL to a local file with retries."""
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)

    if dest.exists() and dest.stat().st_size > 0:
        log(f"  Already exists, skipping: {dest.name}")
        return True

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            log(f"  Downloading: {url}")
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 soyprint-downloader"})
            with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
                data = resp.read()
                if encoding:
                    # Re-encode if needed
                    text = data.decode(encoding, errors="replace")
                    with open(dest, "w", encoding=encoding) as f:
                        f.write(text)
                else:
                    with open(dest, "wb") as f:
                        f.write(data)
            log(f"  Saved: {dest}")
            return True
        except Exception as e:
            warn(f"  Attempt {attempt}/{MAX_RETRIES} failed: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
    error(f"  FAILED to download: {url}")
    return False


def download_json(url, timeout=120):
    """Download a URL and return parsed JSON."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 soyprint-downloader"})
            with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            warn(f"  Attempt {attempt}/{MAX_RETRIES} failed for JSON: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
    return None


# ===========================================================================
# 1. COMEX TRADE DATA (MDIC) - Exports & Imports by municipality
# ===========================================================================

def download_comex(years, dry_run=False):
    """
    Download COMEX municipality-level trade data.
    Format: semicolon-separated CSV with columns:
      CO_ANO;CO_MES;SH4;CO_PAIS;SG_UF_MUN;CO_MUN;KG_LIQUIDO;VL_FOB

    The original 2013 files were named EXP_2013_MUN_COMEX.csv / IMP_2013_MUN_COMEX.csv
    and read with read.csv2() (semicolon separator).

    MDIC provides yearly files at:
      https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/EXP_{YEAR}_MUN.csv
      https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/IMP_{YEAR}_MUN.csv
    """
    log("=" * 60)
    log("COMEX Trade Data (MDIC)")
    log("=" * 60)

    base_url = "https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun"

    for year in years:
        for prefix in ["EXP", "IMP"]:
            url = f"{base_url}/{prefix}_{year}_MUN.csv"
            subdir = "COMEX_exports" if prefix == "EXP" else "COMEX_imports"
            dest = RAW_DIR / "00" / subdir / f"{prefix}_{year}_MUN_COMEX.csv"
            if dry_run:
                log(f"  Would download: {url} -> {dest}")
            else:
                download(url, dest)


# ===========================================================================
# 2. COMEX LOOKUP TABLES (MDIC) - Country codes, Municipality codes
# ===========================================================================

def download_comex_lookups(dry_run=False):
    """
    Download COMEX auxiliary tables.

    PAIS_COMEX.csv format (semicolon-separated, ISO-8859-1):
      CO_PAIS;CO_PAIS_ISON3;CO_PAIS_ISOA3;NO_PAIS;NO_PAIS_ING;NO_PAIS_ESP

    UF_MUN_COMEX.csv format (semicolon-separated, ISO-8859-1):
      CO_MUN_GEO;NO_MUN;NO_MUN_MIN;SG_UF
    """
    log("=" * 60)
    log("COMEX Lookup Tables")
    log("=" * 60)

    lookups = {
        "PAIS_COMEX.csv": "https://balanca.economia.gov.br/balanca/bd/tabelas/PAIS.csv",
        "UF_MUN_COMEX.csv": "https://balanca.economia.gov.br/balanca/bd/tabelas/UF_MUN.csv",
    }

    for fname, url in lookups.items():
        dest = RAW_DIR / "00" / "COMEX_codes" / fname
        if dry_run:
            log(f"  Would download: {url} -> {dest}")
            # step 04 also reads PAIS_COMEX.csv from data/raw/04/
            if fname == "PAIS_COMEX.csv":
                log(f"  Would also copy -> {RAW_DIR / '04' / fname}")
        else:
            # These are ISO-8859-1 encoded, keep as-is
            download(url, dest, encoding="ISO-8859-1")
            # step 04 reads PAIS_COMEX.csv from data/raw/04/ as well
            if fname == "PAIS_COMEX.csv" and dest.exists():
                import shutil
                dest_04 = RAW_DIR / "04" / fname
                dest_04.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest, dest_04)
                log(f"  Copied to {dest_04}")


# ===========================================================================
# 3. IBGE SIDRA - Soybean Production (Table 1612)
# ===========================================================================

def download_sidra_production(years, dry_run=False):
    """
    Download IBGE SIDRA Table 1612 - soybean production by municipality.

    Original format (read with read.csv, skip=2):
      "Cód.","Município","Produto","Ano","Área plantada","Área colhida","Quantidade produzida"

    SIDRA API returns JSON. We convert to the same CSV format.

    API URL pattern:
      https://apisidra.ibge.gov.br/values/t/1612/n6/all/v/109,216,214/p/{year}/c81/2713
      v/109 = area planted (ha), v/216 = area harvested (ha), v/214 = production (tonnes)
      (NB: v/215 = Valor da produção / Mil Reais -- the production *value*, NOT tonnes;
       a previous version used v/214,216,215 and wrote the monetary value into the
       production column, inflating prod_bean for the affected years.)
      c81/2713 = Soja (em grão)
    """
    log("=" * 60)
    log("IBGE SIDRA Table 1612 - Soybean Production")
    log("=" * 60)

    for year in years:
        dest = RAW_DIR / "00" / "IBGE_production" / f"Production_tabela1612_IBGE_{year}.csv"
        if dry_run:
            log(f"  Would download SIDRA 1612 for {year} -> {dest}")
            continue

        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        url = (
            f"https://apisidra.ibge.gov.br/values/t/1612/n6/all"
            f"/v/109,216,214/p/{year}/c81/2713"
        )
        log(f"  Fetching SIDRA 1612 for year {year}...")
        data = download_json(url, timeout=180)
        if not data:
            error(f"  Failed to download SIDRA 1612 for {year}")
            continue

        # data[0] is header, data[1:] are rows
        # Convert to CSV matching original format:
        # "Cód.","Município","Produto","Ano","Área plantada (Hectares)","Área colhida (Hectares)","Quantidade produzida (Toneladas)"
        dest.parent.mkdir(parents=True, exist_ok=True)

        # Group by municipality - SIDRA returns one row per variable
        munis = {}
        for row in data[1:]:
            co_mun = row.get("D1C") or row.get("Município (Código)")
            nm_mun = row.get("D1N") or row.get("Município")
            var_code = row.get("D2C") or row.get("Variável (Código)")
            value = row.get("V") or row.get("Valor")

            if co_mun not in munis:
                munis[co_mun] = {"code": co_mun, "name": nm_mun, "109": "-", "216": "-", "214": "-"}
            munis[co_mun][var_code] = value if value and value != "..." and value != "-" else "-"

        with open(dest, "w", encoding="utf-8", newline="") as f:
            # Write header lines to match original format (skip=2 in R means skip 2 lines)
            f.write(f'"Tabela 1612 - Área plantada, área colhida, quantidade produzida das lavouras temporárias"\n')
            f.write(f'"Cód.","Município","Produto das lavouras temporárias","Ano","Variável"\n')
            f.write(f'"Cód.","Município","Produto das lavouras temporárias","Ano","Área plantada (Hectares)","Área colhida (Hectares)","Quantidade produzida (Toneladas)"\n')
            for m in munis.values():
                f.write(f'"{m["code"]}","{m["name"]}","Soja (em grão)","{year}","{m["109"]}","{m["216"]}","{m["214"]}"\n')

        log(f"  Saved {len(munis)} municipalities to {dest.name}")
        time.sleep(1)  # Be nice to SIDRA API


# ===========================================================================
# 4. IBGE SIDRA - Population Estimates (Table 6579)
# ===========================================================================

def download_sidra_population(years, dry_run=False):
    """
    Download IBGE SIDRA Table 6579 - population estimates.
    Note: Table 6579 only goes through 2021. For 2022+ we try Table 9514 (Census 2022).

    Original format (read with read.csv, skip=1):
      "Cód.","Município","Ano","Variável",""
      "1100015","Alta Floresta D'Oeste (RO)","2001","População residente estimada (Pessoas)","26919"

    API URL:
      https://apisidra.ibge.gov.br/values/t/6579/n6/all/v/9324/p/{year}
    """
    log("=" * 60)
    log("IBGE SIDRA - Population Estimates")
    log("=" * 60)

    for year in years:
        dest = RAW_DIR / "00" / "IBGE_population" / f"Population_tabela6579_IBGE_{year}.csv"
        if dry_run:
            log(f"  Would download SIDRA population for {year} -> {dest}")
            continue

        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        # Table 6579 goes through 2021; 2022 via table 9514; 2023+ not in SIDRA
        if year <= 2021:
            table = "6579"
            var = "9324"
            var_name = "População residente estimada (Pessoas)"
        elif year == 2022:
            table = "9514"
            var = "allxp"
            var_name = "População residente (Pessoas)"
        else:
            # 2023+ population estimates not available in SIDRA
            # They are published as separate files on IBGE website
            warn(f"  Population data for {year} is not available in SIDRA API.")
            warn(f"  Download manually from: https://www.ibge.gov.br/estatisticas/sociais/populacao/9103-estimativas-de-populacao.html")
            note_dest = RAW_DIR / "00" / "IBGE_population" / f"Population_{year}_MANUAL_DOWNLOAD_NEEDED.txt"
            note_dest.parent.mkdir(parents=True, exist_ok=True)
            with open(note_dest, "w") as f:
                f.write(f"Population estimates for {year} are not in SIDRA.\n")
                f.write(f"Download from: https://www.ibge.gov.br/estatisticas/sociais/populacao/9103-estimativas-de-populacao.html\n")
                f.write(f"Save as: Population_tabela6579_IBGE_{year}.csv in the same format as earlier years.\n")
            continue

        url = f"https://apisidra.ibge.gov.br/values/t/{table}/n6/all/v/{var}/p/{year}"
        log(f"  Fetching SIDRA table {table} for year {year}...")
        data = download_json(url, timeout=180)
        if not data or len(data) <= 1:
            warn(f"  No data returned for table {table} year {year}.")
            error(f"  FAILED to download population data for {year}")
            continue

        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="") as f:
            f.write(f'"Tabela - População residente estimada"\n')
            f.write(f'"Cód.","Município","Ano","Variável",""\n')
            for row in data[1:]:
                co_mun = row.get("D1C") or row.get("Município (Código)")
                nm_mun = row.get("D1N") or row.get("Município")
                value = row.get("V") or row.get("Valor") or ""
                f.write(f'"{co_mun}","{nm_mun}","{year}","{var_name}","{value}"\n')

        log(f"  Saved population data for {year} to {dest.name}")
        time.sleep(1)


# ===========================================================================
# 5. IBGE SIDRA - Livestock (Table 3939)
# ===========================================================================

def download_sidra_livestock(years, dry_run=False):
    """
    Download IBGE SIDRA Table 3939 - livestock headcounts by municipality.

    FIX (2026-07): the previous version fetched one herd type at a time using a
    hardcoded c79 code list in which "Galináceos - total" (2679) was wrong, so
    that column came back empty for every year this script produced (2014+),
    breaking broiler counts -> negative cake feed -> cake re-export ridge fallback.
    2010-2013 were Stefan's original web-interface extracts and are unaffected.

    This version issues ONE request per year with c79/all and maps categories by
    NAME (field D3N) rather than by a guessed code, so it is robust to SIDRA's
    code scheme (some poultry sub-categories carry 5-digit codes like 32xxx).

    Original format (read with read.csv2, skip=4):
      Semicolon-separated with columns:
      "Nível";"Cód.";"Município";"Bovino";"Bubalino";"Equino";"Suíno - total";...

    API URL:
      https://apisidra.ibge.gov.br/values/t/3939/n6/all/v/105/p/{year}/c79/all
      v/105 = Efetivo dos rebanhos (Cabeças);  c79/all = every herd type
    """
    log("=" * 60)
    log("IBGE SIDRA Table 3939 - Livestock")
    log("=" * 60)

    # Herd types (SIDRA table 3939, classification c79). Codes VERIFIED against the
    # live API 2026-07 -- the previous list was wrong for every type except Bovino
    # (e.g. it fetched Equino under "Bubalino", quail under "Galináceos-galinhas",
    # and a nonexistent 2679 for "Galináceos-total"), scrambling all 2014+ files.
    # Newer sub-categories carry 5-digit codes (32xxx). One request PER TYPE across
    # all munis (n6/all + c79/all is rejected 400 as too large); values are placed
    # by the RETURNED name (D4N), so a stale code self-corrects to its true column.
    livestock_types = [
        ("2670",  "Bovino"),
        ("2675",  "Bubalino"),
        ("2672",  "Equino"),
        ("32794", "Suíno - total"),
        ("32795", "Suíno - matrizes de suínos"),
        ("2681",  "Caprino"),
        ("2677",  "Ovino"),
        ("32796", "Galináceos - total"),
        ("32793", "Galináceos - galinhas"),
        ("2680",  "Codornas"),
    ]
    col_names = [t[1] for t in livestock_types]

    for year in years:
        dest = RAW_DIR / "00" / "IBGE_livestock" / f"Livestock_{year}_tabela3939_IBGE.csv"
        if dry_run:
            log(f"  Would download SIDRA 3939 for {year} -> {dest}")
            continue

        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        # SIDRA dimension keys: D1=Município, D2=Variável, D3=Ano, D4=Tipo de rebanho.
        # The herd-type NAME is D4N (NOT D3, which is the year).
        munis = {}
        failed = False
        for type_code, type_name in livestock_types:
            url = f"https://apisidra.ibge.gov.br/values/t/3939/n6/all/v/105/p/{year}/c79/{type_code}"
            log(f"  Fetching SIDRA 3939 for year {year}, {type_name} (c79/{type_code})...")
            data = download_json(url, timeout=300)
            if not data:
                error(f"  Failed to download SIDRA 3939 for {year}, {type_name}")
                failed = True
                break
            for row in data[1:]:  # data[0] is the header row
                co_mun = row.get("D1C") or row.get("Município (Código)")
                nm_mun = row.get("D1N") or row.get("Município")
                cat    = row.get("D4N") or type_name   # returned herd-type NAME
                value  = row.get("V") or row.get("Valor") or "-"
                if value in ("...", "..", "-", "", None):
                    value = "-"
                if co_mun not in munis:
                    munis[co_mun] = {"code": co_mun, "name": nm_mun,
                                     **{c: "-" for c in col_names}}
                if cat in munis[co_mun]:
                    munis[co_mun][cat] = value
            time.sleep(1)  # be nice between requests

        if failed:
            continue

        # Guard: fail loudly if the historically-broken column is still empty.
        n_gal = sum(1 for m in munis.values()
                    if m["Galináceos - total"] not in ("-", None))
        log(f"  {year}: {len(munis)} munis; 'Galináceos - total' populated in {n_gal}")
        if n_gal == 0:
            error(f"  {year}: 'Galináceos - total' STILL EMPTY -- inspect c79 names (D4N) in the API response")

        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="") as f:
            # Match original format: 4 header lines (skip=4 in R), semicolon-separated
            f.write(f'"Tabela 3939 - Efetivo dos rebanhos, por tipo de rebanho"\n')
            f.write(f'"Variável - Efetivo dos rebanhos (Cabeças)"\n')
            f.write(f'"Nível";"Cód.";"Município";"Ano x Tipo de rebanho"\n')
            f.write(f'"Nível";"Cód.";"Município";"{year}"\n')
            hdr = ";".join([f'"{c}"' for c in col_names])
            f.write(f'"Nível";"Cód.";"Município";{hdr}\n')
            for m in munis.values():
                vals = ";".join([f'"{m[c]}"' for c in col_names])
                f.write(f'"MU";"{m["code"]}";"{m["name"]}";{vals}\n')

        log(f"  Saved {len(munis)} municipalities to {dest.name}")
        time.sleep(1)


# ===========================================================================
# 6. IBGE SIDRA - Milked Cows (Table 94)
# ===========================================================================

def download_sidra_milkcows(years, dry_run=False):
    """
    Download IBGE SIDRA Table 94 - milked cows by municipality.

    Original format (read with read.csv2, skip=3):
      "Nível";"Cód.";"Município";"2013"
      "MU";"1100015";"Alta Floresta D'Oeste (RO)";"6691"

    API URL:
      https://apisidra.ibge.gov.br/values/t/94/n6/all/v/106/p/{year}
      v/106 = Vacas ordenhadas (Cabeças)
    """
    log("=" * 60)
    log("IBGE SIDRA Table 94 - Milked Cows")
    log("=" * 60)

    for year in years:
        dest = RAW_DIR / "00" / "IBGE_milkcows" / f"MilkCows_{year}_tabela94_IBGE.csv"
        if dry_run:
            log(f"  Would download SIDRA 94 for {year} -> {dest}")
            continue

        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        url = f"https://apisidra.ibge.gov.br/values/t/94/n6/all/v/allxp/p/{year}"
        log(f"  Fetching SIDRA 94 for year {year}...")
        data = download_json(url, timeout=180)
        if not data:
            error(f"  Failed to download SIDRA 94 for {year}")
            continue

        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="") as f:
            # Match original format: 3 header lines (skip=3 in R), semicolon-separated
            f.write(f'"Tabela 94 - Vacas ordenhadas"\n')
            f.write(f'"Variável - Vacas ordenhadas (Cabeças)"\n')
            f.write(f'"Nível";"Cód.";"Município";"Ano"\n')
            f.write(f'"Nível";"Cód.";"Município";"{year}"\n')
            for row in data[1:]:
                co_mun = row.get("D1C") or row.get("Município (Código)")
                nm_mun = row.get("D1N") or row.get("Município")
                value = row.get("V") or row.get("Valor") or "-"
                if value in ("...", "", None):
                    value = "-"
                f.write(f'"MU";"{co_mun}";"{nm_mun}";"{value}"\n')

        log(f"  Saved milkcows data for {year} to {dest.name}")
        time.sleep(1)


# ===========================================================================
# 7. FAOSTAT - Food Balance Sheets (Commodity Balance Sheet for soy)
# ===========================================================================

def download_faostat_cbs(years, dry_run=False):
    """
    Download FAO Food Balance Sheet data for Brazilian soy products.

    Original format: Excel file CBS_SOY_2013_FAO.xlsx with structure:
      Row 1: None, None, 2013, 2013, 2013
      Row 2: None, None, "Soyabean Cake", "Soyabean Oil", "Soyabeans"
      Row 3: None, None, "Value (tonnes)", "Value (tonnes)", "Value (tonnes)"
      Rows 4+: "Brazil", element_name, value, value, value

    FAOSTAT API:
      https://fenixservices.fao.org/faostat/api/v1/en/data/FBS
      area=21 (Brazil), item=2555,2571,2590, element=all

    Note: FBS data typically available through 2022 only.
    """
    log("=" * 60)
    log("FAOSTAT Food Balance Sheets - Brazilian Soy")
    log("=" * 60)

    # FAOSTAT item codes for FBS domain
    # 2555 = Soyabeans, 2571 = Soyabean Oil, 2590 = Soyabean Cake
    # Element codes: 511=Domestic supply, 5511=Production, 5611=Import,
    # 5911=Export, 5141=Food, 5521=Feed, 5527=Seed, 5154=Other uses,
    # 5023=Processing, 5071=Stock Variation

    elements_order = [
        ("Domestic supply quantity", "511"),
        ("Production", "5511"),
        ("Export Quantity", "5911"),
        ("Import Quantity", "5611"),
        ("Food supply quantity (tonnes)", "5141"),
        ("Feed", "5521"),
        ("Seed", "5527"),
        ("Other uses", "5154"),
        ("Processing", "5023"),
        ("Stock Variation", "5071"),
    ]

    # Step 1: Download bulk FBS file (covers all years at once)
    bulk_zip = RAW_DIR / "00" / "FAO_CBS" / "_faostat_fbs_bulk.zip"
    bulk_csv = RAW_DIR / "00" / "FAO_CBS" / "_faostat_fbs_bulk.csv"

    if not bulk_csv.exists():
        bulk_url = "https://bulks-faostat.fao.org/production/FoodBalanceSheets_E_All_Data_(Normalized).zip"
        if dry_run:
            log(f"  Would download FAOSTAT FBS bulk -> {bulk_zip}")
            for year in years:
                log(f"  Would extract CBS for {year}")
            return

        log(f"  Downloading FAOSTAT FBS bulk file (~55 MB)...")
        if download(bulk_url, bulk_zip, timeout=300):
            # Extract the CSV from the zip
            import zipfile
            with zipfile.ZipFile(bulk_zip, 'r') as zf:
                csv_names = [n for n in zf.namelist() if n.endswith('.csv')]
                if csv_names:
                    log(f"  Extracting {csv_names[0]}...")
                    with zf.open(csv_names[0]) as src, open(bulk_csv, 'wb') as dst:
                        dst.write(src.read())
                    log(f"  Extracted to {bulk_csv.name}")
            # Clean up zip
            bulk_zip.unlink(missing_ok=True)
        else:
            error("  Failed to download FAOSTAT FBS bulk file")
            return
    else:
        log(f"  Using existing bulk FBS file: {bulk_csv.name}")

    if dry_run:
        return

    # Step 2: Parse the bulk CSV and extract Brazil soy data per year
    # CSV columns: Area Code,Area,Item Code,Item,Element Code,Element,Year Code,Year,Unit,Value,Flag,Flag Description
    # Items: 2555=Soyabeans, 2571=Soyabean Oil, 2590=Soyabean Cake
    # Area: 21=Brazil
    log(f"  Parsing bulk FBS CSV for Brazil soy data...")
    fbs_data = {}  # {year: {item_code: {element_code: value}}}
    with open(bulk_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            area_code = row.get("Area Code", row.get("Area Code (M49)", ""))
            item_code = row.get("Item Code", row.get("Item Code (FBS)", ""))
            if str(area_code) not in ("21", "'21"):  # Brazil
                continue
            if str(item_code) not in ("2555", "2571", "2590"):
                continue
            yr = int(row.get("Year", 0))
            elem_code = str(row.get("Element Code", ""))
            value = row.get("Value", "")
            try:
                value = float(value) if value else None
            except (ValueError, TypeError):
                value = None

            if yr not in fbs_data:
                fbs_data[yr] = {}
            if item_code not in fbs_data[yr]:
                fbs_data[yr][item_code] = {}
            fbs_data[yr][item_code][elem_code] = value

    log(f"  Found FBS data for years: {sorted(fbs_data.keys())}")

    # Step 3: Write per-year Excel files
    try:
        import openpyxl
    except ImportError:
        error("  openpyxl not available - cannot write Excel. Install with: pip3 install openpyxl")
        return

    for year in years:
        dest = RAW_DIR / "00" / "FAO_CBS" / f"CBS_SOY_{year}_FAO.xlsx"
        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        if year not in fbs_data:
            warn(f"  No FAOSTAT FBS data available for {year}")
            note_dest = RAW_DIR / "00" / "FAO_CBS" / f"CBS_SOY_{year}_FAO_NOT_AVAILABLE.txt"
            note_dest.parent.mkdir(parents=True, exist_ok=True)
            with open(note_dest, "w") as f:
                f.write(f"FAOSTAT Food Balance Sheet data for year {year} is not yet available.\n")
                f.write(f"Latest available year is typically 2022.\n")
                f.write(f"Consider using CONAB or USDA estimates as proxy.\n")
            continue

        vals = fbs_data[year]
        wb = openpyxl.Workbook()
        ws = wb.active

        # Header rows matching original format
        ws.append([None, None, year, year, year])
        ws.append([None, None, "Soyabean Cake", "Soyabean Oil", "Soyabeans"])
        ws.append([None, None, "Value (tonnes)", "Value (tonnes)", "Value (tonnes)"])

        # Data rows: columns are cake(2590), oil(2571), beans(2555)
        for elem_name, elem_code in elements_order:
            cake_val = vals.get("2590", {}).get(elem_code)
            oil_val = vals.get("2571", {}).get(elem_code)
            bean_val = vals.get("2555", {}).get(elem_code)
            ws.append(["Brazil", elem_name, cake_val, oil_val, bean_val])

        # Footer
        ws.append([None, None, None, None, None])
        ws.append([None, "https://www.fao.org/faostat/en/#data/FBS", None, None, None])

        dest.parent.mkdir(parents=True, exist_ok=True)
        wb.save(dest)
        log(f"  Saved CBS data for {year} to {dest.name}")


# ===========================================================================
# 8. FAOSTAT - Detailed Trade Matrix (bilateral soy trade)
# ===========================================================================

def download_faostat_trade(years, dry_run=False):
    """
    Download FAOSTAT Detailed Trade Matrix for Brazil soy products.

    Original format: CSV with columns:
      Domain Code,Domain,Reporter Country Code (FAO),Reporter Countries,
      Partner Country Code (ISO3),Partner Countries,Element Code,Element,
      Item Code,Item,Year Code,Year,Unit,Value,Flag,Flag Description

    Items: 236 (Soybeans), 237 (Oil, soybean), 238 (Cake, soybeans)
    Elements: 5910 (Export Quantity), 5610 (Import Quantity)
    """
    log("=" * 60)
    log("FAOSTAT Detailed Trade Matrix - Brazil Soy")
    log("=" * 60)

    soy_items = {"236", "237", "238"}  # Soybeans, Oil soybean, Cake soybeans
    fieldnames = [
        "Domain Code", "Domain", "Reporter Country Code (FAO)", "Reporter Countries",
        "Partner Country Code (ISO3)", "Partner Countries", "Element Code", "Element",
        "Item Code", "Item", "Year Code", "Year", "Unit", "Value", "Flag", "Flag Description"
    ]

    # Step 1: Download bulk trade matrix file
    bulk_zip = RAW_DIR / "04" / "_faostat_trade_bulk.zip"
    bulk_csv = RAW_DIR / "04" / "_faostat_trade_bulk.csv"

    if not bulk_csv.exists():
        bulk_url = "https://bulks-faostat.fao.org/production/Trade_DetailedTradeMatrix_E_All_Data_(Normalized).zip"
        if dry_run:
            log(f"  Would download FAOSTAT Trade bulk -> {bulk_zip}")
            for year in years:
                log(f"  Would extract trade for {year}")
            return

        log(f"  Downloading FAOSTAT Trade bulk file (~420 MB, this may take a while)...")
        if download(bulk_url, bulk_zip, timeout=600):
            import zipfile
            with zipfile.ZipFile(bulk_zip, 'r') as zf:
                csv_names = [n for n in zf.namelist() if n.endswith('.csv')]
                if csv_names:
                    log(f"  Extracting {csv_names[0]}...")
                    with zf.open(csv_names[0]) as src, open(bulk_csv, 'wb') as dst:
                        dst.write(src.read())
                    log(f"  Extracted to {bulk_csv.name}")
            bulk_zip.unlink(missing_ok=True)
        else:
            error("  Failed to download FAOSTAT Trade bulk file")
            return
    else:
        log(f"  Using existing bulk trade file: {bulk_csv.name}")

    if dry_run:
        return

    # Step 2: Parse bulk CSV, extracting only Brazil soy rows
    log(f"  Parsing bulk trade CSV for Brazil soy data (this may take a minute)...")
    trade_by_year = {}  # {year: [rows]}
    with open(bulk_csv, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            reporter_code = row.get("Reporter Country Code (FAO)", row.get("Reporter Country Code", ""))
            item_code = row.get("Item Code", "")
            if str(reporter_code) != "21":  # Brazil
                continue
            if str(item_code) not in soy_items:
                continue
            yr = int(row.get("Year", 0))
            if yr not in trade_by_year:
                trade_by_year[yr] = []
            # Normalize to expected format
            out_row = {
                "Domain Code": row.get("Domain Code", "TM"),
                "Domain": row.get("Domain", "Detailed trade matrix"),
                "Reporter Country Code (FAO)": reporter_code,
                "Reporter Countries": row.get("Reporter Countries", "Brazil"),
                "Partner Country Code (ISO3)": row.get("Partner Country Code (ISO3)", row.get("Partner Countries Code (ISO3)", "")),
                "Partner Countries": row.get("Partner Countries", ""),
                "Element Code": row.get("Element Code", ""),
                "Element": row.get("Element", ""),
                "Item Code": item_code,
                "Item": row.get("Item", ""),
                "Year Code": str(yr),
                "Year": str(yr),
                "Unit": row.get("Unit", "tonnes"),
                "Value": row.get("Value", ""),
                "Flag": row.get("Flag", ""),
                "Flag Description": row.get("Flag Description", ""),
            }
            trade_by_year[yr].append(out_row)

    log(f"  Found trade data for years: {sorted(trade_by_year.keys())}")

    # Step 3: Write per-year CSV files
    for year in years:
        dest = RAW_DIR / "04" / f"FAOSTAT_tradematrix_BRAsoy_{year}.csv"
        if dest.exists() and dest.stat().st_size > 0:
            log(f"  Already exists, skipping: {dest.name}")
            continue

        if year in trade_by_year and trade_by_year[year]:
            rows = trade_by_year[year]
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
                writer.writeheader()
                writer.writerows(rows)
            log(f"  Saved {len(rows)} trade records for {year} to {dest.name}")
        else:
            warn(f"  No FAOSTAT trade data available for {year}")
            note_dest = RAW_DIR / "04" / f"FAOSTAT_tradematrix_BRAsoy_{year}_NOT_AVAILABLE.txt"
            note_dest.parent.mkdir(parents=True, exist_ok=True)
            with open(note_dest, "w") as f:
                f.write(f"FAOSTAT trade matrix data for year {year} not yet available.\n")


# ===========================================================================
# 9. IBGE Municipality boundaries via direct download
# ===========================================================================

def download_municipality_boundaries(years, dry_run=False):
    """
    Download IBGE municipality boundary shapefiles.

    IBGE provides these at:
      https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/malhas_municipais/municipio_{year}/Brasil/BR/

    Alternative: use the geobr R/Python package (recommended for R pipeline).
    This function downloads the zip files; the R scripts can also use geobr.
    """
    log("=" * 60)
    log("IBGE Municipality Boundaries")
    log("=" * 60)
    log("  NOTE: Municipality boundaries are best downloaded via the geobr R package.")
    log("  In R: geobr::read_municipality(year = YEAR)")
    log("  This avoids format/path issues with IBGE's FTP structure.")
    log("")

    # We'll provide a helper R script instead of trying to navigate IBGE's FTP
    helper_script = RAW_DIR / "00" / "_scripts" / "download_geobr_boundaries.R"
    if dry_run:
        log(f"  Would create R helper script: {helper_script}")
        return

    helper_script.parent.mkdir(parents=True, exist_ok=True)
    with open(helper_script, "w") as f:
        f.write('# Helper script to download municipality boundaries using geobr\n')
        f.write('# Run this in R: source("data/raw/00/_scripts/download_geobr_boundaries.R")\n\n')
        f.write('if (!require("geobr")) install.packages("geobr")\n')
        f.write('if (!require("sf")) install.packages("sf")\n\n')
        f.write('library(geobr)\nlibrary(sf)\n\n')
        f.write(f'years <- {min(years)}:{max(years)}\n\n')
        f.write('dir.create("data/raw/00/IBGE_boundaries", recursive = TRUE, showWarnings = FALSE)\n\n')
        f.write('for (yr in years) {\n')
        f.write('  cat(sprintf("Downloading municipality boundaries for %d...\\n", yr))\n')
        f.write('  tryCatch({\n')
        f.write('    mun <- read_municipality(year = yr, showProgress = FALSE)\n')
        f.write('    out_file <- sprintf("data/raw/00/IBGE_boundaries/municipios_%d.gpkg", yr)\n')
        f.write('    st_write(mun, out_file, driver = "GPKG", delete_dsn = TRUE)\n')
        f.write('    cat(sprintf("  Saved: %s\\n", out_file))\n')
        f.write('  }, error = function(e) {\n')
        f.write('    cat(sprintf("  Failed for %d: %s\\n", yr, e$message))\n')
        f.write('  })\n')
        f.write('}\n')
    log(f"  Created R helper script: {helper_script}")


# ===========================================================================
# 10. IBGE Municipality code list (for GEO_MUN_XXXX_IBGE.xlsx)
# ===========================================================================

def download_municipality_codes(years, dry_run=False):
    """
    Download municipality code list from IBGE API.

    Original format (GEO_MUN_2013_IBGE.xlsx): Excel with columns:
      co_mun, nm_mun, co_state, nm_state

    IBGE API: https://servicodados.ibge.gov.br/api/v1/localidades/municipios
    Returns JSON with all municipalities.
    """
    log("=" * 60)
    log("IBGE Municipality Code List")
    log("=" * 60)

    # Municipality codes don't change much year to year, but we download once
    dest = RAW_DIR / "00" / "IBGE_municipalities" / "GEO_MUN_current_IBGE.xlsx"
    if dry_run:
        log(f"  Would download IBGE municipality codes -> {dest}")
        return

    if dest.exists() and dest.stat().st_size > 0:
        log(f"  Already exists, skipping: {dest.name}")
        return

    url = "https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado"
    log(f"  Fetching IBGE municipality list...")
    data = download_json(url, timeout=60)
    if not data:
        error("  Failed to download municipality codes")
        return

    try:
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(["co_mun", "nm_mun", "co_state", "nm_state"])

        for m in data:
            co_mun = m.get("municipio-id", m.get("id"))
            nm_mun = m.get("municipio-nome", m.get("nome", "")).upper()
            co_state = m.get("UF-id", "")
            nm_state = m.get("UF-sigla", "")

            # Try nested structure if flat keys don't work
            if not co_state and "microrregiao" in m:
                uf = m.get("microrregiao", {}).get("mesorregiao", {}).get("UF", {})
                co_state = uf.get("id", "")
                nm_state = uf.get("sigla", "")
            elif not co_state and "municipio" in m:
                pass  # already handled above

            ws.append([co_mun, nm_mun, co_state, nm_state])

        dest.parent.mkdir(parents=True, exist_ok=True)
        wb.save(dest)
        log(f"  Saved {len(data)} municipalities to {dest.name}")

        # Also create year-specific copies (symlinks or copies)
        for year in years:
            year_dest = RAW_DIR / "00" / "IBGE_municipalities" / f"GEO_MUN_{year}_IBGE.xlsx"
            if not year_dest.exists():
                import shutil
                shutil.copy2(dest, year_dest)
                log(f"  Copied to {year_dest.name}")

    except ImportError:
        error("  openpyxl not available - cannot write Excel")


# ===========================================================================
# MAIN
# ===========================================================================

def main():
    parser = argparse.ArgumentParser(description="Download data for soyprint model extension (2014-2025)")
    parser.add_argument("--years", nargs="+", type=int, default=YEARS,
                        help="Years to download (default: 2014-2025)")
    parser.add_argument("--only", nargs="+", type=str, default=None,
                        help="Only download specific sources: comex, comex_lookups, sidra_prod, sidra_pop, sidra_livestock, sidra_milkcows, faostat_cbs, faostat_trade, boundaries, mun_codes")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be downloaded without actually downloading")
    args = parser.parse_args()

    years = sorted(args.years)
    only = set(args.only) if args.only else None
    dry = args.dry_run

    log(f"Soyprint Data Download Script")
    log(f"Years: {min(years)}-{max(years)}")
    log(f"Output directory: {RAW_DIR}")
    if dry:
        log("DRY RUN - no files will be downloaded")
    log("")

    sources = {
        "comex": ("COMEX Trade Data", lambda: download_comex(years, dry)),
        "comex_lookups": ("COMEX Lookup Tables", lambda: download_comex_lookups(dry)),
        "sidra_prod": ("SIDRA Production", lambda: download_sidra_production(years, dry)),
        "sidra_pop": ("SIDRA Population", lambda: download_sidra_population(years, dry)),
        "sidra_livestock": ("SIDRA Livestock", lambda: download_sidra_livestock(years, dry)),
        "sidra_milkcows": ("SIDRA Milked Cows", lambda: download_sidra_milkcows(years, dry)),
        "faostat_cbs": ("FAOSTAT CBS", lambda: download_faostat_cbs(years, dry)),
        "faostat_trade": ("FAOSTAT Trade Matrix", lambda: download_faostat_trade(years, dry)),
        "boundaries": ("Municipality Boundaries", lambda: download_municipality_boundaries(years, dry)),
        "mun_codes": ("Municipality Codes", lambda: download_municipality_codes(years, dry)),
    }

    for key, (name, func) in sources.items():
        if only is None or key in only:
            try:
                func()
            except Exception as e:
                error(f"Failed to download {name}: {e}")
                import traceback
                traceback.print_exc()
            log("")

    # Summary of manual downloads needed
    log("=" * 60)
    log("MANUAL DOWNLOADS REQUIRED")
    log("=" * 60)
    log("")
    log("The following datasets cannot be fully automated and need manual download:")
    log("")
    log("1. ABIOVE Processing Facilities")
    log("   URL: https://abiove.org.br/estatisticas/")
    log("   Look for: 'Capacidade Instalada' spreadsheets")
    log("   Save as: data/raw/00/ABIOVE_processing/ABIOVE_raw_capacity_{YEAR}.xlsx")
    log("   Sheets needed: 'processing_MUN' and 'refining_bottling_MUN'")
    log("   Columns: co_mun, nm_mun, nm_state, proc_fac_act, proc_cap_act, ...")
    log("")
    log("2. ANP Biodiesel Capacity")
    log("   URL: https://www.gov.br/anp/pt-br/centrais-de-conteudo/publicacoes/anuario-estatistico/")
    log("   Look for: Table 2.6 in each annual yearbook")
    log("   Save as: data/raw/00/ANP_biodiesel/Biodiesel_capacity_{YEAR}_ANP.xlsx")
    log("   Sheets needed: 'capacity' (facility + m3/day) and 'materials' (soy share by region)")
    log("")
    log("3. IBGE POF (Soy Oil Consumption)")
    log("   URL: https://www.ibge.gov.br/estatisticas/sociais/educacao/9050-pesquisa-de-orcamentos-familiares.html")
    log("   Only POF 2017-2018 available. POF 2024-2025 expected in 2026.")
    log("   Save as: data/raw/00/IBGE_POF/POF_soy_oil_{YEAR}_IBGE.csv (reuse for all years, or interpolate)")
    log("")
    log("4. IBGE Grain Storage Facilities (point locations)")
    log("   URL: https://www.ibge.gov.br/estatisticas/economicas/agricultura-e-pecuaria/9199-pesquisa-de-estoques.html")
    log("   Aggregated data: https://sidra.ibge.gov.br/tabela/278")
    log("   Save as: data/raw/00/IBGE_storage/armazens_{YEAR}.shp")
    log("   Note: point-level facility data may require contacting IBGE directly")
    log("")
    log("5. FAO Gridded Livestock (GLW3) - STATIC, reuse from original")
    log("   URL: https://dataverse.harvard.edu/dataverse/glw")
    log("   These are 2010 reference year rasters. Reuse the existing files in data/raw/02/geo/FAO_gridded_livestock/")
    log("")
    log("6. FAO GLEAM Production System Raster - STATIC, reuse from original")
    log("   URL: https://www.fao.org/gleam/resources/en/")
    log("   Reuse existing: data/raw/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif")
    log("")
    log("7. FAO GLEAM Feed Ratios - STATIC, reuse from original")
    log("   Reuse existing: data/raw/03/Feed_ratios_FAO.xlsx")
    log("")
    log("8. IBGE Census Feedlot Cattle")
    log("   2006 Census: https://sidra.ibge.gov.br/tabela/919 (already have)")
    log("   2017 Census: https://sidra.ibge.gov.br/tabela/6911 (download manually)")
    log("   Save as: data/raw/02/FeedlotCattle_2017_tabela6911_IBGE.xlsx")
    log("")
    log("9. FABIO Bilateral Trade Data")
    log("   Pre-built (1986-2013): https://doi.org/10.5281/zenodo.2577066")
    log("   To extend: clone https://github.com/fineprint-global/fabio and rebuild with updated FAOSTAT data")
    log("   Save outputs to: data/fabio/trade/")
    log("")
    log("10. IBGE Localities (municipality capitals)")
    log("    URL: https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/localidades/")
    log("    2022 edition available. Save to: data/raw/00/IBGE_localities/")
    log("    Note: static reference data, can reuse 2010 version for all years")
    log("")
    log("=" * 60)
    log("DONE")
    log("=" * 60)


if __name__ == "__main__":
    main()
