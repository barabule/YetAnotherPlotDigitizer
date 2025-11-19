


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

function cubic_bezier_segment_derivative(segment::Vector{PT}, t) where PT
    @assert length(controls) == 4 "A cubic segment requires exactly 4 control points."
    T = eltype(first(segment))
    t = T(t)

    P0, P1, P2, P3 = controls[1:4]

    Q0 = PT(3.0 * (P1 - P0))
    Q1 = PT(3.0 * (P2 - P1))
    Q2 = PT(3.0 * (P3 - P2))

    t_ = one(T) - t
    
    # B'(t) = Q0*t'^2 + 2*Q1*t'*t + Q2*t^2 (Quadratic Bézier formula)
    return PT(t_^2 * Q0 + 2.0 * t_ * t * Q1 + t^2 * Q2)
end


# Function to generate the piecewise cubic Bézier curve points
function piecewise_cubic_bezier(control_points::Vector{PT}; 
                                N_segments=50, #how many sub-segments to draw for each segment
                                ) where PT

    @assert (length(control_points)-1) % 3 == 0 "Must have 3k+1 control points, k = segments"

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




"""
    sample_arc_length(segment::Vector{PT}; samples = 100) where PT

Simple accumulation of linear segments.
Return a tuple (t, L) of t values and their corresponding arc lengths.
"""
function sample_arc_length(segment::AbstractVector{PT}; samples_per_segment = 100) where PT
    #returns a tuple of t values and their corresponding arc length
    T = eltype(first(segment))
    @assert length(segment) == 4 "Cubic segment must have 4 control points"
    ti = LinRange(0, 1, samples_per_segment)
    L = zeros(T, size(ti))
    P_prev = first(segment)
    for (i, t) in enumerate(ti) 
        P_curr = cubic_bezier_point(t, segment...)
        L[i] = norm(P_curr - P_prev)
        if i>1
            L[i] += L[i-1]
        end
        P_prev = P_curr
    end
    return (ti, L)
end


function create_arc_length_lut(control_points::Vector{PT}; samples_per_segment=50) where PT
    lut = (;index = [1], tval = [0.0], length = [0.0])
    

    cumulative_length = 0.0
    
    idx_main_pts = filter(i -> is_main_vertex(control_points, i), 1:length(control_points))
    num_segments = length(idx_main_pts) - 1

    for i in 1:num_segments
        i1, i2 = idx_main_pts[i], idx_main_pts[i+1]
        seg = view(control_points, i1:i2)
        (t, L) = sample_arc_length(seg; samples_per_segment)
        for j in 1:samples_per_segment
           
            push!(lut.index, i)
            push!(lut.tval, t[j])
            push!(lut.length, cumulative_length + L[j])
        end
        cumulative_length += last(L)
    end

    return lut, cumulative_length
end


function sample_cubic_bezier_curve(control_points::Vector{PT}; samples = 100, lut_samples = 20) where PT
    @assert (length(control_points)-1) % 3 == 0 "Must have 3k+1 control points, k = segments"
    
    LUT, total_arc_length = create_arc_length_lut(control_points; samples_per_segment = lut_samples)
     
    idx_main_pts = filter(i -> is_main_vertex(control_points, i), 1:length(control_points))
    
    l_samples = LinRange(0, total_arc_length, samples)
    PTS = [first(control_points)]
    for (i, len) in enumerate(l_samples)
        i==1 && continue
        if i == samples  
            push!(PTS, last(control_points))  
            break
        end

        idx = findfirst(l -> l >= len, LUT.length) #lookup
        #linear interpolate on the previous segment
        l1, l2 = LUT.length[idx-1], LUT.length[idx]
        t = (len - l1) / (l2 - l1)  #TODO this could be a starting point for Newton Raphson
        idseg = LUT.index[idx]
        i1, i2 = idx_main_pts[idseg], idx_main_pts[idseg+1]
        CP = view(control_points, i1:i2)
        t1, t2 = LUT.tval[idx-1], LUT.tval[idx]
        P1 = cubic_bezier_point(t1, CP...)
        P2 = cubic_bezier_point(t2, CP...)
        push!(PTS, (1-t)* P1 + t * P2)
    end
    return PTS
end

function add_bezier_segment!(vertices, mousepos)
    #identify where to put new point
    #TODO a better way to id the closest segment ?
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


