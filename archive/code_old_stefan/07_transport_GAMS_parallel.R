## running the inter-modal transport optimization in parallel with different input paramter settings

library(doParallel)
library(parallel)
library(foreach)
library(dplyr)
library(readr)
library(stringr)

library(reshape2)
library(gdxrrw) # if not installed, tun install_github("GAMS-dev/gdxrrw/gdxrrw")
library(gdxdt)
library(tidyr)
library(tibble)

# initialize external GDX libraries
igdx("~/gams37.1_linux_x64_64_sfx") 

# prepare constant base data (independent of iteration) ----------------------------------------

# load data
SOY_MUN <- readRDS("results/intermediate/SOY_MUN_fin.rds")
load("results/intermediate/stations.Rdata")
load("results/intermediate/ports.Rdata")
load("results/intermediate/cargo_long.Rdata")
load("results/intermediate/dist_matrices.Rdata")

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

# excess supply and demand
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

# export & processing demand
export_processing <- mutate(SOY_MUN, exp_proc_bean = exp_bean + proc_bean) %>% 
  dplyr::select(c(co_mun, c(exp_proc_bean, exp_oil, exp_cake))) %>% 
  rename("a" = "co_mun", 
         "bean" = "exp_proc_bean", 
         "oil" = "exp_oil", 
         "cake" = "exp_cake")

# products
products <- c("bean","oil", "cake")


# put data in gdx-conformable format 

## sets: products, MUs, train stations, ports
product_lst <- list(name='product',  type = 'set', uels=list(products), ts='products')#, te = matrix(ncol = 1, SOY_MUN$nm_mun))
a_lst <-   list(name='a',  type = 'set', uels=list(SOY_MUN$co_mun),ts='municipalities')#, te = matrix(ncol = 1, SOY_MUN$nm_mun))
w1_list <- list(name='w1', type = 'set', uels=list(ports_orig$cdi_tuaria),ts='origin ports')
w2_list <- list(name='w2', type = 'set', uels=list(ports_dest$cdi_tuaria),ts='destination ports')
r1_list <- list(name='r1', type = 'set', uels=list(stations_orig$CodigoTres),ts='origin stations')#, te =  matrix(ncol = 1, stations_orig$name))
r2_list <- list(name='r2', type = 'set', uels=list(stations_dest$CodigoTres),ts='destination stations')#, te =  matrix(ncol = 1, stations_dest$name))

## parameters: supply, demand, export+processing demand, transport costs, route capacities
# Note that excess supply and demand is used
supply <- list(name='supply',val=as.matrix(excess_supply[,2:4]), uels=list(excess_supply$a, products),
               dim=2, domains = c("a", "product"), form='full',type='parameter',ts='demand quantities')

demand  <- list(name='demand',val=as.matrix(excess_demand[,2:4]), uels=list(excess_demand$a, products),
                dim=2, domains = c("a", "product"), form='full',type='parameter',ts='demand quantities')

exp_proc <- list(name='exp_proc',val=as.matrix(export_processing[,2:4]), uels=list(export_processing$a, products),
                 dim=2,domains = c("a", "product"), form='full',type='parameter',ts='export and processing demand')


# capacity constraints for rail and water
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


wgdx.lst("results/outputs/gams/GAMS_base_data.gdx", 
           list(product_lst, a_lst, 
                w1_list, w2_list, r1_list, r2_list, 
                supply, demand, exp_proc, 
                cap_w, cap_r))



# run parallel iterations with randomized cost parameters ------------------------------------------------

dir.create("./results/outputs/gams/bs_tmp", showWarnings = FALSE, recursive = TRUE)
dir.create("./results/outputs/gams/bs_res", showWarnings = FALSE, recursive = TRUE)

tibble(id = integer(), 
       c_road = double(), c_rail_short = double(), c_rail_long = double(), c_water = double(), m_switch = double(),
       objval = double()) %>% 
  write_csv(file = "./results/outputs/gams/bs_res/bs_par.csv", col_names = TRUE)

cl <- makeCluster(detectCores(), type = "FORK")
registerDoParallel(cl)

## Declare that parallel RNG should be used for in a parallel foreach() call.
## %dorng% will still result in parallel processing; it uses %dopar% internally.
## see https://stackoverflow.com/questions/43299428/foreach-doparallel-and-random-generation
library("doRNG")

