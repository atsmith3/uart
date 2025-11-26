######################################################################
#
# DESCRIPTION: UART Peripheral Verification CMake Configuration
#
# Phase 1: Module Tests (bit_sync, sync_fifo)
#
######################################################################

cmake_minimum_required(VERSION 3.8)
project(uart_verification)

# Find required packages
find_package(verilator HINTS $ENV{VERILATOR_ROOT} ${VERILATOR_ROOT})
if (NOT verilator_FOUND)
  message(FATAL_ERROR "Verilator was not found. Either install it, or set the VERILATOR_ROOT environment variable")
endif()

find_package(Boost 1.65 REQUIRED COMPONENTS unit_test_framework)
if (NOT Boost_FOUND)
  message(FATAL_ERROR "Boost.Test was not found. Install with: sudo apt-get install libboost-test-dev")
endif()

# Set WORKSPACE - either from environment or auto-detect
if(DEFINED ENV{WORKSPACE})
  set(WORKSPACE "$ENV{WORKSPACE}")
else()
  # Auto-detect: go up one directory from simulation
  get_filename_component(WORKSPACE "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
  message(STATUS "WORKSPACE not set, auto-detected: ${WORKSPACE}")
endif()

set(RTL_ROOT ${WORKSPACE}/rtl)

#####################################################################
# Phase 1: Module Tests
#####################################################################

# Bit Synchronizer
add_library(verilated_bit_sync STATIC)
verilate(verilated_bit_sync COVERAGE TRACE
  PREFIX Vbit_sync
  SOURCES ${RTL_ROOT}/bit_sync.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# Synchronous FIFO
add_library(verilated_sync_fifo STATIC)
verilate(verilated_sync_fifo COVERAGE TRACE
  PREFIX Vsync_fifo
  SOURCES ${RTL_ROOT}/sync_fifo.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# Baud Rate Generator
add_library(verilated_baud_gen STATIC)
verilate(verilated_baud_gen COVERAGE TRACE
  PREFIX Vbaud_gen
  SOURCES ${RTL_ROOT}/baud_gen.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# UART Transmitter
add_library(verilated_uart_tx STATIC)
verilate(verilated_uart_tx COVERAGE TRACE
  PREFIX Vuart_tx
  SOURCES ${RTL_ROOT}/uart_tx.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# UART TX Path (integration)
add_library(verilated_uart_tx_path STATIC)
verilate(verilated_uart_tx_path COVERAGE TRACE
  PREFIX Vuart_tx_path
  SOURCES ${RTL_ROOT}/uart_tx_path.sv ${RTL_ROOT}/sync_fifo.sv ${RTL_ROOT}/uart_tx.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# UART Receiver
add_library(verilated_uart_rx STATIC)
verilate(verilated_uart_rx COVERAGE TRACE
  PREFIX Vuart_rx
  SOURCES ${RTL_ROOT}/uart_rx.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# UART RX Path (integration)
add_library(verilated_uart_rx_path STATIC)
verilate(verilated_uart_rx_path COVERAGE TRACE
  PREFIX Vuart_rx_path
  SOURCES ${RTL_ROOT}/uart_rx_path.sv ${RTL_ROOT}/bit_sync.sv ${RTL_ROOT}/uart_rx.sv ${RTL_ROOT}/sync_fifo.sv
  VERILATOR_ARGS -Wall -Wno-fatal -DSIMULATION
)

# Module test executable
add_executable(module_tests
  tests/test_main.cpp
  tests/module/bit_sync_test.cpp
  tests/module/sync_fifo_test.cpp
  tests/module/baud_gen_test.cpp
  tests/module/uart_tx_test.cpp
  tests/module/uart_tx_path_test.cpp
  tests/module/uart_rx_test.cpp
  tests/module/uart_rx_path_test.cpp
)

target_link_libraries(module_tests
  verilated_bit_sync
  verilated_sync_fifo
  verilated_baud_gen
  verilated_uart_tx
  verilated_uart_tx_path
  verilated_uart_rx
  verilated_uart_rx_path
  ${Boost_LIBRARIES}
)

target_include_directories(module_tests PRIVATE
  ${Boost_INCLUDE_DIRS}
)

# CTest integration
enable_testing()
add_test(NAME module_tests COMMAND module_tests --log_level=test_suite)

# Display build info
message(STATUS "==============================================")
message(STATUS "UART Verification Build Configuration")
message(STATUS "==============================================")
message(STATUS "Workspace: ${WORKSPACE}")
message(STATUS "RTL Root: ${RTL_ROOT}")
message(STATUS "Verilator: ${VERILATOR_EXECUTABLE}")
message(STATUS "Boost: ${Boost_VERSION}")
message(STATUS "==============================================")
