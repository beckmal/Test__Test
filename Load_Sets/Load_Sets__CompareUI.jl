# Load_Sets__CompareUI.jl
# Patient Image Comparison UI - Shows all images for a selected patient

# Required packages for database functionality
using XLSX
using Dates
using LinearAlgebra: eigen
using Statistics: median
using Colors: N0f8, RGB, LCHab  # Fixed-point normalized UInt8 + color conversion
using JSON3  # For multi-class polygon metadata serialization

# ============================================================================
# MULTI-POLYGON DATA STRUCTURES
# ============================================================================

"""
    PolygonEntry

Represents a single polygon with class assignment for multi-class wound annotation.

# Fields
- `id::Int`: Unique polygon ID within image
- `class::Symbol`: Wound class (:scar, :redness, :hematoma, :necrosis, :background, :custom)
- `class_name::String`: Custom class name (overrides default if provided)
- `sample_number::Int`: Sample number for this class (default 1)
- `vertices::Vector`: Polygon vertices in UI coordinate space (Point2f elements)
- `complete::Bool`: Whether polygon is closed and finalized
- `lch_data::Union{NamedTuple, Nothing}`: Cached L*C*h color metrics (L_median, C_median, h_median, count)

# Example
```julia
poly = PolygonEntry(
    id = 1,
    class = :redness,
    class_name = "Entzündung",
    sample_number = 2,
    vertices = [Point2f(100, 200), Point2f(150, 250), Point2f(120, 300)],
    complete = true,
    lch_data = (L_median=45.2, C_median=32.1, h_median=25.3, count=1250)
)
```
"""
struct PolygonEntry
    id::Int
    class::Symbol
    class_name::String
    sample_number::Int
    vertices::Vector  # Point2f elements (no type annotation to avoid load-order dependency)
    complete::Bool
    lch_data::Union{NamedTuple, Nothing}
end

# Constructor with default values
PolygonEntry(id::Int, class::Symbol, vertices::Vector) = 
    PolygonEntry(id, class, "", 1, vertices, false, nothing)

# Constructor with class name and sample number
PolygonEntry(id::Int, class::Symbol, class_name::String, sample_number::Int, vertices::Vector) = 
    PolygonEntry(id, class, class_name, sample_number, vertices, false, nothing)

"""
    class_to_index(class::Symbol) -> UInt8

Convert wound class symbol to index for mask encoding.

# Class Mapping
- 0: no mask (transparent)
- 1: :scar
- 2: :redness
- 3: :hematoma
- 4: :necrosis
- 5: :background
"""
function class_to_index(class::Symbol)::UInt8
    class_map = Dict(
        :scar => UInt8(1),
        :redness => UInt8(2),
        :hematoma => UInt8(3),
        :necrosis => UInt8(4),
        :background => UInt8(5)
    )
    return get(class_map, class, UInt8(0))
end

"""
    index_to_class(index::UInt8) -> Symbol

Convert mask index to wound class symbol.
"""
function index_to_class(index::UInt8)::Symbol
    index_map = Dict(
        UInt8(0) => :none,
        UInt8(1) => :scar,
        UInt8(2) => :redness,
        UInt8(3) => :hematoma,
        UInt8(4) => :necrosis,
        UInt8(5) => :background
    )
    return get(index_map, index, :none)
end

"""
    get_class_color(class::Symbol) -> RGBf

Get display color for wound class from CLASS_COLORS_RGB.
"""
function get_class_color(class::Symbol)
    class_colors = Dict(
        :scar => Bas3GLMakie.GLMakie.RGBf(0, 1, 0),      # Green
        :redness => Bas3GLMakie.GLMakie.RGBf(1, 0, 0),    # Red
        :hematoma => Bas3GLMakie.GLMakie.RGBf(0.85, 0.65, 0.125),  # Goldenrod
        :necrosis => Bas3GLMakie.GLMakie.RGBf(0, 0, 1),   # Blue
        :background => Bas3GLMakie.GLMakie.RGBf(0.5, 0.5, 0.5)  # Gray
    )
    return get(class_colors, class, Bas3GLMakie.GLMakie.RGBf(1, 1, 1))
end

# Available wound classes (ordered for UI display)
const WOUND_CLASSES = [:scar, :redness, :hematoma, :necrosis, :background]

# ============================================================================
# HELPER FUNCTIONS FOR POLYGON MASK FILENAME MANAGEMENT
# ============================================================================

"""
    construct_polygon_mask_filename(image_index::Int, polygon::PolygonEntry) -> String

Construct standardized filename for individual polygon mask.

# Format
`MuHa_{patient_num}_polygon_{class_name}_{polygon_id}.png`

# Arguments
- `image_index::Int`: Patient image index (1-306)
- `polygon::PolygonEntry`: Polygon with class_name and id

# Returns
- `String`: Filename (not full path)

# Examples
```julia
polygon = PolygonEntry(id=1, class=:scar, class_name="In_Narbe", ...)
construct_polygon_mask_filename(1, polygon)
# → "MuHa_001_polygon_In_Narbe_1.png"

polygon = PolygonEntry(id=15, class=:hematoma, class_name="Umgebung", ...)
construct_polygon_mask_filename(23, polygon)
# → "MuHa_023_polygon_Umgebung_15.png"
```
"""
function construct_polygon_mask_filename(image_index::Int, polygon::PolygonEntry)
    local patient_num = lpad(image_index, 3, '0')
    local class_name = polygon.class_name  # German name from CLASS_NAMES_DE
    local polygon_id = polygon.id
    
    return "MuHa_$(patient_num)_polygon_$(class_name)_$(polygon_id).png"
end

"""
    parse_polygon_mask_filename(filename::String) -> Union{NamedTuple, Nothing}

Parse polygon mask filename to extract metadata.

# Arguments
- `filename::String`: Filename like "MuHa_001_polygon_In_Narbe_15.png"

# Returns
- `(patient_num=1, class_name="In_Narbe", polygon_id=15)` if valid
- `nothing` if filename doesn't match pattern

# Pattern
`MuHa_{patient_num}_polygon_{class_name}_{polygon_id}.png`

# Examples
```julia
parse_polygon_mask_filename("MuHa_001_polygon_In_Narbe_1.png")
# → (patient_num=1, class_name="In_Narbe", polygon_id=1)

parse_polygon_mask_filename("MuHa_023_polygon_Umgebung_15.png")
# → (patient_num=23, class_name="Umgebung", polygon_id=15)

parse_polygon_mask_filename("invalid_file.png")
# → nothing
```
"""
function parse_polygon_mask_filename(filename::String)
    # Pattern: MuHa_{NNN}_polygon_{class_name}_{id}.png
    local pattern = r"^MuHa_(\d{3})_polygon_([^_]+)_(\d+)\.png$"
    local m = match(pattern, filename)
    
    if isnothing(m)
        return nothing
    end
    
    return (
        patient_num = parse(Int, m.captures[1]),
        class_name = m.captures[2],
        polygon_id = parse(Int, m.captures[3])
    )
end

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
    get_patient_image_counts(db_path::String) -> Dict{Int, Int}

Returns a dictionary mapping patient_id => image_count.
Only includes patients that have at least one image.

# Example
```julia
counts = get_patient_image_counts(db_path)
# => Dict(1 => 3, 2 => 5, 3 => 2)  # Patient 1 has 3 images, etc.
```
"""
function get_patient_image_counts(db_path::String)
    counts = Dict{Int, Int}()
    
    if !isfile(db_path)
        return counts
    end
    
    try
        xf = XLSX.readxlsx(db_path)
        sheet = xf["Metadata"]
        dims = XLSX.get_dimension(sheet)
        last_row = dims.stop.row_number
        
        for row in 2:last_row
            patient_id = sheet[row, 4]  # Column D = Patient_ID
            if !isnothing(patient_id) && patient_id isa Number
                pid = Int(patient_id)
                counts[pid] = get(counts, pid, 0) + 1
            end
        end
    catch e
        @warn "Error reading patient image counts: $e"
    end
    
    return counts
end

"""
    filter_patients_by_exact_count(patient_ids::Vector{Int}, 
                                    image_counts::Dict{Int, Int}, 
                                    target_count::Int) -> Vector{Int}

Filters patient IDs to only include those with exactly target_count images.
If target_count ≤ 0, returns all patients (no filter).

# Arguments
- `patient_ids`: List of all patient IDs to filter
- `image_counts`: Dictionary mapping patient_id => count (from get_patient_image_counts)
- `target_count`: Exact number of images required (0 = no filter)

# Example
```julia
all_patients = [1, 2, 3, 4]
counts = Dict(1 => 3, 2 => 1, 3 => 2, 4 => 5)
filtered = filter_patients_by_exact_count(all_patients, counts, 2)
# => [3]  # Only patients with exactly 2 images
```
"""
function filter_patients_by_exact_count(patient_ids::Vector{Int}, 
                                        image_counts::Dict{Int, Int}, 
                                        target_count::Int)
    if target_count <= 0
        return patient_ids  # No filter
    end
    
    return filter(pid -> get(image_counts, pid, 0) == target_count, patient_ids)
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
# POLYGON MASK EXPORT FUNCTIONS
# ============================================================================

"""
    get_patient_folder_from_filename(filename::String, base_dir::String) -> Union{String, Nothing}

Extract patient folder path from filename.
Parses patient number from filename and constructs full path to patient folder.

# Arguments
- `filename`: Image filename (e.g., "MuHa_001_raw_adj.png")
- `base_dir`: Base directory path (e.g., "/mnt/c/Syncthing/MuHa - Bilder")

# Returns
- Full path to patient folder (e.g., "/mnt/c/Syncthing/MuHa - Bilder/MuHa_001/")
- `nothing` if filename is invalid or folder doesn't exist

# Examples
```julia
path = get_patient_folder_from_filename("MuHa_001_raw_adj.png", "/mnt/c/Syncthing/MuHa - Bilder")
# => "/mnt/c/Syncthing/MuHa - Bilder/MuHa_001/"
```
"""
function get_patient_folder_from_filename(filename::String, base_dir::String)
    # Match pattern: MuHa_XXX_... where XXX is 3 digits
    m = match(r"MuHa_(\d{3})", filename)
    if isnothing(m)
        @warn "[MASK-EXPORT] Invalid filename format: $filename"
        return nothing
    end
    
    local patient_num = m.captures[1]  # e.g., "001"
    local patient_folder_name = "MuHa_$(patient_num)"
    local patient_folder_path = joinpath(base_dir, patient_folder_name)
    
    # Check if folder exists
    if !isdir(patient_folder_path)
        @warn "[MASK-EXPORT] Patient folder not found: $patient_folder_path"
        return nothing
    end
    
    return patient_folder_path
end

"""
    save_polygon_mask_png(mask::BitMatrix, output_path::String) -> Tuple{Bool, String}

Save polygon mask as PNG file.

# Arguments
- `mask`: BitMatrix (h x w) - binary mask where true=inside polygon, false=outside
- `output_path`: Full path including filename (e.g., "/path/MuHa_001_raw_adj_polygon_mask.png")

# Returns
- Tuple of (success::Bool, message::String)
  - success=true: File saved successfully
  - success=false: Error occurred, message contains error details

# Notes
- Converts BitMatrix to grayscale: false→0 (black), true→255 (white)
- Uses PNG format (lossless compression)
- Overwrites existing files without warning
"""
function save_polygon_mask_png(mask::BitMatrix, output_path::String)
    try
        # Convert BitMatrix to RGB image for GLMakie save
        # false → RGB{Float32}(0,0,0) = black
        # true → RGB{Float32}(1,1,1) = white
        local h, w = size(mask)
        
        # GLMakie.save() saves arrays as-is in the same orientation
        # Mask is already in landscape orientation (H×W landscape), so save directly
        local img_rgb = Matrix{Bas3ImageSegmentation.v_RGB}(undef, h, w)
        for i in 1:h, j in 1:w
            img_rgb[i, j] = mask[i, j] ? Bas3ImageSegmentation.v_RGB(1, 1, 1) : Bas3ImageSegmentation.v_RGB(0, 0, 0)
        end
        
        # Save as PNG - will be H×W in PNG file (landscape, matching UI)
        Bas3GLMakie.GLMakie.save(output_path, img_rgb)
        
        println("[MASK-EXPORT] Saved mask: $(h)×$(w) array → PNG $(h)×$(w) (landscape)")
        return (true, "Maske gespeichert: $(basename(output_path))")
    catch e
        local error_msg = "Fehler beim Speichern: $(typeof(e))"
        @warn "[MASK-EXPORT] Failed to save mask: $e"
        return (false, error_msg)
    end
end

"""
    save_polygon_mask_individual(
        image_index::Int,
        polygon::PolygonEntry,
        mask::BitMatrix,
        patient_folder::String
    ) -> (Bool, String)

Save individual polygon mask to separate PNG file with class name in filename.

# Arguments
- `image_index::Int`: Patient image index (1-306)
- `polygon::PolygonEntry`: Polygon with id and class_name
- `mask::BitMatrix`: Binary mask for this polygon only
- `patient_folder::String`: Path to MuHa_XXX folder

# Returns
- `(true, filename)`: Success with filename
- `(false, error_msg)`: Failure with error message

# File naming
- Format: MuHa_{patient_num}_polygon_{class_name}_{polygon_id}.png
- Example: MuHa_001_polygon_In_Narbe_1.png
"""
function save_polygon_mask_individual(
    image_index::Int,
    polygon::PolygonEntry,
    mask::BitMatrix,
    patient_folder::String
)
    local total_time = 0.0
    local filename_time = 0.0
    local rotate_time = 0.0
    local flip_time = 0.0
    local convert_time = 0.0
    local save_time = 0.0
    
    try
        total_time = @elapsed begin
            # Construct filename using helper (includes class name)
            local filename = ""
            filename_time = @elapsed begin
                filename = construct_polygon_mask_filename(image_index, polygon)
            end
            local output_path = joinpath(patient_folder, filename)
            
            # IMPORTANT: Mask is in landscape orientation (H×W after rotr90)
            # Need to rotate back to portrait to match original files (rotl90 inverts rotr90)
            local mask_portrait = nothing
            rotate_time = @elapsed begin
                mask_portrait = rotl90(mask)
            end
            
            # Flip vertically (around horizontal axis) to match image coordinate system
            local mask_flipped = nothing
            flip_time = @elapsed begin
                mask_flipped = reverse(mask_portrait, dims=1)
            end
            
            # Convert BitMatrix to RGB (using portrait orientation)
            local h, w = size(mask_flipped)
            local img_rgb = nothing
            convert_time = @elapsed begin
                img_rgb = Matrix{Bas3ImageSegmentation.v_RGB}(undef, h, w)
                for i in 1:h, j in 1:w
                    img_rgb[i, j] = mask_flipped[i, j] ? 
                        Bas3ImageSegmentation.v_RGB(1, 1, 1) : 
                        Bas3ImageSegmentation.v_RGB(0, 0, 0)
                end
            end
            
            # Save as PNG in portrait orientation
            save_time = @elapsed begin
                Bas3GLMakie.GLMakie.save(output_path, img_rgb)
            end
            
            println("[PERF-POLYGON-SAVE] ID=$(polygon.id) class=$(polygon.class_name): total=$(round(total_time*1000, digits=1))ms, rotate=$(round(rotate_time*1000, digits=1))ms, flip=$(round(flip_time*1000, digits=1))ms, convert=$(round(convert_time*1000, digits=1))ms, save=$(round(save_time*1000, digits=1))ms")
            println("[MASK-EXPORT] Saved polygon $(polygon.id) ($(polygon.class_name)): $filename ($(h)×$(w) portrait, flipped)")
            
            return (true, filename)
        end
    catch e
        local error_msg = "Failed to save polygon $(polygon.id): $(typeof(e))"
        @warn "[MASK-EXPORT] $error_msg: $e"
        return (false, error_msg)
    end
end

# ============================================================================
# MASK OVERLAY FUNCTIONS (for displaying saved polygon masks)
# ============================================================================

"""
    load_polygon_mask_if_exists(image_index::Int) -> Union{Matrix{RGB{Float32}}, Nothing}

Load saved polygon mask PNG if it exists.

# Arguments
- `image_index::Int`: Image index (1-306)

# Returns
- `Matrix{RGB{Float32}}`: RGB mask in landscape orientation (matches UI display)
- `nothing`: If file doesn't exist

# Coordinate Pipeline
SAVE: rotr90(original portrait) → mask in landscape → FileIO.save() → PNG in landscape
LOAD: FileIO.load() → PNG in landscape → matches UI display directly!

# Process
1. Construct path: MuHa_XXX/MuHa_XXX_polygon_mask.png
2. Load PNG directly with FileIO.load() - already in landscape orientation
3. Convert to RGB{Float32} without any coordinate transformations
4. Return mask (already matches base image orientation!)
"""
function load_polygon_mask_if_exists(image_index::Int)
    local total_time = 0.0
    local file_check_time = 0.0
    local png_load_time = 0.0
    local convert_time = 0.0
    local composite_time = 0.0
    
    total_time = @elapsed begin
        local base_dir = dirname(get_database_path())
        local patient_num = lpad(image_index, 3, '0')
        local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
        
        # Try loading composite mask first (NEW: fast path for v3 format)
        local composite_mask_path = joinpath(patient_folder, "MuHa_$(patient_num)_composite_mask.png")
        
        file_check_time = @elapsed begin
            if isfile(composite_mask_path)
                # Load pre-generated composite (fast!)
                try
                    local img = Bas3GLMakie.GLMakie.FileIO.load(composite_mask_path)
                    local h, w = size(img)
                    local mask_rgb = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h, w)
                    
                    for i in 1:h, j in 1:w
                        local rgb_val = Bas3ImageSegmentation.RGB(img[i, j])
                        mask_rgb[i, j] = Bas3ImageSegmentation.RGB{Float32}(
                            Float32(rgb_val.r), 
                            Float32(rgb_val.g), 
                            Float32(rgb_val.b)
                        )
                    end
                    
                    println("[MASK-LOAD] Loaded composite mask (v3 format): $(size(mask_rgb))")
                    return mask_rgb
                catch e
                    @warn "[MASK-LOAD] Failed to load composite mask: $e"
                end
            end
        end
        
        # Fallback 1: Try old single mask format (backward compatibility)
        local single_mask_path = joinpath(patient_folder, "MuHa_$(patient_num)_polygon_mask.png")
        
        if isfile(single_mask_path)
            try
                png_load_time = @elapsed begin
                    local img = Bas3GLMakie.GLMakie.FileIO.load(single_mask_path)
                    local h, w = size(img)
                    local mask_rgb = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h, w)
                    
                    for i in 1:h, j in 1:w
                        local rgb_val = Bas3ImageSegmentation.RGB(img[i, j])
                        mask_rgb[i, j] = Bas3ImageSegmentation.RGB{Float32}(
                            Float32(rgb_val.r), 
                            Float32(rgb_val.g), 
                            Float32(rgb_val.b)
                        )
                    end
                    
                    println("[MASK-LOAD] Loaded single mask (v2 format): $(size(mask_rgb))")
                    return mask_rgb
                end
            catch e
                @warn "[MASK-LOAD] Failed to load single mask: $e"
            end
        end
        
        # Fallback 2: Try loading individual masks and reconstruct composite (NEW)
        println("[MASK-LOAD] No composite or single mask found, trying individual masks...")
        
        composite_time = @elapsed begin
            local individual_masks = load_polygon_masks_individual(image_index)
            
            if length(individual_masks) > 0
                local polygons = load_multiclass_metadata(image_index)
                local composite = reconstruct_composite_mask(individual_masks, polygons)
                
                if size(composite) != (0, 0)
                    println("[MASK-LOAD] Reconstructed composite from $(length(individual_masks)) individual masks")
                    return composite
                end
            end
        end
        
        # No masks found
        println("[MASK-LOAD] No masks found for image $image_index")
        return nothing
    end
    
    println("[PERF-MASK-PNG] Image $image_index: total=$(round(total_time*1000, digits=2))ms")
end

"""
    load_polygon_masks_individual(image_index::Int) -> Dict{Int, Matrix{RGB{Float32}}}

Load all individual polygon masks for an image using class-based filenames.

# Arguments
- `image_index::Int`: Patient image index (1-306)

