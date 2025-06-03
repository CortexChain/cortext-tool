#!/bin/bash

# ContextChain Infrastructure Setup Script
# This script creates all necessary configuration files and directories

set -e

echo "🚀 Setting up ContextChain infrastructure with Redis 'cortext_redis' database..."

# Create directories
echo "📁 Creating directories..."
mkdir -p nginx
mkdir -p redis
mkdir -p kafka
mkdir -p logstash/config
mkdir -p logstash/pipeline
mkdir -p filebeat

# Create Redis Master configuration
echo "🔴 Creating Redis Master configuration..."
cat > redis/redis-master.conf << 'EOF'
# Redis Master Configuration for ContextChain
# Database: cortext_redis

# Network
bind 0.0.0.0
port 6379
protected-mode no

# General
daemonize no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

# Database Configuration
databases 16
save 900 1
save 300 10
save 60 10000

# Persistence
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename cortext_redis_master.rdb
dir /data

# AOF Configuration
appendonly yes
appendfilename "cortext_redis_master.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Replication
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-ping-replica-period 10
repl-timeout 60
repl-disable-tcp-nodelay no
repl-backlog-size 1mb
repl-backlog-ttl 3600

# Memory Management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Performance
timeout 0
tcp-keepalive 300
tcp-backlog 511

# Slow Log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Client Output Buffer
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
EOF

# Create Redis Slave configuration
echo "🔵 Creating Redis Slave configuration..."
cat > redis/redis-slave.conf << 'EOF'
# Redis Slave Configuration for ContextChain
# Database: cortext_redis (Read-Only)

# Network
bind 0.0.0.0
port 6379
protected-mode no

# General
daemonize no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

# Database Configuration
databases 16

# Replication Configuration
replicaof contextchain-redis-master 6379
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-ping-replica-period 10
repl-timeout 60
repl-disable-tcp-nodelay no
repl-backlog-size 1mb
repl-backlog-ttl 3600

# Persistence
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename cortext_redis_slave.rdb
dir /data

# AOF Configuration
appendonly yes
appendfilename "cortext_redis_slave.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Memory Management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Performance
timeout 0
tcp-keepalive 300
tcp-backlog 511

# Slow Log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Client Output Buffer
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
EOF

