
####### Script to compare aggregate MU data with national data from FAO

# Data root: all inputs and generated outputs live here (moved off the repo 2026-09-17).
# Override per run with the environment variable SOYPRINT_DATA_DIR (e.g. isolated worker dirs).
DATA_DIR <- Sys.getenv("SOYPRINT_DATA_DIR", "/mnt/bigdata/projects/soyprint")

library(dplyr)
library(openxlsx)

# Year parameter (default 2013)
args <- commandArgs(trailingOnly = TRUE)
YEAR <- if (length(args) > 0) as.integer(args[1]) else 2013
OUT  <- paste0(DATA_DIR, "/generated/outputs/00_", YEAR, "/")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# should results be written to file?
write = TRUE

# load and format data ---------------------------------------------------------------------------------
SOY_MUN <- readRDS(paste0(OUT, "SOY_MUN_00.rds"))
CBS_SOY <- openxlsx::read.xlsx(paste0(DATA_DIR, "/raw/00/FAO_CBS/CBS_SOY_", YEAR, "_FAO.xlsx"))

# Guard: the rows and columns below are taken BY POSITION. Check that each carries the FAO
# label it is assumed to carry, and fail loudly if a workbook ever arrives in another layout.
.fao_elements <- c("Domestic supply quantity", "Production", "Export Quantity", "Import Quantity",
                   "Food supply quantity (tonnes)", "Feed", "Seed", "Other uses", "Processing",
                   "Stock Variation")
.fao_items <- c("Soyabean Cake", "Soyabean Oil", "Soyabeans")   # columns 3:5; reordered by 5:3 below
.got_el <- trimws(as.character(CBS_SOY[-c(1, 2, nrow(CBS_SOY)), 2]))
.got_it <- trimws(as.character(unlist(CBS_SOY[1, 3:5])))
if (!identical(.got_el, .fao_elements) || !identical(.got_it, .fao_items)) {
  stop(sprintf("[00] CBS_SOY_%d_FAO.xlsx layout changed. Elements: %s | items: %s", YEAR,
               paste(.got_el, collapse = "; "), paste(.got_it, collapse = "; ")), call. = FALSE)
}

# Log the stock-variation sign convention of this workbook, from its own domestic-supply identity
# (domestic supply = production - export + import +/- stock variation). Values are NOT changed here:
# the code below reads the row as a withdrawal, and step 05's closing residual absorbs a flipped sign.
.v <- function(el, col) suppressWarnings(as.numeric(as.character(CBS_SOY[-c(1, 2, nrow(CBS_SOY)), col][match(el, .got_el)])))
for (.k in 3:5) {
  .v0 <- function(el) { x <- .v(el, .k); if (is.na(x)) 0 else x }
  .base <- .v0("Production") - .v0("Export Quantity") + .v0("Import Quantity")
  .sv <- .v0("Stock Variation"); .ds <- .v0("Domestic supply quantity")
  .conv <- if (.sv == 0) "no stock variation" else if (abs(.base + .sv - .ds) <= abs(.base - .sv - .ds))
    "positive = withdrawal" else "positive = addition"
  message(sprintf("[00] %d %s: FAO Stock Variation %.0f t, sign convention: %s", YEAR, .got_it[.k - 2], .sv, .conv))
}

# format FAO CBS
CBS_SOY <- CBS_SOY[-c(1,2, nrow(CBS_SOY)),]
rownames(CBS_SOY) <- c("domestic_supply","production", "export", "import" , "food" , "feed", "seed", "other", "processing", "stock_withdrawal")
CBS_SOY <- CBS_SOY[,5:3]
colnames(CBS_SOY) <- c("bean", "oil", "cake")
CBS_SOY <- as.data.frame(t(CBS_SOY), stringsAsFactors = FALSE)
CBS_SOY <- CBS_SOY %>% mutate(across(everything(), ~as.numeric(as.character(.x))))
CBS_SOY[is.na(CBS_SOY)] <- 0

# CAKE ROW (2026-10-06): FAO's food balance sheets carry no soybean cake. The cake column of the
# CBS_SOY workbooks is a hand-built estimate of unknown origin whose exports ran 3-10 Mt above
# COMEX from 2007 (2022: 30.7 Mt against 20.35 Mt) and left 2.2 Mt of feed in 2022. It is
# no longer used. The cake row is rebuilt here, every year, from traceable inputs:
#   production = CAKE_EXTRACTION x beans processed (FAO balance, bean column)
#   export     = COMEX heading 2304, national total of the year's municipal export file
#                (the same file step 00 reads; SOY_MUN$exp_cake is its municipal aggregate)
#   feed       = production - export          (domestic supply; imports, stocks, other uses = 0,
#                                              as in the workbooks)
CAKE_EXTRACTION <- 0.75   # tonnes of cake per tonne of beans processed, as in the workbooks
.comex <- read.csv2(paste0(DATA_DIR, "/raw/00/COMEX_exports/EXP_", YEAR, "_MUN_COMEX.csv"),
                    header = TRUE, stringsAsFactors = FALSE)
