# Load_Sets__CompareUI__test.jl
# Comprehensive test suite for Patient Image Comparison UI
#
# Usage:
#   julia --script=Bas3ImageSegmentation/Load_Sets/Load_Sets__CompareUI__test.jl
#
# Test Categories:
#   1. Unit Tests: Database functions, validation functions
#   2. Integration Tests: Figure creation, widget interaction
#   3. Static Analysis: Code structure verification (cache structure)
#   4. Interactive Tests: Full UI workflow simulation (optional)
#
# Consolidated from:
#   - test_cache_structure.jl

println("=" ^ 80)
println("Load_Sets__CompareUI__test.jl - Comprehensive Test Suite")
println("=" ^ 80)
println("[TIMING] Test started at: $(Dates.now())")

using Dates

# ============================================================================
# SETUP
# ============================================================================

println("\n[SETUP] Loading base modules...")
include("Load_Sets.jl")

println("[SETUP] Loading CompareUI module...")
include("Load_Sets__CompareUI.jl")

# Track test results
const TEST_RESULTS = Dict{String, Bool}()
const TEST_MESSAGES = Dict{String, String}()

function record_test(name::String, passed::Bool, msg::String="")
    TEST_RESULTS[name] = passed
    TEST_MESSAGES[name] = msg
    status = passed ? "PASS" : "FAIL"
    symbol = passed ? "✅" : "❌"
    println("  [$status] $symbol $name" * (isempty(msg) ? "" : " - $msg"))
end

function run_test(test_fn::Function, name::String)
    try
        result = test_fn()
        record_test(name, true, "")
        return result
    catch e
        record_test(name, false, string(e))
        return nothing
    end
end

# ============================================================================
# UNIT TESTS: DATABASE FUNCTIONS
# ============================================================================

println("\n" * "=" ^ 80)
println("UNIT TESTS: Database Functions")
println("=" ^ 80)

# Test: get_database_path
run_test("get_database_path returns valid path") do
    db_path = get_database_path()
    @assert !isempty(db_path) "Database path should not be empty"
    @assert endswith(db_path, "MuHa.xlsx") "Database path should end with MuHa.xlsx"
    return db_path
end

# Test: Database file exists
db_path = get_database_path()
run_test("Database file exists") do
    @assert isfile(db_path) "Database file must exist at: $db_path"
end

# Test: get_all_patient_ids returns sorted integers
run_test("get_all_patient_ids returns sorted integers") do
    patient_ids = get_all_patient_ids(db_path)
    @assert isa(patient_ids, Vector{Int}) "Should return Vector{Int}"
    @assert length(patient_ids) > 0 "Should have at least one patient"
    @assert issorted(patient_ids) "Patient IDs should be sorted"
    @assert all(id > 0 for id in patient_ids) "All IDs should be positive"
    return patient_ids
end

# Test: get_images_for_patient returns correct structure
run_test("get_images_for_patient returns correct structure") do
    patient_ids = get_all_patient_ids(db_path)
    if isempty(patient_ids)
        error("No patients to test with")
    end
    
    entries = get_images_for_patient(db_path, patient_ids[1])
    @assert isa(entries, Vector) "Should return a Vector"
    
    if !isempty(entries)
        entry = entries[1]
        @assert haskey(entry, :image_index) "Entry should have :image_index"
        @assert haskey(entry, :filename) "Entry should have :filename"
        @assert haskey(entry, :date) "Entry should have :date"
        @assert haskey(entry, :info) "Entry should have :info"
        @assert haskey(entry, :row) "Entry should have :row"
        @assert isa(entry.image_index, Int) ":image_index should be Int"
        @assert isa(entry.row, Int) ":row should be Int"
    end
    return entries
end

# Test: get_images_for_patient returns empty for non-existent patient
run_test("get_images_for_patient returns empty for non-existent patient") do
    entries = get_images_for_patient(db_path, 999999)
    @assert isempty(entries) "Should return empty Vector for non-existent patient"
end

# Test: get_images_for_patient sorted by date
run_test("get_images_for_patient sorted by date") do
    patient_ids = get_all_patient_ids(db_path)
    
    for pid in patient_ids[1:min(3, length(patient_ids))]
        entries = get_images_for_patient(db_path, pid)
        if length(entries) >= 2
            dates = [e.date for e in entries]
            @assert issorted(dates) "Entries should be sorted by date for patient $pid"
        end
    end
end

# ============================================================================
# UNIT TESTS: VALIDATION FUNCTIONS
# ============================================================================

println("\n" * "=" ^ 80)
println("UNIT TESTS: Validation Functions")
println("=" ^ 80)

