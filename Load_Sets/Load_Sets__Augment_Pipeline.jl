# ============================================================================
# Load_Sets__Augment_Pipeline.jl
# ============================================================================
# Core augmentation pipeline functions for balanced dataset generation.
#
# This module provides all functions needed to:
# - Analyze source images for class distribution
# - Sample augmentation parameters explicitly
# - Apply smart cropping to focus on target classes
# - Generate balanced augmented datasets
# - Save and load augmented data with metadata
#
# Dependencies:
# - Load_Sets__Augment_Config.jl (types and constants)
# - Load_Sets__Config.jl (input/output types, resolve_path)
# - Bas3ImageSegmentation (augmentation transforms)
#
# Usage:
#   include("Load_Sets__Augment_Pipeline.jl")
#   source_info = analyze_source_classes(sets)
#   inputs, outputs, indices, metadata = generate_balanced_sets(...)
# ============================================================================

using Random
using Statistics
using Dates

# ============================================================================
# Parameter Sampling
# ============================================================================

"""
    sample_augmentation_parameters(; seed, intermediate_size, target_size)

Sample all augmentation parameters explicitly using a random seed.
Returns a NamedTuple with all parameter values for reproducibility.

# Arguments
- `seed::UInt64` - Random seed for reproducibility
- `intermediate_size::Tuple{Int,Int}` - Size after smart crop (height, width)
- `target_size::Tuple{Int,Int}` - Final output size (height, width)

# Returns
NamedTuple with fields:
- Geometric: scale_factor, shear_x_angle, shear_y_angle, rotation_angle, flip_type
- Crop: final_crop_y_start, final_crop_x_start, final_crop_height, final_crop_width
- Elastic: elastic_grid_h, elastic_grid_w, elastic_scale, elastic_sigma, elastic_iterations
- Color: brightness_factor, saturation_offset, blur_kernel_size, blur_sigma
"""
function sample_augmentation_parameters(; seed::UInt64, intermediate_size, target_size)
    Random.seed!(seed)
    
    # Main pipeline parameters
    scale_factor = rand(0.9:0.01:1.1)
    shear_x_angle = rand(-10:0.1:10)
    shear_y_angle = rand(-10:0.1:10)
    rotation_angle = rand(1:0.1:360)
    
    # Flip type (Either transformation)
    flip_choice = rand(1:3)
    flip_type = if flip_choice == 1
        :flipx
    elseif flip_choice == 2
        :flipy
    else
        :noop
    end
    
    # Final crop parameters (CropSize to target size)
    crop_y_start = rand(1:(intermediate_size[1] - target_size[1] + 1))
    crop_x_start = rand(1:(intermediate_size[2] - target_size[2] + 1))
    
    # Post pipeline (ElasticDistortion) - fixed parameters
    elastic_grid_h = 8
    elastic_grid_w = 8
    elastic_scale = 0.2
    elastic_sigma = 2.0
    elastic_iterations = 1
    
    # Input pipeline parameters
    brightness_factor = rand(0.8:0.1:1.2)
    saturation_offset = rand(-0.2:0.1:0.2)
    blur_kernel_size = rand([3, 5, 7])
    blur_sigma = rand(1.0:0.1:3.0)
    
    return (
        scale_factor = scale_factor,
        shear_x_angle = shear_x_angle,
        shear_y_angle = shear_y_angle,
        rotation_angle = rotation_angle,
        flip_type = flip_type,
        final_crop_y_start = crop_y_start,
        final_crop_x_start = crop_x_start,
        final_crop_height = target_size[1],
        final_crop_width = target_size[2],
        elastic_grid_h = elastic_grid_h,
        elastic_grid_w = elastic_grid_w,
        elastic_scale = elastic_scale,
        elastic_sigma = elastic_sigma,
        elastic_iterations = elastic_iterations,
        brightness_factor = brightness_factor,
        saturation_offset = saturation_offset,
        blur_kernel_size = blur_kernel_size,
        blur_sigma = blur_sigma
    )
end

# ============================================================================
# Source Image Analysis
# ============================================================================

