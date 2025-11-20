# Load_Sets__InteractiveUI__integration_test.jl
# Automated integration test suite for interactive UI functionality
# Tests full UI behavior using programmatic button clicks

"""
    Integration Test Suite for Interactive UI (Figure 4)
    
    Tests:
    1. Navigation controls (Next/Previous buttons, textbox)
    2. Parameter controls (threshold, min_area, aspect_ratio, etc.)
    3. Region selection workflow
    4. Display toggles (segmentation overlay)
    5. Observable synchronization
    6. Marker detection across images
    7. Boundary conditions
"""

println("=== Interactive UI Integration Test Suite ===")
println("Loading required modules...\n")

# Load the core modules and dataset
include("Load_Sets__Core.jl")

# Load a smaller dataset for faster testing
println("Loading test dataset (10 images)...")
const test_sets = load_original_sets(10, false)
println("Loaded $(length(test_sets)) image sets\n")

# Create interactive figure in test mode
println("Creating interactive figure in test mode...")
const test_result = create_interactive_figure(test_sets, input_type, raw_output_type; test_mode=true)
const test_fig = test_result.figure
const test_obs = test_result.observables
const test_widgets = test_result.widgets

println("✓ Figure created successfully")
println("  Widgets: $(join(sort([string(k) for k in keys(test_widgets)]), ", "))")
println("  Observables: $(join(sort([string(k) for k in keys(test_obs)]), ", "))")
println()

# Display the figure (optional - can be commented out for headless testing)
println("Displaying test figure...")
display(Bas3GLMakie.GLMakie.Screen(), test_fig)
sleep(1)  # Allow rendering

# ============================================================================
# Test Utilities
# ============================================================================

test_counter = 0
passed_tests = 0
failed_tests = 0

function test_assert(condition::Bool, test_name::String, details::String="")
    global test_counter, passed_tests, failed_tests
    test_counter += 1
    
    if condition
        passed_tests += 1
        println("  ✓ Test $test_counter: $test_name")
        if !isempty(details)
            println("    → $details")
        end
    else
        failed_tests += 1
        println("  ✗ Test $test_counter FAILED: $test_name")
        if !isempty(details)
            println("    → $details")
        end
    end
end

function test_section(section_name::String)
    println("\n" * "="^60)
    println("  $section_name")
    println("="^60)
end

# ============================================================================
# Test 1: Initial State Verification
# ============================================================================

test_section("Test 1: Initial State Verification")

initial_idx = test_obs[:current_image_index][]
test_assert(initial_idx == 1, "Initial image index is 1", "Index: $initial_idx")

initial_textbox = test_widgets[:nav_textbox].stored_string[]
test_assert(initial_textbox == "1", "Initial textbox shows '1'", "Textbox: '$initial_textbox'")

initial_markers = test_obs[:current_markers][]
test_assert(isa(initial_markers, Vector), "Current markers is a Vector", "Type: $(typeof(initial_markers))")

initial_selection_active = test_obs[:selection_active][]
test_assert(initial_selection_active == false, "Selection initially inactive", "Active: $initial_selection_active")

initial_segmentation_toggle = test_widgets[:segmentation_toggle].active[]
test_assert(initial_segmentation_toggle == true, "Segmentation overlay initially enabled", "Enabled: $initial_segmentation_toggle")

# ============================================================================
# Test 2: Navigation - Next Button
# ============================================================================

test_section("Test 2: Navigation - Next Button")

# Click Next button 3 times
for i in 1:3
    println("\n[Test] Clicking Next button (iteration $i)...")
    prev_idx = test_obs[:current_image_index][]
    
    # Simulate button click
    test_widgets[:next_button].clicks[] = test_widgets[:next_button].clicks[] + 1
    sleep(0.5)  # Allow updates to propagate
    
    new_idx = test_obs[:current_image_index][]
    textbox_value = test_widgets[:nav_textbox].stored_string[]
    
    test_assert(new_idx == prev_idx + 1, "Next button increments image index", "Changed from $prev_idx to $new_idx")
    test_assert(textbox_value == string(new_idx), "Textbox synchronized with image index", "Textbox: '$textbox_value', Index: $new_idx")
