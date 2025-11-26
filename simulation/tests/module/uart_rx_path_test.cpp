/*
 * uart_rx_path Module Tests
 *
 * Tests complete RX datapath: bit_sync + uart_rx + FIFO integration
 *
 * Test Coverage:
 * - Bit synchronization of async RX input
 * - Automatic reception and FIFO fill
 * - FIFO read interface
 * - Status flags (empty, full, active, level)
 * - Error detection (frame error, overrun)
 * - Multiple byte reception
 * - Back-to-back frames
 * - Duplicate write prevention
 */

#include "Vuart_rx_path.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(UartRXPath_ModuleTests)

struct UartRXPathFixture {
    Vuart_rx_path* dut;
    int cycle_count;

    UartRXPathFixture() {
        dut = new Vuart_rx_path;
        cycle_count = 0;

        // Initialize inputs
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->sample_tick = 0;
        dut->rx_serial = 1;  // Idle high
        dut->rd_en = 0;
    }

    ~UartRXPathFixture() {
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
        dut->rx_serial = 1;
        dut->rd_en = 0;
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
        dut->rx_serial = 1;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Start bit (low)
        dut->rx_serial = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Data bits (LSB first)
        for (int bit = 0; bit < 8; bit++) {
            dut->rx_serial = (data >> bit) & 1;
            for (int i = 0; i < 16; i++) tick_with_sample();
        }

        // Stop bit (high)
        dut->rx_serial = 1;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Wait for FIFO write to complete
        for (int i = 0; i < 10; i++) tick_with_sample();

        // Return to idle
        dut->rx_serial = 1;
    }

    // Helper: Send frame with invalid stop bit (for error testing)
    void send_frame_invalid_stop(uint8_t data) {
        // Start bit
        dut->rx_serial = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Data bits
        for (int bit = 0; bit < 8; bit++) {
            dut->rx_serial = (data >> bit) & 1;
            for (int i = 0; i < 16; i++) tick_with_sample();
        }

        // Stop bit (INVALID - should be high but we send low)
        dut->rx_serial = 0;
        for (int i = 0; i < 16; i++) tick_with_sample();

        // Wait for error detection
        for (int i = 0; i < 10; i++) tick_with_sample();
    }

    // Helper: Read byte from FIFO
    uint8_t read_fifo() {
        dut->rd_en = 1;
        tick();
        dut->rd_en = 0;
        tick();  // Data available 1 cycle later
        return dut->rd_data;
    }
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(uart_rx_path_reset_state, UartRXPathFixture) {
    reset();

    // After reset: empty, not full, not active, level=0
    BOOST_CHECK_EQUAL(dut->rx_empty, 1);
    BOOST_CHECK_EQUAL(dut->rx_full, 0);
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
    BOOST_CHECK_EQUAL(dut->rx_level, 0);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
    BOOST_CHECK_EQUAL(dut->overrun_error, 0);
}

// Test 2: Idle state maintained
BOOST_FIXTURE_TEST_CASE(uart_rx_path_idle_state, UartRXPathFixture) {
    reset();

    // Keep line idle (high)
    dut->rx_serial = 1;
    for (int i = 0; i < 50; i++) {
        tick_with_sample();
        BOOST_CHECK_EQUAL(dut->rx_active, 0);
        BOOST_CHECK_EQUAL(dut->rx_empty, 1);
    }
}

// Test 3: Receive single byte
BOOST_FIXTURE_TEST_CASE(uart_rx_path_single_reception, UartRXPathFixture) {
    reset();

    // Send 0xA5
    send_frame(0xA5);

    // FIFO should not be empty
    BOOST_CHECK_EQUAL(dut->rx_empty, 0);
    BOOST_CHECK_EQUAL(dut->rx_level, 1);

    // Read from FIFO
    uint8_t data = read_fifo();
    BOOST_CHECK_EQUAL(data, 0xA5);

    // FIFO should now be empty
    BOOST_CHECK_EQUAL(dut->rx_empty, 1);
    BOOST_CHECK_EQUAL(dut->rx_level, 0);
}

// Test 4: Automatic reception (no manual control)
BOOST_FIXTURE_TEST_CASE(uart_rx_path_automatic, UartRXPathFixture) {
    reset();

    // Send byte - reception happens automatically
    send_frame(0x42);

    // Data should be in FIFO
    BOOST_CHECK_EQUAL(dut->rx_empty, 0);
    uint8_t data = read_fifo();
    BOOST_CHECK_EQUAL(data, 0x42);
}

// Test 5: Multiple byte reception
BOOST_FIXTURE_TEST_CASE(uart_rx_path_multiple_bytes, UartRXPathFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x11, 0x22, 0x33, 0x44};

    // Send all bytes
    for (uint8_t byte : test_data) {
        send_frame(byte);
    }

    // All bytes should be in FIFO
    BOOST_CHECK_EQUAL(dut->rx_level, 4);

    // Read all bytes
    for (uint8_t expected : test_data) {
        BOOST_CHECK_EQUAL(dut->rx_empty, 0);
        uint8_t received = read_fifo();
        BOOST_CHECK_EQUAL(received, expected);
    }

    // FIFO should be empty
    BOOST_CHECK_EQUAL(dut->rx_empty, 1);
}