# Create Nginx configuration
echo "🌐 Creating Nginx configuration..."
cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging Format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    log_format upstream_time '$remote_addr - $remote_user [$time_local] '
                             '"$request" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent"'
                             'rt=$request_time uct="$upstream_connect_time" '
                             'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;

    # Connection Limiting
    limit_conn_zone $binary_remote_addr zone=perip:10m;

    # Main HTTP Server
    server {
        listen 80 default_server;
        server_name _;
        
        # Security Headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        # Rate Limiting
        limit_req zone=general burst=20 nodelay;
        limit_conn perip 10;

        # Health Check
        location /health {
            access_log off;
            return 200 "ContextChain Infrastructure - Healthy\n";
            add_header Content-Type text/plain;
        }

        # Default redirect to AKHQ
        location / {
            return 301 /akhq;
        }
    }
    
    # AKHQ Kafka UI
    server {
        listen 8080;
        server_name _;
        
        location / {
            proxy_pass http://contextchain-akhq:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
            proxy_buffering off;
        }
    }
    
    # Kibana Dashboard
    server {
        listen 5601;
        server_name _;
        
        location / {
            proxy_pass http://contextchain-kibana:5601;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
    
    # Elasticsearch API
    server {
        listen 9200;
        server_name _;
        
        # API Rate Limiting
        limit_req zone=api burst=20 nodelay;
        
        location / {
            proxy_pass http://contextchain-elasticsearch:9200;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
            
            if ($request_method = 'OPTIONS') {
                return 204;
            }
        }
    }
}

# Stream configuration for Redis TCP proxying
stream {
    log_format basic '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time "$upstream_addr"';

    access_log /var/log/nginx/redis_access.log basic;
    error_log /var/log/nginx/redis_error.log;

    # Redis Write Operations (Master only) - cortext_redis database
    upstream redis_write_stream {
        server contextchain-redis-master:6379 weight=1 max_fails=3 fail_timeout=30s;
    }

    # Redis Read Operations (Slave only) - cortext_redis database
    upstream redis_read_stream {
        server contextchain-redis-slave:6379 weight=1 max_fails=3 fail_timeout=30s;
    }

    # Redis Write Port (6379) - Master only for Write operations
    server {
        listen 6379;
        proxy_pass redis_write_stream;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_bind off;
    }

    # Redis Read Port (6380) - Slave only for Read operations
    server {
        listen 6380;
        proxy_pass redis_read_stream;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_bind off;
    }
}
EOF

# Create Kafka client properties
echo "📨 Creating Kafka client properties..."
cat > kafka/client.properties << 'EOF'
# Kafka Client Configuration for ContextChain
bootstrap.servers=contextchain-kafka:9093
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="123456A@a";

# Producer Settings
acks=all
retries=2147483647
max.in.flight.requests.per.connection=5
enable.idempotence=true
compression.type=lz4

# Consumer Settings
auto.offset.reset=earliest
enable.auto.commit=true
auto.commit.interval.ms=5000
session.timeout.ms=30000
EOF

# Create Logstash configuration
echo "📊 Creating Logstash configuration..."
cat > logstash/config/logstash.yml << 'EOF'
# Logstash Configuration for ContextChain
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: [ "http://contextchain-elasticsearch:9200" ]
path.config: /usr/share/logstash/pipeline
log.level: info
EOF

# Create Logstash pipeline
cat > logstash/pipeline/logstash.conf << 'EOF'
# Logstash Pipeline for ContextChain - Simplified and Stable
input {
  beats {
    port => 5044
  }
  
  tcp {
    port => 5001
    codec => json_lines
  }
  
  udp {
    port => 5001
    codec => json_lines
  }
}

filter {
  # Add basic metadata
  mutate {
    add_field => { "environment" => "contextchain" }
    add_field => { "project" => "cortext_redis" }
    add_field => { "ingested_at" => "%{@timestamp}" }
  }
  
  # Parse Docker container logs
  if [container] and [container][name] {
    mutate {
      add_field => { "container_name" => "%{[container][name]}" }
      add_tag => ["docker", "contextchain"]
    }
    
    # Tag by container type
    if [container][name] =~ /kafka/ {
      mutate { add_tag => ["kafka"] }
    }
    
    if [container][name] =~ /redis/ {
      mutate { add_tag => ["redis", "cortext_redis"] }
    }
    
    if [container][name] =~ /elasticsearch/ {
      mutate { add_tag => ["elasticsearch"] }
    }
    
    if [container][name] =~ /nginx/ {
      mutate { add_tag => ["nginx", "proxy"] }
    }
    
    if [container][name] =~ /logstash/ {
      mutate { add_tag => ["logstash"] }
    }
    
    if [container][name] =~ /kibana/ {
      mutate { add_tag => ["kibana"] }
    }
  }
  
  # Parse log levels from message
  if [message] =~ /ERROR/ {
    mutate { add_field => { "log_level" => "ERROR" } }
  } else if [message] =~ /WARN/ {
    mutate { add_field => { "log_level" => "WARN" } }
  } else if [message] =~ /INFO/ {
    mutate { add_field => { "log_level" => "INFO" } }
  } else if [message] =~ /DEBUG/ {
    mutate { add_field => { "log_level" => "DEBUG" } }
  } else {
    mutate { add_field => { "log_level" => "UNKNOWN" } }
  }
  
  # Clean up and enhance
  if [message] {
    mutate {
      strip => ["message"]
    }
  }
}

output {
  elasticsearch {
    hosts => ["contextchain-elasticsearch:9200"]
    index => "contextchain-logs-%{+YYYY.MM.dd}"
    
    # Simple template management
    manage_template => true
    template_name => "contextchain-template"
    template_overwrite => true
  }
  
  # Console output for debugging
  stdout {
    codec => dots
  }
}
EOF

# Create Filebeat configuration
echo "📋 Creating Filebeat configuration..."
cat > filebeat/filebeat.yml << 'EOF'
# Filebeat Configuration for ContextChain
filebeat.inputs:
- type: container
  paths:
    - '/var/lib/docker/containers/*/*.log'
  fields:
    logtype: docker
    environment: contextchain
    project: cortext_redis
  fields_under_root: true
  processors:
  - add_docker_metadata:
      host: "unix:///var/run/docker.sock"

# Redis specific log collection
- type: log
  paths:
    - '/var/lib/docker/volumes/contextchain_redis_master_data/_data/*.log'
    - '/var/lib/docker/volumes/contextchain_redis_slave_data/_data/*.log'
  fields:
    logtype: redis
    environment: contextchain
    project: cortext_redis
  fields_under_root: true

output.logstash:
  hosts: ["contextchain-logstash:5044"]

processors:
- add_host_metadata:
    when.not.contains.tags: forwarded
- add_cloud_metadata: ~
- add_docker_metadata: ~

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644

# Setup template
setup.template.name: "contextchain"
setup.template.pattern: "contextchain-*"
setup.template.enabled: true
EOF

# Set permissions
echo "🔐 Setting permissions..."
chmod +x setup.sh
chmod 644 nginx/nginx.conf
chmod 644 redis/redis-master.conf
chmod 644 redis/redis-slave.conf
chmod 644 kafka/client.properties
chmod 644 logstash/config/logstash.yml
chmod 644 logstash/pipeline/logstash.conf
chmod 644 filebeat/filebeat.yml

echo "✅ ContextChain Infrastructure setup complete!"
echo ""
echo "🗄️ Redis Database Configuration:"
echo "   - Database Name: cortext_redis"
echo "   - Master RDB File: cortext_redis_master.rdb"
echo "   - Master AOF File: cortext_redis_master.aof"
echo "   - Slave RDB File: cortext_redis_slave.rdb"
echo "   - Slave AOF File: cortext_redis_slave.aof"
echo ""
echo "📋 Next steps:"
echo "1. Run: docker-compose up -d"
echo "2. Access services (ALL through Nginx proxy):"
echo "   🌐 Web Services:"
echo "   - Main Portal: http://localhost"
echo "   - AKHQ (Kafka UI): http://localhost:8080"
echo "   - Kibana: http://localhost:5601"
echo "   - Elasticsearch: http://localhost:9200"
echo "   - Kafka Exporter: http://localhost:9308"
echo "   - Logstash API: http://localhost:9600"
echo "   - Health Check: http://localhost/health"
echo "   - LB Status: http://localhost/lb-status"
echo ""
echo "   🔌 TCP Services:"
echo "   - Redis Write (Master): localhost:6379"
echo "   - Redis Read (Slave): localhost:6380"
echo "   - Kafka PLAINTEXT: localhost:9092"
echo "   - Kafka SASL: localhost:9093"
echo "   - Kafka External: localhost:29092"
echo "   - Kafka JMX: localhost:9999"
echo "   - Logstash Beats: localhost:5044"
echo "   - Logstash TCP: localhost:5001"
echo ""
echo "🔧 Redis Connection Examples:"
echo "   # Write Operations (Master)"
echo "   redis-cli -h localhost -p 6379 -n 0"
echo ""
echo "   # Read Operations (Slave)"  
echo "   redis-cli -h localhost -p 6380 -n 0"
echo ""
echo "🔍 Monitor logs with:"
echo "   docker-compose logs -f [service-name]"
echo ""
echo "🛑 Stop services with:"
echo "   docker-compose down"
echo ""
echo "💾 Data persistence:"
echo "   - Redis data: ./volumes/redis_*_data"
echo "   - Elasticsearch data: ./volumes/elasticsearch_data"
echo "   - Kafka data: ./volumes/kafka_data"