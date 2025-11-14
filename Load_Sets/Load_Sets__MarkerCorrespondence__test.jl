# Load_Sets__MarkerCorrespondence__test.jl
# Test suite for marker detection and correspondence establishment

using Statistics
using LinearAlgebra

println("\n" * "="^70)
println("Testing Load_Sets__MarkerCorrespondence.jl")
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
include("Load_Sets__MarkerCorrespondence.jl")

println("Modules loaded successfully")
flush(stdout)

# ============================================================================
# Helper Functions
# ============================================================================

struct TestRGBImage
    data::Array{Float64, 3}
end

# Add data() method for compatibility with Bas3ImageSegmentation
Bas3ImageSegmentation.data(img::TestRGBImage) = img.data

function create_blank_image(height, width)
    data = zeros(Float64, height, width, 3)
    return TestRGBImage(data)
end

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
# Test detect_calibration_markers()
# ============================================================================

println("\n[Test 1/8] detect_calibration_markers: Single marker")
flush(stdout)

img1 = create_blank_image(200, 200)
# Create elongated marker (aspect ratio ~5)
add_white_rectangle!(img1, 50, 70, 30, 130)  # 21×101

markers1 = detect_calibration_markers(img1; 
    threshold=0.5, kernel_size=0, min_area=1000,
    min_aspect_ratio=3.0, max_aspect_ratio=7.0)

tests_run += 1
if length(markers1) == 1
    m = markers1[1]
    tests_passed += 1
    println("  ✓ Single marker detected")
    println("    Centroid: $(m.centroid)")
    println("    Size: $(m.size) pixels")
    println("    Aspect ratio: $(m.aspect_ratio)")
    println("    Density: $(m.density)")
else
    println("  ✗ FAILED: Expected 1 marker, got $(length(markers1))")
end
flush(stdout)

println("\n[Test 2/8] detect_calibration_markers: Multiple markers")
flush(stdout)

img2 = create_blank_image(300, 300)
# Create 4 elongated markers in corners (5:1 aspect ratio, horizontal)
add_white_rectangle!(img2, 20, 40, 20, 120)     # Top-left
add_white_rectangle!(img2, 20, 40, 180, 280)    # Top-right
add_white_rectangle!(img2, 260, 280, 20, 120)   # Bottom-left
add_white_rectangle!(img2, 260, 280, 180, 280)  # Bottom-right

markers2 = detect_calibration_markers(img2; 
    threshold=0.5, kernel_size=0, min_area=1000,
    min_aspect_ratio=3.0, max_aspect_ratio=7.0)

tests_run += 1
if length(markers2) == 4
    tests_passed += 1
    println("  ✓ Detected $(length(markers2)) markers")
    for (i, m) in enumerate(markers2)
        println("    Marker $i: centroid=$(m.centroid), aspect=$(round(m.aspect_ratio, digits=2))")
    end
else
    println("  ✗ FAILED: Expected 4 markers, got $(length(markers2))")
end
flush(stdout)

println("\n[Test 3/8] detect_calibration_markers: Aspect ratio filtering")
flush(stdout)

img3 = create_blank_image(300, 300)
# Square marker (aspect ~1, should be filtered out)
add_white_rectangle!(img3, 20, 60, 20, 60)      
# Elongated marker (aspect ~5, should be detected)
add_white_rectangle!(img3, 100, 120, 100, 200)  

markers3 = detect_calibration_markers(img3; 
    threshold=0.5, kernel_size=0, min_area=1000,
    min_aspect_ratio=3.0, max_aspect_ratio=7.0)

tests_run += 1
if length(markers3) == 1 && markers3[1].aspect_ratio > 3.0
    tests_passed += 1
    println("  ✓ Aspect ratio filter works")
    println("    Detected: $(length(markers3)) markers (filtered out square)")
    println("    Aspect ratio: $(markers3[1].aspect_ratio)")
else
    println("  ✗ FAILED: Aspect ratio filtering")
end
flush(stdout)

# ============================================================================
# Test define_canonical_positions()
# ============================================================================

println("\n[Test 4/8] define_canonical_positions: corners_4 mode")
flush(stdout)

# Create 4 test markers (using previous detection)
if length(markers2) == 4
    canonical4 = define_canonical_positions(markers2, :corners_4;
        image_size=(500, 500), margin=20.0)
    
    tests_run += 1
    expected_corners = [
        [20.0, 20.0],           # Top-left
        [20.0, 480.0],          # Top-right
        [480.0, 480.0],         # Bottom-right
        [480.0, 20.0]           # Bottom-left
    ]
    
    # Check shape
    if Base.size(canonical4) == (4, 2)
        # Check corners are correct
        all_match = true
        for i in 1:4
            if !(canonical4[i, :] ≈ expected_corners[i])
                all_match = false
                break
            end
        end
        
        if all_match
            tests_passed += 1
            println("  ✓ corners_4 mode works")
            println("    Positions:")
            for i in 1:4
                println("      Corner $i: $(canonical4[i, :])")
            end
        else
            println("  ✗ FAILED: Corner positions don't match")
        end
    else
        println("  ✗ FAILED: Wrong shape $(Base.size(canonical4))")
    end
