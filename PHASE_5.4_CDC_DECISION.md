# Phase 5.4: Clock Domain Crossing Decision

**Date**: 2025-11-26
**Status**: [0K] DECISION DOCUMENTED - CDC NOT REQUIRED
**Rationale**: System-level CDC handled by NoC/interconnect

---

## Decision Summary

**Phase 5.4 CDC implementation is SKIPPED** with the following design requirement:

> **UART Peripheral Clock Domain Requirement:**
> The AXI-Lite interface and UART core logic **must operate on the same clock** (`uart_clk`).
> Clock domain crossing between system/NoC clock domains and the UART peripheral clock
> domain shall be handled by the **system interconnect/NoC infrastructure**.

---

## Rationale

### 1. Standard SoC Practice

In typical SoC architectures, clock domain crossing is handled at the **system interconnect level**, not within individual peripherals:

```
System Architecture:

CPU Core Domain (cpu_clk - e.g., 1 GHz)
    ↓
NoC/Interconnect (noc_clk - e.g., 500 MHz)
    ↓
    ├─── [CDC Bridge] ──→ Peripheral Subsystem A (periph_clk_a - e.g., 100 MHz)
    │                         ├─ UART 0 (periph_clk_a)
    │                         ├─ UART 1 (periph_clk_a)
    │                         └─ SPI 0 (periph_clk_a)
    │
    ├─── [CDC Bridge] ──→ Peripheral Subsystem B (periph_clk_b - e.g., 200 MHz)
    │                         ├─ PCIe Controller (periph_clk_b)
    │                         └─ Ethernet MAC (periph_clk_b)
    │
    └─── [CDC Bridge] ──→ Memory Subsystem (mem_clk - e.g., 800 MHz)
                              └─ DDR Controller (mem_clk)
```

**Key Principle**: Each subsystem runs on its own clock domain, with CDC handled by the interconnect fabric.

### 2. Benefits of System-Level CDC

**Centralized CDC Infrastructure:**
- [0K] **Reusable**: Single CDC implementation serves all peripherals
- [0K] **Well-Tested**: System interconnect CDC is thoroughly verified
- [0K] **Optimized**: Can use async FIFOs, clock crossing bridges, etc.
- [0K] **Configurable**: NoC can adjust CDC strategy per connection

**Peripheral Design Simplification:**
- [0K] **Single Clock Domain**: Simpler logic, easier verification
- [0K] **No Metastability Concerns**: CDC handled externally
- [0K] **Faster Development**: Focus on functional correctness
- [0K] **Easier Integration**: Standard AXI-Lite slave interface

**System-Level Flexibility:**
- [0K] NoC can group peripherals by clock domain
- [0K] Clock gating for power management handled at subsystem level
- [0K] Easy to change clock ratios without modifying peripherals

### 3. Industry Examples

**ARM AMBA Infrastructure:**
- AXI Interconnect includes optional clock crossing bridges
- Peripherals designed as single-clock AXI slaves
- CDC inserted at interconnect boundaries

**Xilinx/AMD SoCs:**
- AXI SmartConnect handles CDC between clock domains
- AXI GPIO, AXI UART, etc. all single-clock designs
- System composer connects domains via SmartConnect

**RISC-V SoC Platforms:**
- TileLink crossbar handles CDC at system level
- Peripheral devices single-clock by design
- CDC inserted via TileLink widgets

### 4. UART-Specific Considerations

**UART Serial Interface:**
- Baud rate is **very slow** compared to AXI bus (9600-921600 baud)
- Internal `baud_gen` module already handles timing division
- Serial I/O inherently async - handled by `bit_sync` module

**Typical Clock Speeds:**
- AXI peripheral bus: 50-200 MHz
- UART serial baud: 9600 Hz - 921 KHz (0.0096-0.921 MHz)
- Ratio: 50,000:1 to 200,000:1

**Observation**: The AXI clock is **already orders of magnitude faster** than UART serial timing. Adding a separate UART clock domain provides **no benefit**.

### 5. Complexity vs. Benefit Analysis

**Adding Internal CDC Would Require:**
- Async FIFO for register read/write data
- Synchronizers for control signals
- Handshake logic for clock crossing
- Extensive testing of clock ratios
- Metastability verification
- ~500-1000 additional lines of RTL
- Significantly more complex verification

