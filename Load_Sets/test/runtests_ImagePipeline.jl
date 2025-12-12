#!/usr/bin/env julia
# runtests_ImagePipeline.jl
# Unit tests for shared image loading pipeline

using Test

# Setup environment
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# Load required modules
include("../Load_Sets__Initialization.jl")
include("../Load_Sets__Config.jl")
include("../Load_Sets__DataLoading.jl")
include("../Load_Sets__DataLoading__ImagePipeline.jl")

using Bas3ImageSegmentation
using Bas3ImageSegmentation: decompose_image_to_values
using Bas3ImageSegmentation.Images: imresize

println("\n" * "="^80)
println("Image Pipeline Unit Tests")
println("="^80)

# Test configuration
const TEST_SOURCE_DIR = resolve_path("C:/Syncthing/MuHa - Bilder")
const TEST_OUTPUT_DIR = resolve_path("C:/Syncthing/Datasets/test_pipeline_output")
const TEST_INDEX = 1  # Use image 1 for testing

# Create test output directory
mkpath(TEST_OUTPUT_DIR)

# ============================================================================
# Test Suite 1: img_loader Function
# ============================================================================

@testset "img_loader" begin
    println("\nTest 1: img_loader function")
    
    @testset "Load input image (raw_adj)" begin
        img = img_loader(TEST_SOURCE_DIR, TEST_INDEX; idtype="raw_adj", filetype="png")
        @test !isnothing(img)
        @test size(img) == (3024, 4032)  # Full resolution portrait
        println("  ✓ Input image loaded: $(size(img))")
    end
    
    @testset "Load polygon mask (if exists)" begin
        # Check if polygon mask exists for test index
        patient_num = lpad(TEST_INDEX, 3, '0')
        mask_path = joinpath(TEST_SOURCE_DIR, "MuHa_$(patient_num)", "MuHa_$(patient_num)_polygon_mask.png")
        
        if isfile(mask_path)
            img = img_loader(TEST_SOURCE_DIR, TEST_INDEX; idtype="polygon_mask", filetype="png")
            @test !isnothing(img)
            println("  ✓ Polygon mask loaded: $(size(img))")
        else
            println("  ⊘ Polygon mask not available for index $TEST_INDEX (skipping)")
        end
    end
    
    @testset "Load segmentation mask" begin
        img = img_loader(TEST_SOURCE_DIR, TEST_INDEX; idtype="seg_scar", filetype="png")
        @test !isnothing(img)
        @test size(img) == (3024, 4032)  # Full resolution portrait
        println("  ✓ Segmentation mask loaded: $(size(img))")
    end
end

# ============================================================================
# Test Suite 2: load_and_process_image Function
# ============================================================================

@testset "load_and_process_image" begin
    println("\nTest 2: load_and_process_image function")
    
    @testset "Process without saving" begin
        img_data = load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1//4,
            output_type=input_type
        )
        
        @test !isnothing(img_data)
        @test typeof(img_data) <: v__Image_Data_Static_Channel
        
        # Check dimensions (portrait: 756 height × 1008 width after 1/4 resize)
        d = data(img_data)
        @test size(d, 1) == 756   # Height
        @test size(d, 2) == 1008  # Width
        @test size(d, 3) == 3     # RGB channels
        
        println("  ✓ Image processed without save: $(size(d))")
    end
    
    @testset "Process with saving" begin
        output_path = joinpath(TEST_OUTPUT_DIR, "test_1_input.bin")
        
        # Remove if exists
        isfile(output_path) && rm(output_path)
        
        img_data, dims, elem_type = load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1//4,
            output_type=input_type,
            save_path=output_path
        )
        
        @test !isnothing(img_data)
        @test isfile(output_path)
        @test dims == (756, 1008, 3)
        @test elem_type == UInt8
        
        # Verify file size
        expected_size = 756 * 1008 * 3  # 2,286,144 bytes
        actual_size = filesize(output_path)
        @test actual_size == expected_size
        
        println("  ✓ Image saved to .bin: $output_path")
        println("    Size: $(actual_size) bytes (expected: $(expected_size))")
    end
    
    @testset "Different resize ratios" begin
        # Quarter resolution
        img_quarter = load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1//4
        )
        d_quarter = data(img_quarter)
        @test size(d_quarter) == (756, 1008, 3)
        println("  ✓ Quarter-res (1//4): $(size(d_quarter))")
        
        # Half resolution
        img_half = load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1//2
        )
        d_half = data(img_half)
        @test size(d_half) == (1512, 2016, 3)
        println("  ✓ Half-res (1//2): $(size(d_half))")
        
        # No resize
        img_full = load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1
        )
        d_full = data(img_full)
        @test size(d_full) == (3024, 4032, 3)
        println("  ✓ Full-res (1): $(size(d_full))")
    end
