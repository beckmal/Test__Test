# Load_Sets__WhiteBalance.jl
# White balance using Bradford chromatic adaptation

"""
    Load_Sets__WhiteBalance

Module for white balancing images using the Bradford chromatic adaptation method.
The Bradford method is the industry standard for chromatic adaptation in color management systems.

# Key Functions
- `whitebalance_bradford(color, src_white, ref_white)` - Apply Bradford adaptation to a single color
- `apply_whitebalance_to_image(img, src_white, ref_white)` - Apply to entire image

# Example
```julia
using Colors

# Correct warm indoor lighting to standard daylight
warm_image = load("indoor_photo.jpg")
corrected = apply_whitebalance_to_image(warm_image, Colors.WP_A, Colors.WP_D65)
```

# References
- WHITEBALANCE_BRADFORD.md - Detailed documentation
- http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
"""

using LinearAlgebra
using Colors
using Statistics  # For median function

# Bradford chromatic adaptation matrix
# Transforms XYZ tristimulus values to cone response domain
const BRADFORD = [0.8951  0.2664 -0.1614;
                 -0.7502  1.7135  0.0367;
                  0.0389 -0.0685  1.0296]

# Precompute inverse for efficiency
const BRADFORD_INV = inv(BRADFORD)

"""
    whitebalance_bradford(c::T, src_white::Color, ref_white::Color) where T <: Color

Apply Bradford chromatic adaptation to white balance a color.

# Arguments
- `c`: Input color to be adapted
- `src_white`: Source white point (illuminant under which color was observed)
- `ref_white`: Reference white point (target illuminant, typically WP_D65)

# Returns
Color adapted to the reference white point, in the same color type as input

# Example
```julia
# Adapt a warm skin tone from indoor lighting (A) to daylight (D65)
color = RGB(0.8, 0.6, 0.4)
result = whitebalance_bradford(color, Colors.WP_A, Colors.WP_D65)
```

# Algorithm
1. Convert input color and white points to XYZ color space
2. Transform XYZ to Bradford cone response domain
3. Apply von Kries diagonal scaling (element-wise ratio of ref/src)
4. Transform back to XYZ using inverse Bradford matrix
5. Convert to original color type

# Notes
- Bradford is considered industry standard for chromatic adaptation
- Small differences from CAT02 method (Colors.jl default)
- Largest differences occur in blue channel and warm→cool transitions
"""
function whitebalance_bradford(c::T, src_white, ref_white) where T
    # Convert all colors to XYZ color space
    local c_xyz = convert(Colors.XYZ, c)
    local src_xyz = convert(Colors.XYZ, src_white)
    local ref_xyz = convert(Colors.XYZ, ref_white)
    
    # Transform XYZ to cone response domain using Bradford matrix
    local c_bradford = BRADFORD * [c_xyz.x, c_xyz.y, c_xyz.z]
    local src_bradford = BRADFORD * [src_xyz.x, src_xyz.y, src_xyz.z]
    local ref_bradford = BRADFORD * [ref_xyz.x, ref_xyz.y, ref_xyz.z]
    
    # Apply von Kries diagonal transform (element-wise scaling)
    # This scales each cone response by the ratio of reference to source
    # Handle division by zero by checking for near-zero values
    local adapted = similar(c_bradford)
    for i in 1:3
        if abs(src_bradford[i]) < 1e-10
            adapted[i] = c_bradford[i]  # Preserve original if source is near zero
        else
            adapted[i] = c_bradford[i] * ref_bradford[i] / src_bradford[i]
        end
    end
    
    # Transform back to XYZ using inverse Bradford matrix
    local xyz_adapted = BRADFORD_INV * adapted
    local result_xyz = Colors.XYZ(xyz_adapted[1], xyz_adapted[2], xyz_adapted[3])
    
    # Convert back to original color type
    convert(T, result_xyz)
end

# sRGB to XYZ conversion matrix (D65 reference white)
const SRGB_TO_XYZ = [0.4124564  0.3575761  0.1804375;
                    0.2126729  0.7151522  0.0721750;
                    0.0193339  0.1191920  0.9503041]

# XYZ to sRGB conversion matrix (D65 reference white)  
const XYZ_TO_SRGB = [3.2404542 -1.5371385 -0.4985314;
                   -0.9692660  1.8760108  0.0415560;
                    0.0556434 -0.2040259  1.0572252]

