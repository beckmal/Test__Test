# Load_Sets__DataLoading.jl
# Data loading and augmentation pipeline

"""
    Load_Sets__DataLoading

Data loading module for wound image datasets.
Handles loading from disk and generating augmented datasets.

Storage architecture:
- Binary files (.bin): Raw image data for memory-mapped access
- JLD2 files (.jld2): Metadata only (dims, element types, index)

This design provides:
- Efficient mmap access (OS handles paging)
- Small metadata files (~1KB vs ~97MB)
- No redundant data storage
"""

using Random
using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2
using Mmap

# Note: Requires Load_Sets__Config.jl to be loaded for base_path, input_type, raw_output_type

# ============================================================================
# Dataset Cache
# ============================================================================

# Global cache for open file handles (to keep mmaps valid)
const _MMAP_FILE_HANDLES = try
    _MMAP_FILE_HANDLES
catch
    Dict{String, IOStream}()
end

# ============================================================================
# File-Backed Memory Mapping
# ============================================================================

"""
    save_image_binary(file_path, image_data) -> (dims, element_type)

Save image data to a raw binary file for memory mapping.
Returns the dimensions of the saved array and the element type.
Preserves the original data type (e.g., N0f8) for efficient storage.
"""
function save_image_binary(file_path::String, image_data)
    # Get raw data - may be Array or VectorOfArray depending on image type
    d = data(image_data)
    
    # Get dimensions and element type from the type parameters
    T = typeof(image_data)
    if T <: v__Image_Data_Static_Channel
        # Extract from type: v__Image_Data_Static_Channel{type, size_type, shape_type, ...}
        size_type = T.parameters[2]
        shape_type = T.parameters[3]
        h, w = parameters(size_type)
        c = length(parameters(shape_type))
        dims = (h, w, c)
        # Get element type from the channel data
        elem_type = eltype(d[:, :, 1])
    elseif T <: v__Image_Data_Static_Data
        # Extract from type: v__Image_Data_Static_Data{type, size_type, shape_type, data_type}
        size_type = T.parameters[2]
        shape_type = T.parameters[3]
        h, w = parameters(size_type)
        c = length(parameters(shape_type))
        dims = (h, w, c)
        elem_type = T.parameters[1]  # element type from type parameter
    else
        # Fallback: try to get size from data
        dims = size(d)
        elem_type = eltype(d)
    end
    
    # Convert to contiguous array preserving original element type
    arr = Array{elem_type}(undef, dims...)
    for i in 1:dims[3]
        arr[:, :, i] .= d[:, :, i]
    end
    
    open(file_path, "w") do io
        write(io, arr)
    end
    return (dims, elem_type)
end

"""
    load_image_mmap(file_path, dims, element_type) -> Array

Load image data using file-backed memory mapping.
This maps the file directly into virtual memory without loading into RAM.
"""
function load_image_mmap(file_path::String, dims::Tuple, element_type::Type)
    # Keep file handle open to maintain mmap validity
    if !haskey(_MMAP_FILE_HANDLES, file_path)
        _MMAP_FILE_HANDLES[file_path] = open(file_path, "r")
    end
    io = _MMAP_FILE_HANDLES[file_path]
    seekstart(io)
    return Mmap.mmap(io, Array{element_type, length(dims)}, dims)
end

"""
    MmapImageSet

A struct that holds file-backed memory-mapped image data.
The actual data is only loaded into RAM when accessed, and the OS
handles paging data in/out automatically.
"""
struct MmapImageSet
    input_path::String
    output_path::String
    input_dims::Tuple{Int,Int,Int}
    output_dims::Tuple{Int,Int,Int}
    input_elem_type::Type
    output_elem_type::Type
    input_type::Any
    output_type::Any
    index::Int
end

"""
    get_input(mset::MmapImageSet) -> Image

Get the input image, memory-mapped from disk.
"""
function get_input(mset::MmapImageSet)
    mapped_data = load_image_mmap(mset.input_path, mset.input_dims, mset.input_elem_type)
    # Reconstruct the image type from mapped data
    # Pass each channel slice separately to the constructor
    # Convert to Float32 for compatibility with image processing functions
    h, w, c = mset.input_dims
    channels = ntuple(i -> Float32.(@view(mapped_data[:, :, i])), c)
    return mset.input_type(channels...)
end

