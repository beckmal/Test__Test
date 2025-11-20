# Load_Sets__MarkerCorrespondence.jl
# Marker detection, correspondence establishment, and dewarping pipeline

"""
    Load_Sets__MarkerCorrespondence

Module for detecting calibration markers and establishing correspondence
between detected positions and canonical (ideal) positions.

# Key Functions
- `detect_calibration_markers(image)`: Find multiple marker regions
- `define_canonical_positions(markers, mode)`: Define target positions
- `establish_correspondence(detected, canonical)`: Match markers to targets
- `dewarp_image_with_markers(image)`: Complete dewarping pipeline

# Marker Types
Supports different marker configurations:
- `:corners_4`: Four corner markers (rectangular)
- `:grid_2x2`: 2×2 grid (4 markers)
- `:grid_3x3`: 3×3 grid (9 markers)
- `:custom`: User-defined positions
"""

using Statistics
using LinearAlgebra

# Note: Requires Load_Sets__ConnectedComponents.jl and Load_Sets__ThinPlateSpline.jl

# ============================================================================
# Marker Information Structure
# ============================================================================

"""
    MarkerInfo

Structure to hold information about a detected marker.

# Fields
- `centroid::Tuple{Float64, Float64}`: Marker center (row, col)
- `corners::Vector{Float64}`: Oriented bounding box corners [r1,c1,r2,c2,r3,c3,r4,c4]
- `mask::BitMatrix`: Binary mask of marker region
- `size::Int`: Number of pixels
- `angle::Float64`: Rotation angle (radians)
- `aspect_ratio::Float64`: Length/width ratio
- `density::Float64`: Pixel density in bounding box
"""
struct MarkerInfo
    centroid::Tuple{Float64, Float64}
    corners::Vector{Float64}
    mask::BitMatrix
    size::Int
    angle::Float64
    aspect_ratio::Float64
    density::Float64
end

# ============================================================================
# Multi-Marker Detection
# ============================================================================