"""
    compute_bradford_matrix(src_white, ref_white)

Pre-compute the complete Bradford chromatic adaptation matrix.
This combines: XYZ→Bradford→Scale→Bradford⁻¹→XYZ into a single 3×3 matrix.

# Returns
3×3 Float64 matrix that transforms source XYZ to adapted XYZ
"""
function compute_bradford_matrix(src_white, ref_white)
    local src_xyz = convert(Colors.XYZ, src_white)
    local ref_xyz = convert(Colors.XYZ, ref_white)
    
    # Transform white points to Bradford cone space
    local src_bradford = BRADFORD * [src_xyz.x, src_xyz.y, src_xyz.z]
    local ref_bradford = BRADFORD * [ref_xyz.x, ref_xyz.y, ref_xyz.z]
    
    # Compute diagonal scaling matrix
    local scale = zeros(3, 3)
    for i in 1:3
        if abs(src_bradford[i]) > 1e-10
            scale[i, i] = ref_bradford[i] / src_bradford[i]
        else
            scale[i, i] = 1.0
        end
    end
    
    # Combined matrix: Bradford⁻¹ × Scale × Bradford
    return BRADFORD_INV * scale * BRADFORD
end

"""
    srgb_gamma_expand(v::Float64) -> Float64

Remove sRGB gamma encoding (expand to linear).
"""
@inline function srgb_gamma_expand(v::Float64)
    v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4
end

"""
    srgb_gamma_compress(v::Float64) -> Float64

Apply sRGB gamma encoding (compress from linear).
"""
@inline function srgb_gamma_compress(v::Float64)
    v <= 0.0031308 ? 12.92 * v : 1.055 * v^(1.0/2.4) - 0.055
end

"""
    apply_whitebalance_to_image(img::Matrix, src_white, ref_white)

Apply Bradford white balance to an entire image.

# Arguments
- `img`: Image matrix (any color type supported by Colors.jl)
- `src_white`: Source white point (original lighting)
- `ref_white`: Reference white point (target lighting)

# Returns
New image matrix with white balance applied

# Performance (OPTIMIZED)
- Pre-computes Bradford matrix once (not per-pixel)
- Uses direct array operations (avoids Color type allocations)
- ~50ns per pixel → ~0.6s for 3024×4032 image

# Notes
- Creates new image, does not modify input
- All pixels processed independently (parallelizable)
- Preserves image dimensions and structure
"""
function apply_whitebalance_to_image(img::AbstractMatrix, src_white, ref_white)
    println("[WB] Applying white balance to $(size(img)) image")
    println("[WB] Source: $src_white → Reference: $ref_white")
    flush(stdout)
    
    local start_time = time()
    
    # OPTIMIZATION: Pre-compute the complete transformation matrix ONCE
    local M_adapt = compute_bradford_matrix(src_white, ref_white)
    
    # Combined matrix: XYZ_TO_SRGB × M_adapt × SRGB_TO_XYZ
    # This transforms linear RGB directly without intermediate XYZ allocation
    local M_combined = XYZ_TO_SRGB * M_adapt * SRGB_TO_XYZ
    
    # Pre-allocate result array
    local result = similar(img)
    local h, w = size(img)
    
    # Process each pixel with pre-computed matrix
    @inbounds for j in 1:w
        for i in 1:h
            local pixel = img[i, j]
            
            # Skip pure black pixels (optimization for masked regions)
            if pixel.r == 0 && pixel.g == 0 && pixel.b == 0
                result[i, j] = pixel
                continue
            end
            
            # Convert sRGB to linear RGB
            local r_lin = srgb_gamma_expand(Float64(pixel.r))
            local g_lin = srgb_gamma_expand(Float64(pixel.g))
            local b_lin = srgb_gamma_expand(Float64(pixel.b))
            
            # Apply combined transformation (single matrix multiply)
            local r_out = M_combined[1,1] * r_lin + M_combined[1,2] * g_lin + M_combined[1,3] * b_lin
            local g_out = M_combined[2,1] * r_lin + M_combined[2,2] * g_lin + M_combined[2,3] * b_lin
            local b_out = M_combined[3,1] * r_lin + M_combined[3,2] * g_lin + M_combined[3,3] * b_lin
            
            # Convert back to sRGB with gamma and clamp
            local r_final = clamp(srgb_gamma_compress(r_out), 0.0, 1.0)
            local g_final = clamp(srgb_gamma_compress(g_out), 0.0, 1.0)
            local b_final = clamp(srgb_gamma_compress(b_out), 0.0, 1.0)
            
            result[i, j] = typeof(pixel)(r_final, g_final, b_final)
        end
    end
    
    local elapsed = time() - start_time
    println("[WB] ✓ White balance applied in $(round(elapsed, digits=3))s ($(round(h*w/elapsed/1e6, digits=2)) Mpix/s)")
    flush(stdout)
    
    return result
end

"""
    clamp_color(c::RGB)

Clamp RGB color values to valid range [0, 1].

Used after white balance to handle out-of-gamut colors that may result
from chromatic adaptation.

# Example
```julia
color = RGB(1.2, 0.5, -0.1)  # Out of gamut
clamped = clamp_color(color)  # RGB(1.0, 0.5, 0.0)
```
"""
function clamp_color(c::T) where T <: Colors.RGB
    T(
        clamp(c.r, 0.0, 1.0),
        clamp(c.g, 0.0, 1.0),
        clamp(c.b, 0.0, 1.0)
    )
