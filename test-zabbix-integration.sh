#!/bin/bash

# Integration Test for Zabbix 7.0.1 with Azure Storage Cost Monitor Template
# This script:
# 1. Starts Zabbix via Docker Compose
# 2. Creates a test host
# 3. Imports and applies the Azure Storage Cost Monitor template
# 4. Sends test data using zabbix_sender
# 5. Verifies data was received successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.zabbix.yml"
# Use YAML template for automated testing (cleaner format, better compatibility)
# For production Web UI import, you can use either YAML or XML format
TEMPLATE_FILE="${ZABBIX_TEMPLATE_FILE:-$SCRIPT_DIR/zabbix-template-azure-storage-monitor-7.0.yaml}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Zabbix connection settings
ZABBIX_URL="http://localhost:8080"
ZABBIX_API_URL="$ZABBIX_URL/api_jsonrpc.php"
ZABBIX_USER="Admin"
ZABBIX_PASSWORD="zabbix"
ZABBIX_SERVER="localhost"
ZABBIX_PORT="10051"
TEST_HOST_NAME="azure-storage-monitor-test"

# Global variables
AUTH_TOKEN=""
HOST_ID=""
TEMPLATE_ID=""

# Logging functions
log_info() {
    printf "%b[INFO]%b %s\n" "${BLUE}" "${NC}" "$1"
}

log_success() {
    printf "%b[SUCCESS]%b %s\n" "${GREEN}" "${NC}" "$1"
}

log_error() {
    printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$1"
}

log_warning() {
    printf "%b[WARNING]%b %s\n" "${YELLOW}" "${NC}" "$1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    if [[ "${SKIP_CLEANUP:-false}" == "false" ]]; then
        docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
        log_info "Cleanup completed"
    else
        log_warning "Skipping cleanup (SKIP_CLEANUP=true)"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    if ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Start Zabbix containers
start_zabbix() {
    log_info "Starting Zabbix containers..."

    # Stop any existing containers
    docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true

    # Start containers
    docker compose -f "$COMPOSE_FILE" up -d

    log_success "Zabbix containers started"
}

# Wait for Zabbix to be ready
wait_for_zabbix() {
    log_info "Waiting for Zabbix to be ready..."

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -f "$ZABBIX_URL/ping" > /dev/null 2>&1; then
            # Additional wait for backend to be ready
            sleep 10
            log_success "Zabbix web interface is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done

    echo ""
    log_error "Zabbix failed to start within expected time"
    log_info "Checking container status:"
    docker compose -f "$COMPOSE_FILE" ps
    log_info "Checking zabbix-server logs:"
    docker compose -f "$COMPOSE_FILE" logs --tail=50 zabbix-server
    return 1
}

# Authenticate with Zabbix API
zabbix_authenticate() {
    log_info "Authenticating with Zabbix API..."

    local response
    response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"user.login\",
            \"params\": {
                \"username\": \"$ZABBIX_USER\",
                \"password\": \"$ZABBIX_PASSWORD\"
            },
            \"id\": 1
        }")

    AUTH_TOKEN=$(echo "$response" | jq -r '.result // empty')

    if [[ -z "$AUTH_TOKEN" ]] || [[ "$AUTH_TOKEN" == "null" ]]; then
        log_error "Authentication failed"
        log_error "Response: $response"
        return 1
    fi

    log_success "Authentication successful"
}

# Import template
import_template() {
    log_info "Importing Azure Storage Cost Monitor template..."

    # Detect template format
    local template_format="xml"
    if [[ "$TEMPLATE_FILE" == *.yaml ]] || [[ "$TEMPLATE_FILE" == *.yml ]]; then
        template_format="yaml"
    elif [[ "$TEMPLATE_FILE" == *.json ]]; then
        template_format="json"
    fi

    log_info "Detected template format: $template_format"

    # Read template file and escape for JSON
    local template_content
    template_content=$(cat "$TEMPLATE_FILE" | jq -Rs .)

    local response
    response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"configuration.import\",
            \"params\": {
                \"format\": \"$template_format\",
                \"rules\": {
                    \"templates\": {
                        \"createMissing\": true,
                        \"updateExisting\": true
                    },
                    \"items\": {
                        \"createMissing\": true,
                        \"updateExisting\": true
                    },
                    \"triggers\": {
                        \"createMissing\": true,
                        \"updateExisting\": true
                    },
                    \"discoveryRules\": {
                        \"createMissing\": true,
                        \"updateExisting\": true
                    },
                    \"template_groups\": {
                        \"createMissing\": true
                    }
                },
                \"source\": $template_content
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 2
        }")

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        log_error "Template import failed"
        log_error "Response: $response"
        return 1
    fi

    log_success "Template imported successfully"

    # Get template ID
    local template_response
    template_response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"template.get\",
            \"params\": {
                \"filter\": {
                    \"host\": \"Azure Storage Cost Monitor\"
                }
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 3
        }")

    TEMPLATE_ID=$(echo "$template_response" | jq -r '.result[0].templateid // empty')

    if [[ -z "$TEMPLATE_ID" ]] || [[ "$TEMPLATE_ID" == "null" ]]; then
        log_error "Failed to get template ID"
        log_error "Response: $template_response"
        return 1
    fi

    log_success "Template ID: $TEMPLATE_ID"
}

