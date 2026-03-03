package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"regexp"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds/rdsutils"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	_ "github.com/lib/pq"
	"github.com/pressly/goose/v3"
)

// getDBPassword fetches the DB password from AWS Secrets Manager using the ARN
func getDBPassword(secretArn string) (string, error) {
	sess, err := session.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create AWS session: %w", err)
	}
	client := secretsmanager.New(sess)
	input := &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretArn),
	}
	result, err := client.GetSecretValue(input)
	if err != nil {
		return "", fmt.Errorf("failed to get secret value: %w", err)
	}
	var secretString string
	if result.SecretString != nil {
		secretString = *result.SecretString
	} else {
		return "", fmt.Errorf("secret value is binary, not supported")
	}
	// Assume the secret is a JSON with at least a "password" field
	var secretMap map[string]string
	if err := json.Unmarshal([]byte(secretString), &secretMap); err != nil {
		return "", fmt.Errorf("failed to unmarshal secret JSON: %w", err)
	}
	password, ok := secretMap["password"]
	if !ok {
		return "", fmt.Errorf("password field not found in secret")
	}
	return password, nil
}

// getIAMAuthToken generates a short-lived RDS IAM authentication token using the Lambda's
// execution role credentials. The token is valid for 15 minutes and used as the DB password.
func getIAMAuthToken(host, port, region, dbUser string) (string, error) {
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		return "", fmt.Errorf("failed to create AWS session: %w", err)
	}
	endpoint := fmt.Sprintf("%s:%s", host, port)
	token, err := rdsutils.BuildAuthToken(endpoint, region, dbUser, sess.Config.Credentials)
	if err != nil {
		return "", fmt.Errorf("failed to build IAM auth token: %w", err)
	}
	return token, nil
}

// buildPostgresURL constructs the PostgreSQL connection URL from environment variables.
// When USE_IAM_AUTH=true, an IAM authentication token is used instead of a static password.
// The Lambda's execution role must have the rds-db:connect IAM permission.
func buildPostgresURL() (string, error) {
	user := os.Getenv("DB_USERNAME")
	host := os.Getenv("DB_ADDRESS")
	port := os.Getenv("DB_PORT")
	dbname := os.Getenv("DB_NAME")
	useIAMAuth := os.Getenv("USE_IAM_AUTH") == "true"

	if user == "" || host == "" || port == "" || dbname == "" {
		return "", fmt.Errorf("missing one or more required environment variables: DB_USERNAME, DB_ADDRESS, DB_PORT, DB_NAME")
	}

	var password string
	if useIAMAuth {
		region := os.Getenv("DB_REGION")
		if region == "" {
			return "", fmt.Errorf("DB_REGION is required when USE_IAM_AUTH is true")
		}
		log.Printf("Using IAM authentication for DB connection (region: %s, user: %s)", region, user)
		token, err := getIAMAuthToken(host, port, region, user)
		if err != nil {
			return "", fmt.Errorf("failed to generate IAM auth token: %w", err)
		}
		password = token
	} else {
		secretArn := os.Getenv("DB_SECRET_ARN")
		if secretArn == "" {
			return "", fmt.Errorf("DB_SECRET_ARN is required when USE_IAM_AUTH is false")
		}
		var err error
		password, err = getDBPassword(secretArn)
		if err != nil {
			return "", fmt.Errorf("failed to retrieve DB password: %w", err)
		}
	}

	// URL-encode username and password
	encodedUser := url.QueryEscape(user)
	encodedPassword := url.QueryEscape(password)

	dbURL := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=require", encodedUser, encodedPassword, host, port, dbname)

	// When DB_SCHEMA is set, include search_path in the connection URL so that
	// every connection obtained from the *sql.DB pool uses the correct schema.
	// lib/pq treats unknown DSN parameters as SET key=value session variables.
	schema := os.Getenv("DB_SCHEMA")
	if schema != "" && schema != "public" {
		dbURL += "&search_path=" + url.QueryEscape(schema)
	}

	return dbURL, nil
}

