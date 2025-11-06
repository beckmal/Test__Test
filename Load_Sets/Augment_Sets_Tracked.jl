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
    augmented_index::Int
    source_index::Int
    timestamp::DateTime
    random_seed::UInt64
    
    # Quality metrics (informational, not used for filtering)
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
    # Simple round-robin selection, skipping excluded indices
    pool_size = length(tracker.usage_counts)
    max_attempts = pool_size * 2
    
    for _ in 1:max_attempts
        # Round-robin: cycle through all images
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

# Compute quality metrics without rejection
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
# Path Resolution Utilities
# ============================================================================

# Function to resolve paths based on operating system
# Converts C:/ paths to /mnt/c/ on WSL and vice versa
function resolve_path(relative_path::String)
    if Sys.iswindows()
        # Running on native Windows
        # Convert /mnt/c/ to C:/ if needed
        if startswith(relative_path, "/mnt/")
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        # Running on Linux/WSL
        # Convert C:/ to /mnt/c/ if needed
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

# Base path for datasets - will be converted based on OS
base_path = resolve_path("C:/Syncthing/Datasets")

println("\n=== Loading Original Dataset ===")

const sets = try
    sets
catch
    let
        temp_sets = []
        _length = 306  # Total number of images in dataset
        
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
# Data Augmentation Pipeline (Simplified & Trackable)
# ============================================================================

