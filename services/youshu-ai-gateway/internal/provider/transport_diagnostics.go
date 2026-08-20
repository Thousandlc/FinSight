package provider

import (
	"encoding/json"
	"errors"
	"net"
	"net/url"
	"regexp"
	"strings"
)

const (
	ErrorCategoryRequestConstruction = "requestConstructionFailure"
	ErrorCategoryDNS                 = "dnsFailure"
	ErrorCategoryConnection          = "connectionFailure"
	ErrorCategoryTLS                 = "tlsFailure"
	ErrorCategoryTimeout             = "timeout"
	ErrorCategoryHTTP401             = "http401"
	ErrorCategoryHTTP403             = "http403"
	ErrorCategoryHTTP400             = "http400"
	ErrorCategoryHTTP404             = "http404"
	ErrorCategoryHTTP429             = "http429"
	ErrorCategoryHTTP5xx             = "http5xx"
	ErrorCategoryProviderRejected    = "providerRejected"
	ErrorCategoryResponseRead        = "responseReadFailure"
)

// ParseRequestURLParts extracts safe URL parts for diagnostics (no secrets).
func ParseRequestURLParts(rawURL string) (scheme, host, path string) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", "", ""
	}
	return u.Scheme, u.Host, u.Path
}

// ClassifyDoError maps client.Do errors to transport categories.
func ClassifyDoError(err error) string {
	if err == nil {
		return ""
	}
	if isTimeoutErr(err) {
		return ErrorCategoryTimeout
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		if netErr.Timeout() {
			return ErrorCategoryTimeout
		}
	}
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return ErrorCategoryDNS
	}
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		if urlErr.Timeout() {
			return ErrorCategoryTimeout
		}
		if urlErr.Op == "dial" || urlErr.Op == "connect" {
			return ErrorCategoryConnection
		}
	}
	msg := strings.ToLower(err.Error())
	switch {
	case strings.Contains(msg, "tls") || strings.Contains(msg, "x509"):
		return ErrorCategoryTLS
	case strings.Contains(msg, "no such host") || strings.Contains(msg, "dns"):
		return ErrorCategoryDNS
	case strings.Contains(msg, "connection refused") || strings.Contains(msg, "connect"):
		return ErrorCategoryConnection
	default:
		return ErrorCategoryConnection
	}
}

// ClassifyHTTPStatus maps HTTP status codes to transport categories.
func ClassifyHTTPStatus(status int) string {
	switch status {
	case 401:
		return ErrorCategoryHTTP401
	case 403:
		return ErrorCategoryHTTP403
	case 400:
		return ErrorCategoryHTTP400
	case 404:
		return ErrorCategoryHTTP404
	case 429:
		return ErrorCategoryHTTP429
	default:
		if status >= 500 {
			return ErrorCategoryHTTP5xx
		}
		if status >= 400 {
			return ErrorCategoryProviderRejected
		}
		return ""
	}
}

type providerErrorEnvelope struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
		Type    string `json:"type"`
	} `json:"error"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ExtractProviderError extracts sanitized provider error fields from JSON bodies.
func ExtractProviderError(body []byte) (code, message string) {
	var env providerErrorEnvelope
	if err := json.Unmarshal(body, &env); err != nil {
		return "", ""
	}
	code = strings.TrimSpace(env.Error.Code)
	if code == "" {
		code = strings.TrimSpace(env.Code)
	}
	message = sanitizeProviderMessage(env.Error.Message)
	if message == "" {
		message = sanitizeProviderMessage(env.Message)
	}
	return code, message
}

var providerSecretPattern = regexp.MustCompile(`sk-[a-zA-Z0-9_-]+`)

func sanitizeProviderMessage(raw string) string {
	msg := strings.TrimSpace(raw)
	if msg == "" {
		return ""
	}
	msg = providerSecretPattern.ReplaceAllString(msg, "[REDACTED]")
	msg = strings.ReplaceAll(msg, "Bearer ", "Bearer [REDACTED] ")
	if len(msg) > 240 {
		msg = msg[:240] + "..."
	}
	return msg
}
