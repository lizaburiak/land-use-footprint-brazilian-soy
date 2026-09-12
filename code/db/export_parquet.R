#!/usr/bin/env Rscript
# ============================================================================
# SOYPRINT results database - stage 1: export pipeline outputs to Parquet.
#
# Reads the per-year .rds outputs of the pipeline and writes long-format,
# hive-partitioned Parquet under data/db/parquet/<table>/year=YYYY/data.parquet.
# Stage 2 (code/db/build_duckdb.py) assembles data/db/soyprint.duckdb from these.
#
# Fact tables written per year (sources in parentheses):
#   production          (05 SOY_MUN_fin)         mun: tonnes + hectares
#   domestic_use        (05 SOY_MUN_fin, melted) mun x product x use_category
#   trade               (05 EXP/IMP_MUN_SOY_cbs) mun x product x partner, t + USD
#   export_attribution  (08 source_to_export_*)  mun x product x destination, t
#   transport_flows     (08 flows_mu, melted)    mun_orig x mun_dest x product, t
#   footprint_country   (20 F_mass A/B_country)  mun x consumer country, ha
#   footprint_product   (20 F_mass A/B_product)  mun x consumer product, ha
#   footprint_animal_country (20 F_mass A_prod_country) mun x country x animal
#                                                product (8 items, partial), ha
#
# Dimension inputs written once (no year partition) under data/db/parquet/dims/:
#   dim_municipality  co_mun, name, state, biome, matopiba, lon, lat
#
# Usage:
#   Rscript code/db/export_parquet.R 2019            # one year
#   Rscript code/db/export_parquet.R --all           # all years found on disk
#   Rscript code/db/export_parquet.R --all --force   # overwrite existing
# ============================================================================

suppressMessages({
  library(data.table)
  library(Matrix)
  library(nanoparquet)
})

args  <- commandArgs(trailingOnly = TRUE)
FORCE <- "--force" %in% args
args  <- setdiff(args, "--force")

OUT_ROOT <- "data/db/parquet"
dir.create(OUT_ROOT, showWarnings = FALSE, recursive = TRUE)

years_on_disk <- sort(as.integer(sub("^05_", "", grep("^05_[0-9]{4}$",
  list.files("data/generated/outputs"), value = TRUE))))
YEARS <- if ("--all" %in% args) years_on_disk else as.integer(args)
if (length(YEARS) == 0 || anyNA(YEARS))
  stop("usage: Rscript code/db/export_parquet.R <YEAR ...>|--all [--force]")

# provenance rows collected while exporting, appended to meta/provenance.parquet
PROV <- list()

write_pq <- function(dt, table, year = NULL, src = NULL) {
  dir <- if (is.null(year)) file.path(OUT_ROOT, table)
         else file.path(OUT_ROOT, table, sprintf("year=%d", year))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, "data.parquet")
  if (file.exists(path) && !FORCE) { cat("  [skip]", path, "\n"); return(invisible()) }
  nanoparquet::write_parquet(as.data.frame(dt), path)
  cat(sprintf("  [ok] %s (%s rows)\n", path, format(nrow(dt), big.mark = ",")))
  if (!is.null(src)) PROV[[length(PROV) + 1]] <<- data.table(
    tbl = table, year = if (is.null(year)) NA_integer_ else year,
    source_file = src,
    source_mtime = format(file.mtime(src), "%Y-%m-%d %H:%M:%S"),
    exported_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
}

# sparse matrix -> long triplets, restricted to municipal soy rows (co_mun_c021)
soy_triplets <- function(M) {
  code <- suppressWarnings(as.numeric(sub("_.*", "", rownames(M))))
  comm <- sub(".*_", "", rownames(M))
  soy  <- !is.na(code) & code > 1000 & comm == "c021"
  Ms   <- M[soy, , drop = FALSE]
  tr   <- as.data.table(Matrix::summary(Ms))
  tr[, `:=`(co_mun = as.integer(sub("_.*", "", rownames(Ms)))[i],
            col    = colnames(Ms)[j])]
  tr[x != 0, .(co_mun, col, value = x)]
}

