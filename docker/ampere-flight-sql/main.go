package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/apache/arrow-go/v18/arrow"
	"github.com/apache/arrow-go/v18/arrow/flight"
	"github.com/apache/arrow-go/v18/arrow/flight/flightsql"
	"github.com/apache/arrow-go/v18/arrow/memory"
	duckdb "github.com/duckdb/duckdb-go/v2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

type config struct {
	flightPort, healthPort int
	threads                int
	maxQueries             int
	memoryLimit            string
	minioEndpoint          string
	minioAccessKey         string
	minioSecretKey         string
	catalogURI             string
	oauthURI               string
	oauthScope             string
	clientID               string
	clientSecret           string
	warehouse              string
	flightToken            string
	caCertFile             string
}

func required(name string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		log.Fatalf("missing required environment variable %s", name)
	}
	return value
}

func envInt(name string, fallback int) int {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	n, err := strconv.Atoi(value)
	if err != nil || n < 1 {
		log.Fatalf("%s must be a positive integer", name)
	}
	return n
}

func loadConfig() config {
	return config{
		flightPort:     envInt("FLIGHT_SQL_PORT", 8815),
		healthPort:     envInt("HEALTH_PORT", 8080),
		threads:        envInt("DUCKDB_THREADS", 2),
		maxQueries:     envInt("MAX_CONCURRENT_QUERIES", 1),
		memoryLimit:    required("DUCKDB_MEMORY_LIMIT"),
		minioEndpoint:  required("MINIO_S3_ENDPOINT"),
		minioAccessKey: required("MINIO_ACCESS_KEY"),
		minioSecretKey: required("MINIO_SECRET_KEY"),
		catalogURI:     required("LAKEKEEPER_CATALOG_URI"),
		oauthURI:       required("LAKEKEEPER_OAUTH_URI"),
		oauthScope:     required("LAKEKEEPER_SCOPE"),
		clientID:       required("LAKEKEEPER_CLIENT_ID"),
		clientSecret:   required("LAKEKEEPER_CLIENT_SECRET"),
		warehouse:      required("ICEBERG_GOLD_WAREHOUSE"),
		flightToken:    required("FLIGHT_SQL_TOKEN"),
		caCertFile:     strings.TrimSpace(os.Getenv("DUCKDB_CA_CERT_FILE")),
	}
}

func quoted(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }

func initialize(ctx context.Context, cfg config) (*sql.DB, *sql.Conn, error) {
	db, err := sql.Open("duckdb", "")
	if err != nil {
		return nil, nil, err
	}
	db.SetMaxOpenConns(1)
	conn, err := db.Conn(ctx)
	if err != nil {
		db.Close()
		return nil, nil, err
	}
	closeOnError := func(err error) (*sql.DB, *sql.Conn, error) {
		conn.Close()
		db.Close()
		return nil, nil, err
	}
	endpoint := strings.TrimPrefix(strings.TrimPrefix(cfg.minioEndpoint, "https://"), "http://")
	ssl := strings.HasPrefix(cfg.minioEndpoint, "https://")
	if strings.Contains(endpoint, "/") || !strings.HasPrefix(cfg.minioEndpoint, "http") {
		return closeOnError(errors.New("MINIO_S3_ENDPOINT must be an HTTP(S) origin"))
	}
	statements := []string{
		fmt.Sprintf("SET threads = %d", cfg.threads),
		"SET memory_limit = " + quoted(cfg.memoryLimit),
		"LOAD httpfs",
		"LOAD iceberg",
	}
	if cfg.caCertFile != "" {
		statements = append(statements, "SET ca_cert_file = "+quoted(cfg.caCertFile))
	}
	statements = append(statements,
		fmt.Sprintf("CREATE SECRET flight_s3 (TYPE S3, PROVIDER CONFIG, KEY_ID %s, SECRET %s, ENDPOINT %s, REGION 'us-east-1', URL_STYLE 'path', USE_SSL %t)", quoted(cfg.minioAccessKey), quoted(cfg.minioSecretKey), quoted(endpoint), ssl),
		fmt.Sprintf("CREATE SECRET flight_lakekeeper (TYPE ICEBERG, CLIENT_ID %s, CLIENT_SECRET %s, OAUTH2_SERVER_URI %s, OAUTH2_SCOPE %s, ENDPOINT %s)", quoted(cfg.clientID), quoted(cfg.clientSecret), quoted(cfg.oauthURI), quoted(cfg.oauthScope), quoted(cfg.catalogURI)),
		fmt.Sprintf("ATTACH %s AS iceberg_gold (TYPE ICEBERG, READ_ONLY)", quoted(cfg.warehouse)),
		"SET lock_configuration = true",
		"SELECT * FROM iceberg_gold.gold.fct_orders_sales LIMIT 0",
	)
	for index, statement := range statements {
		if _, err := conn.ExecContext(ctx, statement); err != nil {
			return closeOnError(fmt.Errorf("DuckDB initialization step %d failed: %w", index+1, err))
		}
	}
	return db, conn, nil
}

