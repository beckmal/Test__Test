# test_colors.jl
# Tests for Load_Sets__Colors.jl module
# NOTE: Using write(stdout, ...) instead of println to avoid module conflicts after loading packages

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST: Load_Sets__Colors.jl\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)

write(stdout, "Loading real Bas3ImageSegmentation package (may take ~25s)...\n"); flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie

write(stdout, "✓ Packages loaded\n"); flush(stdout)

write(stdout, "Loading module...\n"); flush(stdout)
include("Load_Sets__Colors.jl")
write(stdout, "✓ Module loaded\n\n"); flush(stdout)

test_results = Dict{String, Bool}()

# Test 1: CLASS_COLORS_RGB
write(stdout, "Test 1: CLASS_COLORS_RGB\n"); flush(stdout)
try
    @assert Base.length(CLASS_COLORS_RGB) == 5
    @assert CLASS_COLORS_RGB[1] == Bas3GLMakie.GLMakie.RGBf(0, 1, 0)
    @assert CLASS_COLORS_RGB[3] == :goldenrod
    test_results["CLASS_COLORS_RGB"] = true
    write(stdout, "  ✓ CLASS_COLORS_RGB (5 colors defined)\n"); flush(stdout)
catch e
    test_results["CLASS_COLORS_RGB"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 2: CHANNEL_COLORS_RGB
write(stdout, "Test 2: CHANNEL_COLORS_RGB\n"); flush(stdout)
try
    @assert CHANNEL_COLORS_RGB isa Dict
    @assert CHANNEL_COLORS_RGB[:red] == :red
    @assert CHANNEL_COLORS_RGB[:green] == :green
    @assert CHANNEL_COLORS_RGB[:blue] == :blue
    test_results["CHANNEL_COLORS_RGB"] = true
    write(stdout, "  ✓ CHANNEL_COLORS_RGB (3 channels defined)\n"); flush(stdout)
catch e
    test_results["CHANNEL_COLORS_RGB"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 3: CLASS_NAMES_DE
write(stdout, "Test 3: CLASS_NAMES_DE\n"); flush(stdout)
try
    @assert CLASS_NAMES_DE isa Dict
    @assert CLASS_NAMES_DE[:scar] == "Narbe"
    @assert CLASS_NAMES_DE[:background] == "Hintergrund"
    @assert Base.length(CLASS_NAMES_DE) == 5
    test_results["CLASS_NAMES_DE"] = true
    write(stdout, "  ✓ CLASS_NAMES_DE (5 translations defined)\n"); flush(stdout)
catch e
    test_results["CLASS_NAMES_DE"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 4: CHANNEL_NAMES_DE
write(stdout, "Test 4: CHANNEL_NAMES_DE\n"); flush(stdout)
try
    @assert CHANNEL_NAMES_DE isa Dict
    @assert Base.haskey(CHANNEL_NAMES_DE, :red)
    @assert Base.haskey(CHANNEL_NAMES_DE, :green)
    @assert Base.haskey(CHANNEL_NAMES_DE, :blue)
    test_results["CHANNEL_NAMES_DE"] = true
    write(stdout, "  ✓ CHANNEL_NAMES_DE (3 translations defined)\n"); flush(stdout)
catch e
    test_results["CHANNEL_NAMES_DE"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 5: get_german_class_names function
write(stdout, "Test 5: get_german_class_names()\n"); flush(stdout)
try
    result = get_german_class_names([:scar, :redness])
    @assert Base.length(result) == 2
    @assert result[1] == "Narbe"
    test_results["get_german_class_names"] = true
    write(stdout, "  ✓ get_german_class_names() works\n"); flush(stdout)
catch e
    test_results["get_german_class_names"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 6: get_german_channel_names function
write(stdout, "Test 6: get_german_channel_names()\n"); flush(stdout)
try
    result = get_german_channel_names([:red, :blue])
    @assert Base.length(result) == 2
    test_results["get_german_channel_names"] = true
    write(stdout, "  ✓ get_german_channel_names() works\n"); flush(stdout)
catch e
    test_results["get_german_channel_names"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# Test 7: create_rgba_overlay function
write(stdout, "Test 7: create_rgba_overlay()\n"); flush(stdout)
try
    mask = BitMatrix([1 0; 0 1])
    color = Bas3GLMakie.GLMakie.RGBf(1.0, 0.0, 0.0)
    result = create_rgba_overlay(mask, color, 0.5f0)
    @assert Base.size(result) == (2, 2)
    @assert result[1,1].alpha == 0.5f0
    @assert result[1,2].alpha == 0.0f0
    test_results["create_rgba_overlay"] = true
    write(stdout, "  ✓ create_rgba_overlay() works\n"); flush(stdout)
catch e
    test_results["create_rgba_overlay"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

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