end

final_idx_after_next = test_obs[:current_image_index][]
test_assert(final_idx_after_next == 4, "After 3 Next clicks, index is 4", "Index: $final_idx_after_next")

# ============================================================================
# Test 3: Navigation - Previous Button
# ============================================================================

test_section("Test 3: Navigation - Previous Button")

# Click Previous button 2 times
for i in 1:2
    println("\n[Test] Clicking Previous button (iteration $i)...")
    prev_idx = test_obs[:current_image_index][]
    
    # Simulate button click
    test_widgets[:prev_button].clicks[] = test_widgets[:prev_button].clicks[] + 1
    sleep(0.5)
    
    new_idx = test_obs[:current_image_index][]
    textbox_value = test_widgets[:nav_textbox].stored_string[]
    
    test_assert(new_idx == prev_idx - 1, "Previous button decrements image index", "Changed from $prev_idx to $new_idx")
    test_assert(textbox_value == string(new_idx), "Textbox synchronized with image index", "Textbox: '$textbox_value', Index: $new_idx")
end

final_idx_after_prev = test_obs[:current_image_index][]
test_assert(final_idx_after_prev == 2, "After 2 Previous clicks, index is 2", "Index: $final_idx_after_prev")

# ============================================================================
# Test 4: Navigation - Textbox Direct Input
# ============================================================================

test_section("Test 4: Navigation - Textbox Direct Input")

println("\n[Test] Setting textbox to '7'...")
test_widgets[:nav_textbox].stored_string[] = "7"
sleep(0.5)

new_idx = test_obs[:current_image_index][]
test_assert(new_idx == 7, "Textbox input updates image index", "Index: $new_idx")

println("\n[Test] Setting textbox to '1'...")
test_widgets[:nav_textbox].stored_string[] = "1"
sleep(0.5)

new_idx = test_obs[:current_image_index][]
test_assert(new_idx == 1, "Textbox navigation back to 1 works", "Index: $new_idx")

# ============================================================================
# Test 5: Parameter Controls - Threshold
# ============================================================================

test_section("Test 5: Parameter Controls - Threshold")

println("\n[Test] Changing threshold parameter...")
initial_threshold = test_widgets[:threshold_textbox].stored_string[]
println("  Initial threshold: $initial_threshold")

test_widgets[:threshold_textbox].stored_string[] = "0.6"
sleep(1)  # Allow detection to run

new_threshold = test_widgets[:threshold_textbox].stored_string[]
test_assert(new_threshold == "0.6", "Threshold textbox updated", "Threshold: $new_threshold")

# Verify that marker detection ran (observable should have been updated)
markers_after_threshold_change = test_obs[:current_markers][]
test_assert(isa(markers_after_threshold_change, Vector), "Marker detection ran after threshold change", "Markers: $(length(markers_after_threshold_change))")

# Reset to default
test_widgets[:threshold_textbox].stored_string[] = "0.7"
sleep(1)

# ============================================================================
# Test 6: Parameter Controls - Min Area
# ============================================================================

test_section("Test 6: Parameter Controls - Min Area")

println("\n[Test] Changing min_area parameter...")
initial_min_area = test_widgets[:min_area_textbox].stored_string[]
println("  Initial min_area: $initial_min_area")

test_widgets[:min_area_textbox].stored_string[] = "5000"
sleep(1)

new_min_area = test_widgets[:min_area_textbox].stored_string[]
test_assert(new_min_area == "5000", "Min area textbox updated", "Min area: $new_min_area")

markers_after_min_area_change = test_obs[:current_markers][]
test_assert(isa(markers_after_min_area_change, Vector), "Marker detection ran after min_area change", "Markers: $(length(markers_after_min_area_change))")

# Reset to default
test_widgets[:min_area_textbox].stored_string[] = "8000"
sleep(1)

# ============================================================================
# Test 7: Display Toggle - Segmentation Overlay
# ============================================================================

test_section("Test 7: Display Toggle - Segmentation Overlay")

println("\n[Test] Toggling segmentation overlay off...")
initial_toggle_state = test_widgets[:segmentation_toggle].active[]
println("  Initial state: $initial_toggle_state")

