import Random
#Random.seed!(1234)

# ============================================================================
# Initialize Environment and Reporters
# ============================================================================

const reporters = try
    for (key, value) in reporters
        stop(value)
    end
    Bas3GLMakie.GLMakie.closeall()
    reporters
catch
    println("=== Initializing reporters ===")
    import Pkg
    Pkg.activate(@__DIR__)
    println("Updating packages...")
    Pkg.update()
    println("Resolving dependencies...")
    Pkg.resolve()
    println("Skipping Revise for faster loading...")

    println("Loading Bas3Plots...")
    using Bas3Plots
    import Bas3Plots.display
    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    using Bas3GLMakie.GLMakie: Figure, Label, Axis, image!, hidedecorations!, DataAspect, RGB
    println("Loading Bas3_EnvironmentTools (1)...")
    using Bas3_EnvironmentTools

    println("Loading Bas3ImageSegmentation...")
    using Bas3ImageSegmentation
    println("Loading Bas3ImageSegmentation.Bas3...")
    using Bas3ImageSegmentation.Bas3
    println("Loading Bas3ImageSegmentation.Bas3IGABOptimization...")
    using Bas3ImageSegmentation.Bas3IGABOptimization
    println("Importing Base functions...")
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    println("Loading Random, Mmap, Statistics, LinearAlgebra...")
    using Random
    using Mmap
    using Statistics
    using LinearAlgebra
    println("Loading JLD2...")
    using Bas3ImageSegmentation.JLD2
    println("Loading Dates...")
    using Dates

    println("Loading Bas3_EnvironmentTools (2)...")
    using Bas3_EnvironmentTools
    println("Importing RemoteChannel...")
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    println("=== Reporters initialized ===")
    Dict()
end

# ============================================================================
# Type Definitions
# ============================================================================

const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:scar, :redness, :hematoma, :necrosis, :background)})
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:foreground, :background)})

import Bas3.convert

# ============================================================================
# Augmentation Tracking Structures
# ============================================================================

# Metadata for each augmented sample
struct AugmentationMetadata
    # Basic info
    augmented_index::Int
    source_index::Int
    timestamp::DateTime
    random_seed::UInt64
    target_class::Symbol
    
    # Smart crop parameters (applied first)
    smart_crop_x_start::Int
    smart_crop_y_start::Int
    smart_crop_width::Int
    smart_crop_height::Int
    
    # Main pipeline parameters (geometric transformations)
    scale_factor::Float64
    shear_x_angle::Float64
    shear_y_angle::Float64
    rotation_angle::Float64
    flip_type::Symbol          # :flipx, :flipy, or :noop
    
    # Final crop to target size (after main pipeline)
    final_crop_y_start::Int
    final_crop_x_start::Int
    final_crop_height::Int
    final_crop_width::Int
    
    # Post pipeline (elastic distortion)
    elastic_grid_h::Int
    elastic_grid_w::Int
    elastic_scale::Float64
    elastic_sigma::Float64
    elastic_iterations::Int
    
    # Input pipeline (color/blur - applied to input only)
    brightness_factor::Float64
    saturation_offset::Float64
    blur_kernel_size::Int
    blur_sigma::Float64
    
    # Quality metrics (computed after augmentation)
    scar_percentage::Float64
    redness_percentage::Float64
    hematoma_percentage::Float64
    necrosis_percentage::Float64
    background_percentage::Float64
end

# ============================================================================
# Explicit Parameter Sampling
# ============================================================================

