# Augment_Sets__SourceClassDistribution_StatisticsUI.jl
# Interactive UI for displaying source image usage and class distribution
# Displays: source usage histogram, target vs actual class distribution, pixel coverage

import Random

# ============================================================================
# Environment Setup
# ============================================================================

const _env_source_class = try
    _env_source_class
catch
    println("=== Initializing Source & Class Distribution UI ===")
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.resolve()

    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    using Bas3GLMakie.GLMakie: Figure, Label, Axis, barplot!, scatter!, lines!, axislegend
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

# Platform-independent path resolution
function resolve_data_path_sc()
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

const metadata_dir_sc = resolve_data_path_sc()
println("Resolved metadata directory: $(metadata_dir_sc)")

const summary_file_sc = joinpath(metadata_dir_sc, "augmentation_summary.jld2")
println("Loading: $(summary_file_sc)")

const summary_data_sc = JLD2.load(summary_file_sc)
const all_metadata_sc = summary_data_sc["all_metadata"]
const target_dist_sc = summary_data_sc["target_distribution"]
println("Loaded $(length(all_metadata_sc)) metadata entries")

# Extract arrays
const source_indices_sc = [m.source_index for m in all_metadata_sc]
const target_classes_sc = [m.target_class for m in all_metadata_sc]
const scar_pcts_sc = [m.scar_percentage for m in all_metadata_sc]
const redness_pcts_sc = [m.redness_percentage for m in all_metadata_sc]
const hematoma_pcts_sc = [m.hematoma_percentage for m in all_metadata_sc]
const necrosis_pcts_sc = [m.necrosis_percentage for m in all_metadata_sc]
const background_pcts_sc = [m.background_percentage for m in all_metadata_sc]

const class_order_sc = [:scar, :redness, :hematoma, :necrosis, :background]
const class_colors_sc = [:indianred, :mediumseagreen, :cornflowerblue, :gold, :slategray]

# ============================================================================
# Figure Creation
# ============================================================================

println("Creating Source & Class Distribution figure...")

fig = Figure(size=(1600, 1000))
fig[0, :] = Label(fig, "Source Image Usage & Class Distribution", fontsize=24, font=:bold)

# Source image usage histogram
ax_source = Axis(fig[1, 1:2], title="Source Image Usage Distribution", 
                 xlabel="Source Image Index", ylabel="Usage Count")
source_usage = [count(==(i), source_indices_sc) for i in 1:50]  # Assuming 50 source images
used_sources = findall(>(0), source_usage)
barplot!(ax_source, used_sources, source_usage[used_sources], color=:steelblue, 
         strokewidth=0.5, strokecolor=:black)

# Target class distribution (actual vs target)
ax_class = Axis(fig[2, 1], title="Target Class Distribution", 
                xlabel="Class", ylabel="Sample Count",
                xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

actual_counts = [count(==(c), target_classes_sc) for c in class_order_sc]
target_counts = [round(Int, target_dist_sc[c] / 100 * length(all_metadata_sc)) for c in class_order_sc]

# Grouped bar chart
barplot!(ax_class, (1:5) .- 0.15, actual_counts, width=0.3, color=:steelblue, label="Actual")
barplot!(ax_class, (1:5) .+ 0.15, target_counts, width=0.3, color=:coral, label="Target")
axislegend(ax_class, position=:rt)

# Pixel coverage distribution per class (box plot style)
ax_pixel = Axis(fig[2, 2], title="Pixel Coverage Distribution by Class",
                xlabel="Class", ylabel="Coverage (%)",
                xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

pixel_data = [scar_pcts_sc, redness_pcts_sc, hematoma_pcts_sc, necrosis_pcts_sc, background_pcts_sc]

for (i, (pcts, col)) in enumerate(zip(pixel_data, class_colors_sc))
    μ = mean(pcts)
    σ = std(pcts)
    min_v = minimum(pcts)
    max_v = maximum(pcts)
    
    # Draw range line
    lines!(ax_pixel, [i, i], [min_v, max_v], color=col, linewidth=2)
    # Draw mean ± std box
    lines!(ax_pixel, [i-0.2, i+0.2], [μ-σ, μ-σ], color=col, linewidth=2)
    lines!(ax_pixel, [i-0.2, i+0.2], [μ+σ, μ+σ], color=col, linewidth=2)
    lines!(ax_pixel, [i-0.2, i-0.2], [μ-σ, μ+σ], color=col, linewidth=2)
    lines!(ax_pixel, [i+0.2, i+0.2], [μ-σ, μ+σ], color=col, linewidth=2)
    # Draw mean point
    scatter!(ax_pixel, [i], [μ], color=col, markersize=12)
end

# ============================================================================
# Display
# ============================================================================

println("Displaying Source & Class Distribution UI...")
display(fig)

println("\n✓ Source & Class Distribution UI displayed successfully!")
println("  - Source image usage histogram")
println("  - Actual vs Target class distribution")
println("  - Pixel coverage distribution by class")
println("  - Close the window to exit")
