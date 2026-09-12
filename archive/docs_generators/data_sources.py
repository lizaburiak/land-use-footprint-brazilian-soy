import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

wb = openpyxl.Workbook()

# ── Sheet 1: DATA (main table) ──
ws = wb.active
ws.title = "data"

headers = ["#", "Dataset", "Input File(s)", "Pipeline Step", "Source Org",
           "Years Available", "Latest Year", "Programmatic Download?",
           "Download URL / API Endpoint", "Status for 2014-2025", "Notes"]

# Header styling
header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF", size=11)
wrap = Alignment(wrap_text=True, vertical="top")
thin_border = Border(
    left=Side(style='thin'), right=Side(style='thin'),
    top=Side(style='thin'), bottom=Side(style='thin')
)

for col, h in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = wrap
    cell.border = thin_border

rows = [
    [1, "COMEX Trade Data (Exports)",
     "EXP_{YEAR}_MUN.csv",
     "00", "MDIC / COMEX Stat",
     "1997-2026", "2025",
     "YES - Direct CSV per year",
     "https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/EXP_{YEAR}_MUN.csv",
     "FULLY AVAILABLE",
     "Replace {YEAR} with 2014, 2015, ..., 2025. Large files."],

    [2, "COMEX Trade Data (Imports)",
     "IMP_{YEAR}_MUN.csv",
     "00", "MDIC / COMEX Stat",
     "1997-2026", "2025",
     "YES - Direct CSV per year",
     "https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/IMP_{YEAR}_MUN.csv",
     "FULLY AVAILABLE",
     "Same structure as exports."],

    [3, "COMEX Lookup: Country Codes",
     "PAIS_COMEX.csv",
     "00", "MDIC / COMEX Stat",
     "Current", "2025",
     "YES - Direct CSV",
     "https://balanca.economia.gov.br/balanca/bd/tabelas/PAIS.csv",
     "AVAILABLE",
     "Also in TABELAS_AUXILIARES.xlsx"],

    [4, "COMEX Lookup: Municipality Codes",
     "UF_MUN_COMEX.csv",
     "00", "MDIC / COMEX Stat",
     "Current", "2025",
     "YES - Direct CSV",
     "https://balanca.economia.gov.br/balanca/bd/tabelas/UF_MUN.csv",
     "AVAILABLE",
     "Also in TABELAS_AUXILIARES.xlsx"],

    [5, "Soybean Production by Municipality",
     "Production_tabela1612_IBGE.csv",
     "00", "IBGE / SIDRA (PAM)",
     "1994-2024", "2024",
     "YES - SIDRA API + R sidrar / Python sidrapy",
     "https://sidra.ibge.gov.br/tabela/1612\nAPI: https://apisidra.ibge.gov.br/values/t/1612/n6/all/v/214,216,215/p/{YEAR}/c81/2713",
     "AVAILABLE (to 2024)",
     "2025 data expected ~Sep 2026. Variables: v/214=area planted, v/216=area harvested, v/215=production(t). c81/2713=soja."],

    [6, "Municipality Population Estimates",
     "Population_tabela6579_IBGE.csv",
     "00", "IBGE / SIDRA",
     "2001-2021 (Table 6579); 2022+ separate",
     "2025",
     "YES - SIDRA API for 2001-2021; separate download for 2022+",
     "https://sidra.ibge.gov.br/tabela/6579\n2022+: https://www.ibge.gov.br/estatisticas/sociais/populacao/9103-estimativas-de-populacao.html",
     "AVAILABLE (combine sources)",
     "Table 6579 stops at 2021. 2022 Census data in Table 9514. 2023-2025 from IBGE annual estimates (XLS)."],

    [7, "Livestock Headcounts by Municipality",
     "Livestock_2013_tabela3939_IBGE.csv",
     "00", "IBGE / SIDRA (PPM)",
     "1974-2024", "2024",
     "YES - SIDRA API",
     "https://sidra.ibge.gov.br/tabela/3939\nAPI: https://apisidra.ibge.gov.br/values/t/3939/n6/all/v/all/p/{YEAR}",
     "FULLY AVAILABLE",
     "Cattle, buffalo, horse, pig, goat, sheep, chicken, laying hens, quail. Annual."],

    [8, "Milked Cows by Municipality",
     "MilkCows_2013_tabela94_IBGE.csv",
     "00", "IBGE / SIDRA (PPM)",
     "1974-2024", "2024",
     "YES - SIDRA API",
     "https://sidra.ibge.gov.br/tabela/94\nAPI: https://apisidra.ibge.gov.br/values/t/94/n6/all/v/all/p/{YEAR}",
     "FULLY AVAILABLE",
     "Same PPM survey as Table 3939."],

    [9, "FAO Commodity Balance Sheet (Soy)",
     "CBS_SOY_{YEAR}_FAO.xlsx",
     "00", "FAO / FAOSTAT",
     "2010-2022 (new FBS); 1961-2013 (old)",
     "2022",
     "YES - FAOSTAT API + bulk download",
     "https://www.fao.org/faostat/en/#data/FBS\nBulk: https://bulks-faostat.fao.org/production/FoodBalanceSheets_E_All_Data_(Normalized).zip\nAPI: https://fenixservices.fao.org/faostat/api/v1/en/data/FBS",
     "GAP: 2023-2025 missing",
     "FBS latest year is 2022. For 2023-2025 may need SUA data or CONAB/USDA estimates as proxy."],

    [10, "ABIOVE Processing Facilities",
     "Processing_facilities_{YEAR}_ABIOVE.xlsx",
     "00", "ABIOVE",
     "Various years available", "2024",
     "PARTIAL - Excel downloads from website",
     "https://abiove.org.br/estatisticas/\nhttps://abiove.org.br/capacidade-instalada-da-industria-de-oleos-vegetais/",
     "AVAILABLE (manual download)",
     "Need crushing + refining capacity by municipality. Check 'Capacidade Instalada' section. May need manual extraction."],

    [11, "ANP Biodiesel Capacity",
     "Biodiesel_capacity_{YEAR}_ANP.xlsx",
     "00", "ANP",
     "Annual yearbooks", "2024",
     "PARTIAL - Excel/PDF from yearbooks",
     "https://www.gov.br/anp/pt-br/centrais-de-conteudo/publicacoes/anuario-estatistico/\nTable 2.6 in each yearbook",
     "AVAILABLE (manual download)",
     "Need facility-level daily capacity (m³/day) + regional soy feedstock share. Check Table 2.6 of each ANP Yearbook."],

    [12, "POF Soy Oil Acquisition",
     "POF_soy_oil_{YEAR}_IBGE.xlsx",
     "00", "IBGE / POF",
     "2002-03, 2008-09, 2017-18",
     "2017-18",
     "YES - Microdata ZIP download",
     "https://ftp.ibge.gov.br/Orcamentos_Familiares/\nhttps://www.ibge.gov.br/estatisticas/sociais/educacao/9050-pesquisa-de-orcamentos-familiares.html",
     "GAP: Not annual data",
     "Only 3 survey rounds exist. POF 2024-25 in field, results expected 2026. Must interpolate or hold constant between rounds."],

    [13, "Municipality Boundaries (Polygons)",
     "GEO_MUN_{YEAR}_IBGE_merged.gpkg",
     "00", "IBGE / geobr package",
     "Annual mesh updates", "2024",
     "YES - geobr R/Python package (1 line)",
     "R: geobr::read_municipality(year=YEAR)\nPython: geobr.read_municipality(year=YEAR)\nhttps://www.ibge.gov.br/geociencias/organizacao-do-territorio/malhas-territoriais/15774-malhas.html",
     "FULLY AVAILABLE",
     "geobr package is the easiest way. Also on geoftp.ibge.gov.br."],

    [14, "IBGE Localities (Capital Points)",
     "BR_Localidades_{YEAR}.shp",
     "00", "IBGE",
     "2010, 2022 editions", "2022",
     "YES - Direct download",
     "https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/localidades/",
     "AVAILABLE",
     "Static reference data. 2022 edition has 87,362 localities. Used to extract municipality capitals."],

    [15, "IBGE Grain Storage Facilities",
     "armazens_{YEAR}.shp",
     "00", "IBGE",
     "Semiannual since 2007", "2025",
     "PARTIAL - SIDRA Table 278 for aggregates; microdata may need request",
     "https://sidra.ibge.gov.br/tabela/278\nhttps://www.ibge.gov.br/estatisticas/economicas/agricultura-e-pecuaria/9199-pesquisa-de-estoques.html",
     "AVAILABLE (aggregates); point data may need IBGE contact",
     "SIDRA has municipality-level # of establishments + capacity. Individual facility coordinates may require special request."],

    [16, "FAO Gridded Livestock (GLW3)",
     "Various .tif files (chicken, pig, cattle, buffalo)",
     "02", "FAO / Harvard Dataverse",
     "Reference year 2010 (GLW3)", "2010",
     "YES - Direct GeoTIFF download",
     "https://dataverse.harvard.edu/dataverse/glw\nhttps://data.apps.fao.org/catalog/dataset/glw",
     "STATIC (2010 reference)",
     "Not updated annually. GLW4 or new AGLW dataset (2025 preprint, 1961-2021) may provide temporal updates."],

    [17, "FAO GLEAM Production System Raster",
     "glps_gleam_61113_10km.tif",
     "02", "FAO / GLEAM",
     "Reference year 2015", "2015",
     "PARTIAL - Download from FAO catalog",
     "https://data.apps.fao.org/catalog/dataset/global-livestock-environmental-assessment-model-gleam-production\nhttps://www.fao.org/gleam/resources/en/",
     "STATIC (2015 reference)",
     "Global ruminant production system classification at ~10km. Not updated annually."],

    [18, "Feedlot Cattle (Census)",
     "FeedlotCattle_{YEAR}_tabela919_IBGE.xlsx",
     "02", "IBGE / Agricultural Census",
     "2006 (Table 919), 2017 (Table 6911)", "2017",
     "YES - SIDRA API",
     "https://sidra.ibge.gov.br/tabela/919 (2006)\nhttps://sidra.ibge.gov.br/tabela/6911 (2017)",
     "GAP: Census years only (2006, 2017)",
     "No annual data. Must extrapolate between census years. 2017 Census has related tables (6911, 6914)."],

    [19, "FAO/GLEAM Feed Ratios",
     "Feed_ratios_FAO.xlsx",
     "03", "FAO / GLEAM",
     "Reference: GLEAM 3.0 (2015)", "2015",
     "NO - Extract from PDF/model docs",
     "https://www.fao.org/fileadmin/user_upload/gleam/docs/GLEAM_3.0_Model_description.pdf\nhttps://www.fao.org/gleam/en/",
     "STATIC (parameters)",
     "Feed ration coefficients (DMI, % soybean, % soy cake per animal). In GLEAM model documentation appendix. Can reuse original values."],

    [20, "FABIO Bilateral Trade Data",
     "btd_bal.rds, FABIO_exp/, etc.",
     "04", "FABIO / fineprint-global",
     "1986-2013 (v1.1); code rebuilds to 2022",
     "2013 (prebuilt); 2022 (rebuild)",
     "YES - Zenodo download; GitHub code to rebuild",
     "https://doi.org/10.5281/zenodo.2577066\nhttps://github.com/fineprint-global/fabio",
     "GAP: Must rebuild for 2014-2022; 2023-2025 limited by FAOSTAT",
     "Pre-built ends at 2013. Run FABIO GitHub code with updated FAOSTAT to extend. Limited by FAOSTAT data availability."],

    [21, "FAOSTAT Bilateral Trade Matrix (Brazil Soy)",
     "FAOSTAT_tradematrix_BRAsoy.csv",
     "04", "FAO / FAOSTAT",
     "1961-2023", "2023",
     "YES - FAOSTAT API + bulk download",
     "https://www.fao.org/faostat/en/#data/TM\nAPI: https://fenixservices.fao.org/faostat/api/v1/en/data/TM\nBulk: https://bulks-faostat.fao.org/production/Trade_DetailedTradeMatrix_E_All_Data_(Normalized).zip",
     "AVAILABLE to 2023; GAP 2024-2025",
     "Filter: area=21 (Brazil), items=236 (soybeans), 237 (soybean oil), 238 (soybean cake)."],

    [22, "IBGE Municipality Code List",
     "GEO_MUN_{YEAR}_IBGE_merged.xlsx",
     "00", "IBGE",
     "Updated annually", "2024",
     "YES - IBGE API / geobr package",
     "https://servicodados.ibge.gov.br/api/v1/localidades/municipios\nhttps://www.ibge.gov.br/explica/codigos-dos-municipios.php",
     "FULLY AVAILABLE",
     "Municipality codes, names, state codes. API returns JSON. geobr also provides this."],
]

