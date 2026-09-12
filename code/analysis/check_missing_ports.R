# Quantify interior soy cargo (ANTAQ) whose origin/destination port is absent
# from the ANTAQ port shapefile (IP.shp) - i.e. the flows Stefan patched with
# his hand-curated ip_add.gpkg. Run from repo root.

suppressMessages({library(sf); library(dplyr)})

ports <- st_read("data/geo/ANTAQ/IP.shp", quiet = TRUE, options = "ENCODING=WINDOWS-1252")

years <- as.integer(sub("Carga.txt", "", basename(Sys.glob("data/geo/ANTAQ/[0-9][0-9][0-9][0-9]Carga.txt"))))

for (yr in sort(years)) {
  cw  <- read.csv2(sprintf("data/geo/ANTAQ/%dCarga.txt", yr), encoding = "UTF-8", stringsAsFactors = FALSE)
  cwc <- read.csv2(sprintf("data/geo/ANTAQ/%dCarga_Conteinerizada.txt", yr), encoding = "UTF-8", stringsAsFactors = FALSE)
  cw <- left_join(cw, cwc, by = "IDCarga")
  cw$co_product <- ifelse(cw$Carga.Geral.Acondicionamento == "Conteinerizada",
                          cw$CDMercadoriaConteinerizada, cw$CDMercadoria)
  cw <- cw %>%
    filter(co_product %in% c(1201, 1507, 2304),
           Tipo.Navegação == "Interior",
           substr(Origem, 1, 2) == "BR",
           substr(Destino, 1, 2) == "BR") %>%
    distinct(Origem, Destino, co_product, VLPesoCargaBruta, .keep_all = TRUE)

  tot <- sum(cw$VLPesoCargaBruta, na.rm = TRUE)
  bad <- filter(cw, !(Origem %in% ports$cdi_tuaria) | !(Destino %in% ports$cdi_tuaria))
  bp  <- sort(table(c(bad$Origem[!(bad$Origem %in% ports$cdi_tuaria)],
                      bad$Destino[!(bad$Destino %in% ports$cdi_tuaria)])), decreasing = TRUE)
  cat(sprintf("%d: total interior soy %.2f Mt | on missing ports: %.2f Mt (%.1f%%) | ports: %s\n",
              yr, tot / 1e6, sum(bad$VLPesoCargaBruta, na.rm = TRUE) / 1e6,
              100 * sum(bad$VLPesoCargaBruta, na.rm = TRUE) / tot,
              paste(names(bp), collapse = ", ")))
}
