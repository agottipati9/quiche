#!/bin/bash

# --- 1. Set and Validate Algorithm ---

# List of valid congestion control algorithms
VALID_ALGORITHMS="QBIC RENO BBRR B2ON PRGC LLMX"

# Set default algorithm to QBIC if no argument is provided
DEFAULT_ALGORITHM="QBIC"
CC_ALGORITHM=${1:-$DEFAULT_ALGORITHM}

# Set default ip to localhost if no argument is provided
DEFAULT_BASE_IP=localhost
IP=${2:-$DEFAULT_BASE_IP}

# Set default port to 4430 if no argument is provided
DEFAULT_BASE_PORT=4430
PORT=${3:-$DEFAULT_BASE_PORT}

# Set default file size to 100 Mb to 4430 if no argument is provided
B_IN_MB_SIZE=1048576
DEFAULT_FILE_SIZE_MB=100
FILE_SIZE=${4:-$DEFAULT_FILE_SIZE_MB}
FILE_SIZE_B=$((FILE_SIZE * B_IN_MB_SIZE))

# Check if the chosen algorithm is in the valid list
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [QBIC|RENO|BBRR (BBRv1)|B2ON (BBRv3)|PRGC (Prague Cubic)|LLMX (LLM Modified BBR)] IP PORT FILE_SIZE (MB)"
    echo "Example: $0 QBIC localhost 4430 100"
    exit 1
fi

# --- 2. Setup Log File ---

# Create a unique log file for this test run, e.g., "performance_log_BBRR.txt"
CLIENT_LOG_FILE="performance_log_${CC_ALGORITHM}_client.txt"
echo "Starting test for $CC_ALGORITHM. Output will be in ${CLIENT_LOG_FILE}"

# Write a header *into* the log file (overwrites old file)
echo "--- Test for Congestion Control Algorithm: $CC_ALGORITHM ---" > ${CLIENT_LOG_FILE}

# --- 3. Run Client ---
# We now use $CC_ALGORITHM for the --connection_options
# We use '>>' to *append* the client output to the log file after our header
echo "Running client and logging..."
./quiche/bazel-bin/quiche/quic_client \
  --disable_certificate_verification \
  --v=1 \
  --stderrthreshold=0 \
  --drop_response_body=true \
  --connection_options=$CC_ALGORITHM \
  https://${IP}:${PORT}/${FILE_SIZE_B} \
  >> ${CLIENT_LOG_FILE} 2>&1

# --- 4. Stop Server ---
echo "Test complete."
echo "Logs are in ${CLIENT_LOG_FILE}. Stop server and download logs."
echo "Run 'cat ${CLIENT_LOG_FILE}' to see the results."