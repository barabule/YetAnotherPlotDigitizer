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
using Pkg
using DataInterpolations


include("typedefs.jl")
include("bezier.jl")
include("interpolation_curves.jl")
include("curvedata.jl")
include("gui.jl")

export main

end # module YetAnotherPlotDigitizer
