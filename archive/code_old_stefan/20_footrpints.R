### calculate footprints on the level of municipalities ###

library(Matrix)
library(data.table)
library(countrycode)

write = TRUE

LA_mass <- readRDS("results/intermediate/FABIO/2013_L_mass.rds")
LB_mass <- readRDS("results/intermediate/FABIO/2013_B_inv_mass.rds")
LA_value <- readRDS("results/intermediate/FABIO/2013_L_value.rds")
LB_value <- readRDS("results/intermediate/FABIO/2013_B_inv_value.rds")
X <- readRDS("results/intermediate/FABIO/X.rds")
X <- X
YA <- readRDS("results/intermediate/FABIO/Y_hybrid.rds")
YA <- YA$`2013`
load("/mnt/nfs_fineprint/tmp/exiobase/pxp/2013_Y.RData")
YB <- as(Y, "sparseMatrix"); rm(Y)
load("/mnt/nfs_fineprint/tmp/exiobase/Y.codes.RData")
load("/mnt/nfs_fineprint/tmp/exiobase/pxp/IO.codes.RData")
E <- readRDS("/mnt/nfs_fineprint/tmp/fabio/v2/E.rds")
E <- E$`2013`
l_mun <- read.csv("data/old/soy_areas_mapbiomas.csv") 
cbs <- readRDS("results/intermediate/FABIO/cbs_final.rds")
areas <- unique(cbs[,.(area_code, area)])
areas_mun <- areas[area_code > 1000,]
regions <- fread("data/old/FABIO/inst/regions_full.csv")
items <- fread("data/old/FABIO/inst/items_full.csv")


# prepare land-use data ------------------------------------------------------------------------

# extend E by municipality land use
l_mun <- as.data.table(l_mun)[,.(year,area,class,co_mun)]
setnames(l_mun, "area", "landuse")
l_mun <- merge(areas_mun, l_mun[class == 39,], by.x = "area_code", by.y = "co_mun", all.x = TRUE)
l_mun[is.na(landuse), `:=`(landuse = 0)]
l_mun[, `:=`(item_code = 2555, class = NULL, year = NULL)]
l_mun <- merge(l_mun, cbs[,.(area_code, item_code, production)], by = c("item_code", "area_code"))
#l_mun <- merge(l_mun, as.data.table(SOY_MUN)[,.(co_mun, area_plant)], by.x = "area_code", by.y = "co_mun")

# intensity:
#l_mun[,landuse := landuse/production]
#l_mun[!is.finite(landuse), landuse := 0]
#l_mun[, production := NULL]

soy_E <- unique(E[item_code %in% c(2555, 2571, 2590), .(item_code, item, comm_code, comm_group, group)])
E_mun <- as.data.table(expand.grid(area_code = areas_mun$area_code, item_code = c(2555, 2571, 2590))) 
E_mun <- merge(E_mun, soy_E, by = "item_code")
E_mun[, area := areas$area[match(area_code, areas$area_code)]]
E_mun <- merge(E_mun, l_mun, by = c("area_code", "area", "item_code"), all.x = TRUE)
E_mun[is.na(landuse), landuse := 0]

E <- rbind(E, E_mun, fill=TRUE)
E <- E[area_code %in% unique(cbs$area_code),]
E <- E[! (item_code %in% c(2555, 2571, 2590) & area_code == 21),]
E[is.na(E)] <- 0
# ensure correct order
setkey(E, area_code, comm_code)


# compute demand-driven production and footprints ------------------------------------

# aggregate final demand categories
# for YA
colnames(YA) <- sub("_.*", "", colnames(YA))
colnames(YA) <-  regions$iso3c[match(as.numeric(colnames(YA)), regions$code)] # change to ISO code
sum_mat <- as(sapply(unique(colnames(YA)),"==",colnames(YA)), "Matrix")*1
YA_country <- YA %*% sum_mat 
# for YB
# convert ISO2 codes to ISO3
Y.codes$ISO3 <- countrycode(Y.codes$`Region Name`, origin = "iso2c", destination = "iso3c")
Y.codes$ISO3[substr(Y.codes$`Region Name`,1,1) == "W"] <- paste0("ROW_",Y.codes$`Region Name`[substr(Y.codes$`Region Name`,1,1) == "W"] )
dimnames(YB) <- list(paste0(IO.codes$Country.Code,"_",IO.codes$Product.Code),Y.codes$ISO3)
sum_mat <- as(sapply(unique(colnames(YB)),"==",colnames(YB)), "Matrix")*1
YB_country <- YB %*% sum_mat 
  

## by consumer country: 

# calculate production embodied in final demand impulse 
PA_mass  <- LA_mass  %*% YA_country
PA_value <- LA_value %*% YA_country
PB_mass  <- LB_mass  %*% YB_country
PB_value <- LB_value %*% YB_country
# append food/nonfood to colnames
colnames(PA_mass) <-  paste0(colnames(PA_mass) ,"_food")
colnames(PA_value) <- paste0(colnames(PA_value),"_food")
colnames(PB_mass) <-  paste0(colnames(PB_mass) ,"_nonfood")
colnames(PB_value) <- paste0(colnames(PB_value),"_nonfood")

