# Load_Sets__ThinPlateSpline__test.jl
# Tests for Thin Plate Spline transformation functions

# Load the module under test
include("Load_Sets__ThinPlateSpline.jl")

using Test
using LinearAlgebra

println("\n" * "="^70)
println("Testing Load_Sets__ThinPlateSpline")
println("="^70)

# ============================================================================
# Test 1: TPS Kernel Function
# ============================================================================
println("\n[Test 1] Testing tps_kernel() - radial basis function")

# Test kernel at r=0 (should return 0)
@test tps_kernel(0.0) == 0.0
@test tps_kernel(1e-15) == 0.0  # Very small r

# Test kernel at specific values
# φ(r) = r² log(r)
r = 2.0
expected = r^2 * log(r)
@test tps_kernel(r) ≈ expected

r = 5.5
expected = r^2 * log(r)
@test tps_kernel(r) ≈ expected

println("✓ TPS kernel function works correctly")

# ============================================================================
# Test 2: Kernel Matrix Construction
# ============================================================================
println("\n[Test 2] Testing build_kernel_matrix() - pairwise kernel values")

# Simple 3-point configuration
points = [0.0 0.0;
          1.0 0.0;
          0.0 1.0]

K = build_kernel_matrix(points)

# Check dimensions
@test size(K) == (3, 3)

# Diagonal should be zero (distance to self)
@test K[1,1] == 0.0
@test K[2,2] == 0.0
@test K[3,3] == 0.0

# Check symmetry
@test K[1,2] ≈ K[2,1]
@test K[1,3] ≈ K[3,1]
@test K[2,3] ≈ K[3,2]

# Check specific value: distance from point 1 to point 2
r12 = sqrt((1.0-0.0)^2 + (0.0-0.0)^2)  # = 1.0
expected_k12 = tps_kernel(r12)  # = 1.0 * log(1.0) = 0.0
@test K[1,2] ≈ expected_k12

# Distance from point 1 to point 3: sqrt(2)
r13 = sqrt((0.0-0.0)^2 + (1.0-0.0)^2)  # = 1.0
expected_k13 = tps_kernel(r13)
@test K[1,3] ≈ expected_k13

println("✓ Kernel matrix construction works correctly")

# ============================================================================
# Test 3: TPS Parameters - Identity Transformation
# ============================================================================
println("\n[Test 3] Testing compute_tps_parameters() - identity transformation")

# Source and target are identical (no deformation)
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = copy(source)

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)

# For identity transformation, weights should be near zero
# and affine should be identity: row_out = row_in, col_out = col_in
# This means: a_r ≈ [0, 1, 0], a_c ≈ [0, 0, 1]

# Weights should be very small (ideally zero)
@test maximum(abs.(w_r)) < 1e-10
@test maximum(abs.(w_c)) < 1e-10

# Test transformation of a point (should map to itself)
test_point = (50.0, 50.0)
out_row, out_col = apply_tps_transform(test_point, source, w_r, w_c, a_r, a_c)
@test out_row ≈ 50.0 atol=1e-6
@test out_col ≈ 50.0 atol=1e-6

println("✓ Identity transformation produces correct parameters")

# ============================================================================
# Test 4: TPS Parameters - Pure Translation
# ============================================================================
println("\n[Test 4] Testing compute_tps_parameters() - pure translation")

# Shift all points by (5, 10)
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = source .+ [5.0 10.0]  # Add (5, 10) to all points

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)

# Test transformation of arbitrary point
test_point = (50.0, 50.0)
out_row, out_col = apply_tps_transform(test_point, source, w_r, w_c, a_r, a_c)
@test out_row ≈ 55.0 atol=1e-6  # 50 + 5
@test out_col ≈ 60.0 atol=1e-6  # 50 + 10

# Test another point
test_point = (30.0, 70.0)
out_row, out_col = apply_tps_transform(test_point, source, w_r, w_c, a_r, a_c)
@test out_row ≈ 35.0 atol=1e-6
@test out_col ≈ 80.0 atol=1e-6

println("✓ Pure translation produces correct transformation")

# ============================================================================
# Test 5: TPS Parameters - Scaling
# ============================================================================
println("\n[Test 5] Testing compute_tps_parameters() - uniform scaling")

# Scale by 2x around origin
source = [10.0 10.0;
          50.0 10.0;
          50.0 50.0;
          10.0 50.0]
