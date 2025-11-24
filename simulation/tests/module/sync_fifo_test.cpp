/*
 * Synchronous FIFO Module-Level Tests
 *
 * Tests the synchronous FIFO implementation with various access patterns.
 */

#include "Vsync_fifo.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(SyncFIFO_ModuleTests)

// Test fixture for FIFO tests
struct FIFOFixture {
    Vsync_fifo* dut;
    uint64_t time_counter;

    FIFOFixture() : time_counter(0) {
        dut = new Vsync_fifo;
        dut->clk = 0;
        dut->rst_n = 0;
        dut->wr_en = 0;
        dut->rd_en = 0;
        dut->wr_data = 0;
    }

    ~FIFOFixture() {
        delete dut;
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        time_counter++;

        dut->clk = 1;
        dut->eval();
        time_counter++;
    }

    void reset() {
        dut->rst_n = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
    }

    void write(uint8_t data) {
        dut->wr_en = 1;
        dut->wr_data = data;
        tick();
        dut->wr_en = 0;
    }

    uint8_t read() {
        dut->rd_en = 1;
        tick();
        uint8_t data = dut->rd_data;
        dut->rd_en = 0;
        return data;
    }
};

// Test basic write and read
BOOST_FIXTURE_TEST_CASE(fifo_basic_write_read, FIFOFixture) {
    reset();

    // Initially empty
    BOOST_CHECK_EQUAL(dut->empty, 1);
    BOOST_CHECK_EQUAL(dut->full, 0);
    BOOST_CHECK_EQUAL(dut->level, 0);

    // Write one byte
    write(0xAB);
    tick();

    BOOST_CHECK_EQUAL(dut->empty, 0);
    BOOST_CHECK_EQUAL(dut->level, 1);

    // Read it back
    uint8_t data = read();
    tick();

    BOOST_CHECK_EQUAL(data, 0xAB);
    BOOST_CHECK_EQUAL(dut->empty, 1);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test FIFO full condition
BOOST_FIXTURE_TEST_CASE(fifo_fill_to_full, FIFOFixture) {
    reset();

    // Fill FIFO (depth = 8)
    for (int i = 0; i < 8; i++) {
        BOOST_CHECK_EQUAL(dut->full, 0);
        write(i);
        tick();
    }

    // Should be full now
    BOOST_CHECK_EQUAL(dut->full, 1);
    BOOST_CHECK_EQUAL(dut->level, 8);

    // Read all back
    for (int i = 0; i < 8; i++) {
        uint8_t data = read();
        tick();
        BOOST_CHECK_EQUAL(data, i);
    }

    BOOST_CHECK_EQUAL(dut->empty, 1);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test simultaneous read/write
BOOST_FIXTURE_TEST_CASE(fifo_simultaneous_read_write, FIFOFixture) {
    reset();

    // Write initial data
    for (int i = 0; i < 4; i++) {
        write(i);
    }
    tick();

    BOOST_CHECK_EQUAL(dut->level, 4);

    // Simultaneous read and write (level should stay constant)
    for (int i = 0; i < 4; i++) {
        dut->wr_en = 1;
        dut->wr_data = i + 10;
        dut->rd_en = 1;
        tick();
        uint8_t rd_data = dut->rd_data;
        BOOST_CHECK_EQUAL(rd_data, i);
        dut->wr_en = 0;
        dut->rd_en = 0;
    }

    BOOST_CHECK_EQUAL(dut->level, 4);

    // Read remaining data
    for (int i = 0; i < 4; i++) {
        uint8_t data = read();
        tick();
        BOOST_CHECK_EQUAL(data, i + 10);
    }

    BOOST_CHECK_EQUAL(dut->empty, 1);
}

// Test almost full/empty flags
BOOST_FIXTURE_TEST_CASE(fifo_almost_flags, FIFOFixture) {
    reset();

    // Fill to almost full (depth - 2 = 6)
    for (int i = 0; i < 6; i++) {
        write(i);
    }
    tick();

    BOOST_CHECK_EQUAL(dut->almost_full, 1);
    BOOST_CHECK_EQUAL(dut->full, 0);

    // One more write
    write(0xFF);
    tick();
    BOOST_CHECK_EQUAL(dut->almost_full, 1);

    // One more to full
    write(0xEE);
    tick();
    BOOST_CHECK_EQUAL(dut->full, 1);

    // Test almost empty
    // Read down to 2 entries
    for (int i = 0; i < 6; i++) {
        read();
    }
    tick();

    BOOST_CHECK_EQUAL(dut->almost_empty, 1);
    BOOST_CHECK_EQUAL(dut->empty, 0);
}

BOOST_AUTO_TEST_SUITE_END()