# Returns
- `Dict{polygon_id => mask}`: Dictionary mapping polygon IDs to their masks
- Empty dict if no masks found

# Process
1. Load metadata JSON to get polygon IDs and class names
2. Construct filename using construct_polygon_mask_filename()
3. Load each MuHa_XXX_polygon_{class_name}_{id}.png file
4. Return dictionary of masks by polygon ID
"""
function load_polygon_masks_individual(image_index::Int)
    local masks = Dict{Int, Matrix{Bas3ImageSegmentation.RGB{Float32}}}()
    
    # Load metadata to get polygon IDs and class names
    local metadata_polygons = load_multiclass_metadata(image_index)
    
    if length(metadata_polygons) == 0
        return masks
    end
    
    # Load each polygon's mask file
    local base_dir = dirname(get_database_path())
    local patient_num = lpad(image_index, 3, '0')
    local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
    
    for polygon in metadata_polygons
        # Construct filename using helper (includes class name)
        local filename = construct_polygon_mask_filename(image_index, polygon)
        local mask_path = joinpath(patient_folder, filename)
        
        # Fallback: If mask_file field exists in polygon, try that first
        if hasfield(typeof(polygon), :mask_file) && !isnothing(polygon.mask_file)
            local json_filename = polygon.mask_file
            local json_mask_path = joinpath(patient_folder, json_filename)
            
            if isfile(json_mask_path)
                mask_path = json_mask_path
                filename = json_filename
            elseif !isfile(mask_path)
                @warn "[MASK-LOAD] Neither JSON filename ($json_filename) nor reconstructed filename ($filename) found"
                continue
            end
        end
        
        if !isfile(mask_path)
            @warn "[MASK-LOAD] Missing mask file: $filename (polygon $(polygon.id), class $(polygon.class_name))"
            continue
        end
        
        try
            # Load PNG
            local img = Bas3GLMakie.GLMakie.FileIO.load(mask_path)
            
            # Flip back (undo the vertical flip from save)
            local img_unflipped = reverse(img, dims=1)
            
            local h, w = size(img_unflipped)
            
            # Convert to RGB{Float32}
            local mask_rgb = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h, w)
            for i in 1:h, j in 1:w
                local rgb_val = Bas3ImageSegmentation.RGB(img_unflipped[i, j])
                mask_rgb[i, j] = Bas3ImageSegmentation.RGB{Float32}(
                    Float32(rgb_val.r), 
                    Float32(rgb_val.g), 
                    Float32(rgb_val.b)
                )
            end
            
            masks[polygon.id] = mask_rgb
            println("[MASK-LOAD] ✓ Loaded polygon $(polygon.id) ($(polygon.class_name)): $(h)×$(w) (unflipped)")
        catch e
            @warn "[MASK-LOAD] ✗ Failed to load polygon $(polygon.id) ($(polygon.class_name)): $e"
        end
    end
    
    return masks
end

"""
    reconstruct_composite_mask(
        individual_masks::Dict{Int, Matrix{RGB{Float32}}},
        polygons::Vector{PolygonEntry}
    ) -> Matrix{RGB{Float32}}

Reconstruct composite mask from individual polygon masks using class colors.

# Arguments
- `individual_masks::Dict{Int, Matrix{RGB{Float32}}}`: Individual polygon masks
- `polygons::Vector{PolygonEntry}`: Polygon metadata (for class info)

# Returns
- `Matrix{RGB{Float32}}`: Composite mask with class-based coloring

# Process
1. Create blank canvas (all black)
2. For each polygon (in order of ID):
   - Get polygon's class color from get_class_color()
   - Apply mask pixels using class color
   - Later polygons overwrite earlier ones (last wins)
"""
function reconstruct_composite_mask(
    individual_masks::Dict{Int, Matrix{Bas3ImageSegmentation.RGB{Float32}}},
    polygons::Vector{PolygonEntry}
)
    local total_time = 0.0
    local canvas_create_time = 0.0
    local overlay_time = 0.0
    
    total_time = @elapsed begin
        if length(individual_masks) == 0
            return Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, 0, 0)
        end
        
        # Get dimensions from first mask
        local first_mask = first(values(individual_masks))
        local h, w = size(first_mask)
        
        # Create blank composite (all black)
        local composite = nothing
        canvas_create_time = @elapsed begin
            composite = fill(Bas3ImageSegmentation.RGB{Float32}(0, 0, 0), h, w)
        end
        
        # Apply each polygon mask with its class color
        overlay_time = @elapsed begin
            for polygon in polygons
                if !haskey(individual_masks, polygon.id)
                    continue
                end
                
                local mask = individual_masks[polygon.id]
                local class_color_rgbf = get_class_color(polygon.class)
                local class_color = Bas3ImageSegmentation.RGB{Float32}(
                    Float32(class_color_rgbf.r),
                    Float32(class_color_rgbf.g),
                    Float32(class_color_rgbf.b)
                )
                
                # Apply colored mask (where mask is white, use class color)
                for i in 1:h, j in 1:w
                    if mask[i, j].r > 0.5  # White pixel in mask (polygon interior)
                        composite[i, j] = class_color
                    end
                end
            end
        end
        
        println("[PERF-RECONSTRUCT] total=$(round(total_time*1000, digits=1))ms, canvas=$(round(canvas_create_time*1000, digits=1))ms, overlay=$(round(overlay_time*1000, digits=1))ms, n_polygons=$(length(individual_masks)), size=$(h)×$(w)")
        println("[MASK-COMPOSITE] Reconstructed composite from $(length(individual_masks)) polygons: $(h)×$(w)")
        return composite
    end
end

"""
    save_composite_mask_from_individuals(image_index::Int) -> Bool

Generate and save a composite mask from individual polygon PNGs.
Used for quick visual inspection without loading all individual files.

# Arguments
- `image_index::Int`: Patient image index (1-306)

# Saves
- `MuHa_XXX_composite_mask.png`: Combined view with class colors

# Returns
- `true`: Success
- `false`: Failure or no masks found
"""
function save_composite_mask_from_individuals(image_index::Int)
    local total_time = 0.0
    local load_time = 0.0
    local metadata_load_time = 0.0
    local reconstruct_time = 0.0
    local save_time = 0.0
    
    total_time = @elapsed begin
        local individual_masks = nothing
        load_time = @elapsed begin
            individual_masks = load_polygon_masks_individual(image_index)
        end
        
        local polygons = nothing
        metadata_load_time = @elapsed begin
            polygons = load_multiclass_metadata(image_index)
        end
        
        if length(individual_masks) == 0
            @warn "[MASK-COMPOSITE] No individual masks found for image $image_index"
            return false
        end
        
        local composite = nothing
        reconstruct_time = @elapsed begin
            composite = reconstruct_composite_mask(individual_masks, polygons)
        end
        
        # Save composite
        local base_dir = dirname(get_database_path())
        local patient_num = lpad(image_index, 3, '0')
        local composite_path = joinpath(
            base_dir, 
            "MuHa_$(patient_num)", 
            "MuHa_$(patient_num)_composite_mask.png"
        )
        
        save_time = @elapsed begin
            try
                Bas3GLMakie.GLMakie.save(composite_path, composite)
                println("[PERF-COMPOSITE] total=$(round(total_time*1000, digits=1))ms, load=$(round(load_time*1000, digits=1))ms, metadata=$(round(metadata_load_time*1000, digits=1))ms, reconstruct=$(round(reconstruct_time*1000, digits=1))ms, save=$(round(save_time*1000, digits=1))ms, n_polygons=$(length(individual_masks))")
                println("[MASK-COMPOSITE] Saved composite mask from $(length(individual_masks)) polygons: $(basename(composite_path))")
                return true
            catch e
                @warn "[MASK-COMPOSITE] Failed to save composite: $e"
                return false
            end
        end
    end
end

"""
    detect_mask_format(image_index::Int) -> Symbol

Detect which mask format is used for a given image.

# Arguments
- `image_index::Int`: Patient image index (1-306)

# Returns
- `:separate_files`: Individual polygon masks with class names
- `:single_file`: Old single combined mask
- `:none`: No masks found

# Detection Logic
1. Check JSON metadata for mask_format field (version 3)
2. Check for individual polygon mask files (pattern: *_polygon_*_*.png)
3. Check for old single mask file (*_polygon_mask.png)
4. Return :none if nothing found
"""
function detect_mask_format(image_index::Int)
    local base_dir = dirname(get_database_path())
    local patient_num = lpad(image_index, 3, '0')
    local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
    
    if !isdir(patient_folder)
        return :none
    end
    
    # Try loading metadata to check for mask_format field
    local metadata_polygons = load_multiclass_metadata(image_index)
    if length(metadata_polygons) > 0
        # Check if first polygon has mask_file field (indicates version 3)
        local first_poly = metadata_polygons[1]
        if hasfield(typeof(first_poly), :mask_file) && !isnothing(first_poly.mask_file)
            return :separate_files
        end
    end
    
    # Check for individual polygon mask files
    local files = readdir(patient_folder)
    if any(f -> occursin(r"_polygon_[^_]+_\d+\.png$", f), files)
        return :separate_files
    end
    
    # Check for old single mask
    local single_mask_path = joinpath(patient_folder, "MuHa_$(patient_num)_polygon_mask.png")
    if isfile(single_mask_path)
        return :single_file
    end
    
    return :none
end

"""
    migrate_polygon_mask_filenames(image_index::Int) -> Bool

Rename polygon mask files to match current class names in JSON metadata.
Use this after changing class names in Load_Sets__Colors.jl.

# Arguments
- `image_index::Int`: Patient image index (1-306)

# Returns
- `true`: Migration successful or no changes needed
- `false`: Migration failed

# Process
1. Load metadata to get current polygon info
2. For each polygon, compare stored mask_file with expected filename
3. Rename files if they differ
4. Update JSON metadata with new filenames
"""
function migrate_polygon_mask_filenames(image_index::Int)
    local polygons = load_multiclass_metadata(image_index)
    
    if length(polygons) == 0
        println("[MIGRATION] No polygons found for image $image_index")
        return true
    end
    
    local base_dir = dirname(get_database_path())
    local patient_num = lpad(image_index, 3, '0')
    local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
    
    local renamed_count = 0
    local failed_count = 0
    
    for polygon in polygons
        # Get expected filename from current class name
        local new_filename = construct_polygon_mask_filename(image_index, polygon)
        
        # Get current filename from JSON (if exists)
        local old_filename = if hasfield(typeof(polygon), :mask_file) && !isnothing(polygon.mask_file)
            polygon.mask_file
        else
            # No mask_file field, assume old filename matches new one
            new_filename
        end
        
        # Skip if already correct
        if old_filename == new_filename
            continue
        end
        
        local old_path = joinpath(patient_folder, old_filename)
        local new_path = joinpath(patient_folder, new_filename)
        
        # Rename file if it exists
        if isfile(old_path)
            try
                mv(old_path, new_path)
                println("[MIGRATION] Renamed: $old_filename → $new_filename")
                renamed_count += 1
                
                # Update polygon's mask_file field (if it exists)
                if hasfield(typeof(polygon), :mask_file)
                    polygon.mask_file = new_filename
                end
            catch e
                @warn "[MIGRATION] Failed to rename $old_filename: $e"
                failed_count += 1
            end
        else
            @warn "[MIGRATION] File not found: $old_filename (expected for polygon $(polygon.id))"
            failed_count += 1
        end
    end
    
    # Save updated metadata if any files were renamed
    if renamed_count > 0
        save_multiclass_metadata(image_index, polygons)
        println("[MIGRATION] Updated metadata with $(renamed_count) new filenames")
    end
    
    println("[MIGRATION] Complete: $(renamed_count) renamed, $(failed_count) failed")
    return failed_count == 0
end

"""
    load_polygon_mask_mmap(image_index::Int) -> Union{Matrix{RGB{N0f8}}, Nothing}

Load saved polygon mask from .bin file using memory mapping (OPTIMIZED VERSION).

# Arguments
- `image_index::Int`: Image index (1-306)

# Returns
- `Matrix{RGB{N0f8}}`: RGB mask in landscape orientation (756×1008, matches UI display)
  - N0f8 = Normalized 0-255 as fixed-point 0.0-1.0 (no float conversion overhead)
- `nothing`: If file doesn't exist

# Process
1. Check for .bin mask in dataset folder: {index}_polygon_mask.bin
2. Load via mmap as UInt8 (same as storage format) - quarter resolution (1008×756 portrait)
3. Reinterpret UInt8 → RGB{N0f8} (zero-copy conversion)
4. Apply rotr90() to landscape orientation (756×1008) - MATCHES input image pipeline
5. Return mask (already at display resolution, NO RESIZE NEEDED!)

# Performance
- Memory: 3 bytes/pixel (vs 12 bytes for Float32)
- Conversion: ~2-5x faster (reinterpret vs float division)
- 2-6x faster than PNG loading (no decode, no resize)
- 64x less memory usage (quarter-res vs full-res)

# Note
RGB{N0f8} is fully compatible with GLMakie.image!() and Colors.jl operations.
"""
function load_polygon_mask_mmap(image_index::Int)
    local total_time = 0.0
    local file_check_time = 0.0
    local mmap_load_time = 0.0
    local array_construct_time = 0.0
    local rotation_time = 0.0
    
    total_time = @elapsed begin
        try
            # Construct path to .bin mask file
            # Use base_path from Config (C:/Syncthing/Datasets) + original_quarter_res + INDEX_polygon_mask.bin
            local mask_bin_path = joinpath(base_path, "original_quarter_res", "$(image_index)_polygon_mask.bin")
            
            file_check_time = @elapsed begin
                if !isfile(mask_bin_path)
                    return nothing
                end
            end
            
            # Dimensions for quarter-res mask (portrait orientation before rotr90)
            # MUST MATCH input image storage: 756 height × 1008 width (portrait)
            local dims = (756, 1008, 3)  # H×W×C in portrait
            
            local mapped_data = nothing
            mmap_load_time = @elapsed begin
                mapped_data = load_image_mmap(mask_bin_path, dims, UInt8)
            end
            
            # OPTIMIZED: Use reinterpret + reshape to avoid explicit loop
            # Convert UInt8 H×W×3 to RGB{N0f8} H×W (N0f8 = normalized 0-255 as 0.0-1.0)
            local h, w, c = dims
            local mask_matrix = nothing
            
            array_construct_time = @elapsed begin
                # Create RGB{N0f8} array from UInt8 channels
                # N0f8 is Colors.jl's fixed-point type that stores 0-255 as 0.0-1.0 without conversion
                mask_matrix = Array{RGB{N0f8}}(undef, h, w)
                @inbounds for i in 1:h, j in 1:w
                    mask_matrix[i, j] = RGB{N0f8}(
                        reinterpret(N0f8, mapped_data[i, j, 1]),
                        reinterpret(N0f8, mapped_data[i, j, 2]),
                        reinterpret(N0f8, mapped_data[i, j, 3])
                    )
                end
            end
            
            # Apply rotr90 to match UI coordinate system (landscape display)
            local mask_rotated = nothing
            rotation_time = @elapsed begin
                mask_rotated = rotr90(mask_matrix)
            end
            
            println("[PERF-MASK-MMAP] Image $image_index: total=$(round(total_time*1000, digits=2))ms, file_check=$(round(file_check_time*1000, digits=2))ms, mmap=$(round(mmap_load_time*1000, digits=2))ms, array_construct=$(round(array_construct_time*1000, digits=2))ms, rotate=$(round(rotation_time*1000, digits=2))ms")
            println("[MASK-LOAD-MMAP] Loaded .bin mask for image $(image_index): $(size(mask_matrix)) RGB{N0f8} → rotr90 → $(size(mask_rotated))")
            
            return mask_rotated
            
        catch e
            @warn "[MASK-LOAD-MMAP] Failed to load .bin mask for image $(image_index): $e"
            return nothing
        end
    end
end

"""
    load_class_mask_for_display(image_index::Int, target_size::Union{Tuple{Int,Int}, Nothing}=nothing, sets_index_map::Dict{Int,Int}=Dict{Int,Int}()) -> Union{Matrix{RGB{Float32}}, Nothing}

Load class segmentation mask from sets[image_index][2] (output) for display.

# Arguments
- `image_index::Int`: Image index (1-306)
- `target_size::Union{Tuple{Int,Int}, Nothing}`: Target display size (H×W) for resizing
- `sets_index_map::Dict{Int,Int}`: Map from image_index to array position in sets

# Returns
- `Matrix{RGB{Float32}}`: Class mask as RGB visualization OR
- `nothing`: If mask doesn't exist

# Process
1. Lookup image in sets using index map
2. Extract output_img (class segmentation mask)
3. Convert class probabilities to RGB using class colors
4. Rotate to landscape orientation (rotr90)
5. Resize to target display size if provided
"""
function load_class_mask_for_display(image_index::Int, target_size::Union{Tuple{Int,Int}, Nothing}=nothing, sets_index_map::Dict{Int,Int}=Dict{Int,Int}())
    # Lookup image in sets
    local array_pos = get(sets_index_map, image_index, nothing)
    if isnothing(array_pos)
        return nothing
    end
    
    # Get output mask (class segmentation)
    local output_img = sets[array_pos][2]
    if isnothing(output_img)
        return nothing
    end
    
    # Get mask data and dimensions
    local mask_data = data(output_img)  # Should be H × W × C (portrait orientation)
    local h, w, num_classes = size(mask_data)
    
    # Convert class probabilities to RGB visualization
    # Use class colors from CLASS_COLORS_RGB
    local rgb_mask = fill(Bas3ImageSegmentation.RGB{Float32}(0, 0, 0), h, w)
    
    for i in 1:h
        for j in 1:w
            # Find dominant class for this pixel
            local max_prob = 0.0f0
            local max_class_idx = 0
            
            for c in 1:num_classes
                if mask_data[i, j, c] > max_prob
                    max_prob = mask_data[i, j, c]
                    max_class_idx = c
                end
            end
            
            # Apply class color if probability > threshold
            if max_prob > 0.5f0 && max_class_idx > 0 && max_class_idx <= length(CLASS_COLORS_RGB)
                # Get class color by index (CLASS_COLORS_RGB is an array)
                local class_color = CLASS_COLORS_RGB[max_class_idx]
                
                # Convert color to RGB{Float32}
                if class_color isa Symbol
                    # Symbol color (like :goldenrod, :black) - convert using GLMakie
                    local rgb_parsed = Bas3GLMakie.GLMakie.to_color(class_color)
                    rgb_mask[i, j] = Bas3ImageSegmentation.RGB{Float32}(rgb_parsed.r, rgb_parsed.g, rgb_parsed.b)
                else
                    # Already an RGBf - extract components
                    rgb_mask[i, j] = Bas3ImageSegmentation.RGB{Float32}(class_color.r, class_color.g, class_color.b)
                end
            end
        end
    end
    
    # Rotate to landscape orientation (rotr90)
    local rotated_mask = rotr90(rgb_mask)
    
    # Resize if target size provided
    if !isnothing(target_size)
        local target_h, target_w = target_size
        local current_h, current_w = size(rotated_mask)
        
        if (target_h, target_w) != (current_h, current_w)
            # Simple nearest-neighbor resize
            local resized = fill(Bas3ImageSegmentation.RGB{Float32}(0, 0, 0), target_h, target_w)
            local scale_h = current_h / target_h
            local scale_w = current_w / target_w
            
            for i in 1:target_h
                for j in 1:target_w
                    local src_i = min(current_h, max(1, round(Int, i * scale_h)))
                    local src_j = min(current_w, max(1, round(Int, j * scale_w)))
                    resized[i, j] = rotated_mask[src_i, src_j]
                end
            end
            
            return resized
        end
    end
    
    return rotated_mask
end

"""
    load_mask_for_display(image_index::Int, target_size::Union{Tuple{Int,Int}, Nothing}=nothing) -> Union{Matrix, Nothing}

Load polygon mask for display, trying .bin first (fast), then PNG fallback (slow).

# Arguments
- `image_index::Int`: Image index (1-306)
- `target_size::Union{Tuple{Int,Int}, Nothing}`: Target display size (H×W), required only if PNG fallback is used

# Returns
- `Matrix{RGB{N0f8}}`: Mask from .bin (UInt8-backed, efficient) OR
- `Matrix{RGB{Float32}}`: Mask from PNG fallback (slower) OR
- `nothing`: If no mask exists

