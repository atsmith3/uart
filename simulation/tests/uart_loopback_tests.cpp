/*
 * UART System-Level Loopback Tests
 *
 * Tests the complete UART system with TX connected to RX (loopback mode)
 */

#include "Vuart_top.h"
#include "test_utils.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <iostream>

using namespace uart_test;

BOOST_AUTO_TEST_SUITE(UART_System_Loopback_Tests)

// Test fixture for system-level tests
struct UARTSystemFixture {
    Vuart_top* dut;
    uint64_t time_counter;
    uint64_t axi_clk_period;   // 1 MHz = 1000 ns
    uint64_t uart_clk_period;  // 7.3728 MHz = 135.6 ns

    UARTSystemFixture() : time_counter(0), axi_clk_period(1000), uart_clk_period(136) {
        dut = new Vuart_top;
        dut->clk = 0;
        dut->uart_clk = 0;
        dut->rst_n = 0;

        // Initialize AXI-Lite signals
        dut->s_axi_awvalid = 0;
        dut->s_axi_wvalid = 0;
        dut->s_axi_bready = 1;
        dut->s_axi_arvalid = 0;
        dut->s_axi_rready = 1;

        // Loopback: TX -> RX
        dut->uart_rx = 1;  // Idle high
    }

    ~UARTSystemFixture() {
        delete dut;
    }

    void tick_axi() {
        dut->clk = 0;
        dut->eval();
        time_counter++;
        dut->clk = 1;
        dut->eval();
        time_counter++;
    }

    void tick_uart() {
        dut->uart_clk = 0;
        dut->eval();
        time_counter++;
        dut->uart_clk = 1;
        dut->eval();
        time_counter++;

        // Loopback connection
        dut->uart_rx = dut->uart_tx;
    }

    // Run both clocks for a period
    void tick_both(int count = 1) {
        for (int i = 0; i < count; i++) {
            // Tick UART clock more frequently (7.3728 MHz vs 1 MHz)
            for (int j = 0; j < 8; j++) {
                tick_uart();
            }
            tick_axi();
        }
    }

    void reset() {
        dut->rst_n = 0;
        tick_both(10);
        dut->rst_n = 1;
        tick_both(10);
    }

    // AXI-Lite write transaction
    void axi_write(uint32_t addr, uint32_t data) {
        dut->s_axi_awaddr = addr;
        dut->s_axi_awvalid = 1;
        dut->s_axi_wdata = data;
        dut->s_axi_wstrb = 0xF;
        dut->s_axi_wvalid = 1;

        // Wait for ready
        while (!dut->s_axi_awready || !dut->s_axi_wready) {
            tick_axi();
        }
        tick_axi();

        dut->s_axi_awvalid = 0;
        dut->s_axi_wvalid = 0;

        // Wait for response
        while (!dut->s_axi_bvalid) {
            tick_axi();
        }
        tick_axi();
    }

    // AXI-Lite read transaction
    uint32_t axi_read(uint32_t addr) {
        dut->s_axi_araddr = addr;
        dut->s_axi_arvalid = 1;

        // Wait for ready
        while (!dut->s_axi_arready) {
            tick_axi();
        }
        tick_axi();

        dut->s_axi_arvalid = 0;

        // Wait for response
        while (!dut->s_axi_rvalid) {
            tick_axi();
        }
        uint32_t data = dut->s_axi_rdata;
        tick_axi();

        return data;
    }

    // Initialize UART with given baud rate
    void uart_init(uint32_t baud_rate) {
        uint8_t divisor = get_baud_divisor(baud_rate);

        // Reset FIFOs
        axi_write(reg::FIFO_CTRL, fifo_ctrl::TX_FIFO_RST | fifo_ctrl::RX_FIFO_RST);
        tick_both(10);

        // Set baud rate
        axi_write(reg::BAUD_DIV, divisor);

        // Enable TX and RX
        axi_write(reg::CTRL, ctrl::TX_EN | ctrl::RX_EN);

        tick_both(10);
    }

    // Send byte via UART
    void uart_send(uint8_t data) {
        axi_write(reg::TX_DATA, data);
    }

