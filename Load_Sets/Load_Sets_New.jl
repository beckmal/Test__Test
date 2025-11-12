# ============================================================================
# Load_Sets_New.jl - Modular version with visualizations
# ============================================================================
# This file uses the refactored modular components from Load_Sets__Core.jl
# and includes the main visualization code (Figures 1-3).
#
# Note: The interactive UI (Figure 4) is not included here. For interactive
# exploration, use the original Load_Sets.jl file.
# ============================================================================

println("=== Loading modular components ===")

# Load all modular components via the core module loader
include("Load_Sets__Core.jl")

# All functions from the modular components are now available in Main namespace:
# - From Config: input_type, raw_output_type, output_type, resolve_path
# - From Colors: class_names_de, channel_names_de, get_german_names, get_german_channel_names
# - From Morphology: morphological_dilate, morphological_erode, morphological_close, morphological_open
# - From Utilities: find_outliers, compute_skewness
# - From Statistics: compute_class_area_statistics, compute_bounding_box_statistics, compute_channel_statistics
# - From ConnectedComponents: find_connected_components, extract_white_mask
# - From DataLoading: load_original_sets
# - From Initialization: reporters (initialized packages)

println("=== Loading dataset ===")

# Load all dataset files (306 images from disk)
const sets = load_original_sets(306, false)
println("Loaded $(length(sets)) image sets")

# Split into inputs and raw outputs
const inputs = [set[1] for set in sets]
const raw_outputs = [set[2] for set in sets]

println("=== Computing statistics ===")

# Compute class area statistics using modular function
println("Computing class area statistics...")
const class_stats = compute_class_area_statistics(sets, raw_output_type)

# Extract data for visualization
const classes = class_stats.classes
const bbox_classes = filter(c -> c != :background, classes)
const class_totals = class_stats.class_totals
const class_areas_per_image = class_stats.class_areas_per_image
const normalized_statistics = class_stats.normalized_statistics
const total_pixels = class_stats.total_pixels

# Compute bounding box statistics using modular function
println("Computing bounding box statistics...")
const bbox_stats = compute_bounding_box_statistics(sets, raw_output_type)

# Extract data for visualization
const bbox_metrics = bbox_stats.bbox_metrics
const bbox_statistics = bbox_stats.bbox_statistics

# Compute channel statistics using modular function
println("Computing channel statistics...")
const channel_stats = compute_channel_statistics(sets, input_type)

# Extract data for visualization
const channel_names = channel_stats.channel_names
const channel_means_per_image = channel_stats.channel_means_per_image
const global_channel_stats = channel_stats.global_channel_stats

println("\n=== Generating visualizations ===")
println("Note: Interactive UI (Figure 4) not included in this version.")
println("For interactive exploration, use Load_Sets.jl\n")

# Create convenience dictionaries for German names and colors
const class_names_de = CLASS_NAMES_DE
const channel_names_de = CHANNEL_NAMES_DE
const class_colors = CLASS_COLORS_RGB
const channel_colors = CHANNEL_COLORS_RGB
const num_channels = length(channel_names)

# ============================================================================
# Figure 1: Class Statistics
# ============================================================================
println("Generating Figure 1: Class Statistics...")

stats_fig = Figure(size=(1800, 900))

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

# Helper function to identify outliers using IQR method
function find_outliers(data)
    if length(data) == 0
        return Bool[], 0.0
    end
    
    q1 = quantile(data, 0.25)
    q3 = quantile(data, 0.75)
    iqr = q3 - q1
    lower_bound = q1 - 1.5 * iqr
    upper_bound = q3 + 1.5 * iqr
    
    outlier_mask = (data .< lower_bound) .| (data .> upper_bound)
    outlier_percentage = 100.0 * sum(outlier_mask) / length(data)
    
    return outlier_mask, outlier_percentage
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

# Display and save
display(Bas3GLMakie.GLMakie.Screen(), stats_fig)
stats_filename = "Full_Dataset_Class_Area_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(stats_filename, stats_fig)
println("Saved class statistics to $(stats_filename)")

# ============================================================================
# Figure 2: Detailed Bounding Box Metrics Visualization
# ============================================================================
println("Generating Figure 2: Bounding Box Statistics...")

bbox_fig = Figure(size=(1600, 1200))

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

# Display and save
display(Bas3GLMakie.GLMakie.Screen(), bbox_fig)
bbox_filename = "Full_Dataset_Bounding_Box_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(bbox_filename, bbox_fig)
println("Saved bounding box metrics to $(bbox_filename)")

# ============================================================================
# Figure 3: Channel Statistics Visualization
# ============================================================================
println("Generating Figure 3: Channel Statistics...")

channel_fig = Figure(size=(1600, 1200))

# Add title
Bas3GLMakie.GLMakie.Label(
    channel_fig[1, 1:2],
    "RGB-Kanalstatistik Gesamtdatensatz ($(length(sets)) Bilder)",
    fontsize=24,
    font=:bold,
    halign=:center
)

