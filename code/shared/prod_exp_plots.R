# ============================================================================
# Brazil soy production & export trends — bars for volume (Mt) with lines for
# Brazil's share of world production/exports, from FAOSTAT. Interactive helper.
# Inputs : data/raw/{QCL_SOY_FAO,TCL_SOY_FAO}.csv, data/generated/base/regions.csv
# Output : results/figures/soy_trend_bra.pdf
# ============================================================================
# some basic soy statistics on brazilian soy complex

library(readr)
library(dplyr)
library(ggplot2)
library(patchwork)
library(ggtext)

reg <-  read.csv2("data/generated/base/regions.csv", row.names = 1)
soy_prod <- read_csv("data/raw/QCL_SOY_FAO.csv") %>% filter(Area != "China") # China is double-counted
soy_exp <- read_csv("data/raw/TCL_SOY_FAO.csv")  %>% filter(Area != "China") # China is double-counted
reg <- dplyr::select(reg, c(CO_BTD,region)) %>% unique() %>% filter(CO_BTD != 999 ) #& CO_PAIS_ISON3 != 999

soy_prod <- group_by(soy_prod, Item, Year) %>% rename(prod = Value) %>% 
  mutate(prod = prod / 1e6) %>% 
  mutate(prod_share = prod/sum(prod, na.rm = TRUE), .after=prod) %>%
  left_join(reg, by = c("Area Code (FAO)" = "CO_BTD"))

soy_exp <- filter(soy_exp, Element == "Export Quantity", Item == "Soybeans") %>%
  group_by(Item, Year) %>% rename(exp = Value) %>% 
  mutate(exp = exp / 1e6) %>% 
  mutate(exp_share = exp/sum(exp, na.rm = TRUE), .after=exp)

soy_prod_bra <- filter(soy_prod, Area == "Brazil") %>% dplyr::select(-c(Domain, `Domain Code`, Element, `Element Code`, Flag, `Flag Description`, Unit))
soy_exp_bra  <- filter(soy_exp, Area == "Brazil")  %>% dplyr::select(-c(Domain, `Domain Code`, Element, `Element Code`, Flag, `Flag Description`, Unit))
soy_bra <- full_join(soy_prod_bra, soy_exp_bra, by = c("Area Code (FAO)", "Area", "Item Code (FAO)", "Item", "Year Code", "Year")) #"Element Code", "Element",

# plot combined
(comboplot <- ggplot(soy_bra, aes(x=Year)) +
    geom_bar( aes(y=prod, fill = "production"), stat="identity", size=.3,  color="white", alpha=.5) + #fill=absColor1,
    geom_bar( aes(y=exp, fill = "exports"), stat="identity", size=.3, color="white", alpha=0.7) + #fill=absColor2, 
    geom_line( aes(y=prod_share/coeff1, color = "share in world production"), size=1) + #, color=shareColor1
    geom_line( aes(y=exp_share/coeff1, color = "share in world exports"), size=1) + # , color=shareColor2
    scale_fill_manual("  ", values=c("production" = "firebrick", "exports" = "palegreen3")) +
    scale_color_manual(" ", values=c("share in world production" = "darkred", "share in world exports" = "darkgreen")) +
    
    scale_y_continuous(
      
      # Features of the first axis
      name = "Production and export volume in megatons (bars)",
      
      # Add a second axis and specify its features
      sec.axis = sec_axis(~.*coeff1, 
                          name="Share in world production and exports (lines)"),
    ) +
    
    theme_minimal() +
    
    theme(
      axis.title.y = element_text(size = 10, margin = margin(t = 0, r = 10, b = 0, l = 0)),#color = absColor, size=10),
      axis.title.y.right = element_text(size = 10, margin = margin(t = 0, r = 0, b = 0, l = 15)),
      axis.title.x = element_text(size = 10),
      legend.position = "bottom", legend.direction="vertical", legend.margin = margin(t=-23)
    ) +
    
    guides(fill = guide_legend(order = 1, keywidth = 0.5, keyheight = 1, override.aes = list(alpha = 0.4)), 
           color = guide_legend(order = 2, keywidth = 1, keyheight = 1.05))
)

ggsave(comboplot, filename = "results/figures/soy_trend_bra.pdf", height = 11, width = 15, units = "cm")


soy_prod_region <- group_by(soy_prod, region, Year) %>%
  mutate(prod_share_reg = prod/sum(prod, na.rm = TRUE), prod_reg = sum(prod, na.rm = TRUE)) %>% 
  ungroup() %>% group_by(Year) %>%
  mutate(reg_share_global = prod_reg/sum(prod, na.rm = TRUE))
