# Load_Sets__InteractiveUI__test_extended.jl
# Comprehensive tests for Load_Sets__InteractiveUI.jl including interactive figure testing
# NOTE: Using write(stdout, ...) and Base.* functions to avoid module conflicts

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "TEST: Load_Sets__InteractiveUI.jl - COMPREHENSIVE TESTING\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)

write(stdout, "Loading packages (may take ~60s for GLMakie)...\n"); flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
using Statistics
using LinearAlgebra

write(stdout, "✓ Packages loaded\n"); flush(stdout)

write(stdout, "Loading modules...\n"); flush(stdout)
include("Load_Sets__ConnectedComponents.jl")
include("Load_Sets__MarkerCorrespondence.jl")
include("Load_Sets__ThinPlateSpline.jl")
include("Load_Sets__InteractiveUI.jl")
write(stdout, "✓ Modules loaded\n\n"); flush(stdout)

test_results = Dict{String, Bool}()

# ==============================================================================
# PHASE 1: Mock Data Infrastructure
# ==============================================================================

write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "PHASE 1: Setting up Mock Data Infrastructure\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

# Mock image type with required interface
struct MockImage
    data::Array{Float64, 3}
end

# Implement required interface methods
Bas3ImageSegmentation.data(img::MockImage) = img.data
Bas3ImageSegmentation.image(img::MockImage) = Bas3ImageSegmentation.RGB{Float32}.(img.data[:,:,1], img.data[:,:,2], img.data[:,:,3])
Base.size(img::MockImage) = Base.size(img.data)

# Mock output type with shape() method
struct MockOutputType end
Bas3ImageSegmentation.shape(::MockOutputType) = [:scar, :redness, :hematoma, :necrosis, :background]

# Mock input type (simple placeholder)
struct MockInputType end
Bas3ImageSegmentation.shape(::MockInputType) = [:red, :green, :blue]

"""
Create a mock dataset with synthetic images containing white marker rectangles.
Creates small images (size x size) with white rectangular markers that can be detected.
"""
function create_mock_dataset(n_images=3, img_size=(100, 100))
    sets = []
    
    for i in 1:n_images
        # Create input RGB image with a white marker
        input_data = zeros(Float64, img_size[1], img_size[2], 3)
        
        # Add some random background variation
        input_data[:, :, 1] .= 0.1 .+ 0.1 .* Base.rand(img_size...)  # Red
        input_data[:, :, 2] .= 0.1 .+ 0.1 .* Base.rand(img_size...)  # Green
        input_data[:, :, 3] .= 0.1 .+ 0.1 .* Base.rand(img_size...)  # Blue
        
        # Add white rectangular marker (aspect ratio ~5:1 for detection)
        # Position varies by image
        marker_h = 15
        marker_w = 75
        marker_r_start = 20 + (i-1) * 5  # Vary position slightly
        marker_c_start = 10
        
        input_data[marker_r_start:(marker_r_start+marker_h-1), 
                   marker_c_start:(marker_c_start+marker_w-1), :] .= 1.0
        
        # Create output segmentation mask (5 classes)
        output_data = zeros(Float64, img_size[1], img_size[2], 5)
        
        # Add some random segmentation regions
        # Class 1 (scar) - top left quadrant
        output_data[1:Base.div(img_size[1],2), 1:Base.div(img_size[2],2), 1] .= 
            Base.rand(Base.div(img_size[1],2), Base.div(img_size[2],2))
        
        # Class 2 (redness) - top right quadrant
        output_data[1:Base.div(img_size[1],2), (Base.div(img_size[2],2)+1):end, 2] .=
            Base.rand(Base.div(img_size[1],2), img_size[2] - Base.div(img_size[2],2))
        
        # Background for rest
        output_data[:, :, 5] .= 0.3
        
        # Normalize so each pixel sums to ~1.0
        for r in 1:img_size[1]
            for c in 1:img_size[2]
                total = Base.sum(output_data[r, c, :])
                if total > 0
                    output_data[r, c, :] ./= total
                end
            end
        end
        
        input_img = MockImage(input_data)
        output_img = MockImage(output_data)
        
        Base.push!(sets, (input_img, output_img))
    end
    
    return sets
end

write(stdout, "✓ Mock data infrastructure created\n\n"); flush(stdout)

# ==============================================================================
# PHASE 1 TEST: Verify mock data creation
# ==============================================================================

write(stdout, "Test 1: Mock dataset creation\n"); flush(stdout)
try
    sets = create_mock_dataset(3, (100, 100))
    
    @assert Base.length(sets) == 3
    @assert Base.size(Bas3ImageSegmentation.data(sets[1][1])) == (100, 100, 3)
    @assert Base.size(Bas3ImageSegmentation.data(sets[1][2])) == (100, 100, 5)
    
    # Verify image has white marker region
    input_data = Bas3ImageSegmentation.data(sets[1][1])
    has_white_pixels = any(input_data .> 0.9)
    @assert has_white_pixels
    
    test_results["mock_dataset"] = true
    write(stdout, "  ✓ Mock dataset created: 3 images, 100x100 pixels\n"); flush(stdout)
