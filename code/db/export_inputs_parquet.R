#!/usr/bin/env Rscript
# ============================================================================
# SOYPRINT inputs database - stage 1b: export cleaned pipeline INPUTS to
# Parquet (the outputs of preparation steps 00-03, i.e. the harmonised raw
# data as the pipeline consumes it, before any balancing).
#
# Tables written per year under data/db/parquet/<table>/year=YYYY/:
#   input_municipality      (00 SOY_MUN_00)     the "grand input": one row per
#                                               municipality with production,
#                                               trade totals, processing/refining
#                                               capacity, population, livestock,
#                                               storage, food oil demand, biodiesel
#   input_trade             (00 EXP/IMP_MUN_SOY_00) raw COMEX soy flows,
#                                               mun x product x partner (pre-CBS)
#   input_cbs_national      (00 CBS_SOY)        FAO commodity balance, Brazil,
#                                               bean/oil/cake
#   input_livestock_systems (02 LIVESTOCK_MUN_02) mun x animal category, heads
#   input_feed              (03 bean/cake_feed_t) mun x animal category, feed t
#
# Written once (has a year column, no partition):
#   input_faostat_trade     (raw/04 FAOSTAT tradematrix) BRA soy trade by
#                                               partner, for benchmarks
#
# Usage:
#   Rscript code/db/export_inputs_parquet.R 2019          # one year
#   Rscript code/db/export_inputs_parquet.R --all         # all years on disk
#   Rscript code/db/export_inputs_parquet.R --all --force # overwrite existing
# ============================================================================

suppressMessages({
  library(data.table)
  library(nanoparquet)
})

args  <- commandArgs(trailingOnly = TRUE)
FORCE <- "--force" %in% args
args  <- setdiff(args, "--force")

OUT_ROOT <- "data/db/parquet"
dir.create(OUT_ROOT, showWarnings = FALSE, recursive = TRUE)

years_on_disk <- sort(as.integer(sub("^00_", "", grep("^00_[0-9]{4}$",
  list.files("data/generated/outputs"), value = TRUE))))
YEARS <- if ("--all" %in% args) years_on_disk else as.integer(args)
if (length(YEARS) == 0 || anyNA(YEARS))
  stop("usage: Rscript code/db/export_inputs_parquet.R <YEAR ...>|--all [--force]")

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

# "soybean"/"soy_oil"/"soy_cake" -> bean/oil/cake (matches dim_soy_product)
prod_std <- function(x) {
  x <- tolower(as.character(x))
  fifelse(grepl("bean$", x), "bean",
  fifelse(grepl("oil",  x), "oil",
  fifelse(grepl("cake", x), "cake", x)))
}

