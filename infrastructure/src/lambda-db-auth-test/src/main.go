package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/rds/rdsutils"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"github.com/aws/aws-sdk-go/service/sts"
	_ "github.com/lib/pq"
)

type Response struct {
	Status      string            `json:"status"`
	Auth        string            `json:"auth"`
	User        string            `json:"user"`
	Schema      string            `json:"schema"`
	CallerARN   string            `json:"caller_arn,omitempty"`
	AccountID   string            `json:"account_id,omitempty"`
	TokenLength int               `json:"token_length,omitempty"`
	Tests       map[string]string `json:"tests"`
	Message     string            `json:"message,omitempty"`
}

func handler(ctx context.Context) (Response, error) {
	username := os.Getenv("DB_USERNAME")
	host := os.Getenv("DB_ADDRESS")
	port := os.Getenv("DB_PORT")
	dbname := os.Getenv("DB_NAME")
	schema := os.Getenv("DB_SCHEMA")
	region := os.Getenv("DB_REGION")
	secretName := os.Getenv("APP_USER_SECRET_NAME") // optional: for password fallback test

	if region == "" {
		region = os.Getenv("AWS_REGION")
	}

	log.Printf("=== DB Auth Diagnostic Test ===")
	log.Printf("Host:   %s", host)
	log.Printf("Port:   %s", port)
	log.Printf("User:   %s", username)
	log.Printf("DB:     %s", dbname)
	log.Printf("Schema: %s", schema)
	log.Printf("Region: %s", region)

	tests := make(map[string]string)

	sess, err := session.NewSession(&aws.Config{Region: aws.String(region)})
	if err != nil {
		return Response{Status: "FAIL", Message: fmt.Sprintf("AWS session failed: %s", err)}, nil
	}

	// --- Diagnostic 1: Who am I? (STS GetCallerIdentity) ---
	log.Println("Step 1: STS GetCallerIdentity...")
	var callerARN, accountID string
	stsClient := sts.New(sess)
	identity, err := stsClient.GetCallerIdentity(&sts.GetCallerIdentityInput{})
	if err != nil {
		tests["sts_identity"] = fmt.Sprintf("FAIL: %s", err)
		log.Printf("  FAIL: %s", err)
	} else {
		callerARN = *identity.Arn
		accountID = *identity.Account
		tests["sts_identity"] = callerARN
		log.Printf("  ARN:     %s", callerARN)
		log.Printf("  Account: %s", accountID)
	}

	// --- Diagnostic 2: Generate IAM auth token ---
	log.Println("Step 2: Generate IAM auth token...")
	endpoint := fmt.Sprintf("%s:%s", host, port)
	token, err := rdsutils.BuildAuthToken(endpoint, region, username, sess.Config.Credentials)
	if err != nil {
		return Response{Status: "FAIL", Auth: "iam", CallerARN: callerARN,
			Message: fmt.Sprintf("Token generation failed: %s", err), Tests: tests}, nil
	}
	tokenLen := len(token)
	tests["iam_token_length"] = fmt.Sprintf("%d", tokenLen)
	// Show first 80 chars (safe — it's a presigned URL, contains no secret after expiry)
	preview := token
	if len(preview) > 80 {
		preview = preview[:80] + "..."
	}
	tests["iam_token_preview"] = preview
	log.Printf("  Token length: %d", tokenLen)
	log.Printf("  Token preview: %s", preview)

	// --- Diagnostic 3: Check rds_iam via master user (password auth) ---
	// Connect as master user via Secrets Manager to check rds_iam membership
	// This uses the RDS-managed master secret (not the app user secret)
	log.Println("Step 3: Pre-flight check — verify rds_iam is granted (via password auth)...")
	if secretName != "" {
		pw, err := getSecretPassword(sess, secretName)
		if err != nil {
			tests["preflight_password_connect"] = fmt.Sprintf("FAIL (secret read): %s", err)
			log.Printf("  Cannot read secret %s: %s", secretName, err)
		} else {
			pwURL := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=require",
				url.QueryEscape(username), url.QueryEscape(pw), host, port, dbname)
			pwDB, err := sql.Open("postgres", pwURL)
			if err == nil {
				defer pwDB.Close()
				if err := pwDB.PingContext(ctx); err != nil {
					tests["preflight_password_connect"] = fmt.Sprintf("FAIL (ping): %s", err)
					log.Printf("  Password auth ping failed: %s", err)
				} else {
					tests["preflight_password_connect"] = "PASS"
					log.Println("  Password auth: PASS")

					// Check rds_iam
					var hasRdsIam bool
					err = pwDB.QueryRowContext(ctx,
						`SELECT EXISTS(
							SELECT 1 FROM pg_auth_members
							WHERE roleid = (SELECT oid FROM pg_roles WHERE rolname = 'rds_iam')
							AND member = (SELECT oid FROM pg_roles WHERE rolname = $1)
						)`, username).Scan(&hasRdsIam)
					if err != nil {
						tests["rds_iam_granted"] = fmt.Sprintf("FAIL: %s", err)
					} else {
						tests["rds_iam_granted"] = fmt.Sprintf("%v", hasRdsIam)
						log.Printf("  rds_iam granted to %s: %v", username, hasRdsIam)
					}
				}
			} else {
				tests["preflight_password_connect"] = fmt.Sprintf("FAIL (open): %s", err)
			}
		}
	} else {
		tests["preflight_password_connect"] = "SKIPPED (no APP_USER_SECRET_NAME)"
		log.Println("  Skipped — APP_USER_SECRET_NAME not set")
	}

	// --- Diagnostic 4: IAM token connection attempt ---
	log.Println("Step 4: Connect with IAM token...")
	encodedUser := url.QueryEscape(username)
	encodedToken := url.QueryEscape(token)
	dbURL := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=require",
		encodedUser, encodedToken, host, port, dbname)
	if schema != "" && schema != "public" {
		dbURL += "&search_path=" + url.QueryEscape(schema)
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		tests["iam_connect"] = fmt.Sprintf("FAIL (open): %s", err)
		return Response{Status: "FAIL", Auth: "iam", User: username, Schema: schema,
			CallerARN: callerARN, AccountID: accountID, TokenLength: tokenLen,
			Tests: tests, Message: fmt.Sprintf("sql.Open failed: %s", err)}, nil
	}
	defer db.Close()

	if err := db.PingContext(ctx); err != nil {
		tests["iam_connect"] = fmt.Sprintf("FAIL (ping): %s", err)
		log.Printf("  IAM connect FAILED: %s", err)
		return Response{
			Status: "FAIL", Auth: "iam", User: username, Schema: schema,
			CallerARN: callerARN, AccountID: accountID, TokenLength: tokenLen,
			Tests: tests, Message: fmt.Sprintf("IAM auth failed: %s", err),
		}, nil
	}
	tests["iam_connect"] = "PASS"
	log.Println("  IAM connect: PASS")

	// --- Diagnostic 5: Run queries via IAM connection ---
	var currentUser string
	if err := db.QueryRowContext(ctx, "SELECT current_user").Scan(&currentUser); err != nil {
		tests["current_user"] = fmt.Sprintf("FAIL: %s", err)
	} else {
		tests["current_user"] = currentUser
	}

	var searchPath string
	if err := db.QueryRowContext(ctx, "SHOW search_path").Scan(&searchPath); err != nil {
		tests["search_path"] = fmt.Sprintf("FAIL: %s", err)
	} else {
		tests["search_path"] = searchPath
	}

	rows, err := db.QueryContext(ctx,
		"SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name", schema)
	if err != nil {
		tests["tables"] = fmt.Sprintf("FAIL: %s", err)
	} else {
		defer rows.Close()
		var tables []string
		for rows.Next() {
			var t string
			if err := rows.Scan(&t); err == nil {
				tables = append(tables, t)
			}
		}
		tests["tables"] = fmt.Sprintf("%v", tables)
	}

	log.Println("=== All diagnostics complete ===")

	return Response{
		Status:      "PASS",
		Auth:        "iam",
		User:        currentUser,
		Schema:      schema,
		CallerARN:   callerARN,
		AccountID:   accountID,
		TokenLength: tokenLen,
		Tests:       tests,
	}, nil
}

func getSecretPassword(sess *session.Session, secretName string) (string, error) {
	client := secretsmanager.New(sess)
	result, err := client.GetSecretValue(&secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretName),
	})
	if err != nil {
		return "", err
	}
	if result.SecretString == nil {
		return "", fmt.Errorf("secret is binary")
	}
	var m map[string]string
	if err := json.Unmarshal([]byte(*result.SecretString), &m); err != nil {
		return "", err
	}
	pw, ok := m["password"]
	if !ok {
		return "", fmt.Errorf("no password field in secret")
	}
	return pw, nil
}

func main() {
	lambda.Start(handler)
}