"""
Sample all augmentation parameters explicitly using a random seed.
Returns a NamedTuple with all parameter values.
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
    # After all transformations, image should be intermediate_size
    # We crop to target_size from intermediate_size
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
# Source Image Class Analysis
# ============================================================================

# Source image class analysis
struct SourceClassInfo
    source_index::Int
    scar_percentage::Float64
    redness_percentage::Float64
    hematoma_percentage::Float64
    necrosis_percentage::Float64
    background_percentage::Float64
    total_pixels::Int
end

# ============================================================================
# Path Resolution Utilities
# ============================================================================

function resolve_path(relative_path::String)
    if Sys.iswindows()
        if startswith(relative_path, "/mnt/")
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        if occursin(r"^[A-Za-z]:[/\\]", relative_path)
            drive_letter = lowercase(relative_path[1])
            rest_of_path = replace(relative_path[4:end], "\\" => "/")
            return "/mnt/$(drive_letter)/$(rest_of_path)"
        else
            return relative_path
        end
    end
end

# ============================================================================
# Load Original Dataset
# ============================================================================

base_path = resolve_path("C:/Syncthing/Datasets")

println("\n=== Loading Original Dataset ===")

const sets = try
    sets
catch
    let
        temp_sets = []
        _length = 306
        
        println("Loading original sets from disk ($((_length)) images)...")
        for index in 1:_length
            if index % 50 == 0 || index == 1 || index == _length
                println("  Loading set $(index)/$(_length)")
            end
            input, output = JLD2.load(joinpath(base_path, "original/$(index).jld2"), "set")
            push!(temp_sets, (memory_map(input), memory_map(output), index))
        end
        println("Original sets loaded: $(length(temp_sets)) sets")
        [temp_sets...]
    end
end

# ============================================================================
# Source Image Analysis
# ============================================================================

println("\n=== Analyzing Source Images ===")

function analyze_source_classes(sets)
    source_info = SourceClassInfo[]
    
    for (idx, (input, output, source_idx)) in enumerate(sets)
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

const source_class_info = analyze_source_classes(sets)

# Print summary
println("\nSource Image Class Distribution Summary:")
println("  Scar:     $(round(mean([s.scar_percentage for s in source_class_info]), digits=2))%")
println("  Redness:  $(round(mean([s.redness_percentage for s in source_class_info]), digits=2))%")
println("  Hematoma: $(round(mean([s.hematoma_percentage for s in source_class_info]), digits=2))%")
println("  Necrosis: $(round(mean([s.necrosis_percentage for s in source_class_info]), digits=2))%")

# ============================================================================
# Smart Cropping Functions
# ============================================================================

function find_class_pixels(output_data, class_idx::Int)
    """Find all pixel coordinates where class is present"""
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

function smart_crop_for_class(output, class_symbol::Symbol, crop_size::Tuple{Int,Int})
    """
    Find best crop window that maximizes target class presence.
    Returns (x_start, y_start) for top-left corner of crop.
    """
    output_data = data(output)
    img_height, img_width = size(output_data, 1), size(output_data, 2)
    crop_h, crop_w = crop_size
    
    # Map class symbol to index
    class_idx = if class_symbol == :scar
        1
    elseif class_symbol == :redness
        2
    elseif class_symbol == :hematoma
        3
    elseif class_symbol == :necrosis
        4
    else
        5  # background
    end
    
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

# ============================================================================
# Weighted Source Selection
# ============================================================================

function select_source_for_class(source_info::Vector{SourceClassInfo}, 
                                  target_class::Symbol,
                                  excluded_indices::Set{Int})
    """
    Select source image weighted by presence of target class.
    """
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
        weights[idx] = 0.0
    end
    
    # Normalize weights
    total_weight = sum(weights)
    if total_weight == 0.0
        error("No valid sources available")
    end
    
    weights ./= total_weight
    
    # Sample according to weights
    sample_idx = rand()
    cumsum_weight = 0.0
    for (idx, w) in enumerate(weights)
        cumsum_weight += w
        if sample_idx <= cumsum_weight
            return idx
        end
    end
    
    # Fallback (shouldn't reach here)
    return findfirst(w -> w > 0, weights)
end

# ============================================================================
# Target Distribution Configuration
# ============================================================================

# User-specified target distribution
const TARGET_DISTRIBUTION = Dict{Symbol, Float64}(
    :scar => 15.0,        # 5%
    :redness => 15.0,     # 5%
    :hematoma => 30.0,   # 15%
    :necrosis => 5.0,    # 1%
    :background => 35.0  # 74%
)

println("\n=== Target Distribution ===")
for (class, pct) in sort(collect(TARGET_DISTRIBUTION), by=x->x[2], rev=true)
    println("  $(class): $(pct)%")
end

# ============================================================================
# Helper Functions for Hybrid Approach
# ============================================================================

"""
Build augmentation pipelines from explicit parameters.
Returns (main_pipeline, input_pipeline, post_pipeline).
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

function calculate_sample_counts(total_length::Int, target_distribution::Dict{Symbol, Float64})
    """
    Calculate how many samples to generate for each class based on target distribution.
    Returns a vector of (class, count) tuples sorted by count descending.
    """
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

function apply_smart_crop(input, output, target_class::Symbol, intermediate_size::Tuple{Int,Int})
    """
    Apply smart cropping to focus on target class regions.
    Returns cropped input, cropped output, and crop window (x_start, y_start, width, height).
    """
    output_data = data(output)
    input_data = data(input)
    
    img_height, img_width = size(output_data, 1), size(output_data, 2)
    crop_h, crop_w = intermediate_size
    
    # If image is smaller than crop size, return as-is with no-crop window
    if img_height < crop_h || img_width < crop_w
        return input, output, (1, 1, img_width, img_height)
    end
    
    # Get crop window using existing smart_crop_for_class function
    crop_window = smart_crop_for_class(output, target_class, intermediate_size)
    x_start, y_start, w, h = crop_window
    
    # Apply crop to both input and output
    cropped_output_data = output_data[y_start:(y_start + h - 1), x_start:(x_start + w - 1), :]
    cropped_input_data = input_data[y_start:(y_start + h - 1), x_start:(x_start + w - 1), :]
    
    # Convert back to proper types
    input_type = typeof(input)
    output_type = typeof(output)
    
    cropped_input = input_type(cropped_input_data)
    cropped_output = output_type(cropped_output_data)
    
    return cropped_input, cropped_output, crop_window