# calculate municipal land-use footprints by country
l <- as.vector(E$landuse / X)
l[!is.finite(l)] <- 0
FA_mass  <- l*PA_mass
FA_value <- l*PA_value
FB_mass  <- l*PB_mass 
FB_value <- l*PB_value


## by consumer product: 
YA_product <- as(diag(rowSums(YA_country)), "sparseMatrix")
dimnames(YA_product) <- list(rownames(YA_country), sub(".*_", "", rownames(YA_country)))
sum_mat <- as(sapply(unique(colnames(YA_product)),"==",colnames(YA_product)), "Matrix")*1
YA_product <- YA_product %*% sum_mat
YB_product <- as(diag(rowSums(YB_country)), "sparseMatrix")
dimnames(YB_product) <- list(rownames(YB_country), sub(".*_", "", rownames(YB_country)))
sum_mat <- as(sapply(unique(colnames(YB_product)),"==",colnames(YB_product)), "Matrix")*1
YB_product <- YB_product %*% sum_mat

# calculate production embodied in final demand impulse 
PA_mass_product <-  LA_mass  %*% YA_product
PA_value_product <- LA_value %*% YA_product
PB_mass_product <-  LB_mass  %*% YB_product
PB_value_product <- LB_value %*% YB_product

# calculate municipal land-use footprints by product
l <- as.vector(E$landuse / X)
l[!is.finite(l)] <- 0
FA_mass_product  <-  l*PA_mass_product
FA_value_product <- l*PA_value_product
FB_mass_product  <-  l*PB_mass_product 
FB_value_product <- l*PB_value_product


# for specifically relevant consumer products by country:

# define relevant products:
prod_sel <- list("c110", "c111", "c112", "c114", "c115", "c116", "c117", "c118")
names(prod_sel) <- items$item[match(prod_sel, items$comm_code)]
prod_group_sel <- list("dairy" = c("c110", "c111"), 
                       "meat" = c("c114", "c115", "c116", "c117", "c118"),
                       "meat-dairy" = c("c110", "c111", "c114", "c115", "c116", "c117", "c118"),
                       "meat-dairy-eggs" = c("c110", "c111", "c112", "c114", "c115", "c116", "c117", "c118"))
prod_sel <- c(prod_sel, prod_group_sel)

PA_prod_country <- # lapply(c("mass", "value"), function(alloc){
  sapply(names(prod_sel), function(prod_nm){
    prod <- prod_sel[[prod_nm]]
    YA_prod_country <- YA_country
    YA_prod_country[!grepl(paste(prod,collapse="|"), rownames(YA_prod_country)),] <- 0 
    colnames(YA_prod_country) <- paste0(colnames(YA_prod_country),"_",prod_nm)
    PA_mass_prod_country <- LA_mass  %*% YA_prod_country
    PA_value_prod_country <- LA_value  %*% YA_prod_country
    #FA_mass_prod_country  <- l*PA_mass_prod_country
    #FA_value_prod_country <- l*PA_value_prod_country
    return(list(mass = PA_mass_prod_country, value = PA_value_prod_country))
  }, USE.NAMES = TRUE, simplify = FALSE)
#})

PA_prod_country <- sapply(c("mass", "value"), function(alloc){
  do.call("cbind", lapply(PA_prod_country, function(x) x[[alloc]]))
}, USE.NAMES = TRUE, simplify = FALSE)

FA_prod_country <- lapply(PA_prod_country, function(PA){
  FA <- l*PA
})


P_mass  <- list("A_country" = PA_mass,  "B_country" = PB_mass,  "A_product" = PA_mass_product, "B_product" =  PB_mass_product, "A_product_country" = PA_prod_country$mass)
P_value <- list("A_country" = PA_value, "B_country" = PB_value, "A_product" = PA_value_product, "B_product" = PB_value_product, "A_product_country" = PA_prod_country$value)
F_mass  <- list("A_country" = FA_mass,  "B_country" = FB_mass,  "A_product" = FA_mass_product,  "B_product" = FB_mass_product, "A_prod_country" = FA_prod_country$mass)
F_value <- list("A_country" = FA_value, "B_country" = FB_value, "A_product" = FA_value_product, "B_product" = FB_value_product, "A_prod_country" = FA_prod_country$value)

# Store results -----------------------
if (write){
  saveRDS(P_mass , "results/footprints/P_mass.rds")
  saveRDS(P_value, "results/footprints/P_value.rds")
  saveRDS(F_mass , "results/footprints/F_mass.rds")
  saveRDS(F_value, "results/footprints/F_value.rds")
}

rm(list = ls())
gc()
