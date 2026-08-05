#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# dataprocessor.sh — Data Processing Module for BS Framework
# Модуль обработки данных для фреймворка BS
#
# Description:
#   Comprehensive data processing module supporting:
#   - XPath queries for XML
#   - JPath queries for JSON
#   - JSON manipulation and validation
#   - XML parsing and transformation
#   - CSV processing and conversion
#   - Cross-format data conversion
#
# Features:
#   - Query languages support (XPath, JPath)
#   - Data validation and transformation
#   - Cross-format conversion
#   - Streaming processing for large files
#   - Error handling and reporting
#
# Dependencies:
#   - jq (for JSON processing)
#   - xmllint (for XML processing)
#   - xmlstarlet (for XPath support)
#   - csvkit (for CSV processing)
#   - python3 (for advanced XPath)
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck

# Source Guard / Защита от повторной загрузки
bs::guard "DATA_PROCESSOR" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh" "../system/platformcheck.sh"

# Data processor configuration
readonly DATA_PROCESSOR_CONFIG_DIR="${HOME}/.config/dataprocessor"
readonly DATA_PROCESSOR_CACHE_DIR="/tmp/data_processor_cache"
readonly DATA_PROCESSOR_MAX_FILE_SIZE="100M"

# Module state
DATA_PROCESSOR_FORMATS=("json" "xml" "csv" "yaml" "tsv")

# Module initialization
dataprocessor::init() {
    local func_name="dataprocessor::init"
    
    log::info "Initializing Data Processor module..."
    
    # Create necessary directories
    mkdir -p "${DATA_PROCESSOR_CONFIG_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create config directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${DATA_PROCESSOR_CACHE_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Check dependencies
    dataprocessor::check_dependencies
    
    log::success "Data Processor module initialized successfully"
}

