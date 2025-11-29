# Load_Sets__DataLoading.jl
# Data loading and augmentation pipeline

"""
    Load_Sets__DataLoading

Data loading module for wound image datasets.
Handles loading from disk and generating augmented datasets.
"""

using Random
using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2
using Mmap

# Note: Requires Load_Sets__Config.jl to be loaded for base_path, input_type, raw_output_type

# ============================================================================
# Dataset Cache
# ============================================================================

# Global cache for loaded datasets to avoid reloading on subsequent calls
const _LOADED_SETS_CACHE = try
    _LOADED_SETS_CACHE
catch
    Dict{Int, Vector}()
end

# ============================================================================
# Original Dataset Loading
# ============================================================================

"""
    load_original_sets(length::Int=306, regenerate::Bool=false; resize_ratio=1) -> Vector{Tuple}

Load original wound image dataset from disk or generate from source.

# Arguments
- `length::Int`: Number of images to load (default: 306)
- `regenerate::Bool`: If true, regenerate from source images; if false, load from disk (default: false)
- `resize_ratio`: Ratio for image resizing (default: 1 = no resize, 1//4 = quarter size)

# Returns
- `Vector{Tuple}`: Vector of (input_image, output_mask, index) tuples

# Example
```julia
sets = load_original_sets(306, false)  # Load first 306 images from disk
sets = load_original_sets(306, true; resize_ratio=1)  # Regenerate at full resolution
```

# File Structure
- Loads from: `base_path/original/{index}.jld2`
- Generates from: `base_path/../MuHa - Bilder/`  (source images)
"""
function load_original_sets(_length::Int=306, regenerate_images::Bool=false; resize_ratio=1)
    # Check cache first
    if haskey(_LOADED_SETS_CACHE, _length) && !regenerate_images
        cached_sets = _LOADED_SETS_CACHE[_length]
        println("Using cached sets: $(length(cached_sets)) sets already loaded")
        return cached_sets
    end
    
    temp_sets = []
    _index_array = collect(1:_length)  # Sequential order for predictable UI mapping
    
    if regenerate_images == false
        println("Loading original sets from disk (first $((_length)) images)...")
        for index in 1:_length
            println("  Loading set $(index)/$(_length)")
            @time begin
                input, output = JLD2.load(joinpath(base_path, "original/$(index).jld2"), "set")
            end
            push!(temp_sets, (memory_map(input), memory_map(output), index))
        end
    else
        println("Generating original sets from source images (resize_ratio=$(resize_ratio))...")
        println("  (Memory-efficient mode: save immediately after each image)")
        for index in 1:_length
            println("  Loading and saving image $(index)/$(_length)")
            @time begin
                input, output = @__(Bas3ImageSegmentation.load_input_and_output(
                    resolve_path("C:/Syncthing/MuHa - Bilder"),
                    _index_array[index];
                    input_type=input_type,
                    output_type=raw_output_type,
                    output_collection=true,
                    resize_ratio=resize_ratio
                ))
                # Save immediately to avoid accumulating all images in memory
                JLD2.save(joinpath(base_path, "original/$(index).jld2"), "set", (input, output, _index_array[index]))
            end
            # Force garbage collection periodically to release memory
            if index % 10 == 0
                GC.gc()
            end
        end
        
        # Now load them back with memory mapping for the return value
        println("Loading saved sets with memory mapping...")
        for index in 1:_length
            input, output, idx = JLD2.load(joinpath(base_path, "original/$(index).jld2"), "set")
            push!(temp_sets, (memory_map(input), memory_map(output), idx))
        end
    end
    
    println("Original sets loaded: $(length(temp_sets)) sets")
    
    # Store in cache
    result = [temp_sets...]
    _LOADED_SETS_CACHE[_length] = result
    println("Cached $(length(result)) sets for future use")
    
    return result
end

# ============================================================================
# Augmentation Pipeline (For Reference)
# ============================================================================

