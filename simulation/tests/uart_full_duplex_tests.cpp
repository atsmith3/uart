/*
 * UART System-Level Full Duplex Tests
 *
 * Tests two UART transceivers communicating with each other in full duplex mode
 */

#include "Vuart_top.h"
#include "test_utils.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <iostream>
#include <queue>

using namespace uart_test;

BOOST_AUTO_TEST_SUITE(UART_System_FullDuplex_Tests)

// Test fixture for full duplex tests with two UART instances
struct UARTFullDuplexFixture {
    Vuart_top* uart_a;  // UART A
    Vuart_top* uart_b;  // UART B
    uint64_t time_counter;

    UARTFullDuplexFixture() : time_counter(0) {
        // Initialize UART A
        uart_a = new Vuart_top;
        uart_a->clk = 0;
        uart_a->uart_clk = 0;
        uart_a->rst_n = 0;
        uart_a->s_axi_awvalid = 0;
        uart_a->s_axi_wvalid = 0;
        uart_a->s_axi_bready = 1;
        uart_a->s_axi_arvalid = 0;
        uart_a->s_axi_rready = 1;
        uart_a->uart_rx = 1;

        // Initialize UART B
        uart_b = new Vuart_top;
        uart_b->clk = 0;
        uart_b->uart_clk = 0;
        uart_b->rst_n = 0;
        uart_b->s_axi_awvalid = 0;
        uart_b->s_axi_wvalid = 0;
        uart_b->s_axi_bready = 1;
        uart_b->s_axi_arvalid = 0;
        uart_b->s_axi_rready = 1;
        uart_b->uart_rx = 1;
    }

    ~UARTFullDuplexFixture() {
        delete uart_a;
        delete uart_b;
    }

    void tick_axi() {
        // Tick AXI clock for both UARTs
        uart_a->clk = 0;
        uart_b->clk = 0;
        uart_a->eval();
        uart_b->eval();
        time_counter++;

        uart_a->clk = 1;
        uart_b->clk = 1;
        uart_a->eval();
        uart_b->eval();
        time_counter++;
    }

    void tick_uart() {
        // Tick UART clock for both UARTs
        uart_a->uart_clk = 0;
        uart_b->uart_clk = 0;
        uart_a->eval();
        uart_b->eval();
        time_counter++;

        uart_a->uart_clk = 1;
        uart_b->uart_clk = 1;
        uart_a->eval();
        uart_b->eval();
        time_counter++;

        // Cross-connect: A's TX -> B's RX, B's TX -> A's RX
        uart_a->uart_rx = uart_b->uart_tx;
        uart_b->uart_rx = uart_a->uart_tx;
    }

    void tick_both(int count = 1) {
        for (int i = 0; i < count; i++) {
            // Interleave clocks: tick UART first to allow CDC signals to propagate
            // Tick UART clock more frequently (7.3728 MHz vs 1 MHz)
            for (int j = 0; j < 8; j++) {
                tick_uart();
            }
            tick_axi();
            // Tick UART a few more times after AXI to allow response to propagate back
            for (int j = 0; j < 4; j++) {
                tick_uart();
            }
        }
    }

    void reset() {
        uart_a->rst_n = 0;
        uart_b->rst_n = 0;
        tick_both(10);
        uart_a->rst_n = 1;
        uart_b->rst_n = 1;
        tick_both(10);
    }

    // AXI-Lite write for specific UART
    void axi_write(Vuart_top* uart, uint32_t addr, uint32_t data) {
        uart->s_axi_awaddr = addr;
        uart->s_axi_awvalid = 1;
        uart->s_axi_wdata = data;
        uart->s_axi_wstrb = 0xF;
        uart->s_axi_wvalid = 1;

        // Wait for ready (tick both clocks for CDC)
        while (!uart->s_axi_awready || !uart->s_axi_wready) {
            tick_both();
        }
        tick_both();

        uart->s_axi_awvalid = 0;
        uart->s_axi_wvalid = 0;

        // Wait for response (tick both clocks for CDC)
        while (!uart->s_axi_bvalid) {
            tick_both();
        }
        tick_both();
    }

