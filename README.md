# QOI.jl - Implementation of the QOI (Quite OK Image) format

[![Build Status](https://github.com/KristofferC/QOI.jl/workflows/CI/badge.svg)](https://github.com/KristofferC/QOI.jl/actions?query=workflows/CI) [![codecov](https://codecov.io/gh/KristofferC/QOI.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/KristofferC/QOI.jl)


This Julia package contains a decoder and encoder for the [QOI image format](https://qoiformat.org/). The QOI format is very simple and can be faster than using PNG (see the [benchmarks](#benchmarks)) at the cost of a slightly worse compression ratio.

The code here is based on the reference C implementation given in https://github.com/phoboslab/qoi.

## FileIO API

This is the simplest API and likely the one that most should use. Simply, use the `load`/`save` API from FileIO.jl to load and save QOI images.

```jl
using FileIO
image = load("test.qoi")
save("test2.qoi", image)
```

## Basic API

- `QOI.qoi_decode(f::Union{String, IO, AbstractVector{UInt8}})` - Read an image in the QOI format from the file/IO/bytes `f` and return a `Matrix` with `RGB{N0f8}` or `RGBA{N0f8}` elements from [ColorTypes.jl](https://github.com/JuliaGraphics/ColorTypes.jl).
- `QOI.qoi_encode(f::Union{String, IO}, image::AbstractMatrix{<:Colorant})` - Write the `image` to the file/IO `f`.
  Images with an alpha channel are stored as `RGBA{N0f8}`, all others as `RGB{N0f8}` (other colorants, like `Gray`, are converted).

Invalid or truncated input throws a `QOI.QOIException`.

## Advanced API

The QOI format stores pixels in row-major order while Julia matrices are column-major,
so a transpose is required to create the matrices returned in the basic API.
To avoid this, the following more advanced APIs work directly on the raw bytes:

- `QOI.qoi_decode_raw(f::Union{String, IO, AbstractVector{UInt8}})` - Decodes an image in the QOI format and returns a tuple `(header, image)`
  where `header` is a `QOI.QOIHeader` (see below) and `image` is a `Matrix{UInt8}` of size `(channels * width, height)` with the uncompressed pixel values.

- `QOI.qoi_encode_raw(image::AbstractVecOrMat{UInt8}, header::QOI.QOIHeader)` - Returns a `Vector{UInt8}` with the QOI encoding of the
  raw pixel values in `image` (row-major, `channels` bytes per pixel). The header is defined as
  ```jl
  struct QOIHeader
    width::UInt32
    height::UInt32
    channels::QOI.QOIChannel # @enum
    colorspace::QOI.QOIColorSpace # @enum
  end
  ```

  where `channels` can be either `QOI.QOI_RGB` or `QOI.QOI_RGBA` and `colorspace` can be either `QOI.QOI_SRGB` or `QOI.QOI_LINEAR`.

- `QOI.qoi_encode_raw(io::IO, image::AbstractVecOrMat{UInt8}, header::QOI.QOIHeader)` - Same as above except writing the encoded bytes to `io`.

- `QOI.qoi_encode_raw!(data::AbstractVector{UInt8}, image::AbstractVecOrMat{UInt8}, header::QOI.QOIHeader)` - Same as above except writing the encoded bytes into `data`, which is resized as needed.
  This allows reusing the output buffer when encoding many images.

## Benchmarks

The benchmarks here compare the speed of encoding/decoding images with QOI.jl and PNGFiles.jl (which uses `libpng`).
It is supposed to mimic https://qoiformat.org/benchmark/.
The images used in the benchmark are taken from `TestImages.jl`, specifically, all the PNG images in https://testimages.juliaimages.org/stable/imagelist/.
The benchmarks were run with Julia 1.13 on an Apple M4 Pro.
`mpps` is megapixels per second.
They can be repeated with `julia --project=benchmark benchmark/runbenchmarks.jl` (requires Julia 1.11+).

<details><summary>Expand to see benchmark results</summary>


`autumn_leaves.png` 105x140 57.42kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.21|0.25|68.85|57.72|22.18 |38.6%|
|  QOI       |0.04|0.06|412.15|228.35|28.25 |49.2%|

----------------------

`barbara_color.png` 576x720 1215.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |6.27|10.38|66.13|39.95|812.84 |66.9%|
|  QOI       |1.5|2.33|277.14|178.34|945.75 |77.8%|

----------------------

`chelsea.png` 300x451 396.39kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |1.81|3.11|74.58|43.5|218.84 |55.2%|
|  QOI       |0.37|0.67|368.75|203.2|233.27 |58.8%|

----------------------

`coffee.png` 400x600 703.12kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |3.44|5.97|69.83|40.2|443.18 |63.0%|
|  QOI       |0.78|1.52|307.31|158.37|493.3 |70.2%|

----------------------

`fabio_color_256.png` 256x256 192.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.89|1.38|73.52|47.59|118.0 |61.5%|
|  QOI       |0.21|0.32|309.62|203.87|154.86 |80.7%|

----------------------

`fabio_color_512.png` 512x512 768.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |3.47|5.72|75.46|45.81|327.45 |42.6%|
|  QOI       |0.86|1.62|304.94|162.3|463.9 |60.4%|

----------------------

`fabio_gray_256.png` 256x256 192.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.85|1.24|77.08|52.86|108.65 |56.6%|
|  QOI       |0.19|0.25|341.63|264.84|87.99 |45.8%|

----------------------

`fabio_gray_512.png` 512x512 768.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |3.12|4.44|83.96|59.03|259.41 |33.8%|
|  QOI       |0.98|1.32|268.08|198.06|298.29 |38.8%|

----------------------

`lena_gray_16bit.png` 256x256 192.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.86|1.24|75.91|52.67|100.71 |52.5%|
|  QOI       |0.19|0.24|339.93|278.63|82.01 |42.7%|

----------------------

`lighthouse.png` 512x768 1152.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |5.55|9.73|70.83|40.43|692.56 |60.1%|
|  QOI       |1.29|2.34|304.0|167.92|638.75 |55.4%|

----------------------

`monarch_color.png` 512x768 1152.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |5.45|9.63|72.14|40.83|613.23 |53.2%|
|  QOI       |1.4|2.67|281.18|147.46|715.79 |62.1%|

----------------------

`monarch_color_256.png` 256x256 192.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.95|1.57|68.78|41.77|129.52 |67.5%|
|  QOI       |0.19|0.34|338.98|190.74|144.39 |75.2%|

----------------------

`mountainstream.png` 512x768 1152.0kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |5.79|10.4|67.92|37.81|892.34 |77.5%|
|  QOI       |1.2|2.0|328.71|196.89|824.83 |71.6%|

----------------------

`toucan.png` 150x162 94.92kB

|           | decode ms | encode ms | decode mpps | encode mpps | size kb | rate |
|:-----------|----------:|----------:|------------:|------------:|--------:|-----:|
|  PNGFiles  |0.28|0.36|85.87|68.37|25.84 |27.2%|
|  QOI       |0.05|0.08|530.17|300.93|43.28 |45.6%|

</details>
