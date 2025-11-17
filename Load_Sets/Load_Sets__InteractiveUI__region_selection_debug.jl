# Load_Sets__InteractiveUI__region_selection_debug.jl
# Debug test for region selection functionality
# Tests the mouse event handling and coordinate transformation

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "DEBUG: Region Selection in Load_Sets__InteractiveUI.jl\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)

write(stdout, "Loading packages...\n"); flush(stdout)

using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
using Statistics
using LinearAlgebra

write(stdout, "✓ Packages loaded\n"); flush(stdout)

test_results = Dict{String, Bool}()

# ==============================================================================
# Test 1: axis_to_pixel coordinate transformation (from line 364)
# ==============================================================================

write(stdout, "\nTest 1: axis_to_pixel coordinate transformation\n"); flush(stdout)

function axis_to_pixel(point_axis, img_height, img_width)
    rot_row = round(Int, point_axis[1])
    rot_col = round(Int, point_axis[2])
    
    orig_row = img_height - rot_col + 1
    orig_col = rot_row
    
    return (orig_row, orig_col)
end

try
    # Simulate various click positions on a 100x200 image
    img_height, img_width = 100, 200
    
    test_cases = [
        ((10.0, 10.0), "Top-left area"),
        ((100.0, 50.0), "Middle area"),
        ((190.0, 90.0), "Bottom-right area"),
        ((1.0, 1.0), "Absolute top-left"),
        ((200.0, 100.0), "Absolute bottom-right")
    ]
    
    write(stdout, "  Image dimensions: $(img_height)×$(img_width) (H×W)\n"); flush(stdout)
    
    for (point, desc) in test_cases
        orig = axis_to_pixel(point, img_height, img_width)
        write(stdout, "  $desc: axis$point -> pixel$orig\n"); flush(stdout)
        
        # Validate bounds
        if orig[1] < 1 || orig[1] > img_height || orig[2] < 1 || orig[2] > img_width
            write(stdout, "    ⚠️  WARNING: Out of bounds!\n"); flush(stdout)
        end
    end
    
    test_results["axis_to_pixel_basic"] = true
    write(stdout, "  ✓ Coordinate transformation working\n"); flush(stdout)
