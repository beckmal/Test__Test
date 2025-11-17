# Load_Sets__InteractiveUI__test_mode.jl
# Basic tests for test_mode functionality

println("="^80)
println("TEST: Load_Sets__InteractiveUI.jl - TEST MODE")
println("="^80)
println()

println("Activating environment...")
include("ENVIRONMENT_ACTIVATE.jl")
println("✓ Environment activated\n")

println("Setting up headless mode...")
# Set environment variable to prevent GLMakie from trying to open a window
ENV["DISPLAY"] = ""
println("✓ Headless mode configured\n")

println("Loading packages...")
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
println("✓ Packages loaded\n")

println("Loading modules...")
include("Load_Sets__ConnectedComponents.jl")
include("Load_Sets__MarkerCorrespondence.jl")
include("Load_Sets__ThinPlateSpline.jl")
include("Load_Sets__InteractiveUI.jl")
println("✓ Modules loaded\n")

# Mock data infrastructure
struct MockImage
    data::Array{Float64, 3}
end

Bas3ImageSegmentation.data(img::MockImage) = img.data
Bas3ImageSegmentation.image(img::MockImage) = 
    Bas3ImageSegmentation.RGB{Float32}.(img.data[:,:,1], img.data[:,:,2], img.data[:,:,3])
Base.size(img::MockImage) = Base.size(img.data)

struct MockOutputType end
Bas3ImageSegmentation.shape(::MockOutputType) = [:scar, :redness, :hematoma, :necrosis, :background]

struct MockInputType end
Bas3ImageSegmentation.shape(::MockInputType) = [:red, :green, :blue]

function create_test_dataset(n_images=2, img_size=(100, 100))
    sets = []
    for i in 1:n_images
        input_data = rand(Float64, img_size[1], img_size[2], 3)
        output_data = zeros(Float64, img_size[1], img_size[2], 5)
        output_data[:, :, 5] .= 1.0
        
        push!(sets, (MockImage(input_data), MockImage(output_data)))
    end
    return sets
end

# Test results storage
test_results = Dict{String, Bool}()

# ==============================================================================
# TEST 1: Production Mode (Backward Compatibility)
# ==============================================================================
println("[TEST 1] Production mode returns Figure only")
try
    sets = create_test_dataset(2)
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    # Verify return type
    @assert fig isa Bas3GLMakie.GLMakie.Figure "Expected Figure object"
    @assert !(fig isa Tuple) "Production mode should not return tuple"
    
    println("✓ PASS: Production mode unchanged")
    test_results["production_mode"] = true
catch e
    println("✗ FAIL: Production mode broken")
    println("  Error: ", e)
    test_results["production_mode"] = false
end
println()

# ==============================================================================
# TEST 2: Test Mode Returns Named Tuple
# ==============================================================================
println("[TEST 2] Test mode returns named tuple")
try
    sets = create_test_dataset(2)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    
    # Verify structure
    @assert hasfield(typeof(result), :figure) "Missing figure field"
    @assert hasfield(typeof(result), :observables) "Missing observables field"
    @assert hasfield(typeof(result), :widgets) "Missing widgets field"
    
    # Verify types
    @assert result.figure isa Bas3GLMakie.GLMakie.Figure "figure not a Figure"
    @assert result.observables isa Dict "observables not a Dict"
    @assert result.widgets isa Dict "widgets not a Dict"
    
    println("✓ PASS: Test mode returns correct structure")
    test_results["test_mode_structure"] = true
catch e
    println("✗ FAIL: Test mode structure incorrect")
    println("  Error: ", e)
    test_results["test_mode_structure"] = false
end
println()

# ==============================================================================
# TEST 3: All Required Observables Present
# ==============================================================================
println("[TEST 3] All required observables present")
try
    sets = create_test_dataset(2)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    obs = result.observables
    
    required_observables = [
        :selection_active, :selection_corner1, :selection_corner2,
        :selection_complete, :selection_rect, :preview_rect,
        :current_markers, :dewarp_success, :dewarp_message,
        :current_dewarped_image, :current_input_image, :current_output_image,
        :current_white_overlay, :current_marker_viz
    ]
    
    missing = []
    for key in required_observables
        if !haskey(obs, key)
            push!(missing, key)
        end
    end
    
    if isempty(missing)
        println("✓ PASS: All 14 observables present")
        test_results["observables_present"] = true
    else
        println("✗ FAIL: Missing observables: ", missing)
        test_results["observables_present"] = false
    end
