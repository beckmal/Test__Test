# ============================================================================
# Image Loader Helper (Shared)
# ============================================================================

function img_loader(base_path, Number_of_Dataset; idtype = "raw", filetype = "jpg")
    id_str = lpad(Number_of_Dataset, 3, '0')
    img_path = joinpath([base_path, "MuHa_$(id_str)", "MuHa_$(id_str)_$(idtype).$(filetype)"])
    return ImageMagick.load_(img_path)
end

import Bas3.is_iterable

# ============================================================================
# UNIFIED IMAGE LOADING API (v2.0.0)
# ============================================================================

"""
    load_images(base_path, data_index; kwargs...) -> Image | Tuple{Image, Image}

Universal image loading function for Bas3ImageSegmentation (v2.0.0+).

# Behavior Modes
The function automatically detects what to load based on provided parameters:

1. **Pair Mode** (when `output_type` is provided):
   - Loads raw_adj.png → input image
   - Loads seg_*.png → output image  
   - Returns: `(input, output)` tuple

2. **Single Mode** (when `idtype` is provided):
   - Loads specified file type
   - Returns: single typed image

# Arguments
- `base_path::String`: Source directory (e.g., "C:/Syncthing/MuHa - Bilder")
- `data_index::Int`: Patient index (1-306)

# Keywords (Pair Mode)
- `input_type::Type`: Input image type (default: from config)
- `output_type::Type`: Output image type (required for pair mode)
- `input_collection::Bool`: Load multiple input files (default: false)
- `output_collection::Bool`: Load multiple output files (default: true)
- `resize_ratio`: Resize ratio (default: 1//4)

# Keywords (Single Mode)
- `idtype::String`: Image type identifier
  - "raw_adj" → Input image
  - "polygon_mask" → Polygon mask
  - "seg_scar", "seg_redness", etc. → Segmentation masks
- `filetype::String`: File extension (default: "png")
- `resize_ratio`: Resize ratio (default: 1//4)
- `image_type::Type`: Output type (default: from config)

# Returns
- **Pair mode**: `Tuple{input_type, output_type}`
- **Single mode**: `image_type`

# Examples

## Pair Mode (Neural Network Training)
```julia
# Load training data
input, output = load_images(
    "C:/Syncthing/MuHa - Bilder", 1;
    input_type = input_type,
    output_type = raw_output_type,
    output_collection = true,
    resize_ratio = 1//4
)
```

## Single Mode (Polygon Masks)
```julia
# Load polygon mask
mask = load_images(
    "C:/Syncthing/MuHa - Bilder", 1;
    idtype = "polygon_mask",
    resize_ratio = 1//4,
    image_type = input_type
)
```
"""
function load_images(
    base_path::String,
    data_index::Int;
    # Pair mode parameters
    input_type::Union{Type, Nothing} = nothing,
    output_type::Union{Type, Nothing} = nothing,
    input_collection::Bool = false,
    output_collection::Bool = true,
    # Single mode parameters
    idtype::Union{String, Nothing} = nothing,
    filetype::String = "png",
    image_type::Union{Type, Nothing} = nothing,
    # Common parameters
    resize_ratio = 1//4
)
    # Determine mode based on parameters
    if !isnothing(output_type)
        # PAIR MODE: Load input + output
        return _load_pair(
            base_path, data_index;
            input_type = input_type,
            output_type = output_type,
            input_collection = input_collection,
            output_collection = output_collection,
            resize_ratio = resize_ratio
        )
    elseif !isnothing(idtype)
        # SINGLE MODE: Load specified file
        return _load_single(
            base_path, data_index;
            idtype = idtype,
            filetype = filetype,
            image_type = image_type,
            resize_ratio = resize_ratio
        )
    else
        error("""
        Invalid parameters for load_images().
        
        For pair mode (input+output), provide:
          - output_type (required)
          - input_type (optional)
          - input_collection, output_collection (optional)
        
        For single mode, provide:
          - idtype (required, e.g., "polygon_mask", "seg_scar")
          - image_type (optional)
        
        Examples:
          # Pair mode
          input, output = load_images(dir, idx; output_type=raw_output_type)
          
          # Single mode
          mask = load_images(dir, idx; idtype="polygon_mask")
        """)
    end