# Test: validate_date_compare - valid dates
run_test("validate_date_compare accepts valid dates") do
    valid_cases = [
        ("2025-11-29", true),
        ("2024-01-15", true),
        ("2020-12-31", true),
        ("", true),  # Empty is OK
    ]
    
    for (date_str, expected) in valid_cases
        (valid, msg) = validate_date_compare(date_str)
        @assert valid == expected "Date '$date_str' should be valid=$expected, got valid=$valid, msg=$msg"
    end
end

# Test: validate_date_compare - invalid format
run_test("validate_date_compare rejects invalid format") do
    invalid_cases = [
        "not-a-date",
        "25-11-29",      # Short year
        "2025/11/29",    # Wrong separator
        "2025.11.29",    # Wrong separator
        "11-29-2025",    # Wrong order
        "2025-1-29",     # Single digit month
        "2025-11-9",     # Single digit day
    ]
    
    for date_str in invalid_cases
        (valid, msg) = validate_date_compare(date_str)
        @assert !valid "Date '$date_str' should be invalid"
    end
end

# Test: validate_date_compare - invalid values
run_test("validate_date_compare rejects invalid date values") do
    invalid_cases = [
        "2025-13-01",    # Invalid month
        "2025-00-01",    # Zero month
        "2025-02-30",    # Invalid day for February
    ]
    
    for date_str in invalid_cases
        (valid, msg) = validate_date_compare(date_str)
        @assert !valid "Date '$date_str' should be invalid"
    end
end

# Test: validate_date_compare - future dates
run_test("validate_date_compare rejects future dates") do
    future_date = Dates.format(Dates.today() + Dates.Day(365), "yyyy-mm-dd")
    (valid, msg) = validate_date_compare(future_date)
    @assert !valid "Future date '$future_date' should be invalid"
    @assert occursin("Zukunft", msg) "Error message should mention future"
end

# Test: validate_info_compare - valid info
run_test("validate_info_compare accepts valid info") do
    valid_cases = [
        "",                  # Empty
        "Short note",        # Normal
        "A" ^ 500,          # Max length
    ]
    
    for info_str in valid_cases
        (valid, msg) = validate_info_compare(info_str)
        @assert valid "Info of length $(length(info_str)) should be valid"
    end
end

# Test: validate_info_compare - too long
run_test("validate_info_compare rejects >500 chars") do
    long_info = "B" ^ 501
    (valid, msg) = validate_info_compare(long_info)
    @assert !valid "Info with 501 chars should be invalid"
    @assert occursin("500", msg) "Error message should mention 500 limit"
end

# ============================================================================
# INTEGRATION TESTS: FIGURE CREATION
# ============================================================================

println("\n" * "=" ^ 80)
println("INTEGRATION TESTS: Figure Creation")
println("=" ^ 80)

# Test: create_compare_figure returns Figure
global test_fig = nothing
run_test("create_compare_figure returns GLMakie Figure") do
    global test_fig = create_compare_figure(sets, input_type; max_images_per_row=6)
    @assert test_fig !== nothing "Figure should not be nothing"
    @assert isa(test_fig, Bas3GLMakie.GLMakie.Figure) "Should return a Figure"
    return test_fig
end

# Test: create_compare_figure in test_mode returns NamedTuple
global test_result = nothing
run_test("create_compare_figure test_mode=true returns internals") do
    global test_result = create_compare_figure(sets, input_type; max_images_per_row=6, test_mode=true)
    @assert test_result !== nothing "test_result should not be nothing"
    @assert haskey(test_result, :figure) "Should have :figure"
    @assert haskey(test_result, :observables) "Should have :observables"
    @assert haskey(test_result, :widgets) "Should have :widgets"
    @assert haskey(test_result, :dynamic_widgets) "Should have :dynamic_widgets"
    @assert haskey(test_result, :functions) "Should have :functions"
    @assert haskey(test_result, :db_path) "Should have :db_path"
    @assert haskey(test_result, :all_patient_ids) "Should have :all_patient_ids"
    return test_result
end

# Test: test_mode exposes required observables
run_test("test_mode exposes required observables") do
    obs = test_result.observables
    @assert haskey(obs, :current_patient_id) "Should expose :current_patient_id"
    @assert haskey(obs, :current_entries) "Should expose :current_entries"
    @assert isa(obs[:current_patient_id], Bas3GLMakie.GLMakie.Observable) "Should be Observable"
    @assert isa(obs[:current_entries], Bas3GLMakie.GLMakie.Observable) "Should be Observable"
end

# Test: test_mode exposes required widgets
run_test("test_mode exposes required widgets") do
    widgets = test_result.widgets
    @assert haskey(widgets, :patient_menu) "Should expose :patient_menu"
    @assert haskey(widgets, :refresh_button) "Should expose :refresh_button"
    @assert haskey(widgets, :status_label) "Should expose :status_label"
end

