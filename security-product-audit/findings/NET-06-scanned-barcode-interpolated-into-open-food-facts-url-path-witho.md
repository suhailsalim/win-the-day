# NET-06 — Scanned barcode interpolated into Open Food Facts URL path without percent-encoding

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Network & transport |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | transport |
| **Location(s)** | `WinTheDay/Core/AppStore.swift`, `WinTheDay/Food/FoodLookup.swift`, `WinTheDay/Food/BarcodeScanner.swift`, `WinTheDay/Food/CatalogView.swift` |

## Summary

AppStore.lookupBarcode interpolates the raw scanned barcode payload straight into the Open Food Facts product URL path with no percent-encoding, unlike the sibling FoodLookup.off search path which correctly encodes its term. The fixed scheme+host prefix limits impact to a malformed or failed read-only GET against openfoodfacts.org.

## Details

Confirmed at `WinTheDay/Core/AppStore.swift:1667-1673`:

```swift
func lookupBarcode(_ code: String, kind: CatalogKind) async -> CatalogItem? {
    let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_size"
    guard let url = URL(string: urlStr),
          let (d, _) = try? await URLSession.shared.data(from: url),
          ...
```

`code` is interpolated straight into the path with no `addingPercentEncoding`. This contrasts with the sibling lookup at `WinTheDay/Food/FoodLookup.swift:57`, which encodes its term:

```swift
let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&...")
```

So the reported inconsistency is real and correctly located.

One correction to the original report's reasoning about the input space. The report assumed "EAN/UPC symbologies constrain the value to digits." That is not guaranteed. The scanner is created at `WinTheDay/Food/BarcodeScanner.swift:14-15` with `recognizedDataTypes: [.barcode()]` and no symbology filter, so VisionKit's `DataScannerViewController` recognizes all supported symbologies — including 2D codes (QR, PDF417, Aztec, Code128) that can carry arbitrary UTF-8. The payload is taken verbatim (`code.payloadStringValue` → `parent.onScan(payload)`, `BarcodeScanner.swift:44-46`) and flows through `CatalogView.swift:166 → 328-330` into `lookupBarcode`. So the untrusted-content path (threat model c) is genuine and broader than the report implied — an attacker-crafted 2D barcode can contain `?`, `&`, `#`, `/`, etc.

What bounds the impact: the scheme and authority (`https://world.openfoodfacts.org`) are a fixed literal prefix that appears *before* the interpolation point. The attacker controls only the trailing path segment and query — they cannot introduce a new authority, so this is not SSRF and cannot redirect to an attacker-controlled host. `URLSession.shared` sends no credentials, auth header, or app cookies to OFF. Payloads containing a space cause `URL(string:)` to return `nil`, which the `guard` turns into a safe no-op (returns `nil`). The worst realistic outcome is a request to an arbitrary path/query on the read-only Open Food Facts host, whose response is parsed as product JSON — i.e. a failed or wrong product lookup. No data exfiltration, no state change (the result only pre-fills a catalog item the user must still save).

This is a legitimate defense-in-depth / code-consistency defect, not a security-impactful vulnerability.

## Failure / exploit scenario

Threat model (c), malicious content author. An attacker prints a QR code (the scanner accepts 2D symbologies, not just numeric EAN/UPC) encoding a payload such as `../../../cgi/nutrients` or `123?foo=bar#x`. The victim scans it while adding a food item. `lookupBarcode` builds `https://world.openfoodfacts.org/api/v2/product/<payload>.json?...` and issues a GET. Because the host prefix is fixed, the request still targets openfoodfacts.org over HTTPS with no credentials; the crafted path/query at most yields a failed lookup (guard returns nil) or an unrelated OFF JSON body that fails the `status == 1` check. There is no path to reach an attacker host, leak user data, or mutate app state — the barcode result only pre-populates a catalog draft the user must confirm.

## Impact

Practically none from a security standpoint. Under HTTPS to a fixed, read-only, credential-less host, the worst case is a malformed request that returns no product. The value of fixing it is code consistency (it already percent-encodes the sibling search path) and removing a latent footgun should the URL construction ever be refactored to include attacker-influenceable authority or additional endpoints.

## Recommendation

Percent-encode the barcode before interpolation to match the sibling search path and eliminate the theoretical path/query injection:

```swift
let enc = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(enc).json?fields=..."
```

Optionally, since Open Food Facts barcodes are numeric, defensively reject non-digit payloads before the request (`guard code.allSatisfy(\.isNumber)`), which also filters out arbitrary 2D-barcode payloads the unfiltered `.barcode()` scanner can produce.

## References

- CWE-116: Improper Encoding or Escaping of Output


---

_Finding NET-06. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._