else
    tests_run += 1
    println("  ⊘ SKIPPED: Need 4 markers from Test 2")
end
flush(stdout)

println("\n[Test 5/8] define_canonical_positions: grid_2x2 mode")
flush(stdout)

if length(markers2) == 4
    canonical_grid = define_canonical_positions(markers2, :grid_2x2;
        image_size=(400, 400), margin=50.0)
    
    tests_run += 1
    if Base.size(canonical_grid) == (4, 2)
        # Check that all positions use margin=50 and grid spacing
        grid_spacing = 400 - 2*50  # 300
        
        # First marker should be at (50, 50)
        if canonical_grid[1, 1] == 50.0 && canonical_grid[1, 2] == 50.0
            tests_passed += 1
            println("  ✓ grid_2x2 mode works")
            println("    Grid spacing: $grid_spacing")
            println("    Positions:")
            for i in 1:4
                println("      Marker $i: $(canonical_grid[i, :])")
            end
        else
            println("  ✗ FAILED: Grid positions incorrect")
        end
    else
        println("  ✗ FAILED: Wrong shape")
    end
else
    tests_run += 1
    println("  ⊘ SKIPPED: Need 4 markers")
end
flush(stdout)

# ============================================================================
# Test establish_correspondence()
# ============================================================================

println("\n[Test 6/8] establish_correspondence: spatial_order method")
flush(stdout)

# Create simple test case with known positions
test_markers = [
    MarkerInfo((100.0, 100.0), Float64[], falses(10,10), 1000, 0.0, 5.0, 0.9),
    MarkerInfo((100.0, 200.0), Float64[], falses(10,10), 1000, 0.0, 5.0, 0.9),
    MarkerInfo((200.0, 100.0), Float64[], falses(10,10), 1000, 0.0, 5.0, 0.9),
    MarkerInfo((200.0, 200.0), Float64[], falses(10,10), 1000, 0.0, 5.0, 0.9),
]

test_canonical = Float64[
    50.0  50.0;
    50.0  250.0;
    250.0 50.0;
    250.0 250.0;
]

source, target = establish_correspondence(test_markers, test_canonical; 
    method=:spatial_order)

tests_run += 1
if Base.size(source) == (4, 2) && Base.size(target) == (4, 2)
    tests_passed += 1
    println("  ✓ spatial_order correspondence works")
    println("    Source points:")
    for i in 1:4
        println("      $(source[i, :]) → $(target[i, :])")
    end
else
    println("  ✗ FAILED: Wrong output shape")
end
flush(stdout)

println("\n[Test 7/8] establish_correspondence: nearest_neighbor method")
flush(stdout)

source_nn, target_nn = establish_correspondence(test_markers, test_canonical; 
    method=:nearest_neighbor)

tests_run += 1
if Base.size(source_nn) == (4, 2) && Base.size(target_nn) == (4, 2)
    # Verify that each source is matched to a reasonable target
    all_reasonable = true
    for i in 1:4
        dist = sqrt(sum((source_nn[i, :] .- target_nn[i, :]).^2))
        if dist > 200.0  # Should be reasonably close
            all_reasonable = false
            break
        end
    end
    
    if all_reasonable
        tests_passed += 1
        println("  ✓ nearest_neighbor correspondence works")
        println("    Matches:")
        for i in 1:4
            dist = sqrt(sum((source_nn[i, :] .- target_nn[i, :]).^2))
            println("      $(source_nn[i, :]) → $(target_nn[i, :]) (dist=$(round(dist, digits=1)))")
        end
    else
        println("  ✗ FAILED: Unreasonable matches")
    end
else
    println("  ✗ FAILED: Wrong output shape")
end
flush(stdout)

println("\n[Test 8/8] MarkerInfo structure validation")
flush(stdout)

# Test that MarkerInfo struct works correctly
test_marker = MarkerInfo(
    (150.0, 200.0),           # centroid
    [10.0, 10.0, 20.0, 10.0, 20.0, 20.0, 10.0, 20.0],  # corners
    falses(30, 30),            # mask
    2000,                      # size
    0.5,                       # angle
    4.8,                       # aspect_ratio
    0.95                       # density
)

tests_run += 1
if test_marker.centroid == (150.0, 200.0) && 
   test_marker.size == 2000 && 
   test_marker.aspect_ratio == 4.8
    tests_passed += 1
    println("  ✓ MarkerInfo structure validated")
    println("    Centroid: $(test_marker.centroid)")
    println("    Size: $(test_marker.size)")
    println("    Aspect: $(test_marker.aspect_ratio)")
    println("    Density: $(test_marker.density)")
else
    println("  ✗ FAILED: MarkerInfo structure")
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