**Benefits Provided:**
- None (NoC already provides CDC)
- Adds redundant complexity
- Increases area and power consumption
- Harder to verify and maintain

**Conclusion**: Cost >> Benefit → Skip internal CDC

---

## Design Specification

### Clock Domain Architecture

**uart_axi_top Module:**
```systemverilog
module uart_axi_top #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int TX_FIFO_DEPTH = 8,
    parameter int RX_FIFO_DEPTH = 8
) (
    // Single clock domain for entire peripheral
    input  logic                    clk,        // Peripheral subsystem clock
    input  logic                    rst_n,      // Active-low reset

    // AXI-Lite interface (runs on 'clk')
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic                    awvalid,
    output logic                    awready,
    // ... (all AXI signals synchronous to 'clk')

    // UART serial interface (async, handled by bit_sync)
    output logic                    uart_tx,
    input  logic                    uart_rx,

    // Interrupt (synchronous to 'clk')
    output logic                    irq
);
```

**Clock Domain Diagram:**
```
                    System Interconnect/NoC
                            |
                    [CDC Bridge/Async FIFO]  ← Handles system clock → uart_clk crossing
                            ↓
                   +------------------+
                   | uart_axi_top     |
                   | (Single Clock)   |
                   |                  |
clk (uart_clk) →→→→| clk              |
                   |                  |
                   | axi_lite_slave_if|  All logic
                   | uart_top         |  runs on
                   |   uart_regs      |  single
                   |   baud_gen       |  'clk'
                   |   uart_tx_path   |
                   |   uart_rx_path   |
                   +------------------+
                            ↓
                      uart_tx, uart_rx (async serial I/O, handled by bit_sync)
```

### Integration Requirements

**System Integrator Checklist:**

1. **Clock Connection:**
   - Connect peripheral subsystem clock to `uart_axi_top.clk`
   - Ensure NoC/interconnect provides CDC from system clock to peripheral clock

2. **Reset:**
   - Provide synchronized reset to peripheral subsystem
   - Reset must be synchronous to `uart_clk` (peripheral clock)

3. **AXI-Lite Connection:**
   - NoC/interconnect must insert CDC bridge **before** uart_axi_top
   - CDC bridge converts: (noc_clk, AXI) → (uart_clk, AXI)
   - uart_axi_top sees only synchronized AXI transactions

4. **Clock Gating (Optional):**
   - Can gate `uart_clk` when UART not in use (power saving)
   - Must ungated before any AXI access
   - Peripheral provides status via registers when active

### Example System Integration

**Using Async FIFO Bridge:**
```systemverilog
// System-level integration
module peripheral_subsystem (
    input  logic sys_clk,          // NoC/system clock
    input  logic uart_clk,         // Peripheral subsystem clock
    input  logic rst_n,

    // AXI from NoC (sys_clk domain)
    axi_lite_if.slave noc_axi,

    // UART pins
    output logic uart_tx,
    input  logic uart_rx
);

    // CDC Bridge: sys_clk → uart_clk
    axi_lite_if #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) uart_axi_sync();

    axi_cdc_bridge cdc_bridge (
        .s_clk      (sys_clk),
        .s_axi      (noc_axi),       // From NoC
        .m_clk      (uart_clk),
        .m_axi      (uart_axi_sync), // To UART
        .rst_n      (rst_n)
    );

    // UART Peripheral (single clock domain)
    uart_axi_top uart0 (
        .clk        (uart_clk),      // Single clock
        .rst_n      (rst_n),
        // AXI interface (uart_clk domain)
        .awaddr     (uart_axi_sync.awaddr),
        .awvalid    (uart_axi_sync.awvalid),
        .awready    (uart_axi_sync.awready),
        // ...
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .irq        (uart_irq)
    );

endmodule
```

---

## Documentation Updates

### Interface Specifications

**Updated uart_axi_top Clock Requirement:**

> **Clock Domain:**
> - Single clock domain design
> - All AXI-Lite interface signals synchronous to `clk` input
> - UART serial signals (uart_tx, uart_rx) are asynchronous and handled by internal synchronizers
> - Clock domain crossing between system/NoC clock and `clk` must be handled by external infrastructure

**Updated Integration Guide:**

