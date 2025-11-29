# Test version that saves screenshot
println("=== Testing Patient Image Comparison UI ===")

# Load base setup
include("Load_Sets.jl")

# Load CompareUI module
println("Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Create the comparison figure in test mode
println("Creating comparison figure...")
fig_data = create_compare_figure(sets, input_type; max_images_per_row=6, test_mode=true)
fig = fig_data.figure

println("\nWaiting for render...")
sleep(3)

# Save screenshot using GLMakie
Bas3GLMakie.GLMakie.save("/tmp/compare_ui_test.png", fig)
println("\n=== Screenshot saved ===")
println("File: /tmp/compare_ui_test.png")
println("Size: ", filesize("/tmp/compare_ui_test.png"), " bytes")

# Also test changing patient
println("\n=== Testing patient change ===")
fig_data.widgets[:patient_menu].i_selected[] = 2
sleep(2)
Bas3GLMakie.GLMakie.save("/tmp/compare_ui_patient2.png", fig)
println("Patient 2 screenshot: /tmp/compare_ui_patient2.png")
println("Size: ", filesize("/tmp/compare_ui_patient2.png"), " bytes")

println("\n=== Test Complete ===")
