vcl 4.1;
import std;
# Default backend definition
backend default {
    .host = "127.0.0.1";
    .port = "3000";  # Adjust to your Apostrophe port
    .connect_timeout = 600s;
    .first_byte_timeout = 600s;
    .between_bytes_timeout = 600s;
}
# ACL for purge requests
acl purge {
    "localhost";
    "127.0.0.1";
    # Add additional IPs if needed
}
sub vcl_recv {
    # Handle purge requests
    if (req.method == "PURGE" && req.url != "/purge-all-site-content") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed."));
        }
        ban("req.url == " + req.url);
        return (synth(200, "Purged " + req.url));
    }

    if (req.method == "PURGE" && req.url == "/purge-all-site-content") {
        # if (!client.ip ~ purge) {
        #     return (synth(405, "Not allowed."));
        # }

        # Ban everything
        ban("req.url ~ .");

        # Log the full site flush
        std.log("EMERGENCY: Full site cache flush executed");

        return (synth(200, "Purged entire site cache"));
    }

    # 1) Skip cache for admin, login, and API routes
    if (req.url ~ "(?i)^/api" ||
        req.url ~ "(?i)@apostrophecms" ||
        req.url ~ "(?i)/login" ||
        req.url ~ "(?i)/logout" ||
        req.url ~ "(?i)/admin" ||
        req.url ~ "(?i)/editor") {
        return (pass);
    }
    # 2) Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
    # 3) Skip cache for authenticated users
    if (req.http.Cookie &&
        req.http.Cookie ~ "$APP_NAME$.loggedIn=true") {
        return (pass);
    }
    # 4) For anonymous users, save cookies but don't use for cache key
    if (req.http.Cookie) {
        set req.http.X-Original-Cookie = req.http.Cookie;
        unset req.http.Cookie;
    }
    return (hash);
}
sub vcl_hash {
    hash_data(req.url);
    hash_data(req.http.host);
    return (lookup);
}
sub vcl_backend_fetch {
    # Restore cookies for backend request
    if (bereq.http.X-Original-Cookie) {
        set bereq.http.Cookie = bereq.http.X-Original-Cookie;
        unset bereq.http.X-Original-Cookie;
    }
    return (fetch);
}

sub vcl_backend_response {
    # Don't cache error responses
    if (beresp.status >= 500) {
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    # For authenticated users, don't cache
    if (beresp.http.Set-Cookie &&
        beresp.http.Set-Cookie ~ "$APP_NAME$.loggedIn=true" &&
        # lets still cache js and css
        beresp.http.Content-Type !~ "application/javascript" &&
        beresp.http.Content-Type !~ "text/css") {
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
        return (deliver);
    }

    # For dynamic HTML pages
    if (beresp.http.Content-Type ~ "text/html") {
        # Cache for 1 week - effectively "forever" in most content lifecycles
        # This will be cleared by purges when content changes
        set beresp.ttl = 1w;

        # Small grace period helps with traffic spikes but ensures purges work
        set beresp.grace = 2m;

        # Safety mechanism: add a header for tracking long-cached content
        set beresp.http.X-Cache-Generation = "long-term";

        # Add simple timestamp indicator instead of using std.time2str
        # Current time in epoch seconds (Unix timestamp)
        set beresp.http.X-Cached-At-Epoch = now;
    }
    else {
        # For static assets (CSS, JS, images, etc.)
        set beresp.ttl = 1w;  # Long caching for assets
        set beresp.grace = 1d;  # Long grace period for assets
    }

    # Save cookies but allow caching for non-authenticated requests
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Saved-Set-Cookie = beresp.http.Set-Cookie;
        unset beresp.http.Set-Cookie;
    }

    # Ensure proper validation headers are present
    if (!beresp.http.ETag) {
        set beresp.http.ETag = "W/" + std.random(1000, 9999);
    }

    # Add a unique identifier for this version (for debugging)
    set beresp.http.X-Version = std.random(1000000, 9999999);

    return (deliver);
}

sub vcl_deliver {
    # Restore cookies
    if (resp.http.X-Saved-Set-Cookie) {
        set resp.http.Set-Cookie = resp.http.X-Saved-Set-Cookie;
        unset resp.http.X-Saved-Set-Cookie;
    }

    # Add cache hit/miss info
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    return (deliver);
}

sub vcl_purge {
    return (restart);
}