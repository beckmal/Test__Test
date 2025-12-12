#!/usr/bin/env julia
# test_load_images.jl
# Unit tests for unified load_images() function (v2.0.0)

using Test

# Setup environment
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Bas3ImageSegmentation

println("\n" * "="^80)
println("load_images() Unit Tests (v2.0.0)")
println("="^80)

# Test configuration
const TEST_SOURCE_DIR = "C:/Syncthing/MuHa - Bilder"
const TEST_INDEX = 1

# ============================================================================
# Test Suite 1: Pair Mode (Input + Output)
# ============================================================================

@testset "load_images - Pair Mode" begin
    println("\nTest 1: Pair mode (input + output)")
    
    @testset "Load with explicit types" begin
        input_type_test = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:red, :green, :blue)})
        output_type_test = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
        
        input, output = load_images(
            TEST_SOURCE_DIR, TEST_INDEX;
            input_type = input_type_test,
            output_type = output_type_test,
            output_collection = true,
            resize_ratio = 1//4
        )
        
        @test !isnothing(input)
        @test !isnothing(output)
        @test size(Bas3ImageSegmentation.data(input)) == (756, 1008, 3)
        @test size(Bas3ImageSegmentation.data(output), 3) == 5  # 5 classes
        println("  ✓ Explicit types: input=$(size(Bas3ImageSegmentation.data(input))), output channels=$(size(Bas3ImageSegmentation.data(output), 3))")
    end
    
    @testset "Load with default input_type" begin
        output_type_test = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
        
        input, output = load_images(
            TEST_SOURCE_DIR, TEST_INDEX;
            output_type = output_type_test,
            output_collection = true
        )
        
        @test !isnothing(input)
        @test !isnothing(output)
        println("  ✓ Default input_type works")
    end
end

# ============================================================================
# Test Suite 2: Single Mode (Individual Files)
# ============================================================================

@testset "load_images - Single Mode" begin
    println("\nTest 2: Single mode (individual files)")
    
    @testset "Load polygon mask" begin
        # Check if polygon mask exists
        patient_num = lpad(TEST_INDEX, 3, '0')
        mask_path = joinpath(TEST_SOURCE_DIR, "MuHa_$(patient_num)", "MuHa_$(patient_num)_polygon_mask.png")
        
        if isfile(mask_path)
            mask = load_images(
                TEST_SOURCE_DIR, TEST_INDEX;
                idtype = "polygon_mask",
                resize_ratio = 1//4
            )
            
            @test !isnothing(mask)
            @test size(Bas3ImageSegmentation.data(mask)) == (756, 1008, 3)
            println("  ✓ Polygon mask loaded: $(size(Bas3ImageSegmentation.data(mask)))")
        else
            println("  ⊘ Polygon mask not available for index $TEST_INDEX (skipping)")
        end
    end
    
    @testset "Load input image via single mode" begin
        img = load_images(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype = "raw_adj",
            filetype = "png",
            resize_ratio = 1//4
        )
        
        @test !isnothing(img)
        @test size(Bas3ImageSegmentation.data(img)) == (756, 1008, 3)
        println("  ✓ Input image (single mode): $(size(Bas3ImageSegmentation.data(img)))")
    end
    
    @testset "Different resize ratios" begin
        # Quarter
        img_quarter = load_images(TEST_SOURCE_DIR, TEST_INDEX; idtype="raw_adj", resize_ratio=1//4)
        @test size(Bas3ImageSegmentation.data(img_quarter)) == (756, 1008, 3)
        println("  ✓ Quarter-res: $(size(Bas3ImageSegmentation.data(img_quarter)))")
        
        # Half (slower, skip if needed)
        # img_half = load_images(TEST_SOURCE_DIR, TEST_INDEX; idtype="raw_adj", resize_ratio=1//2)
        # @test size(Bas3ImageSegmentation.data(img_half)) == (1512, 2016, 3)
    end
end

# ============================================================================
# Test Suite 3: Backward Compatibility (Deprecated Function)
# ============================================================================

@testset "Backward Compatibility" begin
    println("\nTest 3: Deprecated load_input_and_output() compatibility")
    
    @testset "Deprecated function still works" begin
        input_type_test = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:red, :green, :blue)})
        output_type_test = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
        
        # Should work but emit deprecation warning
        input, output = load_input_and_output(
            TEST_SOURCE_DIR, TEST_INDEX;
            input_type = input_type_test,
            output_type = output_type_test,
            output_collection = true
        )
        
        @test !isnothing(input)
        @test !isnothing(output)
        println("  ✓ Deprecated function works (with warning)")
    end
end

# ============================================================================
# Test Suite 4: Error Handling
# ============================================================================

@testset "Error Handling" begin
    println("\nTest 4: Error handling")
    
    @testset "Missing required parameters" begin
        @test_throws ErrorException load_images(TEST_SOURCE_DIR, TEST_INDEX)
        println("  ✓ Correctly errors on missing parameters")
    end
    
    @testset "Invalid index" begin
        @test_throws Exception load_images(
            TEST_SOURCE_DIR, 999;
            idtype = "polygon_mask"
        )
        println("  ✓ Correctly errors on invalid index")
    end
    
    @testset "Invalid idtype" begin
        @test_throws Exception load_images(
            TEST_SOURCE_DIR, TEST_INDEX;
            idtype = "nonexistent_type"
        )
        println("  ✓ Correctly errors on invalid idtype")
    end
end

# ============================================================================
# Summary
# ============================================================================

println("\n" * "="^80)
println("All Tests Complete!")
println("="^80)
println("\nv2.0.0 Unified API validated:")
println("  ✓ Pair mode (input + output)")
println("  ✓ Single mode (polygon masks, individual files)")
println("  ✓ Backward compatibility (deprecated function)")
println("  ✓ Error handling")
