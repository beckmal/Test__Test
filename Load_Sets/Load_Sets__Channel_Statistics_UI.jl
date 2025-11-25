# ============================================================================
# Load_Sets__Channel_Statistics_UI.jl
# ============================================================================
# Generates Figure 3: RGB Channel Statistics
#
# Required variables from Load_Sets.jl:
# - sets: dataset of (input, output) pairs
# - inputs: input images
# - channel_stats: channel statistics from compute_channel_statistics()
# - channel_names, channel_means_per_image, global_channel_stats
# - channel_names_de: Dict{Symbol, String} mapping channel names to German
# ============================================================================

"""
    create_channel_statistics_figure(sets, inputs, channel_stats, channel_names_de)

Generate RGB channel statistics figure with histograms, correlations, and distributions.

Returns:
- `fig`: The GLMakie Figure object
"""
function create_channel_statistics_figure(sets, inputs, channel_stats, channel_names_de)
    # Extract data from channel_stats
    channel_names = channel_stats.channel_names
    channel_means_per_image = channel_stats.channel_means_per_image
    global_channel_stats = channel_stats.global_channel_stats
    
    channel_fig = Bas3GLMakie.GLMakie.Figure(size=(1600, 1200))
    
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
    
    num_channels = length(channel_names)
    
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
    
    channel_outlier_percentages = Dict{Symbol, Float64}()
    
    for (i, channel) in enumerate(channel_names)
        local per_image_means = channel_means_per_image[channel]
        local color = rgb_colors[channel]
        
        local outlier_mask, outlier_pct = find_outliers(per_image_means)
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
    
    return channel_fig
end