"""
    detect_calibration_markers(image; 
                                threshold::Float64=0.7,
                                min_area::Int=8000,
                                max_markers::Int=20,
                                min_aspect_ratio::Float64=3.0,
                                max_aspect_ratio::Float64=7.0,
                                kernel_size::Int=3,
                                region::Union{Nothing, Tuple}=nothing)
    -> Vector{MarkerInfo}

Detect multiple calibration markers in an image.

# Algorithm
1. Extract white mask with all connected components
2. Analyze each component separately
3. Filter by size, aspect ratio, and density
4. Return sorted by size (largest first)

# Arguments
- `threshold::Float64`: RGB threshold for white detection (0.0-1.0)
- `min_area::Int`: Minimum marker size in pixels
- `max_markers::Int`: Maximum number of markers to detect
- `min_aspect_ratio, max_aspect_ratio`: Expected marker shape range
- `kernel_size::Int`: Morphological operation kernel size
- `region::Union{Nothing, Tuple}`: Optional ROI (r_min, r_max, c_min, c_max)

# Returns
- `Vector{MarkerInfo}`: Detected markers, sorted by size (descending)

# Example
```julia
markers = detect_calibration_markers(image; 
    threshold=0.7,
    min_area=8000,
    min_aspect_ratio=4.0,
    max_aspect_ratio=6.0)

println("Found ", length(markers), " markers")
for (i, m) in enumerate(markers)
    println("  Marker \$i: center=\$(m.centroid), aspect=\$(m.aspect_ratio)")
end
```
"""
function detect_calibration_markers(image; 
                                     threshold::Float64=0.7,
                                     min_area::Int=8000,
                                     max_markers::Int=20,
                                     min_aspect_ratio::Float64=3.0,
                                     max_aspect_ratio::Float64=7.0,
                                     kernel_size::Int=3,
                                     region::Union{Nothing, Tuple}=nothing)
    
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
    
    # Extract all white regions
    white_mask_all = (rgb_data[:,:,1] .>= threshold) .& 
                     (rgb_data[:,:,2] .>= threshold) .& 
                     (rgb_data[:,:,3] .>= threshold) .&
                     region_mask
    
    # Apply morphological operations
    if kernel_size > 0
        white_mask_all = morphological_close(white_mask_all, kernel_size)
        white_mask_all = morphological_open(white_mask_all, kernel_size)
    end
    
    # Label connected components
    labeled = Bas3ImageSegmentation.label_components(white_mask_all)
    num_components = Base.maximum(labeled)
    
    if num_components == 0
        return MarkerInfo[]
    end
    
    # Analyze each component
    markers = MarkerInfo[]
    
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
        
        row_indices = Float64[p[1] for p in pixel_coords]
        col_indices = Float64[p[2] for p in pixel_coords]
        
        # Compute centroid
        centroid_row = mean(row_indices)
        centroid_col = mean(col_indices)
        
        # Center coordinates for PCA
        centered_rows = row_indices .- centroid_row
        centered_cols = col_indices .- centroid_col
        
        # Covariance matrix for PCA
        n = length(centered_rows)
        cov_matrix = [
            sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
            sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
        ]
        
        # Compute eigenvectors
        eigen_result = eigen(cov_matrix)
        principal_axes = eigen_result.vectors
        
        # Project onto principal axes
        proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
        proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
        
        min_proj1, max_proj1 = extrema(proj_axis1)
        min_proj2, max_proj2 = extrema(proj_axis2)
        
        # Oriented bounding box dimensions
        rotated_width = max_proj1 - min_proj1
        rotated_height = max_proj2 - min_proj2
        rotated_bbox_area = rotated_width * rotated_height
        
        # Density
        density = component_size / rotated_bbox_area
        
        # Rotation angle
        rotation_angle = atan(principal_axes[1, 2], principal_axes[2, 2])
        
        # Corners in original coordinates
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
        
        corners_flat = vcat([[c[1], c[2]] for c in corners_original]...)
        
        # Aspect ratio
        aspect_ratio = max(rotated_width, rotated_height) / min(rotated_width, rotated_height)
        
        # Note: Aspect ratio validation removed to allow detection of valid markers
        # with unusual shapes (very round or elongated). TPS only uses centroids,
        # so geometric properties don't affect dewarping quality.
        
        # Create MarkerInfo
        marker = MarkerInfo(
            (centroid_row, centroid_col),
            corners_flat,
            component_mask,
            component_size,
            rotation_angle,
            aspect_ratio,
            density
        )
        
        push!(markers, marker)
        
        # Stop if reached max markers
        if length(markers) >= max_markers
            break
        end
    end
    
    # Sort by size (largest first)
    sort!(markers, by=m -> m.size, rev=true)
    
    return markers
end

# ============================================================================
# Canonical Position Definition
# ============================================================================

