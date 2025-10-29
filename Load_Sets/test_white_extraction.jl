#!/usr/bin/env julia
# Standalone script to test white region extraction
# Run this after Load_Sets.jl has been loaded

println("=== White Region Extraction Test ===")

# Check if sets variable exists
if !@isdefined(sets)
    println("ERROR: 'sets' variable not found!")
    println("Please run Load_Sets.jl first:")
    println("  include(\"Load_Sets.jl\")")
    exit(1)
end

println("Found $(length(sets)) images in dataset")

# Configuration
const WHITE_THRESHOLD = 0.8

# Test extraction on first image
println("\nTesting on first image...")
test_img = sets[1][1]

println("Image type: ", typeof(test_img))
println("Image shape: ", shape(test_img))

# Get RGB data
rgb_data = data(test_img)
println("RGB data size: ", size(rgb_data))

# Extract white regions
println("\nExtracting white regions with threshold=$(WHITE_THRESHOLD)...")
white_mask = (rgb_data[:,:,1] .>= WHITE_THRESHOLD) .& 
             (rgb_data[:,:,2] .>= WHITE_THRESHOLD) .& 
             (rgb_data[:,:,3] .>= WHITE_THRESHOLD)

# Statistics
white_count = sum(white_mask)
total_pixels = size(rgb_data, 1) * size(rgb_data, 2)
white_percentage = (white_count / total_pixels) * 100

println("\nResults:")
println("  White pixels: ", white_count)
println("  Total pixels: ", total_pixels)
println("  White percentage: ", round(white_percentage, digits=2), "%")

# Test with different thresholds
println("\nTesting different thresholds:")
for thresh in [0.9, 0.85, 0.8, 0.75, 0.7]
    mask = (rgb_data[:,:,1] .>= thresh) .& 
           (rgb_data[:,:,2] .>= thresh) .& 
           (rgb_data[:,:,3] .>= thresh)
    count = sum(mask)
    pct = (count / total_pixels) * 100
    println("  Threshold $(thresh): $(count) pixels ($(round(pct, digits=2))%)")
end

println("\n=== Test Complete ===")
println("If this works, you can run the full white extraction by executing:")
println("the white extraction section in Load_Sets.jl")
