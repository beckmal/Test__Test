# ============================================================================
# Load_Sets__Augment_ParameterDistributions_UI.jl
# ============================================================================
# UI component for displaying augmentation parameter distributions.
# Shows histograms of: scale, rotation, shear, brightness, saturation, blur, flip
#
# Usage:
#   include("Load_Sets__Augment_ParameterDistributions_UI.jl")
#   fig = create_augment_parameter_distributions_figure(all_metadata)
#   display(fig)
# ============================================================================

"""
    create_augment_parameter_distributions_figure(all_metadata)

Create a figure showing distribution histograms of all augmentation parameters.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples

# Returns
GLMakie Figure with 9 parameter distribution plots (3x3 grid):
- Row 1: Scale factor, Rotation angle, Shear X angle
- Row 2: Shear Y angle, Brightness factor, Saturation offset
- Row 3: Blur kernel size, Blur sigma, Flip type
"""
function create_augment_parameter_distributions_figure(all_metadata::Vector{AugmentationMetadata})
    # Extract parameter arrays
    scale_factors = [m.scale_factor for m in all_metadata]
    rotation_angles = [m.rotation_angle for m in all_metadata]
    shear_x_angles = [m.shear_x_angle for m in all_metadata]
    shear_y_angles = [m.shear_y_angle for m in all_metadata]
    brightness_factors = [m.brightness_factor for m in all_metadata]
    saturation_offsets = [m.saturation_offset for m in all_metadata]
    blur_kernel_sizes = [m.blur_kernel_size for m in all_metadata]
    blur_sigmas = [m.blur_sigma for m in all_metadata]
    flip_types = [m.flip_type for m in all_metadata]
    
    # Create figure
    fig = Bas3GLMakie.GLMakie.Figure(size=(1800, 1200))
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[0, :], 
        "Augmentation Parameter Distributions (N=$(length(all_metadata)))", 
        fontsize=24, 
        font=:bold
    )
    
    # Row 1: Scale, Rotation, Shear X
    ax1 = Bas3GLMakie.GLMakie.Axis(fig[1, 1], title="Scale Factor", xlabel="Scale", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax1, scale_factors, bins=20, color=:steelblue)
    
    ax2 = Bas3GLMakie.GLMakie.Axis(fig[1, 2], title="Rotation Angle", xlabel="Degrees", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax2, rotation_angles, bins=36, color=:coral)
    
    ax3 = Bas3GLMakie.GLMakie.Axis(fig[1, 3], title="Shear X Angle", xlabel="Degrees", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax3, shear_x_angles, bins=20, color=:mediumseagreen)
    
    # Row 2: Shear Y, Brightness, Saturation
    ax4 = Bas3GLMakie.GLMakie.Axis(fig[2, 1], title="Shear Y Angle", xlabel="Degrees", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax4, shear_y_angles, bins=20, color=:mediumpurple)
    
    ax5 = Bas3GLMakie.GLMakie.Axis(fig[2, 2], title="Brightness Factor", xlabel="Factor", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax5, brightness_factors, bins=10, color=:gold)
    
    ax6 = Bas3GLMakie.GLMakie.Axis(fig[2, 3], title="Saturation Offset", xlabel="Offset", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax6, saturation_offsets, bins=10, color=:darkorange)
    
    # Row 3: Blur kernel, Blur sigma, Flip type
    ax7 = Bas3GLMakie.GLMakie.Axis(fig[3, 1], title="Blur Kernel Size", xlabel="Size", ylabel="Count", xticks=[3, 5, 7])
    kernel_counts = [count(==(k), blur_kernel_sizes) for k in [3, 5, 7]]
    Bas3GLMakie.GLMakie.barplot!(ax7, [3, 5, 7], kernel_counts, color=:slategray)
    
    ax8 = Bas3GLMakie.GLMakie.Axis(fig[3, 2], title="Blur Sigma", xlabel="σ", ylabel="Count")
    Bas3GLMakie.GLMakie.hist!(ax8, blur_sigmas, bins=20, color=:teal)
    
    ax9 = Bas3GLMakie.GLMakie.Axis(fig[3, 3], title="Flip Type", xlabel="Type", ylabel="Count", 
               xticks=(1:3, ["FlipX", "FlipY", "NoOp"]))
    flip_counts = [count(==(t), flip_types) for t in [:flipx, :flipy, :noop]]
    Bas3GLMakie.GLMakie.barplot!(ax9, 1:3, flip_counts, color=[:indianred, :cornflowerblue, :darkgray])
    
    return fig
end

"""
    save_augment_parameter_distributions_figure(fig, output_path)

Save the parameter distributions figure to a file.

# Arguments
- `fig` - Figure to save
- `output_path::String` - Path for output file (e.g., "params.png")
"""
function save_augment_parameter_distributions_figure(fig, output_path::String)
    Bas3GLMakie.GLMakie.save(output_path, fig)
    println("Saved: $(output_path)")
end

println("  Load_Sets__Augment_ParameterDistributions_UI loaded")