"""
    analyze_source_classes(sets) -> Vector{SourceClassInfo}

Analyze class distribution for all source images.
Used for weighted source selection during augmentation.

# Arguments
- `sets` - Vector of (input, output, index) tuples

# Returns
Vector of SourceClassInfo structs with class percentages for each source.
"""
function analyze_source_classes(sets)
    source_info = SourceClassInfo[]
    
    for (idx, set_tuple) in enumerate(sets)
        # Handle both (input, output) and (input, output, index) formats
        output = length(set_tuple) >= 2 ? set_tuple[2] : set_tuple[2]
        source_idx = length(set_tuple) >= 3 ? set_tuple[3] : idx
        
        output_data = data(output)
        total_pixels = size(output_data, 1) * size(output_data, 2)
        
        scar_area = sum(output_data[:, :, 1])
        redness_area = sum(output_data[:, :, 2])
        hematoma_area = sum(output_data[:, :, 3])
        necrosis_area = sum(output_data[:, :, 4])
        background_area = sum(output_data[:, :, 5])
        
        info = SourceClassInfo(
            source_idx,
            scar_area / total_pixels * 100,
            redness_area / total_pixels * 100,
            hematoma_area / total_pixels * 100,
            necrosis_area / total_pixels * 100,
            background_area / total_pixels * 100,
            total_pixels
        )
        
        push!(source_info, info)
        
        if idx == 1 || idx % 100 == 0 || idx == length(sets)
            println("  Analyzed $(idx)/$(length(sets)) sources")
        end
    end
    
    return source_info
end

# ============================================================================
# Smart Cropping Functions
# ============================================================================

"""
    find_class_pixels(output_data, class_idx::Int) -> Vector{Tuple{Int,Int}}

Find all pixel coordinates where a specific class is present.

# Arguments
- `output_data` - 3D array (H, W, C) of class probabilities
- `class_idx` - Channel index for the target class

# Returns
Vector of (row, col) coordinate tuples where class > 0.5
"""
function find_class_pixels(output_data, class_idx::Int)
    coords = Tuple{Int,Int}[]
    for i in 1:size(output_data, 1)
        for j in 1:size(output_data, 2)
            if output_data[i, j, class_idx] > 0.5
                push!(coords, (i, j))
            end
        end
    end
    return coords
end

"""
    smart_crop_for_class(output, class_symbol::Symbol, crop_size::Tuple{Int,Int})

Find best crop window that maximizes target class presence.

# Arguments
- `output` - Output segmentation mask image
- `class_symbol` - Target class (:scar, :redness, :hematoma, :necrosis, :background)
- `crop_size` - Desired crop size (height, width)

# Returns
Tuple (x_start, y_start, width, height) for the crop window.
"""
function smart_crop_for_class(output, class_symbol::Symbol, crop_size::Tuple{Int,Int})
    output_data = data(output)
    img_height, img_width = size(output_data, 1), size(output_data, 2)
    crop_h, crop_w = crop_size
    
    # Get class index
    class_idx = get_class_index(class_symbol)
    
    # For background, use random crop
    if class_symbol == :background
        x_start = rand(1:(img_width - crop_w + 1))
        y_start = rand(1:(img_height - crop_h + 1))
        return (x_start, y_start, crop_w, crop_h)
    end
    
    # Find all pixels of target class
    class_coords = find_class_pixels(output_data, class_idx)
    
    if isempty(class_coords)
        # No class pixels found, use random crop
        x_start = rand(1:(img_width - crop_w + 1))
        y_start = rand(1:(img_height - crop_h + 1))
        return (x_start, y_start, crop_w, crop_h)
    end
    
    # Sample a few candidate crop windows centered on class pixels
    num_candidates = min(20, length(class_coords))
    sampled_coords = rand(class_coords, num_candidates)
    
    best_score = -1.0
    best_window = (1, 1, crop_w, crop_h)
    
    for (cy, cx) in sampled_coords
        # Center crop on this pixel
        x_start = max(1, min(cx - crop_w ÷ 2, img_width - crop_w + 1))
        y_start = max(1, min(cy - crop_h ÷ 2, img_height - crop_h + 1))
        
        # Calculate class percentage in this window
        window = output_data[y_start:(y_start + crop_h - 1), x_start:(x_start + crop_w - 1), class_idx]
        class_pct = sum(window) / (crop_h * crop_w) * 100
        
        if class_pct > best_score
            best_score = class_pct
            best_window = (x_start, y_start, crop_w, crop_h)
        end
    end
    
    return best_window
