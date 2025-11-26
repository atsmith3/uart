/*
 * Boost.Test Main Entry Point
 *
 * This file provides the main() function for all test suites.
 */

#define BOOST_TEST_MODULE uart_tests
#include <boost/test/unit_test.hpp>
#include <verilated.h>

// Global setup/teardown
struct GlobalFixture {
    GlobalFixture() {
        // Initialize Verilator
        Verilated::debug(0);
        Verilated::randReset(2);
        Verilated::traceEverOn(true);
    }

    ~GlobalFixture() {
        // Cleanup Verilator
    }
};

BOOST_GLOBAL_FIXTURE(GlobalFixture);
