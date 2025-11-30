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
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/Load_Sets__CompareUI__test_caching.jl
# ============================================================================

println("="^80)
println("TEST: CompareUI Async Caching Performance")
println("="^80)
println()

# Load base setup
println("[TEST] Loading Load_Sets setup...")
include("Load_Sets.jl")

# Load CompareUI module
println("[TEST] Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Create UI in test mode
println("[TEST] Creating CompareUI in test_mode=true...")
result = create_compare_figure(sets, input_type; test_mode=true, max_images_per_row=3)

println()
println("="^80)
println("Test Configuration")
println("="^80)
println("Available patients: $(length(result.all_patient_ids))")
println("First 10 patients: $(result.all_patient_ids[1:min(10, length(result.all_patient_ids))])")
println()

# Display to start event loop
println("[TEST] Displaying figure...")
screen = Bas3GLMakie.GLMakie.Screen()
display(screen, result.figure)

# Register mousebutton workaround
Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(result.figure).mousebutton) do event
end

println()
println("="^80)
println("Initial Load Test")
println("="^80)
println()

# Wait for initial async load to complete
println("[TEST] Waiting for initial async load of patient 1...")
println("[TEST] This should show:")
println("  1. Cache MISS message")
println("  2. 'Loading...' placeholder in UI")
println("  3. Async preload triggered")
println("  4. Preload completes and rebuilds UI")
println("  5. Cache HIT on rebuild")
println()

# Wait for initial load (async)
let initial_wait = 0
    max_wait = 300  # 5 minutes max
    while initial_wait < max_wait
        sleep(5)
        initial_wait += 5
        
        # Check if cache has patient 1
        local cached = result.functions[:get_from_cache](1)
        if !isnothing(cached)
            println("[TEST] ✓ Initial load complete after $(initial_wait)s")
            break
        end
        
        if initial_wait % 30 == 0
            println("[TEST] Still loading... ($(initial_wait)s elapsed)")
        end
    end
end

println()
println("="^80)
println("Cache Statistics After Initial Load")
println("="^80)
println("Cache hits: $(result.cache[:cache_hits][])")
println("Cache misses: $(result.cache[:cache_misses][])")
println()

# Test navigation
if length(result.all_patient_ids) >= 3
    println()
    println("="^80)
    println("Navigation Test (Manual)")
    println("="^80)
    println()
    println("You can now test navigation manually:")
    println("  1. Click 'Weiter →' to navigate to patient 2")
    println("     - Should show 'Loading...' briefly")
    println("     - Async preload runs in background")
    println("     - UI rebuilds when complete")
    println()
    println("  2. Click 'Weiter →' again to patient 3")
    println("     - Same async behavior")
    println()
    println("  3. Click '← Zurück' to return to patient 2")
    println("     - Should be INSTANT (cache hit)")
    println("     - Build time ~18s vs ~200s")
    println()
    println("  4. Click '← Zurück' to return to patient 1")
    println("     - Should be INSTANT (cache hit)")
    println()
    println("Watch the console for [CACHE] and [PRELOAD] messages.")
    println()
else
    println()
    println("="^80)
    println("WARNING: Not enough patients for navigation test")
    println("="^80)
    println("Need at least 3 patients, found: $(length(result.all_patient_ids))")
    println()
end

println("="^80)
println("Key Observations to Validate")
println("="^80)
println()
println("✓ First load (patient 1):")
println("  - Shows 'Loading...' message")
println("  - Cache MISS logged")
println("  - Async preload triggered")
println("  - UI rebuilds automatically when done")
println("  - Second build shows Cache HIT")
println()
println("✓ Navigation to new patient:")
println("  - Shows 'Loading...' briefly")
println("  - Async preload in background")
println("  - UI updates when ready")
println()
println("✓ Navigation to cached patient:")
println("  - INSTANT load (~18s)")
println("  - Cache HIT logged")
println("  - No 'Loading...' message")
println()
println("✓ UI never freezes:")
println("  - Always responsive during loads")
println("  - Can close window anytime")
println()
println("="^80)
println("Close window when done testing.")
println("="^80)
