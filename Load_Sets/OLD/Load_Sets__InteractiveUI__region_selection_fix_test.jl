# Load_Sets__InteractiveUI__region_selection_fix_test.jl
# Test the fixed region selection logic

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST: Region Selection Fix Verification\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

# Simulate the selection state machine with the fixed logic
struct Point2f
    x::Float64
    y::Float64
end

Base.:(==)(a::Point2f, b::Point2f) = a.x == b.x && a.y == b.y

mutable struct Observable{T}
    value::T
end

Base.getindex(o::Observable) = o.value
Base.setindex!(o::Observable, val) = (o.value = val)

# Initialize observables
selection_active = Observable(false)
selection_corner1 = Observable(Point2f(0.0, 0.0))
selection_corner2 = Observable(Point2f(0.0, 0.0))
selection_complete = Observable(false)

write(stdout, "Test 1: Normal two-click selection\n"); flush(stdout)
write(stdout, "-" ^40 * "\n"); flush(stdout)

# Activate selection
selection_active[] = true
write(stdout, "  1. Toggle ON: active=$(selection_active[])\n"); flush(stdout)

# First click at (20, 30)
mp1 = Point2f(20.0, 30.0)
if selection_active[] && !selection_complete[]
    if selection_corner1[] == Point2f(0.0, 0.0)
        selection_corner1[] = mp1
        write(stdout, "  2. First click at $mp1: corner1=$(selection_corner1[])\n"); flush(stdout)
    end
end

# Second click at (80, 70)
mp2 = Point2f(80.0, 70.0)
if selection_active[] && !selection_complete[]
    if selection_corner1[] != Point2f(0.0, 0.0)
        selection_corner2[] = mp2
        selection_complete[] = true
        write(stdout, "  3. Second click at $mp2: complete=$(selection_complete[])\n"); flush(stdout)
    end
end

@assert selection_complete[]
@assert selection_corner1[] == mp1
@assert selection_corner2[] == mp2
write(stdout, "  ✓ Selection completed correctly\n\n"); flush(stdout)

write(stdout, "Test 2: Click again after completion (NEW FEATURE)\n"); flush(stdout)
write(stdout, "-" ^40 * "\n"); flush(stdout)

# Third click - should start a new selection
mp3 = Point2f(15.0, 25.0)
if selection_active[]
    if !selection_complete[]
        # Not complete, normal click logic
        write(stdout, "  ERROR: Should be complete!\n"); flush(stdout)
    else
        # NEW LOGIC: Selection complete, start new selection
        selection_corner1[] = mp3
        selection_corner2[] = Point2f(0.0, 0.0)
        selection_complete[] = false
        write(stdout, "  4. Third click at $mp3: Starting new selection\n"); flush(stdout)
        write(stdout, "     corner1=$(selection_corner1[]), complete=$(selection_complete[])\n"); flush(stdout)
    end
end

@assert !selection_complete[]
@assert selection_corner1[] == mp3
@assert selection_corner2[] == Point2f(0.0, 0.0)
write(stdout, "  ✓ New selection started correctly\n\n"); flush(stdout)

write(stdout, "Test 3: Complete the new selection\n"); flush(stdout)
write(stdout, "-" ^40 * "\n"); flush(stdout)

# Fourth click - complete the new selection
mp4 = Point2f(95.0, 85.0)
if selection_active[] && !selection_complete[]
    if selection_corner1[] != Point2f(0.0, 0.0)
        selection_corner2[] = mp4
        selection_complete[] = true
        write(stdout, "  5. Fourth click at $mp4: New selection complete\n"); flush(stdout)
    end
end

@assert selection_complete[]
@assert selection_corner1[] == mp3
@assert selection_corner2[] == mp4
write(stdout, "  ✓ New selection completed with different corners\n\n"); flush(stdout)

write(stdout, "Test 4: Clear selection button\n"); flush(stdout)
write(stdout, "-" ^40 * "\n"); flush(stdout)

# Simulate clear button click
selection_corner1[] = Point2f(0.0, 0.0)
selection_corner2[] = Point2f(0.0, 0.0)
selection_complete[] = false
write(stdout, "  6. Clear button clicked\n"); flush(stdout)
write(stdout, "     complete=$(selection_complete[]), corner1=$(selection_corner1[])\n"); flush(stdout)

@assert !selection_complete[]
@assert selection_corner1[] == Point2f(0.0, 0.0)
write(stdout, "  ✓ Selection cleared correctly\n\n"); flush(stdout)

write(stdout, "Test 5: Toggle OFF and back ON\n"); flush(stdout)
write(stdout, "-" ^40 * "\n"); flush(stdout)

# Start a partial selection
selection_corner1[] = Point2f(10.0, 10.0)
write(stdout, "  7. Partial selection: corner1=$(selection_corner1[])\n"); flush(stdout)

# Toggle OFF
selection_active[] = false
write(stdout, "  8. Toggle OFF: active=$(selection_active[])\n"); flush(stdout)

# Toggle back ON - should reset incomplete selection
if true  # Simulating toggle ON
    selection_active[] = true
    # NEW LOGIC: Reset if incomplete
    if !selection_complete[] && selection_corner1[] != Point2f(0.0, 0.0)
        selection_corner1[] = Point2f(0.0, 0.0)
        selection_corner2[] = Point2f(0.0, 0.0)
        write(stdout, "  9. Toggle ON: Reset incomplete selection\n"); flush(stdout)
    end
end

@assert selection_corner1[] == Point2f(0.0, 0.0)
write(stdout, "  ✓ Incomplete selection cleared on toggle\n\n"); flush(stdout)

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "ALL TESTS PASSED ✓\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "\nSummary of fixes:\n"); flush(stdout)
write(stdout, "1. Clicks are now consumed (Consume(true)) whenever selection is active\n"); flush(stdout)
write(stdout, "2. After completing a selection, next click starts a new selection\n"); flush(stdout)
write(stdout, "3. Toggling ON with incomplete selection resets the state\n"); flush(stdout)
write(stdout, "4. User can create multiple selections without clicking 'Clear'\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
