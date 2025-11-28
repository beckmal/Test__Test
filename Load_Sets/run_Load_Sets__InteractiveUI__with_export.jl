# ============================================================================
# run_Load_Sets__InteractiveUI__with_export.jl
# ============================================================================
# Launches the Interactive Marker Detection UI with test_mode enabled,
# automatically exports the closeup axis as PNG, then keeps UI open.
#
# Usage:
#   julia --script=Bas3ImageSegmentation/Load_Sets/run_Load_Sets__InteractiveUI__with_export.jl
#
# Output:
#   /tmp/closeup_observable.png - Full resolution closeup from observable data
#
# This script:
# 1. Loads the UI with test_mode=true
# 2. Waits for initialization and rendering
# 3. Exports closeup observable data to PNG automatically
# 4. Keeps UI window open for further interaction
# ============================================================================

println("[EXPORT] === Launching Interactive Marker Detection UI (with Auto-Export) ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load InteractiveUI module
println("[EXPORT] Loading InteractiveUI module...")
include("Load_Sets__InteractiveUI.jl")

# Create interactive figure with test_mode enabled
println("[EXPORT] Creating interactive figure with test_mode=true...")
const test_result = create_interactive_figure(sets, input_type, raw_output_type; test_mode=true)

println("\n[EXPORT] === Interactive UI Created ===")

# Display the figure and wait for rendering
println("[EXPORT] Displaying figure and waiting for OpenGL rendering...")
const export_screen = display(Bas3GLMakie.GLMakie.Screen(), test_result.figure)
sleep(5)  # Wait for OpenGL rendering to complete
println("[EXPORT] Rendering complete")

# ============================================================================
# AUTO-EXPORT: Save closeup observable data to PNG
# ============================================================================
println("\n" * "="^80)
println("[EXPORT] AUTO-EXPORTING CLOSEUP OBSERVABLE DATA")
println("="^80)

const CLOSEUP_OUTPUT_PATH = "/tmp/closeup_observable.png"

try
    # Access the observable data directly
    closeup_data = test_result.observables[:current_closeup_image][]
    
    if isnothing(closeup_data)
        println("[EXPORT] ⚠ Closeup observable is empty - no marker detected yet")
        println("[EXPORT]   The UI will stay open for manual interaction")
    else
        # Get dimensions
        img_size = size(closeup_data)
        println("[EXPORT] Observable data size: $(img_size)")
        
        # Save directly using GLMakie.save
        Bas3GLMakie.GLMakie.save(CLOSEUP_OUTPUT_PATH, closeup_data)
        
        # Verify file
        if isfile(CLOSEUP_OUTPUT_PATH)
            filesize_kb = round(stat(CLOSEUP_OUTPUT_PATH).size / 1024, digits=1)
            println("[EXPORT] ✓ Saved: $(CLOSEUP_OUTPUT_PATH)")
            println("[EXPORT] ✓ File size: $(filesize_kb) KB")
            println("[EXPORT] ✓ Image dimensions: $(img_size)")
        else
            println("[EXPORT] ✗ File was not created")
        end
    end
catch e
    println("[EXPORT] ✗ ERROR during auto-export: $(typeof(e))")
    println("[EXPORT]   $(sprint(showerror, e))")
end

println("="^80)
println("")

# ============================================================================
# Keep UI open - wait for window to close
# ============================================================================
println("[EXPORT] UI window is open. Close the window to exit.")
println("[EXPORT] Output saved to: $(CLOSEUP_OUTPUT_PATH)")
println("")

# Wait for the screen/window to be closed
wait(export_screen)

println("[EXPORT] Window closed. Exiting.")
