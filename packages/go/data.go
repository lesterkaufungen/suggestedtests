package suggestedtests

import (
	crand "crypto/rand"
	"encoding/binary"
	"fmt"
	"math/bits"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

// Alphanumeric is the default alphabet of TestData.String.
const Alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

const lowercase = "abcdefghijklmnopqrstuvwxyz"

var words = []string{
	"alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
	"juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
	"sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
}

// SeedEnvVar fixes the seed of every TestData returned by Data.
const SeedEnvVar = "SUGGESTEDTESTS_SEED"

// TestData generates seeded random test data (xoshiro256**). The same seed
// produces the same values on every platform and Go version, so a failing
// test can be reproduced exactly. It is not safe for concurrent use.
//
// Methods panic on invalid arguments (e.g. max < min), like math/rand.
type TestData struct {
	seed uint64
	s    [4]uint64
}

// NewTestData returns a generator for seed.
func NewTestData(seed uint64) *TestData {
	d := &TestData{seed: seed}
	x := seed
	for i := range d.s { // splitmix64 seeding
		x += 0x9e3779b97f4a7c15
		z := x
		z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9
		z = (z ^ (z >> 27)) * 0x94d049bb133111eb
		d.s[i] = z ^ (z >> 31)
	}
	return d
}

// RandomTestData returns a generator with a random seed; read Seed to
// reproduce it.
func RandomTestData() *TestData {
	var b [8]byte
	if _, err := crand.Read(b[:]); err != nil {
		return NewTestData(uint64(time.Now().UnixNano()))
	}
	return NewTestData(binary.LittleEndian.Uint64(b[:]) >> 33) // short seeds are easier to copy
}

// Data returns a TestData seeded randomly per test, or from
// $SUGGESTEDTESTS_SEED. If the test fails, the seed is logged with the
// command to reproduce it.
//
//	func TestSignup(t *testing.T) {
//		d := st.Data(t)
//		if err := signup(d.Email()); err != nil { t.Fatal(err) }
//	}
func Data(t testing.TB) *TestData {
	t.Helper()
	var d *TestData
	if env := os.Getenv(SeedEnvVar); env != "" {
		seed, err := strconv.ParseUint(strings.TrimSpace(env), 10, 64)
		if err != nil {
			t.Fatalf("suggestedtests: $%s must be an unsigned integer, got %q", SeedEnvVar, env)
		}
		d = NewTestData(seed)
	} else {
		d = RandomTestData()
	}
	t.Cleanup(func() {
		if t.Failed() {
			t.Logf("TestData seed: %d (reproduce with %s=%d go test -run '^%s$')", d.seed, SeedEnvVar, d.seed, t.Name())
		}
	})
	return d
}

// Seed returns the seed the generator was created with.
func (d *TestData) Seed() uint64 { return d.seed }

// Uint64 returns 64 random bits.
func (d *TestData) Uint64() uint64 {
	s := &d.s
	result := bits.RotateLeft64(s[1]*5, 7) * 9
	t := s[1] << 17
	s[2] ^= s[0]
	s[3] ^= s[1]
	s[1] ^= s[2]
	s[0] ^= s[3]
	s[2] ^= t
	s[3] = bits.RotateLeft64(s[3], 45)
	return result
}

// below returns an unbiased value in [0, n); n > 0.
func (d *TestData) below(n uint64) uint64 {
	threshold := -n % n
	for {
		if r := d.Uint64(); r >= threshold {
			return r % n
		}
	}
}

// Int returns an integer in [min, max] (inclusive).
func (d *TestData) Int(min, max int) int {
	if max < min {
		panic(fmt.Sprintf("suggestedtests: TestData.Int: max (%d) < min (%d)", max, min))
	}
	span := uint64(max) - uint64(min) + 1
	if span == 0 { // the full 64-bit range
		return int(d.Uint64())
	}
	return min + int(d.below(span))
}

// Float returns a float64 in [min, max).
func (d *TestData) Float(min, max float64) float64 {
	if max < min {
		panic(fmt.Sprintf("suggestedtests: TestData.Float: max (%g) < min (%g)", max, min))
	}
	return min + float64(d.Uint64()>>11)/(1<<53)*(max-min)
}

// Bool returns true with the given probability, in [0, 1].
func (d *TestData) Bool(probability float64) bool {
	if !(probability >= 0 && probability <= 1) {
		panic(fmt.Sprintf("suggestedtests: TestData.Bool: probability must be in [0, 1], got %g", probability))
	}
	return float64(d.Uint64()>>11)/(1<<53) < probability
}

// String returns n characters (runes) drawn from alphabet; "" means
// Alphanumeric.
func (d *TestData) String(n int, alphabet string) string {
	if n < 0 {
		panic(fmt.Sprintf("suggestedtests: TestData.String: n must be >= 0, got %d", n))
	}
	if alphabet == "" {
		alphabet = Alphanumeric
	}
	runes := []rune(alphabet)
	if !utf8.ValidString(alphabet) {
		panic("suggestedtests: TestData.String: alphabet must be valid UTF-8")
	}
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteRune(runes[d.below(uint64(len(runes)))])
	}
	return b.String()
}

