
# SPI Master Core with Wishbone BUS Interface



A synthesizable, full-duplex **Serial Peripheral Interface (SPI) Master IP Core** with an integrated **Wishbone B3 SoC bus interface** designed in Verilog HDL. Supports programmable clock generation, variable word lengths, independent transmit/receive edge polarity, multi-device slave select decoding, and automated interrupt assertion.


<strong>SPI MASTER CORE ARCHITECTURE & DESIGN BLOCKS OF SPI MASTER CORE ARCHITECTURE</strong>

<p align="center">
  <img src="https://github.com/sathvika1128/SPI/blob/main/architecture.png">
</p>

---

## 2. Register Map (Wishbone Memory-Mapped I/O)

All registers are accessible via 32-bit Wishbone word read/write transactions:

| Address Offset | Register Name | Access | Width | Description |
| :---: | :--- | :---: | :---: | :--- |
| `5'h00` | **`SPI_RX_0` / `SPI_TX_0`** | R/W | 32-bit | Transmit Data Register 0 (write) / Receive Data Register 0 (read). |
| `5'h04` | **`SPI_RX_1` / `SPI_TX_1`** | R/W | 32-bit | Transmit/Receive Data Register 1 (used for transfers > 32 bits). |
| `5'h08` | **`SPI_RX_2` / `SPI_TX_2`** | R/W | 32-bit | Transmit/Receive Data Register 2 (used for transfers > 64 bits). |
| `5'h0C` | **`SPI_RX_3` / `SPI_TX_3`** | R/W | 32-bit | Transmit/Receive Data Register 3 (used for transfers > 96 bits). |
| `5'h10` | **`SPI_CTRL`** | R/W | 14-bit | Control and Status Register (Mode, Length, Go, Interrupt). |
| `5'h14` | **`SPI_DIVIDE`** | R/W | 8-bit | Programmable Clock Divider Register (determines `SCLK` speed). |
| `5'h18` | **`SPI_SS`** | R/W | 8-bit | Target Slave Select Register (asserts corresponding `ss_pad_o`). |

---

## 3. Control & Status Register (`SPI_CTRL`) Bitfield

```text
 13     12    11       10           9         8        7       6        0
+-----+-----+-----+------------+------------+----+-----------+------------+
| ASS | IE  | LSB | TX_NEGEDGE | RX_NEGEDGE | GO |  RESERVED |  CHAR_LEN  |
+-----+-----+-----+------------+------------+----+-----------+------------+
```

| Bit | Name | Default | Functionality |
| :---: | :--- | :---: | :--- |
| **13** | **`ASS`** | `0` | **Auto Slave Select:** 1 = Automatically drives `ss_pad_o` active-low during transfer and deasserts high when idle. |
| **12** | **`IE`** | `0` | **Interrupt Enable:** 1 = Asserts `wb_int_o` on transfer completion. |
| **11** | **`LSB`** | `0` | **Bit Order:** 0 = MSB first (standard SPI), 1 = LSB first. |
| **10** | **`TX_NEGEDGE`** | `0` | **Transmit Edge:** 1 = Transmit on SCLK falling edge, 0 = Transmit on rising edge. |
| **9** | **`RX_NEGEDGE`** | `0` | **Receive Edge:** 1 = Sample MISO on SCLK falling edge, 0 = Sample on rising edge. |
| **8** | **`GO / BUSY`** | `0` | **Start / Status:** Write `1` to begin transfer. Hardware clears bit to `0` when transfer finishes. |
| **6:0** | **`CHAR_LEN`** | `0` | **Transfer Length:** Specifies transfer length in bits (`1` to `127` bits; `0` = 128 bits). |

---

## 4. SPI Modes & Clock Generation

The core supports all 4 standard SPI modes by configuring `TX_NEGEDGE` and `RX_NEGEDGE`:

| SPI Mode | CPOL | CPHA | `TX_NEGEDGE` | `RX_NEGEDGE` | SCLK Idle | Sample Edge | Shift/Drive Edge |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mode 0** | `0` | `0` | `1` | `0` | Low | Rising Edge | Falling Edge |
| **Mode 1** | `0` | `1` | `0` | `1` | Low | Falling Edge | Rising Edge |
| **Mode 2** | `1` | `0` | `0` | `1` | High | Falling Edge | Rising Edge |
| **Mode 3** | `1` | `1` | `1` | `0` | High | Rising Edge | Falling Edge |

### SCLK Frequency Formulation:
The serial clock period is derived from the Wishbone system clock via the 8-bit programmable divider:

$$F_{\text{SCLK}} = \frac{F_{\text{sys}}}{2 \times (\text{DIVIDER} + 1)}$$

