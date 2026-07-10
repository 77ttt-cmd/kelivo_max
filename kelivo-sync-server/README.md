# Kelivo Max Sync Server

Backend server for Kelivo Max cloud sync.

## Development

### Prerequisites
- Dart SDK >= 3.12.0
- Docker & Docker Compose (for PostgreSQL)

### Start database
```bash
docker-compose up -d db
```

### Run server
```bash
dart pub get
dart run bin/server.dart
```

### Run tests
```bash
dart test
```

### Health check
```bash
curl http://localhost:8080/health
```
