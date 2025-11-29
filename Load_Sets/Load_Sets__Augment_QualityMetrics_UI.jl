# ============================================================================
# Load_Sets__Augment_QualityMetrics_UI.jl
# ============================================================================
# UI component for displaying augmentation quality metrics.
# Shows: class composition, mean coverage, crop positions
#
# Usage:
#   include("Load_Sets__Augment_QualityMetrics_UI.jl")
#   fig = create_augment_quality_metrics_figure(all_metadata)
#   display(fig)
# ============================================================================

using Statistics

"""
    create_augment_quality_metrics_figure(all_metadata)

Create a figure showing quality metrics analysis.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples

# Returns
GLMakie Figure with 4 plots:
- Stacked area chart of class composition per sample
- Mean pixel coverage by target class
- Smart crop position scatter plot
- FG% vs Size Multiplier scatter plot
"""
function create_augment_quality_metrics_figure(all_metadata::Vector{AugmentationMetadata})
    # Extract data
    target_classes = [m.target_class for m in all_metadata]
    scar_pcts = [m.scar_percentage for m in all_metadata]
    redness_pcts = [m.redness_percentage for m in all_metadata]
    hematoma_pcts = [m.hematoma_percentage for m in all_metadata]
    necrosis_pcts = [m.necrosis_percentage for m in all_metadata]
    background_pcts = [m.background_percentage for m in all_metadata]
    
    class_order = AUGMENT_CLASS_ORDER
    
    # Extract growth metrics
    size_multipliers = [m.size_multiplier for m in all_metadata]
    actual_fg_percentages = [m.actual_fg_percentage for m in all_metadata]
    fg_thresholds_used = [m.fg_threshold_used for m in all_metadata]
    
    # Create figure (taller to accommodate 4 plots)
    fig = Bas3GLMakie.GLMakie.Figure(size=(1600, 1300))
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[0, :], 
        "Quality Metrics Analysis", 
        fontsize=24, 
        font=:bold
    )
    
    # Plot 1: Stacked area showing class composition (first 100 samples)
    ax_stack = Bas3GLMakie.GLMakie.Axis(
        fig[1, 1:2], 
        title="Class Composition per Sample (first 100 samples)",
        xlabel="Sample Index", 
        ylabel="Coverage (%)"
    )
    
    n_show = min(100, length(all_metadata))
    sample_range = 1:n_show
    
    # Stack the percentages
    y_scar = scar_pcts[sample_range]
    y_redness = y_scar .+ redness_pcts[sample_range]
    y_hematoma = y_redness .+ hematoma_pcts[sample_range]
    y_necrosis = y_hematoma .+ necrosis_pcts[sample_range]
    y_background = y_necrosis .+ background_pcts[sample_range]
    
    Bas3GLMakie.GLMakie.band!(ax_stack, collect(sample_range), zeros(n_show), y_scar, 
                              color=(:indianred, 0.8), label="Scar")
    Bas3GLMakie.GLMakie.band!(ax_stack, collect(sample_range), y_scar, y_redness, 
                              color=(:mediumseagreen, 0.8), label="Redness")
    Bas3GLMakie.GLMakie.band!(ax_stack, collect(sample_range), y_redness, y_hematoma, 
                              color=(:cornflowerblue, 0.8), label="Hematoma")
    Bas3GLMakie.GLMakie.band!(ax_stack, collect(sample_range), y_hematoma, y_necrosis, 
                              color=(:gold, 0.8), label="Necrosis")
    Bas3GLMakie.GLMakie.band!(ax_stack, collect(sample_range), y_necrosis, y_background, 
                              color=(:slategray, 0.8), label="Background")
    
    Bas3GLMakie.GLMakie.axislegend(ax_stack, position=:rt, nbanks=2)
    
    # Plot 2: Mean pixel coverage by target class
    ax_mean = Bas3GLMakie.GLMakie.Axis(
        fig[2, 1], 
        title="Mean Pixel Coverage by Target Class",
        xlabel="Target Class", 
        ylabel="Mean Coverage (%)",
        xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"])
    )
    
    # Group samples by target class and compute mean coverage
    target_class_indices = Dict(c => findall(==(c), target_classes) for c in class_order)
    
    mean_coverage_by_target = Float64[]
    for tc in class_order
        indices = target_class_indices[tc]
        if isempty(indices)
            push!(mean_coverage_by_target, 0.0)
        elseif tc == :scar
            push!(mean_coverage_by_target, mean(scar_pcts[indices]))
        elseif tc == :redness
            push!(mean_coverage_by_target, mean(redness_pcts[indices]))
        elseif tc == :hematoma
            push!(mean_coverage_by_target, mean(hematoma_pcts[indices]))
        elseif tc == :necrosis
            push!(mean_coverage_by_target, mean(necrosis_pcts[indices]))
        else
            push!(mean_coverage_by_target, mean(background_pcts[indices]))
        end
    end
    
    Bas3GLMakie.GLMakie.barplot!(ax_mean, 1:5, mean_coverage_by_target, color=collect(AUGMENT_CLASS_COLORS))
    
    # Plot 3: Smart crop position scatter plot
    ax_crop = Bas3GLMakie.GLMakie.Axis(
        fig[2, 2], 
        title="Smart Crop Positions",
        xlabel="X Start", 
        ylabel="Y Start"
    )
    
    crop_x = [m.smart_crop_x_start for m in all_metadata]
    crop_y = [m.smart_crop_y_start for m in all_metadata]
    
    # Color by target class
    target_class_nums = [findfirst(==(m.target_class), class_order) for m in all_metadata]
    Bas3GLMakie.GLMakie.scatter!(
        ax_crop, 
        crop_x, 
        crop_y, 
        color=target_class_nums, 
        colormap=:viridis, 
        markersize=4, 
        alpha=0.5
    )
    
    # Plot 4: FG% vs Size Multiplier scatter plot
    ax_growth = Bas3GLMakie.GLMakie.Axis(
        fig[3, :], 
        title="Actual FG% vs Size Multiplier (Growth Relationship)",
        xlabel="Size Multiplier (×)", 
        ylabel="Actual FG%"
    )
    
    # Scatter plot colored by target class
    Bas3GLMakie.GLMakie.scatter!(
        ax_growth, 
        size_multipliers, 
        actual_fg_percentages, 
        color=target_class_nums, 
        colormap=:viridis, 
        markersize=8, 
        alpha=0.6
    )
    
    # Add horizontal lines for typical thresholds
    unique_thresholds = sort(unique(fg_thresholds_used))
    for (i, thresh) in enumerate(unique_thresholds)
        if thresh < 100.0  # Don't plot 100% threshold (background)
            Bas3GLMakie.GLMakie.hlines!(ax_growth, [thresh], color=:red, linestyle=:dash, linewidth=1.5,
                                        label=(i == 1 ? "FG Thresholds" : nothing))
        end
    end
    
    # Add legend
    Bas3GLMakie.GLMakie.axislegend(ax_growth, position=:rt)
    
    return fig
end

"""
    save_augment_quality_metrics_figure(fig, output_path)

Save the quality metrics figure to a file.
"""
function save_augment_quality_metrics_figure(fig, output_path::String)
    Bas3GLMakie.GLMakie.save(output_path, fig)
    println("Saved: $(output_path)")
end

println("  Load_Sets__Augment_QualityMetrics_UI loaded")
