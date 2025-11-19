# SPDX-License-Identifier: MIT

module YetAnotherPlotDigitizer

using GLMakie
import GLMakie.GLFW
using LinearAlgebra 
using StaticArrays 
using Observables
using FileIO
using Colors
using DelimitedFiles

include("bezier.jl")


export main

function main(;
        num_colors = 8,
        color_btn_height = 30,
        num_color_cols = 4,
        sidebar_width = 200,
        bottombar_height = 100,
        PICK_THRESHOLD = 30,
        )

    #######GLOBALS###########################
    
    ###markers for the scaling range selection
    # a ring with a vertical bar 
    Ring = BezierPath([
            MoveTo(Point(1, 0)),
            EllipticalArc(Point(0, 0), 1, 1, 0, 0, 2pi),
            MoveTo(Point(0.5, 0.0)),
            EllipticalArc(Point(0, 0), 0.5, 0.5, 0, 0, -2pi),
            ClosePath(),
            MoveTo(0.1, 2.5),
            LineTo(-0.1, 2.5),
            LineTo(-0.1, -2.5),
            LineTo(0.1, -2.5),
            ClosePath(),
                    ])

    #colors
    cmap = distinguishable_colors(num_colors, rand(RGB)) #color map for curves
    current_color = Observable(first(cmap)) 

    is_colorgrid_visible = Observable(false)


    #this is the reference image which is "digitized"
    ref_img = Observable{Any}(fill(RGB(0.1, 0.1, 0.1), 640, 480))
    
    

    #scaling range markers
    sz = size(ref_img[])
    X1 = Point2f(0.1 * sz[1], 0.1 * sz[2])
    X2 = Point2f(0.9 * sz[1], 0.1 * sz[2])
    Y1 = Point2f(0.5 * sz[1], 0.1 * sz[2])
    Y2 = Point2f(0.5 * sz[1], 0.9 * sz[2])
    scale_rect = Observable([X1, X2, Y1, Y2])
    scale_type = Observable([:linear, :linear])

    
    

    current_curve = Observable(get_initial_curve_pts(scale_rect[]))#the current active curve
    ntinit = (;name= "Curve 01", color = current_color[], points = current_curve[])
    ALL_CURVES = [ntinit] #holds all the curves

    plot_range = Observable([0.0, 1.0, 0.0, 1.0]) #scaling ranges x1, x2, y1, y2


    #currently dragged point (scale range or curve)
    

    #the fitting curve
    bezier_curve = lift(current_curve) do pts
        curve = piecewise_cubic_bezier(pts)
    end

    dragging_curve = Observable(false)

    # Variables to store the state during a drag operation
    drag_start_pos = Point2f(0, 0)
    dragged_index = -1
    target_observable = nothing # ctrl_scatter or scal

    # Get the observable for the Mouse.leftdrag event on the axis's scene
    
    previous_curve_id = Observable(1)


    num_export = Observable(100) #how many points per curve to export
    export_folder = nothing
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

    
    label_help = Label(fig, "Press \"a\" to add a segment, \"d\" to delete one.",
                    fontsize= 16,
                    color = :grey10,
                    halign =:center,
                    valign = :top,
                    padding = (10, 0, 0, 10),
                    tellwidth = false,
                    )
    fig[0,1] = label_help

    
    #################### SCALE / GLOBAL ##############################################################################


    tbscale = [Textbox(fig, width = sidebar_width/3, validator = Float64) for _ in 1:4]
    cblogx = Checkbox(fig, checked=false)
    cblogy = Checkbox(fig, checked=false)
    SCALE_GL[1,1] = Label(fig, "Scale")
    SCALE_GL[2,1] = vgrid!(
                    hgrid!(Label(fig, "X1:"), tbscale[1]),
                    hgrid!(Label(fig, "X2:"), tbscale[2]),
                    hgrid!(Label(fig, "log"), cblogx),
                    hgrid!(Label(fig, "Y1:"), tbscale[3]),
                    hgrid!(Label(fig, "Y2:"), tbscale[4]),
                    hgrid!(Label(fig, "log"), cblogy),
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

    tb_curve_name = Textbox(fig, placeholder = "Curve 01", width = 0.7 * sidebar_width)

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

    CURRENT_CURVE_GL[2,1] = hgrid!(btn_color, Box(fig, color = current_color, width = 0.4 * sidebar_width))
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


    ########################PLOTS#######################################################################################

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
    
    lines!(ax_img, bezier_curve, color = current_color, linewidth = 4, label = "Curve 01")# final Bézier curve

    
    lines!(ax_img, current_curve, color = (:grey, 0.5), linestyle = :dash)

    #control pts
    
    
    ctlr_colors = @lift map(i -> is_main_vertex($current_curve, i) ? :blue : :red, eachindex($current_curve))
    ctrl_scatter = scatter!(ax_img, current_curve, 
                        markersize = PICK_THRESHOLD, 
                        color = ctlr_colors, 
                        strokecolor = :black, 
                        strokewidth = 1, 
                        marker = :circle, 
                        )

    

    #############BOTTOM######################################

    btn_export = Button(fig, label="Export", width = 50)

    menu_export = Menu(fig, 
                        options = [("CSV", :csv), 
                                    ("TXT", :txt)],
                        default = "CSV",
                        width = 80,
                        )


    tb_export_num = Textbox(fig, placeholder = "100", validator = Int)

    BOTTOMBAR[1,1] = vgrid!(
                    hgrid!(Label(fig, "Points to export: "), tb_export_num),
                    hgrid!(btn_export, menu_export),
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
        
        is_colorgrid_visible[] = true
        
    end

    

    on(btn_add_curve.clicks) do _
        
        #just add a new curve 
        inext= length(ALL_CURVES)+1
        new_name = "Curve $inext"
        pts = get_initial_curve_pts(scale_rect[])
        current_curve[] = pts
        current_color[] = cmap[inext]
        push!(ALL_CURVES, (;name = new_name,
                        color = current_color[],
                        points= pts))
        opts = menu_curves.options[]
        push!(opts, (new_name, inext))
        menu_curves.options[] = opts
        tb_curve_name.displayed_string = new_name
        menu_curves.i_selected[] = inext
    end

    on(menu_curves.selection) do s
        if previous_curve_id[] == s || isnothing(s)
            return nothing
        end
        
        
        previous_curve_id[] = s
        #put the new data in
        # @info "s", s
        cdata = ALL_CURVES[s]

        tb_curve_name.stored_string[] = cdata.name
        current_color[] = cdata.color
        current_curve[] = cdata.points
    end

    

    on(tb_curve_name.stored_string) do s
        id = menu_curves.selection[]
        
        update_curve!(ALL_CURVES, id; name = s)
        #also update the menu entry
        opts = menu_curves.options[]
        # @info "opts", opts
        opts[id] = (s, opts[id][2])
        menu_curves.options[] = opts
        
    end

    on(current_color) do c
        
        update_curve!(ALL_CURVES, previous_curve_id[]; color= c)
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
        export_folder = dirname(f1)
        println(f1)
        try
            ref_img[] = rotr90(load(f1))
            #  
            reset_plot!(ax_img)
            
        catch e
            @info "Triggered"
            
        end
        
    end


    on(tb_export_num.stored_string) do s
        n = 10
        try n = parse(Int, s); catch; end
        num_export[] = max(10, n)
    end

    on(btn_export.clicks) do _
        N = num_export[]
        format = menu_export.selection[]
       
        export_curves(ALL_CURVES, 
                    scale_rect[], 
                    plot_range[], 
                    scale_type[];
                    N, 
                    format, 
                    export_folder,
                    )

    end
    #####################MOUSE Interaction#########################################

    
    
    on(events(ax_img.scene).mousebutton, priority = 20) do event
        # Only react to left mouse button press
        if event.button == Mouse.left && event.action == Mouse.press
            # @info "triggered mouse press"
            mousepos = Makie.mouseposition(ax_img.scene)
            dragged_index = -1
            target_observable = nothing
            
            #try the scaling pts
            idx = find_closest_point_to_position(scale_rect[], mousepos; PICK_THRESHOLD, area= :square)
            if idx !=-1
                 target_observable = scaling_pts
                 dragged_index = idx
                 return Consume(true)   
            end
            
            idx = find_closest_point_to_position(current_curve[], mousepos; PICK_THRESHOLD, area= :square)
            if idx != -1
                target_observable = ctrl_scatter
                dragged_index = idx
                return Consume(true)
            end

        end
        return Consume(false)
    end

    # Interaction for mouse movement (dragging)
    on(events(ax_img).mouseposition, priority = 10) do mp
        if dragged_index != -1 && ispressed(fig, Mouse.left)
            # Convert mouse position (in pixels) to data coordinates
            new_data_pos = Makie.mouseposition(ax_img.scene)
            
            if target_observable === scaling_pts
               
                current_points = scale_rect[]
                current_points[dragged_index[]] = new_data_pos
                scale_rect[] = current_points # Notify the Observable of the change
                return Consume(true)
            end
            if target_observable === ctrl_scatter
                current_points = current_curve[]
                move_control_vertices!(current_points, dragged_index[], new_data_pos)
                current_curve[] = current_points # Notify the Observable of the change
                return Consume(true)
            end
            
        end
        return Consume(false)
    end

    # Interaction for releasing the mouse button
    on(events(ax_img).mousebutton, priority = 10) do event
        if event.button == Mouse.left && event.action == Mouse.release
            # Stop dragging
            dragged_index = -1
            update_curve!(ALL_CURVES, previous_curve_id[]; points = current_curve[])
        end
        return Consume(false)
    end


    on(events(ax_img).keyboardbutton, priority = 10) do event
        if event.action == Keyboard.press
            current_points = current_curve[]
            
            if event.key == Keyboard.a # Add point
                # Check if we have a valid mouse position in data coordinates
                data_pos = try Makie.mouseposition(ax_img.scene) catch; return Consume(false) end
                
                add_bezier_segment!(current_points, data_pos)
                # @info "current_points",current_points
                current_curve[] = current_points
                return Consume(true)
            
            elseif event.key == Keyboard.d # delete closest main segment (removes 3 points from curve)
                data_pos = try Makie.mouseposition(ax_img.scene) catch; return Consume(false) end
                remove_bezier_segment!(current_points, data_pos)
                current_curve[] = current_points
            end
            
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







function find_closest_point_to_position(pts, pos; 
                                    PICK_THRESHOLD = 20,
                                    area = :circle, #:circle or :square
                                    )
    index = -1
    dmin = Inf

    if area == :circle
        dist = (p1, p2) -> norm(p1 .- p2)
    elseif area ==:square
        dist = (p1, p2) -> norm(p1 .- p2, Inf)
    end

    
    for (i, pt) in enumerate(pts)
        d = dist(pt, pos)
        if d <= PICK_THRESHOLD && d<dmin 
            dmin = d
            index = i   
        end
    end
    
    return index
end

function get_initial_curve_pts(PTS)
    X1, X2, Y1, Y2 = PTS
    R1 = Point2f(X1[1], Y1[2])
    R2 = Point2d(X2[1], Y2[2])
    C1 = 0.8 * R1 + 0.2 * R2
    C2 = 0.6 * R1 + 0.4 * R2
    C3 = 0.4 * R1 + 0.6 * R2
    C4 = 0.2 * R1 + 0.8 * R2

    return [C1, C2, C3, C4]

end


function update_curve!(CRV, id; name = nothing,
                        color = nothing,
                        points = nothing)

    @assert 0 < id <= length(CRV)
    nt = CRV[id]
    name = isnothing(name) ? nt.name : name
    color = isnothing(color) ? nt.color : color
    points = isnothing(points) ? nt.points : points
    
    @assert typeof(name) == typeof(nt.name)
    @assert typeof(color) == typeof(nt.color)
    @assert typeof(points) == typeof(nt.points)
    
    CRV[id] = (;name, color, points)

end

function export_curves(ALL_CURVES, scale_rect, plot_range, scale_type; 
                    N = 100, 
                    format = :csv, 
                    export_folder = nothing::Union{Nothing, String})


    if format==:csv
        ext = ".csv"
        delim = ','
    elseif format == :txt
        ext = ".txt"
        delim = ','
    end

    for crv in ALL_CURVES
        if isnothing(export_folder)
            fn = crv.name * ext
        else
            fn = joinpath(export_folder, crv.name * ext)
        end
        data = sample_cubic_bezier_curve(crv.points; samples = N, lut_samples = 200)
        #needs to be transformed
        tdata = transform_pts(data, scale_rect, plot_range, scale_type)
        writedlm(fn, tdata, delim)
        @info "Exported", fn
    end
    
    return nothing
end

function transform_pts(PTS::Vector{PT}, scale_rect, plot_range, scale_type) where PT
    #simplest case where we ignore rotation and log space
    X1, X2, Y1, Y2 = scale_rect #point2f - plot coords
    x1, x2, y1, y2 = plot_range #scalars - target coords
    scale_x = (x2 - x1) / (X2[1] - X1[1])
    scale_y = (y2 - y1) / (Y2[2] - Y1[2])
    tX = -X1[1]
    tY = -Y1[2]
    tx = x1 
    ty = y1 
    out = zeros(eltype(X1), length(PTS), 2)
    for i in eachindex(PTS)
        x, y = PTS[i]
        x = (x + tX) * scale_x + tx
        y = (y + tY) * scale_y + ty
        out[i, :] .= x, y
    end
    return out
end



end # module YetAnotherPlotDigitizer
