# Load_Sets__CompareUI.jl
# Patient Image Comparison UI - Shows all images for a selected patient

# Required packages for database functionality
using XLSX
using Dates
using LinearAlgebra: eigen
using Statistics: median

# ============================================================================
# DATABASE FUNCTIONS FOR MUHA.XLSX (Shared with InteractiveUI)
# ============================================================================

"""
    get_database_path() -> String

Returns the path to MuHa.xlsx database.
Automatically constructs platform-appropriate path, with fallback to local directory.
"""
function get_database_path()
    # Construct platform-independent path to the database
    # Base location: Syncthing/MuHa - Bilder/MuHa.xlsx on C: drive
    if Sys.iswindows()
        # On Windows, need C:\\ (with separator) not just C:
        primary_path = joinpath("C:\\", "Syncthing", "MuHa - Bilder", "MuHa.xlsx")
    else
        # WSL/Linux: C: drive mounted at /mnt/c
        primary_path = joinpath("/mnt", "c", "Syncthing", "MuHa - Bilder", "MuHa.xlsx")
    end
    
    if isfile(primary_path)
        return primary_path
    end
    
    # Fallback to local directory (works on all platforms)
    fallback = joinpath(@__DIR__, "MuHa.xlsx")
    if !isfile(fallback)
        @info "Database will be created at: $fallback"
    end
    return fallback
end

"""
    validate_date_compare(date_str::String) -> (Bool, String)

Validates date string in YYYY-MM-DD format.
Returns (success, error_message).
"""
function validate_date_compare(date_str::String)
    if isempty(date_str)
        return (true, "")  # Empty is OK (optional)
    end
    
    if !occursin(r"^\d{4}-\d{2}-\d{2}$", date_str)
        return (false, "Format muss YYYY-MM-DD sein")
    end
    
    try
        parsed = Dates.Date(date_str, "yyyy-mm-dd")
        if parsed > Dates.today()
            return (false, "Datum darf nicht in der Zukunft liegen")
        end
        return (true, "")
    catch
        return (false, "Ungültiges Datum")
    end
end

"""
    validate_info_compare(info_str::String) -> (Bool, String)

Validates info field (max 500 characters).
Returns (success, error_message).
"""
function validate_info_compare(info_str::String)
    if length(info_str) > 500
        return (false, "Info darf maximal 500 Zeichen haben")
    end
    return (true, "")
end

"""
    validate_patient_id_compare(patient_id_str::String) -> (Bool, String)

Validates patient ID string (must be positive integer).
Returns (success, error_message).
"""
function validate_patient_id_compare(patient_id_str::String)
    if isempty(strip(patient_id_str))
        return (false, "Patient-ID darf nicht leer sein")
    end
    
    patient_id = tryparse(Int, strip(patient_id_str))
    if isnothing(patient_id)
        return (false, "Patient-ID muss eine Zahl sein")
    end
    
    if patient_id <= 0
        return (false, "Patient-ID muss größer als 0 sein")
    end
    
    return (true, "")
end

"""
    initialize_database_compare() -> String

Creates MuHa.xlsx if it doesn't exist with proper schema.
Returns path to database file.
"""
function initialize_database_compare()
    db_path = get_database_path()
    db_dir = dirname(db_path)
    
    if !isdir(db_dir)
        @warn "Database directory not found: $db_dir"
        db_path = joinpath(@__DIR__, "MuHa.xlsx")
        println("[COMPARE-DB] Using fallback location: $db_path")
    end
    
    if !isfile(db_path)
        println("[COMPARE-DB] Creating new database: $db_path")
        
        XLSX.openxlsx(db_path, mode="w") do xf
            sheet = xf[1]
            XLSX.rename!(sheet, "Metadata")
            
            # Write headers
            sheet["A1"] = "Image_Index"
            sheet["B1"] = "Filename"
            sheet["C1"] = "Date"
            sheet["D1"] = "Patient_ID"
            sheet["E1"] = "Info"
            sheet["F1"] = "Created_At"
            sheet["G1"] = "Updated_At"
        end
        
        println("[COMPARE-DB] Database created successfully")
    else
        println("[COMPARE-DB] Using existing database: $db_path")
    end
    
    return db_path
end

"""
    get_all_patient_ids(db_path::String) -> Vector{Int}

Returns a sorted list of all unique patient IDs in the database.
"""
function get_all_patient_ids(db_path::String)
    if !isfile(db_path)
        return Int[]
    end
    
    patient_ids = Set{Int}()
    
    try
        xf = XLSX.readxlsx(db_path)
        sheet = xf["Metadata"]
        dims = XLSX.get_dimension(sheet)
        last_row = dims.stop.row_number
        
        for row in 2:last_row
            patient_id = sheet[row, 4]  # Column D = Patient_ID
            if !isnothing(patient_id) && patient_id isa Number
                push!(patient_ids, Int(patient_id))
            end
        end
    catch e
        @warn "Error reading patient IDs: $e"
    end
    
    return sort(collect(patient_ids))
end

"""
    get_images_for_patient(db_path::String, patient_id::Int) -> Vector{NamedTuple}

Returns all image entries for a given patient ID.
Each entry is a NamedTuple with fields: image_index, filename, date, info, row
"""
function get_images_for_patient(db_path::String, patient_id::Int)
    entries = NamedTuple{(:image_index, :filename, :date, :info, :row), Tuple{Int, String, String, String, Int}}[]
    
    if !isfile(db_path)
        return entries
    end
    
    try
        xf = XLSX.readxlsx(db_path)
        sheet = xf["Metadata"]
        dims = XLSX.get_dimension(sheet)
        last_row = dims.stop.row_number
        
        for row in 2:last_row
            pid = sheet[row, 4]  # Column D = Patient_ID
            if !isnothing(pid) && pid isa Number && Int(pid) == patient_id
                entry = (
                    image_index = Int(sheet[row, 1]),
                    filename = string(something(sheet[row, 2], "")),
                    date = string(something(sheet[row, 3], "")),
                    info = string(something(sheet[row, 5], "")),
                    row = row
                )
                push!(entries, entry)
            end
        end
    catch e
        @warn "Error reading entries for patient $patient_id: $e"
    end
    
    # Sort by date (oldest first), then by image_index
    sort!(entries, by = e -> (e.date, e.image_index))
    
    return entries
end

"""
    update_entry_compare(db_path::String, row::Int, date::String, info::String)

Updates date and info fields for an entry at given row.
"""
function update_entry_compare(db_path::String, row::Int, date::String, info::String)
    XLSX.openxlsx(db_path, mode="rw") do xf
        sheet = xf["Metadata"]
        
        timestamp = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
        
        sheet[row, 3] = date   # Column C = Date
        sheet[row, 5] = info   # Column E = Info
        sheet[row, 7] = timestamp  # Column G = Updated_At
    end
    
    println("[COMPARE-DB] Updated entry at row $row")
end

"""
    update_patient_id_compare(db_path::String, row::Int, new_patient_id::Int)

Updates patient ID for an entry at given row.
Used when reassigning an image to a different patient.
"""
function update_patient_id_compare(db_path::String, row::Int, new_patient_id::Int)
    XLSX.openxlsx(db_path, mode="rw") do xf
        sheet = xf["Metadata"]
        
        timestamp = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
        
        sheet[row, 4] = new_patient_id  # Column D = Patient_ID
        sheet[row, 7] = timestamp       # Column G = Updated_At
    end
    
    println("[COMPARE-DB] Updated patient ID to $new_patient_id at row $row")
end

# ============================================================================
# POLYGON GEOMETRY FUNCTIONS (for polygon selection feature)
# ============================================================================

"""
    point_in_polygon(point, vertices)

Test if a point is inside a polygon using ray-casting algorithm.
Point and vertices are in (x, y) = (col, row) format.
Returns true if point is inside polygon, false otherwise.

Algorithm: Cast a ray from the point to the right (increasing x).
Count how many polygon edges the ray crosses.
If odd number of crossings, point is inside; if even, point is outside.
"""
function point_in_polygon(point::Bas3GLMakie.GLMakie.Point2f, vertices::Vector{Bas3GLMakie.GLMakie.Point2f})
    if length(vertices) < 3
        return false
    end
    
    local px, py = point[1], point[2]
    local n = length(vertices)
    local inside = false
    
    # Check each edge of the polygon
    local p1 = vertices[end]
    for i in 1:n
        local p2 = vertices[i]
        local x1, y1 = p1[1], p1[2]
        local x2, y2 = p2[1], p2[2]
        
        # Check if ray crosses this edge
        # Ray is cast horizontally to the right from point
        if ((y1 > py) != (y2 > py)) &&
           (px < (x2 - x1) * (py - y1) / (y2 - y1) + x1)
            inside = !inside
        end
        
        p1 = p2
    end
    
    return inside
end

"""
    polygon_bounds_aabb(vertices)

Calculate axis-aligned bounding box (AABB) for polygon.
Returns (min_x, max_x, min_y, max_y).
"""
function polygon_bounds_aabb(vertices::Vector{Bas3GLMakie.GLMakie.Point2f})
    if isempty(vertices)
        return (0.0, 0.0, 0.0, 0.0)
    end
    
    local x_coords = [v[1] for v in vertices]
    local y_coords = [v[2] for v in vertices]
    
    return (minimum(x_coords), maximum(x_coords), minimum(y_coords), maximum(y_coords))
