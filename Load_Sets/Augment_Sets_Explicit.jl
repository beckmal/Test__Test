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
    println("Loading Bas3ImageSegmentation.Augmentor...")
    using Bas3ImageSegmentation.Augmentor: Crop
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
# Enhanced Augmentation Metadata with Explicit Parameters
# ============================================================================

struct AugmentationMetadata
    # Basic info
    augmented_index::Int
    source_index::Int
    timestamp::DateTime
    random_seed::UInt64
    
    # Main pipeline parameters (geometric transformations)
    scale_factor::Float64
    crop_y_start::Int          # After scale, before shear/rotate
    crop_x_start::Int
    crop_height::Int
    crop_width::Int
    shear_x_angle::Float64
    shear_y_angle::Float64
    rotation_angle::Float64
    flip_type::Symbol          # :flipx, :flipy, or :noop
    
    # Post pipeline (elastic distortion - fixed params for now)
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
    
    # Final crop to target size (after all transformations)
    final_crop_y_start::Int
    final_crop_x_start::Int
    final_crop_height::Int
    final_crop_width::Int
    
    # Quality metrics (computed after augmentation)
    scar_percentage::Float64
    redness_percentage::Float64
    hematoma_percentage::Float64
    necrosis_percentage::Float64
    background_percentage::Float64
end

# Track source image usage
mutable struct SourceImageTracker
    usage_counts::Vector{Int}
    selection_history::Vector{Int}
    total_selections::Int
end

function SourceImageTracker(num_sources::Int)
    return SourceImageTracker(
        zeros(Int, num_sources),
        Int[],
        0
    )
end

function select_source_image!(tracker::SourceImageTracker, excluded_indices::Set{Int})
    pool_size = length(tracker.usage_counts)
    max_attempts = pool_size * 2
    
    for _ in 1:max_attempts
        candidate_idx = (tracker.total_selections % pool_size) + 1
        
        if !(candidate_idx in excluded_indices)
            tracker.total_selections += 1
            tracker.usage_counts[candidate_idx] += 1
            push!(tracker.selection_history, candidate_idx)
            return candidate_idx
        else
            tracker.total_selections += 1
        end
    end
    
    error("Unable to find valid source image after $(max_attempts) attempts")
end

# Compute quality metrics
function compute_quality_metrics(output_data)
    total_pixels = size(output_data, 1) * size(output_data, 2)
    
    scar_area = sum(output_data[:, :, 1])
    redness_area = sum(output_data[:, :, 2])
    hematoma_area = sum(output_data[:, :, 3])
    necrosis_area = sum(output_data[:, :, 4])
    background_area = sum(output_data[:, :, 5])
    
    return (
        scar_pct = scar_area / total_pixels * 100,
        redness_pct = redness_area / total_pixels * 100,
        hematoma_pct = hematoma_area / total_pixels * 100,
        necrosis_pct = necrosis_area / total_pixels * 100,
        background_pct = background_area / total_pixels * 100
    )
end

# ============================================================================
# Explicit Parameter Sampling
# ============================================================================

