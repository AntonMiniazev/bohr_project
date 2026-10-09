package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"database/sql/driver"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/apache/arrow-go/v18/arrow"
	"github.com/apache/arrow-go/v18/arrow/array"
	"github.com/apache/arrow-go/v18/arrow/flight"
	"github.com/apache/arrow-go/v18/arrow/flight/flightsql"
	duckdb "github.com/duckdb/duckdb-go/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type queryServer struct {
	flightsql.BaseServer
	conn     *sql.Conn
	slots    chan struct{}
	prepared sync.Map
}

func (s *queryServer) takeSlot(ctx context.Context) error {
	select {
	case s.slots <- struct{}{}:
		return nil
	case <-ctx.Done():
		return status.Error(codes.Canceled, "query canceled while waiting for a slot")
	}
}

func (s *queryServer) releaseSlot() { <-s.slots }

func (s *queryServer) GetFlightInfoStatement(_ context.Context, cmd flightsql.StatementQuery, desc *flight.FlightDescriptor) (*flight.FlightInfo, error) {
	if len(cmd.GetTransactionId()) != 0 {
		return nil, status.Error(codes.Unimplemented, "transactions are unavailable")
	}
	query, err := validateQuery(cmd.GetQuery())
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	ticket, err := flightsql.CreateStatementQueryTicket([]byte(query))
	if err != nil {
		return nil, err
	}
	return &flight.FlightInfo{
		Endpoint:         []*flight.FlightEndpoint{{Ticket: &flight.Ticket{Ticket: ticket}}},
		FlightDescriptor: desc,
		TotalRecords:     -1,
		TotalBytes:       -1,
	}, nil
}

func (s *queryServer) GetSchemaStatement(ctx context.Context, cmd flightsql.StatementQuery, _ *flight.FlightDescriptor) (*flight.SchemaResult, error) {
	if len(cmd.GetTransactionId()) != 0 {
		return nil, status.Error(codes.Unimplemented, "transactions are unavailable")
	}
	query, err := validateQuery(cmd.GetQuery())
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return s.schemaForQuery(ctx, query)
}

func (s *queryServer) schemaForQuery(ctx context.Context, query string) (*flight.SchemaResult, error) {
	if err := s.takeSlot(ctx); err != nil {
		return nil, err
	}
	defer s.releaseSlot()
	var schema *arrow.Schema
	probe := "SELECT * FROM (" + query + ") AS flight_schema_probe LIMIT 0"
	err := s.conn.Raw(func(raw any) error {
		var queryErr error
		schema, queryErr = arrowQuery(ctx, raw.(driver.Conn), probe)
		return queryErr
	})
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, "schema query failed: "+err.Error())
	}
	return &flight.SchemaResult{Schema: flight.SerializeSchema(schema, s.Alloc)}, nil
}

type queryReady struct {
	schema *arrow.Schema
	err    error
}

