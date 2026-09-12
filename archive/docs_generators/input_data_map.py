"""Build Excel mapping every input file per script to its current data source."""
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

wb = openpyxl.Workbook()
wb.remove(wb.active)

hdr_font = Font(bold=True, color="FFFFFF", size=10)
hdr_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
wrap = Alignment(wrap_text=True, vertical="top")
thin = Border(left=Side('thin'), right=Side('thin'), top=Side('thin'), bottom=Side('thin'))
green = PatternFill(start_color="C6EFCE", end_color="C6EFCE", fill_type="solid")
yellow = PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid")
red = PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid")
gray = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")

headers = ["Data Description", "Original Input File (2013 code)", "Current Data File(s)", "Source / URL", "Years Available", "Status", "Notes"]
col_widths = [30, 35, 40, 55, 18, 15, 40]

def make_sheet(name, rows):
    ws = wb.create_sheet(name)
    for c, h in enumerate(headers, 1):
        cell = ws.cell(row=1, column=c, value=h)
        cell.font = hdr_font; cell.fill = hdr_fill; cell.alignment = wrap; cell.border = thin
    for r, row in enumerate(rows, 2):
        for c, val in enumerate(row, 1):
            cell = ws.cell(row=r, column=c, value=val)
            cell.alignment = wrap; cell.border = thin
        # Color status column
        status_cell = ws.cell(row=r, column=6)
        s = str(status_cell.value or "").upper()
        if "DOWNLOADED" in s or "AVAILABLE" in s:
            status_cell.fill = green
        elif "REUSE" in s or "STATIC" in s:
            status_cell.fill = gray
        elif "MANUAL" in s or "CONTACT" in s:
            status_cell.fill = red
        elif "PARTIAL" in s or "GAP" in s:
            status_cell.fill = yellow
    for c, w in enumerate(col_widths, 1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(c)].width = w
    ws.auto_filter.ref = ws.dimensions
    ws.freeze_panes = "A2"

