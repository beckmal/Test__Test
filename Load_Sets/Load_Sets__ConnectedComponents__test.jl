# Load_Sets__ConnectedComponents__test.jl
# Test suite for connected component analysis with PCA-based bounding boxes

using Statistics
using LinearAlgebra

println("\n" * "="^70)
println("Testing Load_Sets__ConnectedComponents.jl")
println("="^70)
flush(stdout)

# ============================================================================
# Load Real Bas3ImageSegmentation Package
# ============================================================================

println("Loading real Bas3ImageSegmentation package (may take ~25s)...")
flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation

println("✓ Packages loaded")
flush(stdout)

# ============================================================================
# Load Modules
# ============================================================================

include("Load_Sets__Morphology.jl")
include("Load_Sets__ConnectedComponents.jl")

println("Modules loaded successfully")
flush(stdout)

# ============================================================================
# Helper Functions for Creating Synthetic Test Images
# ============================================================================

"""
Create a simple RGB image wrapper that mimics Bas3ImageSegmentation structure.
"""
struct TestRGBImage
    data::Array{Float64, 3}  # (height, width, 3)
end

# Add data() method for compatibility with Bas3ImageSegmentation
Bas3ImageSegmentation.data(img::TestRGBImage) = img.data

"""
Create a blank RGB image (black background).
"""
function create_blank_image(height, width)
    data = zeros(Float64, height, width, 3)
    return TestRGBImage(data)
end

"""
Create a white rectangle in an RGB image.
"""
function add_white_rectangle!(img::TestRGBImage, r_min, r_max, c_min, c_max; intensity=1.0)
    h, w = Base.size(img.data, 1), Base.size(img.data, 2)
    r_min = max(1, r_min)
    r_max = min(h, r_max)
    c_min = max(1, c_min)
    c_max = min(w, c_max)
    
    img.data[r_min:r_max, c_min:c_max, 1] .= intensity
    img.data[r_min:r_max, c_min:c_max, 2] .= intensity
    img.data[r_min:r_max, c_min:c_max, 3] .= intensity
end

# Test counter
tests_run = 0
tests_passed = 0

# ============================================================================
# Test extract_contours()
# ============================================================================

println("\n[Test 1/10] extract_contours: Simple square")
flush(stdout)

# 5x5 filled square
mask = falses(10, 10)
mask[3:7, 3:7] .= true

contour = extract_contours(mask)

# Border pixels: perimeter of 5x5 square = 16 boundary pixels
tests_run += 1
if length(contour) == 16
    tests_passed += 1
    println("  ✓ Square contour: $(length(contour)) boundary pixels")
else
    println("  ✗ FAILED: Expected 16 boundary pixels, got $(length(contour))")
end
flush(stdout)

println("\n[Test 2/10] extract_contours: Single pixel")
flush(stdout)

mask2 = falses(5, 5)
mask2[3, 3] = true

contour2 = extract_contours(mask2)

tests_run += 1
if length(contour2) == 1 && contour2[1] == (3, 3)
    tests_passed += 1
    println("  ✓ Single pixel contour: $(length(contour2)) pixel")
else
    println("  ✗ FAILED: Single pixel test")
end
flush(stdout)

println("\n[Test 3/10] extract_contours: Empty mask")
flush(stdout)

mask3 = falses(10, 10)
contour3 = extract_contours(mask3)

tests_run += 1
if length(contour3) == 0
    tests_passed += 1
    println("  ✓ Empty mask contour: $(length(contour3)) pixels")
else
    println("  ✗ FAILED: Empty mask should have 0 contour pixels")
end
flush(stdout)

# ============================================================================
# Test find_connected_components()
# ============================================================================

println("\n[Test 4/10] find_connected_components: Single white rectangle")
flush(stdout)

img = create_blank_image(100, 100)
add_white_rectangle!(img, 20, 40, 30, 60)  # 21x31 rectangle

labeled, n_comp, info = find_connected_components(img; 
    threshold=0.5, kernel_size=0, min_area=100)

tests_run += 1
if n_comp == 1 && length(info) == 1 && info[1].size == 21 * 31
    tests_passed += 1
    println("  ✓ Single component detected")
    println("    Size: $(info[1].size) pixels")
    println("    Centroid: $(info[1].centroid)")
    println("    BBox: $(info[1].bbox)")
else
    println("  ✗ FAILED: n_comp=$n_comp, expected 1")
end
flush(stdout)

println("\n[Test 5/10] find_connected_components: Multiple components")
flush(stdout)

img2 = create_blank_image(100, 100)
add_white_rectangle!(img2, 10, 20, 10, 20)   # Component 1
add_white_rectangle!(img2, 40, 50, 40, 50)   # Component 2
add_white_rectangle!(img2, 70, 80, 70, 80)   # Component 3

labeled2, n_comp2, info2 = find_connected_components(img2; 
    threshold=0.5, kernel_size=0, min_area=50)

tests_run += 1
if n_comp2 == 3 && length(info2) == 3
    tests_passed += 1
    println("  ✓ Detected $(n_comp2) components")
    for (i, comp) in enumerate(info2)
        println("    Component $i: size=$(comp.size), centroid=$(comp.centroid)")
    end
else
    println("  ✗ FAILED: Expected 3 components, got $n_comp2")
end
flush(stdout)

println("\n[Test 6/10] find_connected_components: Min area filtering")
flush(stdout)

img3 = create_blank_image(100, 100)
add_white_rectangle!(img3, 10, 30, 10, 30)   # 21x21 = 441 pixels (large)
add_white_rectangle!(img3, 50, 55, 50, 55)   # 6x6 = 36 pixels (small)

