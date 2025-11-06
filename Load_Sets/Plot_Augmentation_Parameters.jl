"""
Visualize augmentation parameters for all generated samples

Creates comprehensive plots showing the distribution of all transformation parameters
Layout: 4 rows with 2-3 plots each
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
metadata_dir = joinpath(base_path, "augmented_explicit_metadata")
summary_file = joinpath(metadata_dir, "augmentation_summary.jld2")

println("\n" * "="^80)
println("AUGMENTATION PARAMETER VISUALIZATION")
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
crop_y_positions = [m.crop_y_start for m in all_metadata]
crop_x_positions = [m.crop_x_start for m in all_metadata]

# Flip types as numbers for plotting
flip_types = [m.flip_type for m in all_metadata]
flip_numbers = [ft == :flipx ? 1 : (ft == :flipy ? 2 : 3) for ft in flip_types]
flip_labels = ["FlipX", "FlipY", "NoOp"]
flip_colors = [:red, :blue, :green]

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
Label(fig[1, :], "Augmentation Parameter Analysis - $(length(all_metadata)) Samples", 
      fontsize=28, font=:bold)

# ============================================================================
# Row 2, Column 1: Source Image Usage Frequency
# ============================================================================

ax1 = Axis(fig[2, 1],
    title="Source Image Usage Frequency",
    xlabel="Number of Times Used",
    ylabel="Original Image Index",
    yticks=source_ids
)
barplot!(ax1, source_ids, usage_counts, direction=:x, color=:steelblue)
for i in 1:length(source_ids)
    text!(ax1, usage_counts[i] + 0.3, source_ids[i], 
          text="$(usage_counts[i])", 
          fontsize=12, align=(:left, :center))
end

# Add summary line
avg_usage = mean(usage_counts)
lines!(ax1, [avg_usage, avg_usage], [minimum(source_ids)-1, maximum(source_ids)+1], 
       color=:red, linestyle=:dash, linewidth=2, label="Average: $(round(avg_usage, digits=1))")
Legend(fig[2, 1], ax1, position=:rt, framevisible=true)

# ============================================================================
# Row 2, Column 2: Scale Factor
# ============================================================================

ax2 = Axis(fig[2, 2], 
    title="Scale Factor",
    xlabel="Scale Factor",
    ylabel="Original Image Index"
)
scatter!(ax2, scale_factors, source_indices, color=:blue, markersize=8)
lines!(ax2, [1.0, 1.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 3: Rotation Angle
# ============================================================================

ax3 = Axis(fig[2, 3],
    title="Rotation Angle",
    xlabel="Degrees",
    ylabel="Original Image Index"
)
scatter!(ax3, rotation_angles, source_indices, color=:orange, markersize=8)
lines!(ax3, [0.0, 0.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 4: Brightness Factor
# ============================================================================

ax4 = Axis(fig[2, 4],
    title="Brightness Factor",
    xlabel="Brightness Multiplier",
    ylabel="Original Image Index"
)
scatter!(ax4, brightness_factors, source_indices, color=:gold, markersize=8)
lines!(ax4, [1.0, 1.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 5: Saturation Offset
# ============================================================================

ax5 = Axis(fig[2, 5],
    title="Saturation Offset",
    xlabel="Saturation Offset",
    ylabel="Original Image Index"
)
scatter!(ax5, saturation_offsets, source_indices, color=:purple, markersize=8)
lines!(ax5, [0.0, 0.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 2, Column 6: Blur Sigma
# ============================================================================

ax6 = Axis(fig[2, 6],
    title="Blur Sigma (σ)",
    xlabel="Sigma Value",
    ylabel="Original Image Index"
)
scatter!(ax6, blur_sigmas, source_indices, color=:teal, markersize=8)

# ============================================================================
# Row 3, Column 1: Blur Kernel Size
# ============================================================================

ax7 = Axis(fig[3, 1],
    title="Blur Kernel Size",
    xlabel="Kernel Size",
    ylabel="Original Image Index",
    xticks=[3, 5, 7]
)
scatter!(ax7, blur_kernel_sizes, source_indices, color=:cyan, markersize=8)

# ============================================================================
# Row 3, Column 2: Crop Y Position
# ============================================================================

ax8 = Axis(fig[3, 2],
    title="Crop Start Position - Y Coordinate",
    xlabel="Y Position (pixels)",
    ylabel="Original Image Index"
)
scatter!(ax8, crop_y_positions, source_indices, color=:magenta, markersize=8)

# ============================================================================
# Row 3, Column 3: Crop X Position
# ============================================================================

ax9 = Axis(fig[3, 3],
    title="Crop Start Position - X Coordinate",
    xlabel="X Position (pixels)",
    ylabel="Original Image Index"
)
scatter!(ax9, crop_x_positions, source_indices, color=:brown, markersize=8)

# ============================================================================
# Row 3, Column 4: Shear X Angle
# ============================================================================

ax10 = Axis(fig[3, 4],
    title="Shear X Angle",
    xlabel="Degrees",
    ylabel="Original Image Index"
)
scatter!(ax10, shear_x_angles, source_indices, color=:red, markersize=8)
lines!(ax10, [0.0, 0.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 3, Column 5: Shear Y Angle
# ============================================================================

ax11 = Axis(fig[3, 5],
    title="Shear Y Angle",
    xlabel="Degrees",
    ylabel="Original Image Index"
)
scatter!(ax11, shear_y_angles, source_indices, color=:blue, markersize=8)
lines!(ax11, [0.0, 0.0], [minimum(source_indices), maximum(source_indices)], color=:gray, linestyle=:dash, linewidth=2)

# ============================================================================
# Row 3, Column 6: Flip Type
# ============================================================================

ax12 = Axis(fig[3, 6],
    title="Flip Type",
    xlabel="Flip Operation",
    ylabel="Original Image Index",
    xticks=(1:3, flip_labels)
)
scatter!(ax12, flip_numbers, source_indices, color=[flip_colors[fn] for fn in flip_numbers], markersize=8)

# ============================================================================
# Set all columns to equal width
# ============================================================================

#=
for col in 1:6
    colsize!(fig.layout, col, Fixed(560))
end
=#
# ============================================================================
# Save figure
# ============================================================================

output_file = "Augmentation_Parameters_$(length(all_metadata))_samples.png"
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
println("  • Row 2: Source Usage | Scale Factor | Rotation | Brightness | Saturation | Blur Sigma")
println("  • Row 3: Blur Kernel | Crop Y | Crop X | Shear X | Shear Y | Flip Type")
println("="^80)