# ---------------------------------------------------------------------------
export_year <- function(Y) {
  cat(sprintf("== %d ==\n", Y))

  # ---- step 00: the grand municipal input ---------------------------------
  f00 <- sprintf("data/generated/outputs/00_%d/SOY_MUN_00.rds", Y)
  if (file.exists(f00)) {
    s <- as.data.table(readRDS(f00))
    # names/state live in dim_municipality; everything else is kept verbatim
    s[, c("nm_mun", "co_state", "nm_state") := NULL]
    s[, co_mun := as.integer(co_mun)]
    write_pq(s, "input_municipality", Y, f00)
  } else cat("  [miss]", f00, "\n")

  # ---- step 00: raw COMEX soy trade (pre-CBS-balancing) --------------------
  fe <- sprintf("data/generated/outputs/00_%d/EXP_MUN_SOY_00.rds", Y)
  fi <- sprintf("data/generated/outputs/00_%d/IMP_MUN_SOY_00.rds", Y)
  if (file.exists(fe) && file.exists(fi)) {
    e <- as.data.table(readRDS(fe))
    i <- as.data.table(readRDS(fi))
    tr <- rbind(
      e[, .(co_mun = as.integer(co_mun), product = prod_std(product),
            flow = "export", partner_iso3 = nm_destin,
            partner_comex = as.integer(co_destin), hs4 = as.integer(HS4),
            tonnes = export, value_usd = export_dol)],
      i[, .(co_mun = as.integer(co_mun), product = prod_std(product),
            flow = "import", partner_iso3 = nm_origin,
            partner_comex = as.integer(co_origin), hs4 = as.integer(HS4),
            tonnes = import, value_usd = import_dol)])
    write_pq(tr[tonnes != 0 | value_usd != 0], "input_trade", Y, fe)
  } else cat("  [miss]", fe, "\n")

  # ---- step 00: national FAO commodity balance ----------------------------
  fc <- sprintf("data/generated/outputs/00_%d/CBS_SOY.rds", Y)
  if (file.exists(fc)) {
    cbs <- readRDS(fc)
    cbs <- data.table(product = rownames(cbs), as.data.table(cbs))
    write_pq(cbs, "input_cbs_national", Y, fc)
  } else cat("  [miss]", fc, "\n")

  # ---- step 02: livestock split into production systems -------------------
  fl <- sprintf("data/generated/outputs/02_%d/LIVESTOCK_MUN_02.rds", Y)
  if (file.exists(fl)) {
    l <- as.data.table(readRDS(fl))
    l[, nm_mun := NULL]
    lv <- melt(l, id.vars = "co_mun", variable.name = "animal",
               value.name = "heads", variable.factor = FALSE)
    write_pq(lv[!is.na(heads) & heads != 0,
                .(co_mun = as.integer(co_mun), animal, heads)],
             "input_livestock_systems", Y, fl)
  } else cat("  [miss]", fl, "\n")

  # ---- step 03: feed demand per animal category ---------------------------
  fb <- sprintf("data/generated/outputs/03_%d/bean_feed_t.rds", Y)
  fk <- sprintf("data/generated/outputs/03_%d/cake_feed_t.rds", Y)
  if (file.exists(fb) && file.exists(fk)) {
    m <- function(f, v) {
      x <- readRDS(f)
      dt <- data.table(co_mun = as.integer(rownames(x)), as.data.table(x))
      melt(dt, id.vars = "co_mun", variable.name = "animal",
           value.name = v, variable.factor = FALSE)
    }
    fd <- merge(m(fb, "feed_bean_t"), m(fk, "feed_cake_t"),
                by = c("co_mun", "animal"), all = TRUE)
    for (v in c("feed_bean_t", "feed_cake_t")) fd[is.na(get(v)), (v) := 0]
    write_pq(fd[feed_bean_t != 0 | feed_cake_t != 0], "input_feed", Y, fb)
  } else cat("  [miss]", fb, "\n")
}

# ---- once: FAOSTAT bilateral trade benchmark (all years in one file) -------
export_faostat <- function() {
  src <- "data/raw/04/FAOSTAT_tradematrix_BRAsoy_ALL.csv"
  if (!file.exists(src)) { cat("  [miss]", src, "\n"); return(invisible()) }
  x <- fread(src)
  setnames(x, c("Partner Country Code (ISO3)", "Partner Countries"),
              c("partner_iso3", "partner_name"))
  x[, product := fifelse(grepl("Cake", Item), "cake",
               fifelse(grepl("[Oo]il", Item), "oil", "bean"))]
  x[, flow := fifelse(grepl("Export", Element), "export", "import")]
  x[, measure := fifelse(grepl("Quantity", Element), "tonnes", "value_kusd")]
  out <- dcast(x, Year + product + flow + partner_iso3 + partner_name
               ~ measure, value.var = "Value", fun.aggregate = sum)
  setnames(out, "Year", "year")
  if (!"value_kusd" %in% names(out)) out[, value_kusd := NA_real_]
  write_pq(out[, .(year = as.integer(year), product, flow, partner_iso3,
                   partner_name, tonnes, value_kusd)],
           "input_faostat_trade", src = src)
}

# ---------------------------------------------------------------------------
for (Y in YEARS) export_year(Y)
cat("== once-only ==\n")
export_faostat()

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
