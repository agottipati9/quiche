#!/usr/bin/env python3

import sys
import re
import numpy as np

def parse_tput_log(filename):
    """
    Parses a log file to extract the *last* content-length and TTLB value.
    """
    content_length = None
    ttlb = None
    
    # Regex patterns
    length_pattern = re.compile(r"content-length (\d+)")
    ttlb_pattern = re.compile(r"TTLB\(us\): (\d+)")
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                length_match = length_pattern.search(line)
                if length_match:
                    content_length = int(length_match.group(1))
                
                ttlb_match = ttlb_pattern.search(line)
                if ttlb_match:
                    ttlb = int(ttlb_match.group(1))
    except FileNotFoundError:
        print(f"Error: Log file not found at {filename}", file=sys.stderr)
        sys.exit(1)
    
    return content_length, ttlb

def write_statistics(length_bytes, time_us, stats_filename, algorithm, data_filename):
    """
    Calculates and appends the throughput to a file.
    """
    if not length_bytes or not time_us:
        print(f"No 'content-length' or 'TTLB(us)' data found in {data_filename}.")
        return

    # --- Calculations ---
    time_sec = time_us / 1_000_000.0  # Convert microseconds to seconds
    total_bits = length_bytes * 8
    
    # Calculate throughput in Gbps (Gigabits per second)
    throughput_gbps = (total_bits / time_sec) / 1_000_000_000.0

    # Open the stats file in 'append' mode (a)
    with open(stats_filename, 'a') as f:
        f.write("\n--- 🚀 Throughput Test Results ---\n")
        f.write(f"Algorithm:    {algorithm}\n")
        f.write(f"Data File:    {data_filename}\n")
        f.write("-----------------------------------\n")
        f.write(f"File Size:    {(length_bytes / (1024**3)):.2f} GiB\n")
        f.write(f"Time Taken:   {time_sec:.2f} s\n")
        f.write(f"Throughput:   {throughput_gbps:.4f} Gbps\n")
        f.write("-----------------------------------\n")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 parse_tput_log.py <data_file> <algorithm_name> <stats_output_file>")
        sys.exit(1)
        
    data_file = sys.argv[1]
    algo_name = sys.argv[2]
    stats_file = sys.argv[3]
    
    length, time = parse_tput_log(data_file)
    write_statistics(length, time, stats_file, algo_name, data_file)