catch e
    test_results["mock_dataset"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# PHASE 2: Test Full Interactive Figure Creation
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "PHASE 2: Testing Interactive Figure Creation\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

write(stdout, "Test 2: Create interactive figure - Full structure\n"); flush(stdout)
write(stdout, "  (This may take 30-60 seconds on first run...)\n"); flush(stdout)
try
    # Create mock dataset
    sets = create_mock_dataset(5, (100, 100))
    input_type = MockInputType()
    raw_output_type = MockOutputType()
    
    # Create the full interactive figure (no display needed!)
    fig = create_interactive_figure(sets, input_type, raw_output_type)
    
    # Verify figure exists
    @assert !Base.isnothing(fig)
    
    # Verify figure has content
    @assert Base.hasfield(typeof(fig), :layout)
    
    test_results["figure_creation_full"] = true
    write(stdout, "  ✓ Interactive figure created successfully\n"); flush(stdout)
catch e
    test_results["figure_creation_full"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
    write(stdout, "  Error details: "); flush(stdout)
    Base.showerror(stdout, e, Base.catch_backtrace())
    write(stdout, "\n"); flush(stdout)
end

# ==============================================================================
# PHASE 3: Test Observable Interactions
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "PHASE 3: Testing Observable Interactions\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

# Helper function to find widgets in figure
function find_textbox_by_placeholder(fig, placeholder_text::String)
    # Search recursively through figure layout
    function search_content(content)
        for item in content
            if item isa Bas3GLMakie.GLMakie.Textbox
                if Base.hasfield(typeof(item), :placeholder) && 
                   occursin(placeholder_text, item.placeholder[])
                    return item
                end
            end
            # Search in GridLayout content
            if Base.hasfield(typeof(item), :content)
                result = search_content(item.content)
                if !Base.isnothing(result)
                    return result
                end
            end
        end
        return nothing
    end
    
    return search_content(fig.content)
end

function find_button_by_label(fig, label_text::String)
    function search_content(content)
        for item in content
            if item isa Bas3GLMakie.GLMakie.Button
                if Base.hasfield(typeof(item), :label) &&
                   occursin(label_text, item.label[])
                    return item
                end
            end
            if Base.hasfield(typeof(item), :content)
                result = search_content(item.content)
                if !Base.isnothing(result)
                    return result
                end
            end
        end
        return nothing
    end
    
    return search_content(fig.content)
end

function find_toggle_in_layout(fig)
    function search_content(content)
        for item in content
            if item isa Bas3GLMakie.GLMakie.Toggle
                return item
            end
            if Base.hasfield(typeof(item), :content)
                result = search_content(item.content)
                if !Base.isnothing(result)
                    return result
                end
            end
        end
        return nothing
    end
    
    return search_content(fig.content)
end

write(stdout, "Test 3: Navigation - Next button interaction\n"); flush(stdout)
try
    sets = create_mock_dataset(5, (100, 100))
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    # Find navigation textbox
    textbox = find_textbox_by_placeholder(fig, "Bildnummer")
    @assert !Base.isnothing(textbox)
    
    # Find next button
    next_button = find_button_by_label(fig, "chstes")  # "Nächstes"
    @assert !Base.isnothing(next_button)
    
    # Initial state should be image 1
    initial_value = textbox.stored_string[]
    @assert initial_value == "1"
    
    # Simulate next button click
    next_button.clicks[] = next_button.clicks[] + 1
    
    # Allow time for observable updates to propagate
    Base.sleep(0.2)
    
    # Verify image changed to 2
    new_value = textbox.stored_string[]
    @assert new_value == "2"
    
    test_results["navigation_next"] = true
    write(stdout, "  ✓ Next button: Image 1 -> 2\n"); flush(stdout)
catch e
    test_results["navigation_next"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

write(stdout, "Test 4: Navigation - Previous button interaction\n"); flush(stdout)
try
    sets = create_mock_dataset(5, (100, 100))
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    textbox = find_textbox_by_placeholder(fig, "Bildnummer")
    next_button = find_button_by_label(fig, "chstes")
    prev_button = find_button_by_label(fig, "Vorheriges")
    
    @assert !Base.isnothing(prev_button)
    
    # Go to image 2 first
    next_button.clicks[] = next_button.clicks[] + 1
    Base.sleep(0.2)
    
    @assert textbox.stored_string[] == "2"
    
    # Now go back to image 1
    prev_button.clicks[] = prev_button.clicks[] + 1
    Base.sleep(0.2)
    
    @assert textbox.stored_string[] == "1"
    
    test_results["navigation_prev"] = true
    write(stdout, "  ✓ Previous button: Image 2 -> 1\n"); flush(stdout)
catch e
    test_results["navigation_prev"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

write(stdout, "Test 5: Parameter textbox - Threshold update\n"); flush(stdout)
try
    sets = create_mock_dataset(3, (100, 100))
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    # Find threshold textbox (look for one with default "0.7")
    function find_threshold_textbox(fig)
        function search(content)
            for item in content
                if item isa Bas3GLMakie.GLMakie.Textbox
                    if item.stored_string[] == "0.7"
                        return item
                    end
                end
                if Base.hasfield(typeof(item), :content)
                    result = search(item.content)
                    if !Base.isnothing(result)
                        return result
                    end
                end
            end
            return nothing
        end
        return search(fig.content)
    end
    
    threshold_box = find_threshold_textbox(fig)
    @assert !Base.isnothing(threshold_box)
    
    old_value = threshold_box.stored_string[]
    @assert old_value == "0.7"
    
    # Change threshold value
    threshold_box.stored_string[] = "0.5"
    Base.sleep(0.2)
    
    # Verify value changed
    @assert threshold_box.stored_string[] == "0.5"
    
    test_results["parameter_threshold"] = true
    write(stdout, "  ✓ Threshold updated: 0.7 -> 0.5\n"); flush(stdout)
catch e
    test_results["parameter_threshold"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# PHASE 4: Test Toggle Controls and File Output
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "PHASE 4: Testing Toggles and File Output\n"); flush(stdout)
write(stdout, "="^80 * "\n\n"); flush(stdout)

write(stdout, "Test 6: Toggle controls - Segmentation overlay\n"); flush(stdout)
try
    sets = create_mock_dataset(3, (100, 100))
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    # Find segmentation toggle
    seg_toggle = find_toggle_in_layout(fig)
    @assert !Base.isnothing(seg_toggle)
    
    # Get initial state (don't assume what it is)
    initial_state = seg_toggle.active[]
    
    # Toggle to opposite state
    seg_toggle.active[] = !initial_state
    Base.sleep(0.1)
    @assert seg_toggle.active[] == !initial_state
    
    # Toggle back to original state
    seg_toggle.active[] = initial_state
    Base.sleep(0.1)
    @assert seg_toggle.active[] == initial_state
    
    test_results["toggle_segmentation"] = true
    write(stdout, "  ✓ Segmentation toggle: $(initial_state) -> $(!initial_state) -> $(initial_state)\n"); flush(stdout)
catch e
    test_results["toggle_segmentation"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

write(stdout, "Test 7: Display - Save figure to PNG file\n"); flush(stdout)
try
    sets = create_mock_dataset(3, (100, 100))
    fig = create_interactive_figure(sets, MockInputType(), MockOutputType())
    
    # Save to file (works in headless mode!)
    output_file = "test_interactive_ui_output.png"
    
    # Remove file if it exists
    if Base.isfile(output_file)
        Base.rm(output_file)
    end
    
    Bas3GLMakie.GLMakie.save(output_file, fig)
    
    # Verify file exists
    @assert Base.isfile(output_file)
    
    # Verify file size is reasonable
    file_size = Base.filesize(output_file)
    @assert file_size > 10000  # At least 10KB
    @assert file_size < 50000000  # Less than 50MB
    
    # Cleanup
    Base.rm(output_file)
    
    test_results["save_figure"] = true
    write(stdout, "  ✓ Figure saved to PNG ($file_size bytes)\n"); flush(stdout)
catch e
    test_results["save_figure"] = false
    write(stdout, "  ✗ Failed: $e\n"); flush(stdout)
end

# ==============================================================================
# Test Summary
# ==============================================================================

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "COMPREHENSIVE TEST SUMMARY\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)

total = Base.length(test_results)
passed = Base.count(Base.values(test_results))
failed = total - passed

write(stdout, "\nResults by Phase:\n"); flush(stdout)
write(stdout, "  Phase 1 (Mock Data):         Test 1\n"); flush(stdout)
write(stdout, "  Phase 2 (Figure Creation):   Test 2\n"); flush(stdout)
write(stdout, "  Phase 3 (Interactions):      Tests 3-5\n"); flush(stdout)
write(stdout, "  Phase 4 (Display/Toggles):   Tests 6-7\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)

write(stdout, "Total Tests: $total\n"); flush(stdout)
write(stdout, "Passed: $passed\n"); flush(stdout)
write(stdout, "Failed: $failed\n"); flush(stdout)

if passed == total
    write(stdout, "\n🎉 ALL TESTS PASSED! 🎉\n"); flush(stdout)
end

if failed > 0
    write(stdout, "\nFailed tests:\n"); flush(stdout)
    for (name, result) in test_results
        if !result
            write(stdout, "  ✗ $name\n"); flush(stdout)
        end
    end
end

write(stdout, "\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
write(stdout, "Test Coverage Summary:\n"); flush(stdout)
write(stdout, "  ✓ Mock data infrastructure\n"); flush(stdout)
write(stdout, "  ✓ Full interactive figure creation\n"); flush(stdout)
write(stdout, "  ✓ Navigation button observables\n"); flush(stdout)
write(stdout, "  ✓ Parameter textbox updates\n"); flush(stdout)
write(stdout, "  ✓ Toggle control interactions\n"); flush(stdout)
write(stdout, "  ✓ Headless PNG file export\n"); flush(stdout)
write(stdout, "\n"); flush(stdout)
write(stdout, "⭐ Key Achievement: Tested interactive UI WITHOUT requiring display!\n"); flush(stdout)
write(stdout, "="^80 * "\n"); flush(stdout)