for i, row in enumerate(rows, 2):
    for col, val in enumerate(row, 1):
        cell = ws.cell(row=i, column=col, value=val)
        cell.alignment = wrap
        cell.border = thin_border

# Color-code Status column
green_fill = PatternFill(start_color="C6EFCE", end_color="C6EFCE", fill_type="solid")
yellow_fill = PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid")
red_fill = PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid")
gray_fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")

for i in range(2, len(rows) + 2):
    cell = ws.cell(row=i, column=10)  # Status column
    val = str(cell.value).upper()
    if "FULLY AVAILABLE" in val or val == "AVAILABLE":
        cell.fill = green_fill
    elif "AVAILABLE" in val and "GAP" not in val:
        cell.fill = green_fill
    elif "GAP" in val:
        cell.fill = red_fill
    elif "STATIC" in val:
        cell.fill = gray_fill
    elif "AVAILABLE" in val:
        cell.fill = yellow_fill

# Column widths
col_widths = [4, 35, 30, 10, 20, 25, 10, 25, 60, 30, 50]
for i, w in enumerate(col_widths, 1):
    ws.column_dimensions[get_column_letter(i)].width = w

ws.auto_filter.ref = ws.dimensions
ws.freeze_panes = "A2"


# ── Sheet 2: DESCRIPTION ──
ws2 = wb.create_sheet("description")