end

function meets_quality_threshold(output, target_class::Symbol, source_info::SourceClassInfo)
    """
    Check if augmented sample meets minimum quality threshold for target class.
    Thresholds are adaptive based on source data availability.
    """
    output_data = data(output)
    total_pixels = size(output_data, 1) * size(output_data, 2)
    
    # Calculate actual percentages
    class_idx = if target_class == :scar
        1
    elseif target_class == :redness
        2
    elseif target_class == :hematoma
        3
    elseif target_class == :necrosis
        4
    else
        5  # background
    end
    
    actual_pct = sum(output_data[:, :, class_idx]) / total_pixels * 100
    
    # For background, any amount is acceptable
    if target_class == :background
        return true
    end
    
    # For minority classes, use adaptive thresholds based on source availability
    # Threshold = max(0.5%, source_percentage * 0.3)
    # This ensures we don't reject all samples for very rare classes
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
# Balanced Dataset Generation Pipeline
# ============================================================================

@__(function generate_balanced_sets(; 
    _length, 
    _size, 
    temp_augmented_sets, 
    excluded_indices,
    target_distribution,
    source_info,
    start_index=1,
    keywords...
)
    println("\n=== Configuring Hybrid Balanced Augmentation with Explicit Parameters ===")
    
    # Larger intermediate size for smart cropping
    intermediate_size = (max(150, maximum(_size) * 2), max(150, maximum(_size) * 2))
    
    println("  Strategy: Hybrid multi-stage with smart cropping and explicit parameters")
    println("  All transformation parameters will be sampled explicitly and tracked")
    println("  Smart crop size: $(intermediate_size)")
    println("  Final size: $(_size)")
    println("  Excluded source indices: $(collect(excluded_indices))")
    
    # Calculate samples per class using multi-stage approach
    sample_counts = calculate_sample_counts(_length, target_distribution)
    println("\n=== Multi-Stage Sample Allocation ===")
    for (class, count) in sample_counts
        pct = round(count / _length * 100, digits=1)
        println("  $(class): $(count) samples ($(pct)%)")
    end
    
    # Initialize output arrays
    local inputs, outputs
    inputs = Vector{@__(input_type{_size})}(undef, _length)
    outputs = Vector{@__(raw_output_type{_size})}(undef, _length)
    image_indices = Vector{Int}(undef, _length)
    metadata_list = Vector{AugmentationMetadata}(undef, _length)
    
    # Track sample counts per target class (for verification)
    sample_counts_by_target = Dict{Symbol, Int}(
        :scar => 0,
        :redness => 0,
        :hematoma => 0,
        :necrosis => 0,
        :background => 0
    )
    
    # Track average pixel distribution across all samples (for information)
    pixel_distribution = Dict{Symbol, Float64}(
        :scar => 0.0,
        :redness => 0.0,
        :hematoma => 0.0,
        :necrosis => 0.0,
        :background => 0.0
    )
    
    println("\n=== Generating Balanced Augmented Images (Hybrid Approach) ===")
    
    successful_samples = 0
    total_attempts = 0
    total_rejections = 0
    
    # Process each class in stages
    for (target_class, num_samples) in sample_counts
        println("\n--- Stage: Generating $(num_samples) samples for $(target_class) ---")
        
        class_successful = 0
        class_attempts = 0
        class_rejections = 0
        max_attempts_per_class = num_samples * 100  # Allow 100x attempts per class
        
        while class_successful < num_samples && class_attempts < max_attempts_per_class
            class_attempts += 1
            total_attempts += 1
            
            if class_successful % 5 == 0 && class_successful > 0
                println("  Generated $(class_successful)/$(num_samples) for $(target_class) ($(class_rejections) rejections)")
            end
            
            try
                # Step 1: Select source image weighted by target class
                sample_index = select_source_for_class(source_info, target_class, excluded_indices)
                
                # Step 2: Generate random seed and sample augmentation parameters
                aug_seed = rand(UInt64)
                params = sample_augmentation_parameters(
                    seed = aug_seed,
                    intermediate_size = intermediate_size,
                    target_size = _size
                )
                
                # Step 3: Build pipelines from parameters
                main_pipeline, input_pipeline_explicit, post_pipeline_explicit = build_pipelines_from_params(params)
                
                # Get source data
                input, output = temp_augmented_sets[sample_index]
                
                # Step 4: Apply smart cropping to focus on target class
                cropped_input, cropped_output, smart_crop_window = apply_smart_crop(input, output, target_class, intermediate_size)
                
                # Step 5: Apply main augmentation pipeline with explicit parameters
                augmented_input, augmented_output = augment((cropped_input, cropped_output), main_pipeline)
                
                # Step 6: Final crop to target size
                final_input, final_output = augment((augmented_input, augmented_output), CropSize(_size...))
                
                # Step 7: Apply post-processing with explicit parameters
                final_input = augment(final_input, post_pipeline_explicit |> input_pipeline_explicit)
                final_output = augment(final_output, post_pipeline_explicit)
                final_output = convert(raw_output_type, final_output)
                
                # Step 8: Quality check (rejection sampling)
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
                
                # Update sample count tracking for target class
                sample_counts_by_target[target_class] += 1
                
                # Update pixel distribution tracking (for information only)
                pixel_distribution[:scar] += scar_pct
                pixel_distribution[:redness] += redness_pct
                pixel_distribution[:hematoma] += hematoma_pct
                pixel_distribution[:necrosis] += necrosis_pct
                pixel_distribution[:background] += background_pct
                
                # Store result
                successful_samples += 1
                class_successful += 1
                inputs[successful_samples] = final_input
                outputs[successful_samples] = final_output
                image_indices[successful_samples] = sample_index
                
                # Create metadata with all explicit parameters
                metadata_list[successful_samples] = AugmentationMetadata(
                    start_index + successful_samples - 1,
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
                    background_pct
                )
                
            catch error
                if class_attempts % 20 == 0
                    println("    Error during augmentation (attempt $(class_attempts) for $(target_class)): $(typeof(error))")
                end
                # Continue trying
            end
        end
        
        if class_attempts >= max_attempts_per_class
            println("  ⚠ Warning: Reached maximum attempts for $(target_class)")
            println("    Generated $(class_successful)/$(num_samples) samples")
        else
            rejection_rate_class = class_rejections / class_attempts * 100
            println("  ✓ Completed $(target_class): $(class_successful) samples ($(round(rejection_rate_class, digits=1))% rejection)")
        end
    end
    
    # Shuffle samples to mix classes
    println("\n=== Shuffling samples to mix classes ===")
    shuffle_indices = Random.randperm(_length)
    inputs = inputs[shuffle_indices]
    outputs = outputs[shuffle_indices]
    image_indices = image_indices[shuffle_indices]
    metadata_list = metadata_list[shuffle_indices]
    
    rejection_rate = total_rejections / total_attempts * 100
    println("\n✓ Augmentation complete: $(successful_samples) samples generated")
    println("  Total attempts: $(total_attempts)")
    println("  Total rejections: $(total_rejections)")
    println("  Rejection rate: $(round(rejection_rate, digits=2))%")
    
    # Print sample count distribution (should match target distribution)
    println("\n  Sample count distribution by target class:")
    for (class, count) in sort(collect(sample_counts_by_target), by=x->x[2], rev=true)
        actual_pct = count / successful_samples * 100
        target_pct = target_distribution[class]
        diff = actual_pct - target_pct
        println("    $(class): $(count) samples ($(round(actual_pct, digits=2))% actual vs $(target_pct)% target, diff: $(round(diff, digits=2))%)")
    end
    
    # Print pixel distribution (for information - will differ from target)
    println("\n  Average pixel coverage distribution:")
    for (class, total_pct) in sort(collect(pixel_distribution), by=x->x[2], rev=true)
        avg_pct = total_pct / successful_samples
        println("    $(class): $(round(avg_pct, digits=2))% average pixel coverage")
    end
    
    return inputs, outputs, image_indices, metadata_list
end; Transform=false)

