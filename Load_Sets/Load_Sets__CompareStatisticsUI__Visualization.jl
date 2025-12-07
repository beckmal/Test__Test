# ============================================================================
# Load_Sets__CompareStatisticsUI__Visualization.jl
# ============================================================================
# Visualization functions for multi-patient L*C*h cohort analysis
#
# This module provides functions to:
# - Plot individual patient trajectories (overlay/spaghetti plots)
# - Plot mean ± std bands (statistical central tendency)
# - Plot median + quartile bands (robust statistics)
# - Create statistics tables
# - Create patient lists
#
# Requires GLMakie for plotting
# ============================================================================

# ============================================================================
# PLOTTING FUNCTIONS
# ============================================================================

"""
    plot_individual_trajectories!(ax, trajectories, dates, color, alpha;
                                   metric_name="L*")

Plot individual patient trajectories as semi-transparent lines with scatter points.

# Arguments
- `ax`: GLMakie Axis to plot on
- `trajectories`: Vector of Vector{Float64}, each inner vector is one patient's trajectory
- `dates`: Vector of timepoint positions (1, 2, 3, ...) or actual date values
- `color`: Base color for lines
- `alpha`: Transparency (0-1, default 0.2 for overlay effect)
- `metric_name`: Name for legend (default "L*")

# Example
```julia
plot_individual_trajectories!(ax, all_l_trajectories, [1, 2, 3], :red, 0.2)
```
"""
function plot_individual_trajectories!(ax, trajectories, dates, color, alpha=0.2; metric_name="L*")
    for trajectory in trajectories
        # Skip NaN values by filtering
        local valid_indices = findall(!isnan, trajectory)
        if !isempty(valid_indices)
            local valid_dates = dates[valid_indices]
            local valid_values = trajectory[valid_indices]
            
            # Plot lines
            Bas3GLMakie.GLMakie.lines!(
                ax,
                valid_dates,
                valid_values,
                color = (color, alpha),
                linewidth = 1
            )
            
            # Plot scatter points
            Bas3GLMakie.GLMakie.scatter!(
                ax,
                valid_dates,
                valid_values,
                color = (color, alpha * 1.5),  # Slightly more visible than lines
                markersize = 4
            )
        end
    end
end

"""
    plot_mean_std_band!(ax, dates, means, stds, color; 
                        metric_name="L*", line_label="Mean", linestyle=:solid)

Plot mean line with ±std shaded band.

# Arguments
- `ax`: GLMakie Axis
- `dates`: X-axis positions
- `means`: Mean values per timepoint
- `stds`: Standard deviations per timepoint
- `color`: Color for line and band
- `metric_name`: Name for legend entry
- `line_label`: Label for mean line (default "Mean")
- `linestyle`: Line style (:solid, :dash, :dot) (default :solid)

# Returns
- Tuple of (line_element, band_element) for legend

# Example
```julia
mean_line, std_band = plot_mean_std_band!(ax, [1,2,3], means, stds, :blue, linestyle=:dash)
```
"""
function plot_mean_std_band!(ax, dates, means, stds, color; metric_name="L*", line_label="Mean", linestyle=:solid)
    # Filter out NaN values
    local valid_indices = findall(i -> !isnan(means[i]) && !isnan(stds[i]), 1:length(means))
    
    if isempty(valid_indices)
        return (nothing, nothing)
    end
    
    local valid_dates = dates[valid_indices]
    local valid_means = means[valid_indices]
    local valid_stds = stds[valid_indices]
    
    # Plot std band
    local upper = valid_means .+ valid_stds
    local lower = valid_means .- valid_stds
    
    local band_elem = Bas3GLMakie.GLMakie.band!(
        ax,
        valid_dates,
        lower,
        upper,
        color = (color, 0.3)
    )
    
    # Plot mean line
    local line_elem = Bas3GLMakie.GLMakie.lines!(
        ax,
        valid_dates,
        valid_means,
        color = color,
        linewidth = 2,
        linestyle = linestyle,
        label = "$metric_name $line_label"
    )
    
    return (line_elem, band_elem)
