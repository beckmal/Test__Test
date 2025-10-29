# Exploration script to understand white regions in images
println("=== Exploring White Regions in Images ===")
println("Sets available: ", length(sets))

# Get first image
input_img = sets[1][1]  # Input RGB image
output_img = sets[1][2]  # Segmentation output

println("\nInput image info:")
println("  Type: ", typeof(input_img))
println("  Shape: ", shape(input_img))
println("  Size: ", size(data(input_img)))

# Get RGB data
rgb_data = data(input_img)
println("\nRGB data stats:")
println("  Red channel - min: ", minimum(rgb_data[:,:,1]), ", max: ", maximum(rgb_data[:,:,1]), ", mean: ", mean(rgb_data[:,:,1]))
println("  Green channel - min: ", minimum(rgb_data[:,:,2]), ", max: ", maximum(rgb_data[:,:,2]), ", mean: ", mean(rgb_data[:,:,2]))
println("  Blue channel - min: ", minimum(rgb_data[:,:,3]), ", max: ", maximum(rgb_data[:,:,3]), ", mean: ", mean(rgb_data[:,:,3]))

# Calculate white regions (where R, G, B are all high)
# White pixels typically have all channels close to 1.0
white_threshold = 0.8  # Adjust this threshold
white_mask = (rgb_data[:,:,1] .>= white_threshold) .& 
             (rgb_data[:,:,2] .>= white_threshold) .& 
             (rgb_data[:,:,3] .>= white_threshold)

white_count = sum(white_mask)
total_pixels = size(rgb_data, 1) * size(rgb_data, 2)
white_percentage = (white_count / total_pixels) * 100

println("\nWhite region analysis (threshold >= ", white_threshold, "):")
println("  White pixels: ", white_count)
println("  Total pixels: ", total_pixels)
println("  White percentage: ", round(white_percentage, digits=2), "%")

# Try different thresholds
println("\nWhite detection with different thresholds:")
for thresh in [0.9, 0.85, 0.8, 0.75, 0.7]
    mask = (rgb_data[:,:,1] .>= thresh) .& 
           (rgb_data[:,:,2] .>= thresh) .& 
           (rgb_data[:,:,3] .>= thresh)
    count = sum(mask)
    pct = (count / total_pixels) * 100
    println("  Threshold ", thresh, ": ", count, " pixels (", round(pct, digits=2), "%)")
end

println("\n=== Exploration complete ===")
