/*
 * uart_tx Module Tests
 *
 * Tests UART transmitter with 8N1 format (8 data bits, no parity, 1 stop bit)
 *
 * Test Coverage:
 * - Reset behavior
 * - Ready/valid handshake
 * - Frame format (start bit, 8 data bits LSB first, stop bit)
 * - Idle state (tx_serial high)
 * - Bit timing (16 baud_ticks per bit)
 * - Back-to-back transmissions
 * - tx_active flag
 * - Various data patterns
 */

#include "Vuart_tx.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(UartTX_ModuleTests)

struct UartTXFixture {
    Vuart_tx* dut;
    int cycle_count;
    int baud_tick_count;

    UartTXFixture() {
        dut = new Vuart_tx;
        cycle_count = 0;
        baud_tick_count = 0;

        // Initialize inputs
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->baud_tick = 0;
        dut->tx_data = 0;
        dut->tx_valid = 0;
    }

    ~UartTXFixture() {
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
        dut->tx_valid = 0;
        dut->baud_tick = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;
        baud_tick_count = 0;
    }

    // Helper: Generate baud tick (pulses for 1 cycle every 16 cycles for testing)
    void tick_with_baud() {
        // Simple pattern: baud_tick high every cycle for this test
        // (In real system, baud_gen provides this)
        dut->baud_tick = 1;
        tick();
        dut->baud_tick = 0;
        baud_tick_count++;
    }

    // Helper: Collect serial bits over a frame (10 bits: start + 8 data + stop)
    std::vector<int> collect_frame() {
        std::vector<int> bits;
        for (int i = 0; i < 10 * 16; i++) {
            // Sample in middle of each bit period (at tick 8 of 16)
            if (i % 16 == 8) {
                bits.push_back(dut->tx_serial);
            }
            tick_with_baud();
        }
        return bits;
    }

    // Helper: Start transmission
    void start_transmission(uint8_t data) {
        dut->tx_data = data;
        dut->tx_valid = 1;
        tick();
        dut->tx_valid = 0;
    }
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(uart_tx_reset_state, UartTXFixture) {
    reset();

    // After reset: ready=1, serial=1 (idle high), active=0
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
    BOOST_CHECK_EQUAL(dut->tx_serial, 1);
    BOOST_CHECK_EQUAL(dut->tx_active, 0);
}

// Test 2: Idle state maintained without transaction
BOOST_FIXTURE_TEST_CASE(uart_tx_idle_state, UartTXFixture) {
    reset();

    // Run for many cycles without starting transmission
    for (int i = 0; i < 50; i++) {
        tick_with_baud();
        BOOST_CHECK_EQUAL(dut->tx_ready, 1);
        BOOST_CHECK_EQUAL(dut->tx_serial, 1);
        BOOST_CHECK_EQUAL(dut->tx_active, 0);
    }
}

// Test 3: Ready/valid handshake
BOOST_FIXTURE_TEST_CASE(uart_tx_handshake, UartTXFixture) {
    reset();

    // Initially ready
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);

    // Assert valid with data
    dut->tx_data = 0xAB;
    dut->tx_valid = 1;
    tick();

    // After transaction, ready should go low
    BOOST_CHECK_EQUAL(dut->tx_ready, 0);
    BOOST_CHECK_EQUAL(dut->tx_active, 1);

    // Clear valid (transaction already occurred)
    dut->tx_valid = 0;
}

// Test 4: Start bit timing and value
BOOST_FIXTURE_TEST_CASE(uart_tx_start_bit, UartTXFixture) {
    reset();

    // Start transmission
    start_transmission(0xAB);

    // tx_serial should be idle (1) before first baud_tick
    BOOST_CHECK_EQUAL(dut->tx_serial, 1);

    // After first baud_tick, should see start bit (0)
    tick_with_baud();
    BOOST_CHECK_EQUAL(dut->tx_serial, 0);
    BOOST_CHECK_EQUAL(dut->tx_active, 1);

    // Start bit lasts 16 baud_ticks
    for (int i = 1; i < 16; i++) {
        tick_with_baud();
        BOOST_CHECK_EQUAL(dut->tx_serial, 0);
    }
}

