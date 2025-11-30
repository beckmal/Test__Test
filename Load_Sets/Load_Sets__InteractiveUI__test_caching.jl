# ============================================================================
# Load_Sets__InteractiveUI__test_caching.jl
# ============================================================================
# Tests the preloading/caching mechanism in InteractiveUI with metrics collection
# 
# Metrics collected:
# - Cache hit/miss count (via console output)
# - Load time for each navigation (with/without cache)
# - Preload completion timing
#
# Usage:
#   cd /home/o2c4/workspace
#   julia ENVIRONMENT_ACTIVATE.jl --script=Bas3ImageSegmentation/Load_Sets/Load_Sets__InteractiveUI__test_caching.jl --interactive
# ============================================================================

println("="^80)
println("TEST: InteractiveUI Caching/Preloading Performance Metrics")
println("="^80)
println()

# Metrics storage
mutable struct TestMetrics
    navigation_times::Vector{Tuple{Int, Int, Float64}}  # (from, to, time_ms)
    cache_hits::Int
    cache_misses::Int
end

const test_metrics = TestMetrics(Tuple{Int, Int, Float64}[], 0, 0)

# Load base setup
println("[TEST] Loading Load_Sets setup...")
include("Load_Sets.jl")

# Load InteractiveUI module
println("[TEST] Loading InteractiveUI module...")
include("Load_Sets__InteractiveUI.jl")

# Create UI in test mode
println("[TEST] Creating InteractiveUI in test_mode=true...")
result = create_interactive_figure(sets, input_type, raw_output_type; test_mode=true)

println("[TEST] Observables: $(keys(result.observables))")
println("[TEST] Widgets: $(keys(result.widgets))")

# Display to start event loop
println("[TEST] Displaying figure...")
screen = Bas3GLMakie.GLMakie.Screen()
display(screen, result.figure)

# Register mousebutton workaround
Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(result.figure).mousebutton) do event
end

# Wait for initialization and initial preload
println("[TEST] Waiting 10s for UI initialization and initial preload to complete...")
sleep(10)

println()
println("="^80)
println("[TEST] Starting navigation performance test")
println("="^80)
println()

"""
Navigate and measure time until display update completes.
"""
function navigate_and_measure!(widgets, observables, direction::Symbol, wait_for_preload::Bool=true)
    local from_idx = observables[:current_image_index][]
    
    println("[TEST] Starting navigation from index $from_idx ($(direction))...")
    local start_time = time()
    
    # Trigger navigation
    if direction == :next
        widgets[:next_button].clicks[] = widgets[:next_button].clicks[] + 1
    else
        widgets[:prev_button].clicks[] = widgets[:prev_button].clicks[] + 1
    end
    
    # Wait for navigation to complete
    sleep(0.2)
    local timeout = 15.0
    local waited = 0.0
    while observables[:current_image_index][] == from_idx && waited < timeout
        sleep(0.1)
        waited += 0.1
    end
    
    # Measure time until index changed
    local elapsed_ms = (time() - start_time) * 1000
    local to_idx = observables[:current_image_index][]
    
    push!(test_metrics.navigation_times, (from_idx, to_idx, elapsed_ms))
    println("[METRICS] Navigation $from_idx -> $to_idx completed in $(round(elapsed_ms, digits=1)) ms")
    
    # Optionally wait for preload to complete
    if wait_for_preload
        println("[TEST] Waiting 3s for preload of adjacent images...")
        sleep(3)
    end
    
    return (from_idx, to_idx, elapsed_ms)
end

# Test sequence
println("[TEST] Navigation sequence: 1 -> 2 -> 3 -> 4 -> 5 -> 4 -> 3 -> 2 -> 1")
println()

current_idx = result.observables[:current_image_index][]
println("[METRICS] Starting at index: $current_idx")
println()

# Phase 1: Forward navigation (expecting cache misses initially, then preload helps)
println("-"^60)
println("[TEST] PHASE 1: Forward navigation (1 -> 5)")
println("[TEST] First nav likely cache miss, then preload should help")
println("-"^60)
println()

for i in 1:4
    navigate_and_measure!(result.widgets, result.observables, :next, true)
    println()
end

# Phase 2: Backward navigation (expecting cache hits)
println("-"^60)
println("[TEST] PHASE 2: Backward navigation (5 -> 1)")
println("[TEST] These should benefit from preloading")
println("-"^60)
println()

for i in 1:4
    navigate_and_measure!(result.widgets, result.observables, :prev, true)
    println()
end

# Calculate and display metrics
println()
println("="^80)
println("[TEST] PERFORMANCE METRICS SUMMARY")
println("="^80)
println()

forward_times = [t[3] for t in test_metrics.navigation_times[1:4]]
backward_times = [t[3] for t in test_metrics.navigation_times[5:8]]

println("Forward navigation times (1->5):")
for (i, (from, to, t)) in enumerate(test_metrics.navigation_times[1:4])
    println("  $from -> $to: $(round(t, digits=1)) ms")
end
println("  Average: $(round(sum(forward_times)/length(forward_times), digits=1)) ms")
println()

println("Backward navigation times (5->1):")
for (i, (from, to, t)) in enumerate(test_metrics.navigation_times[5:8])
    println("  $from -> $to: $(round(t, digits=1)) ms")
end
println("  Average: $(round(sum(backward_times)/length(backward_times), digits=1)) ms")
println()

avg_forward = sum(forward_times) / length(forward_times)
avg_backward = sum(backward_times) / length(backward_times)

println("-"^60)
println("ANALYSIS:")
println("-"^60)
println("  Forward avg:  $(round(avg_forward, digits=1)) ms")
println("  Backward avg: $(round(avg_backward, digits=1)) ms")

if avg_backward < avg_forward
    speedup = avg_forward / avg_backward
    savings_pct = 100 * (1 - avg_backward / avg_forward)
    println("  Speedup:      $(round(speedup, digits=2))x faster on backward")
    println("  Time saved:   $(round(savings_pct, digits=0))%")
    println()
    println("  Caching appears to be working!")
elseif avg_forward < avg_backward
    println("  Forward was faster than backward (preload helped forward navigation)")
    println()
    println("  This is expected - preload runs after each navigation")
else
    println("  No significant speedup detected")
    println()
    println("  Note: Check console for [CACHE] Hit/Miss messages")
end

println()
println("="^80)
println("Check console output above for [CACHE] Hit/Miss and [PRELOAD] messages")
println("="^80)
println()

# Summary of what to look for
println("KEY LOG MESSAGES TO LOOK FOR:")
println("  [CACHE] Hit for index N       - Cache hit (fast)")
println("  [CACHE] Miss for index N      - Cache miss (slow, computed)")
println("  [PRELOAD] Starting preload... - Background preload started")
println("  [PRELOAD] Cached index N      - Preload completed")
println()
println("Manual test: Click navigation buttons and observe timing.")
println("Close window when done.")
println()
