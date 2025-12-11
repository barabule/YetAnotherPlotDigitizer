function main(;
        num_colors = 32,
        color_btn_height = 30,
        num_color_cols = 4,
        sidebar_width = 200,
        bottombar_height = 100,
        PICK_THRESHOLD = 20,
        MARKER_SIZE = 25,
        SCALE_MARKER_SIZE = 12,
        number_of_fine_points = 1000,
        )

    #######GLOBALS###########################
    
    ###markers for the scaling range selection
    # a RingBarMarker with a vertical bar 
    RingBarMarker = BezierPath([
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


    HollowCircleMarker = BezierPath([
        MoveTo(Point(0.5, 0)),
        EllipticalArc(Point(0, 0), 0.5, 0.5, 0, 0, 2pi),
        MoveTo(Point(0.35, 0.0)),
        EllipticalArc(Point(0, 0), 0.35, 0.35, 0, 0, -2pi),
        ClosePath(),
    ])


    HollowDiamondMarker = BezierPath([
        MoveTo(Point(0.5, 0)),
        LineTo(0, 0.5),
        LineTo(-0.5, 0),
        LineTo(0, -0.5),
        LineTo(0.5, 0),
        MoveTo(0.35, 0),
        LineTo(0, -0.35),
        LineTo(-0.35, 0),
        LineTo(0, 0.35),
        LineTo(0.35, 0),
        ClosePath()
    ])


    cmap = distinguishable_colors(num_colors, rand(RGB))

    PZ=  zero(Point2f)
    
    is_colorgrid_visible = Observable(false)
    assets_folder = joinpath(dirname(@__DIR__), "assets")
    
    init_img = try
        fn = joinpath(assets_folder, "example_raster_plot.jpg")
        # @info fn
        rotr90(load(fn))
    catch
        fill(RGB(0.1, 0.1, 0.1), 640, 480)
    end

    BigDataStore = Dict{Symbol, Any}(
                    # general
                    :cmap => cmap,#color map for curves
                    #img
                    :ref_img => Observable{Any}(init_img),
                    #scaling
                    :scale_rect => Observable([PZ, PZ, PZ, PZ]), #scaling range markers
                    :scale_type => Observable([:linear, :linear]),
                    :plot_range => Observable([0.0, 1.0, 0.0, 1.0]), #x1,x2,y1,y2 scaling ranges
                    :freeze_scale => nothing, #observable to indicate if the scale markers can be moved
                    #plotting
                    :marker_handles => HollowCircleMarker,
                    :marker_smooth => HollowCircleMarker,
                    :marker_sharp => HollowDiamondMarker,
                    :color_handles => :grey,
                    :color_smooth => :red,
                    :color_sharp => :red,
                    :size_control_points => MARKER_SIZE,
                    :size_handles => 0.8 * MARKER_SIZE,
                    :ax => nothing, #holds the plot axis
                    :curve_controls => nothing, #stuff that needs to change to reflect the current curve
                    #export
                    :num_export => Observable(100), #how many points per curve to export
                    :export_horizontal => nothing, #export curves sampled horizontally
                    :export_folder => nothing, 
                    #curve data
                    :edited_curve_id => Observable(1), #id of the current curve
                    :current_curve => nothing, #control for current curve
                    :current_curve_pts => nothing, #holds just the control points
                    :current_color => Observable(first(cmap)), #color of currently edited curve
                    :other_curve_plots => [], #holds the plot objects for other curves than the current
                    :ALL_CURVES => [], #holds all curve data
                    :current_curve_type => Observable(:bezier), #indicates if the current curve is bezier or interpolating
                    :number_of_fine_points => number_of_fine_points, #no of points to plot for fine curves

    ) #holds everything
    
    reset_marker_positions!(size(BigDataStore[:ref_img][]), BigDataStore[:scale_rect]) #set to default positions

    BigDataStore[:current_curve] = Observable(CubicBezierCurve(get_initial_curve_pts(BigDataStore[:scale_rect][])))

    ntinit = (;name= "Curve 01", 
            color = BigDataStore[:current_color][], 
            points = BigDataStore[:current_curve][].points, 
            is_smooth=[false, false],
            curve_type = :bezier,
            )
    BigDataStore[:ALL_CURVES] = [ntinit]


    # Variables to store the state during a drag operation
    dragged_index = -1 #index to the closest vertex
    target_observable = nothing # ctrl_scatter or scal

    status_text = Observable("Status")

    #######LAYOUT#######################################################################################################


    fig = Figure(size = (800, 600))
    
    ax_img = Axis(fig[1,1], aspect = DataAspect(), tellheight=  false, tellwidth = false)
    deregister_interaction!(ax_img, :rectanglezoom) #just gets in the way when dragging
    BigDataStore[:ax] = ax_img
    
    SIDEBAR = GridLayout(fig[1,2], width = sidebar_width, tellheight = false)

    SCALE_GL = GridLayout(SIDEBAR[1,1], width = sidebar_width) #range scaling
    ALL_CURVES_GL = GridLayout(SIDEBAR[2,1], width = sidebar_width) #menu to select the current curve
    CURRENT_CURVE_GL = GridLayout(SIDEBAR[3,1], width = sidebar_width) #holds settings for the current curve
    
    CC_COLOR_GL = GridLayout(SIDEBAR[4, 1]) #shows a grid of colors
    empty_layout = GridLayout()
    color_option_grid = GridLayout()
    HIDDEN_GL = GridLayout(bbox = (-200, -100, 0, 100)) #used to swap the color buttons when "hidden"
    
    CURVE_TYPE_GL = GridLayout(SIDEBAR[5,1]) # menu to select interpolation type


    BOTTOMBAR = GridLayout(fig[2,1], tellwidth =false, height = bottombar_height)#other stuff?

    
    label_help = Label(fig, "Press \"a\" to add a segment, \"d\" to delete one, 's' to toggle sharp." *
                            "\nZoom with scrollwheel, pan with RMB, reset zoom with CTRL+LMB" *
                            "\nDrag and drop an image file to load it.",
                    fontsize= 16,
                    font = :italic,
                    color = :grey40,
                    halign =:center,
                    valign = :top,
                    padding = (10, 0, 0, 10),
                    tellwidth = false,
                    )
    label_status = Label(fig, text = status_text)
    fig[0,:] = label_help
    fig[-1, :] = label_status
    
    #################### SCALE / GLOBAL ################################################################################

    cb_freeze_scale = Checkbox(fig, checked =false)
    BigDataStore[:freeze_scale] = cb_freeze_scale.checked
    tbscale = [Textbox(fig, width = sidebar_width/3, validator = Float64, 
                            placeholder = "$(BigDataStore[:plot_range][][i])") for i in 1:4]
    cblogx = Checkbox(fig, checked=false)
    cblogy = Checkbox(fig, checked=false)
    SCALE_GL[1,1] = Label(fig, "Scale")
    SCALE_GL[2,1] = vgrid!(
                    hgrid!(Label(fig, "Freeze scale markers"), cb_freeze_scale),
                    hgrid!(Label(fig, "X1:"), tbscale[1]),
                    hgrid!(Label(fig, "X2:"), tbscale[2]),
                    hgrid!(Label(fig, "log"), cblogx),
                    hgrid!(Label(fig, "Y1:"), tbscale[3]),
                    hgrid!(Label(fig, "Y2:"), tbscale[4]),
                    hgrid!(Label(fig, "log"), cblogy),
                                )

    
    #############ALL CURVES#############################################################################################

    menu_curves = Menu(fig, options = [("Curve 01", 1)],
                        default = "Curve 01", 
                        width = 0.5 * sidebar_width
                        )

    ALL_CURVES_GL[1, 1] = vgrid!(
                        hgrid!(Label(fig, "Curve: "), menu_curves),
                                )


    push!(BigDataStore, :curves_menu => menu_curves)
    #################CURVE##############################################################################################

    tb_curve_name = Textbox(fig, placeholder = "Curve 01", width = 0.7 * sidebar_width)

    btn_add_curve = Button(fig, label = "Add")
    btn_rem_curve = Button(fig, label = "Rem")
    label_curve_name = Label(fig, "Current curve:", width = sidebar_width)
    CURRENT_CURVE_GL[1, 1] =vgrid!(
                    label_curve_name,
                    hgrid!(Label(fig, "Name"), tb_curve_name),
                    hgrid!(btn_add_curve, btn_rem_curve),
                    )

    ##############COLOR GRID############################################################################################

    btn_color = Button(fig,
                        label = "Color",
                        height = color_btn_height,
                        )

    CURRENT_CURVE_GL[2,1] = hgrid!(btn_color, Box(fig, color = BigDataStore[:current_color], width = 0.4 * sidebar_width))
    CC_COLOR_GL[1,1] = empty_layout

    HIDDEN_GL[1,1] = color_option_grid
    populate_color_chooser(fig,
                      color_option_grid, 
                      BigDataStore[:cmap], 
                      BigDataStore[:current_color], 
                      is_colorgrid_visible; 
                      btn_height = color_btn_height,
                      num_color_cols,
                      btn_width = 0.7*(sidebar_width / num_color_cols),
                      )


    ####################    CURVE TYPE     #############################################################################

    menu_curve_type = Menu(fig, options = zip(InterpolationTypeNames, InterpolationTypeList),
                            default = "Bezier")

    CURVE_TYPE_GL[1,1] = vgrid!(
                    hgrid!( Label(fig, "Curve type "), menu_curve_type)
    )



    ####################    PLOTS     ##################################################################################

    

    img_plot = image!(ax_img, BigDataStore[:ref_img])
    scaling_pts = (scatter!(ax_img, BigDataStore[:scale_rect], color = [:red, :red, :green, :green], 
                                marker = RingBarMarker,
                                markersize = SCALE_MARKER_SIZE,
                                rotation = [0, 0, pi/2, pi/2], 
                                strokecolor = :black,
                                strokewidth =1,),

    text!(ax_img, BigDataStore[:scale_rect]; text =["X1", "X2", "Y1", "Y2"],
                        color = [:red, :red, :green, :green],
                        # color = :black,
                        fontsize = SCALE_MARKER_SIZE,
                        offset = (SCALE_MARKER_SIZE, SCALE_MARKER_SIZE)
                        ),

                        
    )
    
    
    #hi res sampling of the current curve
    
    BigDataStore[:current_curve_pts] = CC = lift(BigDataStore[:current_curve]) do C
        pts = C.points
    end

    bezier_curve = lift(CC, BigDataStore[:current_curve_type]) do C, ct
        N = BigDataStore[:number_of_fine_points]
        if ct == :bezier
            nseg = number_of_cubic_segments(C)
            N_segments = round(Int, N / nseg)
            return piecewise_cubic_bezier(C; N_segments)
        else
            itp = make_new_interpolator(C, ct)
            return eval_pts(itp; N)
        end
    end
    # bezier_curve = lift(BigDataStore[:current_curve]) do CP
    #     pts = CP.points
    #     piecewise_cubic_bezier(pts; N_segments = 50)
    # end
    cname = lift(BigDataStore[:edited_curve_id]) do id
        nt = BigDataStore[:ALL_CURVES][id]
        nt.name
    end
    edited_curve_fine_plot = lines!(ax_img, bezier_curve, 
                                    color = BigDataStore[:current_color], 
                                    linewidth = 0.2 * MARKER_SIZE,
                                    alpha = 0.6,
                                    linestyle = :solid)
                                    #

    
    

    #control pts
    ctrl_lines = lines!(ax_img, CC, color = (:grey, 0.5), linestyle = :dash)

    ### WORKAROUND

    SmoothPoints = lift(BigDataStore[:current_curve_pts], BigDataStore[:current_curve_type]) do pts, ct
        
        if is_bezier(ct)
            cc = BigDataStore[:current_curve][]
            idx_main_cp = filter(i -> is_control_point(i), eachindex(cc.points))
            idx_smooth = filter(i -> cc.is_smooth[i], eachindex(cc.is_smooth))
            return cc.points[idx_main_cp[idx_smooth]]
        else
            return pts
        end
    end

    SharpPoints = lift(BigDataStore[:current_curve], BigDataStore[:current_curve_type]) do cc, ct
        if is_bezier(ct)
            idx_main_cp = filter(i -> is_control_point(i), eachindex(cc.points))
            idx_sharp = filter(i -> !cc.is_smooth[i], eachindex(cc.is_smooth))
            return cc.points[idx_main_cp[idx_sharp]]
        else
            return Vector{eltype(cc.points)}()
        end
    end

    HandlePoints = lift(BigDataStore[:current_curve], BigDataStore[:current_curve_type]) do cc, ct
        if is_bezier(ct)
            idx_handle_pts = filter(i -> !is_control_point(i), eachindex(cc.points))
            return cc.points[idx_handle_pts]
        else
            return Vector{eltype(cc.points)}()
        end
    end

    scatter!(ax_img, HandlePoints,
                marker = BigDataStore[:marker_handles],
                markersize = BigDataStore[:size_handles],
                color = BigDataStore[:color_handles],
                strokecolor = :black,
                strokewidth = 1,
                )

    scatter!(ax_img, SmoothPoints, 
                marker = BigDataStore[:marker_smooth],
                markersize = BigDataStore[:size_control_points],
                color = BigDataStore[:color_smooth],
                strokecolor = :black,
                strokewidth = 1,
                )

    scatter!(ax_img, SharpPoints,
                marker = BigDataStore[:marker_sharp],
                markersize = BigDataStore[:size_control_points],
                color = BigDataStore[:color_sharp],
                strokecolor = :black,
                strokewidth = 1,
                )

    

    curve_controls = [tb_curve_name, BigDataStore[:current_color], BigDataStore[:current_curve], label_curve_name]
    BigDataStore[:curve_controls] = curve_controls

    #########    BOTTOM    #############################################################################################

    btn_export = Button(fig, label="Export", width = 50)

    menu_export = Menu(fig, 
                        options = [("CSV", :csv), 
                                    ("TAB", :tab),
                                    ("SPACE", :space),
                                    ("Semicolon ;", :semicolon),
                                    ],
                        default = "CSV",
                        width = 80,
                        )


    tb_export_num = Textbox(fig, placeholder = "100", validator = Int)


    cb_export_horizontal = Checkbox(fig)
    BigDataStore[:export_horizontal] = cb_export_horizontal.checked

    BOTTOMBAR[1,1] = vgrid!(
                    hgrid!(Label(fig, "Points to export: "), tb_export_num, Label(fig, "Sample in X"), cb_export_horizontal),
                    hgrid!(btn_export, menu_export),
                            )           


    ###########    EVENTS    ###########################################################################################
    
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
        inext= length(BigDataStore[:ALL_CURVES])+1
        new_name = "Curve $inext"
        pts = get_initial_curve_pts(BigDataStore[:scale_rect][])
        

        next_color_id = mod(inext, num_colors) + 1
        new_color = BigDataStore[:cmap][next_color_id]
        nt = (;name = new_name,
               color = new_color,
               points= pts,
               is_smooth = [false, false],
               curve_type = menu_curve_type.selection[], 
               )     
        
        push!(BigDataStore[:ALL_CURVES], nt)
        BigDataStore[:edited_curve_id][] = inext
        rebuild_menu_options!(menu_curves, BigDataStore[:ALL_CURVES])
        
        update_current_curve_controls!(BigDataStore, nt)
        
        switch_other_curves_plot!(ax_img, BigDataStore[:ALL_CURVES], inext, BigDataStore[:other_curve_plots])
        
        status_text[] = "Added new curve $new_name"
        menu_curves.i_selected[] = BigDataStore[:edited_curve_id][]
        # menu_curve_type.i_selected[] = 1 #bezier
    end

    on(btn_rem_curve.clicks) do _
        #remove the current curve
        num_curves = length(BigDataStore[:ALL_CURVES])
        if num_curves >1
            id_delete = BigDataStore[:edited_curve_id][]#delete the current curve
            old_name = BigDataStore[:ALL_CURVES][id_delete].name
            deleteat!(BigDataStore[:ALL_CURVES], id_delete[])
            rebuild_menu_options!(menu_curves, BigDataStore[:ALL_CURVES])
            BigDataStore[:edited_curve_id][] = lastindex(BigDataStore[:ALL_CURVES])#set the current curve to the last in the list
            update_current_curve_controls!(BigDataStore)#we should also update the color etc...
            switch_other_curves_plot!(ax_img, BigDataStore[:ALL_CURVES], 
                                BigDataStore[:edited_curve_id][], BigDataStore[:other_curve_plots])
            status_text[] = "Removed curve $old_name"
        end
    end

    # TODO proper update - issue with curve_pts
    on(menu_curves.selection) do s
        if BigDataStore[:edited_curve_id][] == s || isnothing(s)
            return nothing
        end
        
        
        BigDataStore[:edited_curve_id][] = s
        cdata = BigDataStore[:ALL_CURVES][s]
        
        menu_curve_type.i_selected[] = ITP_Dict[cdata.curve_type]

        update_current_curve_controls!(BigDataStore)
        switch_other_curves_plot!(ax_img, BigDataStore[:ALL_CURVES], s, BigDataStore[:other_curve_plots])
        
        status_text[] = "Editing curve $(cdata.name)"
        # AC = BigDataStore[:ALL_CURVES]
        # for nt in AC
        #     @info "Curve type", nt.curve_type
        # end
    end

    

    on(tb_curve_name.stored_string) do s
        id = BigDataStore[:edited_curve_id][]
        old_name = BigDataStore[:ALL_CURVES][id].name
        update_curve!(BigDataStore; name = s)
        #also update the menu entry
        opts = menu_curves.options[]
        # @info "opts", opts
        opts[id] = (s, opts[id][2])
        menu_curves.options[] = opts
        menu_curves.i_selected[] = id
        label_curve_name.text[] = "Current curve: $s"
        status_text[] = "Changed curve from $old_name to $s"
        
    end

    on(BigDataStore[:current_color]) do c
        
        update_curve!(BigDataStore; color= c)
    end

    for (i, tb) in enumerate(tbscale)
        on(tb.stored_string) do s
            
            v = parse(Float64, s)
            BigDataStore[:plot_range][][i] = v
            #@info "plot range:", BigDataStore[:plot_range][]
            status_text[] = "plot range: $(BigDataStore[:plot_range][])"
        end
    end

    for (i, cb) in enumerate((cblogx, cblogy))
        on(cb.checked) do val
            
            st = val ? :log : :linear
            BigDataStore[:scale_type][][i] = st
            axis = cb==cblogx ? "X" : "Y"
            stext = st==:log ? "logarithmic" : "linear"
            status_text[] = "Changed $axis scaling to $stext"
        end
    end


    on(menu_curve_type.selection) do s
        pts = BigDataStore[:current_curve_pts][]
        N = length(pts)
        if !has_valid_number_of_points(N, s) #do something to make it valid for the current itp
            reset_curve!(pts, s) #simplest case
            # BigDataStore[:current_curve_pts][] = pts
        end
        if s == :bezier
            BigDataStore[:current_curve][] = CubicBezierCurve(pts; all_sharp = true)
        else
            # t must be  sorted for the other interpolation types...
            make_valid!(pts, s)
            BigDataStore[:current_curve_pts][] = pts
        end
        
        BigDataStore[:current_curve_type][] = s
        
        update_curve!(BigDataStore; curve_type = s)
        
    end


    ##########################     RESET    ############################################################################
    ## TODO better reset
    on(events(fig).dropped_files) do files
        isempty(files) && return nothing
        
        f1 = first(files)
        BigDataStore[:export_folder] = dirname(f1)
        println(f1)
        try
            BigDataStore[:ref_img][] = rotr90(load(f1))
            
        catch e
            # @info "Probably not an image?"
            status_text = "Cannot open this file. Probably not an image?"
            return nothing
        end

        reset_limits!(ax_img) 
        #reset most state 
        if length(BigDataStore[:ALL_CURVES])>=2 #drop all but the 1st curve
            deleteat!(BigDataStore[:ALL_CURVES], 2:length(BigDataStore[:ALL_CURVES]))
        end
        reset_marker_positions!(size(BigDataStore[:ref_img][]), BigDataStore[:scale_rect])
        # @info "reset"
        ntinit = initial_curve(BigDataStore; reset = true)
        BigDataStore[:current_curve_type][] = :bezier
        menu_curve_type.i_selected[] = ITP_Dict[:bezier] #1
        status_text[] = "New image imported!"   
        
        # @info BigDataStore        
    end

    ####################################################################################################################

    on(tb_export_num.stored_string) do s
        n = 10
        try n = parse(Int, s); catch; end
        BigDataStore[:num_export][] = max(10, n)
        status_text[] = "Curve export density = $n points"
    end

    on(btn_export.clicks) do _
        N = BigDataStore[:num_export][]
        format = menu_export.selection[]
        #check if the are negative numbers when log scale range
        for i in 1:2
            if BigDataStore[:scale_type][][i] == :log
                if BigDataStore[:plot_range][][2i-1] <= 0 || BigDataStore[:plot_range][][2i] <= 0 
                    status_text[] =  "Cannot export, log scaling needs positive numbers.\n
                                    Please set the X1, X2, Y1 or Y2 to be positive!"
                    return nothing
                end
            end
        end
         
        export_curves(BigDataStore[:ALL_CURVES], 
                    BigDataStore[:scale_rect][], 
                    BigDataStore[:plot_range][], 
                    BigDataStore[:scale_type][];
                    N, 
                    format, 
                    export_folder = BigDataStore[:export_folder],
                    sample_horizontal = BigDataStore[:export_horizontal][],
                    )
        status_text[] = "Exported files!"
    end
######################   MOUSE Interaction   ###########################################################################
    
    on(events(ax_img.scene).mousebutton, priority = 20) do event
        # Only react to left mouse button press
        if event.button != Mouse.left || event.action != Mouse.press
            return Consume(false)
        end

        # @info "triggered mouse press"
        mousepos = Makie.mouseposition(ax_img.scene)
        dragged_index = -1
        target_observable = nothing
        #manual priority

        #try the scaling pts
        idx = find_closest_point_to_position(BigDataStore[:scale_rect][], mousepos; 
                                            PICK_THRESHOLD, 
                                            area= :square)
        if idx !=-1 && !BigDataStore[:freeze_scale][] #ignore the scale markers if frozen
                target_observable = scaling_pts
                dragged_index = idx
                return Consume(true)   
        end
        #try the control point curve
        idx = find_closest_point_to_position(BigDataStore[:current_curve][], mousepos; 
                                                thresh = PICK_THRESHOLD, 
                                                area= :square)
        idx == -1 && return Consume(false)
        # @info "snatched", idx
        #found something
        target_observable = ctrl_lines
        dragged_index = idx
        return Consume(true)
    end

    # Interaction for mouse movement (dragging)
    on(events(ax_img).mouseposition, priority = 10) do mp
        # if dragged_index != -1 && ispressed(fig, Mouse.left)
        dragged_index != -1 && ispressed(fig, Mouse.left) || return Consume(false)
        # Convert mouse position (in pixels) to data coordinates
        new_data_pos = Makie.mouseposition(ax_img.scene)
        
        if target_observable === scaling_pts && !BigDataStore[:freeze_scale][]
            current_points = BigDataStore[:scale_rect][]
            current_points[dragged_index[]] = new_data_pos
            BigDataStore[:scale_rect][] = current_points # Notify the Observable of the change
            return Consume(true)
        end
        # @info "before", dragged_index
        target_observable == ctrl_lines || return Consume(false)
        # @info "ctrl"
        if BigDataStore[:current_curve_type][] == :bezier
            # @info "bezier"
            cubic_curve = BigDataStore[:current_curve][]
            move!(cubic_curve, dragged_index, new_data_pos)
            BigDataStore[:current_curve][]  = cubic_curve 
            # @info "done bezier"
        else
            # @info "itp"
            pts = BigDataStore[:current_curve][].points
            move_itp!(pts, dragged_index, new_data_pos)
            BigDataStore[:current_curve_pts][] = pts
            # @info "after itp"
        end
        
        # @info "moving PT", dragged_index, "num CP", length(current_points.points)
        # Notify the Observable of the change
        return Consume(true)
         
    end

    # Interaction for releasing the mouse button
    on(events(ax_img).mousebutton, priority = 10) do event
        if event.button == Mouse.left && event.action == Mouse.release
            # Stop dragging
            dragged_index = -1
            update_curve!(BigDataStore; 
                          points = BigDataStore[:current_curve][].points,
                          is_smooth = BigDataStore[:current_curve][].is_smooth)
        end
        return Consume(false)
    end

#################   KEYBOARD   #########################################################################################

    on(events(ax_img).keyboardbutton, priority = 10) do event
        event.action == Keyboard.press || return Consume(false)

        if event.key == Keyboard.a # Add point
            # Check if we have a valid mouse position in data coordinates
            data_pos = try Makie.mouseposition(ax_img.scene) catch; return Consume(false) end

            CT = BigDataStore[:current_curve_type][]
            
            if CT == :bezier
                current_points = BigDataStore[:current_curve][]
                # segid = find_closest_segment(current_points, data_pos)
                segid = find_closest_projected_segment(current_points, data_pos)
                add_segment!(current_points, segid)
                BigDataStore[:current_curve][] = current_points
                return Consume(true)
            end
            
            #not a bezier
            pts = BigDataStore[:current_curve][].points
            add_point!(pts, data_pos)
            BigDataStore[:current_curve_pts][] = pts
            return Consume(true)
        end

        if event.key == Keyboard.d # delete closest main segment (removes 3 points from curve)
            data_pos = try Makie.mouseposition(ax_img.scene) catch; return Consume(false) end
            
            CT = BigDataStore[:current_curve_type][]

            if CT == :bezier
                current_points = BigDataStore[:current_curve][]
                cpid = find_closest_control_point_to_position(current_points, data_pos)
                remove_control_point!(current_points, cpid)
                BigDataStore[:current_curve][] = current_points 
                return Consume(true)
            end

            #not a bezier
            pts = BigDataStore[:current_curve][].points
            remove_point!(pts, data_pos; min_pts = minimum_points(CT))
            BigDataStore[:current_curve_pts][] = pts #
            return Consume(true)
        end
        
        if event.key == Keyboard.s #toggle is_smooth of the closest CP
            BigDataStore[:current_curve_type][] == :bezier || return Consume(true) #no effect for other curve types

            data_pos = try Makie.mouseposition(ax_img.scene) catch; return Consume(false) end
            current_points = BigDataStore[:current_curve][]
            cp_id = find_closest_control_point_to_position(current_points, data_pos)
            toggle_smoothness(current_points, cp_id)
            BigDataStore[:current_curve][] = current_points
            return Consume(true)
        end

        return Consume(false)
    end


    ####################################################################################################################
    
    
    

    return wait(display(fig))
end





# create for each color a button and behavior
function populate_color_chooser(fig::Figure, grid::GridLayout, 
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




function update_curve!(D::Dict{Symbol, Any}; name = nothing,
                        color = nothing,
                        points = nothing,
                        is_smooth = nothing,
                        curve_type = nothing,)

    nt = D[:ALL_CURVES][D[:edited_curve_id][]]

    name = isnothing(name) ? nt.name : name
    color = isnothing(color) ? nt.color : color
    points = isnothing(points) ? nt.points : points
    is_smooth = isnothing(is_smooth) ? nt.is_smooth : is_smooth
    curve_type = isnothing(curve_type) ? nt.curve_type : curve_type
    # @info "n", name, "c", color, "pts", length(points), "sm", is_smooth 
    @assert typeof(name) == typeof(nt.name)

    # @info "col type", typeof(color), "col t2", typeof(nt.color)
    # @info "col check", typeof(color) == typeof(nt.color)
    
    @assert typeof(color) == typeof(nt.color)
    # @info "no assertion errors"
    @assert typeof(points) == typeof(nt.points)
    @assert eltype(is_smooth) == eltype(is_smooth)
    if curve_type == :bezier && !(length(is_smooth) == div(length(points)-1,3)+1)
        #make it the correct length
        is_smooth = fill(false, div(length(points)-1,3)+1)
    end
    @assert typeof(curve_type) == Symbol

    D[:ALL_CURVES][D[:edited_curve_id][]] = (;name, color, points, is_smooth, curve_type)

end

function update_current_curve_controls!(D::Dict{Symbol, Any}, cdata=nothing)
    curve_controls = D[:curve_controls] 
    cdata = isnothing(cdata) ? D[:ALL_CURVES][D[:edited_curve_id][]] : cdata

    TB, current_color, current_curve, crv_label = curve_controls
    # TB.placeholder[] = cdata.name #this doesn't do anything
    current_color[] = cdata.color 
    ct = D[:current_curve_type][]
    if ct == :bezier 
        current_curve[] = CubicBezierCurve(cdata.points, cdata.is_smooth)
    else
        D[:current_curve_pts][] = cdata.points
    end

    crv_label.text[] = "Current curve: $(cdata.name)"

    return nothing
end

function rebuild_menu_options!(menu, ALL_CURVES)
    
    opts = Vector{Tuple{String, Int}}()
    # @info "before", opts
    for (i, crv) in enumerate(ALL_CURVES)
        push!(opts, (crv.name, i))
    end
    # @info "options done", opts
    menu.options[] = opts
end


function switch_other_curves_plot!(ax, all_curves, id, plot_handles; N = 1000)
    #delete old plots
    if !isnothing(plot_handles) || !isempty(plot_handles)
        for plt in plot_handles
            delete!(ax, plt)
        end
        empty!(plot_handles)
    else
        return nothing
    end
    #gather new curves to plot
    ids = filter(i -> i!=id, eachindex(all_curves))
    # @info "ids", ids, "id", id
    if !isnothing(ids)
        for i in ids
            crv = all_curves[i]
            if crv.curve_type == :bezier
                nseg = number_of_cubic_segments(crv.points)
                N_segments = round(Int, N / nseg)
                pts = piecewise_cubic_bezier(crv.points; N_segments)
            else
                # @info "points", crv.points
                interpolator = make_new_interpolator(crv.points, crv.curve_type)
                pts = eval_pts(interpolator; N)
            end
            color = crv.color
            push!(plot_handles, lines!(ax, pts, color= color))
        end
        
    end
    return nothing
end


function export_curves(ALL_CURVES, scale_rect, plot_range, scale_type; 
                    N = 100, 
                    format = :csv, 
                    export_folder = nothing::Union{Nothing, String},
                    sample_horizontal = false)


    if format==:csv
        ext, delim = ".csv", ','
    elseif format == :tab
        ext, delim = ".txt", '\t'
    elseif format == :space
        ext, delim = ".txt", ' '
    elseif format == :semicolon
        ext ,delim = ".txt", ';'
    end

    for crv in ALL_CURVES
        ct = crv.curve_type
        pts = crv.points
        if isnothing(export_folder)
            fn = crv.name * ext
        else
            fn = joinpath(export_folder, crv.name * ext)
        end

        if sample_horizontal
            if ct == :bezier
                data = sample_cubic_bezier_curve_horizontally(pts; samples = N, lut_samples = 200)
            else
                interpolator = make_new_interpolator(pts,ct)
                data = eval_pts(interpolator; N)
            end

        else #arclen
            if ct == :bezier
                data = sample_cubic_bezier_curve(pts; samples = N, lut_samples = 200)
            else
                interpolator = make_new_interpolator(pts, ct)
                data = eval_pts_arclen(interpolator; N)
            end
        end
        
        #needs to be transformed
        X1, X2, Y1, Y2 = scale_rect
        tdata = transform_pts(data, (X1[1], X2[1], Y1[2], Y2[2]), plot_range, scale_type)
        writedlm(fn, tdata, delim)
        @info "Exported", fn
    end
    
    return nothing
end




function transform_pts(PTS::Vector{PT}, source, target, scale_type) where PT
    #simplest case where we ignore rotation and log space
    T = eltype(first(PTS))
    X1, X2, Y1, Y2 = source #scalars - plot coords
    x1, x2, y1, y2 = target #scalars - target coords

    out = zeros(eltype(X1), length(PTS), 2)
    for i in 1:2
        SP1, SP2 = source[2i-1], source[2i]
        TP1, TP2 = target[2i-1], target[2i]
        out[:,i] .= transform([p[i] for p in PTS],(SP1, SP2), (TP1, TP2), ScaleType(scale_type[i]))
        # if scale_type[i] == :linear
        #     out[:, i] .= transform_linear([p[i] for p in PTS],(SP1, SP2), (TP1, TP2))
        # else #log
        #     out[:, i] .= transform_log([p[i] for p in PTS], (SP1, SP2), (TP1, TP2))
        # end
    end
    return out
end

function transform(coords::Vector{T}, source::Tuple{T1, T1}, target::Tuple{T2, T2}, ::LinearScaleType) where {T, T1, T2}
    X1, X2 = source
    x1, x2 = target

    s = (x2 - x1) / (X2 - X1)
    TRN = -X1
    trn = x1
    return @. (coords + TRN) * s + trn
end


function transform(coords::Vector{T}, source::Tuple{T1, T1}, target::Tuple{T2, T2}, ::LogScaleType) where {T, T1, T2}
    X1, X2 = source
    x1, x2 = target
    @assert x1 > 0 && x2 > 0 "Both target coordinates must be positive for logarithmic scaling!"
    x1, x2 = log(x1), log(x2)

    s = (x2 - x1) / (X2 - X1)
    TRN = -X1
    trn = x1
    return @. exp((coords + TRN) * s + trn)

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

function reset_marker_positions!(imsize, markers)
    

    sz = imsize
    X1 = Point2f(0.1 * sz[1], 0.1 * sz[2])
    X2 = Point2f(0.9 * sz[1], 0.1 * sz[2])
    Y1 = Point2f(0.5 * sz[1], 0.1 * sz[2])
    Y2 = Point2f(0.5 * sz[1], 0.9 * sz[2])
    markers[] = [X1, X2, Y1, Y2]
    
    return nothing

end

function initial_curve(D::Dict{Symbol, Any}; reset = false)
    
    points = get_initial_curve_pts(D[:scale_rect][])
    CB = CubicBezierCurve(points)
    is_sm = CB.is_smooth
    color = D[:current_color][]
    ntinit = (;name= "Curve 01", color, points, is_smooth = is_sm)
    # @info "reset start"
    if reset
        D[:current_curve][] = CB
        
        D[:edited_curve_id][] = 1
        allc = D[:ALL_CURVES]
        length(allc)>2 && deleteat!(allc, 2:length(allc))
        D[:current_color][] = color
        # @info "edited", D[:edited_curve_id][]
        # @info "CC", D[:current_curve]
        update_curve!(D; ntinit...)
        # @info "rebuild"
        menu_curves = D[:curves_menu]
        rebuild_menu_options!(menu_curves, D[:ALL_CURVES])
        menu_curves.i_selected[] = 1
        # @info "switch"
        switch_other_curves_plot!(D[:ax], D[:ALL_CURVES], 1, D[:other_curve_plots])
        update_current_curve_controls!(D)
    end
    return ntinit
end

function is_bezier(s::Symbol)
    return s == :bezier
end