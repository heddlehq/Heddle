// Package providers knows the AI providers Heddle offers, and can ask one whether a
// key works and which models it gives access to.
package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/heddlehq/heddle/cli/internal/text"
)

// Provider is an entry of the same list the Credentials page shows.
type Provider struct {
	ID           string
	Name         string
	Note         string
	KeyHint      string
	KeyPage      string
	DefaultModel string
	// EnvKeys are the variables a key for this provider usually sits in already.
	EnvKeys []string

	url     string
	headers func(key string) map[string]string
	models  func(body []byte) []string
}

func bearer(key string) map[string]string {
	return map[string]string{"Authorization": "Bearer " + key}
}

// All lists the providers, in the order the AI page shows them.
var All = []Provider{
	{
		ID: "anthropic", Name: "Anthropic", Note: "Claude",
		KeyHint: "sk-ant-…", KeyPage: "console.anthropic.com/settings/keys",
		DefaultModel: "claude-sonnet-5-5",
		EnvKeys:      []string{"ANTHROPIC_API_KEY"},
		url:          "https://api.anthropic.com/v1/models?limit=100",
		headers: func(key string) map[string]string {
			return map[string]string{"x-api-key": key, "anthropic-version": "2023-06-01"}
		},
		models: dataIDs,
	},
	{
		ID: "openai", Name: "OpenAI", Note: "GPT, GPT Image, Whisper",
		KeyHint: "sk-…", KeyPage: "platform.openai.com/api-keys",
		DefaultModel: "gpt-4o-mini",
		EnvKeys:      []string{"OPENAI_API_KEY"},
		url:          "https://api.openai.com/v1/models",
		headers:      bearer,
		models:       chatModels,
	},
	{
		ID: "google", Name: "Google", Note: "Gemini, Nano Banana",
		KeyHint: "AIza…", KeyPage: "aistudio.google.com/apikey",
		DefaultModel: "gemini-2.5-flash",
		EnvKeys:      []string{"GEMINI_API_KEY", "GOOGLE_API_KEY"},
		url:          "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200",
		headers: func(key string) map[string]string {
			return map[string]string{"x-goog-api-key": key}
		},
		models: geminiModels,
	},
	{
		ID: "xai", Name: "xAI", Note: "Grok",
		KeyHint: "xai-…", KeyPage: "console.x.ai",
		DefaultModel: "grok-4",
		EnvKeys:      []string{"XAI_API_KEY"},
		url:          "https://api.x.ai/v1/models",
		headers:      bearer,
		models:       dataIDs,
	},
}

// Find returns a provider by id.
func Find(id string) (Provider, bool) {
	index := slices.IndexFunc(All, func(p Provider) bool { return p.ID == id })
	if index < 0 {
		return Provider{}, false
	}
	return All[index], true
}

// ErrRejected means the provider answered and refused the key, as opposed to
// not being reachable, which says nothing about the key.
var ErrRejected = errors.New("rejected")

// rejection is an ErrRejected that reads well on screen.
type rejection struct{ message string }

func (r rejection) Error() string        { return r.message }
func (r rejection) Is(target error) bool { return target == ErrRejected }

// Check asks the provider for its models, which proves the key at no cost.
func (p Provider) Check(ctx context.Context, key string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, p.url, nil)
	if err != nil {
		return nil, err
	}
	for name, value := range p.headers(key) {
		request.Header.Set(name, value)
	}

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, 4*1024*1024))
	if err != nil {
		return nil, err
	}

	switch response.StatusCode {
	case http.StatusOK:
		return p.models(body), nil
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusBadRequest:
		return nil, rejection{text.T(p.Name+" refused this key.", "A "+p.Name+" recusou esta chave.")}
	default:
		return nil, fmt.Errorf("%s answered %s", p.Name, response.Status)
	}
}

func dataIDs(body []byte) []string {
	var payload struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if json.Unmarshal(body, &payload) != nil {
		return nil
	}

	ids := make([]string, 0, len(payload.Data))
	for _, model := range payload.Data {
		ids = append(ids, model.ID)
	}
	return ids
}

// chatModels drops what can't chat: OpenAI lists embeddings, audio and images too.
func chatModels(body []byte) []string {
	skip := []string{"embedding", "whisper", "tts", "dall-e", "image", "audio", "realtime", "moderation", "transcribe", "sora", "davinci", "babbage"}
	return slices.DeleteFunc(dataIDs(body), func(id string) bool {
		return slices.ContainsFunc(skip, func(word string) bool { return strings.Contains(id, word) })
	})
}

func geminiModels(body []byte) []string {
	var payload struct {
		Models []struct {
			Name    string   `json:"name"`
			Methods []string `json:"supportedGenerationMethods"`
		} `json:"models"`
	}
	if json.Unmarshal(body, &payload) != nil {
		return nil
	}

	ids := make([]string, 0, len(payload.Models))
	for _, model := range payload.Models {
		if slices.Contains(model.Methods, "generateContent") {
			ids = append(ids, strings.TrimPrefix(model.Name, "models/"))
		}
	}
	return ids
}
