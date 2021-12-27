# QOI.jl - Implementation of the QOI (Quite OK Image) format 

This Julia package contains a decoder and encoder for the [QOI image format](https://qoiformat.org/).
It is based on the reference C implementation given in https://github.com/phoboslab/qoi.

## FileIO API

This is the simple API and likely the one that most should use.

```jl
using FileIO
image = load("test.qoi")
save("test2.qoi", image)
```

## Basic API

- `QOI.qoi_decode(f::Union{String, IO})` - Read an image in the QOI format from the file/IO `f` and return a matrix with `RGB` or `RGBA` colorants from [ColorTypes.jl](https://github.com/JuliaGraphics/ColorTypes.jl)
- `QOI.qoi_encode(f::Union{String, IO}, image::AbstractMatrix{<:Colorant})` - Write the `image` to the the file/IO `f`. 

## Advanced API

The QOI format is read in row-major order.
This means that a transpose is required to create the matrices returned in the basic API.
To avoid this, the following more advanced APIs exist:

- `QOI.qoi_decode_raw(v::AbstractVector{UIt8}})` - Takes a vector of the bytes of an image in QOI format and returns the uncompressed vector of bytes from decoding.  

- `QOI.qoi_encode_raw(image::AbstractVecOrMat{UInt8}, header::QOI.QOIHeader)` - Returns the bytes from compressing the bytes in `image`. The required header is defined as
  ```jl
  struct QOIHeader
    width::UInt32
    height::UInt32
    channels::QOI.QOIChannel # @enum
    colorspace::QOI.QOIColorSpace # @enum
  end
  ```

  where `channels` can be either `QOI.QOI_RGB` or `QOI.QOI_RGBA` and `colorspace` can be either `QOI.QOI_SRGB` or `QOI.QOI_LINEAR`

- `QOI.qoi_encode_raw!(data::AbstractVecOrMat{UInt8}, image::AbstractVecOrMat{UInt8}, header::QOIHeader)` - Same as above except writing the compressed data into `data`.  

## TODOs:

- Do some benchmarks