desc_data = [
    ["OVERVIEW"],
    ["This file catalogs all data sources needed to extend the Brazilian soybean supply chain model (soyprint) from 2013 to 2025."],
    ["The original model was built for reference year 2013. This file identifies where to download updated data for years 2014-2025."],
    [""],
    ["PIPELINE STEPS"],
    ["00 - Data preparation: municipality-level production, trade, population, livestock, processing, storage, biodiesel"],
    ["01 - Consumption & processing estimation"],
    ["02 - Livestock system disaggregation (requires FAO gridded rasters)"],
    ["03 - Feed use estimation"],
    ["04 - Trade harmonization (FABIO + FAOSTAT bilateral trade)"],
    ["05 - Balancing"],
    [""],
    ["KEY DATA GAPS FOR 2014-2025"],
    ["1. FAOSTAT Food Balance Sheets: available only through 2022. Gap for 2023-2025."],
    ["2. IBGE Population (Table 6579): SIDRA stops at 2021. Must combine with 2022 Census + annual estimates."],
    ["3. POF soy oil consumption: not annual. Only 2017-18 round available. Must interpolate."],
    ["4. FABIO bilateral trade: pre-built only to 2013. Must rebuild using GitHub code + FAOSTAT."],
    ["5. IBGE Census feedlot cattle: only 2006 and 2017 census years. Must extrapolate."],
    ["6. FAO gridded livestock (GLW3) and GLEAM rasters: static snapshots (2010, 2015). Not annually updated."],
    ["7. FAOSTAT bilateral trade matrix: available through 2023. Gap for 2024-2025."],
    [""],
    ["DATASETS THAT CAN BE FULLY AUTOMATED (script download)"],
    ["- COMEX trade data (exports + imports): direct CSV URLs per year"],
    ["- COMEX lookup tables (PAIS, UF_MUN): direct CSV URLs"],
    ["- IBGE SIDRA tables (1612, 3939, 94, 6579): API calls"],
    ["- IBGE municipality boundaries: geobr package"],
    ["- FAOSTAT trade matrix: API + bulk download"],
    ["- FAOSTAT Food Balance Sheets: API + bulk download"],
    [""],
    ["DATASETS REQUIRING MANUAL DOWNLOAD"],
    ["- ABIOVE processing facilities (website, Excel files)"],
    ["- ANP biodiesel capacity (yearbook tables)"],
    ["- FAO GLW3 gridded livestock rasters (Harvard Dataverse)"],
    ["- FAO GLEAM production system raster"],
    ["- FAO GLEAM feed ratios (from PDF documentation)"],
    ["- IBGE POF microdata"],
    ["- IBGE grain storage facility point data (may need IBGE contact)"],
]