end

"""
    apply_smart_crop(input, output, target_class::Symbol, intermediate_size::Tuple{Int,Int})

Apply smart cropping to focus on target class regions.

# Arguments
- `input` - Input RGB image
- `output` - Output segmentation mask
- `target_class` - Class to focus on
- `intermediate_size` - Size to crop to (height, width)

# Returns
Tuple (cropped_input, cropped_output, crop_window) where crop_window is (x, y, w, h)
"""
function apply_smart_crop(input, output, target_class::Symbol, intermediate_size::Tuple{Int,Int})
    output_data = data(output)
    input_data = data(input)
    
    img_height, img_width = size(output_data, 1), size(output_data, 2)
    crop_h, crop_w = intermediate_size
    
    # If image is smaller than crop size, return as-is with no-crop window
    if img_height < crop_h || img_width < crop_w
        return input, output, (1, 1, img_width, img_height)
    end
    
    # Get crop window using smart_crop_for_class
    crop_window = smart_crop_for_class(output, target_class, intermediate_size)
    x_start, y_start, w, h = crop_window
    
    # Apply crop to both input and output
    cropped_output_data = output_data[y_start:(y_start + h - 1), x_start:(x_start + w - 1), :]
    cropped_input_data = input_data[y_start:(y_start + h - 1), x_start:(x_start + w - 1), :]
    
    # Convert back to proper types
    input_t = typeof(input)
    output_t = typeof(output)
    
    cropped_input = input_t(cropped_input_data)
    cropped_output = output_t(cropped_output_data)
    
    return cropped_input, cropped_output, crop_window
end

# ============================================================================
# Weighted Source Selection
# ============================================================================

"""
    select_source_for_class(source_info, target_class, excluded_indices)

Select source image weighted by presence of target class.

# Arguments
- `source_info::Vector{SourceClassInfo}` - Class analysis for all sources
- `target_class::Symbol` - Class to weight selection by
- `excluded_indices::Set{Int}` - Source indices to exclude

# Returns
Index of selected source image.
"""
function select_source_for_class(source_info::Vector{SourceClassInfo}, 
                                  target_class::Symbol,
                                  excluded_indices::Set{Int})
    # Get class percentages
    class_values = if target_class == :scar
        [s.scar_percentage for s in source_info]
    elseif target_class == :redness
        [s.redness_percentage for s in source_info]
    elseif target_class == :hematoma
        [s.hematoma_percentage for s in source_info]
    elseif target_class == :necrosis
        [s.necrosis_percentage for s in source_info]
    else  # background
        [s.background_percentage for s in source_info]
    end
    
    # Create weights (add small epsilon to avoid zero weights)
    weights = class_values .+ 0.01
    
    # Zero out excluded indices
    for idx in excluded_indices
        if idx <= length(weights)
            weights[idx] = 0.0
        end
    end
    
    # Normalize weights
    total_weight = sum(weights)
    if total_weight == 0.0
        error("No valid sources available")
    end
    
    weights ./= total_weight
    
    # Sample according to weights
    sample_val = rand()
    cumsum_weight = 0.0
    for (idx, w) in enumerate(weights)
        cumsum_weight += w
        if sample_val <= cumsum_weight
            return idx
        end
    end
    
    # Fallback (shouldn't reach here)
    return findfirst(w -> w > 0, weights)
end

# ============================================================================
# Pipeline Building
# ============================================================================

