#!/bin/bash

echo "🎯 Creating sample Kafka topics..."

topics=(
  "user-events:3:1"
  "order-events:6:1"
  "audit-logs:1:1"
  "kafka-logs:3:1"
)

for topic_config in "${topics[@]}"; do
  IFS=':' read -r topic_name partitions replication <<< "$topic_config"
  
  echo "Creating topic: $topic_name"
  docker exec contextchain-kafka kafka-topics.sh \
    --create \
    --topic "$topic_name" \
    --partitions "$partitions" \
    --replication-factor "$replication" \
    --bootstrap-server localhost:9092 2>/dev/null || echo "Topic $topic_name already exists"
done

echo "✅ Topics created!"
echo ""
echo "📋 List all topics:"
docker exec contextchain-kafka kafka-topics.sh --list --bootstrap-server localhost:9092
