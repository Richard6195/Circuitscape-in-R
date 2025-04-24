######## Circuitscape in R ; https://docs.circuitscape.org/Circuitscape.jl/latest/

# Richard Gunner ; richard.m.g@hotmail.com

# A Flexible R Function to Write the .ini and Run Circuitscape.

### Main Function Signature:
  
  # cost_file: path to your ASCII or GeoTIFF cost/resistance raster.
  # focal_nodes_file: path to your .txt with focal points (no column/row names) or ACII (ASCII file as the "focal node polygon" input) 
  # scenario: "pairwise" is typical for multi-focal connectivity.  'advanced' mode for one-to-all / all-to-one requires additional arguments (ground_file, source_file, remove_src_or_gnd, use_direct_grounds, etc.)
  # habitat_map_is_resistance: set TRUE if your file is a resistance raster; if it’s conductance, set FALSE.
  # connect_four_neighbors_only, connect_using_avg_resistances: adjacency decisions.
  # parallelize, max_parallel, solver: performance parameters. Alternative solver = 'cg+amg'
  # write_cur_maps: 0 or 1 for whether to output each pair’s current map.
  # write_cum_cur_map_only: whether to only write the combined cumulative current map.
  # log_transform_maps: whether to log-transform the results.
  # run_in_julia: if TRUE, calls Circuitscape immediately. If FALSE, just writes the .ini file for manual usage.

# ini_lines: We piece together lines of text that correspond to Circuitscape keys. We coerce booleans to “true”/“false” strings using tolower(as.character(...)).
# Write: We write the .ini file to output_dir.
# Run: If run_in_julia is TRUE, we do JuliaCall::julia_call("compute", ini_path) immediately, capturing the result. The user can parse or load the output raster afterward.

