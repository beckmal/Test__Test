# Augment_Sets__ParameterDistributions_StatisticsUI.jl
# Interactive UI for displaying augmentation parameter distributions
# Displays histograms of: scale, rotation, shear, brightness, saturation, blur, flip

import Random

# ============================================================================
# Environment Setup
# ============================================================================

const _env_param_dist = try
    _env_param_dist
catch
    println("=== Initializing Parameter Distributions UI ===")
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.resolve()

    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    using Bas3GLMakie.GLMakie: Figure, Label, Axis, hist!, barplot!, axislegend
    using Bas3GLMakie.GLMakie: hidedecorations!, DataAspect, save, display

    println("Loading Bas3ImageSegmentation...")
    using Bas3ImageSegmentation
    using Bas3ImageSegmentation.JLD2
    
    println("Loading Statistics...")
    using Statistics
    
    println("=== Environment initialized ===")
    Dict()
end

# ============================================================================
# Data Loading
# ============================================================================

# Platform-independent path resolution using @__DIR__
# The script is in: .../workspace/Bas3ImageSegmentation/Load_Sets/
# Data is in: C:\Syncthing\Datasets\ (Windows) or /mnt/c/Syncthing/Datasets/ (WSL)

function resolve_data_path()
    # Try Windows path first
    win_path = raw"C:\Syncthing\Datasets\augmented_balanced_metadata"
    if isdir(win_path)
        return win_path
    end
    
    # Try WSL path
    wsl_path = "/mnt/c/Syncthing/Datasets/augmented_balanced_metadata"
    if isdir(wsl_path)
        return wsl_path
    end
    
    # Fallback: try relative to script directory
    script_dir = @__DIR__
    # Go up from Load_Sets -> Bas3ImageSegmentation -> workspace
    workspace = dirname(dirname(script_dir))
    # Check if there's a Datasets folder nearby
    datasets_path = joinpath(workspace, "Datasets", "augmented_balanced_metadata")
    if isdir(datasets_path)
        return datasets_path
    end
    
    error("Could not find augmented_balanced_metadata directory. Tried:\n  - $win_path\n  - $wsl_path\n  - $datasets_path")
end

const metadata_dir = resolve_data_path()
println("Resolved metadata directory: $(metadata_dir)")

const summary_file = joinpath(metadata_dir, "augmentation_summary.jld2")
println("Loading: $(summary_file)")

const summary_data_param = JLD2.load(summary_file)
const all_metadata_param = summary_data_param["all_metadata"]
println("Loaded $(length(all_metadata_param)) metadata entries")

# Extract parameter arrays
const scale_factors = [m.scale_factor for m in all_metadata_param]
const rotation_angles = [m.rotation_angle for m in all_metadata_param]
const shear_x_angles = [m.shear_x_angle for m in all_metadata_param]
const shear_y_angles = [m.shear_y_angle for m in all_metadata_param]
const brightness_factors = [m.brightness_factor for m in all_metadata_param]
const saturation_offsets = [m.saturation_offset for m in all_metadata_param]
const blur_kernel_sizes = [m.blur_kernel_size for m in all_metadata_param]
const blur_sigmas = [m.blur_sigma for m in all_metadata_param]
const flip_types = [m.flip_type for m in all_metadata_param]

# ============================================================================
# Figure Creation
# ============================================================================

println("Creating Parameter Distributions figure...")

fig = Figure(size=(1800, 1200))
fig[0, :] = Label(fig, "Augmentation Parameter Distributions (N=$(length(all_metadata_param)))", fontsize=24, font=:bold)

# Scale factor histogram
ax1 = Axis(fig[1, 1], title="Scale Factor", xlabel="Scale", ylabel="Count")
hist!(ax1, scale_factors, bins=20, color=:steelblue)

# Rotation angle histogram
ax2 = Axis(fig[1, 2], title="Rotation Angle", xlabel="Degrees", ylabel="Count")
hist!(ax2, rotation_angles, bins=36, color=:coral)

# Shear X histogram
ax3 = Axis(fig[1, 3], title="Shear X Angle", xlabel="Degrees", ylabel="Count")
hist!(ax3, shear_x_angles, bins=20, color=:mediumseagreen)

# Shear Y histogram
ax4 = Axis(fig[2, 1], title="Shear Y Angle", xlabel="Degrees", ylabel="Count")
hist!(ax4, shear_y_angles, bins=20, color=:mediumpurple)

# Brightness histogram
ax5 = Axis(fig[2, 2], title="Brightness Factor", xlabel="Factor", ylabel="Count")
hist!(ax5, brightness_factors, bins=10, color=:gold)

# Saturation histogram
ax6 = Axis(fig[2, 3], title="Saturation Offset", xlabel="Offset", ylabel="Count")
hist!(ax6, saturation_offsets, bins=10, color=:darkorange)

# Blur kernel size bar chart
ax7 = Axis(fig[3, 1], title="Blur Kernel Size", xlabel="Size", ylabel="Count", xticks=[3, 5, 7])
kernel_counts = [count(==(k), blur_kernel_sizes) for k in [3, 5, 7]]
barplot!(ax7, [3, 5, 7], kernel_counts, color=:slategray)

# Blur sigma histogram
ax8 = Axis(fig[3, 2], title="Blur Sigma", xlabel="σ", ylabel="Count")
hist!(ax8, blur_sigmas, bins=20, color=:teal)

# Flip type bar chart
ax9 = Axis(fig[3, 3], title="Flip Type", xlabel="Type", ylabel="Count", 
           xticks=(1:3, ["FlipX", "FlipY", "NoOp"]))
flip_counts = [count(==(t), flip_types) for t in [:flipx, :flipy, :noop]]
barplot!(ax9, 1:3, flip_counts, color=[:indianred, :cornflowerblue, :darkgray])

# ============================================================================
# Display
# ============================================================================

println("Displaying Parameter Distributions UI...")
display(fig)

println("\n✓ Parameter Distributions UI displayed successfully!")
println("  - 9 parameter distribution plots shown")
println("  - Close the window to exit")
