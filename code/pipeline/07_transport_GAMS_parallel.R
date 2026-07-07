## running the inter-modal transport optimization in parallel with different input parameter settings

# year argument (default 2013, range 2000-2022)
YEAR <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(YEAR)) YEAR <- 2013
stopifnot(YEAR >= 2000, YEAR <= 2022)

library(doParallel)
library(parallel)
library(foreach)
library(dplyr)
library(readr)
library(stringr)

library(reshape2)
library(gdxrrw) # if not installed, run install_github("GAMS-dev/gdxrrw/gdxrrw")
library(gdxdt)
library(tidyr)
library(tibble)

# initialize external GDX libraries
igdx("~/gams37.1_linux_x64_64_sfx")

# year-scoped GAMS dirs
gams_base <- paste0("./data/generated/outputs/gams/GAMS_base_data_", YEAR, ".gdx")
bs_tmp_dir <- paste0("./data/generated/outputs/gams/bs_tmp_", YEAR)
bs_res_dir <- paste0("./data/generated/outputs/gams/bs_res_", YEAR)
bs_par_csv <- file.path(bs_res_dir, "bs_par.csv")

# prepare constant base data (independent of iteration) ----------------------------------------

# load data
SOY_MUN <- readRDS(paste0("data/generated/outputs/05_", YEAR, "/SOY_MUN_fin.rds"))
load(paste0("data/generated/outputs/06_", YEAR, "/stations.Rdata"))
load(paste0("data/generated/outputs/06_", YEAR, "/ports.Rdata"))
load(paste0("data/generated/outputs/06_", YEAR, "/cargo_long.Rdata"))
load(paste0("data/generated/outputs/06_", YEAR, "/dist_matrices.Rdata"))

# change MU code to character for GAMS
SOY_MUN$co_mun <- as.character(SOY_MUN$co_mun)

# total supply and demand per MU for each product
supply <- dplyr::select(SOY_MUN, c(co_mun, total_supply_bean:total_supply_cake)) %>%
  rename("a" = "co_mun",
         "bean" = "total_supply_bean",
         "oil" = "total_supply_oil",
         "cake" = "total_supply_cake")
demand <- dplyr::select(SOY_MUN, c(co_mun, total_use_bean:total_use_cake)) %>%
  rename("a" = "co_mun",
         "bean" = "total_use_bean",
         "oil" = "total_use_oil",
         "cake" = "total_use_cake")

excess_supply <- dplyr::select(SOY_MUN, c(co_mun, excess_supply_bean:excess_supply_cake)) %>%
  rename("a" = "co_mun",
         "bean" = "excess_supply_bean",
         "oil" = "excess_supply_oil",
         "cake" = "excess_supply_cake")
excess_demand <- dplyr::select(SOY_MUN, c(co_mun, excess_use_bean:excess_use_cake)) %>%
  rename("a" = "co_mun",
         "bean" = "excess_use_bean",
         "oil" = "excess_use_oil",
         "cake" = "excess_use_cake")

export_processing <- mutate(SOY_MUN, exp_proc_bean = exp_bean + proc_bean) %>%
  dplyr::select(c(co_mun, c(exp_proc_bean, exp_oil, exp_cake))) %>%
  rename("a" = "co_mun",
         "bean" = "exp_proc_bean",
         "oil" = "exp_oil",
         "cake" = "exp_cake")

products <- c("bean","oil", "cake")


# put data in gdx-conformable format

product_lst <- list(name='product',  type = 'set', uels=list(products), ts='products')
a_lst <-   list(name='a',  type = 'set', uels=list(SOY_MUN$co_mun),ts='municipalities')
w1_list <- list(name='w1', type = 'set', uels=list(ports_orig$cdi_tuaria),ts='origin ports')
w2_list <- list(name='w2', type = 'set', uels=list(ports_dest$cdi_tuaria),ts='destination ports')
r1_list <- list(name='r1', type = 'set', uels=list(stations_orig$CodigoTres),ts='origin stations')
r2_list <- list(name='r2', type = 'set', uels=list(stations_dest$CodigoTres),ts='destination stations')

