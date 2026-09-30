#!/usr/bin/env Rscript
# inventory_outputs.R -- inventory every pipeline artefact under data/generated/.
#
# Records, per file: path, size, format, object class, dimensions and column
# names. This is the evidence base for the release-schema decision (it says what
# the pipeline actually produces, independent of any design sketch).
#
# Usage: Rscript code/inventory_outputs.R [root] [out.csv]
#   root    default data/generated
#   out.csv default results/reference/output_inventory.csv
#
# Nothing is inferred: a file that cannot be read is recorded with the read
# error in `notes`, never guessed at or skipped silently.

# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) >= 1) args[1] else file.path(DATA_DIR, "generated")
out  <- if (length(args) >= 2) args[2] else "results/reference/output_inventory.csv"

if (!dir.exists(root)) stop("no such directory: ", root)
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)

files <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = FALSE)
files <- files[!file.info(files)$isdir]
if (!length(files)) stop("no files under ", root)

# describe one in-memory object without loading assumptions about its type
describe <- function(obj) {
  cls <- paste(class(obj), collapse = "/")
  nr <- nc <- NA_integer_
  cols <- NA_character_
  if (is.data.frame(obj)) {
    nr <- nrow(obj); nc <- ncol(obj); cols <- paste(names(obj), collapse = "|")
  } else if (inherits(obj, c("Matrix", "matrix", "array"))) {
    d <- dim(obj)
    if (!is.null(d)) { nr <- d[1]; nc <- if (length(d) >= 2) d[2] else NA_integer_ }
    dn <- dimnames(obj)
    if (!is.null(dn) && length(dn) >= 2 && !is.null(dn[[2]]))
      cols <- paste(utils::head(dn[[2]], 200), collapse = "|")
  } else if (is.list(obj)) {
    nr <- length(obj)
    if (!is.null(names(obj))) cols <- paste(utils::head(names(obj), 200), collapse = "|")
  } else if (is.atomic(obj)) {
    nr <- length(obj)
  }
  list(class = cls, nrow = nr, ncol = nc, cols = cols)
}

rows <- list()
for (f in files) {
  ext  <- tolower(tools::file_ext(f))
  info <- file.info(f)
  rec  <- list(path = f, bytes = info$size, format = ext,
               object = NA_character_, class = NA_character_,
               nrow = NA_integer_, ncol = NA_integer_,
               columns = NA_character_, notes = "")
  if (ext == "rds") {
    o <- tryCatch(readRDS(f), error = function(e) e)
    if (inherits(o, "error")) {
      rec$notes <- paste("READ ERROR:", conditionMessage(o))
    } else {
      d <- describe(o)
      rec$object <- basename(f); rec$class <- d$class
      rec$nrow <- d$nrow; rec$ncol <- d$ncol; rec$columns <- d$cols
    }
    rows[[length(rows) + 1]] <- rec
  } else if (ext %in% c("rdata", "rda")) {
    # an .RData holds N named objects -- emit one row per object
    e <- new.env()
    ok <- tryCatch({ load(f, envir = e); TRUE },
                   error = function(err) { rec$notes <<- paste("READ ERROR:", conditionMessage(err)); FALSE })
    if (!ok) { rows[[length(rows) + 1]] <- rec } else {
      for (nm in ls(e)) {
        d <- describe(get(nm, envir = e))
        r <- rec; r$object <- nm; r$class <- d$class
        r$nrow <- d$nrow; r$ncol <- d$ncol; r$columns <- d$cols
        rows[[length(rows) + 1]] <- r
      }
    }
  } else {
    rec$notes <- "not an R serialisation; size recorded only"
    rows[[length(rows) + 1]] <- rec
  }
}

inv <- do.call(rbind, lapply(rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
inv <- inv[order(inv$path, inv$object), ]
write.csv(inv, out, row.names = FALSE, na = "")
cat("wrote", out, "--", nrow(inv), "rows from", length(files), "files\n")