> **System Integration:**
> 1. Provide stable clock to `uart_axi_top.clk` (e.g., 50-200 MHz)
> 2. Insert CDC bridge between NoC clock domain and uart_axi_top if clocks differ
> 3. UART peripheral operates entirely in `clk` domain
> 4. Serial I/O synchronization handled internally by `bit_sync` module

### User Documentation

**Clock Requirements:**
```
Module: uart_axi_top
Clock Input: clk
Frequency Range: 10 MHz - 200 MHz (typical)
Clock Domain: Single
CDC Required: External (if connecting to different clock domain)
```

**Recommendations:**
- For standalone use: Connect to system clock directly
- For SoC integration: Use NoC CDC bridge
- For low-power: Use dedicated peripheral subsystem clock with gating

---

## Verification Implications

### Testing Strategy (Simplified)

**Single-Clock Testing:**
- [0K] All existing tests remain valid (already single-clock)
- [0K] No need for multi-clock simulations
- [0K] No metastability testing required
- [0K] Simpler test infrastructure

**Focus Areas:**
- AXI-Lite protocol compliance
- UART functional correctness
- Register access timing
- Interrupt generation
- FIFO operation

**NOT Required:**
- ❌ Clock ratio sweeps
- ❌ Metastability injection
- ❌ Async FIFO testing
- ❌ Clock domain crossing verification

### Test Results

**Current Status:**
- All 11 test suites: [0K] PASSING
- Single clock domain: [0K] VERIFIED
- Ready for system integration: [0K] YES

---

## Trade-Off Analysis

### Option A: Internal CDC (NOT CHOSEN)

**Pros:**
- Self-contained CDC within peripheral
- Could operate on different clock than AXI bus

**Cons:**
- Redundant with system-level CDC
- Adds 500-1000 lines of complex RTL
- Requires extensive CDC verification
- Increases area and power
- No practical benefit (NoC already provides CDC)
- Standard practice is system-level CDC

### Option B: Single Clock Domain (CHOSEN [0K])

**Pros:**
- [0K] Standard industry practice
- [0K] Simpler design and verification
- [0K] Smaller area and power footprint
- [0K] Relies on proven NoC CDC infrastructure
- [0K] Consistent with ARM, Xilinx, RISC-V designs
- [0K] Already implemented and tested

**Cons:**
- Requires external CDC (but NoC provides this anyway)
- Less "academic" (but more practical)

**Decision**: Option B chosen for practical, industry-standard design.

---

## Future Considerations

### If Standalone CDC Needed

In the unlikely event that standalone CDC is needed (e.g., FPGA without NoC):

**Recommended Approach:**
1. Use vendor-provided CDC IP (Xilinx AXI Clock Converter, Intel Avalon Clock Crossing)
2. Insert async FIFO between interconnect and uart_axi_top
3. Do NOT modify uart_axi_top itself - keep it single-clock

**External CDC Wrapper Example:**
```systemverilog
module uart_with_cdc_wrapper (
    input  logic sys_clk,
    input  logic uart_clk,
    // AXI on sys_clk
    // CDC bridge inserted here
    // uart_axi_top on uart_clk
);
```

This maintains uart_axi_top as a clean single-clock peripheral.

---

## Conclusion

**Phase 5.4 CDC Decision: SKIP internal CDC implementation**

**Rationale:**
1. System-level CDC is standard industry practice
2. NoC/interconnect infrastructure handles clock domain crossing
3. UART peripheral designed as single-clock AXI-Lite slave
4. Adds unnecessary complexity with no benefit
5. Consistent with ARM, Xilinx, and RISC-V design methodologies

**Design Requirement:**
> uart_axi_top operates in a single clock domain (`clk`). External CDC must be
> provided by system interconnect when crossing from different clock domains.

**Status:**
- [0K] Design decision documented
- [0K] Interface specification updated
- [0K] Ready for system integration
- [0K] Phase 5 can proceed to completion

**Next Steps:**
- Mark Phase 5.4 as "N/A - System-level CDC" in tracking
- Proceed to Phase 5 wrap-up and exit criteria
- Document final peripheral specifications

---

**Document Version**: 1.0
**Authors**: Claude + User
**Review Status**: Approved
**Design Impact**: Low (confirms existing single-clock architecture)
