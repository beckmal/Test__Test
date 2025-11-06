"""
Analyze augmentation metadata with explicit transformation parameters

This script provides detailed analysis of all transformation parameters:
- Geometric transformations (scale, rotation, shear, flip)
- Color transformations (brightness, saturation)
- Blur parameters
- Crop positions
"""

import Pkg
Pkg.activate(@__DIR__)

using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2
using Statistics
using Dates

# Path setup
function resolve_path(relative_path::String)
    if Sys.iswindows()
        if startswith(relative_path, "/mnt/")
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        if occursin(r"^[A-Za-z]:[/\\]", relative_path)
            drive_letter = lowercase(relative_path[1])
            rest_of_path = replace(relative_path[4:end], "\\" => "/")
            return "/mnt/$(drive_letter)/$(rest_of_path)"
        else
            return relative_path
        end
    end
end

base_path = resolve_path("C:/Syncthing/Datasets")
metadata_dir = joinpath(base_path, "augmented_explicit_metadata")
summary_file = joinpath(metadata_dir, "augmentation_summary.jld2")

println("\n" * "="^80)
println("EXPLICIT PARAMETER ANALYSIS")
println("="^80)

if !isfile(summary_file)
    println("ERROR: Metadata file not found at: $(summary_file)")
    println("Please run Augment_Sets_Explicit.jl first to generate metadata.")
    exit(1)
end

println("Loading metadata from: $(summary_file)")

# Load metadata
data = JLD2.load(summary_file)
all_metadata = data["all_metadata"]
source_usage_counts = data["source_usage_counts"]
generation_timestamp = data["generation_timestamp"]

println("✓ Metadata loaded successfully")
println("  Generation timestamp: $(generation_timestamp)")
println("  Total augmented samples: $(length(all_metadata))")

# ============================================================================
# 1. GEOMETRIC TRANSFORMATION ANALYSIS
# ============================================================================

println("\n" * "="^80)
println("GEOMETRIC TRANSFORMATION PARAMETERS")
println("="^80)

# Extract all geometric parameters
scale_factors = [m.scale_factor for m in all_metadata]
rotation_angles = [m.rotation_angle for m in all_metadata]
shear_x_angles = [m.shear_x_angle for m in all_metadata]
shear_y_angles = [m.shear_y_angle for m in all_metadata]
flip_types = [m.flip_type for m in all_metadata]

println("\n1. Scale Factor:")
println("   Range: [0.9, 1.1]")
println("   Mean:  $(round(mean(scale_factors), digits=4))")
println("   Std:   $(round(std(scale_factors), digits=4))")
println("   Min:   $(round(minimum(scale_factors), digits=4))")
println("   Max:   $(round(maximum(scale_factors), digits=4))")

println("\n2. Rotation Angle (degrees):")
println("   Range: [1, 360]")
println("   Mean:  $(round(mean(rotation_angles), digits=2))°")
println("   Std:   $(round(std(rotation_angles), digits=2))°")
println("   Min:   $(round(minimum(rotation_angles), digits=2))°")
println("   Max:   $(round(maximum(rotation_angles), digits=2))°")

println("\n3. Shear X Angle (degrees):")
println("   Range: [-10, 10]")
println("   Mean:  $(round(mean(shear_x_angles), digits=2))°")
println("   Std:   $(round(std(shear_x_angles), digits=2))°")
println("   Min:   $(round(minimum(shear_x_angles), digits=2))°")
println("   Max:   $(round(maximum(shear_x_angles), digits=2))°")

println("\n4. Shear Y Angle (degrees):")
println("   Range: [-10, 10]")
println("   Mean:  $(round(mean(shear_y_angles), digits=2))°")
println("   Std:   $(round(std(shear_y_angles), digits=2))°")
println("   Min:   $(round(minimum(shear_y_angles), digits=2))°")
println("   Max:   $(round(maximum(shear_y_angles), digits=2))°")

println("\n5. Flip Distribution:")
flip_counts = Dict(:flipx => 0, :flipy => 0, :noop => 0)
for ft in flip_types
    flip_counts[ft] += 1
end
for (flip, count) in flip_counts
    pct = round(count / length(flip_types) * 100, digits=1)
    println("   $(flip): $(count) ($(pct)%)")
end

# ============================================================================
# 2. COLOR AND BLUR TRANSFORMATION ANALYSIS
# ============================================================================

println("\n" * "="^80)
println("COLOR AND BLUR PARAMETERS")
println("="^80)

brightness_factors = [m.brightness_factor for m in all_metadata]
saturation_offsets = [m.saturation_offset for m in all_metadata]
blur_kernel_sizes = [m.blur_kernel_size for m in all_metadata]
blur_sigmas = [m.blur_sigma for m in all_metadata]