"""
Sample all augmentation parameters explicitly using a random seed.
Returns a NamedTuple with all parameter values.
"""
function sample_augmentation_parameters(; seed::UInt64, source_size, target_size)
    Random.seed!(seed)
    
    # Main pipeline parameters
    scale_factor = rand(0.9:0.01:1.1)
    
    # Calculate crop coordinates for RCropSize equivalent
    # After scaling, we crop to maximum(target_size)
    scaled_h = round(Int, source_size[1] * scale_factor)
    scaled_w = round(Int, source_size[2] * scale_factor)
    crop_size = maximum(target_size)
    
    if scaled_h >= crop_size && scaled_w >= crop_size
        crop_y_start = rand(1:(scaled_h - crop_size + 1))
        crop_x_start = rand(1:(scaled_w - crop_size + 1))
    else
        crop_y_start = 1
        crop_x_start = 1
    end
    
    shear_x_angle = rand(-10:0.1:10)
    shear_y_angle = rand(-10:0.1:10)
    rotation_angle = rand(1:0.1:360)
    flip_type = rand([:flipx, :flipy, :noop])
    
    # Input pipeline parameters (color and blur)
    brightness_factor = rand(0.8:0.1:1.2)
    saturation_offset = rand(-0.2:0.1:0.2)
    blur_kernel_size = rand(3:2:7)
    blur_sigma = rand(1:0.1:3)
    
    # Final crop to exact target size
    # After all transformations, image might be slightly larger
    # We'll determine these coordinates after transformations
    final_crop_y_start = 1
    final_crop_x_start = 1
    final_crop_height = target_size[1]
    final_crop_width = target_size[2]
    
    return (
        scale_factor = scale_factor,
        crop_y_start = crop_y_start,
        crop_x_start = crop_x_start,
        crop_height = crop_size,
        crop_width = crop_size,
        shear_x_angle = shear_x_angle,
        shear_y_angle = shear_y_angle,
        rotation_angle = rotation_angle,
        flip_type = flip_type,
        brightness_factor = brightness_factor,
        saturation_offset = saturation_offset,
        blur_kernel_size = blur_kernel_size,
        blur_sigma = blur_sigma,
        final_crop_y_start = final_crop_y_start,
        final_crop_x_start = final_crop_x_start,
        final_crop_height = final_crop_height,
        final_crop_width = final_crop_width
    )
end

"""
Build augmentation pipelines from explicit parameters.
Returns (main_pipeline, input_pipeline, post_pipeline).
"""
function build_pipelines_from_params(params)
    # Main geometric pipeline with explicit parameters
    main_pipeline = Scale(params.scale_factor) |>
                    Crop(
                        params.crop_y_start:(params.crop_y_start + params.crop_height - 1),
                        params.crop_x_start:(params.crop_x_start + params.crop_width - 1)
                    ) |>
                    ShearX(params.shear_x_angle) |>
                    ShearY(params.shear_y_angle) |>
                    Rotate(params.rotation_angle) |>
                    CropSize(params.crop_height, params.crop_width)
    
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
    
    # Post pipeline (elastic distortion - using fixed params)
    post_pipeline = ElasticDistortion(8, 8, 0.2, 2, 1)
    
    return main_pipeline, input_pipeline, post_pipeline
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
            println("  Loading set $(index)/$(_length)")
            @time begin
                input, output = JLD2.load(joinpath(base_path, "original/$(index).jld2"), "set")
            end
            push!(temp_sets, (memory_map(input), memory_map(output), index))
        end
        println("Original sets loaded: $(length(temp_sets)) sets")
        [temp_sets...]
    end
end

# ============================================================================
# Data Augmentation with Explicit Parameter Tracking
# ============================================================================

