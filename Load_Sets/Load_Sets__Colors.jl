# Load_Sets__Colors.jl
# Color definitions and German translations for wound classification

"""
    Load_Sets__Colors

Color definitions module for wound classification visualization.
Provides German translations and RGB color mappings for classes and channels.
"""

# ============================================================================
# German Class Name Translations
# ============================================================================

const CLASS_NAMES_DE = Dict(
    :scar => "In_Narbe",
    :redness => "Bei_Narbe",
    :hematoma => "Umgebung",
    :necrosis => "Entfernt",
    :background => "Hintergrund"
)

"""
    get_german_class_names(classes::Vector{Symbol}) -> Vector{String}

Convert class symbols to German names.

# Example
```julia
classes = [:scar, :redness, :hematoma]
get_german_class_names(classes)  # ["In_Narbe", "Bei_Narbe", "Umgebung"]
```
"""
function get_german_class_names(classes)
    return [CLASS_NAMES_DE[c] for c in classes]
end

# ============================================================================
# Class Colors (for wound segmentation visualization)
# ============================================================================

const CLASS_COLORS_RGB = [
    Bas3GLMakie.GLMakie.RGBf(0, 1, 0),      # In_Narbe - Green
    Bas3GLMakie.GLMakie.RGBf(1, 0, 0),      # Bei_Narbe - Red
    :goldenrod,                             # Umgebung - Goldenrod/Yellow
    Bas3GLMakie.GLMakie.RGBf(0, 0, 1),      # Entfernt - Blue
    :black                                  # Background (Hintergrund) - Black
]

# ============================================================================
# German Channel Name Translations
# ============================================================================

const CHANNEL_NAMES_DE = Dict(
    :red => "Rot",
    :green => "Grün",
    :blue => "Blau"
)

"""
    get_german_channel_names(channels::Vector{Symbol}) -> Vector{String}

Convert channel symbols to German names.

# Example
```julia
channels = [:red, :green, :blue]
get_german_channel_names(channels)  # ["Rot", "Grün", "Blau"]
```
"""
function get_german_channel_names(channels)
    return [CHANNEL_NAMES_DE[c] for c in channels]
end

# ============================================================================
# Channel Colors (for RGB visualization)
# ============================================================================

const CHANNEL_COLORS_RGB = Dict(
    :red => :red,
    :green => :green,
    :blue => :blue
)

# ============================================================================
# Overlay Creation Utilities
# ============================================================================

"""
    create_rgba_overlay(mask::BitMatrix, color::RGBf, alpha::Float32) -> Matrix{RGBA}

Create RGBA overlay from boolean mask with specified color and transparency.

# Arguments
- `mask::BitMatrix`: Boolean mask (true = colored, false = transparent)
- `color::RGBf`: RGB color for true pixels
- `alpha::Float32`: Transparency level (0.0 = transparent, 1.0 = opaque)

# Returns
- `Matrix{RGBA}`: RGBA image suitable for overlay visualization
"""
function create_rgba_overlay(mask::BitMatrix, color, alpha::Float32)
    return map(mask) do is_active
        if is_active
            Bas3ImageSegmentation.RGBA{Float32}(color.r, color.g, color.b, alpha)
        else
            Bas3ImageSegmentation.RGBA{Float32}(0.0f0, 0.0f0, 0.0f0, 0.0f0)  # Transparent
        end
    end
end
