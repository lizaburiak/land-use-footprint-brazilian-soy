#!/usr/bin/env Rscript
# Generate a draft parent-group mapping from canonical_companies_raw.csv.
# Output: inputs/00/new/ABIOVE_processing/canonical_companies_with_parents.csv
# This is a DRAFT — user reviews and edits the `parent_group` column.

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

P <- "inputs/00/new/ABIOVE_processing"
raw <- read.csv(file.path(P, "canonical_companies_raw.csv"),
                stringsAsFactors = FALSE, encoding = "UTF-8")

# Normalization: lowercase, strip diacritics, collapse whitespace
norm <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

raw$norm <- norm(raw$company)

# Rule-based parent assignment: each rule maps a regex-on-norm to a parent group.
# Order matters — more specific first. Curated based on known Brazilian crusher
# landscape and observed name variants. User should review every row.
rules <- list(
  # Big multinationals
  list(re = "^bunge$|bunge ",                     parent = "Bunge"),
  list(re = "^adm$|^adm ",                        parent = "ADM"),
  list(re = "^cargill$",                          parent = "Cargill"),
  list(re = "louis dreyfus|^ldc$|^coinbra$",      parent = "Louis Dreyfus Company"),
  list(re = "^cofco$",                            parent = "COFCO"),
  list(re = "^nidera$",                           parent = "COFCO"),  # COFCO acquired Nidera 2014; before that = Nidera
  list(re = "^noble$|noble agri",                 parent = "COFCO"),  # COFCO acquired Noble Agri 2016
  list(re = "^amaggi$|^maggi$",                   parent = "Amaggi"),
  # Major Brazilian players
  list(re = "^caramuru",                          parent = "Caramuru"),
  list(re = "^granol$",                           parent = "Granol"),
  list(re = "^granoleo$|granoleo",                parent = "Granoleo"),
  list(re = "^granosul$",                         parent = "Granosul"),
  list(re = "^bianchini$",                        parent = "Bianchini"),
  list(re = "^oleoplan$",                         parent = "Oleoplan"),
  list(re = "^olvebasa$",                         parent = "Olvebasa"),
  list(re = "^olvego$",                           parent = "Olvego"),
  list(re = "^olvepar$",                          parent = "Olvepar"),
  list(re = "^olfar$",                            parent = "Olfar"),
  list(re = "^brejeiro$",                         parent = "Brejeiro"),
  list(re = "^baldo$",                            parent = "Baldo"),
  list(re = "^bertol$",                           parent = "Bertol"),
  list(re = "^algar agro$",                       parent = "Algar Agro"),
  list(re = "^selecta$",                          parent = "CJ Selecta"),  # acquired by CJ Group 2017
  list(re = "^cj selecta$",                       parent = "CJ Selecta"),
  list(re = "^clarion$",                          parent = "Clarion"),
  list(re = "^root brasil",                       parent = "Clarion"),  # operates Clarion's plant
  # Food/agribusiness conglomerates
  list(re = "^brf$",                              parent = "BRF"),
  list(re = "^sadia$",                            parent = "BRF"),      # Sadia merged with Perdigão -> BRF (2009)
  list(re = "^perdigao$|perdigão",                parent = "BRF"),
  list(re = "^jbs$",                              parent = "JBS"),
  list(re = "^m\\. dias branco$|m dias branco",   parent = "M Dias Branco"),
  # Diplomata / DIP
  list(re = "^diplomata$|dip frangos",            parent = "Diplomata"),
  # Cooperatives (most have crushing as one segment of broader cooperative)
  list(re = "^coamo$",                            parent = "Coamo (coop)"),
  list(re = "^cocamar$",                          parent = "Cocamar (coop)"),
  list(re = "^copacol$",                          parent = "Copacol (coop)"),
  list(re = "^coopavel$",                         parent = "Coopavel (coop)"),
  list(re = "^cooperalfa$",                       parent = "Cooperalfa (coop)"),
  list(re = "^cooperativa.*lar$|cooper\\..*lar$|^lar$|cooperativaagroindustrial lar",
                                                  parent = "C.Vale/Lar (coop)"),
  list(re = "^cooper.*agraria$|cooper\\..*agraria|cooperativaagraria",
                                                  parent = "Cooper Agraria (coop)"),
  list(re = "^comigo$",                           parent = "Comigo (coop)"),
  list(re = "^c\\.vale$|c vale",                  parent = "C.Vale (coop)"),
  list(re = "^camera$",                           parent = "Camera (coop)"),
  list(re = "^ceagro$",                           parent = "Ceagro"),
  # Mid-size private
  list(re = "^sperafico$",                        parent = "Sperafico"),
  list(re = "^giovelli$",                         parent = "Giovelli"),
  list(re = "^imcopa$",                           parent = "Imcopa"),
  list(re = "^sina$",                             parent = "Sina"),
  list(re = "^insol$",                            parent = "Insol"),
  list(re = "^agrenco$",                          parent = "Agrenco"),
  list(re = "^bsbios$",                           parent = "BSBIOS"),
  list(re = "^be8$",                              parent = "BE8"),  # BSBIOS renamed to BE8 (2023)
  list(re = "^3 tentos",                          parent = "3Tentos"),
  list(re = "^fazendao",                          parent = "Fazendão"),
  list(re = "^taua$",                             parent = "Tauá"),
  list(re = "^warpol$",                           parent = "Warpol"),
  list(re = "^sebben$",                           parent = "Sebben"),
  list(re = "^bocchi$",                           parent = "Bocchi"),
  list(re = "^socceppar$|^soccepar$",             parent = "Soccepar"),
  list(re = "^sipal$",                            parent = "Sipal"),
  list(re = "^correcta$",                         parent = "Correcta"),
  list(re = "^dureino$",                          parent = "Dureino"),
  list(re = "^vaccaro$",                          parent = "Vaccaro"),
  list(re = "^zaffari$",                          parent = "Zaffari"),
  list(re = "^lasa$",                             parent = "Lasa"),
  list(re = "^olfar$",                            parent = "Olfar"),
  list(re = "^cereal$",                           parent = "Cereal"),
  list(re = "^carol$",                            parent = "Carol"),
  list(re = "^abc inco|^abc-inco",                parent = "ABC-Inco"),
  list(re = "^braswey$",                          parent = "Braswey"),
  list(re = "^solae do brasil",                   parent = "Solae"),
  list(re = "^mgt do brasil",                     parent = "MGT"),
  list(re = "^cocentral$",                        parent = "Cocentral"),
  list(re = "^ovelpar$",                          parent = "Ovelpar"),
  list(re = "^atlas$",                            parent = "Atlas"),
  list(re = "^araguassu$",                        parent = "Araguassú"),
  list(re = "^nidera$",                           parent = "Nidera (pre-2014)/COFCO"),
  list(re = "^agrodanieli$|^agrodaniele$",        parent = "Agrodanieli"),
  list(re = "^agrex",                             parent = "Agrex do Brasil"),
  list(re = "^agrosoja$",                         parent = "Agrosoja"),
  list(re = "^algodoeira palmeirense|^apsa",      parent = "Algodoeira Palmeirense"),
  list(re = "^estrela$",                          parent = "Estrela"),
  list(re = "^grupal$",                           parent = "Grupal"),
  list(re = "^nossa soja$|^soja nossa$",          parent = "Nossa Soja"),
  list(re = "^portal$",                           parent = "Portal"),
  list(re = "^santa rosa$",                       parent = "Santa Rosa"),
  list(re = "^sodru$",                            parent = "Sodru"),
  list(re = "^udigraos$|^udigrãos$|^udigraos",    parent = "Udigrãos"),
  list(re = "^cooperatv|^coopertradicao|^cooperativa tradicao", parent = "Coop Tradição"),
  list(re = "^coceagro$",                         parent = "Coceagro"),
  list(re = "^comove$",                           parent = "Comove"),
  list(re = "^cooper agraria$",                   parent = "Cooper Agraria"),
  list(re = "^bsbios$|^be8$",                     parent = "BSBIOS/BE8"),
  list(re = "^clw|tesmann",                       parent = "CLW/Tesmann"),
  list(re = "^oleoveg$",                          parent = "Oleoveg"),
  list(re = "^parecis sa$",                       parent = "Parecis"),
  list(re = "^cnh$",                              parent = "CNH"),
  list(re = "^dual$",                             parent = "Dual"),
  list(re = "^agrofoods$",                        parent = "Agrofoods"),
  list(re = "^alianca agricola",                  parent = "Aliança Agricola"),
  list(re = "^lapa$|^grupo potencial|^potencial$",parent = "Grupo Potencial"),
  list(re = "^copasul$",                          parent = "Copasul (coop)"),
  list(re = "^c\\.vale$",                         parent = "C.Vale (coop)"),
  list(re = "^cealv$|^calv$",                     parent = "CEALV")
)