end

"""
    create_polygon_mask(img, vertices)

Create a binary mask for the polygon region.
Returns a BitMatrix with true for pixels inside the polygon.
Uses AABB optimization to reduce number of point-in-polygon tests.

Vertices are in axis coordinates (x, y) = (col, row).
"""
function create_polygon_mask(img, vertices::Vector{Bas3GLMakie.GLMakie.Point2f})
    if length(vertices) < 3
        # Return empty mask
        local img_data = data(img)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        return falses(h, w)
    end
    
    # Get image dimensions
    local img_data = data(img)
    local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
    
    # Get AABB for optimization
    local min_x, max_x, min_y, max_y = polygon_bounds_aabb(vertices)
    
    # Convert to pixel indices (clamp to image bounds)
    # vertices are in (x, y) = (col, row) format
    local col_start = max(1, floor(Int, min_x))
    local col_end = min(w, ceil(Int, max_x))
    local row_start = max(1, floor(Int, min_y))
    local row_end = min(h, ceil(Int, max_y))
    
    println("[POLYGON-MASK] AABB: rows=$(row_start):$(row_end), cols=$(col_start):$(col_end)")
    println("[POLYGON-MASK] Image size: $(h)x$(w), vertices: $(length(vertices))")
    
    # Create mask
    local mask = falses(h, w)
    
    # Only test pixels within AABB
    local pixels_tested = 0
    local pixels_inside = 0
    
    for row in row_start:row_end
        for col in col_start:col_end
            # Create point in (x, y) = (col, row) format
            local pt = Bas3GLMakie.GLMakie.Point2f(Float32(col), Float32(row))
            pixels_tested += 1
            
            if point_in_polygon(pt, vertices)
                mask[row, col] = true
                pixels_inside += 1
            end
        end
    end
    
    println("[POLYGON-MASK] Tested $(pixels_tested) pixels, $(pixels_inside) inside polygon")
    
    return mask
end

# ============================================================================
# BOUNDING BOX EXTRACTION FOR CLASS VISUALIZATION
# ============================================================================

# Color scheme for bounding boxes (matches InteractiveUI)
const BBOX_COLORS = Dict(
    :scar => (:green, 0.5),
    :redness => (:red, 0.5),
    :hematoma => (:goldenrod, 0.5),
    :necrosis => (:blue, 0.5)
)

"""
    extract_class_bboxes(output_image, classes) -> Dict{Symbol, Vector{Vector{Float64}}}

Extracts rotated bounding boxes for all classes in an output segmentation image.
Uses PCA to compute oriented bounding boxes (minimum area rectangles).

Returns a Dict mapping class symbols to lists of corner coordinates.
Each bbox is [r1, c1, r2, c2, r3, c3, r4, c4] representing 4 corners.
"""
function extract_class_bboxes(output_image, classes)
    local output_data = data(output_image)
    local bboxes_by_class = Dict{Symbol, Vector{Vector{Float64}}}()
    
    # Process each non-background class
    for (class_idx, class) in enumerate(classes)
        if class == :background
            continue
        end
        
        bboxes_by_class[class] = []
        
        # Extract binary mask for this class (threshold at 0.5)
        local class_mask = output_data[:, :, class_idx] .> 0.5
        
        # Skip if no pixels for this class
        if !any(class_mask)
            continue
        end
        
        # Label connected components
        local labeled = Bas3ImageSegmentation.label_components(class_mask)
        local num_components = maximum(labeled)
        
        # Process each connected component
        for component_id in 1:num_components
            # Get mask for this component
            local component_mask = labeled .== component_id
            
            # Find all pixels in this component
            local pixel_coords = findall(component_mask)
            
            if isempty(pixel_coords)
                continue
            end
            
            # Extract row and column indices
            local row_indices = Float64[p[1] for p in pixel_coords]
            local col_indices = Float64[p[2] for p in pixel_coords]
            
            # Compute centroid
            local centroid_row = sum(row_indices) / length(row_indices)
            local centroid_col = sum(col_indices) / length(col_indices)
            
            # Center the coordinates
            local centered_rows = row_indices .- centroid_row
            local centered_cols = col_indices .- centroid_col
            
            # Compute covariance matrix for PCA
            local n = length(centered_rows)
            local cov_matrix = [
                sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
                sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
            ]
            
            # Compute eigenvectors (principal directions)
            local eigen_result = eigen(cov_matrix)
            local principal_axes = eigen_result.vectors
            
            # Project points onto principal axes
            local proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
            local proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
            
            # Find min/max along each principal axis
            local min_proj1, max_proj1 = extrema(proj_axis1)
            local min_proj2, max_proj2 = extrema(proj_axis2)
            
            # Compute corners of rotated rectangle in original coordinates
            local corners_proj = [
                (min_proj1, min_proj2),
                (max_proj1, min_proj2),
                (max_proj1, max_proj2),
                (min_proj1, max_proj2)
            ]
            
            local corners_original = map(corners_proj) do (p1, p2)
                row = centroid_row + p1 * principal_axes[1, 2] + p2 * principal_axes[1, 1]
                col = centroid_col + p1 * principal_axes[2, 2] + p2 * principal_axes[2, 1]
                [row, col]
            end
            
            # Flatten to [r1, c1, r2, c2, r3, c3, r4, c4]
            local rotated_corners = vcat(corners_original...)
            
            push!(bboxes_by_class[class], rotated_corners)
        end
    end
    
    return bboxes_by_class
end

"""
    draw_bboxes_on_axis!(ax, bboxes_dict, img_height)

Draws bounding boxes for all classes on the given axis.
Handles coordinate transformation for rotr90 display.
"""
function draw_bboxes_on_axis!(ax, bboxes_dict, img_height)
    local bbox_plots = []
    
    for (class, bboxes) in bboxes_dict
        local color = get(BBOX_COLORS, class, (:white, 0.5))
        
        for rotated_corners in bboxes
            # rotated_corners is [r1, c1, r2, c2, r3, c3, r4, c4]
            if length(rotated_corners) < 8
                continue
            end
            
            # Extract 4 corners
            local corners = [
                (rotated_corners[1], rotated_corners[2]),
                (rotated_corners[3], rotated_corners[4]),
                (rotated_corners[5], rotated_corners[6]),
                (rotated_corners[7], rotated_corners[8])
            ]
            
            # Transform coordinates for rotr90 display
            # rotr90 transforms: (row, col) -> (col, height - row + 1)
            local x_coords = Float64[]
            local y_coords = Float64[]
            
            for (row, col) in corners
                push!(x_coords, col)
                push!(y_coords, img_height - row + 1)
            end
            
            # Close the rectangle
            push!(x_coords, corners[1][2])
            push!(y_coords, img_height - corners[1][1] + 1)
            
            local line_plot = Bas3GLMakie.GLMakie.lines!(ax, x_coords, y_coords; color=color, linewidth=2)
            push!(bbox_plots, line_plot)
        end
    end
    
    return bbox_plots
end

# ============================================================================
# HSV HISTOGRAM EXTRACTION FOR CLASS REGIONS
# ============================================================================

# Import Colors for HSV conversion (available via Bas3ImageSegmentation)
using Colors: HSV, RGB

# German class names for display
const CLASS_NAMES_DE_HSV = Dict(
    :scar => "Narbe",
    :redness => "Rötung", 
    :hematoma => "Hämatom",
    :necrosis => "Nekrose"
)

"""
    extract_class_hsv_values(input_img, output_img, classes)

Extract HSV values for each class based on segmentation mask.
Returns Dict mapping class symbol to NamedTuple with:
- h_values, s_values, v_values: Arrays for histogram
- median_h, median_s, median_v: Median values
- count: Number of pixels
"""
function extract_class_hsv_values(input_img, output_img, classes)
    local input_data = data(input_img)
    local output_data = data(output_img)
    local results = Dict{Symbol, NamedTuple}()
    
    for (class_idx, class) in enumerate(classes)
        if class == :background
            continue
        end
        
        # Get class mask (pixels belonging to this class)
        local class_mask = output_data[:, :, class_idx] .> 0.5
        
        if !any(class_mask)
            results[class] = (
                h_values = Float64[],
                s_values = Float64[],
                v_values = Float64[],
                median_h = NaN,
                median_s = NaN,
                median_v = NaN,
                count = 0
            )
            continue
        end
        
        # Count pixels for pre-allocation
        local pixel_indices = findall(class_mask)
        local n_pixels = length(pixel_indices)
        
        # Pre-allocate arrays
        local h_values = Vector{Float64}(undef, n_pixels)
        local s_values = Vector{Float64}(undef, n_pixels)
        local v_values = Vector{Float64}(undef, n_pixels)
        
        # Extract HSV values from input image at masked locations
        @inbounds for (i, idx) in enumerate(pixel_indices)
            local r, c = idx[1], idx[2]
            # Get RGB values from input data array (row, col, channel)
            local red = input_data[r, c, 1]
            local green = input_data[r, c, 2]
            local blue = input_data[r, c, 3]
            local rgb_pixel = RGB(red, green, blue)
            local hsv_pixel = HSV(rgb_pixel)
            
            h_values[i] = hsv_pixel.h           # 0-360°
            s_values[i] = hsv_pixel.s * 100.0   # 0-100%
            v_values[i] = hsv_pixel.v * 100.0   # 0-100%
        end
        
        # Compute medians
        local median_h = n_pixels > 0 ? median(h_values) : NaN
        local median_s = n_pixels > 0 ? median(s_values) : NaN
        local median_v = n_pixels > 0 ? median(v_values) : NaN
        
        results[class] = (
            h_values = h_values,
            s_values = s_values,
            v_values = v_values,
            median_h = median_h,
            median_s = median_s,
            median_v = median_v,
            count = n_pixels
        )
    end
    
    return results