# ============================================================================
# Generate and Save Balanced Dataset
# ============================================================================

println("\n=== Starting Balanced Augmentation Process ===")

const total_augmented_length = 1000
const augmented_size = (100, 50)
const excluded_source_indices = Set([8, 16])

augmented_dir = joinpath(base_path, "augmented_balanced")
metadata_dir = joinpath(base_path, "augmented_balanced_metadata")
if !isdir(augmented_dir)
    println("Creating augmented directory: $(augmented_dir)")
    mkpath(augmented_dir)
end
if !isdir(metadata_dir)
    println("Creating metadata directory: $(metadata_dir)")
    mkpath(metadata_dir)
end

const augmented_sets = try
    augmented_sets
catch
    let
        temp_augmented_sets = []
        all_metadata = AugmentationMetadata[]
        
        println("\n=== Generating Balanced Augmented Sets ===")
        
        @time begin
            augmented_inputs, augmented_outputs, image_indices, metadata_list = @__(generate_balanced_sets(
                _length=total_augmented_length,
                _size=augmented_size,
                temp_augmented_sets=sets,
                excluded_indices=excluded_source_indices,
                target_distribution=TARGET_DISTRIBUTION,
                source_info=source_class_info,
                start_index=1
            ))
        end
        
        println("\n  Saving augmented samples and metadata to disk...")
        for index in 1:length(augmented_inputs)
            if index == 1 || index == length(augmented_inputs)
                println("    Saving augmented set $(index)/$(total_augmented_length)")
            end
            
            # Save image data
            JLD2.save(
                joinpath(augmented_dir, "$(index).jld2"),
                "set",
                (augmented_inputs[index], augmented_outputs[index])
            )
            
            # Save metadata
            JLD2.save(
                joinpath(metadata_dir, "$(index)_metadata.jld2"),
                "metadata",
                metadata_list[index]
            )
            
            push!(temp_augmented_sets, (
                memory_map(augmented_inputs[index]),
                memory_map(augmented_outputs[index]),
                image_indices[index]
            ))
            
            push!(all_metadata, metadata_list[index])
        end
        
        println("\n✓ Augmented sets generated and saved: $(length(temp_augmented_sets)) sets")
        
        # Save aggregate statistics
        println("\n=== Saving Aggregate Metrics ===")
        JLD2.save(
            joinpath(metadata_dir, "augmentation_summary.jld2"),
            "all_metadata", all_metadata,
            "target_distribution", TARGET_DISTRIBUTION,
            "excluded_indices", collect(excluded_source_indices),
            "generation_timestamp", now()
        )
        
        [temp_augmented_sets...]
    end
