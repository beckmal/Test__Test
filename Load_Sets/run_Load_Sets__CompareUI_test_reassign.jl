# Test patient ID reassignment feature
println("=== Testing Patient ID Reassignment ===")

# Load base setup
include("Load_Sets.jl")

# Load CompareUI module
println("Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Create the comparison figure in test mode
println("Creating comparison figure...")
fig_data = create_compare_figure(sets, input_type; max_images_per_row=6, test_mode=true)
fig = fig_data.figure

println("\n=== Initial State ===")
println("Current patient: ", fig_data.observables[:current_patient_id][])
println("Number of images: ", length(fig_data.dynamic_widgets[:patient_id_textboxes]))

# Check patient ID textboxes exist
pid_tbs = fig_data.dynamic_widgets[:patient_id_textboxes]
println("Patient ID textboxes created: ", length(pid_tbs))

if length(pid_tbs) > 0
    println("First image patient ID value: ", pid_tbs[1].displayed_string[])
end

# Test validation functions
println("\n=== Testing Validation ===")
println("validate_patient_id_compare('') = ", validate_patient_id_compare(""))
println("validate_patient_id_compare('abc') = ", validate_patient_id_compare("abc"))
println("validate_patient_id_compare('0') = ", validate_patient_id_compare("0"))
println("validate_patient_id_compare('-1') = ", validate_patient_id_compare("-1"))
println("validate_patient_id_compare('42') = ", validate_patient_id_compare("42"))
println("validate_patient_id_compare(' 5 ') = ", validate_patient_id_compare(" 5 "))

# Save screenshot
sleep(2)
Bas3GLMakie.GLMakie.save("/tmp/compare_ui_reassign_test.png", fig)
println("\nScreenshot saved: /tmp/compare_ui_reassign_test.png")
println("Size: ", filesize("/tmp/compare_ui_reassign_test.png"), " bytes")

println("\n=== Test Complete ===")
