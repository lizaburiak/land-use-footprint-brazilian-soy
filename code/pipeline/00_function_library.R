### soyprint function library ###
# (plotting helpers for the retired benchmark maps/scatters were removed 2026-08;
#  see git history. Remaining users: 10_create_benchmarks.R (ci_funct),
#  21_probability_maps.R + code/prep/prep_mb_tiles.R (burn_rast, gplot_data).)

## nicely named confidence intervals of a matrix returned as df
library(gmodels)
library(dplyr)

ci_funct <- function(x, level = 95, margin = 1, stats = c("lower", "upper", "mean", "se")){
     t(apply(as.matrix(x), margin, function(mat) {ci(mat, confidence = level/100)})) %>%
     as.data.frame() %>%
     rename("upper" = `CI upper`,
            "lower" = `CI lower`,
            "mean" = Estimate,
            "se" = `Std. Error`) %>%
     dplyr::select(one_of(stats))  %>%
     rename_with(~str_c(.,level), everything())
}


# fine-scale footprints --------------------------------------------------------------


# create function to write probability values from transport model in to soy pixels for each MU
# TODO: if a sub-region is selected (e.g. MT), make sure only those tiles are processes and written to file which overlap with the region
burn_rast <- function(rast, poly, class, value, file, zeroes = TRUE, subarea = FALSE){
  # if the target class is not contained in the raster or it does not overlap with the polygon extent, stop
  if(!class %in% rast[] | !ifelse(subarea, st_intersects(st_as_sfc(st_bbox(poly)), st_as_sfc(st_bbox(rast)), sparse = F), TRUE)) {
    return() # next # out <- NULL stop("no soy in tile")
  } else {
    # optional: extract required class --> not needed if raster is already (0/1)
    rast <- clamp(rast, class, class, useValues = FALSE) # rast[rast != class] <- NA ; rast[!is.na(rast)] <- 1
    # optional: round if needed
    poly <- mutate(poly, !!rlang::sym(value) := round(!!rlang::sym(value)))  # value_var <- rlang::sym(value)
    if(!zeroes) poly <- filter(poly, !!rlang::sym(value) > 0 )
    # rasterize
    out <- fasterize::fasterize(poly, rast, field = value) # we could also create a raster brick by value/destination with "by"
    # keep only soy pixels
    out <- out * rast
    # if a file name was specified write and load from file, otherwise load in memory (not suggested)
    if (missing(file)) {
      return(out)
    } else {
      writeRaster(out, filename=file, format="GTiff", datatype="INT1U", overwrite=TRUE)
      raster(file)
    }
  }
}




# function to reshape raster into data frame
# taken from https://stackoverflow.com/questions/47116217/overlay-raster-layer-on-map-in-ggplot2-in-r/47190738#47190738

# this is nice because it only retains information of non-NA cells and their position!
gplot_data <- function(x, maxpixels = 500000)  {
  x <- raster::sampleRegular(x, maxpixels, asRaster = TRUE)
  coords <- raster::xyFromCell(x, seq_len(raster::ncell(x)))
  ## Extract values
  dat <- utils::stack(as.data.frame(raster::getValues(x)))
  names(dat) <- c('value', 'variable')

  dat <- dplyr::as_tibble(data.frame(coords, dat))

  if (!is.null(levels(x))) {
    dat <- dplyr::left_join(dat, levels(x)[[1]],
                            by = c("value" = "ID"))
  }
  dat
}
