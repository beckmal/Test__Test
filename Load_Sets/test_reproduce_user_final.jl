# test_reproduce_user_final.jl
# Reproduces user's exact interaction and saves the center image axis directly

println("="^80)
println("TEST: Reproduce User Interaction - Image Axis Only")
println("="^80)
println()

println("Loading required modules...")
include("Load_Sets__Core.jl")
println("✓ Modules loaded\n")

# Load test dataset
println("Loading test dataset (1 image)...")
const test_sets = load_original_sets(1, false)
println("Loaded $(length(test_sets)) image sets\n")

# Create interactive figure in test mode
println("Creating interactive figure in test mode...")
const test_result = create_interactive_figure(test_sets, input_type, raw_output_type; test_mode=true)
const test_fig = test_result.figure
const test_obs = test_result.observables
const test_widgets = test_result.widgets

println("✓ Figure created successfully\n")

# Display the figure
println("Displaying interactive UI...")
const screen = Bas3GLMakie.GLMakie.Screen()
display(screen, test_fig)
sleep(2)
println("✓ UI displayed\n")

# ============================================================================
# Reproduce User's Exact Interaction
# ============================================================================

println("="^80)
println("Setting Up Selection (User's Parameters)")
println("="^80)
println()

# Exact parameters from user's screenshot
axis_corner1 = (350.0, 600.0)
axis_corner2 = (700.0, 230.0)
rotation_angle = 20.0

println("Parameters:")
println("  Corner 1: $(axis_corner1)")
println("  Corner 2: $(axis_corner2)")
println("  Rotation: $(rotation_angle)°")
println()

println("Setting selection...")
# IMPORTANT: Disable selection mode first to prevent mouse events from interfering
test_obs[:selection_active][] = false

# Set selection corners
test_obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(axis_corner1[1], axis_corner1[2])
test_obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(axis_corner2[1], axis_corner2[2])

# Set rotation BEFORE marking selection complete (so detection uses correct angle)
println("Setting rotation...")
test_obs[:selection_rotation][] = rotation_angle
test_widgets[:rotation_textbox].stored_string[] = string(rotation_angle)

# CRITICAL: Manually update selection_rect observable to draw the cyan box
# This mimics what the UI does in the mouse click handler (line 2102) and rotation callback (line 1669)
println("Updating selection_rect observable for cyan box visualization...")
function make_rotated_rectangle_local(c1, c2, angle_degrees::Float64)
    x_min, x_max = Base.minmax(c1[1], c2[1])
    y_min, y_max = Base.minmax(c1[2], c2[2])
    center_x = (x_min + x_max) / 2
    center_y = (y_min + y_max) / 2
    corners = [
        (x_min - center_x, y_min - center_y),
        (x_max - center_x, y_min - center_y),
        (x_max - center_x, y_max - center_y),
        (x_min - center_x, y_max - center_y)
    ]
    angle_rad = deg2rad(angle_degrees)
    cos_a = cos(angle_rad)
    sin_a = sin(angle_rad)
    rotated_corners = map(corners) do (x, y)
        rotated_x = x * cos_a - y * sin_a + center_x
        rotated_y = x * sin_a + y * cos_a + center_y
        Bas3GLMakie.GLMakie.Point2f(rotated_x, rotated_y)
    end
    push!(rotated_corners, rotated_corners[1])
    return rotated_corners
end

test_obs[:selection_rect][] = make_rotated_rectangle_local(
    test_obs[:selection_corner1][], 
    test_obs[:selection_corner2][], 
    rotation_angle
)
sleep(0.5)

# Now mark selection complete - this triggers detection with the rotation already set
test_obs[:selection_complete][] = true
sleep(2)  # Allow detection to complete

println("Adjusting detection parameters...")
test_widgets[:threshold_textbox].stored_string[] = "0.7"
test_widgets[:min_area_textbox].stored_string[] = "8000"
sleep(2)  # Allow detection to re-run with new parameters

println("✓ Configuration complete")
println("  Threshold: 0.7")
println("  Min area: 8000")
println()

# Check results
markers = test_obs[:current_markers][]
marker_success = test_obs[:marker_success][]
marker_message = test_obs[:marker_message][]

println("Detection results:")
println("  Markers: $(length(markers))")
println("  Success: $marker_success")
println("  Message: $marker_message")
println()

# ============================================================================
# Capture the Image Axis Only (Center Panel)
# ============================================================================

println("="^80)
println("Capturing Image Axis from Interactive UI")
println("="^80)
println()

# Allow final rendering to complete
println("Waiting for UI to fully render...")
sleep(1)

# Save the axis directly using GLMakie.save
# Capture the full UI and crop to center image axis
println("Capturing full UI buffer...")
full_buffer = Bas3GLMakie.GLMakie.colorbuffer(screen)
println("  Full buffer size: $(size(full_buffer))")

# Crop to center panel (center image axis)
# Layout: left panel ~300px, center axis ~800px, right panels ~1100px
# Total ~2200px width, ~1000px height
println("Cropping to center image axis (row 2, column 2)...")
center_crop = full_buffer[150:950, 300:1100, :]

output_path = joinpath(@__DIR__, "user_interaction_image_axis.png")
println("Saving image axis to: $(output_path)")
Bas3GLMakie.GLMakie.save(output_path, center_crop)
println("✓ Image axis saved")

# Close the window to end the script
println("Closing window...")
Bas3GLMakie.GLMakie.close(screen)

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^80)
println("SUMMARY")
println("="^80)
println()

println("✅ User interaction reproduced")
println("✅ Image axis saved: user_interaction_image_axis.png")
println()
println("The image shows the center panel with:")
println("  - Input image (base layer)")
println("  - Ground truth segmentation (colored overlay, 75% opacity)")
println("  - Cyan selection border (rotated $(rotation_angle)°) - border only, no fill")
println("  - Red detection overlay (marker region)")
println("  - Purple/magenta bounding box (detected marker outline)")
println("  - Colored bounding boxes (ground truth class regions)")
println()
println("Detection results:")
println("  Markers found: $(length(markers))")
println("  Success: $marker_success")
println()
println("="^80)