// setupSchemaAndUser creates the schema if it doesn't exist and ensures app_user role
// has appropriate access scoped to that schema only.
// The password is read from the Terraform-managed Secrets Manager secret.
func setupSchemaAndUser(db *sql.DB, schema, appUserSecretName string) error {
	appUsername := fmt.Sprintf("app_user_%s", schema)

	log.Printf("Setting up schema '%s' and user '%s'...", schema, appUsername)

	// Read the password from the Terraform-managed Secrets Manager secret
	password, err := getDBPassword(appUserSecretName)
	if err != nil {
		return fmt.Errorf("failed to read app user password from secret %s: %w", appUserSecretName, err)
	}

	// Create schema if not exists
	if _, err := db.Exec(fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema)); err != nil {
		return fmt.Errorf("failed to create schema %s: %w", schema, err)
	}
	log.Printf("Schema '%s' ensured", schema)

	// Check if role exists
	var roleExists bool
	err = db.QueryRow("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = $1)", appUsername).Scan(&roleExists)
	if err != nil {
		return fmt.Errorf("failed to check if role %s exists: %w", appUsername, err)
	}

	if !roleExists {
		// Create the role with the password from Secrets Manager
		if _, err := db.Exec(fmt.Sprintf("CREATE ROLE %s LOGIN PASSWORD '%s'", appUsername, password)); err != nil {
			return fmt.Errorf("failed to create role %s: %w", appUsername, err)
		}
		log.Printf("Created role '%s'", appUsername)
	} else {
		// Sync password with the Terraform-managed secret (supports rotation)
		if _, err := db.Exec(fmt.Sprintf("ALTER ROLE %s PASSWORD '%s'", appUsername, password)); err != nil {
			return fmt.Errorf("failed to update password for role %s: %w", appUsername, err)
		}
		log.Printf("Synced password for existing role '%s' from Secrets Manager", appUsername)
	}

	// Set default search_path for the role so it always uses the correct schema
	if _, err := db.Exec(fmt.Sprintf("ALTER ROLE %s SET search_path TO %s", appUsername, schema)); err != nil {
		return fmt.Errorf("failed to set search_path for %s: %w", appUsername, err)
	}

	// Grant rds_iam so the app_user can authenticate via IAM tokens instead of a password.
	// This is a no-op if the rds_iam role does not exist (non-Aurora environments).
	var rdsIamExists bool
	if err := db.QueryRow("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'rds_iam')").Scan(&rdsIamExists); err != nil {
		return fmt.Errorf("failed to check for rds_iam role: %w", err)
	}
	if rdsIamExists {
		if _, err := db.Exec(fmt.Sprintf("GRANT rds_iam TO %s", appUsername)); err != nil {
			return fmt.Errorf("failed to grant rds_iam to %s: %w", appUsername, err)
		}
		log.Printf("Granted rds_iam to '%s' for IAM authentication support", appUsername)
	}

	// Grant schema usage and DML privileges
	grants := []string{
		fmt.Sprintf("GRANT USAGE ON SCHEMA %s TO %s", schema, appUsername),
		fmt.Sprintf("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %s TO %s", schema, appUsername),
		fmt.Sprintf("GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA %s TO %s", schema, appUsername),
		fmt.Sprintf("ALTER DEFAULT PRIVILEGES IN SCHEMA %s GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %s", schema, appUsername),
		fmt.Sprintf("ALTER DEFAULT PRIVILEGES IN SCHEMA %s GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %s", schema, appUsername),
	}

	for _, grant := range grants {
		if _, err := db.Exec(grant); err != nil {
			return fmt.Errorf("failed to execute grant '%s': %w", grant, err)
		}
	}

	log.Printf("Granted schema-scoped privileges to '%s' on schema '%s'", appUsername, schema)
	return nil
}

// Response struct
type Response struct {
	Message string `json:"message"`
}

// Event struct for Lambda invocation payload
type Event struct {
	Action string `json:"action"` // "migrate" (default) or "teardown"
}

// teardownSchemaAndUser drops the schema and its app_user role.
// This is called during environment destruction to clean up database resources.
func teardownSchemaAndUser(db *sql.DB, schema string) error {
	appUsername := fmt.Sprintf("app_user_%s", schema)

	log.Printf("Tearing down schema '%s' and user '%s'...", schema, appUsername)

	// Revoke all privileges and drop schema (CASCADE drops all objects in the schema)
	teardownSQL := []string{
		fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema),
	}

	for _, stmt := range teardownSQL {
		log.Printf("Executing: %s", stmt)
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("failed to execute '%s': %w", stmt, err)
		}
	}
	log.Printf("Dropped schema '%s'", schema)

	// Revoke all remaining privileges and drop the role
	var roleExists bool
	err := db.QueryRow("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = $1)", appUsername).Scan(&roleExists)
	if err != nil {
		return fmt.Errorf("failed to check if role %s exists: %w", appUsername, err)
	}

	if roleExists {
		// Reassign owned objects to current user (postgres) and drop owned
		revokeSQL := []string{
			fmt.Sprintf("REASSIGN OWNED BY %s TO CURRENT_USER", appUsername),
			fmt.Sprintf("DROP OWNED BY %s", appUsername),
			fmt.Sprintf("DROP ROLE %s", appUsername),
		}
		for _, stmt := range revokeSQL {
			log.Printf("Executing: %s", stmt)
			if _, err := db.Exec(stmt); err != nil {
				return fmt.Errorf("failed to execute '%s': %w", stmt, err)
			}
		}
		log.Printf("Dropped role '%s'", appUsername)
	} else {
		log.Printf("Role '%s' does not exist, nothing to drop", appUsername)
	}

	return nil
}

