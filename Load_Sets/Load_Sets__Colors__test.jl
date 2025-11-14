# test_colors.jl
# Tests for Load_Sets__Colors.jl module

"""
    Test Suite: Color Definitions and Translations
    
Tests for:
- Color constant definitions
- German class name translations
- German channel name translations
- Translation lookup functions
"""

println("="^80)
println("TEST: Load_Sets__Colors.jl")
println("="^80)
println()

# ============================================================================
# Setup
# ============================================================================

println("Loading module...")
include("Load_Sets__Colors.jl")
println("✓ Module loaded\n")

# ============================================================================
# Test 1: Class Color Definitions
# ============================================================================

println("Test 1: Class Color Definitions")
println("─"^80)

test_results = Dict{String, Bool}()

# Test 1.1: All class colors defined
test_name = "All Class Colors Defined"
expected_classes = [:background, :granulation, :necrosis, :slough, :black]
try
    for class_name in expected_classes
        @assert haskey(class_colors, class_name) "$class_name color not defined"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
    for class_name in expected_classes
        println("    $class_name: $(class_colors[class_name])")
    end
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

# Test 1.2: Colors are 3-tuples of Floats
test_name = "Colors Are Float64 Tuples"
try
    for (class_name, color) in class_colors
        @assert color isa Tuple{Float64, Float64, Float64} "$class_name color is not Float64 tuple"
        @assert all(0.0 .<= color .<= 1.0) "$class_name color values not in [0, 1]"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

# Test 1.3: Colors are visually distinct
test_name = "Colors Are Distinct"
try
    colors_list = collect(values(class_colors))
    num_unique = length(unique(colors_list))
    @assert num_unique == length(colors_list) "Duplicate colors detected"
    test_results[test_name] = true
    println("  ✓ $test_name: $num_unique unique colors")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 2: Channel Color Definitions
# ============================================================================

println("Test 2: Channel Color Definitions")
println("─"^80)

test_name = "All Channel Colors Defined"
expected_channels = [:red, :green, :blue]
try
    for channel in expected_channels
        @assert haskey(channel_colors, channel) "$channel color not defined"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
    for channel in expected_channels
        println("    $channel: $(channel_colors[channel])")
    end
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Channel Colors Match Expected RGB"
try
    @assert channel_colors[:red] == (1.0, 0.0, 0.0) "Red channel color incorrect"
    @assert channel_colors[:green] == (0.0, 1.0, 0.0) "Green channel color incorrect"
    @assert channel_colors[:blue] == (0.0, 0.0, 1.0) "Blue channel color incorrect"
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 3: German Class Translations
# ============================================================================

println("Test 3: German Class Translations")
println("─"^80)

test_name = "All Class Translations Defined"
try
    for class_name in expected_classes
        @assert haskey(class_names_german, class_name) "$class_name German translation missing"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
    for class_name in expected_classes
        println("    $class_name → $(class_names_german[class_name])")
    end
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Translations Are Non-Empty Strings"
try
    for (key, value) in class_names_german
        @assert value isa String "$key translation is not a String"
        @assert !isempty(value) "$key translation is empty"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Translations Are Capitalized"
try
    for (key, value) in class_names_german
        @assert isuppercase(first(value)) "$key translation not capitalized: $value"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 4: German Channel Translations
# ============================================================================

println("Test 4: German Channel Translations")
println("─"^80)

test_name = "All Channel Translations Defined"
try
    for channel in expected_channels
        @assert haskey(channel_names_german, channel) "$channel German translation missing"
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
    for channel in expected_channels
        println("    $channel → $(channel_names_german[channel])")
    end
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Channel Translations Match Expected"
try
    @assert channel_names_german[:red] == "Rot" "Red translation incorrect"
    @assert channel_names_german[:green] == "Grün" "Green translation incorrect"
    @assert channel_names_german[:blue] == "Blau" "Blue translation incorrect"
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 5: Lookup Consistency
# ============================================================================

println("Test 5: Cross-Reference Consistency")
println("─"^80)

test_name = "Class Colors and Translations Aligned"
try
    colors_keys = Set(keys(class_colors))
    translations_keys = Set(keys(class_names_german))
    @assert colors_keys == translations_keys "Class color keys don't match translation keys"
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Channel Colors and Translations Aligned"
try
    colors_keys = Set(keys(channel_colors))
    translations_keys = Set(keys(channel_names_german))
    @assert colors_keys == translations_keys "Channel color keys don't match translation keys"
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 6: Color Value Ranges
# ============================================================================

println("Test 6: Color Value Ranges")
println("─"^80)

test_name = "All Color Values In Valid Range [0, 1]"
try
    for (name, color) in class_colors
        for (i, component) in enumerate(color)
            @assert 0.0 <= component <= 1.0 "$name color component $i out of range: $component"
        end
    end
    for (name, color) in channel_colors
        for (i, component) in enumerate(color)
            @assert 0.0 <= component <= 1.0 "$name color component $i out of range: $component"
        end
    end
    test_results[test_name] = true
    println("  ✓ $test_name")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Test 7: Specific Color Expectations
# ============================================================================

println("Test 7: Expected Color Values")
println("─"^80)

test_name = "Background Is Gray"
try
    bg_color = class_colors[:background]
    # Background should be some shade of gray (R ≈ G ≈ B)
    @assert abs(bg_color[1] - bg_color[2]) < 0.1 "Background not gray-ish"
    @assert abs(bg_color[2] - bg_color[3]) < 0.1 "Background not gray-ish"
    test_results[test_name] = true
    println("  ✓ $test_name: $(bg_color)")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

test_name = "Granulation Is Pinkish-Red"
try
    gran_color = class_colors[:granulation]
    # Granulation should be pinkish/reddish (high R component)
    @assert gran_color[1] > 0.5 "Granulation color not red enough"
    test_results[test_name] = true
    println("  ✓ $test_name: $(gran_color)")
catch e
    test_results[test_name] = false
    println("  ✗ $test_name: $e")
end

println()

# ============================================================================
# Summary
# ============================================================================

println("="^80)
println("TEST SUMMARY")
println("="^80)
println()

total = length(test_results)
passed = count(values(test_results))
failed = total - passed

println("Total Tests: $total")
println("Passed: $passed")
println("Failed: $failed")
println("Success Rate: $(round(100 * passed / total, digits=2))%")
println()

if failed > 0
    println("Failed Tests:")
    for (name, result) in test_results
        if !result
            println("  ✗ $name")
        end
    end
    println()
end

println("="^80)
println()

# Return exit code
exit(failed == 0 ? 0 : 1)
