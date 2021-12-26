module QOI

using FixedPointNumbers
using ColorTypes


#############
# Constants #
#############

const QOI_OP_INDEX = 0x00 # 00xxxxxx
const QOI_OP_DIFF  = 0x40 # 01xxxxxx
const QOI_OP_LUMA  = 0x80 # 10xxxxxx
const QOI_OP_RUN   = 0xc0 # 11xxxxxx
const QOI_OP_RGB   = 0xfe # 11111110
const QOI_OP_RGBA  = 0xff # 11111111
const QOI_MASK_2   = 0xc0 # 11000000
const QOI_MAGIC = UInt32('q') << 24 | UInt32('o') << 16 | UInt32('i') << 8 | UInt32('f')
const QOI_PIXELS_MAX = 400000000
const QOI_PADDING = (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)


#########
# Pixel #
#########

struct Pixel
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    function Pixel(r::UInt8, g::UInt8, b::UInt8, a::UInt8)
        new(r, g, b, a)
    end
end

@inline qoi_color_hash(p::Pixel) = p.r*3 + p.g*5 + p.b*7 + p.a*11


#############
# QOIHeader #
#############

@enum QOIChannel::UInt8 begin
    QOI_RGB = 0x03
    QOI_RGBA = 0x04
end

@enum QOIColorSpace::UInt8 begin
    QOI_SRGB = 0x00
    QOI_LINEAR = 0x01
end

struct QOIHeader
    width::UInt32
    height::UInt32
    channels::QOIChannel
    colorspace::QOIColorSpace
end
function QOIHeader(width::UInt32, height::UInt32, channels::UInt8, colorspace::UInt8)
    if (width == 0 || height == 0 ||
        channels < 3 || channels > 4 ||
        colorspace > 1) # TODO: Check size
        throw_invalid_header_error()
    end
    return QOIHeader(width, height, QOIChannel(channels), QOIColorSpace(colorspace))
end


##############  
# Exceptions #
##############

struct QOIException <: Exception
    msg::String
end
Base.showerror(io::IO, qoi::QOIException) = print(io, qoi.msg)

@noinline throw_magic_bytes_error(magic::UInt32) =
    throw(QOIException("invalid magic bytes, got $(repr(magic)), expected $(repr(QOI_MAGIC))"))
@noinline throw_invalid_header_error() =
    throw(QOIException("invalid header"))
@noinline throw_unexpected_eof() =
    throw(QOIException("unexpected end of file"))


############
# Encoding #
############

mutable struct QOIWriter{V <: AbstractVecOrMat{UInt8}}
    v::V
    pos::Int
end
QOIWriter(v::AbstractVecOrMat{UInt8}) = QOIWriter(v, 0)

@inline function qoi_write!(qoiw::QOIWriter, v::UInt8)
    qoiw.pos += 1 
    qoiw.pos > length(qoiw.v) && resize!(qoiw.v, max(1, length(qoiw.v) * 2))
    qoiw.v[qoiw.pos] = v
end

function qoi_write_32!(qoiw::QOIWriter, v::UInt32)
    qoi_write!(qoiw, ((0xff000000 & v) >> 24) % UInt8)
    qoi_write!(qoiw, ((0x00ff0000 & v) >> 16) % UInt8)
    qoi_write!(qoiw, ((0x0000ff00 & v) >> 8)  % UInt8)
    qoi_write!(qoiw, ((0x000000ff & v))       % UInt8)
    return 
end

qoi_encode_raw(image::AbstractVecOrMat{UInt8}, header::QOIHeader) =
    qoi_encode_raw!(Vector{UInt8}(undef, 256), image, header)

function qoi_encode_raw(io::IO, image::AbstractVecOrMat{UInt8}, header::QOIHeader)
    data = qoi_encode_raw(image, header)
    write(io, data)
end

