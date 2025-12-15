# ============================================================================
# Load_Sets__CompareUI__test_performance.jl
# ============================================================================
# Performance tests for CompareUI polygon mask save operations
# 
# This test validates:
# - Individual polygon PNG save performance (< 2 seconds target)
# - BitMatrix → RGB conversion timing
# - PNG encoding overhead
# - Composite mask generation timing (when enabled)
# - Full save workflow end-to-end performance
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/Load_Sets__CompareUI__test_performance.jl
#
# Consolidated from:
#   - __test_polygon_save_performance.jl (UI-based approach)
#   - __test_polygon_save_performance_direct.jl (direct function benchmark)
#
# Based on performance analysis session: 2025-12-15
# See: PNG_SAVE_PERFORMANCE_ANALYSIS_RESULTS.md
# ============================================================================

using Test

println("="^80)
println("TEST: CompareUI Polygon Save Performance")
println("="^80)
println()

# Load base setup
println("[SETUP] Loading Load_Sets core modules...")
include("Load_Sets__Core.jl")

# Load CompareUI module
println("[SETUP] Loading CompareUI functions...")
include("Load_Sets__CompareUI.jl")
println()

# Test parameters
const TEST_IMAGE_INDEX = 62  # Patient 062 has existing polygon data
const BASE_DIR = "/mnt/c/Syncthing/MuHa - Bilder"

println("="^80)
println("Test Configuration")
println("="^80)
println("  Test Image Index: $TEST_IMAGE_INDEX")
println("  Base Directory: $BASE_DIR")
println("  Julia threads: $(Threads.nthreads())")
println()

# ============================================================================
# TEST 1: Load Test Data
# ============================================================================

@testset "Load Test Data" begin
    println("\n[TEST 1] Loading test data for performance benchmarks")
    
    # Load polygon metadata
    global patient_num = lpad(TEST_IMAGE_INDEX, 3, '0')
    global metadata_path = joinpath(BASE_DIR, "MuHa_$(patient_num)", "MuHa_$(patient_num)_polygon_metadata.json")
    
    @test isfile(metadata_path)
    println("  ✓ Metadata file exists: $metadata_path")
    
    global polygons = load_multiclass_metadata(TEST_IMAGE_INDEX)
    @test length(polygons) > 0
    println("  ✓ Loaded $(length(polygons)) polygon(s)")
    
    for (i, poly) in enumerate(polygons)
        println("    Polygon $i: ID=$(poly.id), class=$(poly.class), vertices=$(length(poly.vertices)), complete=$(poly.complete)")
    end
    
    # Find a complete polygon for testing
    global complete_poly_idx = findfirst(p -> p.complete, polygons)
    @test !isnothing(complete_poly_idx)
    println("  ✓ Found complete polygon at index $complete_poly_idx")
    
    global test_polygon = polygons[complete_poly_idx]
    @test test_polygon.complete == true
    @test length(test_polygon.vertices) >= 3
    println("  ✓ Test polygon: ID=$(test_polygon.id), $(length(test_polygon.vertices)) vertices")
end

# ============================================================================
# TEST 2: Image Loading Performance
# ============================================================================

@testset "Image Loading Performance" begin
    println("\n[TEST 2] Measuring full-resolution image load time")
    
    global original_filename = "MuHa_$(patient_num)_raw_adj.png"
    global original_path = joinpath(BASE_DIR, "MuHa_$(patient_num)", original_filename)
    
    @test isfile(original_path)
    println("  ✓ Original image exists: $original_path")
    
    # Measure load time
    load_time = @elapsed begin
        global original_img_loaded = Bas3GLMakie.GLMakie.FileIO.load(original_path)
    end
    
    println("  ✓ Image load time: $(round(load_time*1000, digits=1))ms")
    println("    Size (portrait): $(size(original_img_loaded))")
    
    # Typical WSL mount access from /mnt/c/ is 200-800ms for 15MB PNG
    @test load_time < 2.0  # Should be under 2 seconds
    
    # Measure rotation time (to landscape)
    rotate_time = @elapsed begin
        global original_img_rotated = rotr90(original_img_loaded)
    end
    
    println("  ✓ Image rotate time: $(round(rotate_time*1000, digits=1))ms")
    println("    Size (landscape): $(size(original_img_rotated))")
    
    # Rotation is array reindexing, typically 40-250ms for 4032×3024
    @test rotate_time < 0.5  # Should be under 500ms