supply <- list(name='supply',val=as.matrix(excess_supply[,2:4]), uels=list(excess_supply$a, products),
               dim=2, domains = c("a", "product"), form='full',type='parameter',ts='demand quantities')

demand  <- list(name='demand',val=as.matrix(excess_demand[,2:4]), uels=list(excess_demand$a, products),
                dim=2, domains = c("a", "product"), form='full',type='parameter',ts='demand quantities')

exp_proc <- list(name='exp_proc',val=as.matrix(export_processing[,2:4]), uels=list(export_processing$a, products),
                 dim=2,domains = c("a", "product"), form='full',type='parameter',ts='export and processing demand')


cap_r <- cargo_rail_long %>%
  rename (r1 = orig, r2 = dest, value = volume) %>%
  mutate(across(r1:product,as.factor))
attr(cap_r,'symName') <- 'cap_r';
attr(cap_r,'ts') <- 'transportation capacities between all stations';
attr(cap_r,'domains') <- c("r1", "r2", "product")

cap_w <- cargo_water_long %>%
  rename (w1 = orig, w2 = dest, value = volume) %>%
  mutate(across(w1:product,as.factor))
attr(cap_w,'symName') <- 'cap_w';
attr(cap_w,'ts') <- 'transportation capacities between all ports';
attr(cap_w,'domains') <- c("w1", "w2", "product")


wgdx.lst(gams_base,
           list(product_lst, a_lst,
                w1_list, w2_list, r1_list, r2_list,
                supply, demand, exp_proc,
                cap_w, cap_r))



# run parallel iterations with randomized cost parameters ------------------------------------------------

