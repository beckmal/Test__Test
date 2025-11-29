# ============================================================================
# run_Load_Sets__Regenerate_Original.jl
# ============================================================================
# Runner script to regenerate the original dataset from source images.
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/run_Load_Sets__Regenerate_Original.jl
#
# This will regenerate all 306 original images at full resolution (resize_ratio=1)
# ============================================================================

println("=== Original Dataset Regeneration ===")
println("")

# Configuration
const TOTAL_IMAGES = 306
const RESIZE_RATIO = 1  # Full resolution (no downscaling)

println("Configuration:")
println("  Total images: $(TOTAL_IMAGES)")
println("  Resize ratio: $(RESIZE_RATIO) (1 = full resolution)")
println("")

# Load environment (but don't load the cached sets)
println("Loading environment...")
include("Load_Sets__Initialization.jl")
include("Load_Sets__Config.jl")
include("Load_Sets__DataLoading.jl")

output_path = joinpath(base_path, "original")
println("")
println("Output directory: $(output_path)")
println("")

# Regenerate original sets
println("=== Regenerating Original Dataset ===")
println("This will take a while for $(TOTAL_IMAGES) full-resolution images...")
println("")

@time begin
    sets = load_original_sets(TOTAL_IMAGES, true; resize_ratio=RESIZE_RATIO)
end

# Print summary
println("")
println("="^70)
println("REGENERATION COMPLETE")
println("="^70)
println("Total images regenerated: $(length(sets))")

# Check first image size
if length(sets) > 0
    first_input = sets[1][1]
    input_data = data(first_input)
    println("Image dimensions: $(size(input_data, 1)) x $(size(input_data, 2))")
end

println("Output directory: $(output_path)")
println("="^70)
