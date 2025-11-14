# Load_Sets__ThinPlateSpline.jl
# Thin Plate Spline (TPS) transformation for image dewarping

"""
    Load_Sets__ThinPlateSpline

Thin Plate Spline (TPS) implementation for non-rigid image warping.
Used for dewarping images based on calibration marker correspondence.

# Theory
Thin Plate Spline minimizes bending energy while interpolating control points.
The radial basis function is: φ(r) = r² log(r)

# Key Functions
- `tps_kernel(r)`: Radial basis function
- `compute_tps_parameters(source_points, target_points)`: Fit TPS transformation
- `apply_tps_transform(point, source_points, weights, affine_params)`: Transform single point
- `warp_image_tps(image, source_points, target_points)`: Warp entire image
- `warp_mask_tps(mask, source_points, target_points)`: Warp binary mask

# References
- Bookstein, F. L. (1989). Principal warps: Thin-plate splines and the decomposition 
  of deformations. IEEE Transactions on Pattern Analysis and Machine Intelligence.
"""

using LinearAlgebra
using Statistics

# ============================================================================
# TPS Kernel and Basic Functions
# ============================================================================

"""
    tps_kernel(r::Float64) -> Float64

Thin plate spline radial basis function: φ(r) = r² log(r).

# Arguments
- `r::Float64`: Radial distance

# Returns
- Kernel value (0.0 if r ≈ 0)

# Note
Handles r = 0 case by returning 0 (limit as r → 0 is 0).
"""
function tps_kernel(r::Float64)
    if r < 1e-10
        return 0.0
    end
    return r * r * log(r)
end

"""
    build_kernel_matrix(points::Matrix{Float64}) -> Matrix{Float64}

Build TPS kernel matrix K where K[i,j] = φ(||p_i - p_j||).

# Arguments
- `points::Matrix{Float64}`: N×2 matrix of control points [row, col]

# Returns
- `K::Matrix{Float64}`: N×N kernel matrix
"""
function build_kernel_matrix(points::Matrix{Float64})
    n = size(points, 1)
    K = zeros(Float64, n, n)
    
    for i in 1:n
        for j in 1:n
            if i != j
                dx = points[i, 1] - points[j, 1]
                dy = points[i, 2] - points[j, 2]
                r = sqrt(dx * dx + dy * dy)
                K[i, j] = tps_kernel(r)
            end
        end
    end
    
    return K
end

# ============================================================================
# TPS Parameter Computation
# ============================================================================

