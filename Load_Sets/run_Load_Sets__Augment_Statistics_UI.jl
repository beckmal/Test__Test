# ============================================================================
# run_Augment_AllVisualizations.jl
# ============================================================================
# Runner script to generate and save all augmentation visualizations.
# Creates PNG files without displaying interactive windows.
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/run_Augment_AllVisualizations.jl
# ============================================================================

println("=== All Visualizations Runner ===")
println("")

# ============================================================================
# Load Environment
# ============================================================================

println("Loading environment...")
include("Load_Sets.jl")

# Load all UI modules
include("Load_Sets__Augment_ParameterDistributions_UI.jl")
include("Load_Sets__Augment_SourceClassDistribution_UI.jl")
include("Load_Sets__Augment_QualityMetrics_UI.jl")
include("Load_Sets__Augment_SampleGallery_UI.jl")
include("Load_Sets__Augment_SummaryDashboard_UI.jl")

# ============================================================================
# Load Metadata
# ============================================================================

base_path = resolve_path("C:/Syncthing/Datasets")
metadata_dir = joinpath(base_path, "augmented_balanced_metadata")
output_dir = joinpath(base_path, "augmented_balanced")

println("Loading metadata from: $(metadata_dir)")
all_metadata, target_dist = load_augmented_metadata(metadata_dir)

# Configuration (base size - actual sizes are now variable)
const AUGMENTED_SIZE = (50, 100)  # Base size (height, width)

# ============================================================================
# Generate All Figures
# ============================================================================

println("\n=== Generating Visualizations ===")

# Figure 1: Parameter Distributions
println("\n1. Parameter Distributions...")
fig1 = create_augment_parameter_distributions_figure(all_metadata)
save_augment_parameter_distributions_figure(fig1, joinpath(metadata_dir, "augmentation_parameter_distributions.png"))
display(Bas3GLMakie.GLMakie.Screen(), fig1)  # Ensure figure is rendered before saving
# Figure 2: Source/Class Distribution
println("\n2. Source/Class Distribution...")
fig2 = create_augment_source_class_distribution_figure(all_metadata, target_dist, length(sets))
save_augment_source_class_distribution_figure(fig2, joinpath(metadata_dir, "augmentation_source_and_class_distribution.png"))
display(Bas3GLMakie.GLMakie.Screen(), fig2)  # Ensure figure is rendered before saving
# Figure 3: Quality Metrics
println("\n3. Quality Metrics...")
fig3 = create_augment_quality_metrics_figure(all_metadata)
save_augment_quality_metrics_figure(fig3, joinpath(metadata_dir, "augmentation_quality_metrics.png"))
display(Bas3GLMakie.GLMakie.Screen(), fig3)  # Ensure figure is rendered before saving
# Figure 4: Sample Gallery (static version)
println("\n4. Sample Gallery...")
fig4 = create_augment_sample_gallery_figure(all_metadata, output_dir; interactive=false)
save_augment_sample_gallery_figure(fig4, joinpath(metadata_dir, "augmentation_sample_gallery.png"))
display(Bas3GLMakie.GLMakie.Screen(), fig4)  # Ensure figure is rendered before saving
# Figure 5: Summary Dashboard
println("\n5. Summary Dashboard...")
fig5 = create_augment_summary_dashboard_figure(all_metadata, target_dist, length(sets), AUGMENTED_SIZE)
save_augment_summary_dashboard_figure(fig5, joinpath(metadata_dir, "augmentation_summary_dashboard.png"))
display(Bas3GLMakie.GLMakie.Screen(), fig5)  # Ensure figure is rendered before saving
# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^70)
println("VISUALIZATION GENERATION COMPLETE")
println("="^70)
println("Generated 5 visualization files in: $(metadata_dir)")
println("  1. augmentation_parameter_distributions.png")
println("  2. augmentation_source_and_class_distribution.png")
println("  3. augmentation_quality_metrics.png")
println("  4. augmentation_sample_gallery.png")
println("  5. augmentation_summary_dashboard.png")
println("="^70)
