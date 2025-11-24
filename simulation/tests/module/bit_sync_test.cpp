/*
 * Bit Synchronizer Module-Level Tests
 */

#include "Vbit_sync.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>

BOOST_AUTO_TEST_SUITE(BitSync_ModuleTests)

struct BitSyncFixture {
    Vbit_sync* dut;

    BitSyncFixture() {
        dut = new Vbit_sync;
        dut->clk_dst = 0;
        dut->rst_n_dst = 0;
        dut->data_in = 0;
    }

    ~BitSyncFixture() {
        delete dut;
    }

    void tick() {
        dut->clk_dst = 0;
        dut->eval();
        dut->clk_dst = 1;
        dut->eval();
    }

    void reset() {
        dut->rst_n_dst = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n_dst = 1;
        tick();
    }
};

BOOST_FIXTURE_TEST_CASE(bit_sync_basic, BitSyncFixture) {
    reset();

    // Output should initially be 0
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Change input to 1
    dut->data_in = 1;

    // Need 2 clock cycles to synchronize (2-stage synchronizer)
    tick();
    // After 1 cycle, may still be 0
    tick();
    // After 2 cycles, should definitely be 1
    tick();

    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Change back to 0
    dut->data_in = 0;
    tick();
    tick();
    tick();

    BOOST_CHECK_EQUAL(dut->data_out, 0);
}

BOOST_AUTO_TEST_SUITE_END()