# With min_area=100, should only get the large component
labeled3a, n_comp3a, info3a = find_connected_components(img3; 
    threshold=0.5, kernel_size=0, min_area=100)

# With min_area=30, should get both
labeled3b, n_comp3b, info3b = find_connected_components(img3; 
    threshold=0.5, kernel_size=0, min_area=30)

tests_run += 1
if n_comp3a == 1 && n_comp3b == 2
    tests_passed += 1
    println("  ✓ Min area filtering works")
    println("    min_area=100: $(n_comp3a) components")
    println("    min_area=30: $(n_comp3b) components")
else
    println("  ✗ FAILED: min_area filtering (got $n_comp3a and $n_comp3b)")
end
flush(stdout)

# ============================================================================
# Test extract_white_mask() - Core PCA-based selection
# ============================================================================

println("\n[Test 7/10] extract_white_mask: Basic white region detection")
flush(stdout)

img4 = create_blank_image(100, 100)
add_white_rectangle!(img4, 20, 60, 30, 70)  # 41x41 rectangle

mask4, size4, pct4, n_comp4, density4, corners4, angle4, aspect4 = 
    extract_white_mask(img4; threshold=0.5, kernel_size=0, min_component_area=100)

tests_run += 1
if sum(mask4) == 41 * 41 && n_comp4 == 1 && density4 > 0.9 && length(corners4) == 8
    tests_passed += 1
    println("  ✓ White region detected")
    println("    Size: $size4 pixels")
    println("    Density: $density4")
    println("    Aspect ratio: $aspect4")
else
    println("  ✗ FAILED: Basic detection (sum=$(sum(mask4)), density=$density4)")
end
flush(stdout)

println("\n[Test 8/10] extract_white_mask: Component selection by density")
flush(stdout)

img5 = create_blank_image(100, 100)

# Create sparse component (low density) - rectangle with holes
add_white_rectangle!(img5, 15, 35, 15, 35)  # 21x21 base
# Punch holes in it to reduce density
for i in 17:2:33
    for j in 17:2:33
        img5.data[i, j, :] .= 0.0
    end
end

# Create dense component (high density) - solid rectangle
add_white_rectangle!(img5, 60, 80, 60, 80)  # 21x21 = 441 pixels (solid)

# With aspect_ratio_weight=0.0, should select densest component (solid rectangle)
mask5, size5, pct5, n_comp5, density5, corners5, angle5, aspect5 = 
    extract_white_mask(img5; threshold=0.5, kernel_size=0, 
                      min_component_area=100, aspect_ratio_weight=0.0)

# The dense component should be selected
tests_run += 1
if size5 == 441 && density5 > 0.9
    tests_passed += 1
    println("  ✓ Densest component selected")
    println("    Total components: $n_comp5")
    println("    Selected size: $size5")
    println("    Selected density: $density5")
else
    println("  ✗ FAILED: Density selection (n_comp=$n_comp5, size=$size5, density=$density5)")
end
flush(stdout)

println("\n[Test 9/10] extract_white_mask: Aspect ratio preference")
flush(stdout)

img6 = create_blank_image(200, 200)

# Square component (aspect ratio ~1.0)
add_white_rectangle!(img6, 20, 60, 20, 60)  # 41x41

# Elongated component (aspect ratio ~5.0)
add_white_rectangle!(img6, 100, 120, 50, 150)  # 21x101 ≈ 1:5

# With high aspect_ratio_weight and preferred=5.0, should select elongated
mask6, size6, pct6, n_comp6, density6, corners6, angle6, aspect6 = 
    extract_white_mask(img6; threshold=0.5, kernel_size=0, 
                      min_component_area=100, 
                      preferred_aspect_ratio=5.0,
                      aspect_ratio_weight=0.9)

tests_run += 1
if n_comp6 == 2 && aspect6 > 4.0
    tests_passed += 1
    println("  ✓ Aspect ratio preference works")
    println("    Total components: $n_comp6")
    println("    Selected aspect ratio: $aspect6")
else
    println("  ✗ FAILED: Aspect ratio selection (aspect=$aspect6)")
end
flush(stdout)

println("\n[Test 10/10] extract_white_mask: Region restriction")
flush(stdout)

img7 = create_blank_image(100, 100)
add_white_rectangle!(img7, 10, 30, 10, 30)   # Outside region
add_white_rectangle!(img7, 60, 80, 60, 80)   # Inside region

# Restrict search to bottom-right quadrant
region = (50, 100, 50, 100)

mask7, size7, pct7, n_comp7, density7, corners7, angle7, aspect7 = 
    extract_white_mask(img7; threshold=0.5, kernel_size=0, 
                      min_component_area=100, region=region)

# Check that detected component is in the restricted region
detected_pixels = findall(mask7)
all_in_region = all(p[1] >= 50 && p[2] >= 50 for p in detected_pixels)

tests_run += 1
if n_comp7 == 1 && size7 == 21 * 21 && all_in_region
    tests_passed += 1
    println("  ✓ Region restriction works")
    println("    Detected components in region: $n_comp7")
    println("    Component size: $size7")
else
    println("  ✗ FAILED: Region restriction (n_comp=$n_comp7, size=$size7)")
end
flush(stdout)

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^70)
println("Test Results: $tests_passed / $tests_run tests passed")
if tests_passed == tests_run
    println("All tests completed successfully!")
else
    println("Some tests failed!")
end
println("="^70)
println()
flush(stdout)
