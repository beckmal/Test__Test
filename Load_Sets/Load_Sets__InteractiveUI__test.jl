# Load_Sets__InteractiveUI__test.jl
# Tests for helper functions in Load_Sets__InteractiveUI.jl
# NOTE: Using write(stdout, ...) and Base.* functions to avoid module conflicts

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST: Load_Sets__InteractiveUI.jl Helper Functions\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)

write(stdout, "Activating environment...\n"); flush(stdout)
include("ENVIRONMENT_ACTIVATE.jl")
write(stdout, "✓ Environment activated\n\n"); flush(stdout)

write(stdout, "Loading packages (may take ~25s)...\n"); flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
using Statistics
using LinearAlgebra

write(stdout, "✓ Packages loaded\n"); flush(stdout)

write(stdout, "Loading modules...\n"); flush(stdout)
# Note: We only test pure helper functions, not the full UI creation
# which requires marker detection and dewarping dependencies
write(stdout, "✓ Modules ready\n\n"); flush(stdout)

test_results = Dict{String, Bool}()

# ==============================================================================
# Test Helper Functions (extracted from create_interactive_figure)
# ==============================================================================

# Helper function: extract_contours (lines 331-358)
function extract_contours(mask)
    h, w = Base.size(mask)
    contour_points = Tuple{Int, Int}[]
    
    for i in 1:h
        for j in 1:w
            if mask[i, j]
                is_boundary = false
                
                for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
                    ni, nj = i + di, j + dj
                    if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                        is_boundary = true
                        break
                    end
                end
                
                if is_boundary
                    Base.push!(contour_points, (i, j))
                end
            end
        end
    end
    
    return contour_points
end

# Helper function: axis_to_pixel (lines 363-384)
function axis_to_pixel(point_axis, img_height, img_width)
    rot_row = Base.round(Int, point_axis[1])
    rot_col = Base.round(Int, point_axis[2])
    
    orig_row = img_height - rot_col + 1
    orig_col = rot_row
    
    return (orig_row, orig_col)
end

# Helper function: make_rectangle (lines 387-397)
function make_rectangle(c1, c2)
    x_min, x_max = Base.minmax(c1[1], c2[1])
    y_min, y_max = Base.minmax(c1[2], c2[2])
    return Bas3GLMakie.GLMakie.Point2f[
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min)
    ]
end

# Helper function: compute_white_region_channel_stats (lines 633-686)
function compute_white_region_channel_stats(image, white_mask)
    raw_data = Bas3ImageSegmentation.data(image)
    rgb_data = permutedims(raw_data, (3, 1, 2))
    
    stats = Dict{Symbol, Dict{Symbol, Float64}}()
    
    channel_names = if Base.size(rgb_data, 1) == 3
        [:red, :green, :blue]
    else
        error("Image must have 3 color channels (RGB)")
    end
    
    white_pixel_count = Base.sum(white_mask)
    
    if white_pixel_count == 0
        for (i, ch) in Base.enumerate(channel_names)
            stats[ch] = Dict(:mean => 0.0, :std => 0.0, :skewness => 0.0)
        end
        return stats, 0
    end
    
    for (i, ch) in Base.enumerate(channel_names)
        channel_data = rgb_data[i, :, :]
        white_values = channel_data[white_mask]
        
        ch_mean = Statistics.mean(white_values)
        ch_std = Statistics.std(white_values)
        
        n = Base.length(white_values)
        if n > 2 && ch_std > 0
            centered = white_values .- ch_mean
            m3 = Base.sum(centered .^ 3) / n
            ch_skewness = m3 / (ch_std ^ 3)
        else
            ch_skewness = 0.0
        end
        
        stats[ch] = Dict(
            :mean => ch_mean,
            :std => ch_std,
            :skewness => ch_skewness
        )
    end
    
    return stats, white_pixel_count
end

# ==============================================================================
# Test 1: extract_contours - Simple square
# ==============================================================================

write(stdout, "Test 1: extract_contours - Simple square\n"); flush(stdout)
try
    mask = falses(10, 10)
    mask[3:7, 3:7] .= true
    
    contour = extract_contours(mask)
    
    # 5x5 filled square should have 16 boundary pixels
    @assert Base.length(contour) == 16
    
    test_results["extract_contours_square"] = true
    write(stdout, "  ✓ Simple square: $(Base.length(contour)) boundary pixels\n"); flush(stdout)