@__(function generate_augmented_sets(; 
    _length, 
    _size, 
    temp_augmented_sets, 
    excluded_indices,
    start_index=1,
    keywords...
)
    println("\n=== Configuring Augmentation with Explicit Parameters ===")
    println("  All transformation parameters will be sampled explicitly and tracked")
    println("  Excluded source indices: $(collect(excluded_indices))")
    
    # Initialize output arrays
    local inputs, outputs
    inputs = Vector{@__(input_type{_size})}(undef, _length)
    outputs = Vector{@__(raw_output_type{_size})}(undef, _length)
    image_indices = Vector{Int}(undef, _length)
    metadata_list = Vector{AugmentationMetadata}(undef, _length)
    
    # Initialize source image tracker
    tracker = SourceImageTracker(length(temp_augmented_sets))
    
    println("\n=== Generating Augmented Images ===")
    println("  Target: $(_length) augmented samples")
    println("  Size: $(_size)")
    println("  Source pool: $(length(temp_augmented_sets)) images")
    println("  Selection strategy: Round-robin (uniform distribution)")
    
    for index in 1:_length
        if index % 10 == 1 || index == _length
            println("  Generating augmented sample $(index)/$(_length)")
        end
        
        try
            # Select source image
            sample_index = select_source_image!(tracker, excluded_indices)
            input, output = temp_augmented_sets[sample_index]
            
            # Generate random seed for this sample
            random_seed = rand(UInt64)
            
            # Sample all parameters explicitly
            source_size = size(data(input))
            params = sample_augmentation_parameters(
                seed=random_seed,
                source_size=source_size,
                target_size=_size
            )
            
            # Build pipelines from explicit parameters
            main_pipeline, input_pipeline, post_pipeline = build_pipelines_from_params(params)
            
            # Apply augmentation pipelines
            augmented_input, augmented_output = augment((input, output), main_pipeline)
            augmented_input, augmented_output = augment(
                (augmented_input, augmented_output), 
                CropSize(_size...)
            )
            
            # Apply post-processing
            inputs[index] = augment(augmented_input, post_pipeline |> input_pipeline)
            augmented_output = augment(augmented_output, post_pipeline)
            augmented_output = convert(raw_output_type, augmented_output)
            outputs[index] = augmented_output
            image_indices[index] = sample_index
            
            # Compute quality metrics
            augmented_output_data = data(augmented_output)
            quality = compute_quality_metrics(augmented_output_data)
            
            # Create comprehensive metadata with all parameters
            metadata_list[index] = AugmentationMetadata(
                start_index + index - 1,
                sample_index,
                now(),
                random_seed,
                # Geometric parameters
                params.scale_factor,
                params.crop_y_start,
                params.crop_x_start,
                params.crop_height,
                params.crop_width,
                params.shear_x_angle,
                params.shear_y_angle,
                params.rotation_angle,
                params.flip_type,
                # Elastic distortion (fixed)
                8, 8, 0.2, 2.0, 1,
                # Color/blur parameters
                params.brightness_factor,
                params.saturation_offset,
                params.blur_kernel_size,
                params.blur_sigma,
                # Final crop
                params.final_crop_y_start,
                params.final_crop_x_start,
                params.final_crop_height,
                params.final_crop_width,
                # Quality metrics
                quality.scar_pct,
                quality.redness_pct,
                quality.hematoma_pct,
                quality.necrosis_pct,
                quality.background_pct
            )
            
        catch error
            println("    Error during augmentation of sample $(index)")
            println("    Error type: $(typeof(error))")
            println("    Error message: $(error)")
            throw(error)
        end
    end
    
    println("\n✓ Augmentation complete: $(_length) samples generated with explicit parameters")
    return inputs, outputs, image_indices, metadata_list, tracker
end; Transform=false)

# ============================================================================
# Generate and Save Augmented Dataset
# ============================================================================

println("\n=== Starting Augmentation Process ===")

const total_augmented_length = 100  # Number of augmented samples to generate
const batch_size = 50               # Process in batches to manage memory
const augmented_size = (100, 50)    # Size of augmented images (width, height)
const load_from_disk = false        # Set to true to load existing augmented data
const excluded_source_indices = Set([8, 16])  # Problematic source images to exclude