"""
    build_pipelines_from_params(params)

Build augmentation pipelines from explicit parameters.

# Arguments
- `params` - NamedTuple from sample_augmentation_parameters()

# Returns
Tuple (main_pipeline, input_pipeline, post_pipeline) of augmentation transforms.
"""
function build_pipelines_from_params(params)
    # Main geometric pipeline with explicit parameters
    main_pipeline = Scale(params.scale_factor) |>
                    ShearX(params.shear_x_angle) |>
                    ShearY(params.shear_y_angle) |>
                    Rotate(params.rotation_angle)
    
    # Add flip operation based on sampled choice
    if params.flip_type == :flipx
        main_pipeline = main_pipeline |> FlipX()
    elseif params.flip_type == :flipy
        main_pipeline = main_pipeline |> FlipY()
    else
        main_pipeline = main_pipeline |> NoOp()
    end
    
    # Input pipeline with explicit parameters
    input_pipeline = ColorJitter(
        params.brightness_factor,
        params.saturation_offset
    ) |> GaussianBlur(
        params.blur_kernel_size,
        params.blur_sigma
    )
    
    # Post pipeline (elastic distortion)
    post_pipeline = ElasticDistortion(
        params.elastic_grid_h,
        params.elastic_grid_w,
        params.elastic_scale,
        params.elastic_sigma,
        params.elastic_iterations
    )
    
    return main_pipeline, input_pipeline, post_pipeline
end

# ============================================================================
# Sample Count Calculation
# ============================================================================

"""
    calculate_sample_counts(total_length, target_distribution)

Calculate how many samples to generate for each class.

# Arguments
- `total_length::Int` - Total number of samples to generate
- `target_distribution::Dict{Symbol, Float64}` - Target percentages per class

# Returns
Vector of (class, count) pairs sorted by count descending.
"""
function calculate_sample_counts(total_length::Int, target_distribution::Dict{Symbol, Float64})
    sample_counts = Pair{Symbol, Int}[]
    
    for (class, pct) in target_distribution
        count = round(Int, total_length * pct / 100.0)
        push!(sample_counts, class => count)
    end
    
    # Adjust to ensure total equals exactly total_length
    current_total = sum(count for (_, count) in sample_counts)
    diff = total_length - current_total
    
    if diff != 0
        # Add/subtract from background class
        for i in 1:length(sample_counts)
            if sample_counts[i].first == :background
                sample_counts[i] = :background => (sample_counts[i].second + diff)
                break
            end
        end
    end
    
    # Sort by count descending for processing order
    sort!(sample_counts, by=x->x.second, rev=true)
    
    return sample_counts
end

# ============================================================================
# Foreground Percentage Computation
# ============================================================================

"""
    compute_foreground_percentage(output) -> Float64

Calculate percentage of foreground (non-background) pixels.

# Arguments
- `output` - Output segmentation mask

# Returns
Foreground percentage (0-100)
"""
function compute_foreground_percentage(output)
    output_data = data(output)
    total_pixels = size(output_data, 1) * size(output_data, 2)
    
    # Sum all non-background channels (channels 1-4: scar, redness, hematoma, necrosis)
    fg_pixels = sum(output_data[:, :, 1:4])
    
    return (fg_pixels / total_pixels) * 100.0
end

"""
    calculate_intermediate_size(base_size, max_multiplier) -> Tuple{Int,Int}

Calculate required intermediate size to accommodate max final size with geometric transforms.

# Arguments
- `base_size::Tuple{Int,Int}` - Base patch size (height, width)
- `max_multiplier::Int` - Maximum size multiplier

# Returns
Required intermediate size (height, width)
"""
function calculate_intermediate_size(base_size::Tuple{Int,Int}, max_multiplier::Int)
    max_final_h = base_size[1] * max_multiplier
    max_final_w = base_size[2] * max_multiplier
    
    # Multiply by 2 to handle rotation (diagonal case)
    # Add extra margin (1.2×) for safety
    margin = 1.2
    intermediate_h = round(Int, max_final_h * 2 * margin)
    intermediate_w = round(Int, max_final_w * 2 * margin)
    
    return (intermediate_h, intermediate_w)
end

# ============================================================================
# Quality Threshold
# ============================================================================