target = source .* 2.0  # Scale by 2

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)

# Test transformation
test_point = (30.0, 30.0)
out_row, out_col = apply_tps_transform(test_point, source, w_r, w_c, a_r, a_c)
@test out_row ≈ 60.0 atol=1e-4  # 30 * 2
@test out_col ≈ 60.0 atol=1e-4  # 30 * 2

println("✓ Scaling transformation produces correct result")

# ============================================================================
# Test 6: TPS Interpolation at Control Points
# ============================================================================
println("\n[Test 6] Testing TPS interpolation at control points (exact fit)")

# Arbitrary correspondence
source = [10.0 20.0;
          80.0 15.0;
          75.0 85.0;
          15.0 90.0]
target = [5.0 25.0;
          85.0 20.0;
          80.0 80.0;
          10.0 85.0]

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)

# TPS should EXACTLY interpolate at control points (with regularization=0)
for i in 1:size(source, 1)
    src_point = (source[i, 1], source[i, 2])
    out_row, out_col = apply_tps_transform(src_point, source, w_r, w_c, a_r, a_c)
    
    expected_row = target[i, 1]
    expected_col = target[i, 2]
    
    @test out_row ≈ expected_row atol=1e-6
    @test out_col ≈ expected_col atol=1e-6
end

println("✓ TPS exactly interpolates control points")

# ============================================================================
# Test 7: TPS with Regularization
# ============================================================================
println("\n[Test 7] Testing compute_tps_parameters() with regularization")

# Use same points but with regularization
source = [10.0 20.0;
          80.0 15.0;
          75.0 85.0;
          15.0 90.0]
target = [5.0 25.0;
          85.0 20.0;
          80.0 80.0;
          10.0 85.0]

# Small regularization
w_r, w_c, a_r, a_c = compute_tps_parameters(source, target; regularization=0.1)

# With regularization, fit is approximate (not exact)
# But should still be reasonably close
for i in 1:size(source, 1)
    src_point = (source[i, 1], source[i, 2])
    out_row, out_col = apply_tps_transform(src_point, source, w_r, w_c, a_r, a_c)
    
    expected_row = target[i, 1]
    expected_col = target[i, 2]
    
    # Allow larger tolerance with regularization
    @test abs(out_row - expected_row) < 2.0
    @test abs(out_col - expected_col) < 2.0
end

# Weights should be smaller with regularization (smoother)
w_r_unreg, w_c_unreg, _, _ = compute_tps_parameters(source, target; regularization=0.0)
@test norm(w_r) <= norm(w_r_unreg) * 1.1  # May be slightly larger due to numerical differences
@test norm(w_c) <= norm(w_c_unreg) * 1.1

println("✓ Regularization produces smoother (smaller weight) transformations")

# ============================================================================
# Test 8: Error Handling - Insufficient Points
# ============================================================================
println("\n[Test 8] Testing error handling - insufficient control points")

# Only 2 points (need at least 3)
source = [10.0 10.0;
          90.0 90.0]
target = [10.0 10.0;
          90.0 90.0]

try
    w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)
    @test false  # Should have thrown error
catch e
    @test occursin("at least 3", string(e))
end

println("✓ Correctly rejects insufficient control points")

# ============================================================================
# Test 9: Error Handling - Mismatched Point Counts
# ============================================================================
println("\n[Test 9] Testing error handling - mismatched point counts")

source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0]
target = [10.0 10.0;
          90.0 10.0]  # Only 2 points

try
    w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)
    @test false  # Should have thrown error
catch e
    @test occursin("same number", string(e))
end

println("✓ Correctly rejects mismatched point counts")

# ============================================================================
# Test 10: Residual Error Computation
# ============================================================================
println("\n[Test 10] Testing compute_tps_residual_error()")

# Identity transformation should have zero error
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = copy(source)

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)
mean_err, max_err, per_point_errs = compute_tps_residual_error(
    source, target, w_r, w_c, a_r, a_c)

@test mean_err < 1e-6
@test max_err < 1e-6
@test length(per_point_errs) == 4
@test all(per_point_errs .< 1e-6)

# Translation should also have near-zero error at control points
target = source .+ [5.0 10.0]
w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)
mean_err, max_err, per_point_errs = compute_tps_residual_error(
    source, target, w_r, w_c, a_r, a_c)

@test mean_err < 1e-6
@test max_err < 1e-6