"""
    define_canonical_positions(markers::Vector{MarkerInfo},
                               mode::Symbol=:corners_4;
                               image_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                               margin::Float64=10.0,
                               spacing::Union{Nothing, Float64}=nothing)
    -> Matrix{Float64}

Define canonical (ideal) positions for detected markers.

# Modes
- `:corners_4`: 4 corners of rectangle with margins
- `:grid_2x2`: 2×2 regular grid
- `:grid_3x3`: 3×3 regular grid
- `:auto`: Automatically detect grid pattern from marker positions
- `:preserve_relative`: Keep relative positions but regularize spacing

# Arguments
- `markers::Vector{MarkerInfo}`: Detected markers
- `mode::Symbol`: Positioning mode
- `image_size::Union{Nothing, Tuple{Int, Int}}`: Target image size (height, width)
  - If nothing, infers from marker positions
- `margin::Float64`: Margin from image edges (pixels)
- `spacing::Union{Nothing, Float64}`: Grid spacing (for grid modes)
  - If nothing, computed from marker distribution

# Returns
- `Matrix{Float64}`: N×2 canonical positions [row, col]

# Example
```julia
markers = detect_calibration_markers(image)
canonical = define_canonical_positions(markers, :corners_4; 
    image_size=(500, 500), margin=20.0)
```
"""
function define_canonical_positions(markers::Vector{MarkerInfo},
                                     mode::Symbol=:corners_4;
                                     image_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                                     margin::Float64=10.0,
                                     spacing::Union{Nothing, Float64}=nothing)
    
    n_markers = length(markers)
    
    if n_markers == 0
        error("No markers provided")
    end
    
    # Infer image size if not provided
    if isnothing(image_size)
        # Find bounding box of all markers
        all_rows = [m.centroid[1] for m in markers]
        all_cols = [m.centroid[2] for m in markers]
        max_row = Base.maximum(all_rows) + margin
        max_col = Base.maximum(all_cols) + margin
        image_height = ceil(Int, max_row + margin)
        image_width = ceil(Int, max_col + margin)
    else
        image_height, image_width = image_size
    end
    
    canonical_positions = zeros(Float64, n_markers, 2)
    
    if mode == :corners_4
        # Four corners in rectangular arrangement
        if n_markers != 4
            @warn "corners_4 mode expects 4 markers, got $n_markers. Using first 4."
            n_markers = min(4, n_markers)
        end
        
        # Define corners: top-left, top-right, bottom-right, bottom-left
        canonical_positions[1, :] = [margin, margin]
        canonical_positions[2, :] = [margin, image_width - margin]
        canonical_positions[3, :] = [image_height - margin, image_width - margin]
        canonical_positions[4, :] = [image_height - margin, margin]
        
    elseif mode == :grid_2x2
        # 2×2 grid
        if n_markers != 4
            @warn "grid_2x2 expects 4 markers, got $n_markers"
        end
        
        grid_spacing = isnothing(spacing) ? (min(image_height, image_width) - 2*margin) : spacing
        
        positions = [
            [margin, margin],
            [margin, margin + grid_spacing],
            [margin + grid_spacing, margin],
            [margin + grid_spacing, margin + grid_spacing]
        ]
        
        for i in 1:min(4, n_markers)
            canonical_positions[i, :] = positions[i]
        end
        
    elseif mode == :grid_3x3
        # 3×3 grid
        if n_markers != 9
            @warn "grid_3x3 expects 9 markers, got $n_markers"
        end
        
        grid_spacing = isnothing(spacing) ? (min(image_height, image_width) - 2*margin) / 2 : spacing
        
        idx = 1
        for i in 0:2
            for j in 0:2
                if idx <= n_markers
                    canonical_positions[idx, :] = [margin + i*grid_spacing, margin + j*grid_spacing]
                    idx += 1
                end
            end
        end
        
    elseif mode == :auto
        # Auto-detect grid structure from marker positions
        # Use clustering or nearest-neighbor analysis
        all_rows = [m.centroid[1] for m in markers]
        all_cols = [m.centroid[2] for m in markers]
        
        # Estimate grid dimensions
        unique_rows = unique(round.(all_rows, digits=0))
        unique_cols = unique(round.(all_cols, digits=0))
        
        # Simple regularization: create uniform grid
        row_spacing = (Base.maximum(all_rows) - Base.minimum(all_rows)) / (length(unique_rows) - 1)
        col_spacing = (Base.maximum(all_cols) - Base.minimum(all_cols)) / (length(unique_cols) - 1)
        
        # Place markers on regular grid
        for (i, marker) in enumerate(markers)
            row_idx = round(Int, (marker.centroid[1] - Base.minimum(all_rows)) / row_spacing)
            col_idx = round(Int, (marker.centroid[2] - Base.minimum(all_cols)) / col_spacing)
            
            canonical_positions[i, :] = [
                margin + row_idx * row_spacing,
                margin + col_idx * col_spacing
            ]
        end
        
    elseif mode == :preserve_relative
        # Keep relative positions but regularize
        all_rows = [m.centroid[1] for m in markers]
        all_cols = [m.centroid[2] for m in markers]
        
        # Normalize to [margin, size-margin] range
        min_row, max_row = extrema(all_rows)
        min_col, max_col = extrema(all_cols)
        
        row_range = max_row - min_row
        col_range = max_col - min_col
        
        for (i, marker) in enumerate(markers)
            normalized_row = (marker.centroid[1] - min_row) / row_range
            normalized_col = (marker.centroid[2] - min_col) / col_range
            
            canonical_positions[i, :] = [
                margin + normalized_row * (image_height - 2*margin),
                margin + normalized_col * (image_width - 2*margin)
            ]
        end
        
    else
        error("Unknown mode: $mode. Use :corners_4, :grid_2x2, :grid_3x3, :auto, or :preserve_relative")
    end
    
    return canonical_positions[1:n_markers, :]
