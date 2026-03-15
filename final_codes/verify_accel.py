import random
import subprocess
import os
import sys
import re

def generate_matrix(rows, cols, name):
    matrix = [[random.randint(0, 10) for _ in range(cols)] for _ in range(rows)]
    return matrix

def write_mem_file(matrix, rows, cols, filename, column_major=False):
    with open(filename, "w") as f:
        # Verilog hex format
        f.write(f"{rows:x}\n")
        f.write(f"{cols:x}\n")
        if column_major:
            for j in range(cols):
                for i in range(rows):
                    f.write(f"{matrix[i][j]:x}\n")
        else:
            for row in matrix:
                for val in row:
                    f.write(f"{val:x}\n")

def run_simulation():
    # print("Compiling and running simulation...")
    # Use the same command as before
    # Added -Wall to see warnings
    cmd = "iverilog -g2012 -o sim.out controller.v accel.v tb_accel.v art.v dn.v mn.v art_config_hw/art_config_unit.v && vvp sim.out"
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Simulation failed:\n{e.stderr}")
        return None

def parse_results(sim_output):
    # Look for lines like "mem_C[2] =     5"
    results = []
    lines = sim_output.splitlines()
    for line in lines:
        match = re.search(r"mem_C\[(\d+)\] =\s+(\d+|x)", line)
        if match:
            val_str = match.group(2)
            if val_str == 'x':
                results.append(None)
            else:
                results.append(int(val_str))
    
    # Header check
    # TB prints: M =           2, N =           2
    m_match = re.search(r"M =\s+(\d+)", sim_output)
    n_match = re.search(r"N =\s+(\d+)", sim_output)
    
    m_val = int(m_match.group(1)) if m_match else 0
    n_val = int(n_match.group(1)) if n_match else 0
    
    return m_val, n_val, results

def calculate_expected(a, b, m, k, n):
    expected = []
    # Scheduler maps global_vn to i = global_vn // n, j = global_vn % n
    for global_vn in range(m * n):
        i = global_vn // n
        j = global_vn % n
        val = 0
        for x in range(k):
            val += a[i][x] * b[x][j]
        expected.append(val)
    return expected

def verify(m, k, n):
    if k > 8:
        print("Error: K cannot be greater than NUM_MS (8)")
        return

    print(f"Testing Matrix Multiplication: ({m}x{k}) * ({k}x{n})")
    
    # 1. Generate Matrices
    a = generate_matrix(m, k, "A")
    b = generate_matrix(k, n, "B")
    
    # 2. Write to files (using the names accel.v expects)
    # Note: Using matrices/mem_A_2x2.mem as the target since it's already in accel.v
    write_mem_file(a, m, k, "matrices/mem_A_2x2.mem", column_major=False)
    write_mem_file(b, k, n, "matrices/mem_B_2x2.mem", column_major=True)
    
    # 3. Run Simulation
    output = run_simulation()
    if output is None:
        return

    # 4. Parse Results
    m_sim, n_sim, hw_results = parse_results(output)
    
    if m_sim != m or n_sim != n:
        print(f"FAILURE: Dimension mismatch! Expected {m}x{n}, got {m_sim}x{n_sim}")
        # print(output) # Debug
        return

    # 5. Compare
    expected = calculate_expected(a, b, m, k, n)
    
    print(f"\n{'Idx':<4} | {'Expected':<10} | {'Hardware':<10} | {'Status'}")
    print("-" * 45)
    
    matches = 0
    for i in range(len(expected)):
        exp = expected[i]
        hw = hw_results[i] if i < len(hw_results) else None
        
        status = "MATCH" if exp == hw else "MISMATCH"
        if status == "MATCH": matches += 1
        
        hw_str = str(hw) if hw is not None else "N/A"
        print(f"{i:<4} | {exp:<10} | {hw_str:<10} | {status}")
        
    print("-" * 45)
    print(f"Total Matches: {matches}/{len(expected)}")
    
    if matches == len(expected):
        print("Verification SUCCESSFUL!")
    else:
        print("Verification FAILED.")

if __name__ == "__main__":
    if len(sys.argv) == 4:
        m = int(sys.argv[1])
        k = int(sys.argv[2])
        n = int(sys.argv[3])
    else:
        # Default test
        m, k, n = 2, 4, 2
        
    verify(m, k, n)
