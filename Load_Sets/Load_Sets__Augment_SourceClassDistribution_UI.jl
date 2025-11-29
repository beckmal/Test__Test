# ============================================================================
# Load_Sets__Augment_SourceClassDistribution_UI.jl
# ============================================================================
# UI component for displaying source image usage and class distribution.
#
# Usage:
#   include("Load_Sets__Augment_SourceClassDistribution_UI.jl")
#   fig = create_augment_source_class_distribution_figure(all_metadata, target_dist, num_sources)
#   display(fig)
# ============================================================================

using Statistics

"""
    create_augment_source_class_distribution_figure(all_metadata, target_distribution, num_sources)

Create a figure showing source image usage and class distribution.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples
- `target_distribution::Dict{Symbol, Float64}` - Target class distribution percentages
- `num_sources::Int` - Total number of source images available

# Returns
GLMakie Figure with 3 plots:
- Source image usage histogram
- Target class distribution (actual vs target)
- Pixel coverage distribution by class
"""
function create_augment_source_class_distribution_figure(
    all_metadata::Vector{AugmentationMetadata},
    target_distribution::Dict{Symbol, Float64},
    num_sources::Int
)
    # Extract data
    source_indices = [m.source_index for m in all_metadata]
    target_classes = [m.target_class for m in all_metadata]
    scar_pcts = [m.scar_percentage for m in all_metadata]
    redness_pcts = [m.redness_percentage for m in all_metadata]
    hematoma_pcts = [m.hematoma_percentage for m in all_metadata]
    necrosis_pcts = [m.necrosis_percentage for m in all_metadata]
    background_pcts = [m.background_percentage for m in all_metadata]
    
    # Create figure
    fig = Bas3GLMakie.GLMakie.Figure(size=(1600, 1000))
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[0, :], 
        "Source Image Usage & Class Distribution", 
        fontsize=24, 
        font=:bold
    )
    
    # Plot 1: Source image usage histogram
    ax_source = Bas3GLMakie.GLMakie.Axis(
        fig[1, 1:2], 
        title="Source Image Usage Distribution", 
        xlabel="Source Image Index", 
        ylabel="Usage Count"
    )
    source_usage = [count(==(i), source_indices) for i in 1:num_sources]
    used_sources = findall(>(0), source_usage)
    Bas3GLMakie.GLMakie.barplot!(
        ax_source, 
        used_sources, 
        source_usage[used_sources], 
        color=:steelblue, 
        strokewidth=0.5, 
        strokecolor=:black
    )
    
    # Plot 2: Target class distribution (actual vs target)
    class_order = AUGMENT_CLASS_ORDER
    ax_class = Bas3GLMakie.GLMakie.Axis(
        fig[2, 1], 
        title="Target Class Distribution", 
        xlabel="Class", 
        ylabel="Sample Count",
        xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"])
    )
    
    actual_counts = [count(==(c), target_classes) for c in class_order]
    target_counts = [round(Int, target_distribution[c] / 100 * length(all_metadata)) for c in class_order]
    
    # Grouped bar chart
    Bas3GLMakie.GLMakie.barplot!(ax_class, (1:5) .- 0.15, actual_counts, width=0.3, color=:steelblue, label="Actual")
    Bas3GLMakie.GLMakie.barplot!(ax_class, (1:5) .+ 0.15, target_counts, width=0.3, color=:coral, label="Target")
    Bas3GLMakie.GLMakie.axislegend(ax_class, position=:rt)
    
    # Plot 3: Pixel coverage distribution per class
    ax_pixel = Bas3GLMakie.GLMakie.Axis(
        fig[2, 2], 
        title="Pixel Coverage Distribution by Class",
        xlabel="Class", 
        ylabel="Coverage (%)",
        xticks=(1:5, ["Scar", "Redness", "Hematoma", "Necrosis", "Background"])
    )
    
    pixel_data = [scar_pcts, redness_pcts, hematoma_pcts, necrosis_pcts, background_pcts]
    class_colors = AUGMENT_CLASS_COLORS
    
    for (i, (pcts, col)) in enumerate(zip(pixel_data, class_colors))
        μ = mean(pcts)
        σ = std(pcts)
        min_v = minimum(pcts)
        max_v = maximum(pcts)
        
        # Draw range line
        Bas3GLMakie.GLMakie.lines!(ax_pixel, [i, i], [min_v, max_v], color=col, linewidth=2)
        # Draw mean ± std box
        Bas3GLMakie.GLMakie.lines!(ax_pixel, [i-0.2, i+0.2], [μ-σ, μ-σ], color=col, linewidth=2)
        Bas3GLMakie.GLMakie.lines!(ax_pixel, [i-0.2, i+0.2], [μ+σ, μ+σ], color=col, linewidth=2)
        Bas3GLMakie.GLMakie.lines!(ax_pixel, [i-0.2, i-0.2], [μ-σ, μ+σ], color=col, linewidth=2)
        Bas3GLMakie.GLMakie.lines!(ax_pixel, [i+0.2, i+0.2], [μ-σ, μ+σ], color=col, linewidth=2)
        # Draw mean point
        Bas3GLMakie.GLMakie.scatter!(ax_pixel, [i], [μ], color=col, markersize=12)
    end
    
    return fig
end

"""
    save_augment_source_class_distribution_figure(fig, output_path)

Save the source/class distribution figure to a file.
"""
function save_augment_source_class_distribution_figure(fig, output_path::String)
    Bas3GLMakie.GLMakie.save(output_path, fig)
    println("Saved: $(output_path)")
end

println("  Load_Sets__Augment_SourceClassDistribution_UI loaded")