// HandleRequest is the handler function for the Lambda function
func HandleRequest(ctx context.Context, event Event) (Response, error) {
	action := event.Action
	if action == "" {
		action = "migrate"
	}

	log.Printf("Starting Goose migration Lambda handler (action: %s)", action)

	schema := os.Getenv("DB_SCHEMA")
	appUserSecretName := os.Getenv("APP_USER_SECRET_NAME")

	if schema == "" {
		schema = "public"
		log.Println("DB_SCHEMA not set, defaulting to 'public'")
	}

	dbURL, err := buildPostgresURL()
	if err != nil {
		log.Printf("Failed to build DB URL: %s", redactPassword(err.Error()))
		return Response{"Failed to build DB URL: " + redactPassword(err.Error())}, err
	}

	// Redact password in log output
	log.Printf("Connecting to DB: %s", redactPassword(dbURL))
	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Printf("Failed to connect to DB: %s", redactPassword(err.Error()))
		return Response{"Failed to connect to DB"}, err
	}
	defer db.Close()

	// Handle teardown action — drops schema and user for environment cleanup
	if action == "teardown" {
		if schema == "public" {
			return Response{"Cannot teardown public schema"}, fmt.Errorf("cannot teardown public schema")
		}
		if err := teardownSchemaAndUser(db, schema); err != nil {
			log.Printf("Failed to teardown schema and user: %s", err.Error())
			return Response{"Failed to teardown schema and user"}, err
		}
		log.Printf("Teardown successful (schema: %s)", schema)
		return Response{fmt.Sprintf("Teardown successful (schema: %s)", schema)}, nil
	}

	// --- Migrate action (default) ---

	// Step 1: Create schema and app_user (runs as master user)
	if schema != "public" {
		if appUserSecretName == "" {
			return Response{"APP_USER_SECRET_NAME is required when DB_SCHEMA is set"}, fmt.Errorf("APP_USER_SECRET_NAME is required when DB_SCHEMA is set")
		}
		if err := setupSchemaAndUser(db, schema, appUserSecretName); err != nil {
			log.Printf("Failed to setup schema and user: %s", err.Error())
			return Response{"Failed to setup schema and user"}, err
		}
	}

	// Step 2: Run goose migrations.
	// search_path is set via the connection URL (see buildPostgresURL), so every
	// connection from the pool automatically targets the correct schema.
	log.Println("Running goose.Up migrations...")
	if err := goose.Up(db, "migrations"); err != nil {
		log.Printf("Migration failed: %s", redactPassword(err.Error()))
		return Response{"Migration failed"}, err
	}

	// Step 3: Re-grant DML privileges on tables/sequences created by the migrations.
	// ALTER DEFAULT PRIVILEGES (set in setupSchemaAndUser) covers future objects,
	// but an explicit re-grant ensures privileges are correct even if the default
	// privileges were modified or if migrations ran before they were set.
	if schema != "public" {
		appUsername := fmt.Sprintf("app_user_%s", schema)
		log.Printf("Re-granting privileges on migrated objects to '%s'...", appUsername)
		regrants := []string{
			fmt.Sprintf("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %s TO %s", schema, appUsername),
			fmt.Sprintf("GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA %s TO %s", schema, appUsername),
		}
		for _, g := range regrants {
			if _, err := db.Exec(g); err != nil {
				log.Printf("Failed to execute re-grant '%s': %s", g, err.Error())
				return Response{"Failed to re-grant privileges after migration"}, err
			}
		}
	}

	log.Printf("Migration successful (schema: %s)", schema)
	return Response{fmt.Sprintf("Migration successful (schema: %s)", schema)}, nil
}

// redactPassword redacts the password in a Postgres connection URL for logging
func redactPassword(url string) string {
	return regexp.MustCompile(`:[^:@/]+@`).ReplaceAllString(url, ":[REDACTED]@")
}

func main() {
	lambda.Start(HandleRequest)
}
