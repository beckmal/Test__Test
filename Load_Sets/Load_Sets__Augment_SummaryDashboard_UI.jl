# ============================================================================
# Load_Sets__Augment_SummaryDashboard_UI.jl
# ============================================================================
# UI component for displaying augmentation summary dashboard.
# Shows: Statistics text panel + pie chart of class distribution
#
# Usage:
#   include("Load_Sets__Augment_SummaryDashboard_UI.jl")
#   fig = create_augment_summary_dashboard_figure(all_metadata, target_dist, num_sources, augmented_size)
#   display(fig)
# ============================================================================

using Statistics

"""
    create_augment_summary_dashboard_figure(all_metadata, target_distribution, num_sources, augmented_size)

Create a summary dashboard figure with statistics and pie chart.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples
- `target_distribution::Dict{Symbol, Float64}` - Target class distribution
- `num_sources::Int` - Total number of source images
- `augmented_size::Tuple{Int,Int}` - Size of augmented images (height, width)

# Returns
GLMakie Figure with:
- Left panel: Statistics text
- Right panel: Pie chart of target class distribution
"""
function create_augment_summary_dashboard_figure(
    all_metadata::Vector{AugmentationMetadata},
    target_distribution::Dict{Symbol, Float64},
    num_sources::Int,
    augmented_size::Tuple{Int,Int}
)
    # Extract data
    source_indices = [m.source_index for m in all_metadata]
    target_classes = [m.target_class for m in all_metadata]
    scale_factors = [m.scale_factor for m in all_metadata]
    rotation_angles = [m.rotation_angle for m in all_metadata]
    shear_x_angles = [m.shear_x_angle for m in all_metadata]
    shear_y_angles = [m.shear_y_angle for m in all_metadata]
    brightness_factors = [m.brightness_factor for m in all_metadata]
    saturation_offsets = [m.saturation_offset for m in all_metadata]
    blur_sigmas = [m.blur_sigma for m in all_metadata]
    
    scar_pcts = [m.scar_percentage for m in all_metadata]
    redness_pcts = [m.redness_percentage for m in all_metadata]
    hematoma_pcts = [m.hematoma_percentage for m in all_metadata]
    necrosis_pcts = [m.necrosis_percentage for m in all_metadata]
    background_pcts = [m.background_percentage for m in all_metadata]
    
    class_order = AUGMENT_CLASS_ORDER
    class_colors = AUGMENT_CLASS_COLORS
    
    # Create figure
    fig = Bas3GLMakie.GLMakie.Figure(size=(1400, 900))
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[0, :], 
        "Augmentation Summary Dashboard", 
        fontsize=24, 
        font=:bold
    )
    
    # Statistics text panel
    stats_text = """
Dataset Statistics:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Augmented Samples: $(length(all_metadata))
Original Source Images: $(num_sources)
Unique Sources Used: $(length(unique(source_indices)))
Image Size: $(augmented_size[1])×$(augmented_size[2]) pixels

Parameter Ranges:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scale Factor: $(round(minimum(scale_factors), digits=2)) - $(round(maximum(scale_factors), digits=2))
Rotation: $(round(minimum(rotation_angles), digits=1))° - $(round(maximum(rotation_angles), digits=1))°
Shear X: $(round(minimum(shear_x_angles), digits=1))° - $(round(maximum(shear_x_angles), digits=1))°
Shear Y: $(round(minimum(shear_y_angles), digits=1))° - $(round(maximum(shear_y_angles), digits=1))°
Brightness: $(round(minimum(brightness_factors), digits=2)) - $(round(maximum(brightness_factors), digits=2))
Saturation: $(round(minimum(saturation_offsets), digits=2)) - $(round(maximum(saturation_offsets), digits=2))
Blur σ: $(round(minimum(blur_sigmas), digits=2)) - $(round(maximum(blur_sigmas), digits=2))

Class Distribution:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scar: $(count(==(Symbol("scar")), target_classes)) samples ($(round(mean(scar_pcts), digits=2))% mean coverage)
Redness: $(count(==(Symbol("redness")), target_classes)) samples ($(round(mean(redness_pcts), digits=2))% mean coverage)
Hematoma: $(count(==(Symbol("hematoma")), target_classes)) samples ($(round(mean(hematoma_pcts), digits=2))% mean coverage)
Necrosis: $(count(==(Symbol("necrosis")), target_classes)) samples ($(round(mean(necrosis_pcts), digits=2))% mean coverage)
Background: $(count(==(Symbol("background")), target_classes)) samples ($(round(mean(background_pcts), digits=2))% mean coverage)
"""
    
    Bas3GLMakie.GLMakie.Label(
        fig[1, 1], 
        stats_text, 
        fontsize=12, 
        halign=:left, 
        valign=:top, 
        font=:regular,
        tellwidth=false, 
        tellheight=false
    )
    
    # Pie chart for target class distribution
    ax_pie = Bas3GLMakie.GLMakie.Axis(
        fig[1, 2], 
        title="Target Class Distribution", 
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(ax_pie)
    Bas3GLMakie.GLMakie.hidespines!(ax_pie)
    
    pie_values = [count(==(c), target_classes) for c in class_order]
    
    # Draw pie chart using arcs
    let
        total = sum(pie_values)
        start_angle = 0.0
        for (i, (val, col)) in enumerate(zip(pie_values, class_colors))
            angle = 2π * val / total
            end_angle = start_angle + angle
            
            # Draw pie slice as polygon
            n_points = max(10, round(Int, angle * 20))
            angles = range(start_angle, end_angle, length=n_points)
            xs = [0.0; cos.(angles)]
            ys = [0.0; sin.(angles)]
            Bas3GLMakie.GLMakie.poly!(ax_pie, Bas3GLMakie.GLMakie.Point2f.(xs, ys), color=col)
            
            # Add percentage label
            mid_angle = (start_angle + end_angle) / 2
            label_r = 0.7
            Bas3GLMakie.GLMakie.text!(
                ax_pie, 
                label_r * cos(mid_angle), 
                label_r * sin(mid_angle),
                text="$(round(100*val/total, digits=1))%", 
                fontsize=10, 
                align=(:center, :center)
            )
            
            start_angle = end_angle
        end
    end
    
    Bas3GLMakie.GLMakie.limits!(ax_pie, -1.3, 1.3, -1.3, 1.3)
    
    # Add legend below pie chart
    legend_items = ["$(String(c)): $(count(==(c), target_classes))" for c in class_order]
    legend_text = join(legend_items, " | ")
    Bas3GLMakie.GLMakie.Label(fig[2, 2], legend_text, fontsize=10, halign=:center)
    
    return fig
end

"""
    save_augment_summary_dashboard_figure(fig, output_path)

Save the summary dashboard figure to a file.
"""
function save_augment_summary_dashboard_figure(fig, output_path::String)
    Bas3GLMakie.GLMakie.save(output_path, fig)
    println("Saved: $(output_path)")
end

println("  Load_Sets__Augment_SummaryDashboard_UI loaded")