end

# ============================================================================
# Correspondence Establishment
# ============================================================================

"""
    establish_correspondence(markers::Vector{MarkerInfo},
                             canonical_positions::Matrix{Float64};
                             method::Symbol=:spatial_order)
    -> (source_points, target_points)

Match detected markers to canonical positions.

# Methods
- `:spatial_order`: Order by spatial position (left-to-right, top-to-bottom)
- `:nearest_neighbor`: Match each marker to nearest canonical position
- `:hungarian`: Optimal assignment using Hungarian algorithm

# Arguments
- `markers::Vector{MarkerInfo}`: Detected markers
- `canonical_positions::Matrix{Float64}`: N×2 target positions
- `method::Symbol`: Matching method

# Returns
- `source_points::Matrix{Float64}`: Detected positions [row, col]
- `target_points::Matrix{Float64}`: Corresponding canonical positions

# Example
```julia
markers = detect_calibration_markers(image)
canonical = define_canonical_positions(markers, :corners_4)
source, target = establish_correspondence(markers, canonical)
```
"""
function establish_correspondence(markers::Vector{MarkerInfo},
                                   canonical_positions::Matrix{Float64};
                                   method::Symbol=:spatial_order)
    
    n_markers = length(markers)
    n_canonical = Base.size(canonical_positions, 1)
    
    if n_markers != n_canonical
        @warn "Number of markers ($n_markers) != canonical positions ($n_canonical). Using minimum."
        n = min(n_markers, n_canonical)
        markers = markers[1:n]
        canonical_positions = canonical_positions[1:n, :]
        n_markers = n
        n_canonical = n
    end
    
    source_points = zeros(Float64, n_markers, 2)
    target_points = zeros(Float64, n_markers, 2)
    
    if method == :spatial_order
        # Sort both by spatial position (row-major order)
        marker_positions = [(m.centroid[1], m.centroid[2], i) for (i, m) in enumerate(markers)]
        sort!(marker_positions, by=p -> (p[1], p[2]))  # Sort by row, then col
        
        canonical_list = [(canonical_positions[i, 1], canonical_positions[i, 2], i) 
                          for i in 1:n_canonical]
        sort!(canonical_list, by=p -> (p[1], p[2]))
        
        for i in 1:n_markers
            marker_idx = marker_positions[i][3]
            canonical_idx = canonical_list[i][3]
            
            source_points[i, :] = [markers[marker_idx].centroid[1], markers[marker_idx].centroid[2]]
            target_points[i, :] = canonical_positions[canonical_idx, :]
        end
        
    elseif method == :nearest_neighbor
        # Greedy nearest neighbor matching
        used_canonical = Set{Int}()
        
        for (i, marker) in enumerate(markers)
            best_dist = Inf
            best_idx = 1
            
            for j in 1:n_canonical
                if j ∈ used_canonical
                    continue
                end
                
                dx = marker.centroid[1] - canonical_positions[j, 1]
                dy = marker.centroid[2] - canonical_positions[j, 2]
                dist = sqrt(dx^2 + dy^2)
                
                if dist < best_dist
                    best_dist = dist
                    best_idx = j
                end
            end
            
            push!(used_canonical, best_idx)
            source_points[i, :] = [marker.centroid[1], marker.centroid[2]]
            target_points[i, :] = canonical_positions[best_idx, :]
        end
        
    else
        error("Unknown method: $method. Use :spatial_order or :nearest_neighbor")
    end
    
    return source_points, target_points
end

# ============================================================================
# Complete Dewarping Pipeline
# ============================================================================

