/*
 * uart_rx Module Tests
 *
 * Tests UART receiver with 8N1 format and 16× oversampling
 *
 * Test Coverage:
 * - Reset behavior
 * - Start bit detection
 * - Start bit validation (false start detection)
 * - Data bit sampling at bit center (count 8 of 16)
 * - LSB-first deserialization
 * - Stop bit validation
 * - Frame error detection
 * - Ready/valid handshake
 * - rx_active flag
 * - Various data patterns
 */

#include "Vuart_rx.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(UartRX_ModuleTests)

struct UartRXFixture {
    Vuart_rx* dut;
    int cycle_count;

    UartRXFixture() {
        dut = new Vuart_rx;
        cycle_count = 0;

        // Initialize inputs
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->sample_tick = 0;
        dut->rx_serial_sync = 1;  // Idle high
        dut->rx_ready = 0;
    }

    ~UartRXFixture() {
        delete dut;
    }

    void tick() {
        dut->uart_clk = 0;
        dut->eval();
        dut->uart_clk = 1;
        dut->eval();
        cycle_count++;
    }

    void reset() {
        dut->rst_n = 0;
        dut->sample_tick = 0;
        dut->rx_serial_sync = 1;
        dut->rx_ready = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;
    }

    // Helper: Generate sample tick pulse
    void tick_with_sample() {
        dut->sample_tick = 1;
        tick();
        dut->sample_tick = 0;
    }

    // Helper: Send serial frame (start + 8 data bits + stop)
    void send_frame(uint8_t data) {
        // Idle (high)
        dut->rx_serial_sync = 1;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Start bit (low)
        dut->rx_serial_sync = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Data bits (LSB first)
        for (int bit = 0; bit < 8; bit++) {
            dut->rx_serial_sync = (data >> bit) & 1;
            for (int i = 0; i < 16; i++) tick_with_sample();
        }

        // Stop bit (high)
        dut->rx_serial_sync = 1;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Wait a few more cycles for rx_valid to assert
        for (int i = 0; i < 5; i++) tick_with_sample();

        // Return to idle
        dut->rx_serial_sync = 1;
    }

    // Helper: Send frame with invalid stop bit (for error testing)
    void send_frame_invalid_stop(uint8_t data) {
        // Start bit
        dut->rx_serial_sync = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Data bits
        for (int bit = 0; bit < 8; bit++) {
            dut->rx_serial_sync = (data >> bit) & 1;
            for (int i = 0; i < 16; i++) tick_with_sample();
        }

        // Stop bit (INVALID - should be high but we send low)
        dut->rx_serial_sync = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();
    }
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(uart_rx_reset_state, UartRXFixture) {
    reset();

    // After reset: not active, not valid, no frame error
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
    BOOST_CHECK_EQUAL(dut->rx_valid, 0);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

// Test 2: Idle state maintained
BOOST_FIXTURE_TEST_CASE(uart_rx_idle_state, UartRXFixture) {
    reset();

    // Keep line idle (high)
    dut->rx_serial_sync = 1;
    for (int i = 0; i < 50; i++) {
        tick_with_sample();
        BOOST_CHECK_EQUAL(dut->rx_active, 0);
        BOOST_CHECK_EQUAL(dut->rx_valid, 0);
    }
}

// Test 3: Start bit detection
BOOST_FIXTURE_TEST_CASE(uart_rx_start_bit_detection, UartRXFixture) {
    reset();

    // Idle high
    dut->rx_serial_sync = 1;
    tick_with_sample();
    BOOST_CHECK_EQUAL(dut->rx_active, 0);

    // Falling edge (start bit)
    dut->rx_serial_sync = 0;
    tick_with_sample();

    // Should become active
    BOOST_CHECK_EQUAL(dut->rx_active, 1);
}

// Test 4: Simple data reception
BOOST_FIXTURE_TEST_CASE(uart_rx_simple_reception, UartRXFixture) {
    reset();

    // Send 0xA5 (0b10100101)
    send_frame(0xA5);

    // rx_valid should be asserted
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0xA5);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

// Test 5: Ready/valid handshake
BOOST_FIXTURE_TEST_CASE(uart_rx_handshake, UartRXFixture) {
    reset();

    send_frame(0x42);

    // Valid should be asserted
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x42);

    // Assert ready for handshake
    dut->rx_ready = 1;
    tick();

    // After handshake, valid should deassert
    BOOST_CHECK_EQUAL(dut->rx_valid, 0);

    dut->rx_ready = 0;
}

// Test 6: Frame error detection (invalid stop bit)
BOOST_FIXTURE_TEST_CASE(uart_rx_frame_error, UartRXFixture) {
    reset();

    send_frame_invalid_stop(0x55);

    // Frame error should be set
    BOOST_CHECK_EQUAL(dut->frame_error, 1);
}

// Test 7: LSB first reception
BOOST_FIXTURE_TEST_CASE(uart_rx_lsb_first, UartRXFixture) {
    reset();

    // Send 0xAA (0b10101010, LSB first on wire: 0,1,0,1,0,1,0,1)
    send_frame(0xAA);

    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0xAA);
}

