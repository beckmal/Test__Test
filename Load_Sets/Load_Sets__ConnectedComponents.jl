# Load_Sets__ConnectedComponents.jl
# Connected component analysis with PCA-based oriented bounding boxes

"""
    Load_Sets__ConnectedComponents

Connected component analysis module for white region detection and analysis.
Uses PCA for oriented bounding boxes and smart component selection.
"""

using Statistics
using LinearAlgebra

# Note: Requires Load_Sets__Morphology.jl to be loaded for morphological operations

# ============================================================================
# Adaptive Thresholding Utilities
# ============================================================================

"""
    box_filter(data, window_size)

Compute local mean using a box filter (uniform averaging).
Uses integral image for O(1) per-pixel computation.

# Arguments
- `data::Matrix{Float64}`: Input 2D array
- `window_size::Int`: Size of square window (must be odd)

# Returns
- `Matrix{Float64}`: Local mean at each pixel
"""
function box_filter(data::Matrix{<:Real}, window_size::Int)
    h, w = size(data)
    half_win = window_size ÷ 2
    
    # Compute integral image (cumulative sum)
    # integral[i,j] = sum of all pixels from (1,1) to (i,j)
    integral = zeros(Float64, h + 1, w + 1)
    for i in 1:h
        for j in 1:w
            integral[i+1, j+1] = Float64(data[i, j]) + integral[i, j+1] + integral[i+1, j] - integral[i, j]
        end
    end
    
    # Compute local mean using integral image
    result = zeros(Float64, h, w)
    for i in 1:h
        for j in 1:w
            # Window bounds (clamped to image boundaries)
            r1 = max(1, i - half_win)
            r2 = min(h, i + half_win)
            c1 = max(1, j - half_win)
            c2 = min(w, j + half_win)
            
            # Sum in window using integral image
            window_sum = integral[r2+1, c2+1] - integral[r1, c2+1] - integral[r2+1, c1] + integral[r1, c1]
            window_area = (r2 - r1 + 1) * (c2 - c1 + 1)
            
            result[i, j] = window_sum / window_area
        end
    end
    
    return result
end

"""
    adaptive_threshold(data, window_size, offset; min_threshold=0.0)

Apply adaptive thresholding using local mean.

A pixel is considered "on" if:
    data[i,j] > local_mean[i,j] + offset AND data[i,j] > min_threshold

# Arguments
- `data::Matrix{Float64}`: Input 2D array (e.g., brightness values 0-1)
- `window_size::Int`: Size of local neighborhood for mean computation
- `offset::Float64`: Offset added to local mean (positive = more selective)
- `min_threshold::Float64`: Global minimum threshold (default 0.0)

# Returns
- `BitMatrix`: Binary mask where pixels exceed adaptive threshold
"""
function adaptive_threshold(data::Matrix{<:Real}, window_size::Int, offset::Float64; min_threshold::Float64=0.0)
    local_mean = box_filter(data, window_size)
    
    # Pixel is "on" if above local mean + offset AND above global minimum
    return (data .> (local_mean .+ offset)) .& (data .> min_threshold)
end

"""
    compute_brightness(rgb_data)

Convert RGB image data to grayscale brightness.
Uses standard luminance formula: 0.299*R + 0.587*G + 0.114*B

# Arguments
- `rgb_data`: 3D array (H x W x 3) with RGB channels

# Returns
- `Matrix{Float64}`: 2D brightness array
"""
function compute_brightness(rgb_data)
    return 0.299 .* Float64.(rgb_data[:,:,1]) .+ 
           0.587 .* Float64.(rgb_data[:,:,2]) .+ 
           0.114 .* Float64.(rgb_data[:,:,3])
end

# ============================================================================
# White Region Extraction with PCA-Based Bounding Box
# ============================================================================