# ── Script 00 ──
make_sheet("00_data_preparation", [
    ["Municipality code list (IBGE)",
     "inputs/00/GEO_MUN_2013_IBGE_merged.xlsx",
     "inputs/00/GEO_MUN_2013_IBGE_merged.xlsx",
     "IBGE / geobr package\nhttps://servicodados.ibge.gov.br/api/v1/localidades/municipios",
     "2013 (reusable)",
     "REUSE 2013",
     "Codes rarely change. Could update via geobr or IBGE API."],

    ["Exports by municipality (COMEX)",
     "inputs/00/EXP_2013_MUN_COMEX.csv",
     "inputs/00/new/COMEX_exports/EXP_{YEAR}_MUN_COMEX.csv",
     "MDIC / COMEX Stat\nhttps://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/",
     "2000-2025",
     "DOWNLOADED",
     "Semicolon CSV. Direct URL per year. 26 years."],

    ["Imports by municipality (COMEX)",
     "inputs/00/IMP_2013_MUN_COMEX.csv",
     "inputs/00/new/COMEX_imports/IMP_{YEAR}_MUN_COMEX.csv",
     "MDIC / COMEX Stat\nhttps://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/",
     "2000-2025",
     "DOWNLOADED",
     "Same structure as exports. 26 years."],

    ["COMEX municipality lookup",
     "inputs/00/UF_MUN_COMEX.csv",
     "inputs/00/UF_MUN_COMEX.csv",
     "MDIC\nhttps://balanca.economia.gov.br/balanca/bd/tabelas/UF_MUN.csv",
     "current",
     "DOWNLOADED",
     "ISO-8859-1 encoding. Static lookup. 5571 rows."],

    ["COMEX country codes lookup",
     "inputs/00/PAIS_COMEX.csv",
     "inputs/00/PAIS_COMEX.csv",
     "MDIC\nhttps://balanca.economia.gov.br/balanca/bd/tabelas/PAIS.csv",
     "current",
     "DOWNLOADED",
     "ISO-8859-1 encoding. Static lookup. 282 rows."],

    ["Soybean production by municipality (IBGE PAM)",
     "inputs/00/Production_tabela1612_IBGE.csv",
     "inputs/00/new/IBGE_production/Production_tabela1612_IBGE_{YEAR}.csv",
     "IBGE SIDRA Table 1612\nhttps://sidra.ibge.gov.br/tabela/1612\nAPI: apisidra.ibge.gov.br",
     "2000-2024",
     "DOWNLOADED",
     "25 years. 2025 not yet published (~Sep 2026). read.csv(skip=2)."],

    ["Processing facilities (ABIOVE)",
     "inputs/00/Processing_facilities_2013_ABIOVE.xlsx",
     "inputs/00/Processing_facilities_2025_ABIOVE.xlsx",
     "ABIOVE\nhttps://abiove.org.br/abiove_content/Abiove/Pesquisa-de-Capacidade-Instalada_2025-2.xlsx",
     "2025 (survey)",
     "DOWNLOADED",
     "124 soy plants, 88 municipalities. Capacity weighted by 2013 per-plant data + ANP biodiesel proxy + state median fallback. Raw ABIOVE file in inputs/00/new/ABIOVE_processing/."],

    ["Population estimates (IBGE)",
     "inputs/00/Population_tabela6579_IBGE.csv",
     "inputs/00/new/IBGE_population/Population_tabela6579_IBGE_{YEAR}.csv\ninputs/00/new/IBGE_population/Population_tabela9514_IBGE_2022.csv (Census 2022)",
     "IBGE SIDRA Table 6579 (estimates 2001-2021, 2024-2025)\nTable 136 (Census 2000)\nTable 793 (Contagem 2007)\nTable 200 (Census 2010)\nTable 9514 (Census 2022)",
     "2000-2022, 2024-2025",
     "DOWNLOADED",
     "25 years. 2000/2010/2022=Census, 2007=Contagem, rest=estimates. 2023 gap: no IBGE estimate."],

    ["Livestock headcounts (IBGE PPM)",
     "inputs/00/Livestock_2013_tabela3939_IBGE.csv",
     "inputs/00/new/IBGE_livestock/Livestock_{YEAR}_tabela3939_IBGE.csv",
     "IBGE SIDRA Table 3939\nhttps://sidra.ibge.gov.br/tabela/3939\nAPI: apisidra.ibge.gov.br",
     "2000-2025",
     "DOWNLOADED",
     "26 years. Semicolon CSV, skip=4. 10 animal types per municipality."],

    ["Milked cows (IBGE PPM)",
     "inputs/00/MilkCows_2013_tabela94_IBGE.csv",
     "inputs/00/new/IBGE_milkcows/MilkCows_{YEAR}_tabela94_IBGE.csv",
     "IBGE SIDRA Table 94\nhttps://sidra.ibge.gov.br/tabela/94\nAPI: apisidra.ibge.gov.br",
     "2000-2024",
     "DOWNLOADED",
     "25 years. Semicolon CSV, skip=3."],

    ["Grain storage facilities (IBGE)",
     "inputs/00/geo/IBGE_logistic_network/armazens_2014.shp",
     "inputs/00/geo/IBGE_logistic_network/armazens_2014.shp",
     "IBGE Pesquisa de Estoques\nhttps://sidra.ibge.gov.br/tabela/278",
     "2014 (shapefile)",
     "REUSE 2014",
     "Point locations with CAP_TON. Table 278 has 2007-2025 semiannual data but API does not support municipality-level download. Web-only or CONAB SICARM."],

    ["Per-capita soy oil acquisition (POF)",
     "inputs/00/POF_soy_oil_2017_IBGE.xlsx",
     "inputs/00/new/IBGE_POF/POF_soy_oil_{2002,2008,2018}_IBGE.csv\ninputs/00/POF_soy_oil_2017_IBGE.xlsx (original)",
     "IBGE SIDRA Table 2393\nhttps://sidra.ibge.gov.br/tabela/2393",
     "2002-03, 2008-09, 2017-18",
     "DOWNLOADED",
     "3 POF editions (survey not annual). Per-capita soy oil acquisition (kg) by state. Declining trend: ~8kg (2002) -> ~6kg (2008) -> ~4kg (2018). Next: POF 2024-25 (~2026)."],

    ["Biodiesel capacity (ANP)",
     "inputs/00/Biodiesel_capacity_2013_ANP.xlsx",
     "inputs/00/new/ANP_biodiesel/ANP_painel/Biodiesel_DadosAbertos_CSV_Capacidade.csv\ninputs/00/new/ANP_biodiesel/ANP_biodiesel_t4-8_{2008-2011}.xls\ninputs/00/new/ANP_biodiesel/ANP_biodiesel_t4-9_{2012-2017,2023-2025}.xls",
     "ANP Panel Data (monthly, 2018+)\nhttps://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/pb-da-biodiesel.zip\nANP Yearbooks (2008-2017)\nhttps://www.gov.br/anp/pt-br/centrais-de-conteudo/publicacoes/anuario-estatistico/",
     "2008-2026",
     "DOWNLOADED",
     "Yearbooks 2008-2017 (per-plant capacity XLS). Panel CSV 2018-2026 (monthly by municipality). Pre-2008: program minimal. 2014 yearbook has no XLS table (PDF only)."],

    ["Municipality boundaries (IBGE)",
     "inputs/00/geo/GEO_MUN_2013_IBGE_merged.gpkg",
     "inputs/00/geo/boundaries/municipios_{YEAR}.gpkg",
     "IBGE / geobr R package\nhttps://ipeagit.github.io/geobr/",
     "2000-2022 (15 snapshots)",
     "DOWNLOADED",
     "15 boundary files via geobr: 2000(5431 mun), 2001(5561), 2005-2007(5564), 2010(5565), 2013-2022(5570). Major change in 2001 (+130 municipalities)."],

    ["Municipality capital locations (IBGE)",
     "inputs/00/geo/IBGE_localities/BR_Localidades_2010_v1.shx",
     "inputs/00/geo/IBGE_localities/BR_Localidades_2010_v1.shx",
     "IBGE\nhttps://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/localidades/",
     "2010 / 2022",
     "REUSE 2010",
     "Static reference. 2022 edition available but 2010 works fine."],
])