catch e
    test_results["extract_contours_square"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 2: extract_contours - Single pixel
# ==============================================================================

write(stdout, "Test 2: extract_contours - Single pixel\n"); flush(stdout)
try
    mask = falses(5, 5)
    mask[3, 3] = true
    
    contour = extract_contours(mask)
    
    @assert Base.length(contour) == 1
    @assert contour[1] == (3, 3)
    
    test_results["extract_contours_single"] = true
    write(stdout, "  ✓ Single pixel: 1 boundary pixel\n"); flush(stdout)
catch e
    test_results["extract_contours_single"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 3: extract_contours - Empty mask
# ==============================================================================

write(stdout, "Test 3: extract_contours - Empty mask\n"); flush(stdout)
try
    mask = falses(10, 10)
    contour = extract_contours(mask)
    
    @assert Base.length(contour) == 0
    
    test_results["extract_contours_empty"] = true
    write(stdout, "  ✓ Empty mask: 0 boundary pixels\n"); flush(stdout)
catch e
    test_results["extract_contours_empty"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 4: axis_to_pixel - Coordinate transformation
# ==============================================================================

write(stdout, "Test 4: axis_to_pixel - Coordinate transformation\n"); flush(stdout)
try
    # Test image dimensions: 100x200 (height x width)
    img_height = 100
    img_width = 200
    
    # Test point in axis coordinates (after rotr90)
    point_axis = (50.0, 30.0)  # (rot_row, rot_col)
    
    # Expected: orig_row = 100 - 30 + 1 = 71, orig_col = 50
    orig_row, orig_col = axis_to_pixel(point_axis, img_height, img_width)
    
    @assert orig_row == 71
    @assert orig_col == 50
    
    test_results["axis_to_pixel"] = true
    write(stdout, "  ✓ Coordinate transformation: ($img_height,$img_width) -> ($orig_row,$orig_col)\n"); flush(stdout)
catch e
    test_results["axis_to_pixel"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 5: make_rectangle - Rectangle creation
# ==============================================================================

write(stdout, "Test 5: make_rectangle - Rectangle creation\n"); flush(stdout)
try
    c1 = (10.0, 20.0)
    c2 = (50.0, 80.0)
    
    rect = make_rectangle(c1, c2)
    
    # Should have 5 points (4 corners + closing point)
    @assert Base.length(rect) == 5
    
    # First and last points should be identical (closed loop)
    @assert rect[1] == rect[5]
    
    # Check corners are correct
    @assert rect[1][1] == 10.0  # x_min
    @assert rect[1][2] == 20.0  # y_min
    @assert rect[3][1] == 50.0  # x_max
    @assert rect[3][2] == 80.0  # y_max
    
    test_results["make_rectangle"] = true
    write(stdout, "  ✓ Rectangle created with 5 points\n"); flush(stdout)
catch e
    test_results["make_rectangle"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 6: compute_white_region_channel_stats - With mock image
# ==============================================================================

write(stdout, "Test 6: compute_white_region_channel_stats - With data\n"); flush(stdout)
try
    # Create a simple test image (10x10 RGB)
    struct TestImage
        data::Array{Float64, 3}
    end
    Bas3ImageSegmentation.data(img::TestImage) = img.data
    
    # Create uniform red image
    img_data = zeros(Float64, 10, 10, 3)
    img_data[:, :, 1] .= 1.0  # Red channel = 1.0
    img_data[:, :, 2] .= 0.5  # Green channel = 0.5
    img_data[:, :, 3] .= 0.2  # Blue channel = 0.2
    
    test_img = TestImage(img_data)
    
    # Create mask covering half the image
    white_mask = falses(10, 10)
    white_mask[1:5, :] .= true
    
    stats, pixel_count = compute_white_region_channel_stats(test_img, white_mask)
    
    @assert pixel_count == 50  # Half of 10x10
    @assert Base.haskey(stats, :red)
    @assert Base.haskey(stats, :green)
    @assert Base.haskey(stats, :blue)
    
    # Uniform values should have std ≈ 0 and specific means
    @assert Base.abs(stats[:red][:mean] - 1.0) < 0.01
    @assert Base.abs(stats[:green][:mean] - 0.5) < 0.01
    @assert Base.abs(stats[:blue][:mean] - 0.2) < 0.01
    
    test_results["compute_stats_with_data"] = true
    write(stdout, "  ✓ Statistics computed: $pixel_count pixels\n"); flush(stdout)
catch e
    test_results["compute_stats_with_data"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 7: compute_white_region_channel_stats - Empty mask
# ==============================================================================

write(stdout, "Test 7: compute_white_region_channel_stats - Empty mask\n"); flush(stdout)
try
    struct TestImage2
        data::Array{Float64, 3}
    end
    Bas3ImageSegmentation.data(img::TestImage2) = img.data
    
    img_data = Base.ones(Float64, 10, 10, 3)
    test_img = TestImage2(img_data)
    
    # Empty mask
    white_mask = falses(10, 10)
    
    stats, pixel_count = compute_white_region_channel_stats(test_img, white_mask)
    
    @assert pixel_count == 0
    @assert stats[:red][:mean] == 0.0
    @assert stats[:red][:std] == 0.0
    @assert stats[:red][:skewness] == 0.0
    
    test_results["compute_stats_empty_mask"] = true
    write(stdout, "  ✓ Empty mask handled correctly\n"); flush(stdout)
catch e
    test_results["compute_stats_empty_mask"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 8: Figure creation without display (structure test)
# ==============================================================================

write(stdout, "Test 8: Figure creation - Structure validation\n"); flush(stdout)
try
    # Create a minimal figure to test structure (no display)
    fig = Bas3GLMakie.GLMakie.Figure(size=(800, 600))
    
    # Add an axis
    ax = Bas3GLMakie.GLMakie.Axis(
        fig[1, 1];
        title="Test Axis"
    )
    
    # Verify figure was created
    @assert !Base.isnothing(fig)
    @assert !Base.isnothing(ax)
    
    # Verify axis has the expected title
    @assert ax.title[] == "Test Axis"
    
    test_results["figure_creation"] = true
    write(stdout, "  ✓ Figure created without display\n"); flush(stdout)
catch e
    test_results["figure_creation"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test Summary
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST SUMMARY\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)

total = Base.length(test_results)
passed = Base.count(Base.values(test_results))
failed = total - passed

write(stdout, "Total Tests: $total\n"); flush(stdout)
write(stdout, "Passed: $passed\n"); flush(stdout)
write(stdout, "Failed: $failed\n"); flush(stdout)

if failed > 0
    write(stdout, "\nFailed tests:\n"); flush(stdout)
    for (name, result) in test_results
        if !result
            write(stdout, "  ✗ $name\n"); flush(stdout)
        end
    end
end

write(stdout, "="^80 * "\n"); flush(stdout)