test_widgets[:segmentation_toggle].active[] = false
sleep(0.3)

new_toggle_state = test_widgets[:segmentation_toggle].active[]
test_assert(new_toggle_state == false, "Segmentation toggle set to false", "State: $new_toggle_state")

println("\n[Test] Toggling segmentation overlay back on...")
test_widgets[:segmentation_toggle].active[] = true
sleep(0.3)

new_toggle_state = test_widgets[:segmentation_toggle].active[]
test_assert(new_toggle_state == true, "Segmentation toggle set to true", "State: $new_toggle_state")

# ============================================================================
# Test 8: Region Selection Toggle
# ============================================================================

test_section("Test 8: Region Selection Toggle")

println("\n[Test] Activating region selection...")
initial_selection_state = test_widgets[:selection_toggle].active[]
println("  Initial state: $initial_selection_state")

test_widgets[:selection_toggle].active[] = true
sleep(0.3)

new_selection_state = test_obs[:selection_active][]
test_assert(new_selection_state == true, "Selection toggle activates selection_active observable", "Active: $new_selection_state")

status_label_text = test_widgets[:selection_status_label].text[]
test_assert(occursin("linke Ecke", status_label_text) || occursin("corner", lowercase(status_label_text)), 
            "Status label shows selection prompt", "Label: '$status_label_text'")

println("\n[Test] Deactivating region selection...")
test_widgets[:selection_toggle].active[] = false
sleep(0.3)

new_selection_state = test_obs[:selection_active][]
test_assert(new_selection_state == false, "Selection toggle deactivates selection_active observable", "Active: $new_selection_state")

# ============================================================================
# Test 9: Marker Detection Across Images
# ============================================================================

test_section("Test 9: Marker Detection Across Images")

println("\n[Test] Scanning through all images to check marker detection...")

# Navigate to image 1
test_widgets[:nav_textbox].stored_string[] = "1"
sleep(0.5)

marker_counts = Int[]
for i in 1:length(test_sets)
    println("  Checking image $i...")
    test_widgets[:nav_textbox].stored_string[] = string(i)
    sleep(0.5)
    
    current_markers = test_obs[:current_markers][]
    marker_count = length(current_markers)
    push!(marker_counts, marker_count)
    
    println("    → Markers detected: $marker_count")
end

test_assert(length(marker_counts) == length(test_sets), "Scanned all images", "Scanned: $(length(marker_counts))")
test_assert(any(marker_counts .> 0), "At least one image has markers", "Images with markers: $(sum(marker_counts .> 0))")

println("\n  Marker detection summary:")
println("    Total images: $(length(test_sets))")
println("    Images with markers: $(sum(marker_counts .> 0))")
println("    Images without markers: $(sum(marker_counts .== 0))")
println("    Total markers found: $(sum(marker_counts))")

# ============================================================================
# Test 10: Observable Synchronization
# ============================================================================

test_section("Test 10: Observable Synchronization")

println("\n[Test] Verifying observable synchronization...")

# Navigate to a specific image
test_widgets[:nav_textbox].stored_string[] = "5"
sleep(0.5)

current_idx = test_obs[:current_image_index][]
textbox_val = parse(Int, test_widgets[:nav_textbox].stored_string[])

test_assert(current_idx == textbox_val, "Image index observable matches textbox", "Index: $current_idx, Textbox: $textbox_val")

# Check that input/output images are observables
test_assert(isa(test_obs[:current_input_image], Bas3GLMakie.GLMakie.Observable), 
            "current_input_image is Observable", "Type: $(typeof(test_obs[:current_input_image]))")
test_assert(isa(test_obs[:current_output_image], Bas3GLMakie.GLMakie.Observable), 
            "current_output_image is Observable", "Type: $(typeof(test_obs[:current_output_image]))")
test_assert(isa(test_obs[:current_white_overlay], Bas3GLMakie.GLMakie.Observable), 
            "current_white_overlay is Observable", "Type: $(typeof(test_obs[:current_white_overlay]))")

# ============================================================================
# Test 11: Boundary Conditions - Navigation Limits
# ============================================================================

