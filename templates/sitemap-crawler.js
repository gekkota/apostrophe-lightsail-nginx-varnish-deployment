#!/usr/bin/env node
/**
 * Apostrophe CMS Sitemap Crawler for Pre-caching
 *
 * This script crawls a sitemap.xml file and visits all URLs to prime the cache.
 * It handles sitemap indexes, multiple sitemaps, and follows redirects safely.
 *
 * Usage: node crawler.js [baseUrl] [sitemapPath]
 * Example: node crawler.js https://example.com /sitemap.xml
 */

const fs = require('fs');
const https = require('https');
const http = require('http');
const url = require('url');

// Parse command line arguments
const baseUrl = process.argv[2] || 'http://localhost:81';
const sitemapPath = process.argv[3] || '/sitemap.xml';
const fullSitemapUrl = baseUrl + (sitemapPath.startsWith('/') ? sitemapPath : `/${sitemapPath}`);

// Configuration
const CONFIG = {
    maxRedirects: 5,            // Maximum number of redirects to follow
    requestTimeout: 30000,      // Request timeout in milliseconds (30 seconds)
    concurrentRequests: 3,      // Number of concurrent requests
    batchDelay: 1000,           // Delay between batches in milliseconds
    userAgent: 'Mozilla/5.0 AposCMSDeploymentCache/1.0',
    retryCount: 3,              // Number of times to retry failed requests
    retryDelay: 2000            // Delay between retries in milliseconds
};

// Logging with timestamps
function log(message, isError = false) {
    const timestamp = new Date().toISOString();
    const logMethod = isError ? console.error : console.log;
    logMethod(`[${timestamp}] ${message}`);
}

// Simple XML parser function (no dependencies required)
function parseSimpleXml(xmlString) {
    // Check for empty or malformed XML
    if (!xmlString || xmlString.trim() === '') {
        log('Warning: Empty XML content received', true);
        return { isSitemapIndex: false, urls: [] };
    }

    // This is a basic parser for sitemap XML that extracts URLs without needing xml2js
    const urls = [];
    const locRegex = /<loc>(.*?)<\/loc>/g;
    let match;

    // Extract all URLs from <loc> tags
    while ((match = locRegex.exec(xmlString)) !== null) {
        // Clean URL (trim whitespace, decode entities)
        let cleanUrl = match[1].trim()
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'");

        urls.push(cleanUrl);
    }

    // Check if this is a sitemap index
    if (xmlString.includes('<sitemapindex') && urls.length > 0) {
        log(`Found sitemap index with ${urls.length} sub-sitemaps`);
        return {
            isSitemapIndex: true,
            sitemapUrls: urls
        };
    }

    log(`Found ${urls.length} URLs in sitemap`);
    return {
        isSitemapIndex: false,
        urls: urls
    };
}

// Improved URL fetcher with retry and redirect handling
async function fetchUrl(urlToFetch, redirectCount = 0) {
    // Prevent redirect loops
    if (redirectCount > CONFIG.maxRedirects) {
        throw new Error(`Too many redirects (>${CONFIG.maxRedirects}) for ${urlToFetch}`);
    }

    // Parse the URL to handle both absolute and relative URLs
    let parsedUrl;
    try {
        parsedUrl = url.parse(urlToFetch);
    } catch (e) {
        log(`Invalid URL: ${urlToFetch}`, true);
        throw new Error(`Invalid URL: ${urlToFetch}`);
    }

    // For relative URLs, use the protocol and host from the base URL
    if (!parsedUrl.protocol) {
        urlToFetch = baseUrl + (urlToFetch.startsWith('/') ? '' : '/') + urlToFetch;
        log(`Converted relative URL to absolute: ${urlToFetch}`);
        parsedUrl = url.parse(urlToFetch);
    }

    // Determine which protocol to use based on the URL
    const urlProtocol = parsedUrl.protocol === 'https:' ? https : http;

    // Configure request options
    const options = {
        headers: {
            'User-Agent': CONFIG.userAgent,
            'Accept': 'text/html,application/xhtml+xml,application/xml',
            'Accept-Encoding': 'gzip, deflate'
        },
        timeout: CONFIG.requestTimeout
    };

    // Function to attempt the fetch with retries
    const attemptFetch = async (retryAttempt = 0) => {
        return new Promise((resolve, reject) => {
            log(`Fetching: ${urlToFetch}${retryAttempt > 0 ? ` (retry ${retryAttempt}/${CONFIG.retryCount})` : ''}`);

            const req = urlProtocol.get(urlToFetch, options, (res) => {
                // Handle redirects
                if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                    const redirectUrl = res.headers.location;
                    log(`Following redirect (${res.statusCode}) from ${urlToFetch} to: ${redirectUrl}`);
                    // Resolve with the result of following the redirect
                    resolve(fetchUrl(redirectUrl, redirectCount + 1));
                    return;
                }

                // Handle other non-200 responses
                if (res.statusCode !== 200) {
                    const error = new Error(`Status Code: ${res.statusCode} for ${urlToFetch}`);
                    error.statusCode = res.statusCode;
                    reject(error);
                    return;
                }

                // Collect response data
                const data = [];
                res.on('data', (chunk) => {
                    data.push(chunk);
                });

                res.on('end', () => {
                    try {
                        const responseData = Buffer.concat(data).toString();
                        log(`Successfully fetched: ${urlToFetch} (${responseData.length} bytes)`);
                        resolve(responseData);
                    } catch (e) {
                        reject(new Error(`Error processing response: ${e.message}`));
                    }
                });
            });

            req.on('error', (e) => {
                reject(e);
            });

            req.on('timeout', () => {
                req.destroy();
                reject(new Error(`Request timed out for ${urlToFetch}`));
            });
        });
    };

    // Implement retry logic
    let lastError;
    for (let retryAttempt = 0; retryAttempt <= CONFIG.retryCount; retryAttempt++) {
        try {
            if (retryAttempt > 0) {
                // Wait before retry
                await new Promise(resolve => setTimeout(resolve, CONFIG.retryDelay));
            }
            return await attemptFetch(retryAttempt);
        } catch (error) {
            lastError = error;
            // Don't log for the last attempt as the error will be thrown
            if (retryAttempt < CONFIG.retryCount) {
                log(`Error fetching ${urlToFetch} (attempt ${retryAttempt + 1}/${CONFIG.retryCount + 1}): ${error.message}`, true);
            }
        }
    }

    // If we get here, all retries failed
    throw lastError;
}

