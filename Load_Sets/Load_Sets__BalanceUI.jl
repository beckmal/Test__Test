# Load_Sets__BalanceUI.jl
# Simple viewer for original images and extracted regions

"""
    create_balance_figure(sets, input_type, raw_output_type; test_mode=false)

Creates a balance viewer figure with:
- Top left: Before white balance (full original image)
- Top middle: After white balance (full original image with WB applied)
- Top right: Masked region (used to calculate WB parameters)
- Bottom left: HSV histogram for before image (masked region)
- Bottom middle: HSV histogram for after image (masked region)
- White balance is calculated from masked region and applied to full image
- Navigation controls for browsing dataset

# Arguments
- `sets`: Vector of (input_image, output_image, dataset_index) tuples
- `input_type`: Input image type
- `raw_output_type`: Raw output image type
- `test_mode::Bool=false`: If true, return (figure, observables, widgets) for testing

# Returns
- **Production mode** (`test_mode=false`): `Figure` - GLMakie Figure object
- **Test mode** (`test_mode=true`): Named tuple with:
  - `figure`: GLMakie Figure object
  - `observables`: Dict{Symbol, Observable} - Internal state observables
  - `widgets`: Dict{Symbol, Widget} - UI widget references

# Examples
```julia
include("Load_Sets__Core.jl")
include("Load_Sets__BalanceUI.jl")
sets = load_original_sets(50, false)
fig = create_balance_figure(sets, input_type, raw_output_type)
display(GLMakie.Screen(), fig)
```
"""
function create_balance_figure(sets, input_type, raw_output_type; 
                               test_mode::Bool=false)
    println("[INFO] Creating balance viewer with $(length(sets)) images (test_mode=$test_mode)")
    
    # Base path for MuHa folders - detect Windows vs WSL/Linux
    local BASE_PATH = if Sys.iswindows()
        raw"C:\Syncthing\MuHa - Bilder"
    else
        "/mnt/c/Syncthing/MuHa - Bilder"
    end
    
    # Figure: 3 rows x 4 columns
    # Row 1: Original Image | Full Image Histogram (Before) | Masked Region Histogram (Before) | Mean HSV Values (Before)
    # Row 2: Masked Region | White Balance Controls | (empty) | (empty)
    # Row 3: WB Applied Image | Full Image Histogram (After) | Masked Region Histogram (After) | Mean HSV Values (After)
    local fgr = Figure(size=(3600, 1800))  # Increased from 3200x1600 for better spacing
    
    # Add main title
    local title_label = Bas3GLMakie.GLMakie.Label(
        fgr[1, 1:5], 
        "Weißabgleich Viewer: Vorher/Nachher Vergleich",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    # Row 1: Original Image + Full Image Histogram + Full Image Median + Masked Region Histogram + Masked Region Median
    local axs_before = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 1];
        title="Original (Vollbild)",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs_before)
    
    local axs_hist_full_before = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2];
        title="HSV Histogramm (Vollbild - Vorher)",
        xlabel="Normalisiert (0-1)",
        ylabel="Dichte"
    )
    
    # Median HSV values label for full image "Before" state
    local median_hsv_full_before_label = Bas3GLMakie.GLMakie.Label(
        fgr[2, 3],
        "Median HSV:\n(Vollbild)\n\nH: ---°\nS: ---%\nV: ---%",
        fontsize=14,
        halign=:left,
        valign=:center,
        tellheight=false,
        tellwidth=false
    )
    
    local axs_hist_masked_before = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 4];
        title="HSV Histogramm (Maskierte Region - Vorher)",
        xlabel="Normalisiert (0-1)",
        ylabel="Dichte"
    )
    
    # Median HSV values label for masked region "Before" state
    local median_hsv_masked_before_label = Bas3GLMakie.GLMakie.Label(
        fgr[2, 5],
        "Median HSV:\n(Maskierte Region)\n\nH: ---°\nS: ---%\nV: ---%",
        fontsize=14,
        halign=:left,
        valign=:center,
        tellheight=false,
        tellwidth=false
    )
    
    # Row 2: Masked Region + White Balance Controls
    local axs_masked = Bas3GLMakie.GLMakie.Axis(
        fgr[3, 1];
        title="Maskierte Region (zur WB-Berechnung)",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs_masked)
    
    # White balance controls will be placed in fgr[3, 2:5]
    
    # Row 3: After White Balance Image + Full Image Histogram + Full Image Median + Masked Region Histogram + Masked Region Median
    local axs_after = Bas3GLMakie.GLMakie.Axis(
        fgr[4, 1];
        title="Mit Weißabgleich (Vollbild)",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs_after)
    
    local axs_hist_full_after = Bas3GLMakie.GLMakie.Axis(
        fgr[4, 2];
        title="HSV Histogramm (Vollbild - Nachher)",
        xlabel="Normalisiert (0-1)",
        ylabel="Dichte"
    )
    
    # Median HSV values label for full image "After" state
    local median_hsv_full_after_label = Bas3GLMakie.GLMakie.Label(
        fgr[4, 3],
        "Median HSV:\n(Vollbild)\n\nH: ---°\nS: ---%\nV: ---%",
        fontsize=14,
        halign=:left,
        valign=:center,
        tellheight=false,
        tellwidth=false
    )
    
    local axs_hist_masked_after = Bas3GLMakie.GLMakie.Axis(
        fgr[4, 4];
        title="HSV Histogramm (Maskierte Region - Nachher)",
        xlabel="Normalisiert (0-1)",
        ylabel="Dichte"
    )
    
    # Median HSV values label for masked region "After" state
    local median_hsv_masked_after_label = Bas3GLMakie.GLMakie.Label(
        fgr[4, 5],
        "Median HSV:\n(Maskierte Region)\n\nH: ---°\nS: ---%\nV: ---%",
        fontsize=14,
        halign=:left,
        valign=:center,
        tellheight=false,
        tellwidth=false
    )
    
    # Link axes for synchronized zooming and panning
    # Link original (before) and after white balance images
    Bas3GLMakie.GLMakie.linkaxes!(axs_before, axs_after)
    # Also link the masked region view
    Bas3GLMakie.GLMakie.linkaxes!(axs_before, axs_masked)
    
    # Note: Histogram axes are NOT linked - each can have independent scales
    # This allows full image histograms to show different ranges than masked region histograms
    
    # Navigation panel at bottom
    local nav_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[5, 1:5])
    
    # Navigation controls
    Bas3GLMakie.GLMakie.Label(
        nav_grid[1, 1:3],
        "Navigation",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    local prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[2, 1],
        label="◀ Zurück",
        fontsize=14
    )
    
    local nav_textbox = Bas3GLMakie.GLMakie.Textbox(
        nav_grid[2, 2],
        placeholder="1",
        stored_string="1",
        width=100
    )
    
    local next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[2, 3],
        label="Weiter ▶",
        fontsize=14
    )
    
    local textbox_label = Bas3GLMakie.GLMakie.Label(
        nav_grid[3, 1:3],
        "Bild 1 von $(length(sets))",
        fontsize=14,
        halign=:center
    )
    
    # Status label for errors/info
    local status_label = Bas3GLMakie.GLMakie.Label(
        nav_grid[4, 1:3],
        "",
        fontsize=12,
        halign=:center
    )
    
    # White balance controls (direct placement in row 2, columns 2-4)
    # Define white point options
    local WHITE_POINTS = Dict(
        "D65 (Tageslicht 6500K)" => Colors.WP_D65,
        "D50 (Horizont 5000K)" => Colors.WP_D50,
        "A (Glühlampe 2856K)" => Colors.WP_A,
        "D55 (Mittag 5500K)" => Colors.WP_D55,
        "D75 (Nord-Tageslicht 7500K)" => Colors.WP_D75,
        "E (Gleiche Energie)" => Colors.WP_E,
        "F2 (Kaltweiß Fluor.)" => Colors.WP_F2,
        "F7 (Tageslicht Fluor.)" => Colors.WP_F7,
        "F11 (Dreiband Fluor.)" => Colors.WP_F11
    )
    
    local wp_names = collect(keys(WHITE_POINTS))
    sort!(wp_names)
    
    # White balance controls in columns 2-5 (spanning across histogram and median columns)
    # AUTOMATIC MODE: Source white extracted from ruler, only target selection needed
    
    # Column 2-3: Info label explaining automatic extraction (span 2 columns)
    Bas3GLMakie.GLMakie.Label(
        fgr[3, 2:3],
        "Quell-WP:\nAutomatisch\naus Lineal\n(Median)",
        fontsize=11,
        halign=:center,
        valign=:center
    )
    
    # Column 4: Target white point label + menu
    local tgt_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[3, 4])
    Bas3GLMakie.GLMakie.Label(
        tgt_grid[1, 1],
        "Ziel-WP:",
        fontsize=12,
        halign=:left,
        valign=:center
    )
    local ref_white_menu = Bas3GLMakie.GLMakie.Menu(
        tgt_grid[1, 2],
        options=wp_names,
        default="D50 (Horizont 5000K)"
    )
    
    # Column 5: Apply button
    local apply_wb_button = Bas3GLMakie.GLMakie.Button(
        fgr[3, 5],
        label="Weißabgleich\nAnwenden",
        fontsize=12
    )
    
    # Set layout sizes
    # Row sizes
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(50))  # Title
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Auto())     # Row 1: Original + Histogram
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 3, Bas3GLMakie.GLMakie.Fixed(150)) # Row 2: Masked + Controls (fixed height for controls)
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 4, Bas3GLMakie.GLMakie.Auto())     # Row 3: After WB + Histogram
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 5, Bas3GLMakie.GLMakie.Fixed(150)) # Navigation
    
    # Column sizes - 5 columns now: Image | Histogram | Median | Histogram | Median
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Relative(0.25))  # Images column (25%)
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Relative(0.25))  # Full histogram (25%)
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 3, Bas3GLMakie.GLMakie.Relative(0.12))  # Full median values (12%)
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 4, Bas3GLMakie.GLMakie.Relative(0.25))  # Masked histogram (25%)
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 5, Bas3GLMakie.GLMakie.Relative(0.13))  # Masked median values (13%)
    
    # Observables for reactive state
    local current_index = Bas3GLMakie.GLMakie.Observable(1)
    local original_image_obs = Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100))
    local original_wb_obs = Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100))
    local masked_region_obs = Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100))
    
    # ========================================================================
    # PRELOAD CACHE - stores adjacent images for instant navigation
    # ========================================================================
    # Cache structure: idx => (original_img, masked_region, success, message)
    local preload_cache = Dict{Int, Tuple{Any, Any, Bool, String}}()
    local preload_lock = ReentrantLock()
    local preload_tasks = Dict{Int, Task}()  # Track running preload tasks
    
    # Display images
    # Before white balance (left - full original)
    Bas3GLMakie.GLMakie.image!(
        axs_before,
        original_image_obs;
        interpolate=false
    )
    
    # After white balance (middle - full original with WB)
    Bas3GLMakie.GLMakie.image!(
        axs_after,
        original_wb_obs;
        interpolate=false
    )
    
    # Masked region (right - for WB calculation)
    Bas3GLMakie.GLMakie.image!(
        axs_masked,
        masked_region_obs;
        interpolate=false
    )
    
    """
        extract_hsv_values(img)
    
    Extract H, S, V channel values from non-black pixels.
    Returns (h_values, s_values, v_values, median_h, median_s, median_v) where:
    - H (Hue) is in 0-360 degrees
    - S (Saturation) is in 0-100 percent
    - V (Value) is in 0-100 percent
    - median_h, median_s, median_v are the median values (robust to outliers)
    
    OPTIMIZED: Pre-allocates arrays and uses direct field access to avoid allocations.
    """
    function extract_hsv_values(img)
        local start_time = time()
        
        # OPTIMIZATION: Count non-black pixels first for pre-allocation
        local n_pixels = 0
        @inbounds for pixel in img
            if pixel.r > 0.0f0 || pixel.g > 0.0f0 || pixel.b > 0.0f0
                n_pixels += 1
            end
        end
        
        # OPTIMIZATION: Pre-allocate arrays with exact size (avoids reallocation)
        local h_values = Vector{Float64}(undef, n_pixels)
        local s_values = Vector{Float64}(undef, n_pixels)
        local v_values = Vector{Float64}(undef, n_pixels)
        
        # Extract non-black pixel values and convert to HSV
        local idx = 1
        @inbounds for pixel in img
            # Skip pure black pixels (masked regions)
            if pixel.r > 0.0f0 || pixel.g > 0.0f0 || pixel.b > 0.0f0
                # Convert RGB to HSV using Colors.jl
                local hsv_pixel = Colors.HSV(pixel)
                
                # Extract HSV components normalized to 0-1 range:
                # - H (Hue): 0-360° → 0-1 (divide by 360)
                # - S (Saturation): already 0-1
                # - V (Value): already 0-1
                h_values[idx] = hsv_pixel.h / 360.0  # Normalize to 0-1
                s_values[idx] = hsv_pixel.s          # Already 0-1
                v_values[idx] = hsv_pixel.v          # Already 0-1
                idx += 1
            end
        end
        
        # Compute median values (robust to outliers like dirt, glare, shadows)
        # All values are in 0-1 range
        local median_h = n_pixels > 0 ? Statistics.median(h_values) : 0.0
        local median_s = n_pixels > 0 ? Statistics.median(s_values) : 0.0
        local median_v = n_pixels > 0 ? Statistics.median(v_values) : 0.0
        
        # Convert to human-readable format for display
        local median_h_deg = median_h * 360.0  # 0-1 → 0-360°
        local median_s_pct = median_s * 100.0  # 0-1 → 0-100%
        local median_v_pct = median_v * 100.0  # 0-1 → 0-100%
        
        local elapsed = time() - start_time
        println("[HISTOGRAM] Extracted $(n_pixels) pixels → Median HSV: H=$(round(median_h_deg, digits=1))°, S=$(round(median_s_pct, digits=1))%, V=$(round(median_v_pct, digits=1))% ($(round(elapsed*1000, digits=1))ms)")
        
        # Return raw values (in 0-1 scale) plus human-readable values for labels
        return (h_values, s_values, v_values, median_h_deg, median_s_pct, median_v_pct)
    end
    
    """
        create_histogram_observables(axis, title_suffix="")
    
    Creates Observable-based histogram plots for HSV channels.
    Returns a named tuple with observables for H, S, V data.
    This approach avoids the GLMakie empty!(axis) + hist!() rendering bug.
    """
    function create_histogram_observables(axis, title_suffix="")
        println("[HISTOGRAM] Creating Observable-based histogram: $title_suffix")
        
        # Create Observables for HSV channel data
        local h_data = Bas3GLMakie.GLMakie.Observable(Float64[0.0])
        local s_data = Bas3GLMakie.GLMakie.Observable(Float64[0.0])
        local v_data = Bas3GLMakie.GLMakie.Observable(Float64[0.0])
        
        # Plot histograms using Observables
        # All channels normalized to 0-1 range for unified axis
        
        # Hue (normalized 0-1) - shown in orange
        Bas3GLMakie.GLMakie.hist!(
            axis,
            h_data;
            bins=50,
            color=(:orange, 0.5),
            normalization=:pdf,
            label="H (Farbton)"
        )
        
        # Saturation (0-1) - shown in magenta
        Bas3GLMakie.GLMakie.hist!(
            axis,
            s_data;
            bins=50,
            color=(:magenta, 0.5),
            normalization=:pdf,
            label="S (Sättigung)"
        )
        
        # Value (0-1) - shown in gray
        Bas3GLMakie.GLMakie.hist!(
            axis,
            v_data;
            bins=50,
            color=(:gray, 0.5),
            normalization=:pdf,
            label="V (Helligkeit)"
        )
        
        # Add legend
        Bas3GLMakie.GLMakie.axislegend(axis, position=:rt)
        
        # Set initial title
        axis.title[] = "HSV Histogramm $title_suffix"
        
        # Set fixed axis limits
        # X-axis: 0-1 normalized scale for all channels
        # Y-axis: density (auto)
        Bas3GLMakie.GLMakie.xlims!(axis, 0, 1)
        Bas3GLMakie.GLMakie.ylims!(axis, 0, nothing)
        
        println("[HISTOGRAM] ✓ Observable-based histogram created (x-axis fixed 0-1)")
        
        return (h_data=h_data, s_data=s_data, v_data=v_data)
    end
    
    """
        update_histogram_data!(h_obs, s_obs, v_obs, img, median_label, title_suffix="", update_median=true)
    
    Update histogram Observable data for an image using HSV color space.
    This updates the Observables which automatically trigger histogram re-rendering.
    Optionally updates the median HSV values label.
    """
    function update_histogram_data!(h_obs, s_obs, v_obs, img, median_label, title_suffix="", update_median=true)
        println("[HISTOGRAM] Updating histogram data: $title_suffix")
        
        # Extract HSV values and medians
        local h_values, s_values, v_values, median_h, median_s, median_v = extract_hsv_values(img)
        
        println("[HISTOGRAM] Updating Observable data with $(length(h_values)) values")
        
        # BUGFIX: Makie hist! crashes on empty arrays (extrema() fails)
        # If no pixels extracted, use placeholder value to avoid crash
        if isempty(h_values)
            println("[HISTOGRAM] ⚠ No pixels to histogram - using placeholder values")
            h_values = Float64[0.0]
            s_values = Float64[0.0]
            v_values = Float64[0.0]
        end
        
        # Update Observables - this automatically updates the histograms
        h_obs[] = h_values
        s_obs[] = s_values
        v_obs[] = v_values
        
        # Update median values label only if requested
        if update_median
            median_label.text[] = "Median HSV:\n(Maskierte Region)\n\nH: $(round(median_h, digits=1))°\nS: $(round(median_s, digits=1))%\nV: $(round(median_v, digits=1))%"
        end
        
        println("[HISTOGRAM] ✓ Histogram data updated successfully")
    end
    
    # Create Observable-based histograms (avoids GLMakie empty! + hist! bug)
    println("[INIT] Creating Observable-based histograms...")
    local hist_full_before = create_histogram_observables(axs_hist_full_before, "(Vollbild - Vorher)")
    local hist_masked_before = create_histogram_observables(axs_hist_masked_before, "(Maskierte Region - Vorher)")
    local hist_full_after = create_histogram_observables(axs_hist_full_after, "(Vollbild - Nachher)")
    local hist_masked_after = create_histogram_observables(axs_hist_masked_after, "(Maskierte Region - Nachher)")
    println("[INIT] ✓ All histograms created")
    
    """
        load_muha_images(dataset_idx::Int)
    
    Load original source image and ruler mask from MuHa folder.
    Extract the masked region from the original image.
    Returns (original_img, masked_region_img, success, message)
    """
    function load_muha_images(dataset_idx::Int)
        # Format dataset index as MuHa_XXX
        local muha_id = "MuHa_" * lpad(dataset_idx, 3, '0')
        local folder_path = joinpath(BASE_PATH, muha_id)
        
        println("[LOAD] Loading images for $muha_id from $folder_path")
        flush(stdout)
        
        # Check if folder exists
        println("[DEBUG] Checking if folder exists: $folder_path")
        println("[DEBUG] isdir result: $(isdir(folder_path))")
        flush(stdout)
        if !isdir(folder_path)
            println("[ERROR] Folder not found!")
            flush(stdout)
            local placeholder = zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100)
            return (
                placeholder,
                placeholder,
                false,
                "Ordner nicht gefunden: $muha_id"
            )
        end
        println("[DEBUG] Folder exists, proceeding...")
        flush(stdout)
        
        # Load original source image (MuHa_XXX_raw_adj.png) and ruler mask
        local original_path = joinpath(folder_path, muha_id * "_raw_adj.png")
        local extracted_path = joinpath(folder_path, muha_id * "_ruler_mask.png")
        
        println("[LOAD] Original: $original_path")
        println("[LOAD] Ruler mask: $extracted_path")
        flush(stdout)
        
        local original_img = nothing
        local extracted_img = nothing
        local messages = String[]
        
        # Try to load original
        if isfile(original_path)
            try
                # Use PNG library directly since FileIO may not be in scope
                original_img = Bas3ImageSegmentation.Bas3.FileIO.load(original_path)
                println("[LOAD] ✓ Original loaded: $(typeof(original_img)) size=$(size(original_img))")
                flush(stdout)
            catch e
                push!(messages, "Fehler beim Laden: $(basename(original_path))")
                println("[ERROR] Failed to load original: $e")
                flush(stdout)
            end
        else
            push!(messages, "Nicht gefunden: _raw_adj.png")
            println("[WARN] Original not found: $original_path")
            flush(stdout)
        end
        
        # Try to load ruler mask
        if isfile(extracted_path)
            try
                extracted_img = Bas3ImageSegmentation.Bas3.FileIO.load(extracted_path)
                println("[LOAD] ✓ Ruler mask loaded: $(typeof(extracted_img)) size=$(size(extracted_img))")
                flush(stdout)
            catch e
                push!(messages, "Fehler beim Laden: $(basename(extracted_path))")
                println("[ERROR] Failed to load ruler mask: $e")
                flush(stdout)
            end
        else
            push!(messages, "Nicht gefunden: _ruler_mask.png")
            println("[WARN] Ruler mask not found: $extracted_path")
            flush(stdout)
        end
        
        # Provide placeholder if loading failed
        if isnothing(original_img)
            original_img = zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100)
        end
        
        if isnothing(extracted_img)
            extracted_img = zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100)
            extracted_region = extracted_img
        else
            # Extract the masked region from the original image
            # Create a binary mask (white pixels in the mask)
            println("[EXTRACT] Extracting masked region from original image")
            flush(stdout)
            
            local extracted_region = similar(original_img)
            local mask_height, mask_width = size(extracted_img)
            local orig_height, orig_width = size(original_img)
            
            # Ensure dimensions match
            if mask_height != orig_height || mask_width != orig_width
                println("[WARN] Size mismatch: mask=$(mask_height)x$(mask_width), original=$(orig_height)x$(orig_width)")
                flush(stdout)
                extracted_region = zeros(Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}, 100, 100)
            else
                # Apply mask: keep pixels where mask is white (R+G+B > 1.5), otherwise black
                for i in 1:mask_height
                    for j in 1:mask_width
                        local mask_pixel = extracted_img[i, j]
                        local intensity = Float64(mask_pixel.r) + Float64(mask_pixel.g) + Float64(mask_pixel.b)
                        
                        if intensity > 1.5  # White pixel in mask
                            extracted_region[i, j] = original_img[i, j]
                        else
                            extracted_region[i, j] = Bas3GLMakie.GLMakie.RGB{Bas3GLMakie.GLMakie.N0f8}(0, 0, 0)  # Black
                        end
                    end
                end
                println("[EXTRACT] ✓ Region extracted")
                flush(stdout)
            end
        end
        
        local success = isempty(messages)
        local message = success ? "✓ Bilder geladen: $muha_id" : join(messages, " | ")
        
        return (original_img, extracted_region, success, message)
    end
    
    # ========================================================================
    # PRELOAD FUNCTIONS - background loading for adjacent images
    # ========================================================================
    
    """
        preload_image(idx::Int)
    
    Preload image at index idx into cache. Called in background task.
    """
    function preload_image(idx::Int)
        try
            # Bounds check
            if idx < 1 || idx > length(sets)
                @warn "[PRELOAD] Index $idx out of bounds (1-$(length(sets)))"
                return (success = false, error = "Index out of bounds")
            end
            
            # Skip if already cached (use flag to avoid return in lock)
            local should_skip = false
            lock(preload_lock) do
                if haskey(preload_cache, idx)
                    println("[PRELOAD] Index $idx already cached, skipping")
                    should_skip = true
                end
            end
            
            if should_skip
                return (success = true, error = nothing)
            end
            
            # Get dataset index
            local dataset_idx = sets[idx][3]
            println("[PRELOAD] Starting preload for index $idx (dataset $dataset_idx)...")
            
            # Load images (this is the slow part - disk I/O)
            local original_img, masked_region, success, message = nothing, nothing, false, ""
            try
                original_img, masked_region, success, message = load_muha_images(dataset_idx)
            catch e
                @warn "[PRELOAD] Error loading images for index $idx: $e"
                success = false
                message = "Load error: $(typeof(e))"
            end
            
            # Store in cache (even if load failed, cache the failure)
            lock(preload_lock) do
                preload_cache[idx] = (original_img, masked_region, success, message)
                println("[PRELOAD] ✓ Cached index $idx (success=$success, cache size: $(length(preload_cache)))")
            end
            
            return (success = success, error = success ? nothing : message)
            
        catch e
            @warn "[PRELOAD] Fatal error preloading index $idx: $e"
            return (success = false, error = "Fatal preload error: $(typeof(e))")
        end
    end
    
    """
        trigger_preload(idx::Int)
    
    Spawn background task to preload image at idx.
    Non-blocking, safe to call multiple times.
    """
    function trigger_preload(idx::Int)
        try
            # Bounds check
            if idx < 1 || idx > length(sets)
                @warn "[PRELOAD] Trigger called with invalid index $idx (bounds: 1-$(length(sets)))"
                return
            end
            
            # Skip if already cached or loading (must use explicit flag since return in lock() do doesn't exit function)
            local should_skip = lock(preload_lock) do
                if haskey(preload_cache, idx)
                    println("[PRELOAD] Index $idx already cached, skipping")
                    return true
                end
                if haskey(preload_tasks, idx) && !istaskdone(preload_tasks[idx])
                    println("[PRELOAD] Index $idx already loading, skipping")
                    return true
                end
                return false
            end
            
            if should_skip
                return
            end
            
            # Spawn background task using @async (cooperative multitasking)
            println("[PRELOAD] Spawning async preload task for index $idx...")
            local task = @async begin
                try
                    yield()  # Give other tasks a chance first
                    local result = preload_image(idx)
                    if !result.success
                        @warn "[PRELOAD] Async preload failed for index $idx: $(result.error)"
                    end
                catch e
                    @warn "[PRELOAD] Async task error for index $idx: $e"
                finally
                    # Clean up task tracking
                    lock(preload_lock) do
                        delete!(preload_tasks, idx)
                    end
                end
            end
            
            lock(preload_lock) do
                preload_tasks[idx] = task
            end
            yield()  # Let the async task start
            
        catch e
            @warn "[PRELOAD] Error in trigger_preload for index $idx: $e"
        end
    end
    
    """
        get_from_cache_or_load(idx::Int)
    
    Get image data from cache if available, otherwise load synchronously.
    If a preload task is in progress for this index, wait for it briefly.
    Returns (original_img, masked_region, success, message).
    """
    function get_from_cache_or_load(idx::Int)
        try
            # Check if there's a preload task in progress for this index
            local task_to_wait = nothing
            lock(preload_lock) do
                if haskey(preload_tasks, idx) && !istaskdone(preload_tasks[idx])
                    task_to_wait = preload_tasks[idx]
                end
            end
            
            # If preload is in progress, wait for it (up to 3 seconds)
            if !isnothing(task_to_wait)
                println("[CACHE] Preload in progress for index $idx, waiting...")
                local start_wait = time()
                local max_wait = 3.0  # seconds
                while !istaskdone(task_to_wait) && (time() - start_wait) < max_wait
                    yield()
                    sleep(0.05)
                end
                local waited_ms = (time() - start_wait) * 1000
                if istaskdone(task_to_wait)
                    println("[CACHE] Preload completed after $(round(waited_ms, digits=0))ms wait")
                else
                    println("[CACHE] Preload still running after $(round(waited_ms, digits=0))ms, proceeding without it")
                end
            end
            
            # Try to get from cache
            local cached = nothing
            lock(preload_lock) do
                if haskey(preload_cache, idx)
                    cached = pop!(preload_cache, idx)
                    println("[CACHE] ✓ Hit for index $idx (remaining cache: $(length(preload_cache)))")
                end
            end
            
            if !isnothing(cached)
                return cached
            end
            
            # Cache miss - load synchronously
            println("[CACHE] Miss for index $idx, loading synchronously...")
            local dataset_idx = sets[idx][3]
            
            # Load with error handling
            local original_img, masked_region, success, message = nothing, nothing, false, ""
            try
                original_img, masked_region, success, message = load_muha_images(dataset_idx)
            catch e
                @warn "[CACHE] Error loading image for index $idx: $e"
                success = false
                message = "Load error: $(typeof(e))"
            end
            
            return (original_img, masked_region, success, message)
            
        catch e
            @warn "[CACHE] Fatal error in get_from_cache_or_load for index $idx: $e"
            # Return error tuple
            return (nothing, nothing, false, "Cache error: $(typeof(e))")
        end
    end
    
    """
        cleanup_cache(current_idx::Int)
    
    Remove cache entries that are no longer adjacent to current index.
    Keeps memory usage bounded.
    """
    function cleanup_cache(current_idx::Int)
        lock(preload_lock) do
            local to_remove = Int[]
            for cached_idx in keys(preload_cache)
                if abs(cached_idx - current_idx) > 1
                    push!(to_remove, cached_idx)
                end
            end
            for idx in to_remove
                delete!(preload_cache, idx)
                println("[CACHE] Evicted index $idx (too far from current $current_idx)")
            end
        end
    end
    
    """
        update_display(idx::Int)
    
    Update display to show images and histograms for the given index.
    Uses preload cache if available, triggers preload for adjacent images.
    """
    function update_display(idx::Int)
        try
            println("[UPDATE] ========================================")
            println("[UPDATE] Updating display for index $idx")
            
            # Bounds check
            if idx < 1 || idx > length(sets)
                println("[ERROR] Invalid image index: $idx (valid range: 1-$(length(sets)))")
                status_label.text[] = "Ungültiger Index: $idx (gültig: 1-$(length(sets)))"
                return
            end
        
        # Get dataset index from tuple
        local dataset_idx = sets[idx][3]
        println("[UPDATE] UI index: $idx -> Dataset index: $dataset_idx")
        
        # Load images (from cache or disk)
        println("[UPDATE] Loading images for dataset $dataset_idx...")
        local original_img, masked_region, success, message = get_from_cache_or_load(idx)
        
        println("[UPDATE] Load result: success=$success, message='$message'")
        println("[UPDATE] Original image size: $(size(original_img))")
        println("[UPDATE] Masked region size: $(size(masked_region))")
        
        # Update observables
        println("[UPDATE] Updating observables...")
        original_image_obs[] = original_img
        original_wb_obs[] = original_img  # Initialize as original (no WB yet)
        masked_region_obs[] = masked_region
        
        # Update histograms - OPTIMIZATION: Only compute "before" histograms on navigation
        # "After" histograms are identical until white balance is applied, so we copy the data
        println("[UPDATE] Updating histograms (optimized: compute before, copy to after)...")
        
        # Compute "before" histograms (the actual work)
        update_histogram_data!(hist_full_before.h_data, hist_full_before.s_data, hist_full_before.v_data, 
                               original_img, median_hsv_full_before_label, "(Vollbild - Vorher)", true)
        update_histogram_data!(hist_masked_before.h_data, hist_masked_before.s_data, hist_masked_before.v_data, 
                               masked_region, median_hsv_masked_before_label, "(Maskierte Region - Vorher)", true)
        
        # Copy "before" data to "after" (no WB applied yet, so they're identical)
        # This avoids redundant HSV extraction for 24M+ pixels
        hist_full_after.h_data[] = hist_full_before.h_data[]
        hist_full_after.s_data[] = hist_full_before.s_data[]
        hist_full_after.v_data[] = hist_full_before.v_data[]
        hist_masked_after.h_data[] = hist_masked_before.h_data[]
        hist_masked_after.s_data[] = hist_masked_before.s_data[]
        hist_masked_after.v_data[] = hist_masked_before.v_data[]
        
        # Copy median labels too
        median_hsv_full_after_label.text[] = median_hsv_full_before_label.text[]
        median_hsv_masked_after_label.text[] = median_hsv_masked_before_label.text[]
        
        # Update axis titles
        local muha_id = "MuHa_" * lpad(dataset_idx, 3, '0')
        println("[UPDATE] Updating axis titles for $muha_id")
        axs_before.title[] = "Original ($muha_id)"
        axs_after.title[] = "Mit Weißabgleich ($muha_id)"
        axs_masked.title[] = "Maskierte Region ($muha_id)"
        
        # Update labels
        textbox_label.text[] = "Bild $idx von $(length(sets)) (Dataset: $muha_id)"
        status_label.text[] = message
        
        # Update current index
        current_index[] = idx
        if nav_textbox.stored_string[] != string(idx)
            nav_textbox.stored_string[] = string(idx)
        end
        
        # Reset white balance status
        status_label.text[] = ""
        
            println("[UPDATE] ✓ Display updated successfully for $muha_id")
            
            # Trigger preload for adjacent images (non-blocking)
            println("[UPDATE] Triggering preload for adjacent images...")
            try
                cleanup_cache(idx)
                trigger_preload(idx - 1)
                trigger_preload(idx + 1)
            catch e
                @warn "[UPDATE] Error triggering preload: $e"
                # Non-fatal - continue
            end
            
            println("[UPDATE] ========================================")
            
        catch e
            @warn "[UPDATE] Error updating display for index $idx: $e"
            status_label.text[] = "Fehler beim Anzeigen von Bild $idx: $(typeof(e))"
            
            # Try to show error state
            try
                textbox_label.text[] = "Fehler bei Bild $idx"
                axs_before.title[] = "Fehler"
                axs_after.title[] = "Fehler"
                axs_masked.title[] = "Fehler"
            catch
                # Even error display failed - nothing we can do
            end
        end
    end
    
    # Navigation button handlers
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do _
        println("[NAVIGATION] Previous button clicked")
        local current_idx = current_index[]
        local new_idx = max(1, current_idx - 1)
        
        if new_idx != current_idx
            println("[NAVIGATION] Going to previous image: $current_idx -> $new_idx")
            update_display(new_idx)
        else
            println("[NAVIGATION] Already at first image ($current_idx)")
        end
    end
    
    Bas3GLMakie.GLMakie.on(next_button.clicks) do _
        println("[NAVIGATION] Next button clicked")
        local current_idx = current_index[]
        local new_idx = min(length(sets), current_idx + 1)
        
        if new_idx != current_idx
            println("[NAVIGATION] Going to next image: $current_idx -> $new_idx")
            update_display(new_idx)
        else
            println("[NAVIGATION] Already at last image ($current_idx)")
        end
    end
    
    # Textbox handler
    Bas3GLMakie.GLMakie.on(nav_textbox.stored_string) do s
        println("[NAVIGATION] Textbox changed to: '$s'")
        local idx = tryparse(Int, s)
        
        if !isnothing(idx) && idx != current_index[]
            println("[NAVIGATION] Parsed index: $idx (current: $(current_index[]))")
            update_display(idx)
        elseif isnothing(idx)
            println("[ERROR] Invalid textbox input: '$s' (not a valid integer)")
            status_label.text[] = "Ungültige Eingabe: '$s'"
        else
            println("[NAVIGATION] Textbox shows current index: $idx (no change)")
        end
    end
    
    # White balance button handler - AUTOMATIC WHITE EXTRACTION
    Bas3GLMakie.GLMakie.on(apply_wb_button.clicks) do _
        println("[WB] ========================================")
        println("[WB] AUTOMATIC WHITE BALANCE FROM RULER")
        println("[WB] ========================================")
        flush(stdout)
        
        # Get the masked region and full original image
        local original_full = original_image_obs[]
        local masked_region = masked_region_obs[]
        
        println("[WB] Image dimensions:")
        println("[WB]   Full image:    $(size(original_full))")
        println("[WB]   Masked region: $(size(masked_region))")
        flush(stdout)
        
        try
            status_label.text[] = "Extrahiere Weißpunkt aus Lineal (Median)..."
            
            # =====================================================================
            # STEP 1: EXTRACT WHITE POINT FROM MASKED RULER REGION
            # =====================================================================
            # This implements Step 1: "Extract the white from the ruler"
            # Computes median(R), median(G), median(B) in LINEAR space
            println("[WB] ")
            println("[WB] STEP 1: Extract white from ruler")
            println("[WB] ---------------------------------------")
            local start_time = time()
            
            local src_white = extract_white_point_from_masked_region(masked_region)
            
            local extract_time = time() - start_time
            println("[WB] ✓ Extraction complete in $(round(extract_time, digits=3))s")
            println("[WB] ")
            flush(stdout)
            
            # =====================================================================
            # STEP 2: DECIDE TARGET WHITE POINT
            # =====================================================================
            # This implements Step 2: "Decide your target white"
            println("[WB] STEP 2: Target white point")
            println("[WB] ---------------------------------------")
            local ref_name = ref_white_menu.selection[]
            local ref_white = WHITE_POINTS[ref_name]
            
            println("[WB] Target: $ref_name")
            println("[WB] XYZ = ($(round(ref_white.x, digits=4)), $(round(ref_white.y, digits=4)), $(round(ref_white.z, digits=4)))")
            println("[WB] ")
            flush(stdout)
            
            # =====================================================================
            # STEP 3-7: APPLY BRADFORD CHROMATIC ADAPTATION
            # =====================================================================
            # This implements Steps 3-7:
            # - Step 3: Convert measured white RGB→XYZ (done in extract function)
            # - Step 4: Convert both whites to Bradford cone space (LMS)
            # - Step 5: Form adaptation diagonal matrix D
            # - Step 6: Construct full Bradford matrix MBA = MB^-1 · D · MB
            # - Step 7: Apply to whole image
            # All handled by whitebalance_bradford() function!
            
            status_label.text[] = "Wende Bradford-Transformation an (Schritte 4-7)..."
            
            println("[WB] STEP 3-7: Bradford chromatic adaptation")
            println("[WB] ---------------------------------------")
            println("[WB] Applying to full image...")
            start_time = time()
            
            local wb_full_image = apply_whitebalance_with_clamping(original_full, src_white, ref_white)
            
            local full_elapsed = time() - start_time
            println("[WB] ✓ Full image processed in $(round(full_elapsed, digits=2))s")
            
            println("[WB] Applying to masked region for histogram comparison...")
            start_time = time()
            
            local wb_masked_region = apply_whitebalance_with_clamping(masked_region, src_white, ref_white)
            
            local masked_elapsed = time() - start_time
            println("[WB] ✓ Masked region processed in $(round(masked_elapsed, digits=2))s")
            println("[WB] ")
            flush(stdout)
            
            # =====================================================================
            # UPDATE DISPLAYS AND HISTOGRAMS
            # =====================================================================
            println("[WB] Updating displays...")
            original_wb_obs[] = wb_full_image
            
            # Update all histograms
            update_histogram_data!(hist_full_before.h_data, hist_full_before.s_data, hist_full_before.v_data, 
                                   original_full, median_hsv_full_before_label, "(Vollbild - Vorher)", true)
            update_histogram_data!(hist_masked_before.h_data, hist_masked_before.s_data, hist_masked_before.v_data, 
                                   masked_region, median_hsv_masked_before_label, "(Maskierte Region - Vorher)", true)
            update_histogram_data!(hist_full_after.h_data, hist_full_after.s_data, hist_full_after.v_data, 
                                   wb_full_image, median_hsv_full_after_label, "(Vollbild - Nachher)", true)
            update_histogram_data!(hist_masked_after.h_data, hist_masked_after.s_data, hist_masked_after.v_data, 
                                   wb_masked_region, median_hsv_masked_after_label, "(Maskierte Region - Nachher)", true)
            
            # Show detailed status with extracted white point
            local src_xyz_str = "XYZ($(round(src_white.x, digits=3)), $(round(src_white.y, digits=3)), $(round(src_white.z, digits=3)))"
            status_label.text[] = "✓ WB: Lineal $src_xyz_str → $ref_name (Median)"
            
            println("[WB] ✓✓✓ WHITE BALANCE COMPLETE ✓✓✓")
            println("[WB] Source (from ruler): $src_xyz_str")
            println("[WB] Target: $ref_name")
            println("[WB] Total time: $(round(extract_time + full_elapsed + masked_elapsed, digits=2))s")
            println("[WB] ========================================")
            flush(stdout)
            
        catch e
            local error_msg = "❌ Fehler: $e"
            status_label.text[] = error_msg
            println("[WB] ❌❌❌ ERROR ❌❌❌")
            println("[WB] Error: $e")
            println("[WB] Stacktrace:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
            println("[WB] ========================================")
            flush(stdout)
        end
    end
    
    # Initialize with first image
    println("[INIT] Initializing Balance UI with first image...")
    update_display(1)
    println("[INIT] ✓ Balance UI initialization complete")
    
    # Return based on test_mode
    if test_mode
        local observables = Dict{Symbol, Any}(
            :current_index => current_index,
            :original_image => original_image_obs,
            :original_wb => original_wb_obs,
            :masked_region => masked_region_obs
        )
        
        local widgets = Dict{Symbol, Any}(
            :nav_textbox => nav_textbox,
            :prev_button => prev_button,
            :next_button => next_button,
            :textbox_label => textbox_label,
            :status_label => status_label,
            :ref_white_menu => ref_white_menu,
            :apply_wb_button => apply_wb_button
        )
        
        return (figure=fgr, observables=observables, widgets=widgets)
    else
        return fgr
    end
end
