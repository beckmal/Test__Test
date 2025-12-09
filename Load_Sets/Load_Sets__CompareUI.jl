# Load_Sets__CompareUI.jl
# Patient Image Comparison UI - Shows all images for a selected patient

# Required packages for database functionality
using XLSX
using Dates
using LinearAlgebra: eigen
using Statistics: median
using Colors: N0f8, RGB, LCHab  # Fixed-point normalized UInt8 + color conversion

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
    local rotation_time = 0.0
    
    total_time = @elapsed begin
        local base_dir = dirname(get_database_path())
        local patient_num = lpad(image_index, 3, '0')
        local mask_path = joinpath(base_dir, "MuHa_$(patient_num)", 
                                   "MuHa_$(patient_num)_polygon_mask.png")
        
        file_check_time = @elapsed begin
            if !isfile(mask_path)
                return nothing
            end
        end
        
        try
            # Load PNG directly with FileIO
            local img = nothing
            png_load_time = @elapsed begin
                img = Bas3GLMakie.GLMakie.FileIO.load(mask_path)
            end
            
            # Convert to RGB{Float32}
            local h, w = size(img)
            local mask_rgb = nothing
            
            convert_time = @elapsed begin
                mask_rgb = Matrix{Bas3ImageSegmentation.RGB{Float32}}(undef, h, w)
                
                for i in 1:h, j in 1:w
                    local rgb_val = Bas3ImageSegmentation.RGB(img[i, j])
                    mask_rgb[i, j] = Bas3ImageSegmentation.RGB{Float32}(Float32(rgb_val.r), Float32(rgb_val.g), Float32(rgb_val.b))
                end
            end
            
            # Apply rotr90 to match base image orientation
            # Base image: load from .bin (portrait) → rotr90() → landscape display
            # Mask: load from PNG (portrait) → rotr90() → landscape display (matches base!)
            println("[MASK-LOAD-DEBUG] Before rotr90: $(size(mask_rgb))")
            local mask_rotated = nothing
            rotation_time = @elapsed begin
                mask_rotated = rotr90(mask_rgb)
            end
            println("[MASK-LOAD-DEBUG] After rotr90: $(size(mask_rotated))")
            
            println("[PERF-MASK-PNG] Image $image_index: total=$(round(total_time*1000, digits=2))ms, file_check=$(round(file_check_time*1000, digits=2))ms, png_load=$(round(png_load_time*1000, digits=2))ms, convert=$(round(convert_time*1000, digits=2))ms, rotate=$(round(rotation_time*1000, digits=2))ms, size=$(size(img))")
            println("[MASK-LOAD] Loaded existing mask for image $(image_index): $(size(mask_rotated)) [FIXED-V4]")
            return mask_rotated
        catch e
            @warn "[MASK-LOAD] Failed to load mask for image $(image_index): $e"
            return nothing
        end
    end
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
    
    # ========================================================================
    # POLYGON MASK EXPORT FUNCTION (for programmatic access)
    # ========================================================================
    
    """
    Save polygon mask for a specific column to PNG file.
    Can be called programmatically for testing or batch processing.
    
    Returns: (success::Bool, message::String, output_path::String)
    """
    function save_polygon_mask_for_column(col_idx::Int)
        # Check if polygon is closed
        if !polygon_complete_per_image[col_idx][]
            return (false, "Polygon muss geschlossen sein zum Speichern", "")
        end
        
        # Check if column index is valid
        if col_idx < 1 || col_idx > length(image_observables)
            return (false, "Ungültiger Spaltenindex: $col_idx", "")
        end
        
        # Get current entry and polygon vertices
        local entry = current_entries[][col_idx]
        local vertices_lowres = polygon_vertices_per_image[col_idx][]
        
        if length(vertices_lowres) < 3
            return (false, "Polygon muss mindestens 3 Vertices haben", "")
        end
        
        println("[MASK-EXPORT] Image index: $(entry.image_index) → Patient folder: MuHa_$(lpad(entry.image_index, 3, '0'))")
        println("[MASK-EXPORT] Polygon vertices (lowres): $(length(vertices_lowres))")
        
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
        println("[MASK-EXPORT] Loading original image: $original_path")
        local original_img_loaded = Bas3GLMakie.GLMakie.FileIO.load(original_path)
        println("[MASK-EXPORT] Original loaded size: $(size(original_img_loaded))")
        
        # Apply same rotation as UI (rotr90 for landscape viewing)
        local original_img_rotated = rotr90(original_img_loaded)
        println("[MASK-EXPORT] Original rotated size: $(size(original_img_rotated))")
        
        # Scale vertices from UI coordinate space to fullres
        # NOTE: The UI image might be downsampled by GLMakie for display!
        # We need to scale based on the ACTUAL displayed image size, not the array size
        local rotated_lowres = image_observables[col_idx][]
        local height_rot_lowres = size(rotated_lowres, 1)   # Height of actual image array in UI
        local width_rot_lowres = size(rotated_lowres, 2)    # Width of actual image array in UI
        local height_rot_fullres = size(original_img_rotated, 1)  # Height of rotated fullres image
        local width_rot_fullres = size(original_img_rotated, 2)   # Width of rotated fullres image
        
        # Scale factors (from UI image to fullres)
        local scale_factor_x = Float32(width_rot_fullres) / Float32(width_rot_lowres)
        local scale_factor_y = Float32(height_rot_fullres) / Float32(height_rot_lowres)
        
        println("[MASK-EXPORT] UI image size: $(height_rot_lowres)×$(width_rot_lowres) (H×W)")
        println("[MASK-EXPORT] Fullres rotated size: $(height_rot_fullres)×$(width_rot_fullres) (H×W)")
        println("[MASK-EXPORT] Scale factors: x=$(scale_factor_x), y=$(scale_factor_y)")
        println("[MASK-EXPORT] Vertices in UI space: ", vertices_lowres)
        
        # Scale vertices to fullres (stay in rotated coordinate space)
        # NOTE: v[1] and v[2] are SWAPPED - v[1]=y, v[2]=x in GLMakie mouse coordinates!
        # NOTE: X-axis is horizontally flipped - need to invert x-coordinate
        local vertices_fullres = [Bas3GLMakie.GLMakie.Point2f(
            width_rot_fullres - (v[2] * scale_factor_x),   # Flip X: width - x
            v[1] * scale_factor_y                            # Y is correct
        ) for v in vertices_lowres]
        println("[MASK-EXPORT] Scaled vertices to fullres rotated space: ", vertices_fullres)
        
        # Generate mask in ROTATED fullres space (matches what user sees in UI)
        local mask_rotated = create_polygon_mask(original_img_rotated, vertices_fullres)
        println("[MASK-EXPORT] Mask generated in rotated space: $(size(mask_rotated))")
        println("[MASK-EXPORT] This is the mask that matches the UI display (landscape)")
        
        # Construct output path
        local output_filename = "MuHa_$(patient_num)_polygon_mask.png"
        local output_path = joinpath(patient_folder, output_filename)
        
        println("[MASK-EXPORT] Saving mask in landscape orientation: $output_path")
        
        # Save mask as PNG (keep in rotated/landscape orientation to match raw file which is also landscape)
        local success, msg = save_polygon_mask_png(mask_rotated, output_path)
        
        if success
            println("[MASK-EXPORT] SUCCESS: $msg")
        else
            println("[MASK-EXPORT] FAILED: $msg")
        end
        
        return (success, msg, output_path)
    end
    
    # ========================================================================
    # BUILD PATIENT IMAGES
    # ========================================================================
    # Cache patient image counts (computed once, updated on refresh)
    local patient_image_counts = Bas3GLMakie.GLMakie.Observable(
        get_patient_image_counts(db_path)
    )
    
    # Current filter setting (0 = no filter, 1+ = exact image count)
    local exact_image_filter = Bas3GLMakie.GLMakie.Observable(0)
    
    # Filtered patient IDs (reactive to filter changes)
    local filtered_patient_ids = Bas3GLMakie.GLMakie.Observable(all_patient_ids)
    
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
    
    # Row 2: Patient ID selector and filter (label + menus)
    local selector_filter_grid = Bas3GLMakie.GLMakie.GridLayout(left_column[2, 1])
    
    # Row 2.1: Patient ID selector
    Bas3GLMakie.GLMakie.Label(
        selector_filter_grid[1, 1],
        "Patient-ID:",
        fontsize=12,
        halign=:right
    )
    local patient_menu = Bas3GLMakie.GLMakie.Menu(
        selector_filter_grid[1, 2],
        options = [string(pid) for pid in all_patient_ids],
        default = isempty(all_patient_ids) ? nothing : string(all_patient_ids[1]),
        width = 100
    )
    
    # Row 2.2: Image count filter
    Bas3GLMakie.GLMakie.Label(
        selector_filter_grid[2, 1],
        "Bilderanzahl:",
        fontsize=12,
        halign=:right
    )
    local filter_menu = Bas3GLMakie.GLMakie.Menu(
        selector_filter_grid[2, 2],
        options = ["Alle", "1 Bild", "2 Bilder", "3 Bilder", "4 Bilder", "5 Bilder"],
        default = "Alle",
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
    
    # Row 8: L*C*h Timeline Plot (polygon-based)
    local timeline_grid_lch = Bas3GLMakie.GLMakie.GridLayout(left_column[8, 1])
    local timeline_axis_lch = Ref{Any}(nothing)  # Will hold LCh axis reference for clearing
    
    # Set left column row sizes
    Bas3GLMakie.GLMakie.rowsize!(left_column, 1, Bas3GLMakie.GLMakie.Fixed(50))   # Title
    Bas3GLMakie.GLMakie.rowsize!(left_column, 2, Bas3GLMakie.GLMakie.Fixed(70))   # Patient selector + filter (2 rows)
    Bas3GLMakie.GLMakie.rowsize!(left_column, 3, Bas3GLMakie.GLMakie.Fixed(35))   # Nav buttons
    Bas3GLMakie.GLMakie.rowsize!(left_column, 4, Bas3GLMakie.GLMakie.Fixed(35))   # Refresh
    Bas3GLMakie.GLMakie.rowsize!(left_column, 5, Bas3GLMakie.GLMakie.Fixed(35))   # Clear polygons
    Bas3GLMakie.GLMakie.rowsize!(left_column, 6, Bas3GLMakie.GLMakie.Fixed(40))   # Status
    Bas3GLMakie.GLMakie.rowsize!(left_column, 7, Bas3GLMakie.GLMakie.Auto())      # Spacer (flexible)
    Bas3GLMakie.GLMakie.rowsize!(left_column, 8, Bas3GLMakie.GLMakie.Fixed(560))  # L*C*h Timeline (expanded)
    
    # ========================================================================
    # RIGHT COLUMN: Images Container (scrollable grid)
    # ========================================================================
    local images_grid = Bas3GLMakie.GLMakie.GridLayout(right_column[1, 1])
    
    # Store references to dynamically created widgets
    local image_axes = Bas3GLMakie.GLMakie.Axis[]
    local date_textboxes = []
    local info_textboxes = []
    local patient_id_textboxes = []  # For patient ID reassignment
    local save_buttons = []
    local image_labels = []
    local image_observables = []
    local lch_polygon_data = []   # L*C*h data per polygon (NamedTuple per image)
    
    # POLYGON SELECTION: Per-image polygon state arrays
    local polygon_vertices_per_image = []     # Vector of Observable{Vector{Point2f}}
    local polygon_active_per_image = []       # Vector of Observable{Bool}
    local polygon_complete_per_image = []     # Vector of Observable{Bool}
    local polygon_buttons_per_image = []      # Vector of (close_btn, clear_btn) tuples
    
    # MASK OVERLAY: Per-image saved mask overlay state arrays
    local saved_mask_overlays = []            # Vector of Observable{Union{Matrix{RGBAf}, Nothing}}
    local saved_mask_visible = []             # Vector of Observable{Bool} (show/hide toggle)
    local saved_mask_exists = []              # Vector of Bool (track if saved mask exists)
    
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
    
    # Clear all image widgets - RECURSIVE deletion for nested GridLayouts
    function clear_images_grid!()
        println("[COMPARE-UI] Clearing images grid ($(length(images_grid.content)) items) and timeline...")
        
        # Clear the main images_grid recursively
        delete_gridlayout_contents!(images_grid)
        
        # Clear the LCh timeline_grid
        delete_gridlayout_contents!(timeline_grid_lch)
        timeline_axis_lch[] = nothing
        
        # Clear widget arrays
        empty!(image_axes)
        empty!(date_textboxes)
        empty!(info_textboxes)
        empty!(patient_id_textboxes)
        empty!(save_buttons)
        empty!(image_labels)
        empty!(image_observables)
        empty!(lch_polygon_data)  # Clear L*C*h polygon data
        
        # Clear polygon state arrays
        empty!(polygon_vertices_per_image)
        empty!(polygon_active_per_image)
        empty!(polygon_complete_per_image)
        empty!(polygon_buttons_per_image)
        
        # Clear mask overlay arrays
        empty!(saved_mask_overlays)
        empty!(saved_mask_visible)
        empty!(saved_mask_exists)
        
        println("[COMPARE-UI] Grid cleared, $(length(images_grid.content)) items remaining")
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
                
                # Layer 2: SAVED MASK OVERLAY (display existing polygon masks)
                # Use cached mask data if available, otherwise load from disk
                # Accept both RGB{N0f8} (UInt8-backed) and RGB{Float32}
                local mask_rgb_obs = Bas3GLMakie.GLMakie.Observable{Union{Matrix, Nothing}}(nothing)
                local mask_visible_obs = Bas3GLMakie.GLMakie.Observable(true)  # Visible by default
                
                if haskey(img_data, :mask_exists) && img_data.mask_exists
                    # USE CACHED MASK DATA
                    mask_rgb_obs[] = img_data.mask_resized
                    push!(saved_mask_exists, true)
                    
                    println("[MASK-OVERLAY] Loaded mask from cache for image $(entry.image_index)")
                else
                    # FALLBACK: Load from disk if not in cache
                    local display_height, display_width = size(img_data.input_rotated)
                    local mask_resized = load_mask_for_display(entry.image_index, (display_height, display_width))
                    
                    if !isnothing(mask_resized)
                        mask_rgb_obs[] = mask_resized
                        push!(saved_mask_exists, true)
                        
                        println("[MASK-OVERLAY] Loaded mask from disk for image $(entry.image_index)")
                    else
                        push!(saved_mask_exists, false)
                        println("[MASK-OVERLAY] No saved mask for image $(entry.image_index)")
                    end
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
                
                # Layer 2: SAVED MASK OVERLAY (display existing polygon masks)
                # Load existing mask if available (try .bin first, then PNG)
                local display_height, display_width = size(images.input)
                local mask_resized = load_mask_for_display(entry.image_index, (display_height, display_width))
                # Accept both RGB{N0f8} (UInt8-backed) and RGB{Float32}
                local mask_rgb_obs = Bas3GLMakie.GLMakie.Observable{Union{Matrix, Nothing}}(nothing)
                local mask_visible_obs = Bas3GLMakie.GLMakie.Observable(true)  # Visible by default
                
                if !isnothing(mask_resized)
                    mask_rgb_obs[] = mask_resized
                    push!(saved_mask_exists, true)
                    
                    println("[MASK-OVERLAY] Loaded mask for image $(entry.image_index) (fallback)")
                else
                    push!(saved_mask_exists, false)
                    println("[MASK-OVERLAY] No saved mask for image $(entry.image_index) (fallback)")
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
            
            # Row 3: Polygon control buttons - TOP ROW (Mask toggle)
            local polygon_control_grid_row1 = Bas3GLMakie.GLMakie.GridLayout(images_grid[3, col])
            
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
            
            # Create button with static initial values (Button attributes are not reactive)
            local toggle_mask_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid_row1[1, 1],
                label = initial_label,
                fontsize = 10,
                width = 120,
                buttoncolor = initial_color
            )
            
            # Row 4: Polygon control buttons - BOTTOM ROW (Drawing controls + Save)
            local polygon_control_grid_row2 = Bas3GLMakie.GLMakie.GridLayout(images_grid[4, col])
            
            local start_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid_row2[1, 1],
                label="Polygon",
                fontsize=9,
                width=60
            )
            
            local close_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid_row2[1, 2],
                label="Schließen",
                fontsize=9,
                width=70
            )
            
            local clear_poly_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid_row2[1, 3],
                label="Löschen",
                fontsize=9,
                width=60
            )
            
            local save_mask_btn = Bas3GLMakie.GLMakie.Button(
                polygon_control_grid_row2[1, 4],
                label="PNG speichern",
                fontsize=9,
                width=90
            )
            
            push!(polygon_buttons_per_image, (start_poly_btn, close_poly_btn, clear_poly_btn, save_mask_btn, toggle_mask_btn))
            
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
                    
                    # Extract L*C*h values from polygon region
                    local entry = current_entries[][col_idx]
                    local img_data = get(cached_lookup, entry.image_index, nothing)
                    
                    if !isnothing(img_data)
                        local lch_result = extract_polygon_lch_values(
                            img_data.input_raw,
                            polygon_vertices_per_image[col_idx][],
                            img_data.input_rotated
                        )
                        
                        # Store in lch_polygon_data array
                        lch_polygon_data[col_idx] = lch_result
                        
                        # Rebuild timeline with new data
                        delete_gridlayout_contents!(timeline_grid_lch)
                        timeline_axis_lch[] = create_lch_timeline!(timeline_grid_lch, current_entries[], lch_polygon_data)
                        
                        status_label.text = "Polygon $(col_idx): $(lch_result.count) Pixel analysiert"
                        status_label.color = :green
                    else
                        status_label.text = "Fehler: Bilddaten nicht verfügbar"
                        status_label.color = :red
                    end
                else
                    println("[POLYGON] Cannot close polygon for column $col_idx - need at least 3 vertices")
                    status_label.text = "Polygon braucht mindestens 3 Punkte"
                    status_label.color = :orange
                end
            end
            
            # Clear polygon button
            Bas3GLMakie.GLMakie.on(clear_poly_btn.clicks) do n
                println("[POLYGON] Clear polygon for column $col_idx")
                polygon_vertices_per_image[col_idx][] = Bas3GLMakie.GLMakie.Point2f[]
                polygon_active_per_image[col_idx][] = false
                polygon_complete_per_image[col_idx][] = false
            end
            
            # Save polygon mask button
            Bas3GLMakie.GLMakie.on(save_mask_btn.clicks) do n
                println("[POLYGON] Save mask for column $col_idx")
                
                # Call the extracted function
                local success, msg, output_path = save_polygon_mask_for_column(col_idx)
                
                if success
                    status_label.text = msg
                    status_label.color = :green
                    
                    # NEW: Update overlay with newly saved mask
                    println("[MASK-OVERLAY] Updating overlay after save for column $col_idx")
                    
                    # Reload mask from file (try .bin first, then PNG)
                    local entry = current_entries[][col_idx]
                    local display_height, display_width = size(image_observables[col_idx][])
                    local mask_resized = load_mask_for_display(entry.image_index, (display_height, display_width))
                    
                    if !isnothing(mask_resized)
                        # Update observable
                        saved_mask_overlays[col_idx][] = mask_resized
                        saved_mask_exists[col_idx] = true
                        saved_mask_visible[col_idx][] = true  # Show new mask
                        
                        println("[MASK-OVERLAY] Mask updated successfully")
                    end
                else
                    status_label.text = msg
                    status_label.color = :red
                end
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
        
        local widget_creation_time = time() - widget_creation_start
        println("[PERF-BUILD] Widget creation ($(num_images) images): $(round(widget_creation_time*1000, digits=2))ms")
        
        # ====================================================================
        # CREATE L*C*h TIMELINE PLOT (auto-load from .bin masks + manual override)
        # ====================================================================
        
        # AUTOMATIC: Compute L*C*h from saved polygon mask .bin files
        println("[COMPARE-UI] Computing L*C*h from saved masks for $(length(entries[1:num_images])) images...")
        local lch_compute_time = @elapsed begin
            lch_polygon_data = compute_lch_from_saved_masks(entries[1:num_images], cached_lookup)
        end
        println("[PERF-BUILD] LCh computation: $(round(lch_compute_time*1000, digits=2))ms")
        
        # Create timeline (handles NaN values for missing masks)
        local timeline_create_time = @elapsed begin
            delete_gridlayout_contents!(timeline_grid_lch)
            timeline_axis_lch[] = create_lch_timeline!(timeline_grid_lch, entries[1:num_images], lch_polygon_data)
        end
        println("[PERF-BUILD] Timeline creation: $(round(timeline_create_time*1000, digits=2))ms")
        
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
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 2, Bas3GLMakie.GLMakie.Fixed(400))  # Image (increased - no HSV)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 3, Bas3GLMakie.GLMakie.Fixed(35))   # Polygon controls row 1 (mask toggle)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 4, Bas3GLMakie.GLMakie.Fixed(35))   # Polygon controls row 2 (drawing + save)
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 5, Bas3GLMakie.GLMakie.Fixed(40))   # Date
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 6, Bas3GLMakie.GLMakie.Fixed(40))   # Info
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 7, Bas3GLMakie.GLMakie.Fixed(40))   # Patient-ID
        Bas3GLMakie.GLMakie.rowsize!(images_grid, 8, Bas3GLMakie.GLMakie.Fixed(40))   # Save button
        
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
                :image_labels => image_labels,
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
