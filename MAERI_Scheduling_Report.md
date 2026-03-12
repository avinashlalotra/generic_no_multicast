# MAERI Packet Scheduler & DN Allocation Report

This document explains the architecture, scheduling, and routing design of the packet scheduler wrapper you've just built. It is written to give you a complete human-readable understanding of the design choices, how virtual neurons are mapped, and how the pipeline avoids data loss.

---

## 1. Virtual Neuron (VN) Allocation Strategy
In the MAERI architecture, a **Virtual Neuron (VN)** is responsible for computing a single element of your output matrix $C$. 
Since you are multiplying Matrix A ($M \times K$) by Matrix B ($K \times N$), each output element $C_{i,j}$ conceptually requires a dot product consisting of $K$ scalar multiplications.

To parallelize this completely across the hardware, we map **each multiplication to a dedicated Multiplier Switch (MS)**. 
- **Number of VNs required** = $M \times N$
- **MS per VN required** = $K$ 
- **Total MS utilized** = $M \times N \times K$

### Contiguous Mapping Strategy
The MS units are physically allocated to VNs in contiguous blocks. The scheduler conceptually calculates a unique numeric identifier for each VN using `(i * N + j)`. Multiplied by $K$, this gives the base Multiplier Switch index for that VN.

Using the $2 \times 2$ matrices with $K=2$ example:
- **VN1 ($C_{00}$)** Uses MS0 and MS1
- **VN2 ($C_{01}$)** Uses MS2 and MS3
- **VN3 ($C_{10}$)** Uses MS4 and MS5
- **VN4 ($C_{11}$)** Uses MS6 and MS7

Inside the MAERI architecture, the adder tree will mathematically group these statically assigned contiguous MS pairs.

---

## 2. Scheduling Algorithm: Stationary Row Execution
To compute the matrix multiplication, the scheduler uses a **Stationary Phase** approach. The goal is to maximize data locality and reuse. Rather than sending A and B elements simultaneously, the scheduler sends Matrix A into the MS units so they can "stay stationary" while Matrix B streams past them.

This happens in two stages:
1. **Phase A (Stationary Load):** The scheduler traverses the entire combination of output neurons and sends the corresponding elements from Matrix A. These elements sit "stationary" inside the Multiplier Switches, waiting for their corresponding B multiplier.
2. **Phase B (Streaming):** The scheduler traverses the exact same loop sequence again, but this time pulls elements from Matrix B. As these elements arrive at the MS units, they immediately multiply with the stationary A values.

### Loop Ordering
To ensure the correct elements are read from memory and sent to the correct MS unit, the scheduler utilizes the following nested loop traversal sequence:
```verilog
for j in 0..N-1        // Column of B (and column of C)
  for i in 0..M-1      // Row of A (and row of C)
    for t in 0..K-1    // Element index inside the dot product
```
Because the simulated hardware currently does **not** support multicast (conceptually broadcasting one element of A to multiple MS units simultaneously), the scheduler explicitly unicasts duplicates. For instance, $A_{00}$ is read and unicast to MS0 (for VN1), and then later read again and unicast to MS2 (for VN2).

---

## 3. Path Bit (Mask) Generation
The Distribution Network (DN) uses a "Path Bit" mask to route a data packet through the switch fabric to the correct MS unit. Since we are using unicast routing, **exactly one bit is set to `1` per active packet**.

For a given iteration `(j, i, t)`, the target MS index is mathematically derived as:
```verilog
ms_index = ((i * N + j) * K) + t;
```
The scheduler hardware translates this index to a one-hot encoded routing mask by left-shifting:
```verilog
mask_val = 1 << ms_index;
```
**Example:** When `i=1` (Row 1), `j=1` (Col 1), and `t=0` (first element in dot product), `ms_index = ((1*2 + 1)*2) + 0 = 6`. 
The mask generated is `01000000`, steering the data payload exclusively to MS6.

---

## 4. Handshake Protocol & Pipeline Backpressure (The Wrapper)
Once the packets are formulated, they must traverse a shared Distribution Network, which might experience structural or temporal congestion.

To seamlessly handle congestion, the inner `packet_scheduler.v` was housed inside a newer `scheduler_wrapper.v` that implements standard `en/rdy` (Enable/Ready) handshakes:
- **`config_dn`:** Carries the routing Mask (`config_data`) and path Enable (`config_en`).
- **`data_dn`:** Carries the payload Element (`data_data`) and data Enable (`data_en`).

### Zero-Data-Loss Pipelining
Because the system utilizes synchronous memory (where a read request takes 1 clock cycle to return payload data), we established a pipelined backpressure lock.
```verilog
wire stall = (a_pkt_valid | b_pkt_valid) & !out_ready;
```
Using the `stall` mechanism, if the DN becomes congested (`!out_ready`), the scheduler freezes identically in time. It prevents the internal `i/j/t` counters from incrementing, holds the `state` flip-flops, and forces the `simple_mem` address lines to hold perfectly stationary until the downstream sink removes the stall. This ensures that an arbitrary pipeline bubble never triggers a dropped or duplicated matrix calculation.

---

## 5. Scalability & Generalization
- **Strictly Parameterized Limits:** By mapping strictly parameterized values `(M, N, K, NUM_MS, DATA_W)`, this logic perfectly generalizes to infinitely larger matrix dimensions (e.g., K=16, M=4).
- **No Additional Changes Required:** Standard usage simply entails altering the Top-Level parameters and ensuring `NUM_MS >= M*N*K`.
- **Future "Multicast" Enhancements:** Currently, $A$ and $B$ values are fetched redundantly for multiple VNs. As you scale, simple memory bandwidth fetching will organically become a bottleneck. The next evolutionary architectural step would be implementing a "Multicast Mask" (e.g., `mask = 00000101`) to conceptually send $A_{00}$ simultaneously to both MS0 and MS2 using a single memory read cycle.