// Test 6: Back-to-back frames
BOOST_FIXTURE_TEST_CASE(uart_rx_path_back_to_back, UartRXPathFixture) {
    reset();

    // Send two frames back-to-back
    send_frame(0xAA);
    send_frame(0x55);

    // Both should be in FIFO
    BOOST_CHECK_EQUAL(dut->rx_level, 2);

    // Read first byte
    uint8_t data1 = read_fifo();
    BOOST_CHECK_EQUAL(data1, 0xAA);

    // Read second byte
    uint8_t data2 = read_fifo();
    BOOST_CHECK_EQUAL(data2, 0x55);
}

// Test 7: FIFO full condition
BOOST_FIXTURE_TEST_CASE(uart_rx_path_fifo_full, UartRXPathFixture) {
    reset();

    // Fill FIFO (default depth is 8)
    for (int i = 0; i < 8; i++) {
        send_frame(i);
    }

    // FIFO should be full
    BOOST_CHECK_EQUAL(dut->rx_full, 1);
    BOOST_CHECK_EQUAL(dut->rx_level, 8);

    // Read one byte
    uint8_t data = read_fifo();
    BOOST_CHECK_EQUAL(data, 0);

    // FIFO should no longer be full
    BOOST_CHECK_EQUAL(dut->rx_full, 0);
    BOOST_CHECK_EQUAL(dut->rx_level, 7);
}

// Test 8: Overrun error detection
BOOST_FIXTURE_TEST_CASE(uart_rx_path_overrun, UartRXPathFixture) {
    reset();

    // Fill FIFO completely
    for (int i = 0; i < 8; i++) {
        send_frame(i);
    }

    BOOST_CHECK_EQUAL(dut->rx_full, 1);

    // Send one more byte (should cause overrun)
    send_frame(0xFF);

    // Overrun error should be flagged
    BOOST_CHECK_EQUAL(dut->overrun_error, 1);

    // FIFO should still be full with original data
    BOOST_CHECK_EQUAL(dut->rx_full, 1);
}

// Test 9: Frame error detection
BOOST_FIXTURE_TEST_CASE(uart_rx_path_frame_error, UartRXPathFixture) {
    reset();

    // Send frame with invalid stop bit
    send_frame_invalid_stop(0x55);

    // Frame error should be set
    BOOST_CHECK_EQUAL(dut->frame_error, 1);
}

// Test 10: rx_active flag during reception
BOOST_FIXTURE_TEST_CASE(uart_rx_path_active_flag, UartRXPathFixture) {
    reset();

    // Initially not active
    BOOST_CHECK_EQUAL(dut->rx_active, 0);

    // Start sending a frame
    dut->rx_serial = 0;  // Start bit
    tick_with_sample();

    // Give time for bit_sync to propagate (2-3 cycles)
    for (int i = 0; i < 5; i++) tick_with_sample();

    // Should be active
    BOOST_CHECK_EQUAL(dut->rx_active, 1);

    // Complete the frame
    for (int i = 0; i < 15; i++) tick_with_sample();  // Rest of start bit

    // Data bits (all zeros)
    dut->rx_serial = 0;
    for (int bit = 0; bit < 8; bit++) {
        for (int i = 0; i < 16; i++) tick_with_sample();
    }

    // Stop bit
    dut->rx_serial = 1;
    for (int i = 0; i < 16; i++) tick_with_sample();

    // Wait for write to FIFO
    for (int i = 0; i < 10; i++) tick_with_sample();

    // Should be inactive after frame completes
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
}

// Test 11: Bit synchronization (async input handling)
BOOST_FIXTURE_TEST_CASE(uart_rx_path_bit_sync, UartRXPathFixture) {
    reset();

    // Send frame normally - bit_sync should handle async input
    send_frame(0x5A);

    // Data should be correctly received despite async input
    BOOST_CHECK_EQUAL(dut->rx_empty, 0);
    uint8_t data = read_fifo();
    BOOST_CHECK_EQUAL(data, 0x5A);
}

// Test 12: FIFO level tracking
BOOST_FIXTURE_TEST_CASE(uart_rx_path_level_tracking, UartRXPathFixture) {
    reset();

    BOOST_CHECK_EQUAL(dut->rx_level, 0);

    // Add bytes one at a time
    for (int i = 1; i <= 5; i++) {
        send_frame(i);
        BOOST_CHECK_EQUAL(dut->rx_level, i);
    }

    // Remove bytes one at a time
    for (int i = 5; i >= 1; i--) {
        BOOST_CHECK_EQUAL(dut->rx_level, i);
        read_fifo();
        BOOST_CHECK_EQUAL(dut->rx_level, i - 1);
    }
}

// Test 13: No duplicate writes to FIFO
BOOST_FIXTURE_TEST_CASE(uart_rx_path_no_duplicates, UartRXPathFixture) {
    reset();

    // Send single byte
    send_frame(0x99);

    // Only ONE byte should be in FIFO (not duplicates)
    BOOST_CHECK_EQUAL(dut->rx_level, 1);

    // Read the byte
    uint8_t data = read_fifo();
    BOOST_CHECK_EQUAL(data, 0x99);

    // FIFO should be empty (no extra copies)
    BOOST_CHECK_EQUAL(dut->rx_empty, 1);
}

// Test 14: Various data patterns
BOOST_FIXTURE_TEST_CASE(uart_rx_path_data_patterns, UartRXPathFixture) {
    reset();

    std::vector<uint8_t> patterns = {0x00, 0xFF, 0xAA, 0x55, 0x0F, 0xF0};

    for (uint8_t pattern : patterns) {
        send_frame(pattern);
        uint8_t received = read_fifo();
        BOOST_CHECK_EQUAL(received, pattern);
    }
}

BOOST_AUTO_TEST_SUITE_END()