"""
    compute_tps_parameters(source_points::Matrix{Float64}, 
                           target_points::Matrix{Float64};
                           regularization::Float64=0.0) 
    -> (weights_row, weights_col, affine_row, affine_col)

Compute TPS transformation parameters from source to target points.

# Algorithm
Solves the linear system:
    [K  P] [w]   [v]
    [P' 0] [a] = [0]

where:
- K: kernel matrix
- P: homogeneous coordinates [1, x, y]
- w: TPS weights for radial basis functions
- a: affine transformation parameters [a₀, aₓ, aᵧ]
- v: target coordinates

# Arguments
- `source_points::Matrix{Float64}`: N×2 control points in source image [row, col]
- `target_points::Matrix{Float64}`: N×2 corresponding points in target space [row, col]
- `regularization::Float64`: Regularization parameter λ (default: 0.0)
  - λ = 0: Exact interpolation
  - λ > 0: Smooth approximation (useful for noisy points)

# Returns
Tuple of:
- `weights_row::Vector{Float64}`: TPS weights for row coordinate (length N)
- `weights_col::Vector{Float64}`: TPS weights for col coordinate (length N)
- `affine_row::Vector{Float64}`: Affine parameters for row [a₀, aₓ, aᵧ]
- `affine_col::Vector{Float64}`: Affine parameters for col [a₀, aₓ, aᵧ]

# Example
```julia
# Define correspondence: 4 corners
source = [1.0 1.0; 100.0 1.0; 100.0 100.0; 1.0 100.0]
target = [5.0 5.0; 95.0 8.0; 92.0 95.0; 8.0 92.0]  # Warped
w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)
```
"""
function compute_tps_parameters(source_points::Matrix{Float64}, 
                                 target_points::Matrix{Float64};
                                 regularization::Float64=0.0)
    n = size(source_points, 1)
    
    if size(target_points, 1) != n
        error("Source and target points must have same number of points")
    end
    
    if n < 3
        error("Need at least 3 control points for TPS")
    end
    
    # Build kernel matrix K (n × n)
    K = build_kernel_matrix(source_points)
    
    # Add regularization to diagonal
    if regularization > 0.0
        K .+= regularization * I(n)
    end
    
    # Build constraint matrix P (n × 3): [1, x, y]
    P = zeros(Float64, n, 3)
    P[:, 1] .= 1.0
    P[:, 2] = source_points[:, 1]  # row coordinates
    P[:, 3] = source_points[:, 2]  # col coordinates
    
    # Build full system matrix L: [K P; P' 0]
    # Size: (n+3) × (n+3)
    L = zeros(Float64, n + 3, n + 3)
    L[1:n, 1:n] = K
    L[1:n, n+1:n+3] = P
    L[n+1:n+3, 1:n] = P'
    # L[n+1:n+3, n+1:n+3] remains zero
    
    # Build right-hand side vectors for row and col separately
    # For row coordinate
    b_row = zeros(Float64, n + 3)
    b_row[1:n] = target_points[:, 1]  # target row coordinates
    
    # For col coordinate
    b_col = zeros(Float64, n + 3)
    b_col[1:n] = target_points[:, 2]  # target col coordinates
    
    # Solve linear systems
    try
        solution_row = L \ b_row
        solution_col = L \ b_col
        
        # Extract weights and affine parameters
        weights_row = solution_row[1:n]
        affine_row = solution_row[n+1:n+3]
        
        weights_col = solution_col[1:n]
        affine_col = solution_col[n+1:n+3]
        
        return weights_row, weights_col, affine_row, affine_col
        
    catch e
        error("Failed to solve TPS system (matrix may be singular). Try adding regularization. Error: $e")
    end
end

# ============================================================================
# TPS Transformation Application
# ============================================================================

"""
    apply_tps_transform(point::Tuple{Float64, Float64},
                        source_points::Matrix{Float64},
                        weights_row::Vector{Float64},
                        weights_col::Vector{Float64},
                        affine_row::Vector{Float64},
                        affine_col::Vector{Float64})
    -> (new_row, new_col)

Transform a single point using computed TPS parameters.

# Arguments
- `point::Tuple{Float64, Float64}`: Input point (row, col) in source space
- `source_points::Matrix{Float64}`: N×2 control points used for TPS fitting
- `weights_row, weights_col::Vector{Float64}`: TPS weights
- `affine_row, affine_col::Vector{Float64}`: Affine parameters [a₀, aₓ, aᵧ]

# Returns
- `(new_row, new_col)`: Transformed point in target space

# Note
This implements the forward transformation: source → target
"""
function apply_tps_transform(point::Tuple{Float64, Float64},
                              source_points::Matrix{Float64},
                              weights_row::Vector{Float64},
                              weights_col::Vector{Float64},
                              affine_row::Vector{Float64},
                              affine_col::Vector{Float64})
    x, y = point
    n = size(source_points, 1)
    
    # Start with affine component: a₀ + aₓ*x + aᵧ*y
    new_row = affine_row[1] + affine_row[2] * x + affine_row[3] * y
    new_col = affine_col[1] + affine_col[2] * x + affine_col[3] * y
    
    # Add non-linear TPS component: Σ wᵢ φ(||p - pᵢ||)
    for i in 1:n
        dx = x - source_points[i, 1]
        dy = y - source_points[i, 2]
        r = sqrt(dx * dx + dy * dy)
        kernel_val = tps_kernel(r)
        
        new_row += weights_row[i] * kernel_val
        new_col += weights_col[i] * kernel_val
    end
    
    return (new_row, new_col)
end

# ============================================================================
# Image Warping
# ============================================================================