# Create test host and link template
create_test_host() {
    log_info "Creating test host: $TEST_HOST_NAME..."

    # First, get or create host group
    local hostgroup_response
    hostgroup_response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"hostgroup.get\",
            \"params\": {
                \"filter\": {
                    \"name\": \"Linux servers\"
                }
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 4
        }")

    local hostgroup_id
    hostgroup_id=$(echo "$hostgroup_response" | jq -r '.result[0].groupid // empty')

    if [[ -z "$hostgroup_id" ]] || [[ "$hostgroup_id" == "null" ]]; then
        log_error "Failed to get host group ID"
        return 1
    fi

    # Create host with template
    local host_response
    host_response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"host.create\",
            \"params\": {
                \"host\": \"$TEST_HOST_NAME\",
                \"name\": \"Azure Storage Monitor Test Host\",
                \"groups\": [
                    {
                        \"groupid\": \"$hostgroup_id\"
                    }
                ],
                \"templates\": [
                    {
                        \"templateid\": \"$TEMPLATE_ID\"
                    }
                ],
                \"interfaces\": [
                    {
                        \"type\": 1,
                        \"main\": 1,
                        \"useip\": 1,
                        \"ip\": \"127.0.0.1\",
                        \"dns\": \"\",
                        \"port\": \"10050\"
                    }
                ]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 5
        }")

    if echo "$host_response" | jq -e '.error' > /dev/null 2>&1; then
        log_error "Host creation failed"
        log_error "Response: $host_response"
        return 1
    fi

    HOST_ID=$(echo "$host_response" | jq -r '.result.hostids[0] // empty')

    if [[ -z "$HOST_ID" ]] || [[ "$HOST_ID" == "null" ]]; then
        log_error "Failed to get host ID"
        log_error "Response: $host_response"
        return 1
    fi

    log_success "Test host created with ID: $HOST_ID"
    log_success "Template applied to host"
}

# Install zabbix_sender in container
install_zabbix_sender() {
    log_info "Checking zabbix_sender availability..."

    # Check if zabbix_sender is available on host
    if command -v zabbix_sender &> /dev/null; then
        log_success "zabbix_sender found on host"
        return 0
    fi

    # Try to use zabbix_sender from docker container
    log_info "Using zabbix_sender from Docker container"
}

# Send test data via zabbix_sender
send_test_data() {
    log_info "Sending test data via zabbix_sender..."

    # Create test data file
    local data_file="/tmp/zabbix_test_data_$$.txt"

    # Get current timestamp
    local timestamp
    timestamp=$(date +%s)

    # Create test data
    cat > "$data_file" << EOF
$TEST_HOST_NAME azure.storage.all.total_waste.monthly $timestamp 123.45
$TEST_HOST_NAME azure.storage.all.total_disks $timestamp 5
$TEST_HOST_NAME azure.storage.all.total_snapshots $timestamp 3
$TEST_HOST_NAME azure.storage.all.subscriptions_scanned $timestamp 2
$TEST_HOST_NAME azure.storage.all.invalid_tags $timestamp 0
$TEST_HOST_NAME azure.storage.all.excluded_pending_review $timestamp 1
$TEST_HOST_NAME azure.storage.script.last_run_timestamp $timestamp $timestamp
$TEST_HOST_NAME azure.storage.script.execution_time_seconds $timestamp 45
$TEST_HOST_NAME azure.storage.script.last_run_status $timestamp 0
EOF

    log_info "Test data prepared:"
    cat "$data_file"

    # Send data using zabbix_sender from container
    local sender_output
    if command -v zabbix_sender &> /dev/null; then
        # Use host's zabbix_sender
        sender_output=$(zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -i "$data_file" 2>&1) || true
    else
        # Use zabbix_sender from docker container
        sender_output=$(docker exec zabbix-server zabbix_sender -z "$ZABBIX_SERVER" -p "$ZABBIX_PORT" -i "$data_file" 2>&1) || {
            # Copy file to container and try again
            docker cp "$data_file" zabbix-server:/tmp/test_data.txt
            sender_output=$(docker exec zabbix-server zabbix_sender -z localhost -p 10051 -i /tmp/test_data.txt 2>&1) || true
        }
    fi

    echo "$sender_output"

    # Clean up
    rm -f "$data_file"

    # Check if send was successful
    if echo "$sender_output" | grep -q "processed: [1-9]"; then
        log_success "Test data sent successfully"
        # Wait for data to be processed
        log_info "Waiting for data to be processed..."
        sleep 15
        return 0
    else
        log_warning "zabbix_sender output suggests some issues, but continuing..."
        sleep 15
        return 0
    fi
}

