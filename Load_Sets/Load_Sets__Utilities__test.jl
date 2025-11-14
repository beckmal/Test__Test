# test_utilities.jl  
# Tests for Load_Sets__Utilities.jl
println("="^60)
println("Testing Load_Sets__Utilities.jl")
println("="^60); flush(stdout)

# Load module
include("Load_Sets__Utilities.jl")
println("Module loaded"); flush(stdout)

# Test counters
tests_run = 0
tests_passed = 0

# ============================================================================
# Test 1: axis_to_pixel coordinate transformation
# ============================================================================

println("\nTest 1: axis_to_pixel transformations"); flush(stdout)

# Test 1.1: Basic transformation
# For a 100x200 image (height x width), test corner transformations
img_h, img_w = 100, 200

# Top-left of rotated image -> where in original?
point1 = (1.0, 1.0)  # (rot_row, rot_col)
result1 = axis_to_pixel(point1, img_h, img_w)
# orig_row = img_h - rot_col + 1 = 100 - 1 + 1 = 100
# orig_col = rot_row = 1
tests_run += 1
if result1 == (100, 1)
    tests_passed += 1
    println("  ✓ Top-left corner transforms correctly")
else
    println("  ✗ Top-left corner: expected (100, 1), got $result1")
end
flush(stdout)

# Test 1.2: Bottom-right of rotated image
point2 = (Float64(img_w), Float64(img_h))  # (200, 100)
result2 = axis_to_pixel(point2, img_h, img_w)
# orig_row = 100 - 100 + 1 = 1
# orig_col = 200
tests_run += 1
if result2 == (1, 200)
    tests_passed += 1
    println("  ✓ Bottom-right corner transforms correctly")
else
    println("  ✗ Bottom-right corner: expected (1, 200), got $result2")
end
flush(stdout)

# Test 1.3: Center point
point3 = (100.0, 50.0)
result3 = axis_to_pixel(point3, img_h, img_w)
# orig_row = 100 - 50 + 1 = 51
# orig_col = 100
tests_run += 1
if result3 == (51, 100)
    tests_passed += 1
    println("  ✓ Center point transforms correctly")
else
    println("  ✗ Center point: expected (51, 100), got $result3")
end
flush(stdout)

# Test 1.4: Rounding behavior
point4 = (10.7, 20.3)
result4 = axis_to_pixel(point4, img_h, img_w)
# rot_row = round(10.7) = 11, rot_col = round(20.3) = 20
# orig_row = 100 - 20 + 1 = 81
# orig_col = 11
tests_run += 1
if result4 == (81, 11)
    tests_passed += 1
    println("  ✓ Rounding works correctly")
else
    println("  ✗ Rounding: expected (81, 11), got $result4")
end
flush(stdout)

# Test 1.5: Square image (special case)
point5 = (50.0, 50.0)
result5 = axis_to_pixel(point5, 100, 100)  # 100x100 square
# orig_row = 100 - 50 + 1 = 51
# orig_col = 50
tests_run += 1
if result5 == (51, 50)
    tests_passed += 1
    println("  ✓ Square image transforms correctly")
else
    println("  ✗ Square image: expected (51, 50), got $result5")
end
flush(stdout)

# ============================================================================
# Test 2: make_rectangle (if Bas3GLMakie available)
# ============================================================================

println("\nTest 2: make_rectangle (skipped - requires Bas3GLMakie)"); flush(stdout)
# We skip this test as it requires external package Bas3GLMakie
# In actual usage, this function creates a polygon from corners

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^60)
println("Tests: $tests_passed/$tests_run passed")
println("="^60)
flush(stdout)

if tests_passed == tests_run
    println("✓ All tests passed!")
else
    println("✗ Some tests failed")
end