assign_parent <- function(name_norm) {
  for (r in rules) {
    if (grepl(r$re, name_norm, perl = TRUE)) return(r$parent)
  }
  return(NA_character_)
}

raw$parent_group <- vapply(raw$norm, assign_parent, FUN.VALUE = character(1))
raw$needs_review <- is.na(raw$parent_group)

# For unmapped, propose the raw name itself (Title Case) as parent
raw$parent_group[raw$needs_review] <- str_to_title(raw$company[raw$needs_review])

# Reorder for readability
out <- raw %>%
  select(company, parent_group, needs_review, n_plant_years, n_distinct_plants, years) %>%
  arrange(desc(n_plant_years))

cat("\n=== Mapping summary ===\n")
cat("Total raw company names:    ", nrow(out), "\n")
cat("Unique parent groups:       ", length(unique(out$parent_group)), "\n")
cat("Rows needing manual review: ", sum(out$needs_review), "\n\n")

# Show coverage: parent groups by total plant-years (= activity weight)
by_parent <- out %>%
  group_by(parent_group) %>%
  summarise(total_plant_years = sum(n_plant_years),
            distinct_plants_max = max(n_distinct_plants),
            raw_name_variants = n(),
            needs_review = any(needs_review),
            .groups = "drop") %>%
  arrange(desc(total_plant_years)) %>%
  mutate(cum_share = round(cumsum(total_plant_years) / sum(total_plant_years), 3))

cat("Parent-group coverage (covers what % of plant-years):\n")
print(head(by_parent, 30))

write.csv(out, file.path(P, "canonical_companies_with_parents.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
write.csv(by_parent, file.path(P, "parent_groups_summary.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("\nWrote: ", file.path(P, "canonical_companies_with_parents.csv"), "\n", sep="")
cat("Wrote: ", file.path(P, "parent_groups_summary.csv"), "\n", sep="")