# Process
1. Try .bin loading (FAST - already at quarter-res with rotr90, returns RGB{N0f8})
2. Fallback to PNG loading (SLOW - full-res, needs resize, returns RGB{Float32})
"""
function load_mask_for_display(image_index::Int, target_size::Union{Tuple{Int,Int}, Nothing}=nothing)
    # Try .bin first (fast, correct resolution, already rotated)
    local mask_display = load_polygon_mask_mmap(image_index)
    if !isnothing(mask_display)
        return mask_display
    end
    
    # Fallback to PNG (old method - slow, needs resize)
    local mask_fullres = load_polygon_mask_if_exists(image_index)
    if !isnothing(mask_fullres) && !isnothing(target_size)
        return resize_mask_to_display(mask_fullres, target_size)
    end
    
    return nothing
end

"""
    resize_mask_to_display(mask_fullres::Matrix{RGB{Float32}}, target_size::Tuple{Int,Int}) -> Matrix{RGB{Float32}}

Resize full-resolution RGB mask to match display resolution.

# Arguments
- `mask_fullres::Matrix{RGB{Float32}}`: Full-resolution mask (e.g., 4032×3024)
- `target_size::Tuple{Int,Int}`: Target size (height, width) from displayed image

# Returns
- `Matrix{RGB{Float32}}`: Resized mask matching display dimensions

# Algorithm
Uses bilinear interpolation per RGB channel to preserve smooth values.
"""
function resize_mask_to_display(mask_fullres::Matrix{Bas3ImageSegmentation.RGB{Float32}}, target_size::Tuple{Int,Int})
    local h_full, w_full = size(mask_fullres)
    local h_target, w_target = target_size
    
    # Create target mask
    local mask_resized = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h_target, w_target)
    
    # Scale factors
    local scale_y = Float32(h_full - 1) / Float32(h_target - 1)
    local scale_x = Float32(w_full - 1) / Float32(w_target - 1)
    
    # Bilinear interpolation per channel
    for i in 1:h_target, j in 1:w_target
        # Map target coordinates to source coordinates
        local y_src = (i - 1) * scale_y + 1
        local x_src = (j - 1) * scale_x + 1
        
        # Get integer parts and fractional parts
        local y0 = floor(Int, y_src)
        local x0 = floor(Int, x_src)
        local y1 = min(y0 + 1, h_full)
        local x1 = min(x0 + 1, w_full)
        
        local dy = y_src - y0
        local dx = x_src - x0
        
        # Clamp to valid range
        y0 = clamp(y0, 1, h_full)
        x0 = clamp(x0, 1, w_full)
        
        # Get four neighboring pixels
        local c00 = mask_fullres[y0, x0]
        local c01 = mask_fullres[y0, x1]
        local c10 = mask_fullres[y1, x0]
        local c11 = mask_fullres[y1, x1]
        
        # Bilinear interpolation per channel
        local r0 = c00.r * (1 - dx) + c01.r * dx
        local r1 = c10.r * (1 - dx) + c11.r * dx
        local r = r0 * (1 - dy) + r1 * dy
        
        local g0 = c00.g * (1 - dx) + c01.g * dx
        local g1 = c10.g * (1 - dx) + c11.g * dx
        local g = g0 * (1 - dy) + g1 * dy
        
        local b0 = c00.b * (1 - dx) + c01.b * dx
        local b1 = c10.b * (1 - dx) + c11.b * dx
        local b = b0 * (1 - dy) + b1 * dy
        
        mask_resized[i, j] = Bas3ImageSegmentation.RGB{Float32}(
            clamp(r, 0.0f0, 1.0f0),
            clamp(g, 0.0f0, 1.0f0),
            clamp(b, 0.0f0, 1.0f0)
        )
    end
    
    return mask_resized
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
    # Get image dimensions - handle both Matrix and v__Image_Data types
    local h, w
    if img isa AbstractMatrix
        # img is already a Matrix (e.g., Matrix{RGB{Float32}})
        h, w = Base.size(img, 1), Base.size(img, 2)
    else
        # img is v__Image_Data type
        local img_data = data(img)
        h, w = Base.size(img_data, 1), Base.size(img_data, 2)
    end
    
    if length(vertices) < 3
        # Return empty mask
        return falses(h, w)
    end
    
    # GLMakie's image! displays with standard image convention:
    # - Y coordinate matches matrix row index (Y increases downward)
    # - X coordinate matches matrix col index (X increases rightward)
    # - Mouse position (x, y) directly corresponds to (col, row)
    # Therefore, NO coordinate transformation is needed
    
    println("[POLYGON-MASK] Image size: $(h)x$(w), vertices: $(length(vertices))")
    println("[POLYGON-MASK] Vertex coordinates (x=col, y=row): ", vertices)
    
    # Get AABB for optimization
    local min_x, max_x, min_y, max_y = polygon_bounds_aabb(vertices)
    
    # Convert to pixel indices (clamp to image bounds)
    # vertices are in (x, y) = (col, row) format
    local col_start = max(1, floor(Int, min_x))
    local col_end = min(w, ceil(Int, max_x))
    local row_start = max(1, floor(Int, min_y))
    local row_end = min(h, ceil(Int, max_y))
    
    println("[POLYGON-MASK] AABB: rows=$(row_start):$(row_end), cols=$(col_start):$(col_end)")
    
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
# MULTI-CLASS POLYGON METADATA (JSON Serialization)
# ============================================================================

"""
    save_multiclass_metadata(image_index::Int, polygons::Vector{PolygonEntry}) -> Bool

Save polygon metadata to JSON file in patient folder.

# File Format
{
  "version": 2,
  "image_index": 1,
  "polygons": [
    {
      "id": 1,
      "class": "redness",
      "vertices": [[120.5, 340.2], [180.3, 350.1], ...],
      "complete": true,
      "lch_data": {"L_median": 45.2, "C_median": 32.1, "h_median": 25.3, "count": 1250}
    }
  ]
}
"""
function save_multiclass_metadata(image_index::Int, polygons::Vector{PolygonEntry})
    local base_dir = dirname(get_database_path())
    local patient_num = lpad(image_index, 3, '0')
    local json_path = joinpath(base_dir, "MuHa_$(patient_num)", 
                               "MuHa_$(patient_num)_polygon_metadata.json")
    
    try
        # Convert to JSON-serializable format
        poly_data = []
        for poly in polygons
            push!(poly_data, Dict(
                "id" => poly.id,
                "class" => String(poly.class),
                "class_name" => poly.class_name,
                "sample_number" => poly.sample_number,
                "vertices" => [[Float64(v[1]), Float64(v[2])] for v in poly.vertices],
                "complete" => poly.complete,
                "mask_file" => construct_polygon_mask_filename(image_index, poly),  # NEW: Add mask filename
                "lch_data" => isnothing(poly.lch_data) ? nothing : Dict(
                    "L_median" => poly.lch_data.median_l,
                    "C_median" => poly.lch_data.median_c,
                    "h_median" => poly.lch_data.median_h,
                    "count" => poly.lch_data.count
                )
            ))
        end
        
        metadata = Dict(
            "version" => 3,  # CHANGED: Version 2 → 3
            "image_index" => image_index,
            "mask_format" => "separate_files",  # NEW: Indicate mask format
            "polygons" => poly_data
        )
        
        # Write JSON
        json_str = JSON3.write(metadata)
        write(json_path, json_str)
        
        println("[METADATA] Saved $(length(polygons)) polygons to $json_path (version 3)")
        return true
    catch e
        @warn "[METADATA] Failed to save: $e"
        return false
    end
end

"""
    load_multiclass_metadata(image_index::Int) -> Vector{PolygonEntry}

Load polygon metadata from JSON file. Returns empty array if file doesn't exist.
"""
function load_multiclass_metadata(image_index::Int)
    local base_dir = dirname(get_database_path())
    local patient_num = lpad(image_index, 3, '0')
    local json_path = joinpath(base_dir, "MuHa_$(patient_num)", 
                               "MuHa_$(patient_num)_polygon_metadata.json")
    
    if !isfile(json_path)
        return PolygonEntry[]
    end
    
    try
        json_str = read(json_path, String)
        data = JSON3.read(json_str)
        
        # Check version (support version 2 and 3)
        local version = get(data, :version, 1)
        if version != 2 && version != 3
            @warn "[METADATA] Unsupported version: $version (expected 2 or 3)"
            return PolygonEntry[]
        end
        
        # Parse polygons
        polygons = PolygonEntry[]
        for poly_data in data.polygons
            vertices = [Bas3GLMakie.GLMakie.Point2f(Float32(v[1]), Float32(v[2])) for v in poly_data.vertices]
            
            lch_data = nothing
            if !isnothing(poly_data.lch_data)
                lch_data = (
                    median_l = Float64(poly_data.lch_data.L_median),
                    median_c = Float64(poly_data.lch_data.C_median),
                    median_h = Float64(poly_data.lch_data.h_median),
                    count = Int(poly_data.lch_data.count)
                )
            end
            
            # Get class_name and sample_number (with defaults for backward compatibility)
            class_name = get(poly_data, :class_name, "")
            sample_number = get(poly_data, :sample_number, 1)
            
            # NEW: Get mask_file field (version 3), ignore if missing
            # Note: PolygonEntry struct doesn't have mask_file field yet,
            # but we read it for future use in load_polygon_masks_individual()
            # which checks poly_data directly from JSON
            
            push!(polygons, PolygonEntry(
                Int(poly_data.id),
                Symbol(poly_data.class),
                String(class_name),
                Int(sample_number),
                vertices,
                Bool(poly_data.complete),
                lch_data
            ))
        end
        
        println("[METADATA] Loaded $(length(polygons)) polygons from $json_path (version $version)")
        return polygons
    catch e
        @warn "[METADATA] Failed to load: $e"
        return PolygonEntry[]
    end
end

# ============================================================================
# POLYGON-BASED L*C*h EXTRACTION (Manual ROI Selection)
# ============================================================================

# ============================================================================
# L*C*h EXTRACTION FROM POLYGON REGIONS
# ============================================================================

"""
    extract_polygon_lch_values(input_img, polygon_vertices, img_rotated)

Extract L*C*h values from polygon region in input image.

# Arguments
- `input_img`: Raw input image (NOT rotated, for data access)
- `polygon_vertices`: Vector{Point2f} in axis coordinates (rotated space)
- `img_rotated`: Rotated image (for dimensions)

# Returns
NamedTuple with:
- l_values, c_values, h_values: Arrays of L*C*h values
- median_l, median_c, median_h: Median values
- count: Number of pixels in polygon

# Notes
- Handles coordinate transformation for rotr90 images
- Returns empty data if polygon has < 3 vertices
"""
function extract_polygon_lch_values(input_img, polygon_vertices::Vector{Bas3GLMakie.GLMakie.Point2f}, img_rotated)
    # Return empty if invalid polygon
    if length(polygon_vertices) < 3
        return (
            l_values = Float64[],
            c_values = Float64[],
            h_values = Float64[],
            median_l = NaN,
            median_c = NaN,
            median_h = NaN,
            count = 0
        )
    end
    
    # Create polygon mask in rotated space
    local mask_rotated = create_polygon_mask(img_rotated, polygon_vertices)
    
    # Transform mask back to original orientation
    # rotr90 inverse is rotl90
    local mask_original = rotl90(mask_rotated)
    
    # Get input data in original orientation
    local input_data = data(input_img)
    
    # Find pixels inside polygon
    local pixel_indices = findall(mask_original)
    local n_pixels = length(pixel_indices)
    
    if n_pixels == 0
        return (
            l_values = Float64[],
            c_values = Float64[],
            h_values = Float64[],
            median_l = NaN,
            median_c = NaN,
            median_h = NaN,
            count = 0
        )
    end
    
    # Pre-allocate arrays
    local l_values = Vector{Float64}(undef, n_pixels)
    local c_values = Vector{Float64}(undef, n_pixels)
    local h_values = Vector{Float64}(undef, n_pixels)
    
    # Extract L*C*h values
    @inbounds for (i, idx) in enumerate(pixel_indices)
        local r, c = idx[1], idx[2]
        local red = input_data[r, c, 1]
        local green = input_data[r, c, 2]
        local blue = input_data[r, c, 3]
        local rgb_pixel = RGB(red, green, blue)
        local lch_pixel = LCHab(rgb_pixel)
        
        l_values[i] = lch_pixel.l
        c_values[i] = lch_pixel.c
        h_values[i] = lch_pixel.h
    end
    
    # Compute medians
    local median_l = median(l_values)
    local median_c = median(c_values)
    local median_h = median(h_values)
    
    println("[POLYGON-LCH] Extracted $(n_pixels) pixels: L*=$(round(median_l, digits=1)), C*=$(round(median_c, digits=1)), h°=$(round(median_h, digits=1))")
    
    return (
        l_values = l_values,
        c_values = c_values,
        h_values = h_values,
        median_l = median_l,
        median_c = median_c,
        median_h = median_h,
        count = n_pixels
    )
end

"""
    extract_class_lch_values(input_img, output_img, classes)

Extract L*C*h (LCHab) values for each class based on segmentation mask.
L*C*h is a perceptually uniform color space based on L*a*b*.

Returns Dict mapping class symbol to NamedTuple with:
- l_values, c_values, h_values: Arrays for histogram/analysis
- median_l, median_c, median_h: Median values
- count: Number of pixels

Color components:
- L* (Lightness): 0-100, perceptual lightness
- C* (Chroma): 0-100+, color intensity/saturation
- h° (Hue): 0-360°, color angle (0°=red, 90°=yellow, 180°=green, 270°=blue)
"""
function extract_class_lch_values(input_img, output_img, classes)
    local input_data = data(input_img)
    local output_data = data(output_img)
    local output_classes = shape(output_img)  # Get actual class channels in output
    local results = Dict{Symbol, NamedTuple}()
    
    for class in classes
        if class == :background
            continue
        end
        
        # Find the channel index for this class in the output
        local class_idx = findfirst(==(class), output_classes)
        
        if isnothing(class_idx)
            # Class not present in this output image
            results[class] = (
                l_values = Float64[],
                c_values = Float64[],
                h_values = Float64[],
                median_l = NaN,
                median_c = NaN,
                median_h = NaN,
                count = 0
            )
            continue
        end
        
        # Get class mask (pixels belonging to this class)
        local class_mask = output_data[:, :, class_idx] .> 0.5
        
        if !any(class_mask)
            results[class] = (
                l_values = Float64[],
                c_values = Float64[],
                h_values = Float64[],
                median_l = NaN,
                median_c = NaN,
                median_h = NaN,
                count = 0
            )
            continue
        end
        
        # Count pixels for pre-allocation
        local pixel_indices = findall(class_mask)
        local n_pixels = length(pixel_indices)
        
        # Pre-allocate arrays
        local l_values = Vector{Float64}(undef, n_pixels)
        local c_values = Vector{Float64}(undef, n_pixels)
        local h_values = Vector{Float64}(undef, n_pixels)
        
        # Extract LCh values from input image at masked locations
        @inbounds for (i, idx) in enumerate(pixel_indices)
            local r, c = idx[1], idx[2]
            # Get RGB values from input data array (row, col, channel)
            local red = input_data[r, c, 1]
            local green = input_data[r, c, 2]
            local blue = input_data[r, c, 3]
            local rgb_pixel = RGB(red, green, blue)
            
            # Convert RGB → LCHab using Colors.jl
            local lch_pixel = LCHab(rgb_pixel)
            
            l_values[i] = lch_pixel.l   # 0-100
            c_values[i] = lch_pixel.c   # 0-100+ (unbounded, typically < 150)
            h_values[i] = lch_pixel.h   # 0-360°
        end
        
        # Compute medians
        local median_l = n_pixels > 0 ? median(l_values) : NaN
        local median_c = n_pixels > 0 ? median(c_values) : NaN
        local median_h = n_pixels > 0 ? median(h_values) : NaN
        
        results[class] = (
            l_values = l_values,
            c_values = c_values,
            h_values = h_values,
            median_l = median_l,
            median_c = median_c,
            median_h = median_h,
            count = n_pixels
        )
    end
    
    return results
end

"""
    extract_lch_from_polygon_mask(input_img, mask_rgb::Matrix{RGB{Float32}})

Extract L*C*h color values from a saved polygon mask file.
Similar to extract_polygon_lch_values but uses a saved mask instead of polygon vertices.

# Arguments
- `input_img`: Input image (portrait orientation, 1008×756×3)
- `mask_rgb`: RGB polygon mask (landscape orientation from load_polygon_mask_mmap)

# Returns
NamedTuple with:
- `l_values`: Vector of L* values (0-100) for all mask pixels
- `c_values`: Vector of C* values (0-150+) for all mask pixels
- `h_values`: Vector of h° values (0-360) for all mask pixels
- `median_l`, `median_c`, `median_h`: Median values
- `count`: Number of pixels in mask

# Example
```julia
mask_rgb = load_polygon_mask_mmap(1)
lch_data = extract_lch_from_polygon_mask(input_img, mask_rgb)
println("Median L*: ", lch_data.median_l)
```
"""
function extract_lch_from_polygon_mask(input_img, mask_rgb)
    # Reverse rotation: mask is landscape, input is portrait
    # mask is rotl90(portrait), so inverse is rotr90(landscape)
    local mask_portrait = rotr90(mask_rgb)
    
    # Get input data (portrait orientation: 1008×756×3)
    local input_data = data(input_img)
    local h, w = size(mask_portrait)
    
    # Find mask pixels (threshold to identify white/colored pixels vs black)
    local mask_pixels = findall(mask_portrait) do pixel
        # Consider pixel part of mask if any channel > threshold
        pixel.r > 0.1 || pixel.g > 0.1 || pixel.b > 0.1
    end
    
    local n_pixels = length(mask_pixels)
    
    if n_pixels == 0
        return (
            l_values = Float64[],
            c_values = Float64[],
            h_values = Float64[],
            median_l = NaN,
            median_c = NaN,
            median_h = NaN,
            count = 0
        )
    end
    
    # Pre-allocate arrays
    local l_values = Vector{Float64}(undef, n_pixels)
    local c_values = Vector{Float64}(undef, n_pixels)
    local h_values = Vector{Float64}(undef, n_pixels)
    
    # Extract L*C*h values
    @inbounds for (i, idx) in enumerate(mask_pixels)
        local r, c = idx[1], idx[2]
        
        # Get RGB from input image
        local red = input_data[r, c, 1]
        local green = input_data[r, c, 2]
        local blue = input_data[r, c, 3]
        local rgb_pixel = RGB(red, green, blue)
        
        # Convert to L*C*h
        local lch_pixel = LCHab(rgb_pixel)
        
        l_values[i] = lch_pixel.l   # 0-100
        c_values[i] = lch_pixel.c   # 0-150+
        h_values[i] = lch_pixel.h   # 0-360°
    end
    
    # Compute statistics
    local median_l = median(l_values)
    local median_c = median(c_values)
    local median_h = median(h_values)
    
    return (
        l_values = l_values,
        c_values = c_values,
        h_values = h_values,
        median_l = median_l,
        median_c = median_c,
        median_h = median_h,
        count = n_pixels
    )
end

"""
    compute_lch_from_saved_masks(entries, cached_lookup::Dict)

Compute L*C*h values from saved polygon mask .bin files for all patient images.
Automatically loads masks and extracts color data. Returns NaN for images without masks.

# Arguments
- `entries`: Vector of patient entries (from database)
- `cached_lookup`: Dict mapping image_index to (input_raw, output_raw, input_rotated)

# Returns
- Vector of NamedTuples (one per entry, NaN values if no mask exists)