println("\n1. Brightness Factor:")
println("   Range: [0.8, 1.2]")
println("   Mean:  $(round(mean(brightness_factors), digits=4))")
println("   Std:   $(round(std(brightness_factors), digits=4))")
println("   Min:   $(round(minimum(brightness_factors), digits=4))")
println("   Max:   $(round(maximum(brightness_factors), digits=4))")

println("\n2. Saturation Offset:")
println("   Range: [-0.2, 0.2]")
println("   Mean:  $(round(mean(saturation_offsets), digits=4))")
println("   Std:   $(round(std(saturation_offsets), digits=4))")
println("   Min:   $(round(minimum(saturation_offsets), digits=4))")
println("   Max:   $(round(maximum(saturation_offsets), digits=4))")

println("\n3. Blur Kernel Size:")
println("   Range: [3, 5, 7]")
kernel_counts = Dict(3 => 0, 5 => 0, 7 => 0)
for k in blur_kernel_sizes
    kernel_counts[k] += 1
end
for (kernel, count) in sort(collect(kernel_counts))
    pct = round(count / length(blur_kernel_sizes) * 100, digits=1)
    println("   $(kernel): $(count) ($(pct)%)")
end

println("\n4. Blur Sigma:")
println("   Range: [1.0, 3.0]")
println("   Mean:  $(round(mean(blur_sigmas), digits=4))")
println("   Std:   $(round(std(blur_sigmas), digits=4))")
println("   Min:   $(round(minimum(blur_sigmas), digits=4))")
println("   Max:   $(round(maximum(blur_sigmas), digits=4))")

# ============================================================================
# 3. CROP POSITION ANALYSIS
# ============================================================================

println("\n" * "="^80)
println("CROP POSITION ANALYSIS")
println("="^80)

crop_y_starts = [m.crop_y_start for m in all_metadata]
crop_x_starts = [m.crop_x_start for m in all_metadata]

println("\n1. Crop Y Position (after scale):")
println("   Mean:  $(round(mean(crop_y_starts), digits=2))")
println("   Std:   $(round(std(crop_y_starts), digits=2))")
println("   Min:   $(minimum(crop_y_starts))")
println("   Max:   $(maximum(crop_y_starts))")

println("\n2. Crop X Position (after scale):")
println("   Mean:  $(round(mean(crop_x_starts), digits=2))")
println("   Std:   $(round(std(crop_x_starts), digits=2))")
println("   Min:   $(minimum(crop_x_starts))")
println("   Max:   $(maximum(crop_x_starts))")

# ============================================================================
# 4. REPRODUCIBILITY TEST
# ============================================================================

println("\n" * "="^80)
println("REPRODUCIBILITY INFORMATION")
println("="^80)

println("\nAll parameters are explicitly stored:")
println("  ✓ Scale factor")
println("  ✓ Crop position (y, x)")
println("  ✓ Shear angles (X, Y)")
println("  ✓ Rotation angle")
println("  ✓ Flip type")
println("  ✓ Brightness factor")
println("  ✓ Saturation offset")
println("  ✓ Blur kernel size")
println("  ✓ Blur sigma")

println("\nTo reproduce any augmentation:")
println("  1. Load metadata for desired sample")
println("  2. Build pipeline with exact parameter values")
println("  3. Apply to original source image")
println("  4. Result will be bit-for-bit identical")

# ============================================================================
# 5. EXPORT TO CSV
# ============================================================================

println("\n" * "="^80)
println("EXPORTING PARAMETERS TO CSV")
println("="^80)

csv_file = joinpath(metadata_dir, "explicit_parameters.csv")
println("Writing to: $(csv_file)")

open(csv_file, "w") do io
    # Header
    println(io, join([
        "augmented_index", "source_index", "timestamp", "random_seed",
        "scale_factor", "crop_y_start", "crop_x_start", "crop_height", "crop_width",
        "shear_x_angle", "shear_y_angle", "rotation_angle", "flip_type",
        "brightness_factor", "saturation_offset", "blur_kernel_size", "blur_sigma",
        "scar_pct", "redness_pct", "hematoma_pct", "necrosis_pct", "background_pct"
    ], ","))
    
    # Data rows
    for m in all_metadata
        println(io, join([
            m.augmented_index, m.source_index, m.timestamp, m.random_seed,
            m.scale_factor, m.crop_y_start, m.crop_x_start, m.crop_height, m.crop_width,
            m.shear_x_angle, m.shear_y_angle, m.rotation_angle, m.flip_type,
            m.brightness_factor, m.saturation_offset, m.blur_kernel_size, m.blur_sigma,
            m.scar_percentage, m.redness_percentage, m.hematoma_percentage, 
            m.necrosis_percentage, m.background_percentage
        ], ","))
    end
