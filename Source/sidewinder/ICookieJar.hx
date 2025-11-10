package sidewinder;

import sidewinder.CookieJar.Cookie;

/**
 * Interface for cookie jar implementations.
 * Allows dependency injection and testing with mock implementations.
 */
interface ICookieJar {
    /**
     * Parse and store cookies from Set-Cookie header(s).
     * @param setCookieHeader The value of a Set-Cookie header
     * @param url The URL of the request (used to extract domain/path)
     */
    function setCookie(setCookieHeader:String, url:String):Void;
    
    /**
     * Get all cookies that match the given URL as a Cookie header string.
     * @param url The URL to match cookies against
     * @return Cookie header value (e.g., "name1=value1; name2=value2")
     */
    function getCookieHeader(url:String):String;
    
    /**
     * Get all stored cookies (for debugging).
     */
    function getAllCookies():Array<Cookie>;
    
    /**
     * Clear all cookies.
     */
    function clear():Void;
}
