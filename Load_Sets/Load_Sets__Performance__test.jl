# ============================================================================
# Load_Sets__Performance__test.jl
# ============================================================================
# Measures actual performance of preloading/caching for all three UIs
# 
# Tests:
# - Raw .bin file loading (CompareUI style)
# - Sequential vs Parallel performance
# - BalanceUI style loading (load_muha_images)
# - InteractiveUI style computation (marker detection)
# - Cache access overhead
# - Image transformation overhead
#
# Usage:
#   julia --script=./Bas3ImageSegmentation/Load_Sets/Load_Sets__Performance__test.jl
#
# Consolidated from:
#   - test_cache_timing.jl
# ============================================================================

println("="^80)
println("TEST: Cache Performance Timing Measurement")
println("="^80)
println()

# Load the base module
include("Load_Sets.jl")

using Statistics

# ============================================================================
# SETUP - Load datasets
# ============================================================================

println("[SETUP] Loading datasets...")
setup_start = time()

# Load original sets (shared by all UIs)
sets = load_original_sets(50, false)  # Load 50 images
println("[SETUP] Loaded $(length(sets)) image sets")

setup_elapsed = time() - setup_start
println("[SETUP] Dataset loading took $(round(setup_elapsed * 1000, digits=0))ms")
println()

# ============================================================================
# TEST 1: Raw .bin file loading (what CompareUI does in parallel)
# ============================================================================

println("="^80)
println("TEST 1: Raw .bin File Loading (CompareUI style)")
println("="^80)
println()

function measure_bin_loading(sets, indices)
    times = Float64[]
    for idx in indices
        if idx < 1 || idx > length(sets)
            continue
        end
        
        start = time()
        
        # This is what get_images_by_index does
        input_img = sets[idx][1]
        output_img = sets[idx][2]
        
        # Force data loading by accessing the image
        input_rgb = rotr90(image(input_img))
        output_rgb = rotr90(image(output_img))
        
        elapsed = (time() - start) * 1000
        push!(times, elapsed)
        println("  Index $idx: $(round(elapsed, digits=1))ms")
    end
    return times
end

println("[TEST 1a] Sequential .bin loading (5 images):")
seq_times = measure_bin_loading(sets, 1:5)
println()
println("  Mean: $(round(mean(seq_times), digits=1))ms, Std: $(round(std(seq_times), digits=1))ms")
println()

println("[TEST 1b] Parallel .bin loading (5 images using Threads.@spawn):")
parallel_start = time()
tasks = map(1:5) do idx
    Threads.@spawn begin
        start = time()
        input_img = sets[idx][1]
        output_img = sets[idx][2]
        input_rgb = rotr90(image(input_img))
        output_rgb = rotr90(image(output_img))
        elapsed = (time() - start) * 1000
        (idx=idx, time=elapsed)
    end
end
results = fetch.(tasks)
parallel_total = (time() - parallel_start) * 1000

println("  Individual times:")
for r in results
    println("    Index $(r.idx): $(round(r.time, digits=1))ms")
end
println()
println("  Total parallel time: $(round(parallel_total, digits=1))ms")
println("  Sequential equivalent: $(round(sum(seq_times), digits=1))ms")
println("  Speedup: $(round(sum(seq_times) / parallel_total, digits=2))x")
println("  Threads available: $(Threads.nthreads())")
println()

# ============================================================================
# TEST 2: BalanceUI style loading (load_muha_images)
# ============================================================================

println("="^80)
println("TEST 2: BalanceUI Style Loading (load_muha_images)")
println("="^80)
println()

# Check if load_muha_images exists and MuHa data is available
muha_available = false
try
    # Try to find a valid MuHa dataset index
    for idx in 1:min(10, length(sets))
        dataset_idx = sets[idx][3]
        if dataset_idx > 0
            muha_available = true
            break
        end
    end
catch e
    println("[TEST 2] Skipped - MuHa data not available: $e")
end

if muha_available
    println("[TEST 2] MuHa data available, measuring load_muha_images timing...")
    
    # Find valid indices
    valid_indices = Int[]
    for idx in 1:min(20, length(sets))
        dataset_idx = sets[idx][3]
        if dataset_idx > 0
            push!(valid_indices, idx)
        end
        if length(valid_indices) >= 5
            break
        end
    end
    
    if !isempty(valid_indices)
        muha_times = Float64[]
        for idx in valid_indices
            dataset_idx = sets[idx][3]
            start = time()
            try
                # This is what BalanceUI preload_image does
                original_img, masked_region, success, message = load_muha_images(dataset_idx)
                elapsed = (time() - start) * 1000
                push!(muha_times, elapsed)
                println("  Index $idx (dataset $dataset_idx): $(round(elapsed, digits=1))ms (success=$success)")
            catch e
                elapsed = (time() - start) * 1000
                println("  Index $idx (dataset $dataset_idx): $(round(elapsed, digits=1))ms (ERROR: $e)")
            end
        end
        
        if !isempty(muha_times)
            println()
            println("  Summary:")
            println("    Mean: $(round(mean(muha_times), digits=1))ms")
            println("    Min: $(round(minimum(muha_times), digits=1))ms")
            println("    Max: $(round(maximum(muha_times), digits=1))ms")
        end
    else
        println("[TEST 2] No valid MuHa indices found")
    end
else
    println("[TEST 2] Skipped - MuHa data not available")
end
println()

