# Augment_Sets__SummaryDashboard_StatisticsUI.jl
# Interactive UI for displaying summary statistics dashboard
# Displays: statistics text panel and pie chart of target class distribution

import Random

# ============================================================================
# Environment Setup
# ============================================================================

const _env_summary = try
    _env_summary
catch
    println("=== Initializing Summary Dashboard UI ===")
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.resolve()

    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    using Bas3GLMakie.GLMakie: Figure, Label, Axis, poly!, text!, limits!
    using Bas3GLMakie.GLMakie: hidedecorations!, hidespines!, DataAspect, save, display, Point2f

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

# Platform-independent path resolution
function resolve_data_path_sum()
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
    
    error("Could not find augmented_balanced_metadata directory. Tried:\n  - $win_path\n  - $wsl_path")
end

const metadata_dir_sum = resolve_data_path_sum()
println("Resolved metadata directory: $(metadata_dir_sum)")

const summary_file_sum = joinpath(metadata_dir_sum, "augmentation_summary.jld2")
println("Loading: $(summary_file_sum)")

const summary_data_sum = JLD2.load(summary_file_sum)
const all_metadata_sum = summary_data_sum["all_metadata"]
println("Loaded $(length(all_metadata_sum)) metadata entries")

# Extract arrays
const scale_factors_sum = [m.scale_factor for m in all_metadata_sum]
const rotation_angles_sum = [m.rotation_angle for m in all_metadata_sum]
const shear_x_angles_sum = [m.shear_x_angle for m in all_metadata_sum]
const shear_y_angles_sum = [m.shear_y_angle for m in all_metadata_sum]
const brightness_factors_sum = [m.brightness_factor for m in all_metadata_sum]
const saturation_offsets_sum = [m.saturation_offset for m in all_metadata_sum]
const blur_sigmas_sum = [m.blur_sigma for m in all_metadata_sum]
const source_indices_sum = [m.source_index for m in all_metadata_sum]
const target_classes_sum = [m.target_class for m in all_metadata_sum]
const scar_pcts_sum = [m.scar_percentage for m in all_metadata_sum]
const redness_pcts_sum = [m.redness_percentage for m in all_metadata_sum]
const hematoma_pcts_sum = [m.hematoma_percentage for m in all_metadata_sum]
const necrosis_pcts_sum = [m.necrosis_percentage for m in all_metadata_sum]
const background_pcts_sum = [m.background_percentage for m in all_metadata_sum]

const class_order_sum = [:scar, :redness, :hematoma, :necrosis, :background]
const class_colors_sum = [:red, :orange, :purple, :black, :gray]

const augmented_size = (100, 50)

# ============================================================================
# Figure Creation
# ============================================================================

println("Creating Summary Dashboard figure...")

fig = Figure(size=(1400, 900))
fig[0, :] = Label(fig, "Augmentation Summary Dashboard", fontsize=24, font=:bold)

# Statistics text panel
stats_text = """
Dataset Statistics:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Augmented Samples: $(length(all_metadata_sum))
Original Source Images: 50
Unique Sources Used: $(length(unique(source_indices_sum)))
Image Size: $(augmented_size[1])×$(augmented_size[2]) pixels

Parameter Ranges:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scale Factor: $(round(minimum(scale_factors_sum), digits=2)) - $(round(maximum(scale_factors_sum), digits=2))
Rotation: $(round(minimum(rotation_angles_sum), digits=1))° - $(round(maximum(rotation_angles_sum), digits=1))°
Shear X: $(round(minimum(shear_x_angles_sum), digits=1))° - $(round(maximum(shear_x_angles_sum), digits=1))°
Shear Y: $(round(minimum(shear_y_angles_sum), digits=1))° - $(round(maximum(shear_y_angles_sum), digits=1))°
Brightness: $(round(minimum(brightness_factors_sum), digits=2)) - $(round(maximum(brightness_factors_sum), digits=2))
Saturation: $(round(minimum(saturation_offsets_sum), digits=2)) - $(round(maximum(saturation_offsets_sum), digits=2))
Blur σ: $(round(minimum(blur_sigmas_sum), digits=2)) - $(round(maximum(blur_sigmas_sum), digits=2))

Class Distribution:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scar: $(count(==(Symbol("scar")), target_classes_sum)) samples ($(round(mean(scar_pcts_sum), digits=2))% mean coverage)
Redness: $(count(==(Symbol("redness")), target_classes_sum)) samples ($(round(mean(redness_pcts_sum), digits=2))% mean coverage)
Hematoma: $(count(==(Symbol("hematoma")), target_classes_sum)) samples ($(round(mean(hematoma_pcts_sum), digits=2))% mean coverage)
Necrosis: $(count(==(Symbol("necrosis")), target_classes_sum)) samples ($(round(mean(necrosis_pcts_sum), digits=2))% mean coverage)
Background: $(count(==(Symbol("background")), target_classes_sum)) samples ($(round(mean(background_pcts_sum), digits=2))% mean coverage)
"""

Label(fig[1, 1], stats_text, fontsize=12, halign=:left, valign=:top, font=:regular,
      tellwidth=false, tellheight=false)

# Pie chart for target class distribution
ax_pie = Axis(fig[1, 2], title="Target Class Distribution", aspect=DataAspect())
hidedecorations!(ax_pie)
hidespines!(ax_pie)

pie_values = [count(==(c), target_classes_sum) for c in class_order_sum]
pie_colors = class_colors_sum

# Simple pie chart using arcs - wrapped in let block for proper scope
let
    total = sum(pie_values)
    start_angle = 0.0
    for (i, (val, col)) in enumerate(zip(pie_values, pie_colors))
        angle = 2π * val / total
        end_angle = start_angle + angle
        
        # Draw pie slice as polygon
        n_points = max(10, round(Int, angle * 20))
        angles = range(start_angle, end_angle, length=n_points)
        xs = [0.0; cos.(angles)]
        ys = [0.0; sin.(angles)]
        poly!(ax_pie, Point2f.(xs, ys), color=col)
        
        # Add label
        mid_angle = (start_angle + end_angle) / 2
        label_r = 0.7
        text!(ax_pie, label_r * cos(mid_angle), label_r * sin(mid_angle),
              text="$(round(100*val/total, digits=1))%", fontsize=10, align=(:center, :center))
        
        start_angle = end_angle
    end
end

limits!(ax_pie, -1.3, 1.3, -1.3, 1.3)

# ============================================================================
# Display
# ============================================================================

println("Displaying Summary Dashboard UI...")
display(fig)

println("\n✓ Summary Dashboard UI displayed successfully!")
println("  - Dataset statistics panel")
println("  - Parameter ranges")
println("  - Class distribution pie chart")
println("  - Close the window to exit")