end

"""
    plot_median_quartiles!(ax, dates, medians, q25, q75, color;
                           metric_name="L*", linestyle=:solid)

Plot median line with 25th-75th percentile band (IQR).

# Arguments
- `ax`: GLMakie Axis
- `dates`: X-axis positions
- `medians`: Median values per timepoint
- `q25`: 25th percentile values
- `q75`: 75th percentile values
- `color`: Color for line and band
- `metric_name`: Name for legend
- `linestyle`: Line style (:solid, :dash, :dot)

# Returns
- Tuple of (line_element, band_element) for legend

# Example
```julia
median_line, iqr_band = plot_median_quartiles!(ax, [1,2,3], medians, q25, q75, :green)
```
"""
function plot_median_quartiles!(ax, dates, medians, q25, q75, color; 
                                metric_name="L*", linestyle=:solid)
    # Filter out NaN values
    local valid_indices = findall(i -> !isnan(medians[i]) && !isnan(q25[i]) && !isnan(q75[i]), 
                                   1:length(medians))
    
    if isempty(valid_indices)
        return (nothing, nothing)
    end
    
    local valid_dates = dates[valid_indices]
    local valid_medians = medians[valid_indices]
    local valid_q25 = q25[valid_indices]
    local valid_q75 = q75[valid_indices]
    
    # Plot quartile band (IQR)
    local band_elem = Bas3GLMakie.GLMakie.band!(
        ax,
        valid_dates,
        valid_q25,
        valid_q75,
        color = (color, 0.25)
    )
    
    # Plot median line (bold)
    local line_elem = Bas3GLMakie.GLMakie.lines!(
        ax,
        valid_dates,
        valid_medians,
        color = color,
        linewidth = 3,
        linestyle = linestyle,
        label = "$metric_name Median"
    )
    
    return (line_elem, band_elem)
end