"""
    extract_white_mask(img; threshold=0.7, threshold_upper=1.0, min_component_area=100, 
                       preferred_aspect_ratio=5.0, aspect_ratio_weight=0.5, 
                       kernel_size=3, region=nothing, adaptive=false,
                       adaptive_window=25, adaptive_offset=0.1)
    -> (mask, size, percentage, num_components, density, corners, angle, aspect_ratio)

Find best white region using PCA-based oriented bounding box analysis.

# Algorithm
1. Threshold image to create initial white mask:
   - Global mode: threshold <= RGB channels <= threshold_upper (band-pass filter)
   - Adaptive mode: brightness > local_mean + offset (handles uneven lighting)
2. Apply morphological closing and opening to improve connectivity
3. Label connected components
4. For each component:
   - Compute PCA to find principal axes
   - Calculate oriented bounding box (minimum area rectangle)
   - Compute density and aspect ratio
   - Score based on weighted combination of density and aspect ratio match
5. Select component with highest combined score

# Parameters
- `threshold::Float64`: Lower RGB threshold for white detection (0.0-1.0, default: 0.7)
  - In adaptive mode, serves as minimum global threshold
- `threshold_upper::Float64`: Upper RGB threshold (0.0-1.0, default: 1.0)
  - Pixels brighter than this are excluded (useful for filtering out specular highlights)
  - Set to 1.0 to disable upper threshold
- `min_component_area::Int`: Minimum pixels to consider (default: 100)
- `preferred_aspect_ratio::Float64`: Target aspect ratio (longer/shorter, default: 5.0)
- `aspect_ratio_weight::Float64`: Weight for aspect ratio vs density (0.0-1.0, default: 0.5)
  - 0.0 = purely density-based selection
  - 0.5 = balanced
  - 1.0 = purely aspect ratio-based
- `kernel_size::Int`: Morphological operation kernel size (default: 3)
  - 0 = no morphological operations
  - 3 = recommended (moderate gap filling)
  - 5+ = aggressive (may merge separate objects)
- `region::Union{Nothing, Tuple}`: Optional (r_min, r_max, c_min, c_max) to restrict search
- `adaptive::Bool`: Enable adaptive thresholding (default: false)
- `adaptive_window::Int`: Window size for local mean computation (default: 25)
- `adaptive_offset::Float64`: Offset added to local mean (default: 0.1)
  - Higher = more selective (only much brighter than surroundings)
  - Lower = more inclusive

# Returns
Tuple of:
- `mask::BitMatrix`: Binary mask of best component
- `size::Int`: Number of pixels in best component
- `percentage::Float64`: Percentage of image area
- `num_components::Int`: Total number of components found
- `density::Float64`: Pixel density in oriented bounding box
- `corners::Vector{Float64}`: Flattened corner coordinates [r1,c1,r2,c2,r3,c3,r4,c4]
- `angle::Float64`: Rotation angle (radians)
- `aspect_ratio::Float64`: Aspect ratio (≥ 1.0)

# Example
```julia
# Global threshold mode with band-pass (exclude very bright pixels)
mask, size, pct, n_comp, density, corners, angle, aspect = 
    extract_white_mask(image; 
        threshold=0.7,
        threshold_upper=0.95,  # exclude specular highlights
        min_component_area=8000,
        preferred_aspect_ratio=5.0,
        aspect_ratio_weight=0.6,
        kernel_size=3)

# Adaptive threshold mode (better for uneven lighting)
mask, size, pct, n_comp, density, corners, angle, aspect = 
    extract_white_mask(image; 
        adaptive=true,
        adaptive_window=25,
        adaptive_offset=0.05,
        threshold=0.5,  # minimum threshold
        min_component_area=8000)
```
"""
function extract_white_mask(img; threshold=0.7, threshold_upper=1.0, min_component_area=100, 
                            preferred_aspect_ratio=5.0, aspect_ratio_weight=0.5, 
                            kernel_size=3, region=nothing, region_mask=nothing,
                            adaptive=false, adaptive_window=25, adaptive_offset=0.1)
    rgb_data = Bas3ImageSegmentation.data(img)
    
    # Apply region mask if specified
    if !isnothing(region_mask)
        # Use pre-computed region mask (e.g., rotated rectangle)
        # Already a BitMatrix of correct size
    elseif !isnothing(region)
        r_min, r_max, c_min, c_max = region
        # Clamp to valid bounds
        r_min = max(1, min(r_min, Base.size(rgb_data, 1)))
        r_max = max(1, min(r_max, Base.size(rgb_data, 1)))
        c_min = max(1, min(c_min, Base.size(rgb_data, 2)))
        c_max = max(1, min(c_max, Base.size(rgb_data, 2)))
        # Create mask for region
        region_mask = falses(Base.size(rgb_data, 1), Base.size(rgb_data, 2))
        region_mask[r_min:r_max, c_min:c_max] .= true
    else
        region_mask = trues(Base.size(rgb_data, 1), Base.size(rgb_data, 2))
    end
    
    # Initial white mask - threshold within region
    local region_mask_count = sum(region_mask)
    println("[EXTRACT-WHITE-MASK] Region mask has $(region_mask_count) pixels (size: $(Base.size(region_mask)))")
    
    if adaptive
        # Adaptive thresholding: compare to local neighborhood mean
        # Better for handling uneven lighting, shadows, and highlights
        brightness = compute_brightness(rgb_data)
        
        # Apply adaptive threshold with global minimum and upper bound
        adaptive_mask = adaptive_threshold(brightness, adaptive_window, adaptive_offset; 
                                           min_threshold=Float64(threshold))
        # Apply upper threshold if specified (filter out very bright pixels)
        if threshold_upper < 1.0
            upper_mask = brightness .<= threshold_upper
            white_mask_all = adaptive_mask .& upper_mask .& region_mask
        else
            white_mask_all = adaptive_mask .& region_mask
        end
        
        println("[EXTRACT-WHITE-MASK] Adaptive mode: window=$adaptive_window, offset=$adaptive_offset, min_threshold=$threshold, upper=$threshold_upper")
    else
        # Global thresholding: all RGB channels must be within threshold range (band-pass)
        # Lower threshold: pixels must be >= threshold
        # Upper threshold: pixels must be <= threshold_upper (filters specular highlights)
        lower_mask = (rgb_data[:,:,1] .>= threshold) .& 
                     (rgb_data[:,:,2] .>= threshold) .& 
                     (rgb_data[:,:,3] .>= threshold)
        
        if threshold_upper < 1.0
            upper_mask = (rgb_data[:,:,1] .<= threshold_upper) .& 
                         (rgb_data[:,:,2] .<= threshold_upper) .& 
                         (rgb_data[:,:,3] .<= threshold_upper)
            white_mask_all = lower_mask .& upper_mask .& region_mask
        else
            white_mask_all = lower_mask .& region_mask
        end
        
        println("[EXTRACT-WHITE-MASK] Global mode: threshold=$threshold, upper=$threshold_upper")
    end
    
    # Apply morphological operations to improve connectivity
    if kernel_size > 0
        white_mask_all = morphological_close(white_mask_all, kernel_size)
        white_mask_all = morphological_open(white_mask_all, kernel_size)
        # IMPORTANT: Re-apply region_mask after morphological ops to prevent expansion beyond region
        white_mask_all = white_mask_all .& region_mask
    end
    
    # Label all connected components
    labeled = Bas3ImageSegmentation.label_components(white_mask_all)
    num_components = Base.maximum(labeled)
    
    if num_components == 0
        # No white regions found
        return white_mask_all, 0, 0.0, 0, 0.0, Float64[], 0.0, 0.0
    end
    
    # Analyze each connected component
    best_label = 0
    best_score = 0.0  # Combined score (density + aspect ratio match)
    best_density = 0.0
    best_rotated_corners = Float64[]
    best_rotation_angle = 0.0
    best_size = 0
    best_aspect_ratio = 0.0
    
    for label in 1:num_components
        # Get mask for this component - CONSTRAIN TO REGION IMMEDIATELY
        component_mask = (labeled .== label) .& region_mask
        component_size = sum(component_mask)
        
        # Skip if below minimum area or empty after region constraint
        if component_size < min_component_area
            continue
        end
        
        # Get all pixel coordinates for this component
        pixel_coords = findall(component_mask)
        if isempty(pixel_coords)
            continue
        end
        
        # Extract row and column indices
        row_indices = Float64[p[1] for p in pixel_coords]
        col_indices = Float64[p[2] for p in pixel_coords]
        
        # Compute centroid
        centroid_row = sum(row_indices) / length(row_indices)
        centroid_col = sum(col_indices) / length(col_indices)
        
        # Center the coordinates
        centered_rows = row_indices .- centroid_row
        centered_cols = col_indices .- centroid_col
        
        # Compute covariance matrix for PCA
        n = length(centered_rows)
        cov_matrix = [
            sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
            sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
        ]
        
        # Compute eigenvectors (principal directions)
        eigen_result = eigen(cov_matrix)
        principal_axes = eigen_result.vectors
        
        # Project points onto principal axes
        proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
        proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
        
        # Find min/max along each principal axis
        min_proj1, max_proj1 = extrema(proj_axis1)
        min_proj2, max_proj2 = extrema(proj_axis2)
        
        # Calculate oriented bounding box area
        rotated_width = max_proj1 - min_proj1
        rotated_height = max_proj2 - min_proj2
        rotated_bbox_area = rotated_width * rotated_height
        
        # Compute density with rotated bounding box
        rotated_density = component_size / rotated_bbox_area
        
        # Calculate rotation angle
        rotation_angle = atan(principal_axes[1, 2], principal_axes[2, 2])
        
        # Compute corners of rotated rectangle in original coordinates
        corners_proj = [
            (min_proj1, min_proj2),
            (max_proj1, min_proj2),
            (max_proj1, max_proj2),
            (min_proj1, max_proj2)
        ]
        
        corners_original = map(corners_proj) do (p1, p2)
            row = centroid_row + p1 * principal_axes[1, 2] + p2 * principal_axes[1, 1]
            col = centroid_col + p1 * principal_axes[2, 2] + p2 * principal_axes[2, 1]
            (row, col)
        end
        
        # Calculate aspect ratio (always >= 1, using longer/shorter dimension)
        aspect_ratio = max(rotated_width, rotated_height) / min(rotated_width, rotated_height)
        
        # Compute aspect ratio score (0 to 1, higher is better match)
        # Uses exponential decay from the preferred aspect ratio
        aspect_ratio_score = exp(-abs(aspect_ratio - preferred_aspect_ratio) / preferred_aspect_ratio)
        
        # Normalize density to 0-1 range (assuming density typically < 1.0)
        normalized_density = min(rotated_density, 1.0)
        
        # Calculate brightness score: mean brightness of component pixels
        brightness_sum = 0.0
        for coord in pixel_coords
            # Get RGB values at this pixel
            r = rgb_data[coord[1], coord[2], 1]
            g = rgb_data[coord[1], coord[2], 2]
            b = rgb_data[coord[1], coord[2], 3]
            # Mean RGB as brightness
            brightness_sum += (r + g + b) / 3.0
        end
        brightness_score = brightness_sum / length(pixel_coords)
        
        # Combined score: prioritize brightness for white ruler detection
        # Weights: 50% brightness, 30% density, 20% aspect ratio
        combined_score = 0.5 * brightness_score + 0.3 * normalized_density + 0.2 * aspect_ratio_score
        
        # Select component with highest combined score
        if combined_score > best_score
            best_score = combined_score
            best_density = rotated_density
            best_label = label
            best_rotated_corners = vcat([[c[1], c[2]] for c in corners_original]...)
            best_rotation_angle = rotation_angle
            best_size = component_size
            best_aspect_ratio = aspect_ratio
            println("[COMPONENT-ANALYSIS] Label $label: size=$component_size, brightness=$(round(brightness_score, digits=3)), density=$(round(rotated_density, digits=3)), aspect=$(round(aspect_ratio, digits=2)), score=$(round(combined_score, digits=3))")
        end
    end
    
    if best_label == 0
        # No components met the minimum area requirement
        return white_mask_all, 0, 0.0, num_components, 0.0, Float64[], 0.0, 0.0
    end
    
    # Create mask with only the densest component
    # IMPORTANT: Re-apply region_mask to ensure morphological operations didn't expand beyond region
    unconstrained_mask = labeled .== best_label
    white_mask = unconstrained_mask .& region_mask
    
    # Debug: Log mask constraint effectiveness
    unconstrained_count = sum(unconstrained_mask)
    constrained_count = sum(white_mask)
    println("[MASK-CONSTRAINT] Unconstrained pixels: $(unconstrained_count), Constrained pixels: $(constrained_count), Reduction: $(unconstrained_count - constrained_count)")
    
    # Recalculate corners from the constrained mask to ensure they match the actual mask boundaries
    constrained_pixel_coords = [(i, j) for i in 1:Base.size(white_mask, 1), j in 1:Base.size(white_mask, 2) if white_mask[i, j]]
    
    if !isempty(constrained_pixel_coords)
        # Recalculate rotated bounding box from constrained mask
        constrained_row_indices = Float64[p[1] for p in constrained_pixel_coords]
        constrained_col_indices = Float64[p[2] for p in constrained_pixel_coords]
        
        constrained_centroid_row = sum(constrained_row_indices) / length(constrained_row_indices)
        constrained_centroid_col = sum(constrained_col_indices) / length(constrained_col_indices)
        
        constrained_centered_rows = constrained_row_indices .- constrained_centroid_row
        constrained_centered_cols = constrained_col_indices .- constrained_centroid_col
        
        n_constrained = length(constrained_centered_rows)
        constrained_cov_matrix = [
            sum(constrained_centered_rows .* constrained_centered_rows) / n_constrained   sum(constrained_centered_rows .* constrained_centered_cols) / n_constrained;
            sum(constrained_centered_rows .* constrained_centered_cols) / n_constrained   sum(constrained_centered_cols .* constrained_centered_cols) / n_constrained
        ]
        
        constrained_eigen_result = eigen(constrained_cov_matrix)
        constrained_principal_axes = constrained_eigen_result.vectors
        
        constrained_proj_axis1 = constrained_centered_rows .* constrained_principal_axes[1, 2] .+ constrained_centered_cols .* constrained_principal_axes[2, 2]
        constrained_proj_axis2 = constrained_centered_rows .* constrained_principal_axes[1, 1] .+ constrained_centered_cols .* constrained_principal_axes[2, 1]
        
        constrained_min_proj1, constrained_max_proj1 = extrema(constrained_proj_axis1)
        constrained_min_proj2, constrained_max_proj2 = extrema(constrained_proj_axis2)
        
        constrained_corners_proj = [
            (constrained_min_proj1, constrained_min_proj2),
            (constrained_max_proj1, constrained_min_proj2),
            (constrained_max_proj1, constrained_max_proj2),
            (constrained_min_proj1, constrained_max_proj2)
        ]
        
        constrained_corners_original = map(constrained_corners_proj) do (p1, p2)
            row = constrained_centroid_row + p1 * constrained_principal_axes[1, 2] + p2 * constrained_principal_axes[1, 1]
            col = constrained_centroid_col + p1 * constrained_principal_axes[2, 2] + p2 * constrained_principal_axes[2, 1]
            (row, col)
        end
        
        # Clip corners to stay within region_mask bounds
        # Find the actual bounding box of the region_mask
        region_rows = findall(any(region_mask, dims=2))
        region_cols = findall(any(region_mask, dims=1))
        if !isempty(region_rows) && !isempty(region_cols)
            region_r_min = first(region_rows)[1]
            region_r_max = last(region_rows)[1]
            region_c_min = first(region_cols)[2]
            region_c_max = last(region_cols)[2]
            
            constrained_corners_original = map(constrained_corners_original) do (r, c)
                clipped_r = clamp(r, Float64(region_r_min), Float64(region_r_max))
                clipped_c = clamp(c, Float64(region_c_min), Float64(region_c_max))
                (clipped_r, clipped_c)
            end
            println("[CORNER-CLIP] Clipped corners to region bounds: rows=$region_r_min:$region_r_max, cols=$region_c_min:$region_c_max")
        end
        
        best_rotated_corners = vcat([[c[1], c[2]] for c in constrained_corners_original]...)
        
        # Recalculate rotation angle from constrained mask
        best_rotation_angle = atan(constrained_principal_axes[1, 2], constrained_principal_axes[2, 2])
        
        # Recalculate aspect ratio from constrained mask
        constrained_rotated_width = constrained_max_proj1 - constrained_min_proj1
        constrained_rotated_height = constrained_max_proj2 - constrained_min_proj2
        best_aspect_ratio = max(constrained_rotated_width, constrained_rotated_height) / min(constrained_rotated_width, constrained_rotated_height)
        
        # Recalculate size and density from constrained mask
        best_size = length(constrained_pixel_coords)
        constrained_rotated_bbox_area = constrained_rotated_width * constrained_rotated_height
        best_density = best_size / constrained_rotated_bbox_area
        
        println("[RECALC-VERIFY] Recalculated from constrained mask: size=$best_size, density=$(round(best_density, digits=3)), aspect=$(round(best_aspect_ratio, digits=2))")
    end
    
    total_pixels = Base.size(rgb_data, 1) * Base.size(rgb_data, 2)
    white_percentage = (best_size / total_pixels) * 100
    
    return white_mask, best_size, white_percentage, num_components, best_density, best_rotated_corners, best_rotation_angle, best_aspect_ratio
