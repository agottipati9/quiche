#!/usr/bin/env python3

import sys
import re
import numpy as np

def parse_log(filename):
    """
    Parses a log file to extract all TTLB (Time to Last Byte) values.
    """
    latencies = []
    
    # Regex to find "TTLB(us): 123" and extract the number
    pattern = re.compile(r"TTLB\(us\): (\d+)")
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                match = pattern.search(line)
                if match:
                    # Add the extracted latency value as an integer
                    latencies.append(int(match.group(1)))
    except FileNotFoundError:
        print(f"Error: Log file not found at {filename}", file=sys.stderr)
        sys.exit(1)
    
    return latencies

def write_statistics(latencies, stats_filename, algorithm, data_filename):
    """
    Calculates and appends the mean, median, and p90 statistics to a file.
    """
    if not latencies:
        print(f"No 'TTLB(us):' data found in {data_filename}. Cannot calculate stats.")
        return

    # Convert to a NumPy array for easy calculations
    lat_array = np.array(latencies)
    
    count = len(lat_array)
    mean_val = np.mean(lat_array)
    median_val = np.median(lat_array)
    p90_val = np.percentile(lat_array, 90)

    # Open the stats file in 'append' mode (a)
    with open(stats_filename, 'a') as f:
        f.write("\n--- 📊 Latency Test Results ---\n")
        f.write(f"Algorithm:    {algorithm}\n")
        f.write(f"Data File:    {data_filename}\n")
        f.write(f"Total Samples:  {count}\n")
        f.write("----------------------------------\n")
        f.write(f"Mean (Average): {mean_val:.2f} us\n")
        f.write(f"Median (p50):   {median_val:.2f} us\n")
        f.write(f"p90 Latency:    {p90_val:.2f} us\n")
        f.write("----------------------------------\n")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 parse_log.py <data_file> <algorithm_name> <stats_output_file>")
        sys.exit(1)
        
    data_file = sys.argv[1]
    algo_name = sys.argv[2]
    stats_file = sys.argv[3]
    
    data = parse_log(data_file)
    write_statistics(data, stats_file, algo_name, data_file)