function qoi_encode_raw!(data::AbstractVector{UInt8}, image::AbstractVecOrMat{UInt8}, header::QOIHeader)
    # error Check

    qoiw = QOIWriter(data)

    # Header
    qoi_write_32!(qoiw, QOI_MAGIC)
    qoi_write_32!(qoiw, header.width)
    qoi_write_32!(qoiw, header.height)
    qoi_write!(qoiw, header.channels |> Integer)
    qoi_write!(qoiw, header.colorspace |> Integer)

    index = fill(Pixel(0x00, 0x00, 0x00, 0x00), 64)
    run = 0x00
    px_prev = Pixel(0x00, 0x00, 0x00, 0xff)
    px = px_prev
    
    channels = Integer(header.channels)
    px_len = header.width * header.height * channels
    px_end = px_len - channels + 1

    # Data
    for px_pos in 1:channels:px_len
        r = image[px_pos + 0]
        g = image[px_pos + 1]
        b = image[px_pos + 2]
        a = header.channels == QOI_RGBA ? image[px_pos + 3] : 0xff
        px = Pixel(r, g, b, a)

        if px == px_prev
            run += 0x01
            if run == 62 || px_pos == px_end
                qoi_write!(qoiw, QOI_OP_RUN |  (run-0x01))
                run = 0x00
            end
        else
            if run > 0
                qoi_write!(qoiw, QOI_OP_RUN | (run-0x01))
                run = 0x00
            end

            index_pos = mod1(qoi_color_hash(px)+1, 64) % UInt8
            if index[index_pos] == px
                qoi_write!(qoiw, QOI_OP_INDEX | (index_pos - 0x01))
            else
                index[index_pos] = px
                if px.a == px_prev.a
                    vr = ((px.r) - (px_prev.r)) % Int8
                    vg = ((px.g) - (px_prev.g)) % Int8
                    vb = ((px.b) - (px_prev.b)) % Int8

                    vg_r = vr - vg
                    vg_b = vb - vg
                    if      vr > -3 && vr < 2 &&
                            vg > -3 && vg < 2 &&
                            vb > -3 && vb < 2
                        qoi_write!(qoiw, QOI_OP_DIFF | ((vr + 0x02) % UInt8) << 4 | ((vg + 0x02) % UInt8) << 2 | (vb + 0x02)  % UInt8)
                    elseif  vg_r > -9 && vg_r < 8 &&
                            vg > -33  && vg < 32 &&
                            vg_b > -9 && vg_b < 8
                        qoi_write!(qoiw, QOI_OP_LUMA   | (vg + UInt8(32)) % UInt8)
                        qoi_write!(qoiw, ((vg_r + 0x08) % UInt8) << 4 | (vg_b + 0x08) % UInt8)
                    else
                        qoi_write!(qoiw, QOI_OP_RGB)
                        qoi_write!(qoiw, px.r)
                        qoi_write!(qoiw, px.g)
                        qoi_write!(qoiw, px.b)
                    end
                else
                    qoi_write!(qoiw, QOI_OP_RGBA)
                    qoi_write!(qoiw, px.r)
                    qoi_write!(qoiw, px.g)
                    qoi_write!(qoiw, px.b)
                    qoi_write!(qoiw, px.a)
                end
            end
        end
        px_prev = px
    end

    # Padding
    for x in QOI_PADDING
        qoi_write!(qoiw, x)
	end

    sizehint!(data, qoiw.pos)
    resize!(data, qoiw.pos)
    return data
end

function qoi_encode(file::String, image::AbstractMatrix{T}) where T <: Colorant
    if T <: TransparentColor
        if T != RGBA{N0f8}
            image = convert(RGBA{N0f8}, image)
        end
        channel = QOI_RGBA
    else
        if T != RGB{N0f8}
            image = convert(RGB{N0f8}, image)
        end 
        channel = QOI_RGB
    end
    header = QOIHeader(size(image, 2), size(image, 1), channel, QOI_SRGB)
    image = permutedims(image)
    open(file, "w") do io
        image_raw = reinterpret(UInt8, image)
        qoi_encode_raw(io, image_raw, header)
    end
end


############
# Decoding #
############

mutable struct QOIReader{V <: AbstractVecOrMat{UInt8}}
    v::V
    pos::Int
end
QOIReader(v::AbstractVecOrMat{UInt8}) = QOIReader(v, 0)

