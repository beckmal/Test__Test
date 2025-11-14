# Load_Sets__Core.jl
# Core functionality - loads all modular components

"""
    Load_Sets__Core

Core module that loads all refactored components in correct dependency order.
Use this to get all core functionality including interactive visualizations.

# Included Modules
- Config: Type definitions and path resolution
- Colors: Color definitions and German translations
- Morphology: Image processing operations
- Utilities: Helper functions
- Statistics: Statistical computations
- ConnectedComponents: White region detection and PCA analysis
- DataLoading: Dataset loading and augmentation
- Initialization: Package loading and environment setup
- InteractiveUI: Interactive visualization (Figure 4)

# Usage
```julia
include("Load_Sets__Core.jl")

# Now you have access to all functions:
sets = load_original_sets(306, false)
stats = compute_class_area_statistics(sets, raw_output_type)
mask = extract_white_mask(image; threshold=0.7)
fig = create_interactive_figure(sets, input_type, raw_output_type)
display(GLMakie.Screen(), fig)
```
"""

# Load all modules in dependency order
println("Loading Load_Sets core modules...")

println("  1/8 Loading Initialization...")
include("Load_Sets__Initialization.jl")

println("  2/8 Loading Config...")
include("Load_Sets__Config.jl")

println("  3/8 Loading Colors...")
include("Load_Sets__Colors.jl")

println("  4/8 Loading Morphology...")
include("Load_Sets__Morphology.jl")

println("  5/8 Loading Utilities...")
include("Load_Sets__Utilities.jl")

println("  6/8 Loading Statistics...")
include("Load_Sets__Statistics.jl")

println("  7/8 Loading ConnectedComponents...")
include("Load_Sets__ConnectedComponents.jl")

println("  8/11 Loading DataLoading...")
include("Load_Sets__DataLoading.jl")

println("  9/11 Loading ThinPlateSpline...")
include("Load_Sets__ThinPlateSpline.jl")

println("  10/11 Loading MarkerCorrespondence...")
include("Load_Sets__MarkerCorrespondence.jl")

println("  11/11 Loading InteractiveUI...")
include("Load_Sets__InteractiveUI.jl")

println("✅ Load_Sets core modules loaded successfully")

# Export main data loading function for convenience
println("\n📦 Core functionality available:")
println("  - load_original_sets(length, regenerate)")
println("  - compute_class_area_statistics(sets, raw_output_type)")
println("  - compute_bounding_box_statistics(sets, raw_output_type)")
println("  - compute_channel_statistics(sets, input_type)")
println("  - extract_white_mask(img; threshold, min_area, ...)")
println("  - find_connected_components(img; threshold, kernel_size, ...)")
println("  - morphological_dilate/erode/close/open(mask, kernel_size)")
println("  - find_outliers(data)")
println("  - compute_skewness(values)")
println("  - create_interactive_figure(sets, input_type, raw_output_type)")
println("  - detect_calibration_markers(img; threshold, min_area, ...)")
println("  - dewarp_image_with_markers(img; marker_detection_params, ...)")
println("  - warp_image_tps(img, source_points, target_points)")
println("")
