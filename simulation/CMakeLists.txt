######################################################################
#
# DESCRIPTION: UART Peripheral Verification CMake Configuration
#
# Builds Verilator testbench with Boost.Test integration for
# automated system-level and module-level testing.
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

# RTL sources for uart_top
set(RTL_SRC
  ${RTL_ROOT}/uart_top.sv
  ${RTL_ROOT}/bit_sync.sv
  ${RTL_ROOT}/sync_fifo.sv
  ${RTL_ROOT}/uart_baud_gen.sv
  ${RTL_ROOT}/uart_tx.sv
  ${RTL_ROOT}/uart_rx.sv
  ${RTL_ROOT}/uart_tx_path.sv
  ${RTL_ROOT}/uart_rx_path.sv
  ${RTL_ROOT}/axi_lite_slave_if.sv
  ${RTL_ROOT}/uart_regs.sv
)

# Verilated UART library for system tests
add_library(verilated_uart STATIC
  test_utils.cpp
)

# Verilate the RTL into the library
verilate(verilated_uart COVERAGE TRACE
  PREFIX Vuart_top
  INCLUDE_DIRS ${RTL_ROOT}
  VERILATOR_ARGS -f ./input.vc -O3 --x-assign unique --x-initial unique
  SOURCES ${RTL_SRC}
)

target_include_directories(verilated_uart PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${Boost_INCLUDE_DIRS}
)

# System-level tests
add_executable(uart_system_tests
  tests/test_main.cpp
  tests/uart_loopback_tests.cpp
  tests/uart_full_duplex_tests.cpp
)

target_link_libraries(uart_system_tests
  verilated_uart
  ${Boost_LIBRARIES}
)

#--------------------------------------------------------------------------
# Module-level tests (separate verilated libraries for each module)
#--------------------------------------------------------------------------

# Bit Synchronizer
add_library(verilated_bit_sync STATIC)
verilate(verilated_bit_sync COVERAGE TRACE
  PREFIX Vbit_sync
  SOURCES ${RTL_ROOT}/bit_sync.sv
)

# Synchronous FIFO
add_library(verilated_sync_fifo STATIC)
verilate(verilated_sync_fifo COVERAGE TRACE
  PREFIX Vsync_fifo
  SOURCES ${RTL_ROOT}/sync_fifo.sv
)

# Baud Rate Generator
add_library(verilated_baud_gen STATIC)
verilate(verilated_baud_gen COVERAGE TRACE
  PREFIX Vuart_baud_gen
  SOURCES ${RTL_ROOT}/uart_baud_gen.sv
)

# UART Transmitter
add_library(verilated_uart_tx STATIC)
verilate(verilated_uart_tx COVERAGE TRACE
  PREFIX Vuart_tx
  SOURCES ${RTL_ROOT}/uart_tx.sv
)

# UART Receiver
add_library(verilated_uart_rx STATIC)
verilate(verilated_uart_rx COVERAGE TRACE
  PREFIX Vuart_rx
  VERILATOR_ARGS --top-module uart_rx
  SOURCES ${RTL_ROOT}/uart_rx.sv ${RTL_ROOT}/bit_sync.sv
)

# Module test executable
add_executable(module_tests
  tests/test_main.cpp
  tests/module/bit_sync_test.cpp
  tests/module/sync_fifo_test.cpp
  tests/module/baud_gen_test.cpp
  tests/module/uart_tx_test.cpp
  tests/module/uart_rx_test.cpp
)

target_link_libraries(module_tests
  verilated_bit_sync
  verilated_sync_fifo
  verilated_baud_gen
  verilated_uart_tx
  verilated_uart_rx
  ${Boost_LIBRARIES}
)

# CTest integration
enable_testing()
add_test(NAME module_tests COMMAND module_tests)
add_test(NAME system_tests COMMAND uart_system_tests)