func (s *queryServer) DoGetStatement(ctx context.Context, cmd flightsql.StatementQueryTicket) (*arrow.Schema, <-chan flight.StreamChunk, error) {
	query, err := validateQuery(string(cmd.GetStatementHandle()))
	if err != nil {
		return nil, nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return s.doGetQuery(ctx, query)
}

func (s *queryServer) CreatePreparedStatement(_ context.Context, req flightsql.ActionCreatePreparedStatementRequest) (flightsql.ActionCreatePreparedStatementResult, error) {
	if len(req.GetTransactionId()) != 0 {
		return flightsql.ActionCreatePreparedStatementResult{}, status.Error(codes.Unimplemented, "transactions are unavailable")
	}
	query, err := validateQuery(req.GetQuery())
	if err != nil {
		return flightsql.ActionCreatePreparedStatementResult{}, status.Error(codes.InvalidArgument, err.Error())
	}
	handle := make([]byte, 32)
	if _, err := rand.Read(handle); err != nil {
		return flightsql.ActionCreatePreparedStatementResult{}, status.Error(codes.Internal, "could not create statement handle")
	}
	s.prepared.Store(string(handle), query)
	return flightsql.ActionCreatePreparedStatementResult{Handle: handle}, nil
}

func (s *queryServer) ClosePreparedStatement(_ context.Context, req flightsql.ActionClosePreparedStatementRequest) error {
	if _, found := s.prepared.LoadAndDelete(string(req.GetPreparedStatementHandle())); !found {
		return status.Error(codes.InvalidArgument, "prepared statement not found")
	}
	return nil
}

func (s *queryServer) preparedQuery(handle []byte) (string, error) {
	value, found := s.prepared.Load(string(handle))
	if !found {
		return "", status.Error(codes.InvalidArgument, "prepared statement not found")
	}
	return value.(string), nil
}

func (s *queryServer) GetFlightInfoPreparedStatement(_ context.Context, cmd flightsql.PreparedStatementQuery, desc *flight.FlightDescriptor) (*flight.FlightInfo, error) {
	if _, err := s.preparedQuery(cmd.GetPreparedStatementHandle()); err != nil {
		return nil, err
	}
	return &flight.FlightInfo{
		Endpoint:         []*flight.FlightEndpoint{{Ticket: &flight.Ticket{Ticket: desc.Cmd}}},
		FlightDescriptor: desc,
		TotalRecords:     -1,
		TotalBytes:       -1,
	}, nil
}

func (s *queryServer) GetSchemaPreparedStatement(ctx context.Context, cmd flightsql.PreparedStatementQuery, _ *flight.FlightDescriptor) (*flight.SchemaResult, error) {
	query, err := s.preparedQuery(cmd.GetPreparedStatementHandle())
	if err != nil {
		return nil, err
	}
	return s.schemaForQuery(ctx, query)
}

func (s *queryServer) DoGetPreparedStatement(ctx context.Context, cmd flightsql.PreparedStatementQuery) (*arrow.Schema, <-chan flight.StreamChunk, error) {
	query, err := s.preparedQuery(cmd.GetPreparedStatementHandle())
	if err != nil {
		return nil, nil, err
	}
	return s.doGetQuery(ctx, query)
}

func (s *queryServer) doGetQuery(ctx context.Context, query string) (*arrow.Schema, <-chan flight.StreamChunk, error) {
	if err := s.takeSlot(ctx); err != nil {
		return nil, nil, err
	}
	chunks := make(chan flight.StreamChunk)
	ready := make(chan queryReady, 1)
	start := time.Now()
	go func() {
		defer s.releaseSlot()
		sent := false
		var rowCount int64
		err := s.conn.Raw(func(raw any) error {
			arrowConn, err := duckdb.NewArrowFromConn(raw.(driver.Conn))
			if err != nil {
				return err
			}
			reader, err := arrowConn.QueryContext(ctx, query)
			if err != nil {
				return err
			}
			defer reader.Release()

			ready <- queryReady{schema: reader.Schema()}
			sent = true

			counted := &countingReader{
				RecordReader: reader,
				rows:         &rowCount,
			}

			flight.StreamChunksFromReader(ctx, counted, chunks)
			return nil
		})
		if !sent {
			ready <- queryReady{err: err}
			close(chunks)
		}
		log.Printf("query finished: rows=%d duration=%s error=%v", rowCount, time.Since(start).Round(time.Millisecond), err)
	}()
	result := <-ready
	if result.err != nil {
		return nil, nil, status.Error(codes.InvalidArgument, "query failed: "+result.err.Error())
	}
	return result.schema, chunks, nil
}

type countingReader struct {
	array.RecordReader
	rows *int64
}

func (r *countingReader) Next() bool {
	if !r.RecordReader.Next() {
		return false
	}
	*r.rows += r.RecordReader.RecordBatch().NumRows()
	return true
}

// validateQuery accepts one SELECT only. The lexer treats quoted values as data,
// rejects comments and statement chaining, and blocks commands or table functions
// that could change state or access local files. Gold access is also read-only in
// DuckDB. Storage credentials should be scoped to Gold when a dedicated
// MinIO policy is provisioned.
func validateQuery(input string) (string, error) {
	if len(input) == 0 || len(input) > 65536 {
		return "", fmt.Errorf("query must contain 1 to 65536 bytes")
	}
	lower := strings.ToLower(input)
	for _, path := range []string{"s3://", "http://", "https://", ".parquet", ".csv", ".json"} {
		if strings.Contains(lower, path) {
			return "", fmt.Errorf("direct file and URL paths are unavailable")
		}
	}
	var tokens []string
	var word strings.Builder
	state := byte(0)
	lastSemicolon := -1
	flush := func() {
		if word.Len() != 0 {
			tokens = append(tokens, strings.ToUpper(word.String()))
			word.Reset()
		}
	}
	for i := 0; i < len(input); i++ {
		ch := input[i]
		if state != 0 {
			if ch == state {
				if i+1 < len(input) && input[i+1] == state {
					i++
				} else {
					state = 0
				}
			}
			continue
		}
		if ch == '"' {
			return "", fmt.Errorf("quoted identifiers are unavailable")
		}
		if ch == '\'' {
			flush()
			state = ch
			continue
		}
		if ch == '-' && i+1 < len(input) && input[i+1] == '-' || ch == '/' && i+1 < len(input) && input[i+1] == '*' {
			return "", fmt.Errorf("SQL comments are unavailable")
		}
		if ch == ';' {
			flush()
			if lastSemicolon != -1 {
				return "", fmt.Errorf("only one SQL statement is allowed")
			}
			lastSemicolon = i
			continue
		}
		if ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_' {
			word.WriteByte(ch)
		} else {
			flush()
		}
	}
	flush()
	if state != 0 {
		return "", fmt.Errorf("unterminated SQL string or identifier")
	}
	if lastSemicolon >= 0 && strings.TrimSpace(input[lastSemicolon+1:]) != "" {
		return "", fmt.Errorf("only one SQL statement is allowed")
	}
	if len(tokens) == 0 || tokens[0] != "SELECT" {
		return "", fmt.Errorf("only SELECT is allowed")
	}
	for _, token := range tokens {
		switch token {
		case "INSERT", "UPDATE", "DELETE", "MERGE", "CREATE", "DROP", "ALTER", "ATTACH", "DETACH", "INSTALL", "LOAD", "COPY", "CALL", "PRAGMA", "SET", "RESET", "EXPORT", "IMPORT", "VACUUM", "CHECKPOINT", "EXECUTE", "PREPARE", "QUERY", "QUERY_TABLE", "GLOB", "GETENV", "DUCKDB_SECRETS", "WHICH_SECRET", "DUCKDB_SETTINGS", "CURRENT_SETTING", "ICEBERG_SCAN":
			return "", fmt.Errorf("SQL token %s is unavailable", token)
		}
		if strings.HasPrefix(token, "READ_") || strings.HasPrefix(token, "SQLITE_") || strings.HasPrefix(token, "PRAGMA_") {
			return "", fmt.Errorf("SQL function %s is unavailable", token)
		}
	}
	query := strings.TrimSpace(input)
	if lastSemicolon >= 0 {
		query = strings.TrimSpace(input[:lastSemicolon])
	}
	return query, nil
}
