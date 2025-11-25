# ============================================================================
# Load_Sets__Class_Statistics_UI.jl
# ============================================================================
# Generates Figure 1: Class Area Statistics
#
# Required variables from Load_Sets.jl:
# - sets: dataset of (input, output) pairs
# - class_stats: class area statistics from compute_class_area_statistics()
# - classes, class_totals, class_areas_per_image, normalized_statistics, total_pixels
# - class_names_de: Dict{Symbol, String} mapping class names to German
# ============================================================================

"""
    create_class_statistics_figure(sets, class_stats, class_names_de)

Generate class area statistics figure with 6 axes showing distributions and means.

Returns:
- `fig`: The GLMakie Figure object
"""
function create_class_statistics_figure(sets, class_stats, class_names_de)
    # Extract data from class_stats
    classes = class_stats.classes
    class_totals = class_stats.class_totals
    class_areas_per_image = class_stats.class_areas_per_image
    normalized_statistics = class_stats.normalized_statistics
    total_pixels = class_stats.total_pixels
    
    stats_fig = Bas3GLMakie.GLMakie.Figure(size=(1800, 900))
    
    # Add title for statistics figure
    stats_title = Bas3GLMakie.GLMakie.Label(
        stats_fig[1, 1:3], 
        "Klassenflächenstatistik Gesamtdatensatz ($(length(sets)) Bilder)", 
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    num_classes = length(classes)
    
    # Calculate max and min values for non-background classes (for zoomed plots)
    non_background_classes = filter(c -> c != :background, classes)
    # For axs3: use raw proportions
    max_total_proportion = maximum(class_totals[class] / total_pixels for class in non_background_classes)
    min_total_proportion = minimum(class_totals[class] / total_pixels for class in non_background_classes)
    range_total_proportion = max_total_proportion - min_total_proportion
    padding_total = range_total_proportion * 0.1
    # For axs4: use normalized statistics with std
    max_normalized_with_std = maximum(normalized_statistics[class].mean + normalized_statistics[class].std for class in non_background_classes)
    min_normalized_with_std = minimum(normalized_statistics[class].mean - normalized_statistics[class].std for class in non_background_classes)
    range_normalized = max_normalized_with_std - min_normalized_with_std
    padding_normalized = range_normalized * 0.1
    
    # Axis 1: Total class areas as proportions (bar plot)
    axs1 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 1]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Gesamtklassenflächen (normalisiert)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse"
    )
    
    # Axis 2: Class area distribution (normalized to sum to 1)
    axs2 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 2]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Klassenflächenverteilung (normalisiert)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse"
    )
    
    # Axis 5: Mean+Std error bars (normalized) - linked to axs2
    axs5 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 3]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Klassenfläche Mittelwert ± Std (normalisiert)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse"
    )
    
    # Link axes 2 and 5 (non-zoomed plots)
    Bas3GLMakie.GLMakie.linkyaxes!(axs2, axs5)
    Bas3GLMakie.GLMakie.linkxaxes!(axs2, axs5)
    
    # Axis 3: Total class areas (zoomed to non-background classes, bar plot)
    axs3 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 1]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Gesamtklassenflächen (normalisiert; gezoomt)",
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_total_proportion - padding_total, max_total_proportion + padding_total)
    )
    
    # Axis 4: Class area distribution (zoomed to non-background classes)
    axs4 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 2]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Klassenflächenverteilung (normalisiert; gezoomt)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_normalized_with_std - padding_normalized, max_normalized_with_std + padding_normalized)
    )
    
    # Axis 6: Mean+Std error bars (zoomed to non-background classes) - linked to axs4
    axs6 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 3]; 
        xticks=(1:num_classes, get_german_class_names(classes)), 
        title="Klassenfläche Mittelwert ± Std (normalisiert; gezoomt)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_normalized_with_std - padding_normalized, max_normalized_with_std + padding_normalized)
    )
    
    # Link axes 4 and 6 (zoomed plots)
    Bas3GLMakie.GLMakie.linkyaxes!(axs4, axs6)
    Bas3GLMakie.GLMakie.linkxaxes!(axs4, axs6)
    
    # Define colors for all classes
    stats_class_colors = [Bas3GLMakie.GLMakie.RGBf(0, 1, 0), Bas3GLMakie.GLMakie.RGBf(1, 0, 0), :goldenrod, Bas3GLMakie.GLMakie.RGBf(0, 0, 1), :black]
    
    # Prepare normalized per-image data
    normalized_per_image = Dict{Symbol, Vector{Float64}}()
    for class in classes
        normalized_per_image[class] = Float64[]
    end
    
    num_images = length(class_areas_per_image[classes[1]])
    for img_idx in 1:num_images
        local img_total = sum(class_areas_per_image[class][img_idx] for class in classes)
        for class in classes
            push!(normalized_per_image[class], class_areas_per_image[class][img_idx] / img_total)
        end
    end
    
    # Store per-class outlier percentages
    class_outlier_percentages_normalized = Dict{Symbol, Float64}()
    
    # Plot data
    for (i, class) in enumerate(classes)
        local color = stats_class_colors[i]
        local normalized_data = normalized_per_image[class]
        local total_prop = class_totals[class] / total_pixels
        
        # Find outliers
        local normalized_outlier_mask, normalized_outlier_pct = find_outliers(normalized_data)
        class_outlier_percentages_normalized[class] = normalized_outlier_pct
        
        # Axis 1: Bar plot
        Bas3GLMakie.GLMakie.barplot!(axs1, [i], [total_prop]; color=color, width=0.6, label=class_names_de[class])
        
        # Axis 3: Bar plot (zoomed)
        Bas3GLMakie.GLMakie.barplot!(axs3, [i], [total_prop]; color=color, width=0.6, label=class_names_de[class])
        
        # Axis 2: Boxplot
        Bas3GLMakie.GLMakie.boxplot!(
            axs2, 
            fill(i, length(normalized_data)), 
            normalized_data; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6,
            label=class_names_de[class]
        )
        if sum(normalized_outlier_mask) > 0
            local outlier_normalized = normalized_data[normalized_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                axs2,
                fill(i, length(outlier_normalized)),
                outlier_normalized;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 4: Boxplot (zoomed)
        Bas3GLMakie.GLMakie.boxplot!(
            axs4, 
            fill(i, length(normalized_data)), 
            normalized_data; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6,
            label=class_names_de[class]
        )
        if sum(normalized_outlier_mask) > 0
            local outlier_normalized = normalized_data[normalized_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                axs4,
                fill(i, length(outlier_normalized)),
                outlier_normalized;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 5: Mean+Std error bars
        local mean_val = normalized_statistics[class].mean
        local std_val = normalized_statistics[class].std
        Bas3GLMakie.GLMakie.scatter!(axs5, i, mean_val; markersize=10, color=color, label=class_names_de[class])
        Bas3GLMakie.GLMakie.errorbars!(
            axs5, 
            [i], 
            [mean_val], 
            [std_val]; 
            color=color, 
            linewidth=2,
            whiskerwidth=10
        )
        
        # Axis 6: Mean+Std error bars (zoomed)
        Bas3GLMakie.GLMakie.scatter!(axs6, i, mean_val; markersize=10, color=color, label=class_names_de[class])
        Bas3GLMakie.GLMakie.errorbars!(
            axs6, 
            [i], 
            [mean_val], 
            [std_val]; 
            color=color, 
            linewidth=2,
            whiskerwidth=10
        )
    end
    
    # Add legends with outlier percentages
    y_position = 0.98
    y_spacing = 0.05
    for (i, class) in enumerate(classes)
        local color = stats_class_colors[i]
        local legend_text = "$(class_names_de[class]): $(round(class_outlier_percentages_normalized[class], digits=1))%"
        Bas3GLMakie.GLMakie.text!(
            axs2,
            0.75, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:center, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        Bas3GLMakie.GLMakie.text!(
            axs4,
            0.75, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:center, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    # Add mean ± std legends
    for (i, class) in enumerate(classes)
        local color = stats_class_colors[i]
        local mean_val = normalized_statistics[class].mean
        local std_val = normalized_statistics[class].std
        local legend_text = "$(class_names_de[class]): $(round(mean_val, digits=4)) ± $(round(std_val, digits=4))"
        
        Bas3GLMakie.GLMakie.text!(
            axs5,
            0.02, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        Bas3GLMakie.GLMakie.text!(
            axs6,
            0.02, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    return stats_fig
end
