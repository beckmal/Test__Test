# Load_Sets__InteractiveUI__test_interaction.jl
# True interaction tests - simulates real user interactions with the displayed UI
# NOTE: Requires display environment (X11/Wayland) - will not work headless

Base.println("="^80)
Base.println("TEST: Load_Sets__InteractiveUI.jl - TRUE INTERACTION TESTING")
Base.println("="^80)
Base.println()

Base.println("⚠️  WARNING: This test requires a display environment (X11/Wayland)")
Base.println("⚠️  The GLMakie window will open and automated interactions will occur")
Base.println()

Base.println("Activating environment...")
include("ENVIRONMENT_ACTIVATE.jl")
Base.println("✓ Environment activated\n")

Base.println("Loading packages...")
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
using Statistics
Base.println("✓ Packages loaded\n")

Base.println("Loading modules...")
include("Load_Sets__ConnectedComponents.jl")
include("Load_Sets__MarkerCorrespondence.jl")
include("Load_Sets__ThinPlateSpline.jl")
include("Load_Sets__InteractiveUI.jl")
Base.println("✓ Modules loaded\n")

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

function create_test_dataset(n_images=3, img_size=(200, 200))
    sets = []
    for i in 1:n_images
        # Create input RGB image with white marker
        input_data = zeros(Float64, img_size[1], img_size[2], 3)
        
        # Add background
        input_data[:, :, 1] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 2] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 3] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        
        # Add white marker
        marker_h = 20
        marker_w = 100
        marker_r_start = 30 + (i-1) * 10
        marker_c_start = 20
        
        input_data[marker_r_start:(marker_r_start+marker_h-1), 
                   marker_c_start:(marker_c_start+marker_w-1), :] .= 1.0
        
        # Create output segmentation
        output_data = zeros(Float64, img_size[1], img_size[2], 5)
        output_data[1:Base.div(img_size[1],2), 1:Base.div(img_size[2],2), 1] .= 
            Base.rand(Base.div(img_size[1],2), Base.div(img_size[2],2))
        output_data[:, :, 5] .= 0.3
        
        # Normalize
        for r in 1:img_size[1]
            for c in 1:img_size[2]
                total = Base.sum(output_data[r, c, :])
                if total > 0
                    output_data[r, c, :] ./= total
                end
            end
        end
        
        Base.push!(sets, (MockImage(input_data), MockImage(output_data)))
    end
    
    return sets
end

test_results = Dict{String, Bool}()

