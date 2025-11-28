# Load_Sets__InteractiveUI.jl
# Interactive visualization module - Figure 4

# Required packages for database functionality
using XLSX
using Dates

# ============================================================================
# DATABASE FUNCTIONS FOR MUHA.XLSX
# ============================================================================

# Database path: Platform-independent, uses @__DIR__ to resolve at runtime
# This ensures it works on Windows, WSL, Linux, etc. without hardcoded paths

"""
    validate_date(date_str::String) -> (Bool, String)

Validates date string in YYYY-MM-DD format.
Returns (success, error_message).
"""
function validate_date(date_str::String)
    # Check format with regex
    if !occursin(r"^\d{4}-\d{2}-\d{2}$", date_str)
        return (false, "Format muss YYYY-MM-DD sein")
    end
    
    # Check if valid date
    try
        parsed = Dates.Date(date_str, "yyyy-mm-dd")
        
        # Check not in future
        if parsed > Dates.today()
            return (false, "Datum darf nicht in der Zukunft liegen")
        end
        
        return (true, "")
    catch
        return (false, "Ungültiges Datum")
    end
end

"""
    validate_patient_id(id_str::String) -> (Bool, String)

Validates patient ID must be integer > 0.
Returns (success, error_message).
"""
function validate_patient_id(id_str::String)
    if isempty(id_str)
        return (false, "Patient-ID ist erforderlich")
    end
    
    # Try to parse as integer
    try
        id = parse(Int, id_str)
        
        if id <= 0
            return (false, "Patient-ID muss größer als 0 sein")
        end
        
        return (true, "")
    catch
        return (false, "Patient-ID muss eine Zahl sein")
    end
end

"""
    validate_info(info_str::String) -> (Bool, String)

Validates info field (max 500 characters).
Returns (success, error_message).
"""
function validate_info(info_str::String)
    if length(info_str) > 500
        return (false, "Info darf maximal 500 Zeichen haben")
    end
    
    return (true, "")
end

"""
    initialize_database() -> String

Creates MuHa.xlsx if it doesn't exist with proper schema.
Returns path to database file.

Platform-independent: Always uses the Load_Sets directory where this script lives.
"""
function initialize_database()
    # Platform-independent: database lives next to this script
    db_path = joinpath(@__DIR__, "MuHa.xlsx")
    println("[DATABASE] Using location: $db_path")
    
    # Create if doesn't exist
    if !isfile(db_path)
        println("[DATABASE] Creating new database: $db_path")
        
        # Create new workbook
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
        
        println("[DATABASE] Created successfully")
    else
        println("[DATABASE] Existing database found: $db_path")
    end
    
    return db_path
end

"""
    find_entry_for_image(db_path::String, image_index::Int) -> (Bool, Int, Dict)

Searches for existing entry for given image index.
Returns (found, row_number, entry_data).
"""
function find_entry_for_image(db_path::String, image_index::Int)
    xf = XLSX.readxlsx(db_path)
    sheet = xf["Metadata"]
    
    # Get dimensions
    dims = XLSX.get_dimension(sheet)
    last_row = dims.stop.row_number
    
    # Search for image_index in column A
    for row in 2:last_row  # Skip header row
        cell_value = sheet[row, 1]
        if !isnothing(cell_value) && cell_value == image_index
            existing = Dict(
                "filename" => sheet[row, 2],
                "date" => string(sheet[row, 3]),
                "patient_id" => sheet[row, 4],
                "info" => something(sheet[row, 5], ""),
                "created_at" => string(sheet[row, 6]),
                "updated_at" => string(sheet[row, 7])
            )
            return (true, row, existing)
        end
    end
    
    return (false, -1, Dict())
end

"""
    append_entry(db_path::String, image_index::Int, filename::String, 
                 date::String, patient_id::Int, info::String)

Appends new entry to database.
"""
function append_entry(db_path::String, image_index::Int, filename::String, 
                     date::String, patient_id::Int, info::String)
    XLSX.openxlsx(db_path, mode="rw") do xf
        sheet = xf["Metadata"]
        
        # Find next empty row
        dims = XLSX.get_dimension(sheet)
        next_row = dims.stop.row_number + 1
        
        # Get current timestamp
        timestamp = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
        
        # Write data
        sheet[next_row, 1] = image_index
        sheet[next_row, 2] = filename
        sheet[next_row, 3] = date
        sheet[next_row, 4] = patient_id
        sheet[next_row, 5] = info
        sheet[next_row, 6] = timestamp
        sheet[next_row, 7] = timestamp
    end
    
    println("[DATABASE] Appended entry for image $image_index")
end

"""
    update_entry(db_path::String, row::Int, date::String, patient_id::Int, info::String)

Updates existing entry at given row (preserves Created_At, updates Updated_At).
"""
function update_entry(db_path::String, row::Int, date::String, patient_id::Int, info::String)
    XLSX.openxlsx(db_path, mode="rw") do xf
        sheet = xf["Metadata"]
        
        # Get current timestamp
        timestamp = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
        
        # Update data (preserve Created_At in column F)
        sheet[row, 3] = date
        sheet[row, 4] = patient_id
        sheet[row, 5] = info
        sheet[row, 7] = timestamp  # Only update Updated_At
    end
    
    println("[DATABASE] Updated entry at row $row")
end

# ============================================================================
# INTERACTIVE UI FIGURE CREATION
# ============================================================================

