#!/usr/bin/env Rscript
# build_release_parquet.R -- export the pipeline's per-year .rds artefacts to the
# release Parquet layer (Stage 5, part 1 of 2).
#
# Fact tables are hive-partitioned by year (<table>/year=<Y>/part-0.parquet);
# dimensions are written once, unpartitioned. code/build_release_db.py then loads
# this layer into SQLite. The split exists because only R can read .rds and only
# Python has sqlite3 here -- Parquet is the handover format.
#
# Usage: Rscript code/build_release_parquet.R [START] [END] [OUTDIR]
#   defaults: 2000 2020 data/generated/parquet
#
# Deviations from Figure 5, all deliberate and recorded in meta_provenance:
#   - footprint_animal_country / footprint_country / footprint_product are built per year
#     from step 20's {YEAR}_F_mass.rds, for whichever years that file exists; years without
#     it are simply absent. Rows below FP_MIN_HA hectares are dropped (see below), and
#     footprint_product.product_code carries a product_family column instead of the
#     Figure 5 FK to dim_commodity, which cannot hold for EXIOBASE codes.
#   - dim_municipality drops `biome` and `matopiba`: no source exists in this repo
#     (STRUCTURE.md:31,103 claim results/reference/mun_biome_lookup.csv, which is absent).
#   - dim_commodity drops `enduse_bucket`: not present in items.csv, no rule available.
#   - meta_build.duckdb_version -> sqlite_version (the release container is SQLite).

# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(arrow); library(sf); library(Matrix)
})

args   <- commandArgs(trailingOnly = TRUE)
START  <- if (length(args) >= 1) as.integer(args[1]) else 2000L
END    <- if (length(args) >= 2) as.integer(args[2]) else 2020L
OUTDIR <- if (length(args) >= 3) args[3] else file.path(DATA_DIR, "generated/parquet")
YEARS  <- START:END
OUT    <- function(...) file.path(OUTDIR, ...)
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

`%||%` <- function(a, b) if (is.null(a)) b else a
# This arrow build has no zstd; snappy is present everywhere and is the safe default.
PARQUET_CODEC <- if (arrow::codec_is_available("zstd")) "zstd" else "snappy"

outp <- function(step, year, file) sprintf(file.path(DATA_DIR, "generated/outputs/%s_%d/%s"), step, year, file)

# provenance is accumulated as we go: one row per (table, year) actually written
PROV <- list()
note_prov <- function(tbl, year, src) {
  mt <- if (!is.null(src) && file.exists(src)) format(file.mtime(src), "%Y-%m-%dT%H:%M:%S%z") else NA_character_
  PROV[[length(PROV) + 1L]] <<- data.frame(
    tbl = tbl, year = if (is.null(year)) NA_integer_ else as.integer(year),
    source_file = src %||% NA_character_, source_mtime = mt,
    exported_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE)
}

write_fact <- function(df, tbl, year) {
  if (is.null(df) || !nrow(df)) return(invisible(0L))
  d <- OUT(tbl, sprintf("year=%d", year))
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  arrow::write_parquet(df, file.path(d, "part-0.parquet"), compression = PARQUET_CODEC)
  invisible(nrow(df))
}
write_dim <- function(df, tbl) {
  dir.create(OUT(tbl), showWarnings = FALSE, recursive = TRUE)
  arrow::write_parquet(df, OUT(tbl, "part-0.parquet"), compression = PARQUET_CODEC)
  cat(sprintf("  %-26s %8s rows\n", tbl, format(nrow(df), big.mark = ",")))
  invisible(nrow(df))
}

