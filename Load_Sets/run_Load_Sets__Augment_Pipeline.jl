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
const TOTAL_LENGTH = 1000  # Full dataset

# Base patch size (height, width) - patches grow from this
const BASE_SIZE = (50, 100)

# Maximum size multiplier (max size = BASE_SIZE × MAX_MULTIPLIER)
const MAX_MULTIPLIER = 4

# Per-class foreground thresholds (%)
const FG_THRESHOLDS = Dict{Symbol, Float64}(
    :scar       => 50.0,
    :redness    => 50.0,
    :hematoma   => 50.0,
    :necrosis   => 50.0,
    :background => 100.0
)

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
    aug_inputs, aug_outputs, aug_image_indices, aug_metadata_list = generate_balanced_sets(
        sets = sets,
        source_info = source_info,
        target_distribution = TARGET_DIST,
        total_length = TOTAL_LENGTH,
        base_size = BASE_SIZE,
        max_multiplier = MAX_MULTIPLIER,
        fg_thresholds = FG_THRESHOLDS,
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
    aug_inputs,
    aug_outputs,
    aug_metadata_list,
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

# Print growth statistics
println("\n=== Growth Statistics ===")
multiplier_counts = Dict{Int, Int}()
growth_counts = Dict{Int, Int}()

for m in aug_metadata_list
    multiplier_counts[m.size_multiplier] = get(multiplier_counts, m.size_multiplier, 0) + 1
    growth_counts[m.growth_iterations] = get(growth_counts, m.growth_iterations, 0) + 1
end

println("\nSize distribution:")
for mult in sort(collect(keys(multiplier_counts)))
    count = multiplier_counts[mult]
    pct = round(100 * count / length(aug_metadata_list), digits=1)
    println("  $(mult)× ($(BASE_SIZE[1]*mult)×$(BASE_SIZE[2]*mult)): $count samples ($pct%)")
end

println("\nGrowth iterations:")
for iters in sort(collect(keys(growth_counts)))
    count = growth_counts[iters]
    pct = round(100 * count / length(aug_metadata_list), digits=1)
    println("  $iters iterations: $count samples ($pct%)")
end

max_reached_count = count(m -> m.max_size_reached, aug_metadata_list)
println("\nMax size reached: $max_reached_count samples")

println("="^70)