dir.create(bs_tmp_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(bs_res_dir, showWarnings = FALSE, recursive = TRUE)

tibble(id = integer(),
       c_road = double(), c_rail_short = double(), c_rail_long = double(), c_water = double(), m_switch = double(),
       objval = double()) %>%
  write_csv(file = bs_par_csv, col_names = TRUE)

cl <- makeCluster(detectCores(), type = "FORK")
registerDoParallel(cl)

library("doRNG")

system.time(
  foreach(
    i = 1:1000
   ) %dorng% {

     cat("\n iteration", i, "\n")

    gdx_cost <- tempfile(tmpdir = bs_tmp_dir, fileext = ".gdx")
    gdx_out <- tempfile(tmpdir = bs_tmp_dir, fileext = ".gdx")

    c_road <- runif(1, 0.0129, 0.1738)
    c_rail_short <- runif(1, 0.0055, 0.0645)
    c_rail_long <- c_rail_short
    c_water <- runif(1, 0.0044, 0.0316)
    m_switch <- runif(1, 0.7358, 2.5734)

    road_cost_MUN <- c_road * road_dist_MUN / 1000
    road_cost_MUN_stat <- c_road * road_dist_MUN_stat / 1000 + m_switch
    road_cost_MUN_port <- c_road * road_dist_MUN_port / 1000 + m_switch
    road_cost_stat_MUN <- c_road * road_dist_stat_MUN / 1000 + m_switch
    road_cost_port_MUN <- c_road * road_dist_port_MUN / 1000 + m_switch
    rail_cost <- rail_dist
    rail_cost[rail_dist < 1000000]  <- rail_dist[rail_dist < 1000000] * c_rail_short / 1000
    rail_cost[rail_dist >= 1000000] <- rail_dist[rail_dist >= 1000000] * c_rail_long / 1000
    water_cost <- water_dist * c_water / 1000

    C_a_b <- list(name='C_a_b',val=road_cost_MUN, uels=dimnames(road_cost_MUN),
                  dim=2, domains = c("a", "b"), form='full',type='parameter',
                  ts='road transportation costs per tkm between all MUs')
    C_a_w1 <- list(name='C_a_w1',val=road_cost_MUN_port, uels=dimnames(road_cost_MUN_port),
                   dim=2, domains = c("a", "w1"), form='full',type='parameter',
                   ts='road transportation costs per tkm between MUs and origin ports')
    C_a_r1  <- list(name='C_a_r1',val=road_cost_MUN_stat, uels=dimnames(road_cost_MUN_stat),
                    dim=2, domains = c("a", "r1"), form='full',type='parameter',
                    ts='road transportation costs per tkm between MUs and origin stations')
    C_w2_b <- list(name='C_w2_b',val=road_cost_port_MUN, uels=dimnames(road_cost_port_MUN),
                   dim=2, domains = c("w2", "b"), form='full',type='parameter',
                   ts='road transportation costs per tkm between MUs and origin ports')
    C_r2_b <- list(name='C_r2_b',val=road_cost_stat_MUN, uels=dimnames(road_cost_stat_MUN),
                   dim=2, domains = c("r2", "b"), form='full',type='parameter',
                   ts='road transportation costs per tkm between MUs and origin ports')
    C_r1_r2 <- list(name='C_r1_r2',val=rail_cost, uels=dimnames(rail_cost),
                    dim=2, domains = c("r1", "r2"), form='full',type='parameter',
                    ts='rail transportation costs per tkm between rail terminals')
    C_w1_w2 <- list(name='C_w1_w2',val=water_cost, uels=dimnames(water_cost),
                    dim=2, domains = c("w1", "w2"), form='full',type='parameter',
                    ts='water transportation costs per tkm between ports')

   wgdx.lst(gdx_cost,
            list(C_a_b, C_a_w1, C_a_r1, C_w2_b, C_r2_b, C_r1_r2, C_w1_w2))


    gms <- paste0(getwd(),"/archive/code_old_stefan/gams/transport_model_Brazil_intermod_par.gms")
    isWindows <- ("mingw32" == R.Version()$os)
    if (isWindows) gms <- gsub("/","\\",gms,fixed=TRUE)
    ingdx <- paste0(getwd(), "/", gams_base)
    if (isWindows) ingdx <- gsub("/","\\",ingdx,fixed=TRUE)
    costgdx <- gdx_cost
    if (isWindows) costgdx <- gsub("/","\\",costgdx,fixed=TRUE)
    outgdx <- gdx_out
    if (isWindows) outgdx <- gsub("/","\\",outgdx,fixed=TRUE)

    gams(paste0(gms, " --INPUT=", ingdx, " --COST=", costgdx,  " --OUTPUT=", outgdx))


    X_a_b <-   readgdx(outgdx, "X_a_b")
    X_a_r1 <-  readgdx(outgdx, "X_a_r1")
    X_a_w1 <-  readgdx(outgdx, "X_a_w1")
    X_r1_r2 <- readgdx(outgdx, "X_r1_r2")
    X_w1_w2 <- readgdx(outgdx, "X_w1_w2")
    X_r2_b <-  readgdx(outgdx, "X_r2_b")
    X_w2_b <-  readgdx(outgdx, "X_w2_b")
    totalcost <- rgdx(outgdx, requestList = list(name = "xtotalcost"))$val[1]

    products <- c("bean","oil", "cake")
    X_a_b_wide <- sapply(products, function(x){
      filter(X_a_b, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = b, values_from = value)  %>%
        arrange(a) %>% column_to_rownames("a") %>%
        dplyr::select(as.character(sort(as.numeric(names(.))))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_a_r1_wide <- sapply(products, function(x){
      filter(X_a_r1, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = r1, values_from = value)  %>%
        arrange(a) %>% column_to_rownames("a") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_r1_r2_wide <- sapply(products, function(x){
      filter(X_r1_r2, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = r2, values_from = value) %>%
        arrange(r1) %>% column_to_rownames("r1") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_r2_b_wide <- sapply(products, function(x){
      filter(X_r2_b, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = b, values_from = value) %>%
        arrange(r2) %>% column_to_rownames("r2") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_a_w1_wide <- sapply(products, function(x){
      filter(X_a_w1, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = w1, values_from = value) %>%
        arrange(a) %>% column_to_rownames("a") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_w1_w2_wide <- sapply(products, function(x){
      filter(X_w1_w2, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = w2, values_from = value) %>%
        arrange(w1) %>% column_to_rownames("w1") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_w2_b_wide <- sapply(products, function(x){
      filter(X_w2_b, product == x) %>% dplyr::select(!product) %>%
        pivot_wider(names_from = b, values_from = value) %>%
        arrange(w2) %>% column_to_rownames("w2") %>%
        dplyr::select(sort(names(.))) %>%
        replace(is.na(.), 0) %>% as("matrix")
    }, USE.NAMES = TRUE, simplify = FALSE)

    X_a_b_r_wide <- Map(function(x,y,z){
      if(min(c(dim(x), dim(y), dim(z))) == 0) {
        NULL
    } else {
      t(t(x)/colSums(x)) %*% t(t(y)/colSums(y)) %*% z
      }
    }, X_a_r1_wide, X_r1_r2_wide, X_r2_b_wide)

    X_a_b_w_wide <- Map(function(x,y,z){
      if(min(c(dim(x), dim(y), dim(z))) == 0) {
        NULL
      } else {
      t(t(x)/colSums(x)) %*% t(t(y)/colSums(y)) %*% z
        }
      },
      X_a_w1_wide, X_w1_w2_wide, X_w2_b_wide)

    X_a_b_r <- do.call(rbind, lapply(products, function(x){
      if (is.null(X_a_b_r_wide[[x]])) {
        data.frame(co_orig = 0, co_dest = 0, product = x, value_rail = 0)
      } else {
      as.data.frame.table(X_a_b_r_wide[[x]], stringsAsFactors = FALSE) %>%
        rename(co_orig = Var1, co_dest = Var2, value_rail = Freq) %>%
        mutate(product = x, .after = co_dest)
      }})) %>%
      filter(value_rail > 0) %>% mutate(across(co_orig:co_dest, as.numeric))

    X_a_b_w <- do.call(rbind, lapply(products, function(x){
      if (is.null(X_a_b_w_wide[[x]])) {
        data.frame(co_orig = 0, co_dest = 0, product = x, value_water = 0)
      } else {
      as.data.frame.table(X_a_b_w_wide[[x]], stringsAsFactors = FALSE) %>%
        rename(co_orig = Var1, co_dest = Var2, value_water = Freq) %>%
        mutate(product = x, .after = co_dest)
        }})) %>%
      filter(value_water > 0) %>% mutate(across(co_orig:co_dest, as.numeric))

    X_a_b_all <- rename(X_a_b, co_orig = a, co_dest = b, value_road = value) %>%
      mutate(co_orig = as.numeric(co_orig), co_dest = as.numeric(co_dest)) %>%
      full_join(X_a_b_r, by = c("co_orig", "co_dest", "product")) %>%
      full_join(X_a_b_w, by = c("co_orig", "co_dest", "product")) %>%
      replace(is.na(.), 0) %>%
      mutate(value_total = value_road + value_rail + value_water)

    rm(X_a_b, X_a_r1, X_a_w1, X_r1_r2, X_w1_w2, X_r2_b, X_w2_b,
       X_a_b_wide, X_a_r1_wide, X_a_w1_wide, X_r1_r2_wide, X_w1_w2_wide, X_r2_b_wide, X_w2_b_wide,
       X_a_b_r_wide, X_a_b_w_wide, X_a_b_r, X_a_b_w)

    X_a_b_tot <- dplyr::select(X_a_b_all, -(value_road:value_water)) %>%
      rename(value = value_total)
    rm(X_a_b_all)

    write_rds(X_a_b_tot, file = str_c(bs_res_dir, "/", str_pad(i, 5, pad = "0"), ".rds"))

    tibble(id = i, c_road, c_rail_short, c_rail_long, c_water, m_switch, totalcost) %>%
      write_csv(file = bs_par_csv, col_names = FALSE, append = TRUE)

    file.remove(gdx_cost)
    file.remove(gdx_out)

  }
)

stopCluster(cl)
