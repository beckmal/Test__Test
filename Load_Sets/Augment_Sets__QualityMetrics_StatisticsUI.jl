# Augment_Sets__QualityMetrics_StatisticsUI.jl
# Interactive UI for displaying quality metrics analysis
# Displays: class composition stacked area, mean coverage by target class, smart crop positions

import Random

# ============================================================================
# Environment Setup
# ============================================================================

const _env_quality = try
    _env_quality
catch
    println("=== Initializing Quality Metrics UI ===")
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.resolve()

    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    using Bas3GLMakie.GLMakie: Figure, Label, Axis, band!, barplot!, scatter!, axislegend
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
function resolve_data_path_qm()
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

const metadata_dir_qm = resolve_data_path_qm()
println("Resolved metadata directory: $(metadata_dir_qm)")

const summary_file_qm = joinpath(metadata_dir_qm, "augmentation_summary.jld2")
println("Loading: $(summary_file_qm)")

const summary_data_qm = JLD2.load(summary_file_qm)
const all_metadata_qm = summary_data_qm["all_metadata"]
println("Loaded $(length(all_metadata_qm)) metadata entries")

# Extract arrays
const target_classes_qm = [m.target_class for m in all_metadata_qm]
const scar_pcts_qm = [m.scar_percentage for m in all_metadata_qm]
const redness_pcts_qm = [m.redness_percentage for m in all_metadata_qm]
const hematoma_pcts_qm = [m.hematoma_percentage for m in all_metadata_qm]
const necrosis_pcts_qm = [m.necrosis_percentage for m in all_metadata_qm]
const background_pcts_qm = [m.background_percentage for m in all_metadata_qm]

const class_order_qm = [:scar, :redness, :hematoma, :necrosis, :background]
const class_colors_qm = [:indianred, :mediumseagreen, :cornflowerblue, :gold, :slategray]

# ============================================================================
# Figure Creation
# ============================================================================

println("Creating Quality Metrics figure...")

fig = Figure(size=(1600, 1000))
fig[0, :] = Label(fig, "Quality Metrics Analysis", fontsize=24, font=:bold)

# Stacked area showing class composition across samples (first 100 samples)
ax_stack = Axis(fig[1, 1:2], title="Class Composition per Sample (first 100 samples)",
                xlabel="Sample Index", ylabel="Coverage (%)")

n_show = min(100, length(all_metadata_qm))
sample_range = 1:n_show

# Stack the percentages
y_scar = scar_pcts_qm[sample_range]
y_redness = y_scar .+ redness_pcts_qm[sample_range]
y_hematoma = y_redness .+ hematoma_pcts_qm[sample_range]
y_necrosis = y_hematoma .+ necrosis_pcts_qm[sample_range]
y_background = y_necrosis .+ background_pcts_qm[sample_range]

band!(ax_stack, collect(sample_range), zeros(n_show), y_scar, color=(:indianred, 0.8), label="Scar")
band!(ax_stack, collect(sample_range), y_scar, y_redness, color=(:mediumseagreen, 0.8), label="Redness")
band!(ax_stack, collect(sample_range), y_redness, y_hematoma, color=(:cornflowerblue, 0.8), label="Hematoma")
band!(ax_stack, collect(sample_range), y_hematoma, y_necrosis, color=(:gold, 0.8), label="Necrosis")
band!(ax_stack, collect(sample_range), y_necrosis, y_background, color=(:slategray, 0.8), label="Background")

axislegend(ax_stack, position=:rt, nbanks=2)

# Mean pixel coverage by target class
ax_mean = Axis(fig[2, 1], title="Mean Pixel Coverage by Target Class",
               xlabel="Target Class", ylabel="Mean Coverage (%)",
               xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"]))

# Group samples by target class and compute mean pixel coverage for each class
target_class_indices_qm = Dict(c => findall(==(c), target_classes_qm) for c in class_order_qm)

# For each target class, show mean of the corresponding pixel class
mean_coverage_by_target = Float64[]
for (i, tc) in enumerate(class_order_qm)
    indices = target_class_indices_qm[tc]
    if tc == :scar
        push!(mean_coverage_by_target, mean(scar_pcts_qm[indices]))
    elseif tc == :redness
        push!(mean_coverage_by_target, mean(redness_pcts_qm[indices]))
    elseif tc == :hematoma
        push!(mean_coverage_by_target, mean(hematoma_pcts_qm[indices]))
    elseif tc == :necrosis
        push!(mean_coverage_by_target, mean(necrosis_pcts_qm[indices]))
    else
        push!(mean_coverage_by_target, mean(background_pcts_qm[indices]))
    end
end

barplot!(ax_mean, 1:5, mean_coverage_by_target, color=class_colors_qm)

# Smart crop position scatter plot
ax_crop = Axis(fig[2, 2], title="Smart Crop Positions",
               xlabel="X Start", ylabel="Y Start")
crop_x = [m.smart_crop_x_start for m in all_metadata_qm]
crop_y = [m.smart_crop_y_start for m in all_metadata_qm]

# Color by target class
target_class_nums = [findfirst(==(m.target_class), class_order_qm) for m in all_metadata_qm]
scatter!(ax_crop, crop_x, crop_y, color=target_class_nums, colormap=:viridis, 
         markersize=4, alpha=0.5)

# ============================================================================
# Display
# ============================================================================

println("Displaying Quality Metrics UI...")
display(fig)

println("\n✓ Quality Metrics UI displayed successfully!")
println("  - Class composition stacked area chart")
println("  - Mean pixel coverage by target class")
println("  - Smart crop position scatter plot")
println("  - Close the window to exit")