# Example
```julia
lch_data = compute_lch_from_saved_masks(current_entries[], patient_image_cache[patient_id])
```
"""
function compute_lch_from_saved_masks(entries, cached_lookup::Dict)
    local results = []
    local total_extract_time = 0.0
    local total_mask_load_time = 0.0
    
    for entry in entries
        # Load mask .bin file
        local mask_load_start = time()
        local mask_rgb = load_polygon_mask_mmap(entry.image_index)
        total_mask_load_time += (time() - mask_load_start)
        
        if !isnothing(mask_rgb)
            # Get input image from cache
            local img_data = get(cached_lookup, entry.image_index, nothing)
            
            if !isnothing(img_data) && !isnothing(img_data.input_raw)
                # Extract L*C*h from mask
                local extract_start = time()
                local lch_result = extract_lch_from_polygon_mask(img_data.input_raw, mask_rgb)
                total_extract_time += (time() - extract_start)
                
                push!(results, lch_result)
                println("[MASK-COMPUTE] Image $(entry.image_index): $(lch_result.count) pixels, L*=$(round(lch_result.median_l, digits=1))")
            else
                # No image data in cache
                push!(results, (
                    l_values = Float64[],
                    c_values = Float64[],
                    h_values = Float64[],
                    median_l = NaN,
                    median_c = NaN,
                    median_h = NaN,
                    count = 0
                ))
                println("[MASK-COMPUTE] Image $(entry.image_index): No image data in cache")
            end
        else
            # No mask file exists
            push!(results, (
                l_values = Float64[],
                c_values = Float64[],
                h_values = Float64[],
                median_l = NaN,
                median_c = NaN,
                median_h = NaN,
                count = 0
            ))
            println("[MASK-COMPUTE] Image $(entry.image_index): No saved mask")
        end
    end
    
    println("[PERF-LCH-COMPUTE] Total mask load: $(round(total_mask_load_time*1000, digits=2))ms, Total extract: $(round(total_extract_time*1000, digits=2))ms")
    
    return results
end

"""
    compute_lch_from_saved_masks_multiclass(entries, cached_lookup::Dict)
    -> Dict{Symbol, Vector{Union{NamedTuple, Nothing}}}

Compute L*C*h data per class across all images using saved JSON metadata.

Returns: Dict mapping class symbol to array of L*C*h data (one per image).
"""
function compute_lch_from_saved_masks_multiclass(entries, cached_lookup::Dict)
    # Initialize result dict
    lch_per_class = Dict{Symbol, Vector{Union{NamedTuple, Nothing}}}()
    for class in WOUND_CLASSES
        lch_per_class[class] = fill(nothing, length(entries))
    end
    
    for (img_idx, entry) in enumerate(entries)
        # Load polygon metadata
        polygons = load_multiclass_metadata(entry.image_index)
        
        if isempty(polygons)
            continue  # No polygons for this image
        end
        
        # Get image data
        img_data = get(cached_lookup, entry.image_index, nothing)
        if isnothing(img_data) || isnothing(img_data.input_raw)
            continue
        end
        
        # Group polygons by class and use their cached L*C*h data
        for poly in polygons
            if poly.complete && !isnothing(poly.lch_data)
                # Use cached L*C*h data from polygon
                lch_per_class[poly.class][img_idx] = poly.lch_data
                println("[MULTI-LCH] Image $(entry.image_index), class $(poly.class): $(poly.lch_data.count) pixels")
            end
        end
    end
    
    return lch_per_class
end

# H/S timeline and mini histograms removed - now using polygon-based L*C*h analysis

"""
    create_lch_timeline!(timeline_grid, entries, lch_data_list)

Create L*C*h timeline plot showing color evolution over time from polygon regions.
Displays three vertically stacked axes (L*, C*, h°) for clear separation.

L*C*h is a perceptually uniform color space based on L*a*b*.
- L* (Lightness): 0-100, whether wound becomes paler
- C* (Chroma): 0-100+, intensity of color
- h° (Hue): 0-360°, actual color tone

# Arguments
- `timeline_grid`: GridLayout to place the plot
- `entries`: Vector of entry dictionaries with date field
- `lch_data_list`: Vector of NamedTuple with L*C*h data per polygon

# Returns
- Tuple of three Axis objects (ax_l, ax_c, ax_h) or nothing if no data
"""
function create_lch_timeline!(timeline_grid, entries, lch_data_list)
    # Skip if no data
    if isempty(entries) || isempty(lch_data_list)
        Bas3GLMakie.GLMakie.Label(
            timeline_grid[1, 1],
            "Keine Polygondaten\n\nBitte Polygone zeichnen",
            fontsize=12,
            color=:gray,
            halign=:center
        )
        return nothing
    end
    
    # Extract L, C, h values from polygon data across all images
    # Keep NaN for missing data to show all timepoints
    local l_values = Float64[]
    local c_values = Float64[]
    local h_values = Float64[]
    local all_indices = Int[]
    
    for (i, lch_data) in enumerate(lch_data_list)
        # lch_data is now a NamedTuple (not Dict)
        push!(all_indices, i)
        
        if !isnothing(lch_data) && lch_data.count > 0 && !isnan(lch_data.median_l)
            # Normalize L from 0-100 to 0-1
            push!(l_values, lch_data.median_l / 100.0)
            # Normalize C from 0-150 to 0-1 (assume max chroma ~150)
            push!(c_values, lch_data.median_c / 150.0)
            # Normalize h from 0-360 to 0-1
            push!(h_values, lch_data.median_h / 360.0)
        else
            # Keep NaN for missing data (will create gaps in plot)
            push!(l_values, NaN)
            push!(c_values, NaN)
            push!(h_values, NaN)
        end
    end
    
    # Check if we have ANY valid data
    local has_valid_data = any(!isnan, l_values)
    
    # Skip if no valid data - show THREE EMPTY AXES with placeholder text
    if !has_valid_data
        println("[LCH-TIMELINE] No valid polygon data, showing three empty axes")
        
        # Create empty L* axis (top)
        local ax_l = Bas3GLMakie.GLMakie.Axis(
            timeline_grid[1, 1],
            title = "L*C*h Verlauf (Polygonregion)",
            titlesize = 12,
            xlabel = "",
            ylabel = "L* (0-1)",
            xlabelsize = 9,
            ylabelsize = 9,
            xticklabelsize = 7,
            yticklabelsize = 7,
            xticklabelsvisible = false
        )
        Bas3GLMakie.GLMakie.ylims!(ax_l, 0, 1)
        Bas3GLMakie.GLMakie.xlims!(ax_l, 0, 1)
        
        # Create empty C* axis (middle)
        local ax_c = Bas3GLMakie.GLMakie.Axis(
            timeline_grid[2, 1],
            xlabel = "",
            ylabel = "C* (0-1)",
            xlabelsize = 9,
            ylabelsize = 9,
            xticklabelsize = 7,
            yticklabelsize = 7,
            xticklabelsvisible = false
        )
        Bas3GLMakie.GLMakie.ylims!(ax_c, 0, 1)
        Bas3GLMakie.GLMakie.xlims!(ax_c, 0, 1)
        
        # Create empty h° axis (bottom)
        local ax_h = Bas3GLMakie.GLMakie.Axis(
            timeline_grid[3, 1],
            xlabel = "Zeitpunkt",
            ylabel = "h° (0-1)",
            xlabelsize = 9,
            ylabelsize = 9,
            xticklabelsize = 7,
            yticklabelsize = 7
        )
        Bas3GLMakie.GLMakie.ylims!(ax_h, 0, 1)
        Bas3GLMakie.GLMakie.xlims!(ax_h, 0, 1)
        
        # Add centered placeholder text to middle axis
        Bas3GLMakie.GLMakie.text!(
            ax_c,
            0.5, 0.5,
            text = "Keine Polygondaten\n\nBitte Polygone zeichnen und schließen",
            align = (:center, :center),
            fontsize = 12,
            color = :gray
        )
        
        # Link X-axes
        Bas3GLMakie.GLMakie.linkxaxes!(ax_l, ax_c, ax_h)
        
        # Set row sizes: equal space for three axes
        Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 1, 180)
        Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 2, 180)
        Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 3, 180)
        
        return (ax_l, ax_c, ax_h)
    end
    
    # Data is in order by image index (left to right in UI)
    # Use timepoint-based X-axis (T1, T2, T3, ...) like CompareStatisticsUI
    local timepoints = collect(1:length(all_indices))
    local timepoint_labels = ["T$i" for i in timepoints]
    
    # Fixed Y-axis limits 0-1 for all axes (no dynamic scaling)
    local l_ylim_min = 0.0
    local l_ylim_max = 1.0
    
    local c_ylim_min = 0.0
    local c_ylim_max = 1.0
    
    local h_ylim_min = 0.0
    local h_ylim_max = 1.0
    
    # ========================================================================
    # THREE VERTICALLY STACKED AXES (L*, C*, h°)
    # ========================================================================
    
    # Create L* axis (top)
    local ax_l = Bas3GLMakie.GLMakie.Axis(
        timeline_grid[1, 1],
        title = "L*C*h Verlauf (Polygonregion)",
        titlesize = 12,
        xlabel = "",  # No label on top axis
        ylabel = "L* (0-1)",
        xlabelsize = 9,
        ylabelsize = 9,
        xticklabelsize = 7,
        yticklabelsize = 7,
        xticklabelsvisible = false,  # Hide X tick labels on top axis
        xticks = (timepoints, timepoint_labels)
    )
    Bas3GLMakie.GLMakie.ylims!(ax_l, l_ylim_min, l_ylim_max)
    
    # Plot L* (blue, solid, circle markers) - NaN values create gaps
    Bas3GLMakie.GLMakie.scatterlines!(
        ax_l, 
        timepoints, 
        l_values;
        color = :blue,
        linewidth = 2,
        linestyle = :solid,
        marker = :circle,
        markersize = 10
    )
    
    # Create C* axis (middle)
    local ax_c = Bas3GLMakie.GLMakie.Axis(
        timeline_grid[2, 1],
        xlabel = "",  # No label on middle axis
        ylabel = "C* (0-1)",
        xlabelsize = 9,
        ylabelsize = 9,
        xticklabelsize = 7,
        yticklabelsize = 7,
        xticklabelsvisible = false,  # Hide X tick labels on middle axis
        xticks = (timepoints, timepoint_labels)
    )
    Bas3GLMakie.GLMakie.ylims!(ax_c, c_ylim_min, c_ylim_max)
    
    # Plot C* (red, solid, diamond markers) - NaN values create gaps
    Bas3GLMakie.GLMakie.scatterlines!(
        ax_c,
        timepoints,
        c_values;
        color = :red,
        linewidth = 2,
        linestyle = :solid,
        marker = :diamond,
        markersize = 10
    )
    
    # Create h° axis (bottom)
    local ax_h = Bas3GLMakie.GLMakie.Axis(
        timeline_grid[3, 1],
        xlabel = "Zeitpunkt",  # Only bottom axis shows xlabel
        ylabel = "h° (0-1)",
        xlabelsize = 9,
        ylabelsize = 9,
        xticklabelsize = 7,
        yticklabelsize = 7,
        xticks = (timepoints, timepoint_labels)
    )
    Bas3GLMakie.GLMakie.ylims!(ax_h, h_ylim_min, h_ylim_max)
    
    # Plot h° (green, solid, rectangle markers) - NaN values create gaps
    Bas3GLMakie.GLMakie.scatterlines!(
        ax_h,
        timepoints,
        h_values;
        color = :green,
        linewidth = 2,
        linestyle = :solid,
        marker = :rect,
        markersize = 9
    )
    
    # Link X-axes for synchronized zooming/panning
    Bas3GLMakie.GLMakie.linkxaxes!(ax_l, ax_c, ax_h)
    
    # Set row sizes: equal space for three axes (180px each = 540px total)
    Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 1, 180)
    Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 2, 180)
    Bas3GLMakie.GLMakie.rowsize!(timeline_grid, 3, 180)
    
    return (ax_l, ax_c, ax_h)
end

"""
    create_multiclass_lch_timeline!(grid, entries, lch_data_per_class)

Create L*C*h timeline with multiple lines (one per wound class).
Each class is plotted in its designated color with legend.
"""
function create_multiclass_lch_timeline!(
    grid::Bas3GLMakie.GLMakie.GridLayout, 
    entries::Vector, 
    lch_data_per_class::Dict{Symbol, Vector{Union{NamedTuple, Nothing}}}
)
    # Create 3 axes
    ax_L = Bas3GLMakie.GLMakie.Axis(
        grid[1, 1],
        ylabel="L* (Helligkeit)",
        xticks=(1:length(entries), ["T$i" for i in 1:length(entries)])
    )
    
    ax_C = Bas3GLMakie.GLMakie.Axis(
        grid[2, 1],
        ylabel="C* (Chroma)",
        xticks=(1:length(entries), ["T$i" for i in 1:length(entries)])
    )
    
    ax_h = Bas3GLMakie.GLMakie.Axis(
        grid[3, 1],
        ylabel="h° (Farbton)",
        xlabel="Zeitpunkt",
        xticks=(1:length(entries), ["T$i" for i in 1:length(entries)])
    )
    
    # Plot each class as separate line
    has_plots = false
    for class in WOUND_CLASSES
        if !haskey(lch_data_per_class, class)
            continue
        end
        
        data = lch_data_per_class[class]
        color = get_class_color(class)
        class_name = CLASS_NAMES_DE[class]
        
        # Extract valid (non-nothing) datapoints
        L_vals = Float32[]
        C_vals = Float32[]
        h_vals = Float32[]
        x_vals = Int[]
        
        for (i, d) in enumerate(data)
            if !isnothing(d) && d.count > 0
                push!(L_vals, Float32(d.median_l))
                push!(C_vals, Float32(d.median_c))
                push!(h_vals, Float32(d.median_h))
                push!(x_vals, i)
            end
        end
        
        if !isempty(x_vals)
            # Plot with markers and lines
            Bas3GLMakie.GLMakie.scatterlines!(ax_L, x_vals, L_vals, 
                color=color, linewidth=2, markersize=8, label=class_name)
            Bas3GLMakie.GLMakie.scatterlines!(ax_C, x_vals, C_vals, 
                color=color, linewidth=2, markersize=8)
            Bas3GLMakie.GLMakie.scatterlines!(ax_h, x_vals, h_vals, 
                color=color, linewidth=2, markersize=8)
            
            has_plots = true
            println("[TIMELINE-MULTI] Plotted $(length(x_vals)) points for $class")
        end
    end
    
    # Add legend only if we have plots
    if has_plots
        Bas3GLMakie.GLMakie.Legend(
            grid[4, 1],              # Row 4, below all axes
            ax_L, 
            "Klassen", 
            framevisible=true,
            orientation=:horizontal, # Horizontal layout for better space usage
            tellheight=false,        # Let grid manage height
            tellwidth=false          # Let grid manage width
        )
    end
    
    return (ax_L, ax_C, ax_h)
end

# ============================================================================
# POLYGON MASK EXPORT HELPERS (Module-level functions)
# ============================================================================

"""
    scale_vertices_to_fullres(
        vertices_lowres::Vector{Point2f},
        image_lowres::Matrix,
        image_fullres::Matrix
    ) -> Vector{Point2f}

Scale polygon vertices from UI (lowres) coordinate space to fullres image space.

# Arguments
- `vertices_lowres`: Polygon vertices in UI coordinate space
- `image_lowres`: UI display image (for size reference)
- `image_fullres`: Full-resolution rotated image (target coordinate space)

# Returns
- Scaled vertices in fullres coordinate space