end

"""
    apply_whitebalance_with_clamping(img::Matrix, src_white, ref_white)

Apply white balance with automatic clamping of out-of-gamut colors.

# Arguments
- `img`: Image matrix
- `src_white`: Source white point
- `ref_white`: Reference white point

# Returns
White balanced image with all colors clamped to valid RGB range

# Notes
- The optimized apply_whitebalance_to_image now includes clamping by default
- This function is kept for API compatibility
"""
function apply_whitebalance_with_clamping(img::AbstractMatrix, src_white, ref_white)
    # Optimized version already includes clamping
    return apply_whitebalance_to_image(img, src_white, ref_white)
end

# =============================================================================
# AUTOMATIC WHITE POINT EXTRACTION FROM CALIBRATION TARGET
# =============================================================================

"""
    srgb_to_linear(v::Float64) -> Float64

Remove sRGB gamma encoding to get linear light intensity.

# Formula
- If v ≤ 0.04045: linear = v / 12.92
- If v > 0.04045: linear = ((v + 0.055) / 1.055)^2.4

# Reference
IEC 61966-2-1:1999 (sRGB standard)

# Why This Matters
RGB values in images are gamma-encoded for perceptual uniformity.
But for averaging light intensities (white balance), we MUST work in linear space.

# Example
```julia
srgb_to_linear(0.5)  # => 0.2140  (not 0.5!)
srgb_to_linear(1.0)  # => 1.0
```
"""
function srgb_to_linear(v::Float64)
    if v <= 0.04045
        return v / 12.92
    else
        return ((v + 0.055) / 1.055) ^ 2.4
    end
end

"""
    extract_white_point_from_masked_region(masked_region::AbstractMatrix{<:RGB}) -> Colors.XYZ

Extract white point from ruler's white patch using MEDIAN (robust to outliers).

# Arguments
- `masked_region`: Masked image where non-black pixels represent the ruler's white patch

# Returns
XYZ color representing the measured white point under scene illumination

# Algorithm Steps (Following Bradford White Balance Theory)
1. Extract non-black pixels from masked region (ruler's white patch)
2. Linearize RGB values (remove sRGB gamma encoding) - CRITICAL!
3. Compute MEDIAN for each channel (R, G, B) - robust to outliers
4. Convert linearized median RGB to XYZ using sRGB→XYZ matrix
5. Return XYZ white point for Bradford chromatic adaptation

# Why MEDIAN?
Medical images may have imperfections on the ruler:
- ✅ Robust to dirt/dust (dark outliers)
- ✅ Robust to specular reflections/glare (bright outliers)
- ✅ Robust to shadows from uneven contact
- ✅ Robust to JPEG compression artifacts
- ✅ More stable across different captures

# Example
```julia
# Extract white point from ruler in medical image
ruler_region = load("MuHa_001_ruler_mask_applied.png")
measured_white = extract_white_point_from_masked_region(ruler_region)
# => Colors.XYZ(0.88, 0.92, 0.75)  # Warm tungsten lighting detected

# Use for automatic white balance
corrected = apply_whitebalance_to_image(image, measured_white, Colors.WP_D65)
```

# Notes
- **Linearization is CRITICAL** - RGB values are gamma-encoded, must average in linear space
- **MEDIAN is robust** - ignores outliers from dirt, glare, shadows, artifacts
- Works with any calibration target that has a known white patch
- Returns D65 fallback if no white pixels found
"""
function extract_white_point_from_masked_region(masked_region::AbstractMatrix{<:Colors.RGB})
    local start_time = time()
    
    # OPTIMIZATION: Count non-black pixels first for pre-allocation
    local pixel_count = 0
    @inbounds for pixel in masked_region
        if pixel.r > 0.01f0 || pixel.g > 0.01f0 || pixel.b > 0.01f0
            pixel_count += 1
        end
    end
    
    if pixel_count == 0
        println("[WB_EXTRACT] ⚠️  No white pixels found! Using D65 fallback")
        return Colors.WP_D65
    end
    
    # OPTIMIZATION: Pre-allocate arrays with exact size
    local r_values = Vector{Float64}(undef, pixel_count)
    local g_values = Vector{Float64}(undef, pixel_count)
    local b_values = Vector{Float64}(undef, pixel_count)
    
    # Step 1 & 2: Extract and linearize non-black pixels
    local idx = 1
    @inbounds for pixel in masked_region
        local r = Float64(pixel.r)
        local g = Float64(pixel.g)
        local b = Float64(pixel.b)
        
        if r > 0.01 || g > 0.01 || b > 0.01
            # Linearize RGB values (remove sRGB gamma encoding)
            r_values[idx] = srgb_to_linear(r)
            g_values[idx] = srgb_to_linear(g)
            b_values[idx] = srgb_to_linear(b)
            idx += 1
        end
    end
    
    # Step 3: Compute MEDIAN for each channel (robust to outliers)
    local Rw_linear = median(r_values)
    local Gw_linear = median(g_values)
    local Bw_linear = median(b_values)
    
    # Step 4: Convert linearized RGB to XYZ using sRGB→XYZ matrix
    # Use the pre-defined SRGB_TO_XYZ constant matrix
    local XYZ_vec = SRGB_TO_XYZ * [Rw_linear, Gw_linear, Bw_linear]
    
    # Step 5: Return XYZ white point
    local white_xyz = Colors.XYZ(XYZ_vec[1], XYZ_vec[2], XYZ_vec[3])
    
    # Diagnostic: Compare to standard illuminants
    local d65_dist = sqrt((white_xyz.x - Colors.WP_D65.x)^2 + (white_xyz.y - Colors.WP_D65.y)^2 + (white_xyz.z - Colors.WP_D65.z)^2)
    local a_dist = sqrt((white_xyz.x - Colors.WP_A.x)^2 + (white_xyz.y - Colors.WP_A.y)^2 + (white_xyz.z - Colors.WP_A.z)^2)
    
    local elapsed = time() - start_time
    local lighting_type = d65_dist < 0.1 ? "well-balanced (D65)" : (a_dist < d65_dist ? "warm/tungsten" : "non-standard")
    println("[WB_EXTRACT] ✓ Extracted XYZ($(round(white_xyz.x, digits=3)), $(round(white_xyz.y, digits=3)), $(round(white_xyz.z, digits=3))) from $pixel_count pixels in $(round(elapsed*1000, digits=1))ms ($lighting_type)")
    flush(stdout)
    
    return white_xyz
