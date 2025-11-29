# ============================================================================
# run_Augment_Pipeline.jl
# ============================================================================
# Runner script to generate a balanced augmented dataset.
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/run_Augment_Pipeline.jl
#
# Configuration:
#   Edit the constants below to customize the augmentation.
# ============================================================================

println("=== Augmentation Pipeline Runner ===")
println("")

# ============================================================================
# Configuration - Edit these values as needed
# ============================================================================

# Number of augmented samples to generate
const TOTAL_LENGTH = 1000

# Output image size (height, width)
const TARGET_SIZE = (100, 50)

# Source indices to exclude (e.g., bad quality images)
const EXCLUDED_INDICES = Set([8, 16])

# Target class distribution (percentages, must sum to 100)
const TARGET_DIST = Dict{Symbol, Float64}(
    :scar => 15.0,
    :redness => 15.0,
    :hematoma => 30.0,
    :necrosis => 5.0,
    :background => 35.0
)

# ============================================================================
# Load Environment
# ============================================================================

println("Loading environment...")
include("Load_Sets.jl")

# ============================================================================
# Path Configuration
# ============================================================================

base_path = resolve_path("C:/Syncthing/Datasets")
output_dir = joinpath(base_path, "augmented_balanced")
metadata_dir = joinpath(base_path, "augmented_balanced_metadata")

println("Output directory: $(output_dir)")
println("Metadata directory: $(metadata_dir)")

# ============================================================================
# Analyze Source Images
# ============================================================================

println("\n=== Analyzing Source Images ===")
source_info = analyze_source_classes(sets)

println("\nSource Class Distribution Summary:")
println("  Scar:     $(round(mean([s.scar_percentage for s in source_info]), digits=2))%")
println("  Redness:  $(round(mean([s.redness_percentage for s in source_info]), digits=2))%")
println("  Hematoma: $(round(mean([s.hematoma_percentage for s in source_info]), digits=2))%")
println("  Necrosis: $(round(mean([s.necrosis_percentage for s in source_info]), digits=2))%")

# ============================================================================
# Generate Augmented Dataset
# ============================================================================

println("\n=== Generating Augmented Dataset ===")

@time begin
    inputs, outputs, image_indices, metadata_list = generate_balanced_sets(
        sets = sets,
        source_info = source_info,
        target_distribution = TARGET_DIST,
        total_length = TOTAL_LENGTH,
        target_size = TARGET_SIZE,
        excluded_indices = EXCLUDED_INDICES,
        input_type = input_type,
        raw_output_type = raw_output_type
    )
end

# ============================================================================
# Save to Disk
# ============================================================================

println("\n=== Saving Dataset ===")

augmented_sets = save_augmented_dataset(
    inputs,
    outputs,
    metadata_list,
    output_dir,
    metadata_dir;
    target_distribution = TARGET_DIST,
    excluded_indices = EXCLUDED_INDICES,
    memory_map_fn = memory_map
)

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^70)
println("AUGMENTATION COMPLETE")
println("="^70)
println("Total samples generated: $(length(augmented_sets))")
println("Output directory: $(output_dir)")
println("Metadata directory: $(metadata_dir)")
println("="^70)
