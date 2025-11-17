module Bas3GLMakie_Bas3ImageSegmentation
    using Bas3ImageSegmentation
    using Bas3ImageSegmentation.Bas3
    using Bas3ImageSegmentation.Distributed

    import Bas3.size
    import Bas3.length
    import Bas3.minimum
    import Bas3.maximum #TODO make a using macro for this

    using Bas3Plots
    import Bas3Plots.display
    import Bas3Plots.notify
    
    using Bas3GLMakie
    using Bas3Observables

    #=
    using GLMakie

    fig = Figure()

    ax = Axis(fig[1, 1])
    fig[2, 1] = buttongrid = GridLayout(tellwidth = false)

    counts = Observable([1, 4, 3, 7, 2])

    buttonlabels = [lift(x -> "Count: $(x[i])", counts) for i in 1:5]

    buttons = buttongrid[1, 1:5] = [Button(fig, label = l) for l in buttonlabels]

    for i in 1:5
        on(buttons[i].clicks) do n
            counts[][i] += 1
            notify(counts)
        end
    end

    barplot!(counts, color = cgrad(:Spectral)[LinRange(0, 1, 5)])
    ylims!(ax, 0, 20)

    fig
    =#^
    #=
        @__(function Bas3Plots.c__Plot(
            _plot,
            ::typeof(Bas3ImageSegmentation.neuralnetwork_workload);
            input::v__Type{<: Bas3ImageSegmentation.v__Image_Data},
            output::v__Type{<: Bas3ImageSegmentation.v__Image_Data},
            show_window = true
        )
        =#
    const plot_initialize_flag = 3
    const plot_active_flag = 1
    const plot_inactive_flag = 2
    const plot_hidden_flag = 0
    @__(function Bas3Plots.c__Plot(
        _plot,
        ::typeof(Bas3ImageSegmentation.neuralnetwork_workload);
        input::v__Type{input_type},
        output::v__Type{output_type},
        show_window=false
    ) where {
        input_type<:u__{v__Image_Data,c__Image_Data},
        output_type<:u__{v__Image_Data,c__Image_Data}
    }
        text = function _text(flag)
            if flag == plot_hidden_flag
                return "Image Window (Hidden)"
            elseif flag == plot_active_flag
                return "Image Window (Active)"
            elseif flag == plot_inactive_flag
                return "Image Window (Inactive)"
            end
        end
        label = Bas3GLMakie.GLMakie.Observable(text(show_window))
        button = Bas3GLMakie.GLMakie.Button(
            _plot;
            label=label
        )
        flag = Ref{Int64}(plot_hidden_flag)
        array_type = Array{v_RGB,2}
        observable_type = Bas3GLMakie.GLMakie.Observable{array_type}
        observables = (
            observable_type(array_type(undef, 8, 8)),
            observable_type(array_type(undef, 8, 8)),
            observable_type(array_type(undef, 8, 8)),
        )
        function _on_click(clicks)
            if flag[] == plot_hidden_flag

                flag[] = plot_initialize_flag
                image_figure = Bas3GLMakie.Figure()
                observables[1][] = array_type(undef, 512, 512)
                observables[2][] = array_type(undef, 512, 512)
                observables[3][] = array_type(undef, 512, 512)
                for (index, title) in ((1, "input"), (2, "output reference"), (3, "output predicted"))
                    image_axis = Bas3GLMakie.GLMakie.Axis(
                        image_figure[1, index];
                        title,
                        aspect=Bas3GLMakie.GLMakie.DataAspect()
                    )
                    Bas3GLMakie.GLMakie.image!(
                        image_axis,
                        observables[index];
                    )
                end
                display(Bas3GLMakie.GLMakie.Screen(), image_figure)
                flag[] = plot_active_flag
                label[] = text(plot_active_flag)
            elseif flag[] == plot_active_flag
                label[] = text(plot_inactive_flag)
                flag[] = plot_inactive_flag
            elseif flag[] == plot_inactive_flag
                label[] = text(plot_active_flag)
                flag[] = plot_active_flag
            end
        end
        if show_window == true
            _on_click(button.clicks)
        end
        on(_on_click, button.clicks)
        #=
        channel_button = Bas3GLMakie.GLMakie.Button(
            layout[2, 1];
            label="Channel Window"
        )
        error_button = Bas3GLMakie.GLMakie.Button(
            layout[3, 1];
            label="Error Window"
        )
        performance_button = Bas3GLMakie.GLMakie.Button(
            layout[4, 1];
            label="Performance Window"
        )
        =#

        #index = 0
        return v__Update_Plot(
            @__(function _update_handler(observables; input, output, keywords...)
                    if flag[] == plot_active_flag
                        observables[1][] = image(input)
                        observables[2][] = image(output.reference)
                        observables[3][] = image(output.predicted)
                    end
                end; Transform=false),
            observables
        )
    end)#; const SolLayout = c__Solver_Layout
    @__(function Bas3Plots.c__Plot(
        _plot,
        ::typeof(Bas3ImageSegmentation.neuralnetwork_workload);
        error_metric::metrics_type,
        show_window = false
    ) where {
        metrics_type<:v__Tuple
    }
        text = function _text(flag)
            if flag == plot_hidden_flag
                return "Error Window (Hidden)"
            elseif flag == plot_active_flag
                return "Error Window (Active)"
            elseif flag == plot_inactive_flag
                return "Error Window (Inactive)"
            end
        end
        label = Bas3GLMakie.GLMakie.Observable(text(show_window))
        button = Bas3GLMakie.GLMakie.Button(
            _plot;
            label=label
        )
        flag = Ref{Int64}(plot_hidden_flag)
        array_type = Array{Bas3GLMakie.GLMakie.Point2f,1}
        observable_type = Bas3GLMakie.GLMakie.Observable{array_type}
        observables = (
            observable_type(array_type()),
            observable_type(array_type()),
            Ref{Any}()
        )
        function _on_click(clicks)
            if flag[] == plot_hidden_flag
                flag[] = plot_initialize_flag
                metrics_figure = Bas3GLMakie.Figure()
                metrics_axis = Bas3GLMakie.GLMakie.Axis(
                    metrics_figure[1, 1];
                    title="Error over Observations"
                )
                Bas3GLMakie.GLMakie.scatter!(
                    metrics_axis,
                    observables[1];
                    color=Bas3GLMakie.GLMakie.RGBA(1.0, 0.0, 0.0, 0.5),
                    markersize=5
                )
                Bas3GLMakie.GLMakie.lines!(
                    metrics_axis,
                    observables[1];
                    color=Bas3GLMakie.GLMakie.RGBA(1.0, 0.0, 0.0, 0.5),
                    linewidth=2
                )
                observables[3][] = metrics_axis
                display(Bas3GLMakie.GLMakie.Screen(), metrics_figure)
                label[] = text(1)
                flag[] = plot_active_flag
            elseif flag[] == plot_active_flag
                label[] = text(2)
                flag[] = plot_inactive_flag
            elseif flag[] == plot_inactive_flag
                label[] = text(plot_active_flag)
                flag[] = plot_active_flag
            end
        end
        if show_window == true
            _on_click(button.clicks)
        end
        on(_on_click, button.clicks)
        return v__Update_Plot(
            @__(function _update_handler(observables; observation, error, keywords...)
                    #println("CALL: _update_handler(observables; observation, error, keywords...)")
                    if flag[] == plot_active_flag
                        observables[1][] = Bas3GLMakie.GLMakie.Point2f.(observation, error)
                        Bas3GLMakie.GLMakie.autolimits!(observables[3][])
                    end
                end; Transform=false),
            observables
        )
    end)
    @__(function Bas3Plots.c__Plot(
        _plot,
        ::typeof(Bas3ImageSegmentation.neuralnetwork_workload);
        performance_metric::metrics_type,
        show_window = false
    ) where {
        metrics_type<:v__Tuple
    }
        text = function _text(flag)
            if flag == plot_hidden_flag
                return "Performance Window (Hidden)"
            elseif flag == plot_active_flag
                return "Performance Window (Active)"
            elseif flag == plot_inactive_flag
                return "Performance Window (Inactive)"
            end
        end
        label = Bas3GLMakie.GLMakie.Observable(text(show_window))
        button = Bas3GLMakie.GLMakie.Button(
            _plot;
            label=label
        )
        flag = Ref{Int64}(plot_hidden_flag)
        array_type = Array{Bas3GLMakie.GLMakie.Point2f,1}
        observable_type = Bas3GLMakie.GLMakie.Observable{array_type}
        observables = (
            observable_type(array_type()),
            observable_type(array_type()),
            Ref{Any}()
        )
        function _on_click(clicks)
            if flag[] == plot_hidden_flag
                flag[] = plot_initialize_flag
                performance_figure = Bas3GLMakie.Figure()
                performance_axis = Bas3GLMakie.GLMakie.Axis(
                    performance_figure[1, 1];
                    title="Performance over Observations"
                )
                Bas3GLMakie.GLMakie.scatter!(
                    performance_axis,
                    observables[1];
                    color=Bas3GLMakie.GLMakie.RGBA(0.0, 1.0, 0.0, 0.5),
                    markersize=5
                )
                Bas3GLMakie.GLMakie.lines!(
                    performance_axis,
                    observables[1];
                    color=Bas3GLMakie.GLMakie.RGBA(0.0, 1.0, 0.0, 0.5),
                    linewidth=2
                )
                observables[3][] = performance_axis
                display(Bas3GLMakie.GLMakie.Screen(), performance_figure)
                label[] = text(plot_active_flag)
                flag[] = plot_active_flag
            elseif flag[] == plot_active_flag
                label[] = text(plot_inactive_flag)
                flag[] = plot_inactive_flag
            elseif flag[] == plot_inactive_flag
                label[] = text(plot_active_flag)
                flag[] = plot_active_flag
            end
        end
        if show_window == true
            _on_click(button.clicks)
        end
        on(_on_click, button.clicks)
        return v__Update_Plot(
            @__(function _update_handler(observables; observation, absolute_performance, keywords...)
                    #println("CALL: _update_handler(observables; observation, absolute_performance, keywords...)")
                    if flag[] == plot_active_flag
                        observables[1][] = Bas3GLMakie.GLMakie.Point2f.(observation, absolute_performance)
                        Bas3GLMakie.GLMakie.autolimits!(observables[3][])
                    end
                end; Transform=false),
            observables
        )
    end)
end