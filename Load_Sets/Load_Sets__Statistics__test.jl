# Load_Sets__Statistics__test.jl
# Test suite for statistical computation functions

using Test

# Include the Statistics module
include("Load_Sets__Statistics.jl")

println("\n" * "="^70)
println("Testing Load_Sets__Statistics.jl")
println("="^70)
flush(stdout)

# ============================================================================
# Test compute_skewness()
# ============================================================================

println("\n[Test 1/12] compute_skewness: Symmetric distribution (should be ~0)")
flush(stdout)
@testset "Skewness: Symmetric" begin
    # Perfectly symmetric around mean=5
    symmetric_data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]
    skew = compute_skewness(symmetric_data)
    @test abs(skew) < 0.01  # Should be close to zero
    println("  ✓ Symmetric data skewness: $skew (expected ~0)")
end
flush(stdout)

println("\n[Test 2/12] compute_skewness: Right-skewed distribution (positive)")
flush(stdout)
@testset "Skewness: Right-skewed" begin
    # Long tail on the right (many small values, few large)
    right_skewed = [1.0, 1.0, 1.0, 2.0, 2.0, 3.0, 10.0, 20.0]
    skew = compute_skewness(right_skewed)
    @test skew > 0.5  # Should be positive
    println("  ✓ Right-skewed data skewness: $skew (expected > 0)")
end
flush(stdout)

println("\n[Test 3/12] compute_skewness: Left-skewed distribution (negative)")
flush(stdout)
@testset "Skewness: Left-skewed" begin
    # Long tail on the left (many large values, few small)
    left_skewed = [1.0, 5.0, 10.0, 10.0, 11.0, 11.0, 11.0, 12.0]
    skew = compute_skewness(left_skewed)
    @test skew < -0.5  # Should be negative
    println("  ✓ Left-skewed data skewness: $skew (expected < 0)")
end
flush(stdout)

println("\n[Test 4/12] compute_skewness: All identical values (should be 0)")
flush(stdout)
@testset "Skewness: Constant" begin
    # Standard deviation is zero
    constant_data = [5.0, 5.0, 5.0, 5.0, 5.0]
    skew = compute_skewness(constant_data)
    @test skew == 0.0
    println("  ✓ Constant data skewness: $skew (expected 0)")
end
flush(stdout)

println("\n[Test 5/12] compute_skewness: Empty vector (edge case)")
flush(stdout)
@testset "Skewness: Empty" begin
    empty_data = Float64[]
    skew = compute_skewness(empty_data)
    @test skew == 0.0
    println("  ✓ Empty data skewness: $skew (expected 0)")
end
flush(stdout)

println("\n[Test 6/12] compute_skewness: Single value (edge case)")
flush(stdout)
@testset "Skewness: Single value" begin
    single_value = [42.0]
    skew = compute_skewness(single_value)
    @test skew == 0.0 || isnan(skew)  # Can be 0 or NaN depending on implementation
    println("  ✓ Single value skewness: $skew")
end
flush(stdout)

# ============================================================================
# Test find_outliers()
# ============================================================================

println("\n[Test 7/12] find_outliers: No outliers in normal data")
flush(stdout)
@testset "Outliers: None" begin
    # Well-behaved data with no outliers
    normal_data = [10.0, 12.0, 11.0, 13.0, 12.5, 11.5, 10.5, 12.0]
    outlier_mask, outlier_pct = find_outliers(normal_data)
    @test sum(outlier_mask) == 0
    @test outlier_pct == 0.0
    println("  ✓ No outliers detected: $(sum(outlier_mask)) outliers, $outlier_pct%")
end
flush(stdout)

println("\n[Test 8/12] find_outliers: Clear outliers on both ends")
flush(stdout)
@testset "Outliers: Both ends" begin
    # Data with clear outliers
    data_with_outliers = [1.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 100.0]
    outlier_mask, outlier_pct = find_outliers(data_with_outliers)
    
    # Should detect low (1.0) and high (100.0) as outliers
    @test sum(outlier_mask) >= 2
    @test outlier_pct >= 20.0  # At least 2 out of 8
    @test outlier_mask[1] == true   # 1.0 is an outlier
    @test outlier_mask[8] == true   # 100.0 is an outlier
    
    println("  ✓ Detected $(sum(outlier_mask)) outliers: $outlier_pct%")
    println("    Outlier positions: $(findall(outlier_mask))")
end
flush(stdout)

println("\n[Test 9/12] find_outliers: High outlier only")
flush(stdout)
@testset "Outliers: High only" begin
    # Single high outlier
    data_high = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 50.0]
    outlier_mask, outlier_pct = find_outliers(data_high)
    
    @test sum(outlier_mask) >= 1
    @test outlier_mask[8] == true  # 50.0 should be detected
    
    println("  ✓ Detected $(sum(outlier_mask)) high outlier(s): $outlier_pct%")
end
flush(stdout)

println("\n[Test 10/12] find_outliers: Empty data (edge case)")
flush(stdout)
@testset "Outliers: Empty" begin
    empty_data = Float64[]
    outlier_mask, outlier_pct = find_outliers(empty_data)
    
    @test isempty(outlier_mask)
    @test outlier_pct == 0.0
    
    println("  ✓ Empty data handled: $outlier_pct% outliers")
end
flush(stdout)

println("\n[Test 11/12] find_outliers: All identical values (no outliers)")
flush(stdout)
@testset "Outliers: Constant" begin
    # All values the same - IQR is zero, no outliers
    constant_data = [5.0, 5.0, 5.0, 5.0, 5.0]
    outlier_mask, outlier_pct = find_outliers(constant_data)
    
    @test sum(outlier_mask) == 0
    @test outlier_pct == 0.0
    
    println("  ✓ Constant data: $outlier_pct% outliers")
end
flush(stdout)

println("\n[Test 12/12] find_outliers: IQR method validation")
flush(stdout)
@testset "Outliers: IQR method" begin
    # Known data to verify IQR calculation
    # Data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    # Q1 = 3.25, Q3 = 7.75, IQR = 4.5
    # Lower bound = 3.25 - 1.5*4.5 = -3.5
    # Upper bound = 7.75 + 1.5*4.5 = 14.5
    # No outliers expected in range [1, 10]
    
    test_data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    outlier_mask, outlier_pct = find_outliers(test_data)
    
    @test sum(outlier_mask) == 0
    @test outlier_pct == 0.0
    
    # Now add an outlier beyond upper bound
    test_data_with_outlier = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 20.0]
    outlier_mask2, outlier_pct2 = find_outliers(test_data_with_outlier)
    
    @test sum(outlier_mask2) >= 1
    @test outlier_mask2[end] == true  # 20.0 should be outlier
    
    println("  ✓ IQR method validated")
    println("    [1-10]: $(sum(outlier_mask)) outliers")
    println("    [1-10, 20]: $(sum(outlier_mask2)) outliers")
end
flush(stdout)

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^70)
println("All tests completed successfully!")
println("="^70)
println()
flush(stdout)