"""
    get_output(mset::MmapImageSet) -> Image

Get the output image, memory-mapped from disk.
"""
function get_output(mset::MmapImageSet)
    mapped_data = load_image_mmap(mset.output_path, mset.output_dims, mset.output_elem_type)
    # Pass each channel slice separately to the constructor
    # Convert to Float32 for compatibility with image processing functions
    h, w, c = mset.output_dims
    channels = ntuple(i -> Float32.(@view(mapped_data[:, :, i])), c)
    return mset.output_type(channels...)
end

# Make MmapImageSet indexable like a tuple: set[1]=input, set[2]=output, set[3]=index
function Base.getindex(mset::MmapImageSet, i::Int)
    if i == 1
        return get_input(mset)
    elseif i == 2
        return get_output(mset)
    elseif i == 3
        return mset.index
    else
        throw(BoundsError(mset, i))
    end
end
Base.length(::MmapImageSet) = 3
Base.iterate(mset::MmapImageSet) = (get_input(mset), 2)
function Base.iterate(mset::MmapImageSet, state::Int)
    if state == 2
        return (get_output(mset), 3)
    elseif state == 3
        return (mset.index, 4)
    else
        return nothing
    end
end

# ============================================================================
# Original Dataset Loading
# ============================================================================

"""
    load_original_sets(length::Int=306, regenerate::Bool=false; resize_ratio=1) -> Vector{MmapImageSet}

Load original wound image dataset from disk or generate from source.

# Arguments
- `length::Int`: Number of images to load (default: 306)
- `regenerate::Bool`: If true, regenerate from source images; if false, load from disk (default: false)
- `resize_ratio`: Ratio for image resizing (default: 1 = no resize, 1//4 = quarter size)

# Returns
- `Vector{MmapImageSet}`: Vector of memory-mapped image set wrappers

# File Structure (binary-only with JLD2 metadata)
- Binary input data: `base_path/original/{index}_input.bin`
- Binary output data: `base_path/original/{index}_output.bin`
- JLD2 metadata: `base_path/original/{index}_meta.jld2` (dims, elem_types, index only)
"""
function load_original_sets(_length::Int=306, regenerate_images::Bool=false; resize_ratio=1)
    temp_sets = Vector{MmapImageSet}()
    _index_array = collect(1:_length)  # Sequential order for predictable UI mapping
    original_dir = joinpath(base_path, "original")
    
    if regenerate_images
        println("Generating original sets from source images (resize_ratio=$(resize_ratio))...")
        println("  Storage: binary files + JLD2 metadata (no image data in JLD2)")
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
                
                # Save binary files for memory mapping
                input_bin_path = joinpath(original_dir, "$(index)_input.bin")
                output_bin_path = joinpath(original_dir, "$(index)_output.bin")
                input_dims, input_elem_type = save_image_binary(input_bin_path, input)
                output_dims, output_elem_type = save_image_binary(output_bin_path, output)
                
                # Save metadata only to JLD2 (no image data!)
                meta_path = joinpath(original_dir, "$(index)_meta.jld2")
                JLD2.save(meta_path, "metadata", (
                    input_dims=input_dims,
                    output_dims=output_dims,
                    input_elem_type=input_elem_type,
                    output_elem_type=output_elem_type,
                    index=_index_array[index]
                ))
            end
            # Force garbage collection periodically to release memory
            if index % 10 == 0
                GC.gc()
            end
        end
        println("Regeneration complete.")
    end
    
    # Load sets from binary files + metadata
    println("Creating file-backed memory maps for $(_length) images...")
    for index in 1:_length
        input_bin_path = joinpath(original_dir, "$(index)_input.bin")
        output_bin_path = joinpath(original_dir, "$(index)_output.bin")
        meta_path = joinpath(original_dir, "$(index)_meta.jld2")
        
        if !isfile(input_bin_path) || !isfile(output_bin_path) || !isfile(meta_path)
            error("Missing files for image $(index). Run with regenerate=true to create them.")
        end
        
        # Load metadata
        metadata = JLD2.load(meta_path, "metadata")
        
        mset = MmapImageSet(
            input_bin_path,
            output_bin_path,
            metadata.input_dims,
            metadata.output_dims,
            metadata.input_elem_type,
            metadata.output_elem_type,
            input_type,
            raw_output_type,
            metadata.index
        )
        push!(temp_sets, mset)
        
        if index == 1 || index % 50 == 0 || index == _length
            println("  Prepared $(index)/$(_length) images")
        end
    end
    
    println("File-backed memory maps ready (data loaded on-demand by OS)")
    println("Original sets ready: $(length(temp_sets)) sets")
    return temp_sets
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
