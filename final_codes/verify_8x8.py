import sys

def verify():
    # Matrix A: 8x8 Identity
    matrix_a = [[0]*8 for _ in range(8)]
    for i in range(8):
        matrix_a[i][i] = 1
    
    # Matrix B: 8x8 Sequence 1..64, stored in column-major
    # B[i][j] = (j*8 + i) + 1
    matrix_b = [[0]*8 for _ in range(8)]
    for j in range(8):
        for i in range(8):
            matrix_b[i][j] = (j*8 + i) + 1
            
    # Expected result order: global_vn maps to i_curr = global_vn / 8, j_curr = global_vn % 8
    expected = []
    for global_vn in range(64):
        i_curr = global_vn // 8
        j_curr = global_vn % 8
        val = 0
        for k in range(8):
            val += matrix_a[i_curr][k] * matrix_b[k][j_curr]
        expected.append(val)
        
    # Read hardware results
    try:
        hw_results = []
        with open("results_8x8.txt", "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    hw_results.append(int(line))
    except FileNotFoundError:
        print("Error: results_8x8.txt not found.")
        return
    except ValueError as e:
        print(f"Error parsing hex/int: {e}")
        return

    print(f"{'Idx':<4} | {'Exp':<6} | {'HW':<6} | {'Status'}")
    print("-" * 30)
    
    matches = 0
    for i in range(64):
        exp = expected[i]
        hw = hw_results[i] if i < len(hw_results) else None
        
        status = "MATCH" if exp == hw else "MISMATCH"
        if status == "MATCH": matches += 1
        
        hw_str = str(hw) if hw is not None else "N/A"
        print(f"{i:<4} | {exp:<6} | {hw_str:<6} | {status}")
        
    print("-" * 30)
    print(f"Total Matches: {matches}/64")
    if matches == 64:
        print("Verification SUCCESSFUL!")
    else:
        print("Verification FAILED.")

if __name__ == "__main__":
    verify()