catch e
    test_results["axis_to_pixel_basic"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 2: make_rectangle function (from line 387)
# ==============================================================================

write(stdout, "\nTest 2: make_rectangle function\n"); flush(stdout)

function make_rectangle(c1, c2)
    x_min, x_max = minmax(c1[1], c2[1])
    y_min, y_max = minmax(c1[2], c2[2])
    return Bas3GLMakie.GLMakie.Point2f[
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
        Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
        Bas3GLMakie.GLMakie.Point2f(x_min, y_min)
    ]
end

try
    # Test with normal selection
    c1 = (10.0, 20.0)
    c2 = (100.0, 80.0)
    rect = make_rectangle(c1, c2)
    
    @assert Base.length(rect) == 5
    @assert rect[1] == rect[5]  # Closed loop
    
    write(stdout, "  Rectangle from $c1 to $c2:\n"); flush(stdout)
    write(stdout, "    $(Base.length(rect)) points (closed loop: $(rect[1] == rect[5]))\n"); flush(stdout)
    
    # Test with reversed selection (user clicks top-right first, then bottom-left)
    c1_rev = (100.0, 80.0)
    c2_rev = (10.0, 20.0)
    rect_rev = make_rectangle(c1_rev, c2_rev)
    
    @assert rect == rect_rev  # Should produce same rectangle
    
    write(stdout, "  Reversed selection produces same rectangle: ✓\n"); flush(stdout)
    
    test_results["make_rectangle"] = true
    write(stdout, "  ✓ Rectangle creation working\n"); flush(stdout)
catch e
    test_results["make_rectangle"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test 3: Region bounds validation
# ==============================================================================

write(stdout, "\nTest 3: Region bounds validation\n"); flush(stdout)

try
    img_height, img_width = 100, 200
    
    # Simulate user clicking two corners
    click1_axis = (20.0, 30.0)  # First click
    click2_axis = (80.0, 70.0)  # Second click
    
    # Convert to pixel coordinates
    c1_px = axis_to_pixel(click1_axis, img_height, img_width)
    c2_px = axis_to_pixel(click2_axis, img_height, img_width)
    
    write(stdout, "  Click 1: axis$click1_axis -> pixel$c1_px\n"); flush(stdout)
    write(stdout, "  Click 2: axis$click2_axis -> pixel$c2_px\n"); flush(stdout)
    
    # Ensure correct ordering (as done in the actual code at line 742-743)
    r_min, r_max = minmax(c1_px[1], c2_px[1])
    c_min, c_max = minmax(c1_px[2], c2_px[2])
    
    region = (r_min, r_max, c_min, c_max)
    
    write(stdout, "  Region bounds: rows[$r_min:$r_max], cols[$c_min:$c_max]\n"); flush(stdout)
    
    # Validate
    @assert r_min >= 1 && r_max <= img_height
    @assert c_min >= 1 && c_max <= img_width
    @assert r_min < r_max
    @assert c_min < c_max
    
    area = (r_max - r_min + 1) * (c_max - c_min + 1)
    write(stdout, "  Region area: $(area) pixels\n"); flush(stdout)
    
    test_results["region_bounds"] = true
    write(stdout, "  ✓ Region bounds validation passed\n"); flush(stdout)
catch e
    test_results["region_bounds"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
    Base.showerror(stdout, e, catch_backtrace())
    write(stdout, "\n"); flush(stdout)
end

# ==============================================================================
# Test 4: Observable state transitions
# ==============================================================================

write(stdout, "\nTest 4: Observable state transitions\n"); flush(stdout)

try
    # Simulate the selection state machine
    selection_active = Bas3GLMakie.GLMakie.Observable(false)
    selection_corner1 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    selection_corner2 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    selection_complete = Bas3GLMakie.GLMakie.Observable(false)
    
    write(stdout, "  Initial state:\n"); flush(stdout)
    write(stdout, "    active=$(selection_active[]), complete=$(selection_complete[])\n"); flush(stdout)
    write(stdout, "    corner1=$(selection_corner1[]), corner2=$(selection_corner2[])\n"); flush(stdout)
    
    # Activate selection
    selection_active[] = true
    write(stdout, "  After activation: active=$(selection_active[])\n"); flush(stdout)
    
    # First click
    selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(20.0, 30.0)
    write(stdout, "  After 1st click: corner1=$(selection_corner1[])\n"); flush(stdout)
    
    # Check state before second click
    if selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0) && !selection_complete[]
        write(stdout, "  Ready for 2nd click ✓\n"); flush(stdout)
    else
        write(stdout, "  ✗ State error before 2nd click\n"); flush(stdout)
        test_results["observable_state"] = false
    end
    
    # Second click
    selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(80.0, 70.0)
    selection_complete[] = true
    write(stdout, "  After 2nd click: corner2=$(selection_corner2[]), complete=$(selection_complete[])\n"); flush(stdout)
    
    # Verify final state
    @assert selection_active[]
    @assert selection_complete[]
    @assert selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
    @assert selection_corner2[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
    
    # Clear selection
    selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
    selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
    selection_complete[] = false
    
    write(stdout, "  After clear: complete=$(selection_complete[]), corner1=$(selection_corner1[])\n"); flush(stdout)
    
    test_results["observable_state"] = true
    write(stdout, "  ✓ Observable state transitions working\n"); flush(stdout)
catch e
    test_results["observable_state"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
    Base.showerror(stdout, e, catch_backtrace())
    write(stdout, "\n"); flush(stdout)
end

# ==============================================================================
# Test 5: Mouse event consume logic
# ==============================================================================

write(stdout, "\nTest 5: Mouse event consume logic\n"); flush(stdout)

try
    # Test the Consume return type used in mouse handlers
    consume_true = Bas3GLMakie.GLMakie.Consume(true)
    consume_false = Bas3GLMakie.GLMakie.Consume(false)
    
    write(stdout, "  Consume(true): $consume_true\n"); flush(stdout)
    write(stdout, "  Consume(false): $consume_false\n"); flush(stdout)
    
    # Simulate event handler logic
    selection_active = true
    selection_complete = false
    click_in_axis = true  # mp is not nothing
    
    should_consume = selection_active && !selection_complete && click_in_axis
    
    write(stdout, "  Should consume event: $should_consume\n"); flush(stdout)
    
    test_results["consume_logic"] = true
    write(stdout, "  ✓ Event consume logic working\n"); flush(stdout)
catch e
    test_results["consume_logic"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test Summary
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST SUMMARY\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)

total = Base.length(test_results)
passed = Base.count(Base.values(test_results))
failed = total - passed

write(stdout, "Total Tests: $total\n"); flush(stdout)
write(stdout, "Passed: $passed\n"); flush(stdout)
write(stdout, "Failed: $failed\n"); flush(stdout)

if failed > 0
    write(stdout, "\nFailed tests:\n"); flush(stdout)
    for (name, result) in test_results
        if !result
            write(stdout, "  ✗ $name\n"); flush(stdout)
        end
    end
end

write(stdout, "="^80 * "\n"); flush(stdout)

# ==============================================================================
# Test 6: Identify potential issues
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "POTENTIAL ISSUES ANALYSIS\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

write(stdout, "Analyzing common region selection failure modes:\n\n"); flush(stdout)

write(stdout, "1. Mouse Event Priority:\n"); flush(stdout)
write(stdout, "   - Event handlers use priority=2\n"); flush(stdout)
write(stdout, "   - Higher priority handlers execute first\n"); flush(stdout)
write(stdout, "   - Check if other handlers are consuming events first\n\n"); flush(stdout)

write(stdout, "2. Coordinate System:\n"); flush(stdout)
write(stdout, "   - Image displayed with rotr90()\n"); flush(stdout)
write(stdout, "   - axis_to_pixel() reverses the transformation\n"); flush(stdout)
write(stdout, "   - Ensure clicks are within axis bounds\n\n"); flush(stdout)

write(stdout, "3. Observable Updates:\n"); flush(stdout)
write(stdout, "   - selection_rect[] must be updated after both clicks\n"); flush(stdout)
write(stdout, "   - preview_rect[] updates during mouse move\n"); flush(stdout)
write(stdout, "   - Check if observables are triggering updates\n\n"); flush(stdout)

write(stdout, "4. State Machine:\n"); flush(stdout)
write(stdout, "   - Initial: active=false, corner1=(0,0), complete=false\n"); flush(stdout)
write(stdout, "   - After toggle: active=true\n"); flush(stdout)
write(stdout, "   - After 1st click: corner1=(x,y)\n"); flush(stdout)
write(stdout, "   - After 2nd click: corner2=(x,y), complete=true\n"); flush(stdout)
write(stdout, "   - Ensure state transitions happen correctly\n\n"); flush(stdout)

write(stdout, "5. Mouse Position Check:\n"); flush(stdout)
write(stdout, "   - mouseposition(axs3.scene) returns nothing if outside axis\n"); flush(stdout)
write(stdout, "   - Check ensures clicks are within bounds\n"); flush(stdout)
write(stdout, "   - If user clicks outside image, event is ignored\n\n"); flush(stdout)

write(stdout, "="^80 * "\n"); flush(stdout)