    // AXI-Lite read for specific UART
    uint32_t axi_read(Vuart_top* uart, uint32_t addr) {
        uart->s_axi_araddr = addr;
        uart->s_axi_arvalid = 1;

        // Wait for ready (tick both clocks for CDC)
        while (!uart->s_axi_arready) {
            tick_both();
        }
        tick_both();

        uart->s_axi_arvalid = 0;

        // Wait for response (tick both clocks for CDC)
        while (!uart->s_axi_rvalid) {
            tick_both();
        }
        uint32_t data = uart->s_axi_rdata;
        tick_both();

        return data;
    }

    // Initialize both UARTs with same baud rate
    void uart_init_both(uint32_t baud_rate) {
        uint8_t divisor = get_baud_divisor(baud_rate);

        // Reset FIFOs for both
        axi_write(uart_a, reg::FIFO_CTRL, fifo_ctrl::TX_FIFO_RST | fifo_ctrl::RX_FIFO_RST);
        axi_write(uart_b, reg::FIFO_CTRL, fifo_ctrl::TX_FIFO_RST | fifo_ctrl::RX_FIFO_RST);
        tick_both(10);

        // Set baud rate for both
        axi_write(uart_a, reg::BAUD_DIV, divisor);
        axi_write(uart_b, reg::BAUD_DIV, divisor);

        // Enable TX and RX for both
        axi_write(uart_a, reg::CTRL, ctrl::TX_EN | ctrl::RX_EN);
        axi_write(uart_b, reg::CTRL, ctrl::TX_EN | ctrl::RX_EN);

        tick_both(10);
    }

    void uart_send(Vuart_top* uart, uint8_t data) {
        axi_write(uart, reg::TX_DATA, data);
    }

    uint8_t uart_receive(Vuart_top* uart) {
        return axi_read(uart, reg::RX_DATA) & 0xFF;
    }

    uint32_t uart_status(Vuart_top* uart) {
        return axi_read(uart, reg::STATUS);
    }

    void wait_rx_ready(Vuart_top* uart, int max_ticks = 100000) {
        for (int i = 0; i < max_ticks; i++) {
            uint32_t status = uart_status(uart);
            if (!(status & status::RX_EMPTY)) {
                return;
            }
            tick_both(10);
        }
        BOOST_FAIL("Timeout waiting for RX data");
    }
};

// Basic full duplex test: A sends to B, B sends to A simultaneously
BOOST_FIXTURE_TEST_CASE(full_duplex_simultaneous, UARTFullDuplexFixture) {
    reset();
    uart_init_both(baud::BAUD_115200);

    // A sends 0xAA to B, B sends 0xBB to A simultaneously
    uart_send(uart_a, 0xAA);
    uart_send(uart_b, 0xBB);

    // Wait for both to receive
    wait_rx_ready(uart_a);  // A receives from B
    wait_rx_ready(uart_b);  // B receives from A

    // Check received data
    uint8_t a_received = uart_receive(uart_a);
    uint8_t b_received = uart_receive(uart_b);

    BOOST_CHECK_EQUAL(a_received, 0xBB);  // A got BB from B
    BOOST_CHECK_EQUAL(b_received, 0xAA);  // B got AA from A
}

// Full duplex test: bidirectional burst
BOOST_FIXTURE_TEST_CASE(full_duplex_burst, UARTFullDuplexFixture) {
    reset();
    uart_init_both(baud::BAUD_115200);

    std::vector<uint8_t> a_to_b = {0x11, 0x22, 0x33, 0x44};
    std::vector<uint8_t> b_to_a = {0xAA, 0xBB, 0xCC, 0xDD};

    // Send bursts from both sides
    for (size_t i = 0; i < a_to_b.size(); i++) {
        uart_send(uart_a, a_to_b[i]);
        uart_send(uart_b, b_to_a[i]);
        tick_both(50);
    }

    // Receive at A (from B)
    for (size_t i = 0; i < b_to_a.size(); i++) {
        wait_rx_ready(uart_a);
        uint8_t received = uart_receive(uart_a);
        BOOST_CHECK_EQUAL(received, b_to_a[i]);
    }

    // Receive at B (from A)
    for (size_t i = 0; i < a_to_b.size(); i++) {
        wait_rx_ready(uart_b);
        uint8_t received = uart_receive(uart_b);
        BOOST_CHECK_EQUAL(received, a_to_b[i]);
    }
}

