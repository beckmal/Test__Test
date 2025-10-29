# White Region Extraction and Visualization
# This script extracts white regions from medical wound images

println("=== White Region Extraction ===")

# Configuration
WHITE_THRESHOLD = 0.8  # RGB values >= this are considered white
MIN_REGION_SIZE = 50   # Minimum pixels for a valid white region

# Function to extract white regions
function extract_white_regions(img; threshold=WHITE_THRESHOLD, min_size=MIN_REGION_SIZE)
    """
    Extract white regions from an image.
    
    Returns:
    - white_mask: Binary mask of white regions
    - stats: Dictionary with statistics
    """
    rgb_data = data(img)
    
    # Create initial white mask using RGB threshold
    white_mask = (rgb_data[:,:,1] .>= threshold) .& 
                 (rgb_data[:,:,2] .>= threshold) .& 
                 (rgb_data[:,:,3] .>= threshold)
    
    # Calculate statistics
    white_count = sum(white_mask)
    total_pixels = size(rgb_data, 1) * size(rgb_data, 2)
    white_percentage = (white_count / total_pixels) * 100
    
    stats = Dict(
        "white_pixels" => white_count,
        "total_pixels" => total_pixels,
        "white_percentage" => white_percentage,
        "threshold" => threshold
    )
    
    return white_mask, stats
end

# Function to visualize white regions
function visualize_white_regions(img, white_mask, stats, image_index=1)
    """
    Create a visualization showing:
    1. Original image
    2. White regions highlighted
    3. White mask only
    """
    # Create figure with 3 subplots
    fgr = Bas3GLMakie.GLMakie.Figure(size=(1800, 600))
    
    # Subplot 1: Original image
    ax1 = Bas3GLMakie.GLMakie.Axis(fgr[1, 1], 
                                    title="Original Image",
                                    aspect=Bas3GLMakie.GLMakie.DataAspect())
    Bas3GLMakie.GLMakie.image!(ax1, image(img))
    Bas3GLMakie.GLMakie.hidedecorations!(ax1)
    
    # Subplot 2: Original with white regions highlighted in red
    ax2 = Bas3GLMakie.GLMakie.Axis(fgr[1, 2], 
                                    title="White Regions Highlighted (Red Overlay)",
                                    aspect=Bas3GLMakie.GLMakie.DataAspect())
    Bas3GLMakie.GLMakie.image!(ax2, image(img))
    
    # Create red overlay for white regions
    rgb_data = data(img)
    h, w = size(rgb_data, 1), size(rgb_data, 2)
    red_overlay = zeros(Float32, h, w, 4)  # RGBA
    red_overlay[:,:,1] .= 1.0  # Red channel
    red_overlay[:,:,4] .= white_mask .* 0.6  # Alpha channel (60% opacity where mask is true)
    
    Bas3GLMakie.GLMakie.image!(ax2, red_overlay)
    Bas3GLMakie.GLMakie.hidedecorations!(ax2)
    
    # Subplot 3: White mask only (black and white)
    ax3 = Bas3GLMakie.GLMakie.Axis(fgr[1, 3], 
                                    title="White Mask",
                                    aspect=Bas3GLMakie.GLMakie.DataAspect())
    Bas3GLMakie.GLMakie.heatmap!(ax3, Float32.(white_mask), colormap=:grays)
    Bas3GLMakie.GLMakie.hidedecorations!(ax3)
    
    # Add statistics as title
    stats_text = string(
        "Image ", image_index, " | ",
        "White pixels: ", stats["white_pixels"], " / ", stats["total_pixels"], 
        " (", round(stats["white_percentage"], digits=2), "%) | ",
        "Threshold: ", stats["threshold"]
    )
    Bas3GLMakie.GLMakie.Label(fgr[0, :], stats_text, fontsize=16, tellwidth=false)
    
    return fgr
end

# Process first 5 images as examples
println("\nProcessing first 5 images...")
for i in 1:min(5, length(sets))
    println("\n--- Image ", i, " ---")
    
    input_img = sets[i][1]
    
    # Extract white regions
    white_mask, stats = extract_white_regions(input_img)
    
    # Print statistics
    println("  White pixels: ", stats["white_pixels"])
    println("  Total pixels: ", stats["total_pixels"])
    println("  White percentage: ", round(stats["white_percentage"], digits=2), "%")
    
    # Create visualization
    fgr = visualize_white_regions(input_img, white_mask, stats, i)
    
    # Save figure
    filename = string("white_regions_image_", i, ".png")
    Bas3GLMakie.GLMakie.save(filename, fgr)
    println("  Saved: ", filename)
    
    # Close figure to free memory
    Bas3GLMakie.GLMakie.closeall()
end

# Summary statistics across all images
println("\n=== Summary Statistics Across All Images ===")
all_percentages = Float64[]
for i in 1:length(sets)
    input_img = sets[i][1]
    white_mask, stats = extract_white_regions(input_img)
    push!(all_percentages, stats["white_percentage"])
end

println("White region percentages:")
println("  Min: ", round(minimum(all_percentages), digits=2), "%")
println("  Max: ", round(maximum(all_percentages), digits=2), "%")
println("  Mean: ", round(mean(all_percentages), digits=2), "%")
println("  Median: ", round(median(all_percentages), digits=2), "%")

println("\n=== White Region Extraction Complete ===")