# Test: test_mode exposes dynamic widgets arrays
run_test("test_mode exposes dynamic widget arrays") do
    dyn = test_result.dynamic_widgets
    @assert haskey(dyn, :image_axes) "Should expose :image_axes"
    @assert haskey(dyn, :date_textboxes) "Should expose :date_textboxes"
    @assert haskey(dyn, :info_textboxes) "Should expose :info_textboxes"
    @assert haskey(dyn, :save_buttons) "Should expose :save_buttons"
    @assert haskey(dyn, :image_labels) "Should expose :image_labels"
    @assert haskey(dyn, :image_observables) "Should expose :image_observables"
end

# Test: test_mode exposes helper functions
run_test("test_mode exposes helper functions") do
    funcs = test_result.functions
    @assert haskey(funcs, :build_patient_images!) "Should expose :build_patient_images!"
    @assert haskey(funcs, :clear_images_grid!) "Should expose :clear_images_grid!"
    @assert haskey(funcs, :get_image_by_index) "Should expose :get_image_by_index"
end

# ============================================================================
# INTEGRATION TESTS: WIDGET INTERACTION
# ============================================================================

println("\n" * "=" ^ 80)
println("INTEGRATION TESTS: Widget Interaction")
println("=" ^ 80)

# Display figure for interaction tests
println("\n[SETUP] Displaying figure for interaction tests...")
const screen = Bas3GLMakie.GLMakie.Screen()
display(screen, test_result.figure)
sleep(2)

# Test: Patient menu selection triggers callback
run_test("Patient menu selection triggers callback") do
    if length(test_result.all_patient_ids) < 2
        println("    [SKIP] Only 1 patient available")
        return
    end
    
    obs = test_result.observables
    widgets = test_result.widgets
    
    # Get initial patient
    initial_patient = obs[:current_patient_id][]
    
    # Select a different patient
    second_patient = test_result.all_patient_ids[2]
    widgets[:patient_menu].selection[] = string(second_patient)
    sleep(1)
    
    # Verify patient changed
    new_patient = obs[:current_patient_id][]
    @assert new_patient == second_patient "Patient should change to $second_patient, got $new_patient"
end

# Test: Patient selection updates entries
run_test("Patient selection updates current_entries") do
    obs = test_result.observables
    
    # Get entries for current patient
    current_pid = obs[:current_patient_id][]
    entries = obs[:current_entries][]
    
    # Verify entries match database
    db_entries = get_images_for_patient(test_result.db_path, current_pid)
    @assert length(entries) == length(db_entries) "Entry count should match database"
end

# Test: Textbox editing works
run_test("Date textbox can be edited") do
    dyn = test_result.dynamic_widgets
    if isempty(dyn[:date_textboxes])
        println("    [SKIP] No textboxes available")
        return
    end
    
    date_tb = dyn[:date_textboxes][1]
    test_date = "2025-11-29"
    date_tb.stored_string[] = test_date
    sleep(0.5)
    
    @assert date_tb.stored_string[] == test_date "Date should be set to $test_date"
end

run_test("Info textbox can be edited") do
    dyn = test_result.dynamic_widgets
    if isempty(dyn[:info_textboxes])
        println("    [SKIP] No textboxes available")
        return
    end
    
    info_tb = dyn[:info_textboxes][1]
    test_info = "Test info from Load_Sets__CompareUI__test.jl"
    info_tb.stored_string[] = test_info
    sleep(0.5)
    
    @assert info_tb.stored_string[] == test_info "Info should be set"
end

# Test: Save button click increments counter
run_test("Save button click increments counter") do
    dyn = test_result.dynamic_widgets
    if isempty(dyn[:save_buttons])
        println("    [SKIP] No save buttons available")
        return
    end
    
    save_btn = dyn[:save_buttons][1]
    initial_clicks = save_btn.clicks[]
    save_btn.clicks[] = initial_clicks + 1
    sleep(1)
    
    @assert save_btn.clicks[] == initial_clicks + 1 "Click count should increment"
end

# Test: Refresh button updates patient list
run_test("Refresh button click updates status") do
    widgets = test_result.widgets
    
    refresh_btn = widgets[:refresh_button]
    initial_clicks = refresh_btn.clicks[]
    refresh_btn.clicks[] = initial_clicks + 1
    sleep(2)
    
    # Check status label was updated
    status_text = widgets[:status_label].text[]
    @assert !isempty(status_text) "Status should be updated after refresh"
end

# Test: build_patient_images! function works
run_test("build_patient_images! function works") do
    funcs = test_result.functions
    obs = test_result.observables
    
    # Get a patient ID
    pid = test_result.all_patient_ids[1]
    
    # Call the function
    funcs[:build_patient_images!](pid)
    sleep(1)
    
    # Verify entries were updated
    entries = obs[:current_entries][]
    expected = get_images_for_patient(test_result.db_path, pid)
    @assert length(entries) == length(expected) "Entries should match database for patient $pid"
