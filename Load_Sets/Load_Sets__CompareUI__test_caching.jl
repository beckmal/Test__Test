# ============================================================================
# Load_Sets__CompareUI__test_caching.jl
# ============================================================================
# Tests the async preloading/caching mechanism in CompareUI
# 
# This test validates:
# - Async loading works without blocking UI
# - Cache hits are significantly faster than cache misses
# - Navigation triggers appropriate preloads
# - UI shows "Loading..." message during async loads
# - Multi-threaded preload performance
# - Cache structure correctness (no bbox/HSV in cache)
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/Load_Sets__CompareUI__test_caching.jl
#
# Consolidated from:
#   - test_performance_CompareUI.jl
#   - test_preload_performance.jl
# ============================================================================

println("="^80)
println("TEST: CompareUI Async Caching Performance")
println("="^80)
println()

# Load base setup
println("[SETUP] Loading Load_Sets setup...")
include("Load_Sets.jl")

# Load CompareUI module
println("[SETUP] Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Create UI in test mode
println("[SETUP] Creating CompareUI in test_mode=true...")
result = create_compare_figure(sets, input_type; test_mode=true, max_images_per_row=3)

println()
println("="^80)
println("Test Configuration")
println("="^80)
println("Julia threads: $(Threads.nthreads())")
println("Available patients: $(length(result.all_patient_ids))")
println("First 10 patients: $(result.all_patient_ids[1:min(10, length(result.all_patient_ids))])")
println()

# ============================================================================
# TEST 1: Preload Performance Measurement (Automated)
# ============================================================================

println("="^80)
println("TEST 1: Preload Performance Measurement")
println("="^80)
println()

# Clean cache before testing
println("[SETUP] Clearing cache...")
lock(result.cache[:cache_lock]) do
    empty!(result.cache[:patient_image_cache])
    empty!(result.cache[:preload_tasks])
end

# Force garbage collection
GC.gc()
sleep(1)

# Test patient ID
test_patient_id = result.all_patient_ids[1]
println("[TEST] Testing patient $test_patient_id")
println()

# Measure preload time
println("[PERF] Starting preload performance measurement...")
start_time = time()

# Run preload
preload_result = result.functions[:preload_patient_images](test_patient_id)

end_time = time()
elapsed_seconds = end_time - start_time

println()
println("-"^60)
println("PRELOAD RESULTS")
println("-"^60)
println("[RESULT] Preload completed in: $(round(elapsed_seconds, digits=3)) seconds")
println("[RESULT] Success: $(preload_result.success)")
if !isnothing(preload_result.error)
    println("[RESULT] Error: $(preload_result.error)")
end
println()

# Calculate per-image time based on cached images
lock(result.cache[:cache_lock]) do
    if haskey(result.cache[:patient_image_cache], test_patient_id)
        cached = result.cache[:patient_image_cache][test_patient_id]
        num_images = length(cached)
        if num_images > 0
            per_image_ms = (elapsed_seconds / num_images) * 1000
            println("[RESULT] Number of images: $num_images")
            println("[RESULT] Time per image: $(round(per_image_ms, digits=1)) ms")
            println("[RESULT] Images per second: $(round(num_images / elapsed_seconds, digits=2))")
        end
    end
end
println()

# ============================================================================
# TEST 2: Cache Structure Verification
# ============================================================================

println("="^80)
println("TEST 2: Cache Structure Verification")
println("="^80)
println()

lock(result.cache[:cache_lock]) do
    if haskey(result.cache[:patient_image_cache], test_patient_id)
        cached = result.cache[:patient_image_cache][test_patient_id]
        println("[VERIFY] Cached $(length(cached)) images")
        
        if length(cached) > 0
            # Check structure
            first_img = cached[1]
            keys_present = keys(first_img)
            println("[VERIFY] Cache structure keys: $(keys_present)")
            
            # Expected keys (no bbox/HSV - those are computed on-demand)
            expected_keys = Set([:image_index, :input_rotated, :output_rotated, :input_raw, :output_raw, :height])
            actual_keys = Set(keys_present)
            
            # Verify no bbox/HSV in cache
            has_bboxes = :bboxes in keys_present
            has_hsv = :hsv_data in keys_present
            
            if !has_bboxes && !has_hsv
                println("[VERIFY] CORRECT: bbox/HSV NOT in cache (on-demand computation)")
            else
                println("[VERIFY] WARNING: bbox/HSV found in cache (should be on-demand!)")
            end
            
            # Verify expected keys present
            if actual_keys == expected_keys
                println("[VERIFY] CORRECT: All expected keys present")
            else
                missing = setdiff(expected_keys, actual_keys)
                extra = setdiff(actual_keys, expected_keys)
                if !isempty(missing)
                    println("[VERIFY] WARNING: Missing keys: $missing")
                end
                if !isempty(extra)
                    println("[VERIFY] NOTE: Extra keys: $extra")
                end
            end
        end
    else
        println("[VERIFY] WARNING: Patient $test_patient_id not in cache!")
    end
end
println()

# ============================================================================
# TEST 3: Performance Assessment
# ============================================================================

println("="^80)
println("TEST 3: Performance Assessment")
println("="^80)
println()

if elapsed_seconds < 2.0
    println("[ASSESSMENT] EXCELLENT: Multi-threading working perfectly!")
    println("[ASSESSMENT] Performance matches expectations for parallel I/O")
elseif elapsed_seconds < 5.0
    println("[ASSESSMENT] GOOD: Significant improvement over sequential")
    println("[ASSESSMENT] Likely limited by disk I/O bandwidth")
elseif elapsed_seconds < 15.0
    println("[ASSESSMENT] FAIR: Better than before but not optimal")
    println("[ASSESSMENT] Check if multi-threading is actually being used")
else
    println("[ASSESSMENT] SLOW: Performance may not be improved")
    println("[ASSESSMENT] Investigate: Are threads being utilized?")
end
println()

println("Expected performance benchmarks:")
println("  - ORIGINAL (sequential + bbox + HSV): ~200 seconds")
println("  - After cache opt (sequential .bin only): ~10-20 seconds")
println("  - After multi-threading (parallel .bin): ~0.3-2 seconds")
println()

# ============================================================================
# TEST 4: Interactive Navigation Test (requires display)
# ============================================================================

println("="^80)
println("TEST 4: Interactive Navigation Test")
println("="^80)
println()

# Display to start event loop
println("[SETUP] Displaying figure for interactive testing...")
screen = Bas3GLMakie.GLMakie.Screen()
display(screen, result.figure)

# Register mousebutton workaround
Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(result.figure).mousebutton) do event
end