// Function to process a sitemap URL
async function processSitemap(sitemapUrl) {
    try {
        log(`Processing sitemap: ${sitemapUrl}`);
        const sitemapXml = await fetchUrl(sitemapUrl);
        const parsedData = parseSimpleXml(sitemapXml);

        if (parsedData.isSitemapIndex) {
            // This is a sitemap index, process each sub-sitemap
            let allUrls = [];
            for (const subSitemapUrl of parsedData.sitemapUrls) {
                try {
                    const subUrls = await processSitemap(subSitemapUrl);
                    allUrls = allUrls.concat(subUrls);
                } catch (err) {
                    log(`Error processing sub-sitemap ${subSitemapUrl}: ${err.message}`, true);
                }
            }
            return allUrls;
        } else {
            // This is a regular sitemap, return the URLs
            return parsedData.urls;
        }
    } catch (error) {
        log(`Error processing sitemap ${sitemapUrl}: ${error.message}`, true);

        // Try a basic connection test
        try {
            log(`Testing connection to ${sitemapUrl} without parsing...`);
            await fetchUrl(sitemapUrl);
            log(`Connection to ${sitemapUrl} successful, but XML parsing failed`);
        } catch (e) {
            log(`Connection test to ${sitemapUrl} also failed: ${e.message}`, true);
        }

        return [];
    }
}

// Perform a connectivity test before starting
async function testConnection() {
    try {
        log(`Testing connectivity to: ${baseUrl}`);
        await fetchUrl(baseUrl);
        log(`Base URL connectivity test successful`);
        return true;
    } catch (e) {
        log(`Initial connectivity test failed: ${e.message}`, true);
        return false;
    }
}

async function crawlSitemap() {
    log('========================================');
    log(`Starting sitemap crawl for: ${fullSitemapUrl}`);
    log('========================================');

    try {
        // First test connectivity
        const connectionOk = await testConnection();
        if (!connectionOk) {
            log('WARNING: Initial connectivity test failed. Will try to continue anyway.', true);
        }

        // Process the sitemap
        const urls = await processSitemap(fullSitemapUrl);

        if (urls.length === 0) {
            log('No URLs found to crawl. Sitemap may be empty or inaccessible.', true);
            return;
        }

        log(`Found total of ${urls.length} URLs to crawl`);

        // Crawl each URL to prime the cache
        let successCount = 0;
        let failCount = 0;

        // Process URLs in batches to limit concurrency
        for (let i = 0; i < urls.length; i += CONFIG.concurrentRequests) {
            const batch = urls.slice(i, i + CONFIG.concurrentRequests);
            log(`Processing batch ${Math.floor(i/CONFIG.concurrentRequests) + 1}/${Math.ceil(urls.length/CONFIG.concurrentRequests)} (${batch.length} URLs)`);

            const promises = batch.map(async (pageUrl, index) => {
                try {
                    log(`[${i + index + 1}/${urls.length}] Crawling: ${pageUrl}`);
                    await fetchUrl(pageUrl);
                    log(`✓ Success: ${pageUrl}`);
                    return true;
                } catch (err) {
                    log(`✗ Failed to fetch ${pageUrl}: ${err.message}`, true);
                    return false;
                }
            });

            const results = await Promise.all(promises);
            successCount += results.filter(Boolean).length;
            failCount += results.filter(r => !r).length;

            // Small delay between batches to avoid overwhelming the server
            if (i + CONFIG.concurrentRequests < urls.length) {
                await new Promise(resolve => setTimeout(resolve, CONFIG.batchDelay));
            }
        }

        log('========================================');
        log(`Crawl completed. Success: ${successCount}, Failed: ${failCount}`);
        log('========================================');
    } catch (error) {
        log(`Fatal error crawling sitemap: ${error.message}`, true);
        log('Crawl process terminated abnormally');
        process.exit(1);
    }
}

// Start the crawl
crawlSitemap().catch(err => {
    log(`Unhandled error: ${err.message}`, true);
    process.exit(1);
});