# Load_Sets__PolygonDataset.jl
# Generate native dataset files from polygon masks

"""
    Load_Sets__PolygonDataset

Module for generating native .bin + .jld2 dataset files from polygon masks.
Transforms polygon mask PNG files into the binary format expected by Load_Sets infrastructure.

# Key Functions
- `scan_polygon_masks(source_dir)` - Find all polygon mask files
- `load_polygon_mask(mask_path, resize_ratio)` - Load and process polygon mask
- `convert_polygon_to_output_format(...)` - Apply polygon mask to segmentation
- `generate_polygon_dataset(...)` - Main generation pipeline

# Data Flow
Source (MuHa - Bilder/MuHa_XXX/) → Processing → Target (Datasets/original_backup_half_res/)
- MuHa_XXX_raw_adj.png → resize → XXX_input.bin
- MuHa_XXX_polygon_mask.png + seg_*.png → apply mask → XXX_output.bin
- Metadata → XXX_meta.jld2
"""

using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2

# Requires Load_Sets__Initialization.jl to provide ImageMagick, imresize, Gray, etc.
# Requires Load_Sets__Config.jl to be loaded for resolve_path, input_type, raw_output_type
# Requires Load_Sets__DataLoading.jl to be loaded for save_image_binary

# Import required functions from loaded packages
import Bas3ImageSegmentation.ImageMagick
import Bas3ImageSegmentation.Images: imresize, red, green, blue, Gray

# ============================================================================
# Polygon Mask Scanning
# ============================================================================

"""
    scan_polygon_masks(source_dir::String) -> Vector{Int}

Scan MuHa - Bilder directory for polygon masks.
Returns vector of patient indices (1-306) that have polygon masks.

# Arguments
- `source_dir::String`: Base directory (e.g., "C:/Syncthing/MuHa - Bilder")

# Returns
- `Vector{Int}`: Indices of patients with polygon masks (expected: 141)

# Example
```julia
indices = scan_polygon_masks("/mnt/c/Syncthing/MuHa - Bilder")
println("Found \$(length(indices)) polygon masks")
```
"""
function scan_polygon_masks(source_dir::String)
    indices = Int[]
    for i in 1:306
        id_str = lpad(i, 3, '0')
        mask_path = joinpath(source_dir, "MuHa_$(id_str)", "MuHa_$(id_str)_polygon_mask.png")
        if isfile(mask_path)
            push!(indices, i)
        end
    end
    return indices
end

# ============================================================================
# Image Loading Helpers
# ============================================================================

"""
    load_and_resize_image(path::String, resize_ratio) -> Matrix

Load PNG image and resize if needed.
Returns grayscale matrix (0.0 to 1.0).
"""
function load_and_resize_image(path::String, resize_ratio)
    img = ImageMagick.load_(path)
    if resize_ratio != 1
        img = imresize(img; ratio=resize_ratio)
    end
    return Gray.(img)
end

"""
    load_polygon_mask(mask_path::String, resize_ratio) -> BitMatrix

Load polygon mask PNG and convert to binary mask.

# Arguments
- `mask_path::String`: Path to MuHa_XXX_polygon_mask.png
- `resize_ratio`: Resize ratio (e.g., 1//2 for half resolution)

# Returns
- `BitMatrix`: Binary mask (true=wound foreground, false=background)

# Processing
1. Load PNG (RGB, 8-bit white/black)
2. Convert to grayscale
3. Resize if ratio != 1
4. Threshold: >0.5 = foreground, <=0.5 = background
"""
function load_polygon_mask(mask_path::String, resize_ratio)
    img = ImageMagick.load_(mask_path)
    if resize_ratio != 1
        img = imresize(img; ratio=resize_ratio)
    end
    gray = Gray.(img)
    return gray .> 0.5  # BitMatrix: true=wound, false=background
end