# ------------------------------------------------------------- footprints --
# Step 20 emits {YEAR}_F_mass.rds: a list of sparse matrices whose rows are
# "<area>_<comm>" and whose columns vary by split. Only the municipal soybean rows
# (co_mun > 1000, comm c021) belong in the release; everything else is the rest of
# the world's FABIO/EXIOBASE detail. Mass allocation (hectares) is the convention
# every step-20 consumer already uses, so the release follows it.
#
# FP_MIN_HA: the matrices carry a very long tail of numerically-nonzero dust --
# keeping every cell makes the footprint layer ~73M rows (~20x the rest of the
# database) while 0.01 ha keeps 99.945% of the hectares in 12.2% of the rows.
# Measured on 2013; recorded in meta_provenance so the cut is never invisible.
FP_MIN_HA <- 0.01

# FP_MIN_YEAR: first year of the footprint tables. 2000 was excluded until 2026-09-30: its
# traced footprint was 20.7% of harvested area (64-78% in other years), which on 2026-09-23
# was put down to steps 13-15. The real cause was step 12 (commit 2fe3b78): SOY_MUN_fin for
# 2000 ends with an out-of-order code (2919553), and the re-export matrix labels were taken
# in file order while its indices were in sorted order, so 3,454 municipalities carried a
# neighbour's flows. Re-run with the fix, 2000 traces 70.5% of harvested area with max
# municipal coverage 1.014 and none above 1.10, the same standard as 2001-2003. Note the
# manuscript (paper/data_section/data.tex:136) still says the series starts in 2001.
FP_MIN_YEAR <- 2000L

soy_triplets <- function(M) {
  rn   <- rownames(M)
  code <- suppressWarnings(as.numeric(sub("_.*", "", rn)))
  comm <- sub(".*_", "", rn)
  keep <- !is.na(code) & code > 1000 & comm == "c021"
  Ms   <- M[keep, , drop = FALSE]
  tr   <- as.data.frame(Matrix::summary(Ms))
  if (!nrow(tr)) return(data.frame(co_mun = integer(), col = character(),
                                   value = numeric(), stringsAsFactors = FALSE))
  data.frame(co_mun = as.integer(sub("_.*", "", rownames(Ms)))[tr$i],
             col    = colnames(Ms)[tr$j],
             value  = tr$x,
             stringsAsFactors = FALSE) %>%
    filter(abs(value) >= FP_MIN_HA)
}
FP_BUILT <- character()

# The pipeline uses two product vocabularies: step 05 says soybean/soy_oil/soy_cake,
# step 08 says bean/oil/cake. The release standardises on bean/oil/cake.
PRODUCT <- c(soybean = "bean", soy_oil = "oil", soy_cake = "cake",
             bean = "bean", oil = "oil", cake = "cake")
ITEM2PROD <- c("2555" = "bean", "2571" = "oil", "2590" = "cake")

# ---------------------------------------------------------------- dimensions --
cat("Dimensions:\n")

# dim_municipality is written AFTER the fact loop -- see below. It must be the union of
# the MUN_capitals spine and every co_mun the facts actually reference, or the SQLite
# foreign keys reject real rows (e.g. Pinto Bandeira 4314530, present 2001-2004 only,
# and the COMEX undisclosed-origin sentinel 9300000).
SEEN_MUN <- integer(0)

# reference year for the dimension sources (first year with step 00/04/05 output)
spine_year <- YEARS[file.exists(outp("00", YEARS, "MUN_capitals.rds")) &
                    file.exists(outp("05", YEARS, "EXP_MUN_SOY_cbs.rds")) &
                    file.exists(outp("04", YEARS, "regions.rds"))][1]
stopifnot(!is.na(spine_year))

# dim_soy_product -- HS4 and FABIO item codes read from the data, not hardcoded
prodmap <- readRDS(outp("05", spine_year, "EXP_MUN_SOY_cbs.rds")) %>%
  select(product, HS4, item_code) %>% distinct()
dim_soy_product <- prodmap %>%
  transmute(product = unname(PRODUCT[as.character(product)]),
            hs4 = as.integer(HS4), fabio_item_code = as.integer(item_code)) %>%
  mutate(description = c(bean = "Soybeans", oil = "Soybean oil",
                         cake = "Soybean cake/meal")[product]) %>%
  arrange(match(product, c("bean", "oil", "cake")))