// Word returns a short lowercase word.
func (d *TestData) Word() string { return Pick(d, words) }

// Sentence returns n words, capitalised and ending with a period.
func (d *TestData) Sentence(n int) string {
	if n < 1 {
		panic(fmt.Sprintf("suggestedtests: TestData.Sentence: n must be >= 1, got %d", n))
	}
	ws := make([]string, n)
	for i := range ws {
		ws[i] = d.Word()
	}
	s := strings.Join(ws, " ")
	return strings.ToUpper(s[:1]) + s[1:] + "."
}

// Email returns a syntactically valid address on the reserved example.com domain.
func (d *TestData) Email() string {
	return d.Word() + "." + d.String(5, lowercase) + "@example.com"
}

// UUID returns a version 4 UUID string.
func (d *TestData) UUID() string {
	var b [16]byte
	binary.BigEndian.PutUint64(b[:8], d.Uint64())
	binary.BigEndian.PutUint64(b[8:], d.Uint64())
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// Time returns a UTC time in [from, to), at microsecond precision. Zero
// values default to 2000-01-01 and 2030-01-01.
func (d *TestData) Time(from, to time.Time) time.Time {
	if from.IsZero() {
		from = time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	}
	if to.IsZero() {
		to = time.Date(2030, 1, 1, 0, 0, 0, 0, time.UTC)
	}
	if to.Before(from) {
		panic("suggestedtests: TestData.Time: to is before from")
	}
	span := to.Sub(from).Microseconds()
	if span == 0 {
		return from.UTC()
	}
	return from.Add(time.Duration(d.below(uint64(span))) * time.Microsecond).UTC()
}

// Pick returns a random element of options, which must not be empty.
func Pick[T any](d *TestData, options []T) T {
	if len(options) == 0 {
		panic("suggestedtests: Pick: options must not be empty")
	}
	return options[d.below(uint64(len(options)))]
}

// ListOf returns n values produced by generate.
func ListOf[T any](d *TestData, n int, generate func(*TestData) T) []T {
	if n < 0 {
		panic(fmt.Sprintf("suggestedtests: ListOf: n must be >= 0, got %d", n))
	}
	out := make([]T, n)
	for i := range out {
		out[i] = generate(d)
	}
	return out
}

// Shuffled returns a shuffled copy of items (Fisher-Yates).
func Shuffled[T any](d *TestData, items []T) []T {
	out := append([]T(nil), items...)
	for i := len(out) - 1; i > 0; i-- {
		j := int(d.below(uint64(i + 1)))
		out[i], out[j] = out[j], out[i]
	}
	return out
}
