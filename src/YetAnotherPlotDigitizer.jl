module YetAnotherPlotDigitizer

using GLMakie
import GLMakie.GLFW
using LinearAlgebra 
using StaticArrays 
using Observables
using FileIO
using Colors


# include("bezier.jl")


export main

function main(;
        num_colors = 8,
        color_btn_height = 30,
        num_color_cols = 4,
        sidebar_width = 200,
        PICK_THRESHOLD = 20,
        )

    #######GLOBALS###########################
    
    Ring = BezierPath([
            MoveTo(Point(1, 0)),
            EllipticalArc(Point(0, 0), 1, 1, 0, 0, 2pi),
            MoveTo(Point(0.75, 0.0)),
            EllipticalArc(Point(0, 0), 0.9, 0.9, 0, 0, -2pi),
            ClosePath(),
            MoveTo(0.1, 1.75),
            LineTo(-0.1, 1.75),
            LineTo(-0.1, -1.75),
            LineTo(0.1, -1.75),
            ClosePath(),
                    ])

    cmap = distinguishable_colors(num_colors, rand(RGB)) #color map for curves

    current_color = Observable(first(cmap)) 

    is_colorgrid_visible = Observable(false)

    ref_img = Observable{Any}(fill(RGB(0.1, 0.1, 0.1), 100, 100))
    
    current_curve = Observable(Point2f[])
    
    #to be placed by user
    X1 = Point2f(10,10)
    X2 = Point2f(90,10)
    Y1 = Point2f(50, 10)
    Y2 = Point2f(50, 90)
    scale_rect = Observable([X1, X2, Y1, Y2])
    
    dragged_index = Observable{Union{Nothing, Int}}(nothing)
    #######Layout#############################


    fig = Figure()
    # inspector = fig.scene.events.inspector
    # inspector.range[] = PICK_THRESHOLD


    ax_img = Axis(fig[1,1], aspect = DataAspect())
    deregister_interaction!(ax_img, :rectanglezoom)

    color_grid = fig[1,2] = GridLayout(width = sidebar_width, tellheight = false)

    hidden_layout = GridLayout(bbox = (-200, -100, 0, 100))

    ####color menu#########
    
    menu_container = color_grid[1,1] = GridLayout()
    btn_color = Button(fig,
                        label = "Choose color",
                        height = color_btn_height,
                        )

    color_option_grid = GridLayout()
    color_option_grid.tellheight = false
    color_option_grid.tellwidth = false

    empty_layout = GridLayout()

    menu_container[1, 1] = hgrid!(btn_color, Box(fig, color = current_color))



    ##########################################################
    img_plot = image!(ax_img, ref_img)
    scaling_pts = (scatter!(ax_img, scale_rect, color = [:red, :red, :green, :green], 
                                marker = Ring,
                                markersize = 20,
                                rotation = [0, 0, pi/2, pi/2]),

    text!(ax_img, scale_rect; text =["X1", "X2", "Y1", "Y2"],
                        color = [:red, :red, :green, :green],
                        # color = :black,
                        fontsize = PICK_THRESHOLD,
                        offset = (PICK_THRESHOLD, PICK_THRESHOLD)
                        )
    )
    
    ########EVENTS###########################################
    
    on(is_colorgrid_visible) do val
        if val
            menu_container[2, 1] = color_option_grid
            hidden_layout[1,1] = empty_layout
        else
            menu_container[2, 1] = empty_layout
            hidden_layout[1,1] = color_option_grid
        end
    end

    on(btn_color.clicks) do _
        is_colorgrid_visible[] = true
    end


    on(events(fig).dropped_files) do files
        isempty(files) && return nothing
        
        f1 = first(files)
        println(f1)
        try
            ref_img[] = rotr90(load(f1))
            #  
            reset_plot!(ax_img)
            
        catch e
            @info "Triggered"
            
        end
        
    end

    #####################MOUSE Interaction#########################################

    # Interaction for pressing the mouse button
    on(events(fig).mousebutton, priority = 10) do event
        # Only react to left mouse button press
        if event.button == Mouse.left && event.action == Mouse.press
            # Pick the closest control point on the scatter plot
            # `pick` returns the plot object and the index of the picked element
            plot, index = pick(ax_img.scene, events(ax_img).mouseposition[], PICK_THRESHOLD)
            # @info plot
            # Check if a control point was picked
            if plot === scaling_pts[1] && index !== nothing
                dragged_index[] = index
                # Consume the event so the default interaction (e.g., pan) doesn't run
                return Consume(true) 
            end
        end
        return Consume(false)
    end

    # Interaction for mouse movement (dragging)
    on(events(fig).mouseposition, priority = 10) do mp
        if dragged_index[] !== nothing && ispressed(fig, Mouse.left)
            # Convert mouse position (in pixels) to data coordinates
            
            # dragged_index[] == 1 && return Consume(true) #fixed 1st point
            new_data_pos = Makie.mouseposition(ax_img.scene)
            
            # Update the specific control point's position
            current_points = scale_rect[]
            current_points[dragged_index[]] = new_data_pos
            scale_rect[] = current_points # Notify the Observable of the change
            
            # Consume the event to prevent other interactions from running
            return Consume(true)
        end
        return Consume(false)
    end

    # Interaction for releasing the mouse button
    on(events(fig).mousebutton, priority = 10) do event
        if event.button == Mouse.left && event.action == Mouse.release
            # Stop dragging
            dragged_index[] = nothing
            return Consume(true)
        end
        return Consume(false)
    end


    #######################
    
    menu_container[2,1] = empty_layout
    hidden_layout[1,1] = color_option_grid

    populate_dropdown(fig,
                      color_option_grid, 
                      cmap, 
                      current_color, 
                      is_colorgrid_visible; 
                      btn_height = color_btn_height,
                      num_color_cols,
                      btn_width = 0.7*(sidebar_width / num_color_cols),
                      )

    

    return fig
end



function populate_dropdown(fig::Figure, grid::GridLayout, 
                            colormap_entries, 
                            current_color::Observable, 
                            is_open:: Observable;
                            btn_height = 30,
                            num_color_cols = 4,
                            btn_width = 30,
                            )
    

    num_colors = length(colormap_entries)
    num_rows = ceil(Int, num_colors / num_color_cols)
    num_matrix = num_rows * num_color_cols
    entry_matrix = reshape(1:num_matrix, num_rows, num_color_cols)

    R = CartesianIndices(entry_matrix)
    for i in 1:num_colors
        j, k = Tuple(R[i])
        entry = colormap_entries[i]
        # Create a Button for each entry
        btn = grid[j, k] = Button(fig, 
            label = "", #no label
            # Customize the appearance with a colored Box
            buttoncolor = entry, 
            height = btn_height,
            width = btn_width,
        )
        
        # When a button is clicked, update the selected color and close the dropdown
        on(btn.clicks) do _
            current_color[] = entry
            is_open[] = false
        end
    end
    
    # Ensure the grid is positioned correctly over the main figure
    rowgap!(grid, 1) # Reduce gap between color rows
    
    return
end


function reset_plot!(ax::Axis, delete_plots= nothing::Union{Nothing, Vector{Plot}})

    
    
    !isnothing(delete_plots) && delete!(ax, delete_plots)

    
    reset_limits!(ax)
    
end


end # module YetAnotherPlotDigitizer
