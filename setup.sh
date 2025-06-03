#!/bin/bash

# Complete Setup Script for Kafka + ELK Stack + Open Source UIs
echo "🚀 Setting up Complete Kafka Ecosystem with ELK Stack..."

# Tạo các thư mục cần thiết
echo "📁 Creating directories..."
mkdir -p {data/{kafka,zookeeper,elasticsearch,schema-registry,kafka-connect},logstash/{config,pipeline},filebeat,configs/sample-data}

# Set permissions
echo "🔒 Setting permissions..."
sudo chown -R 1001:1001 data/{kafka,zookeeper,schema-registry,kafka-connect}
sudo chown -R 1000:1000 data/elasticsearch

# Tạo Logstash configuration
echo "⚙️ Creating Logstash configuration..."
cat > logstash/config/logstash.yml << EOF
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: ["http://contextchain-elasticsearch:9200"]
xpack.monitoring.enabled: false
EOF

# Tạo Logstash pipeline
cat > logstash/pipeline/logstash.conf << 'EOF'
input {
  beats {
    port => 5044
  }
  
  kafka {
    bootstrap_servers => "contextchain-kafka:9092"
    topics => ["kafka-logs", "application-logs"]
    codec => json
    consumer_threads => 3
  }
}

filter {
  if [fields][log_type] == "container" {
    json {
      source => "message"
    }
    
    date {
      match => [ "timestamp", "ISO8601" ]
    }
    
    mutate {
      add_field => { "log_source" => "docker_container" }
    }
  }
  
  # Kafka logs
  if [container][name] == "contextchain-kafka" {
    grok {
      match => { 
        "message" => "\[%{TIMESTAMP_ISO8601:kafka_timestamp}\] %{LOGLEVEL:kafka_level} %{GREEDYDATA:kafka_message}" 
      }
    }
    
    mutate {
      add_field => { "service" => "kafka" }
      add_field => { "log_type" => "kafka_server" }
    }
  }
  
  # Zookeeper logs
  if [container][name] == "contextchain-zookeeper" {
    grok {
      match => { 
        "message" => "%{TIMESTAMP_ISO8601:zk_timestamp} \[myid:%{NUMBER:zk_myid}\] - %{LOGLEVEL:zk_level}  \[%{DATA:zk_thread}\] - %{GREEDYDATA:zk_message}"
      }
    }
    
    mutate {
      add_field => { "service" => "zookeeper" }
      add_field => { "log_type" => "zookeeper_server" }
    }
  }
  
  # AKHQ logs
  if [container][name] == "contextchain-akhq" {
    mutate {
      add_field => { "service" => "akhq" }
      add_field => { "log_type" => "kafka_ui" }
    }
  }
  
  # Schema Registry logs
  if [container][name] == "contextchain-schema-registry" {
    mutate {
      add_field => { "service" => "schema-registry" }
      add_field => { "log_type" => "schema_registry" }
    }
  }
  
  mutate {
    add_field => { "environment" => "contextchain" }
    add_field => { "processed_at" => "%{@timestamp}" }
  }
}

output {
  elasticsearch {
    hosts => ["http://contextchain-elasticsearch:9200"]
    index => "contextchain-logs-%{+YYYY.MM.dd}"
  }
  
  stdout { 
    codec => rubydebug 
  }
}
EOF

# Tạo Filebeat configuration
cat > filebeat/filebeat.yml << EOF
filebeat.inputs:
- type: container
  paths:
    - '/var/lib/docker/containers/*/*.log'
  
  processors:
  - add_docker_metadata:
      host: "unix:///var/run/docker.sock"
  
  - drop_event:
      when:
        not:
          or:
            - contains:
                docker.container.name: "contextchain-kafka"
            - contains:
                docker.container.name: "contextchain-zookeeper"
            - contains:
                docker.container.name: "contextchain-akhq"
            - contains:
                docker.container.name: "contextchain-kafdrop"
            - contains:
                docker.container.name: "contextchain-schema-registry"
            - contains:
                docker.container.name: "contextchain-kafka-connect"
  
  fields:
    log_type: container
    environment: contextchain
  fields_under_root: false

output.kafka:
  hosts: ["contextchain-kafka:9092"]
  topic: "kafka-logs"
  partition.round_robin:
    reachable_only: false
  
  required_acks: 1
  compression: lz4
  max_message_bytes: 1000000

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644

processors:
- add_host_metadata: ~
- add_docker_metadata: ~
- decode_json_fields:
    fields: ["message"]
    target: ""
    overwrite_keys: true
EOF

# Sample topics configuration
cat > configs/sample-data/sample-topics.json << EOF
{
  "topics": [
    {
      "name": "user-events",
      "partitions": 3,
      "replicationFactor": 1,
      "configs": {
        "retention.ms": "604800000",
        "compression.type": "lz4"
      }
    },
    {
      "name": "order-events", 
      "partitions": 6,
      "replicationFactor": 1,
      "configs": {
        "retention.ms": "2592000000",
        "compression.type": "lz4"
      }
    },
    {
      "name": "audit-logs",
      "partitions": 1,
      "replicationFactor": 1,
      "configs": {
        "retention.ms": "7776000000",
        "compression.type": "gzip"
      }
    }
  ]
}
EOF

# Sample Avro schema
cat > configs/sample-data/user-schema.avsc << EOF
{
  "type": "record",
  "name": "User",
  "namespace": "com.contextchain.avro",
  "fields": [
    {
      "name": "id",
      "type": "string"
    },
    {
      "name": "username",
      "type": "string"
    },
    {
      "name": "email",
      "type": "string"
    },
    {
      "name": "created_at",
      "type": "long",
      "logicalType": "timestamp-millis"
    },
    {
      "name": "status",
      "type": {
        "type": "enum",
        "name": "UserStatus",
        "symbols": ["ACTIVE", "INACTIVE", "SUSPENDED"]
      },
      "default": "ACTIVE"
    }
  ]
}
EOF

# Create topic creation script
cat > create-topics.sh << 'EOF'
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
EOF

chmod +x create-topics.sh

# Create health check script
cat > check-health.sh << 'EOF'
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
EOF

chmod +x check-health.sh

# Set vm.max_map_count for Elasticsearch
echo "🔧 Setting vm.max_map_count for Elasticsearch..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "🚀 Next steps:"
echo "   1. docker-compose up -d              # Start all services"
echo "   2. ./check-health.sh                 # Check service status"
echo "   3. ./create-topics.sh                # Create sample topics"
echo "   4. Open http://localhost:8081        # Access AKHQ"
echo ""
echo "🌐 Main Access URLs:"
echo "   🎯 AKHQ (Primary):   http://localhost:8081"
echo "   📈 Kafdrop:          http://localhost:9000"
echo "   🔍 Kibana:          http://localhost:5601"
echo ""
echo "📚 Sample files created in: configs/sample-data/"