end

# Test: clear_images_grid! function works
run_test("clear_images_grid! function clears widgets") do
    funcs = test_result.functions
    dyn = test_result.dynamic_widgets
    
    # First ensure we have widgets
    funcs[:build_patient_images!](test_result.all_patient_ids[1])
    sleep(1)
    
    # Clear the grid
    funcs[:clear_images_grid!]()
    
    # Verify arrays are empty
    @assert isempty(dyn[:image_axes]) "image_axes should be empty"
    @assert isempty(dyn[:date_textboxes]) "date_textboxes should be empty"
    @assert isempty(dyn[:info_textboxes]) "info_textboxes should be empty"
    @assert isempty(dyn[:save_buttons]) "save_buttons should be empty"
end

# Test: get_image_by_index returns valid image
run_test("get_image_by_index returns valid image") do
    funcs = test_result.functions
    
    # Get first available image index
    entries = get_images_for_patient(test_result.db_path, test_result.all_patient_ids[1])
    if isempty(entries)
        println("    [SKIP] No images available")
        return
    end
    
    img_idx = entries[1].image_index
    img = funcs[:get_image_by_index](img_idx)
    
    @assert img !== nothing "Image should not be nothing"
    @assert size(img, 1) > 0 && size(img, 2) > 0 "Image should have positive dimensions"
end

# ============================================================================
# STATIC ANALYSIS: CODE STRUCTURE VERIFICATION
# ============================================================================

println("\n" * "=" ^ 80)
println("STATIC ANALYSIS: Cache Structure Verification")
println("=" ^ 80)
println()
println("(from test_cache_structure.jl)")
println()

# Read CompareUI source code
compare_ui_path = joinpath(@__DIR__, "Load_Sets__CompareUI.jl")
code = read(compare_ui_path, String)

# Test: Preload returns only raw data (no bbox/HSV computation)
run_test("Preload comment indicates raw data only (no bbox/HSV)") do
    @assert occursin("# (bbox/HSV will be computed on-demand when UI displays them)", code) "Preload comment should indicate on-demand bbox/HSV"
end

# Test: Cache data structure does not include bboxes/hsv_data
run_test("Cache data structure excludes bboxes/hsv_data") do
    # Find the data tuple in preload section
    data_section = match(r"data = \(\s*image_index.*?height.*?\)"s, code)
    if isnothing(data_section)
        error("Could not find data tuple in preload section")
    end
    cached_struct = data_section.match
    @assert !occursin("bboxes", cached_struct) "Cache should NOT include bboxes"
    @assert !occursin("hsv_data", cached_struct) "Cache should NOT include hsv_data"
end

# Test: Bboxes computed on-demand in UI
run_test("Bboxes computed on-demand in UI") do
    @assert occursin("# Layer 3: Draw bounding boxes (computed on-demand from cached raw data)", code) "Comment for on-demand bbox computation should exist"
end

# Test: HSV computed on-demand in UI
run_test("HSV computed on-demand in UI") do
    @assert occursin("# Row 3: HSV mini histograms (computed on-demand from cached raw data)", code) "Comment for on-demand HSV computation should exist"
end

# Test: extract_class_bboxes called from cached img_data
run_test("extract_class_bboxes called from cached data") do
    @assert occursin("extract_class_bboxes(img_data.output_raw", code) "Should call extract_class_bboxes from cached img_data"
end

# Read InteractiveUI source code
interactive_ui_path = joinpath(@__DIR__, "Load_Sets__InteractiveUI.jl")
code_interactive = read(interactive_ui_path, String)

# Test: InteractiveUI cache type updated (no bboxes)
run_test("InteractiveUI cache excludes bboxes") do
    @assert occursin("# NOTE: bboxes computed on-demand", code_interactive) "InteractiveUI should have on-demand bboxes comment"
end

# ============================================================================
# SUMMARY
# ============================================================================

println("\n" * "=" ^ 80)
println("TEST SUMMARY")
println("=" ^ 80)

passed = count(v -> v, values(TEST_RESULTS))
failed = count(v -> !v, values(TEST_RESULTS))
total = length(TEST_RESULTS)

println("\nResults: $passed passed, $failed failed, $total total")

if failed > 0
    println("\nFailed tests:")
    for (name, passed) in TEST_RESULTS
        if !passed
            println("  ❌ $name")
            msg = TEST_MESSAGES[name]
            if !isempty(msg)
                println("     Error: $msg")
            end
        end
    end
end

println("\n[TIMING] Test finished at: $(Dates.now())")

# Final assertion
@assert failed == 0 "Some tests failed!"

println("\n[DONE] All tests passed! ✅")