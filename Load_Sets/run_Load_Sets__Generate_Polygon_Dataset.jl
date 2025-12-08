#!/usr/bin/env julia
# run_Load_Sets__Generate_Polygon_Dataset.jl
# Runner script for polygon dataset generation

# Import Base functions explicitly to avoid conflicts
import Base: println, print

println("="^80)
println("Polygon Mask Dataset Generation")
println("="^80)

# ============================================================================
# Configuration
# ============================================================================

const SOURCE_DIR = "C:/Syncthing/MuHa - Bilder"
const OUTPUT_DIR = "C:/Syncthing/Datasets/original_backup_half_res"
const RESIZE_RATIO = 1//2  # Half resolution

# Test mode: set to true to process only one image for validation
# Set to false for full dataset generation
const TEST_MODE = false
const TEST_INDEX = nothing  # Set to specific index (e.g., 1) or nothing for first available

println("\nConfiguration:")
println("  Source: $(SOURCE_DIR)")
println("  Output: $(OUTPUT_DIR)")
println("  Resize: $(RESIZE_RATIO) (half resolution)")
println("  Test mode: $(TEST_MODE)")
if TEST_MODE && TEST_INDEX !== nothing
    println("  Test index: $(TEST_INDEX)")
end

# ============================================================================
# Environment Setup
# ============================================================================

println("\n" * "="^80)
println("Loading Environment...")
println("="^80)

# Load initialization (includes all required packages)
include("Load_Sets__Initialization.jl")
println("✓ Load_Sets__Initialization")

# Load modules in correct order
include("Load_Sets__Config.jl")
println("✓ Load_Sets__Config")

include("Load_Sets__DataLoading.jl")
println("✓ Load_Sets__DataLoading")

include("Load_Sets__PolygonDataset.jl")
println("✓ Load_Sets__PolygonDataset")

# ============================================================================
# Pre-Flight Checks
# ============================================================================

println("\n" * "="^80)
println("Pre-Flight Checks")
println("="^80)

# Resolve paths for cross-platform compatibility
resolved_source = resolve_path(SOURCE_DIR)
resolved_output = resolve_path(OUTPUT_DIR)

println("\nResolved paths:")
println("  Source: $(resolved_source)")
println("  Output: $(resolved_output)")

# Check source directory exists
if !isdir(resolved_source)
    error("Source directory does not exist: $(resolved_source)")
end
println("✓ Source directory exists")

# Check output directory (create if needed)
if !isdir(resolved_output)
    println("⚠ Output directory does not exist, will create: $(resolved_output)")
else
    println("✓ Output directory exists")
    
    # Check for existing files
    existing_files = filter(f -> endswith(f, ".bin") || endswith(f, ".jld2"), readdir(resolved_output))
    if !isempty(existing_files)
        println("⚠ Found $(length(existing_files)) existing dataset files")
        println("  Generation will overwrite files with matching indices")
    end
end

# Scan for polygon masks
print("\nScanning for polygon masks... ")
available_indices = scan_polygon_masks(resolved_source)
println("found $(length(available_indices))")

if isempty(available_indices)
    error("No polygon masks found in source directory!")
end

println("✓ Available indices: $(available_indices[1:min(10, length(available_indices))])")
if length(available_indices) > 10
    println("  ... and $(length(available_indices) - 10) more")
end

# Estimate storage requirements
if TEST_MODE
    estimated_size = 24  # MB per image
    estimated_count = 1
else
    estimated_size = 24 * length(available_indices)  # MB
    estimated_count = length(available_indices)
end

println("\nStorage estimates:")
println("  Images to process: $(estimated_count)")
println("  Estimated storage: $(round(estimated_size / 1000, digits=2)) GB")
println("  (Input: ~8.8MB + Output: ~14.8MB + Metadata: ~8KB per image)")

# ============================================================================
# Dataset Generation
# ============================================================================

println("\n" * "="^80)
println("Dataset Generation")
println("="^80)

