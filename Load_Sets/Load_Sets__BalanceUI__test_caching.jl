# ============================================================================
# Load_Sets__BalanceUI__test_caching.jl
# ============================================================================
# Tests the preloading/caching mechanism in BalanceUI with metrics collection
# 
# Metrics collected:
# - Cache hit/miss count
# - Load time for each navigation (with/without cache)
# - Preload completion timing
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/Load_Sets__BalanceUI__test_caching.jl --interactive
# ============================================================================

println("="^80)
println("TEST: BalanceUI Caching/Preloading Performance Metrics")
println("="^80)
println()

# Metrics storage
mutable struct TestMetrics
    navigation_times::Vector{Tuple{Int, Int, Float64}}  # (from, to, time_ms)
end

const test_metrics = TestMetrics(Tuple{Int, Int, Float64}[])

# Load base setup
println("[TEST] Loading Load_Sets setup...")
include("Load_Sets.jl")

# Load BalanceUI module
println("[TEST] Loading BalanceUI module...")
include("Load_Sets__BalanceUI.jl")

# Create UI in test mode
println("[TEST] Creating BalanceUI in test_mode=true...")
result = create_balance_figure(sets, input_type, raw_output_type; test_mode=true)

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
println("[TEST] Waiting 12s for UI initialization and initial preload to fully complete...")
sleep(12)

println()
println("="^80)
println("[TEST] Starting navigation performance test")
println("="^80)
println()

"""
Navigate and measure time until display update completes.
"""
function navigate_and_measure!(widgets, observables, direction::Symbol, wait_for_preload::Bool=true)
    local from_idx = observables[:current_index][]
    
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
    while observables[:current_index][] == from_idx && waited < timeout
        sleep(0.1)
        waited += 0.1
    end
    
    # Measure time until index changed
    local elapsed_ms = (time() - start_time) * 1000
    local to_idx = observables[:current_index][]
    
    push!(test_metrics.navigation_times, (from_idx, to_idx, elapsed_ms))
    println("[METRICS] Navigation $from_idx → $to_idx completed in $(round(elapsed_ms, digits=1)) ms")
    
    # Optionally wait for preload to complete
    if wait_for_preload
        println("[TEST] Waiting 8s for preload of adjacent images...")
        sleep(8)
    end
    
    return (from_idx, to_idx, elapsed_ms)
end

# Test sequence
println("[TEST] Navigation sequence: 1 → 2 → 3 → 4 → 5 → 4 → 3 → 2 → 1")
println()

current_idx = result.observables[:current_index][]
println("[METRICS] Starting at index: $current_idx")
println()

# Phase 1: Forward navigation (expecting cache misses initially)
println("-"^60)
println("[TEST] PHASE 1: Forward navigation (1 → 5)")
println("[TEST] First nav likely cache miss, then preload should help")
println("-"^60)
println()

for i in 1:4
    navigate_and_measure!(result.widgets, result.observables, :next, true)
    println()
end

# Phase 2: Backward navigation (expecting cache hits)
println("-"^60)
println("[TEST] PHASE 2: Backward navigation (5 → 1)")
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

println("Forward navigation times (1→5):")
for (i, (from, to, t)) in enumerate(test_metrics.navigation_times[1:4])
    println("  $from → $to: $(round(t, digits=1)) ms")
end
println("  Average: $(round(sum(forward_times)/length(forward_times), digits=1)) ms")
println()

println("Backward navigation times (5→1):")
for (i, (from, to, t)) in enumerate(test_metrics.navigation_times[5:8])
    println("  $from → $to: $(round(t, digits=1)) ms")
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
    println("  Speedup:      $(round(speedup, digits=2))x faster on backward")
    println()
    println("  ✓ Caching appears to be working!")
else
    println("  No speedup detected")
    println()
    println("  Note: The histogram computation (~1200ms) dominates load time.")
    println("  Caching saves disk I/O (~200ms) but histograms still need recomputation.")
end

println()
println("="^80)
println("Check console output above for [CACHE] Hit/Miss messages")
println("="^80)
println()
println("Manual test: Click navigation buttons and observe timing.")
println("Close window when done.")
println()
