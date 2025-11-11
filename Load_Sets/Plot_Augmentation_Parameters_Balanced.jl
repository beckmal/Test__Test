"""
Visualize augmentation parameters for balanced dataset with explicit metadata

Creates comprehensive plots showing the distribution of all transformation parameters
Layout: 2 rows with 6 plots each, matching the explicit augmentation visualization
"""

import Pkg
Pkg.activate(@__DIR__)

using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2
using Statistics
using Dates

println("Loading Bas3GLMakie...")
using Bas3GLMakie
using Bas3GLMakie.GLMakie: Figure, Axis, scatter!, barplot!, lines!, text!
using Bas3GLMakie.GLMakie: Label, Legend, colsize!, Fixed

# Path setup
function resolve_path(relative_path::String)
    if Sys.iswindows()
        if startswith(relative_path, "/mnt/")
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        if occursin(r"^[A-Za-z]:[/\\]", relative_path)
            drive_letter = lowercase(relative_path[1])
            rest_of_path = replace(relative_path[4:end], "\\" => "/")
            return "/mnt/$(drive_letter)/$(rest_of_path)"
        else
            return relative_path
        end
    end
end

base_path = resolve_path("C:/Syncthing/Datasets")
metadata_dir = joinpath(base_path, "augmented_balanced_metadata")
summary_file = joinpath(metadata_dir, "augmentation_summary.jld2")

println("\n" * "="^80)
println("BALANCED AUGMENTATION PARAMETER VISUALIZATION")
println("="^80)

if !isfile(summary_file)
    println("ERROR: Metadata file not found at: $(summary_file)")
    exit(1)
end

println("Loading metadata from: $(summary_file)")
data = JLD2.load(summary_file)
all_metadata = data["all_metadata"]
println("✓ Loaded $(length(all_metadata)) samples")

# Extract all parameters
sample_indices = 1:length(all_metadata)
scale_factors = [m.scale_factor for m in all_metadata]
rotation_angles = [m.rotation_angle for m in all_metadata]
shear_x_angles = [m.shear_x_angle for m in all_metadata]
shear_y_angles = [m.shear_y_angle for m in all_metadata]
brightness_factors = [m.brightness_factor for m in all_metadata]
saturation_offsets = [m.saturation_offset for m in all_metadata]
blur_kernel_sizes = [m.blur_kernel_size for m in all_metadata]
blur_sigmas = [m.blur_sigma for m in all_metadata]
smart_crop_x = [m.smart_crop_x_start for m in all_metadata]
smart_crop_y = [m.smart_crop_y_start for m in all_metadata]

# Flip types as numbers for plotting
flip_types = [m.flip_type for m in all_metadata]
flip_numbers = [ft == :flipx ? 1 : (ft == :flipy ? 2 : 3) for ft in flip_types]
flip_labels = ["FlipX", "FlipY", "NoOp"]
flip_colors = [:red, :blue, :green]

# Target class tracking (unique to balanced dataset)
target_classes = [m.target_class for m in all_metadata]
class_counts = Dict{Symbol, Int}()
for cls in target_classes
    class_counts[cls] = get(class_counts, cls, 0) + 1
end
sorted_classes = sort(collect(class_counts), by=x->x[2], rev=true)
class_names = [String(x[1]) for x in sorted_classes]
class_sample_counts = [x[2] for x in sorted_classes]

# Source image usage tracking
source_indices = [m.source_index for m in all_metadata]
source_counts = Dict{Int, Int}()
for idx in source_indices
    source_counts[idx] = get(source_counts, idx, 0) + 1
end
sorted_sources = sort(collect(source_counts), by=x->x[1])
source_ids = [x[1] for x in sorted_sources]
usage_counts = [x[2] for x in sorted_sources]

println("\n" * "="^80)
println("Creating visualizations...")
println("="^80)

# ============================================================================
# Create figure with 2 rows, 6 columns each
# ============================================================================

fig = Figure(size=(3600, 1000), fontsize=14, figure_padding=(20, 40, 20, 40))

# Title spanning all columns
Label(fig[1, :], "Balanced Augmentation Parameter Analysis - $(length(all_metadata)) Samples", 
      fontsize=28, font=:bold)

# ============================================================================
# Row 2, Column 1: Source Image Occurrence
# ============================================================================

ax1 = Axis(fig[2, 1],
    title="Source Image Occurrence",
    xlabel="Source Image ID",
    ylabel="Number of Occurrences"
)
barplot!(ax1, source_ids, usage_counts, color=:steelblue)

# ============================================================================
# Row 2, Column 2: Scale Factor
# ============================================================================