end

# ============================================================================
# White Region Channel Statistics
# ============================================================================

"""
    compute_white_region_channel_stats(image, white_mask) -> (stats, pixel_count)

Compute RGB channel statistics for pixels within white mask.

# Arguments
- `image`: Input RGB image
- `white_mask::BitMatrix`: Boolean mask of white region

# Returns
- `stats::Dict{Symbol, Dict{Symbol, Float64}}`: Statistics per channel
  - `:red`, `:green`, `:blue` → `:mean`, `:std`, `:skewness`
- `pixel_count::Int`: Number of white pixels

# Example
```julia
stats, count = compute_white_region_channel_stats(image, white_mask)
println("Red channel mean: ", stats[:red][:mean])
println("White pixels: ", count)
```
"""
function compute_white_region_channel_stats(image, white_mask)
    # Extract RGB data - use data() to get raw array, then permute to (channels, height, width)
    raw_data = Bas3ImageSegmentation.data(image)  # Returns (height, width, 3)
    rgb_data = permutedims(raw_data, (3, 1, 2))  # Convert to (3, height, width)
    
    # Initialize result dictionaries
    stats = Dict{Symbol, Dict{Symbol, Float64}}()
    
    # Get channel names
    channel_names = if Base.size(rgb_data, 1) == 3
        [:red, :green, :blue]
    else
        error("Image must have 3 color channels (RGB)")
    end
    
    # Count white pixels
    white_pixel_count = sum(white_mask)
    
    if white_pixel_count == 0
        # No white pixels - return zeros
        for (i, ch) in enumerate(channel_names)
            stats[ch] = Dict(:mean => 0.0, :std => 0.0, :skewness => 0.0)
        end
        return stats, 0
    end
    
    # Extract white pixel values for each channel
    for (i, ch) in enumerate(channel_names)
        channel_data = rgb_data[i, :, :]
        white_values = channel_data[white_mask]
        
        # Compute statistics
        ch_mean = mean(white_values)
        ch_std = std(white_values)
        
        # Compute skewness manually
        n = length(white_values)
        if n > 2 && ch_std > 0
            centered = white_values .- ch_mean
            m3 = sum(centered .^ 3) / n
            ch_skewness = m3 / (ch_std ^ 3)
        else
            ch_skewness = 0.0
        end
        
        stats[ch] = Dict(
            :mean => ch_mean,
            :std => ch_std,
            :skewness => ch_skewness
        )
    end
    
    return stats, white_pixel_count
