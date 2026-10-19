module github.com/lesterkaufungen/suggestedtests/packages/go

// The oldest Go that generics, embed and purego v0.10 support. Keep it here:
// don't use newer standard library APIs (min/max, slices, maps, math/rand/v2,
// errors.Join, sync.OnceValue, atomic.Int64, ...). CI tests Go 1.18 and stable.
go 1.18

require github.com/ebitengine/purego v0.10.2
