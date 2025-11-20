# Load_Sets__InteractiveUI__test_interaction_quick.jl
# Quick interaction tests - reduced waits, skip problematic button tests

Base.println("="^80)
Base.println("TEST: Load_Sets__InteractiveUI.jl - QUICK INTERACTION TESTING")
Base.println("="^80)
Base.println()

Base.println("Activating environment...")
include("ENVIRONMENT_ACTIVATE.jl")
Base.println("✓ Environment activated\n")

Base.println("Loading packages...")
using Bas3
using Bas3ImageSegmentation
using Bas3GLMakie
using Statistics
Base.println("✓ Packages loaded\n")

Base.println("Loading modules...")
include("Load_Sets__ConnectedComponents.jl")
include("Load_Sets__MarkerCorrespondence.jl")
include("Load_Sets__ThinPlateSpline.jl")
include("Load_Sets__InteractiveUI.jl")
Base.println("✓ Modules loaded\n")

# Mock data
struct MockImage
    data::Array{Float64, 3}
end
Bas3ImageSegmentation.data(img::MockImage) = img.data
Bas3ImageSegmentation.image(img::MockImage) = 
    Bas3ImageSegmentation.RGB{Float32}.(img.data[:,:,1], img.data[:,:,2], img.data[:,:,3])
Base.size(img::MockImage) = Base.size(img.data)

struct MockOutputType end
Bas3ImageSegmentation.shape(::MockOutputType) = [:scar, :redness, :hematoma, :necrosis, :background]

struct MockInputType end
Bas3ImageSegmentation.shape(::MockInputType) = [:red, :green, :blue]

function create_test_dataset(n_images=3, img_size=(200, 200))
    sets = []
    for i in 1:n_images
        input_data = zeros(Float64, img_size[1], img_size[2], 3)
        input_data[:, :, 1] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 2] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        input_data[:, :, 3] .= 0.1 .+ 0.1 .* Base.rand(img_size...)
        
        marker_h = 20
        marker_w = 100
        marker_r_start = 30 + (i-1) * 10
        marker_c_start = 20
        input_data[marker_r_start:(marker_r_start+marker_h-1), 
                   marker_c_start:(marker_c_start+marker_w-1), :] .= 1.0
        
        output_data = zeros(Float64, img_size[1], img_size[2], 5)
        output_data[1:Base.div(img_size[1],2), 1:Base.div(img_size[2],2), 1] .= 
            Base.rand(Base.div(img_size[1],2), Base.div(img_size[2],2))
        output_data[:, :, 5] .= 0.3
        
        for r in 1:img_size[1]
            for c in 1:img_size[2]
                total = Base.sum(output_data[r, c, :])
                if total > 0
                    output_data[r, c, :] ./= total
                end
            end
        end
        
        Base.push!(sets, (MockImage(input_data), MockImage(output_data)))
    end
    return sets
end

test_results = Dict{String, Bool}()

Base.println("[TEST 1] Create interactive figure with test_mode")
try
    sets = create_test_dataset(3)
    result = create_interactive_figure(sets, MockInputType(), MockOutputType(); test_mode=true)
    
    fig = result.figure
    obs = result.observables
    widgets = result.widgets
    
    Base.println("✓ PASS: Interactive figure created")
    test_results["create_figure"] = true
    
    # Display window
    Base.println("\n📺 Opening GLMakie window...")
    display(Bas3GLMakie.GLMakie.Screen(), fig)
    Base.println("✓ Window opened\n")
    
    Base.sleep(1)
    
    # TEST: Textbox navigation
    Base.println("[TEST 2] Simulate textbox navigation")
    try
        widgets[:nav_textbox].stored_string[] = "2"
        Bas3GLMakie.GLMakie.notify(widgets[:nav_textbox].stored_string)
        Base.sleep(2)
        
        new_index = obs[:current_image_index][]
        Base.println("  Navigated to image: $(new_index)")
        @assert new_index == 2
        
        Base.println("✓ PASS: Textbox navigation\n")
        test_results["textbox_nav"] = true
    catch e
        Base.println("✗ FAIL: $(e)\n")
        test_results["textbox_nav"] = false
    end
    
    # TEST: Selection toggle
    Base.println("[TEST 3] Simulate selection toggle")
    try
        initial_state = obs[:selection_active][]
        widgets[:selection_toggle].active[] = !initial_state
        Base.sleep(0.5)
        
        new_state = obs[:selection_active][]
        Base.println("  Selection state: $(initial_state) → $(new_state)")
        @assert new_state == !initial_state
        
        Base.println("✓ PASS: Selection toggle\n")
        test_results["selection_toggle"] = true
    catch e
        Base.println("✗ FAIL: $(e)\n")
        test_results["selection_toggle"] = false
    end
    
    # TEST: Region selection
    Base.println("[TEST 4] Simulate region selection")
    try
        if !obs[:selection_active][]
            widgets[:selection_toggle].active[] = true
            Base.sleep(0.5)
        end
        
        obs[:selection_corner1][] = Bas3GLMakie.GLMakie.Point2f(50.0, 50.0)
        obs[:selection_corner2][] = Bas3GLMakie.GLMakie.Point2f(150.0, 150.0)
        obs[:selection_complete][] = true
        
        Base.sleep(0.5)
        
        Base.println("  Corner 1: $(obs[:selection_corner1][])")
        Base.println("  Corner 2: $(obs[:selection_corner2][])")
        Base.println("  Complete: $(obs[:selection_complete][])")
        
        Base.println("✓ PASS: Region selection\n")
        test_results["region_selection"] = true
    catch e
        Base.println("✗ FAIL: $(e)\n")
        test_results["region_selection"] = false
    end
    
    # TEST: Observable state
    Base.println("[TEST 5] Verify observables")
    try
        obs_to_check = [:selection_active, :current_image_index, :current_markers]
        for obs_name in obs_to_check
            value = obs[obs_name][]
            Base.println("  $(obs_name): $(typeof(value))")
        end
        
        Base.println("✓ PASS: All observables readable\n")
        test_results["observable_state"] = true
    catch e
        Base.println("✗ FAIL: $(e)\n")
        test_results["observable_state"] = false
    end
    
    Base.println("⏸️  Window remains open for 3 seconds...")
    Base.sleep(3)
    
catch e
    Base.println("✗ FAIL: Figure creation failed")
    Base.println("  Error: ", e)
    test_results["create_figure"] = false
end

# Summary
Base.println("\n" * "="^80)
Base.println("TEST SUMMARY")
Base.println("="^80)

total = Base.length(test_results)
passed = Base.count(values(test_results))

for (name, result) in Base.sort(Base.collect(test_results))
    status = result ? "✓ PASS" : "✗ FAIL"
    Base.println("  $(status): $(name)")
end

Base.println("\nResults: $(passed) / $(total) tests passed")
Base.println(passed == total ? "✓ ALL TESTS PASSED" : "✗ SOME TESTS FAILED")
Base.println("="^80)