"""
    plot_cohort_lch_timeline!(ax_l, ax_c, ax_h, cohort_stats::CohortClassStats,
                              show_individuals::Bool,
                              show_boxplot::Bool;
                              base_color=:blue,
                              class_name="Class")

Main plotting function for cohort L*C*h° timeline (three separate axes).

Plots three metrics on separate axes:
- L* (Lightness): Plotted on ax_l
- C* (Chroma): Plotted on ax_c
- h° (Hue): Plotted on ax_h

# Arguments
- `ax_l`: GLMakie Axis for L* (Lightness)
- `ax_c`: GLMakie Axis for C* (Chroma)
- `ax_h`: GLMakie Axis for h° (Hue)
- `cohort_stats`: CohortClassStats with aggregated data
- `show_individuals`: Plot individual patient trajectories (overlay with scatter)
- `show_boxplot`: Plot boxplots for each metric at each timepoint
- `base_color`: Color for plots (default :blue)
- `class_name`: Name for legend (default "Class")

# Example
```julia
plot_cohort_lch_timeline!(ax_l, ax_c, ax_h, redness_stats, true, true)
```
"""
function plot_cohort_lch_timeline!(ax_l, ax_c, ax_h, cohort_stats::CohortClassStats,
                                   show_individuals::Bool,
                                   show_boxplot::Bool;
                                   base_color=:blue,
                                   class_name="Class")
    local timepoints = collect(1:cohort_stats.timepoint_count)
    
    # Normalize values (L*: 0-100 → 0-1, C*: 0-150 → 0-1, h°: 0-360 → 0-1)
    local l_medians_norm = cohort_stats.l_medians ./ 100.0
    local l_q25_norm = cohort_stats.l_q25 ./ 100.0
    local l_q75_norm = cohort_stats.l_q75 ./ 100.0
    
    local c_medians_norm = cohort_stats.c_medians ./ 150.0
    local c_q25_norm = cohort_stats.c_q25 ./ 150.0
    local c_q75_norm = cohort_stats.c_q75 ./ 150.0
    
    local h_medians_norm = cohort_stats.h_medians ./ 360.0
    local h_q25_norm = cohort_stats.h_q25 ./ 360.0
    local h_q75_norm = cohort_stats.h_q75 ./ 360.0
    
    # Normalize individual trajectories
    local l_traj_norm = [traj ./ 100.0 for traj in cohort_stats.all_l_trajectories]
    local c_traj_norm = [traj ./ 150.0 for traj in cohort_stats.all_c_trajectories]
    local h_traj_norm = [traj ./ 360.0 for traj in cohort_stats.all_h_trajectories]
    
    # ========================================================================
    # Plot L* on ax_l (Lightness axis)
    # ========================================================================
    
    if show_individuals && !isempty(l_traj_norm)
        plot_individual_trajectories!(ax_l, l_traj_norm, timepoints, base_color, 0.15, 
                                      metric_name="L*")
    end
    
    if show_boxplot
        for t in 1:cohort_stats.timepoint_count
            local l_q25 = l_q25_norm[t]
            local l_median = l_medians_norm[t]
            local l_q75 = l_q75_norm[t]
            
            if !isnan(l_median) && !isnan(l_q25) && !isnan(l_q75)
                # Box (IQR: Q1 to Q3)
                Bas3GLMakie.GLMakie.poly!(
                    ax_l,
                    Bas3GLMakie.GLMakie.Rect(t - 0.15, l_q25, 0.3, l_q75 - l_q25),
                    color = (base_color, 0.3),
                    strokecolor = base_color,
                    strokewidth = 2
                )
                
                # Median line
                Bas3GLMakie.GLMakie.linesegments!(
                    ax_l,
                    [Bas3GLMakie.GLMakie.Point2f(t - 0.15, l_median), 
                     Bas3GLMakie.GLMakie.Point2f(t + 0.15, l_median)],
                    color = base_color,
                    linewidth = 3
                )
            end
        end
    end
    
    # ========================================================================
    # Plot C* on ax_c (Chroma axis)
    # ========================================================================
    
    if show_individuals && !isempty(c_traj_norm)
        plot_individual_trajectories!(ax_c, c_traj_norm, timepoints, base_color, 0.15, 
                                      metric_name="C*")
    end
    
    if show_boxplot
        for t in 1:cohort_stats.timepoint_count
            local c_q25 = c_q25_norm[t]
            local c_median = c_medians_norm[t]
            local c_q75 = c_q75_norm[t]
            
            if !isnan(c_median) && !isnan(c_q25) && !isnan(c_q75)
                # Box (IQR: Q1 to Q3)
                Bas3GLMakie.GLMakie.poly!(
                    ax_c,
                    Bas3GLMakie.GLMakie.Rect(t - 0.15, c_q25, 0.3, c_q75 - c_q25),
                    color = (base_color, 0.3),
                    strokecolor = base_color,
                    strokewidth = 2
                )
                
                # Median line
                Bas3GLMakie.GLMakie.linesegments!(
                    ax_c,
                    [Bas3GLMakie.GLMakie.Point2f(t - 0.15, c_median), 
                     Bas3GLMakie.GLMakie.Point2f(t + 0.15, c_median)],
                    color = base_color,
                    linewidth = 3
                )
            end
        end
    end
    
    # ========================================================================
    # Plot h° on ax_h (Hue axis)
    # ========================================================================
    
    if show_individuals && !isempty(h_traj_norm)
        plot_individual_trajectories!(ax_h, h_traj_norm, timepoints, base_color, 0.15, 
                                      metric_name="h°")
    end
    
    if show_boxplot
        for t in 1:cohort_stats.timepoint_count
            local h_q25 = h_q25_norm[t]
            local h_median = h_medians_norm[t]
            local h_q75 = h_q75_norm[t]
            
            if !isnan(h_median) && !isnan(h_q25) && !isnan(h_q75)
                # Box (IQR: Q1 to Q3)
                Bas3GLMakie.GLMakie.poly!(
                    ax_h,
                    Bas3GLMakie.GLMakie.Rect(t - 0.15, h_q25, 0.3, h_q75 - h_q25),
                    color = (base_color, 0.3),
                    strokecolor = base_color,
                    strokewidth = 2
                )
                
                # Median line
                Bas3GLMakie.GLMakie.linesegments!(
                    ax_h,
                    [Bas3GLMakie.GLMakie.Point2f(t - 0.15, h_median), 
                     Bas3GLMakie.GLMakie.Point2f(t + 0.15, h_median)],
                    color = base_color,
                    linewidth = 3
                )
            end
        end
    end
