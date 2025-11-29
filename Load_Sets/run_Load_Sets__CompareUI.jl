# ============================================================================
# run_Load_Sets__CompareUI.jl
# ============================================================================
# Launches the Patient Image Comparison UI
#
# Usage:
#   julia --script=run_Load_Sets__CompareUI.jl
#
# This UI allows you to:
# - Select a patient by ID from a dropdown menu
# - View all images for that patient in a horizontal row
# - Edit date and info fields for each image
# - Save changes to the MuHa.xlsx database
#
# Prerequisites:
# - MuHa.xlsx database must exist with patient entries
# - Use InteractiveUI first to add images to patients
# ============================================================================

println("=== Launching Patient Image Comparison UI ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load CompareUI module
println("Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Create and display the comparison figure
println("Creating comparison figure...")
const compare_fig = create_compare_figure(sets, input_type; max_images_per_row=6)

println("\n=== CompareUI Ready ===")
println("Controls:")
println("  - Select patient from dropdown menu")
println("  - Edit date/info fields for each image")
println("  - Click 'Speichern' to save changes per image")
println("  - Click 'Aktualisieren' to refresh patient list")
println("  - Close window when done")
println("")

# Display the figure
display(Bas3GLMakie.GLMakie.Screen(), compare_fig)
