#!/bin/bash

# --- 1. Set and Validate Algorithm ---

VALID_ALGORITHMS="QBIC RENO BBRR B2ON PRGC"
DEFAULT_ALGORITHM="QBIC"
CC_ALGORITHM=${1:-$DEFAULT_ALGORITHM}

# Set the file size to 100 MiB (1024 * 1024 * 100)
# This large size ensures we measure steady-state throughput.
FILE_SIZE_BYTES=104857600

if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [ALGORITHM]"
    echo "Example: $0 BBRR"
    exit 1
fi

# --- 2. Setup Log Files ---

# This file will store the raw output for this specific run
RAW_LOG_FILE="tput_log_${CC_ALGORITHM}.txt"
# This file will store the summary statistics for *all* runs
STATS_FILE="tput_summary_${CC_ALGORITHM}.txt"

echo "Starting 100 MiB throughput test for $CC_ALGORITHM."
echo "Raw output will be in ${RAW_LOG_FILE}"

# Write a header into the raw log file (overwrites old file)
echo "--- Throughput Test for $CC_ALGORITHM ---" > ${RAW_LOG_FILE}
echo "File Size: ${FILE_SIZE_BYTES} bytes" >> ${RAW_LOG_FILE}

# --- 3. Create Certificates (if they don't exist) ---
if [ ! -f cert.pem ]; then
    echo "Creating test certificates..."
    openssl req -new -x509 -nodes -days 365 \
      -keyout key.pem -out cert.pem \
      -subj "/C=US/ST/L/O/CN=localhost"
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
# We are running 1 request for a very large file.
echo "Running client and logging... (This may take several seconds)"
./quiche/bazel-bin/quiche/quic_client \
  --disable_certificate_verification \
  --v=1 \
  --stderrthreshold=0 \
  --drop_response_body=true \
  --connection_options=$CC_ALGORITHM \
  --num_requests=1 \
  --disable_port_changes=true \
  https://localhost:4433/${FILE_SIZE_BYTES} \
  >> ${RAW_LOG_FILE} 2>&1

# --- 6. Stop Server ---
echo "Test complete. Stopping server..."
kill $SERVER_PID

# --- 7. Parse Results ---
echo "Calculating and saving statistics to ${STATS_FILE}..."
# We will create this new parser script next
./parse_tput_log.py ${RAW_LOG_FILE} ${CC_ALGORITHM} ${STATS_FILE}

echo "Done. Summary written to ${STATS_FILE}."