end

"""
    create_hsv_mini_histograms!(parent_layout, hsv_class_data, classes)

Create vertically stacked mini HSV histograms for each class (4 rows x 1 column).
Returns the created GridLayout.
"""
function create_hsv_mini_histograms!(parent_layout, hsv_class_data, classes)
    # Define class order for vertical stack: scar, redness, hematoma, necrosis
    local class_order = [:scar, :redness, :hematoma, :necrosis]
    
    # Create vertical nested grid (4 rows, 1 column)
    local hsv_grid = Bas3GLMakie.GLMakie.GridLayout(parent_layout)
    
    for (row_idx, class) in enumerate(class_order)
        local class_data = get(hsv_class_data, class, nothing)
        local color = BBOX_COLORS[class][1]
        local class_name = get(CLASS_NAMES_DE_HSV, class, string(class))
        
        if isnothing(class_data) || class_data.count == 0
            # No data - show placeholder
            Bas3GLMakie.GLMakie.Label(
                hsv_grid[row_idx, 1],
                "$class_name (keine Pixel)",
                fontsize=8,
                color=:gray,
                halign=:center
            )
            continue
        end
        
        # Create compact title with class name and stats on one line (normalized 0-1)
        local h_norm = round(class_data.median_h / 360.0, digits=2)
        local s_norm = round(class_data.median_s / 100.0, digits=2)
        local v_norm = round(class_data.median_v / 100.0, digits=2)
        local title_text = "$class_name n=$(class_data.count) H=$(h_norm) S=$(s_norm) V=$(v_norm)"
        
        local ax = Bas3GLMakie.GLMakie.Axis(
            hsv_grid[row_idx, 1],
            title=title_text,
            titlesize=7,
            titlecolor=color,
            xlabelsize=6,
            ylabelsize=6,
            xticklabelsize=5,
            yticklabelsize=5
        )
        
        # Hide decorations for compact display
        Bas3GLMakie.GLMakie.hideydecorations!(ax)
        Bas3GLMakie.GLMakie.hidexdecorations!(ax)
        
        # Plot H, S, V histograms with transparency (all normalized to 0-1)
        if length(class_data.h_values) > 0
            # Hue (0-360) - normalize to 0-1
            local h_normalized = class_data.h_values ./ 360.0
            Bas3GLMakie.GLMakie.hist!(ax, h_normalized, bins=12, color=(:orange, 0.5), normalization=:pdf, direction=:x)
            
            # Saturation (0-100) - normalize to 0-1
            local s_normalized = class_data.s_values ./ 100.0
            Bas3GLMakie.GLMakie.hist!(ax, s_normalized, bins=12, color=(:magenta, 0.4), normalization=:pdf, direction=:x)
            
            # Value (0-100) - normalize to 0-1
            local v_normalized = class_data.v_values ./ 100.0
            Bas3GLMakie.GLMakie.hist!(ax, v_normalized, bins=12, color=(:gray, 0.4), normalization=:pdf, direction=:x)
        end
        
        # Set axis limits (y-axis for values since rotated 90°, normalized 0-1)
        Bas3GLMakie.GLMakie.ylims!(ax, 0, 1)
    end
    
    # Set tight row spacing for vertical stack
    Bas3GLMakie.GLMakie.rowgap!(hsv_grid, 2)
    
    return hsv_grid
end

# ============================================================================
# H/S TIMELINE PLOT (Narrow left-column axis showing H/S medians over time)
# ============================================================================

"""
    create_hs_timeline!(timeline_grid, entries, hsv_data_list, classes)

Create a timeline plot showing H and S median values over time for each class.
Optimized for narrow left-column layout (280px width) with legend below axis.

# Arguments
- `timeline_grid`: Parent GridLayout for the timeline
- `entries`: Vector of NamedTuples with :date field (YYYY-MM-DD format)
- `hsv_data_list`: Vector of Dict{Symbol, NamedTuple} with HSV data per image
- `classes`: Tuple of class symbols (e.g., (:scar, :redness, :hematoma, :necrosis, :background))

# Plot Design
- X-axis: Date (parsed from entries) - abbreviated format "dd.mm"
- Y-axis: Normalized value (0-1)
  - H (Hue): normalized from 0-360° to 0-1
  - S (Saturation): normalized from 0-100% to 0-1
- Lines: Solid + markers for H, dashed + markers for S
- Colors: Match BBOX_COLORS per class
- Legend: Below axis in 2-column layout

# Returns
- The created Axis object
"""
function create_hs_timeline!(timeline_grid, entries, hsv_data_list, classes)
    # Skip if no data
    if isempty(entries) || isempty(hsv_data_list)
        Bas3GLMakie.GLMakie.Label(
            timeline_grid[1, 1],
            "Keine Zeitdaten",
            fontsize=10,
            color=:gray,
            halign=:center
        )
        return nothing
    end
    
    # Parse dates and convert to numeric values for plotting
    local dates = Dates.Date[]
    local date_values = Float64[]
    
    for entry in entries
        try
            local parsed_date = Dates.Date(entry.date, "yyyy-mm-dd")
            push!(dates, parsed_date)
            push!(date_values, Float64(Dates.value(parsed_date)))
        catch e
            @warn "[TIMELINE] Failed to parse date: $(entry.date)"
            # Use index-based fallback (should not happen per requirements)
            push!(dates, Dates.Date(2000, 1, 1))
            push!(date_values, Float64(length(dates)))
        end
    end
    
    # Create axis (optimized for narrow width)
    local ax = Bas3GLMakie.GLMakie.Axis(
        timeline_grid[1, 1],
        title = "H/S Verlauf",
        titlesize = 10,
        xlabel = "",  # Remove xlabel to save space
        ylabel = "Wert (0-1)",
        xlabelsize = 8,
        ylabelsize = 8,
        xticklabelsize = 6,
        yticklabelsize = 6,
        xticklabelrotation = π/4  # Rotate labels 45° to fit
    )
    
    # Set Y limits (normalized 0-1)
    Bas3GLMakie.GLMakie.ylims!(ax, 0, 1)
    
    # Custom X-axis tick formatting (abbreviated dates for narrow width)
    local unique_dates = unique(dates)
    local tick_positions = [Float64(Dates.value(d)) for d in unique_dates]
    local tick_labels = [Dates.format(d, "dd.mm") for d in unique_dates]  # Abbreviated
    ax.xticks = (tick_positions, tick_labels)
    
    # Class order for plotting
    local class_order = [:scar, :redness, :hematoma, :necrosis]
    
    # Collect plot elements for legend
    local legend_elements = []
    local legend_labels = String[]
    
    for class in class_order
        local base_color = BBOX_COLORS[class][1]
        local class_name = get(CLASS_NAMES_DE_HSV, class, string(class))
        
        # Extract H and S values for this class across all images
        local h_values = Float64[]
        local s_values = Float64[]
        local valid_date_values = Float64[]
        
        for (i, hsv_data) in enumerate(hsv_data_list)
            local class_data = get(hsv_data, class, nothing)
            if !isnothing(class_data) && class_data.count > 0 && !isnan(class_data.median_h)
                # Normalize H from 0-360 to 0-1
                push!(h_values, class_data.median_h / 360.0)
                # Normalize S from 0-100 to 0-1
                push!(s_values, class_data.median_s / 100.0)
                push!(valid_date_values, date_values[i])
            end
        end
        
        # Skip if no valid data for this class
        if isempty(h_values)
            continue
        end
        
        # Sort by date for proper line connection
        local sort_idx = sortperm(valid_date_values)
        local sorted_dates = valid_date_values[sort_idx]
        local sorted_h = h_values[sort_idx]
        local sorted_s = s_values[sort_idx]
        
        # Plot H line (solid + circle markers, smaller for narrow width)
        local h_line = Bas3GLMakie.GLMakie.scatterlines!(
            ax, 
            sorted_dates, 
            sorted_h;
            color = base_color,
            linewidth = 1.5,
            linestyle = :solid,
            marker = :circle,
            markersize = 6
        )
        push!(legend_elements, h_line)
        push!(legend_labels, "$class_name H")
        
        # Plot S line (dashed + diamond markers, slightly transparent)
        local s_line = Bas3GLMakie.GLMakie.scatterlines!(
            ax,
            sorted_dates,
            sorted_s;
            color = (base_color, 0.7),
            linewidth = 1.5,
            linestyle = :dash,
            marker = :diamond,
            markersize = 6
        )
        push!(legend_elements, s_line)
        push!(legend_labels, "$class_name S")
    end
    
    # Add legend BELOW axis (2-column layout for compact display)
    if !isempty(legend_elements)
        Bas3GLMakie.GLMakie.Legend(
            timeline_grid[2, 1],  # Below axis
            legend_elements,
            legend_labels,
            labelsize = 6,
            framevisible = false,
            padding = (2, 2, 2, 2),
            rowgap = 1,
            colgap = 5,
            nbanks = 2,  # 2-column layout
            orientation = :horizontal
        )
        
        # Set row sizes: axis takes most space, legend is compact below
        Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 1, Bas3GLMakie.GLMakie.Relative(0.75))
        Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 2, Bas3GLMakie.GLMakie.Relative(0.25))
    end
    
    return ax