ax2 = Axis(fig[2, 2], 
    title="Scale Factor",
    xlabel="Source Image ID",
    ylabel="Scale Factor"
)
scatter!(ax2, source_indices, scale_factors, color=:blue, markersize=8)
lines!(ax2, [minimum(source_indices), maximum(source_indices)], [1.0, 1.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 3: Rotation Angle
# ============================================================================

ax3 = Axis(fig[2, 3],
    title="Rotation Angle",
    xlabel="Source Image ID",
    ylabel="Degrees"
)
scatter!(ax3, source_indices, rotation_angles, color=:orange, markersize=8)
lines!(ax3, [minimum(source_indices), maximum(source_indices)], [0.0, 0.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 4: Brightness Factor
# ============================================================================

ax4 = Axis(fig[2, 4],
    title="Brightness Factor",
    xlabel="Source Image ID",
    ylabel="Brightness Multiplier"
)
scatter!(ax4, source_indices, brightness_factors, color=:gold, markersize=8)
lines!(ax4, [minimum(source_indices), maximum(source_indices)], [1.0, 1.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 5: Saturation Offset
# ============================================================================

ax5 = Axis(fig[2, 5],
    title="Saturation Offset",
    xlabel="Source Image ID",
    ylabel="Saturation Offset"
)
scatter!(ax5, source_indices, saturation_offsets, color=:purple, markersize=8)
lines!(ax5, [minimum(source_indices), maximum(source_indices)], [0.0, 0.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 6: Blur Sigma
# ============================================================================

ax6 = Axis(fig[2, 6],
    title="Blur Sigma (σ)",
    xlabel="Source Image ID",
    ylabel="Sigma Value"
)
scatter!(ax6, source_indices, blur_sigmas, color=:teal, markersize=8)

# ============================================================================
# Row 3, Column 1: Blur Kernel Size
# ============================================================================

ax7 = Axis(fig[3, 1],
    title="Blur Kernel Size",
    xlabel="Source Image ID",
    ylabel="Kernel Size",
    yticks=[3, 5, 7]
)
scatter!(ax7, source_indices, blur_kernel_sizes, color=:cyan, markersize=8)

# ============================================================================
# Row 3, Column 2: Smart Crop Y Position
# ============================================================================

ax8 = Axis(fig[3, 2],
    title="Smart Crop Y Position",
    xlabel="Source Image ID",
    ylabel="Y Position (pixels)"
)
scatter!(ax8, source_indices, smart_crop_y, color=:magenta, markersize=8)

# ============================================================================
# Row 3, Column 3: Smart Crop X Position
# ============================================================================

ax9 = Axis(fig[3, 3],
    title="Smart Crop X Position",
    xlabel="Source Image ID",
    ylabel="X Position (pixels)"
)
scatter!(ax9, source_indices, smart_crop_x, color=:brown, markersize=8)

# ============================================================================
# Row 3, Column 4: Shear X Angle
# ============================================================================

ax10 = Axis(fig[3, 4],
    title="Shear X Angle",
    xlabel="Source Image ID",
    ylabel="Degrees"
)
scatter!(ax10, source_indices, shear_x_angles, color=:red, markersize=8)
lines!(ax10, [minimum(source_indices), maximum(source_indices)], [0.0, 0.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 3, Column 5: Shear Y Angle
# ============================================================================

ax11 = Axis(fig[3, 5],
    title="Shear Y Angle",
    xlabel="Source Image ID",
    ylabel="Degrees"
)
scatter!(ax11, source_indices, shear_y_angles, color=:blue, markersize=8)
lines!(ax11, [minimum(source_indices), maximum(source_indices)], [0.0, 0.0], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 3, Column 6: Flip Type
# ============================================================================

ax12 = Axis(fig[3, 6],
    title="Flip Type",
    xlabel="Source Image ID",
    ylabel="Flip Operation",
    yticks=(1:3, flip_labels)
)
scatter!(ax12, source_indices, flip_numbers, color=[flip_colors[fn] for fn in flip_numbers], markersize=8)

# ============================================================================
# Save figure
# ============================================================================

output_file = "Augmentation_Parameters_Balanced_$(length(all_metadata))_samples.png"
println("\nSaving visualization to: $(output_file)")
save(output_file, fig)

println("✓ Visualization saved successfully")

# Also display
display(fig)

println("\n" * "="^80)
println("VISUALIZATION COMPLETE")
println("="^80)
println("File: $(output_file)")
println("\nThe visualization shows (2 rows, 6 columns each):")
println("  • Row 2: Source Image | Scale Factor | Rotation | Brightness | Saturation | Blur Sigma")
println("  • Row 3: Blur Kernel | Smart Crop Y | Smart Crop X | Shear X | Shear Y | Flip Type")
println("="^80)
