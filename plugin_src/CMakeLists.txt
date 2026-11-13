cmake_minimum_required(VERSION 3.20)
project(nask_capture CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")   # sem depender do VC++ Redistributable

# Cabeçalhos de terceiros (baixados pelo workflow ou colocados à mão em plugin_src/include):
#   include/reframework/API.h  - REFramework, praydog (MIT)
#   include/stb_image_write.h  - stb, Sean Barrett (domínio público / MIT)
add_library(nask_capture SHARED nask_capture.cpp)
target_include_directories(nask_capture PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_options(nask_capture PRIVATE /utf-8 /W3 /O2)
target_compile_definitions(nask_capture PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(nask_capture PRIVATE d3d12 dxgi shell32 ole32)
