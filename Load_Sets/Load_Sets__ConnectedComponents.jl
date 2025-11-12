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
# White Region Extraction with PCA-Based Bounding Box
# ============================================================================

"""
    extract_white_mask(img; threshold=0.7, min_component_area=100, 
                       preferred_aspect_ratio=5.0, aspect_ratio_weight=0.5, 
                       kernel_size=3, region=nothing)
    -> (mask, size, percentage, num_components, density, corners, angle, aspect_ratio)

Find best white region using PCA-based oriented bounding box analysis.

# Algorithm
1. Threshold RGB channels to create initial white mask
2. Apply morphological closing and opening to improve connectivity
3. Label connected components
4. For each component:
   - Compute PCA to find principal axes
   - Calculate oriented bounding box (minimum area rectangle)
   - Compute density and aspect ratio
   - Score based on weighted combination of density and aspect ratio match
5. Select component with highest combined score

# Parameters
- `threshold::Float64`: RGB threshold for white detection (0.0-1.0, default: 0.7)
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
mask, size, pct, n_comp, density, corners, angle, aspect = 
    extract_white_mask(image; 
        threshold=0.7,
        min_component_area=8000,
        preferred_aspect_ratio=5.0,
        aspect_ratio_weight=0.6,
        kernel_size=3)
```
"""
function extract_white_mask(img; threshold=0.7, min_component_area=100, 
                            preferred_aspect_ratio=5.0, aspect_ratio_weight=0.5, 
                            kernel_size=3, region=nothing)
    rgb_data = Bas3ImageSegmentation.data(img)
    
    # Apply region mask if specified
    if !isnothing(region)
        r_min, r_max, c_min, c_max = region
        # Clamp to valid bounds
        r_min = max(1, min(r_min, size(rgb_data, 1)))
        r_max = max(1, min(r_max, size(rgb_data, 1)))
        c_min = max(1, min(c_min, size(rgb_data, 2)))
        c_max = max(1, min(c_max, size(rgb_data, 2)))
        # Create mask for region
        region_mask = falses(size(rgb_data, 1), size(rgb_data, 2))
        region_mask[r_min:r_max, c_min:c_max] .= true
    else
        region_mask = trues(size(rgb_data, 1), size(rgb_data, 2))
    end
    
    # Initial white mask - all pixels with RGB >= threshold AND within region
    white_mask_all = (rgb_data[:,:,1] .>= threshold) .& 
                     (rgb_data[:,:,2] .>= threshold) .& 
                     (rgb_data[:,:,3] .>= threshold) .&
                     region_mask
    
    # Apply morphological operations to improve connectivity
    if kernel_size > 0
        white_mask_all = morphological_close(white_mask_all, kernel_size)
        white_mask_all = morphological_open(white_mask_all, kernel_size)
    end
    
    # Label all connected components
    labeled = Bas3ImageSegmentation.label_components(white_mask_all)
    num_components = maximum(labeled)
    
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
        # Get mask for this component
        component_mask = labeled .== label
        component_size = sum(component_mask)
        
        # Skip if below minimum area
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
        
        # Combined score: weighted average of density and aspect ratio match
        combined_score = (1.0 - aspect_ratio_weight) * normalized_density + aspect_ratio_weight * aspect_ratio_score
        
        # Select component with highest combined score
        if combined_score > best_score
            best_score = combined_score
            best_density = rotated_density
            best_label = label
            best_rotated_corners = vcat([[c[1], c[2]] for c in corners_original]...)
            best_rotation_angle = rotation_angle
            best_size = component_size
            best_aspect_ratio = aspect_ratio
        end
    end
    
    if best_label == 0
        # No components met the minimum area requirement
        return white_mask_all, 0, 0.0, num_components, 0.0, Float64[], 0.0, 0.0
    end
    
    # Create mask with only the densest component
    white_mask = labeled .== best_label
    
    total_pixels = size(rgb_data, 1) * size(rgb_data, 2)
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
    channel_names = if size(rgb_data, 1) == 3
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
    h, w = size(mask)
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