"""
    warp_image_tps(image,
                   source_points::Matrix{Float64},
                   target_points::Matrix{Float64};
                   output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                   regularization::Float64=0.0,
                   fill_value::Float32=0.0f0)
    -> warped_image

Warp image using thin plate spline transformation.

# Algorithm
Uses inverse mapping: for each pixel in output, find corresponding location
in input image and interpolate. This ensures no holes in output.

# Arguments
- `image`: Input image (Bas3ImageSegmentation.c__Image_Data)
- `source_points::Matrix{Float64}`: N×2 control points in warped image [row, col]
- `target_points::Matrix{Float64}`: N×2 canonical/target positions [row, col]
- `output_size::Union{Nothing, Tuple{Int, Int}}`: Output dimensions (height, width)
  - If nothing, uses input image size
- `regularization::Float64`: TPS regularization parameter (default: 0.0)
- `fill_value::Float32`: Value for out-of-bounds pixels (default: 0.0)

# Returns
- Warped image (same type as input)

# Note
This computes INVERSE transformation (target → source) for warping.
Control points should be specified in the direction: warped → canonical.

# Example
```julia
# Markers detected in warped image at these positions
source = [10.0 10.0; 490.0 15.0; 485.0 490.0; 15.0 485.0]
# Canonical positions (where they should be)
target = [10.0 10.0; 490.0 10.0; 490.0 490.0; 10.0 490.0]

dewarped = warp_image_tps(image, source, target)
```
"""
function warp_image_tps(image,
                        source_points::Matrix{Float64},
                        target_points::Matrix{Float64};
                        output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                        regularization::Float64=0.0,
                        fill_value::Float32=0.0f0)
    
    # Get input dimensions
    input_data = Bas3ImageSegmentation.data(image)
    input_height, input_width, num_channels = size(input_data)
    
    # Determine output size
    if isnothing(output_size)
        output_height, output_width = input_height, input_width
    else
        output_height, output_width = output_size
    end
    
    # Compute TPS parameters for INVERSE transformation (target → source)
    # This allows us to sample from source for each target pixel
    weights_row, weights_col, affine_row, affine_col = 
        compute_tps_parameters(target_points, source_points; 
                               regularization=regularization)
    
    # Create output array
    output_data = fill(fill_value, output_height, output_width, num_channels)
    
    # For each output pixel, find source location and interpolate
    for out_row in 1:output_height
        for out_col in 1:output_width
            # Transform output coordinates to input coordinates
            src_row, src_col = apply_tps_transform(
                (Float64(out_row), Float64(out_col)),
                target_points,
                weights_row, weights_col,
                affine_row, affine_col
            )
            
            # Check if source location is within input bounds
            if src_row >= 1 && src_row <= input_height && 
               src_col >= 1 && src_col <= input_width
                
                # Bilinear interpolation
                row_low = floor(Int, src_row)
                row_high = min(ceil(Int, src_row), input_height)
                col_low = floor(Int, src_col)
                col_high = min(ceil(Int, src_col), input_width)
                
                # Interpolation weights
                row_weight = src_row - row_low
                col_weight = src_col - col_low
                
                # Ensure valid indices
                row_low = max(1, row_low)
                col_low = max(1, col_low)
                
                # Interpolate all channels
                for ch in 1:num_channels
                    # Four corner values
                    val_00 = input_data[row_low, col_low, ch]
                    val_01 = input_data[row_low, col_high, ch]
                    val_10 = input_data[row_high, col_low, ch]
                    val_11 = input_data[row_high, col_high, ch]
                    
                    # Bilinear interpolation
                    val_0 = (1 - col_weight) * val_00 + col_weight * val_01
                    val_1 = (1 - col_weight) * val_10 + col_weight * val_11
                    interpolated = (1 - row_weight) * val_0 + row_weight * val_1
                    
                    output_data[out_row, out_col, ch] = interpolated
                end
            end
            # else: keep fill_value
        end
    end
    
    # Create output image with same type as input
    channels_tuple = Bas3ImageSegmentation.m__get_channels(image)
    output_image = Bas3ImageSegmentation.c__Image_Data{Float32, channels_tuple}(output_data)
    
    return output_image
end