write_dim(dim_soy_product, "dim_soy_product")
note_prov("dim_soy_product", NA, outp("05", spine_year, "EXP_MUN_SOY_cbs.rds"))

# dim_country -- continent derived from iso3c (countrycode); `region` kept verbatim
# from regions.rds, which is a mixed-granularity FABIO grouping, NOT a continent.
regions <- readRDS(outp("04", spine_year, "regions.rds"))
iso <- as.character(regions$CO_PAIS_ISOA3)
continent <- if (requireNamespace("countrycode", quietly = TRUE)) {
  countrycode::countrycode(iso, "iso3c", "continent", warn = FALSE)
} else {
  warning("countrycode not installed -- continent left NA")
  rep(NA_character_, length(iso))
}
# regions.rds is a COMEX-code table, so several rows share one iso3 (COMEX 20
# "Alboran-Perejil Islands" -> ESP, COMEX 100 "Manaus Free Trade Zone" -> BRA).
# Collapsing with distinct() alone would label Spain "Alboran-Perejil"; take the
# canonical country name from countrycode and keep the COMEX label only as fallback.
canonical <- if (requireNamespace("countrycode", quietly = TRUE)) {
  countrycode::countrycode(iso, "iso3c", "country.name", warn = FALSE)
} else rep(NA_character_, length(iso))
dim_country <- data.frame(
  iso3c = iso, name_comex = as.character(regions$NO_PAIS_ING),
  name_canon = canonical,
  continent = continent, region = as.character(regions$region),
  eu27 = as.logical(regions$EU27), stringsAsFactors = FALSE) %>%
  filter(!is.na(iso3c), iso3c != "") %>%
  mutate(region = ifelse(region == "", NA_character_, region)) %>%
  # prefer rows that carry a region label when collapsing duplicates
  arrange(iso3c, is.na(region)) %>%
  distinct(iso3c, .keep_all = TRUE) %>%
  transmute(iso3c, name = ifelse(is.na(name_canon), name_comex, name_canon),
            continent, region, eu27) %>%
  arrange(iso3c)
write_dim(dim_country, "dim_country")
note_prov("dim_country", NA, outp("04", spine_year, "regions.rds"))

# dim_commodity -- enduse_bucket omitted (no source); `group` is a reserved SQL
# keyword and is quoted in the SQLite DDL downstream.
items <- read.csv(file.path(DATA_DIR, "fabio/trade/FABIO_exp/items.csv"), stringsAsFactors = FALSE)
dim_commodity <- items %>%
  transmute(comm_code = as.character(comm_code), item_code = as.integer(item_code),
            item = as.character(item), comm_group = as.character(comm_group),
            group = as.character(group)) %>%
  distinct(comm_code, .keep_all = TRUE) %>% arrange(comm_code)
write_dim(dim_commodity, "dim_commodity")
note_prov("dim_commodity", NA, file.path(DATA_DIR, "fabio/trade/FABIO_exp/items.csv"))

# FAO numeric country code -> iso3, needed because step 05 stores partners as FAO codes
fao2iso <- setNames(as.character(regions$CO_PAIS_ISOA3), as.character(regions$CO_FAO))

