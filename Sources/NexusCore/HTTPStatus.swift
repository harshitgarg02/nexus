import Foundation

public struct HTTPStatus: Equatable {
    public let code: Int
    public let name: String
    public let meaning: String

    public var category: String {
        switch code / 100 {
        case 1: return "Informational"
        case 2: return "Success"
        case 3: return "Redirection"
        case 4: return "Client error"
        default: return "Server error"
        }
    }

    // code | name | meaning
    private static let table = """
    100|Continue|The client should continue with the request.
    101|Switching Protocols|The server is switching to the protocol named in Upgrade.
    102|Processing|WebDAV: the request was received and is still being processed.
    103|Early Hints|Preload hints sent before the final response.
    200|OK|The request succeeded.
    201|Created|A new resource was created.
    202|Accepted|Accepted for processing, which isn't finished yet.
    203|Non-Authoritative Information|A proxy changed the origin's response.
    204|No Content|Success, with no response body.
    205|Reset Content|Success; the client should reset its form or view.
    206|Partial Content|Only part of the resource was returned (range request).
    207|Multi-Status|WebDAV: several status codes are in the body.
    208|Already Reported|WebDAV: members were already listed earlier.
    226|IM Used|The response is a delta-encoded instance.
    300|Multiple Choices|Several representations are available.
    301|Moved Permanently|The resource has a new permanent URL.
    302|Found|Temporary redirect to another URL.
    303|See Other|Fetch the result with GET at another URL.
    304|Not Modified|Your cached copy is still valid.
    307|Temporary Redirect|Repeat the same request, same method, at another URL.
    308|Permanent Redirect|Permanent redirect that keeps the method.
    400|Bad Request|Malformed request the server can't process.
    401|Unauthorized|Authentication is required or failed.
    402|Payment Required|Reserved; sometimes used for paywalls or quotas.
    403|Forbidden|Understood but refused. Authenticating again won't help.
    404|Not Found|There is no resource at this URL.
    405|Method Not Allowed|The method isn't supported for this resource.
    406|Not Acceptable|Can't produce a response matching the Accept headers.
    407|Proxy Authentication Required|The proxy needs credentials first.
    408|Request Timeout|The server gave up waiting for the request.
    409|Conflict|Conflicts with the current state of the resource.
    410|Gone|Permanently removed, with no forwarding address.
    411|Length Required|A Content-Length header is required.
    412|Precondition Failed|A precondition header such as If-Match evaluated false.
    413|Content Too Large|The request body exceeds what the server accepts.
    414|URI Too Long|The URL is longer than the server will process.
    415|Unsupported Media Type|The Content-Type isn't supported.
    416|Range Not Satisfiable|The requested byte range is outside the resource.
    417|Expectation Failed|The Expect header can't be met.
    418|I'm a Teapot|April Fools' joke (RFC 2324): a teapot refuses to brew coffee.
    421|Misdirected Request|Sent to a server that can't produce a response for this host.
    422|Unprocessable Content|Well-formed but semantically invalid, usually validation errors.
    423|Locked|WebDAV: the resource is locked.
    424|Failed Dependency|WebDAV: failed because an earlier request failed.
    425|Too Early|The server won't risk processing a replayable request.
    426|Upgrade Required|The client must switch to another protocol.
    428|Precondition Required|The request must be conditional (If-Match…).
    429|Too Many Requests|Rate limited. Check the Retry-After header.
    431|Request Header Fields Too Large|The headers are too big.
    451|Unavailable For Legal Reasons|Blocked for legal reasons.
    500|Internal Server Error|A generic server-side failure.
    501|Not Implemented|The server doesn't support this functionality.
    502|Bad Gateway|An upstream server sent an invalid response.
    503|Service Unavailable|Overloaded or down for maintenance.
    504|Gateway Timeout|An upstream server didn't answer in time.
    505|HTTP Version Not Supported|The HTTP version isn't supported.
    506|Variant Also Negotiates|A configuration error in content negotiation.
    507|Insufficient Storage|WebDAV: the server is out of storage.
    508|Loop Detected|WebDAV: an infinite loop was detected.
    510|Not Extended|Further extensions to the request are required.
    511|Network Authentication Required|The client must authenticate to get network access.
    """

    public static let all: [HTTPStatus] = table.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3, let c = Int(p[0]) else { return nil }
        return HTTPStatus(code: c, name: p[1], meaning: p[2])
    }

    /// "404" → that code; "4xx" or "4" → the whole class; anything else → name/meaning search.
    public static func lookup(_ query: String) -> [HTTPStatus] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if q.count == 3, let c = Int(q) { return all.filter { $0.code == c } }
        if q.count == 3, q.hasSuffix("xx"), let d = Int(q.prefix(1)) { return all.filter { $0.code / 100 == d } }
        if q.count == 1, let d = Int(q) { return all.filter { $0.code / 100 == d } }
        let words = q.split(separator: " ").map(String.init)
        return all.filter { s in
            let hay = (s.name + " " + s.meaning).lowercased().replacingOccurrences(of: "'", with: "")
            return words.allSatisfy { hay.contains($0.replacingOccurrences(of: "'", with: "")) }
        }
    }
}