# ---------------------------------------------------------------------------
export_year <- function(Y) {
  cat(sprintf("== %d ==\n", Y))

  # ---- step 05: production, domestic use, trade ---------------------------
  f05 <- sprintf("data/generated/outputs/05_%d/SOY_MUN_fin.rds", Y)
  if (file.exists(f05)) {
    s <- as.data.table(readRDS(f05))

    write_pq(s[, .(co_mun = as.integer(co_mun),
                   area_planted_ha   = area_plant,
                   area_harvested_ha = area_harv,
                   production_bean_t = prod_bean,
                   processed_bean_t  = proc_bean,
                   production_oil_t  = prod_oil,
                   production_cake_t = prod_cake)],
             "production", Y, f05)

    # melt use components to (co_mun, product, use_category, tonnes)
    use_map <- data.table(
      colnm    = c("food_bean", "feed_bean", "seed_bean", "proc_bean", "stock_bean",
                   "food_oil", "other_oil", "stock_oil",
                   "feed_cake", "stock_cake"),
      product  = c(rep("bean", 5), rep("oil", 3), rep("cake", 2)),
      use_category = c("food", "feed", "seed", "processing", "stock_change",
                       "food", "other", "stock_change",
                       "feed", "stock_change"))
    u <- melt(s[, c("co_mun", use_map$colnm), with = FALSE],
              id.vars = "co_mun", variable.name = "colnm", value.name = "tonnes",
              variable.factor = FALSE)
    u <- merge(u, use_map, by = "colnm")[tonnes != 0]
    write_pq(u[, .(co_mun = as.integer(co_mun), product, use_category, tonnes)],
             "domestic_use", Y, f05)
  } else cat("  [miss]", f05, "\n")

  fe <- sprintf("data/generated/outputs/05_%d/EXP_MUN_SOY_cbs.rds", Y)
  fi <- sprintf("data/generated/outputs/05_%d/IMP_MUN_SOY_cbs.rds", Y)
  if (file.exists(fe) && file.exists(fi)) {
    e <- as.data.table(readRDS(fe))
    i <- as.data.table(readRDS(fi))
    tr <- rbind(
      # NB: in EXP/IMP_MUN_SOY_cbs the *_name column holds the ISO3 code and
      # *_code the numeric COMEX country code - we keep the ISO3.
      e[, .(co_mun = as.integer(co_mun), product = prod_std(product), flow = "export",
            partner_iso3 = to_name, hs4 = as.integer(HS4),
            tonnes = export, value_usd = export_dol)],
      i[, .(co_mun = as.integer(co_mun), product = prod_std(product), flow = "import",
            partner_iso3 = from_name, hs4 = as.integer(HS4),
            tonnes = import, value_usd = import_dol)])
    write_pq(tr[tonnes != 0 | value_usd != 0], "trade", Y, fe)
  } else cat("  [miss]", fe, "\n")

  # ---- step 08: export attribution + transport flows ----------------------
  f08 <- sprintf("data/generated/outputs/08_%d/source_to_export_mean.rds", Y)
  if (file.exists(f08)) {
    se <- readRDS(f08)
    ea <- rbindlist(lapply(names(se), function(m)
      as.data.table(se[[m]])[, .(method = m, product = prod_std(item_code),
                                 co_mun = as.integer(from_code),
                                 dest_iso3 = to_code, tonnes = value)]))
    write_pq(ea[tonnes > 0], "export_attribution", Y, f08)
  } else cat("  [miss]", f08, "\n")

  ffl <- sprintf("data/generated/outputs/08_%d/flows_mu.rds", Y)
  if (file.exists(ffl)) {
    fm <- as.data.table(readRDS(ffl))
    methods <- setdiff(names(fm), c("co_orig", "co_dest", "product"))
    fl <- melt(fm, id.vars = c("co_orig", "co_dest", "product"),
               measure.vars = methods, variable.name = "method",
               value.name = "tonnes", variable.factor = FALSE)
    fl[method == "mean", method := "multimode_mean"]
    write_pq(fl[tonnes > 0, .(method, product = prod_std(product),
                              co_mun_orig = as.integer(co_orig),
                              co_mun_dest = as.integer(co_dest), tonnes)],
             "transport_flows", Y, ffl)
  } else cat("  [miss]", ffl, "\n")

  # ---- step 20: land footprints (F_mass, hectares) -------------------------
  ffp <- sprintf("data/generated/footprints/%d_F_mass.rds", Y)
  if (file.exists(ffp)) {
    FM <- readRDS(ffp)

    fc <- rbind(
      soy_triplets(FM$A_country)[, .(co_mun,
        consumer_code = sub("_food$", "", col), demand = "food", hectares = value)],
      soy_triplets(FM$B_country)[, .(co_mun,
        consumer_code = sub("_nonfood$", "", col), demand = "nonfood", hectares = value)])
    write_pq(fc, "footprint_country", Y, ffp)

    fp <- rbind(
      soy_triplets(FM$A_product)[, .(co_mun, product_family = "fabio",
                                     product_code = col, hectares = value)],
      soy_triplets(FM$B_product)[, .(co_mun, product_family = "exiobase",
                                     product_code = col, hectares = value)])
    write_pq(fp, "footprint_product", Y, ffp)

    # A_prod_country: keep the 8 individual animal items; drop the overlapping
    # group aggregates (dairy, meat, meat-dairy, meat-dairy-eggs) - derivable.
    ac <- soy_triplets(FM$A_prod_country)
    ac[, `:=`(consumer_iso3 = substr(col, 1, 3), item = substring(col, 5))]
    ac <- ac[!item %in% c("dairy", "meat", "meat-dairy", "meat-dairy-eggs")]
    write_pq(ac[, .(co_mun, consumer_iso3, item, hectares = value)],
             "footprint_animal_country", Y, ffp)
    rm(FM); gc(verbose = FALSE)
  } else cat("  [miss]", ffp, "\n")
}