# -------------------------------------------------------------- fact tables --
cat("\nFact tables by year:\n")
counts <- list()
for (Y in YEARS) {
  f_soy <- outp("05", Y, "SOY_MUN_fin.rds")
  if (!file.exists(f_soy)) { cat(sprintf("  %d  SKIPPED (no step 05 output)\n", Y)); next }
  soy <- readRDS(f_soy)
  n <- list(year = Y)

  # production: one row per municipality-year
  production <- soy %>% transmute(
    co_mun = as.integer(co_mun),
    area_planted_ha   = as.numeric(area_plant),
    area_harvested_ha = as.numeric(area_harv),
    production_bean_t = as.numeric(prod_bean),
    processed_bean_t  = as.numeric(proc_bean),
    production_oil_t  = as.numeric(prod_oil),
    production_cake_t = as.numeric(prod_cake),
    year = as.integer(Y))
  n$production <- write_fact(production, "production", Y)
  note_prov("production", Y, f_soy)

  # domestic_use: wide -> long. Zero/NA rows are dropped; a fact table records use
  # that happened, and keeping ~5 zero rows per municipality would triple the table.
  du_map <- tribble(
    ~col,          ~product, ~use_category,
    "food_bean",   "bean",   "food",
    "food_oil",    "oil",    "food",
    "other_oil",   "oil",    "other",
    "seed_bean",   "bean",   "seed",
    "feed_bean",   "bean",   "feed",
    "feed_cake",   "cake",   "feed")
  du_have <- du_map %>% filter(col %in% names(soy))
  # Stock rows come from 05b_stock_decomposition.R, which splits step 05's net stock change
  # (stock_bean/oil/cake) into FAO stock variation, losses and residual. The parts sum to
  # the net row per municipality and product; the model itself still uses the net.
  f_dec <- outp("05", Y, "STOCK_DECOMP_MUN.rds")
  if (!file.exists(f_dec)) stop("[release] missing ", f_dec, " -- run code/pipeline/05b_stock_decomposition.R ", Y)
  stock_rows <- readRDS(f_dec) %>%
    transmute(co_mun = as.integer(co_mun), product = as.character(product),
              use_category = c(stock = "stock", losses = "losses", residual = "residual")[as.character(component)],
              tonnes = as.numeric(tonnes))
  stopifnot(!anyNA(stock_rows$use_category))
  domestic_use <- soy %>%
    select(co_mun, all_of(du_have$col)) %>%
    pivot_longer(-co_mun, names_to = "col", values_to = "tonnes") %>%
    inner_join(du_have, by = "col") %>%
    transmute(co_mun = as.integer(co_mun), product, use_category, tonnes = as.numeric(tonnes)) %>%
    bind_rows(stock_rows) %>%
    filter(!is.na(tonnes), tonnes != 0) %>%
    mutate(year = as.integer(Y)) %>%
    arrange(co_mun, product, use_category)
  n$domestic_use <- write_fact(domestic_use, "domestic_use", Y)
  note_prov("domestic_use", Y, f_soy)
  note_prov("domestic_use", Y, f_dec)

  # trade: exports and imports stacked; FAO partner codes resolved to iso3
  f_exp <- outp("05", Y, "EXP_MUN_SOY_cbs.rds"); f_imp <- outp("05", Y, "IMP_MUN_SOY_cbs.rds")
  tr <- list()
  if (file.exists(f_exp)) {
    e <- readRDS(f_exp)
    tr[[1]] <- e %>% transmute(
      co_mun = as.integer(co_mun), product = unname(PRODUCT[as.character(product)]),
      flow = "export", partner_iso3 = unname(fao2iso[as.character(to_code)]),
      hs4 = as.integer(HS4), tonnes = as.numeric(export),
      value_usd = as.numeric(export_dol), year = as.integer(Y))
  }
  if (file.exists(f_imp)) {
    i <- readRDS(f_imp)
    tr[[2]] <- i %>% transmute(
      co_mun = as.integer(co_mun), product = unname(PRODUCT[as.character(product)]),
      flow = "import", partner_iso3 = unname(fao2iso[as.character(from_code)]),
      hs4 = as.integer(HS4), tonnes = as.numeric(import),
      value_usd = as.numeric(import_dol), year = as.integer(Y))
  }
  trade <- bind_rows(tr) %>% filter(!is.na(tonnes), tonnes != 0) %>%
    arrange(co_mun, flow, product, partner_iso3)
  n$trade <- write_fact(trade, "trade", Y)
  note_prov("trade", Y, f_exp)

  # transport_flows: flows_mu carries one column per routing method
  f_flows <- outp("08", Y, "flows_mu.rds")
  if (file.exists(f_flows)) {
    fl <- readRDS(f_flows)
    method_cols <- intersect(c("euclid", "mean", "multimode_mean"), names(fl))
    transport_flows <- fl %>%
      select(co_orig, co_dest, product, all_of(method_cols)) %>%
      pivot_longer(all_of(method_cols), names_to = "method", values_to = "tonnes") %>%
      filter(!is.na(tonnes), tonnes != 0) %>%
      transmute(method, product = unname(PRODUCT[as.character(product)]),
                co_mun_orig = as.integer(co_orig), co_mun_dest = as.integer(co_dest),
                tonnes = as.numeric(tonnes), year = as.integer(Y)) %>%
      arrange(method, product, co_mun_orig, co_mun_dest)
    n$transport_flows <- write_fact(transport_flows, "transport_flows", Y)
    note_prov("transport_flows", Y, f_flows)
  }

  # export_attribution: a named list, one data.frame per method
  f_attr <- outp("08", Y, "source_to_export_mean.rds")
  if (file.exists(f_attr)) {
    sa <- readRDS(f_attr)
    ea <- bind_rows(lapply(names(sa), function(m) {
      d <- sa[[m]]; if (!is.data.frame(d) || !nrow(d)) return(NULL)
      data.frame(method = m,
                 product = unname(ifelse(as.character(d$item_code) %in% names(ITEM2PROD),
                                         ITEM2PROD[as.character(d$item_code)],
                                         PRODUCT[as.character(d$item_code)])),
                 co_mun = suppressWarnings(as.integer(as.character(d$from_code))),
                 dest_iso3 = as.character(d$to_code),
                 tonnes = as.numeric(d$value), year = as.integer(Y),
                 stringsAsFactors = FALSE)
    })) %>% filter(!is.na(tonnes), tonnes != 0, !is.na(co_mun)) %>%
      arrange(method, product, co_mun, dest_iso3)
    n$export_attribution <- write_fact(ea, "export_attribution", Y)
    note_prov("export_attribution", Y, f_attr)
  }

  # footprints: step 20 F_mass, hectares of Brazilian municipal soy land
  ffp <- file.path(DATA_DIR, sprintf("generated/footprints/%d_F_mass.rds", Y))
  if (Y < FP_MIN_YEAR && file.exists(ffp)) {
    cat(sprintf("  %d  footprint tables SKIPPED (before FP_MIN_YEAR=%d; see the note there)\n",
                Y, FP_MIN_YEAR))
  } else if (file.exists(ffp)) {
    FM <- readRDS(ffp)

    # who consumes it: A = food (FABIO), B = nonfood (EXIOBASE)
    footprint_country <- bind_rows(
      soy_triplets(FM$A_country) %>%
        transmute(co_mun, consumer_code = sub("_food$", "", col), demand = "food",
                  hectares = value),
      soy_triplets(FM$B_country) %>%
        transmute(co_mun, consumer_code = sub("_nonfood$", "", col), demand = "nonfood",
                  hectares = value)) %>%
      transmute(co_mun, consumer_code, demand, hectares, year = as.integer(Y)) %>%
      arrange(co_mun, demand, consumer_code)
    n$footprint_country <- write_fact(footprint_country, "footprint_country", Y)
    note_prov("footprint_country", Y, ffp)

    # as what: product_family disambiguates the two code systems. Figure 5 gives
    # product_code an FK to dim_commodity, which cannot hold -- B_product columns are
    # EXIOBASE products, not FABIO items -- so the family column carries that instead.
    footprint_product <- bind_rows(
      soy_triplets(FM$A_product) %>%
        transmute(co_mun, product_family = "fabio", product_code = col, hectares = value),
      soy_triplets(FM$B_product) %>%
        transmute(co_mun, product_family = "exiobase", product_code = col, hectares = value)) %>%
      transmute(co_mun, product_family, product_code, hectares, year = as.integer(Y)) %>%
      arrange(co_mun, product_family, product_code)
    n$footprint_product <- write_fact(footprint_product, "footprint_product", Y)
    note_prov("footprint_product", Y, ffp)

    # which animal product, in which country. Keep the 8 individual items; the 4 group
    # aggregates (dairy, meat, meat-dairy, meat-dairy-eggs) overlap them and are derivable.
    footprint_animal_country <- soy_triplets(FM$A_prod_country) %>%
      mutate(consumer_iso3 = substr(col, 1, 3), item = substring(col, 5)) %>%
      filter(!item %in% c("dairy", "meat", "meat-dairy", "meat-dairy-eggs")) %>%
      transmute(co_mun, consumer_iso3, item, hectares = value, year = as.integer(Y)) %>%
      arrange(co_mun, consumer_iso3, item)
    n$footprint_animal_country <- write_fact(footprint_animal_country,
                                             "footprint_animal_country", Y)
    note_prov("footprint_animal_country", Y, ffp)

    FP_BUILT <- union(FP_BUILT, c("footprint_country", "footprint_product",
                                  "footprint_animal_country"))
    SEEN_MUN <- unique(c(SEEN_MUN, footprint_country$co_mun))
    rm(FM, footprint_country, footprint_product, footprint_animal_country)
    gc(verbose = FALSE)
  }

  SEEN_MUN <- unique(c(SEEN_MUN, production$co_mun, domestic_use$co_mun,
                       if (nrow(trade)) trade$co_mun else integer(0)))
  if (exists("transport_flows") && nrow(transport_flows))
    SEEN_MUN <- unique(c(SEEN_MUN, transport_flows$co_mun_orig, transport_flows$co_mun_dest))
  if (exists("ea") && nrow(ea)) SEEN_MUN <- unique(c(SEEN_MUN, ea$co_mun))

  counts[[as.character(Y)]] <- n
  cat(sprintf("  %d  production=%s domestic_use=%s trade=%s transport=%s export_attr=%s footprint=%s\n",
      Y, format(n$production %||% 0, big.mark = ","),
      format(n$domestic_use %||% 0, big.mark = ","), format(n$trade %||% 0, big.mark = ","),
      format(n$transport_flows %||% 0, big.mark = ","),
      format(n$export_attribution %||% 0, big.mark = ","),
      format((n$footprint_country %||% 0) + (n$footprint_product %||% 0) +
             (n$footprint_animal_country %||% 0), big.mark = ",")))
}

