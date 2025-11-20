# Load_Sets__InteractiveUI__test_real_clicks.jl
# Automated test that simulates real button clicks as closely as possible
# - Displays the actual interactive figure
# - Uses GLMakie's button click notification (closest to real clicks)
# - Verifies UI state changes
# - Keeps window open for visual inspection

Base.println("="^80)
Base.println("AUTOMATED TEST: Real Button Click Simulation")
Base.println("="^80)
Base.println()

Base.println("⚠️  This test will:")
Base.println("  1. Open the interactive GLMakie window")
Base.println("  2. Automatically simulate button clicks")
Base.println("  3. Verify the UI responds correctly")
Base.println("  4. Keep window open for visual inspection")
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

function create_test_dataset(n_images=5, img_size=(200, 200))
    Base.println("Creating test dataset with $(n_images) images...")
    sets = []
    
    for i in 1:n_images
        # Create varied input images so we can see they're different
        input_data = zeros(Float64, img_size[1], img_size[2], 3)
        
        # Different background colors for each image
        base_r = 0.1 + (i-1) * 0.1
        base_g = 0.2 + (i-1) * 0.05
        base_b = 0.15 + (i-1) * 0.08
        
        input_data[:, :, 1] .= base_r .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 2] .= base_g .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 3] .= base_b .+ 0.1 .* Base.rand(img_size...)
        
        # Add white marker at different positions
        marker_h = 20
        marker_w = 100
        marker_r_start = 30 + (i-1) * 15
        marker_c_start = 20 + (i-1) * 10
        
        # Keep marker in bounds
        if marker_r_start + marker_h > img_size[1]
            marker_r_start = 30
        end
        if marker_c_start + marker_w > img_size[2]
            marker_c_start = 20
        end
        
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
    
    Base.println("✓ Created $(n_images) test images\n")
    return sets
end

# Test results tracking
test_results = Dict{String, Bool}()
test_details = Dict{String, String}()

# Create test dataset
const N_IMAGES = 5
sets = create_test_dataset(N_IMAGES)

Base.println("="^80)
Base.println("Creating Interactive Figure with test_mode=true")
Base.println("="^80)
Base.println()

result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)

fig = result.figure
obs = result.observables
widgets = result.widgets

Base.println("✓ Interactive figure created\n")

# Display the figure - THIS IS THE KEY STEP
Base.println("📺 Opening GLMakie window...")
Base.println("   (You should see the interactive UI window open)")
Base.println()
display(Bas3GLMakie.GLMakie.Screen(), fig)

# Give window time to fully render
Base.println("⏳ Waiting 2 seconds for window to render...")
Base.sleep(2)
Base.println("✓ Window should now be visible\n")

# ==============================================================================
# TEST 1: Initial State Verification
# ==============================================================================
Base.println("="^80)
Base.println("TEST 1: Verify Initial State")
Base.println("="^80)

try
    initial_idx = obs[:current_image_index][]
    textbox_value = widgets[:nav_textbox].stored_string[]
    
    Base.println("Initial image index: $(initial_idx)")
    Base.println("Textbox shows: $(textbox_value)")
    
    @assert initial_idx == 1 "Should start at image 1"
    @assert textbox_value == "1" "Textbox should show '1'"
    
    test_results["initial_state"] = true
    test_details["initial_state"] = "Started at image 1"
    Base.println("✓ PASS: Initial state correct\n")
