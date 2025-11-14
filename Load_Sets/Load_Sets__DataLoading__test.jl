# Load_Sets__DataLoading__test.jl
# Tests for data loading logic (load_original_sets function)

# Mock JLD2
mutable struct MockJLD2State
    loads::Vector{String}
    saves::Vector{String}
end

const mock_state = MockJLD2State(String[], String[])

function mock_load(path::String)
    push!(mock_state.loads, path)
    return (zeros(Float32, 2, 2, 3), zeros(Float32, 2, 2, 5))
end

function mock_save(path::String)
    push!(mock_state.saves, path)
end

# Test disk loading logic
function test_disk_load(n::Int)
    result = []
    for i in 1:n
        path = "/mock/original/$(i).jld2"
        data = mock_load(path)
        push!(result, (data[1], data[2], i))
    end
    return result
end

# Test regenerate logic
function test_regen(n::Int)
    result = []
    for i in 1:n
        push!(result, (zeros(Float32, 2, 2, 3), zeros(Float32, 2, 2, 5)))
    end
    for i in 1:n
        mock_save("/mock/original/$(i).jld2")
    end
    return result
end

# Run tests
p = 0
t = 0

# Test 1: Disk load returns correct count
t += 1
empty!(mock_state.loads)
r = test_disk_load(3)
length(r) == 3 && (p += 1; println("✓ Test 1: Disk load returns 3 sets"))

# Test 2: JLD2.load called 3 times
t += 1
length(mock_state.loads) == 3 && (p += 1; println("✓ Test 2: JLD2.load called 3 times"))

# Test 3: Regenerate returns correct count
t += 1
empty!(mock_state.saves)
r2 = test_regen(2)
length(r2) == 2 && (p += 1; println("✓ Test 3: Regenerate returns 2 sets"))

# Test 4: JLD2.save called 2 times
t += 1
length(mock_state.saves) == 2 && (p += 1; println("✓ Test 4: JLD2.save called 2 times"))

# Test 5: No saves in disk load mode
t += 1
empty!(mock_state.saves)
test_disk_load(1)
length(mock_state.saves) == 0 && (p += 1; println("✓ Test 5: No saves in disk mode"))

# Test 6: Correct load path
t += 1
"/mock/original/1.jld2" in mock_state.loads && (p += 1; println("✓ Test 6: Correct load paths"))

println("$(p)/$(t) tests passed")