end

# ============================================================================
# STATISTICS TABLE
# ============================================================================

"""
    create_statistics_table!(layout, cohort_stats::CohortClassStats, class_name::String)

Create a table showing statistics for each timepoint.

# Arguments
- `layout`: GridLayout to place table in
- `cohort_stats`: CohortClassStats with aggregated data
- `class_name`: Name of class for table title

# Layout
```
Timepoint │  L* Mean │  L* Std │  C* Mean │  C* Std │  h° Mean │  h° Std
─────────────────────────────────────────────────────────────────────────
T1        │    45.2  │   8.3   │   35.1   │   6.2   │   38.5   │   12.1
T2        │    52.8  │   7.1   │   42.3   │   5.8   │   42.1   │   10.3
T3        │    58.1  │   6.5   │   48.7   │   5.1   │   45.2   │    9.8
```
"""
function create_statistics_table!(layout, cohort_stats::CohortClassStats, class_name::String)
    # Title
    Bas3GLMakie.GLMakie.Label(
        layout[1, 1:7],
        "Statistik: $class_name (n=$(cohort_stats.num_patients))",
        fontsize = 14,
        font = :bold,
        halign = :center,
        padding = (5, 5, 10, 5)
    )
    
    # Headers
    local headers = ["Zeitpunkt", "L* μ", "L* σ", "C* μ", "C* σ", "h° μ", "h° σ"]
    for (col, header) in enumerate(headers)
        Bas3GLMakie.GLMakie.Label(
            layout[2, col],
            header,
            fontsize = 11,
            font = :bold,
            halign = :center,
            padding = (5, 5, 5, 5)
        )
    end
    
    # Data rows
    for t in 1:cohort_stats.timepoint_count
        local row = t + 2
        
        # Timepoint label
        Bas3GLMakie.GLMakie.Label(
            layout[row, 1],
            "T$t",
            fontsize = 10,
            halign = :center,
            padding = (3, 3, 3, 3)
        )
        
        # L* mean and std
        local l_mean_str = isnan(cohort_stats.l_means[t]) ? "---" : 
                          string(round(cohort_stats.l_means[t], digits=1))
        local l_std_str = isnan(cohort_stats.l_stds[t]) ? "---" :
                         string(round(cohort_stats.l_stds[t], digits=1))
        
        Bas3GLMakie.GLMakie.Label(layout[row, 2], l_mean_str, fontsize=10, halign=:center, padding=(3,3,3,3))
        Bas3GLMakie.GLMakie.Label(layout[row, 3], l_std_str, fontsize=10, halign=:center, padding=(3,3,3,3))
        
        # C* mean and std
        local c_mean_str = isnan(cohort_stats.c_means[t]) ? "---" :
                          string(round(cohort_stats.c_means[t], digits=1))
        local c_std_str = isnan(cohort_stats.c_stds[t]) ? "---" :
                         string(round(cohort_stats.c_stds[t], digits=1))
        
        Bas3GLMakie.GLMakie.Label(layout[row, 4], c_mean_str, fontsize=10, halign=:center, padding=(3,3,3,3))
        Bas3GLMakie.GLMakie.Label(layout[row, 5], c_std_str, fontsize=10, halign=:center, padding=(3,3,3,3))
        
        # h° mean and std
        local h_mean_str = isnan(cohort_stats.h_means[t]) ? "---" :
                          string(round(cohort_stats.h_means[t], digits=1))
        local h_std_str = isnan(cohort_stats.h_stds[t]) ? "---" :
                         string(round(cohort_stats.h_stds[t], digits=1))
        
        Bas3GLMakie.GLMakie.Label(layout[row, 6], h_mean_str, fontsize=10, halign=:center, padding=(3,3,3,3))
        Bas3GLMakie.GLMakie.Label(layout[row, 7], h_std_str, fontsize=10, halign=:center, padding=(3,3,3,3))
    end
