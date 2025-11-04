#!/bin/bash

# TODO: doesn't work, likely need to monitor cwnd changes from the server side

# --- 1. Set and Validate Algorithm ---

# List of valid congestion control algorithms
VALID_ALGORITHMS="QBIC RENO BBRR B2ON PRGC"

# Set default algorithm to QBIC if no argument is provided
DEFAULT_ALGORITHM="QBIC"
CC_ALGORITHM=${1:-$DEFAULT_ALGORITHM}

# Check if the chosen algorithm is in the valid list
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [QBIC|RENO|BBRR (BBRv1)|B2ON (BBRv3)|PRGC (Prague Cubic)]"
    exit 1
fi

# --- 2. Setup Log File ---

# Create a unique log file for this test run, e.g., "performance_log_BBRR.txt"
LOG_FILE="performance_log_${CC_ALGORITHM}.txt"
echo "Starting test for $CC_ALGORITHM. Output will be in ${LOG_FILE}"

# Write a header *into* the log file (overwrites old file)
echo "--- Test for Congestion Control Algorithm: $CC_ALGORITHM ---" > ${LOG_FILE}

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
  --port=4433 \
  --certificate_file=./cert.pem \
  --key_file=./key.pem \
  --generate_dynamic_responses=true &

SERVER_PID=$!
echo "Server started with PID ${SERVER_PID}"
sleep 1

# --- 5. Run Client ---
echo "Running client and logging..."
./quiche/bazel-bin/quiche/quic_client \
  --disable_certificate_verification \
  --v=1 \
  --stderrthreshold=0 \
  --drop_response_body=true \
  --connection_options=$CC_ALGORITHM \
  --body_file="$(< upload_data.tmp)" \
  --disable_port_changes=true \
  https://localhost:4433/ \
  >> ${LOG_FILE} 2>&1

# --- 6. Stop Server ---
echo "Test complete. Stopping server..."
kill $SERVER_PID

echo "Done. Logs are in ${LOG_FILE}"
echo "Run 'cat ${LOG_FILE}' to see the results."