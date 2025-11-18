
function bezier_fit_fig(results::Ref{Dict{String, Any}};
                                PICK_THRESHOLD = 20,
                                )

     
    
    data = results[]["data"]
    strain = data.strain
    stress = data.stress
    min_strain, max_strain = extrema(strain)
    min_stress, max_stress = extrema(stress)
    strain = collect(strain)
    stress = collect(stress) 
    # push!(results, "scale factors" => (;max_strain, max_stress))
    P1 = Point2f(0, 0)
    P4 = Point2f(last(strain), last(stress))

    mp = findfirst(x-> x>0.2*max_strain, strain)
    P2 = Point2f(strain[mp], 1.4 * stress[mp])
    mp = findfirst(x -> x> 0.8 * max_strain, strain)
    P3 = Point2f(strain[mp], 1.4 * stress[mp])

    initial_cpoints = Point2f[P1, P2, P3, P4]
    
    
    cpoints = Observable(initial_cpoints) 
    
    
    bezier_curve = lift(cpoints) do pts
        curve = piecewise_cubic_bezier(pts)
        
        if haskey(results[], "bezier fit")
            results[]["bezier fit"] = curve
            results[]["status"] = 1
            # @info "updated", results[]["status"]
        else
            push!(results[], "bezier fit"=> curve)
        end
        
        curve
    end

    
    fig = Figure()
    ax = Axis(fig[1, 1], title = "Interactive Piecewise Cubic Bézier Curve",
                # aspect = DataAspect(), #maybe not needed
                )

    label_help = Label(fig, "Press \"a\" to add a segment, \"d\" to delete one.",
                    fontsize= 16,
                    color = :grey10,
                    halign =:center,
                    valign = :top,
                    padding = (10, 0, 0, 10),
                    tellwidth = false,
                    )
    fig[0,1] = label_help
    #
    deregister_interaction!(ax, :rectanglezoom)

    #plot the data
    if !isnothing(data)
        scatter!(ax, strain, stress, color= :grey50, alpha=0.5, label = "Data")
    end

    # final Bézier curve
    lines!(ax, bezier_curve, color = :black, linewidth = 4, label = "Bézier Curve")

    # control polygon
    lines!(ax, cpoints, color = (:grey, 0.5), linestyle = :dash, label = "Control Polygon")

    #control pts
    scatter_plot = scatter!(ax, cpoints, markersize = 15, color = :red, strokecolor = :black, strokewidth = 1, marker = :circle, label = "Control Points")

    # --- 3. Interactivity: Dragging Control Points ---
    # Find the index of the closest control point when the mouse is pressed
    dragged_index = Observable{Union{Nothing, Int}}(nothing)
    
    
     ##################################EVENTS###########################################################################

    # Interaction for pressing the mouse button
    on(events(fig).mousebutton, priority = 10) do event
        # Only react to left mouse button press
        if event.button == Mouse.left && event.action == Mouse.press
            # Pick the closest control point on the scatter plot
            # `pick` returns the plot object and the index of the picked element
            plot, index = pick(ax.scene, events(ax).mouseposition[])
            
            # Check if a control point was picked
            if plot === scatter_plot && index !== nothing
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
            new_data_pos = Makie.mouseposition(ax.scene)
            
            # Update the specific control point's position
            current_points = cpoints[]
            move_control_vertices!(current_points, dragged_index[], new_data_pos)
            cpoints[] = current_points # Notify the Observable of the change
            
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

    
    
    on(events(fig).keyboardbutton, priority = 10) do event
        if event.action == Keyboard.press
            current_points = cpoints[]
            
            if event.key == Keyboard.a # Add point
                # Check if we have a valid mouse position in data coordinates
                data_pos = try Makie.mouseposition(ax.scene) catch; return Consume(false) end
                
                add_bezier_segment!(current_points, data_pos)
                # @info "current_points",current_points
                cpoints[] = current_points
                return Consume(true)
            
            elseif event.key == Keyboard.d # delete closest main segment (removes 3 points from curve)
                data_pos = try Makie.mouseposition(ax.scene) catch; return Consume(false) end
                remove_bezier_segment!(current_points, data_pos)
                cpoints[] = current_points
            end
            
        end
        return Consume(false)
    end

    # Set up the Axis limits to encompass the initial points
    autolimits!(ax)
    
    # Add a Legend (optional, but helpful)
    fig[1, 2] = Legend(fig, ax)

    # Display the figure
    screen = GLMakie.Screen()
    display(screen, fig)

    wait(fig.scene)

    return nothing
end

function cubic_bezier_point(t::Real, P0, P1, P2, P3)
    # The standard cubic Bézier formula: B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
    a = 1 - t
    b = a * a
    c = b * a
    w0 = c
    w1 = 3 * b * t
    w2 = 3 * a * t^2
    w3 = t^3
    return P0 * w0 + P1 * w1 + P2 * w2 + P3 * w3
end

# Function to generate the piecewise cubic Bézier curve points
function piecewise_cubic_bezier(control_points::Vector{PT}; 
                                N_segments=50, #how many sub-segments to draw for each segment
                                ) where PT

    curve_points = PT[]
    n_points = length(control_points)

    if n_points < 4
        return curve_points
    end

    #total pts 3k+1 for k segments
    num_segments = div(n_points - 1, 3)

    cache = zeros(PT, N_segments+1)
    ti = (0:N_segments) * (1/N_segments) #reusable
    for k in 0:(num_segments - 1)
        
        idx = 3 * k + 1
        P0, P1, P2, P3 = control_points[idx], 
                        control_points[idx + 1], 
                        control_points[idx + 2], 
                        control_points[idx + 3]

        # Generate points for this segment
        for i in 0:N_segments
            t = ti[i+1]
            cache[i+1] = cubic_bezier_point(t, P0, P1, P2, P3)
        end
        push!(curve_points, cache...)
    end

    return curve_points