# Define RGB colors
rgb_colors = Dict(:red => :red, :green => :green, :blue => :blue)

# Left Column: Channel Correlation Plots
channel_ax6 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[2, 1]; 
    title="Kanalkorrelationen Grün vs Blau",
    xlabel="Grün Mittelwert", 
    ylabel="Blau Mittelwert"
)

channel_ax5 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[3, 1]; 
    title="Kanalkorrelationen Rot vs Blau",
    xlabel="Rot Mittelwert", 
    ylabel="Blau Mittelwert"
)

channel_ax4 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[4, 1]; 
    title="Kanalkorrelationen Rot vs Grün", 
    xlabel="Rot Mittelwert", 
    ylabel="Grün Mittelwert"
)

# Link axes
Bas3GLMakie.GLMakie.linkxaxes!(channel_ax4, channel_ax5)
Bas3GLMakie.GLMakie.linkyaxes!(channel_ax5, channel_ax6)

# Right Column: RGB Statistics
channel_ax2 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[2, 2]; 
    title="RGB-Kanäle Histogramm", 
    ylabel="Dichte", 
    xlabel="Intensität (0.0-1.0)"
)

# Histogram
for (channel_idx, channel) in enumerate(channel_names)
    local all_pixels = Float64[]
    for input_image in inputs
        local input_data = data(input_image)
        append!(all_pixels, vec(input_data[:, :, channel_idx]))
    end
    
    local color = rgb_colors[channel]
    Bas3GLMakie.GLMakie.hist!(
        channel_ax2, 
        all_pixels; 
        bins=50, 
        color=(color, 0.5),
        normalization=:pdf,
        label=channel_names_de[channel]
    )
end

Bas3GLMakie.GLMakie.axislegend(channel_ax2; position=:rt, labelsize=12)

# Mean intensity plot
channel_ax1 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[3, 2]; 
    xticks=(1:num_channels, get_german_channel_names(channel_names)), 
    title="Mittlere Intensität Mittelwert ± Std pro Kanal",
    ylabel="Mittlere Intensität (0.0-1.0)",
    xlabel="Kanal"
)

for (i, channel) in enumerate(channel_names)
    local stats = global_channel_stats[channel]
    local color = rgb_colors[channel]
    
    Bas3GLMakie.GLMakie.scatter!(
        channel_ax1,
        [i],
        [stats.mean];
        markersize=12,
        color=color,
        marker=:circle,
        label=channel_names_de[channel]
    )
    Bas3GLMakie.GLMakie.errorbars!(
        channel_ax1,
        [i],
        [stats.mean],
        [stats.std],
        [stats.std];
        whiskerwidth=10,
        color=color,
        linewidth=2
    )
end

Bas3GLMakie.GLMakie.axislegend(channel_ax1; position=:rt, labelsize=12)

# Boxplot
channel_ax3 = Bas3GLMakie.GLMakie.Axis(
    channel_fig[4, 2]; 
    xticks=(1:num_channels, get_german_channel_names(channel_names)), 
    title="Mittlere Intensitätsverteilung pro Kanal",
    ylabel="Mittlere Intensität (0.0-1.0)", 
    xlabel="Kanal"
)

# Helper function for channel outliers
function find_channel_outliers(data)
    if length(data) == 0
        return Bool[], 0.0
    end
    
    q1 = quantile(data, 0.25)
    q3 = quantile(data, 0.75)
    iqr = q3 - q1
    lower_bound = q1 - 1.5 * iqr
    upper_bound = q3 + 1.5 * iqr
    
    outlier_mask = (data .< lower_bound) .| (data .> upper_bound)
    outlier_percentage = 100.0 * sum(outlier_mask) / length(data)
    
    return outlier_mask, outlier_percentage
end

channel_outlier_percentages = Dict{Symbol, Float64}()

for (i, channel) in enumerate(channel_names)
    local per_image_means = channel_means_per_image[channel]
    local color = rgb_colors[channel]
    
    local outlier_mask, outlier_pct = find_channel_outliers(per_image_means)
    channel_outlier_percentages[channel] = outlier_pct
    
    Bas3GLMakie.GLMakie.boxplot!(
        channel_ax3,
        fill(i, length(per_image_means)),
        per_image_means;
        color=(color, 0.6),
        show_outliers=true,
        width=0.6,
        label=channel_names_de[channel]
    )
end

Bas3GLMakie.GLMakie.axislegend(channel_ax3; position=:rt, labelsize=12)

# Add outlier percentages
legend_lines_channel = String[]
for channel in channel_names
    push!(legend_lines_channel, "$(channel_names_de[channel]): $(round(channel_outlier_percentages[channel], digits=1))%")
end

Bas3GLMakie.GLMakie.text!(
    channel_ax3,
    0.02, 0.98;
    text=join(legend_lines_channel, "\n"),
    align=(:left, :top),
    fontsize=12,
    space=:relative,
    color=:black,
    font=:bold
)

