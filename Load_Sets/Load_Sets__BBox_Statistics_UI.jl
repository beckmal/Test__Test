# ============================================================================
# Load_Sets__BBox_Statistics_UI.jl
# ============================================================================
# Generates Figure 2: Bounding Box Statistics
#
# Required variables from Load_Sets.jl:
# - sets: dataset of (input, output) pairs
# - bbox_stats: bounding box statistics from compute_bounding_box_statistics()
# - bbox_classes: non-background classes
# - bbox_metrics, bbox_statistics
# - class_names_de: Dict{Symbol, String} mapping class names to German
# ============================================================================

"""
    create_bbox_statistics_figure(sets, bbox_stats, bbox_classes, class_names_de)

Generate bounding box statistics figure with width/height/aspect ratio distributions.

Returns:
- `fig`: The GLMakie Figure object
"""
function create_bbox_statistics_figure(sets, bbox_stats, bbox_classes, class_names_de)
    # Extract data from bbox_stats
    bbox_metrics = bbox_stats.bbox_metrics
    bbox_statistics = bbox_stats.bbox_statistics
    
    bbox_fig = Bas3GLMakie.GLMakie.Figure(size=(1600, 1200))
    
    # Add title
    Bas3GLMakie.GLMakie.Label(
        bbox_fig[1, 1:12],
        "Begrenzungsrahmenstatistik Gesamtdatensatz ($(length(sets)) Bilder)",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    num_bbox_classes = length(bbox_classes)
    
    # Create axes
    bbox_ax1 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 1:4]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Breitenverteilung pro Klasse", 
        ylabel="Breite [px]", 
        xlabel="Klasse"
    )
    
    bbox_ax2 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 5:8]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Höhenverteilung pro Klasse", 
        ylabel="Höhe [px]", 
        xlabel="Klasse"
    )
    
    bbox_ax3 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 9:12]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Seitenverhältnisverteilung pro Klasse", 
        ylabel="Seitenverhältnis", 
        xlabel="Klasse"
    )
    
    bbox_ax6 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 1:4]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Breite Mittelwert ± Std pro Klasse", 
        ylabel="Breite [px]", 
        xlabel="Klasse"
    )
    
    bbox_ax7 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 5:8]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Höhe Mittelwert ± Std pro Klasse", 
        ylabel="Höhe [px]", 
        xlabel="Klasse"
    )
    
    bbox_ax8 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 9:12]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Seitenverhältnis Mittelwert ± Std pro Klasse", 
        ylabel="Seitenverhältnis", 
        xlabel="Klasse"
    )
    
    bbox_ax4_1 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 1:2]; 
        title="Breite vs Höhe (0-300px)", 
        xlabel="Breite [px]", 
        ylabel="Höhe [px]",
        aspect=1,
        limits=(0, 300, 0, 300)
    )
    
    bbox_ax4_2 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 3:4]; 
        title="Breite vs Höhe (0-600px)", 
        xlabel="Breite [px]", 
        ylabel="Höhe [px]",
        aspect=1,
        limits=(0, 600, 0, 600)
    )
    
    bbox_ax4_3 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 5:6]; 
        title="Breite vs Höhe (0-900px)", 
        xlabel="Breite [px]", 
        ylabel="Höhe [px]",
        aspect=1,
        limits=(0, 900, 0, 900)
    )
    
    bbox_ax5 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 7:12]; 
        xticks=(1:num_bbox_classes, get_german_class_names(bbox_classes)), 
        title="Anzahl Begrenzungsrahmen pro Klasse", 
        ylabel="Anzahl", 
        xlabel="Klasse"
    )
    
    # Define colors
    class_colors = [Bas3GLMakie.GLMakie.RGBf(0, 1, 0), Bas3GLMakie.GLMakie.RGBf(1, 0, 0), :goldenrod, Bas3GLMakie.GLMakie.RGBf(0, 0, 1)]
    
    # Store outlier percentages and slopes
    class_outlier_pct_width = Dict{Symbol, Float64}()
    class_outlier_pct_height = Dict{Symbol, Float64}()
    class_outlier_pct_aspect = Dict{Symbol, Float64}()
    class_slopes = Dict{Symbol, Float64}()
    
    # Plot data
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Width boxplot
        local widths = bbox_metrics[class][:widths]
        local width_outlier_mask, width_outlier_pct = find_outliers(widths)
        class_outlier_pct_width[class] = width_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax1, 
            fill(i, length(widths)), 
            widths; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6,
            label=class_names_de[class]
        )
        if sum(width_outlier_mask) > 0
            local outlier_widths = widths[width_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax1,
                fill(i, length(outlier_widths)),
                outlier_widths;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Height boxplot
        local heights = bbox_metrics[class][:heights]
        local height_outlier_mask, height_outlier_pct = find_outliers(heights)
        class_outlier_pct_height[class] = height_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax2, 
            fill(i, length(heights)), 
            heights; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6,
            label=class_names_de[class]
        )
        if sum(height_outlier_mask) > 0
            local outlier_heights = heights[height_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax2,
                fill(i, length(outlier_heights)),
                outlier_heights;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Aspect ratio boxplot
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_outlier_mask, aspect_outlier_pct = find_outliers(aspect_ratios)
        class_outlier_pct_aspect[class] = aspect_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax3, 
            fill(i, length(aspect_ratios)), 
            aspect_ratios; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6,
            label=class_names_de[class]
        )
        if sum(aspect_outlier_mask) > 0
            local outlier_aspects = aspect_ratios[aspect_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax3,
                fill(i, length(outlier_aspects)),
                outlier_aspects;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Compute regression slope
        if length(widths) >= 2
            local mean_w = mean(widths)
            local mean_h = mean(heights)
            local cov_wh = sum((widths .- mean_w) .* (heights .- mean_h)) / length(widths)
            local var_w = sum((widths .- mean_w).^2) / length(widths)
            
            if var_w > 0
                local slope = cov_wh / var_w
                class_slopes[class] = slope
            end
        end
        
        # Number of components
        Bas3GLMakie.GLMakie.barplot!(bbox_ax5, [i], [stats[:num_components]]; color=color, width=0.6, label=class_names_de[class])
    end
    
    # Mean ± Std plots
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Width mean ± std
        local widths = bbox_metrics[class][:widths]
        local width_mean = mean(widths)
        local width_std = std(widths)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax6,
            [i],
            [width_mean];
            markersize=12,
            color=color,
            marker=:circle,
            label=class_names_de[class]
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax6,
            [i],
            [width_mean],
            [width_std],
            [width_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
        
        # Height mean ± std
        local heights = bbox_metrics[class][:heights]
        local height_mean = mean(heights)
        local height_std = std(heights)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax7,
            [i],
            [height_mean];
            markersize=12,
            color=color,
            marker=:circle,
            label=class_names_de[class]
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax7,
            [i],
            [height_mean],
            [height_std],
            [height_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
        
        # Aspect ratio mean ± std
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_mean = mean(aspect_ratios)
        local aspect_std = std(aspect_ratios)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax8,
            [i],
            [aspect_mean];
            markersize=12,
            color=color,
            marker=:circle,
            label=class_names_de[class]
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax8,
            [i],
            [aspect_mean],
            [aspect_std],
            [aspect_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
    end
    
    # Link axes
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax1, bbox_ax6)
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax2, bbox_ax7)
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax3, bbox_ax8)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax1, bbox_ax6)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax2, bbox_ax7)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax3, bbox_ax8)
    
    # Add outlier percentage legends
    y_position = 0.98
    y_spacing = 0.05
    
    for (i, class) in enumerate(bbox_classes)
        local color = class_colors[i]
        
        # Width outliers
        local legend_text = "$(class_names_de[class]): $(round(class_outlier_pct_width[class], digits=1))%"
        Bas3GLMakie.GLMakie.text!(
            bbox_ax1,
            0.75, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:center, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Height outliers
        legend_text = "$(class_names_de[class]): $(round(class_outlier_pct_height[class], digits=1))%"
        Bas3GLMakie.GLMakie.text!(
            bbox_ax2,
            0.75, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:center, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Aspect ratio outliers
        legend_text = "$(class_names_de[class]): $(round(class_outlier_pct_aspect[class], digits=1))%"
        Bas3GLMakie.GLMakie.text!(
            bbox_ax3,
            0.75, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:center, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    # Add slope legends
    for (i, class) in enumerate(bbox_classes)
        if haskey(class_slopes, class)
            local color = class_colors[i]
            local slope_text = "$(class_names_de[class]): $(round(class_slopes[class], digits=2))"
            
            for ax in [bbox_ax4_1, bbox_ax4_2, bbox_ax4_3]
                Bas3GLMakie.GLMakie.text!(
                    ax,
                    0.02, y_position - (i-1) * y_spacing;
                    text=slope_text,
                    align=(:left, :top),
                    fontsize=12,
                    space=:relative,
                    color=color,
                    font=:bold
                )
            end
        end
    end
    
    # Add mean ± std legends
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Width
        local widths = bbox_metrics[class][:widths]
        local width_mean = mean(widths)
        local width_std = std(widths)
        local width_legend_text = "$(class_names_de[class]): $(round(width_mean, digits=1)) ± $(round(width_std, digits=1))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax6,
            0.02, y_position - (i-1) * y_spacing;
            text=width_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Height
        local heights = bbox_metrics[class][:heights]
        local height_mean = mean(heights)
        local height_std = std(heights)
        local height_legend_text = "$(class_names_de[class]): $(round(height_mean, digits=1)) ± $(round(height_std, digits=1))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax7,
            0.02, y_position - (i-1) * y_spacing;
            text=height_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Aspect ratio
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_mean = mean(aspect_ratios)
        local aspect_std = std(aspect_ratios)
        local aspect_legend_text = "$(class_names_de[class]): $(round(aspect_mean, digits=2)) ± $(round(aspect_std, digits=2))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax8,
            0.02, y_position - (i-1) * y_spacing;
            text=aspect_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    # Add reference lines
    Bas3GLMakie.GLMakie.lines!(bbox_ax4_1, [0, 300], [0, 300]; color=:black, linestyle=:dash, linewidth=1, label="y=x")
    Bas3GLMakie.GLMakie.lines!(bbox_ax4_2, [0, 600], [0, 600]; color=:black, linestyle=:dash, linewidth=1, label="y=x")
    Bas3GLMakie.GLMakie.lines!(bbox_ax4_3, [0, 900], [0, 900]; color=:black, linestyle=:dash, linewidth=1, label="y=x")
    
    # Plot scatter points
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        local widths = bbox_metrics[class][:widths]
        local heights = bbox_metrics[class][:heights]
        
        for ax in [bbox_ax4_1, bbox_ax4_2, bbox_ax4_3]
            Bas3GLMakie.GLMakie.scatter!(
                ax, 
                widths, 
                heights; 
                markersize=8, 
                color=(color, 0.6),
                label=class_names_de[class]
            )
        end
    end
    
    # Plot regression lines
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        if haskey(class_slopes, class)
            local widths = bbox_metrics[class][:widths]
            local heights = bbox_metrics[class][:heights]
            local slope = class_slopes[class]
            local mean_w = mean(widths)
            local mean_h = mean(heights)
            local intercept = mean_h - slope * mean_w
            
            local w_min = minimum(widths)
            local w_max = maximum(widths)
            local w_range = range(w_min, w_max, length=100)
            local h_pred = slope .* w_range .+ intercept
            
            for ax in [bbox_ax4_1, bbox_ax4_2, bbox_ax4_3]
                Bas3GLMakie.GLMakie.lines!(
                    ax,
                    w_range,
                    h_pred;
                    color=color,
                    linewidth=2,
                    linestyle=:solid
                )
            end
        end
    end
    
    return bbox_fig
end
