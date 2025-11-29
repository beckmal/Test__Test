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
        
        # Create compact title with class name and stats on one line
        local title_text = "$class_name n=$(class_data.count) H=$(round(Int, class_data.median_h))° S=$(round(Int, class_data.median_s))% V=$(round(Int, class_data.median_v))%"
        
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
        
        # Plot H, S, V histograms with transparency
        if length(class_data.h_values) > 0
            # Hue (0-360) - normalize to percentage for consistent scale
            local h_normalized = class_data.h_values ./ 3.6
            Bas3GLMakie.GLMakie.hist!(ax, h_normalized, bins=12, color=(:orange, 0.5), normalization=:pdf)
            
            # Saturation (0-100)
            Bas3GLMakie.GLMakie.hist!(ax, class_data.s_values, bins=12, color=(:magenta, 0.4), normalization=:pdf)
            
            # Value (0-100)
            Bas3GLMakie.GLMakie.hist!(ax, class_data.v_values, bins=12, color=(:gray, 0.4), normalization=:pdf)
        end
        
        # Set axis limits
        Bas3GLMakie.GLMakie.xlims!(ax, 0, 100)
    end
    
    # Set tight row spacing for vertical stack
    Bas3GLMakie.GLMakie.rowgap!(hsv_grid, 2)
    
    return hsv_grid
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
    fig_width = min(400 * max_images_per_row + 200, 2400)
    local fgr = Bas3GLMakie.GLMakie.Figure(size=(fig_width, 800))
    
    # ========================================================================
    # ROW 1: Title and Patient Selector
    # ========================================================================
    local title_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[1, 1])
    
    Bas3GLMakie.GLMakie.Label(
        title_grid[1, 1],
        "Patientenbilder Vergleich",
        fontsize=24,
        font=:bold,
        halign=:left
    )
    
    # Patient ID selector
    Bas3GLMakie.GLMakie.Label(
        title_grid[1, 2],
        "Patient-ID:",
        fontsize=14,
        halign=:right
    )
    
    # Menu for patient selection
    local patient_menu = Bas3GLMakie.GLMakie.Menu(
        title_grid[1, 3],
        options = [string(pid) for pid in all_patient_ids],
        default = isempty(all_patient_ids) ? nothing : string(all_patient_ids[1]),
        width = 100
    )
    
    # Refresh button to reload patient list
    local refresh_button = Bas3GLMakie.GLMakie.Button(
        title_grid[1, 4],
        label = "Aktualisieren",
        fontsize = 12
    )
    
    # Status label
    local status_label = Bas3GLMakie.GLMakie.Label(
        title_grid[1, 5],
        "",
        fontsize=12,
        halign=:left,
        color=:gray
    )
    
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(60))
    
    # ========================================================================
    # ROW 2: Images Container (scrollable grid)
    # ========================================================================
    local images_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[2, 1])
    
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
    local current_entries = Bas3GLMakie.GLMakie.Observable(NamedTuple[])
    local current_patient_id = Bas3GLMakie.GLMakie.Observable(isempty(all_patient_ids) ? 0 : all_patient_ids[1])
    
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
    
    # Clear all image widgets - RECURSIVE deletion for nested GridLayouts
    function clear_images_grid!()
        println("[COMPARE-UI] Clearing images grid ($(length(images_grid.content)) items)...")
        
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
        
        println("[COMPARE-UI] Grid cleared, $(length(images_grid.content)) items remaining")
    end
    
    # Build image widgets for current patient
    function build_patient_images!(patient_id::Int)
        println("[COMPARE-UI] Building images for patient $patient_id")
        
        # Clear existing widgets
        clear_images_grid!()
        
        # Get entries for this patient
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
        
        status_label.text = "$(length(entries)) Bilder für Patient $patient_id"
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
            
            # Get both input and output images
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
                println("[COMPARE-UI] Drew bounding boxes for image $(entry.image_index): $(sum(length(v) for v in values(bboxes))) boxes")
            end
            
            # Row 3: HSV mini histograms (2x2 grid per class)
            if !isnothing(images.output_raw) && !isnothing(images.input_raw)
                local class_hsv = extract_class_hsv_values(images.input_raw, images.output_raw, classes)
                push!(hsv_class_data, class_hsv)
                
                local hsv_grid = create_hsv_mini_histograms!(images_grid[3, col], class_hsv, classes)
                push!(hsv_grids, hsv_grid)
                
                # Log HSV extraction
                local total_pixels = sum(d.count for d in values(class_hsv))
                println("[COMPARE-UI] Extracted HSV for image $(entry.image_index): $total_pixels pixels across $(length(class_hsv)) classes")
            else
                push!(hsv_class_data, Dict())
                push!(hsv_grids, nothing)
            end
            
            # Row 4: Date label + textbox
            local date_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[4, col])
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
            
            # Row 5: Info label + textbox
            local info_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[5, col])
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
            
            # Row 6: Patient-ID label + textbox (for reassignment)
            local pid_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[6, col])
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
            
            # Row 7: Save button
            local save_btn = Bas3GLMakie.GLMakie.Button(
                images_grid[7, col],
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
        
        # Show message if more images exist
        if length(entries) > max_images_per_row
            Bas3GLMakie.GLMakie.Label(
                images_grid[8, 1:num_images],
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
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 4, Bas3GLMakie.GLMakie.Fixed(40))   # Date
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 5, Bas3GLMakie.GLMakie.Fixed(40))   # Info
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 6, Bas3GLMakie.GLMakie.Fixed(40))   # Patient-ID
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 7, Bas3GLMakie.GLMakie.Fixed(40))   # Save button
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
                :status_label => status_label,
            ),
            # Dynamic widget arrays (change when patient changes)
            dynamic_widgets = Dict(
                :image_axes => image_axes,
                :date_textboxes => date_textboxes,
                :info_textboxes => info_textboxes,
                :patient_id_textboxes => patient_id_textboxes,  # NEW
                :save_buttons => save_buttons,
                :image_labels => image_labels,
                :image_observables => image_observables,
                :hsv_grids => hsv_grids,           # NEW: HSV histogram grids
                :hsv_class_data => hsv_class_data, # NEW: HSV data per image
            ),
            # Expose helper functions for testing
            functions = Dict(
                :build_patient_images! => build_patient_images!,
                :clear_images_grid! => clear_images_grid!,
                :get_image_by_index => get_image_by_index,
            ),
            # Database path for verification
            db_path = db_path,
            all_patient_ids = all_patient_ids,
        )
    else
        return fgr
    end
end
