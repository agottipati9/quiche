#!/bin/bash
set -e

### --- 1. Set and Validate Arguments (MODIFIED) ---

# List of valid congestion control algorithms (from your script)
VALID_ALGORITHMS="BBRR LLMX"

# --- Configuration ---
# Defaults for the RTT fairness test
DEFAULT_ALGORITHM="LLMX"
DEFAULT_OUTPUT_PATH="./latency_case_logs"
DEFAULT_BASE_PORT=4430
DEFAULT_BASE_DELAY_MS=30  # 30ms one-way = 60ms base RTT

# We are only testing 1 flow
TOTAL_FLOWS=1
#REQUEST_PATH="/1048576000"
REQUEST_PATH="/104857600"

# TODO: Set your Mahimahi trace files here
UPLINK_TRACE="./traces/12mbps"
DOWNLINK_TRACE="./traces/12mbps"

# Centralized binary paths
CLIENT_BIN="./quiche/bazel-bin/quiche/quic_client"
SERVER_BIN="./quiche/bazel-bin/quiche/quic_server"

# --- Parse Arguments ---
CC_ALGORITHM=${1:-$DEFAULT_ALGORITHM}
OUTPUT_PATH=${2:-$DEFAULT_OUTPUT_PATH}
BASE_PORT=${3:-$DEFAULT_BASE_PORT}
BASE_DELAY_MS=${4:-$DEFAULT_BASE_DELAY_MS}


# --- Validate Algorithm ---
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [Algorithm] [Output Path] [Base Port] [Base_Delay_ms]"
    echo "Example: $0 LLMX ./logs 8440 10"
    echo ""
    echo "This runs a 1-flow test:"
    echo "  Flow 1 RTT: (Base_Delay_ms * 2)"
    echo ""
    echo "Valid Algorithms: [BBRR (BBRv1)|LLMX (LLM Modified BBR)]"
    exit 1
fi

### --- 2. Setup Log Directory (MODIFIED) ---

# Create a unique log directory for this run
RUN_LOG_DIR="${OUTPUT_PATH}/${CC_ALGORITHM}_RTT_${BASE_DELAY_MS}"
rm -rf "$RUN_LOG_DIR" # Clean previous runs
mkdir -p "$RUN_LOG_DIR"

RTT_MS=$(($BASE_DELAY_MS * 2))

echo "Starting RTT fairness test for '$CC_ALGORITHM'."
echo "  Logs will be stored in $RUN_LOG_DIR"


### --- 3. Create Certificates (UNMODIFIED) ---
if [ ! -f cert.pem ]; then
    echo "Creating test certificates..."
    openssl req -new -x509 -nodes -days 365 \
      -keyout key.pem -out cert.pem \
      -subj "/C=US/ST=Test/L/O=Test/CN=localhost"
fi

### --- 4. Start All Servers (UNMODIFIED) ---
# This will now start $TOTAL_FLOWS=1 servers
SERVER_PIDS=()
echo "Starting $TOTAL_FLOWS servers in the background..."

for i in $(seq 1 $TOTAL_FLOWS); do
    PORT=$(($BASE_PORT + $i))
    LOG_ID="server_${i}"
    
    SERVER_LOG="${RUN_LOG_DIR}/server_${i}.txt"
    echo "--- Server $i on port $PORT ---" > $SERVER_LOG

   $SERVER_BIN \
      --port=$PORT \
      --certificate_file=./cert.pem \
      --key_file=./key.pem \
      --generate_dynamic_responses=true \
      --v=1 \
      --stderrthreshold=0 \
      >> $SERVER_LOG 2>&1 &
    
    SERVER_PIDS+=($!)
done

echo "All servers started. PIDs: ${SERVER_PIDS[@]}"
sleep 2 # Give servers time to start

### --- 5. Run Clients in Mahimahi (HEAVILY MODIFIED) ---
# This is the core logic. We build a command for each flow.
# The high-RTT flow will be wrapped in an *inner* mm-delay.
CLIENT_COMMANDS=""

# --- Part 5a: Build command for Flow ---
echo "Building command for 1 '$CC_ALGORITHM' flow..."
i=1
PORT=$(($BASE_PORT + $i))
LOG_ID="client_${i}_${CC_ALGORITHM}_RTT_${RTT_MS}ms"
URL="https://10.0.0.1:${PORT}${REQUEST_PATH}"
CLIENT_LOG="${RUN_LOG_DIR}/${LOG_ID}.txt"

echo "--- Test for $CC_ALGORITHM (ID: $LOG_ID) connecting to $URL ---" > $CLIENT_LOG

CMD_RTT="$CLIENT_BIN \
    --disable_certificate_verification --v=1 --stderrthreshold=0 \
    --drop_response_body=true \
    --connection_options=$CC_ALGORITHM \
    $URL \
    >> $CLIENT_LOG 2>&1"

# Add to command string, run in background
# This flow *only* gets the base delay from the outer mm-delay
CLIENT_COMMANDS+="$CMD_RTT & "

# --- Part 5c: Add the final 'wait' ---
CLIENT_COMMANDS+=" wait "

# --- Part 5d: Execute ---
echo "Launching clients inside Mahimahi bottleneck..."
#
# The outer mm-delay sets the *BASE* one-way RTT for *ALL* flows.
# Flow's one-way delay = $BASE_DELAY_MS
mm-delay $BASE_DELAY_MS \
    mm-link $UPLINK_TRACE $DOWNLINK_TRACE \
        --downlink-queue=droptail \
        --downlink-queue-args="packets=100" \
        -- sh -c "$CLIENT_COMMANDS"

echo "All clients have finished."

### --- 6. Stop Servers (UNMODIFIED) ---
echo "Test complete. Stopping all $TOTAL_FLOWS servers..."
kill ${SERVER_PIDS[@]} # Kill all PIDs in the array

echo "Done. Logs are in $RUN_LOG_DIR"
echo "Example: 'grep 'Final' ${RUN_LOG_DIR}/*.txt'"