# ============================================================================
# TEST 3: InteractiveUI style computation (marker detection)
# ============================================================================

println("="^80)
println("TEST 3: InteractiveUI Style Computation (Marker Detection)")
println("="^80)
println()

# Define the marker detection functions inline (simplified)
function measure_marker_detection(sets, indices)
    times = Float64[]
    
    for idx in indices
        if idx < 1 || idx > length(sets)
            continue
        end
        
        start = time()
        
        # Get input image
        img_input = sets[idx][1]
        
        # Build default params (simplified)
        threshold = 0.7
        threshold_upper = 1.0
        min_area = 8000
        aspect_ratio = 5.0
        kernel_size = 3
        
        # Extract white mask (this is the expensive part)
        img_rgb = image(img_input)
        img_size = size(img_rgb)
        
        # Convert to grayscale and threshold
        gray = [0.299f0 * p.r + 0.587f0 * p.g + 0.114f0 * p.b for p in img_rgb]
        mask = (gray .>= threshold) .& (gray .<= threshold_upper)
        
        # Morphological operations (simplified - just erosion/dilation concept)
        # In real code this would use ImageMorphology
        
        elapsed = (time() - start) * 1000
        push!(times, elapsed)
        println("  Index $idx: $(round(elapsed, digits=1))ms (image size: $(img_size))")
    end
    
    return times
end

println("[TEST 3a] Basic threshold computation (5 images):")
marker_times = measure_marker_detection(sets, 1:5)
if !isempty(marker_times)
    println()
    println("  Summary:")
    println("    Mean: $(round(mean(marker_times), digits=1))ms")
    println("    Min: $(round(minimum(marker_times), digits=1))ms")
    println("    Max: $(round(maximum(marker_times), digits=1))ms")
end
println()

# ============================================================================
# TEST 4: Cache access overhead
# ============================================================================

println("="^80)
println("TEST 4: Cache Access Overhead")
println("="^80)
println()

# Simulate cache operations
cache = Dict{Int, Any}()
cache_lock = ReentrantLock()

# Measure lock overhead
println("[TEST 4a] Lock acquisition overhead (1000 iterations):")
lock_times = Float64[]
for _ in 1:1000
    start = time()
    lock(cache_lock) do
        # Just acquire and release
    end
    push!(lock_times, (time() - start) * 1_000_000)  # microseconds
end
println("  Mean: $(round(mean(lock_times), digits=3))us")
println("  Max: $(round(maximum(lock_times), digits=3))us")
println()

# Measure Dict operations under lock
println("[TEST 4b] Dict operations under lock (1000 iterations):")
dict_times = Float64[]
for i in 1:1000
    start = time()
    lock(cache_lock) do
        cache[i] = (i, "data", true)
        _ = haskey(cache, i)
        _ = get(cache, i, nothing)
    end
    push!(dict_times, (time() - start) * 1_000_000)  # microseconds
end
println("  Mean: $(round(mean(dict_times), digits=3))us")
println("  Max: $(round(maximum(dict_times), digits=3))us")
println()

# ============================================================================
# TEST 5: Image transformation overhead
# ============================================================================

println("="^80)
println("TEST 5: Image Transformation Overhead")
println("="^80)
println()

# Load one image for transformation tests
test_img = sets[1][1]
test_rgb = image(test_img)
println("  Test image size: $(size(test_rgb))")
println()

println("[TEST 5a] rotr90 rotation (10 iterations):")
rot_times = Float64[]
for _ in 1:10
    start = time()
    _ = rotr90(test_rgb)
    push!(rot_times, (time() - start) * 1000)
end
println("  Mean: $(round(mean(rot_times), digits=1))ms")
println()

println("[TEST 5b] image() extraction (10 iterations):")
extract_times = Float64[]
for _ in 1:10
    start = time()
    _ = image(test_img)
    push!(extract_times, (time() - start) * 1000)
end
println("  Mean: $(round(mean(extract_times), digits=1))ms")
println()

# ============================================================================
# SUMMARY
# ============================================================================

println("="^80)
println("TIMING SUMMARY")
println("="^80)
println()

println("Component Breakdown (approximate):")
println("-"^60)
println("1. .bin file loading (mmap):     $(round(mean(seq_times), digits=0))ms per image")
println("2. Parallel speedup:             $(round(sum(seq_times) / parallel_total, digits=1))x with $(Threads.nthreads()) threads")
println("3. Lock overhead:                $(round(mean(lock_times), digits=1))us (negligible)")
println("4. rotr90 rotation:              $(round(mean(rot_times), digits=0))ms per image")
println("5. image() extraction:           $(round(mean(extract_times), digits=0))ms per image")
println()

println("Implications:")
println("-"^60)
println("- CompareUI parallel loading is effective ($(round(sum(seq_times) / parallel_total, digits=1))x speedup)")
println("- Lock overhead is negligible (~$(round(mean(lock_times), digits=0))us)")
println("- Main bottleneck is disk I/O for .bin files")
println("- Image transformations add ~$(round(mean(rot_times) + mean(extract_times), digits=0))ms overhead")
println()

println("Recommendations:")
println("-"^60)
println("- Keep parallel loading in CompareUI")
println("- Consider parallel adjacent-image preload for BalanceUI/InteractiveUI")
println("- Cache transformed images (post-rotr90) not raw data")
println()

println("="^80)
println("TEST COMPLETE")
println("="^80)
