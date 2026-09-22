// A small net/http server with the parts you always end up adding anyway:
// request logging, JSON responses, timeouts, and graceful shutdown on SIGINT.
//
// Run:
//	go run http_server.go
//	curl localhost:8080/health
//	curl localhost:8080/api/greet?name=ada
//
// Needs Go 1.21+ (log/slog). On older Go, swap slog for log.Printf.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// maxBodyBytes caps request bodies. Without a limit, a client can stream
// gigabytes into your handler and OOM the box.
const maxBodyBytes = 1 << 20 // 1 MiB

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /api/greet", handleGreet)
	mux.HandleFunc("POST /api/echo", handleEcho)

	srv := &http.Server{
		Addr:              ":8080",
		Handler:           withLogging(withMaxBody(mux)),
		ReadHeaderTimeout: 5 * time.Second,  // slowloris protection
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// Serve in a goroutine so main can wait on the signal channel below.
	errCh := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	// Wait for Ctrl-C / SIGTERM, or for ListenAndServe to blow up.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errCh:
		slog.Error("server failed", "err", err)
		os.Exit(1)
	case sig := <-stop:
		slog.Info("shutting down", "signal", sig.String())
	}

	// Give in-flight requests up to 10s to finish. If they don't, they're cut
	// off. That's better than hanging forever waiting for a stuck client.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}
	slog.Info("bye")
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleGreet(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		// Default rather than 400 — makes curl-ing it friendly.
		name = "world"
	}
	writeJSON(w, http.StatusOK, map[string]string{"greeting": "hello, " + name})
}

func handleEcho(w http.ResponseWriter, r *http.Request) {
	// r.Body is already capped by withMaxBody, so this Decode is safe.
	var payload map[string]any
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"received": payload})
}

// --- middleware -------------------------------------------------------------

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

func withMaxBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		next.ServeHTTP(w, r)
	})
}

// --- helpers ----------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// Headers are already sent, so we can't change the status here. Just log.
		slog.Error("encode response", "err", err)
	}
}