catch e
    println("✗ FAIL: Observable check failed")
    println("  Error: ", e)
    test_results["observables_present"] = false
end
println()

# ==============================================================================
# TEST 4: All Required Widgets Present
# ==============================================================================
println("[TEST 4] All required widgets present")
try
    sets = create_test_dataset(2)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    widgets = result.widgets
    
    required_widgets = [
        :nav_textbox, :prev_button, :next_button, :textbox_label,
        :selection_toggle, :clear_selection_button, :selection_status_label,
        :threshold_textbox, :min_area_textbox, :aspect_ratio_textbox,
        :aspect_weight_textbox, :kernel_size_textbox,
        :segmentation_toggle
    ]
    
    missing = []
    for key in required_widgets
        if !haskey(widgets, key)
            push!(missing, key)
        end
    end
    
    if isempty(missing)
        println("✓ PASS: All 13 widgets present")
        test_results["widgets_present"] = true
    else
        println("✗ FAIL: Missing widgets: ", missing)
        test_results["widgets_present"] = false
    end
catch e
    println("✗ FAIL: Widget check failed")
    println("  Error: ", e)
    test_results["widgets_present"] = false
end
println()

# ==============================================================================
# TEST 5: Observable Access Works
# ==============================================================================
println("[TEST 5] Observables can be read and modified")
try
    sets = create_test_dataset(2)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    obs = result.observables
    
    # Read initial values
    initial_active = obs[:selection_active][]
    initial_complete = obs[:selection_complete][]
    
    # Modify values
    obs[:selection_active][] = true
    obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(10, 10)
    obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(50, 50)
    
    # Verify modifications
    @assert obs[:selection_active][] == true "Observable modification failed"
    @assert obs[:selection_corner1][] == Bas3GLMakie.GLMakie.Point2f(10, 10) "Corner1 not set"
    @assert obs[:selection_corner2][] == Bas3GLMakie.GLMakie.Point2f(50, 50) "Corner2 not set"
    
    println("✓ PASS: Observables readable and writable")
    test_results["observable_access"] = true
catch e
    println("✗ FAIL: Observable access failed")
    println("  Error: ", e)
    test_results["observable_access"] = false
end
println()

# ==============================================================================
# TEST 6: Widget Manipulation Works
# ==============================================================================
println("[TEST 6] Widgets can be manipulated")
try
    sets = create_test_dataset(2)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    widgets = result.widgets
    
    # Modify textbox
    widgets[:nav_textbox].stored_string[] = "2"
    @assert widgets[:nav_textbox].stored_string[] == "2" "Textbox modification failed"
    
    # Toggle switch
    initial_toggle = widgets[:selection_toggle].active[]
    widgets[:selection_toggle].active[] = !initial_toggle
    @assert widgets[:selection_toggle].active[] == !initial_toggle "Toggle failed"
    
    # Button click (just verify notify works, don't check side effects)
    Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
    
    println("✓ PASS: Widget manipulation works")
    test_results["widget_manipulation"] = true
catch e
    println("✗ FAIL: Widget manipulation failed")
    println("  Error: ", e)
    test_results["widget_manipulation"] = false
end
println()

# ==============================================================================
# Summary
# ==============================================================================
println("="^80)
println("TEST SUMMARY")
println("="^80)

total_tests = length(test_results)
passed_tests = count(values(test_results))

for (test_name, result) in sort(collect(test_results))
    status = result ? "✓ PASS" : "✗ FAIL"
    println("  $status: $test_name")
end

println()
println("Results: $passed_tests / $total_tests tests passed")

if passed_tests == total_tests
    println("✓ ALL TESTS PASSED")
    exit(0)
else
    println("✗ SOME TESTS FAILED")
    exit(1)
end
println("="^80)
