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

Plot individual patient trajectories as semi-transparent lines.

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
            
            Bas3GLMakie.GLMakie.lines!(
                ax,
                valid_dates,
                valid_values,
                color = (color, alpha),
                linewidth = 1
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
    plot_cohort_lch_timeline!(ax, cohort_stats::CohortClassStats,
                              show_individuals::Bool,
                              show_mean_std::Bool,
                              show_median::Bool,
                              show_quartiles::Bool;
                              base_color=:blue,
                              class_name="Class")

Main plotting function for cohort L*C*h timeline.

Plots three metrics (L*, C*, h°) with different line styles:
- L*: Solid lines
- C*: Dashed lines  
- h°: Dotted lines

# Arguments
- `ax`: GLMakie Axis
- `cohort_stats`: CohortClassStats with aggregated data
- `show_individuals`: Plot individual patient trajectories (overlay)
- `show_mean_std`: Plot mean ± std bands
- `show_median`: Plot median lines
- `show_quartiles`: Plot 25th-75th percentile bands
- `base_color`: Color for plots (default :blue)
- `class_name`: Name for legend (default "Class")

# Returns
- Vector of legend elements

# Example
```julia
legend_elems = plot_cohort_lch_timeline!(ax, redness_stats, true, true, false, false)
```
"""
function plot_cohort_lch_timeline!(ax, cohort_stats::CohortClassStats,
                                   show_individuals::Bool,
                                   show_mean_std::Bool,
                                   show_median::Bool,
                                   show_quartiles::Bool;
                                   base_color=:blue,
                                   class_name="Class")
    local legend_elements = []
    local timepoints = collect(1:cohort_stats.timepoint_count)
    
    # Normalize values (L*: 0-100 → 0-1, C*: 0-150 → 0-1, h°: 0-360 → 0-1)
    local l_means_norm = cohort_stats.l_means ./ 100.0
    local l_stds_norm = cohort_stats.l_stds ./ 100.0
    local l_medians_norm = cohort_stats.l_medians ./ 100.0
    local l_q25_norm = cohort_stats.l_q25 ./ 100.0
    local l_q75_norm = cohort_stats.l_q75 ./ 100.0
    
    local c_means_norm = cohort_stats.c_means ./ 150.0
    local c_stds_norm = cohort_stats.c_stds ./ 150.0
    local c_medians_norm = cohort_stats.c_medians ./ 150.0
    local c_q25_norm = cohort_stats.c_q25 ./ 150.0
    local c_q75_norm = cohort_stats.c_q75 ./ 150.0
    
    local h_means_norm = cohort_stats.h_means ./ 360.0
    local h_stds_norm = cohort_stats.h_stds ./ 360.0
    local h_medians_norm = cohort_stats.h_medians ./ 360.0
    local h_q25_norm = cohort_stats.h_q25 ./ 360.0
    local h_q75_norm = cohort_stats.h_q75 ./ 360.0
    
    # Normalize individual trajectories
    local l_traj_norm = [traj ./ 100.0 for traj in cohort_stats.all_l_trajectories]
    local c_traj_norm = [traj ./ 150.0 for traj in cohort_stats.all_c_trajectories]
    local h_traj_norm = [traj ./ 360.0 for traj in cohort_stats.all_h_trajectories]
    
    # ========================================================================
    # Plot L* (solid lines)
    # ========================================================================
    
    if show_individuals && !isempty(l_traj_norm)
        plot_individual_trajectories!(ax, l_traj_norm, timepoints, base_color, 0.15, 
                                      metric_name="L*")
    end
    
    if show_mean_std
        local l_mean_line, l_std_band = plot_mean_std_band!(
            ax, timepoints, l_means_norm, l_stds_norm, base_color,
            metric_name="L*", line_label="Mittelwert", linestyle=:solid
        )
        if !isnothing(l_mean_line)
            push!(legend_elements, l_mean_line)
        end
    end
    
    if show_median
        local l_median_line, _ = plot_median_quartiles!(
            ax, timepoints, l_medians_norm, l_q25_norm, l_q75_norm, base_color,
            metric_name="L*", linestyle=:solid
        )
        if !isnothing(l_median_line)
            push!(legend_elements, l_median_line)
        end
    end
    
    if show_quartiles
        local dummy_line, l_iqr_band = plot_median_quartiles!(
            ax, timepoints, l_medians_norm, l_q25_norm, l_q75_norm, base_color,
            metric_name="L*", linestyle=:solid
        )
    end
    
    # ========================================================================
    # Plot C* (dashed lines)
    # ========================================================================
    
    local c_color = (base_color, 0.7)  # Slightly transparent for distinction
    
    if show_individuals && !isempty(c_traj_norm)
        plot_individual_trajectories!(ax, c_traj_norm, timepoints, base_color, 0.1,
                                      metric_name="C*")
    end
    
    if show_mean_std
        local c_mean_line, c_std_band = plot_mean_std_band!(
            ax, timepoints, c_means_norm, c_stds_norm, base_color,
            metric_name="C*", line_label="Mittelwert", linestyle=:dash
        )
        if !isnothing(c_mean_line)
            push!(legend_elements, c_mean_line)
        end
    end
    
    if show_median
        local c_median_plot = Bas3GLMakie.GLMakie.lines!(
            ax, timepoints, c_medians_norm,
            color = base_color,
            linewidth = 3,
            linestyle = :dash,
            label = "C* Median"
        )
        push!(legend_elements, c_median_plot)
    end
    
    # ========================================================================
    # Plot h° (dotted lines)
    # ========================================================================
    
    if show_individuals && !isempty(h_traj_norm)
        plot_individual_trajectories!(ax, h_traj_norm, timepoints, base_color, 0.08,
                                      metric_name="h°")
    end
    
    if show_mean_std
        local h_mean_line, h_std_band = plot_mean_std_band!(
            ax, timepoints, h_means_norm, h_stds_norm, base_color,
            metric_name="h°", line_label="Mittelwert", linestyle=:dot
        )
        if !isnothing(h_mean_line)
            push!(legend_elements, h_mean_line)
        end
    end
    
    if show_median
        local h_median_plot = Bas3GLMakie.GLMakie.lines!(
            ax, timepoints, h_medians_norm,
            color = base_color,
            linewidth = 3,
            linestyle = :dot,
            label = "h° Median"
        )
        push!(legend_elements, h_median_plot)
    end
    
    return legend_elements
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
# PATIENT LIST
# ============================================================================

"""
    create_patient_list!(layout, patient_ids::Vector{Int}, max_display::Int=20)

Create a scrollable list of patient IDs included in cohort.

# Arguments
- `layout`: GridLayout to place list in
- `patient_ids`: Vector of patient IDs
- `max_display`: Maximum number of patients to show (default 20)
"""
function create_patient_list!(layout, patient_ids::Vector{Int}, max_display::Int=20)
    # Title
    Bas3GLMakie.GLMakie.Label(
        layout[1, 1],
        "Patienten (n=$(length(patient_ids)))",
        fontsize = 13,
        font = :bold,
        halign = :center,
        padding = (5, 5, 8, 5)
    )
    
    # Show first max_display patients
    local display_count = min(length(patient_ids), max_display)
    local patient_list_str = join(["P$id" for id in patient_ids[1:display_count]], ", ")
    
    if length(patient_ids) > max_display
        patient_list_str *= ", ... (+$(length(patient_ids) - max_display) mehr)"
    end
    
    Bas3GLMakie.GLMakie.Label(
        layout[2, 1],
        patient_list_str,
        fontsize = 10,
        halign = :left,
        valign = :top,
        padding = (10, 10, 5, 5),
        word_wrap = true
    )
end

println("✅ CompareStatisticsUI Visualization module loaded")
