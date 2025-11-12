#!/bin/bash

# --- 1. Set and Validate Algorithm ---

# List of valid congestion control algorithms
VALID_ALGORITHMS="QBIC RENO BBRR B2ON PRGC LLMX"

# Set default algorithm to QBIC if no argument is provided
DEFAULT_ALGORITHM="QBIC"
CC_ALGORITHM=${1:-$DEFAULT_ALGORITHM}

# Set default port to 4430 if no argument is provided
DEFAULT_BASE_PORT=4430
PORT=${2:-$DEFAULT_BASE_PORT}

# Check if the chosen algorithm is in the valid list
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [QBIC|RENO|BBRR (BBRv1)|B2ON (BBRv3)|PRGC (Prague Cubic)|LLMX (LLM Modified BBR)] PORT"
    echo "Example: $0 QBIC 4430"
    exit 1
fi

# --- 2. Setup Log File ---

# Create a unique log file for this test run, e.g., "performance_log_BBRR.txt"
SERVER_LOG_FILE="performance_log_${CC_ALGORITHM}_server.txt"
echo "Starting test for $CC_ALGORITHM. Output will be in ${SERVER_LOG_FILE}"

# Write a header *into* the log file (overwrites old file)
echo "--- Test for Congestion Control Algorithm: $CC_ALGORITHM ---" > ${SERVER_LOG_FILE}

# --- 3. Create Certificates (if they don't exist) ---
if [ ! -f cert.pem ]; then
    echo "Creating test certificates..."
    openssl req -new -x509 -nodes -days 365 \
      -keyout key.pem -out cert.pem \
      -subj "/C=US/ST=Test/L=Test/O=Test/CN=localhost"
fi

# --- 4. Start Server ---
echo "Starting server in dynamic response mode..."
./quiche/bazel-bin/quiche/quic_server \
  --port=$PORT \
  --certificate_file=./cert.pem \
  --key_file=./key.pem \
  --generate_dynamic_responses=true \
  --v=1 \
  --stderrthreshold=0 \
  >> ${SERVER_LOG_FILE} 2>&1