"""
    warp_mask_tps(mask::BitMatrix,
                  source_points::Matrix{Float64},
                  target_points::Matrix{Float64};
                  output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                  regularization::Float64=0.0,
                  threshold::Float64=0.5)
    -> BitMatrix

Warp binary mask using TPS transformation.

# Arguments
- `mask::BitMatrix`: Binary mask to warp
- `source_points, target_points`: Control point correspondence
- `output_size`: Output dimensions (default: input size)
- `regularization`: TPS regularization
- `threshold`: Threshold for binarization after interpolation (default: 0.5)

# Returns
- Warped binary mask
"""
function warp_mask_tps(mask::BitMatrix,
                       source_points::Matrix{Float64},
                       target_points::Matrix{Float64};
                       output_size::Union{Nothing, Tuple{Int, Int}}=nothing,
                       regularization::Float64=0.0,
                       threshold::Float64=0.5)
    
    input_height, input_width = size(mask)
    
    if isnothing(output_size)
        output_height, output_width = input_height, input_width
    else
        output_height, output_width = output_size
    end
    
    # Compute inverse TPS parameters
    weights_row, weights_col, affine_row, affine_col = 
        compute_tps_parameters(target_points, source_points; 
                               regularization=regularization)
    
    # Create output mask
    output_mask = falses(output_height, output_width)
    
    # Transform each output pixel
    for out_row in 1:output_height
        for out_col in 1:output_width
            src_row, src_col = apply_tps_transform(
                (Float64(out_row), Float64(out_col)),
                target_points,
                weights_row, weights_col,
                affine_row, affine_col
            )
            
            # Nearest neighbor sampling for binary mask
            src_row_int = round(Int, src_row)
            src_col_int = round(Int, src_col)
            
            if src_row_int >= 1 && src_row_int <= input_height && 
               src_col_int >= 1 && src_col_int <= input_width
                output_mask[out_row, out_col] = mask[src_row_int, src_col_int]
            end
        end
    end
    
    return output_mask
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    compute_tps_residual_error(source_points::Matrix{Float64},
                                target_points::Matrix{Float64},
                                weights_row::Vector{Float64},
                                weights_col::Vector{Float64},
                                affine_row::Vector{Float64},
                                affine_col::Vector{Float64})
    -> (mean_error, max_error, per_point_errors)

Compute residual error at control points (for quality assessment).

# Returns
- `mean_error::Float64`: Mean Euclidean distance error
- `max_error::Float64`: Maximum error across all points
- `per_point_errors::Vector{Float64}`: Error for each control point
"""
function compute_tps_residual_error(source_points::Matrix{Float64},
                                     target_points::Matrix{Float64},
                                     weights_row::Vector{Float64},
                                     weights_col::Vector{Float64},
                                     affine_row::Vector{Float64},
                                     affine_col::Vector{Float64})
    n = size(source_points, 1)
    errors = zeros(Float64, n)
    
    for i in 1:n
        # Transform source point
        pred_row, pred_col = apply_tps_transform(
            (source_points[i, 1], source_points[i, 2]),
            source_points,
            weights_row, weights_col,
            affine_row, affine_col
        )
        
        # Compute error
        true_row, true_col = target_points[i, 1], target_points[i, 2]
        error = sqrt((pred_row - true_row)^2 + (pred_col - true_col)^2)
        errors[i] = error
    end
    
    return mean(errors), maximum(errors), errors
end

"""
    estimate_deformation_magnitude(source_points::Matrix{Float64},
                                    target_points::Matrix{Float64})
    -> (mean_displacement, max_displacement)

Estimate magnitude of deformation from control point correspondence.

# Returns
- `mean_displacement::Float64`: Average displacement across control points
- `max_displacement::Float64`: Maximum displacement
"""
function estimate_deformation_magnitude(source_points::Matrix{Float64},
                                         target_points::Matrix{Float64})
    n = size(source_points, 1)
    displacements = zeros(Float64, n)
    
    for i in 1:n
        dx = target_points[i, 1] - source_points[i, 1]
        dy = target_points[i, 2] - source_points[i, 2]
        displacements[i] = sqrt(dx^2 + dy^2)
    end
    
    return mean(displacements), maximum(displacements)
end

println("✅ TPS module loaded: thin plate spline transformation")