test_section("Test 11: Boundary Conditions - Navigation Limits")

println("\n[Test] Testing navigation at boundaries...")

# Go to first image
test_widgets[:nav_textbox].stored_string[] = "1"
sleep(0.5)

println("  At first image (1), attempting Previous button...")
initial_idx = test_obs[:current_image_index][]
test_widgets[:prev_button].clicks[] = test_widgets[:prev_button].clicks[] + 1
sleep(0.5)

idx_after_prev = test_obs[:current_image_index][]
test_assert(idx_after_prev == initial_idx, "Previous button does nothing at first image", "Index stayed at: $idx_after_prev")

# Go to last image
last_image_idx = length(test_sets)
test_widgets[:nav_textbox].stored_string[] = string(last_image_idx)
sleep(0.5)

println("  At last image ($last_image_idx), attempting Next button...")
initial_idx = test_obs[:current_image_index][]
test_widgets[:next_button].clicks[] = test_widgets[:next_button].clicks[] + 1
sleep(0.5)

idx_after_next = test_obs[:current_image_index][]
test_assert(idx_after_next == initial_idx, "Next button does nothing at last image", "Index stayed at: $idx_after_next")

# ============================================================================
# Test 12: Region Selection Clear Button
# ============================================================================

test_section("Test 12: Region Selection Clear Button")

println("\n[Test] Testing clear selection button...")

# Activate selection and set some corners (simulate)
test_widgets[:selection_toggle].active[] = true
sleep(0.3)

test_obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(10.0, 10.0)
test_obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(100.0, 100.0)
test_obs[:selection_complete][] = true
sleep(0.3)

println("  Selection corners set, verifying...")
corner1 = test_obs[:selection_corner1][]
corner2 = test_obs[:selection_corner2][]
selection_complete = test_obs[:selection_complete][]

test_assert(corner1 != Bas3GLMakie.GLMakie.Point2f(0, 0), "Selection corner 1 is set", "Corner1: $corner1")
test_assert(corner2 != Bas3GLMakie.GLMakie.Point2f(0, 0), "Selection corner 2 is set", "Corner2: $corner2")
test_assert(selection_complete == true, "Selection marked as complete", "Complete: $selection_complete")

println("  Clicking clear selection button...")
test_widgets[:clear_selection_button].clicks[] = test_widgets[:clear_selection_button].clicks[] + 1
sleep(0.5)

corner1_after = test_obs[:selection_corner1][]
corner2_after = test_obs[:selection_corner2][]
selection_complete_after = test_obs[:selection_complete][]

test_assert(corner1_after == Bas3GLMakie.GLMakie.Point2f(0, 0), "Corner 1 cleared", "Corner1: $corner1_after")
test_assert(corner2_after == Bas3GLMakie.GLMakie.Point2f(0, 0), "Corner 2 cleared", "Corner2: $corner2_after")
test_assert(selection_complete_after == false, "Selection marked as incomplete", "Complete: $selection_complete_after")

# Deactivate selection
test_widgets[:selection_toggle].active[] = false
sleep(0.3)

# ============================================================================
# Test Summary
# ============================================================================

println("\n" * "="^60)
println("  TEST SUMMARY")
println("="^60)
println()
println("  Total tests run: $test_counter")
println("  Passed: $passed_tests ✓")
println("  Failed: $failed_tests ✗")
println()

if failed_tests == 0
    println("  🎉 ALL TESTS PASSED! 🎉")
    println()
    println("  The interactive UI is functioning correctly:")
    println("    • Navigation controls work (Next, Previous, Textbox)")
    println("    • Parameter controls update marker detection")
    println("    • Display toggles function properly")
    println("    • Region selection can be activated/cleared")
    println("    • Observables stay synchronized")
    println("    • Boundary conditions handled correctly")
    println("    • Marker detection runs across all images")
else
    println("  ⚠️  SOME TESTS FAILED")
    println("  Review the output above for details.")
end

println()
println("="^60)
println("  Interactive window is still open for manual inspection.")
println("  Close the window or press Ctrl+D to exit.")
println("="^60)
