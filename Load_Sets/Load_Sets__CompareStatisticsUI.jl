# ============================================================================
# Load_Sets__CompareStatisticsUI.jl
# ============================================================================
# Multi-patient L*C*h cohort analysis UI
#
# This UI allows statistical analysis of wound healing trajectories by:
# - Filtering patients by exact image count
# - Aggregating L*C*h color data across patient cohorts
# - Visualizing trends with overlays, means, medians, and statistics
#
# Usage:
#   include("Load_Sets__CompareStatisticsUI.jl")
#   fig = create_compare_statistics_figure(sets, db_path)
#   display(fig)
#
# Prerequisites:
# - Load_Sets.jl must be loaded (provides datasets and core functions)
# - Load_Sets__CompareUI.jl must be loaded (provides filtering and extraction)
# - MuHa.xlsx database must exist
# ============================================================================

# Load required modules
include("Load_Sets__CompareStatisticsUI__DataAggregation.jl")
include("Load_Sets__CompareStatisticsUI__Visualization.jl")

# ============================================================================
# MAIN UI CONSTRUCTION
# ============================================================================

"""
    create_compare_statistics_figure(sets, db_path; default_filter=3, default_class=:redness)

Create multi-patient L*C*h cohort analysis UI.

# Arguments
- `sets`: Image dataset from load_original_sets()
- `db_path`: Path to MuHa.xlsx database
- `default_filter`: Initial image count filter (default 3)
- `default_class`: Initial class to analyze (default :redness)

# Returns
- GLMakie Figure object

# Features
- Filter patients by exact image count
- Select which wound class to analyze
- Toggle visualization layers (individuals, mean±std, median, quartiles)
- Statistics table showing metrics per timepoint
- Patient list showing included IDs

# Example
```julia
fig = create_compare_statistics_figure(sets, "MuHa.xlsx", default_filter=3)
display(fig)
```
"""
function create_compare_statistics_figure(sets, db_path; 
                                          default_filter=3, 
                                          default_class=:redness)
    println("[COHORT-UI] Creating Compare Statistics UI...")
    
    # ========================================================================
    # PERFORMANCE OPTIMIZATION: Initialize caches
    # ========================================================================
    
    # Build image index map for O(1) lookups (replaces O(n) linear search)
    if isempty(IMAGE_INDEX_MAP)
        initialize_image_index!(sets)
    end
    
    # Build patient database cache (avoids repeated file reads)
    if isempty(PATIENT_DB_CACHE)
        initialize_patient_db_cache!(db_path)
    end
    
    # ========================================================================
    # INITIALIZE DATA
    # ========================================================================
    
    # Get patient counts
    local patient_counts = get_patient_image_counts(db_path)
    local all_patient_ids = sort(collect(keys(patient_counts)))
    
    # Get available classes from CLASS_NAMES_DE (defined in Load_Sets__Colors.jl)
    # Exclude :background as it's not relevant for wound analysis
    local classes = [:scar, :redness, :hematoma, :necrosis]
    
    # Count patients per image count
    local counts_by_num = Dict{Int, Int}()
    for count in values(patient_counts)
        counts_by_num[count] = get(counts_by_num, count, 0) + 1
    end
    
    # Build filter options
    local filter_options = ["Alle ($(length(all_patient_ids)))"]
    local filter_values = [0]  # 0 = no filter
    
    for num_images in sort(collect(keys(counts_by_num)))
        if num_images >= 2  # Only show 2+ images
            local count = counts_by_num[num_images]
            local label = num_images == 1 ? "1 Bild ($count)" : "$num_images Bilder ($count)"
            push!(filter_options, label)
            push!(filter_values, num_images)
        end
    end
    
    println("[COHORT-UI] Found $(length(all_patient_ids)) total patients")
    println("[COHORT-UI] Filter options: $(length(filter_options))")
    
    # ========================================================================
    # CREATE FIGURE
    # ========================================================================
    
    local fig = Bas3GLMakie.GLMakie.Figure(size=(1920, 1080), backgroundcolor=:white)
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[1, 1:2],
        "L*C*h Kohortenanalyse - Statistischer Vergleich",
        fontsize = 24,
        font = :bold,
        halign = :center,
        padding = (0, 0, 15, 10)
    )
    
    # ========================================================================
    # LEFT PANEL: Controls
    # ========================================================================
    
    local left_panel = Bas3GLMakie.GLMakie.GridLayout(fig[2, 1])
    
    # Filter control
    Bas3GLMakie.GLMakie.Label(
        left_panel[1, 1:2],
        "Bilderanzahl:",
        fontsize = 14,
        font = :bold,
        halign = :left,
        padding = (5, 5, 10, 5)
    )
    
    local filter_menu = Bas3GLMakie.GLMakie.Menu(
        left_panel[2, 1:2],
        options = filter_options,
        default = default_filter > 0 ? "$(default_filter) Bilder ($(get(counts_by_num, default_filter, 0)))" : filter_options[1],
        fontsize = 13
    )
    
    # Class selector
    Bas3GLMakie.GLMakie.Label(
        left_panel[3, 1:2],
        "Klasse:",
        fontsize = 14,
        font = :bold,
        halign = :left,
        padding = (5, 5, 15, 10)
    )
    
    local class_options = [String(c) for c in classes]
    local class_menu = Bas3GLMakie.GLMakie.Menu(
        left_panel[4, 1:2],
        options = class_options,
        default = String(default_class),
        fontsize = 13
    )
    
    # Visualization toggles
    Bas3GLMakie.GLMakie.Label(
        left_panel[5, 1:2],
        "Visualisierung:",
        fontsize = 14,
        font = :bold,
        halign = :left,
        padding = (5, 5, 15, 10)
    )
    
    local toggle_individuals = Bas3GLMakie.GLMakie.Toggle(left_panel[6, 1], active=false)
    Bas3GLMakie.GLMakie.Label(
        left_panel[6, 2],
        "Einzelne Patienten",
        fontsize = 12,
        halign = :left
    )
    
    local toggle_boxplot = Bas3GLMakie.GLMakie.Toggle(left_panel[7, 1], active=true)
    Bas3GLMakie.GLMakie.Label(
        left_panel[7, 2],
        "Boxplot",
        fontsize = 12,
        halign = :left
    )
    
    # Update button
    local update_button = Bas3GLMakie.GLMakie.Button(
        left_panel[8, 1:2],
        label = "Aktualisieren",
        fontsize = 14,
        padding = (5, 5, 15, 5)
    )
    
    # Status label
    local status_label = Bas3GLMakie.GLMakie.Label(
        left_panel[9, 1:2],
        "",
        fontsize = 11,
        halign = :center,
        color = :gray,
        padding = (5, 5, 10, 5)
    )
    
    # Set left panel column sizes
    Bas3GLMakie.GLMakie.colsize!(left_panel, 1, Bas3GLMakie.GLMakie.Fixed(40))
    Bas3GLMakie.GLMakie.colsize!(left_panel, 2, Bas3GLMakie.GLMakie.Auto())
    
    # Add row spacing for better visual separation
    Bas3GLMakie.GLMakie.rowgap!(left_panel, 5)
    
    # ========================================================================
    # RIGHT PANEL: Plots and Statistics
    # ========================================================================
    
    local right_panel = Bas3GLMakie.GLMakie.GridLayout(fig[2, 2])
    
    # Patient list area
    local patient_grid = Bas3GLMakie.GLMakie.GridLayout(right_panel[2, 1:3])
    
    # Set row sizes for right panel (removed stats table)
    Bas3GLMakie.GLMakie.rowsize!(right_panel, 1, Bas3GLMakie.GLMakie.Relative(0.87))  # Plot - much larger
    Bas3GLMakie.GLMakie.rowsize!(right_panel, 2, Bas3GLMakie.GLMakie.Relative(0.13))  # Patient list
    
    # Add row spacing for better visual separation
    Bas3GLMakie.GLMakie.rowgap!(right_panel, 15)
    
    # Set column sizes for main figure
    Bas3GLMakie.GLMakie.colsize!(fig.layout, 1, Bas3GLMakie.GLMakie.Fixed(330))  # Left panel - increased from 300
    Bas3GLMakie.GLMakie.colsize!(fig.layout, 2, Bas3GLMakie.GLMakie.Auto())      # Right panel
    
    # Add column spacing
    Bas3GLMakie.GLMakie.colgap!(fig.layout, 20)
    
    # ========================================================================
    # UPDATE FUNCTION
    # ========================================================================
    
    """
    Update the cohort plot based on current filter and class selection.
    """
    function update_cohort_plot!()
        println("\n[COHORT-UI] Updating cohort plot...")
        local update_start = time()
        
        # Get current selections
        local selected_filter_idx = findfirst(==(filter_menu.selection[]), filter_options)
        local target_count = filter_values[selected_filter_idx]
        
        local selected_class_name = class_menu.selection[]
        local selected_class_symbol = Symbol(selected_class_name)  # Convert string to symbol
        
        println("[COHORT-UI] Filter: $target_count images")
        println("[COHORT-UI] Class: $selected_class_symbol")
        
        # Filter patients
        local filtered_patients = if target_count == 0
            all_patient_ids
        else
            filter_patients_by_exact_count(all_patient_ids, patient_counts, target_count)
        end
        
        println("[COHORT-UI] Filtered to $(length(filtered_patients)) patients")
        
        if isempty(filtered_patients)
            status_label.text[] = "Keine Patienten gefunden"
            status_label.color[] = Bas3GLMakie.GLMakie.RGBf(1.0, 0.0, 0.0)  # Red
            return
        end
        
        # Update status
        status_label.text[] = "Lade Daten für $(length(filtered_patients)) Patienten..."
        status_label.color[] = Bas3GLMakie.GLMakie.RGBf(1.0, 0.6, 0.0)  # Orange
        
        # Collect data
        local patient_data_list = collect_cohort_lch_data(
            sets,
            db_path,
            filtered_patients,
            [selected_class_symbol],
            show_progress = true
        )
        
        if isempty(patient_data_list)
            status_label.text[] = "Keine gültigen Daten gefunden"
            status_label.color[] = Bas3GLMakie.GLMakie.RGBf(1.0, 0.0, 0.0)  # Red
            return
        end
        
        # Aggregate statistics
        local cohort_stats = aggregate_cohort_statistics(patient_data_list, selected_class_symbol)
        
        if isnothing(cohort_stats)
            status_label.text[] = "Fehler bei Aggregation"
            status_label.color[] = Bas3GLMakie.GLMakie.RGBf(1.0, 0.0, 0.0)  # Red
            return
        end
        
        # Clear existing content (using same approach as CompareUI)
        function delete_gridlayout_contents!(gl)
            while !isempty(gl.content)
                local content_item = gl.content[1]
                local obj = content_item.content
                
                # If this is a nested GridLayout, recursively clear it first
                if obj isa Bas3GLMakie.GLMakie.GridLayout
                    delete_gridlayout_contents!(obj)
                end
                
                # Delete the object from the figure
                try
                    Bas3GLMakie.GLMakie.delete!(obj)
                catch e
                    # Fallback: remove from content array
                    try
                        deleteat!(gl.content, 1)
                    catch
                        # Skip if already removed
                    end
                end
            end
        end
        
        # Clear ONLY row 1 of right_panel (axis and legend) - keep patient_grid intact
        # Filter content items that are in row 1
        local row1_items = filter(c -> c.span.rows == 1:1, right_panel.content)
        for content_item in row1_items
            local obj = content_item.content
            try
                Bas3GLMakie.GLMakie.delete!(obj)
            catch e
                # Ignore deletion errors
            end
        end
        
        # Clear patient_grid contents (but keep the GridLayout itself)
        delete_gridlayout_contents!(patient_grid)
        
        # Create three axes side-by-side: L* (left), C* (center), h° (right)
        local ax_l = Bas3GLMakie.GLMakie.Axis(
            right_panel[1, 1],
            title = "L* Zeitverlauf: $(selected_class_symbol) (n=$(cohort_stats.num_patients))",
            xlabel = "Zeitpunkt",
            ylabel = "L* (Lightness, 0-1)",
            xticks = (1:cohort_stats.timepoint_count, ["T$i" for i in 1:cohort_stats.timepoint_count]),
            titlesize = 16,
            xlabelsize = 14,
            ylabelsize = 14,
            xticklabelsize = 12,
            yticklabelsize = 12
        )
        
        local ax_c = Bas3GLMakie.GLMakie.Axis(
            right_panel[1, 2],
            title = "C* Zeitverlauf: $(selected_class_symbol) (n=$(cohort_stats.num_patients))",
            xlabel = "Zeitpunkt",
            ylabel = "C* (Chroma, 0-1)",
            xticks = (1:cohort_stats.timepoint_count, ["T$i" for i in 1:cohort_stats.timepoint_count]),
            titlesize = 16,
            xlabelsize = 14,
            ylabelsize = 14,
            xticklabelsize = 12,
            yticklabelsize = 12
        )
        
        local ax_h = Bas3GLMakie.GLMakie.Axis(
            right_panel[1, 3],
            title = "h° Zeitverlauf: $(selected_class_symbol) (n=$(cohort_stats.num_patients))",
            xlabel = "Zeitpunkt",
            ylabel = "h° (Hue, 0-1)",
            xticks = (1:cohort_stats.timepoint_count, ["T$i" for i in 1:cohort_stats.timepoint_count]),
            titlesize = 16,
            xlabelsize = 14,
            ylabelsize = 14,
            xticklabelsize = 12,
            yticklabelsize = 12
        )
        
        # Calculate dynamic axis limits with 10% padding
        # For L* (0-100 range, normalized to 0-1)
        local l_all_values = Float64[]
        for traj in cohort_stats.all_l_trajectories
            append!(l_all_values, filter(!isnan, traj ./ 100.0))
        end
        local l_min = isempty(l_all_values) ? 0.0 : minimum(l_all_values)
        local l_max = isempty(l_all_values) ? 1.0 : maximum(l_all_values)
        local l_span = l_max - l_min
        local l_padding = l_span * 0.1
        local l_ylim_min = max(0.0, l_min - l_padding)
        local l_ylim_max = min(1.0, l_max + l_padding)
        
        # For C* (0-150 range, normalized to 0-1)
        local c_all_values = Float64[]
        for traj in cohort_stats.all_c_trajectories
            append!(c_all_values, filter(!isnan, traj ./ 150.0))
        end
        local c_min = isempty(c_all_values) ? 0.0 : minimum(c_all_values)
        local c_max = isempty(c_all_values) ? 1.0 : maximum(c_all_values)
        local c_span = c_max - c_min
        local c_padding = c_span * 0.1
        local c_ylim_min = max(0.0, c_min - c_padding)
        local c_ylim_max = min(1.0, c_max + c_padding)
        
        # For h° (0-360 range, normalized to 0-1)
        local h_all_values = Float64[]
        for traj in cohort_stats.all_h_trajectories
            append!(h_all_values, filter(!isnan, traj ./ 360.0))
        end
        local h_min = isempty(h_all_values) ? 0.0 : minimum(h_all_values)
        local h_max = isempty(h_all_values) ? 1.0 : maximum(h_all_values)
        local h_span = h_max - h_min
        local h_padding = h_span * 0.1
        local h_ylim_min = max(0.0, h_min - h_padding)
        local h_ylim_max = min(1.0, h_max + h_padding)
        
        # Apply dynamic limits
        Bas3GLMakie.GLMakie.ylims!(ax_l, l_ylim_min, l_ylim_max)
        Bas3GLMakie.GLMakie.ylims!(ax_c, c_ylim_min, c_ylim_max)
        Bas3GLMakie.GLMakie.ylims!(ax_h, h_ylim_min, h_ylim_max)
        
        println("[COHORT-UI] Dynamic axis limits:")
        println("  L*: [$(round(l_ylim_min, digits=3)), $(round(l_ylim_max, digits=3))] (span: $(round(l_span, digits=3)))")
        println("  C*: [$(round(c_ylim_min, digits=3)), $(round(c_ylim_max, digits=3))] (span: $(round(c_span, digits=3)))")
        println("  h°: [$(round(h_ylim_min, digits=3)), $(round(h_ylim_max, digits=3))] (span: $(round(h_span, digits=3)))")
        
        # Set equal column sizes for all three axes
        Bas3GLMakie.GLMakie.colsize!(right_panel, 1, Bas3GLMakie.GLMakie.Auto())
        Bas3GLMakie.GLMakie.colsize!(right_panel, 2, Bas3GLMakie.GLMakie.Auto())
        Bas3GLMakie.GLMakie.colsize!(right_panel, 3, Bas3GLMakie.GLMakie.Auto())
        
        # Get class color
        local class_color = get(BBOX_COLORS, selected_class_symbol, (:blue, 1.0))[1]
        
        # Plot with current toggle settings
        plot_cohort_lch_timeline!(
            ax_l,
            ax_c,
            ax_h,
            cohort_stats,
            toggle_individuals.active[],
            toggle_boxplot.active[],
            base_color = class_color,
            class_name = String(selected_class_symbol)
        )
        
        # Create time delta histograms
        create_time_delta_histograms!(patient_grid, patient_data_list)
        
        # Update status
        local elapsed = round(time() - update_start, digits=2)
        status_label.text[] = "✓ $(cohort_stats.num_patients) Patienten geladen ($elapsed s)"
        status_label.color[] = Bas3GLMakie.GLMakie.RGBf(0.0, 0.7, 0.0)  # Green
        
        println("[COHORT-UI] Update complete in $elapsed seconds")
    end
    
    # ========================================================================
    # CONNECT CALLBACKS
    # ========================================================================
    
    # Update button click
    Bas3GLMakie.GLMakie.on(update_button.clicks) do _
        update_cohort_plot!()
    end
    
    # Also update on toggle changes
    Bas3GLMakie.GLMakie.on(toggle_individuals.active) do _
        # Check if axis exists in right_panel
        local has_axis = any(c -> c isa Bas3GLMakie.GLMakie.Axis, right_panel.content)
        if has_axis
            update_cohort_plot!()
        end
    end
    
    Bas3GLMakie.GLMakie.on(toggle_boxplot.active) do _
        local has_axis = any(c -> c isa Bas3GLMakie.GLMakie.Axis, right_panel.content)
        if has_axis
            update_cohort_plot!()
        end
    end
    
    # ========================================================================
    # INITIAL LOAD
    # ========================================================================
    
    println("[COHORT-UI] Performing initial load...")
    update_cohort_plot!()
    
    println("[COHORT-UI] Figure created successfully")
    return fig
end

println("✅ CompareStatisticsUI main module loaded")
println("    Usage: fig = create_compare_statistics_figure(sets, db_path)")