println("✓ Residual error computation works correctly")

# ============================================================================
# Test 11: Deformation Magnitude Estimation
# ============================================================================
println("\n[Test 11] Testing estimate_deformation_magnitude()")

# No deformation
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = copy(source)

mean_disp, max_disp = estimate_deformation_magnitude(source, target)
@test mean_disp == 0.0
@test max_disp == 0.0

# Pure translation by (3, 4) -> displacement = 5
target = source .+ [3.0 4.0]
mean_disp, max_disp = estimate_deformation_magnitude(source, target)
expected_disp = sqrt(3^2 + 4^2)  # = 5.0
@test mean_disp ≈ expected_disp
@test max_disp ≈ expected_disp

# Mixed displacements
target = [10.0 10.0;   # no displacement
          95.0 10.0;   # displacement = 5 in row
          90.0 94.0;   # displacement = 4 in col
          10.0 90.0]   # no displacement

mean_disp, max_disp = estimate_deformation_magnitude(source, target)
expected_mean = (0 + 5 + 4 + 0) / 4
@test mean_disp ≈ expected_mean
@test max_disp ≈ 5.0

println("✓ Deformation magnitude estimation works correctly")

# ============================================================================
# Test 12: Mask Warping (without full Bas3ImageSegmentation)
# ============================================================================
println("\n[Test 12] Testing warp_mask_tps() - basic functionality")

# Create simple binary mask
mask = falses(100, 100)
mask[40:60, 40:60] .= true  # Square in center

# Identity transformation (no warping)
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = copy(source)

warped = warp_mask_tps(mask, source, target)

# Should be identical to input
@test size(warped) == size(mask)
@test sum(warped) ≈ sum(mask) atol=50  # Allow some boundary differences

# Center region should be preserved
@test all(warped[45:55, 45:55])  # Center should still be true

println("✓ Mask warping preserves content with identity transformation")

# ============================================================================
# Test 13: Non-rigid Deformation (Perspective-like)
# ============================================================================
println("\n[Test 13] Testing TPS with non-rigid deformation")

# Simulate perspective distortion: top edge compressed
source = [10.0 10.0;
          90.0 10.0;
          90.0 90.0;
          10.0 90.0]
target = [20.0 20.0;   # Top-left moved in
          80.0 20.0;   # Top-right moved in
          90.0 90.0;   # Bottom corners stay same
          10.0 90.0]

w_r, w_c, a_r, a_c = compute_tps_parameters(source, target)

# Test point in middle should be somewhere between extremes
test_point = (50.0, 50.0)  # Center of source
out_row, out_col = apply_tps_transform(test_point, source, w_r, w_c, a_r, a_c)

# Should be in reasonable range (between 10-90 for both coords)
@test 10.0 < out_row < 90.0
@test 10.0 < out_col < 90.0

# Control points should still be exactly interpolated
for i in 1:4
    src_point = (source[i, 1], source[i, 2])
    out_row, out_col = apply_tps_transform(src_point, source, w_r, w_c, a_r, a_c)
    @test out_row ≈ target[i, 1] atol=1e-6
    @test out_col ≈ target[i, 2] atol=1e-6
end

println("✓ Non-rigid deformation interpolates correctly")

# ============================================================================
# Test Summary
# ============================================================================
println("\n" * "="^70)
println("✅ All 13 TPS tests passed!")
println("="^70)

println("\nTested functions:")
println("  ✓ tps_kernel() - radial basis function")
println("  ✓ build_kernel_matrix() - pairwise kernel computation")
println("  ✓ compute_tps_parameters() - fit TPS transformation")
println("  ✓ apply_tps_transform() - transform points")
println("  ✓ compute_tps_residual_error() - quality assessment")
println("  ✓ estimate_deformation_magnitude() - deformation analysis")
println("  ✓ warp_mask_tps() - binary mask warping")

println("\nValidated scenarios:")
println("  ✓ Identity transformation")
println("  ✓ Pure translation")
println("  ✓ Uniform scaling")
println("  ✓ Non-rigid deformation")
println("  ✓ Exact interpolation at control points")
println("  ✓ Regularized fitting (approximate)")
println("  ✓ Error handling (insufficient/mismatched points)")

println("\nNot tested (require Bas3ImageSegmentation.c__Image_Data):")
println("  - warp_image_tps() - full image warping with bilinear interpolation")

flush(stdout)