# Run generation with timing
@time begin
    generated_indices = generate_polygon_dataset(
        resolved_source,
        resolved_output;
        resize_ratio=RESIZE_RATIO,
        test_mode=TEST_MODE,
        test_index=TEST_INDEX
    )
end

# ============================================================================
# Verification
# ============================================================================

println("\n" * "="^80)
println("Verification")
println("="^80)

# Verify generated files
verification_passed = verify_dataset(resolved_output, generated_indices)

if verification_passed
    println("\n✅ Dataset generation SUCCESSFUL")
else
    println("\n⚠️ Dataset generation completed with WARNINGS")
    println("Check the verification output above for details")
end

# ============================================================================
# Test Loading
# ============================================================================

if verification_passed
    println("\n" * "="^80)
    println("Test Loading with Load_Sets Infrastructure")
    println("="^80)
    
    try
        println("\nAttempting to load generated dataset...")
        
        # Load first image using MmapImageSet
        test_index = generated_indices[1]
        println("Loading image $(test_index)...")
        
        input_bin = joinpath(resolved_output, "$(test_index)_input.bin")
        output_bin = joinpath(resolved_output, "$(test_index)_output.bin")
        meta_jld2 = joinpath(resolved_output, "$(test_index)_meta.jld2")
        
        metadata = JLD2.load(meta_jld2, "metadata")
        
        mset = MmapImageSet(
            input_bin,
            output_bin,
            metadata.input_dims,
            metadata.output_dims,
            metadata.input_elem_type,
            metadata.output_elem_type,
            input_type,
            raw_output_type,
            metadata.index
        )
        
        # Test accessing data
        println("  Loading input image...")
        input_img = get_input(mset)
        println("  ✓ Input shape: $(size(data(input_img)))")
        println("  ✓ Input channels: $(shape(input_img))")
        
        println("  Loading output image...")
        output_img = get_output(mset)
        println("  ✓ Output shape: $(size(data(output_img)))")
        println("  ✓ Output channels: $(shape(output_img))")
        
        # Verify polygon mask application
        output_data = data(output_img)
        background_sum = sum(output_data[:, :, 5])
        foreground_sum = sum(output_data[:, :, 1:4])
        total_pixels = size(output_data, 1) * size(output_data, 2)
        
        println("  Background pixels: $(round(100 * background_sum / total_pixels, digits=2))%")
        println("  Foreground pixels: $(round(100 * foreground_sum / total_pixels, digits=2))%")
        
        println("\n✅ Test loading SUCCESSFUL")
        println("Dataset is compatible with Load_Sets infrastructure")
        
    catch e
        println("\n❌ Test loading FAILED:")
        println("  $(e)")
        println("\nGenerated files may not be compatible with Load_Sets infrastructure")
    end
end

# ============================================================================
# Final Summary
# ============================================================================

println("\n" * "="^80)
println("FINAL SUMMARY")
println("="^80)

println("\nGenerated Dataset:")
println("  Location: $(resolved_output)")
println("  Images: $(length(generated_indices))")
println("  Resize ratio: $(RESIZE_RATIO)")
println("  Format: .bin (binary) + .jld2 (metadata)")

if TEST_MODE
    println("\n⚠️ TEST MODE was enabled - only $(length(generated_indices)) image(s) processed")
    println("To generate full dataset, set TEST_MODE = false")
else
    println("\n✅ Full dataset generation complete")
end

println("\nNext steps:")
println("  1. Visual inspection with InteractiveUI")
println("  2. Integration testing with CompareUI")
println("  3. Training pipeline validation")

println("\nTo load this dataset:")
println("  sets = load_original_sets(")
println("      $(length(generated_indices)),")
println("      false;")
println("      resize_ratio=$(RESIZE_RATIO),")
println("      dataset_folder=\"original_backup_half_res\"")
println("  )")

println("\n" * "="^80)
println("Generation script completed")
println("="^80)