end

println("\n" * "="^70)
println("BALANCED AUGMENTATION SUMMARY")
println("="^70)
println("Original dataset size:    $(length(sets)) images")
println("Augmented dataset size:   $(length(augmented_sets)) images")
println("Augmented image size:     $(augmented_size[1])x$(augmented_size[2]) pixels")
println("Storage location:         $(augmented_dir)")
println("Metadata location:        $(metadata_dir)")
println("="^70)

# ============================================================================
# Visualization of Augmentation Results
# ============================================================================

println("\n=== Generating Visualizations ===")

# Load metadata for visualization
println("Loading metadata for visualization...")
summary_data = JLD2.load(joinpath(metadata_dir, "augmentation_summary.jld2"))
all_metadata = summary_data["all_metadata"]
target_dist = summary_data["target_distribution"]

# Extract parameter arrays from metadata
scale_factors = [m.scale_factor for m in all_metadata]
rotation_angles = [m.rotation_angle for m in all_metadata]
shear_x_angles = [m.shear_x_angle for m in all_metadata]
shear_y_angles = [m.shear_y_angle for m in all_metadata]
brightness_factors = [m.brightness_factor for m in all_metadata]
saturation_offsets = [m.saturation_offset for m in all_metadata]
blur_kernel_sizes = [m.blur_kernel_size for m in all_metadata]
blur_sigmas = [m.blur_sigma for m in all_metadata]
flip_types = [m.flip_type for m in all_metadata]
source_indices = [m.source_index for m in all_metadata]
target_classes = [m.target_class for m in all_metadata]

# Quality metrics
scar_pcts = [m.scar_percentage for m in all_metadata]
redness_pcts = [m.redness_percentage for m in all_metadata]
hematoma_pcts = [m.hematoma_percentage for m in all_metadata]
necrosis_pcts = [m.necrosis_percentage for m in all_metadata]
background_pcts = [m.background_percentage for m in all_metadata]

# ============================================================================
# Figure 1: Parameter Distribution Histograms
# ============================================================================

println("Creating parameter distribution plots...")

fig1 = Figure(size=(1800, 1200))
fig1[0, :] = Label(fig1, "Augmentation Parameter Distributions (N=$(length(all_metadata)))", fontsize=24, font=:bold)

# Scale factor histogram
ax1 = Axis(fig1[1, 1], title="Scale Factor", xlabel="Scale", ylabel="Count")
hist!(ax1, scale_factors, bins=20, color=:steelblue)

# Rotation angle histogram
ax2 = Axis(fig1[1, 2], title="Rotation Angle", xlabel="Degrees", ylabel="Count")
hist!(ax2, rotation_angles, bins=36, color=:coral)

# Shear X histogram
ax3 = Axis(fig1[1, 3], title="Shear X Angle", xlabel="Degrees", ylabel="Count")
hist!(ax3, shear_x_angles, bins=20, color=:mediumseagreen)

# Shear Y histogram
ax4 = Axis(fig1[2, 1], title="Shear Y Angle", xlabel="Degrees", ylabel="Count")
hist!(ax4, shear_y_angles, bins=20, color=:mediumpurple)

# Brightness histogram
ax5 = Axis(fig1[2, 2], title="Brightness Factor", xlabel="Factor", ylabel="Count")
hist!(ax5, brightness_factors, bins=10, color=:gold)

# Saturation histogram
ax6 = Axis(fig1[2, 3], title="Saturation Offset", xlabel="Offset", ylabel="Count")
hist!(ax6, saturation_offsets, bins=10, color=:darkorange)

# Blur kernel size bar chart
ax7 = Axis(fig1[3, 1], title="Blur Kernel Size", xlabel="Size", ylabel="Count", xticks=[3, 5, 7])
kernel_counts = [count(==(k), blur_kernel_sizes) for k in [3, 5, 7]]
barplot!(ax7, [3, 5, 7], kernel_counts, color=:slategray)