catch e
    test_results["initial_state"] = false
    test_details["initial_state"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

Base.sleep(1)

# ==============================================================================
# TEST 2: Simulate Next Button Click
# ==============================================================================
Base.println("="^80)
Base.println("TEST 2: Simulate Next Button Click")
Base.println("="^80)

try
    initial_idx = obs[:current_image_index][]
    Base.println("Before click: Image $(initial_idx)")
    
    # Simulate button click by notifying the clicks observable
    Base.println("🖱️  Simulating Next button click...")
    Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
    
    # Give time for UI to update
    Base.println("⏳ Waiting for UI to update...")
    Base.sleep(2)
    
    new_idx = obs[:current_image_index][]
    textbox_value = widgets[:nav_textbox].stored_string[]
    
    Base.println("After click: Image $(new_idx)")
    Base.println("Textbox shows: $(textbox_value)")
    
    @assert new_idx == initial_idx + 1 "Image should advance by 1"
    @assert textbox_value == "$(new_idx)" "Textbox should update"
    
    test_results["next_button"] = true
    test_details["next_button"] = "Advanced from $(initial_idx) to $(new_idx)"
    Base.println("✓ PASS: Next button works!\n")
catch e
    test_results["next_button"] = false
    test_details["next_button"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
    Base.showerror(stdout, e, Base.catch_backtrace())
    Base.println()
end

Base.sleep(1)

# ==============================================================================
# TEST 3: Simulate Multiple Next Clicks
# ==============================================================================
Base.println("="^80)
Base.println("TEST 3: Simulate Multiple Next Button Clicks")
Base.println("="^80)

try
    start_idx = obs[:current_image_index][]
    Base.println("Starting at image: $(start_idx)")
    
    for i in 1:2
        Base.println("\n🖱️  Click $(i): Pressing Next button...")
        Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
        Base.sleep(2)
        
        current_idx = obs[:current_image_index][]
        Base.println("   → Now at image $(current_idx)")
    end
    
    final_idx = obs[:current_image_index][]
    expected_idx = Base.min(start_idx + 2, N_IMAGES)
    
    Base.println("\nFinal image: $(final_idx) (expected: $(expected_idx))")
    
    @assert final_idx == expected_idx "Should be at image $(expected_idx)"
    
    test_results["multiple_next"] = true
    test_details["multiple_next"] = "Advanced from $(start_idx) to $(final_idx)"
    Base.println("✓ PASS: Multiple Next clicks work!\n")
catch e
    test_results["multiple_next"] = false
    test_details["multiple_next"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

Base.sleep(1)

# ==============================================================================
# TEST 4: Simulate Previous Button Click
# ==============================================================================
Base.println("="^80)
Base.println("TEST 4: Simulate Previous Button Click")
Base.println("="^80)

try
    initial_idx = obs[:current_image_index][]
    Base.println("Before click: Image $(initial_idx)")
    
    if initial_idx > 1
        Base.println("🖱️  Simulating Previous button click...")
        Bas3GLMakie.GLMakie.notify(widgets[:prev_button].clicks)
        
        Base.println("⏳ Waiting for UI to update...")
        Base.sleep(2)
        
        new_idx = obs[:current_image_index][]
        textbox_value = widgets[:nav_textbox].stored_string[]
        
        Base.println("After click: Image $(new_idx)")
        Base.println("Textbox shows: $(textbox_value)")
        
        @assert new_idx == initial_idx - 1 "Image should go back by 1"
        @assert textbox_value == "$(new_idx)" "Textbox should update"
        
        test_results["prev_button"] = true
        test_details["prev_button"] = "Went back from $(initial_idx) to $(new_idx)"
        Base.println("✓ PASS: Previous button works!\n")
    else
        Base.println("⚠️  Skipping (already at first image)")
        test_results["prev_button"] = true
        test_details["prev_button"] = "Skipped (at image 1)"
        Base.println("✓ PASS: Correctly at first image\n")
    end
catch e
    test_results["prev_button"] = false
    test_details["prev_button"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

Base.sleep(1)

# ==============================================================================
# TEST 5: Textbox Navigation
# ==============================================================================
Base.println("="^80)
Base.println("TEST 5: Textbox Navigation (Type and Enter)")
Base.println("="^80)

try
    target_idx = 1  # Go back to first image
    Base.println("Target image: $(target_idx)")
    
    Base.println("⌨️  Typing '$(target_idx)' in textbox...")
    widgets[:nav_textbox].stored_string[] = "$(target_idx)"
    
    Base.println("↵  Simulating Enter key (notify observable)...")
    Bas3GLMakie.GLMakie.notify(widgets[:nav_textbox].stored_string)
    
    Base.println("⏳ Waiting for UI to update...")
    Base.sleep(2)
    
    new_idx = obs[:current_image_index][]
    Base.println("Current image: $(new_idx)")
    
    @assert new_idx == target_idx "Should navigate to image $(target_idx)"
    
    test_results["textbox_nav"] = true
    test_details["textbox_nav"] = "Navigated to image $(target_idx)"
    Base.println("✓ PASS: Textbox navigation works!\n")
catch e
    test_results["textbox_nav"] = false
    test_details["textbox_nav"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

Base.sleep(1)

# ==============================================================================
# TEST 6: Selection Toggle
# ==============================================================================
Base.println("="^80)
Base.println("TEST 6: Selection Mode Toggle")
Base.println("="^80)

try
    initial_state = obs[:selection_active][]
    Base.println("Selection active: $(initial_state)")
    
    Base.println("🖱️  Clicking selection toggle...")
    widgets[:selection_toggle].active[] = !initial_state
    
    Base.sleep(1)
    
    new_state = obs[:selection_active][]
    Base.println("Selection active: $(new_state)")
    
    @assert new_state == !initial_state "Toggle should change state"
    
    test_results["selection_toggle"] = true
    test_details["selection_toggle"] = "Toggled from $(initial_state) to $(new_state)"
    Base.println("✓ PASS: Selection toggle works!\n")
catch e
    test_results["selection_toggle"] = false
    test_details["selection_toggle"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

Base.sleep(1)

# ==============================================================================
# TEST 7: Full Navigation Cycle
# ==============================================================================
Base.println("="^80)
Base.println("TEST 7: Full Navigation Cycle (1→2→3→2→1)")
Base.println("="^80)

try
    Base.println("🖱️  Clicking Next 2 times to reach image 3...")
    Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
    Base.sleep(1.5)
    Bas3GLMakie.GLMakie.notify(widgets[:next_button].clicks)
    Base.sleep(1.5)
    
    idx_at_3 = obs[:current_image_index][]
    Base.println("   → At image $(idx_at_3)")
    
    Base.println("🖱️  Clicking Previous 1 time to reach image 2...")
    Bas3GLMakie.GLMakie.notify(widgets[:prev_button].clicks)
    Base.sleep(1.5)
    
    idx_at_2 = obs[:current_image_index][]
    Base.println("   → At image $(idx_at_2)")
    
    Base.println("🖱️  Clicking Previous 1 time to reach image 1...")
    Bas3GLMakie.GLMakie.notify(widgets[:prev_button].clicks)
    Base.sleep(1.5)
    
    final_idx = obs[:current_image_index][]
    Base.println("   → At image $(final_idx)")
    
    @assert idx_at_3 == 3 "Should reach image 3"
    @assert idx_at_2 == 2 "Should be at image 2"
    @assert final_idx == 1 "Should return to image 1"
    
    test_results["full_cycle"] = true
    test_details["full_cycle"] = "Successfully navigated: 1→3→2→1"
    Base.println("✓ PASS: Full navigation cycle works!\n")
catch e
    test_results["full_cycle"] = false
    test_details["full_cycle"] = "Error: $(e)"
    Base.println("✗ FAIL: $(e)\n")
end

# ==============================================================================
# VISUAL INSPECTION PERIOD
# ==============================================================================
Base.println("="^80)
Base.println("VISUAL INSPECTION")
Base.println("="^80)
Base.println()
Base.println("The GLMakie window should still be open.")
Base.println("You can now manually:")
Base.println("  • Click the Next/Previous buttons with your mouse")
Base.println("  • Type numbers in the textbox and press Enter")
Base.println("  • Toggle selection mode")
Base.println("  • Make region selections if toggle is on")
Base.println()
Base.println("Window will remain open for 15 seconds...")
Base.println("(You can close it manually if you're done sooner)")
Base.println()

Base.sleep(15)

# ==============================================================================
# TEST SUMMARY
# ==============================================================================
Base.println("\n" * "="^80)
Base.println("TEST SUMMARY")
Base.println("="^80)
Base.println()

total_tests = Base.length(test_results)
passed_tests = Base.count(values(test_results))
failed_tests = total_tests - passed_tests

Base.println("Results: $(passed_tests) / $(total_tests) tests passed")
Base.println()

# Print detailed results
for (test_name, result) in Base.sort(Base.collect(test_results))
    status = result ? "✓ PASS" : "✗ FAIL"
    detail = test_details[test_name]
    Base.println("  $(status): $(test_name)")
    Base.println("           $(detail)")
end

Base.println()
Base.println("="^80)

if passed_tests == total_tests
    Base.println("✅ ALL TESTS PASSED")
    Base.println()
    Base.println("The interactive UI buttons are working correctly!")
    Base.println("Button clicks successfully:")
    Base.println("  • Advance to next image")
    Base.println("  • Go back to previous image")
    Base.println("  • Update the textbox display")
    Base.println("  • Change the current image index")
else
    Base.println("⚠️  SOME TESTS FAILED ($(failed_tests) failed)")
    Base.println()
    Base.println("Check the error messages above for details.")
    Base.println("Common issues:")
    Base.println("  • Namespace conflicts (string, minmax, etc.)")
    Base.println("  • update_image_display_internal errors")
    Base.println("  • Observable update failures")
end

Base.println("="^80)
Base.println()
Base.println("Note: This test simulates button clicks by notifying GLMakie's")
Base.println("      click observables, which is the closest possible simulation")
Base.println("      to real mouse clicks without OS-level automation tools.")
Base.println()