# Channel correlation scatter plots
red_means = channel_means_per_image[:red]
green_means = channel_means_per_image[:green]
blue_means = channel_means_per_image[:blue]

# Calculate ranges for axis limits
red_min = minimum(red_means)
red_max = maximum(red_means)
red_range = red_max - red_min
red_padding = red_range * 0.1

green_min = minimum(green_means)
green_max = maximum(green_means)
green_range = green_max - green_min
green_padding = green_range * 0.1

blue_min = minimum(blue_means)
blue_max = maximum(blue_means)
blue_range = blue_max - blue_min
blue_padding = blue_range * 0.1

# Red vs Green (channel_ax4)
rg_colors = [Bas3GLMakie.GLMakie.RGB(r, g, 0.0) for (r, g) in zip(red_means, green_means)]
Bas3GLMakie.GLMakie.scatter!(channel_ax4, red_means, green_means; markersize=10, color=rg_colors)
rg_min = max(red_min, green_min)
rg_max = min(red_max, green_max)
if rg_min < rg_max
    Bas3GLMakie.GLMakie.lines!(channel_ax4, [rg_min, rg_max], [rg_min, rg_max]; color=:gray, linestyle=:dash, linewidth=1)
end
Bas3GLMakie.GLMakie.xlims!(channel_ax4, red_min - red_padding, red_max + red_padding)
Bas3GLMakie.GLMakie.ylims!(channel_ax4, green_min - green_padding, green_max + green_padding)
corr_rg = cor(red_means, green_means)
Bas3GLMakie.GLMakie.text!(
    channel_ax4,
    red_min + 0.05 * red_range,
    green_max - 0.05 * green_range;
    text="r = $(round(corr_rg, digits=3))",
    fontsize=12,
    align=(:left, :top)
)

# Red vs Blue (channel_ax5)
rb_colors = [Bas3GLMakie.GLMakie.RGB(r, 0.0, b) for (r, b) in zip(red_means, blue_means)]
Bas3GLMakie.GLMakie.scatter!(channel_ax5, red_means, blue_means; markersize=10, color=rb_colors)
rb_min = max(red_min, blue_min)
rb_max = min(red_max, blue_max)
if rb_min < rb_max
    Bas3GLMakie.GLMakie.lines!(channel_ax5, [rb_min, rb_max], [rb_min, rb_max]; color=:gray, linestyle=:dash, linewidth=1)
end
Bas3GLMakie.GLMakie.xlims!(channel_ax5, red_min - red_padding, red_max + red_padding)
Bas3GLMakie.GLMakie.ylims!(channel_ax5, blue_min - blue_padding, blue_max + blue_padding)
corr_rb = cor(red_means, blue_means)
Bas3GLMakie.GLMakie.text!(
    channel_ax5,
    red_min + 0.05 * red_range,
    blue_max - 0.05 * blue_range;
    text="r = $(round(corr_rb, digits=3))",
    fontsize=12,
    align=(:left, :top)
)

# Green vs Blue (channel_ax6)
gb_colors = [Bas3GLMakie.GLMakie.RGB(0.0, g, b) for (g, b) in zip(green_means, blue_means)]
Bas3GLMakie.GLMakie.scatter!(channel_ax6, green_means, blue_means; markersize=10, color=gb_colors)
gb_min = max(green_min, blue_min)
gb_max = min(green_max, blue_max)
if gb_min < gb_max
    Bas3GLMakie.GLMakie.lines!(channel_ax6, [gb_min, gb_max], [gb_min, gb_max]; color=:gray, linestyle=:dash, linewidth=1)
end
Bas3GLMakie.GLMakie.xlims!(channel_ax6, green_min - green_padding, green_max + green_padding)
Bas3GLMakie.GLMakie.ylims!(channel_ax6, blue_min - blue_padding, blue_max + blue_padding)
corr_gb = cor(green_means, blue_means)
Bas3GLMakie.GLMakie.text!(
    channel_ax6,
    green_min + 0.05 * green_range,
    blue_max - 0.05 * blue_range;
    text="r = $(round(corr_gb, digits=3))",
    fontsize=12,
    align=(:left, :top)
)

# Display and save
display(Bas3GLMakie.GLMakie.Screen(), channel_fig)
channel_filename = "Full_Dataset_RGB_Channel_Statistics_$(length(sets))_images.png"
Bas3GLMakie.GLMakie.save(channel_filename, channel_fig)
println("Saved channel statistics to $(channel_filename)")

# ============================================================================
# Summary
# ============================================================================
println("\n=== Visualization Complete ===")
println("Generated 3 figures:")
println("  1. Class Statistics (6 axes)")
println("  2. Bounding Box Metrics (9 axes)")
println("  3. Channel Statistics (6 axes)")
println("\nFor interactive image exploration (Figure 4), use Load_Sets.jl")
println("=== Done ===")