end

# ============================================================================
# Test Suite 3: Backward Compatibility (Byte-for-Byte Equivalence)
# ============================================================================

@testset "Backward Compatibility" begin
    println("\nTest 3: Backward compatibility with original pipeline")
    
    @testset "Compare with existing input.bin" begin
        # Generate test file with new pipeline
        test_output_path = joinpath(TEST_OUTPUT_DIR, "test_backward_compat.bin")
        isfile(test_output_path) && rm(test_output_path)
        
        load_and_process_image(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype="raw_adj",
            resize_ratio=1//4,
            output_type=input_type,
            save_path=test_output_path
        )
        
        # Compare with original file (if exists)
        original_path = joinpath(base_path, "original_quarter_res", "$(TEST_INDEX)_input.bin")
        
        if isfile(original_path)
            test_bytes = read(test_output_path)
            original_bytes = read(original_path)
            
            @test test_bytes == original_bytes
            println("  ✓ BYTE-IDENTICAL to original pipeline!")
            println("    Original: $original_path")
            println("    Test: $test_output_path")
        else
            println("  ⊘ Original file not found (skipping comparison): $original_path")
        end
    end
end

# ============================================================================
# Test Suite 4: batch_process_images Function
# ============================================================================

@testset "batch_process_images" begin
    println("\nTest 4: batch_process_images function")
    
    @testset "Batch process small set" begin
        # Process just 3 images for testing
        test_indices = [1, 2, 3]
        
        result = batch_process_images(
            TEST_SOURCE_DIR,
            TEST_OUTPUT_DIR,
            test_indices;
            idtype="raw_adj",
            filename_template="\$(index)_input_batch_test.bin",
            resize_ratio=1//4,
            output_type=input_type,
            skip_existing=false,  # Force regenerate for test
            progress_interval=1
        )
        
        @test result.generated == 3
        @test result.errors == 0
        @test result.total_time > 0
        
        # Verify all files exist
        for idx in test_indices
            file_path = joinpath(TEST_OUTPUT_DIR, "$(idx)_input_batch_test.bin")
            @test isfile(file_path)
        end
        
        println("  ✓ Batch processed 3 images successfully")
    end
    
    @testset "Skip existing files" begin
        test_indices = [1, 2, 3]
        
        # Run again with skip_existing=true
        result = batch_process_images(
            TEST_SOURCE_DIR,
            TEST_OUTPUT_DIR,
            test_indices;
            idtype="raw_adj",
            filename_template="\$(index)_input_batch_test.bin",
            skip_existing=true,
            progress_interval=1
        )
        
        @test result.skipped == 3
        @test result.generated == 0
        
        println("  ✓ Correctly skipped existing files")
    end
end

# ============================================================================
# Test Suite 5: Error Handling
# ============================================================================

@testset "Error Handling" begin
    println("\nTest 5: Error handling")
    
    @testset "Invalid index" begin
        # Index 999 should not exist
        try
            img = img_loader(TEST_SOURCE_DIR, 999; idtype="raw_adj", filetype="png")
            @test false  # Should have thrown error
        catch e
            @test true  # Expected to fail
            println("  ✓ Correctly handles invalid index")
        end
    end
    
    @testset "Invalid idtype" begin
        # Non-existent file type
        try
            img = img_loader(TEST_SOURCE_DIR, TEST_INDEX; idtype="nonexistent", filetype="png")
            @test false  # Should have thrown error
        catch e
            @test true  # Expected to fail
            println("  ✓ Correctly handles invalid idtype")
        end
    end
end

# ============================================================================
# Cleanup
# ============================================================================

println("\n" * "="^80)
println("Cleanup")
println("="^80)

# Option: Remove test output directory
# Uncomment if you want to clean up after tests
# rm(TEST_OUTPUT_DIR; recursive=true, force=true)
# println("✓ Test output directory removed")

println("\nTest output directory preserved: $TEST_OUTPUT_DIR")
println("You can inspect the generated .bin files or remove manually")

println("\n" * "="^80)
println("All Tests Complete!")
println("="^80)