"""
    meets_quality_threshold(output, target_class, source_info)

Check if augmented sample meets minimum quality threshold for target class.

# Arguments
- `output` - Augmented output segmentation mask
- `target_class::Symbol` - Target class for this sample
- `source_info::SourceClassInfo` - Class info for the source image

# Returns
`true` if sample meets threshold, `false` otherwise.
"""
function meets_quality_threshold(output, target_class::Symbol, source_info::SourceClassInfo)
    output_data = data(output)
    total_pixels = size(output_data, 1) * size(output_data, 2)
    
    # Get class index
    class_idx = get_class_index(target_class)
    
    actual_pct = sum(output_data[:, :, class_idx]) / total_pixels * 100
    
    # For background, any amount is acceptable
    if target_class == :background
        return true
    end
    
    # For minority classes, use adaptive thresholds based on source availability
    source_pct = if target_class == :scar
        source_info.scar_percentage
    elseif target_class == :redness
        source_info.redness_percentage
    elseif target_class == :hematoma
        source_info.hematoma_percentage
    else  # necrosis
        source_info.necrosis_percentage
    end
    
    min_threshold = max(0.5, source_pct * 0.3)
    
    return actual_pct >= min_threshold
end

# ============================================================================
# Main Generation Function
# ============================================================================

"""
    generate_balanced_sets(; kwargs...)

Generate a balanced augmented dataset with explicit parameter tracking and dynamic sizing.

# Keyword Arguments
- `sets` - Source dataset (vector of (input, output) or (input, output, index) tuples)
- `source_info::Vector{SourceClassInfo}` - Pre-computed source class analysis
- `target_distribution::Dict{Symbol, Float64}` - Target class distribution
- `total_length::Int` - Number of samples to generate
- `base_size::Tuple{Int,Int}` - Base patch size (height, width), default (50, 100)
- `max_multiplier::Int` - Maximum size multiplier for growth (default: 4)
- `fg_thresholds::Dict{Symbol, Float64}` - Per-class FG% thresholds (default: FG_THRESHOLDS)
- `excluded_indices::Set{Int}` - Source indices to exclude (default: empty)
- `input_type` - Type for input images
- `raw_output_type` - Type for output masks

# Returns
Tuple (inputs, outputs, image_indices, metadata_list):
- `inputs` - Vector of augmented input images (variable sizes)
- `outputs` - Vector of augmented output masks (variable sizes)
- `image_indices` - Vector of source indices used
- `metadata_list` - Vector of AugmentationMetadata
"""
function generate_balanced_sets(;
    sets,
    source_info::Vector{SourceClassInfo},
    target_distribution::Dict{Symbol, Float64},
    total_length::Int,
    base_size::Tuple{Int,Int} = (50, 100),
    max_multiplier::Int = 4,
    fg_thresholds::Dict{Symbol, Float64} = FG_THRESHOLDS,
    excluded_indices::Set{Int} = Set{Int}(),
    input_type,
    raw_output_type
)
    # Calculate intermediate size based on max final size
    intermediate_size = calculate_intermediate_size(base_size, max_multiplier)
    
    println("\n=== Configuring Balanced Augmentation ===")
    println("  Base size: $(base_size)")
    println("  Max multiplier: $(max_multiplier)× (max size: $(base_size[1]*max_multiplier)×$(base_size[2]*max_multiplier))")
    println("  Intermediate size: $(intermediate_size)")
    println("  FG thresholds: $(fg_thresholds)")
    println("  Total samples: $(total_length)")
    println("  Excluded sources: $(collect(excluded_indices))")
    
    # Calculate samples per class
    sample_counts = calculate_sample_counts(total_length, target_distribution)
    println("\n=== Sample Allocation ===")
    for (class, count) in sample_counts
        pct = round(count / total_length * 100, digits=1)
        println("  $(class): $(count) samples ($(pct)%)")
    end
    
    # Initialize output arrays as empty - we'll collect them dynamically
    inputs = []
    outputs = []
    image_indices = Int[]
    metadata_list = AugmentationMetadata[]
    
    # Track counts
    sample_counts_by_target = Dict{Symbol, Int}(c => 0 for c in AUGMENT_CLASS_ORDER)
    pixel_distribution = Dict{Symbol, Float64}(c => 0.0 for c in AUGMENT_CLASS_ORDER)
    
    println("\n=== Generating Augmented Images ===")
    
    successful_samples = 0
    total_attempts = 0
    total_rejections = 0
    
    # Process each class in stages
    for (target_class, num_samples) in sample_counts
        println("\n--- Stage: $(target_class) ($(num_samples) samples) ---")
        
        class_successful = 0
        class_attempts = 0
        class_rejections = 0
        max_attempts_per_class = num_samples * 100
        
        while class_successful < num_samples && class_attempts < max_attempts_per_class
            class_attempts += 1
            total_attempts += 1
            
            if class_successful % 20 == 0 && class_successful > 0
                println("  Generated $(class_successful)/$(num_samples) for $(target_class)")
            end
            
            try
                # Step 1: Select source image
                sample_index = select_source_for_class(source_info, target_class, excluded_indices)
                
                # Step 2: Sample parameters (use base_size for initial crop)
                aug_seed = rand(UInt64)
                params = sample_augmentation_parameters(
                    seed = aug_seed,
                    intermediate_size = intermediate_size,
                    target_size = base_size  # Start with base size
                )
                
                # Step 3: Build pipelines
                main_pipeline, input_pipeline_explicit, post_pipeline_explicit = build_pipelines_from_params(params)
                
                # Get source data
                input_img = sets[sample_index][1]
                output_img = sets[sample_index][2]
                
                # Step 4: Smart cropping to LARGE intermediate
                cropped_input, cropped_output, smart_crop_window = apply_smart_crop(
                    input_img, output_img, target_class, intermediate_size
                )
                
                # Step 5: Apply geometric transformations to intermediate
                augmented_input, augmented_output = augment(
                    (cropped_input, cropped_output), 
                    main_pipeline
                )
                
                # Step 6: Iterative Growth Loop
                fg_threshold = get_fg_threshold(target_class)
                multiplier = 1
                growth_iterations = 0
                actual_fg_pct = 100.0
                final_input = nothing
                final_output = nothing
                max_size_reached = false
                
                # Get intermediate dimensions
                output_dims = size(data(augmented_output))
                intermediate_h, intermediate_w = output_dims[1], output_dims[2]
                
                while multiplier <= max_multiplier
                    growth_iterations += 1
                    
                    # Calculate current crop size
                    current_h = base_size[1] * multiplier
                    current_w = base_size[2] * multiplier
                    
                    # Check if intermediate is large enough
                    if current_h > intermediate_h || current_w > intermediate_w
                        # Can't grow further, use previous multiplier
                        multiplier -= 1
                        if multiplier < 1
                            multiplier = 1
                        end
                        break
                    end
                    
                    # Extract crop from center of augmented intermediate using CropSize
                    crop_pipeline = CropSize(current_h, current_w)
                    
                    # Apply crop to extract final size
                    final_input, final_output = augment(
                        (augmented_input, augmented_output),
                        crop_pipeline
                    )
                    
                    # Compute foreground percentage
                    actual_fg_pct = compute_foreground_percentage(final_output)
                    
                    # Check threshold
                    if actual_fg_pct <= fg_threshold
                        # Threshold met, stop growing
                        break
                    end
                    
                    # Check if we've reached max multiplier
                    if multiplier >= max_multiplier
                        # Can't grow further, stay at max
                        break
                    end
                    
                    # Continue growing
                    multiplier += 1
                end
                
                # Check if we hit max size
                max_size_reached = (multiplier >= max_multiplier && actual_fg_pct > fg_threshold)
                
                # Step 7: Post-processing (elastic applied to BOTH together, color only to input)
                # Apply elastic distortion to both input and output in a SINGLE call
                # to ensure the same random displacement field is used for both
                final_input, final_output = augment((final_input, final_output), post_pipeline_explicit)
                # Apply color augmentation (brightness, saturation, blur) only to input
                final_input = augment(final_input, input_pipeline_explicit)
                final_output = convert(raw_output_type, final_output)
                
                # Step 8: Quality check
                if !meets_quality_threshold(final_output, target_class, source_info[sample_index])
                    class_rejections += 1
                    total_rejections += 1
                    continue
                end
                
                # Compute quality metrics
                final_output_data = data(final_output)
                total_pixels = size(final_output_data, 1) * size(final_output_data, 2)
                
                scar_pct = sum(final_output_data[:, :, 1]) / total_pixels * 100
                redness_pct = sum(final_output_data[:, :, 2]) / total_pixels * 100
                hematoma_pct = sum(final_output_data[:, :, 3]) / total_pixels * 100
                necrosis_pct = sum(final_output_data[:, :, 4]) / total_pixels * 100
                background_pct = sum(final_output_data[:, :, 5]) / total_pixels * 100
                
                # Update tracking
                sample_counts_by_target[target_class] += 1
                pixel_distribution[:scar] += scar_pct
                pixel_distribution[:redness] += redness_pct
                pixel_distribution[:hematoma] += hematoma_pct
                pixel_distribution[:necrosis] += necrosis_pct
                pixel_distribution[:background] += background_pct
                
                # Store result
                successful_samples += 1
                class_successful += 1
                push!(inputs, final_input)
                push!(outputs, final_output)
                push!(image_indices, sample_index)
                
                # Create metadata
                push!(metadata_list, AugmentationMetadata(
                    successful_samples,
                    sample_index,
                    now(),
                    aug_seed,
                    target_class,
                    smart_crop_window[1],
                    smart_crop_window[2],
                    smart_crop_window[3],
                    smart_crop_window[4],
                    params.scale_factor,
                    params.shear_x_angle,
                    params.shear_y_angle,
                    params.rotation_angle,
                    params.flip_type,
                    params.final_crop_y_start,
                    params.final_crop_x_start,
                    params.final_crop_height,
                    params.final_crop_width,
                    params.elastic_grid_h,
                    params.elastic_grid_w,
                    params.elastic_scale,
                    params.elastic_sigma,
                    params.elastic_iterations,
                    params.brightness_factor,
                    params.saturation_offset,
                    params.blur_kernel_size,
                    params.blur_sigma,
                    scar_pct,
                    redness_pct,
                    hematoma_pct,
                    necrosis_pct,
                    background_pct,
                    multiplier,                      # size_multiplier
                    base_size[1] * multiplier,      # patch_height
                    base_size[2] * multiplier,      # patch_width
                    fg_threshold,                   # fg_threshold_used
                    actual_fg_pct,                  # actual_fg_percentage
                    growth_iterations,              # growth_iterations
                    max_size_reached,               # max_size_reached
                    intermediate_h,                 # intermediate_height
                    intermediate_w                  # intermediate_width
                ))
                
            catch error
                if class_attempts % 50 == 0
                    println("    Error (attempt $(class_attempts)): $(typeof(error))")
                    println("    Message: $(error)")
                    if isa(error, MethodError)
                        println("    Method: $(error.f)")
                        println("    Args: $(error.args)")
                    end
                end
            end
        end
        
        if class_attempts >= max_attempts_per_class
            println("  Warning: Max attempts reached for $(target_class)")
        end
        rejection_rate = class_rejections / max(1, class_attempts) * 100
        println("  Completed $(target_class): $(class_successful) samples ($(round(rejection_rate, digits=1))% rejected)")
    end
    
    # Shuffle samples
    println("\n=== Shuffling samples ===")
    shuffle_indices = Random.randperm(successful_samples)
    inputs = inputs[shuffle_indices]
    outputs = outputs[shuffle_indices]
    image_indices = image_indices[shuffle_indices]
    metadata_list = metadata_list[shuffle_indices]
    
    # Print summary
    rejection_rate = total_rejections / max(1, total_attempts) * 100
    println("\n=== Generation Complete ===")
    println("  Total samples: $(successful_samples)")
    println("  Total attempts: $(total_attempts)")
    println("  Rejection rate: $(round(rejection_rate, digits=2))%")
    
    println("\n  Distribution by target class:")
    for (class, count) in sort(collect(sample_counts_by_target), by=x->x[2], rev=true)
        pct = count / successful_samples * 100
        println("    $(class): $(count) ($(round(pct, digits=1))%)")
    end
    
    return inputs, outputs, image_indices, metadata_list
