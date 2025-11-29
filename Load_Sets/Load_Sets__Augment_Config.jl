# ============================================================================
# Load_Sets__Augment_Config.jl
# ============================================================================
# Configuration and type definitions for the augmentation pipeline.
# 
# Contents:
# - AugmentationMetadata: Struct tracking all parameters for each augmented sample
# - SourceClassInfo: Struct for source image class analysis
# - Default configuration constants
#
# Usage:
#   include("Load_Sets__Augment_Config.jl")
#   # Types and constants are now available
# ============================================================================

using Dates

# ============================================================================
# Type Definitions
# ============================================================================

"""
    AugmentationMetadata

Complete metadata for a single augmented sample, tracking all transformation
parameters for reproducibility and analysis.

# Fields
- `augmented_index::Int` - Index in the augmented dataset
- `source_index::Int` - Index of the source image used
- `timestamp::DateTime` - When the augmentation was performed
- `random_seed::UInt64` - Seed used for reproducible randomness
- `target_class::Symbol` - Target class this sample was generated for

## Smart Crop Parameters (applied first)
- `smart_crop_x_start::Int` - X position of smart crop window
- `smart_crop_y_start::Int` - Y position of smart crop window
- `smart_crop_width::Int` - Width of smart crop window
- `smart_crop_height::Int` - Height of smart crop window

## Geometric Transformation Parameters
- `scale_factor::Float64` - Scale factor (0.9-1.1)
- `shear_x_angle::Float64` - Shear X angle in degrees (-10 to 10)
- `shear_y_angle::Float64` - Shear Y angle in degrees (-10 to 10)
- `rotation_angle::Float64` - Rotation angle in degrees (1-360)
- `flip_type::Symbol` - Flip operation (:flipx, :flipy, or :noop)

## Final Crop Parameters (after geometric transforms)
- `final_crop_y_start::Int` - Y start of final crop
- `final_crop_x_start::Int` - X start of final crop
- `final_crop_height::Int` - Height of final crop (target height)
- `final_crop_width::Int` - Width of final crop (target width)

## Elastic Distortion Parameters
- `elastic_grid_h::Int` - Grid height for elastic distortion
- `elastic_grid_w::Int` - Grid width for elastic distortion
- `elastic_scale::Float64` - Scale of elastic distortion
- `elastic_sigma::Float64` - Sigma for elastic distortion smoothing
- `elastic_iterations::Int` - Number of elastic distortion iterations

## Color/Blur Parameters (applied to input only)
- `brightness_factor::Float64` - Brightness adjustment (0.8-1.2)
- `saturation_offset::Float64` - Saturation adjustment (-0.2 to 0.2)
- `blur_kernel_size::Int` - Gaussian blur kernel size (3, 5, or 7)
- `blur_sigma::Float64` - Gaussian blur sigma (1.0-3.0)

## Quality Metrics (computed after augmentation)
- `scar_percentage::Float64` - Percentage of scar pixels
- `redness_percentage::Float64` - Percentage of redness pixels
- `hematoma_percentage::Float64` - Percentage of hematoma pixels
- `necrosis_percentage::Float64` - Percentage of necrosis pixels
- `background_percentage::Float64` - Percentage of background pixels
"""
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
    
    # Dynamic sizing fields (added for growth algorithm)
    size_multiplier::Int                   # Final multiplier used (1, 2, 3, or 4)
    patch_height::Int                      # Actual height (= base_height × multiplier)
    patch_width::Int                       # Actual width (= base_width × multiplier)
    fg_threshold_used::Float64             # Threshold for target class
    actual_fg_percentage::Float64          # Actual FG% in final patch
    growth_iterations::Int                 # How many crops tried (1 = no growth)
    max_size_reached::Bool                 # Hit max_multiplier limit?
    intermediate_height::Int               # Height of intermediate image
    intermediate_width::Int                # Width of intermediate image
end