# Generate augmented dataset WITHOUT class-aware sampling or rejection loops
@__(function generate_augmented_sets(; 
    _length, 
    _size, 
    temp_augmented_sets, 
    excluded_indices,
    start_index=1,
    keywords...
)
    println("\n=== Configuring Augmentation Pipeline ===")
    
    # Input pipeline: color and blur augmentation
    input_pipeline = ColorJitter(
        0.8:0.1:1.2,      # Brightness range
        -0.2:0.1:0.2      # Saturation range
    ) |> GaussianBlur(
        3:2:7,            # Kernel size range
        1:0.1:3           # Sigma range
    )
    
    # Post pipeline: elastic distortion for realistic deformation
    post_pipeline = ElasticDistortion(
        8,                # Grid height
        8,                # Grid width
        0.2,              # Scale
        2,                # Sigma
        1                 # Iterations
    )
    
    # Main pipeline: geometric transformations
    pipeline = Scale(
        0.9:0.01:1.1      # Scale factor range (90%-110%)
    ) |> RCropSize(
        maximum(_size), maximum(_size)  # Random crop to max size
    ) |> ShearX(
        -10:0.1:10        # Horizontal shear angle range
    ) |> ShearY(
        -10:0.1:10        # Vertical shear angle range
    ) |> Rotate(
        1:0.1:360         # Rotation angle range
    ) |> CropSize(
        maximum(_size), maximum(_size)  # Final crop to desired size
    ) |> Either(
        1 => FlipX(),     # Horizontal flip
        1 => FlipY(),     # Vertical flip
        1 => NoOp()       # No flip
    )
    
    println("  Input pipeline: ColorJitter + GaussianBlur")
    println("  Post pipeline: ElasticDistortion")
    println("  Main pipeline: Scale → Crop → Shear → Rotate → Flip")
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
            # Select source image (round-robin, no class bias)
            sample_index = select_source_image!(tracker, excluded_indices)
            
            # Generate random seed for reproducibility
            random_seed = rand(UInt64)
            
            # Apply augmentation pipeline (no rejection - accept all)
            input, output = temp_augmented_sets[sample_index]
            augmented_input, augmented_output = augment((input, output), pipeline)
            augmented_input, augmented_output = augment((augmented_input, augmented_output), CropSize(_size...))
            
            # Apply post-processing
            inputs[index] = augment(augmented_input, post_pipeline |> input_pipeline)
            augmented_output = augment(augmented_output, post_pipeline)
            augmented_output = convert(raw_output_type, augmented_output)
            outputs[index] = augmented_output
            image_indices[index] = sample_index
            
            # Compute quality metrics (informational only, no filtering)
            augmented_output_data = data(augmented_output)
            quality = compute_quality_metrics(augmented_output_data)
            
            # Create metadata
            metadata_list[index] = AugmentationMetadata(
                start_index + index - 1,  # Global augmented index
                sample_index,
                now(),
                random_seed,
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
    
    println("\n✓ Augmentation complete: $(_length) samples generated")
    return inputs, outputs, image_indices, metadata_list, tracker
end; Transform=false)

# ============================================================================
# Generate and Save Augmented Dataset
# ============================================================================

println("\n=== Starting Augmentation Process ===")

# Configuration
const total_augmented_length = 100  # Total number of augmented samples to generate
const batch_size = 50               # Process in batches to manage memory
const augmented_size = (100, 50)    # Size of augmented images (width, height)
const load_from_disk = false        # Set to true to load existing augmented data
const excluded_source_indices = Set([8, 16])  # Problematic source images to exclude

# Create augmented directory if it doesn't exist
augmented_dir = joinpath(base_path, "augmented")
metadata_dir = joinpath(base_path, "augmented_metadata")
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
        
        if load_from_disk
            println("\n=== Loading Augmented Sets from Disk ===")
            for index in 1:total_augmented_length
                println("  Loading augmented set $(index)/$(total_augmented_length)")
                @time begin
                    input, output = JLD2.load(joinpath(base_path, "augmented/$(index).jld2"), "set")
                end
                image_index = get(sets[mod1(index, length(sets))], 3, index)
                push!(temp_augmented_sets, (memory_map(input), memory_map(output), image_index))
            end
            println("✓ Augmented sets loaded: $(length(temp_augmented_sets)) sets")
        else
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
                    
                    # Merge batch tracker into global tracker
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
                    
                    # Save image data
                    JLD2.save(
                        joinpath(base_path, "augmented/$(augmented_length).jld2"),
                        "set",
                        (augmented_inputs[index], augmented_outputs[index])
                    )
                    
                    # Save metadata
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
            
            # Generate usage report
            println("\n" * "="^70)
            println("SOURCE IMAGE USAGE STATISTICS")
            println("="^70)
            println("Total augmented samples: $(length(all_metadata))")
            println("Total source selections: $(global_tracker.total_selections)")
            println("\nUsage distribution:")
            for (idx, count) in enumerate(global_tracker.usage_counts)
                if count > 0
                    pct = count / sum(global_tracker.usage_counts) * 100
                    println("  Source #$(idx): $(count) times ($(round(pct, digits=1))%)")
                end
            end
            
            # Quality metrics summary
            println("\n" * "="^70)
            println("QUALITY METRICS SUMMARY (Informational)")
            println("="^70)
            
            scar_pcts = [m.scar_percentage for m in all_metadata]
            redness_pcts = [m.redness_percentage for m in all_metadata]
            hematoma_pcts = [m.hematoma_percentage for m in all_metadata]
            necrosis_pcts = [m.necrosis_percentage for m in all_metadata]
            
            println("Mean foreground percentage per class:")
            println("  Scar:     $(round(mean(scar_pcts), digits=2))% ± $(round(std(scar_pcts), digits=2))%")
            println("  Redness:  $(round(mean(redness_pcts), digits=2))% ± $(round(std(redness_pcts), digits=2))%")
            println("  Hematoma: $(round(mean(hematoma_pcts), digits=2))% ± $(round(std(hematoma_pcts), digits=2))%")
            println("  Necrosis: $(round(mean(necrosis_pcts), digits=2))% ± $(round(std(necrosis_pcts), digits=2))%")
            
            # Count samples below 5% threshold (for comparison with old method)
            println("\nSamples with <5% foreground (would have been rejected in old pipeline):")
            println("  Scar:     $(count(<(5), scar_pcts)) samples ($(round(count(<(5), scar_pcts)/length(scar_pcts)*100, digits=1))%)")
            println("  Redness:  $(count(<(5), redness_pcts)) samples ($(round(count(<(5), redness_pcts)/length(redness_pcts)*100, digits=1))%)")
            println("  Hematoma: $(count(<(5), hematoma_pcts)) samples ($(round(count(<(5), hematoma_pcts)/length(hematoma_pcts)*100, digits=1))%)")
            println("  Necrosis: $(count(<(5), necrosis_pcts)) samples ($(round(count(<(5), necrosis_pcts)/length(necrosis_pcts)*100, digits=1))%)")
            println("="^70)
        end
        
        [temp_augmented_sets...]
    end
end

# ============================================================================
# Summary Statistics
# ============================================================================

println("\n" * "="^70)
println("AUGMENTATION SUMMARY")
println("="^70)
println("Original dataset size:    $(length(sets)) images")
println("Augmented dataset size:   $(length(augmented_sets)) images")
println("Augmented image size:     $(augmented_size[1])x$(augmented_size[2]) pixels")
println("Storage location:         $(joinpath(base_path, "augmented"))")
println("Metadata location:        $(joinpath(base_path, "augmented_metadata"))")
println("="^70)

# ============================================================================
# Visualize Sample Augmentations
# ============================================================================

println("\n=== Creating Visualization ===")

# Select a few random samples to visualize
sample_indices = rand(1:length(augmented_sets), min(6, length(augmented_sets)))

fig = Figure(size=(1800, 1200))
fig[0, :] = Label(fig, "Data Augmentation Results - Sample Images (Tracked Pipeline)", fontsize=24, font=:bold)

for (plot_idx, aug_idx) in enumerate(sample_indices)
    row = div(plot_idx - 1, 3) + 1
    col = mod(plot_idx - 1, 3) + 1
    
    input_image, output_image, source_idx = augmented_sets[aug_idx]
    
    # Display input image (RGB)
    ax_input = Axis(fig[row*2-1, col], title="Augmented #$(aug_idx) (from #$(source_idx)) - Input", aspect=DataAspect())
    rgb_data = data(input_image)
    # Convert to matrix of RGB color objects and rotate
    img_matrix = [RGB(rgb_data[i, j, 1], rgb_data[i, j, 2], rgb_data[i, j, 3]) 
                  for i in 1:size(rgb_data, 1), j in 1:size(rgb_data, 2)]
    img_rotated = rotr90(img_matrix)
    image!(ax_input, img_rotated)
    hidedecorations!(ax_input)
    
    # Display output segmentation mask
    ax_output = Axis(fig[row*2, col], title="Segmentation Mask", aspect=DataAspect())
    output_data = data(output_image)
    # Create RGB visualization: red=scar, green=redness, blue=hematoma, yellow=necrosis
    # Convert to matrix of RGB color objects and rotate
    mask_matrix = [RGB(
        output_data[i, j, 1] + output_data[i, j, 4],  # Red channel
        output_data[i, j, 2] + output_data[i, j, 4],  # Green channel
        output_data[i, j, 3]                           # Blue channel
    ) for i in 1:size(output_data, 1), j in 1:size(output_data, 2)]
    mask_rotated = rotr90(mask_matrix)
    image!(ax_output, mask_rotated)
    hidedecorations!(ax_output)
end

# Add legend
legend_text = """
Classes:
  • Scar (Red)
  • Redness (Green)
  • Hematoma (Blue)
  • Necrosis (Yellow)
  • Background (Black)

Augmentation Pipeline (Tracked):
  1. Color jitter & blur
  2. Scale (90-110%)
  3. Shear & rotation
  4. Random flip
  5. Elastic distortion

Improvements:
  ✓ No class oversampling
  ✓ No rejection loops
  ✓ Full metadata tracking
  ✓ Uniform source distribution
"""

Label(fig[end+1, :], legend_text, fontsize=12, halign=:left, tellwidth=false)

# Save figure
output_filename = "Augmented_Dataset_Tracked_$(length(augmented_sets))_images.png"
println("Saving visualization: $(output_filename)")
save(output_filename, fig)

display(fig)

println("\n✓ Augmentation process complete!")
println("Image files saved to: $(joinpath(base_path, "augmented"))")
println("Metadata files saved to: $(joinpath(base_path, "augmented_metadata"))")
println("Visualization saved: $(output_filename)")
println("\nTo access metadata, load: $(joinpath(metadata_dir, "augmentation_summary.jld2"))")