@inline qoi_read!(qoir::QOIReader) = (qoir.pos+=1; #=@inbounds=# qoir.v[qoir.pos])

function qoi_read_32!(qoir::QOIReader)
    a = UInt32(qoi_read!(qoir))
    b = UInt32(qoi_read!(qoir))
    c = UInt32(qoi_read!(qoir))
    d = UInt32(qoi_read!(qoir))
    return a << 24 | b << 16 | c << 8 | d
end

@inline qoi_read_rgb!(qoir::QOIReader) = (qoi_read!(qoir), qoi_read!(qoir), qoi_read!(qoir))
@inline qoi_read_rgba!(qoir::QOIReader) = (qoi_read!(qoir), qoi_read!(qoir), qoi_read!(qoir), qoi_read!(qoir))



function qoi_decode_raw(v::AbstractVector{UInt8})
    qoir = QOIReader(v)

    # Magic
    magic = qoi_read_32!(qoir)
    magic == QOI_MAGIC || throw_magic_bytes_error(magic)

    # Header
    width = qoi_read_32!(qoir)
    height = qoi_read_32!(qoir)
    channels = qoi_read!(qoir)
    colorspace = qoi_read!(qoir)
    header = QOIHeader(width, height, channels, colorspace)

    # Data
    n_pixels = header.width * header.height
    n_values = n_pixels * channels
    data = Vector{UInt8}(undef, n_values)
    index = fill(Pixel(0x00, 0x00, 0x00, 0x00), 64)
    px = Pixel(0x00, 0x00, 0x00, 0xFF)
    px_idx = 1
    run = 0x00

    for px_idx in 1:channels:n_values
        if run > 0
            run -= 0x01
        else
            b1 = qoi_read!(qoir)
            if b1 == QOI_OP_RGB
                r, g, b = qoi_read_rgb!(qoir)     
                px = Pixel(r, g, b, px.a)
            elseif b1 == QOI_OP_RGBA
                r, g, b, a = qoi_read_rgba!(qoir)
                px = Pixel(r, g, b, a)
            elseif b1 & QOI_MASK_2 == QOI_OP_INDEX
                px = index[b1+0x01]
            elseif (b1 & QOI_MASK_2) == QOI_OP_DIFF
                r = px.r + ((b1 >> 0x04) & 0x03) - 0x02
                g = px.g + ((b1 >> 0x02) & 0x03) - 0x02
                b = px.b + ( b1          & 0x03) - 0x02
                px = Pixel(r, g, b, px.a)
            elseif ((b1 & QOI_MASK_2) == QOI_OP_LUMA)
                b2 = qoi_read!(qoir)
                vg = (b1 & 0x3f) - UInt8(32)
                r = px.r + vg - 0x08 + ((b2 >> 4) & 0x0f)
                g = px.g + vg
                b = px.b + vg - 0x08 +  (b2       & 0x0f)
                px = Pixel(r, g, b, px.a)
            elseif (b1 & QOI_MASK_2) == QOI_OP_RUN
                run = (b1 & 0x3f)
            else
                error("unreachable")
            end
            @inbounds index[mod1(qoi_color_hash(px)+1, 64)] = px
        end

        data[px_idx+0] = px.r
        data[px_idx+1] = px.g
        data[px_idx+2] = px.b
        if header.channels == QOI_RGBA
            data[px_idx+3] = px.a
        end
    end

    # Read padding
    for _ in 1:7
        x = qoi_read!(qoir) 
        x == 0 || throw_unexpected_eof()
    end  
    x = qoi_read!(qoir)
    x == 1 || throw_unexpected_eof()

    image = reshape(data, Int(header.width) * channels, Int(header.height))
    return header, image
end

function _to_colortype(header, raw_image)
    T = header.channels == QOI_RGBA ? RGBA{N0f8} : RGB{N0f8} 
    return permutedims(reinterpret(T, raw_image))
end

function qoi_decode(v::AbstractVector{UInt8})
    header, raw_image = qoi_decode_raw(v)
    return _to_colortype(header, raw_image)
end

qoi_decode_raw(f::Union{String, IO}) = qoi_decode_raw(Base.read(f))
qoi_decode(f::Union{String, IO}) = qoi_decode(Base.read(f))

end