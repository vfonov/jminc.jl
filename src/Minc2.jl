module Minc2

    module minc2_simple
        using LIBMINC_jll
        using CBinding
        # Main.SYSROOT...,
        c`$([
            "-I$(LIBMINC_jll.artifact_dir)/include",
            "-L$(dirname(LIBMINC_jll.libminc2_path))", 
            "-L$(dirname(LIBMINC_jll.libminc2_simple_path))", 
            "-llibminc2-simple","-llibminc2",
        ])`

        c"""
        #include <minc2-simple.h>
        """ji

        #c"typedef double minc2_dir_cos[3];"j
    end

    using CBinding
    using .minc2_simple


    @enum DIM begin
        DIM_UNKNOWN = Cint(minc2_simple.MINC2_DIM_UNKNOWN)
        DIM_X = Cint(minc2_simple.MINC2_DIM_X  )
        DIM_Y = Cint(minc2_simple.MINC2_DIM_Y )
        DIM_Z = Cint(minc2_simple.MINC2_DIM_Z )
        DIM_TIME = Cint(minc2_simple.MINC2_DIM_TIME )
        DIM_VEC  = Cint(minc2_simple.MINC2_DIM_VEC )
        DIM_END  = Cint(minc2_simple.MINC2_DIM_END)
    end

    # TODO: double check?
    minc2_spatial=Dict(Cint(minc2_simple.MINC2_DIM_X)=>1,
                       Cint(minc2_simple.MINC2_DIM_Y)=>2,
                       Cint(minc2_simple.MINC2_DIM_Z)=>3)

    # map Julia types to minc2 data types
    julia_to_minc2 = Dict(
       Type{Int8}     => Cint(minc2_simple.MINC2_BYTE ),
       Type{Int16}    => Cint(minc2_simple.MINC2_SHORT),
       Type{Int32}    => Cint(minc2_simple.MINC2_INT ),
       Type{Float32}  => Cint(minc2_simple.MINC2_FLOAT ),
       Type{Float64}  => Cint(minc2_simple.MINC2_DOUBLE ),
       Type{String}   => Cint(minc2_simple.MINC2_STRING ),
       Type{UInt8}    => Cint(minc2_simple.MINC2_UBYTE ),
       Type{UInt16}   => Cint(minc2_simple.MINC2_USHORT ),
       Type{UInt32}   => Cint(minc2_simple.MINC2_UINT ),
       Type{Complex{Int16}} => Cint(minc2_simple.MINC2_SCOMPLEX ),
       Type{Complex{Int32}} => Cint(minc2_simple.MINC2_ICOMPLEX ),
       Type{Complex{Float32}} => Cint(minc2_simple.MINC2_FCOMPLEX ),
       Type{Complex{Float64}} => Cint(minc2_simple.MINC2_DCOMPLEX ),
       Type{Any}  => Cint(minc2_simple.MINC2_UNKNOWN)
    )

    const _minc2_dimension=c"minc2_simple.struct minc2_dimension"
    

    # map MINC2 types to Julia
    minc2_to_julia=Dict([(j,i) for (i,j) in julia_to_minc2])

    @enum STATUS begin
        # minc2 status
        SUCCESS  = Cint(minc2_simple.MINC2_SUCCESS)
        ERROR    = Cint(minc2_simple.MINC2_ERROR)
    end

    macro minc2_check( ex ) # STATUS::SUCCESS
        return :($(esc(ex)) == 0 ? $(nothing) : throw(SystemError("MINC2 error")))
    end

    mutable struct VolumeHandle
        x::Ref
        function VolumeHandle()
          ret = new( Ref(minc2_simple.minc2_allocate0()) )

          finalizer(x -> c"minc2_simple.minc2_destroy"(x[]), ret.x)
          return ret
        end
    end

    """
    Structure describing spatial orientation of the minc file
    """
    mutable struct MincHeader
        dims::Vector{Int32}
        start::Vector{Float64}
        step::Vector{Float64}
        dir_cos::Matrix{Float64}
        dir_cos_valid::Vector{Bool}
        # TODO: figure out how to make it compatible with other libraries
        axis::Vector{Int32}

        function MincHeader(ndim)
            new(zeros(ndim),
                zeros(ndim), 
                ones(ndim), 
                Matrix{Float64}(undef, ndim, 3),
                zeros(Bool,ndim),
                zeros(ndim))
        end
    end

    """
    Open minc file, return handle
    """
    function open_minc_file(fname::String)
        h = VolumeHandle()
        @minc2_check minc2_simple.minc2_open(h.x[], fname)
        return h
    end

    """
    Define new minc file structure, return handle
    """
    function define_minc_file(hdr::MincHeader,::Type{Store}=Float32,::Type{Repr}=Store) where {Store,Repr}
        h = VolumeHandle()

        _store_type = julia_to_minc2[Type{Store}]
        _representation_type = julia_to_minc2[Type{Repr}]
        
        _dims = [
            c"minc2_simple.struct minc2_dimension"(
                    id=hdr.axis[i],
                    length=j,
                    start=hdr.start[i],
                    step=hdr.step[i],
                    have_dir_cos=Int(hdr.dir_cos_valid[i]),
                    dir_cos=Tuple(hdr.dir_cos[i,:])
                ) for (i,j) in enumerate(hdr.dims)
        ]
        push!(_dims,c"minc2_simple.struct minc2_dimension"(id=Cint(minc2_simple.MINC2_DIM_END)))

        @minc2_check minc2_simple.minc2_define(h.x[], _dims, _store_type, _representation_type)

        # TODO: fix this
        _global_scaling = 0
        _slice_scaling  = 0 
        if _store_type != _representation_type && !(Store==Float32 && Repr==Float64 || Store==Float64 && Repr==Float32)
            _global_scaling = 1 # slice scaling is not completely supported yet in minc2-simple
            #_slice_scaling = 1
        end
        @minc2_check minc2_simple.minc2_set_scaling(h.x[],_global_scaling,_slice_scaling )

        return h
    end

    """
    Create empty minc file on disk, structure need to be defined in advance
    """
    function create_minc_file(h::VolumeHandle, path::String)
        @minc2_check minc2_simple.minc2_create(h.x[], path )
    end

    """
    Close currently open minc file, commit data on disk
    """
    function close_minc_file(h::VolumeHandle)
        @minc2_check minc2_simple.minc2_close( h.x[] )
    end

    """
    Query number of dimensions in the minc file
    """
    function ndim(h::VolumeHandle)
        dd = Ref{Int}(0)
        @minc2_check minc2_simple.minc2_ndim( h.x[], dd )
        return dd[]
    end

    """
    Prepare to read volume in standard order: [V,X,Y,Z,TIME]
    """
    function setup_standard_order(h::VolumeHandle)
        @minc2_check minc2_simple.minc2_setup_standard_order(h.x[])
    end
    
    function _hdr_convert!(hdr,dd)
        for i = 1:length(hdr.start)
            hdr.dims[i] = dd[][i].length
            hdr.start[i] = dd[][i].start
            hdr.step[i] = dd[][i].step
            if dd[][i].have_dir_cos != 0
                hdr.dir_cos[i,:] .= dd[][i].dir_cos[:]
                hdr.dir_cos_valid[i] = true
            else # TODO: do it only for spatial dimension
                hdr.dir_cos[i,:] = zeros(3)
                if haskey(minc2_spatial, dd[][i].id)  
                    hdr.dir_cos[i,minc2_spatial[dd[][i].id]] = 1.0
                end
                hdr.dir_cos_valid[i] = false
            end
            hdr.axis[i] = dd[][i].id
        end
        return hdr
    end

    """
    Return volume representation header
    """
    function representation_header(h::VolumeHandle)::MincHeader
        hdr = MincHeader(ndim(h))
        dd = Ref{c"minc2_simple.struct minc2_dimension *"}()

        # this is supposed to be in a standard order
        @minc2_check minc2_simple.minc2_get_representation_dimensions(h.x[], dd)

        return _hdr_convert!(hdr,dd)
    end

    """
    return volume on-disk stucture header
    """
    function store_header(h::VolumeHandle)::MincHeader
        hdr = MincHeader(ndim(h))
        dd = Ref{c"minc2_simple.struct minc2_dimension *"}()

        # this is supposed to be in a standard order
        @minc2_check minc2_simple.minc2_get_store_dimensions(h.x[], dd)

        return _hdr_convert!(hdr,dd)
    end


    """
    Read the actual volume using handle
    return volume, storage header
    """
    function read_minc_volume_raw(h::VolumeHandle, ::Type{T}=Float32 ) where {T}
        # TODO: use ImageMetadata to store header contents?
        store_hdr = store_header( h )
        volume = Array{T}(undef, store_hdr.dims...)

        @minc2_check minc2_simple.minc2_load_complete_volume(h.x[], Base.unsafe_convert(Ptr{Cvoid},volume), julia_to_minc2[Type{T}] )
        return volume, store_hdr
    end

    """
    Read the actual volume using handle
    return volume, representation header,storage header
    """
    function read_minc_volume_std(h::VolumeHandle, ::Type{T}=Float32 ) where {T}
        # TODO: use ImageMetadata to store header contents?
        setup_standard_order( h )
        store_hdr = store_header( h )
        hdr = representation_header( h )
        volume = Array{T}(undef, hdr.dims...)

        @minc2_check minc2_simple.minc2_load_complete_volume(h.x[], Base.unsafe_convert(Ptr{Cvoid},volume), julia_to_minc2[Type{T}] )
        return volume, hdr, store_hdr
    end

    """
    Read the actual volume using path
    return volume, representation header,storage header
    """
    function read_minc_volume_std(path::String, ::Type{T}=Float32 ) where {T}
        handle = open_minc_file(path)
        volume, hdr, store_hdr = read_minc_volume_std(handle,T)
        close_minc_file(handle)

        return volume, hdr, store_hdr
    end

    """
    Read the actual volume using path
    return volume, representation header,storage header
    """
    function read_minc_volume_raw(path::String, ::Type{T}=Float32 ) where {T}
        handle = open_minc_file(path)
        volume, store_hdr = read_minc_volume_raw(handle,T)
        close_minc_file(handle)

        return volume, store_hdr
    end


    """
    write full volume to file, file should be defined and created
    return nothing
    """
    function write_minc_volume_raw(h::VolumeHandle, volume::Array{T} ) where {T}
        @minc2_check minc2_simple.minc2_save_complete_volume(h.x[], Base.unsafe_convert(Ptr{Cvoid},volume),julia_to_minc2[Type{T}])
        return nothing
    end


    """
    write full volume to file, file should be defined and created
    return nothing
    """
    function write_minc_volume_std(h::VolumeHandle, volume::Array{T} ) where {T}
        setup_standard_order( h )
        write_minc_volume(h,volume)
        return nothing
    end

    """
    Copy metadata from one file to another
    """
    function copy_minc_metadata(i::VolumeHandle,o::VolumeHandle)
        @minc2_check minc2_simple.minc2_copy_metadata(i.x[],o.x[])
    end
    

    """
    Read minc2 header attribute
    :param group: attribute group name
    :param attribute: attribute name
    :return:
    """
    function read_minc_attribute(h::VolumeHandle, group::String, attribute::String)::Union{String,AbstractVector,Nothing}

        attr_type  = Ref{Int}(0)
        attr_length = Ref{Int}(0)

        # assume that if we can't get attribute type, it's missing, return nil

        @minc2_check minc2_simple.minc2_get_attribute_type(h.x[], group, attribute, attr_type)
        @minc2_check minc2_simple.minc2_get_attribute_length(h.x[], group, attribute, attr_length)
        
        # assume that array of BYTES is a string 
        # TODO: make sure it's a good assumption
        if attr_type[] == minc2_simple.MINC2_STRING 
            _buf = Vector{UInt8}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, _buf, attr_length[])
            return String(_buf)
        elseif attr_type[] == minc2_simple.MINC2_FLOAT
            # TODO: finish this
            buf = Vector{Float32}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_DOUBLE
            # TODO: finish this
            buf = Vector{Float64}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_INT
            # TODO: finish this
            buf = Vector{Int32}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_SHORT
            # TODO: finish this
            buf = Vector{Int16}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_UINT
            # TODO: finish this
            buf = Vector{UInt32}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_USHORT
            # TODO: finish this
            buf = Vector{UInt16}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_BYTE
            # TODO: finish this
            buf = Vector{Int8}}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        elseif attr_type[] == minc2_simple.MINC2_UBYTE
            # TODO: finish this
            buf = Vector{UInt8}}(undef,attr_length[])
            @minc2_check minc2_simple.minc2_read_attribute(h.x[], group, attribute, buf, attr_length[])
            return buf
        else
            throw(SystemError("MINC2 unsupported data type"))
        end

        return nothing
    end


    """
    Store attribute into minc2 file
    :param group:  group name
    :param attribute:  attribute name
    :param value:  attribute value
    :return:
    """
    function write_minc_attribute(h::VolumeHandle, group::String, attribute::String, value::T) where {T}
        val_type = julia_to_minc2[Type{T}]
        attr_length = length(value)
        # TODO: make this work for other type
        # Right now it might write garbage for anything but strings
        if isa(value,String)
            _value=Vector{UInt8}(value)
            @minc2_check minc2_simple.minc2_write_attribute(h.x[], group, attribute, Base.unsafe_convert(Ptr{Cvoid},_value), attr_length, val_type)
        else
            @minc2_check minc2_simple.minc2_write_attribute(h.x[], group, attribute, Base.unsafe_convert(Ptr{Cvoid},value), attr_length, val_type)
        end
    end

    """
    return history string
    """
    function read_minc_history(i::VolumeHandle)::Union{String, Missing}
        return read_minc_attribute(i,"","history")
    end

    """
    write history string
    """
    function write_minc_history(i::VolumeHandle,history::String)
        write_minc_attribute(i,"","history",history)
    end


    """
    write full volume to file, need to provide details of file structure
    return nothing
    """
    function write_minc_volume_std(path::String, ::Type{Store}, 
            store_hdr::Union{MincHeader, Nothing}, 
            volume::Array{Repr};like::Union{String, Nothing}=nothing, 
            history::Union{String, Nothing}=nothing ) where {Store,Repr}
        
        if isnothing(like)
            # TODO: check if store_hdr is compatible with volume

            handle = define_minc_file(store_hdr, Store, Repr)
            create_minc_file(handle,path)

            if !isnothing(history)
                write_minc_history(handle,history)
            end

            write_minc_volume_std(handle,volume)
            close_minc_file(handle)
        else
            # need to copy file structure
            in_h = open_minc_file(like)
            store_hdr = store_header( in_h )

            # TODO: check if store_hdr is compatible with volume
            handle = define_minc_file(store_hdr, Store, Repr)
            create_minc_file(handle,path)
            
            copy_minc_metadata(in_h,handle)

            if !isnothing(history)
                write_minc_history(handle,history)
            end

            write_minc_volume_std(handle,volume)
            close_minc_file(in_h)
            close_minc_file(handle)
        end

        return nothing
    end

    """
    write full volume to file, need to provide details of file structure
    return nothing
    """
    function write_minc_volume_raw(path::String, ::Type{Store}, 
            store_hdr::Union{MincHeader, Nothing}, 
            volume::Array{Repr};like::Union{String, Nothing}=nothing, 
            history::Union{String, Nothing}=nothing ) where {Store, Repr}
        
        if isnothing(like)
            # TODO: check if store_hdr is compatible with volume

            handle = define_minc_file(store_hdr, Store, Repr)
            create_minc_file(handle,path)

            if !isnothing(history)
                write_minc_history(handle,history)
            end

            write_minc_volume_raw(handle, volume)
            close_minc_file(handle)
        else
            # need to copy file structure
            in_h = open_minc_file(like)
            store_hdr = store_header( in_h )

            # TODO: check if store_hdr is compatible with volume
            handle = define_minc_file(store_hdr, Store, Repr)
            create_minc_file(handle,path)
            
            copy_minc_metadata(in_h,handle)

            if !isnothing(history)
                write_minc_history(handle,history)
            end

            write_minc_volume_raw(handle,volume)
            close_minc_file(in_h)
            close_minc_file(handle)
        end

        return nothing
    end


end # module