func authMiddleware(token string) flight.ServerMiddleware {
	check := func(ctx context.Context) error {
		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			return status.Error(codes.Unauthenticated, "missing authorization")
		}
		values := md.Get("authorization")
		if len(values) != 1 || subtle.ConstantTimeCompare([]byte(values[0]), []byte("Bearer "+token)) != 1 {
			return status.Error(codes.Unauthenticated, "invalid authorization")
		}
		return nil
	}
	return flight.ServerMiddleware{
		Unary: func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
			if err := check(ctx); err != nil {
				return nil, err
			}
			return handler(ctx, req)
		},
		Stream: func(srv any, stream grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
			if err := check(stream.Context()); err != nil {
				return err
			}
			return handler(srv, stream)
		},
	}
}

func main() {
	if os.Getenv("FLIGHT_SQL_INSTALL_EXTENSIONS") == "1" {
		if err := installExtensions(); err != nil {
			log.Fatal(err)
		}
		return
	}
	cfg := loadConfig()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	db, conn, err := initialize(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	defer conn.Close()

	queryServer := &queryServer{conn: conn, slots: make(chan struct{}, cfg.maxQueries)}
	queryServer.Alloc = memory.DefaultAllocator
	server := flight.NewServerWithMiddleware([]flight.ServerMiddleware{authMiddleware(cfg.flightToken)})
	server.RegisterFlightService(flightsql.NewFlightServer(queryServer))
	if err := server.Init(fmt.Sprintf("0.0.0.0:%d", cfg.flightPort)); err != nil {
		log.Fatal(err)
	}
	var ready atomic.Bool
	health := http.NewServeMux()
	health.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	health.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	httpServer := &http.Server{Addr: fmt.Sprintf("0.0.0.0:%d", cfg.healthPort), Handler: health, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("health server failed: %v", err)
			stop()
		}
	}()
	go func() {
		ready.Store(true)
		if err := server.Serve(); err != nil {
			log.Printf("Flight SQL server failed: %v", err)
			stop()
		}
	}()
	log.Printf("Flight SQL ready on port %d; Gold Iceberg attached", cfg.flightPort)
	<-ctx.Done()
	ready.Store(false)
	server.Shutdown()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}

func installExtensions() error {
	db, err := sql.Open("duckdb", "")
	if err != nil {
		return err
	}
	defer db.Close()
	for _, extension := range []string{"httpfs", "avro", "iceberg"} {
		if _, err := db.Exec("INSTALL " + extension); err != nil {
			return fmt.Errorf("install %s extension: %w", extension, err)
		}
	}
	return nil
}

func arrowQuery(ctx context.Context, conn driver.Conn, query string) (*arrow.Schema, error) {
	arrowConn, err := duckdb.NewArrowFromConn(conn)
	if err != nil {
		return nil, err
	}
	reader, err := arrowConn.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer reader.Release()
	return reader.Schema(), nil
}
