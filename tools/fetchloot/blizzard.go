package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	apiBase   = "https://us.api.blizzard.com"
	tokenURL  = "https://oauth.battle.net/token"
	namespace = "static-us"
	locale    = "en_US"

	// Client ID for the SpecLoot data-fetcher Battle.net app. Not a secret.
	clientID = "006a330ae62f4a2bbae7b794443e86a3"
)

type Client struct {
	http  *http.Client
	token string
}

func NewClient(clientID, clientSecret string) (*Client, error) {
	body := strings.NewReader("grant_type=client_credentials")
	req, err := http.NewRequest("POST", tokenURL, body)
	if err != nil {
		return nil, err
	}
	auth := base64.StdEncoding.EncodeToString([]byte(clientID + ":" + clientSecret))
	req.Header.Set("Authorization", "Basic "+auth)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	httpc := &http.Client{Timeout: 30 * time.Second}
	resp, err := httpc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("token request failed: %d %s", resp.StatusCode, string(b))
	}
	var t struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&t); err != nil {
		return nil, err
	}
	return &Client{http: httpc, token: t.AccessToken}, nil
}

func (c *Client) get(path string, out interface{}) error {
	body, err := c.getRaw(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, out)
}

// getRaw fetches a Blizzard API path and returns the raw response bytes.
// Useful for inspection commands that pretty-print the full JSON body.
func (c *Client) GetRaw(path string) ([]byte, error) { return c.getRaw(path) }

func (c *Client) getRaw(path string) ([]byte, error) {
	sep := "?"
	if strings.Contains(path, "?") {
		sep = "&"
	}
	u := apiBase + path + sep + "namespace=" + namespace + "&locale=" + locale
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("%s: status %d body=%s", path, resp.StatusCode, string(body))
	}
	return body, nil
}

// --- Journal Instance ---

type JournalInstance struct {
	ID         int                          `json:"id"`
	Name       string                       `json:"name"`
	Encounters []JournalInstanceEncounterRef `json:"encounters"`
	Category   struct {
		Type string `json:"type"`
	} `json:"category"`
	Expansion struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
	} `json:"expansion"`
}

type JournalInstanceEncounterRef struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

func (c *Client) GetInstance(id int) (*JournalInstance, error) {
	var out JournalInstance
	if err := c.get(fmt.Sprintf("/data/wow/journal-instance/%d", id), &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Journal Instance Index ---

type JournalInstanceIndex struct {
	Instances []struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
	} `json:"instances"`
}

func (c *Client) GetInstanceIndex() (*JournalInstanceIndex, error) {
	var out JournalInstanceIndex
	if err := c.get("/data/wow/journal-instance/index", &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// FindInstanceIDByName returns the journal-instance ID whose name matches
// (case-insensitive) the given exact name. If multiple instances share the
// name (e.g. an old expansion's dungeon and its modernized re-release), it
// returns an error listing all candidate IDs so the caller can disambiguate
// rather than silently picking the wrong one.
func (c *Client) FindInstanceIDByName(name string) (int, error) {
	idx, err := c.GetInstanceIndex()
	if err != nil {
		return 0, err
	}
	want := strings.ToLower(name)
	var matches []int
	for _, e := range idx.Instances {
		if strings.ToLower(e.Name) == want {
			matches = append(matches, e.ID)
		}
	}
	switch len(matches) {
	case 0:
		return 0, fmt.Errorf("no journal-instance named %q in index (have %d entries)", name, len(idx.Instances))
	case 1:
		return matches[0], nil
	default:
		return 0, fmt.Errorf("name %q matches multiple journal-instances %v — set journalInstanceId by hand to disambiguate", name, matches)
	}
}

// FindInstancesByPattern returns all instances whose name contains the given
// substring (case-insensitive). Useful for ad-hoc lookups when you don't know
// the exact name (e.g. "voidspire" matching "The Voidspire").
func (c *Client) FindInstancesByPattern(pattern string) ([]struct {
	ID   int
	Name string
}, error) {
	idx, err := c.GetInstanceIndex()
	if err != nil {
		return nil, err
	}
	needle := strings.ToLower(pattern)
	var out []struct {
		ID   int
		Name string
	}
	for _, e := range idx.Instances {
		if strings.Contains(strings.ToLower(e.Name), needle) {
			out = append(out, struct {
				ID   int
				Name string
			}{e.ID, e.Name})
		}
	}
	return out, nil
}

// --- Journal Encounter ---

type JournalEncounter struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Items []struct {
		Item struct {
			ID   int    `json:"id"`
			Name string `json:"name"`
		} `json:"item"`
	} `json:"items"`
}

func (c *Client) GetEncounter(id int) (*JournalEncounter, error) {
	var out JournalEncounter
	if err := c.get(fmt.Sprintf("/data/wow/journal-encounter/%d", id), &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Item ---

type Item struct {
	ID            int    `json:"id"`
	Name          string `json:"name"`
	Quality       NameType `json:"quality"`
	InventoryType NameType `json:"inventory_type"`
	ItemClass     IDName   `json:"item_class"`
	ItemSubclass  IDName   `json:"item_subclass"`
	PreviewItem   struct {
		Stats []struct {
			Type    NameType `json:"type"`
			IsNegated bool   `json:"is_negated"`
		} `json:"stats"`
	} `json:"preview_item"`
}

type NameType struct {
	Type string `json:"type"`
	Name string `json:"name"`
}

type IDName struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

func (c *Client) GetItem(id int) (*Item, error) {
	var out Item
	if err := c.get(fmt.Sprintf("/data/wow/item/%d", id), &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// --- Item Media (icon) ---

type ItemMedia struct {
	Assets []struct {
		Key   string `json:"key"`
		Value string `json:"value"`
	} `json:"assets"`
}

func (c *Client) GetItemMedia(id int) (*ItemMedia, error) {
	var out ItemMedia
	if err := c.get(fmt.Sprintf("/data/wow/media/item/%d", id), &out); err != nil {
		return nil, err
	}
	return &out, nil
}