end

# ============================================================================
# TIME DELTA HISTOGRAMS
# ============================================================================

"""
    create_time_delta_histograms!(layout, patient_data_list::Vector{PatientLChData})

Create side-by-side histograms showing time deltas between timepoints.

# Arguments
- `layout`: GridLayout to place histograms in
- `patient_data_list`: Vector of PatientLChData with date information

# Layout
Creates one histogram per delta:
- Δ(T1→T2), Δ(T2→T3), Δ(T3→T4), etc.
Number of histograms = max(dates per patient) - 1

# Histogram Properties
- Bin width: 1 day (fixed)
- No statistics overlay (clean visualization)
- Horizontal layout (side-by-side)
"""
function create_time_delta_histograms!(layout, patient_data_list)
    # Calculate time deltas for all patients
    local max_deltas = 0
    for patient in patient_data_list
        max_deltas = max(max_deltas, length(patient.dates) - 1)
    end
    
    if max_deltas == 0
        # No deltas to show (patients have only 1 image each)
        Bas3GLMakie.GLMakie.Label(
            layout[1, 1],
            "Keine Zeitintervalle (alle Patienten haben nur 1 Bild)",
            fontsize = 12,
            halign = :center,
            color = :gray
        )
        return
    end
    
    # Collect deltas: deltas[i] = all Δ(Ti→Ti+1) across patients
    local deltas = [Float64[] for _ in 1:max_deltas]
    
    for patient in patient_data_list
        for i in 1:(length(patient.dates) - 1)
            local delta_days = (patient.dates[i+1] - patient.dates[i]).value
            push!(deltas[i], Float64(delta_days))
        end
    end
    
    # Create one histogram per delta (directly in row 1, no separate title row)
    for i in 1:max_deltas
        local delta_values = deltas[i]
        
        if isempty(delta_values)
            continue
        end
        
        # Calculate bin range with 1-day bins
        local min_val = floor(minimum(delta_values))
        local max_val = ceil(maximum(delta_values))
        local bins = range(min_val, max_val + 1, step=1)
        
        # Create axis with title incorporating the delta description
        local ax = Bas3GLMakie.GLMakie.Axis(
            layout[1, i],
            title = "Δ(T$(i)→T$(i+1)) - Zeitintervall",
            xlabel = "Tage",
            ylabel = i == 1 ? "Anzahl Patienten" : "",
            titlesize = 11,
            xlabelsize = 10,
            ylabelsize = 10,
            xticklabelsize = 9,
            yticklabelsize = 9
        )
        
        # Plot histogram with 1-day bins
        Bas3GLMakie.GLMakie.hist!(
            ax,
            delta_values,
            bins = bins,
            color = (:steelblue, 0.7),
            strokewidth = 1,
            strokecolor = :steelblue
        )
        
        # Set x-axis limits to exclude empty bins on left and right
        # Add small padding (0.5 days) to prevent bars from touching edges
        Bas3GLMakie.GLMakie.xlims!(ax, min_val - 0.5, max_val + 0.5)
    end
end

println("✅ CompareStatisticsUI Visualization module loaded")