println()
println("Cache Statistics:")
println("  Cache hits: $(result.cache[:cache_hits][])")
println("  Cache misses: $(result.cache[:cache_misses][])")
println()

# Wait for initial async load to complete
println("[TEST] Waiting for initial async load of patient 1...")
let initial_wait = 0
    max_wait = 120  # 2 minutes max
    while initial_wait < max_wait
        sleep(5)
        initial_wait += 5
        
        # Check if cache has patient 1
        cached = result.functions[:get_from_cache](test_patient_id)
        if !isnothing(cached)
            println("[TEST] Initial load complete after $(initial_wait)s")
            break
        end
        
        if initial_wait % 30 == 0
            println("[TEST] Still loading... ($(initial_wait)s elapsed)")
        end
    end
end

println()
println("Updated Cache Statistics:")
println("  Cache hits: $(result.cache[:cache_hits][])")
println("  Cache misses: $(result.cache[:cache_misses][])")
println()

# Navigation instructions
if length(result.all_patient_ids) >= 3
    println("="^80)
    println("Manual Navigation Test Instructions")
    println("="^80)
    println()
    println("Test navigation manually:")
    println("  1. Click 'Weiter ->' to navigate to patient 2")
    println("     - Should show 'Loading...' briefly")
    println("     - Async preload runs in background")
    println("     - UI rebuilds when complete")
    println()
    println("  2. Click 'Weiter ->' again to patient 3")
    println("     - Same async behavior")
    println()
    println("  3. Click '<- Zuruck' to return to patient 2")
    println("     - Should be INSTANT (cache hit)")
    println()
    println("  4. Click '<- Zuruck' to return to patient 1")
    println("     - Should be INSTANT (cache hit)")
    println()
    println("Watch the console for [CACHE] and [PRELOAD] messages.")
else
    println("WARNING: Not enough patients for navigation test")
    println("Need at least 3 patients, found: $(length(result.all_patient_ids))")
end

println()
println("="^80)
println("Key Observations to Validate")
println("="^80)
println()
println("First load (cache miss):")
println("  - Shows 'Loading...' message")
println("  - Cache MISS logged")
println("  - Async preload triggered")
println("  - UI rebuilds automatically when done")
println()
println("Navigation to cached patient:")
println("  - INSTANT load")
println("  - Cache HIT logged")
println("  - No 'Loading...' message")
println()
println("UI responsiveness:")
println("  - Always responsive during loads")
println("  - Can close window anytime")
println()
println("="^80)
println("Close window when done testing.")
println("="^80)