end

# ============================================================================
# Save/Load Functions
# ============================================================================

"""
    save_augmented_dataset(inputs, outputs, metadata_list, output_dir, metadata_dir; memory_map_fn=identity)

Save augmented dataset to disk.

# Arguments
- `inputs` - Vector of input images
- `outputs` - Vector of output masks
- `metadata_list` - Vector of AugmentationMetadata
- `output_dir` - Directory for image data
- `metadata_dir` - Directory for metadata
- `target_distribution` - Target distribution used (for summary)
- `excluded_indices` - Excluded source indices (for summary)
- `memory_map_fn` - Function to apply before saving (default: identity)

# Returns
Vector of (input, output, source_index) tuples (optionally memory-mapped).
"""
function save_augmented_dataset(
    inputs, 
    outputs, 
    metadata_list, 
    output_dir::String, 
    metadata_dir::String;
    target_distribution::Dict{Symbol, Float64} = DEFAULT_TARGET_DISTRIBUTION,
    excluded_indices::Set{Int} = Set{Int}(),
    memory_map_fn = identity
)
    # Create directories
    mkpath(output_dir)
    mkpath(metadata_dir)
    
    println("\n=== Saving Augmented Dataset ===")
    println("  Output dir: $(output_dir)")
    println("  Metadata dir: $(metadata_dir)")
    
    result_sets = []
    
    for (index, (input, output, metadata)) in enumerate(zip(inputs, outputs, metadata_list))
        if index == 1 || index == length(inputs) || index % 100 == 0
            println("  Saving $(index)/$(length(inputs))")
        end
        
        # Save image data
        JLD2.save(
            joinpath(output_dir, "$(index).jld2"),
            "set", (input, output)
        )
        
        # Save metadata
        JLD2.save(
            joinpath(metadata_dir, "$(index)_metadata.jld2"),
            "metadata", metadata
        )
        
        push!(result_sets, (
            memory_map_fn(input),
            memory_map_fn(output),
            metadata.source_index
        ))
    end
    
    # Save summary
    println("  Saving summary...")
    JLD2.save(
        joinpath(metadata_dir, "augmentation_summary.jld2"),
        "all_metadata", metadata_list,
        "target_distribution", target_distribution,
        "excluded_indices", collect(excluded_indices),
        "generation_timestamp", now()
    )
    
    println("  Done! Saved $(length(inputs)) samples")
    
    return result_sets