system.time(
  #par_bs <- foreach(
  #  i = 1:2, 
  #  .combine = 'bind_rows'
  foreach(
    i = 1:1000
  #) %dopar% {
   ) %dorng% {
    
     cat("\n iteration", i, "\n")
     
    # create temporary files to write intermediate files to
    gdx_cost <- tempfile(tmpdir = "./results/outputs/gams/bs_tmp", fileext = ".gdx")
    gdx_out <- tempfile(tmpdir = "./results/outputs/gams/bs_tmp", fileext = ".gdx")
    
    # random par ------------------------------------------------------------
    # c_road <- rnorm(1, 0.1624, 0.01)
    # c_rail_short <- rnorm(1, 0.0792, 0.01) # < 1000 km
    # c_rail_long <- rnorm(1, 0.0614, 0.01) # > 1000 km
    # c_water <- rnorm(1, 0.027, 0.01)
    # m_switch <- rnorm(1, 2.22, 0.1) # intermodal cargo transfer markup (for switching modes)
    
    c_road <- runif(1, 0.0129, 0.1738)
    c_rail_short <- runif(1, 0.0055, 0.0645) # < 1000 km
    c_rail_long <- c_rail_short # no longer have this distinction!
    c_water <- runif(1, 0.0044, 0.0316)
    m_switch <- runif(1, 0.7358, 2.5734) # intermodal cargo transfer markup (for switching modes)

    # assign cost values to compute cost matrices
    # NOTE: one could also avoid this by doing the multiplöication directly in GAMS
    ## road 
    road_cost_MUN <- c_road * road_dist_MUN / 1000
    road_cost_MUN_stat <- c_road * road_dist_MUN_stat / 1000 + m_switch # adding switching cost 
    road_cost_MUN_port <- c_road * road_dist_MUN_port / 1000 + m_switch
    road_cost_stat_MUN <- c_road * road_dist_stat_MUN / 1000 + m_switch
    road_cost_port_MUN <- c_road * road_dist_port_MUN / 1000 + m_switch
    ## rail 
    rail_cost <- rail_dist
    rail_cost[rail_dist < 1000000]  <- rail_dist[rail_dist < 1000000] * c_rail_short / 1000
    rail_cost[rail_dist >= 1000000] <- rail_dist[rail_dist >= 1000000] * c_rail_long / 1000
    ## water 
    water_cost <- water_dist * c_water / 1000
    
    # write GDX -----------------------------------------------------------
    
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

    # write
   wgdx.lst(gdx_cost, 
            list(C_a_b, C_a_w1, C_a_r1, C_w2_b, C_r2_b, C_r1_r2, C_w1_w2))
  

    # RUN GAMS ------------------------------------------------------
    
    # define file path of .gms file in correct format
    gms <- paste0(getwd(),"/code/old/gams/transport_model_Brazil_intermod_par.gms")
    isWindows <- ("mingw32" == R.Version()$os)
    if (isWindows) gms <- gsub("/","\\",gms,fixed=TRUE)
    # base input file
    ingdx <- paste0(getwd(),"/results/outputs/gams/GAMS_base_data.gdx")
    if (isWindows) ingdx <- gsub("/","\\",ingdx,fixed=TRUE)
    # cost input file
    costgdx <- gdx_cost
    if (isWindows) costgdx <- gsub("/","\\",costgdx,fixed=TRUE)
    # output file
    outgdx <- gdx_out
    if (isWindows) outgdx <- gsub("/","\\",outgdx,fixed=TRUE)
    
    # RUN model
    gams(paste0(gms, " --INPUT=", ingdx, " --COST=", costgdx,  " --OUTPUT=", outgdx))
    

    # Process output -----------------------------------------------
    X_a_b <-   readgdx(outgdx, "X_a_b")
    X_a_r1 <-  readgdx(outgdx, "X_a_r1")
    X_a_w1 <-  readgdx(outgdx, "X_a_w1")
    X_r1_r2 <- readgdx(outgdx, "X_r1_r2")
    X_w1_w2 <- readgdx(outgdx, "X_w1_w2")
    X_r2_b <-  readgdx(outgdx, "X_r2_b")
    X_w2_b <-  readgdx(outgdx, "X_w2_b")
    totalcost <- rgdx(outgdx, requestList = list(name = "xtotalcost"))$val[1]
    
    ## compile flows from source MU to target MU
    # get flows into wide format matrices per product
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
    
    # obtain rail and water flows from origin to destination MU
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
    
    # back to long
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

    # merge flows from all modes
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
    
    #res <- X_a_b_tot
    
    # write results
    write_rds(X_a_b_tot, file = str_c("./results/outputs/gams/bs_res/",str_pad(i, 5, pad = "0"),".rds"))
    
    # append parameter and objective value information to par file
    tibble(id = i, c_road, c_rail_short, c_rail_long, c_water, m_switch, totalcost) %>% 
      write_csv(file = "./results/outputs/gams/bs_res/bs_par.csv", col_names = FALSE, append = TRUE)
    
    # delete temporary files
    file.remove(gdx_cost)
    file.remove(gdx_out)
    
  }
)

stopCluster(cl)
