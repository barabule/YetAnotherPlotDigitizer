


function cubic_bezier_point(t::Real, P0::PT, P1::PT, P2::PT, P3::PT) where PT
    # The standard cubic Bézier formula: B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
    a = 1 - t
    b = a * a
    c = b * a
    w0 = c
    w1 = 3 * b * t
    w2 = 3 * a * t^2
    w3 = t^3
    return PT(P0 * w0 + P1 * w1 + P2 * w2 + P3 * w3)
end


function cubic_bezier_segment_derivative(t, P0::PT, P1::PT, P2::PT, P3::PT) where PT
    
    T = eltype(P0)
    
    Q0 = PT(3.0 * (P1 - P0))
    Q1 = PT(3.0 * (P2 - P1))
    Q2 = PT(3.0 * (P3 - P2))

    t_ = one(T) - t
    return PT(t_^2 * Q0 + 2.0 * t_ * t * Q1 + t^2 * Q2)
end


# Function to generate the piecewise cubic Bézier curve points
function piecewise_cubic_bezier(control_points::Vector{PT}; 
                                N_segments=50, #how many sub-segments to draw for each segment
                                ) where PT

    n_points = length(control_points)
    @assert (n_points - 1) % 3 == 0 "Must have 3k+1 control points for k = segments!"

    curve_points = PT[]
    
    #total pts 3k+1 for k segments
    num_segments = div(n_points - 1, 3)

    cache = zeros(PT, N_segments+1)
    ti = (0:N_segments) * (1/N_segments) #reusable for each segment
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


"""
    create_arc_length_lut(control_points::Vector{PT}; samples_per_segment=50) where PT

Precomputes for each cubic segment in control_points the arclength corresponding to the parameter value.
Return a lut and the total length of the curve.
The lut is a named tuple with 3 fields: 'index' (corresponding segment), 'tval' - parameter value and 'length' - the arclength
The 'length' field is cumulative!
"""
function create_arc_length_lut(control_points::Vector{PT}; samples_per_segment=50) where PT
    lut = (;index = [1], tval = [0.0], length = [0.0])
    

    cumulative_length = 0.0
    
    idx_main_pts = filter(i -> is_control_point(i), 1:length(control_points))
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


function create_horizontal_lut(control_points::Vector{PT}; samples_per_segment= 10) where PT
    

    nseg = div(length(control_points)-1, 3) #4 -> 1, 7 -> 2
    ti = LinRange(0, 1, samples_per_segment)
    T = eltype(first(control_points))
    lut = (;index = repeat(collect(1:nseg), inner = samples_per_segment),
            tval = repeat(ti, nseg),
            xval = Vector{T}())
    
    
    xvalbuf = zeros(eltype(first(control_points)), samples_per_segment)
    for i in 1:nseg
        
        idx_start = 3 * (i-1) + 1
        P0, P1, P2, P3 = control_points[idx_start], control_points[idx_start+1], control_points[idx_start+2], control_points[idx_start+3]
        for j in 1:samples_per_segment
            xvalbuf[j] = cubic_bezier_point(ti[j], P0, P1, P2, P3)[1]
        end
        push!(lut.xval, xvalbuf...)
    end
    return lut
end


function sample_cubic_bezier_curve(control_points::Vector{PT}; samples = 100, lut_samples = 20) where PT
    @assert (length(control_points)-1) % 3 == 0 "Must have 3k+1 control points, k = segments"
    
    LUT, total_arc_length = create_arc_length_lut(control_points; samples_per_segment = lut_samples)
     
    idx_main_pts = filter(i -> is_control_point(i), 1:length(control_points))
    
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


function sample_cubic_bezier_curve_horizontally(control_points::Vector{PT}; samples = 100, lut_samples =20) where PT

    LUT =  create_horizontal_lut(control_points; samples_per_segment = lut_samples)
    xfirst = first(control_points)[1]
    xlast = last(control_points)[1]

    xrange = LinRange(xfirst, xlast, samples) 

    PTS = [first(control_points)]
    @assert samples >= 2 "At least 2 samples are needed!"
    
    for i in 2:samples-1
        xi = xrange[i]
        
        id_hi = findfirst(x -> x > xi, LUT.xval)
        id_lo = id_hi-1
        
        xhi, xlo = LUT.xval[id_hi], LUT.xval[id_lo] #bracketing interval
        
        u = (xi - xlo)/ (xhi - xlo) 
        t = LUT.tval[id_lo] * (1-u) + LUT.tval[id_hi] * u
        
        seg = LUT.index[id_hi] 
        id_pt = 3 * (seg-1)+ 1
        
        P0, P1, P2, P3 = control_points[id_pt], control_points[id_pt+1], control_points[id_pt+2], control_points[id_pt+3]
        push!(PTS, cubic_bezier_point(t, P0, P1, P2, P3))
    end
    push!(PTS, last(control_points))

end


function add_to_middle!(arr::Vector{T}, idx, els) where T

    @assert 1<=idx<=lastindex(arr)
    @assert eltype(els) == T
    splice!(arr, idx+1:idx, els)
    nothing
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
    # return (Q, norm(P-Q), t)
    return (;projection = Q,
            distance = norm(P-Q),
            parameter = t)
end