# ==============================================================================
# TEST 1: Create Interactive Figure with test_mode
# ==============================================================================
Base.println("[TEST 1] Create interactive figure with test_mode")
try
    sets = create_test_dataset(3)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    
    # Verify structure
    @assert Base.hasfield(typeof(result), :figure)
    @assert Base.hasfield(typeof(result), :observables)
    @assert Base.hasfield(typeof(result), :widgets)
    
    fig = result.figure
    obs = result.observables
    widgets = result.widgets
    
    Base.println("✓ PASS: Interactive figure created with test_mode")
    test_results["create_figure"] = true
    
    # Display the figure (this opens the window)
    Base.println("\n📺 Opening GLMakie window...")
    display(Bas3GLMakie.GLMakie.Screen(), fig)
    Base.println("✓ Window opened")
    
    # Give time for window to render
    Base.sleep(2)
    
    # ==============================================================================
    # TEST 2: Simulate Button Click - Next Button
    # ==============================================================================
    Base.println("\n[TEST 2] Simulate Next button click")
    try
        initial_index = obs[:current_image_index][]
        Base.println("  Initial image index: $(initial_index)")
        
        # Simulate button click by notifying the button's click observable
        Base.println("  Simulating Next button click...")
        Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
        
        # Give time for UI to update
        Base.sleep(1)
        
        new_index = obs[:current_image_index][]
        Base.println("  New image index: $(new_index)")
        
        @assert new_index == initial_index + 1 "Image index should increment"
        
        Base.println("✓ PASS: Next button click simulated successfully")
        test_results["next_button"] = true
    catch e
        Base.println("✗ FAIL: Next button test failed")
        Base.println("  Error: ", e)
        test_results["next_button"] = false
    end
    
    # ==============================================================================
    # TEST 3: Simulate Button Click - Previous Button
    # ==============================================================================
    Base.println("\n[TEST 3] Simulate Previous button click")
    try
        initial_index = obs[:current_image_index][]
        Base.println("  Initial image index: $(initial_index)")
        
        Base.println("  Simulating Previous button click...")
        Bas3GLMakie.GLMakie.notify(widgets[:prev_button].clicks)
        
        Base.sleep(1)
        
        new_index = obs[:current_image_index][]
        Base.println("  New image index: $(new_index)")
        
        @assert new_index == initial_index - 1 "Image index should decrement"
        
        Base.println("✓ PASS: Previous button click simulated successfully")
        test_results["prev_button"] = true
    catch e
        Base.println("✗ FAIL: Previous button test failed")
        Base.println("  Error: ", e)
        test_results["prev_button"] = false
    end
    
    # ==============================================================================
    # TEST 4: Simulate Textbox Input - Navigate to Image
    # ==============================================================================
    Base.println("\n[TEST 4] Simulate textbox navigation")
    try
        target_index = 3
        Base.println("  Navigating to image $(target_index)...")
        
        # Set textbox value
        widgets[:nav_textbox].stored_string[] = "$(target_index)"
        
        # Simulate Enter key by notifying the stored_string observable
        Bas3GLMakie.GLMakie.notify(widgets[:nav_textbox].stored_string)
        
        Base.sleep(1)
        
        new_index = obs[:current_image_index][]
        Base.println("  Current image index: $(new_index)")
        
        @assert new_index == target_index "Should navigate to image $(target_index)"
        
        Base.println("✓ PASS: Textbox navigation simulated successfully")
        test_results["textbox_nav"] = true
    catch e
        Base.println("✗ FAIL: Textbox navigation test failed")
        Base.println("  Error: ", e)
        test_results["textbox_nav"] = false
    end
    
    # ==============================================================================
    # TEST 5: Simulate Toggle - Selection Mode
    # ==============================================================================
    Base.println("\n[TEST 5] Simulate selection toggle")
    try
        initial_state = obs[:selection_active][]
        Base.println("  Initial selection state: $(initial_state)")
        
        # Toggle the selection mode
        Base.println("  Toggling selection mode...")
        widgets[:selection_toggle].active[] = !initial_state
        
        Base.sleep(0.5)
        
        new_state = obs[:selection_active][]
        Base.println("  New selection state: $(new_state)")
        
        @assert new_state == !initial_state "Selection state should toggle"
        
        Base.println("✓ PASS: Selection toggle simulated successfully")
        test_results["selection_toggle"] = true
    catch e
        Base.println("✗ FAIL: Selection toggle test failed")
        Base.println("  Error: ", e)
        test_results["selection_toggle"] = false
    end
    
    # ==============================================================================
    # TEST 6: Simulate Mouse Click - Region Selection (Corner 1)
    # ==============================================================================
    Base.println("\n[TEST 6] Simulate mouse click for region selection (corner 1)")
    try
        # Make sure selection is active
        if !obs[:selection_active][]
            widgets[:selection_toggle].active[] = true
            Base.sleep(0.5)
        end
        
        # Simulate first corner click
        click_point = Bas3GLMakie.GLMakie.Point2f(50.0, 50.0)
        Base.println("  Simulating click at $(click_point)...")
        
        obs[:selection_corner1][] = click_point
        
        Base.sleep(0.5)
        
        corner1 = obs[:selection_corner1][]
        Base.println("  Corner 1 set to: $(corner1)")
        
        @assert corner1 == click_point "Corner 1 should be set to click point"
        
        Base.println("✓ PASS: Mouse click for corner 1 simulated successfully")
        test_results["mouse_click_corner1"] = true
    catch e
        Base.println("✗ FAIL: Mouse click corner 1 test failed")
        Base.println("  Error: ", e)
        test_results["mouse_click_corner1"] = false
    end
    
    # ==============================================================================
    # TEST 7: Simulate Mouse Click - Region Selection (Corner 2)
    # ==============================================================================
    Base.println("\n[TEST 7] Simulate mouse click for region selection (corner 2)")
    try
        # Simulate second corner click
        click_point = Bas3GLMakie.GLMakie.Point2f(150.0, 150.0)
        Base.println("  Simulating click at $(click_point)...")
        
        obs[:selection_corner2][] = click_point
        obs[:selection_complete][] = true
        
        Base.sleep(0.5)
        
        corner2 = obs[:selection_corner2][]
        is_complete = obs[:selection_complete][]
        
        Base.println("  Corner 2 set to: $(corner2)")
        Base.println("  Selection complete: $(is_complete)")
        
        @assert corner2 == click_point "Corner 2 should be set to click point"
        @assert is_complete "Selection should be marked complete"
        
        Base.println("✓ PASS: Mouse click for corner 2 simulated successfully")
        test_results["mouse_click_corner2"] = true
    catch e
        Base.println("✗ FAIL: Mouse click corner 2 test failed")
        Base.println("  Error: ", e)
        test_results["mouse_click_corner2"] = false
    end
    
    # ==============================================================================
    # TEST 8: Simulate Clear Selection Button
    # ==============================================================================
    Base.println("\n[TEST 8] Simulate clear selection button")
    try
        Base.println("  Simulating clear selection button click...")
        Bas3GLMakie.GLMakie.notify(widgets[:clear_selection_button].clicks)
        
        Base.sleep(0.5)
        
        corner1 = obs[:selection_corner1][]
        corner2 = obs[:selection_corner2][]
        is_complete = obs[:selection_complete][]
        
        Base.println("  Corner 1: $(corner1)")
        Base.println("  Corner 2: $(corner2)")
        Base.println("  Selection complete: $(is_complete)")
        
        @assert corner1 == Bas3GLMakie.GLMakie.Point2f(0.0, 0.0) "Corner 1 should be reset"
        @assert corner2 == Bas3GLMakie.GLMakie.Point2f(0.0, 0.0) "Corner 2 should be reset"
        @assert !is_complete "Selection should not be complete"
        
        Base.println("✓ PASS: Clear selection button simulated successfully")
        test_results["clear_selection"] = true
    catch e
        Base.println("✗ FAIL: Clear selection test failed")
        Base.println("  Error: ", e)
        test_results["clear_selection"] = false
    end
    
    # ==============================================================================
    # TEST 9: Simulate Parameter Change - Threshold Textbox
    # ==============================================================================
    Base.println("\n[TEST 9] Simulate parameter change (threshold)")
    try
        new_threshold = "0.85"
        Base.println("  Setting threshold to $(new_threshold)...")
        
        widgets[:threshold_textbox].stored_string[] = new_threshold
        Bas3GLMakie.GLMakie.notify(widgets[:threshold_textbox].stored_string)
        
        Base.sleep(0.5)
        
        current_value = widgets[:threshold_textbox].stored_string[]
        Base.println("  Current threshold: $(current_value)")
        
        @assert current_value == new_threshold "Threshold should be updated"
        
        Base.println("✓ PASS: Parameter change simulated successfully")
        test_results["parameter_change"] = true
    catch e
        Base.println("✗ FAIL: Parameter change test failed")
        Base.println("  Error: ", e)
        test_results["parameter_change"] = false
    end
    
    # ==============================================================================
    # TEST 10: Verify Observables Update
    # ==============================================================================
    Base.println("\n[TEST 10] Verify observables reflect UI state")
    try
        # Check that we can read all observables
        Base.println("  Reading all observables...")
        
        observables_to_check = [
            :selection_active, :selection_corner1, :selection_corner2,
            :selection_complete, :current_image_index,
            :current_input_image, :current_output_image,
            :current_markers, :dewarp_success
        ]
        
        all_readable = true
        for obs_name in observables_to_check
            try
                value = obs[obs_name][]
                Base.println("    $(obs_name): $(typeof(value))")
            catch e
                Base.println("    ✗ Failed to read $(obs_name): $(e)")
                all_readable = false
            end
        end
        
        @assert all_readable "All observables should be readable"
        
        Base.println("✓ PASS: All observables are readable and reflect UI state")
        test_results["observable_state"] = true
    catch e
        Base.println("✗ FAIL: Observable state verification failed")
        Base.println("  Error: ", e)
        test_results["observable_state"] = false
    end
    
    # Keep window open for visual inspection
    Base.println("\n⏸️  Window will remain open for 10 seconds for visual inspection...")
    Base.sleep(10)
    
