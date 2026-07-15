#!/bin/bash

# Provided by Tony Chou

CONFIG_FILE="$HOME/.elasticdump_export.conf"

# Load previous configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

read -p "Elasticsearch IP [${ES_IP:-10.106.123.10}]: " TMP
ES_IP=${TMP:-${ES_IP:-10.106.123.10}}

read -p "Index prefix, without -* [${INDEX_PREFIX:-aella-ser}]: " TMP
INDEX_PREFIX=${TMP:-${INDEX_PREFIX:-aella-ser}}

read -p "Output directory [${OUTDIR:-/tmp}]: " TMP
OUTDIR=${TMP:-${OUTDIR:-/tmp}}

read -p "Start epoch ms [${START:-1735689599000}]: " TMP
START=${TMP:-${START:-1735689599000}}

read -p "End epoch ms [${END:-1773878399000}]: " TMP
END=${TMP:-${END:-1773878399000}}

read -p "Number of query conditions [${NUM:-0}]: " TMP
NUM=${TMP:-${NUM:-0}}

ES="http://${ES_IP}:9200"
INDEX="${INDEX_PREFIX}-*"

QUERY=""
QUERY_CONFIG=""

for ((i=1; i<=NUM; i++))
do
    eval LAST_FIELD=\${FIELD_$i}
    eval LAST_VALUE=\${VALUE_$i}

    read -p "Field $i [${LAST_FIELD}]: " TMP
    FIELD=${TMP:-$LAST_FIELD}

    read -p "Value $i [${LAST_VALUE}]: " TMP
    VALUE=${TMP:-$LAST_VALUE}

    QUERY="${QUERY},{\"match_phrase\":{\"${FIELD}\":\"${VALUE}\"}}"

    QUERY_CONFIG="${QUERY_CONFIG}
FIELD_${i}=\"${FIELD}\"
VALUE_${i}=\"${VALUE}\""
done

# Save latest configuration
cat > "$CONFIG_FILE" <<EOF
ES_IP="${ES_IP}"
INDEX_PREFIX="${INDEX_PREFIX}"
OUTDIR="${OUTDIR}"
START="${START}"
END="${END}"
NUM="${NUM}"
${QUERY_CONFIG}
EOF

mkdir -p "$OUTDIR"

DAY_MS=86400000
CURRENT=$START

echo ""
echo "Using Elasticsearch: ${ES}"
echo "Using index: ${INDEX}"
echo "Output directory: ${OUTDIR}"
echo "Configuration saved to: ${CONFIG_FILE}"
echo ""

while [ "$CURRENT" -lt "$END" ]
do
    NEXT=$((CURRENT + DAY_MS))

    if [ "$NEXT" -gt "$END" ]; then
        NEXT=$END
    fi

    DATE_NAME=$(date -u -d "@$((CURRENT / 1000))" +%Y-%m-%d)
    OUT_FILE="${OUTDIR}/${INDEX_PREFIX}_${DATE_NAME}.log"

    SEARCHBODY="{\"query\":{\"bool\":{\"must\":[{\"range\":{\"timestamp\":{\"lt\":${NEXT},\"gte\":${CURRENT}}}}${QUERY}]}}}"

    echo "=================================================="
    echo "Exporting date: ${DATE_NAME}"
    echo "Output file: ${OUT_FILE}"
    echo "=================================================="

    elasticdump \
        --input=${ES}/${INDEX} \
        --output=${OUT_FILE} \
        --searchBody="${SEARCHBODY}"

    echo "Compressing completed file in background: ${OUT_FILE}"
    gzip -f "${OUT_FILE}" &

    CURRENT=$NEXT
done

wait

echo ""
echo "All exports completed."