end

# ============================================================================
# Contour Extraction
# ============================================================================

"""
    extract_contours(mask::BitMatrix) -> Vector{Tuple{Int, Int}}

Extract boundary pixels from binary mask using 4-connectivity.

# Algorithm
A pixel is a boundary pixel if it is true in the mask and has at least one
false neighbor (or is at image edge) in 4-connected neighborhood.

# Arguments
- `mask::BitMatrix`: Binary mask

# Returns
- `Vector{Tuple{Int, Int}}`: List of (row, col) coordinates of boundary pixels

# Example
```julia
contour_points = extract_contours(white_mask)
println("Contour has ", length(contour_points), " pixels")
```
"""
function extract_contours(mask)
    # Find boundary pixels (pixels adjacent to background)
    h, w = Base.size(mask)
    contour_points = Tuple{Int, Int}[]
    
    for i in 1:h
        for j in 1:w
            if mask[i, j]
                is_boundary = false
                
                # Check 4-connected neighbors (up, down, left, right)
                for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
                    ni, nj = i + di, j + dj
                    if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                        is_boundary = true
                        break
                    end
                end
                
                if is_boundary
                    push!(contour_points, (i, j))
                end
            end
        end
    end
    
    return contour_points
end

# ============================================================================
# Multi-Marker Detection Support
# ============================================================================