# Check dependencies
dataprocessor::check_dependencies() {
    local func_name="dataprocessor::check_dependencies"
    local missing_deps=()
    
    log::debug "Checking Data Processor dependencies..."
    
    # Check for jq (JSON)
    if ! utils::has jq; then
        missing_deps+=("jq")
    fi
    
    # Check for xmllint (XML)
    if ! utils::has xmllint; then
        missing_deps+=("libxml2-utils")
    fi
    
    # Check for xmlstarlet (XPath)
    if ! utils::has xmlstarlet; then
        missing_deps+=("xmlstarlet")
    fi
    
    # Check for csvkit (CSV)
    if ! utils::has csvkit; then
        # csvkit is optional, we'll provide fallback
        log::debug "csvkit not found - CSV functionality will be limited"
    fi
    
    # Check for python3 (for advanced XPath)
    if ! utils::has python3; then
        missing_deps+=("python3")
    fi
    
    # Install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        dataprocessor::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install dependencies
dataprocessor::install_dependencies() {
    local func_name="dataprocessor::install_dependencies"
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y jq libxml2-utils xmlstarlet python3
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        dnf install -y jq libxml2 xmlstarlet python3
    elif platformcheck::is_macos; then
        if ! utils::has brew; then
            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install jq libxml2 xmlstarlet python3
    else
        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# ============================================================================
# JSON PROCESSING
# Обработка JSON
# ============================================================================

# Validate JSON
dataprocessor::json::validate() {
    local func_name="dataprocessor::json::validate"
    local json_data="${1:-}"
    
    if [[ -z "${json_data}" ]]; then
        errorhandler::throw "${func_name}" "JSON data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if echo "${json_data}" | utils::quiet_err jq empty; then
        return 0
    else
        return 1
    fi
}

# Pretty print JSON
dataprocessor::json::pretty() {
    local func_name="dataprocessor::json::pretty"
    local json_data="${1:-}"
    
    if [[ -z "${json_data}" ]]; then
        errorhandler::throw "${func_name}" "JSON data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json_data}" | utils::quiet_err jq '.' || {
        errorhandler::throw "${func_name}" "Invalid JSON data" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Minify JSON
dataprocessor::json::minify() {
    local func_name="dataprocessor::json::minify"
    local json_data="${1:-}"
    
    if [[ -z "${json_data}" ]]; then
        errorhandler::throw "${func_name}" "JSON data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json_data}" | utils::quiet_err jq -c '.' || {
        errorhandler::throw "${func_name}" "Invalid JSON data" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Query JSON with JPath (jq syntax)
dataprocessor::json::query() {
    local func_name="dataprocessor::json::query"
    local json_data="${1:-}"
    local query="${2:-}"
    
    if [[ -z "${json_data}" ]] || [[ -z "${query}" ]]; then
        errorhandler::throw "${func_name}" "JSON data and query are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json_data}" | utils::quiet_err jq -r "${query}" || {
        errorhandler::throw "${func_name}" "Invalid query or JSON data" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Update JSON value
dataprocessor::json::update() {
    local func_name="dataprocessor::json::update"
    local json_data="${1:-}"
    local path="${2:-}"
    local new_value="${3:-}"
    
    if [[ -z "${json_data}" ]] || [[ -z "${path}" ]]; then
        errorhandler::throw "${func_name}" "JSON data and path are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json_data}" | utils::quiet_err jq "${path} = ${new_value}" || {
        errorhandler::throw "${func_name}" "Invalid JSON data or path" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Delete JSON key
dataprocessor::json::delete() {
    local func_name="dataprocessor::json::delete"
    local json_data="${1:-}"
    local path="${2:-}"
    
    if [[ -z "${json_data}" ]] || [[ -z "${path}" ]]; then
        errorhandler::throw "${func_name}" "JSON data and path are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json_data}" | utils::quiet_err jq "del(${path})" || {
        errorhandler::throw "${func_name}" "Invalid JSON data or path" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Merge JSON objects
dataprocessor::json::merge() {
    local func_name="dataprocessor::json::merge"
    local json1="${1:-}"
    local json2="${2:-}"
    
    if [[ -z "${json1}" ]] || [[ -z "${json2}" ]]; then
        errorhandler::throw "${func_name}" "Two JSON objects are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${json1}" "${json2}" | utils::quiet_err jq -s '.[0] * .[1]' || {
        errorhandler::throw "${func_name}" "Invalid JSON data" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Convert JSON to CSV
dataprocessor::json::to_csv() {
    local func_name="dataprocessor::json::to_csv"
    local json_data="${1:-}"
    
    if [[ -z "${json_data}" ]]; then
        errorhandler::throw "${func_name}" "JSON data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use csvkit if available, otherwise use jq
    if utils::has in2csv; then
        echo "${json_data}" | in2csv --format json
    else
        # Fallback to jq
        echo "${json_data}" | utils::quiet_err jq -r '.[] | @csv' || {
            errorhandler::throw "${func_name}" "Failed to convert JSON to CSV" \
                "${LIB_ERROR_CONVERSION_FAILED}"
        }
    fi
}

# ============================================================================
# XML PROCESSING
# Обработка XML
# ============================================================================

# Validate XML
dataprocessor::xml::validate() {
    local func_name="dataprocessor::xml::validate"
    local xml_data="${1:-}"
    
    if [[ -z "${xml_data}" ]]; then
        errorhandler::throw "${func_name}" "XML data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${xml_data}" | utils::quiet_err xmllint --noout - && return 0 || return 1
}

# Pretty print XML
dataprocessor::xml::pretty() {
    local func_name="dataprocessor::xml::pretty"
    local xml_data="${1:-}"
    
    if [[ -z "${xml_data}" ]]; then
        errorhandler::throw "${func_name}" "XML data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    echo "${xml_data}" | utils::quiet_err xmllint --format - || {
        errorhandler::throw "${func_name}" "Invalid XML data" \
            "${LIB_ERROR_INVALID_DATA}"
    }
}

# Query XML with XPath
dataprocessor::xml::xpath() {
    local func_name="dataprocessor::xml::xpath"
    local xml_data="${1:-}"
    local xpath_query="${2:-}"
    
    if [[ -z "${xml_data}" ]] || [[ -z "${xpath_query}" ]]; then
        errorhandler::throw "${func_name}" "XML data and XPath query are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Try xmlstarlet first, then xmllint
    if utils::has xmlstarlet; then
        echo "${xml_data}" | utils::quiet_err xmlstarlet sel -t -v "${xpath_query}" - || {
            errorhandler::throw "${func_name}" "Invalid XPath query or XML data" \
                "${LIB_ERROR_INVALID_DATA}"
        }
    else
        echo "${xml_data}" | utils::quiet_err xmllint --xpath "${xpath_query}" - || {
            errorhandler::throw "${func_name}" "Invalid XPath query or XML data" \
                "${LIB_ERROR_INVALID_DATA}"
        }
    fi
}

# Convert XML to JSON
dataprocessor::xml::to_json() {
    local func_name="dataprocessor::xml::to_json"
    local xml_data="${1:-}"
    
    if [[ -z "${xml_data}" ]]; then
        errorhandler::throw "${func_name}" "XML data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use xmltodict via python3 if available
    if utils::quiet_err python3 -c "import xmltodict"; then
        echo "${xml_data}" | python3 -c "
import xmltodict, json, sys
xml_data = sys.stdin.read()
try:
    data = xmltodict.parse(xml_data)
    print(json.dumps(data, indent=2))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        errorhandler::throw "${func_name}" "xmltodict python module not found. Install with: pip3 install xmltodict" \
            "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# Convert XML to CSV
dataprocessor::xml::to_csv() {
    local func_name="dataprocessor::xml::to_csv"
    local xml_data="${1:-}"
    local xpath_query="${2:-//row}"
    
    if [[ -z "${xml_data}" ]]; then
        errorhandler::throw "${func_name}" "XML data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # First convert to JSON, then to CSV
    local json_data
    json_data=$(dataprocessor::xml::to_json "${xml_data}")
    
    dataprocessor::json::to_csv "${json_data}"
}

# Extract XML elements
dataprocessor::xml::extract() {
    local func_name="dataprocessor::xml::extract"
    local xml_data="${1:-}"
    local element_name="${2:-}"
    
    if [[ -z "${xml_data}" ]] || [[ -z "${element_name}" ]]; then
        errorhandler::throw "${func_name}" "XML data and element name are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    dataprocessor::xml::xpath "${xml_data}" "//${element_name}"
}

# ============================================================================
# CSV PROCESSING
# Обработка CSV
# ============================================================================

# Validate CSV
dataprocessor::csv::validate() {
    local func_name="dataprocessor::csv::validate"
    local csv_data="${1:-}"
    
    if [[ -z "${csv_data}" ]]; then
        errorhandler::throw "${func_name}" "CSV data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Basic validation - check for consistent column count
    local header_cols
    header_cols=$(echo "${csv_data}" | head -1 | awk -F',' '{print NF}')
    
    local line_num=2
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local line_cols
            line_cols=$(echo "${line}" | awk -F',' '{print NF}')
            
            if [[ "${line_cols}" != "${header_cols}" ]]; then
                return 1
            fi
        fi
        ((line_num++))
    done <<< "$(echo "${csv_data}" | tail -n +2)"
    
    return 0
}

# Convert CSV to JSON
dataprocessor::csv::to_json() {
    local func_name="dataprocessor::csv::to_json"
    local csv_data="${1:-}"
    
    if [[ -z "${csv_data}" ]]; then
        errorhandler::throw "${func_name}" "CSV data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use csvkit if available
    if utils::has csvjson; then
        echo "${csv_data}" | csvjson
    else
        # Fallback implementation
        local header
        header=$(echo "${csv_data}" | head -1)
        IFS=',' read -ra headers <<< "${header}"
        
        echo "["
        
        local first=true
        while IFS= read -r line; do
            if [[ -n "${line}" ]] && [[ "${line}" != "${header}" ]]; then
                if [[ "${first}" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                
                echo -n "  {"
                IFS=',' read -ra values <<< "${line}"
                
                local first_field=true
                for i in "${!headers[@]}"; do
                    if [[ "${first_field}" == "true" ]]; then
                        first_field=false
                    else
                        echo -n ", "
                    fi
                    
                    local value="${values[$i]}"
                    # Remove quotes if present
                    value="${value%\"}"
                    value="${value#\"}"
                    
                    echo -n "\"${headers[$i]}\": \"${value}\""
                done
                
                echo -n "}"
            fi
        done <<< "$(echo "${csv_data}" | tail -n +2)"
        
        echo ""
        echo "]"
    fi
}

# Filter CSV data
dataprocessor::csv::filter() {
    local func_name="dataprocessor::csv::filter"
    local csv_data="${1:-}"
    local column="${2:-}"
    local value="${3:-}"
    
    if [[ -z "${csv_data}" ]] || [[ -z "${column}" ]]; then
        errorhandler::throw "${func_name}" "CSV data and column are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use csvkit if available
    if utils::has csvgrep; then
        echo "${csv_data}" | csvgrep -c "${column}" -m "${value}"
    else
        # Fallback implementation
        local header
        header=$(echo "${csv_data}" | head -1)
        
        echo "${header}"
        
        # Find column index
        local col_index=1
        IFS=',' read -ra headers <<< "${header}"
        for i in "${!headers[@]}"; do
            if [[ "${headers[$i]}" == "${column}" ]]; then
                col_index=$((i + 1))
                break
            fi
        done
        
        # Filter rows
        while IFS= read -r line; do
            if [[ -n "${line}" ]] && [[ "${line}" != "${header}" ]]; then
                IFS=',' read -ra values <<< "${line}"
                if [[ "${values[$((col_index - 1))]}" == "${value}" ]]; then
                    echo "${line}"
                fi
            fi
        done <<< "$(echo "${csv_data}" | tail -n +2)"
    fi
}

# Sort CSV data
dataprocessor::csv::sort() {
    local func_name="dataprocessor::csv::sort"
    local csv_data="${1:-}"
    local column="${2:-}"
    local direction="${3:-asc}"
    
    if [[ -z "${csv_data}" ]] || [[ -z "${column}" ]]; then
        errorhandler::throw "${func_name}" "CSV data and column are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use csvkit if available
    if utils::has csvsort; then
        local sort_flag=""
        if [[ "${direction}" == "desc" ]]; then
            sort_flag="-r"
        fi
        echo "${csv_data}" | csvsort -c "${column}" ${sort_flag}
    else
        # Fallback implementation
        local header
        header=$(echo "${csv_data}" | head -1)
        
        echo "${header}"
        
        # Sort data (excluding header)
        if [[ "${direction}" == "desc" ]]; then
            echo "${csv_data}" | tail -n +2 | sort -t',' -k"${column}" -r
        else
            echo "${csv_data}" | tail -n +2 | sort -t',' -k"${column}"
        fi
    fi
}

# ============================================================================
# YAML PROCESSING (BASIC)
# Обработка YAML (базовая)
# ============================================================================

# Convert YAML to JSON
dataprocessor::yaml::to_json() {
    local func_name="dataprocessor::yaml::to_json"
    local yaml_data="${1:-}"
    
    if [[ -z "${yaml_data}" ]]; then
        errorhandler::throw "${func_name}" "YAML data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use yq if available, otherwise use python3 with pyyaml
    if utils::has yq; then
        echo "${yaml_data}" | yq -j
    elif utils::quiet_err python3 -c "import yaml"; then
        echo "${yaml_data}" | python3 -c "
import yaml, json, sys
yaml_data = sys.stdin.read()
try:
    data = yaml.safe_load(yaml_data)
    print(json.dumps(data, indent=2))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        errorhandler::throw "${func_name}" "YAML processing tools not found. Install yq or python3-pyyaml" \
            "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# Convert JSON to YAML
dataprocessor::json::to_yaml() {
    local func_name="dataprocessor::json::to_yaml"
    local json_data="${1:-}"
    
    if [[ -z "${json_data}" ]]; then
        errorhandler::throw "${func_name}" "JSON data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use yq if available, otherwise use python3 with pyyaml
    if utils::has yq; then
        echo "${json_data}" | yq -y
    elif utils::quiet_err python3 -c "import yaml"; then
        echo "${json_data}" | python3 -c "
import yaml, json, sys
json_data = sys.stdin.read()
try:
    data = json.loads(json_data)
    print(yaml.dump(data, default_flow_style=False))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        errorhandler::throw "${func_name}" "YAML processing tools not found. Install yq or python3-pyyaml" \
            "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# ============================================================================
# CROSS-FORMAT CONVERSION
# Кросс-форматное преобразование
# ============================================================================

# Auto-detect format and convert
dataprocessor::convert() {
    local func_name="dataprocessor::convert"
    local input_data="${1:-}"
    local output_format="${2:-}"
    
    if [[ -z "${input_data}" ]] || [[ -z "${output_format}" ]]; then
        errorhandler::throw "${func_name}" "Input data and output format are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Detect input format
    local input_format
    input_format=$(dataprocessor::detect_format "${input_data}")
    
    if [[ -z "${input_format}" ]]; then
        errorhandler::throw "${func_name}" "Unable to detect input format" \
            "${LIB_ERROR_FORMAT_UNKNOWN}"
    fi
    
    # Convert based on formats
    case "${input_format}-${output_format}" in
        json-xml)
            dataprocessor::json::to_xml "${input_data}"
            ;;
        json-csv)
            dataprocessor::json::to_csv "${input_data}"
            ;;
        json-yaml)
            dataprocessor::json::to_yaml "${input_data}"
            ;;
        xml-json)
            dataprocessor::xml::to_json "${input_data}"
            ;;
        xml-csv)
            dataprocessor::xml::to_csv "${input_data}"
            ;;
        csv-json)
            dataprocessor::csv::to_json "${input_data}"
            ;;
        csv-xml)
            # Convert CSV to JSON first, then to XML
            local json_data
            json_data=$(dataprocessor::csv::to_json "${input_data}")
            dataprocessor::json::to_xml "${json_data}"
            ;;
        yaml-json)
            dataprocessor::yaml::to_json "${input_data}"
            ;;
        *)
            errorhandler::throw "${func_name}" "Conversion from ${input_format} to ${output_format} not supported" \
                "${LIB_ERROR_CONVERSION_NOT_SUPPORTED}"
            ;;
    esac
}

# Detect data format
dataprocessor::detect_format() {
    local data="${1:-}"
    
    # JSON detection
    if echo "${data}" | utils::quiet_err jq empty; then
        echo "json"
        return 0
    fi
    
    # XML detection
    if echo "${data}" | utils::quiet_err xmllint --noout -; then
        echo "xml"
        return 0
    fi
    
    # CSV detection (simple)
    local first_line
    first_line=$(echo "${data}" | head -1)
    if [[ "${first_line}" == *","* ]] && [[ "${first_line}" != *"<"* ]] && [[ "${first_line}" != *"{"* ]]; then
        echo "csv"
        return 0
    fi
    
    # YAML detection (basic)
    if echo "${data}" | grep -q "^\s*[a-zA-Z_][a-zA-Z0-9_]*:"; then
        echo "yaml"
        return 0
    fi
    
    return 1
}

# ============================================================================
# JPATH PROCESSING (JSONPath)
# Обработка JPath (JSONPath)
# ============================================================================

# Query JSON with JSONPath
dataprocessor::jpath::query() {
    local func_name="dataprocessor::jpath::query"
    local json_data="${1:-}"
    local jpath_query="${2:-}"
    
    if [[ -z "${json_data}" ]] || [[ -z "${jpath_query}" ]]; then
        errorhandler::throw "${func_name}" "JSON data and JPath query are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Convert JSONPath to jq syntax and execute
    local jq_query
    jq_query=$(dataprocessor::jpath::to_jq "${jpath_query}")
    
    dataprocessor::json::query "${json_data}" "${jq_query}"
}

# Convert JSONPath to jq syntax
dataprocessor::jpath::to_jq() {
    local jpath="${1:-}"
    
    # Simple conversion - in production, this would be more comprehensive
    local jq_query="${jpath}"
    
    # Replace JSONPath syntax with jq syntax
    jq_query="${jq_query//\$/}"
    jq_query="${jq_query//\./}"  # Remove leading dot
    jq_query="${jq_query//\[\*\]/[]}"  # Convert [*] to []
    # Convert [' to " (helper vars: quotes break the substitution parser inline)
    local jpath_from="\['"
    local jpath_to='".'
    jq_query="${jq_query//${jpath_from}/${jpath_to}}"
    jq_query="${jq_query//\]/}"  # Convert '] to "
    
    echo "${jq_query}"
}

# ============================================================================
# XPATH PROCESSING (Advanced)
# Обработка XPath (расширенная)
# ============================================================================

# Query with advanced XPath features
dataprocessor::xpath::query() {
    local func_name="dataprocessor::xpath::query"
    local xml_data="${1:-}"
    local xpath_query="${2:-}"
    local options="${3:-}"
    
    if [[ -z "${xml_data}" ]] || [[ -z "${xpath_query}" ]]; then
        errorhandler::throw "${func_name}" "XML data and XPath query are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Use python3 with lxml for advanced XPath if available
    if utils::quiet_err python3 -c "import lxml.etree"; then
        echo "${xml_data}" | python3 -c "
import lxml.etree as ET
import sys
xml_data = sys.stdin.read()
xpath_query = '${xpath_query}'
try:
    root = ET.fromstring(xml_data)
    results = root.xpath(xpath_query)
    for result in results:
        if isinstance(result, str):
            print(result)
        else:
            print(ET.tostring(result, encoding='unicode'))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        # Fallback to basic XPath
        dataprocessor::xml::xpath "${xml_data}" "${xpath_query}"
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# Вспомогательные функции
# ============================================================================

# Get file info
dataprocessor::file::info() {
    local func_name="dataprocessor::file::info"
    local file_path="${1:-}"
    
    if [[ -z "${file_path}" ]]; then
        errorhandler::throw "${func_name}" "File path is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ ! -f "${file_path}" ]]; then
        errorhandler::throw "${func_name}" "File not found: ${file_path}" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    local file_size
    file_size=$(utils::quiet_err stat -c %s "${file_path}" || utils::quiet_err stat -f %z "${file_path}")
    
    local file_type
    file_type=$(utils::quiet_err file -b "${file_path}" || echo "unknown")
    
    local first_bytes
    first_bytes=$(head -c 100 "${file_path}" | utils::quiet_err od -c | head -1 || echo "")
    
    cat << EOF
{
  "path": "${file_path}",
  "size": ${file_size},
  "type": "${file_type}",
  "sample": "${first_bytes}"
}
EOF
}

# Process large files with streaming
dataprocessor::stream::process() {
    local func_name="dataprocessor::stream::process"
    local file_path="${1:-}"
    local processor="${2:-}"
    local chunk_size="${3:-1000}"
    
    if [[ -z "${file_path}" ]] || [[ -z "${processor}" ]]; then
        errorhandler::throw "${func_name}" "File path and processor function are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ ! -f "${file_path}" ]]; then
        errorhandler::throw "${func_name}" "File not found: ${file_path}" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    # Process file in chunks
    local temp_file
    temp_file=$(mktemp)
    
    split -l "${chunk_size}" "${file_path}" "${temp_file}.chunk."
    
    for chunk in "${temp_file}.chunk."*; do
        "${processor}" "${chunk}"
        rm -f "${chunk}"
    done
    
    rm -f "${temp_file}"
}

# Validate data structure
dataprocessor::validate() {
    local func_name="dataprocessor::validate"
    local data="${1:-}"
    local format="${2:-auto}"
    
    if [[ -z "${data}" ]]; then
        errorhandler::throw "${func_name}" "Data is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ "${format}" == "auto" ]]; then
        format=$(dataprocessor::detect_format "${data}")
    fi
    
    case "${format}" in
        json)
            dataprocessor::json::validate "${data}"
            ;;
        xml)
            dataprocessor::xml::validate "${data}"
            ;;
        csv)
            dataprocessor::csv::validate "${data}"
            ;;
        *)
            errorhandler::throw "${func_name}" "Unknown format: ${format}" \
                "${LIB_ERROR_FORMAT_UNKNOWN}"
            ;;
    esac
}

# ============================================================================
# MODULE INFO
# Информация о модуле
# ============================================================================

dataprocessor::info() {
    cat << EOF
Data Processor Module v1.0.0

Supported Formats:
  JSON          - JavaScript Object Notation
  XML           - Extensible Markup Language
  CSV           - Comma Separated Values
  YAML          - YAML Ain't Markup Language
  TSV           - Tab Separated Values

Query Languages:
  XPath         - XML Path Language
  JPath         - JSONPath (via jq)
  JSONPath      - JSON query language

Available Functions:
  JSON Processing:
    dataprocessor::json::validate        - Validate JSON syntax
    dataprocessor::json::pretty          - Pretty print JSON
    dataprocessor::json::minify          - Minify JSON
    dataprocessor::json::query           - Query with jq
    dataprocessor::json::update          - Update JSON values
    dataprocessor::json::delete          - Delete JSON keys
    dataprocessor::json::merge           - Merge JSON objects
    dataprocessor::json::to_csv          - Convert JSON to CSV
    dataprocessor::json::to_yaml         - Convert JSON to YAML

  XML Processing:
    dataprocessor::xml::validate         - Validate XML syntax
    dataprocessor::xml::pretty           - Pretty print XML
    dataprocessor::xml::xpath            - Query with XPath
    dataprocessor::xml::to_json          - Convert XML to JSON
    dataprocessor::xml::to_csv           - Convert XML to CSV
    dataprocessor::xml::extract          - Extract XML elements

  CSV Processing:
    dataprocessor::csv::validate         - Validate CSV structure
    dataprocessor::csv::to_json          - Convert CSV to JSON
    dataprocessor::csv::filter           - Filter CSV data
    dataprocessor::csv::sort             - Sort CSV data

  YAML Processing:
    dataprocessor::yaml::to_json         - Convert YAML to JSON
    dataprocessor::json::to_yaml         - Convert JSON to YAML

  Cross-Format:
    dataprocessor::convert               - Auto-detect and convert
    dataprocessor::detect_format         - Detect data format
    dataprocessor::validate              - Validate data structure

  Query Languages:
    dataprocessor::jpath::query          - Query JSON with JSONPath
    dataprocessor::xpath::query          - Advanced XPath queries

  Utilities:
    dataprocessor::file::info            - Get file information
    dataprocessor::stream::process       - Stream process large files

Configuration:
  Config directory: ${DATA_PROCESSOR_CONFIG_DIR}
  Cache directory: ${DATA_PROCESSOR_CACHE_DIR}
  Max file size: ${DATA_PROCESSOR_MAX_FILE_SIZE}

Dependencies:
  jq, xmllint, xmlstarlet, python3, csvkit (optional)

Usage:
  dataprocessor::json::query '{\"key\": \"value\"}' '.key'
  dataprocessor::xml::xpath '<root><item>value</item></root>' '//item'
  dataprocessor::convert '{\"data\": [1,2,3]}' csv
  dataprocessor::jpath::query '{\"store\": {\"book\": [{\"title\": \"Book1\"}]}}' '$.store.book[0].title'
EOF
}
