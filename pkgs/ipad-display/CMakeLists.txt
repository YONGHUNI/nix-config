cmake_minimum_required(VERSION 3.16)
project(ipad-display-tray LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 REQUIRED COMPONENTS Widgets)
find_package(KF6StatusNotifierItem REQUIRED)

add_executable(ipad-display-tray main.cpp)
target_link_libraries(ipad-display-tray PRIVATE Qt6::Widgets KF6::StatusNotifierItem)
target_compile_definitions(ipad-display-tray PRIVATE IPAD_DISPLAY_CLI="${IPAD_DISPLAY_CLI}")
install(TARGETS ipad-display-tray RUNTIME DESTINATION bin)