// Test 5: Data bits LSB first
BOOST_FIXTURE_TEST_CASE(uart_tx_data_bits_lsb_first, UartTXFixture) {
    reset();

    // Transmit 0b10101010 = 0xAA
    start_transmission(0xAA);

    // Skip start bit (16 ticks)
    for (int i = 0; i < 16; i++) {
        tick_with_baud();
    }

    // Sample data bits (0xAA = 0b10101010, LSB first = 0,1,0,1,0,1,0,1)
    std::vector<int> expected = {0, 1, 0, 1, 0, 1, 0, 1};
    for (int bit : expected) {
        // Sample in middle of bit period
        for (int i = 0; i < 8; i++) tick_with_baud();
        BOOST_CHECK_EQUAL(dut->tx_serial, bit);
        for (int i = 8; i < 16; i++) tick_with_baud();
    }
}

// Test 6: Stop bit
BOOST_FIXTURE_TEST_CASE(uart_tx_stop_bit, UartTXFixture) {
    reset();

    start_transmission(0x55);

    // Skip start bit + 8 data bits (9 * 16 = 144 ticks)
    for (int i = 0; i < 9 * 16; i++) {
        tick_with_baud();
    }

    // Now in STOP state, stop bit should be 1 for 16 ticks
    for (int i = 0; i < 16; i++) {
        tick_with_baud();
        BOOST_CHECK_EQUAL(dut->tx_serial, 1);
    }

    // After stop bit, should return to idle
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
    BOOST_CHECK_EQUAL(dut->tx_active, 0);
    BOOST_CHECK_EQUAL(dut->tx_serial, 1);
}

// Test 7: Complete frame format
BOOST_FIXTURE_TEST_CASE(uart_tx_complete_frame, UartTXFixture) {
    reset();

    start_transmission(0xA5);  // 0b10100101

    std::vector<int> bits = collect_frame();

    // Verify frame: start(0) + data(LSB first: 1,0,1,0,0,1,0,1) + stop(1)
    BOOST_CHECK_EQUAL(bits.size(), 10);
    BOOST_CHECK_EQUAL(bits[0], 0);  // Start bit
    BOOST_CHECK_EQUAL(bits[1], 1);  // D0 (LSB)
    BOOST_CHECK_EQUAL(bits[2], 0);  // D1
    BOOST_CHECK_EQUAL(bits[3], 1);  // D2
    BOOST_CHECK_EQUAL(bits[4], 0);  // D3
    BOOST_CHECK_EQUAL(bits[5], 0);  // D4
    BOOST_CHECK_EQUAL(bits[6], 1);  // D5
    BOOST_CHECK_EQUAL(bits[7], 0);  // D6
    BOOST_CHECK_EQUAL(bits[8], 1);  // D7 (MSB)
    BOOST_CHECK_EQUAL(bits[9], 1);  // Stop bit
}

// Test 8: tx_active flag timing
BOOST_FIXTURE_TEST_CASE(uart_tx_active_flag, UartTXFixture) {
    reset();

    // Initially not active
    BOOST_CHECK_EQUAL(dut->tx_active, 0);

    start_transmission(0x42);

    // Should be active immediately after handshake
    BOOST_CHECK_EQUAL(dut->tx_active, 1);

    // Stay active during entire frame (160 baud_ticks)
    for (int i = 0; i < 159; i++) {
        tick_with_baud();
        BOOST_CHECK_EQUAL(dut->tx_active, 1);
    }

    // Final tick
    tick_with_baud();

    // After frame complete, should go inactive
    BOOST_CHECK_EQUAL(dut->tx_active, 0);
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
}