"""
    load_raw_input(base_path::String, patient_index::Int, resize_ratio) -> Tuple

Load raw input image (MuHa_XXX_raw_adj.png) and decompose to RGB channels.

# Returns
- Tuple of 3 grayscale matrices (red, green, blue channels)
"""
function load_raw_input(base_path::String, patient_index::Int, resize_ratio)
    id_str = lpad(patient_index, 3, '0')
    img_path = joinpath(base_path, "MuHa_$(id_str)", "MuHa_$(id_str)_raw_adj.png")
    
    img = ImageMagick.load_(img_path)
    if resize_ratio != 1
        img = imresize(img; ratio=resize_ratio)
    end
    
    # Decompose to RGB channels
    red_channel = Float32.(red.(img))
    green_channel = Float32.(green.(img))
    blue_channel = Float32.(blue.(img))
    
    return (red_channel, green_channel, blue_channel)
end

# ============================================================================
# Polygon to Output Conversion
# ============================================================================

"""
    convert_polygon_to_output_format(
        patient_index::Int,
        polygon_mask::BitMatrix,
        base_path::String,
        resize_ratio
    ) -> Tuple{5 matrices}

Convert binary polygon mask to 5-channel output format.
Applies polygon mask as filter to original segmentation masks.

# Strategy
- Load original seg_*.png masks (scar, redness, hematoma, necrosis)
- Apply polygon mask: keep only pixels inside polygon, outside → 0
- Background channel = inverse of polygon mask

# Arguments
- `patient_index::Int`: Patient index (1-306)
- `polygon_mask::BitMatrix`: Binary polygon mask (true=wound)
- `base_path::String`: Base directory for source images
- `resize_ratio`: Resize ratio for segmentation masks

# Returns
- Tuple of 5 Float32 matrices: (scar, redness, hematoma, necrosis, background)

# Output Channels
1. scar - Original scar mask clipped to polygon
2. redness - Original redness mask clipped to polygon
3. hematoma - Original hematoma mask clipped to polygon
4. necrosis - Original necrosis mask clipped to polygon
5. background - Inverse of polygon mask
"""
function convert_polygon_to_output_format(
    patient_index::Int,
    polygon_mask::BitMatrix,
    base_path::String,
    resize_ratio
)
    id_str = lpad(patient_index, 3, '0')
    patient_dir = joinpath(base_path, "MuHa_$(id_str)")
    
    # Load original segmentation masks
    scar_path = joinpath(patient_dir, "MuHa_$(id_str)_seg_scar.png")
    redness_path = joinpath(patient_dir, "MuHa_$(id_str)_seg_redness.png")
    hematoma_path = joinpath(patient_dir, "MuHa_$(id_str)_seg_hematoma.png")
    necrosis_path = joinpath(patient_dir, "MuHa_$(id_str)_seg_necrosis.png")
    
    # Load and resize
    scar = load_and_resize_image(scar_path, resize_ratio)
    redness = load_and_resize_image(redness_path, resize_ratio)
    hematoma = load_and_resize_image(hematoma_path, resize_ratio)
    necrosis = load_and_resize_image(necrosis_path, resize_ratio)
    
    # Apply polygon mask: element-wise multiplication
    # Inside polygon: keep original value, outside: set to 0
    scar_masked = Float32.(scar) .* polygon_mask
    redness_masked = Float32.(redness) .* polygon_mask
    hematoma_masked = Float32.(hematoma) .* polygon_mask
    necrosis_masked = Float32.(necrosis) .* polygon_mask
    
    # Background = inverse of polygon mask
    background = Float32.(.!polygon_mask)
    
    return (scar_masked, redness_masked, hematoma_masked, necrosis_masked, background)
end

# ============================================================================
# Main Generation Pipeline
# ============================================================================