# ── Script 00_FAO ──
make_sheet("00_FAO_consistency", [
    ["FAO Commodity Balance Sheet (soy)",
     "inputs/00/CBS_SOY_2013_FAO.xlsx",
     "inputs/00/new/FAO_CBS/CBS_SOY_{YEAR}_FAO.xlsx",
     "FAOSTAT Food Balance Sheets\nhttps://www.fao.org/faostat/en/#data/FBS\nHistoric: bulks-faostat.fao.org/production/FoodBalanceSheetsHistoric_E_All_Data.zip",
     "2000-2023",
     "DOWNLOADED",
     "24 years. 2000-2013: from historic FBS bulk (cake DERIVED: processing×0.75). 2014-2023: from new FBS (cake actual). 2024+ not yet published by FAO."],

    ["SOY_MUN_00 (from script 00)",
     "outputs/00/SOY_MUN_00.rds",
     "outputs/00_{YEAR}/SOY_MUN_00.rds",
     "Output from script 00",
     "—",
     "PIPELINE OUTPUT",
     ""],
])

# ── Script 01 ──
make_sheet("01_consumption_processing", [
    ["CBS_SOY (from script 00_FAO)",
     "outputs/00/CBS_SOY.rds",
     "outputs/00_{YEAR}/CBS_SOY.rds",
     "Output from script 00_FAO",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["SOY_MUN_00 (from script 00)",
     "outputs/00/SOY_MUN_00.rds",
     "outputs/00_{YEAR}/SOY_MUN_00.rds",
     "Output from script 00",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["GEO_MUN_SOY_00 (from script 00)",
     "outputs/00/GEO_MUN_SOY_00.rds",
     "outputs/00_{YEAR}/GEO_MUN_SOY_00.rds",
     "Output from script 00",
     "—",
     "PIPELINE OUTPUT",
     ""],
])

# ── Script 02 ──
make_sheet("02_livestock_systems", [
    ["SOY_MUN_01 (from script 01)",
     "outputs/01/SOY_MUN_01.rds",
     "outputs/01_{YEAR}/SOY_MUN_01.rds",
     "Output from script 01",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["GEO_MUN_SOY_01 (from script 01)",
     "outputs/01/GEO_MUN_SOY_01.rds",
     "outputs/01_{YEAR}/GEO_MUN_SOY_01.rds",
     "Output from script 01",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["Chicken density — extensive (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/06_ChExt_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\nhttps://dataverse.harvard.edu/dataverse/glw\ndoi:10.7910/DVN/SUFASB",
     "2010 (static)",
     "STATIC — already in project",
     "Used to compute production system shares per municipality. Reuse for all years."],
    ["Chicken density — intensive (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/07_ChInt_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/SUFASB",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Pig density — extensive (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/8_PgExt_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/33N0JG",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Pig density — intensive (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/9_PgInt_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/33N0JG",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Pig density — industrial (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/10_PgInd_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/33N0JG",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Cattle density (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/5_Ct_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/GIVQ75",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Buffalo density (FAO GLW3)",
     "inputs/02/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif",
     "inputs/02/geo/FAO_gridded_livestock/5_Bf_2010_Da.tif",
     "FAO GLW3 / Harvard Dataverse\ndoi:10.7910/DVN/5U8MWI",
     "2010 (static)",
     "STATIC — already in project",
     ""],
    ["Ruminant production systems (FAO GLEAM)",
     "inputs/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif",
     "inputs/02/geo/FAO_gridded_livestock/glps_gleam_61113_10km.tif",
     "FAO GLEAM\nhttps://data.apps.fao.org/catalog/dataset/global-livestock-environmental-assessment-model-gleam-production",
     "~2015 (static)",
     "STATIC — already in project",
     "15 production system classes at ~10km resolution."],
    ["Feedlot cattle (IBGE Census 2006)",
     "inputs/02/FeedlotCattle_2006_tabela919_IBGE.xlsx",
     "inputs/02/FeedlotCattle_2006_tabela919_IBGE.xlsx",
     "IBGE SIDRA Table 919 (Census 2006)\nhttps://sidra.ibge.gov.br/tabela/919\n2017 Census: Table 6911",
     "2006 (census)\n2017 available",
     "REUSE 2006 + download 2017",
     "Census data only (2006, 2017). Script extrapolates to target year. Download 2017 Census Table 6911 for better extrapolation."],
])

# ── Script 03 ──
make_sheet("03_feed_use", [
    ["SOY_MUN_02 (from script 02)",
     "outputs/02/SOY_MUN_02.rds",
     "outputs/02_{YEAR}/SOY_MUN_02.rds",
     "Output from script 02",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["GEO_MUN_SOY_02 (from script 02)",
     "outputs/02/GEO_MUN_SOY_02.rds",
     "outputs/02_{YEAR}/GEO_MUN_SOY_02.rds",
     "Output from script 02",
     "—",
     "PIPELINE OUTPUT",
     ""],
    ["Feed ratios by livestock system (FAO GLEAM)",
     "inputs/03/Feed_ratios_FAO.xlsx",
     "inputs/03/Feed_ratios_FAO.xlsx",
     "FAO GLEAM 3.0 model documentation\nhttps://www.fao.org/gleam/resources/en/",
     "~2015 (static)",
     "STATIC — already in project",
     "Sheet 2: DM intake, % soybean, % soy cake per animal per year. Static parameters."],
    ["CBS_SOY (from script 00_FAO)",
     "outputs/00/CBS_SOY.rds",
     "outputs/00_{YEAR}/CBS_SOY.rds",
     "Output from script 00_FAO",
     "—",
     "PIPELINE OUTPUT",
     "Used to rescale feed totals to FAO national values."],
])

# ── Script 04 ──
make_sheet("04_trade_harmonization", [
    ["EXP_MUN_SOY_00 (from script 00)",
     "outputs/00/EXP_MUN_SOY_00.rds",
     "outputs/00_{YEAR}/EXP_MUN_SOY_00.rds",
     "Output from script 00", "—", "PIPELINE OUTPUT", ""],
    ["IMP_MUN_SOY_00 (from script 00)",
     "outputs/00/IMP_MUN_SOY_00.rds",
     "outputs/00_{YEAR}/IMP_MUN_SOY_00.rds",
     "Output from script 00", "—", "PIPELINE OUTPUT", ""],
    ["FABIO bilateral trade — import side",
     "inputs/04/FABIO/btd_bal.rds",
     "inputs/04/FABIO/btd_bal.rds",
     "FABIO v1.1 (Zenodo)\nhttps://doi.org/10.5281/zenodo.2577066\nOr rebuild from GitHub: github.com/fineprint-global/fabio",
     "1986-2013 (v1.1)\n2010-2023 (v2, rebuild)",
     "AVAILABLE (2013)\nCONTACT for 2014+",
     "Pre-built only to 2013. For 2014+: contact Martin Bruckner (martin.bruckner@wu.ac.at) for v2 or rebuild FABIO."],
    ["FABIO bilateral trade — export side (v1)",
     "inputs/04/FABIO/FABIO_exp/v1/btd_bal.rds",
     "inputs/04/FABIO/FABIO_exp/v1/btd_bal.rds",
     "Same as above", "Same", "Same", ""],
    ["FABIO bilateral trade — export side (pure)",
     "inputs/04/FABIO/FABIO_exp/pure/btd_bal.rds",
     "inputs/04/FABIO/FABIO_exp/pure/btd_bal.rds",
     "Same as above", "Same", "Same", ""],
    ["FABIO CBS (commodity balance sheets)",
     "inputs/04/FABIO/FABIO_exp/v1/cbs_full.rds",
     "inputs/04/FABIO/FABIO_exp/v1/cbs_full.rds",
     "Same as above", "Same", "Same", ""],
    ["FAOSTAT trade matrix (Brazil soy)",
     "inputs/04/FABIO/FAOSTAT_tradematrix_BRAsoy.csv",
     "inputs/04/FAOSTAT_tradematrix_BRAsoy_{YEAR}.csv\ninputs/04/FAOSTAT_tradematrix_BRAsoy_ALL.csv",
     "FAOSTAT Detailed Trade Matrix\nhttps://www.fao.org/faostat/en/#data/TM\nBulk: bulks-faostat.fao.org",
     "2014-2024",
     "DOWNLOADED",
     "Items: 236 (soybeans), 237 (oil), 238 (cake). Brazil=area 21."],
    ["COMEX country codes (for script 04)",
     "inputs/04/PAIS_COMEX.csv",
     "inputs/04/PAIS_COMEX.csv",
     "MDIC", "current", "AVAILABLE", "Same as inputs/00/ version"],
    ["FAO regions lookup",
     "inputs/04/FABIO/FAO_regions_full.csv",
     "inputs/04/FABIO/FAO_regions_full.csv",
     "FABIO repo: inst/regions_full.csv", "static", "AVAILABLE", ""],
    ["FABIO regions lookup",
     "inputs/04/FABIO/FABIO_regions.xlsx",
     "inputs/04/FABIO/FABIO_regions.xlsx",
     "FABIO repo", "static", "AVAILABLE", ""],
])

# ── Script 05 ──
make_sheet("05_balancing", [
    ["SOY_MUN_03 (from script 03)",
     "outputs/03/SOY_MUN_03.rds",
     "outputs/03_{YEAR}/SOY_MUN_03.rds",
     "Output from script 03", "—", "PIPELINE OUTPUT", ""],
    ["GEO_MUN_SOY_03 (from script 03)",
     "outputs/03/GEO_MUN_SOY_03.rds",
     "outputs/03_{YEAR}/GEO_MUN_SOY_03.rds",
     "Output from script 03", "—", "PIPELINE OUTPUT", ""],
    ["CBS_SOY (from script 00_FAO)",
     "outputs/00/CBS_SOY.rds",
     "outputs/00_{YEAR}/CBS_SOY.rds",
     "Output from script 00_FAO", "—", "PIPELINE OUTPUT", ""],
    ["EXP_MUN_SOY (from script 04)",
     "outputs/04/EXP_MUN_SOY.rds",
     "outputs/04_{YEAR}/EXP_MUN_SOY.rds",
     "Output from script 04", "—", "PIPELINE OUTPUT", ""],
    ["IMP_MUN_SOY (from script 04)",
     "outputs/04/IMP_MUN_SOY.rds",
     "outputs/04_{YEAR}/IMP_MUN_SOY.rds",
     "Output from script 04", "—", "PIPELINE OUTPUT", ""],
])

# ── Script 06 ──
make_sheet("06_transport_cost", [
    ["SOY_MUN_fin (from script 05)",
     "intermediate_data/SOY_MUN_fin.rds", "", "Output from script 05", "—", "PIPELINE OUTPUT", ""],
    ["GEO_MUN_SOY_fin (from script 05)",
     "intermediate_data/GEO_MUN_SOY_fin.rds", "", "Output from script 05", "—", "PIPELINE OUTPUT", ""],
    ["OSM road network shapefile",
     "input_data/geo/OSM_logistic_network/gis_osm_roads_free_1.shp",
     "NOT DOWNLOADED",
     "OpenStreetMap / Geofabrik\nhttps://download.geofabrik.de/south-america/brazil.html",
     "2014+ snapshots",
     "MANUAL DOWNLOAD",
     "Download Brazil shapefile from Geofabrik. ~700MB."],
    ["Waterways (DNIT)",
     "input_data/geo/DNIT_logistic_network/Hidrovias.shp",
     "NOT DOWNLOADED",
     "DNIT (Dept. Nacional de Infraestrutura de Transportes)\nhttps://www.gov.br/dnit/pt-br",
     "varies",
     "MANUAL DOWNLOAD",
     "Brazilian waterway network shapefile."],
    ["Ports (ANTAQ)",
     "input_data/geo/ANTAQ/IP.shp + 2013Carga*.txt",
     "NOT DOWNLOADED",
     "ANTAQ\nhttps://www.gov.br/antaq/pt-br",
     "varies",
     "MANUAL DOWNLOAD",
     "Port locations + cargo data. Multiple files."],
    ["Railway (ANTT)",
     "input_data/geo/ANTT/Linhas.shp + Estacoes.shp + train_stations_soy.gpkg",
     "NOT DOWNLOADED",
     "ANTT\nhttps://www.gov.br/antt/pt-br",
     "varies",
     "MANUAL DOWNLOAD",
     "Railway lines, stations, soy-specific stations."],
    ["Rail cargo data (ANTT)",
     "input_data/RailCargo_2006-21_ANTT.xls",
     "NOT DOWNLOADED",
     "ANTT", "2006-2021", "MANUAL DOWNLOAD", "Sheet per year."],
    ["MUN_capitals (from script 00)",
     "intermediate_data/MUN_capitals.rds", "", "Output from script 00", "—", "PIPELINE OUTPUT", ""],
])

# ── Scripts 12-19 ──
make_sheet("12-19_FABIO_MRIO", [
    ["FABIO btd_bal.rds (full bilateral trade, ALL commodities)",
     "input_data/FABIO/FABIO_exp/v1/btd_bal.rds",
     "FABIO_build/fabio/output/btd_bal.rds (after rebuild)",
     "FABIO v2 GitHub\nhttps://github.com/fineprint-global/fabio\nContact: martin.bruckner@wu.ac.at",
     "2010-2023 (v2)",
     "CONTACT / REBUILD",
     "Full MRIO needs ALL 124 commodities × 192 countries. Must rebuild FABIO or request pre-built from WU Vienna."],
    ["FABIO cbs_full.rds (commodity balance, ALL commodities)",
     "input_data/FABIO/FABIO_exp/v1/cbs_full.rds",
     "FABIO_build/fabio/output/cbs_full.rds (after rebuild)",
     "Same as above", "Same", "CONTACT / REBUILD", ""],
    ["FABIO items, regions, supply-shares, use, tcf files",
     "input_data/FABIO/inst/*.csv",
     "FABIO_build/fabio/inst/*.csv",
     "FABIO GitHub repo (already cloned)",
     "static",
     "AVAILABLE",
     "Cloned to FABIO_build/fabio/inst/. These are static config files."],
    ["FABIO live_tidy, prices_tidy",
     "input_data/FABIO/tidy/live_tidy.rds, prices_tidy.rds",
     "FABIO_build/fabio/data/tidy/ (after rebuild)",
     "Generated by FABIO pipeline step 01",
     "—",
     "REBUILD NEEDED",
     ""],
    ["FABIO-EXIOBASE hybrid concordance",
     "input_data/FABIO/FABIO_hybrid/fabio-exio_*.csv",
     "NOT DOWNLOADED",
     "FABIO-hybrid GitHub\nhttps://github.com/fineprint-global/fabio-hybrid",
     "static",
     "MANUAL DOWNLOAD",
     "Only needed for script 18 (hybridization with EXIOBASE)."],
    ["EXIOBASE Z matrix",
     "(loaded from /mnt/nfs_fineprint/ in original code)",
     "NOT DOWNLOADED",
     "EXIOBASE\nhttps://www.exiobase.eu/",
     "varies",
     "MANUAL DOWNLOAD",
     "Only needed for script 18. Large matrices."],
])

out = "/Users/elizavetaburiak/Desktop/work/wu/soybean/soyprint_liza's_update/input_data_map.xlsx"
wb.save(out)
print(f"Saved to: {out}")