# Blur sigma histogram
ax8 = Axis(fig1[3, 2], title="Blur Sigma", xlabel="σ", ylabel="Count")
hist!(ax8, blur_sigmas, bins=20, color=:teal)

# Flip type bar chart
ax9 = Axis(fig1[3, 3], title="Flip Type", xlabel="Type", ylabel="Count", 
           xticks=(1:3, ["FlipX", "FlipY", "NoOp"]))
flip_counts = [count(==(t), flip_types) for t in [:flipx, :flipy, :noop]]
barplot!(ax9, 1:3, flip_counts, color=[:indianred, :cornflowerblue, :darkgray])

# Save Figure 1
fig1_filename = joinpath(metadata_dir, "augmentation_parameter_distributions.png")
save(fig1_filename, fig1)
println("  Saved: $(fig1_filename)")

# ============================================================================
# Figure 2: Source Image Usage and Class Distribution
# ============================================================================

println("Creating source usage and class distribution plots...")

fig2 = Figure(size=(1600, 1000))
fig2[0, :] = Label(fig2, "Source Image Usage & Class Distribution", fontsize=24, font=:bold)

# Source image usage histogram
ax_source = Axis(fig2[1, 1:2], title="Source Image Usage Distribution", 
                 xlabel="Source Image Index", ylabel="Usage Count")
source_usage = [count(==(i), source_indices) for i in 1:length(sets)]
# Only show non-zero usage
used_sources = findall(>(0), source_usage)
barplot!(ax_source, used_sources, source_usage[used_sources], color=:steelblue, 
         strokewidth=0.5, strokecolor=:black)

