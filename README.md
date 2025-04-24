# circuitscape_run()

## Introduction

`circuitscape_run()` is a flexible R function designed to **generate** a Circuitscape `.ini` configuration file and **optionally** run Circuitscape *directly from R* using the [JuliaCall](https://cran.r-project.org/package=JuliaCall) package. Circuitscape is a powerful tool for modeling ecological connectivity (e.g., multi-route corridors, pinch points) by treating landscapes as electrical networks. See [Circuitscape](https://docs.circuitscape.org/Circuitscape.jl/latest/) for full documentation.

This function aims to streamline workflows for:
- **Pairwise mode**: computing connectivity/current flow among multiple focal nodes.
- **Advanced mode**: (partial) for one-to-all/all-to-one setups (not heavily tested).
- **Optionally** plotting the resulting cumulative current map in R.

### Key Features

- **Generates** a `.ini` file for Circuitscape based on user inputs.
- **Configures** adjacency (4 or 8 neighbors), solver choice, memory options, and more.
- **Accepts** focal nodes as:
  - **Points** (`.txt` file with `[ID, X, Y]`, no header)
  - **Polygons** represented as **integer-labeled ASCII raster** (one integer per polygon).
- **Runs** Circuitscape in Julia from R, returning logs and optionally plotting the final `_cum_curmap.asc`.

> **Note**: This function focuses on **pairwise** mode for analyzing multi-focal connectivity. Short-circuit polygons (used for advanced grounding or masking) are **not** fully handled here. If you need complex short-circuit polygons, you may need to adapt the generated `.ini`.

---

# Installation & Dependencies

1. **R Packages**  
   - [JuliaCall](https://cran.r-project.org/package=JuliaCall) to call Julia from R.  
   - [raster](https://cran.r-project.org/package=raster) (or [terra]) for reading ASCII rasters, plotting.  
   - Optionally, other packages if your script uses them.

2. **Julia**  
   - Circuitscape is written in Julia.  
   - If you do **not** have Julia installed, the function attempts to install it automatically via `JuliaCall::install_julia()`.  
   - If Julia is already installed, ensure `JuliaCall::julia_setup(installJulia=FALSE)` can find it.

3. **Circuitscape.jl**  
   - The function calls `JuliaCall::julia_install_package_if_needed("Circuitscape")` to install the Julia package.

---

# Function Overview

```r
circuitscape_run <- function(
    cost_file, # path to your ASCII cost/resistance raster.
    # ============ Focal Nodes Arguments ============
    # Exactly one of these should be specified:
    # 1) `focal_points_file`: typical .txt with columns [ID X Y]
    # 2) `focal_polygons_ascii`: .asc with integer IDs for polygons
    focal_points_file = NULL,
    focal_polygons_ascii = NULL,
    
    output_name         = "circuitscape_output",
    output_dir          = getwd(),
    
    # ============ Circuitscape Scenario ============
    scenario            = "pairwise", # or "advanced" for one-to-all / all-to-one modes (though these features have not been tested)
    
    # ============ Basic Habitat/Connectivity Options ============
    habitat_map_is_resistance = TRUE, # If FALSE => interpret cost_file as conductance
    connect_four_neighbors_only   = FALSE, # 4 vs. 8 cell connectivity
    connect_using_avg_resistances = TRUE, # average diagonal cost
    
    # ============ Performance / Memory Options ============
    parallelize = FALSE, # multi-core?
    max_parallel = 0, # how many cores if parallelize = TRUE?
    solver = "cholmod",  # or "cg+amg"
    preemptive_memory_release = FALSE, # can help on large runs if memory-limited
    print_timings = TRUE, # This is not functional in R
    
    # ============ Logging Options ============
    log_level        = "INFO",
    screenprint_log  = TRUE, # This is not functional in R
    
    # ============ Output Options ============
    write_cur_maps = 1,  # 0 => no per-pair current maps, 1 => create them
    write_cum_cur_map_only = TRUE, # focus on final sum of all pairs current map, not all pairs as separate maps as well
    write_volt_maps         = FALSE, # optional: output voltage rasters
    log_transform_maps      = FALSE, # optional: log-transform currents
    compress_grids          = FALSE, # optional: compress output grids
    
    # ============ Advanced Mode Options ============
    ground_file_is_resistance = TRUE,
    remove_src_or_gnd      = "keepall", # or "rmvsrc", "rmvgnd", "rmvall"
    ground_file            = "",
    source_file            = "",
    use_direct_grounds     = FALSE,
    use_unit_currents      = FALSE,
    
    # ============ Execution & Extras ============
    run_in_julia = TRUE, # if FALSE => just write .ini file, user can run manually
    plot         = FALSE, # if TRUE and run_in_julia=TRUE, plot the cum_cur_map
    plot_extent  = NULL,  # e.g., c(xmin, xmax, ymin, ymax) if you want to crop
    plot_zlim    = NULL, # e.g., c(0,10) to crop colour scale limits, or leave NULL
    print_ini_lines = FALSE  # if TRUE => print .ini lines to console
) {

}

# Example run:

```r
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
```

---

## License

This project is licensed under the MIT License.

## Contact

For questions, bug reports, suggestions, or contributions, please contact:
- Richard Gunner
- Email: rgunner@ab.mpg.de
- GitHub: [Richard6195](https://github.com/Richard6195)

