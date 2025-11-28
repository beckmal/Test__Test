# ============================================================================
# run_Load_Sets__InteractiveUI.jl
# ============================================================================
# Launches the Interactive Marker Detection UI
#
# Usage:
#   julia --script=run_Load_Sets__InteractiveUI.jl
#
# This UI allows you to:
# - Browse through the dataset images
# - Adjust morphological operations interactively
# - Detect white markers automatically
# - Visualize segmentation masks
# ============================================================================

println("=== Launching Interactive Marker Detection UI ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load InteractiveUI module
println("Loading InteractiveUI module...")
include("Load_Sets__InteractiveUI.jl")

# Create and display the interactive figure
println("Creating interactive figure...")
const interactive_fig = create_interactive_figure(sets, input_type, raw_output_type)

println("\n=== Interactive UI Ready ===")
println("Controls:")
println("  - Use sliders to adjust morphological parameters")
println("  - Browse images using the image index slider")
println("  - Close window when done")
println("")

# Display the figure
display(Bas3GLMakie.GLMakie.Screen(), interactive_fig)

# Keep the process alive to maintain the window
println("\nUI window is now open. Press Ctrl+C to close.")
try
    while true
        sleep(1)
    end
catch e
    if isa(e, InterruptException)
        println("\nClosing UI...")
    else
        rethrow(e)
    end
end
