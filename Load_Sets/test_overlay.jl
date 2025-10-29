# Quick test to verify overlay visualization
println("Testing overlay with existing session...")
println("Sets available: ", length(sets))
println("Creating figure with overlay...")

# Create a simple test figure
using Bas3GLMakie
fgr = Figure(size=(800, 600))
axs = Bas3GLMakie.GLMakie.Axis(
    fgr[1, 1];
    title="Test Overlay",
    aspect=Bas3GLMakie.GLMakie.DataAspect()
)
Bas3GLMakie.GLMakie.hidedecorations!(axs)

# Display input image
input_img = rotr90(image(sets[1][1]))
Bas3GLMakie.GLMakie.image!(axs, input_img)

# Overlay segmentation with 50% transparency
output_img = rotr90(image(sets[1][2]))
Bas3GLMakie.GLMakie.image!(axs, output_img; alpha=0.5)

# Save the figure
Bas3GLMakie.save("test_overlay.png", fgr)
println("Saved test_overlay.png")
