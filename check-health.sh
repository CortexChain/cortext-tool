#!/bin/bash

echo "🔍 Checking service health..."

services=(
  "Zookeeper:2181"
  "Kafka:9092" 
  "AKHQ:8081"
  "Kafdrop:9000"
  "Schema-Registry:8082"
  "Kafka-Connect:8083"
  "Elasticsearch:9200"
  "Kibana:5601"
)

for service in "${services[@]}"; do
  IFS=':' read -r name port <<< "$service"
  echo -n "Checking $name:$port... "
  
  if nc -z localhost $port 2>/dev/null; then
    echo "✅ UP"
  else
    echo "❌ DOWN"
  fi
done

echo ""
echo "🌐 Service URLs:"
echo "   🎯 AKHQ:             http://localhost:8081"
echo "   📈 Kafdrop:          http://localhost:9000"
echo "   📋 Schema Registry:  http://localhost:8082"
echo "   🔌 Kafka Connect:    http://localhost:8083"
echo "   🔍 Kibana:          http://localhost:5601"
echo "   ⚡ Elasticsearch:   http://localhost:9200"
echo "   📈 Kafka Metrics:   http://localhost:9308"