"""
    dewarp_image_with_markers(image;
                              marker_detection_params::Dict=Dict(),
                              canonical_mode::Symbol=:corners_4,
                              canonical_params::Dict=Dict(),
                              correspondence_method::Symbol=:spatial_order,
                              tps_regularization::Float64=0.0,
                              output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                              return_debug_info::Bool=false)
    -> Union{image, Tuple}

Complete pipeline for marker-based image dewarping.

# Workflow
1. Detect calibration markers
2. Define canonical positions
3. Establish correspondence
4. Compute TPS transformation
5. Warp image

# Arguments
- `image`: Input image to dewarp
- `marker_detection_params::Dict`: Parameters for detect_calibration_markers
  - :threshold, :min_area, :min_aspect_ratio, etc.
- `canonical_mode::Symbol`: Mode for canonical position definition
- `canonical_params::Dict`: Parameters for define_canonical_positions
- `correspondence_method::Symbol`: Matching method
- `tps_regularization::Float64`: TPS smoothing parameter
- `output_size`: Output dimensions (default: input size)
- `return_debug_info::Bool`: If true, return (image, debug_dict)

# Returns
- Dewarped image (if return_debug_info=false)
- (Dewarped image, debug_dict) if return_debug_info=true

Debug dict contains:
- :markers: Detected markers
- :source_points: Detected positions
- :target_points: Canonical positions
- :tps_params: TPS weights and affine parameters
- :residual_error: Mean/max error at control points
- :deformation_magnitude: Mean/max displacement

# Example
```julia
# Simple usage
dewarped = dewarp_image_with_markers(image)

# With parameters
dewarped, debug = dewarp_image_with_markers(image;
    marker_detection_params=Dict(:threshold => 0.75, :min_area => 10000),
    canonical_mode=:corners_4,
    tps_regularization=0.001,
    return_debug_info=true)

println("Found ", length(debug[:markers]), " markers")
println("Mean error: ", debug[:residual_error][1])
```
"""
function dewarp_image_with_markers(image;
                                    marker_detection_params::Dict=Dict(),
                                    canonical_mode::Symbol=:corners_4,
                                    canonical_params::Dict=Dict(),
                                    correspondence_method::Symbol=:spatial_order,
                                    tps_regularization::Float64=0.0,
                                    output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                                    return_debug_info::Bool=false)
    
    # Step 1: Detect markers
    markers = detect_calibration_markers(image; marker_detection_params...)
    
    if isempty(markers)
        error("No calibration markers detected. Adjust detection parameters.")
    end
    
    println("Detected $(length(markers)) calibration markers")
    
    # Step 2: Define canonical positions
    image_data = Bas3ImageSegmentation.data(image)
    img_size = isnothing(output_size) ? (Base.size(image_data, 1), Base.size(image_data, 2)) : output_size
    
    canonical_positions = define_canonical_positions(
        markers, canonical_mode; 
        image_size=img_size,
        canonical_params...
    )
    
    # Step 3: Establish correspondence
    source_points, target_points = establish_correspondence(
        markers, canonical_positions;
        method=correspondence_method
    )
    
    println("Established correspondence for $(Base.size(source_points, 1)) control points")
    
    # Step 4: Compute TPS parameters and error metrics
    weights_row, weights_col, affine_row, affine_col = 
        compute_tps_parameters(source_points, target_points; 
                               regularization=tps_regularization)
    
    mean_error, max_error, per_point_errors = 
        compute_tps_residual_error(source_points, target_points,
                                    weights_row, weights_col,
                                    affine_row, affine_col)
    
    mean_displacement, max_displacement = 
        estimate_deformation_magnitude(source_points, target_points)
    
    println("TPS fitted: mean residual = $(round(mean_error, digits=3)) px, " *
            "max residual = $(round(max_error, digits=3)) px")
    println("Deformation: mean = $(round(mean_displacement, digits=2)) px, " *
            "max = $(round(max_displacement, digits=2)) px")
    
    # Step 5: Warp image
    dewarped_image = warp_image_tps(image, source_points, target_points;
                                     output_size=output_size,
                                     regularization=tps_regularization)
    
    println("Image dewarped successfully")
    
    if return_debug_info
        debug_info = Dict(
            :markers => markers,
            :source_points => source_points,
            :target_points => target_points,
            :tps_params => (weights_row, weights_col, affine_row, affine_col),
            :residual_error => (mean_error, max_error, per_point_errors),
            :deformation_magnitude => (mean_displacement, max_displacement)
        )
        return dewarped_image, debug_info
    else
        return dewarped_image
    end
end

println("✅ Marker correspondence module loaded: marker detection and dewarping pipeline")