circuitscape_run <- function(
    cost_file,
    # ============ Focal Nodes Arguments ============
    # Exactly one of these should be specified:
    # 1) `focal_points_file`: typical .txt with columns [ID X Y]
    # 2) `focal_polygons_ascii`: .asc with integer IDs for polygons
    focal_points_file = NULL,   # path to ASCII or text of point coordinates
    focal_polygons_ascii = NULL,# path to an integer-labeled ASCII raster for polygon-based focal nodes
    
    output_name         = "circuitscape_output",
    output_dir          = getwd(),
    
    # ============ Circuitscape Scenario ============
    scenario            = "pairwise", # or "advanced" for one-to-all / all-to-one modes
    
    # ============ Basic Habitat/Connectivity Options ============
    habitat_map_is_resistance = TRUE, # If FALSE => interpret cost_file as conductance
    connect_four_neighbors_only   = FALSE, # 4 vs. 8 cell connectivity
    connect_using_avg_resistances = TRUE, # average diagonal cost
    
    # ============ Performance / Memory Options ============
    parallelize = FALSE, # multi-core
    max_parallel = 0, # how many cores
    solver = "cholmod", # or "cg+amg" [read circuitscape documentation; https://docs.circuitscape.org/Circuitscape.jl/latest/]
    preemptive_memory_release = FALSE,   # can help on large runs if memory-limited
    print_timings          = TRUE,       # prints additional run timing info - This doesn't actually do anything in R
    
    # ============ Logging Options ============
    log_level        = "INFO", # DEBUG, INFO, WARNING, ERROR, CRITICAL
    screenprint_log  = TRUE,  # if TRUE => progress messages printed to console - This doesn't actually do anything in R
    
    # ============ Output Options ============
    write_cur_maps = 1,   # 0 => no per-pair current maps, 1 => create them
    write_cum_cur_map_only = TRUE,  # focus on final sum of all pairs
    write_volt_maps         = FALSE, # optional: output voltage rasters
    log_transform_maps      = FALSE, # optional: log-transform currents
    compress_grids          = FALSE, # optional: compress output grids
    
    # ============ Advanced Mode Options ============
    # advanced: if user sets 'scenario="advanced"', these matter
    ground_file_is_resistance = TRUE,
    remove_src_or_gnd      = "keepall",  # or "rmvsrc", "rmvgnd", "rmvall"
    ground_file            = "",
    source_file            = "",
    use_direct_grounds     = FALSE,
    use_unit_currents      = FALSE,
    
    # ============ Execution & Extras ============
    run_in_julia = TRUE,  # if FALSE => just write .ini file, user can run manually
    plot               = FALSE,  # if TRUE and run_in_julia=TRUE, plot the cum_cur_map
    plot_extent        = NULL,   # e.g., c(xmin, xmax, ymin, ymax) if you want to crop
    plot_zlim          = NULL,   # e.g., c(0,10) to crop colour scale limits, or leave NULL
    print_ini_lines    = FALSE   # if TRUE => print .ini lines to console
) {
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # 1) Validate Focal Inputs
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # We can't handle both points AND polygons at once in a straightforward way (unless advanced usage).
  # If scenario = "pairwise" or "advanced", we need at least one of them.
  
  both_specified <- !is.null(focal_points_file) && !is.null(focal_polygons_ascii)
  none_specified <- is.null(focal_points_file) && is.null(focal_polygons_ascii)
  
  if (both_specified) {
    stop("Please specify EITHER `focal_points_file` OR `focal_polygons_ascii`, not both.")
  }
  
  if (none_specified) {
    stop("No focal node input provided. Supply either `focal_points_file` (points) or `focal_polygons_ascii` (integer-coded ASCII raster).")
  }
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # 2) Build the .ini lines for scenario + habitat + connections
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  # (A) Scenario lines
  scenario_lines <- c(
    "[Circuitscape mode]",
    paste0("scenario = ", scenario),
    "data_type = raster"
  )
  
  # (B) Habitat block
  habitat_lines <- c(
    "[Habitat raster or graph]",
    paste0("habitat_file = ", cost_file),
    paste0("habitat_map_is_resistances = ", tolower(as.character(habitat_map_is_resistance)))
  )
  
  # (C) Connection scheme
  connection_lines <- c(
    "[Connection scheme for raster habitat data]",
    paste0("connect_four_neighbors_only = ", tolower(as.character(connect_four_neighbors_only))),
    paste0("connect_using_avg_resistances = ", tolower(as.character(connect_using_avg_resistances)))
  )
  
  # (D) Pairwise or advanced focal node lines
  # Circuitscape uses "point_file = ..." for either actual point data
  # OR an ASCII polygon raster if `use_polygons = true`.
  
  focal_lines <- c("[Options for pairwise and one-to-all and all-to-one modes]")
  
  # If user gave points or polygons (ASCII), either way it's "point_file = <...>"
  # Circuitscape lumps integer-labeled ASCII into polygons if "use_polygons=false" in the short-circuit block
  # but we still effectively treat them as polygons for pairwise connectivity.
  
  point_file_val <- if (!is.null(focal_points_file)) {
    focal_points_file
  } else {
    # If user tries to pass a .shp for focal_polygons_ascii => error
    if (tools::file_ext(focal_polygons_ascii) == "shp") {
      stop("ERROR: For pairwise polygon nodes, provide an integer-coded ASCII file, not a shapefile.")
    }
    focal_polygons_ascii
  }
  
  focal_lines <- c(
    focal_lines,
    paste0("point_file = ", point_file_val),
    "use_included_pairs = False"
  )
  
  # (E) Advanced mode lines (only relevant if scenario="advanced")
  advanced_lines <- c(
    "[Options for advanced mode]",
    paste0("ground_file_is_resistances = ", tolower(as.character(ground_file_is_resistance))),
    paste0("remove_src_or_gnd = ", remove_src_or_gnd),
    if (nzchar(ground_file))  paste0("ground_file = ", ground_file) else "# ground_file not provided",
    if (nzchar(source_file))  paste0("source_file = ", source_file) else "# source_file not provided",
    paste0("use_unit_currents = ", tolower(as.character(use_unit_currents))),
    paste0("use_direct_grounds = ", tolower(as.character(use_direct_grounds)))
  )
  
  # (F) Output options
  output_lines <- c(
    "[Output options]",
    paste0("output_file = ", file.path(output_dir, paste0(output_name, ".out"))),
    paste0("log_file = ", file.path(output_dir, paste0(output_name, ".log"))),
    paste0("profiler_log_file = ", file.path(output_dir, paste0(output_name, "_rusages.log"))),
    paste0("write_cur_maps = ", write_cur_maps),
    paste0("write_cum_cur_map_only = ", tolower(as.character(write_cum_cur_map_only))),
    paste0("write_volt_maps = ", tolower(as.character(write_volt_maps))),
    paste0("log_transform_maps = ", tolower(as.character(log_transform_maps))),
    paste0("compress_grids = ", tolower(as.character(compress_grids)))
  )
  
  # (G) Calculation options
  calculation_lines <- c(
    "[Calculation options]",
    "low_memory_mode = false",  # user can add argument if desired
    paste0("parallelize = ", tolower(as.character(parallelize))),
    paste0("max_parallel = ", max_parallel),
    paste0("solver = ", solver),
    paste0("preemptive_memory_release = ", tolower(as.character(preemptive_memory_release))),
    paste0("print_timings = ", if (print_timings) "1" else "0")
  )
  
  # (H) Logging options
  logging_lines <- c(
    "[Logging Options]",
    paste0("log_level = ", log_level),
    paste0("screenprint_log = ", tolower(as.character(screenprint_log)))
  )
  
  # (I) Short-circuit polygons block
  # We do NOT use these for pairwise polygon focal nodes, so we keep "use_polygons=false" here
  # That ensures Circuitscape does NOT interpret the ASCII as short-circuit polygons.
  polygons_lines <- c(
    "[Short circuit regions (aka polygons)]",
    "polygon_file = (Browse for a short-circuit region file)",
    "use_polygons = false"
  )
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # 3) Combine all lines into a single vector
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  ini_lines <- c(
    scenario_lines,
    "",
    habitat_lines,
    "",
    connection_lines,
    "",
    focal_lines,
    ""
  )
  
  if (tolower(scenario) == "advanced") {
    ini_lines <- c(ini_lines, advanced_lines, "")
  }
  
  ini_lines <- c(
    ini_lines,
    output_lines,
    "",
    calculation_lines,
    "",
    logging_lines,
    "",
    polygons_lines
  )
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # 4) Write the .ini file to disk
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ini_path <- file.path(output_dir, paste0(output_name, ".ini"))
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)  # ensure folder
  writeLines(ini_lines, ini_path)
  
  message("Wrote Circuitscape config to: ", ini_path)
  
  if (print_ini_lines) {
    cat("=== Circuitscape .INI contents ===\n")
    cat(ini_lines, sep = "\n")
    cat("\n=== End of .INI ===\n\n")
  }
  
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # 5) Optionally run Circuitscape via Julia
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  if (!run_in_julia) {
    message("Circuitscape .ini file created. Set run_in_julia=TRUE to compute automatically.")
    return(invisible(NULL))
  }
  # Otherwise, run Circuitscape in Julia
    pkgs_required <- c("JuliaCall", "raster")
    for (pkg in pkgs_required) {
      if (!require(pkg, character.only = TRUE)) {
        install.packages(pkg, dependencies = TRUE, type = "source")
        suppressMessages(library(pkg, character.only = TRUE))
      } else {
        suppressMessages(library(pkg, character.only = TRUE))
      }
    }
    
    installed_pkgs <- row.names(installed.packages())
    missing_pkgs   <- setdiff(pkgs_required, installed_pkgs)
    if (length(missing_pkgs) > 0) {
      stop("The following required packages are not installed: ",
           paste(missing_pkgs, collapse = ", "))
    }
    
     # Installs Julia if not present
    tryCatch(
      {
        JuliaCall::julia_setup(installJulia = FALSE)
      },
      error = function(e) {
        # If we got here, it means julia_setup couldn't find an installed Julia
        message("Julia not found. Installing now...")
        JuliaCall::install_julia()
        JuliaCall::julia_setup(installJulia = FALSE)
      }
    )
    JuliaCall::julia_install_package_if_needed("Circuitscape")
    JuliaCall::julia_library("Circuitscape")
    
    old_wd <- getwd()
    setwd(output_dir)
    on.exit(setwd(old_wd), add = TRUE)
    
    message("Running Circuitscape with scenario='", scenario,
            "', use_polygons=", use_polygons_value,
            " for point_file='", point_file_value, "' ...")
    
    
    output <- capture.output({
      result <- JuliaCall::julia_call("compute", ini_path)
    })
    # see the captured lines
    cat(output, sep="\n")
    
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # 6) If plot=TRUE, load & plot the cumulative current map
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    
    # Typically, Circuitscape writes <output_name>_cum_curmap.asc if you are in pairwise
    # and have write_cum_cur_map_only=TRUE or write_cur_maps=1.
    if (plot) {
      # Build the expected path
      cum_map_asc <- file.path(output_dir, paste0(output_name, "_cum_curmap.asc"))
      
      if (file.exists(cum_map_asc)) {
        # load as a RasterLayer
        cum_map <- raster::raster(cum_map_asc)
        
        # optionally crop if user gave an extent
        if (!is.null(plot_extent) && length(plot_extent) == 4) {
          # c(xmin, xmax, ymin, ymax)
          e <- raster::extent(plot_extent[1], plot_extent[2], plot_extent[3], plot_extent[4])
          cum_map <- raster::crop(cum_map, e)
        }
        
        # Plot with optional zlim
        if (is.null(plot_zlim)) {
          raster::plot(cum_map,
                       main = paste("Circuitscape Cumulative Current:", output_name),
                       col = terrain.colors(100))
        } else {
          raster::plot(cum_map,
                       main = paste("Circuitscape Cumulative Current:", output_name),
                       col = terrain.colors(100),
                       zlim = plot_zlim)
        }
        
      } else {
        warning("Could not find the expected cumulative current map: ", cum_map_asc,
                "\nCheck if Circuitscape generated a different name or if 'write_cum_cur_map_only=FALSE'.")
      }
    }
    
    
    
    # Return them in a list so the user can inspect:
    return(
      invisible(result = result)
    )
}

####################################################################################################################################################################################################################
# Example run

setwd("xxx") # Set working directory to where data files are.

res <- circuitscape_run(
  cost_file          = "myCostSurface.asc",
  focal_points_file  = "myPoints.txt",
  output_name        = "ExampleCircuitscape",
  run_in_julia       = TRUE,
  plot               = TRUE,
  plot_extent        = c(550000, 560000, 915000, 925000),  # optional
  plot_zlim          = c(0, 20),                           # optional
  print_ini_lines    = TRUE,
  parallelize = TRUE, # multi-core
  max_parallel = 4, # how many cores
  solver = "cholmod",
  write_cum_cur_map_only = TRUE
)
