-- Migration: Create profiles table
-- Purpose: Store user profile data synchronized with Cognito
-- IAM DB Auth: app_user connects using IAM tokens (no password)

CREATE TABLE IF NOT EXISTS profiles (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(128) NOT NULL UNIQUE COMMENT 'Cognito sub claim (UUID)',
  email VARCHAR(255) NOT NULL,
  phone_number VARCHAR(20),
  full_name VARCHAR(255),
  role ENUM('ADMIN', 'DRIVER', 'PASSENGER') NOT NULL DEFAULT 'PASSENGER',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_user_id (user_id),
  INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Grant permissions to app_user (IAM-authenticated user)
-- Note: This must be run after creating the IAM-authenticated MySQL user
-- Example: CREATE USER 'app_user' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT SELECT, INSERT, UPDATE, DELETE ON ridebooking.profiles TO 'app_user'@'%';