end

"""
    load_augmented_metadata(metadata_dir) -> (all_metadata, target_distribution)

Load augmentation metadata from disk.

# Arguments
- `metadata_dir` - Directory containing metadata files

# Returns
Tuple (all_metadata::Vector{AugmentationMetadata}, target_dist::Dict{Symbol,Float64})
"""
function load_augmented_metadata(metadata_dir::String)
    summary_file = joinpath(metadata_dir, "augmentation_summary.jld2")
    
    if !isfile(summary_file)
        error("Summary file not found: $(summary_file)")
    end
    
    summary_data = JLD2.load(summary_file)
    all_metadata = summary_data["all_metadata"]
    target_dist = summary_data["target_distribution"]
    
    println("Loaded $(length(all_metadata)) metadata entries from $(metadata_dir)")
    
    return all_metadata, target_dist
end

"""
    load_augmented_sample(output_dir, index) -> (input, output)

Load a single augmented sample from disk.

# Arguments
- `output_dir` - Directory containing image data
- `index` - Sample index to load

# Returns
Tuple (input, output) of the augmented images.
"""
function load_augmented_sample(output_dir::String, index::Int)
    filepath = joinpath(output_dir, "$(index).jld2")
    
    if !isfile(filepath)
        error("Sample file not found: $(filepath)")
    end
    
    return JLD2.load(filepath, "set")
end

println("  Load_Sets__Augment_Pipeline loaded")
