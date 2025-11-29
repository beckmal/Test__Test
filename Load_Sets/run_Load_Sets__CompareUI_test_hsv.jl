# ============================================================================
# run_Load_Sets__CompareUI_test_hsv.jl
# ============================================================================
# Tests the HSV histogram feature in CompareUI
#
# Usage:
#   julia --script=run_Load_Sets__CompareUI_test_hsv.jl
#
# This script:
# - Loads the CompareUI in test mode
# - Verifies HSV histogram extraction functions work
# - Verifies HSV grids are created for each image
# - Prints statistics for verification
# ============================================================================

println("=== Testing HSV Histogram Feature in CompareUI ===")

# Load base setup with only 50 images (faster testing)
import Base: print, println
import Pkg
Pkg.activate(@__DIR__)

println("Loading modular components...")
include("Load_Sets__Core.jl")

println("Loading dataset (50 images only)...")
const sets = load_original_sets(50, false)
println("Loaded $(length(sets)) image sets")

const inputs = [set[1] for set in sets]
const raw_outputs = [set[2] for set in sets]
const class_names_de = CLASS_NAMES_DE
const channel_names_de = CHANNEL_NAMES_DE

# Load CompareUI module
println("\nLoading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Test 1: Verify HSV extraction function works directly
println("\n=== Test 1: Direct HSV Extraction Test ===")
test_input, test_output, test_idx = sets[1]
classes = shape(test_output)
println("Classes available: $classes")

hsv_data = extract_class_hsv_values(test_input, test_output, classes)
println("Extracted HSV data for $(length(hsv_data)) classes:")

for (class, class_data) in hsv_data
    if class_data.count > 0
        println("  $class: $(class_data.count) pixels, median H=$(round(class_data.median_h, digits=1))° S=$(round(class_data.median_s, digits=1))% V=$(round(class_data.median_v, digits=1))%")
    else
        println("  $class: no pixels")
    end
end

# Test 2: Create UI in test mode
println("\n=== Test 2: Create CompareUI in Test Mode ===")
ui_result = create_compare_figure(sets, input_type; max_images_per_row=6, test_mode=true)

println("Figure created: $(ui_result.figure)")
println("Database path: $(ui_result.db_path)")
println("Patient IDs count: $(length(ui_result.all_patient_ids))")
println("Current patient: $(ui_result.observables[:current_patient_id][])")

# Test 3: Check dynamic widgets
println("\n=== Test 3: Verify Dynamic Widgets ===")
dw = ui_result.dynamic_widgets
println("Image axes: $(length(dw[:image_axes]))")
println("Date textboxes: $(length(dw[:date_textboxes]))")
println("Info textboxes: $(length(dw[:info_textboxes]))")
println("Patient ID textboxes: $(length(dw[:patient_id_textboxes]))")
println("Save buttons: $(length(dw[:save_buttons]))")
println("HSV grids: $(length(dw[:hsv_grids]))")
println("HSV class data: $(length(dw[:hsv_class_data]))")

# Test 4: Verify HSV data per image
println("\n=== Test 4: HSV Data Summary Per Image ===")
for (i, hsv_data_item) in enumerate(dw[:hsv_class_data])
    if isempty(hsv_data_item)
        println("Image $i: no HSV data (image not in loaded sets)")
    else
        total_pixels = sum(d.count for d in values(hsv_data_item))
        classes_with_data = filter(kv -> kv.second.count > 0, hsv_data_item)
        println("Image $i: $total_pixels pixels across $(length(classes_with_data)) classes")
        for (class, data) in classes_with_data
            println("    $class: n=$(data.count), H=$(round(data.median_h, digits=0))° S=$(round(data.median_s, digits=0))% V=$(round(data.median_v, digits=0))%")
        end
    end
end

# Test 5: Display the figure
println("\n=== Test 5: Displaying Figure ===")
display(Bas3GLMakie.GLMakie.Screen(), ui_result.figure)

println("\n=== HSV Histogram Test Complete ===")
println("Note: Images 62, 73, 77 (Patient 1) are not in the first 50 loaded sets.")
println("To see HSV histograms, select a patient whose images are in index range 1-50.")
println("")