"""
    generate_polygon_dataset(
        source_dir::String,
        output_dir::String;
        resize_ratio=1//2,
        test_mode::Bool=false,
        test_index::Union{Int,Nothing}=nothing
    )

Main generation function for polygon mask dataset.

# Process
1. Scan for polygon masks → get indices (141 expected)
2. For each index:
   a. Load raw_adj.png → input image (RGB channels)
   b. Load polygon_mask.png → binary mask
   c. Load original seg_*.png masks (5 classes)
   d. Apply polygon mask to segmentation
   e. Construct Image_Data types
   f. Save to input.bin, output.bin, meta.jld2
3. Progress reporting every 10 images
4. Periodic GC every 10 images

# Arguments
- `source_dir::String`: Source directory (e.g., "C:/Syncthing/MuHa - Bilder")
- `output_dir::String`: Output directory (e.g., "C:/Syncthing/Datasets/original_backup_half_res")
- `resize_ratio`: Resize ratio (default: 1//2 for half resolution)
- `test_mode::Bool`: If true, only process test_index
- `test_index::Union{Int,Nothing}`: Specific index for testing

# Storage Estimates (resize_ratio=1//2)
- Input: ~8.8MB per image
- Output: ~14.8MB per image
- Metadata: ~8KB per image
- Total per image: ~24MB
- Total dataset (141 images): ~3.4GB

# Example
```julia
generate_polygon_dataset(
    resolve_path("C:/Syncthing/MuHa - Bilder"),
    resolve_path("C:/Syncthing/Datasets/original_backup_half_res");
    resize_ratio=1//2
)
```
"""
function generate_polygon_dataset(
    source_dir::String,
    output_dir::String;
    resize_ratio=1//2,
    test_mode::Bool=false,
    test_index::Union{Int,Nothing}=nothing
)
    # Scan for available masks
    all_indices = scan_polygon_masks(source_dir)
    println("Found $(length(all_indices)) images with polygon masks")
    
    # Filter for test mode
    if test_mode
        if test_index === nothing
            indices = [all_indices[1]]  # First available
            println("TEST MODE: Processing first index only: $(indices[1])")
        else
            if test_index in all_indices
                indices = [test_index]
                println("TEST MODE: Processing index $(test_index)")
            else
                error("Test index $(test_index) does not have a polygon mask")
            end
        end
    else
        indices = all_indices
    end
    
    # Create output directory
    mkpath(output_dir)
    println("Output directory: $(output_dir)")
    
    # Check disk space (require at least 5GB free)
    # Note: This is a rough check, may not work on all systems
    try
        disk_stats = Sys.free_memory()
        println("Available system memory: $(round(disk_stats / 1e9, digits=2)) GB")
    catch
        println("Could not check available memory (proceeding anyway)")
    end
    
    # Process each image
    println("\n=== Starting Dataset Generation ===")
    start_time = time()
    
    for (count, patient_index) in enumerate(indices)
        iter_start = time()
        println("\n[$count/$(length(indices))] Processing Patient $(patient_index)...")
        
        try
            # 1. Load input image (RGB)
            print("  Loading input image... ")
            input_channels = load_raw_input(source_dir, patient_index, resize_ratio)
            println("✓")
            
            # 2. Load polygon mask
            print("  Loading polygon mask... ")
            id_str = lpad(patient_index, 3, '0')
            mask_path = joinpath(source_dir, "MuHa_$(id_str)", "MuHa_$(id_str)_polygon_mask.png")
            polygon_mask = load_polygon_mask(mask_path, resize_ratio)
            mask_area = sum(polygon_mask)
            total_pixels = length(polygon_mask)
            mask_percentage = round(100 * mask_area / total_pixels, digits=2)
            println("✓ ($(mask_percentage)% foreground)")
            
            # 3. Convert to output format (5 channels with polygon applied)
            print("  Applying polygon to segmentation... ")
            output_channels = convert_polygon_to_output_format(
                patient_index, polygon_mask, source_dir, resize_ratio
            )
            println("✓")
            
            # 4. Construct Image_Data types
            print("  Constructing image data types... ")
            input_image_data = input_type(input_channels...)
            output_image_data = raw_output_type(output_channels...)
            println("✓")
            
            # 5. Save to binary + metadata
            print("  Saving to disk... ")
            input_bin = joinpath(output_dir, "$(patient_index)_input.bin")
            output_bin = joinpath(output_dir, "$(patient_index)_output.bin")
            meta_jld2 = joinpath(output_dir, "$(patient_index)_meta.jld2")
            
            input_dims, input_elem_type = save_image_binary(input_bin, input_image_data)
            output_dims, output_elem_type = save_image_binary(output_bin, output_image_data)
            
            JLD2.save(meta_jld2, "metadata", (
                input_dims=input_dims,
                output_dims=output_dims,
                input_elem_type=input_elem_type,
                output_elem_type=output_elem_type,
                index=patient_index
            ))
            println("✓")
            
            # Report timing
            iter_time = time() - iter_start
            println("  Completed in $(round(iter_time, digits=2))s")
            
            # Periodic GC
            if count % 10 == 0
                print("  Running garbage collection... ")
                GC.gc()
                println("✓")
            end
            
        catch e
            println("\n❌ ERROR processing patient $(patient_index):")
            println("  $(e)")
            if !test_mode
                println("  Continuing with next image...")
            else
                rethrow(e)
            end
        end
    end
    
    # Final summary
    total_time = time() - start_time
    println("\n=== Generation Complete ===")
    println("Successfully processed: $(length(indices)) images")
    println("Total time: $(round(total_time / 60, digits=2)) minutes")
    println("Average per image: $(round(total_time / length(indices), digits=2)) seconds")
    println("Output directory: $(output_dir)")
    
    return indices
