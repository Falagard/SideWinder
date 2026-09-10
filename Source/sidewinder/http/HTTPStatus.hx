package sidewinder.http;

// SIDEWINDER-SNAKE-REMOVAL-S1.
//
// SideWinder's own HTTP status vocabulary, ported verbatim (code + message) from
// snake-server's `snake.http.HTTPStatus`, which was SideWinder's ONLY remaining
// use of that library across the reusable core -- 48 of 50 references, to a
// 341-line table of constants.
//
// The type name is deliberately unchanged so consuming code needs only an import
// swap (`snake.http.HTTPStatus` -> `sidewinder.http.HTTPStatus`), never a rename
// at the ~88 platform call sites.
class HTTPStatus {

	// informational

	public static final CONTINUE = new HTTPStatus(100, 'Continue');
	public static final SWITCHING_PROTOCOLS = new HTTPStatus(101, 'Switching Protocols');
	public static final PROCESSING = new HTTPStatus(102, 'Processing');
	public static final EARLY_HINTS = new HTTPStatus(103, 'Early Hints');

	// success

	public static final OK = new HTTPStatus(200, 'OK');
	public static final CREATED = new HTTPStatus(201, 'Created');
	public static final ACCEPTED = new HTTPStatus(202, 'Accepted');
	public static final NON_AUTHORITATIVE_INFORMATION = new HTTPStatus(203, 'Non-Authoritative Information');
	public static final NO_CONTENT = new HTTPStatus(204, 'No Content');
	public static final RESET_CONTENT = new HTTPStatus(205, 'Reset Content');
	public static final PARTIAL_CONTENT = new HTTPStatus(206, 'Partial Content');
	public static final MULTI_STATUS = new HTTPStatus(207, 'Multi-Status');
	public static final ALREADY_REPORTED = new HTTPStatus(208, 'Already Reported');
	public static final IM_USED = new HTTPStatus(226, 'IM Used');

	// redirection

	public static final MULTIPLE_CHOICES = new HTTPStatus(300, 'Multiple Choices');
	public static final MOVED_PERMANENTLY = new HTTPStatus(301, 'Moved Permanently');
	public static final FOUND = new HTTPStatus(302, 'Found');
	public static final SEE_OTHER = new HTTPStatus(303, 'See Other');
	public static final NOT_MODIFIED = new HTTPStatus(304, 'Not Modified');
	public static final USE_PROXY = new HTTPStatus(305, 'Use Proxy');
	public static final TEMPORARY_REDIRECT = new HTTPStatus(307, 'Temporary Redirect');
	public static final PERMANENT_REDIRECT = new HTTPStatus(308, 'Permanent Redirect');

	// client error

	public static final BAD_REQUEST = new HTTPStatus(400, 'Bad Request');
	public static final UNAUTHORIZED = new HTTPStatus(401, 'Unauthorized');
	public static final PAYMENT_REQUIRED = new HTTPStatus(402, 'Payment Required');
	public static final FORBIDDEN = new HTTPStatus(403, 'Forbidden');
	public static final NOT_FOUND = new HTTPStatus(404, 'Not Found');
	public static final METHOD_NOT_ALLOWED = new HTTPStatus(405, 'Method Not Allowed');
	public static final NOT_ACCEPTABLE = new HTTPStatus(406, 'Not Acceptable');
	public static final PROXY_AUTHENTICATION_REQUIRED = new HTTPStatus(407, 'Proxy Authentication Required');
	public static final REQUEST_TIMEOUT = new HTTPStatus(408, 'Request Timeout');
	public static final CONFLICT = new HTTPStatus(409, 'Conflict');
	public static final GONE = new HTTPStatus(410, 'Gone');
	public static final LENGTH_REQUIRED = new HTTPStatus(411, 'Length Required');
	public static final PRECONDITION_FAILED = new HTTPStatus(412, 'Precondition Failed');
	public static final REQUEST_ENTITY_TOO_LARGE = new HTTPStatus(413, 'Request Entity Too Large');
	public static final REQUEST_URI_TOO_LONG = new HTTPStatus(414, 'Request-URI Too Long');
	public static final UNSUPPORTED_MEDIA_TYPE = new HTTPStatus(415, 'Unsupported Media Type');
	public static final REQUESTED_RANGE_NOT_SATISFIABLE = new HTTPStatus(416, 'Requested Range Not Satisfiable');
	public static final EXPECTATION_FAILED = new HTTPStatus(417, 'Expectation Failed');
	public static final IM_A_TEAPOT = new HTTPStatus(418, 'I\'m a Teapot');
	public static final MISDIRECTED_REQUEST = new HTTPStatus(421, 'Misdirected Request');
	public static final UNPROCESSABLE_ENTITY = new HTTPStatus(422, 'Unprocessable Entity');
	public static final LOCKED = new HTTPStatus(423, 'Locked');
	public static final FAILED_DEPENDENCY = new HTTPStatus(424, 'Failed Dependency');
	public static final TOO_EARLY = new HTTPStatus(425, 'Too Early');
	public static final UPGRADE_REQUIRED = new HTTPStatus(426, 'Upgrade Required');
	public static final PRECONDITION_REQUIRED = new HTTPStatus(428, 'Precondition Required');
	public static final TOO_MANY_REQUESTS = new HTTPStatus(429, 'Too Many Requests');
	public static final REQUEST_HEADER_FIELDS_TOO_LARGE = new HTTPStatus(431, 'Request Header Fields Too Large');
	public static final UNAVAILABLE_FOR_LEGAL_REASONS = new HTTPStatus(451, 'Unavailable For Legal Reasons');

	// server error

	public static final INTERNAL_SERVER_ERROR = new HTTPStatus(500, 'Internal Server Error');
	public static final NOT_IMPLEMENTED = new HTTPStatus(501, 'Not Implemented');
	public static final BAD_GATEWAY = new HTTPStatus(502, 'Bad Gateway');
	public static final SERVICE_UNAVAILABLE = new HTTPStatus(503, 'Service Unavailable');
	public static final GATEWAY_TIMEOUT = new HTTPStatus(504, 'Gateway Timeout');
	public static final HTTP_VERSION_NOT_SUPPORTED = new HTTPStatus(505, 'HTTP Version Not Supported');
	public static final VARIANT_ALSO_NEGOTIATES = new HTTPStatus(506, 'Variant Also Negotiates');
	public static final INSUFFICIENT_STORAGE = new HTTPStatus(507, 'Insufficient Storage');
	public static final LOOP_DETECTED = new HTTPStatus(508, 'Loop Detected');
	public static final NOT_EXTENDED = new HTTPStatus(510, 'Not Extended');
	public static final NETWORK_AUTHENTICATION_REQUIRED = new HTTPStatus(511, 'Network Authentication Required');

	/** The numeric HTTP status code. */
	public var code:Int;

	/** The default message describing the HTTP status. */
	public var message:String;

	private function new(code:Int, message:String) {
		this.code = code;
		this.message = message;
	}
}