# ------------------------------------------------------- dim_municipality (late) --
cat("\nMunicipality dimension:\n")
caps <- readRDS(outp("00", spine_year, "MUN_capitals.rds"))
if (inherits(caps, "sf")) caps <- sf::st_drop_geometry(caps)
states <- bind_rows(lapply(YEARS, function(y) {
  f <- outp("05", y, "SOY_MUN_fin.rds")
  if (!file.exists(f)) return(NULL)
  readRDS(f) %>% select(co_mun, nm_mun, co_state, nm_state)
})) %>% mutate(co_mun = as.integer(co_mun)) %>%
  # step 05 writes "0" placeholders for municipalities missing from that year's IBGE
  # list (2919553 in 2000; 5104526, 5104542 in 2004); skip them so a later year names them
  filter(!is.na(nm_mun), !trimws(as.character(nm_mun)) %in% c("", "0")) %>%
  distinct(co_mun, .keep_all = TRUE)

# Fallback names: every IBGE municipality table on disk, latest year first. Covers codes
# that SOY_MUN_fin never names (e.g. municipalities created after the spine year).
ibge <- bind_rows(lapply(rev(sort(Sys.glob(file.path(DATA_DIR, "raw/00/IBGE_municipalities/GEO_MUN_*_IBGE.csv")))),
  function(f) read.csv(f, stringsAsFactors = FALSE, encoding = "UTF-8") %>%
    transmute(co_mun = as.integer(co_mun), nm_ibge = as.character(nm_mun),
              co_state_ibge = as.integer(co_state), nm_state_ibge = as.character(nm_state)))) %>%
  distinct(co_mun, .keep_all = TRUE)

