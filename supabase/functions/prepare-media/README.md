# Local photo inspection

The Edge function authenticates the caller through Supabase Auth, downloads only the caller's
immutable upload-attempt path, inspects JPEG markers/dimensions/size, rejects APP1/APP13/COM
and unknown application metadata, fully decodes with bounded memory, and computes SHA256.
Only its server credential can finalize measured media; mobile clients cannot bypass inspection.
Decoded pixels are discarded. Uploaded bytes remain unchanged, preserving client metadata removal.

Dependency: `jpeg-js` **0.4.4**, pinned in `deno.json`. The decoder derives from jpgjs under
Apache-2.0; its test encoder carries Adobe's redistribution terms. The npm distribution retains
the notices. Primary sources: [versioned README and license notices](https://github.com/jpeg-js/jpeg-js/blob/v0.4.4/README.md),
[package license](https://github.com/jpeg-js/jpeg-js/blob/v0.4.4/LICENSE).
Decode limits: 4.2 megapixels, 128 MiB estimated allocation, strict decoding; frame headers are
checked for a maximum side of 2,048 before decoding. Encoded uploads cannot exceed 3 MiB.

Lead commands (local only): `supabase functions serve prepare-media`; `deno task test` from this
directory. Deno should generate its resolution lock during the lead's first dependency resolution;
no fabricated lock hashes are checked in. Runtime Supabase credentials remain server environment
variables; no secrets belong in source or mobile configuration.
