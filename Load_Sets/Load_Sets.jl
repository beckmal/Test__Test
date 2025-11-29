# ============================================================================
# Load_Sets.jl - Modular Base Setup
# ============================================================================
# This file provides the base setup for all Load_Sets scripts:
# - Activates the environment
# - Loads all modular components from Load_Sets__Core.jl
# - Loads the dataset (using file-backed memory mapping for efficiency)
# - Defines core variables used by UI and statistics scripts
#
# Use this file as a base for:
# - run_Load_Sets__InteractiveUI.jl
# - run_Load_Sets__BalanceUI.jl
# - run_Load_Sets__StatisticsUI.jl
# ============================================================================

# Explicitly import Base print functions to avoid ambiguity with Bas3 exports
import Base: print, println

import Pkg
Pkg.activate(@__DIR__)
println("=== Load_Sets.jl - Base Setup ===")

# Load all modular components via the core module loader
println("Loading modular components...")
include("Load_Sets__Core.jl")

# All functions from the modular components are now available:
# - From Config: input_type, raw_output_type, output_type, resolve_path
# - From Colors: class_names_de, channel_names_de, get_german_names, get_german_channel_names
# - From Morphology: morphological_dilate, morphological_erode, morphological_close, morphological_open
# - From Utilities: find_outliers, compute_skewness
# - From Statistics: compute_class_area_statistics, compute_bounding_box_statistics, compute_channel_statistics
# - From ConnectedComponents: find_connected_components, extract_white_mask
# - From DataLoading: load_original_sets, MmapImageSet
# - From Initialization: reporters (initialized packages)

println("Loading dataset with file-backed memory mapping...")

# Load dataset files from disk using file-backed mmap
# This creates lightweight wrappers; actual data is loaded on-demand by the OS
const sets = load_original_sets(306, false)
println("Prepared $(length(sets)) image sets (file-backed mmap)")

# Note: With mmap, we don't pre-load inputs/outputs to avoid loading all data into RAM
# Access individual images via sets[i][1] (input) and sets[i][2] (output)
# The OS will automatically page data in/out as needed

# Export convenience dictionaries for German names and colors
const class_names_de = CLASS_NAMES_DE
const channel_names_de = CHANNEL_NAMES_DE

println("=== Base setup complete ===")
println("Variables available:")
println("  - sets: $(length(sets)) image pairs (file-backed mmap)")
println("  - Access via sets[i][1] (input), sets[i][2] (output), sets[i][3] (index)")
println("  - class_names_de: German class name mappings")
println("  - channel_names_de: German channel name mappings")
println("")
