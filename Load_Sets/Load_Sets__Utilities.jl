# Load_Sets__Utilities.jl
# Helper utility functions for image processing and coordinate transformations

"""
    Load_Sets__Utilities

Utility functions module for coordinate transformations, geometry, and PCA.
"""

# ============================================================================
# Coordinate Transformation
# ============================================================================

"""
    axis_to_pixel(point_axis, img_height, img_width) -> (Int, Int)

Convert axis coordinates to image pixel coordinates.

Input axis shows rotr90(image), so need to reverse transform.

# Transform Details
- Original image: H×W (height × width)
- After rotr90: W×H (cols become rows, rows become cols)
- Forward: rotated[orig_col, H - orig_row + 1] = original[orig_row, orig_col]
- Inverse:
  - orig_row = H - rot_col + 1
  - orig_col = rot_row

# Arguments
- `point_axis`: (rot_row, rot_col) in rotated/axis space
- `img_height`: Original image height
- `img_width`: Original image width

# Returns
- `(orig_row, orig_col)`: Coordinates in original image space
"""
function axis_to_pixel(point_axis, img_height, img_width)
    rot_row = round(Int, point_axis[1])
    rot_col = round(Int, point_axis[2])
    
    # Convert to original image coordinates
    orig_row = img_height - rot_col + 1
    orig_col = rot_row
    
    return (orig_row, orig_col)
end

# ============================================================================
# Geometry Utilities
# ============================================================================

"""
    make_rectangle(c1, c2) -> Vector{Point2f}

Create rectangle polygon from two opposite corners.

# Arguments
- `c1`: First corner (x, y)
- `c2`: Opposite corner (x, y)

# Returns
- `Vector{Point2f}`: 5 points forming closed rectangle (last = first)
"""
function make_rectangle(c1, c2)
    x_min, x_max = minmax(c1[1], c2[1])
    y_min, y_max = minmax(c1[2], c2[2])
    return Bas3GLMakie.GLMakie.Point2f[
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min)  # Close the loop
    ]
end