dim_municipality <- caps %>%
  transmute(co_mun = as.integer(co_mun), nm_mun_cap = na_if(trimws(as.character(nm_mun)), "0"),
            lon = as.numeric(LONG), lat = as.numeric(LAT)) %>%
  full_join(states, by = "co_mun") %>%
  transmute(co_mun,
            nm_mun = ifelse(is.na(nm_mun_cap), as.character(nm_mun), nm_mun_cap),
            co_state = as.integer(co_state), nm_state = as.character(nm_state),
            lon, lat)

extra <- setdiff(SEEN_MUN, dim_municipality$co_mun)
if (length(extra)) {
  dim_municipality <- bind_rows(dim_municipality, data.frame(
    co_mun = as.integer(extra), nm_mun = NA_character_, co_state = NA_integer_,
    nm_state = NA_character_, lon = NA_real_, lat = NA_real_))
}
dim_municipality <- dim_municipality %>%
  left_join(ibge, by = "co_mun") %>%
  mutate(nm_mun   = coalesce(nm_mun, nm_ibge),
         co_state = coalesce(co_state, co_state_ibge),
         nm_state = coalesce(nm_state, nm_state_ibge)) %>%
  select(-nm_ibge, -co_state_ibge, -nm_state_ibge)
# 9300000 is COMEX's undisclosed-origin sentinel, not a municipality; label it so no
# one mistakes it for a place.
dim_municipality <- dim_municipality %>%
  mutate(nm_mun = ifelse(co_mun == 9300000L,
                         "UNDISCLOSED (COMEX undisclosed-origin sentinel)", nm_mun)) %>%
  arrange(co_mun)