// Test asymmetric traffic: A sends more than B
BOOST_FIXTURE_TEST_CASE(full_duplex_asymmetric, UARTFullDuplexFixture) {
    reset();
    uart_init_both(baud::BAUD_115200);

    // A sends 8 bytes, B sends 2 bytes
    std::vector<uint8_t> a_data = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
    std::vector<uint8_t> b_data = {0xF1, 0xF2};

    // Send from A
    for (uint8_t byte : a_data) {
        uart_send(uart_a, byte);
        tick_both(50);
    }

    // Send from B
    for (uint8_t byte : b_data) {
        uart_send(uart_b, byte);
        tick_both(50);
    }

    // B receives all 8 bytes from A
    for (uint8_t expected : a_data) {
        wait_rx_ready(uart_b);
        uint8_t received = uart_receive(uart_b);
        BOOST_CHECK_EQUAL(received, expected);
    }

    // A receives 2 bytes from B
    for (uint8_t expected : b_data) {
        wait_rx_ready(uart_a);
        uint8_t received = uart_receive(uart_a);
        BOOST_CHECK_EQUAL(received, expected);
    }
}

// Test full duplex with different baud rates (error case - should fail or corrupt)
BOOST_FIXTURE_TEST_CASE(full_duplex_same_baud, UARTFullDuplexFixture) {
    reset();

    // Initialize both with same baud rate
    uart_init_both(baud::BAUD_115200);

    // Send a pattern
    uart_send(uart_a, 0x5A);
    uart_send(uart_b, 0xA5);

    wait_rx_ready(uart_a);
    wait_rx_ready(uart_b);

    uint8_t a_received = uart_receive(uart_a);
    uint8_t b_received = uart_receive(uart_b);

    // Should receive correctly with matching baud rates
    BOOST_CHECK_EQUAL(a_received, 0xA5);
    BOOST_CHECK_EQUAL(b_received, 0x5A);
}

// Test FIFO filling with full duplex
BOOST_FIXTURE_TEST_CASE(full_duplex_fifo_test, UARTFullDuplexFixture) {
    reset();
    uart_init_both(baud::BAUD_115200);

    // Fill up FIFOs with multiple bytes (8 entry FIFOs)
    for (int i = 0; i < 8; i++) {
        uart_send(uart_a, 0x10 + i);
        uart_send(uart_b, 0x20 + i);
    }

    // Give time for transmission
    tick_both(10000);

    // Verify all bytes received
    for (int i = 0; i < 8; i++) {
        wait_rx_ready(uart_a);
        wait_rx_ready(uart_b);

        uint8_t a_rx = uart_receive(uart_a);
        uint8_t b_rx = uart_receive(uart_b);

        BOOST_CHECK_EQUAL(a_rx, 0x20 + i);  // A receives from B
        BOOST_CHECK_EQUAL(b_rx, 0x10 + i);  // B receives from A
    }
}

// Test with random data patterns
BOOST_FIXTURE_TEST_CASE(full_duplex_random_data, UARTFullDuplexFixture) {
    reset();
    uart_init_both(baud::BAUD_460800);  // Test at higher baud rate

    std::vector<uint8_t> a_data = generate_random_data(16);
    std::vector<uint8_t> b_data = generate_random_data(16);

    // Send data from both sides
    for (size_t i = 0; i < 16; i++) {
        uart_send(uart_a, a_data[i]);
        uart_send(uart_b, b_data[i]);
        tick_both(100);
    }

    // Verify B receives A's data correctly
    for (size_t i = 0; i < 16; i++) {
        wait_rx_ready(uart_b, 200000);
        uint8_t received = uart_receive(uart_b);
        BOOST_CHECK_EQUAL(received, a_data[i]);
    }

    // Verify A receives B's data correctly
    for (size_t i = 0; i < 16; i++) {
        wait_rx_ready(uart_a, 200000);
        uint8_t received = uart_receive(uart_a);
        BOOST_CHECK_EQUAL(received, b_data[i]);
    }
}

BOOST_AUTO_TEST_SUITE_END()
