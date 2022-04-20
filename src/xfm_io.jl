"""
Axis typed from MINC volume, TODO: make this compatible with NIFTI ?
"""
@enum XFM begin
    MINC2_XFM_LINEAR                 = Cint(minc2_simple.MINC2_XFM_LINEAR)
    MINC2_XFM_THIN_PLATE_SPLINE      = Cint(minc2_simple.MINC2_XFM_THIN_PLATE_SPLINE)
    MINC2_XFM_USER_TRANSFORM         = Cint(minc2_simple.MINC2_XFM_USER_TRANSFORM)
    MINC2_XFM_CONCATENATED_TRANSFORM = Cint(minc2_simple.MINC2_XFM_CONCATENATED_TRANSFORM)
    MINC2_XFM_GRID_TRANSFORM         = Cint(minc2_simple.MINC2_XFM_GRID_TRANSFORM)
end


"""
minc2_simple XFM transform handle
"""
mutable struct TransformHandle
    x::Ref
    function TransformHandle()
    ret = new( Ref(minc2_simple.minc2_xfm_allocate0()) )

    finalizer(x -> c"minc2_simple.minc2_xfm_destroy"(x[]), ret.x)
    return ret
    end
end



"""
Open transform xfm file, return handle
"""
function open_xfm_file(fname::String)::TransformHandle
    h = TransformHandle()
    @minc2_check minc2_simple.minc2_xfm_open(h.x[], fname)
    return h
end

"""
Save information into file
"""
function save_xfm_file(h::TransformHandle , path::String)
    @minc2_check  minc2_simple.minc2_xfm_save(h.x[],path)
end

"""
Transform point x,y,z
"""
function transform_point(h::TransformHandle, xyz::Vector{Float64})::Vector{Float64}
    xyz_out=zeros(Float64,3)
    @minc2_check  minc2_simple.minc2_xfm_transform_point(h.x[],xyz,xyz_out)
    return xyz_out
end

"""
Transform point x,y,z
"""
function inverse_transform_point(h::TransformHandle, xyz::Vector{Float64})::Vector{Float64}
    xyz_out=zeros(Float64,3)
    @minc2_check  minc2_simple.minc2_xfm_inverse_transform_point(h.x[],xyz,xyz_out)
    return xyz_out
end

"""
Invert transform
"""
function invert_transform(h::TransformHandle)
    @minc2_check  minc2_simple.minc2_xfm_invert(h.x[])
end

"""
Get number of transformations
"""
function get_n_concat(h::TransformHandle)::Int
    n = Ref{Int}(0)
    @minc2_check minc2_simple.minc2_xfm_get_n_concat( h.x[], n )
    return n[]
end

"""
Get transform type 
"""
function get_n_type(h::TransformHandle;n::Int=0)::XFM
    t = Ref{Int}(0)
    @minc2_check minc2_simple.minc2_xfm_get_n_type( h.x[], n, t )
    return XFM(t[])
end

function get_grid_transform(h::TransformHandle;n::Int=0)        
    c_file=Ref{c"char *"}()
    inv=Ref{Int}(0)

    @minc2_check minc2_simple.minc2_xfm_get_grid_transform(h.x[],n,inv,c_file)
    r=String(c_file)
    Libc.free(ptr)

    return (r,inv[]!=0)
end

function get_linear_transform(h::TransformHandle;n::Int=0)
    mat=zeros(Float64,4,4)
    @minc2_check minc2_simple.minc2_xfm_get_linear_transform(h.x[], n, Base.unsafe_convert(Ptr{Cdouble},mat))
    return transpose(mat)
end

function get_linear_transform_param(h::TransformHandle;n::Int64=0,center::Union{Nothing,Vector{Float64}}=nothing)
    if isnothing(center)
        center=zeros(Float64,3)
    end

    translations=zeros(Float64,3)
    scales=zeros(Float64,3)
    scales=zeros(Float64,3)
    shears=zeros(Float64,3)
    rotations=zeros(Float64,3)
    @minc2_check minc2_simple.minc2_xfm_extract_linear_param(h.x[],n,center,translations,scales,shears,rotations)

    return (center=center,translations=translations,scales=scales,shears=shears,rotations=rotations)
end

function append_linear_transform(h::TransformHandle,lin::Matrix{Float64})
    @minc2_check minc2_simple.minc2_xfm_append_linear_transform(h.x[],lin)
end

# TODO: 
function append_grid_transform(h::TransformHandle,grid_file::String;inv::Bool=false)
    @minc2_check minc2_simple.append_grid_transform(h.x[],grid_file,inv)
end

function concat_xfm(h::TransformHandle,i::TransformHandle)
    @minc2_check minc2_simple.minc2_xfm_concat_xfm(h.x[], i.x[])
end
