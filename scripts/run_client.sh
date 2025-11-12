#!/bin/bash

# --- 1. Set and Validate Parameters ---

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

# Set default file size to 1000 Mb if no argument is provided
B_IN_MB_SIZE=1048576
DEFAULT_FILE_SIZE_MB=1000
FILE_SIZE=${4:-$DEFAULT_FILE_SIZE_MB}
FILE_SIZE_B=$((FILE_SIZE * B_IN_MB_SIZE))

# Set default number of trials to 10 if no argument is provided
DEFAULT_NUM_TRIALS=10
NUM_TRIALS=${5:-$DEFAULT_NUM_TRIALS}

# Set log dir
LOG_DIR=./logs

# Check if the chosen algorithm is in the valid list
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [ALGORITHM] [IP] [PORT] [FILE_SIZE_MB] [NUM_TRIALS]"
    echo "Valid Algorithms: QBIC|RENO|BBRR (BBRv1)|B2ON (BBRv3)|PRGC (Prague Cubic)|LLMX (LLM Modified BBR)"
    echo "Example: $0 QBIC localhost 4430 1000 10"
    exit 1
fi

echo "Starting test for $CC_ALGORITHM: $NUM_TRIALS trial(s)."

# --- 2. Run Trials ---

mkdir -p $LOG_DIR

# Loop from 1 to NUM_TRIALS
for (( I=1; I<=$NUM_TRIALS; I++ ))
do
    # --- 2a. Setup Log File ---
    # Create a unique log file for this specific trial
    CLIENT_LOG_FILE="performance_log_${CC_ALGORITHM}_client_${I}.txt"
    echo "--- Trial $I/$NUM_TRIALS: Starting test for $CC_ALGORITHM. Output will be in ${CLIENT_LOG_FILE} ---"

    # Write a header *into* the log file (overwrites old file)
    echo "--- Test for Congestion Control Algorithm: $CC_ALGORITHM --- Trial $I ---" > ${CLIENT_LOG_FILE}

    # --- 2b. Run Client ---
    # We now use $CC_ALGORITHM for the --connection_options
    # We use '>>' to *append* the client output to the log file after our header
    echo "Running client and logging to ${CLIENT_LOG_FILE}..."
    ./quiche/bazel-bin/quiche/quic_client \
      --disable_certificate_verification \
      --v=1 \
      --stderrthreshold=0 \
      --drop_response_body=true \
      --connection_options=$CC_ALGORITHM \
      https://${IP}:${PORT}/${FILE_SIZE_B} \
      >> ${CLIENT_LOG_FILE} 2>&1

    echo "Trial $I complete. Log is in ${CLIENT_LOG_FILE}."

    mv $CLIENT_LOG_FILE $LOG_DIR/$CLIENT_LOG_FILE
    
    # small delay between trials
    sleep 1 

done

# --- 3. Stop Server ---
echo "All $NUM_TRIALS trials complete."
echo "Stop server and download logs."
echo "Run 'cat performance_log_${CC_ALGORITHM}_client_*.txt' to see all results."