# Load_Sets__Morphology.jl
# Morphological operations for binary image processing

"""
    Load_Sets__Morphology

Morphological image processing operations module.
Provides dilation, erosion, opening, and closing operations for binary masks.

# Operations
- **Dilation**: Expands white regions (fills gaps)
- **Erosion**: Shrinks white regions (removes noise)
- **Closing**: Dilate then erode (connects nearby regions, fills small gaps)
- **Opening**: Erode then dilate (removes small speckles and noise)

# Kernel
All operations use a square kernel with configurable radius.
kernel_size=3 means 7x7 kernel (±3 pixels in each direction)
"""

# ============================================================================
# Dilation
# ============================================================================

"""
    morphological_dilate(mask::BitMatrix, kernel_size::Int) -> BitMatrix

Expand white regions by kernel_size pixels.

# Algorithm
For each black pixel, if any neighbor within kernel_size is white, 
make this pixel white.

# Arguments
- `mask::BitMatrix`: Input binary mask
- `kernel_size::Int`: Kernel radius (0 = no operation)

# Returns
- `BitMatrix`: Dilated mask

# Effect
- Expands white regions
- Fills small gaps
- Connects nearby objects

# Example
```julia
mask = Bool[0 0 1; 0 1 1; 1 1 0]
dilated = morphological_dilate(mask, 1)
# More white pixels than original
```
"""
function morphological_dilate(mask::BitMatrix, kernel_size::Int)
    if kernel_size <= 0
        return mask
    end
    
    h, w = Base.size(mask)
    result = copy(mask)
    
    # For each pixel, if any neighbor within kernel_size is white, make this pixel white
    for i in 1:h
        for j in 1:w
            if !mask[i, j]
                # Check neighbors within kernel radius
                for di in -kernel_size:kernel_size
                    for dj in -kernel_size:kernel_size
                        ni, nj = i + di, j + dj
                        if ni >= 1 && ni <= h && nj >= 1 && nj <= w && mask[ni, nj]
                            result[i, j] = true
                            break
                        end
                    end
                    if result[i, j]
                        break
                    end
                end
            end
        end
    end
    
    return result
end

# ============================================================================
# Erosion
# ============================================================================

"""
    morphological_erode(mask::BitMatrix, kernel_size::Int) -> BitMatrix

Shrink white regions by kernel_size pixels.

# Algorithm
For each white pixel, if any neighbor within kernel_size is black,
make this pixel black.

# Arguments
- `mask::BitMatrix`: Input binary mask
- `kernel_size::Int`: Kernel radius (0 = no operation)

# Returns
- `BitMatrix`: Eroded mask

# Effect
- Shrinks white regions
- Removes thin protrusions
- Eliminates small noise

# Example
```julia
mask = Bool[1 1 1; 1 1 1; 1 1 0]
eroded = morphological_erode(mask, 1)
# Fewer white pixels than original
```
"""
function morphological_erode(mask::BitMatrix, kernel_size::Int)
    if kernel_size <= 0
        return mask
    end
    
    h, w = Base.size(mask)
    result = copy(mask)
    
    # For each white pixel, if any neighbor within kernel_size is black, make this pixel black
    for i in 1:h
        for j in 1:w
            if mask[i, j]
                # Check if all neighbors within kernel radius are white
                all_white = true
                for di in -kernel_size:kernel_size
                    for dj in -kernel_size:kernel_size
                        ni, nj = i + di, j + dj
                        if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                            all_white = false
                            break
                        end
                    end
                    if !all_white
                        break
                    end
                end
                result[i, j] = all_white
            end
        end
    end
    
    return result
end

# ============================================================================
# Closing
# ============================================================================

"""
    morphological_close(mask::BitMatrix, kernel_size::Int) -> BitMatrix

Dilate then erode. Fills small gaps and connects nearby regions.

# Algorithm
1. Dilate with kernel_size
2. Erode with kernel_size

# Arguments
- `mask::BitMatrix`: Input binary mask
- `kernel_size::Int`: Kernel radius (0 = no operation)

# Returns
- `BitMatrix`: Closed mask

# Effect
- Fills small holes
- Connects nearby objects
- Preserves overall shape

# Use Case
Improve connectivity before connected component labeling.

# Example
```julia
# Two nearby regions with gap
mask = Bool[1 1 0 1 1; 1 1 0 1 1]
closed = morphological_close(mask, 1)
# Gap filled, regions connected
```
"""
function morphological_close(mask::BitMatrix, kernel_size::Int)
    if kernel_size <= 0
        return mask
    end
    dilated = morphological_dilate(mask, kernel_size)
    return morphological_erode(dilated, kernel_size)
end

# ============================================================================
# Opening
# ============================================================================

"""
    morphological_open(mask::BitMatrix, kernel_size::Int) -> BitMatrix

Erode then dilate. Removes small noise and speckles.

# Algorithm
1. Erode with kernel_size
2. Dilate with kernel_size

# Arguments
- `mask::BitMatrix`: Input binary mask
- `kernel_size::Int`: Kernel radius (0 = no operation)

# Returns
- `BitMatrix`: Opened mask

# Effect
- Removes small isolated pixels
- Eliminates thin protrusions
- Preserves larger regions

# Use Case
Clean up noise after thresholding.

# Example
```julia
# Large region with small noise pixels
mask = Bool[1 1 1 0 1; 1 1 1 0 0; 1 1 1 0 0]
opened = morphological_open(mask, 1)
# Small isolated pixels removed
```
"""
function morphological_open(mask::BitMatrix, kernel_size::Int)
    if kernel_size <= 0
        return mask
    end
    eroded = morphological_erode(mask, kernel_size)
    return morphological_dilate(eroded, kernel_size)
end

# ============================================================================
# Recommended Usage Pattern
# ============================================================================

"""
# Typical workflow for white region detection:

```julia
# 1. Threshold to create binary mask
mask = (image .>= threshold)

# 2. Close to fill gaps and connect nearby regions
mask = morphological_close(mask, 3)

# 3. Open to remove small noise
mask = morphological_open(mask, 3)

# 4. Now ready for connected component labeling
labeled = label_components(mask)
```

# Kernel Size Guidelines:
- kernel_size = 0: No operation
- kernel_size = 1-2: Minimal gap filling/noise removal
- kernel_size = 3: Recommended default (good balance)
- kernel_size = 5+: Aggressive (may merge separate objects)
"""