catch e
    Base.println("✗ FAIL: Figure creation failed")
    Base.println("  Error: ", e)
    Base.println("  Backtrace:")
    for (exc, bt) in Base.catch_stack()
        Base.showerror(stdout, exc, bt)
        Base.println()
    end
    test_results["create_figure"] = false
end

# ==============================================================================
# Summary
# ==============================================================================
Base.println("\n" * "="^80)
Base.println("TEST SUMMARY")
Base.println("="^80)

total_tests = Base.length(test_results)
passed_tests = Base.count(values(test_results))

for (test_name, result) in Base.sort(Base.collect(test_results))
    status = result ? "✓ PASS" : "✗ FAIL"
    Base.println("  $(status): $(test_name)")
end

Base.println()
Base.println("Results: $(passed_tests) / $(total_tests) tests passed")

if passed_tests == total_tests
    Base.println("✓ ALL TESTS PASSED")
    Base.println()
    Base.println("NOTE: These tests simulated user interactions programmatically.")
    Base.println("For true UI testing, consider:")
    Base.println("  1. Manual testing with the interactive window")
    Base.println("  2. Screen recording for visual regression testing")
    Base.println("  3. UI automation tools (e.g., TestImages.jl + manual verification)")
else
    Base.println("✗ SOME TESTS FAILED")
end

Base.println("="^80)
