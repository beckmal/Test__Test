# ============================================================================
# run_Load_Sets__StatisticsUI.jl
# ============================================================================
# Generates all three dataset statistics figures
#
# Usage:
#   julia --script=run_Load_Sets__StatisticsUI.jl
#
# This script generates three comprehensive statistical visualizations:
# 1. Class Area Statistics (6 axes) - distributions and proportions
# 2. Bounding Box Statistics (9 axes) - width/height/aspect ratio analysis
# 3. RGB Channel Statistics (6 axes) - intensity distributions and correlations
#
# All figures are saved as PNG files in the current directory.
# ============================================================================

println("=== Generating Dataset Statistics Figures ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load statistics UI modules
println("Loading statistics UI modules...")
include("Load_Sets__Class_Statistics_UI.jl")
include("Load_Sets__BBox_Statistics_UI.jl")
include("Load_Sets__Channel_Statistics_UI.jl")

println("\n=== Computing statistics ===")

# Compute class area statistics
println("Computing class area statistics...")
const class_stats = compute_class_area_statistics(sets, raw_output_type)
const classes = class_stats.classes
const bbox_classes = filter(c -> c != :background, classes)

# Compute bounding box statistics
println("Computing bounding box statistics...")
const bbox_stats = compute_bounding_box_statistics(sets, raw_output_type)

# Compute channel statistics
println("Computing channel statistics...")
const channel_stats = compute_channel_statistics(sets, input_type)

println("\n=== Generating figures ===")

# ============================================================================
# Figure 1: Class Statistics
# ============================================================================
println("Generating Figure 1: Class Statistics...")
const stats_fig = create_class_statistics_figure(sets, class_stats, class_names_de)

# Save figure
const stats_filename = "Full_Dataset_Class_Area_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(stats_filename, stats_fig)
Bas3GLMakie.GLMakie.display(Bas3GLMakie.GLMakie.Screen(), stats_fig)
println("✓ Saved: $(stats_filename)")

# ============================================================================
# Figure 2: Bounding Box Statistics
# ============================================================================
println("Generating Figure 2: Bounding Box Statistics...")
const bbox_fig = create_bbox_statistics_figure(sets, bbox_stats, bbox_classes, class_names_de)

# Save figure
const bbox_filename = "Full_Dataset_Bounding_Box_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(bbox_filename, bbox_fig)
Bas3GLMakie.GLMakie.display(Bas3GLMakie.GLMakie.Screen(), bbox_fig)
println("✓ Saved: $(bbox_filename)")

# ============================================================================
# Figure 3: Channel Statistics
# ============================================================================
println("Generating Figure 3: RGB Channel Statistics...")
const channel_fig = create_channel_statistics_figure(sets, inputs, channel_stats, channel_names_de)

# Save figure
const channel_filename = "Full_Dataset_RGB_Channel_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(channel_filename, channel_fig)
Bas3GLMakie.GLMakie.display(Bas3GLMakie.GLMakie.Screen(), channel_fig)
println("✓ Saved: $(channel_filename)")

# ============================================================================
# Summary
# ============================================================================
println("\n=== Statistics Generation Complete ===")
println("Generated 3 comprehensive figures:")
println("  1. $(stats_filename)")
println("  2. $(bbox_filename)")
println("  3. $(channel_filename)")
println("")
println("All statistics are based on $(length(sets)) dataset images.")
println("=== Done ===")
