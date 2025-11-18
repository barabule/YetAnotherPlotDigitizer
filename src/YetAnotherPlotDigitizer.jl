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
        bottombar_height = 100,
        PICK_THRESHOLD = 20,
        )

    #######GLOBALS###########################
    
    ###markers for the scaling range selection
    # a ring with a vertical bar 
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

    #colors
    cmap = distinguishable_colors(num_colors, rand(RGB)) #color map for curves
    current_color = Observable(first(cmap)) 

    is_colorgrid_visible = Observable(false)


    #this is the reference image which is "digitized"
    ref_img = Observable{Any}(fill(RGB(0.1, 0.1, 0.1), 100, 100))
    
    #the current active curve
    current_curve = Observable(Point2f[])
    ALL_CURVES = Vector{Any}() #holds all the curves

    #scaling range markers
    X1 = Point2f(10,10)
    X2 = Point2f(90,10)
    Y1 = Point2f(50, 10)
    Y2 = Point2f(50, 90)
    scale_rect = Observable([X1, X2, Y1, Y2])
    scale_type = Observable([:linear, :linear])

    #xrange, yrange
    plot_range = Observable([0.0, 1.0, 0.0, 1.0])


    #currently dragged point (scale range or curve)
    dragged_index = Observable{Union{Nothing, Int}}(nothing)


    #######LAYOUT#############################


    fig = Figure()
    
    ax_img = Axis(fig[1,1], aspect = DataAspect())
    deregister_interaction!(ax_img, :rectanglezoom) #just gets in the way when dragging

    SIDEBAR = GridLayout(fig[1,2], width = sidebar_width, tellheight = false)

    SCALE_GL = GridLayout(SIDEBAR[1,1], width = sidebar_width) #range scaling
    ALL_CURVES_GL = GridLayout(SIDEBAR[2,1], width = sidebar_width) #menu to select the current curve
    CURRENT_CURVE_GL = GridLayout(SIDEBAR[3,1], width = sidebar_width) #holds settings for the current curve
    
    CC_COLOR_GL = GridLayout(SIDEBAR[4, 1]) #shows a grid of colors
    empty_layout = GridLayout()
    color_option_grid = GridLayout()
    HIDDEN_GL = GridLayout(bbox = (-200, -100, 0, 100)) #used to swap the color buttons when "hidden"
    
    BOTTOMBAR = GridLayout(fig[2,1], tellwidth =false, height = bottombar_height)#other stuff?

    
    

    #################### SCALE / GLOBAL ##############################################################################


    tbscale = [Textbox(fig, width = sidebar_width/3, validator = Float64) for _ in 1:4]
    cblogx = Checkbox(fig, checked=false)
    cblogy = Checkbox(fig, checked=false)
    SCALE_GL[1,1] = Label(fig, "Scale")
    SCALE_GL[2,1] = vgrid!(
                    hgrid!(Label(fig, "X1:"), tbscale[1]),
                    hgrid!(Label(fig, "X2:"), tbscale[2]),
                    # hgrid!(Label(fig, "log"), cblogx),
                    hgrid!(Label(fig, "Y1:"), tbscale[3]),
                    hgrid!(Label(fig, "Y2:"), tbscale[4]),
                    # hgrid!(Label(fig, "log"), cblogy),
                                )


    #############ALL CURVES##########################################################################################

    menu_curves = Menu(fig, options = [("Curve 01", 1)],
                        default = "Curve 01", 
                        width = 0.5 * sidebar_width
                        )
    ALL_CURVES_GL[1, 1] = vgrid!(
                        hgrid!(Label(fig, "Curve: "), menu_curves),
    )


    # ###############CURVE##############################################################################################

    tb_curve_name = Textbox(fig, placeholder = "Curve 01")

    btn_add_curve = Button(fig, label = "Add")

    CURRENT_CURVE_GL[1, 1] =vgrid!(
                    Label(fig, "Current curve"),
                    hgrid!(Label(fig, "Name"), tb_curve_name),
                    btn_add_curve,
    )

    #####COLOR GRID

    btn_color = Button(fig,
                        label = "Color",
                        height = color_btn_height,
                        )

    CURRENT_CURVE_GL[2,1] = btn_color
    CC_COLOR_GL[1,1] = empty_layout

    HIDDEN_GL[1,1] = color_option_grid
    populate_dropdown(fig,
                      color_option_grid, 
                      cmap, 
                      current_color, 
                      is_colorgrid_visible; 
                      btn_height = color_btn_height,
                      num_color_cols,
                      btn_width = 0.7*(sidebar_width / num_color_cols),
                      )

    
    

    

    ##########################################################

    img_plot = image!(ax_img, ref_img)
    scaling_pts = (scatter!(ax_img, scale_rect, color = [:red, :red, :green, :green], 
                                marker = Ring,
                                markersize = PICK_THRESHOLD/2,
                                rotation = [0, 0, pi/2, pi/2]),

    text!(ax_img, scale_rect; text =["X1", "X2", "Y1", "Y2"],
                        color = [:red, :red, :green, :green],
                        # color = :black,
                        fontsize = PICK_THRESHOLD/2,
                        offset = (PICK_THRESHOLD/2, PICK_THRESHOLD/2)
                        )
    )
    

    #############BOTTOM######################################

    BOTTOMBAR[1,1] = hgrid!(
                Label(fig, "X logscale"), cblogx, Label(fig, "Y logscale"), cblogy
    )


    ########EVENTS###########################################
    
    on(is_colorgrid_visible) do val
        if val
            CC_COLOR_GL[1, 1] = color_option_grid
            HIDDEN_GL[1,1] = empty_layout
        else
            CC_COLOR_GL[1, 1] = empty_layout
            HIDDEN_GL[1,1] = color_option_grid
        end
    end

    on(btn_color.clicks) do _
        @info "Before click"
        is_colorgrid_visible[] = true
        @info "clicked"
    end

    

    on(btn_add_curve.clicks) do _
        # @info "Clicked"

        #overwrite the selected curve entry
        curve_id = menu_curves.i_selected
        curve_name = tb_curve_name.stored_string
        pts = current_curve[]
        color = current_color[]

        nt = (;name = curve_name,
                            color,
                            points = pts,
                            )
        if !isempty(ALL_CURVES) || length(ALL_CURVES)>=curve_id
            ALL_CURVES[curve_id] = nt
        else
            push!(ALL_CURVES, nt)
        end
        #add a new curve 
        inext= length(ALL_CURVES)+1
        new_name = "Curve $inext"
        pts = []
        current_curve[] = pts
        current_color[] = cmap[inext]
        push!(ALL_CURVES[], (;name = new_name,
                        color = current_color[],
                        points= pts))
        push!(menu_curves.options, (new_name, inext))
        tb_curve_name.displayed_string = new_name
        
    end

    on(tb_curve_name.stored_string) do s
        id = menu_curves.i_selected[]
        opts = menu_curves.options[]
        @info "opts", opts
        opts[id] = (s, opts[id][2])
        menu_curves.options[] = opts
        menu_curves.selection[] = s
    end

    for (i, tb) in enumerate(tbscale)
        on(tb.stored_string) do s
            
            v = parse(Float64, s)
            plot_range[][i] = v
            @info "plot range:", plot_range[]
        end
    end

    for (i, cb) in enumerate((cblogx, cblogy))
        on(cb.checked) do val
            @info "checked"
            st = val ? :log : :linear
            scale_type[][i] = st
        end
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
    on(events(ax_img).mousebutton, priority = 10) do event
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
    on(events(ax_img).mouseposition, priority = 10) do mp
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
    on(events(ax_img).mousebutton, priority = 10) do event
        if event.button == Mouse.left && event.action == Mouse.release
            # Stop dragging
            dragged_index[] = nothing
            return Consume(false) #very important
        end
        return Consume(false)
    end


    #######################
    
    
    

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


function transform_pts(PTS::Vector{PT}, scale_rect, plot_range, scale_type) where PT
    #simplest case where we ignore rotation and log space
    X1, X2, Y1, Y2 = scale_rect #point2f - plot coords
    x1, x2, y1, y2 = plot_range #scalars - target coords
    scale_x = (x2 - x1) / (X2 - X1)
    scale_y = (y2 - y1) / (Y2 - Y1)
    tx = x1 - X1
    ty = y1 - Y1
    out = zeros(eltype(X1), length(PTS), 2)
    for i in eachindex(PTS)
        x, y = PTS[i]
        x *= scale_x
        x += tx
        y *= scale_y
        y += ty
        out[i, :] = x, y
    end
    return out
end


end # module YetAnotherPlotDigitizer
