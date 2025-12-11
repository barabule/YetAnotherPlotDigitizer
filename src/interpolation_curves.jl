
ITP = DataInterpolations.AbstractInterpolation
#allowable interpolation types
const InterpolationTypeList = (
    :bezier,
    :linear,
    :akima,
    :constant,
    :smoothedconstant,
    :quadraticspline,
    :cubicspline,
    :pchip,
    # :bspline,
)

const InterpolationTypeNames = (
    "Bezier",
    "Linear",
    "Akima",
    "Constant",
    "SmoothedConstant",
    "QuadraticSpline",
    "CubicSpline",
    "PCHIP",
    # "BSpline",
)


function make_new_interpolator(pts::Vector{PT}, interpolatortype::Symbol) where PT
    if interpolatortype == :bezier
        return nothing 
    end
    u, t = last.(pts), first.(pts)
    if !in(interpolatortype, InterpolationTypeList)
        error("Interpolation type not found: $(interpolatortype)")
    end
    @assert issorted(t) "t must be sorted!"

    if interpolatortype == :linear
        itp = LinearInterpolation
    end
    
    if interpolatortype == :akima
        itp = AkimaInterpolation
    end
    
    if interpolatortype == :constant
        itp = ConstantInterpolation
    end
    
    if interpolatortype == :smoothedconstant
        itp = SmoothedConstantInterpolation
    end
    
    if interpolatortype == :cubicspline
        itp = CubicSpline
    end
    
    if interpolatortype == :pchip
        itp = PCHIPInterpolation
    end
    
    if interpolatortype == :quadraticspline
        itp = QuadraticSpline
    end

    if interpolatortype == :bspline
        return BSplineInterpolation(u, t, 3, :ArcLen, :Uniform)
    end
    return itp(u, t)
end


function find_closest(pts::Vector{PT}, pt) where PT
     
    dmin, idx = Inf, -1
    for i in eachindex(pts)
        dist = norm(pt - pts[i])
        if dist < dmin
            dmin = dist
            idx = i
        end
    end
    return idx
end


function move!(pts::Vector{PT}, idx, position) where PT
    #check if moving the point would produce an unsorted array 
    t = position[1]
    invalid = (idx !=1 && pts[idx-1][1]>=t) || (idx !=lastindex(pts) && pts[idx+1][1]<= t)
    if !invalid
        pts[idx] = PT(position)
    end
    return nothing
end


function eval_pts(itp::ITP; N= 1000)
    t = itp.t
    ti = LinRange(first(t), last(t), N)
    ui = itp(ti)
    
    return [SVector{2}(ti[i], ui[i]) for i in eachindex(ti)]
end


function add_point!(pts::Vector{PT}, pos) where PT
    idx = -1
    for (i, point) in enumerate(pts)
        if point[1] > pos[1]
            idx = i
            break
        end
    end
    if idx == -1
        push!(pts, PT(pos...))
    else
        splice!(pts, idx:idx-1, [PT(pos...)]) 
    end
    nothing
end

function minimum_points(itp_type::Symbol)
    if in(itp_type, (:akima, :cubicspline, :quadratic, :pchip) )
        return 3
    elseif in(itp_type, (:bspline, :bezier) )
        return 4 #degree 3
    else
        return 2
    end
end


function remove_point!(pts::Vector{PT}, pos::PT; min_pts = 2) where PT
    length(pts)<=min_pts && return nothing
    idx = find_closest(pts, pos)
    deleteat!(pts, idx)
    nothing
end