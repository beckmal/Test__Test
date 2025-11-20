# Load_Sets__InteractiveUI.jl
# Interactive visualization module - STEP 6: Add region selection

"""
    create_interactive_figure(sets, input_type, raw_output_type)

Creates an interactive visualization figure with marker detection.
"""
function create_interactive_figure(sets, input_type, raw_output_type)
    println("[INIT] Creating interactive figure with $(length(sets)) images")
    
    # Helper function to detect markers
    function detect_markers_only(img, params)
        try
            println("[DETECTION] Detecting markers: threshold=$(params[:threshold]), min_area=$(params[:min_area]), aspect_ratio=$(params[:aspect_ratio]), kernel_size=$(params[:kernel_size]), region=$(params[:region])")
            
            local markers = detect_calibration_markers(img;
                threshold=params[:threshold],
                min_area=params[:min_area],
                min_aspect_ratio=params[:aspect_ratio] * 0.8,
                max_aspect_ratio=params[:aspect_ratio] * 1.2,
                kernel_size=params[:kernel_size],
                region=params[:region])
            
            if isempty(markers)
                local region_text = isnothing(params[:region]) ? "full image" : "selected region"
                local message = "⚠️ No markers found in $region_text"
                println("[DETECTION] $message")
                return markers, false, message
            else
                local message = "✓ Detected $(length(markers)) marker(s)"
                println("[DETECTION] $message")
                return markers, true, message
            end
        catch e
            local error_msg = "❌ Error: $(typeof(e))"
            println("[ERROR] Marker detection failed: $e")
            return MarkerInfo[], false, error_msg
        end
    end
    
    # Helper function to create marker visualization overlay
    function create_marker_overlay(img, markers)
        local img_data = data(img)
        local h, w = Base.size(img_data, 1), Base.size(img_data, 2)
        local overlay = fill(Bas3ImageSegmentation.RGBA{Float32}(0.0f0, 0.0f0, 0.0f0, 0.0f0), h, w)
        
        if !isempty(markers)
            local best_marker = markers[1]
            for i in 1:h, j in 1:w
                if best_marker.mask[i, j]
                    overlay[i, j] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 0.0f0, 0.0f0, 0.7f0)
                end
            end
        end
        
        return overlay
    end
    
    # Create figure
    fig = Figure(size=(1900, 900))
    
    # CRITICAL: Register empty mousebutton handler EARLY to activate WSLg event system
    # This MUST come before any button handlers are registered
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fig).mousebutton) do event
        # Empty handler - just activates event system
    end
    
    # Add title
    Bas3GLMakie.GLMakie.Label(
        fig[1, 1:3], 
        "Interactive Image Viewer - Step 5: Statistics Panel",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    # Image display axis
    img_axis = Bas3GLMakie.GLMakie.Axis(
        fig[2, 1];
        title="Input Image with Segmentation + Markers",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(img_axis)
    
    # Create observables
    current_input = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][1])))
    current_output = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][2])))
    
    # Detect initial markers
    init_params = Dict(:threshold => 0.7, :min_area => 8000, :aspect_ratio => 5.0, :kernel_size => 3, :region => nothing)
    init_markers, init_success, init_message = detect_markers_only(sets[1][1], init_params)
    current_marker_overlay = Bas3GLMakie.GLMakie.Observable(rotr90(create_marker_overlay(sets[1][1], init_markers)))
    
    # Display images
    Bas3GLMakie.GLMakie.image!(img_axis, current_input)
    Bas3GLMakie.GLMakie.image!(img_axis, current_output; alpha=0.5)
    Bas3GLMakie.GLMakie.image!(img_axis, current_marker_overlay)
    
    # Parameter control panel
    param_grid = Bas3GLMakie.GLMakie.GridLayout(fig[2, 2])
    
    # Panel title
    Bas3GLMakie.GLMakie.Label(
        param_grid[1, 1:2],
        "Marker Detection Parameters",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    # Threshold parameter
    threshold_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[2, 1],
        placeholder="0.7",
        stored_string="0.7",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[2, 2],
        "Threshold (0.0-1.0)",
        fontsize=14,
        halign=:left
    )
    
    # Min area parameter
    min_area_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[3, 1],
        placeholder="8000",
        stored_string="8000",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[3, 2],
        "Min Area [px]",
        fontsize=14,
        halign=:left
    )
    
    # Aspect ratio parameter
    aspect_ratio_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[4, 1],
        placeholder="5.0",
        stored_string="5.0",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[4, 2],
        "Aspect Ratio",
        fontsize=14,
        halign=:left
    )
    
    # Kernel size parameter
    kernel_size_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[5, 1],
        placeholder="3",
        stored_string="3",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[5, 2],
        "Kernel Size (0-7)",
        fontsize=14,
        halign=:left
    )
    
    # Update button
    update_button = Bas3GLMakie.GLMakie.Button(
        param_grid[6, 1:2],
        label="Update Detection",
        fontsize=14
    )
    
    # Status label
    status_label = Bas3GLMakie.GLMakie.Label(
        param_grid[7, 1:2],
        init_message,
        fontsize=12,
        halign=:center,
        color=init_success ? :green : :orange
    )
    
    # Statistics panel
    stats_grid = Bas3GLMakie.GLMakie.GridLayout(fig[2, 3])
    
    Bas3GLMakie.GLMakie.Label(
        stats_grid[1, 1],
        "Marker Statistics",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    # Create observable labels for marker stats
    marker_count_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[2, 1],
        "Markers: $(length(init_markers))",
        fontsize=14,
        halign=:left
    )
    
    marker_area_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[3, 1],
        length(init_markers) > 0 ? "Area: $(sum(init_markers[1].mask)) px" : "Area: 0 px",
        fontsize=14,
        halign=:left
    )
    
    marker_centroid_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[4, 1],
        length(init_markers) > 0 ? "Centroid: ($(round(Int, init_markers[1].centroid[1])), $(round(Int, init_markers[1].centroid[2])))" : "Centroid: N/A",
        fontsize=14,
        halign=:left
    )
    
    marker_bbox_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[5, 1],
        length(init_markers) > 0 ? "Aspect Ratio: $(round(init_markers[1].aspect_ratio, digits=2))" : "Aspect Ratio: N/A",
        fontsize=14,
        halign=:left
    )
    
    marker_angle_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[6, 1],
        length(init_markers) > 0 ? "Angle: $(round(rad2deg(init_markers[1].angle), digits=1))°" : "Angle: N/A",
        fontsize=14,
        halign=:left
    )
    
    # Region selection controls
    Bas3GLMakie.GLMakie.Label(
        stats_grid[8, 1],
        "Region Selection",
        fontsize=16,
        font=:bold,
        halign=:center
    )
    
    region_toggle = Bas3GLMakie.GLMakie.Toggle(
        stats_grid[9, 1],
        active=false
    )
    
    region_status_label = Bas3GLMakie.GLMakie.Label(
        stats_grid[10, 1],
        "Toggle to enable",
        fontsize=11,
        halign=:center,
        color=:gray
    )
    
    clear_region_button = Bas3GLMakie.GLMakie.Button(
        stats_grid[11, 1],
        label="Clear Region",
        fontsize=12
    )
    
    # Region selection state
    selection_active = Bas3GLMakie.GLMakie.Observable(false)
    selection_corner1 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    selection_corner2 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    selection_complete = Bas3GLMakie.GLMakie.Observable(false)
    current_region = Bas3GLMakie.GLMakie.Observable{Union{Nothing, Tuple{Int,Int,Int,Int}}}(nothing)
    
    # Rectangle visualization (filled polygon with stroke)
    selection_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    preview_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    
    # Draw selection rectangle (cyan with semi-transparent fill)
    Bas3GLMakie.GLMakie.poly!(img_axis, selection_rect,
        color = (:cyan, 0.2),
        strokecolor = :cyan,
        strokewidth = 3,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($selection_rect)))
    
    # Draw preview rectangle while selecting
    Bas3GLMakie.GLMakie.poly!(img_axis, preview_rect,
        color = (:cyan, 0.1),
        strokecolor = (:cyan, 0.6),
        strokewidth = 2,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($preview_rect)))
    
    # Helper to make rectangle from two corners
    function make_rectangle(p1, p2)
        x_min, x_max = minmax(p1[1], p2[1])
        y_min, y_max = minmax(p1[2], p2[2])
        return Bas3GLMakie.GLMakie.Point2f[
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min)  # Close the loop
        ]
    end
    
    # Helper to convert axis coords to pixel coords
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
    
    # Region toggle callback
    Bas3GLMakie.GLMakie.on(region_toggle.active) do active
        println("[SELECTION] Region toggle: $(active ? "ON" : "OFF")")
        selection_active[] = active
        if active
            # Clear any stale selection state when activating
            selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
            selection_complete[] = false
            selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
            region_status_label.text = "Click bottom-left corner"
            region_status_label.color = :blue
        else
            region_status_label.text = "Selection disabled"
            region_status_label.color = :gray
        end
    end
    
    # Clear region button callback
    Bas3GLMakie.GLMakie.on(clear_region_button.clicks) do n
        println("[SELECTION] Clear region button clicked")
        selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_complete[] = false
        selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        current_region[] = nothing
        region_status_label.text = "Selection cleared"
        region_status_label.color = :gray
        
        # Re-detect on full image
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing
            update_to_image(current_idx)
        end
    end
    
    # Helper function to update image and re-detect markers
    function update_to_image(idx)
        println("[UPDATE] Updating to image $idx")
        
        # Get current parameters
        threshold = tryparse(Float64, threshold_textbox.stored_string[])
        min_area = tryparse(Int, min_area_textbox.stored_string[])
        aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
        kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
        
        # Use defaults if invalid
        if threshold === nothing; threshold = 0.7; end
        if min_area === nothing; min_area = 8000; end
        if aspect_ratio === nothing; aspect_ratio = 5.0; end
        if kernel_size === nothing; kernel_size = 3; end
        
        println("[PARAMETERS] threshold=$threshold, min_area=$min_area, aspect_ratio=$aspect_ratio, kernel_size=$kernel_size, region=$(current_region[])")

        
        # Update images
        current_input[] = rotr90(image(sets[idx][1]))
        current_output[] = rotr90(image(sets[idx][2]))
        
        # Re-detect markers
        params = Dict(:threshold => threshold, :min_area => min_area, :aspect_ratio => aspect_ratio, :kernel_size => kernel_size, :region => current_region[])
        markers, success, message = detect_markers_only(sets[idx][1], params)
        current_marker_overlay[] = rotr90(create_marker_overlay(sets[idx][1], markers))
        status_label.text = message
        status_label.color = success ? :green : :orange
        
        # Update statistics labels
        marker_count_label.text = "Markers: $(length(markers))"
        if length(markers) > 0
            marker_area_label.text = "Area: $(sum(markers[1].mask)) px"
            marker_centroid_label.text = "Centroid: ($(round(Int, markers[1].centroid[1])), $(round(Int, markers[1].centroid[2])))"
            marker_bbox_label.text = "Aspect Ratio: $(round(markers[1].aspect_ratio, digits=2))"
            marker_angle_label.text = "Angle: $(round(rad2deg(markers[1].angle), digits=1))°"
        else
            marker_area_label.text = "Area: 0 px"
            marker_centroid_label.text = "Centroid: N/A"
            marker_bbox_label.text = "Aspect Ratio: N/A"
            marker_angle_label.text = "Angle: N/A"
        end
    end
    
    # Update button callback
    Bas3GLMakie.GLMakie.on(update_button.clicks) do n
        println("[WIDGET] Update button clicked (count: $n)")
        
        # Parse parameters
        threshold = tryparse(Float64, threshold_textbox.stored_string[])
        min_area = tryparse(Int, min_area_textbox.stored_string[])
        aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
        kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
        
        # Validate
        if threshold === nothing || threshold < 0.0 || threshold > 1.0
            println("[ERROR] Invalid threshold: $(threshold_textbox.stored_string[])")
            status_label.text = "Invalid threshold!"
            status_label.color = :red
            return
        end
        
        if min_area === nothing || min_area <= 0
            println("[ERROR] Invalid min area: $(min_area_textbox.stored_string[])")
            status_label.text = "Invalid min area!"
            status_label.color = :red
            return
        end
        
        if aspect_ratio === nothing || aspect_ratio < 1.0
            println("[ERROR] Invalid aspect ratio: $(aspect_ratio_textbox.stored_string[])")
            status_label.text = "Invalid aspect ratio!"
            status_label.color = :red
            return
        end
        
        if kernel_size === nothing || kernel_size < 0 || kernel_size > 7
            println("[ERROR] Invalid kernel size: $(kernel_size_textbox.stored_string[])")
            status_label.text = "Invalid kernel size!"
            status_label.color = :red
            return
        end
        
        # Get current image index
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx === nothing
            current_idx = 1
        end
        
        # Re-detect with new parameters
        update_to_image(current_idx)
    end
    
    # Navigation controls
    nav_grid = Bas3GLMakie.GLMakie.GridLayout(fig[3, 1:2])
    
    prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 1],
        label="← Previous",
        fontsize=14
    )
    
    textbox = Bas3GLMakie.GLMakie.Textbox(
        nav_grid[1, 2],
        placeholder="Image number (1-$(length(sets)))",
        stored_string="1"
    )
    
    next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 3],
        label="Next →",
        fontsize=14
    )
    
    label = Bas3GLMakie.GLMakie.Label(
        nav_grid[2, 1:3],
        "Image: 1 / $(length(sets))",
        fontsize=16,
        halign=:center
    )
    
    # Button callbacks with image update and marker re-detection
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do n
        
        println("Previous button clicked! Count: $n")
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx > 1
            new_idx = current_idx - 1
            
            textbox.stored_string[] = string(new_idx)
            label.text = "Image: $new_idx / $(length(sets))"
            update_to_image(new_idx)
            println("  -> Navigated to image $new_idx")
        end
    end
    
    Bas3GLMakie.GLMakie.on(next_button.clicks) do n
        
        println("Next button clicked! Count: $n")
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx < length(sets)
            new_idx = current_idx + 1
            
            textbox.stored_string[] = string(new_idx)
            label.text = "Image: $new_idx / $(length(sets))"
            update_to_image(new_idx)
            println("  -> Navigated to image $new_idx")
        end
    end
    
    Bas3GLMakie.GLMakie.on(textbox.stored_string) do str
        
        println("Textbox changed to: $str")
        idx = tryparse(Int, str)
        if idx !== nothing && idx >= 1 && idx <= length(sets)
            
            label.text = "Image: $idx / $(length(sets))"
            update_to_image(idx)
            println("  -> Valid image index: $idx")
        else
            
            println("  -> Invalid input")
        end
    end
    
    # Mouse click handler for region selection on img_axis
    # Priority 0 allows button clicks to be processed first
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(img_axis).mousebutton, priority=0) do event
        if event.button == Bas3GLMakie.GLMakie.Mouse.left && event.action == Bas3GLMakie.GLMakie.Mouse.press
            if selection_active[]
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(img_axis.scene)
                
                # Check if click is within axis bounds
                if isnothing(mp)
                    return Bas3GLMakie.GLMakie.Consume(false)
                end
                
                if !selection_complete[]
                    if selection_corner1[] == Bas3GLMakie.GLMakie.Point2f(0, 0)
                        # First click - set bottom-left
                        selection_corner1[] = mp
                        region_status_label.text = "Click top-right corner"
                        region_status_label.color = :blue
                        
                        println("Corner 1 set: $mp")
                    else
                        # Second click - set top-right
                        selection_corner2[] = mp
                        selection_complete[] = true
                        
                        # Update rectangle visualization
                        selection_rect[] = make_rectangle(selection_corner1[], selection_corner2[])
                        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]  # Clear preview
                        
                        region_status_label.text = "Selection complete"
                        region_status_label.color = :green
                        
                        println("Corner 2 set: $mp")
                        
                        # Get current image and convert axis coordinates to pixel coordinates
                        current_idx = tryparse(Int, textbox.stored_string[])
                        if current_idx !== nothing && current_idx >= 1 && current_idx <= length(sets)
                            img = sets[current_idx][1]
                            img_height = Base.size(data(img), 1)
                            img_width = Base.size(data(img), 2)
                            
                            c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
                            c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
                            
                            # Ensure correct ordering (min to max)
                            r_min, r_max = minmax(c1_px[1], c2_px[1])
                            c_min, c_max = minmax(c1_px[2], c2_px[2])
                            
                            current_region[] = (r_min, r_max, c_min, c_max)
                            println("[SELECTION] Region bounds: ($r_min, $r_max, $c_min, $c_max)")
                            
                            # Re-detect markers with region constraint
                            update_to_image(current_idx)
                        end
                    end
                end
                # Always consume events when selection is active to prevent axis interference
                return Bas3GLMakie.GLMakie.Consume(true)
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    # Mouse move handler for preview rectangle
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(img_axis).mouseposition, priority=0) do mp_window
        if selection_active[] && !selection_complete[]
            if selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(img_axis.scene)
                
                if !isnothing(mp)
                    # Update preview rectangle
                    preview_rect[] = make_rectangle(selection_corner1[], mp)
                end
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    println("[INIT] Interactive UI creation complete")
    println("\n[STEP 6] Region selection complete!")
    println("  - Toggle ON to enable selection mode")
    println("  - Click two corners on the image to define region")
    println("  - Cyan rectangle shows selected region (with preview while selecting)")
    println("  - Markers will be detected only in selected region")
    println("  - Click 'Clear Region' to reset and detect on full image\n")
    
    return fig
end