* For $F_{\text{sys}} = 50\text{ MHz}$ (Wishbone system clock) and $\text{DIVIDER} = 4$:
  $$F_{\text{SCLK}} = \frac{50\text{ MHz}}{2 \times (4 + 1)} = \frac{50\text{ MHz}}{10} = \mathbf{5\text{ MHz}}$$

---

## 5. Verification Test Suite ([`tb.v`](tb.v))

The self-checking testbench executes 8 distinct verification scenarios with automated scoreboard assertion checks:

```text
==================================================================
       STARTING SPI MASTER WITH WISHBONE INTERFACE TESTBENCH       
==================================================================

[TEST 1] Verifying Register Reset Default States...
[PASS] Reset DIVIDER default is 0x00                 | Received: 0x00 (Expected: 0x00)
[PASS] Reset SS default is 0x00                      | Received: 0x00 (Expected: 0x00)

[TEST 2] Verifying Programmable Clock Divider...
[PASS] Divider programmed to 4                       | Received: 0x04 (Expected: 0x04)
[PASS] Divider reprogrammed to 8                     | Received: 0x08 (Expected: 0x08)

[TEST 3] Testing Mode 0 (CPOL=0, CPHA=0, MSB-First) Full-Duplex Loopback...
[PASS] Mode 0 Loopback Data Match (0x5A)             | Received: 0x5a (Expected: 0x5a)

[TEST 4] Testing Mode 1 (CPOL=0, CPHA=1, MSB-First) Full-Duplex Loopback...
[PASS] Mode 1 Loopback Data Match (0xA5)             | Received: 0xa5 (Expected: 0xa5)

[TEST 5] Testing LSB-First Bit Ordering Transfer...
[PASS] LSB-First Loopback Data Match (0x37)          | Received: 0x37 (Expected: 0x37)

[TEST 6] Testing Variable Character Length (4-bit Transfer)...
[PASS] 4-Bit Character Length Match (0xB)            | Received: 0x0b (Expected: 0x0b)

[TEST 7] Testing Auto Slave Select (ASS) Decoding...
[PASS] Slave 2 asserted active-low (0xFB) during transfer | Received: 0xfb (Expected: 0xfb)
[PASS] Slave Select deasserts high (0xFF) after transfer  | Received: 0xff (Expected: 0xff)

[TEST 8] Testing Interactive SPI Slave Communication...
[PASS] Slave Response Payload Received (0xA5)        | Received: 0xa5 (Expected: 0xa5)

==================================================================
             SPI MASTER VERIFICATION SCOREBOARD                   
==================================================================
 Total Assertions Checked : 11
 Total Passing Checks     : 11
 Total Error Count        : 0

 >>> [STATUS: ALL SPI MASTER VERIFICATION TESTS PASSED!] <<< 
 [CONFIRMED] Programmable clock divider functionality verified.
 [CONFIRMED] Full-duplex serial transmission verified across SPI modes.
 [CONFIRMED] Auto Slave Select and multi-slave decoding verified.
 [CONFIRMED] Wishbone SoC bus read/write handshakes verified.
==================================================================
```

---

## 6. FPGA Implementation & Synthesis Results

The SPI Master core was synthesized targeting the **Xilinx Artix-7 Basys 3 FPGA (`xc7a35tcpg236-1`)** using **Vivado Design Suite (out-of-context synthesis)** with zero timing violations and zero inferred latches.

### Hardware Resource Utilization:

| Resource | Used | Available on Basys 3 (`xc7a35t`) | Utilization % |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | **118** | 20,800 | **0.57%** |
| -- *LUT2* | 5 | - | - |
| -- *LUT3* | 11 | - | - |
| -- *LUT4* | 23 | - | - |
| -- *LUT5* | 32 | - | - |
| -- *LUT6* | 47 | - | - |
| **Slice Registers (FFs)** | **71** | 41,600 | **0.17%** |
| -- *FDCE* | 70 | - | - |
| -- *FDPE* | 1 | - | - |
| **Carry Chains (`CARRY4`)** | **1** | 5,200 | **0.02%** |
| **Inferred Latches** | **0** | - | **0.00% (Clean Synchronous RTL)** |

### Module Hierarchy Area Breakdown:

| Module Instance | Sub-block | Cell Count | Primary Logic Functions |
| :--- | :--- | :---: | :--- |
| `top` | `spi_top` | **190** | Complete Wishbone SPI subsystem |
| `top/SR` | [`spi_shift_reg`](spi_shift_reg.v) | **98** | Full-duplex shift register, MSB/LSB multiplexer, bit counter |
| `top/SC` | [`spi_clgen`](spi_clgen.v) | **39** | Programmable baud rate clock generator & edge detectors (`cpol_0`, `cpol_1`) |
| Top-level Glue | Wishbone Decoder | **53** | 32-bit Wishbone address decode, register muxes, interrupt & `wb_ack_out` |

---

