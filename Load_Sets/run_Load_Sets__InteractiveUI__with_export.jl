# ============================================================================
# run_Load_Sets__InteractiveUI_with_export.jl
# ============================================================================
# Launches the Interactive Marker Detection UI with test_mode enabled
# and provides export functionality for individual axes
#
# Usage:
#   julia -i run_Load_Sets__InteractiveUI_with_export.jl
#
# Note: Use -i flag for interactive mode so you can type export_current_axes()
#
# This UI allows you to:
# - Browse through the dataset images
# - Adjust morphological operations interactively
# - Detect white markers automatically
# - Visualize segmentation masks
# - Export individual axis images using colorbuffer (rendered viewports)
# ============================================================================

println("[EXPORT] === Launching Interactive Marker Detection UI (with Export) ===")

# Load base setup (modules, dataset, core variables)
include("Load_Sets.jl")

# Load InteractiveUI module
println("[EXPORT] Loading InteractiveUI module...")
include("Load_Sets__InteractiveUI.jl")

# Create interactive figure with test_mode enabled
println("[EXPORT] Creating interactive figure with test_mode=true...")
const test_result = create_interactive_figure(sets, input_type, raw_output_type; test_mode=true)

println("\n[EXPORT] === Interactive UI Ready ===")
println("Controls:")
println("  - Use sliders to adjust morphological parameters")
println("  - Browse images using the image index slider")
println("  - Adjust closeup rotation with 'Nahansicht Rotation' textbox")
println("  - Export images anytime (see instructions below)")
println("")

# Display the figure and wait for rendering (CRITICAL for colorbuffer capture)
println("[EXPORT] Displaying figure and waiting for OpenGL rendering...")
const export_screen = display(Bas3GLMakie.GLMakie.Screen(), test_result.figure)
sleep(3)  # CRITICAL: Wait for OpenGL rendering to complete
println("[EXPORT] Rendering complete")

println("\n" * "="^80)
println("EXPORT FUNCTIONALITY")
println("="^80)
println("To export current axis images, run in the REPL:")
println("")
println("  export_current_axes()")
println("")
println("This will save to /tmp:")
println("  - closeup_axis.png    (Closeup view - rendered viewport)")
println("  - image_axis.png      (Main image view - rendered viewport)")
println("="^80)
println("")

# Define export function in global scope
"""
    export_current_axes()

Export current axis images from the running UI to /tmp.
Uses the RECOMMENDED methodology: colorbuffer capture of rendered viewports.

Follows Interactive UI Debugging Methodology Pattern 5 (Individual Axis Export).
Captures the exact rendered output as displayed on screen using OpenGL framebuffer.

Exports:
- /tmp/closeup_axis.png - Closeup view with current rotation (rendered viewport)
- /tmp/image_axis.png - Main image axis with overlays (rendered viewport)

Note: Output dimensions are viewport size (screen-space), not data dimensions.
This is expected - captures exactly what the user sees.
"""
function export_current_axes()
    println("[EXPORT] " * "="^80)
    println("[EXPORT] EXPORTING CURRENT AXIS IMAGES")
    println("[EXPORT] " * "="^80)
    
    try
        # Export closeup axis using colorbuffer (Pattern 5: Individual Axis Export)
        println("\n[EXPORT] [1/2] Exporting closeup axis...")
        closeup_axis = test_result.axes[:closeup_axis]
        closeup_buffer = Bas3GLMakie.GLMakie.colorbuffer(closeup_axis.scene)
        closeup_path = "/tmp/closeup_axis.png"
        Bas3GLMakie.GLMakie.save(closeup_path, closeup_buffer)
        println("[EXPORT]   ✓ Saved: $(closeup_path)")
        println("[EXPORT]   ✓ Viewport size: $(size(closeup_buffer)) (screen-space dimensions)")
        
        # Export image axis using colorbuffer
        println("\n[EXPORT] [2/2] Exporting image axis...")
        image_axis = test_result.axes[:image_axis]
        image_buffer = Bas3GLMakie.GLMakie.colorbuffer(image_axis.scene)
        image_path = "/tmp/image_axis.png"
        Bas3GLMakie.GLMakie.save(image_path, image_buffer)
        println("[EXPORT]   ✓ Saved: $(image_path)")
        println("[EXPORT]   ✓ Viewport size: $(size(image_buffer)) (screen-space dimensions)")
        
        # Verify files
        println("\n[EXPORT] " * "="^80)
        println("[EXPORT] EXPORT COMPLETE - File Summary:")
        println("[EXPORT] " * "="^80)
        
        for (name, path) in [("Closeup axis", closeup_path), ("Image axis", image_path)]
            if isfile(path)
                filesize_kb = round(stat(path).size / 1024, digits=1)
                println("[EXPORT]   ✓ $name: $(filesize_kb) KB")
            else
                println("[EXPORT]   ✗ $name: FILE NOT FOUND")
            end
        end
        
        println("\n[EXPORT] " * "="^80)
        println("[EXPORT] To view images from WSL:")
        println("[EXPORT]   explorer.exe /tmp/closeup_axis.png")
        println("[EXPORT]   explorer.exe /tmp/image_axis.png")
        println("[EXPORT] " * "="^80)
        
        return (closeup_path, image_path)
        
    catch e
        println("[EXPORT] ✗ ERROR during export: $(typeof(e))")
        println("[EXPORT]   $(sprint(showerror, e))")
        println("[EXPORT]   Ensure the UI is displayed and rendering is complete")
        rethrow(e)
    end
end

# Make export function globally available
@eval Main export_current_axes() = $export_current_axes()

println("")
println("="^80)
println("✓ UI is displayed and ready for use")
println("✓ Julia REPL is active - you can type commands")
println("")
println("To export current axis images, type:")
println("  export_current_axes()")
println("")
println("Notes:")
println("  - Exports use colorbuffer capture (rendered viewport)")
println("  - Output dimensions are screen-space (viewport size)")
println("  - Captures exactly what you see on screen")
println("")
println("To close: Press Ctrl+D or type exit()")
println("="^80)
println("")
