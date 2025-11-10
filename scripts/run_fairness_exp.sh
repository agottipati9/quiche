#!/bin/bash
set -e

### --- 1. Set and Validate Arguments ---

# List of valid congestion control algorithms (from your script)
VALID_ALGORITHMS="QBIC RENO BBRR B2ON PRGC LLMX"

# --- Configuration ---
# The algorithm for the first 4 flows is hardcoded
STABLE_ALGO="QBIC"
STABLE_FLOW_COUNT=4

# Defaults for the latecomer test
DEFAULT_LATE_ALGORITHM="BBRR"
DEFAULT_OUTPUT_PATH="./latecomer_logs"
DEFAULT_BASE_PORT=4430
DEFAULT_DELAY_SEC=10 # Convergence delay in seconds

# Total flows will be 4 + 1
TOTAL_FLOWS=5
REQUEST_PATH="/104857600" # 100MB

# TODO: Set your Mahimahi trace files here
UPLINK_TRACE="traces/12mbps.mahi"
DOWNLINK_TRACE="traces/12mbps.mahi"

# Centralized binary paths
CLIENT_BIN="./quiche/bazel-bin/quiche/quic_client"
SERVER_BIN="./quiche/bazel-bin/quiche/quic_server"

# --- Parse Arguments ---
# The 1st argument is now the algorithm for the LATECOMER flow
CC_ALGORITHM=${1:-$DEFAULT_LATE_ALGORITHM}
OUTPUT_PATH=${2:-$DEFAULT_OUTPUT_PATH}
BASE_PORT=${3:-$DEFAULT_BASE_PORT}
CONVERGENCE_DELAY_SEC=${4:-$DEFAULT_DELAY_SEC}


# --- Validate Algorithm (from your script) ---
if ! echo "$VALID_ALGORITHMS" | grep -w -q "$CC_ALGORITHM"; then
    echo "Error: Invalid algorithm '$CC_ALGORITHM'."
    echo "Usage: $0 [Latecomer_Algorithm] [Output Path] [Base Port] [Delay_sec]"
    echo "Example: $0 BBRR ./logs 8440 10"
    echo ""
    echo "Valid Algorithms: [QBIC|RENO|BBRR (BBRv1)|B2ON (BBRv3)|PRGC (Prague Cubic)|LLMX (LLM Modified BBR)]"
    exit 1
fi

### --- 2. Setup Log Directory ---

# Create a unique log directory for this run
RUN_LOG_DIR="${OUTPUT_PATH}/${CC_ALGORITHM}_latecomer"
rm -rf "$RUN_LOG_DIR" # Clean previous runs
mkdir -p "$RUN_LOG_DIR"

echo "Starting latecomer test."
echo "  Stable Flows: 4 x $STABLE_ALGO"
echo "  Latecomer Flow: 1 x $CC_ALGORITHM (after $CONVERGENCE_DELAY_SEC seconds)"
echo "  Logs will be stored in $RUN_LOG_DIR"

### --- 3. Create Certificates (from your script) ---
if [ ! -f cert.pem ]; then
    echo "Creating test certificates..."
    openssl req -new -x509 -nodes -days 365 \
      -keyout key.pem -out cert.pem \
      -subj "/C=US/ST=Test/L/O=Test/CN=localhost"
fi

### --- 4. Start All 5 Servers ---
# We can start all servers at the beginning.
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

### --- 5. Run Clients in Mahimahi (with delay) ---
# This is the core logic. We build a single, complex
# command to run inside the 'sh -c'
CLIENT_COMMANDS=""

# --- Part 5a: Build commands for the first 4 CUBIC flows ---
echo "Building commands for 4 '$STABLE_ALGO' (CUBIC) flows..."
for i in $(seq 1 $STABLE_FLOW_COUNT); do
    PORT=$(($BASE_PORT + $i))
    LOG_ID="client_${i}_${STABLE_ALGO}"
    URL="https://10.0.0.1:${PORT}${REQUEST_PATH}"
    CLIENT_LOG="${RUN_LOG_DIR}/${LOG_ID}.txt"

    echo "--- Test for $STABLE_ALGO (ID: $LOG_ID) connecting to $URL ---" > $CLIENT_LOG

    CMD="$CLIENT_BIN \
      --disable_certificate_verification --v=1 --stderrthreshold=0 \
      --drop_response_body=true \
      --connection_options=$STABLE_ALGO \
      $URL \
      >> $CLIENT_LOG 2>&1"
    
    # Add to command string, run in background
    CLIENT_COMMANDS+="$CMD & "
done

# --- Part 5b: Add the convergence delay ---
CLIENT_COMMANDS+=" echo '--- [Mahi Shell] 4 CUBIC flows running. Waiting $CONVERGENCE_DELAY_SEC seconds for convergence... ---' ; "
CLIENT_COMMANDS+=" sleep $CONVERGENCE_DELAY_SEC ; "

# --- Part 5c: Build command for the 5th (configurable) flow ---
echo "Building command for 1 '$CC_ALGORITHM' (latecomer) flow..."
i=5
PORT=$(($BASE_PORT + $i))
LOG_ID="client_${i}_${CC_ALGORITHM}_LATE"
URL="https://10.0.0.1:${PORT}${REQUEST_PATH}"
CLIENT_LOG="${RUN_LOG_DIR}/${LOG_ID}.txt"

echo "--- Test for $CC_ALGORITHM (ID: $LOG_ID) connecting to $URL ---" > $CLIENT_LOG

CMD="$CLIENT_BIN \
  --disable_certificate_verification --v=1 --stderrthreshold=0 \
  --drop_response_body=true \
  --connection_options=$CC_ALGORITHM \
  $URL \
  >> $CLIENT_LOG 2>&1"

CLIENT_COMMANDS+="$CMD & "

# --- Part 5d: Add the final 'wait' ---
CLIENT_COMMANDS+=" echo '--- [Mahi Shell] Latecomer flow started. Waiting for all 5 flows to complete. ---' ; "
CLIENT_COMMANDS+=" wait "

# --- Part 5e: Execute ---
echo "Launching clients inside Mahimahi bottleneck..."
mm-link $UPLINK_TRACE $DOWNLINK_TRACE -- sh -c "$CLIENT_COMMANDS"

echo "All clients have finished."

### --- 6. Stop Servers ---
echo "Test complete. Stopping all $TOTAL_FLOWS servers..."
kill ${SERVER_PIDS[@]} # Kill all PIDs in the array

echo "Done. Logs are in $RUN_LOG_DIR"
echo "Example: 'cat ${RUN_LOG_DIR}/client_5_${CC_ALGORITHM}_LATE.txt'"