// Test 9: Back-to-back transmissions
BOOST_FIXTURE_TEST_CASE(uart_tx_back_to_back, UartTXFixture) {
    reset();

    // First transmission
    start_transmission(0x11);
    std::vector<int> frame1 = collect_frame();

    // Should be ready immediately after first frame
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
    BOOST_CHECK_EQUAL(dut->tx_active, 0);

    // Second transmission immediately
    start_transmission(0x22);
    std::vector<int> frame2 = collect_frame();

    // Verify both frames
    BOOST_CHECK_EQUAL(frame1[0], 0);  // Start
    BOOST_CHECK_EQUAL(frame1[1], 1);  // 0x11 = 0b00010001, LSB first = 1,0,0,0,1,0,0,0
    BOOST_CHECK_EQUAL(frame1[9], 1);  // Stop

    BOOST_CHECK_EQUAL(frame2[0], 0);  // Start
    BOOST_CHECK_EQUAL(frame2[2], 1);  // 0x22 = 0b00100010, LSB first = 0,1,0,0,0,1,0,0
    BOOST_CHECK_EQUAL(frame2[9], 1);  // Stop
}

// Test 10: All zeros data
BOOST_FIXTURE_TEST_CASE(uart_tx_all_zeros, UartTXFixture) {
    reset();

    start_transmission(0x00);

    std::vector<int> bits = collect_frame();

    // Start bit = 0, all data bits = 0, stop bit = 1
    BOOST_CHECK_EQUAL(bits[0], 0);
    for (int i = 1; i <= 8; i++) {
        BOOST_CHECK_EQUAL(bits[i], 0);
    }
    BOOST_CHECK_EQUAL(bits[9], 1);
}

// Test 11: All ones data
BOOST_FIXTURE_TEST_CASE(uart_tx_all_ones, UartTXFixture) {
    reset();

    start_transmission(0xFF);

    std::vector<int> bits = collect_frame();

    // Start bit = 0, all data bits = 1, stop bit = 1
    BOOST_CHECK_EQUAL(bits[0], 0);
    for (int i = 1; i <= 8; i++) {
        BOOST_CHECK_EQUAL(bits[i], 1);
    }
    BOOST_CHECK_EQUAL(bits[9], 1);
}

// Test 12: tx_valid held high (should only accept once)
BOOST_FIXTURE_TEST_CASE(uart_tx_valid_held_high, UartTXFixture) {
    reset();

    // Hold valid high continuously
    dut->tx_data = 0x12;
    dut->tx_valid = 1;
    tick();

    // Transaction should occur only once
    BOOST_CHECK_EQUAL(dut->tx_ready, 0);
    BOOST_CHECK_EQUAL(dut->tx_active, 1);

    // Even though valid stays high, no new transaction
    for (int i = 0; i < 160; i++) {
        tick_with_baud();
    }

    // After frame completes, if valid still high, new transaction would start
    // But we only check that the first frame completed correctly
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
}

// Test 13: Ready goes low during transmission
BOOST_FIXTURE_TEST_CASE(uart_tx_ready_during_transmission, UartTXFixture) {
    reset();

    start_transmission(0x99);

    // tx_ready should be 0 throughout transmission
    for (int i = 0; i < 160; i++) {
        tick_with_baud();
        if (i < 159) {  // Not yet complete
            BOOST_CHECK_EQUAL(dut->tx_ready, 0);
        }
    }

    // After transmission, ready goes back high
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
}

// Test 14: Multiple different data patterns
BOOST_FIXTURE_TEST_CASE(uart_tx_multiple_patterns, UartTXFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x00, 0xFF, 0xAA, 0x55, 0x0F, 0xF0};

    for (uint8_t data : test_data) {
        // Wait for ready
        while (!dut->tx_ready) tick_with_baud();

        start_transmission(data);
        std::vector<int> bits = collect_frame();

        // Verify frame structure
        BOOST_CHECK_EQUAL(bits[0], 0);   // Start bit
        BOOST_CHECK_EQUAL(bits[9], 1);   // Stop bit

        // Verify data bits (LSB first)
        for (int i = 0; i < 8; i++) {
            int expected_bit = (data >> i) & 1;
            BOOST_CHECK_EQUAL(bits[i + 1], expected_bit);
        }
    }
}

BOOST_AUTO_TEST_SUITE_END()