# Target class distribution (actual vs target)
ax_class = Axis(fig2[2, 1], title="Target Class Distribution", 
                xlabel="Class", ylabel="Sample Count",
                xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

class_order = [:scar, :redness, :hematoma, :necrosis, :background]
actual_counts = [count(==(c), target_classes) for c in class_order]
target_counts = [round(Int, target_dist[c] / 100 * length(all_metadata)) for c in class_order]

# Grouped bar chart
barplot!(ax_class, (1:5) .- 0.15, actual_counts, width=0.3, color=:steelblue, label="Actual")
barplot!(ax_class, (1:5) .+ 0.15, target_counts, width=0.3, color=:coral, label="Target")
axislegend(ax_class, position=:rt)

# Pixel coverage distribution per class (box plot style using scatter + lines)
ax_pixel = Axis(fig2[2, 2], title="Pixel Coverage Distribution by Class",
                xlabel="Class", ylabel="Coverage (%)",
                xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

pixel_data = [scar_pcts, redness_pcts, hematoma_pcts, necrosis_pcts, background_pcts]
class_colors = [:indianred, :mediumseagreen, :cornflowerblue, :gold, :slategray]

for (i, (pcts, col)) in enumerate(zip(pixel_data, class_colors))
    μ = mean(pcts)
    σ = std(pcts)
    min_v = minimum(pcts)
    max_v = maximum(pcts)
    
    # Draw range line
    lines!(ax_pixel, [i, i], [min_v, max_v], color=col, linewidth=2)
    # Draw mean ± std box
    lines!(ax_pixel, [i-0.2, i+0.2], [μ-σ, μ-σ], color=col, linewidth=2)
    lines!(ax_pixel, [i-0.2, i+0.2], [μ+σ, μ+σ], color=col, linewidth=2)
    lines!(ax_pixel, [i-0.2, i-0.2], [μ-σ, μ+σ], color=col, linewidth=2)
    lines!(ax_pixel, [i+0.2, i+0.2], [μ-σ, μ+σ], color=col, linewidth=2)
    # Draw mean point
    scatter!(ax_pixel, [i], [μ], color=col, markersize=12)
end

# Save Figure 2
fig2_filename = joinpath(metadata_dir, "augmentation_source_and_class_distribution.png")
save(fig2_filename, fig2)
println("  Saved: $(fig2_filename)")

# ============================================================================
# Figure 3: Quality Metrics Heatmap and Correlation
# ============================================================================

println("Creating quality metrics visualization...")

fig3 = Figure(size=(1600, 1000))
fig3[0, :] = Label(fig3, "Quality Metrics Analysis", fontsize=24, font=:bold)

# Stacked area showing class composition across samples (first 100 samples)
ax_stack = Axis(fig3[1, 1:2], title="Class Composition per Sample (first 100 samples)",
                xlabel="Sample Index", ylabel="Coverage (%)")

n_show = min(100, length(all_metadata))
sample_range = 1:n_show

# Stack the percentages
y_scar = scar_pcts[sample_range]
y_redness = y_scar .+ redness_pcts[sample_range]
y_hematoma = y_redness .+ hematoma_pcts[sample_range]
y_necrosis = y_hematoma .+ necrosis_pcts[sample_range]
y_background = y_necrosis .+ background_pcts[sample_range]

band!(ax_stack, collect(sample_range), zeros(n_show), y_scar, color=(:indianred, 0.8), label="Scar")
band!(ax_stack, collect(sample_range), y_scar, y_redness, color=(:mediumseagreen, 0.8), label="Redness")
band!(ax_stack, collect(sample_range), y_redness, y_hematoma, color=(:cornflowerblue, 0.8), label="Hematoma")
band!(ax_stack, collect(sample_range), y_hematoma, y_necrosis, color=(:gold, 0.8), label="Necrosis")
band!(ax_stack, collect(sample_range), y_necrosis, y_background, color=(:slategray, 0.8), label="Background")

axislegend(ax_stack, position=:rt, nbanks=2)

# Mean pixel coverage by target class
ax_mean = Axis(fig3[2, 1], title="Mean Pixel Coverage by Target Class",
               xlabel="Target Class", ylabel="Mean Coverage (%)",
               xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

# Group samples by target class and compute mean pixel coverage for each class
target_class_indices = Dict(c => findall(==(c), target_classes) for c in class_order)

# For each target class, show mean of the corresponding pixel class
mean_coverage_by_target = Float64[]
for (i, tc) in enumerate(class_order)
    indices = target_class_indices[tc]
    if tc == :scar
        push!(mean_coverage_by_target, mean(scar_pcts[indices]))
    elseif tc == :redness
        push!(mean_coverage_by_target, mean(redness_pcts[indices]))
    elseif tc == :hematoma
        push!(mean_coverage_by_target, mean(hematoma_pcts[indices]))
    elseif tc == :necrosis
        push!(mean_coverage_by_target, mean(necrosis_pcts[indices]))
    else
        push!(mean_coverage_by_target, mean(background_pcts[indices]))
    end
end

barplot!(ax_mean, 1:5, mean_coverage_by_target, color=class_colors)

# Smart crop position scatter plot
ax_crop = Axis(fig3[2, 2], title="Smart Crop Positions",
               xlabel="X Start", ylabel="Y Start")
crop_x = [m.smart_crop_x_start for m in all_metadata]
crop_y = [m.smart_crop_y_start for m in all_metadata]

# Color by target class
target_class_nums = [findfirst(==(m.target_class), class_order) for m in all_metadata]
scatter!(ax_crop, crop_x, crop_y, color=target_class_nums, colormap=:viridis, 
         markersize=4, alpha=0.5)

# Save Figure 3
fig3_filename = joinpath(metadata_dir, "augmentation_quality_metrics.png")
save(fig3_filename, fig3)
println("  Saved: $(fig3_filename)")

# ============================================================================
# Figure 4: Sample Gallery with Metadata Overlay
# ============================================================================

println("Creating sample gallery...")

fig4 = Figure(size=(2000, 1400))
fig4[0, :] = Label(fig4, "Sample Augmented Images with Parameters", fontsize=24, font=:bold)

# Select samples: one from each target class
gallery_indices = Int[]
for tc in class_order
    indices = findall(==(tc), target_classes)
    if !isempty(indices)
        push!(gallery_indices, rand(indices))
    end
end

# Add a few more random samples
while length(gallery_indices) < 10
    idx = rand(1:length(all_metadata))
    if !(idx in gallery_indices)
        push!(gallery_indices, idx)
    end
end

for (plot_idx, aug_idx) in enumerate(gallery_indices[1:min(10, length(gallery_indices))])
    row = div(plot_idx - 1, 5) + 1
    col = mod(plot_idx - 1, 5) + 1
    
    input_image, output_image, source_idx = augmented_sets[aug_idx]
    m = all_metadata[aug_idx]
    
    # Create subplot for input image
    ax = Axis(fig4[row*2-1, col], aspect=DataAspect(),
              title="Sample #$(aug_idx)", titlesize=10)
    rgb_data = data(input_image)
    img_matrix = [RGB(rgb_data[i, j, 1], rgb_data[i, j, 2], rgb_data[i, j, 3]) 
                  for i in 1:size(rgb_data, 1), j in 1:size(rgb_data, 2)]
    img_rotated = rotr90(img_matrix)
    image!(ax, img_rotated)
    hidedecorations!(ax)
    
    # Create subplot for segmentation mask
    ax_mask = Axis(fig4[row*2, col], aspect=DataAspect())
    output_data = data(output_image)
    mask_matrix = [RGB(
        output_data[i, j, 1] + output_data[i, j, 4],
        output_data[i, j, 2] + output_data[i, j, 4],
        output_data[i, j, 3]
    ) for i in 1:size(output_data, 1), j in 1:size(output_data, 2)]
    mask_rotated = rotr90(mask_matrix)
    image!(ax_mask, mask_rotated)
    hidedecorations!(ax_mask)
    
    # Add metadata text below each pair
    param_text = "Src:$(m.source_index) | $(m.target_class)\nRot:$(round(m.rotation_angle,digits=0))° | Scale:$(round(m.scale_factor,digits=2))"
    Label(fig4[row*2+1, col], param_text, fontsize=8, halign=:center)
end

# Add legend
legend_text = "Classes: Scar(Red) | Redness(Green) | Hematoma(Blue) | Necrosis(Yellow) | Background(Black)"
Label(fig4[end+1, :], legend_text, fontsize=12, halign=:center)

# Save Figure 4
fig4_filename = joinpath(metadata_dir, "augmentation_sample_gallery.png")
save(fig4_filename, fig4)
println("  Saved: $(fig4_filename)")

# ============================================================================
# Figure 5: Summary Statistics Dashboard
# ============================================================================

println("Creating summary dashboard...")

fig5 = Figure(size=(1400, 900))
fig5[0, :] = Label(fig5, "Augmentation Summary Dashboard", fontsize=24, font=:bold)

# Statistics text panel
stats_text = """
Dataset Statistics:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Augmented Samples: $(length(all_metadata))
Original Source Images: $(length(sets))
Unique Sources Used: $(length(unique(source_indices)))
Image Size: $(augmented_size[1])×$(augmented_size[2]) pixels

Parameter Ranges:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scale Factor: $(round(minimum(scale_factors), digits=2)) - $(round(maximum(scale_factors), digits=2))
Rotation: $(round(minimum(rotation_angles), digits=1))° - $(round(maximum(rotation_angles), digits=1))°
Shear X: $(round(minimum(shear_x_angles), digits=1))° - $(round(maximum(shear_x_angles), digits=1))°
Shear Y: $(round(minimum(shear_y_angles), digits=1))° - $(round(maximum(shear_y_angles), digits=1))°
Brightness: $(round(minimum(brightness_factors), digits=2)) - $(round(maximum(brightness_factors), digits=2))
Saturation: $(round(minimum(saturation_offsets), digits=2)) - $(round(maximum(saturation_offsets), digits=2))
Blur σ: $(round(minimum(blur_sigmas), digits=2)) - $(round(maximum(blur_sigmas), digits=2))

Class Distribution:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scar: $(count(==(Symbol("scar")), target_classes)) samples ($(round(mean(scar_pcts), digits=2))% mean coverage)
Redness: $(count(==(Symbol("redness")), target_classes)) samples ($(round(mean(redness_pcts), digits=2))% mean coverage)
Hematoma: $(count(==(Symbol("hematoma")), target_classes)) samples ($(round(mean(hematoma_pcts), digits=2))% mean coverage)
Necrosis: $(count(==(Symbol("necrosis")), target_classes)) samples ($(round(mean(necrosis_pcts), digits=2))% mean coverage)
Background: $(count(==(Symbol("background")), target_classes)) samples ($(round(mean(background_pcts), digits=2))% mean coverage)
"""

Label(fig5[1, 1], stats_text, fontsize=12, halign=:left, valign=:top, font=:regular,
      tellwidth=false, tellheight=false)

# Pie chart for target class distribution
ax_pie = Axis(fig5[1, 2], title="Target Class Distribution", aspect=DataAspect())
hidedecorations!(ax_pie)
hidespines!(ax_pie)

pie_values = [count(==(c), target_classes) for c in class_order]
pie_colors = class_colors

# Simple pie chart using arcs - wrapped in let block for proper scope
let
    total = sum(pie_values)
    start_angle = 0.0
    for (i, (val, col)) in enumerate(zip(pie_values, pie_colors))
        angle = 2π * val / total
        end_angle = start_angle + angle
        
        # Draw pie slice as polygon
        n_points = max(10, round(Int, angle * 20))
        angles = range(start_angle, end_angle, length=n_points)
        xs = [0.0; cos.(angles)]
        ys = [0.0; sin.(angles)]
        poly!(ax_pie, Point2f.(xs, ys), color=col)
        
        # Add label
        mid_angle = (start_angle + end_angle) / 2
        label_r = 0.7
        text!(ax_pie, label_r * cos(mid_angle), label_r * sin(mid_angle),
              text="$(round(100*val/total, digits=1))%", fontsize=10, align=(:center, :center))
        
        start_angle = end_angle
    end
end

limits!(ax_pie, -1.3, 1.3, -1.3, 1.3)

# Save Figure 5
fig5_filename = joinpath(metadata_dir, "augmentation_summary_dashboard.png")
save(fig5_filename, fig5)
println("  Saved: $(fig5_filename)")

# ============================================================================
# Display all figures
# ============================================================================

println("\n=== Visualization Complete ===")
println("Generated 5 visualization files:")
println("  1. $(fig1_filename)")
println("  2. $(fig2_filename)")
println("  3. $(fig3_filename)")
println("  4. $(fig4_filename)")
println("  5. $(fig5_filename)")

# Display figures (if running interactively)
display(fig1)
display(fig2)
display(fig3)
display(fig4)
display(fig5)

println("\n✓ Balanced augmentation process complete!")