end

# ============================================================================
# Internal: Load Pair (Input + Output)
# ============================================================================

# Internal function to load input+output image pairs.
# Called by load_images() when output_type is provided.
# This is the EXACT implementation from the original load_input_and_output() function.
@__(function _load_pair(
    base_path, data_index;
    input_type,
    output_type,
    input_collection,
    output_collection,
    resize_ratio
)
    # Use default input_type from package config if not provided
    if isnothing(input_type)
        input_type = Bas3ImageSegmentation.input_type
    end
    
    # EXACT COPY of original load_input_and_output implementation (lines 91-144)
    local input_image_size
    local input_images = ()
    local canonicalized_input_shape = ()
    input_shape = shape(input_type)
    
    if input_collection == false
        input_image = img_loader(base_path, data_index; idtype="raw_adj", filetype="png")
        # Apply configurable resize (ratio=1 means no resize)
        if resize_ratio != 1
            input_image = imresize(input_image; ratio=resize_ratio)
        end
        input_image_size = size(input_image)
        for index in 1:length(input_shape)
            input_images = (input_images..., decompose_image_to_values(input_shape[index], input_image))
            canonicalized_input_shape = (canonicalized_input_shape..., input_shape[index])
        end
    else
        throw("TODO")
    end
    
    local output_image_size
    local output_images = ()
    local canonicalized_output_shape = ()
    output_shape = shape(output_type)
    
    if output_collection == false
        throw("TODO")
    else
        for index in 1:length(output_shape)
            output_image = img_loader(base_path, data_index; idtype="seg_$(output_shape[index])", filetype="png")
            # Apply configurable resize (ratio=1 means no resize)
            if resize_ratio != 1
                output_image = imresize(output_image; ratio=resize_ratio)
            end
            output_image_size = size(output_image)
            if output_image_size[1:2] != input_image_size[1:2]
                error("Output image size $(output_image_size) does not match input image size $(input_image_size)")
            end
            output_images = (output_images..., Gray.(output_image))
            canonicalized_output_shape = (canonicalized_output_shape..., output_shape[index])
        end
    end
    
    return input_type(input_images...), output_type(output_images...)
end)

# ============================================================================
# Internal: Load Single File
# ============================================================================

# Internal function to load a single image file.
# Called by load_images() when idtype is provided.
function _load_single(
    base_path, data_index;
    idtype,
    filetype,
    image_type,
    resize_ratio
)
    # Use default input_type from package config if not provided
    if isnothing(image_type)
        image_type = Bas3ImageSegmentation.input_type
    end
    
    # Load PNG
    img = img_loader(base_path, data_index; idtype=idtype, filetype=filetype)
    
    # Resize
    if resize_ratio != 1
        img = imresize(img; ratio=resize_ratio)
    end
    
    # Decompose to channels
    img_shape = shape(image_type)
    channels = ()
    for channel_index in 1:length(img_shape)
        channels = (channels..., decompose_image_to_values(img_shape[channel_index], img))
    end
    
    # Construct typed image
    return image_type(channels...)
end

# ============================================================================
# BACKWARD COMPATIBILITY (DEPRECATED - Will be removed in v3.0.0)
# ============================================================================

# DEPRECATED: Use `load_images()` instead.
# This function is deprecated as of v2.0.0 and will be removed in v3.0.0 (6 months).
# Migration: Simply rename load_input_and_output() to load_images() - API is identical.
@__(function load_input_and_output(base_path, data_index; input_type, input_collection=false, output_type, output_collection=false, resize_ratio=1//4)
    # Deprecation warning (only show once per session)
    @warn """
    load_input_and_output() is DEPRECATED as of v2.0.0
    
    Use load_images() instead (identical API):
      input, output = load_images($(base_path), $(data_index); input_type=..., output_type=...)
    
    This function will be removed in v3.0.0 (July 2026 - 6 months from now).
    
    Simply rename the function - all parameters are the same.
    """ maxlog=1
    
    # Delegate to new unified function
    return load_images(
        base_path, data_index;
        input_type = input_type,
        output_type = output_type,
        input_collection = input_collection,
        output_collection = output_collection,
        resize_ratio = resize_ratio
    )
end)
