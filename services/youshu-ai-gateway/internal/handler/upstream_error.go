package handler

import (
	"errors"
	"net/http"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func mapUpstreamError(err error) (status int, code string, message string, retryAfter *int) {
	var upstream *provider.UpstreamError
	if errors.As(err, &upstream) {
		retryAfter = upstream.RetryAfter
		switch upstream.Code {
		case contract.ErrProviderRateLimited, contract.ErrRateLimited:
			return http.StatusTooManyRequests, contract.ErrProviderRateLimited, "AI 服务繁忙，请稍后再试。", retryAfter
		case contract.ErrProviderUnavailable:
			return http.StatusServiceUnavailable, contract.ErrProviderUnavailable, "AI 服务暂时不可用。", nil
		case contract.ErrProviderTimeout:
			return http.StatusGatewayTimeout, contract.ErrProviderTimeout, "AI 响应超时，请稍后再试。", nil
		case contract.ErrInvalidProviderResponse:
			return http.StatusBadGateway, contract.ErrInvalidProviderResponse, "上游返回无效。", nil
		case contract.ErrInternalError:
			return http.StatusInternalServerError, contract.ErrInternalError, "服务异常，请稍后再试。", nil
		default:
			return http.StatusBadGateway, contract.ErrInvalidProviderResponse, "上游返回无效。", nil
		}
	}
	return http.StatusBadGateway, contract.ErrInvalidProviderResponse, "上游返回无效。", nil
}