# Notes
- Handles GLMakie coordinate system: v[1]=y, v[2]=x (swapped!)
- Handles X-axis flip: X is horizontally flipped in GLMakie
"""
function scale_vertices_to_fullres(
    vertices_lowres::Vector{Bas3GLMakie.GLMakie.Point2f},
    image_lowres::Matrix,
    image_fullres::Matrix
)
    local height_lowres = size(image_lowres, 1)
    local width_lowres = size(image_lowres, 2)
    local height_fullres = size(image_fullres, 1)
    local width_fullres = size(image_fullres, 2)
    
    local scale_factor_x = Float32(width_fullres) / Float32(width_lowres)
    local scale_factor_y = Float32(height_fullres) / Float32(height_lowres)
    
    # Scale vertices (GLMakie coords: v[1]=y, v[2]=x, X is flipped)
    local vertices_fullres = [Bas3GLMakie.GLMakie.Point2f(
        width_fullres - (v[2] * scale_factor_x),  # Flip X: width - x
        v[1] * scale_factor_y                       # Y is correct
    ) for v in vertices_lowres]
    
    return vertices_fullres
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
    # ========================================================================
    # UI DESIGN CONSTANTS (RELATIVE APPROACH)
    # ========================================================================
    
    # Typography scale (5-level harmonious progression)
    local FONT_SIZE_TITLE = 16          # Main title
    local FONT_SIZE_SECTION = 13        # Section headers (e.g., "Bild X")
    local FONT_SIZE_LABEL = 11          # Input labels
    local FONT_SIZE_TEXTBOX = 10        # Textbox inputs
    local FONT_SIZE_BUTTON = 11         # Text buttons
    local FONT_SIZE_BUTTON_ICON = 10    # Icon buttons (✓, ✗)
    local FONT_SIZE_STATUS = 9          # Status messages
    
    # NO SPACING CONSTANTS NEEDED!
    # We use proportional gaps instead of fixed pixels:
    # - .colgaps[] and .rowgaps[] with ratio values (1, 2, 3, etc.)
    # - Relative() for proportional columns (0.35 = 35%)
    # - Auto() with weights for semantic sizing
    
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
    
    # ========================================================================
    # BUILD PATIENT IMAGES (save_polygon_mask_for_column defined as inner function below)
    # ========================================================================
    # Cache patient image counts (computed once, updated on refresh)
    local patient_image_counts = Bas3GLMakie.GLMakie.Observable(
        get_patient_image_counts(db_path)
    )
    
    # Current filter setting (0 = no filter, 1+ = exact image count)
    local exact_image_filter = Bas3GLMakie.GLMakie.Observable(0)
    
    # Filtered patient IDs (reactive to filter changes)
    local filtered_patient_ids = Bas3GLMakie.GLMakie.Observable(all_patient_ids)
    
    # Create responsive figure with initial size (user can resize)
    # Responsive design: no fixed width calculation, scales with window
    local fgr = Bas3GLMakie.GLMakie.Figure(size=(1400, 900))
    
    # ========================================================================
    # TWO-COLUMN MAIN LAYOUT (RESPONSIVE, FILLS ENTIRE FIGURE)
    # ========================================================================
    # Column 1: Controls + Timeline (15% of window width)
    # Column 2: Images Grid (85% of window width - MAXIMIZED)
    
    # FIX: Add tellheight=false and tellwidth=false to accept parent allocations
    # This ensures GridLayouts expand to fill entire figure height and width
    local left_column = Bas3GLMakie.GLMakie.GridLayout(fgr[1, 1]; tellheight=false, tellwidth=false)
    local right_column = Bas3GLMakie.GLMakie.GridLayout(fgr[1, 2]; tellheight=false, tellwidth=false)
    
    # Set column widths (responsive proportions - change based on timeline visibility)
    # Initial: Left 15% (controls + timeline), Right 85% (images)
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Relative(0.15))
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Relative(0.85))
    
    # FIX: Remove explicit rowsize! - default behavior fills figure height
    # Previous: rowsize!(fgr.layout, 1, Auto()) prevented full height spanning
    
    # ========================================================================
    # LEFT COLUMN: Controls (rows 1-5) + Spacer (row 6) + Timeline (row 7)
    # ========================================================================
    
    # Row 1: Title
    Bas3GLMakie.GLMakie.Label(
        left_column[1, 1],
        "Patientenbilder\nVergleich",
        fontsize=FONT_SIZE_TITLE,
        font=:bold,
        halign=:center
    )
    
    # Row 2: Patient ID selector and filter (label + menus)
    local selector_filter_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[2, 1])
    
    # Row 2.1: Patient ID selector
    Bas3GLMakie.GLMakie.Label(
        selector_filter_grid[1, 1],
        "Patient-ID:",
        fontsize=FONT_SIZE_LABEL,
        halign=:right
    )
    local patient_menu = Bas3GLMakie.GLMakie.Menu(
        selector_filter_grid[1, 2],
        options = [string(pid) for pid in all_patient_ids],
        default = isempty(all_patient_ids) ? nothing : string(all_patient_ids[1])
    )
    
    # Row 2.2: Image count filter
    Bas3GLMakie.GLMakie.Label(
        selector_filter_grid[2, 1],
        "Bilderanzahl:",
        fontsize=FONT_SIZE_LABEL,
        halign=:right
    )
    local filter_menu = Bas3GLMakie.GLMakie.Menu(
        selector_filter_grid[2, 2],
        options = ["Alle", "1 Bild", "2 Bilder", "3 Bilder", "4 Bilder", "5 Bilder"],
        default = "Alle"
    )
    
    # Set proportional columns AFTER widgets are created (labels: 35%, inputs: 65%)
    Bas3GLMakie.GLMakie.colsize!(selector_filter_grid, 1, Bas3GLMakie.GLMakie.Relative(0.35))
    Bas3GLMakie.GLMakie.colsize!(selector_filter_grid, 2, Bas3GLMakie.GLMakie.Relative(0.65))
    
    # Set relative row sizing (required for Relative() gaps to work)
    Bas3GLMakie.GLMakie.rowsize!(selector_filter_grid, 1, Bas3GLMakie.GLMakie.Relative(0.48))  # Patient selector ~48%
    Bas3GLMakie.GLMakie.rowsize!(selector_filter_grid, 2, Bas3GLMakie.GLMakie.Relative(0.48))  # Filter menu ~48%
    
    # Set row gap using rowgap! function (pure relative)
    Bas3GLMakie.GLMakie.rowgap!(selector_filter_grid, 1, Bas3GLMakie.GLMakie.Relative(0.01))  # Gap ~1% (was 0.5%)
    
    # Row 3: Navigation buttons
    local nav_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[3, 1])
    local prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 1],
        label = "← Zurück",
        fontsize = FONT_SIZE_BUTTON
    )
    local next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 2],
        label = "Weiter →",
        fontsize = FONT_SIZE_BUTTON
    )
    
    # Row 4: Refresh button
    local refresh_button = Bas3GLMakie.GLMakie.Button(
        left_column[4, 1],
        label = "Aktualisieren",
        fontsize = FONT_SIZE_BUTTON
    )
    
    # Row 5: Clear all polygons button
    local clear_polygons_button = Bas3GLMakie.GLMakie.Button(
        left_column[5, 1],
        label = "Polygone löschen",
        fontsize = FONT_SIZE_BUTTON
    )
    
    # Row 6: Status label
    local status_label = Bas3GLMakie.GLMakie.Label(
        left_column[6, 1],
        "",
        fontsize=FONT_SIZE_STATUS,
        halign=:center,
        color=:gray
    )
    
    # Row 7: Timeline section (toggle button + plot in nested GridLayout)
    local timeline_section = Bas3GLMakie.GLMakie.GridLayout(left_column[7, 1])
    
    # Timeline toggle button (row 1 of timeline_section)
    local timeline_toggle_btn = Bas3GLMakie.GLMakie.Button(
        timeline_section[1, 1],
        label = "▼ Timeline",
        fontsize = FONT_SIZE_BUTTON_ICON,
        halign = :center
    )
    
    # L*C*h Timeline Plot (row 2 of timeline_section, collapsible)
    # Using Ref to allow reassignment when deleting/recreating GridLayout
    local timeline_grid_lch = Ref{Any}(Bas3GLMakie.GLMakie.GridLayout(timeline_section[2, 1]))
    # With Relative() sizing, keep default tellheight to respect parent allocation
    # timeline_grid_lch[].tellheight = false  # Commented out - was causing overflow with Relative() sizing
    local timeline_axis_lch = Ref{Any}(nothing)  # Will hold LCh axis reference for clearing
    
    # Set row sizing for timeline_section (row 1 = button, row 2 = plot with dynamic sizing)
    Bas3GLMakie.GLMakie.rowsize!(timeline_section, 1, Bas3GLMakie.GLMakie.Relative(0.08))  # Button ~8% of timeline_section
    # Row 2 sizing is set dynamically (89% when visible, 0% when hidden) - see lines ~1859, 1874, 1893
    
    # Set gap between toggle button and timeline plot (pure relative)
    Bas3GLMakie.GLMakie.rowgap!(timeline_section, 1, Bas3GLMakie.GLMakie.Relative(0.02))  # ~2%
    
    # Row 8: Expandable spacer (absorbs unused vertical space when timeline hidden)
    # Empty Label acts as flexible spacer
    local spacer_label = Bas3GLMakie.GLMakie.Label(
        left_column[8, 1],
        "",
        fontsize = 1
    )
    
    # Set left column row sizes (content-driven + responsive timeline with dynamic sizing)
    # Rows 1-6: Auto-sized to content (no explicit rowsize needed)
    # Row 7: Timeline section (toggle + plot) - size controlled by timeline_row_size observable
    # Set left_column row sizing (required for Relative() gaps to work)
    # left_column has 8 rows: title, selector, nav, refresh, clear, status, timeline_section, spacer
    Bas3GLMakie.GLMakie.rowsize!(left_column, 1, Bas3GLMakie.GLMakie.Relative(0.05))   # Title ~5%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 2, Bas3GLMakie.GLMakie.Relative(0.12))   # Selector ~12%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 3, Bas3GLMakie.GLMakie.Relative(0.05))   # Nav buttons ~5%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 4, Bas3GLMakie.GLMakie.Relative(0.05))   # Refresh ~5%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 5, Bas3GLMakie.GLMakie.Relative(0.05))   # Clear ~5%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 6, Bas3GLMakie.GLMakie.Relative(0.04))   # Status ~4%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 7, Bas3GLMakie.GLMakie.Relative(0.45))   # Timeline section ~45%
    Bas3GLMakie.GLMakie.rowsize!(left_column, 8, Bas3GLMakie.GLMakie.Relative(0.15))   # Expandable spacer ~15%
    
    # Set row gaps for visual grouping using rowgap! function (pure relative)
    Bas3GLMakie.GLMakie.rowgap!(left_column, 1, Bas3GLMakie.GLMakie.Relative(0.005))   # After title - small gap ~0.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 2, Bas3GLMakie.GLMakie.Relative(0.015))   # After patient selector - larger gap ~1.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 3, Bas3GLMakie.GLMakie.Relative(0.005))   # After nav buttons - small gap ~0.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 4, Bas3GLMakie.GLMakie.Relative(0.005))   # After refresh - small gap ~0.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 5, Bas3GLMakie.GLMakie.Relative(0.015))   # After clear polygons - larger gap ~1.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 6, Bas3GLMakie.GLMakie.Relative(0.005))   # After status - small gap ~0.5%
    Bas3GLMakie.GLMakie.rowgap!(left_column, 7, Bas3GLMakie.GLMakie.Relative(0.0))     # After timeline section - no gap
    
    # ========================================================================
    # RIGHT COLUMN: Images Container (fills entire right column height)
    # ========================================================================
    # FIX: Add tellheight=false and tellwidth=false to expand to parent size
    local images_grid = Bas3GLMakie.GLMakie.GridLayout(right_column[1, 1]; tellheight=false, tellwidth=false)
    
    # Store references to dynamically created widgets
    local image_axes = Bas3GLMakie.GLMakie.Axis[]
    local date_textboxes = []
    local info_textboxes = []
    local patient_id_textboxes = []  # For patient ID reassignment
    local save_buttons = []
    local image_axes = []
    local image_observables = []
    local lch_polygon_data = []   # L*C*h data per polygon (NamedTuple per image) - LEGACY for manual drawing
    local lch_multiclass_data = Dict{Symbol, Vector{Union{NamedTuple, Nothing}}}()  # NEW: Per-class L*C*h data
    
    # POLYGON SELECTION: Per-image polygon state arrays (LEGACY - for backwards compatibility)
    local polygon_vertices_per_image = []     # Vector of Observable{Vector{Point2f}}
    local polygon_active_per_image = []       # Vector of Observable{Bool}
    local polygon_complete_per_image = []     # Vector of Observable{Bool}
    local polygon_buttons_per_image = []      # Vector of (close_btn, clear_btn) tuples
    
    # MULTI-POLYGON: Per-image polygon collections (NEW)
    local polygons_per_image = []             # Vector of Observable{Vector{PolygonEntry}}
    local active_polygon_id_per_image = []    # Vector of Observable{Union{Int, Nothing}}
    local selected_class_per_image = []       # Vector of Observable{Symbol}
    local polygon_id_counter = Ref(0)         # Global counter for unique polygon IDs
    
    # MASK OVERLAY: Per-image saved mask overlay state arrays
    local saved_mask_overlays = []            # Vector of Observable{Union{Matrix{RGBAf}, Nothing}}
    local saved_mask_visible = []             # Vector of Observable{Bool} (show/hide toggle)
    local saved_mask_exists = []              # Vector of Bool (track if saved mask exists)
    
    local current_entries = Bas3GLMakie.GLMakie.Observable(NamedTuple[])
    local current_patient_id = Bas3GLMakie.GLMakie.Observable(isempty(all_patient_ids) ? 0 : all_patient_ids[1])
    
    # ========================================================================
    # COLLAPSIBLE TIMELINE STATE
    # ========================================================================
    
    # Observable to track timeline visibility
    local timeline_visible = Bas3GLMakie.GLMakie.Observable(true)
    
    # Timeline toggle callback (defined after observables)
    # Option A: Dynamic column widths with widget rebuild
    Bas3GLMakie.GLMakie.on(timeline_toggle_btn.clicks) do _
        timeline_visible[] = !timeline_visible[]
        
        println("[TIMELINE-TOGGLE] Button clicked, timeline_visible = $(timeline_visible[])")
        
        # Store current patient to rebuild after layout change
        local current_patient = current_patient_id[]
        
        if timeline_visible[]
            # SHOW timeline - expand sidebar
            println("[TIMELINE-TOGGLE] Showing timeline...")
            
            # Step 1: Change column proportions
            Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Relative(0.15))  # 8% → 15%
            Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Relative(0.85))  # 92% → 85%
            
            # Step 2: Let layout solver process changes
            yield()
            
            # Step 3: Rebuild images to pick up new column width
            println("[TIMELINE-TOGGLE] Rebuilding images for narrower column...")
            local rebuild_start = time()
            build_patient_images!(current_patient)
            println("[TIMELINE-TOGGLE] Images rebuilt in $(round((time() - rebuild_start) * 1000, digits=1))ms")
            
            # Step 4: Update toggle button label
            timeline_toggle_btn.label = "▼ Timeline"
            
            # Recreate timeline if we have data
            if !isempty(lch_multiclass_data) && !isnothing(current_entries[]) && !isempty(current_entries[])
                if !isnothing(timeline_grid_lch[])
                    delete_gridlayout_contents!(timeline_grid_lch[])
                    timeline_axis_lch[] = create_multiclass_lch_timeline!(
                        timeline_grid_lch[], 
                        current_entries[], 
                        lch_multiclass_data
                    )
                    # Set timeline plot row size within timeline_section (pure relative)
                    Bas3GLMakie.GLMakie.rowsize!(timeline_section, 2, Bas3GLMakie.GLMakie.Relative(0.89))  # 89% of timeline_section
                    println("[TIMELINE-TOGGLE] Timeline recreated with 89% height")
                end
            end
        else
            # HIDE timeline - shrink sidebar
            println("[TIMELINE-TOGGLE] Hiding timeline...")
            
            # Step 1: Clear timeline content first
            if !isnothing(timeline_grid_lch[])
                delete_gridlayout_contents!(timeline_grid_lch[])
            end
            timeline_axis_lch[] = nothing
            
            # Collapse timeline plot row to 0 within timeline_section (pure relative)
            Bas3GLMakie.GLMakie.rowsize!(timeline_section, 2, Bas3GLMakie.GLMakie.Relative(0.0))  # 0% = hidden
            timeline_toggle_btn.label = "▶ Timeline"
            
            # Step 2: Change column proportions  
            Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Relative(0.08))  # 15% → 8%
            Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Relative(0.92))  # 85% → 92%
            
            # Step 3: Let layout solver process changes
            yield()
            
            # Step 4: Rebuild images to pick up new column width
            println("[TIMELINE-TOGGLE] Rebuilding images for wider column...")
            local rebuild_start = time()
            build_patient_images!(current_patient)
            println("[TIMELINE-TOGGLE] Images rebuilt in $(round((time() - rebuild_start) * 1000, digits=1))ms - images should be larger!")
        end
    end
    
    # Set initial timeline plot size within timeline_section (row 2 = plot, row 1 = button) - pure relative
    Bas3GLMakie.GLMakie.rowsize!(timeline_section, 2, Bas3GLMakie.GLMakie.Relative(0.89))  # 89% = visible initially (8% button + 2% gap + 89% plot = 99%)
    
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
    
    # Build index map for O(1) lookup (replaces O(n) linear search)
    # Map: image_index => array_position in sets
    local sets_index_map = Dict{Int, Int}()
    for (array_pos, mset) in enumerate(sets)
        local idx = mset[3]  # Extract index from (input_img, output_img, idx) tuple
        sets_index_map[idx] = array_pos
    end
    println("[COMPARE-UI] Built index map for $(length(sets_index_map)) images")
    
    # Get both input and output images from sets by image_index
    function get_images_by_index(image_index::Int)
        local total_time = 0.0
        local lookup_time = 0.0
        local image_convert_time = 0.0
        local rotation_time = 0.0
        
        total_time = @elapsed begin
            # O(1) dictionary lookup instead of O(n) linear search
            local array_pos = nothing
            lookup_time = @elapsed begin
                array_pos = get(sets_index_map, image_index, nothing)
            end
            
            if !isnothing(array_pos)
                local input_img = sets[array_pos][1]
                local output_img = sets[array_pos][2]
                
                local rotated = nothing
                local raw = nothing
                local h = 0
                
                # Time image type conversion
                image_convert_time = @elapsed begin
                    raw = input_img
                    h = Base.size(data(input_img), 1)
                end
                
                # Time rotation
                rotation_time = @elapsed begin
                    rotated = rotr90(image(input_img))
                end
                
                println("[PERF-GET_IMAGE] Image $image_index: total=$(round(total_time*1000, digits=2))ms, lookup=$(round(lookup_time*1000, digits=2))ms, convert=$(round(image_convert_time*1000, digits=2))ms, rotate=$(round(rotation_time*1000, digits=2))ms")
                
                return (
                    input = rotated,
                    input_raw = raw,
                    height = h
                )
            end
        end
        
        # Return placeholder if not found
        println("[PERF-GET_IMAGE] Image $image_index: NOT FOUND (total=$(round(total_time*1000, digits=2))ms)")
        local placeholder = fill(Bas3ImageSegmentation.RGB{Float32}(0.5f0, 0.5f0, 0.5f0), 100, 100)
        return (input = placeholder, input_raw = nothing, height = 100)
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
            
            local preload_start_time = time()
            
            # Spawn parallel tasks to load each image and mask
            load_tasks = map(entries) do entry
                Threads.@spawn begin
                    local task_start_time = time()
                    local get_images_time = 0.0
                    local mask_load_time = 0.0
                    local mask_resize_time = 0.0
                    
                    try
                        # Get raw images (loads .bin files into RAM)
                        local images = nothing
                        get_images_time = @elapsed begin
                            images = get_images_by_index(entry.image_index)
                        end
                        
                        # Load mask if available - OPTIMIZED: Use mmap loading (2-6x faster)
                        # Try .bin first (fast), fallback to PNG (slow, for backward compatibility)
                        local mask_display = nothing
                        local mask_method = "none"
                        
                        mask_load_time = @elapsed begin
                            mask_display = load_polygon_mask_mmap(entry.image_index)
                            
                            if isnothing(mask_display)
                                mask_method = "png_fallback"
                                # Fallback to PNG loading (old method)
                                local mask_fullres = load_polygon_mask_if_exists(entry.image_index)
                                if !isnothing(mask_fullres)
                                    # Resize to display resolution
                                    local display_height, display_width = size(images.input)
                                    mask_resize_time = @elapsed begin
                                        mask_display = resize_mask_to_display(mask_fullres, (display_height, display_width))
                                    end
                                end
                            else
                                mask_method = "bin_mmap"
                            end
                        end
                        
                        local mask_exists = !isnothing(mask_display)
                        local task_total_time = time() - task_start_time
                        
                        println("[PERF-PRELOAD] Image $(entry.image_index): total=$(round(task_total_time*1000, digits=2))ms, get_images=$(round(get_images_time*1000, digits=2))ms, mask_load=$(round(mask_load_time*1000, digits=2))ms (method=$mask_method), mask_resize=$(round(mask_resize_time*1000, digits=2))ms")
                        
                        # Return input images and mask data
                        (
                            success = true,
                            data = (
                                image_index = entry.image_index,
                                input_rotated = images.input,
                                input_raw = images.input_raw,
                                height = images.height,
                                # Mask data (already at display resolution from mmap)
                                mask_exists = mask_exists,
                                mask_resized = mask_display
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
            local fetch_start = time()
            cached_images = NamedTuple[]
            for task in load_tasks
                result = fetch(task)
                if result.success
                    push!(cached_images, result.data)
                end
            end
            local fetch_time = time() - fetch_start
            local total_preload_time = time() - preload_start_time
            
            # Store in cache
            lock(cache_lock) do
                patient_image_cache[patient_id] = cached_images
                delete!(preload_tasks, patient_id)  # Remove from in-progress
                println("[PRELOAD] Cached $(length(cached_images))/$(length(entries)) images for patient $patient_id")
                println("[PERF-PRELOAD-SUMMARY] Patient $patient_id: TOTAL=$(round(total_preload_time*1000, digits=2))ms, fetch_wait=$(round(fetch_time*1000, digits=2))ms, avg_per_image=$(round(total_preload_time*1000/length(entries), digits=2))ms")
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
    
    # Helper to recursively delete GridLayout contents
    # Moved outside clear_images_grid! so it can be called from polygon callbacks
    function delete_gridlayout_contents!(gl)
        while !isempty(gl.content)
            content_item = gl.content[1]
            obj = content_item.content
            
            # If this is a nested GridLayout, recursively clear it first, then remove it from parent
            if obj isa Bas3GLMakie.GLMakie.GridLayout
                delete_gridlayout_contents!(obj)
                # Remove GridLayout from its parent
                deleteat!(gl.content, 1)
            else
                # Delete non-GridLayout objects normally
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
    end
    
    # Clear all image widgets - RECURSIVE deletion for nested GridLayouts
    function clear_images_grid!()
        println("[COMPARE-UI] Clearing images grid ($(length(images_grid.content)) items) and timeline...")
        
        # Clear the main images_grid recursively
        delete_gridlayout_contents!(images_grid)
        
        # Clear the LCh timeline_grid (only if it exists)
        if !isnothing(timeline_grid_lch[])
            delete_gridlayout_contents!(timeline_grid_lch[])
        end
        timeline_axis_lch[] = nothing
        
        # Clear widget arrays
        empty!(image_axes)
        empty!(date_textboxes)
        empty!(info_textboxes)
        empty!(patient_id_textboxes)
        empty!(save_buttons)
        empty!(image_observables)
        empty!(lch_polygon_data)  # Clear L*C*h polygon data (legacy)
        empty!(lch_multiclass_data)  # Clear multi-class L*C*h data
        
        # Clear polygon state arrays (legacy)
        empty!(polygon_vertices_per_image)
        empty!(polygon_active_per_image)
        empty!(polygon_complete_per_image)
        empty!(polygon_buttons_per_image)
        
        # Clear multi-polygon arrays (new)
        empty!(polygons_per_image)
        empty!(active_polygon_id_per_image)
        empty!(selected_class_per_image)
        
        # Clear mask overlay arrays
        empty!(saved_mask_overlays)
        empty!(saved_mask_visible)
        empty!(saved_mask_exists)
        
        println("[COMPARE-UI] Grid cleared, $(length(images_grid.content)) items remaining")
    end
    
    # ========================================================================
    # MULTI-POLYGON HELPER FUNCTIONS
    # ========================================================================
    
    """
    Add new polygon to image column's collection. Returns polygon ID.
    """
    function add_polygon_to_collection!(col_idx::Int, class::Symbol, class_name::String, sample_number::Int, vertices::Vector{Bas3GLMakie.GLMakie.Point2f}; manual_id::Union{Nothing, Int}=nothing)
        # Generate unique ID (auto-increment or use manual ID)
        new_id = if isnothing(manual_id)
            # Auto-increment
            polygon_id_counter[] += 1
            polygon_id_counter[]
        else
            # Validate manual ID
            current_polygons = polygons_per_image[col_idx][]
            if any(p -> p.id == manual_id, current_polygons)
                println("[MULTI-POLYGON] WARNING: Manual ID $manual_id already exists in column $col_idx, auto-incrementing instead")
                polygon_id_counter[] += 1
                polygon_id_counter[]
            else
                # Use manual ID and update counter if necessary
                if manual_id > polygon_id_counter[]
                    polygon_id_counter[] = manual_id
                end
                manual_id
            end
        end
        
        # Create polygon entry
        poly = PolygonEntry(new_id, class, class_name, sample_number, vertices, false, nothing)
        
        # Add to collection
        current_polygons = polygons_per_image[col_idx][]
        push!(current_polygons, poly)
        polygons_per_image[col_idx][] = current_polygons  # Trigger observable update
        
        id_source = isnothing(manual_id) ? "auto" : "manual"
        println("[MULTI-POLYGON] Added polygon ID=$new_id ($id_source), class=$class, name=\"$class_name\", sample=$sample_number to column $col_idx")
        return new_id
    end
    
    """
    Remove polygon by ID from image column's collection.
    """
    function remove_polygon_from_collection!(col_idx::Int, polygon_id::Int)
        current_polygons = polygons_per_image[col_idx][]
        filter!(p -> p.id != polygon_id, current_polygons)
        polygons_per_image[col_idx][] = current_polygons
        
        println("[MULTI-POLYGON] Removed polygon ID=$polygon_id from column $col_idx")
    end
    
    """
    Find polygon by ID in image column's collection.
    """
    function get_polygon_by_id(col_idx::Int, polygon_id::Int)
        current_polygons = polygons_per_image[col_idx][]
        idx = findfirst(p -> p.id == polygon_id, current_polygons)
        return isnothing(idx) ? nothing : current_polygons[idx]
    end
    
    """
    Update polygon in collection (immutable update pattern).
    """
    function update_polygon!(col_idx::Int, polygon_id::Int, new_poly::PolygonEntry)
        current_polygons = polygons_per_image[col_idx][]
        idx = findfirst(p -> p.id == polygon_id, current_polygons)
        
        if !isnothing(idx)
            current_polygons[idx] = new_poly
            polygons_per_image[col_idx][] = current_polygons
        end
    end
    
    """
    Update L*C*h data for specific polygon.
    """
    function update_polygon_lch!(col_idx::Int, polygon_id::Int, lch_data::NamedTuple)
        poly = get_polygon_by_id(col_idx, polygon_id)
        if !isnothing(poly)
            new_poly = PolygonEntry(poly.id, poly.class, poly.vertices, poly.complete, lch_data)
            update_polygon!(col_idx, polygon_id, new_poly)
        end
    end
    
    """
    Update polygon ID (for renumbering existing polygons).
    Returns (success::Bool, message::String)
    """
    function update_polygon_id!(col_idx::Int, old_id::Int, new_id::Int)
        # Validate new_id
        if new_id <= 0
            return (false, "ID muss größer als 0 sein")
        end
        
        # Check if new_id already exists (and is not the same polygon)
        current_polygons = polygons_per_image[col_idx][]
        if any(p -> p.id == new_id && p.id != old_id, current_polygons)
            return (false, "ID $new_id bereits vergeben")
        end
        
        # Get the polygon to update
        poly = get_polygon_by_id(col_idx, old_id)
        if isnothing(poly)
            return (false, "Polygon ID=$old_id nicht gefunden")
        end
        
        # Create new polygon with new ID
        new_poly = PolygonEntry(new_id, poly.class, poly.class_name, poly.sample_number, poly.vertices, poly.complete, poly.lch_data)
        
        # Replace in collection
        idx = findfirst(p -> p.id == old_id, current_polygons)
        if !isnothing(idx)
            current_polygons[idx] = new_poly
            polygons_per_image[col_idx][] = current_polygons
            
            # Update global counter if needed
            if new_id > polygon_id_counter[]
                polygon_id_counter[] = new_id
            end
            
            # Update active polygon ID if this was the active polygon
            if active_polygon_id_per_image[col_idx][] == old_id
                active_polygon_id_per_image[col_idx][] = new_id
            end
            
            println("[ID-UPDATE] Polygon ID updated: $old_id → $new_id in column $col_idx")
            return (true, "ID aktualisiert: $old_id → $new_id")
        end
        
        return (false, "Aktualisierung fehlgeschlagen")
    end
    
    # Save polygon masks for a column to individual PNG files
    function save_polygon_mask_for_column(col_idx::Int)
        local total_time = 0.0
        local validation_time = 0.0
        local load_fullres_time = 0.0
        local mask_creation_time = 0.0
        local individual_save_time = 0.0
        
        total_time = @elapsed begin
            # Check if column index is valid
            validation_time = @elapsed begin
                if col_idx < 1 || col_idx > length(image_observables)
                    return (false, "Ungültiger Spaltenindex: $col_idx", "")
                end
                
                # Get current entry
                local entry = current_entries[][col_idx]
                
                # NEW: Get ALL polygons for this image (not just active one)
                local all_polygons = polygons_per_image[col_idx][]
                
                if length(all_polygons) == 0
                    return (false, "Keine Polygone zum Speichern vorhanden", "")
                end
            end
            
            local entry = current_entries[][col_idx]
            local all_polygons = polygons_per_image[col_idx][]
            
            println("[MASK-EXPORT] Image index: $(entry.image_index) → Patient folder: MuHa_$(lpad(entry.image_index, 3, '0'))")
            println("[MASK-EXPORT] Total polygons for this image: $(length(all_polygons))")
            
            # Construct paths
            local base_dir = dirname(get_database_path())
            local patient_num = lpad(entry.image_index, 3, '0')
            local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
            
            if !isdir(patient_folder)
                return (false, "Patient-Ordner nicht gefunden: $patient_folder", "")
            end
            
            local original_filename = "MuHa_$(patient_num)_raw_adj.png"
            local original_path = joinpath(patient_folder, original_filename)
            
            if !isfile(original_path)
                return (false, "Original-Bild nicht gefunden: $original_path", "")
            end
            
            # Load original full-resolution image
            local original_img_rotated = nothing
            load_fullres_time = @elapsed begin
                println("[MASK-EXPORT] Loading original image: $original_path")
                local original_img_loaded = Bas3GLMakie.GLMakie.FileIO.load(original_path)
                println("[MASK-EXPORT] Original loaded size: $(size(original_img_loaded))")
                
                # Apply same rotation as UI (rotr90 for landscape viewing)
                original_img_rotated = rotr90(original_img_loaded)
                println("[MASK-EXPORT] Original rotated size: $(size(original_img_rotated))")
            end
            
            # Get UI image for size reference
            local image_lowres = image_observables[col_idx][]
            
            println("[MASK-EXPORT] UI image size: $(size(image_lowres)) (H×W)")
            println("[MASK-EXPORT] Fullres rotated size: $(size(original_img_rotated)) (H×W)")
            
            # NEW: Loop through ALL complete polygons and save each separately
            local saved_count = 0
            local skipped_count = 0
            local failed_polygons = Tuple{Int, String, String}[]
            
            individual_save_time = @elapsed begin
                for polygon in all_polygons
                    # Skip incomplete polygons
                    if !polygon.complete
                        println("[MASK-EXPORT] ⊘ Skipping incomplete polygon $(polygon.id) ($(polygon.class_name))")
                        skipped_count += 1
                        continue
                    end
                    
                    if length(polygon.vertices) < 3
                        @warn "[MASK-EXPORT] ⊘ Skipping polygon $(polygon.id): less than 3 vertices"
                        skipped_count += 1
                        continue
                    end
                    
                    # Scale vertices for this polygon
                    local single_polygon_time = @elapsed begin
                        local vertices_fullres = scale_vertices_to_fullres(
                            polygon.vertices,
                            image_lowres,
                            original_img_rotated
                        )
                        
                        println("[MASK-EXPORT] Processing polygon $(polygon.id) ($(polygon.class_name)): $(length(polygon.vertices)) vertices")
                        
                        # Generate mask for THIS polygon only
                        local mask_single = create_polygon_mask(original_img_rotated, vertices_fullres)
                        
                        # Save individual polygon mask (NEW: uses class name in filename)
                        local (success, msg) = save_polygon_mask_individual(
                            entry.image_index,
                            polygon,
                            mask_single,
                            patient_folder
                        )
                        
                        if success
                            saved_count += 1
                            println("[MASK-EXPORT] ✓ Saved: $msg")
                        else
                            push!(failed_polygons, (polygon.id, polygon.class_name, msg))
                            @warn "[MASK-EXPORT] ✗ Failed: polygon $(polygon.id) ($(polygon.class_name)) - $msg"
                        end
                    end
                    
                    println("[PERF-SINGLE-POLYGON] ID=$(polygon.id): total_processing=$(round(single_polygon_time*1000, digits=1))ms")
                end
            end
            
            # NOTE: Composite mask generation removed for performance (was taking 20+ seconds)
            # Individual polygon PNGs are sufficient for analysis
            # Composite can be regenerated later if needed using load_polygon_masks_individual()
            
            println("[PERF-SAVE-COLUMN] total=$(round(total_time*1000, digits=1))ms, validation=$(round(validation_time*1000, digits=1))ms, load_fullres=$(round(load_fullres_time*1000, digits=1))ms, individual_save=$(round(individual_save_time*1000, digits=1))ms, n_polygons=$(saved_count)")
            
            # Summary message
            local total_count = length(all_polygons)
            local failed_count = length(failed_polygons)
            
            if saved_count == total_count && failed_count == 0
                local summary_msg = "$(saved_count) Masken gespeichert"
                return (true, summary_msg, patient_folder)
            elseif saved_count > 0
                local failed_summary = join(["$(p[2])_$(p[1])" for p in failed_polygons], ", ")
                local summary_msg = "$(saved_count)/$(total_count) Masken gespeichert"
                local detail_msg = skipped_count > 0 ? 
                    "$(skipped_count) übersprungen, $(failed_count) fehlgeschlagen: $failed_summary" :
                    "$(failed_count) fehlgeschlagen: $failed_summary"
                return (true, summary_msg, detail_msg)
            else
                return (false, "Alle Masken fehlgeschlagen", "Keine Polygone erfolgreich gespeichert")
            end
        end
    end
    
    # Build image widgets for current patient
    function build_patient_images!(patient_id::Int)
        try
            println("[COMPARE-UI] Building images for patient $patient_id")
            local build_start_time = time()
            
            # Clear existing widgets
            local clear_time = @elapsed clear_images_grid!()
            println("[PERF-BUILD] Grid clear: $(round(clear_time*1000, digits=2))ms")
        
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
        
        local widget_creation_start = time()
        
        for (col, entry) in enumerate(entries[1:num_images])
            println("[COMPARE-UI] Creating column $col for image $(entry.image_index)")
            
            # Row 1: Image header removed (will be in data section below)
            
            # Row 1: Image axis (moved from row 2)
            local ax = Bas3GLMakie.GLMakie.Axis(
                images_grid[1, col],
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
                
                # Layer 2: SAVED MASK OVERLAY (display class segmentation mask)
                # Load class mask from sets[array_pos][2] (output segmentation)
                local mask_rgb_obs = Bas3GLMakie.GLMakie.Observable{Union{Matrix, Nothing}}(nothing)
                local mask_visible_obs = Bas3GLMakie.GLMakie.Observable(true)  # Visible by default
                
                # Load class segmentation mask
                local display_height, display_width = size(img_data.input_rotated)
                local class_mask = load_class_mask_for_display(entry.image_index, (display_height, display_width), sets_index_map)
                
                if !isnothing(class_mask)
                    mask_rgb_obs[] = class_mask
                    push!(saved_mask_exists, true)
                    println("[MASK-OVERLAY] Loaded class segmentation mask for image $(entry.image_index)")
                else
                    push!(saved_mask_exists, false)
                    println("[MASK-OVERLAY] No class segmentation mask for image $(entry.image_index)")
                end
                
                push!(saved_mask_overlays, mask_rgb_obs)
                push!(saved_mask_visible, mask_visible_obs)
                
                # Display overlay (reactive to visibility toggle) with 50% alpha
                # FIX: Use 'visible' attribute for reliable toggling
                # Provide 1x1 black pixel placeholder when mask is nothing
                Bas3GLMakie.GLMakie.image!(
                    ax,
                    Bas3GLMakie.GLMakie.@lift(
                        !isnothing($mask_rgb_obs) ? $mask_rgb_obs : 
                        fill(Bas3ImageSegmentation.RGB{Float32}(0, 0, 0), 1, 1)
                    );
                    alpha = 0.5,
                    visible = Bas3GLMakie.GLMakie.@lift($mask_visible_obs && !isnothing($mask_rgb_obs))
                )
                
                # Layer 3: POLYGON OVERLAY (per-image polygon selection)
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
                
                # Initialize multi-polygon arrays (NEW)
                push!(polygons_per_image, Bas3GLMakie.GLMakie.Observable(PolygonEntry[]))
                push!(active_polygon_id_per_image, Bas3GLMakie.GLMakie.Observable{Union{Int, Nothing}}(nothing))
                push!(selected_class_per_image, Bas3GLMakie.GLMakie.Observable(:redness))  # Default class
                
                # Initialize empty L*C*h data (will be populated when polygon is closed)
                push!(lch_polygon_data, (
                    l_values = Float64[],
                    c_values = Float64[],
                    h_values = Float64[],
                    median_l = NaN,
                    median_c = NaN,
                    median_h = NaN,
                    count = 0
                ))
            else
                # FALLBACK: Compute fresh (should rarely happen)
                println("[COMPARE-UI] WARNING: Image $(entry.image_index) not in cache, computing fresh")
                
                local images = get_images_by_index(entry.image_index)
                
                # Create observable for input image
                local img_obs = Bas3GLMakie.GLMakie.Observable(images.input)
                push!(image_observables, img_obs)
                
                # Layer 1: Display input image (base layer)
                Bas3GLMakie.GLMakie.image!(ax, img_obs)
                
                # Layer 2: SAVED MASK OVERLAY (display class segmentation mask)
                # Load class mask from sets[array_pos][2] (output segmentation)
                local display_height, display_width = size(images.input)
                local class_mask = load_class_mask_for_display(entry.image_index, (display_height, display_width), sets_index_map)
                
                local mask_rgb_obs = Bas3GLMakie.GLMakie.Observable{Union{Matrix, Nothing}}(nothing)
                local mask_visible_obs = Bas3GLMakie.GLMakie.Observable(true)  # Visible by default
                
                if !isnothing(class_mask)
                    mask_rgb_obs[] = class_mask
                    push!(saved_mask_exists, true)
                    println("[MASK-OVERLAY] Loaded class segmentation mask for image $(entry.image_index) (fallback)")
                else
                    push!(saved_mask_exists, false)
                    println("[MASK-OVERLAY] No class segmentation mask for image $(entry.image_index) (fallback)")
                end
                
                push!(saved_mask_overlays, mask_rgb_obs)
                push!(saved_mask_visible, mask_visible_obs)
                
                # Display overlay (reactive to visibility toggle) with 50% alpha
                # FIX: Use 'visible' attribute for reliable toggling
                # Provide 1x1 black pixel placeholder when mask is nothing
                Bas3GLMakie.GLMakie.image!(
                    ax,
                    Bas3GLMakie.GLMakie.@lift(
                        !isnothing($mask_rgb_obs) ? $mask_rgb_obs : 
                        fill(Bas3ImageSegmentation.RGB{Float32}(0, 0, 0), 1, 1)
                    );
                    alpha = 0.5,
                    visible = Bas3GLMakie.GLMakie.@lift($mask_visible_obs && !isnothing($mask_rgb_obs))
                )
                
                # Layer 3: POLYGON OVERLAY (per-image polygon selection)
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
                
                # Initialize multi-polygon arrays (NEW)
                push!(polygons_per_image, Bas3GLMakie.GLMakie.Observable(PolygonEntry[]))
                push!(active_polygon_id_per_image, Bas3GLMakie.GLMakie.Observable{Union{Int, Nothing}}(nothing))
                push!(selected_class_per_image, Bas3GLMakie.GLMakie.Observable(:redness))  # Default class
                
                # Initialize empty L*C*h data (will be populated when polygon is closed)
                push!(lch_polygon_data, (
                    l_values = Float64[],
                    c_values = Float64[],
                    h_values = Float64[],
                    median_l = NaN,
                    median_c = NaN,
                    median_h = NaN,
                    count = 0
                ))
            end
            
            # Row 2: Create & Select - Class, ID, Polygon selector (3 columns)
            local class_selector_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[2, col])
            
            # Column 1: Class menu (no label)
            local class_menu = Bas3GLMakie.GLMakie.Menu(
                class_selector_grid[1, 1],
                options = [CLASS_NAMES_DE[c] for c in WOUND_CLASSES],
                default = CLASS_NAMES_DE[:redness]
            )
            
            # Column 2: ID textbox (no label)
            local polygon_id_textbox = Bas3GLMakie.GLMakie.Textbox(
                class_selector_grid[1, 2],
                placeholder="auto"
            )
            
            # Textbox on-change callback for automatic ID updates
            local col_idx_textbox = col
            Bas3GLMakie.GLMakie.on(polygon_id_textbox.displayed_string) do new_id_str
                println("[UI-TEXTBOX-ID] Textbox changed to: '$new_id_str'")
                
                # Get active polygon ID
                active_id = active_polygon_id_per_image[col_idx_textbox][]
                
                # Only validate if there's an active polygon (not in "create new" mode)
                if isnothing(active_id)
                    println("[UI-TEXTBOX-ID] No active polygon, value will be used for creation")
                    return
                end
                
                # Skip if empty (user is clearing)
                if isempty(new_id_str)
                    println("[UI-TEXTBOX-ID] Empty textbox - will revert to current ID on OK")
                    return
                end
                
                # Parse new ID (validate only, don't update yet)
                local new_id
                try
                    new_id = parse(Int, new_id_str)
                catch e
                    # Silent fail during typing - user might not be done
                    println("[UI-TEXTBOX-ID] Invalid format (parsing): '$new_id_str'")
                    return
                end
                
                # Skip if ID unchanged
                if new_id == active_id
                    println("[UI-TEXTBOX-ID] ID unchanged ($new_id)")
                    return
                end
                
                # Validate new ID (but don't apply yet - wait for OK button)
                println("[UI-TEXTBOX-ID] Validating pending ID change: $active_id → $new_id")
                
                # Check for negative/zero
                if new_id <= 0
                    status_label.text = "ID muss > 0 sein"
                    status_label.color = :orange
                    println("[UI-TEXTBOX-ID] ✗ Invalid ID: $new_id <= 0")
                    return
                end
                
                # Check for duplicate
                current_polygons = polygons_per_image[col_idx_textbox][]
                if any(p -> p.id == new_id && p.id != active_id, current_polygons)
                    status_label.text = "ID $new_id bereits vergeben"
                    status_label.color = :red
                    println("[UI-TEXTBOX-ID] ✗ Duplicate ID: $new_id")
                    return
                end
                
                # Valid pending change - show hint
                status_label.text = "ID-Änderung vorbereitet ($active_id → $new_id) - OK drücken"
                status_label.color = :blue
                println("[UI-TEXTBOX-ID] ✓ Valid pending ID change: $active_id → $new_id")
            end
            
            # Column 3: Polygon selector dropdown (no label)
            local col_idx_list = col
            local polygon_selector = Bas3GLMakie.GLMakie.Observable{Vector{String}}(["Neu erstellen"])
            local polygon_selector_menu = Bas3GLMakie.GLMakie.Menu(
                class_selector_grid[1, 3],
                options = polygon_selector,
                default = "Neu erstellen"
            )
            
            # Update selector options when polygon list changes
            Bas3GLMakie.GLMakie.on(polygons_per_image[col_idx_list]) do polys
                if isempty(polys)
                    polygon_selector[] = ["Neu erstellen"]
                else
                    options = ["Neu erstellen"]
                    for poly in polys
                        display_name = isempty(poly.class_name) ? CLASS_NAMES_DE[poly.class] : poly.class_name
                        push!(options, "ID:$(poly.id) $display_name #$(poly.sample_number)")
                    end
                    polygon_selector[] = options
                end
            end
            
            # When user selects a polygon, set it as active for editing
            local col_idx_selector = col
            Bas3GLMakie.GLMakie.on(polygon_selector_menu.selection) do sel
                # Handle nothing/missing selection (happens when dropdown updates)
                if isnothing(sel)
                    return
                end
                
                if sel == "Neu erstellen"
                    # Clear active polygon - next "+ Neu" will create new one
                    active_polygon_id_per_image[col_idx_selector][] = nothing
                    polygon_id_textbox.displayed_string[] = ""  # Clear textbox
                    polygon_vertices_per_image[col_idx_selector][] = Bas3GLMakie.GLMakie.Point2f[]  # Clear visual overlay
                    status_label.text = "Bereit für neues Polygon"
                    status_label.color = :blue
                else
                    # Extract polygon ID from selection string "ID:X ..."
                    m = match(r"ID:(\d+)", sel)
                    if !isnothing(m)
                        selected_id = parse(Int, m.captures[1])
                        active_polygon_id_per_image[col_idx_selector][] = selected_id
                        
                        # Populate textbox with current ID
                        id_str = string(selected_id)
                        println("[UI-SELECTOR] Populating textbox with ID=$id_str")
                        polygon_id_textbox.displayed_string[] = id_str
                        println("[UI-SELECTOR] Textbox value after assignment: '$(polygon_id_textbox.displayed_string[])')")
                        
                        # Get polygon details
                        poly = get_polygon_by_id(col_idx_selector, selected_id)
                        if !isnothing(poly)
                            # Update drawing layer to show selected polygon (Option A: Simple visual feedback)
                            polygon_vertices_per_image[col_idx_selector][] = poly.vertices
                            polygon_active_per_image[col_idx_selector][] = false  # Not in active drawing mode
                            polygon_complete_per_image[col_idx_selector][] = poly.complete
                            
                            display_name = isempty(poly.class_name) ? CLASS_NAMES_DE[poly.class] : poly.class_name
                            status_label.text = "Ausgewählt: $display_name #$(poly.sample_number)"
                            status_label.color = get_class_color(poly.class)
                            println("[UI-SELECTOR] Showing polygon vertices on image: $(length(poly.vertices)) vertices")
                        end
                    end
                end
            end
            
            # Set column proportions for Row 2: 30%, 15%, 55%
            Bas3GLMakie.GLMakie.colsize!(class_selector_grid, 1, Bas3GLMakie.GLMakie.Relative(0.30))  # Class dropdown
            Bas3GLMakie.GLMakie.colsize!(class_selector_grid, 2, Bas3GLMakie.GLMakie.Relative(0.15))  # ID textbox
            Bas3GLMakie.GLMakie.colsize!(class_selector_grid, 3, Bas3GLMakie.GLMakie.Relative(0.55))  # Polygon selector
            
            # Add visual grouping gaps
            Bas3GLMakie.GLMakie.colgap!(class_selector_grid, 1, Bas3GLMakie.GLMakie.Relative(0.01))  # Class → ID
            Bas3GLMakie.GLMakie.colgap!(class_selector_grid, 2, Bas3GLMakie.GLMakie.Relative(0.03))  # ID → Selector
            
            # Wire class menu to observable
            local col_idx_class = col
            Bas3GLMakie.GLMakie.on(class_menu.selection) do sel
                for (class_sym, german_name) in CLASS_NAMES_DE
                    if german_name == sel
                        selected_class_per_image[col_idx_class][] = class_sym
                        println("[CLASS-SELECT] Column $col_idx_class: Selected class $class_sym")
                        break
                    end
                end
            end
            
            # NOTE: Do NOT set column sizes - let GLMakie auto-size to avoid BoundsError during rebuild
            # The textbox will auto-size based on its content/placeholder
            
            # Placeholder for custom class name textbox - DEFERRED due to GLMakie layout issues
            local custom_class_textbox = (displayed_string = Ref(""),)  # Mock object with empty string
            
            # Row 3: Consolidated control buttons (Create + Edit + Finalize + Mask)
            local control_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[3, col])
            
            # IMPORTANT: Capture loop variable by VALUE to avoid closure issues
            local col_captured = col
            
            # Capture mask existence state for this column (plain Bool, not reactive)
            local mask_exists_for_col = saved_mask_exists[col_captured]
            
            # Get initial button state from observable
            local initial_visible = saved_mask_visible[col_captured][]
            local initial_label = initial_visible ? "Maske AN" : "Maske AUS"
            local initial_color = if !mask_exists_for_col
                Bas3GLMakie.GLMakie.RGBf(0.7, 0.7, 0.7)  # Gray if no mask
            else
                initial_visible ? Bas3GLMakie.GLMakie.RGBf(0.9, 0.9, 0.3) : Bas3GLMakie.GLMakie.RGBf(0.7, 0.7, 0.7)  # Yellow when visible, gray when hidden
            end
            
            # Row 3: Actions - CREATE | EDIT | FINALIZE | PERSISTENCE
            # Column 1: Create new polygon button (CREATE group)
            local create_poly_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 1],
                label="+ Neu",
                fontsize=FONT_SIZE_BUTTON
            )
            
            # Column 2: Edit button (EDIT group)
            local edit_poly_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 2],
                label="Bearb",
                fontsize=FONT_SIZE_BUTTON,
                buttoncolor=Bas3GLMakie.GLMakie.RGBf(0.7, 0.7, 0.7)  # Start grayed out
            )
            
            # Column 3: Undo button (EDIT group)
            local undo_vertex_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 3],
                label="Zurck",
                fontsize=FONT_SIZE_BUTTON
            )
            
            # Column 4: Delete button (EDIT group)
            local delete_poly_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 4],
                label="Losch",
                fontsize=FONT_SIZE_BUTTON,
                buttoncolor=Bas3GLMakie.GLMakie.RGBf(0.9, 0.3, 0.3)  # Red for destructive action
            )
            
            # Column 5: Close/OK button (FINALIZE group)
            local close_poly_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 5],
                label="OK",
                fontsize=FONT_SIZE_BUTTON
            )
            
            # Column 6: Toggle mask button (PERSISTENCE group)
            local toggle_mask_btn = Bas3GLMakie.GLMakie.Button(
                control_grid[1, 6],
                label = initial_label,
                fontsize = FONT_SIZE_BUTTON,
                buttoncolor = initial_color
            )
            
            # Push buttons
            push!(polygon_buttons_per_image, (create_poly_btn, edit_poly_btn, close_poly_btn, undo_vertex_btn, delete_poly_btn, toggle_mask_btn))
            
            # Set column sizing for Row 3: 12%, 12%, 12%, 12%, 32%, 20%
            Bas3GLMakie.GLMakie.colsize!(control_grid, 1, Bas3GLMakie.GLMakie.Relative(0.12))  # + Neu
            Bas3GLMakie.GLMakie.colsize!(control_grid, 2, Bas3GLMakie.GLMakie.Relative(0.12))  # Bearb
            Bas3GLMakie.GLMakie.colsize!(control_grid, 3, Bas3GLMakie.GLMakie.Relative(0.12))  # Zurck
            Bas3GLMakie.GLMakie.colsize!(control_grid, 4, Bas3GLMakie.GLMakie.Relative(0.12))  # Losch
            Bas3GLMakie.GLMakie.colsize!(control_grid, 5, Bas3GLMakie.GLMakie.Relative(0.32))  # OK (larger - includes save)
            Bas3GLMakie.GLMakie.colsize!(control_grid, 6, Bas3GLMakie.GLMakie.Relative(0.20))  # Maske
            
            # Set column gaps for visual grouping: CREATE | EDIT | FINALIZE | PERSISTENCE
            Bas3GLMakie.GLMakie.colgap!(control_grid, 1, Bas3GLMakie.GLMakie.Relative(0.02))   # + Neu → Bearb (group separator)
            Bas3GLMakie.GLMakie.colgap!(control_grid, 2, Bas3GLMakie.GLMakie.Relative(0.01))   # Bearb → Zurck (small)
            Bas3GLMakie.GLMakie.colgap!(control_grid, 3, Bas3GLMakie.GLMakie.Relative(0.01))   # Zurck → Losch (small)
            Bas3GLMakie.GLMakie.colgap!(control_grid, 4, Bas3GLMakie.GLMakie.Relative(0.02))   # Losch → OK (group separator)
            Bas3GLMakie.GLMakie.colgap!(control_grid, 5, Bas3GLMakie.GLMakie.Relative(0.02))   # OK → Maske (group separator)
            
            # Polygon button callbacks (capture col index for this specific image)
            local col_idx = col
            
            # Create new polygon button - UPDATED FOR MULTI-POLYGON (only creates new)
            Bas3GLMakie.GLMakie.on(create_poly_btn.clicks) do n
                # Always create new polygon
                println("[UI-BTN-CREATE] '+ Neu' button clicked for column $col_idx")
                
                # Get selected class
                current_class = selected_class_per_image[col_idx][]
                println("[UI-BTN-CREATE] Selected class: $current_class")
                
                # Get custom class name from textbox (fallback to empty string)
                custom_name = something(custom_class_textbox.displayed_string[], "")
                if !isempty(custom_name)
                    println("[UI-BTN-CREATE] Custom class name provided: '$custom_name'")
                end
                
                # Get manual ID from textbox (fallback to auto-increment)
                polygon_id_str = something(polygon_id_textbox.displayed_string[], "")
                manual_id = if isempty(polygon_id_str)
                    println("[UI-BTN-CREATE] No manual ID specified, using auto-increment")
                    nothing
                else
                    # Parse user input
                    try
                        id_val = parse(Int, polygon_id_str)
                        if id_val <= 0
                            println("[UI-BTN-CREATE] Invalid ID '$polygon_id_str' (must be > 0), falling back to auto-increment")
                            nothing
                        else
                            println("[UI-BTN-CREATE] Manual ID provided: $id_val")
                            id_val
                        end
                    catch e
                        println("[UI-BTN-CREATE] Invalid ID input '$polygon_id_str', falling back to auto-increment")
                        nothing
                    end
                end
                
                # Auto-increment sample number logic (unchanged)
                current_polygons = polygons_per_image[col_idx][]
                max_sample = 0
                for p in current_polygons
                    if p.class == current_class && p.sample_number > max_sample
                        max_sample = p.sample_number
                    end
                end
                sample_num = max_sample + 1
                println("[UI-BTN-CREATE] Auto-incrementing sample number: $sample_num (existing polygons of this class: $(count(p -> p.class == current_class, current_polygons)))")
                
                # Use German class name if custom name is empty
                final_class_name = isempty(custom_name) ? CLASS_NAMES_DE[current_class] : custom_name
                
                # Create new polygon with empty vertices (pass manual_id if provided)
                println("[UI-BTN-CREATE] Creating polygon: class=$current_class, name='$final_class_name', sample=$sample_num, manual_id=$(isnothing(manual_id) ? "auto" : manual_id)")
                new_id = add_polygon_to_collection!(col_idx, current_class, final_class_name, sample_num, Bas3GLMakie.GLMakie.Point2f[]; manual_id=manual_id)
                println("[UI-BTN-CREATE] Polygon created with ID=$new_id")
                
                # Populate textbox with created ID (so user sees what ID was assigned)
                polygon_id_textbox.displayed_string[] = string(new_id)
                
                # Set as active polygon
                active_polygon_id_per_image[col_idx][] = new_id
                println("[UI-BTN-CREATE] Set polygon ID=$new_id as active for column $col_idx")
                
                # Legacy support: also set old polygon state
                polygon_vertices_per_image[col_idx][] = Bas3GLMakie.GLMakie.Point2f[]
                polygon_active_per_image[col_idx][] = true
                polygon_complete_per_image[col_idx][] = false
                
                # Build display name
                display_name = isempty(custom_name) ? CLASS_NAMES_DE[current_class] : custom_name
                status_label.text = "Polygon starten: $display_name #$sample_num (ID=$new_id)"
                status_label.color = get_class_color(current_class)
                println("[UI-BTN-CREATE] Status updated: '$display_name #$sample_num (ID=$new_id)'")
            end
            
            # Edit existing polygon button - NEW
            Bas3GLMakie.GLMakie.on(edit_poly_btn.clicks) do n
                println("[UI-BTN-EDIT] 'Bearb' button clicked for column $col_idx")
                
                # Continue editing selected polygon
                active_id = active_polygon_id_per_image[col_idx][]
                
                if isnothing(active_id)
                    println("[UI-BTN-EDIT] No polygon selected, cannot edit")
                    status_label.text = "Kein Polygon ausgewählt"
                    status_label.color = :orange
                    return
                end
                
                println("[UI-BTN-EDIT] Attempting to edit polygon ID=$active_id")
                poly = get_polygon_by_id(col_idx, active_id)
                if !isnothing(poly)
                    println("[UI-BTN-EDIT] Found polygon: class=$(poly.class), name='$(poly.class_name)', sample=$(poly.sample_number), vertices=$(length(poly.vertices)), complete=$(poly.complete)")
                    
                    # Update legacy state to show existing vertices
                    polygon_vertices_per_image[col_idx][] = poly.vertices
                    polygon_active_per_image[col_idx][] = true
                    polygon_complete_per_image[col_idx][] = false
                    
                    display_name = isempty(poly.class_name) ? CLASS_NAMES_DE[poly.class] : poly.class_name
                    status_label.text = "Bearbeite: $display_name #$(poly.sample_number)"
                    status_label.color = get_class_color(poly.class)
                    println("[UI-BTN-EDIT] Editing started: '$display_name #$(poly.sample_number)' with $(length(poly.vertices)) existing vertices")
                else
                    println("[UI-BTN-EDIT] ERROR: Polygon ID=$active_id not found in collection")
                end
            end
            
            # Close polygon button - UPDATED FOR MULTI-POLYGON + AUTO-SAVE
            Bas3GLMakie.GLMakie.on(close_poly_btn.clicks) do n
                println("[UI-BTN-CLOSE] 'OK' button clicked for column $col_idx")
                active_id = active_polygon_id_per_image[col_idx][]
                
                if isnothing(active_id)
                    println("[UI-BTN-CLOSE] No active polygon to close")
                    status_label.text = "Kein aktives Polygon"
                    status_label.color = :orange
                    return
                end
                
                poly = get_polygon_by_id(col_idx, active_id)
                if isnothing(poly) || length(poly.vertices) < 3
                    vertex_count = isnothing(poly) ? 0 : length(poly.vertices)
                    println("[UI-BTN-CLOSE] Cannot close polygon ID=$active_id: insufficient vertices ($vertex_count < 3)")
                    status_label.text = "Polygon braucht mindestens 3 Punkte"
                    status_label.color = :orange
                    return
                end
                
                println("[UI-BTN-CLOSE] Closing polygon ID=$active_id with $(length(poly.vertices)) vertices")
                
                # NEW: Check if ID was changed in textbox
                local final_polygon_id = active_id
                local id_changed = false
                local old_png_path = nothing
                polygon_id_str = something(polygon_id_textbox.displayed_string[], "")
                
                if !isempty(polygon_id_str)
                    try
                        local requested_id = parse(Int, polygon_id_str)
                        
                        if requested_id != active_id
                            # User changed ID - validate and apply
                            println("[UI-BTN-CLOSE] ID change requested: $active_id → $requested_id")
                            
                            if requested_id <= 0
                                status_label.text = "Ungültige ID: muss > 0 sein"
                                status_label.color = :red
                                println("[UI-BTN-CLOSE] ✗ Invalid ID: $requested_id <= 0")
                                return
                            end
                            
                            current_polygons = polygons_per_image[col_idx][]
                            if any(p -> p.id == requested_id && p.id != active_id, current_polygons)
                                status_label.text = "ID $requested_id bereits vergeben"
                                status_label.color = :red
                                println("[UI-BTN-CLOSE] ✗ Duplicate ID: $requested_id")
                                return
                            end
                            
                            # NEW: Build old PNG filename before ID change (for deletion later)
                            local entry = current_entries[][col_idx]
                            local base_dir = dirname(get_database_path())
                            local patient_num = lpad(entry.image_index, 3, '0')
                            local patient_folder = joinpath(base_dir, "MuHa_$(patient_num)")
                            local old_filename = construct_polygon_mask_filename(entry.image_index, poly)
                            old_png_path = joinpath(patient_folder, old_filename)
                            println("[UI-BTN-CLOSE] Old PNG path (will delete): $old_png_path")
                            
                            # Apply ID change
                            (success, msg) = update_polygon_id!(col_idx, active_id, requested_id)
                            if !success
                                status_label.text = msg
                                status_label.color = :red
                                println("[UI-BTN-CLOSE] ✗ ID update failed: $msg")
                                return
                            end
                            
                            final_polygon_id = requested_id
                            id_changed = true
                            println("[UI-BTN-CLOSE] ✓ Updated polygon ID: $active_id → $requested_id")
                            
                            # Refresh polygon reference after ID change
                            poly = get_polygon_by_id(col_idx, final_polygon_id)
                            if isnothing(poly)
                                status_label.text = "Fehler: Polygon nach ID-Änderung nicht gefunden"
                                status_label.color = :red
                                return
                            end
                            
                            # Refresh polygon list to show new ID in dropdown
                            Bas3GLMakie.GLMakie.notify(polygons_per_image[col_idx])
                        end
                    catch e
                        status_label.text = "Ungültige ID-Eingabe: $polygon_id_str"
                        status_label.color = :red
                        println("[UI-BTN-CLOSE] ✗ Failed to parse ID: $polygon_id_str")
                        return
                    end
                end
                
                # Extract L*C*h values
                local entry = current_entries[][col_idx]
                local img_data = get(cached_lookup, entry.image_index, nothing)
                
                if isnothing(img_data)
                    println("[UI-BTN-CLOSE] ERROR: Image data not available for image $(entry.image_index)")
                    status_label.text = "Fehler: Bilddaten nicht verfügbar"
                    status_label.color = :red
                    return
                end
                
                println("[UI-BTN-CLOSE] Extracting L*C*h values from image $(entry.image_index)")
                local lch_result = extract_polygon_lch_values(
                    img_data.input_raw,
                    poly.vertices,
                    img_data.input_rotated
                )
                println("[UI-BTN-CLOSE] L*C*h extraction complete: $(lch_result.count) pixels, L*=$(round(lch_result.median_l, digits=2)), C*=$(round(lch_result.median_c, digits=2)), h°=$(round(lch_result.median_h, digits=2))")
                
                # Mark polygon as complete
                new_poly = PolygonEntry(
                    final_polygon_id,  # Use final ID (after potential change)
                    poly.class, 
                    poly.class_name, 
                    poly.sample_number, 
                    poly.vertices, 
                    true,  # complete = true
                    lch_result
                )
                update_polygon!(col_idx, final_polygon_id, new_poly)
                println("[UI-BTN-CLOSE] Polygon ID=$final_polygon_id marked as complete")
                
                # NEW: Save metadata JSON automatically
                current_polygons = polygons_per_image[col_idx][]
                json_success = save_multiclass_metadata(entry.image_index, current_polygons)
                
                if !json_success
                    status_label.text = "Fehler beim Speichern der Metadaten"
                    status_label.color = :red
                    println("[UI-BTN-CLOSE] ✗ Failed to save metadata")
                    return
                end
                println("[UI-BTN-CLOSE] ✓ Metadata saved successfully")
                
                # NEW: Export PNG files automatically
                status_label.text = "Speichere PNG-Masken..."
                status_label.color = :blue
                
                png_success, png_msg, png_detail = save_polygon_mask_for_column(col_idx)
                
                if !png_success
                    status_label.text = "Metadaten OK, PNG-Fehler: $png_msg"
                    status_label.color = :orange
                    println("[UI-BTN-CLOSE] ⚠ PNG export failed: $png_msg")
                    # Continue anyway - polygon is complete even if PNG failed
                else
                    println("[UI-BTN-CLOSE] ✓ PNG export successful: $png_msg")
                    
                    # NEW: Delete old PNG file if ID was changed
                    if id_changed && !isnothing(old_png_path) && isfile(old_png_path)
                        try
                            rm(old_png_path)
                            println("[UI-BTN-CLOSE] ✓ Deleted old PNG file: $(basename(old_png_path))")
                        catch e
                            @warn "[UI-BTN-CLOSE] ⚠ Failed to delete old PNG: $old_png_path - $e"
                        end
                    end
                end
                
                # Clear active polygon state
                active_polygon_id_per_image[col_idx][] = nothing
                polygon_complete_per_image[col_idx][] = true
                polygon_active_per_image[col_idx][] = false
                
                # Legacy support: update old state
                if col_idx <= length(lch_polygon_data)
                    lch_polygon_data[col_idx] = lch_result
                end
                
                # Build display name for final status
                display_name = isempty(poly.class_name) ? CLASS_NAMES_DE[poly.class] : poly.class_name
                status_label.text = "✓ $display_name #$(poly.sample_number): $(lch_result.count) Pixel gespeichert"
                status_label.color = :green
                println("[UI-BTN-CLOSE] ✓ Polygon finalized and saved successfully")
            end
            
            # Undo last vertex button - NEW
            Bas3GLMakie.GLMakie.on(undo_vertex_btn.clicks) do n
                println("[UI-BTN-UNDO] 'Zurck' button clicked for column $col_idx")
                vertices = polygon_vertices_per_image[col_idx][]
                
                if isempty(vertices)
                    println("[UI-BTN-UNDO] No vertices to remove")
                    status_label.text = "Keine Punkte zum Entfernen"
                    status_label.color = :orange
                    return
                end
                
                println("[UI-BTN-UNDO] Removing last vertex (current count: $(length(vertices)))")
                
                # Remove last vertex
                new_vertices = vertices[1:end-1]
                polygon_vertices_per_image[col_idx][] = new_vertices
                
                # Also update active polygon in collection
                active_id = active_polygon_id_per_image[col_idx][]
                if !isnothing(active_id)
                    poly = get_polygon_by_id(col_idx, active_id)
                    if !isnothing(poly)
                        println("[UI-BTN-UNDO] Updating polygon ID=$active_id in collection")
                        updated_poly = PolygonEntry(poly.id, poly.class, poly.class_name, poly.sample_number, new_vertices, false, nothing)
                        update_polygon!(col_idx, active_id, updated_poly)
                        println("[UI-BTN-UNDO] Polygon ID=$active_id updated successfully")
                    else
                        println("[UI-BTN-UNDO] WARNING: Active polygon ID=$active_id not found in collection")
                    end
                else
                    println("[UI-BTN-UNDO] No active polygon ID set")
                end
                
                status_label.text = "Letzter Punkt entfernt ($(length(new_vertices)) übrig)"
                status_label.color = :blue
                println("[UI-BTN-UNDO] Undo complete: $(length(new_vertices)) vertices remaining")
            end
            
            # Delete polygon button - NEW
            Bas3GLMakie.GLMakie.on(delete_poly_btn.clicks) do n
                println("[UI-BTN-DELETE] 'Losch' button clicked for column $col_idx")
                
                active_id = active_polygon_id_per_image[col_idx][]
                println("[UI-BTN-DELETE] Active polygon ID: $(isnothing(active_id) ? "none" : active_id)")
                
                if isnothing(active_id)
                    println("[UI-BTN-DELETE] ERROR: No polygon selected for deletion")
                    status_label.text = "Kein Polygon ausgewählt"
                    status_label.color = :orange
                    return
                end
                
                # Get polygon details before deletion for logging
                poly_to_delete = get_polygon_by_id(col_idx, active_id)
                if !isnothing(poly_to_delete)
                    println("[UI-BTN-DELETE] Deleting polygon: ID=$active_id, class=$(poly_to_delete.class), sample=$(poly_to_delete.sample_number), vertices=$(length(poly_to_delete.vertices)), complete=$(poly_to_delete.complete)")
                else
                    println("[UI-BTN-DELETE] WARNING: Polygon ID=$active_id not found in collection")
                end
                
                # Remove from collection
                println("[UI-BTN-DELETE] Removing polygon ID=$active_id from collection")
                remove_polygon_from_collection!(col_idx, active_id)
                
                # Clear active state
                println("[UI-BTN-DELETE] Clearing active polygon state for column $col_idx")
                active_polygon_id_per_image[col_idx][] = nothing
                polygon_vertices_per_image[col_idx][] = Bas3GLMakie.GLMakie.Point2f[]
                polygon_active_per_image[col_idx][] = false
                polygon_complete_per_image[col_idx][] = false
                
                println("[UI-BTN-DELETE] Polygon ID=$active_id successfully deleted")
                status_label.text = "Polygon ID=$active_id gelöscht"
                status_label.color = :green
            end
            
            
            # Toggle mask overlay button
            Bas3GLMakie.GLMakie.on(toggle_mask_btn.clicks) do n
                if saved_mask_exists[col_idx]
                    # Toggle visibility observable
                    saved_mask_visible[col_idx][] = !saved_mask_visible[col_idx][]
                    
                    # Manually update button appearance (Button attributes are not reactive)
                    local new_visible = saved_mask_visible[col_idx][]
                    toggle_mask_btn.label = new_visible ? "Maske AN" : "Maske AUS"
                    toggle_mask_btn.buttoncolor = new_visible ? Bas3GLMakie.GLMakie.RGBf(0.9, 0.9, 0.3) : Bas3GLMakie.GLMakie.RGBf(0.7, 0.7, 0.7)
                    
                    println("[MASK-OVERLAY] Toggle mask visibility for column $col_idx: $(saved_mask_visible[col_idx][])")
                else
                    println("[MASK-OVERLAY] No saved mask for column $col_idx")
                    status_label.text = "Keine gespeicherte Maske für dieses Bild"
                    status_label.color = :orange
                end
            end
            
            # Update edit button state when active polygon changes
            Bas3GLMakie.GLMakie.on(active_polygon_id_per_image[col_idx_list]) do active_id
                # Update edit button state
                if isnothing(active_id)
                    edit_poly_btn.buttoncolor = Bas3GLMakie.GLMakie.RGBf(0.7, 0.7, 0.7)  # Grayed out
                else
                    edit_poly_btn.buttoncolor = Bas3GLMakie.GLMakie.RGBf(0.3, 0.7, 0.9)  # Blue when polygon selected
                end
            end
            
            # Row 4: Patient metadata section with header (moved from Row 5)
            local data_grid = Bas3GLMakie.GLMakie.GridLayout(images_grid[4, col])
            

            
            # Header row: "Bild X" label + Save button
            Bas3GLMakie.GLMakie.Label(
                data_grid[1, 1],
                "Bild $(entry.image_index)",
                fontsize=FONT_SIZE_SECTION,
                font=:bold,
                halign=:left,
                valign=:center
            )
            
            local save_btn = Bas3GLMakie.GLMakie.Button(
                data_grid[1, 2],
                label="Speichern",
                fontsize=FONT_SIZE_BUTTON
            )
            push!(save_buttons, save_btn)
            
            # Save button callback (capture variables for closure)
            local entry_row = entry.row
            local entry_idx = entry.image_index
            local col_idx = col
            local original_patient_id = patient_id  # Capture current patient ID
            
            Bas3GLMakie.GLMakie.on(save_btn.clicks) do n
                println("[COMPARE-UI] Save clicked for image $entry_idx (column $col_idx)")
                
                # Get current values from textboxes
                new_date = something(date_textboxes[col_idx].displayed_string[], "")
                new_info = something(info_textboxes[col_idx].displayed_string[], "")
                
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
                
                # Update database (patient ID reassignment removed - use original patient_id)
                try
                    success = update_image_metadata(db_path, entry_row, new_date, new_info)
                    
                    if success
                        status_label.text = "Bild $entry_idx gespeichert"
                        status_label.color = :green
                        
                        # Update current_entries to reflect changes
                        updated_entry = (
                            row = entry_row,
                            patient_id = original_patient_id,  # Keep original patient ID
                            image_index = entry_idx,
                            date = new_date,
                            info = new_info
                        )
                        
                        local entries = current_entries[]
                        entries[col_idx] = updated_entry
                        current_entries[] = entries
                    else
                        status_label.text = "Fehler beim Speichern von Bild $entry_idx"
                        status_label.color = :red
                    end
                catch e
                    @warn "[COMPARE-UI] Error saving metadata: $e"
                    status_label.text = "Fehler beim Speichern: $(typeof(e))"
                    status_label.color = :red
                end
            end
            
            # Date section (row 2)
            Bas3GLMakie.GLMakie.Label(
                data_grid[2, 1],
                "Datum:",
                fontsize=FONT_SIZE_LABEL,
                halign=:right,
                valign=:center
            )
            
            local date_box = Bas3GLMakie.GLMakie.Textbox(
                data_grid[2, 2],
                placeholder="YYYY-MM-DD",
                stored_string=entry.date
            )
            push!(date_textboxes, date_box)
            
            # Info section (row 3)
            Bas3GLMakie.GLMakie.Label(
                data_grid[3, 1],
                "Info:",
                fontsize=FONT_SIZE_LABEL,
                halign=:right,
                valign=:top
            )
            
            local info_box = Bas3GLMakie.GLMakie.Textbox(
                data_grid[3, 2],
                placeholder="Zusatzinformationen",
                stored_string=entry.info
            )
            push!(info_textboxes, info_box)
            
            # Set proportional columns AFTER widgets are created
            # Column 1: 50% (for "Bild X" label), Column 2: 50% (for save button)
            Bas3GLMakie.GLMakie.colsize!(data_grid, 1, Bas3GLMakie.GLMakie.Relative(0.50))
            Bas3GLMakie.GLMakie.colsize!(data_grid, 2, Bas3GLMakie.GLMakie.Relative(0.50))
            
            # Set relative row sizing for data_grid (required when using Relative() gaps)
            # Parent row 4 = 12% of images_grid ≈ 108px @ 900px window
            # Now 3 rows: Header+Button (25%), Date (35%), Info (35%)
            Bas3GLMakie.GLMakie.rowsize!(data_grid, 1, Bas3GLMakie.GLMakie.Relative(0.25))   # Header+Button 25%
            Bas3GLMakie.GLMakie.rowsize!(data_grid, 2, Bas3GLMakie.GLMakie.Relative(0.35))   # Date row 35%
            Bas3GLMakie.GLMakie.rowsize!(data_grid, 3, Bas3GLMakie.GLMakie.Relative(0.35))   # Info row 35%
            
            # Set relative row gaps within data_grid (percentage of parent row 4 height)
            Bas3GLMakie.GLMakie.rowgap!(data_grid, 1, Bas3GLMakie.GLMakie.Relative(0.02))    # After header (2%)
            Bas3GLMakie.GLMakie.rowgap!(data_grid, 2, Bas3GLMakie.GLMakie.Relative(0.03))   # Between date and info (3%)
            
        end
        
        # Pure relative sizing: Percentage-based rows and gaps (5 rows total for streamlined UI)
        # Row heights and gaps scale proportionally with window size
        # Save button now integrated into Row 4 (metadata section)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 1, Bas3GLMakie.GLMakie.Relative(0.60))  # Image 60%
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 2, Bas3GLMakie.GLMakie.Relative(0.04))  # Create & Select row 4%
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 3, Bas3GLMakie.GLMakie.Relative(0.04))  # Action buttons row 4%
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 4, Bas3GLMakie.GLMakie.Relative(0.16))  # Metadata + Save button 16%
        
        Bas3GLMakie.GLMakie.rowgap!(images_grid, 1, Bas3GLMakie.GLMakie.Relative(0.01))   # After image
        Bas3GLMakie.GLMakie.rowgap!(images_grid, 2, Bas3GLMakie.GLMakie.Relative(0.005))  # After Create & Select
        Bas3GLMakie.GLMakie.rowgap!(images_grid, 3, Bas3GLMakie.GLMakie.Relative(0.01))   # After Action buttons
        
        local widget_creation_time = time() - widget_creation_start
        println("[PERF-BUILD] Widget creation ($(num_images) images): $(round(widget_creation_time*1000, digits=2))ms")
        
        # ====================================================================
        # CREATE L*C*h TIMELINE PLOT (auto-load from .bin masks + manual override)
        # ====================================================================
        
        # AUTOMATIC: Compute L*C*h from saved polygon mask .bin files (MULTI-CLASS)
        println("[COMPARE-UI] Computing L*C*h from saved masks for $(length(entries[1:num_images])) images...")
        local lch_compute_time = @elapsed begin
            lch_multiclass_data = compute_lch_from_saved_masks_multiclass(entries[1:num_images], cached_lookup)
        end
        println("[PERF-BUILD] LCh computation: $(round(lch_compute_time*1000, digits=2))ms")
        
        # Create timeline (handles NaN values for missing masks, ONLY if timeline VISIBLE)
        local timeline_create_time = @elapsed begin
            if !isnothing(timeline_grid_lch[]) && timeline_visible[]
                # Timeline is visible - create/update it
                delete_gridlayout_contents!(timeline_grid_lch[])
                timeline_axis_lch[] = create_multiclass_lch_timeline!(timeline_grid_lch[], entries[1:num_images], lch_multiclass_data)
                println("[PERF-BUILD] Timeline created (visible)")
            elseif !timeline_visible[]
                # Timeline is hidden - ensure it stays empty
                if !isnothing(timeline_grid_lch[])
                    delete_gridlayout_contents!(timeline_grid_lch[])
                end
                timeline_axis_lch[] = nothing
                println("[PERF-BUILD] Timeline skipped (hidden)")
            end
        end
        println("[PERF-BUILD] Timeline operation: $(round(timeline_create_time*1000, digits=2))ms")
        
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
        
        # Set column widths (responsive - equal distribution)
        for col in 1:num_images
            Bas3GLMakie.GLMakie.colsize!(images_grid, col, Bas3GLMakie.GLMakie.Relative(1.0 / num_images))
        end
        
        # Pure relative sizing: All rows use Auto() (natural widget sizing)
        # No explicit rowsize needed - widgets determine their own natural height
        
            # Log timing
            local build_elapsed = round((time() - build_start_time) * 1000, digits=1)
            println("[COMPARE-UI] Build completed in $(build_elapsed)ms (CACHE HIT)")
            
            # PROACTIVE PRELOADING: Start loading adjacent patients in background
            # This makes navigation feel instant
            local current_idx = findfirst(==(patient_id), all_patient_ids)
            if !isnothing(current_idx)
                # Preload next patient (if exists)
                if current_idx < length(all_patient_ids)
                    local next_patient_id = all_patient_ids[current_idx + 1]
                    trigger_preload(next_patient_id)
                    println("[PRELOAD-PROACTIVE] Triggered preload for next patient: $next_patient_id")
                end
                
                # Preload previous patient (if exists)
                if current_idx > 1
                    local prev_patient_id = all_patient_ids[current_idx - 1]
                    trigger_preload(prev_patient_id)
                    println("[PRELOAD-PROACTIVE] Triggered preload for previous patient: $prev_patient_id")
                end
            end
            
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
    
    # Filter menu callback
    Bas3GLMakie.GLMakie.on(filter_menu.selection) do selected
        if !isnothing(selected)
            # Map selection to exact image count
            target_count = if selected == "Alle"
                0
            elseif selected == "1 Bild"
                1
            elseif selected == "2 Bilder"
                2
            elseif selected == "3 Bilder"
                3
            elseif selected == "4 Bilder"
                4
            elseif selected == "5 Bilder"
                5
            else
                0
            end
            
            exact_image_filter[] = target_count
            
            println("[FILTER] Applying filter: exactly $target_count images")
            
            # Apply filter
            counts = patient_image_counts[]
            all_pids = get_all_patient_ids(db_path)
            filtered = filter_patients_by_exact_count(all_pids, counts, target_count)
            
            filtered_patient_ids[] = filtered
            
            # Update patient menu with filtered list
            if isempty(filtered)
                filter_text = target_count == 1 ? "exakt 1 Bild" : "exakt $target_count Bildern"
                status_label.text = "Keine Patienten mit $filter_text"
                status_label.color = :orange
                patient_menu.options = []
            else
                patient_menu.options = [string(pid) for pid in filtered]
                
                # Select first patient in filtered list
                patient_menu.i_selected[] = 1
                current_patient_id[] = filtered[1]
                build_patient_images!(filtered[1])
                
                filter_text = target_count == 0 ? "alle" : (target_count == 1 ? "exakt 1 Bild" : "exakt $target_count Bilder")
                status_label.text = "$(length(filtered)) Patienten ($filter_text)"
                status_label.color = :green
            end
        end
    end
    
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
        
        # Recompute image counts
        patient_image_counts[] = get_patient_image_counts(db_path)
        
        # Apply current filter
        counts = patient_image_counts[]
        target_count = exact_image_filter[]
        filtered = filter_patients_by_exact_count(new_patient_ids, counts, target_count)
        
        filtered_patient_ids[] = filtered
        
        if isempty(filtered)
            filter_text = target_count == 1 ? "exakt 1 Bild" : "exakt $target_count Bildern"
            status_label.text = "Keine Patienten mit $filter_text"
            status_label.color = :orange
            patient_menu.options = []
            return
        end
        
        # Update menu with filtered list
        patient_menu.options = [string(pid) for pid in filtered]
        
        # Rebuild current patient if still in filtered list
        if current_patient_id[] in filtered
            build_patient_images!(current_patient_id[])
        else
            # Switch to first patient in filtered list
            current_patient_id[] = filtered[1]
            patient_menu.i_selected[] = 1
            build_patient_images!(filtered[1])
        end
        
        filter_text = target_count == 0 ? "" : (target_count == 1 ? " (exakt 1 Bild)" : " (exakt $(target_count) Bilder)")
        status_label.text = "Liste aktualisiert: $(length(filtered)) Patienten$(filter_text)"
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
                                
                                # BUGFIX: Also update active polygon in collection with new vertices
                                local active_id = active_polygon_id_per_image[col_idx][]
                                if !isnothing(active_id)
                                    local poly = get_polygon_by_id(col_idx, active_id)
                                    if !isnothing(poly)
                                        local updated_poly = PolygonEntry(poly.id, poly.class, poly.class_name, poly.sample_number, current_verts, false, nothing)
                                        update_polygon!(col_idx, active_id, updated_poly)
                                        println("[POLYGON] Updated polygon ID=$active_id in collection (now $(length(current_verts)) vertices)")
                                    end
                                end
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
        local available_patients = filtered_patient_ids[]
        
        if target_idx < 1 || target_idx > length(available_patients)
            println("[NAV] Index $target_idx out of bounds (1-$(length(available_patients)))")
            return
        end
        
        local target_patient_id = available_patients[target_idx]
        println("[NAV] Navigating to patient index $target_idx (patient_id=$target_patient_id)")
        
        # Update current patient
        current_patient_id[] = target_patient_id
        patient_menu.i_selected[] = target_idx
        
        # Build images (will use cache if available)
        build_patient_images!(target_patient_id)
        
        # Clean up old cache entries
        cleanup_cache(target_patient_id)
        
        # Trigger preloads for neighbors (within filtered list)
        if target_idx > 1
            trigger_preload(available_patients[target_idx - 1])
        end
        if target_idx < length(available_patients)
            trigger_preload(available_patients[target_idx + 1])
        end
    end
    
    # Previous button callback
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do n
        local available_patients = filtered_patient_ids[]
        local current_idx = findfirst(==(current_patient_id[]), available_patients)
        if isnothing(current_idx)
            println("[NAV] Current patient not found in filtered list")
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
        local available_patients = filtered_patient_ids[]
        local current_idx = findfirst(==(current_patient_id[]), available_patients)
        if isnothing(current_idx)
            println("[NAV] Current patient not found in filtered list")
            return
        end
        
        if current_idx >= length(available_patients)
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
    println("=== Polygon Analysis Workflow ===")
    println("  1. Click 'Polygon' button to activate drawing mode")
    println("  2. Click on image to add vertices (cyan points)")
    println("  3. Click 'Schließen' to close polygon and extract L*C*h values")
    println("  4. Timeline updates automatically with median L*C*h values")
    println("  5. Click 'Löschen' to clear polygon and start over")
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
                :filter_menu => filter_menu,       # NEW: Filter menu for testing
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
                :image_observables => image_observables,
                # :hsv_grids => hsv_grids,  # TODO: Not implemented yet
                # :hsv_class_data => hsv_class_data,  # TODO: Not implemented yet
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
                :save_polygon_mask_for_column => save_polygon_mask_for_column,   # NEW: Programmatic mask save
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
