# Local Development Setup

## Prerequisites

- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
- Node.js 20 LTS
- npm

## Quick Start

### 1. Start MySQL Database

```bash
# From project root
docker-compose up -d

# Verify MySQL is running
docker-compose ps

# View logs
docker-compose logs -f mysql
```

### 2. Configure Backend Environment

```bash
cd apps/backend-api

# Copy template and edit with your values
cp .env.example .env

# Update Cognito values after running Terraform
# Get from: cd ../../infra/terraform/envs/dev && terraform output
```

### 3. Install Dependencies

```bash
# From apps/backend-api
npm install
```

### 4. Run Database Migrations

```bash
# Connect to MySQL (password: local_dev_password_change_me)
docker exec -it d2-ridebooking-mysql mysql -u app_user -p ridebooking

# Or run migration file
docker exec -i d2-ridebooking-mysql mysql -u root -proot_password_change_me ridebooking < migrations/001_create_profiles_table.sql
```

### 5. Start Backend API

```bash
# Development mode (build then watch dist)
npm run start:dev

# Or production mode
npm run build && npm start
```

### 6. Test Health Endpoint

```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "backend-api",
  "timestamp": "2026-01-19T00:00:00.000Z"
}
```

## Common Tasks

### View Database

```bash
# Connect to MySQL shell
docker exec -it d2-ridebooking-mysql mysql -u app_user -p ridebooking

# Show tables
SHOW TABLES;

# View profiles
SELECT * FROM profiles;
```

### Stop Services

```bash
# Stop MySQL (preserves data)
docker-compose stop

# Stop and remove containers (preserves data in volume)
docker-compose down

# Remove everything including data (CAUTION)
docker-compose down -v
```

### Reset Database

```bash
# Stop and remove volume
docker-compose down -v

# Start fresh
docker-compose up -d

# Re-run migrations
docker exec -i d2-ridebooking-mysql mysql -u root -proot_password_change_me ridebooking < apps/backend-api/migrations/001_create_profiles_table.sql
```

## Environment Variables

### Required for Backend

| Variable | Description | Example |
|----------|-------------|---------|
| `NODE_ENV` | Environment name | `dev` |
| `PORT` | Server port | `3000` |
| `AWS_REGION` | AWS region | `ap-southeast-1` |
| `COGNITO_USER_POOL_ID` | Cognito pool ID | `ap-southeast-1_abc123` |
| `COGNITO_CLIENT_ID` | Cognito client ID | `1a2b3c4d5e...` |
| `DB_HOST` | MySQL host | `localhost` |
| `DB_PORT` | MySQL port | `3306` |
| `DB_NAME` | Database name | `ridebooking` |
| `DB_USER` | Database user | `app_user` |
| `DB_PASSWORD` | Database password (local only) | `local_dev_password_change_me` |

### Getting Cognito Values

After running Terraform in `infra/terraform/envs/dev`:

```bash
cd infra/terraform/envs/dev

# Get User Pool ID
terraform output -raw cognito_user_pool_id

# Get Client ID
terraform output -raw cognito_user_pool_client_id
```

## Troubleshooting

### MySQL Connection Refused

```bash
# Check if MySQL is running
docker-compose ps

# Check logs for errors
docker-compose logs mysql

# Restart MySQL
docker-compose restart mysql
```

### Port 3306 Already in Use

```bash
# Find process using port 3306
# Windows
netstat -ano | findstr :3306

# Linux/Mac
lsof -i :3306

# Kill the process or change port in docker-compose.yml
```

### Backend Can't Connect to MySQL

1. Verify MySQL is healthy: `docker-compose ps`
2. Check `.env` has correct `DB_HOST=localhost` and `DB_PORT=3306`
3. Verify credentials match docker-compose.yml
4. Test connection: `docker exec -it d2-ridebooking-mysql mysql -u app_user -p`

### IAM DB Authentication in Local Dev

Local Docker MySQL does not support IAM authentication. For local dev:
- Use password-based auth (DB_PASSWORD in .env)
- IAM auth is only used in AWS (EC2 → RDS)
- Database service will skip IAM token generation if DB_PASSWORD is set
