package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	version   = "dev"
	buildTime = "unknown"
)

var (
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total HTTP requests by path and status code",
		},
		[]string{"method", "path", "status"},
	)
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5},
		},
		[]string{"method", "path"},
	)
)

type App struct {
	dbHost string
	dbPort string
	log    *slog.Logger
}

type HealthResponse struct {
	Status  string `json:"status"`
	DB      string `json:"db,omitempty"`
	Version string `json:"version"`
}

type InfoResponse struct {
	Name      string `json:"name"`
	Version   string `json:"version"`
	BuildTime string `json:"buildTime"`
	Hostname  string `json:"hostname"`
}

func newApp() *App {
	return &App{
		dbHost: os.Getenv("DB_HOST"),
		dbPort: getEnv("DB_PORT", "5432"),
		log: slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelInfo,
		})),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func (a *App) pingDB(ctx context.Context) error {
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(a.dbHost, a.dbPort))
	if err != nil {
		return err
	}
	conn.Close()
	return nil
}

func (a *App) health(w http.ResponseWriter, r *http.Request) {
	resp := HealthResponse{Status: "ok", Version: version}

	if a.dbHost != "" {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := a.pingDB(ctx); err != nil {
			resp.DB = fmt.Sprintf("unreachable: %v", err)
			resp.Status = "degraded"
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(resp) //nolint:errcheck
			return
		}
		resp.DB = "ok"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp) //nolint:errcheck
}

func (a *App) info(w http.ResponseWriter, r *http.Request) {
	hostname, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(InfoResponse{ //nolint:errcheck
		Name:      "devops-portfolio-app",
		Version:   version,
		BuildTime: buildTime,
		Hostname:  hostname,
	})
}

// responseWriter wraps http.ResponseWriter to capture the status code for metrics.
type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

func (a *App) withMetrics(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}

		next(rw, r)

		duration := time.Since(start).Seconds()
		status := fmt.Sprintf("%d", rw.status)

		httpRequestsTotal.WithLabelValues(r.Method, path, status).Inc()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(duration)

		a.log.Info("request",
			"method", r.Method,
			"path", path,
			"status", rw.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	}
}

func main() {
	app := newApp()
	port := getEnv("PORT", "8080")

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.withMetrics("/health", app.health))
	mux.HandleFunc("/", app.withMetrics("/", app.info))
	// Prometheus scrape endpoint — separate from app handlers so scrape latency
	// does not pollute application latency histograms.
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		app.log.Info("server starting", "port", port, "version", version, "buildTime", buildTime)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			app.log.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	sig := <-quit
	app.log.Info("shutdown signal received", "signal", sig.String())

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		app.log.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}

	app.log.Info("server stopped cleanly")
}