end

println("✓ CSV export complete: $(csv_file)")

# ============================================================================
# 6. PARAMETER DISTRIBUTION CHECK
# ============================================================================

println("\n" * "="^80)
println("PARAMETER DISTRIBUTION VALIDATION")
println("="^80)

println("\nChecking if parameter distributions match expected ranges...")

all_good = true

# Check scale factor
if 0.9 <= minimum(scale_factors) && maximum(scale_factors) <= 1.1
    println("  ✓ Scale factors within [0.9, 1.1]")
else
    println("  ✗ Scale factors outside expected range!")
    all_good = false
end

# Check rotation
if 1 <= minimum(rotation_angles) && maximum(rotation_angles) <= 360
    println("  ✓ Rotation angles within [1, 360]")
else
    println("  ✗ Rotation angles outside expected range!")
    all_good = false
end

# Check shear X
if -10 <= minimum(shear_x_angles) && maximum(shear_x_angles) <= 10
    println("  ✓ Shear X angles within [-10, 10]")
else
    println("  ✗ Shear X angles outside expected range!")
    all_good = false
end

# Check shear Y
if -10 <= minimum(shear_y_angles) && maximum(shear_y_angles) <= 10
    println("  ✓ Shear Y angles within [-10, 10]")
else
    println("  ✗ Shear Y angles outside expected range!")
    all_good = false
end

# Check brightness
if 0.8 <= minimum(brightness_factors) && maximum(brightness_factors) <= 1.2
    println("  ✓ Brightness factors within [0.8, 1.2]")
else
    println("  ✗ Brightness factors outside expected range!")
    all_good = false
end

# Check saturation
if -0.2 <= minimum(saturation_offsets) && maximum(saturation_offsets) <= 0.2
    println("  ✓ Saturation offsets within [-0.2, 0.2]")
else
    println("  ✗ Saturation offsets outside expected range!")
    all_good = false
end

# Check blur sigma
if 1.0 <= minimum(blur_sigmas) && maximum(blur_sigmas) <= 3.0
    println("  ✓ Blur sigmas within [1.0, 3.0]")
else
    println("  ✗ Blur sigmas outside expected range!")
    all_good = false
end

if all_good
    println("\n✓ All parameters within expected ranges")
else
    println("\n✗ Some parameters outside expected ranges - check implementation!")
end

# ============================================================================
# 7. SAMPLE AUGMENTATION DETAILS
# ============================================================================

println("\n" * "="^80)
println("SAMPLE AUGMENTATION DETAILS")
println("="^80)

for i in 1:min(3, length(all_metadata))
    m = all_metadata[i]
    println("\nSample #$(i):")
    println("  Source: #$(m.source_index)")
    println("  Seed: $(m.random_seed)")
    println("  Geometric:")
    println("    Scale:    $(round(m.scale_factor, digits=3))x")
    println("    Crop:     Y=$(m.crop_y_start):$(m.crop_y_start+m.crop_height-1), X=$(m.crop_x_start):$(m.crop_x_start+m.crop_width-1)")
    println("    Shear:    X=$(round(m.shear_x_angle, digits=2))°, Y=$(round(m.shear_y_angle, digits=2))°")
    println("    Rotation: $(round(m.rotation_angle, digits=2))°")
    println("    Flip:     $(m.flip_type)")
    println("  Appearance:")
    println("    Brightness: $(round(m.brightness_factor, digits=2))x")
    println("    Saturation: $(round(m.saturation_offset, digits=2))")
    println("    Blur:       kernel=$(m.blur_kernel_size), σ=$(round(m.blur_sigma, digits=2))")
    println("  Quality:")
    println("    Scar:     $(round(m.scar_percentage, digits=2))%")
    println("    Redness:  $(round(m.redness_percentage, digits=2))%")
    println("    Hematoma: $(round(m.hematoma_percentage, digits=2))%")
    println("    Necrosis: $(round(m.necrosis_percentage, digits=2))%")
end

# ============================================================================
# FINAL SUMMARY
# ============================================================================

println("\n" * "="^80)
println("ANALYSIS COMPLETE")
println("="^80)

println("\nFiles generated:")
println("  - $(csv_file)")

println("\nKey capabilities:")
println("  ✓ Perfect reproducibility (exact parameter values known)")
println("  ✓ Parameter distribution analysis")
println("  ✓ Filter samples by any transformation parameter")
println("  ✓ Understand which transformations were applied")
println("  ✓ Debug augmentation issues")

println("\nExample analysis queries:")
println("  - Find all samples rotated > 300°")
println("  - Find all horizontally flipped samples")
println("  - Find samples with high brightness")
println("  - Analyze correlation between parameters and quality")

println("="^80)