// Test 8: All zeros
BOOST_FIXTURE_TEST_CASE(uart_rx_all_zeros, UartRXFixture) {
    reset();

    send_frame(0x00);

    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x00);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

// Test 9: All ones
BOOST_FIXTURE_TEST_CASE(uart_rx_all_ones, UartRXFixture) {
    reset();

    send_frame(0xFF);

    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0xFF);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

// Test 10: False start detection
BOOST_FIXTURE_TEST_CASE(uart_rx_false_start, UartRXFixture) {
    reset();

    // Start with idle
    dut->rx_serial_sync = 1;
    tick_with_sample();

    // Brief low pulse (false start)
    dut->rx_serial_sync = 0;
    for (int i = 0; i < 4; i++) tick_with_sample();

    // Goes back high before sample point
    dut->rx_serial_sync = 1;
    for (int i = 0; i < 12; i++) tick_with_sample();

    // Should return to idle, no valid data
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
    BOOST_CHECK_EQUAL(dut->rx_valid, 0);
}

// Test 11: Back-to-back frames
BOOST_FIXTURE_TEST_CASE(uart_rx_back_to_back, UartRXFixture) {
    reset();

    // First frame
    send_frame(0x11);
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x11);

    // Handshake
    dut->rx_ready = 1;
    tick();
    dut->rx_ready = 0;

    // Second frame immediately
    send_frame(0x22);
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x22);
}

// Test 12: rx_active flag timing
BOOST_FIXTURE_TEST_CASE(uart_rx_active_flag, UartRXFixture) {
    reset();

    // Initially not active
    BOOST_CHECK_EQUAL(dut->rx_active, 0);

    // Start bit
    dut->rx_serial_sync = 0;
    tick_with_sample();

    // Should be active
    BOOST_CHECK_EQUAL(dut->rx_active, 1);

    // Stay active through entire frame
    for (int i = 0; i < 15; i++) tick_with_sample();  // Rest of start bit

    for (int bit = 0; bit < 8; bit++) {
        dut->rx_serial_sync = 0;
        for (int i = 0; i < 16; i++) {
            tick_with_sample();
            BOOST_CHECK_EQUAL(dut->rx_active, 1);
        }
    }

    // Stop bit
    dut->rx_serial_sync = 1;
    for (int i = 0; i < 16; i++) {
        tick_with_sample();
    }

    // Wait for rx_valid to assert
    for (int i = 0; i < 5; i++) tick_with_sample();

    // After frame, should still be active until handshake
    BOOST_CHECK_EQUAL(dut->rx_active, 1);

    // Handshake
    dut->rx_ready = 1;
    tick();

    // Now should be inactive
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
}

// Test 13: Multiple data patterns
BOOST_FIXTURE_TEST_CASE(uart_rx_multiple_patterns, UartRXFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x00, 0xFF, 0xAA, 0x55, 0x0F, 0xF0, 0x12, 0x34};

    for (uint8_t expected : test_data) {
        send_frame(expected);

        BOOST_CHECK_EQUAL(dut->rx_valid, 1);
        BOOST_CHECK_EQUAL(dut->rx_data, expected);
        BOOST_CHECK_EQUAL(dut->frame_error, 0);

        // Handshake
        dut->rx_ready = 1;
        tick();
        dut->rx_ready = 0;

        // Small idle period
        dut->rx_serial_sync = 1;
        for (int i = 0; i < 8; i++) tick_with_sample();
    }
}

// Test 14: Valid held until handshake
BOOST_FIXTURE_TEST_CASE(uart_rx_valid_held, UartRXFixture) {
    reset();

    send_frame(0x99);

    // Valid should be asserted
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x99);

    // Wait several cycles without handshake
    for (int i = 0; i < 20; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->rx_valid, 1);  // Should stay high
        BOOST_CHECK_EQUAL(dut->rx_data, 0x99);  // Data should be stable
    }

    // Finally handshake
    dut->rx_ready = 1;
    tick();

    // Now valid should go low
    BOOST_CHECK_EQUAL(dut->rx_valid, 0);
}

BOOST_AUTO_TEST_SUITE_END()