# Create directories
augmented_dir = joinpath(base_path, "augmented_explicit")
metadata_dir = joinpath(base_path, "augmented_explicit_metadata")
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
        global_tracker = SourceImageTracker(length(sets))
        
        if !load_from_disk
            println("\n=== Generating and Saving Augmented Sets ===")
            augmented_length = 0
            batch_count = 0
            
            while true
                batch_count += 1
                remaining = total_augmented_length - augmented_length
                current_batch_size = min(batch_size, remaining)
                
                println("\n--- Batch $(batch_count) ---")
                println("  Generating $(current_batch_size) samples ($(augmented_length + 1)-$(augmented_length + current_batch_size)/$(total_augmented_length))")
                
                @time begin
                    augmented_inputs, augmented_outputs, image_indices, metadata_list, batch_tracker = @__(generate_augmented_sets(
                        _length=current_batch_size,
                        _size=augmented_size,
                        temp_augmented_sets=sets,
                        excluded_indices=excluded_source_indices,
                        start_index=augmented_length + 1
                    ))
                    
                    global_tracker.usage_counts .+= batch_tracker.usage_counts
                    append!(global_tracker.selection_history, batch_tracker.selection_history)
                    global_tracker.total_selections += batch_tracker.total_selections
                end
                
                println("  Saving augmented samples and metadata to disk...")
                for index in 1:length(augmented_inputs)
                    augmented_length += 1
                    if index % 10 == 1 || index == length(augmented_inputs)
                        println("    Saving augmented set $(augmented_length)/$(total_augmented_length)")
                    end
                    
                    JLD2.save(
                        joinpath(augmented_dir, "$(augmented_length).jld2"),
                        "set",
                        (augmented_inputs[index], augmented_outputs[index])
                    )
                    
                    JLD2.save(
                        joinpath(metadata_dir, "$(augmented_length)_metadata.jld2"),
                        "metadata",
                        metadata_list[index]
                    )
                    
                    push!(temp_augmented_sets, (
                        memory_map(augmented_inputs[index]),
                        memory_map(augmented_outputs[index]),
                        image_indices[index]
                    ))
                    
                    push!(all_metadata, metadata_list[index])
                    
                    if augmented_length >= total_augmented_length
                        break
                    end
                end
                
                if augmented_length >= total_augmented_length
                    break
                end
            end
            
            println("\n✓ Augmented sets generated and saved: $(length(temp_augmented_sets)) sets")
            
            # Save aggregate statistics
            println("\n=== Saving Aggregate Metrics ===")
            JLD2.save(
                joinpath(metadata_dir, "augmentation_summary.jld2"),
                "all_metadata", all_metadata,
                "source_usage_counts", global_tracker.usage_counts,
                "selection_history", global_tracker.selection_history,
                "total_selections", global_tracker.total_selections,
                "excluded_indices", collect(excluded_source_indices),
                "generation_timestamp", now()
            )
            
            # Print sample parameters
            println("\n" * "="^70)
            println("SAMPLE AUGMENTATION PARAMETERS")
            println("="^70)
            if length(all_metadata) > 0
                m = all_metadata[1]
                println("Sample #1 parameters:")
                println("  Source: #$(m.source_index)")
                println("  Seed: $(m.random_seed)")
                println("  Scale: $(round(m.scale_factor, digits=3))x")
                println("  Crop: ($(m.crop_y_start), $(m.crop_x_start)) → ($(m.crop_height)x$(m.crop_width))")
                println("  Shear: X=$(round(m.shear_x_angle, digits=2))°, Y=$(round(m.shear_y_angle, digits=2))°")
                println("  Rotation: $(round(m.rotation_angle, digits=2))°")
                println("  Flip: $(m.flip_type)")
                println("  Brightness: $(round(m.brightness_factor, digits=2))")
                println("  Saturation: $(round(m.saturation_offset, digits=2))")
                println("  Blur: kernel=$(m.blur_kernel_size), σ=$(round(m.blur_sigma, digits=2))")
            end
            println("="^70)
        end
        
        [temp_augmented_sets...]
    end
end

println("\n" * "="^70)
println("AUGMENTATION SUMMARY (EXPLICIT PARAMETERS)")
println("="^70)
println("Original dataset size:    $(length(sets)) images")
println("Augmented dataset size:   $(length(augmented_sets)) images")
println("Augmented image size:     $(augmented_size[1])x$(augmented_size[2]) pixels")
println("Storage location:         $(joinpath(base_path, "augmented_explicit"))")
println("Metadata location:        $(joinpath(base_path, "augmented_explicit_metadata"))")
println("Parameters tracked:       17 transformation parameters per sample")
println("="^70)

println("\n✓ Augmentation process complete with explicit parameter tracking!")
println("Image files saved to: $(joinpath(base_path, "augmented_explicit"))")
println("Metadata files saved to: $(joinpath(base_path, "augmented_explicit_metadata"))")
println("\nTo access metadata, load: $(joinpath(metadata_dir, "augmentation_summary.jld2"))")
