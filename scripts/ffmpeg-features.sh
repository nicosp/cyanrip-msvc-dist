# FFmpeg's version and the features cyanrip needs, the same as in cyanrip's
# own static builds.  Sourced by build-static.sh and build-ffmpeg-msvc.sh.

FFMPEG_VERSION=9.0.2

FFMPEG_FEATURES=(
    --disable-{programs,devices,filters,decoders,hwaccels,encoders,muxers}
    --disable-{debug,protocols,demuxers,parsers,doc,swscale,network}
    --disable-{avdevice,autodetect}
    --disable-bsfs --enable-protocol=file,data
    --enable-encoder=flac,tta,aac,wavpack,alac,pcm_s16le,pcm_s32le,pcm_f64le
    --enable-muxer=flac,tta,ipod,wv,mp3,opus,ogg,wav,pcm_s16le,pcm_s32le,image2,singlejpeg
    --enable-parser=png,mjpeg --enable-decoder=mjpeg,png
    --enable-demuxer={image2,image_jpeg_pipe,image_png_pipe}
    --enable-zlib
    --enable-filter={hdcd,aemphasis,ebur128,anullsink,aresample}
    --enable-lib{mp3lame,vorbis,opus}
    --enable-encoder={libmp3lame,libvorbis,libopus}
)
