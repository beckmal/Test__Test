#!/usr/bin/env julia
# run_Generate_Polygon_Mask_Bins.jl
# Generate polygon mask .bin files using the EXACT same pipeline as input.bin generation
# This script mirrors regenerate_quarter_res.jl but processes polygon_mask.png instead of raw_adj.png

import Base: println, print

println("="^80)
println("Polygon Mask .bin Generation - Using Input Pipeline")
println("="^80)

# ============================================================================
# SECTION 1: Environment Setup (COPY from regenerate_quarter_res.jl)
# ============================================================================

import Pkg
Pkg.activate(@__DIR__)

println("\nLoading initialization...")
include("Load_Sets__Initialization.jl")
println("Loading config...")
include("Load_Sets__Config.jl")
println("Loading DataLoading...")
include("Load_Sets__DataLoading.jl")

using Bas3ImageSegmentation
using Bas3ImageSegmentation: decompose_image_to_values
using Bas3ImageSegmentation.Images: imresize

println("✓ Environment loaded")

# ============================================================================
# SECTION 2: Helper Functions (COPY from load_input_and_output/-method-1.jl)
# ============================================================================

"""
    img_loader(base_path, Number_of_Dataset; idtype, filetype)

Load image using ImageMagick (EXACT COPY from load_input_and_output/-method-1.jl lines 1-5)
"""
function img_loader(base_path, Number_of_Dataset; idtype = "raw", filetype = "jpg")
    id_str = lpad(Number_of_Dataset, 3, '0')
    img_path = joinpath([base_path, "MuHa_$(id_str)", "MuHa_$(id_str)_$(idtype).$(filetype)"])
    return Bas3ImageSegmentation.ImageMagick.load_(img_path)
end

# ============================================================================
# SECTION 3: Configuration
# ============================================================================

const SOURCE_DIR = "C:/Syncthing/MuHa - Bilder"
const OUTPUT_DIR = "C:/Syncthing/Datasets/original_quarter_res"
const RESIZE_RATIO = 1//4
const MAX_IMAGES = 306  # Set to 10 for testing, 306 for full generation

println("\n" * "="^80)
println("Configuration")
println("="^80)
println("Source: $(SOURCE_DIR)/MuHa_XXX/MuHa_XXX_polygon_mask.png")
println("Output: $(OUTPUT_DIR)/{index}_polygon_mask.bin")
println("Resize ratio: $(RESIZE_RATIO)")
println("Max images: $(MAX_IMAGES)")

# Resolve paths
resolved_source = resolve_path(SOURCE_DIR)
resolved_output = resolve_path(OUTPUT_DIR)

println("\nResolved paths:")
println("  Source: $(resolved_source)")
println("  Output: $(resolved_output)")

# Verify directories exist
if !isdir(resolved_source)
    error("Source directory does not exist: $(resolved_source)")
end
if !isdir(resolved_output)
    error("Output directory does not exist: $(resolved_output)")
end
println("✓ Directories verified")

# ============================================================================
# SECTION 4: Scan for Available Polygon Masks
# ============================================================================

println("\n" * "="^80)
println("Scanning for Polygon Masks")
println("="^80)

available_masks = Int[]

for index in 1:MAX_IMAGES
    patient_num = lpad(index, 3, '0')
    mask_path = joinpath(resolved_source, "MuHa_$(patient_num)", "MuHa_$(patient_num)_polygon_mask.png")
    
    if isfile(mask_path)
        push!(available_masks, index)
    end
end

println("\nFound $(length(available_masks)) polygon masks")
if isempty(available_masks)
    error("No polygon masks found!")
end
println("Indices: $(join(available_masks, ", "))")

# ============================================================================
# SECTION 5: Main Processing Loop (COPY pipeline from load_input_and_output)
# ============================================================================

println("\n" * "="^80)
println("Generating .bin Files")
println("="^80)
println("\nPipeline: ImageMagick.load_() → imresize() → decompose → input_type() → save_image_binary()")
println("This is the EXACT same pipeline used for input.bin generation\n")

# Counters
total_generated = 0
total_skipped = 0
total_errors = 0

for index in available_masks
    global total_generated, total_skipped, total_errors
    try
        println("[$index/$(MAX_IMAGES)] Processing...")
        
        # Check if already exists
        mask_bin_path = joinpath(resolved_output, "$(index)_polygon_mask.bin")
        if isfile(mask_bin_path)
            println("  → Skipping (already exists)")
            total_skipped += 1
            continue
        end
        
        # ====================================================================
        # EXACT COPY from load_input_and_output/-method-1.jl lines 96-104
        # ONLY CHANGE: idtype="polygon_mask" instead of "raw_adj"
        # ====================================================================
        
        # Line 96: Load PNG using ImageMagick
        mask_image = img_loader(
            resolved_source, 
            index; 
            idtype="polygon_mask",    # ← ONLY CHANGE from "raw_adj"
            filetype="png"
        )
        
        # Lines 98-100: Resize using imresize
        if RESIZE_RATIO != 1
            mask_image = imresize(mask_image; ratio=RESIZE_RATIO)
        end
        
        # Line 101: Get size
        mask_image_size = size(mask_image)
        
        # Lines 102-104: Decompose to RGB channels
        input_shape = shape(input_type)
        local mask_images = ()
        for channel_index in 1:length(input_shape)
            mask_images = (mask_images..., decompose_image_to_values(input_shape[channel_index], mask_image))
        end
        
        # Line 144: Create Image_Data structure
        mask_data = input_type(mask_images...)
        
        # ====================================================================
        # EXACT COPY from regenerate_quarter_res.jl line 40
        # ====================================================================
        
        # Save using existing save_image_binary function
        dims, elem_type = save_image_binary(mask_bin_path, mask_data)
        
        # Verify file was created
        file_size_mb = round(filesize(mask_bin_path) / 1024 / 1024, digits=2)
        
        println("  → Generated: dims=$(dims), type=$(elem_type), size=$(file_size_mb) MB")
        total_generated += 1
        
    catch e
        @warn "Failed to process mask $index: $e"
        println("  → ERROR: $e")
        total_errors += 1
    end
end

# ============================================================================
# SECTION 6: Summary
# ============================================================================

println("\n" * "="^80)
println("Generation Complete")
println("="^80)

println("\nResults:")
println("  Available masks: $(length(available_masks))")
println("  Generated: $(total_generated)")
println("  Skipped (existing): $(total_skipped)")
println("  Errors: $(total_errors)")

if total_generated > 0
    # Calculate expected size (756×1008×3 UInt8)
    expected_size_mb = round(total_generated * 756 * 1008 * 3 / 1024 / 1024, digits=2)
    println("\nExpected total size: $(expected_size_mb) MB")
end

println("\n" * "="^80)
println("Verification Steps")
println("="^80)
println("\n1. Check file sizes match input.bin:")
println("   ls -lh $(resolved_output)/*_input.bin $(resolved_output)/*_polygon_mask.bin | head -20")

println("\n2. Verify both are 2.18 MB (2,286,144 bytes):")
println("   stat --format='%n: %s bytes' $(resolved_output)/1_input.bin $(resolved_output)/1_polygon_mask.bin")

println("\n3. Test in CompareUI to verify alignment")

println("\n✓ Done!")
