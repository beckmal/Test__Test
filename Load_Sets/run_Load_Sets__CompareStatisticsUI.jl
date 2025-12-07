# ============================================================================
# run_Load_Sets__CompareStatisticsUI.jl
# ============================================================================
# Launches the Compare Statistics UI for multi-patient L*C*h cohort analysis
#
# Usage:
#   julia --script=run_Load_Sets__CompareStatisticsUI.jl
#
# This UI allows you to:
# - Filter patients by exact image count (e.g., "all patients with 3 images")
# - Select which wound class to analyze (:redness, :granulation_tissue, etc.)
# - View aggregated L*C*h trajectories across the patient cohort
# - Toggle visualization layers (individual lines, mean±std, median, quartiles)
# - Export statistics and patient lists
#
# Prerequisites:
# - MuHa.xlsx database must exist with patient entries
# - Images must be available in the dataset
# ============================================================================

println("=== Launching Compare Statistics UI ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load CompareUI module (provides filtering and L*C*h extraction)
println("Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Load CompareStatisticsUI module
println("Loading CompareStatisticsUI module...")
include("Load_Sets__CompareStatisticsUI.jl")

# Initialize database path (provided by CompareUI module)
const db_path = initialize_database_compare()

# Create and display the comparison statistics figure
println("\nCreating comparison statistics figure...")
println("  Database: $db_path")
println("  Default filter: 3 images")
println("  Default class: :redness")
println("")

const compare_stats_fig = create_compare_statistics_figure(
    sets, 
    db_path;
    default_filter = 3,
    default_class = :redness
)

println("\n=== CompareStatisticsUI Ready ===")
println("Controls:")
println("  - Select image count filter from dropdown")
println("  - Select class to analyze")
println("  - Toggle visualization layers:")
println("    • Einzelne Patienten: Show individual patient trajectories")
println("    • Mittelwert ± Std: Show mean with standard deviation band")
println("    • Median: Show median line")
println("    • Quartile: Show 25th-75th percentile bands")
println("  - Click 'Aktualisieren' to update plot")
println("")
println("Plot legend:")
println("  - Solid lines: L* (lightness)")
println("  - Dashed lines: C* (chroma)")
println("  - Dotted lines: h° (hue)")
println("")
println("Close window when done")
println("")

# Display the figure
display(Bas3GLMakie.GLMakie.Screen(), compare_stats_fig)