.comex_2304 <- sum(as.numeric(.comex$KG_LIQUIDO[.comex$SH4 == 2304]), na.rm = TRUE) / 1000
rm(.comex)
.cake_exp  <- sum(SOY_MUN$exp_cake, na.rm = TRUE)
.cake_prod <- CAKE_EXTRACTION * CBS_SOY["bean", "processing"]
.cake_feed <- .cake_prod - .cake_exp
message(sprintf("[00] %d cake row: production %.0f t (%.2f x %.0f), export %.0f t (COMEX 2304: %.0f t), feed %.0f t; workbook had export %.0f t, feed %.0f t",
                YEAR, .cake_prod, CAKE_EXTRACTION, CBS_SOY["bean", "processing"], .cake_exp, .comex_2304,
                .cake_feed, CBS_SOY["cake", "export"], CBS_SOY["cake", "feed"]))
# GUARD: the municipal aggregate must reproduce COMEX 2304, and feed cannot be negative.
if (.comex_2304 <= 0 || abs(.cake_exp - .comex_2304) / .comex_2304 > 0.005)
  stop(sprintf("[00] %d cake guard: municipal cake exports (%.0f t) differ from COMEX heading 2304 (%.0f t) by more than 0.5%%",
               YEAR, .cake_exp, .comex_2304), call. = FALSE)
if (.cake_feed < 0)
  stop(sprintf("[00] %d cake guard: cake feed is negative (production %.0f t - export %.0f t)",
               YEAR, .cake_prod, .cake_exp), call. = FALSE)
CBS_SOY["cake", ] <- 0
CBS_SOY["cake", "production"]      <- .cake_prod
CBS_SOY["cake", "export"]          <- .cake_exp
CBS_SOY["cake", "feed"]            <- .cake_feed
CBS_SOY["cake", "domestic_supply"] <- .cake_feed

CBS_SOY<- mutate(CBS_SOY, stock_addition = -stock_withdrawal)


# investigate structure of CBS ---------------------------------------------------------------------------

# supply side:
CBS_SOY$domestic_supply
CBS_SOY <- mutate(CBS_SOY, dom_supply_side = production - export + import + stock_withdrawal)
# --> domestic_supply = production - export + import + stock_withdrawal

# use side:
CBS_SOY <- mutate(CBS_SOY, dom_use_side = food + feed + other + processing + seed)
# --> domestic_supply = food + feed + other + processing + seed


# consistency checks between FAO and gathered MU data on aggregate -----------------------------------------------

consistency <- data.frame(row.names = c("MU_data","FAO"))

###  check if MU soybean production sums up to FOA data
consistency$prod[1] <- sum(SOY_MUN$prod, na.rm = TRUE)
consistency$prod[2] <- CBS_SOY["bean", "production"]


### check exports
consistency$exp_bean[1] <- sum(SOY_MUN$exp_bean, na.rm = TRUE)
consistency$exp_bean[2] <- CBS_SOY["bean","export"]

consistency$exp_oil[1] <- sum(SOY_MUN$exp_oil, na.rm = TRUE)
consistency$exp_oil[2] <- CBS_SOY["oil", "export"]

consistency$exp_cake[1] <- sum(SOY_MUN$exp_cake, na.rm = TRUE)
consistency$exp_cake[2] <- CBS_SOY["cake", "export"]


### check imports
consistency$imp_bean[1] <- sum(SOY_MUN$imp_bean, na.rm = TRUE)
consistency$imp_bean[2] <- CBS_SOY["bean","import"]

consistency$imp_oil[1] <- sum(SOY_MUN$imp_oil, na.rm = TRUE)
consistency$imp_oil[2] <- CBS_SOY["oil","import"]

consistency$imp_cake[1] <- sum(SOY_MUN$imp_cake, na.rm = TRUE)
consistency$imp_cake[2] <- CBS_SOY["cake", "import"]


### check processing
# compare with preliminary annual soybean processing amount by multiplying daily capacities with 5 weekdays*52
consistency$proc_cap[1] <- sum(SOY_MUN$proc_cap, na.rm = TRUE)*5*52
consistency$proc_cap[2] <- CBS_SOY["bean", "processing"]

consistency$ref_cap[1] <- sum(SOY_MUN$ref_cap, na.rm = TRUE)*5*52
consistency$ref_cap[2] <- CBS_SOY["oil", "production"]


# write data
if (write == TRUE) {
  saveRDS(CBS_SOY, file = paste0(OUT, "CBS_SOY.rds"))
  write.csv2(CBS_SOY, file = paste0(OUT, "CBS_SOY.csv"))
  saveRDS(consistency, file = paste0(OUT, "FAO_consistency.rds"))
}

rm(list=ls())
gc()