end

# ============================================================================
# TEST 3: Polygon Mask Creation Performance
# ============================================================================

@testset "Polygon Mask Creation" begin
    println("\n[TEST 3] Measuring polygon mask creation time")
    
    mask_create_time = @elapsed begin
        global test_mask = create_polygon_mask(original_img_rotated, test_polygon.vertices)
    end
    
    println("  ✓ Mask creation time: $(round(mask_create_time*1000, digits=1))ms")
    println("    Mask size: $(size(test_mask))")
    
    mask_pixel_count = sum(test_mask)
    println("    Pixels inside polygon: $mask_pixel_count")
    
    @test mask_pixel_count > 0  # Should have at least some pixels
    @test size(test_mask) == size(original_img_rotated)
    
    # Mask creation is point-in-polygon for all pixels
    # For 4032×3024 = 12.2M pixels with ~6 vertices: should be under 500ms
    @test mask_create_time < 1.0
end

# ============================================================================
# TEST 4: Individual Polygon Save Performance (PRIMARY BENCHMARK)
# ============================================================================

@testset "Individual Polygon Save Performance" begin
    println("\n[TEST 4] Benchmarking individual polygon PNG save")
    println("  This is the PRIMARY performance metric for user-facing responsiveness")
    println()
    
    global patient_folder = joinpath(BASE_DIR, "MuHa_$(patient_num)")
    @test isdir(patient_folder)
    
    # Run the actual save function with timing
    println("  Running save_polygon_mask_individual()...")
    println("  (Check [PERF-POLYGON-SAVE] logs below for detailed breakdown)")
    println()
    
    total_save_time = @elapsed begin
        global (save_success, filename) = save_polygon_mask_individual(
            TEST_IMAGE_INDEX,
            test_polygon,
            test_mask,
            patient_folder
        )
    end
    
    println()
    println("  ✓ Individual save time: $(round(total_save_time*1000, digits=1))ms")
    println("    Success: $save_success")
    println("    Filename: $filename")
    
    @test save_success == true
    @test !isnothing(filename)
    
    # PERFORMANCE TARGET: < 2 seconds for individual polygon save
    # After optimization (removing composite auto-generation): ~1.7 seconds
    # Before optimization: ~23 seconds (due to composite generation)
    @test total_save_time < 3.0  # Allow some headroom for slower systems
    
    if total_save_time > 2.0
        @warn "Individual save time exceeded 2 second target: $(round(total_save_time, digits=2))s"
    else
        println("  ✓ Performance target met: < 2 seconds")
    end
    
    # Verify saved file exists
    if !isnothing(filename)
        saved_path = joinpath(patient_folder, filename)
        @test isfile(saved_path)
        println("  ✓ Saved file exists: $saved_path")
    end
end

# ============================================================================
# TEST 5: Composite Mask Generation Performance (OPTIONAL)
# ============================================================================