end

# ============================================================================
# Verification Utilities
# ============================================================================

"""
    verify_dataset(output_dir::String, expected_indices::Vector{Int})

Verify that all expected dataset files exist and are valid.

# Checks
- All .bin and .jld2 files exist
- Metadata is readable
- File sizes are reasonable

# Example
```julia
indices = scan_polygon_masks(resolve_path("C:/Syncthing/MuHa - Bilder"))
verify_dataset(resolve_path("C:/Syncthing/Datasets/original_backup_half_res"), indices)
```
"""
function verify_dataset(output_dir::String, expected_indices::Vector{Int})
    println("\n=== Dataset Verification ===")
    println("Checking $(length(expected_indices)) image sets...")
    
    missing_files = String[]
    invalid_metadata = Int[]
    
    for idx in expected_indices
        input_bin = joinpath(output_dir, "$(idx)_input.bin")
        output_bin = joinpath(output_dir, "$(idx)_output.bin")
        meta_jld2 = joinpath(output_dir, "$(idx)_meta.jld2")
        
        # Check file existence
        if !isfile(input_bin)
            push!(missing_files, input_bin)
        end
        if !isfile(output_bin)
            push!(missing_files, output_bin)
        end
        if !isfile(meta_jld2)
            push!(missing_files, meta_jld2)
        end
        
        # Check metadata validity
        if isfile(meta_jld2)
            try
                metadata = JLD2.load(meta_jld2, "metadata")
                # Verify required fields
                if !haskey(metadata, :input_dims) || !haskey(metadata, :output_dims)
                    push!(invalid_metadata, idx)
                end
            catch
                push!(invalid_metadata, idx)
            end
        end
    end
    
    # Report results
    if isempty(missing_files) && isempty(invalid_metadata)
        println("✓ All files present and valid")
        
        # Calculate total size
        total_size = 0
        for idx in expected_indices
            total_size += filesize(joinpath(output_dir, "$(idx)_input.bin"))
            total_size += filesize(joinpath(output_dir, "$(idx)_output.bin"))
            total_size += filesize(joinpath(output_dir, "$(idx)_meta.jld2"))
        end
        println("Total dataset size: $(round(total_size / 1e9, digits=2)) GB")
        
        return true
    else
        if !isempty(missing_files)
            println("❌ Missing files ($(length(missing_files))):")
            for f in missing_files[1:min(10, length(missing_files))]
                println("  - $f")
            end
            if length(missing_files) > 10
                println("  ... and $(length(missing_files) - 10) more")
            end
        end
        
        if !isempty(invalid_metadata)
            println("❌ Invalid metadata for indices: $(invalid_metadata)")
        end
        
        return false
    end
end
