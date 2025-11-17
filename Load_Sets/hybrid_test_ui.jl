# Hybrid UI Test - Displays UI and runs automated tests
# Watch the UI as automated interactions occur, then test manually

println("=== Hybrid UI Test (Automated + Manual) ===\n")

# Load the modular components
include("Load_Sets__Core.jl")

println("Loading test dataset (first 10 images)...")
const test_sets = load_original_sets(10, false)
println("Loaded $(length(test_sets)) image sets\n")

println("Creating interactive figure in test mode...")
const result = create_interactive_figure(test_sets, input_type, raw_output_type; test_mode=true)

println("✓ Figure created successfully\n")

# Access components
obs = result.observables
widgets = result.widgets
fig = result.figure

println("="^70)
println("PART 1: AUTOMATED TESTING")
println("="^70)
println()
println("The UI will now open and automated tests will run.")
println("Watch the UI as it:")
println("  - Navigates between images")
println("  - Changes parameters")
println("  - Enables/disables features")
println()
println("Displaying the interactive figure...")

# Display the figure
screen = display(Bas3GLMakie.GLMakie.Screen(), fig)

# Give window time to render
sleep(2.0)
println("✓ Figure displayed\n")

# Helper function for automated tests
function auto_test(description::String, action::Function, delay::Float64=0.8)
    println("  → $description")
    try
        action()
        sleep(delay)
        current_idx = obs[:current_image_index][]
        println("    ✓ Success (current image: $current_idx)")
        return true
    catch e
        println("    ✗ ERROR: $e")
        return false
    end
end

println("Starting automated tests...\n")
test_results = []

# Test sequence
push!(test_results, auto_test("Navigate to image 2", () -> widgets[:nav_textbox].stored_string[] = "2"))

push!(test_results, auto_test("Change threshold to 0.65 on image 2", () -> widgets[:threshold_textbox].stored_string[] = "0.65"))

push!(test_results, auto_test("Navigate to image 3", () -> widgets[:nav_textbox].stored_string[] = "3"))

push!(test_results, auto_test("Change min area to 9000 on image 3", () -> widgets[:min_area_textbox].stored_string[] = "9000"))

push!(test_results, auto_test("Click next button (→ image 4)", () -> widgets[:next_button].clicks[] += 1))

push!(test_results, auto_test("Change aspect ratio to 4.5 on image 4", () -> widgets[:aspect_ratio_textbox].stored_string[] = "4.5"))

push!(test_results, auto_test("Navigate to image 6", () -> widgets[:nav_textbox].stored_string[] = "6"))

push!(test_results, auto_test("Click prev button (← image 5)", () -> widgets[:prev_button].clicks[] += 1))

push!(test_results, auto_test("Change kernel size to 5 on image 5", () -> widgets[:kernel_size_textbox].stored_string[] = "5"))

push!(test_results, auto_test("Toggle segmentation overlay", () -> begin
    current_state = widgets[:segmentation_toggle].active[]
    widgets[:segmentation_toggle].active[] = !current_state
    sleep(0.3)
    widgets[:segmentation_toggle].active[] = current_state
end))

push!(test_results, auto_test("Navigate to image 7", () -> widgets[:nav_textbox].stored_string[] = "7"))

push!(test_results, auto_test("Enable region selection on image 7", () -> widgets[:selection_toggle].active[] = true))

push!(test_results, auto_test("Set selection corners on image 7", () -> begin
    obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(100, 100)
    sleep(0.2)
    obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(400, 400)
    sleep(0.2)
    obs[:selection_complete][] = true
end, 1.5))

push!(test_results, auto_test("Navigate to image 8 with active selection", () -> widgets[:nav_textbox].stored_string[] = "8"))

push!(test_results, auto_test("Change threshold to 0.8 on image 8", () -> widgets[:threshold_textbox].stored_string[] = "0.8"))

push!(test_results, auto_test("Clear selection on image 8", () -> widgets[:clear_selection_button].clicks[] += 1))

push!(test_results, auto_test("Navigate back to image 1", () -> widgets[:nav_textbox].stored_string[] = "1"))

# Print automated test results
println("\n" * "="^70)
println("AUTOMATED TEST RESULTS")
println("="^70)
total_tests = length(test_results)
passed_tests = sum(test_results)
failed_tests = total_tests - passed_tests

println("Total tests: $total_tests")
println("Passed: $passed_tests")
println("Failed: $failed_tests")

if failed_tests == 0
    println("\n✓✓✓ ALL AUTOMATED TESTS PASSED ✓✓✓")
else
    println("\n✗✗✗ SOME AUTOMATED TESTS FAILED ✗✗✗")
end

# Verify image index tracking
println("\nImage index tracking verification:")
println("  Current index: $(obs[:current_image_index][])")
println("  Expected: 1")
if obs[:current_image_index][] == 1
    println("  ✓ Correct")
else
    println("  ✗ Incorrect")
end

println("\n" * "="^70)
println("PART 2: MANUAL TESTING")
println("="^70)
println()
println("The automated tests have completed.")
println("The UI is still open for manual testing.")
println()
println("Please try these manual tests:")
println()
println("1. STRESS TEST - Rapid Navigation")
println("   → Quickly click 'Next' and 'Previous' multiple times")
println("   → Type different image numbers rapidly")
println("   → Change parameters while navigating")
println()
println("2. ORIGINAL BUG SCENARIO")
println("   → Navigate to image 1")
println("   → Navigate to image 2, 3, or higher")
println("   → Click buttons and change parameters")
println("   → Use region selection")
println("   → If it doesn't crash, the fix works!")
println()
println("3. EDGE CASES")
println("   → Navigate to first image (1)")
println("   → Navigate to last image (10)")
println("   → Try invalid inputs (0, 11, abc, etc.)")
println()
println("="^70)
println()
println("The window will remain open for manual testing.")
println("When done, close the window or press Ctrl+C to exit.")
println()