"""
    SourceClassInfo

Analysis of class distribution for a single source image.
Used for weighted source selection during augmentation.

# Fields
- `source_index::Int` - Index of the source image
- `scar_percentage::Float64` - Percentage of scar pixels
- `redness_percentage::Float64` - Percentage of redness pixels
- `hematoma_percentage::Float64` - Percentage of hematoma pixels
- `necrosis_percentage::Float64` - Percentage of necrosis pixels
- `background_percentage::Float64` - Percentage of background pixels
- `total_pixels::Int` - Total number of pixels in the image
"""
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
# Default Configuration
# ============================================================================

"""
Default target class distribution for balanced augmentation.
Values are percentages that should sum to 100.
"""
const DEFAULT_TARGET_DISTRIBUTION = Dict{Symbol, Float64}(
    :scar => 15.0,
    :redness => 15.0,
    :hematoma => 30.0,
    :necrosis => 5.0,
    :background => 35.0
)

"""
Default output size for augmented images (height, width).
"""
const DEFAULT_AUGMENTED_SIZE = (100, 50)

"""
Default intermediate size for smart cropping.
Should be larger than final size to allow for geometric transforms.
"""
const DEFAULT_INTERMEDIATE_SIZE = (150, 150)

"""
Default number of augmented samples to generate.
"""
const DEFAULT_AUGMENTED_LENGTH = 1000

"""
Per-class foreground thresholds.
Each class can have different tolerance for foreground content.
If FG% exceeds threshold, patch grows until threshold met.
"""
const FG_THRESHOLDS = Dict{Symbol, Float64}(
    :scar       => 50.0,    # 50% maximum foreground
    :redness    => 50.0,    # 50% maximum foreground
    :hematoma   => 50.0,    # 50% maximum foreground
    :necrosis   => 50.0,    # 50% maximum foreground
    :background => 100.0    # No limit (background samples don't grow)
)

"""
Maximum size multiplier for dynamic growth.
Limits growth to prevent extremely large patches.
"""
const MAX_MULTIPLIER = 4  # Max size = 200×400 (for base 50×100)

"""
Class order for consistent iteration.
"""
const AUGMENT_CLASS_ORDER = [:scar, :redness, :hematoma, :necrosis, :background]

"""
Class index mapping for output channels.
"""
const CLASS_INDEX_MAP = Dict{Symbol, Int}(
    :scar => 1,
    :redness => 2,
    :hematoma => 3,
    :necrosis => 4,
    :background => 5
)

"""
Colors for visualization of each class.
"""
const AUGMENT_CLASS_COLORS = [
    :indianred,      # scar
    :mediumseagreen, # redness
    :cornflowerblue, # hematoma
    :gold,           # necrosis
    :slategray       # background
]

# ============================================================================
# Utility Functions
# ============================================================================

"""
    get_class_index(class::Symbol) -> Int

Get the channel index for a class symbol.
"""
function get_class_index(class::Symbol)
    return CLASS_INDEX_MAP[class]
end

"""
    get_class_color(class::Symbol)

Get the visualization color for a class.
"""
function get_class_color(class::Symbol)
    idx = findfirst(==(class), AUGMENT_CLASS_ORDER)
    return isnothing(idx) ? :gray : AUGMENT_CLASS_COLORS[idx]
end

"""
    validate_target_distribution(dist::Dict{Symbol, Float64}) -> Bool

Validate that target distribution sums to approximately 100%.
"""
function validate_target_distribution(dist::Dict{Symbol, Float64})
    total = sum(values(dist))
    return abs(total - 100.0) < 0.01
end

"""
    get_fg_threshold(target_class::Symbol) -> Float64

Get the foreground threshold for a specific target class.
"""
function get_fg_threshold(target_class::Symbol)
    return get(FG_THRESHOLDS, target_class, 50.0)
end

println("  Load_Sets__Augment_Config loaded")