# item_code/product spellings differ across steps ("soybean"/"bean"/"soy_oil"...)
prod_std <- function(x) {
  x <- tolower(as.character(x))
  fifelse(grepl("bean$|^1201$|^2555$", x), "bean",
  fifelse(grepl("oil",  x), "oil",
  fifelse(grepl("cake", x), "cake", x)))
}

# ---- dimension: municipalities (built once from latest available geo) -------
export_dim_municipality <- function() {
  path <- file.path(OUT_ROOT, "dims", "dim_municipality", "data.parquet")
  if (file.exists(path) && !FORCE) { cat("  [skip] dim_municipality\n"); return(invisible()) }
  suppressMessages(library(sf)); sf_use_s2(FALSE)
  yr_geo <- max(YEARS[file.exists(sprintf(
    "data/generated/outputs/05_%d/GEO_MUN_SOY_fin.rds", YEARS))])
  cat(sprintf("  [dim] municipalities from GEO_MUN_SOY_fin %d\n", yr_geo))
  g <- readRDS(sprintf("data/generated/outputs/05_%d/GEO_MUN_SOY_fin.rds", yr_geo))
  pts <- suppressWarnings(st_coordinates(st_transform(
    st_point_on_surface(st_geometry(g)), 4326)))
  d <- data.table(co_mun = as.integer(g$co_mun), nm_mun = g$nm_mun,
                  co_state = as.integer(g$co_state), nm_state = g$nm_state,
                  lon = round(pts[, 1], 5), lat = round(pts[, 2], 5))
  # municipalities present in other years but not in the reference geometry;
  # backfill coordinates from the newest GEO file that contains them
  for (Y in rev(setdiff(YEARS, yr_geo))) {
    f <- sprintf("data/generated/outputs/05_%d/SOY_MUN_fin.rds", Y)
    if (!file.exists(f)) next
    s <- as.data.table(readRDS(f))[, .(co_mun = as.integer(co_mun), nm_mun,
                                       co_state = as.integer(co_state), nm_state)]
    extra <- s[!co_mun %in% d$co_mun]
    if (nrow(extra) == 0) next
    fg <- sprintf("data/generated/outputs/05_%d/GEO_MUN_SOY_fin.rds", Y)
    extra[, `:=`(lon = NA_real_, lat = NA_real_)]
    if (file.exists(fg)) {
      g2 <- readRDS(fg)
      hit <- match(extra$co_mun, as.integer(g2$co_mun))
      ok  <- !is.na(hit)
      if (any(ok)) {
        p2 <- suppressWarnings(st_coordinates(st_transform(
          st_point_on_surface(st_geometry(g2)[hit[ok]]), 4326)))
        extra[ok, `:=`(lon = round(p2[, 1], 5), lat = round(p2[, 2], 5))]
      }
    }
    d <- rbind(d, extra)
  }
  # COMEX "undeclared municipality" placeholder codes referenced by trade rows
  d[co_mun >= 9000000, `:=`(nm_mun = "(undeclared)",
                            nm_state = NA_character_, co_state = NA_integer_)]
  lut <- "results/reference/mun_biome_lookup.csv"
  if (file.exists(lut)) {
    b <- fread(lut)[, .(co_mun = as.integer(co_mun), biome, matopiba)]
    d <- merge(d, b, by = "co_mun", all.x = TRUE)
  } else { d[, `:=`(biome = NA_character_, matopiba = NA)] }
  # municipalities absent from the cached lookup (created after its base year):
  # locate them in the IBGE biome polygons directly
  miss <- which(is.na(d$biome) & !is.na(d$lon))
  bshp <- "data/geo/IBGE_biomes/lm_bioma_250.shp"
  if (length(miss) && file.exists(bshp)) {
    bio <- suppressMessages(st_read(bshp, quiet = TRUE))
    pts <- st_transform(st_as_sf(d[miss], coords = c("lon", "lat"), crs = 4326),
                        st_crs(bio))
    d$biome[miss] <- bio$Bioma[st_nearest_feature(pts, bio)]
    d$matopiba[miss] <- d$biome[miss] == "Cerrado" &
                        d$co_state[miss] %in% c(21, 17, 22, 29)
    cat(sprintf("  [dim] biome backfilled for %d municipality(ies)\n", length(miss)))
  }
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  nanoparquet::write_parquet(as.data.frame(d), path)
  cat(sprintf("  [ok] %s (%d municipalities)\n", path, nrow(d)))
}

# ---------------------------------------------------------------------------
for (Y in YEARS) export_year(Y)
cat("== dims ==\n")
export_dim_municipality()

if (length(PROV)) {
  dir.create(file.path(OUT_ROOT, "meta"), showWarnings = FALSE, recursive = TRUE)
  ppath <- file.path(OUT_ROOT, "meta", "provenance.parquet")
  prov <- rbindlist(PROV)
  if (file.exists(ppath)) {
    old <- as.data.table(nanoparquet::read_parquet(ppath))
    prov <- rbind(old[!prov, on = c("tbl", "year")], prov)   # newest wins
  }
  nanoparquet::write_parquet(as.data.frame(prov), ppath)
  cat(sprintf("[meta] provenance: %d rows -> %s\n", nrow(prov), ppath))
}
cat("done.\n")
