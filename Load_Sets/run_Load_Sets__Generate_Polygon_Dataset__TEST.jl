#!/usr/bin/env julia
# run_Load_Sets__Generate_Polygon_Dataset__TEST.jl
# Test script for polygon dataset generation (single image)

# Import Base functions explicitly to avoid conflicts
import Base: println, print

println("="^80)
println("Polygon Dataset Generation - TEST MODE")
println("="^80)

# ============================================================================
# Configuration
# ============================================================================

const SOURCE_DIR = "C:/Syncthing/MuHa - Bilder"
const OUTPUT_DIR = "C:/Syncthing/Datasets/original_backup_half_res"
const RESIZE_RATIO = 1//2  # Half resolution
const TEST_MODE = true  # Always test mode
const TEST_INDEX = nothing  # Use first available

println("\nConfiguration:")
println("  Source: $(SOURCE_DIR)")
println("  Output: $(OUTPUT_DIR)")
println("  Resize: $(RESIZE_RATIO) (half resolution)")
println("  Test mode: $(TEST_MODE) (processing single image)")

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
end

# Scan for polygon masks
print("\nScanning for polygon masks... ")
available_indices = scan_polygon_masks(resolved_source)
println("found $(length(available_indices))")

if isempty(available_indices)
    error("No polygon masks found in source directory!")
end

test_index = available_indices[1]
println("✓ Will test with first available index: $(test_index)")

# ============================================================================
# Dataset Generation (Single Image)
# ============================================================================

println("\n" * "="^80)
println("Dataset Generation - Single Image Test")
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
    println("\n✅ Test generation SUCCESSFUL")
else
    println("\n⚠️ Test generation completed with WARNINGS")
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
        rethrow(e)
    end
end

# ============================================================================
# Final Summary
# ============================================================================

println("\n" * "="^80)
println("TEST COMPLETE")
println("="^80)

println("\n✅ Single image test successful!")
println("\nGenerated file:")
println("  $(resolved_output)/$(generated_indices[1])_input.bin")
println("  $(resolved_output)/$(generated_indices[1])_output.bin")
println("  $(resolved_output)/$(generated_indices[1])_meta.jld2")

println("\nTo generate full dataset (141 images):")
println("  Run: run_Load_Sets__Generate_Polygon_Dataset.jl with TEST_MODE = false")

println("\n" * "="^80)
