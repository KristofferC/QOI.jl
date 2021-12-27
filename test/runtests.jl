using QOI
using Test
using Downloads
using p7zip_jll
using ImageIO
using FileIO

function download_testset()
    p7z = p7zip_jll.p7zip()
    # TODO: Cache this and host it somewhere else to be nice.
    # Perhaps use a scratch space based on the SHA of the file?
    file = Downloads.download("https://qoiformat.org/qoi_test_images.zip")
    tempdir = mktempdir()
    run(`$p7z e $file -o$tempdir`)
    return tempdir
end

function check_roundtrip_qoi(file)
    header, image = QOI.qoi_decode_raw(file)
    data = QOI.qoi_encode_raw(image, header)
    return data == read(file)
end

tmp = download_testset()    

# Test roundtrip of raw decode/encode
for file in readdir(tmp; join=true)
    if endswith(file, ".qoi")
        @info "testing roundtrip of $file"
        @test check_roundtrip_qoi(file)
    end
end

# Test correctness vs PNG
for file_name in Set(getindex.(splitext.(readdir(tmp; join=true)), 1))
    qoi = file_name * ".qoi"
    isfile(qoi) || continue
    @info "comparing to png $qoi"
    png = file_name * ".png"
    img_qoi = QOI.qoi_decode(qoi)
    img_png = load(png)
    @test img_qoi == img_png

    t = tempname()
    QOI.qoi_encode(t, img_qoi)
    @test read(t) == read(qoi)
end

f_logo = joinpath(@__DIR__, "qoi_logo.qoi")

# Test IO API
data_io = open(QOI.qoi_decode, f_logo)
data_file = QOI.qoi_decode(f_logo)
@test data_io == data_file

# Test FileIO integration (enable when https://github.com/JuliaIO/FileIO.jl/pull/354 is merged)
# @test data_file == FileIO.load(f_logo)
# t = tempname()
# @test data_file == FileIO.save(t, data_file)
# @test read(f_logo) == read(t)
