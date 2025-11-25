# ============================================================================
# run_Load_Sets__BalanceUI.jl
# ============================================================================
# Launches the White Balance UI
#
# Usage:
#   julia --script=run_Load_Sets__BalanceUI.jl
#
# This UI allows you to:
# - Browse through the dataset images
# - Automatically detect white balance regions
# - Apply white balance correction using Bradford chromatic adaptation
# - Compare before/after images side-by-side
# - View RGB histograms for both original and balanced images
# ============================================================================

println("=== Launching White Balance UI ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load BalanceUI module
println("Loading BalanceUI module...")
include("Load_Sets__BalanceUI.jl")

# Create and display the balance figure
println("Creating balance UI figure...")
const balance_fig = create_balance_figure(sets, input_type, raw_output_type; test_mode=false)

println("\n=== White Balance UI Ready ===")
println("Controls:")
println("  - Use image index slider to browse images")
println("  - Automatic white region detection and white balance")
println("  - Compare Before/After with RGB histograms")
println("  - Close window when done")
println("")

# Display the figure (GLMakie keeps process alive automatically)
display(Bas3GLMakie.GLMakie.Screen(), balance_fig)

# WORKAROUND: Register figure-level mouse event AFTER display to activate event system
# This fixes button clicks not working in WSLg/GLMakie
println("Registering mousebutton workaround...")
Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(balance_fig).mousebutton) do event
    # Silent workaround - no output needed
end
println("Workaround registered!")