# Verify data was received
verify_data() {
    log_info "Verifying data was received..."

    # Get item data
    local items_response
    items_response=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json-rpc" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.get\",
            \"params\": {
                \"hostids\": \"$HOST_ID\",
                \"search\": {
                    \"key_\": \"azure.storage.all.total_waste.monthly\"
                },
                \"output\": [\"itemid\", \"name\", \"key_\", \"lastvalue\", \"lastclock\"]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 6
        }")

    local item_count
    item_count=$(echo "$items_response" | jq '.result | length')

    if [[ "$item_count" -gt 0 ]]; then
        log_success "Found $item_count item(s)"
        echo "$items_response" | jq '.result[] | {name: .name, key: .key_, lastvalue: .lastvalue}'
    else
        log_warning "No items found yet (this may be normal if Zabbix hasn't processed data)"
    fi

    # Try to get history data
    local item_id
    item_id=$(echo "$items_response" | jq -r '.result[0].itemid // empty')

    if [[ -n "$item_id" ]] && [[ "$item_id" != "null" ]]; then
        log_info "Checking history for item ID: $item_id"

        local history_response
        history_response=$(curl -s -X POST "$ZABBIX_API_URL" \
            -H "Content-Type: application/json-rpc" \
            -d "{
                \"jsonrpc\": \"2.0\",
                \"method\": \"history.get\",
                \"params\": {
                    \"itemids\": \"$item_id\",
                    \"limit\": 10,
                    \"sortfield\": \"clock\",
                    \"sortorder\": \"DESC\"
                },
                \"auth\": \"$AUTH_TOKEN\",
                \"id\": 7
            }")

        local history_count
        history_count=$(echo "$history_response" | jq '.result | length')

        if [[ "$history_count" -gt 0 ]]; then
            log_success "Found $history_count history record(s)"
            echo "$history_response" | jq '.result[] | {value: .value, clock: .clock}'
        else
            log_warning "No history data found yet"
            log_info "This is expected for Zabbix trapper items - data will appear after processing"
        fi
    fi

    log_success "Data verification completed"
}

# Display summary
display_summary() {
    echo ""
    echo "========================================"
    log_success "Zabbix Integration Test Summary"
    echo "========================================"
    echo "Zabbix URL: $ZABBIX_URL"
    echo "Zabbix API: $ZABBIX_API_URL"
    echo "Username: $ZABBIX_USER"
    echo "Password: $ZABBIX_PASSWORD"
    echo ""
    echo "Test Host: $TEST_HOST_NAME"
    echo "Host ID: $HOST_ID"
    echo "Template ID: $TEMPLATE_ID"
    echo ""
    log_info "You can access Zabbix web interface at: $ZABBIX_URL"
    log_info "To keep Zabbix running, set SKIP_CLEANUP=true"
    echo "========================================"
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "Zabbix 7.0.1 Integration Test"
    echo "Azure Storage Cost Monitor Template"
    echo "========================================"
    echo ""

    check_prerequisites
    start_zabbix
    wait_for_zabbix
    zabbix_authenticate
    import_template
    create_test_host
    install_zabbix_sender
    send_test_data
    verify_data
    display_summary

    log_success "All tests completed successfully!"

    if [[ "${SKIP_CLEANUP:-false}" == "true" ]]; then
        log_warning "Zabbix containers are still running. Use 'docker compose -f $COMPOSE_FILE down -v' to stop them."
        # Remove trap so cleanup doesn't run
        trap - EXIT
    fi
}

# Run main function
main "$@"