for i, row in enumerate(desc_data, 1):
    cell = ws2.cell(row=i, column=1, value=row[0])
    if row[0] in ["OVERVIEW", "PIPELINE STEPS", "KEY DATA GAPS FOR 2014-2025",
                   "DATASETS THAT CAN BE FULLY AUTOMATED (script download)",
                   "DATASETS REQUIRING MANUAL DOWNLOAD"]:
        cell.font = Font(bold=True, size=12)

ws2.column_dimensions['A'].width = 120


# ── Sheet 3: SOURCES (links) ──
ws3 = wb.create_sheet("sources")

src_headers = ["#", "Source Name", "URL", "Type", "Notes"]
for col, h in enumerate(src_headers, 1):
    cell = ws3.cell(row=1, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.border = thin_border

sources = [
    [1, "COMEX Stat (MDIC) - Raw Data", "https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/", "Trade data", "Direct CSV downloads by year"],
    [2, "COMEX Stat - Auxiliary Tables", "https://balanca.economia.gov.br/balanca/bd/tabelas/", "Lookup tables", "PAIS.csv, UF_MUN.csv"],
    [3, "COMEX Stat - API", "https://api-comexstat.mdic.gov.br/docs?ui=swagger", "API", "Swagger docs for REST API"],
    [4, "IBGE SIDRA - Table 1612 (Soy Production)", "https://sidra.ibge.gov.br/tabela/1612", "Production data", "PAM survey, annual"],
    [5, "IBGE SIDRA - Table 3939 (Livestock)", "https://sidra.ibge.gov.br/tabela/3939", "Livestock data", "PPM survey, annual"],
    [6, "IBGE SIDRA - Table 94 (Milked Cows)", "https://sidra.ibge.gov.br/tabela/94", "Livestock data", "PPM survey, annual"],
    [7, "IBGE SIDRA - Table 6579 (Population)", "https://sidra.ibge.gov.br/tabela/6579", "Population data", "Ends at 2021"],
    [8, "IBGE Population Estimates (2022+)", "https://www.ibge.gov.br/estatisticas/sociais/populacao/9103-estimativas-de-populacao.html", "Population data", "Annual XLS downloads"],
    [9, "IBGE SIDRA API Documentation", "https://servicodados.ibge.gov.br/api/docs/agregados?versao=3", "API docs", "For programmatic SIDRA access"],
    [10, "IBGE SIDRA - Table 919 (Feedlot Cattle 2006)", "https://sidra.ibge.gov.br/tabela/919", "Census data", "Agricultural Census 2006"],
    [11, "IBGE SIDRA - Table 6911 (Feedlot Cattle 2017)", "https://sidra.ibge.gov.br/tabela/6911", "Census data", "Agricultural Census 2017"],
    [12, "IBGE Municipal Boundaries (Malhas)", "https://www.ibge.gov.br/geociencias/organizacao-do-territorio/malhas-territoriais/15774-malhas.html", "Geospatial", "Shapefiles/GPKG"],
    [13, "geobr R/Python Package", "https://ipeagit.github.io/geobr/", "Geospatial tool", "Easiest way to get IBGE boundaries"],
    [14, "IBGE Localities", "https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/localidades/", "Geospatial", "Point locations of cities/villages"],
    [15, "IBGE Grain Storage (Table 278)", "https://sidra.ibge.gov.br/tabela/278", "Storage data", "Semiannual, aggregated by municipality"],
    [16, "IBGE POF 2017-2018", "https://www.ibge.gov.br/estatisticas/sociais/educacao/9050-pesquisa-de-orcamentos-familiares.html", "Consumption data", "Microdata available"],
    [17, "FAOSTAT Food Balance Sheets", "https://www.fao.org/faostat/en/#data/FBS", "Supply/use data", "Through 2022"],
    [18, "FAOSTAT Detailed Trade Matrix", "https://www.fao.org/faostat/en/#data/TM", "Trade data", "Through 2023"],
    [19, "FAOSTAT Bulk Downloads", "https://bulks-faostat.fao.org/production/", "Bulk data", "ZIP files for all FAOSTAT domains"],
    [20, "ABIOVE Statistics", "https://abiove.org.br/estatisticas/", "Processing data", "Installed capacity spreadsheets"],
    [21, "ANP Statistical Yearbook", "https://www.gov.br/anp/pt-br/centrais-de-conteudo/publicacoes/anuario-estatistico/", "Biodiesel data", "Annual yearbooks with facility tables"],
    [22, "FAO GLW3 (Harvard Dataverse)", "https://dataverse.harvard.edu/dataverse/glw", "Gridded livestock", "GeoTIFF rasters, 2010 reference"],
    [23, "FAO GLEAM Resources", "https://www.fao.org/gleam/resources/en/", "Livestock systems", "Production system rasters + feed ratios"],
    [24, "FAO GLEAM 3.0 Model Description (PDF)", "https://www.fao.org/fileadmin/user_upload/gleam/docs/GLEAM_3.0_Model_description.pdf", "Feed ratios", "Appendix tables with feed ration coefficients"],
    [25, "FABIO on Zenodo (v1.1)", "https://doi.org/10.5281/zenodo.2577066", "MRIO data", "Pre-built 1986-2013"],
    [26, "FABIO GitHub Repository", "https://github.com/fineprint-global/fabio", "MRIO code", "Code to rebuild FABIO from FAOSTAT"],
    [27, "IBGE Municipality API", "https://servicodados.ibge.gov.br/api/v1/localidades/municipios", "API", "Returns all municipality codes as JSON"],
]

for i, row in enumerate(sources, 2):
    for col, val in enumerate(row, 1):
        cell = ws3.cell(row=i, column=col, value=val)
        cell.alignment = wrap
        cell.border = thin_border

ws3.column_dimensions['A'].width = 4
ws3.column_dimensions['B'].width = 40
ws3.column_dimensions['C'].width = 80
ws3.column_dimensions['D'].width = 20
ws3.column_dimensions['E'].width = 40
ws3.auto_filter.ref = ws3.dimensions
ws3.freeze_panes = "A2"

# Save
out_path = "/Users/elizavetaburiak/Desktop/work/wu/soybean/soyprint_liza's_update/data_sources_for_extension.xlsx"
wb.save(out_path)
print(f"Saved to: {out_path}")