"""
    generate_sets(; _length, _size, temp_augmented_sets, keywords...)

Generate augmented image sets with transformations.

# Note
This function is provided for reference but augmentation is currently disabled
in the main pipeline. The original Load_Sets.jl focuses on original images only.

# Augmentation Pipeline
1. Scale (0.9x to 1.1x)
2. Random crop
3. Shear X and Y (-10° to +10°)
4. Rotate (1° to 360°)
5. Crop to size
6. Random flip X/Y or no-op
7. Color jitter (brightness, saturation)
8. Gaussian blur
9. Elastic distortion

# Arguments
- `_length::Int`: Number of samples to generate
- `_size::Tuple`: Output image size (height, width)
- `temp_augmented_sets`: Source images for augmentation
- `keywords...`: Additional keyword arguments

# Returns
- `(inputs, outputs, image_indices)`: Augmented images and their source indices
"""
@__(function generate_sets(; _length, _size, temp_augmented_sets, keywords...)
    # Input preprocessing pipeline
    input_pipeline = ColorJitter(
        0.8:0.1:1.2,
        -0.2:0.1:0.2,
    ) |> GaussianBlur(
        3:2:7,
        1:0.1:3
    )
    
    # Post-processing pipeline
    post_pipeline = ElasticDistortion(
        8,
        8,
        0.2,
        2,
        1
    )
    
    # Main augmentation pipeline
    pipeline = Scale(
                   0.9:0.01:1.1
               ) |> RCropSize(
                   maximum(_size), maximum(_size)
               ) |> ShearX(
                   -10:0.1:10
               ) |> ShearY(
                   -10:0.1:10
               ) |> Rotate(
                   1:0.1:360
               ) |> CropSize(
                   maximum(_size), maximum(_size)
               ) |> Either(
                   1 => FlipX(),
                   1 => FlipY(),
                   1 => NoOp()
               )
    
    local inputs, outputs
    inputs = Vector{@__(input_type{_size})}(undef, _length)
    outputs = Vector{@__(raw_output_type{_size})}(undef, _length)
    image_indices = Vector{Int}(undef, _length)
    
    # Class-aware sampling (oversampling rare classes)
    class_indicies = shuffle([1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 4, 4, 4])
    class_indicies_length = length(class_indicies)
    class_indicies_index = 1
    
    for index in 1:_length
        class = class_indicies[class_indicies_index]
        class_indicies_index += 1
        if class_indicies_index > class_indicies_length
            class_indicies_index = 1
        end
        
        while true
            try
                local augmented_input, augmented_output, sample_index
                
                # Quality control loop: ensure >= 5% foreground
                while true
                    # Select random source (exclude problematic indices 8, 16)
                    while true
                        sample_index = rand(1:length(temp_augmented_sets))
                        if sample_index != 8 && sample_index != 16
                            break
                        end
                    end
                    
                    # Apply augmentation
                    input, output = temp_augmented_sets[sample_index]
                    augmented_input, augmented_output = augment((input, output), pipeline)
                    augmented_input, augmented_output = augment((augmented_input, augmented_output), CropSize(_size...))
                    augmented_output_data = data(augmented_output)
                    
                    # Check foreground area for target class
                    foreground_area = sum(augmented_output_data[:, :, class])
                    background_area = sum(augmented_output_data[:, :, 5])
                    area = foreground_area + background_area
                    
                    if (foreground_area / area) >= 0.05
                        break  # Quality threshold met
                    end
                end
                
                # Apply post-processing
                # Apply elastic distortion to both input and output in a SINGLE call
                # to ensure the same random displacement field is used for both
                augmented_input, augmented_output = augment((augmented_input, augmented_output), post_pipeline)
                # Apply color augmentation (brightness, saturation, blur) only to input
                inputs[index] = augment(augmented_input, input_pipeline)
                augmented_output = convert(raw_output_type, augmented_output)
                outputs[index] = augmented_output
                image_indices[index] = sample_index
                break
                
            catch error
                throw(error)
            end
        end
    end
    
    return inputs, outputs, image_indices
end; Transform=false)