write_dim(dim_municipality, "dim_municipality")
note_prov("dim_municipality", NA, outp("00", spine_year, "MUN_capitals.rds"))

# ------------------------------------------------------------------ metadata --
cat("\nMetadata:\n")
git <- function(a) tryCatch(trimws(system2("git", a, stdout = TRUE, stderr = FALSE)[1]),
                            error = function(e) NA_character_)
meta_build <- data.frame(
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  git_commit = git(c("rev-parse", "HEAD")),
  git_branch = git(c("rev-parse", "--abbrev-ref", "HEAD")),
  sqlite_version = NA_character_,   # filled by build_release_db.py
  stringsAsFactors = FALSE)
write_dim(meta_build, "meta_build")

# record any Figure 5 footprint table still missing, and the cut applied to those built
for (t in setdiff(c("footprint_animal_country", "footprint_country", "footprint_product"),
                  FP_BUILT)) {
  PROV[[length(PROV) + 1L]] <- data.frame(
    tbl = t, year = NA_integer_,
    source_file = "NOT BUILT -- no step 20 footprint output for any year in range",
    source_mtime = NA_character_,
    exported_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), stringsAsFactors = FALSE)
}
if (length(FP_BUILT)) {
  fp_years <- sort(unique(unlist(lapply(PROV, function(p)
    if (p$tbl %in% FP_BUILT) p$year else NULL))))
  for (t in FP_BUILT) {
    PROV[[length(PROV) + 1L]] <- data.frame(
      tbl = t, year = NA_integer_,
      source_file = sprintf(paste0("THRESHOLD: rows below %g ha dropped (keeps ~99.95%% of ",
                                   "hectares); mass allocation (F_mass); years %s. ",
                                   "Years before %d are excluded: unresolved municipal ",
                                   "supply-use imbalance in that build (see build_release_parquet.R)"),
                            FP_MIN_HA, paste(range(fp_years), collapse = "-"), FP_MIN_YEAR),
      source_mtime = NA_character_,
      exported_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), stringsAsFactors = FALSE)
  }
}
meta_provenance <- bind_rows(PROV)
write_dim(meta_provenance, "meta_provenance")

cat(sprintf("\nParquet layer written to %s for %d-%d.\n", OUTDIR, START, END))
