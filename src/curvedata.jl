struct CurveData{T}
    name::String
    points::Vector{SVector{2,T}}
    color::Color
    curve_type::Symbol
    is_smooth::Vector{Bool}
end


function add(CD::CurveData, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        segment_id = find_closest_projected_segment(C, pos)
        add_segment!(C, segment_id)
        return CurveData(
                    CD.name, 
                    C.points, 
                    CD.color, 
                    ct, 
                    C.is_smooth,
        )
    else
        add_point!(pts, pos)
        return CurveData(
                    CD.name, 
                    pts, 
                    CD.color, 
                    ct, 
                    CD.is_smooth,
        )
    end
    nothing
end


function rem(CD::CurveData, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        cpid = find_closest_control_point_to_position(C, pos)
        remove_control_point!(C, cpid)
        return CurveData(
                CD.name,
                C.points,
                CD.color,
                ct,
                CD.is_smooth
        )
    else
        min_pts = minimum_points(ct)
        remove_point!(pts, pos; min_pts)
        return CurveData(
                CD.name, 
                pts, 
                CD.color, 
                ct, 
                CD.is_smooth,
        )
    end
    nothing
end


function move(CD::CurveData, idx, pos)
    pts = CD.points
    ct = CD.curve_type
    if ct == :bezier
        C = CubicBezierCurve(pts, CD.is_smooth)
        move!(C, idx, pos)
        return CurveData(
            CD.name,
            C.points,
            CD.color,
            ct,
            CD.is_smooth
        )
    else
        move_itp!(pts, idx, pos)
        return CurveData(
            CD.name,
            pts,
            CD.color,
            ct,
            CD.is_smooth
        )
    end
    nothing
end


function update(CD::CurveData; 
                name = nothing,
                color = nothing,)


    pts = CD.points
    
    is_smooth = CD.is_smooth

    
    name =isnothing(name) ? CD.name : name
    @assert typeof(name) == typeof(CD.name)

    color = isnothing(color) ? CD.color : color
    @assert typeof(color) == typeof(CD.color)

    return CurveData(
        name,
        pts,
        color,
        CD.curve_type,
        is_smooth,
    )
end


function change_curve_type(CD::CurveData, ct::Symbol)
    @assert in(ct, InterpolationTypeList) "$ct not found in curve type list"

    ct_prev = CD.curve_type

    ct == ct_prev && return CD #no effect

    pts = CD.points
    N = length(pts)
    
    if !has_valid_number_of_points(N, ct)#check if valid amound of points for the new ct
        reset_curve!(pts, ct)
    end
    
    if ct == :bezier
        is_smooth = fill(false, div(length(pts)-1, 3) + 1)
        # @info "N", length(pts)
        # @info "is_smooth", is_smooth
    else
        make_valid!(pts, ct) #special for monotonic
        is_smooth = CD.is_smooth
    end

    return CurveData(
        CD.name,
        pts,
        CD.color,
        ct,
        is_smooth
    )
end


"""
    eval_curve(CD::CurveData; samples = 1000)

Evaluates CD in samples points uniformly in parameter space.
"""
function eval_curve(CD::CurveData; samples = 1000)# for plotting

    pts = CD.points
    ct = CD.curve_type

    if ct == :bezier
        nseg = number_of_cubic_segments(pts)
        # @info "nseg", nseg
        N_segments = round(Int, samples / nseg)
        return piecewise_cubic_bezier(pts; N_segments)
    else
        itp = make_new_interpolator(pts, ct)
        return eval_pts(itp; samples)
    end
    nothing
end


"""
    sample_curve(CD::CurveData; 
                    samples = 1000, 
                    arclen = false, 
                    lut_samples = 100)

Samples points from curve CD.
arclen - bool indicating if arclen sampling should be used (samples are approximately uniform along the curve arclenth)
If arclen is false - the samples are uniform in the 1st coordinate.
"""
function sample_curve(CD::CurveData; 
                    samples = 1000, 
                    arclen = false, 
                    lut_samples = 100) #for exporting

    pts = CD.points
    ct = CD.curve_type

    if ct == :bezier
        if arclen
            return sample_cubic_bezier_curve(pts; samples, lut_samples)
        else
            return sample_cubic_bezier_curve_horizontally(pts; samples, lut_samples)
        end
    end
    #not bezier
    interpolator = make_new_interpolator(pts, ct)
    if arclen
        return eval_pts_arclen(interpolator;  samples)
    else
        return eval_pts(interpolator; samples)
    end
    nothing
end


function toggle_sharp(CD::CurveData, pos)
    ct = CD.curve_type
    ct == :bezier || return CD

    pts = CD.points
    C = CubicBezierCurve(pts, CD.is_smooth)
    cp_id = find_closest_control_point_to_position(C, pos)
    toggle_smoothness(C, cp_id)

    return CurveData(
        CD.name,
        C.points,
        CD.color,
        ct,
        C.is_smooth
    )
end

"""
    CurveData(bbox::Tuple{T, T, T, T}, name, color;
                    itp = :bezier::Symbol) where T<:Real

Construct a default curve from a bounding box.
bbox should be a tuple with (xmin, xmax, ymin, ymax) values.
Makes a new curve of interpolation type given by Symbol itp with minimum amount of points.
4 for Bezier, 2 for Linear etc...
"""
function CurveData(bbox::Tuple{T, T, T, T}, name, color;
                    itp = :bezier::Symbol) where T<:Real

    @assert in(itp, InterpolationTypeList)

    N = minimum_points(itp)
    x1, x2, y1, y2 = bbox
    #generate points in a line from P1 to PN
    P1 = SVector{2}(0.8 * x1 + 0.2 * x2, 0.8 * y1 + 0.2 * y2)
    PN = SVector{2}(0.2 * x1 + 0.8 * x2, 0.2 * y1 + 0.8 * y2)

    pts = [P1]
    m = N - 2
    if m>0
        for i in 1:m
            t = (i)/(N-1)
            push!(pts, P1 * (1-t) + PN * t)
        end
    end
    push!(pts, PN)
    
    is_smooth = [false, false]

    return CurveData(
        name,
        pts,
        color,
        itp,
        is_smooth
    )
end

function find_closest_point_to_position(CD::CurveData, pos; thresh = nothing::Union{Nothing, Real})

    pts = CD.points

    idx = -1
    dmin = Inf

    for i in eachindex(pts)
        pt = pts[i]
        # dist = max(abs.(pt - pos)...)
        dist = norm(pt - pos)
        if dist < dmin
            idx = i
            dmin = dist
        end
    end
    if !isnothing(thresh) && dmin >= thresh
        return -1
    end
    return idx
end