"""
    create_interactive_figure(sets, input_type, raw_output_type; test_mode=false)

Creates an interactive visualization figure with:
- Image viewer with segmentation overlay
- White region detection with PCA-based oriented bounding boxes
- Interactive parameter controls (threshold, min area, aspect ratio, etc.)
- Dual statistics panels (full image vs white region)
- Region selection tool for constrained detection
- Navigation controls for browsing dataset

# Arguments
- `sets`: Vector of (input_image, output_image) tuples
- `input_type`: Input image type
- `raw_output_type`: Raw output image type
- `test_mode::Bool=false`: If true, return (figure, observables, widgets) for testing

# Returns
- **Production mode** (`test_mode=false`): `Figure` - GLMakie Figure object
- **Test mode** (`test_mode=true`): Named tuple with:
  - `figure`: GLMakie Figure object
  - `observables`: Dict{Symbol, Observable} - Internal state observables
  - `widgets`: Dict{Symbol, Widget} - UI widget references

# Test Mode Observables
Region Selection:
- `:selection_active`, `:selection_corner1`, `:selection_corner2`
- `:selection_complete`, `:selection_rect`, `:preview_rect`

Marker Detection:
- `:current_markers`, `:marker_success`, `:marker_message`

Image State:
- `:current_input_image`, `:current_output_image`
- `:current_white_overlay`, `:current_marker_viz`

# Test Mode Widgets
Navigation: `:nav_textbox`, `:prev_button`, `:next_button`, `:textbox_label`
Selection: `:selection_toggle`, `:clear_selection_button`, `:selection_status_label`
Parameters: `:threshold_textbox`, `:min_area_textbox`, `:aspect_ratio_textbox`, 
            `:aspect_weight_textbox`, `:kernel_size_textbox`
Display: `:segmentation_toggle`

# Dependencies
Requires functions from:
- Load_Sets__ConnectedComponents: extract_white_mask, find_connected_components
- Load_Sets__Morphology: morphological_close, morphological_open
- Load_Sets__Utilities: compute_skewness
- Load_Sets__Colors: CLASS_COLORS_RGB

# Examples
```julia
# Production usage (unchanged)
include("Load_Sets__Core.jl")
include("Load_Sets__InteractiveUI.jl")
sets = load_original_sets(306, false)
fig = create_interactive_figure(sets, input_type, raw_output_type)
display(GLMakie.Screen(), fig)

# Test mode usage (new)
result = create_interactive_figure(sets, input_type, raw_output_type; test_mode=true)
fig = result.figure
obs = result.observables
widgets = result.widgets

# Monitor state
println("Markers detected: ", length(obs[:current_markers][]))

# Simulate selection
obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(10, 10)
obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(100, 100)
obs[:selection_complete][] = true

# Verify results
@assert obs[:dewarp_success][]
```
"""
function create_interactive_figure(sets, input_type, raw_output_type; 
                                   test_mode::Bool=false)
    println("[INFO] Creating interactive figure with $(length(sets)) images (test_mode=$test_mode)")
    
    # Get classes from the first output image's shape
    classes = shape(sets[1][2])
    
    # Figure 4: Image Visualization with White Region Detection
    # Layout: Marker Extraction - Image - Full Image Stats - White Region Stats - Controls
    local fgr = Bas3GLMakie.GLMakie.Figure(size=(2200, 1000))

    # Add title for image figure
    local img_title = Bas3GLMakie.GLMakie.Label(
        fgr[1, 1:5], 
        "Interaktive Bildvisualisierung mit Markererkennung",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    # Column 1: Closeup View of Extracted Region (rotatable)
    local axs_closeup = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 1];
        title="Region Nahansicht (rotierbar)",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs_closeup)
    
    # Column 2: Input Image with Segmentation Overlay and White Region Detection
    local axs3 = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2];
        title="Eingabebild mit Segmentierung + Markererkennung",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs3)
    
    # Column 3: Full Image Statistics Plots (stacked vertically)
    # Axis for Mean ± Std per Channel
    local full_mean_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][1, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Gesamtbild: Intensität Mittelwert ± Std",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for Boxplot per Channel
    local full_box_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][2, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Gesamtbild: Intensitätsverteilung",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for RGB Histogram
    local full_hist_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][3, 1];
        title="Gesamtbild: RGB-Kanäle Histogramm",
        ylabel="Dichte",
        xlabel="Intensität"
    )
    
    # Column 4: White Region Statistics Plots (stacked vertically)
    # Axis for Mean ± Std per Channel
    local region_mean_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 4][1, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Marker: Intensität Mittelwert ± Std",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for Boxplot per Channel
    local region_box_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 4][2, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Marker: Intensitätsverteilung",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for RGB Histogram
    local region_hist_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 4][3, 1];
        title="Marker: RGB-Kanäle Histogramm",
        ylabel="Dichte",
        xlabel="Intensität"
    )
    
    # Column 5: Parameter control panel
    local param_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[2, 5])
    
    # Set row and column sizes
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(50))  # Title row
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(400)) # Marker column
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 3, Bas3GLMakie.GLMakie.Fixed(300)) # Full image stats column
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 4, Bas3GLMakie.GLMakie.Fixed(300)) # White region stats column
    
    # ========================================================================
    # DATABASE CONTROLS SECTION (Row 3, spanning columns 1-2)
    # ========================================================================
    local db_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[3, 1:2])
    
    # Set database controls row size (after creating it)
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 3, Bas3GLMakie.GLMakie.Fixed(120))
    
    # Initialize database
    local db_path = initialize_database()
    
    # Section title
    Bas3GLMakie.GLMakie.Label(
        db_grid[1, 1:4],
        "Datenbank Eintrag für MuHa-Bilder",
        fontsize=16,
        font=:bold,
        halign=:center
    )
    
    # Row 2: Date textbox + label + Patient ID textbox + label
    local date_textbox = Bas3GLMakie.GLMakie.Textbox(
        db_grid[2, 1],
        placeholder="YYYY-MM-DD",
        stored_string=Dates.format(Dates.today(), "yyyy-mm-dd"),
        width=150
    )
    local date_label = Bas3GLMakie.GLMakie.Label(
        db_grid[2, 2],
        "Datum",
        fontsize=12,
        halign=:left,
        color=:green  # Start green (initialized with valid date)
    )
    
    local patient_id_textbox = Bas3GLMakie.GLMakie.Textbox(
        db_grid[2, 3],
        placeholder="Nummer",
        width=120
    )
    local patient_id_label = Bas3GLMakie.GLMakie.Label(
        db_grid[2, 4],
        "Patient-ID",
        fontsize=12,
        halign=:left,
        color=:gray  # Start gray (empty)
    )
    
    # Row 3: Info textbox spanning multiple columns + label + character counter
    local info_textbox = Bas3GLMakie.GLMakie.Textbox(
        db_grid[3, 1:3],
        placeholder="Zusätzliche Informationen (optional)",
        width=400
    )
    local info_label = Bas3GLMakie.GLMakie.Label(
        db_grid[3, 4],
        "Info",
        fontsize=12,
        halign=:left,
        color=:gray  # Start gray (optional field)
    )
    
    # Character counter for info field (below textbox)
    local info_counter_label = Bas3GLMakie.GLMakie.Label(
        db_grid[3, 1],
        "0/500",
        fontsize=10,
        halign=:left,
        color=:gray
    )
    
    # Row 4: Save button + Status label
    local save_db_button = Bas3GLMakie.GLMakie.Button(
        db_grid[4, 1:2],
        label="Speichern in Datenbank",
        width=250
    )
    
    local db_status_label = Bas3GLMakie.GLMakie.Label(
        db_grid[4, 3:4],
        "Kein Eintrag vorhanden",
        fontsize=12,
        halign=:left,
        color=:black
    )
    
    # ========================================================================
    # REAL-TIME VALIDATION CALLBACKS
    # ========================================================================
    
    # Date textbox - real-time validation as user types
    Bas3GLMakie.GLMakie.on(date_textbox.displayed_string) do str
        str_clean = something(str, "")
        
        if isempty(str_clean)
            date_label.color = :gray  # Empty - neutral
        else
            (valid, msg) = validate_date(str_clean)
            if valid
                date_label.color = :green  # Valid - ready
            else
                date_label.color = :red  # Invalid - needs fixing
            end
        end
    end
    
    # Patient ID textbox - real-time validation as user types
    Bas3GLMakie.GLMakie.on(patient_id_textbox.displayed_string) do str
        println("[REALTIME] Patient ID displayed_string changed to: '$str'")
        flush(stdout)
        str_clean = something(str, "")
        
        if isempty(str_clean)
            patient_id_label.color = :gray  # Empty - neutral
        else
            (valid, msg) = validate_patient_id(str_clean)
            if valid
                patient_id_label.color = :green  # Valid - ready
                println("[REALTIME] Patient ID is VALID")
            else
                patient_id_label.color = :red  # Invalid - needs fixing
                println("[REALTIME] Patient ID is INVALID: $msg")
            end
        end
        flush(stdout)
    end
    
    # Info textbox - real-time character counter
    Bas3GLMakie.GLMakie.on(info_textbox.displayed_string) do str
        str_clean = something(str, "")
        char_count = length(str_clean)
        
        # Update counter text
        info_counter_label.text = "$char_count/500"
        
        # Update colors based on length
        if char_count == 0
            info_label.color = :gray        # Empty - optional field
            info_counter_label.color = :gray
        elseif char_count <= 450
            info_label.color = :green       # Normal range - good
            info_counter_label.color = :gray
        elseif char_count <= 500
            info_label.color = :orange      # Approaching limit - warning
            info_counter_label.color = :orange
        else
            info_label.color = :red         # Over limit - error
            info_counter_label.color = :red
        end
    end
    
    # ========================================================================
    # END DATABASE CONTROLS SECTION
    # ========================================================================
    
    # Panel title
    Bas3GLMakie.GLMakie.Label(
        param_grid[1, 1:4],
        "Regionsparameter",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    # Two-column layout: Left column (cols 1-2), Right column (cols 3-4)
    # Each parameter has: textbox | label | textbox | label
    
    # Row 2: Lower threshold | Upper threshold
    local threshold_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[2, 1],
        placeholder="0.7",
        stored_string="0.7",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[2, 2],
        "Unterer Schwellwert",
        fontsize=12,
        halign=:left
    )
    local threshold_upper_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[2, 3],
        placeholder="1.0",
        stored_string="1.0",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[2, 4],
        "Oberer Schwellwert",
        fontsize=12,
        halign=:left
    )
    
    # Row 3: Min area | Aspect ratio
    local min_area_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[3, 1],
        placeholder="8000",
        stored_string="8000",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[3, 2],
        "Min. Fläche [px]",
        fontsize=12,
        halign=:left
    )
    local aspect_ratio_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[3, 3],
        placeholder="5.0",
        stored_string="5.0",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[3, 4],
        "Seitenverhältnis",
        fontsize=12,
        halign=:left
    )
    
    # Row 4: Aspect weight | Kernel size
    local aspect_weight_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[4, 1],
        placeholder="0.6",
        stored_string="0.6",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[4, 2],
        "SV-Gewichtung",
        fontsize=12,
        halign=:left
    )
    local kernel_size_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[4, 3],
        placeholder="3",
        stored_string="3",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[4, 4],
        "Kernelgröße",
        fontsize=12,
        halign=:left
    )
    
    # Row 5: Adaptive toggle | Adaptive window
    local adaptive_toggle = Bas3GLMakie.GLMakie.Toggle(
        param_grid[5, 1],
        active=false
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[5, 2],
        "Adaptiv aktivieren",
        fontsize=12,
        halign=:left
    )
    local adaptive_window_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[5, 3],
        placeholder="25",
        stored_string="25",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[5, 4],
        "Adaptive Fenster",
        fontsize=12,
        halign=:left
    )
    
    # Row 6: Adaptive offset (spans left side only)
    local adaptive_offset_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[6, 1],
        placeholder="0.1",
        stored_string="0.1",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[6, 2],
        "Adaptive Offset",
        fontsize=12,
        halign=:left
    )
    
    # Error/status message label - spans both columns
    local param_status_label = Bas3GLMakie.GLMakie.Label(
        param_grid[11, 1:2],
        "",
        fontsize=12,
        halign=:center,
        color=:red
    )
    
    # Add separator
    Bas3GLMakie.GLMakie.Label(
        param_grid[12, 1:2],
        "─────────────────────",
        fontsize=12,
        halign=:center
    )
    
    # Region Selection Controls
    Bas3GLMakie.GLMakie.Label(
        param_grid[13, 1:4],
        "Regionsauswahl",
        fontsize=16,
        font=:bold,
        halign=:center
    )
    
    local start_selection_button = Bas3GLMakie.GLMakie.Button(
        param_grid[14, 1:2],
        label="Neue Auswahl starten",
        fontsize=12
    )
    
    local clear_selection_button = Bas3GLMakie.GLMakie.Button(
        param_grid[14, 3:4],
        label="Auswahl löschen",
        fontsize=12
    )
    
    local save_mask_button = Bas3GLMakie.GLMakie.Button(
        param_grid[15, 1:4],
        label="Maske speichern",
        fontsize=12
    )
    
    # Row 16: Rotation and X Position
    local rotation_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[16, 1],
        placeholder="0.0",
        stored_string="0.0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[16, 2],
        "Rotation [°]",
        fontsize=12,
        halign=:left
    )
    local x_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[16, 3],
        placeholder="0",
        stored_string="0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[16, 4],
        "X Position",
        fontsize=12,
        halign=:left
    )
    
    # Row 17: Y Position and Breite
    local y_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[17, 1],
        placeholder="0",
        stored_string="0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[17, 2],
        "Y Position",
        fontsize=12,
        halign=:left
    )
    local width_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[17, 3],
        placeholder="0",
        stored_string="0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[17, 4],
        "Breite",
        fontsize=12,
        halign=:left
    )
    
    # Row 18: Höhe (spans all columns since it's the last parameter)
    local height_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[18, 1],
        placeholder="0",
        stored_string="0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[18, 2],
        "Höhe",
        fontsize=12,
        halign=:left
    )
    
    # Row 18b: Closeup Rotation (right side of same row)
    local closeup_rotation_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[18, 3],
        placeholder="0.0",
        stored_string="0.0",
        width=60
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[18, 4],
        "Nahansicht Rotation [°]",
        fontsize=12,
        halign=:left
    )
    
    local selection_status_label = Bas3GLMakie.GLMakie.Label(
        param_grid[19, 1:4],
        "Keine Auswahl",
        fontsize=11,
        halign=:center,
        color=:gray
    )
    
    # Add separator
    Bas3GLMakie.GLMakie.Label(
        param_grid[20, 1:4],
        "─────────────────────",
        fontsize=12,
        halign=:center
    )
    
    # Overlay Control
    Bas3GLMakie.GLMakie.Label(
        param_grid[21, 1:4],
        "Überlagerungen",
        fontsize=16,
        font=:bold,
        halign=:center
    )
    
    local segmentation_toggle = Bas3GLMakie.GLMakie.Toggle(
        param_grid[22, 1],
        active=true
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[22, 2],
        "Segmentierung anzeigen",
        fontsize=12,
        halign=:left
    )
    
    # Navigation controls in a separate GridLayout
    local nav_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[3, 1:4])
    # Add navigation buttons and textbox for image selection
    local prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 1],
        label="← Vorheriges",
        fontsize=14
    )
    
    local textbox = Bas3GLMakie.GLMakie.Textbox(
        nav_grid[1, 2],
        placeholder="Bildnummer eingeben (1-$(length(sets)))",
        stored_string="1"
    )
    
    local next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 3],
        label="Nächstes →",
        fontsize=14
    )
    
    local textbox_label = Bas3GLMakie.GLMakie.Label(
        nav_grid[2, 1:3],
        "Bild: 1 / $(length(sets))",
        fontsize=16,
        halign=:center
    )
    
    # WORKAROUND: Register figure-level mouse event to activate event system
    # This MUST be done early, before button click handlers are registered
    # Fixes button clicks not working in WSLg/GLMakie
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).mousebutton) do event
        # Do nothing - just activates event handling for the figure
    end
    
    # Contour extraction using boundary detection
    function extract_contours(mask)
        # Find boundary pixels (pixels adjacent to background)
        h, w = Base.size(mask)
        contour_points = Tuple{Int, Int}[]
        
        for i in 1:h
            for j in 1:w
                if mask[i, j]
                    is_boundary = false
                    
                    # Check 4-connected neighbors (up, down, left, right)
                    for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
                        ni, nj = i + di, j + dj
                        if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                            is_boundary = true
                            break
                        end
                    end
                    
                    if is_boundary
                        push!(contour_points, (i, j))
                    end
                end
            end
        end
        
        return contour_points
    end
    
    # Helper functions for region selection
    
    # Convert axis coordinates to image pixel coordinates
    # Input axis shows rotr90(image), so need to reverse transform
    function axis_to_pixel(point_axis, img_height, img_width)
        # rotr90 rotates 90 degrees clockwise
        # Original image is H×W (height × width)
        # After rotr90, it becomes W×H (cols become rows, rows become cols)
        # 
        # Forward transform: rotated[orig_col, H - orig_row + 1] = original[orig_row, orig_col]
        # Inverse transform: 
        #   orig_row = H - rot_col + 1
        #   orig_col = rot_row
        #
        # point_axis is in rotated space: (rot_row, rot_col)
        # which corresponds to (x, y) in axis coordinates
        rot_row = round(Int, point_axis[1])
        rot_col = round(Int, point_axis[2])
        
        # Convert to original image coordinates
        orig_row = img_height - rot_col + 1
        orig_col = rot_row
        
        return (orig_row, orig_col)
    end
    
    # Create rectangle polygon from two corners
    function make_rectangle(c1, c2)
        x_min, x_max = minmax(c1[1], c2[1])
        y_min, y_max = minmax(c1[2], c2[2])
        return Bas3GLMakie.GLMakie.Point2f[
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min)  # Close the loop
        ]
    end
    
    # Create rotated rectangle polygon from two corners and rotation angle
    function make_rotated_rectangle(c1, c2, angle_degrees::Float64)
        # Get base rectangle corners (before rotation)
        x_min, x_max = minmax(c1[1], c2[1])
        y_min, y_max = minmax(c1[2], c2[2])
        
        # Calculate center point
        center_x = (x_min + x_max) / 2
        center_y = (y_min + y_max) / 2
        
        # Define corners relative to center
        corners = [
            (x_min - center_x, y_min - center_y),
            (x_max - center_x, y_min - center_y),
            (x_max - center_x, y_max - center_y),
            (x_min - center_x, y_max - center_y)
        ]
        
        # Convert angle to radians
        angle_rad = deg2rad(angle_degrees)
        cos_a = cos(angle_rad)
        sin_a = sin(angle_rad)
        
        # Rotate corners around center
        rotated_corners = map(corners) do (x, y)
            rotated_x = x * cos_a - y * sin_a + center_x
            rotated_y = x * sin_a + y * cos_a + center_y
            Bas3GLMakie.GLMakie.Point2f(rotated_x, rotated_y)
        end
        
        # Close the loop
        push!(rotated_corners, rotated_corners[1])
        
        return rotated_corners
    end
    
    # Get axis-aligned bounding box from rotated rectangle corners for region extraction
    function get_rotated_rect_bounds(c1, c2, angle_degrees::Float64)
        # Get rotated corners (without closing point)
        rotated_rect = make_rotated_rectangle(c1, c2, angle_degrees)
        pop!(rotated_rect)  # Remove closing point
        
        # Find min/max of rotated corners
        x_coords = [p[1] for p in rotated_rect]
        y_coords = [p[2] for p in rotated_rect]
        
        return (minimum(x_coords), maximum(x_coords), minimum(y_coords), maximum(y_coords))
    end
    
    # Helper function to calculate selection region - single source of truth
    function calculate_selection_region(img, corner1, corner2, angle_degrees::Float64)
        local img_data = data(img)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        
        # IMPORTANT: corner1 and corner2 are in (row, col) format from axis_to_pixel()
        # But get_rotated_rect_bounds() expects (x, y) format where x=col, y=row
        # So we need to swap: (row, col) -> (col, row) aka (x, y)
        local c1_xy = (corner1[2], corner1[1])  # (row, col) -> (x, y) = (col, row)
        local c2_xy = (corner2[2], corner2[1])  # (row, col) -> (x, y) = (col, row)
        
        # Get bounding box of rotated rectangle in (x, y) space
        local min_x, max_x, min_y, max_y = get_rotated_rect_bounds(c1_xy, c2_xy, angle_degrees)
        
        # Convert to pixel indices (clamp to image bounds)
        # min_x/max_x are column coordinates, min_y/max_y are row coordinates
        local col_start = max(1, floor(Int, min_x))
        local col_end = min(w, ceil(Int, max_x))
        local row_start = max(1, floor(Int, min_y))
        local row_end = min(h, ceil(Int, max_y))
        
        @info "[REGION-CALC] angle=$(angle_degrees)° → rows=$(row_start):$(row_end), cols=$(col_start):$(col_end)"
        
        return (row_start:row_end, col_start:col_end)
    end
    
    # Note: White region extraction removed - now using only detect_calibration_markers() for consistency
    # The white overlay will be created from the detected markers
    
    # Helper function to create marker visualization image
    function create_marker_visualization(img, markers)
        # Get image dimensions
        local img_data = data(img)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        
        # Create a grayscale visualization showing detected markers
        local viz = zeros(Bas3ImageSegmentation.RGB{Float32}, h, w)
        
        # Only show the best marker (largest one - first in sorted list)
        # Each image should have only one marker
        if !isempty(markers)
            local best_marker = markers[1]  # Markers are sorted by size (largest first)
            # Fill marker region with white
            viz[best_marker.mask] .= Bas3ImageSegmentation.RGB{Float32}(1.0f0, 1.0f0, 1.0f0)
        end
        
        # Overlay will be drawn separately with scatter and lines
        return rotr90(viz)
    end
    
    # Helper function to extract and rotate closeup region from marker bounding box
    function extract_closeup_region(img, markers, rotation_degrees::Float64)
        """
        Extracts the detected marker region using axis-aligned bounding box (AABB) in original space.
        
        Uses a simple two-step process:
        1. Find AABB of masked pixels in original image space
        2. Extract rectangle and rotate by (pca_angle + user_rotation)
        
        This ensures:
        - User rotation is relative to original detected orientation
        - rotation=0° shows marker at original angle
        - rotation=-pca_angle shows horizontal (smallest canvas for nearly-horizontal markers)
        - Predictable canvas behavior: rotating toward horizontal reduces size
        
        Trade-off: AABB may include corner pixels if marker is tilted, resulting in
        slightly larger base canvas than PCA-aligned extraction. However, this "waste"
        is recovered when user rotates toward horizontal, and the behavior is more intuitive.
        """
        
        println("[CLOSEUP-EXTRACT] Called with $(length(markers)) markers, user_rotation=$(rotation_degrees)°")
        
        # Return placeholder if no markers
        if isempty(markers)
            println("[CLOSEUP-EXTRACT] No markers - returning gray placeholder")
            return fill(Bas3ImageSegmentation.RGB{Float32}(0.5f0, 0.5f0, 0.5f0), 100, 100)
        end
        
        local best_marker = markers[1]
        local mask = best_marker.mask
        local pca_angle_rad = best_marker.angle  # PCA angle from detection (RADIANS)
        local pca_angle = rad2deg(pca_angle_rad)  # Convert to degrees immediately
        
        # Get image data in original space
        local img_data = data(img)  # H×W×3 (756×1008×3)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        
        println("[CLOSEUP-EXTRACT] Extracting from mask with size=$(size(mask)), image size=($h, $w)")
        println("[CLOSEUP-EXTRACT] PCA angle from detection: $(round(pca_angle, digits=2))° ($(round(pca_angle_rad, digits=4)) rad) - extracting at detected angle")
        
        # Find all masked pixels
        local masked_coords = findall(mask)
        
        if isempty(masked_coords)
            println("[CLOSEUP-EXTRACT] Empty mask - returning gray placeholder")
            return fill(Bas3ImageSegmentation.RGB{Float32}(0.5f0, 0.5f0, 0.5f0), 100, 100)
        end
        
        # Extract using OBB corners directly (the magenta box)
        # This gives us the exact tight bounding box calculated from PCA
        println("[CLOSEUP-EXTRACT] Extracting OBB using pre-computed corners")
        
        # Parse OBB corners from marker
        local corners = best_marker.corners  # [r1,c1, r2,c2, r3,c3, r4,c4]
        if length(corners) != 8
            println("[CLOSEUP-EXTRACT] ERROR: Invalid corners data, length=$(length(corners))")
            return fill(Bas3ImageSegmentation.RGB{Float32}(0.5f0, 0.5f0, 0.5f0), 100, 100)
        end
        
        local c1 = (corners[1], corners[2])  # (row, col)
        local c2 = (corners[3], corners[4])
        local c3 = (corners[5], corners[6])
        local c4 = (corners[7], corners[8])
        
        println("[CLOSEUP-EXTRACT] OBB corners: c1=$(round.(c1, digits=1)), c2=$(round.(c2, digits=1)), c3=$(round.(c3, digits=1)), c4=$(round.(c4, digits=1))")
        
        # Calculate OBB dimensions from corners
        local edge_12 = sqrt((c2[1] - c1[1])^2 + (c2[2] - c1[2])^2)
        local edge_23 = sqrt((c3[1] - c2[1])^2 + (c3[2] - c2[2])^2)
        
        # Width is the longer edge, height is the shorter edge
        local obb_width = max(edge_12, edge_23)
        local obb_height = min(edge_12, edge_23)
        
        # Determine which edge is the long axis
        local long_axis_is_12 = edge_12 > edge_23
        
        println("[CLOSEUP-EXTRACT] OBB dimensions: $(round(obb_width, digits=1))×$(round(obb_height, digits=1)) (area=$(round(obb_width * obb_height, digits=0)))")
        
        # Calculate OBB orientation (angle of long axis)
        local obb_angle_rad = if long_axis_is_12
            atan(c2[1] - c1[1], c2[2] - c1[2])  # Angle from c1 to c2
        else
            atan(c3[1] - c2[1], c3[2] - c2[2])  # Angle from c2 to c3
        end
        local obb_angle_deg = rad2deg(obb_angle_rad)
        
        println("[CLOSEUP-EXTRACT] OBB orientation: $(round(obb_angle_deg, digits=2))° (should match PCA angle $(round(pca_angle, digits=2))°)")
        
        # Get centroid
        local centroid_r = best_marker.centroid[1]
        local centroid_c = best_marker.centroid[2]
        
        # Create output canvas at detected angle (no rotation yet)
        local height = Int(round(obb_height))
        local width = Int(round(obb_width))
        local closeup = fill(Float32(0.5), height, width, 3)  # Gray background
        
        println("[CLOSEUP-EXTRACT] Extracting $(height)×$(width) canvas at detected angle")
        
        # Calculate basis vectors from OBB edges
        # These define the coordinate system of the rotated rectangle
        if long_axis_is_12
            # Width axis (horizontal in output) = c1→c2 direction (normalized)
            local width_vec_r = (c2[1] - c1[1]) / edge_12
            local width_vec_c = (c2[2] - c1[2]) / edge_12
            # Height axis (vertical in output) = c3→c2 direction (REVERSED to fix mirroring)
            local height_vec_r = (c2[1] - c3[1]) / edge_23
            local height_vec_c = (c2[2] - c3[2]) / edge_23
        else
            # Width axis = c2→c3 direction
            local width_vec_r = (c3[1] - c2[1]) / edge_23
            local width_vec_c = (c3[2] - c2[2]) / edge_23
            # Height axis = c2→c1 direction (REVERSED to fix mirroring)
            local height_vec_r = (c1[1] - c2[1]) / edge_12
            local height_vec_c = (c1[2] - c2[2]) / edge_12
        end
        
        println("[CLOSEUP-EXTRACT] OBB basis vectors:")
        println("  Width axis: ($(round(width_vec_r, digits=3)), $(round(width_vec_c, digits=3)))")
        println("  Height axis: ($(round(height_vec_r, digits=3)), $(round(height_vec_c, digits=3)))")
        
        # Bilinear interpolation helper with mask checking
        function sample_bilinear_masked(img::Array{Float32,3}, mask::BitMatrix, r::Float64, c::Float64)
            local h_img, w_img = Base.size(img, 1), Base.size(img, 2)
            
            # Clamp to image bounds
            if r < 1 || r > h_img || c < 1 || c > w_img
                return (0.5f0, 0.5f0, 0.5f0)  # Gray for out of bounds
            end
            
            # Get integer coordinates for mask check
            local r_check = round(Int, clamp(r, 1, h_img))
            local c_check = round(Int, clamp(c, 1, w_img))
            
            # Check if this pixel is in the ruler mask
            if !mask[r_check, c_check]
                return (0.5f0, 0.5f0, 0.5f0)  # Gray for non-ruler pixels
            end
            
            # Get integer and fractional parts
            local r0 = floor(Int, r)
            local c0 = floor(Int, c)
            local r1 = min(r0 + 1, h_img)
            local c1 = min(c0 + 1, w_img)
            local fr = r - r0
            local fc = c - c0
            
            # Bilinear weights
            local w00 = (1 - fr) * (1 - fc)
            local w01 = (1 - fr) * fc
            local w10 = fr * (1 - fc)
            local w11 = fr * fc
            
            # Sample RGB channels
            return (
                Float32(w00 * img[r0, c0, 1] + w01 * img[r0, c1, 1] + w10 * img[r1, c0, 1] + w11 * img[r1, c1, 1]),
                Float32(w00 * img[r0, c0, 2] + w01 * img[r0, c1, 2] + w10 * img[r1, c0, 2] + w11 * img[r1, c1, 2]),
                Float32(w00 * img[r0, c0, 3] + w01 * img[r0, c1, 3] + w10 * img[r1, c0, 3] + w11 * img[r1, c1, 3])
            )
        end
        
        # Extract OBB by sampling from original image using basis vectors
        local pixel_count = 0
        local masked_pixel_count = 0
        for out_r in 1:height
            for out_c in 1:width
                # Map to OBB local coordinates (centered at origin)
                local local_r = out_r - height / 2.0
                local local_c = out_c - width / 2.0
                
                # Transform using OBB basis vectors
                # img_coords = centroid + local_c * width_vec + local_r * height_vec
                local img_r = centroid_r + local_c * width_vec_r + local_r * height_vec_r
                local img_c = centroid_c + local_c * width_vec_c + local_r * height_vec_c
                
                # Sample with bilinear interpolation and mask checking
                local rgb = sample_bilinear_masked(img_data, mask, img_r, img_c)
                closeup[out_r, out_c, 1] = rgb[1]
                closeup[out_r, out_c, 2] = rgb[2]
                closeup[out_r, out_c, 3] = rgb[3]
                
                # Count sampled pixels
                pixel_count += 1
                if rgb[1] != 0.5f0 || rgb[2] != 0.5f0 || rgb[3] != 0.5f0
                    masked_pixel_count += 1
                end
            end
        end
        
        println("[CLOSEUP-EXTRACT] Sampled $(pixel_count) total pixels, $(masked_pixel_count) ruler pixels ($(round(100*masked_pixel_count/pixel_count, digits=1))% fill)")
        
        # Apply user rotation from detected angle
        # Semantic: rotation=0° shows marker at detected angle (as extracted from OBB)
        # - rotation=0° shows marker at original detected angle (~17.6° tilt)
        # - rotation=-pca_angle rotates to horizontal
        # - rotation > 0 rotates clockwise from detected angle
        # - rotation < 0 rotates counter-clockwise from detected angle
        local total_rotation = rotation_degrees
        local final_data = closeup
        
        if abs(total_rotation) > 0.1
            println("[CLOSEUP-EXTRACT] Applying rotation: $(rotation_degrees)° from detected angle")
            final_data = rotate_image_continuous(closeup, total_rotation)
            println("[CLOSEUP-EXTRACT] After rotation: $(size(final_data))")
        else
            println("[CLOSEUP-EXTRACT] No rotation applied (showing at detected angle)")
        end
        
        # Convert to RGB matrix
        local rgb_matrix = convert_to_rgb_matrix(final_data)
        
        # Apply display rotation (rotr90) to match the red overlay transformation
        println("[CLOSEUP-EXTRACT] Applying rotr90 to match display coordinate space")
        return rotr90(rgb_matrix)
    end
    
    # Helper function to rotate image data by any angle with bilinear interpolation
    function rotate_image_continuous(img_data, angle_degrees::Float64)
        """
        Rotates image by any angle using bilinear interpolation.
        
        Args:
            img_data: H×W×C array (Float32)
            angle_degrees: Rotation angle in degrees (positive = clockwise)
            
        Returns:
            Rotated image with same center, potentially larger dimensions
        """
        # Quick path for no rotation
        if abs(angle_degrees) < 0.1
            return img_data
        end
        
        local h, w, c = size(img_data)
        local center_y = (h + 1) / 2.0
        local center_x = (w + 1) / 2.0
        
        # Convert angle to radians (clockwise rotation)
        local angle_rad = -deg2rad(angle_degrees)  # Negative for clockwise
        local cos_a = cos(angle_rad)
        local sin_a = sin(angle_rad)
        
        # Calculate new dimensions to fit entire rotated image
        local corners_y = [1.0, 1.0, Float64(h), Float64(h)]
        local corners_x = [1.0, Float64(w), 1.0, Float64(w)]
        local rotated_corners_y = Float64[]
        local rotated_corners_x = Float64[]
        
        for i in 1:4
            local dy = corners_y[i] - center_y
            local dx = corners_x[i] - center_x
            local new_y = dy * cos_a - dx * sin_a + center_y
            local new_x = dy * sin_a + dx * cos_a + center_x
            push!(rotated_corners_y, new_y)
            push!(rotated_corners_x, new_x)
        end
        
        local new_h = ceil(Int, maximum(rotated_corners_y) - minimum(rotated_corners_y)) + 1
        local new_w = ceil(Int, maximum(rotated_corners_x) - minimum(rotated_corners_x)) + 1
        local new_center_y = (new_h + 1) / 2.0
        local new_center_x = (new_w + 1) / 2.0
        
        println("[ROTATE] Input: $(h)×$(w)×$(c), angle=$(angle_degrees)°, output: $(new_h)×$(new_w)")
        
        # Create output array with gray background
        local rotated = fill(Float32(0.5), new_h, new_w, c)
        
        # Reverse rotation matrix (to find source coordinates from destination)
        local cos_a_inv = cos(-angle_rad)
        local sin_a_inv = sin(-angle_rad)
        
        # For each output pixel, find corresponding source pixel
        for out_y in 1:new_h
            for out_x in 1:new_w
                # Translate to centered coordinates
                local dy = out_y - new_center_y
                local dx = out_x - new_center_x
                
                # Rotate back to source coordinates
                local src_y = dy * cos_a_inv - dx * sin_a_inv + center_y
                local src_x = dy * sin_a_inv + dx * cos_a_inv + center_x
                
                # Bilinear interpolation if within source bounds
                if src_y >= 1.0 && src_y <= h && src_x >= 1.0 && src_x <= w
                    local y0 = floor(Int, src_y)
                    local x0 = floor(Int, src_x)
                    local y1 = min(y0 + 1, h)
                    local x1 = min(x0 + 1, w)
                    
                    local fy = src_y - y0
                    local fx = src_x - x0
                    
                    # Bilinear weights
                    local w00 = (1 - fx) * (1 - fy)
                    local w10 = fx * (1 - fy)
                    local w01 = (1 - fx) * fy
                    local w11 = fx * fy
                    
                    # Interpolate each channel
                    for ch in 1:c
                        rotated[out_y, out_x, ch] = Float32(
                            w00 * img_data[y0, x0, ch] +
                            w10 * img_data[y0, x1, ch] +
                            w01 * img_data[y1, x0, ch] +
                            w11 * img_data[y1, x1, ch]
                        )
                    end
                end
            end
        end
        
        return rotated
    end
    
    # Helper to rotate 3D array 90° clockwise
    function rotr90_3d(img_data)
        local h, w, c = size(img_data)
        local rotated = zeros(Float32, w, h, c)
        for i in 1:h
            for j in 1:w
                for ch in 1:c
                    rotated[j, h - i + 1, ch] = img_data[i, j, ch]
                end
            end
        end
        return rotated
    end
    
    # Helper to rotate 3D array 90° counter-clockwise
    function rotl90_3d(img_data)
        local h, w, c = size(img_data)
        local rotated = zeros(Float32, w, h, c)
        for i in 1:h
            for j in 1:w
                for ch in 1:c
                    rotated[w - j + 1, i, ch] = img_data[i, j, ch]
                end
            end
        end
        return rotated
    end
    
    # Helper function to convert 3D array (H×W×3) to 2D RGB matrix
    function convert_to_rgb_matrix(img_data)
        """
        Converts a 3D array (height × width × 3) to a 2D matrix of RGB values
        """
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        local rgb_matrix = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h, w)
        
        for i in 1:h
            for j in 1:w
                rgb_matrix[i, j] = Bas3ImageSegmentation.RGB{Float32}(
                    img_data[i, j, 1],  # R
                    img_data[i, j, 2],  # G
                    img_data[i, j, 3]   # B
                )
            end
        end
        
        return rgb_matrix
    end
    
    # Check if a point is inside a rotated rectangle defined by c1, c2, angle
    function point_in_rotated_rect(point, c1, c2, angle_degrees::Float64)
        # Get rectangle bounds
        x_min, x_max = minmax(c1[1], c2[1])
        y_min, y_max = minmax(c1[2], c2[2])

        # Center
        center_x = (x_min + x_max) / 2
        center_y = (y_min + y_max) / 2

        # Translate point to center at origin
        px = point[2] - center_x  # point is (row, col), so x is col
        py = point[1] - center_y  # y is row

        # Rotate back by -angle
        angle_rad = -deg2rad(angle_degrees)
        cos_a = cos(angle_rad)
        sin_a = sin(angle_rad)

        rx = px * cos_a - py * sin_a
        ry = px * sin_a + py * cos_a

        # Check if in axis-aligned rectangle
        return (x_min - center_x) <= rx <= (x_max - center_x) &&
               (y_min - center_y) <= ry <= (y_max - center_y)
    end

    # Helper function to detect markers using extract_white_mask (single best component with weighted scoring)
    function detect_markers_only(img, params)
        try
            # Check if we have rotation parameters for creating a rotated region mask
            local region_param = params[:region]
            local rotated_mask = nothing
            
            if !isnothing(region_param) && haskey(params, :angle) && haskey(params, :c1) && haskey(params, :c2)
                # We have rotation info - create a rotated region mask instead of axis-aligned box
                local angle = params[:angle]
                if angle != 0.0  # Only apply rotation mask if actually rotated
                    local img_data = data(img)
                    local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
                    local c1 = params[:c1]
                    local c2 = params[:c2]
                    
                    # Get axis-aligned bounding box to limit the search area
                    local r_min, r_max, c_min, c_max = region_param
                    
                    # IMPORTANT: c1 and c2 are in (row, col) format from axis_to_pixel()
                    # point_in_rotated_rect expects corners in (x, y) = (col, row) format
                    # When we swap coordinates, we also need to negate the angle to maintain rotation direction
                    local c1_xy = (c1[2], c1[1])  # (row, col) -> (col, row) = (x, y)
                    local c2_xy = (c2[2], c2[1])  # (row, col) -> (col, row) = (x, y)
                    local angle_corrected = -angle  # Negate angle due to coordinate swap
                    
                    # Create mask for pixels inside the rotated rectangle (only check within bounding box)
                    rotated_mask = falses(h, w)
                    for r in r_min:r_max
                        for c in c_min:c_max
                            if point_in_rotated_rect((r, c), c1_xy, c2_xy, angle_corrected)
                                rotated_mask[r, c] = true
                            end
                        end
                    end
                    
                    local rotated_mask_count = sum(rotated_mask)
                    println("[DETECT-MARKERS] Created rotated region mask with angle=$(angle)°, bounding box: rows=$(r_min):$(r_max), cols=$(c_min):$(c_max), mask_pixels=$(rotated_mask_count)")
                end
            end
            
            # Use extract_white_mask to find the single best component with weighted scoring
            # This uses: (1-weight) * density + weight * aspect_ratio_score
            # Support adaptive thresholding if parameters are provided
            local adaptive_enabled = get(params, :adaptive, false)
            local adaptive_window = get(params, :adaptive_window, 25)
            local adaptive_offset = get(params, :adaptive_offset, 0.1)
            local threshold_upper = get(params, :threshold_upper, 1.0)
            
            local mask, size, percentage, num_components, density, corners, angle, aspect_ratio = 
                extract_white_mask(img;
                    threshold=params[:threshold],
                    threshold_upper=threshold_upper,
                    min_component_area=params[:min_area],
                    preferred_aspect_ratio=params[:aspect_ratio],
                    aspect_ratio_weight=params[:aspect_ratio_weight],
                    kernel_size=params[:kernel_size],
                    region=region_param,
                    region_mask=rotated_mask,
                    adaptive=adaptive_enabled,
                    adaptive_window=adaptive_window,
                    adaptive_offset=adaptive_offset)

            # Convert extract_white_mask output to MarkerInfo format
            local markers = MarkerInfo[]
            if size > 0 && !isempty(corners)
                # Calculate centroid from mask
                local pixel_coords = findall(mask)
                if !isempty(pixel_coords)
                    local centroid_row = mean(Float64[p[1] for p in pixel_coords])
                    local centroid_col = mean(Float64[p[2] for p in pixel_coords])
                    
                    # Create MarkerInfo struct
                    local marker = MarkerInfo(
                        (centroid_row, centroid_col),
                        corners,
                        mask,
                        size,
                        angle,
                        aspect_ratio,
                        density
                    )
                    push!(markers, marker)
                end
            end

            # Provide detailed feedback about detection results
            if isempty(markers)
                local region_text = isnothing(params[:region]) ? "full image" : "selected region"
                local msg = "⚠️ No marker found in $region_text (found $num_components components total, try adjusting parameters)"
                return markers, false, msg
            else
                local score_info = "density=$(round(density, digits=3)), aspect=$(round(aspect_ratio, digits=2))"
                local message = "✓ Detected best marker: $score_info (from $num_components total components)"
                return markers, true, message
            end
        catch e
            # Provide specific error information
            local error_msg = "❌ Error: $(typeof(e)) - $(sprint(showerror, e))"
            return MarkerInfo[], false, error_msg
        end
    end
    
    # Initial marker detection with weighted scoring parameters
    # Adaptive thresholding disabled by default, can be enabled via params
    local init_params = Dict(:threshold => 0.7, :threshold_upper => 1.0, :min_area => 8000, :aspect_ratio => 5.0, :aspect_ratio_weight => 0.6, :kernel_size => 3, :region => nothing, :adaptive => false, :adaptive_window => 25, :adaptive_offset => 0.1)
    local init_markers, init_success, init_message = detect_markers_only(sets[1][1], init_params)
    local init_marker_viz = create_marker_visualization(sets[1][1], init_markers)
    
    # Helper function to create RGBA overlay from MarkerInfo (uses only the best/first marker)
    function create_white_overlay(img, markers)
        # Get image dimensions
        local img_data = data(img)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        
        # Create RGBA overlay: red with 70% opacity for marker regions, transparent elsewhere
        local overlay = fill(Bas3ImageSegmentation.RGBA{Float32}(0.0f0, 0.0f0, 0.0f0, 0.0f0), h, w)
        
        # Only show the best marker (largest one - first in sorted list)
        if !isempty(markers)
            local best_marker = markers[1]
            
            # Fill marker region with red at 70% opacity
            for idx in findall(best_marker.mask)
                overlay[idx] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 0.0f0, 0.0f0, 0.7f0)
            end
            
            # Extract contours from the marker mask
            local contours = extract_contours(best_marker.mask)
            
            # Draw contours in bright yellow for better visibility
            for (i, j) in contours
                overlay[i, j] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 1.0f0, 0.0f0, 1.0f0)
            end
            
            # Draw rotated bounding box in magenta using the marker's corner information
            if !isempty(best_marker.corners) && length(best_marker.corners) >= 8
                # Extract 4 corners from the flat array
                local corners = [
                    (best_marker.corners[1], best_marker.corners[2]),
                    (best_marker.corners[3], best_marker.corners[4]),
                    (best_marker.corners[5], best_marker.corners[6]),
                    (best_marker.corners[7], best_marker.corners[8])
                ]
                
                # Draw lines between consecutive corners
                for i in 1:4
                    local next_i = (i % 4) + 1
                    local r1, c1 = corners[i]
                    local r2, c2 = corners[next_i]
                    
                    # Simple line drawing using interpolation
                    local steps = max(abs(r2 - r1), abs(c2 - c1))
                    if steps > 0
                        for step in 0:Int(ceil(steps))
                            local t = step / steps
                            local r = Int(round(r1 + t * (r2 - r1)))
                            local c = Int(round(c1 + t * (c2 - c1)))
                            if r >= 1 && r <= h && c >= 1 && c <= w
                                overlay[r, c] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 0.0f0, 1.0f0, 1.0f0)
                            end
                        end
                    end
                end
            end
        end
        
        return rotr90(overlay)
    end
    
    # Function to extract rotated bounding boxes for all classes in an image
    function extract_class_bboxes(output_image)
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
    
    # Compute channel statistics for white regions only
    function compute_white_region_channel_stats(image, white_mask)
        # Extract RGB data - use data() to get raw array, then permute to (channels, height, width)
        raw_data = data(image)  # Returns (height, width, 3)
        rgb_data = permutedims(raw_data, (3, 1, 2))  # Convert to (3, height, width)
        
        # Initialize result dictionaries
        stats = Dict{Symbol, Dict{Symbol, Float64}}()
        
        # Get channel names
        channel_names = if Base.size(rgb_data, 1) == 3
            [:red, :green, :blue]
        else
            error("Image must have 3 color channels (RGB)")
        end
        
        # Count white pixels
        white_pixel_count = sum(white_mask)
        
        if white_pixel_count == 0
            # No white pixels - return zeros
            for (i, ch) in enumerate(channel_names)
                stats[ch] = Dict(:mean => 0.0, :std => 0.0, :skewness => 0.0)
            end
            return stats, 0
        end
        
        # Extract white pixel values for each channel
        for (i, ch) in enumerate(channel_names)
            channel_data = rgb_data[i, :, :]
            white_values = channel_data[white_mask]
            
            # Compute statistics
            ch_mean = mean(white_values)
            ch_std = std(white_values)
            
            # Compute skewness manually
            n = length(white_values)
            if n > 2 && ch_std > 0
                centered = white_values .- ch_mean
                m3 = sum(centered .^ 3) / n
                ch_skewness = m3 / (ch_std ^ 3)
            else
                ch_skewness = 0.0
            end
            
            stats[ch] = Dict(
                :mean => ch_mean,
                :std => ch_std,
                :skewness => ch_skewness
            )
        end
        
        return stats, white_pixel_count
    end
    
    # Display initial input and output images using the image() function
    local current_input_image = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][1])))
    local current_output_image = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][2])))
    local current_white_overlay = Bas3GLMakie.GLMakie.Observable(create_white_overlay(sets[1][1], init_markers))
    local current_class_bboxes = Bas3GLMakie.GLMakie.Observable(extract_class_bboxes(sets[1][2]))
    
    # Observables for marker visualization
    local current_marker_viz = Bas3GLMakie.GLMakie.Observable(init_marker_viz)
    local current_markers = Bas3GLMakie.GLMakie.Observable(init_markers)
    local marker_success = Bas3GLMakie.GLMakie.Observable(init_success)
    local marker_message = Bas3GLMakie.GLMakie.Observable(init_message)
    
    # Observables for closeup view
    local closeup_rotation = Bas3GLMakie.GLMakie.Observable(0.0)
    # Use main detection markers for closeup (single source of truth)
    local init_closeup = extract_closeup_region(sets[1][1], init_markers, 0.0)
    local current_closeup_image = Bas3GLMakie.GLMakie.Observable(init_closeup)
    
    # Track current image index (fixes crashes when navigating between images)
    local current_image_index = Bas3GLMakie.GLMakie.Observable(1)
    
    # Region selection observables
    local selection_active = Bas3GLMakie.GLMakie.Observable(false)
    local selection_corner1 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    local selection_corner2 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    local selection_complete = Bas3GLMakie.GLMakie.Observable(false)
    local selection_rotation = Bas3GLMakie.GLMakie.Observable(0.0)  # Rotation angle in degrees
    local selection_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    local preview_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    
    # Flag to prevent recursive callback triggering
    local updating_from_button = Ref(false)
    local updating_textboxes = Ref(false)
    
    # Helper function to update textbox (both stored and displayed strings)
    function set_textbox_value(textbox, value::String)
        textbox.stored_string[] = value
        textbox.displayed_string[] = value
    end
    
    # Helper function to rerun marker detection on current selection
    function rerun_selection_detection()
        println("[RERUN-DETECTION] Called")
        if !selection_complete[]
            println("[RERUN-DETECTION] Skipping - no selection complete")
            return  # No selection to process
        end
        
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx === nothing || current_idx < 1 || current_idx > length(sets)
            return
        end
        
        # Get parameters
        threshold = tryparse(Float64, threshold_textbox.stored_string[])
        threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
        min_area = tryparse(Int, min_area_textbox.stored_string[])
        aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
        aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
        kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
        adaptive = adaptive_toggle.active[]
        adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
        adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
        angle = tryparse(Float64, rotation_textbox.stored_string[])
        println("[AUTO-UPDATE] Using parameters: threshold=$threshold-$threshold_upper, min_area=$min_area, aspect_ratio=$aspect_ratio, kernel=$kernel_size, adaptive=$adaptive")
        
        if threshold === nothing || threshold_upper === nothing || min_area === nothing || aspect_ratio === nothing || 
           aspect_weight === nothing || kernel_size === nothing || angle === nothing || 
           adaptive_window === nothing || adaptive_offset === nothing
            return
        end
        
        # Get image
        img = sets[current_idx][1]
        img_height = Base.size(data(img), 1)
        img_width = Base.size(data(img), 2)
        
        # Convert selection corners to pixel coordinates
        c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
        c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
        
        # Use shared helper function for consistent region calculation (Path 2: selection changes)
        local row_range, col_range = calculate_selection_region(img, c1_px, c2_px, angle)
        region = (first(row_range), last(row_range), first(col_range), last(col_range))
        println("[AUTO-UPDATE] Running marker detection on region: rows=$(row_range), cols=$(col_range), rotation=$(angle)°")
        
        # Detect markers
        local params = Dict(:threshold => threshold, :threshold_upper => threshold_upper, :min_area => min_area, :aspect_ratio => aspect_ratio, :aspect_ratio_weight => aspect_weight, :kernel_size => kernel_size, :region => region, :c1 => c1_px, :c2 => c2_px, :angle => angle, :adaptive => adaptive, :adaptive_window => adaptive_window, :adaptive_offset => adaptive_offset)
        local markers, success, message = detect_markers_only(img, params)
        
        # Update state and trigger display update
        if !isempty(markers)
            println("[AUTO-UPDATE] Found $(length(markers)) marker(s), success=$(success)")
            current_white_overlay[] = create_white_overlay(img, markers)
            current_marker_viz[] = create_marker_visualization(img, markers)
            current_markers[] = markers
            
            # Update closeup view using same markers as region detection
            local closeup_img = extract_closeup_region(img, markers, closeup_rotation[])
            current_closeup_image[] = closeup_img
            
            println("[AUTO-UPDATE] Setting marker_success=$(success), marker_message=$(message)")
            marker_success[] = success
            marker_message[] = message
            # Trigger bounding box redraw by updating class_bboxes observable
            current_class_bboxes[] = extract_class_bboxes(sets[current_idx][2])
            # Explicitly notify all observables to force display refresh
            Bas3GLMakie.GLMakie.notify(current_white_overlay)
            Bas3GLMakie.GLMakie.notify(current_marker_viz)
            Bas3GLMakie.GLMakie.notify(current_markers)
            Bas3GLMakie.GLMakie.notify(current_class_bboxes)
            Bas3GLMakie.GLMakie.notify(current_closeup_image)
            println("[AUTO-UPDATE] Display refreshed: markers, overlays, bounding boxes, and closeup updated")
        else
            println("[AUTO-UPDATE] No markers found, success=$(success)")
            println("[AUTO-UPDATE] Clearing previous detection results")
            
            # Clear all detection visuals to avoid showing stale results
            img = sets[current_idx][1]
            current_white_overlay[] = create_white_overlay(img, MarkerInfo[])  # Empty overlay
            current_marker_viz[] = create_marker_visualization(img, MarkerInfo[])  # Empty/black image
            current_markers[] = MarkerInfo[]  # Empty list
            
            # Clear closeup view (show placeholder)
            current_closeup_image[] = fill(Bas3GLMakie.GLMakie.RGB{Float32}(0.5, 0.5, 0.5), 100, 100)
            
            # Update status with enhanced message showing rotation angle if applicable
            marker_success[] = false
            if angle != 0.0
                marker_message[] = "⚠️ Keine Marker in rotierter Region gefunden ($(angle)°) - versuchen Sie andere Parameter"
            else
                marker_message[] = message
            end
            
            # Force refresh of all detection-related observables
            Bas3GLMakie.GLMakie.notify(current_white_overlay)
            Bas3GLMakie.GLMakie.notify(current_marker_viz)
            Bas3GLMakie.GLMakie.notify(current_markers)
            Bas3GLMakie.GLMakie.notify(current_closeup_image)
            
            println("[AUTO-UPDATE] Display cleared: no markers in selected region")
        end
    end
    
    # Helper function to update database status label for current image
    function update_database_status(idx)
        (found, row, data) = find_entry_for_image(db_path, idx)
        if found
            db_status_label.text = "Eintrag vom $(data["date"]) (Patient: $(data["patient_id"]))"
            db_status_label.color = :green
        else
            db_status_label.text = "Kein Eintrag vorhanden"
            db_status_label.color = :black
        end
    end
    
    # Helper function to update the image display (core logic without textbox update)
    function update_image_display_internal(idx, threshold=0.7, threshold_upper=1.0, min_component_area=8000, preferred_aspect_ratio=5.0, aspect_ratio_weight=0.6, kernel_size=3, adaptive=false, adaptive_window=25, adaptive_offset=0.1)
        println("[UPDATE] Updating to image $idx with params: threshold=$threshold-$threshold_upper, min_area=$min_component_area, aspect_ratio=$preferred_aspect_ratio, kernel_size=$kernel_size, adaptive=$adaptive")
        
        # Validate the input
        if idx < 1 || idx > length(sets)
            println("[ERROR] Invalid image index: $idx (max: $(length(sets)))")
            textbox_label.text = "Ungültige Eingabe! Geben Sie eine Zahl zwischen 1 und $(length(sets)) ein"
            return false
        end
        
        # Update current image index observable (CRITICAL FIX)
        println("[OBSERVABLE] current_image_index: $(current_image_index[]) -> $idx")
        current_image_index[] = idx
        
        # Update label to show current image
        textbox_label.text = "Bild: $idx / $(length(sets))"
        
        # Get input RGB image (sets[idx][1] is the input image)
        input_img = rotr90(image(sets[idx][1]))
        current_input_image[] = input_img
        
        # Get output segmentation image (sets[idx][2] is the output/ground truth)
        output_img = rotr90(image(sets[idx][2]))
        current_output_image[] = output_img
        
        # Apply region constraint if selection is complete
        local region = nothing
        if selection_complete[]
            img = sets[idx][1]
            img_height = Base.size(data(img), 1)
            img_width = Base.size(data(img), 2)
            
            c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
            c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
            
            # Get rotation angle from textbox (Path 1: parameter changes)
            local rotation_angle = tryparse(Float64, rotation_textbox.stored_string[])
            if rotation_angle === nothing
                rotation_angle = 0.0
            end
            
            # Use shared helper function for consistent region calculation
            local row_range, col_range = calculate_selection_region(img, c1_px, c2_px, rotation_angle)
            region = (first(row_range), last(row_range), first(col_range), last(col_range))
        end
        
        # Extract class bounding boxes
        current_class_bboxes[] = extract_class_bboxes(sets[idx][2])
        
        # Update marker visualization (detection only, no dewarping)
        local params = Dict(:threshold => threshold, :threshold_upper => threshold_upper, :min_area => min_component_area, :aspect_ratio => preferred_aspect_ratio, :aspect_ratio_weight => aspect_ratio_weight, :kernel_size => kernel_size, :region => region, :adaptive => adaptive, :adaptive_window => adaptive_window, :adaptive_offset => adaptive_offset)
        if !isnothing(region)
            params[:c1] = c1_px
            params[:c2] = c2_px
            params[:angle] = rotation_angle
        end
        local markers, success, message = detect_markers_only(sets[idx][1], params)
        
        println("[PARAM-UPDATE] Detection result: markers=$(length(markers)), success=$(success)")
        
        # STATE PRESERVATION: Only update visualization if markers were detected
        # This prevents UI corruption when detection fails
        if !isempty(markers)
            current_marker_viz[] = create_marker_visualization(sets[idx][1], markers)
            current_markers[] = markers
            current_white_overlay[] = create_white_overlay(sets[idx][1], markers)
            
            # Update closeup view using same markers as main detection
            local closeup_img = extract_closeup_region(sets[idx][1], markers, closeup_rotation[])
            current_closeup_image[] = closeup_img
            
            # Explicitly notify visualization observables to force UI refresh
            Bas3GLMakie.GLMakie.notify(current_marker_viz)
            Bas3GLMakie.GLMakie.notify(current_markers)
            Bas3GLMakie.GLMakie.notify(current_white_overlay)
            Bas3GLMakie.GLMakie.notify(current_closeup_image)
        else
            # No markers found - clear detection visuals (both full image and region cases)
            println("[PARAM-UPDATE] Clearing detection results: no markers found")
            current_marker_viz[] = create_marker_visualization(sets[idx][1], MarkerInfo[])
            current_markers[] = MarkerInfo[]
            current_white_overlay[] = create_white_overlay(sets[idx][1], MarkerInfo[])
            
            # Show placeholder in closeup
            current_closeup_image[] = fill(Bas3GLMakie.GLMakie.RGB{Float32}(0.5, 0.5, 0.5), 100, 100)
            
            # Notify after clearing
            Bas3GLMakie.GLMakie.notify(current_marker_viz)
            Bas3GLMakie.GLMakie.notify(current_markers)
            Bas3GLMakie.GLMakie.notify(current_white_overlay)
            Bas3GLMakie.GLMakie.notify(current_closeup_image)
        end
        
        println("[PARAM-UPDATE] Setting marker_success=$(success), marker_message=$(message)")
        marker_success[] = success
        marker_message[] = message
        
        # Compute full-image channel statistics
        local input_img_original = sets[idx][1]  # Original image (not rotated)
        local raw_data = data(input_img_original)  # Returns (height, width, 3)
        local rgb_data = permutedims(raw_data, (3, 1, 2))  # Convert to (3, height, width)
        
        # Full image stats
        local full_r_mean = mean(rgb_data[1, :, :])
        local full_g_mean = mean(rgb_data[2, :, :])
        local full_b_mean = mean(rgb_data[3, :, :])
        
        local full_r_std = std(rgb_data[1, :, :])
        local full_g_std = std(rgb_data[2, :, :])
        local full_b_std = std(rgb_data[3, :, :])
        
        # Compute skewness for full image
        function compute_channel_skewness(channel_data)
            ch_mean = mean(channel_data)
            ch_std = std(channel_data)
            n = length(channel_data)
            if n > 2 && ch_std > 0
                centered = channel_data .- ch_mean
                m3 = sum(centered .^ 3) / n
                return m3 / (ch_std ^ 3)
            else
                return 0.0
            end
        end
        
        local full_r_skew = compute_channel_skewness(rgb_data[1, :, :])
        local full_g_skew = compute_channel_skewness(rgb_data[2, :, :])
        local full_b_skew = compute_channel_skewness(rgb_data[3, :, :])
        
        # Plot full image statistics
        # Clear previous plots
        empty!(full_mean_ax)
        empty!(full_box_ax)
        empty!(full_hist_ax)
        
        # Plot 1: Mean ± Std for full image
        local channel_colors = [:red, :green, :blue]
        local full_means = [full_r_mean, full_g_mean, full_b_mean]
        local full_stds = [full_r_std, full_g_std, full_b_std]
        
        for i in 1:3
            Bas3GLMakie.GLMakie.scatter!(
                full_mean_ax,
                [i],
                [full_means[i]];
                markersize=12,
                color=channel_colors[i],
                marker=:circle
            )
            Bas3GLMakie.GLMakie.errorbars!(
                full_mean_ax,
                [i],
                [full_means[i]],
                [full_stds[i]],
                [full_stds[i]];
                whiskerwidth=10,
                color=channel_colors[i],
                linewidth=2
            )
        end
        
        # Plot 2: Boxplot for full image
        local full_red_values = vec(rgb_data[1, :, :])
        local full_green_values = vec(rgb_data[2, :, :])
        local full_blue_values = vec(rgb_data[3, :, :])
        
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(1, length(full_red_values)),
            full_red_values;
            color=(:red, 0.6),
            show_outliers=true,
            width=0.6
        )
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(2, length(full_green_values)),
            full_green_values;
            color=(:green, 0.6),
            show_outliers=true,
            width=0.6
        )
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(3, length(full_blue_values)),
            full_blue_values;
            color=(:blue, 0.6),
            show_outliers=true,
            width=0.6
        )
        
        # Plot 3: RGB Histogram for full image
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_red_values;
            bins=50,
            color=(:red, 0.5),
            normalization=:pdf,
            label="Red"
        )
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_green_values;
            bins=50,
            color=(:green, 0.5),
            normalization=:pdf,
            label="Green"
        )
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_blue_values;
            bins=50,
            color=(:blue, 0.5),
            normalization=:pdf,
            label="Blue"
        )
        
        # Refresh axis limits for full image plots
        Bas3GLMakie.GLMakie.autolimits!(full_mean_ax)
        Bas3GLMakie.GLMakie.autolimits!(full_box_ax)
        Bas3GLMakie.GLMakie.autolimits!(full_hist_ax)
        
        # Compute marker region channel statistics (using the best marker)
        if !isempty(markers)
            local best_marker = markers[1]
            local marker_mask = best_marker.mask
            local white_stats, white_pixel_count = compute_white_region_channel_stats(input_img_original, marker_mask)
            
            local white_r_mean = white_stats[:red][:mean]
            local white_g_mean = white_stats[:green][:mean]
            local white_b_mean = white_stats[:blue][:mean]
            
            local white_r_std = white_stats[:red][:std]
            local white_g_std = white_stats[:green][:std]
            local white_b_std = white_stats[:blue][:std]
            
            local white_r_skew = white_stats[:red][:skewness]
            local white_g_skew = white_stats[:green][:skewness]
            local white_b_skew = white_stats[:blue][:skewness]
            
            # Extract pixel values for plotting
            local raw_data_plot = data(input_img_original)  # Returns (height, width, 3)
            local rgb_data_plot = permutedims(raw_data_plot, (3, 1, 2))  # Convert to (3, height, width)
            local red_values = rgb_data_plot[1, :, :][marker_mask]
            local green_values = rgb_data_plot[2, :, :][marker_mask]
            local blue_values = rgb_data_plot[3, :, :][marker_mask]
            
            # Clear previous plots
            empty!(region_mean_ax)
            empty!(region_box_ax)
            empty!(region_hist_ax)
            
            # Plot 1: Mean ± Std
            local channel_colors = [:red, :green, :blue]
            local means = [white_r_mean, white_g_mean, white_b_mean]
            local stds = [white_r_std, white_g_std, white_b_std]
            
            for i in 1:3
                Bas3GLMakie.GLMakie.scatter!(
                    region_mean_ax,
                    [i],
                    [means[i]];
                    markersize=12,
                    color=channel_colors[i],
                    marker=:circle
                )
                Bas3GLMakie.GLMakie.errorbars!(
                    region_mean_ax,
                    [i],
                    [means[i]],
                    [stds[i]],
                    [stds[i]];
                    whiskerwidth=10,
                    color=channel_colors[i],
                    linewidth=2
                )
            end
            
            # Plot 2: Boxplot
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(1, length(red_values)),
                red_values;
                color=(:red, 0.6),
                show_outliers=true,
                width=0.6
            )
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(2, length(green_values)),
                green_values;
                color=(:green, 0.6),
                show_outliers=true,
                width=0.6
            )
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(3, length(blue_values)),
                blue_values;
                color=(:blue, 0.6),
                show_outliers=true,
                width=0.6
            )
            
            # Plot 3: RGB Histogram
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                red_values;
                bins=50,
                color=(:red, 0.5),
                normalization=:pdf,
                label="Red"
            )
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                green_values;
                bins=50,
                color=(:green, 0.5),
                normalization=:pdf,
                label="Green"
            )
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                blue_values;
                bins=50,
                color=(:blue, 0.5),
                normalization=:pdf,
                label="Blue"
            )
            
            # Refresh axis limits to update display
            Bas3GLMakie.GLMakie.autolimits!(region_mean_ax)
            Bas3GLMakie.GLMakie.autolimits!(region_box_ax)
            Bas3GLMakie.GLMakie.autolimits!(region_hist_ax)
        end
        
        println("[UPDATE] Successfully updated to image $idx (markers detected: $(length(current_markers[])))")
        
        # Update database status and clear info textbox for new image
        update_database_status(idx)
        info_textbox.stored_string[] = ""
        
        return true
    end
    
    # Update images when textbox value changes
    Bas3GLMakie.GLMakie.on(textbox.stored_string) do str
        # Skip if being updated from button click
        if updating_from_button[]
            println("[NAVIGATION] Skipping textbox callback (button update in progress)")
            return
        end
        
        # Parse the input string to an integer
        idx = tryparse(Int, str)
        
        if idx !== nothing
            println("[NAVIGATION] Textbox changed: $(current_image_index[]) -> $idx")
            
            # Clear region selection when changing images (selection coords are image-specific)
            selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_complete[] = false
            selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            if selection_active[]
                selection_status_label.text = "Klicken Sie auf die untere linke Ecke"
                selection_status_label.color = :blue
            end
            
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            adaptive = adaptive_toggle.active[]
            adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
            adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            threshold_upper = threshold_upper === nothing ? 1.0 : threshold_upper
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            adaptive_window = adaptive_window === nothing ? 25 : adaptive_window
            adaptive_offset = adaptive_offset === nothing ? 0.1 : adaptive_offset
            
            update_image_display_internal(idx, threshold, threshold_upper, min_area, aspect_ratio, aspect_weight, kernel_size, adaptive, adaptive_window, adaptive_offset)
        else
            println("[ERROR] Invalid textbox input: $str")
            textbox_label.text = "Ungültige Eingabe! Geben Sie eine Zahl zwischen 1 und $(length(sets)) ein"
        end
    end
    
    # Previous button callback
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do n
        println("[NAVIGATION] Previous button clicked")
        
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx > 1
            new_idx = current_idx - 1
            println("[NAVIGATION] Going to previous image: $current_idx -> $new_idx")
            
            # Clear region selection when changing images (selection coords are image-specific)
            selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_complete[] = false
            selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            if selection_active[]
                selection_status_label.text = "Klicken Sie auf die untere linke Ecke"
                selection_status_label.color = :blue
            end
            
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            adaptive = adaptive_toggle.active[]
            adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
            adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            threshold_upper = threshold_upper === nothing ? 1.0 : threshold_upper
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            adaptive_window = adaptive_window === nothing ? 25 : adaptive_window
            adaptive_offset = adaptive_offset === nothing ? 0.1 : adaptive_offset
            
            # Update images
            if update_image_display_internal(new_idx, threshold, threshold_upper, min_area, aspect_ratio, aspect_weight, kernel_size, adaptive, adaptive_window, adaptive_offset)
                # Update textbox without triggering callback
                updating_from_button[] = true
                textbox.stored_string[] = string(new_idx)
                updating_from_button[] = false
                println("[NAVIGATION] Successfully updated to image $new_idx")
            else
                println("[ERROR] Failed to update to image $new_idx")
            end
        else
            println("[NAVIGATION] Cannot go to previous image (current_idx=$current_idx)")
        end
    end
    
    # Next button callback
    Bas3GLMakie.GLMakie.on(next_button.clicks) do n
        println("[NAVIGATION] Next button clicked")
        
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx < length(sets)
            new_idx = current_idx + 1
            println("[NAVIGATION] Going to next image: $current_idx -> $new_idx")
            
            # Clear region selection when changing images (selection coords are image-specific)
            selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_complete[] = false
            selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            if selection_active[]
                selection_status_label.text = "Klicken Sie auf die untere linke Ecke"
                selection_status_label.color = :blue
            end
            
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            adaptive = adaptive_toggle.active[]
            adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
            adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            threshold_upper = threshold_upper === nothing ? 1.0 : threshold_upper
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            adaptive_window = adaptive_window === nothing ? 25 : adaptive_window
            adaptive_offset = adaptive_offset === nothing ? 0.1 : adaptive_offset
            
            
            # Update images
            if update_image_display_internal(new_idx, threshold, threshold_upper, min_area, aspect_ratio, aspect_weight, kernel_size, adaptive, adaptive_window, adaptive_offset)
                # Update textbox without triggering callback
                updating_from_button[] = true
                textbox.stored_string[] = string(new_idx)
                updating_from_button[] = false
                println("[NAVIGATION] Successfully updated to image $new_idx")
            else
                println("[ERROR] Failed to update to image $new_idx")
            end
        else
            println("[NAVIGATION] Cannot go to previous image (current_idx=$current_idx)")
        end
    end
    
    # Database save button callback
    Bas3GLMakie.GLMakie.on(save_db_button.clicks) do n
        println("[DATABASE] Save button clicked")
        flush(stdout)
        
        try
            println("[DATABASE] Entering try block...")
            flush(stdout)
            # Get current image index
            current_idx = tryparse(Int, textbox.stored_string[])
            println("[DATABASE] Current index: $current_idx")
            flush(stdout)
            
            if current_idx === nothing || current_idx < 1 || current_idx > length(sets)
                db_status_label.text = "Fehler: Ungültiger Bildindex"
                db_status_label.color = :red
                return
            end
            
            # Get textbox values from displayed_string (current typed value)
            # NOTE: We read from displayed_string (not stored_string) because:
            # - displayed_string = current typed value (what user sees)
            # - stored_string = committed value (requires Enter key press)
            # - Save button should capture current state without requiring Enter
            # - This is consistent with real-time validation which watches displayed_string
            date_str = something(date_textbox.displayed_string[], "")
            patient_id_str = something(patient_id_textbox.displayed_string[], "")
            info_str = something(info_textbox.displayed_string[], "")
            println("[DATABASE] Retrieved values: date='$date_str', patient='$patient_id_str', info='$info_str'")
            flush(stdout)
            
            # Validate date
            println("[DATABASE] Validating date...")
            flush(stdout)
            (valid_date, date_msg) = validate_date(date_str)
            println("[DATABASE] Date validation result: valid=$valid_date, msg='$date_msg'")
            flush(stdout)
            if !valid_date
                db_status_label.text = "Fehler: $date_msg"
                db_status_label.color = :red
                return
            end
            
            # Validate patient ID
            println("[DATABASE] Validating patient ID...")
            flush(stdout)
            (valid_id, id_msg) = validate_patient_id(patient_id_str)
            println("[DATABASE] Patient ID validation result: valid=$valid_id, msg='$id_msg'")
            flush(stdout)
            if !valid_id
                db_status_label.text = "Fehler: $id_msg"
                db_status_label.color = :red
                return
            end
            
            # Validate info
            (valid_info, info_msg) = validate_info(info_str)
            if !valid_info
                db_status_label.text = "Fehler: $info_msg"
                db_status_label.color = :red
                return
            end
            
            # Parse patient ID
            patient_id = parse(Int, patient_id_str)
            
            # Get current image filename (use index-based naming)
            filename = "image_$(lpad(current_idx, 3, '0')).png"
            
            # Check if entry already exists
            (found, row, existing) = find_entry_for_image(db_path, current_idx)
            
            if found
                # Show confirmation for update
                println("[DATABASE] Entry exists for image $current_idx")
                println("  Existing: Date=$(existing["date"]), Patient=$(existing["patient_id"]), Info=$(existing["info"])")
                println("  New: Date=$date_str, Patient=$patient_id, Info=$info_str")
                
                # TODO: In a full implementation, show a proper dialog
                # For now, we'll update directly with a warning message
                db_status_label.text = "Warnung: Eintrag wird aktualisiert..."
                db_status_label.color = :orange
                
                # Update entry
                update_entry(db_path, row, date_str, patient_id, info_str)
                db_status_label.text = "Aktualisiert! Bild $current_idx"
                db_status_label.color = :green
            else
                # Append new entry
                append_entry(db_path, current_idx, filename, date_str, patient_id, info_str)
                db_status_label.text = "Gespeichert! Bild $current_idx"
                db_status_label.color = :green
            end
            
            # Clear info textbox (keep date and patient_id for batch entry)
            info_textbox.stored_string[] = ""
            
            println("[DATABASE] Save completed for image $current_idx")
        catch e
            error_msg = sprint(showerror, e, catch_backtrace())
            println("[DATABASE ERROR] Exception occurred:")
            println(error_msg)
            db_status_label.text = "Fehler: $(typeof(e))"
            db_status_label.color = :red
        end
    end
    
    # Initialize database status for first image
    update_database_status(1)
    
    # Helper function to update white detection with current parameters
    function update_white_detection(source="manual")
        # Parse and validate all parameters
        threshold = tryparse(Float64, threshold_textbox.stored_string[])
        threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
        min_area = tryparse(Int, min_area_textbox.stored_string[])
        aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
        aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
        kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
        adaptive = adaptive_toggle.active[]
        adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
        adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
        
        # Validation checks
        validation_errors = String[]
        
        if threshold === nothing
            push!(validation_errors, "Lower threshold must be a number")
        elseif threshold < 0.0 || threshold > 1.0
            push!(validation_errors, "Lower threshold must be 0.0-1.0")
        end
        
        if threshold_upper === nothing
            push!(validation_errors, "Upper threshold must be a number")
        elseif threshold_upper < 0.0 || threshold_upper > 1.0
            push!(validation_errors, "Upper threshold must be 0.0-1.0")
        elseif threshold !== nothing && threshold_upper < threshold
            push!(validation_errors, "Upper threshold must be >= lower threshold")
        end
        
        if min_area === nothing
            push!(validation_errors, "Min Area must be a number")
        elseif min_area <= 0
            push!(validation_errors, "Min Area must be > 0")
        end
        
        if aspect_ratio === nothing
            push!(validation_errors, "Aspect Ratio must be a number")
        elseif aspect_ratio < 1.0
            push!(validation_errors, "Aspect Ratio must be >= 1.0")
        end
        
        if aspect_weight === nothing
            push!(validation_errors, "Aspect Weight must be a number")
        elseif aspect_weight < 0.0 || aspect_weight > 1.0
            push!(validation_errors, "Aspect Weight must be 0.0-1.0")
        end
        
        if kernel_size === nothing
            push!(validation_errors, "Kernel Size must be a number")
        elseif kernel_size < 0 || kernel_size > 10
            push!(validation_errors, "Kernel Size must be 0-10")
        end
        
        if adaptive_window === nothing
            push!(validation_errors, "Adaptive Window must be a number")
        elseif adaptive_window < 5 || adaptive_window > 51
            push!(validation_errors, "Adaptive Window must be 5-51")
        end
        
        if adaptive_offset === nothing
            push!(validation_errors, "Adaptive Offset must be a number")
        elseif adaptive_offset < 0.0 || adaptive_offset > 1.0
            push!(validation_errors, "Adaptive Offset must be 0.0-1.0")
        end
        
        # If validation fails, show error
        if !isempty(validation_errors)
            param_status_label.text = join(validation_errors, " | ")
            param_status_label.color = :red
            return false
        end
        
        # Get current image index
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx === nothing
            param_status_label.text = "Ungültiger Bildindex"
            param_status_label.color = :red
            return false
        end
        
        # Update the display with new parameters
        if update_image_display_internal(current_idx, threshold, threshold_upper, min_area, aspect_ratio, aspect_weight, kernel_size, adaptive, adaptive_window, adaptive_offset)
            param_status_label.text = "Aktualisiert ($source)"
            param_status_label.color = :green
            return true
        else
            param_status_label.text = "Failed to update"
            param_status_label.color = :red
            return false
        end
    end
    
    # Auto-update when textboxes change
    Bas3GLMakie.GLMakie.on(threshold_textbox.stored_string) do val
        println("[PARAMETER] Lower threshold changed to: $val")
        update_white_detection("lower threshold")
    end
    
    Bas3GLMakie.GLMakie.on(threshold_upper_textbox.stored_string) do val
        println("[PARAMETER] Upper threshold changed to: $val")
        update_white_detection("upper threshold")
    end
    
    Bas3GLMakie.GLMakie.on(min_area_textbox.stored_string) do val
        println("[PARAMETER] Min area changed to: $val")
        update_white_detection("min area")
    end
    
    Bas3GLMakie.GLMakie.on(aspect_ratio_textbox.stored_string) do val
        println("[PARAMETER] Aspect ratio changed to: $val")
        update_white_detection("aspect ratio")
    end
    
    Bas3GLMakie.GLMakie.on(aspect_weight_textbox.stored_string) do val
        println("[PARAMETER] Aspect weight changed to: $val")
        update_white_detection("aspect weight")
    end
    
    Bas3GLMakie.GLMakie.on(kernel_size_textbox.stored_string) do val
        println("[PARAMETER] Kernel size changed to: $val")
        update_white_detection("kernel size")
    end
    
    Bas3GLMakie.GLMakie.on(adaptive_toggle.active) do val
        println("[PARAMETER] Adaptive threshold changed to: $val")
        update_white_detection("adaptive mode")
    end
    
    Bas3GLMakie.GLMakie.on(adaptive_window_textbox.stored_string) do val
        println("[PARAMETER] Adaptive window changed to: $val")
        update_white_detection("adaptive window")
    end
    
    Bas3GLMakie.GLMakie.on(adaptive_offset_textbox.stored_string) do val
        println("[PARAMETER] Adaptive offset changed to: $val")
        update_white_detection("adaptive offset")
    end
    
    # Start selection button callback
    Bas3GLMakie.GLMakie.on(start_selection_button.clicks) do n
        println("[SELECTION] Start selection button clicked")
        
        # Clear any previous selection
        selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_complete[] = false
        selection_rotation[] = 0.0
        rotation_textbox.stored_string[] = "0.0"
        set_textbox_value(x_textbox, "0")
        set_textbox_value(y_textbox, "0")
        set_textbox_value(width_textbox, "0")
        set_textbox_value(height_textbox, "0")
        selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        
        # Activate selection mode
        selection_active[] = true
        selection_status_label.text = "Klicken Sie auf die erste Ecke"
        selection_status_label.color = :blue
        println("[SELECTION] Selection mode activated - waiting for first corner")
    end
    
    # Rotation textbox callback - update rectangle when rotation changes
    Bas3GLMakie.GLMakie.on(rotation_textbox.stored_string) do val
        if selection_complete[]
            angle = tryparse(Float64, val)
            if angle !== nothing
                println("[SELECTION] Rotation changed to: $(angle) degrees")
                selection_rotation[] = angle
                
                # Update rectangle visualization with rotation
                selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                
                # Automatically rerun marker detection
                rerun_selection_detection()
            else
                println("[SELECTION] Invalid rotation angle: $val")
            end
        end
    end
    
    # Closeup rotation callback
    Bas3GLMakie.GLMakie.on(closeup_rotation_textbox.stored_string) do val
        angle = tryparse(Float64, val)
        if angle !== nothing
            println("[CLOSEUP] Rotation changed to: $(angle) degrees")
            closeup_rotation[] = angle
            
            # Regenerate closeup with new rotation using current markers
            current_idx = current_image_index[]
            if current_idx >= 1 && current_idx <= length(sets)
                closeup_img = extract_closeup_region(
                    sets[current_idx][1], 
                    current_markers[],  # Use current markers directly
                    angle
                )
                current_closeup_image[] = closeup_img
                Bas3GLMakie.GLMakie.notify(current_closeup_image)
            end
        else
            println("[CLOSEUP] Invalid rotation angle: $val")
        end
    end
    
    # Position and size textbox callbacks - update selection when edited
    Bas3GLMakie.GLMakie.on(x_textbox.stored_string) do val
        if updating_textboxes[]
            return  # Skip callback during programmatic update
        end
        if selection_complete[]
            center_x = tryparse(Float64, val)
            width_val = tryparse(Float64, width_textbox.stored_string[])
            if center_x !== nothing && width_val !== nothing
                # Keep y and height the same
                y_min = minimum([selection_corner1[][2], selection_corner2[][2]])
                y_max = maximum([selection_corner1[][2], selection_corner2[][2]])
                
                # Update corners from center_x and width
                half_width = width_val / 2
                selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(center_x - half_width, y_min)
                selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(center_x + half_width, y_max)
                
                # Update visualization
                angle = tryparse(Float64, rotation_textbox.stored_string[])
                angle = angle === nothing ? 0.0 : angle
                selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                
                # Update ALL textboxes to stay in sync
                center_y = (y_min + y_max) / 2
                height = y_max - y_min
                updating_textboxes[] = true
                set_textbox_value(y_textbox, string(round(Int, center_y)))
                set_textbox_value(height_textbox, string(round(Int, height)))
                updating_textboxes[] = false
                
                println("[SELECTION] Center X updated to: $center_x")
                
                # Automatically rerun marker detection
                rerun_selection_detection()
            end
        end
    end
    
    Bas3GLMakie.GLMakie.on(y_textbox.stored_string) do val
        if updating_textboxes[]
            return  # Skip callback during programmatic update
        end
        if selection_complete[]
            center_y = tryparse(Float64, val)
            height_val = tryparse(Float64, height_textbox.stored_string[])
            if center_y !== nothing && height_val !== nothing
                # Keep x and width the same
                x_min = minimum([selection_corner1[][1], selection_corner2[][1]])
                x_max = maximum([selection_corner1[][1], selection_corner2[][1]])
                
                # Update corners from center_y and height
                half_height = height_val / 2
                selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(x_min, center_y - half_height)
                selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(x_max, center_y + half_height)
                
                # Update visualization
                angle = tryparse(Float64, rotation_textbox.stored_string[])
                angle = angle === nothing ? 0.0 : angle
                selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                
                # Update ALL textboxes to stay in sync
                center_x = (x_min + x_max) / 2
                width = x_max - x_min
                updating_textboxes[] = true
                set_textbox_value(x_textbox, string(round(Int, center_x)))
                set_textbox_value(width_textbox, string(round(Int, width)))
                updating_textboxes[] = false
                
                println("[SELECTION] Center Y updated to: $center_y")
                
                # Automatically rerun marker detection
                rerun_selection_detection()
            end
        end
    end
    
    Bas3GLMakie.GLMakie.on(width_textbox.stored_string) do val
        if updating_textboxes[]
            return  # Skip callback during programmatic update
        end
        if selection_complete[]
            width_val = tryparse(Float64, val)
            center_x = tryparse(Float64, x_textbox.stored_string[])
            if width_val !== nothing && width_val > 0 && center_x !== nothing
                # Keep center_x and y positions the same
                y_min = minimum([selection_corner1[][2], selection_corner2[][2]])
                y_max = maximum([selection_corner1[][2], selection_corner2[][2]])
                
                # Update corners from center_x and new width
                half_width = width_val / 2
                selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(center_x - half_width, y_min)
                selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(center_x + half_width, y_max)
                
                # Update visualization
                angle = tryparse(Float64, rotation_textbox.stored_string[])
                angle = angle === nothing ? 0.0 : angle
                selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                
                # Update ALL textboxes to stay in sync  
                center_y = (y_min + y_max) / 2
                height = y_max - y_min
                updating_textboxes[] = true
                set_textbox_value(y_textbox, string(round(Int, center_y)))
                set_textbox_value(height_textbox, string(round(Int, height)))
                updating_textboxes[] = false
                
                println("[SELECTION] Width updated to: $width_val")
                
                # Automatically rerun marker detection
                rerun_selection_detection()
            end
        end
    end
    
    Bas3GLMakie.GLMakie.on(height_textbox.stored_string) do val
        if updating_textboxes[]
            return  # Skip callback during programmatic update
        end
        if selection_complete[]
            height_val = tryparse(Float64, val)
            center_y = tryparse(Float64, y_textbox.stored_string[])
            if height_val !== nothing && height_val > 0 && center_y !== nothing
                # Keep center_y and x positions the same
                x_min = minimum([selection_corner1[][1], selection_corner2[][1]])
                x_max = maximum([selection_corner1[][1], selection_corner2[][1]])
                
                # Update corners from center_y and new height
                half_height = height_val / 2
                selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(x_min, center_y - half_height)
                selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(x_max, center_y + half_height)
                
                # Update visualization
                angle = tryparse(Float64, rotation_textbox.stored_string[])
                angle = angle === nothing ? 0.0 : angle
                selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                
                # Update ALL textboxes to stay in sync
                center_x = (x_min + x_max) / 2
                width = x_max - x_min
                updating_textboxes[] = true
                set_textbox_value(x_textbox, string(round(Int, center_x)))
                set_textbox_value(width_textbox, string(round(Int, width)))
                updating_textboxes[] = false
                
                println("[SELECTION] Height updated to: $height_val")
                
                # Automatically rerun marker detection
                rerun_selection_detection()
            end
        end
    end
    
    # Observable to handle selection completion - syncs textboxes AND runs marker detection
    # This ensures the same behavior whether triggered by mouse click or programmatically
    Bas3GLMakie.GLMakie.on(selection_complete) do is_complete
        if is_complete && selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0) && selection_corner2[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
            # Sync textboxes with selection corners
            x_min, x_max = minmax(selection_corner1[][1], selection_corner2[][1])
            y_min, y_max = minmax(selection_corner1[][2], selection_corner2[][2])
            center_x = (x_min + x_max) / 2
            center_y = (y_min + y_max) / 2
            width = x_max - x_min
            height = y_max - y_min
            updating_textboxes[] = true
            set_textbox_value(x_textbox, string(round(Int, center_x)))
            set_textbox_value(y_textbox, string(round(Int, center_y)))
            set_textbox_value(width_textbox, string(round(Int, width)))
            set_textbox_value(height_textbox, string(round(Int, height)))
            updating_textboxes[] = false
            println("[SELECTION] Textboxes synced: center_x=$(center_x), center_y=$(center_y), w=$(width), h=$(height)")
            
            # Get current rotation angle
            angle = tryparse(Float64, rotation_textbox.stored_string[])
            if angle === nothing
                angle = 0.0
            end
            
            # Re-run marker detection on selected region
            current_idx = tryparse(Int, textbox.stored_string[])
            if current_idx !== nothing && current_idx >= 1 && current_idx <= length(sets)
                threshold = tryparse(Float64, threshold_textbox.stored_string[])
                threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
                min_area = tryparse(Int, min_area_textbox.stored_string[])
                aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
                aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
                kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
                
                if threshold !== nothing && threshold_upper !== nothing && min_area !== nothing && aspect_ratio !== nothing && aspect_weight !== nothing && kernel_size !== nothing
                    # Convert axis coordinates to pixel coordinates
                    img = sets[current_idx][1]
                    img_height = Base.size(data(img), 1)
                    img_width = Base.size(data(img), 2)
                    
                    # Convert selection corners to pixel coordinates
                    c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
                    c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
                    
                    # Use shared helper function for consistent region calculation (Path 3: initial selection)
                    local row_range, col_range = calculate_selection_region(img, c1_px, c2_px, angle)
                    region = (first(row_range), last(row_range), first(col_range), last(col_range))
                    println("[SELECTION] Running marker detection on rotated region: rows=$(row_range), cols=$(col_range)")
                    
                    # Detect markers with region constraint (same as update_image_display_internal)
        local params = Dict(:threshold => threshold, :threshold_upper => threshold_upper, :min_area => min_area, :aspect_ratio => aspect_ratio, :aspect_ratio_weight => aspect_weight, :kernel_size => kernel_size, :region => region, :c1 => c1_px, :c2 => c2_px, :angle => angle)
                    local markers, success, message = detect_markers_only(img, params)
                    
                    # STATE PRESERVATION: Only update if markers were found
                    # This prevents corruption when region selection finds nothing
                    if !isempty(markers)
                        println("[SELECTION-CALLBACK] Found $(length(markers)) marker(s), success=$(success)")
                        current_white_overlay[] = create_white_overlay(img, markers)
                        current_marker_viz[] = create_marker_visualization(img, markers)
                        current_markers[] = markers
                        
                        # Update closeup view using same markers as selection detection
                        local closeup_img = extract_closeup_region(img, markers, closeup_rotation[])
                        current_closeup_image[] = closeup_img
                        Bas3GLMakie.GLMakie.notify(current_closeup_image)
                        println("[SELECTION-CALLBACK] Closeup updated with $(length(markers)) marker(s)")
                        
                        println("[SELECTION-CALLBACK] Setting marker_success=$(success), marker_message=$(message)")
                        marker_success[] = success
                        marker_message[] = message
                    else
                        println("[SELECTION-CALLBACK] No markers found, success=$(success)")
                        println("[SELECTION-CALLBACK] Clearing previous detection results")
                        
                        # Clear all detection visuals instead of preserving old state
                        current_white_overlay[] = create_white_overlay(img, MarkerInfo[])
                        current_marker_viz[] = create_marker_visualization(img, MarkerInfo[])
                        current_markers[] = MarkerInfo[]
                        
                        # Clear closeup view (show placeholder)
                        current_closeup_image[] = fill(Bas3GLMakie.GLMakie.RGB{Float32}(0.5, 0.5, 0.5), 100, 100)
                        Bas3GLMakie.GLMakie.notify(current_closeup_image)
                        println("[SELECTION-CALLBACK] Closeup cleared (no markers)")
                        
                        # Update status with enhanced message
                        println("[SELECTION-CALLBACK] Setting marker_success=false, marker_message=$(message)")
                        marker_success[] = false
                        if angle != 0.0
                            marker_message[] = "⚠️ Keine Marker in rotierter Region gefunden ($(angle)°) - versuchen Sie andere Parameter"
                        else
                            marker_message[] = message
                        end
                    end
                end
            end
        end
    end
    
    # Clear selection button callback
    Bas3GLMakie.GLMakie.on(clear_selection_button.clicks) do n
        println("[SELECTION] Clear selection button clicked")
        
        # Deactivate selection mode
        selection_active[] = false
        
        # Clear all selection state
        selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_complete[] = false
        selection_rotation[] = 0.0
        rotation_textbox.stored_string[] = "0.0"
        set_textbox_value(x_textbox, "0")
        set_textbox_value(y_textbox, "0")
        set_textbox_value(width_textbox, "0")
        set_textbox_value(height_textbox, "0")
        selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        selection_status_label.text = "Auswahl gelöscht"
        selection_status_label.color = :gray
        println("[SELECTION] Selection cleared")
        
        # Re-run extraction on full image
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx >= 1 && current_idx <= length(sets)
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            threshold_upper = tryparse(Float64, threshold_upper_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            adaptive = adaptive_toggle.active[]
            adaptive_window = tryparse(Int, adaptive_window_textbox.stored_string[])
            adaptive_offset = tryparse(Float64, adaptive_offset_textbox.stored_string[])
            
            if threshold !== nothing && threshold_upper !== nothing && min_area !== nothing && aspect_ratio !== nothing && aspect_weight !== nothing && kernel_size !== nothing && adaptive_window !== nothing && adaptive_offset !== nothing
                println("[SELECTION] Re-running detection on full image after clearing selection")
                update_image_display_internal(current_idx, threshold, threshold_upper, min_area, aspect_ratio, aspect_weight, kernel_size, adaptive, adaptive_window, adaptive_offset)
            end
        end
    end
    
    # Save mask button callback
    Bas3GLMakie.GLMakie.on(save_mask_button.clicks) do n
        println("[SAVE] Save mask button clicked")
        
        # Get current markers
        markers = current_markers[]
        
        if isempty(markers)
            println("[SAVE] No markers detected - nothing to save")
            selection_status_label.text = "⚠ Keine Maske zum Speichern"
            selection_status_label.color = :red
            return
        end
        
        # Get UI index from textbox
        ui_idx = tryparse(Int, textbox.stored_string[])
        if ui_idx === nothing || ui_idx < 1 || ui_idx > length(sets)
            println("[SAVE] Invalid image index: $ui_idx")
            selection_status_label.text = "❌ Ungültiger Index"
            selection_status_label.color = :red
            return
        end
        
        # Get original dataset index from sets tuple
        current_set = sets[ui_idx]
        dataset_idx = if length(current_set) >= 3
            current_set[3]  # Original dataset index (1-306)
        else
            ui_idx  # Fallback to UI index if tuple doesn't have index
        end
        
        println("[SAVE] UI index: $ui_idx, Dataset index: $dataset_idx")
        
        # Format dataset index as 3-digit zero-padded string
        id_str = lpad(dataset_idx, 3, '0')  # e.g., "001", "042", "306"
        
        # Construct MuHa folder path (resolve for WSL/Windows compatibility)
        base_path = resolve_path("C:/Syncthing/MuHa - Bilder")
        folder_name = "MuHa_$(id_str)"
        folder_path = joinpath(base_path, folder_name)
        
        # Check if folder exists
        if !isdir(folder_path)
            error_msg = "❌ Ordner nicht gefunden: $folder_name"
            println("[SAVE] Error: Folder does not exist: $folder_path")
            selection_status_label.text = error_msg
            selection_status_label.color = :red
            return
        end
        
        # Construct output filename following MuHa convention
        output_filename = "MuHa_$(id_str)_ruler_mask.png"
        output_path = joinpath(folder_path, output_filename)
        
        println("[SAVE] Target path: $output_path")
        
        # Get the best marker (first in list)
        best_marker = markers[1]
        mask = best_marker.mask
        
        try
            # Convert mask to grayscale image (white=marker, black=background)
            # Convert BitMatrix to RGB array for saving as PNG
            h, w = size(mask)
            mask_img = zeros(Bas3ImageSegmentation.RGB{Float32}, h, w)
            mask_img[mask] .= Bas3ImageSegmentation.RGB{Float32}(1.0f0, 1.0f0, 1.0f0)  # White where mask is true
            
            # Apply rotr90 to match UI display coordinate system
            # This ensures saved mask aligns with how images are displayed in the UI
            mask_img_rotated = rotr90(mask_img)
            
            # Save to MuHa folder
            Bas3GLMakie.GLMakie.save(output_path, mask_img_rotated)
            
            println("[SAVE] ✓ Mask saved to: $output_path")
            selection_status_label.text = "✓ Gespeichert: $folder_name"
            selection_status_label.color = :green
            
            # Reset status after 3 seconds
            @async begin
                sleep(3)
                if selection_active[]
                    selection_status_label.text = "Klicken Sie auf die untere linke Ecke"
                    selection_status_label.color = :blue
                else
                    selection_status_label.text = "Keine Auswahl"
                    selection_status_label.color = :gray
                end
            end
        catch e
            error_msg = "❌ Fehler: $(typeof(e))"
            println("[SAVE] Error saving mask: $e")
            println("[SAVE] Stack trace:")
            Base.showerror(stdout, e, catch_backtrace())
            println()
            selection_status_label.text = error_msg
            selection_status_label.color = :red
        end
    end
    
    # Display closeup visualization axis (no overlays - just the rotated closeup image)
    # Use a dynamic approach: recreate the image plot when observable changes dimensions
    # This is necessary because GLMakie doesn't handle dimension changes well with image!()
    local closeup_plot_ref = Ref{Any}(nothing)
    
    function update_closeup_plot()
        # Clear existing plot
        empty!(axs_closeup)
        
        # Create new image plot with current observable value
        closeup_plot_ref[] = Bas3GLMakie.GLMakie.image!(axs_closeup, current_closeup_image[])
        
        # Reset axis limits to fit the image
        Bas3GLMakie.GLMakie.autolimits!(axs_closeup)
    end
    
    # Initial plot
    update_closeup_plot()
    
    # Update plot when observable changes
    Bas3GLMakie.GLMakie.on(current_closeup_image) do img
        update_closeup_plot()
    end
    
    # Display the input image
    Bas3GLMakie.GLMakie.image!(axs3, current_input_image)
    
    # Overlay the segmentation output with 25% transparency (alpha=0.75)
    # Store reference to control visibility
    local segmentation_overlay_plot = Bas3GLMakie.GLMakie.image!(axs3, current_output_image; alpha=0.75)
    
    # Overlay the white region detection with red fill and yellow contours
    # Store reference to control visibility
    local white_overlay_plot = Bas3GLMakie.GLMakie.image!(axs3, current_white_overlay)
    
    # Segmentation toggle callback - control visibility of segmentation and white overlays
    Bas3GLMakie.GLMakie.on(segmentation_toggle.active) do active
        println("[DISPLAY] Segmentation toggle changed: $active")
        segmentation_overlay_plot.visible = active
        white_overlay_plot.visible = active
        # Update bounding box visibility - will be set up below
    end
    
    # Mouse click event handler for region selection
    # Priority 0 allows button clicks to be processed first
    # Note: Figure-level workaround already registered early (line 377-379)
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(axs3).mousebutton, priority = 0) do event
        if event.button == Bas3GLMakie.GLMakie.Mouse.left && event.action == Bas3GLMakie.GLMakie.Mouse.press
            if selection_active[]
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(axs3.scene)
                
                # Check if click is within axis bounds
                # mouseposition returns nothing if outside the axis
                if isnothing(mp)
                    return Bas3GLMakie.GLMakie.Consume(false)
                end
                
                if !selection_complete[]
                    if selection_corner1[] == Bas3GLMakie.GLMakie.Point2f(0, 0)
                        # First click - set first corner
                        println("[SELECTION] First corner selected: $mp")
                        selection_corner1[] = mp
                        selection_status_label.text = "Klicken Sie auf die gegenüberliegende Ecke"
                        selection_status_label.color = :blue
                    else
                        # Second click - set second corner
                        println("[SELECTION] Second corner selected: $mp")
                        selection_corner2[] = mp
                        selection_complete[] = true
                        
                        # Get current rotation angle
                        angle = tryparse(Float64, rotation_textbox.stored_string[])
                        if angle === nothing
                            angle = 0.0
                        end
                        selection_rotation[] = angle
                        
                        # Update rectangle visualization with rotation
                        selection_rect[] = make_rotated_rectangle(selection_corner1[], selection_corner2[], angle)
                        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]  # Clear preview
                        
                        # Update position and size textboxes with CENTER coordinates
                        x_min, x_max = minmax(selection_corner1[][1], selection_corner2[][1])
                        y_min, y_max = minmax(selection_corner1[][2], selection_corner2[][2])
                        center_x = (x_min + x_max) / 2
                        center_y = (y_min + y_max) / 2
                        width = x_max - x_min
                        height = y_max - y_min
                        updating_textboxes[] = true
                        set_textbox_value(x_textbox, string(round(Int, center_x)))
                        set_textbox_value(y_textbox, string(round(Int, center_y)))
                        set_textbox_value(width_textbox, string(round(Int, width)))
                        set_textbox_value(height_textbox, string(round(Int, height)))
                        updating_textboxes[] = false
                        
                        # Deactivate selection mode after completing selection
                        selection_active[] = false
                        selection_status_label.text = "Auswahl abgeschlossen (Rotation: $(angle) Grad)"
                        selection_status_label.color = :green
                        println("[SELECTION] Selection completed: corner1=$(selection_corner1[]), corner2=$(selection_corner2[]), rotation=$(angle) degrees")
                        
                        # NOTE: Marker detection now handled by selection_complete observable (line ~1693)
                        # This ensures consistent behavior for both mouse clicks and programmatic triggers
                    end
                end
                # Always consume events when selection is active to prevent axis interference
                return Bas3GLMakie.GLMakie.Consume(true)
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    # Mouse move event handler for preview
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(axs3).mouseposition, priority = 0) do mp_window
        if selection_active[] && !selection_complete[]
            if selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(axs3.scene)
                
                if !isnothing(mp)
                    # Get current rotation angle from textbox
                    angle = tryparse(Float64, rotation_textbox.stored_string[])
                    if angle === nothing
                        angle = 0.0
                    end
                    
                    println("[PREVIEW] Updating preview with angle: $(angle) degrees, corner1: $(selection_corner1[]), corner2: $mp")
                    
                    # Update preview rectangle with rotation
                    preview_rect[] = make_rotated_rectangle(selection_corner1[], mp, angle)
                    
                    # Update position and size textboxes with current preview values (CENTER coordinates)
                    x_min, x_max = minmax(selection_corner1[][1], mp[1])
                    y_min, y_max = minmax(selection_corner1[][2], mp[2])
                    center_x = (x_min + x_max) / 2
                    center_y = (y_min + y_max) / 2
                    width = x_max - x_min
                    height = y_max - y_min
                    updating_textboxes[] = true
                    set_textbox_value(x_textbox, string(round(Int, center_x)))
                    set_textbox_value(y_textbox, string(round(Int, center_y)))
                    set_textbox_value(width_textbox, string(round(Int, width)))
                    set_textbox_value(height_textbox, string(round(Int, height)))
                    updating_textboxes[] = false
                    
                    println("[PREVIEW] Preview rect corners: $(preview_rect[])")
                end
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    # Draw selection rectangle (cyan border only, no fill)
    Bas3GLMakie.GLMakie.lines!(axs3, selection_rect, 
        color = :cyan,
        linewidth = 3,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($selection_rect)))
    
    # Draw preview rectangle while selecting (cyan border only, thinner line)
    Bas3GLMakie.GLMakie.lines!(axs3, preview_rect,
        color = :cyan,
        linewidth = 2,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($preview_rect)))
    
    # Draw bounding boxes for each class with 50% alpha
    # Colors match CLASS_COLORS_RGB: scar=GREEN, redness=RED, hematoma=goldenrod, necrosis=BLUE
    local bbox_colors_map = Dict(
        :scar => (:green, 0.5),        # RGB(0, 1, 0)
        :redness => (:red, 0.5),       # RGB(1, 0, 0)
        :hematoma => (:goldenrod, 0.5), # goldenrod
        :necrosis => (:blue, 0.5)      # RGB(0, 0, 1)
    )
    
    # Store references to bbox plot objects so we can delete them
    local bbox_plot_objects = []
    
    # Function to draw bounding boxes (will be called when observable updates)
    Bas3GLMakie.GLMakie.on(current_class_bboxes) do bboxes_dict
        println("[OBSERVABLE] current_class_bboxes changed: $(length(bboxes_dict)) classes")
        
        # Delete all previous bbox drawings
        for plot_obj in bbox_plot_objects
            Bas3GLMakie.GLMakie.delete!(axs3, plot_obj)
        end
        empty!(bbox_plot_objects)
        
        # Get image height for coordinate transformation
        local output_data, img_height
        try
            output_data = data(sets[current_image_index[]][2])
            img_height = Base.size(output_data, 1)
            println("[OBSERVABLE] Drawing bounding boxes for image $(current_image_index[]) (height=$img_height)")
        catch e
            println("[ERROR] Failed to get image data for bounding boxes: $e")
            return
        end
        
        # Draw new bounding boxes (only if segmentation is visible)
        for (class, bboxes) in bboxes_dict
            local color = get(bbox_colors_map, class, (:white, 0.5))
            
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
                
                local line_plot = Bas3GLMakie.GLMakie.lines!(axs3, x_coords, y_coords; color=color, linewidth=2, visible=segmentation_toggle.active[])
                push!(bbox_plot_objects, line_plot)
            end
        end
    end
    
    # Trigger initial drawing
    Bas3GLMakie.GLMakie.notify(current_class_bboxes)
    
    println("\n[INFO] Navigation controls ready:")
    println("  - Type a number (1-$(length(sets))) in the textbox and press Enter")
    println("  - Click '← Previous' to go to previous image")
    println("  - Click 'Next →' to go to next image")
    println("  - Enable region selection to limit white detection area\n")
    
    # Test mode: Return figure + observables + widgets for programmatic control
    # Add keyboard shortcut to save debug images (Press 'S' key)
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).keyboardbutton) do event
        if event.action == Bas3GLMakie.GLMakie.Keyboard.press || event.action == Bas3GLMakie.GLMakie.Keyboard.repeat
            if event.key == Bas3GLMakie.GLMakie.Keyboard.s
                println("[DEBUG] 'S' key pressed - Saving debug images...")
                
                # Get current image index
                current_idx = current_image_index[]
                if current_idx === nothing || current_idx < 1 || current_idx > length(sets)
                    println("[DEBUG] No valid image loaded")
                    return
                end
                
                # Save original image
                original_img = current_input_image[]
                if original_img !== nothing
                    save("/tmp/debug_original_image.png", Bas3GLMakie.GLMakie.rotr90(original_img))
                    println("[DEBUG] ✓ Saved: /tmp/debug_original_image.png (size: $(size(original_img)))")
                end
                
                # Save closeup image  
                closeup_img = current_closeup_image[]
                if closeup_img !== nothing
                    save("/tmp/debug_closeup_image.png", closeup_img)
                    println("[DEBUG] ✓ Saved: /tmp/debug_closeup_image.png (size: $(size(closeup_img)))")
                end
                
                # Save marker visualization
                marker_viz = current_marker_viz[]
                if marker_viz !== nothing
                    save("/tmp/debug_marker_viz.png", Bas3GLMakie.GLMakie.rotr90(marker_viz))
                    println("[DEBUG] ✓ Saved: /tmp/debug_marker_viz.png (size: $(size(marker_viz)))")
                end
                
                # Save current output (segmented) image
                output_img = current_output_image[]
                if output_img !== nothing
                    save("/tmp/debug_output_image.png", Bas3GLMakie.GLMakie.rotr90(output_img))
                    println("[DEBUG] ✓ Saved: /tmp/debug_output_image.png (size: $(size(output_img)))")
                end
                
                println("[DEBUG] All available images saved to /tmp/debug_*.png")
            end
        end
    end
    
    if test_mode
        println("[TEST MODE] Returning figure with observables and widgets access")
        
        # Create axes dictionary for direct access
        axes_dict = Dict{Symbol, Any}(
            :closeup_axis => axs_closeup,
            :image_axis => axs3,
            :full_mean_axis => full_mean_ax,
            :full_box_axis => full_box_ax,
            :region_mean_axis => region_mean_ax,
            :region_box_axis => region_box_ax
        )
        
        # Create observables dictionary (Priority 1 + Priority 2)
        observables_dict = Dict{Symbol, Any}(
            # Region Selection (Priority 1)
            :selection_active => selection_active,
            :selection_corner1 => selection_corner1,
            :selection_corner2 => selection_corner2,
            :selection_complete => selection_complete,
            :selection_rect => selection_rect,
            :preview_rect => preview_rect,
            :selection_rotation => selection_rotation,
            
            # Marker Detection (Priority 1)
            :current_markers => current_markers,
            :marker_success => marker_success,
            :marker_message => marker_message,
            
            # Image State (Priority 1 + 2)
            :current_input_image => current_input_image,
            :current_output_image => current_output_image,
            :current_white_overlay => current_white_overlay,
            :current_marker_viz => current_marker_viz,
            :current_image_index => current_image_index,
            :current_class_bboxes => current_class_bboxes,
            
            # Closeup View
            :closeup_rotation => closeup_rotation,
            :current_closeup_image => current_closeup_image
        )
        
        # Create widgets dictionary (Priority 1 + Priority 2 + Priority 3)
        widgets_dict = Dict{Symbol, Any}(
            # Navigation (Priority 1)
            :nav_textbox => textbox,
            :prev_button => prev_button,
            :next_button => next_button,
            :textbox_label => textbox_label,
            
            # Selection (Priority 1)
            :start_selection_button => start_selection_button,
            :rotation_textbox => rotation_textbox,
            :clear_selection_button => clear_selection_button,
            :save_mask_button => save_mask_button,
            :selection_status_label => selection_status_label,
            
            # Closeup
            :closeup_rotation_textbox => closeup_rotation_textbox,
            
            # Position/Size Textboxes (Priority 1)
            :x_textbox => x_textbox,
            :y_textbox => y_textbox,
            :width_textbox => width_textbox,
            :height_textbox => height_textbox,
            
            # Parameters (Priority 2)
            :threshold_textbox => threshold_textbox,
            :threshold_upper_textbox => threshold_upper_textbox,
            :min_area_textbox => min_area_textbox,
            :aspect_ratio_textbox => aspect_ratio_textbox,
            :aspect_weight_textbox => aspect_weight_textbox,
            :kernel_size_textbox => kernel_size_textbox,
            :adaptive_toggle => adaptive_toggle,
            :adaptive_window_textbox => adaptive_window_textbox,
            :adaptive_offset_textbox => adaptive_offset_textbox,
            
            # Display (Priority 3)
            :segmentation_toggle => segmentation_toggle,
            
            # Database Controls
            :date_textbox => date_textbox,
            :patient_id_textbox => patient_id_textbox,
            :info_textbox => info_textbox,
            :save_db_button => save_db_button,
            :db_status_label => db_status_label
        )
        
        # Return named tuple with all components
        return (
            figure = fgr,
            axes = axes_dict,
            observables = observables_dict,
            widgets = widgets_dict
        )
    else
        # Production mode: Return figure only (unchanged behavior)
        return fgr
    end
end
