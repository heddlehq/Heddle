package providers

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
)

func serving(t *testing.T, status int, body string) Provider {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer the-key" {
			t.Errorf("headers: %v", r.Header)
		}
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
	t.Cleanup(server.Close)
	return Provider{Name: "Test", url: server.URL, headers: bearer, models: chatModels}
}

func TestCheckListsWhatCanChat(t *testing.T) {
	provider := serving(t, 200, `{"data":[{"id":"gpt-5"},{"id":"text-embedding-3"},{"id":"whisper-1"}]}`)
	models, err := provider.Check(context.Background(), "the-key")
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(models, []string{"gpt-5"}) {
		t.Fatalf("got %v", models)
	}
}

func TestCheckTellsARefusedKeyFromAnOutage(t *testing.T) {
	refused := serving(t, 401, `{}`)
	if _, err := refused.Check(context.Background(), "the-key"); !errors.Is(err, ErrRejected) {
		t.Fatalf("got %v", err)
	}

	down := serving(t, 503, ``)
	if _, err := down.Check(context.Background(), "the-key"); err == nil || errors.Is(err, ErrRejected) {
		t.Fatalf("an outage says nothing about the key: %v", err)
	}
}

func TestGeminiKeepsOnlyWhatGeneratesText(t *testing.T) {
	body := `{"models":[
		{"name":"models/gemini-x","supportedGenerationMethods":["generateContent"]},
		{"name":"models/embedding","supportedGenerationMethods":["embedContent"]}]}`
	if got := geminiModels([]byte(body)); !slices.Equal(got, []string{"gemini-x"}) {
		t.Fatalf("got %v", got)
	}
}

func TestEveryProviderIsComplete(t *testing.T) {
	for _, provider := range All {
		if provider.url == "" || provider.headers == nil || provider.models == nil || provider.DefaultModel == "" || provider.KeyPage == "" {
			t.Errorf("%s is missing something", provider.ID)
		}
	}
}