end


function add_bezier_segment!(vertices, mousepos)
    #identify where to put new point
    Q, i1, i2 = find_closest_main_segment_horizontal(vertices, mousepos) #closest point on control polygon to mouseposition
    # @info "Q", Q, "i1 ", i1, " i2 ", i2
    V1, V2 = vertices[i1+1], vertices[i2-1] #closest control verts
    # @info "V1", V1, "V2", V2
    PT = eltype(vertices)
    C1 = PT(@. 0.75 * V1 + 0.25 * V2)
    C2 = PT(@. 0.5 * V1 + 0.5 * V2)
    C3 = PT(@. 0.25 * V1 + 0.75 * V2)
    # @info "C1", C1, "C2", C2, "C3", C3
    add_to_middle!(vertices, i1+2, (C1, C2, C3))
    
    return nothing
end


function add_to_middle!(arr::Vector, idx, els)
    
    @assert firstindex(arr)<= idx <= lastindex(arr)
    T = eltype(arr)
    @assert eltype(els) == T
    

    if idx != lastindex(arr)
        last = arr[idx:end]
        deleteat!(arr,idx:length(arr))
        push!(arr, els...)
        push!(arr, last...)
    elseif idx == lastindex
        push!(arr, els...)
    elseif idx== firstindex
        pushfirst!(arr, els...)
    end

    return nothing
end

function remove_bezier_segment!(vertices, mousepos)
    
    length(vertices) <= 4 && return nothing #
    Q, i1, i2 = find_closest_main_segment_horizontal(vertices, mousepos)
    @info "mousepos", mousepos, " Q ", Q, "i1", i1, "i2", i2
    deleteat!(vertices, (i1, i1+1, i2-1))
    return nothing
end


function find_closest_main_segment_horizontal(vertices, P)

    
    segments = div(length(vertices)-1, 3)
    x= P[1]
    
    for k in 0:(segments-1)
        idx = 3k + 1
        i1, i2 = idx, idx+3
        
        V1, V2 = vertices[i1], vertices[i2]
        x1, x2 = V1[1], V2[1]
        
        if k==0
            if x <= x1
                Q = 0.5 * V1 + 0.5 *V2
                
                return (Q, i1, i2)
            end
        end
        if (k==segments-1)
            if x >= x2
                Q = 0.5 * V1 + 0.5 *V2
                
                return (Q, i1, i2)
            end
        end
        if x1 < x < x2
            t = (x - x1)/(x2 - x1)
            Q = (1-t)*V1 + t * V2
            
            return (Q, i1, i2)
        end
    end

end


function find_closest_main_segment(vertices, P) 
    
    
    num_segments = div(length(vertices)-1, 3)
    dmin = Inf
    Qbest = P
    idxbest = (1, 4) #default
    for k in 0:(num_segments - 1)
        
        idx = 3 * k + 1
        i1, i2 = idx, idx+3
        M1, M2 = vertices[i1], vertices[i2]
        (Q, d, t) = closest_point_to_line_segment(M1, M2, P)
        @info "t ", t, "d", d
        if 0 <= t <= 1
            return (Q, i1, i2)
        end
        
        if d < dmin
            dmin = d
            Qbest = Q
            idxbest = (i1, i2)
        end
    end
    i1, i2 = idxbest
    @assert (i2 - i1) == 3
    return (Qbest, idxbest...)
end


function closest_point_to_line_segment(L1, L2, P) #closest pt 
    PL1 = P - L1
    L21 = L2 - L1

    snL21 = dot(L21, L21) #squared norm
    
    Q = L1 + dot(PL1, L21) * L21 / snL21 #projected point
    if L1[1] !==L2[1]
        t = (L2[1] - Q[1]) / (L21[1])
    else
        t = (L2[2] - Q[2] / (L21[2]))
    end
    return (Q, norm(P-Q), t)
end


function move_control_vertices!(vertices, idx, new_pos)
    
    old_pos = vertices[idx]
    vertices[idx] = new_pos #move the vertex to new_pos


    #basically behaves like Inkscape
    #case 1  - the moved vertex is a main control vertex (interpolating point)
    # move all attached vertices by the same amount to preserve tangency
    if is_main_vertex(vertices, idx)
        if idx== firstindex(vertices)
            attached = (idx+1)
        elseif idx == lastindex(vertices)
            attached = (idx-1)
        else
            attached = (idx-1, idx+1)
        end
        dmove = new_pos - old_pos
        for i in attached
            vertices[i] += dmove
        end
        return nothing
    end

    #case 2 the moved vertex is a secondary control vertex
    #rotate the opposite vertex around the nearest main vertex 
    if idx-1 == firstindex(vertices) || idx + 1 == lastindex(vertices) #nothing to do
        return nothing
    end

    if is_main_vertex(vertices, idx-1)
        center = vertices[idx-1]
        V = vertices[idx-2]
        idnext = idx-2
    else
        center = vertices[idx+1]
        V = vertices[idx+2]
        idnext = idx+2
    end
    L = norm(V-center)
    vertices[idnext] = normalize(center - vertices[idx]) * L + center #preserve the segment length
    return nothing
end


function is_main_vertex(vertices, idx)
    @assert firstindex(vertices) <= idx <= lastindex(vertices)
    i = mod(idx, 3) #1 2 0 1 2 0 1 -> 1, 4, 7
    return i==1
end