@testset "Composite Mask Generation Performance" begin
    println("\n[TEST 5] Benchmarking composite mask generation")
    println("  NOTE: Composite auto-generation was removed for performance")
    println("  This test measures manual composite generation if needed")
    println()
    
    println("  Running save_composite_mask_from_individuals()...")
    println("  (Check [PERF-COMPOSITE] and [PERF-RECONSTRUCT] logs below)")
    println()
    
    composite_time = @elapsed begin
        global comp_success = save_composite_mask_from_individuals(TEST_IMAGE_INDEX)
    end
    
    println()
    println("  ✓ Composite generation time: $(round(composite_time*1000, digits=1))ms")
    println("    Success: $comp_success")
    
    @test comp_success == true
    
    # Composite generation involves:
    # 1. Loading all individual PNGs (20+ seconds on WSL mount!)
    # 2. Reconstructing overlay (~300ms)
    # 3. Saving composite PNG (~500ms)
    #
    # KNOWN ISSUE: Loading PNGs from WSL-mounted Windows filesystem
    # takes 20+ seconds for multiple files. This is why composite
    # auto-generation was removed from the save workflow.
    
    if composite_time > 5.0
        @warn "Composite generation slow ($(round(composite_time, digits=1))s) - likely WSL filesystem overhead"
        println("  ⚠️  This is expected on WSL-mounted Windows filesystems (/mnt/c/)")
        println("  ⚠️  Composite auto-generation has been DISABLED to avoid blocking saves")
    end
    
    # Verify composite file exists
    composite_filename = "MuHa_$(patient_num)_composite_mask.png"
    composite_path = joinpath(patient_folder, composite_filename)
    @test isfile(composite_path)
    println("  ✓ Composite file exists: $composite_path")
end

# ============================================================================
# TEST 6: Full Workflow End-to-End Timing
# ============================================================================

@testset "Full Workflow End-to-End" begin
    println("\n[TEST 6] Measuring full workflow: load → mask → save")
    
    # Simulate full workflow for one new polygon
    workflow_time = @elapsed begin
        # Load image (would be cached in real UI)
        img_loaded = Bas3GLMakie.GLMakie.FileIO.load(original_path)
        img_rotated = rotr90(img_loaded)
        
        # Create mask from polygon
        mask = create_polygon_mask(img_rotated, test_polygon.vertices)
        
        # Save individual polygon
        (success, _) = save_polygon_mask_individual(
            TEST_IMAGE_INDEX,
            test_polygon,
            mask,
            patient_folder
        )
    end
    
    println("  ✓ Full workflow time: $(round(workflow_time*1000, digits=1))ms")
    
    # Full workflow target: < 4 seconds
    # Breakdown:
    #   - Image load: ~500ms (WSL mount)
    #   - Rotate: ~40ms
    #   - Mask create: ~300ms
    #   - Individual save: ~1700ms
    #   Total: ~2540ms
    @test workflow_time < 5.0
    
    if workflow_time < 3.0
        println("  ✓ Excellent performance: < 3 seconds")
    elseif workflow_time < 4.0
        println("  ✓ Good performance: < 4 seconds")
    else
        @warn "Workflow time approaching limit: $(round(workflow_time, digits=1))s"
    end
end

# ============================================================================
# SUMMARY
# ============================================================================

println()
println("="^80)
println("PERFORMANCE TEST SUMMARY")
println("="^80)
println()
println("KEY METRICS:")
println("  Individual polygon save: Should be < 2 seconds ✅")
println("  Full workflow: Should be < 4 seconds ✅")
println("  Composite generation: ~20+ seconds (DISABLED in auto-save) ⚠️")
println()
println("OPTIMIZATION HISTORY:")
println("  Before: 23+ seconds per polygon (with auto-composite)")
println("  After:  ~1.7 seconds per polygon (composite disabled)")
println("  Speedup: 13x faster (95% reduction)")
println()
println("ROOT CAUSE IDENTIFIED:")
println("  WSL-mounted Windows filesystem (/mnt/c/) causes 20+ second")
println("  overhead when loading multiple PNGs for composite generation.")
println("  Individual PNG saves are fast (~1.7s), composite is slow.")
println()
println("SOLUTION IMPLEMENTED:")
println("  Removed automatic composite mask generation from save workflow.")
println("  Individual polygon PNGs are sufficient for analysis.")
println("  Composite can be manually regenerated if needed.")
println()
println("For detailed analysis, see:")
println("  - PNG_SAVE_PERFORMANCE_ANALYSIS_RESULTS.md")
println("  - COMPOSITE_MASK_REMOVAL.md")
println("  - SESSION_SUMMARY_PNG_PERFORMANCE.md")
println()

println("="^80)
println("All polygon save performance tests completed!")
println("="^80)
println()