"""
    find_connected_components(image; threshold=0.7, kernel_size=3, 
                               region=nothing, min_area=100)
    -> (labeled_array, num_components, component_info)

Find all connected components in white regions.

This is a lower-level function that returns all components for further analysis.
Used by marker detection functions in Load_Sets__MarkerCorrespondence.jl.

# Arguments
- `image`: Input image
- `threshold::Float64`: RGB threshold for white detection (default: 0.7)
- `kernel_size::Int`: Morphological operation kernel size (default: 3)
- `region::Union{Nothing, Tuple}`: Optional ROI restriction (r_min, r_max, c_min, c_max)
- `min_area::Int`: Minimum component size to include (default: 100)

# Returns
Tuple of:
- `labeled_array::Matrix{Int}`: Labeled components (0 = background)
- `num_components::Int`: Number of components found
- `component_info::Vector{NamedTuple}`: Info for each component
  - :label: Component ID
  - :size: Number of pixels
  - :centroid: (row, col) center position
  - :bbox: Axis-aligned bounding box (r_min, r_max, c_min, c_max)

# Example
```julia
labeled, n_comp, info = find_connected_components(image; 
    threshold=0.7, min_area=8000)

println("Found \$n_comp components")
for comp in info
    println("  Component \$(comp.label): size=\$(comp.size), center=\$(comp.centroid)")
end
```
"""
function find_connected_components(image; threshold=0.7, kernel_size=3, 
                                    region=nothing, min_area=100)
    rgb_data = Bas3ImageSegmentation.data(image)
    
    # Apply region mask if specified
    if !isnothing(region)
        r_min, r_max, c_min, c_max = region
        r_min = max(1, min(r_min, Base.size(rgb_data, 1)))
        r_max = max(1, min(r_max, Base.size(rgb_data, 1)))
        c_min = max(1, min(c_min, Base.size(rgb_data, 2)))
        c_max = max(1, min(c_max, Base.size(rgb_data, 2)))
        region_mask = falses(Base.size(rgb_data, 1), Base.size(rgb_data, 2))
        region_mask[r_min:r_max, c_min:c_max] .= true
    else
        region_mask = trues(Base.size(rgb_data, 1), Base.size(rgb_data, 2))
    end
    
    # Create white mask
    white_mask_all = (rgb_data[:,:,1] .>= threshold) .& 
                     (rgb_data[:,:,2] .>= threshold) .& 
                     (rgb_data[:,:,3] .>= threshold) .&
                     region_mask
    
    # Apply morphological operations
    if kernel_size > 0
        white_mask_all = morphological_close(white_mask_all, kernel_size)
        white_mask_all = morphological_open(white_mask_all, kernel_size)
    end
    
    # Label components
    labeled = Bas3ImageSegmentation.label_components(white_mask_all)
    num_components = Base.maximum(labeled)
    
    # Extract component information
    component_info = NamedTuple{(:label, :size, :centroid, :bbox), Tuple{Int, Int, Tuple{Float64, Float64}, Tuple{Int, Int, Int, Int}}}[]
    
    for label in 1:num_components
        component_mask = labeled .== label
        component_size = sum(component_mask)
        
        # Skip if too small
        if component_size < min_area
            continue
        end
        
        # Get pixel coordinates
        pixel_coords = findall(component_mask)
        if isempty(pixel_coords)
            continue
        end
        
        row_indices = [p[1] for p in pixel_coords]
        col_indices = [p[2] for p in pixel_coords]
        
        # Compute centroid
        centroid_row = sum(row_indices) / length(row_indices)
        centroid_col = sum(col_indices) / length(col_indices)
        
        # Compute axis-aligned bounding box
        r_min = Base.minimum(row_indices)
        r_max = Base.maximum(row_indices)
        c_min = Base.minimum(col_indices)
        c_max = Base.maximum(col_indices)
        
        info = (
            label = label,
            size = component_size,
            centroid = (centroid_row, centroid_col),
            bbox = (r_min, r_max, c_min, c_max)
        )
        
        push!(component_info, info)
    end
    
    return labeled, length(component_info), component_info
end
