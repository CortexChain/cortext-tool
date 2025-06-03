# ContextChain Kafka + ELK Stack

Hệ thống streaming và logging hoàn chỉnh với Apache Kafka và ELK Stack (Elasticsearch, Logstash, Kibana) được containerize với Docker Compose.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        ContextChain System                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Kafka UI  │    │   Kafdrop   │    │    AKHQ     │         │
│  │   :8080     │    │    :9000    │    │    :8081    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│          │                  │                  │               │
│          └──────────────────┼──────────────────┘               │
│                             │                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Apache Kafka                          │   │
│  │                   :9092, :29092                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │   │
│  │  │user-events  │  │order-events │  │ audit-logs  │    │   │
│  │  │  (3 parts)  │  │  (6 parts)  │  │  (1 part)   │    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Zookeeper                            │   │
│  │                     :2181                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                         ELK Stack                              │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Filebeat   │───▶│  Logstash   │───▶│Elasticsearch│         │
│  │             │    │    :5044    │    │    :9200    │         │
│  │             │    │    :5001    │    │    :9300    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│          │                                      │               │
│          │          ┌─────────────┐             │               │
│          └─────────▶│   Kibana    │◀────────────┘               │
│                     │    :5601    │                             │
│                     └─────────────┘                             │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                       Monitoring                               │
│                                                                 │
│  ┌─────────────┐                                               │
│  │Kafka Export │  ──── Prometheus Metrics                     │
│  │    :9308    │                                               │
│  └─────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow

### 1. Log Collection Flow
```
Docker Containers → Filebeat → Kafka Topic (kafka-logs) → Logstash → Elasticsearch → Kibana
```

### 2. Application Data Flow
```
Applications → Kafka Topics → Consumers → Processing → Elasticsearch (via Logstash)
```

### 3. Monitoring Flow
```
Kafka JMX Metrics → Kafka Exporter → Prometheus Metrics (Port 9308)
```

## 📋 Services Overview

| Service | Port | Description | Health Check |
|---------|------|-------------|--------------|
| **Zookeeper** | 2181 | Kafka coordination service | `nc -vz localhost 2181` |
| **Kafka** | 9092, 29092 | Message streaming platform | `kafka-topics.sh --list` |
| **Kafka UI** | 8080 | Web UI for Kafka management | http://localhost:8080 |
| **Elasticsearch** | 9200, 9300 | Search and analytics engine | `curl localhost:9200/_cluster/health` |
| **Logstash** | 5044, 5001, 9600 | Data processing pipeline | - |
| **Kibana** | 5601 | Data visualization dashboard | http://localhost:5601 |
| **Filebeat** | - | Log shipping agent | - |
| **Kafka Exporter** | 9308 | Prometheus metrics exporter | http://localhost:9308 |

## 🚀 Quick Start

### Prerequisites
- Docker và Docker Compose
- Minimum 8GB RAM
- 10GB free disk space

### 1. Setup Environment
```bash
# Clone hoặc tạo thư mục project
mkdir contextchain-kafka-elk
cd contextchain-kafka-elk

# Copy docker-compose.yml và setup script vào thư mục
# Chạy setup script
chmod +x setup.sh
./setup.sh
```

### 2. Start Services
```bash
# Start all services
docker-compose up -d

# Check service status
./check-health.sh
```

### 3. Create Sample Topics
```bash
# Create sample Kafka topics
./create-topics.sh
```

### 4. Access Web UIs
- **Kafka UI**: http://localhost:8080
- **Kibana**: http://localhost:5601
- **Elasticsearch**: http://localhost:9200

## 📊 Sample Topics

| Topic | Partitions | Retention | Compression | Use Case |
|-------|------------|-----------|-------------|----------|
| **user-events** | 3 | 7 days | lz4 | User activity tracking |
| **order-events** | 6 | 30 days | lz4 | E-commerce transactions |
| **audit-logs** | 1 | 90 days | gzip | Security and compliance |
| **kafka-logs** | 3 | 7 days | lz4 | System logs from containers |

## 🔧 Configuration Details

### Kafka Optimization
- **Segment Size**: 1GB for better I/O performance
- **Compression**: LZ4 for balance between speed and size
- **JVM Tuning**: G1GC with optimized heap settings
- **Resource Limits**: 6GB RAM, 2 CPU cores

### Elasticsearch Configuration
- **Single Node**: Development setup
- **Memory**: 1GB heap size
- **Security**: Disabled for development
- **Health Checks**: Cluster health monitoring

### Logstash Pipeline
- **Input**: Beats (port 5044) + Kafka consumer
- **Filters**: Container logs parsing, Kafka/Zookeeper log patterns
- **Output**: Elasticsearch indexing + stdout debug

## 📈 Monitoring & Observability

### Health Checks
```bash
# Check all services
./check-health.sh

# Individual service checks
docker-compose ps
docker-compose logs [service-name]
```

### Kafka Metrics
- **JMX Port**: 9999
- **Prometheus Metrics**: http://localhost:9308
- **Key Metrics**: Throughput, latency, consumer lag

### Log Analysis
- **Kibana Dashboards**: http://localhost:5601
- **Index Pattern**: `contextchain-logs-*`
- **Log Sources**: Kafka, Zookeeper, application containers

## 💡 Usage Examples

### Produce Messages
```bash
# Send test message to user-events topic
docker exec -it contextchain-kafka kafka-console-producer.sh \
  --topic user-events \
  --bootstrap-server localhost:9092

# Type your JSON message:
{"user_id": "123", "action": "login", "timestamp": "2025-06-03T10:00:00Z"}
```

### Consume Messages
```bash
# Consume from beginning
docker exec -it contextchain-kafka kafka-console-consumer.sh \
  --topic user-events \
  --from-beginning \
  --bootstrap-server localhost:9092
```

### Elasticsearch Queries
```bash
# Check index health
curl "localhost:9200/_cat/indices?v"

# Search recent logs
curl -X GET "localhost:9200/contextchain-logs-*/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match_all": {}}, "size": 10}'
```

## 🛠️ Troubleshooting

### Common Issues

1. **Elasticsearch won't start**
   ```bash
   # Increase vm.max_map_count
   sudo sysctl -w vm.max_map_count=262144
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   ```

2. **Kafka connection refused**
   ```bash
   # Check if Zookeeper is healthy first
   docker-compose logs zookeeper
   docker-compose restart kafka
   ```

3. **Out of memory errors**
   ```bash
   # Check Docker resource limits
   docker stats
   # Reduce heap sizes in docker-compose.yml if needed
   ```

### Log Analysis
```bash
# View service logs
docker-compose logs -f kafka
docker-compose logs -f elasticsearch
docker-compose logs -f logstash

# Check disk usage
docker system df
docker volume ls
```

## 🔒 Security Notes

⚠️ **Development Setup**: Security features are disabled for development. For production:
- Enable Kafka SASL/SSL authentication
- Enable Elasticsearch security features
- Use proper network segmentation
- Implement proper access controls

## 📚 Advanced Configuration

### Adding New Topics
```bash
# Create topic with custom config
docker exec contextchain-kafka kafka-topics.sh \
  --create \
  --topic new-topic \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --bootstrap-server localhost:9092
```

### Schema Registry Integration
- Uncomment Schema Registry service in docker-compose.yml
- Port: 8082
- Avro schema management

### Kafka Connect
- Uncomment Kafka Connect service
- Port: 8083
- Connector management API

## 🧹 Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes (data will be lost)
docker-compose down -v

# Remove all containers and images
docker-compose down --rmi all -v --remove-orphans
```