end

"""
    normalize_white_point_luminance(white_xyz::Colors.XYZ) -> Colors.XYZ

Normalize a white point to Y=1.0, preserving chromaticity (x, y coordinates).

This enables **chromaticity-only** white balance correction, where color temperature
is corrected but overall image brightness is preserved.

# Why This Matters
Standard illuminant white points (D50, D65, A, etc.) are luminance-normalized (Y=1.0).
But extracted white points from images often have Y≠1.0 due to:
- Ruler in shadow (Y < 1.0) → Full Bradford would brighten image
- Specular reflection on ruler (Y > 1.0) → Full Bradford would darken image
- Varying exposure across dataset

# Algorithm
Scales XYZ uniformly so Y becomes 1.0:
    scale = 1.0 / Y
    XYZ_normalized = (X * scale, 1.0, Z * scale)

This preserves the chromaticity coordinates:
    x = X / (X + Y + Z)  → unchanged
    y = Y / (X + Y + Z)  → unchanged

# Example
```julia
# Dim warm white extracted from shadowed ruler
extracted = Colors.XYZ(0.70, 0.75, 0.50)

# Normalize to Y=1.0 for chromaticity-only correction
normalized = normalize_white_point_luminance(extracted)
# => Colors.XYZ(0.933, 1.0, 0.667)

# Now Bradford adaptation only corrects color, not brightness
corrected = apply_whitebalance_to_image(img, normalized, Colors.WP_D50)
```

# See Also
- `extract_white_point_from_masked_region`: Extracts raw white point (may have Y≠1.0)
- `whitebalance_bradford`: Applies chromatic adaptation
"""
function normalize_white_point_luminance(white_xyz::Colors.XYZ)
    if white_xyz.y <= 0
        println("[WB_NORMALIZE] ⚠ Y≤0, returning unchanged")
        return white_xyz
    end
    
    local scale = 1.0 / white_xyz.y
    local normalized = Colors.XYZ(white_xyz.x * scale, 1.0, white_xyz.z * scale)
    
    println("[WB_NORMALIZE] Normalized Y: $(round(white_xyz.y, digits=3)) → 1.0 (scale=$(round(scale, digits=3)))")
    println("[WB_NORMALIZE] XYZ: ($(round(white_xyz.x, digits=3)), $(round(white_xyz.y, digits=3)), $(round(white_xyz.z, digits=3))) → ($(round(normalized.x, digits=3)), 1.0, $(round(normalized.z, digits=3)))")
    
    return normalized
end

# Export public functions
export whitebalance_bradford, apply_whitebalance_to_image, apply_whitebalance_with_clamping, clamp_color
export extract_white_point_from_masked_region, srgb_to_linear, normalize_white_point_luminance

println("✓ Load_Sets__WhiteBalance loaded (with automatic white extraction)")