end

# ============================================================================
# COMPARE UI FIGURE CREATION
# ============================================================================

"""
    create_compare_figure(sets, input_type; max_images_per_row=6, test_mode=false)

Creates a patient comparison UI figure with:
- Patient ID selector (dropdown/menu)
- Horizontal row of all images for selected patient
- Editable date and info fields below each image
- Save button for each image

# Arguments
- `sets`: Vector of (input_image, output_image, index) tuples from load_original_sets()
- `input_type`: Input image type for display
- `max_images_per_row::Int=6`: Maximum images to show (scrollable if more)
- `test_mode::Bool=false`: If true, returns NamedTuple with internals for testing

# Returns
- If test_mode=false: GLMakie Figure object
- If test_mode=true: NamedTuple with (figure, observables, widgets, functions)
"""
function create_compare_figure(sets, input_type; max_images_per_row::Int=6, test_mode::Bool=false)
    println("[COMPARE-UI] Creating patient comparison figure...")
    
    # Initialize database
    db_path = initialize_database_compare()
    
    # Get all patient IDs
    all_patient_ids = get_all_patient_ids(db_path)
    println("[COMPARE-UI] Found $(length(all_patient_ids)) patients in database")
    
    if isempty(all_patient_ids)
        @warn "No patients found in database. Add entries via InteractiveUI first."
        all_patient_ids = [0]  # Placeholder
    end
    
    # Create figure with dynamic width based on max images
    # Add 300px for left control column
    fig_width = min(350 * max_images_per_row + 300, 2400)
    local fgr = Bas3GLMakie.GLMakie.Figure(size=(fig_width, 800))
    
    # ========================================================================
    # TWO-COLUMN MAIN LAYOUT
    # ========================================================================
    # Column 1: Controls + H/S Timeline (fixed 280px)
    # Column 2: Images Grid (expandable)
    
    local left_column = Bas3GLMakie.GLMakie.GridLayout(fgr[1, 1])
    local right_column = Bas3GLMakie.GLMakie.GridLayout(fgr[1, 2])
    
    # Set column widths
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(280))
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Auto())
    
    # ========================================================================
    # LEFT COLUMN: Controls (rows 1-5) + Spacer (row 6) + Timeline (row 7)
    # ========================================================================
    
    # Row 1: Title
    Bas3GLMakie.GLMakie.Label(
        left_column[1, 1],
        "Patientenbilder\nVergleich",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    # Row 2: Patient ID selector (label + menu)
    local patient_selector_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[2, 1])
    Bas3GLMakie.GLMakie.Label(
        patient_selector_grid[1, 1],
        "Patient-ID:",
        fontsize=12,
        halign=:right
    )
    local patient_menu = Bas3GLMakie.GLMakie.Menu(
        patient_selector_grid[1, 2],
        options = [string(pid) for pid in all_patient_ids],
        default = isempty(all_patient_ids) ? nothing : string(all_patient_ids[1]),
        width = 100
    )
    
    # Row 3: Navigation buttons
    local nav_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[3, 1])
    local prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 1],
        label = "← Zurück",
        fontsize = 11
    )
    local next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 2],
        label = "Weiter →",
        fontsize = 11
    )
    
    # Row 4: Refresh button
    local refresh_button = Bas3GLMakie.GLMakie.Button(
        left_column[4, 1],
        label = "Aktualisieren",
        fontsize = 11
    )
    
    # Row 5: Clear all polygons button
    local clear_polygons_button = Bas3GLMakie.GLMakie.Button(
        left_column[5, 1],
        label = "Polygone löschen",
        fontsize = 11
    )
    
    # Row 6: Status label
    local status_label = Bas3GLMakie.GLMakie.Label(
        left_column[6, 1],
        "",
        fontsize=10,
        halign=:center,
        color=:gray
    )
    
    # Row 7: Spacer (expands to fill space)
    Bas3GLMakie.GLMakie.Box(left_column[7, 1], color=:transparent)
    
    # Row 8: H/S Timeline Plot
    local timeline_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[8, 1])
    local timeline_axis = Ref{Any}(nothing)  # Will hold axis reference for clearing
    
    # Set left column row sizes
    Bas3GLMakie.GLMakie.rowsize!(left_column, 1, Bas3GLMakie.GLMakie.Fixed(50))   # Title
    Bas3GLMakie.GLMakie.rowsize!(left_column, 2, Bas3GLMakie.GLMakie.Fixed(35))   # Patient selector
    Bas3GLMakie.GLMakie.rowsize!(left_column, 3, Bas3GLMakie.GLMakie.Fixed(35))   # Nav buttons
    Bas3GLMakie.GLMakie.rowsize!(left_column, 4, Bas3GLMakie.GLMakie.Fixed(35))   # Refresh
    Bas3GLMakie.GLMakie.rowsize!(left_column, 5, Bas3GLMakie.GLMakie.Fixed(35))   # Clear polygons
    Bas3GLMakie.GLMakie.rowsize!(left_column, 6, Bas3GLMakie.GLMakie.Fixed(40))   # Status
    Bas3GLMakie.GLMakie.rowsize!(left_column, 7, Bas3GLMakie.GLMakie.Auto())      # Spacer (flexible)
    Bas3GLMakie.GLMakie.rowsize!(left_column, 8, Bas3GLMakie.GLMakie.Fixed(300))  # Timeline
    
    # ========================================================================
    # RIGHT COLUMN: Images Container (scrollable grid)
    # ========================================================================
    local images_grid = Bas3GLMakie.GLMakie.GridLayout(right_column[1, 1])
    
    # Store references to dynamically created widgets
    local image_axes = Bas3GLMakie.GLMakie.Axis[]
    local date_textboxes = []
    local info_textboxes = []
    local patient_id_textboxes = []  # NEW: for patient ID reassignment
    local save_buttons = []
    local image_labels = []
    local image_observables = []
    local hsv_grids = []        # NEW: HSV histogram 2x2 grids
    local hsv_class_data = []   # NEW: HSV data per image
    
    # POLYGON SELECTION: Per-image polygon state arrays
    local polygon_vertices_per_image = []     # Vector of Observable{Vector{Point2f}}
    local polygon_active_per_image = []       # Vector of Observable{Bool}
    local polygon_complete_per_image = []     # Vector of Observable{Bool}
    local polygon_buttons_per_image = []      # Vector of (close_btn, clear_btn) tuples
    
    local current_entries = Bas3GLMakie.GLMakie.Observable(NamedTuple[])
    local current_patient_id = Bas3GLMakie.GLMakie.Observable(isempty(all_patient_ids) ? 0 : all_patient_ids[1])
    
    # ========================================================================
    # PRELOAD CACHE INFRASTRUCTURE
    # ========================================================================
    
    # Cache: patient_id => Vector{NamedTuple} with precomputed image data
    # Each entry: (image_index, input_rotated, output_rotated, input_raw, output_raw, height, bboxes, hsv_data)
    local patient_image_cache = Dict{Int, Vector{NamedTuple}}()
    local cache_lock = ReentrantLock()
    local preload_tasks = Dict{Int, Task}()  # patient_id => Task (for in-progress preloads)
    
    # Cache statistics for debugging
    local cache_hits = Ref(0)
    local cache_misses = Ref(0)
    
    # ========================================================================
    # HELPER FUNCTIONS
    # ========================================================================
    
    # Get classes from the first output image (needed for bounding boxes)
    local classes = shape(sets[1][2])
    println("[COMPARE-UI] Classes detected: $classes")
    
    # Get both input and output images from sets by image_index
    function get_images_by_index(image_index::Int)
        for (input_img, output_img, idx) in sets
            if idx == image_index
                return (
                    input = rotr90(image(input_img)),
                    output = rotr90(image(output_img)),
                    input_raw = input_img,    # Keep raw for HSV extraction
                    output_raw = output_img,  # Keep raw for bbox extraction
                    height = Base.size(data(input_img), 1)  # Original height before rotr90
                )
            end
        end
        # Return placeholder if not found
        local placeholder = fill(Bas3ImageSegmentation.RGB{Float32}(0.5f0, 0.5f0, 0.5f0), 100, 100)
        return (input = placeholder, output = placeholder, input_raw = nothing, output_raw = nothing, height = 100)
    end
    
    # Legacy function for compatibility
    function get_image_by_index(image_index::Int)
        return get_images_by_index(image_index).input
    end
    
    # ========================================================================
    # PRELOAD FUNCTIONS
    # ========================================================================
    
    """
    Preload all image data for a patient (runs asynchronously).
    Stores precomputed rotated images, bboxes, and HSV data in cache.
    """
    function preload_patient_images(patient_id::Int)
        try
            println("[PRELOAD] Starting preload for patient $patient_id")
            
            # Check if already cached or in progress
            local should_skip = false
            lock(cache_lock) do
                if haskey(patient_image_cache, patient_id)
                    println("[PRELOAD] Patient $patient_id already cached, skipping")
                    should_skip = true
                end
            end
            
            if should_skip
                return (success = true, error = nothing)
            end
            
            # Get entries for this patient
            local entries = nothing
            try
                entries = get_images_for_patient(db_path, patient_id)
            catch e
                @warn "[PRELOAD] Error reading entries for patient $patient_id: $e"
                return (success = false, error = "Database read error: $(typeof(e))")
            end
            
            if isempty(entries)
                println("[PRELOAD] No entries for patient $patient_id")
                return (success = true, error = nothing)
            end
            
            # Load .bin files in parallel using multi-threading
            # Spawn one task per image to load in parallel across CPU cores
            println("[PRELOAD] Loading $(length(entries)) images using $(Threads.nthreads()) threads")
            
            # Spawn parallel tasks to load each image
            load_tasks = map(entries) do entry
                Threads.@spawn begin
                    try
                        # Get raw images (loads .bin files into RAM)
                        images = get_images_by_index(entry.image_index)
                        
                        # Return ONLY the raw data - no bbox/HSV computation
                        # (bbox/HSV will be computed on-demand when UI displays them)
                        (
                            success = true,
                            data = (
                                image_index = entry.image_index,
                                input_rotated = images.input,
                                output_rotated = images.output,
                                input_raw = images.input_raw,
                                output_raw = images.output_raw,
                                height = images.height,
                            ),
                            error = nothing
                        )
                    catch e
                        @warn "[PRELOAD] Error loading image $(entry.image_index): $e"
                        (success = false, data = nothing, error = e)
                    end
                end
            end
            
            # Wait for all parallel loads to complete and collect results
            cached_images = NamedTuple[]
            for task in load_tasks
                result = fetch(task)
                if result.success
                    push!(cached_images, result.data)
                end
            end
            
            # Store in cache
            lock(cache_lock) do
                patient_image_cache[patient_id] = cached_images
                delete!(preload_tasks, patient_id)  # Remove from in-progress
                println("[PRELOAD] Cached $(length(cached_images))/$(length(entries)) images for patient $patient_id")
            end
            
            return (success = true, error = nothing)
            
        catch e
            @warn "[PRELOAD] Fatal error preloading patient $patient_id: $e"
            # Clean up task tracking
            lock(cache_lock) do
                delete!(preload_tasks, patient_id)
            end
            return (success = false, error = "Fatal preload error: $(typeof(e))")
        end
    end
    
    """
    Trigger multi-threaded preload for a patient (non-blocking).
    Uses Threads.@spawn for true parallel execution across CPU cores.
    """
    function trigger_preload(patient_id::Int)
        lock(cache_lock) do
            # Skip if already cached or in progress
            if haskey(patient_image_cache, patient_id)
                return
            end
            if haskey(preload_tasks, patient_id) && !istaskdone(preload_tasks[patient_id])
                return
            end
            
            # Start async preload (parallel loading happens inside preload_patient_images)
            # Use @async for main thread compatibility - parallel .bin loading is inside
            task = @async begin
                preload_patient_images(patient_id)
            end
            preload_tasks[patient_id] = task
            println("[PRELOAD] Triggered async preload for patient $patient_id (parallel .bin loading inside)")
        end
    end
    
    """
    Get cached images for patient (non-blocking).
    Returns cached data or nothing if not in cache.
    """
    function get_from_cache(patient_id::Int)
        local cached = nothing
        lock(cache_lock) do
            cached = get(patient_image_cache, patient_id, nothing)
        end
        return cached
    end
    
    """
    Trigger multi-threaded preload with callback executed when preload completes.
    Callback is executed to rebuild UI with loaded data.
    Uses Threads.@spawn for parallel .bin file loading.
    """
    function trigger_preload_with_callback(callback::Function, patient_id::Int)
        try
            local should_start = false
            local already_cached = false
            
            lock(cache_lock) do
                # Check if already cached
                if haskey(patient_image_cache, patient_id)
                    already_cached = true
                # Check if already in progress
                elseif haskey(preload_tasks, patient_id) && !istaskdone(preload_tasks[patient_id])
                    println("[PRELOAD] Patient $patient_id already loading, skipping")
                else
                    # Need to start new preload
                    should_start = true
                end
            end
            
            # If already cached, execute callback immediately
            if already_cached
                println("[PRELOAD] Patient $patient_id already cached, executing callback immediately")
                try
                    callback()
                catch e
                    @warn "[PRELOAD] Error executing callback for cached patient $patient_id: $e"
                    # Show error in UI
                    status_label.text = "Fehler beim Laden von Patient $patient_id"
                    status_label.color = :red
                end
                return
            end
            
            # Start async preload if needed (parallel .bin loading happens inside preload_patient_images)
            # Use @async for main thread compatibility on Windows - callbacks run on main thread
            if should_start
                local task = @async begin
                    try
                        local result = preload_patient_images(patient_id)
                        
                        # Execute callback on completion (already on main thread via @async)
                        try
                            if result.success
                                println("[PRELOAD] Preload complete for patient $patient_id, executing callback")
                                callback()
                            else
                                # Preload failed - show error in UI
                                @warn "[PRELOAD] Preload failed for patient $patient_id: $(result.error)"
                                status_label.text = "Fehler beim Laden: $(result.error)"
                                status_label.color = :red
                                
                                # Clear loading message
                                clear_images_grid!()
                                Bas3GLMakie.GLMakie.Label(
                                    images_grid[1, 1],
                                    "Fehler beim Laden von Patient $patient_id\n\n$(result.error)\n\nBitte versuchen Sie einen anderen Patienten.",
                                    fontsize=16,
                                    halign=:center,
                                    color=:red
                                )
                            end
                        catch e
                            @warn "[PRELOAD] Error executing callback for patient $patient_id: $e"
                            status_label.text = "Fehler nach dem Laden: $(typeof(e))"
                            status_label.color = :red
                        end
                    catch e
                        @warn "[PRELOAD] Async task error for patient $patient_id: $e"
                        # Clean up task tracking
                        lock(cache_lock) do
                            delete!(preload_tasks, patient_id)
                        end
                        
                        # Show error in UI (already on main thread)
                        status_label.text = "Fehler beim asynchronen Laden: $(typeof(e))"
                        status_label.color = :red
                    end
                end
                
                lock(cache_lock) do
                    preload_tasks[patient_id] = task
                end
                
                println("[PRELOAD] Triggered async preload for patient $patient_id with callback (parallel .bin loading inside)")
            end
        catch e
            @warn "[PRELOAD] Error in trigger_preload_with_callback for patient $patient_id: $e"
            status_label.text = "Fehler beim Starten des Ladevorgangs: $(typeof(e))"
            status_label.color = :red
        end
    end
    
    """
    Clean up cache entries for patients far from current.
    Keeps current patient and immediate neighbors.
    """
    function cleanup_cache(current_patient_id::Int)
        # Find current patient's position in the sorted list
        local current_idx = findfirst(==(current_patient_id), all_patient_ids)
        if isnothing(current_idx)
            return
        end
        
        # Keep patients within ±1 position
        local keep_ids = Set{Int}()
        for offset in -1:1
            local idx = current_idx + offset
            if 1 <= idx <= length(all_patient_ids)
                push!(keep_ids, all_patient_ids[idx])
            end
        end
        
        # Evict entries not in keep_ids
        lock(cache_lock) do
            for patient_id in collect(keys(patient_image_cache))
                if !(patient_id in keep_ids)
                    delete!(patient_image_cache, patient_id)
                    println("[CACHE] Evicted patient $patient_id from cache")
                end
            end
        end
    end
    
    # Clear all image widgets - RECURSIVE deletion for nested GridLayouts
    function clear_images_grid!()
        println("[COMPARE-UI] Clearing images grid ($(length(images_grid.content)) items) and timeline...")
        
        # Helper to recursively delete GridLayout contents
        function delete_gridlayout_contents!(gl)
            while !isempty(gl.content)
                content_item = gl.content[1]
                obj = content_item.content
                
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
        
        # Clear the main images_grid recursively
        delete_gridlayout_contents!(images_grid)
        
        # Clear the timeline_grid as well
        delete_gridlayout_contents!(timeline_grid)
        timeline_axis[] = nothing
        
        # Clear widget arrays
        empty!(image_axes)
        empty!(date_textboxes)
        empty!(info_textboxes)
        empty!(patient_id_textboxes)  # NEW
        empty!(save_buttons)
        empty!(image_labels)
        empty!(image_observables)
        empty!(hsv_grids)       # NEW
        empty!(hsv_class_data)  # NEW
        
        # Clear polygon state arrays
        empty!(polygon_vertices_per_image)
        empty!(polygon_active_per_image)
        empty!(polygon_complete_per_image)
        empty!(polygon_buttons_per_image)
        
        println("[COMPARE-UI] Grid cleared, $(length(images_grid.content)) items remaining")
    end
    
    # Build image widgets for current patient
    function build_patient_images!(patient_id::Int)
        try
            println("[COMPARE-UI] Building images for patient $patient_id")
            local build_start_time = time()
            
            # Clear existing widgets
            clear_images_grid!()
        
        # Get entries for this patient (metadata from DB)
        entries = get_images_for_patient(db_path, patient_id)
        current_entries[] = entries
        
        if isempty(entries)
            status_label.text = "Keine Bilder für Patient $patient_id gefunden"
            status_label.color = :orange
            
            # Show placeholder message
            Bas3GLMakie.GLMakie.Label(
                images_grid[1, 1],
                "Keine Bilder vorhanden.\nFügen Sie Bilder über die InteractiveUI hinzu.",
                fontsize=16,
                halign=:center,
                color=:gray
            )
            return
        end
        
        # Check cache (non-blocking)
        local cached_images = get_from_cache(patient_id)
        
        # Handle cache MISS - trigger async load and show loading message
        if isnothing(cached_images)
            cache_misses[] += 1
            println("[CACHE] MISS for patient $patient_id (hits=$(cache_hits[]), misses=$(cache_misses[])) - loading asynchronously...")
            
            # Show loading placeholder
            Bas3GLMakie.GLMakie.Label(
                images_grid[1, 1],
                "Lade Bilder für Patient $patient_id...\n\n$(length(entries)) Bilder werden verarbeitet.\nBitte warten.",
                fontsize=16,
                halign=:center,
                color=:orange
            )
            
            status_label.text = "Lade Patient $patient_id ($(length(entries)) Bilder)..."
            status_label.color = :orange
            
            # Trigger async preload with callback to rebuild UI when done
            trigger_preload_with_callback(patient_id) do
                println("[COMPARE-UI] Async load complete for patient $patient_id, rebuilding UI")
                build_patient_images!(patient_id)  # Recursive call will hit cache
            end
            
            return  # Don't build widgets yet - wait for async load
        end
        
        # Cache HIT - proceed with cached data
        cache_hits[] += 1
        local cache_hit = true
        println("[CACHE] HIT for patient $patient_id (hits=$(cache_hits[]), misses=$(cache_misses[]))")
        
        # Create lookup from image_index to cached data
        local cached_lookup = Dict{Int, NamedTuple}()
        for img_data in cached_images
            cached_lookup[img_data.image_index] = img_data
        end
        
        status_label.text = "$(length(entries)) Bilder für Patient $patient_id (CACHE HIT)"
        status_label.color = :green
        
        # Create widgets for each image
        num_images = min(length(entries), max_images_per_row)
        
        for (col, entry) in enumerate(entries[1:num_images])
            println("[COMPARE-UI] Creating column $col for image $(entry.image_index)")
            
            # Row 1: Image label (index + date)
            local img_label = Bas3GLMakie.GLMakie.Label(
                images_grid[1, col],
                "Bild $(entry.image_index)",
                fontsize=14,
                font=:bold,
                halign=:center
            )
            push!(image_labels, img_label)
            
            # Row 2: Image axis
            local ax = Bas3GLMakie.GLMakie.Axis(
                images_grid[2, col],
                aspect=Bas3GLMakie.GLMakie.DataAspect(),
                title=""
            )
            Bas3GLMakie.GLMakie.hidedecorations!(ax)
            push!(image_axes, ax)
            
            # Get image data from cache or compute fresh
            local img_data = get(cached_lookup, entry.image_index, nothing)
            
            if !isnothing(img_data)
                # USE CACHED DATA
                # Create observable for input image
                local img_obs = Bas3GLMakie.GLMakie.Observable(img_data.input_rotated)
                push!(image_observables, img_obs)
                
                # Layer 1: Display input image (base layer)
                Bas3GLMakie.GLMakie.image!(ax, img_obs)
                
                # Layer 2: Overlay output segmentation with 50% transparency
                local output_obs = Bas3GLMakie.GLMakie.Observable(img_data.output_rotated)
                Bas3GLMakie.GLMakie.image!(ax, output_obs; alpha=0.5)
                
                # Layer 3: Draw bounding boxes (computed on-demand from cached raw data)
                if !isnothing(img_data.output_raw)
                    local bboxes = extract_class_bboxes(img_data.output_raw, classes)
                    draw_bboxes_on_axis!(ax, bboxes, img_data.height)
                    println("[COMPARE-UI] Drew on-demand bboxes for image $(entry.image_index)")
                end
                
                # Layer 4: POLYGON OVERLAY (per-image polygon selection)
                # Initialize polygon state for this image
                local poly_verts = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
                local poly_active = Bas3GLMakie.GLMakie.Observable(false)
                local poly_complete = Bas3GLMakie.GLMakie.Observable(false)
                
                push!(polygon_vertices_per_image, poly_verts)
                push!(polygon_active_per_image, poly_active)
                push!(polygon_complete_per_image, poly_complete)
                
                # Draw polygon lines (cyan, auto-closing)
                Bas3GLMakie.GLMakie.lines!(ax,
                    Bas3GLMakie.GLMakie.@lift(begin
                        verts = $poly_verts
                        isempty(verts) ? Bas3GLMakie.GLMakie.Point2f[] : vcat(verts, [verts[1]])
                    end),
                    color=:cyan,
                    linewidth=2,
                    visible = Bas3GLMakie.GLMakie.@lift(!isempty($poly_verts))
                )
                
                # Draw polygon vertices (cyan circles)
                Bas3GLMakie.GLMakie.scatter!(ax, poly_verts,
                    color=:cyan,
                    markersize=8,
                    visible = Bas3GLMakie.GLMakie.@lift(!isempty($poly_verts))
                )
                
                println("[POLYGON] Initialized polygon state for column $col")
                
                # Row 3: HSV mini histograms (computed on-demand from cached raw data)
                if !isnothing(img_data.output_raw) && !isnothing(img_data.input_raw)
                    local class_hsv = extract_class_hsv_values(img_data.input_raw, img_data.output_raw, classes)
                    push!(hsv_class_data, class_hsv)
                    
                    local hsv_grid = create_hsv_mini_histograms!(images_grid[3, col], class_hsv, classes)
                    push!(hsv_grids, hsv_grid)
                else
                    push!(hsv_class_data, Dict())
                    push!(hsv_grids, nothing)
                end
            else
                # FALLBACK: Compute fresh (should rarely happen)
                println("[COMPARE-UI] WARNING: Image $(entry.image_index) not in cache, computing fresh")
                
                local images = get_images_by_index(entry.image_index)
                
                # Create observable for input image
                local img_obs = Bas3GLMakie.GLMakie.Observable(images.input)
                push!(image_observables, img_obs)
                
                # Layer 1: Display input image (base layer)
                Bas3GLMakie.GLMakie.image!(ax, img_obs)
                
                # Layer 2: Overlay output segmentation with 50% transparency
                local output_obs = Bas3GLMakie.GLMakie.Observable(images.output)
                Bas3GLMakie.GLMakie.image!(ax, output_obs; alpha=0.5)
                
                # Layer 3: Draw bounding boxes for each class
                if !isnothing(images.output_raw)
                    local bboxes = extract_class_bboxes(images.output_raw, classes)
                    draw_bboxes_on_axis!(ax, bboxes, images.height)
                    println("[COMPARE-UI] Drew fresh bboxes for image $(entry.image_index)")
                end
                
                # Layer 4: POLYGON OVERLAY (per-image polygon selection)
                # Initialize polygon state for this image
                local poly_verts = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
                local poly_active = Bas3GLMakie.GLMakie.Observable(false)
                local poly_complete = Bas3GLMakie.GLMakie.Observable(false)
                
                push!(polygon_vertices_per_image, poly_verts)
                push!(polygon_active_per_image, poly_active)
                push!(polygon_complete_per_image, poly_complete)
                
                # Draw polygon lines (cyan, auto-closing)
                Bas3GLMakie.GLMakie.lines!(ax,
                    Bas3GLMakie.GLMakie.@lift(begin
                        verts = $poly_verts
                        isempty(verts) ? Bas3GLMakie.GLMakie.Point2f[] : vcat(verts, [verts[1]])
                    end),
                    color=:cyan,
                    linewidth=2,
                    visible = Bas3GLMakie.GLMakie.@lift(!isempty($poly_verts))
                )
                
                # Draw polygon vertices (cyan circles)
                Bas3GLMakie.GLMakie.scatter!(ax, poly_verts,
                    color=:cyan,
                    markersize=8,
                    visible = Bas3GLMakie.GLMakie.@lift(!isempty($poly_verts))
                )
                
                println("[POLYGON] Initialized polygon state for column $col (fallback)")
                
                # Row 3: HSV mini histograms
                if !isnothing(images.output_raw) && !isnothing(images.input_raw)
                    local class_hsv = extract_class_hsv_values(images.input_raw, images.output_raw, classes)
                    push!(hsv_class_data, class_hsv)
                    
                    local hsv_grid = create_hsv_mini_histograms!(images_grid[3, col], class_hsv, classes)
                    push!(hsv_grids, hsv_grid)
                else
                    push!(hsv_class_data, Dict())
                    push!(hsv_grids, nothing)
                end
            end
            
            # Row 3.5: Polygon control buttons (Start/Close/Clear)
            local polygon_control_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[4, col])
            
            local start_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid[1, 1],
                label="Polygon",
                fontsize=9,
                width=60
            )
            
            local close_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid[1, 2],
                label="Schließen",
                fontsize=9,
                width=70
            )
            
            local clear_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid[1, 3],
                label="Löschen",
                fontsize=9,
                width=60
            )
            
            push!(polygon_buttons_per_image, (start_poly_btn, close_poly_btn, clear_poly_btn))
            
            # Polygon button callbacks (capture col index for this specific image)
            local col_idx = col
            
            # Start polygon button
            Bas3GLMakie.GLMakie.on(start_poly_btn.clicks) do n
                println("[POLYGON] Start polygon for column $col_idx")
                # Clear existing vertices when starting new polygon
                polygon_vertices_per_image[col_idx][] = Bas3GLMakie.GLMakie.Point2f[]
                polygon_active_per_image[col_idx][] = true
                polygon_complete_per_image[col_idx][] = false
            end
            
            # Close polygon button
            Bas3GLMakie.GLMakie.on(close_poly_btn.clicks) do n
                if length(polygon_vertices_per_image[col_idx][]) >= 3
                    println("[POLYGON] Close polygon for column $col_idx ($(length(polygon_vertices_per_image[col_idx][])) vertices)")
                    polygon_complete_per_image[col_idx][] = true
                    polygon_active_per_image[col_idx][] = false
                else
                    println("[POLYGON] Cannot close polygon for column $col_idx - need at least 3 vertices")
                end
            end
            
            # Clear polygon button
            Bas3GLMakie.GLMakie.on(clear_poly_btn.clicks) do n
                println("[POLYGON] Clear polygon for column $col_idx")
                polygon_vertices_per_image[col_idx][] = Bas3GLMakie.GLMakie.Point2f[]
                polygon_active_per_image[col_idx][] = false
                polygon_complete_per_image[col_idx][] = false
            end
            
            # Row 5: Date label + textbox
            local date_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[5, col])
            Bas3GLMakie.GLMakie.Label(
                date_grid[1, 1],
                "Datum:",
                fontsize=11,
                halign=:left
            )
            local date_tb = Bas3GLMakie.GLMakie.Textbox(
                date_grid[1, 2],
                placeholder="YYYY-MM-DD",
                stored_string=entry.date,
                width=120
            )
            push!(date_textboxes, date_tb)
            
            # Row 6: Info label + textbox
            local info_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[6, col])
            Bas3GLMakie.GLMakie.Label(
                info_grid[1, 1],
                "Info:",
                fontsize=11,
                halign=:left
            )
            local info_tb = Bas3GLMakie.GLMakie.Textbox(
                info_grid[1, 2],
                placeholder="Zusatzinfo...",
                stored_string=entry.info,
                width=200
            )
            push!(info_textboxes, info_tb)
            
            # Row 7: Patient-ID label + textbox (for reassignment)
            local pid_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[7, col])
            Bas3GLMakie.GLMakie.Label(
                pid_grid[1, 1],
                "Patient:",
                fontsize=11,
                halign=:left
            )
            local pid_tb = Bas3GLMakie.GLMakie.Textbox(
                pid_grid[1, 2],
                placeholder="ID",
                stored_string=string(patient_id),
                width=80
            )
            push!(patient_id_textboxes, pid_tb)
            
            # Row 8: Save button
            local save_btn = Bas3GLMakie.GLMakie.Button(
                images_grid[8, col],
                label="Speichern",
                fontsize=11
            )
            push!(save_buttons, save_btn)
            
            # Save button callback
            local entry_row = entry.row
            local entry_idx = entry.image_index
            local col_idx = col
            local original_patient_id = patient_id  # Capture current patient ID
            
            Bas3GLMakie.GLMakie.on(save_btn.clicks) do n
                println("[COMPARE-UI] Save clicked for image $entry_idx (column $col_idx)")
                
                # Get current values from textboxes
                new_date = something(date_textboxes[col_idx].displayed_string[], "")
                new_info = something(info_textboxes[col_idx].displayed_string[], "")
                new_pid_str = something(patient_id_textboxes[col_idx].displayed_string[], "")
                
                # Validate date
                (valid_date, date_msg) = validate_date_compare(new_date)
                if !valid_date
                    status_label.text = "Fehler Bild $entry_idx: $date_msg"
                    status_label.color = :red
                    return
                end
                
                # Validate info
                (valid_info, info_msg) = validate_info_compare(new_info)
                if !valid_info
                    status_label.text = "Fehler Bild $entry_idx: $info_msg"
                    status_label.color = :red
                    return
                end
                
                # Validate patient ID
                (valid_pid, pid_msg) = validate_patient_id_compare(new_pid_str)
                if !valid_pid
                    status_label.text = "Fehler Bild $entry_idx: $pid_msg"
                    status_label.color = :red
                    return
                end
                
                new_patient_id = parse(Int, strip(new_pid_str))
                patient_id_changed = (new_patient_id != original_patient_id)
                
                # Update database
                try
                    # Always update date and info
                    update_entry_compare(db_path, entry_row, new_date, new_info)
                    
                    # If patient ID changed, update that too
                    if patient_id_changed
                        update_patient_id_compare(db_path, entry_row, new_patient_id)
                        println("[COMPARE-UI] Patient ID changed from $original_patient_id to $new_patient_id")
                        
                        status_label.text = "Bild $entry_idx verschoben zu Patient $new_patient_id"
                        status_label.color = :blue
                        
                        # Update patient menu options (in case new patient was created)
                        new_patient_ids = get_all_patient_ids(db_path)
                        patient_menu.options = [string(pid) for pid in new_patient_ids]
                        
                        # Refresh current patient view (image will disappear from this view)
                        build_patient_images!(current_patient_id[])
                    else
                        status_label.text = "Bild $entry_idx gespeichert"
                        status_label.color = :green
                    end
                catch e
                    status_label.text = "Fehler beim Speichern: $(typeof(e))"
                    status_label.color = :red
                end
            end
        end
        
        # ====================================================================
        # CREATE H/S TIMELINE PLOT (after all HSV data is collected)
        # ====================================================================
        if !isempty(hsv_class_data)
            println("[COMPARE-UI] Creating H/S timeline with $(length(hsv_class_data)) data points")
            timeline_axis[] = create_hs_timeline!(timeline_grid, entries[1:num_images], hsv_class_data, classes)
        end
        
        # Show message if more images exist
        if length(entries) > max_images_per_row
            Bas3GLMakie.GLMakie.Label(
                images_grid[9, 1:num_images],
                "Weitere $(length(entries) - max_images_per_row) Bilder vorhanden (max. $max_images_per_row angezeigt)",
                fontsize=12,
                halign=:center,
                color=:orange
            )
        end
        
        # Set column sizes
        for col in 1:num_images
            Bas3GLMakie.GLMakie.colsize!(images_grid, col, Bas3GLMakie.GLMakie.Fixed(350))
        end
        
        # Set row sizes
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 1, Bas3GLMakie.GLMakie.Fixed(30))   # Label
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 2, Bas3GLMakie.GLMakie.Fixed(300))  # Image (reduced for HSV space)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 3, Bas3GLMakie.GLMakie.Fixed(200))  # HSV histograms (4 stacked)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 4, Bas3GLMakie.GLMakie.Fixed(35))   # Polygon controls
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 5, Bas3GLMakie.GLMakie.Fixed(40))   # Date
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 6, Bas3GLMakie.GLMakie.Fixed(40))   # Info
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 7, Bas3GLMakie.GLMakie.Fixed(40))   # Patient-ID
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 8, Bas3GLMakie.GLMakie.Fixed(40))   # Save button
        
            # Log timing
            local build_elapsed = round((time() - build_start_time) * 1000, digits=1)
            println("[COMPARE-UI] Build completed in $(build_elapsed)ms (CACHE HIT)")
            
        catch e
            @warn "[COMPARE-UI] Error building UI for patient $patient_id: $e"
            
            # Clear any partial widgets
            try
                clear_images_grid!()
            catch
                # Ignore errors during cleanup
            end
            
            # Show error message
            Bas3GLMakie.GLMakie.Label(
                images_grid[1, 1],
                "Fehler beim Erstellen der UI für Patient $patient_id\n\n$(typeof(e))\n\nBitte versuchen Sie einen anderen Patienten oder starten Sie neu.",
                fontsize=16,
                halign=:center,
                color=:red
            )
            
            status_label.text = "Fehler beim Erstellen der UI: $(typeof(e))"
            status_label.color = :red
        end
    end
    
    # ========================================================================
    # EVENT CALLBACKS
    # ========================================================================
    
    # Patient menu selection callback
    Bas3GLMakie.GLMakie.on(patient_menu.selection) do selected
        if !isnothing(selected)
            patient_id = tryparse(Int, selected)
            if !isnothing(patient_id)
                println("[COMPARE-UI] Patient selected: $patient_id")
                current_patient_id[] = patient_id
                build_patient_images!(patient_id)
            end
        end
    end
    
    # Refresh button callback
    Bas3GLMakie.GLMakie.on(refresh_button.clicks) do n
        println("[COMPARE-UI] Refreshing patient list...")
        
        # Reload patient IDs from database
        new_patient_ids = get_all_patient_ids(db_path)
        
        if isempty(new_patient_ids)
            status_label.text = "Keine Patienten in Datenbank gefunden"
            status_label.color = :orange
            return
        end
        
        # Update menu options
        patient_menu.options = [string(pid) for pid in new_patient_ids]
        
        # Rebuild current patient view
        if current_patient_id[] in new_patient_ids
            build_patient_images!(current_patient_id[])
        elseif !isempty(new_patient_ids)
            current_patient_id[] = new_patient_ids[1]
            patient_menu.i_selected[] = 1
            build_patient_images!(new_patient_ids[1])
        end
        
        status_label.text = "Liste aktualisiert: $(length(new_patient_ids)) Patienten"
        status_label.color = :green
    end
    
    # Clear all polygons button callback
    Bas3GLMakie.GLMakie.on(clear_polygons_button.clicks) do n
        println("[POLYGON] Clearing all polygons ($(length(polygon_vertices_per_image)) images)")
        for i in 1:length(polygon_vertices_per_image)
            polygon_vertices_per_image[i][] = Bas3GLMakie.GLMakie.Point2f[]
            polygon_active_per_image[i][] = false
            polygon_complete_per_image[i][] = false
        end
        status_label.text = "Alle Polygone gelöscht"
        status_label.color = :green
    end
    
    # Mouse click handler for polygon vertex placement
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).mousebutton) do event
        if event.button == Bas3GLMakie.GLMakie.Mouse.left && 
           event.action == Bas3GLMakie.GLMakie.Mouse.press
            
            # Determine which axis was clicked
            for (col_idx, ax) in enumerate(image_axes)
                # Check if this axis is valid and has a scene
                if !isnothing(ax) && !isnothing(ax.scene)
                    # Get mouse position in axis coordinates
                    local mp = Bas3GLMakie.GLMakie.mouseposition(ax.scene)
                    
                    # Check if mouse is inside axis limits
                    if !isnothing(mp)
                        local x_limits = ax.finallimits[].origin[1] .+ (0, ax.finallimits[].widths[1])
                        local y_limits = ax.finallimits[].origin[2] .+ (0, ax.finallimits[].widths[2])
                        
                        if mp[1] >= x_limits[1] && mp[1] <= x_limits[2] &&
                           mp[2] >= y_limits[1] && mp[2] <= y_limits[2]
                            
                            # Mouse is inside this axis
                            if col_idx <= length(polygon_active_per_image) &&
                               polygon_active_per_image[col_idx][] && 
                               !polygon_complete_per_image[col_idx][]
                                
                                # Add vertex to this image's polygon
                                local new_vertex = Bas3GLMakie.GLMakie.Point2f(Float32(mp[1]), Float32(mp[2]))
                                local current_verts = polygon_vertices_per_image[col_idx][]
                                push!(current_verts, new_vertex)
                                polygon_vertices_per_image[col_idx][] = current_verts
                                
                                println("[POLYGON] Added vertex to column $col_idx: $new_vertex (total: $(length(current_verts)))")
                            end
                            
                            break  # Only process one axis per click
                        end
                    end
                end
            end
        end
    end
    
    # Navigation helper: navigate to patient at given index
    function navigate_to_patient_index(target_idx::Int)
        if target_idx < 1 || target_idx > length(all_patient_ids)
            println("[NAV] Index $target_idx out of bounds (1-$(length(all_patient_ids)))")
            return
        end
        
        local target_patient_id = all_patient_ids[target_idx]
        println("[NAV] Navigating to patient index $target_idx (patient_id=$target_patient_id)")
        
        # Update current patient
        current_patient_id[] = target_patient_id
        patient_menu.i_selected[] = target_idx
        
        # Build images (will use cache if available)
        build_patient_images!(target_patient_id)
        
        # Clean up old cache entries
        cleanup_cache(target_patient_id)
        
        # Trigger preloads for neighbors
        if target_idx > 1
            trigger_preload(all_patient_ids[target_idx - 1])
        end
        if target_idx < length(all_patient_ids)
            trigger_preload(all_patient_ids[target_idx + 1])
        end
    end
    
    # Previous button callback
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do n
        local current_idx = findfirst(==(current_patient_id[]), all_patient_ids)
        if isnothing(current_idx)
            println("[NAV] Current patient not found in list")
            return
        end
        
        if current_idx <= 1
            status_label.text = "Erster Patient erreicht"
            status_label.color = :orange
            return
        end
        
        navigate_to_patient_index(current_idx - 1)
    end
    
    # Next button callback
    Bas3GLMakie.GLMakie.on(next_button.clicks) do n
        local current_idx = findfirst(==(current_patient_id[]), all_patient_ids)
        if isnothing(current_idx)
            println("[NAV] Current patient not found in list")
            return
        end
        
        if current_idx >= length(all_patient_ids)
            status_label.text = "Letzter Patient erreicht"
            status_label.color = :orange
            return
        end
        
        navigate_to_patient_index(current_idx + 1)
    end
    
    # WORKAROUND: Register figure-level mouse event for GLMakie button activation
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).mousebutton) do event
        # Do nothing - just activates event handling
    end
    
    # ========================================================================
    # INITIAL BUILD
    # ========================================================================
    
    # Build images for first patient
    if !isempty(all_patient_ids) && all_patient_ids[1] != 0
        build_patient_images!(all_patient_ids[1])
    else
        status_label.text = "Keine Patienten in Datenbank. Nutzen Sie InteractiveUI zum Hinzufügen."
        status_label.color = :orange
        
        Bas3GLMakie.GLMakie.Label(
            images_grid[1, 1],
            "Keine Patientendaten vorhanden.\n\nBitte fügen Sie zuerst Bilder über die InteractiveUI hinzu:\n  julia --script=run_Load_Sets__InteractiveUI.jl",
            fontsize=16,
            halign=:center,
            color=:gray
        )
    end
    
    println("[COMPARE-UI] Figure created successfully")
    println("\n=== CompareUI Controls ===")
    println("  - Select patient from dropdown menu")
    println("  - Edit date/info fields for each image")
    println("  - Click 'Speichern' to save changes")
    println("  - Click 'Aktualisieren' to reload patient list")
    println("")
    
    # Return based on mode
    if test_mode
        println("[COMPARE-UI] Test mode enabled - returning internals")
        return (
            figure = fgr,
            observables = Dict(
                :current_patient_id => current_patient_id,
                :current_entries => current_entries,
            ),
            widgets = Dict(
                :patient_menu => patient_menu,
                :refresh_button => refresh_button,
                :clear_polygons_button => clear_polygons_button,  # NEW: Clear all polygons
                :prev_button => prev_button,      # NEW: Navigation buttons
                :next_button => next_button,      # NEW: Navigation buttons
                :status_label => status_label,
            ),
            # Dynamic widget arrays (change when patient changes)
            dynamic_widgets = Dict(
                :image_axes => image_axes,
                :date_textboxes => date_textboxes,
                :info_textboxes => info_textboxes,
                :patient_id_textboxes => patient_id_textboxes,
                :save_buttons => save_buttons,
                :image_labels => image_labels,
                :image_observables => image_observables,
                :hsv_grids => hsv_grids,
                :hsv_class_data => hsv_class_data,
                :polygon_vertices_per_image => polygon_vertices_per_image,      # NEW: Polygon state
                :polygon_active_per_image => polygon_active_per_image,          # NEW: Polygon state
                :polygon_complete_per_image => polygon_complete_per_image,      # NEW: Polygon state
                :polygon_buttons_per_image => polygon_buttons_per_image,        # NEW: Polygon buttons
            ),
            # Expose helper functions for testing
            functions = Dict(
                :build_patient_images! => build_patient_images!,
                :clear_images_grid! => clear_images_grid!,
                :get_image_by_index => get_image_by_index,
                :preload_patient_images => preload_patient_images,
                :trigger_preload => trigger_preload,
                :trigger_preload_with_callback => trigger_preload_with_callback,  # NEW: Async with callback
                :get_from_cache => get_from_cache,                                # NEW: Non-blocking cache check
                :cleanup_cache => cleanup_cache,
                :navigate_to_patient_index => navigate_to_patient_index,
            ),
            # Cache state for testing
            cache = Dict(
                :patient_image_cache => patient_image_cache,
                :cache_lock => cache_lock,
                :preload_tasks => preload_tasks,
                :cache_hits => cache_hits,
                :cache_misses => cache_misses,
            ),
            # Database path for verification
            db_path = db_path,
            all_patient_ids = all_patient_ids,
        )
    else
        return fgr
    end
end
