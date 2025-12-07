# Load_Sets__CompareUI__test_polygon.jl
# Unit tests for polygon geometry functions in CompareUI

using Test
using Bas3GLMakie

# Import polygon geometry functions from CompareUI
include("Load_Sets__CompareUI.jl")

println("\n" * "="^70)
println("Testing CompareUI Polygon Geometry Functions")
println("="^70 * "\n")

@testset "Polygon Geometry - Square" begin
    println("\n[TEST] Square polygon (4 vertices)")
    
    # Define a square: (10,10), (50,10), (50,50), (10,50)
    vertices = [
        Bas3GLMakie.GLMakie.Point2f(10, 10),
        Bas3GLMakie.GLMakie.Point2f(50, 10),
        Bas3GLMakie.GLMakie.Point2f(50, 50),
        Bas3GLMakie.GLMakie.Point2f(10, 50)
    ]
    
    # Test 1: Point inside square
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(30, 30), vertices) == true
    println("  ✓ Point (30,30) inside square")
    
    # Test 2: Point outside square
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(5, 5), vertices) == false
    println("  ✓ Point (5,5) outside square")
    
    # Test 3: Point on edge (boundary case - may vary by implementation)
    # Most implementations treat edge as inside
    println("  ✓ Point (10,30) on edge: $(point_in_polygon(Bas3GLMakie.GLMakie.Point2f(10, 30), vertices))")
    
    # Test 4: AABB calculation
    min_x, max_x, min_y, max_y = polygon_bounds_aabb(vertices)
    @test min_x == 10.0
    @test max_x == 50.0
    @test min_y == 10.0
    @test max_y == 50.0
    println("  ✓ AABB: x=[10.0, 50.0], y=[10.0, 50.0]")
end

@testset "Polygon Geometry - Pentagon" begin
    println("\n[TEST] Pentagon polygon (5 vertices)")
    
    # Define a regular-ish pentagon
    vertices = [
        Bas3GLMakie.GLMakie.Point2f(30, 10),
        Bas3GLMakie.GLMakie.Point2f(50, 25),
        Bas3GLMakie.GLMakie.Point2f(40, 50),
        Bas3GLMakie.GLMakie.Point2f(20, 50),
        Bas3GLMakie.GLMakie.Point2f(10, 25)
    ]
    
    # Test 1: Point inside pentagon
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(30, 30), vertices) == true
    println("  ✓ Point (30,30) inside pentagon")
    
    # Test 2: Point outside pentagon
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(5, 5), vertices) == false
    println("  ✓ Point (5,5) outside pentagon")
    
    # Test 3: AABB calculation
    min_x, max_x, min_y, max_y = polygon_bounds_aabb(vertices)
    @test min_x == 10.0
    @test max_x == 50.0
    @test min_y == 10.0
    @test max_y == 50.0
    println("  ✓ AABB: x=[10.0, 50.0], y=[10.0, 50.0]")
end

@testset "Polygon Geometry - Edge Cases" begin
    println("\n[TEST] Edge cases")
    
    # Test 1: Empty polygon
    empty_verts = Bas3GLMakie.GLMakie.Point2f[]
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(10, 10), empty_verts) == false
    println("  ✓ Empty polygon returns false")
    
    # Test 2: Triangle (minimum valid polygon)
    triangle = [
        Bas3GLMakie.GLMakie.Point2f(10, 10),
        Bas3GLMakie.GLMakie.Point2f(50, 10),
        Bas3GLMakie.GLMakie.Point2f(30, 40)
    ]
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(30, 20), triangle) == true
    println("  ✓ Triangle (3 vertices) works correctly")
    
    # Test 3: Two points (invalid polygon)
    line = [
        Bas3GLMakie.GLMakie.Point2f(10, 10),
        Bas3GLMakie.GLMakie.Point2f(50, 50)
    ]
    @test point_in_polygon(Bas3GLMakie.GLMakie.Point2f(30, 30), line) == false
    println("  ✓ Line segment (2 vertices) returns false")
end

@testset "Polygon Performance" begin
    println("\n[TEST] Performance check")
    
    # Create a polygon with 8 vertices
    vertices = [
        Bas3GLMakie.GLMakie.Point2f(100, 50),
        Bas3GLMakie.GLMakie.Point2f(150, 80),
        Bas3GLMakie.GLMakie.Point2f(180, 130),
        Bas3GLMakie.GLMakie.Point2f(170, 180),
        Bas3GLMakie.GLMakie.Point2f(120, 200),
        Bas3GLMakie.GLMakie.Point2f(70, 180),
        Bas3GLMakie.GLMakie.Point2f(50, 130),
        Bas3GLMakie.GLMakie.Point2f(70, 80)
    ]
    
    # Time 1000 point-in-polygon tests
    num_tests = 1000
    test_point = Bas3GLMakie.GLMakie.Point2f(120, 120)
    
    elapsed = @elapsed begin
        for i in 1:num_tests
            point_in_polygon(test_point, vertices)
        end
    end
    
    avg_time_ms = (elapsed / num_tests) * 1000
    println("  ✓ Average time per test: $(round(avg_time_ms, digits=6)) ms")
    println("  ✓ Target: < 0.1 ms per test")
    @test avg_time_ms < 0.1  # Should be very fast for 8 vertices
end

println("\n" * "="^70)
println("All polygon geometry tests completed!")
println("="^70 * "\n")
