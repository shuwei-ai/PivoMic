cmake_minimum_required(VERSION 3.16)
project(pivomic_audio LANGUAGES CXX)

add_library(pivomic_audio SHARED
    napi_init.cpp
    karaoke/audio_capability_probe.cpp
    karaoke/accompaniment_decoder.cpp
    karaoke/duplex_audio_session.cpp
    karaoke/realtime_mixer.cpp
    karaoke/karaoke_engine.cpp
)
target_compile_features(pivomic_audio PRIVATE cxx_std_17)
target_compile_options(pivomic_audio PRIVATE -Wall -Wextra -Werror -Qunused-arguments)
target_include_directories(pivomic_audio PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(pivomic_audio PRIVATE
    ace_napi.z
    ohaudio
    native_media_avsource
    native_media_avdemuxer
    native_media_acodec
    native_media_codecbase
    native_media_core
    hilog_ndk.z
)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libonnxruntime.so")
  message(FATAL_ERROR "Missing ONNX Runtime. Run python3 scripts/setup_separation_runtime.py (arm64-v8a).")
endif()
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libonnxruntime.so")
add_library(pivomic_separation SHARED separation/napi_separation.cpp karaoke/accompaniment_decoder.cpp)
target_compile_features(pivomic_separation PRIVATE cxx_std_17)
target_include_directories(pivomic_separation PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(pivomic_separation PRIVATE onnxruntime ace_napi.z native_media_avsource
    native_media_avdemuxer native_media_acodec native_media_codecbase native_media_core hilog_ndk.z)
target_compile_options(pivomic_separation PRIVATE -Qunused-arguments -O2)