    // Receive byte via UART
    uint8_t uart_receive() {
        return axi_read(reg::RX_DATA) & 0xFF;
    }

    // Get status register
    uint32_t uart_status() {
        return axi_read(reg::STATUS);
    }

    // Wait for RX to have data
    void wait_rx_ready(int max_ticks = 100000) {
        for (int i = 0; i < max_ticks; i++) {
            uint32_t status = uart_status();
            if (!(status & status::RX_EMPTY)) {
                std::cout << "RX ready after " << i << " iterations" << std::endl;
                return;
            }
            tick_both(10);
        }
        std::cout << "ERROR: Timeout waiting for RX data. Final status: 0x"
                  << std::hex << uart_status() << std::dec << std::endl;
        BOOST_FAIL("Timeout waiting for RX data");
    }
};

// Basic loopback test: send one byte
BOOST_FIXTURE_TEST_CASE(loopback_single_byte, UARTSystemFixture) {
    reset();

    std::cout << "Status after reset: 0x" << std::hex << uart_status() << std::dec << std::endl;

    uart_init(baud::BAUD_115200);

    std::cout << "Status after init: 0x" << std::hex << uart_status() << std::dec << std::endl;
    std::cout << "CTRL register: 0x" << std::hex << axi_read(reg::CTRL) << std::dec << std::endl;
    std::cout << "BAUD_DIV register: 0x" << std::hex << axi_read(reg::BAUD_DIV) << std::dec << std::endl;

    // Send a byte
    uart_send(0xAB);

    std::cout << "Status after send: 0x" << std::hex << uart_status() << std::dec << std::endl;

    // Wait for it to arrive
    wait_rx_ready();

    // Read it back
    uint8_t received = uart_receive();

    std::cout << "Received: 0x" << std::hex << (int)received << std::dec << std::endl;

    BOOST_CHECK_EQUAL(received, 0xAB);
}

// Loopback test: multiple bytes
BOOST_FIXTURE_TEST_CASE(loopback_multiple_bytes, UARTSystemFixture) {
    reset();
    uart_init(baud::BAUD_115200);

    std::vector<uint8_t> test_data = {0x00, 0x55, 0xAA, 0xFF, 0x12, 0x34, 0x56, 0x78};

    // Send all bytes
    for (uint8_t byte : test_data) {
        uart_send(byte);
        tick_both(100);  // Give time for transmission
    }

    // Receive all bytes
    for (uint8_t expected : test_data) {
        wait_rx_ready();
        uint8_t received = uart_receive();
        BOOST_CHECK_EQUAL(received, expected);
    }
}

// Test different baud rates
BOOST_FIXTURE_TEST_CASE(loopback_different_baud_rates, UARTSystemFixture) {
    std::vector<uint32_t> baud_rates = {
        baud::BAUD_9600,
        baud::BAUD_115200,
        baud::BAUD_460800
    };

    for (uint32_t baud_rate : baud_rates) {
        reset();
        uart_init(baud_rate);

        uart_send(0xA5);
        wait_rx_ready(200000);  // More time for slower baud rates

        uint8_t received = uart_receive();
        BOOST_CHECK_EQUAL(received, 0xA5);
    }
}

// Test status flags
BOOST_FIXTURE_TEST_CASE(loopback_status_flags, UARTSystemFixture) {
    reset();
    uart_init(baud::BAUD_115200);

    // Check initial status
    uint32_t status = uart_status();
    BOOST_CHECK(status & status::TX_EMPTY);
    BOOST_CHECK(status & status::RX_EMPTY);

    // Send a byte
    uart_send(0x42);

    // TX should become active
    tick_both(100);
    status = uart_status();
    // TX_ACTIVE might be set during transmission

    // Wait for reception
    wait_rx_ready();

    // RX should not be empty now
    status = uart_status();
    BOOST_CHECK(!(status & status::RX_EMPTY));

    // Read the byte
    uint8_t received = uart_receive();
    BOOST_CHECK_EQUAL(received, 0x42);

    // RX should be empty again
    status = uart_status();
    BOOST_CHECK(status & status::RX_EMPTY);
}

BOOST_AUTO_TEST_SUITE_END()
